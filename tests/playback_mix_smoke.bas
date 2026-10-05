/'
    Project: OpenSesh
    ---------------------------

    File: tests/playback_mix_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove that software playback applies MIDI channel gain exactly once.

    Responsibilities:

        - check independent velocity and controller gain stages
        - exercise expression, master volume, pan, mute, and input clamping
        - guard against the former channel-volume-squared playback defect

    This file intentionally does NOT contain:

        - audio device access
        - MIDI parsing
        - graphical mixer interaction
'/

#lang "fb"

#include once "../src/playback_mix.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Function test_Close( _
    ByVal actualValue As Single, _
    ByVal expectedValue As Single _
) As Integer
    Return IIf(Abs(actualValue - expectedValue) <= 0.0001, -1, 0)
End Function


Dim As OsePlaybackMixValues values
playbackMix_Calculate values, 64, 127, 64, 64, 0.8, -1

Dim As Single expectedController = 64.0 / 127.0
Dim As Single expectedVelocity = (64.0 / 127.0) * _
    OSE_PLAYBACK_VOICE_HEADROOM
If Not test_Close(values.meterGain, expectedController) Then _
    test_Fail "CC7 was not represented once in the meter gain"
If Not test_Close(values.channelGain, expectedController * 0.8) Then _
    test_Fail "channel gain did not combine CC7 and master once"
If Not test_Close(values.voiceGain, expectedVelocity) Then _
    test_Fail "CC7 leaked into the per-note velocity gain"
If Not test_Close(values.pan, 0.0) Then _
    test_Fail "center pan did not map to zero"

' Multiplying the two published stages is the final effective note gain.
' The old implementation included CC7 in both stages and produced about half
' this level for a controller value of 64.
Dim As Single expectedEffective = expectedController * 0.8 * _
    expectedVelocity
If Not test_Close(values.channelGain * values.voiceGain, _
    expectedEffective) Then _
    test_Fail "effective gain applied a controller more than once"

playbackMix_Calculate values, 127, 64, 0, 127, 2.0, -1
If Not test_Close(values.channelGain, 64.0 / 127.0) Then _
    test_Fail "expression or master clamping produced the wrong channel gain"
If Not test_Close(values.pan, -1.0) Then _
    test_Fail "hard-left pan was not clamped"

playbackMix_Calculate values, 300, 300, 300, 300, 1.0, -1
If Not test_Close(values.channelGain, 1.0) OrElse _
    Not test_Close(values.voiceGain, OSE_PLAYBACK_VOICE_HEADROOM) OrElse _
    Not test_Close(values.pan, 1.0) Then _
    test_Fail "values above MIDI range were not clamped"

playbackMix_Calculate values, 127, 127, 64, 127, 1.0, 0
If Not test_Close(values.channelGain, 0.0) OrElse _
    Not test_Close(values.meterGain, 0.0) OrElse _
    Not test_Close(values.voiceGain, 0.0) Then _
    test_Fail "inaudible channel retained a nonzero gain"

Print "playback_mix_smoke: effective_gain="; _
    expectedEffective; " pan="; values.pan
End 0

/' end of tests/playback_mix_smoke.bas '/
