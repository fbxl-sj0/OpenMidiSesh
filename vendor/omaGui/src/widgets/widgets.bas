/'
    Project: omaGUI
    ---------------

    File: widgets.bas

    Purpose:
        Manage widget registration, hierarchy, input, drawing, and layout.

    Responsibilities:
        - own the widget registry and bounded modal-root stack
        - resolve parent-relative coordinates
        - route pointer input to the topmost eligible widget
        - maintain movable-window stacking and keyboard focus traversal
        - keep keyboard dispatch bound to its pre-callback widget identities
        - show focus cues only while the user is navigating by keyboard
        - dispatch Alt mnemonics to control activation callbacks
        - route static-caption mnemonics through checked weak focus targets
        - decode conventional ampersand access-key captions
        - draw access-key underlines through the semantic classic palette
        - clip child rendering and hit testing to parent client areas
        - suspend descendant input for collapsed container widgets
        - react to drawable-area changes through reusable anchor constraints
        - dispatch widget updates and rendering in registry order
        - cancel private input state when controls become ineligible
        - tolerate callbacks which remove or replace their own widget tree

    Targets:

        FreeBASIC builds with built-in gfxlib; gfxlib3 is optional when supplied by the compiler.

    Module API:

        Implementation unit assembled by omaGUI.bi when OMAGUI_IMPLEMENTATION is defined.

    This file intentionally does NOT contain:
        - individual widget behavior or appearance
        - platform window creation and event handling
        - application-specific layout rules
'/
#lang "fb"
#include once "src/widgets/widgets.bi"
#include once "src/widgets/radiobox.bi"
#include once "src/backend/theme.bi"

' -------------------------------------------------------------------------
' Global State
' -------------------------------------------------------------------------

Dim Shared As Widget Ptr widget_list_head = 0
Dim Shared As Widget Ptr widget_list_tail = 0
Dim Shared As Widget Ptr widget_modal_root = 0
Dim Shared As Widget Ptr widget_modal_root_stack( _
    0 To GUI_MODAL_ROOT_MAXIMUM_DEPTH - 1 _
)
Dim Shared As Integer widget_modal_root_stack_count
Dim Shared As Widget Ptr widget_pointer_capture = 0
Dim Shared As Widget Ptr widget_last_pointer_target = 0
Dim Shared As Widget Ptr widget_focus = 0
Dim Shared As Widget Ptr widget_pending_front = 0
Dim Shared As Integer gui_UpdateInProgress
Dim Shared As Any Ptr gui_TextTransformHandler
Dim Shared As Integer gui_PreviousMouseButtons
Dim Shared As Integer gui_KeyboardFocusVisible
Dim Shared As Integer gui_ViewportWidth
Dim Shared As Integer gui_ViewportHeight
Dim Shared As UInteger gui_LayoutGeneration
Dim Shared As ULongInt gui_NextRegistryId

Const GUI_LAYOUT_PARENT_GUARD As Integer = 64
Const GUI_LAYOUT_MINIMUM_SIZE As Integer = 1
Const GUI_FOCUS_RING_INSET As Integer = 2
Const GUI_FOCUS_RING_MINIMUM_SIZE As Integer = 5
' gfxlib represents a portable keyboard scan code with one unsigned byte.
Const GUI_MNEMONIC_KEY_LAST As Integer = 255

Private Sub gui_ResetModalRootStack()
    For stack_index As Integer = 0 To GUI_MODAL_ROOT_MAXIMUM_DEPTH - 1
        widget_modal_root_stack(stack_index) = 0
    Next stack_index
    widget_modal_root_stack_count = 0
    widget_modal_root = 0
End Sub

' -------------------------------------------------------------------------
' Access-key captions
' -------------------------------------------------------------------------

Function gui_MnemonicScanCode( _
    ByVal characterCode As Integer _
) As Integer
    If characterCode >= Asc("a") AndAlso characterCode <= Asc("z") Then _
        characterCode -= Asc("a") - Asc("A")
    Select Case characterCode
    Case Asc("0"): Return FB.SC_0
    Case Asc("1"): Return FB.SC_1
    Case Asc("2"): Return FB.SC_2
    Case Asc("3"): Return FB.SC_3
    Case Asc("4"): Return FB.SC_4
    Case Asc("5"): Return FB.SC_5
    Case Asc("6"): Return FB.SC_6
    Case Asc("7"): Return FB.SC_7
    Case Asc("8"): Return FB.SC_8
    Case Asc("9"): Return FB.SC_9
    Case Asc("A"): Return FB.SC_A
    Case Asc("B"): Return FB.SC_B
    Case Asc("C"): Return FB.SC_C
    Case Asc("D"): Return FB.SC_D
    Case Asc("E"): Return FB.SC_E
    Case Asc("F"): Return FB.SC_F
    Case Asc("G"): Return FB.SC_G
    Case Asc("H"): Return FB.SC_H
    Case Asc("I"): Return FB.SC_I
    Case Asc("J"): Return FB.SC_J
    Case Asc("K"): Return FB.SC_K
    Case Asc("L"): Return FB.SC_L
    Case Asc("M"): Return FB.SC_M
    Case Asc("N"): Return FB.SC_N
    Case Asc("O"): Return FB.SC_O
    Case Asc("P"): Return FB.SC_P
    Case Asc("Q"): Return FB.SC_Q
    Case Asc("R"): Return FB.SC_R
    Case Asc("S"): Return FB.SC_S
    Case Asc("T"): Return FB.SC_T
    Case Asc("U"): Return FB.SC_U
    Case Asc("V"): Return FB.SC_V
    Case Asc("W"): Return FB.SC_W
    Case Asc("X"): Return FB.SC_X
    Case Asc("Y"): Return FB.SC_Y
    Case Asc("Z"): Return FB.SC_Z
    End Select
    Return 0
End Function


Function gui_ParseMnemonicCaption( _
    ByRef sourceText As Const String, ByRef displayText As String, _
    ByRef scanCode As Integer, ByRef displayIndex As Integer _
) As Integer
    /'
        A doubled ampersand is one literal ampersand. A single ampersand is a
        marker and is not displayed. The first marker followed by a supported
        ASCII letter or digit owns the Alt shortcut; later markers are still
        removed so rendering remains compatible with classic BASIC captions.
    '/
    Dim As Integer characterIndex = 1
    Dim As Integer outputIndex

    displayText = Space(Len(sourceText))
    displayIndex = -1
    scanCode = 0
    While characterIndex <= Len(sourceText)
        Dim As String characterText = Mid(sourceText, characterIndex, 1)
        If characterText = "&" Then
            If characterIndex < Len(sourceText) AndAlso _
               Mid(sourceText, characterIndex + 1, 1) = "&" Then
                outputIndex += 1
                displayText[outputIndex - 1] = Asc("&")
                characterIndex += 2
                Continue While
            End If
            If scanCode = 0 AndAlso characterIndex < Len(sourceText) Then
                Dim As Integer candidateCode = gui_MnemonicScanCode( _
                    Asc(sourceText, characterIndex + 1) _
                )
                If candidateCode <> 0 Then
                    scanCode = candidateCode
                    displayIndex = outputIndex
                End If
            End If
            characterIndex += 1
            Continue While
        End If
        outputIndex += 1
        ' outputIndex is bounded by the preallocated source-length buffer.
        displayText[outputIndex - 1] = Asc(characterText)
        characterIndex += 1
    Wend
    displayText = Left(displayText, outputIndex)
    Return IIf(scanCode <> 0, -1, 0)
End Function


Sub gui_RenderMnemonicUnderline( _
    ByVal w As Widget Ptr, ByRef display_text As Const String, _
    ByVal text_left As Integer, ByVal text_top As Integer, _
    ByVal text_height As Integer _
)
    If w = 0 OrElse w->mnemonic_key = 0 OrElse _
       Len(display_text) = 0 OrElse text_height < 3 Then Exit Sub
    For character_index As Integer = 1 To Len(display_text)
        If gui_MnemonicScanCode(Asc(display_text, character_index)) <> _
           w->mnemonic_key Then Continue For
        Dim As Integer underline_left = text_left + _
            backend_GetTextWidth(Left(display_text, character_index - 1))
        Dim As Integer glyph_width = backend_GetTextWidth( _
            Mid(display_text, character_index, 1) _
        )
        If glyph_width > 0 Then
            backend_Line _
                underline_left, text_top + text_height - 3, _
                underline_left + glyph_width - 1, _
                text_top + text_height - 3, _
                theme_GetClassicColor(GUI_CLASSIC_COLOR_ACCESS_TEXT)
        End If
        Exit Sub
    Next character_index
End Sub

' -------------------------------------------------------------------------
' Registry Management
' -------------------------------------------------------------------------

Function gui_CreateWidgetBase() As Widget Ptr
    ' New initializes every field, including managed strings and callbacks.
    Dim As Widget Ptr w = New Widget
    If w = 0 Then Return 0
    w->visible = -1
    w->enabled = -1
    Return w
End Function


Sub gui_Init()
    widget_list_head = 0
    widget_list_tail = 0
    gui_ResetModalRootStack()
    widget_pointer_capture = 0
    widget_last_pointer_target = 0
    widget_focus = 0
    widget_pending_front = 0
    gui_UpdateInProgress = 0
    gui_PreviousMouseButtons = 0
    gui_KeyboardFocusVisible = 0
    gui_LayoutGeneration = 0
    gui_NextRegistryId = 0
    backend_GetSize gui_ViewportWidth, gui_ViewportHeight

    If gui_ViewportWidth < GUI_LAYOUT_MINIMUM_SIZE Then _
        gui_ViewportWidth = GUI_LAYOUT_MINIMUM_SIZE
    If gui_ViewportHeight < GUI_LAYOUT_MINIMUM_SIZE Then _
        gui_ViewportHeight = GUI_LAYOUT_MINIMUM_SIZE
End Sub


Private Function gui_IsNameTaken(ByVal widgetName As String) As Integer
    Dim As Widget Ptr current = widget_list_head

    While current <> 0
        If LCase(current->name) = LCase(widgetName) Then Return -1
        current = current->next_widget
    Wend

    Return 0
End Function


Private Function gui_IsRegisteredWidget(ByVal target As Widget Ptr) As Integer
    Dim As Widget Ptr current = widget_list_head

    While current <> 0
        If current = target Then Return -1
        current = current->next_widget
    Wend

    Return 0
End Function

Function gui_IsWidgetRegistered(ByVal w As Widget Ptr) As Integer
    Return gui_IsRegisteredWidget(w)
End Function

Sub gui_SetTextTransformHandler(ByVal handler As Any Ptr)
    gui_TextTransformHandler = handler
End Sub

Function gui_TransformText(ByVal text As String) As String
    If gui_TextTransformHandler = 0 Then Return text
    Return Cast(Function(ByVal As String) As String, _
        gui_TextTransformHandler)(text)
End Function


Private Sub gui_AppendWidget(ByVal w As Widget Ptr)
    If w = 0 Then Exit Sub
    ' Never link one widget pointer into the registry more than once.
    If gui_IsRegisteredWidget(w) <> 0 Then Exit Sub
    ' Registering a hidden popup changes no pixels. Its first visible frame
    ' supplies damage through retained observation or conservative repainting.
    If w->visible <> 0 Then gui_InvalidateAll

    gui_NextRegistryId += 1
    If gui_NextRegistryId = 0 Then gui_NextRegistryId = 1
    w->registry_id = gui_NextRegistryId
    w->next_widget = 0
    If widget_list_head = 0 Then
        widget_list_head = w
        widget_list_tail = w
    Else
        widget_list_tail->next_widget = w
        widget_list_tail = w
    End If
End Sub


Private Function gui_IsSameRegisteredWidget( _
    ByVal target As Widget Ptr, _
    ByVal registryId As ULongInt _
) As Integer
    Dim current As Widget Ptr = widget_list_head

    If target = 0 OrElse registryId = 0 Then Return 0
    While current <> 0
        If current = target Then _
            Return IIf(current->registry_id = registryId, -1, 0)
        current = current->next_widget
    Wend
    Return 0
End Function


Sub gui_AddWidget(ByVal w As Widget Ptr)
    Dim As String baseName
    Dim As Integer suffix

    If w = 0 Then Exit Sub
    If gui_IsRegisteredWidget(w) <> 0 Then Exit Sub

    /'
        Names are public lookup keys. Preserve the original manager contract
        by suffixing duplicates instead of making gui_FindWidget ambiguous.
    '/
    If gui_IsNameTaken(w->name) Then
        baseName = w->name
        suffix = 1

        While gui_IsNameTaken(baseName & "_" & suffix)
            suffix += 1
        Wend

        w->name = baseName & "_" & suffix
    End If

    gui_AppendWidget w
End Sub


Sub gui_AddGeneratedWidget(ByVal w As Widget Ptr)
    /'
        Generated importers already allocate monotonic names. Their fast path
        deliberately skips the duplicate-name scan on very large HMI pages.
    '/
    gui_AppendWidget w
End Sub


Sub gui_SetParent(ByVal child As Widget Ptr, ByVal parent As Widget Ptr)
    Dim As Widget Ptr current
    Dim As Integer parentDepth

    If child = 0 Then Exit Sub
    If child = parent Then Exit Sub

    /'
        A parent cycle would make coordinate resolution and recursive removal
        unsafe. Walk the proposed chain before accepting it and reject chains
        that are cyclic or already exceed the supported hierarchy depth.
    '/
    current = parent
    parentDepth = 0

    While current <> 0 AndAlso parentDepth < GUI_LAYOUT_PARENT_GUARD
        If current = child Then Exit Sub
        current = current->parent
        parentDepth += 1
    Wend

    If current <> 0 Then Exit Sub
    child->parent = parent
End Sub


Sub gui_SetWidgetTheme(ByVal w As Widget Ptr, ByRef themeValue As GUI_Theme)
    If w = 0 Then Exit Sub
    Dim As GUI_Theme savedTheme = current_theme
    theme_SetCurrent themeValue
    w->theme_override = current_theme
    current_theme = savedTheme
    w->theme_override_enabled = -1
    gui_InvalidateAll
End Sub

Sub gui_ClearWidgetTheme(ByVal w As Widget Ptr)
    If w = 0 Then Exit Sub
    w->theme_override_enabled = 0
    gui_InvalidateAll
End Sub

Function gui_GetEffectiveWidgetTheme( _
    ByVal w As Widget Ptr, ByRef themeValue As GUI_Theme _
) As Integer
    Dim As Widget Ptr current = w
    Dim As Integer parentDepth

    If w = 0 Then Return 0

    While current <> 0 AndAlso parentDepth < GUI_LAYOUT_PARENT_GUARD
        If current->theme_override_enabled <> 0 Then
            themeValue = current->theme_override
            Return -1
        End If
        If current->appearance <> 0 Then
            themeValue = *current->appearance
            Return -1
        End If
        current = current->parent
        parentDepth += 1
    Wend

    theme_GetCurrent themeValue
    Return -1
End Function

Private Function gui_IsWithinTree( _
    ByVal w As Widget Ptr, ByVal root As Widget Ptr _
) As Integer
    Dim As Widget Ptr current = w
    Dim As Integer parentDepth

    If root = 0 Then Return 1

    While current <> 0 AndAlso parentDepth < GUI_LAYOUT_PARENT_GUARD
        If current = root Then Return 1
        current = current->parent
        parentDepth += 1
    Wend

    Return 0
End Function


Private Function gui_ModalRootStackIndex( _
    ByVal root As Widget Ptr _
) As Integer
    If root = 0 Then Return -1
    For stack_index As Integer = 0 To widget_modal_root_stack_count - 1
        If widget_modal_root_stack(stack_index) = root Then _
            Return stack_index
    Next stack_index
    Return -1
End Function


Private Sub gui_RemoveModalRootAt(ByVal stack_index As Integer)
    If stack_index < 0 OrElse _
       stack_index >= widget_modal_root_stack_count Then Exit Sub

    For move_index As Integer = stack_index To _
        widget_modal_root_stack_count - 2
        widget_modal_root_stack(move_index) = _
            widget_modal_root_stack(move_index + 1)
    Next move_index

    widget_modal_root_stack_count -= 1
    widget_modal_root_stack(widget_modal_root_stack_count) = 0
    widget_modal_root = 0
    If widget_modal_root_stack_count > 0 Then
        widget_modal_root = _
            widget_modal_root_stack(widget_modal_root_stack_count - 1)
    End If
End Sub


Private Sub gui_ApplyModalRoot()
    If widget_modal_root = 0 Then Exit Sub

    Dim As Widget Ptr current = widget_list_head
    While current <> 0
        If gui_IsWithinTree(current, widget_modal_root) = 0 AndAlso _
           current->cancel_input <> 0 Then _
            current->cancel_input(current)
        current = current->next_widget
    Wend

    If widget_pointer_capture <> 0 AndAlso _
       gui_IsWithinTree(widget_pointer_capture, widget_modal_root) = 0 Then _
        widget_pointer_capture = 0
End Sub


Private Sub gui_ClearModalRootsWithinTree(ByVal tree_root As Widget Ptr)
    If tree_root = 0 OrElse widget_modal_root_stack_count = 0 Then Exit Sub

    Dim As Widget Ptr previous_root = widget_modal_root
    Dim As Integer stack_index = 0
    While stack_index < widget_modal_root_stack_count
        If gui_IsWithinTree(widget_modal_root_stack(stack_index), tree_root) Then
            gui_RemoveModalRootAt stack_index
        Else
            stack_index += 1
        End If
    Wend

    If widget_modal_root <> previous_root Then gui_ApplyModalRoot()
End Sub


Private Function gui_FindOwningWindow( _
    ByVal w As Widget Ptr _
) As Widget Ptr
    Dim As Widget Ptr current = w
    Dim As Integer parentDepth

    While current <> 0 AndAlso parentDepth < GUI_LAYOUT_PARENT_GUARD
        If current->is_window <> 0 Then Return current
        current = current->parent
        parentDepth += 1
    Wend

    Return 0
End Function


Private Function gui_FindStackRoot(ByVal w As Widget Ptr) As Widget Ptr
    Dim As Widget Ptr current
    Dim As Widget Ptr windowRoot
    Dim As Integer parentDepth

    If w = 0 Then Return 0

    windowRoot = gui_FindOwningWindow(w)
    If windowRoot <> 0 Then Return windowRoot

    current = w
    While current->parent <> 0 AndAlso parentDepth < GUI_LAYOUT_PARENT_GUARD
        current = current->parent
        parentDepth += 1
    Wend

    If parentDepth >= GUI_LAYOUT_PARENT_GUARD Then Return 0
    Return current
End Function


Private Function gui_GetRetainedPaintBounds(ByVal w As Widget Ptr, _
    ByRef x As Integer, ByRef y As Integer, ByRef widthValue As Integer, _
    ByRef heightValue As Integer) As Integer
    x = w->ax: y = w->ay: widthValue = w->w: heightValue = w->h
    If w->render_bounds = 0 OrElse w->render_bounds_owner <> w->render Then Return 0
    If w->render_bounds(w, x, y, widthValue, heightValue) = 0 Then Return 0
    ' Both scene replay and damage use this read-only GUI-thread contract.
    ' A declined or malformed rectangle keeps the conservative path.
    If widthValue <= 0 OrElse heightValue <= 0 Then Return 0
    Dim As Integer screenWidth, screenHeight
    backend_GetSize screenWidth, screenHeight
    If x < 0 OrElse y < 0 OrElse x >= screenWidth OrElse y >= screenHeight Then Return 0
    If widthValue > screenWidth - x OrElse heightValue > screenHeight - y Then Return 0
    Return -1
End Function

Sub gui_BringToFront(ByVal w As Widget Ptr)
    Dim As Widget Ptr current
    Dim As Widget Ptr keepHead
    Dim As Widget Ptr keepTail
    Dim As Widget Ptr moveHead
    Dim As Widget Ptr moveTail
    Dim As Widget Ptr nextWidget
    Dim As Widget Ptr stackRoot
    Dim As Integer foundMember, needsReorder

    stackRoot = gui_FindStackRoot(w)
    If stackRoot = 0 Then Exit Sub
    /'
        Foreground requests made during registry traversal are deferred.
        Keep the latest request even if that tree is currently foremost: an
        earlier request in this frame may already be waiting to replace it.
    '/
    If gui_UpdateInProgress <> 0 Then
        widget_pending_front = stackRoot
        Exit Sub
    End If
    current = widget_list_head
    While current <> 0
        If current = stackRoot OrElse gui_IsWithinTree(current, stackRoot) <> 0 Then
            foundMember = -1
        ElseIf foundMember <> 0 Then
            needsReorder = -1
        End If
        current = current->next_widget
    Wend
    ' Repeated activation of the already foremost tree changes no paint order.
    If needsReorder = 0 Then Exit Sub
    Dim As Integer paintX, paintY, paintWidth, paintHeight
    If stackRoot->render_observation <> 0 AndAlso _
       gui_GetRetainedPaintBounds(stackRoot, paintX, paintY, paintWidth, paintHeight) <> 0 Then
        gui_InvalidateRect paintX, paintY, paintWidth, paintHeight
        If stackRoot->retained_visible <> 0 Then gui_InvalidateRect _
            stackRoot->retained_paint_x, stackRoot->retained_paint_y, _
            stackRoot->retained_paint_w, stackRoot->retained_paint_h
    Else
        gui_InvalidateAll
    End If

    /'
        The registry is also the paint order. Rebuild it as two stable lists,
        retaining the relative order of both the unaffected widgets and every
        member of the selected window tree. Appending the selected tree makes
        it the foreground window without invalidating widget pointers.
    '/
    current = widget_list_head

    While current <> 0
        nextWidget = current->next_widget
        current->next_widget = 0

        If current = stackRoot OrElse _
           gui_IsWithinTree(current, stackRoot) Then
            If moveHead = 0 Then
                moveHead = current
                moveTail = current
            Else
                moveTail->next_widget = current
                moveTail = current
            End If
        Else
            If keepHead = 0 Then
                keepHead = current
                keepTail = current
            Else
                keepTail->next_widget = current
                keepTail = current
            End If
        End If

        current = nextWidget
    Wend

    If moveHead = 0 Then Exit Sub

    If keepHead = 0 Then
        widget_list_head = moveHead
    Else
        widget_list_head = keepHead
        keepTail->next_widget = moveHead
    End If

    widget_list_tail = moveTail
End Sub


Sub gui_SetFocus(ByVal w As Widget Ptr)
    If w <> 0 AndAlso w->accepts_focus = 0 Then w = 0
    If widget_focus = w Then Exit Sub

    If widget_focus <> 0 Then widget_focus->has_focus = 0
    widget_focus = w
    If widget_focus <> 0 Then widget_focus->has_focus = -1
End Sub

Function gui_CaretBlinkVisible(ByVal secondsValue As Double) As Integer
    ' At 2^52 seconds a Double can no longer represent half-second phases.
    ' The bounded comparison also declines negative, infinite and NaN clocks.
    Const MAX_PHASE_SECONDS As Double = 4503599627370496.0
    If Not (secondsValue >= 0 AndAlso secondsValue < MAX_PHASE_SECONDS) Then Return 0
    ' INT returns Double here. Only the bounded fractional result is compared;
    ' DOS and 32-bit Unix clocks must never be narrowed to Integer first.
    Dim As Double fractionalSecond = secondsValue - Int(secondsValue)
    Return IIf(fractionalSecond < 0.5, -1, 0)
End Function


Function gui_GetFocus() As Widget Ptr
    Return widget_focus
End Function


Function gui_IsPointerTarget(ByVal w As Widget Ptr) As Integer
    If w = 0 Then Return 0
    Return IIf(widget_last_pointer_target = w, -1, 0)
End Function


Private Function gui_CanFocus(ByVal w As Widget Ptr) As Integer
    If w = 0 Then Return 0
    If w->accepts_focus = 0 Then Return 0
    If w->evis = 0 OrElse w->een = 0 Then Return 0
    If gui_IsWithinTree(w, widget_modal_root) = 0 Then Return 0
    Return -1
End Function


Private Function gui_TabOrderBefore( _
    ByVal firstWidget As Widget Ptr, _
    ByVal firstRegistration As Integer, _
    ByVal secondWidget As Widget Ptr, _
    ByVal secondRegistration As Integer _
) As Integer
    If firstWidget = 0 OrElse secondWidget = 0 Then Return 0

    If firstWidget->tab_order_known <> 0 AndAlso _
       secondWidget->tab_order_known = 0 Then Return -1
    If firstWidget->tab_order_known = 0 AndAlso _
       secondWidget->tab_order_known <> 0 Then Return 0
    If firstWidget->tab_order_known <> 0 AndAlso _
       firstWidget->tab_order <> secondWidget->tab_order Then
        Return IIf(firstWidget->tab_order < secondWidget->tab_order, -1, 0)
    End If

    Return IIf(firstRegistration < secondRegistration, -1, 0)
End Function


Private Function gui_KeyboardNavigationRequested() As Integer
    /'
        Mouse-focused controls still receive keyboard input, but the desktop
        focus cue follows Windows convention and appears only after a key that
        navigates or activates controls. Ordinary text entry does not turn a
        clicked textbox into keyboard-navigation mode.
    '/
    If input_KeyPressEvent(FB.SC_TAB) <> 0 Then Return -1
    If input_KeyPressEvent(KEY_UP) <> 0 Then Return -1
    If input_KeyPressEvent(KEY_DOWN) <> 0 Then Return -1
    If input_KeyPressEvent(KEY_LEFT) <> 0 Then Return -1
    If input_KeyPressEvent(KEY_RIGHT) <> 0 Then Return -1
    If input_KeyPressEvent(KEY_HOME) <> 0 Then Return -1
    If input_KeyPressEvent(KEY_END) <> 0 Then Return -1
    If input_KeyPressEvent(FB.SC_PAGEUP) <> 0 Then Return -1
    If input_KeyPressEvent(FB.SC_PAGEDOWN) <> 0 Then Return -1
    If input_KeyPressEvent(KEY_RETURN) <> 0 Then Return -1
    If input_KeyPressEvent(FB.SC_SPACE) <> 0 Then Return -1
    If input_KeyPressEvent(FB.SC_ALT) <> 0 Then Return -1
    Return 0
End Function


Private Sub gui_UpdateFocusCueMode(ByVal mouseButtons As Integer)
    /'
        A mouse press changes the input mode even when it lands on empty
        desktop. A navigation key in the same retained frame takes precedence
        because it is the newest evidence that keyboard focus should be shown.
    '/
    If mouseButtons <> 0 AndAlso gui_PreviousMouseButtons = 0 Then _
        gui_KeyboardFocusVisible = 0
    If gui_KeyboardNavigationRequested() <> 0 Then _
        gui_KeyboardFocusVisible = -1
End Sub


Sub gui_MoveFocus(ByVal reverseDirection As Integer)
    Dim As Widget Ptr current = widget_list_head
    Dim As Widget Ptr firstEligible
    Dim As Widget Ptr lastEligible
    Dim As Widget Ptr nextEligible
    Dim As Widget Ptr previousEligible
    Dim As Integer currentRegistration = -1
    Dim As Integer registrationIndex
    Dim As Integer firstRegistration
    Dim As Integer lastRegistration
    Dim As Integer nextRegistration
    Dim As Integer previousRegistration

    /'
        Explicit tab order is optional and does not disturb registry paint
        order. Controls with an explicit order come first, with registration
        order breaking ties; controls without one retain registration order
        afterward. Hidden, disabled, and modal-external controls are omitted
        so navigation agrees with pointer hit testing and cannot strand focus.
    '/
    While current <> 0
        If current = widget_focus Then currentRegistration = registrationIndex
        registrationIndex += 1
        current = current->next_widget
    Wend

    registrationIndex = 0
    current = widget_list_head
    While current <> 0
        If gui_CanFocus(current) AndAlso current->skip_tab_stop = 0 Then
            If firstEligible = 0 OrElse gui_TabOrderBefore( _
                current, registrationIndex, _
                firstEligible, firstRegistration _
            ) Then
                firstEligible = current
                firstRegistration = registrationIndex
            End If
            If lastEligible = 0 OrElse gui_TabOrderBefore( _
                lastEligible, lastRegistration, _
                current, registrationIndex _
            ) Then
                lastEligible = current
                lastRegistration = registrationIndex
            End If

            If currentRegistration >= 0 AndAlso current <> widget_focus Then
                If gui_TabOrderBefore( _
                    widget_focus, currentRegistration, _
                    current, registrationIndex _
                ) Then
                    If nextEligible = 0 OrElse gui_TabOrderBefore( _
                        current, registrationIndex, _
                        nextEligible, nextRegistration _
                    ) Then
                        nextEligible = current
                        nextRegistration = registrationIndex
                    End If
                ElseIf gui_TabOrderBefore( _
                    current, registrationIndex, _
                    widget_focus, currentRegistration _
                ) Then
                    If previousEligible = 0 OrElse gui_TabOrderBefore( _
                        previousEligible, previousRegistration, _
                        current, registrationIndex _
                    ) Then
                        previousEligible = current
                        previousRegistration = registrationIndex
                    End If
                End If
            End If
        End If

        registrationIndex += 1
        current = current->next_widget
    Wend

    If firstEligible = 0 Then
        gui_SetFocus 0
        Exit Sub
    End If

    If currentRegistration < 0 Then
        If reverseDirection <> 0 Then
            gui_SetFocus lastEligible
        Else
            gui_SetFocus firstEligible
        End If
    ElseIf reverseDirection <> 0 Then
        If previousEligible = 0 Then previousEligible = lastEligible
        gui_SetFocus previousEligible
    Else
        If nextEligible = 0 Then nextEligible = firstEligible
        gui_SetFocus nextEligible
    End If
End Sub


Sub gui_SetTabStop(ByVal w As Widget Ptr, ByVal enabled As Integer)
    If w = 0 Then Exit Sub
    w->skip_tab_stop = IIf(enabled, 0, -1)
End Sub

Function gui_GetTabStop(ByVal w As Widget Ptr) As Integer
    If w = 0 Then Return 0
    Return IIf(w->skip_tab_stop, 0, -1)
End Function

Function gui_SetTabOrder( _
    ByVal w As Widget Ptr, ByVal tabOrder As Integer _
) As Integer
    If w = 0 Then Return 0

    If tabOrder < 0 Then
        w->tab_order_known = 0
        w->tab_order = 0
    Else
        w->tab_order_known = -1
        w->tab_order = tabOrder
    End If
    Return -1
End Function


Function gui_GetTabOrder( _
    ByVal w As Widget Ptr, ByRef tabOrder As Integer _
) As Integer
    tabOrder = 0
    If w = 0 OrElse w->tab_order_known = 0 Then Return 0
    tabOrder = w->tab_order
    Return -1
End Function


Function gui_SetDefaultAction( _
    ByVal w As Widget Ptr, ByVal enabledState As Integer _
) As Integer
    If w = 0 OrElse w->activate = 0 Then Return 0
    w->is_default_action = IIf(enabledState <> 0, -1, 0)
    Return -1
End Function


Function gui_GetDefaultAction(ByVal w As Widget Ptr) As Integer
    If w = 0 Then Return 0
    Return IIf(w->is_default_action <> 0, -1, 0)
End Function


Function gui_SetCancelAction( _
    ByVal w As Widget Ptr, ByVal enabledState As Integer _
) As Integer
    If w = 0 OrElse w->activate = 0 Then Return 0
    w->is_cancel_action = IIf(enabledState <> 0, -1, 0)
    Return -1
End Function


Function gui_GetCancelAction(ByVal w As Widget Ptr) As Integer
    If w = 0 Then Return 0
    Return IIf(w->is_cancel_action <> 0, -1, 0)
End Function


Private Function gui_DialogActionScope() As Widget Ptr
    Dim As Widget Ptr current
    Dim As Widget Ptr owningWindow
    Dim As Widget Ptr topWindow

    If widget_modal_root <> 0 Then Return widget_modal_root
    owningWindow = gui_FindOwningWindow(widget_focus)
    If owningWindow <> 0 Then Return owningWindow

    /'
        With no focus, the last eligible window in registry order is the
        foreground desktop window. This is the same order used for rendering
        and pointer hit testing after gui_BringToFront rearranges a window tree.
    '/
    current = widget_list_head
    While current <> 0
        If current->is_window <> 0 AndAlso _
           current->evis <> 0 AndAlso current->een <> 0 Then topWindow = current
        current = current->next_widget
    Wend
    Return topWindow
End Function


Private Function gui_FindDialogAction( _
    ByVal defaultAction As Integer, _
    ByVal scopeRoot As Widget Ptr _
) As Widget Ptr
    Dim As Widget Ptr current
    Dim As Integer matchesRole

    current = widget_list_head
    While current <> 0
        matchesRole = IIf( _
            defaultAction <> 0, _
            current->is_default_action, current->is_cancel_action _
        )
        If matchesRole <> 0 AndAlso current->activate <> 0 AndAlso _
           current->evis <> 0 AndAlso current->een <> 0 AndAlso _
           gui_IsWithinTree(current, widget_modal_root) <> 0 AndAlso _
           (scopeRoot = 0 OrElse gui_IsWithinTree(current, scopeRoot) <> 0) Then _
            Return current
        current = current->next_widget
    Wend
    Return 0
End Function


Private Function gui_UnmodifiedKeyPress(ByVal keyCode As Integer) As Integer
    If input_KeyPressEvent(keyCode) = 0 Then Return 0
    If input_ModifiedKeyPressEvent( _
        keyCode, INPUT_MODIFIER_CONTROL _
    ) <> 0 Then Return 0
    If input_ModifiedKeyPressEvent( _
        keyCode, INPUT_MODIFIER_ALT _
    ) <> 0 Then Return 0
    If input_ModifiedKeyPressEvent( _
        keyCode, INPUT_MODIFIER_SHIFT _
    ) <> 0 Then Return 0
    Return -1
End Function


Private Sub gui_CaptureDialogActions( _
    ByVal scopeRoot As Widget Ptr, _
    ByVal focusTarget As Widget Ptr, _
    ByRef focusCapturesReturn As Integer, _
    ByRef focusCapturesEscape As Integer, _
    ByRef defaultTarget As Widget Ptr, _
    ByRef defaultRegistryId As ULongInt, _
    ByRef cancelTarget As Widget Ptr, _
    ByRef cancelRegistryId As ULongInt _
)
    focusCapturesReturn = 0
    focusCapturesEscape = 0
    defaultTarget = 0
    defaultRegistryId = 0
    cancelTarget = 0
    cancelRegistryId = 0

    If focusTarget <> 0 Then
        focusCapturesReturn = focusTarget->captures_return
        focusCapturesEscape = focusTarget->captures_escape
    End If

    If gui_UnmodifiedKeyPress(KEY_RETURN) <> 0 AndAlso _
       focusCapturesReturn = 0 Then
        defaultTarget = gui_FindDialogAction(-1, scopeRoot)
        If defaultTarget <> 0 Then _
            defaultRegistryId = defaultTarget->registry_id
    End If
    If gui_UnmodifiedKeyPress(KEY_ESCAPE) <> 0 AndAlso _
       focusCapturesEscape = 0 Then
        cancelTarget = gui_FindDialogAction(0, scopeRoot)
        If cancelTarget <> 0 Then _
            cancelRegistryId = cancelTarget->registry_id
    End If
End Sub


Private Sub gui_DispatchDialogAction( _
    ByVal focusCapturesReturn As Integer, _
    ByVal focusCapturesEscape As Integer, _
    ByVal scopeRoot As Widget Ptr, _
    ByVal scopeRegistryId As ULongInt, _
    ByVal defaultTarget As Widget Ptr, _
    ByVal defaultRegistryId As ULongInt, _
    ByVal cancelTarget As Widget Ptr, _
    ByVal cancelRegistryId As ULongInt _
)
    Dim As Widget Ptr actionTarget

    /'
        A focused control can reserve Enter or Escape when that key has local
        meaning, such as a list activation, multiline newline, or open popup.
        Action candidates are captured before widget callbacks and checked
        again here. Rebuilding a form therefore cannot route its old key to a
        new default or cancel button. Role targets need not accept focus;
        VBDOS often gives command buttons TabStop=False while assigning a role.
    '/
    If gui_UnmodifiedKeyPress(KEY_RETURN) <> 0 AndAlso _
       focusCapturesReturn = 0 Then
        actionTarget = defaultTarget
        If actionTarget <> 0 AndAlso _
           gui_IsSameRegisteredWidget(actionTarget, defaultRegistryId) <> 0 AndAlso _
           (scopeRoot = 0 OrElse _
            (gui_IsSameRegisteredWidget(scopeRoot, scopeRegistryId) <> 0 AndAlso _
             gui_IsWithinTree(actionTarget, scopeRoot) <> 0)) AndAlso _
           actionTarget->is_default_action <> 0 AndAlso _
           actionTarget->activate <> 0 AndAlso actionTarget->evis <> 0 AndAlso _
           actionTarget->een <> 0 AndAlso _
           gui_IsWithinTree(actionTarget, widget_modal_root) <> 0 Then
            actionTarget->activate(actionTarget)
        End If
    ElseIf gui_UnmodifiedKeyPress(KEY_ESCAPE) <> 0 AndAlso _
           focusCapturesEscape = 0 Then
        actionTarget = cancelTarget
        If actionTarget <> 0 AndAlso _
           gui_IsSameRegisteredWidget(actionTarget, cancelRegistryId) <> 0 AndAlso _
           (scopeRoot = 0 OrElse _
            (gui_IsSameRegisteredWidget(scopeRoot, scopeRegistryId) <> 0 AndAlso _
             gui_IsWithinTree(actionTarget, scopeRoot) <> 0)) AndAlso _
           actionTarget->is_cancel_action <> 0 AndAlso _
           actionTarget->activate <> 0 AndAlso actionTarget->evis <> 0 AndAlso _
           actionTarget->een <> 0 AndAlso _
           gui_IsWithinTree(actionTarget, widget_modal_root) <> 0 Then
            actionTarget->activate(actionTarget)
        End If
    End If
End Sub


Sub gui_SetMnemonic(ByVal w As Widget Ptr, ByVal keyCode As Integer)
    If w = 0 Then Exit Sub
    If keyCode < 0 OrElse keyCode > GUI_MNEMONIC_KEY_LAST Then keyCode = 0
    w->mnemonic_key = keyCode
End Sub


Function gui_SetMnemonicTarget( _
    ByVal sourceWidget As Widget Ptr, ByVal targetWidget As Widget Ptr _
) As Integer
    If gui_IsRegisteredWidget(sourceWidget) = 0 Then Return 0
    If targetWidget = 0 Then
        sourceWidget->mnemonic_target = 0
        Return -1
    End If
    If sourceWidget = targetWidget OrElse _
       gui_IsRegisteredWidget(targetWidget) = 0 Then Return 0
    sourceWidget->mnemonic_target = targetWidget
    Return -1
End Function


Function gui_GetMnemonicTarget( _
    ByVal sourceWidget As Widget Ptr _
) As Widget Ptr
    If gui_IsRegisteredWidget(sourceWidget) = 0 Then Return 0
    If sourceWidget->mnemonic_target <> 0 AndAlso _
       gui_IsRegisteredWidget(sourceWidget->mnemonic_target) = 0 Then _
        sourceWidget->mnemonic_target = 0
    Return sourceWidget->mnemonic_target
End Function

Private Function gui_FindMnemonicSource( _
    ByRef targetWidget As Widget Ptr _
) As Widget Ptr
    Dim As Widget Ptr current = widget_list_head

    targetWidget = 0
    While current <> 0
        If current->mnemonic_key <> 0 AndAlso current->evis <> 0 AndAlso _
           current->een <> 0 AndAlso _
           gui_IsWithinTree(current, widget_modal_root) <> 0 AndAlso _
           input_AltShortcutPressed(current->mnemonic_key) <> 0 Then
            targetWidget = gui_GetMnemonicTarget(current)
            If targetWidget <> 0 Then
                If gui_CanFocus(targetWidget) <> 0 AndAlso _
                   gui_FindOwningWindow(current) = _
                       gui_FindOwningWindow(targetWidget) Then Return current
            ElseIf current->activate <> 0 AndAlso _
                   gui_CanFocus(current) <> 0 Then
                Return current
            End If
        End If
        current = current->next_widget
    Wend

    Return 0
End Function


Function gui_IsKeyboardNavigationActive() As Integer
    Return IIf(gui_KeyboardFocusVisible <> 0, -1, 0)
End Function


Function gui_TrySetModalRoot(ByVal root As Widget Ptr) As Integer
    If root = 0 Then
        gui_ResetModalRootStack()
        Return -1
    End If
    If gui_IsRegisteredWidget(root) = 0 Then Return 0

    Dim As Integer stack_index = gui_ModalRootStackIndex(root)
    If stack_index >= 0 Then
        ' A repeated Show must not displace a newer, still-open modal child.
        Return -1
    End If
    If widget_modal_root_stack_count >= _
       GUI_MODAL_ROOT_MAXIMUM_DEPTH Then Return 0
    widget_modal_root_stack(widget_modal_root_stack_count) = root
    widget_modal_root_stack_count += 1

    widget_modal_root = root
    gui_ApplyModalRoot()
    Return -1
End Function


Sub gui_SetModalRoot(ByVal root As Widget Ptr)
    ' Preserve the original void API; callers needing overflow feedback can
    ' use gui_TrySetModalRoot instead.
    gui_TrySetModalRoot root
End Sub

Sub gui_CancelInput(ByVal root As Widget Ptr)
    ' Explicit cancellation also covers hide/show transitions occurring between
    ' frames. A null root selects the entire registry. Callbacks only discard
    ' private input state, so this walk cannot invalidate its next pointer.
    Dim As Widget Ptr current = widget_list_head
    While current <> 0
        If gui_IsWithinTree(current, root) AndAlso current->cancel_input <> 0 Then current->cancel_input(current)
        current = current->next_widget
    Wend
    If gui_IsWithinTree(widget_pointer_capture, root) Then widget_pointer_capture = 0
End Sub


Sub gui_ClearModalRoot(ByVal root As Widget Ptr)
    If root = 0 Then
        gui_ResetModalRootStack()
        Exit Sub
    End If

    Dim As Integer stack_index = gui_ModalRootStackIndex(root)
    If stack_index < 0 Then Exit Sub
    Dim As Widget Ptr previous_root = widget_modal_root
    gui_RemoveModalRootAt stack_index
    If widget_modal_root <> previous_root Then gui_ApplyModalRoot()
End Sub


Function gui_IsModalOpen() As Integer
    If widget_modal_root <> 0 Then Return 1
    Return 0
End Function


Function gui_SetVisible( _
    ByVal w As Widget Ptr, ByVal visibleState As Integer _
) As Integer
    Dim As Integer nextVisible = IIf(visibleState <> 0, -1, 0)

    If gui_IsRegisteredWidget(w) = 0 Then Return 0
    If w->visible = nextVisible Then Return -1

    If nextVisible = 0 Then
        /'
            A hidden tree cannot retain drag capture, modal roots, or focus.
            Clear those references before exposing another tree so a later
            show begins from a neutral input state.
        '/
        gui_ClearModalRootsWithinTree w
        If widget_focus <> 0 AndAlso _
           gui_IsWithinTree(widget_focus, w) Then gui_SetFocus 0
        gui_CancelInput w
    End If

    w->visible = nextVisible
    Return -1
End Function


Function gui_GetVisible(ByVal w As Widget Ptr) As Integer
    If gui_IsRegisteredWidget(w) = 0 Then Return 0
    Return IIf(w->visible <> 0, -1, 0)
End Function


' -------------------------------------------------------------------------
' Reactive layout
' -------------------------------------------------------------------------

Private Sub gui_AdvanceLayoutGeneration()
    If gui_LayoutGeneration >= &H7FFFFFF0 Then
        gui_LayoutGeneration = 1

        Dim As Widget Ptr current = widget_list_head
        While current <> 0
            current->layout_generation = 0
            current = current->next_widget
        Wend
    Else
        gui_LayoutGeneration += 1
    End If
End Sub


Private Sub gui_ApplyWidgetAnchors( _
    ByVal w As Widget Ptr, _
    ByVal parentDepth As Integer _
)

    Dim As Integer containerWidth
    Dim As Integer containerHeight
    Dim As Integer deltaWidth
    Dim As Integer deltaHeight
    Dim As UInteger horizontalAnchors
    Dim As UInteger verticalAnchors

    If w = 0 OrElse w->layout_generation = gui_LayoutGeneration Then Exit Sub

    If parentDepth >= GUI_LAYOUT_PARENT_GUARD Then
        w->visible = 0
        w->enabled = 0
        w->layout_generation = gui_LayoutGeneration
        Exit Sub
    End If

    If w->parent <> 0 Then
        gui_ApplyWidgetAnchors w->parent, parentDepth + 1
        containerWidth = w->parent->w
        containerHeight = w->parent->h
    Else
        containerWidth = gui_ViewportWidth
        containerHeight = gui_ViewportHeight
    End If

    If w->layout_initialized <> 0 Then
        deltaWidth = containerWidth - w->layout_container_w
        deltaHeight = containerHeight - w->layout_container_h
        horizontalAnchors = w->anchor_flags And _
            (GUI_ANCHOR_LEFT Or GUI_ANCHOR_RIGHT)
        verticalAnchors = w->anchor_flags And _
            (GUI_ANCHOR_TOP Or GUI_ANCHOR_BOTTOM)

        Select Case horizontalAnchors
        Case GUI_ANCHOR_LEFT Or GUI_ANCHOR_RIGHT
            w->x = w->layout_base_x
            w->w = w->layout_base_w + deltaWidth
        Case GUI_ANCHOR_RIGHT
            w->x = w->layout_base_x + deltaWidth
            w->w = w->layout_base_w
        Case GUI_ANCHOR_LEFT
            w->x = w->layout_base_x
            w->w = w->layout_base_w
        Case Else
            w->x = w->layout_base_x + deltaWidth \ 2
            w->w = w->layout_base_w
        End Select

        Select Case verticalAnchors
        Case GUI_ANCHOR_TOP Or GUI_ANCHOR_BOTTOM
            w->y = w->layout_base_y
            w->h = w->layout_base_h + deltaHeight
        Case GUI_ANCHOR_BOTTOM
            w->y = w->layout_base_y + deltaHeight
            w->h = w->layout_base_h
        Case GUI_ANCHOR_TOP
            w->y = w->layout_base_y
            w->h = w->layout_base_h
        Case Else
            w->y = w->layout_base_y + deltaHeight \ 2
            w->h = w->layout_base_h
        End Select

        If w->w < GUI_LAYOUT_MINIMUM_SIZE Then w->w = GUI_LAYOUT_MINIMUM_SIZE
        If w->h < GUI_LAYOUT_MINIMUM_SIZE Then w->h = GUI_LAYOUT_MINIMUM_SIZE
    End If

    w->layout_generation = gui_LayoutGeneration

End Sub


Private Sub gui_ApplyReactiveLayout()

    gui_AdvanceLayoutGeneration

    Dim As Widget Ptr current = widget_list_head
    While current <> 0
        gui_ApplyWidgetAnchors current, 0
        current = current->next_widget
    Wend

End Sub


Sub gui_SetViewportSize(ByVal w As Integer, ByVal h As Integer)

    If w < GUI_LAYOUT_MINIMUM_SIZE Then w = GUI_LAYOUT_MINIMUM_SIZE
    If h < GUI_LAYOUT_MINIMUM_SIZE Then h = GUI_LAYOUT_MINIMUM_SIZE

    If w = gui_ViewportWidth AndAlso h = gui_ViewportHeight Then Exit Sub

    gui_ViewportWidth = w
    gui_ViewportHeight = h
    gui_ApplyReactiveLayout

End Sub


Sub gui_GetViewportSize(ByRef w As Integer, ByRef h As Integer)
    w = gui_ViewportWidth
    h = gui_ViewportHeight
End Sub


Sub gui_SetAnchors(ByVal w As Widget Ptr, ByVal anchorFlags As UInteger)

    If w = 0 Then Exit Sub

    w->anchor_flags = anchorFlags And GUI_ANCHOR_ALL
    w->layout_initialized = -1
    w->layout_base_x = w->x
    w->layout_base_y = w->y
    w->layout_base_w = w->w
    w->layout_base_h = w->h

    If w->parent <> 0 Then
        w->layout_container_w = w->parent->w
        w->layout_container_h = w->parent->h
    Else
        w->layout_container_w = gui_ViewportWidth
        w->layout_container_h = gui_ViewportHeight
    End If

    gui_ApplyReactiveLayout

End Sub


Sub gui_ResetAnchors(ByVal w As Widget Ptr)
    If w = 0 Then Exit Sub

    w->anchor_flags = GUI_ANCHOR_NONE
    w->layout_initialized = 0
    w->layout_generation = 0
End Sub


Private Sub gui_RebaseWidgetLayout(ByVal w As Widget Ptr)
    If w = 0 OrElse w->layout_initialized = 0 Then Exit Sub

    w->layout_base_x = w->x
    w->layout_base_y = w->y
    w->layout_base_w = w->w
    w->layout_base_h = w->h

    If w->parent <> 0 Then
        w->layout_container_w = w->parent->w
        w->layout_container_h = w->parent->h
    Else
        w->layout_container_w = gui_ViewportWidth
        w->layout_container_h = gui_ViewportHeight
    End If
End Sub


Function gui_SetBounds( _
    ByVal w As Widget Ptr, ByVal x As Integer, ByVal y As Integer, _
    ByVal widthValue As Integer, ByVal heightValue As Integer _
) As Integer
    /'
        A caller-controlled layout must not leave reactive anchors attached to
        an old rectangle. Rebase after changing all four values so a later
        viewport resize starts from the new logical bounds instead of snapping
        the widget back to its former location.
    '/
    If w = 0 OrElse widthValue < GUI_LAYOUT_MINIMUM_SIZE OrElse _
       heightValue < GUI_LAYOUT_MINIMUM_SIZE Then Return 0

    w->x = x
    w->y = y
    w->w = widthValue
    w->h = heightValue
    gui_RebaseWidgetLayout w
    gui_ApplyReactiveLayout
    Return -1
End Function


Private Function gui_PointWithinWidget( _
    ByVal w As Widget Ptr, _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer _
) As Integer
    Dim As Integer bottomEdge
    Dim As Integer leftEdge
    Dim As Integer rightEdge
    Dim As Integer topEdge

    If w = 0 Then Return 0

    leftEdge = w->ax
    topEdge = w->ay
    rightEdge = w->ax + w->w
    bottomEdge = w->ay + w->h

    If rightEdge < leftEdge Then Swap rightEdge, leftEdge
    If bottomEdge < topEdge Then Swap bottomEdge, topEdge

    If pointerX >= leftEdge AndAlso pointerX < rightEdge AndAlso _
       pointerY >= topEdge AndAlso pointerY < bottomEdge Then
        Return -1
    End If

    Return 0
End Function


Private Function gui_PointWithinParentClients( _
    ByVal w As Widget Ptr, _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer _
) As Integer
    Dim As Integer clipHeight
    Dim As Integer clipWidth
    Dim As Integer clipX
    Dim As Integer clipY
    Dim As Widget Ptr parent
    Dim As Integer parentDepth

    If w = 0 Then Return 0

    If w->escape_parent_clip <> 0 Then Return -1

    parent = w->parent
    While parent <> 0 AndAlso parentDepth < GUI_LAYOUT_PARENT_GUARD
        If parent->clip_children <> 0 Then
            clipX = parent->ax + parent->child_clip_x
            clipY = parent->ay + parent->child_clip_y
            clipWidth = parent->w - parent->child_clip_x - _
                parent->child_clip_right
            clipHeight = parent->h - parent->child_clip_y - _
                parent->child_clip_bottom

            If pointerX < clipX OrElse pointerX >= clipX + clipWidth OrElse _
               pointerY < clipY OrElse pointerY >= clipY + clipHeight Then
                Return 0
            End If
        End If

        parent = parent->parent
        parentDepth += 1
    Wend

    If parent <> 0 Then Return 0
    Return -1
End Function


Private Function gui_FindTopmostWindowAt( _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer _
) As Widget Ptr
    Dim As Widget Ptr current = widget_list_head
    Dim As Widget Ptr result

    While current <> 0
        If current->is_window <> 0 AndAlso current->evis <> 0 AndAlso _
           current->een <> 0 AndAlso _
           gui_IsWithinTree(current, widget_modal_root) <> 0 AndAlso _
           gui_PointWithinWidget(current, pointerX, pointerY) <> 0 AndAlso _
           gui_PointWithinParentClients( _
               current, pointerX, pointerY _
           ) <> 0 Then
            result = current
        End If

        current = current->next_widget
    Wend

    Return result
End Function


Private Function gui_FindTopmostPointerWidget( _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer _
) As Widget Ptr
    Dim As Widget Ptr current = widget_list_head
    Dim As Widget Ptr owningWindow
    Dim As Widget Ptr result
    Dim As Widget Ptr topWindow

    topWindow = gui_FindTopmostWindowAt(pointerX, pointerY)

    While current <> 0
        If current->update <> 0 AndAlso current->evis <> 0 AndAlso _
           current->een <> 0 AndAlso _
           gui_IsWithinTree(current, widget_modal_root) <> 0 Then
            owningWindow = gui_FindOwningWindow(current)

            If (topWindow = 0 AndAlso owningWindow = 0) OrElse _
               owningWindow = topWindow OrElse current->pointer_global <> 0 Then
                If current->pointer_global <> 0 OrElse _
                   (gui_PointWithinWidget( _
                       current, pointerX, pointerY _
                   ) <> 0 AndAlso _
                   gui_PointWithinParentClients( _
                       current, pointerX, pointerY _
                   ) <> 0) Then
                    If current->pointer_test = 0 Then
                        result = current
                    ElseIf current->pointer_test(current, pointerX, pointerY) <> 0 Then
                        result = current
                    End If
                End If
            End If
        End If

        current = current->next_widget
    Wend

    Return result
End Function


Private Function gui_FindGlobalKeyboardWidget( _
    ByVal keyboardScope As Widget Ptr _
) As Widget Ptr
    Dim As Widget Ptr current = widget_list_head
    Dim As Widget Ptr result

    /'
        Global keyboard dispatch is deliberately narrower than a registry-wide
        broadcast. The last eligible entry is visually foremost after
        gui_BringToFront, and the active modal or form scope prevents a
        background window's command bar from receiving the foreground chord.
    '/
    While current <> 0
        If current->keyboard_global <> 0 AndAlso current->update <> 0 AndAlso _
           current->evis <> 0 AndAlso current->een <> 0 AndAlso _
           gui_IsWithinTree(current, widget_modal_root) <> 0 Then
            If keyboardScope = 0 Then
                If gui_FindOwningWindow(current) = 0 Then result = current
            ElseIf current = keyboardScope OrElse _
                   gui_IsWithinTree(current, keyboardScope) <> 0 Then
                result = current
            End If
        End If
        current = current->next_widget
    Wend

    Return result
End Function


Private Function gui_GetWidgetRenderClip( _
    ByVal w As Widget Ptr, _
    ByRef clipX As Integer, _
    ByRef clipY As Integer, _
    ByRef clipWidth As Integer, _
    ByRef clipHeight As Integer _
) As Integer
    Dim As Integer clipBottom
    Dim As Integer clipRight
    Dim As Integer parentBottom
    Dim As Integer parentLeft
    Dim As Integer parentRight
    Dim As Integer parentTop
    Dim As Widget Ptr parent
    Dim As Integer parentDepth

    backend_GetSize clipWidth, clipHeight
    clipX = 0
    clipY = 0

    If clipWidth <= 0 OrElse clipHeight <= 0 Then Return 0
    If w = 0 Then Return 0

    If w->escape_parent_clip <> 0 Then Return -1

    clipRight = clipWidth
    clipBottom = clipHeight

    parent = w->parent
    While parent <> 0 AndAlso parentDepth < GUI_LAYOUT_PARENT_GUARD
        If parent->clip_children <> 0 Then
            parentLeft = parent->ax + parent->child_clip_x
            parentTop = parent->ay + parent->child_clip_y
            parentRight = parent->ax + parent->w - _
                parent->child_clip_right
            parentBottom = parent->ay + parent->h - _
                parent->child_clip_bottom

            If clipX < parentLeft Then clipX = parentLeft
            If clipY < parentTop Then clipY = parentTop
            If clipRight > parentRight Then clipRight = parentRight
            If clipBottom > parentBottom Then clipBottom = parentBottom
        End If

        parent = parent->parent
        parentDepth += 1
    Wend

    clipWidth = clipRight - clipX
    clipHeight = clipBottom - clipY

    If parent <> 0 OrElse clipWidth <= 0 OrElse clipHeight <= 0 Then Return 0
    Return -1
End Function


Private Sub gui_ResolveLayout()
    Dim As Widget Ptr current = widget_list_head
    Dim As Integer guard

    While current <> 0
        guard = 0

        If current->parent = 0 Then
            current->ax = current->x
            current->ay = current->y
            current->evis = current->visible
            current->een = current->enabled
        Else
            /'
                Parents are added before their child controls in the editor and
                generated dialogs.  The guard keeps malformed parent cycles
                from turning a UI update into an infinite loop.
            '/
            current->ax = current->x
            current->ay = current->y
            current->evis = current->visible
            current->een = current->enabled

            Dim As Widget Ptr parent = current->parent
            While parent <> 0 AndAlso guard < GUI_LAYOUT_PARENT_GUARD
                current->ax += parent->x
                current->ay += parent->y
                current->evis = current->evis And parent->visible
                current->een = current->een And parent->enabled
                If parent->suspend_children <> 0 Then current->een = 0
                parent = parent->parent
                guard += 1
            Wend

            If guard >= GUI_LAYOUT_PARENT_GUARD Then
                current->evis = 0
                current->een = 0
            End If
        End If

        current = current->next_widget
    Wend
End Sub


Sub gui_SynchronizeLayout()
    /'
        Geometry writers may need current absolute coordinates before the next
        input frame. Resolving layout alone avoids advancing input, animation,
        or widget event state merely to obtain those coordinates.
    '/
    gui_ResolveLayout
End Sub


Private Sub gui_DeleteWidget(ByVal target As Widget Ptr)
    Dim As Widget Ptr current
    Dim As Widget Ptr previous
    Dim As Widget Ptr referenceWidget

    If target = 0 Then Exit Sub
    ' An unpainted hidden node has no surface to erase. Other removal retains
    ' the conservative path, including visible descendants and decorations.
    If target->visible <> 0 OrElse target->retained_visible <> 0 Then gui_InvalidateAll

    /'
        Mnemonic targets are weak registry references. Clear inbound pointers
        before invoking the target's destructor so later Alt dispatch cannot
        dereference released widget storage.
    '/
    referenceWidget = widget_list_head
    While referenceWidget <> 0
        If referenceWidget->mnemonic_target = target Then _
            referenceWidget->mnemonic_target = 0
        referenceWidget = referenceWidget->next_widget
    Wend

    current = widget_list_head
    previous = 0

    While current <> 0
        If current = target Then
            If previous = 0 Then
                widget_list_head = current->next_widget
            Else
                previous->next_widget = current->next_widget
            End If

            If widget_list_tail = current Then widget_list_tail = previous

            If current->destroy <> 0 Then current->destroy(current)
            Delete current
            Exit Sub
        End If

        previous = current
        current = current->next_widget
    Wend
End Sub


Private Sub gui_DeleteWidgetTree(ByVal target As Widget Ptr)
    Dim As Widget Ptr current
    Dim As Integer removedChild

    If target = 0 Then Exit Sub

    ' Modal roots are non-owning references and must be removed before any
    ' node in the deleted tree can be released.
    gui_ClearModalRootsWithinTree target

    If widget_focus <> 0 AndAlso _
       gui_IsWithinTree(widget_focus, target) Then
        gui_SetFocus 0
    End If

    If widget_pointer_capture <> 0 AndAlso _
       gui_IsWithinTree(widget_pointer_capture, target) Then
        widget_pointer_capture = 0
    End If

    If widget_last_pointer_target <> 0 AndAlso _
       gui_IsWithinTree(widget_last_pointer_target, target) Then
        widget_last_pointer_target = 0
    End If

    If widget_pending_front <> 0 AndAlso _
       gui_IsWithinTree(widget_pending_front, target) Then
        widget_pending_front = 0
    End If

    Do
        removedChild = 0
        current = widget_list_head

        While current <> 0
            If current->parent = target Then
                gui_DeleteWidgetTree current
                removedChild = 1
                Exit While
            End If

            current = current->next_widget
        Wend
    Loop While removedChild <> 0

    gui_DeleteWidget target
End Sub

Sub gui_ResetForTest()
    gui_InvalidateAll
    gui_TextTransformHandler = 0
    While widget_list_head <> 0
        gui_DeleteWidgetTree widget_list_head
    Wend

    gui_ResetModalRootStack()
    widget_list_tail = 0
    widget_pointer_capture = 0
    widget_last_pointer_target = 0
    widget_pending_front = 0
    gui_UpdateInProgress = 0
    gui_PreviousMouseButtons = 0
    gui_KeyboardFocusVisible = 0
    gui_SetFocus 0
End Sub

Function gui_RemoveWidgetPtr(ByVal target As Widget Ptr) As Integer
    If target = 0 Then Return 0

    ' Validate registry membership before dereferencing the borrowed pointer.
    ' This makes repeated owner cleanup harmless after a parent removed a tree.
    Dim As Widget Ptr current = widget_list_head
    While current <> 0
        If current = target Then
            gui_DeleteWidgetTree current
            Return -1
        End If
        current = current->next_widget
    Wend
    Return 0
End Function

Sub gui_RemoveWidget(ByVal nm As String)
    Dim As Widget Ptr curr = widget_list_head
    While curr <> 0
        If LCase(curr->name) = LCase(nm) Then
            gui_RemoveWidgetPtr curr
            Exit Sub
        End If
        curr = curr->next_widget
    Wend
End Sub

Function gui_FindWidget(ByVal nm As String) As Widget Ptr
    Dim As Widget Ptr curr = widget_list_head
    While curr <> 0
        If LCase(curr->name) = LCase(nm) Then Return curr : End If
        curr = curr->next_widget
    Wend
    Return 0
End Function

Sub gui_DeselectRadioGroup(ByVal group_id As Integer, ByVal caller As Widget Ptr)
    Dim As Widget Ptr curr = widget_list_head
    While curr <> 0
        If curr <> caller And curr->render = @radiobox_Render Then
            Dim As RadioBoxData Ptr d = curr->data
            If d->group_id = group_id Then d->selected = 0
        End If
        curr = curr->next_widget
    Wend
End Sub

' -------------------------------------------------------------------------
' Processing Loops
' -------------------------------------------------------------------------

Sub gui_UpdateAll()
    Dim As Integer allowKeyboard
    Dim As Integer allowPointer
    Dim As Integer mouseButtons
    Dim As Integer mouseX
    Dim As Integer mouseY
    Dim As Widget Ptr pointerTarget
    Dim As Widget Ptr releasedCapture
    Dim As Widget Ptr topWindow
    Dim As Widget Ptr keyboardScope
    Dim As Widget Ptr globalKeyboardTarget
    Dim As Widget Ptr keyboardFocusTarget
    Dim As Widget Ptr defaultActionTarget
    Dim As Widget Ptr cancelActionTarget
    Dim As Widget Ptr mnemonicSource
    Dim As Widget Ptr mnemonicTarget
    Dim As Widget Ptr curr
    Dim As Integer viewportWidth
    Dim As Integer viewportHeight
    Dim As Integer previousX
    Dim As Integer previousY
    Dim As Integer previousWidth
    Dim As Integer previousHeight
    Dim As Integer previousEnabled
    Dim As Integer previousVisible
    Dim As Integer tabCaptured
    Dim As ULongInt currentRegistryId
    Dim As ULongInt pointerTargetRegistryId
    Dim As ULongInt keyboardFocusRegistryId
    Dim As ULongInt globalKeyboardRegistryId
    Dim As ULongInt keyboardScopeRegistryId
    Dim As ULongInt defaultActionRegistryId
    Dim As ULongInt cancelActionRegistryId
    Dim As ULongInt mnemonicSourceRegistryId
    Dim As ULongInt mnemonicTargetRegistryId
    Dim As Integer mnemonicKey
    Dim As Integer keyboardFocusCapturesReturn
    Dim As Integer keyboardFocusCapturesEscape

    defaultActionTarget = 0
    cancelActionTarget = 0
    mnemonicSource = 0
    mnemonicTarget = 0
    keyboardFocusRegistryId = 0
    globalKeyboardRegistryId = 0
    keyboardScopeRegistryId = 0
    defaultActionRegistryId = 0
    cancelActionRegistryId = 0
    mnemonicSourceRegistryId = 0
    mnemonicTargetRegistryId = 0
    mnemonicKey = 0
    keyboardFocusCapturesReturn = 0
    keyboardFocusCapturesEscape = 0

    input_Update()
    backend_GetSize viewportWidth, viewportHeight
    gui_SetViewportSize viewportWidth, viewportHeight

    gui_ResolveLayout()

    If widget_focus <> 0 AndAlso gui_CanFocus(widget_focus) = 0 Then _
        gui_SetFocus 0
    If widget_modal_root <> 0 AndAlso widget_focus = 0 Then _
        gui_MoveFocus 0

    /'
        Read the unmasked frame input once. Each widget update below receives
        a dispatch mask, which prevents overlapping controls from observing
        the same pointer transition while preserving ordinary update calls for
        animation and non-input state.
    '/
    input_SetDispatchMask -1, -1
    mouseX = input_MouseX()
    mouseY = input_MouseY()
    mouseButtons = input_MouseButtons()

    gui_UpdateFocusCueMode mouseButtons

    If widget_pointer_capture <> 0 Then
        pointerTarget = widget_pointer_capture

        If mouseButtons = 0 Then
            releasedCapture = widget_pointer_capture
            widget_pointer_capture = 0
        End If
    Else
        pointerTarget = gui_FindTopmostPointerWidget(mouseX, mouseY)

        /'
            Pointer capture begins only on a button transition. Without this
            edge check, a press which started on empty desktop could be
            dragged onto a button or list row and activate it on release even
            though that control never received the original press.
        '/
        If mouseButtons <> 0 AndAlso gui_PreviousMouseButtons = 0 AndAlso _
           pointerTarget <> 0 Then
            topWindow = gui_FindOwningWindow(pointerTarget)

            If topWindow <> 0 Then
                gui_BringToFront topWindow
                gui_ResolveLayout
                pointerTarget = gui_FindTopmostPointerWidget(mouseX, mouseY)
            End If

            widget_pointer_capture = pointerTarget

            If pointerTarget->accepts_focus <> 0 Then
                gui_SetFocus pointerTarget
            Else
                gui_SetFocus 0
            End If
        ElseIf mouseButtons <> 0 AndAlso gui_PreviousMouseButtons <> 0 Then
            pointerTarget = 0
        End If
    End If

    If releasedCapture <> 0 Then pointerTarget = releasedCapture
    widget_last_pointer_target = pointerTarget
    If pointerTarget <> 0 Then _
        pointerTargetRegistryId = pointerTarget->registry_id

    /'
        Tab normally belongs to the manager. A focused editor can explicitly
        capture an unmodified Tab for indentation, but Shift+Tab and modified
        Tab presses remain navigation commands. Native key events retain the
        modifier state from the instant of the press, so quick modifier chords
        are still routed correctly after the keys have been released.
    '/
    input_SetDispatchMask -1, -1
    If input_KeyPressEvent(FB.SC_TAB) <> 0 Then
        tabCaptured = IIf( _
            widget_focus <> 0 AndAlso widget_focus->captures_tab <> 0 AndAlso _
            input_ModifiedKeyPressEvent( _
                FB.SC_TAB, INPUT_MODIFIER_CONTROL _
            ) = 0 AndAlso _
            input_ModifiedKeyPressEvent( _
                FB.SC_TAB, INPUT_MODIFIER_ALT _
            ) = 0 AndAlso _
            input_ModifiedKeyPressEvent( _
                FB.SC_TAB, INPUT_MODIFIER_SHIFT _
            ) = 0, _
            -1, 0 _
        )
        If tabCaptured = 0 Then
            gui_MoveFocus input_ModifiedKeyPressEvent( _
                FB.SC_TAB, INPUT_MODIFIER_SHIFT _
            )
        End If
    End If

    /'
        Keyboard events belong to the controls that owned focus and form-wide
        actions at the start of this update. Registry IDs make those borrowed
        identities safe to compare after a callback rebuilds a widget tree.
    '/
    keyboardScope = gui_DialogActionScope()
    globalKeyboardTarget = gui_FindGlobalKeyboardWidget(keyboardScope)
    keyboardFocusTarget = widget_focus
    If keyboardScope <> 0 Then _
        keyboardScopeRegistryId = keyboardScope->registry_id
    If keyboardFocusTarget <> 0 Then
        keyboardFocusRegistryId = keyboardFocusTarget->registry_id
    End If
    If globalKeyboardTarget <> 0 Then _
        globalKeyboardRegistryId = globalKeyboardTarget->registry_id
    gui_CaptureDialogActions( _
        keyboardScope, keyboardFocusTarget, _
        keyboardFocusCapturesReturn, keyboardFocusCapturesEscape, _
        defaultActionTarget, defaultActionRegistryId, _
        cancelActionTarget, cancelActionRegistryId _
    )
    mnemonicSource = gui_FindMnemonicSource(mnemonicTarget)
    If mnemonicSource <> 0 Then
        mnemonicSourceRegistryId = mnemonicSource->registry_id
        mnemonicKey = mnemonicSource->mnemonic_key
        If mnemonicTarget <> 0 Then _
            mnemonicTargetRegistryId = mnemonicTarget->registry_id
    End If

    curr = widget_list_head
    gui_UpdateInProgress = -1

    While curr <> 0
        curr->updated_this_frame = 0
        curr = curr->next_widget
    Wend
    curr = widget_list_head

    While curr <> 0
        If curr->updated_this_frame <> 0 Then
            curr = curr->next_widget
            Continue While
        End If
        curr->updated_this_frame = 1
        currentRegistryId = curr->registry_id
        previousX = curr->x
        previousY = curr->y
        previousWidth = curr->w
        previousHeight = curr->h
        previousVisible = curr->visible
        previousEnabled = curr->enabled

        If curr->evis AndAlso curr->een AndAlso _
           gui_IsWithinTree(curr, widget_modal_root) Then
            allowPointer = IIf( _
                curr = pointerTarget AndAlso _
                currentRegistryId = pointerTargetRegistryId, -1, 0 _
            )
            allowKeyboard = IIf( _
                (curr = keyboardFocusTarget AndAlso _
                 currentRegistryId = keyboardFocusRegistryId) OrElse _
                (curr = globalKeyboardTarget AndAlso _
                 currentRegistryId = globalKeyboardRegistryId), _
                -1, 0 _
            )
            input_SetDispatchMask allowPointer, allowKeyboard

            If curr->update <> 0 Then curr->update(curr)
        ElseIf curr->cancel_input <> 0 Then
            curr->cancel_input(curr)
        End If

        /'
            A control activation may remove its own window and construct the
            replacement before returning. Restart from the live registry when
            that happens. The per-frame marker prevents earlier widgets from
            running twice, while a new registration ID distinguishes an
            allocator-reused address from the deleted control.
        '/
        If gui_IsSameRegisteredWidget(curr, currentRegistryId) = 0 Then
            gui_ResolveLayout()
            curr = widget_list_head
            Continue While
        End If

        /'
            Most controls do not change their rectangle during update. Only
            resolve the complete hierarchy again when a movable or resizable
            parent actually changed, preserving correct child input without
            turning every frame into a quadratic registry walk.
        '/
        If curr->x <> previousX OrElse curr->y <> previousY OrElse _
           curr->w <> previousWidth OrElse curr->h <> previousHeight Then
            gui_RebaseWidgetLayout curr
            gui_ResolveLayout()
        ElseIf curr->visible <> previousVisible OrElse _
               curr->enabled <> previousEnabled Then
            gui_ResolveLayout()
        End If

        curr = curr->next_widget
    Wend

    gui_UpdateInProgress = 0
    input_SetDispatchMask -1, -1
    gui_DispatchDialogAction( _
        keyboardFocusCapturesReturn, keyboardFocusCapturesEscape, _
        keyboardScope, keyboardScopeRegistryId, _
        defaultActionTarget, defaultActionRegistryId, _
        cancelActionTarget, cancelActionRegistryId _
    )

    /'
        The first eligible mnemonic source is captured before callbacks and
        dispatched after ordinary updates. This preserves activation polling
        while preventing a replacement form from inheriting the same Alt key.
    '/
    If mnemonicSource <> 0 AndAlso _
       gui_IsSameRegisteredWidget( _
           mnemonicSource, mnemonicSourceRegistryId _
       ) <> 0 AndAlso _
       mnemonicSource->mnemonic_key = mnemonicKey AndAlso _
       mnemonicSource->evis <> 0 AndAlso mnemonicSource->een <> 0 AndAlso _
       gui_IsWithinTree(mnemonicSource, widget_modal_root) <> 0 AndAlso _
       input_AltShortcutPressed(mnemonicKey) <> 0 Then
        If mnemonicTarget <> 0 Then
            If gui_IsSameRegisteredWidget( _
                   mnemonicTarget, mnemonicTargetRegistryId _
               ) <> 0 AndAlso _
               mnemonicSource->mnemonic_target = mnemonicTarget AndAlso _
               gui_CanFocus(mnemonicTarget) <> 0 AndAlso _
               gui_FindOwningWindow(mnemonicSource) = _
                   gui_FindOwningWindow(mnemonicTarget) Then
                gui_KeyboardFocusVisible = -1
                gui_SetFocus mnemonicTarget
            End If
        ElseIf gui_GetMnemonicTarget(mnemonicSource) = 0 AndAlso _
               mnemonicSource->activate <> 0 AndAlso _
               gui_CanFocus(mnemonicSource) <> 0 Then
            gui_KeyboardFocusVisible = -1
            gui_SetFocus mnemonicSource
            mnemonicSource->activate(mnemonicSource)
        End If
    End If

    If widget_focus <> 0 AndAlso gui_CanFocus(widget_focus) = 0 Then _
        gui_SetFocus 0
    gui_PreviousMouseButtons = mouseButtons

    If widget_pending_front <> 0 Then
        Dim As Widget Ptr pendingFront = widget_pending_front
        widget_pending_front = 0
        gui_BringToFront pendingFront
    End If
End Sub

Private Function gui_FindOpaqueCover(ByVal x As Integer, ByVal y As Integer, _
    ByVal widthValue As Integer, ByVal heightValue As Integer) As Widget Ptr
#Ifdef OMAGUI_DISABLE_OPAQUE_CULLING
    ' Keep a reference path for complete-framebuffer comparisons.
    Return 0
#Else
    Dim As Widget Ptr result
    Dim As Widget Ptr current = widget_list_head
    If widthValue <= 0 OrElse heightValue <= 0 Then Return 0
    While current <> 0
        If current->evis <> 0 AndAlso current->is_window <> 0 AndAlso _
           current->parent = 0 AndAlso current->render <> 0 AndAlso _
           current->render_opaque_bounds <> 0 AndAlso current->render_opaque_owner = current->render Then
            Dim As Integer opaqueX, opaqueY, opaqueWidth, opaqueHeight
            If current->render_opaque_bounds(current, opaqueX, opaqueY, opaqueWidth, opaqueHeight) <> 0 AndAlso _
               opaqueWidth > 0 AndAlso opaqueHeight > 0 Then
                If opaqueX <= x AndAlso opaqueY <= y AndAlso _
                   CLngInt(opaqueX) + opaqueWidth >= CLngInt(x) + widthValue AndAlso _
                   CLngInt(opaqueY) + opaqueHeight >= CLngInt(y) + heightValue Then
                    Dim As Integer clipX, clipY, clipWidth, clipHeight
                    If gui_GetWidgetRenderClip(current, clipX, clipY, clipWidth, clipHeight) <> 0 AndAlso _
                       clipX <= x AndAlso clipY <= y AndAlso _
                       CLngInt(clipX) + clipWidth >= CLngInt(x) + widthValue AndAlso _
                       CLngInt(clipY) + clipHeight >= CLngInt(y) + heightValue Then result = current
                End If
            End If
        End If
        current = current->next_widget
    Wend
    Return result
#EndIf
End Function

Private Sub gui_RenderLayer(ByVal renderWindows As Integer)
    Dim As GUI_Theme savedTheme
    Dim As GUI_Theme widgetTheme
    Dim As LongInt bottomEdge
    Dim As LongInt leftEdge
    Dim As LongInt rightEdge
    Dim As Integer screenHeight
    Dim As Integer screenWidth
    Dim As LongInt topEdge
    Dim As Integer clipHeight
    Dim As Integer clipWidth
    Dim As Integer clipX
    Dim As Integer clipY

    Dim As Integer damageX, damageY, damageWidth, damageHeight
    backend_GetClip damageX, damageY, damageWidth, damageHeight
    Dim As Widget Ptr curr = widget_list_head

    gui_ResolveLayout()
    backend_GetSize screenWidth, screenHeight

    /'
        Windows paint after the desktop. A later opaque root which fills the
        complete damage clip makes all earlier pixels irrelevant. Only skip
        whole clips; partial coverage keeps the existing scene replay, and
        callbacks after the covering root still run in their normal order.
        Bounds callbacks are read-only and cannot change registry membership.
    '/
    Dim As Widget Ptr opaqueCover = gui_FindOpaqueCover(damageX, damageY, damageWidth, damageHeight)
    If opaqueCover <> 0 Then
        If renderWindows = 0 Then Exit Sub
        curr = opaqueCover
    End If

    While curr <> 0
        If curr->evis AndAlso _
           (gui_FindOwningWindow(curr) <> 0) = (renderWindows <> 0) Then
            /'
                A modal root limits input, but the normal desktop remains
                visible behind its dialog. Normalizing the rectangle also
                preserves imported line widgets whose width or height is
                intentionally negative.
            '/
            leftEdge = curr->ax
            topEdge = curr->ay
            rightEdge = CLngInt(curr->ax) + curr->w
            bottomEdge = CLngInt(curr->ay) + curr->h
            Dim As Integer paintX, paintY, paintWidth, paintHeight
            If gui_GetRetainedPaintBounds(curr, paintX, paintY, paintWidth, paintHeight) <> 0 Then
                ' An owned popup can extend past its root widget. Replay the
                ' root when damage intersects any part of that painted surface.
                leftEdge = paintX: topEdge = paintY
                rightEdge = CLngInt(paintX) + paintWidth
                bottomEdge = CLngInt(paintY) + paintHeight
            End If

            If rightEdge < leftEdge Then Swap rightEdge, leftEdge
            If bottomEdge < topEdge Then Swap bottomEdge, topEdge
            If rightEdge = leftEdge Then rightEdge += 1
            If bottomEdge = topEdge Then bottomEdge += 1

            If leftEdge < screenWidth AndAlso topEdge < screenHeight AndAlso _
               rightEdge > 0 AndAlso bottomEdge > 0 AndAlso _
               leftEdge < damageX + damageWidth AndAlso _
               topEdge < damageY + damageHeight AndAlso _
               rightEdge > damageX AndAlso bottomEdge > damageY Then
                If gui_GetWidgetRenderClip( _
                    curr, clipX, clipY, clipWidth, clipHeight _
                ) Then
                    backend_SetClip clipX, clipY, clipWidth, clipHeight
                    savedTheme = current_theme
                    If gui_GetEffectiveWidgetTheme(curr, widgetTheme) Then _
                        current_theme = widgetTheme
                    If curr->render <> 0 Then curr->render(curr)
                    If gui_KeyboardFocusVisible <> 0 AndAlso _
                       curr = widget_focus AndAlso _
                       gui_CanFocus(curr) <> 0 AndAlso _
                       curr->w >= GUI_FOCUS_RING_MINIMUM_SIZE AndAlso _
                       curr->h >= GUI_FOCUS_RING_MINIMUM_SIZE Then
                        backend_Rect _
                            curr->ax + GUI_FOCUS_RING_INSET, _
                            curr->ay + GUI_FOCUS_RING_INSET, _
                            curr->w - GUI_FOCUS_RING_INSET * 2, _
                            curr->h - GUI_FOCUS_RING_INSET * 2, _
                            theme_GetColor(GUI_COLOR_SELECT_BG), 0
                    End If
                    current_theme = savedTheme
                    backend_ResetClip
                End If
            End If
        End If
        curr = curr->next_widget
    Wend
End Sub


Sub gui_RefreshLayout()
    gui_ResolveLayout()
End Sub

Function gui_GetPointerWidgetNameAt(ByVal x As Integer, ByVal y As Integer) As String
    gui_ResolveLayout()
    Dim As Widget Ptr target = gui_FindTopmostPointerWidget(x, y)
    If target = 0 Then Return ""
    Return target->name
End Function

Function gui_GetPointerCaptureName() As String
    If gui_IsRegisteredWidget(widget_pointer_capture) = 0 Then Return ""
    Return widget_pointer_capture->name
End Function


Sub gui_RenderDesktop()
    gui_RenderLayer 0
End Sub


Sub gui_RenderWindows()
    gui_RenderLayer -1
End Sub


Sub gui_RenderAll()
    gui_RenderDesktop
    gui_RenderWindows
End Sub


' -------------------------------------------------------------------------
' High-level primitives
' -------------------------------------------------------------------------

Sub gui_DrawLine( _
    ByVal x1 As Integer, ByVal y1 As Integer, _
    ByVal x2 As Integer, ByVal y2 As Integer, _
    ByVal clr As ULong _
)
    backend_Line x1, y1, x2, y2, clr
End Sub


Sub gui_DrawRect( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, _
    ByVal clr As ULong, ByVal filled As Integer _
)
    backend_Rect x, y, w, h, clr, filled
End Sub


Sub gui_DrawCircle( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal radius As Integer, ByVal clr As ULong, _
    ByVal filled As Integer _
)
    backend_Circle x, y, radius, clr, filled
End Sub


Sub gui_DrawCurve( _
    ByVal x1 As Integer, ByVal y1 As Integer, _
    ByVal x2 As Integer, ByVal y2 As Integer, _
    ByVal x3 As Integer, ByVal y3 As Integer, _
    ByVal clr As ULong _
)
    backend_Curve x1, y1, x2, y2, x3, y3, clr
End Sub


' Retained scene management uses this registry and the same layout resolver.
' FBLINT-ALLOW-BAS-INCLUDES
#include once "src/widgets/retained_render.bas"

' end of widgets.bas
