/'
    Project: OpenSesh
    ---------------------------

    File: score_tools.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements score_tools.bi; declarations there define the shared interface.

    Purpose:

        Maintain the Score View note-entry palette state without depending on
        the GUI or the active MIDI document.

    Responsibilities:

        - validate palette choices
        - calculate whole-through-sixty-fourth note lengths
        - combine dotted and triplet timing modifiers deterministically
        - clamp accidental pitch changes to the MIDI key range

    This file intentionally does NOT contain:

        - note insertion or editing
        - score rendering
        - persistent application state
'/

#lang "fb"

#include once "score_tools.bi"

Const SCORE_TOOL_MAX_TICK As ULongInt = &H7FFFFFFFFFFFFFFFULL

' -------------------------------------------------------------------------
' Palette state
' -------------------------------------------------------------------------

Public Sub scoreAddTool_Initialize(ByRef state As ScoreAddToolState)
    state.durationIndex = OSE_SCORE_DURATION_QUARTER
    state.accidentalSemitones = 0
    state.dotted = 0
    state.triplet = 0
    state.tied = 0
End Sub


Public Function scoreAddTool_SetDuration( _
    ByRef state As ScoreAddToolState, _
    ByVal durationIndex As Integer _
) As Integer
    If durationIndex < 0 OrElse durationIndex >= OSE_SCORE_DURATION_COUNT Then
        Return 0
    End If

    state.durationIndex = durationIndex
    Return -1
End Function


Public Function scoreAddTool_SetAccidental( _
    ByRef state As ScoreAddToolState, _
    ByVal accidentalSemitones As Integer _
) As Integer
    If accidentalSemitones < -2 OrElse accidentalSemitones > 2 Then
        Return 0
    End If

    state.accidentalSemitones = accidentalSemitones
    Return -1
End Function


Public Function scoreAddTool_ToggleModifier( _
    ByRef state As ScoreAddToolState, _
    ByVal modifierKind As Integer _
) As Integer
    Select Case modifierKind
        Case OSE_SCORE_MODIFIER_DOT
            state.dotted = IIf(state.dotted = 0, -1, 0)
        Case OSE_SCORE_MODIFIER_TRIPLET
            state.triplet = IIf(state.triplet = 0, -1, 0)
        Case OSE_SCORE_MODIFIER_TIE
            state.tied = IIf(state.tied = 0, -1, 0)
        Case Else
            Return 0
    End Select

    Return -1
End Function


' -------------------------------------------------------------------------
' Bounded note calculations
' -------------------------------------------------------------------------

Public Function scoreAddTool_DurationTicks( _
    ByRef state As ScoreAddToolState, _
    ByVal division As Integer _
) As ULongInt
    If division <= 0 Then
        Return 1
    End If
    If state.durationIndex < 0 OrElse _
        state.durationIndex >= OSE_SCORE_DURATION_COUNT Then
        Return 1
    End If

    Dim As ULongInt durationTicks = CULngInt(division)
    Select Case state.durationIndex
        Case OSE_SCORE_DURATION_WHOLE
            If durationTicks > SCORE_TOOL_MAX_TICK \ 4 Then
                durationTicks = SCORE_TOOL_MAX_TICK
            Else
                durationTicks *= 4
            End If
        Case OSE_SCORE_DURATION_HALF
            If durationTicks > SCORE_TOOL_MAX_TICK \ 2 Then
                durationTicks = SCORE_TOOL_MAX_TICK
            Else
                durationTicks *= 2
            End If
        Case OSE_SCORE_DURATION_QUARTER
            ' The MIDI division already expresses one quarter note.
        Case Else
            Dim As Integer shiftCount = state.durationIndex - _
                OSE_SCORE_DURATION_QUARTER
            For shiftIndex As Integer = 1 To shiftCount
                durationTicks \= 2
                If durationTicks = 0 Then
                    durationTicks = 1
                    Exit For
                End If
            Next
    End Select

    If state.triplet <> 0 Then
        durationTicks = (durationTicks * 2) \ 3
        If durationTicks = 0 Then
            durationTicks = 1
        End If
    End If

    If state.dotted <> 0 Then
        If durationTicks > SCORE_TOOL_MAX_TICK \ 3 Then
            durationTicks = SCORE_TOOL_MAX_TICK
        Else
            durationTicks = (durationTicks * 3) \ 2
        End If
        If durationTicks = 0 Then
            durationTicks = 1
        End If
    End If

    Return durationTicks
End Function


Public Function scoreAddTool_ApplyAccidental( _
    ByVal keyNumber As Integer, _
    ByRef state As ScoreAddToolState _
) As Integer
    Dim As Integer adjustedKey = keyNumber + state.accidentalSemitones
    If adjustedKey < 0 Then
        adjustedKey = 0
    End If
    If adjustedKey > 127 Then
        adjustedKey = 127
    End If
    Return adjustedKey
End Function


Public Function scoreAddTool_DurationName( _
    ByVal durationIndex As Integer _
) As String
    Select Case durationIndex
        Case OSE_SCORE_DURATION_WHOLE
            Return "whole"
        Case OSE_SCORE_DURATION_HALF
            Return "half"
        Case OSE_SCORE_DURATION_QUARTER
            Return "quarter"
        Case OSE_SCORE_DURATION_EIGHTH
            Return "eighth"
        Case OSE_SCORE_DURATION_SIXTEENTH
            Return "sixteenth"
        Case OSE_SCORE_DURATION_THIRTY_SECOND
            Return "thirty-second"
        Case OSE_SCORE_DURATION_SIXTY_FOURTH
            Return "sixty-fourth"
    End Select

    Return "unknown"
End Function

/' end of score_tools.bas '/
