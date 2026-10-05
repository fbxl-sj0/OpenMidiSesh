/'
    Project: OpenSesh
    ---------------------------

    File: ui_style.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements ui_style.bi; declarations there define the shared interface.

    Purpose:

        Define coherent Light, Dark, and Black palettes for the complete editor
        and its code-drawn controls.

    Responsibilities:

        - provide complete semantic palettes for omaGUI and custom drawing
        - keep Light bright, Dark charcoal, and Black true-black at its base
        - make every pointer state visually distinct
        - give active transport and score tools a consistent teal accent
        - preserve measured readable contrast for text and control glyphs
        - bound unknown pointer states to the normal appearance

    This file intentionally does NOT contain:

        - omaGUI or gfxlib calls
        - widget allocation
        - icon geometry
'/

#lang "fb"

#include once "ui_style.bi"

' -------------------------------------------------------------------------
' Application themes
' -------------------------------------------------------------------------

Public Function uiStyle_ThemeName(ByVal themeKind As Integer) As String
    Select Case themeKind
        Case OSE_UI_THEME_DARK
            Return "Dark"
        Case OSE_UI_THEME_BLACK
            Return "Black"
    End Select
    Return "Light"
End Function


Private Sub uiStyle_CommonMeters(ByRef themePalette As OseUiThemePalette)
    themePalette.meterWellColor = RGB(15, 18, 15)
    themePalette.meterIdleGreenColor = RGB(35, 72, 35)
    themePalette.meterIdleYellowColor = RGB(92, 82, 26)
    themePalette.meterIdleRedColor = RGB(90, 34, 30)
    themePalette.meterActiveGreenColor = RGB(20, 210, 42)
    themePalette.meterActiveYellowColor = RGB(225, 219, 23)
    themePalette.meterActiveRedColor = RGB(221, 28, 25)
End Sub


Private Sub uiStyle_LightTheme(ByRef themePalette As OseUiThemePalette)
    themePalette.faceColor = RGB(231, 235, 234)
    themePalette.shadowColor = RGB(174, 182, 182)
    themePalette.highlightColor = RGB(252, 253, 252)
    themePalette.textColor = RGB(27, 35, 38)
    themePalette.selectedTextColor = RGB(255, 255, 255)
    themePalette.selectedFillColor = RGB(0, 125, 116)
    themePalette.borderColor = RGB(89, 103, 106)
    themePalette.windowColor = RGB(242, 245, 244)
    themePalette.menuBarColor = RGB(249, 250, 249)
    themePalette.toolbarColor = RGB(226, 231, 230)
    themePalette.panelColor = RGB(235, 239, 238)
    themePalette.alternatePanelColor = RGB(226, 231, 230)
    themePalette.selectedPanelColor = RGB(214, 235, 233)
    themePalette.insetColor = RGB(216, 222, 222)
    themePalette.headerColor = RGB(222, 228, 227)
    themePalette.dividerColor = RGB(112, 126, 129)
    themePalette.mutedTextColor = RGB(82, 96, 99)
    themePalette.faintTextColor = RGB(116, 129, 131)
    themePalette.accentColor = RGB(0, 125, 116)
    themePalette.accentBrightColor = RGB(16, 165, 156)
    themePalette.dangerColor = RGB(190, 42, 55)
    themePalette.warningColor = RGB(177, 124, 20)
    themePalette.warningTextColor = RGB(0, 0, 0)
    themePalette.scorePaperColor = RGB(255, 255, 252)
    themePalette.scoreAlternateColor = RGB(247, 249, 246)
    themePalette.scoreSelectedColor = RGB(229, 241, 244)
    themePalette.scoreGuideColor = RGB(231, 233, 228)
    themePalette.scoreStrongGuideColor = RGB(187, 191, 187)
    themePalette.scorePlayheadColor = RGB(194, 48, 48)
    themePalette.scoreNoteFillColor = RGB(42, 116, 164)
    themePalette.scoreNoteBorderColor = RGB(28, 82, 120)
    themePalette.audioLabelColor = RGB(40, 91, 52)
    themePalette.audioGuideColor = RGB(104, 139, 110)
    themePalette.audioClipColor = RGB(104, 168, 112)
    themePalette.audioClipTextColor = RGB(9, 29, 12)
    themePalette.railColor = RGB(214, 220, 219)
    themePalette.paletteColor = RGB(224, 229, 228)
    themePalette.faderRailColor = RGB(121, 135, 138)
    themePalette.faderRailShadowColor = RGB(177, 184, 185)
    themePalette.faderTickColor = RGB(104, 117, 120)
    themePalette.faderHandleColor = RGB(152, 165, 167)
    themePalette.faderHandleSelectedColor = RGB(14, 151, 142)
    themePalette.faderHandleOutlineColor = RGB(72, 84, 87)
    themePalette.faderHandleLineColor = RGB(255, 255, 255)
    themePalette.knobOuterColor = RGB(169, 177, 178)
    themePalette.knobFaceColor = RGB(225, 230, 229)
    themePalette.knobBorderColor = RGB(93, 107, 110)
    themePalette.knobInsetColor = RGB(199, 207, 207)
    themePalette.keyboardWhiteColor = RGB(249, 249, 244)
    themePalette.keyboardWhitePressedColor = RGB(132, 190, 218)
    themePalette.keyboardBlackColor = RGB(40, 46, 49)
    themePalette.keyboardBlackPressedColor = RGB(38, 104, 142)
    themePalette.keyboardWhiteTextColor = RGB(38, 44, 48)
    themePalette.keyboardBlackTextColor = RGB(240, 240, 236)
    themePalette.timelineFillColor = RGB(12, 27, 16)
    themePalette.timelineBorderColor = RGB(83, 92, 86)
    themePalette.timelineTextColor = RGB(32, 245, 63)
    themePalette.activityOffColor = RGB(83, 96, 90)
    themePalette.activityOnColor = RGB(24, 176, 45)
End Sub


Private Sub uiStyle_DarkTheme(ByRef themePalette As OseUiThemePalette)
    themePalette.faceColor = RGB(43, 51, 54)
    themePalette.shadowColor = RGB(24, 30, 32)
    themePalette.highlightColor = RGB(72, 83, 86)
    themePalette.textColor = RGB(228, 234, 234)
    themePalette.selectedTextColor = RGB(255, 255, 255)
    themePalette.selectedFillColor = RGB(0, 125, 116)
    themePalette.borderColor = RGB(102, 117, 120)
    themePalette.windowColor = RGB(20, 25, 27)
    themePalette.menuBarColor = RGB(31, 38, 40)
    themePalette.toolbarColor = RGB(34, 42, 44)
    themePalette.panelColor = RGB(40, 48, 51)
    themePalette.alternatePanelColor = RGB(34, 41, 44)
    themePalette.selectedPanelColor = RGB(35, 67, 68)
    themePalette.insetColor = RGB(23, 29, 31)
    themePalette.headerColor = RGB(29, 36, 38)
    themePalette.dividerColor = RGB(92, 106, 109)
    themePalette.mutedTextColor = RGB(176, 188, 190)
    themePalette.faintTextColor = RGB(119, 133, 136)
    themePalette.accentColor = RGB(0, 125, 116)
    themePalette.accentBrightColor = RGB(43, 211, 198)
    themePalette.dangerColor = RGB(190, 42, 55)
    themePalette.warningColor = RGB(220, 163, 36)
    themePalette.warningTextColor = RGB(0, 0, 0)
    themePalette.scorePaperColor = RGB(27, 33, 35)
    themePalette.scoreAlternateColor = RGB(31, 38, 40)
    themePalette.scoreSelectedColor = RGB(34, 60, 62)
    themePalette.scoreGuideColor = RGB(47, 56, 58)
    themePalette.scoreStrongGuideColor = RGB(75, 88, 91)
    themePalette.scorePlayheadColor = RGB(242, 78, 89)
    themePalette.scoreNoteFillColor = RGB(47, 144, 184)
    themePalette.scoreNoteBorderColor = RGB(103, 192, 223)
    themePalette.audioLabelColor = RGB(132, 207, 144)
    themePalette.audioGuideColor = RGB(78, 119, 84)
    themePalette.audioClipColor = RGB(48, 118, 61)
    themePalette.audioClipTextColor = RGB(244, 250, 245)
    themePalette.railColor = RGB(37, 45, 48)
    themePalette.paletteColor = RGB(32, 40, 42)
    themePalette.faderRailColor = RGB(91, 106, 109)
    themePalette.faderRailShadowColor = RGB(13, 18, 20)
    themePalette.faderTickColor = RGB(126, 139, 141)
    themePalette.faderHandleColor = RGB(145, 157, 159)
    themePalette.faderHandleSelectedColor = RGB(34, 199, 186)
    themePalette.faderHandleOutlineColor = RGB(14, 19, 21)
    themePalette.faderHandleLineColor = RGB(238, 242, 241)
    themePalette.knobOuterColor = RGB(12, 16, 18)
    themePalette.knobFaceColor = RGB(38, 47, 51)
    themePalette.knobBorderColor = RGB(116, 132, 136)
    themePalette.knobInsetColor = RGB(29, 36, 39)
    themePalette.keyboardWhiteColor = RGB(225, 229, 224)
    themePalette.keyboardWhitePressedColor = RGB(80, 158, 190)
    themePalette.keyboardBlackColor = RGB(25, 30, 33)
    themePalette.keyboardBlackPressedColor = RGB(33, 111, 145)
    themePalette.keyboardWhiteTextColor = RGB(35, 42, 45)
    themePalette.keyboardBlackTextColor = RGB(235, 239, 236)
    themePalette.timelineFillColor = RGB(5, 14, 7)
    themePalette.timelineBorderColor = RGB(81, 94, 86)
    themePalette.timelineTextColor = RGB(32, 245, 63)
    themePalette.activityOffColor = RGB(55, 90, 55)
    themePalette.activityOnColor = RGB(26, 220, 42)
End Sub


Private Sub uiStyle_BlackTheme(ByRef themePalette As OseUiThemePalette)
    themePalette.faceColor = RGB(13, 13, 13)
    themePalette.shadowColor = RGB(0, 0, 0)
    themePalette.highlightColor = RGB(48, 48, 48)
    themePalette.textColor = RGB(241, 241, 241)
    themePalette.selectedTextColor = RGB(255, 255, 255)
    themePalette.selectedFillColor = RGB(0, 118, 110)
    themePalette.borderColor = RGB(82, 82, 82)
    themePalette.windowColor = RGB(0, 0, 0)
    themePalette.menuBarColor = RGB(5, 5, 5)
    themePalette.toolbarColor = RGB(8, 8, 8)
    themePalette.panelColor = RGB(12, 12, 12)
    themePalette.alternatePanelColor = RGB(6, 6, 6)
    themePalette.selectedPanelColor = RGB(0, 43, 40)
    themePalette.insetColor = RGB(0, 0, 0)
    themePalette.headerColor = RGB(5, 5, 5)
    themePalette.dividerColor = RGB(54, 54, 54)
    themePalette.mutedTextColor = RGB(188, 188, 188)
    themePalette.faintTextColor = RGB(112, 112, 112)
    themePalette.accentColor = RGB(0, 125, 116)
    themePalette.accentBrightColor = RGB(34, 232, 214)
    themePalette.dangerColor = RGB(190, 42, 55)
    themePalette.warningColor = RGB(238, 175, 30)
    themePalette.warningTextColor = RGB(0, 0, 0)
    themePalette.scorePaperColor = RGB(2, 2, 2)
    themePalette.scoreAlternateColor = RGB(8, 8, 8)
    themePalette.scoreSelectedColor = RGB(0, 35, 33)
    themePalette.scoreGuideColor = RGB(26, 26, 26)
    themePalette.scoreStrongGuideColor = RGB(58, 58, 58)
    themePalette.scorePlayheadColor = RGB(255, 67, 80)
    themePalette.scoreNoteFillColor = RGB(30, 150, 198)
    themePalette.scoreNoteBorderColor = RGB(111, 211, 244)
    themePalette.audioLabelColor = RGB(141, 226, 153)
    themePalette.audioGuideColor = RGB(52, 102, 59)
    themePalette.audioClipColor = RGB(43, 125, 56)
    themePalette.audioClipTextColor = RGB(255, 255, 255)
    themePalette.railColor = RGB(10, 10, 10)
    themePalette.paletteColor = RGB(5, 5, 5)
    themePalette.faderRailColor = RGB(73, 73, 73)
    themePalette.faderRailShadowColor = RGB(0, 0, 0)
    themePalette.faderTickColor = RGB(126, 126, 126)
    themePalette.faderHandleColor = RGB(151, 151, 151)
    themePalette.faderHandleSelectedColor = RGB(21, 220, 204)
    themePalette.faderHandleOutlineColor = RGB(0, 0, 0)
    themePalette.faderHandleLineColor = RGB(255, 255, 255)
    themePalette.knobOuterColor = RGB(0, 0, 0)
    themePalette.knobFaceColor = RGB(18, 18, 18)
    themePalette.knobBorderColor = RGB(111, 111, 111)
    themePalette.knobInsetColor = RGB(5, 5, 5)
    themePalette.keyboardWhiteColor = RGB(210, 210, 207)
    themePalette.keyboardWhitePressedColor = RGB(50, 150, 194)
    themePalette.keyboardBlackColor = RGB(0, 0, 0)
    themePalette.keyboardBlackPressedColor = RGB(0, 91, 128)
    themePalette.keyboardWhiteTextColor = RGB(22, 22, 22)
    themePalette.keyboardBlackTextColor = RGB(255, 255, 255)
    themePalette.timelineFillColor = RGB(0, 0, 0)
    themePalette.timelineBorderColor = RGB(65, 65, 65)
    themePalette.timelineTextColor = RGB(37, 255, 69)
    themePalette.activityOffColor = RGB(32, 66, 32)
    themePalette.activityOnColor = RGB(30, 236, 48)
End Sub


Public Sub uiStyle_EditorTheme( _
    ByRef themePalette As OseUiThemePalette, _
    ByVal themeKind As Integer _
)
    Dim As OseUiThemePalette emptyPalette
    themePalette = emptyPalette
    Select Case themeKind
        Case OSE_UI_THEME_DARK
            uiStyle_DarkTheme themePalette
        Case OSE_UI_THEME_BLACK
            uiStyle_BlackTheme themePalette
        Case Else
            uiStyle_LightTheme themePalette
    End Select
    uiStyle_CommonMeters themePalette
End Sub

' -------------------------------------------------------------------------
' Toolbar states
' -------------------------------------------------------------------------

Public Sub uiStyle_Toolbar( _
    ByRef controlStyle As OseUiControlStyle, _
    ByRef themePalette As OseUiThemePalette, _
    ByVal pointerState As Integer, _
    ByVal transportButton As Integer, _
    ByVal active As Integer _
)
    If pointerState < OSE_UI_STATE_NORMAL OrElse _
        pointerState > OSE_UI_STATE_PRESSED Then
        pointerState = OSE_UI_STATE_NORMAL
    End If

    controlStyle.cornerRadius = 5
    If transportButton <> 0 Then
        controlStyle.fillColor = themePalette.insetColor
        controlStyle.borderColor = themePalette.borderColor
        controlStyle.contentColor = themePalette.textColor
        If pointerState = OSE_UI_STATE_HOVER Then
            controlStyle.fillColor = themePalette.selectedPanelColor
            controlStyle.borderColor = themePalette.accentBrightColor
        ElseIf pointerState = OSE_UI_STATE_PRESSED Then
            controlStyle.fillColor = themePalette.shadowColor
            controlStyle.borderColor = themePalette.accentColor
        End If
        If active <> 0 Then
            controlStyle.fillColor = themePalette.accentColor
            controlStyle.borderColor = themePalette.accentBrightColor
            controlStyle.contentColor = themePalette.selectedTextColor
        End If
        Exit Sub
    End If

    controlStyle.fillColor = themePalette.faceColor
    controlStyle.borderColor = themePalette.borderColor
    controlStyle.contentColor = themePalette.textColor
    If pointerState = OSE_UI_STATE_HOVER Then
        controlStyle.fillColor = themePalette.selectedPanelColor
        controlStyle.borderColor = themePalette.accentBrightColor
    ElseIf pointerState = OSE_UI_STATE_PRESSED Then
        controlStyle.fillColor = themePalette.shadowColor
        controlStyle.borderColor = themePalette.accentColor
    End If
End Sub

' -------------------------------------------------------------------------
' Score-tool states
' -------------------------------------------------------------------------

Public Sub uiStyle_ScoreTool( _
    ByRef controlStyle As OseUiControlStyle, _
    ByRef themePalette As OseUiThemePalette, _
    ByVal active As Integer, _
    ByVal enabled As Integer _
)
    controlStyle.cornerRadius = 5
    controlStyle.fillColor = themePalette.faceColor
    controlStyle.borderColor = themePalette.borderColor
    controlStyle.contentColor = themePalette.textColor
    If active <> 0 Then
        controlStyle.fillColor = themePalette.accentColor
        controlStyle.borderColor = themePalette.accentBrightColor
        controlStyle.contentColor = themePalette.selectedTextColor
    End If
    If enabled = 0 Then
        controlStyle.fillColor = themePalette.alternatePanelColor
        controlStyle.borderColor = themePalette.shadowColor
        controlStyle.contentColor = themePalette.faintTextColor
    End If
End Sub

' -------------------------------------------------------------------------
' Mixer-button states
' -------------------------------------------------------------------------

Public Sub uiStyle_MixerButton( _
    ByRef controlStyle As OseUiControlStyle, _
    ByRef themePalette As OseUiThemePalette, _
    ByVal buttonKind As Integer, _
    ByVal active As Integer _
)
    If buttonKind < OSE_UI_MIXER_BUTTON_MUTE OrElse _
        buttonKind > OSE_UI_MIXER_BUTTON_RECORD Then
        buttonKind = OSE_UI_MIXER_BUTTON_MUTE
    End If

    controlStyle.cornerRadius = 3
    controlStyle.fillColor = themePalette.insetColor
    controlStyle.borderColor = themePalette.borderColor
    controlStyle.contentColor = themePalette.mutedTextColor
    If active = 0 Then
        Exit Sub
    End If

    controlStyle.contentColor = themePalette.selectedTextColor
    Select Case buttonKind
        Case OSE_UI_MIXER_BUTTON_MUTE
            controlStyle.fillColor = themePalette.warningColor
            controlStyle.borderColor = themePalette.highlightColor
            controlStyle.contentColor = themePalette.warningTextColor
        Case OSE_UI_MIXER_BUTTON_SOLO
            controlStyle.fillColor = themePalette.accentColor
            controlStyle.borderColor = themePalette.accentBrightColor
        Case OSE_UI_MIXER_BUTTON_RECORD
            controlStyle.fillColor = themePalette.dangerColor
            controlStyle.borderColor = themePalette.highlightColor
    End Select
End Sub

/' end of ui_style.bas '/
