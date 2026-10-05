/'
    Project: OpenSesh
    ---------------------------

    File: score_tools_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify the Score View note-entry palette calculations independently
        from omaGUI and mouse input.

    Responsibilities:

        - verify all seven documented note values
        - verify dot and triplet timing modifiers
        - verify accidental clamping and modifier toggles

    This file intentionally does NOT contain:

        - application window creation
        - MIDI document mutation
        - visual icon assertions
'/

#lang "fb"

#include once "../src/score_tools.bi"

Dim As ScoreAddToolState state
scoreAddTool_Initialize state
If state.durationIndex <> OSE_SCORE_DURATION_QUARTER OrElse _
    scoreAddTool_DurationTicks(state, 96) <> 96 Then
    Print "ERROR: note palette did not initialize to a quarter note"
    End 1
End If

Dim As ULongInt expectedTicks(0 To OSE_SCORE_DURATION_COUNT - 1) = { _
    384, 192, 96, 48, 24, 12, 6 _
}
For durationIndex As Integer = 0 To OSE_SCORE_DURATION_COUNT - 1
    If scoreAddTool_SetDuration(state, durationIndex) = 0 OrElse _
        scoreAddTool_DurationTicks(state, 96) <> expectedTicks(durationIndex) Then
        Print "ERROR: incorrect duration for palette index"; durationIndex
        End 1
    End If
Next

Dim As String expectedNames(0 To OSE_SCORE_DURATION_COUNT - 1) = { _
    "whole", "half", "quarter", "eighth", "sixteenth", _
    "thirty-second", "sixty-fourth" _
}
For durationIndex As Integer = 0 To OSE_SCORE_DURATION_COUNT - 1
    If scoreAddTool_DurationName(durationIndex) <> expectedNames(durationIndex) Then
        Print "ERROR: duration name did not match its visible choice"
        End 1
    End If
Next
If scoreAddTool_DurationName(-1) <> "unknown" OrElse _
    scoreAddTool_DurationName(OSE_SCORE_DURATION_COUNT) <> "unknown" Then
    Print "ERROR: invalid duration name was not bounded"
    End 1
End If

scoreAddTool_SetDuration state, OSE_SCORE_DURATION_EIGHTH
If scoreAddTool_ToggleModifier(state, OSE_SCORE_MODIFIER_DOT) = 0 OrElse _
    scoreAddTool_DurationTicks(state, 96) <> 72 Then
    Print "ERROR: dotted-note calculation is incorrect"
    End 1
End If
If scoreAddTool_ToggleModifier(state, OSE_SCORE_MODIFIER_TRIPLET) = 0 OrElse _
    scoreAddTool_DurationTicks(state, 96) <> 48 Then
    Print "ERROR: combined dot and triplet calculation is incorrect"
    End 1
End If
If scoreAddTool_ToggleModifier(state, OSE_SCORE_MODIFIER_DOT) = 0 OrElse _
    scoreAddTool_DurationTicks(state, 96) <> 32 Then
    Print "ERROR: triplet-note calculation is incorrect"
    End 1
End If

If scoreAddTool_SetAccidental(state, 2) = 0 OrElse _
    scoreAddTool_ApplyAccidental(126, state) <> 127 OrElse _
    scoreAddTool_SetAccidental(state, -2) = 0 OrElse _
    scoreAddTool_ApplyAccidental(1, state) <> 0 Then
    Print "ERROR: accidental pitch clamping is incorrect"
    End 1
End If
If scoreAddTool_SetAccidental(state, 3) <> 0 OrElse _
    scoreAddTool_ToggleModifier(state, 99) <> 0 Then
    Print "ERROR: invalid palette choice was accepted"
    End 1
End If

Print "score tools smoke test passed"
End 0

/' end of score_tools_smoke.bas '/
