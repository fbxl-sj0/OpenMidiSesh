/'
    Project: OpenSesh
    ---------------------------

    File: note_selection.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements note_selection.bi; declarations there define the shared interface.

    Purpose:

        Maintain sorted multi-note selections and a bounded internal
        clipboard independently from the score's GUI gesture state.

    Responsibilities:

        - insert and remove unique note indices while preserving sort order
        - keep a valid primary selection for property dialogs and dragging
        - reconcile legacy single-note assignments with multi-selection state
        - calculate validated time, track, and pitch bounds for a selection
        - copy complete editable-note records and their relative time span
        - translate copied phrases to a validated destination tick and track
        - plan bounded musical edits without mutating the document

    This file intentionally does NOT contain:

        - score coordinates or rendering
        - note insertion, deletion, or movement
        - undo-history capture
'/

#lang "fb"

#include once "note_selection.bi"

' -------------------------------------------------------------------------
' Sorted selection storage
' -------------------------------------------------------------------------

Public Sub noteSelection_Initialize(ByRef state As NoteSelectionState)
    state.count = 0
    state.primaryNoteIndex = -1
End Sub


Public Sub noteSelection_Clear(ByRef state As NoteSelectionState)
    state.count = 0
    state.primaryNoteIndex = -1
End Sub


Private Function noteSelection_FindPosition( _
    ByRef state As NoteSelectionState, _
    ByVal noteIndex As Integer, _
    ByRef insertPosition As Integer _
) As Integer
    Dim As Integer lowPosition = 0
    Dim As Integer highPosition = state.count - 1

    While lowPosition <= highPosition
        Dim As Integer middlePosition = _
            lowPosition + (highPosition - lowPosition) \ 2
        Dim As Integer middleIndex = state.noteIndices(middlePosition)
        If middleIndex = noteIndex Then
            insertPosition = middlePosition
            Return -1
        ElseIf middleIndex < noteIndex Then
            lowPosition = middlePosition + 1
        Else
            highPosition = middlePosition - 1
        End If
    Wend

    insertPosition = lowPosition
    Return 0
End Function


Public Function noteSelection_Contains( _
    ByRef state As NoteSelectionState, _
    ByVal noteIndex As Integer _
) As Integer
    If noteIndex < 0 OrElse state.count <= 0 OrElse _
        state.count > OSE_NOTE_SELECTION_CAPACITY Then
        Return 0
    End If

    Dim As Integer ignoredPosition
    Return noteSelection_FindPosition(state, noteIndex, ignoredPosition)
End Function


Public Function noteSelection_Add( _
    ByRef state As NoteSelectionState, _
    ByVal noteIndex As Integer, _
    ByVal makePrimary As Integer _
) As Integer
    If noteIndex < 0 OrElse state.count < 0 OrElse _
        state.count > OSE_NOTE_SELECTION_CAPACITY Then
        Return 0
    End If

    Dim As Integer insertPosition
    If noteSelection_FindPosition(state, noteIndex, insertPosition) <> 0 Then
        If makePrimary <> 0 Then
            state.primaryNoteIndex = noteIndex
        End If
        Return -1
    End If
    If state.count >= OSE_NOTE_SELECTION_CAPACITY Then
        Return 0
    End If

    For movePosition As Integer = state.count To insertPosition + 1 Step -1
        state.noteIndices(movePosition) = state.noteIndices(movePosition - 1)
    Next
    state.noteIndices(insertPosition) = noteIndex
    state.count += 1
    If makePrimary <> 0 OrElse state.primaryNoteIndex < 0 Then
        state.primaryNoteIndex = noteIndex
    End If
    Return -1
End Function


Public Function noteSelection_Remove( _
    ByRef state As NoteSelectionState, _
    ByVal noteIndex As Integer _
) As Integer
    If noteIndex < 0 OrElse state.count <= 0 OrElse _
        state.count > OSE_NOTE_SELECTION_CAPACITY Then
        Return 0
    End If

    Dim As Integer removePosition
    If noteSelection_FindPosition(state, noteIndex, removePosition) = 0 Then
        Return 0
    End If

    For movePosition As Integer = removePosition To state.count - 2
        state.noteIndices(movePosition) = state.noteIndices(movePosition + 1)
    Next
    state.count -= 1

    If state.count <= 0 Then
        noteSelection_Clear state
    ElseIf state.primaryNoteIndex = noteIndex Then
        ' The highest remaining index is deterministic and is normally the
        ' most recently appended result after a paste operation.
        state.primaryNoteIndex = state.noteIndices(state.count - 1)
    End If
    Return -1
End Function


Public Function noteSelection_SelectOnly( _
    ByRef state As NoteSelectionState, _
    ByVal noteIndex As Integer _
) As Integer
    noteSelection_Clear state
    Return noteSelection_Add(state, noteIndex, -1)
End Function


Public Function noteSelection_Toggle( _
    ByRef state As NoteSelectionState, _
    ByVal noteIndex As Integer _
) As Integer
    If noteSelection_Contains(state, noteIndex) <> 0 Then
        Return noteSelection_Remove(state, noteIndex)
    End If
    Return noteSelection_Add(state, noteIndex, -1)
End Function


Public Sub noteSelection_SynchronizePrimary( _
    ByRef state As NoteSelectionState, _
    ByVal primaryNoteIndex As Integer, _
    ByVal modelNoteCount As Integer _
)
    If modelNoteCount < 0 OrElse primaryNoteIndex < 0 OrElse _
        primaryNoteIndex >= modelNoteCount Then
        noteSelection_Clear state
        Exit Sub
    End If

    If noteSelection_Contains(state, primaryNoteIndex) = 0 Then
        noteSelection_SelectOnly state, primaryNoteIndex
    Else
        state.primaryNoteIndex = primaryNoteIndex
    End If
End Sub


' -------------------------------------------------------------------------
' Selection bounds
' -------------------------------------------------------------------------

Public Function noteSelection_Summarize( _
    ByRef state As NoteSelectionState, _
    ByRef summary As NoteSelectionSummary _
) As Integer
    summary.count = 0
    summary.startTick = 0
    summary.endTick = 0
    summary.minimumTrack = -1
    summary.maximumTrack = -1
    summary.minimumPitch = -1
    summary.maximumPitch = -1

    If state.count <= 0 OrElse _
        state.count > OSE_NOTE_SELECTION_CAPACITY Then
        Return 0
    End If

    Dim As ULongInt minimumTick = OSE_MAX_MIDI_TICK
    Dim As ULongInt maximumTick
    Dim As Integer minimumTrack = OSE_MAX_MIDI_TRACKS
    Dim As Integer maximumTrack = -1
    Dim As Integer minimumPitch = 128
    Dim As Integer maximumPitch = -1

    For selectionPosition As Integer = 0 To state.count - 1
        Dim As MidiEditableNote editableNote
        If midi_GetEditableNote(state.noteIndices(selectionPosition), _
            editableNote) = 0 Then
            Return 0
        End If
        If editableNote.trackIndex < 0 OrElse _
            editableNote.trackIndex >= OSE_MAX_MIDI_TRACKS OrElse _
            editableNote.keyNumber > 127 OrElse _
            editableNote.startTick > OSE_MAX_MIDI_TICK OrElse _
            editableNote.durationTicks > _
                OSE_MAX_MIDI_TICK - editableNote.startTick Then
            Return 0
        End If

        Dim As ULongInt noteEndTick = editableNote.startTick + _
            editableNote.durationTicks
        If editableNote.startTick < minimumTick Then
            minimumTick = editableNote.startTick
        End If
        If noteEndTick > maximumTick Then
            maximumTick = noteEndTick
        End If
        If editableNote.trackIndex < minimumTrack Then
            minimumTrack = editableNote.trackIndex
        End If
        If editableNote.trackIndex > maximumTrack Then
            maximumTrack = editableNote.trackIndex
        End If
        If editableNote.keyNumber < minimumPitch Then
            minimumPitch = editableNote.keyNumber
        End If
        If editableNote.keyNumber > maximumPitch Then
            maximumPitch = editableNote.keyNumber
        End If
    Next

    If minimumTick > maximumTick OrElse minimumTrack > maximumTrack OrElse _
        minimumPitch > maximumPitch Then
        Return 0
    End If

    summary.count = state.count
    summary.startTick = minimumTick
    summary.endTick = maximumTick
    summary.minimumTrack = minimumTrack
    summary.maximumTrack = maximumTrack
    summary.minimumPitch = minimumPitch
    summary.maximumPitch = maximumPitch
    Return -1
End Function


' -------------------------------------------------------------------------
' Internal note clipboard
' -------------------------------------------------------------------------

Public Sub noteClipboard_Initialize(ByRef clipboard As NoteClipboardState)
    clipboard.count = 0
    clipboard.originTick = 0
    clipboard.maximumRelativeEnd = 0
    clipboard.originTrack = 0
    clipboard.maximumRelativeTrack = 0
End Sub


Public Function noteClipboard_Capture( _
    ByRef clipboard As NoteClipboardState, _
    ByRef selection As NoteSelectionState _
) As Integer
    /'
        Validate the complete selection before replacing any clipboard data.
        A later stale index must not leave new notes paired with old origins.
        Model edits and clipboard capture run synchronously on the editor
        thread, so the validated lookups remain stable during this copy.
    '/
    Dim As NoteSelectionSummary selectedRange
    If noteSelection_Summarize(selection, selectedRange) = 0 Then
        Return 0
    End If
    For selectionPosition As Integer = 0 To selection.count - 1
        midi_GetEditableNote selection.noteIndices(selectionPosition), _
            clipboard.notes(selectionPosition)
    Next

    clipboard.count = selectedRange.count
    clipboard.originTick = selectedRange.startTick
    clipboard.maximumRelativeEnd = selectedRange.endTick - selectedRange.startTick
    clipboard.originTrack = selectedRange.minimumTrack
    clipboard.maximumRelativeTrack = selectedRange.maximumTrack - selectedRange.minimumTrack
    Return -1
End Function


Public Function noteClipboard_PreparePaste( _
    ByRef clipboard As NoteClipboardState, _
    ByVal pasteTick As ULongInt, _
    ByVal pasteTrack As Integer, _
    ByVal documentTrackCount As Integer, _
    ByVal outputNotes As MidiEditableNote Ptr, _
    ByVal outputCapacity As Integer _
) As Integer
    If clipboard.count <= 0 OrElse _
        clipboard.count > OSE_NOTE_SELECTION_CAPACITY OrElse _
        outputNotes = 0 OrElse outputCapacity < clipboard.count Then
        Return 0
    End If
    If documentTrackCount <= 0 OrElse _
        documentTrackCount > OSE_MAX_MIDI_TRACKS Then
        Return 0
    End If
    If pasteTrack < 0 OrElse pasteTrack >= documentTrackCount Then
        Return 0
    End If
    If clipboard.originTrack < 0 OrElse _
        clipboard.originTrack >= OSE_MAX_MIDI_TRACKS OrElse _
        clipboard.maximumRelativeTrack < 0 Then
        Return 0
    End If
    If clipboard.maximumRelativeTrack > documentTrackCount - 1 - pasteTrack Then
        Return 0
    End If
    If clipboard.maximumRelativeEnd > OSE_MAX_MIDI_TICK OrElse _
        pasteTick > OSE_MAX_MIDI_TICK - clipboard.maximumRelativeEnd Then
        Return 0
    End If

    For clipboardPosition As Integer = 0 To clipboard.count - 1
        Dim As MidiEditableNote pastedNote = clipboard.notes(clipboardPosition)
        If pastedNote.trackIndex < clipboard.originTrack OrElse _
            pastedNote.trackIndex >= OSE_MAX_MIDI_TRACKS OrElse _
            pastedNote.startTick < clipboard.originTick Then
            Return 0
        End If

        Dim As Integer relativeTrack = pastedNote.trackIndex - _
            clipboard.originTrack
        If relativeTrack < 0 OrElse _
            relativeTrack > clipboard.maximumRelativeTrack Then
            Return 0
        End If

        Dim As ULongInt relativeTick = pastedNote.startTick - _
            clipboard.originTick
        If relativeTick > clipboard.maximumRelativeEnd OrElse _
            pasteTick > OSE_MAX_MIDI_TICK - relativeTick Then
            Return 0
        End If

        pastedNote.trackIndex = pasteTrack + relativeTrack
        pastedNote.startTick = pasteTick + relativeTick
        outputNotes[clipboardPosition] = pastedNote
    Next

    Return clipboard.count
End Function

' -------------------------------------------------------------------------
' Selection editing plans
' -------------------------------------------------------------------------

Public Function noteSelection_PrepareEdit( _
    ByRef selection As NoteSelectionState, _
    ByVal operation As Integer, ByVal amount As Integer, _
    ByVal gridTicks As ULongInt, _
    ByVal outputNotes As MidiEditableNote Ptr, _
    ByVal outputCapacity As Integer _
) As Integer
    If outputNotes = 0 OrElse selection.count <= 0 OrElse _
        selection.count > OSE_NOTE_SELECTION_CAPACITY OrElse _
        outputCapacity < selection.count Then
        Return -1
    End If
    If operation < OSE_NOTE_EDIT_DUPLICATE OrElse _
        operation > OSE_NOTE_EDIT_VELOCITY Then
        Return -1
    End If
    If gridTicks < 1 OrElse gridTicks > OSE_MAX_MIDI_TICK Then
        Return -1
    End If
    If amount < -127 OrElse amount > 127 Then
        Return -1
    End If
    Dim As NoteSelectionSummary selectedRange
    If noteSelection_Summarize(selection, selectedRange) = 0 Then
        Return -1
    End If

    ' Round the whole phrase span up once. Repeated Ctrl+D then preserves
    ' rhythmic spacing, including the final note's duration.
    Dim As ULongInt duplicateOffset = selectedRange.endTick - selectedRange.startTick
    duplicateOffset = ((duplicateOffset + gridTicks - 1) \ gridTicks) * gridTicks
    Dim As Integer changedCount = 0
    For position As Integer = 0 To selection.count - 1
        Dim As MidiEditableNote originalNote
        If midi_GetEditableNote(selection.noteIndices(position), originalNote) = 0 Then
            Return -1
        End If
        Dim As MidiEditableNote editedNote = originalNote
        Select Case operation
            Case OSE_NOTE_EDIT_DUPLICATE
                If duplicateOffset > OSE_MAX_MIDI_TICK - editedNote.startTick Then
                    Return -1
                End If
                editedNote.startTick += duplicateOffset
            Case OSE_NOTE_EDIT_QUANTIZE
                editedNote.startTick = ((editedNote.startTick + gridTicks \ 2) \ gridTicks) * gridTicks
            Case OSE_NOTE_EDIT_PITCH
                ' GM channel 10 pitches select drum sounds, not musical pitch.
                ' A mixed melody/drum selection must keep its kit assignments.
                If editedNote.channel <> 9 Then
                    Dim As Integer pitch = CInt(editedNote.keyNumber) + amount
                    If pitch < 0 OrElse pitch > 127 Then
                        Return -1
                    End If
                    editedNote.keyNumber = pitch
                End If
            Case OSE_NOTE_EDIT_VELOCITY
                Dim As Integer velocity = CInt(editedNote.velocity) + amount
                If velocity < 1 Then
                    velocity = 1
                End If
                If velocity > 127 Then
                    velocity = 127
                End If
                editedNote.velocity = velocity
        End Select
        If editedNote.startTick > OSE_MAX_MIDI_TICK OrElse _
            editedNote.durationTicks > OSE_MAX_MIDI_TICK - editedNote.startTick Then
            Return -1
        End If
        outputNotes[position] = editedNote
        If editedNote.startTick <> originalNote.startTick OrElse _
            editedNote.keyNumber <> originalNote.keyNumber OrElse _
            editedNote.velocity <> originalNote.velocity Then
            changedCount += 1
        End If
    Next
    Return changedCount
End Function

/' end of note_selection.bas '/
