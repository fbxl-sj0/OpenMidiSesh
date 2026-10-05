/'
    Project: OpenSesh
    ---------------------------

    File: midi_output_setup_internal.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Internal midiOutput_SendDefaultSetupSequence using the including backend callback.

    Purpose:

        Restore a known default program and controller state for native MIDI.

    Responsibilities:

        - reset both bank selectors before selecting the default program
        - initialize the playback controllers on all sixteen channels
        - stop sending when the backend reports a device failure

    This file intentionally does NOT contain:

        - native device access or endpoint ownership
        - song-specific automation or note scheduling
'/

#ifndef __OSE_MIDI_OUTPUT_SETUP_INTERNAL_BI__
#define __OSE_MIDI_OUTPUT_SETUP_INTERNAL_BI__

#include once "midi_output.bi"

Private Sub midiOutput_SendDefaultSetupSequence()
    For channelIndex As Integer = 0 To 15
        Dim As Integer controllerStatus = &HB0 Or channelIndex
        ' A Program Change selects within the receiver's current bank. Clear
        ' both selectors first so a preceding song cannot leak its bank here.
        If midiOutput_Send(controllerStatus, 0, 0) = 0 Then Exit Sub
        If midiOutput_Send(controllerStatus, 32, 0) = 0 Then Exit Sub
        If midiOutput_Send(&HC0 Or channelIndex, 0, 0) = 0 Then Exit Sub
        If midiOutput_Send(controllerStatus, 7, 127) = 0 Then Exit Sub
        If midiOutput_Send(controllerStatus, 10, 64) = 0 Then Exit Sub
        If midiOutput_Send(controllerStatus, 11, 127) = 0 Then Exit Sub
        If midiOutput_Send(controllerStatus, 91, 40) = 0 Then Exit Sub
        If midiOutput_Send(controllerStatus, 93, 0) = 0 Then Exit Sub
        If midiOutput_Send(&HE0 Or channelIndex, 0, 64) = 0 Then Exit Sub
    Next
End Sub

#endif

/' end of midi_output_setup_internal.bi '/
