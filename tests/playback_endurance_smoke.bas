/'
    Project: OpenSesh
    ---------------------------

    File: tests/playback_endurance_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Module API: Test executable accepting an output WAV path; selects the null
        driver and drives production synthesis through foreground-feed runtime calls.

    Purpose:

        Prove sustained production software-synth and WAV-export operation in
        accelerated foreground-feed mode.

    Responsibilities:

        - render 30 seconds of stereo output without wall-clock waiting
        - schedule more than ten thousand notes through the production synth
        - vary channel, program, pitch bend, velocity, gain, and pan
        - use sfxlib's null output driver for hardware-independent timing
        - require valid non-silent PCM near both ends of the render
        - require an exact frame count and zero output underruns
        - restart sfxlib and prove retained synth state is rebuilt audibly

    This file intentionally does NOT contain:

        - external MIDI or audio hardware assumptions
        - omaGUI or transport-window automation
        - an independent oscillator implementation
'/

#lang "fb"

#include once "../src/audio_tracks.bi"
#include once "../src/wav_export_sfx.bi"
#include once "../src/playback_mix.bi"
#include once "../src/software_synth.bi"
#include once "../src/sfx_runtime.bi"

Const TEST_RENDER_SECONDS As Double = 30.0
Const TEST_FEED_BLOCK_FRAMES As Long = 256
Const TEST_NOTE_INTERVAL_FRAMES As Long = 128
Const TEST_MINIMUM_NOTES As Integer = 10000
Const TEST_RECOVERY_SECONDS As Double = 1.0

Declare Sub fb_sfxUpdate CDecl Alias "fb_sfxUpdate" (ByVal frames As Long)
' These are public, target-stable names in the linked sfxlib C ABI.
' fblint: disable-next-line FBL931 REASON: This declaration binds the verified sfxlib C ABI export used by the test.
Declare Sub fb_sfxForegroundFeedBegin CDecl Alias "fb_sfxForegroundFeedBegin" ()
' fblint: disable-next-line FBL931 REASON: This declaration binds the verified sfxlib C ABI export used by the test.
Declare Sub fb_sfxForegroundFeedEnd CDecl Alias "fb_sfxForegroundFeedEnd" ()
' The definition query is a target-stable sfxlib C ABI used only to prove the
' restart cleared and then rebuilt the production instrument table.
' fblint: disable-next-line FBL931 REASON: This declaration binds the verified sfxlib C ABI export used by the test.
Declare Function fb_sfxInstrumentDefined CDecl Alias "fb_sfxInstrumentDefined" (ByVal instrumentId As Integer) As Long

' -------------------------------------------------------------------------
' Validation helpers
' -------------------------------------------------------------------------

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Function test_WavePeakRange( _
    ByVal filename As String, _
    ByVal startFrame As ULongInt, _
    ByVal frameCount As ULongInt, _
    ByVal channelCount As Integer _
) As Integer
    Dim As Integer peakValue = 0
    Dim As Short sampleValue = 0
    ' ULongInt matches the bounded file and frame counts checked below.
    ' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
    Dim As ULongInt sampleIndex = 0

    If frameCount = 0 OrElse channelCount < 1 Then
        Return -1
    End If
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then
        Return -1
    End If

    Const waveHeaderBytes As ULongInt = 44
    Const sampleBytes As ULongInt = 2
    ' ULongInt is the fixed 64-bit type used for file offsets and frame counts.
    ' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
    Dim As ULongInt byteOffset = waveHeaderBytes + _
        startFrame * CULngInt(channelCount) * sampleBytes
    ' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
    Dim As ULongInt bytesToRead = frameCount * _
        CULngInt(channelCount) * sampleBytes
    ' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
    Dim As ULongInt fileBytes = CULngInt(Lof(fileNumber))
    If byteOffset > fileBytes OrElse bytesToRead > fileBytes - byteOffset Then
        Close #fileNumber
        Return -1
    End If

    Seek #fileNumber, byteOffset + 1
    ' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
    Dim As ULongInt sampleCount = frameCount * CULngInt(channelCount)
    sampleIndex = 0
    While sampleIndex < sampleCount
        Get #fileNumber, , sampleValue
        Dim As Integer absoluteValue = CInt(sampleValue)
        If absoluteValue < 0 Then
            absoluteValue = -absoluteValue
        End If
        If absoluteValue > peakValue Then
            peakValue = absoluteValue
        End If
        sampleIndex += 1
    Wend
    Close #fileNumber
    Return peakValue
End Function

' -------------------------------------------------------------------------
' Accelerated production render
' -------------------------------------------------------------------------

Dim As String outputFilename = Trim(Command(1))
If outputFilename = "" Then
    Print "usage: playback_endurance_smoke <output.wav>"
    End 2
End If

' Offline foreground feeding deliberately runs faster than real time. A null
' driver prevents that deterministic workload from starving an unrelated live
' hardware callback while retaining the complete production mixer and capture.
' FreeBASIC provides the process environment on both supported desktop hosts.
' fblint: disable-next-line FBL750 REASON: The null-driver test deliberately sets and verifies its own process environment.
SetEnviron "SFXLIB_DRIVER=null"
' fblint: disable-next-line FBL750 REASON: The null-driver test deliberately sets and verifies its own process environment.
If LCase(Trim(Environ("SFXLIB_DRIVER"))) <> "null" Then _
    test_Fail "null output driver selection could not be established"

softwareSynth_Configure()
Dim As OseWavExportState exportState
wavExport_Initialize exportState
Dim As String errorText
If wavExport_Begin(exportState, outputFilename, TEST_RENDER_SECONDS, _
    errorText) = 0 Then _
    test_Fail "endurance capture could not start: " + errorText

' Long deliberately matches sfxlib's fixed 32-bit frame-count ABI.
' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
Dim As Long totalFrames = CLng(TEST_RENDER_SECONDS * _
    CDbl(exportState.sampleRate))
If totalFrames <= 0 Then
    test_Fail "endurance frame count is invalid"
End If

fb_sfxForegroundFeedBegin()
' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
Dim As Long currentFrame
' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
Dim As Long nextNoteFrame
Dim As Integer scheduledNotes
While currentFrame < totalFrames
    While nextNoteFrame <= currentFrame
        Dim As Integer channelIndex = 0
        channelIndex = scheduledNotes Mod 16
        Dim As Integer keyNumber = 24 + (scheduledNotes Mod 84)
        Dim As Integer programNumber = (scheduledNotes * 7) Mod 128
        Dim As Integer pitchBend = (scheduledNotes * 977) Mod 16384
        Dim As Integer noteVelocity = 32 + (scheduledNotes Mod 96)
        Dim As Integer controllerVolume = 64 + (scheduledNotes Mod 64)
        Dim As Integer controllerExpression = 72 + _
            ((scheduledNotes * 3) Mod 56)
        Dim As Integer controllerPan = (scheduledNotes * 11) Mod 128
        Dim As Single durationSeconds = 0.025 + _
            CSng(scheduledNotes Mod 100) / 1000.0

        Dim As OsePlaybackMixValues mixValues
        ' Dense scheduling intentionally overlaps release tails. Keep enough
        ' master headroom to prove sustained output without accepting clipping.
        playbackMix_Calculate mixValues, controllerVolume, _
            controllerExpression, controllerPan, noteVelocity, 0.12, -1
        Dim As OseSoftwareSynthPlayOptions playOptions
        playOptions.bankNumber = 0
        playOptions.fallbackVoiceChannel = -1
        If softwareSynth_PlayMidiNote(channelIndex, keyNumber, programNumber, _
            pitchBend, durationSeconds, mixValues, playOptions) = 0 Then _
            test_Fail "production synth rejected an endurance note"

        scheduledNotes += 1
        nextNoteFrame += TEST_NOTE_INTERVAL_FRAMES
    Wend

    ' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
    Dim As Long framesToFeed = TEST_FEED_BLOCK_FRAMES
    If framesToFeed > totalFrames - currentFrame Then _
        framesToFeed = totalFrames - currentFrame
    fb_sfxUpdate framesToFeed
    currentFrame += framesToFeed
Wend
fb_sfxForegroundFeedEnd()

' ULongInt matches sfxlib's fixed 64-bit cumulative underrun counter.
' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
Dim As ULongInt underrunCount
If wavExport_Finish(exportState, underrunCount, errorText) = 0 Then _
    test_Fail "endurance capture could not finish: " + errorText
If underrunCount <> 0 Then
    test_Fail "accelerated render reported underruns"
End If

Dim As OseWaveInfo waveInfo
If audio_InspectWave(outputFilename, waveInfo) = 0 Then _
    test_Fail "endurance output is not valid PCM WAV"
If waveInfo.audioFormat <> 1 OrElse waveInfo.bitsPerSample <> 16 OrElse _
    waveInfo.channelCount <> 2 OrElse _
    waveInfo.sampleFrames <> CULngInt(totalFrames) Then _
    test_Fail "endurance WAV properties or frame count are incorrect"
If scheduledNotes < TEST_MINIMUM_NOTES Then _
    test_Fail "endurance render scheduled too few notes"

' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
Dim As ULongInt probeFrames = waveInfo.sampleRate
If probeFrames > waveInfo.sampleFrames Then
    probeFrames = waveInfo.sampleFrames
End If
Dim As Integer initialPeak = test_WavePeakRange(outputFilename, 0, _
    probeFrames, waveInfo.channelCount)
Dim As Integer finalPeak = test_WavePeakRange(outputFilename, _
    waveInfo.sampleFrames - probeFrames, probeFrames, waveInfo.channelCount)
If initialPeak < 200 OrElse finalPeak < 200 Then _
    test_Fail "software synthesis did not remain audible through the render"
If initialPeak >= 32767 OrElse finalPeak >= 32767 Then _
    test_Fail "sustained software synthesis clipped at full scale"

' -------------------------------------------------------------------------
' Full runtime restart and retained-state recovery
' -------------------------------------------------------------------------

Dim As Integer originalRuntimeGeneration = sfxRuntime_GetGeneration()
If sfxRuntime_Restart() = 0 Then _
    test_Fail "sound runtime could not restart after the endurance render"
If sfxRuntime_GetGeneration() = originalRuntimeGeneration Then _
    test_Fail "sound runtime generation did not advance after restart"
If fb_sfxInstrumentDefined(0) <> 0 OrElse _
    fb_sfxInstrumentDefined(15) <> 0 Then _
    test_Fail "runtime restart retained stale synthesizer definitions"

Dim As String recoveryFilename = outputFilename + ".recovery.wav"
Dim As OseWavExportState recoveryState
wavExport_Initialize recoveryState
If wavExport_Begin(recoveryState, recoveryFilename, TEST_RECOVERY_SECONDS, _
    errorText) = 0 Then _
    test_Fail "post-restart capture could not start: " + errorText

' Long matches sfxlib's fixed 32-bit frame-count ABI.
' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
Dim As Long recoveryTotalFrames = CLng(TEST_RECOVERY_SECONDS * _
    CDbl(recoveryState.sampleRate))
If recoveryTotalFrames <= 0 Then _
    test_Fail "post-restart frame count is invalid"

Dim As OsePlaybackMixValues recoveryMix
playbackMix_Calculate recoveryMix, 112, 120, 64, 112, 0.30, -1
Dim As OseSoftwareSynthPlayOptions recoveryOptions
recoveryOptions.bankNumber = 0
recoveryOptions.fallbackVoiceChannel = -1
Dim As Integer recoveryNoteResult = softwareSynth_PlayMidiNote( _
    0, 69, 0, 8192, 0.75, recoveryMix, recoveryOptions)
If recoveryNoteResult = 0 Then _
    test_Fail "production synth rejected the post-restart note"
If fb_sfxInstrumentDefined(0) = 0 OrElse _
    fb_sfxInstrumentDefined(15) = 0 Then _
    test_Fail "production synth did not rebuild its runtime definitions"

fb_sfxForegroundFeedBegin()
' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
Dim As Long recoveryFrame
While recoveryFrame < recoveryTotalFrames
    ' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
    Dim As Long recoveryFramesToFeed = TEST_FEED_BLOCK_FRAMES
    If recoveryFramesToFeed > recoveryTotalFrames - recoveryFrame Then _
        recoveryFramesToFeed = recoveryTotalFrames - recoveryFrame
    fb_sfxUpdate recoveryFramesToFeed
    recoveryFrame += recoveryFramesToFeed
Wend
fb_sfxForegroundFeedEnd()

' ULongInt matches sfxlib's fixed 64-bit cumulative underrun counter.
' fblint: disable-next-line FBL423 REASON: Fixed-width frame, file-offset, and underrun types match the tested sfxlib/PCM contract.
Dim As ULongInt recoveryUnderruns
If wavExport_Finish(recoveryState, recoveryUnderruns, errorText) = 0 Then _
    test_Fail "post-restart capture could not finish: " + errorText
If recoveryUnderruns <> 0 Then _
    test_Fail "post-restart render reported underruns"

Dim As OseWaveInfo recoveryWaveInfo
If audio_InspectWave(recoveryFilename, recoveryWaveInfo) = 0 Then _
    test_Fail "post-restart output is not valid PCM WAV"
If recoveryWaveInfo.audioFormat <> 1 OrElse _
    recoveryWaveInfo.bitsPerSample <> 16 OrElse _
    recoveryWaveInfo.channelCount <> 2 OrElse _
    recoveryWaveInfo.sampleFrames <> CULngInt(recoveryTotalFrames) Then _
    test_Fail "post-restart WAV properties or frame count are incorrect"
Dim As Integer recoveryPeak = test_WavePeakRange(recoveryFilename, 0, _
    recoveryWaveInfo.sampleFrames, recoveryWaveInfo.channelCount)
If recoveryPeak < 200 OrElse recoveryPeak >= 32767 Then _
    test_Fail "software synthesis was silent or clipped after runtime restart"

Print "playback_endurance=ok"
Print "render_seconds="; TEST_RENDER_SECONDS; _
    " scheduled_notes="; scheduledNotes
Print "frames="; waveInfo.sampleFrames; " initial_peak="; initialPeak; _
    " final_peak="; finalPeak
Print "underruns="; underrunCount
Print "runtime_restart=ok generation="; sfxRuntime_GetGeneration(); _
    " recovery_peak="; recoveryPeak; _
    " recovery_underruns="; recoveryUnderruns
sfxRuntime_Shutdown()
End 0

/' end of tests/playback_endurance_smoke.bas '/
