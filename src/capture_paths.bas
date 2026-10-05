/'
    Project: OpenSesh
    ---------------------------

    File: capture_paths.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements capture_paths.bi; declarations there define the shared interface.

    Purpose:

        Build safe, portable filenames for audio captured by the editor.

    Responsibilities:

        - keep Windows and Unix directory separators out of application code
        - recognize the parent of paths received from either platform
        - avoid overwriting the first one thousand retained capture names

    This file intentionally does NOT contain:

        - assumptions about a writable installation directory
        - environment-variable or user-profile selection
        - audio-device control
'/

#lang "fb"

#include once "capture_paths.bi"

' -------------------------------------------------------------------------
' Portable path operations
' -------------------------------------------------------------------------

Public Function capturePaths_Separator() As String
#If Defined(__FB_WIN32__)
    Return "\"
#Else
    Return "/"
#EndIf
End Function


Public Function capturePaths_Join( _
    ByVal directoryName As String, _
    ByVal leafName As String _
) As String
    directoryName = Trim(directoryName)
    leafName = Trim(leafName)
    If directoryName = "" OrElse leafName = "" Then
        Return ""
    End If
    If Len(directoryName) > OSE_CAPTURE_PATH_MAX_BYTES OrElse _
        Len(leafName) > OSE_CAPTURE_PATH_MAX_BYTES Then
        Return ""
    End If

    Dim As String finalCharacter = Right(directoryName, 1)
    Dim As String joinedPath
    If finalCharacter = "\" OrElse finalCharacter = "/" Then
        joinedPath = directoryName + leafName
    Else
        joinedPath = directoryName + capturePaths_Separator() + leafName
    End If
    If Len(joinedPath) > OSE_CAPTURE_PATH_MAX_BYTES Then
        Return ""
    End If
    Return joinedPath
End Function


Public Function capturePaths_ParentDirectory( _
    ByVal filename As String _
) As String
    filename = Trim(filename)
    If filename = "" OrElse Len(filename) > OSE_CAPTURE_PATH_MAX_BYTES Then
        Return ""
    End If

    Dim As Integer separatorPosition = InStrRev(filename, "\")
    Dim As Integer slashPosition = InStrRev(filename, "/")
    If slashPosition > separatorPosition Then
        separatorPosition = slashPosition
    End If
    If separatorPosition <= 0 Then
        Return ""
    End If

    ' Preserve both POSIX and drive-letter filesystem roots.
    If separatorPosition = 1 Then
        Return Left(filename, 1)
    End If
    If separatorPosition = 3 AndAlso Mid(filename, 2, 1) = ":" Then
        Return Left(filename, 3)
    End If
    Return Left(filename, separatorPosition - 1)
End Function


Private Function capturePaths_NamePartIsSafe(ByVal namePart As String) As Integer
    If namePart = "" OrElse InStr(namePart, Chr(0)) > 0 OrElse _
        InStr(namePart, Chr(10)) > 0 OrElse InStr(namePart, Chr(13)) > 0 OrElse _
        InStr(namePart, "\") > 0 OrElse InStr(namePart, "/") > 0 OrElse _
        InStr(namePart, ":") > 0 Then
        Return 0
    End If
    Return -1
End Function


Private Function capturePaths_Exists(ByVal filename As String) As Integer
    If Dir(filename) <> "" Then
        Return -1
    End If
    If Dir(filename, fbDirectory Or fbHidden Or fbSystem Or fbReadOnly) <> "" Then
        Return -1
    End If
    Return 0
End Function


Public Function capturePaths_NewFilename( _
    ByVal directoryName As String, _
    ByVal filenameStem As String, _
    ByVal extensionText As String _
) As String
    directoryName = Trim(directoryName)
    filenameStem = Trim(filenameStem)
    extensionText = Trim(extensionText)
    If directoryName = "" OrElse _
        capturePaths_NamePartIsSafe(filenameStem) = 0 OrElse _
        capturePaths_NamePartIsSafe(extensionText) = 0 OrElse _
        Left(extensionText, 1) <> "." Then
        Return ""
    End If

    For candidateIndex As Integer = 0 To OSE_CAPTURE_PATH_CANDIDATES - 1
        Dim As String suffixText
        If candidateIndex > 0 Then
            suffixText = "-" + LTrim(Str(candidateIndex))
        End If
        Dim As String candidate = capturePaths_Join( _
            directoryName, filenameStem + suffixText + extensionText)
        If candidate = "" Then
            Return ""
        End If
        If capturePaths_Exists(candidate) = 0 Then
            Return candidate
        End If
    Next
    Return ""
End Function

/' end of capture_paths.bas '/
