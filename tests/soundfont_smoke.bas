/'
    Project: OpenSesh
    ---------------------------

    File: tests/soundfont_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove that a real SF2 bank is validated, resolved, and rendered.

    Responsibilities:

        - construct a small standards-shaped SoundFont 2 fixture
        - verify RIFF, Hydra, preset fallback, and malformed-file handling
        - render a pitched sample voice and require meaningful PCM output
        - start and stop the production worker through the null audio driver

    This file intentionally does NOT contain:

        - third-party synthesizer code
        - a desktop window or graphical input
        - a copyrighted or redistributed SoundFont bank
'/

#lang "fb"

#include once "../src/soundfont_bank.bi"
#include once "../src/soundfont_synth.bi"
#include once "../src/sfx_runtime.bi"

Private Sub test_Fail(ByVal messageText As String)
    soundfontSynth_Shutdown()
    sfxRuntime_Shutdown()
    Print "FAIL: "; messageText
    End 1
End Sub


Private Function test_Le16(ByVal value As Integer) As String
    Dim As UInteger boundedValue = CUInt(value) And &HFFFF
    Return Chr(boundedValue And 255) + Chr((boundedValue Shr 8) And 255)
End Function


Private Function test_Le32(ByVal value As ULongInt) As String
    Return Chr(value And 255) + _
        Chr((value Shr 8) And 255) + _
        Chr((value Shr 16) And 255) + _
        Chr((value Shr 24) And 255)
End Function


Private Function test_FixedText( _
    ByVal textValue As String, _
    ByVal fieldBytes As Integer _
) As String
    If fieldBytes <= 0 Then
        Return ""
    End If
    Return Left(textValue + Chr(0) + Space(fieldBytes), fieldBytes)
End Function


Private Function test_Chunk( _
    ByVal chunkId As String, _
    ByVal payload As String _
) As String
    Dim As String paddedPayload = payload
    If (Len(paddedPayload) And 1) <> 0 Then
        paddedPayload += Chr(0)
    End If
    Return chunkId + test_Le32(Len(payload)) + paddedPayload
End Function


Private Function test_Generator( _
    ByVal operatorNumber As Integer, _
    ByVal amount As Integer _
) As String
    Return test_Le16(operatorNumber) + test_Le16(amount)
End Function


Private Function test_PresetHeader( _
    ByVal presetName As String, _
    ByVal programNumber As Integer, _
    ByVal bankNumber As Integer, _
    ByVal bagIndex As Integer _
) As String
    Return test_FixedText(presetName, 20) + _
        test_Le16(programNumber) + test_Le16(bankNumber) + _
        test_Le16(bagIndex) + test_Le32(0) + test_Le32(0) + test_Le32(0)
End Function


Private Function test_InstrumentHeader( _
    ByVal instrumentName As String, _
    ByVal bagIndex As Integer _
) As String
    Return test_FixedText(instrumentName, 20) + test_Le16(bagIndex)
End Function


Private Function test_SampleHeader( _
    ByVal sampleName As String, _
    ByVal startPoint As ULongInt, _
    ByVal endPoint As ULongInt, _
    ByVal loopStart As ULongInt, _
    ByVal loopEnd As ULongInt, _
    ByVal sampleRate As ULongInt, _
    ByVal originalPitch As Integer, _
    ByVal sampleType As Integer _
) As String
    Return test_FixedText(sampleName, 20) + _
        test_Le32(startPoint) + test_Le32(endPoint) + _
        test_Le32(loopStart) + test_Le32(loopEnd) + _
        test_Le32(sampleRate) + Chr(originalPitch And 255) + Chr(0) + _
        test_Le16(0) + test_Le16(sampleType)
End Function


Private Sub test_AppendBag( _
    ByRef bagData As String, _
    ByRef generatorData As String, _
    ByVal zoneData As String _
)
    ' Hydra bag indexes count four-byte generator records, including globals.
    bagData += test_Le16(Len(generatorData) \ 4) + test_Le16(0)
    generatorData += zoneData
End Sub


Private Function test_CreateSoundFont( _
    ByVal presetGlobal As String = "", _
    ByVal presetLocal As String = "", _
    ByVal instrumentGlobal As String = "", _
    ByVal instrumentLocal As String = "" _
) As String
    Const samplePointCount As Integer = 512
    Const audibleSamplePoints As Integer = 128
    Dim As String sampleData
    For sampleIndex As Integer = 0 To samplePointCount - 1
        Dim As Integer sampleValue
        If sampleIndex < audibleSamplePoints * 3 Then
            sampleValue = CInt(Sin(CDbl(sampleIndex) * 6.283185307179586 / _
                32.0) * 14000.0)
        End If
        sampleData += test_Le16(sampleValue)
    Next

    Dim As String infoPayload = _
        test_Chunk("ifil", test_Le16(2) + test_Le16(1)) + _
        test_Chunk("isng", "EMU8000" + Chr(0)) + _
        test_Chunk("INAM", "OpenSesh Test Bank" + Chr(0))
    Dim As String samplePayload = test_Chunk("smpl", sampleData)

    Dim As Integer monoPresetBags = IIf(presetGlobal = "", 1, 2)
    Dim As String presetHeaders = _
        test_PresetHeader("Test Sine", 0, 0, 0) + _
        test_PresetHeader("Test Stereo", 1, 0, monoPresetBags) + _
        test_PresetHeader("EOP", 0, 0, monoPresetBags + 1)
    Dim As String presetBags, presetGenerators
    If presetGlobal <> "" Then _
        test_AppendBag presetBags, presetGenerators, presetGlobal
    test_AppendBag presetBags, presetGenerators, presetLocal + test_Generator(41, 0)
    test_AppendBag presetBags, presetGenerators, test_Generator(41, 1)
    test_AppendBag presetBags, presetGenerators, test_Generator(0, 0)
    Dim As Integer monoInstrumentBags = IIf(instrumentGlobal = "", 1, 2)
    Dim As String instrumentHeaders = _
        test_InstrumentHeader("Test Instrument", 0) + _
        test_InstrumentHeader("Stereo Instrument", monoInstrumentBags) + _
        test_InstrumentHeader("EOI", monoInstrumentBags + 2)
    Dim As String instrumentBags, instrumentGenerators
    If instrumentGlobal <> "" Then _
        test_AppendBag instrumentBags, instrumentGenerators, instrumentGlobal
    If instrumentLocal = "" Then
        instrumentLocal = test_Generator(43, &H7F00) + _
            test_Generator(54, 1) + test_Generator(34, -12000) + _
            test_Generator(38, -7973)
    End If
    test_AppendBag instrumentBags, instrumentGenerators, _
        instrumentLocal + test_Generator(53, 0)
    test_AppendBag instrumentBags, instrumentGenerators, _
        test_Generator(43, &H7F00) + _
        test_Generator(54, 1) + _
        test_Generator(17, -500) + _
        test_Generator(57, 1) + test_Generator(53, 1)
    test_AppendBag instrumentBags, instrumentGenerators, _
        test_Generator(43, &H7F00) + _
        test_Generator(54, 1) + _
        test_Generator(17, 500) + _
        test_Generator(57, 1) + test_Generator(53, 2)
    test_AppendBag instrumentBags, instrumentGenerators, test_Generator(0, 0)
    Dim As String sampleHeaders = _
        test_SampleHeader("Sine C4", 0, audibleSamplePoints, 16, 112, _
            22050, 60, 1) + _
        test_SampleHeader("Sine Left", 128, 256, 144, 240, _
            22050, 60, 4) + _
        test_SampleHeader("Sine Right", 256, 384, 272, 368, _
            22050, 60, 2) + _
        test_SampleHeader("EOS", samplePointCount, samplePointCount, _
            samplePointCount, samplePointCount, 0, 0, 0)

    Dim As String presetPayload = _
        test_Chunk("phdr", presetHeaders) + _
        test_Chunk("pbag", presetBags) + _
        test_Chunk("pmod", String(10, 0)) + _
        test_Chunk("pgen", presetGenerators) + _
        test_Chunk("inst", instrumentHeaders) + _
        test_Chunk("ibag", instrumentBags) + _
        test_Chunk("imod", String(10, 0)) + _
        test_Chunk("igen", instrumentGenerators) + _
        test_Chunk("shdr", sampleHeaders)
    Dim As String riffPayload = "sfbk" + _
        test_Chunk("LIST", "INFO" + infoPayload) + _
        test_Chunk("LIST", "sdta" + samplePayload) + _
        test_Chunk("LIST", "pdta" + presetPayload)
    Return "RIFF" + test_Le32(Len(riffPayload)) + riffPayload
End Function


Private Sub test_WriteFile( _
    ByVal filename As String, _
    ByRef fileData As String _
)
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Output Access Write As #fileNumber) <> 0 Then _
        test_Fail "could not truncate a SoundFont fixture"
    Close #fileNumber
    If Open(filename For Binary Access Write As #fileNumber) <> 0 Then _
        test_Fail "could not create a SoundFont fixture"
    Put #fileNumber, 1, fileData
    Close #fileNumber
End Sub


Private Sub test_WritePhase( _
    ByVal filename As String, _
    ByVal phaseName As String _
)
    Dim As String phaseData = "phase=" + phaseName + Chr(10)
    test_WriteFile filename, phaseData
End Sub


Dim As String soundFontFilename = Trim(Command(1))
Dim As String malformedFilename = Trim(Command(2))
Dim As String resultFilename = Trim(Command(3))
' NativeActivity does not provide command-line arguments. Relative defaults
' let the identical test source exercise Android's private working directory.
If soundFontFilename = "" Then
    soundFontFilename = "soundfont-smoke.sf2"
End If
If malformedFilename = "" Then
    malformedFilename = "soundfont-malformed.sf2"
End If
If resultFilename = "" Then
    resultFilename = "soundfont-smoke.result"
End If

Dim As String soundFontData = test_CreateSoundFont()
test_WriteFile soundFontFilename, soundFontData
test_WritePhase resultFilename, "fixture-written"
Dim As String errorText
If soundfontBank_Load(soundFontFilename, errorText) = 0 Then _
    test_Fail "valid SoundFont was rejected: " + errorText
test_WritePhase resultFilename, "bank-loaded"
If soundfontBank_GetName() <> "OpenSesh Test Bank" OrElse _
    soundfontBank_GetPresetCount() <> 2 OrElse _
    soundfontBank_GetSampleHeaderCount() <> 3 OrElse _
    soundfontBank_GetSamplePointCount() <> 512 Then _
    test_Fail "loaded SoundFont metadata is incorrect"
If soundfontBank_HasPreset(0, 0) = 0 OrElse _
    soundfontBank_HasPreset(0, 1) = 0 OrElse _
    soundfontBank_HasPreset(0, 2) <> 0 OrElse _
    soundfontBank_HasPreset(-1, 0) <> 0 Then _
    test_Fail "exact preset inspection is incorrect"

Dim As OseSoundFontVoiceRegion regions( _
    0 To OSE_SOUNDFONT_MAX_REGIONS_PER_NOTE - 1 _
)
If soundfontBank_Resolve(0, 0, 60, 100, regions()) <> 1 Then _
    test_Fail "GM preset did not resolve one sample region"
If regions(0).leftStart <> 0 OrElse regions(0).leftEnd <> 128 OrElse _
    regions(0).leftLoopStart <> 16 OrElse regions(0).leftLoopEnd <> 112 OrElse _
    regions(0).rootKey <> 60 OrElse regions(0).sampleModes <> 1 Then _
    test_Fail "resolved SoundFont region does not match its generators"
If soundfontBank_Resolve(0, 1, 60, 100, regions()) <> 2 OrElse _
    regions(0).leftStart <> 128 OrElse regions(0).rightStart <> 128 OrElse _
    Abs(regions(0).pan + 1.0) > 0.00001 OrElse _
    regions(1).leftStart <> 256 OrElse regions(1).rightStart <> 256 OrElse _
    Abs(regions(1).pan - 1.0) > 0.00001 Then _
    test_Fail "stereo zones were not resolved as independently panned voices"
If soundfontBank_Resolve(512, 0, 60, 100, regions()) <> 1 OrElse _
    soundfontBank_Resolve(0, 7, 60, 100, regions()) <> 1 Then _
    test_Fail "General MIDI fallback did not resolve bank zero program zero"
If soundfontBank_Resolve(0, 0, -1, 100, regions()) <> 0 OrElse _
    soundfontBank_Resolve(0, 0, 60, 0, regions()) <> 0 Then _
    test_Fail "invalid MIDI bounds were accepted by the resolver"
test_WritePhase resultFilename, "regions-resolved"

Dim As String malformedData = Left(soundFontData, Len(soundFontData) - 1)
test_WriteFile malformedFilename, malformedData
If soundfontBank_Load(malformedFilename, errorText) <> 0 Then _
    test_Fail "a truncated SoundFont was accepted"
If soundfontBank_GetName() <> "OpenSesh Test Bank" Then _
    test_Fail "a failed replacement destroyed the active bank"
test_WritePhase resultFilename, "malformed-rejected"

' Local zones replace globals before preset offsets are added to instruments.
' Deliberately different ranges prove both replacement and cross-level filtering.
Dim As String hierarchyData = test_CreateSoundFont( _
    test_Generator(43, &H463C) + test_Generator(44, &H463C) + _
        test_Generator(17, 100) + test_Generator(51, 4) + _
        test_Generator(52, 10) + test_Generator(34, 1200) + _
        test_Generator(35, 1200) + test_Generator(36, 1200) + _
        test_Generator(38, 1200) + test_Generator(48, 100) + _
        test_Generator(37, 100) + test_Generator(56, 20), _
    test_Generator(43, &H5028) + test_Generator(44, &H5A32) + _
        test_Generator(17, 50) + test_Generator(51, 2) + _
        test_Generator(48, 50) + test_Generator(0, 100), _
    test_Generator(43, &H463C) + test_Generator(44, &H463C) + _
        test_Generator(17, 200) + test_Generator(51, 6) + _
        test_Generator(52, 5) + test_Generator(34, -1200) + _
        test_Generator(35, -1200) + test_Generator(36, -1200) + _
        test_Generator(38, -1200) + test_Generator(48, 200) + _
        test_Generator(37, 50) + test_Generator(56, 90) + _
        test_Generator(0, 8) + test_Generator(1, -8) + _
        test_Generator(2, 2) + test_Generator(3, -2) + _
        test_Generator(4, 1) + test_Generator(46, 36) + test_Generator(58, 36), _
    test_Generator(43, &H5A32) + test_Generator(44, &H5028) + _
        test_Generator(17, -100) + test_Generator(51, 1) + _
        test_Generator(52, -5) + test_Generator(38, -2400) + _
        test_Generator(48, 100) + test_Generator(0, 4) + _
        test_Generator(1, -4) + test_Generator(2, 4) + _
        test_Generator(3, -4) + test_Generator(4, 0) + _
        test_Generator(46, -1) + test_Generator(58, -1) + test_Generator(54, 1))
test_WriteFile soundFontFilename, hierarchyData
If soundfontBank_Load(soundFontFilename, errorText) = 0 Then _
    test_Fail "generator hierarchy fixture was rejected: " + errorText
If soundfontBank_Resolve(0, 0, 55, 55, regions()) <> 1 Then _
    test_Fail "local key and velocity ranges did not replace global ranges"
If regions(0).leftStart <> 4 OrElse regions(0).leftEnd <> 124 OrElse _
    regions(0).leftLoopStart <> 20 OrElse regions(0).leftLoopEnd <> 108 OrElse _
    regions(0).keyOverride <> -1 OrElse regions(0).rootKey <> 60 Then _
    test_Fail "local sample generators did not replace inherited values"
If Abs(regions(0).pan + 0.1) > 0.00001 OrElse regions(0).tuneCents <> 305 OrElse _
    regions(0).scaleTuning <> 110 OrElse _
    Abs(regions(0).attenuationGain - CSng(10.0 ^ -0.75)) > 0.00001 OrElse _
    Abs(regions(0).sustainLevel - CSng(10.0 ^ -0.75)) > 0.00001 OrElse _
    Abs(regions(0).attackSeconds - 1.0) > 0.00001 OrElse _
    Abs(regions(0).holdSeconds - 1.0) > 0.00001 OrElse _
    Abs(regions(0).decaySeconds - 1.0) > 0.00001 OrElse _
    Abs(regions(0).releaseSeconds - 0.5) > 0.00001 Then _
    test_Fail "preset offsets were not combined with instrument settings"
If soundfontBank_Resolve(0, 0, 45, 55, regions()) <> 0 OrElse _
    soundfontBank_Resolve(0, 0, 85, 55, regions()) <> 0 OrElse _
    soundfontBank_Resolve(0, 0, 55, 45, regions()) <> 0 OrElse _
    soundfontBank_Resolve(0, 0, 55, 85, regions()) <> 0 Then _
    test_Fail "preset and instrument ranges were not intersected"
test_WriteFile soundFontFilename, soundFontData
If soundfontBank_Load(soundFontFilename, errorText) = 0 Then _
    test_Fail "the original bank could not be restored"

#Ifdef OSE_TEST_SOUNDFONT_PARSER_ONLY
soundfontBank_Clear()
Print "soundfont_parser=ok"
End 0
#EndIf

Dim As OsePlaybackMixValues mixValues
mixValues.channelGain = 0.8
mixValues.meterGain = 0.8
mixValues.voiceGain = 0.45
mixValues.pan = 0.0
Const previewFrames As Integer = 24000
Dim As Single previewSamples(0 To previewFrames * 2 - 1)
If soundfontSynth_RenderPreview(0, 60, 0, 0, 8192, 0.20, mixValues, _
    48000, @previewSamples(0), previewFrames) = 0 Then _
    test_Fail "the production synth rejected an offline preview note"
Dim As Single peakValue
For sampleIndex As Integer = 0 To previewFrames * 2 - 1
    Dim As Single absoluteValue = Abs(previewSamples(sampleIndex))
    If absoluteValue > peakValue Then
        peakValue = absoluteValue
    End If
Next
If peakValue < 0.01 Then _
    test_Fail "the rendered SoundFont note is silent or too quiet"
test_WritePhase resultFilename, "preview-rendered"

' Exclusive classes silence older notes, not the stereo layers of this note.
If soundfontSynth_RenderPreview(9, 60, 0, 1, 8192, 0.20, mixValues, _
    48000, @previewSamples(0), previewFrames) = 0 Then _
    test_Fail "the stereo drum preview was rejected"
Dim As Single leftPeak, rightPeak
For frameIndex As Integer = 0 To previewFrames - 1
    If Abs(previewSamples(frameIndex * 2)) > leftPeak Then _
        leftPeak = Abs(previewSamples(frameIndex * 2))
    If Abs(previewSamples(frameIndex * 2 + 1)) > rightPeak Then _
        rightPeak = Abs(previewSamples(frameIndex * 2 + 1))
Next
If leftPeak < 0.01 OrElse rightPeak < 0.01 Then _
    test_Fail "exclusive-class stereo layers cut off each other"

' Exact velocity boundaries must select their own zones. A forced velocity
' changes the gain after selection, so a quiet note can trigger a loud sample.
Dim As String velocityData = test_CreateSoundFont("", "", "", _
    test_Generator(44, &H3F3F) + test_Generator(47, 127) + _
    test_Generator(54, 1) + test_Generator(38, -7973))
test_WriteFile soundFontFilename, velocityData
If soundfontBank_Load(soundFontFilename, errorText) = 0 Then _
    test_Fail "velocity fixture was rejected: " + errorText
mixValues.voiceGain = OSE_PLAYBACK_VOICE_HEADROOM * 63.0 / 127.0
If soundfontSynth_RenderPreview(0, 60, 0, 0, 8192, 0.20, mixValues, _
    48000, @previewSamples(0), previewFrames) = 0 Then _
    test_Fail "MIDI velocity 63 did not select its exact sample zone"
Dim As Single forcedPeak
For sampleIndex As Integer = 0 To previewFrames * 2 - 1
    If Abs(previewSamples(sampleIndex)) > forcedPeak Then _
        forcedPeak = Abs(previewSamples(sampleIndex))
Next
If Abs(forcedPeak - peakValue) > 0.00001 Then _
    test_Fail "forced sample velocity did not control the rendered gain"
mixValues.voiceGain = OSE_PLAYBACK_VOICE_HEADROOM
test_WriteFile soundFontFilename, soundFontData

SetEnviron "SFXLIB_DRIVER=null"
If soundfontSynth_Load(soundFontFilename, errorText) = 0 Then _
    test_Fail "the SoundFont output worker did not start: " + errorText
test_WritePhase resultFilename, "worker-started"
If soundfontSynth_IsActive() = 0 Then _
    test_Fail "the loaded SoundFont did not become active"
test_WritePhase resultFilename, "worker-active"
Dim As Integer workerPlayResult = soundfontSynth_PlayMidiNote( _
    0, 60, 0, 0, 8192, 0.05, mixValues)
If workerPlayResult = 0 Then _
    test_Fail "the active SoundFont worker rejected a resolved note"
test_WritePhase resultFilename, "worker-note-started"
Sleep 20, 1
test_WritePhase resultFilename, "worker-note-waited"

soundfontSynth_Shutdown()
sfxRuntime_Shutdown()
test_WritePhase resultFilename, "worker-shutdown"
If soundfontBank_IsLoaded() <> 0 OrElse soundfontSynth_IsActive() <> 0 Then _
    test_Fail "SoundFont shutdown retained active resources"

Dim As String resultData = "soundfont_smoke=ok" + Chr(10)
test_WriteFile resultFilename, resultData
Print "soundfont_smoke=ok"
Print "bank_name=OpenSesh Test Bank"
Print "presets=2"
Print "sample_headers=3"
Print "preview_peak="; peakValue
End 0

/' end of tests/soundfont_smoke.bas '/
