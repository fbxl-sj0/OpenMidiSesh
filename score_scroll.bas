/'
    Project: OpenSesh
    ---------------------------

    File: score_scroll.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements score_scroll.bi; declarations there define the shared interface.

    Purpose:

        Provide deterministic, overflow-safe score scrollbar calculations for
        large MIDI timelines and changing track layouts.

    Responsibilities:

        - keep horizontal values inside the published scrollbar range
        - avoid multiplying a 64-bit tick count by the scrollbar range
        - choose the closest representable scrollbar value for a score tick
        - reject negative and stale vertical track positions

    This file intentionally does NOT contain:

        - application globals
        - widget rendering or pointer input
        - MIDI model access
'/

#lang "fb"

#include once "score_scroll.bi"

' -------------------------------------------------------------------------
' Horizontal score range
' -------------------------------------------------------------------------

Public Function scoreScroll_MaximumStart( _
    ByVal timelineTicks As ULongInt, _
    ByVal viewTicks As ULongInt _
) As ULongInt
    If timelineTicks <= viewTicks Then
        Return 0
    End If
    Return timelineTicks - viewTicks
End Function


Public Function scoreScroll_ClampValue( _
    ByVal requestedValue As Integer, _
    ByVal scrollRange As Integer _
) As Integer
    If scrollRange <= 0 Then
        Return 0
    End If
    If requestedValue < 0 Then
        Return 0
    End If
    If requestedValue > scrollRange Then
        Return scrollRange
    End If
    Return requestedValue
End Function


Public Function scoreScroll_ValueToTick( _
    ByVal maximumStart As ULongInt, _
    ByVal requestedValue As Integer, _
    ByVal scrollRange As Integer _
) As ULongInt
    Dim As Integer scrollValue = _
        scoreScroll_ClampValue(requestedValue, scrollRange)
    If maximumStart = 0 OrElse scrollValue = 0 Then
        Return 0
    End If
    If scrollValue = scrollRange Then
        Return maximumStart
    End If

    /'
        Dividing before multiplying prevents overflow when a legal 64-bit
        timeline is much larger than the scrollbar's fixed 1000 positions.
        The remainder product is bounded by scrollRange squared.
    '/
    Dim As ULongInt unsignedRange = CULngInt(scrollRange)
    Dim As ULongInt unsignedValue = CULngInt(scrollValue)
    Dim As ULongInt wholePart = maximumStart \ unsignedRange
    Dim As ULongInt remainderPart = maximumStart Mod unsignedRange
    Return wholePart * unsignedValue + _
        (remainderPart * unsignedValue) \ unsignedRange
End Function


Public Function scoreScroll_TickToValue( _
    ByVal maximumStart As ULongInt, _
    ByVal requestedTick As ULongInt, _
    ByVal scrollRange As Integer _
) As Integer
    If maximumStart = 0 OrElse scrollRange <= 0 Then
        Return 0
    End If
    If requestedTick >= maximumStart Then
        Return scrollRange
    End If

    /'
        A binary search uses the overflow-safe forward mapping as its source
        of truth. The UI range is 1000, so this takes at most ten probes and
        stays exact even above the 53-bit integer precision of Double.
    '/
    Dim As Integer lowerValue
    Dim As Integer upperValue = scrollRange
    While lowerValue < upperValue
        Dim As Integer middleValue = lowerValue + _
            (upperValue - lowerValue + 1) \ 2
        If scoreScroll_ValueToTick( _
            maximumStart, middleValue, scrollRange) <= requestedTick Then
            lowerValue = middleValue
        Else
            upperValue = middleValue - 1
        End If
    Wend

    If lowerValue >= scrollRange Then
        Return scrollRange
    End If
    Dim As ULongInt lowerTick = scoreScroll_ValueToTick( _
        maximumStart, lowerValue, scrollRange)
    Dim As ULongInt upperTick = scoreScroll_ValueToTick( _
        maximumStart, lowerValue + 1, scrollRange)
    If upperTick - requestedTick < requestedTick - lowerTick Then
        lowerValue += 1
    End If
    Return lowerValue
End Function

' -------------------------------------------------------------------------
' Vertical track range
' -------------------------------------------------------------------------

Public Function scoreScroll_MaximumFirstTrack( _
    ByVal trackCount As Integer, _
    ByVal visibleTrackCount As Integer _
) As Integer
    If trackCount <= 0 Then
        Return 0
    End If
    If visibleTrackCount <= 0 Then
        Return trackCount - 1
    End If
    If trackCount <= visibleTrackCount Then
        Return 0
    End If
    Return trackCount - visibleTrackCount
End Function


Public Function scoreScroll_ClampFirstTrack( _
    ByVal requestedTrack As Integer, _
    ByVal maximumFirstTrack As Integer _
) As Integer
    If maximumFirstTrack <= 0 OrElse requestedTrack < 0 Then
        Return 0
    End If
    If requestedTrack > maximumFirstTrack Then
        Return maximumFirstTrack
    End If
    Return requestedTrack
End Function

/' end of score_scroll.bas '/
