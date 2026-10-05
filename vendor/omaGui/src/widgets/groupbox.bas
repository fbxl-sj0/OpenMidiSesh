/'
    Project: omaGUI
    ---------------

    File: groupbox.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements groupbox.bi; declarations there define the interface.

    Purpose:

        Render a portable classic group frame with an optional caption.

    Responsibilities:

        - draw a theme-colored background and inset frame
        - honor optional caller-supplied background and caption colors
        - reserve a clean gap in the upper border for caption text
        - own and release the small caption data record

    This file intentionally does NOT contain:

        - input handling
        - child positioning or clipping
        - application-specific frame behavior
'/

#lang "fb"

#include once "src/widgets/groupbox.bi"
#include once "src/backend/theme.bi"

Const GROUPBOX_MINIMUM_SIZE As Integer = 8
Const GROUPBOX_BORDER_TOP As Integer = 7
Const GROUPBOX_CAPTION_LEFT As Integer = 9
Const GROUPBOX_CAPTION_PADDING As Integer = 3

' -------------------------------------------------------------------------
' Rendering and lifecycle
' -------------------------------------------------------------------------

Sub groupbox_Render(ByVal w As Widget Ptr)
    Dim As GroupBoxData Ptr group_data
    Dim As Integer caption_width
    Dim As ULong background_color
    Dim As ULong foreground_color

    If w = 0 OrElse w->data = 0 Then Exit Sub
    group_data = Cast(GroupBoxData Ptr, w->data)
    background_color = theme_GetColor(GUI_COLOR_WIDGET_BG)
    foreground_color = theme_GetColor(GUI_COLOR_TEXT)
    If group_data->background_color_override <> 0 Then _
        background_color = group_data->background_color
    If group_data->foreground_color_override <> 0 Then _
        foreground_color = group_data->foreground_color

    backend_Rect w->ax, w->ay, w->w, w->h, background_color, -1
    backend_Rect w->ax, w->ay + GROUPBOX_BORDER_TOP, w->w, _
        w->h - GROUPBOX_BORDER_TOP, theme_GetColor(GUI_COLOR_BORDER), 0

    If Len(group_data->text) > 0 Then
        caption_width = backend_GetTextWidth(group_data->text)
        backend_Rect w->ax + GROUPBOX_CAPTION_LEFT - GROUPBOX_CAPTION_PADDING, _
            w->ay, caption_width + GROUPBOX_CAPTION_PADDING * 2, _
            backend_GetTextHeight(), background_color, -1
        backend_Print w->ax + GROUPBOX_CAPTION_LEFT, w->ay, _
            foreground_color, group_data->text
        gui_RenderMnemonicUnderline _
            w, group_data->text, w->ax + GROUPBOX_CAPTION_LEFT, w->ay, _
            backend_GetTextHeight()
    End If
End Sub


Sub groupbox_Destroy(ByVal w As Widget Ptr)
    If w = 0 Then Exit Sub
    If w->data <> 0 Then Delete Cast(GroupBoxData Ptr, w->data)
    w->data = 0
End Sub


Function groupbox_Create( _
    ByVal nm As String, ByVal txt As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer _
) As Widget Ptr
    Dim As GroupBoxData Ptr group_data
    Dim As Widget Ptr result_widget

    If w < GROUPBOX_MINIMUM_SIZE Then w = GROUPBOX_MINIMUM_SIZE
    If h < GROUPBOX_MINIMUM_SIZE Then h = GROUPBOX_MINIMUM_SIZE

    result_widget = New Widget
    group_data = New GroupBoxData
    If result_widget = 0 OrElse group_data = 0 Then
        If result_widget <> 0 Then Delete result_widget
        If group_data <> 0 Then Delete group_data
        Return 0
    End If

    result_widget->name = nm
    result_widget->x = x
    result_widget->y = y
    result_widget->w = w
    result_widget->h = h
    result_widget->visible = -1
    result_widget->enabled = -1
    result_widget->render = @groupbox_Render
    result_widget->destroy = @groupbox_Destroy
    group_data->text = txt
    group_data->background_color_override = 0
    group_data->background_color = 0
    group_data->foreground_color_override = 0
    group_data->foreground_color = 0
    result_widget->data = group_data
    Return result_widget
End Function


Function groupbox_SetBackgroundColor( _
    ByVal w As Widget Ptr, ByVal background_color As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(GroupBoxData Ptr, w->data)
        .background_color = background_color
        .background_color_override = -1
    End With
    Return -1
End Function


Function groupbox_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(GroupBoxData Ptr, w->data)->background_color_override = 0
    Return -1
End Function


Function groupbox_GetBackgroundColor( _
    ByVal w As Widget Ptr, ByRef background_color As ULong _
) As Integer
    Dim As GroupBoxData Ptr group_data

    background_color = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    group_data = Cast(GroupBoxData Ptr, w->data)
    If group_data->background_color_override = 0 Then Return 0
    background_color = group_data->background_color
    Return -1
End Function


Function groupbox_SetForegroundColor( _
    ByVal w As Widget Ptr, ByVal foreground_color As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(GroupBoxData Ptr, w->data)
        .foreground_color = foreground_color
        .foreground_color_override = -1
    End With
    Return -1
End Function


Function groupbox_ClearForegroundColor(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(GroupBoxData Ptr, w->data)->foreground_color_override = 0
    Return -1
End Function


Function groupbox_GetForegroundColor( _
    ByVal w As Widget Ptr, ByRef foreground_color As ULong _
) As Integer
    Dim As GroupBoxData Ptr group_data

    foreground_color = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    group_data = Cast(GroupBoxData Ptr, w->data)
    If group_data->foreground_color_override = 0 Then Return 0
    foreground_color = group_data->foreground_color
    Return -1
End Function

' -------------------------------------------------------------------------
' Public caption API
' -------------------------------------------------------------------------

Function groupbox_SetText( _
    ByVal w As Widget Ptr, ByRef txt As Const String _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(GroupBoxData Ptr, w->data)->text = txt
    Return -1
End Function

/' end of groupbox.bas '/
