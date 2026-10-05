/'
    Project: OpenSesh
    ---------------------------

    File: tests/audio_sample_slots_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Module API: Test executable accepting low/high fixture WAV paths and an
        output WAV path; uses foreground-feed calls for captured sample playback.

    Purpose:

        Prove that the editor's complete audio-clip sample table plays the
        correct PCM waveform after capacity loading and list compaction.

    Responsibilities:

        - generate distinct low- and high-frequency PCM WAV fixtures
        - load and audibly render the final supported clip slot
        - delete clip zero and prove the following waveform moves into slot zero
        - reject invalid playback indexes, channels, pitches, and stale mappings
        - isolate one offline file while another clip remains audibly available
        - restore the repaired file without retaining its previous decoded PCM
        - release every loaded sample before explicit sfxlib shutdown

    This file intentionally does NOT contain:

        - GUI controls or a desktop window
        - MIDI scheduling
        - physical speaker or microphone assumptions
'/

#lang "fb"

#include once "../audio_tracks.bi"
#include once "../audio_sample_slots.bi"
#include once "../wav_export_sfx.bi"
#include once "../sfx_runtime.bi"

Const TEST_SAMPLE_RATE As ULong = 8000
Const TEST_SAMPLE_FRAMES As ULong = 1000
Const TEST_AMPLITUDE As Integer = 12000
Const TEST_LOW_FREQUENCY As Integer = 220
Const TEST_HIGH_FREQUENCY As Integer = 880
Const TEST_MIXER_CHANNEL As Integer = 0
Const TEST_RENDER_SECONDS As Double = 0.125
Const TEST_LOW_CROSSING_MAX As Integer = 90
Const TEST_HIGH_CROSSING_MIN As Integer = 140
Const TEST_USEFUL_PEAK As Integer = 1000

Declare Sub fb_sfxUpdate CDecl Alias "fb_sfxUpdate" (ByVal frames As Long)
Declare Sub fb_sfxForegroundFeedBegin CDecl _
    Alias "fb_sfxForegroundFeedBegin" ()
Declare Sub fb_sfxForegroundFeedEnd CDecl _
    Alias "fb_sfxForegroundFeedEnd" ()

' -------------------------------------------------------------------------
' Test fixture helpers
' -------------------------------------------------------------------------

Private Sub test_Fail(ByVal messageText As String)
    audioSampleSlots_Clear()
    audio_Clear()
    sfxRuntime_Shutdown()
    Print "ERROR: "; messageText
    End 1
End Sub


Private Function test_Le16(ByVal value As ULong) As String
    ' RIFF fields and signed PCM samples are byte strings, not display text.

    Return Chr(CInt(value And &HFF)) + Chr(CInt((value Shr 8) And &HFF))
End Function


Private Function test_Le32(ByVal value As ULong) As String
    Return test_Le16(value And &HFFFF) + test_Le16(value Shr 16)
End Function


Private Function test_WriteTone( _
    ByVal filename As String, _
    ByVal frequency As Integer _
) As Integer
    If filename = "" OrElse frequency <= 0 OrElse _
        frequency >= TEST_SAMPLE_RATE \ 2 Then Return 0

    Dim As ULong dataBytes = TEST_SAMPLE_FRAMES * 2
    Dim As String sampleData = String(dataBytes, Chr(0))
    For sampleIndex As ULong = 0 To TEST_SAMPLE_FRAMES - 1
        Dim As ULong phasePosition = _
            (sampleIndex * CULng(frequency)) Mod TEST_SAMPLE_RATE
        Dim As Integer sampleValue = TEST_AMPLITUDE
        If phasePosition >= TEST_SAMPLE_RATE \ 2 Then _
            sampleValue = -TEST_AMPLITUDE
        Dim As ULong encodedSample = CULng(sampleValue And &HFFFF)
        ' The destination is allocated for every complete 16-bit sample.
        ' fblint: disable-next-line FBL514 REASON: The destination is allocated for each complete 16-bit sample.
        Mid(sampleData, CInt(sampleIndex * 2 + 1), 2) = _
            test_Le16(encodedSample)
    Next

    Dim As String waveData = "RIFF" + test_Le32(36 + dataBytes) + "WAVE" + _
        "fmt " + test_Le32(16) + test_Le16(1) + test_Le16(1) + _
        test_Le32(TEST_SAMPLE_RATE) + test_Le32(TEST_SAMPLE_RATE * 2) + _
        test_Le16(2) + test_Le16(16) + "data" + test_Le32(dataBytes) + _
        sampleData

    If Dir(filename) <> "" Then
        Kill filename
    End If
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Write As #fileNumber) <> 0 Then
        Return 0
    End If
    Put #fileNumber, 1, waveData
    Dim As Integer closeResult = Close(#fileNumber)
    ' fblint: disable-next-line FBL-IO-004 REASON: Close above releases the owned file handle.
    Return IIf(closeResult = 0, -1, 0)
End Function


Private Function test_CorruptWave(ByVal filename As String) As Integer
    If Dir(filename) <> "" Then
        Kill filename
    End If
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Write As #fileNumber) <> 0 Then
        Return 0
    End If
    Dim As String invalidData = "not a RIFF/WAVE file"
    Put #fileNumber, 1, invalidData
    Dim As Integer closeResult = Close(#fileNumber)
    ' fblint: disable-next-line FBL-IO-004 REASON: Close above releases the owned file handle.
    Return IIf(closeResult = 0, -1, 0)
End Function

' -------------------------------------------------------------------------
' Captured-output analysis
' -------------------------------------------------------------------------

Private Function test_AnalyzeWave( _
    ByVal filename As String, _
    ByRef peakValue As Integer, _
    ByRef crossingCount As Integer _
) As Integer
    Dim As Integer channelIndex = 1

    peakValue = 0
    crossingCount = 0

    Dim As OseWaveInfo waveInfo
    If audio_InspectWave(filename, waveInfo) = 0 OrElse _
        waveInfo.audioFormat <> 1 OrElse waveInfo.bitsPerSample <> 16 OrElse _
        waveInfo.channelCount < 1 OrElse waveInfo.channelCount > 2 OrElse _
        waveInfo.sampleFrames = 0 Then Return 0

    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then
        Return 0
    End If
    ' wav_export_sfx writes the canonical 44-byte PCM container.
    Seek #fileNumber, 45
    Dim As Integer previousSign
    For frameIndex As ULongInt = 0 To waveInfo.sampleFrames - 1
        Dim As Short sampleValue
        Get #fileNumber, , sampleValue
        channelIndex = 1
        While channelIndex < waveInfo.channelCount
            Dim As Short ignoredSample
            Get #fileNumber, , ignoredSample
            channelIndex += 1
        Wend

        Dim As Integer wideSample = CInt(sampleValue)
        Dim As Integer absoluteValue = wideSample
        If absoluteValue < 0 Then
            absoluteValue = -absoluteValue
        End If
        If absoluteValue > peakValue Then
            peakValue = absoluteValue
        End If

        Dim As Integer currentSign
        If wideSample > 32 Then
            currentSign = 1
        ElseIf wideSample < -32 Then
            currentSign = -1
        End If
        If currentSign <> 0 Then
            If previousSign <> 0 AndAlso currentSign <> previousSign Then _
                crossingCount += 1
            previousSign = currentSign
        End If
    Next
    Dim As Integer closeResult = Close(#fileNumber)
    ' fblint: disable-next-line FBL-IO-004 REASON: Close above releases the owned file handle.
    Return IIf(closeResult = 0, -1, 0)
End Function


Private Function test_RenderClip( _
    ByVal clipIndex As Integer, _
    ByVal outputFilename As String, _
    ByRef peakValue As Integer, _
    ByRef crossingCount As Integer _
) As Integer
    Dim As OseWavExportState exportState
    wavExport_Initialize exportState
    Dim As String errorText
    If wavExport_Begin(exportState, outputFilename, _
        TEST_RENDER_SECONDS, errorText) = 0 Then Return 0

    volume TEST_MIXER_CHANNEL, 0.80
    pan TEST_MIXER_CHANNEL, 0.0
    fb_sfxForegroundFeedBegin()
    Dim As Integer playResult = audioSampleSlots_Play( _
        TEST_MIXER_CHANNEL, clipIndex, 1.0)
    If playResult <> 0 Then
        Dim As Long renderFrames = CLng( _
            CDbl(exportState.sampleRate) * TEST_RENDER_SECONDS)
        fb_sfxUpdate renderFrames
    End If
    SFX STOP CHANNEL, TEST_MIXER_CHANNEL
    fb_sfxForegroundFeedEnd()

    If playResult = 0 Then
        wavExport_Cancel exportState
        Return 0
    End If
    Dim As ULongInt underrunCount
    If wavExport_Finish(exportState, underrunCount, errorText) = 0 OrElse _
        underrunCount <> 0 Then Return 0
    Return test_AnalyzeWave(outputFilename, peakValue, crossingCount)
End Function

' -------------------------------------------------------------------------
' Capacity and compaction contract
' -------------------------------------------------------------------------

Dim As String lowWaveFilename = Trim(Command(1))
Dim As String highWaveFilename = Trim(Command(2))
Dim As String outputFilename = Trim(Command(3))
If lowWaveFilename = "" OrElse highWaveFilename = "" OrElse _
    outputFilename = "" Then
    Print "usage: audio_sample_slots_smoke <low.wav> <high.wav> <output.wav>"
    End 2
End If

If test_WriteTone(lowWaveFilename, TEST_LOW_FREQUENCY) = 0 OrElse _
    test_WriteTone(highWaveFilename, TEST_HIGH_FREQUENCY) = 0 Then _
    test_Fail "PCM tone fixtures could not be created"

audio_Clear()
For clipIndex As Integer = 0 To OSE_AUDIO_MAX_CLIPS - 1
    If audio_AddClip(highWaveFilename, clipIndex * 16, 1000) <> clipIndex Then _
        test_Fail "the audio document did not accept all 64 clips"
Next
If audio_AddClip(lowWaveFilename, 0, 1000) <> -1 Then _
    test_Fail "the audio document exceeded its 64-clip bound"
If audioSampleSlots_Synchronize() = 0 OrElse _
    audioSampleSlots_GetLoadedCount() <> OSE_AUDIO_MAX_CLIPS OrElse _
    audioSampleSlots_GetUnavailableCount() <> 0 OrElse _
    audioSampleSlots_IsAvailable(OSE_AUDIO_MAX_CLIPS - 1) = 0 Then _
    test_Fail "the complete sfxlib sample table did not synchronize"

If audioSampleSlots_IsAvailable(-1) <> 0 OrElse _
    audioSampleSlots_IsAvailable(OSE_AUDIO_MAX_CLIPS) <> 0 OrElse _
    audioSampleSlots_Play(-1, 0, 1.0) <> 0 OrElse _
    audioSampleSlots_Play(OSE_SFX_MIXER_CHANNEL_COUNT, 0, 1.0) <> 0 OrElse _
    audioSampleSlots_Play(TEST_MIXER_CHANNEL, -1, 1.0) <> 0 OrElse _
    audioSampleSlots_Play(TEST_MIXER_CHANNEL, OSE_AUDIO_MAX_CLIPS, 1.0) <> 0 OrElse _
    audioSampleSlots_Play(TEST_MIXER_CHANNEL, 0, 0.0) <> 0 OrElse _
    audioSampleSlots_Play(TEST_MIXER_CHANNEL, 0, 8.1) <> 0 Then _
    test_Fail "invalid sample playback bounds were accepted"

Dim As Integer capacityPeak
Dim As Integer capacityCrossings
If test_RenderClip(OSE_AUDIO_MAX_CLIPS - 1, outputFilename, _
    capacityPeak, capacityCrossings) = 0 OrElse _
    capacityPeak < TEST_USEFUL_PEAK OrElse _
    capacityCrossings < TEST_HIGH_CROSSING_MIN Then _
    test_Fail "sample slot 64 did not render its high-frequency PCM"

audio_Clear()
If audio_AddClip(lowWaveFilename, 0, 1000) <> 0 OrElse _
    audio_AddClip(highWaveFilename, 16, 1000) <> 1 OrElse _
    audioSampleSlots_Synchronize() = 0 Then _
    test_Fail "the two-clip compaction fixture could not synchronize"

Dim As Integer lowPeak
Dim As Integer lowCrossings
If test_RenderClip(0, outputFilename, lowPeak, lowCrossings) = 0 OrElse _
    lowPeak < TEST_USEFUL_PEAK OrElse _
    lowCrossings > TEST_LOW_CROSSING_MAX Then _
    test_Fail "clip zero did not render its low-frequency PCM"

If audio_RemoveClip(0) = 0 Then _
    test_Fail "deleting clip zero failed"
If audioSampleSlots_IsAvailable(0) <> 0 OrElse _
    audioSampleSlots_Play(TEST_MIXER_CHANNEL, 0, 1.0) <> 0 Then _
    test_Fail "an unsynchronized compacted index retained stale playback"
If audioSampleSlots_Synchronize() = 0 OrElse _
    audio_GetCount() <> 1 OrElse _
    audioSampleSlots_GetLoadedCount() <> 1 OrElse _
    audioSampleSlots_GetUnavailableCount() <> 0 Then _
    test_Fail "deleting clip zero did not compact the sample table"

Dim As Integer compactedPeak
Dim As Integer compactedCrossings
If test_RenderClip(0, outputFilename, compactedPeak, _
    compactedCrossings) = 0 OrElse compactedPeak < TEST_USEFUL_PEAK OrElse _
    compactedCrossings < TEST_HIGH_CROSSING_MIN OrElse _
    compactedCrossings <= lowCrossings * 2 Then _
    test_Fail "the compacted slot played stale low-frequency audio"

If audio_AddClip(lowWaveFilename, 32, 1000) <> 1 OrElse _
    audioSampleSlots_Synchronize() = 0 Then _
    test_Fail "the offline-file isolation fixture could not synchronize"
If test_CorruptWave(highWaveFilename) = 0 Then _
    test_Fail "the offline-file fixture could not be created"
If audioSampleSlots_Synchronize() <> 0 OrElse _
    audioSampleSlots_GetLoadedCount() <> 1 OrElse _
    audioSampleSlots_GetUnavailableCount() <> 1 OrElse _
    audioSampleSlots_IsAvailable(0) <> 0 OrElse _
    audioSampleSlots_IsAvailable(1) = 0 OrElse _
    audioSampleSlots_Play(TEST_MIXER_CHANNEL, 0, 1.0) <> 0 Then _
    test_Fail "an offline slot retained stale data or muted a valid clip"

Dim As Integer isolatedPeak
Dim As Integer isolatedCrossings
If test_RenderClip(1, outputFilename, isolatedPeak, isolatedCrossings) = 0 _
    OrElse isolatedPeak < TEST_USEFUL_PEAK OrElse _
    isolatedCrossings > TEST_LOW_CROSSING_MAX Then _
    test_Fail "the valid clip beside an offline slot did not render"

If test_WriteTone(highWaveFilename, TEST_HIGH_FREQUENCY) = 0 OrElse _
    audioSampleSlots_Synchronize() = 0 OrElse _
    audioSampleSlots_GetLoadedCount() <> 2 OrElse _
    audioSampleSlots_GetUnavailableCount() <> 0 OrElse _
    audioSampleSlots_IsAvailable(0) = 0 Then _
    test_Fail "the repaired offline clip did not recover"

Dim As Integer recoveredPeak
Dim As Integer recoveredCrossings
If test_RenderClip(0, outputFilename, recoveredPeak, recoveredCrossings) = 0 _
    OrElse recoveredPeak < TEST_USEFUL_PEAK OrElse _
    recoveredCrossings < TEST_HIGH_CROSSING_MIN Then _
    test_Fail "the repaired clip did not render its current PCM"

audioSampleSlots_Clear()
audioSampleSlots_Clear()
audio_Clear()
sfxRuntime_Shutdown()
sfxRuntime_Shutdown()

Print "audio_sample_slots=ok"
Print "sample_capacity="; OSE_AUDIO_MAX_CLIPS
Print "capacity_peak="; capacityPeak
Print "low_crossings="; lowCrossings
Print "compacted_crossings="; compactedCrossings
Print "stale_reload_rejected=1"
Print "offline_valid_crossings="; isolatedCrossings
Print "offline_recovery_crossings="; recoveredCrossings
End 0

/' end of tests/audio_sample_slots_smoke.bas '/
