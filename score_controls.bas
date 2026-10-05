/'
    Project: OpenSesh
    ---------------------------

    File: score_controls.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements score_controls.bi; declarations there define the shared interface.

    Purpose:

        Keep score-control drawing and pointer input on exact matching bounds.

    Responsibilities:

        - map rail coordinates to one of five tool identities
        - map palette faces to duration or modifier identities
        - expose the labels rendered beside compact notation glyphs
        - consume palette padding without activating a nearby button
        - reject the intentionally blank lower-right palette cell

    This file intentionally does NOT contain:

        - application globals
        - palette selection behavior
        - score drawing or note placement
'/

#lang "fb"

#include once "score_controls.bi"

' -------------------------------------------------------------------------
' Accessible tool names
' -------------------------------------------------------------------------

Public Function scoreControls_ToolLabel( _
    ByVal toolIndex As Integer _
) As String
    Select Case toolIndex
        Case OSE_SCORE_CONTROL_TOOL_SELECT
            Return "Select"
        Case OSE_SCORE_CONTROL_TOOL_ADD_NOTE
            Return "Note"
        Case OSE_SCORE_CONTROL_TOOL_DELETE_NOTE
            Return "Delete"
        Case OSE_SCORE_CONTROL_TOOL_CUT
            Return "Cut"
        Case OSE_SCORE_CONTROL_TOOL_PASTE
            Return "Paste"
    End Select

    Return ""
End Function


Public Function scoreControls_DurationLabel( _
    ByVal durationIndex As Integer _
) As String
    Select Case durationIndex
        Case 0
            Return "Whole"
        Case 1
            Return "Half"
        Case 2
            Return "Quarter"
        Case 3
            Return "Eighth"
        Case 4
            Return "Sixteenth"
        Case 5
            Return "32nd"
        Case 6
            Return "64th"
    End Select

    Return ""
End Function


Public Function scoreControls_ModifierLabel( _
    ByVal modifierIndex As Integer _
) As String
    Select Case modifierIndex
        Case 0
            Return "Sharp"
        Case 1
            Return "Flat"
        Case 2
            Return "Natural"
        Case 3
            Return "Dot"
        Case 4
            Return "Triplet"
        Case 5
            Return "Tie"
    End Select

    Return ""
End Function


' -------------------------------------------------------------------------
' Control hit testing
' -------------------------------------------------------------------------

Public Sub scoreControls_HitTest( _
    ByRef controlHit As OseScoreControlHit, _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer, _
    ByVal paletteVisible As Integer _
)
    Dim As OseUiInteractionMetrics metrics
    uiInteraction_Metrics metrics, OSE_UI_INTERACTION_FINE
    scoreControls_HitTestWithMetrics controlHit, pointerX, pointerY, _
        paletteVisible, metrics
End Sub


Public Sub scoreControls_HitTestWithMetrics( _
    ByRef controlHit As OseScoreControlHit, _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer, _
    ByVal paletteVisible As Integer, _
    ByRef metrics As OseUiInteractionMetrics _
)
    Dim As OseScoreControlHit emptyHit
    controlHit = emptyHit
    controlHit.index = -1

    If paletteVisible <> 0 AndAlso _
        pointerX >= metrics.scorePaletteLeft AndAlso _
        pointerX < metrics.scorePaletteLeft + _
            metrics.scorePaletteWidth AndAlso _
        pointerY >= metrics.scorePaletteTop AndAlso _
        pointerY < metrics.scorePaletteTop + _
            metrics.scorePaletteHeight Then
        controlHit.kind = OSE_SCORE_CONTROL_PALETTE_BACKGROUND

        Dim As Integer contentX = pointerX - _
            metrics.scorePaletteLeft - 4
        Dim As Integer contentY = pointerY - _
            metrics.scorePaletteTop - 4
        If contentX < 0 OrElse contentY < 0 Then
            Exit Sub
        End If

        Dim As Integer columnIndex = _
            contentX \ metrics.scorePaletteColumnWidth
        Dim As Integer rowIndex = _
            contentY \ metrics.scorePaletteRowHeight
        If columnIndex < 0 OrElse _
            columnIndex >= OSE_SCORE_CONTROL_PALETTE_COLUMNS OrElse _
            rowIndex < 0 OrElse rowIndex >= OSE_SCORE_CONTROL_PALETTE_ROWS Then
            Exit Sub
        End If

        Dim As Integer cellX = _
            contentX - columnIndex * metrics.scorePaletteColumnWidth
        Dim As Integer cellY = _
            contentY - rowIndex * metrics.scorePaletteRowHeight
        If cellX >= metrics.scorePaletteFaceWidth OrElse _
            cellY >= metrics.scorePaletteFaceHeight Then
            Exit Sub
        End If

        If columnIndex = 0 Then
            controlHit.kind = OSE_SCORE_CONTROL_DURATION
            controlHit.index = rowIndex
        ElseIf rowIndex < 6 Then
            controlHit.kind = OSE_SCORE_CONTROL_MODIFIER
            controlHit.index = rowIndex
        End If
        Exit Sub
    End If

    If pointerX < metrics.scoreRailLeft OrElse _
        pointerX >= metrics.scoreRailLeft + metrics.scoreRailWidth OrElse _
        pointerY < metrics.scoreRailFirstTop Then
        Exit Sub
    End If

    Dim As Integer toolIndex = _
        (pointerY - metrics.scoreRailFirstTop) \ metrics.scoreRailStep
    If toolIndex < 0 OrElse toolIndex >= OSE_SCORE_CONTROL_TOOL_COUNT Then
        Exit Sub
    End If
    Dim As Integer toolTop = metrics.scoreRailFirstTop + _
        toolIndex * metrics.scoreRailStep
    If pointerY >= toolTop + metrics.scoreRailHeight Then
        Exit Sub
    End If

    controlHit.kind = OSE_SCORE_CONTROL_TOOL
    controlHit.index = toolIndex
End Sub

/' end of score_controls.bas '/
