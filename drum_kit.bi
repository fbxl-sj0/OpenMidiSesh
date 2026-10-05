/'
    Project: OpenSesh
    ---------------------------

    File: drum_kit.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: drumKit_* pad mapping with OseDrumPadRectangle and pad constants.

    Purpose:

        Declare the portable layout and General MIDI mapping for the editor's
        playable drum kit.

    Responsibilities:

        - describe twelve named General MIDI percussion pads
        - preserve one spatial PC-key label for every pad
        - calculate responsive four-column pad rectangles
        - hit-test the exact rectangles used by the renderer
        - provide bounded soft, medium, and hard velocity choices

    This file intentionally does NOT contain:

        - window or input polling
        - drawing commands
        - synthesizer or MIDI-document operations
'/

#ifndef __OSE_DRUM_KIT_BI__
#define __OSE_DRUM_KIT_BI__

Const OSE_DRUM_PAD_COUNT As Integer = 12
Const OSE_DRUM_COLUMN_COUNT As Integer = 4
Const OSE_DRUM_ROW_COUNT As Integer = 3
Const OSE_DRUM_PAD_GAP As Integer = 10
Const OSE_DRUM_MINIMUM_PAD_SIZE As Integer = 48
Const OSE_DRUM_VELOCITY_SOFT As Integer = 72
Const OSE_DRUM_VELOCITY_MEDIUM As Integer = 100
Const OSE_DRUM_VELOCITY_HARD As Integer = 127

Type OseDrumPadRectangle
    As Integer x
    As Integer y
    As Integer width
    As Integer height
End Type

Declare Function drumKit_Pitch(ByVal padIndex As Integer) As Integer
Declare Function drumKit_Name(ByVal padIndex As Integer) As String
Declare Function drumKit_KeyLabel(ByVal padIndex As Integer) As String
Declare Function drumKit_PadForKeyLabel(ByVal keyLabel As String) As Integer
Declare Function drumKit_VelocityName(ByVal velocity As Integer) As String
Declare Sub drumKit_PadRectangle( _
    ByVal padIndex As Integer, _
    ByVal surfaceX As Integer, _
    ByVal surfaceY As Integer, _
    ByVal surfaceWidth As Integer, _
    ByVal surfaceHeight As Integer, _
    ByRef padRectangle As OseDrumPadRectangle _
)
Declare Function drumKit_PadAtPoint( _
    ByVal pointX As Integer, _
    ByVal pointY As Integer, _
    ByVal surfaceX As Integer, _
    ByVal surfaceY As Integer, _
    ByVal surfaceWidth As Integer, _
    ByVal surfaceHeight As Integer _
) As Integer

#endif

/' end of drum_kit.bi '/
