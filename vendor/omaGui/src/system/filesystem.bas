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

#if defined(__FB_WIN32__) and not defined(OMAGUI_PORTABLE_ONLY)
#include once "src/backend/backend_windows.bi"
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

#if defined(__FB_WIN32__) and not defined(OMAGUI_PORTABLE_ONLY)
    Dim As omaGUI_NativeWindows.FindData findData
    Dim As Any Ptr findHandle
    Dim As String entryName
    Dim As UInteger attributes

    If Right(searchPattern, 1) <> "/" AndAlso _
       Right(searchPattern, 1) <> Chr(92) Then searchPattern &= Chr(92)
    searchPattern &= "*"

    findHandle = omaGUI_NativeWindows.FindFirstFileA(StrPtr(searchPattern), @findData)
    If findHandle = CPtr(Any Ptr, -1) Then Return 0

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
    Loop While omaGUI_NativeWindows.FindNextFileA(findHandle, @findData) <> 0

    omaGUI_NativeWindows.FindClose(findHandle)
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

#if defined(__FB_WIN32__) and not defined(OMAGUI_PORTABLE_ONLY)
    ' GetFileAttributesA returns a 32-bit all-ones value when lookup fails.
    Const SYSTEM_INVALID_FILE_ATTRIBUTES As ULong = &hFFFFFFFF
    Dim As ULong attributes = omaGUI_NativeWindows.GetFileAttributesA(StrPtr(directoryPath))
    If attributes = SYSTEM_INVALID_FILE_ATTRIBUTES Then Return 0
    Return IIf((attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY) <> 0, -1, 0)
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

' -------------------------------------------------------------------------
' Attribute-only file queries
' -------------------------------------------------------------------------

Type SystemPathQuery
    As String entry_name
    As Integer found
End Type

Private Function system_FindPathEntry(ByRef entryName As Const String, _
    ByVal attributes As UInteger, ByVal context As Any Ptr) As Integer
    Dim As SystemPathQuery Ptr query = Cast(SystemPathQuery Ptr, context)
#If Defined(__FB_WIN32__) Or Defined(__FB_DOS__)
    If LCase(entryName) <> LCase(query->entry_name) Then Return 0
#Else
    If entryName <> query->entry_name Then Return 0
#EndIf
    query->found = -1
    Return 1
End Function

Function system_PathExists(ByRef pathValue As Const String) As Integer
    If pathValue = "" OrElse InStr(pathValue, Chr(0)) Then Return 0
#If Defined(__FB_WIN32__) And Not Defined(OMAGUI_PORTABLE_ONLY)
    Return omaGUI_NativeWindows.GetFileAttributesA(StrPtr(pathValue)) <> &hFFFFFFFFUL
#Else
    ' Exact-name comparison avoids treating literal wildcard bytes in Unix
    ' filenames as a DIR pattern. The callback runs inside one enumeration.
    Dim As Integer separator_position = InStrRev(pathValue, "/")
#If Defined(__FB_WIN32__) Or Defined(__FB_DOS__)
    Dim As Integer backslash_position = InStrRev(pathValue, Chr(92))
    If backslash_position > separator_position Then separator_position = backslash_position
#EndIf
    Dim As String parent_path = Left(pathValue, separator_position)
    If parent_path = "" Then parent_path = CurDir
    Dim As SystemPathQuery query
    query.entry_name = Mid(pathValue, separator_position + 1)
    If query.entry_name = "" Then Return system_IsDirectory(pathValue)
    system_EnumerateDirectory parent_path, SYSTEM_DIRECTORY_FILES Or SYSTEM_DIRECTORY_FOLDERS, @system_FindPathEntry, @query
    Return query.found
#EndIf
End Function

Sub system_GetFileDetails(ByRef pathValue As Const String, ByRef sizeValue As LongInt, ByRef modifiedValue As Double)
    sizeValue = -1 : modifiedValue = 0
    If pathValue = "" OrElse InStr(pathValue, Chr(0)) Then Exit Sub
#If Defined(__FB_WIN32__) And Not Defined(OMAGUI_PORTABLE_ONLY)
    Dim As omaGUI_NativeWindows.FindData data_value
    Dim As Any Ptr find_handle = omaGUI_NativeWindows.FindFirstFileA(StrPtr(pathValue), @data_value)
    If find_handle = CPtr(Any Ptr, -1) Then Exit Sub
    If data_value.fileSizeHigh <= &h7FFFFFFFUL Then _
        sizeValue = CLngInt((CULngInt(data_value.fileSizeHigh) Shl 32) Or data_value.fileSizeLow)
    omaGUI_NativeWindows.FindClose find_handle
#EndIf
    ' FileDateTime uses stat, unlike FileLen's stream-based legacy fallback.
    ' No permission to read file contents is needed to display a timestamp.
    modifiedValue = FileDateTime(pathValue)
End Sub

' end of filesystem.bas
