/'
    Project: OpenSesh
    File: tests/wav_export_failure_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Module API: Test executable accepting one destination path; supplies six
        C ABI fb_sfxOutput* stubs to wav_export_sfx.bas.

    Purpose: Exercise WAV export failures without requiring an audio driver.
    Responsibilities: Inject a partial saver failure, preserve the destination,
        reject invalid capture inputs, and verify temporary-file cleanup.
    Ownership: This test owns only its supplied fixture and generated siblings.
    This file intentionally does NOT contain:

        - audio synthesis
        - WAV format parsing
'/

#lang "fb"

#include once "../src/wav_export_sfx.bi"

' The adapter links against these exact C entry points. Replacing the saver
' in this test makes a partial write deterministic without filling a disk.
Dim Shared As Integer test_SaveFails
Dim Shared As Integer test_StartCalls
Dim Shared As Integer test_StopCalls

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub

Private Sub test_WriteFile(ByVal filename As String, ByVal fileData As String)
    Dim As Integer writeResult = -1
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Output As #fileNumber) <> 0 Then _
        test_Fail "could not create the saver fixture"
    Close #fileNumber
    If Open(filename For Binary Access Write As #fileNumber) <> 0 Then _
        test_Fail "could not reopen the saver fixture"
    writeResult = Put(#fileNumber, 1, fileData)
    Close #fileNumber
    If writeResult <> 0 Then
        test_Fail "could not write the saver fixture"
    End If
End Sub

Private Function test_ReadFile(ByVal filename As String) As String
    Dim As LongInt fileBytes = 0
    Dim As Integer readResult = -1
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then _
        test_Fail "could not inspect the retained destination"
    fileBytes = Lof(fileNumber)
    If fileBytes < 1 OrElse fileBytes > 1024 Then
        Close #fileNumber
        test_Fail "unexpected saver fixture size"
    End If
    Dim As String fileData = Space(CInt(fileBytes))
    readResult = Get(#fileNumber, 1, fileData)
    Close #fileNumber
    If readResult <> 0 Then
        test_Fail "could not read the saver fixture"
    End If
    Return fileData
End Function

Public Function fb_sfxOutputSampleRate CDecl Alias "fb_sfxOutputSampleRate" () As Long
    Return 48000
End Function

Public Function fb_sfxOutputUnderruns CDecl Alias "fb_sfxOutputUnderruns" () As ULongInt
    Return 0
End Function

Public Function fb_sfxOutputCaptureStart CDecl Alias "fb_sfxOutputCaptureStart" () As Long
    test_StartCalls += 1
    Return 0
End Function

Public Function fb_sfxOutputCaptureReserve CDecl Alias "fb_sfxOutputCaptureReserve" ( _
    ByVal frames As Long) As Long
    If frames < 1 Then
        Return -1
    End If
    Return 0
End Function

Public Sub fb_sfxOutputCaptureStop CDecl Alias "fb_sfxOutputCaptureStop" ()
    test_StopCalls += 1
End Sub

Public Function fb_sfxOutputCaptureSave CDecl Alias "fb_sfxOutputCaptureSave" ( _
    ByVal filename As Const ZString Ptr) As Long
    If filename = 0 Then
        Return -1
    End If
    If test_SaveFails <> 0 Then
        test_WriteFile *filename, "partial output"
        Return -1
    End If
    test_WriteFile *filename, "complete rendered output"
    Return 0
End Function

' -------------------------------------------------------------------------
' Destination preservation and capture lifecycle
' -------------------------------------------------------------------------

Dim As String destination = Trim(Command(1))
If destination = "" Then
    Print "usage: wav_export_failure_smoke <destination.wav>"
    End 2
End If
Dim As OseWavExportState exportState
wavExport_Initialize exportState
Dim As String errorText
Dim As ULongInt underrunCount
Const testDurationSeconds As Double = 1.0
test_WriteFile destination, "previous complete export"

test_SaveFails = -1
If wavExport_Begin(exportState, destination, testDurationSeconds, errorText) = 0 Then _
    test_Fail "could not prepare the failed save"
If wavExport_Finish(exportState, underrunCount, errorText) <> 0 OrElse _
    errorText = "" OrElse exportState.active <> 0 OrElse _
    test_StopCalls <> 1 Then test_Fail "failed save retained capture state"
If test_ReadFile(destination) <> "previous complete export" Then _
    test_Fail "partial WAV save destroyed the previous destination"
If Dir(destination + ".ose-tmp-*") <> "" Then _
    test_Fail "failed WAV save left a temporary file"

test_SaveFails = 0
If wavExport_Begin(exportState, destination, testDurationSeconds, errorText) = 0 OrElse _
    wavExport_Finish(exportState, underrunCount, errorText) = 0 Then _
    test_Fail "export did not recover after a failed save"
If test_ReadFile(destination) <> "complete rendered output" OrElse _
    exportState.active <> 0 OrElse exportState.filename <> "" Then _
    test_Fail "successful replacement did not commit or clear state"
If Dir(destination + ".ose-tmp-*") <> "" Then _
    test_Fail "successful WAV save left a temporary file"

' A file cannot replace a directory. The saver succeeds, then the operating
' system rejects the commit; the adapter must remove only its temporary file.
Dim As String blockedDestination = destination + ".directory"
If MkDir(blockedDestination) <> 0 Then _
    test_Fail "could not create the blocked destination"
If wavExport_Begin(exportState, blockedDestination, testDurationSeconds, errorText) = 0 OrElse _
    wavExport_Finish(exportState, underrunCount, errorText) <> 0 OrElse _
    exportState.active <> 0 Then test_Fail "directory destination was accepted"
If Dir(blockedDestination + ".ose-tmp-*") <> "" Then _
    test_Fail "rejected commit left a temporary file"
If RmDir(blockedDestination) <> 0 Then _
    test_Fail "rejected commit damaged the existing directory"

' Quiet NaN in IEEE-754 binary64 form avoids generating a floating exception
' while testing values that ordered comparisons alone do not reject.
Dim As Double invalidSeconds = CvD(MkLongInt(&H7FF8000000000000))
Dim As Integer startsBeforeInvalid = test_StartCalls
If wavExport_Begin(exportState, destination + Chr(0) + ".ignored", _
    testDurationSeconds, errorText) <> 0 OrElse _
    wavExport_Begin(exportState, String(4097, "x"), testDurationSeconds, errorText) <> 0 OrElse _
    wavExport_Begin(exportState, destination, invalidSeconds, errorText) <> 0 _
    Then test_Fail "invalid path or duration started a capture"
If test_StartCalls <> startsBeforeInvalid OrElse exportState.active <> 0 Then _
    test_Fail "invalid input changed the capture runtime"
If test_ReadFile(destination) <> "complete rendered output" Then _
    test_Fail "invalid input changed the destination"

Print "wav_export_failure=ok"
End 0

/' end of tests/wav_export_failure_smoke.bas '/
