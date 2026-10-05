/'
    Project: OpenSesh
    ---------------------------

    File: document_history.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements document_history.bi; declarations there define the shared interface.

    Purpose:

        Coordinate bounded MIDI and audio snapshots as one chronological
        document undo and redo history.

    Responsibilities:

        - capture model snapshots without discarding the other model's undo
        - defer redo invalidation until the caller confirms a successful edit
        - restore prepared snapshots when a mutation fails or changes nothing
        - invalidate both model redo branches after a new edit
        - discard the model snapshot represented by a timeline eviction
        - apply only the model named by the newest chronological entry

    This file intentionally does NOT contain:

        - model editing operations
        - window or widget calls
        - save/load transaction policy
'/

#lang "fb"

#include once "document_history.bi"

' -------------------------------------------------------------------------
' Timeline and model-stack alignment
' -------------------------------------------------------------------------

Private Sub documentHistory_DiscardEvictedUndo( _
    ByVal evictedDomain As Integer, _
    ByVal capturedDomain As Integer, _
    ByVal capturedStackWasFull As Integer _
)
    /'
        A full per-model ring evicts its oldest entry during capture. If that
        is also the entry evicted by the shared timeline, no second removal is
        needed. Mixed-domain histories usually stay below the per-model limit,
        so their timeline eviction must be mirrored explicitly.
    '/
    If evictedDomain = OSE_HISTORY_DOMAIN_NONE Then
        Exit Sub
    End If
    If evictedDomain = capturedDomain AndAlso capturedStackWasFull <> 0 Then
        Exit Sub
    End If

    Select Case evictedDomain
        Case OSE_HISTORY_DOMAIN_MIDI
            midi_HistoryDiscardOldestUndo()
        Case OSE_HISTORY_DOMAIN_AUDIO
            audio_HistoryDiscardOldestUndo()
    End Select
End Sub


' -------------------------------------------------------------------------
' Public document history contract
' -------------------------------------------------------------------------

Public Sub documentHistory_Clear(ByRef history As OseDocumentHistory)
    midi_HistoryClear()
    audio_HistoryClear()
    historyTimeline_Clear history.timeline
    history.pendingDomain = OSE_HISTORY_DOMAIN_NONE
    history.pendingStackWasFull = 0
End Sub


Public Function documentHistory_CaptureMidi( _
    ByRef history As OseDocumentHistory, _
    ByRef summary As MidiSummary _
) As Integer
    If documentHistory_PrepareMidi(history, summary) = 0 Then
        Return 0
    End If
    If documentHistory_CommitMidi(history) <> 0 Then
        Return -1
    End If
    documentHistory_CancelMidi history, summary
    Return 0
End Function


Public Function documentHistory_PrepareMidi( _
    ByRef history As OseDocumentHistory, _
    ByRef summary As MidiSummary _
) As Integer
    If history.pendingDomain <> OSE_HISTORY_DOMAIN_NONE Then
        Return 0
    End If
    history.pendingStackWasFull = IIf( _
        midi_HistoryUndoCount() >= OSE_MIDI_HISTORY_DEPTH, -1, 0)
    If midi_PrepareHistory(summary) = 0 Then
        history.pendingStackWasFull = 0
        Return 0
    End If
    history.pendingDomain = OSE_HISTORY_DOMAIN_MIDI
    Return -1
End Function


Public Function documentHistory_CommitMidi( _
    ByRef history As OseDocumentHistory _
) As Integer
    If history.pendingDomain <> OSE_HISTORY_DOMAIN_MIDI Then
        Return 0
    End If
    Dim As Integer capturedStackWasFull = history.pendingStackWasFull
    If midi_CommitPreparedHistory() = 0 Then
        Return 0
    End If

    ' A new edit abandons the complete document redo branch, not merely the
    ' redo snapshots owned by the model being edited.
    audio_HistoryRedoClear()

    Dim As Integer evictedDomain
    If historyTimeline_RecordEdit(history.timeline, OSE_HISTORY_DOMAIN_MIDI, _
        evictedDomain) = 0 Then
        documentHistory_Clear history
        Return 0
    End If
    documentHistory_DiscardEvictedUndo evictedDomain, _
        OSE_HISTORY_DOMAIN_MIDI, capturedStackWasFull
    history.pendingDomain = OSE_HISTORY_DOMAIN_NONE
    history.pendingStackWasFull = 0
    Return -1
End Function


Public Function documentHistory_CancelMidi( _
    ByRef history As OseDocumentHistory, _
    ByRef summary As MidiSummary _
) As Integer
    If history.pendingDomain <> OSE_HISTORY_DOMAIN_MIDI Then
        Return 0
    End If
    If midi_CancelPreparedHistory(summary) = 0 Then
        Return 0
    End If
    history.pendingDomain = OSE_HISTORY_DOMAIN_NONE
    history.pendingStackWasFull = 0
    Return -1
End Function


Public Function documentHistory_CaptureAudio( _
    ByRef history As OseDocumentHistory _
) As Integer
    If documentHistory_PrepareAudio(history) = 0 Then
        Return 0
    End If
    If documentHistory_CommitAudio(history) <> 0 Then
        Return -1
    End If
    documentHistory_CancelAudio history
    Return 0
End Function


Public Function documentHistory_PrepareAudio( _
    ByRef history As OseDocumentHistory _
) As Integer
    If history.pendingDomain <> OSE_HISTORY_DOMAIN_NONE Then
        Return 0
    End If
    history.pendingStackWasFull = IIf( _
        audio_HistoryUndoCount() >= OSE_AUDIO_HISTORY_DEPTH, -1, 0)
    If audio_PrepareHistory() = 0 Then
        history.pendingStackWasFull = 0
        Return 0
    End If
    history.pendingDomain = OSE_HISTORY_DOMAIN_AUDIO
    Return -1
End Function


Public Function documentHistory_CommitAudio( _
    ByRef history As OseDocumentHistory _
) As Integer
    If history.pendingDomain <> OSE_HISTORY_DOMAIN_AUDIO Then
        Return 0
    End If
    Dim As Integer capturedStackWasFull = history.pendingStackWasFull
    If audio_CommitPreparedHistory() = 0 Then
        Return 0
    End If

    midi_HistoryRedoClear()

    Dim As Integer evictedDomain
    If historyTimeline_RecordEdit(history.timeline, OSE_HISTORY_DOMAIN_AUDIO, _
        evictedDomain) = 0 Then
        documentHistory_Clear history
        Return 0
    End If
    documentHistory_DiscardEvictedUndo evictedDomain, _
        OSE_HISTORY_DOMAIN_AUDIO, capturedStackWasFull
    history.pendingDomain = OSE_HISTORY_DOMAIN_NONE
    history.pendingStackWasFull = 0
    Return -1
End Function


Public Function documentHistory_CancelAudio( _
    ByRef history As OseDocumentHistory _
) As Integer
    If history.pendingDomain <> OSE_HISTORY_DOMAIN_AUDIO Then
        Return 0
    End If
    If audio_CancelPreparedHistory() = 0 Then
        Return 0
    End If
    history.pendingDomain = OSE_HISTORY_DOMAIN_NONE
    history.pendingStackWasFull = 0
    Return -1
End Function


Public Function documentHistory_Undo( _
    ByRef history As OseDocumentHistory, _
    ByRef summary As MidiSummary _
) As Integer
    If history.pendingDomain <> OSE_HISTORY_DOMAIN_NONE Then
        Return OSE_HISTORY_DOMAIN_NONE
    End If
    Dim As Integer editDomain = historyTimeline_PeekUndo(history.timeline)
    Select Case editDomain
        Case OSE_HISTORY_DOMAIN_MIDI
            If midi_Undo(summary) = 0 Then
                Return OSE_HISTORY_DOMAIN_NONE
            End If
        Case OSE_HISTORY_DOMAIN_AUDIO
            If audio_Undo() = 0 Then
                Return OSE_HISTORY_DOMAIN_NONE
            End If
        Case Else
            Return OSE_HISTORY_DOMAIN_NONE
    End Select

    /'
        The timeline entry moves only after the selected model succeeds. This
        prevents an allocation or restore failure from exposing a redo command
        for a model state that was never changed.
    '/
    If historyTimeline_CommitUndo(history.timeline) = 0 Then
        Return OSE_HISTORY_DOMAIN_NONE
    End If
    Return editDomain
End Function


Public Function documentHistory_Redo( _
    ByRef history As OseDocumentHistory, _
    ByRef summary As MidiSummary _
) As Integer
    If history.pendingDomain <> OSE_HISTORY_DOMAIN_NONE Then
        Return OSE_HISTORY_DOMAIN_NONE
    End If
    Dim As Integer editDomain = historyTimeline_PeekRedo(history.timeline)
    Select Case editDomain
        Case OSE_HISTORY_DOMAIN_MIDI
            If midi_Redo(summary) = 0 Then
                Return OSE_HISTORY_DOMAIN_NONE
            End If
        Case OSE_HISTORY_DOMAIN_AUDIO
            If audio_Redo() = 0 Then
                Return OSE_HISTORY_DOMAIN_NONE
            End If
        Case Else
            Return OSE_HISTORY_DOMAIN_NONE
    End Select

    If historyTimeline_CommitRedo(history.timeline) = 0 Then
        Return OSE_HISTORY_DOMAIN_NONE
    End If
    Return editDomain
End Function


Public Function documentHistory_UndoCount( _
    ByRef history As OseDocumentHistory _
) As Integer
    Return historyTimeline_UndoCount(history.timeline)
End Function


Public Function documentHistory_RedoCount( _
    ByRef history As OseDocumentHistory _
) As Integer
    Return historyTimeline_RedoCount(history.timeline)
End Function

/' end of document_history.bas '/
