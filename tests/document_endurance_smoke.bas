/'
    Project: OpenSesh
    ---------------------------

    File: tests/document_endurance_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Exercise repeated cross-domain document editing against an independent
        serialized-state history oracle.

    Responsibilities:

        - perform 8,192 deterministic MIDI, audio, undo, redo, and cancel steps
        - wrap and evict the shared sixteen-entry history rings many times
        - compare every restored MIDI and audio state with an independent oracle
        - serialize both document domains after every operation
        - reset complete document lifecycles to release retained string storage

    Ownership:

        - the test writes only the WAV fixture path supplied by its runner

    This file intentionally does NOT contain:

        - graphical editor or audio-device access
        - timing-dependent random input
        - a duplicate implementation of the production history rings
'/

#lang "fb"

#include once "../src/document_history.bi"

Const TEST_OPERATION_COUNT As Integer = 8192
Const TEST_RESET_INTERVAL As Integer = 1024
Const TEST_MAX_ACTIVE_NOTES As Integer = 32

Type TestStateSnapshot
    As String midiData
    As String projectData
    As Integer editDomain
End Type

' -------------------------------------------------------------------------
' Failure and fixture helpers
' -------------------------------------------------------------------------

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Function test_Le16(ByVal value As ULong) As String
    ' RIFF fields are raw bytes, not Unicode text.

    Return Chr(CInt(value And &HFF)) + Chr(CInt((value Shr 8) And &HFF))
End Function


Private Function test_Le32(ByVal value As ULong) As String
    Return test_Le16(value And &HFFFF) + _
        test_Le16((value Shr 16) And &HFFFF)
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


Private Function test_NextRandom(ByRef randomState As ULong) As ULong
    randomState = randomState Xor (randomState Shl 13)
    randomState = randomState Xor (randomState Shr 17)
    randomState = randomState Xor (randomState Shl 5)
    Return randomState
End Function

' -------------------------------------------------------------------------
' Independent serialized-state oracle
' -------------------------------------------------------------------------

Private Function test_CaptureState( _
    ByRef summary As MidiSummary, _
    ByVal projectFilename As String, _
    ByRef snapshot As TestStateSnapshot _
) As Integer
    Dim As TestStateSnapshot emptySnapshot
    snapshot = emptySnapshot
    If midi_SerializeDocument(summary, snapshot.midiData) = 0 Then
        Return 0
    End If
    If audio_SerializeProject(projectFilename, "endurance.mid", _
        snapshot.projectData) = 0 Then Return 0
    Return -1
End Function


Private Function test_StatesEqual( _
    ByRef leftState As TestStateSnapshot, _
    ByRef rightState As TestStateSnapshot _
) As Integer
    Return IIf(leftState.midiData = rightState.midiData AndAlso _
        leftState.projectData = rightState.projectData, -1, 0)
End Function


Private Sub test_ClearStack( _
    historyStack() As TestStateSnapshot, _
    ByRef stackCount As Integer _
)
    Dim As TestStateSnapshot emptySnapshot
    For stackIndex As Integer = 0 To OSE_HISTORY_TIMELINE_DEPTH - 1
        historyStack(stackIndex) = emptySnapshot
    Next
    stackCount = 0
End Sub


Private Sub test_PushStack( _
    historyStack() As TestStateSnapshot, _
    ByRef stackCount As Integer, _
    ByRef snapshot As TestStateSnapshot, _
    ByVal editDomain As Integer _
)
    If stackCount >= OSE_HISTORY_TIMELINE_DEPTH Then
        For stackIndex As Integer = 1 To OSE_HISTORY_TIMELINE_DEPTH - 1
            historyStack(stackIndex - 1) = historyStack(stackIndex)
        Next
        stackCount = OSE_HISTORY_TIMELINE_DEPTH - 1
    End If
    historyStack(stackCount) = snapshot
    historyStack(stackCount).editDomain = editDomain
    stackCount += 1
End Sub


Private Sub test_PopStack( _
    historyStack() As TestStateSnapshot, _
    ByRef stackCount As Integer, _
    ByRef snapshot As TestStateSnapshot _
)
    If stackCount <= 0 Then
        test_Fail "oracle stack underflow"
    End If
    stackCount -= 1
    snapshot = historyStack(stackCount)
    Dim As TestStateSnapshot emptySnapshot
    historyStack(stackCount) = emptySnapshot
End Sub


Private Sub test_VerifyState( _
    ByRef summary As MidiSummary, _
    ByRef history As OseDocumentHistory, _
    ByVal projectFilename As String, _
    ByVal expectedUndoCount As Integer, _
    ByVal expectedRedoCount As Integer _
)
    Dim As TestStateSnapshot currentState
    If test_CaptureState(summary, projectFilename, currentState) = 0 Then _
        test_Fail "current state could not be serialized"
    If summary.trackCount < 1 OrElse summary.trackCount > OSE_MAX_MIDI_TRACKS _
        OrElse summary.noteCount <> midi_GetEditableNoteCount() OrElse _
        summary.noteCount < 1 OrElse summary.noteCount > TEST_MAX_ACTIVE_NOTES Then _
        test_Fail "MIDI summary left its bounded model contract"
    If audio_GetCount() <> 1 Then
        test_Fail "audio clip count changed unexpectedly"
    End If
    If documentHistory_UndoCount(history) <> expectedUndoCount OrElse _
        documentHistory_RedoCount(history) <> expectedRedoCount Then _
        test_Fail "production and oracle history counts diverged"
End Sub


Private Sub test_AssertRestoredState( _
    ByRef summary As MidiSummary, _
    ByVal projectFilename As String, _
    ByRef expectedState As TestStateSnapshot _
)
    Dim As TestStateSnapshot actualState
    If test_CaptureState(summary, projectFilename, actualState) = 0 OrElse _
        test_StatesEqual(actualState, expectedState) = 0 Then _
        test_Fail "restored state did not match the independent oracle"
End Sub

' -------------------------------------------------------------------------
' Production-model edit operations
' -------------------------------------------------------------------------

Private Sub test_InitializeDocument( _
    ByRef summary As MidiSummary, _
    ByRef history As OseDocumentHistory, _
    ByVal waveFilename As String _
)
    If midi_NewDocument(summary) = 0 OrElse _
        midi_AddEditableNote(summary, 0, 0, 240, 60, 0, 96) <> 0 Then _
        test_Fail "MIDI lifecycle initialization failed"
    audio_Clear()
    If audio_AddClip(waveFilename, 0, 1000) <> 0 Then _
        test_Fail "audio lifecycle initialization failed"
    documentHistory_Clear history
End Sub


Private Sub test_ApplyMidiEdit( _
    ByRef summary As MidiSummary, _
    ByRef history As OseDocumentHistory, _
    ByVal cycleIndex As Integer, _
    ByVal randomValue As ULong _
)
    If documentHistory_PrepareMidi(history, summary) = 0 Then _
        test_Fail "MIDI history preparation failed"

    Dim As Integer noteCount = midi_GetEditableNoteCount()
    Dim As Integer editMode = CInt(randomValue Mod 5)
    Dim As Integer mutationSucceeded
    Select Case editMode
        Case 0
            If noteCount < TEST_MAX_ACTIVE_NOTES Then
                mutationSucceeded = IIf(midi_AddEditableNote(summary, 0, _
                    CULngInt(cycleIndex) * 17, _
                    30 + CInt(randomValue Mod 451), _
                    24 + CInt(randomValue Mod 84), _
                    CInt(randomValue And 15), _
                    32 + CInt(randomValue Mod 96)) >= 0, -1, 0) ' fblint: disable-line FBL406 REASON: randomValue is unsigned.
            Else
                editMode = 1
            End If
        Case 2
            If noteCount > 1 Then
                mutationSucceeded = midi_RemoveEditableNote(summary, _
                    randomValue Mod noteCount)
            Else
                editMode = 1
            End If
        Case 3
            mutationSucceeded = midi_SetTrackName(summary, 0, _
                "Endurance track " + LTrim(Str(cycleIndex)))
        Case 4
            mutationSucceeded = midi_SetInitialTempoBpm(summary, _
                40 + ((cycleIndex * 7) Mod 201))
        Case Else
            ' Mode 1 and capacity fallbacks share the note-edit path below.
            If editMode <> 1 Then _
                test_Fail "random MIDI edit selector left its bounded range"
    End Select

    If editMode = 1 Then
        Dim As Integer noteIndex = randomValue Mod noteCount
        Dim As MidiEditableNote editableNote
        If midi_GetEditableNote(noteIndex, editableNote) = 0 Then _
            test_Fail "MIDI edit note lookup failed"
        editableNote.startTick = (CULngInt(cycleIndex) * 37 + randomValue) _
            Mod 200000
        editableNote.durationTicks = 30 + (randomValue Mod 931)
        editableNote.keyNumber = 24 + (randomValue Mod 84)
        editableNote.channel = randomValue Mod 16
        editableNote.velocity = 32 + (randomValue Mod 96)
        mutationSucceeded = midi_SetEditableNote(summary, noteIndex, editableNote)
    End If

    If mutationSucceeded = 0 OrElse _
        documentHistory_CommitMidi(history) = 0 Then _
        test_Fail "MIDI endurance edit failed"
End Sub


Private Sub test_ApplyAudioEdit( _
    ByRef history As OseDocumentHistory, _
    ByVal randomValue As ULong _
)
    If documentHistory_PrepareAudio(history) = 0 Then _
        test_Fail "audio history preparation failed"
    Dim As OseAudioClip clip
    If audio_GetClip(0, clip) = 0 Then
        test_Fail "audio edit lookup failed"
    End If
    clip.startTick = (clip.startTick + 1 + (randomValue Mod 1000)) Mod 200000
    clip.gainPermille = (clip.gainPermille + 1 + _
        (randomValue Mod 997)) Mod 1001
    If audio_SetClip(0, clip) = 0 OrElse _
        documentHistory_CommitAudio(history) = 0 Then _
        test_Fail "audio endurance edit failed"
End Sub


Private Sub test_CancelMidiEdit( _
    ByRef summary As MidiSummary, _
    ByRef history As OseDocumentHistory, _
    ByVal projectFilename As String, _
    ByVal cycleIndex As Integer _
)
    Dim As TestStateSnapshot beforeState
    If test_CaptureState(summary, projectFilename, beforeState) = 0 OrElse _
        documentHistory_PrepareMidi(history, summary) = 0 OrElse _
        midi_AddEditableNote(summary, 0, CULngInt(cycleIndex) * 19, _
            120, 72, 3, 88) < 0 OrElse _
        documentHistory_CancelMidi(history, summary) = 0 Then _
        test_Fail "cancelled MIDI edit failed"
    test_AssertRestoredState summary, projectFilename, beforeState
End Sub


Private Sub test_CancelAudioEdit( _
    ByRef summary As MidiSummary, _
    ByRef history As OseDocumentHistory, _
    ByVal projectFilename As String _
)
    Dim As TestStateSnapshot beforeState
    If test_CaptureState(summary, projectFilename, beforeState) = 0 OrElse _
        documentHistory_PrepareAudio(history) = 0 Then _
        test_Fail "cancelled audio edit preparation failed"
    Dim As OseAudioClip clip
    If audio_GetClip(0, clip) = 0 Then
        test_Fail "cancelled audio lookup failed"
    End If
    clip.startTick = (clip.startTick + 12345) Mod 200000
    If audio_SetClip(0, clip) = 0 OrElse _
        documentHistory_CancelAudio(history) = 0 Then _
        test_Fail "cancelled audio edit failed"
    test_AssertRestoredState summary, projectFilename, beforeState
End Sub

' -------------------------------------------------------------------------
' Deterministic endurance sequence
' -------------------------------------------------------------------------

Dim As String waveFilename = Trim(Command(1))
If waveFilename = "" Then
    test_Fail "WAV fixture path is required"
End If
If test_WriteWave(waveFilename) = 0 Then
    test_Fail "WAV fixture creation failed"
End If
Dim As String projectFilename = waveFilename + ".ose"

Dim As MidiSummary summary
Dim As OseDocumentHistory history
Dim undoStack(0 To OSE_HISTORY_TIMELINE_DEPTH - 1) As TestStateSnapshot
Dim redoStack(0 To OSE_HISTORY_TIMELINE_DEPTH - 1) As TestStateSnapshot
Dim As Integer undoCount
Dim As Integer redoCount
Dim As Integer midiEditCount
Dim As Integer audioEditCount
Dim As Integer undoOperationCount
Dim As Integer redoOperationCount
Dim As Integer cancelOperationCount
Dim As Integer branchCount
Dim As Integer resetCount
' ULong is deliberately the fixed 32-bit state required by xorshift32.
' fblint: disable-next-line FBL423 REASON: ULong deliberately preserves the fixed 32-bit xorshift32 state.
Dim As ULong randomState = &HC0FFEE11

test_InitializeDocument summary, history, waveFilename
For cycleIndex As Integer = 0 To TEST_OPERATION_COUNT - 1
    ' fblint: disable-next-line FBL423 REASON: ULong deliberately preserves the fixed 32-bit xorshift32 state.
    Dim As ULong randomValue = test_NextRandom(randomState)
    Dim As Integer operationCode = CInt(randomValue Mod 10)

    Select Case operationCode
        Case 0, 1, 2, 3
            Dim As TestStateSnapshot beforeState
            If test_CaptureState(summary, projectFilename, beforeState) = 0 Then _
                test_Fail "pre-MIDI state could not be serialized"
            If redoCount > 0 Then
                branchCount += 1
            End If
            test_ApplyMidiEdit summary, history, cycleIndex, randomValue
            test_PushStack undoStack(), undoCount, beforeState, _
                OSE_HISTORY_DOMAIN_MIDI
            test_ClearStack redoStack(), redoCount
            midiEditCount += 1

        Case 4, 5
            Dim As TestStateSnapshot beforeState
            If test_CaptureState(summary, projectFilename, beforeState) = 0 Then _
                test_Fail "pre-audio state could not be serialized"
            If redoCount > 0 Then
                branchCount += 1
            End If
            test_ApplyAudioEdit history, randomValue
            test_PushStack undoStack(), undoCount, beforeState, _
                OSE_HISTORY_DOMAIN_AUDIO
            test_ClearStack redoStack(), redoCount
            audioEditCount += 1

        Case 6
            If undoCount > 0 Then
                Dim As TestStateSnapshot currentState
                Dim As TestStateSnapshot expectedState
                If test_CaptureState(summary, projectFilename, currentState) = 0 _
                    Then test_Fail "pre-undo state could not be serialized"
                test_PopStack undoStack(), undoCount, expectedState
                If documentHistory_Undo(history, summary) <> _
                    expectedState.editDomain Then _
                    test_Fail "undo returned the wrong document domain"
                test_PushStack redoStack(), redoCount, currentState, _
                    expectedState.editDomain
                test_AssertRestoredState summary, projectFilename, expectedState
                undoOperationCount += 1
            ElseIf documentHistory_Undo(history, summary) <> _
                OSE_HISTORY_DOMAIN_NONE Then
                test_Fail "empty undo history accepted an operation"
            End If

        Case 7
            If redoCount > 0 Then
                Dim As TestStateSnapshot currentState
                Dim As TestStateSnapshot expectedState
                If test_CaptureState(summary, projectFilename, currentState) = 0 _
                    Then test_Fail "pre-redo state could not be serialized"
                test_PopStack redoStack(), redoCount, expectedState
                If documentHistory_Redo(history, summary) <> _
                    expectedState.editDomain Then _
                    test_Fail "redo returned the wrong document domain"
                test_PushStack undoStack(), undoCount, currentState, _
                    expectedState.editDomain
                test_AssertRestoredState summary, projectFilename, expectedState
                redoOperationCount += 1
            ElseIf documentHistory_Redo(history, summary) <> _
                OSE_HISTORY_DOMAIN_NONE Then
                test_Fail "empty redo history accepted an operation"
            End If

        Case 8
            Dim As Integer savedUndoCount = undoCount
            Dim As Integer savedRedoCount = redoCount
            test_CancelMidiEdit summary, history, projectFilename, cycleIndex
            If undoCount <> savedUndoCount OrElse redoCount <> savedRedoCount _
                Then test_Fail "cancelled MIDI edit changed the oracle"
            cancelOperationCount += 1

        Case 9
            Dim As Integer savedUndoCount = undoCount
            Dim As Integer savedRedoCount = redoCount
            test_CancelAudioEdit summary, history, projectFilename
            If undoCount <> savedUndoCount OrElse redoCount <> savedRedoCount _
                Then test_Fail "cancelled audio edit changed the oracle"
            cancelOperationCount += 1
        Case Else
            test_Fail "random operation selector left its bounded range"
    End Select

    test_VerifyState summary, history, projectFilename, undoCount, redoCount

    If (cycleIndex + 1) Mod TEST_RESET_INTERVAL = 0 AndAlso _
        cycleIndex + 1 < TEST_OPERATION_COUNT Then
        test_ClearStack undoStack(), undoCount
        test_ClearStack redoStack(), redoCount
        test_InitializeDocument summary, history, waveFilename
        resetCount += 1
    End If
Next

' Drain and restore the final branch once more after all random operations.
While undoCount > 0
    Dim As TestStateSnapshot currentState
    Dim As TestStateSnapshot expectedState
    If test_CaptureState(summary, projectFilename, currentState) = 0 Then _
        test_Fail "final undo state could not be serialized"
    test_PopStack undoStack(), undoCount, expectedState
    If documentHistory_Undo(history, summary) <> expectedState.editDomain Then _
        test_Fail "final undo drain returned the wrong domain"
    test_PushStack redoStack(), redoCount, currentState, expectedState.editDomain
    test_AssertRestoredState summary, projectFilename, expectedState
    undoOperationCount += 1
Wend
While redoCount > 0
    Dim As TestStateSnapshot currentState
    Dim As TestStateSnapshot expectedState
    If test_CaptureState(summary, projectFilename, currentState) = 0 Then _
        test_Fail "final redo state could not be serialized"
    test_PopStack redoStack(), redoCount, expectedState
    If documentHistory_Redo(history, summary) <> expectedState.editDomain Then _
        test_Fail "final redo drain returned the wrong domain"
    test_PushStack undoStack(), undoCount, currentState, expectedState.editDomain
    test_AssertRestoredState summary, projectFilename, expectedState
    redoOperationCount += 1
Wend
test_VerifyState summary, history, projectFilename, undoCount, redoCount

If midiEditCount = 0 OrElse audioEditCount = 0 OrElse _
    undoOperationCount = 0 OrElse redoOperationCount = 0 OrElse _
    cancelOperationCount = 0 OrElse branchCount = 0 Then _
    test_Fail "deterministic sequence missed a required operation family"

Print "document_endurance=ok"
Print "operations="; TEST_OPERATION_COUNT; _
    " midi_edits="; midiEditCount; " audio_edits="; audioEditCount
Print "undos="; undoOperationCount; " redos="; redoOperationCount; _
    " cancels="; cancelOperationCount; " branches="; branchCount
Print "lifecycle_resets="; resetCount
End 0

/' end of tests/document_endurance_smoke.bas '/
