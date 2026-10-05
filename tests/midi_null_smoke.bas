/'
    Project: OpenSesh
    File: midi_null_smoke.bas
    Purpose: verify the external-MIDI capability boundary on unsupported hosts.
    Responsibilities: reject opens and sends; clear poll and clock output safely.
    This file intentionally does NOT contain:
        - device emulation or software synthesis tests
    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later
    Targets: FreeBASIC fb dialect; native BSD, Haiku, and Android capability adapter.
    Module API: test executable; nonzero exit reports a broken capability contract.
'/

#lang "fb"
#include once "../src/midi_input.bi"
#include once "../src/midi_output.bi"

If midiInput_GetDeviceCount() <> 0 OrElse midiOutput_GetDeviceCount() <> 0 Then
    Print "ERROR: unavailable MIDI adapter advertised an endpoint"
    End 1
End If
For deviceIndex As Integer = -1 To 1
    If midiInput_GetDeviceName(deviceIndex) <> "" OrElse _
        midiOutput_GetDeviceName(deviceIndex) <> "" OrElse _
        midiInput_Open(deviceIndex) <> 0 OrElse _
        midiOutput_Open(deviceIndex) <> 0 Then
        Print "ERROR: unavailable MIDI adapter accepted a device"
        End 1
    End If
Next deviceIndex
Dim As OseMidiInputMessage message
' Nonzero sentinels make a missing reset observable without requiring a device.
message.deviceIndex = 123
Dim As ULong timestampMilliseconds = 123
If midiInput_Poll(message) <> 0 OrElse message.deviceIndex <> -1 OrElse _
    midiInput_GetClockMilliseconds(timestampMilliseconds) <> 0 OrElse _
    timestampMilliseconds <> 0 Then
    Print "ERROR: unavailable MIDI adapter retained output data"
    End 1
End If
If midiOutput_Send(&H90, 60, 100) <> 0 OrElse midiOutput_Send(-1, -1, -1) <> 0 Then
    Print "ERROR: unavailable MIDI adapter reported a successful send"
    End 1
End If
midiInput_ClearPending()
midiOutput_AllNotesOff()
midiInput_Close()
midiInput_Close()
midiOutput_Close()
midiOutput_Close()
If midiInput_IsOpen() <> 0 OrElse midiInput_GetOpenDeviceIndex() <> -1 OrElse _
    midiInput_GetDroppedCount() <> 0 OrElse midiOutput_IsOpen() <> 0 Then
    Print "ERROR: unavailable MIDI adapter retained endpoint state"
    End 1
End If
Print "midi_null=ok"
End 0

/' end of midi_null_smoke.bas '/
