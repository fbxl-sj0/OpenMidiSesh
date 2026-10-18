/'
    Project: OpenMidiSesh
    ---------------------------

    File: midi_thread_timing_smoke.bas

    Module API: Test executable; process status reports failed timing assertions.

    Copyright (C) 2026 OpenMidiSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: Linux ALSA MIDI input and output backends.

    Purpose:

        Verify input timestamps are captured while the editor is not polling
        the queue, as happens when a frame takes too long to render.

    Responsibilities:

        - find the local ALSA Midi Through loopback endpoint
        - send two events with a known delay without polling input
        - verify the captured timestamp interval retains that delay

    This file intentionally does NOT contain:

        - physical device assumptions or graphical UI operations
        - recording-model edits
        - MIDI file loading or saving
'/

#lang "fb"

#include once "midi_input.bi"
#include once "midi_output.bi"

Private Sub test_CloseDevices()
    midiOutput_AllNotesOff()
    midiOutput_Close()
    midiInput_Close()
End Sub


Private Sub test_Fail(ByVal message As String)
    test_CloseDevices()
    Print "ERROR: "; message
    End 1
End Sub


Private Function test_FindMidiThrough( _
    ByVal inputEndpoint As Integer _
) As Integer
    Dim As Integer endpointCount
    If inputEndpoint <> 0 Then
        endpointCount = midiInput_GetDeviceCount()
    Else
        endpointCount = midiOutput_GetDeviceCount()
    End If

    For endpointIndex As Integer = 0 To endpointCount - 1
        Dim As String endpointName
        If inputEndpoint <> 0 Then
            endpointName = midiInput_GetDeviceName(endpointIndex)
        Else
            endpointName = midiOutput_GetDeviceName(endpointIndex)
        End If
        If InStr(LCase(endpointName), "midi through") > 0 Then _
            Return endpointIndex
    Next
    Return -1
End Function


Dim As Integer inputIndex = test_FindMidiThrough(-1)
Dim As Integer outputIndex = test_FindMidiThrough(0)
If inputIndex < 0 OrElse outputIndex < 0 Then _
    test_Fail "ALSA Midi Through loopback was not enumerated"

If midiInput_Open(inputIndex) = 0 Then _
    test_Fail "MIDI input could not be opened"
If midiOutput_Open(outputIndex) = 0 Then _
    test_Fail "MIDI output could not be opened"
midiInput_ClearPending()

If midiOutput_Send(&H90, 60, 100) = 0 Then _
    test_Fail "MIDI note-on was rejected"
Sleep 250, 1
If midiOutput_Send(&H80, 60, 0) = 0 Then _
    test_Fail "MIDI note-off was rejected"

' Deliberately leave the queue unread while the second event is timestamped.
Sleep 250, 1

Dim As Integer receivedCount
Dim As OseMidiInputMessage receivedMessages(0 To 1)
Dim As Double startTime = Timer
Do
    While receivedCount < 2 AndAlso midiInput_Poll( _
        receivedMessages(receivedCount)) <> 0
        receivedCount += 1
    Wend
    If receivedCount = 2 Then Exit Do

    Dim As Double elapsed = Timer - startTime
    If elapsed < 0.0 Then elapsed += 86400.0
    If elapsed >= 2.0 Then Exit Do
    Sleep 1, 1
Loop

If receivedCount <> 2 Then _
    test_Fail "loopback did not return both events after delayed polling"
If receivedMessages(0).status <> &H90 OrElse _
    receivedMessages(0).data1 <> 60 OrElse _
    receivedMessages(1).status <> &H80 OrElse _
    receivedMessages(1).data1 <> 60 Then _
    test_Fail "loopback events arrived out of order or with wrong data"

Dim As ULong timestampDelta = _
    receivedMessages(1).timestampMilliseconds - _
    receivedMessages(0).timestampMilliseconds
If timestampDelta < 150 OrElse timestampDelta > 1000 Then _
    test_Fail "timestamp interval did not retain the delayed note-off"

Print "midi_thread_timing=ok"
Print "timestamp_delta_ms="; timestampDelta
test_CloseDevices()
End 0

/' end of midi_thread_timing_smoke.bas '/
