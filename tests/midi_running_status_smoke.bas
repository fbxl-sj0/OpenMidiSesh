/'
    Project: OpenSesh
    ---------------------------

    File: tests/midi_running_status_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify Standard MIDI File running status without losing event bytes.

    Responsibilities:

        - import repeated one-byte and two-byte channel messages
        - verify note timing, velocity, controller data, and event order
        - retain the decoded arrangement through save and reload

    This file intentionally does NOT contain:

        - graphical behavior or playback
        - external MIDI devices
'/

#lang "fb"

#include once "../midi_model.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub

Private Function test_Be32(ByVal value As ULong) As String
    Return Chr((value Shr 24) And 255) + Chr((value Shr 16) And 255) + _
        Chr((value Shr 8) And &HFF) + Chr(value And &HFF)
End Function

Private Sub test_CheckDocument()
    Dim As Integer keys(0 To 2) = {60, 64, 67}
    If midi_GetEditableNoteCount() <> 3 Then
        test_Fail "note count changed"
    End If
    For noteIndex As Integer = 0 To 2
        Dim As MidiEditableNote noteData
        If midi_GetEditableNote(noteIndex, noteData) = 0 Then _
            test_Fail "decoded note is missing"
        If noteData.keyNumber <> keys(noteIndex) OrElse noteData.channel <> 0 OrElse _
            noteData.velocity <> 91 + noteIndex OrElse _
            noteData.startTick <> CULngInt(noteIndex * 120) OrElse _
            noteData.durationTicks <> 360 Then _
            test_Fail "running-status note timing or data changed"
    Next
    If midi_GetChannelEventCount() <> 10 Then
        test_Fail "channel event count changed"
    End If
    Dim As Integer messageTypes(0 To 9) = {&HB0, &HB0, &HC0, &HC0, &HD0, &HD0, _
        &HE0, &HE0, &HA0, &HA0}
    Dim As Integer firstBytes(0 To 9) = {7, 11, 8, 9, 10, 11, 1, 2, 60, 64}
    Dim As Integer secondBytes(0 To 9) = {100, 80, 0, 0, 0, 0, 64, 64, 50, 51}
    For eventIndex As Integer = 0 To 9
        Dim As MidiChannelEventPoint eventData
        If midi_GetChannelEvent(eventIndex, eventData) = 0 Then _
            test_Fail "decoded channel event is missing"
        If eventData.tick <> CULngInt(600 + eventIndex * 10) OrElse _
            eventData.channel <> 0 OrElse eventData.messageType <> messageTypes(eventIndex) OrElse _
            eventData.data1 <> firstBytes(eventIndex) OrElse _
            eventData.data2 <> secondBytes(eventIndex) Then _
            test_Fail "running-status channel event timing or data changed"
    Next
End Sub

Dim As String fixtureFilename = Trim(Command(1))
If fixtureFilename = "" Then
    Print "usage: midi_running_status_smoke <fixture.mid>"
    End 2
End If
Dim As String trackData = _
    Chr(0, &H90, 60, 91) + Chr(120, 64, 92) + Chr(120, 67, 93) + _
    Chr(120, 60, 0) + Chr(120, &H80, 64, 44) + Chr(120, 67, 55) + _
    Chr(0, &HB0, 7, 100) + Chr(10, 11, 80) + _
    Chr(10, &HC0, 8) + Chr(10, 9) + _
    Chr(10, &HD0, 10) + Chr(10, 11) + _
    Chr(10, &HE0, 1, 64) + Chr(10, 2, 64) + _
    Chr(10, &HA0, 60, 50) + Chr(10, 64, 51) + Chr(10, &HFF, &H2F, 0)
Dim As String fileData = "MThd" + test_Be32(6) + Chr(0, 0, 0, 1, 1, &HE0) + _
    "MTrk" + test_Be32(Len(trackData)) + trackData
Dim As Integer fileNumber = FreeFile()
If Open(fixtureFilename For Output Access Write As #fileNumber) <> 0 Then _
    test_Fail "could not create running-status fixture"
Close #fileNumber
If Open(fixtureFilename For Binary Access Write As #fileNumber) <> 0 Then _
    test_Fail "could not open running-status fixture"
Put #fileNumber, 1, fileData
Close #fileNumber

Dim As MidiSummary summary
If midi_LoadSummary(summary, fixtureFilename) = 0 Then _
    test_Fail "valid running-status MIDI was rejected: " + summary.errorText
test_CheckDocument()
If midi_SaveDocument(summary, fixtureFilename + ".saved.mid") = 0 Then _
    test_Fail "running-status document could not be saved: " + summary.errorText
If midi_LoadSummary(summary, fixtureFilename + ".saved.mid") = 0 Then _
    test_Fail "saved running-status document could not be loaded: " + summary.errorText
test_CheckDocument()
Print "midi_running_status=ok message_types=7 notes=3 channel_events=10 roundtrip=1"
End 0

/' end of tests/midi_running_status_smoke.bas '/
