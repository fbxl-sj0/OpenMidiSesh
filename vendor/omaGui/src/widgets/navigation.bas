/'
    Project: omaGUI
    File: navigation.bas
    Purpose: Bridge scope navigation to the current widget registry.
    Responsibilities: Validate weak identities and dispatch controller activation after widget updates.
    This file does not contain application commands or a second event queue.

    The navigation profile is opt-in through OMAGUI_NAVIGATION_EXTENSIONS.
    All state belongs to the GUI thread, like the core registry and input frame.
'/

#lang "fb"

Private Dim Shared As Widget Ptr omagui_nav_scope, omagui_nav_action_target
Private Dim Shared As ULongInt omagui_nav_scope_id, omagui_nav_action_id
Private Dim Shared As Integer omagui_nav_building_scope, omagui_nav_directional

' Profile-owned weak references always carry registry IDs. Callback-driven
' deletion and immediate address reuse must not activate a replacement widget.
Sub gui_NavigationReset()
    omagui_nav_scope = 0: omagui_nav_scope_id = 0
    omagui_nav_action_target = 0: omagui_nav_action_id = 0
    omagui_nav_building_scope = 0: omagui_nav_directional = 0
End Sub

Function gui_GetActiveScope() As Widget Ptr
    If gui_IsSameRegisteredWidget(omagui_nav_scope, omagui_nav_scope_id) = 0 Then Return 0
    Return omagui_nav_scope
End Function

Sub gui_SetActiveScope(ByVal root As Widget Ptr)
    If root <> 0 AndAlso gui_IsRegisteredWidget(root) = 0 Then Exit Sub
    omagui_nav_scope = root: omagui_nav_scope_id = 0
    If root <> 0 Then omagui_nav_scope_id = root->registry_id
    gui_SetModalRoot root
End Sub

Function gui_WidgetIsInActiveScope(ByVal w As Widget Ptr) As Integer
    If gui_IsRegisteredWidget(w) = 0 Then Return 0
    Dim As Widget Ptr root = gui_GetActiveScope()
    Return IIf(root = 0 OrElse gui_IsWithinTree(w, root), -1, 0)
End Function

Function gui_BeginInputScope(ByVal nm As String, ByVal x As Integer, _
    ByVal y As Integer, ByVal w As Integer, ByVal h As Integer) As Widget Ptr
    If w <= 0 OrElse h <= 0 Then Return 0
    Dim As Widget Ptr root = gui_CreateWidgetBase()
    If root = 0 Then Return 0
    root->name = nm: root->x = x: root->y = y: root->w = w: root->h = h
    gui_AddWidget root
    gui_SetActiveScope root
    omagui_nav_building_scope = -1
    Return root
End Function

Sub gui_NavigationAttach(ByVal w As Widget Ptr)
    If w->destroy = @button_Destroy Then
        button_SetFlatStyle w, current_theme.bg_widget, current_theme.text_main, _
            current_theme.bg_select, current_theme.text_select, current_theme.bg_select, current_theme.text_select
    End If
    If w->destroy = @listbox_Destroy Then
        listbox_SetRowHeight w, 40 ' Preserve the logical touch-row size.
        w->cancel_input = @listbox_NavigationCancelInput
    End If
    If omagui_nav_building_scope = 0 Then Exit Sub
    Dim As Widget Ptr root = gui_GetActiveScope()
    If root <> 0 AndAlso w <> root AndAlso w->parent = 0 Then gui_SetParent w, root
End Sub

Sub gui_EndInputScopeBuild()
    omagui_nav_building_scope = 0
End Sub

Sub gui_Shutdown()
    gui_ResetForTest
End Sub

Sub gui_SetFocusable(ByVal w As Widget Ptr, ByVal focusOrder As Integer)
    If w = 0 Then Exit Sub
    w->accepts_focus = -1
    gui_SetTabOrder w, focusOrder
End Sub

Function gui_IsFocused(ByVal w As Widget Ptr) As Integer
    Return IIf(w <> 0 AndAlso gui_GetFocus() = w, -1, 0)
End Function

Function gui_ShouldShowFocus(ByVal w As Widget Ptr) As Integer
    Return IIf(gui_IsFocused(w) AndAlso gui_KeyboardFocusVisible, -1, 0)
End Function

Function gui_WidgetHasNavigation(ByVal w As Widget Ptr) As Integer
    Return gui_IsFocused(w)
End Function

Function gui_WidgetHasPointer(ByVal w As Widget Ptr) As Integer
    Return IIf(w <> 0 AndAlso widget_last_pointer_target = w, -1, 0)
End Function

Function gui_GetPointerCapture() As Widget Ptr
    Return widget_pointer_capture
End Function

Function gui_FocusFirst() As Integer
    gui_SetFocus 0
    gui_MoveFocus 0
    Return IIf(gui_GetFocus() <> 0, -1, 0)
End Function

Function gui_FocusNext(ByVal direction As Integer) As Integer
    gui_MoveFocus IIf(direction < 0, -1, 0)
    Return IIf(gui_GetFocus() <> 0, -1, 0)
End Function

Sub gui_SetDirectionalFocus(ByVal enabled As Integer)
    omagui_nav_directional = IIf(enabled, -1, 0)
End Sub

Sub gui_SetFocusNeighbor(ByVal w As Widget Ptr, ByVal action As Integer, ByVal neighbor As Widget Ptr)
    If w = 0 OrElse action < 0 OrElse action > INPUT_ACTION_RIGHT Then Exit Sub
    If neighbor <> 0 AndAlso gui_IsRegisteredWidget(neighbor) = 0 Then Exit Sub
    w->navigation_neighbor(action) = neighbor
    w->navigation_neighbor_id(action) = 0
    If neighbor <> 0 Then w->navigation_neighbor_id(action) = neighbor->registry_id
End Sub

Sub gui_SetDefaultButton(ByVal w As Widget Ptr)
    gui_SetDefaultAction w, -1
End Sub

Sub gui_SetCancelButton(ByVal w As Widget Ptr)
    gui_SetCancelAction w, -1
End Sub

Function gui_ActivateWidget(ByVal w As Widget Ptr) As Integer
    If gui_IsRegisteredWidget(w) = 0 Then Return 0
    If w->evis = 0 OrElse w->een = 0 OrElse w->activate = 0 Then Return 0
    If gui_WidgetIsInActiveScope(w) = 0 Then Return 0
    w->activate(w)
    Return -1
End Function

Sub button_SetKeyboardFocusOrder(ByVal w As Widget Ptr, ByVal focusOrder As Integer)
    gui_SetFocusable w, focusOrder
End Sub

Sub button_SetKeyboardSelected(ByVal w As Widget Ptr, ByVal selected As Integer)
    button_SetSelected w, selected
End Sub

Sub button_SetKeyboardShortcut(ByVal w As Widget Ptr, ByVal shortcutText As String)
    If w = 0 OrElse w->destroy <> @button_Destroy Then Exit Sub
    w->navigation_shortcut = UCase(Left(Trim(shortcutText), 1))
End Sub

Sub gui_NavigationPrepare()
    omagui_nav_action_target = 0: omagui_nav_action_id = 0
    Dim As Widget Ptr focused = gui_GetFocus()
    ' Core Tab traversal already ran. Consume its semantic alias once.
    If input_KeyPressEvent(FB.SC_TAB) Then input_ConsumeAction INPUT_ACTION_PAGE_NEXT
    If omagui_nav_directional AndAlso focused <> 0 Then
        If focused->update <> @textbox_Update AndAlso focused->update <> @listbox_Update Then
            For action As Integer = INPUT_ACTION_UP To INPUT_ACTION_RIGHT
                If input_ActionPressed(action) Then
                    Dim As Widget Ptr neighbor = focused->navigation_neighbor(action)
                    If gui_IsSameRegisteredWidget(neighbor, focused->navigation_neighbor_id(action)) AndAlso gui_CanFocus(neighbor) Then
                        gui_SetFocus neighbor
                    Else
                        gui_FocusNext IIf(action = INPUT_ACTION_UP OrElse action = INPUT_ACTION_LEFT, -1, 1)
                    End If
                    gui_KeyboardFocusVisible = -1
                    input_ConsumeAction action
                    Exit For
                End If
            Next
        End If
    End If
    If focused <> 0 AndAlso focused->destroy = @listbox_Destroy Then
        Dim As ListBoxData Ptr listData = focused->data
        If listData <> 0 AndAlso listData->item_count > 0 Then
            For action As Integer = 0 To INPUT_ACTION_COUNT - 1
                Dim As Integer nativeHandled = 0
                Select Case action
                Case INPUT_ACTION_UP: nativeHandled = input_KeyPressed(KEY_UP)
                Case INPUT_ACTION_DOWN: nativeHandled = input_KeyPressed(KEY_DOWN)
                Case INPUT_ACTION_PAGE_PREVIOUS: nativeHandled = input_KeyPressed(FB.SC_PAGEUP)
                Case INPUT_ACTION_PAGE_NEXT: nativeHandled = input_KeyPressed(FB.SC_PAGEDOWN)
                Case Else: Continue For
                End Select
                If input_ActionPressed(action) AndAlso nativeHandled = 0 Then
                    Dim As Integer rowIndex = listData->selected_index
                    Dim As Integer pageRows = focused->h \ IIf(listData->row_height > 0, listData->row_height, 40)
                    If pageRows < 1 Then pageRows = 1
                    Select Case action
                    Case INPUT_ACTION_UP: rowIndex -= 1
                    Case INPUT_ACTION_DOWN: rowIndex += 1
                    Case INPUT_ACTION_PAGE_PREVIOUS: rowIndex -= pageRows
                    Case INPUT_ACTION_PAGE_NEXT: rowIndex += pageRows
                    End Select
                    If action <= INPUT_ACTION_DOWN Then
                        If rowIndex < 0 Then rowIndex = listData->item_count - 1
                        If rowIndex >= listData->item_count Then rowIndex = 0
                    Else
                        If rowIndex < 0 Then rowIndex = 0
                        If rowIndex >= listData->item_count Then rowIndex = listData->item_count - 1
                    End If
                    listbox_SetSelectedIndex focused, rowIndex
                    input_ConsumeAction action
                    Exit For
                End If
            Next
        End If
    End If
    focused = gui_GetFocus()
    ' Native keyboard activation belongs to core widgets and dialog actions.
    ' Controller actions use the same callback, after per-frame flags reset.
    If input_LastDevice() = INPUT_DEVICE_GAMEPAD Then
        If input_ActionPressed(INPUT_ACTION_ACCEPT) Then
            If focused <> 0 AndAlso focused->activate <> 0 AndAlso focused->destroy <> @listbox_Destroy Then omagui_nav_action_target = focused
            If omagui_nav_action_target = 0 Then
                Dim As Widget Ptr defaultWidget = widget_list_head
                While defaultWidget <> 0
                    If defaultWidget->is_default_action AndAlso gui_WidgetIsInActiveScope(defaultWidget) Then
                        omagui_nav_action_target = defaultWidget
                        Exit While
                    End If
                    defaultWidget = defaultWidget->next_widget
                Wend
            End If
            If omagui_nav_action_target <> 0 Then input_ConsumeAction INPUT_ACTION_ACCEPT
        ElseIf input_ActionPressed(INPUT_ACTION_CANCEL) Then
            Dim As Widget Ptr current = widget_list_head
            While current <> 0
                If current->is_cancel_action AndAlso gui_WidgetIsInActiveScope(current) Then
                    omagui_nav_action_target = current
                    Exit While
                End If
                current = current->next_widget
            Wend
            input_ConsumeAction INPUT_ACTION_CANCEL
        End If
    Else
        If input_ActionPressed(INPUT_ACTION_ACCEPT) AndAlso focused <> 0 AndAlso focused->activate <> 0 AndAlso focused->destroy <> @listbox_Destroy Then input_ConsumeAction INPUT_ACTION_ACCEPT
        If input_ActionPressed(INPUT_ACTION_CANCEL) Then
            Dim As Widget Ptr cancelWidget = widget_list_head
            While cancelWidget <> 0
                If cancelWidget->is_cancel_action AndAlso gui_WidgetIsInActiveScope(cancelWidget) Then
                    input_ConsumeAction INPUT_ACTION_CANCEL
                    Exit While
                End If
                cancelWidget = cancelWidget->next_widget
            Wend
        End If
        Dim As String typedText = UCase(input_PeekTextInput())
        Dim As Widget Ptr current = widget_list_head
        While current <> 0
            If current->navigation_shortcut <> "" AndAlso InStr(typedText, current->navigation_shortcut) > 0 AndAlso gui_CanFocus(current) Then
                omagui_nav_action_target = current
                Exit While
            End If
            current = current->next_widget
        Wend
    End If
    If omagui_nav_action_target <> 0 Then omagui_nav_action_id = omagui_nav_action_target->registry_id
End Sub

Sub gui_NavigationDispatch()
    Dim As Widget Ptr target = omagui_nav_action_target
    Dim As ULongInt identity = omagui_nav_action_id
    omagui_nav_action_target = 0: omagui_nav_action_id = 0
    If gui_IsSameRegisteredWidget(target, identity) Then gui_ActivateWidget target
End Sub


' Checked setters bound the products used by row, column and grid layouts.
Sub gui_SetPreferredSize(ByVal w As Widget Ptr, ByVal preferredWidth As Integer, ByVal preferredHeight As Integer)
    If w = 0 Then Exit Sub
    If preferredWidth < 0 OrElse preferredWidth > 32767 OrElse preferredHeight < 0 OrElse preferredHeight > 32767 Then Exit Sub
    w->preferred_w = preferredWidth: w->preferred_h = preferredHeight
End Sub

Sub gui_SetMinimumSize(ByVal w As Widget Ptr, ByVal minimumWidth As Integer, ByVal minimumHeight As Integer)
    If w = 0 Then Exit Sub
    If minimumWidth < 0 OrElse minimumWidth > 32767 OrElse minimumHeight < 0 OrElse minimumHeight > 32767 Then Exit Sub
    w->minimum_w = minimumWidth: w->minimum_h = minimumHeight
End Sub

Sub gui_SetLayoutWeight(ByVal w As Widget Ptr, ByVal weight As Integer)
    If w = 0 OrElse weight < 0 OrElse weight > 65535 Then Exit Sub
    w->layout_weight = weight
End Sub

Sub gui_SetGridCell(ByVal w As Widget Ptr, ByVal row As Integer, ByVal column As Integer, ByVal rowSpan As Integer, ByVal columnSpan As Integer)
    If w = 0 Then Exit Sub
    If row < -1 OrElse row > 4095 OrElse column < -1 OrElse column > 4095 Then Exit Sub
    If rowSpan < 1 OrElse rowSpan > 4096 OrElse columnSpan < 1 OrElse columnSpan > 4096 Then Exit Sub
    If row >= 0 AndAlso row + rowSpan > 4096 Then Exit Sub
    If column >= 0 AndAlso column + columnSpan > 4096 Then Exit Sub
    w->layout_row = row: w->layout_column = column
    w->layout_row_span = rowSpan: w->layout_column_span = columnSpan
End Sub

Sub listbox_NavigationCancelInput(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As ListBoxData Ptr d = w->data
    d->pointer_latch = 0: d->pointer_index = -1: d->navigation_dragged = 0
End Sub

' end of navigation.bas
