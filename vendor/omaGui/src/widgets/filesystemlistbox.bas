/'
    Project: omaGUI
    ---------------

    File: filesystemlistbox.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements filesystemlistbox.bi; declarations there define the interface.

    Purpose:

        Populate standard omaGUI list boxes with portable filesystem views.

    Responsibilities:

        - enumerate directories and files through FreeBASIC's Dir API
        - enumerate available Windows drive letters without a platform SDK
        - expose the Unix filesystem root on non-Windows targets
        - sort every populated list for deterministic presentation
        - apply bounded, case-insensitive file patterns on every host
        - reject file patterns that could escape the caller's directory
        - stage complete refreshes before replacing visible list content
        - distinguish invalid input from bounded-list capacity failures
        - combine optional pattern alternatives in one directory scan

    This file intentionally does NOT contain:

        - current-directory mutation
        - file dialog buttons or modal state
        - file creation, deletion, or modification

    Portability note:

        Enumeration uses FreeBASIC's Dir runtime; matching is performed by the
        shared omaGUI wildcard helper because Dir case rules differ by host.
        Windows roots additionally use the compiler-supplied C runtime
        existence check because Dir has no dot entry at a root. No SDK or extra
        library is required. Non-Windows builds expose the filesystem root
        because mount discovery is host-specific. Enumeration and widget
        mutation occur on the GUI thread.
'/

#lang "fb"

#include once "src/widgets/filesystemlistbox.bi"
#include once "src/widgets/wildcard.bi"
#include once "dir.bi"
#If Defined(__FB_WIN32__)
#include once "crt/io.bi"
#EndIf

Const FILESYSTEMLISTBOX_ATTRIBUTE_MASK As Integer = _
    fbNormal Or fbReadOnly Or fbHidden Or fbSystem Or fbDirectory Or fbArchive

Type FilesystemListSnapshot
    As String items(0 To LISTBOX_MAX_ITEMS - 1)
    As Integer item_count, stored_bytes
End Type

#If Defined(__FB_WIN32__)
Const FILESYSTEMLISTBOX_PATH_SEPARATOR As String = "\"
Const FILESYSTEMLISTBOX_SEARCH_WILDCARD As String = "*.*"
#Else
Const FILESYSTEMLISTBOX_PATH_SEPARATOR As String = "/"
Const FILESYSTEMLISTBOX_SEARCH_WILDCARD As String = "*"
#EndIf

' -------------------------------------------------------------------------
' Shared helpers
' -------------------------------------------------------------------------

Private Function filesystemlistbox_JoinPath( _
    ByRef basePath As Const String, _
    ByRef leafName As Const String _
) As String
    If Len(basePath) = 0 Then Return leafName
    If Right(basePath, 1) = FILESYSTEMLISTBOX_PATH_SEPARATOR Then _
        Return basePath & leafName
    Return basePath & FILESYSTEMLISTBOX_PATH_SEPARATOR & leafName
End Function


Private Function filesystemlistbox_IsSafePattern( _
    ByRef patternText As Const String _
) As Integer
    If Len(Trim(patternText)) = 0 OrElse Len(patternText) > 1024 OrElse _
       InStr(patternText, Chr(0)) Then Return 0
    If InStr(patternText, "/") <> 0 OrElse _
       InStr(patternText, "\") <> 0 OrElse _
       InStr(patternText, ":") <> 0 Then Return 0
    Return -1
End Function

Private Function filesystemlistbox_MatchesPattern( _
    ByRef entryName As Const String, _
    ByRef patternText As Const String, _
    ByVal multiplePatterns As Integer _
) As Integer
    If multiplePatterns = 0 Then _
        Return omaguiinternal_WildcardMatches(entryName, patternText)

    Dim As Integer startPosition = 1
    For position As Integer = 1 To Len(patternText) + 1
        If position <= Len(patternText) AndAlso _
           Mid(patternText, position, 1) <> ";" Then Continue For
        Dim As String patternPart = Trim(Mid( _
            patternText, startPosition, position - startPosition _
        ))
        If omaguiinternal_WildcardMatches(entryName, patternPart) Then _
            Return -1
        startPosition = position + 1
    Next position
    Return 0
End Function

Private Function filesystemlistbox_IsDirectory(ByVal pathValue As String) As Integer
    Dim As Integer entryAttributes
    Dim As String directoryEntry = Dir(filesystemlistbox_JoinPath(pathValue, "."), _
        FILESYSTEMLISTBOX_ATTRIBUTE_MASK, entryAttributes)
    If Len(directoryEntry) > 0 AndAlso (entryAttributes And fbDirectory) <> 0 Then Return -1
#If Defined(__FB_WIN32__)
    ' Windows directory enumeration has no "." entry at a drive/share root.
    ' Check only those structural roots with the C runtime shipped with
    ' FreeBASIC. No Windows SDK, external GUI library, or ChDir is involved.
    For position As Integer = 1 To Len(pathValue)
        If Mid(pathValue, position, 1) = "/" Then Mid(pathValue, position, 1) = "\"
    Next position
    Do While Len(pathValue) > 3 AndAlso Right(pathValue, 1) = "\"
        pathValue = Left(pathValue, Len(pathValue) - 1)
    Loop
    Dim As Integer isRoot
    If Len(pathValue) = 3 AndAlso Mid(pathValue, 2) = ":\" Then
        Dim As String driveLetter = UCase(Left(pathValue, 1))
        isRoot = IIf(driveLetter >= "A" AndAlso driveLetter <= "Z", -1, 0)
    ElseIf Left(pathValue, 2) = "\\" Then
        Dim As Integer shareStart = InStr(3, pathValue, "\")
        If shareStart > 3 AndAlso shareStart < Len(pathValue) AndAlso InStr(shareStart + 1, pathValue, "\") = 0 Then
            isRoot = -1
        End If
    End If
    If isRoot Then Return IIf(_access(StrPtr(pathValue), 0) = 0, -1, 0)
#EndIf
    Return 0
End Function


Private Sub filesystemlistbox_Sort(ByRef snapshot As FilesystemListSnapshot)
    Dim As Integer insertIndex
    Dim As Integer itemIndex
    Dim As String itemText

    For itemIndex = 1 To snapshot.item_count - 1
        itemText = snapshot.items(itemIndex)
        insertIndex = itemIndex - 1
        While insertIndex >= 0 AndAlso _
              LCase(snapshot.items(insertIndex)) > LCase(itemText)
            snapshot.items(insertIndex + 1) = snapshot.items(insertIndex)
            insertIndex -= 1
        Wend
        snapshot.items(insertIndex + 1) = itemText
    Next itemIndex
End Sub


Private Function filesystemlistbox_AppendMatches( _
    ByRef snapshot As FilesystemListSnapshot, _
    ByRef directoryPath As Const String, _
    ByRef patternText As Const String, _
    ByVal wantDirectories As Integer, ByVal multiplePatterns As Integer _
) As Integer
    Dim As String entryName
    Dim As String enumerationPattern = filesystemlistbox_JoinPath( _
        directoryPath, FILESYSTEMLISTBOX_SEARCH_WILDCARD _
    )
    Dim As Integer entryAttributes
    Dim As Integer isDirectory
    Dim As Integer capacity_exceeded, includeEntry

    ' Enumerate broadly, then apply one omaGUI matcher on Windows and Unix.
    entryName = Dir(enumerationPattern, _
        FILESYSTEMLISTBOX_ATTRIBUTE_MASK, entryAttributes)
    Do While Len(entryName) > 0
        isDirectory = IIf( _
            (entryAttributes And fbDirectory) <> 0, -1, 0 _
        )
        includeEntry = IIf(wantDirectories, isDirectory AndAlso _
            entryName <> "." AndAlso entryName <> "..", isDirectory = 0)
        If includeEntry AndAlso _
           filesystemlistbox_MatchesPattern( _
               entryName, patternText, multiplePatterns _
           ) = 0 Then
            includeEntry = 0
        End If
        If includeEntry Then
            If snapshot.item_count >= LISTBOX_MAX_ITEMS OrElse _
               Len(entryName) > LISTBOX_MAX_TEXT_BYTES - snapshot.stored_bytes Then
                capacity_exceeded = -1
            ElseIf capacity_exceeded = 0 Then
                snapshot.items(snapshot.item_count) = entryName
                snapshot.item_count += 1
                snapshot.stored_bytes += Len(entryName)
            End If
        End If
        ' Finish the enumeration even after a capacity failure. Dir owns one
        ' search cursor per thread and closes it when enumeration reaches EOF.
        entryName = Dir(entryAttributes)
    Loop

    Return IIf(capacity_exceeded, _
        FILESYSTEMLISTBOX_REFRESH_CAPACITY, FILESYSTEMLISTBOX_REFRESH_OK)
End Function

Private Function filesystemlistbox_RefreshMatches( _
    ByVal w As Widget Ptr, ByRef pathValue As Const String, _
    ByRef patternText As Const String, ByVal wantDirectories As Integer, _
    ByVal multiplePatterns As Integer = 0 _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then _
        Return FILESYSTEMLISTBOX_REFRESH_INVALID_WIDGET
    If Len(Trim(pathValue)) = 0 OrElse Len(pathValue) > 4096 OrElse _
       InStr(pathValue, Chr(0)) OrElse InStr(pathValue, "*") OrElse _
       InStr(pathValue, "?") Then Return FILESYSTEMLISTBOX_REFRESH_INVALID_PATH
    If filesystemlistbox_IsSafePattern(patternText) = 0 Then _
        Return FILESYSTEMLISTBOX_REFRESH_INVALID_PATTERN
    If filesystemlistbox_IsDirectory(pathValue) = 0 Then _
        Return FILESYSTEMLISTBOX_REFRESH_INVALID_PATH
    Dim As FilesystemListSnapshot snapshot
    If multiplePatterns Then
        Dim As Integer startPosition = 1
        For position As Integer = 1 To Len(patternText) + 1
            If position <= Len(patternText) AndAlso Mid(patternText, position, 1) <> ";" Then Continue For
            Dim As String patternPart = Trim(Mid(patternText, startPosition, position - startPosition))
            If filesystemlistbox_IsSafePattern(patternPart) = 0 Then Return FILESYSTEMLISTBOX_REFRESH_INVALID_PATTERN
            startPosition = position + 1
        Next position
    End If
    Dim As Integer refreshResult = filesystemlistbox_AppendMatches(snapshot, _
        pathValue, patternText, wantDirectories, multiplePatterns)
    If refreshResult <> FILESYSTEMLISTBOX_REFRESH_OK Then Return refreshResult
    filesystemlistbox_Sort snapshot
    ' Enumeration and capacity checks completed without touching the widget.
    ' Commit cannot fail: all rows already fit the same list count/text bounds.
    listbox_Clear w
    For itemIndex As Integer = 0 To snapshot.item_count - 1
        listbox_AddItem w, snapshot.items(itemIndex)
    Next itemIndex
    Return FILESYSTEMLISTBOX_REFRESH_OK
End Function

' -------------------------------------------------------------------------
' Directory list
' -------------------------------------------------------------------------

Function directorylistbox_Refresh( _
    ByVal w As Widget Ptr, _
    ByVal pathValue As String _
) As Integer
    Return IIf(directorylistbox_TryRefresh(w, pathValue) = _
        FILESYSTEMLISTBOX_REFRESH_OK, -1, 0)
End Function


Function directorylistbox_TryRefresh( _
    ByVal w As Widget Ptr, _
    ByVal pathValue As String _
) As Integer
    Return filesystemlistbox_RefreshMatches( _
        w, pathValue, FILESYSTEMLISTBOX_SEARCH_WILDCARD, -1)
End Function


Function directorylistbox_Create( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal w As Integer, _
    ByVal h As Integer, _
    ByVal initialPath As String _
) As Widget Ptr
    Dim As Widget Ptr resultWidget

    resultWidget = listbox_Create(nm, x, y, w, h)
    If resultWidget <> 0 Then _
        directorylistbox_Refresh resultWidget, initialPath
    Return resultWidget
End Function

' -------------------------------------------------------------------------
' File list
' -------------------------------------------------------------------------

Function filelistbox_Refresh( _
    ByVal w As Widget Ptr, _
    ByVal pathValue As String, _
    ByVal patternText As String _
) As Integer
    Return IIf(filelistbox_TryRefresh(w, pathValue, patternText) = _
        FILESYSTEMLISTBOX_REFRESH_OK, -1, 0)
End Function


Function filelistbox_TryRefresh( _
    ByVal w As Widget Ptr, _
    ByVal pathValue As String, _
    ByVal patternText As String _
) As Integer
    Return filesystemlistbox_RefreshMatches(w, pathValue, patternText, 0)
End Function

Function filelistbox_TryRefreshPatterns( _
    ByVal w As Widget Ptr, ByVal pathValue As String, _
    ByVal patternText As String _
) As Integer
    Return filesystemlistbox_RefreshMatches(w, pathValue, patternText, 0, -1)
End Function


Function filelistbox_Create( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal w As Integer, _
    ByVal h As Integer, _
    ByVal initialPath As String, _
    ByVal patternText As String _
) As Widget Ptr
    Dim As Widget Ptr resultWidget

    resultWidget = listbox_Create(nm, x, y, w, h)
    If resultWidget <> 0 Then _
        filelistbox_Refresh resultWidget, initialPath, patternText
    Return resultWidget
End Function

' -------------------------------------------------------------------------
' Drive or filesystem-root list
' -------------------------------------------------------------------------

Function drivelistbox_Refresh(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then Return 0
    Dim As FilesystemListSnapshot snapshot
    Dim As String selected_drive

#If Defined(__FB_WIN32__)
    Dim As String current_path = CurDir
    If Len(current_path) >= 2 AndAlso Mid(current_path, 2, 1) = ":" Then _
        selected_drive = UCase(Left(current_path, 2))
    For drive_code As Integer = Asc("A") To Asc("Z")
        Dim As String drive_name = Chr(drive_code) & ":"
        Dim As String root_path = drive_name & FILESYSTEMLISTBOX_PATH_SEPARATOR
        If drive_name = selected_drive OrElse filesystemlistbox_IsDirectory(root_path) Then
            snapshot.items(snapshot.item_count) = drive_name
            snapshot.item_count += 1
            snapshot.stored_bytes += Len(drive_name)
        End If
    Next drive_code
#Else
    selected_drive = FILESYSTEMLISTBOX_PATH_SEPARATOR
    snapshot.items(0) = selected_drive
    snapshot.item_count = 1
    snapshot.stored_bytes = Len(selected_drive)
#EndIf

    ' A failed probe leaves an existing list intact. A successful snapshot is
    ' small enough that the bounded commit cannot exceed ListBox capacity.
    If snapshot.item_count = 0 Then Return 0
    listbox_Clear w
    Dim As Integer selected_index = -1
    For item_index As Integer = 0 To snapshot.item_count - 1
        listbox_AddItem w, snapshot.items(item_index)
        If snapshot.items(item_index) = selected_drive Then _
            selected_index = item_index
    Next item_index
    If selected_index < 0 Then selected_index = 0
    listbox_SetSelectedIndex w, selected_index
    Return -1
End Function


Function drivelistbox_Create( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal w As Integer, _
    ByVal h As Integer _
) As Widget Ptr
    Dim As Widget Ptr resultWidget

    resultWidget = listbox_Create(nm, x, y, w, h)
    If resultWidget <> 0 Then drivelistbox_Refresh resultWidget
    Return resultWidget
End Function

/' end of filesystemlistbox.bas '/
