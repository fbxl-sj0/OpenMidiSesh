/'
    Project: OpenSesh
    ---------------------------

    File: tests/score_scroll_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove the behavior of both visible score scrollbars across ordinary,
        resized, empty, and very large documents.

    Responsibilities:

        - verify horizontal endpoints, clamping, and monotonic mapping
        - exercise a timeline larger than Double's exact integer range
        - verify the closest scrollbar value is selected on reverse mapping
        - clamp vertical positions when tracks or the viewport change

    This file intentionally does NOT contain:

        - omaGUI widgets
        - score drawing
        - pointer automation
'/

#lang "fb"

#include once "../src/score_scroll.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Const TEST_SCROLL_RANGE As Integer = 1000

If scoreScroll_MaximumStart(480, 960) <> 0 Then _
    test_Fail "a short score retained a horizontal range"
If scoreScroll_MaximumStart(1920, 480) <> 1440 Then _
    test_Fail "the horizontal maximum start was wrong"
If scoreScroll_ClampValue(-1, TEST_SCROLL_RANGE) <> 0 OrElse _
    scoreScroll_ClampValue(1001, TEST_SCROLL_RANGE) <> TEST_SCROLL_RANGE Then _
    test_Fail "horizontal values were not clamped"

Dim As ULongInt maximumStart = 9876543210ull
If scoreScroll_ValueToTick(maximumStart, 0, TEST_SCROLL_RANGE) <> 0 Then _
    test_Fail "the horizontal origin did not map to tick zero"
If scoreScroll_ValueToTick( _
    maximumStart, TEST_SCROLL_RANGE, TEST_SCROLL_RANGE) <> maximumStart Then _
    test_Fail "the horizontal endpoint did not map to the last score start"

Dim As ULongInt previousTick
For scrollValue As Integer = 0 To TEST_SCROLL_RANGE
    Dim As ULongInt mappedTick = scoreScroll_ValueToTick( _
        maximumStart, scrollValue, TEST_SCROLL_RANGE)
    If mappedTick < previousTick Then _
        test_Fail "horizontal mapping moved backwards"
    If scoreScroll_TickToValue( _
        maximumStart, mappedTick, TEST_SCROLL_RANGE) <> scrollValue Then _
        test_Fail "horizontal round trip selected the wrong value"
    previousTick = mappedTick
Next

' This value is deliberately above Double's exact integer range. The forward
' mapping must still reach the exact 64-bit endpoint without multiplication
' overflow or floating-point truncation.
Dim As ULongInt hugeMaximum = CULngInt(-1) - 4096
If scoreScroll_ValueToTick( _
    hugeMaximum, TEST_SCROLL_RANGE, TEST_SCROLL_RANGE) <> hugeMaximum Then _
    test_Fail "a huge timeline lost its exact endpoint"
If scoreScroll_TickToValue( _
    hugeMaximum, hugeMaximum, TEST_SCROLL_RANGE) <> TEST_SCROLL_RANGE Then _
    test_Fail "a huge timeline did not reverse-map its endpoint"

If scoreScroll_MaximumFirstTrack(16, 5) <> 11 Then _
    test_Fail "the vertical maximum was wrong"
If scoreScroll_MaximumFirstTrack(3, 5) <> 0 Then _
    test_Fail "a fully visible document retained a vertical range"
If scoreScroll_MaximumFirstTrack(0, 0) <> 0 Then _
    test_Fail "an empty document retained a vertical range"
If scoreScroll_ClampFirstTrack(12, 11) <> 11 Then _
    test_Fail "a stale vertical position survived a track-count shrink"
If scoreScroll_ClampFirstTrack(-1, 11) <> 0 Then _
    test_Fail "a negative vertical position was accepted"

Print "score_scroll=ok"
Print "horizontal_positions=1001 vertical_resize_cases=5"
End 0

/' end of tests/score_scroll_smoke.bas '/
