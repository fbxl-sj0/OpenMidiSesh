/'
    Project: omaGUI
    File: menubar_headings.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for menubar_headings.
    Purpose: Maintain mutable heading state for the native menu bar.
    Responsibilities: compact visible headings and gate navigation/activation.
    This private implementation include contains no platform menu calls.
    The GUI thread owns all state. Metadata changes cancel any pending press
    before moving headings, so release cannot activate a different command.

    This file intentionally does NOT contain:

        - application document state or lifecycle policy
'/
#ifndef __MENUBAR_HEADINGS_BI__
#define __MENUBAR_HEADINGS_BI__

Private Function menubar_HeadingData(ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer) As MenuBarData Ptr
    If bar_widget = 0 OrElse bar_widget->destroy <> @menubar_Destroy OrElse bar_widget->data = 0 Then Return 0
    Dim As MenuBarData Ptr bar_data = bar_widget->data
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    Return bar_data
End Function

Private Function menubar_HeadingAvailable(ByVal bar_data As MenuBarData Ptr, ByVal menu_index As Integer) As Integer
    If bar_data = 0 OrElse menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    If bar_data->menu_visible(menu_index) = 0 OrElse _
       bar_data->menu_enabled(menu_index) = 0 Then Return 0
    If bar_data->menu_popups(menu_index) <> 0 Then _
        Return IIf( _
            menu_GetVisibleItemCount(bar_data->menu_popups(menu_index)) > 0, _
            -1, 0 _
        )
    Return -1
End Function

Private Function menubar_NextHeading(ByVal bar_data As MenuBarData Ptr, ByVal current_menu As Integer, ByVal direction As Integer) As Integer
    If bar_data = 0 OrElse bar_data->menu_count = 0 Then Return -1
    ' fblint: disable-next-line FBL311 REASON: The loop counter bounds repeated work; the cursor or stream state supplies each value.
    For attempt As Integer = 1 To bar_data->menu_count
        current_menu += direction
        If current_menu < 0 Then current_menu = bar_data->menu_count - 1
        If current_menu >= bar_data->menu_count Then current_menu = 0
        If menubar_HeadingAvailable(bar_data, current_menu) Then Return current_menu
    Next attempt
    Return -1
End Function

Private Sub menubar_RecalculateHeadings(ByVal bar_data As MenuBarData Ptr)
    Dim As Integer next_left = 0
    For menu_index As Integer = 0 To bar_data->menu_count - 1
        bar_data->menu_left(menu_index) = next_left
        Dim As Integer heading_width = backend_GetTextWidth(menubar_DisplayText(bar_data->menu_labels(menu_index))) + MENUBAR_HEADING_PADDING
        If heading_width < MENUBAR_MINIMUM_HEADING_WIDTH Then heading_width = MENUBAR_MINIMUM_HEADING_WIDTH
        bar_data->menu_width(menu_index) = heading_width
        If bar_data->menu_visible(menu_index) Then next_left += heading_width
    Next menu_index
End Sub

Sub menubar_CancelInput(ByVal bar_widget As Widget Ptr)
    If bar_widget = 0 OrElse bar_widget->destroy <> @menubar_Destroy OrElse bar_widget->data = 0 Then Exit Sub
    Dim As MenuBarData Ptr bar_data = bar_widget->data
    Dim As Integer open_menu = bar_data->open_menu
    Dim As Widget Ptr open_popup
    If open_menu >= 0 AndAlso open_menu < bar_data->menu_count Then _
        open_popup = bar_data->menu_popups(open_menu)
    bar_data->open_menu = -1
    bar_data->hot_menu = -1
    bar_data->hot_item = -1
    bar_data->pointer_latch = 0
    bar_data->pointer_menu = -1
    bar_data->pointer_item = -1
    bar_data->pointer_open_menu = -1
    bar_widget->pointer_global = 0
    If open_popup <> 0 Then menu_CloseTree open_popup
End Sub

Function menubar_SetMenuLabel(ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer, ByVal menu_text As String) As Integer
    Dim As MenuBarData Ptr bar_data = menubar_HeadingData(bar_widget, menu_index)
    If bar_data = 0 OrElse Len(menu_text) < 1 OrElse Len(menu_text) > MENUBAR_MAXIMUM_LABEL_BYTES Then Return 0
    menubar_CancelInput(bar_widget)
    bar_data->menu_labels(menu_index) = menu_text
    menubar_RecalculateHeadings(bar_data)
    Return -1
End Function

Function menubar_SetMenuVisible(ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer, ByVal visible_value As Integer) As Integer
    Dim As MenuBarData Ptr bar_data = menubar_HeadingData(bar_widget, menu_index)
    If bar_data = 0 Then Return 0
    visible_value = IIf(visible_value, -1, 0)
    If bar_data->menu_visible(menu_index) = visible_value Then Return -1
    menubar_CancelInput(bar_widget)
    bar_data->menu_visible(menu_index) = visible_value
    menubar_RecalculateHeadings(bar_data)
    Return -1
End Function

Function menubar_GetMenuVisible(ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer) As Integer
    Dim As MenuBarData Ptr bar_data = menubar_HeadingData(bar_widget, menu_index)
    If bar_data = 0 Then Return 0
    Return bar_data->menu_visible(menu_index)
End Function

Function menubar_SetMenuEnabled(ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer, ByVal enabled_value As Integer) As Integer
    Dim As MenuBarData Ptr bar_data = menubar_HeadingData(bar_widget, menu_index)
    If bar_data = 0 Then Return 0
    enabled_value = IIf(enabled_value, -1, 0)
    If bar_data->menu_enabled(menu_index) = enabled_value Then Return -1
    menubar_CancelInput(bar_widget)
    bar_data->menu_enabled(menu_index) = enabled_value
    Return -1
End Function

Function menubar_GetMenuEnabled(ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer) As Integer
    Dim As MenuBarData Ptr bar_data = menubar_HeadingData(bar_widget, menu_index)
    If bar_data = 0 Then Return 0
    Return bar_data->menu_enabled(menu_index)
End Function
#endif
/' end of menubar_headings.bi '/
