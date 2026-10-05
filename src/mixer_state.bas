/'
    Project: OpenSesh
    ---------------------------

    File: mixer_state.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements mixer_state.bi; declarations there define the shared interface.

    Purpose:

        Implement predictable mixer-button behavior independently from the
        graphical editor and audio engine.

    Responsibilities:

        - validate every channel index before accessing state arrays
        - retain independent Mute and Solo selections
        - make Record exclusive and allow the armed channel to be disarmed
        - give Mute priority when resolving a soloed channel

    This file intentionally does NOT contain:

        - user-facing status text
        - MIDI output resynchronization
        - mixer rendering or metering
'/

#lang "fb"

#include once "mixer_state.bi"

' -------------------------------------------------------------------------
' State lifecycle
' -------------------------------------------------------------------------

Public Sub mixerState_Initialize(ByRef state As OseMixerChannelState)
    For channelIndex As Integer = 0 To OSE_MIXER_CHANNEL_COUNT - 1
        state.mute(channelIndex) = 0
        state.solo(channelIndex) = 0
        state.record(channelIndex) = 0
    Next
End Sub

' -------------------------------------------------------------------------
' Button actions
' -------------------------------------------------------------------------

Public Function mixerState_ToggleMute( _
    ByRef state As OseMixerChannelState, _
    ByVal channelIndex As Integer _
) As Integer
    If channelIndex < 0 OrElse channelIndex >= OSE_MIXER_CHANNEL_COUNT Then
        Return 0
    End If
    state.mute(channelIndex) = IIf(state.mute(channelIndex) = 0, -1, 0)
    Return state.mute(channelIndex)
End Function


Public Function mixerState_ToggleSolo( _
    ByRef state As OseMixerChannelState, _
    ByVal channelIndex As Integer _
) As Integer
    If channelIndex < 0 OrElse channelIndex >= OSE_MIXER_CHANNEL_COUNT Then
        Return 0
    End If
    state.solo(channelIndex) = IIf(state.solo(channelIndex) = 0, -1, 0)
    Return state.solo(channelIndex)
End Function


Public Function mixerState_ToggleRecord( _
    ByRef state As OseMixerChannelState, _
    ByVal channelIndex As Integer _
) As Integer
    If channelIndex < 0 OrElse channelIndex >= OSE_MIXER_CHANNEL_COUNT Then
        Return 0
    End If

    Dim As Integer wasArmed = state.record(channelIndex)
    For resetIndex As Integer = 0 To OSE_MIXER_CHANNEL_COUNT - 1
        state.record(resetIndex) = 0
    Next
    If wasArmed = 0 Then
        state.record(channelIndex) = -1
    End If
    Return state.record(channelIndex)
End Function

' -------------------------------------------------------------------------
' Resolved state
' -------------------------------------------------------------------------

Public Function mixerState_HasSolo( _
    ByRef state As OseMixerChannelState _
) As Integer
    For channelIndex As Integer = 0 To OSE_MIXER_CHANNEL_COUNT - 1
        If state.solo(channelIndex) <> 0 Then
            Return -1
        End If
    Next
    Return 0
End Function


Public Function mixerState_IsAudible( _
    ByRef state As OseMixerChannelState, _
    ByVal channelIndex As Integer _
) As Integer
    If channelIndex < 0 OrElse channelIndex >= OSE_MIXER_CHANNEL_COUNT Then
        Return 0
    End If
    If state.mute(channelIndex) <> 0 Then
        Return 0
    End If
    If mixerState_HasSolo(state) <> 0 AndAlso _
        state.solo(channelIndex) = 0 Then
        Return 0
    End If
    Return -1
End Function


Public Function mixerState_RecordChannel( _
    ByRef state As OseMixerChannelState _
) As Integer
    For channelIndex As Integer = 0 To OSE_MIXER_CHANNEL_COUNT - 1
        If state.record(channelIndex) <> 0 Then
            Return channelIndex
        End If
    Next
    Return -1
End Function

/' end of mixer_state.bas '/
