/'
    Project: OpenSesh
    ---------------------------

    File: tests/midi_model_malformed_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Module API: Test executable accepting a MIDI fixture path that it rewrites
        with valid and invalid files to check midi_LoadSummary and retained state.

    Purpose:

        Prove that malformed Standard MIDI Files are rejected with bounded,
        useful errors instead of being accepted, truncated, or dereferenced.

    Responsibilities:

        - exercise header, chunk, track-length, and timing validation
        - exercise truncated channel, meta, SysEx, and system events
        - reject invalid fixed-length meta events and format-zero topology
        - retain successful loading of a minimal standards-compliant file
    Ownership: Writers close handles; callers own cleanup of fixture files.
    This file intentionally does NOT contain:

        - graphical application behavior
        - MIDI playback or device access
        - large allocation stress tests
'/

#lang "fb"

#include once "../midi_model.bi"

Dim Shared test_ActiveSummary As MidiSummary

' -------------------------------------------------------------------------
' Binary fixture helpers
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


Private Function test_Header( _
    ByVal formatNumber As Integer, _
    ByVal trackCount As Integer, _
    ByVal division As Integer, _
    ByVal headerLength As ULong = 6 _
) As String
    Return "MThd" + test_Be32(headerLength) + _
        test_Be16(formatNumber) + test_Be16(trackCount) + test_Be16(division)
End Function


Private Function test_Track( _
    ByVal trackData As String, _
    ByVal declaredLength As LongInt = -1 _
) As String
    Dim As ULong storedLength
    If declaredLength < 0 Then
        storedLength = CULng(Len(trackData))
    Else
        storedLength = CULng(declaredLength)
    End If
    Return "MTrk" + test_Be32(storedLength) + trackData
End Function


Private Sub test_WriteFixture( _
    ByVal fixtureFilename As String, _
    ByVal fileData As String _
)
    If Len(Dir(fixtureFilename)) > 0 Then
        Kill fixtureFilename
    End If
    Dim As Integer fileNumber = FreeFile()
    If Open(fixtureFilename For Binary Access Write As #fileNumber) <> 0 Then _
        test_Fail "could not create malformed MIDI fixture"
    Put #fileNumber, 1, fileData
    Close #fileNumber
End Sub


Private Sub test_ExpectReject( _
    ByVal fixtureFilename As String, _
    ByVal fileData As String, _
    ByVal expectedError As String _
)
    test_WriteFixture fixtureFilename, fileData
    If midi_LoadSummary(test_ActiveSummary, fixtureFilename) <> 0 Then _
        test_Fail "malformed MIDI was accepted: " + expectedError
    If InStr(LCase(test_ActiveSummary.errorText), LCase(expectedError)) = 0 Then _
        test_Fail "malformed MIDI lacked the expected error: " + _
            expectedError + " actual=" + test_ActiveSummary.errorText
    If test_ActiveSummary.trackCount <> 1 OrElse _
        test_ActiveSummary.division <> 480 OrElse _
        midi_GetEditableNoteCount() <> 1 Then _
        test_Fail "malformed MIDI replaced the active document: " + expectedError
    Dim As MidiEditableNote sentinelNote
    If midi_GetEditableNote(0, sentinelNote) = 0 OrElse _
        sentinelNote.keyNumber <> 60 OrElse sentinelNote.durationTicks <> 120 _
        Then test_Fail "malformed MIDI damaged the active note: " + expectedError
End Sub

' -------------------------------------------------------------------------
' Rejection matrix
' -------------------------------------------------------------------------

Dim As String fixtureFilename = Trim(Command(1))
If fixtureFilename = "" Then
    Print "usage: midi_model_malformed_smoke.exe <fixture.mid>"
    End 2
End If

Dim As String endOfTrack = Chr(0) + Chr(&HFF) + Chr(&H2F) + Chr(0)
Dim As String validTrack = test_Track(endOfTrack)
Dim As String validHeader = test_Header(0, 1, 480)

test_WriteFixture fixtureFilename, validHeader + validTrack
If midi_LoadSummary(test_ActiveSummary, fixtureFilename) = 0 Then _
    test_Fail "could not load the transactional sentinel document"
If midi_CaptureHistory(test_ActiveSummary) = 0 Then _
    test_Fail "could not capture sentinel undo history"
If midi_AddEditableNote(test_ActiveSummary, 0, 0, 120, 60, 0, 100) < 0 Then _
    test_Fail "could not add the transactional sentinel note"

Dim As String missingFilename = fixtureFilename + ".missing"
If Len(Dir(missingFilename)) > 0 Then
    Kill missingFilename
End If
If midi_LoadSummary(test_ActiveSummary, missingFilename) <> 0 OrElse _
    InStr(LCase(test_ActiveSummary.errorText), "could not open") = 0 OrElse _
    midi_GetEditableNoteCount() <> 1 Then _
    test_Fail "a missing file was accepted or lacked a useful error"
If midi_Undo(test_ActiveSummary) = 0 OrElse midi_GetEditableNoteCount() <> 0 _
    Then test_Fail "failed load discarded the active undo history"
If midi_Redo(test_ActiveSummary) = 0 OrElse midi_GetEditableNoteCount() <> 1 _
    Then test_Fail "failed load discarded the active redo history"

test_ExpectReject fixtureFilename, "MThd", "file size"
test_ExpectReject fixtureFilename, "NOPE" + String(10, Chr(0)), _
    "does not begin with an mthd"
test_ExpectReject fixtureFilename, test_Header(0, 1, 480, 5), _
    "header length"
test_ExpectReject fixtureFilename, test_Header(2, 1, 480) + validTrack, _
    "formats 0 and 1"
test_ExpectReject fixtureFilename, test_Header(0, 0, 480), "track count"
test_ExpectReject fixtureFilename, test_Header(1, 257, 480), "track count"
test_ExpectReject fixtureFilename, test_Header(0, 2, 480) + _
    validTrack + validTrack, "format 0"
test_ExpectReject fixtureFilename, test_Header(0, 1, 0), "division"
test_ExpectReject fixtureFilename, test_Header(0, 1, &HE728), "division"
test_ExpectReject fixtureFilename, validHeader, "ends before all tracks"
test_ExpectReject fixtureFilename, validHeader + "NOPE" + test_Be32(0), _
    "does not begin with mtrk"
test_ExpectReject fixtureFilename, validHeader + test_Track("x", 10), _
    "track length exceeds"

test_ExpectReject fixtureFilename, validHeader + _
    test_Track(String(4, Chr(&H80))), "truncated midi delta-time"
test_ExpectReject fixtureFilename, validHeader + _
    test_Track(Chr(0) + Chr(&H3C)), "without running status"
test_ExpectReject fixtureFilename, validHeader + _
    test_Track(Chr(0) + Chr(&H90) + Chr(&H3C)), "truncated midi event data"
test_ExpectReject fixtureFilename, validHeader + test_Track( _
    Chr(0) + Chr(&H90) + Chr(&H3C) + Chr(&H90)), _
    "channel data contains a status byte"

test_ExpectReject fixtureFilename, validHeader + _
    test_Track(Chr(0) + Chr(&HFF)), "truncated midi meta-event type"
test_ExpectReject fixtureFilename, validHeader + test_Track( _
    Chr(0) + Chr(&HFF) + Chr(1) + String(4, Chr(&H80))), _
    "truncated midi meta-event length"
test_ExpectReject fixtureFilename, validHeader + test_Track( _
    Chr(0) + Chr(&HFF) + Chr(1) + Chr(&H7F)), _
    "meta-event exceeds its track"
test_ExpectReject fixtureFilename, validHeader + test_Track( _
    Chr(0) + Chr(&HFF) + Chr(&H2F) + Chr(1) + Chr(0)), _
    "end-of-track event length"
test_ExpectReject fixtureFilename, validHeader + test_Track( _
    Chr(0) + Chr(&HFF) + Chr(&H51) + Chr(2) + Chr(7) + Chr(&HA1)), _
    "tempo event length"
test_ExpectReject fixtureFilename, validHeader + test_Track( _
    Chr(0) + Chr(&HFF) + Chr(&H51) + Chr(3) + String(3, Chr(0))), _
    "tempo event has a zero value"
test_ExpectReject fixtureFilename, validHeader + test_Track( _
    Chr(0) + Chr(&HFF) + Chr(&H58) + Chr(3) + Chr(4) + Chr(2) + Chr(24)), _
    "time-signature event length"
test_ExpectReject fixtureFilename, validHeader + test_Track( _
    Chr(0) + Chr(&HFF) + Chr(&H58) + Chr(4) + _
    Chr(0) + Chr(2) + Chr(24) + Chr(8)), "time-signature event is invalid"
test_ExpectReject fixtureFilename, validHeader + test_Track( _
    Chr(0) + Chr(&HFF) + Chr(&H59) + Chr(1) + Chr(0)), _
    "key-signature event length"
test_ExpectReject fixtureFilename, validHeader + test_Track( _
    Chr(0) + Chr(&HFF) + Chr(&H59) + Chr(2) + Chr(8) + Chr(0)), _
    "key-signature event is invalid"

test_ExpectReject fixtureFilename, validHeader + test_Track( _
    Chr(0) + Chr(&HF0) + String(4, Chr(&H80))), _
    "truncated midi system-exclusive length"
test_ExpectReject fixtureFilename, validHeader + _
    test_Track(Chr(0) + Chr(&HF0) + Chr(&H7F)), _
    "system-exclusive event exceeds its track"
test_ExpectReject fixtureFilename, validHeader + _
    test_Track(Chr(0) + Chr(&HF4)), "unsupported or truncated midi system event"

Dim As String maximumDelta = _
    Chr(&HFF) + Chr(&HFF) + Chr(&HFF) + Chr(&H7F)
test_ExpectReject fixtureFilename, validHeader + test_Track( _
    maximumDelta + Chr(&H90) + Chr(60) + Chr(64) + _
    Chr(1) + Chr(&H80) + Chr(60) + Chr(0)), _
    "tick exceeds the supported range"

' -------------------------------------------------------------------------
' Valid control fixture
' -------------------------------------------------------------------------

test_WriteFixture fixtureFilename, validHeader + validTrack
Dim As MidiSummary validSummary
If midi_LoadSummary(validSummary, fixtureFilename) = 0 Then _
    test_Fail "minimal valid MIDI was rejected: " + validSummary.errorText
If validSummary.formatNumber <> 0 OrElse validSummary.trackCount <> 1 OrElse _
    validSummary.division <> 480 Then _
    test_Fail "minimal valid MIDI summary was incorrect"

Print "midi_model_malformed=ok"
Print "rejection_cases=31 valid_controls=1 transactional_sentinel=1"
End 0

/' end of tests/midi_model_malformed_smoke.bas '/
