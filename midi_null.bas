/'
    Project: OpenSesh
    ---------------------------

    File: midi_null.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; selected by builds without a native MIDI backend (including Android).

    Module API: Implements midi_input.bi and midi_output.bi with unavailable-endpoint results.

    Purpose:

        Provide an honest MIDI-device boundary for targets without a native
        MIDI endpoint backend.

    Responsibilities:

        - report that no external MIDI input or output endpoints are present
        - reject invalid open and send requests without retaining state
        - satisfy the same portable interfaces used by native backends

    This file intentionally does NOT contain:

        - platform names or conditional operating-system code
        - software-synth playback, which is owned by software_synth.bas
        - silent success paths that pretend unavailable hardware is working
'/

#lang "fb"

#include once "midi_input.bi"
#include once "midi_output.bi"

' -------------------------------------------------------------------------
' Unavailable input endpoint
' -------------------------------------------------------------------------

Public Function midiInput_GetDeviceCount() As Integer
    Return 0
End Function


Public Function midiInput_GetDeviceName( _
    ByVal deviceIndex As Integer _
) As String
    Return ""
End Function


Public Function midiInput_Open(ByVal deviceIndex As Integer) As Integer
    Return 0
End Function


Public Sub midiInput_Close()
End Sub


Public Function midiInput_IsOpen() As Integer
    Return 0
End Function


Public Function midiInput_GetOpenDeviceIndex() As Integer
    Return -1
End Function


Public Sub midiInput_ClearPending()
End Sub


Public Function midiInput_GetClockMilliseconds( _
    ByRef timestampMilliseconds As ULong _
) As Integer
    timestampMilliseconds = 0
    Return 0
End Function


Public Function midiInput_Poll( _
    ByRef message As OseMidiInputMessage _
) As Integer
    Dim As OseMidiInputMessage emptyMessage
    message = emptyMessage
    message.deviceIndex = -1
    Return 0
End Function


Public Function midiInput_GetDroppedCount() As ULongInt
    Return 0
End Function


' -------------------------------------------------------------------------
' Unavailable external output endpoint
' -------------------------------------------------------------------------

Public Function midiOutput_GetDeviceCount() As Integer
    Return 0
End Function


Public Function midiOutput_GetDeviceName( _
    ByVal deviceIndex As Integer _
) As String
    Return ""
End Function


Public Function midiOutput_Open(ByVal deviceIndex As Integer) As Integer
    Return 0
End Function


Public Sub midiOutput_Close()
End Sub


Public Function midiOutput_IsOpen() As Integer
    Return 0
End Function


Public Function midiOutput_Send( _
    ByVal statusByte As Integer, _
    ByVal data1 As Integer, _
    ByVal data2 As Integer _
) As Integer
    Return 0
End Function


Public Sub midiOutput_AllNotesOff()
End Sub

/' end of midi_null.bas '/
