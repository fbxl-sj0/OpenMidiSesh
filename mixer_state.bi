/'
    Project: OpenSesh
    ---------------------------

    File: mixer_state.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: mixerState_* mute/solo/record operations with OseMixerChannelState.

    Purpose:

        Declare the bounded Mute, Solo, and Record state behind each mixer
        channel strip.

    Responsibilities:

        - initialize all channel buttons to an inactive state
        - toggle Mute and Solo independently on every channel
        - enforce one exclusive step-record channel
        - resolve final channel audibility from Mute and Solo state

    This file intentionally does NOT contain:

        - graphical hit testing
        - MIDI or audio commands
        - transport or step-note insertion
'/

#ifndef __OSE_MIXER_STATE_BI__
#define __OSE_MIXER_STATE_BI__

#include once "mixer_controls.bi"

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseMixerChannelState
    As Integer mute(0 To OSE_MIXER_CHANNEL_COUNT - 1)
    As Integer solo(0 To OSE_MIXER_CHANNEL_COUNT - 1)
    As Integer record(0 To OSE_MIXER_CHANNEL_COUNT - 1)
End Type

Declare Sub mixerState_Initialize(ByRef state As OseMixerChannelState)
Declare Function mixerState_ToggleMute( _
    ByRef state As OseMixerChannelState, _
    ByVal channelIndex As Integer _
) As Integer
Declare Function mixerState_ToggleSolo( _
    ByRef state As OseMixerChannelState, _
    ByVal channelIndex As Integer _
) As Integer
Declare Function mixerState_ToggleRecord( _
    ByRef state As OseMixerChannelState, _
    ByVal channelIndex As Integer _
) As Integer
Declare Function mixerState_HasSolo( _
    ByRef state As OseMixerChannelState _
) As Integer
Declare Function mixerState_IsAudible( _
    ByRef state As OseMixerChannelState, _
    ByVal channelIndex As Integer _
) As Integer
Declare Function mixerState_RecordChannel( _
    ByRef state As OseMixerChannelState _
) As Integer

#endif

/' end of mixer_state.bi '/
