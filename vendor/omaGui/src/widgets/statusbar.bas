/'
    Project: omaGUI
    ---------------

    File: statusbar.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements statusbar.bi; declarations there define the interface.

    Purpose:

        Implement a portable classic status bar with bounded text panels.

    Responsibilities:

        - divide current widget width among fixed and flexible panels
        - render classic recessed separators and aligned clipped-length text
        - own and release one StatusBarData record

    This file intentionally does NOT contain:

        - application-specific status messages
        - input event handling
        - operating-system status-bar handles

    Ownership:

        - each widget owns one StatusBarData allocation and its panel strings
'/

#lang "fb"

#include once "src/widgets/statusbar.bi"
#include once "src/backend/theme.bi"

Const STATUSBAR_MINIMUM_WIDTH As Integer = 24
Const STATUSBAR_MINIMUM_HEIGHT As Integer = 18
Const STATUSBAR_MAXIMUM_HEIGHT As Integer = 64
Const STATUSBAR_MAXIMUM_PANEL_WIDTH As Integer = 4096
Const STATUSBAR_TEXT_PADDING As Integer = 6

' -------------------------------------------------------------------------
' Text and panel geometry helpers
' -------------------------------------------------------------------------

Private Function statusbar_FitText( _
    ByRef source_text As Const String, _
    ByVal maximum_width As Integer _
) As String
    Dim As String fitted_text
    Dim As String suffix_text

    If maximum_width < 1 Then Return ""
    If backend_GetTextWidth(source_text) <= maximum_width Then _
        Return source_text
    suffix_text = "..."
    While Len(suffix_text) > 0 AndAlso _
          backend_GetTextWidth(suffix_text) > maximum_width
        suffix_text = Left(suffix_text, Len(suffix_text) - 1)
    Wend
    fitted_text = source_text
    While Len(fitted_text) > 0 AndAlso _
          backend_GetTextWidth(fitted_text & suffix_text) > maximum_width
        fitted_text = Left(fitted_text, Len(fitted_text) - 1)
    Wend
    Return fitted_text & suffix_text
End Function


Private Function statusbar_FutureFixedWidth( _
    ByVal bar_data As StatusBarData Ptr, _
    ByVal first_index As Integer _
) As Integer
    Dim As Integer panel_index
    Dim As Integer total_width

    If bar_data = 0 Then Return 0
    For panel_index = first_index To bar_data->panel_count - 1
        If bar_data->panel_width(panel_index) > 0 Then _
            total_width += bar_data->panel_width(panel_index)
    Next panel_index
    Return total_width
End Function


Private Function statusbar_FutureFlexibleCount( _
    ByVal bar_data As StatusBarData Ptr, _
    ByVal first_index As Integer _
) As Integer
    Dim As Integer panel_index
    Dim As Integer panel_count

    If bar_data = 0 Then Return 0
    For panel_index = first_index To bar_data->panel_count - 1
        If bar_data->panel_width(panel_index) = 0 Then panel_count += 1
    Next panel_index
    Return panel_count
End Function

' -------------------------------------------------------------------------
' Construction and public metadata API
' -------------------------------------------------------------------------

Function statusbar_Create( _
    ByVal widget_name As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal bar_width As Integer, _
    ByVal bar_height As Integer _
) As Widget Ptr
    Dim As StatusBarData Ptr bar_data
    Dim As Widget Ptr bar_widget

    If Len(widget_name) < 1 OrElse _
       Len(widget_name) > STATUSBAR_MAX_TEXT_BYTES Then Return 0
    If bar_width < STATUSBAR_MINIMUM_WIDTH Then _
        bar_width = STATUSBAR_MINIMUM_WIDTH
    If bar_height < STATUSBAR_MINIMUM_HEIGHT Then _
        bar_height = STATUSBAR_MINIMUM_HEIGHT
    If bar_height > STATUSBAR_MAXIMUM_HEIGHT Then _
        bar_height = STATUSBAR_MAXIMUM_HEIGHT

    bar_widget = New Widget
    If bar_widget = 0 Then Return 0
    bar_data = New StatusBarData
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
    bar_widget->render = @statusbar_Render
    bar_widget->destroy = @statusbar_Destroy
    bar_widget->data = bar_data
    Return bar_widget
End Function


Function statusbar_AddPanel( _
    ByVal bar_widget As Widget Ptr, _
    ByVal panel_text As String, _
    ByVal panel_width As Integer _
) As Integer
    Dim As StatusBarData Ptr bar_data
    Dim As Integer panel_index

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return -1
    If Len(panel_text) > STATUSBAR_MAX_TEXT_BYTES Then Return -1
    If panel_width < 0 OrElse _
       panel_width > STATUSBAR_MAXIMUM_PANEL_WIDTH Then Return -1
    bar_data = Cast(StatusBarData Ptr, bar_widget->data)
    If bar_data->panel_count >= STATUSBAR_MAX_PANELS Then Return -1

    panel_index = bar_data->panel_count
    bar_data->panel_text(panel_index) = panel_text
    bar_data->panel_width(panel_index) = panel_width
    bar_data->panel_alignment(panel_index) = BACKEND_ALIGN_LEFT
    bar_data->panel_count += 1
    Return panel_index
End Function


Function statusbar_SetPanelText( _
    ByVal bar_widget As Widget Ptr, _
    ByVal panel_index As Integer, _
    ByVal panel_text As String _
) As Integer
    Dim As StatusBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    If Len(panel_text) > STATUSBAR_MAX_TEXT_BYTES Then Return 0
    bar_data = Cast(StatusBarData Ptr, bar_widget->data)
    If panel_index < 0 OrElse panel_index >= bar_data->panel_count Then Return 0
    bar_data->panel_text(panel_index) = panel_text
    Return -1
End Function


Function statusbar_SetPanelAlignment( _
    ByVal bar_widget As Widget Ptr, _
    ByVal panel_index As Integer, _
    ByVal horizontal_alignment As Integer _
) As Integer
    Dim As StatusBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    If horizontal_alignment < BACKEND_ALIGN_LEFT OrElse _
       horizontal_alignment > BACKEND_ALIGN_RIGHT Then Return 0
    bar_data = Cast(StatusBarData Ptr, bar_widget->data)
    If panel_index < 0 OrElse panel_index >= bar_data->panel_count Then Return 0
    bar_data->panel_alignment(panel_index) = horizontal_alignment
    Return -1
End Function


Function statusbar_GetPanelText( _
    ByVal bar_widget As Widget Ptr, _
    ByVal panel_index As Integer _
) As String
    Dim As StatusBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return ""
    bar_data = Cast(StatusBarData Ptr, bar_widget->data)
    If panel_index < 0 OrElse panel_index >= bar_data->panel_count Then Return ""
    Return bar_data->panel_text(panel_index)
End Function


Function statusbar_GetPanelAlignment( _
    ByVal bar_widget As Widget Ptr, _
    ByVal panel_index As Integer _
) As Integer
    Dim As StatusBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then _
        Return BACKEND_ALIGN_LEFT
    bar_data = Cast(StatusBarData Ptr, bar_widget->data)
    If panel_index < 0 OrElse panel_index >= bar_data->panel_count Then _
        Return BACKEND_ALIGN_LEFT
    Return bar_data->panel_alignment(panel_index)
End Function


Function statusbar_GetPanelCount( _
    ByVal bar_widget As Widget Ptr _
) As Integer
    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    Return Cast(StatusBarData Ptr, bar_widget->data)->panel_count
End Function

' -------------------------------------------------------------------------
' Rendering and lifecycle
' -------------------------------------------------------------------------

Sub statusbar_Render(ByVal bar_widget As Widget Ptr)
    Dim As StatusBarData Ptr bar_data
    Dim As Integer available_width
    Dim As Integer flexible_count
    Dim As Integer future_fixed_width
    Dim As Integer maximum_panel_width
    Dim As Integer panel_index
    Dim As Integer panel_left
    Dim As Integer panel_text_width
    Dim As Integer panel_width
    Dim As Integer remaining_width
    Dim As String display_text

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Exit Sub
    bar_data = Cast(StatusBarData Ptr, bar_widget->data)
    backend_Rect _
        bar_widget->ax, bar_widget->ay, bar_widget->w, bar_widget->h, _
        theme_GetColor(GUI_COLOR_WIDGET_BG), -1
    backend_Line _
        bar_widget->ax, bar_widget->ay, _
        bar_widget->ax + bar_widget->w - 1, bar_widget->ay, _
        theme_GetColor(GUI_COLOR_BORDER)

    available_width = bar_widget->w - 2
    If available_width < 1 OrElse bar_data->panel_count < 1 Then Exit Sub
    remaining_width = available_width
    panel_left = bar_widget->ax + 1
    For panel_index = 0 To bar_data->panel_count - 1
        maximum_panel_width = remaining_width - _
            (bar_data->panel_count - panel_index - 1)
        If maximum_panel_width < 1 Then maximum_panel_width = 1
        If panel_index = bar_data->panel_count - 1 Then
            panel_width = remaining_width
        ElseIf bar_data->panel_width(panel_index) > 0 Then
            panel_width = bar_data->panel_width(panel_index)
            If panel_width > maximum_panel_width Then _
                panel_width = maximum_panel_width
        Else
            future_fixed_width = statusbar_FutureFixedWidth( _
                bar_data, panel_index + 1 _
            )
            flexible_count = statusbar_FutureFlexibleCount( _
                bar_data, panel_index _
            )
            panel_width = remaining_width - future_fixed_width
            If flexible_count > 0 Then panel_width \= flexible_count
            If panel_width < 1 Then panel_width = 1
            If panel_width > maximum_panel_width Then _
                panel_width = maximum_panel_width
        End If

        panel_text_width = panel_width - STATUSBAR_TEXT_PADDING * 2
        If panel_text_width > 0 Then
            display_text = statusbar_FitText( _
                bar_data->panel_text(panel_index), panel_text_width _
            )
            backend_PrintAligned _
                panel_left + STATUSBAR_TEXT_PADDING, bar_widget->ay + 1, _
                panel_text_width, bar_widget->h - 2, _
                theme_GetColor(GUI_COLOR_TEXT), display_text, _
                BACKEND_FONT_DEFAULT, bar_data->panel_alignment(panel_index), _
                BACKEND_ALIGN_MIDDLE
        End If
        If panel_index < bar_data->panel_count - 1 Then
            backend_Line _
                panel_left + panel_width - 1, bar_widget->ay + 3, _
                panel_left + panel_width - 1, _
                bar_widget->ay + bar_widget->h - 4, _
                theme_GetColor(GUI_COLOR_BORDER)
        End If
        panel_left += panel_width
        remaining_width -= panel_width
        If remaining_width < 1 Then Exit For
    Next panel_index
End Sub


Sub statusbar_Destroy(ByVal bar_widget As Widget Ptr)
    If bar_widget = 0 Then Exit Sub
    If bar_widget->data <> 0 Then _
        Delete Cast(StatusBarData Ptr, bar_widget->data)
    bar_widget->data = 0
End Sub

/' end of statusbar.bas '/
