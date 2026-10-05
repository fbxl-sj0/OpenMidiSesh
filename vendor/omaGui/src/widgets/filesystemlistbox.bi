/'
    Project: omaGUI
    ---------------

    File: filesystemlistbox.bi

    Purpose:

        Declare portable factories for the classic directory, drive, and file
        list controls used by VBDOS forms.

    Responsibilities:

        - create ordinary omaGUI list boxes populated from host paths
        - refresh directory names, file-pattern matches, or available roots
        - report why a transactional refresh could not be completed
        - retain deterministic case-insensitive entry ordering
        - match file patterns consistently across host filesystems
        - preserve the old list when a path, pattern, or capacity check fails
        - combine explicit semicolon-separated patterns without duplicate rows

    This file intentionally does NOT contain:

        - platform SDK declarations
        - file dialog policy or navigation state
        - file creation, deletion, or modification
'/

#ifndef __FILESYSTEMLISTBOX_BI__
#define __FILESYSTEMLISTBOX_BI__

#include once "src/widgets/listbox.bi"

' Refresh-result values are positive failures so the historical boolean
' wrappers can continue returning -1 for success and zero for any failure.
Const FILESYSTEMLISTBOX_REFRESH_OK As Integer = 0
Const FILESYSTEMLISTBOX_REFRESH_INVALID_WIDGET As Integer = 1
Const FILESYSTEMLISTBOX_REFRESH_INVALID_PATH As Integer = 2
Const FILESYSTEMLISTBOX_REFRESH_INVALID_PATTERN As Integer = 3
Const FILESYSTEMLISTBOX_REFRESH_CAPACITY As Integer = 4

Declare Function directorylistbox_Create( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal w As Integer, _
    ByVal h As Integer, _
    ByVal initialPath As String _
) As Widget Ptr
Declare Function directorylistbox_Refresh( _
    ByVal w As Widget Ptr, _
    ByVal pathValue As String _
) As Integer
Declare Function directorylistbox_TryRefresh( _
    ByVal w As Widget Ptr, _
    ByVal pathValue As String _
) As Integer
Declare Function drivelistbox_Create( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal w As Integer, _
    ByVal h As Integer _
) As Widget Ptr
Declare Function drivelistbox_Refresh(ByVal w As Widget Ptr) As Integer
' File filters use case-insensitive '*' and '?' matching on every target.
' The DOS wildcard '*.*' includes names without an extension.
Declare Function filelistbox_Create( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal w As Integer, _
    ByVal h As Integer, _
    ByVal initialPath As String, _
    ByVal patternText As String = "*" _
) As Widget Ptr
Declare Function filelistbox_Refresh( _
    ByVal w As Widget Ptr, _
    ByVal pathValue As String, _
    ByVal patternText As String = "*" _
) As Integer
Declare Function filelistbox_TryRefresh( _
    ByVal w As Widget Ptr, _
    ByVal pathValue As String, _
    ByVal patternText As String = "*" _
) As Integer

' The original single-pattern API keeps its literal semicolon behavior.
' This opt-in API splits alternatives and lists each filename once, even when
' more than one alternative matches it.
' This opt-in API trims alternatives, rejects empty alternatives, and commits
' their sorted union only after every search succeeds within the list bounds.
Declare Function filelistbox_TryRefreshPatterns( _
    ByVal w As Widget Ptr, ByVal pathValue As String, _
    ByVal patternText As String _
) As Integer

#endif

/' end of filesystemlistbox.bi '/
