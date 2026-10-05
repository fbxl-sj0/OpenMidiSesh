/'
    Project: OpenSesh
    ---------------------------

    File: playback_state.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements playback_state.bi; declarations there define the shared interface.

    Purpose:

        Reconstruct software-playback channel state from ordered MIDI events.

    Responsibilities:

        - establish General MIDI controller and bend defaults
        - apply bank select, CC7, CC10, CC11, program change, and pitch bend
        - reject unsupported events without changing retained state
        - validate channel indices at the module boundary

    This file intentionally does NOT contain:

        - note-on or note-off handling
        - controller-event storage
        - mixer drawing or sound generation
'/

#lang "fb"

#include once "playback_state.bi"

' -------------------------------------------------------------------------
' State lifecycle
' -------------------------------------------------------------------------

Public Sub playbackState_Initialize(ByRef state As OsePlaybackChannelState)
    Dim As OsePlaybackChannelState emptyState
    state = emptyState
    For channelIndex As Integer = 0 To OSE_PLAYBACK_CHANNEL_COUNT - 1
        state.controllerVolume(channelIndex) = 127
        state.controllerExpression(channelIndex) = 127
        state.controllerPan(channelIndex) = 64
        state.pitchBend(channelIndex) = 8192
    Next
End Sub

' -------------------------------------------------------------------------
' Ordered channel events
' -------------------------------------------------------------------------

Public Function playbackState_Apply( _
    ByRef state As OsePlaybackChannelState, _
    ByRef channelEvent As MidiChannelEventPoint _
) As Integer
    Dim As Integer channelIndex = channelEvent.channel
    If channelIndex < 0 OrElse channelIndex >= OSE_PLAYBACK_CHANNEL_COUNT Then _
        Return 0

    Select Case channelEvent.messageType
        Case &HB0
            Select Case channelEvent.data1
                Case 0
                    state.bankSelectMsb(channelIndex) = channelEvent.data2
                Case 7
                    state.controllerVolume(channelIndex) = channelEvent.data2
                Case 10
                    state.controllerPan(channelIndex) = channelEvent.data2
                Case 11
                    state.controllerExpression(channelIndex) = channelEvent.data2
                Case 32
                    state.bankSelectLsb(channelIndex) = channelEvent.data2
                Case Else
                    Return 0
            End Select
        Case &HC0
            state.programNumber(channelIndex) = channelEvent.data1
        Case &HE0
            state.pitchBend(channelIndex) = _
                CInt(channelEvent.data1) Or (CInt(channelEvent.data2) Shl 7)
        Case Else
            Return 0
    End Select
    Return -1
End Function


Public Function playbackState_BankNumber( _
    ByRef state As OsePlaybackChannelState, _
    ByVal channelIndex As Integer _
) As Integer
    If channelIndex < 0 OrElse channelIndex >= OSE_PLAYBACK_CHANNEL_COUNT Then _
        Return 0
    Return CInt(state.bankSelectMsb(channelIndex)) * 128 + _
        CInt(state.bankSelectLsb(channelIndex))
End Function

/' end of playback_state.bas '/
