/'
    Project: OpenSesh
    ---------------------------

    File: tests/mixer_state_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove the behavior promised by every Mute, Solo, and Record button on
        all sixteen mixer channel strips.

    Responsibilities:

        - toggle Mute on and off for every channel
        - verify single and multiple Solo audibility rules
        - verify Mute overrides Solo
        - verify Record is exclusive and can be disarmed on every channel

    This file intentionally does NOT contain:

        - mixer coordinates
        - audio or MIDI output
        - step-note insertion
'/

#lang "fb"

#include once "../mixer_state.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Dim As OseMixerChannelState state
mixerState_Initialize state
If mixerState_HasSolo(state) <> 0 Then _
    test_Fail "initialized mixer reported an active Solo"
For channelIndex As Integer = 0 To OSE_MIXER_CHANNEL_COUNT - 1
    If mixerState_IsAudible(state, channelIndex) = 0 Then _
        test_Fail "initialized channel was not audible"
    If mixerState_ToggleMute(state, channelIndex) = 0 OrElse _
        mixerState_IsAudible(state, channelIndex) <> 0 Then _
        test_Fail "Mute did not silence channel " + Str(channelIndex)
    If mixerState_ToggleMute(state, channelIndex) <> 0 OrElse _
        mixerState_IsAudible(state, channelIndex) = 0 Then _
        test_Fail "Mute did not restore channel " + Str(channelIndex)
Next

If mixerState_ToggleSolo(state, 3) = 0 Then
    test_Fail "Solo did not engage"
End If
If mixerState_HasSolo(state) = 0 Then
    test_Fail "active Solo was not reported"
End If
For channelIndex As Integer = 0 To OSE_MIXER_CHANNEL_COUNT - 1
    Dim As Integer expectedAudible = IIf(channelIndex = 3, -1, 0)
    If mixerState_IsAudible(state, channelIndex) <> expectedAudible Then _
        test_Fail "single-Solo audibility was wrong"
Next
If mixerState_ToggleSolo(state, 5) = 0 OrElse _
    mixerState_IsAudible(state, 3) = 0 OrElse _
    mixerState_IsAudible(state, 5) = 0 Then _
    test_Fail "multiple Solo buttons did not remain audible"
If mixerState_ToggleMute(state, 3) = 0 OrElse _
    mixerState_IsAudible(state, 3) <> 0 OrElse _
    mixerState_IsAudible(state, 5) = 0 Then _
    test_Fail "Mute did not override Solo"

mixerState_Initialize state
For channelIndex As Integer = 0 To OSE_MIXER_CHANNEL_COUNT - 1
    If mixerState_ToggleRecord(state, channelIndex) = 0 OrElse _
        mixerState_RecordChannel(state) <> channelIndex Then _
        test_Fail "Record did not arm channel " + Str(channelIndex)
    For otherChannel As Integer = 0 To OSE_MIXER_CHANNEL_COUNT - 1
        Dim As Integer expectedState = IIf(otherChannel = channelIndex, -1, 0)
        If state.record(otherChannel) <> expectedState Then _
            test_Fail "Record was not exclusive"
    Next
    If mixerState_ToggleRecord(state, channelIndex) <> 0 OrElse _
        mixerState_RecordChannel(state) <> -1 Then _
        test_Fail "Record did not disarm channel " + Str(channelIndex)
Next

If mixerState_ToggleMute(state, -1) <> 0 OrElse _
    mixerState_ToggleSolo(state, OSE_MIXER_CHANNEL_COUNT) <> 0 OrElse _
    mixerState_ToggleRecord(state, OSE_MIXER_CHANNEL_COUNT) <> 0 OrElse _
    mixerState_IsAudible(state, -1) <> 0 Then _
    test_Fail "invalid channel index changed mixer state"

Print "mixer_state=ok"
Print "button_behaviors="; OSE_MIXER_CHANNEL_COUNT * 3
End 0

/' end of tests/mixer_state_smoke.bas '/
