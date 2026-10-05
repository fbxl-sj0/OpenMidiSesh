/'
    Project: OpenSesh
    ----------------------------

    File: tests/midi_output_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Module API: test MIDI backend callbacks used only by the OSE_MIDI_OUTPUT_TESTING build.

    Purpose:

        Exercise the output state machine against a simulated backend so
        strict tests never send bytes to a physical MIDI device.

    Responsibilities:

        - verify enumeration, invalid-device rejection, and closed-state safety
        - verify open and send failure cleanup and same-device recovery
        - verify valid sends and idempotent close behavior

    This file intentionally does NOT contain:

        - MIDI hardware access or loopback assumptions
        - a graphical UI or MIDI-file parser
'/

#lang "fb"

#include once "../src/midi_output.bi"

Dim Shared test_OpenCalls As Integer
Dim Shared test_CloseCalls As Integer
Dim Shared test_SendCalls As Integer
Dim Shared test_FailNextOpen As Integer
Dim Shared test_FailNextSend As Integer

Public Function midiOutput_TestBackendOpen CDecl _
    Alias "midiOutput_TestBackendOpen" (ByVal deviceIndex As Long) As Long
    If deviceIndex <> 0 Then Return 1
    test_OpenCalls += 1
    If test_FailNextOpen <> 0 Then
        test_FailNextOpen = 0
        Return 1
    End If
    Return 0
End Function

Public Sub midiOutput_TestBackendClose CDecl _
    Alias "midiOutput_TestBackendClose" ()
    test_CloseCalls += 1
End Sub

Public Function midiOutput_TestBackendSend CDecl _
    Alias "midiOutput_TestBackendSend" ( _
        ByVal statusByte As Long, _
        ByVal data1 As Long, _
        ByVal data2 As Long _
    ) As Long
    test_SendCalls += 1
    If statusByte < &H80 OrElse statusByte > &HEF OrElse _
        data1 < 0 OrElse data1 > 127 OrElse data2 < 0 OrElse data2 > 127 Then _
        Return 1
    If test_FailNextSend <> 0 Then
        test_FailNextSend = 0
        Return 1
    End If
    Return 0
End Function

If midiOutput_GetDeviceCount() <> 1 OrElse _
    midiOutput_GetDeviceName(0) <> "Simulated MIDI output" OrElse _
    midiOutput_GetDeviceName(-1) <> "" OrElse _
    midiOutput_GetDeviceName(1) <> "" Then
    Print "ERROR: simulated device enumeration was inconsistent"
    End 1
End If

If midiOutput_Open(-1) <> 0 OrElse midiOutput_Open(1) <> 0 OrElse _
    midiOutput_IsOpen() <> 0 Then
    Print "ERROR: invalid MIDI device was accepted"
    End 1
End If
If midiOutput_Send(&H90, 60, 100) <> 0 Then
    Print "ERROR: closed MIDI output accepted a message"
    End 1
End If

test_FailNextOpen = -1
If midiOutput_Open(0) <> 0 OrElse midiOutput_IsOpen() <> 0 OrElse _
    test_OpenCalls <> 1 Then
    Print "ERROR: a failed MIDI open left the endpoint marked open"
    End 1
End If
If midiOutput_Open(0) = 0 OrElse midiOutput_IsOpen() = 0 OrElse _
    test_OpenCalls <> 2 Then
    Print "ERROR: simulated MIDI output did not recover after open failure"
    End 1
End If
If midiOutput_Open(0) = 0 OrElse test_OpenCalls <> 2 Then
    midiOutput_Close()
    Print "ERROR: opening the same MIDI output was not idempotent"
    End 1
End If
If midiOutput_Send(&H7F, 60, 32) <> 0 OrElse _
    midiOutput_Send(&HF0, 60, 32) <> 0 OrElse _
    midiOutput_Send(&H90, -1, 32) <> 0 OrElse _
    midiOutput_Send(&H90, 128, 32) <> 0 OrElse _
    midiOutput_Send(&H90, 60, -1) <> 0 OrElse _
    midiOutput_Send(&H90, 60, 128) <> 0 OrElse _
    midiOutput_IsOpen() = 0 Then
    midiOutput_Close()
    Print "ERROR: malformed MIDI message changed output state"
    End 1
End If

test_FailNextSend = -1
If midiOutput_Send(&H90, 60, 100) <> 0 OrElse _
    midiOutput_IsOpen() <> 0 OrElse test_CloseCalls <> 1 Then
    midiOutput_Close()
    Print "ERROR: a send failure did not close and clear the endpoint"
    End 1
End If

If midiOutput_Open(0) = 0 OrElse midiOutput_IsOpen() = 0 OrElse _
    test_OpenCalls <> 3 Then
    midiOutput_Close()
    Print "ERROR: output could not reopen after a send failure"
    End 1
End If
If midiOutput_Send(&H90, 60, 100) = 0 OrElse _
    midiOutput_IsOpen() = 0 Then
    midiOutput_Close()
    Print "ERROR: a valid MIDI message failed after recovery"
    End 1
End If

midiOutput_AllNotesOff()
midiOutput_Close()
midiOutput_Close()
If midiOutput_IsOpen() <> 0 OrElse test_CloseCalls <> 2 Then
    Print "ERROR: close was not idempotent after recovery"
    End 1
End If

Print "midi_output=ok simulated_devices=1"
Print "open_failure_stays_closed=1 send_failure_closes=1"
Print "reopen_after_failure=1"
Print "simulated_sends="; test_SendCalls
End 0

/' end of tests/midi_output_smoke.bas '/
