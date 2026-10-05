/'
    Project: omaGUI
    ---------------

    File: filesystem.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements filesystem.bi; declarations there define the interface.

    Purpose:

        Provide a bounded directory listing interface for native applications.

    Responsibilities:

        - keep Win32 directory traversal gated inside omaGUI
        - use the FreeBASIC runtime directory iterator on other platforms
        - return entry names and attributes through a callback

    This file intentionally does NOT contain:

        - application file filters or search logic
        - file content loading or saving
        - file dialog state or widgets
'/

#lang "fb"

#include once "src/system/filesystem.bi"
#include once "dir.bi"
#include once "vbcompat.bi"

#if defined(__FB_WIN32__)
#include once "windows.bi"
#endif

Private Function system_EmitEntry( _
    ByRef entryName As Const String, _
    ByVal attributes As UInteger, _
    ByVal handler As SystemDirectoryEntryHandler, _
    ByVal context As Any Ptr _
) As Integer

    If entryName = "" OrElse entryName = "." OrElse entryName = ".." Then _
        Return 0
    If handler = 0 Then Return 0
    Return handler(entryName, attributes, context)

End Function


Function system_EnumerateDirectory( _
    ByRef directoryPath As Const String, _
    ByVal entryKinds As Integer, _
    ByVal handler As SystemDirectoryEntryHandler, _
    ByVal context As Any Ptr _
) As Integer

    Dim As Integer entryCount
    Dim As String searchPattern = directoryPath

    If directoryPath = "" OrElse handler = 0 Then Return -1
    If (entryKinds And _
        (SYSTEM_DIRECTORY_FILES Or SYSTEM_DIRECTORY_FOLDERS)) = 0 Then _
        Return 0

#if defined(__FB_WIN32__)
    Dim As WIN32_FIND_DATAA findData
    Dim As HANDLE findHandle
    Dim As String entryName
    Dim As UInteger attributes

    If Right(searchPattern, 1) <> "/" AndAlso _
       Right(searchPattern, 1) <> Chr(92) Then searchPattern &= Chr(92)
    searchPattern &= "*"

    findHandle = FindFirstFileA(StrPtr(searchPattern), @findData)
    If findHandle = INVALID_HANDLE_VALUE Then Return 0

    Do
        entryName = findData.cFileName
        attributes = findData.dwFileAttributes
        If ((attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY) <> 0 AndAlso _
            (entryKinds And SYSTEM_DIRECTORY_FOLDERS) <> 0) OrElse _
           ((attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY) = 0 AndAlso _
            (entryKinds And SYSTEM_DIRECTORY_FILES) <> 0) Then
            entryCount += 1
            If system_EmitEntry( _
                entryName, attributes, handler, context _
            ) <> 0 Then Exit Do
        End If
    Loop While FindNextFileA(findHandle, @findData) <> 0

    FindClose(findHandle)
#else
    Dim As Integer attributes
    Dim As Integer stopEnumeration
    Dim As String entryName

    If Right(searchPattern, 1) <> "/" AndAlso _
       Right(searchPattern, 1) <> Chr(92) Then searchPattern &= "/"
    searchPattern &= "*"

    If (entryKinds And SYSTEM_DIRECTORY_FOLDERS) <> 0 Then
        entryName = Dir( _
            searchPattern, fbDirectory Or fbReadOnly Or fbHidden Or fbSystem, attributes _
        )
        While entryName <> ""
            If stopEnumeration = 0 AndAlso _
               (attributes And fbDirectory) <> 0 Then
                entryCount += 1
                If system_EmitEntry( _
                    entryName, CUInt(attributes), handler, context _
                ) <> 0 Then stopEnumeration = -1
            End If
            entryName = Dir(attributes)
        Wend
    End If

    If stopEnumeration <> 0 Then Return entryCount

    If (entryKinds And SYSTEM_DIRECTORY_FILES) <> 0 Then
        entryName = Dir( _
            searchPattern, _
            fbNormal Or fbReadOnly Or fbHidden Or fbSystem Or fbArchive, _
            attributes _
        )
        While entryName <> ""
            If stopEnumeration = 0 AndAlso _
               (attributes And fbDirectory) = 0 Then
                entryCount += 1
                If system_EmitEntry( _
                    entryName, CUInt(attributes), handler, context _
                ) <> 0 Then stopEnumeration = -1
            End If
            entryName = Dir(attributes)
        Wend
    End If
#endif

    Return entryCount

End Function


Function system_IsDirectory(ByRef directoryPath As Const String) As Integer

    If directoryPath = "" Then Return 0

#if defined(__FB_WIN32__)
    Dim As DWORD attributes = GetFileAttributesA(StrPtr(directoryPath))
    ' fblint: disable-next-line FBL310 REASON: The Windows-only branch uses declarations supplied by windows.bi and the system headers.
    If attributes = INVALID_FILE_ATTRIBUTES Then Return 0
    ' fblint: disable-next-line FBL310 REASON: The Windows-only branch uses declarations supplied by windows.bi and the system headers.
    Return IIf((attributes And FILE_ATTRIBUTE_DIRECTORY) <> 0, -1, 0)
#else
    Dim As Integer attributes
    Dim As String lookupPath = directoryPath
    While Len(lookupPath) > 1 AndAlso Right(lookupPath, 1) = "/"
        lookupPath = Left(lookupPath, Len(lookupPath) - 1)
    Wend
    If lookupPath = "/" Then lookupPath = "/."
    /'
        Unix gfxlib/runtime marks non-writable directories read-only. DIR's
        attribute filter must include them, or ordinary system paths such as
        /usr/bin disappear from compiler and file-dialog discovery.
    '/
    If Dir(lookupPath, fbDirectory Or fbReadOnly Or fbHidden Or fbSystem, attributes) = "" Then Return 0
    Return IIf((attributes And fbDirectory) <> 0, -1, 0)
#endif

End Function

' end of filesystem.bas
