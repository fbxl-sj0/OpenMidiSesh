/'
    Project: OpenSesh
    ---------------------------

    File: playback_timing.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements playback_timing.bi; declarations there define the shared interface.

    Purpose:

        Keep software-synth note starts and durations synchronized with the
        score clock, including delayed updates and fast-forward playback.

    Responsibilities:

        - normalize the seconds-since-midnight clock used by FreeBASIC Timer
        - reject invalid or disruptive clock jumps without advancing transport
        - apply explicit inclusive and exclusive tick boundaries
        - prevent completed notes from being replayed after a delayed frame
        - use only the note's remaining score time when starting it late
        - bound sfxlib note duration to practical, supported values

    This file intentionally does NOT contain:

        - transport state mutation
        - MIDI event enumeration
        - audio device access
'/

#lang "fb"

#include once "playback_timing.bi"

Const OSE_PLAYBACK_MINIMUM_NOTE_SECONDS As Double = 0.025
' Match the synth adapters' one-hour voice bound. Long score notes must not
' inherit the old eight-second audition limit; stop still releases them early.
Const OSE_PLAYBACK_MAXIMUM_NOTE_SECONDS As Double = 3600.0
Const OSE_PLAYBACK_MINIMUM_SPEED As Double = 0.125
Const OSE_PLAYBACK_MAXIMUM_SPEED As Double = 16.0
Const OSE_PLAYBACK_CLOCK_SECONDS_PER_DAY As Double = 86400.0
Const OSE_PLAYBACK_MAXIMUM_CLOCK_DELTA As Double = 2.0

' -------------------------------------------------------------------------
' Monotonic transport delta from the platform wall clock
' -------------------------------------------------------------------------

Public Function playbackTiming_ElapsedDelta( _
    ByVal previousClock As Double, _
    ByVal currentClock As Double _
) As Double
    ' Supported FreeBASIC runtimes expose Timer either as seconds since local
    ' midnight or as an arbitrary nonnegative monotonic count. Values which are
    ' invalid, including NaN, must not poison the accumulated transport time. A
    ' long stall is treated like suspend: the editor resumes in place instead
    ' of skipping unplayed material.
    If previousClock <> previousClock OrElse currentClock <> currentClock Then
        Return 0.0
    End If
    If previousClock < 0.0 OrElse currentClock < 0.0 Then
        Return 0.0
    End If

    Dim As Double elapsedDelta = currentClock - previousClock
    If elapsedDelta <> elapsedDelta Then
        Return 0.0
    End If
    If elapsedDelta < 0.0 AndAlso _
        previousClock < OSE_PLAYBACK_CLOCK_SECONDS_PER_DAY AndAlso _
        currentClock < OSE_PLAYBACK_CLOCK_SECONDS_PER_DAY Then
        elapsedDelta += OSE_PLAYBACK_CLOCK_SECONDS_PER_DAY
    End If
    If elapsedDelta < 0.0 OrElse _
        elapsedDelta > OSE_PLAYBACK_MAXIMUM_CLOCK_DELTA Then
        Return 0.0
    End If
    Return elapsedDelta
End Function

' -------------------------------------------------------------------------
' Playback interval selection
' -------------------------------------------------------------------------

Public Function playbackTiming_ShouldStart( _
    ByVal noteStartTick As ULongInt, _
    ByVal noteEndTick As ULongInt, _
    ByVal previousTick As ULongInt, _
    ByVal currentTick As ULongInt, _
    ByVal firstUpdate As Integer _
) As Integer
    If noteEndTick <= noteStartTick Then
        Return 0
    End If
    If noteEndTick <= currentTick Then
        Return 0
    End If

    If firstUpdate <> 0 Then
        Return IIf(noteStartTick <= currentTick, -1, 0)
    End If

    If currentTick < previousTick Then
        Return 0
    End If
    Return IIf(noteStartTick > previousTick AndAlso _
        noteStartTick <= currentTick, -1, 0)
End Function

' -------------------------------------------------------------------------
' Score duration to wall duration
' -------------------------------------------------------------------------

Public Function playbackTiming_WallDuration( _
    ByVal noteEndSeconds As Double, _
    ByVal currentSeconds As Double, _
    ByVal playbackSpeed As Double _
) As Double
    If noteEndSeconds <> noteEndSeconds OrElse currentSeconds <> currentSeconds _
        OrElse playbackSpeed <> playbackSpeed Then
        Return 0.0
    End If
    If noteEndSeconds <= currentSeconds Then
        Return 0.0
    End If

    If playbackSpeed < OSE_PLAYBACK_MINIMUM_SPEED Then
        playbackSpeed = OSE_PLAYBACK_MINIMUM_SPEED
    End If
    If playbackSpeed > OSE_PLAYBACK_MAXIMUM_SPEED Then
        playbackSpeed = OSE_PLAYBACK_MAXIMUM_SPEED
    End If

    Dim As Double wallDuration = _
        (noteEndSeconds - currentSeconds) / playbackSpeed
    If wallDuration < OSE_PLAYBACK_MINIMUM_NOTE_SECONDS Then
        wallDuration = OSE_PLAYBACK_MINIMUM_NOTE_SECONDS
    End If
    If wallDuration > OSE_PLAYBACK_MAXIMUM_NOTE_SECONDS Then
        wallDuration = OSE_PLAYBACK_MAXIMUM_NOTE_SECONDS
    End If
    Return wallDuration
End Function

/' end of playback_timing.bas '/
