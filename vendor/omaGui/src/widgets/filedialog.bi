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
        - search the browsed folder and registered Places recursively, with bounded entry, folder and depth limits
        - allow a bounded application-supplied window title
        - allow portable foreground/background overrides for legacy dialogs
        - expose optional read-only, initial-view, save-format, and drawing-preview controls

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
Const FILEDIALOG_SORT_NAME As Integer = 0
Const FILEDIALOG_SORT_TYPE As Integer = 1
Const FILEDIALOG_SORT_SIZE As Integer = 2
Const FILEDIALOG_SORT_MODIFIED As Integer = 3

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
Declare Function filedialog_SetColors( _
    ByVal w As Widget Ptr, _
    ByVal foreground_color As ULong, _
    ByVal background_color As ULong _
) As Integer
Declare Function filedialog_GetSelectedFile(ByVal w As Widget Ptr) As String
Declare Function filedialog_GetHighlightedFile(ByVal w As Widget Ptr) As String
Declare Function filedialog_SetPreviewWidget(ByVal w As Widget Ptr, ByVal previewWidget As Widget Ptr) As Integer
Declare Function filedialog_GetResultState(ByVal w As Widget Ptr) As Integer
Declare Function filedialog_SetReadOnlyOption(ByVal w As Widget Ptr, ByVal enabled_state As Integer) As Integer
Declare Function filedialog_GetReadOnlyOption(ByVal w As Widget Ptr) As Integer
Declare Function filedialog_SetInitialViewOption(ByVal w As Widget Ptr, ByVal enabled_state As Integer) As Integer
Declare Function filedialog_GetInitialViewOption(ByVal w As Widget Ptr) As Integer
Declare Function filedialog_SetSaveOption(ByVal w As Widget Ptr, ByRef label_text As Const String, ByVal enabled_state As Integer, ByVal checked_state As Integer) As Integer
Declare Function filedialog_GetSaveOption(ByVal w As Widget Ptr) As Integer
Declare Function filedialog_SetFilter( _
    ByVal w As Widget Ptr, _
    ByVal filterPattern As String _
) As Integer
Declare Function filedialog_GetFilter(ByVal w As Widget Ptr) As String
Declare Function filedialog_SetTitle( _
    ByVal w As Widget Ptr, ByVal title_text As String _
) As Integer
' An optional application action. The picker stays open; consume each click once.
Declare Function filedialog_SetOptionsButton(ByVal w As Widget Ptr, ByVal enabled_state As Integer) As Integer
Declare Function filedialog_OptionsRequested(ByVal w As Widget Ptr) As Integer

' These operations use the dialog's cached listing and do not change CurDir.
Declare Function filedialog_SetSort(ByVal w As Widget Ptr, ByVal column_index As Integer, ByVal descending As Integer = 0) As Integer
Declare Function filedialog_AddPlace(ByVal w As Widget Ptr, ByVal caption As String, ByVal pathValue As String) As Integer
' Register an application-configured folder for OPEN's support-path search.
Declare Function filedialog_AddSupportPath(ByVal w As Widget Ptr, ByVal pathValue As String) As Integer
' An optional extension is appended only when a save name has no dot.
Declare Function filedialog_SetDefaultExtension(ByVal w As Widget Ptr, ByVal extension_text As String) As Integer
' Enabled by default. Disable only when the application confirms replacement.
' Confirmation returns a pathname; the dialog never writes or replaces a file.
Declare Sub filedialog_SetConfirmOverwrite(ByVal w As Widget Ptr, ByVal enabled_state As Integer)

#endif

/' end of filedialog.bi '/
