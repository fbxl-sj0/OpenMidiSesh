/'
    Project: omaGUI
    ---------------

    File: filedialog.bas

    Purpose:

        Implement a generated-widget file dialog.

    Responsibilities:

        - show directory contents in an omaGUI list box
        - navigate directories through dialog-owned path state
        - filter files with bounded case-insensitive wildcard-list matching
        - collect an optional safe filename for save operations
        - report accepted and cancelled dialog states
        - claim modal update focus while the dialog is open
        - apply a bounded title to the dialog-owned subwindow

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
#include once "src/system/filesystem.bi"

#include once "dir.bi"
#include once "vbcompat.bi"

Type FileDialogData
    As Widget Ptr win
    As Widget Ptr lst
    As Widget Ptr btn_ok
    As Widget Ptr btn_cancel
    As Widget Ptr filenameBox
    As Widget Ptr btn_enter
    As String current_path
    As String selected_file
    As String filter_pattern
    As Integer mode
    As Integer finished
End Type


' -------------------------------------------------------------------------
' Path helpers
' -------------------------------------------------------------------------

#If Defined(__FB_WIN32__)
Const FILEDIALOG_PATH_SEPARATOR As String = "\"
#Else
Const FILEDIALOG_PATH_SEPARATOR As String = "/"
#EndIf

Const FILEDIALOG_WINDOW_WIDTH As Integer = 400
Const FILEDIALOG_WINDOW_HEIGHT As Integer = 340
Const FILEDIALOG_LIST_X As Integer = 10
Const FILEDIALOG_LIST_Y As Integer = 30
Const FILEDIALOG_LIST_WIDTH As Integer = 380
Const FILEDIALOG_LIST_HEIGHT As Integer = 184
Const FILEDIALOG_FILENAME_Y As Integer = 244
Const FILEDIALOG_FILENAME_HEIGHT As Integer = 24
Const FILEDIALOG_ACTION_Y As Integer = 292
Const FILEDIALOG_ACTION_WIDTH As Integer = 80
Const FILEDIALOG_ACTION_HEIGHT As Integer = 30
Const FILEDIALOG_ACCEPT_X As Integer = 220
Const FILEDIALOG_CANCEL_X As Integer = 310
Const FILEDIALOG_MAX_TITLE_BYTES As Integer = 255
Const FILEDIALOG_ENTRY_ATTRIBUTE_MASK As Integer = _
    fbNormal Or fbReadOnly Or fbHidden Or fbSystem Or fbDirectory Or fbArchive

#If Defined(__FB_WIN32__)
/'
    The Windows OPEN/DIR wildcard accepts *.*, which includes extensionless
    entries there. Unix glob syntax requires * to retain extensionless files.
    Both branches remain inside the standard FreeBASIC Dir API.
'/
Const FILEDIALOG_SEARCH_WILDCARD As String = "*.*"
#Else
Const FILEDIALOG_SEARCH_WILDCARD As String = "*"
#EndIf

Declare Function filedialog_CreateModeAtPath( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal initialPath As String, _
    ByVal initialFilename As String, _
    ByVal mode As Integer _
) As Widget Ptr


Private Function filedialog_JoinPath( _
    ByVal basePath As String, _
    ByVal childName As String _
) As String

    If Len(basePath) = 0 Then Return childName

    If Right(basePath, 1) = FILEDIALOG_PATH_SEPARATOR Then
        Return basePath & childName
    End If

    Return basePath & FILEDIALOG_PATH_SEPARATOR & childName

End Function


Private Function filedialog_GetParentPath(ByVal pathValue As String) As String

    Dim As Integer separatorPosition

    If Len(pathValue) = 0 Then Return ""

    separatorPosition = InStrRev(pathValue, FILEDIALOG_PATH_SEPARATOR)

    If separatorPosition = 0 Then Return pathValue
    If separatorPosition = 1 Then Return Left(pathValue, 1)

    ' Preserve a drive-letter volume root when navigating upward.
    If separatorPosition = 3 AndAlso Mid(pathValue, 2, 1) = ":" Then
        Return Left(pathValue, separatorPosition)
    End If

    Return Left(pathValue, separatorPosition - 1)

End Function


Private Function filedialog_IsSafeFilename(ByVal filename As String) As Integer

    filename = Trim(filename)

    If filename = "" OrElse filename = "." OrElse filename = ".." Then Return 0
    If InStr(filename, "/") <> 0 OrElse InStr(filename, "\") <> 0 Then Return 0
    If InStr(filename, ":") <> 0 Then Return 0

    Return -1

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


Private Function filedialog_FilenameText(ByVal dialogData As FileDialogData Ptr) As String

    If dialogData = 0 OrElse dialogData->filenameBox = 0 Then Return ""
    Return Trim(Cast(TextBoxData Ptr, dialogData->filenameBox->data)->text)

End Function


Private Sub filedialog_SetFilenameText( _
    ByVal dialogData As FileDialogData Ptr, _
    ByVal filename As String _
)

    If dialogData = 0 OrElse dialogData->filenameBox = 0 Then Exit Sub

    Cast(TextBoxData Ptr, dialogData->filenameBox->data)->text = filename

End Sub


Private Sub filedialog_Destroy(ByVal w As Widget Ptr)
    If w->data <> 0 Then Delete Cast(FileDialogData Ptr, w->data)
End Sub

Private Function filedialog_GetRoot(ByVal w As Widget Ptr) As Widget Ptr
    Dim As Widget Ptr curr = w
    While curr <> 0
        If curr->destroy = @filedialog_Destroy AndAlso curr->data <> 0 Then Return curr
        curr = curr->parent
    Wend
    Return 0
End Function

Private Function filedialog_AddEntry( _
    ByRef entryName As Const String, ByVal attributes As UInteger, _
    ByVal context As Any Ptr _
) As Integer
    Dim As FileDialogData Ptr dialogData = Cast(FileDialogData Ptr, context)
    If dialogData = 0 OrElse dialogData->lst = 0 Then Return 1
    If (attributes And SYSTEM_FILE_ATTRIBUTE_DIRECTORY) <> 0 Then
        listbox_AddItem dialogData->lst, "[" & entryName & "]"
    ElseIf filedialog_FilterMatches(entryName, dialogData->filter_pattern) Then
        listbox_AddItem dialogData->lst, entryName
    End If
    Return 0
End Function

Private Sub filedialog_Refresh(ByVal root As Widget Ptr)
    Dim As FileDialogData Ptr d = root->data
    If d = 0 Then Exit Sub

    listbox_Clear(d->lst)
    listbox_AddItem(d->lst, "..")

    system_EnumerateDirectory d->current_path, SYSTEM_DIRECTORY_FOLDERS, @filedialog_AddEntry, d
    If d->mode = FILEDIALOG_MODE_FOLDER Then
        If d->filenameBox <> 0 Then textbox_SetText d->filenameBox, d->current_path, -1
    Else
        system_EnumerateDirectory d->current_path, SYSTEM_DIRECTORY_FILES, @filedialog_AddEntry, d
    End If
End Sub


Private Function filedialog_SelectedDirectory(ByVal d As FileDialogData Ptr) As String
    If d = 0 OrElse d->lst = 0 Then Return ""
    Dim As String selectedItem = listbox_GetSelectedItem(d->lst)
    If selectedItem = ".." Then Return filedialog_GetParentPath(d->current_path)
    If Len(selectedItem) >= 2 AndAlso Left(selectedItem, 1) = "[" AndAlso _
       Right(selectedItem, 1) = "]" Then
        Dim As String pathValue = filedialog_JoinPath( _
            d->current_path, Mid(selectedItem, 2, Len(selectedItem) - 2))
        If system_IsDirectory(pathValue) Then Return pathValue
    End If
    Return ""
End Function


Private Sub filedialog_OnOpenFolder(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub
    Dim As FileDialogData Ptr d = Cast(FileDialogData Ptr, root->data)
    Dim As String selectedPath = filedialog_SelectedDirectory(d)
    If selectedPath = "" Then Exit Sub
    d->current_path = selectedPath
    filedialog_Refresh root
    gui_SetFocus d->lst
End Sub

Private Sub filedialog_OnOK(ByVal w As Widget Ptr)
    Dim As Widget Ptr root
    Dim As FileDialogData Ptr d
    Dim As ListBoxData Ptr ld
    Dim As String sel
    Dim As String filename

    root = filedialog_GetRoot(w)
    If root = 0 Then Exit Sub

    d = root->data
    If d = 0 OrElse d->lst = 0 Then Exit Sub

    ld = d->lst->data
    If ld = 0 Then Exit Sub

    If d->mode = FILEDIALOG_MODE_FOLDER Then
        Dim As String selectedPath = filedialog_SelectedDirectory(d)
        If selectedPath = "" Then selectedPath = d->current_path
        If system_IsDirectory(selectedPath) = 0 Then Exit Sub
        d->selected_file = selectedPath
        d->finished = 1
        Exit Sub
    End If

    sel = ""

    If ld->selected_index >= 0 AndAlso ld->selected_index < ld->item_count Then
        sel = ld->items(ld->selected_index)

        If filedialog_SelectedDirectory(d) <> "" Then
            filedialog_OnOpenFolder w
            Exit Sub
        End If
    End If

    If d->mode = FILEDIALOG_MODE_SAVE Then
        If sel <> "" Then filedialog_SetFilenameText d, sel

        filename = filedialog_FilenameText(d)
        If filedialog_IsSafeFilename(filename) = 0 Then Exit Sub

        d->selected_file = filedialog_JoinPath(d->current_path, filename)
        d->finished = 1
    ElseIf sel <> "" Then
        d->selected_file = filedialog_JoinPath(d->current_path, sel)
        d->finished = 1
    End If
End Sub

Private Sub filedialog_OnCancel(ByVal w As Widget Ptr)
    Dim As Widget Ptr root = filedialog_GetRoot(w)
    If root <> 0 Then Cast(FileDialogData Ptr, root->data)->finished = -1
End Sub

Function filedialog_Create(ByVal nm As String, ByVal x As Integer, ByVal y As Integer) As Widget Ptr

    Return filedialog_CreateModeAtPath( _
        nm, x, y, CurDir, "", FILEDIALOG_MODE_OPEN _
    )

End Function


Function filedialog_CreateAtPath( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal initialPath As String _
) As Widget Ptr

    Return filedialog_CreateModeAtPath( _
        nm, x, y, initialPath, "", FILEDIALOG_MODE_OPEN _
    )

End Function


Function filedialog_CreateSaveAtPath( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal initialPath As String, _
    ByVal initialFilename As String _
) As Widget Ptr

    Return filedialog_CreateModeAtPath( _
        nm, x, y, initialPath, initialFilename, FILEDIALOG_MODE_SAVE _
    )

End Function


Function filedialog_CreateFolderAtPath( _
    ByVal nm As String, ByVal x As Integer, ByVal y As Integer, _
    ByVal initialPath As String _
) As Widget Ptr
    Return filedialog_CreateModeAtPath( _
        nm, x, y, initialPath, "", FILEDIALOG_MODE_FOLDER)
End Function


Sub filedialog_SetDialogStyle(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @filedialog_Destroy Then Exit Sub
    Dim As Widget Ptr windowWidget = Cast(FileDialogData Ptr, w->data)->win
    If windowWidget <> 0 Then subwindow_SetDialogStyle windowWidget
End Sub

Function filedialog_GetWindow(ByVal w As Widget Ptr) As Widget Ptr
    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @filedialog_Destroy Then Return 0
    Return Cast(FileDialogData Ptr, w->data)->win
End Function


Private Function filedialog_CreateModeAtPath( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal initialPath As String, _
    ByVal initialFilename As String, _
    ByVal mode As Integer _
) As Widget Ptr

    Dim As Widget Ptr root = New Widget
    root->name = nm : root->x = x : root->y = y : root->w = 0 : root->h = 0
    root->visible = 1 : root->enabled = 1
    root->ax = x : root->ay = y
    root->evis = 1 : root->een = 1
    root->parent = 0 : root->next_widget = 0
    root->update = 0 : root->render = 0 : root->destroy = @filedialog_Destroy
    root->updated_this_frame = 0

    Dim As FileDialogData Ptr d = New FileDialogData
    d->current_path = Trim(initialPath)
    If d->current_path = "" Then d->current_path = CurDir
    If system_IsDirectory(d->current_path) = 0 Then d->current_path = CurDir
    d->selected_file = ""
    d->filter_pattern = "*"
    d->mode = mode
    d->finished = 0
    root->data = d

    /'
        The dialog root owns the requested screen position.  Its generated
        subwindow begins at local origin so parent-relative layout does not
        add the dialog offset twice.
    '/
    If d->mode = FILEDIALOG_MODE_SAVE Then
        d->win = subwindow_Create( _
            nm & "_win", "Save File", 0, 0, _
            FILEDIALOG_WINDOW_WIDTH, FILEDIALOG_WINDOW_HEIGHT _
        )
    ElseIf d->mode = FILEDIALOG_MODE_FOLDER Then
        d->win = subwindow_Create( _
            nm & "_win", "Select Folder", 0, 0, _
            FILEDIALOG_WINDOW_WIDTH, FILEDIALOG_WINDOW_HEIGHT _
        )
    Else
        d->win = subwindow_Create( _
            nm & "_win", "Select File", 0, 0, _
            FILEDIALOG_WINDOW_WIDTH, FILEDIALOG_WINDOW_HEIGHT _
        )
    End If
    subwindow_SetCloseHandler d->win, @filedialog_OnCancel
    subwindow_SetMoveParent d->win, -1
    gui_AddGeneratedWidget(d->win)
    gui_SetParent(d->win, root)

    d->lst = listbox_Create( _
        nm & "_lst", FILEDIALOG_LIST_X, FILEDIALOG_LIST_Y, _
        FILEDIALOG_LIST_WIDTH, FILEDIALOG_LIST_HEIGHT _
    )
    gui_AddGeneratedWidget(d->lst)
    gui_SetParent(d->lst, d->win)

    If d->mode = FILEDIALOG_MODE_SAVE OrElse d->mode = FILEDIALOG_MODE_FOLDER Then
        d->filenameBox = textbox_Create( _
            nm & "_name", initialFilename, FILEDIALOG_LIST_X, _
            FILEDIALOG_FILENAME_Y, FILEDIALOG_LIST_WIDTH, _
            FILEDIALOG_FILENAME_HEIGHT, 0, 0 _
        )
        gui_AddGeneratedWidget(d->filenameBox)
        gui_SetParent(d->filenameBox, d->win)
        textbox_SetInputLimit d->filenameBox, 4096
        If d->mode = FILEDIALOG_MODE_FOLDER Then
            textbox_SetReadOnly d->filenameBox, -1
            d->btn_enter = button_Create( _
                nm & "_enter", "Open Folder", FILEDIALOG_LIST_X, _
                FILEDIALOG_ACTION_Y, 100, FILEDIALOG_ACTION_HEIGHT, @filedialog_OnOpenFolder)
            gui_AddGeneratedWidget d->btn_enter
            gui_SetParent d->btn_enter, d->win
            d->btn_ok = button_Create( _
                nm & "_ok", "Select Folder", 170, _
                FILEDIALOG_ACTION_Y, 130, FILEDIALOG_ACTION_HEIGHT, @filedialog_OnOK)
        Else
            d->btn_ok = button_Create( _
                nm & "_ok", "Save", FILEDIALOG_ACCEPT_X, _
                FILEDIALOG_ACTION_Y, FILEDIALOG_ACTION_WIDTH, _
                FILEDIALOG_ACTION_HEIGHT, @filedialog_OnOK)
        End If
    Else
        d->btn_ok = button_Create( _
            nm & "_ok", "Open", FILEDIALOG_ACCEPT_X, _
            FILEDIALOG_ACTION_Y, FILEDIALOG_ACTION_WIDTH, _
            FILEDIALOG_ACTION_HEIGHT, @filedialog_OnOK _
        )
    End If
    gui_AddGeneratedWidget(d->btn_ok)
    gui_SetParent(d->btn_ok, d->win)

    d->btn_cancel = button_Create( _
        nm & "_cancel", "Cancel", FILEDIALOG_CANCEL_X, _
        FILEDIALOG_ACTION_Y, FILEDIALOG_ACTION_WIDTH, _
        FILEDIALOG_ACTION_HEIGHT, @filedialog_OnCancel _
    )
    gui_AddGeneratedWidget(d->btn_cancel)
    gui_SetParent(d->btn_cancel, d->win)

    filedialog_Refresh(root)
    gui_SetModalRoot(root)

    Return root
End Function

Function filedialog_GetSelectedFile(ByVal w As Widget Ptr) As String
    If w = 0 Then Return ""
    Dim As FileDialogData Ptr d = w->data
    If d->finished = 1 Then Return d->selected_file
    Return ""
End Function

Function filedialog_GetResultState(ByVal w As Widget Ptr) As Integer
    If w = 0 Then Return 0
    Dim As FileDialogData Ptr d = w->data
    Return d->finished
End Function

Function filedialog_SetTitle( _
    ByVal w As Widget Ptr, ByVal title_text As String _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    If Len(title_text) = 0 OrElse _
       Len(title_text) > FILEDIALOG_MAX_TITLE_BYTES OrElse _
       InStr(title_text, Chr(0)) Then Return 0
    Dim As FileDialogData Ptr dialog_data = _
        Cast(FileDialogData Ptr, w->data)
    If dialog_data->win = 0 OrElse dialog_data->win->data = 0 Then Return 0
    Cast(SubWindowData Ptr, dialog_data->win->data)->title = title_text
    Return -1
End Function


Function filedialog_SetFilter( _
    ByVal w As Widget Ptr, _
    ByVal filterPattern As String _
) As Integer
    Dim As FileDialogData Ptr dialogData

    If w = 0 OrElse w->data = 0 Then Return 0
    filterPattern = Trim(filterPattern)
    If filedialog_IsSafeFilter(filterPattern) = 0 Then Return 0
    dialogData = Cast(FileDialogData Ptr, w->data)
    dialogData->filter_pattern = filterPattern
    filedialog_Refresh w
    Return -1
End Function


Function filedialog_GetFilter(ByVal w As Widget Ptr) As String
    If w = 0 OrElse w->data = 0 Then Return ""
    Return Cast(FileDialogData Ptr, w->data)->filter_pattern
End Function

/' end of filedialog.bas '/
