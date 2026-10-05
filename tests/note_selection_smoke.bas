/'
    Project: OpenSesh
    ---------------------------

    File: note_selection_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify sorted multi-note selection and relative-time clipboard capture
        without requiring GUI automation.

    Responsibilities:

        - verify select-only, additive selection, toggle, and primary fallback
        - verify selected indices remain sorted and unique
        - verify selected time, track, and pitch bounds
        - verify clipboard time and track origins
        - verify destination paste preserves relative timing and track spacing
        - preserve the previous clipboard when a later capture is rejected
        - verify musical edit plans preserve drums, duration, and model limits

    This file intentionally does NOT contain:

        - mouse input simulation
        - score rendering
        - operating-system clipboard calls
'/

#lang "fb"

#include once "../midi_model.bi"
#include once "../note_selection.bi"

Dim As MidiSummary summary
If midi_NewDocument(summary) = 0 Then
    Print "ERROR: could not create selection fixture"
    End 1
End If
If midi_AddTrack(summary) <> 1 OrElse midi_AddTrack(summary) <> 2 Then
    Print "ERROR: could not create destination-paste tracks"
    End 1
End If

Dim As ULongInt quarterTicks = CULngInt(summary.division)
Dim As Integer note0 = midi_AddEditableNote(summary, 0, _
    quarterTicks * 4, quarterTicks, 60, 0, 100)
Dim As Integer note1 = midi_AddEditableNote(summary, 0, _
    quarterTicks * 2, quarterTicks \ 2, 62, 0, 90)
Dim As Integer note2 = midi_AddEditableNote(summary, 1, _
    quarterTicks * 7, quarterTicks * 2, 64, 1, 80)
If note0 <> 0 OrElse note1 <> 1 OrElse note2 <> 2 Then
    Print "ERROR: could not create deterministic editable notes"
    End 1
End If

Dim As NoteSelectionState selection
noteSelection_Initialize selection
If noteSelection_SelectOnly(selection, note2) = 0 OrElse _
    noteSelection_Add(selection, note0, 0) = 0 OrElse _
    noteSelection_Add(selection, note1, -1) = 0 Then
    Print "ERROR: could not build additive selection"
    End 1
End If
If selection.count <> 3 OrElse selection.noteIndices(0) <> note0 OrElse _
    selection.noteIndices(1) <> note1 OrElse _
    selection.noteIndices(2) <> note2 OrElse _
    selection.primaryNoteIndex <> note1 Then
    Print "ERROR: selection order or primary note is incorrect"
    End 1
End If

If noteSelection_Toggle(selection, note1) = 0 Then
    Print "ERROR: selected note could not be toggled off"
    End 1
End If
If selection.count <> 2 OrElse selection.primaryNoteIndex <> note2 OrElse _
    noteSelection_Contains(selection, note1) <> 0 Then
    Print "ERROR: toggle did not preserve a valid primary note"
    End 1
End If

If noteSelection_Remove(selection, note0) = 0 OrElse selection.count <> 1 OrElse _
    selection.primaryNoteIndex <> note2 Then
    Print "ERROR: direct selection removal changed primary ownership"
    End 1
End If
If noteSelection_Add(selection, note0, 0) = 0 Then
    Print "ERROR: removed selection could not be restored"
    End 1
End If
noteSelection_SynchronizePrimary selection, note0, 3
If selection.primaryNoteIndex <> note0 OrElse selection.count <> 2 Then
    Print "ERROR: valid primary synchronization changed the selection"
    End 1
End If
noteSelection_SynchronizePrimary selection, 3, 3
If selection.count <> 0 OrElse selection.primaryNoteIndex <> -1 Then
    Print "ERROR: invalid primary synchronization did not clear selection"
    End 1
End If
If noteSelection_SelectOnly(selection, note2) = 0 OrElse _
    noteSelection_Add(selection, note0, 0) = 0 Then
    Print "ERROR: selection could not be rebuilt after synchronization"
    End 1
End If

Dim As NoteSelectionSummary selectionSummary
If noteSelection_Summarize(selection, selectionSummary) = 0 OrElse _
    selectionSummary.count <> 2 OrElse _
    selectionSummary.startTick <> quarterTicks * 4 OrElse _
    selectionSummary.endTick <> quarterTicks * 9 OrElse _
    selectionSummary.minimumTrack <> 0 OrElse _
    selectionSummary.maximumTrack <> 1 OrElse _
    selectionSummary.minimumPitch <> 60 OrElse _
    selectionSummary.maximumPitch <> 64 Then
    Print "ERROR: selection time, track, or pitch bounds are incorrect"
    End 1
End If

Dim As NoteSelectionState emptySelection
noteSelection_Initialize emptySelection
selectionSummary.count = 99
selectionSummary.startTick = 99
selectionSummary.minimumTrack = 99
If noteSelection_Summarize(emptySelection, selectionSummary) <> 0 OrElse _
    selectionSummary.count <> 0 OrElse selectionSummary.startTick <> 0 OrElse _
    selectionSummary.minimumTrack <> -1 OrElse _
    selectionSummary.maximumPitch <> -1 Then
    Print "ERROR: empty selection did not return cleared bounds"
    End 1
End If

Dim As NoteClipboardState clipboard
noteClipboard_Initialize clipboard
If noteClipboard_Capture(clipboard, selection) = 0 Then
    Print "ERROR: clipboard capture failed"
    End 1
End If
If clipboard.count <> 2 OrElse clipboard.originTick <> quarterTicks * 4 OrElse _
    clipboard.maximumRelativeEnd <> quarterTicks * 5 OrElse _
    clipboard.originTrack <> 0 OrElse clipboard.maximumRelativeTrack <> 1 Then
    Print "ERROR: clipboard relative-time bounds are incorrect"
    End 1
End If
noteSelection_Clear selection
If selection.count <> 0 OrElse selection.primaryNoteIndex <> -1 OrElse _
    clipboard.count <> 2 Then
    Print "ERROR: selection clear changed retained clipboard data"
    End 1
End If

Dim As MidiEditableNote preparedPaste(0 To 1)
If noteClipboard_PreparePaste(clipboard, quarterTicks * 10, 1, _
    summary.trackCount, @preparedPaste(0), 2) <> 2 Then
    Print "ERROR: destination paste preparation failed"
    End 1
End If
If preparedPaste(0).startTick <> quarterTicks * 10 OrElse _
    preparedPaste(0).trackIndex <> 1 OrElse _
    preparedPaste(1).startTick <> quarterTicks * 13 OrElse _
    preparedPaste(1).trackIndex <> 2 Then
    Print "ERROR: destination paste did not preserve relative placement"
    End 1
End If
If noteClipboard_PreparePaste(clipboard, quarterTicks * 10, 2, _
    summary.trackCount, @preparedPaste(0), 2) <> 0 Then
    Print "ERROR: destination paste accepted an overflowing track group"
    End 1
End If

Dim As Integer bulkIndices(0 To 1) = {note0, note2}

' A stale selection can fail after its first valid note. The previous copy
' must remain a complete, usable phrase, including both notes and its origins.
Dim As NoteSelectionState staleSelection
staleSelection.count = 2
staleSelection.noteIndices(0) = note1
staleSelection.noteIndices(1) = midi_GetEditableNoteCount()
If noteClipboard_Capture(clipboard, staleSelection) <> 0 Then
    Print "ERROR: clipboard accepted a stale selection"
    End 1
End If
If noteClipboard_PreparePaste(clipboard, quarterTicks * 10, 1, _
    summary.trackCount, @preparedPaste(0), 2) <> 2 OrElse _
    preparedPaste(0).startTick <> quarterTicks * 10 OrElse _
    preparedPaste(0).keyNumber <> 60 OrElse _
    preparedPaste(1).startTick <> quarterTicks * 13 OrElse _
    preparedPaste(1).keyNumber <> 64 Then
    Print "ERROR: failed capture damaged the previous clipboard"
    End 1
End If

Dim As MidiEditableNote movedNotes(0 To 1)
For notePosition As Integer = 0 To 1
    movedNotes(notePosition) = clipboard.notes(notePosition)
    movedNotes(notePosition).startTick += quarterTicks
    movedNotes(notePosition).keyNumber += 1
Next
If midi_CaptureHistory(summary) = 0 Then
    Print "ERROR: could not capture group-move history"
    End 1
End If
If midi_SetEditableNotes(summary, @bulkIndices(0), @movedNotes(0), 2) = 0 Then
    Print "ERROR: bulk note movement failed"
    End 1
End If
Dim As MidiEditableNote verifiedNote
If midi_GetEditableNote(note2, verifiedNote) = 0 OrElse _
    verifiedNote.startTick <> quarterTicks * 8 OrElse _
    verifiedNote.keyNumber <> 65 Then
    Print "ERROR: bulk note movement stored incorrect values"
    End 1
End If
If midi_Undo(summary) = 0 OrElse _
    midi_GetEditableNote(note2, verifiedNote) = 0 OrElse _
    verifiedNote.startTick <> quarterTicks * 7 OrElse _
    verifiedNote.keyNumber <> 64 OrElse midi_Redo(summary) = 0 Then
    Print "ERROR: group movement was not one undoable edit"
    End 1
End If

If midi_CaptureHistory(summary) = 0 Then
    Print "ERROR: could not capture bulk-paste history"
    End 1
End If
Dim As Integer firstAddedIndex = midi_AddEditableNotes( _
    summary, @clipboard.notes(0), clipboard.count)
If firstAddedIndex <> 3 OrElse midi_GetEditableNoteCount() <> 5 Then
    Print "ERROR: bulk note paste did not append a contiguous group"
    End 1
End If
If midi_Undo(summary) = 0 OrElse midi_GetEditableNoteCount() <> 3 OrElse _
    midi_Redo(summary) = 0 OrElse midi_GetEditableNoteCount() <> 5 Then
    Print "ERROR: bulk paste was not one undoable edit"
    End 1
End If

Dim As Integer removeIndices(0 To 1) = {1, 3}
If midi_CaptureHistory(summary) = 0 Then
    Print "ERROR: could not capture bulk-delete history"
    End 1
End If
If midi_RemoveEditableNotes(summary, @removeIndices(0), 2) = 0 OrElse _
    midi_GetEditableNoteCount() <> 3 Then
    Print "ERROR: bulk note delete did not compact the model"
    End 1
End If
If midi_Undo(summary) = 0 OrElse midi_GetEditableNoteCount() <> 5 OrElse _
    midi_Redo(summary) = 0 OrElse midi_GetEditableNoteCount() <> 3 Then
    Print "ERROR: bulk delete was not one undoable edit"
    End 1
End If

' A melody and a drum hit exercise the musical edit boundary together.
If midi_NewDocument(summary) = 0 Then
    End 1
End If
noteSelection_Clear selection
note0 = midi_AddEditableNote(summary, 0, 13, 90, 60, 0, 125)
note1 = midi_AddEditableNote(summary, 0, 133, 70, 38, 9, 5)
noteSelection_Add selection, note0, -1
noteSelection_Add selection, note1, 0
Dim As MidiEditableNote plannedNotes(0 To 1)
If noteSelection_PrepareEdit(selection, OSE_NOTE_EDIT_DUPLICATE, 0, 120, @plannedNotes(0), 2) <> 2 OrElse _
    plannedNotes(0).startTick <> 253 OrElse plannedNotes(1).startTick <> 373 OrElse _
    plannedNotes(0).durationTicks <> 90 OrElse plannedNotes(1).channel <> 9 Then
    Print "ERROR: duplicate did not preserve intervals, durations and channels"
    End 1
End If
If noteSelection_PrepareEdit(selection, OSE_NOTE_EDIT_QUANTIZE, 0, 120, @plannedNotes(0), 2) <> 2 OrElse _
    plannedNotes(0).startTick <> 0 OrElse plannedNotes(1).startTick <> 120 OrElse _
    plannedNotes(0).durationTicks <> 90 Then
    Print "ERROR: quantize did not preserve duration"
    End 1
End If
If noteSelection_PrepareEdit(selection, OSE_NOTE_EDIT_PITCH, 12, 120, @plannedNotes(0), 2) <> 1 OrElse _
    plannedNotes(0).keyNumber <> 72 OrElse plannedNotes(1).keyNumber <> 38 Then
    Print "ERROR: transpose changed a percussion instrument"
    End 1
End If
If noteSelection_PrepareEdit(selection, OSE_NOTE_EDIT_VELOCITY, 10, 120, @plannedNotes(0), 2) <> 2 OrElse _
    plannedNotes(0).velocity <> 127 OrElse plannedNotes(1).velocity <> 15 Then
    Print "ERROR: louder did not clamp velocity"
    End 1
End If
If noteSelection_PrepareEdit(selection, OSE_NOTE_EDIT_VELOCITY, -10, 120, @plannedNotes(0), 2) <> 2 OrElse _
    plannedNotes(0).velocity <> 115 OrElse plannedNotes(1).velocity <> 1 Then
    Print "ERROR: softer produced a silent note-on"
    End 1
End If
If noteSelection_PrepareEdit(selection, OSE_NOTE_EDIT_PITCH, 127, 120, @plannedNotes(0), 2) <> -1 OrElse _
    noteSelection_PrepareEdit(selection, OSE_NOTE_EDIT_QUANTIZE, 0, 0, @plannedNotes(0), 2) <> -1 OrElse _
    noteSelection_PrepareEdit(selection, OSE_NOTE_EDIT_DUPLICATE, 0, 120, @plannedNotes(0), 1) <> -1 OrElse _
    noteSelection_PrepareEdit(selection, OSE_NOTE_EDIT_DUPLICATE, 0, 120, 0, 2) <> -1 Then
    Print "ERROR: edit planning accepted invalid limits or storage"
    End 1
End If
If midi_GetEditableNote(note0, verifiedNote) = 0 OrElse verifiedNote.startTick <> 13 OrElse _
    verifiedNote.keyNumber <> 60 OrElse verifiedNote.velocity <> 125 OrElse midi_GetEditableNoteCount() <> 2 Then
    Print "ERROR: planning mutated the model"
    End 1
End If
verifiedNote.startTick = OSE_MAX_MIDI_TICK - 90
If midi_SetEditableNotes(summary, @note0, @verifiedNote, 1) = 0 Then
    End 1
End If
noteSelection_SelectOnly selection, note0
If noteSelection_PrepareEdit(selection, OSE_NOTE_EDIT_DUPLICATE, 0, 120, @plannedNotes(0), 2) <> -1 Then
    Print "ERROR: duplicate accepted a note beyond the MIDI timeline"
    End 1
End If

Print "note selection smoke test passed"
End 0

/' end of note_selection_smoke.bas '/
