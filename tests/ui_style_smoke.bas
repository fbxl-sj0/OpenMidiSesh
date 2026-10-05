/'
    Project: OpenSesh
    ---------------------------

    File: tests/ui_style_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify that code-drawn controls visibly communicate interaction state.

    Responsibilities:

        - pin the Light, Dark, and Black semantic palettes
        - enforce readable contrast for semantic text and control pairings
        - distinguish normal, hover, pressed, active, and disabled styles
        - verify toolbar and score controls share the intended corner treatment
        - reject accidental invisible-state regressions

    This file intentionally does NOT contain:

        - framebuffer snapshots
        - icon raster comparisons
        - input callbacks
'/

#lang "fb"

#include once "../ui_style.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Function test_LinearColorChannel( _
    ByVal channelValue As Integer _
) As Double
    Dim As Double normalizedValue = CDbl(channelValue) / 255.0
    If normalizedValue <= 0.04045 Then Return normalizedValue / 12.92
    Return ((normalizedValue + 0.055) / 1.055) ^ 2.4
End Function


Private Function test_RelativeLuminance(ByVal colorValue As ULong) As Double
    Dim As Integer redValue = CInt((colorValue Shr 16) And &HFFul)
    Dim As Integer greenValue = CInt((colorValue Shr 8) And &HFFul)
    Dim As Integer blueValue = CInt(colorValue And &HFFul)
    Return 0.2126 * test_LinearColorChannel(redValue) + _
        0.7152 * test_LinearColorChannel(greenValue) + _
        0.0722 * test_LinearColorChannel(blueValue)
End Function


Private Function test_ContrastRatio( _
    ByVal firstColor As ULong, _
    ByVal secondColor As ULong _
) As Double
    Dim As Double lighter = test_RelativeLuminance(firstColor)
    Dim As Double darker = test_RelativeLuminance(secondColor)
    If darker > lighter Then
        Swap lighter, darker
    End If
    Return (lighter + 0.05) / (darker + 0.05)
End Function


Private Sub test_RequireContrast( _
    ByVal pairingName As String, _
    ByVal foregroundColor As ULong, _
    ByVal backgroundColor As ULong, _
    ByVal minimumRatio As Double, _
    ByRef contrastCheckCount As Integer _
)
    Dim As Double actualRatio = test_ContrastRatio( _
        foregroundColor, backgroundColor)
    If actualRatio < minimumRatio Then
        test_Fail pairingName + " contrast " + Str(actualRatio) + _
            " is below " + Str(minimumRatio)
    End If
    contrastCheckCount += 1
End Sub


Private Sub test_VerifyPaletteContrast( _
    ByRef themePalette As OseUiThemePalette, _
    ByVal themeName As String, _
    ByRef contrastCheckCount As Integer _
)
    Const NORMAL_TEXT_RATIO As Double = 4.5
    Const DISABLED_TEXT_RATIO As Double = 3.0

    test_RequireContrast themeName + " window text", themePalette.textColor, _
        themePalette.windowColor, NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " menu text", themePalette.textColor, _
        themePalette.menuBarColor, NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " toolbar text", themePalette.textColor, _
        themePalette.toolbarColor, NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " face text", themePalette.textColor, _
        themePalette.faceColor, NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " panel text", themePalette.textColor, _
        themePalette.panelColor, NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " alternate panel text", _
        themePalette.textColor, themePalette.alternatePanelColor, _
        NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " selected panel text", _
        themePalette.textColor, themePalette.selectedPanelColor, _
        NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " inset text", themePalette.textColor, _
        themePalette.insetColor, NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " header text", themePalette.textColor, _
        themePalette.headerColor, NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " score text", themePalette.textColor, _
        themePalette.scorePaperColor, NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " alternate score text", _
        themePalette.textColor, themePalette.scoreAlternateColor, _
        NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " selected score text", _
        themePalette.textColor, themePalette.scoreSelectedColor, _
        NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " selected text", _
        themePalette.selectedTextColor, themePalette.selectedFillColor, _
        NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " muted inset text", _
        themePalette.mutedTextColor, themePalette.insetColor, _
        NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " disabled text", _
        themePalette.faintTextColor, themePalette.alternatePanelColor, _
        DISABLED_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " audio heading", _
        themePalette.audioLabelColor, themePalette.scorePaperColor, _
        NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " audio clip text", _
        themePalette.audioClipTextColor, themePalette.audioClipColor, _
        NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " white key text", _
        themePalette.keyboardWhiteTextColor, themePalette.keyboardWhiteColor, _
        NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " pressed white key text", _
        themePalette.keyboardWhiteTextColor, _
        themePalette.keyboardWhitePressedColor, NORMAL_TEXT_RATIO, _
        contrastCheckCount
    test_RequireContrast themeName + " black key text", _
        themePalette.keyboardBlackTextColor, themePalette.keyboardBlackColor, _
        NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " pressed black key text", _
        themePalette.keyboardBlackTextColor, _
        themePalette.keyboardBlackPressedColor, NORMAL_TEXT_RATIO, _
        contrastCheckCount
    test_RequireContrast themeName + " timeline text", _
        themePalette.timelineTextColor, themePalette.timelineFillColor, _
        NORMAL_TEXT_RATIO, contrastCheckCount
    test_RequireContrast themeName + " warning text", _
        themePalette.warningTextColor, themePalette.warningColor, _
        NORMAL_TEXT_RATIO, contrastCheckCount

    Dim As OseUiControlStyle controlStyle
    uiStyle_Toolbar controlStyle, themePalette, OSE_UI_STATE_NORMAL, -1, 0
    test_RequireContrast themeName + " normal transport", _
        controlStyle.contentColor, controlStyle.fillColor, NORMAL_TEXT_RATIO, _
        contrastCheckCount
    uiStyle_Toolbar controlStyle, themePalette, OSE_UI_STATE_HOVER, -1, 0
    test_RequireContrast themeName + " hover transport", _
        controlStyle.contentColor, controlStyle.fillColor, NORMAL_TEXT_RATIO, _
        contrastCheckCount
    uiStyle_Toolbar controlStyle, themePalette, OSE_UI_STATE_PRESSED, -1, 0
    test_RequireContrast themeName + " pressed transport", _
        controlStyle.contentColor, controlStyle.fillColor, NORMAL_TEXT_RATIO, _
        contrastCheckCount
    uiStyle_Toolbar controlStyle, themePalette, OSE_UI_STATE_NORMAL, -1, -1
    test_RequireContrast themeName + " active transport", _
        controlStyle.contentColor, controlStyle.fillColor, NORMAL_TEXT_RATIO, _
        contrastCheckCount

    uiStyle_ScoreTool controlStyle, themePalette, 0, -1
    test_RequireContrast themeName + " normal score tool", _
        controlStyle.contentColor, controlStyle.fillColor, NORMAL_TEXT_RATIO, _
        contrastCheckCount
    uiStyle_ScoreTool controlStyle, themePalette, -1, -1
    test_RequireContrast themeName + " active score tool", _
        controlStyle.contentColor, controlStyle.fillColor, NORMAL_TEXT_RATIO, _
        contrastCheckCount
    uiStyle_ScoreTool controlStyle, themePalette, 0, 0
    test_RequireContrast themeName + " disabled score tool", _
        controlStyle.contentColor, controlStyle.fillColor, DISABLED_TEXT_RATIO, _
        contrastCheckCount

    uiStyle_MixerButton controlStyle, themePalette, _
        OSE_UI_MIXER_BUTTON_MUTE, 0
    test_RequireContrast themeName + " inactive mixer button", _
        controlStyle.contentColor, controlStyle.fillColor, NORMAL_TEXT_RATIO, _
        contrastCheckCount
    uiStyle_MixerButton controlStyle, themePalette, _
        OSE_UI_MIXER_BUTTON_MUTE, -1
    test_RequireContrast themeName + " active mute button", _
        controlStyle.contentColor, controlStyle.fillColor, NORMAL_TEXT_RATIO, _
        contrastCheckCount
    uiStyle_MixerButton controlStyle, themePalette, _
        OSE_UI_MIXER_BUTTON_SOLO, -1
    test_RequireContrast themeName + " active solo button", _
        controlStyle.contentColor, controlStyle.fillColor, NORMAL_TEXT_RATIO, _
        contrastCheckCount
    uiStyle_MixerButton controlStyle, themePalette, _
        OSE_UI_MIXER_BUTTON_RECORD, -1
    test_RequireContrast themeName + " active record button", _
        controlStyle.contentColor, controlStyle.fillColor, NORMAL_TEXT_RATIO, _
        contrastCheckCount
End Sub


Private Sub test_VerifyControlStates( _
    ByRef themePalette As OseUiThemePalette, _
    ByVal themeName As String _
)
    Dim As OseUiControlStyle normalStyle
    Dim As OseUiControlStyle hoverStyle
    Dim As OseUiControlStyle pressedStyle
    Dim As OseUiControlStyle activeStyle
    Dim As OseUiControlStyle disabledStyle

    uiStyle_Toolbar normalStyle, themePalette, OSE_UI_STATE_NORMAL, -1, 0
    uiStyle_Toolbar hoverStyle, themePalette, OSE_UI_STATE_HOVER, -1, 0
    uiStyle_Toolbar pressedStyle, themePalette, OSE_UI_STATE_PRESSED, -1, 0
    uiStyle_Toolbar activeStyle, themePalette, OSE_UI_STATE_NORMAL, -1, -1
    If normalStyle.fillColor = hoverStyle.fillColor OrElse _
        normalStyle.borderColor = hoverStyle.borderColor Then _
        test_Fail themeName + " transport hover state is not visible"
    If hoverStyle.fillColor = pressedStyle.fillColor Then _
        test_Fail themeName + " transport pressed state is not visible"
    If activeStyle.fillColor = normalStyle.fillColor Then _
        test_Fail themeName + " active transport state is not visible"
    If normalStyle.cornerRadius <> 5 OrElse activeStyle.cornerRadius <> 5 Then _
        test_Fail themeName + " toolbar corner treatment changed"

    uiStyle_ScoreTool normalStyle, themePalette, 0, -1
    uiStyle_ScoreTool activeStyle, themePalette, -1, -1
    uiStyle_ScoreTool disabledStyle, themePalette, 0, 0
    If normalStyle.fillColor = activeStyle.fillColor OrElse _
        normalStyle.contentColor = activeStyle.contentColor Then _
        test_Fail themeName + " active score tool is not visible"
    If disabledStyle.contentColor = normalStyle.contentColor Then _
        test_Fail themeName + " disabled score tool is not visually disabled"
    If disabledStyle.fillColor = activeStyle.fillColor Then _
        test_Fail themeName + " disabled score tool looks active"

    Dim As OseUiControlStyle muteStyle
    Dim As OseUiControlStyle soloStyle
    Dim As OseUiControlStyle recordStyle
    uiStyle_MixerButton normalStyle, themePalette, _
        OSE_UI_MIXER_BUTTON_MUTE, 0
    uiStyle_MixerButton muteStyle, themePalette, _
        OSE_UI_MIXER_BUTTON_MUTE, -1
    uiStyle_MixerButton soloStyle, themePalette, _
        OSE_UI_MIXER_BUTTON_SOLO, -1
    uiStyle_MixerButton recordStyle, themePalette, _
        OSE_UI_MIXER_BUTTON_RECORD, -1
    If normalStyle.fillColor = muteStyle.fillColor OrElse _
        muteStyle.fillColor = soloStyle.fillColor OrElse _
        soloStyle.fillColor = recordStyle.fillColor OrElse _
        muteStyle.fillColor = recordStyle.fillColor Then _
        test_Fail themeName + " mixer roles are not visually distinct"
    If normalStyle.cornerRadius <> 3 OrElse recordStyle.cornerRadius <> 3 Then _
        test_Fail themeName + " mixer button corner treatment changed"
End Sub


Dim As OseUiThemePalette lightTheme
Dim As OseUiThemePalette darkTheme
Dim As OseUiThemePalette blackTheme
Dim As OseUiThemePalette fallbackTheme
uiStyle_EditorTheme lightTheme, OSE_UI_THEME_LIGHT
uiStyle_EditorTheme darkTheme, OSE_UI_THEME_DARK
uiStyle_EditorTheme blackTheme, OSE_UI_THEME_BLACK
uiStyle_EditorTheme fallbackTheme, 999

If uiStyle_ThemeName(OSE_UI_THEME_LIGHT) <> "Light" OrElse _
    uiStyle_ThemeName(OSE_UI_THEME_DARK) <> "Dark" OrElse _
    uiStyle_ThemeName(OSE_UI_THEME_BLACK) <> "Black" OrElse _
    uiStyle_ThemeName(999) <> "Light" Then _
    test_Fail "theme names or invalid-theme fallback changed"
If lightTheme.windowColor <> RGB(242, 245, 244) OrElse _
    darkTheme.windowColor <> RGB(20, 25, 27) OrElse _
    blackTheme.windowColor <> RGB(0, 0, 0) Then _
    test_Fail "theme window colors changed"
If fallbackTheme.windowColor <> lightTheme.windowColor OrElse _
    fallbackTheme.textColor <> lightTheme.textColor Then _
    test_Fail "invalid theme does not fall back to Light"
If lightTheme.windowColor = darkTheme.windowColor OrElse _
    darkTheme.windowColor = blackTheme.windowColor OrElse _
    lightTheme.windowColor = blackTheme.windowColor Then _
    test_Fail "Light, Dark, and Black are not distinct"
If lightTheme.textColor = lightTheme.windowColor OrElse _
    darkTheme.textColor = darkTheme.windowColor OrElse _
    blackTheme.textColor = blackTheme.windowColor Then _
    test_Fail "a theme loses foreground/background contrast"
If lightTheme.meterActiveGreenColor <> darkTheme.meterActiveGreenColor OrElse _
    darkTheme.meterActiveGreenColor <> blackTheme.meterActiveGreenColor Then _
    test_Fail "VU semantics differ between themes"

test_VerifyControlStates lightTheme, "Light"
test_VerifyControlStates darkTheme, "Dark"
test_VerifyControlStates blackTheme, "Black"

Dim As Integer contrastCheckCount
test_VerifyPaletteContrast lightTheme, "Light", contrastCheckCount
test_VerifyPaletteContrast darkTheme, "Dark", contrastCheckCount
test_VerifyPaletteContrast blackTheme, "Black", contrastCheckCount

Print "ui_style=ok"
Print "theme_modes=3 theme_colors=68 toolbar_states=12 score_states=9 mixer_roles=9"
Print "contrast_checks="; contrastCheckCount; " normal_text_ratio=4.5 disabled_text_ratio=3.0"
End 0

/' end of tests/ui_style_smoke.bas '/
