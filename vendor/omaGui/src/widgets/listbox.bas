/'
    Project: omaGUI
    ---------------

    File: listbox.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements listbox.bi; declarations there define the interface.

    Purpose:
        Implement a bounded, selectable, scrolling list control.

    Responsibilities:
        - render list rows and vertical or horizontal scrolling columns
        - select pointer rows once on release inside the pressed row
        - recognize two timely releases on the same row as a double activation
        - select rows through edge-triggered keyboard input
        - scroll through the wheel, keyboard, or scrollbar
        - keep programmatic selections visible and range checked
        - render optional normal client and text colors

    This file intentionally does NOT contain:
        - filesystem enumeration
        - application-specific list commands
        - global input dispatch policy
'/

#lang "fb"
#include once "src/widgets/listbox.bi"
#include once "src/widgets/scrollbar.bi"
#include once "src/widgets/menu.bi"
#include once "src/widgets/checkbox.bi"
#include once "src/backend/theme.bi"

#ifdef OMAGUI_NAVIGATION_EXTENSIONS
Const LISTBOX_SCROLLBAR_WIDTH As Integer = 28 ' Touch profile uses fingertip-sized thumbs.
#else
Const LISTBOX_SCROLLBAR_WIDTH As Integer = 15
#endif
Const LISTBOX_ROW_HEIGHT As Integer = 16
Const LISTBOX_CLIP_INSET As Integer = 1
Const LISTBOX_TEXT_X_OFFSET As Integer = 4
Const LISTBOX_TEXT_Y_OFFSET As Integer = 2
Const LISTBOX_WHEEL_ROWS As Integer = 3
Const LISTBOX_KEY_UP_BIT As Integer = 1
Const LISTBOX_KEY_DOWN_BIT As Integer = 2
Const LISTBOX_KEY_HOME_BIT As Integer = 4
Const LISTBOX_KEY_END_BIT As Integer = 8
Const LISTBOX_KEY_PAGE_UP_BIT As Integer = 16
Const LISTBOX_KEY_PAGE_DOWN_BIT As Integer = 32
Const LISTBOX_KEY_ENTER_BIT As Integer = 64
Const LISTBOX_KEY_LEFT_BIT As Integer = 256
Const LISTBOX_KEY_RIGHT_BIT As Integer = 512
Const LISTBOX_KEY_NAVIGATION_BITS As Integer = 831 ' Up through Page Down, Left and Right.
Const LISTBOX_KEY_SPACE_BIT As Integer = 128
Const LISTBOX_DOUBLE_CLICK_SECONDS As Double = 0.5
Const LISTBOX_SECONDS_PER_DAY As Double = 86400.0
Const LISTBOX_HEADER_HEIGHT As Integer = 20
Const LISTBOX_NAVIGATION_ROW_HEIGHT As Integer = 18
Const LISTBOX_DROPDOWN_HEIGHT As Integer = 24

Private Function listbox_RowHeight(ByVal d As ListBoxData Ptr) As Integer
    If d->row_height > 0 Then Return d->row_height
    If d->navigation_style Then Return LISTBOX_NAVIGATION_ROW_HEIGHT
    Return LISTBOX_ROW_HEIGHT
End Function

Private Function listbox_HeaderHeight(ByVal d As ListBoxData Ptr) As Integer
    If d->table_column_count > 0 Then Return LISTBOX_HEADER_HEIGHT
    Return 0
End Function

#include once "src/widgets/listbox_layout.bi"

Private Sub listbox_DropdownSelect(ByVal context As Any Ptr, ByVal itemIndex As Integer)
    Dim As Widget Ptr w = Cast(Widget Ptr, context)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As ListBoxData Ptr d = Cast(ListBoxData Ptr, w->data)
    If itemIndex < 0 OrElse itemIndex >= d->item_count Then Exit Sub
    listbox_SetSelectedIndex w, itemIndex
    gui_SetFocus w
End Sub


Private Sub listbox_OpenDropdown(ByVal w As Widget Ptr)
    Dim As ListBoxData Ptr d = Cast(ListBoxData Ptr, w->data)
    If d->item_count < 1 OrElse d->item_count > MENU_MAX_ITEMS Then Exit Sub
    If d->dropdown_popup = 0 Then
        d->dropdown_popup = menu_Create(w->name & "_choices", 0, w->h)
        If d->dropdown_popup = 0 Then Exit Sub
        gui_AddGeneratedWidget d->dropdown_popup
        gui_SetParent d->dropdown_popup, w
        menu_SetSelectionHandler d->dropdown_popup, @listbox_DropdownSelect, w
    End If
    menu_ClearItems d->dropdown_popup
    menu_SetItemHeight d->dropdown_popup, LISTBOX_HEADER_HEIGHT
    For itemIndex As Integer = 0 To d->item_count - 1
        menu_AddItem d->dropdown_popup, d->items(itemIndex), 0
    Next itemIndex
    d->dropdown_popup->w = w->w
    d->dropdown_popup->y = w->h
    Dim As Integer screenWidth, screenHeight, bottomLimit
    backend_GetSize screenWidth, screenHeight
    bottomLimit = screenHeight
    Dim As Widget Ptr parentWidget = w->parent
    While parentWidget <> 0
        If parentWidget->clip_children Then
            Dim As Integer parentBottom = parentWidget->ay + parentWidget->h - parentWidget->child_clip_bottom
            If parentBottom < bottomLimit Then bottomLimit = parentBottom
        End If
        parentWidget = parentWidget->parent
    Wend
    If w->ay + w->h + d->dropdown_popup->h > bottomLimit Then _
        d->dropdown_popup->y = -d->dropdown_popup->h
    menu_ShowAt d->dropdown_popup, w->ax, w->ay + d->dropdown_popup->y, -1
    Dim As MenuData Ptr popupData = Cast(MenuData Ptr, d->dropdown_popup->data)
    If popupData <> 0 AndAlso d->selected_index >= 0 AndAlso _
       d->selected_index < d->item_count Then
        popupData->selected = d->selected_index
        If popupData->selected >= popupData->visible_rows AndAlso popupData->visible_rows > 0 Then _
            popupData->scroll_top = popupData->selected - popupData->visible_rows + 1
    End If
End Sub


Private Sub listbox_DropdownUpdate(ByVal w As Widget Ptr)
    Dim As ListBoxData Ptr d = Cast(ListBoxData Ptr, w->data)
    Dim As Integer mouseDown = input_MouseButtons() And 1
    Dim As Integer inside = IIf(input_MouseX() >= w->ax AndAlso _
        input_MouseX() < w->ax + w->w AndAlso input_MouseY() >= w->ay AndAlso _
        input_MouseY() < w->ay + w->h, -1, 0)
    If mouseDown <> 0 AndAlso inside <> 0 Then
        d->pointer_latch = -1
    ElseIf mouseDown = 0 AndAlso d->pointer_latch <> 0 Then
        d->pointer_latch = 0
        If inside <> 0 Then listbox_OpenDropdown w
    End If
    If w->has_focus = 0 Then Exit Sub
    If input_ModifiedKeyPressEvent(KEY_UP, INPUT_MODIFIER_NONE) Then
        If d->selected_index > 0 Then listbox_SetSelectedIndex w, d->selected_index - 1
    ElseIf input_ModifiedKeyPressEvent(KEY_DOWN, INPUT_MODIFIER_NONE) Then
        If d->selected_index < d->item_count - 1 Then listbox_SetSelectedIndex w, d->selected_index + 1
    End If
    If input_ModifiedKeyPressEvent(KEY_DOWN, INPUT_MODIFIER_ALT) OrElse _
       input_ModifiedKeyPressEvent(FB.SC_SPACE, INPUT_MODIFIER_NONE) Then _
        listbox_OpenDropdown w
End Sub


Private Sub listbox_DropdownRender(ByVal w As Widget Ptr)
    If w->w <= 26 OrElse w->h <= 2 Then Exit Sub
    Dim As ULong borderColor = current_theme.win_border
    If w->has_focus Then borderColor = current_theme.bg_select
    backend_Rect w->ax, w->ay, w->w, w->h, current_theme.bg_widget, 1
    backend_Rect w->ax, w->ay, w->w, w->h, borderColor, 0
    backend_SetClip w->ax + 4, w->ay + 1, w->w - 26, w->h - 2
    backend_Print w->ax + 4, w->ay + (w->h - backend_GetTextHeight()) \ 2, _
        current_theme.text_main, listbox_GetSelectedItem(w)
    backend_ResetClip
    Dim As Integer arrowX = w->ax + w->w - 12
    Dim As Integer arrowY = w->ay + w->h \ 2
    backend_Line arrowX - 3, arrowY - 2, arrowX, arrowY + 1, current_theme.bg_dark
    backend_Line arrowX, arrowY + 1, arrowX + 3, arrowY - 2, current_theme.bg_dark
End Sub

' -------------------------------------------------------------------------
' Private state helpers
' -------------------------------------------------------------------------

Private Sub listbox_SynchronizeScrollbar(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As ListBoxData Ptr listData = Cast(ListBoxData Ptr, w->data)
    If listData->scrollbar = 0 Then Exit Sub
    ' This scrollbar is owned by the list rather than registered as a GUI
    ' child. Both input and rendering must synchronize its absolute rectangle.
    ' Rendering may be the first call after construction, moving, or resizing.
    With *listData->scrollbar
        If listData->column_count > 0 Then
            .ax = w->ax
            .ay = w->ay + listbox_ClientHeight(w)
            .w = w->w
            .h = LISTBOX_SCROLLBAR_WIDTH
            If .h > w->h Then .h = w->h
        Else
            .ax = w->ax + w->w - LISTBOX_SCROLLBAR_WIDTH
            .ay = w->ay + listbox_HeaderHeight(listData)
            .w = LISTBOX_SCROLLBAR_WIDTH
            .h = w->h - listbox_HeaderHeight(listData)
        End If
    End With
End Sub

Private Sub listbox_ClampScroll(ByVal w As Widget Ptr)
    Dim As ListBoxData Ptr listData
    Dim As ScrollBarData Ptr scrollData
    Dim As Integer maximumScroll
    Dim As Integer visibleCount

    If w = 0 OrElse w->data = 0 Then Exit Sub

    listData = Cast(ListBoxData Ptr, w->data)
    visibleCount = listbox_RowsPerColumn(w)
    Dim As Integer scroll_units = listData->scroll_top
    Dim As Integer rows_per_column = visibleCount
    If listData->column_count > 0 Then
        maximumScroll = (listData->item_count + rows_per_column - 1) \ rows_per_column - listbox_VisibleColumns(w)
        visibleCount = listbox_VisibleColumns(w)
        scroll_units = listData->scroll_top \ rows_per_column
    Else
        maximumScroll = listData->item_count - visibleCount
    End If
    If maximumScroll < 0 Then maximumScroll = 0

    If scroll_units < 0 Then scroll_units = 0
    If scroll_units > maximumScroll Then scroll_units = maximumScroll
    listData->scroll_top = scroll_units
    If listData->column_count > 0 Then listData->scroll_top *= rows_per_column

    If listData->scrollbar <> 0 AndAlso _
       listData->scrollbar->data <> 0 Then
        scrollData = Cast(ScrollBarData Ptr, listData->scrollbar->data)
        scrollData->max_val = maximumScroll
        scrollData->page_size = visibleCount
        scrollData->value = scroll_units
        scrollData->vertical = IIf(listData->column_count > 0, 0, -1)
    End If
End Sub


Private Sub listbox_ReadKeyState( _
    ByVal keyCode As Integer, _
    ByVal keyBit As Integer, _
    ByRef heldState As Integer, _
    ByRef pressState As Integer _
)
    If input_KeyPressed(keyCode) <> 0 Then heldState Or= keyBit
    If input_KeyPressEvent(keyCode) <> 0 Then pressState Or= keyBit
End Sub


Private Sub listbox_ClearDoubleClick(ByVal d As ListBoxData Ptr)
    If d = 0 Then Exit Sub
    d->double_click_armed = 0
    d->double_click_index = -1
    d->double_click_clock = 0.0
End Sub

#include once "src/widgets/listbox_selection.bi"


Private Sub listbox_RecordPointerActivation( _
    ByVal d As ListBoxData Ptr, ByVal item_index As Integer _
)
    Dim As Double clock_now
    Dim As Double elapsed_seconds

    If d = 0 OrElse item_index < 0 OrElse item_index >= d->item_count Then
        listbox_ClearDoubleClick d
        Exit Sub
    End If

    d->activation_count += 1
    clock_now = CDbl(Timer)
    If d->double_click_armed AndAlso d->double_click_index = item_index Then
        elapsed_seconds = clock_now - d->double_click_clock
        ' TIMER is portable but wraps at midnight. A backward wall-clock jump
        ' larger than one day cannot be a continuation of a pointer gesture.
        If elapsed_seconds < 0.0 Then elapsed_seconds += LISTBOX_SECONDS_PER_DAY
        If elapsed_seconds >= 0.0 AndAlso _
           elapsed_seconds <= LISTBOX_DOUBLE_CLICK_SECONDS Then
            d->double_activation_count += 1
            listbox_ClearDoubleClick d
            Exit Sub
        End If
    End If

    d->double_click_armed = -1
    d->double_click_index = item_index
    d->double_click_clock = clock_now
End Sub


Private Function listbox_KeyActivated( _
    ByVal heldState As Integer, _
    ByVal pressState As Integer, _
    ByVal previousHeldState As Integer, _
    ByVal keyBit As Integer _
) As Integer
    If (pressState And keyBit) <> 0 Then Return -1
    If (heldState And keyBit) <> 0 AndAlso _
       (previousHeldState And keyBit) = 0 Then Return -1
    Return 0
End Function


Private Sub listbox_UpdateKeyboard( _
    ByVal w As Widget Ptr, _
    ByVal d As ListBoxData Ptr, _
    ByVal visibleCount As Integer _
)
    Dim As Integer keyPressState
    Dim As Integer keyState
    Dim As Integer navigationActivated
    Dim As Integer previousSelection = d->selected_index

    listbox_ReadKeyState KEY_UP, LISTBOX_KEY_UP_BIT, keyState, keyPressState
    listbox_ReadKeyState _
        KEY_DOWN, LISTBOX_KEY_DOWN_BIT, keyState, keyPressState
    listbox_ReadKeyState _
        KEY_HOME, LISTBOX_KEY_HOME_BIT, keyState, keyPressState
    listbox_ReadKeyState _
        KEY_END, LISTBOX_KEY_END_BIT, keyState, keyPressState
    listbox_ReadKeyState _
        FB.SC_PAGEUP, LISTBOX_KEY_PAGE_UP_BIT, keyState, keyPressState
    listbox_ReadKeyState _
        FB.SC_PAGEDOWN, LISTBOX_KEY_PAGE_DOWN_BIT, keyState, keyPressState
    listbox_ReadKeyState _
        KEY_RETURN, LISTBOX_KEY_ENTER_BIT, keyState, keyPressState
    If d->selection_mode <> LISTBOX_SELECTION_SINGLE OrElse d->checklist_style Then
        listbox_ReadKeyState FB.SC_SPACE, LISTBOX_KEY_SPACE_BIT, keyState, keyPressState
    End If
    If d->column_count > 0 Then
        listbox_ReadKeyState KEY_LEFT, LISTBOX_KEY_LEFT_BIT, keyState, keyPressState
        listbox_ReadKeyState KEY_RIGHT, LISTBOX_KEY_RIGHT_BIT, keyState, keyPressState
    End If

    ' Reveal the caret only for a navigation gesture. Idle focus and Enter
    ' must preserve scrolling performed through TopIndex, wheel or scrollbar.
    navigationActivated = (keyPressState Or (keyState And Not d->key_latch)) And LISTBOX_KEY_NAVIGATION_BITS

    If listbox_KeyActivated( _
        keyState, keyPressState, d->key_latch, LISTBOX_KEY_UP_BIT _
    ) Then
        If d->item_count > 0 AndAlso d->selected_index < 0 Then
            d->selected_index = 0
        ElseIf d->selected_index > 0 Then
            d->selected_index -= 1
        End If
    End If

    If listbox_KeyActivated( _
        keyState, keyPressState, d->key_latch, LISTBOX_KEY_DOWN_BIT _
    ) Then
        If d->item_count > 0 AndAlso d->selected_index < 0 Then
            d->selected_index = 0
        ElseIf d->selected_index < d->item_count - 1 Then
            d->selected_index += 1
        End If
    End If

    If d->item_count > 0 AndAlso listbox_KeyActivated( _
        keyState, keyPressState, d->key_latch, LISTBOX_KEY_HOME_BIT _
    ) Then
        d->selected_index = 0
    End If

    If d->item_count > 0 AndAlso listbox_KeyActivated( _
        keyState, keyPressState, d->key_latch, LISTBOX_KEY_END_BIT _
    ) Then
        d->selected_index = d->item_count - 1
    End If

    If d->item_count > 0 AndAlso listbox_KeyActivated( _
        keyState, keyPressState, d->key_latch, LISTBOX_KEY_PAGE_UP_BIT _
    ) Then
        If d->selected_index < 0 Then d->selected_index = 0
        d->selected_index -= visibleCount
        If d->selected_index < 0 Then d->selected_index = 0
    End If

    If d->item_count > 0 AndAlso listbox_KeyActivated( _
        keyState, keyPressState, d->key_latch, LISTBOX_KEY_PAGE_DOWN_BIT _
    ) Then
        If d->selected_index < 0 Then d->selected_index = 0
        d->selected_index += visibleCount
        If d->selected_index >= d->item_count Then _
            d->selected_index = d->item_count - 1
    End If

    If d->column_count > 0 AndAlso d->item_count > 0 Then
        If listbox_KeyActivated(keyState, keyPressState, d->key_latch, LISTBOX_KEY_LEFT_BIT) Then
            d->selected_index -= listbox_RowsPerColumn(w)
            If d->selected_index < 0 Then d->selected_index = 0
        End If
        If listbox_KeyActivated(keyState, keyPressState, d->key_latch, LISTBOX_KEY_RIGHT_BIT) Then
            If d->selected_index < 0 Then
                d->selected_index = 0
            Else
                d->selected_index += listbox_RowsPerColumn(w)
                If d->selected_index >= d->item_count Then d->selected_index = d->item_count - 1
            End If
        End If
    End If

    If d->selection_mode <> LISTBOX_SELECTION_SINGLE Then
        Dim As Integer shiftDown = (input_KeyPressed(FB.SC_LSHIFT) Or input_KeyPressed(FB.SC_RSHIFT))
        Dim As Integer controlDown = input_KeyPressed(FB.SC_CONTROL)
        If navigationActivated Then
            If d->selection_anchor < 0 Then d->selection_anchor = previousSelection
            listbox_SelectGesture d, d->selected_index, shiftDown, controlDown, 0
        End If
        If listbox_KeyActivated(keyState, keyPressState, d->key_latch, LISTBOX_KEY_SPACE_BIT) Then
            If d->selected_index < 0 AndAlso d->item_count > 0 Then d->selected_index = 0
            listbox_SelectGesture d, d->selected_index, shiftDown, controlDown, -1
            If d->selected_index >= 0 Then d->activation_count += 1
        End If
    End If

    If d->checklist_style AndAlso d->selected_index >= 0 AndAlso _
       d->selected_index < d->item_count AndAlso _
       listbox_KeyActivated(keyState, keyPressState, d->key_latch, LISTBOX_KEY_SPACE_BIT) Then
        d->checked_items(d->selected_index) Xor= 1
    End If

    If d->selection_mode = LISTBOX_SELECTION_SINGLE AndAlso previousSelection <> d->selected_index Then d->selection_change_count += 1
    If d->selected_index >= 0 AndAlso _
       d->selected_index < d->item_count AndAlso _
       listbox_KeyActivated( _
           keyState, keyPressState, d->key_latch, LISTBOX_KEY_ENTER_BIT _
       ) Then
        d->activation_count += 1
    End If

    /'
        A pointer press may focus a scrolled list before release creates its
        first selection. Index -1 is not a row and must not pull the viewport
        back to the top between the press and release frames.
    '/
    If navigationActivated AndAlso d->selected_index >= 0 Then
        listbox_RevealRow w, d->selected_index
    End If

    d->key_latch = keyState
    listbox_ClampScroll w
End Sub


Sub listbox_Update(ByVal w As Widget Ptr)
    Dim As ListBoxData Ptr d
    Dim As Integer mx
    Dim As Integer my
    Dim As Integer mb
    Dim As Integer wheelDelta
    Dim As Integer pointerIndex = -1
    Dim As Integer visibleCount

    If w = 0 OrElse w->data = 0 Then Exit Sub
    d = Cast(ListBoxData Ptr, w->data)
    If d->dropdown_style Then
        listbox_DropdownUpdate w
        Exit Sub
    End If
    mx = input_MouseX()
    my = input_MouseY()
    mb = input_MouseButtons()
    wheelDelta = input_MouseWheel()
    visibleCount = listbox_RowsPerColumn(w) * listbox_VisibleColumns(w)
    listbox_ClampScroll w

    If d->scrollbar <> 0 Then
        listbox_SynchronizeScrollbar w
        d->scrollbar->update(d->scrollbar)
        d->scroll_top = Cast(ScrollBarData Ptr, d->scrollbar->data)->value
        If d->column_count > 0 Then d->scroll_top *= listbox_RowsPerColumn(w)
    End If

    If wheelDelta <> 0 AndAlso _
       mx >= w->ax AndAlso mx < w->ax + w->w - IIf(d->column_count > 0, 0, LISTBOX_SCROLLBAR_WIDTH) AndAlso _
       my >= w->ay AndAlso my < w->ay + listbox_ClientHeight(w) Then
        Dim As LongInt next_top = d->scroll_top
        ' Any larger wheel jump already traverses the entire bounded list.
        Dim As Integer wheel_steps = wheelDelta
        If wheel_steps > LISTBOX_MAX_ITEMS Then wheel_steps = LISTBOX_MAX_ITEMS
        If wheel_steps < -LISTBOX_MAX_ITEMS Then wheel_steps = -LISTBOX_MAX_ITEMS
        If d->column_count > 0 Then
            next_top -= CLngInt(wheel_steps) * listbox_RowsPerColumn(w)
        Else
            next_top -= CLngInt(wheel_steps) * LISTBOX_WHEEL_ROWS
        End If
        If next_top < 0 Then next_top = 0
        If next_top > d->item_count Then next_top = d->item_count
        d->scroll_top = CInt(next_top)
        listbox_ClampScroll w
    End If

    pointerIndex = listbox_HitRow(w, mx, my)

    /'
        Pointer selection follows the same release-inside contract as a push
        button. The press records one row but does not publish a selection.
        This matters when an application rebuilds a list in response to the
        selection: a held mouse button must not select another row from the
        replacement list on the next frame.

        gui_UpdateAll retains pointer capture until release, so this widget
        receives the final pointer position even when the user drags outside.
    '/
    If (mb And 1) Then
        If d->pointer_latch = 0 Then
            d->pointer_latch = -1
            d->pointer_index = pointerIndex
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
            d->navigation_drag_y = my: d->navigation_drag_top = d->scroll_top
            d->navigation_dragged = 0
#endif
            ' Retain the modifiers with the press, just as the row is retained.
            d->pointer_shift = input_KeyPressed(FB.SC_LSHIFT) Or input_KeyPressed(FB.SC_RSHIFT)
            d->pointer_control = input_KeyPressed(FB.SC_CONTROL)
        End If
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
        If d->pointer_index >= 0 Then
            Dim As LongInt deltaY = CLngInt(my) - d->navigation_drag_y
            If Abs(deltaY) >= 6 Then ' Separate a row tap from a logical-pixel swipe.
                Dim As LongInt nextTop = d->navigation_drag_top - deltaY \ listbox_RowHeight(d)
                If nextTop < 0 Then nextTop = 0
                If nextTop > d->item_count Then nextTop = d->item_count
                d->scroll_top = CInt(nextTop)
                d->navigation_dragged = -1
                listbox_ClampScroll w
            End If
        End If
#endif
    ElseIf d->pointer_latch Then
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
        If d->navigation_dragged Then d->pointer_index = -1
        d->navigation_dragged = 0
#endif
        If d->pointer_index >= 0 AndAlso _
           pointerIndex = d->pointer_index Then
            If d->selection_mode = LISTBOX_SELECTION_SINGLE AndAlso d->selected_index <> d->pointer_index Then d->selection_change_count += 1
            d->selected_index = d->pointer_index
            listbox_SelectGesture d, d->pointer_index, d->pointer_shift, d->pointer_control, -1
            listbox_RecordPointerActivation d, d->pointer_index
            If d->checklist_style Then d->checked_items(d->pointer_index) Xor= 1
        Else
            listbox_ClearDoubleClick d
        End If
        d->pointer_latch = 0
        d->pointer_index = -1
    End If

    If w->has_focus <> 0 Then
        listbox_UpdateKeyboard w, d, visibleCount
    Else
        d->key_latch = 0
    End If
End Sub

' -------------------------------------------------------------------------
' Rendering and lifecycle
' -------------------------------------------------------------------------

Private Sub listbox_NavigationPrint(ByVal d As ListBoxData Ptr, ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByVal textValue As String)
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
    If d->font_scale > 0 AndAlso d->font_scale <= 2 Then
        backend_PrintScaledFontAlpha x, y, clr, textValue, 0, d->font_scale, d->font_scale, 255
        Exit Sub
    End If
#endif
    backend_Print x, y, clr, textValue
End Sub

Sub listbox_Render(ByVal w As Widget Ptr)
    Dim As ListBoxData Ptr d
    Dim As ULong background_color
    Dim As ULong foreground_color

    If w = 0 OrElse w->data = 0 Then Exit Sub
    d = Cast(ListBoxData Ptr, w->data)
    If d->dropdown_style Then
        listbox_DropdownRender w
        Exit Sub
    End If
    background_color = theme_GetColor(GUI_COLOR_WIDGET_BG)
    foreground_color = theme_GetColor(GUI_COLOR_TEXT)
    If d->background_color_override Then _
        background_color = d->background_color
    If d->foreground_color_override Then _
        foreground_color = d->foreground_color

    backend_Rect(w->ax, w->ay, w->w, w->h, background_color, 1)
    Dim As ULong border_color = theme_GetColor(GUI_COLOR_BORDER)
    If current_theme.control_style = GUI_CONTROL_STYLE_FLAT Then border_color = current_theme.bg_dark
    If d->border_color_override Then border_color = d->border_color
    backend_Rect(w->ax, w->ay, w->w, w->h, border_color, 0)

    If d->column_count > 0 Then
        listbox_ClampScroll w
        listbox_RenderColumns w, foreground_color
    Else
        Dim As Integer header_height = listbox_HeaderHeight(d)
        Dim As Integer content_width = w->w - LISTBOX_SCROLLBAR_WIDTH
        Dim As Integer clip_width = content_width - LISTBOX_CLIP_INSET * 2
        Dim As Integer clip_height = w->h - header_height - LISTBOX_CLIP_INSET * 2
        If clip_width <= 0 OrElse clip_height <= 0 Then Exit Sub
        backend_SetClip w->ax + LISTBOX_CLIP_INSET, _
            w->ay + header_height + LISTBOX_CLIP_INSET, clip_width, clip_height
        Dim As Integer visible_count = listbox_RowsPerColumn(w)
        If visible_count < 1 Then visible_count = 1
        For i As Integer = 0 To visible_count
            Dim As Integer idx = i + d->scroll_top
            If idx >= 0 And idx < d->item_count Then
                Dim As Integer iy = w->ay + header_height + i * listbox_RowHeight(d)
                Dim As Integer rowSelected
                listbox_GetItemSelected w, idx, rowSelected
                Dim As ULong row_color = foreground_color
                If d->table_column_count > 0 AndAlso (idx Mod 2) = 1 Then _ ' fblint: disable-line FBL406 REASON: The Mod operands are nonnegative; the minus sign belongs to a different expression.
                    backend_Rect w->ax + 1, iy, clip_width, listbox_RowHeight(d), RGB(247, 247, 247), 1
                If rowSelected AndAlso d->checklist_style = 0 Then
                    Dim As Integer selection_x = w->ax + LISTBOX_CLIP_INSET
                    Dim As Integer selection_width = clip_width
                    Dim As ULong selection_color = theme_GetColor(GUI_COLOR_SELECT_BG)
                    row_color = theme_GetColor(GUI_COLOR_SELECT_TEXT)
                    If d->selected_background_color_override Then _
                        selection_color = d->selected_background_color
                    If d->selected_foreground_color_override Then _
                        row_color = d->selected_foreground_color
                    If d->navigation_style Then
                        selection_x = w->ax + 22
                        selection_width = backend_GetTextWidth(d->items(idx)) + 4
                        selection_color = RGB(225, 225, 225)
                        row_color = foreground_color
                    End If
                    backend_Rect selection_x, iy, selection_width, _
                        listbox_RowHeight(d), selection_color, 1
                End If
                If d->checklist_style Then
                    Dim As Widget checkWidget
                    Dim As CheckBoxData checkData
                    checkWidget.enabled = -1
                    checkWidget.ax = w->ax + 4
                    checkWidget.ay = iy + 2
                    checkWidget.data = @checkData
                    checkData.label = d->items(idx)
                    checkData.checked = d->checked_items(idx)
                    checkbox_Render @checkWidget
                ElseIf d->navigation_style Then
                    For dotY As Integer = iy To iy + listbox_RowHeight(d) - 1 Step 2
                        If idx < d->item_count - 1 OrElse dotY < iy + 9 Then _
                            backend_Rect w->ax + 12, dotY, 1, 1, current_theme.bg_dark, 1
                    Next dotY
                    For dotX As Integer = w->ax + 14 To w->ax + 20 Step 2
                        backend_Rect dotX, iy + 9, 1, 1, current_theme.bg_dark, 1
                    Next dotX
                    listbox_NavigationPrint d, w->ax + 24, iy + LISTBOX_TEXT_Y_OFFSET, row_color, d->items(idx)
                ElseIf d->table_column_count > 0 Then
                    Dim As Integer column_x = w->ax + 1
                    Dim As Integer field_start = 1
                    For column_index As Integer = 0 To d->table_column_count - 1
                        Dim As Integer field_end = InStr(field_start, d->items(idx), Chr(9))
                        If field_end = 0 Then field_end = Len(d->items(idx)) + 1
                        backend_SetClip column_x, iy, d->table_column_widths(column_index), listbox_RowHeight(d)
                        listbox_NavigationPrint d, column_x + 4, iy + LISTBOX_TEXT_Y_OFFSET, row_color, _
                            Mid(d->items(idx), field_start, field_end - field_start)
                        backend_ResetClip
                        field_start = field_end + 1
                        column_x += d->table_column_widths(column_index)
                    Next column_index
                Else
                    Dim As Integer separatorPosition = InStr(d->items(idx), Chr(9))
                    If separatorPosition > 0 AndAlso d->right_column_offset >= 0 Then
                        listbox_NavigationPrint d, w->ax + d->text_inset, _
                            iy + LISTBOX_TEXT_Y_OFFSET, row_color, _
                            Left(d->items(idx), separatorPosition - 1)
                        listbox_NavigationPrint d, w->ax + d->right_column_offset, _
                            iy + LISTBOX_TEXT_Y_OFFSET, row_color, _
                            Mid(d->items(idx), separatorPosition + 1)
                    Else
                        listbox_NavigationPrint d, w->ax + d->text_inset, _
                            iy + LISTBOX_TEXT_Y_OFFSET, row_color, d->items(idx)
                    End If
                End If
                If d->selection_mode <> LISTBOX_SELECTION_SINGLE AndAlso w->has_focus AndAlso idx = d->selected_index Then
                    backend_Rect w->ax + LISTBOX_CLIP_INSET, iy, clip_width, _
                        listbox_RowHeight(d), border_color, 0
                End If
            End If
        Next
        backend_ResetClip()
        If header_height > 0 Then
            Dim As Integer column_x = w->ax + 1
            For column_index As Integer = 0 To d->table_column_count - 1
                backend_SetClip column_x, w->ay + 1, d->table_column_widths(column_index), header_height - 1
                listbox_NavigationPrint d, column_x + 4, w->ay + 3, current_theme.text_main, d->table_column_titles(column_index)
                backend_ResetClip
                column_x += d->table_column_widths(column_index)
            Next column_index
            backend_Line w->ax + 1, w->ay + header_height - 1, _
                w->ax + content_width - 2, w->ay + header_height - 1, current_theme.win_border
        End If
    End If

    If d->scrollbar <> 0 Then
        listbox_SynchronizeScrollbar w
        listbox_ClampScroll w
        d->scrollbar->render(d->scrollbar)
    End If
End Sub

Sub listbox_Destroy(ByVal w As Widget Ptr)
    If w = 0 Then Exit Sub
    If w->data <> 0 Then
        Dim As ListBoxData Ptr d = Cast(ListBoxData Ptr, w->data)

        If d->scrollbar <> 0 Then
            If d->scrollbar->destroy <> 0 Then d->scrollbar->destroy(d->scrollbar)
            Delete d->scrollbar
            d->scrollbar = 0
        End If

        Delete d
        w->data = 0
    End If
End Sub

Function listbox_Create(ByVal nm As String, ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer) As Widget Ptr
    Dim As Widget Ptr res = New Widget
    Dim As ListBoxData Ptr d

    If res = 0 Then Return 0
    res->name = nm : res->x = x : res->y = y : res->w = w : res->h = h
    res->update = @listbox_Update : res->render = @listbox_Render : res->destroy = @listbox_Destroy
    res->visible = 1 : res->enabled = 1
    res->accepts_focus = -1
    res->captures_return = -1
    d = New ListBoxData
    If d = 0 Then
        Delete res
        Return 0
    End If
    d->item_count = 0 : d->selected_index = -1 : d->scroll_top = 0
    d->key_latch = 0
    d->pointer_latch = 0
    d->pointer_index = -1
    d->activation_count = 0
    d->double_activation_count = 0
    d->selection_mode = LISTBOX_SELECTION_SINGLE
    d->selection_anchor = -1
    d->column_count = 0
    d->text_inset = LISTBOX_TEXT_X_OFFSET
    listbox_ClearDoubleClick d
    d->background_color_override = 0
    d->foreground_color_override = 0
    d->right_column_offset = -1
    d->scrollbar = scrollbar_Create( _
        nm & "_sb", x + w - LISTBOX_SCROLLBAR_WIDTH, y, _
        LISTBOX_SCROLLBAR_WIDTH, h, 0, 1, -1 _
    )
    If d->scrollbar = 0 Then
        Delete d
        Delete res
        Return 0
    End If
    res->data = d
    Return res
End Function


Sub listbox_SetNavigationStyle(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then Exit Sub
    Dim As ListBoxData Ptr d = Cast(ListBoxData Ptr, w->data)
    If d->column_count OrElse d->table_column_count OrElse d->dropdown_style OrElse d->checklist_style Then Exit Sub
    d->navigation_style = -1
    listbox_ClampScroll w
End Sub


Sub listbox_SetRowHeight(ByVal w As Widget Ptr, ByVal rowHeight As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then Exit Sub
    If rowHeight < 16 OrElse rowHeight > 96 Then Exit Sub
    Dim As ListBoxData Ptr d = Cast(ListBoxData Ptr, w->data)
    If d->dropdown_style Then Exit Sub
    d->row_height = rowHeight
    listbox_ClampScroll w
End Sub


Sub listbox_SetTextInset(ByVal w As Widget Ptr, ByVal inset As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then Exit Sub
    If inset < 0 OrElse inset > 128 Then Exit Sub
    Cast(ListBoxData Ptr, w->data)->text_inset = inset
End Sub


Sub listbox_SetColumn( _
    ByVal w As Widget Ptr, ByVal columnIndex As Integer, _
    ByVal title As String, ByVal columnWidth As Integer _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then Exit Sub
    If columnIndex < 0 OrElse columnIndex >= LISTBOX_MAX_TABLE_COLUMNS Then Exit Sub
    If columnWidth < 16 OrElse columnWidth > 4096 Then Exit Sub
    Dim As ListBoxData Ptr d = Cast(ListBoxData Ptr, w->data)
    If d->column_count OrElse d->navigation_style OrElse d->dropdown_style OrElse d->checklist_style Then Exit Sub
    If columnIndex > d->table_column_count Then Exit Sub
    d->table_column_titles(columnIndex) = gui_TransformText(title)
    d->table_column_widths(columnIndex) = columnWidth
    If d->table_column_count <= columnIndex Then d->table_column_count = columnIndex + 1
    listbox_ClampScroll w
End Sub


Sub listbox_SetDropdownStyle(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then Exit Sub
    Dim As ListBoxData Ptr d = Cast(ListBoxData Ptr, w->data)
    If d->item_count > MENU_MAX_ITEMS OrElse d->column_count OrElse _
       d->table_column_count OrElse d->navigation_style OrElse d->checklist_style Then Exit Sub
    d->dropdown_style = -1
    w->h = LISTBOX_DROPDOWN_HEIGHT
End Sub


Sub listbox_SetChecklistStyle(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then Exit Sub
    Dim As ListBoxData Ptr d = Cast(ListBoxData Ptr, w->data)
    If d->column_count OrElse d->table_column_count OrElse d->navigation_style OrElse d->dropdown_style Then Exit Sub
    d->checklist_style = -1
End Sub


Sub listbox_SetChecked(ByVal w As Widget Ptr, ByVal itemIndex As Integer, ByVal isChecked As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then Exit Sub
    Dim As ListBoxData Ptr d = Cast(ListBoxData Ptr, w->data)
    If itemIndex < 0 OrElse itemIndex >= d->item_count Then Exit Sub
    d->checked_items(itemIndex) = IIf(isChecked <> 0, 1, 0)
End Sub


Function listbox_IsChecked(ByVal w As Widget Ptr, ByVal itemIndex As Integer) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then Return 0
    Dim As ListBoxData Ptr d = Cast(ListBoxData Ptr, w->data)
    If itemIndex < 0 OrElse itemIndex >= d->item_count Then Return 0
    Return IIf(d->checked_items(itemIndex), -1, 0)
End Function


Sub listbox_SetScrollbarColors( _
    ByVal w As Widget Ptr, ByVal trackColor As ULong, _
    ByVal thumbColor As ULong, ByVal thumbBorderColor As ULong _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then Exit Sub
    scrollbar_SetColors Cast(ListBoxData Ptr, w->data)->scrollbar, _
        trackColor, thumbColor, thumbBorderColor
End Sub

' -------------------------------------------------------------------------
' Public item, selection, and color API
' -------------------------------------------------------------------------

Sub listbox_AddItem(ByVal w As Widget Ptr, ByVal lbl As String)
    ' Keep the historical void API. Callers needing failure reporting use InsertItem.
    listbox_InsertItem w, lbl
End Sub

Function listbox_InsertItem( _
    ByVal w As Widget Ptr, ByRef item_text As Const String, ByVal item_index As Integer _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Dim As ListBoxData Ptr d = w->data
    Dim As Integer stored_bytes = Len(item_text)
    If d->item_count < 0 OrElse d->item_count >= LISTBOX_MAX_ITEMS Then Return 0
    If d->dropdown_style AndAlso d->item_count >= MENU_MAX_ITEMS Then Return 0
    If item_index = -1 Then item_index = d->item_count
    If item_index < 0 OrElse item_index > d->item_count Then Return 0
    For index_value As Integer = 0 To d->item_count - 1
        If Len(d->items(index_value)) > LISTBOX_MAX_TEXT_BYTES - stored_bytes Then Return 0
        stored_bytes += Len(d->items(index_value))
    Next index_value
    If stored_bytes > LISTBOX_MAX_TEXT_BYTES Then Return 0
    ' Copy before shifting: item_text may refer to an existing row.
    Dim As String retained_text = item_text
    For index_value As Integer = d->item_count To item_index + 1 Step -1
        d->items(index_value) = d->items(index_value - 1)
        d->item_data(index_value) = d->item_data(index_value - 1)
        d->selected_rows(index_value) = d->selected_rows(index_value - 1)
        d->checked_items(index_value) = d->checked_items(index_value - 1)
    Next index_value
    d->items(item_index) = retained_text
    d->item_data(item_index) = 0
    d->selected_rows(item_index) = 0
    d->checked_items(item_index) = 0
    d->item_count += 1
    d->selection_change_count += 1
    If d->selected_index >= item_index Then d->selected_index += 1
    If d->selection_anchor >= item_index Then d->selection_anchor += 1
    ' A pending pointer release cannot activate content that moved under it.
    If d->pointer_latch Then d->pointer_index = -1
    listbox_ClearDoubleClick d
    listbox_ClampScroll w
    Return -1
End Function

Function listbox_RemoveItem(ByVal w As Widget Ptr, ByVal item_index As Integer) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Dim As ListBoxData Ptr d = w->data
    If d->item_count < 0 OrElse d->item_count > LISTBOX_MAX_ITEMS OrElse _
       item_index < 0 OrElse item_index >= d->item_count Then Return 0
    For index_value As Integer = item_index To d->item_count - 2
        d->items(index_value) = d->items(index_value + 1)
        d->item_data(index_value) = d->item_data(index_value + 1)
        d->selected_rows(index_value) = d->selected_rows(index_value + 1)
        d->checked_items(index_value) = d->checked_items(index_value + 1)
    Next index_value
    d->item_count -= 1
    d->selection_change_count += 1
    d->items(d->item_count) = ""
    d->item_data(d->item_count) = 0
    d->selected_rows(d->item_count) = 0
    d->checked_items(d->item_count) = 0
    If d->selection_anchor = item_index Then
        d->selection_anchor = -1
    ElseIf d->selection_anchor > item_index Then
        d->selection_anchor -= 1
    End If
    If d->selected_index = item_index Then
        d->selected_index = -1
    ElseIf d->selected_index > item_index Then
        d->selected_index -= 1
    End If
    If d->pointer_latch Then d->pointer_index = -1
    listbox_ClearDoubleClick d
    listbox_ClampScroll w
    Return -1
End Function

Function listbox_GetItem( _
    ByVal w As Widget Ptr, ByVal item_index As Integer, ByRef item_text As String _
) As Integer
    If w = 0 OrElse w->data = 0 Then
        item_text = ""
        Return 0
    End If
    Dim As ListBoxData Ptr d = w->data
    If d->item_count < 0 OrElse d->item_count > LISTBOX_MAX_ITEMS OrElse _
       item_index < 0 OrElse item_index >= d->item_count Then
        item_text = ""
        Return 0
    End If
    item_text = d->items(item_index)
    Return -1
End Function

Function listbox_SetItem( _
    ByVal w As Widget Ptr, ByVal item_index As Integer, ByRef item_text As Const String _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Dim As ListBoxData Ptr d = w->data
    If d->item_count < 0 OrElse d->item_count > LISTBOX_MAX_ITEMS OrElse _
       item_index < 0 OrElse item_index >= d->item_count Then Return 0
    Dim As Integer stored_bytes = Len(item_text)
    If stored_bytes > LISTBOX_MAX_TEXT_BYTES Then Return 0
    For index_value As Integer = 0 To d->item_count - 1
        If index_value = item_index Then Continue For
        If Len(d->items(index_value)) > LISTBOX_MAX_TEXT_BYTES - stored_bytes Then Return 0
        stored_bytes += Len(d->items(index_value))
    Next index_value
    ' Capture aliases before replacement, and validate the whole text budget
    ' before touching the row or any input state.
    Dim As String retained_text = item_text
    d->items(item_index) = retained_text
    If d->pointer_latch Then d->pointer_index = -1
    listbox_ClearDoubleClick d
    Return -1
End Function

Function listbox_SetItemData( _
    ByVal w As Widget Ptr, ByVal item_index As Integer, ByVal data_value As LongInt _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Dim As ListBoxData Ptr d = w->data
    If d->item_count < 0 OrElse d->item_count > LISTBOX_MAX_ITEMS OrElse _
       item_index < 0 OrElse item_index >= d->item_count Then Return 0
    d->item_data(item_index) = data_value
    Return -1
End Function

Function listbox_GetItemData( _
    ByVal w As Widget Ptr, ByVal item_index As Integer, ByRef data_value As LongInt _
) As Integer
    If w = 0 OrElse w->data = 0 Then
        data_value = 0
        Return 0
    End If
    Dim As ListBoxData Ptr d = w->data
    If d->item_count < 0 OrElse d->item_count > LISTBOX_MAX_ITEMS OrElse _
       item_index < 0 OrElse item_index >= d->item_count Then
        data_value = 0
        Return 0
    End If
    data_value = d->item_data(item_index)
    Return -1
End Function

Function listbox_SetTopIndex(ByVal w As Widget Ptr, ByVal item_index As Integer) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Dim As ListBoxData Ptr d = w->data
    If d->item_count < 0 OrElse d->item_count > LISTBOX_MAX_ITEMS OrElse _
       item_index < 0 OrElse item_index >= d->item_count Then Return 0
    Dim As Integer old_top = d->scroll_top
    d->scroll_top = item_index
    listbox_ClampScroll w
    If old_top <> d->scroll_top Then
        If d->pointer_latch Then d->pointer_index = -1
        listbox_ClearDoubleClick d
    End If
    Return -1
End Function

Function listbox_GetTopIndex(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return -1
    Dim As ListBoxData Ptr d = w->data
    If d->item_count < 0 OrElse d->item_count > LISTBOX_MAX_ITEMS Then Return -1
    listbox_ClampScroll w
    Return d->scroll_top
End Function

Sub listbox_Clear(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub

    Dim As ListBoxData Ptr d = w->data
    Dim As Integer retained_count = d->item_count
    If retained_count > LISTBOX_MAX_ITEMS Then retained_count = LISTBOX_MAX_ITEMS
    For item_index As Integer = 0 To retained_count - 1
        d->items(item_index) = ""
        d->item_data(item_index) = 0
        d->selected_rows(item_index) = 0
        d->checked_items(item_index) = 0
    Next item_index
    If d->item_count > 0 Then d->selection_change_count += 1
    d->item_count = 0 : d->selected_index = -1 : d->scroll_top = 0
    d->selection_anchor = -1
    /'
        Clearing content must not manufacture a new physical input edge.
        Applications commonly rebuild a navigation list immediately after a
        selection. Preserve the keyboard latch until key release so one held
        Down key cannot walk through the replacement list. Preserve an active
        pointer latch as well, but invalidate its old row so release can only
        cancel, never select the same numeric row in new content.
    '/
    If d->pointer_latch Then d->pointer_index = -1
    listbox_ClearDoubleClick d
    listbox_ClampScroll w
End Sub


Function listbox_GetSelectedIndex(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return -1
    Return Cast(ListBoxData Ptr, w->data)->selected_index
End Function


Function listbox_GetSelectedItem(ByVal w As Widget Ptr) As String
    Dim As ListBoxData Ptr listData

    If w = 0 OrElse w->data = 0 Then Return ""

    listData = Cast(ListBoxData Ptr, w->data)
    If listData->selected_index < 0 OrElse _
       listData->selected_index >= listData->item_count Then
        Return ""
    End If

    Return listData->items(listData->selected_index)
End Function


Function listbox_GetItemCount(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Return Cast(ListBoxData Ptr, w->data)->item_count
End Function


Function listbox_GetActivationCount(ByVal w As Widget Ptr) As ULongInt
    If w = 0 OrElse w->data = 0 Then Return 0
    Return Cast(ListBoxData Ptr, w->data)->activation_count
End Function


Function listbox_GetDoubleActivationCount(ByVal w As Widget Ptr) As ULongInt
    If w = 0 OrElse w->data = 0 Then Return 0
    Return Cast(ListBoxData Ptr, w->data)->double_activation_count
End Function


Function listbox_ActivateSelected(ByVal w As Widget Ptr) As Integer
    Dim As ListBoxData Ptr listData

    If w = 0 OrElse w->data = 0 Then Return 0
    listData = Cast(ListBoxData Ptr, w->data)
    If listData->selected_index < 0 OrElse _
       listData->selected_index >= listData->item_count Then Return 0

    /'
        Applications poll activation_count after OMAGUI updates. Programmatic
        activation follows the same event contract as Enter and pointer
        release, which also makes accessible or test-driven activation
        possible without reaching into retained widget data.
    '/
    listData->activation_count += 1
    Return -1
End Function


Function listbox_DoubleActivateSelected(ByVal w As Widget Ptr) As Integer
    Dim As ListBoxData Ptr listData

    If w = 0 OrElse w->data = 0 Then Return 0
    listData = Cast(ListBoxData Ptr, w->data)
    If listData->selected_index < 0 OrElse _
       listData->selected_index >= listData->item_count Then Return 0

    /'
        A programmatic double activation represents the completed gesture.
        Polling applications therefore receive one ordinary activation and one
        double activation in the same update, matching the second pointer
        release of a physical double click.
    '/
    listData->activation_count += 1
    listData->double_activation_count += 1
    listbox_ClearDoubleClick listData
    Return -1
End Function


Function listbox_SetSelectedIndex( _
    ByVal w As Widget Ptr, _
    ByVal selectedIndex As Integer _
) As Integer
    Dim As ListBoxData Ptr listData

    If w = 0 OrElse w->data = 0 Then Return 0
    listData = Cast(ListBoxData Ptr, w->data)

    If selectedIndex = -1 Then
        If listData->selection_mode = LISTBOX_SELECTION_SINGLE AndAlso listData->selected_index <> -1 Then listData->selection_change_count += 1
        listData->selected_index = -1
        listbox_ClearSelectedRows listData
        listData->selection_anchor = -1
        Return -1
    End If
    If selectedIndex < 0 OrElse selectedIndex >= listData->item_count Then
        Return 0
    End If

    If listData->selection_mode = LISTBOX_SELECTION_SINGLE AndAlso listData->selected_index <> selectedIndex Then listData->selection_change_count += 1
    listData->selected_index = selectedIndex
    listbox_RevealRow w, selectedIndex
    listbox_ClampScroll w
    Return -1
End Function


Function listbox_SetColumnCount(ByVal w As Widget Ptr, ByVal column_count As Integer) As Integer
    Dim As ListBoxData Ptr d = listbox_SelectionData(w)
    If d = 0 OrElse column_count < 0 OrElse column_count > LISTBOX_MAX_COLUMNS Then Return 0
    If column_count > 0 AndAlso (d->table_column_count OrElse d->navigation_style OrElse _
       d->dropdown_style OrElse d->checklist_style) Then Return 0
    If d->column_count = column_count Then Return -1
    d->column_count = column_count
    If d->pointer_latch Then d->pointer_index = -1
    If d->scrollbar <> 0 Then scrollbar_CancelPointer d->scrollbar
    listbox_ClearDoubleClick d
    If input_KeyPressed(KEY_LEFT) Then d->key_latch Or= LISTBOX_KEY_LEFT_BIT
    If input_KeyPressed(KEY_RIGHT) Then d->key_latch Or= LISTBOX_KEY_RIGHT_BIT
    listbox_ClampScroll w
    listbox_SynchronizeScrollbar w
    Return -1
End Function

Function listbox_GetColumnCount(ByVal w As Widget Ptr) As Integer
    Dim As ListBoxData Ptr d = listbox_SelectionData(w)
    If d = 0 Then Return -1
    Return d->column_count
End Function

Function listbox_SetBackgroundColor( _
    ByVal w As Widget Ptr, _
    ByVal color_value As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(ListBoxData Ptr, w->data)
        .background_color = color_value
        .background_color_override = -1
    End With
    Return -1
End Function


Function listbox_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(ListBoxData Ptr, w->data)->background_color_override = 0
    Return -1
End Function


Function listbox_GetBackgroundColor( _
    ByVal w As Widget Ptr, _
    ByRef color_value As ULong _
) As Integer
    Dim As ListBoxData Ptr list_data

    color_value = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    list_data = Cast(ListBoxData Ptr, w->data)
    If list_data->background_color_override = 0 Then Return 0
    color_value = list_data->background_color
    Return -1
End Function


Function listbox_SetForegroundColor( _
    ByVal w As Widget Ptr, _
    ByVal color_value As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(ListBoxData Ptr, w->data)
        .foreground_color = color_value
        .foreground_color_override = -1
    End With
    Return -1
End Function


Function listbox_ClearForegroundColor(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(ListBoxData Ptr, w->data)->foreground_color_override = 0
    Return -1
End Function


Function listbox_GetForegroundColor( _
    ByVal w As Widget Ptr, _
    ByRef color_value As ULong _
) As Integer
    Dim As ListBoxData Ptr list_data

    color_value = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    list_data = Cast(ListBoxData Ptr, w->data)
    If list_data->foreground_color_override = 0 Then Return 0
    color_value = list_data->foreground_color
    Return -1
End Function

Sub listbox_SetColors( _
    ByVal w As Widget Ptr, _
    ByVal background_color As ULong, ByVal border_color As ULong, _
    ByVal foreground_color As ULong, _
    ByVal selected_background_color As ULong, _
    ByVal selected_foreground_color As ULong _
)
    Dim As ListBoxData Ptr list_data

    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then Exit Sub
    list_data = Cast(ListBoxData Ptr, w->data)
    With *list_data
        .background_color = background_color
        .background_color_override = -1
        .border_color = border_color
        .border_color_override = -1
        .foreground_color = foreground_color
        .foreground_color_override = -1
        .selected_background_color = selected_background_color
        .selected_background_color_override = -1
        .selected_foreground_color = selected_foreground_color
        .selected_foreground_color_override = -1
    End With
End Sub

Function listbox_SetRightColumn( _
    ByVal w As Widget Ptr, ByVal column_offset As Integer _
) As Integer
    Dim As ListBoxData Ptr list_data

    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @listbox_Destroy Then Return 0
    If column_offset < 0 OrElse _
       column_offset >= w->w - LISTBOX_SCROLLBAR_WIDTH Then Return 0
    list_data = Cast(ListBoxData Ptr, w->data)
    list_data->right_column_offset = column_offset
    Return -1
End Function

/' end of listbox.bas '/
