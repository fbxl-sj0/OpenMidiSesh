/'
    Project: OpenSesh
    ---------------------------

    File: tests/audio_history_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Stress the bounded multi-step audio-clip undo and redo rings.

    Responsibilities:

        - create one small valid PCM WAV clip
        - exceed the configured history depth with distinct clip edits
        - cancel edits at full capacity without evicting history
        - preserve an existing redo branch after a failed prepared edit
        - prove exact undo/redo counts, eviction, branching, and clearing

    Ownership:

        - the test writes only the WAV fixture path supplied by its runner

    This file intentionally does NOT contain:

        - audio-device or sfxlib calls
        - MIDI model state
        - project-container serialization
'/

#lang "fb"

#include once "../src/audio_tracks.bi"

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


Dim As String waveFilename = Trim(Command(1))
If waveFilename = "" Then
    test_Fail "WAV fixture path is required"
End If
If test_WriteWave(waveFilename) = 0 Then
    test_Fail "WAV fixture creation failed"
End If

audio_Clear()
If audio_AddClip(waveFilename, 0, 1000) <> 0 Then _
    test_Fail "initial audio clip could not be added"

Const extraEdits As Integer = 4
Const totalEdits As Integer = OSE_AUDIO_HISTORY_DEPTH + extraEdits
Dim As OseAudioClip editedClip
For editIndex As Integer = 0 To totalEdits - 1
    If audio_CaptureHistory() = 0 OrElse audio_GetClip(0, editedClip) = 0 Then _
        test_Fail "audio history capture failed"
    editedClip.startTick = 1000 + CULngInt(editIndex) * 10
    editedClip.gainPermille = 500 + editIndex
    If audio_SetClip(0, editedClip) = 0 Then
        test_Fail "audio edit failed"
    End If
    Dim As Integer expectedUndoCount = editIndex + 1
    If expectedUndoCount > OSE_AUDIO_HISTORY_DEPTH Then _
        expectedUndoCount = OSE_AUDIO_HISTORY_DEPTH
    If audio_HistoryUndoCount() <> expectedUndoCount OrElse _
        audio_HistoryRedoCount() <> 0 Then _
        test_Fail "audio capture counts exceeded the bounded ring"
Next

Dim As Integer fullUndoCount = audio_HistoryUndoCount()
If audio_PrepareHistory() = 0 OrElse audio_PrepareHistory() <> 0 OrElse _
    audio_GetClip(0, editedClip) = 0 Then _
    test_Fail "audio full-ring cancellation setup failed"
editedClip.startTick = 8888
If audio_SetClip(0, editedClip) = 0 OrElse _
    audio_CancelPreparedHistory() = 0 OrElse _
    audio_GetClip(0, editedClip) = 0 OrElse _
    editedClip.startTick <> 1190 OrElse _
    audio_HistoryUndoCount() <> fullUndoCount OrElse _
    audio_HistoryRedoCount() <> 0 Then _
    test_Fail "cancel at full audio history capacity changed the branch"

For undoIndex As Integer = 1 To OSE_AUDIO_HISTORY_DEPTH
    If audio_Undo() = 0 OrElse audio_GetClip(0, editedClip) = 0 Then _
        test_Fail "bounded audio undo failed"
    Dim As ULongInt expectedTick = 1190 - CULngInt(undoIndex) * 10
    If editedClip.startTick <> expectedTick OrElse _
        audio_HistoryUndoCount() <> OSE_AUDIO_HISTORY_DEPTH - undoIndex OrElse _
        audio_HistoryRedoCount() <> undoIndex Then _
        test_Fail "audio undo restored the wrong ring state"
Next
If editedClip.startTick <> 1030 OrElse audio_Undo() <> 0 Then _
    test_Fail "audio undo crossed the configured history depth"

For redoIndex As Integer = 1 To OSE_AUDIO_HISTORY_DEPTH
    If audio_Redo() = 0 OrElse audio_GetClip(0, editedClip) = 0 Then _
        test_Fail "bounded audio redo failed"
    Dim As ULongInt expectedTick = 1030 + CULngInt(redoIndex) * 10
    If editedClip.startTick <> expectedTick OrElse _
        audio_HistoryUndoCount() <> redoIndex OrElse _
        audio_HistoryRedoCount() <> OSE_AUDIO_HISTORY_DEPTH - redoIndex Then _
        test_Fail "audio redo restored the wrong ring state"
Next
If editedClip.startTick <> 1190 OrElse audio_Redo() <> 0 Then _
    test_Fail "audio redo crossed the available branch"

For undoIndex As Integer = 1 To 8
    If audio_Undo() = 0 Then
        test_Fail "audio branch setup undo failed"
    End If
Next
If audio_GetClip(0, editedClip) = 0 OrElse editedClip.startTick <> 1110 OrElse _
    audio_HistoryRedoCount() <> 8 Then _
    test_Fail "audio branch setup reached the wrong state"
If audio_CaptureHistory() = 0 Then
    test_Fail "audio branch capture failed"
End If
editedClip.startTick = 7777
editedClip.gainPermille = 777
If audio_SetClip(0, editedClip) = 0 Then
    test_Fail "audio branch edit failed"
End If
If audio_HistoryRedoCount() <> 0 OrElse audio_Redo() <> 0 Then _
    test_Fail "new audio branch retained abandoned redo states"
If audio_Undo() = 0 OrElse audio_GetClip(0, editedClip) = 0 OrElse _
    editedClip.startTick <> 1110 Then _
    test_Fail "audio branch undo failed"
If audio_Redo() = 0 OrElse audio_GetClip(0, editedClip) = 0 OrElse _
    editedClip.startTick <> 7777 OrElse editedClip.gainPermille <> 777 Then _
    test_Fail "audio branch redo failed"

If audio_Undo() = 0 OrElse audio_GetClip(0, editedClip) = 0 Then _
    test_Fail "audio cancel redo setup undo failed"
Dim As Integer cancelUndoCount = audio_HistoryUndoCount()
Dim As Integer cancelRedoCount = audio_HistoryRedoCount()
Dim As ULongInt cancelStartTick = editedClip.startTick
If audio_PrepareHistory() = 0 Then _
    test_Fail "audio cancel redo snapshot preparation failed"
If audio_Undo() <> 0 OrElse audio_Redo() <> 0 Then _
    test_Fail "undo or redo ran during a prepared audio edit"
editedClip.startTick = 9999
editedClip.gainPermille = 999
If audio_SetClip(0, editedClip) = 0 OrElse _
    audio_CancelPreparedHistory() = 0 OrElse _
    audio_GetClip(0, editedClip) = 0 OrElse _
    editedClip.startTick <> cancelStartTick OrElse _
    audio_HistoryUndoCount() <> cancelUndoCount OrElse _
    audio_HistoryRedoCount() <> cancelRedoCount Then _
    test_Fail "cancelled audio edit changed state or history counts"
If audio_Redo() = 0 OrElse audio_GetClip(0, editedClip) = 0 OrElse _
    editedClip.startTick <> 7777 OrElse editedClip.gainPermille <> 777 Then _
    test_Fail "cancelled audio edit destroyed the existing redo branch"

audio_HistoryClear()
If audio_HistoryUndoCount() <> 0 OrElse audio_HistoryRedoCount() <> 0 OrElse _
    audio_Undo() <> 0 OrElse audio_Redo() <> 0 Then _
    test_Fail "audio history clear retained a snapshot"

Print "audio_history=ok"
Print "depth="; OSE_AUDIO_HISTORY_DEPTH; " edits="; totalEdits; _
    " branch_undos=8 cancelled_edits=2"
End 0

/' end of tests/audio_history_smoke.bas '/
