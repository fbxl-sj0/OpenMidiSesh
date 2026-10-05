/'
    Project: OpenSesh
    ---------------------------

    File: tests/playback_state_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify the channel automation state consumed by software playback.

    Responsibilities:

        - check all General MIDI defaults on every channel
        - apply bank, volume, expression, pan, program, and pitch-bend events
        - prove unsupported events leave retained state unchanged

    This file intentionally does NOT contain:

        - MIDI file parsing
        - audio output
        - event sorting
'/

#lang "fb"

#include once "../playback_state.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Dim As OsePlaybackChannelState state
playbackState_Initialize state
For channelIndex As Integer = 0 To OSE_PLAYBACK_CHANNEL_COUNT - 1
    If state.programNumber(channelIndex) <> 0 OrElse _
        playbackState_BankNumber(state, channelIndex) <> 0 OrElse _
        state.controllerVolume(channelIndex) <> 127 OrElse _
        state.controllerExpression(channelIndex) <> 127 OrElse _
        state.controllerPan(channelIndex) <> 64 OrElse _
        state.pitchBend(channelIndex) <> 8192 Then _
        test_Fail "channel defaults are incorrect"
Next

Dim As MidiChannelEventPoint channelEvent
channelEvent.channel = 3
channelEvent.messageType = &HB0
channelEvent.data1 = 0
channelEvent.data2 = 2
If Not playbackState_Apply(state, channelEvent) Then _
    test_Fail "CC0 bank-select MSB was not applied"
channelEvent.data1 = 32
channelEvent.data2 = 9
If Not playbackState_Apply(state, channelEvent) OrElse _
    playbackState_BankNumber(state, 3) <> 265 Then _
    test_Fail "CC32 bank-select LSB was not applied"

channelEvent.data1 = 7
channelEvent.data2 = 81
If Not playbackState_Apply(state, channelEvent) OrElse _
    state.controllerVolume(3) <> 81 Then _
    test_Fail "CC7 volume was not applied"

channelEvent.data1 = 10
channelEvent.data2 = 19
If Not playbackState_Apply(state, channelEvent) OrElse _
    state.controllerPan(3) <> 19 Then _
    test_Fail "CC10 pan was not applied"
channelEvent.data1 = 11
channelEvent.data2 = 62
If Not playbackState_Apply(state, channelEvent) OrElse _
    state.controllerExpression(3) <> 62 Then _
    test_Fail "CC11 expression was not applied"

channelEvent.messageType = &HC0
channelEvent.data1 = 73
If Not playbackState_Apply(state, channelEvent) OrElse _
    state.programNumber(3) <> 73 Then _
    test_Fail "program change was not applied"

channelEvent.messageType = &HE0
channelEvent.data1 = 1
channelEvent.data2 = 65
If Not playbackState_Apply(state, channelEvent) OrElse _
    state.pitchBend(3) <> 8321 Then _
    test_Fail "pitch bend was not assembled from fourteen bits"

Dim As OsePlaybackChannelState retainedState = state
channelEvent.messageType = &HB0
channelEvent.data1 = 91
channelEvent.data2 = 127
If playbackState_Apply(state, channelEvent) OrElse _
    state.controllerVolume(3) <> retainedState.controllerVolume(3) OrElse _
    state.controllerExpression(3) <> retainedState.controllerExpression(3) _
    Then test_Fail "unsupported controller changed playback state"

Print "playback_state=ok"
Print "bank=265 volume=81 expression=62 pan=19 program=73 bend=8321"
End 0

/' end of tests/playback_state_smoke.bas '/
