/'
    Project: OpenSesh
    ---------------------------

    File: playback_mix.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: playbackMix_Calculate with OsePlaybackMixValues and voice headroom.

    Purpose:

        Declare the gain and pan values used by the software synthesizer for
        one MIDI note and its channel.

    Responsibilities:

        - normalize bounded MIDI controller and velocity values
        - keep per-note velocity separate from channel CC7 and CC11 gain
        - calculate channel pan and meter gain from the same playback state
        - silence every output when the channel is not audible

    This file intentionally does NOT contain:

        - sfxlib commands
        - MIDI event scheduling
        - mixer widgets or meter animation
'/

#ifndef __OSE_PLAYBACK_MIX_BI__
#define __OSE_PLAYBACK_MIX_BI__

Const OSE_PLAYBACK_VOICE_HEADROOM As Single = 0.45

' The synthesizer applies voiceGain in SOUND and channelGain through the
' channel VOLUME command. Keeping the two stages explicit prevents CC7 from
' being applied both places, which would incorrectly square channel volume.
' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OsePlaybackMixValues
    As Single channelGain
    As Single meterGain
    As Single voiceGain
    As Single pan
End Type

Declare Sub playbackMix_Calculate( _
    ByRef values As OsePlaybackMixValues, _
    ByVal controllerVolume As Integer, _
    ByVal controllerExpression As Integer, _
    ByVal controllerPan As Integer, _
    ByVal noteVelocity As Integer, _
    ByVal masterVolume As Single, _
    ByVal audible As Integer _
)

#endif

/' end of playback_mix.bi '/
