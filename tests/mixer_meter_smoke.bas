/'
    Project: OpenSesh
    ---------------------------

    File: tests/mixer_meter_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify that VU meters follow scheduled sound activity instead of
        displaying static fader-derived mock levels.

    Responsibilities:

        - prove idle meters remain at zero regardless of fader position
        - verify note attack, duration, and release behavior
        - verify mute, pause, pan, and master volume affect displayed levels
        - verify invalid channels and values are bounded safely

    This file intentionally does NOT contain:

        - graphical pixel assertions
        - sfxlib playback or audio-device assumptions
        - score scheduling
'/

#lang "fb"

#include once "../src/mixer_meter.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "ERROR: "; messageText
    End 1
End Sub


Dim As OseMixerMeterState meterState
mixerMeter_Initialize meterState
mixerMeter_SetChannelMix meterState, 0, 0.82, 0.0, -1
mixerMeter_SetMasterVolume meterState, 0.75
mixerMeter_Update meterState, 0.01, 0
If Abs(mixerMeter_ChannelLevel(meterState, 0)) > 0.0001 OrElse _
    Abs(mixerMeter_MasterLeftLevel(meterState)) > 0.0001 OrElse _
    Abs(mixerMeter_MasterRightLevel(meterState)) > 0.0001 Then _
    test_Fail "idle fader position produced fake meter activity"

If Not mixerMeter_Trigger(meterState, 0, 1.0, 0.20) Then _
    test_Fail "valid sound activity was rejected"
mixerMeter_Update meterState, 0.01, 0
If mixerMeter_ChannelLevel(meterState, 0) < 0.81 OrElse _
    mixerMeter_MasterLeftLevel(meterState) < 0.60 OrElse _
    mixerMeter_MasterRightLevel(meterState) < 0.60 Then _
    test_Fail "sound activity did not drive channel and master meters"

mixerMeter_SetChannelMix meterState, 0, 0.82, -1.0, -1
mixerMeter_Update meterState, 0.01, 0
If mixerMeter_MasterLeftLevel(meterState) <= 0.0 OrElse _
    Abs(mixerMeter_MasterRightLevel(meterState)) > 0.0001 Then _
    test_Fail "hard-left pan did not separate master meters"

mixerMeter_Update meterState, 0.10, -1
If mixerMeter_ChannelLevel(meterState, 0) <= 0.0 Then _
    test_Fail "pause discarded retained source activity"
mixerMeter_SetChannelMix meterState, 0, 0.82, 0.0, 0
mixerMeter_Update meterState, 0.10, 0
If mixerMeter_ChannelLevel(meterState, 0) >= 0.82 Then _
    test_Fail "inaudible channel did not begin meter release"

mixerMeter_StopAll meterState
For releaseStep As Integer = 0 To 5
    mixerMeter_Update meterState, 0.10, 0
Next
If Abs(mixerMeter_ChannelLevel(meterState, 0)) > 0.0001 OrElse _
    Abs(mixerMeter_MasterLeftLevel(meterState)) > 0.0001 OrElse _
    Abs(mixerMeter_MasterRightLevel(meterState)) > 0.0001 Then _
    test_Fail "stopped activity did not release to zero"

If mixerMeter_Trigger(meterState, -1, 1.0, 1.0) <> 0 OrElse _
    mixerMeter_Trigger(meterState, 16, 1.0, 1.0) <> 0 OrElse _
    mixerMeter_Trigger(meterState, 0, 0.0, 1.0) <> 0 OrElse _
    mixerMeter_Trigger(meterState, 0, 1.0, 0.0) <> 0 Then _
    test_Fail "invalid meter activity was accepted"

mixerMeter_Initialize meterState
mixerMeter_SetChannelMix meterState, 0, 1.0, 0.0, -1
mixerMeter_SetChannelMix meterState, 1, 1.0, 0.0, -1
' fblint: disable-next-line FBL407,FBL-NUM-013 REASON: integer return values are tested; Real arguments are not compared.
If mixerMeter_Trigger(meterState, 0, 1.0, 2.0) = 0 OrElse _
    mixerMeter_Trigger(meterState, 1, 0.8, 2.0) = 0 Then _
    test_Fail "per-channel stop fixture could not be triggered"
mixerMeter_Update meterState, 0.01, 0
mixerMeter_StopChannel meterState, 0
mixerMeter_StopChannel meterState, -1
For releaseStep As Integer = 0 To 1
    mixerMeter_Update meterState, 0.25, 0
Next
If Abs(mixerMeter_ChannelLevel(meterState, 0)) > 0.0001 OrElse _
    mixerMeter_ChannelLevel(meterState, 1) <= 0.0 Then _
    test_Fail "per-channel stop changed the wrong meter"

Print "mixer_meter=ok"
Print "idle_level=0"
End 0

/' end of mixer_meter_smoke.bas '/
