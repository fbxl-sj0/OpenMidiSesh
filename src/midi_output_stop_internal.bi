/'
    Project: OpenSesh
    ---------------------------

    File: midi_output_stop_internal.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Internal midiOutput_SendStopSequence using the including backend callback.

    Purpose:

        Share the transport stop sequence between native MIDI backends.

    Responsibilities:

        - release sustain and sostenuto before sending all-notes-off
        - silence remaining voices on all sixteen MIDI channels
        - stop sending when the backend reports a device failure

    This file intentionally does NOT contain:

        - device ownership or operating-system calls
        - normal playback controller setup
        - note scheduling
'/

#ifndef __OSE_MIDI_OUTPUT_STOP_INTERNAL_BI__
#define __OSE_MIDI_OUTPUT_STOP_INTERNAL_BI__

#include once "midi_output.bi"

Private Sub midiOutput_SendStopSequence()
    /'
        All Notes Off (CC123) obeys held pedals and envelope releases. A
        transport stop must also release sustain (CC64) and sostenuto (CC66),
        then use All Sound Off (CC120) to silence remaining voices. Keeping
        the pedal releases supports older receivers without CC120 support.
        Subsequent playback reconstructs its controllers from the song.
    '/
    For channelIndex As Integer = 0 To 15
        Dim As Integer statusByte = &HB0 Or channelIndex
        If midiOutput_Send(statusByte, 64, 0) = 0 Then Exit Sub
        If midiOutput_Send(statusByte, 66, 0) = 0 Then Exit Sub
        If midiOutput_Send(statusByte, 123, 0) = 0 Then Exit Sub
        If midiOutput_Send(statusByte, 120, 0) = 0 Then Exit Sub
    Next
End Sub

#endif

/' end of midi_output_stop_internal.bi '/
