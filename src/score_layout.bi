/'
    Project: OpenSesh
    ---------------------------

    File: score_layout.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: scoreLayout_* staff/row mapping with OseScoreLayoutState and geometry limits.

    Purpose:

        Declare stable per-track score layout decisions and the shared
        vertical zoom geometry used by drawing and pointer input.

    Responsibilities:

        - choose an initial treble or bass clef from imported track pitches
        - retain that clef throughout ordinary note editing
        - keep clef state aligned when tracks are added or removed
        - calculate scaled staff, note, and hit-target measurements
        - calculate the vertical note position for the retained clef

    This file intentionally does NOT contain:

        - MIDI model mutation
        - score drawing or mouse input
        - full engraving or user-facing clef-change commands
'/

#ifndef __OSE_SCORE_LAYOUT_BI__
#define __OSE_SCORE_LAYOUT_BI__

#include once "midi_model.bi"

Const OSE_SCORE_CLEF_TREBLE As UByte = 0
Const OSE_SCORE_CLEF_BASS As UByte = 1

Const OSE_SCORE_ROW_HEIGHT_MINIMUM As Integer = 44
Const OSE_SCORE_ROW_HEIGHT_DEFAULT As Integer = 52
Const OSE_SCORE_ROW_HEIGHT_MAXIMUM As Integer = 100
Const OSE_SCORE_LINE_SPACING_DEFAULT As Integer = 7

Type OseScoreLayoutState
    As Integer trackCount
    As Integer collectingInitialPitches
    As LongInt pitchTotal(0 To OSE_MAX_MIDI_TRACKS - 1)
    As Integer pitchCount(0 To OSE_MAX_MIDI_TRACKS - 1)
    As UByte clef(0 To OSE_MAX_MIDI_TRACKS - 1)
End Type

Declare Sub scoreLayout_BeginDocument( _
    ByRef state As OseScoreLayoutState, _
    ByVal trackCount As Integer _
)

Declare Sub scoreLayout_ObserveInitialPitch( _
    ByRef state As OseScoreLayoutState, _
    ByVal trackIndex As Integer, _
    ByVal keyNumber As Integer _
)

Declare Sub scoreLayout_FinalizeDocument(ByRef state As OseScoreLayoutState)

Declare Function scoreLayout_AddTrack( _
    ByRef state As OseScoreLayoutState _
) As Integer

Declare Function scoreLayout_RemoveTrack( _
    ByRef state As OseScoreLayoutState, _
    ByVal trackIndex As Integer _
) As Integer

Declare Sub scoreLayout_SynchronizeTrackCount( _
    ByRef state As OseScoreLayoutState, _
    ByVal trackCount As Integer _
)

Declare Function scoreLayout_UsesBassClef( _
    ByRef state As OseScoreLayoutState, _
    ByVal trackIndex As Integer _
) As Integer

Declare Function scoreLayout_BoundedRowHeight( _
    ByVal rowHeight As Integer _
) As Integer

Declare Function scoreLayout_LineSpacing( _
    ByVal rowHeight As Integer _
) As Integer

Declare Function scoreLayout_StaffHeight( _
    ByVal rowHeight As Integer _
) As Integer

Declare Function scoreLayout_RowTopOffset( _
    ByVal rowHeight As Integer _
) As Integer

Declare Function scoreLayout_FirstStaffOffset( _
    ByVal rowHeight As Integer _
) As Integer

Declare Function scoreLayout_ScalePixels( _
    ByVal rowHeight As Integer, _
    ByVal defaultPixels As Integer _
) As Integer

Declare Function scoreLayout_NoteY( _
    ByRef state As OseScoreLayoutState, _
    ByVal trackIndex As Integer, _
    ByVal staffY As Integer, _
    ByVal diatonicStep As Integer, _
    ByVal rowHeight As Integer _
) As Integer

#endif

/' end of score_layout.bi '/
