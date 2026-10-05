/'
    Project: OpenSesh
    ---------------------------

    File: keyboard_controls.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: keyboardControls_* pitch/hit mapping and keyboard geometry constants.

    Purpose:

        Declare the geometry, pitch, and PC-key labels for the two-octave
        performance keyboard.

    Responsibilities:

        - map fourteen white and ten black key faces to MIDI pitches
        - give black keys priority in their overlapping upper area
        - reject points outside the visible piano
        - provide the twenty-four printed PC-key labels

    This file intentionally does NOT contain:

        - pointer polling
        - sound or recording commands
        - graphical rendering
'/

#ifndef __OSE_KEYBOARD_CONTROLS_BI__
#define __OSE_KEYBOARD_CONTROLS_BI__

Const OSE_KEYBOARD_NOTE_COUNT As Integer = 24
Const OSE_KEYBOARD_WHITE_KEY_COUNT As Integer = 14
Const OSE_KEYBOARD_BLACK_KEY_COUNT As Integer = 10
Const OSE_KEYBOARD_WHITE_KEY_WIDTH As Integer = 54
Const OSE_KEYBOARD_WHITE_KEY_HEIGHT As Integer = 154
Const OSE_KEYBOARD_BLACK_KEY_WIDTH As Integer = 32
Const OSE_KEYBOARD_BLACK_KEY_HEIGHT As Integer = 94
Const OSE_KEYBOARD_LEFT As Integer = 26
Const OSE_KEYBOARD_TOP As Integer = 138

Declare Function keyboardControls_WhitePitch( _
    ByVal basePitch As Integer, _
    ByVal whiteIndex As Integer _
) As Integer
Declare Function keyboardControls_BlackPitch( _
    ByVal basePitch As Integer, _
    ByVal blackIndex As Integer _
) As Integer
Declare Function keyboardControls_BlackLeft( _
    ByVal blackIndex As Integer _
) As Integer
Declare Function keyboardControls_PitchAtPoint( _
    ByVal basePitch As Integer, _
    ByVal localX As Integer, _
    ByVal localY As Integer _
) As Integer
Declare Function keyboardControls_KeyLabel( _
    ByVal noteOffset As Integer _
) As String

#endif

/' end of keyboard_controls.bi '/
