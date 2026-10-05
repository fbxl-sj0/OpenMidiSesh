/'
    Project: omaGUI
    ---------------

    File: inputdialog.bas

    Purpose:

        Implement a bounded modal prompt for text and boolean input.

    Responsibilities:

        - generate a modal window with up to two fields and two checkboxes
        - retain user values while the caller inspects the completed result
        - report accept and cancel without applying application policy
        - release dialog metadata through the normal widget lifecycle

    This file intentionally does NOT contain:

        - input meaning or validation
        - file, print, find, or replace operations
        - platform-native controls

    Ownership:

        - the root widget owns InputDialogData
        - generated child widgets are owned by the GUI registry
'/

#lang "fb"

#include once "src/widgets/inputdialog.bi"
#include once "src/widgets/subwindow.bi"
#include once "src/widgets/button.bi"
#include once "src/widgets/checkbox.bi"
#include once "src/widgets/label.bi"
#include once "src/widgets/textbox.bi"

Const INPUTDIALOG_WIDTH As Integer = 460
Const INPUTDIALOG_HEIGHT As Integer = 286
Const INPUTDIALOG_TEXT_WIDTH As Integer = 420
Const INPUTDIALOG_TEXT_HEIGHT As Integer = 30

Type InputDialogData
    As Widget Ptr window_widget
    As Widget Ptr fields(0 To INPUTDIALOG_FIELD_COUNT - 1)
    As Widget Ptr options(0 To INPUTDIALOG_OPTION_COUNT - 1)
    As Integer finished
End Type

' -------------------------------------------------------------------------
' Generated control callbacks
' -------------------------------------------------------------------------

Private Function inputdialog_GetRoot( _
    ByVal child_widget As Widget Ptr _
) As Widget Ptr
    Dim As Widget Ptr current_widget

    current_widget = child_widget
    While current_widget <> 0
        If current_widget->parent = 0 Then Return current_widget
        current_widget = current_widget->parent
    Wend
    Return 0
End Function


Private Sub inputdialog_OnAccept(ByVal button_widget As Widget Ptr)
    Dim As Widget Ptr root_widget

    root_widget = inputdialog_GetRoot(button_widget)
    If root_widget = 0 OrElse root_widget->data = 0 Then Exit Sub
    Cast(InputDialogData Ptr, root_widget->data)->finished = 1
End Sub


Private Sub inputdialog_OnCancel(ByVal button_widget As Widget Ptr)
    Dim As Widget Ptr root_widget

    root_widget = inputdialog_GetRoot(button_widget)
    If root_widget = 0 OrElse root_widget->data = 0 Then Exit Sub
    Cast(InputDialogData Ptr, root_widget->data)->finished = -1
End Sub


Private Sub inputdialog_Destroy(ByVal root_widget As Widget Ptr)
    If root_widget = 0 OrElse root_widget->data = 0 Then Exit Sub
    Delete Cast(InputDialogData Ptr, root_widget->data)
    root_widget->data = 0
End Sub

' -------------------------------------------------------------------------
' Construction
' -------------------------------------------------------------------------

Function inputdialog_Create( _
    ByVal widget_name As String, _
    ByVal title_text As String, _
    ByVal first_prompt As String, _
    ByVal first_value As String, _
    ByVal second_prompt As String, _
    ByVal second_value As String, _
    ByVal first_option As String, _
    ByVal first_option_checked As Integer, _
    ByVal second_option As String, _
    ByVal second_option_checked As Integer, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal accept_text As String _
) As Widget Ptr
    Dim As InputDialogData Ptr dialog_data
    Dim As Widget Ptr accept_button
    Dim As Widget Ptr cancel_button
    Dim As Widget Ptr prompt_label
    Dim As Widget Ptr root_widget
    Dim As Integer option_top

    first_prompt = Trim(first_prompt)
    If Len(first_prompt) = 0 Then Return 0
    title_text = Trim(title_text)
    If Len(title_text) = 0 Then title_text = "Input"
    accept_text = Trim(accept_text)
    If Len(accept_text) = 0 Then accept_text = "OK"

    root_widget = New Widget
    dialog_data = New InputDialogData
    If root_widget = 0 OrElse dialog_data = 0 Then
        If root_widget <> 0 Then Delete root_widget
        If dialog_data <> 0 Then Delete dialog_data
        Return 0
    End If
    root_widget->name = widget_name
    root_widget->x = left_position
    root_widget->y = top_position
    root_widget->visible = -1
    root_widget->enabled = -1
    root_widget->destroy = @inputdialog_Destroy
    root_widget->data = dialog_data

    dialog_data->window_widget = subwindow_Create( _
        widget_name & "_window", title_text, 0, 0, _
        INPUTDIALOG_WIDTH, INPUTDIALOG_HEIGHT _
    )
    subwindow_SetCloseHandler _
        dialog_data->window_widget, @inputdialog_OnCancel
    gui_AddGeneratedWidget dialog_data->window_widget
    gui_SetParent dialog_data->window_widget, root_widget

    prompt_label = label_Create( _
        widget_name & "_prompt_0", first_prompt, 20, 42, RGB(0, 0, 0), _
        BACKEND_FONT_ARIAL_10_REGULAR _
    )
    dialog_data->fields(0) = textbox_Create( _
        widget_name & "_field_0", first_value, 20, 64, _
        INPUTDIALOG_TEXT_WIDTH, INPUTDIALOG_TEXT_HEIGHT, _
        0, 0, TEXTBOX_SCROLLBAR_NONE _
    )
    gui_AddGeneratedWidget prompt_label
    gui_AddGeneratedWidget dialog_data->fields(0)
    gui_SetParent prompt_label, dialog_data->window_widget
    gui_SetParent dialog_data->fields(0), dialog_data->window_widget

    second_prompt = Trim(second_prompt)
    If Len(second_prompt) > 0 Then
        prompt_label = label_Create( _
            widget_name & "_prompt_1", second_prompt, 20, 104, _
            RGB(0, 0, 0), BACKEND_FONT_ARIAL_10_REGULAR _
        )
        dialog_data->fields(1) = textbox_Create( _
            widget_name & "_field_1", second_value, 20, 126, _
            INPUTDIALOG_TEXT_WIDTH, INPUTDIALOG_TEXT_HEIGHT, _
            0, 0, TEXTBOX_SCROLLBAR_NONE _
        )
        gui_AddGeneratedWidget prompt_label
        gui_AddGeneratedWidget dialog_data->fields(1)
        gui_SetParent prompt_label, dialog_data->window_widget
        gui_SetParent dialog_data->fields(1), dialog_data->window_widget
        option_top = 172
    Else
        option_top = 112
    End If

    first_option = Trim(first_option)
    If Len(first_option) > 0 Then
        dialog_data->options(0) = checkbox_Create( _
            widget_name & "_option_0", first_option, 20, option_top, _
            IIf(first_option_checked <> 0, -1, 0) _
        )
        gui_AddGeneratedWidget dialog_data->options(0)
        gui_SetParent dialog_data->options(0), dialog_data->window_widget
    End If
    second_option = Trim(second_option)
    If Len(second_option) > 0 Then
        dialog_data->options(1) = checkbox_Create( _
            widget_name & "_option_1", second_option, 230, option_top, _
            IIf(second_option_checked <> 0, -1, 0) _
        )
        gui_AddGeneratedWidget dialog_data->options(1)
        gui_SetParent dialog_data->options(1), dialog_data->window_widget
    End If

    accept_button = button_Create( _
        widget_name & "_accept", accept_text, 260, 238, 84, 30, _
        @inputdialog_OnAccept _
    )
    cancel_button = button_Create( _
        widget_name & "_cancel", "Cancel", 354, 238, 84, 30, _
        @inputdialog_OnCancel _
    )
    gui_AddGeneratedWidget accept_button
    gui_AddGeneratedWidget cancel_button
    gui_SetParent accept_button, dialog_data->window_widget
    gui_SetParent cancel_button, dialog_data->window_widget
    ' Escape is resolved by the GUI manager within this modal tree.
    gui_SetCancelAction cancel_button, -1
    gui_SetModalRoot root_widget
    gui_SetFocus dialog_data->fields(0)
    Return root_widget
End Function

' -------------------------------------------------------------------------
' Result access
' -------------------------------------------------------------------------

Function inputdialog_GetResultState( _
    ByVal dialog_widget As Widget Ptr _
) As Integer
    If dialog_widget = 0 OrElse dialog_widget->data = 0 Then Return 0
    Return Cast(InputDialogData Ptr, dialog_widget->data)->finished
End Function


Function inputdialog_GetText( _
    ByVal dialog_widget As Widget Ptr, _
    ByVal field_index As Integer _
) As String
    Dim As InputDialogData Ptr dialog_data
    Dim As TextBoxData Ptr text_data

    If dialog_widget = 0 OrElse dialog_widget->data = 0 OrElse _
       field_index < 0 OrElse field_index >= INPUTDIALOG_FIELD_COUNT Then _
        Return ""
    dialog_data = Cast(InputDialogData Ptr, dialog_widget->data)
    If dialog_data->fields(field_index) = 0 OrElse _
       dialog_data->fields(field_index)->data = 0 Then Return ""
    text_data = Cast(TextBoxData Ptr, dialog_data->fields(field_index)->data)
    Return text_data->text
End Function


Function inputdialog_GetOption( _
    ByVal dialog_widget As Widget Ptr, _
    ByVal option_index As Integer _
) As Integer
    Dim As CheckBoxData Ptr checkbox_data
    Dim As InputDialogData Ptr dialog_data

    If dialog_widget = 0 OrElse dialog_widget->data = 0 OrElse _
       option_index < 0 OrElse option_index >= INPUTDIALOG_OPTION_COUNT Then _
        Return 0
    dialog_data = Cast(InputDialogData Ptr, dialog_widget->data)
    If dialog_data->options(option_index) = 0 OrElse _
       dialog_data->options(option_index)->data = 0 Then Return 0
    checkbox_data = Cast(CheckBoxData Ptr, dialog_data->options(option_index)->data)
    Return IIf(checkbox_data->checked <> 0, -1, 0)
End Function

/' end of inputdialog.bas '/
