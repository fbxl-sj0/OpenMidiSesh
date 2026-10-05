/'
    Project: OpenSesh
    ---------------------------

    File: selected_note_playback.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements selected_note_playback.bi; declarations there define the shared interface.

    Purpose:

        Capture selected editable notes into a deterministic playback
        snapshot that remains valid if the document changes later.

    Responsibilities:

        - reject empty, stale, malformed, or unbounded selections
        - calculate the selected phrase's complete score-time bounds
        - sort copied notes without recursion or unbounded allocation
        - return copied notes to the shared transport engine

    This file intentionally does NOT contain:

        - audio or external MIDI device access
        - transport state, tempo conversion, or wall-clock scheduling
        - mutation of the editable MIDI model
'/

#lang "fb"

#include once "selected_note_playback.bi"

' -------------------------------------------------------------------------
' Snapshot ordering
' -------------------------------------------------------------------------

Private Function selectedNotePlayback_Compare( _
    ByRef leftEntry As OseSelectedNotePlaybackEntry, _
    ByRef rightEntry As OseSelectedNotePlaybackEntry _
) As Integer
    If leftEntry.note.startTick < rightEntry.note.startTick Then
        Return -1
    End If
    If leftEntry.note.startTick > rightEntry.note.startTick Then
        Return 1
    End If
    If leftEntry.note.trackIndex < rightEntry.note.trackIndex Then
        Return -1
    End If
    If leftEntry.note.trackIndex > rightEntry.note.trackIndex Then
        Return 1
    End If
    If leftEntry.note.channel < rightEntry.note.channel Then
        Return -1
    End If
    If leftEntry.note.channel > rightEntry.note.channel Then
        Return 1
    End If
    If leftEntry.note.keyNumber < rightEntry.note.keyNumber Then
        Return -1
    End If
    If leftEntry.note.keyNumber > rightEntry.note.keyNumber Then
        Return 1
    End If
    If leftEntry.sourceNoteIndex < rightEntry.sourceNoteIndex Then
        Return -1
    End If
    If leftEntry.sourceNoteIndex > rightEntry.sourceNoteIndex Then
        Return 1
    End If
    Return 0
End Function


Private Sub selectedNotePlayback_SiftDown( _
    ByRef state As OseSelectedNotePlaybackState, _
    ByVal rootIndex As Integer, _
    ByVal finalIndex As Integer _
)
    While rootIndex <= finalIndex
        Dim As Integer childIndex = rootIndex * 2 + 1
        If childIndex > finalIndex Then
            Exit While
        End If

        If childIndex < finalIndex AndAlso _
            selectedNotePlayback_Compare( _
                state.entries(childIndex), _
                state.entries(childIndex + 1)) < 0 Then
            childIndex += 1
        End If

        If selectedNotePlayback_Compare( _
            state.entries(rootIndex), state.entries(childIndex)) >= 0 Then
            Exit While
        End If

        Swap state.entries(rootIndex), state.entries(childIndex)
        rootIndex = childIndex
    Wend
End Sub


Private Sub selectedNotePlayback_Sort( _
    ByRef state As OseSelectedNotePlaybackState _
)
    If state.count <= 1 Then
        Exit Sub
    End If

    For rootIndex As Integer = state.count \ 2 - 1 To 0 Step -1
        selectedNotePlayback_SiftDown state, rootIndex, state.count - 1
    Next
    For finalIndex As Integer = state.count - 1 To 1 Step -1
        Swap state.entries(0), state.entries(finalIndex)
        selectedNotePlayback_SiftDown state, 0, finalIndex - 1
    Next
End Sub


' -------------------------------------------------------------------------
' Public snapshot operations
' -------------------------------------------------------------------------

Public Sub selectedNotePlayback_Initialize( _
    ByRef state As OseSelectedNotePlaybackState _
)
    state.count = 0
    state.startTick = 0
    state.endTick = 0
End Sub


Public Function selectedNotePlayback_Capture( _
    ByRef state As OseSelectedNotePlaybackState, _
    ByRef selection As NoteSelectionState _
) As Integer
    selectedNotePlayback_Initialize state
    If selection.count <= 0 OrElse _
        selection.count > OSE_NOTE_SELECTION_CAPACITY Then
        Return 0
    End If

    Dim As Integer modelNoteCount = midi_GetEditableNoteCount()
    If modelNoteCount <= 0 Then
        Return 0
    End If

    Dim As ULongInt firstTick = OSE_MAX_MIDI_TICK
    Dim As ULongInt finalTick
    For selectionPosition As Integer = 0 To selection.count - 1
        Dim As Integer sourceNoteIndex = _
            selection.noteIndices(selectionPosition)
        If sourceNoteIndex < 0 OrElse sourceNoteIndex >= modelNoteCount Then
            selectedNotePlayback_Initialize state
            Return 0
        End If

        Dim As MidiEditableNote editableNote
        If midi_GetEditableNote(sourceNoteIndex, editableNote) = 0 OrElse _
            editableNote.durationTicks = 0 OrElse _
            editableNote.startTick > OSE_MAX_MIDI_TICK OrElse _
            editableNote.durationTicks > _
                OSE_MAX_MIDI_TICK - editableNote.startTick OrElse _
            editableNote.trackIndex < 0 OrElse _
            editableNote.trackIndex >= OSE_MAX_MIDI_TRACKS OrElse _
            editableNote.channel > 15 Then
            selectedNotePlayback_Initialize state
            Return 0
        End If

        state.entries(selectionPosition).note = editableNote
        state.entries(selectionPosition).sourceNoteIndex = sourceNoteIndex
        If editableNote.startTick < firstTick Then
            firstTick = editableNote.startTick
        End If
        Dim As ULongInt noteEndTick = _
            editableNote.startTick + editableNote.durationTicks
        If noteEndTick > finalTick Then
            finalTick = noteEndTick
        End If
    Next

    If firstTick > OSE_MAX_MIDI_TICK OrElse finalTick <= firstTick Then
        selectedNotePlayback_Initialize state
        Return 0
    End If

    state.count = selection.count
    state.startTick = firstTick
    state.endTick = finalTick
    selectedNotePlayback_Sort state
    Return -1
End Function


Public Function selectedNotePlayback_GetNote( _
    ByRef state As OseSelectedNotePlaybackState, _
    ByVal playbackIndex As Integer, _
    ByRef editableNote As MidiEditableNote _
) As Integer
    If playbackIndex < 0 OrElse playbackIndex >= state.count OrElse _
        state.count > OSE_NOTE_SELECTION_CAPACITY Then
        Return 0
    End If
    editableNote = state.entries(playbackIndex).note
    Return -1
End Function

/' end of selected_note_playback.bas '/
