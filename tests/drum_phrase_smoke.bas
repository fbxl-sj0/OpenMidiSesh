/'
    Project: OpenSesh
    File: tests/drum_phrase_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.
    Purpose: Verify drum phrase persistence, independent timing and undo.
    Responsibilities: Exercise MIDI round trips, malformed metadata, repeat
        boundaries, channel isolation, capacity guards and batch insertion.
    This file intentionally does NOT contain:

        - GUI tests
        - audio-device tests
'/

#lang "fb"
#include once "../src/drum_phrase.bi"

Private Sub test_Check(ByVal condition As Integer, ByVal messageText As String)
    If condition <> 0 Then
        Exit Sub
    End If
    Print "FAIL: "; messageText
    End 1
End Sub

Dim As MidiSummary summary
Dim As OseDrumPhrase phrase
Dim As OseDrumPhrase loadedPhrase
Dim As String fixturePath = Command(1)
If fixturePath = "" Then
    fixturePath = "drum-phrase-smoke.mid"
End If
test_Check midi_NewDocument(summary) <> 0, "new document"
test_Check drumPhrase_PadForRow(0) = 8 AndAlso drumPhrase_PadForRow(1) = 9 AndAlso _
    drumPhrase_PadForRow(2) = 11, "kick, snare and closed hat are on the first grid page"
Dim As Integer seenPads(0 To OSE_DRUM_PAD_COUNT - 1)
For rowIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
    Dim As Integer padIndex = drumPhrase_PadForRow(rowIndex)
    test_Check padIndex >= 0 AndAlso padIndex < OSE_DRUM_PAD_COUNT, "valid grid row"
    test_Check seenPads(padIndex) = 0, "each drum has exactly one row"
    seenPads(padIndex) = -1
Next
test_Check drumPhrase_PadForRow(-1) = -1 AndAlso drumPhrase_PadForRow(12) = -1, "bounded row mapping"
summary.division = 100
drumPhrase_Reset phrase, 0
test_Check drumPhrase_Valid(phrase), "default phrase"
phrase.title = "Offbeat thirds"
phrase.denominator = 3
phrase.velocity(8, 0) = OSE_DRUM_VELOCITY_HARD
phrase.velocity(9, 4) = OSE_DRUM_VELOCITY_SOFT
phrase.velocity(11, 15) = OSE_DRUM_VELOCITY_MEDIUM
' Hidden cells remain available if a phrase is lengthened again.
phrase.velocity(0, 63) = OSE_DRUM_VELOCITY_HARD
test_Check drumPhrase_Store(summary, 0, phrase), "store first phrase"
test_Check drumPhrase_Load(0, loadedPhrase), "read first phrase"
test_Check loadedPhrase.title = phrase.title AndAlso loadedPhrase.denominator = 3 AndAlso _
    loadedPhrase.velocity(0, 63) = 127 AndAlso loadedPhrase.velocity(9, 4) = 72, "metadata values"
Dim As Integer storedCount = midi_GetTextEventCount()
test_Check drumPhrase_Store(summary, 0, phrase), "store same phrase"
test_Check midi_GetTextEventCount() = storedCount, "store is idempotent"
For slot As Integer = 1 To OSE_DRUM_PHRASE_COUNT - 1
    phrase.title = "Phrase " + LTrim(Str(slot + 1))
    phrase.numerator = slot + 1
    test_Check drumPhrase_Store(summary, slot, phrase), "store all slots"
Next
test_Check drumPhrase_Load(0, phrase), "recover original phrase"
test_Check drumPhrase_Store(summary, -1, phrase) = 0 AndAlso _
    drumPhrase_Store(summary, 16, phrase) = 0, "reject invalid slots"

Dim As Integer signatureCount = summary.timeSignatureCount
Dim As Integer originalMeter = summary.timeSignatureMap(0).numerator
Dim As Integer originalUnit = summary.timeSignatureMap(0).denominatorPower
Dim As ULongInt endTick
test_Check midi_PrepareHistory(summary), "prepare insert undo"
test_Check drumPhrase_Insert(summary, phrase, 0, 7, 64, endTick), "insert repeated thirds into empty song"
test_Check midi_CommitPreparedHistory(), "commit insert undo"
test_Check endTick = 34140, "repeats use absolute rounded boundaries"
test_Check midi_GetEditableNoteCount() = 192, "three hits per phrase"
For noteIndex As Integer = 0 To 191
    Dim As MidiEditableNote noteValue
    test_Check midi_GetEditableNote(noteIndex, noteValue), "read inserted note"
    Dim As Integer repeatIndex = noteIndex \ 3
    Dim As Integer expectedStep = repeatIndex * 16
    Dim As Integer expectedPitch = 36
    Select Case noteIndex Mod 3
        Case 1
            expectedStep += 4
            expectedPitch = 38
        Case 2
            expectedStep += 15
            expectedPitch = 42
    End Select
    Dim As ULongInt expectedTick = 7 + (CULngInt(expectedStep) * 100 + 1) \ 3
    test_Check noteValue.startTick = expectedTick AndAlso noteValue.channel = 9 AndAlso _
        noteValue.keyNumber = expectedPitch AndAlso noteValue.durationTicks >= 33 AndAlso _
        noteValue.durationTicks <= 34, "exact drum hit placement"
Next
test_Check summary.timeSignatureCount = signatureCount AndAlso _
    summary.timeSignatureMap(0).numerator = originalMeter AndAlso _
    summary.timeSignatureMap(0).denominatorPower = originalUnit, "drums leave song meter unchanged"
test_Check midi_Undo(summary) AndAlso midi_GetEditableNoteCount() = 0, "undo removes whole placement"
test_Check midi_Redo(summary) AndAlso midi_GetEditableNoteCount() = 192, "redo restores placement"
test_Check drumPhrase_Insert(summary, phrase, 0, 0, 1, endTick), "insert into nonempty song"
test_Check drumPhrase_Insert(summary, phrase, 0, OSE_MAX_MIDI_TICK - 1, 1, endTick) = 0, "reject tick overflow"
test_Check drumPhrase_Insert(summary, phrase, -1, 0, 1, endTick) = 0, "reject missing track"
test_Check drumPhrase_Insert(summary, phrase, 0, 0, 65, endTick) = 0, "reject repeat overflow"
Dim As Integer oldDivision = summary.division
summary.division = 1
test_Check drumPhrase_Insert(summary, phrase, 0, 0, 1, endTick) = 0, "reject insufficient resolution"
summary.division = oldDivision

test_Check midi_SaveDocument(summary, fixturePath), "save phrases with MIDI"
test_Check midi_NewDocument(summary), "clear before loading"
test_Check midi_LoadSummary(summary, fixturePath), "reload saved phrases"
For slot As Integer = 0 To OSE_DRUM_PHRASE_COUNT - 1
    test_Check drumPhrase_Load(slot, loadedPhrase), "all phrase slots survive file round trip"
    test_Check loadedPhrase.denominator = 3 AndAlso loadedPhrase.velocity(0, 63) = 127, "hidden cells and independent meter survive"
Next
test_Check midi_PrepareHistory(summary), "prepare phrase edit"
phrase.title = "Changed phrase"
test_Check drumPhrase_Store(summary, 0, phrase), "edit stored phrase"
test_Check midi_CommitPreparedHistory() AndAlso midi_Undo(summary), "undo stored phrase edit"
test_Check drumPhrase_Load(0, loadedPhrase) AndAlso loadedPhrase.title = "Offbeat thirds", "undo restores phrase metadata"

' Corrupt external MIDI text must never partially fill the caller's draft.
Dim As MidiTextEventPoint textPoint
test_Check midi_GetTextEvent(0, textPoint), "find metadata to corrupt"
textPoint.textValue = "OpenSesh:DrumPhrase:1:0|ZZ0304|Bad|" + String(768, "h")
test_Check midi_SetTextEvent(summary, textPoint.sourceIndex, textPoint), "write malformed hex fixture"
test_Check drumPhrase_Load(0, loadedPhrase) = 0 AndAlso loadedPhrase.denominator = 4, "reject malformed meter"
textPoint.textValue = "OpenSesh:DrumPhrase:1:0|040304|Bad|" + String(767, "h") + "?"
test_Check midi_SetTextEvent(summary, textPoint.sourceIndex, textPoint), "write malformed velocity fixture"
test_Check drumPhrase_Load(0, loadedPhrase) = 0 AndAlso loadedPhrase.velocity(0, 0) = 0, "reject partial velocity payload"
drumPhrase_Reset phrase, 0
test_Check drumPhrase_Insert(summary, phrase, 0, 0, 1, endTick) = 0, "empty phrase cannot mutate song"
phrase.denominator = 0
test_Check drumPhrase_Valid(phrase) = 0 AndAlso drumPhrase_StepTick(phrase, 100, 1) = 0, "zero denominator is safe"
Print "PASS: drum phrase persistence, 4/3 timing, repeats, channel isolation, undo and malformed input"
End 0

/' end of drum_phrase_smoke.bas '/
