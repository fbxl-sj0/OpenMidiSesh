/'
    Project: OpenSesh
    ---------------------------

    File: ui_icons.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: uiIcons_* bitmap decoding/placement and OSE_UI_ICON_* identifiers.

    Purpose:

        Declare the fixed-size grayscale coverage masks used by compact editor
        controls on every supported graphics backend.

    Responsibilities:

        - assign stable identities to score-tool and transport icons
        - expose one checked 24 x 24 coverage row at a time
        - decode hexadecimal coverage samples into alpha values
        - center an icon safely inside controls of any supported size

    This file intentionally does NOT contain:

        - framebuffer drawing
        - theme colors
        - control hit testing or application commands
'/

#ifndef __OSE_UI_ICONS_BI__
#define __OSE_UI_ICONS_BI__

Const OSE_UI_ICON_SIZE As Integer = 24

Const OSE_UI_ICON_POINTER As Integer = 0
Const OSE_UI_ICON_NOTE As Integer = 1
Const OSE_UI_ICON_TRASH As Integer = 2
Const OSE_UI_ICON_CUT As Integer = 3
Const OSE_UI_ICON_PASTE As Integer = 4
Const OSE_UI_ICON_STOP As Integer = 5
Const OSE_UI_ICON_PAUSE As Integer = 6
Const OSE_UI_ICON_REWIND As Integer = 7
Const OSE_UI_ICON_PLAY As Integer = 8
Const OSE_UI_ICON_FORWARD As Integer = 9
Const OSE_UI_ICON_RECORD As Integer = 10
Const OSE_UI_ICON_STEP As Integer = 11
Const OSE_UI_ICON_COUNT As Integer = 12

Declare Function uiIcons_IsValid(ByVal iconId As Integer) As Integer
Declare Function uiIcons_Name(ByVal iconId As Integer) As String
Declare Function uiIcons_GetRow( _
    ByVal iconId As Integer, _
    ByVal rowIndex As Integer, _
    ByRef rowText As String _
) As Integer
Declare Function uiIcons_DecodeCoverage( _
    ByVal maskCharacter As UByte _
) As Integer
Declare Function uiIcons_Coverage( _
    ByVal iconId As Integer, _
    ByVal pixelX As Integer, _
    ByVal pixelY As Integer _
) As Integer
Declare Function uiIcons_CenteredOffset( _
    ByVal containerExtent As Integer _
) As Integer

#endif

' end of ui_icons.bi
