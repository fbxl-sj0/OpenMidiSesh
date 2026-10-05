/'
    Project: OpenSesh
    ---------------------------

    File: score_layout.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements score_layout.bi; declarations there define the shared interface.

    Purpose:

        Keep each track's score coordinate system stable while notes are
        edited, and derive one coherent geometry from vertical zoom.

    Responsibilities:

        - derive one initial clef from a bounded imported pitch average
        - prevent later note edits from silently changing the retained clef
        - compact or extend layout state alongside track operations
        - scale staff, notation, and input measurements from track row height
        - map diatonic pitch steps into the selected staff coordinate system

    This file intentionally does NOT contain:

        - score rendering primitives
        - MIDI document storage
        - automatic clef changes inside an existing track
'/

#lang "fb"

#include once "score_layout.bi"

' Middle C is the initial clef boundary used by the compact score preview.
Const SCORE_LAYOUT_BASS_BOUNDARY_KEY As Integer = 60
' Treble F5 and bass A3 are the top lines of the two compact staff layouts.
Const SCORE_LAYOUT_TREBLE_TOP_DIATONIC As Integer = 38
Const SCORE_LAYOUT_BASS_TOP_DIATONIC As Integer = 26


Private Function scoreLayout_BoundedTrackCount( _
    ByVal trackCount As Integer _
) As Integer
    If trackCount < 0 Then
        Return 0
    End If
    If trackCount > OSE_MAX_MIDI_TRACKS Then
        Return OSE_MAX_MIDI_TRACKS
    End If
    Return trackCount
End Function


Public Sub scoreLayout_BeginDocument( _
    ByRef state As OseScoreLayoutState, _
    ByVal trackCount As Integer _
)
    state.trackCount = scoreLayout_BoundedTrackCount(trackCount)
    state.collectingInitialPitches = -1
    For trackIndex As Integer = 0 To OSE_MAX_MIDI_TRACKS - 1
        state.pitchTotal(trackIndex) = 0
        state.pitchCount(trackIndex) = 0
        state.clef(trackIndex) = OSE_SCORE_CLEF_TREBLE
    Next
End Sub


Public Sub scoreLayout_ObserveInitialPitch( _
    ByRef state As OseScoreLayoutState, _
    ByVal trackIndex As Integer, _
    ByVal keyNumber As Integer _
)
    If state.collectingInitialPitches = 0 Then
        Exit Sub
    End If
    If trackIndex < 0 OrElse trackIndex >= state.trackCount Then
        Exit Sub
    End If
    If keyNumber < 0 OrElse keyNumber > 127 Then
        Exit Sub
    End If
    If state.pitchCount(trackIndex) >= 2147483647 Then
        Exit Sub
    End If

    state.pitchTotal(trackIndex) += keyNumber
    state.pitchCount(trackIndex) += 1
End Sub


Public Sub scoreLayout_FinalizeDocument(ByRef state As OseScoreLayoutState)
    If state.collectingInitialPitches = 0 Then
        Exit Sub
    End If

    For trackIndex As Integer = 0 To state.trackCount - 1
        If state.pitchCount(trackIndex) > 0 AndAlso _
            state.pitchTotal(trackIndex) \ state.pitchCount(trackIndex) < _
                SCORE_LAYOUT_BASS_BOUNDARY_KEY Then
            state.clef(trackIndex) = OSE_SCORE_CLEF_BASS
        Else
            state.clef(trackIndex) = OSE_SCORE_CLEF_TREBLE
        End If
    Next
    state.collectingInitialPitches = 0
End Sub


Public Function scoreLayout_AddTrack( _
    ByRef state As OseScoreLayoutState _
) As Integer
    If state.trackCount < 0 Then
        state.trackCount = 0
    End If
    If state.trackCount >= OSE_MAX_MIDI_TRACKS Then
        Return -1
    End If

    Dim As Integer addedTrack = state.trackCount
    state.pitchTotal(addedTrack) = 0
    state.pitchCount(addedTrack) = 0
    state.clef(addedTrack) = OSE_SCORE_CLEF_TREBLE
    state.trackCount += 1
    Return addedTrack
End Function


Public Function scoreLayout_RemoveTrack( _
    ByRef state As OseScoreLayoutState, _
    ByVal trackIndex As Integer _
) As Integer
    If trackIndex < 0 OrElse trackIndex >= state.trackCount Then
        Return 0
    End If

    For destinationTrack As Integer = trackIndex To state.trackCount - 2
        state.pitchTotal(destinationTrack) = state.pitchTotal(destinationTrack + 1)
        state.pitchCount(destinationTrack) = state.pitchCount(destinationTrack + 1)
        state.clef(destinationTrack) = state.clef(destinationTrack + 1)
    Next

    state.trackCount -= 1
    If state.trackCount < 0 Then
        state.trackCount = 0
    End If
    state.pitchTotal(state.trackCount) = 0
    state.pitchCount(state.trackCount) = 0
    state.clef(state.trackCount) = OSE_SCORE_CLEF_TREBLE
    Return -1
End Function


Public Sub scoreLayout_SynchronizeTrackCount( _
    ByRef state As OseScoreLayoutState, _
    ByVal trackCount As Integer _
)
    Dim As Integer boundedCount = scoreLayout_BoundedTrackCount(trackCount)
    While state.trackCount < boundedCount
        If scoreLayout_AddTrack(state) < 0 Then
            Exit While
        End If
    Wend
    If state.trackCount > boundedCount Then
        state.trackCount = boundedCount
    End If
End Sub


Public Function scoreLayout_UsesBassClef( _
    ByRef state As OseScoreLayoutState, _
    ByVal trackIndex As Integer _
) As Integer
    If trackIndex < 0 OrElse trackIndex >= state.trackCount Then
        Return 0
    End If
    Return IIf(state.clef(trackIndex) = OSE_SCORE_CLEF_BASS, -1, 0)
End Function


Public Function scoreLayout_BoundedRowHeight( _
    ByVal rowHeight As Integer _
) As Integer
    If rowHeight < OSE_SCORE_ROW_HEIGHT_MINIMUM Then
        Return OSE_SCORE_ROW_HEIGHT_MINIMUM
    End If
    If rowHeight > OSE_SCORE_ROW_HEIGHT_MAXIMUM Then
        Return OSE_SCORE_ROW_HEIGHT_MAXIMUM
    End If
    Return rowHeight
End Function


Public Function scoreLayout_LineSpacing( _
    ByVal rowHeight As Integer _
) As Integer
    Dim As Integer boundedHeight = scoreLayout_BoundedRowHeight(rowHeight)
    Dim As Integer spacing = CInt((CDbl(boundedHeight) * _
        OSE_SCORE_LINE_SPACING_DEFAULT) / OSE_SCORE_ROW_HEIGHT_DEFAULT)
    If spacing < 1 Then
        spacing = 1
    End If
    Return spacing
End Function


Public Function scoreLayout_StaffHeight( _
    ByVal rowHeight As Integer _
) As Integer
    ' Five staff lines contain four complete line-to-line spaces.
    Return scoreLayout_LineSpacing(rowHeight) * 4
End Function


Public Function scoreLayout_RowTopOffset( _
    ByVal rowHeight As Integer _
) As Integer
    ' Three staff spaces reserve room above the top line for labels and notes.
    Return scoreLayout_LineSpacing(rowHeight) * 3
End Function


Public Function scoreLayout_FirstStaffOffset( _
    ByVal rowHeight As Integer _
) As Integer
    /'
        The first row begins 39 pixels below the score panel. Moving its staff
        by the scaled top offset keeps that row boundary fixed while the lines
        separate, so zoom never invades the ruler and title area.
    '/
    Const FIRST_ROW_TOP As Integer = 39
    Return FIRST_ROW_TOP + scoreLayout_RowTopOffset(rowHeight)
End Function


Public Function scoreLayout_ScalePixels( _
    ByVal rowHeight As Integer, _
    ByVal defaultPixels As Integer _
) As Integer
    If defaultPixels = 0 Then
        Return 0
    End If

    Dim As Integer signValue = 1
    Dim As Integer magnitude = defaultPixels
    If magnitude < 0 Then
        signValue = -1
        magnitude = -magnitude
    End If

    Dim As Integer scaledValue = (magnitude * _
        scoreLayout_LineSpacing(rowHeight) + _
        OSE_SCORE_LINE_SPACING_DEFAULT \ 2) \ _
        OSE_SCORE_LINE_SPACING_DEFAULT
    If scaledValue < 1 Then
        scaledValue = 1
    End If
    Return scaledValue * signValue
End Function


Public Function scoreLayout_NoteY( _
    ByRef state As OseScoreLayoutState, _
    ByVal trackIndex As Integer, _
    ByVal staffY As Integer, _
    ByVal diatonicStep As Integer, _
    ByVal rowHeight As Integer _
) As Integer
    Dim As Integer topLineDiatonic = SCORE_LAYOUT_TREBLE_TOP_DIATONIC
    If scoreLayout_UsesBassClef(state, trackIndex) <> 0 Then
        topLineDiatonic = SCORE_LAYOUT_BASS_TOP_DIATONIC
    End If
    Dim As Integer lineSpacing = scoreLayout_LineSpacing(rowHeight)
    Return staffY + CInt(CDbl(topLineDiatonic - diatonicStep) * _
        CDbl(lineSpacing) / 2.0)
End Function

/' end of score_layout.bas '/
