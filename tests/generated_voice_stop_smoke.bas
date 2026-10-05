/'
    Project: OpenSesh
    ---------------------------

    File: tests/generated_voice_stop_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Module API: Test executable requiring SFXLIB_DRIVER=null; supplies a private
        stop-worker callback and uses the raw mixer bridge to inspect generated audio.

    Purpose:

        Verify the production generated-voice stop helper with real mixed PCM.

    Responsibilities:

        - require the null output driver before any runtime initialization
        - show that sample-only SFX STOP leaves SOUND and NOISE playing
        - prove generated voices become silent at the next rendered block
        - preserve another channel's generated voice while stopping one channel
        - exclude concurrent stop calls while the renderer owns the runtime lock

    Ownership and threading:

        RawOpen suspends automatic mixing. This test owns the render clock and
        uses the same locked mixer process/read bridge as the SoundFont worker.
        It uses C int signatures through Long on 32- and 64-bit FB targets.
        A separate mutex protects the stop worker's handshake; bounded waits
        give that worker a chance to attempt Stop while rendering is locked.

    This file intentionally does NOT contain:

        - hardware audio or MIDI endpoints
        - private runtime structure layouts or synthetic replacement mixers
        - audio performance thresholds or waveform snapshot matching
'/

#lang "fb"

#include once "sfxlib_raw.bi"
#include once "../generated_voice_stop_internal.bi"

Declare Sub test_RuntimeLock CDecl Alias "fb_sfxRuntimeLock" ()
Declare Sub test_RuntimeUnlock CDecl Alias "fb_sfxRuntimeUnlock" ()
Declare Sub test_MixerProcess CDecl Alias "fb_sfxMixerProcess" (ByVal frames As Long)
Declare Function test_MixBufferRead CDecl Alias "fb_sfxMixBufferRead" ( _
    ByVal samples As Single Ptr, ByVal frames As Long _
) As Long

Const TEST_RENDER_FRAMES As Integer = 256
Const TEST_WORKER_TIMEOUT_SECONDS As Double = 3.0
Dim Shared test_StopMutex As Any Ptr
Dim Shared test_StopEntered As Integer
Dim Shared test_StopReturned As Integer

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub

Private Function test_RenderEnergy() As Double
    Dim As Single samples(0 To TEST_RENDER_FRAMES * 2 - 1)
    test_RuntimeLock()
    test_MixerProcess TEST_RENDER_FRAMES
    Dim As Long copiedFrames = test_MixBufferRead(@samples(0), TEST_RENDER_FRAMES)
    test_RuntimeUnlock()
    If copiedFrames <> TEST_RENDER_FRAMES Then
        test_Fail "mixer returned a short block"
    End If
    Dim As Double energy
    For sampleIndex As Integer = 0 To TEST_RENDER_FRAMES * 2 - 1
        energy += CDbl(samples(sampleIndex)) * CDbl(samples(sampleIndex))
    Next
    Return energy
End Function

Private Function test_Elapsed(ByVal startClock As Double) As Double
    Dim As Double elapsedSeconds = Timer - startClock
    If elapsedSeconds < 0.0 Then
        elapsedSeconds += 86400.0
    End If
    Return elapsedSeconds
End Function

Private Sub test_StopWorker(ByVal unused As Any Ptr)
    MutexLock test_StopMutex
    test_StopEntered = -1
    MutexUnlock test_StopMutex
    generatedVoiceStop_Channel 0
    MutexLock test_StopMutex
    test_StopReturned = -1
    MutexUnlock test_StopMutex
End Sub

Private Sub test_CheckStopExclusion()
    test_StopMutex = MutexCreate()
    If test_StopMutex = 0 Then
        test_Fail "could not create stop-worker handshake"
    End If
    sound 0, 440, 8.0, 0.5
    test_RuntimeLock()
    Dim As Any Ptr stopWorker = ThreadCreate(@test_StopWorker, 0)
    If stopWorker = 0 Then
        test_RuntimeUnlock()
        MutexDestroy test_StopMutex
        test_Fail "could not create concurrent stop worker"
    End If

    Dim As String failureText
    Dim As Double waitClock = Timer
    Do
        MutexLock test_StopMutex
        Dim As Integer entered = test_StopEntered
        MutexUnlock test_StopMutex
        If entered <> 0 Then
            Exit Do
        End If
        If test_Elapsed(waitClock) >= TEST_WORKER_TIMEOUT_SECONDS Then
            failureText = "stop worker did not reach its call barrier"
            Exit Do
        End If
        Sleep 1, 1
    Loop

    ' The rendering owner retains its lock while the other thread attempts
    ' the production helper. An unlocked helper silences this live fixture.
    If Len(failureText) = 0 Then
        For observation As Integer = 1 To 100
            If test_RenderEnergy() <= 0.000001 Then
                failureText = "concurrent Stop changed a renderer-owned voice"
                Exit For
            End If
            MutexLock test_StopMutex
            Dim As Integer returned = test_StopReturned
            MutexUnlock test_StopMutex
            If returned <> 0 Then
                failureText = "concurrent Stop returned while the renderer held its lock"
                Exit For
            End If
            Sleep 1, 1
        Next
    End If
    test_RuntimeUnlock()
    ThreadWait stopWorker
    MutexDestroy test_StopMutex
    test_StopMutex = 0
    If Len(failureText) <> 0 Then
        test_Fail failureText
    End If
    If test_RenderEnergy() <> 0.0 Then _
        test_Fail "concurrent Stop did not finish after the renderer unlocked"
End Sub

If Environ("SFXLIB_DRIVER") <> "null" Then _
    test_Fail "set SFXLIB_DRIVER=null before running this test"
If sfxlib.RawOpen() <= 0 Then
    test_Fail "null raw output could not be initialized"
End If

For voiceKind As Integer = 0 To 1
    For channelIndex As Integer = 0 To 1
        volume channelIndex, 1.0
        pan channelIndex, 0.0
        If voiceKind = 0 Then
            sound channelIndex, 440 + channelIndex * 110, 8.0, 0.5
        Else
            noise channelIndex, 8.0, 0.5
        End If
    Next
    If test_RenderEnergy() <= 0.000001 Then _
        test_Fail "generated fixture was silent before Stop"

    SFX STOP CHANNEL, 0
    SFX STOP CHANNEL, 1
    If test_RenderEnergy() <= 0.000001 Then _
        test_Fail "fixture did not expose sample-only Stop behavior"

    generatedVoiceStop_Channel 0
    If test_RenderEnergy() <= 0.000001 Then _
        test_Fail "stopping one generated channel also stopped its neighbor"
    generatedVoiceStop_Channel 1
    If test_RenderEnergy() <> 0.0 Then _
        test_Fail "a generated voice survived the transport stop helper"
Next

test_CheckStopExclusion()
sfxlib.RawClose()
Print "generated_voice_stop=ok sound=1 noise=1 channel_isolation=1 lock_exclusion=1"
End 0

/' end of tests/generated_voice_stop_smoke.bas '/
