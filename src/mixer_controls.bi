/'
    Project: OpenSesh
    ---------------------------

    File: mixer_controls.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: mixerControls_* hit/layout operations with OseMixerControlLayout and OseMixerControlHit.

    Purpose:

        Declare one coordinate contract for every code-drawn mixer control.

    Responsibilities:

        - calculate responsive channel-strip and master layout
        - identify the channel and control under a pointer coordinate
        - convert fader and knob positions into normalized values
        - expose enough geometry for drawing and interaction to stay aligned

    This file intentionally does NOT contain:

        - MIDI model mutation
        - sfxlib mixer commands
        - rendering primitives or pointer polling
'/

#ifndef __OSE_MIXER_CONTROLS_BI__
#define __OSE_MIXER_CONTROLS_BI__

#include once "ui_interaction.bi"

Const OSE_MIXER_HEIGHT As Integer = 238
Const OSE_MIXER_CHANNEL_COUNT As Integer = 16
Const OSE_MIXER_MASTER_WIDTH As Integer = 164
Const OSE_MIXER_MINIMUM_STRIP_WIDTH As Integer = 58
Const OSE_MIXER_TOUCH_MINIMUM_STRIP_WIDTH As Integer = 88
Const OSE_MIXER_TITLE_HEIGHT As Integer = 24

Const OSE_MIXER_CONTROL_NONE As Integer = 0
Const OSE_MIXER_CONTROL_CHANNEL_FADER As Integer = 1
Const OSE_MIXER_CONTROL_CHANNEL_CHORUS As Integer = 2
Const OSE_MIXER_CONTROL_CHANNEL_REVERB As Integer = 3
Const OSE_MIXER_CONTROL_CHANNEL_PAN As Integer = 4
Const OSE_MIXER_CONTROL_CHANNEL_MUTE As Integer = 5
Const OSE_MIXER_CONTROL_CHANNEL_SOLO As Integer = 6
Const OSE_MIXER_CONTROL_CHANNEL_RECORD As Integer = 7
Const OSE_MIXER_CONTROL_MASTER_FADER As Integer = 8
Const OSE_MIXER_CONTROL_MASTER_WET As Integer = 9
Const OSE_MIXER_CONTROL_MASTER_FEEDBACK As Integer = 10
Const OSE_MIXER_CONTROL_PAGE_PREVIOUS As Integer = 11
Const OSE_MIXER_CONTROL_PAGE_NEXT As Integer = 12
Const OSE_MIXER_PAGE_BUTTON_WIDTH As Integer = 20
Const OSE_MIXER_PAGE_BUTTON_HEIGHT As Integer = 16

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseMixerControlLayout
    As Integer mixerTop
    As Integer mixerLeft
    As Integer masterLeft
    As Integer channelAreaWidth
    As Integer visibleCount
    As Integer firstChannel
    As Integer stripWidth
    As Integer faderTop
    As Integer faderBottom
    As Integer knobTop
    As Integer knobBottom
    As Integer knobCenterY
    As Integer nameBoxTop
    As Integer buttonTop
    As Integer buttonHeight
    As Integer pagePreviousLeft
    As Integer pageNextLeft
    As Integer pageButtonTop
    As Integer pageButtonWidth
    As Integer pageButtonHeight
End Type

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseMixerControlHit
    As Integer kind
    As Integer channelIndex
    As Integer slotIndex
    As Single normalizedValue
End Type

Declare Sub mixerControls_CalculateLayout( _
    ByRef layout As OseMixerControlLayout, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal selectedChannel As Integer _
)

Declare Sub mixerControls_CalculateLayoutForInteraction( _
    ByRef layout As OseMixerControlLayout, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal selectedChannel As Integer, _
    ByVal interactionMode As Integer _
)

Declare Function mixerControls_ChannelAtX( _
    ByRef layout As OseMixerControlLayout, _
    ByVal pointerX As Integer _
) As Integer

Declare Function mixerControls_StripLeft( _
    ByRef layout As OseMixerControlLayout, _
    ByVal slotIndex As Integer _
) As Integer

Declare Function mixerControls_StripRight( _
    ByRef layout As OseMixerControlLayout, _
    ByVal slotIndex As Integer _
) As Integer

Declare Function mixerControls_ChannelFaderX( _
    ByRef layout As OseMixerControlLayout, _
    ByVal slotIndex As Integer _
) As Integer

Declare Sub mixerControls_HitTest( _
    ByRef controlHit As OseMixerControlHit, _
    ByRef layout As OseMixerControlLayout, _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer _
)

Declare Function mixerControls_ValueForControl( _
    ByRef layout As OseMixerControlLayout, _
    ByVal controlKind As Integer, _
    ByVal channelIndex As Integer, _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer _
) As Single

#endif

/' end of mixer_controls.bi '/
