/'
    Project: OpenSesh
    ---------------------------

    File: score_tools.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: scoreAddTool_* duration/accidental operations with ScoreAddToolState and tool constants.

    Purpose:

        Define the notation-entry choices shared by the Score View palette
        and deterministic tests.

    Responsibilities:

        - retain the selected whole-through-sixty-fourth note value
        - retain accidental, dot, triplet, and tie modifiers
        - convert the selected note value into bounded MIDI ticks
        - apply a bounded accidental offset to a MIDI key number

    This file intentionally does NOT contain:

        - score coordinates or mouse handling
        - omaGUI drawing
        - MIDI document mutation
'/

#ifndef __OSE_SCORE_TOOLS_BI__
#define __OSE_SCORE_TOOLS_BI__

Const OSE_SCORE_DURATION_WHOLE As Integer = 0
Const OSE_SCORE_DURATION_HALF As Integer = 1
Const OSE_SCORE_DURATION_QUARTER As Integer = 2
Const OSE_SCORE_DURATION_EIGHTH As Integer = 3
Const OSE_SCORE_DURATION_SIXTEENTH As Integer = 4
Const OSE_SCORE_DURATION_THIRTY_SECOND As Integer = 5
Const OSE_SCORE_DURATION_SIXTY_FOURTH As Integer = 6
Const OSE_SCORE_DURATION_COUNT As Integer = 7

Const OSE_SCORE_MODIFIER_DOT As Integer = 1
Const OSE_SCORE_MODIFIER_TRIPLET As Integer = 2
Const OSE_SCORE_MODIFIER_TIE As Integer = 3

Type ScoreAddToolState
    As Integer durationIndex
    As Integer accidentalSemitones
    As Integer dotted
    As Integer triplet
    As Integer tied
End Type

Declare Sub scoreAddTool_Initialize(ByRef state As ScoreAddToolState)

Declare Function scoreAddTool_SetDuration( _
    ByRef state As ScoreAddToolState, _
    ByVal durationIndex As Integer _
) As Integer

Declare Function scoreAddTool_SetAccidental( _
    ByRef state As ScoreAddToolState, _
    ByVal accidentalSemitones As Integer _
) As Integer

Declare Function scoreAddTool_ToggleModifier( _
    ByRef state As ScoreAddToolState, _
    ByVal modifierKind As Integer _
) As Integer

Declare Function scoreAddTool_DurationTicks( _
    ByRef state As ScoreAddToolState, _
    ByVal division As Integer _
) As ULongInt

Declare Function scoreAddTool_ApplyAccidental( _
    ByVal keyNumber As Integer, _
    ByRef state As ScoreAddToolState _
) As Integer

Declare Function scoreAddTool_DurationName( _
    ByVal durationIndex As Integer _
) As String

#endif

/' end of score_tools.bi '/
