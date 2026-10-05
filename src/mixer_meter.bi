/'
    Project: OpenSesh
    ---------------------------

    File: mixer_meter.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: mixerMeter_* observations with OseMixerMeterState.

    Purpose:

        Declare the bounded audio-activity envelope used by channel and master
        VU meters.

    Responsibilities:

        - accept activity from the same notes and clips sent to sfxlib
        - apply channel audibility, fader, pan, and master state
        - provide fast attack and time-based release behavior
        - expose independent channel and stereo master meter levels

    This file intentionally does NOT contain:

        - score playback scheduling
        - sfxlib calls or audio-device access
        - graphical meter drawing
'/

#ifndef __OSE_MIXER_METER_BI__
#define __OSE_MIXER_METER_BI__

Const OSE_MIXER_METER_CHANNEL_COUNT As Integer = 16

Type OseMixerMeterState
    As Single sourceLevel(0 To OSE_MIXER_METER_CHANNEL_COUNT - 1)
    As Double sourceSeconds(0 To OSE_MIXER_METER_CHANNEL_COUNT - 1)
    As Single displayLevel(0 To OSE_MIXER_METER_CHANNEL_COUNT - 1)
    As Single channelVolume(0 To OSE_MIXER_METER_CHANNEL_COUNT - 1)
    As Single channelPan(0 To OSE_MIXER_METER_CHANNEL_COUNT - 1)
    As Integer channelAudible(0 To OSE_MIXER_METER_CHANNEL_COUNT - 1)
    As Single masterVolume
    As Single masterLeftLevel
    As Single masterRightLevel
End Type

Declare Sub mixerMeter_Initialize(ByRef state As OseMixerMeterState)

Declare Sub mixerMeter_SetChannelMix( _
    ByRef state As OseMixerMeterState, _
    ByVal channelIndex As Integer, _
    ByVal volumeLevel As Single, _
    ByVal panPosition As Single, _
    ByVal audible As Integer _
)

Declare Sub mixerMeter_SetMasterVolume( _
    ByRef state As OseMixerMeterState, _
    ByVal volumeLevel As Single _
)

Declare Function mixerMeter_Trigger( _
    ByRef state As OseMixerMeterState, _
    ByVal channelIndex As Integer, _
    ByVal sourceLevel As Single, _
    ByVal durationSeconds As Double _
) As Integer

Declare Sub mixerMeter_StopChannel( _
    ByRef state As OseMixerMeterState, _
    ByVal channelIndex As Integer _
)

Declare Sub mixerMeter_StopAll(ByRef state As OseMixerMeterState)

Declare Sub mixerMeter_Update( _
    ByRef state As OseMixerMeterState, _
    ByVal elapsedSeconds As Double, _
    ByVal paused As Integer _
)

Declare Function mixerMeter_ChannelLevel( _
    ByRef state As OseMixerMeterState, _
    ByVal channelIndex As Integer _
) As Single

Declare Function mixerMeter_MasterLeftLevel( _
    ByRef state As OseMixerMeterState _
) As Single

Declare Function mixerMeter_MasterRightLevel( _
    ByRef state As OseMixerMeterState _
) As Single

#endif

/' end of mixer_meter.bi '/
