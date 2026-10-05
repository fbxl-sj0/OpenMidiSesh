/'
    Project: omaGUI
    ---------------

    File: toolbar.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements toolbar.bi; declarations there define the interface.

    Purpose:

        Implement a portable classic command toolbar.

    Responsibilities:

        - calculate stable command and separator rectangles
        - render normal, hot, pressed, and disabled command states
        - route one release-inside pointer activation to a shared callback
        - own and release one ToolBarData record

    This file intentionally does NOT contain:

        - application-specific commands
        - keyboard-shortcut policy
        - operating-system toolbar handles

    Ownership:

        - each widget owns one ToolBarData allocation and its label strings
'/

#lang "fb"

#include once "src/widgets/toolbar.bi"
#include once "src/backend/theme.bi"

Const TOOLBAR_MINIMUM_WIDTH As Integer = 40
Const TOOLBAR_MINIMUM_HEIGHT As Integer = 24
Const TOOLBAR_MAXIMUM_HEIGHT As Integer = 48
Const TOOLBAR_MINIMUM_BUTTON_WIDTH As Integer = 28
Const TOOLBAR_MAXIMUM_BUTTON_WIDTH As Integer = 256
Const TOOLBAR_BUTTON_PADDING As Integer = 20
Const TOOLBAR_OUTER_PADDING As Integer = 4
Const TOOLBAR_SEPARATOR_WIDTH As Integer = 9
Const TOOLBAR_ITEM_GAP As Integer = 2

' -------------------------------------------------------------------------
' Checked item access and geometry
' -------------------------------------------------------------------------

Private Function toolbar_ItemIsButton( _
    ByVal bar_data As ToolBarData Ptr, _
    ByVal item_index As Integer _
) As Integer
    If bar_data = 0 Then Return 0
    If item_index < 0 OrElse item_index >= bar_data->item_count Then Return 0
    Return IIf(bar_data->item_kind(item_index) = TOOLBAR_ITEM_BUTTON, -1, 0)
End Function


Private Function toolbar_NextItemLeft( _
    ByVal bar_data As ToolBarData Ptr _
) As Integer
    Dim As Integer last_index

    If bar_data = 0 OrElse bar_data->item_count < 1 Then _
        Return TOOLBAR_OUTER_PADDING
    last_index = bar_data->item_count - 1
    Return bar_data->item_left(last_index) + _
        bar_data->item_width(last_index) + TOOLBAR_ITEM_GAP
End Function


Private Function toolbar_PointerItem( _
    ByVal bar_widget As Widget Ptr, _
    ByVal bar_data As ToolBarData Ptr, _
    ByVal pointer_x As Integer, _
    ByVal pointer_y As Integer _
) As Integer
    Dim As Integer item_index
    Dim As Integer item_left

    If bar_widget = 0 OrElse bar_data = 0 Then Return -1
    If pointer_x < bar_widget->ax OrElse _
       pointer_x >= bar_widget->ax + bar_widget->w OrElse _
       pointer_y < bar_widget->ay OrElse _
       pointer_y >= bar_widget->ay + bar_widget->h Then Return -1

    For item_index = 0 To bar_data->item_count - 1
        If toolbar_ItemIsButton(bar_data, item_index) = 0 Then Continue For
        item_left = bar_widget->ax + bar_data->item_left(item_index)
        If pointer_x >= item_left AndAlso _
           pointer_x < item_left + bar_data->item_width(item_index) Then
            Return item_index
        End If
    Next item_index
    Return -1
End Function

' -------------------------------------------------------------------------
' Construction and public metadata API
' -------------------------------------------------------------------------

Function toolbar_Create( _
    ByVal widget_name As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal bar_width As Integer, _
    ByVal bar_height As Integer _
) As Widget Ptr
    Dim As ToolBarData Ptr bar_data
    Dim As Widget Ptr bar_widget

    If Len(widget_name) < 1 OrElse _
       Len(widget_name) > TOOLBAR_MAX_TEXT_BYTES Then Return 0
    If bar_width < TOOLBAR_MINIMUM_WIDTH Then bar_width = TOOLBAR_MINIMUM_WIDTH
    If bar_height < TOOLBAR_MINIMUM_HEIGHT Then _
        bar_height = TOOLBAR_MINIMUM_HEIGHT
    If bar_height > TOOLBAR_MAXIMUM_HEIGHT Then _
        bar_height = TOOLBAR_MAXIMUM_HEIGHT

    bar_widget = New Widget
    If bar_widget = 0 Then Return 0
    bar_data = New ToolBarData
    If bar_data = 0 Then
        Delete bar_widget
        Return 0
    End If

    bar_widget->name = widget_name
    bar_widget->x = left_position
    bar_widget->y = top_position
    bar_widget->w = bar_width
    bar_widget->h = bar_height
    bar_widget->visible = -1
    bar_widget->enabled = -1
    bar_widget->accepts_focus = 0
    bar_widget->update = @toolbar_Update
    bar_widget->render = @toolbar_Render
    bar_widget->destroy = @toolbar_Destroy
    bar_widget->data = bar_data
    bar_data->hot_item = -1
    bar_data->pressed_item = -1
    Return bar_widget
End Function


Function toolbar_AddButton( _
    ByVal bar_widget As Widget Ptr, _
    ByVal button_text As String, _
    ByVal button_width As Integer _
) As Integer
    Dim As ToolBarData Ptr bar_data
    Dim As Integer item_index

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return -1
    If Len(button_text) < 1 OrElse _
       Len(button_text) > TOOLBAR_MAX_TEXT_BYTES Then Return -1
    If button_width < 0 OrElse _
       button_width > TOOLBAR_MAXIMUM_BUTTON_WIDTH Then Return -1
    bar_data = Cast(ToolBarData Ptr, bar_widget->data)
    If bar_data->item_count >= TOOLBAR_MAX_ITEMS Then Return -1

    If button_width = 0 Then
        button_width = backend_GetTextWidth(button_text) + TOOLBAR_BUTTON_PADDING
    End If
    If button_width < TOOLBAR_MINIMUM_BUTTON_WIDTH Then _
        button_width = TOOLBAR_MINIMUM_BUTTON_WIDTH

    item_index = bar_data->item_count
    bar_data->item_text(item_index) = button_text
    bar_data->item_kind(item_index) = TOOLBAR_ITEM_BUTTON
    bar_data->item_left(item_index) = toolbar_NextItemLeft(bar_data)
    bar_data->item_width(item_index) = button_width
    bar_data->item_enabled(item_index) = -1
    bar_data->item_count += 1
    Return item_index
End Function


Function toolbar_AddSeparator( _
    ByVal bar_widget As Widget Ptr _
) As Integer
    Dim As ToolBarData Ptr bar_data
    Dim As Integer item_index

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return -1
    bar_data = Cast(ToolBarData Ptr, bar_widget->data)
    If bar_data->item_count >= TOOLBAR_MAX_ITEMS Then Return -1

    item_index = bar_data->item_count
    bar_data->item_kind(item_index) = TOOLBAR_ITEM_SEPARATOR
    bar_data->item_left(item_index) = toolbar_NextItemLeft(bar_data)
    bar_data->item_width(item_index) = TOOLBAR_SEPARATOR_WIDTH
    bar_data->item_count += 1
    Return item_index
End Function


Sub toolbar_SetSelectionHandler( _
    ByVal bar_widget As Widget Ptr, _
    ByVal selection_handler As Any Ptr, _
    ByVal selection_context As Any Ptr _
)
    Dim As ToolBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Exit Sub
    bar_data = Cast(ToolBarData Ptr, bar_widget->data)
    bar_data->selection_handler = selection_handler
    bar_data->selection_context = selection_context
End Sub


Function toolbar_SetItemEnabled( _
    ByVal bar_widget As Widget Ptr, _
    ByVal item_index As Integer, _
    ByVal enabled_value As Integer _
) As Integer
    Dim As ToolBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    bar_data = Cast(ToolBarData Ptr, bar_widget->data)
    If toolbar_ItemIsButton(bar_data, item_index) = 0 Then Return 0
    bar_data->item_enabled(item_index) = IIf(enabled_value <> 0, -1, 0)
    If enabled_value = 0 Then
        If bar_data->hot_item = item_index Then bar_data->hot_item = -1
        If bar_data->pressed_item = item_index Then bar_data->pressed_item = -1
    End If
    Return -1
End Function


Function toolbar_GetItemEnabled( _
    ByVal bar_widget As Widget Ptr, _
    ByVal item_index As Integer _
) As Integer
    Dim As ToolBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    bar_data = Cast(ToolBarData Ptr, bar_widget->data)
    If toolbar_ItemIsButton(bar_data, item_index) = 0 Then Return 0
    Return bar_data->item_enabled(item_index)
End Function


Function toolbar_GetItemCount( _
    ByVal bar_widget As Widget Ptr _
) As Integer
    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    Return Cast(ToolBarData Ptr, bar_widget->data)->item_count
End Function


Function toolbar_GetItemLabel( _
    ByVal bar_widget As Widget Ptr, _
    ByVal item_index As Integer _
) As String
    Dim As ToolBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return ""
    bar_data = Cast(ToolBarData Ptr, bar_widget->data)
    If toolbar_ItemIsButton(bar_data, item_index) = 0 Then Return ""
    Return bar_data->item_text(item_index)
End Function

' -------------------------------------------------------------------------
' Input and activation
' -------------------------------------------------------------------------

Function toolbar_ActivateItem( _
    ByVal bar_widget As Widget Ptr, _
    ByVal item_index As Integer _
) As Integer
    Dim As ToolBarData Ptr bar_data
    Dim As Any Ptr callback_context
    Dim As Any Ptr callback_handler

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    bar_data = Cast(ToolBarData Ptr, bar_widget->data)
    If toolbar_ItemIsButton(bar_data, item_index) = 0 OrElse _
       bar_data->item_enabled(item_index) = 0 Then Return 0

    /'
        Copy callback state before dispatch because application code may
        remove the toolbar or rebuild its complete owning screen.
    '/
    callback_handler = bar_data->selection_handler
    callback_context = bar_data->selection_context
    If callback_handler <> 0 Then
        Cast( _
            Sub(ByVal As Any Ptr, ByVal As Integer), callback_handler _
        )(callback_context, item_index)
    End If
    Return -1
End Function


Sub toolbar_Update(ByVal bar_widget As Widget Ptr)
    Dim As ToolBarData Ptr bar_data
    Dim As Integer activation_item
    Dim As Integer pointer_buttons
    Dim As Integer pointer_item

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Exit Sub
    bar_data = Cast(ToolBarData Ptr, bar_widget->data)
    pointer_buttons = input_MouseButtons()
    pointer_item = toolbar_PointerItem( _
        bar_widget, bar_data, input_MouseX(), input_MouseY() _
    )
    If pointer_item >= 0 AndAlso _
       bar_data->item_enabled(pointer_item) = 0 Then pointer_item = -1
    bar_data->hot_item = pointer_item

    If (pointer_buttons And 1) <> 0 Then
        If bar_data->pointer_latch = 0 Then
            bar_data->pointer_latch = -1
            bar_data->pressed_item = pointer_item
        End If
        Exit Sub
    End If

    If bar_data->pointer_latch = 0 Then Exit Sub
    activation_item = -1
    If pointer_item >= 0 AndAlso pointer_item = bar_data->pressed_item Then _
        activation_item = pointer_item
    bar_data->pointer_latch = 0
    bar_data->pressed_item = -1
    If activation_item >= 0 Then _
        toolbar_ActivateItem bar_widget, activation_item
End Sub

' -------------------------------------------------------------------------
' Rendering and lifecycle
' -------------------------------------------------------------------------

Private Sub toolbar_RenderButton( _
    ByVal bar_widget As Widget Ptr, _
    ByVal bar_data As ToolBarData Ptr, _
    ByVal item_index As Integer, _
    ByVal item_left As Integer, _
    ByVal draw_width As Integer _
)
    Dim As Integer is_pressed
    Dim As ULong dark_color
    Dim As ULong light_color
    Dim As ULong text_color

    If draw_width < 2 Then Exit Sub
    dark_color = current_theme.bg_dark
    light_color = current_theme.bg_light
    is_pressed = IIf( _
        bar_data->pointer_latch <> 0 AndAlso _
        bar_data->pressed_item = item_index AndAlso _
        bar_data->hot_item = item_index, -1, 0 _
    )
    If is_pressed Then Swap dark_color, light_color

    If item_index = bar_data->hot_item OrElse is_pressed Then
        backend_Rect _
            item_left, bar_widget->ay + 3, draw_width, bar_widget->h - 6, _
            current_theme.bg_face, -1
        backend_Line _
            item_left, bar_widget->ay + 3, _
            item_left + draw_width - 1, bar_widget->ay + 3, light_color
        backend_Line _
            item_left, bar_widget->ay + 3, _
            item_left, bar_widget->ay + bar_widget->h - 4, light_color
        backend_Line _
            item_left, bar_widget->ay + bar_widget->h - 4, _
            item_left + draw_width - 1, _
            bar_widget->ay + bar_widget->h - 4, dark_color
        backend_Line _
            item_left + draw_width - 1, bar_widget->ay + 3, _
            item_left + draw_width - 1, _
            bar_widget->ay + bar_widget->h - 4, dark_color
    End If

    If bar_data->item_enabled(item_index) Then
        text_color = theme_GetClassicColor( _
            GUI_CLASSIC_COLOR_COMMAND_TEXT _
        )
    Else
        text_color = theme_GetClassicColor( _
            GUI_CLASSIC_COLOR_DISABLED_TEXT _
        )
    End If
    If draw_width > 8 Then
        backend_PrintAligned _
            item_left + 4, bar_widget->ay + 2 + Abs(is_pressed), _
            draw_width - 8, bar_widget->h - 4, text_color, _
            bar_data->item_text(item_index), BACKEND_FONT_DEFAULT, _
            BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE
    End If
End Sub


Sub toolbar_Render(ByVal bar_widget As Widget Ptr)
    Dim As ToolBarData Ptr bar_data
    Dim As Integer available_width
    Dim As Integer draw_width
    Dim As Integer item_index
    Dim As Integer item_left
    Dim As Integer separator_x

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Exit Sub
    bar_data = Cast(ToolBarData Ptr, bar_widget->data)
    backend_Rect _
        bar_widget->ax, bar_widget->ay, bar_widget->w, bar_widget->h, _
        current_theme.bg_face, -1
    backend_Line _
        bar_widget->ax, bar_widget->ay + bar_widget->h - 1, _
        bar_widget->ax + bar_widget->w - 1, _
        bar_widget->ay + bar_widget->h - 1, current_theme.bg_dark

    For item_index = 0 To bar_data->item_count - 1
        item_left = bar_widget->ax + bar_data->item_left(item_index)
        available_width = bar_widget->ax + bar_widget->w - item_left
        If available_width < 1 Then Exit For
        draw_width = bar_data->item_width(item_index)
        If draw_width > available_width Then draw_width = available_width

        If bar_data->item_kind(item_index) = TOOLBAR_ITEM_SEPARATOR Then
            separator_x = item_left + draw_width \ 2
            backend_Line _
                separator_x, bar_widget->ay + 6, separator_x, _
                bar_widget->ay + bar_widget->h - 7, current_theme.bg_dark
            If separator_x + 1 < bar_widget->ax + bar_widget->w Then
                backend_Line _
                    separator_x + 1, bar_widget->ay + 6, separator_x + 1, _
                    bar_widget->ay + bar_widget->h - 7, current_theme.bg_light
            End If
        Else
            toolbar_RenderButton _
                bar_widget, bar_data, item_index, item_left, draw_width
        End If
    Next item_index
End Sub


Sub toolbar_Destroy(ByVal bar_widget As Widget Ptr)
    If bar_widget = 0 Then Exit Sub
    If bar_widget->data <> 0 Then _
        Delete Cast(ToolBarData Ptr, bar_widget->data)
    bar_widget->data = 0
End Sub

/' end of toolbar.bas '/
