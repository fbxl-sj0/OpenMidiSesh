/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/channel_state.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Reconcile channel controls for playback.

    Responsibilities:

        - apply bounded volume, pan and effect state
        - refresh channel state after document changes

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_CHANNEL_STATE_BI__
#define __OSE_EDITOR_CHANNEL_STATE_BI__


' -------------------------------------------------------------------------
' Playback channel state
' -------------------------------------------------------------------------

Private Function session_PlaybackChannelEventBefore( _
    ByRef leftEvent As MidiChannelEventPoint, _
    ByRef rightEvent As MidiChannelEventPoint _
) As Integer
    If leftEvent.tick < rightEvent.tick Then
        Return -1
    End If
    If leftEvent.tick > rightEvent.tick Then
        Return 0
    End If
    If leftEvent.trackIndex < rightEvent.trackIndex Then
        Return -1
    End If
    If leftEvent.trackIndex > rightEvent.trackIndex Then
        Return 0
    End If
    Return leftEvent.sourceIndex < rightEvent.sourceIndex
End Function


Private Sub session_SortPlaybackChannelEvents( _
    events() As MidiChannelEventPoint, _
    ByVal lowIndex As Integer, _
    ByVal highIndex As Integer _
)
    If lowIndex >= highIndex Then
        Exit Sub
    End If

    Dim As Integer leftIndex = lowIndex
    Dim As Integer rightIndex = highIndex
    Dim As MidiChannelEventPoint pivot = _
        events(lowIndex + (highIndex - lowIndex) \ 2)

    Do
        While leftIndex <= highIndex AndAlso _
            session_PlaybackChannelEventBefore(events(leftIndex), pivot) <> 0
            leftIndex += 1
        Wend
        While rightIndex >= lowIndex AndAlso _
            session_PlaybackChannelEventBefore(pivot, events(rightIndex)) <> 0
            rightIndex -= 1
        Wend
        If leftIndex <= rightIndex Then
            Swap events(leftIndex), events(rightIndex)
            leftIndex += 1
            rightIndex -= 1
        End If
    Loop While leftIndex <= rightIndex

    If lowIndex < rightIndex Then _
        session_SortPlaybackChannelEvents events(), lowIndex, rightIndex
    If leftIndex < highIndex Then _
        session_SortPlaybackChannelEvents events(), leftIndex, highIndex
End Sub


Private Sub session_RebuildPlaybackChannelEventOrder()
    If session_PlaybackChannelOrderDirty = 0 Then
        Exit Sub
    End If

    Erase session_PlaybackOrderedChannelEvents
    session_PlaybackOrderedChannelEventCount = 0
    Dim As Integer eventCount = midi_GetChannelEventCount()
    If eventCount <= 0 Then
        session_PlaybackChannelOrderDirty = 0
        Exit Sub
    End If

    Redim session_PlaybackOrderedChannelEvents(0 To eventCount - 1)
    For eventIndex As Integer = 0 To eventCount - 1
        Dim As MidiChannelEventPoint channelEvent
        If midi_GetChannelEvent(eventIndex, channelEvent) = 0 Then
            Continue For
        End If
        session_PlaybackOrderedChannelEvents( _
            session_PlaybackOrderedChannelEventCount) = channelEvent
        session_PlaybackOrderedChannelEventCount += 1
    Next

    If session_PlaybackOrderedChannelEventCount > 1 Then
        session_SortPlaybackChannelEvents _
            session_PlaybackOrderedChannelEvents(), 0, _
            session_PlaybackOrderedChannelEventCount - 1
    End If
    session_PlaybackChannelOrderDirty = 0
End Sub


Private Sub session_ResetPlaybackChannelState()
    playbackState_Initialize session_PlaybackState
End Sub


Private Sub session_ApplyPlaybackChannelEvent( _
    ByRef channelEvent As MidiChannelEventPoint _
)
    playbackState_Apply session_PlaybackState, channelEvent
End Sub


Private Sub session_ApplyPlaybackChannelEvents( _
    ByVal currentTick As ULongInt, _
    ByVal previousTick As ULongInt, _
    ByVal firstUpdate As Integer _
)
    session_RebuildPlaybackChannelEventOrder()
    For eventIndex As Integer = 0 To _
        session_PlaybackOrderedChannelEventCount - 1
        Dim As MidiChannelEventPoint channelEvent = _
            session_PlaybackOrderedChannelEvents(eventIndex)

        Dim As Integer inRange = 0
        If firstUpdate <> 0 Then
            If channelEvent.tick <= currentTick Then
                inRange = -1
            End If
        ElseIf channelEvent.tick > previousTick AndAlso _
            channelEvent.tick <= currentTick Then
            inRange = -1
        End If
        If inRange <> 0 Then
            session_ApplyPlaybackChannelEvent channelEvent
        End If
    Next
End Sub

#endif

/' end of src/editor/channel_state.bi '/
