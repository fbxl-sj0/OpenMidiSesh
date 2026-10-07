/'
    Project: omaGUI
    File: menu_retained.bas
    Purpose: Describe the pixels painted by portable popup menus.
    Responsibilities: Observe exact node contents and bound the open popup
        branch so closing, moving and changing submenus repaint old pixels.
    This file does not dispatch input, draw menus or own menu lifetime.

    These callbacks run read-only on the GUI thread. Menu nodes belong to
    their registered parent tree. The root painter clips each node to its
    own surface, then restores the enclosing clip before drawing children.
'/

Function menu_GetRenderObservation(ByVal w As Widget Ptr) As String
    If w = 0 OrElse w->data = 0 Then Return ""
    Dim As MenuData Ptr d = w->data
    If d->count < 0 OrElse d->count > MENU_MAX_ITEMS Then Return ""
    Dim As String result
    result &= MKLongInt(d->count) & MKLongInt(d->selected) & MKLongInt(d->details_style)
    result &= MKLongInt(d->item_height) & MKLongInt(d->vertical_inset) & _
        MKLongInt(d->caption_inset) & MKLongInt(d->shortcut_inset) & _
        MKLongInt(d->separator_inset) & MKLongInt(d->text_y_offset)
    result &= MKLongInt(d->scroll_top) & MKLongInt(d->visible_rows) & MKLongInt(d->open_submenu)
    result &= MKLongInt(CLngInt(CUInt(d->parent_menu)))
    If d->open_submenu >= 0 AndAlso d->open_submenu < d->count Then _
        result &= MKLongInt(CLngInt(CUInt(d->submenus(d->open_submenu))))
    For itemIndex As Integer = 0 To d->count - 1
        ' Exact bytes also observe direct legacy writes to the public arrays.
        result &= MKLongInt(Len(d->items(itemIndex))) & d->items(itemIndex)
        result &= MKLongInt(Len(d->shortcuts(itemIndex))) & d->shortcuts(itemIndex)
        result &= MKLongInt(d->item_kinds(itemIndex)) & MKLongInt(d->item_enabled(itemIndex)) & _
            MKLongInt(d->item_visible(itemIndex)) & MKLongInt(d->item_checked(itemIndex)) & _
            MKLongInt(d->item_submenu(itemIndex))
    Next itemIndex
    Return result
End Function

Function menu_GetRenderBounds(ByVal w As Widget Ptr, ByRef x As Integer, _
    ByRef y As Integer, ByRef widthValue As Integer, ByRef heightValue As Integer) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Dim As Integer screenWidth, screenHeight
    backend_GetSize screenWidth, screenHeight
    If screenWidth <= 0 OrElse screenHeight <= 0 Then Return 0
    Dim As LongInt leftEdge = screenWidth
    Dim As LongInt topEdge = screenHeight
    Dim As LongInt rightEdge, bottomEdge
    Dim As Widget Ptr node = w
    Dim As Integer depth
    While node <> 0
        If depth >= MENU_MAX_NESTING OrElse node->data = 0 OrElse _
           node->render <> @menu_Render OrElse node->destroy <> @menu_Destroy OrElse _
           node->w < 2 OrElse node->h < 2 Then Return 0
        Dim As MenuData Ptr d = node->data
        If d->count < 0 OrElse d->count > MENU_MAX_ITEMS OrElse d->sizing_depth <> 0 Then Return 0
        ' Use wide additions before clipping. Returned coordinates fit the
        ' drawable even on 32-bit targets and malformed off-screen positions.
        Dim As LongInt nodeLeft = node->ax
        Dim As LongInt nodeTop = node->ay
        Dim As LongInt nodeRight = CLngInt(node->ax) + node->w
        Dim As LongInt nodeBottom = CLngInt(node->ay) + node->h
        If nodeLeft < 0 Then nodeLeft = 0
        If nodeTop < 0 Then nodeTop = 0
        If nodeRight > screenWidth Then nodeRight = screenWidth
        If nodeBottom > screenHeight Then nodeBottom = screenHeight
        If nodeRight > nodeLeft AndAlso nodeBottom > nodeTop Then
            If nodeLeft < leftEdge Then leftEdge = nodeLeft
            If nodeTop < topEdge Then topEdge = nodeTop
            If nodeRight > rightEdge Then rightEdge = nodeRight
            If nodeBottom > bottomEdge Then bottomEdge = nodeBottom
        End If
        ' Descendants are registered and have their own exact observations.
        ' Without that invariant the root must keep conservative full repainting.
        If d->open_submenu < 0 OrElse d->open_submenu >= d->count Then Exit While
        Dim As Widget Ptr child = d->submenus(d->open_submenu)
        If child = 0 OrElse child->visible = 0 Then Exit While
        If gui_IsWidgetRegistered(child) = 0 OrElse child->data = 0 OrElse _
           child->parent <> node OrElse Cast(MenuData Ptr, child->data)->parent_menu <> node Then Return 0
        node = child
        depth += 1
    Wend
    If rightEdge <= leftEdge OrElse bottomEdge <= topEdge Then Return 0
    x = CInt(leftEdge): y = CInt(topEdge)
    widthValue = CInt(rightEdge - leftEdge): heightValue = CInt(bottomEdge - topEdge)
    Return -1
End Function

' end of menu_retained.bas
