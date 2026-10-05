/'
    Project: OpenSesh
    ---------------------------

    File: midi_input_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Exercise the optional MIDI-input interface without requiring a
        physical MIDI device to be attached to the test machine.

    Responsibilities:

        - verify safe device enumeration and invalid-device rejection
        - verify close, clear, and polling are harmless when no device is open

    This file intentionally does NOT contain:

        - simulated callback access to private backend state
        - graphical UI or recording-model edits
        - assumptions that a Windows or Linux MIDI device exists
'/

#lang "fb"

#include once "../midi_input.bi"

Dim As Integer deviceCount = midiInput_GetDeviceCount()
If deviceCount < 0 Then
    Print "ERROR: negative MIDI input device count"
    End 1
End If

For deviceIndex As Integer = 0 To deviceCount - 1
    Dim As String deviceName = midiInput_GetDeviceName(deviceIndex)
    If Trim(deviceName) = "" Then
        Print "ERROR: MIDI input device has no name"
        End 1
    End If
Next deviceIndex
If midiInput_GetDeviceName(-1) <> "" OrElse _
    midiInput_GetDeviceName(deviceCount) <> "" Then
    Print "ERROR: invalid MIDI input device returned a name"
    End 1
End If

If midiInput_Open(-1) <> 0 Then
    Print "ERROR: invalid MIDI input device was accepted"
    End 1
End If
If midiInput_IsOpen() <> 0 OrElse midiInput_GetOpenDeviceIndex() <> -1 Then
    Print "ERROR: rejected MIDI input left a device marked open"
    End 1
End If

Dim As OseMidiInputMessage message
midiInput_ClearPending()
If midiInput_Poll(message) <> 0 Then
    Print "ERROR: empty MIDI input queue returned a message"
    End 1
End If

midiInput_Close()
midiInput_Close()
If midiInput_IsOpen() <> 0 OrElse midiInput_GetOpenDeviceIndex() <> -1 Then
    Print "ERROR: close retained MIDI input device state"
    End 1
End If
If midiInput_GetDroppedCount() <> 0 Then
    Print "ERROR: empty MIDI input queue reported dropped messages"
    End 1
End If
Print "midi_input=ok"
Print "devices="; deviceCount
Print "dropped="; midiInput_GetDroppedCount()
End 0

/' end of midi_input_smoke.bas '/
