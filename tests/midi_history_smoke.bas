/'
    Project: OpenSesh
    ---------------------------

    File: tests/midi_history_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Stress the bounded multi-step MIDI undo and redo rings.

    Responsibilities:

        - exceed the configured depth and prove oldest-step eviction
        - round-trip notes and managed track-name event strings
        - prove undo/redo counts at every transition
        - cancel edits at full capacity without evicting history
        - preserve an existing redo branch after a failed prepared edit
        - prove a branch edit invalidates the abandoned redo path

    This file intentionally does NOT contain:

        - MIDI file parsing or writing
        - application-level audio history routing
        - graphical editor code
'/

#lang "fb"

#include once "../midi_model.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Dim As MidiSummary summary
If midi_NewDocument(summary) = 0 Then
    test_Fail "new document failed"
End If

Const extraEdits As Integer = 4
Const totalEdits As Integer = OSE_MIDI_HISTORY_DEPTH + extraEdits
For editIndex As Integer = 0 To totalEdits - 1
    If midi_CaptureHistory(summary) = 0 Then _
        test_Fail "history capture failed"
    If midi_AddEditableNote(summary, 0, CULngInt(editIndex) * 120, 60, _
        48 + (editIndex Mod 24), 0, 80 + (editIndex Mod 40)) < 0 Then _
        test_Fail "history note could not be added"
    If midi_SetTrackName(summary, 0, _
        "History step " + LTrim(Str(editIndex))) = 0 Then _
        test_Fail "managed track name could not be stored"
    Dim As Integer expectedUndoCount = editIndex + 1
    If expectedUndoCount > OSE_MIDI_HISTORY_DEPTH Then _
        expectedUndoCount = OSE_MIDI_HISTORY_DEPTH
    If midi_HistoryUndoCount() <> expectedUndoCount OrElse _
        midi_HistoryRedoCount() <> 0 Then _
        test_Fail "capture counts exceeded the bounded ring"
Next

If summary.noteCount <> totalEdits OrElse _
    midi_TrackDisplayName(summary, 0) <> _
        "History step " + LTrim(Str(totalEdits - 1)) Then _
    test_Fail "final MIDI edit state is incorrect"

Dim As Integer fullUndoCount = midi_HistoryUndoCount()
If midi_PrepareHistory(summary) = 0 OrElse _
    midi_PrepareHistory(summary) <> 0 OrElse _
    midi_AddEditableNote(summary, 0, 6000, 120, 75, 2, 99) < 0 OrElse _
    midi_CancelPreparedHistory(summary) = 0 OrElse _
    summary.noteCount <> totalEdits OrElse _
    midi_HistoryUndoCount() <> fullUndoCount OrElse _
    midi_HistoryRedoCount() <> 0 Then _
    test_Fail "cancel at full MIDI history capacity changed the branch"

For undoIndex As Integer = 1 To OSE_MIDI_HISTORY_DEPTH
    If midi_Undo(summary) = 0 Then
        test_Fail "bounded undo failed"
    End If
    If summary.noteCount <> totalEdits - undoIndex OrElse _
        midi_HistoryUndoCount() <> OSE_MIDI_HISTORY_DEPTH - undoIndex OrElse _
        midi_HistoryRedoCount() <> undoIndex Then _
        test_Fail "undo restored the wrong ring state"
Next
If summary.noteCount <> extraEdits OrElse _
    midi_TrackDisplayName(summary, 0) <> _
        "History step " + LTrim(Str(extraEdits - 1)) Then _
    test_Fail "oldest retained MIDI state is incorrect"
If midi_Undo(summary) <> 0 OrElse summary.noteCount <> extraEdits Then _
    test_Fail "undo crossed the configured history depth"

For redoIndex As Integer = 1 To OSE_MIDI_HISTORY_DEPTH
    If midi_Redo(summary) = 0 Then
        test_Fail "bounded redo failed"
    End If
    If summary.noteCount <> extraEdits + redoIndex OrElse _
        midi_HistoryUndoCount() <> redoIndex OrElse _
        midi_HistoryRedoCount() <> OSE_MIDI_HISTORY_DEPTH - redoIndex Then _
        test_Fail "redo restored the wrong ring state"
Next
If midi_Redo(summary) <> 0 OrElse summary.noteCount <> totalEdits Then _
    test_Fail "redo crossed the available branch"

For undoIndex As Integer = 1 To 8
    If midi_Undo(summary) = 0 Then
        test_Fail "branch setup undo failed"
    End If
Next
If summary.noteCount <> totalEdits - 8 OrElse _
    midi_HistoryRedoCount() <> 8 Then _
    test_Fail "branch setup reached the wrong state"
If midi_CaptureHistory(summary) = 0 OrElse _
    midi_AddEditableNote(summary, 0, 5000, 120, 72, 1, 100) < 0 OrElse _
    midi_SetTrackName(summary, 0, "Branch edit") = 0 Then _
    test_Fail "branch edit failed"
If midi_HistoryRedoCount() <> 0 OrElse midi_Redo(summary) <> 0 Then _
    test_Fail "new MIDI branch retained abandoned redo states"
If midi_Undo(summary) = 0 OrElse summary.noteCount <> totalEdits - 8 Then _
    test_Fail "branch undo failed"
If midi_Redo(summary) = 0 OrElse summary.noteCount <> totalEdits - 7 OrElse _
    midi_TrackDisplayName(summary, 0) <> "Branch edit" Then _
    test_Fail "branch redo failed"

' A failed edit after Undo must not silently destroy the user's Redo command.
If midi_Undo(summary) = 0 Then
    test_Fail "cancel redo setup undo failed"
End If
Dim As Integer cancelUndoCount = midi_HistoryUndoCount()
Dim As Integer cancelRedoCount = midi_HistoryRedoCount()
Dim As Integer cancelNoteCount = summary.noteCount
If midi_PrepareHistory(summary) = 0 Then _
    test_Fail "cancel redo snapshot preparation failed"
If midi_Undo(summary) <> 0 OrElse midi_Redo(summary) <> 0 Then _
    test_Fail "undo or redo ran during a prepared MIDI edit"
If midi_AddEditableNote(summary, 0, 7000, 120, 77, 3, 90) < 0 OrElse _
    midi_SetTrackName(summary, 0, "Cancelled edit") = 0 Then _
    test_Fail "cancel redo mutation setup failed"
If midi_CancelPreparedHistory(summary) = 0 OrElse _
    summary.noteCount <> cancelNoteCount OrElse _
    midi_HistoryUndoCount() <> cancelUndoCount OrElse _
    midi_HistoryRedoCount() <> cancelRedoCount Then _
    test_Fail "cancelled MIDI edit changed state or history counts"
If midi_Redo(summary) = 0 OrElse _
    midi_TrackDisplayName(summary, 0) <> "Branch edit" Then _
    test_Fail "cancelled MIDI edit destroyed the existing redo branch"

midi_HistoryClear()
If midi_HistoryUndoCount() <> 0 OrElse midi_HistoryRedoCount() <> 0 OrElse _
    midi_Undo(summary) <> 0 OrElse midi_Redo(summary) <> 0 Then _
    test_Fail "MIDI history clear retained a snapshot"

Print "midi_history=ok"
Print "depth="; OSE_MIDI_HISTORY_DEPTH; " edits="; totalEdits; _
    " branch_undos=8 cancelled_edits=2"
End 0

/' end of tests/midi_history_smoke.bas '/
