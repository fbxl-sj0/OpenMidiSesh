/'
    Project: OpenSesh
    ---------------------------

    File: tests/score_controls_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove that all eighteen code-drawn score controls use their visible
        faces and that nearby padding cannot activate the wrong command.

    Responsibilities:

        - probe all five score rail tools
        - require a stable text label for every score rail tool
        - probe all seven duration and six modifier buttons
        - verify button gaps, frame padding, and the blank cell are background
        - verify a hidden palette cannot consume score input
        - repeat semantic hit testing against finger-sized touch geometry

    This file intentionally does NOT contain:

        - note-entry behavior
        - MIDI mutation
        - graphical rendering
'/

#lang "fb"

#include once "../score_controls.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Dim As OseScoreControlHit controlHit
Dim As OseUiInteractionMetrics touchMetrics
Dim As String expectedToolLabels(0 To OSE_SCORE_CONTROL_TOOL_COUNT - 1) = { _
    "Select", "Note", "Delete", "Cut", "Paste" _
}
Dim As String expectedDurationLabels(0 To _
    OSE_SCORE_CONTROL_PALETTE_ROWS - 1) = { _
    "Whole", "Half", "Quarter", "Eighth", "Sixteenth", "32nd", "64th" _
}
Dim As String expectedModifierLabels(0 To 5) = { _
    "Sharp", "Flat", "Natural", "Dot", "Triplet", "Tie" _
}
For toolIndex As Integer = 0 To OSE_SCORE_CONTROL_TOOL_COUNT - 1
    Dim As Integer toolTop = OSE_SCORE_CONTROL_RAIL_FIRST_TOP + _
        toolIndex * OSE_SCORE_CONTROL_RAIL_STEP
    scoreControls_HitTest controlHit, OSE_SCORE_CONTROL_RAIL_LEFT + 5, _
        toolTop + 5, 0
    If controlHit.kind <> OSE_SCORE_CONTROL_TOOL OrElse _
        controlHit.index <> toolIndex Then _
        test_Fail "wrong score tool identity"
    If scoreControls_ToolLabel(toolIndex) <> expectedToolLabels(toolIndex) Then _
        test_Fail "score tool has no stable visible label"
Next
If scoreControls_ToolLabel(-1) <> "" OrElse _
    scoreControls_ToolLabel(OSE_SCORE_CONTROL_TOOL_COUNT) <> "" Then _
    test_Fail "invalid score tool received a visible label"

For rowIndex As Integer = 0 To OSE_SCORE_CONTROL_PALETTE_ROWS - 1
    Dim As Integer buttonTop = OSE_SCORE_CONTROL_PALETTE_TOP + 4 + _
        rowIndex * OSE_SCORE_CONTROL_PALETTE_ROW_HEIGHT
    scoreControls_HitTest controlHit, _
        OSE_SCORE_CONTROL_PALETTE_LEFT + 8, buttonTop + 5, -1
    If controlHit.kind <> OSE_SCORE_CONTROL_DURATION OrElse _
        controlHit.index <> rowIndex Then _
        test_Fail "wrong duration-button identity"
    If scoreControls_DurationLabel(rowIndex) <> _
        expectedDurationLabels(rowIndex) Then _
        test_Fail "duration button has no stable visible label"

    If rowIndex < 6 Then
        scoreControls_HitTest controlHit, _
            OSE_SCORE_CONTROL_PALETTE_LEFT + 4 + _
                OSE_SCORE_CONTROL_PALETTE_COLUMN_WIDTH + 5, _
            buttonTop + 5, -1
        If controlHit.kind <> OSE_SCORE_CONTROL_MODIFIER OrElse _
            controlHit.index <> rowIndex Then _
            test_Fail "wrong modifier-button identity"
        If scoreControls_ModifierLabel(rowIndex) <> _
            expectedModifierLabels(rowIndex) Then _
            test_Fail "modifier button has no stable visible label"
    End If
Next
If scoreControls_DurationLabel(-1) <> "" OrElse _
    scoreControls_DurationLabel(OSE_SCORE_CONTROL_PALETTE_ROWS) <> "" OrElse _
    scoreControls_ModifierLabel(-1) <> "" OrElse _
    scoreControls_ModifierLabel(6) <> "" Then _
    test_Fail "invalid palette item received a visible label"

' The left frame formerly divided a negative local coordinate toward zero and
' accidentally selected the first duration. Gaps had the same problem.
scoreControls_HitTest controlHit, OSE_SCORE_CONTROL_PALETTE_LEFT + 1, _
    OSE_SCORE_CONTROL_PALETTE_TOP + 1, -1
If controlHit.kind <> OSE_SCORE_CONTROL_PALETTE_BACKGROUND Then _
    test_Fail "palette frame activated a button"
scoreControls_HitTest controlHit, OSE_SCORE_CONTROL_PALETTE_LEFT + 4 + _
    OSE_SCORE_CONTROL_PALETTE_FACE_WIDTH, _
    OSE_SCORE_CONTROL_PALETTE_TOP + 9, -1
If controlHit.kind <> OSE_SCORE_CONTROL_PALETTE_BACKGROUND Then _
    test_Fail "inter-button gap activated a button"
scoreControls_HitTest controlHit, _
    OSE_SCORE_CONTROL_PALETTE_LEFT + 4 + _
        OSE_SCORE_CONTROL_PALETTE_COLUMN_WIDTH + 5, _
    OSE_SCORE_CONTROL_PALETTE_TOP + 4 + _
        (OSE_SCORE_CONTROL_PALETTE_ROWS - 1) * _
        OSE_SCORE_CONTROL_PALETTE_ROW_HEIGHT + 5, -1
If controlHit.kind <> OSE_SCORE_CONTROL_PALETTE_BACKGROUND Then _
    test_Fail "blank lower-right palette cell acted like a button"
scoreControls_HitTest controlHit, OSE_SCORE_CONTROL_PALETTE_LEFT + 8, _
    OSE_SCORE_CONTROL_PALETTE_TOP + 9, 0
If controlHit.kind <> OSE_SCORE_CONTROL_NONE Then _
    test_Fail "hidden palette consumed input"

scoreControls_HitTest controlHit, OSE_SCORE_CONTROL_RAIL_LEFT + _
    OSE_SCORE_CONTROL_RAIL_WIDTH, OSE_SCORE_CONTROL_RAIL_FIRST_TOP + 5, 0
If controlHit.kind <> OSE_SCORE_CONTROL_NONE Then _
    test_Fail "coordinate beyond the visible rail face selected a tool"

uiInteraction_Metrics touchMetrics, OSE_UI_INTERACTION_TOUCH
For toolIndex As Integer = 0 To OSE_SCORE_CONTROL_TOOL_COUNT - 1
    Dim As Integer toolTop = touchMetrics.scoreRailFirstTop + _
        toolIndex * touchMetrics.scoreRailStep
    scoreControls_HitTestWithMetrics controlHit, _
        touchMetrics.scoreRailLeft + touchMetrics.scoreRailWidth - 1, _
        toolTop + touchMetrics.scoreRailHeight - 1, 0, touchMetrics
    If controlHit.kind <> OSE_SCORE_CONTROL_TOOL OrElse _
        controlHit.index <> toolIndex Then _
        test_Fail "touch score tool did not use its full visible face"
Next

For rowIndex As Integer = 0 To OSE_SCORE_CONTROL_PALETTE_ROWS - 1
    Dim As Integer buttonTop = touchMetrics.scorePaletteTop + 4 + _
        rowIndex * touchMetrics.scorePaletteRowHeight
    scoreControls_HitTestWithMetrics controlHit, _
        touchMetrics.scorePaletteLeft + 4 + _
            touchMetrics.scorePaletteFaceWidth - 1, _
        buttonTop + touchMetrics.scorePaletteFaceHeight - 1, -1, touchMetrics
    If controlHit.kind <> OSE_SCORE_CONTROL_DURATION OrElse _
        controlHit.index <> rowIndex Then _
        test_Fail "touch duration did not use its full visible face"
Next

Print "score_controls=ok"
Print "tool_controls=5 tool_labels=5 palette_controls=13 palette_labels=13"; _
    " profiles=2"
End 0

/' end of tests/score_controls_smoke.bas '/
