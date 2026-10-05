/'
    Project: OpenSesh
    ---------------------------

    File: tests/project_transaction_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove recoverable two-file project commits under deterministic faults.

    Responsibilities:

        - inject failures before the first and second destination commits
        - simulate interruption after either commit and after completion
        - verify rollback and restart recovery preserve exact prior bytes
        - verify new-file rollback and adversarial corrupt-journal refusal

    Ownership:

        - the test owns only paths derived from the supplied fixture base

    This file intentionally does NOT contain:

        - MIDI or project serialization
        - application globals
        - user-interface behavior
'/

#lang "fb"

#include once "../src/project_transaction.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Sub test_WriteFile( _
    ByVal filename As String, _
    ByRef fileData As String _
)
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Write As #fileNumber) <> 0 Then _
        test_Fail "fixture file could not be written"
    Put #fileNumber, 1, fileData
    Close #fileNumber
End Sub


Private Function test_ReadFile(ByVal filename As String) As String
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then _
        test_Fail "fixture file could not be read"
    Dim As LongInt fileSize = Lof(fileNumber)
    Dim As String fileData
    If fileSize > 0 Then
        fileData = Space(CInt(fileSize))
        Get #fileNumber, 1, fileData
    End If
    Close #fileNumber
    Return fileData
End Function


Private Sub test_RemoveFile(ByVal filename As String)
    If Len(Dir(filename)) > 0 Then
        Kill filename
    End If
End Sub


Private Function test_ReplaceJournalField( _
    ByRef journalData As String, _
    ByVal fieldName As String, _
    ByVal replacementValue As String _
) As String
    Dim As String prefixText = fieldName + " "
    Dim As Integer fieldStart = InStr(journalData, prefixText)
    If fieldStart <= 0 OrElse _
        (fieldStart > 1 AndAlso _
         Mid(journalData, fieldStart - 2, 2) <> Chr(13) + Chr(10)) Then _
        test_Fail "journal fixture field was not found"

    Dim As Integer valueStart = fieldStart + Len(prefixText)
    Dim As Integer valueEnd = InStr(valueStart, journalData, Chr(13) + Chr(10))
    If valueEnd <= valueStart Then
        test_Fail "journal fixture field was empty"
    End If
    Return Left(journalData, valueStart - 1) + replacementValue + _
        Mid(journalData, valueEnd)
End Function


Private Sub test_ResetPair( _
    ByVal midiFilename As String, _
    ByVal projectFilename As String, _
    ByRef oldMidiData As String, _
    ByRef oldProjectData As String _
)
    test_WriteFile midiFilename, oldMidiData
    test_WriteFile projectFilename, oldProjectData
End Sub


Private Function test_ReplaceJournalPath( _
    ByRef journalData As String, _
    ByVal fieldName As String, _
    ByVal replacementPath As String _
) As String
    Dim As String prefixText = fieldName + " "
    Dim As Integer fieldStart = InStr(journalData, prefixText)
    Dim As Integer headerEnd = InStr(fieldStart, journalData, Chr(13) + Chr(10))
    Dim As Integer pathEnd = InStr(headerEnd + 2, journalData, Chr(13) + Chr(10))
    If fieldStart <= 0 OrElse headerEnd <= fieldStart OrElse pathEnd <= headerEnd Then _
        test_Fail "journal path fixture was not found"
    Return Left(journalData, fieldStart - 1) + prefixText + _
        LTrim(Str(Len(replacementPath))) + Chr(13) + Chr(10) + _
        replacementPath + Mid(journalData, pathEnd)
End Function


Private Sub test_AssertPair( _
    ByVal midiFilename As String, _
    ByVal projectFilename As String, _
    ByRef expectedMidiData As String, _
    ByRef expectedProjectData As String _
)
    If test_ReadFile(midiFilename) <> expectedMidiData OrElse _
        test_ReadFile(projectFilename) <> expectedProjectData Then _
        test_Fail "transaction pair contains mismatched bytes"
End Sub


Private Sub test_AssertClean( _
    ByVal midiFilename As String, _
    ByVal projectFilename As String _
)
    If Len(Dir(projectFilename + ".ose-pair-transaction")) > 0 OrElse _
        Len(Dir(midiFilename + ".ose-tmp-*")) > 0 OrElse _
        Len(Dir(projectFilename + ".ose-tmp-*")) > 0 Then _
        test_Fail "transaction-owned journal or backup was not cleaned"
End Sub


Dim As String fixtureBase = Trim(Command(1))
If fixtureBase = "" Then
    test_Fail "fixture base path is required"
End If
Dim As String midiFilename = fixtureBase + ".mid"
Dim As String projectFilename = fixtureBase + ".ose"
Dim As String journalFilename = projectFilename + ".ose-pair-transaction"
Dim As String oldMidiData = "old-midi" + Chr(0) + String(8192, "M")
Dim As String oldProjectData = "old-project" + Chr(13) + Chr(10)
Dim As String newMidiData = "new-midi" + Chr(0) + String(1024, "N")
Dim As String newProjectData = "new-project" + Chr(13) + Chr(10)
Dim As String errorText

' A first-commit failure must not change either pre-existing destination.
test_ResetPair midiFilename, projectFilename, oldMidiData, oldProjectData
projectTransaction_TestInject OSE_PROJECT_TRANSACTION_FAIL_FIRST_COMMIT
If projectTransaction_SavePair(midiFilename, newMidiData, projectFilename, _
    newProjectData, errorText) <> 0 OrElse errorText = "" Then _
    test_Fail "first-commit failure injection was not reported"
test_AssertPair midiFilename, projectFilename, oldMidiData, oldProjectData
test_AssertClean midiFilename, projectFilename

' A second-commit failure occurs after MIDI replacement and must roll it back.
projectTransaction_TestInject OSE_PROJECT_TRANSACTION_FAIL_SECOND_COMMIT
If projectTransaction_SavePair(midiFilename, newMidiData, projectFilename, _
    newProjectData, errorText) <> 0 Then _
    test_Fail "second-commit failure injection was not reported"
test_AssertPair midiFilename, projectFilename, oldMidiData, oldProjectData
test_AssertClean midiFilename, projectFilename

' An interruption after the first commit leaves a prepared journal. Recovery
' must use it to restore both old destinations before any later project load.
projectTransaction_TestInject OSE_PROJECT_TRANSACTION_INTERRUPT_AFTER_FIRST
If projectTransaction_SavePair(midiFilename, newMidiData, projectFilename, _
    newProjectData, errorText) <> 0 OrElse _
    test_ReadFile(midiFilename) <> newMidiData OrElse _
    test_ReadFile(projectFilename) <> oldProjectData OrElse _
    Len(Dir(journalFilename)) = 0 Then _
    test_Fail "first-commit interruption state is incorrect"
Dim As String preparedJournal = test_ReadFile(journalFilename)
If projectTransaction_Recover(projectFilename, errorText) = 0 Then _
    test_Fail "first-commit interruption could not be recovered"
test_AssertPair midiFilename, projectFilename, oldMidiData, oldProjectData
test_AssertClean midiFilename, projectFilename

' If both files changed but PREPARED remains, recovery conservatively restores
' the old pair. The application never exposes an unconfirmed partial commit.
projectTransaction_TestInject OSE_PROJECT_TRANSACTION_INTERRUPT_AFTER_SECOND
If projectTransaction_SavePair(midiFilename, newMidiData, projectFilename, _
    newProjectData, errorText) <> 0 Then _
    test_Fail "second-commit interruption was not reported"
test_AssertPair midiFilename, projectFilename, newMidiData, newProjectData
If projectTransaction_Recover(projectFilename, errorText) = 0 Then _
    test_Fail "second-commit interruption could not be recovered"
test_AssertPair midiFilename, projectFilename, oldMidiData, oldProjectData
test_AssertClean midiFilename, projectFilename

' Once COMMITTED is durable, recovery keeps the new pair and only removes the
' backups and journal left by an interruption during cleanup.
projectTransaction_TestInject OSE_PROJECT_TRANSACTION_INTERRUPT_AFTER_COMMITTED
If projectTransaction_SavePair(midiFilename, newMidiData, projectFilename, _
    newProjectData, errorText) <> 0 OrElse Len(Dir(journalFilename)) = 0 Then _
    test_Fail "completed-transaction interruption was not preserved"
If projectTransaction_Recover(projectFilename, errorText) = 0 Then _
    test_Fail "completed transaction cleanup could not be recovered"
test_AssertPair midiFilename, projectFilename, newMidiData, newProjectData
test_AssertClean midiFilename, projectFilename

' A normal save replaces both images and leaves no transaction artifacts.
test_ResetPair midiFilename, projectFilename, oldMidiData, oldProjectData
If projectTransaction_SavePair(midiFilename, newMidiData, projectFilename, _
    newProjectData, errorText) = 0 Then test_Fail "normal pair commit failed"
test_AssertPair midiFilename, projectFilename, newMidiData, newProjectData
test_AssertClean midiFilename, projectFilename

' When neither destination existed, failed commit rollback must remove the
' newly-created first destination instead of manufacturing empty old files.
test_RemoveFile midiFilename
test_RemoveFile projectFilename
projectTransaction_TestInject OSE_PROJECT_TRANSACTION_FAIL_SECOND_COMMIT
If projectTransaction_SavePair(midiFilename, newMidiData, projectFilename, _
    newProjectData, errorText) <> 0 OrElse Len(Dir(midiFilename)) > 0 OrElse _
    Len(Dir(projectFilename)) > 0 Then _
    test_Fail "new-pair rollback left a partial destination"
test_AssertClean midiFilename, projectFilename

' Invalid journals are never trusted for rollback paths and remain available
' for inspection instead of being silently discarded. The structured cases
' exercise complete decimal consumption, canonical spelling, and field bounds.
test_ResetPair midiFilename, projectFilename, oldMidiData, oldProjectData
Dim As String corruptJournals(0 To 15)
corruptJournals(0) = "not a project transaction" + Chr(13) + Chr(10)
corruptJournals(1) = test_ReplaceJournalField( _
    preparedJournal, "STATE", "01")
corruptJournals(2) = test_ReplaceJournalField( _
    preparedJournal, "STATE", "999999999999999999999999")
corruptJournals(3) = test_ReplaceJournalField( _
    preparedJournal, "MIDI_EXISTED", "00")
corruptJournals(4) = test_ReplaceJournalField( _
    preparedJournal, "PROJECT_EXISTED", "2")
corruptJournals(5) = test_ReplaceJournalField( _
    preparedJournal, "MIDI_PATH", "+3")
corruptJournals(6) = test_ReplaceJournalField( _
    preparedJournal, "PROJECT_PATH", "3x")
corruptJournals(7) = test_ReplaceJournalField( _
    preparedJournal, "PROJECT_BACKUP", " 3")

Dim As String unsafeSuffixes(0 To 7) = {"", "not-owned", "123-1/../sentinel", _
    "123-1\..\sentinel", "123:stream", "123--1", "123-1/extra", "1-2-3"}
Dim As String committedJournal = test_ReplaceJournalField(preparedJournal, "STATE", "2")
For suffixIndex As Integer = 0 To UBound(unsafeSuffixes)
    corruptJournals(8 + suffixIndex) = test_ReplaceJournalPath(committedJournal, _
        "MIDI_BACKUP", midiFilename + ".ose-tmp-" + unsafeSuffixes(suffixIndex))
Next

For corruptIndex As Integer = 0 To UBound(corruptJournals)
    test_RemoveFile journalFilename
    test_WriteFile journalFilename, corruptJournals(corruptIndex)
    errorText = ""
    If projectTransaction_Recover(projectFilename, errorText) <> 0 OrElse _
        errorText <> _
            "project transaction journal is invalid; no files were changed" Then _
        test_Fail "corrupt journal was not rejected before recovery"
    test_AssertPair midiFilename, projectFilename, oldMidiData, oldProjectData
    If test_ReadFile(journalFilename) <> corruptJournals(corruptIndex) Then _
        test_Fail "corrupt journal was changed"
Next
test_RemoveFile journalFilename

#If Defined(__FB_WIN32__)
If projectTransaction_SavePair(midiFilename, newMidiData, UCase(midiFilename), _
    newProjectData, errorText) <> 0 Then _
    test_Fail "case-only aliases were accepted as two transaction destinations"
test_AssertPair midiFilename, projectFilename, oldMidiData, oldProjectData
#EndIf

Print "project_transaction=ok"
Print "commit_failures=2 interrupted_states=3 new_pair_rollback=1 " + _
    "corrupt_journal_rejections=16"
Print "project_transaction_corrupt_journal_rejections=16"
End 0

/' end of tests/project_transaction_smoke.bas '/
