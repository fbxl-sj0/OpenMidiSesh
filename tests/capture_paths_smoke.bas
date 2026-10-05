/'
    Project: OpenSesh
    ---------------------------

    File: tests/capture_paths_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove that retained recording names are portable and non-destructive.

    Responsibilities:

        - verify target-specific path joining
        - verify Windows and Unix parent parsing on either build target
        - skip occupied files and occupied directory names
        - reject unsafe stems, extensions, and empty inputs

    This file intentionally does NOT contain:

        - user-profile policy
        - audio-device access
        - application GUI code
'/

#lang "fb"

#include once "../capture_paths.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Dim As String fixtureDirectory = Trim(Command(1))
If fixtureDirectory = "" Then
    test_Fail "fixture directory argument is required"
End If
If MkDir(fixtureDirectory) <> 0 AndAlso Dir(fixtureDirectory, fbDirectory) = "" Then _
    test_Fail "fixture directory could not be created"

Dim As String expectedJoin = fixtureDirectory + capturePaths_Separator() + _
    "capture.wav"
If capturePaths_Join(fixtureDirectory, "capture.wav") <> expectedJoin Then _
    test_Fail "target path separator was not used"
If capturePaths_Join(fixtureDirectory + capturePaths_Separator(), _
    "capture.wav") <> expectedJoin Then _
    test_Fail "existing trailing separator was duplicated"
If capturePaths_ParentDirectory("C:\Music\take.wav") <> "C:\Music" OrElse _
    capturePaths_ParentDirectory("/home/user/take.wav") <> "/home/user" OrElse _
    capturePaths_ParentDirectory("take.wav") <> "" Then _
    test_Fail "parent directory parsing failed"

Dim As String firstCandidate = capturePaths_NewFilename( _
    fixtureDirectory, "session-recording", ".wav")
If firstCandidate <> capturePaths_Join( _
    fixtureDirectory, "session-recording.wav") Then _
    test_Fail "first capture candidate was incorrect"

Dim As Integer fileNumber = FreeFile()
If Open(firstCandidate For Output Access Write As #fileNumber) <> 0 Then _
    test_Fail "occupied file fixture could not be created"
Print #fileNumber, "preserve"
Close #fileNumber

Dim As String secondCandidate = capturePaths_Join( _
    fixtureDirectory, "session-recording-1.wav")
If MkDir(secondCandidate) <> 0 Then _
    test_Fail "occupied directory fixture could not be created"
Dim As String selectedCandidate = capturePaths_NewFilename( _
    fixtureDirectory, "session-recording", ".wav")
If selectedCandidate <> capturePaths_Join( _
    fixtureDirectory, "session-recording-2.wav") Then _
    test_Fail "occupied capture names were not preserved"

If capturePaths_NewFilename("", "capture", ".wav") <> "" OrElse _
    capturePaths_NewFilename(fixtureDirectory, "../capture", ".wav") <> "" OrElse _
    capturePaths_NewFilename(fixtureDirectory, "capture", "wav") <> "" OrElse _
    capturePaths_NewFilename(fixtureDirectory, "capture", ".w/av") <> "" Then _
    test_Fail "unsafe capture path input was accepted"

If capturePaths_ParentDirectory(firstCandidate) <> fixtureDirectory OrElse _
    capturePaths_ParentDirectory(secondCandidate) <> fixtureDirectory Then _
    test_Fail "cleanup target escaped the isolated fixture directory"
' The exact file and directory were created above inside the runner-owned
' fixture path. They are validated again before this bounded cleanup.
' fblint: disable-next-line FBL761,FBL-IO-014 REASON: These exact runner-owned fixture paths were created and validated immediately above.
Kill firstCandidate
' fblint: disable-next-line FBL761 REASON: These exact runner-owned fixture paths were created and validated immediately above.
RmDir secondCandidate
' fblint: disable-next-line FBL761 REASON: These exact runner-owned fixture paths were created and validated immediately above.
RmDir fixtureDirectory
If Dir(firstCandidate) <> "" OrElse Dir(secondCandidate, fbDirectory) <> "" OrElse _
    Dir(fixtureDirectory, fbDirectory) <> "" Then _
    test_Fail "capture path fixtures were not removed"

Print "capture_paths=ok"
Print "occupied_names=2 invalid_inputs=4"
End 0

/' end of tests/capture_paths_smoke.bas '/
