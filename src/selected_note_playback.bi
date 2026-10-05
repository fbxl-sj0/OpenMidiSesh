/'
    Project: OpenSesh
    ---------------------------

    File: selected_note_playback.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: selectedNotePlayback_* snapshots with OseSelectedNotePlaybackState/Entry.

    Purpose:

        Define a bounded, immutable snapshot of the notes selected for
        audition through the normal playback engine.

    Responsibilities:

        - copy the current note selection without changing the document
        - retain source-note identity for deterministic ordering
        - order notes by score time while preserving simultaneous notes
        - expose the inclusive playback origin and exclusive ending tick

    This file intentionally does NOT contain:

        - transport clocks, tempo conversion, or playback-speed policy
        - software-synth or native MIDI output calls
        - score selection gestures or GUI commands
'/

#ifndef __OSE_SELECTED_NOTE_PLAYBACK_BI__
#define __OSE_SELECTED_NOTE_PLAYBACK_BI__

#include once "midi_model.bi"
#include once "note_selection.bi"

Type OseSelectedNotePlaybackEntry
    As MidiEditableNote note
    As Integer sourceNoteIndex
End Type

Type OseSelectedNotePlaybackState
    As Integer count
    As ULongInt startTick
    As ULongInt endTick
    As OseSelectedNotePlaybackEntry entries( _
        0 To OSE_NOTE_SELECTION_CAPACITY - 1)
End Type

Declare Sub selectedNotePlayback_Initialize( _
    ByRef state As OseSelectedNotePlaybackState _
)

Declare Function selectedNotePlayback_Capture( _
    ByRef state As OseSelectedNotePlaybackState, _
    ByRef selection As NoteSelectionState _
) As Integer

Declare Function selectedNotePlayback_GetNote( _
    ByRef state As OseSelectedNotePlaybackState, _
    ByVal playbackIndex As Integer, _
    ByRef editableNote As MidiEditableNote _
) As Integer

#endif

/' end of selected_note_playback.bi '/
