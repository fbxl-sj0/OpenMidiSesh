/'
    Project: omaGUI
    File: listbox_layout.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for listbox_layout.
    Purpose: Share column geometry between rendering, scrolling and hit testing.
    Responsibilities: Bound row/column calculations and reveal the caret.
    This file intentionally does NOT own input edges or selection state.
    Private GUI-thread include in listbox.bas. scroll_top remains a row index;
    in column mode it is aligned to the first row of the leftmost column.

    This file intentionally does NOT contain:

        - application document state or lifecycle policy
'/
#ifndef __LISTBOX_LAYOUT_BI__
#define __LISTBOX_LAYOUT_BI__

Private Function listbox_VisibleColumns(ByVal w As Widget Ptr) As Integer
    Dim As ListBoxData Ptr d = w->data
    If d->column_count = 0 Then Return 1
    Dim As Integer count_value = d->column_count
    If count_value > w->w Then count_value = w->w
    If count_value < 1 Then count_value = 1
    Return count_value
End Function

Private Function listbox_ClientHeight(ByVal w As Widget Ptr) As Integer
    Dim As ListBoxData Ptr d = w->data
    Dim As Integer height_value = w->h
    height_value -= listbox_HeaderHeight(d)
    If d->column_count > 0 Then
        If height_value <= LISTBOX_SCROLLBAR_WIDTH Then Return 0
        height_value -= LISTBOX_SCROLLBAR_WIDTH
    End If
    If height_value < 0 Then height_value = 0
    Return height_value
End Function

Private Function listbox_RowsPerColumn(ByVal w As Widget Ptr) As Integer
    Dim As ListBoxData Ptr d = w->data
    Dim As Integer row_count = listbox_ClientHeight(w) \ listbox_RowHeight(d)
    If row_count < 1 Then row_count = 1
    ' More physical rows cannot expose more than the fixed retained capacity.
    If row_count > LISTBOX_MAX_ITEMS Then row_count = LISTBOX_MAX_ITEMS
    Return row_count
End Function

Private Function listbox_ColumnWidth(ByVal w As Widget Ptr) As Integer
    Dim As Integer width_value = w->w \ listbox_VisibleColumns(w)
    If width_value < 1 Then width_value = 1
    Return width_value
End Function

Private Sub listbox_RevealRow(ByVal w As Widget Ptr, ByVal item_index As Integer)
    Dim As ListBoxData Ptr d = w->data
    If item_index < 0 OrElse item_index >= d->item_count Then Exit Sub
    Dim As Integer rows_per_column = listbox_RowsPerColumn(w)
    If d->column_count > 0 Then
        Dim As Integer first_column = d->scroll_top \ rows_per_column
        Dim As Integer item_column = item_index \ rows_per_column
        Dim As Integer visible_columns = listbox_VisibleColumns(w)
        If item_column < first_column Then
            d->scroll_top = item_column * rows_per_column
        ElseIf item_column >= first_column + visible_columns Then
            d->scroll_top = (item_column - visible_columns + 1) * rows_per_column
        End If
    Else
        If item_index < d->scroll_top Then
            d->scroll_top = item_index
        ElseIf item_index >= d->scroll_top + rows_per_column Then
            d->scroll_top = item_index - rows_per_column + 1
        End If
    End If
End Sub

Private Function listbox_HitRow(ByVal w As Widget Ptr, ByVal pointer_x As Integer, ByVal pointer_y As Integer) As Integer
    Dim As ListBoxData Ptr d = w->data
    Dim As Integer client_width = w->w
    If d->column_count = 0 Then client_width -= LISTBOX_SCROLLBAR_WIDTH
    Dim As Integer relative_x = pointer_x - w->ax
    Dim As Integer relative_y = pointer_y - w->ay - listbox_HeaderHeight(d)
    If relative_x < 0 OrElse relative_x >= client_width OrElse relative_y < 0 OrElse relative_y >= listbox_ClientHeight(w) Then Return -1
    Dim As Integer row_index = relative_y \ listbox_RowHeight(d)
    If d->column_count > 0 Then
        Dim As Integer rows_per_column = listbox_RowsPerColumn(w)
        If row_index >= rows_per_column Then Return -1
        Dim As Integer column_index = relative_x \ listbox_ColumnWidth(w)
        Dim As Integer visible_columns = listbox_VisibleColumns(w)
        ' Rounding remainder belongs to the last visible column.
        If column_index >= visible_columns Then column_index = visible_columns - 1
        row_index += column_index * rows_per_column
    End If
    row_index += d->scroll_top
    If row_index < 0 OrElse row_index >= d->item_count Then Return -1
    Return row_index
End Function

Private Sub listbox_RenderColumns(ByVal w As Widget Ptr, ByVal foreground_color As ULong)
    Dim As ListBoxData Ptr d = w->data
    Dim As Integer rows_per_column = listbox_RowsPerColumn(w)
    Dim As Integer visible_columns = listbox_VisibleColumns(w)
    Dim As Integer column_width = listbox_ColumnWidth(w)
    Dim As Integer client_height = listbox_ClientHeight(w)
    If w->w <= LISTBOX_CLIP_INSET * 2 OrElse client_height <= LISTBOX_CLIP_INSET * 2 Then Exit Sub
    For item_index As Integer = d->scroll_top To d->item_count - 1
        Dim As Integer column_index = (item_index - d->scroll_top) \ rows_per_column
        If column_index >= visible_columns Then Exit For
        Dim As Integer row_index = (item_index - d->scroll_top) Mod rows_per_column ' fblint: disable-line FBL406 REASON: Range checks keep the dividend nonnegative and the modulus positive before this calculation.
        Dim As Integer column_x = w->ax + column_index * column_width
        Dim As Integer row_y = w->ay + row_index * listbox_RowHeight(d)
        Dim As Integer width_value = column_width
        If column_index = visible_columns - 1 Then width_value = w->w - column_index * column_width
        If width_value <= LISTBOX_CLIP_INSET * 2 Then Continue For
        ' Clips are a backend stack. Balance each cell's push before moving
        ' to another column so disjoint columns do not intersect each other.
        backend_SetClip column_x + LISTBOX_CLIP_INSET, w->ay + LISTBOX_CLIP_INSET, _
            width_value - LISTBOX_CLIP_INSET * 2, client_height - LISTBOX_CLIP_INSET * 2
        Dim As Integer selected_value
        listbox_GetItemSelected w, item_index, selected_value
        Dim As ULong text_color = foreground_color
        If selected_value Then
            Dim As ULong selection_color = theme_GetColor(GUI_COLOR_SELECT_BG)
            If d->selected_background_color_override Then _
                selection_color = d->selected_background_color
            backend_Rect column_x + LISTBOX_CLIP_INSET, row_y, width_value - LISTBOX_CLIP_INSET * 2, listbox_RowHeight(d), selection_color, 1
            text_color = theme_GetColor(GUI_COLOR_SELECT_TEXT)
            If d->selected_foreground_color_override Then _
                text_color = d->selected_foreground_color
        End If
        backend_Print column_x + LISTBOX_TEXT_X_OFFSET, row_y + LISTBOX_TEXT_Y_OFFSET, text_color, d->items(item_index)
        If d->selection_mode <> LISTBOX_SELECTION_SINGLE AndAlso w->has_focus AndAlso item_index = d->selected_index Then
            backend_Rect column_x + LISTBOX_CLIP_INSET, row_y, width_value - LISTBOX_CLIP_INSET * 2, listbox_RowHeight(d), theme_GetColor(GUI_COLOR_BORDER), 0
        End If
        backend_ResetClip
    Next item_index
End Sub

#endif
/' end of listbox_layout.bi '/
