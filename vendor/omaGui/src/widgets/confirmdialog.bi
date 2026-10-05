/'
    Project: omaGUI
    ---------------

    File: confirmdialog.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for confirmdialog.

    Purpose:

        Declare modal decision windows for actions that need an explicit
        user choice before changing application state.

    Responsibilities:

        - preserve the existing confirm-or-cancel factory
        - create reusable one-, two-, or three-choice modal windows
        - expose caller-selected result values to the owning application

    This file intentionally does NOT contain:

        - application-specific confirmation policy
        - file operations
        - platform-native dialog calls
'/

#ifndef __CONFIRMDIALOG_BI__
#define __CONFIRMDIALOG_BI__

#include once "src/widgets/widgets.bi"

' Portable presentation choices, independent of any operating-system flags.
Const CONFIRM_ICON_NONE As Integer = 0
Const CONFIRM_ICON_ERROR As Integer = 1
Const CONFIRM_ICON_QUESTION As Integer = 2
Const CONFIRM_ICON_WARNING As Integer = 3
Const CONFIRM_ICON_INFORMATION As Integer = 4

Type ConfirmDialogOptions
    As Integer width = 400
    As Integer maximum_height = 600
    As Integer icon_kind = CONFIRM_ICON_NONE
    As Integer default_choice = 0
End Type

/'
    Extended dialogs wrap the complete message and grow vertically up to the
    supplied limit. Invalid options or text which cannot fit return zero,
    without installing a modal root. Width: 320..4096; height: 150..4096;
    message: at most 16384 bytes. Choice indices are zero-based.

    As with the existing factories, call on the GUI thread outside an update
    traversal, then register the returned root with gui_AddWidget. Its generated
    children are registry-owned. Removing the root removes the whole tree.
'/
Declare Function confirmdialog_CreateChoicesEx( _
    ByVal nm As String, ByVal title As String, ByVal message As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByRef options As Const ConfirmDialogOptions, _
    ByVal firstText As String, ByVal firstResult As Integer, _
    ByVal secondText As String = "", ByVal secondResult As Integer = 0, _
    ByVal thirdText As String = "", ByVal thirdResult As Integer = 0, _
    ByVal closeResult As Integer = 0 _
) As Widget Ptr

' Returns a borrowed live child, or zero for a null/wrong widget or bad index.
' The caller must not retain this pointer after removing the dialog tree.
Declare Function confirmdialog_GetActionButton( _
    ByVal w As Widget Ptr, ByVal choiceIndex As Integer _
) As Widget Ptr

' Borrow the generated subwindow for application-specific dialog styling.
' The pointer remains valid only while the dialog root is registered.
Declare Function confirmdialog_GetWindow(ByVal w As Widget Ptr) As Widget Ptr
Declare Function confirmdialog_GetMessageLabel(ByVal w As Widget Ptr) As Widget Ptr

Declare Function confirmdialog_Create( _
    ByVal nm As String, _
    ByVal title As String, _
    ByVal message As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal confirmText As String = "Discard" _
) As Widget Ptr
Declare Function confirmdialog_CreateChoices( _
    ByVal nm As String, _
    ByVal title As String, _
    ByVal message As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal firstText As String, _
    ByVal firstResult As Integer, _
    ByVal secondText As String = "", _
    ByVal secondResult As Integer = 0, _
    ByVal thirdText As String = "", _
    ByVal thirdResult As Integer = 0, _
    ByVal closeResult As Integer = 0 _
) As Widget Ptr
Declare Function confirmdialog_GetResultState(ByVal w As Widget Ptr) As Integer
Declare Sub confirmdialog_SetDialogStyle(ByVal w As Widget Ptr)

#endif

' end of confirmdialog.bi
