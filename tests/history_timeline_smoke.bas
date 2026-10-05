/'
    Project: OpenSesh
    ---------------------------

    File: tests/history_timeline_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove chronological edit routing across MIDI and audio model domains.

    Responsibilities:

        - exceed and verify timeline depth eviction
        - verify complete alternating-domain undo and redo order
        - verify branch edits invalidate redo
        - reject invalid domains and clear all retained state

    This file intentionally does NOT contain:

        - MIDI or audio snapshot storage
        - application globals
        - graphical editor code
'/

#lang "fb"

#include once "../history_timeline.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Dim As OseHistoryTimeline timeline
historyTimeline_Clear timeline
Dim As Integer evictedDomain
If historyTimeline_RecordEdit(timeline, OSE_HISTORY_DOMAIN_NONE, _
    evictedDomain) <> 0 Then test_Fail "invalid edit domain was accepted"

Const extraEdits As Integer = 4
Const totalEdits As Integer = OSE_HISTORY_TIMELINE_DEPTH + extraEdits
For editIndex As Integer = 0 To totalEdits - 1
    Dim As Integer editDomain = IIf((editIndex And 1) = 0, _
        OSE_HISTORY_DOMAIN_MIDI, OSE_HISTORY_DOMAIN_AUDIO)
    If historyTimeline_RecordEdit(timeline, editDomain, evictedDomain) = 0 Then _
        test_Fail "timeline record failed"
    If editIndex < OSE_HISTORY_TIMELINE_DEPTH Then
        If evictedDomain <> OSE_HISTORY_DOMAIN_NONE Then _
            test_Fail "timeline evicted an entry before reaching its bound"
    Else
        Dim As Integer expectedEviction = IIf( _
            ((editIndex - OSE_HISTORY_TIMELINE_DEPTH) And 1) = 0, _
            OSE_HISTORY_DOMAIN_MIDI, OSE_HISTORY_DOMAIN_AUDIO)
        If evictedDomain <> expectedEviction Then _
            test_Fail "timeline evicted the wrong oldest domain"
    End If
Next
If historyTimeline_UndoCount(timeline) <> OSE_HISTORY_TIMELINE_DEPTH OrElse _
    historyTimeline_RedoCount(timeline) <> 0 Then _
    test_Fail "timeline did not stop at its bound"

For undoIndex As Integer = 0 To OSE_HISTORY_TIMELINE_DEPTH - 1
    Dim As Integer sourceEdit = totalEdits - 1 - undoIndex
    Dim As Integer expectedDomain = IIf((sourceEdit And 1) = 0, _
        OSE_HISTORY_DOMAIN_MIDI, OSE_HISTORY_DOMAIN_AUDIO)
    If historyTimeline_PeekUndo(timeline) <> expectedDomain OrElse _
        historyTimeline_CommitUndo(timeline) = 0 Then _
        test_Fail "chronological undo domain order failed"
Next
If historyTimeline_PeekUndo(timeline) <> OSE_HISTORY_DOMAIN_NONE OrElse _
    historyTimeline_CommitUndo(timeline) <> 0 OrElse _
    historyTimeline_RedoCount(timeline) <> OSE_HISTORY_TIMELINE_DEPTH Then _
    test_Fail "timeline undo crossed its retained history"

For redoIndex As Integer = 0 To OSE_HISTORY_TIMELINE_DEPTH - 1
    Dim As Integer sourceEdit = extraEdits + redoIndex
    Dim As Integer expectedDomain = IIf((sourceEdit And 1) = 0, _
        OSE_HISTORY_DOMAIN_MIDI, OSE_HISTORY_DOMAIN_AUDIO)
    If historyTimeline_PeekRedo(timeline) <> expectedDomain OrElse _
        historyTimeline_CommitRedo(timeline) = 0 Then _
        test_Fail "chronological redo domain order failed"
Next
If historyTimeline_PeekRedo(timeline) <> OSE_HISTORY_DOMAIN_NONE OrElse _
    historyTimeline_CommitRedo(timeline) <> 0 Then _
    test_Fail "timeline redo crossed its retained history"

For undoIndex As Integer = 1 To 8
    If historyTimeline_CommitUndo(timeline) = 0 Then _
        test_Fail "branch setup undo failed"
Next
If historyTimeline_RedoCount(timeline) <> 8 OrElse _
    historyTimeline_RecordEdit(timeline, OSE_HISTORY_DOMAIN_MIDI, _
        evictedDomain) = 0 OrElse historyTimeline_RedoCount(timeline) <> 0 OrElse _
    historyTimeline_PeekUndo(timeline) <> OSE_HISTORY_DOMAIN_MIDI Then _
    test_Fail "branch edit did not replace the redo path"

historyTimeline_Clear timeline
If historyTimeline_UndoCount(timeline) <> 0 OrElse _
    historyTimeline_RedoCount(timeline) <> 0 OrElse _
    historyTimeline_PeekUndo(timeline) <> OSE_HISTORY_DOMAIN_NONE OrElse _
    historyTimeline_PeekRedo(timeline) <> OSE_HISTORY_DOMAIN_NONE Then _
    test_Fail "timeline clear retained a domain"

Print "history_timeline=ok"
Print "depth="; OSE_HISTORY_TIMELINE_DEPTH; " edits="; totalEdits; _
    " alternating_domains=2"
End 0

/' end of tests/history_timeline_smoke.bas '/
