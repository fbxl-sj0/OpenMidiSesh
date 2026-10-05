/'
    Project: OpenSesh
    ---------------------------

    File: music_export.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements music_export.bi; declarations there define the shared interface.

    Purpose:

        Convert the editor's bounded MIDI note model into a playable
        four-channel ProTracker module.

    Responsibilities:

        - quantize MIDI timing to four ProTracker rows per quarter note
        - reduce arbitrary MIDI polyphony to four deterministic tracker voices
        - generate compact looping instrument waveforms without external assets
        - emit the public 31-sample M.K. module layout in big-endian form
        - report every material timing, pitch, and voice reduction

    Resource ownership:

        The shared atomic writer owns its temporary file and replaces the
        destination only after verifying every byte. Conversion buffers are
        managed FreeBASIC strings or arrays released automatically on return.

    This file intentionally does NOT contain:

        - a tracker editor or MOD playback engine
        - sfxlib output capture
        - omaGui widgets or application status messages
'/

#lang "fb"

#include once "music_export.bi"
#include once "atomic_file_internal.bi"

' -------------------------------------------------------------------------
' ProTracker layout
' -------------------------------------------------------------------------

Const MOD_TITLE_BYTES As Integer = 20
Const MOD_SAMPLE_COUNT As Integer = 31
Const MOD_SAMPLE_HEADER_BYTES As Integer = 30
Const MOD_SAMPLE_NAME_BYTES As Integer = 22
Const MOD_ORDER_BYTES As Integer = 128
Const MOD_HEADER_BYTES As Integer = 1084
Const MOD_PATTERN_BYTES As Integer = 1024
Const MOD_CELL_BYTES As Integer = 4
Const MOD_SAMPLE_WAVE_BYTES As Integer = 64
Const MOD_ROWS_PER_QUARTER As Integer = 4
Const MOD_LOWEST_KEY As Integer = 24
Const MOD_HIGHEST_KEY As Integer = 71
Const MOD_LOWEST_PERIOD As Integer = 1712
Const MOD_HIGHEST_PERIOD As Integer = 113
Const MOD_DEFAULT_TEMPO As Integer = 125
Const MOD_MIN_TEMPO As Integer = 32
Const MOD_MAX_TEMPO As Integer = 255
Const MOD_AMIGA_CLOCK As Double = 7093789.2
Const MOD_TWO_PI As Double = 6.2831853071795864769

Type ModPreparedNote
    As Integer sourceIndex
    As Integer startRow
    As Integer endRow
    As Integer keyNumber
    As Integer midiChannel
    As Integer velocity
    As Integer assignedChannel
    As Integer offRow
    As Integer offRequired
    As Integer written
End Type

' -------------------------------------------------------------------------
' Binary helpers
' -------------------------------------------------------------------------

Private Sub mod_AppendByte(ByRef outputData As String, ByVal byteValue As Integer)
    outputData += Chr(byteValue And &HFF)
End Sub


Private Sub mod_AppendBe16(ByRef outputData As String, ByVal wordValue As Integer)
    mod_AppendByte outputData, (wordValue Shr 8) And &HFF
    mod_AppendByte outputData, wordValue And &HFF
End Sub


Private Function mod_FixedAscii( _
    ByVal sourceText As String, _
    ByVal fieldWidth As Integer _
) As String
    If fieldWidth <= 0 Then
        Return ""
    End If

    Dim As String resultText = Left(sourceText, fieldWidth)
    For characterIndex As Integer = 1 To Len(resultText)
        Dim As Integer characterValue = Asc(Mid(resultText, characterIndex, 1))
        If characterValue < 32 OrElse characterValue > 126 Then _
            Mid(resultText, characterIndex, 1) = " "
    Next
    If Len(resultText) < fieldWidth Then _
        resultText += String(fieldWidth - Len(resultText), Chr(0))
    Return resultText
End Function


Private Function mod_GetPatternByte( _
    ByRef patternData As String, _
    ByVal byteOffset As Integer _
) As Integer
    If byteOffset < 0 OrElse byteOffset >= Len(patternData) Then
        Return 0
    End If
    Return Asc(Mid(patternData, byteOffset + 1, 1))
End Function


Private Sub mod_SetPatternByte( _
    ByRef patternData As String, _
    ByVal byteOffset As Integer, _
    ByVal byteValue As Integer _
)
    If byteOffset < 0 OrElse byteOffset >= Len(patternData) Then
        Exit Sub
    End If
    Mid(patternData, byteOffset + 1, 1) = Chr(byteValue And &HFF)
End Sub


Private Function mod_CellOffset( _
    ByVal rowIndex As Integer, _
    ByVal channelIndex As Integer _
) As Integer
    If rowIndex < 0 OrElse rowIndex >= OSE_MOD_EXPORT_MAX_ROWS OrElse _
        channelIndex < 0 OrElse channelIndex >= OSE_MOD_EXPORT_CHANNELS Then _
        Return -1
    Return rowIndex * OSE_MOD_EXPORT_CHANNELS * MOD_CELL_BYTES + _
        channelIndex * MOD_CELL_BYTES
End Function


Private Sub mod_SetCell( _
    ByRef patternData As String, _
    ByVal rowIndex As Integer, _
    ByVal channelIndex As Integer, _
    ByVal sampleIndex As Integer, _
    ByVal periodValue As Integer, _
    ByVal effectNumber As Integer, _
    ByVal effectParameter As Integer _
)
    Dim As Integer byteOffset = mod_CellOffset(rowIndex, channelIndex)
    If byteOffset < 0 Then
        Exit Sub
    End If

    mod_SetPatternByte patternData, byteOffset, _
        (sampleIndex And &HF0) Or ((periodValue Shr 8) And &H0F)
    mod_SetPatternByte patternData, byteOffset + 1, periodValue And &HFF
    mod_SetPatternByte patternData, byteOffset + 2, _
        ((sampleIndex And &H0F) Shl 4) Or (effectNumber And &H0F)
    mod_SetPatternByte patternData, byteOffset + 3, effectParameter And &HFF
End Sub


Private Sub mod_SetCellEffect( _
    ByRef patternData As String, _
    ByVal rowIndex As Integer, _
    ByVal channelIndex As Integer, _
    ByVal effectNumber As Integer, _
    ByVal effectParameter As Integer _
)
    Dim As Integer byteOffset = mod_CellOffset(rowIndex, channelIndex)
    If byteOffset < 0 Then
        Exit Sub
    End If
    Dim As Integer sampleLowByte = mod_GetPatternByte(patternData, byteOffset + 2)
    mod_SetPatternByte patternData, byteOffset + 2, _
        (sampleLowByte And &HF0) Or (effectNumber And &H0F)
    mod_SetPatternByte patternData, byteOffset + 3, effectParameter And &HFF
End Sub

' -------------------------------------------------------------------------
' Timing and pitch conversion
' -------------------------------------------------------------------------

Private Function mod_RowForTick( _
    ByVal tickValue As ULongInt, _
    ByVal division As Integer _
) As LongInt
    If division <= 0 Then
        Return -1
    End If
    Dim As Double exactRow = (CDbl(tickValue) * MOD_ROWS_PER_QUARTER) / _
        CDbl(division)
    If exactRow < 0.0 OrElse exactRow > 2147483647.0 Then
        Return 2147483647
    End If
    Return CLngInt(Int(exactRow + 0.5))
End Function


Private Function mod_PeriodForKey( _
    ByVal sourceKey As Integer, _
    ByRef octaveFolded As Integer _
) As Integer
    Dim As Integer trackerKey = sourceKey
    octaveFolded = 0
    While trackerKey < MOD_LOWEST_KEY
        trackerKey += 12
        octaveFolded = -1
    Wend
    While trackerKey > MOD_HIGHEST_KEY
        trackerKey -= 12
        octaveFolded = -1
    Wend

    Dim As Double frequency = 440.0 * _
        (2.0 ^ (CDbl(trackerKey - 69) / 12.0))
    Dim As Double exactPeriod = MOD_AMIGA_CLOCK / _
        (2.0 * MOD_SAMPLE_WAVE_BYTES * frequency)
    Dim As Integer periodValue = CInt(Int(exactPeriod + 0.5))
    If periodValue > MOD_LOWEST_PERIOD Then
        periodValue = MOD_LOWEST_PERIOD
    End If
    If periodValue < MOD_HIGHEST_PERIOD Then
        periodValue = MOD_HIGHEST_PERIOD
    End If
    Return periodValue
End Function


Private Function mod_TempoForMicroseconds( _
    ByVal microsecondsPerQuarter As ULong, _
    ByRef wasClamped As Integer _
) As Integer
    If microsecondsPerQuarter = 0 Then
        microsecondsPerQuarter = 500000
    End If
    Dim As Integer tempoValue = CInt(Int( _
        60000000.0 / CDbl(microsecondsPerQuarter) + 0.5))
    wasClamped = 0
    If tempoValue < MOD_MIN_TEMPO Then
        tempoValue = MOD_MIN_TEMPO
        wasClamped = -1
    ElseIf tempoValue > MOD_MAX_TEMPO Then
        tempoValue = MOD_MAX_TEMPO
        wasClamped = -1
    End If
    Return tempoValue
End Function

' -------------------------------------------------------------------------
' Prepared-note ordering
' -------------------------------------------------------------------------

Private Function mod_NoteBefore( _
    ByRef leftNote As ModPreparedNote, _
    ByRef rightNote As ModPreparedNote _
) As Integer
    If leftNote.startRow < rightNote.startRow Then
        Return -1
    End If
    If leftNote.startRow > rightNote.startRow Then
        Return 0
    End If
    ' Keep the four strongest attacks when more than four notes quantize to
    ' one tracker row. Source order remains the final deterministic tie-break.
    If leftNote.velocity > rightNote.velocity Then
        Return -1
    End If
    If leftNote.velocity < rightNote.velocity Then
        Return 0
    End If
    If leftNote.midiChannel < rightNote.midiChannel Then
        Return -1
    End If
    If leftNote.midiChannel > rightNote.midiChannel Then
        Return 0
    End If
    Return IIf(leftNote.sourceIndex < rightNote.sourceIndex, -1, 0)
End Function


Private Sub mod_SortNotes( _
    preparedNotes() As ModPreparedNote, _
    ByVal firstIndex As Integer, _
    ByVal lastIndex As Integer _
)
    Dim As Integer leftIndex = firstIndex
    Dim As Integer rightIndex = lastIndex
    Dim As ModPreparedNote pivotNote = _
        preparedNotes(firstIndex + (lastIndex - firstIndex) \ 2)

    Do
        While mod_NoteBefore(preparedNotes(leftIndex), pivotNote) <> 0
            leftIndex += 1
        Wend
        While mod_NoteBefore(pivotNote, preparedNotes(rightIndex)) <> 0
            rightIndex -= 1
        Wend
        If leftIndex <= rightIndex Then
            Swap preparedNotes(leftIndex), preparedNotes(rightIndex)
            leftIndex += 1
            rightIndex -= 1
        End If
    Loop Until leftIndex > rightIndex

    If firstIndex < rightIndex Then _
        mod_SortNotes preparedNotes(), firstIndex, rightIndex
    If leftIndex < lastIndex Then _
        mod_SortNotes preparedNotes(), leftIndex, lastIndex
End Sub

' -------------------------------------------------------------------------
' Generated tracker instruments
' -------------------------------------------------------------------------

Private Function mod_WaveSample( _
    ByVal sampleIndex As Integer, _
    ByVal programNumber As Integer, _
    ByVal pointIndex As Integer _
) As Integer
    Dim As Double phase = CDbl(pointIndex) / MOD_SAMPLE_WAVE_BYTES
    Dim As Double waveValue
    Dim As Integer familyIndex = (programNumber \ 8) And 7

    Select Case familyIndex
        Case 0
            waveValue = Sin(MOD_TWO_PI * phase)
        Case 1
            waveValue = 1.0 - 4.0 * Abs(phase - 0.5)
        Case 2
            waveValue = 2.0 * phase - 1.0
        Case 3
            If phase < 0.5 Then
                waveValue = 1.0
            Else
                waveValue = -1.0
            End If
        Case 4
            If phase < 0.25 Then
                waveValue = 1.0
            Else
                waveValue = -0.55
            End If
        Case 5
            waveValue = Sin(MOD_TWO_PI * phase) * 0.72 + _
                Sin(MOD_TWO_PI * phase * 3.0) * 0.28
        Case 6
            waveValue = Sin(MOD_TWO_PI * phase) * 0.55 + _
                (2.0 * phase - 1.0) * 0.45
        Case Else
            ' Percussion and effects channels use a deterministic periodic
            ' noise table so identical exports remain byte-for-byte stable.
            waveValue = Sin(CDbl((pointIndex + 1) * _
                (sampleIndex * 37 + 113)))
    End Select

    Dim As Integer pcmValue
    If waveValue >= 0.0 Then
        pcmValue = CInt(Int(waveValue * 110.0 + 0.5))
    Else
        pcmValue = CInt(Int(waveValue * 110.0 - 0.5))
    End If
    If pcmValue < -127 Then
        pcmValue = -127
    End If
    If pcmValue > 127 Then
        pcmValue = 127
    End If
    Return pcmValue
End Function


Private Function mod_BuildSampleData( _
    ByVal sampleIndex As Integer, _
    ByVal programNumber As Integer _
) As String
    Dim As String sampleData
    For pointIndex As Integer = 0 To MOD_SAMPLE_WAVE_BYTES - 1
        mod_AppendByte sampleData, _
            mod_WaveSample(sampleIndex, programNumber, pointIndex)
    Next
    Return sampleData
End Function

' -------------------------------------------------------------------------
' Pattern construction
' -------------------------------------------------------------------------

Private Function mod_ChannelVolume( _
    ByRef summary As MidiSummary, _
    ByVal midiChannel As Integer, _
    ByVal velocity As Integer _
) As Integer
    If midiChannel < 0 OrElse midiChannel > 15 Then
        Return 0
    End If
    Dim As Double scaledVolume = CDbl(velocity) * _
        CDbl(summary.channelVolume(midiChannel)) * _
        CDbl(summary.channelExpression(midiChannel))
    scaledVolume = (scaledVolume * 64.0) / (127.0 * 127.0 * 127.0)
    Dim As Integer trackerVolume = CInt(Int(scaledVolume + 0.5))
    If trackerVolume < 0 Then
        trackerVolume = 0
    End If
    If trackerVolume > 64 Then
        trackerVolume = 64
    End If
    Return trackerVolume
End Function


Private Sub mod_PlaceTempo( _
    ByRef patternData As String, _
    ByVal rowIndex As Integer, _
    ByVal tempoValue As Integer _
)
    Dim As Integer selectedChannel = OSE_MOD_EXPORT_CHANNELS - 1
    For channelIndex As Integer = OSE_MOD_EXPORT_CHANNELS - 1 To 0 Step -1
        Dim As Integer byteOffset = mod_CellOffset(rowIndex, channelIndex)
        Dim As Integer effectByte = mod_GetPatternByte( _
            patternData, byteOffset + 2) And &H0F
        If effectByte = 0 Then
            selectedChannel = channelIndex
            Exit For
        End If
    Next
    mod_SetCellEffect patternData, rowIndex, selectedChannel, &HF, tempoValue
End Sub


Private Sub mod_WriteTempoMap( _
    ByRef summary As MidiSummary, _
    ByRef patternData As String, _
    ByVal lastMusicRow As Integer, _
    ByRef report As OseModExportReport _
)
    Dim As Integer hasInitialTempo = 0
    For tempoIndex As Integer = 0 To summary.tempoCount - 1
        Dim As MidiTempoPoint tempoPoint = summary.tempoMap(tempoIndex)
        Dim As LongInt tempoRow = mod_RowForTick(tempoPoint.tick, summary.division)
        If tempoRow < 0 OrElse tempoRow > lastMusicRow OrElse _
            tempoRow >= OSE_MOD_EXPORT_MAX_ROWS Then Continue For
        If tempoRow = 0 Then
            hasInitialTempo = -1
        End If
        Dim As Integer wasClamped
        Dim As Integer tempoValue = mod_TempoForMicroseconds( _
            tempoPoint.microsecondsPerQuarter, wasClamped)
        mod_PlaceTempo patternData, CInt(tempoRow), tempoValue
        report.tempoEventsWritten += 1
        If wasClamped <> 0 Then
            report.tempoEventsClamped += 1
        End If
    Next

    If hasInitialTempo = 0 Then
        Dim As Integer wasClamped
        Dim As ULong initialMicroseconds = summary.tempoMicrosecondsPerQuarter
        If initialMicroseconds = 0 Then
            initialMicroseconds = 500000
        End If
        Dim As Integer tempoValue = mod_TempoForMicroseconds( _
            initialMicroseconds, wasClamped)
        mod_PlaceTempo patternData, 0, tempoValue
        report.tempoEventsWritten += 1
        If wasClamped <> 0 Then
            report.tempoEventsClamped += 1
        End If
    End If
End Sub

' -------------------------------------------------------------------------
' Public exporter
' -------------------------------------------------------------------------

' This routine deliberately presents the conversion as one transaction. Its
' branches validate independent format limits and all converge before I/O.
' fblint: disable-next-line FBL111 REASON: Independent format-limit branches converge before the single output transaction.
Function musicExport_SaveMod( _
    ByRef summary As MidiSummary, _
    ByVal filename As String, _
    ByRef report As OseModExportReport _
) As Integer
    Dim As OseModExportReport emptyReport
    report = emptyReport

    filename = Trim(filename)
    If filename = "" Then
        report.errorText = "No MOD output filename was supplied."
        Return 0
    End If
    If summary.division <= 0 Then
        report.errorText = "The document does not use supported metric MIDI timing."
        Return 0
    End If

    Dim As Integer sourceNoteCount = midi_GetEditableNoteCount()
    If sourceNoteCount <= 0 OrElse sourceNoteCount > OSE_MAX_EDITABLE_NOTES Then
        report.errorText = "The document has no notes to export."
        Return 0
    End If

    ReDim As ModPreparedNote preparedNotes(0 To sourceNoteCount - 1)
    Dim As Integer preparedCount
    For sourceIndex As Integer = 0 To sourceNoteCount - 1
        Dim As MidiEditableNote sourceNote
        If midi_GetEditableNote(sourceIndex, sourceNote) = 0 Then
            Continue For
        End If
        report.notesConsidered += 1

        Dim As LongInt startRow = mod_RowForTick( _
            sourceNote.startTick, summary.division)
        If startRow < 0 OrElse startRow >= OSE_MOD_EXPORT_MAX_ROWS Then
            report.notesTruncated += 1
            Continue For
        End If

        Dim As ULongInt endTick = sourceNote.startTick
        If sourceNote.durationTicks > OSE_MAX_MIDI_TICK - endTick Then
            endTick = OSE_MAX_MIDI_TICK
        Else
            endTick += sourceNote.durationTicks
        End If
        Dim As LongInt endRow = mod_RowForTick(endTick, summary.division)
        If endRow <= startRow Then
            endRow = startRow + 1
        End If
        If endRow > OSE_MOD_EXPORT_MAX_ROWS Then
            endRow = OSE_MOD_EXPORT_MAX_ROWS
            report.notesTruncated += 1
        End If

        With preparedNotes(preparedCount)
            .sourceIndex = sourceIndex
            .startRow = CInt(startRow)
            .endRow = CInt(endRow)
            .keyNumber = sourceNote.keyNumber
            .midiChannel = sourceNote.channel
            .velocity = sourceNote.velocity
            .assignedChannel = -1
            .offRow = CInt(endRow)
        End With
        preparedCount += 1
    Next

    If preparedCount <= 0 Then
        report.errorText = "Every note falls beyond the ProTracker timeline limit."
        Return 0
    End If
    If preparedCount > 1 Then _
        mod_SortNotes preparedNotes(), 0, preparedCount - 1

    Dim As String patternData = String( _
        OSE_MOD_EXPORT_MAX_PATTERNS * MOD_PATTERN_BYTES, Chr(0))
    Dim As Integer activeEndRow(0 To OSE_MOD_EXPORT_CHANNELS - 1)
    Dim As Integer lastAssignment(0 To OSE_MOD_EXPORT_CHANNELS - 1)
    Dim As Integer rowUsed(0 To OSE_MOD_EXPORT_CHANNELS - 1)
    For channelIndex As Integer = 0 To OSE_MOD_EXPORT_CHANNELS - 1
        lastAssignment(channelIndex) = -1
    Next

    Dim As Integer currentRow = -1
    Dim As Integer maximumUsedRow
    For preparedIndex As Integer = 0 To preparedCount - 1
        Dim As ModPreparedNote Ptr preparedNote = @preparedNotes(preparedIndex)
        If preparedNote->startRow <> currentRow Then
            currentRow = preparedNote->startRow
            For channelIndex As Integer = 0 To OSE_MOD_EXPORT_CHANNELS - 1
                rowUsed(channelIndex) = 0
            Next
        End If

        Dim As Integer preferredChannel = preparedNote->midiChannel Mod _ ' fblint: disable-line FBL406 REASON: The validated MIDI channel is nonnegative; the negative sentinel is the next declaration.
            OSE_MOD_EXPORT_CHANNELS
        Dim As Integer selectedChannel = -1
        If rowUsed(preferredChannel) = 0 AndAlso _
            activeEndRow(preferredChannel) <= preparedNote->startRow Then _
            selectedChannel = preferredChannel

        If selectedChannel < 0 Then
            For channelIndex As Integer = 0 To OSE_MOD_EXPORT_CHANNELS - 1
                If rowUsed(channelIndex) = 0 AndAlso _
                    activeEndRow(channelIndex) <= preparedNote->startRow Then
                    selectedChannel = channelIndex
                    Exit For
                End If
            Next
        End If

        If selectedChannel < 0 Then
            Dim As Integer earliestEndRow = OSE_MOD_EXPORT_MAX_ROWS + 1
            For channelIndex As Integer = 0 To OSE_MOD_EXPORT_CHANNELS - 1
                If rowUsed(channelIndex) = 0 AndAlso _
                    activeEndRow(channelIndex) < earliestEndRow Then
                    earliestEndRow = activeEndRow(channelIndex)
                    selectedChannel = channelIndex
                End If
            Next
            If selectedChannel >= 0 Then
                report.voiceSteals += 1
            End If
        End If

        If selectedChannel < 0 Then
            report.notesDropped += 1
            Continue For
        End If

        Dim As Integer previousAssignment = lastAssignment(selectedChannel)
        If previousAssignment >= 0 Then
            If preparedNotes(previousAssignment).endRow < preparedNote->startRow Then
                preparedNotes(previousAssignment).offRow = _
                    preparedNotes(previousAssignment).endRow
                preparedNotes(previousAssignment).offRequired = -1
            Else
                preparedNotes(previousAssignment).offRow = preparedNote->startRow
                preparedNotes(previousAssignment).offRequired = 0
            End If
        End If

        Dim As Integer octaveFolded
        Dim As Integer periodValue = mod_PeriodForKey( _
            preparedNote->keyNumber, octaveFolded)
        If octaveFolded <> 0 Then
            report.octaveFoldedNotes += 1
        End If
        Dim As Integer sampleIndex = preparedNote->midiChannel + 1
        If sampleIndex < 1 Then
            sampleIndex = 1
        End If
        If sampleIndex > 16 Then
            sampleIndex = 16
        End If
        Dim As Integer trackerVolume = mod_ChannelVolume( _
            summary, preparedNote->midiChannel, preparedNote->velocity)

        mod_SetCell patternData, preparedNote->startRow, selectedChannel, _
            sampleIndex, periodValue, &HC, trackerVolume
        preparedNote->assignedChannel = selectedChannel
        preparedNote->written = -1
        activeEndRow(selectedChannel) = preparedNote->endRow
        lastAssignment(selectedChannel) = preparedIndex
        rowUsed(selectedChannel) = -1
        report.notesWritten += 1
        If preparedNote->startRow > maximumUsedRow Then _
            maximumUsedRow = preparedNote->startRow
    Next

    For channelIndex As Integer = 0 To OSE_MOD_EXPORT_CHANNELS - 1
        Dim As Integer preparedIndex = lastAssignment(channelIndex)
        If preparedIndex >= 0 AndAlso _
            preparedNotes(preparedIndex).endRow < OSE_MOD_EXPORT_MAX_ROWS Then
            preparedNotes(preparedIndex).offRow = preparedNotes(preparedIndex).endRow
            preparedNotes(preparedIndex).offRequired = -1
        End If
    Next

    For preparedIndex As Integer = 0 To preparedCount - 1
        Dim As ModPreparedNote Ptr preparedNote = @preparedNotes(preparedIndex)
        If preparedNote->written = 0 OrElse preparedNote->offRequired = 0 OrElse _
            preparedNote->offRow <= preparedNote->startRow OrElse _
            preparedNote->offRow >= OSE_MOD_EXPORT_MAX_ROWS Then Continue For
        mod_SetCell patternData, preparedNote->offRow, _
            preparedNote->assignedChannel, 0, 0, &HC, 0
        If preparedNote->offRow > maximumUsedRow Then _
            maximumUsedRow = preparedNote->offRow
    Next

    If report.notesWritten <= 0 Then
        report.errorText = "No notes fit the four ProTracker channels."
        Return 0
    End If

    mod_WriteTempoMap summary, patternData, maximumUsedRow, report
    report.patternCount = maximumUsedRow \ OSE_MOD_EXPORT_ROWS_PER_PATTERN + 1
    If report.patternCount < 1 Then
        report.patternCount = 1
    End If
    If report.patternCount > OSE_MOD_EXPORT_MAX_PATTERNS Then _
        report.patternCount = OSE_MOD_EXPORT_MAX_PATTERNS
    report.durationRows = maximumUsedRow + 1

    Dim As String titleText = Trim(summary.documentTitle)
    If titleText = "" Then
        titleText = "OpenSesh"
    End If
    Dim As String outputData = mod_FixedAscii(titleText, MOD_TITLE_BYTES)

    For sampleIndex As Integer = 1 To MOD_SAMPLE_COUNT
        If sampleIndex <= 16 Then
            Dim As Integer midiChannel = sampleIndex - 1
            Dim As Integer programNumber = summary.channelProgram(midiChannel)
            Dim As String sampleName = "Ch " + LTrim(Str(sampleIndex)) + _
                " Program " + LTrim(Str(programNumber + 1))
            ' Thirty-one fixed headers are a bounded binary-image assembly.
            ' fblint: disable-next-line FBL503 REASON: A fixed number of sample headers is appended to the bounded binary image.
            outputData += mod_FixedAscii(sampleName, MOD_SAMPLE_NAME_BYTES)
            mod_AppendBe16 outputData, MOD_SAMPLE_WAVE_BYTES \ 2
            mod_AppendByte outputData, 0
            Dim As Integer defaultVolume = CInt(Int( _
                CDbl(summary.channelVolume(midiChannel)) * 64.0 / 127.0 + 0.5))
            If defaultVolume < 0 Then
                defaultVolume = 0
            End If
            If defaultVolume > 64 Then
                defaultVolume = 64
            End If
            mod_AppendByte outputData, defaultVolume
            mod_AppendBe16 outputData, 0
            mod_AppendBe16 outputData, MOD_SAMPLE_WAVE_BYTES \ 2
        Else
            ' The remaining fifteen empty headers are another fixed-size loop.
            ' fblint: disable-next-line FBL503 REASON: A fixed number of sample headers is appended to the bounded binary image.
            outputData += mod_FixedAscii("", MOD_SAMPLE_NAME_BYTES)
            mod_AppendBe16 outputData, 0
            mod_AppendByte outputData, 0
            mod_AppendByte outputData, 0
            mod_AppendBe16 outputData, 0
            mod_AppendBe16 outputData, 1
        End If
    Next

    mod_AppendByte outputData, report.patternCount
    mod_AppendByte outputData, 127
    For orderIndex As Integer = 0 To MOD_ORDER_BYTES - 1
        If orderIndex < report.patternCount Then
            mod_AppendByte outputData, orderIndex
        Else
            mod_AppendByte outputData, 0
        End If
    Next
    outputData += "M.K."
    outputData += Left(patternData, report.patternCount * MOD_PATTERN_BYTES)
    For sampleIndex As Integer = 1 To 16
        outputData += mod_BuildSampleData(sampleIndex, _
            summary.channelProgram(sampleIndex - 1))
    Next

    Dim As Integer expectedBytes = MOD_HEADER_BYTES + _
        report.patternCount * MOD_PATTERN_BYTES + _
        16 * MOD_SAMPLE_WAVE_BYTES
    If Len(outputData) <> expectedBytes Then
        report.errorText = "The internal MOD image failed its size check."
        Return 0
    End If

    If atomicFile_WriteVerified(filename, outputData) = 0 Then
        report.errorText = "The MOD output could not be safely replaced; the previous file was preserved."
        Return 0
    End If
    Return -1
End Function

/' end of music_export.bas '/
