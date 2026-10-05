/'
    Project: OpenSesh
    ---------------------------

    File: midi_model_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Exercise the bounded MIDI reader without opening the graphical editor.

    Responsibilities:

        - load a caller-supplied Standard MIDI File
        - print the parsed container and event summary
        - exercise note, track, tempo, key-signature, text, and channel-mix edits
          before a save round trip
        - exercise the bounded undo and redo snapshots
        - preserve same-tick event order and silent track tails through saving
        - rebuild derived state after track removal without retaining deleted events
        - return a failure code when validation rejects the input
    Ownership: Fixture file handles close before load/save; callers supply paths.
    This file intentionally does NOT contain:

        - a GUI event loop
        - audio playback
        - score rendering
'/

#lang "fb"

#include once "../midi_model.bi"

Private Sub test_RoundtripFail(ByVal messageText As String)
    Print "ERROR: "; messageText
    End 1
End Sub


Private Function test_RoundtripBe32(ByVal value As ULong) As String
    Return Chr((value Shr 24) And 255, (value Shr 16) And 255, _
        (value Shr 8) And &HFF, value And &HFF)
End Function


Private Function test_OrderedTrack(ByVal firstVelocity As Integer) As String
    ' Program setup must precede the notes. Sustain changes intentionally
    ' appear on opposite sides of same-tick releases. Equal-key onsets have
    ' different velocities and FIFO durations, making reordered notes visible.
    Return Chr(0, &HFF, 3, 1) + "T" + Chr(0, &HFF, 1, 1) + "X" + _
        Chr(0, &HC0, 42, 0, &H90, 60, firstVelocity, 0, &H90, 60, 99) + _
        Chr(120, &HB0, 64, 127, 0, &H80, 60, 0, 0, &H90, 60, 88) + _
        Chr(120, &H80, 60, 0, 0, &HB0, 64, 0, 120, &H80, 60, 0) + _
        Chr(&H8C, &H18, &HFF, &H2F, 0)
End Function


Private Function test_OrderedImage(ByVal firstVelocity As Integer) As String
    Dim As String trackData = test_OrderedTrack(firstVelocity)
    ' The note track ends at 1920; an entirely silent second track ends at 2400.
    Dim As String silentTrack = Chr(&H92, &H60, &HFF, &H2F, 0)
    Return "MThd" + test_RoundtripBe32(6) + Chr(0, 1, 0, 2, 1, &HE0) + _
        "MTrk" + test_RoundtripBe32(Len(trackData)) + trackData + _
        "MTrk" + test_RoundtripBe32(Len(silentTrack)) + silentTrack
End Function


Private Sub test_AssertOrderedImage( _
    ByRef summary As MidiSummary, _
    ByVal firstVelocity As Integer, _
    ByVal operationText As String _
)
    Dim As String serializedData
    If midi_SerializeDocument(summary, serializedData) = 0 OrElse _
        serializedData <> test_OrderedImage(firstVelocity) Then _
        test_RoundtripFail operationText + " changed event order or track tails"
End Sub


Private Sub test_EventOrderAndTrackTails(ByVal fixtureFilename As String)
    Dim As String fixtureData = test_OrderedImage(71)
    Dim As Integer fileNumber = FreeFile()
    If Open(fixtureFilename For Output Access Write As #fileNumber) <> 0 Then _
        test_RoundtripFail "could not create event-order fixture"
    Close #fileNumber
    If Open(fixtureFilename For Binary Access Write As #fileNumber) <> 0 Then _
        test_RoundtripFail "could not reopen event-order fixture"
    If Put(#fileNumber, 1, fixtureData) <> 0 Then
        Close #fileNumber
        test_RoundtripFail "could not write event-order fixture"
    End If
    Close #fileNumber

    Dim As MidiSummary orderedSummary
    If midi_LoadSummary(orderedSummary, fixtureFilename) = 0 Then _
        test_RoundtripFail "could not load event-order fixture"
    test_AssertOrderedImage orderedSummary, 71, "Import/save"

    ' A caller may supply a fresh note value; ordering belongs to the model.
    Dim As MidiEditableNote editedNote
    editedNote.trackIndex = 0
    editedNote.startTick = 0
    editedNote.durationTicks = 120
    editedNote.channel = 0
    editedNote.keyNumber = 60
    editedNote.velocity = 75
    If midi_CaptureHistory(orderedSummary) = 0 OrElse _
        midi_SetEditableNote(orderedSummary, 0, editedNote) = 0 Then _
        test_RoundtripFail "could not edit ordered note"
    test_AssertOrderedImage orderedSummary, 75, "Note edit"
    If midi_Undo(orderedSummary) = 0 Then
        test_RoundtripFail "ordered note undo failed"
    End If
    test_AssertOrderedImage orderedSummary, 71, "Undo"
    If midi_Redo(orderedSummary) = 0 Then
        test_RoundtripFail "ordered note redo failed"
    End If
    test_AssertOrderedImage orderedSummary, 75, "Redo"
    If midi_Undo(orderedSummary) = 0 Then
        test_RoundtripFail "second ordered undo failed"
    End If

    Dim As Integer noteIndices(0 To 0) = {0}
    Dim As MidiEditableNote editedNotes(0 To 0)
    editedNotes(0).trackIndex = 0
    editedNotes(0).startTick = 0
    editedNotes(0).durationTicks = 120
    editedNotes(0).channel = 0
    editedNotes(0).keyNumber = 60
    editedNotes(0).velocity = 75
    If midi_PrepareHistory(orderedSummary) = 0 OrElse _
        midi_SetEditableNotes(orderedSummary, @noteIndices(0), _
            @editedNotes(0), 1) = 0 Then _
        test_RoundtripFail "ordered batch edit failed"
    test_AssertOrderedImage orderedSummary, 75, "Batch edit"
    If midi_CancelPreparedHistory(orderedSummary) = 0 Then _
        test_RoundtripFail "ordered batch cancellation failed"
    test_AssertOrderedImage orderedSummary, 71, "Cancelled edit"

    If midi_SaveDocument(orderedSummary, fixtureFilename) = 0 OrElse _
        midi_LoadSummary(orderedSummary, fixtureFilename) = 0 Then _
        test_RoundtripFail "ordered file did not save/reload"
    Dim As Integer expectedVelocities(0 To 2) = {71, 99, 88}
    Dim As ULongInt expectedStarts(0 To 2) = {0, 0, 120}
    Dim As ULongInt expectedDurations(0 To 2) = {120, 240, 240}
    If midi_GetEditableNoteCount() <> 3 Then _
        test_RoundtripFail "ordered roundtrip changed the note count"
    For noteIndex As Integer = 0 To 2
        Dim As MidiEditableNote noteData
        If midi_GetEditableNote(noteIndex, noteData) = 0 OrElse _
            noteData.velocity <> expectedVelocities(noteIndex) OrElse _
            noteData.startTick <> expectedStarts(noteIndex) OrElse _
            noteData.durationTicks <> expectedDurations(noteIndex) Then _
            test_RoundtripFail "roundtrip reordered overlapping note ownership"
    Next
    If orderedSummary.tracks(0).endTick <> 1920 OrElse _
        orderedSummary.tracks(1).endTick <> 2400 OrElse _
        orderedSummary.durationTicks <> 2400 Then _
        test_RoundtripFail "roundtrip shortened trailing or entirely silent track"

    If midi_AddEditableNote(orderedSummary, 0, 3000, 120, 64, 0, 90) < 0 OrElse _
        midi_SaveDocument(orderedSummary, fixtureFilename) = 0 OrElse _
        midi_LoadSummary(orderedSummary, fixtureFilename) = 0 OrElse _
        orderedSummary.tracks(0).endTick <> 3120 Then _
        test_RoundtripFail "new note extended beyond serialized end-of-track"

    ' Fresh notes have no source ordinals. Preserve insertion order for equal
    ' onsets and emit setup before them without reversing FIFO note ownership.
    If midi_NewDocument(orderedSummary) = 0 OrElse _
        midi_AddChannelEvent(orderedSummary, 0, 0, 0, &HC0, 42, 0) < 0 OrElse _
        midi_AddEditableNote(orderedSummary, 0, 0, 120, 60, 0, 71) < 0 OrElse _
        midi_AddEditableNote(orderedSummary, 0, 0, 240, 60, 0, 99) < 0 Then _
        test_RoundtripFail "generated ordered document could not be created"
    Dim As String generatedData
    Dim As String generatedTrack = Chr(0, &HC0, 42, 0, &H90, 60, 71, _
        0, &H90, 60, 99, 120, &H80, 60, 0, 120, &H80, 60, 0, _
        0, &HFF, &H2F, 0)
    Dim As String expectedGenerated = "MThd" + test_RoundtripBe32(6) + _
        Chr(0, 0, 0, 1, 1, &HE0) + "MTrk" + _
        test_RoundtripBe32(Len(generatedTrack)) + generatedTrack
    If midi_SerializeDocument(orderedSummary, generatedData) = 0 OrElse _
        generatedData <> expectedGenerated Then _
        test_RoundtripFail "generated same-tick notes or setup changed order"

    If Kill(fixtureFilename) <> 0 Then _
        test_RoundtripFail "event-order fixture cleanup failed"
    Print "same_tick_order_roundtrip=ok track_tail_roundtrip=ok"
End Sub


Private Sub test_AssertDerivedState( _
    ByRef actual As MidiSummary, _
    ByRef expected As MidiSummary, _
    ByVal operationText As String _
)
    If actual.trackCount <> expected.trackCount OrElse _
        actual.noteCount <> expected.noteCount OrElse _
        actual.preservedEventCount <> expected.preservedEventCount OrElse _
        actual.durationTicks <> expected.durationTicks OrElse _
        actual.tempoCount <> expected.tempoCount OrElse _
        actual.timeSignatureCount <> expected.timeSignatureCount OrElse _
        actual.keySignatureCount <> expected.keySignatureCount OrElse _
        actual.tempoMicrosecondsPerQuarter <> expected.tempoMicrosecondsPerQuarter OrElse _
        actual.documentTitle <> expected.documentTitle OrElse _
        actual.copyrightText <> expected.copyrightText OrElse _
        actual.lyricText <> expected.lyricText OrElse _
        actual.markerText <> expected.markerText Then _
        test_RoundtripFail operationText + " changed derived document state"
    For pointIndex As Integer = 0 To expected.tempoCount - 1
        If actual.tempoMap(pointIndex).tick <> expected.tempoMap(pointIndex).tick OrElse _
            actual.tempoMap(pointIndex).microsecondsPerQuarter <> _
            expected.tempoMap(pointIndex).microsecondsPerQuarter Then _
            test_RoundtripFail operationText + " changed a tempo point"
    Next
    For pointIndex As Integer = 0 To expected.timeSignatureCount - 1
        If actual.timeSignatureMap(pointIndex).tick <> _
            expected.timeSignatureMap(pointIndex).tick OrElse _
            actual.timeSignatureMap(pointIndex).numerator <> _
            expected.timeSignatureMap(pointIndex).numerator OrElse _
            actual.timeSignatureMap(pointIndex).denominatorPower <> _
            expected.timeSignatureMap(pointIndex).denominatorPower OrElse _
            actual.timeSignatureMap(pointIndex).clocksPerMetronome <> _
            expected.timeSignatureMap(pointIndex).clocksPerMetronome OrElse _
            actual.timeSignatureMap(pointIndex).thirtySecondNotesPerQuarter <> _
            expected.timeSignatureMap(pointIndex).thirtySecondNotesPerQuarter Then _
            test_RoundtripFail operationText + " changed a time signature"
    Next
    For pointIndex As Integer = 0 To expected.keySignatureCount - 1
        If actual.keySignatureMap(pointIndex).tick <> _
            expected.keySignatureMap(pointIndex).tick OrElse _
            actual.keySignatureMap(pointIndex).sharpsFlats <> _
            expected.keySignatureMap(pointIndex).sharpsFlats OrElse _
            actual.keySignatureMap(pointIndex).minor <> _
            expected.keySignatureMap(pointIndex).minor Then _
            test_RoundtripFail operationText + " changed a key signature"
    Next
    For channelIndex As Integer = 0 To 15
        If actual.channelProgram(channelIndex) <> expected.channelProgram(channelIndex) OrElse _
            actual.channelVolume(channelIndex) <> expected.channelVolume(channelIndex) OrElse _
            actual.channelExpression(channelIndex) <> expected.channelExpression(channelIndex) OrElse _
            actual.channelPan(channelIndex) <> expected.channelPan(channelIndex) OrElse _
            actual.channelChorus(channelIndex) <> expected.channelChorus(channelIndex) OrElse _
            actual.channelReverb(channelIndex) <> expected.channelReverb(channelIndex) OrElse _
            actual.channelPitchBend(channelIndex) <> expected.channelPitchBend(channelIndex) Then _
            test_RoundtripFail operationText + " changed channel state"
    Next
    For trackIndex As Integer = 0 To expected.trackCount - 1
        If actual.tracks(trackIndex).name <> expected.tracks(trackIndex).name Then _
            test_RoundtripFail operationText + " changed a track name"
    Next
    If Abs(midi_TicksToSeconds(actual, actual.durationTicks) - _
        midi_TicksToSeconds(expected, expected.durationTicks)) > 0.0000001 Then _
        test_RoundtripFail operationText + " changed playback timing"
End Sub


Private Sub test_CheckRemovedTrackHistory( _
    ByRef summary As MidiSummary, _
    ByRef originalSummary As MidiSummary, _
    ByRef originalData As String, _
    ByVal fixtureFilename As String _
)
    Dim As MidiSummary removedSummary = summary
    Dim As String removedData
    Dim As String restoredData
    If midi_SerializeDocument(summary, removedData) = 0 OrElse _
        midi_Undo(summary) = 0 OrElse _
        midi_SerializeDocument(summary, restoredData) = 0 OrElse _
        restoredData <> originalData Then _
        test_RoundtripFail "track-removal undo changed source events"
    test_AssertDerivedState summary, originalSummary, "Track-removal undo"
    If midi_Redo(summary) = 0 OrElse _
        midi_SerializeDocument(summary, restoredData) = 0 OrElse _
        restoredData <> removedData Then _
        test_RoundtripFail "track-removal redo changed source events"
    test_AssertDerivedState summary, removedSummary, "Track-removal redo"
    If midi_SaveDocument(summary, fixtureFilename) = 0 OrElse _
        midi_LoadSummary(summary, fixtureFilename) = 0 Then _
        test_RoundtripFail "removed-track document did not save/reload"
    test_AssertDerivedState summary, removedSummary, "Track-removal save/reload"
End Sub


Private Sub test_RemovedTrackCaches(ByVal fixtureFilename As String)
    Dim As MidiSummary removalSummary
    If midi_NewDocument(removalSummary) = 0 OrElse _
        midi_SetTrackName(removalSummary, 0, "Retained") = 0 OrElse _
        midi_SetInitialTempoBpm(removalSummary, 150) = 0 OrElse _
        midi_SetTimeSignaturePoint(removalSummary, 0, 3, 2) = 0 OrElse _
        midi_SetKeySignaturePoint(removalSummary, 0, 2, 0) = 0 OrElse _
        midi_SetChannelMix(removalSummary, 0, 90, 20) = 0 OrElse _
        midi_SetChannelEffects(removalSummary, 0, 12, 24) = 0 OrElse _
        midi_AddChannelEvent(removalSummary, 0, 0, 0, &HC0, 5, 0) < 0 OrElse _
        midi_AddChannelEvent(removalSummary, 0, 0, 0, &HB0, 11, 80) < 0 OrElse _
        midi_AddChannelEvent(removalSummary, 0, 0, 0, &HE0, 52, 66) < 0 OrElse _
        midi_AddEditableNote(removalSummary, 0, 0, 1440, 60, 0, 90) < 0 OrElse _
        midi_AddTrack(removalSummary) <> 1 Then _
        test_RoundtripFail "retained initial settings could not be created"
    If midi_AddTempoPointBpm(removalSummary, 1, 480, 60) < 0 OrElse _
        midi_AddTimeSignaturePoint(removalSummary, 1, 480, 5, 3) < 0 OrElse _
        midi_AddKeySignaturePoint(removalSummary, 1, 480, -3, 1) < 0 OrElse _
        midi_AddTextEvent(removalSummary, 1, 0, &H01, "Deleted title") < 0 OrElse _
        midi_AddTextEvent(removalSummary, 1, 0, &H02, "Deleted copyright") < 0 OrElse _
        midi_AddTextEvent(removalSummary, 1, 0, &H05, "Deleted lyrics") < 0 OrElse _
        midi_AddTextEvent(removalSummary, 1, 0, &H06, "Deleted marker") < 0 Then _
        test_RoundtripFail "removed-track metadata could not be created"
    For channelIndex As Integer = 0 To 1
        If midi_AddChannelEvent(removalSummary, 1, 480, channelIndex, &HC0, 42, 0) < 0 OrElse _
            midi_AddChannelEvent(removalSummary, 1, 480, channelIndex, &HB0, 7, 25) < 0 OrElse _
            midi_AddChannelEvent(removalSummary, 1, 480, channelIndex, &HB0, 10, 100) < 0 OrElse _
            midi_AddChannelEvent(removalSummary, 1, 480, channelIndex, &HB0, 11, 30) < 0 OrElse _
            midi_AddChannelEvent(removalSummary, 1, 480, channelIndex, &HB0, 93, 70) < 0 OrElse _
            midi_AddChannelEvent(removalSummary, 1, 480, channelIndex, &HB0, 91, 80) < 0 OrElse _
            midi_AddChannelEvent(removalSummary, 1, 480, channelIndex, &HE0, 16, 78) < 0 Then _
            test_RoundtripFail "removed-track channel events could not be created"
    Next
    Dim As MidiSummary originalSummary = removalSummary
    Dim As String originalData
    If midi_SerializeDocument(removalSummary, originalData) = 0 OrElse _
        midi_CaptureHistory(removalSummary) = 0 OrElse _
        midi_RemoveTrack(removalSummary, 1) = 0 Then _
        test_RoundtripFail "metadata track could not be removed"
    If removalSummary.tempoCount <> 1 OrElse _
        removalSummary.tempoMap(0).microsecondsPerQuarter <> 400000 OrElse _
        removalSummary.timeSignatureCount <> 1 OrElse _
        removalSummary.timeSignatureMap(0).numerator <> 3 OrElse _
        removalSummary.keySignatureCount <> 1 OrElse _
        removalSummary.keySignatureMap(0).sharpsFlats <> 2 OrElse _
        Abs(midi_TicksToSeconds(removalSummary, 1440) - 1.2) > 0.0000001 Then _
        test_RoundtripFail "removed track left ghost timing or erased initial settings"
    If removalSummary.documentTitle <> "" OrElse removalSummary.copyrightText <> "" OrElse _
        removalSummary.lyricText <> "" OrElse removalSummary.markerText <> "" OrElse _
        removalSummary.tracks(0).name <> "Retained" OrElse midi_GetTextEventCount() <> 1 Then _
        test_RoundtripFail "removed track left ghost text or erased retained track name"
    If removalSummary.channelProgram(0) <> 5 OrElse removalSummary.channelVolume(0) <> 90 OrElse _
        removalSummary.channelPan(0) <> 20 OrElse removalSummary.channelExpression(0) <> 80 OrElse _
        removalSummary.channelChorus(0) <> 12 OrElse removalSummary.channelReverb(0) <> 24 OrElse _
        removalSummary.channelPitchBend(0) <> 8500 OrElse _
        removalSummary.channelProgram(1) <> 0 OrElse removalSummary.channelVolume(1) <> 127 OrElse _
        removalSummary.channelPan(1) <> 64 OrElse removalSummary.channelExpression(1) <> 127 OrElse _
        removalSummary.channelChorus(1) <> 0 OrElse removalSummary.channelReverb(1) <> 40 OrElse _
        removalSummary.channelPitchBend(1) <> 8192 OrElse midi_GetChannelEventCount() <> 7 Then _
        test_RoundtripFail "removed-track channel state did not fall back to retained events/defaults"
    test_CheckRemovedTrackHistory removalSummary, originalSummary, originalData, fixtureFilename

    ' Removing the track that owns initial values must synthesize cached
    ' defaults while keeping later changes on the surviving track.
    If midi_NewDocument(removalSummary) = 0 OrElse _
        midi_SetInitialTempoBpm(removalSummary, 75) = 0 OrElse _
        midi_SetTimeSignaturePoint(removalSummary, 0, 5, 3) = 0 OrElse _
        midi_SetKeySignaturePoint(removalSummary, 0, -3, 1) = 0 OrElse _
        midi_SetChannelMix(removalSummary, 0, 40, 100) = 0 OrElse _
        midi_AddTextEvent(removalSummary, 0, 0, &H01, "Old title") < 0 OrElse _
        midi_AddTrack(removalSummary) <> 1 OrElse _
        midi_SetTrackName(removalSummary, 1, "Later changes") = 0 OrElse _
        midi_AddTextEvent(removalSummary, 1, 0, &H01, "Retained title") < 0 OrElse _
        midi_AddEditableNote(removalSummary, 1, 0, 1920, 64, 0, 90) < 0 OrElse _
        midi_AddTempoPointBpm(removalSummary, 1, 1440, 90) < 0 OrElse _
        midi_AddTempoPointBpm(removalSummary, 1, 960, 60) < 0 OrElse _
        midi_AddTimeSignaturePoint(removalSummary, 1, 960, 7, 3) < 0 OrElse _
        midi_AddKeySignaturePoint(removalSummary, 1, 960, 4, 1) < 0 Then _
        test_RoundtripFail "initial-owner removal fixture could not be created"
    originalSummary = removalSummary
    If midi_SerializeDocument(removalSummary, originalData) = 0 OrElse _
        midi_CaptureHistory(removalSummary) = 0 OrElse _
        midi_RemoveTrack(removalSummary, 0) = 0 Then _
        test_RoundtripFail "initial-value owner could not be removed"
    If removalSummary.tempoCount <> 3 OrElse removalSummary.tempoMap(0).tick <> 0 OrElse _
        removalSummary.tempoMap(0).microsecondsPerQuarter <> 500000 OrElse _
        removalSummary.tempoMap(1).tick <> 960 OrElse _
        removalSummary.timeSignatureCount <> 2 OrElse _
        removalSummary.timeSignatureMap(0).numerator <> 4 OrElse _
        removalSummary.timeSignatureMap(0).denominatorPower <> 2 OrElse _
        removalSummary.timeSignatureMap(1).numerator <> 7 OrElse _
        removalSummary.keySignatureCount <> 2 OrElse _
        removalSummary.keySignatureMap(0).sharpsFlats <> 0 OrElse _
        removalSummary.keySignatureMap(0).minor <> 0 OrElse _
        removalSummary.keySignatureMap(1).sharpsFlats <> 4 OrElse _
        removalSummary.documentTitle <> "Retained title" OrElse _
        removalSummary.preservedEventCount <> 6 OrElse midi_GetChannelEventCount() <> 0 OrElse _
        Abs(midi_TicksToSeconds(removalSummary, 1920) - 2.666666) > 0.0000001 Then _
        test_RoundtripFail "initial-owner removal lost later events or retained deleted defaults"
    test_CheckRemovedTrackHistory removalSummary, originalSummary, originalData, fixtureFilename

    Dim As Integer sourceCountBefore = removalSummary.preservedEventCount
    If midi_SetInitialTempoBpm(removalSummary, 150) = 0 OrElse _
        midi_SetTimeSignaturePoint(removalSummary, 0, 3, 2) = 0 OrElse _
        midi_SetKeySignaturePoint(removalSummary, 0, 2, 0) = 0 OrElse _
        removalSummary.preservedEventCount <> sourceCountBefore + 3 OrElse _
        removalSummary.tempoMap(0).microsecondsPerQuarter <> 400000 OrElse _
        removalSummary.tempoMap(1).microsecondsPerQuarter <> 1000000 OrElse _
        removalSummary.timeSignatureMap(0).numerator <> 3 OrElse _
        removalSummary.keySignatureMap(0).sharpsFlats <> 2 Then _
        test_RoundtripFail "editing synthesized defaults did not create real initial events"
    originalSummary = removalSummary
    If midi_SaveDocument(removalSummary, fixtureFilename) = 0 OrElse _
        midi_LoadSummary(removalSummary, fixtureFilename) = 0 Then _
        test_RoundtripFail "edited defaults did not save/reload"
    test_AssertDerivedState removalSummary, originalSummary, "Edited defaults save/reload"
    If Kill(fixtureFilename) <> 0 Then
        test_RoundtripFail "track-removal fixture cleanup failed"
    End If
    Print "removed_track_cache_roundtrip=ok removed_track_history=ok"
End Sub


Dim As String filename = Trim(Command(1))
If filename = "" Then
    Print "usage: midi_model_smoke.exe <file.mid>"
    End 2
End If

Dim As MidiSummary summary
If midi_LoadSummary(summary, filename) = 0 Then
    Print "ERROR: "; summary.errorText
    End 1
End If

Print "format="; summary.formatNumber
Print "tracks="; summary.trackCount
Print "division="; summary.division
Print "events="; summary.eventCount
Print "notes="; summary.noteCount
Print "preview="; summary.previewCount
Print "tempo_events="; summary.tempoCount
Print "key_events="; summary.keySignatureCount
Print "text_events="; midi_GetTextEventCount()
Print "seconds="; midi_EstimatedSeconds(summary)

Dim As ULongInt timingTick = summary.durationTicks \ 2
Dim As Double timingSeconds = midi_TicksToSeconds(summary, timingTick)
Dim As ULongInt timingRoundTrip = midi_SecondsToTicks(summary, timingSeconds)
Dim As ULongInt timingDifference
If timingRoundTrip >= timingTick Then
    timingDifference = timingRoundTrip - timingTick
Else
    timingDifference = timingTick - timingRoundTrip
End If
If timingDifference > 1 Then
    Print "ERROR: tempo timing conversion drifted by more than one tick"
    End 1
End If
Print "timing_roundtrip_tick="; timingRoundTrip

For trackIndex As Integer = 0 To summary.trackCount - 1
    Print trackIndex + 1; ": "; midi_TrackDisplayName(summary, trackIndex); _
        " events="; summary.tracks(trackIndex).eventCount; _
        " notes="; summary.tracks(trackIndex).noteCount
Next
If midi_KeyDisplayName(0) <> "C-1" OrElse _
    midi_KeyDisplayName(69) <> "A4" OrElse _
    midi_KeyDisplayName(127) <> "G9" OrElse _
    midi_KeyDisplayName(-1) <> "?" OrElse _
    midi_KeyDisplayName(128) <> "?" Then
    Print "ERROR: MIDI key display names are incorrect"
    End 1
End If

' -------------------------------------------------------------------------
' Edit and save round trip
' -------------------------------------------------------------------------

Dim As String saveFilename = Trim(Command(2))
If saveFilename <> "" Then
    Dim As Integer addedTrack = midi_AddTrack(summary)
    If addedTrack < 0 Then
        Print "ERROR: could not add the save-roundtrip track"
        End 1
    End If

    If summary.keySignatureCount <= 0 OrElse _
        summary.keySignatureMap(0).tick <> 0 Then
        Print "ERROR: no usable initial key signature"
        End 1
    End If
    Dim As ULongInt keyTestStep = CULngInt(summary.division)
    If keyTestStep = 0 Then
        keyTestStep = 1
    End If
    Dim As ULongInt keyTestTick = summary.durationTicks
    If summary.durationTicks <= OSE_MAX_MIDI_TICK - keyTestStep Then
        keyTestTick = summary.durationTicks + keyTestStep
    End If
    Dim As Integer keyTestAttempts = 0
    Do
        Dim As Integer keyTickUsed = 0
        For keyIndex As Integer = 0 To summary.keySignatureCount - 1
            If summary.keySignatureMap(keyIndex).tick = keyTestTick Then
                keyTickUsed = 1
                Exit For
            End If
        Next
        If keyTickUsed = 0 Then
            Exit Do
        End If
        If keyTestTick <= OSE_MAX_MIDI_TICK - keyTestStep Then
            keyTestTick += keyTestStep
        ElseIf keyTestTick > 0 Then
            keyTestTick -= 1
        Else
            Print "ERROR: no free key-signature test tick"
            End 1
        End If
        keyTestAttempts += 1
        If keyTestAttempts > summary.keySignatureCount + 1 Then
            Print "ERROR: no free key-signature test tick"
            End 1
        End If
    Loop
    Dim As Integer temporaryKey = midi_AddKeySignaturePoint( _
        summary, addedTrack, keyTestTick, -2, 1)
    If temporaryKey < 0 OrElse summary.keySignatureCount <= 1 Then
        Print "ERROR: could not add a temporary key signature"
        End 1
    End If
    Dim As Integer temporaryKeyIndex = -1
    For keyIndex As Integer = 0 To summary.keySignatureCount - 1
        If summary.keySignatureMap(keyIndex).tick = keyTestTick Then
            temporaryKeyIndex = keyIndex
            Exit For
        End If
    Next
    If temporaryKeyIndex <= 0 OrElse _
        midi_SetKeySignaturePoint(summary, temporaryKeyIndex, 3, 0) = 0 OrElse _
        summary.keySignatureMap(temporaryKeyIndex).sharpsFlats <> 3 OrElse _
        summary.keySignatureMap(temporaryKeyIndex).minor <> 0 OrElse _
        midi_RemoveKeySignaturePoint(summary, temporaryKeyIndex) = 0 OrElse _
        summary.keySignatureCount <= 0 Then
        Print "ERROR: could not remove the temporary key signature"
        End 1
    End If

    Dim As MidiTextEventPoint titlePoint
    Dim As Integer titleSourceIndex = -1
    For textIndex As Integer = 0 To midi_GetTextEventCount() - 1
        If midi_GetTextEvent(textIndex, titlePoint) <> 0 AndAlso _
            titlePoint.metaType = &H01 Then
            titleSourceIndex = titlePoint.sourceIndex
            Exit For
        End If
    Next
    If titleSourceIndex >= 0 Then
        titlePoint.textValue = "OpenSesh test"
        If midi_SetTextEvent(summary, titleSourceIndex, titlePoint) = 0 Then
            Print "ERROR: could not update document title"
            End 1
        End If
    ElseIf midi_AddTextEvent(summary, 0, 0, &H01, _
        "OpenSesh test") < 0 Then
        Print "ERROR: could not add document title"
        End 1
    End If

    Dim As MidiTextEventPoint copyrightPoint
    Dim As Integer copyrightSourceIndex = -1
    For textIndex As Integer = 0 To midi_GetTextEventCount() - 1
        If midi_GetTextEvent(textIndex, copyrightPoint) <> 0 AndAlso _
            copyrightPoint.metaType = &H02 Then
            copyrightSourceIndex = copyrightPoint.sourceIndex
            Exit For
        End If
    Next
    If copyrightSourceIndex >= 0 Then
        copyrightPoint.textValue = "GPL test metadata"
        If midi_SetTextEvent(summary, copyrightSourceIndex, copyrightPoint) = 0 Then
            Print "ERROR: could not update copyright metadata"
            End 1
        End If
    ElseIf midi_AddTextEvent(summary, 0, 0, &H02, _
        "GPL test metadata") < 0 Then
        Print "ERROR: could not add copyright metadata"
        End 1
    End If

    Dim As Integer originalTextCount = midi_GetTextEventCount()
    Dim As Integer temporaryText = midi_AddTextEvent(summary, addedTrack, _
        keyTestTick, &H06, "OpenSesh marker")
    If temporaryText < 0 OrElse _
        midi_GetTextEventCount() <> originalTextCount + 1 Then
        Print "ERROR: could not add a temporary text event"
        End 1
    End If
    Dim As MidiTextEventPoint temporaryTextPoint
    If midi_GetTextEvent(midi_GetTextEventCount() - 1, temporaryTextPoint) = 0 Then
        Print "ERROR: could not read the temporary text event"
        End 1
    End If
    temporaryTextPoint.textValue = "Edited marker"
    If midi_SetTextEvent(summary, temporaryTextPoint.sourceIndex, _
        temporaryTextPoint) = 0 OrElse _
        midi_RemoveTextEvent(summary, temporaryTextPoint.sourceIndex) = 0 OrElse _
        midi_GetTextEventCount() <> originalTextCount Then
        Print "ERROR: could not edit and remove the temporary text event"
        End 1
    End If

    Dim As ULongInt editDuration = CULngInt(summary.division) \ 2
    If editDuration = 0 Then
        editDuration = 1
    End If
    Dim As Integer addedNote = midi_AddEditableNote(summary, 0, 0, editDuration, _
        60, 0, 100)
    If addedNote < 0 Then
        Print "ERROR: could not add the save-roundtrip note"
        End 1
    End If
    Dim As MidiEditableNote editedNote
    If midi_GetEditableNote(addedNote, editedNote) = 0 Then
        Print "ERROR: could not read the save-roundtrip note"
        End 1
    End If
    editedNote.startTick = CULngInt(summary.division)
    editedNote.trackIndex = addedTrack
    editedNote.channel = 3
    editedNote.keyNumber = 64
    editedNote.velocity = 90
    editedNote.durationTicks = editDuration * 2
    Dim As ULongInt quantizeGrid = CULngInt(summary.division) \ 4
    If quantizeGrid < 2 Then
        quantizeGrid = 2
    End If
    Dim As ULongInt quantizeOffset = quantizeGrid \ 4
    If quantizeOffset = 0 Then
        quantizeOffset = 1
    End If
    If editedNote.startTick > OSE_MAX_MIDI_TICK - quantizeOffset Then
        Print "ERROR: quantize test tick would overflow"
        End 1
    End If
    editedNote.startTick += quantizeOffset
    If midi_SetEditableNote(summary, addedNote, editedNote) = 0 Then
        Print "ERROR: could not edit the save-roundtrip note"
        End 1
    End If
    Dim As ULongInt expectedQuantizedTick = _
        (editedNote.startTick \ quantizeGrid) * quantizeGrid
    If editedNote.startTick Mod quantizeGrid >= (quantizeGrid + 1) \ 2 Then
        If expectedQuantizedTick <= OSE_MAX_MIDI_TICK - quantizeGrid Then
            expectedQuantizedTick += quantizeGrid
        Else
            expectedQuantizedTick = OSE_MAX_MIDI_TICK
        End If
    End If
    Dim As ULongInt latestStart = _
        OSE_MAX_MIDI_TICK - editedNote.durationTicks
    If expectedQuantizedTick > latestStart Then _
        expectedQuantizedTick = latestStart
    Dim As Integer quantizedNotes = midi_QuantizeTrack( _
        summary, addedTrack, quantizeGrid)
    If quantizedNotes < 1 Then
        Print "ERROR: track quantization did not update the test note"
        End 1
    End If
    If midi_GetEditableNote(addedNote, editedNote) = 0 OrElse _
        editedNote.startTick <> expectedQuantizedTick Then
        Print "ERROR: track quantization produced the wrong note start"
        End 1
    End If
    Print "quantized_notes="; quantizedNotes

    Dim As Integer historyBaselineNotes = summary.noteCount
    If midi_CaptureHistory(summary) = 0 Then
        Print "ERROR: could not capture undo history"
        End 1
    End If
    Dim As Integer historyNote = midi_AddEditableNote(summary, addedTrack, _
        summary.durationTicks, editDuration, 67, 3, 88)
    If historyNote < 0 OrElse midi_Undo(summary) = 0 OrElse _
        summary.noteCount <> historyBaselineNotes Then
        Print "ERROR: undo did not restore the note state"
        End 1
    End If
    If midi_Redo(summary) = 0 OrElse _
        summary.noteCount <> historyBaselineNotes + 1 Then
        Print "ERROR: redo did not restore the edited note state"
        End 1
    End If
    If midi_CaptureHistory(summary) = 0 OrElse _
        midi_RemoveEditableNote(summary, historyNote) = 0 OrElse _
        summary.noteCount <> historyBaselineNotes Then
        Print "ERROR: could not remove the history test note"
        End 1
    End If
    Print "history_roundtrip=ok"
    midi_HistoryClear()
    If midi_Undo(summary) <> 0 OrElse midi_Redo(summary) <> 0 OrElse _
        summary.noteCount <> historyBaselineNotes Then
        Print "ERROR: MIDI history clear retained a stale snapshot"
        End 1
    End If

    Dim As Integer originalTempoCount = summary.tempoCount
    If midi_SetInitialTempoBpm(summary, 96) = 0 Then
        Print "ERROR: could not edit the initial tempo"
        End 1
    End If
    If summary.tempoCount <> originalTempoCount OrElse _
        summary.tempoMap(0).tick <> 0 Then
        Print "ERROR: initial tempo edit changed the tempo-map shape"
        End 1
    End If
    For tempoIndex As Integer = 0 To summary.tempoCount - 1
        If summary.tempoMap(tempoIndex).tick = 0 AndAlso _
            summary.tempoMap(tempoIndex).microsecondsPerQuarter <> 625000 Then
            Print "ERROR: initial tempo edit left a stale tick-zero tempo"
            End 1
        End If
    Next
    If summary.tempoCount > 1 Then
        If midi_SetTempoPointBpm(summary, 1, 100) = 0 Then
            Print "ERROR: could not edit a later tempo point"
            End 1
        End If
    End If

    If midi_SetChannelMix(summary, 0, 101, 33) = 0 Then
        Print "ERROR: could not edit the channel mix"
        End 1
    End If
    Dim As Integer preservedAfterMix = summary.preservedEventCount
    If midi_SetChannelMix(summary, 0, 102, 34) = 0 OrElse _
        summary.preservedEventCount <> preservedAfterMix Then
        Print "ERROR: repeated channel-mix edit was not stable"
        End 1
    End If
    If midi_SetChannelEffects(summary, 0, 22, 55) = 0 Then
        Print "ERROR: could not edit channel chorus or reverb"
        End 1
    End If
    Dim As Integer preservedAfterEffects = summary.preservedEventCount
    If midi_SetChannelEffects(summary, 0, 33, 66) = 0 OrElse _
        summary.preservedEventCount <> preservedAfterEffects Then
        Print "ERROR: repeated channel-effects edit was not stable"
        End 1
    End If

    Dim As String sysexPayload = Chr(&H7D) + Chr(&H10) + Chr(&H20) + Chr(&H30)
    If midi_AddSystemExclusiveEvent(summary, addedTrack, keyTestTick, _
        &HF0, sysexPayload) < 0 Then
        Print "ERROR: could not add the bounded system-exclusive event"
        End 1
    End If
    If midi_AddSystemExclusiveEvent(summary, addedTrack, keyTestTick, _
        &H90, sysexPayload) >= 0 Then
        Print "ERROR: invalid system-exclusive status was accepted"
        End 1
    End If
    If midi_AddSystemExclusiveEvent(summary, addedTrack, keyTestTick, _
        &HF7, Space(OSE_MAX_SYSEX_EVENT_BYTES + 1)) >= 0 Then
        Print "ERROR: oversized system-exclusive payload was accepted"
        End 1
    End If
    Dim As MidiSystemExclusivePoint sysexPoint
    If midi_GetSystemExclusiveEventCount() <= 0 OrElse _
        midi_GetSystemExclusiveEvent( _
            midi_GetSystemExclusiveEventCount() - 1, sysexPoint) = 0 OrElse _
        sysexPoint.statusByte <> &HF0 OrElse _
        sysexPoint.payload <> sysexPayload Then
        Print "ERROR: system-exclusive event could not be read back"
        End 1
    End If

    Dim As Integer initialSystemEventCount = midi_GetSystemEventCount()
    Dim As Integer systemF1Source = midi_AddSystemEvent( _
        summary, addedTrack, keyTestTick, &HF1, 42, 0)
    Dim As Integer systemF2Source = midi_AddSystemEvent( _
        summary, addedTrack, keyTestTick, &HF2, 1, 2)
    Dim As Integer systemF6Source = midi_AddSystemEvent( _
        summary, addedTrack, keyTestTick, &HF6, 0, 0)
    If systemF1Source < 0 OrElse systemF2Source < 0 OrElse _
        systemF6Source < 0 Then
        Print "ERROR: could not add supported system-common events"
        End 1
    End If
    If midi_AddSystemEvent(summary, addedTrack, keyTestTick, &HF8, 0, 0) >= 0 OrElse _
        midi_AddSystemEvent(summary, addedTrack, keyTestTick, &HF1, 128, 0) >= 0 Then
        Print "ERROR: invalid system-common event was accepted"
        End 1
    End If
    Dim As MidiSystemEventPoint systemPoint
    If midi_GetSystemEventCount() <> initialSystemEventCount + 3 OrElse _
        midi_GetSystemEvent(midi_GetSystemEventCount() - 3, systemPoint) = 0 OrElse _
        systemPoint.statusByte <> &HF1 OrElse systemPoint.dataLength <> 1 OrElse _
        systemPoint.data1 <> 42 Then
        Print "ERROR: one-byte system-common event could not be read back"
        End 1
    End If
    If midi_GetSystemEvent(initialSystemEventCount + 1, systemPoint) = 0 OrElse _
        systemPoint.statusByte <> &HF2 OrElse systemPoint.dataLength <> 2 Then
        Print "ERROR: two-byte system-common event could not be read back"
        End 1
    End If
    systemPoint.tick = keyTestTick + CULngInt(summary.division)
    systemPoint.data1 = 3
    systemPoint.data2 = 4
    If midi_SetSystemEvent(summary, systemF2Source, systemPoint) = 0 Then
        Print "ERROR: system-common event edit failed"
        End 1
    End If
    systemPoint.dataLength = 1
    If midi_SetSystemEvent(summary, systemF2Source, systemPoint) <> 0 Then
        Print "ERROR: invalid system-common event edit was accepted"
        End 1
    End If
    If midi_RemoveSystemEvent(summary, systemF6Source) = 0 OrElse _
        midi_GetSystemEventCount() <> initialSystemEventCount + 2 Then
        Print "ERROR: system-common event removal failed"
        End 1
    End If

    Dim As Integer controllerCount = midi_GetControllerPointCount()
    If controllerCount <= 0 Then
        Print "ERROR: imported file has no editable controller points"
        End 1
    End If
    Dim As MidiControllerPoint editedController
    If midi_GetControllerPoint(0, editedController) = 0 Then
        Print "ERROR: could not read an editable controller point"
        End 1
    End If
    Dim As ULongInt editedControllerTick = editedController.tick + _
        CULngInt(summary.division)
    Dim As Integer editedControllerValue = _
        (CInt(editedController.controllerValue) + 17) Mod 128
    editedController.tick = editedControllerTick
    editedController.controllerValue = CUByte(editedControllerValue)
    If midi_SetControllerPoint(summary, editedController.sourceIndex, _
        editedController) = 0 Then
        Print "ERROR: could not edit an imported controller point"
        End 1
    End If

    Dim As Integer temporaryController = midi_AddControllerPoint( _
        summary, addedTrack, summary.durationTicks, 1, 74, 55)
    If temporaryController < 0 Then
        Print "ERROR: could not add a controller point"
        End 1
    End If
    Dim As Integer controllerCountWithTemporary = _
        midi_GetControllerPointCount()
    If midi_RemoveControllerPoint(summary, temporaryController) = 0 OrElse _
        midi_GetControllerPointCount() <> controllerCountWithTemporary - 1 Then
        Print "ERROR: could not remove the temporary controller point"
        End 1
    End If
    Dim As Integer temporaryChannelEvent = midi_AddChannelEvent( _
        summary, addedTrack, summary.durationTicks, 2, &HC0, 17, 0)
    Dim As Integer channelEventCountWithTemporary = midi_GetChannelEventCount()
    If temporaryChannelEvent < 0 OrElse _
        midi_RemoveChannelEvent(summary, temporaryChannelEvent) = 0 OrElse _
        midi_GetChannelEventCount() <> channelEventCountWithTemporary - 1 Then
        Print "ERROR: generic channel-event removal failed"
        End 1
    End If
    Dim As Integer overwriteFile = FreeFile()
    If Open(saveFilename For Output Access Write As #overwriteFile) <> 0 Then
        Print "ERROR: could not create oversized MIDI overwrite fixture"
        End 1
    End If
    Print #overwriteFile, String(16384, "X");
    Close #overwriteFile
    If midi_SaveDocument(summary, saveFilename) = 0 Then
        Print "ERROR: could not save MIDI document"
        End 1
    End If

    Dim As MidiSummary savedSummary
    If midi_LoadSummary(savedSummary, saveFilename) = 0 Then
        Print "ERROR: saved MIDI document did not reload: "; savedSummary.errorText
        End 1
    End If
    If savedSummary.fileSize >= 16384 Then
        Print "ERROR: MIDI save retained stale trailing bytes"
        End 1
    End If
    If savedSummary.noteCount <> summary.noteCount Then
        Print "ERROR: save round trip changed the note count"
        End 1
    End If
    If savedSummary.trackCount <> summary.trackCount Then
        Print "ERROR: save round trip changed the track count"
        End 1
    End If
    If savedSummary.eventCount <> summary.eventCount Then
        Print "ERROR: save round trip changed the normalized event count"
        End 1
    End If
    If savedSummary.preservedEventCount <> summary.preservedEventCount Then
        Print "ERROR: save round trip discarded non-note events"
        End 1
    End If
    If midi_GetSystemExclusiveEventCount() <= 0 OrElse _
        midi_GetSystemExclusiveEvent( _
            midi_GetSystemExclusiveEventCount() - 1, sysexPoint) = 0 OrElse _
        sysexPoint.statusByte <> &HF0 OrElse _
        sysexPoint.payload <> sysexPayload Then
        Print "ERROR: saved system-exclusive event changed"
        End 1
    End If
    If midi_GetSystemEventCount() <> initialSystemEventCount + 2 OrElse _
        midi_GetSystemEvent(midi_GetSystemEventCount() - 2, systemPoint) = 0 OrElse _
        systemPoint.statusByte <> &HF1 OrElse systemPoint.dataLength <> 1 OrElse _
        systemPoint.data1 <> 42 Then
        Print "ERROR: saved system-common event changed"
        End 1
    End If
    If midi_GetSystemEvent(midi_GetSystemEventCount() - 1, systemPoint) = 0 OrElse _
        systemPoint.statusByte <> &HF2 OrElse systemPoint.dataLength <> 2 OrElse _
        systemPoint.tick <> keyTestTick + CULngInt(summary.division) OrElse _
        systemPoint.data1 <> 3 OrElse systemPoint.data2 <> 4 Then
        Print "ERROR: edited system-common event changed"
        End 1
    End If
    If savedSummary.tempoCount <> summary.tempoCount Then
        Print "ERROR: save round trip changed the tempo map"
        End 1
    End If
    For tempoIndex As Integer = 0 To summary.tempoCount - 1
        If savedSummary.tempoMap(tempoIndex).tick <> _
            summary.tempoMap(tempoIndex).tick OrElse _
            savedSummary.tempoMap(tempoIndex).microsecondsPerQuarter <> _
            summary.tempoMap(tempoIndex).microsecondsPerQuarter Then
            Print "ERROR: save round trip changed a tempo point"
            End 1
        End If
    Next
    If savedSummary.timeSignatureCount <> summary.timeSignatureCount Then
        Print "ERROR: save round trip changed the time-signature map"
        End 1
    End If
    For signatureIndex As Integer = 0 To summary.timeSignatureCount - 1
        If savedSummary.timeSignatureMap(signatureIndex).tick <> _
            summary.timeSignatureMap(signatureIndex).tick OrElse _
            savedSummary.timeSignatureMap(signatureIndex).numerator <> _
            summary.timeSignatureMap(signatureIndex).numerator OrElse _
            savedSummary.timeSignatureMap(signatureIndex).denominatorPower <> _
            summary.timeSignatureMap(signatureIndex).denominatorPower Then
            Print "ERROR: save round trip changed a time signature"
            End 1
        End If
    Next
    If savedSummary.keySignatureCount <> summary.keySignatureCount Then
        Print "ERROR: save round trip changed the key-signature map"
        End 1
    End If
    For keyIndex As Integer = 0 To summary.keySignatureCount - 1
        If savedSummary.keySignatureMap(keyIndex).tick <> _
            summary.keySignatureMap(keyIndex).tick OrElse _
            savedSummary.keySignatureMap(keyIndex).sharpsFlats <> _
            summary.keySignatureMap(keyIndex).sharpsFlats OrElse _
            savedSummary.keySignatureMap(keyIndex).minor <> _
            summary.keySignatureMap(keyIndex).minor Then
            Print "ERROR: save round trip changed a key signature"
            End 1
        End If
    Next
    If midi_GetTextEventCount() <> originalTextCount OrElse _
        savedSummary.documentTitle <> summary.documentTitle OrElse _
        savedSummary.copyrightText <> summary.copyrightText OrElse _
        savedSummary.lyricText <> summary.lyricText OrElse _
        savedSummary.markerText <> summary.markerText Then
        Print "ERROR: save round trip changed text metadata"
        End 1
    End If
    If savedSummary.channelProgram(0) <> summary.channelProgram(0) OrElse _
        savedSummary.channelVolume(0) <> summary.channelVolume(0) OrElse _
        savedSummary.channelPan(0) <> summary.channelPan(0) OrElse _
        savedSummary.channelChorus(0) <> summary.channelChorus(0) OrElse _
        savedSummary.channelReverb(0) <> summary.channelReverb(0) OrElse _
        savedSummary.channelExpression(0) <> summary.channelExpression(0) OrElse _
        savedSummary.channelPitchBend(0) <> summary.channelPitchBend(0) Then
        Print "ERROR: save round trip changed channel zero state"
        End 1
    End If
    For channelIndex As Integer = 1 To 15
        If savedSummary.channelProgram(channelIndex) <> _
            summary.channelProgram(channelIndex) OrElse _
            savedSummary.channelVolume(channelIndex) <> _
            summary.channelVolume(channelIndex) OrElse _
            savedSummary.channelExpression(channelIndex) <> _
            summary.channelExpression(channelIndex) OrElse _
            savedSummary.channelPan(channelIndex) <> _
            summary.channelPan(channelIndex) OrElse _
            savedSummary.channelChorus(channelIndex) <> _
            summary.channelChorus(channelIndex) OrElse _
            savedSummary.channelReverb(channelIndex) <> _
            summary.channelReverb(channelIndex) OrElse _
            savedSummary.channelPitchBend(channelIndex) <> _
            summary.channelPitchBend(channelIndex) Then
            Print "ERROR: save round trip changed channel state"
            End 1
        End If
    Next
    Dim As Integer foundEditedNote = 0
    For noteIndex As Integer = 0 To midi_GetEditableNoteCount() - 1
        If midi_GetEditableNote(noteIndex, editedNote) <> 0 Then
            If editedNote.startTick = expectedQuantizedTick AndAlso _
                editedNote.trackIndex = addedTrack AndAlso editedNote.channel = 3 AndAlso _
                editedNote.keyNumber = 64 AndAlso editedNote.velocity = 90 AndAlso _
                editedNote.durationTicks = editDuration * 2 Then
                foundEditedNote = -1
                Exit For
            End If
        End If
    Next
    If foundEditedNote = 0 Then
        Print "ERROR: edited note properties did not survive save"
        End 1
    End If
    Dim As Integer foundEditedController = 0
    Dim As MidiControllerPoint savedController
    For pointIndex As Integer = 0 To midi_GetControllerPointCount() - 1
        If midi_GetControllerPoint(pointIndex, savedController) <> 0 Then
            If savedController.tick = editedControllerTick AndAlso _
                savedController.channel = editedController.channel AndAlso _
                savedController.controllerNumber = _
                    editedController.controllerNumber AndAlso _
                savedController.controllerValue = editedControllerValue Then
                foundEditedController = -1
                Exit For
            End If
        End If
    Next
    If foundEditedController = 0 Then
        Print "ERROR: edited controller point did not survive save"
        End 1
    End If
    Print "save_roundtrip_preserved_events="; savedSummary.preservedEventCount
    Print "save_roundtrip_tracks="; savedSummary.trackCount
    Print "save_roundtrip_notes="; savedSummary.noteCount
    test_EventOrderAndTrackTails saveFilename + ".event-order.mid"
    test_RemovedTrackCaches saveFilename + ".track-removal.mid"
End If

End 0

/' end of midi_model_smoke.bas '/
