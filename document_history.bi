/'
    Project: OpenSesh
    ---------------------------

    File: document_history.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: documentHistory_* operations with OseDocumentHistory.

    Purpose:

        Declare the application-level undo coordinator for MIDI and audio
        document edits.

    Responsibilities:

        - retain chronological edit order across both model domains
        - keep per-model snapshot rings aligned with the shared timeline
        - prepare and cancel failed edits without damaging redo branches
        - route undo and redo to exactly one model domain
        - clear all document history at document boundaries

    This file intentionally does NOT contain:

        - MIDI or audio mutation commands
        - widget refresh behavior
        - dirty-document policy
'/

#ifndef __OSE_DOCUMENT_HISTORY_BI__
#define __OSE_DOCUMENT_HISTORY_BI__

#include once "midi_model.bi"
#include once "audio_tracks.bi"
#include once "history_timeline.bi"

Type OseDocumentHistory
    timeline As OseHistoryTimeline
    As Integer pendingDomain
    As Integer pendingStackWasFull
End Type

Declare Sub documentHistory_Clear(ByRef history As OseDocumentHistory)

Declare Function documentHistory_CaptureMidi( _
    ByRef history As OseDocumentHistory, _
    ByRef summary As MidiSummary _
) As Integer

Declare Function documentHistory_PrepareMidi( _
    ByRef history As OseDocumentHistory, _
    ByRef summary As MidiSummary _
) As Integer

Declare Function documentHistory_CommitMidi( _
    ByRef history As OseDocumentHistory _
) As Integer

Declare Function documentHistory_CancelMidi( _
    ByRef history As OseDocumentHistory, _
    ByRef summary As MidiSummary _
) As Integer

Declare Function documentHistory_CaptureAudio( _
    ByRef history As OseDocumentHistory _
) As Integer

Declare Function documentHistory_PrepareAudio( _
    ByRef history As OseDocumentHistory _
) As Integer

Declare Function documentHistory_CommitAudio( _
    ByRef history As OseDocumentHistory _
) As Integer

Declare Function documentHistory_CancelAudio( _
    ByRef history As OseDocumentHistory _
) As Integer

Declare Function documentHistory_Undo( _
    ByRef history As OseDocumentHistory, _
    ByRef summary As MidiSummary _
) As Integer

Declare Function documentHistory_Redo( _
    ByRef history As OseDocumentHistory, _
    ByRef summary As MidiSummary _
) As Integer

Declare Function documentHistory_UndoCount( _
    ByRef history As OseDocumentHistory _
) As Integer

Declare Function documentHistory_RedoCount( _
    ByRef history As OseDocumentHistory _
) As Integer

#endif

/' end of document_history.bi '/
