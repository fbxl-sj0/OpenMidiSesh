/'
    Project: OpenSesh
    ---------------------------

    File: tests/document_history_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Stress the complete chronological MIDI/audio undo coordinator.

    Responsibilities:

        - alternate real MIDI and audio edits beyond the shared history depth
        - prove model snapshots remain aligned after mixed-domain eviction
        - verify exact undo and redo states after every operation
        - cancel a cross-domain edit without destroying the redo timeline
        - verify a new branch clears redo snapshots from both models

    Ownership:

        - the test writes only the WAV fixture path supplied by its runner

    This file intentionally does NOT contain:

        - graphical editor code
        - audio-device access
        - MIDI file serialization
'/

#lang "fb"

#include once "../src/document_history.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Function test_Le16(ByVal value As ULong) As String
    Return Chr(CInt(value And &HFF)) + Chr(CInt((value Shr 8) And &HFF))
End Function


Private Function test_Le32(ByVal value As ULong) As String
    Return Chr(CInt(value And &HFF)) + _
        Chr(CInt((value Shr 8) And &HFF)) + _
        Chr(CInt((value Shr 16) And &HFF)) + _
        Chr(CInt((value Shr 24) And &HFF))
End Function


Private Function test_WriteWave(ByVal filename As String) As Integer
    Const sampleRate As ULong = 8000
    Const dataBytes As ULong = 8
    Dim As String waveData = "RIFF" + test_Le32(36 + dataBytes) + "WAVE" + _
        "fmt " + test_Le32(16) + test_Le16(1) + test_Le16(1) + _
        test_Le32(sampleRate) + test_Le32(sampleRate) + test_Le16(1) + _
        test_Le16(8) + "data" + test_Le32(dataBytes) + Space(dataBytes)
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Write As #fileNumber) <> 0 Then
        Return 0
    End If
    Put #fileNumber, 1, waveData
    Close #fileNumber
    Return -1
End Function


Private Sub test_AssertState( _
    ByRef summary As MidiSummary, _
    ByVal expectedMidiEdits As Integer, _
    ByVal expectedAudioEdits As Integer _
)
    If summary.noteCount <> expectedMidiEdits Then _
        test_Fail "MIDI state does not match the chronological position"

    Dim As OseAudioClip clip
    If audio_GetClip(0, clip) = 0 Then
        test_Fail "audio clip disappeared"
    End If
    Dim As ULongInt expectedTick
    If expectedAudioEdits > 0 Then
        expectedTick = CULngInt(expectedAudioEdits * 2 - 1) * 100
    End If
    If clip.startTick <> expectedTick Then _
        test_Fail "audio state does not match the chronological position"
End Sub


Dim As String waveFilename = Trim(Command(1))
If waveFilename = "" Then
    test_Fail "WAV fixture path is required"
End If
If test_WriteWave(waveFilename) = 0 Then
    test_Fail "WAV fixture creation failed"
End If

Dim As MidiSummary summary
If midi_NewDocument(summary) = 0 Then
    test_Fail "new MIDI document failed"
End If
audio_Clear()
If audio_AddClip(waveFilename, 0, 1000) <> 0 Then _
    test_Fail "initial audio clip could not be added"

Dim As OseDocumentHistory history
documentHistory_Clear history

Const extraEdits As Integer = 4
Const totalEdits As Integer = OSE_HISTORY_TIMELINE_DEPTH + extraEdits
Dim As Integer midiEditCount
Dim As Integer audioEditCount
For editIndex As Integer = 0 To totalEdits - 1
    If (editIndex And &H1) = 0 Then
        If documentHistory_CaptureMidi(history, summary) = 0 OrElse _
            midi_AddEditableNote(summary, 0, CULngInt(editIndex) * 120, _
                60, 48 + editIndex, 0, 100) < 0 Then _
            test_Fail "coordinated MIDI edit failed"
        midiEditCount += 1
    Else
        If documentHistory_CaptureAudio(history) = 0 Then _
            test_Fail "coordinated audio capture failed"
        Dim As OseAudioClip clip
        If audio_GetClip(0, clip) = 0 Then
            test_Fail "audio clip read failed"
        End If
        clip.startTick = CULngInt(editIndex) * 100
        clip.gainPermille = 700 + editIndex
        If audio_SetClip(0, clip) = 0 Then
            test_Fail "audio edit failed"
        End If
        audioEditCount += 1
    End If
Next

If documentHistory_UndoCount(history) <> OSE_HISTORY_TIMELINE_DEPTH OrElse _
    documentHistory_RedoCount(history) <> 0 OrElse _
    midi_HistoryUndoCount() <> OSE_HISTORY_TIMELINE_DEPTH \ 2 OrElse _
    audio_HistoryUndoCount() <> OSE_HISTORY_TIMELINE_DEPTH \ 2 Then _
    test_Fail "mixed-domain eviction left model rings misaligned"
test_AssertState summary, midiEditCount, audioEditCount

For undoIndex As Integer = 0 To OSE_HISTORY_TIMELINE_DEPTH - 1
    Dim As Integer sourceEdit = totalEdits - 1 - undoIndex
    Dim As Integer expectedDomain
    If (sourceEdit And &H1) = 0 Then
        expectedDomain = OSE_HISTORY_DOMAIN_MIDI
        midiEditCount -= 1
    Else
        expectedDomain = OSE_HISTORY_DOMAIN_AUDIO
        audioEditCount -= 1
    End If
    If documentHistory_Undo(history, summary) <> expectedDomain Then _
        test_Fail "undo routed to the wrong model"
    test_AssertState summary, midiEditCount, audioEditCount
Next
If documentHistory_Undo(history, summary) <> OSE_HISTORY_DOMAIN_NONE OrElse _
    midi_HistoryUndoCount() <> 0 OrElse audio_HistoryUndoCount() <> 0 OrElse _
    midi_HistoryRedoCount() <> OSE_HISTORY_TIMELINE_DEPTH \ 2 OrElse _
    audio_HistoryRedoCount() <> OSE_HISTORY_TIMELINE_DEPTH \ 2 Then _
    test_Fail "undo crossed or desynchronized the retained history"

For redoIndex As Integer = 0 To OSE_HISTORY_TIMELINE_DEPTH - 1
    Dim As Integer sourceEdit = extraEdits + redoIndex
    Dim As Integer expectedDomain
    If (sourceEdit And &H1) = 0 Then
        expectedDomain = OSE_HISTORY_DOMAIN_MIDI
        midiEditCount += 1
    Else
        expectedDomain = OSE_HISTORY_DOMAIN_AUDIO
        audioEditCount += 1
    End If
    If documentHistory_Redo(history, summary) <> expectedDomain Then _
        test_Fail "redo routed to the wrong model"
    test_AssertState summary, midiEditCount, audioEditCount
Next
If documentHistory_Redo(history, summary) <> OSE_HISTORY_DOMAIN_NONE Then _
    test_Fail "redo crossed the available branch"

For undoIndex As Integer = 1 To 7
    Dim As Integer appliedDomain = documentHistory_Undo(history, summary)
    If appliedDomain = OSE_HISTORY_DOMAIN_MIDI Then
        midiEditCount -= 1
    ElseIf appliedDomain = OSE_HISTORY_DOMAIN_AUDIO Then
        audioEditCount -= 1
    Else
        test_Fail "branch setup undo failed"
    End If
Next
test_AssertState summary, midiEditCount, audioEditCount

If documentHistory_PrepareAudio(history) = 0 Then _
    test_Fail "branch audio preparation failed"
Dim As OseAudioClip branchClip
If audio_GetClip(0, branchClip) = 0 Then
    test_Fail "branch clip read failed"
End If
branchClip.startTick = 7777
branchClip.gainPermille = 777
If audio_SetClip(0, branchClip) = 0 Then
    test_Fail "branch audio edit failed"
End If
If documentHistory_CommitAudio(history) = 0 Then _
    test_Fail "branch audio commit failed"

If documentHistory_RedoCount(history) <> 0 OrElse _
    midi_HistoryRedoCount() <> 0 OrElse audio_HistoryRedoCount() <> 0 OrElse _
    documentHistory_Redo(history, summary) <> OSE_HISTORY_DOMAIN_NONE Then _
    test_Fail "new branch retained abandoned redo snapshots"
If documentHistory_Undo(history, summary) <> OSE_HISTORY_DOMAIN_AUDIO Then _
    test_Fail "branch undo routed incorrectly"
test_AssertState summary, midiEditCount, audioEditCount
If documentHistory_Redo(history, summary) <> OSE_HISTORY_DOMAIN_AUDIO OrElse _
    audio_GetClip(0, branchClip) = 0 OrElse branchClip.startTick <> 7777 OrElse _
    branchClip.gainPermille <> 777 Then _
    test_Fail "branch redo did not restore the new audio state"

If documentHistory_Undo(history, summary) <> OSE_HISTORY_DOMAIN_AUDIO Then _
    test_Fail "cross-domain cancel setup undo failed"
Dim As Integer cancelUndoCount = documentHistory_UndoCount(history)
Dim As Integer cancelRedoCount = documentHistory_RedoCount(history)
Dim As Integer cancelNoteCount = summary.noteCount
If documentHistory_PrepareMidi(history, summary) = 0 OrElse _
    midi_AddEditableNote(summary, 0, 9000, 120, 79, 4, 88) < 0 Then _
    test_Fail "cross-domain cancelled MIDI edit setup failed"
If documentHistory_Undo(history, summary) <> OSE_HISTORY_DOMAIN_NONE OrElse _
    documentHistory_Redo(history, summary) <> OSE_HISTORY_DOMAIN_NONE Then _
    test_Fail "coordinator allowed history movement during a prepared edit"
If documentHistory_CancelMidi(history, summary) = 0 OrElse _
    summary.noteCount <> cancelNoteCount OrElse _
    documentHistory_UndoCount(history) <> cancelUndoCount OrElse _
    documentHistory_RedoCount(history) <> cancelRedoCount Then _
    test_Fail "cross-domain cancellation changed state or timeline counts"
If documentHistory_Redo(history, summary) <> OSE_HISTORY_DOMAIN_AUDIO OrElse _
    audio_GetClip(0, branchClip) = 0 OrElse branchClip.startTick <> 7777 Then _
    test_Fail "cross-domain cancellation destroyed the audio redo branch"

documentHistory_Clear history
If documentHistory_UndoCount(history) <> 0 OrElse _
    documentHistory_RedoCount(history) <> 0 OrElse _
    midi_HistoryUndoCount() <> 0 OrElse midi_HistoryRedoCount() <> 0 OrElse _
    audio_HistoryUndoCount() <> 0 OrElse audio_HistoryRedoCount() <> 0 Then _
    test_Fail "document history clear retained snapshots"

Print "document_history=ok"
Print "depth="; OSE_HISTORY_TIMELINE_DEPTH; " edits="; totalEdits; _
    " alternating_domains=2 branch_undos=7 cancelled_edits=1"
End 0

/' end of tests/document_history_smoke.bas '/
