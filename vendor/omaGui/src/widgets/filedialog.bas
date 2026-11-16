/'
    Project: omaGUI
    ---------------

    File: filedialog.bas

    Purpose:

        Implement a generated-widget file dialog.

    Responsibilities:

        - browse cached directory entries in a sortable details table
        - navigate directories through dialog-owned path state
        - filter files with bounded case-insensitive wildcard-list matching
        - collect typed open/save paths and confirm replacement
        - expose optional read-only, initial-view, save-format and application-preview controls
        - report accepted and cancelled dialog states
        - claim modal update focus while the dialog is open
        - apply a bounded title and responsive portable layout
        - navigate through places, history and an editable location
        - search the browsed folder and registered places with a bounded scan
        - search configured support paths through the same portable directory API
        - create explicitly requested folders without shell commands

    Targets:

        FreeBASIC builds with built-in gfxlib; gfxlib3 is optional when supplied by the compiler.

    Module API:

        Implementation unit assembled by omaGUI.bi when OMAGUI_IMPLEMENTATION is defined.

    This file intentionally does NOT contain:

        - editor save/load policy
        - platform-native file dialog calls
        - map serialization logic
'/

#lang "fb"
#include once "src/widgets/filedialog.bi"
#include once "src/widgets/wildcard.bi"
#include once "src/widgets/subwindow.bi"
#include once "src/widgets/listbox.bi"
#include once "src/widgets/button.bi"
#include once "src/widgets/label.bi"
#include once "src/widgets/textbox.bi"
#include once "src/widgets/checkbox.bi"
#include once "src/system/filesystem.bi"

#include once "dir.bi"
#include once "vbcompat.bi"

' -------------------------------------------------------------------------
' Dialog-owned model and path handling
' -------------------------------------------------------------------------

Const FILEDIALOG_MAX_ENTRIES As Integer = LISTBOX_MAX_ITEMS - 1
Const FILEDIALOG_MAX_NAME_BYTES As Integer = 1048576
Const FILEDIALOG_MAX_PATH_BYTES As Integer = 4096
Const FILEDIALOG_HISTORY_CAPACITY As Integer = 32
' Places include Windows drive roots plus common folders and app support paths.
Const FILEDIALOG_PLACE_CAPACITY As Integer = 64
Const FILEDIALOG_SUPPORT_PATH_CAPACITY As Integer = 16
' A user-started Places scan is bounded so a root-folder query cannot monopolize the UI thread.
Const FILEDIALOG_SEARCH_SCAN_LIMIT As Integer = 50000
' Bound queued memory and directory cycles while Find File walks nested folders.
Const FILEDIALOG_SEARCH_DIRECTORY_LIMIT As Integer = 2048
Const FILEDIALOG_SEARCH_DEPTH_LIMIT As Integer = 32
Const FILEDIALOG_MAX_TITLE_BYTES As Integer = 255
Const FILEDIALOG_WINDOW_WIDTH As Integer = 720
Const FILEDIALOG_WINDOW_HEIGHT As Integer = 480
#If Defined(__FB_WIN32__) Or Defined(__FB_DOS__)
Const FILEDIALOG_PATH_SEPARATOR As String = "\"
#Else
Const FILEDIALOG_PATH_SEPARATOR As String = "/"
#EndIf

Type FileDialogEntry
    As String entry_name, entry_path, name_key, kind_text, modified_text, size_text
    As UInteger attributes
    As Double modified_value
    As LongInt size_value
    As Integer details_loaded
End Type

Type FileDialogSearchDirectory
    As String path_value
    As Integer depth
End Type

Type FileDialogData
    ' Generated controls belong to the GUI registry. This record only owns
    ' strings, the bounded directory cache and navigation history, all on the
    ' GUI thread. Never run enumeration concurrently with the RTL DIR iterator.
    As Widget Ptr win, lst, btn_ok, btn_cancel, filenameBox, btn_enter
    As String current_path, selected_file, filter_pattern
    As Integer mode, finished
    As Widget Ptr pathBox, searchBox, filterBox, places, statusLabel
    As Widget Ptr btn_back, btn_forward, btn_up, btn_go, btn_refresh, btn_new, btn_find_files, btn_search_paths, btn_options
    As Widget Ptr hiddenBox, readOnlyBox, initialViewBox, saveOptionBox, previewBox, previewWidget
    As Widget Ptr nameLabel, filterLabel, searchLabel, placesLabel
    As FileDialogEntry entries(0 To FILEDIALOG_MAX_ENTRIES - 1)
    As Integer order(0 To FILEDIALOG_MAX_ENTRIES - 1)
    As Integer entry_count, name_bytes, truncated, visible_count
    As Integer sort_column, sort_descending, show_hidden, read_only_option_enabled, choose_initial_view_enabled, save_option_enabled
    As Integer preview_enabled
    As Integer layout_width, layout_height, layout_top, selected_entry
    As ULongInt selection_serial, double_serial, places_serial
    As ULongInt search_serial, filter_serial, filename_serial
    As String search_text, search_root, pending_replace, default_extension, previous_name
    As Integer search_all_places, search_scan_count
    As FileDialogSearchDirectory search_directories(0 To FILEDIALOG_SEARCH_DIRECTORY_LIMIT - 1)
    As Integer search_directory_count, search_directory_index, search_root_depth, search_recursive
    As String support_paths(0 To FILEDIALOG_SUPPORT_PATH_CAPACITY - 1)
    As Integer support_path_count
    As Integer confirm_overwrite, creating_folder, header_latch
    As Integer options_enabled, options_requested
    As String history(0 To FILEDIALOG_HISTORY_CAPACITY - 1)
    As Integer history_count, history_index
    As String place_paths(0 To FILEDIALOG_PLACE_CAPACITY - 1)
    As Integer place_count
    ' Diagnostic observation: sorting/searching and idle updates do not scan.
    As ULongInt directory_scan_count
End Type

Declare Function filedialog_CreateModeAtPath(ByVal nm As String, ByVal x As Integer, _
    ByVal y As Integer, ByVal initialPath As String, ByVal initialFilename As String, _
    ByVal mode As Integer) As Widget Ptr
Declare Sub filedialog_Update(ByVal root As Widget Ptr)
Declare Sub filedialog_OnOK(ByVal w As Widget Ptr)
Declare Sub filedialog_OnCancel(ByVal w As Widget Ptr)
Declare Sub filedialog_Refresh(ByVal root As Widget Ptr)
Declare Sub filedialog_OnFindFiles(ByVal w As Widget Ptr)
Declare Sub filedialog_OnSearchPaths(ByVal w As Widget Ptr)
Declare Sub filedialog_RebuildView(ByVal root As Widget Ptr)
Declare Sub filedialog_Layout(ByVal root As Widget Ptr)

Private Sub filedialog_Destroy(ByVal w As Widget Ptr)
    If w->data <> 0 Then Delete Cast(FileDialogData Ptr, w->data)
    w->data = 0
End Sub

Private Function filedialog_GetRoot(ByVal w As Widget Ptr) As Widget Ptr
    ' A corrupt parent cycle must not turn an application callback into a hang.
    ' The traversal counter is consumed by FOR/NEXT, not by the loop body.

    For depth As Integer = 0 To 255
        If w = 0 Then Return 0
        If w->destroy = @filedialog_Destroy AndAlso w->data <> 0 Then Return w
        w = w->parent
    Next depth
    Return 0
End Function

Private Function filedialog_RootLength(ByRef pathValue As Const String) As Integer
#If Defined(__FB_WIN32__) Or Defined(__FB_DOS__)
    If Len(pathValue) >= 3 AndAlso Mid(pathValue, 2, 1) = ":" Then Return 3
    If Left(pathValue, 2) = "\\" Then
        Dim As Integer server_end = InStr(3, pathValue, "\")
        If server_end = 0 Then Return Len(pathValue)
        Dim As Integer share_end = InStr(server_end + 1, pathValue, "\")
        If share_end = 0 Then Return Len(pathValue)
        Return share_end - 1
    End If
#EndIf
    If Left(pathValue, 1) = FILEDIALOG_PATH_SEPARATOR Then Return 1
    Return 0
End Function

Private Function filedialog_GetParentPath(ByVal pathValue As String) As String
    Dim As Integer root_length = filedialog_RootLength(pathValue)
    While Len(pathValue) > root_length AndAlso Right(pathValue, 1) = FILEDIALOG_PATH_SEPARATOR
        pathValue = Left(pathValue, Len(pathValue) - 1)
    Wend
    Dim As Integer separator_position = InStrRev(pathValue, FILEDIALOG_PATH_SEPARATOR)
    If separator_position <= root_length Then Return Left(pathValue, root_length)
    Return Left(pathValue, separator_position - 1)
End Function

Private Function filedialog_JoinPath(ByVal basePath As String, ByVal childName As String) As String
    If basePath = "" Then Return childName
    If Right(basePath, 1) = FILEDIALOG_PATH_SEPARATOR Then Return basePath & childName
    Return basePath & FILEDIALOG_PATH_SEPARATOR & childName
End Function

Private Function filedialog_ResolvePath(ByVal pathValue As String, ByVal basePath As String) As String
    ' Path bytes are significant on Unix, including leading/trailing spaces.
    ' Only filters are trimmed; selecting a row must return its actual name.
    If pathValue = "" OrElse Len(pathValue) > FILEDIALOG_MAX_PATH_BYTES Then Return ""
    For character_index As Integer = 1 To Len(pathValue)
        If Asc(pathValue, character_index) < 32 Then Return ""
    Next character_index
#If Defined(__FB_WIN32__) Or Defined(__FB_DOS__)
    For character_index As Integer = 1 To Len(pathValue)
        If Mid(pathValue, character_index, 1) = "/" Then Mid(pathValue, character_index, 1) = "\"
    Next character_index
    ' Drive-relative paths depend on a hidden per-drive current directory.
    ' Require a full drive root instead of changing the process directory.
    If Len(pathValue) >= 2 AndAlso Mid(pathValue, 2, 1) = ":" Then
        If Len(pathValue) < 3 OrElse Mid(pathValue, 3, 1) <> "\" Then Return ""
    ElseIf Left(pathValue, 1) = "\" AndAlso Left(pathValue, 2) <> "\\" Then
        pathValue = Left(basePath, filedialog_RootLength(basePath)) & Mid(pathValue, 2)
    End If
#EndIf
    If filedialog_RootLength(pathValue) = 0 Then pathValue = filedialog_JoinPath(basePath, pathValue)
    If Len(pathValue) > FILEDIALOG_MAX_PATH_BYTES Then Return ""
    Dim As Integer root_length = filedialog_RootLength(pathValue)
    Dim As String result_path = Left(pathValue, root_length)
    Dim As Integer part_start = root_length + 1
    While part_start <= Len(pathValue)
        Dim As Integer part_end = InStr(part_start, pathValue, FILEDIALOG_PATH_SEPARATOR)
        If part_end = 0 Then part_end = Len(pathValue) + 1
        Dim As String part = Mid(pathValue, part_start, part_end - part_start)
        If part = ".." Then
            result_path = filedialog_GetParentPath(result_path)
        ElseIf part <> "" AndAlso part <> "." Then
            result_path = filedialog_JoinPath(result_path, part)
        End If
        part_start = part_end + 1
    Wend
    Return result_path
End Function

Private Function filedialog_IsSafeFilename(ByVal filename As String) As Integer
    If filename = "" OrElse filename = "." OrElse filename = ".." Then Return 0
    If Len(filename) > FILEDIALOG_MAX_PATH_BYTES Then Return 0
    For character_index As Integer = 1 To Len(filename)
        If Asc(filename, character_index) < 32 Then Return 0
    Next character_index
    If InStr(filename, FILEDIALOG_PATH_SEPARATOR) Then Return 0
#If Defined(__FB_WIN32__) Or Defined(__FB_DOS__)
    If InStr(filename, "/") OrElse InStr(filename, ":") OrElse InStr(filename, "*") OrElse _
       InStr(filename, "?") OrElse InStr(filename, Chr(34)) OrElse InStr(filename, "<") OrElse _
       InStr(filename, ">") OrElse InStr(filename, "|") Then Return 0
    If Right(filename, 1) = "." OrElse Right(filename, 1) = " " Then Return 0
    Dim As String stem = UCase(filename)
    Dim As Integer dot_position = InStr(stem, ".")
    If dot_position Then stem = Left(stem, dot_position - 1)
    stem = RTrim(stem)
    If stem = "CON" OrElse stem = "PRN" OrElse stem = "AUX" OrElse stem = "NUL" Then Return 0
    If Len(stem) = 4 AndAlso (Left(stem, 3) = "COM" OrElse Left(stem, 3) = "LPT") Then
        If Right(stem, 1) >= "1" AndAlso Right(stem, 1) <= "9" Then Return 0
    End If
#EndIf
    Return -1
End Function

Private Function filedialog_DisplayName(ByVal value As String) As String
    ' Tabs delimit table columns, not filenames. Keep raw bytes in the model.
    For character_index As Integer = 1 To Len(value)
        If Asc(value, character_index) < 32 Then Mid(value, character_index, 1) = "?"
    Next character_index
    Return value
End Function

Private Function filedialog_IsSafeFilter( _
    ByRef filterPattern As Const String _
) As Integer
    Dim As Integer character_index
    Dim As Integer character_value
    Dim As Integer pattern_start = 1
    Dim As Integer pattern_count = 1

    If Len(filterPattern) < 1 OrElse _
       Len(filterPattern) > FILEDIALOG_MAX_FILTER_BYTES Then Return 0
    For character_index = 1 To Len(filterPattern)
        character_value = Asc(Mid(filterPattern, character_index, 1))
        If character_value < 32 OrElse _
           Mid(filterPattern, character_index, 1) = "/" OrElse _
           Mid(filterPattern, character_index, 1) = "\" OrElse _
           Mid(filterPattern, character_index, 1) = ":" Then Return 0
        If Mid(filterPattern, character_index, 1) = ";" Then
            ' A list must contain complete patterns. Empty entries would make
            ' filter behavior depend on a platform's empty-glob handling.
            If character_index = pattern_start Then Return 0
            pattern_count += 1
            If pattern_count > FILEDIALOG_MAX_FILTER_PATTERNS Then Return 0
            pattern_start = character_index + 1
        End If
    Next character_index
    If pattern_start > Len(filterPattern) Then Return 0
    Return -1
End Function


Private Function filedialog_FilterMatches( _
    ByRef filename As Const String, _
    ByRef filterPattern As Const String _
) As Integer
    Dim As Integer pattern_start = 1
    Dim As Integer pattern_end
    Dim As Integer pattern_count

    /'
        A semicolon list is intentionally interpreted here, after directory
        enumeration. The shared matcher keeps this OR rule case-insensitive
        and consistent with the file-list widget on every backend.
    '/
    While pattern_start <= Len(filterPattern)
        pattern_end = InStr(pattern_start, filterPattern, ";")
        If pattern_end = 0 Then pattern_end = Len(filterPattern) + 1
        pattern_count += 1
        If pattern_count > FILEDIALOG_MAX_FILTER_PATTERNS OrElse _
           pattern_end = pattern_start Then Return 0
        If omaguiinternal_WildcardMatches( _
            filename, Mid(filterPattern, pattern_start, _
            pattern_end - pattern_start) _
        ) Then Return -1
        pattern_start = pattern_end + 1
    Wend
    Return 0
End Function


' -------------------------------------------------------------------------
' Cached directory listing and table presentation
' -------------------------------------------------------------------------

Private Sub filedialog_Status(ByVal d As FileDialogData Ptr, ByVal message_text As String)
    label_SetText d->statusLabel, message_text
End Sub

Private Sub filedialog_ClearReplace(ByVal d As FileDialogData Ptr)
    d->pending_replace = ""
    If d->mode = FILEDIALOG_MODE_SAVE Then button_SetText d->btn_ok, "Save"
End Sub

Private Function filedialog_QueueSearchDirectory(ByVal d As FileDialogData Ptr, _
    ByVal path_value As String, ByVal depth_value As Integer) As Integer
    If d = 0 OrElse path_value = "" OrElse Len(path_value) > FILEDIALOG_MAX_PATH_BYTES Then Return -1
    For directory_index As Integer = 0 To d->search_directory_count - 1
        If d->search_directories(directory_index).path_value = path_value Then Return -1
    Next directory_index
    If d->search_directory_count >= FILEDIALOG_SEARCH_DIRECTORY_LIMIT Then
        d->truncated = -1
        Return 0
    End If
    With d->search_directories(d->search_directory_count)
        .path_value = path_value
        .depth = depth_value
    End With
    d->search_directory_count += 1
    Return -1
End Function

Private Function filedialog_AddEntry(ByRef entryName As Const String, _
    ByVal attributes As UInteger, ByVal context As Any Ptr) As Integer
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, context)
    Dim As String entry_path = ""
    If d->search_all_places Then
        d->search_scan_count += 1
        If d->search_scan_count > FILEDIALOG_SEARCH_SCAN_LIMIT Then
            d->truncated = -1
            Return 1
        End If
        If (attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY) <> 0 Then
            If d->search_recursive = 0 Then Return 0
            If entryName = "." OrElse entryName = ".." Then Return 0
            If (attributes And SYSTEM_FILE_ATTRIBUTE_REPARSE_POINT) <> 0 Then Return 0
            If d->show_hidden = 0 AndAlso (Left(entryName, 1) = "." OrElse (attributes And fbHidden) <> 0) Then Return 0
            If d->search_root_depth >= FILEDIALOG_SEARCH_DEPTH_LIMIT Then
                d->truncated = -1
                Return 1
            End If
#If Not Defined(__FB_WIN32__) And Not Defined(__FB_DOS__)
            ' Recursing from the Unix root would walk pseudo-filesystems such
            ' as /proc and /sys. Their mounted folders remain searchable Places.
            If d->search_root = "/" Then Return 0
#EndIf
            Dim As String child_path = filedialog_JoinPath(d->search_root, entryName)
            If Len(child_path) > FILEDIALOG_MAX_PATH_BYTES Then Return 0
            If filedialog_QueueSearchDirectory(d, child_path, d->search_root_depth + 1) = 0 Then Return 1
            Return 0
        End If
        If d->search_text = "" OrElse InStr(LCase(entryName), d->search_text) = 0 Then Return 0
        entry_path = filedialog_JoinPath(d->search_root, entryName)
        If Len(entry_path) > FILEDIALOG_MAX_PATH_BYTES Then Return 0
    End If
    Dim As LongInt required_bytes = Len(entryName) + Len(entry_path)
    If d->entry_count >= FILEDIALOG_MAX_ENTRIES OrElse _
       required_bytes > FILEDIALOG_MAX_NAME_BYTES - d->name_bytes Then
        d->truncated = -1
        Return 1
    End If
    Dim As Integer entry_index = d->entry_count
    d->entries(entry_index).entry_name = entryName
    d->entries(entry_index).entry_path = entry_path
    d->entries(entry_index).name_key = LCase(entryName)
    d->entries(entry_index).attributes = attributes
    d->entries(entry_index).size_value = -1
    d->entries(entry_index).size_text = "-"
    If attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY Then
        d->entries(entry_index).kind_text = "Folder"
    Else
        Dim As Integer dot_position = InStrRev(entryName, ".")
        d->entries(entry_index).kind_text = "File"
        If dot_position > 1 AndAlso dot_position < Len(entryName) Then _
            d->entries(entry_index).kind_text = UCase(Mid(entryName, dot_position + 1)) & " file"
    End If
    d->name_bytes += required_bytes
    d->entry_count += 1
    Return 0
End Function

Private Function filedialog_EntryPath(ByVal d As FileDialogData Ptr, ByVal entry_index As Integer) As String
    If entry_index < 0 OrElse entry_index >= d->entry_count Then Return ""
    If d->entries(entry_index).entry_path <> "" Then Return d->entries(entry_index).entry_path
    Return filedialog_JoinPath(d->current_path, d->entries(entry_index).entry_name)
End Function

Private Sub filedialog_LoadDetails(ByVal d As FileDialogData Ptr, ByVal entry_index As Integer)
    If entry_index < 0 OrElse entry_index >= d->entry_count Then Exit Sub
    If d->entries(entry_index).details_loaded Then Exit Sub
    Dim As String path_value = filedialog_EntryPath(d,entry_index)
    ' Query attributes/timestamps, never open file contents. FileLen and
    ' FileExists in older runtimes open a stream and can block on Unix FIFOs.
    ' Size is optional: legacy portable runtimes expose no safe size query.
    system_GetFileDetails path_value, d->entries(entry_index).size_value, _
        d->entries(entry_index).modified_value
    If (d->entries(entry_index).attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY) = 0 AndAlso _
       d->entries(entry_index).size_value >= 0 Then
        Dim As Double display_size = d->entries(entry_index).size_value
        Dim As String size_units(0 To 4) = {"B", "KiB", "MiB", "GiB", "TiB"}
        Dim As Integer unit_index = 0
        While display_size >= 1024 AndAlso unit_index < 4
            display_size /= 1024
            unit_index += 1
        Wend
        d->entries(entry_index).size_text = IIf(unit_index = 0, LTrim(Str(d->entries(entry_index).size_value)), _
            Format(display_size, "0.0")) & " " & size_units(unit_index)
    End If
    If d->entries(entry_index).modified_value > 0 Then
        d->entries(entry_index).modified_text = Format(d->entries(entry_index).modified_value, "yyyy-mm-dd hh:mm")
    Else
        d->entries(entry_index).modified_text = "-"
    End If
    d->entries(entry_index).details_loaded = -1
End Sub

Private Function filedialog_RowText(ByVal d As FileDialogData Ptr, ByVal entry_index As Integer) As String
    Dim As String name_text = filedialog_DisplayName(d->entries(entry_index).entry_name)
    If d->entries(entry_index).entry_path <> "" Then _
        name_text &= " (" & filedialog_DisplayName(filedialog_GetParentPath(d->entries(entry_index).entry_path)) & ")"
    If d->entries(entry_index).attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY Then _
        name_text = "[" & name_text & "]"
    If d->layout_width < 540 Then Return name_text
    Dim As String row_text = name_text & Chr(9) & d->entries(entry_index).kind_text & Chr(9)
    If d->layout_width >= 700 Then row_text &= d->entries(entry_index).size_text & Chr(9)
    Return row_text & d->entries(entry_index).modified_text
End Function

Private Function filedialog_ComesAfter(ByVal d As FileDialogData Ptr, _
    ByVal left_index As Integer, ByVal right_index As Integer) As Integer
    Dim As Integer left_folder = (d->entries(left_index).attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY) <> 0
    Dim As Integer right_folder = (d->entries(right_index).attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY) <> 0
    If left_folder <> right_folder Then Return left_folder = 0
    Dim As Integer comparison
    Select Case d->sort_column
    Case FILEDIALOG_SORT_TYPE
        If d->entries(left_index).kind_text > d->entries(right_index).kind_text Then comparison = 1
        If d->entries(left_index).kind_text < d->entries(right_index).kind_text Then comparison = -1
    Case FILEDIALOG_SORT_SIZE
        If d->entries(left_index).size_value > d->entries(right_index).size_value Then comparison = 1
        If d->entries(left_index).size_value < d->entries(right_index).size_value Then comparison = -1
    Case FILEDIALOG_SORT_MODIFIED
        If d->entries(left_index).modified_value > d->entries(right_index).modified_value Then comparison = 1
        If d->entries(left_index).modified_value < d->entries(right_index).modified_value Then comparison = -1
    End Select
    If comparison = 0 Then
        If d->entries(left_index).name_key > d->entries(right_index).name_key Then comparison = 1
        If d->entries(left_index).name_key < d->entries(right_index).name_key Then comparison = -1
        If comparison = 0 Then
            If d->entries(left_index).entry_name > d->entries(right_index).entry_name Then comparison = 1
            If d->entries(left_index).entry_name < d->entries(right_index).entry_name Then comparison = -1
        End If
    End If
    If d->sort_descending Then comparison = -comparison
    Return comparison > 0
End Function

Private Function filedialog_SelectedEntry(ByVal d As FileDialogData Ptr) As Integer
    Dim As LongInt entry_id
    If listbox_GetItemData(d->lst, listbox_GetSelectedIndex(d->lst), entry_id) = 0 Then Return -2
    If entry_id < 0 OrElse entry_id > d->entry_count Then Return -2
    Return CInt(entry_id) - 1 ' -1 is parent; -2 means no row selected.
End Function

Private Sub filedialog_RebuildView(ByVal root As Widget Ptr)
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    Dim As Integer old_entry = filedialog_SelectedEntry(d)
    d->visible_count = 0
    For entry_index As Integer = 0 To d->entry_count - 1
        If d->show_hidden = 0 AndAlso ((d->entries(entry_index).attributes And fbHidden) <> 0 OrElse _
            Left(d->entries(entry_index).entry_name, 1) = ".") Then Continue For
        If InStr(d->entries(entry_index).name_key, d->search_text) = 0 AndAlso d->search_text <> "" Then Continue For
        If (d->entries(entry_index).attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY) = 0 AndAlso _
           filedialog_FilterMatches(d->entries(entry_index).entry_name, d->filter_pattern) = 0 Then Continue For
        If d->sort_column = FILEDIALOG_SORT_SIZE OrElse d->sort_column = FILEDIALOG_SORT_MODIFIED Then _
            filedialog_LoadDetails d, entry_index
        d->order(d->visible_count) = entry_index
        d->visible_count += 1
    Next entry_index
    ' Shell sort bounds work and avoids recursion/stack growth on DOS. Only
    ' indexes move; cached names and metadata remain owned by their entries.
    Dim As Integer gap = d->visible_count \ 2
    While gap > 0
        For index_value As Integer = gap To d->visible_count - 1
            Dim As Integer moving_entry = d->order(index_value)
            Dim As Integer insertion_index = index_value
            While insertion_index >= gap
                If filedialog_ComesAfter(d, d->order(insertion_index - gap), moving_entry) = 0 Then Exit While
                d->order(insertion_index) = d->order(insertion_index - gap)
                insertion_index -= gap
            Wend
            d->order(insertion_index) = moving_entry
        Next index_value
        gap \= 2
    Wend
    listbox_Clear d->lst
    Dim As Integer first_result_row = 0
    If d->search_all_places = 0 Then
        listbox_AddItem d->lst, ".."
        listbox_SetItemData d->lst, 0, 0
        first_result_row = 1
    End If
    For row_index As Integer = 0 To d->visible_count - 1
        Dim As Integer entry_index = d->order(row_index)
        listbox_AddItem d->lst, filedialog_RowText(d, entry_index)
        listbox_SetItemData d->lst, row_index + first_result_row, entry_index + 1
        If entry_index = old_entry Then listbox_SetSelectedIndex d->lst, row_index + first_result_row
    Next row_index
    d->selection_serial = listbox_GetSelectionChangeCount(d->lst)
    d->selected_entry = filedialog_SelectedEntry(d)
    d->double_serial = listbox_GetDoubleActivationCount(d->lst)
    Dim As String status_text = LTrim(Str(d->visible_count)) & " items shown"
    If d->visible_count <> d->entry_count Then status_text &= " of " & LTrim(Str(d->entry_count))
    If d->truncated Then status_text &= " (listing limit reached; use a narrower folder)"
    If d->visible_count = 0 Then status_text &= " - no matching items"
    filedialog_Status d, status_text
End Sub

Private Sub filedialog_Refresh(ByVal root As Widget Ptr)
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    d->search_all_places = 0: d->search_root = "": d->search_scan_count = 0
    listbox_Clear d->lst
    For entry_index As Integer = 0 To d->entry_count - 1
        d->entries(entry_index) = Type<FileDialogEntry>()
    Next entry_index
    d->entry_count = 0 : d->name_bytes = 0 : d->truncated = 0
    d->directory_scan_count += 1
    Dim As Integer entry_kinds = SYSTEM_DIRECTORY_FOLDERS
    If d->mode <> FILEDIALOG_MODE_FOLDER Then entry_kinds Or= SYSTEM_DIRECTORY_FILES
    Dim As Integer scan_result = system_EnumerateDirectory(d->current_path, entry_kinds, @filedialog_AddEntry, d)
    textbox_SetText d->pathBox, d->current_path, -1
    If d->mode = FILEDIALOG_MODE_FOLDER Then textbox_SetText d->filenameBox, d->current_path, -1
    filedialog_ClearReplace d
    filedialog_RebuildView root
    If scan_result < 0 Then filedialog_Status d, "Could not read this directory."
End Sub

Private Function filedialog_Navigate(ByVal root As Widget Ptr, ByVal path_value As String, _
    ByVal remember As Integer = -1) As Integer
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    path_value = filedialog_ResolvePath(path_value, d->current_path)
    If path_value = "" OrElse system_IsDirectory(path_value) = 0 Then
        filedialog_Status d, "Directory not found or unavailable. Check the location."
        Return 0
    End If
    If remember AndAlso path_value <> d->current_path Then
        d->history_count = d->history_index + 1
        If d->history_count = FILEDIALOG_HISTORY_CAPACITY Then
            For history_index As Integer = 1 To FILEDIALOG_HISTORY_CAPACITY - 1
                d->history(history_index - 1) = d->history(history_index)
            Next history_index
            d->history_count -= 1
        End If
        d->history(d->history_count) = path_value
        d->history_index = d->history_count
        d->history_count += 1
    End If
    d->search_all_places = 0: d->search_root = "": d->search_scan_count = 0
    d->current_path = path_value
    d->search_text = ""
    textbox_SetText d->searchBox, "", -1
    d->search_serial = Cast(TextBoxData Ptr, d->searchBox->data)->change_serial
    filedialog_Refresh root
    d->btn_back->enabled = d->history_index > 0
    d->btn_forward->enabled = d->history_index < d->history_count - 1
    gui_SetFocus d->lst
    Return -1
End Function

' -------------------------------------------------------------------------
' Commands: navigation, typed paths, save confirmation and folder creation
' -------------------------------------------------------------------------

Private Sub filedialog_OnGo(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    filedialog_Navigate root, textbox_GetText(d->pathBox)
End Sub

Private Sub filedialog_OnHistory(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    Dim As Integer next_index = d->history_index + IIf(w = d->btn_back, -1, 1)
    If next_index < 0 OrElse next_index >= d->history_count Then Exit Sub
    If system_IsDirectory(d->history(next_index)) = 0 Then
        filedialog_Status d, "That history location is no longer available."
        Exit Sub
    End If
    d->history_index = next_index
    filedialog_Navigate root, d->history(next_index), 0
End Sub

Private Sub filedialog_OnUp(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    filedialog_Navigate root, filedialog_GetParentPath(d->current_path)
End Sub

Private Sub filedialog_OnRefresh(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    If d->search_all_places Then
        filedialog_OnFindFiles w
    Else
        filedialog_Refresh root
    End If
End Sub

Private Sub filedialog_OnFindFiles(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    If d->mode <> FILEDIALOG_MODE_OPEN Then Exit Sub
    Dim As String query_text = Trim(textbox_GetText(d->searchBox))
    If query_text = "" Then
        filedialog_Status d, "Enter filename text in Search before using Find File."
        gui_SetFocus d->searchBox
        Exit Sub
    End If

    d->search_text = LCase(query_text)
    d->search_serial = Cast(TextBoxData Ptr, d->searchBox->data)->change_serial
    d->search_all_places = -1: d->search_recursive = -1
    d->search_scan_count = 0: d->search_root = "": d->search_root_depth = 0
    For directory_index As Integer = 0 To d->search_directory_count - 1
        d->search_directories(directory_index) = Type<FileDialogSearchDirectory>
    Next directory_index
    d->search_directory_count = 0: d->search_directory_index = 0
    For entry_index As Integer = 0 To d->entry_count - 1
        d->entries(entry_index) = Type<FileDialogEntry>()
    Next entry_index
    d->entry_count = 0: d->name_bytes = 0: d->truncated = 0
    textbox_SetText d->filenameBox, "", -1
    d->filename_serial = Cast(TextBoxData Ptr, d->filenameBox->data)->change_serial

    ' Find File scans the current folder and registered Places recursively.
    ' Both the entry and directory queues are bounded before walking child paths.
    Dim As Integer places_searched = 0
    filedialog_QueueSearchDirectory d, d->current_path, 0
    ' Search configured paths early so a large Working folder cannot hide a
    ' known library file when the total-entry limit is reached.
    For path_index As Integer = 0 To d->support_path_count - 1
        Dim As String support_path = d->support_paths(path_index)
        If support_path = "" OrElse system_IsDirectory(support_path) = 0 Then Continue For
        If filedialog_QueueSearchDirectory(d, support_path, 0) = 0 Then Exit For
    Next path_index
    For place_index As Integer = 0 To d->place_count - 1
        If d->truncated Then Exit For
        Dim As String place_path = d->place_paths(place_index)
        If place_path = "" OrElse system_IsDirectory(place_path) = 0 Then Continue For
        If filedialog_QueueSearchDirectory(d, place_path, 0) = 0 Then Exit For
    Next place_index
    While d->search_directory_index < d->search_directory_count AndAlso d->truncated = 0
        Dim As Integer directory_index = d->search_directory_index
        d->search_root = d->search_directories(directory_index).path_value
        d->search_root_depth = d->search_directories(directory_index).depth
        d->search_directory_index += 1
        places_searched += 1
        d->directory_scan_count += 1
        system_EnumerateDirectory(d->search_root, _
            SYSTEM_DIRECTORY_FILES Or SYSTEM_DIRECTORY_FOLDERS, @filedialog_AddEntry, d)
    Wend
    d->search_root = ""
    listbox_SetSelectedIndex d->lst, -1
    d->selected_entry = -2
    filedialog_RebuildView root
    If d->entry_count = 0 Then
        filedialog_Status d, "Find File found no matching files in " & LTrim(Str(places_searched)) & " locations."
    Else
        filedialog_Status d, "Find File found " & LTrim(Str(d->visible_count)) & " result(s) in " & LTrim(Str(places_searched)) & " locations."
    End If
    If d->truncated Then filedialog_Status d, "Find File stopped at the search limit. Narrow the search and try again."
    gui_SetFocus d->lst
End Sub

Private Sub filedialog_OnOptions(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    If (d->mode <> FILEDIALOG_MODE_OPEN AndAlso d->mode <> FILEDIALOG_MODE_SAVE) OrElse _
       d->options_enabled = 0 OrElse d->finished Then Exit Sub
    ' Leave the selected path and filename in place while the owner opens its options dialog.
    d->options_requested = -1
End Sub

Private Sub filedialog_OnSearchPaths(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    If d->mode <> FILEDIALOG_MODE_OPEN Then Exit Sub
    If d->support_path_count = 0 Then
        filedialog_Status d, "Set support paths in Options before searching them."
        Exit Sub
    End If
    Dim As String query_text = Trim(textbox_GetText(d->searchBox))
    If query_text = "" Then
        filedialog_Status d, "Enter filename text in Search before searching support paths."
        gui_SetFocus d->searchBox
        Exit Sub
    End If
    d->search_text = LCase(query_text)
    d->search_serial = Cast(TextBoxData Ptr, d->searchBox->data)->change_serial
    d->search_all_places = -1: d->search_scan_count = 0: d->search_root = ""
    For entry_index As Integer = 0 To d->entry_count - 1
        d->entries(entry_index) = Type<FileDialogEntry>()
    Next entry_index
    d->entry_count = 0: d->name_bytes = 0: d->truncated = 0
    textbox_SetText d->filenameBox, "", -1
    d->filename_serial = Cast(TextBoxData Ptr, d->filenameBox->data)->change_serial
    Dim As Integer paths_searched = 0
    For path_index As Integer = 0 To d->support_path_count - 1
        Dim As String path_value = d->support_paths(path_index)
        If path_value = "" OrElse system_IsDirectory(path_value) = 0 Then Continue For
        d->search_root = path_value
        paths_searched += 1
        d->directory_scan_count += 1
        system_EnumerateDirectory path_value, SYSTEM_DIRECTORY_FILES, @filedialog_AddEntry, d
        If d->truncated Then Exit For
    Next path_index
    d->search_root = ""
    listbox_SetSelectedIndex d->lst, -1
    d->selected_entry = -2
    filedialog_RebuildView root
    If d->entry_count = 0 Then
        filedialog_Status d, "Search paths found no matching files in " & LTrim(Str(paths_searched)) & " paths."
    Else
        filedialog_Status d, "Search paths found " & LTrim(Str(d->visible_count)) & " result(s) in " & LTrim(Str(paths_searched)) & " paths."
    End If
    If d->truncated Then filedialog_Status d, "Search stopped at the entry limit. Narrow the search and try again."
    gui_SetFocus d->lst
End Sub

Private Sub filedialog_OnOpenFolder(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    Dim As Integer entry_index = filedialog_SelectedEntry(d)
    If entry_index = -1 Then
        filedialog_OnUp w
    ElseIf entry_index >= 0 Then
        If d->entries(entry_index).attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY Then _
            filedialog_Navigate root, filedialog_JoinPath(d->current_path, d->entries(entry_index).entry_name)
    End If
End Sub

Private Sub filedialog_OnNewFolder(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    If d->creating_folder Then
        filedialog_OnOK w
        Exit Sub
    End If
    d->previous_name = textbox_GetText(d->filenameBox)
    d->creating_folder = -1
    textbox_SetReadOnly d->filenameBox, 0
    textbox_SetText d->filenameBox, "New folder", -1
    textbox_SelectAll d->filenameBox
    button_SetText d->btn_new, "Create"
    button_SetText d->btn_ok, "Create"
    filedialog_Status d, "Enter a new folder name. Escape returns to browsing."
    gui_SetFocus d->filenameBox
End Sub

Private Sub filedialog_EndNewFolder(ByVal d As FileDialogData Ptr)
    d->creating_folder = 0
    button_SetText d->btn_new, "New folder"
    button_SetText d->btn_ok, IIf(d->mode = FILEDIALOG_MODE_SAVE, "Save", IIf(d->mode = FILEDIALOG_MODE_FOLDER, "Select", "Open"))
    textbox_SetReadOnly d->filenameBox, d->mode = FILEDIALOG_MODE_FOLDER
    textbox_SetText d->filenameBox, d->previous_name, -1
End Sub

Private Sub filedialog_OnOK(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    If d->finished Then Exit Sub
    Dim As String filename = textbox_GetText(d->filenameBox)
    Dim As ULongInt name_serial = Cast(TextBoxData Ptr, d->filenameBox->data)->change_serial
    If name_serial <> d->filename_serial Then
        d->filename_serial = name_serial
        If d->pending_replace <> "" Then filedialog_ClearReplace d
        If d->mode <> FILEDIALOG_MODE_FOLDER AndAlso d->creating_folder = 0 Then _
            listbox_SetSelectedIndex d->lst, -1
    End If
    Dim As Integer entry_index = filedialog_SelectedEntry(d)
    If d->creating_folder Then
        If filedialog_IsSafeFilename(filename) = 0 Then
            filedialog_Status d, "Enter one valid folder name, without a path."
            Exit Sub
        End If
        Dim As String new_path = filedialog_JoinPath(d->current_path, filename)
        If Len(new_path) > FILEDIALOG_MAX_PATH_BYTES OrElse MkDir(new_path) <> 0 Then
            filedialog_Status d, "Could not create the folder. Check its name and permissions."
            Exit Sub
        End If
        filedialog_EndNewFolder d
        filedialog_Navigate root, new_path
        Exit Sub
    End If
    If d->mode = FILEDIALOG_MODE_FOLDER Then
        Dim As String selected_path = d->current_path
        If entry_index = -1 Then selected_path = filedialog_GetParentPath(d->current_path)
        If entry_index >= 0 Then
            If d->entries(entry_index).attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY Then _
                selected_path = filedialog_JoinPath(d->current_path, d->entries(entry_index).entry_name)
        End If
        If system_IsDirectory(selected_path) Then
            d->selected_file = selected_path : d->finished = 1
        Else
            filedialog_Status d, "Selected folder is no longer available."
        End If
        Exit Sub
    End If
    ' A row activation navigates folders. A typed name always has precedence
    ' over an old file selection, so Save cannot silently discard an edit.
    If entry_index = -1 Then
        filedialog_OnUp w : Exit Sub
    ElseIf entry_index >= 0 Then
        If d->entries(entry_index).attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY Then
            filedialog_OnOpenFolder w : Exit Sub
        End If
    End If
    If gui_GetFocus() = d->lst OrElse filename = "" Then
        If entry_index = -1 Then
            filedialog_OnUp w : Exit Sub
        ElseIf entry_index >= 0 Then
            If d->entries(entry_index).attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY Then
                filedialog_OnOpenFolder w : Exit Sub
            End If
            If d->search_all_places AndAlso d->entries(entry_index).entry_path <> "" Then
                filename = d->entries(entry_index).entry_path
            Else
                filename = d->entries(entry_index).entry_name
            End If
        End If
    End If
    Dim As String path_value = filedialog_ResolvePath(filename, d->current_path)
    If path_value <> "" AndAlso system_IsDirectory(path_value) Then
        filedialog_Navigate root, path_value : Exit Sub
    End If
    If path_value = "" Then
        filedialog_Status d, "Enter a filename or select a file."
        Exit Sub
    End If
    Dim As Integer separator_position = InStrRev(path_value, FILEDIALOG_PATH_SEPARATOR)
    Dim As String basename = Mid(path_value, separator_position + 1)
    Dim As String parent_path = filedialog_GetParentPath(path_value)
    If filedialog_IsSafeFilename(basename) = 0 OrElse system_IsDirectory(parent_path) = 0 Then
        filedialog_Status d, "Invalid filename or unavailable parent directory."
        Exit Sub
    End If
    If d->mode = FILEDIALOG_MODE_SAVE Then
        If d->default_extension <> "" AndAlso InStr(basename, ".") = 0 Then path_value &= d->default_extension
        If Len(path_value) > FILEDIALOG_MAX_PATH_BYTES Then
            filedialog_Status d, "The complete pathname is too long."
            Exit Sub
        End If
        ' Appending the default extension can resolve to an existing folder.
        ' A directory must never be offered as a file replacement destination.
        If system_IsDirectory(path_value) Then
            filedialog_Navigate root, path_value
            Exit Sub
        End If
        If d->confirm_overwrite AndAlso system_PathExists(path_value) Then
            If d->pending_replace <> path_value Then
                d->pending_replace = path_value
                button_SetText d->btn_ok, "Replace"
                filedialog_Status d, "File exists. Click Replace to confirm, or edit the filename."
                Exit Sub
            End If
        End If
    ElseIf system_PathExists(path_value) = 0 Then
        filedialog_Status d, "File not found. Check the filename or refresh the list."
        Exit Sub
    End If
    d->selected_file = path_value : d->finished = 1
End Sub

Private Sub filedialog_OnCancel(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    If d->creating_folder Then
        filedialog_EndNewFolder d
        filedialog_RebuildView root
    Else
        d->finished = -1
    End If
End Sub

Private Function filedialog_TextKey(ByVal w As Widget Ptr, ByVal key_code As Integer, _
    ByVal modifiers As Integer) As Integer
    If key_code <> FB.SC_ENTER OrElse modifiers <> INPUT_MODIFIER_NONE Then Return 0
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    If w = d->pathBox Then
        filedialog_OnGo w
    ElseIf w = d->filterBox Then
        If filedialog_SetFilter(root, textbox_GetText(w)) = 0 Then _
            filedialog_Status d, "Use up to 16 patterns, separated by semicolons (example: *.bas;*.bi)."
    ElseIf w = d->filenameBox Then
        filedialog_OnOK w
    ElseIf w = d->searchBox Then
        gui_SetFocus d->lst
    End If
    Return -1
End Function

Private Sub filedialog_WindowUpdate(ByVal w As Widget Ptr)
    subwindow_Update w
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    If d->finished Then Exit Sub
    If input_ExactModifiedKeyPressEvent(FB.SC_L, INPUT_MODIFIER_CONTROL) Then
        gui_SetFocus d->pathBox : textbox_SelectAll d->pathBox
    ElseIf input_ExactModifiedKeyPressEvent(FB.SC_F, INPUT_MODIFIER_CONTROL) Then
        gui_SetFocus d->searchBox : textbox_SelectAll d->searchBox
    ElseIf input_ExactModifiedKeyPressEvent(FB.SC_H, INPUT_MODIFIER_CONTROL) Then
        checkbox_SetChecked d->hiddenBox, Not checkbox_GetChecked(d->hiddenBox)
    ElseIf input_ExactModifiedKeyPressEvent(FB.SC_LEFT, INPUT_MODIFIER_ALT) Then
        filedialog_OnHistory d->btn_back
    ElseIf input_ExactModifiedKeyPressEvent(FB.SC_RIGHT, INPUT_MODIFIER_ALT) Then
        filedialog_OnHistory d->btn_forward
    ElseIf input_ExactModifiedKeyPressEvent(FB.SC_UP, INPUT_MODIFIER_ALT) Then
        filedialog_OnUp w
    ElseIf input_ExactModifiedKeyPressEvent(FB.SC_F5, INPUT_MODIFIER_NONE) Then
        filedialog_OnRefresh w
    End If
    filedialog_Layout root
End Sub

Private Sub filedialog_ListUpdate(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    Dim As Integer pressed = (input_MouseButtons() And 1) <> 0
    If pressed AndAlso d->header_latch = 0 AndAlso input_MouseY() >= w->ay AndAlso _
       input_MouseY() < w->ay + LISTBOX_HEADER_HEIGHT Then
        Dim As ListBoxData Ptr ld = Cast(ListBoxData Ptr, w->data)
        Dim As Integer column_x = w->ax
        For column_index As Integer = 0 To ld->table_column_count - 1
            If input_MouseX() >= column_x AndAlso input_MouseX() < column_x + ld->table_column_widths(column_index) Then
                Dim As Integer sort_index = column_index
                If ld->table_column_count = 3 AndAlso column_index = 2 Then sort_index = FILEDIALOG_SORT_MODIFIED
                filedialog_SetSort root, sort_index, IIf(d->sort_column = sort_index, Not d->sort_descending, 0)
                Exit For
            End If
            column_x += ld->table_column_widths(column_index)
        Next column_index
    Else
        listbox_Update w
    End If
    d->header_latch = pressed
End Sub

' -------------------------------------------------------------------------
' Responsive layout and event observations
' -------------------------------------------------------------------------

Private Sub filedialog_Layout(ByVal root As Widget Ptr)
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    Dim As Integer top_value = subwindow_GetClientTopInset(d->win) + 8
    If d->win->w < 360 Then gui_SetBounds d->win, d->win->x, d->win->y, 360, d->win->h
    If d->win->h < 300 Then gui_SetBounds d->win, d->win->x, d->win->y, d->win->w, 300
    If d->layout_width = d->win->w AndAlso d->layout_height = d->win->h AndAlso d->layout_top = top_value Then Exit Sub
    d->layout_width = d->win->w : d->layout_height = d->win->h : d->layout_top = top_value
    Dim As Integer width_value = d->win->w, height_value = d->win->h
    Dim As Integer sidebar = IIf(width_value >= 600, 134, 0)
    Dim As Integer list_x = 10 + sidebar
    Dim As Integer preview_width = 0
    Dim As Integer preview_visible = (d->previewWidget <> 0 AndAlso d->preview_enabled <> 0 AndAlso _
        d->mode = FILEDIALOG_MODE_OPEN AndAlso width_value >= 660)
    If preview_visible Then preview_width = 244
    Dim As Integer list_width = width_value - list_x - 10 - preview_width - IIf(preview_visible, 10, 0)
    Dim As Integer list_y = top_value + 70
    Dim As Integer list_height = height_value - list_y - 126
    gui_SetBounds d->btn_back, 10, top_value, 48, 26
    gui_SetBounds d->btn_forward, 62, top_value, 48, 26
    gui_SetBounds d->btn_up, 114, top_value, 48, 26
    gui_SetBounds d->btn_refresh, 166, top_value, 68, 26
    d->btn_find_files->visible = (d->mode = FILEDIALOG_MODE_OPEN AndAlso width_value >= 480)
    gui_SetBounds d->btn_find_files, 244, top_value, 100, 26
    d->btn_search_paths->visible = (d->mode = FILEDIALOG_MODE_OPEN AndAlso width_value >= 480 AndAlso d->support_path_count > 0)
    gui_SetBounds d->btn_search_paths, 350, top_value, 112, 26
    d->previewBox->visible = (d->previewWidget <> 0 AndAlso d->mode = FILEDIALOG_MODE_OPEN AndAlso width_value >= 660)
    If d->previewBox->visible Then gui_SetBounds d->previewBox, 468, top_value + 3, 128, 20
    d->btn_options->visible = ((d->mode = FILEDIALOG_MODE_OPEN OrElse d->mode = FILEDIALOG_MODE_SAVE) AndAlso d->options_enabled <> 0)
    gui_SetBounds d->btn_options, width_value - 278, height_value - 36, 82, 26
    gui_SetBounds d->btn_new, width_value - 112, top_value, 102, 26
    gui_SetBounds d->pathBox, 10, top_value + 34, width_value - 74, 26
    gui_SetBounds d->btn_go, width_value - 58, top_value + 34, 48, 26
    d->places->visible = sidebar <> 0 : d->placesLabel->visible = sidebar <> 0
    gui_SetBounds d->placesLabel, 10, list_y, 122, 20
    gui_SetBounds d->places, 10, list_y + 24, 122, list_height - 24
    gui_SetBounds d->lst, list_x, list_y, list_width, list_height
    If d->previewWidget <> 0 Then
        d->previewWidget->visible = preview_visible
        If preview_visible Then gui_SetBounds d->previewWidget, list_x + list_width + 10, list_y, preview_width, list_height
    End If
    Dim As Integer name_width = list_width - 16
    Dim As Integer type_width = 0, size_width = 0, date_width = 0
    If width_value >= 540 Then type_width = 92 : date_width = 126
    If width_value >= 700 Then size_width = 84
    name_width -= type_width + size_width + date_width
    Dim As String sort_arrow = IIf(d->sort_descending, " v", " ^")
    ' Table count is dialog-owned layout state. Reset it before rebuilding
    ' the supported contiguous columns; zero-width columns are not valid.
    Cast(ListBoxData Ptr, d->lst->data)->table_column_count = 0
    listbox_SetColumn d->lst, 0, "Name" & IIf(d->sort_column = 0, sort_arrow, ""), name_width
    If type_width Then
        listbox_SetColumn d->lst, 1, "Type" & IIf(d->sort_column = 1, sort_arrow, ""), type_width
        Dim As Integer date_column = 2
        If size_width Then
            listbox_SetColumn d->lst, 2, "Size" & IIf(d->sort_column = 2, sort_arrow, ""), size_width
            date_column = 3
        End If
        listbox_SetColumn d->lst, date_column, "Modified" & IIf(d->sort_column = 3, sort_arrow, ""), date_width
    End If
    Dim As Integer first_file_row = IIf(d->search_all_places, 0, 1)
    For row_index As Integer = first_file_row To listbox_GetItemCount(d->lst) - 1
        Dim As LongInt entry_id
        If listbox_GetItemData(d->lst, row_index, entry_id) Then
            If entry_id >= 1 AndAlso entry_id <= d->entry_count Then
                Dim As String row_text = filedialog_RowText(d, CInt(entry_id) - 1)
                listbox_SetItem d->lst, row_index, row_text
            End If
        End If
    Next row_index
    Dim As Integer bottom_y = height_value - 118
    gui_SetBounds d->searchLabel, 10, bottom_y + 5, 54, 20
    gui_SetBounds d->searchBox, 66, bottom_y, width_value - 232, 24
    gui_SetBounds d->hiddenBox, width_value - 156, bottom_y + 3, 146, 20
    gui_SetBounds d->filterLabel, 10, bottom_y + 34, 54, 20
    gui_SetBounds d->filterBox, 66, bottom_y + 29, 132, 24
    gui_SetBounds d->nameLabel, 208, bottom_y + 34, 48, 20
    gui_SetBounds d->filenameBox, 258, bottom_y + 29, width_value - 268, 24
    d->readOnlyBox->visible = (d->mode = FILEDIALOG_MODE_OPEN AndAlso d->read_only_option_enabled)
    d->initialViewBox->visible = (d->mode = FILEDIALOG_MODE_OPEN AndAlso d->choose_initial_view_enabled)
    d->saveOptionBox->visible = (d->mode = FILEDIALOG_MODE_SAVE AndAlso d->save_option_enabled)
    Dim As Integer status_x = 10
    If d->mode = FILEDIALOG_MODE_SAVE AndAlso d->save_option_enabled Then
        gui_SetBounds d->saveOptionBox, 10, bottom_y + 59, 142, 20
        status_x = 160
    ElseIf d->mode = FILEDIALOG_MODE_OPEN AndAlso d->read_only_option_enabled Then
        gui_SetBounds d->readOnlyBox, 10, bottom_y + 59, 142, 20
        status_x = 160
    End If
    If d->mode = FILEDIALOG_MODE_OPEN AndAlso d->choose_initial_view_enabled Then
        If d->read_only_option_enabled Then
            gui_SetBounds d->initialViewBox, 160, bottom_y + 59, 174, 20
            status_x = 342
        Else
            gui_SetBounds d->initialViewBox, 10, bottom_y + 59, 174, 20
            status_x = 192
        End If
    End If
    gui_SetBounds d->statusLabel, status_x, bottom_y + 59, width_value - status_x - 10, 20
    gui_SetBounds d->btn_enter, 10, height_value - 36, 112, 26
    gui_SetBounds d->btn_ok, width_value - 186, height_value - 36, 82, 26
    gui_SetBounds d->btn_cancel, width_value - 96, height_value - 36, 86, 26
    gui_RefreshLayout
End Sub

Private Sub filedialog_Update(ByVal root As Widget Ptr)
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    If d->finished Then Exit Sub
    Dim As ULongInt serial_value = Cast(TextBoxData Ptr, d->searchBox->data)->change_serial
    If serial_value <> d->search_serial Then
        d->search_serial = serial_value
        d->search_text = LCase(textbox_GetText(d->searchBox))
        If d->search_all_places Then
            ' Changing the query leaves multi-place mode; click Find File to scan the places again.
            filedialog_Refresh root
        Else
            filedialog_RebuildView root
        End If
    End If
    If checkbox_GetChecked(d->hiddenBox) <> d->show_hidden Then
        d->show_hidden = checkbox_GetChecked(d->hiddenBox)
        filedialog_RebuildView root
    End If
    serial_value = Cast(TextBoxData Ptr, d->filterBox->data)->change_serial
    If serial_value <> d->filter_serial Then
        d->filter_serial = serial_value
        Dim As String pattern_value = Trim(textbox_GetText(d->filterBox))
        If filedialog_IsSafeFilter(pattern_value) Then
            d->filter_pattern = pattern_value
            filedialog_RebuildView root
        Else
            filedialog_Status d, "Invalid filter; the last valid filter remains active."
        End If
    End If
    serial_value = Cast(TextBoxData Ptr, d->filenameBox->data)->change_serial
    If serial_value <> d->filename_serial Then
        d->filename_serial = serial_value
        If d->pending_replace <> "" Then filedialog_ClearReplace d
        If d->mode <> FILEDIALOG_MODE_FOLDER AndAlso d->creating_folder = 0 Then _
            listbox_SetSelectedIndex d->lst, -1
    End If
    serial_value = listbox_GetSelectionChangeCount(d->lst)
    Dim As Integer entry_index = filedialog_SelectedEntry(d)
    If serial_value <> d->selection_serial OrElse entry_index <> d->selected_entry Then
        d->selection_serial = serial_value : d->selected_entry = entry_index
        If entry_index >= 0 AndAlso d->creating_folder = 0 AndAlso d->mode <> FILEDIALOG_MODE_FOLDER Then
            If (d->entries(entry_index).attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY) = 0 Then
                Dim As String selected_name = d->entries(entry_index).entry_name
                If d->search_all_places AndAlso d->entries(entry_index).entry_path <> "" Then _
                    selected_name = d->entries(entry_index).entry_path
                textbox_SetText d->filenameBox, selected_name, -1
                d->filename_serial = Cast(TextBoxData Ptr, d->filenameBox->data)->change_serial
                If d->pending_replace <> "" Then filedialog_ClearReplace d
            End If
        End If
        If d->previewWidget <> 0 Then _
            gui_InvalidateRect d->previewWidget->ax, d->previewWidget->ay, d->previewWidget->w, d->previewWidget->h
    End If
    If d->previewWidget <> 0 AndAlso checkbox_GetChecked(d->previewBox) <> d->preview_enabled Then
        d->preview_enabled = checkbox_GetChecked(d->previewBox)
        d->layout_width = -1
        filedialog_Layout root
        gui_InvalidateRect d->previewWidget->ax, d->previewWidget->ay, d->previewWidget->w, d->previewWidget->h
    End If
    serial_value = listbox_GetDoubleActivationCount(d->lst)
    If serial_value <> d->double_serial Then
        d->double_serial = serial_value
        If entry_index < 0 OrElse (d->entries(entry_index).attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY) <> 0 Then
            filedialog_OnOpenFolder d->lst
        Else
            filedialog_OnOK d->lst
        End If
    End If
    serial_value = listbox_GetActivationCount(d->places)
    If serial_value <> d->places_serial Then
        d->places_serial = serial_value
        Dim As Integer place_index = listbox_GetSelectedIndex(d->places)
        If place_index >= 0 AndAlso place_index < d->place_count Then _
            filedialog_Navigate root, d->place_paths(place_index)
    End If
    ' Lazy metadata queries are limited to eight visible entries per frame.
    ' Scroll/search reuses the cache; an idle frame does no filesystem work.
    Dim As Integer first_row = listbox_GetTopIndex(d->lst)
    Dim As Integer last_row = first_row + d->lst->h \ 22 + 2
    If last_row >= listbox_GetItemCount(d->lst) Then last_row = listbox_GetItemCount(d->lst) - 1
    Dim As Integer details_budget = 8
    For row_index As Integer = first_row To last_row
        Dim As LongInt entry_id
        If listbox_GetItemData(d->lst, row_index, entry_id) = 0 Then Continue For
        If entry_id < 1 OrElse entry_id > d->entry_count Then Continue For
        entry_index = CInt(entry_id) - 1
        If d->entries(entry_index).details_loaded Then Continue For
        filedialog_LoadDetails d, entry_index
        Dim As String row_text = filedialog_RowText(d, entry_index)
        listbox_SetItem d->lst, row_index, row_text
        details_budget -= 1
        If details_budget = 0 Then Exit For
    Next row_index
End Sub

' -------------------------------------------------------------------------
' Construction and public interface
' -------------------------------------------------------------------------

Private Sub filedialog_OwnControl(ByVal w As Widget Ptr, ByVal parent As Widget Ptr)
    gui_AddGeneratedWidget w
    gui_SetParent w, parent
End Sub

Function filedialog_AddPlace(ByVal w As Widget Ptr, ByVal caption As String, ByVal pathValue As String) As Integer
    If filedialog_GetRoot(w) <> w OrElse w = 0 Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    If d->place_count >= FILEDIALOG_PLACE_CAPACITY OrElse Len(caption) < 1 OrElse Len(caption) > 80 Then Return 0
    pathValue = filedialog_ResolvePath(pathValue, d->current_path)
    If pathValue = "" OrElse system_IsDirectory(pathValue) = 0 Then Return 0
    For place_index As Integer = 0 To d->place_count - 1
        If d->place_paths(place_index) = pathValue Then Return 0
    Next place_index
    d->place_paths(d->place_count) = pathValue
    d->place_count += 1
    listbox_AddItem d->places, filedialog_DisplayName(caption)
    Return -1
End Function

Function filedialog_AddSupportPath(ByVal w As Widget Ptr, ByVal pathValue As String) As Integer
    If filedialog_GetRoot(w) <> w OrElse w = 0 Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    If d->mode <> FILEDIALOG_MODE_OPEN OrElse d->support_path_count >= FILEDIALOG_SUPPORT_PATH_CAPACITY Then Return 0
    pathValue = filedialog_ResolvePath(pathValue, d->current_path)
    If pathValue = "" OrElse system_IsDirectory(pathValue) = 0 Then Return 0
    For path_index As Integer = 0 To d->support_path_count - 1
        If d->support_paths(path_index) = pathValue Then Return 0
    Next path_index
    d->support_paths(d->support_path_count) = pathValue
    d->support_path_count += 1
    Dim As String directory_name = filedialog_DisplayName(pathValue)
    filedialog_AddPlace w, "Support: " & Left(directory_name, 72), pathValue
    d->layout_width = -1
    filedialog_Layout w
    Return -1
End Function

Private Function filedialog_CreateModeAtPath(ByVal nm As String, ByVal x As Integer, _
    ByVal y As Integer, ByVal initialPath As String, ByVal initialFilename As String, _
    ByVal mode As Integer) As Widget Ptr
    Dim As Widget Ptr root = New Widget
    If root = 0 Then Return 0
    Dim As FileDialogData Ptr d = New FileDialogData
    If d = 0 Then Delete root : Return 0
    root->name = nm : root->x = x : root->y = y : root->w = 0 : root->h = 0
    root->visible = 1 : root->enabled = 1 : root->ax = x : root->ay = y
    root->evis = 1 : root->een = 1 : root->data = d
    root->update = @filedialog_Update : root->destroy = @filedialog_Destroy
    d->current_path = filedialog_ResolvePath(initialPath, CurDir)
    If d->current_path = "" OrElse system_IsDirectory(d->current_path) = 0 Then d->current_path = CurDir
    d->filter_pattern = "*" : d->mode = mode : d->confirm_overwrite = -1
    d->selected_entry = -2
    d->history(0) = d->current_path : d->history_count = 1
    Dim As Integer viewport_width, viewport_height
    backend_GetSize viewport_width, viewport_height
    Dim As Integer width_value = FILEDIALOG_WINDOW_WIDTH, height_value = FILEDIALOG_WINDOW_HEIGHT
    If viewport_width > 0 AndAlso width_value > viewport_width - 16 Then width_value = viewport_width - 16
    If viewport_height > 0 AndAlso height_value > viewport_height - 16 Then height_value = viewport_height - 16
    If width_value < 360 Then width_value = 360
    If height_value < 300 Then height_value = 300
    If x + width_value > viewport_width Then root->x = viewport_width - width_value
    If y + height_value > viewport_height Then root->y = viewport_height - height_value
    If root->x < 0 Then root->x = 0
    If root->y < 0 Then root->y = 0
    d->win = subwindow_Create(nm & "_win", IIf(mode = FILEDIALOG_MODE_SAVE, "Save File", _
        IIf(mode = FILEDIALOG_MODE_FOLDER, "Select Folder", "Open File")), 0, 0, width_value, height_value)
    subwindow_SetDialogStyle d->win
    subwindow_SetBorderStyle d->win, SUBWINDOW_BORDER_SIZABLE_SINGLE
    ' A modal picker must retain its actions. Minimize would suspend all of
    ' its children while leaving modal ownership active.
    subwindow_SetMinButton d->win, 0
    subwindow_SetMaxButton d->win, 0
    subwindow_SetMoveParent d->win, -1
    subwindow_SetCloseHandler d->win, @filedialog_OnCancel
    d->win->keyboard_global = -1 : d->win->update = @filedialog_WindowUpdate
    filedialog_OwnControl d->win, root
    d->btn_back = button_Create(nm & "_back", "Back", 0, 0, 48, 26, @filedialog_OnHistory)
    d->btn_forward = button_Create(nm & "_forward", "Next", 0, 0, 48, 26, @filedialog_OnHistory)
    d->btn_up = button_Create(nm & "_up", "Up", 0, 0, 48, 26, @filedialog_OnUp)
    d->btn_refresh = button_Create(nm & "_refresh", "Refresh", 0, 0, 68, 26, @filedialog_OnRefresh)
    d->btn_new = button_Create(nm & "_new", "New folder", 0, 0, 102, 26, @filedialog_OnNewFolder)
    d->btn_find_files = button_Create(nm & "_find_files", "Find File", 0, 0, 100, 26, @filedialog_OnFindFiles)
    d->btn_search_paths = button_Create(nm & "_search_paths", "Search Paths", 0, 0, 112, 26, @filedialog_OnSearchPaths)
    d->btn_options = button_Create(nm & "_options", "Options", 0, 0, 82, 26, @filedialog_OnOptions)
    d->btn_options->visible = 0
    d->pathBox = textbox_Create(nm & "_path", d->current_path, 0, 0, 200, 26, 0, 0)
    d->btn_go = button_Create(nm & "_go", "Go", 0, 0, 48, 26, @filedialog_OnGo)
    d->lst = listbox_Create(nm & "_lst", 0, 0, 200, 160)
    d->lst->update = @filedialog_ListUpdate
    listbox_SetRowHeight d->lst, 22
    d->placesLabel = label_Create(nm & "_places_label", "Places", 0, 0, LABEL_COLOR_THEME_TEXT)
    d->places = listbox_Create(nm & "_places", 0, 0, 122, 160)
    listbox_SetRowHeight d->places, 26
    d->searchLabel = label_Create(nm & "_search_label", "Search", 0, 0, LABEL_COLOR_THEME_TEXT)
    d->searchBox = textbox_Create(nm & "_search", "", 0, 0, 200, 24, 0, 0)
    textbox_SetCueBanner d->searchBox, "Find in this folder", RGB(100, 100, 100)
    d->hiddenBox = checkbox_Create(nm & "_hidden", "Show hidden", 0, 0)
    d->readOnlyBox = checkbox_Create(nm & "_read_only", "Open read-only", 0, 0)
    d->readOnlyBox->visible = 0
    d->initialViewBox = checkbox_Create(nm & "_initial_view", "Choose initial view", 0, 0)
    d->initialViewBox->visible = 0
    d->saveOptionBox = checkbox_Create(nm & "_save_option", "Binary DXF", 0, 0)
    d->saveOptionBox->visible = 0
    d->previewBox = checkbox_Create(nm & "_preview", "Preview", 0, 0)
    d->previewBox->visible = 0
    d->filterLabel = label_Create(nm & "_filter_label", "Filter", 0, 0, LABEL_COLOR_THEME_TEXT)
    d->filterBox = textbox_Create(nm & "_filter", "*", 0, 0, 132, 24, 0, 0)
    d->nameLabel = label_Create(nm & "_name_label", "Name", 0, 0, LABEL_COLOR_THEME_TEXT)
    d->filenameBox = textbox_Create(nm & "_name", Left(initialFilename, FILEDIALOG_MAX_PATH_BYTES), 0, 0, 200, 24, 0, 0)
    d->statusLabel = label_Create(nm & "_status", "", 0, 0, LABEL_COLOR_THEME_TEXT)
    d->btn_enter = button_Create(nm & "_enter", "Open Folder", 0, 0, 112, 26, @filedialog_OnOpenFolder)
    d->btn_enter->visible = mode = FILEDIALOG_MODE_FOLDER
    d->btn_ok = button_Create(nm & "_ok", IIf(mode = FILEDIALOG_MODE_SAVE, "Save", _
        IIf(mode = FILEDIALOG_MODE_FOLDER, "Select", "Open")), 0, 0, 82, 26, @filedialog_OnOK)
    d->btn_cancel = button_Create(nm & "_cancel", "Cancel", 0, 0, 86, 26, @filedialog_OnCancel)
    Dim As Widget Ptr controls(0 To 27) = {d->btn_back, d->btn_forward, d->btn_up, d->btn_refresh, d->btn_find_files, d->btn_search_paths, d->btn_new, _
        d->pathBox, d->btn_go, d->lst, d->placesLabel, d->places, d->searchLabel, d->searchBox, d->hiddenBox, _
        d->filterLabel, d->filterBox, d->nameLabel, d->filenameBox, d->statusLabel, d->btn_enter, d->btn_ok, d->btn_cancel, _
        d->readOnlyBox, d->initialViewBox, d->btn_options, d->previewBox, d->saveOptionBox}
    For control_index As Integer = 0 To 27
        filedialog_OwnControl controls(control_index), d->win
    Next control_index
    textbox_SetInputLimit d->pathBox, FILEDIALOG_MAX_PATH_BYTES
    textbox_SetInputLimit d->filenameBox, FILEDIALOG_MAX_PATH_BYTES
    textbox_SetInputLimit d->searchBox, 255
    textbox_SetInputLimit d->filterBox, FILEDIALOG_MAX_FILTER_BYTES
    textbox_SetReadOnly d->filenameBox, mode = FILEDIALOG_MODE_FOLDER
    textbox_SetKeyEventHandler d->pathBox, @filedialog_TextKey
    textbox_SetKeyEventHandler d->searchBox, @filedialog_TextKey
    textbox_SetKeyEventHandler d->filterBox, @filedialog_TextKey
    textbox_SetKeyEventHandler d->filenameBox, @filedialog_TextKey
    ' These controls handle Enter before the manager's default action.
    d->pathBox->captures_return = -1 : d->searchBox->captures_return = -1
    d->filterBox->captures_return = -1 : d->filenameBox->captures_return = -1
    gui_SetDefaultAction d->btn_ok, -1
    gui_SetCancelAction d->btn_cancel, -1
    label_SetClipToBounds d->statusLabel, -1
    label_SetClipToBounds d->placesLabel, -1
    d->btn_back->enabled = 0 : d->btn_forward->enabled = 0
    filedialog_AddPlace root, "Starting folder", d->current_path
    Dim As String home_path = Environ("HOME")
#If Defined(__FB_WIN32__)
    If home_path = "" Then home_path = Environ("USERPROFILE")
#EndIf
    If home_path <> "" Then
        filedialog_AddPlace root, "Home", home_path
        filedialog_AddPlace root, "Desktop", filedialog_JoinPath(home_path, "Desktop")
        filedialog_AddPlace root, "Documents", filedialog_JoinPath(home_path, "Documents")
        filedialog_AddPlace root, "Downloads", filedialog_JoinPath(home_path, "Downloads")
    End If
    filedialog_AddPlace root, "Working folder", CurDir
#If Defined(__FB_WIN32__) And Not Defined(__FB_DOS__)
    ' Add available drive roots to Find File while leaving the current folder unchanged.
    For drive_index As Integer = Asc("A") To Asc("Z")
        Dim As String drive_path = Chr(drive_index) & ":\"
        If system_IsDirectory(drive_path) Then _
            filedialog_AddPlace root, "Drive " & Chr(drive_index), drive_path
    Next drive_index
#Else
    filedialog_AddPlace root, "Root", Left(d->current_path, filedialog_RootLength(d->current_path))
#EndIf
#If Not Defined(__FB_WIN32__) And Not Defined(__FB_DOS__)
    filedialog_AddPlace root, "Volumes", "/Volumes"
    filedialog_AddPlace root, "Media", "/media"
    filedialog_AddPlace root, "Boot", "/boot"
#EndIf
    filedialog_Layout root
    filedialog_Refresh root
    d->filename_serial = Cast(TextBoxData Ptr, d->filenameBox->data)->change_serial
    gui_AddWidget root
    If gui_TrySetModalRoot(root) = 0 Then gui_RemoveWidgetPtr root : Return 0
    gui_SetFocus d->lst
    Return root
End Function

Function filedialog_Create(ByVal nm As String, ByVal x As Integer, ByVal y As Integer) As Widget Ptr
    Return filedialog_CreateModeAtPath(nm, x, y, CurDir, "", FILEDIALOG_MODE_OPEN)
End Function

Function filedialog_CreateAtPath(ByVal nm As String, ByVal x As Integer, ByVal y As Integer, ByVal initialPath As String) As Widget Ptr
    Return filedialog_CreateModeAtPath(nm, x, y, initialPath, "", FILEDIALOG_MODE_OPEN)
End Function

Function filedialog_CreateSaveAtPath(ByVal nm As String, ByVal x As Integer, ByVal y As Integer, _
    ByVal initialPath As String, ByVal initialFilename As String) As Widget Ptr
    Return filedialog_CreateModeAtPath(nm, x, y, initialPath, initialFilename, FILEDIALOG_MODE_SAVE)
End Function

Function filedialog_CreateFolderAtPath(ByVal nm As String, ByVal x As Integer, ByVal y As Integer, ByVal initialPath As String) As Widget Ptr
    Return filedialog_CreateModeAtPath(nm, x, y, initialPath, "", FILEDIALOG_MODE_FOLDER)
End Function

Sub filedialog_SetDialogStyle(ByVal w As Widget Ptr)
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Exit Sub
    subwindow_SetDialogStyle Cast(FileDialogData Ptr, w->data)->win
    filedialog_Layout w
End Sub

Function filedialog_GetWindow(ByVal w As Widget Ptr) As Widget Ptr
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    Return Cast(FileDialogData Ptr, w->data)->win
End Function

Private Function filedialog_SetLabelColors( _
    ByVal w As Widget Ptr, ByVal foreground_color As ULong, _
    ByVal background_color As ULong _
) As Integer
    If w = 0 Then Return -1
    If label_SetTextColorLiteral(w, foreground_color) = 0 OrElse _
       label_SetBackgroundColor(w, background_color) = 0 Then Return 0
    Return -1
End Function

Private Function filedialog_SetTextBoxColors( _
    ByVal w As Widget Ptr, ByVal foreground_color As ULong, _
    ByVal background_color As ULong _
) As Integer
    If w = 0 Then Return -1
    If textbox_SetForegroundColor(w, foreground_color) = 0 OrElse _
       textbox_SetBackgroundColor(w, background_color) = 0 Then Return 0
    Return -1
End Function

Private Function filedialog_SetListColors( _
    ByVal w As Widget Ptr, ByVal foreground_color As ULong, _
    ByVal background_color As ULong _
) As Integer
    If w = 0 Then Return -1
    If listbox_SetForegroundColor(w, foreground_color) = 0 OrElse _
       listbox_SetBackgroundColor(w, background_color) = 0 Then Return 0
    Return -1
End Function

Private Function filedialog_SetCheckBoxColors( _
    ByVal w As Widget Ptr, ByVal foreground_color As ULong, _
    ByVal background_color As ULong _
) As Integer
    If w = 0 Then Return -1
    If checkbox_SetForegroundColor(w, foreground_color) = 0 OrElse _
       checkbox_SetBackgroundColor(w, background_color) = 0 Then Return 0
    Return -1
End Function

Private Function filedialog_SetButtonColor( _
    ByVal w As Widget Ptr, ByVal background_color As ULong _
) As Integer
    If w = 0 Then Return -1
    Return button_SetBackgroundColor(w, background_color)
End Function

Function filedialog_SetColors( _
    ByVal w As Widget Ptr, ByVal foreground_color As ULong, _
    ByVal background_color As ULong _
) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    If d->win = 0 OrElse subwindow_SetClientColor( _
        d->win, background_color _
    ) = 0 OrElse subwindow_SetTitleColors( _
        d->win, background_color, foreground_color _
    ) = 0 Then Return 0

    If filedialog_SetLabelColors(d->nameLabel, foreground_color, background_color) = 0 OrElse _
       filedialog_SetLabelColors(d->filterLabel, foreground_color, background_color) = 0 OrElse _
       filedialog_SetLabelColors(d->searchLabel, foreground_color, background_color) = 0 OrElse _
       filedialog_SetLabelColors(d->placesLabel, foreground_color, background_color) = 0 OrElse _
       filedialog_SetLabelColors(d->statusLabel, foreground_color, background_color) = 0 OrElse _
       filedialog_SetTextBoxColors(d->pathBox, foreground_color, background_color) = 0 OrElse _
       filedialog_SetTextBoxColors(d->searchBox, foreground_color, background_color) = 0 OrElse _
       filedialog_SetTextBoxColors(d->filterBox, foreground_color, background_color) = 0 OrElse _
       filedialog_SetTextBoxColors(d->filenameBox, foreground_color, background_color) = 0 OrElse _
       filedialog_SetListColors(d->lst, foreground_color, background_color) = 0 OrElse _
       filedialog_SetListColors(d->places, foreground_color, background_color) = 0 OrElse _
       filedialog_SetCheckBoxColors(d->hiddenBox, foreground_color, background_color) = 0 Then _
        Return 0

    If filedialog_SetButtonColor(d->btn_ok, background_color) = 0 OrElse _
       filedialog_SetButtonColor(d->btn_cancel, background_color) = 0 OrElse _
       filedialog_SetButtonColor(d->btn_enter, background_color) = 0 OrElse _
       filedialog_SetButtonColor(d->btn_back, background_color) = 0 OrElse _
       filedialog_SetButtonColor(d->btn_forward, background_color) = 0 OrElse _
       filedialog_SetButtonColor(d->btn_up, background_color) = 0 OrElse _
       filedialog_SetButtonColor(d->btn_go, background_color) = 0 OrElse _
       filedialog_SetButtonColor(d->btn_refresh, background_color) = 0 OrElse _
       filedialog_SetButtonColor(d->btn_new, background_color) = 0 Then _
        Return 0
    Return -1
End Function

Function filedialog_GetSelectedFile(ByVal w As Widget Ptr) As String
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return ""
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    If d->finished = 1 Then Return d->selected_file
    Return ""
End Function

Function filedialog_GetHighlightedFile(ByVal w As Widget Ptr) As String
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Return ""
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    If d->mode <> FILEDIALOG_MODE_OPEN OrElse d->selected_entry < 0 OrElse _
       d->selected_entry >= d->entry_count Then Return ""
    If (d->entries(d->selected_entry).attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY) <> 0 Then Return ""
    If d->search_all_places AndAlso d->entries(d->selected_entry).entry_path <> "" Then _
        Return d->entries(d->selected_entry).entry_path
    Return filedialog_JoinPath(d->current_path, d->entries(d->selected_entry).entry_name)
End Function

Function filedialog_SetPreviewWidget(ByVal w As Widget Ptr, ByVal previewWidget As Widget Ptr) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w OrElse previewWidget = 0 Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    If d->mode <> FILEDIALOG_MODE_OPEN OrElse (d->previewWidget <> 0 AndAlso d->previewWidget <> previewWidget) Then Return 0
    If d->previewWidget = previewWidget Then Return -1
    d->previewWidget = previewWidget
    filedialog_OwnControl d->previewWidget, d->win
    d->preview_enabled = checkbox_GetChecked(d->previewBox)
    d->layout_width = -1
    filedialog_Layout w
    Return -1
End Function

Function filedialog_GetResultState(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    Return Cast(FileDialogData Ptr, w->data)->finished
End Function

Function filedialog_SetReadOnlyOption(ByVal w As Widget Ptr, ByVal enabled_state As Integer) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    If d->mode <> FILEDIALOG_MODE_OPEN OrElse d->readOnlyBox = 0 Then Return 0
    d->read_only_option_enabled = (enabled_state <> 0)
    d->readOnlyBox->visible = d->read_only_option_enabled
    If d->read_only_option_enabled = 0 Then checkbox_SetChecked d->readOnlyBox, 0
    d->layout_width = -1
    filedialog_Layout w
    Return -1
End Function

Function filedialog_GetReadOnlyOption(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    If d->read_only_option_enabled = 0 OrElse d->readOnlyBox = 0 Then Return 0
    Return checkbox_GetChecked(d->readOnlyBox) <> 0
End Function

Function filedialog_SetInitialViewOption(ByVal w As Widget Ptr, ByVal enabled_state As Integer) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    If d->mode <> FILEDIALOG_MODE_OPEN OrElse d->initialViewBox = 0 Then Return 0
    d->choose_initial_view_enabled = (enabled_state <> 0)
    d->initialViewBox->visible = d->choose_initial_view_enabled
    If d->choose_initial_view_enabled = 0 Then checkbox_SetChecked d->initialViewBox, 0
    d->layout_width = -1
    filedialog_Layout w
    Return -1
End Function

Function filedialog_GetInitialViewOption(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    If d->choose_initial_view_enabled = 0 OrElse d->initialViewBox = 0 Then Return 0
    Return checkbox_GetChecked(d->initialViewBox) <> 0
End Function

Function filedialog_SetSaveOption(ByVal w As Widget Ptr, ByRef label_text As Const String, ByVal enabled_state As Integer, ByVal checked_state As Integer) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    If d->mode <> FILEDIALOG_MODE_SAVE OrElse d->saveOptionBox = 0 OrElse _
       Len(label_text) < 1 OrElse Len(label_text) > 64 OrElse InStr(label_text, Chr(0)) Then Return 0
    If checkbox_SetText(d->saveOptionBox, label_text) = 0 Then Return 0
    d->save_option_enabled = (enabled_state <> 0)
    If d->save_option_enabled Then
        checkbox_SetChecked d->saveOptionBox, checked_state <> 0
    Else
        checkbox_SetChecked d->saveOptionBox, 0
    End If
    d->layout_width = -1
    filedialog_Layout w
    Return -1
End Function

Function filedialog_GetSaveOption(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    If d->mode <> FILEDIALOG_MODE_SAVE OrElse d->save_option_enabled = 0 OrElse d->saveOptionBox = 0 Then Return 0
    Return checkbox_GetChecked(d->saveOptionBox) <> 0
End Function

Function filedialog_SetTitle(ByVal w As Widget Ptr, ByVal title_text As String) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    If Len(title_text) < 1 OrElse Len(title_text) > FILEDIALOG_MAX_TITLE_BYTES OrElse InStr(title_text, Chr(0)) Then Return 0
    Return subwindow_SetTitle(Cast(FileDialogData Ptr, w->data)->win, title_text)
End Function

Function filedialog_SetOptionsButton(ByVal w As Widget Ptr, ByVal enabled_state As Integer) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    If d->mode <> FILEDIALOG_MODE_OPEN AndAlso d->mode <> FILEDIALOG_MODE_SAVE Then Return 0
    d->options_enabled = (enabled_state <> 0)
    d->options_requested = 0
    d->layout_width = 0
    filedialog_Layout w
    Return -1
End Function

Function filedialog_OptionsRequested(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    If (d->mode <> FILEDIALOG_MODE_OPEN AndAlso d->mode <> FILEDIALOG_MODE_SAVE) OrElse _
       d->options_enabled = 0 OrElse d->options_requested = 0 Then Return 0
    d->options_requested = 0
    Return -1
End Function

Function filedialog_SetFilter(ByVal w As Widget Ptr, ByVal filterPattern As String) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    filterPattern = Trim(filterPattern)
    If filedialog_IsSafeFilter(filterPattern) = 0 Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    d->filter_pattern = filterPattern
    textbox_SetText d->filterBox, filterPattern, -1
    d->filter_serial = Cast(TextBoxData Ptr, d->filterBox->data)->change_serial
    filedialog_RebuildView w
    Return -1
End Function

Function filedialog_GetFilter(ByVal w As Widget Ptr) As String
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return ""
    Return Cast(FileDialogData Ptr, w->data)->filter_pattern
End Function

Function filedialog_SetSort(ByVal w As Widget Ptr, ByVal column_index As Integer, ByVal descending As Integer) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    If column_index < FILEDIALOG_SORT_NAME OrElse column_index > FILEDIALOG_SORT_MODIFIED Then Return 0
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, w->data)
    d->sort_column = column_index : d->sort_descending = descending <> 0
    d->layout_width = 0
    filedialog_Layout w
    filedialog_RebuildView w
    Return -1
End Function

Function filedialog_SetDefaultExtension(ByVal w As Widget Ptr, ByVal extension_text As String) As Integer
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Return 0
    If extension_text <> "" Then
        If Left(extension_text, 1) = "." Then extension_text = Mid(extension_text, 2)
        If Len(extension_text) < 1 OrElse Len(extension_text) > 32 Then Return 0
        For character_index As Integer = 1 To Len(extension_text)
            Dim As Integer character_value = Asc(extension_text, character_index)
            If Not ((character_value >= 48 AndAlso character_value <= 57) OrElse _
                (character_value >= 65 AndAlso character_value <= 90) OrElse _
                (character_value >= 97 AndAlso character_value <= 122) OrElse character_value = 95 OrElse character_value = 45) Then Return 0
        Next character_index
        extension_text = "." & extension_text
    End If
    Cast(FileDialogData Ptr, w->data)->default_extension = extension_text
    filedialog_ClearReplace Cast(FileDialogData Ptr, w->data)
    Return -1
End Function

Sub filedialog_SetConfirmOverwrite(ByVal w As Widget Ptr, ByVal enabled_state As Integer)
    If w = 0 OrElse filedialog_GetRoot(w) <> w Then Exit Sub
    Cast(FileDialogData Ptr, w->data)->confirm_overwrite = enabled_state <> 0
    filedialog_ClearReplace Cast(FileDialogData Ptr, w->data)
End Sub

/' end of filedialog.bas '/
