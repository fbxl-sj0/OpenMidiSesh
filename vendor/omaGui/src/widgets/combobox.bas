/'
    Project: omaGUI
    ---------------

    File: combobox.bas

    Purpose:

        Implement portable DropDown and Simple ComboBox styles.

    Responsibilities:

        - render editable and fixed values, the drop-down arrow, and bounded lists
        - route release-inside pointer choices and outside-click dismissal
        - support arrow, Home, End, Enter, Space, and Escape keys
        - match bounded keyboard prefixes for choice-only controls
        - keep the pending row visible and expose user-open notifications
        - render optional normal client and text colors
        - preserve selection identity across checked list mutations
        - cancel popup input without calling application code

    This file intentionally does NOT contain:

        - autocomplete or application-specific matching policy
        - application-specific choice semantics
        - native window or control APIs

    Ownership:

        - the widget owns one ComboBoxData allocation and all item strings
'/

#lang "fb"

#include once "src/widgets/combobox.bi"
#include once "src/backend/theme.bi"

Const COMBOBOX_MINIMUM_WIDTH As Integer = 40
Const COMBOBOX_MINIMUM_HEIGHT As Integer = 18
Const COMBOBOX_ARROW_WIDTH As Integer = 18
Const COMBOBOX_SIMPLE_FIELD_HEIGHT As Integer = COMBOBOX_MINIMUM_HEIGHT
Const COMBOBOX_ROW_HEIGHT As Integer = 18
Const COMBOBOX_POPUP_BORDER As Integer = 1
Const COMBOBOX_TEXT_INSET As Integer = 4
Const COMBOBOX_POINTER_OUTSIDE As Integer = -1
Const COMBOBOX_POINTER_HEADER As Integer = -2
Const COMBOBOX_POINTER_EDIT As Integer = -3
Const COMBOBOX_TYPE_AHEAD_MAX_BYTES As Integer = 256
Const COMBOBOX_TYPE_AHEAD_TIMEOUT_SECONDS As Double = 1.0
Const COMBOBOX_SECONDS_PER_DAY As Double = 86400.0

' -------------------------------------------------------------------------
' Private geometry and state helpers
' -------------------------------------------------------------------------

Private Function combobox_VisibleRows( _
    ByVal combo_data As ComboBoxData Ptr, _
    ByVal combo_widget As Widget Ptr = 0 _
) As Integer
    Dim As Integer visible_rows

    If combo_data = 0 Then Return 0
    visible_rows = combo_data->item_count
    If visible_rows > combo_data->maximum_rows Then _
        visible_rows = combo_data->maximum_rows
    If combo_data->simple_mode <> 0 Then
        Dim As Integer available_height
        Dim As Integer geometry_rows
        If combo_widget = 0 Then Return 0
        available_height = combo_widget->h - _
            COMBOBOX_SIMPLE_FIELD_HEIGHT - COMBOBOX_POPUP_BORDER * 2
        If available_height < 0 Then available_height = 0
        geometry_rows = available_height \ COMBOBOX_ROW_HEIGHT
        If visible_rows > geometry_rows Then visible_rows = geometry_rows
    End If
    Return visible_rows
End Function


Private Function combobox_PopupHeight( _
    ByVal combo_data As ComboBoxData Ptr _
) As Integer
    Return combobox_VisibleRows(combo_data) * COMBOBOX_ROW_HEIGHT + _
        COMBOBOX_POPUP_BORDER * 2
End Function


Private Function combobox_PopupTop( _
    ByVal combo_widget As Widget Ptr, _
    ByVal combo_data As ComboBoxData Ptr _
) As Integer
    Dim As Integer popup_height
    Dim As Integer viewport_height
    Dim As Integer viewport_width

    If combo_widget = 0 OrElse combo_data = 0 Then Return 0
    popup_height = combobox_PopupHeight(combo_data)
    backend_GetSize viewport_width, viewport_height

    If combo_widget->ay + combo_widget->h + popup_height > viewport_height _
       AndAlso combo_widget->ay - popup_height >= 0 Then
        Return combo_widget->ay - popup_height
    End If
    Return combo_widget->ay + combo_widget->h
End Function


Private Sub combobox_ClampScroll( _
    ByVal combo_data As ComboBoxData Ptr, _
    ByVal combo_widget As Widget Ptr = 0 _
)
    Dim As Integer maximum_scroll
    Dim As Integer visible_rows

    If combo_data = 0 Then Exit Sub
    visible_rows = combobox_VisibleRows(combo_data, combo_widget)
    maximum_scroll = combo_data->item_count - visible_rows
    If visible_rows <= 0 Then maximum_scroll = 0
    If maximum_scroll < 0 Then maximum_scroll = 0
    If combo_data->scroll_top < 0 Then combo_data->scroll_top = 0
    If combo_data->scroll_top > maximum_scroll Then _
        combo_data->scroll_top = maximum_scroll
End Sub


Private Sub combobox_ResetTypeAhead(ByVal combo_data As ComboBoxData Ptr)
    If combo_data = 0 Then Exit Sub
    combo_data->type_ahead_text = ""
    combo_data->type_ahead_clock = 0.0
    combo_data->type_ahead_clock_initialized = 0
End Sub


Private Sub combobox_RevealPending( _
    ByVal combo_widget As Widget Ptr, _
    ByVal combo_data As ComboBoxData Ptr _
)
    Dim As Integer visible_rows

    If combo_data = 0 OrElse combo_data->pending_index < 0 Then Exit Sub
    visible_rows = combobox_VisibleRows(combo_data, combo_widget)
    If visible_rows <= 0 Then Exit Sub
    If combo_data->pending_index < combo_data->scroll_top Then
        combo_data->scroll_top = combo_data->pending_index
    ElseIf combo_data->pending_index >= _
           combo_data->scroll_top + visible_rows Then
        combo_data->scroll_top = combo_data->pending_index - visible_rows + 1
    End If
    combobox_ClampScroll combo_data, combo_widget
End Sub


Private Sub combobox_SetOpenState( _
    ByVal combo_widget As Widget Ptr, _
    ByVal combo_data As ComboBoxData Ptr, _
    ByVal open_state As Integer _
)
    If combo_widget = 0 OrElse combo_data = 0 Then Exit Sub
    combobox_ResetTypeAhead combo_data

    If combo_data->simple_mode <> 0 Then
        combo_data->is_open = 0
        combo_widget->pointer_global = 0
        combo_widget->captures_escape = 0
        combo_data->pending_index = combo_data->selected_index
        Return
    End If

    If open_state <> 0 AndAlso combo_data->item_count > 0 Then
        combo_data->is_open = -1
        combo_widget->pointer_global = -1
        combo_widget->captures_escape = -1
        combo_data->pending_index = combo_data->selected_index
        If combo_data->pending_index < 0 Then combo_data->pending_index = 0
        combobox_RevealPending combo_widget, combo_data

        /'
            The popup is drawn outside the widget's closed rectangle. Moving
            the control to the end of its current registry layer keeps those
            rows above sibling controls while preserving the parent link.
        '/
        gui_BringToFront combo_widget
    Else
        combo_data->is_open = 0
        combo_widget->pointer_global = 0
        combo_widget->captures_escape = 0
        combo_data->pending_index = combo_data->selected_index
    End If
End Sub


Private Sub combobox_OpenForUser( _
    ByVal combo_widget As Widget Ptr, _
    ByVal combo_data As ComboBoxData Ptr _
)
    If combo_widget = 0 OrElse combo_data = 0 OrElse _
       combo_data->is_open <> 0 Then Exit Sub
    combobox_SetOpenState combo_widget, combo_data, -1
    ' An empty list cannot open and therefore does not produce DropDown.
    If combo_data->is_open <> 0 Then combo_data->dropdown_count += 1
End Sub


Private Sub combobox_NotifySelection( _
    ByVal combo_widget As Widget Ptr, _
    ByVal combo_data As ComboBoxData Ptr, _
    ByVal selected_index As Integer _
)
    Dim As Integer text_changed
    Dim As String previous_text

    If combo_widget = 0 OrElse combo_data = 0 Then Exit Sub
    If selected_index < 0 OrElse _
       selected_index >= combo_data->item_count Then Exit Sub
    ' A user can activate the selected row again without changing its text.
    ' Keep the historical change callback separate from activation polling.
    combo_data->activation_count += 1
    previous_text = combo_data->edit_text
    If combo_data->editable Then
        combo_data->edit_text = combo_data->items(selected_index)
        combo_data->edit_cursor = Len(combo_data->edit_text)
        text_changed = IIf(previous_text <> combo_data->edit_text, -1, 0)
    End If
    If selected_index = combo_data->selected_index AndAlso _
       text_changed = 0 Then Exit Sub

    combo_data->selected_index = selected_index
    combo_data->pending_index = selected_index
    combo_data->change_count += 1
    If combo_data->change_handler <> 0 Then
        Cast(Sub(ByVal As Widget Ptr), _
            combo_data->change_handler)(combo_widget)
    End If
End Sub


Private Function combobox_ExactItemIndex( _
    ByVal combo_data As ComboBoxData Ptr, _
    ByRef text_value As Const String _
) As Integer
    If combo_data = 0 Then Return -1
    For item_index As Integer = 0 To combo_data->item_count - 1
        If combo_data->items(item_index) = text_value Then Return item_index
    Next item_index
    Return -1
End Function


Private Sub combobox_NotifyEditText( _
    ByVal combo_widget As Widget Ptr, _
    ByVal combo_data As ComboBoxData Ptr, _
    ByRef text_value As Const String _
)
    If combo_widget = 0 OrElse combo_data = 0 OrElse _
       combo_data->editable = 0 OrElse combo_data->edit_text = text_value Then _
        Exit Sub

    combo_data->edit_text = text_value
    combo_data->edit_cursor = Len(combo_data->edit_text)
    combo_data->selected_index = _
        combobox_ExactItemIndex(combo_data, combo_data->edit_text)
    combo_data->pending_index = combo_data->selected_index
    combo_data->change_count += 1
    If combo_data->change_handler <> 0 Then _
        Cast(Sub(ByVal As Widget Ptr), _
            combo_data->change_handler)(combo_widget)
End Sub


Private Function combobox_FilterEditText( _
    ByRef source_text As Const String _
) As String
    Dim As String filtered_text

    For character_index As Integer = 1 To Len(source_text)
        Dim As Integer character_code = Asc(source_text, character_index)
        ' A ComboBox edit field is one physical line. Preserve byte-oriented
        ' portable text while excluding NUL and line terminators.
        If character_code >= 32 AndAlso character_code <= 255 Then _
            filtered_text &= Chr(character_code)
    Next character_index
    Return filtered_text
End Function


Private Function combobox_TypeAheadFoldByte( _
    ByVal character_code As Integer _
) As Integer
    ' ASCII folding is deterministic across host locales and byte encodings.
    If character_code >= Asc("A") AndAlso character_code <= Asc("Z") Then _
        Return character_code + Asc("a") - Asc("A")
    Return character_code
End Function


Private Function combobox_TypeAheadMatches( _
    ByRef item_text As Const String, _
    ByRef prefix_text As Const String _
) As Integer
    If Len(prefix_text) = 0 OrElse Len(item_text) < Len(prefix_text) Then _
        Return 0

    For byte_index As Integer = 1 To Len(prefix_text)
        If combobox_TypeAheadFoldByte(Asc(item_text, byte_index)) <> _
           combobox_TypeAheadFoldByte(Asc(prefix_text, byte_index)) Then _
            Return 0
    Next byte_index
    Return -1
End Function


Private Function combobox_FindTypeAheadItem( _
    ByVal combo_data As ComboBoxData Ptr, _
    ByRef prefix_text As Const String, _
    ByVal first_index As Integer _
) As Integer
    Dim As Integer checked_index

    If combo_data = 0 OrElse combo_data->item_count <= 0 OrElse _
       combo_data->item_count > COMBOBOX_MAX_ITEMS Then Return -1
    If first_index < 0 OrElse first_index >= combo_data->item_count Then _
        first_index = 0

    For item_offset As Integer = 0 To combo_data->item_count - 1
        checked_index = first_index + item_offset
        If checked_index >= combo_data->item_count Then _
            checked_index -= combo_data->item_count
        If combobox_TypeAheadMatches( _
            combo_data->items(checked_index), prefix_text) Then _
            Return checked_index
    Next item_offset
    Return -1
End Function


Private Function combobox_TypeAheadInput( _
    ByVal combo_widget As Widget Ptr, _
    ByVal combo_data As ComboBoxData Ptr _
) As Integer
    Dim As String typed_text
    Dim As String previous_prefix
    Dim As String next_prefix
    Dim As Double clock_now
    Dim As Double elapsed_seconds
    Dim As Integer prefix_is_fresh
    Dim As Integer repeat_character
    Dim As Integer base_index
    Dim As Integer first_index
    Dim As Integer selected_index
    Dim As Integer matched_index

    If combo_widget = 0 OrElse combo_data = 0 OrElse _
       combo_data->editable <> 0 Then Return 0
    If combo_widget->has_focus = 0 Then
        combobox_ResetTypeAhead combo_data
        Return 0
    End If

    typed_text = combobox_FilterEditText(input_PollTextInput())
    If Len(typed_text) = 0 Then
        If input_KeyPressEvent(KEY_BACKSPACE) <> 0 OrElse _
           input_KeyPressEvent(KEY_LEFT) <> 0 OrElse _
           input_KeyPressEvent(KEY_RIGHT) <> 0 OrElse _
           input_KeyPressEvent(KEY_HOME) <> 0 OrElse _
           input_KeyPressEvent(KEY_END) <> 0 OrElse _
           input_KeyPressEvent(KEY_UP) <> 0 OrElse _
           input_KeyPressEvent(KEY_DOWN) <> 0 OrElse _
           input_KeyPressEvent(KEY_RETURN) <> 0 OrElse _
           input_KeyPressEvent(KEY_ESCAPE) <> 0 OrElse _
           input_KeyPressEvent(FB.SC_SPACE) <> 0 Then _
            combobox_ResetTypeAhead combo_data
        Return 0
    End If
    If combo_data->item_count <= 0 OrElse _
       combo_data->item_count > COMBOBOX_MAX_ITEMS Then
        combobox_ResetTypeAhead combo_data
        Return 0
    End If
    If Len(typed_text) > COMBOBOX_TYPE_AHEAD_MAX_BYTES Then _
        typed_text = Left(typed_text, COMBOBOX_TYPE_AHEAD_MAX_BYTES)

    clock_now = CDbl(Timer)
    If combo_data->type_ahead_clock_initialized <> 0 Then
        elapsed_seconds = clock_now - combo_data->type_ahead_clock
        ' Timer wraps at midnight. A backward clock change otherwise expires
        ' the query instead of extending it for an entire day.
        If elapsed_seconds < 0.0 Then _
            elapsed_seconds += COMBOBOX_SECONDS_PER_DAY
        If elapsed_seconds >= 0.0 AndAlso _
           elapsed_seconds <= COMBOBOX_TYPE_AHEAD_TIMEOUT_SECONDS Then
            prefix_is_fresh = -1
            previous_prefix = combo_data->type_ahead_text
        End If
    End If

    If prefix_is_fresh <> 0 AndAlso Len(typed_text) = 1 AndAlso _
       Len(previous_prefix) = 1 AndAlso _
       combobox_TypeAheadFoldByte(Asc(typed_text, 1)) = _
       combobox_TypeAheadFoldByte(Asc(previous_prefix, 1)) Then
        next_prefix = previous_prefix
        repeat_character = -1
    Else
        If Len(previous_prefix) > _
           COMBOBOX_TYPE_AHEAD_MAX_BYTES - Len(typed_text) Then _
            previous_prefix = ""
        next_prefix = previous_prefix & typed_text
        If Len(next_prefix) > COMBOBOX_TYPE_AHEAD_MAX_BYTES Then _
            next_prefix = Left(next_prefix, COMBOBOX_TYPE_AHEAD_MAX_BYTES)
    End If

    combo_data->type_ahead_text = next_prefix
    combo_data->type_ahead_clock = clock_now
    combo_data->type_ahead_clock_initialized = -1

    selected_index = combo_data->selected_index
    If combo_data->is_open <> 0 AndAlso _
       combo_data->pending_index >= 0 AndAlso _
       combo_data->pending_index < combo_data->item_count Then _
        selected_index = combo_data->pending_index
    If repeat_character <> 0 OrElse prefix_is_fresh = 0 Then
        first_index = selected_index + 1
    ElseIf selected_index >= 0 AndAlso _
           selected_index < combo_data->item_count AndAlso _
           combobox_TypeAheadMatches( _
               combo_data->items(selected_index), next_prefix) Then
        first_index = selected_index
    Else
        first_index = 0
    End If

    matched_index = combobox_FindTypeAheadItem( _
        combo_data, next_prefix, first_index)
    If matched_index < 0 Then Return 0

    If combo_data->is_open <> 0 Then
        If combo_data->pending_index <> matched_index Then
            combo_data->pending_index = matched_index
            combobox_RevealPending combo_widget, combo_data
        End If
        Return 0
    End If

    If matched_index = combo_data->selected_index Then Return 0
    combobox_NotifySelection combo_widget, combo_data, matched_index
    ' The application callback may release this widget and its data.
    Return -1
End Function


Private Sub combobox_EditTextInput( _
    ByVal combo_widget As Widget Ptr, _
    ByVal combo_data As ComboBoxData Ptr _
)
    Dim As String typed_text
    Dim As String updated_text
    Dim As Integer desired_cursor

    If combo_widget = 0 OrElse combo_data = 0 OrElse _
       combo_data->editable = 0 OrElse combo_widget->has_focus = 0 Then Exit Sub

    If combo_data->edit_cursor < 0 Then combo_data->edit_cursor = 0
    If combo_data->edit_cursor > Len(combo_data->edit_text) Then _
        combo_data->edit_cursor = Len(combo_data->edit_text)

    typed_text = combobox_FilterEditText(input_PollTextInput())
    If Len(typed_text) > 0 Then
        If Len(combo_data->edit_text) <= COMBOBOX_MAX_TEXT_BYTES - _
           Len(typed_text) Then
            updated_text = Left(combo_data->edit_text, combo_data->edit_cursor) & _
                typed_text & Mid(combo_data->edit_text, combo_data->edit_cursor + 1)
            desired_cursor = combo_data->edit_cursor + Len(typed_text)
            combobox_NotifyEditText combo_widget, combo_data, updated_text
            combo_data->edit_cursor = desired_cursor
        End If
    End If

    If input_KeyPressEvent(KEY_BACKSPACE) Then
        If combo_data->edit_cursor > 0 Then
            updated_text = Left(combo_data->edit_text, _
                combo_data->edit_cursor - 1) & _
                Mid(combo_data->edit_text, combo_data->edit_cursor + 1)
            desired_cursor = combo_data->edit_cursor - 1
            combobox_NotifyEditText combo_widget, combo_data, updated_text
            combo_data->edit_cursor = desired_cursor
        End If
    ElseIf input_KeyPressEvent(KEY_DELETE) Then
        If combo_data->edit_cursor < Len(combo_data->edit_text) Then
            updated_text = Left(combo_data->edit_text, combo_data->edit_cursor) & _
                Mid(combo_data->edit_text, combo_data->edit_cursor + 2)
            desired_cursor = combo_data->edit_cursor
            combobox_NotifyEditText combo_widget, combo_data, updated_text
            combo_data->edit_cursor = desired_cursor
        End If
    ElseIf combo_data->is_open = 0 AndAlso _
           input_KeyPressEvent(KEY_LEFT) Then
        If combo_data->edit_cursor > 0 Then combo_data->edit_cursor -= 1
    ElseIf combo_data->is_open = 0 AndAlso _
           input_KeyPressEvent(KEY_RIGHT) Then
        If combo_data->edit_cursor < Len(combo_data->edit_text) Then _
            combo_data->edit_cursor += 1
    ElseIf combo_data->is_open = 0 AndAlso _
           input_KeyPressEvent(KEY_HOME) Then
        combo_data->edit_cursor = 0
    ElseIf combo_data->is_open = 0 AndAlso _
           input_KeyPressEvent(KEY_END) Then
        combo_data->edit_cursor = Len(combo_data->edit_text)
    End If
End Sub


Private Function combobox_PointerTarget( _
    ByVal combo_widget As Widget Ptr, _
    ByVal combo_data As ComboBoxData Ptr, _
    ByVal pointer_x As Integer, _
    ByVal pointer_y As Integer _
) As Integer
    Dim As Integer item_index
    Dim As Integer popup_top
    Dim As Integer visible_rows

    If combo_widget = 0 OrElse combo_data = 0 Then _
        Return COMBOBOX_POINTER_OUTSIDE

    If combo_data->simple_mode <> 0 Then
        If pointer_x < combo_widget->ax OrElse _
           pointer_x >= combo_widget->ax + combo_widget->w OrElse _
           pointer_y < combo_widget->ay OrElse _
           pointer_y >= combo_widget->ay + combo_widget->h Then _
            Return COMBOBOX_POINTER_OUTSIDE
        If pointer_y < combo_widget->ay + COMBOBOX_SIMPLE_FIELD_HEIGHT Then _
            Return COMBOBOX_POINTER_EDIT
        visible_rows = combobox_VisibleRows(combo_data, combo_widget)
        If visible_rows <= 0 OrElse _
           pointer_y < combo_widget->ay + COMBOBOX_SIMPLE_FIELD_HEIGHT + _
               COMBOBOX_POPUP_BORDER Then _
            Return COMBOBOX_POINTER_OUTSIDE
        item_index = combo_data->scroll_top + _
            (pointer_y - combo_widget->ay - _
             COMBOBOX_SIMPLE_FIELD_HEIGHT - COMBOBOX_POPUP_BORDER) \ _
                COMBOBOX_ROW_HEIGHT
        If item_index < combo_data->scroll_top OrElse _
           item_index >= combo_data->scroll_top + visible_rows OrElse _
           item_index >= combo_data->item_count Then _
            Return COMBOBOX_POINTER_OUTSIDE
        Return item_index
    End If

    If pointer_x >= combo_widget->ax AndAlso _
       pointer_x < combo_widget->ax + combo_widget->w AndAlso _
       pointer_y >= combo_widget->ay AndAlso _
       pointer_y < combo_widget->ay + combo_widget->h Then
        If combo_data->editable AndAlso _
           pointer_x < combo_widget->ax + combo_widget->w - _
               COMBOBOX_ARROW_WIDTH Then Return COMBOBOX_POINTER_EDIT
        Return COMBOBOX_POINTER_HEADER
    End If

    If combo_data->is_open = 0 Then Return COMBOBOX_POINTER_OUTSIDE
    visible_rows = combobox_VisibleRows(combo_data, combo_widget)
    popup_top = combobox_PopupTop(combo_widget, combo_data)
    If pointer_x < combo_widget->ax OrElse _
       pointer_x >= combo_widget->ax + combo_widget->w OrElse _
       pointer_y < popup_top + COMBOBOX_POPUP_BORDER OrElse _
       pointer_y >= popup_top + COMBOBOX_POPUP_BORDER + _
           visible_rows * COMBOBOX_ROW_HEIGHT Then
        Return COMBOBOX_POINTER_OUTSIDE
    End If

    item_index = combo_data->scroll_top + _
        (pointer_y - popup_top - COMBOBOX_POPUP_BORDER) \ _
            COMBOBOX_ROW_HEIGHT
    If item_index < 0 OrElse item_index >= combo_data->item_count Then _
        Return COMBOBOX_POINTER_OUTSIDE
    Return item_index
End Function

' -------------------------------------------------------------------------
' Input and activation
' -------------------------------------------------------------------------

Sub combobox_Activate(ByVal combo_widget As Widget Ptr)
    Dim As ComboBoxData Ptr combo_data

    If combo_widget = 0 OrElse combo_widget->data = 0 Then Exit Sub
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    If combo_data->simple_mode <> 0 Then Exit Sub
    If combo_data->is_open <> 0 Then
        combobox_SetOpenState combo_widget, combo_data, 0
    Else
        combobox_OpenForUser combo_widget, combo_data
    End If
End Sub


Sub combobox_Update(ByVal combo_widget As Widget Ptr)
    Dim As ComboBoxData Ptr combo_data
    Dim As Integer pointer_buttons
    Dim As Integer pointer_target
    Dim As Integer wheel_rows

    If combo_widget = 0 OrElse combo_widget->data = 0 Then Exit Sub
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    If combo_widget->visible = 0 OrElse combo_widget->enabled = 0 Then
        combobox_CancelInput combo_widget
        Exit Sub
    End If
    If combo_data->simple_mode <> 0 Then
        combo_data->pending_index = combo_data->selected_index
        combobox_ClampScroll combo_data, combo_widget
        combobox_RevealPending combo_widget, combo_data
    End If
    If combo_widget->has_focus = 0 Then _
        combobox_ResetTypeAhead combo_data
    pointer_buttons = input_MouseButtons()
    pointer_target = combobox_PointerTarget( _
        combo_widget, combo_data, input_MouseX(), input_MouseY() _
    )

    If combo_data->is_open <> 0 OrElse combo_data->simple_mode <> 0 Then
        wheel_rows = input_MouseWheel()
        If wheel_rows <> 0 Then
            ' Only the bounded list range matters, even for extreme mock input.
            If wheel_rows > COMBOBOX_MAX_ITEMS Then wheel_rows = COMBOBOX_MAX_ITEMS
            If wheel_rows < -COMBOBOX_MAX_ITEMS Then wheel_rows = -COMBOBOX_MAX_ITEMS
            combo_data->scroll_top -= wheel_rows
            combobox_ClampScroll combo_data, combo_widget
        End If
    End If

    If (pointer_buttons And 1) <> 0 Then
        If combo_data->pointer_latch = 0 Then
            combo_data->pointer_latch = -1
            combo_data->pointer_target = pointer_target
        End If
    ElseIf combo_data->pointer_latch <> 0 Then
        Dim As Integer committed_index = -1
        If combo_data->simple_mode <> 0 Then
            If combo_data->pointer_target >= 0 AndAlso _
               pointer_target = combo_data->pointer_target Then
                committed_index = pointer_target
            ElseIf combo_data->pointer_target = COMBOBOX_POINTER_EDIT AndAlso _
                   pointer_target = COMBOBOX_POINTER_EDIT Then
                combo_data->edit_cursor = Len(combo_data->edit_text)
            End If
        ElseIf combo_data->is_open <> 0 Then
            If combo_data->pointer_target >= 0 AndAlso _
               pointer_target = combo_data->pointer_target Then
                committed_index = pointer_target
                combobox_SetOpenState combo_widget, combo_data, 0
            ElseIf combo_data->pointer_target = COMBOBOX_POINTER_HEADER AndAlso _
                   pointer_target = COMBOBOX_POINTER_HEADER Then
                combobox_SetOpenState combo_widget, combo_data, 0
            ElseIf combo_data->pointer_target = COMBOBOX_POINTER_EDIT AndAlso _
                   pointer_target = COMBOBOX_POINTER_EDIT Then
                combobox_SetOpenState combo_widget, combo_data, 0
                combo_data->edit_cursor = Len(combo_data->edit_text)
            ElseIf combo_data->pointer_target = COMBOBOX_POINTER_OUTSIDE Then
                combobox_SetOpenState combo_widget, combo_data, 0
            End If
        ElseIf combo_data->pointer_target = COMBOBOX_POINTER_HEADER AndAlso _
               pointer_target = COMBOBOX_POINTER_HEADER Then
            combobox_OpenForUser combo_widget, combo_data
        ElseIf combo_data->pointer_target = COMBOBOX_POINTER_EDIT AndAlso _
               pointer_target = COMBOBOX_POINTER_EDIT Then
            ' The portable edit field has no hidden native child. Keep focus
            ' on the ComboBox and place the insertion point at its safe end.
            combo_data->edit_cursor = Len(combo_data->edit_text)
        End If
        combo_data->pointer_latch = 0
        combo_data->pointer_target = COMBOBOX_POINTER_OUTSIDE
        If committed_index >= 0 Then
            ' Complete all private state before notifying. The callback may
            ' release control data, so nothing may dereference it afterward.
            combobox_NotifySelection combo_widget, combo_data, committed_index
            Exit Sub
        End If
    End If

    If combo_widget->has_focus = 0 Then Exit Sub

    combobox_EditTextInput combo_widget, combo_data
    If combo_data->editable = 0 Then
        If combobox_TypeAheadInput(combo_widget, combo_data) <> 0 Then Exit Sub
    End If

    If input_KeyPressEvent(KEY_ESCAPE) <> 0 AndAlso _
       combo_data->is_open <> 0 Then
        combobox_SetOpenState combo_widget, combo_data, 0
        Exit Sub
    End If

    If input_KeyPressEvent(KEY_RETURN) <> 0 OrElse _
       (combo_data->editable = 0 AndAlso _
        input_KeyPressEvent(FB.SC_SPACE) <> 0) Then
        If combo_data->simple_mode <> 0 Then
            Exit Sub
        ElseIf combo_data->is_open <> 0 Then
            Dim As Integer committed_index = combo_data->pending_index
            combobox_SetOpenState combo_widget, combo_data, 0
            combobox_NotifySelection combo_widget, combo_data, committed_index
        Else
            combobox_OpenForUser combo_widget, combo_data
        End If
        Exit Sub
    End If

    If combo_data->item_count = 0 Then Exit Sub
    If input_KeyPressEvent(KEY_UP) <> 0 Then
        If combo_data->is_open <> 0 Then
            If combo_data->pending_index > 0 Then _
                combo_data->pending_index -= 1
            combobox_RevealPending combo_widget, combo_data
        ElseIf combo_data->selected_index > 0 Then
            combobox_NotifySelection _
                combo_widget, combo_data, combo_data->selected_index - 1
        End If
    ElseIf input_KeyPressEvent(KEY_DOWN) <> 0 Then
        If combo_data->is_open <> 0 Then
            If combo_data->pending_index < combo_data->item_count - 1 Then _
                combo_data->pending_index += 1
            combobox_RevealPending combo_widget, combo_data
        ElseIf combo_data->selected_index < combo_data->item_count - 1 Then
            combobox_NotifySelection _
                combo_widget, combo_data, combo_data->selected_index + 1
        End If
    ElseIf input_KeyPressEvent(KEY_HOME) <> 0 Then
        If combo_data->is_open <> 0 Then
            combo_data->pending_index = 0
            combobox_RevealPending combo_widget, combo_data
        Else
            combobox_NotifySelection combo_widget, combo_data, 0
        End If
    ElseIf input_KeyPressEvent(KEY_END) <> 0 Then
        If combo_data->is_open <> 0 Then
            combo_data->pending_index = combo_data->item_count - 1
            combobox_RevealPending combo_widget, combo_data
        Else
            combobox_NotifySelection _
                combo_widget, combo_data, combo_data->item_count - 1
        End If
    End If
End Sub

' -------------------------------------------------------------------------
' Rendering and lifecycle
' -------------------------------------------------------------------------

Sub combobox_Render(ByVal combo_widget As Widget Ptr)
    Dim As ComboBoxData Ptr combo_data
    Dim As Integer arrow_left
    Dim As Integer arrow_middle_x
    Dim As Integer arrow_middle_y
    Dim As Integer item_index
    Dim As Integer popup_height
    Dim As Integer popup_top
    Dim As Integer row_index
    Dim As Integer row_top
    Dim As Integer visible_rows
    Dim As ULong background_color
    Dim As ULong foreground_color
    Dim As String selected_text

    If combo_widget = 0 OrElse combo_widget->data = 0 Then Exit Sub
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    background_color = theme_GetColor(GUI_COLOR_WIDGET_BG)
    foreground_color = theme_GetColor(GUI_COLOR_TEXT)
    If combo_data->background_color_override Then _
        background_color = combo_data->background_color
    If combo_data->foreground_color_override Then _
        foreground_color = combo_data->foreground_color
    If combo_data->editable Then
        selected_text = combo_data->edit_text
    ElseIf combo_data->selected_index >= 0 AndAlso _
       combo_data->selected_index < combo_data->item_count Then
        selected_text = combo_data->items(combo_data->selected_index)
    End If

    If combo_data->simple_mode <> 0 Then
        Dim As Integer field_height = COMBOBOX_SIMPLE_FIELD_HEIGHT
        Dim As Integer row_index
        Dim As Integer row_top
        If field_height > combo_widget->h Then field_height = combo_widget->h

        backend_Rect combo_widget->ax, combo_widget->ay, _
            combo_widget->w, combo_widget->h, background_color, -1
        backend_Rect combo_widget->ax, combo_widget->ay, _
            combo_widget->w, combo_widget->h, _
            theme_GetColor(GUI_COLOR_BORDER), 0
        backend_PrintAligned _
            combo_widget->ax + COMBOBOX_TEXT_INSET, combo_widget->ay, _
            combo_widget->w - COMBOBOX_TEXT_INSET * 2, field_height, _
            foreground_color, selected_text, BACKEND_FONT_DEFAULT, _
            BACKEND_ALIGN_LEFT, BACKEND_ALIGN_MIDDLE

        If combo_data->editable AndAlso combo_widget->has_focus AndAlso _
           Int(Timer * 2) Mod 2 = 0 Then
            Dim As Integer caret_x = combo_widget->ax + _
                COMBOBOX_TEXT_INSET + _
                backend_GetTextWidth(Left( _
                    selected_text, combo_data->edit_cursor))
            If caret_x > combo_widget->ax + combo_widget->w - 2 Then _
                caret_x = combo_widget->ax + combo_widget->w - 2
            backend_Line caret_x, combo_widget->ay + 4, caret_x, _
                combo_widget->ay + field_height - 5, foreground_color
        End If

        If combo_widget->h > field_height Then
            backend_Line combo_widget->ax + 1, _
                combo_widget->ay + field_height, _
                combo_widget->ax + combo_widget->w - 2, _
                combo_widget->ay + field_height, _
                theme_GetColor(GUI_COLOR_BORDER)
            visible_rows = combobox_VisibleRows(combo_data, combo_widget)
            For row_index = 0 To visible_rows - 1
                item_index = combo_data->scroll_top + row_index
                If item_index < 0 OrElse _
                   item_index >= combo_data->item_count Then Exit For
                row_top = combo_widget->ay + field_height + _
                    COMBOBOX_POPUP_BORDER + row_index * _
                        COMBOBOX_ROW_HEIGHT
                If item_index = combo_data->selected_index Then
                    backend_Rect combo_widget->ax + _
                        COMBOBOX_POPUP_BORDER, row_top, _
                        combo_widget->w - COMBOBOX_POPUP_BORDER * 2, _
                        COMBOBOX_ROW_HEIGHT, _
                        theme_GetColor(GUI_COLOR_SELECT_BG), -1
                    backend_PrintAligned _
                        combo_widget->ax + COMBOBOX_TEXT_INSET, row_top, _
                        combo_widget->w - COMBOBOX_TEXT_INSET * 2, _
                        COMBOBOX_ROW_HEIGHT, _
                        theme_GetColor(GUI_COLOR_SELECT_TEXT), _
                        combo_data->items(item_index), _
                        BACKEND_FONT_DEFAULT, BACKEND_ALIGN_LEFT, _
                        BACKEND_ALIGN_MIDDLE
                Else
                    backend_PrintAligned _
                        combo_widget->ax + COMBOBOX_TEXT_INSET, row_top, _
                        combo_widget->w - COMBOBOX_TEXT_INSET * 2, _
                        COMBOBOX_ROW_HEIGHT, foreground_color, _
                        combo_data->items(item_index), _
                        BACKEND_FONT_DEFAULT, BACKEND_ALIGN_LEFT, _
                        BACKEND_ALIGN_MIDDLE
                End If
            Next row_index
        End If
        Exit Sub
    End If

    arrow_left = combo_widget->ax + combo_widget->w - COMBOBOX_ARROW_WIDTH

    backend_Rect combo_widget->ax, combo_widget->ay, _
        combo_widget->w, combo_widget->h, _
        background_color, -1
    backend_Rect combo_widget->ax, combo_widget->ay, _
        combo_widget->w, combo_widget->h, _
        theme_GetColor(GUI_COLOR_BORDER), 0
    backend_Rect arrow_left, combo_widget->ay, COMBOBOX_ARROW_WIDTH, _
        combo_widget->h, current_theme.bg_face, -1
    backend_Rect arrow_left, combo_widget->ay, COMBOBOX_ARROW_WIDTH, _
        combo_widget->h, theme_GetColor(GUI_COLOR_BORDER), 0

    backend_PrintAligned _
        combo_widget->ax + COMBOBOX_TEXT_INSET, combo_widget->ay, _
        combo_widget->w - COMBOBOX_ARROW_WIDTH - COMBOBOX_TEXT_INSET * 2, _
        combo_widget->h, foreground_color, selected_text, _
        BACKEND_FONT_DEFAULT, BACKEND_ALIGN_LEFT, BACKEND_ALIGN_MIDDLE

    If combo_data->editable AndAlso combo_widget->has_focus AndAlso _
       combo_data->is_open = 0 AndAlso Int(Timer * 2) Mod 2 = 0 Then
        Dim As Integer caret_x = combo_widget->ax + COMBOBOX_TEXT_INSET + _
            backend_GetTextWidth(Left(selected_text, combo_data->edit_cursor))
        If caret_x > arrow_left - 2 Then caret_x = arrow_left - 2
        backend_Line caret_x, combo_widget->ay + 4, caret_x, _
            combo_widget->ay + combo_widget->h - 5, foreground_color
    End If

    arrow_middle_x = arrow_left + COMBOBOX_ARROW_WIDTH \ 2
    arrow_middle_y = combo_widget->ay + combo_widget->h \ 2
    backend_Line arrow_middle_x - 4, arrow_middle_y - 2, _
        arrow_middle_x + 4, arrow_middle_y - 2, _
        theme_GetColor(GUI_COLOR_TEXT)
    backend_Line arrow_middle_x - 3, arrow_middle_y - 1, _
        arrow_middle_x + 3, arrow_middle_y - 1, _
        theme_GetColor(GUI_COLOR_TEXT)
    backend_Line arrow_middle_x - 2, arrow_middle_y, _
        arrow_middle_x + 2, arrow_middle_y, _
        theme_GetColor(GUI_COLOR_TEXT)
    backend_Line arrow_middle_x - 1, arrow_middle_y + 1, _
        arrow_middle_x + 1, arrow_middle_y + 1, _
        theme_GetColor(GUI_COLOR_TEXT)

    If combo_data->is_open = 0 Then Exit Sub
    visible_rows = combobox_VisibleRows(combo_data, combo_widget)
    popup_height = combobox_PopupHeight(combo_data)
    popup_top = combobox_PopupTop(combo_widget, combo_data)
    backend_Rect combo_widget->ax, popup_top, combo_widget->w, popup_height, _
        background_color, -1
    backend_Rect combo_widget->ax, popup_top, combo_widget->w, popup_height, _
        theme_GetColor(GUI_COLOR_BORDER), 0

    For row_index = 0 To visible_rows - 1
        item_index = combo_data->scroll_top + row_index
        If item_index < 0 OrElse item_index >= combo_data->item_count Then _
            Exit For
        row_top = popup_top + COMBOBOX_POPUP_BORDER + _
            row_index * COMBOBOX_ROW_HEIGHT
        If item_index = combo_data->pending_index Then
            backend_Rect combo_widget->ax + COMBOBOX_POPUP_BORDER, row_top, _
                combo_widget->w - COMBOBOX_POPUP_BORDER * 2, _
                COMBOBOX_ROW_HEIGHT, theme_GetColor(GUI_COLOR_SELECT_BG), -1
            backend_PrintAligned _
                combo_widget->ax + COMBOBOX_TEXT_INSET, row_top, _
                combo_widget->w - COMBOBOX_TEXT_INSET * 2, _
                COMBOBOX_ROW_HEIGHT, theme_GetColor(GUI_COLOR_SELECT_TEXT), _
                combo_data->items(item_index), BACKEND_FONT_DEFAULT, _
                BACKEND_ALIGN_LEFT, BACKEND_ALIGN_MIDDLE
        Else
            backend_PrintAligned _
                combo_widget->ax + COMBOBOX_TEXT_INSET, row_top, _
                combo_widget->w - COMBOBOX_TEXT_INSET * 2, _
                COMBOBOX_ROW_HEIGHT, foreground_color, _
                combo_data->items(item_index), BACKEND_FONT_DEFAULT, _
                BACKEND_ALIGN_LEFT, BACKEND_ALIGN_MIDDLE
        End If
    Next row_index
End Sub


Sub combobox_Destroy(ByVal combo_widget As Widget Ptr)
    If combo_widget = 0 Then Exit Sub
    If combo_widget->data <> 0 Then _
        Delete Cast(ComboBoxData Ptr, combo_widget->data)
    combo_widget->data = 0
End Sub


Function combobox_Create( _
    ByVal widget_name As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal combo_width As Integer, _
    ByVal combo_height As Integer, _
    ByVal maximum_rows As Integer, _
    ByVal change_handler As Any Ptr _
) As Widget Ptr
    Dim As ComboBoxData Ptr combo_data
    Dim As Widget Ptr combo_widget

    If maximum_rows < 1 OrElse _
       maximum_rows > COMBOBOX_MAX_VISIBLE_ROWS Then Return 0
    If combo_width < COMBOBOX_MINIMUM_WIDTH Then _
        combo_width = COMBOBOX_MINIMUM_WIDTH
    If combo_height < COMBOBOX_MINIMUM_HEIGHT Then _
        combo_height = COMBOBOX_MINIMUM_HEIGHT

    combo_widget = New Widget
    combo_data = New ComboBoxData
    If combo_widget = 0 OrElse combo_data = 0 Then
        If combo_widget <> 0 Then Delete combo_widget
        If combo_data <> 0 Then Delete combo_data
        Return 0
    End If

    combo_widget->name = widget_name
    combo_widget->x = left_position
    combo_widget->y = top_position
    combo_widget->w = combo_width
    combo_widget->h = combo_height
    combo_widget->visible = -1
    combo_widget->enabled = -1
    combo_widget->accepts_focus = -1
    combo_widget->captures_return = -1
    combo_widget->render = @combobox_Render
    combo_widget->update = @combobox_Update
    combo_widget->activate = @combobox_Activate
    combo_widget->destroy = @combobox_Destroy
    combo_widget->cancel_input = @combobox_CancelInput
    combo_data->selected_index = -1
    combo_data->pending_index = -1
    combo_data->scroll_top = 0
    combo_data->maximum_rows = maximum_rows
    combo_data->pointer_target = COMBOBOX_POINTER_OUTSIDE
    combo_data->change_handler = change_handler
    combo_data->background_color_override = 0
    combo_data->foreground_color_override = 0
    combo_data->editable = 0
    combo_data->simple_mode = 0
    combo_data->edit_text = ""
    combo_data->edit_cursor = 0
    combo_data->type_ahead_text = ""
    combo_data->type_ahead_clock = 0.0
    combo_data->type_ahead_clock_initialized = 0
    combo_widget->data = combo_data
    Return combo_widget
End Function

' -------------------------------------------------------------------------
' Public item and state API
' -------------------------------------------------------------------------

Function combobox_AddItem( _
    ByVal combo_widget As Widget Ptr, _
    ByRef item_text As Const String _
) As Integer
    Return combobox_InsertItem(combo_widget, item_text)
End Function

Sub combobox_CancelInput(ByVal combo_widget As Widget Ptr)
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Exit Sub
    Dim As ComboBoxData Ptr combo_data = combo_widget->data
    combobox_SetOpenState combo_widget, combo_data, 0
    combo_data->pointer_latch = IIf(input_UnmaskedMouseButtons() And 1, -1, 0)
    combo_data->pointer_target = COMBOBOX_POINTER_OUTSIDE
End Sub

Function combobox_InsertItem( _
    ByVal combo_widget As Widget Ptr, ByRef item_text As Const String, _
    ByVal item_index As Integer _
) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    Dim As ComboBoxData Ptr combo_data = combo_widget->data
    If combo_data->item_count < 0 OrElse combo_data->item_count >= COMBOBOX_MAX_ITEMS Then Return 0
    If item_index = -1 Then item_index = combo_data->item_count
    If item_index < 0 OrElse item_index > combo_data->item_count Then Return 0
    Dim As Integer stored_bytes = Len(item_text)
    If stored_bytes > COMBOBOX_MAX_TEXT_BYTES Then Return 0
    For index_value As Integer = 0 To combo_data->item_count - 1
        If Len(combo_data->items(index_value)) > COMBOBOX_MAX_TEXT_BYTES - stored_bytes Then Return 0
        stored_bytes += Len(combo_data->items(index_value))
    Next index_value
    ' The caller may pass one of our own item strings. Preserve it before the
    ' shift, and complete validation before changing anything in the widget.
    Dim As String retained_text = item_text
    For index_value As Integer = combo_data->item_count To item_index + 1 Step -1
        combo_data->items(index_value) = combo_data->items(index_value - 1)
        combo_data->item_data(index_value) = combo_data->item_data(index_value - 1)
    Next index_value
    combo_data->items(item_index) = retained_text
    combo_data->item_data(item_index) = 0
    combo_data->item_count += 1
    If combo_data->selected_index >= item_index Then combo_data->selected_index += 1
    combobox_CancelInput combo_widget
    combobox_ClampScroll combo_data, combo_widget
    Return -1
End Function

Function combobox_RemoveItem(ByVal combo_widget As Widget Ptr, ByVal item_index As Integer) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    Dim As ComboBoxData Ptr combo_data = combo_widget->data
    If combo_data->item_count < 0 OrElse combo_data->item_count > COMBOBOX_MAX_ITEMS OrElse _
       item_index < 0 OrElse item_index >= combo_data->item_count Then Return 0
    For index_value As Integer = item_index To combo_data->item_count - 2
        combo_data->items(index_value) = combo_data->items(index_value + 1)
        combo_data->item_data(index_value) = combo_data->item_data(index_value + 1)
    Next index_value
    combo_data->item_count -= 1
    combo_data->items(combo_data->item_count) = ""
    combo_data->item_data(combo_data->item_count) = 0
    If combo_data->selected_index = item_index Then
        combo_data->selected_index = -1
    ElseIf combo_data->selected_index > item_index Then
        combo_data->selected_index -= 1
    End If
    combobox_CancelInput combo_widget
    combobox_ClampScroll combo_data, combo_widget
    Return -1
End Function

Function combobox_GetItem( _
    ByVal combo_widget As Widget Ptr, ByVal item_index As Integer, ByRef item_text As String _
) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then
        item_text = ""
        Return 0
    End If
    Dim As ComboBoxData Ptr combo_data = combo_widget->data
    If combo_data->item_count < 0 OrElse combo_data->item_count > COMBOBOX_MAX_ITEMS OrElse _
       item_index < 0 OrElse item_index >= combo_data->item_count Then
        item_text = ""
        Return 0
    End If
    item_text = combo_data->items(item_index)
    Return -1
End Function

Function combobox_GetItemCount(ByVal combo_widget As Widget Ptr) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    Return Cast(ComboBoxData Ptr, combo_widget->data)->item_count
End Function

Function combobox_GetActivationCount(ByVal combo_widget As Widget Ptr) As ULongInt
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    Return Cast(ComboBoxData Ptr, combo_widget->data)->activation_count
End Function


Function combobox_GetDropDownCount(ByVal combo_widget As Widget Ptr) As ULongInt
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    Return Cast(ComboBoxData Ptr, combo_widget->data)->dropdown_count
End Function


Function combobox_SetBackgroundColor( _
    ByVal combo_widget As Widget Ptr, _
    ByVal color_value As ULong _
) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    With *Cast(ComboBoxData Ptr, combo_widget->data)
        .background_color = color_value
        .background_color_override = -1
    End With
    Return -1
End Function


Function combobox_ClearBackgroundColor( _
    ByVal combo_widget As Widget Ptr _
) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    Cast(ComboBoxData Ptr, combo_widget->data)->background_color_override = 0
    Return -1
End Function


Function combobox_GetBackgroundColor( _
    ByVal combo_widget As Widget Ptr, _
    ByRef color_value As ULong _
) As Integer
    Dim As ComboBoxData Ptr combo_data

    color_value = 0
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    If combo_data->background_color_override = 0 Then Return 0
    color_value = combo_data->background_color
    Return -1
End Function


Function combobox_SetForegroundColor( _
    ByVal combo_widget As Widget Ptr, _
    ByVal color_value As ULong _
) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    With *Cast(ComboBoxData Ptr, combo_widget->data)
        .foreground_color = color_value
        .foreground_color_override = -1
    End With
    Return -1
End Function


Function combobox_ClearForegroundColor( _
    ByVal combo_widget As Widget Ptr _
) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    Cast(ComboBoxData Ptr, combo_widget->data)->foreground_color_override = 0
    Return -1
End Function


Function combobox_GetForegroundColor( _
    ByVal combo_widget As Widget Ptr, _
    ByRef color_value As ULong _
) As Integer
    Dim As ComboBoxData Ptr combo_data

    color_value = 0
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    If combo_data->foreground_color_override = 0 Then Return 0
    color_value = combo_data->foreground_color
    Return -1
End Function


Function combobox_SetItem( _
    ByVal combo_widget As Widget Ptr, ByVal item_index As Integer, ByRef item_text As Const String _
) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    Dim As ComboBoxData Ptr combo_data = combo_widget->data
    If combo_data->item_count < 0 OrElse combo_data->item_count > COMBOBOX_MAX_ITEMS OrElse _
       item_index < 0 OrElse item_index >= combo_data->item_count Then Return 0
    Dim As Integer stored_bytes = Len(item_text)
    If stored_bytes > COMBOBOX_MAX_TEXT_BYTES Then Return 0
    For index_value As Integer = 0 To combo_data->item_count - 1
        If index_value = item_index Then Continue For
        If Len(combo_data->items(index_value)) > COMBOBOX_MAX_TEXT_BYTES - stored_bytes Then Return 0
        stored_bytes += Len(combo_data->items(index_value))
    Next index_value
    Dim As String retained_text = item_text
    combo_data->items(item_index) = retained_text
    combobox_ResetTypeAhead combo_data
    ' Editing a label does not commit a choice or close its popup. Consume a
    ' held press so its release cannot select newly substituted content.
    combo_data->pointer_latch = IIf(input_UnmaskedMouseButtons() And 1, -1, 0)
    combo_data->pointer_target = COMBOBOX_POINTER_OUTSIDE
    Return -1
End Function

Function combobox_SetItemData( _
    ByVal combo_widget As Widget Ptr, ByVal item_index As Integer, ByVal data_value As LongInt _
) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    Dim As ComboBoxData Ptr combo_data = combo_widget->data
    If combo_data->item_count < 0 OrElse combo_data->item_count > COMBOBOX_MAX_ITEMS OrElse _
       item_index < 0 OrElse item_index >= combo_data->item_count Then Return 0
    combo_data->item_data(item_index) = data_value
    Return -1
End Function

Function combobox_GetItemData( _
    ByVal combo_widget As Widget Ptr, ByVal item_index As Integer, ByRef data_value As LongInt _
) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then
        data_value = 0
        Return 0
    End If
    Dim As ComboBoxData Ptr combo_data = combo_widget->data
    If combo_data->item_count < 0 OrElse combo_data->item_count > COMBOBOX_MAX_ITEMS OrElse _
       item_index < 0 OrElse item_index >= combo_data->item_count Then
        data_value = 0
        Return 0
    End If
    data_value = combo_data->item_data(item_index)
    Return -1
End Function

Sub combobox_Clear(ByVal combo_widget As Widget Ptr)
    Dim As ComboBoxData Ptr combo_data
    Dim As Integer item_index

    If combo_widget = 0 OrElse combo_widget->data = 0 Then Exit Sub
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    Dim As Integer retained_count = combo_data->item_count
    If retained_count > COMBOBOX_MAX_ITEMS Then retained_count = COMBOBOX_MAX_ITEMS
    For item_index = 0 To retained_count - 1
        combo_data->items(item_index) = ""
        combo_data->item_data(item_index) = 0
    Next item_index
    combo_data->item_count = 0
    combo_data->selected_index = -1
    combo_data->pending_index = -1
    combo_data->scroll_top = 0
    If combo_data->editable Then
        combo_data->edit_text = ""
        combo_data->edit_cursor = 0
    End If
    combobox_CancelInput combo_widget
End Sub


Function combobox_GetSelectedIndex( _
    ByVal combo_widget As Widget Ptr _
) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return -1
    Return Cast(ComboBoxData Ptr, combo_widget->data)->selected_index
End Function


Function combobox_GetSelectedItem( _
    ByVal combo_widget As Widget Ptr _
) As String
    Dim As ComboBoxData Ptr combo_data

    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return ""
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    If combo_data->selected_index < 0 OrElse _
       combo_data->selected_index >= combo_data->item_count Then Return ""
    Return combo_data->items(combo_data->selected_index)
End Function


Function combobox_SetSelectedIndex( _
    ByVal combo_widget As Widget Ptr, _
    ByVal selected_index As Integer _
) As Integer
    Dim As ComboBoxData Ptr combo_data

    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    If selected_index < -1 OrElse _
       selected_index >= combo_data->item_count Then Return 0

    combo_data->selected_index = selected_index
    combo_data->pending_index = selected_index
    combobox_ResetTypeAhead combo_data
    If combo_data->editable Then
        combo_data->edit_text = ""
        If selected_index >= 0 Then _
            combo_data->edit_text = combo_data->items(selected_index)
        combo_data->edit_cursor = Len(combo_data->edit_text)
    End If
    combobox_RevealPending combo_widget, combo_data
    Return -1
End Function


Function combobox_SetOpen( _
    ByVal combo_widget As Widget Ptr, _
    ByVal open_state As Integer _
) As Integer
    Dim As ComboBoxData Ptr combo_data

    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    If combo_data->simple_mode <> 0 Then Return -1
    If open_state <> 0 AndAlso combo_data->item_count = 0 Then Return 0
    combobox_SetOpenState combo_widget, combo_data, open_state
    Return -1
End Function


Function combobox_IsOpen( _
    ByVal combo_widget As Widget Ptr _
) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    Dim As ComboBoxData Ptr combo_data = combo_widget->data
    Return IIf(combo_data->simple_mode <> 0, -1, combo_data->is_open)
End Function


Function combobox_SetEditable( _
    ByVal combo_widget As Widget Ptr, _
    ByVal editable_state As Integer _
) As Integer
    Dim As ComboBoxData Ptr combo_data

    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    editable_state = IIf(editable_state <> 0, -1, 0)
    If combo_data->editable = editable_state AndAlso _
       combo_data->simple_mode = 0 Then Return -1
    combo_data->simple_mode = 0
    combo_data->editable = editable_state
    combobox_ResetTypeAhead combo_data
    If combo_data->editable Then
        combo_data->edit_text = ""
        If combo_data->selected_index >= 0 AndAlso _
           combo_data->selected_index < combo_data->item_count Then _
            combo_data->edit_text = _
                combo_data->items(combo_data->selected_index)
        combo_data->edit_cursor = Len(combo_data->edit_text)
    End If
    Return -1
End Function


Function combobox_IsEditable( _
    ByVal combo_widget As Widget Ptr _
) As Integer
    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    Return Cast(ComboBoxData Ptr, combo_widget->data)->editable
End Function


Function combobox_SetStyle( _
    ByVal combo_widget As Widget Ptr, _
    ByVal style_value As Integer _
) As Integer
    Dim As ComboBoxData Ptr combo_data
    Dim As Integer editable_state

    If combo_widget = 0 OrElse combo_widget->data = 0 OrElse _
       style_value < 0 OrElse style_value > 2 Then Return 0
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    If style_value = 1 Then
        If combobox_SetEditable(combo_widget, -1) = 0 Then Return 0
        combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
        combo_data->simple_mode = -1
        combo_data->is_open = 0
        combo_widget->pointer_global = 0
        combo_widget->captures_escape = 0
        combo_data->pending_index = combo_data->selected_index
        combobox_RevealPending combo_widget, combo_data
    Else
        If style_value = 0 Then editable_state = -1
        If combobox_SetEditable(combo_widget, editable_state) = 0 Then _
            Return 0
        combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
        combo_data->simple_mode = 0
        combobox_SetOpenState combo_widget, combo_data, 0
    End If
    Return -1
End Function


Function combobox_GetStyle( _
    ByVal combo_widget As Widget Ptr _
) As Integer
    Dim As ComboBoxData Ptr combo_data

    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return -1
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    If combo_data->simple_mode <> 0 Then Return 1
    If combo_data->editable <> 0 Then Return 0
    Return 2
End Function


Function combobox_GetText( _
    ByVal combo_widget As Widget Ptr _
) As String
    Dim As ComboBoxData Ptr combo_data

    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return ""
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    If combo_data->editable Then Return combo_data->edit_text
    Return combobox_GetSelectedItem(combo_widget)
End Function


Function combobox_SetText( _
    ByVal combo_widget As Widget Ptr, _
    ByRef text_value As Const String _
) As Integer
    Dim As ComboBoxData Ptr combo_data
    Dim As String filtered_text

    If combo_widget = 0 OrElse combo_widget->data = 0 Then Return 0
    combo_data = Cast(ComboBoxData Ptr, combo_widget->data)
    filtered_text = combobox_FilterEditText(text_value)
    If Len(filtered_text) <> Len(text_value) OrElse _
       Len(filtered_text) > COMBOBOX_MAX_TEXT_BYTES Then Return 0
    If combo_data->editable = 0 Then
        Dim As Integer selected_index = _
            combobox_ExactItemIndex(combo_data, filtered_text)
        If selected_index < 0 Then Return 0
        Return combobox_SetSelectedIndex(combo_widget, selected_index)
    End If
    combo_data->edit_text = filtered_text
    combo_data->edit_cursor = Len(combo_data->edit_text)
    combo_data->selected_index = _
        combobox_ExactItemIndex(combo_data, combo_data->edit_text)
    combo_data->pending_index = combo_data->selected_index
    Return -1
End Function

/' end of combobox.bas '/
