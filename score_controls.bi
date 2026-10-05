/'
    Project: OpenSesh
    ---------------------------

    File: score_controls.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: scoreControls_* hit/label operations with OseScoreControlHit and control constants.

    Purpose:

        Declare the shared coordinate contract for the score tool rail and Add
        Note palette.

    Responsibilities:

        - identify all five score tools
        - identify seven duration and six modifier buttons
        - provide stable visible names for every code-drawn choice
        - keep frame padding and inter-button gaps noninteractive
        - distinguish palette background from coordinates outside the palette

    This file intentionally does NOT contain:

        - note-entry state mutation
        - MIDI editing
        - rendering primitives or pointer polling
'/

#ifndef __OSE_SCORE_CONTROLS_BI__
#define __OSE_SCORE_CONTROLS_BI__

#include once "ui_interaction.bi"

Const OSE_SCORE_CONTROL_TOOL_COUNT As Integer = 5
Const OSE_SCORE_CONTROL_TOOL_SELECT As Integer = 0
Const OSE_SCORE_CONTROL_TOOL_ADD_NOTE As Integer = 1
Const OSE_SCORE_CONTROL_TOOL_DELETE_NOTE As Integer = 2
Const OSE_SCORE_CONTROL_TOOL_CUT As Integer = 3
Const OSE_SCORE_CONTROL_TOOL_PASTE As Integer = 4

Const OSE_SCORE_CONTROL_RAIL_LEFT As Integer = 6
Const OSE_SCORE_CONTROL_RAIL_FIRST_TOP As Integer = 107
Const OSE_SCORE_CONTROL_RAIL_WIDTH As Integer = 82
Const OSE_SCORE_CONTROL_RAIL_HEIGHT As Integer = 29
Const OSE_SCORE_CONTROL_RAIL_STEP As Integer = 31

Const OSE_SCORE_CONTROL_PALETTE_LEFT As Integer = 90
Const OSE_SCORE_CONTROL_PALETTE_TOP As Integer = 138
Const OSE_SCORE_CONTROL_PALETTE_COLUMN_WIDTH As Integer = 86
Const OSE_SCORE_CONTROL_PALETTE_ROW_HEIGHT As Integer = 27
Const OSE_SCORE_CONTROL_PALETTE_FACE_WIDTH As Integer = 84
Const OSE_SCORE_CONTROL_PALETTE_FACE_HEIGHT As Integer = 25
Const OSE_SCORE_CONTROL_PALETTE_COLUMNS As Integer = 2
Const OSE_SCORE_CONTROL_PALETTE_ROWS As Integer = 7
Const OSE_SCORE_CONTROL_PALETTE_WIDTH As Integer = 180
Const OSE_SCORE_CONTROL_PALETTE_HEIGHT As Integer = 197

Const OSE_SCORE_CONTROL_NONE As Integer = 0
Const OSE_SCORE_CONTROL_TOOL As Integer = 1
Const OSE_SCORE_CONTROL_DURATION As Integer = 2
Const OSE_SCORE_CONTROL_MODIFIER As Integer = 3
Const OSE_SCORE_CONTROL_PALETTE_BACKGROUND As Integer = 4

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseScoreControlHit
    As Integer kind
    As Integer index
End Type

Declare Sub scoreControls_HitTest( _
    ByRef controlHit As OseScoreControlHit, _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer, _
    ByVal paletteVisible As Integer _
)

Declare Sub scoreControls_HitTestWithMetrics( _
    ByRef controlHit As OseScoreControlHit, _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer, _
    ByVal paletteVisible As Integer, _
    ByRef metrics As OseUiInteractionMetrics _
)

Declare Function scoreControls_ToolLabel( _
    ByVal toolIndex As Integer _
) As String

Declare Function scoreControls_DurationLabel( _
    ByVal durationIndex As Integer _
) As String

Declare Function scoreControls_ModifierLabel( _
    ByVal modifierIndex As Integer _
) As String

#endif

/' end of score_controls.bi '/
