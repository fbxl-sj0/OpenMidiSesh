/'
    Project: OpenSesh
    ---------------------------

    File: history_timeline.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: historyTimeline_* operations with OseHistoryTimeline and history-domain constants.

    Purpose:

        Declare the chronological edit-domain timeline used by application undo.

    Responsibilities:

        - retain the last sixteen MIDI/audio edit domains in user order
        - move domain entries between undo and redo without model coupling
        - report the oldest evicted domain so its model snapshot can be dropped

    This file intentionally does NOT contain:

        - MIDI or audio snapshot data
        - application widgets
        - document mutation
'/

#ifndef __OSE_HISTORY_TIMELINE_BI__
#define __OSE_HISTORY_TIMELINE_BI__

Const OSE_HISTORY_TIMELINE_DEPTH As Integer = 16
Const OSE_HISTORY_DOMAIN_NONE As Integer = 0
Const OSE_HISTORY_DOMAIN_MIDI As Integer = 1
Const OSE_HISTORY_DOMAIN_AUDIO As Integer = 2

Type OseHistoryTimeline ' fblint: disable-line FBL910 REASON: This record is process-local state, never a raw serialized or external ABI layout.
    undoDomains(0 To OSE_HISTORY_TIMELINE_DEPTH - 1) As Integer
    As Integer undoStart
    As Integer undoCount
    redoDomains(0 To OSE_HISTORY_TIMELINE_DEPTH - 1) As Integer
    As Integer redoStart
    As Integer redoCount
End Type

Declare Sub historyTimeline_Clear(ByRef timeline As OseHistoryTimeline)

Declare Function historyTimeline_RecordEdit( _
    ByRef timeline As OseHistoryTimeline, _
    ByVal editDomain As Integer, _
    ByRef evictedDomain As Integer _
) As Integer

Declare Function historyTimeline_PeekUndo( _
    ByRef timeline As OseHistoryTimeline _
) As Integer

Declare Function historyTimeline_PeekRedo( _
    ByRef timeline As OseHistoryTimeline _
) As Integer

Declare Function historyTimeline_CommitUndo( _
    ByRef timeline As OseHistoryTimeline _
) As Integer

Declare Function historyTimeline_CommitRedo( _
    ByRef timeline As OseHistoryTimeline _
) As Integer

Declare Function historyTimeline_UndoCount( _
    ByRef timeline As OseHistoryTimeline _
) As Integer

Declare Function historyTimeline_RedoCount( _
    ByRef timeline As OseHistoryTimeline _
) As Integer

#endif

/' end of history_timeline.bi '/
