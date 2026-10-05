/'
    Project: OpenSesh
    ---------------------------

    File: soundfont_bank.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements soundfont_bank.bi; declarations there define the shared interface.

    Purpose:

        Read a SoundFont 2 bank and resolve its preset graph for native voices.

    Responsibilities:

        - validate RIFF, INFO, sample-data, and Hydra chunk boundaries
        - reject malformed counts, indexes, sample links, and allocations
        - preserve the previous bank when a replacement cannot be loaded
        - combine preset and instrument global and local generator zones
        - translate supported SF2 generators into safe playback regions

    This file intentionally does NOT contain:

        - a realtime voice mixer
        - an audio-output dependency
        - file dialogs or application-global settings

    Resource ownership:

        The active bank owns every Hydra table and the decoded sample buffer.
        Loading is transactional: a temporary bank owns all allocations until
        validation succeeds, then replaces the old bank in one operation.
        Clear and shutdown release those allocations. The synth stops its
        output worker before either operation, so active voices never retain
        pointers into a bank being replaced.
'/

#lang "fb"

#include once "soundfont_bank.bi"
#include once "binary_file_internal.bi"

Const SOUNDFONT_BANK_MAX_FILE_BYTES As ULongInt = 1073741824
Const SOUNDFONT_BANK_MAX_TABLE_RECORDS As Integer = 1048576
Const SOUNDFONT_BANK_SAMPLE_HEADER_MONO As Integer = 1
Const SOUNDFONT_BANK_SAMPLE_HEADER_RIGHT As Integer = 2
Const SOUNDFONT_BANK_SAMPLE_HEADER_LEFT As Integer = 4
Const SOUNDFONT_BANK_SAMPLE_HEADER_LINKED As Integer = 8
Const SOUNDFONT_BANK_SAMPLE_HEADER_ROM As Integer = &H8000
Const SF2_COARSE_SAMPLE_STEP As LongInt = 32768
Const SF2_PAN_LIMIT As Integer = 500
Const SF2_MAX_ATTENUATION_CENTIBELS As Integer = 1440

' Fixed record sizes from section 7 of the SF2.04 specification.
Const SF2_PRESET_HEADER_RECORD_BYTES As Integer = 38
Const SF2_BAG_RECORD_BYTES As Integer = 4
Const SF2_GENERATOR_RECORD_BYTES As Integer = 4
Const SF2_INSTRUMENT_HEADER_RECORD_BYTES As Integer = 22
Const SF2_SAMPLE_HEADER_RECORD_BYTES As Integer = 46
Const SF2_MODULATOR_RECORD_BYTES As Integer = 10
Const SF2_FIXED_NAME_BYTES As Integer = 20

' Byte offsets inside fixed Hydra records. File helpers accept zero-based offsets.
Const SF2_PRESET_PROGRAM_OFFSET As Integer = 20
Const SF2_PRESET_BANK_OFFSET As Integer = 22
Const SF2_PRESET_BAG_OFFSET As Integer = 24
Const SF2_INSTRUMENT_BAG_OFFSET As Integer = 20
Const SF2_SAMPLE_START_OFFSET As Integer = 20
Const SF2_SAMPLE_END_OFFSET As Integer = 24
Const SF2_SAMPLE_LOOP_START_OFFSET As Integer = 28
Const SF2_SAMPLE_LOOP_END_OFFSET As Integer = 32
Const SF2_SAMPLE_RATE_OFFSET As Integer = 36
Const SF2_SAMPLE_ORIGINAL_PITCH_OFFSET As Integer = 40
Const SF2_SAMPLE_PITCH_CORRECTION_OFFSET As Integer = 41
Const SF2_SAMPLE_LINK_OFFSET As Integer = 42
Const SF2_SAMPLE_TYPE_OFFSET As Integer = 44

' SoundFont generator operator numbers from section 8.1 of the SF2.04
' specification. Names are kept local because callers work with resolved data.
Const SF2_GEN_START_OFFSET As Integer = 0
Const SF2_GEN_END_OFFSET As Integer = 1
Const SF2_GEN_LOOP_START_OFFSET As Integer = 2
Const SF2_GEN_LOOP_END_OFFSET As Integer = 3
Const SF2_GEN_START_COARSE_OFFSET As Integer = 4
Const SF2_GEN_PAN As Integer = 17
Const SF2_GEN_ATTACK_VOLUME As Integer = 34
Const SF2_GEN_HOLD_VOLUME As Integer = 35
Const SF2_GEN_DECAY_VOLUME As Integer = 36
Const SF2_GEN_SUSTAIN_VOLUME As Integer = 37
Const SF2_GEN_RELEASE_VOLUME As Integer = 38
Const SF2_GEN_INSTRUMENT As Integer = 41
Const SF2_GEN_KEY_RANGE As Integer = 43
Const SF2_GEN_VELOCITY_RANGE As Integer = 44
Const SF2_GEN_LOOP_START_COARSE_OFFSET As Integer = 45
Const SF2_GEN_KEY_NUMBER As Integer = 46
Const SF2_GEN_VELOCITY As Integer = 47
Const SF2_GEN_INITIAL_ATTENUATION As Integer = 48
Const SF2_GEN_END_COARSE_OFFSET As Integer = 12
Const SF2_GEN_COARSE_TUNE As Integer = 51
Const SF2_GEN_FINE_TUNE As Integer = 52
Const SF2_GEN_SAMPLE_ID As Integer = 53
Const SF2_GEN_SAMPLE_MODES As Integer = 54
Const SF2_GEN_SCALE_TUNING As Integer = 56
Const SF2_GEN_EXCLUSIVE_CLASS As Integer = 57
Const SF2_GEN_OVERRIDING_ROOT_KEY As Integer = 58
Const SF2_GEN_LOOP_END_COARSE_OFFSET As Integer = 50

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type SoundFontPresetHeader
    As String name
    As UShort programNumber
    As UShort bankNumber
    As UShort bagIndex
End Type

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type SoundFontBag
    As UShort generatorIndex
    As UShort modulatorIndex
End Type

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type SoundFontGenerator
    As UShort operatorNumber
    As UShort amount
End Type

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type SoundFontInstrumentHeader
    As String name
    As UShort bagIndex
End Type

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type SoundFontSampleHeader
    As String name
    As ULong startPoint
    As ULong endPoint
    As ULong loopStart
    As ULong loopEnd
    As ULong sampleRate
    As UByte originalPitch
    As Byte pitchCorrection
    As UShort sampleLink
    As UShort sampleType
End Type

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type SoundFontChunkLocation
    As ULongInt offset
    As ULongInt length
    As Integer found
End Type

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type SoundFontGeneratorState
    As Integer keyLow
    As Integer keyHigh
    As Integer velocityLow
    As Integer velocityHigh
    As Integer instrumentIndex
    As Integer sampleIndex
    As Integer forcedKey
    As Integer forcedVelocity
    As LongInt startOffset
    As LongInt endOffset
    As LongInt loopStartOffset
    As LongInt loopEndOffset
    As LongInt startCoarseOffset
    As LongInt endCoarseOffset
    As LongInt loopStartCoarseOffset
    As LongInt loopEndCoarseOffset
    As Integer pan
    As Integer attackTimecents
    As Integer holdTimecents
    As Integer decayTimecents
    As Integer sustainCentibels
    As Integer releaseTimecents
    As Integer attenuationCentibels
    As Integer coarseTune
    As Integer fineTune
    As Integer sampleModes
    As Integer scaleTuning
    As Integer exclusiveClass
    As Integer overridingRootKey
End Type

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type SoundFontBankStorage
    As String filename
    As String bankName
    As Short Ptr sampleData
    As ULongInt samplePointCount
    As SoundFontPresetHeader Ptr presets
    As Integer presetCount
    As SoundFontBag Ptr presetBags
    As Integer presetBagCount
    As SoundFontGenerator Ptr presetGenerators
    As Integer presetGeneratorCount
    As SoundFontInstrumentHeader Ptr instruments
    As Integer instrumentCount
    As SoundFontBag Ptr instrumentBags
    As Integer instrumentBagCount
    As SoundFontGenerator Ptr instrumentGenerators
    As Integer instrumentGeneratorCount
    As SoundFontSampleHeader Ptr sampleHeaders
    As Integer sampleHeaderCount
End Type

' fblint: disable-next-line FBL301 REASON: this module owns the one selected immutable bank.
Dim Shared soundfontBank_Active As SoundFontBankStorage

' -------------------------------------------------------------------------
' Bounded binary helpers
' -------------------------------------------------------------------------

Private Function soundfontBank_HasBytes( _
    ByVal offset As ULongInt, _
    ByVal byteCount As ULongInt, _
    ByVal limit As ULongInt _
) As Integer
    If offset > limit OrElse byteCount > limit - offset Then
        Return 0
    End If
    Return -1
End Function


Private Function soundfontBank_ReadText( _
    ByVal fileNumber As Integer, _
    ByVal offset As ULongInt, _
    ByVal byteCount As Integer, _
    ByVal limit As ULongInt, _
    ByRef resultText As String _
) As Integer
    resultText = ""
    If byteCount < 0 OrElse _
        soundfontBank_HasBytes(offset, CULngInt(byteCount), limit) = 0 Then
        Return 0
    End If
    If byteCount = 0 Then
        Return -1
    End If
    resultText = Space(byteCount)
    Return binaryFile_ReadExact(fileNumber, CLngInt(offset + 1), _
        StrPtr(resultText), byteCount)
End Function


Private Function soundfontBank_ReadU16( _
    ByVal fileNumber As Integer, _
    ByVal offset As ULongInt, _
    ByVal limit As ULongInt, _
    ByRef resultValue As UShort _
) As Integer
    resultValue = 0
    If soundfontBank_HasBytes(offset, 2, limit) = 0 Then
        Return 0
    End If
    Return binaryFile_ReadExact(fileNumber, CLngInt(offset + 1), _
        @resultValue, SizeOf(resultValue))
End Function


Private Function soundfontBank_ReadU32( _
    ByVal fileNumber As Integer, _
    ByVal offset As ULongInt, _
    ByVal limit As ULongInt, _
    ByRef resultValue As ULong _
) As Integer
    resultValue = 0
    If soundfontBank_HasBytes(offset, 4, limit) = 0 Then
        Return 0
    End If
    Return binaryFile_ReadExact(fileNumber, CLngInt(offset + 1), _
        @resultValue, SizeOf(resultValue))
End Function


Private Function soundfontBank_FourCc( _
    ByVal fileNumber As Integer, _
    ByVal offset As ULongInt, _
    ByVal limit As ULongInt _
) As String
    Dim As String resultText
    If soundfontBank_ReadText(fileNumber, offset, 4, limit, resultText) = 0 Then
        Return ""
    End If
    Return resultText
End Function


Private Function soundfontBank_TrimFixedText(ByVal fixedText As String) As String
    Dim As Integer nullPosition = InStr(fixedText, Chr(0))
    If nullPosition > 0 Then
        fixedText = Left(fixedText, nullPosition - 1)
    End If
    Return Left(Trim(fixedText), OSE_SOUNDFONT_MAX_NAME_BYTES)
End Function


Private Function soundfontBank_SignedAmount(ByVal amount As UShort) As Integer
    If amount >= 32768 Then
        Return CInt(amount) - 65536
    End If
    Return CInt(amount)
End Function


Private Function soundfontBank_RecordCount( _
    ByVal chunkLength As ULongInt, _
    ByVal recordBytes As Integer, _
    ByRef recordCount As Integer _
) As Integer
    recordCount = 0
    If recordBytes <= 0 OrElse chunkLength = 0 OrElse _
        chunkLength Mod CULngInt(recordBytes) <> 0 Then
        Return 0
    End If
    Dim As ULongInt exactCount = chunkLength \ CULngInt(recordBytes)
    If exactCount < 1 OrElse _
        exactCount > CULngInt(SOUNDFONT_BANK_MAX_TABLE_RECORDS) Then
        Return 0
    End If
    recordCount = CInt(exactCount)
    Return -1
End Function

' -------------------------------------------------------------------------
' Storage lifecycle
' -------------------------------------------------------------------------

Private Sub soundfontBank_ClearStorage(ByRef bank As SoundFontBankStorage)
    If bank.sampleData <> 0 Then
        Deallocate bank.sampleData
    End If
    If bank.presets <> 0 Then
        Delete[] bank.presets
    End If
    If bank.presetBags <> 0 Then
        Deallocate bank.presetBags
    End If
    If bank.presetGenerators <> 0 Then
        Deallocate bank.presetGenerators
    End If
    If bank.instruments <> 0 Then
        Delete[] bank.instruments
    End If
    If bank.instrumentBags <> 0 Then
        Deallocate bank.instrumentBags
    End If
    If bank.instrumentGenerators <> 0 Then
        Deallocate bank.instrumentGenerators
    End If
    If bank.sampleHeaders <> 0 Then
        Delete[] bank.sampleHeaders
    End If
    Dim As SoundFontBankStorage emptyBank
    bank = emptyBank
End Sub


Public Sub soundfontBank_Clear()
    soundfontBank_ClearStorage soundfontBank_Active
End Sub


Private Sub soundfontBank_MoveStorage( _
    ByRef targetBank As SoundFontBankStorage, _
    ByRef sourceBank As SoundFontBankStorage _
)
    soundfontBank_ClearStorage targetBank
    targetBank = sourceBank
    Dim As SoundFontBankStorage emptyBank
    sourceBank = emptyBank
End Sub

' -------------------------------------------------------------------------
' RIFF chunk discovery
' -------------------------------------------------------------------------

Private Function soundfontBank_FindList( _
    ByVal fileNumber As Integer, _
    ByVal listOffset As ULongInt, _
    ByVal listLength As ULongInt, _
    ByVal wantedListType As String, _
    ByVal fileLimit As ULongInt, _
    ByRef foundList As SoundFontChunkLocation _
) As Integer
    If Len(wantedListType) <> 4 OrElse _
        soundfontBank_HasBytes(listOffset, listLength, fileLimit) = 0 Then
        Return 0
    End If
    Dim As ULongInt cursor = listOffset
    Dim As ULongInt listEnd = listOffset + listLength
    While cursor < listEnd
        If soundfontBank_HasBytes(cursor, 8, listEnd) = 0 Then
            Return 0
        End If
        Dim As String chunkId = soundfontBank_FourCc( _
            fileNumber, cursor, listEnd)
        Dim As ULong chunkLength32
        If soundfontBank_ReadU32(fileNumber, cursor + 4, listEnd, _
            chunkLength32) = 0 Then
            Return 0
        End If
        Dim As ULongInt chunkLength = CULngInt(chunkLength32)
        Dim As ULongInt payloadOffset = cursor + 8
        If soundfontBank_HasBytes(payloadOffset, chunkLength, listEnd) = 0 Then
            Return 0
        End If
        If chunkId = "LIST" AndAlso chunkLength >= 4 Then
            If soundfontBank_FourCc(fileNumber, payloadOffset, listEnd) = _
                wantedListType Then
                If foundList.found <> 0 Then
                    Return 0
                End If
                foundList.offset = payloadOffset + 4
                foundList.length = chunkLength - 4
                foundList.found = -1
            End If
        End If
        Dim As ULongInt paddedLength = chunkLength + (chunkLength And &H1)
        If paddedLength > listEnd - payloadOffset Then
            Return 0
        End If
        cursor = payloadOffset + paddedLength
    Wend
    Return IIf(cursor = listEnd, -1, 0)
End Function


Private Function soundfontBank_FindSubchunks( _
    ByVal fileNumber As Integer, _
    ByVal listOffset As ULongInt, _
    ByVal listLength As ULongInt, _
    wantedIds() As String, _
    locations() As SoundFontChunkLocation, _
    ByVal fileLimit As ULongInt _
) As Integer
    If UBound(wantedIds) < LBound(wantedIds) OrElse _
        UBound(locations) < LBound(locations) OrElse _
        LBound(wantedIds) <> LBound(locations) OrElse _
        UBound(wantedIds) <> UBound(locations) OrElse _
        soundfontBank_HasBytes(listOffset, listLength, fileLimit) = 0 Then
        Return 0
    End If
    Dim As ULongInt cursor = listOffset
    Dim As ULongInt listEnd = listOffset + listLength
    While cursor < listEnd
        If soundfontBank_HasBytes(cursor, 8, listEnd) = 0 Then
            Return 0
        End If
        Dim As String chunkId = soundfontBank_FourCc( _
            fileNumber, cursor, listEnd)
        Dim As ULong chunkLength32
        If soundfontBank_ReadU32(fileNumber, cursor + 4, listEnd, _
            chunkLength32) = 0 Then
            Return 0
        End If
        Dim As ULongInt chunkLength = CULngInt(chunkLength32)
        Dim As ULongInt payloadOffset = cursor + 8
        If soundfontBank_HasBytes(payloadOffset, chunkLength, listEnd) = 0 Then
            Return 0
        End If
        For wantedIndex As Integer = LBound(wantedIds) To UBound(wantedIds)
            If chunkId = wantedIds(wantedIndex) Then
                If locations(wantedIndex).found <> 0 Then
                    Return 0
                End If
                locations(wantedIndex).offset = payloadOffset
                locations(wantedIndex).length = chunkLength
                locations(wantedIndex).found = -1
            End If
        Next
        Dim As ULongInt paddedLength = chunkLength + (chunkLength And &H1)
        If paddedLength > listEnd - payloadOffset Then
            Return 0
        End If
        cursor = payloadOffset + paddedLength
    Wend
    Return IIf(cursor = listEnd, -1, 0)
End Function

' -------------------------------------------------------------------------
' Hydra table readers
' -------------------------------------------------------------------------

Private Function soundfontBank_LoadPresetHeaders( _
    ByVal fileNumber As Integer, _
    ByRef location As SoundFontChunkLocation, _
    ByVal fileLimit As ULongInt, _
    ByRef bank As SoundFontBankStorage _
) As Integer
    Dim As Integer storedCount
    If location.found = 0 OrElse _
        soundfontBank_RecordCount(location.length, _
            SF2_PRESET_HEADER_RECORD_BYTES, storedCount) = 0 OrElse _
        storedCount < 2 Then
        Return 0
    End If
    bank.presetCount = storedCount - 1
    bank.presets = New SoundFontPresetHeader[storedCount]
    If bank.presets = 0 Then
        Return 0
    End If
    For recordIndex As Integer = 0 To storedCount - 1
        Dim As ULongInt recordOffset = location.offset + _
            CULngInt(recordIndex) * SF2_PRESET_HEADER_RECORD_BYTES
        Dim As String fixedName
        If soundfontBank_ReadText(fileNumber, recordOffset, _
            SF2_FIXED_NAME_BYTES, fileLimit, _
            fixedName) = 0 OrElse _
            soundfontBank_ReadU16(fileNumber, recordOffset + _
                SF2_PRESET_PROGRAM_OFFSET, fileLimit, _
                bank.presets[recordIndex].programNumber) = 0 OrElse _
            soundfontBank_ReadU16(fileNumber, recordOffset + _
                SF2_PRESET_BANK_OFFSET, fileLimit, _
                bank.presets[recordIndex].bankNumber) = 0 OrElse _
            soundfontBank_ReadU16(fileNumber, recordOffset + _
                SF2_PRESET_BAG_OFFSET, fileLimit, _
                bank.presets[recordIndex].bagIndex) = 0 Then
            Return 0
        End If
        bank.presets[recordIndex].name = soundfontBank_TrimFixedText(fixedName)
    Next
    If bank.presets[storedCount - 1].name <> "EOP" Then
        Return 0
    End If
    Return -1
End Function


Private Function soundfontBank_LoadBags( _
    ByVal fileNumber As Integer, _
    ByRef location As SoundFontChunkLocation, _
    ByVal fileLimit As ULongInt, _
    ByRef bags As SoundFontBag Ptr, _
    ByRef bagCount As Integer _
) As Integer
    If location.found = 0 OrElse _
        soundfontBank_RecordCount(location.length, SF2_BAG_RECORD_BYTES, _
            bagCount) = 0 OrElse _
        bagCount < 2 Then
        Return 0
    End If
    bags = Callocate(CULngInt(bagCount) * SizeOf(SoundFontBag))
    If bags = 0 Then
        Return 0
    End If
    For recordIndex As Integer = 0 To bagCount - 1
        Dim As ULongInt recordOffset = location.offset + _
            CULngInt(recordIndex) * SF2_BAG_RECORD_BYTES
        If soundfontBank_ReadU16(fileNumber, recordOffset, fileLimit, _
            bags[recordIndex].generatorIndex) = 0 OrElse _
            soundfontBank_ReadU16(fileNumber, recordOffset + 2, fileLimit, _
                bags[recordIndex].modulatorIndex) = 0 Then
            Return 0
        End If
    Next
    Return -1
End Function


Private Function soundfontBank_LoadGenerators( _
    ByVal fileNumber As Integer, _
    ByRef location As SoundFontChunkLocation, _
    ByVal fileLimit As ULongInt, _
    ByRef generators As SoundFontGenerator Ptr, _
    ByRef generatorCount As Integer _
) As Integer
    If location.found = 0 OrElse _
        soundfontBank_RecordCount(location.length, SF2_GENERATOR_RECORD_BYTES, _
            generatorCount) = 0 Then
        Return 0
    End If
    generators = Callocate( _
        CULngInt(generatorCount) * SizeOf(SoundFontGenerator))
    If generators = 0 Then
        Return 0
    End If
    For recordIndex As Integer = 0 To generatorCount - 1
        Dim As ULongInt recordOffset = location.offset + _
            CULngInt(recordIndex) * SF2_GENERATOR_RECORD_BYTES
        If soundfontBank_ReadU16(fileNumber, recordOffset, fileLimit, _
            generators[recordIndex].operatorNumber) = 0 OrElse _
            soundfontBank_ReadU16(fileNumber, recordOffset + 2, fileLimit, _
                generators[recordIndex].amount) = 0 Then
            Return 0
        End If
    Next
    Return -1
End Function


Private Function soundfontBank_LoadInstrumentHeaders( _
    ByVal fileNumber As Integer, _
    ByRef location As SoundFontChunkLocation, _
    ByVal fileLimit As ULongInt, _
    ByRef bank As SoundFontBankStorage _
) As Integer
    Dim As Integer storedCount
    If location.found = 0 OrElse _
        soundfontBank_RecordCount(location.length, _
            SF2_INSTRUMENT_HEADER_RECORD_BYTES, storedCount) = 0 OrElse _
        storedCount < 2 Then
        Return 0
    End If
    bank.instrumentCount = storedCount - 1
    bank.instruments = New SoundFontInstrumentHeader[storedCount]
    If bank.instruments = 0 Then
        Return 0
    End If
    For recordIndex As Integer = 0 To storedCount - 1
        Dim As ULongInt recordOffset = location.offset + _
            CULngInt(recordIndex) * SF2_INSTRUMENT_HEADER_RECORD_BYTES
        Dim As String fixedName
        If soundfontBank_ReadText(fileNumber, recordOffset, _
            SF2_FIXED_NAME_BYTES, fileLimit, _
            fixedName) = 0 OrElse _
            soundfontBank_ReadU16(fileNumber, recordOffset + _
                SF2_INSTRUMENT_BAG_OFFSET, fileLimit, _
                bank.instruments[recordIndex].bagIndex) = 0 Then
            Return 0
        End If
        bank.instruments[recordIndex].name = _
            soundfontBank_TrimFixedText(fixedName)
    Next
    If bank.instruments[storedCount - 1].name <> "EOI" Then
        Return 0
    End If
    Return -1
End Function


Private Function soundfontBank_LoadSampleHeaders( _
    ByVal fileNumber As Integer, _
    ByRef location As SoundFontChunkLocation, _
    ByVal fileLimit As ULongInt, _
    ByRef bank As SoundFontBankStorage _
) As Integer
    Dim As Integer storedCount
    If location.found = 0 OrElse _
        soundfontBank_RecordCount(location.length, _
            SF2_SAMPLE_HEADER_RECORD_BYTES, storedCount) = 0 OrElse _
        storedCount < 2 Then
        Return 0
    End If
    bank.sampleHeaderCount = storedCount - 1
    bank.sampleHeaders = New SoundFontSampleHeader[storedCount]
    If bank.sampleHeaders = 0 Then
        Return 0
    End If
    For recordIndex As Integer = 0 To storedCount - 1
        Dim As ULongInt recordOffset = location.offset + _
            CULngInt(recordIndex) * SF2_SAMPLE_HEADER_RECORD_BYTES
        Dim As String fixedName
        If soundfontBank_ReadText(fileNumber, recordOffset, _
            SF2_FIXED_NAME_BYTES, fileLimit, _
            fixedName) = 0 OrElse _
            soundfontBank_ReadU32(fileNumber, recordOffset + _
                SF2_SAMPLE_START_OFFSET, fileLimit, _
                bank.sampleHeaders[recordIndex].startPoint) = 0 OrElse _
            soundfontBank_ReadU32(fileNumber, recordOffset + _
                SF2_SAMPLE_END_OFFSET, fileLimit, _
                bank.sampleHeaders[recordIndex].endPoint) = 0 OrElse _
            soundfontBank_ReadU32(fileNumber, recordOffset + _
                SF2_SAMPLE_LOOP_START_OFFSET, fileLimit, _
                bank.sampleHeaders[recordIndex].loopStart) = 0 OrElse _
            soundfontBank_ReadU32(fileNumber, recordOffset + _
                SF2_SAMPLE_LOOP_END_OFFSET, fileLimit, _
                bank.sampleHeaders[recordIndex].loopEnd) = 0 OrElse _
            soundfontBank_ReadU32(fileNumber, recordOffset + _
                SF2_SAMPLE_RATE_OFFSET, fileLimit, _
                bank.sampleHeaders[recordIndex].sampleRate) = 0 Then
            Return 0
        End If
        If soundfontBank_ReadU16(fileNumber, recordOffset + _
            SF2_SAMPLE_LINK_OFFSET, fileLimit, _
            bank.sampleHeaders[recordIndex].sampleLink) = 0 OrElse _
            soundfontBank_ReadU16(fileNumber, recordOffset + _
                SF2_SAMPLE_TYPE_OFFSET, fileLimit, _
                bank.sampleHeaders[recordIndex].sampleType) = 0 Then
            Return 0
        End If
        ' The byte reads above are one-based FreeBASIC positions. Read them
        ' explicitly after the fixed-width fields so signed correction remains
        ' distinct from the following 16-bit sample-link member.
        If binaryFile_ReadExact(fileNumber, CLngInt(recordOffset + _
            SF2_SAMPLE_ORIGINAL_PITCH_OFFSET + 1), _
            @bank.sampleHeaders[recordIndex].originalPitch, _
            SizeOf(bank.sampleHeaders[recordIndex].originalPitch)) = 0 OrElse _
            binaryFile_ReadExact(fileNumber, CLngInt(recordOffset + _
            SF2_SAMPLE_PITCH_CORRECTION_OFFSET + 1), _
            @bank.sampleHeaders[recordIndex].pitchCorrection, _
            SizeOf(bank.sampleHeaders[recordIndex].pitchCorrection)) = 0 Then
            Return 0
        End If
        bank.sampleHeaders[recordIndex].name = _
            soundfontBank_TrimFixedText(fixedName)
    Next
    If bank.sampleHeaders[storedCount - 1].name <> "EOS" Then
        Return 0
    End If
    Return -1
End Function


Private Function soundfontBank_ValidateIndexes( _
    ByRef bank As SoundFontBankStorage _
) As Integer
    For presetIndex As Integer = 0 To bank.presetCount
        If bank.presets[presetIndex].bagIndex >= bank.presetBagCount Then
            Return 0
        End If
        If presetIndex > 0 AndAlso _
            bank.presets[presetIndex].bagIndex < _
            bank.presets[presetIndex - 1].bagIndex Then
            Return 0
        End If
    Next
    For bagIndex As Integer = 0 To bank.presetBagCount - 1
        If bank.presetBags[bagIndex].generatorIndex >= _
            bank.presetGeneratorCount Then
            Return 0
        End If
        If bagIndex > 0 AndAlso _
            bank.presetBags[bagIndex].generatorIndex < _
            bank.presetBags[bagIndex - 1].generatorIndex Then
            Return 0
        End If
    Next
    For instrumentIndex As Integer = 0 To bank.instrumentCount
        If bank.instruments[instrumentIndex].bagIndex >= _
            bank.instrumentBagCount Then
            Return 0
        End If
        If instrumentIndex > 0 AndAlso _
            bank.instruments[instrumentIndex].bagIndex < _
            bank.instruments[instrumentIndex - 1].bagIndex Then
            Return 0
        End If
    Next
    For bagIndex As Integer = 0 To bank.instrumentBagCount - 1
        If bank.instrumentBags[bagIndex].generatorIndex >= _
            bank.instrumentGeneratorCount Then
            Return 0
        End If
        If bagIndex > 0 AndAlso _
            bank.instrumentBags[bagIndex].generatorIndex < _
            bank.instrumentBags[bagIndex - 1].generatorIndex Then
            Return 0
        End If
    Next
    For sampleIndex As Integer = 0 To bank.sampleHeaderCount - 1
        Dim As SoundFontSampleHeader Ptr sampleHeader = _
            @bank.sampleHeaders[sampleIndex]
        If sampleHeader->startPoint >= sampleHeader->endPoint OrElse _
            CULngInt(sampleHeader->endPoint) > bank.samplePointCount OrElse _
            sampleHeader->sampleRate < 400 OrElse _
            sampleHeader->sampleRate > 384000 OrElse _
            sampleHeader->originalPitch > 127 OrElse _
            (sampleHeader->sampleType And SOUNDFONT_BANK_SAMPLE_HEADER_ROM) <> 0 Then
            Return 0
        End If
        Dim As Integer baseType = sampleHeader->sampleType And &H7FFF
        If baseType <> SOUNDFONT_BANK_SAMPLE_HEADER_MONO AndAlso _
            baseType <> SOUNDFONT_BANK_SAMPLE_HEADER_RIGHT AndAlso _
            baseType <> SOUNDFONT_BANK_SAMPLE_HEADER_LEFT AndAlso _
            baseType <> SOUNDFONT_BANK_SAMPLE_HEADER_LINKED Then
            Return 0
        End If
        If baseType <> SOUNDFONT_BANK_SAMPLE_HEADER_MONO Then
            If sampleHeader->sampleLink >= bank.sampleHeaderCount Then
                Return 0
            End If
        End If
    Next
    Return -1
End Function

' -------------------------------------------------------------------------
' Transactional public load
' -------------------------------------------------------------------------

Public Function soundfontBank_Load( _
    ByVal filename As String, _
    ByRef errorText As String _
) As Integer
    ' Checked FreeBASIC builds emit resume labels around binary reads. Keep
    ' the bounds initialized before those error paths exist.
    Dim As ULongInt fileBytes
    errorText = ""
    filename = Trim(filename)
    If filename = "" OrElse Len(filename) > OSE_SOUNDFONT_MAX_PATH_BYTES OrElse _
        InStr(filename, Chr(0)) > 0 Then
        errorText = "The SoundFont path is invalid."
        Return 0
    End If

    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then
        errorText = "The SoundFont file could not be opened."
        Return 0
    End If

    Dim As SoundFontBankStorage candidateBank
    Dim As Integer loadResult
    Do
        Dim As LongInt signedFileBytes = Lof(fileNumber)
        If signedFileBytes < 12 OrElse _
            CULngInt(signedFileBytes) > SOUNDFONT_BANK_MAX_FILE_BYTES Then
            errorText = "The SoundFont file size is outside supported limits."
            Exit Do
        End If
        fileBytes = CULngInt(signedFileBytes)
        Dim As ULong riffLength32
        If soundfontBank_FourCc(fileNumber, 0, fileBytes) <> "RIFF" OrElse _
            soundfontBank_ReadU32(fileNumber, 4, fileBytes, riffLength32) = 0 OrElse _
            soundfontBank_FourCc(fileNumber, 8, fileBytes) <> "sfbk" OrElse _
            CULngInt(riffLength32) + 8 <> fileBytes Then
            errorText = "The file is not a complete SoundFont 2 RIFF bank."
            Exit Do
        End If

        Dim As SoundFontChunkLocation infoList
        Dim As SoundFontChunkLocation sampleList
        Dim As SoundFontChunkLocation presetList
        If soundfontBank_FindList(fileNumber, 12, fileBytes - 12, "INFO", _
            fileBytes, infoList) = 0 OrElse _
            soundfontBank_FindList(fileNumber, 12, fileBytes - 12, "sdta", _
                fileBytes, sampleList) = 0 OrElse _
            soundfontBank_FindList(fileNumber, 12, fileBytes - 12, "pdta", _
                fileBytes, presetList) = 0 OrElse _
            infoList.found = 0 OrElse sampleList.found = 0 OrElse _
            presetList.found = 0 Then
            errorText = "The SoundFont is missing a required INFO, sdta, or pdta list."
            Exit Do
        End If

        Dim As String infoIds(0 To 1) = {"ifil", "INAM"}
        Dim As SoundFontChunkLocation infoChunks(0 To 1)
        If soundfontBank_FindSubchunks(fileNumber, infoList.offset, _
            infoList.length, infoIds(), infoChunks(), fileBytes) = 0 OrElse _
            infoChunks(0).found = 0 OrElse infoChunks(0).length <> 4 OrElse _
            infoChunks(1).found = 0 OrElse infoChunks(1).length < 1 OrElse _
            infoChunks(1).length > OSE_SOUNDFONT_MAX_NAME_BYTES + 1 Then
            errorText = "The SoundFont INFO list is malformed."
            Exit Do
        End If
        Dim As UShort versionMajor
        Dim As UShort versionMinor
        If soundfontBank_ReadU16(fileNumber, infoChunks(0).offset, fileBytes, _
            versionMajor) = 0 OrElse _
            soundfontBank_ReadU16(fileNumber, infoChunks(0).offset + 2, fileBytes, _
                versionMinor) = 0 OrElse versionMajor <> 2 Then
            errorText = "Only SoundFont 2 banks are supported."
            Exit Do
        End If
        Dim As String fixedBankName
        If soundfontBank_ReadText(fileNumber, infoChunks(1).offset, _
            CInt(infoChunks(1).length), fileBytes, fixedBankName) = 0 Then
            errorText = "The SoundFont name could not be read."
            Exit Do
        End If
        candidateBank.bankName = soundfontBank_TrimFixedText(fixedBankName)
        If candidateBank.bankName = "" Then
            candidateBank.bankName = "Unnamed SoundFont"
        End If

        Dim As String sampleIds(0 To 0) = {"smpl"}
        Dim As SoundFontChunkLocation sampleChunks(0 To 0)
        If soundfontBank_FindSubchunks(fileNumber, sampleList.offset, _
            sampleList.length, sampleIds(), sampleChunks(), fileBytes) = 0 OrElse _
            sampleChunks(0).found = 0 OrElse sampleChunks(0).length < 2 OrElse _
            (sampleChunks(0).length And &H1) <> 0 Then
            errorText = "The SoundFont sample-data chunk is malformed."
            Exit Do
        End If
        candidateBank.samplePointCount = sampleChunks(0).length \ 2
        candidateBank.sampleData = Allocate(sampleChunks(0).length)
        If candidateBank.sampleData = 0 Then
            errorText = "There is not enough memory for the SoundFont samples."
            Exit Do
        End If
        If binaryFile_ReadExact(fileNumber, CLngInt(sampleChunks(0).offset + 1), _
            candidateBank.sampleData, CInt(sampleChunks(0).length)) = 0 Then
            errorText = "The SoundFont sample data could not be read completely."
            Exit Do
        End If

        Dim As String hydraIds(0 To 8) = { _
            "phdr", "pbag", "pmod", "pgen", "inst", _
            "ibag", "imod", "igen", "shdr" _
        }
        Dim As SoundFontChunkLocation hydra(0 To 8)
        If soundfontBank_FindSubchunks(fileNumber, presetList.offset, _
            presetList.length, hydraIds(), hydra(), fileBytes) = 0 Then
            errorText = "The SoundFont Hydra table is malformed."
            Exit Do
        End If
        For hydraIndex As Integer = 0 To 8
            If hydra(hydraIndex).found = 0 Then
                errorText = "The SoundFont is missing a required Hydra table."
                Exit Do
            End If
        Next
        If errorText <> "" Then
            Exit Do
        End If
        ' Modulators are retained by the file but are not needed for the
        ' baseline General MIDI generator path. Their fixed records and
        ' terminal entries are still validated so damaged offsets are rejected.
        Dim As Integer presetModulatorCount
        Dim As Integer instrumentModulatorCount
        If soundfontBank_RecordCount(hydra(2).length, _
            SF2_MODULATOR_RECORD_BYTES, _
            presetModulatorCount) = 0 OrElse _
            soundfontBank_RecordCount(hydra(6).length, _
                SF2_MODULATOR_RECORD_BYTES, _
                instrumentModulatorCount) = 0 OrElse _
            soundfontBank_LoadPresetHeaders(fileNumber, hydra(0), fileBytes, _
                candidateBank) = 0 OrElse _
            soundfontBank_LoadBags(fileNumber, hydra(1), fileBytes, _
                candidateBank.presetBags, candidateBank.presetBagCount) = 0 OrElse _
            soundfontBank_LoadGenerators(fileNumber, hydra(3), fileBytes, _
                candidateBank.presetGenerators, _
                candidateBank.presetGeneratorCount) = 0 OrElse _
            soundfontBank_LoadInstrumentHeaders(fileNumber, hydra(4), fileBytes, _
                candidateBank) = 0 OrElse _
            soundfontBank_LoadBags(fileNumber, hydra(5), fileBytes, _
                candidateBank.instrumentBags, _
                candidateBank.instrumentBagCount) = 0 OrElse _
            soundfontBank_LoadGenerators(fileNumber, hydra(7), fileBytes, _
                candidateBank.instrumentGenerators, _
                candidateBank.instrumentGeneratorCount) = 0 OrElse _
            soundfontBank_LoadSampleHeaders(fileNumber, hydra(8), fileBytes, _
                candidateBank) = 0 OrElse _
            soundfontBank_ValidateIndexes(candidateBank) = 0 Then
            errorText = "The SoundFont Hydra records contain invalid indexes or samples."
            Exit Do
        End If

        candidateBank.filename = filename
        loadResult = -1
    Loop While 0
    Close #fileNumber

    If loadResult = 0 Then
        soundfontBank_ClearStorage candidateBank
        Return 0
    End If
    soundfontBank_MoveStorage soundfontBank_Active, candidateBank
    Return -1
End Function

' -------------------------------------------------------------------------
' Generator resolution
' -------------------------------------------------------------------------

Private Sub soundfontBank_DefaultGeneratorState( _
    ByRef generatorState As SoundFontGeneratorState, _
    ByVal presetLevel As Integer _
)
    Dim As SoundFontGeneratorState emptyState
    generatorState = emptyState
    generatorState.keyLow = 0
    generatorState.keyHigh = 127
    generatorState.velocityLow = 0
    generatorState.velocityHigh = 127
    generatorState.instrumentIndex = -1
    generatorState.sampleIndex = -1
    generatorState.forcedKey = -1
    generatorState.forcedVelocity = -1
    ' Preset values are offsets. Instrument values start at SF2 defaults.
    If presetLevel = 0 Then
        generatorState.attackTimecents = -12000
        generatorState.holdTimecents = -12000
        generatorState.decayTimecents = -12000
        generatorState.releaseTimecents = -12000
        generatorState.scaleTuning = 100
    End If
    generatorState.overridingRootKey = -1
End Sub


Private Sub soundfontBank_ApplyGenerator( _
    ByRef generatorState As SoundFontGeneratorState, _
    ByRef generator As SoundFontGenerator _
)
    Dim As Integer signedAmount = soundfontBank_SignedAmount(generator.amount)
    Select Case generator.operatorNumber
        Case SF2_GEN_START_OFFSET
            generatorState.startOffset = signedAmount
        Case SF2_GEN_END_OFFSET
            generatorState.endOffset = signedAmount
        Case SF2_GEN_LOOP_START_OFFSET
            generatorState.loopStartOffset = signedAmount
        Case SF2_GEN_LOOP_END_OFFSET
            generatorState.loopEndOffset = signedAmount
        Case SF2_GEN_START_COARSE_OFFSET
            generatorState.startCoarseOffset = _
                CLngInt(signedAmount) * SF2_COARSE_SAMPLE_STEP
        Case SF2_GEN_END_COARSE_OFFSET
            generatorState.endCoarseOffset = _
                CLngInt(signedAmount) * SF2_COARSE_SAMPLE_STEP
        Case SF2_GEN_LOOP_START_COARSE_OFFSET
            generatorState.loopStartCoarseOffset = _
                CLngInt(signedAmount) * SF2_COARSE_SAMPLE_STEP
        Case SF2_GEN_LOOP_END_COARSE_OFFSET
            generatorState.loopEndCoarseOffset = _
                CLngInt(signedAmount) * SF2_COARSE_SAMPLE_STEP
        Case SF2_GEN_PAN
            generatorState.pan = signedAmount
        Case SF2_GEN_ATTACK_VOLUME
            generatorState.attackTimecents = signedAmount
        Case SF2_GEN_HOLD_VOLUME
            generatorState.holdTimecents = signedAmount
        Case SF2_GEN_DECAY_VOLUME
            generatorState.decayTimecents = signedAmount
        Case SF2_GEN_SUSTAIN_VOLUME
            generatorState.sustainCentibels = signedAmount
        Case SF2_GEN_RELEASE_VOLUME
            generatorState.releaseTimecents = signedAmount
        Case SF2_GEN_INSTRUMENT
            generatorState.instrumentIndex = generator.amount
        Case SF2_GEN_KEY_RANGE
            Dim As Integer lowKey = generator.amount And &HFF
            Dim As Integer highKey = (generator.amount Shr 8) And &HFF
            generatorState.keyLow = lowKey
            generatorState.keyHigh = highKey
        Case SF2_GEN_VELOCITY_RANGE
            Dim As Integer lowVelocity = generator.amount And &HFF
            Dim As Integer highVelocity = (generator.amount Shr 8) And &HFF
            generatorState.velocityLow = lowVelocity
            generatorState.velocityHigh = highVelocity
        Case SF2_GEN_KEY_NUMBER
            If signedAmount >= -1 AndAlso signedAmount <= 127 Then
                generatorState.forcedKey = signedAmount
            End If
        Case SF2_GEN_VELOCITY
            If signedAmount >= -1 AndAlso signedAmount <= 127 Then
                generatorState.forcedVelocity = signedAmount
            End If
        Case SF2_GEN_INITIAL_ATTENUATION
            generatorState.attenuationCentibels = signedAmount
        Case SF2_GEN_COARSE_TUNE
            generatorState.coarseTune = signedAmount
        Case SF2_GEN_FINE_TUNE
            generatorState.fineTune = signedAmount
        Case SF2_GEN_SAMPLE_ID
            generatorState.sampleIndex = generator.amount
        Case SF2_GEN_SAMPLE_MODES
            generatorState.sampleModes = generator.amount And &H3
        Case SF2_GEN_SCALE_TUNING
            generatorState.scaleTuning = signedAmount
        Case SF2_GEN_EXCLUSIVE_CLASS
            generatorState.exclusiveClass = generator.amount
        Case SF2_GEN_OVERRIDING_ROOT_KEY
            If signedAmount >= -1 AndAlso signedAmount <= 127 Then
                generatorState.overridingRootKey = signedAmount
            End If
    End Select
End Sub


Private Function soundfontBank_ApplyBag( _
    ByRef generatorState As SoundFontGeneratorState, _
    ByVal bagIndex As Integer, _
    ByVal presetLevel As Integer _
) As Integer
    Dim As SoundFontBag Ptr bags
    Dim As SoundFontGenerator Ptr generators
    Dim As Integer bagCount
    Dim As Integer generatorCount
    If presetLevel <> 0 Then
        bags = soundfontBank_Active.presetBags
        generators = soundfontBank_Active.presetGenerators
        bagCount = soundfontBank_Active.presetBagCount
        generatorCount = soundfontBank_Active.presetGeneratorCount
    Else
        bags = soundfontBank_Active.instrumentBags
        generators = soundfontBank_Active.instrumentGenerators
        bagCount = soundfontBank_Active.instrumentBagCount
        generatorCount = soundfontBank_Active.instrumentGeneratorCount
    End If
    If bags = 0 OrElse generators = 0 OrElse bagIndex < 0 OrElse _
        bagIndex + 1 >= bagCount Then
        Return 0
    End If
    Dim As Integer firstGenerator = bags[bagIndex].generatorIndex
    Dim As Integer finalGenerator = bags[bagIndex + 1].generatorIndex
    If firstGenerator < 0 OrElse finalGenerator < firstGenerator OrElse _
        finalGenerator > generatorCount Then
        Return 0
    End If
    For generatorIndex As Integer = firstGenerator To finalGenerator - 1
        ' SF2 section 8.5 limits sample addressing and substitutions to the
        ' instrument level. Ignore misplaced operators instead of allowing a
        ' malformed preset to select arbitrary sample addresses or note keys.
        Dim As Integer operatorNumber = generators[generatorIndex].operatorNumber
        If presetLevel <> 0 Then
            Select Case operatorNumber
                Case SF2_GEN_START_OFFSET, SF2_GEN_END_OFFSET, _
                    SF2_GEN_LOOP_START_OFFSET, SF2_GEN_LOOP_END_OFFSET, _
                    SF2_GEN_START_COARSE_OFFSET, SF2_GEN_END_COARSE_OFFSET, _
                    SF2_GEN_LOOP_START_COARSE_OFFSET, SF2_GEN_LOOP_END_COARSE_OFFSET, _
                    SF2_GEN_KEY_NUMBER, SF2_GEN_VELOCITY, SF2_GEN_SAMPLE_ID, _
                    SF2_GEN_SAMPLE_MODES, SF2_GEN_EXCLUSIVE_CLASS, _
                    SF2_GEN_OVERRIDING_ROOT_KEY
                    Continue For
            End Select
        ElseIf operatorNumber = SF2_GEN_INSTRUMENT Then
            Continue For
        End If
        soundfontBank_ApplyGenerator generatorState, generators[generatorIndex]
    Next
    Return -1
End Function


Private Sub soundfontBank_CombinePreset( _
    ByRef instrumentZone As SoundFontGeneratorState, _
    ByRef presetZone As SoundFontGeneratorState _
)
    /'
        SF2.04 section 9.4 has two separate precedence rules. Local generators
        replace global generators at their own level. Preset value generators
        then add to the resolved instrument values. Ranges have already been
        checked independently at both levels, which provides their intersection.
        Keep fine and coarse sample offsets separate until resolution so a
        local fine offset cannot erase an inherited coarse offset.
    '/
    instrumentZone.startOffset += instrumentZone.startCoarseOffset
    instrumentZone.endOffset += instrumentZone.endCoarseOffset
    instrumentZone.loopStartOffset += instrumentZone.loopStartCoarseOffset
    instrumentZone.loopEndOffset += instrumentZone.loopEndCoarseOffset
    instrumentZone.pan += presetZone.pan
    ' -32768 is the SF2 zero-time sentinel and remains zero after modulation.
    If instrumentZone.attackTimecents <> -32768 Then
        instrumentZone.attackTimecents += presetZone.attackTimecents
    End If
    If instrumentZone.holdTimecents <> -32768 Then
        instrumentZone.holdTimecents += presetZone.holdTimecents
    End If
    If instrumentZone.decayTimecents <> -32768 Then
        instrumentZone.decayTimecents += presetZone.decayTimecents
    End If
    If instrumentZone.releaseTimecents <> -32768 Then
        instrumentZone.releaseTimecents += presetZone.releaseTimecents
    End If
    instrumentZone.sustainCentibels += presetZone.sustainCentibels
    instrumentZone.attenuationCentibels += presetZone.attenuationCentibels
    instrumentZone.coarseTune += presetZone.coarseTune
    instrumentZone.fineTune += presetZone.fineTune
    instrumentZone.scaleTuning += presetZone.scaleTuning
End Sub


Private Function soundfontBank_StateMatches( _
    ByRef generatorState As SoundFontGeneratorState, _
    ByVal keyNumber As Integer, _
    ByVal velocity As Integer _
) As Integer
    If generatorState.keyLow > generatorState.keyHigh OrElse _
        generatorState.velocityLow > generatorState.velocityHigh OrElse _
        keyNumber < generatorState.keyLow OrElse keyNumber > generatorState.keyHigh OrElse _
        velocity < generatorState.velocityLow OrElse _
        velocity > generatorState.velocityHigh Then
        Return 0
    End If
    Return -1
End Function


Private Function soundfontBank_TimecentsSeconds( _
    ByVal timecents As Integer _
) As Single
    If timecents <= -12000 Then
        Return 0.0
    End If
    If timecents > 12000 Then
        timecents = 12000
    End If
    Return CSng(2.0 ^ (CDbl(timecents) / 1200.0))
End Function


Private Function soundfontBank_AdjustPoint( _
    ByVal basePoint As ULong, _
    ByVal pointOffset As LongInt, _
    ByVal sampleLimit As ULongInt, _
    ByRef adjustedPoint As ULongInt _
) As Integer
    If pointOffset < 0 Then
        Dim As ULongInt magnitude = CULngInt(-(pointOffset + 1)) + 1
        If magnitude > CULngInt(basePoint) Then
            Return 0
        End If
        adjustedPoint = CULngInt(basePoint) - magnitude
    Else
        adjustedPoint = CULngInt(basePoint) + CULngInt(pointOffset)
        If adjustedPoint < CULngInt(basePoint) Then
            Return 0
        End If
    End If
    Return IIf(adjustedPoint <= sampleLimit, -1, 0)
End Function


Private Function soundfontBank_BuildRegion( _
    ByRef generatorState As SoundFontGeneratorState, _
    ByRef region As OseSoundFontVoiceRegion _
) As Integer
    Dim As Integer sampleIndex = generatorState.sampleIndex
    If sampleIndex < 0 OrElse _
        sampleIndex >= soundfontBank_Active.sampleHeaderCount Then
        Return 0
    End If
    Dim As SoundFontSampleHeader Ptr primary = _
        @soundfontBank_Active.sampleHeaders[sampleIndex]
    Dim As SoundFontSampleHeader Ptr leftSample = primary
    Dim As SoundFontSampleHeader Ptr rightSample = primary
    /'
        An instrument zone selects exactly one sample header. Stereo banks use
        two zones with complementary pan generators, one for each linked
        header. Automatically following wSampleLink here would render both
        channels twice and would reject established banks whose informational
        link values are not reciprocal indexes. The mixer therefore treats
        each selected header as one mono source and lets its zone pan place it.
    '/

    Dim As OseSoundFontVoiceRegion emptyRegion
    region = emptyRegion
    If soundfontBank_AdjustPoint(leftSample->startPoint, _
        generatorState.startOffset, soundfontBank_Active.samplePointCount, _
        region.leftStart) = 0 OrElse _
        soundfontBank_AdjustPoint(leftSample->endPoint, _
            generatorState.endOffset, soundfontBank_Active.samplePointCount, _
            region.leftEnd) = 0 OrElse _
        soundfontBank_AdjustPoint(leftSample->loopStart, _
            generatorState.loopStartOffset, soundfontBank_Active.samplePointCount, _
            region.leftLoopStart) = 0 OrElse _
        soundfontBank_AdjustPoint(leftSample->loopEnd, _
            generatorState.loopEndOffset, soundfontBank_Active.samplePointCount, _
            region.leftLoopEnd) = 0 OrElse _
        soundfontBank_AdjustPoint(rightSample->startPoint, _
            generatorState.startOffset, soundfontBank_Active.samplePointCount, _
            region.rightStart) = 0 OrElse _
        soundfontBank_AdjustPoint(rightSample->endPoint, _
            generatorState.endOffset, soundfontBank_Active.samplePointCount, _
            region.rightEnd) = 0 OrElse _
        soundfontBank_AdjustPoint(rightSample->loopStart, _
            generatorState.loopStartOffset, soundfontBank_Active.samplePointCount, _
            region.rightLoopStart) = 0 OrElse _
        soundfontBank_AdjustPoint(rightSample->loopEnd, _
            generatorState.loopEndOffset, soundfontBank_Active.samplePointCount, _
            region.rightLoopEnd) = 0 Then
        Return 0
    End If
    If region.leftStart >= region.leftEnd OrElse _
        region.rightStart >= region.rightEnd Then
        Return 0
    End If

    region.sampleRate = leftSample->sampleRate
    region.rootKey = leftSample->originalPitch
    region.keyOverride = generatorState.forcedKey
    region.velocityOverride = generatorState.forcedVelocity
    If generatorState.overridingRootKey >= 0 Then
        region.rootKey = generatorState.overridingRootKey
    End If
    region.tuneCents = generatorState.coarseTune * 100 + _
        generatorState.fineTune - CInt(leftSample->pitchCorrection)
    region.scaleTuning = generatorState.scaleTuning
    If region.scaleTuning < 0 Then
        region.scaleTuning = 0
    End If
    If region.scaleTuning > 1200 Then
        region.scaleTuning = 1200
    End If
    region.sampleModes = generatorState.sampleModes
    If region.leftLoopStart >= region.leftLoopEnd OrElse _
        region.leftLoopStart < region.leftStart OrElse _
        region.leftLoopEnd > region.leftEnd OrElse _
        region.rightLoopStart >= region.rightLoopEnd OrElse _
        region.rightLoopStart < region.rightStart OrElse _
        region.rightLoopEnd > region.rightEnd Then
        region.sampleModes = 0
    End If
    region.exclusiveClass = generatorState.exclusiveClass
    Dim As Integer boundedPan = generatorState.pan
    If boundedPan < -SF2_PAN_LIMIT Then
        boundedPan = -SF2_PAN_LIMIT
    End If
    If boundedPan > SF2_PAN_LIMIT Then
        boundedPan = SF2_PAN_LIMIT
    End If
    region.pan = CSng(boundedPan) / CSng(SF2_PAN_LIMIT)
    Dim As Integer attenuation = generatorState.attenuationCentibels
    If attenuation < 0 Then
        attenuation = 0
    End If
    If attenuation > SF2_MAX_ATTENUATION_CENTIBELS Then
        attenuation = SF2_MAX_ATTENUATION_CENTIBELS
    End If
    region.attenuationGain = CSng(10.0 ^ (-CDbl(attenuation) / 200.0))
    region.attackSeconds = soundfontBank_TimecentsSeconds( _
        generatorState.attackTimecents)
    region.holdSeconds = soundfontBank_TimecentsSeconds( _
        generatorState.holdTimecents)
    region.decaySeconds = soundfontBank_TimecentsSeconds( _
        generatorState.decayTimecents)
    Dim As Integer sustainCentibels = generatorState.sustainCentibels
    If sustainCentibels < 0 Then
        sustainCentibels = 0
    End If
    If sustainCentibels > 1440 Then
        sustainCentibels = 1440
    End If
    region.sustainLevel = CSng(10.0 ^ (-CDbl(sustainCentibels) / 200.0))
    region.releaseSeconds = soundfontBank_TimecentsSeconds( _
        generatorState.releaseTimecents)
    Return -1
End Function


Private Function soundfontBank_ResolvePreset( _
    ByVal presetIndex As Integer, _
    ByVal keyNumber As Integer, _
    ByVal velocity As Integer, _
    regions() As OseSoundFontVoiceRegion _
) As Integer
    If presetIndex < 0 OrElse presetIndex >= soundfontBank_Active.presetCount Then
        Return 0
    End If
    If UBound(regions) < LBound(regions) Then
        Return 0
    End If
    Dim As Integer regionCapacity = UBound(regions) - LBound(regions) + 1
    If regionCapacity < 1 Then
        Return 0
    End If
    Dim As Integer firstPresetBag = _
        soundfontBank_Active.presets[presetIndex].bagIndex
    Dim As Integer finalPresetBag = _
        soundfontBank_Active.presets[presetIndex + 1].bagIndex
    If firstPresetBag < 0 OrElse finalPresetBag < firstPresetBag OrElse _
        finalPresetBag >= soundfontBank_Active.presetBagCount Then
        Return 0
    End If

    Dim As SoundFontGeneratorState presetGlobal
    soundfontBank_DefaultGeneratorState presetGlobal, -1
    Dim As Integer resolvedCount
    For presetBagIndex As Integer = firstPresetBag To finalPresetBag - 1
        Dim As SoundFontGeneratorState presetZone = presetGlobal
        If soundfontBank_ApplyBag(presetZone, presetBagIndex, -1) = 0 Then
            Return 0
        End If
        If presetZone.instrumentIndex < 0 Then
            If presetBagIndex = firstPresetBag Then
                presetGlobal = presetZone
            End If
            Continue For
        End If
        If soundfontBank_StateMatches(presetZone, keyNumber, velocity) = 0 OrElse _
            presetZone.instrumentIndex >= soundfontBank_Active.instrumentCount Then
            Continue For
        End If

        Dim As Integer instrumentIndex = presetZone.instrumentIndex
        Dim As Integer firstInstrumentBag = _
            soundfontBank_Active.instruments[instrumentIndex].bagIndex
        Dim As Integer finalInstrumentBag = _
            soundfontBank_Active.instruments[instrumentIndex + 1].bagIndex
        If firstInstrumentBag < 0 OrElse _
            finalInstrumentBag < firstInstrumentBag OrElse _
            finalInstrumentBag >= soundfontBank_Active.instrumentBagCount Then
            Continue For
        End If
        Dim As SoundFontGeneratorState instrumentGlobal
        soundfontBank_DefaultGeneratorState instrumentGlobal, 0
        For instrumentBagIndex As Integer = firstInstrumentBag To _
            finalInstrumentBag - 1
            Dim As SoundFontGeneratorState instrumentZone = instrumentGlobal
            If soundfontBank_ApplyBag(instrumentZone, instrumentBagIndex, 0) = 0 Then
                Return resolvedCount
            End If
            If instrumentZone.sampleIndex < 0 Then
                If instrumentBagIndex = firstInstrumentBag Then
                    instrumentGlobal = instrumentZone
                End If
                Continue For
            End If
            If soundfontBank_StateMatches(instrumentZone, keyNumber, velocity) = 0 Then
                Continue For
            End If
            If resolvedCount >= regionCapacity OrElse _
                resolvedCount >= OSE_SOUNDFONT_MAX_REGIONS_PER_NOTE Then
                Return resolvedCount
            End If
            soundfontBank_CombinePreset instrumentZone, presetZone
            If soundfontBank_BuildRegion(instrumentZone, _
                regions(LBound(regions) + resolvedCount)) <> 0 Then
                resolvedCount += 1
            End If
        Next
    Next
    Return resolvedCount
End Function


Public Function soundfontBank_Resolve( _
    ByVal bankNumber As Integer, _
    ByVal programNumber As Integer, _
    ByVal keyNumber As Integer, _
    ByVal velocity As Integer, _
    regions() As OseSoundFontVoiceRegion _
) As Integer
    If soundfontBank_IsLoaded() = 0 OrElse bankNumber < 0 OrElse _
        bankNumber > 16383 OrElse programNumber < 0 OrElse _
        programNumber > 127 OrElse keyNumber < 0 OrElse keyNumber > 127 OrElse _
        velocity < 1 OrElse velocity > 127 Then
        Return 0
    End If
    Dim As Integer fallbackBanks(0 To 2) = {bankNumber, bankNumber Shr 7, 0}
    For fallbackIndex As Integer = 0 To 2
        Dim As Integer wantedBank = fallbackBanks(fallbackIndex)
        Dim As Integer duplicateBank
        For previousIndex As Integer = 0 To fallbackIndex - 1
            If fallbackBanks(previousIndex) = wantedBank Then
                duplicateBank = -1
            End If
        Next
        If duplicateBank <> 0 Then
            Continue For
        End If
        For presetIndex As Integer = 0 To soundfontBank_Active.presetCount - 1
            If soundfontBank_Active.presets[presetIndex].bankNumber = wantedBank AndAlso _
                soundfontBank_Active.presets[presetIndex].programNumber = _
                programNumber Then
                Dim As Integer regionCount = soundfontBank_ResolvePreset( _
                    presetIndex, keyNumber, velocity, regions())
                If regionCount > 0 Then
                    Return regionCount
                End If
            End If
        Next
    Next
    If programNumber <> 0 Then
        For presetIndex As Integer = 0 To soundfontBank_Active.presetCount - 1
            If soundfontBank_Active.presets[presetIndex].bankNumber = 0 AndAlso _
                soundfontBank_Active.presets[presetIndex].programNumber = 0 Then
                Return soundfontBank_ResolvePreset( _
                    presetIndex, keyNumber, velocity, regions())
            End If
        Next
    End If
    Return 0
End Function

' -------------------------------------------------------------------------
' Immutable bank inspection
' -------------------------------------------------------------------------

Public Function soundfontBank_IsLoaded() As Integer
    Return IIf(soundfontBank_Active.sampleData <> 0 AndAlso _
        soundfontBank_Active.presetCount > 0 AndAlso _
        soundfontBank_Active.sampleHeaderCount > 0, -1, 0)
End Function


Public Function soundfontBank_GetFilename() As String
    Return soundfontBank_Active.filename
End Function


Public Function soundfontBank_GetName() As String
    Return soundfontBank_Active.bankName
End Function


Public Function soundfontBank_GetPresetCount() As Integer
    Return soundfontBank_Active.presetCount
End Function


Public Function soundfontBank_GetSampleHeaderCount() As Integer
    Return soundfontBank_Active.sampleHeaderCount
End Function


Public Function soundfontBank_GetSamplePointCount() As ULongInt
    Return soundfontBank_Active.samplePointCount
End Function


Public Function soundfontBank_GetSampleData() As Short Ptr
    Return soundfontBank_Active.sampleData
End Function


Public Function soundfontBank_HasPreset( _
    ByVal bankNumber As Integer, _
    ByVal programNumber As Integer _
) As Integer
    If soundfontBank_IsLoaded() = 0 OrElse bankNumber < 0 OrElse _
        bankNumber > 16383 OrElse programNumber < 0 OrElse _
        programNumber > 127 Then
        Return 0
    End If
    For presetIndex As Integer = 0 To soundfontBank_Active.presetCount - 1
        If soundfontBank_Active.presets[presetIndex].bankNumber = bankNumber AndAlso _
            soundfontBank_Active.presets[presetIndex].programNumber = _
            programNumber Then
            Return -1
        End If
    Next
    Return 0
End Function

/' end of soundfont_bank.bas '/
