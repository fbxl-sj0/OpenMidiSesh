/'
    Project: OpenSesh
    ---------------------------

    File: tests/midi_model_fuzz_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Module API: Test executable accepting a temporary base path for generated
        .control.mid and .candidate.mid files; checks midi_* document and history state.

    Purpose:

        Exercise the Standard MIDI File loader with a deterministic corpus of
        truncations, substitutions, insertions, and random byte blocks.

    Responsibilities:

        - generate repeatable mutations from a feature-rich valid MIDI seed
        - require every rejected load to preserve the active document
        - require every rejected load to preserve undo and redo state
        - validate and serialize every mutation which remains standards-valid
        - bound corpus size and candidate length for routine test runs

    This file intentionally does NOT contain:

        - nondeterministic random-number library calls
        - unbounded file or allocation stress
        - graphical application behavior
        - MIDI hardware access
'/

#lang "fb"

#include once "../src/midi_model.bi"

Const TEST_RANDOM_SEED As ULong = &HC0DEC0DEUL
Const TEST_RANDOM_CASES As Integer = 1536
Const TEST_MAX_INSERT_BYTES As Integer = 32
Const TEST_MAX_RANDOM_FILE_BYTES As Integer = 512
Const TEST_SENTINEL_KEY As Integer = 72
Const TEST_SENTINEL_TICK As ULongInt = 960
Const TEST_SENTINEL_DURATION As ULongInt = 240

Dim Shared test_ActiveSummary As MidiSummary
Dim Shared test_SeedData As String
Dim Shared test_ControlFilename As String
Dim Shared test_CandidateFilename As String
Dim Shared test_SeedNoteCount As Integer
Dim Shared test_RejectedCount As Integer
Dim Shared test_AcceptedCount As Integer
Dim Shared test_CaseCount As Integer

' -------------------------------------------------------------------------
' Failure and binary helpers
' -------------------------------------------------------------------------

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Function test_Be16(ByVal value As Integer) As String
    Return Chr((value Shr 8) And &HFF) + Chr(value And &HFF)
End Function


Private Function test_Be32(ByVal value As ULong) As String
    Return Chr((value Shr 24) And &HFF) + _
        Chr((value Shr 16) And &HFF) + _
        Chr((value Shr 8) And &HFF) + Chr(value And &HFF)
End Function


Private Function test_Track(ByVal trackData As String) As String
    Return "MTrk" + test_Be32(CULng(Len(trackData))) + trackData
End Function


Private Sub test_WriteFile( _
    ByVal filename As String, _
    ByVal fileData As String _
)
    If Len(Dir(filename)) > 0 Then
        Kill filename
    End If
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Write As #fileNumber) <> 0 Then _
        test_Fail "could not create fuzz fixture"
    If Len(fileData) > 0 Then
        Put #fileNumber, 1, fileData
    End If
    Close #fileNumber
End Sub


Private Function test_NextRandom(ByRef randomState As ULong) As ULong
    /'
        Xorshift32 is deliberately specified here instead of using Rnd. Its
        unsigned operations produce the same corpus on Windows and Linux.
    '/
    randomState Xor= randomState Shl 13
    randomState Xor= randomState Shr 17
    randomState Xor= randomState Shl 5
    Return randomState
End Function


Private Function test_RandomBelow( _
    ByRef randomState As ULong, _
    ByVal upperBound As Integer _
) As Integer
    If upperBound <= 1 Then
        Return 0
    End If
    Return CInt(test_NextRandom(randomState) Mod CULng(upperBound))
End Function


Private Function test_RandomBytes( _
    ByRef randomState As ULong, _
    ByVal byteCount As Integer _
) As String
    If byteCount <= 0 Then
        Return ""
    End If
    Dim As String resultData = String(byteCount, Chr(0))
    For byteIndex As Integer = 1 To byteCount
        Mid(resultData, byteIndex, 1) = Chr( _
            test_RandomBelow(randomState, 256))
    Next
    Return resultData
End Function

' -------------------------------------------------------------------------
' Transactional sentinel
' -------------------------------------------------------------------------

Private Sub test_LoadSentinel()
    test_WriteFile test_ControlFilename, test_SeedData
    If midi_LoadSummary(test_ActiveSummary, test_ControlFilename) = 0 Then _
        test_Fail "valid fuzz seed could not be loaded: " + _
            test_ActiveSummary.errorText
    test_SeedNoteCount = midi_GetEditableNoteCount()
    If test_SeedNoteCount <> 1 Then _
        test_Fail "valid fuzz seed did not contain one note"
    If midi_CaptureHistory(test_ActiveSummary) = 0 Then _
        test_Fail "could not capture fuzz sentinel history"
    If midi_AddEditableNote(test_ActiveSummary, 0, TEST_SENTINEL_TICK, _
        TEST_SENTINEL_DURATION, TEST_SENTINEL_KEY, 0, 101) < 0 Then _
        test_Fail "could not add fuzz sentinel note"
    If midi_HistoryUndoCount() <> 1 OrElse _
        midi_HistoryRedoCount() <> 0 Then _
        test_Fail "fuzz sentinel history was not initialized"
End Sub


Private Sub test_RequireSentinel(ByVal caseIndex As Integer)
    If test_ActiveSummary.trackCount <> 1 OrElse _
        test_ActiveSummary.division <> 480 OrElse _
        midi_GetEditableNoteCount() <> test_SeedNoteCount + 1 OrElse _
        midi_HistoryUndoCount() <> 1 OrElse _
        midi_HistoryRedoCount() <> 0 Then _
        test_Fail "rejected fuzz case changed document state at case " + _
            Str(caseIndex)

    Dim As MidiEditableNote sentinelNote
    If midi_GetEditableNote(test_SeedNoteCount, sentinelNote) = 0 OrElse _
        sentinelNote.keyNumber <> TEST_SENTINEL_KEY OrElse _
        sentinelNote.startTick <> TEST_SENTINEL_TICK OrElse _
        sentinelNote.durationTicks <> TEST_SENTINEL_DURATION Then _
        test_Fail "rejected fuzz case damaged sentinel note at case " + _
            Str(caseIndex)
    If test_ActiveSummary.errorText = "" Then _
        test_Fail "rejected fuzz case returned no diagnostic at case " + _
            Str(caseIndex)
End Sub

' -------------------------------------------------------------------------
' Accepted-document invariants
' -------------------------------------------------------------------------

Private Sub test_ValidateAccepted(ByVal caseIndex As Integer)
    If test_ActiveSummary.trackCount <= 0 OrElse _
        test_ActiveSummary.trackCount > OSE_MAX_MIDI_TRACKS OrElse _
        test_ActiveSummary.division <= 0 OrElse _
        test_ActiveSummary.tempoCount <= 0 OrElse _
        test_ActiveSummary.tempoCount > OSE_MAX_TEMPO_EVENTS OrElse _
        test_ActiveSummary.timeSignatureCount <= 0 OrElse _
        test_ActiveSummary.timeSignatureCount > _
            OSE_MAX_TIME_SIGNATURE_EVENTS OrElse _
        test_ActiveSummary.keySignatureCount <= 0 OrElse _
        test_ActiveSummary.keySignatureCount > _
            OSE_MAX_KEY_SIGNATURE_EVENTS OrElse _
        midi_GetEditableNoteCount() < 0 OrElse _
        midi_GetEditableNoteCount() > OSE_MAX_EDITABLE_NOTES Then _
        test_Fail "accepted fuzz case violated summary bounds at case " + _
            Str(caseIndex)

    For noteIndex As Integer = 0 To midi_GetEditableNoteCount() - 1
        Dim As MidiEditableNote editableNote
        If midi_GetEditableNote(noteIndex, editableNote) = 0 OrElse _
            editableNote.trackIndex < 0 OrElse _
            editableNote.trackIndex >= test_ActiveSummary.trackCount OrElse _
            editableNote.keyNumber > 127 OrElse editableNote.channel > 15 OrElse _
            editableNote.velocity = 0 OrElse editableNote.durationTicks = 0 OrElse _
            editableNote.startTick > OSE_MAX_MIDI_TICK OrElse _
            editableNote.durationTicks > _
                OSE_MAX_MIDI_TICK - editableNote.startTick Then _
            test_Fail "accepted fuzz note violated bounds at case " + _
                Str(caseIndex)
    Next

    Dim As String serializedData
    If midi_SerializeDocument(test_ActiveSummary, serializedData) = 0 OrElse _
        Len(serializedData) < 14 OrElse Left(serializedData, 4) <> "MThd" Then _
        test_Fail "accepted fuzz case could not be serialized at case " + _
            Str(caseIndex)
End Sub


Private Sub test_RunCandidate(ByVal candidateData As String)
    test_CaseCount += 1
    test_WriteFile test_CandidateFilename, candidateData
    If midi_LoadSummary(test_ActiveSummary, test_CandidateFilename) = 0 Then
        test_RejectedCount += 1
        test_RequireSentinel test_CaseCount
    Else
        test_AcceptedCount += 1
        test_ValidateAccepted test_CaseCount
        test_LoadSentinel()
    End If
End Sub

' -------------------------------------------------------------------------
' Feature-rich valid seed
' -------------------------------------------------------------------------

Dim As String fixtureBase = Trim(Command(1))
If fixtureBase = "" Then
    Print "usage: midi_model_fuzz_smoke.exe <temporary-base-path>"
    End 2
End If
test_ControlFilename = fixtureBase + ".control.mid"
test_CandidateFilename = fixtureBase + ".candidate.mid"

Dim As String trackData
trackData += Chr(0) + Chr(&HFF) + Chr(&H51) + Chr(3) + _
    Chr(&H07) + Chr(&HA1) + Chr(&H20)
trackData += Chr(0) + Chr(&HFF) + Chr(&H58) + Chr(4) + _
    Chr(4) + Chr(2) + Chr(24) + Chr(8)
trackData += Chr(0) + Chr(&HFF) + Chr(&H59) + Chr(2) + Chr(0) + Chr(0)
trackData += Chr(0) + Chr(&HFF) + Chr(&H03) + Chr(4) + "Fuzz"
trackData += Chr(0) + Chr(&HC0) + Chr(5)
trackData += Chr(0) + Chr(&HB0) + Chr(7) + Chr(100)
trackData += Chr(0) + Chr(&H90) + Chr(60) + Chr(100)
trackData += Chr(120) + Chr(&H80) + Chr(60) + Chr(0)
trackData += Chr(0) + Chr(&HF0) + Chr(3) + Chr(1) + Chr(2) + Chr(&HF7)
trackData += Chr(0) + Chr(&HFF) + Chr(&H2F) + Chr(0)
test_SeedData = "MThd" + test_Be32(6) + test_Be16(0) + _
    test_Be16(1) + test_Be16(480) + test_Track(trackData)

test_LoadSentinel()

' -------------------------------------------------------------------------
' Exhaustive local mutations
' -------------------------------------------------------------------------

For truncationLength As Integer = 0 To Len(test_SeedData) - 1
    test_RunCandidate Left(test_SeedData, truncationLength)
Next

Dim As Integer replacementValues(0 To 3) = {0, &H7F, &H80, &HFF}
For bytePosition As Integer = 1 To Len(test_SeedData)
    For replacementIndex As Integer = 0 To 3
        Dim As String candidateData = test_SeedData
        ' The copied seed has the exact indexed length. FB-LINTER: DISABLE-NEXT-LINE FBL514 REASON: The copied seed has the exact indexed length.
        Mid(candidateData, bytePosition, 1) = _
            Chr(replacementValues(replacementIndex))
        test_RunCandidate candidateData
    Next
Next

' -------------------------------------------------------------------------
' Deterministic mixed mutations
' -------------------------------------------------------------------------

Dim As ULong randomState = TEST_RANDOM_SEED
For randomCase As Integer = 1 To TEST_RANDOM_CASES
    Dim As Integer mutationKind = test_RandomBelow(randomState, 6)
    Dim As String candidateData = test_SeedData

    Select Case mutationKind
        Case 0
            Dim As Integer mutationCount = 1 + _
                test_RandomBelow(randomState, 8)
            For mutationIndex As Integer = 1 To mutationCount
                Dim As Integer bytePosition = 1 + _
                    test_RandomBelow(randomState, Len(candidateData))
                Mid(candidateData, bytePosition, 1) = Chr( _
                    test_RandomBelow(randomState, 256))
            Next

        Case 1
            candidateData = Left(candidateData, _
                test_RandomBelow(randomState, Len(candidateData) + 1))

        Case 2
            Dim As Integer insertionPosition = _
                test_RandomBelow(randomState, Len(candidateData) + 1)
            Dim As Integer insertionLength = 1 + _
                test_RandomBelow(randomState, TEST_MAX_INSERT_BYTES)
            candidateData = Left(candidateData, insertionPosition) + _
                test_RandomBytes(randomState, insertionLength) + _
                Mid(candidateData, insertionPosition + 1)

        Case 3
            Dim As Integer blockStart = 1 + _
                test_RandomBelow(randomState, Len(candidateData))
            Dim As Integer maximumBlock = Len(candidateData) - blockStart + 1
            Dim As Integer blockLength = 1 + _
                test_RandomBelow(randomState, maximumBlock)
            ' The replacement is exactly blockLength bytes. FB-LINTER: DISABLE-NEXT-LINE FBL514 REASON: The replacement is exactly blockLength bytes.
            Mid(candidateData, blockStart, blockLength) = _
                test_RandomBytes(randomState, blockLength)

        Case 4
            Dim As Integer tailLength = _
                test_RandomBelow(randomState, TEST_MAX_INSERT_BYTES + 1)
            candidateData += test_RandomBytes(randomState, tailLength)

        Case Else
            Dim As Integer prefixLength = _
                test_RandomBelow(randomState, Len(test_SeedData) + 1)
            Dim As Integer randomLength = _
                test_RandomBelow(randomState, TEST_MAX_RANDOM_FILE_BYTES + 1)
            candidateData = Left(test_SeedData, prefixLength) + _
                test_RandomBytes(randomState, randomLength)
    End Select
    test_RunCandidate candidateData
Next

' -------------------------------------------------------------------------
' Final history proof and result
' -------------------------------------------------------------------------

If test_RejectedCount <= 0 OrElse test_AcceptedCount <= 0 Then _
    test_Fail "fuzz corpus did not exercise both acceptance outcomes"
If midi_Undo(test_ActiveSummary) = 0 OrElse _
    midi_GetEditableNoteCount() <> test_SeedNoteCount Then _
    test_Fail "fuzz corpus damaged final undo history"
If midi_Redo(test_ActiveSummary) = 0 OrElse _
    midi_GetEditableNoteCount() <> test_SeedNoteCount + 1 Then _
    test_Fail "fuzz corpus damaged final redo history"

Print "midi_model_fuzz=ok"
Print "cases="; test_CaseCount; " rejected="; test_RejectedCount; _
    " accepted="; test_AcceptedCount; " seed_bytes="; Len(test_SeedData)
End 0

/' end of tests/midi_model_fuzz_smoke.bas '/
