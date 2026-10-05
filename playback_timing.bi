/'
    Project: OpenSesh
    ---------------------------

    File: playback_timing.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: playbackTiming_* elapsed time, note boundaries, and wall-duration calculations.

    Purpose:

        Declare the score-time to wall-time rules used when the software
        synthesizer starts notes during normal and accelerated playback.

    Responsibilities:

        - normalize the platform Timer clock across midnight
        - reject implausible clock jumps after suspend or a stalled update
        - decide whether a note crosses the current playback interval
        - reject notes which have already ended before a delayed update
        - convert remaining score duration into bounded wall-clock duration
        - keep fast-forward timing consistent with the moving playhead

    This file intentionally does NOT contain:

        - MIDI storage or parsing
        - sfxlib commands
        - transport widgets or application state
'/

#ifndef __OSE_PLAYBACK_TIMING_BI__
#define __OSE_PLAYBACK_TIMING_BI__

Declare Function playbackTiming_ElapsedDelta( _
    ByVal previousClock As Double, _
    ByVal currentClock As Double _
) As Double

Declare Function playbackTiming_ShouldStart( _
    ByVal noteStartTick As ULongInt, _
    ByVal noteEndTick As ULongInt, _
    ByVal previousTick As ULongInt, _
    ByVal currentTick As ULongInt, _
    ByVal firstUpdate As Integer _
) As Integer

Declare Function playbackTiming_WallDuration( _
    ByVal noteEndSeconds As Double, _
    ByVal currentSeconds As Double, _
    ByVal playbackSpeed As Double _
) As Double

#endif

/' end of playback_timing.bi '/
