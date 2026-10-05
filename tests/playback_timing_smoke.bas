/'
    Project: OpenSesh
    ---------------------------

    File: tests/playback_timing_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove that note scheduling follows the transport clock instead of
        replaying stale notes or leaving normal-speed voices during fast play.

    Responsibilities:

        - simulate twelve-hour normal and fast transports across midnight
        - prove long-run note boundaries are neither skipped nor repeated
        - bound accumulated transport drift over millions of display frames
        - verify first-frame, normal-frame, and exact-boundary note starts
        - reject notes which ended before the current update
        - verify remaining-duration and fast-forward conversion
        - exercise invalid duration and speed limits

    This file intentionally does NOT contain:

        - an audio device
        - a MIDI parser
        - graphical transport input
'/

#lang "fb"

#include once "../playback_timing.bi"

Const TEST_SECONDS_PER_DAY As Double = 86400.0
Const TEST_FRAME_SECONDS As Double = 1.0 / 60.0
Const TEST_TICKS_PER_SECOND As Double = 960.0
Const TEST_WALL_HOURS As Integer = 12
Const TEST_FRAME_COUNT As Integer = TEST_WALL_HOURS * 60 * 60 * 60
Const TEST_NOTE_SPACING_TICKS As ULongInt = 120
Const TEST_NOTE_DURATION_TICKS As ULongInt = 96

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Function test_Close( _
    ByVal actualValue As Double, _
    ByVal expectedValue As Double _
) As Integer
    Return IIf(Abs(actualValue - expectedValue) <= 0.000001, -1, 0)
End Function


Private Sub test_LongTransport(ByVal playbackSpeed As Double)
    ' Start at 23:00 so every run proves the seconds-since-midnight wrap. The
    ' 60 Hz loop represents a real long session but completes without waiting.
    Dim As Double currentClock = 23.0 * 60.0 * 60.0
    Dim As Double previousClock = currentClock
    Dim As Double elapsedSeconds
    ' ULongInt is the fixed 64-bit type used by production MIDI tick APIs.
    ' fblint: disable-next-line FBL423 REASON: ULongInt matches the production MIDI API fixed 64-bit tick/count domain.
    Dim As ULongInt previousTick
    ' fblint: disable-next-line FBL423 REASON: ULongInt matches the production MIDI API fixed 64-bit tick/count domain.
    Dim As ULongInt nextNoteTick
    ' fblint: disable-next-line FBL423 REASON: ULongInt matches the production MIDI API fixed 64-bit tick/count domain.
    Dim As ULongInt scheduledNotes

    If playbackTiming_ShouldStart(0, TEST_NOTE_DURATION_TICKS, _
        0, 0, -1) = 0 Then _
        test_Fail "long transport did not start its tick-zero note"
    scheduledNotes = 1
    nextNoteTick = TEST_NOTE_SPACING_TICKS

    For frameIndex As Integer = 1 To TEST_FRAME_COUNT
        currentClock += TEST_FRAME_SECONDS
        If currentClock >= TEST_SECONDS_PER_DAY Then _
            currentClock -= TEST_SECONDS_PER_DAY

        Dim As Double elapsedDelta = playbackTiming_ElapsedDelta( _
            previousClock, currentClock)
        If Abs(elapsedDelta - TEST_FRAME_SECONDS) > 0.0000001 Then _
            test_Fail "long transport clock delta drifted or stopped"
        elapsedSeconds += elapsedDelta * playbackSpeed

        ' fblint: disable-next-line FBL423 REASON: ULongInt matches the production MIDI API fixed 64-bit tick/count domain.
        Dim As ULongInt currentTick = CULngInt(Int( _
            elapsedSeconds * TEST_TICKS_PER_SECOND + 0.000001))
        If currentTick < previousTick Then _
            test_Fail "long transport tick moved backwards"

        While nextNoteTick <= currentTick
            If playbackTiming_ShouldStart(nextNoteTick, _
                nextNoteTick + TEST_NOTE_DURATION_TICKS, previousTick, _
                currentTick, 0) = 0 Then _
                test_Fail "long transport skipped an active note boundary"
            scheduledNotes += 1
            nextNoteTick += TEST_NOTE_SPACING_TICKS
        Wend

        If playbackTiming_ShouldStart(nextNoteTick, _
            nextNoteTick + TEST_NOTE_DURATION_TICKS, previousTick, _
            currentTick, 0) <> 0 Then _
            test_Fail "long transport started a future note"
        If playbackTiming_ShouldStart(previousTick, _
            previousTick + TEST_NOTE_DURATION_TICKS, previousTick, _
            currentTick, 0) <> 0 Then _
            test_Fail "long transport repeated a previous boundary"

        previousTick = currentTick
        previousClock = currentClock
    Next

    Dim As Double expectedSeconds = _
        CDbl(TEST_WALL_HOURS * 60 * 60) * playbackSpeed
    If Abs(elapsedSeconds - expectedSeconds) > 0.001 Then _
        test_Fail "multi-hour transport accumulated excessive time drift"

    ' fblint: disable-next-line FBL423 REASON: ULongInt matches the production MIDI API fixed 64-bit tick/count domain.
    Dim As ULongInt expectedTick = CULngInt(Int( _
        expectedSeconds * TEST_TICKS_PER_SECOND + 0.000001))
    ' fblint: disable-next-line FBL423 REASON: ULongInt matches the production MIDI API fixed 64-bit tick/count domain.
    Dim As ULongInt expectedNotes = _
        previousTick \ TEST_NOTE_SPACING_TICKS + 1
    ' Repeated binary fractions can finish infinitesimally below an exact tick
    ' boundary. One tick of quantization is acceptable only when the separately
    ' checked accumulated clock error remains below one millisecond.
    If previousTick > expectedTick OrElse _
        expectedTick - previousTick > 1 OrElse _
        scheduledNotes <> expectedNotes Then _
        test_Fail "multi-hour transport lost a tick or note boundary"
End Sub


If Not test_Close(playbackTiming_ElapsedDelta(10.0, 10.25), 0.25) Then _
    test_Fail "ordinary playback clock delta was wrong"
If Not test_Close(playbackTiming_ElapsedDelta(1700000.0, 1700000.25), _
    0.25) Then test_Fail "monotonic playback clock delta was wrong"
If Not test_Close(playbackTiming_ElapsedDelta(86399.9, 0.1), 0.2) Then _
    test_Fail "midnight playback clock wrap was wrong"
If playbackTiming_ElapsedDelta(10.0, 12.0001) <> 0.0 Then _
    test_Fail "an excessive playback clock stall advanced transport"
If playbackTiming_ElapsedDelta(-1.0, 0.0) <> 0.0 OrElse _
    playbackTiming_ElapsedDelta(1700000.0, 1699999.0) <> 0.0 Then _
    test_Fail "an invalid platform clock value advanced transport"

If playbackTiming_ShouldStart(0, 480, 0, 0, -1) = 0 Then _
    test_Fail "a tick-zero note did not start on the first update"
If playbackTiming_ShouldStart(120, 480, 0, 120, 0) = 0 Then _
    test_Fail "a note at the inclusive current boundary did not start"
If playbackTiming_ShouldStart(120, 480, 120, 240, 0) <> 0 Then _
    test_Fail "a note at the exclusive previous boundary started twice"
If playbackTiming_ShouldStart(0, 120, 0, 120, -1) <> 0 Then _
    test_Fail "a note which had already ended was replayed"
If playbackTiming_ShouldStart(0, 480, 0, 240, -1) = 0 Then _
    test_Fail "an active note was not restored during a first update"
If playbackTiming_ShouldStart(300, 240, 0, 240, 0) <> 0 Then _
    test_Fail "an invalid backwards note duration was accepted"
If playbackTiming_ShouldStart(120, 480, 300, 200, 0) <> 0 Then _
    test_Fail "a backwards playback interval was accepted"

If Not test_Close(playbackTiming_WallDuration(2.0, 0.5, 1.0), 1.5) Then _
    test_Fail "remaining normal-speed duration was wrong"
If Not test_Close(playbackTiming_WallDuration(2.0, 0.0, 4.0), 0.5) Then _
    test_Fail "fast-forward duration did not follow the score clock"
If Not test_Close(playbackTiming_WallDuration(0.5, 0.5, 1.0), 0.0) Then _
    test_Fail "an ended note retained a wall duration"
If Not test_Close(playbackTiming_WallDuration(100.0, 0.0, 1.0), 100.0) Then _
    test_Fail "long score notes were shortened to an audition duration"
If Not test_Close(playbackTiming_WallDuration(7200.0, 0.0, 1.0), 3600.0) Then _
    test_Fail "maximum voice duration was not bounded"
If Not test_Close(playbackTiming_WallDuration(0.001, 0.0, 1.0), 0.025) Then _
    test_Fail "minimum audible voice duration was not bounded"
If Not test_Close(playbackTiming_WallDuration(1.0, 0.0, 0.0), 8.0) Then _
    test_Fail "invalid playback speed was not bounded"

' Construct non-finite IEEE-754 values without a divide-by-zero operation.
Dim As Double quietNan = CvD(MkLongInt(&H7FF8000000000000))
Dim As Double positiveInfinity = CvD(MkLongInt(&H7FF0000000000000))
If playbackTiming_ElapsedDelta(positiveInfinity, positiveInfinity) <> 0.0 OrElse _
    playbackTiming_ElapsedDelta(quietNan, 1.0) <> 0.0 OrElse _
    playbackTiming_WallDuration(quietNan, 0.0, 1.0) <> 0.0 OrElse _
    playbackTiming_WallDuration(1.0, quietNan, 1.0) <> 0.0 OrElse _
    playbackTiming_WallDuration(1.0, 0.0, quietNan) <> 0.0 Then _
    test_Fail "invalid floating values escaped the timing boundary"

test_LongTransport 1.0
test_LongTransport 4.0

Print "playback_timing=ok"
Print "fast_note_seconds="; playbackTiming_WallDuration(2.0, 0.0, 4.0)
Print "long_transport_wall_hours="; TEST_WALL_HOURS; " speeds=1,4"
End 0

/' end of tests/playback_timing_smoke.bas '/
