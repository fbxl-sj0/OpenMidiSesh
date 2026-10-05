/'
    Project: OpenSesh
    File: tests/soundfont_shutdown_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Module API: Test executable providing SoundFont-bank and C runtime stubs
        to exercise the production worker's shutdown against a controlled write barrier.

    Purpose: Reproduce a raw write racing SoundFont output shutdown.
    Responsibilities: Run the production worker, suspend its write after the
        stop check, and require teardown to release exclusive raw output.
    Ownership and threading: A test mutex protects shared worker state.
    This file intentionally does NOT contain:

        - native device access or SF2 parsing
        - test-only branches in the production synthesizer
'/

#lang "fb"

#include once "../soundfont_synth.bi"
#include once "../soundfont_bank.bi"

Const TEST_SHUTDOWN_TIMEOUT_SECONDS As Double = 3.0
Dim Shared test_Mutex As Any Ptr
Dim Shared test_RawActive As Integer
Dim Shared test_WriteEntered As Integer
Dim Shared test_ReopenedAfterClose As Integer
Dim Shared test_CloseCalls As Integer
Dim Shared test_FailNextWrite As Integer
Dim Shared test_WriteFailures As Integer

Private Function test_Elapsed(ByVal startClock As Double) As Double
    Dim As Double elapsedSeconds = Timer - startClock
    If elapsedSeconds < 0.0 Then
        elapsedSeconds += 86400.0
    End If
    Return elapsedSeconds
End Function

Private Sub test_Fail(ByVal messageText As String)
    soundfontSynth_Shutdown()
    If test_Mutex <> 0 Then
        MutexDestroy test_Mutex
    End If
    Print "FAIL: "; messageText
    End 1
End Sub

' Match the runtime's documented implicit RawWrite open. The barrier places
' the actual worker between its stop check and the write's stream mutation.
Public Function fb_sfxRawOpen CDecl Alias "fb_sfxRawOpen" () As Long
    MutexLock test_Mutex
    test_RawActive = -1
    MutexUnlock test_Mutex
    Return 48000
End Function

Public Sub fb_sfxRawClose CDecl Alias "fb_sfxRawClose" ()
    MutexLock test_Mutex
    test_RawActive = 0
    test_CloseCalls += 1
    MutexUnlock test_Mutex
End Sub

Public Function fb_sfxRawWrite CDecl Alias "fb_sfxRawWrite" ( _
    ByVal samples As Const Single Ptr, _
    ByVal frames As Long, _
    ByVal channels As Long _
) As Long
    If samples = 0 OrElse frames <= 0 OrElse channels <> 2 Then
        Return -1
    End If
    MutexLock test_Mutex
    If test_FailNextWrite <> 0 Then
        test_FailNextWrite = 0
        test_WriteFailures += 1
        MutexUnlock test_Mutex
        Return -1
    End If
    test_WriteEntered = -1
    MutexUnlock test_Mutex
    Dim As Double startClock = Timer
    Do
        MutexLock test_Mutex
        Dim As Integer closeObserved = test_CloseCalls > 0
        If closeObserved <> 0 Then
            test_RawActive = -1
            test_ReopenedAfterClose = -1
        End If
        MutexUnlock test_Mutex
        If closeObserved <> 0 Then
            Return frames
        End If
        If test_Elapsed(startClock) >= TEST_SHUTDOWN_TIMEOUT_SECONDS Then
            Return -1
        End If
        Sleep 1, 1
    Loop
End Function

Public Sub fb_sfxRuntimeLock CDecl Alias "fb_sfxRuntimeLock" ()
End Sub

Public Sub fb_sfxRuntimeUnlock CDecl Alias "fb_sfxRuntimeUnlock" ()
End Sub

Public Sub fb_sfxMixerProcess CDecl Alias "fb_sfxMixerProcess" (ByVal frames As Integer)
End Sub

Public Function fb_sfxMixBufferRead CDecl Alias "fb_sfxMixBufferRead" ( _
    ByVal samples As Single Ptr, ByVal frames As Integer _
) As Integer
    If samples = 0 OrElse frames <= 0 Then
        Return 0
    End If
    For sampleIndex As Integer = 0 To frames * 2 - 1
        samples[sampleIndex] = 0.0
    Next
    Return frames
End Function

Public Function fb_sfxBufferFrames CDecl Alias "fb_sfxBufferFrames" () As Integer
    Return 256
End Function

' A bank is present so ResumeOutput starts the real worker. No voice is
' requested; the renderer sees an empty sample buffer and leaves silence.
Public Function soundfontBank_IsLoaded() As Integer
    Return -1
End Function

Public Function soundfontBank_GetSampleData() As Short Ptr
    Return 0
End Function

Public Function soundfontBank_Load( _
    ByVal filename As String, ByRef errorText As String _
) As Integer
    Return 0
End Function

Public Sub soundfontBank_Clear()
End Sub

Public Function soundfontBank_GetFilename() As String
    Return ""
End Function

Public Function soundfontBank_GetName() As String
    Return ""
End Function

Public Function soundfontBank_Resolve( _
    ByVal bankNumber As Integer, ByVal programNumber As Integer, _
    ByVal keyNumber As Integer, ByVal velocity As Integer, _
    regions() As OseSoundFontVoiceRegion _
) As Integer
    Return 0
End Function

Dim As String errorText
Dim As Double failureWaitClock
Dim As Double writeWaitClock
Dim As Integer failedWritesObserved
Dim As Integer workerClosedStream
Dim As Integer failureWriteCount
Dim As Integer failureCloseCalls
Dim As Integer failureRawActive
Dim As Integer writeEntered
Dim As Integer reopenedAfterClose
Dim As Integer rawStillActive
Dim As Integer closeCalls

test_Mutex = MutexCreate()
If test_Mutex = 0 Then
    test_Fail "could not create the test synchronization lock"
End If
test_FailNextWrite = -1
soundfontSynth_ResumeOutput errorText
failureWaitClock = Timer
Do
    MutexLock test_Mutex
    failedWritesObserved = test_WriteFailures
    workerClosedStream = test_CloseCalls > 0 AndAlso _
        test_RawActive = 0
    MutexUnlock test_Mutex
    If failedWritesObserved > 0 AndAlso workerClosedStream <> 0 AndAlso _
        soundfontSynth_IsActive() = 0 Then
        Exit Do
    End If
    If test_Elapsed(failureWaitClock) >= _
        TEST_SHUTDOWN_TIMEOUT_SECONDS Then _
        test_Fail "worker did not close the stream after a raw-write failure"
    Sleep 1, 1
Loop
soundfontSynth_SuspendOutput()
MutexLock test_Mutex
failureWriteCount = test_WriteFailures
failureCloseCalls = test_CloseCalls
failureRawActive = test_RawActive
MutexUnlock test_Mutex
If failureWriteCount <> 1 OrElse failureCloseCalls < 3 OrElse _
    failureRawActive <> 0 OrElse soundfontSynth_IsActive() <> 0 Then
    test_Fail "worker write failure did not immediately release raw output"
End If

soundfontSynth_Shutdown()
MutexDestroy test_Mutex
test_Mutex = 0
test_RawActive = 0
test_WriteEntered = 0
test_ReopenedAfterClose = 0
test_CloseCalls = 0
test_FailNextWrite = 0
test_WriteFailures = 0
test_Mutex = MutexCreate()
If test_Mutex = 0 Then
    test_Fail "could not recreate the test synchronization lock"
End If

If soundfontSynth_ResumeOutput(errorText) = 0 Then _
    test_Fail "could not start the production worker: " + errorText

writeWaitClock = Timer
Do
    MutexLock test_Mutex
    writeEntered = test_WriteEntered
    MutexUnlock test_Mutex
    If writeEntered <> 0 Then
        Exit Do
    End If
    If test_Elapsed(writeWaitClock) >= TEST_SHUTDOWN_TIMEOUT_SECONDS Then _
        test_Fail "the production worker did not reach the write barrier"
    Sleep 1, 1
Loop

soundfontSynth_SuspendOutput()
MutexLock test_Mutex
reopenedAfterClose = test_ReopenedAfterClose
rawStillActive = test_RawActive
closeCalls = test_CloseCalls
MutexUnlock test_Mutex
If reopenedAfterClose = 0 Then _
    test_Fail "the fixture did not force a write after the first close"
If rawStillActive <> 0 OrElse soundfontSynth_IsActive() <> 0 Then _
    test_Fail "shutdown left exclusive raw output active after the worker exited"

soundfontSynth_Shutdown()
MutexDestroy test_Mutex
test_Mutex = 0
Print "soundfont_shutdown=ok failed_write_closed=1 write_after_close=1 final_raw_active=0 close_calls="; closeCalls
End 0

/' end of tests/soundfont_shutdown_smoke.bas '/
