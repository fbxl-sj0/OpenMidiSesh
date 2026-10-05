/'
    Project: omaGUI
    File: listbox_selection.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for listbox_selection.
    Purpose: Keep multiple row selection separate from keyboard focus.
    Responsibilities: Checked selection APIs and simple/extended gestures.
    This file intentionally does NOT own rendering, scrolling or input polling.
    Private include in listbox.bas. All calls run on the GUI thread. Row flags
    are inline bounded storage, so selection adds no separately owned memory.

    This file intentionally does NOT contain:

        - application document state or lifecycle policy
'/

#ifndef __LISTBOX_SELECTION_BI__
#define __LISTBOX_SELECTION_BI__

Private Function listbox_SelectionData(ByVal w As Widget Ptr) As ListBoxData Ptr
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then Return 0
    Dim As ListBoxData Ptr d = w->data
    If d->item_count < 0 OrElse d->item_count > LISTBOX_MAX_ITEMS Then Return 0
    Return d
End Function

Private Sub listbox_SelectRow(ByVal d As ListBoxData Ptr, ByVal item_index As Integer, ByVal selected_value As Integer)
    If item_index < 0 OrElse item_index >= d->item_count Then Exit Sub
    Dim As UByte flag_value = IIf(selected_value, 1, 0)
    If d->selected_rows(item_index) = flag_value Then Exit Sub
    d->selected_rows(item_index) = flag_value
    d->selection_change_count += 1
End Sub

Private Sub listbox_ClearSelectedRows(ByVal d As ListBoxData Ptr)
    For item_index As Integer = 0 To d->item_count - 1
        listbox_SelectRow d, item_index, 0
    Next item_index
End Sub

Private Sub listbox_SelectGesture(ByVal d As ListBoxData Ptr, ByVal item_index As Integer, _
    ByVal shift_down As Integer, ByVal control_down As Integer, ByVal toggle_action As Integer)
    If item_index < 0 OrElse item_index >= d->item_count OrElse d->selection_mode = LISTBOX_SELECTION_SINGLE Then Exit Sub
    If d->selection_mode = LISTBOX_SELECTION_SIMPLE Then
        If toggle_action Then listbox_SelectRow d, item_index, (d->selected_rows(item_index) = 0)
        Exit Sub
    End If
    If shift_down Then
        If d->selection_anchor < 0 OrElse d->selection_anchor >= d->item_count Then d->selection_anchor = item_index
        Dim As Integer first_row = d->selection_anchor
        Dim As Integer last_row = item_index
        If first_row > last_row Then Swap first_row, last_row
        ' Plain Shift replaces the range, so reversing direction shrinks it.
        ' Ctrl+Shift adds the range without losing independently selected rows.
        For row_index As Integer = 0 To d->item_count - 1
            If row_index >= first_row AndAlso row_index <= last_row Then
                listbox_SelectRow d, row_index, -1
            ElseIf control_down = 0 Then
                listbox_SelectRow d, row_index, 0
            End If
        Next row_index
    ElseIf control_down Then
        If toggle_action Then
            listbox_SelectRow d, item_index, (d->selected_rows(item_index) = 0)
            d->selection_anchor = item_index
        End If
    Else
        For row_index As Integer = 0 To d->item_count - 1
            listbox_SelectRow d, row_index, (row_index = item_index)
        Next row_index
        d->selection_anchor = item_index
    End If
End Sub

Function listbox_SetSelectionMode(ByVal w As Widget Ptr, ByVal mode_value As Integer) As Integer
    Dim As ListBoxData Ptr d = listbox_SelectionData(w)
    If d = 0 OrElse mode_value < LISTBOX_SELECTION_SINGLE OrElse mode_value > LISTBOX_SELECTION_EXTENDED Then Return 0
    If d->selection_mode = mode_value Then Return -1
    If d->selection_mode = LISTBOX_SELECTION_SINGLE Then
        listbox_ClearSelectedRows d
        listbox_SelectRow d, d->selected_index, -1
    ElseIf mode_value = LISTBOX_SELECTION_SINGLE Then
        Dim As Integer retained_row = -1
        For item_index As Integer = 0 To d->item_count - 1
            If d->selected_rows(item_index) Then
                If retained_row = -1 OrElse item_index = d->selected_index Then retained_row = item_index
                If item_index = d->selected_index Then Exit For
            End If
        Next item_index
        d->selected_index = retained_row
        listbox_ClearSelectedRows d
    End If
    d->selection_mode = mode_value
    d->selection_change_count += 1
    d->selection_anchor = d->selected_index
    ' Changing modes while Space is held must not invent a new key press.
    If input_KeyPressed(FB.SC_SPACE) Then d->key_latch Or= LISTBOX_KEY_SPACE_BIT
    If d->pointer_latch Then d->pointer_index = -1
    listbox_ClearDoubleClick d
    Return -1
End Function

Function listbox_GetSelectionMode(ByVal w As Widget Ptr) As Integer
    Dim As ListBoxData Ptr d = listbox_SelectionData(w)
    If d = 0 Then Return -1
    Return d->selection_mode
End Function

Function listbox_SetItemSelected(ByVal w As Widget Ptr, ByVal item_index As Integer, ByVal selected_value As Integer) As Integer
    Dim As ListBoxData Ptr d = listbox_SelectionData(w)
    If d = 0 OrElse item_index < 0 OrElse item_index >= d->item_count Then Return 0
    If d->selection_mode = LISTBOX_SELECTION_SINGLE Then
        If selected_value Then Return listbox_SetSelectedIndex(w, item_index)
        If d->selected_index = item_index Then Return listbox_SetSelectedIndex(w, -1)
    Else
        listbox_SelectRow d, item_index, selected_value
    End If
    Return -1
End Function

Function listbox_GetItemSelected(ByVal w As Widget Ptr, ByVal item_index As Integer, ByRef selected_value As Integer) As Integer
    selected_value = 0
    Dim As ListBoxData Ptr d = listbox_SelectionData(w)
    If d = 0 OrElse item_index < 0 OrElse item_index >= d->item_count Then Return 0
    If d->selection_mode = LISTBOX_SELECTION_SINGLE Then
        selected_value = IIf(d->selected_index = item_index, -1, 0)
    Else
        selected_value = IIf(d->selected_rows(item_index), -1, 0)
    End If
    Return -1
End Function

Function listbox_GetSelectedCount(ByVal w As Widget Ptr) As Integer
    Dim As ListBoxData Ptr d = listbox_SelectionData(w)
    If d = 0 Then Return 0
    If d->selection_mode = LISTBOX_SELECTION_SINGLE Then Return IIf(d->selected_index >= 0 AndAlso d->selected_index < d->item_count, 1, 0)
    Dim As Integer selected_count
    For item_index As Integer = 0 To d->item_count - 1
        If d->selected_rows(item_index) Then selected_count += 1
    Next item_index
    Return selected_count
End Function

Function listbox_GetSelectionChangeCount(ByVal w As Widget Ptr) As ULongInt
    Dim As ListBoxData Ptr d = listbox_SelectionData(w)
    If d = 0 Then Return 0
    Return d->selection_change_count
End Function

#endif
/' end of listbox_selection.bi '/
