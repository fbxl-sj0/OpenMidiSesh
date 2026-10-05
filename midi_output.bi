/'
    Project: OpenSesh
    ---------------------------

    File: midi_output.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: midiOutput_* endpoint enumeration, send, and stop operations.

    Purpose:

        Declare the platform-neutral short-message MIDI-output boundary used
        by transport playback and live input monitoring.

    Responsibilities:

        - enumerate native MIDI output endpoints on supported platforms
        - expose explicit open, close, and current-state operations
        - validate and send bounded MIDI 1.0 channel messages
        - provide an all-notes-off safety operation

    Ownership:

        Each backend owns its selected operating-system endpoint until
        midiOutput_Close is called or a device failure closes it.

    This file intentionally does NOT contain:

        - WinMM, sfxlib, or ALSA declarations
        - MIDI input or MIDI-file parsing
        - transport scheduling or omaGui widgets
'/

#ifndef __OSE_MIDI_OUTPUT_BI__
#define __OSE_MIDI_OUTPUT_BI__

Declare Function midiOutput_GetDeviceCount() As Integer

Declare Function midiOutput_GetDeviceName( _
    ByVal deviceIndex As Integer _
) As String

Declare Function midiOutput_Open(ByVal deviceIndex As Integer) As Integer

Declare Sub midiOutput_Close()

Declare Function midiOutput_IsOpen() As Integer

Declare Function midiOutput_Send( _
    ByVal statusByte As Integer, _
    ByVal data1 As Integer, _
    ByVal data2 As Integer _
) As Integer

Declare Sub midiOutput_AllNotesOff()

#endif

/' end of midi_output.bi '/
