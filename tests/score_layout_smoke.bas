/'
    Project: OpenSesh
    ---------------------------

    File: tests/score_layout_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify stable clef selection and coherent vertical score zoom.

    Responsibilities:

        - reproduce the former middle-C average clef-flip regression
        - verify imported low and high tracks receive appropriate initial clefs
        - verify track addition and removal keep clef state aligned
        - verify invalid track and pitch observations are bounded
        - prove staff lines, notes, and hit geometry grow together

    This file intentionally does NOT contain:

        - graphical rendering or screenshot comparison
        - MIDI model mutation
        - user-facing clef editing
'/

#lang "fb"

#include once "../src/score_layout.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "ERROR: "; messageText
    End 1
End Sub


Dim As OseScoreLayoutState layoutState
scoreLayout_BeginDocument layoutState, 2
scoreLayout_ObserveInitialPitch layoutState, 0, 60
scoreLayout_ObserveInitialPitch layoutState, 1, 48
scoreLayout_ObserveInitialPitch layoutState, -1, 0
scoreLayout_ObserveInitialPitch layoutState, 99, 127
scoreLayout_ObserveInitialPitch layoutState, 0, -1
scoreLayout_ObserveInitialPitch layoutState, 0, 128
scoreLayout_FinalizeDocument layoutState

If scoreLayout_UsesBassClef(layoutState, 0) <> 0 Then _
    test_Fail "middle-C track did not start in treble clef"
If scoreLayout_UsesBassClef(layoutState, 1) = 0 Then _
    test_Fail "low imported track did not start in bass clef"

Dim As Integer originalMiddleCY = scoreLayout_NoteY( _
    layoutState, 0, 160, 35, OSE_SCORE_ROW_HEIGHT_DEFAULT)

' Before this state was retained, observing B3 after middle C changed the
' integer pitch average from 60 to 59, flipped to bass clef, and moved every
' already-rendered note by a complete staff interval.
scoreLayout_ObserveInitialPitch layoutState, 0, 59
scoreLayout_FinalizeDocument layoutState
If scoreLayout_UsesBassClef(layoutState, 0) <> 0 OrElse _
    scoreLayout_NoteY(layoutState, 0, 160, 35, _
        OSE_SCORE_ROW_HEIGHT_DEFAULT) <> originalMiddleCY Then _
    test_Fail "an inserted note changed existing score coordinates"

Dim As Integer minimumSpacing = scoreLayout_LineSpacing( _
    OSE_SCORE_ROW_HEIGHT_MINIMUM)
Dim As Integer defaultSpacing = scoreLayout_LineSpacing( _
    OSE_SCORE_ROW_HEIGHT_DEFAULT)
Dim As Integer maximumSpacing = scoreLayout_LineSpacing( _
    OSE_SCORE_ROW_HEIGHT_MAXIMUM)
If minimumSpacing <> 6 OrElse defaultSpacing <> 7 OrElse _
    maximumSpacing <> 13 Then _
    test_Fail "vertical zoom did not separate staff lines predictably"
If scoreLayout_StaffHeight(OSE_SCORE_ROW_HEIGHT_MAXIMUM) <= _
    scoreLayout_StaffHeight(OSE_SCORE_ROW_HEIGHT_DEFAULT) OrElse _
    scoreLayout_ScalePixels(OSE_SCORE_ROW_HEIGHT_MAXIMUM, 10) <= 10 OrElse _
    scoreLayout_ScalePixels(OSE_SCORE_ROW_HEIGHT_MAXIMUM, 14) <= 14 Then _
    test_Fail "vertical zoom did not enlarge notation and hit geometry"

Dim As Integer defaultLowNoteY = scoreLayout_NoteY( _
    layoutState, 0, 160, 28, OSE_SCORE_ROW_HEIGHT_DEFAULT)
Dim As Integer maximumLowNoteY = scoreLayout_NoteY( _
    layoutState, 0, 160, 28, OSE_SCORE_ROW_HEIGHT_MAXIMUM)
If maximumLowNoteY - 160 <= defaultLowNoteY - 160 Then _
    test_Fail "vertical zoom did not spread note pitch positions"
If scoreLayout_FirstStaffOffset(OSE_SCORE_ROW_HEIGHT_DEFAULT) - _
    scoreLayout_RowTopOffset(OSE_SCORE_ROW_HEIGHT_DEFAULT) <> 39 OrElse _
    scoreLayout_FirstStaffOffset(OSE_SCORE_ROW_HEIGHT_MAXIMUM) - _
    scoreLayout_RowTopOffset(OSE_SCORE_ROW_HEIGHT_MAXIMUM) <> 39 Then _
    test_Fail "vertical zoom moved the first row into the score header"
If scoreLayout_BoundedRowHeight(-1) <> OSE_SCORE_ROW_HEIGHT_MINIMUM OrElse _
    scoreLayout_BoundedRowHeight(1000) <> OSE_SCORE_ROW_HEIGHT_MAXIMUM Then _
    test_Fail "vertical zoom row height was not bounded"

Dim As Integer addedTrack = scoreLayout_AddTrack(layoutState)
If addedTrack <> 2 OrElse layoutState.trackCount <> 3 OrElse _
    scoreLayout_UsesBassClef(layoutState, addedTrack) <> 0 Then _
    test_Fail "new track did not receive a stable treble layout"

If scoreLayout_RemoveTrack(layoutState, 0) = 0 OrElse _
    layoutState.trackCount <> 2 OrElse _
    scoreLayout_UsesBassClef(layoutState, 0) = 0 Then _
    test_Fail "track removal did not compact retained clefs"
If scoreLayout_RemoveTrack(layoutState, -1) <> 0 OrElse _
    scoreLayout_RemoveTrack(layoutState, 2) <> 0 Then _
    test_Fail "invalid track removal was accepted"

scoreLayout_SynchronizeTrackCount layoutState, OSE_MAX_MIDI_TRACKS + 10
If layoutState.trackCount <> OSE_MAX_MIDI_TRACKS OrElse _
    scoreLayout_AddTrack(layoutState) <> -1 Then _
    test_Fail "track limit was not enforced"
scoreLayout_SynchronizeTrackCount layoutState, -10
If layoutState.trackCount <> 0 Then _
    test_Fail "negative synchronized track count was not bounded"

Print "score_layout=ok"
Print "stable_middle_c_y="; originalMiddleCY
Print "line_spacing="; minimumSpacing; ","; defaultSpacing; ","; maximumSpacing
End 0

/' end of score_layout_smoke.bas '/
