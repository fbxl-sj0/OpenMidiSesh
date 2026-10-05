/'
    Project: OpenSesh
    File: tests/binary_file_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.
    Purpose: Exercise exact reads using the real FreeBASIC file runtime.
    Responsibilities: Check whole and partial reads, EOF, scalars, arrays,
        strings, invalid spans, and untouched storage after each buffer.
    Ownership: The test creates only the supplied fixture and closes its file.
    This file intentionally does NOT contain:

        - format parsers
        - simulated file I/O
'/

#lang "fb"

#include once "../binary_file_internal.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub

Dim As String filename = Trim(Command(1))
If filename = "" Then
    Print "usage: binary_file_smoke <fixture>"
    End 2
End If
Dim As Integer fileNumber = FreeFile()
If Open(filename For Output As #fileNumber) <> 0 Then _
    test_Fail "could not create the fixture"
Close #fileNumber
If Open(filename For Binary Access Write As #fileNumber) <> 0 Then _
    test_Fail "could not reopen the fixture"
Dim As String contents = "ABCD"
If Put(#fileNumber, 1, contents) <> 0 Then
    test_Fail "fixture write failed"
End If
Close #fileNumber
If Open(filename For Binary Access Read As #fileNumber) <> 0 Then _
    test_Fail "fixture read open failed"

Dim As UByte buffer(0 To 5) = {0, 0, 0, 0, 123, 124}
If binaryFile_ReadExact(fileNumber, 1, @buffer(0), 4) = 0 OrElse _
    buffer(0) <> 65 OrElse buffer(3) <> 68 OrElse _
    buffer(4) <> 123 OrElse buffer(5) <> 124 Then _
    test_Fail "complete byte-array read crossed its span"
Dim As String textValue = Space(2)
If binaryFile_ReadExact(fileNumber, 2, StrPtr(textValue), 2) = 0 OrElse _
    textValue <> "BC" Then test_Fail "string read changed its length or contents"
Dim As UByte scalarValue
If binaryFile_ReadExact(fileNumber, 4, @scalarValue, SizeOf(scalarValue)) = 0 _
    OrElse scalarValue <> 68 Then test_Fail "scalar read did not reach the last byte"

If binaryFile_ReadExact(fileNumber, 3, @buffer(0), 4) <> 0 OrElse _
    binaryFile_ReadExact(fileNumber, 5, @buffer(0), 1) <> 0 Then _
    test_Fail "short read or EOF was accepted as complete"
If buffer(4) <> 123 OrElse buffer(5) <> 124 Then _
    test_Fail "short read crossed its destination span"
If binaryFile_ReadExact(fileNumber, 0, @buffer(0), 1) <> 0 OrElse _
    binaryFile_ReadExact(fileNumber, 1, 0, 1) <> 0 OrElse _
    binaryFile_ReadExact(fileNumber, 1, @buffer(0), 0) <> 0 OrElse _
    binaryFile_ReadExact(fileNumber, 1, @buffer(0), -1) <> 0 OrElse _
    binaryFile_ReadExact(fileNumber, &H7FFFFFFFFFFFFFFFLL, @buffer(0), 2) <> 0 _
    Then test_Fail "invalid read span was accepted"
Close #fileNumber
If binaryFile_ReadExact(fileNumber, 1, @buffer(0), 1) <> 0 Then _
    test_Fail "closed file handle was accepted"

Print "binary_file=ok"
End 0

/' end of tests/binary_file_smoke.bas '/
