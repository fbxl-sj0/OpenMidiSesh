/'
    Project: omaGUI
    ---------------

    File: confirmdialog.bas

    Purpose:

        Implement generated-widget modal decision windows.

    Responsibilities:

        - own the generated subwindow, label, and up to three action buttons
        - preserve the established confirm/cancel API and child names
        - report caller-selected result values without applying application policy
        - keep input inside the confirmation window while it is active
        - offer bounded wrapped messages and portable severity icons

    Targets:

        FreeBASIC builds with built-in gfxlib; gfxlib3 is optional when supplied by the compiler.

    Module API:

        Implementation unit assembled by omaGUI.bi when OMAGUI_IMPLEMENTATION is defined.

    This file intentionally does NOT contain:

        - application state mutation
        - file operations
        - platform-native dialog calls
'/

#lang "fb"

#include once "src/widgets/confirmdialog.bi"
#include once "src/widgets/subwindow.bi"
#include once "src/widgets/button.bi"
#include once "src/widgets/label.bi"

Type ConfirmDialogData
    As Widget Ptr windowWidget
    As Widget Ptr messageLabel
    As Widget Ptr actionButtons(0 To 2)
    As Integer actionResults(0 To 2)
    As Integer actionCount
    As Integer closeResult
    As Integer finished
    As Widget Ptr iconWidget
End Type

Type ConfirmDialogIconData
    As Integer icon_kind
End Type

' -------------------------------------------------------------------------
' Native message icons and unregistered allocation cleanup
' -------------------------------------------------------------------------

Private Sub confirmdialog_DestroyIcon(ByVal w As Widget Ptr)
    If w = 0 Then Exit Sub
    Delete Cast(ConfirmDialogIconData Ptr, w->data)
    w->data = 0
End Sub

Private Sub confirmdialog_RenderIcon(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As Integer iconKind = Cast(ConfirmDialogIconData Ptr, w->data)->icon_kind
    Dim As Integer cx = w->ax + 16
    Dim As Integer cy = w->ay + 16
    Dim As ULong fillColor
    Dim As String markText
    Select Case iconKind
    Case CONFIRM_ICON_ERROR: fillColor = RGB(180, 24, 24): markText = "X"
    Case CONFIRM_ICON_QUESTION: fillColor = RGB(32, 80, 160): markText = "?"
    Case CONFIRM_ICON_WARNING: fillColor = RGB(240, 192, 32): markText = "!"
    Case CONFIRM_ICON_INFORMATION: fillColor = RGB(32, 80, 160): markText = "i"
    Case Else: Exit Sub
    End Select
    ' A 32-pixel badge uses backend primitives and embedded font metrics on
    ' every target. No system icon, font handle, or raster resource is needed.
    backend_Circle cx, cy, 15, fillColor, -1
    backend_Circle cx, cy, 15, RGB(32, 32, 32)
    Dim As ULong textColor = RGB(255, 255, 255)
    If iconKind = CONFIRM_ICON_WARNING Then textColor = RGB(0, 0, 0)
    backend_Print cx - backend_GetTextWidth(markText) \ 2, _
        cy - backend_GetTextHeight() \ 2, textColor, markText
End Sub

Private Sub confirmdialog_FreeChild(ByVal w As Widget Ptr)
    If w = 0 Then Exit Sub
    If w->destroy <> 0 Then w->destroy(w)
    Delete w
End Sub

Private Sub confirmdialog_FreeUnregistered(ByVal root As Widget Ptr)
    If root = 0 Then Exit Sub
    Dim As ConfirmDialogData Ptr dataValue = Cast(ConfirmDialogData Ptr, root->data)
    If dataValue <> 0 Then
        For choiceIndex As Integer = 0 To 2
            confirmdialog_FreeChild dataValue->actionButtons(choiceIndex)
        Next choiceIndex
        confirmdialog_FreeChild dataValue->iconWidget
        confirmdialog_FreeChild dataValue->messageLabel
        confirmdialog_FreeChild dataValue->windowWidget
        Delete dataValue
    End If
    Delete root
End Sub

' -------------------------------------------------------------------------
' Dialog callbacks and factories
' -------------------------------------------------------------------------

Private Sub confirmdialog_Destroy(ByVal w As Widget Ptr)
    If w->data <> 0 Then Delete Cast(ConfirmDialogData Ptr, w->data)
End Sub


Private Function confirmdialog_GetRoot(ByVal w As Widget Ptr) As Widget Ptr

    Dim As Widget Ptr current = w

    While current <> 0
        If current->parent = 0 Then Return current
        current = current->parent
    Wend

    Return 0

End Function


Private Sub confirmdialog_OnChoice(ByVal w As Widget Ptr)

    Dim As Widget Ptr root = confirmdialog_GetRoot(w)

    If root <> 0 Then
        Dim As ConfirmDialogData Ptr dialogData = _
            Cast(ConfirmDialogData Ptr, root->data)

        For choiceIndex As Integer = 0 To dialogData->actionCount - 1
            If dialogData->actionButtons(choiceIndex) = w Then
                dialogData->finished = dialogData->actionResults(choiceIndex)
                Exit For
            End If
        Next choiceIndex
    End If

End Sub


Private Sub confirmdialog_OnCancel(ByVal w As Widget Ptr)

    Dim As Widget Ptr root = confirmdialog_GetRoot(w)

    If root <> 0 Then
        Cast(ConfirmDialogData Ptr, root->data)->finished = _
            Cast(ConfirmDialogData Ptr, root->data)->closeResult
    End If

End Sub


Private Function confirmdialog_CreateConfigured( _
    ByVal nm As String, _
    ByVal title As String, _
    ByVal message As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal firstText As String, _
    ByVal firstResult As Integer, _
    ByVal secondText As String, _
    ByVal secondResult As Integer, _
    ByVal thirdText As String, _
    ByVal thirdResult As Integer, _
    ByVal closeResult As Integer, _
    ByVal legacyNames As Integer, _
    ByVal options As Const ConfirmDialogOptions Ptr = 0 _
) As Widget Ptr

    Const CONFIRM_DIALOG_WIDTH = 400
    Const CONFIRM_DIALOG_HEIGHT = 150
    Const CONFIRM_DIALOG_BUTTON_WIDTH = 88
    Const CONFIRM_DIALOG_BUTTON_HEIGHT = 28
    Const CONFIRM_DIALOG_BUTTON_GAP = 8

    Dim As Widget Ptr root = New Widget
    Dim As ConfirmDialogData Ptr dialogData = New ConfirmDialogData
    If root = 0 OrElse dialogData = 0 Then
        Delete root
        Delete dialogData
        Return 0
    End If
    root->data = dialogData
    Dim As String actionText(0 To 2)
    Dim As Integer actionResult(0 To 2)
    Dim As Integer buttonSpan
    Dim As Integer buttonX

    firstText = Trim(firstText)
    secondText = Trim(secondText)
    thirdText = Trim(thirdText)
    If firstText = "" OrElse firstResult = 0 Then
        Delete dialogData
        Delete root
        Return 0
    End If
    actionText(0) = firstText
    actionResult(0) = firstResult
    dialogData->actionCount = 1
    If secondText <> "" AndAlso secondResult <> 0 Then
        actionText(dialogData->actionCount) = secondText
        actionResult(dialogData->actionCount) = secondResult
        dialogData->actionCount += 1
    End If
    If thirdText <> "" AndAlso thirdResult <> 0 Then
        actionText(dialogData->actionCount) = thirdText
        actionResult(dialogData->actionCount) = thirdResult
        dialogData->actionCount += 1
    End If
    If closeResult = 0 Then closeResult = actionResult(dialogData->actionCount - 1)

    Dim As Integer dialogWidth = CONFIRM_DIALOG_WIDTH
    Dim As Integer dialogHeight = CONFIRM_DIALOG_HEIGHT
    Dim As Integer defaultChoice
    Dim As Integer messageX = 16
    Dim As ConfirmDialogOptions optionValue
    If options <> 0 Then
        optionValue = *options
        If optionValue.width < 320 OrElse optionValue.width > 4096 OrElse _
           optionValue.maximum_height < 150 OrElse optionValue.maximum_height > 4096 OrElse _
           optionValue.icon_kind < CONFIRM_ICON_NONE OrElse optionValue.icon_kind > CONFIRM_ICON_INFORMATION OrElse _
           optionValue.default_choice < 0 OrElse optionValue.default_choice >= dialogData->actionCount OrElse _
           Len(message) > 16384 OrElse x < -1000000 OrElse x > 1000000 OrElse y < -1000000 OrElse y > 1000000 Then
            confirmdialog_FreeUnregistered root
            Return 0
        End If
        dialogWidth = optionValue.width
        defaultChoice = optionValue.default_choice
        If optionValue.icon_kind <> CONFIRM_ICON_NONE Then messageX = 60
    End If

    root->name = nm
    root->x = x
    root->y = y
    root->w = 0
    root->h = 0
    root->visible = 1
    root->enabled = 1
    root->ax = x
    root->ay = y
    root->evis = 1
    root->een = 1
    root->parent = 0
    root->next_widget = 0
    root->update = 0
    root->render = 0
    root->destroy = @confirmdialog_Destroy
    root->updated_this_frame = 0
    root->data = dialogData

    dialogData->finished = 0
    dialogData->closeResult = closeResult
    dialogData->windowWidget = subwindow_Create(nm & "_window", title, 0, 0, dialogWidth, dialogHeight)
    If dialogData->windowWidget <> 0 Then _
        subwindow_SetMoveParent dialogData->windowWidget, -1
    dialogData->messageLabel = label_Create(nm & "_message", message, messageX, 38)
    If dialogData->windowWidget = 0 OrElse dialogData->messageLabel = 0 Then
        confirmdialog_FreeUnregistered root
        Return 0
    End If
    If options <> 0 Then
        ' Message dialogs keep their measured layout and remain reachable
        ' until answered. General subwindow minimize/maximize actions do not
        ' belong on this modal surface; legacy factories retain their setup.
        subwindow_SetMinButton dialogData->windowWidget, 0
        subwindow_SetMaxButton dialogData->windowWidget, 0
        subwindow_SetBorderStyle dialogData->windowWidget, SUBWINDOW_BORDER_FIXED_SINGLE
        label_SetWordWrap dialogData->messageLabel, dialogWidth - messageX - 16, 0
        Dim As Integer lineCount = label_GetRenderedLineCount(dialogData->messageLabel)
        ' Wrapped labels separate lines by two pixels. Reject the label's
        ' capacity boundary as well, since that boundary can hide an ellipsis.
        Dim As Integer messageHeight = lineCount * (backend_GetTextHeight() + 2)
        If messageHeight < 32 Then messageHeight = 32
        dialogHeight = 38 + messageHeight + 16 + CONFIRM_DIALOG_BUTTON_HEIGHT + 18
        If dialogHeight < CONFIRM_DIALOG_HEIGHT Then dialogHeight = CONFIRM_DIALOG_HEIGHT
        If lineCount >= LABEL_MAXIMUM_WRAPPED_LINES OrElse dialogHeight > optionValue.maximum_height Then
            confirmdialog_FreeUnregistered root
            Return 0
        End If
        dialogData->windowWidget->h = dialogHeight
        dialogData->messageLabel->h = messageHeight
        If optionValue.icon_kind <> CONFIRM_ICON_NONE Then
            dialogData->iconWidget = New Widget
            If dialogData->iconWidget = 0 Then
                confirmdialog_FreeUnregistered root
                Return 0
            End If
            With *dialogData->iconWidget
                .data = New ConfirmDialogIconData
                .destroy = @confirmdialog_DestroyIcon
                .render = @confirmdialog_RenderIcon
                .name = nm & "_icon"
                .x = 16: .y = 38: .w = 32: .h = 32
                .visible = -1: .enabled = -1
            End With
            If dialogData->iconWidget->data = 0 Then
                confirmdialog_FreeUnregistered root
                Return 0
            End If
            Cast(ConfirmDialogIconData Ptr, dialogData->iconWidget->data)->icon_kind = optionValue.icon_kind
        End If
    End If
    subwindow_SetCloseHandler _
        dialogData->windowWidget, @confirmdialog_OnCancel
    buttonSpan = dialogData->actionCount * CONFIRM_DIALOG_BUTTON_WIDTH + _
        (dialogData->actionCount - 1) * CONFIRM_DIALOG_BUTTON_GAP
    buttonX = (dialogWidth - buttonSpan) \ 2
    If legacyNames Then
        ' The original two-choice factory placed actions against the right
        ' edge. Keep that layout for callers using its established API.
        buttonX = dialogWidth - buttonSpan - 16
    End If
    For choiceIndex As Integer = 0 To dialogData->actionCount - 1
        Dim As String buttonName
        If legacyNames Then
            buttonName = nm & IIf(choiceIndex = 0, "_confirm", "_cancel")
        Else
            buttonName = nm & "_choice_" & LTrim(Str(choiceIndex))
        End If
        dialogData->actionResults(choiceIndex) = actionResult(choiceIndex)
        dialogData->actionButtons(choiceIndex) = button_Create( _
            buttonName, actionText(choiceIndex), _
            buttonX + choiceIndex * (CONFIRM_DIALOG_BUTTON_WIDTH + CONFIRM_DIALOG_BUTTON_GAP), _
            dialogHeight - 46, CONFIRM_DIALOG_BUTTON_WIDTH, CONFIRM_DIALOG_BUTTON_HEIGHT, _
            @confirmdialog_OnChoice _
        )
        If dialogData->actionButtons(choiceIndex) = 0 Then
            confirmdialog_FreeUnregistered root
            Return 0
        End If
    Next choiceIndex
    ' Publish only once every allocation and layout check has succeeded.
    gui_AddGeneratedWidget dialogData->windowWidget
    gui_AddGeneratedWidget dialogData->messageLabel
    gui_SetParent dialogData->windowWidget, root
    gui_SetParent dialogData->messageLabel, dialogData->windowWidget
    If dialogData->iconWidget <> 0 Then
        gui_AddGeneratedWidget dialogData->iconWidget
        gui_SetParent dialogData->iconWidget, dialogData->windowWidget
    End If
    For choiceIndex As Integer = 0 To dialogData->actionCount - 1
        gui_AddGeneratedWidget dialogData->actionButtons(choiceIndex)
        gui_SetParent dialogData->actionButtons(choiceIndex), dialogData->windowWidget
    Next choiceIndex
    ' Enter activates the first choice in either factory. The legacy factory
    ' keeps the original plain border while retaining that keyboard action.
    gui_SetDefaultAction dialogData->actionButtons(defaultChoice), -1
    If legacyNames Then _
        button_SetDefaultOutline dialogData->actionButtons(defaultChoice), 0
    For choiceIndex As Integer = 0 To dialogData->actionCount - 1
        If dialogData->actionResults(choiceIndex) = closeResult Then _
            gui_SetCancelAction dialogData->actionButtons(choiceIndex), -1
    Next choiceIndex
    ' The modal stack accepts only registered roots.
    gui_AddWidget root
    If gui_TrySetModalRoot(root) = 0 Then
        gui_RemoveWidgetPtr root
        Return 0
    End If
    If options <> 0 Then gui_SetFocus dialogData->actionButtons(defaultChoice)

    Return root

End Function


Function confirmdialog_Create( _
    ByVal nm As String, _
    ByVal title As String, _
    ByVal message As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal confirmText As String _
) As Widget Ptr

    confirmText = Trim(confirmText)
    If confirmText = "" Then confirmText = "Discard"
    Return confirmdialog_CreateConfigured( _
        nm, title, message, x, y, confirmText, 1, "Cancel", -1, "", 0, -1, -1 _
    )

End Function


Function confirmdialog_CreateChoices( _
    ByVal nm As String, _
    ByVal title As String, _
    ByVal message As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal firstText As String, _
    ByVal firstResult As Integer, _
    ByVal secondText As String, _
    ByVal secondResult As Integer, _
    ByVal thirdText As String, _
    ByVal thirdResult As Integer, _
    ByVal closeResult As Integer _
) As Widget Ptr

    Return confirmdialog_CreateConfigured( _
        nm, title, message, x, y, firstText, firstResult, _
        secondText, secondResult, thirdText, thirdResult, closeResult, 0 _
    )

End Function


Function confirmdialog_GetResultState(ByVal w As Widget Ptr) As Integer

    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @confirmdialog_Destroy Then Return 0
    Return Cast(ConfirmDialogData Ptr, w->data)->finished

End Function

Sub confirmdialog_SetDialogStyle(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @confirmdialog_Destroy Then Exit Sub
    Dim As Widget Ptr windowWidget = Cast(ConfirmDialogData Ptr, w->data)->windowWidget
    If windowWidget <> 0 Then subwindow_SetDialogStyle windowWidget
End Sub

Function confirmdialog_CreateChoicesEx( _
    ByVal nm As String, ByVal title As String, ByVal message As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByRef options As Const ConfirmDialogOptions, _
    ByVal firstText As String, ByVal firstResult As Integer, _
    ByVal secondText As String, ByVal secondResult As Integer, _
    ByVal thirdText As String, ByVal thirdResult As Integer, _
    ByVal closeResult As Integer _
) As Widget Ptr
    Return confirmdialog_CreateConfigured(nm, title, message, x, y, _
        firstText, firstResult, secondText, secondResult, thirdText, thirdResult, closeResult, 0, @options)
End Function

Function confirmdialog_GetActionButton( _
    ByVal w As Widget Ptr, ByVal choiceIndex As Integer _
) As Widget Ptr
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @confirmdialog_Destroy Then Return 0
    Dim As ConfirmDialogData Ptr dialogData = Cast(ConfirmDialogData Ptr, w->data)
    If choiceIndex < 0 OrElse choiceIndex >= dialogData->actionCount Then Return 0
    Return dialogData->actionButtons(choiceIndex)
End Function

Function confirmdialog_GetWindow(ByVal w As Widget Ptr) As Widget Ptr
    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @confirmdialog_Destroy Then Return 0
    Return Cast(ConfirmDialogData Ptr, w->data)->windowWidget
End Function

Function confirmdialog_GetMessageLabel(ByVal w As Widget Ptr) As Widget Ptr
    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @confirmdialog_Destroy Then Return 0
    Return Cast(ConfirmDialogData Ptr, w->data)->messageLabel
End Function

' end of confirmdialog.bas
