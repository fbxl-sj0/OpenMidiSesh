/'
    Project: OpenSesh
    ---------------------------

    File: tests/ui_interaction_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify the shared precise-pointer and touch interaction profiles.

    Responsibilities:

        - preserve the established desktop geometry
        - require finger-sized touch controls and non-overlapping toolbars
        - validate persistent interaction names and aliases
        - reject unknown names without changing caller state

    This file intentionally does NOT contain:

        - platform detection
        - graphical rendering
        - touch-contact polling
'/

#lang "fb"

#include once "../ui_interaction.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Sub test_RequireToolbarSeparation( _
    ByRef metrics As OseUiInteractionMetrics _
)
    For buttonIndex As Integer = 1 To OSE_UI_FILE_BUTTON_COUNT - 1
        Dim As Integer previousRight = _
            metrics.fileButtonLeft(buttonIndex - 1) + _
            metrics.fileButtonWidth(buttonIndex - 1)
        If metrics.fileButtonLeft(buttonIndex) < previousRight Then _
            test_Fail "file toolbar buttons overlap"
    Next

    For buttonIndex As Integer = 1 To OSE_UI_TRANSPORT_BUTTON_COUNT - 1
        Dim As Integer previousRight = _
            metrics.transportButtonLeft(buttonIndex - 1) + _
            metrics.transportButtonWidth(buttonIndex - 1)
        If metrics.transportButtonLeft(buttonIndex) < previousRight Then _
            test_Fail "transport buttons overlap"
    Next
End Sub


Dim As OseUiInteractionMetrics desktopMetrics
uiInteraction_Metrics desktopMetrics, OSE_UI_INTERACTION_FINE
If desktopMetrics.menuHeight <> 22 OrElse _
    desktopMetrics.toolbarButtonHeight <> 30 OrElse _
    desktopMetrics.scoreRailWidth <> 82 OrElse _
    desktopMetrics.dragThreshold <> 4 Then _
    test_Fail "desktop geometry changed"
test_RequireToolbarSeparation desktopMetrics

Dim As OseUiInteractionMetrics touchMetrics
uiInteraction_Metrics touchMetrics, OSE_UI_INTERACTION_TOUCH
If touchMetrics.menuHeight < 38 OrElse _
    touchMetrics.menuItemHeight < 44 OrElse _
    touchMetrics.toolbarButtonHeight < 44 OrElse _
    touchMetrics.scoreRailHeight < 44 OrElse _
    touchMetrics.scorePaletteFaceHeight < 36 OrElse _
    touchMetrics.scoreScrollbarSize < 28 OrElse _
    touchMetrics.dragThreshold <= desktopMetrics.dragThreshold Then _
    test_Fail "touch geometry is not finger-sized"
If touchMetrics.topHeight <= desktopMetrics.topHeight OrElse _
    touchMetrics.scoreTop <= desktopMetrics.scoreTop Then _
    test_Fail "touch layout did not reserve its larger top chrome"
test_RequireToolbarSeparation touchMetrics

For buttonIndex As Integer = 0 To OSE_UI_FILE_BUTTON_COUNT - 1
    If touchMetrics.fileButtonWidth(buttonIndex) <= _
        desktopMetrics.fileButtonWidth(buttonIndex) Then _
        test_Fail "touch file button is not wider than desktop"
Next
For buttonIndex As Integer = 0 To OSE_UI_TRANSPORT_BUTTON_COUNT - 1
    If touchMetrics.transportButtonWidth(buttonIndex) < 44 Then _
        test_Fail "touch transport button is too narrow"
Next

Dim As Integer parsedMode = 73
If uiInteraction_Parse("touch", parsedMode) = 0 OrElse _
    parsedMode <> OSE_UI_INTERACTION_TOUCH Then _
    test_Fail "Touch preference did not parse"
If uiInteraction_Parse("coarse", parsedMode) = 0 OrElse _
    parsedMode <> OSE_UI_INTERACTION_TOUCH Then _
    test_Fail "coarse-pointer alias did not parse"
If uiInteraction_Parse("desktop", parsedMode) = 0 OrElse _
    parsedMode <> OSE_UI_INTERACTION_FINE Then _
    test_Fail "desktop alias did not parse"
parsedMode = 73
If uiInteraction_Parse("trackball", parsedMode) <> 0 OrElse _
    parsedMode <> 73 Then _
    test_Fail "unknown interaction name changed caller state"

If uiInteraction_PreferenceText(OSE_UI_INTERACTION_FINE) <> "fine" OrElse _
    uiInteraction_PreferenceText(OSE_UI_INTERACTION_TOUCH) <> "touch" OrElse _
    uiInteraction_PreferenceText(73) <> "" Then _
    test_Fail "interaction preference text is not canonical"
If uiInteraction_Name(OSE_UI_INTERACTION_FINE) <> "Desktop" OrElse _
    uiInteraction_Name(OSE_UI_INTERACTION_TOUCH) <> "Touch" Then _
    test_Fail "interaction display names changed"

Print "ui_interaction=ok"
Print "profiles=2 touch_minimum_target=44 aliases=4"
End 0

/' end of tests/ui_interaction_smoke.bas '/
