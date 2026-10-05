/'
    Project: OpenSesh
    ---------------------------

    File: note_selection.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: noteSelection_* and noteClipboard_* operations with selection and clipboard records.

    Purpose:

        Define the bounded note-selection and internal note-clipboard state
        shared by the score editor and its deterministic tests.

    Responsibilities:

        - retain sorted, unique editable-note indices
        - retain one primary note for property editing and drag anchoring
        - summarize the selected time, track, and pitch range
        - capture selected editable notes into a bounded internal clipboard
        - prepare time-and-track-relative notes for destination paste
        - plan bounded duplicate, quantize, pitch, and velocity edits
        - expose selection operations without depending on GUI state

    This file intentionally does NOT contain:

        - score hit-testing or mouse gesture handling
        - MIDI model mutation
        - operating-system clipboard integration
'/

#ifndef __OSE_NOTE_SELECTION_BI__
#define __OSE_NOTE_SELECTION_BI__

#include once "midi_model.bi"

' The score renderer exposes at most this many editable notes in one frame.
' Matching that limit keeps marquee selection and copy/paste storage bounded.
Const OSE_NOTE_SELECTION_CAPACITY As Integer = 8192

Const OSE_NOTE_EDIT_DUPLICATE As Integer = 0
Const OSE_NOTE_EDIT_QUANTIZE As Integer = 1
Const OSE_NOTE_EDIT_PITCH As Integer = 2
Const OSE_NOTE_EDIT_VELOCITY As Integer = 3

Type NoteSelectionState
    As Integer count
    As Integer primaryNoteIndex
    As Integer noteIndices(0 To OSE_NOTE_SELECTION_CAPACITY - 1)
End Type

Type NoteSelectionSummary
    As Integer count
    As ULongInt startTick
    As ULongInt endTick
    As Integer minimumTrack
    As Integer maximumTrack
    As Integer minimumPitch
    As Integer maximumPitch
End Type

Type NoteClipboardState
    As Integer count
    As ULongInt originTick
    As ULongInt maximumRelativeEnd
    As Integer originTrack
    As Integer maximumRelativeTrack
    As MidiEditableNote notes(0 To OSE_NOTE_SELECTION_CAPACITY - 1)
End Type

Declare Sub noteSelection_Initialize(ByRef state As NoteSelectionState)
Declare Sub noteSelection_Clear(ByRef state As NoteSelectionState)

Declare Function noteSelection_Contains( _
    ByRef state As NoteSelectionState, _
    ByVal noteIndex As Integer _
) As Integer

Declare Function noteSelection_Add( _
    ByRef state As NoteSelectionState, _
    ByVal noteIndex As Integer, _
    ByVal makePrimary As Integer = 0 _
) As Integer

Declare Function noteSelection_Remove( _
    ByRef state As NoteSelectionState, _
    ByVal noteIndex As Integer _
) As Integer

Declare Function noteSelection_SelectOnly( _
    ByRef state As NoteSelectionState, _
    ByVal noteIndex As Integer _
) As Integer

Declare Function noteSelection_Toggle( _
    ByRef state As NoteSelectionState, _
    ByVal noteIndex As Integer _
) As Integer

Declare Sub noteSelection_SynchronizePrimary( _
    ByRef state As NoteSelectionState, _
    ByVal primaryNoteIndex As Integer, _
    ByVal modelNoteCount As Integer _
)

Declare Function noteSelection_Summarize( _
    ByRef state As NoteSelectionState, _
    ByRef summary As NoteSelectionSummary _
) As Integer

Declare Sub noteClipboard_Initialize(ByRef clipboard As NoteClipboardState)

' Prepare a bounded batch without changing the model or clipboard. Returns
' the changed-note count, zero for no change, or -1 for invalid input. The
' caller must discard the entire output on failure and own the undo step.
Declare Function noteSelection_PrepareEdit( _
    ByRef selection As NoteSelectionState, _
    ByVal operation As Integer, ByVal amount As Integer, _
    ByVal gridTicks As ULongInt, _
    ByVal outputNotes As MidiEditableNote Ptr, _
    ByVal outputCapacity As Integer _
) As Integer

' Rejected captures preserve the previous clipboard, including its notes.
Declare Function noteClipboard_Capture( _
    ByRef clipboard As NoteClipboardState, _
    ByRef selection As NoteSelectionState _
) As Integer

Declare Function noteClipboard_PreparePaste( _
    ByRef clipboard As NoteClipboardState, _
    ByVal pasteTick As ULongInt, _
    ByVal pasteTrack As Integer, _
    ByVal documentTrackCount As Integer, _
    ByVal outputNotes As MidiEditableNote Ptr, _
    ByVal outputCapacity As Integer _
) As Integer

#endif

/' end of note_selection.bi '/
