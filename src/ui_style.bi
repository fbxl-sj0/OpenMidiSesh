/'
    Project: OpenSesh
    ---------------------------

    File: ui_style.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: uiStyle_* theme/control styles with OseUiControlStyle and OseUiThemePalette.

    Purpose:

        Declare the visual states shared by the editor's code-drawn controls.

    Responsibilities:

        - define complete Light, Dark, and Black application palettes
        - provide semantic colors shared by omaGUI and custom drawing
        - provide normal, hover, pressed, active, and disabled colors
        - provide foregrounds with explicit readable-contrast pairings
        - keep toolbar and score-tool styling consistent
        - expose the state rules to deterministic tests

    This file intentionally does NOT contain:

        - drawing commands
        - mouse hit testing
        - application callbacks
'/

#ifndef __OSE_UI_STYLE_BI__
#define __OSE_UI_STYLE_BI__

Const OSE_UI_STATE_NORMAL As Integer = 0
Const OSE_UI_STATE_HOVER As Integer = 1
Const OSE_UI_STATE_PRESSED As Integer = 2
Const OSE_UI_THEME_LIGHT As Integer = 0
Const OSE_UI_THEME_DARK As Integer = 1
Const OSE_UI_THEME_BLACK As Integer = 2
Const OSE_UI_THEME_COUNT As Integer = 3
Const OSE_UI_MIXER_BUTTON_MUTE As Integer = 0
Const OSE_UI_MIXER_BUTTON_SOLO As Integer = 1
Const OSE_UI_MIXER_BUTTON_RECORD As Integer = 2

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseUiControlStyle
    As ULong fillColor
    As ULong borderColor
    As ULong contentColor
    As Integer cornerRadius
End Type

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseUiThemePalette
    ' Public omaGUI theme bridge.
    As ULong faceColor
    As ULong shadowColor
    As ULong highlightColor
    As ULong textColor
    As ULong selectedTextColor
    As ULong selectedFillColor
    As ULong borderColor

    ' Application surfaces and semantic foregrounds.
    As ULong windowColor
    As ULong menuBarColor
    As ULong toolbarColor
    As ULong panelColor
    As ULong alternatePanelColor
    As ULong selectedPanelColor
    As ULong insetColor
    As ULong headerColor
    As ULong dividerColor
    As ULong mutedTextColor
    As ULong faintTextColor
    As ULong accentColor
    As ULong accentBrightColor
    As ULong dangerColor
    As ULong warningColor
    As ULong warningTextColor

    ' Score, audio lane, and palette surfaces.
    As ULong scorePaperColor
    As ULong scoreAlternateColor
    As ULong scoreSelectedColor
    As ULong scoreGuideColor
    As ULong scoreStrongGuideColor
    As ULong scorePlayheadColor
    As ULong scoreNoteFillColor
    As ULong scoreNoteBorderColor
    As ULong audioLabelColor
    As ULong audioGuideColor
    As ULong audioClipColor
    As ULong audioClipTextColor
    As ULong railColor
    As ULong paletteColor

    ' Mixer and knob hardware.
    As ULong faderRailColor
    As ULong faderRailShadowColor
    As ULong faderTickColor
    As ULong faderHandleColor
    As ULong faderHandleSelectedColor
    As ULong faderHandleOutlineColor
    As ULong faderHandleLineColor
    As ULong knobOuterColor
    As ULong knobFaceColor
    As ULong knobBorderColor
    As ULong knobInsetColor

    ' Performance keyboard and compact status displays.
    As ULong keyboardWhiteColor
    As ULong keyboardWhitePressedColor
    As ULong keyboardBlackColor
    As ULong keyboardBlackPressedColor
    As ULong keyboardWhiteTextColor
    As ULong keyboardBlackTextColor
    As ULong timelineFillColor
    As ULong timelineBorderColor
    As ULong timelineTextColor
    As ULong activityOffColor
    As ULong activityOnColor

    ' VU lamps retain conventional green, yellow, and red meaning in every mode.
    As ULong meterWellColor
    As ULong meterIdleGreenColor
    As ULong meterIdleYellowColor
    As ULong meterIdleRedColor
    As ULong meterActiveGreenColor
    As ULong meterActiveYellowColor
    As ULong meterActiveRedColor
End Type

Declare Function uiStyle_ThemeName(ByVal themeKind As Integer) As String

Declare Sub uiStyle_EditorTheme( _
    ByRef themePalette As OseUiThemePalette, _
    ByVal themeKind As Integer = OSE_UI_THEME_LIGHT _
)

Declare Sub uiStyle_Toolbar( _
    ByRef controlStyle As OseUiControlStyle, _
    ByRef themePalette As OseUiThemePalette, _
    ByVal pointerState As Integer, _
    ByVal transportButton As Integer, _
    ByVal active As Integer _
)

Declare Sub uiStyle_ScoreTool( _
    ByRef controlStyle As OseUiControlStyle, _
    ByRef themePalette As OseUiThemePalette, _
    ByVal active As Integer, _
    ByVal enabled As Integer _
)

Declare Sub uiStyle_MixerButton( _
    ByRef controlStyle As OseUiControlStyle, _
    ByRef themePalette As OseUiThemePalette, _
    ByVal buttonKind As Integer, _
    ByVal active As Integer _
)

#endif

/' end of ui_style.bi '/
