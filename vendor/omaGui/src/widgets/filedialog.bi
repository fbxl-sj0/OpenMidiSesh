/'
    Project: omaGUI
    ---------------

    File: filedialog.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for filedialog.

    Purpose:

        Declare the file dialog widget interface.

    Responsibilities:

        - expose file dialog construction
        - expose selected-file and dialog-result queries
        - allow callers to select an initial directory without changing CurDir
        - expose an optional save mode with a caller-supplied default name
        - provide portable case-insensitive wildcard filters
        - allow a bounded application-supplied window title

    This file intentionally does NOT contain:

        - directory enumeration implementation
        - rendering logic
        - editor-specific file handling
'/

#ifndef __FILEDIALOG_BI__
#define __FILEDIALOG_BI__

#include once "src/widgets/widgets.bi"

Const FILEDIALOG_MODE_OPEN As Integer = 0
Const FILEDIALOG_MODE_SAVE As Integer = 1
Const FILEDIALOG_MODE_FOLDER As Integer = 2
Const FILEDIALOG_MAX_FILTER_BYTES As Integer = 160
Const FILEDIALOG_MAX_FILTER_PATTERNS As Integer = 16

Declare Function filedialog_Create(ByVal nm As String, ByVal x As Integer, ByVal y As Integer) As Widget Ptr
Declare Function filedialog_CreateAtPath( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal initialPath As String _
) As Widget Ptr
Declare Function filedialog_CreateSaveAtPath( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal initialPath As String, _
    ByVal initialFilename As String _
) As Widget Ptr
Declare Function filedialog_CreateFolderAtPath( _
    ByVal nm As String, ByVal x As Integer, ByVal y As Integer, _
    ByVal initialPath As String _
) As Widget Ptr
Declare Sub filedialog_SetDialogStyle(ByVal w As Widget Ptr)
' Borrow the generated subwindow for application-specific dialog styling.
' The pointer remains valid only while the dialog root is registered.
Declare Function filedialog_GetWindow(ByVal w As Widget Ptr) As Widget Ptr
Declare Function filedialog_GetSelectedFile(ByVal w As Widget Ptr) As String
Declare Function filedialog_GetResultState(ByVal w As Widget Ptr) As Integer
Declare Function filedialog_SetFilter( _
    ByVal w As Widget Ptr, _
    ByVal filterPattern As String _
) As Integer
Declare Function filedialog_GetFilter(ByVal w As Widget Ptr) As String
Declare Function filedialog_SetTitle( _
    ByVal w As Widget Ptr, ByVal title_text As String _
) As Integer

#endif

/' end of filedialog.bi '/
