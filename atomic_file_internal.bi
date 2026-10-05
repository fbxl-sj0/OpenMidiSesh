/'
    Project: OpenSesh
    ---------------------------

    File: atomic_file_internal.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Internal atomicFile_* helpers; include privately in persistence modules.

    Purpose:

        Give persistence modules a private, cross-platform atomic file writer.

    Responsibilities:

        - create a same-directory temporary file without touching the target
        - write and byte-verify the complete temporary image
        - atomically replace the destination through the operating system
        - remove a failed temporary file without deleting the destination

    Ownership:

        - the caller retains ownership of its destination path and data
        - this helper owns only its generated `.ose-tmp-*` file

    This file intentionally does NOT contain:

        - a public application API
        - serialization or file-format logic
        - backup retention or cloud synchronization
'/

#ifndef __OSE_ATOMIC_FILE_INTERNAL_BI__
#define __OSE_ATOMIC_FILE_INTERNAL_BI__

#include once "binary_file_internal.bi"

#If Defined(__FB_WIN32__)

#include once "windows.bi"

Const ATOMIC_FILE_REPLACE_EXISTING As ULong = &H1
Const ATOMIC_FILE_WRITE_THROUGH As ULong = &H8

#ElseIf Defined(__FB_ANDROID__) Or Defined(__FB_AROS__)

#include once "crt/stdio.bi"

#Else

#include once "crt/stdio.bi"
#include once "crt/unistd.bi"

#EndIf

Const ATOMIC_FILE_MAX_PATH_BYTES As Integer = 4096
Const ATOMIC_FILE_CANDIDATE_ATTEMPTS As Integer = 64


Private Function atomicFile_ProcessId() As ULong
#If Defined(__FB_WIN32__)
    Return GetCurrentProcessId()
#ElseIf Defined(__FB_ANDROID__) Or Defined(__FB_AROS__)
    /'
        The Android and AROS CRT snapshots do not expose getpid through
        unistd.bi. A monotonic per-process counter still owns uniqueness;
        this bounded timer seed avoids restarting at the same candidate after
        a crash.
    '/
    Return CULng(Timer * 1000.0)
#Else
    Dim As Integer processId = getpid()
    If processId < 0 Then Return 0
    Return CULng(processId)
#EndIf
End Function


Private Sub atomicFile_RemoveTemporary(ByVal temporaryFilename As String)
    If temporaryFilename = "" Then Exit Sub
#If Defined(__FB_WIN32__)
    ' fblint: disable-next-line FBL310 REASON: windows.bi declares DeleteFileA for Windows builds.
    DeleteFileA StrPtr(temporaryFilename)
#Else
    ' fblint: disable-next-line FBL310 REASON: crt/stdio.bi declares remove for Unix and Android builds.
    remove StrPtr(temporaryFilename)
#EndIf
End Sub


Private Function atomicFile_Replace( _
    ByVal temporaryFilename As String, _
    ByVal destinationFilename As String _
) As Integer
#If Defined(__FB_WIN32__)
    Dim As ULong flags = ATOMIC_FILE_REPLACE_EXISTING Or _
        ATOMIC_FILE_WRITE_THROUGH
    Return IIf(MoveFileExA( _
        StrPtr(temporaryFilename), StrPtr(destinationFilename), flags) <> 0, _
        -1, 0)
#Else
    ' fblint: disable-next-line FBL310 REASON: crt/stdio.bi declares rename for Unix builds.
    Return IIf(rename( _
        StrPtr(temporaryFilename), StrPtr(destinationFilename)) = 0, -1, 0)
#EndIf
End Function


Private Function atomicFile_TemporaryName( _
    ByVal destinationFilename As String, _
    ByRef temporaryFilename As String _
) As Integer
    Static As ULong candidateCounter

    temporaryFilename = ""
    For attempt As Integer = 1 To ATOMIC_FILE_CANDIDATE_ATTEMPTS
        candidateCounter += 1
        If candidateCounter = 0 Then candidateCounter = 1
        Dim As String candidate = destinationFilename + ".ose-tmp-" + _
            LTrim(Str(atomicFile_ProcessId())) + "-" + _
            LTrim(Str(candidateCounter))
        If Len(candidate) > ATOMIC_FILE_MAX_PATH_BYTES Then Return 0
        If Len(Dir(candidate)) = 0 Then
            temporaryFilename = candidate
            Return -1
        End If
    Next
    Return 0
End Function


Private Function atomicFile_WriteVerified( _
    ByVal destinationFilename As String, _
    ByRef fileData As String _
) As Integer
    /'
        Checked FreeBASIC builds use resumable runtime-error labels around file
        operations. Keep scalar state above those labels so GCC can prove that
        every generated resume path observes initialized storage.
    '/
    Dim As LongInt writtenBytes = 0

    If destinationFilename = "" OrElse _
        Len(destinationFilename) > ATOMIC_FILE_MAX_PATH_BYTES OrElse _
        InStr(destinationFilename, Chr(0)) > 0 Then Return 0

    Dim As String temporaryFilename
    If atomicFile_TemporaryName( _
        destinationFilename, temporaryFilename) = 0 Then Return 0

    Dim As Integer fileNumber = FreeFile()
    If Open(temporaryFilename For Output Access Write As #fileNumber) <> 0 Then
        ' fblint: disable-next-line FBL-IO-004 REASON: a failed Open does not own a file handle.
        Return 0
    End If
    Close #fileNumber

    fileNumber = FreeFile()
    If Open(temporaryFilename For Binary Access Write As #fileNumber) <> 0 Then
        ' fblint: disable-next-line FBL-IO-004 REASON: a failed Open does not own a file handle.
        atomicFile_RemoveTemporary temporaryFilename
        Return 0
    End If
    If Len(fileData) > 0 Then Put #fileNumber, 1, fileData
    Close #fileNumber

    fileNumber = FreeFile()
    If Open(temporaryFilename For Binary Access Read As #fileNumber) <> 0 Then
        ' fblint: disable-next-line FBL-IO-004 REASON: a failed Open does not own a file handle.
        atomicFile_RemoveTemporary temporaryFilename
        Return 0
    End If
    writtenBytes = Lof(fileNumber)
    Dim As String verifiedData
    If writtenBytes = Len(fileData) AndAlso writtenBytes > 0 Then
        verifiedData = Space(CInt(writtenBytes))
        If binaryFile_ReadExact(fileNumber, 1, StrPtr(verifiedData), _
            Len(verifiedData)) = 0 Then
            Close #fileNumber
            atomicFile_RemoveTemporary temporaryFilename
            Return 0
        End If
    End If
    Close #fileNumber

    If writtenBytes <> Len(fileData) OrElse _
        (writtenBytes > 0 AndAlso verifiedData <> fileData) Then
        atomicFile_RemoveTemporary temporaryFilename
        Return 0
    End If

    If atomicFile_Replace(temporaryFilename, destinationFilename) = 0 Then
        atomicFile_RemoveTemporary temporaryFilename
        Return 0
    End If
    Return -1
End Function

#endif

/' end of atomic_file_internal.bi '/
