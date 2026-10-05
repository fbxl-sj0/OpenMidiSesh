/'
    Project: OpenSesh
    ---------------------------

    File: tests/atomic_file_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Module API: Test executable accepting one destination path; exercises
        the included atomicFile_* helpers and returns a process status.

    Purpose:

        Exercise the private atomic persistence primitive on the host OS.

    Responsibilities:

        - replace a longer destination with exact shorter binary content
        - verify occupied temporary names are never overwritten
        - repeat replacements and prove temporary files are removed
        - reject invalid destinations without changing a valid file

    Ownership:

        - this test owns only the fixture path supplied by its runner
        - it creates and removes one deliberate temporary-name collision

    This file intentionally does NOT contain:

        - MIDI or project serialization
        - simulated process crashes
        - user-interface behavior
'/

#lang "fb"

#include once "../src/atomic_file_internal.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Sub test_WriteDirect( _
    ByVal filename As String, _
    ByRef fileData As String _
)
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Output Access Write As #fileNumber) <> 0 Then _
        test_Fail "could not create direct fixture"
    Close #fileNumber
    fileNumber = FreeFile()
    If Open(filename For Binary Access Write As #fileNumber) <> 0 Then _
        test_Fail "could not open direct fixture"
    If Len(fileData) > 0 Then
        Put #fileNumber, 1, fileData
    End If
    Close #fileNumber
End Sub


Private Function test_ReadDirect(ByVal filename As String) As String
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then _
        test_Fail "could not read fixture"
    Dim As LongInt fileSize = Lof(fileNumber)
    Dim As String fileData
    If fileSize > 0 Then
        fileData = Space(CInt(fileSize))
        Get #fileNumber, 1, fileData
    End If
    Close #fileNumber
    Return fileData
End Function


Dim As String destinationFilename = Trim(Command(1))
If destinationFilename = "" Then
    Print "usage: atomic_file_smoke <destination>"
    End 2
End If

Dim As String initialData = String(16384, "X")
test_WriteDirect destinationFilename, initialData

Dim As String collisionFilename = destinationFilename + ".ose-tmp-" + _
    LTrim(Str(atomicFile_ProcessId())) + "-1"
Dim As String collisionData = "do not overwrite"
test_WriteDirect collisionFilename, collisionData

Dim As String binaryData = "short" + Chr(0) + Chr(255) + "payload"
If atomicFile_WriteVerified(destinationFilename, binaryData) = 0 Then _
    test_Fail "initial atomic replacement failed"
If test_ReadDirect(destinationFilename) <> binaryData Then _
    test_Fail "atomic replacement retained or changed bytes"
If test_ReadDirect(collisionFilename) <> collisionData Then _
    test_Fail "occupied temporary candidate was overwritten"

For replacementIndex As Integer = 1 To 80
    Dim As String nextData = "replacement-" + LTrim(Str(replacementIndex))
    If atomicFile_WriteVerified(destinationFilename, nextData) = 0 Then _
        test_Fail "repeated atomic replacement failed"
    If test_ReadDirect(destinationFilename) <> nextData Then _
        test_Fail "repeated atomic replacement returned wrong data"
Next

Dim As String invalidData = "must not replace valid destination"
If atomicFile_WriteVerified("", invalidData) <> 0 OrElse _
    atomicFile_WriteVerified(String(4097, "x"), invalidData) <> 0 OrElse _
    atomicFile_WriteVerified(destinationFilename + Chr(0), invalidData) <> 0 _
    Then test_Fail "invalid destination was accepted"
If test_ReadDirect(destinationFilename) <> "replacement-80" Then _
    test_Fail "invalid write changed the valid destination"

Dim As String unexpectedTemporary = Dir(destinationFilename + ".ose-tmp-*")
Dim As Integer collisionSeparator = InStrRev(collisionFilename, "\")
Dim As Integer unixSeparator = InStrRev(collisionFilename, "/")
If unixSeparator > collisionSeparator Then
    collisionSeparator = unixSeparator
End If
Dim As String collisionLeaf = Mid(collisionFilename, collisionSeparator + 1)
While unexpectedTemporary <> ""
    If unexpectedTemporary <> collisionFilename AndAlso _
        unexpectedTemporary <> collisionLeaf Then _
        test_Fail "successful replacement left a temporary file"
    unexpectedTemporary = Dir()
Wend

atomicFile_RemoveTemporary collisionFilename
If Len(Dir(collisionFilename)) > 0 Then _
    test_Fail "could not remove the deliberate temporary collision"
Print "atomic_file=ok"
Print "replacements=81 collision_preserved=1 invalid_paths=3"
End 0

/' end of tests/atomic_file_smoke.bas '/
