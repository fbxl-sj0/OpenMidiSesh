/'
    Project: OpenSesh
    ---------------------------

    File: project_transaction.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements project_transaction.bi; declarations there define the shared interface.

    Purpose:

        Commit a project container and sibling MIDI image with rollback and
        restart recovery.

    Responsibilities:

        - preserve byte-exact backups before changing either destination
        - record a same-directory transaction journal before the first commit
        - roll both destinations back after an ordinary write failure
        - recover prepared, committed, or rolled-back journals after restart

    Ownership:

        Each operation closes its file handles before returning. Recovery
        owns only the validated journal, backup, and temporary paths; the
        caller retains ownership of both destination files.

    Recovery model:

        PREPARED means at least one destination may contain new bytes, so both
        originals are restored. COMMITTED means both new images are complete.
        ROLLED_BACK means restoration completed and only cleanup remains.

    This file intentionally does NOT contain:

        - document serialization
        - assumptions about GUI state
        - deletion of files outside validated transaction-owned paths
'/

#lang "fb"

#include once "project_transaction.bi"
#include once "numeric_text.bi"
#include once "atomic_file_internal.bi"

Const OSE_PROJECT_TRANSACTION_JOURNAL_SUFFIX As String = _
    ".ose-pair-transaction"
Const OSE_PROJECT_TRANSACTION_MAGIC As String = "OSEPAIRTRANSACTION 1"
Const OSE_PROJECT_TRANSACTION_STATE_PREPARED As Integer = 1
Const OSE_PROJECT_TRANSACTION_STATE_COMMITTED As Integer = 2
Const OSE_PROJECT_TRANSACTION_STATE_ROLLED_BACK As Integer = 3
Const OSE_PROJECT_TRANSACTION_MAX_JOURNAL_BYTES As Integer = 32768
Const OSE_PROJECT_TRANSACTION_MAX_FILE_BYTES As LongInt = 67108864
Const PROJECT_TRANSACTION_INJECT_NONE As Integer = 0
Const PROJECT_TRANSACTION_INJECT_FAIL_FIRST As Integer = 1
Const PROJECT_TRANSACTION_INJECT_FAIL_SECOND As Integer = 2
Const PROJECT_TRANSACTION_INJECT_AFTER_FIRST As Integer = 3
Const PROJECT_TRANSACTION_INJECT_AFTER_SECOND As Integer = 4
Const PROJECT_TRANSACTION_INJECT_AFTER_COMMITTED As Integer = 5

Type ProjectTransactionJournal
    As Integer stateValue
    As String midiFilename
    As Integer midiExisted
    As String midiBackup
    As String projectFilename
    As Integer projectExisted
    As String projectBackup
End Type

#If Defined(OSE_PROJECT_TRANSACTION_TESTING)
' fblint: disable-next-line FBL301 REASON: deterministic fault injection is private to this test build module.
Dim Shared projectTransaction_InjectedMode As Integer
#EndIf


' -------------------------------------------------------------------------
' Bounded path and file helpers
' -------------------------------------------------------------------------

Private Function projectTransaction_PathIsSafe( _
    ByVal filename As String _
) As Integer
    If filename = "" OrElse Len(filename) > ATOMIC_FILE_MAX_PATH_BYTES Then _
        Return 0
    If InStr(filename, Chr(0)) > 0 OrElse InStr(filename, Chr(10)) > 0 OrElse _
        InStr(filename, Chr(13)) > 0 Then Return 0
    Return -1
End Function


Private Function projectTransaction_BasePath( _
    ByVal filename As String _
) As String
    Dim As Integer separatorPosition = InStrRev(filename, "\")
    Dim As Integer slashPosition = InStrRev(filename, "/")
    If slashPosition > separatorPosition Then
        separatorPosition = slashPosition
    End If
    Dim As Integer dotPosition = InStrRev(filename, ".")
    If dotPosition <= separatorPosition Then
        Return filename
    End If
    Return Left(filename, dotPosition - 1)
End Function


Private Function projectTransaction_PathsAreSiblingPair( _
    ByVal midiFilename As String, _
    ByVal projectFilename As String _
) As Integer
    If projectTransaction_PathIsSafe(midiFilename) = 0 OrElse _
        projectTransaction_PathIsSafe(projectFilename) = 0 OrElse _
        midiFilename = projectFilename Then Return 0
#If Defined(__FB_WIN32__)
    If LCase(midiFilename) = LCase(projectFilename) Then
        Return 0
    End If
    Return IIf(LCase(projectTransaction_BasePath(midiFilename)) = _
        LCase(projectTransaction_BasePath(projectFilename)), -1, 0)
#Else
    Return IIf(projectTransaction_BasePath(midiFilename) = _
        projectTransaction_BasePath(projectFilename), -1, 0)
#EndIf
End Function


Private Function projectTransaction_PathsMatch( _
    ByVal firstPath As String, _
    ByVal secondPath As String _
) As Integer
#If Defined(__FB_WIN32__)
    Return IIf(LCase(firstPath) = LCase(secondPath), -1, 0)
#Else
    Return IIf(firstPath = secondPath, -1, 0)
#EndIf
End Function


Private Function projectTransaction_ReadOptional( _
    ByVal filename As String, _
    ByRef fileExisted As Integer, _
    ByRef fileData As String _
) As Integer
    fileExisted = 0
    fileData = ""
    If projectTransaction_PathIsSafe(filename) = 0 Then
        Return 0
    End If

    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then
        If Len(Dir(filename)) = 0 Then
            Return -1
        End If
        Return 0
    End If

    Dim As LongInt fileSize = Lof(fileNumber)
    If fileSize < 0 OrElse fileSize > OSE_PROJECT_TRANSACTION_MAX_FILE_BYTES Then
        Close #fileNumber
        Return 0
    End If
    If fileSize > 0 Then
        fileData = Space(CInt(fileSize))
        If binaryFile_ReadExact(fileNumber, 1, StrPtr(fileData), Len(fileData)) = 0 Then
            Close #fileNumber
            fileData = ""
            Return 0
        End If
    End If
    Close #fileNumber
    fileExisted = -1
    Return -1
End Function


Private Function projectTransaction_RemoveFile( _
    ByVal filename As String _
) As Integer
    If filename = "" Then
        Return -1
    End If
    If projectTransaction_PathIsSafe(filename) = 0 Then
        Return 0
    End If
    If Len(Dir(filename)) = 0 Then
        Return -1
    End If
    atomicFile_RemoveTemporary filename
    Return IIf(Len(Dir(filename)) = 0, -1, 0)
End Function


Private Sub projectTransaction_AppendLine( _
    ByRef textData As String, _
    ByVal lineText As String _
)
    textData += lineText + Chr(13) + Chr(10)
End Sub


Private Sub projectTransaction_AppendPath( _
    ByRef textData As String, _
    ByVal fieldName As String, _
    ByVal filename As String _
)
    projectTransaction_AppendLine textData, fieldName + " " + _
        LTrim(Str(Len(filename)))
    projectTransaction_AppendLine textData, filename
End Sub


Private Function projectTransaction_NextLine( _
    ByRef textData As String, _
    ByRef cursor As Integer, _
    ByRef lineText As String _
) As Integer
    lineText = ""
    If cursor < 1 OrElse cursor > Len(textData) Then
        Return 0
    End If
    Dim As Integer lineEnd = InStr(cursor, textData, Chr(10))
    If lineEnd = 0 Then
        Return 0
    End If
    lineText = Mid(textData, cursor, lineEnd - cursor)
    If Len(lineText) > 0 AndAlso Right(lineText, 1) = Chr(13) Then _
        lineText = Left(lineText, Len(lineText) - 1)
    cursor = lineEnd + 1
    Return -1
End Function


Private Function projectTransaction_ParseIntegerField( _
    ByRef textData As String, _
    ByRef cursor As Integer, _
    ByVal fieldName As String, _
    ByVal maximumValue As ULongInt, _
    ByRef fieldValue As Integer _
) As Integer
    Dim As String lineText
    If projectTransaction_NextLine(textData, cursor, lineText) = 0 Then
        Return 0
    End If
    Dim As String prefixText = fieldName + " "
    If Left(lineText, Len(prefixText)) <> prefixText Then
        Return 0
    End If
    Dim As String valueText = Mid(lineText, Len(prefixText) + 1)
    Dim As ULongInt parsedValue
    If valueText = "" OrElse valueText <> Trim(valueText) OrElse _
        numericText_ParseUnsigned( _
            valueText, parsedValue, maximumValue) = 0 Then Return 0

    ' Journals are generated canonically. Reject alternate spellings such as
    ' leading zeroes so a byte change cannot retain the same interpretation.
    If valueText <> LTrim(Str(parsedValue)) Then
        Return 0
    End If
    fieldValue = CInt(parsedValue)
    Return -1
End Function


Private Function projectTransaction_ParsePathField( _
    ByRef textData As String, _
    ByRef cursor As Integer, _
    ByVal fieldName As String, _
    ByRef filename As String _
) As Integer
    Dim As Integer expectedLength
    If projectTransaction_ParseIntegerField(textData, cursor, fieldName, _
        ATOMIC_FILE_MAX_PATH_BYTES, expectedLength) = 0 Then Return 0
    If projectTransaction_NextLine(textData, cursor, filename) = 0 OrElse _
        Len(filename) <> expectedLength Then Return 0
    If filename <> "" AndAlso projectTransaction_PathIsSafe(filename) = 0 Then _
        Return 0
    Return -1
End Function


' -------------------------------------------------------------------------
' Journal serialization and validation
' -------------------------------------------------------------------------

Private Function projectTransaction_BuildJournal( _
    ByRef journal As ProjectTransactionJournal, _
    ByRef journalData As String _
) As Integer
    journalData = ""
    projectTransaction_AppendLine journalData, _
        OSE_PROJECT_TRANSACTION_MAGIC
    projectTransaction_AppendLine journalData, "STATE " + _
        LTrim(Str(journal.stateValue))
    projectTransaction_AppendPath journalData, "MIDI_PATH", _
        journal.midiFilename
    projectTransaction_AppendLine journalData, "MIDI_EXISTED " + _
        LTrim(Str(IIf(journal.midiExisted <> 0, 1, 0)))
    projectTransaction_AppendPath journalData, "MIDI_BACKUP", _
        journal.midiBackup
    projectTransaction_AppendPath journalData, "PROJECT_PATH", _
        journal.projectFilename
    projectTransaction_AppendLine journalData, "PROJECT_EXISTED " + _
        LTrim(Str(IIf(journal.projectExisted <> 0, 1, 0)))
    projectTransaction_AppendPath journalData, "PROJECT_BACKUP", _
        journal.projectBackup
    Return IIf(Len(journalData) <= _
        OSE_PROJECT_TRANSACTION_MAX_JOURNAL_BYTES, -1, 0)
End Function


Private Function projectTransaction_BackupPathIsValid( _
    ByVal destinationFilename As String, _
    ByVal backupFilename As String, _
    ByVal destinationExisted As Integer _
) As Integer
    If destinationExisted = 0 Then
        Return IIf(backupFilename = "", -1, 0)
    End If
    If projectTransaction_PathIsSafe(backupFilename) = 0 Then
        Return 0
    End If
    Dim As String expectedPrefix = destinationFilename + ".ose-tmp-"
    If Left(backupFilename, Len(expectedPrefix)) <> expectedPrefix Then
        Return 0
    End If
    ' Only the decimal process/counter suffix generated by the atomic writer
    ' is owned. A prefix alone would also admit separators and parent traversal.
    Dim As String suffixText = Mid(backupFilename, Len(expectedPrefix) + 1)
    Dim As Integer separatorPosition = InStr(suffixText, "-")
    If separatorPosition <= 1 OrElse separatorPosition >= Len(suffixText) Then
        Return 0
    End If
    For characterIndex As Integer = 1 To Len(suffixText)
        If characterIndex = separatorPosition Then
            Continue For
        End If
        Dim As Integer characterCode = Asc(suffixText, characterIndex)
        If characterCode < 48 OrElse characterCode > 57 Then
            Return 0
        End If
    Next
    Return -1
End Function


Private Function projectTransaction_ParseJournal( _
    ByRef journalData As String, _
    ByVal expectedProjectFilename As String, _
    ByRef journal As ProjectTransactionJournal _
) As Integer
    If Len(journalData) <= 0 OrElse _
        Len(journalData) > OSE_PROJECT_TRANSACTION_MAX_JOURNAL_BYTES Then Return 0
    Dim As Integer cursor = 1
    Dim As String lineText
    If projectTransaction_NextLine(journalData, cursor, lineText) = 0 OrElse _
        lineText <> OSE_PROJECT_TRANSACTION_MAGIC Then Return 0
    If projectTransaction_ParseIntegerField(journalData, cursor, "STATE", _
        OSE_PROJECT_TRANSACTION_STATE_ROLLED_BACK, _
        journal.stateValue) = 0 Then Return 0
    If journal.stateValue <> OSE_PROJECT_TRANSACTION_STATE_PREPARED AndAlso _
        journal.stateValue <> OSE_PROJECT_TRANSACTION_STATE_COMMITTED AndAlso _
        journal.stateValue <> OSE_PROJECT_TRANSACTION_STATE_ROLLED_BACK Then _
        Return 0
    If projectTransaction_ParsePathField(journalData, cursor, "MIDI_PATH", _
        journal.midiFilename) = 0 OrElse _
        projectTransaction_ParseIntegerField(journalData, cursor, _
            "MIDI_EXISTED", 1ULL, journal.midiExisted) = 0 OrElse _
        projectTransaction_ParsePathField(journalData, cursor, "MIDI_BACKUP", _
            journal.midiBackup) = 0 OrElse _
        projectTransaction_ParsePathField(journalData, cursor, "PROJECT_PATH", _
        journal.projectFilename) = 0 OrElse _
        projectTransaction_ParseIntegerField(journalData, cursor, _
            "PROJECT_EXISTED", 1ULL, journal.projectExisted) = 0 OrElse _
        projectTransaction_ParsePathField(journalData, cursor, _
            "PROJECT_BACKUP", journal.projectBackup) = 0 Then Return 0
    If cursor <= Len(journalData) Then
        Return 0
    End If
    If journal.midiExisted <> 0 AndAlso journal.midiExisted <> 1 Then
        Return 0
    End If
    If journal.projectExisted <> 0 AndAlso journal.projectExisted <> 1 Then _
        Return 0
    journal.midiExisted = IIf(journal.midiExisted <> 0, -1, 0)
    journal.projectExisted = IIf(journal.projectExisted <> 0, -1, 0)
    If projectTransaction_PathsMatch(journal.projectFilename, _
        expectedProjectFilename) = 0 OrElse _
        projectTransaction_PathsAreSiblingPair(journal.midiFilename, _
            journal.projectFilename) = 0 OrElse _
        projectTransaction_BackupPathIsValid(journal.midiFilename, _
            journal.midiBackup, journal.midiExisted) = 0 OrElse _
        projectTransaction_BackupPathIsValid(journal.projectFilename, _
            journal.projectBackup, journal.projectExisted) = 0 Then Return 0
    Return -1
End Function


Private Function projectTransaction_WriteJournal( _
    ByVal journalFilename As String, _
    ByRef journal As ProjectTransactionJournal _
) As Integer
    Dim As String journalData
    If projectTransaction_BuildJournal(journal, journalData) = 0 Then
        Return 0
    End If
    Return atomicFile_WriteVerified(journalFilename, journalData)
End Function


' -------------------------------------------------------------------------
' Rollback and cleanup
' -------------------------------------------------------------------------

Private Function projectTransaction_RestoreDestination( _
    ByVal destinationFilename As String, _
    ByVal destinationExisted As Integer, _
    ByVal backupFilename As String _
) As Integer
    If destinationExisted = 0 Then _
        Return projectTransaction_RemoveFile(destinationFilename)

    Dim As Integer backupExisted
    Dim As String backupData
    If projectTransaction_ReadOptional(backupFilename, backupExisted, _
        backupData) = 0 OrElse backupExisted = 0 Then Return 0
    Return atomicFile_WriteVerified(destinationFilename, backupData)
End Function


Private Function projectTransaction_Cleanup( _
    ByVal journalFilename As String, _
    ByRef journal As ProjectTransactionJournal _
) As Integer
    Dim As Integer cleanupSucceeded = -1
    If projectTransaction_RemoveFile(journal.midiBackup) = 0 Then _
        cleanupSucceeded = 0
    If projectTransaction_RemoveFile(journal.projectBackup) = 0 Then _
        cleanupSucceeded = 0
    If cleanupSucceeded = 0 Then
        Return 0
    End If
    Return projectTransaction_RemoveFile(journalFilename)
End Function


Private Function projectTransaction_Rollback( _
    ByVal journalFilename As String, _
    ByRef journal As ProjectTransactionJournal _
) As Integer
    Dim As Integer midiRestored = projectTransaction_RestoreDestination( _
        journal.midiFilename, journal.midiExisted, journal.midiBackup)
    Dim As Integer projectRestored = projectTransaction_RestoreDestination( _
        journal.projectFilename, journal.projectExisted, journal.projectBackup)
    If midiRestored = 0 OrElse projectRestored = 0 Then
        Return 0
    End If

    journal.stateValue = OSE_PROJECT_TRANSACTION_STATE_ROLLED_BACK
    If projectTransaction_WriteJournal(journalFilename, journal) = 0 Then
        Return 0
    End If
    Return projectTransaction_Cleanup(journalFilename, journal)
End Function


' -------------------------------------------------------------------------
' Public recovery and commit operations
' -------------------------------------------------------------------------

Function projectTransaction_Recover( _
    ByVal projectFilename As String, _
    ByRef errorText As String _
) As Integer
    errorText = ""
    If projectTransaction_PathIsSafe(projectFilename) = 0 Then
        errorText = "invalid project transaction path"
        Return 0
    End If
    Dim As String journalFilename = projectFilename + _
        OSE_PROJECT_TRANSACTION_JOURNAL_SUFFIX
    Dim As Integer journalExisted
    Dim As String journalData
    If projectTransaction_ReadOptional(journalFilename, journalExisted, _
        journalData) = 0 Then
        errorText = "project transaction journal could not be read"
        Return 0
    End If
    If journalExisted = 0 Then
        Return -1
    End If

    Dim As ProjectTransactionJournal journal
    If projectTransaction_ParseJournal(journalData, projectFilename, _
        journal) = 0 Then
        errorText = "project transaction journal is invalid; no files were changed"
        Return 0
    End If

    If journal.stateValue = OSE_PROJECT_TRANSACTION_STATE_PREPARED Then
        If projectTransaction_Rollback(journalFilename, journal) = 0 Then
            errorText = "interrupted project transaction could not be restored"
            Return 0
        End If
    ElseIf projectTransaction_Cleanup(journalFilename, journal) = 0 Then
        errorText = "completed project transaction cleanup failed"
        Return 0
    End If
    Return -1
End Function


Function projectTransaction_SavePair( _
    ByVal midiFilename As String, _
    ByRef midiData As String, _
    ByVal projectFilename As String, _
    ByRef projectData As String, _
    ByRef errorText As String _
) As Integer
    errorText = ""
    If projectTransaction_PathsAreSiblingPair(midiFilename, _
        projectFilename) = 0 Then
        errorText = "project and MIDI destinations are not a sibling pair"
        Return 0
    End If
    If Len(midiData) <= 0 OrElse _
        Len(midiData) > OSE_PROJECT_TRANSACTION_MAX_FILE_BYTES OrElse _
        Len(projectData) <= 0 OrElse _
        Len(projectData) > OSE_PROJECT_TRANSACTION_MAX_FILE_BYTES Then
        errorText = "serialized project data is empty or exceeds its bound"
        Return 0
    End If
    If projectTransaction_Recover(projectFilename, errorText) = 0 Then
        Return 0
    End If

    Dim As ProjectTransactionJournal journal
    journal.stateValue = OSE_PROJECT_TRANSACTION_STATE_PREPARED
    journal.midiFilename = midiFilename
    journal.projectFilename = projectFilename
    Dim As String midiOriginal
    Dim As String projectOriginal
    If projectTransaction_ReadOptional(midiFilename, journal.midiExisted, _
        midiOriginal) = 0 OrElse _
        projectTransaction_ReadOptional(projectFilename, _
            journal.projectExisted, projectOriginal) = 0 Then
        errorText = "existing project files could not be preserved"
        Return 0
    End If

    If journal.midiExisted <> 0 Then
        If atomicFile_TemporaryName(midiFilename, journal.midiBackup) = 0 OrElse _
            atomicFile_WriteVerified(journal.midiBackup, midiOriginal) = 0 Then
            errorText = "MIDI rollback backup could not be created"
            Return 0
        End If
    End If
    If journal.projectExisted <> 0 Then
        If atomicFile_TemporaryName(projectFilename, _
            journal.projectBackup) = 0 OrElse _
            atomicFile_WriteVerified(journal.projectBackup, _
                projectOriginal) = 0 Then
            projectTransaction_RemoveFile journal.midiBackup
            errorText = "project rollback backup could not be created"
            Return 0
        End If
    End If

    Dim As String journalFilename = projectFilename + _
        OSE_PROJECT_TRANSACTION_JOURNAL_SUFFIX
    If projectTransaction_WriteJournal(journalFilename, journal) = 0 Then
        projectTransaction_RemoveFile journal.midiBackup
        projectTransaction_RemoveFile journal.projectBackup
        errorText = "project transaction journal could not be created"
        Return 0
    End If

    Dim As Integer injectionMode
#If Defined(OSE_PROJECT_TRANSACTION_TESTING)
    injectionMode = projectTransaction_InjectedMode
    projectTransaction_InjectedMode = PROJECT_TRANSACTION_INJECT_NONE
#EndIf

    If injectionMode = PROJECT_TRANSACTION_INJECT_FAIL_FIRST OrElse _
        atomicFile_WriteVerified(midiFilename, midiData) = 0 Then
        If projectTransaction_Rollback(journalFilename, journal) = 0 Then
            errorText = "MIDI commit failed and rollback remains pending"
        Else
            errorText = "MIDI commit failed; original files were restored"
        End If
        Return 0
    End If
    If injectionMode = PROJECT_TRANSACTION_INJECT_AFTER_FIRST Then
        errorText = "simulated interruption after MIDI commit"
        Return 0
    End If

    If injectionMode = PROJECT_TRANSACTION_INJECT_FAIL_SECOND OrElse _
        atomicFile_WriteVerified(projectFilename, projectData) = 0 Then
        If projectTransaction_Rollback(journalFilename, journal) = 0 Then
            errorText = "project commit failed and rollback remains pending"
        Else
            errorText = "project commit failed; original files were restored"
        End If
        Return 0
    End If
    If injectionMode = PROJECT_TRANSACTION_INJECT_AFTER_SECOND Then
        errorText = "simulated interruption after project commit"
        Return 0
    End If

    journal.stateValue = OSE_PROJECT_TRANSACTION_STATE_COMMITTED
    If projectTransaction_WriteJournal(journalFilename, journal) = 0 Then
        errorText = "project files committed but completion journal failed"
        Return 0
    End If
    If injectionMode = PROJECT_TRANSACTION_INJECT_AFTER_COMMITTED Then
        errorText = "simulated interruption after completed journal"
        Return 0
    End If
    If projectTransaction_Cleanup(journalFilename, journal) = 0 Then
        errorText = "project files committed; transaction cleanup is pending"
        Return 0
    End If
    Return -1
End Function


#If Defined(OSE_PROJECT_TRANSACTION_TESTING)

Sub projectTransaction_TestInject(ByVal injectionMode As Integer)
    If injectionMode < PROJECT_TRANSACTION_INJECT_NONE OrElse _
        injectionMode > PROJECT_TRANSACTION_INJECT_AFTER_COMMITTED Then
        projectTransaction_InjectedMode = PROJECT_TRANSACTION_INJECT_NONE
    Else
        projectTransaction_InjectedMode = injectionMode
    End If
End Sub

#EndIf

/' end of project_transaction.bas '/
