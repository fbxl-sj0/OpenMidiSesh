/'
    Project: OpenSesh
    ---------------------------

    File: music_export_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify that a dense editable MIDI fixture becomes a structurally valid
        four-channel ProTracker module with an honest reduction report.

    Responsibilities:

        - create notes that exercise row quantization and four-voice reduction
        - verify the M.K. header, pattern table, sample length, and file size
        - verify octave folding, same-row drops, and one overlapping voice steal

    This file intentionally does NOT contain:

        - MOD playback or decoder-library dependencies
        - omaGui widgets
        - sfxlib audio output
'/

#lang "fb"

#include once "../midi_model.bi"
#include once "../music_export.bi"
#If Defined(__FB_WIN32__)
#include once "windows.bi"
#EndIf

Private Sub test_Fail(ByVal messageText As String)
    Print "ERROR: "; messageText
    End 1
End Sub


Private Function test_ReadBe16( _
    ByRef binaryData As String, _
    ByVal oneBasedOffset As Integer _
) As Integer
    If oneBasedOffset < 1 OrElse oneBasedOffset + 1 > Len(binaryData) Then _
        Return -1
    Return (Asc(Mid(binaryData, oneBasedOffset, 1)) Shl 8) Or _
        Asc(Mid(binaryData, oneBasedOffset + 1, 1))
End Function


Dim As String outputFilename = Trim(Command(1))
If outputFilename = "" Then
    Print "usage: music_export_smoke.exe <output.mod>"
    End 2
End If

Dim As MidiSummary summary
If midi_NewDocument(summary) = 0 Then
    test_Fail "new MIDI document failed"
End If
If midi_SetInitialTempoBpm(summary, 140) = 0 Then _
    test_Fail "initial tempo setup failed"

' Six attacks on row zero prove that the strongest four notes survive the
' tracker cell limit. The following overlap forces one deterministic steal.
For noteOffset As Integer = 0 To 5
    If midi_AddEditableNote(summary, 0, 0, 480, 60 + noteOffset * 2, _
        0, 120 - noteOffset) < 0 Then test_Fail "dense note setup failed"
Next
If midi_AddEditableNote(summary, 0, 240, 480, 79, 0, 110) < 0 Then _
    test_Fail "overlapping note setup failed"
If midi_AddEditableNote(summary, 0, 480, 240, 108, 0, 100) < 0 Then _
    test_Fail "high note setup failed"

Dim As OseModExportReport report
If musicExport_SaveMod(summary, outputFilename, report) = 0 Then _
    test_Fail "MOD export failed: " + report.errorText

If report.notesConsidered <> 8 OrElse report.notesWritten <> 6 OrElse _
    report.notesDropped <> 2 Then _
    test_Fail "four-channel reduction report is incorrect"
If report.voiceSteals <> 1 Then
    test_Fail "overlapping voice steal was not reported"
End If
If report.octaveFoldedNotes < 1 Then
    test_Fail "high pitch was not octave-folded"
End If
If report.tempoEventsWritten < 1 OrElse report.patternCount <> 1 Then _
    test_Fail "tempo or pattern report is incorrect"

Dim As Integer fileNumber = FreeFile()
If Open(outputFilename For Binary Access Read As #fileNumber) <> 0 Then _
    test_Fail "exported MOD could not be reopened"
Dim As LongInt fileBytes = LOF(fileNumber)
Dim As String binaryData = String(CInt(fileBytes), Chr(0))
Get #fileNumber, 1, binaryData
Close #fileNumber

Dim As Integer expectedBytes = 1084 + 1024 + 16 * 64
If fileBytes <> expectedBytes OrElse Len(binaryData) <> expectedBytes Then _
    test_Fail "exported MOD size is incorrect"
If Mid(binaryData, 1081, 4) <> "M.K." Then _
    test_Fail "ProTracker signature is missing"
If Asc(Mid(binaryData, 951, 1)) <> report.patternCount Then _
    test_Fail "song-length byte does not match the report"
If test_ReadBe16(binaryData, 43) <> 32 Then _
    test_Fail "first generated sample is not 64 bytes"

Dim As Integer firstCellPeriod = _
    ((Asc(Mid(binaryData, 1085, 1)) And &H0F) Shl 8) Or _
    Asc(Mid(binaryData, 1086, 1))
If firstCellPeriod <= 0 Then
    test_Fail "first pattern contains no playable note"
End If

' Windows permits writing this open file but denies replacing its directory
' entry. A transactional export must report failure and preserve its bytes.
#If Defined(__FB_WIN32__)
Dim As HANDLE retainedFile = CreateFileA(StrPtr(outputFilename), GENERIC_READ, _
    FILE_SHARE_READ Or FILE_SHARE_WRITE, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0)
If retainedFile = INVALID_HANDLE_VALUE Then test_Fail "could not retain MOD fixture"
If midi_SetInitialTempoBpm(summary, 100) = 0 Then test_Fail "changed tempo setup failed"
Dim As OseModExportReport failedReport
Dim As Integer failedResult = musicExport_SaveMod(summary, outputFilename, failedReport)
CloseHandle retainedFile
If failedResult <> 0 OrElse failedReport.errorText = "" Then _
    test_Fail "MOD replacement failure was not reported"
fileNumber = FreeFile()
If Open(outputFilename For Binary Access Read As #fileNumber) <> 0 Then _
    test_Fail "retained MOD could not be reopened"
Dim As String retainedData = Space(Len(binaryData))
Dim As Integer readResult = Get(#fileNumber, 1, retainedData)
Dim As LongInt retainedBytes = Lof(fileNumber)
Close #fileNumber
If readResult <> 0 OrElse retainedBytes <> Len(binaryData) OrElse _
    retainedData <> binaryData Then test_Fail "failed MOD export changed prior bytes"
If Dir(outputFilename + ".ose-tmp-*") <> "" Then _
    test_Fail "failed MOD export left a temporary file"
#EndIf

Dim As OseModExportReport invalidReport
If musicExport_SaveMod(summary, outputFilename + Chr(0) + "ignored", invalidReport) <> 0 Then _
    test_Fail "MOD export accepted an embedded-NUL path"

Print "music_export=ok"
Print "patterns="; report.patternCount
Print "notes_written="; report.notesWritten
Print "notes_dropped="; report.notesDropped
Print "voice_steals="; report.voiceSteals
Print "octave_folded="; report.octaveFoldedNotes
End 0

/' end of music_export_smoke.bas '/
