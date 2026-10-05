/'
    Project: omaGUI
    ---------------

    File: colordialog.bas

    Purpose:

        Implement a modal classic-palette color chooser.

    Responsibilities:

        - display all sixteen colors with keyboard-focusable index buttons
        - retain selection until the caller explicitly accepts or cancels
        - constrain input to the generated modal widget tree
        - release dialog metadata without owning application state

    This file intentionally does NOT contain:

        - global theme changes
        - native platform dialogs
        - RGB or HSV component editors

    Ownership:

        - the root widget owns ColorDialogData
        - the GUI registry owns the generated window, labels, buttons, and
          swatches through their normal widget lifecycle
'/

#lang "fb"

#include once "src/widgets/colordialog.bi"
#include once "src/widgets/subwindow.bi"
#include once "src/widgets/button.bi"
#include once "src/widgets/label.bi"
#include once "src/widgets/rectwidget.bi"

Const COLORDIALOG_WIDTH As Integer = 486
Const COLORDIALOG_HEIGHT As Integer = 238
Const COLORDIALOG_TILE_SPACING As Integer = 56
Const COLORDIALOG_SWATCH_SIZE As Integer = 28
Const COLORDIALOG_BUTTON_SIZE As Integer = 26

Type ColorDialogData
    As Widget Ptr window_widget
    As Widget Ptr selection_label
    As Widget Ptr color_buttons(0 To COLORDIALOG_COLOR_COUNT - 1)
    As Integer selected_index
    As Integer finished
End Type

' -------------------------------------------------------------------------
' Palette and root helpers
' -------------------------------------------------------------------------

Function colordialog_GetClassicColor( _
    ByVal color_index As Integer _
) As ULong
    Select Case color_index
    Case 0: Return RGB(0, 0, 0)
    Case 1: Return RGB(0, 0, 170)
    Case 2: Return RGB(0, 170, 0)
    Case 3: Return RGB(0, 170, 170)
    Case 4: Return RGB(170, 0, 0)
    Case 5: Return RGB(170, 0, 170)
    Case 6: Return RGB(170, 85, 0)
    Case 7: Return RGB(170, 170, 170)
    Case 8: Return RGB(85, 85, 85)
    Case 9: Return RGB(85, 85, 255)
    Case 10: Return RGB(85, 255, 85)
    Case 11: Return RGB(85, 255, 255)
    Case 12: Return RGB(255, 85, 85)
    Case 13: Return RGB(255, 85, 255)
    Case 14: Return RGB(255, 255, 85)
    Case 15: Return RGB(255, 255, 255)
    End Select
    Return RGB(0, 0, 0)
End Function


Private Function colordialog_GetRoot( _
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


Private Sub colordialog_RefreshSelection(ByVal root_widget As Widget Ptr)
    Dim As ButtonData Ptr button_data
    Dim As ColorDialogData Ptr dialog_data
    Dim As LabelData Ptr label_data
    Dim As Integer color_index
    Dim As String button_text

    If root_widget = 0 OrElse root_widget->data = 0 Then Exit Sub
    dialog_data = Cast(ColorDialogData Ptr, root_widget->data)
    For color_index = 0 To COLORDIALOG_COLOR_COUNT - 1
        If dialog_data->color_buttons(color_index) <> 0 AndAlso _
           dialog_data->color_buttons(color_index)->data <> 0 Then
            button_data = Cast( _
                ButtonData Ptr, dialog_data->color_buttons(color_index)->data _
            )
            button_text = LTrim(Str(color_index))
            If color_index = dialog_data->selected_index Then _
                button_text = "[" & button_text & "]"
            button_data->text = button_text
        End If
    Next color_index

    If dialog_data->selection_label <> 0 AndAlso _
       dialog_data->selection_label->data <> 0 Then
        label_data = Cast(LabelData Ptr, dialog_data->selection_label->data)
        label_data->text = "Selected BASIC color: " & _
            LTrim(Str(dialog_data->selected_index))
    End If
End Sub

' -------------------------------------------------------------------------
' Generated control callbacks
' -------------------------------------------------------------------------

Private Sub colordialog_OnColor(ByVal button_widget As Widget Ptr)
    Dim As Widget Ptr root_widget
    Dim As ColorDialogData Ptr dialog_data
    Dim As Integer color_index
    Dim As Integer separator_position

    root_widget = colordialog_GetRoot(button_widget)
    If root_widget = 0 OrElse root_widget->data = 0 Then Exit Sub
    dialog_data = Cast(ColorDialogData Ptr, root_widget->data)
    separator_position = InStrRev(button_widget->name, "_")
    If separator_position < 1 Then Exit Sub
    color_index = ValInt(Mid(button_widget->name, separator_position + 1))
    If color_index < 0 OrElse color_index >= COLORDIALOG_COLOR_COUNT Then _
        Exit Sub
    dialog_data->selected_index = color_index
    colordialog_RefreshSelection root_widget
End Sub


Private Sub colordialog_OnAccept(ByVal button_widget As Widget Ptr)
    Dim As Widget Ptr root_widget

    root_widget = colordialog_GetRoot(button_widget)
    If root_widget = 0 OrElse root_widget->data = 0 Then Exit Sub
    Cast(ColorDialogData Ptr, root_widget->data)->finished = 1
End Sub


Private Sub colordialog_OnCancel(ByVal button_widget As Widget Ptr)
    Dim As Widget Ptr root_widget

    root_widget = colordialog_GetRoot(button_widget)
    If root_widget = 0 OrElse root_widget->data = 0 Then Exit Sub
    Cast(ColorDialogData Ptr, root_widget->data)->finished = -1
End Sub


Private Sub colordialog_Destroy(ByVal root_widget As Widget Ptr)
    If root_widget = 0 OrElse root_widget->data = 0 Then Exit Sub
    Delete Cast(ColorDialogData Ptr, root_widget->data)
    root_widget->data = 0
End Sub

' -------------------------------------------------------------------------
' Public dialog lifecycle
' -------------------------------------------------------------------------

Function colordialog_Create( _
    ByVal widget_name As String, _
    ByVal title_text As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal initial_color_index As Integer _
) As Widget Ptr
    Dim As ColorDialogData Ptr dialog_data
    Dim As Widget Ptr accept_button
    Dim As Widget Ptr cancel_button
    Dim As Widget Ptr root_widget
    Dim As Widget Ptr swatch_widget
    Dim As Integer color_index
    Dim As Integer column_index
    Dim As Integer row_index
    Dim As Integer tile_left
    Dim As Integer tile_top

    If initial_color_index < 0 OrElse _
       initial_color_index >= COLORDIALOG_COLOR_COUNT Then _
        initial_color_index = 0
    title_text = Trim(title_text)
    If Len(title_text) = 0 Then title_text = "Color Palette"

    root_widget = New Widget
    dialog_data = New ColorDialogData
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
    root_widget->destroy = @colordialog_Destroy
    root_widget->data = dialog_data
    dialog_data->selected_index = initial_color_index
    dialog_data->window_widget = subwindow_Create( _
        widget_name & "_window", title_text, 0, 0, _
        COLORDIALOG_WIDTH, COLORDIALOG_HEIGHT _
    )
    subwindow_SetCloseHandler _
        dialog_data->window_widget, @colordialog_OnCancel
    gui_AddGeneratedWidget dialog_data->window_widget
    gui_SetParent dialog_data->window_widget, root_widget

    For color_index = 0 To COLORDIALOG_COLOR_COUNT - 1
        row_index = color_index \ 8
        column_index = color_index Mod 8
        tile_left = 18 + column_index * COLORDIALOG_TILE_SPACING
        tile_top = 48 + row_index * 48
        swatch_widget = rectwidget_Create( _
            widget_name & "_swatch_" & Str(color_index), tile_left, tile_top, _
            COLORDIALOG_SWATCH_SIZE, COLORDIALOG_SWATCH_SIZE, _
            colordialog_GetClassicColor(color_index), -1 _
        )
        dialog_data->color_buttons(color_index) = button_Create( _
            widget_name & "_color_" & Str(color_index), _
            LTrim(Str(color_index)), tile_left + 29, tile_top - 1, _
            COLORDIALOG_BUTTON_SIZE, COLORDIALOG_SWATCH_SIZE + 2, _
            @colordialog_OnColor _
        )
        gui_AddGeneratedWidget swatch_widget
        gui_AddGeneratedWidget dialog_data->color_buttons(color_index)
        gui_SetParent swatch_widget, dialog_data->window_widget
        gui_SetParent _
            dialog_data->color_buttons(color_index), dialog_data->window_widget
    Next color_index

    dialog_data->selection_label = label_Create( _
        widget_name & "_selection", "", 18, 154, RGB(0, 0, 0), _
        BACKEND_FONT_ARIAL_10_REGULAR _
    )
    accept_button = button_Create( _
        widget_name & "_accept", "OK", 284, 190, 84, 30, _
        @colordialog_OnAccept _
    )
    cancel_button = button_Create( _
        widget_name & "_cancel", "Cancel", 378, 190, 84, 30, _
        @colordialog_OnCancel _
    )
    gui_AddGeneratedWidget dialog_data->selection_label
    gui_AddGeneratedWidget accept_button
    gui_AddGeneratedWidget cancel_button
    gui_SetParent dialog_data->selection_label, dialog_data->window_widget
    gui_SetParent accept_button, dialog_data->window_widget
    gui_SetParent cancel_button, dialog_data->window_widget
    gui_SetModalRoot root_widget
    colordialog_RefreshSelection root_widget
    Return root_widget
End Function


Function colordialog_GetResultState( _
    ByVal dialog_widget As Widget Ptr _
) As Integer
    If dialog_widget = 0 OrElse dialog_widget->data = 0 Then Return 0
    Return Cast(ColorDialogData Ptr, dialog_widget->data)->finished
End Function


Function colordialog_GetSelectedIndex( _
    ByVal dialog_widget As Widget Ptr _
) As Integer
    If dialog_widget = 0 OrElse dialog_widget->data = 0 Then Return -1
    Return Cast(ColorDialogData Ptr, dialog_widget->data)->selected_index
End Function

/' end of colordialog.bas '/
