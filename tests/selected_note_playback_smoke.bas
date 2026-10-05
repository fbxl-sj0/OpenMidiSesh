/'
    Project: OpenSesh
    ---------------------------

    File: tests/selected_note_playback_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify that selected notes form an immutable, chronologically ordered
        phrase which the shared transport can play at score tempo and speed.

    Responsibilities:

        - verify empty and stale selections are rejected without stale state
        - verify one selected note starts immediately and retains its duration
        - verify multiple notes are ordered by score time and deterministic ties
        - verify simultaneous notes remain simultaneous
        - verify the complete phrase ending includes sustained notes
        - verify snapshot data survives later document edits
        - verify tempo-map and speed conversion used by the transport

    This file intentionally does NOT contain:

        - a GUI, audio device, or native MIDI endpoint
        - real-time sleeps or nondeterministic clock measurements
'/

#lang "fb"

#include once "../midi_model.bi"
#include once "../note_selection.bi"
#include once "../selected_note_playback.bi"
#include once "../playback_timing.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Function test_Close( _
    ByVal actualValue As Double, _
    ByVal expectedValue As Double _
) As Integer
    Return IIf(Abs(actualValue - expectedValue) <= 0.000001, -1, 0)
End Function


Dim As MidiSummary summary
If midi_NewDocument(summary) = 0 OrElse midi_AddTrack(summary) <> 1 Then _
    test_Fail "could not create the selected-note fixture"

Dim As ULongInt quarterTicks = CULngInt(summary.division)
Dim As Integer lateNote = midi_AddEditableNote( _
    summary, 0, quarterTicks * 4, quarterTicks * 2, 67, 0, 70)
Dim As Integer firstChordHigh = midi_AddEditableNote( _
    summary, 1, quarterTicks, quarterTicks, 64, 1, 90)
Dim As Integer middleNote = midi_AddEditableNote( _
    summary, 0, quarterTicks * 2, quarterTicks \ 2, 65, 0, 80)
Dim As Integer firstChordLow = midi_AddEditableNote( _
    summary, 0, quarterTicks, quarterTicks * 6, 60, 0, 100)
If lateNote <> 0 OrElse firstChordHigh <> 1 OrElse middleNote <> 2 OrElse _
    firstChordLow <> 3 Then test_Fail "could not add deterministic notes"

Dim As NoteSelectionState selection
noteSelection_Initialize selection
Dim As OseSelectedNotePlaybackState playback
selectedNotePlayback_Initialize playback
If playback.count <> 0 OrElse playback.startTick <> 0 OrElse _
    playback.endTick <> 0 Then test_Fail "initialize retained playback state"
If selectedNotePlayback_Capture(playback, selection) <> 0 OrElse _
    playback.count <> 0 Then test_Fail "empty selection was accepted"

' A single selected note begins at the snapshot origin. The application sets
' its transport clock to this exact score time before the first update.
If noteSelection_SelectOnly(selection, middleNote) = 0 OrElse _
    selectedNotePlayback_Capture(playback, selection) = 0 Then _
    test_Fail "single-note capture failed"
If playback.count <> 1 OrElse playback.startTick <> quarterTicks * 2 OrElse _
    playback.endTick <> quarterTicks * 2 + quarterTicks \ 2 Then _
    test_Fail "single-note bounds were wrong"
Dim As MidiEditableNote capturedNote
If selectedNotePlayback_GetNote(playback, 0, capturedNote) = 0 OrElse _
    capturedNote.keyNumber <> 65 OrElse capturedNote.velocity <> 80 Then _
    test_Fail "single-note data was not preserved"
If playbackTiming_ShouldStart(capturedNote.startTick, playback.endTick, _
    playback.startTick, playback.startTick, -1) = 0 Then _
    test_Fail "single selected note did not start on the first update"

' The selection is stored in model-index order, but playback is score-time
' order. The two tick-one notes remain a chord and use deterministic tie rules.
noteSelection_Clear selection
If noteSelection_Add(selection, lateNote, 0) = 0 OrElse _
    noteSelection_Add(selection, firstChordHigh, 0) = 0 OrElse _
    noteSelection_Add(selection, middleNote, 0) = 0 OrElse _
    noteSelection_Add(selection, firstChordLow, -1) = 0 OrElse _
    selectedNotePlayback_Capture(playback, selection) = 0 Then _
    test_Fail "multi-note capture failed"
If playback.count <> 4 OrElse playback.startTick <> quarterTicks OrElse _
    playback.endTick <> quarterTicks * 7 Then _
    test_Fail "multi-note phrase bounds were wrong"
If playback.entries(0).sourceNoteIndex <> firstChordLow OrElse _
    playback.entries(1).sourceNoteIndex <> firstChordHigh OrElse _
    playback.entries(2).sourceNoteIndex <> middleNote OrElse _
    playback.entries(3).sourceNoteIndex <> lateNote Then _
    test_Fail "selected notes were not in deterministic score order"
If playback.entries(0).note.startTick <> _
    playback.entries(1).note.startTick Then _
    test_Fail "simultaneous selected notes were serialized"

' Editing the model after Play Selected Notes must not retime or repitch the
' phrase already heard by the operator.
Dim As MidiEditableNote changedNote
If midi_GetEditableNote(firstChordLow, changedNote) = 0 Then _
    test_Fail "could not read the snapshot mutation fixture"
changedNote.startTick = quarterTicks * 10
changedNote.keyNumber = 72
If midi_SetEditableNote(summary, firstChordLow, changedNote) = 0 Then _
    test_Fail "could not mutate the model after capture"
If playback.entries(0).note.startTick <> quarterTicks OrElse _
    playback.entries(0).note.keyNumber <> 60 Then _
    test_Fail "document mutation changed an active playback snapshot"

' The phrase crosses a real tempo-map change from 120 to 60 BPM. A 4x
' transport reaches the next selected beat in one eighth wall second, then
' keeps the later sustained ending at the slower score tempo.
If midi_AddTempoPointBpm(summary, 0, quarterTicks * 2, 60) < 0 Then _
    test_Fail "could not add the selected-phrase tempo change"
Dim As Double firstSeconds = midi_TicksToSeconds(summary, playback.startTick)
Dim As Double middleSeconds = midi_TicksToSeconds( _
    summary, playback.entries(2).note.startTick)
If Not test_Close(firstSeconds, 0.5) OrElse _
    Not test_Close((middleSeconds - firstSeconds) / 4.0, 0.125) Then _
    test_Fail "tempo or 4x selection timing was wrong"
Dim As Double finalSeconds = midi_TicksToSeconds(summary, playback.endTick)
If Not test_Close(playbackTiming_WallDuration( _
    finalSeconds, firstSeconds, 4.0), 1.375) Then _
    test_Fail "selected phrase duration did not follow playback speed"

Dim As NoteSelectionState staleSelection
noteSelection_Initialize staleSelection
If noteSelection_Add(staleSelection, midi_GetEditableNoteCount(), -1) = 0 Then _
    test_Fail "could not create the stale-index fixture"
If selectedNotePlayback_Capture(playback, staleSelection) <> 0 OrElse _
    playback.count <> 0 OrElse playback.startTick <> 0 OrElse _
    playback.endTick <> 0 Then _
    test_Fail "stale selection retained a previous playback snapshot"
If selectedNotePlayback_GetNote(playback, 0, capturedNote) <> 0 Then _
    test_Fail "out-of-range snapshot access succeeded"

Print "selected_note_playback=ok"
Print "single_note=1 multi_note=4 simultaneous=2 speed=4x immutable=1"
End 0

/' end of tests/selected_note_playback_smoke.bas '/
