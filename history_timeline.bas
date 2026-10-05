/'
    Project: OpenSesh
    ---------------------------

    File: history_timeline.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements history_timeline.bi; declarations there define the shared interface.

    Purpose:

        Preserve chronological undo order across independent MIDI and audio
        model history stacks.

    Responsibilities:

        - implement fixed-size undo and redo domain rings
        - invalidate redo when a new branch is recorded
        - expose peek-then-commit operations for transactional model routing

    This file intentionally does NOT contain:

        - model snapshot allocation
        - UI refresh behavior
        - assumptions about a successful model undo or redo
'/

#lang "fb"

#include once "history_timeline.bi"

' -------------------------------------------------------------------------
' Ring operations
' -------------------------------------------------------------------------

Private Function historyTimeline_DomainIsValid( _
    ByVal editDomain As Integer _
) As Integer
    If editDomain = OSE_HISTORY_DOMAIN_MIDI OrElse _
        editDomain = OSE_HISTORY_DOMAIN_AUDIO Then
        Return -1
    End If
    Return 0
End Function


Private Sub historyTimeline_RingClear( _
    domains() As Integer, _
    ByRef ringStart As Integer, _
    ByRef ringCount As Integer _
)
    For historyIndex As Integer = 0 To OSE_HISTORY_TIMELINE_DEPTH - 1
        domains(historyIndex) = OSE_HISTORY_DOMAIN_NONE
    Next
    ringStart = 0
    ringCount = 0
End Sub


Private Function historyTimeline_RingNewestIndex( _
    ByVal ringStart As Integer, _
    ByVal ringCount As Integer _
) As Integer
    If ringStart < 0 OrElse ringStart >= OSE_HISTORY_TIMELINE_DEPTH OrElse _
        ringCount <= 0 OrElse ringCount > OSE_HISTORY_TIMELINE_DEPTH Then
        Return -1
    End If
    Return (ringStart + ringCount - 1) Mod OSE_HISTORY_TIMELINE_DEPTH
End Function


Private Function historyTimeline_RingPush( _
    domains() As Integer, _
    ByRef ringStart As Integer, _
    ByRef ringCount As Integer, _
    ByVal editDomain As Integer, _
    ByRef evictedDomain As Integer _
) As Integer
    evictedDomain = OSE_HISTORY_DOMAIN_NONE
    If historyTimeline_DomainIsValid(editDomain) = 0 OrElse _
        ringStart < 0 OrElse ringStart >= OSE_HISTORY_TIMELINE_DEPTH OrElse _
        ringCount < 0 OrElse ringCount > OSE_HISTORY_TIMELINE_DEPTH Then
        Return 0
    End If

    Dim As Integer targetIndex
    If ringCount = OSE_HISTORY_TIMELINE_DEPTH Then
        targetIndex = ringStart
        evictedDomain = domains(targetIndex)
        ringStart = (ringStart + 1) Mod OSE_HISTORY_TIMELINE_DEPTH
    Else
        targetIndex = (ringStart + ringCount) Mod OSE_HISTORY_TIMELINE_DEPTH
        ringCount += 1
    End If
    domains(targetIndex) = editDomain
    Return -1
End Function


Private Function historyTimeline_RingPopNewest( _
    domains() As Integer, _
    ByRef ringStart As Integer, _
    ByRef ringCount As Integer _
) As Integer
    Dim As Integer newestIndex = historyTimeline_RingNewestIndex( _
        ringStart, ringCount)
    If newestIndex < 0 Then
        Return OSE_HISTORY_DOMAIN_NONE
    End If
    Dim As Integer editDomain = domains(newestIndex)
    domains(newestIndex) = OSE_HISTORY_DOMAIN_NONE
    ringCount -= 1
    If ringCount = 0 Then
        ringStart = 0
    End If
    Return editDomain
End Function


' -------------------------------------------------------------------------
' Public chronological history contract
' -------------------------------------------------------------------------

Public Sub historyTimeline_Clear(ByRef timeline As OseHistoryTimeline)
    historyTimeline_RingClear timeline.undoDomains(), timeline.undoStart, _
        timeline.undoCount
    historyTimeline_RingClear timeline.redoDomains(), timeline.redoStart, _
        timeline.redoCount
End Sub


Public Function historyTimeline_RecordEdit( _
    ByRef timeline As OseHistoryTimeline, _
    ByVal editDomain As Integer, _
    ByRef evictedDomain As Integer _
) As Integer
    evictedDomain = OSE_HISTORY_DOMAIN_NONE
    If historyTimeline_DomainIsValid(editDomain) = 0 Then
        Return 0
    End If
    historyTimeline_RingClear timeline.redoDomains(), timeline.redoStart, _
        timeline.redoCount
    Return historyTimeline_RingPush(timeline.undoDomains(), _
        timeline.undoStart, timeline.undoCount, editDomain, evictedDomain)
End Function


Public Function historyTimeline_PeekUndo( _
    ByRef timeline As OseHistoryTimeline _
) As Integer
    Dim As Integer newestIndex = historyTimeline_RingNewestIndex( _
        timeline.undoStart, timeline.undoCount)
    If newestIndex < 0 Then
        Return OSE_HISTORY_DOMAIN_NONE
    End If
    Return timeline.undoDomains(newestIndex)
End Function


Public Function historyTimeline_PeekRedo( _
    ByRef timeline As OseHistoryTimeline _
) As Integer
    Dim As Integer newestIndex = historyTimeline_RingNewestIndex( _
        timeline.redoStart, timeline.redoCount)
    If newestIndex < 0 Then
        Return OSE_HISTORY_DOMAIN_NONE
    End If
    Return timeline.redoDomains(newestIndex)
End Function


Public Function historyTimeline_CommitUndo( _
    ByRef timeline As OseHistoryTimeline _
) As Integer
    Dim As Integer editDomain = historyTimeline_PeekUndo(timeline)
    If historyTimeline_DomainIsValid(editDomain) = 0 Then
        Return 0
    End If
    Dim As Integer ignoredEviction
    If historyTimeline_RingPush(timeline.redoDomains(), timeline.redoStart, _
        timeline.redoCount, editDomain, ignoredEviction) = 0 Then
        Return 0
    End If
    If historyTimeline_RingPopNewest(timeline.undoDomains(), _
        timeline.undoStart, timeline.undoCount) <> editDomain Then
        Return 0
    End If
    Return -1
End Function


Public Function historyTimeline_CommitRedo( _
    ByRef timeline As OseHistoryTimeline _
) As Integer
    Dim As Integer editDomain = historyTimeline_PeekRedo(timeline)
    If historyTimeline_DomainIsValid(editDomain) = 0 Then
        Return 0
    End If
    Dim As Integer ignoredEviction
    If historyTimeline_RingPush(timeline.undoDomains(), timeline.undoStart, _
        timeline.undoCount, editDomain, ignoredEviction) = 0 Then
        Return 0
    End If
    If historyTimeline_RingPopNewest(timeline.redoDomains(), _
        timeline.redoStart, timeline.redoCount) <> editDomain Then
        Return 0
    End If
    Return -1
End Function


Public Function historyTimeline_UndoCount( _
    ByRef timeline As OseHistoryTimeline _
) As Integer
    Return timeline.undoCount
End Function


Public Function historyTimeline_RedoCount( _
    ByRef timeline As OseHistoryTimeline _
) As Integer
    Return timeline.redoCount
End Function

/' end of history_timeline.bas '/
