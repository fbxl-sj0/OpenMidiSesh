/'
    Project: omaGUI
    File: responsive_windows.bas
    Purpose: Keep existing dialog controls reachable in a narrow or short window.
    Responsibilities: Reversible horizontal fitting and focused-field scrolling.
    This file does not change fonts, application forms or native display modes.

    The GUI thread owns the saved geometry in each registered widget. Widths
    and horizontal offsets scale from that stable design geometry, so repeated
    rotations do not accumulate rounding. Vertical geometry retains readable
    fonts and touch heights. A short dialog exposes a right-hand scroll track;
    changing keyboard focus also scrolls the focused control into view. For
    forms without a window, a temporary viewport pan serves the same purpose.
    An overlay keyboard can cover the viewport without changing its size.
    When its bounds are unknown, the focused editor is moved near the top until
    the keyboard closes. A viewport already reduced by the compositor is used
    as reported, without reserving additional space for the keyboard.
'/
#lang "fb"
Private Dim Shared gui_ResponsiveWindows As Integer
Private Dim Shared As Integer gui_KeyboardViewportBefore, gui_KeyboardWasActive
Private Dim Shared As Integer gui_KeyboardViewportBeforeWidth, gui_KeyboardViewportCandidateWidth
Private Dim Shared gui_KeyboardViewportReserved As Integer
Private Dim Shared gui_KeyboardViewportCandidate As Integer
Private Dim Shared gui_KeyboardViewportCandidateAt As Double
Private Const GUI_KEYBOARD_TOP_MARGIN As Integer = 8
Private Const GUI_FOCUS_BOTTOM_GAP As Integer = 4
' Ignore the initial window-manager resize while waiting for a baseline.
Private Const GUI_KEYBOARD_VIEWPORT_SETTLE_SECONDS As Double = 0.25
' A smaller change may be shell chrome rather than space for the keyboard.
Private Const GUI_KEYBOARD_RESERVATION_DIVISOR As Integer = 4

Sub gui_SetResponsiveWindows(ByVal enabled As Integer)
    gui_ResponsiveWindows = IIf(enabled <> 0, -1, 0)
    gui_KeyboardViewportBefore = 0
    gui_KeyboardViewportBeforeWidth = 0
    gui_KeyboardWasActive = 0
    gui_KeyboardViewportReserved = 0
    gui_KeyboardViewportCandidate = 0
    gui_KeyboardViewportCandidateWidth = 0
    gui_KeyboardViewportCandidateAt = 0
End Sub

Sub gui_ResponsiveWindowsLayout()
    If gui_ResponsiveWindows = 0 OrElse gui_ViewportWidth < 2 OrElse gui_ViewportHeight < 2 Then Exit Sub
    Dim root As Widget Ptr = widget_list_head
    While root <> 0
        If root->is_window <> 0 AndAlso root->parent = 0 Then
            If root->responsive_saved = 0 AndAlso (root->w > gui_ViewportWidth OrElse root->h > gui_ViewportHeight) Then
                root->responsive_saved = -1
                root->responsive_w = root->w: root->responsive_h = root->h
            End If
            If root->responsive_saved <> 0 AndAlso root->responsive_w > 0 Then
                root->w = IIf(root->responsive_w < gui_ViewportWidth, root->responsive_w, gui_ViewportWidth)
                root->h = IIf(root->responsive_h < gui_ViewportHeight, root->responsive_h, gui_ViewportHeight)
                root->x = (gui_ViewportWidth - root->w) \ 2
                root->y = (gui_ViewportHeight - root->h) \ 2
                root->content_height = root->responsive_h
                Dim scroll_room As Integer = root->content_height - root->h
                If root->content_scroll_y > scroll_room Then root->content_scroll_y = scroll_room
                If root->content_scroll_y < 0 Then root->content_scroll_y = 0
                ' Reserve a 16-pixel track only when vertical scrolling is needed.
                root->child_clip_right = IIf(scroll_room > 0, 18, 2)
                Dim content_width As Integer = root->w - IIf(scroll_room > 0, 16, 0)
                Dim child As Widget Ptr = widget_list_head
                While child <> 0
                    Dim owner As Widget Ptr = child->parent
                    Dim guard As Integer
                    While owner <> 0 AndAlso owner <> root AndAlso guard < GUI_LAYOUT_PARENT_GUARD
                        owner = owner->parent: guard += 1
                    Wend
                    If owner = root Then
                        If child->responsive_saved = 0 Then
                            child->responsive_saved = -1
                            child->responsive_x = child->x: child->responsive_w = child->w
                        End If
                        child->x = (CLngInt(child->responsive_x) * content_width) \ root->responsive_w
                        child->w = (CLngInt(child->responsive_w) * content_width) \ root->responsive_w
                        If child->w < 1 Then child->w = 1
                    End If
                    child = child->next_widget
                Wend
            End If
        End If
        root = root->next_widget
    Wend
End Sub

Private Function gui_ResponsivePanForFocus( _
    ByVal top_value As LongInt, ByVal height As Integer, ByVal viewport_height As Integer _
) As Integer
    If top_value <= 0 OrElse height <= 0 OrElse viewport_height <= 0 Then Return 0

    ' Leave a small gap below the field when there is room for it.
    Dim pan_amount As LongInt = top_value + height + GUI_FOCUS_BOTTOM_GAP - viewport_height
    If pan_amount <= 0 Then Return 0
    If pan_amount > top_value Then pan_amount = top_value
    If pan_amount > 2147483647LL Then pan_amount = 2147483647LL
    Return CInt(pan_amount)
End Function

Private Function gui_ResponsiveFocusVisibleForKeyboard( _
    ByVal keyboard_active As Integer, ByVal may_overlap As Integer, _
    ByVal keyboard_pending As Integer = 0, ByVal observed_top As Integer = -1 _
) As Integer
    Dim previous_pan As Integer = gui_ResponsivePanY
    Dim root As Widget Ptr = widget_focus
    Dim guard As Integer
    While root <> 0 AndAlso root->parent <> 0 AndAlso guard < GUI_LAYOUT_PARENT_GUARD
        root = root->parent: guard += 1
    Wend

    If keyboard_active = 0 Then
        Dim current_time As Double = Timer
        If gui_KeyboardViewportCandidate <> gui_ViewportHeight OrElse _
           gui_KeyboardViewportCandidateWidth <> gui_ViewportWidth OrElse _
           current_time < gui_KeyboardViewportCandidateAt Then
            gui_KeyboardViewportCandidate = gui_ViewportHeight
            gui_KeyboardViewportCandidateWidth = gui_ViewportWidth
            gui_KeyboardViewportCandidateAt = current_time
            ' Configure and IME visibility callbacks can arrive in either order.
            ' Retain the last settled geometry until this candidate settles too.
        ElseIf keyboard_pending = 0 AndAlso _
               current_time - gui_KeyboardViewportCandidateAt >= GUI_KEYBOARD_VIEWPORT_SETTLE_SECONDS Then
            ' A compositor can reserve space before acknowledging the show
            ' request. Do not settle that reduced size as the full baseline.
            gui_KeyboardViewportBefore = gui_ViewportHeight
            gui_KeyboardViewportBeforeWidth = gui_ViewportWidth
            gui_KeyboardViewportReserved = 0
        End If
        gui_KeyboardWasActive = 0
    ElseIf gui_KeyboardWasActive = 0 Then
        If gui_KeyboardViewportBefore <= 0 Then
            gui_KeyboardViewportBefore = gui_ViewportHeight
            gui_KeyboardViewportBeforeWidth = gui_ViewportWidth
        End If
        gui_KeyboardWasActive = -1
    End If

    gui_ResponsivePanY = 0
    If gui_ResponsiveWindows <> 0 AndAlso root <> 0 AndAlso root->parent = 0 AndAlso _
       widget_focus->text_input <> 0 AndAlso keyboard_active <> 0 Then
        Dim visible_height As Integer = gui_ViewportHeight
        Dim overlay_fallback As Integer = 0
        Dim reserved_height As LongInt = CLngInt(gui_KeyboardViewportBefore) - gui_ViewportHeight
        Dim minimum_reservation As LongInt = _
            CLngInt(gui_KeyboardViewportBefore) \ GUI_KEYBOARD_RESERVATION_DIVISOR
        If minimum_reservation < widget_focus->h Then minimum_reservation = widget_focus->h
        If gui_KeyboardViewportBeforeWidth = gui_ViewportWidth Then
            gui_KeyboardViewportReserved = CLng(reserved_height >= minimum_reservation)
        End If
        If observed_top = visible_height Then gui_KeyboardViewportReserved = -1
        If observed_top >= 0 AndAlso observed_top < visible_height Then
            visible_height = observed_top
            overlay_fallback = -1
        ElseIf may_overlap <> 0 AndAlso observed_top < 0 AndAlso gui_KeyboardViewportReserved = 0 AndAlso _
           (gui_KeyboardViewportBeforeWidth <> gui_ViewportWidth OrElse _
            reserved_height < minimum_reservation) Then
            ' Without keyboard bounds, put the editor at the top rather than
            ' guessing a keyboard height. A substantial height-only shrink
            ' suggests the compositor reserved space. A small shrink or a
            ' simultaneous width change can instead be shell chrome or rotation.
            Dim safe_height As LongInt = CLngInt(widget_focus->h) + _
                GUI_KEYBOARD_TOP_MARGIN + GUI_FOCUS_BOTTOM_GAP
            If safe_height > 0 AndAlso safe_height < visible_height Then visible_height = CInt(safe_height)
            overlay_fallback = -1
        End If
        ' Keep an observed compositor reservation through rotation or scaling
        ' while the keyboard stays open. Its reduced viewport remains usable;
        ' a width change alone does not turn that keyboard into an overlay.
        ' Measured keyboard bounds above still take precedence.
        ' Absolute coordinates include the previous pan until layout resolves.
        If root->is_window = 0 OrElse overlay_fallback <> 0 Then
            gui_ResponsivePanY = gui_ResponsivePanForFocus( _
                CLngInt(widget_focus->ay) + previous_pan, widget_focus->h, visible_height)
        End If
    End If

    Dim changed As Integer = CLng(previous_pan <> gui_ResponsivePanY)
    If changed <> 0 Then gui_InvalidateAll
    If gui_ResponsiveWindows = 0 OrElse root = 0 OrElse root = widget_focus OrElse _
       root->parent <> 0 OrElse root->is_window = 0 OrElse root->content_height <= root->h Then Return changed

    Dim previous As Integer = root->content_scroll_y
    Dim top_value As Integer = widget_focus->ay - root->ay
    Dim bottom_value As Integer = top_value + widget_focus->h
    If top_value < root->child_clip_y + 8 Then root->content_scroll_y += top_value - root->child_clip_y - 8
    If bottom_value > root->h - 8 Then root->content_scroll_y += bottom_value - root->h + 8
    If root->content_scroll_y < 0 Then root->content_scroll_y = 0
    If root->content_scroll_y > root->content_height - root->h Then root->content_scroll_y = root->content_height - root->h
    Return CLng(changed <> 0 OrElse previous <> root->content_scroll_y)
End Function

Function gui_ResponsiveFocusVisible() As Integer
    Dim As Integer keyboard_active = 0, may_overlap = 0, keyboard_pending = 0
    Dim observed_top As Integer = -1
    If gui_ResponsiveWindows <> 0 AndAlso widget_focus <> 0 AndAlso _
       widget_focus->text_input <> 0 Then
        keyboard_active = backend_SoftKeyboardActive()
        keyboard_pending = backend_SoftKeyboardPending()
        If keyboard_active <> 0 Then
            may_overlap = backend_SoftKeyboardMayOverlap()
            observed_top = backend_SoftKeyboardOcclusionTop()
        End If
    End If
    Return gui_ResponsiveFocusVisibleForKeyboard(keyboard_active, may_overlap, keyboard_pending, observed_top)
End Function
' end of responsive_windows.bas
