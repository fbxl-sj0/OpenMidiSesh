/'
    Project: OpenSesh
    ---------------------------

    File: score_scroll.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: scoreScroll_* clamping and tick/scrollbar conversion.

    Purpose:

        Declare the bounded mapping between score positions and the omaGUI
        horizontal and vertical scrollbar values.

    Responsibilities:

        - calculate the last valid horizontal score start
        - map scrollbar values to 64-bit MIDI ticks without overflow
        - map MIDI ticks back to the closest scrollbar value
        - clamp the first visible track after document or viewport changes

    This file intentionally does NOT contain:

        - omaGUI widget access
        - score rendering
        - document or track selection mutation
'/

#ifndef __OSE_SCORE_SCROLL_BI__
#define __OSE_SCORE_SCROLL_BI__

Declare Function scoreScroll_MaximumStart( _
    ByVal timelineTicks As ULongInt, _
    ByVal viewTicks As ULongInt _
) As ULongInt

Declare Function scoreScroll_ClampValue( _
    ByVal requestedValue As Integer, _
    ByVal scrollRange As Integer _
) As Integer

Declare Function scoreScroll_ValueToTick( _
    ByVal maximumStart As ULongInt, _
    ByVal requestedValue As Integer, _
    ByVal scrollRange As Integer _
) As ULongInt

Declare Function scoreScroll_TickToValue( _
    ByVal maximumStart As ULongInt, _
    ByVal requestedTick As ULongInt, _
    ByVal scrollRange As Integer _
) As Integer

Declare Function scoreScroll_MaximumFirstTrack( _
    ByVal trackCount As Integer, _
    ByVal visibleTrackCount As Integer _
) As Integer

Declare Function scoreScroll_ClampFirstTrack( _
    ByVal requestedTrack As Integer, _
    ByVal maximumFirstTrack As Integer _
) As Integer

#endif

/' end of score_scroll.bi '/
