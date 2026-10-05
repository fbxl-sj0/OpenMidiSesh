/'
    Project: OpenSesh
    ---------------------------

    File: playback_state.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: playbackState_* channel automation with OsePlaybackChannelState.

    Purpose:

        Declare the bounded MIDI channel state reconstructed during playback.

    Responsibilities:

        - hold bank, program, volume, expression, pan, and pitch bend per channel
        - initialize all sixteen channels to General MIDI defaults
        - apply supported channel events in timeline order

    This file intentionally does NOT contain:

        - event sorting or clock advancement
        - audio-library calls
        - external MIDI output
'/

#ifndef __OSE_PLAYBACK_STATE_BI__
#define __OSE_PLAYBACK_STATE_BI__

#include once "midi_model.bi"

Const OSE_PLAYBACK_CHANNEL_COUNT As Integer = 16

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OsePlaybackChannelState
    As UByte bankSelectMsb(0 To OSE_PLAYBACK_CHANNEL_COUNT - 1)
    As UByte bankSelectLsb(0 To OSE_PLAYBACK_CHANNEL_COUNT - 1)
    As UByte programNumber(0 To OSE_PLAYBACK_CHANNEL_COUNT - 1)
    As UByte controllerVolume(0 To OSE_PLAYBACK_CHANNEL_COUNT - 1)
    As UByte controllerExpression(0 To OSE_PLAYBACK_CHANNEL_COUNT - 1)
    As UByte controllerPan(0 To OSE_PLAYBACK_CHANNEL_COUNT - 1)
    As Integer pitchBend(0 To OSE_PLAYBACK_CHANNEL_COUNT - 1)
End Type

Declare Sub playbackState_Initialize(ByRef state As OsePlaybackChannelState)
Declare Function playbackState_Apply( _
    ByRef state As OsePlaybackChannelState, _
    ByRef channelEvent As MidiChannelEventPoint _
) As Integer

Declare Function playbackState_BankNumber( _
    ByRef state As OsePlaybackChannelState, _
    ByVal channelIndex As Integer _
) As Integer

#endif

/' end of playback_state.bi '/
