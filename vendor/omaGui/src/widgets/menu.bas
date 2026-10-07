/'
    Project: omaGUI
    ---------------

    File: menu.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements menu.bi; declarations there define the interface.

    Purpose:

        Implement portable popup menus and owned submenu trees.

    Responsibilities:

        - create, populate, size, draw, and destroy popup menus
        - draw menu separators and hover selection
        - publish one selection on a matching pointer release
        - route selections through item or context-aware callbacks
        - retain parent menus while their child branches are open
        - place, scroll, and navigate complete trees inside the viewport
        - restore focus when a tree is dismissed

    This file intentionally does NOT contain:

        - application command policy
        - imported-control ownership rules
        - global pointer-routing policy
'/

#lang "fb"

#include once "src/widgets/menu.bi"
#include once "src/widgets/widgets.bi"

Const MENU_DEFAULT_WIDTH As Integer = 100
Const MENU_ITEM_HEIGHT As Integer = 20
Const MENU_MINIMUM_ITEM_HEIGHT As Integer = 16
Const MENU_MAXIMUM_ITEM_HEIGHT As Integer = 96
Const MENU_SELECTION_INSET As Integer = 2
Const MENU_TEXT_INSET As Integer = 5
Const MENU_SEPARATOR_INSET As Integer = 6
Const MENU_TEXT_HEIGHT As Integer = 8
' Leave a readable gap between the caption and accelerator columns.
Const MENU_SHORTCUT_GAP As Integer = 36
Const MENU_MAXIMUM_INSET As Integer = 128
Const MENU_POINTER_OUTSIDE As Integer = -2
' Bound accidental recursive update scopes before their depth can overflow.
Const MENU_MAX_UPDATE_DEPTH As Integer = 32

' -------------------------------------------------------------------------
' Internal sizing and input helpers
' -------------------------------------------------------------------------

Private Sub menu_UpdateHeight(ByVal m As Widget Ptr)
    Dim As MenuData Ptr d

    If m = 0 OrElse m->data = 0 Then Exit Sub
    d = Cast(MenuData Ptr, m->data)
    If d->sizing_depth > 0 Then
        d->sizing_height_pending = -1
        Exit Sub
    End If
    If d->count < 0 OrElse d->count > MENU_MAX_ITEMS Then Exit Sub
    Dim As Integer rowCount
    For itemIndex As Integer = 0 To d->count - 1
        If d->item_visible(itemIndex) <> 0 Then rowCount += 1
    Next itemIndex
    If d->visible_rows > 0 AndAlso rowCount > d->visible_rows Then rowCount = d->visible_rows
    m->h = rowCount * d->item_height + d->vertical_inset * 2
End Sub


Private Function menu_VisibleItemCount(ByVal d As MenuData Ptr) As Integer
    If d = 0 Then Return 0
    Dim As Integer visibleCount
    For itemIndex As Integer = 0 To d->count - 1
        If d->item_visible(itemIndex) <> 0 Then visibleCount += 1
    Next itemIndex
    Return visibleCount
End Function


Private Function menu_IndexAtVisibleRow( _
    ByVal d As MenuData Ptr, ByVal visibleRow As Integer _
) As Integer
    If d = 0 OrElse visibleRow < 0 Then Return -1
    Dim As Integer currentRow
    For itemIndex As Integer = 0 To d->count - 1
        If d->item_visible(itemIndex) = 0 Then Continue For
        If currentRow = visibleRow Then Return itemIndex
        currentRow += 1
    Next itemIndex
    Return -1
End Function


Private Function menu_VisibleRowOfIndex( _
    ByVal d As MenuData Ptr, ByVal itemIndex As Integer _
) As Integer
    If d = 0 OrElse itemIndex < 0 OrElse itemIndex >= d->count OrElse _
       d->item_visible(itemIndex) = 0 Then Return -1
    Dim As Integer visibleRow
    For currentIndex As Integer = 0 To itemIndex - 1
        If d->item_visible(currentIndex) <> 0 Then visibleRow += 1
    Next currentIndex
    Return visibleRow
End Function


Private Function menu_DisplayText( _
    ByRef sourceText As Const String, ByRef scanCode As Integer, _
    ByRef displayIndex As Integer _
) As String
    Dim As String displayText
    gui_ParseMnemonicCaption sourceText, displayText, scanCode, displayIndex
    Return displayText
End Function


Private Sub menu_RenderMnemonicUnderline( _
    ByRef displayText As Const String, ByVal displayIndex As Integer, _
    ByVal textLeft As Integer, ByVal textTop As Integer, _
    ByVal textHeight As Integer _
)
    If displayIndex < 0 OrElse displayIndex >= Len(displayText) OrElse _
       textHeight < 3 Then Exit Sub

    Dim As Integer underlineLeft = textLeft + _
        backend_GetTextWidth(Left(displayText, displayIndex))
    Dim As Integer glyphWidth = backend_GetTextWidth( _
        Mid(displayText, displayIndex + 1, 1) _
    )
    If glyphWidth < 1 Then Exit Sub
    backend_Line _
        underlineLeft, textTop + textHeight - 3, _
        underlineLeft + glyphWidth - 1, textTop + textHeight - 3, _
        theme_GetClassicColor(GUI_CLASSIC_COLOR_ACCESS_TEXT)
End Sub


Private Sub menu_UpdateWidth(ByVal m As Widget Ptr)
    Dim As MenuData Ptr d = m->data
    If d->sizing_depth > 0 Then
        d->sizing_width_pending = -1
        Exit Sub
    End If
    If d->count < 0 OrElse d->count > MENU_MAX_ITEMS Then Exit Sub
    Dim As Integer captionWidth, shortcutWidth
    Dim As Integer mnemonicScanCode, mnemonicDisplayIndex
    Dim As String displayText
    For itemIndex As Integer = 0 To d->count - 1
        If d->item_kinds(itemIndex) = MENU_ITEM_KIND_SEPARATOR Then Continue For
        displayText = menu_DisplayText( _
            d->items(itemIndex), mnemonicScanCode, mnemonicDisplayIndex _
        )
        Dim As Integer measuredWidth = backend_GetTextWidth(displayText)
        If measuredWidth > captionWidth Then captionWidth = measuredWidth
        measuredWidth = backend_GetTextWidth(d->shortcuts(itemIndex))
        If measuredWidth > shortcutWidth Then shortcutWidth = measuredWidth
    Next itemIndex
    Dim As Integer itemWidth = captionWidth + 20
    If d->details_style <> 0 Then itemWidth = captionWidth + shortcutWidth + _
        d->caption_inset + d->shortcut_inset + MENU_SHORTCUT_GAP
    If itemWidth > m->w Then m->w = itemWidth
End Sub


Private Function menu_HitTest( _
    ByVal w As Widget Ptr, _
    ByVal d As MenuData Ptr, _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer _
) As Integer

    Dim As Integer localY
    Dim As Integer itemIndex

    If mouseX < w->ax OrElse mouseX >= w->ax + w->w OrElse _
       mouseY < w->ay OrElse mouseY >= w->ay + w->h Then _
        Return MENU_POINTER_OUTSIDE

    localY = mouseY - w->ay - d->vertical_inset
    If localY < 0 Then Return -1
    If localY >= w->h - d->vertical_inset * 2 Then Return -1

    itemIndex = menu_IndexAtVisibleRow( _
        d, localY \ d->item_height + d->scroll_top _
    )
    If itemIndex < 0 Then Return -1
    If d->item_kinds(itemIndex) = MENU_ITEM_KIND_SEPARATOR OrElse _
       d->item_enabled(itemIndex) = 0 Then Return -1

    Return itemIndex
End Function

Const MENU_SUBMENU_OVERLAP As Integer = 2
Const MENU_HOVER_DELAY_SECONDS As Double = 0.18

Private Function menu_FirstEnabled(ByVal m As Widget Ptr) As Integer
    Dim As MenuData Ptr d = m->data
    For itemIndex As Integer = 0 To d->count - 1
        If d->item_kinds(itemIndex) = MENU_ITEM_KIND_NORMAL AndAlso _
           d->item_enabled(itemIndex) <> 0 AndAlso _
           d->item_visible(itemIndex) <> 0 Then Return itemIndex
    Next itemIndex
    Return -1
End Function

Private Sub menu_AbsolutePosition(ByVal m As Widget Ptr, ByRef x As Integer, ByRef y As Integer)
    x = 0
    y = 0
    Dim As Widget Ptr current = m
    Dim As Integer parentDepth
    While current <> 0 AndAlso parentDepth < GUI_LAYOUT_PARENT_GUARD
        x += current->x
        y += current->y
        current = current->parent
        parentDepth += 1
    Wend
End Sub

Private Function menu_PointerTest(ByVal w As Widget Ptr, ByVal x As Integer, ByVal y As Integer) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Dim As MenuData Ptr d = w->data
    If gui_IsWidgetRegistered(d->menubar_owner) <> 0 Then
        Dim As Widget Ptr owner = d->menubar_owner
        If x >= owner->ax AndAlso x < owner->ax + owner->w AndAlso _
           y >= owner->ay AndAlso y < owner->ay + owner->h Then Return 0
    End If
    Return -1
End Function

Function menu_GetRoot(ByVal m As Widget Ptr) As Widget Ptr
    Dim As Integer depth
    While m <> 0 AndAlso depth < MENU_MAX_NESTING
        If m->render <> @menu_Render OrElse m->data = 0 Then Return 0
        Dim As MenuData Ptr d = m->data
        If d->parent_menu = 0 Then Return m
        m = d->parent_menu
        depth += 1
    Wend
    Return 0
End Function

Function menu_GetOpenLeaf(ByVal m As Widget Ptr) As Widget Ptr
    m = menu_GetRoot(m)
    Dim As Integer depth
    While m <> 0 AndAlso depth < MENU_MAX_NESTING
        Dim As MenuData Ptr d = m->data
        If d->open_submenu < 0 OrElse d->open_submenu >= d->count Then Return m
        Dim As Widget Ptr child = d->submenus(d->open_submenu)
        If child = 0 OrElse child->visible = 0 Then Return m
        m = child
        depth += 1
    Wend
    Return m
End Function

Private Sub menu_HideBranch(ByVal m As Widget Ptr, ByVal depth As Integer = 0)
    If m = 0 OrElse m->data = 0 OrElse depth >= MENU_MAX_NESTING Then Exit Sub
    Dim As MenuData Ptr d = m->data
    For itemIndex As Integer = 0 To d->count - 1
        If d->submenus(itemIndex) <> 0 Then menu_HideBranch(d->submenus(itemIndex), depth + 1)
    Next itemIndex
    m->visible = 0
    d->open_submenu = -1
    d->selected = -1
    d->pointer_latch = 0
    d->pointer_menu = 0
    d->hover_menu = 0
    d->hover_index = -1
End Sub

Sub menu_CloseTree(ByVal m As Widget Ptr)
    Dim As Widget Ptr root = menu_GetRoot(m)
    If root = 0 Then Exit Sub
    Dim As MenuData Ptr d = root->data
    Dim As Widget Ptr previousFocus = d->restore_focus
    Dim As Widget Ptr menuBarOwner = d->menubar_owner
    Dim As Any Ptr menuBarHandler = d->menubar_handler
    Dim As Any Ptr menuBarContext = d->menubar_context
    Dim As Integer wasVisible = root->visible
    Dim As Integer restoreFocus = IIf(gui_GetFocus() = root OrElse gui_GetFocus() = 0, -1, 0)
    d->restore_focus = 0
    menu_HideBranch(root)
    If restoreFocus <> 0 Then
        If gui_IsWidgetRegistered(previousFocus) <> 0 Then
            gui_SetFocus(previousFocus)
        ElseIf gui_GetFocus() = root Then
            gui_SetFocus(0)
        End If
    End If
    If wasVisible <> 0 AndAlso menuBarHandler <> 0 AndAlso _
       gui_IsWidgetRegistered(menuBarOwner) <> 0 Then
        Cast(Sub(ByVal As Any Ptr, ByVal As Integer), menuBarHandler)( _
            menuBarContext, 0)
    End If
End Sub

Private Sub menu_ConfigureViewport(ByVal m As Widget Ptr)
    Dim As Integer screenWidth, screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As MenuData Ptr d = m->data
    d->visible_rows = (screenHeight - d->vertical_inset * 2) \ d->item_height
    If d->visible_rows < 1 Then d->visible_rows = 1
    Dim As Integer visibleCount = menu_VisibleItemCount(d)
    If d->visible_rows > visibleCount Then d->visible_rows = visibleCount
    If m->w > screenWidth Then m->w = screenWidth
    If d->scroll_top < 0 Then d->scroll_top = 0
    Dim As Integer maximumScroll = visibleCount - d->visible_rows
    If maximumScroll < 0 Then maximumScroll = 0
    If d->scroll_top > maximumScroll Then d->scroll_top = maximumScroll
    menu_UpdateHeight(m)
End Sub

Sub menu_ShowAt(ByVal m As Widget Ptr, ByVal x As Integer, ByVal y As Integer, ByVal selectFirst As Integer)
    If m = 0 OrElse m->data = 0 Then Exit Sub
    Dim As Widget Ptr root = menu_GetRoot(m)
    If root <> m Then Exit Sub
    Dim As MenuData Ptr d = m->data
    If menu_VisibleItemCount(d) < 1 Then Exit Sub
    If m->visible = 0 AndAlso gui_GetFocus() <> m Then d->restore_focus = gui_GetFocus()
    menu_HideBranch(m)
    menu_ConfigureViewport(m)
    Dim As Integer screenWidth, screenHeight, parentX, parentY
    backend_GetSize screenWidth, screenHeight
    If x + m->w > screenWidth Then x = screenWidth - m->w
    If y + m->h > screenHeight Then y = screenHeight - m->h
    If x < 0 Then x = 0
    If y < 0 Then y = 0
    If m->parent <> 0 Then menu_AbsolutePosition(m->parent, parentX, parentY)
    m->x = x - parentX
    m->y = y - parentY
    m->ax = x
    m->ay = y
    m->visible = -1
    m->pointer_global = -1
    d->cascade_side = 1
    d->last_pointer_x = input_MouseX()
    d->last_pointer_y = input_MouseY()
    If selectFirst <> 0 Then d->selected = menu_FirstEnabled(m)
    gui_SetFocus(m)
    gui_BringToFront(m)
End Sub

Private Function menu_SubtreeDepth(ByVal m As Widget Ptr, ByVal depth As Integer = 1) As Integer
    If depth > MENU_MAX_NESTING Then Return depth
    Dim As Integer maximumDepth = depth
    Dim As MenuData Ptr d = m->data
    For itemIndex As Integer = 0 To d->count - 1
        If d->submenus(itemIndex) <> 0 Then
            Dim As Integer childDepth = menu_SubtreeDepth(d->submenus(itemIndex), depth + 1)
            If childDepth > maximumDepth Then maximumDepth = childDepth
        End If
    Next itemIndex
    Return maximumDepth
End Function

Function menu_SetSubmenu(ByVal m As Widget Ptr, ByVal itemIndex As Integer, ByVal submenuWidget As Widget Ptr) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return 0
    Dim As MenuData Ptr d = m->data
    If itemIndex < 0 OrElse itemIndex >= d->count OrElse _
       d->item_kinds(itemIndex) <> MENU_ITEM_KIND_NORMAL Then Return 0
    If d->submenus(itemIndex) = submenuWidget Then Return -1
    If submenuWidget <> 0 Then
        If submenuWidget = m OrElse submenuWidget->data = 0 OrElse submenuWidget->render <> @menu_Render Then Return 0
        If submenuWidget->parent <> 0 Then Return 0
        Dim As Widget Ptr ancestor = m
        Dim As Integer ancestorDepth
        While ancestor <> 0 AndAlso ancestorDepth < MENU_MAX_NESTING
            If ancestor = submenuWidget Then Return 0
            ancestor = Cast(MenuData Ptr, ancestor->data)->parent_menu
            ancestorDepth += 1
        Wend
        If ancestor <> 0 OrElse ancestorDepth + menu_SubtreeDepth(submenuWidget) > MENU_MAX_NESTING Then Return 0
    End If
    If d->submenus(itemIndex) <> 0 Then
        Dim As Widget Ptr root = menu_GetRoot(m)
        If root <> 0 Then
            menu_CancelInput(root)
            Cast(MenuData Ptr, root->data)->hover_menu = 0
        End If
        Dim As Widget Ptr oldSubmenu = d->submenus(itemIndex)
        d->submenus(itemIndex) = 0
        gui_RemoveWidget(oldSubmenu->name)
    End If
    d->submenus(itemIndex) = submenuWidget
    d->open_submenu = -1
    d->item_submenu(itemIndex) = IIf(submenuWidget <> 0, -1, 0)
    d->details_style = -1
    If submenuWidget <> 0 Then
        Cast(MenuData Ptr, submenuWidget->data)->parent_menu = m
        submenuWidget->is_window = 0
        submenuWidget->pointer_global = 0
        submenuWidget->update = 0
        submenuWidget->visible = 0
        gui_SetParent(submenuWidget, m)
        If gui_IsWidgetRegistered(submenuWidget) = 0 Then gui_AddGeneratedWidget(submenuWidget)
    End If
    Return -1
End Function

Function menu_AddSubmenu(ByVal m As Widget Ptr, ByVal text As String, ByVal submenuWidget As Widget Ptr) As Integer
    If m = 0 OrElse m->data = 0 OrElse submenuWidget = 0 Then Return -1
    Dim As MenuData Ptr d = m->data
    If d->count >= MENU_MAX_ITEMS Then Return -1
    Dim As Integer itemIndex = d->count
    menu_AddItem(m, text, 0)
    If menu_SetSubmenu(m, itemIndex, submenuWidget) = 0 Then
        d->items(itemIndex) = ""
        d->count -= 1
        menu_UpdateHeight(m)
        Return -1
    End If
    menu_SetItemDetails(m, itemIndex, "", -1, 0, -1)
    Return itemIndex
End Function

Sub menu_AddCommand(ByVal m As Widget Ptr, ByVal text As String, ByVal commandId As Integer)
    If m = 0 OrElse m->data = 0 Then Exit Sub
    Dim As MenuData Ptr d = m->data
    If d->count < 0 OrElse d->count >= MENU_MAX_ITEMS Then Exit Sub
    Dim As Integer itemIndex = d->count
    menu_AddItem(m, text, 0)
    d->command_ids(itemIndex) = commandId
End Sub

Sub menu_AddDisplayCommand(ByVal m As Widget Ptr, ByVal text As String, ByVal commandId As Integer)
    If m = 0 OrElse m->data = 0 Then Exit Sub
    Dim As MenuData Ptr d = m->data
    If d->count < 0 OrElse d->count >= MENU_MAX_ITEMS Then Exit Sub
    Dim As Integer itemIndex = d->count
    menu_AddDisplayItem(m, text, 0)
    d->command_ids(itemIndex) = commandId
End Sub

Function menu_OpenSubmenu(ByVal m As Widget Ptr, ByVal itemIndex As Integer, ByVal selectFirst As Integer) As Integer
    If m = 0 OrElse m->data = 0 Then Return 0
    Dim As MenuData Ptr d = m->data
    If itemIndex < 0 OrElse itemIndex >= d->count OrElse _
       d->item_enabled(itemIndex) = 0 OrElse _
       d->item_visible(itemIndex) = 0 Then Return 0
    Dim As Widget Ptr child = d->submenus(itemIndex)
    If child = 0 Then Return 0
    If d->open_submenu = itemIndex AndAlso child->visible <> 0 Then Return -1
    If d->open_submenu >= 0 AndAlso d->open_submenu < d->count Then _
        menu_HideBranch(d->submenus(d->open_submenu))
    menu_HideBranch(child)
    menu_ConfigureViewport(child)
    Dim As Integer screenWidth, screenHeight, parentX, parentY
    backend_GetSize screenWidth, screenHeight
    menu_AbsolutePosition(m, parentX, parentY)
    Dim As Integer cascadeSide = d->cascade_side
    If cascadeSide = 0 Then cascadeSide = 1
    Dim As Integer childX = parentX + m->w - MENU_SUBMENU_OVERLAP
    If cascadeSide < 0 Then childX = parentX - child->w + MENU_SUBMENU_OVERLAP
    Dim As Integer visibleRow = menu_VisibleRowOfIndex(d, itemIndex)
    If visibleRow < d->scroll_top OrElse _
       visibleRow >= d->scroll_top + d->visible_rows Then Return 0
    Dim As Integer childY = parentY + d->vertical_inset + _
        (visibleRow - d->scroll_top) * d->item_height
    If childX + child->w > screenWidth Then
        childX = parentX - child->w + MENU_SUBMENU_OVERLAP
        cascadeSide = -1
    ElseIf childX < 0 Then
        childX = parentX + m->w - MENU_SUBMENU_OVERLAP
        cascadeSide = 1
    End If
    If childX < 0 Then childX = 0
    If childY + child->h > screenHeight Then childY = screenHeight - child->h
    If childY < 0 Then childY = 0
    child->x = childX - parentX
    child->y = childY - parentY
    child->ax = childX
    child->ay = childY
    child->visible = -1
    Cast(MenuData Ptr, child->data)->cascade_side = cascadeSide
    d->open_submenu = itemIndex
    d->selected = itemIndex
    If selectFirst <> 0 Then Cast(MenuData Ptr, child->data)->selected = menu_FirstEnabled(child)
    Return -1
End Function

Sub menu_SetMenuBarHandler(ByVal m As Widget Ptr, ByVal handler As Any Ptr, ByVal context As Any Ptr)
    If m = 0 OrElse m->data = 0 Then Exit Sub
    Dim As MenuData Ptr d = m->data
    d->menubar_handler = handler
    d->menubar_context = context
End Sub

Sub menu_SetMenuBarOwner(ByVal m As Widget Ptr, ByVal owner As Widget Ptr)
    If m = 0 OrElse m->data = 0 Then Exit Sub
    Cast(MenuData Ptr, m->data)->menubar_owner = owner
End Sub


Function menu_GetItemCount(ByVal m As Widget Ptr) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return 0
    Return Cast(MenuData Ptr, m->data)->count
End Function


Function menu_GetVisibleItemCount(ByVal m As Widget Ptr) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return 0
    Return menu_VisibleItemCount(Cast(MenuData Ptr, m->data))
End Function


Function menu_GetItemVisible( _
    ByVal m As Widget Ptr, ByVal itemIndex As Integer _
) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return 0
    Dim As MenuData Ptr d = m->data
    If itemIndex < 0 OrElse itemIndex >= d->count Then Return 0
    Return d->item_visible(itemIndex)
End Function


Function menu_SetItemVisible( _
    ByVal m As Widget Ptr, ByVal itemIndex As Integer, _
    ByVal visibleValue As Integer _
) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return 0
    Dim As MenuData Ptr d = m->data
    If itemIndex < 0 OrElse itemIndex >= d->count Then Return 0

    d->item_visible(itemIndex) = IIf(visibleValue <> 0, -1, 0)
    If d->item_visible(itemIndex) = 0 Then
        If d->open_submenu = itemIndex Then
            menu_HideBranch(d->submenus(itemIndex))
            d->open_submenu = -1
        End If
        If d->selected = itemIndex Then d->selected = menu_FirstEnabled(m)
    End If

    If m->visible <> 0 Then
        menu_ConfigureViewport(m)
    Else
        menu_UpdateHeight(m)
    End If
    Dim As Integer selectedRow = menu_VisibleRowOfIndex(d, d->selected)
    If selectedRow >= 0 Then
        If selectedRow < d->scroll_top Then d->scroll_top = selectedRow
        If selectedRow >= d->scroll_top + d->visible_rows Then _
            d->scroll_top = selectedRow - d->visible_rows + 1
    End If
    Return -1
End Function


Function menu_SetItemLabel( _
    ByVal m As Widget Ptr, ByVal itemIndex As Integer, _
    ByVal itemText As String _
) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return 0
    If Len(itemText) > 160 OrElse InStr(itemText, Chr(0)) > 0 Then Return 0
    Dim As MenuData Ptr d = m->data
    If itemIndex < 0 OrElse itemIndex >= d->count OrElse _
       d->item_kinds(itemIndex) <> MENU_ITEM_KIND_NORMAL Then Return 0
    d->items(itemIndex) = gui_TransformText(itemText)
    menu_UpdateWidth(m)
    Return -1
End Function


Function menu_SetItemEnabled( _
    ByVal m As Widget Ptr, ByVal itemIndex As Integer, _
    ByVal enabledValue As Integer _
) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return 0
    Dim As MenuData Ptr d = m->data
    If itemIndex < 0 OrElse itemIndex >= d->count OrElse _
       d->item_kinds(itemIndex) <> MENU_ITEM_KIND_NORMAL Then Return 0
    d->item_enabled(itemIndex) = IIf(enabledValue <> 0, -1, 0)
    If d->item_enabled(itemIndex) = 0 Then
        If d->open_submenu = itemIndex Then
            menu_HideBranch(d->submenus(itemIndex))
            d->open_submenu = -1
        End If
        If d->selected = itemIndex Then d->selected = menu_FirstEnabled(m)
    End If
    Dim As Integer selectedRow = menu_VisibleRowOfIndex(d, d->selected)
    If selectedRow >= 0 Then
        If selectedRow < d->scroll_top Then d->scroll_top = selectedRow
        If d->visible_rows > 0 AndAlso _
           selectedRow >= d->scroll_top + d->visible_rows Then _
            d->scroll_top = selectedRow - d->visible_rows + 1
    End If
    Return -1
End Function


Function menu_SetItemChecked( _
    ByVal m As Widget Ptr, ByVal itemIndex As Integer, _
    ByVal checkedValue As Integer _
) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return 0
    Dim As MenuData Ptr d = m->data
    If itemIndex < 0 OrElse itemIndex >= d->count OrElse _
       d->item_kinds(itemIndex) <> MENU_ITEM_KIND_NORMAL Then Return 0
    d->details_style = -1
    d->item_checked(itemIndex) = IIf(checkedValue <> 0, -1, 0)
    Return -1
End Function


Function menu_SetItemShortcut( _
    ByVal m As Widget Ptr, ByVal itemIndex As Integer, _
    ByVal scanCode As Integer, ByVal modifiers As Integer, _
    ByVal shortcutText As String _
) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return 0
    Dim As MenuData Ptr d = m->data
    If itemIndex < 0 OrElse itemIndex >= d->count OrElse _
       d->item_kinds(itemIndex) <> MENU_ITEM_KIND_NORMAL Then Return 0
    If scanCode < 0 OrElse scanCode > 255 OrElse _
       modifiers < 0 OrElse modifiers > 7 OrElse _
       (scanCode = 0 AndAlso modifiers <> INPUT_MODIFIER_NONE) OrElse _
       Len(shortcutText) > 160 OrElse InStr(shortcutText, Chr(0)) > 0 Then Return 0
    If scanCode <> 0 AndAlso d->submenus(itemIndex) <> 0 Then Return 0

    d->shortcut_scan_codes(itemIndex) = scanCode
    d->shortcut_modifiers(itemIndex) = modifiers
    d->shortcuts(itemIndex) = shortcutText
    menu_UpdateWidth(m)
    Return -1
End Function

' -------------------------------------------------------------------------
' Construction and item management
' -------------------------------------------------------------------------

Function menu_BeginUpdate(ByVal m As Widget Ptr) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return 0
    Dim As MenuData Ptr d = m->data
    If d->sizing_depth < 0 OrElse d->sizing_depth >= MENU_MAX_UPDATE_DEPTH Then Return 0
    d->sizing_depth += 1
    Return -1
End Function

Function menu_EndUpdate(ByVal m As Widget Ptr) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return 0
    Dim As MenuData Ptr d = m->data
    If d->sizing_depth < 1 OrElse d->sizing_depth > MENU_MAX_UPDATE_DEPTH Then Return 0
    d->sizing_depth -= 1
    If d->sizing_depth = 0 Then
        If d->sizing_height_pending <> 0 Then
            d->sizing_height_pending = 0
            menu_UpdateHeight m
        End If
        If d->sizing_width_pending <> 0 Then
            d->sizing_width_pending = 0
            menu_UpdateWidth m
        End If
    End If
    Return -1
End Function

Private Function menu_GetOpaqueBounds(ByVal w As Widget Ptr, ByRef x As Integer, _
    ByRef y As Integer, ByRef widthValue As Integer, ByRef heightValue As Integer) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->w < 2 OrElse w->h < 2 Then Return 0
    Dim As MenuData Ptr d = w->data
    If d->parent_menu <> 0 OrElse d->count < 0 OrElse d->count > MENU_MAX_ITEMS Then Return 0
    ' The border and background fill the root surface before text is drawn.
    ' An open branch can leave gaps between nodes, so its union is not opaque.
    x = w->ax: y = w->ay: widthValue = w->w: heightValue = w->h
    Return -1
End Function

Function menu_Create(ByVal nm As String, ByVal x As Integer, ByVal y As Integer) As Widget Ptr
    Dim As Widget Ptr wgt = New Widget
    If wgt = 0 Then Return 0

    Dim As MenuData Ptr d = New MenuData
    If d = 0 Then
        Delete wgt
        Return 0
    End If

    wgt->name = nm
    wgt->x = x
    wgt->y = y
    wgt->w = MENU_DEFAULT_WIDTH
    wgt->h = 0
    wgt->visible = 0
    wgt->enabled = 1
    wgt->pointer_global = -1
    wgt->is_window = -1
    wgt->escape_parent_clip = -1
    wgt->accepts_focus = -1
    wgt->pointer_test = @menu_PointerTest
    wgt->cancel_input = @menu_CancelInput
    wgt->render = @menu_Render
    wgt->update = @menu_Update
    wgt->destroy = @menu_Destroy
    d->count = 0
    d->open_submenu = -1
    d->hover_index = -1
    d->selected = -1
    d->item_height = MENU_ITEM_HEIGHT
    d->vertical_inset = MENU_SELECTION_INSET
    d->caption_inset = 28
    d->shortcut_inset = 20
    d->separator_inset = MENU_SEPARATOR_INSET
    d->text_y_offset = 0
    d->pointer_latch = 0
    d->pointer_index = -1
    d->selection_handler = 0
    d->selection_context = 0
    wgt->data = d
    wgt->render_observation = @menu_GetRenderObservation
    gui_SetRenderBoundsHandler wgt, @menu_GetRenderBounds
    gui_SetOpaqueRenderBoundsHandler wgt, @menu_GetOpaqueBounds
    Return wgt
End Function


Sub menu_AddDisplayItem( _
    ByVal m As Widget Ptr, _
    ByVal txt As String, _
    ByVal cb As Sub(ByVal As Integer) _
)
    Dim As MenuData Ptr d

    If m = 0 OrElse m->data = 0 Then Exit Sub
    d = Cast(MenuData Ptr, m->data)
    If d->count < 0 OrElse d->count >= MENU_MAX_ITEMS Then Exit Sub

    d->items(d->count) = txt
    d->callbacks(d->count) = cb
    d->item_enabled(d->count) = -1
    d->item_visible(d->count) = -1
    d->shortcut_scan_codes(d->count) = 0
    d->shortcut_modifiers(d->count) = INPUT_MODIFIER_NONE
    d->item_kinds(d->count) = MENU_ITEM_KIND_NORMAL
    d->count += 1
    menu_UpdateHeight m

    menu_UpdateWidth m
End Sub


Sub menu_AddItem( _
    ByVal m As Widget Ptr, _
    ByVal txt As String, _
    ByVal cb As Sub(ByVal As Integer) _
)
    If m = 0 OrElse m->data = 0 Then Exit Sub
    Dim As MenuData Ptr d = Cast(MenuData Ptr, m->data)
    If d->count < 0 OrElse d->count >= MENU_MAX_ITEMS Then Exit Sub
    menu_AddDisplayItem(m, gui_TransformText(txt), cb)
End Sub


Sub menu_AddSeparator(ByVal m As Widget Ptr)
    Dim As MenuData Ptr d

    If m = 0 OrElse m->data = 0 Then Exit Sub
    d = Cast(MenuData Ptr, m->data)
    If d->count >= MENU_MAX_ITEMS Then Exit Sub

    d->items(d->count) = ""
    d->callbacks(d->count) = 0
    d->item_kinds(d->count) = MENU_ITEM_KIND_SEPARATOR
    d->item_visible(d->count) = -1
    d->item_enabled(d->count) = 0
    d->shortcut_scan_codes(d->count) = 0
    d->shortcut_modifiers(d->count) = INPUT_MODIFIER_NONE
    d->count += 1
    menu_UpdateHeight m
End Sub


Sub menu_SetItemHeight( _
    ByVal m As Widget Ptr, _
    ByVal itemHeight As Integer _
)
    If m = 0 OrElse m->data = 0 Then Exit Sub
    If itemHeight < MENU_MINIMUM_ITEM_HEIGHT Then _
        itemHeight = MENU_MINIMUM_ITEM_HEIGHT
    If itemHeight > MENU_MAXIMUM_ITEM_HEIGHT Then _
        itemHeight = MENU_MAXIMUM_ITEM_HEIGHT

    Dim As MenuData Ptr d = Cast(MenuData Ptr, m->data)
    d->item_height = itemHeight
    menu_UpdateHeight m
End Sub

Sub menu_SetInsets( _
    ByVal m As Widget Ptr, ByVal verticalInset As Integer, _
    ByVal captionInset As Integer, ByVal shortcutInset As Integer, _
    ByVal separatorInset As Integer _
)
    If m = 0 OrElse m->data = 0 Then Exit Sub
    If verticalInset < 1 OrElse verticalInset > MENU_MAXIMUM_INSET OrElse _
       captionInset < 1 OrElse captionInset > MENU_MAXIMUM_INSET OrElse _
       shortcutInset < 1 OrElse shortcutInset > MENU_MAXIMUM_INSET OrElse _
       separatorInset < 1 OrElse separatorInset > MENU_MAXIMUM_INSET Then Exit Sub
    Dim As MenuData Ptr d = m->data
    d->vertical_inset = verticalInset
    d->caption_inset = captionInset
    d->shortcut_inset = shortcutInset
    d->separator_inset = separatorInset
    menu_UpdateHeight m
    menu_UpdateWidth m
End Sub


Function menu_SetTextYOffset( _
    ByVal m As Widget Ptr, ByVal offsetPixels As Integer _
) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return 0
    If offsetPixels < -32 OrElse offsetPixels > 32 Then Return 0

    Cast(MenuData Ptr, m->data)->text_y_offset = offsetPixels
    Return -1
End Function


Sub menu_ClearItems(ByVal m As Widget Ptr)
    Dim As MenuData Ptr d

    If m = 0 OrElse m->data = 0 Then Exit Sub
    d = Cast(MenuData Ptr, m->data)
    If d->parent_menu = 0 Then
        menu_CloseTree(m)
    Else
        menu_HideBranch(m)
        Dim As MenuData Ptr parentData = d->parent_menu->data
        If parentData->open_submenu >= 0 AndAlso parentData->open_submenu < parentData->count Then
            If parentData->submenus(parentData->open_submenu) = m Then parentData->open_submenu = -1
        End If
    End If

    For itemIndex As Integer = 0 To MENU_MAX_ITEMS - 1
        If d->submenus(itemIndex) <> 0 Then
            Dim As Widget Ptr child = d->submenus(itemIndex)
            d->submenus(itemIndex) = 0
            gui_RemoveWidget(child->name)
        End If
        d->command_ids(itemIndex) = 0
        d->items(itemIndex) = ""
        d->callbacks(itemIndex) = 0
        d->item_kinds(itemIndex) = MENU_ITEM_KIND_NORMAL
        d->shortcuts(itemIndex) = ""
        d->shortcut_scan_codes(itemIndex) = 0
        d->shortcut_modifiers(itemIndex) = INPUT_MODIFIER_NONE
        d->item_enabled(itemIndex) = -1
        d->item_visible(itemIndex) = -1
        d->item_checked(itemIndex) = 0
        d->item_submenu(itemIndex) = 0
    Next itemIndex

    d->count = 0
    d->selected = -1
    d->pointer_latch = 0
    d->pointer_index = -1
    d->details_style = 0
    d->open_submenu = -1
    d->hover_menu = 0
    d->pointer_menu = 0
    d->hover_index = -1
    d->scroll_top = 0
    d->visible_rows = 0
    m->w = MENU_DEFAULT_WIDTH
    m->h = 0
    ' Clear publishes its empty geometry itself, even inside an update scope.
    d->sizing_height_pending = 0
    d->sizing_width_pending = 0
End Sub


Sub menu_SetSelectionHandler( _
    ByVal m As Widget Ptr, _
    ByVal selection_handler As Any Ptr, _
    ByVal selection_context As Any Ptr _
)
    Dim As MenuData Ptr d

    If m = 0 OrElse m->data = 0 Then Exit Sub
    d = Cast(MenuData Ptr, m->data)
    d->selection_handler = selection_handler
    d->selection_context = selection_context
End Sub

' -------------------------------------------------------------------------
' Rendering
' -------------------------------------------------------------------------

Sub menu_SetItemDetails( _
    ByVal m As Widget Ptr, ByVal itemIndex As Integer, _
    ByVal shortcutText As String, ByVal isEnabled As Integer, _
    ByVal isChecked As Integer, ByVal hasSubmenu As Integer _
)
    If m = 0 OrElse m->data = 0 Then Exit Sub
    Dim As MenuData Ptr d = m->data
    If itemIndex < 0 OrElse itemIndex >= d->count Then Exit Sub
    d->details_style = -1
    d->shortcuts(itemIndex) = shortcutText
    d->item_enabled(itemIndex) = IIf(isEnabled <> 0, -1, 0)
    d->item_checked(itemIndex) = IIf(isChecked <> 0, -1, 0)
    d->item_submenu(itemIndex) = IIf(hasSubmenu <> 0, -1, 0)
    ' Menus share caption and shortcut columns, even when their longest
    ' entries occur on different rows.
    menu_UpdateWidth m
End Sub

Private Sub menu_RenderNode(ByVal w As Widget Ptr, ByVal depth As Integer)
    Dim As MenuData Ptr d

    If w = 0 OrElse w->data = 0 OrElse w->w < 2 OrElse w->h < 2 OrElse _
       depth >= MENU_MAX_NESTING Then Exit Sub
    d = Cast(MenuData Ptr, w->data)
    If d->count < 0 OrElse d->count > MENU_MAX_ITEMS Then Exit Sub
    Dim As GUI_Theme savedTheme = current_theme
    If w->appearance <> 0 Then current_theme = *w->appearance

    Dim As Integer clipX, clipY, clipWidth, clipHeight
    backend_GetClip clipX, clipY, clipWidth, clipHeight
    Dim As LongInt leftEdge = w->ax
    Dim As LongInt topEdge = w->ay
    Dim As LongInt rightEdge = CLngInt(w->ax) + w->w
    Dim As LongInt bottomEdge = CLngInt(w->ay) + w->h
    If leftEdge < clipX Then leftEdge = clipX
    If topEdge < clipY Then topEdge = clipY
    If rightEdge > CLngInt(clipX) + clipWidth Then rightEdge = CLngInt(clipX) + clipWidth
    If bottomEdge > CLngInt(clipY) + clipHeight Then bottomEdge = CLngInt(clipY) + clipHeight
    ' A menu paints inside its own surface. Pop the clip before drawing its
    ' open child, whose surface may escape that rectangle. Avoid empty pushes:
    ' the backend's legacy empty clip maps to the pixel at the screen origin.
    If rightEdge > leftEdge AndAlso bottomEdge > topEdge Then
        backend_SetClip CInt(leftEdge), CInt(topEdge), _
            CInt(rightEdge - leftEdge), CInt(bottomEdge - topEdge)

        backend_Rect(w->ax, w->ay, w->w, w->h, current_theme.win_border, 0)
        backend_Rect _
            (w->ax + 1, w->ay + 1, w->w - 2, w->h - 2, _
            current_theme.menu_background, 1)

        Dim As Integer visibleCount = menu_VisibleItemCount(d)
        Dim As Integer lastVisibleRow = visibleCount - 1
        If d->visible_rows > 0 AndAlso _
           lastVisibleRow >= d->scroll_top + d->visible_rows Then _
            lastVisibleRow = d->scroll_top + d->visible_rows - 1
        For visibleRow As Integer = d->scroll_top To lastVisibleRow
            Dim As Integer itemIndex = menu_IndexAtVisibleRow(d, visibleRow)
            If itemIndex < 0 Then Continue For
            Dim As Integer itemY = w->ay + d->vertical_inset + _
                (visibleRow - d->scroll_top) * d->item_height

            If d->item_kinds(itemIndex) = MENU_ITEM_KIND_SEPARATOR Then
                Dim As Integer lineY = itemY + (d->item_height \ 2)
                Dim As Integer lineX1 = w->ax + d->separator_inset
                Dim As Integer lineX2 = w->ax + w->w - d->separator_inset - 1

                If lineX2 >= lineX1 Then
                    backend_Line _
                        (lineX1, lineY, lineX2, lineY, current_theme.menu_separator)
                    If d->details_style = 0 AndAlso lineY + 1 < w->ay + w->h - 1 Then _
                        backend_Line _
                            (lineX1, lineY + 1, lineX2, lineY + 1, _
                            current_theme.bg_light)
                End If
            ElseIf d->details_style <> 0 Then
                Dim As ULong textColor = current_theme.menu_text
                Dim As Integer textY = itemY + _
                    ((d->item_height - backend_GetTextHeight()) \ 2) + _
                    d->text_y_offset
                Dim As Integer detailMnemonicScanCode
                Dim As Integer detailMnemonicDisplayIndex
                Dim As String detailDisplayText = menu_DisplayText( _
                    d->items(itemIndex), detailMnemonicScanCode, _
                    detailMnemonicDisplayIndex _
                )
                If d->selected = itemIndex AndAlso d->item_enabled(itemIndex) <> 0 Then
                    backend_Rect(w->ax + 2, itemY, w->w - 4, d->item_height, _
                        current_theme.menu_selected_background, 1)
                    textColor = current_theme.menu_selected_text
                End If
                If d->item_enabled(itemIndex) = 0 Then textColor = current_theme.menu_disabled_text
                backend_Print( _
                    w->ax + d->caption_inset, textY, textColor, detailDisplayText _
                )
                menu_RenderMnemonicUnderline( _
                    detailDisplayText, detailMnemonicDisplayIndex, _
                    w->ax + d->caption_inset, textY, backend_GetTextHeight() _
                )
                If d->shortcuts(itemIndex) <> "" Then _
                    backend_Print(w->ax + w->w - d->shortcut_inset - backend_GetTextWidth(d->shortcuts(itemIndex)), _
                        textY, textColor, d->shortcuts(itemIndex))
                If d->item_checked(itemIndex) <> 0 Then
                    backend_Line(w->ax + 9, itemY + d->item_height \ 2, _
                        w->ax + 12, itemY + d->item_height \ 2 + 3, textColor)
                    backend_Line(w->ax + 12, itemY + d->item_height \ 2 + 3, _
                        w->ax + 18, itemY + d->item_height \ 2 - 3, textColor)
                End If
                If d->item_submenu(itemIndex) <> 0 Then
                    Dim As Integer arrowX = w->ax + w->w - 12
                    Dim As Integer arrowY = itemY + d->item_height \ 2
                    backend_Line(arrowX - 2, arrowY - 3, arrowX + 1, arrowY, textColor)
                    backend_Line(arrowX + 1, arrowY, arrowX - 2, arrowY + 3, textColor)
                End If
            ElseIf d->selected = itemIndex Then
                Dim As Integer selectedMnemonicScanCode
                Dim As Integer selectedMnemonicDisplayIndex
                Dim As String selectedDisplayText = menu_DisplayText( _
                    d->items(itemIndex), selectedMnemonicScanCode, _
                    selectedMnemonicDisplayIndex _
                )
                Dim As Integer selectedTextY = itemY + _
                    ((d->item_height - MENU_TEXT_HEIGHT) \ 2) + _
                    d->text_y_offset
                backend_Rect _
                    (w->ax + MENU_SELECTION_INSET, itemY, _
                    w->w - MENU_SELECTION_INSET * 2, d->item_height, _
                    current_theme.menu_selected_background, 1)
                backend_Print _
                    (w->ax + MENU_TEXT_INSET, _
                    itemY + ((d->item_height - MENU_TEXT_HEIGHT) \ 2) + _
                        d->text_y_offset, _
                    current_theme.menu_selected_text, selectedDisplayText)
                menu_RenderMnemonicUnderline( _
                    selectedDisplayText, selectedMnemonicDisplayIndex, _
                    w->ax + MENU_TEXT_INSET, selectedTextY, _
                    backend_GetTextHeight() _
                )
            Else
                Dim As Integer normalMnemonicScanCode
                Dim As Integer normalMnemonicDisplayIndex
                Dim As String normalDisplayText = menu_DisplayText( _
                    d->items(itemIndex), normalMnemonicScanCode, _
                    normalMnemonicDisplayIndex _
                )
                Dim As Integer normalTextY = itemY + _
                    ((d->item_height - MENU_TEXT_HEIGHT) \ 2) + _
                    d->text_y_offset
                backend_Print _
                    (w->ax + MENU_TEXT_INSET, _
                    normalTextY, current_theme.menu_text, normalDisplayText)
                menu_RenderMnemonicUnderline( _
                    normalDisplayText, normalMnemonicDisplayIndex, _
                    w->ax + MENU_TEXT_INSET, normalTextY, _
                    backend_GetTextHeight() _
                )
            End If
        Next visibleRow
        backend_ResetClip
    End If
    /'
        Draw the open branch in ancestry order even when callers constructed
        its deepest menu first. Registered descendants retain lifetime and
        visibility management, but the root owns this complete popup surface.
    '/
    If d->open_submenu >= 0 AndAlso d->open_submenu < d->count Then
        Dim As Widget Ptr child = d->submenus(d->open_submenu)
        If child <> 0 AndAlso child->visible <> 0 Then menu_RenderNode(child, depth + 1)
    End If
    current_theme = savedTheme
End Sub

Sub menu_Render(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    If Cast(MenuData Ptr, w->data)->parent_menu <> 0 Then Exit Sub
    menu_RenderNode(w, 0)
End Sub

' -------------------------------------------------------------------------
' Processing
' -------------------------------------------------------------------------

Private Function menu_NodeAtPoint(ByVal root As Widget Ptr, ByVal x As Integer, ByVal y As Integer) As Widget Ptr
    Dim As Widget Ptr current = root
    Dim As Widget Ptr result = 0
    Dim As Integer depth
    While current <> 0 AndAlso depth < MENU_MAX_NESTING
        If x >= current->ax AndAlso x < current->ax + current->w AndAlso _
           y >= current->ay AndAlso y < current->ay + current->h Then result = current
        Dim As MenuData Ptr d = current->data
        If d->open_submenu < 0 OrElse d->open_submenu >= d->count Then Exit While
        current = d->submenus(d->open_submenu)
        If current <> 0 AndAlso current->visible = 0 Then Exit While
        depth += 1
    Wend
    Return result
End Function

Private Sub menu_EnsureSelectionVisible(ByVal m As Widget Ptr)
    Dim As MenuData Ptr d = m->data
    If d->selected < 0 OrElse d->visible_rows < 1 Then Exit Sub
    Dim As Integer visibleRow = menu_VisibleRowOfIndex(d, d->selected)
    If visibleRow < 0 Then Exit Sub
    If visibleRow < d->scroll_top Then d->scroll_top = visibleRow
    If visibleRow >= d->scroll_top + d->visible_rows Then _
        d->scroll_top = visibleRow - d->visible_rows + 1
End Sub

Private Sub menu_MoveSelection(ByVal m As Widget Ptr, ByVal direction As Integer)
    Dim As MenuData Ptr d = m->data
    Dim As Integer candidate = d->selected
    ' fblint: disable-next-line FBL311 REASON: The loop counter bounds repeated work; the cursor or stream state supplies each value.
    For attempt As Integer = 0 To d->count - 1
        candidate += direction
        If candidate < 0 Then candidate = d->count - 1
        If candidate >= d->count Then candidate = 0
        If d->item_kinds(candidate) = MENU_ITEM_KIND_NORMAL AndAlso _
           d->item_enabled(candidate) <> 0 AndAlso _
           d->item_visible(candidate) <> 0 Then
            d->selected = candidate
            menu_EnsureSelectionVisible(m)
            Exit Sub
        End If
    Next attempt
End Sub

Private Sub menu_Activate(ByVal m As Widget Ptr, ByVal itemIndex As Integer)
    Dim As MenuData Ptr d = m->data
    If itemIndex < 0 OrElse itemIndex >= d->count OrElse _
       d->item_kinds(itemIndex) <> MENU_ITEM_KIND_NORMAL OrElse _
       d->item_enabled(itemIndex) = 0 OrElse d->item_visible(itemIndex) = 0 Then Exit Sub
    If d->submenus(itemIndex) <> 0 Then
        menu_OpenSubmenu(m, itemIndex, -1)
        Exit Sub
    End If
    Dim As Any Ptr selectionHandler = d->selection_handler
    Dim As Any Ptr selectionContext = d->selection_context
    Dim As Sub(ByVal As Integer) itemCallback = d->callbacks(itemIndex)
    menu_CloseTree(m)
    ' Owners may rebuild or remove the tree in this callback. Keep its values
    ' locally and never touch the old menu after invoking application code.
    If selectionHandler <> 0 Then
        Cast(Sub(ByVal As Any Ptr, ByVal As Integer), selectionHandler)(selectionContext, itemIndex)
    ElseIf itemCallback <> 0 Then
        itemCallback(itemIndex)
    End If
End Sub


Private Function menu_FindMnemonic( _
    ByVal m As Widget Ptr, ByVal scanCode As Integer _
) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return -1
    Dim As MenuData Ptr d = m->data
    For itemIndex As Integer = 0 To d->count - 1
        If d->item_kinds(itemIndex) <> MENU_ITEM_KIND_NORMAL OrElse _
           d->item_visible(itemIndex) = 0 OrElse _
           d->item_enabled(itemIndex) = 0 Then Continue For
        Dim As Integer itemScanCode, displayIndex
        Dim As String displayText = menu_DisplayText( _
            d->items(itemIndex), itemScanCode, displayIndex _
        )
        If itemScanCode = scanCode AndAlso Len(displayText) > 0 Then _
            Return itemIndex
    Next itemIndex
    Return -1
End Function


Function menu_ActivateItem( _
    ByVal m As Widget Ptr, ByVal itemIndex As Integer _
) As Integer
    If m = 0 OrElse m->data = 0 OrElse m->render <> @menu_Render Then Return 0
    Dim As MenuData Ptr d = m->data
    If itemIndex < 0 OrElse itemIndex >= d->count OrElse _
       d->item_kinds(itemIndex) <> MENU_ITEM_KIND_NORMAL OrElse _
       d->item_visible(itemIndex) = 0 OrElse _
       d->item_enabled(itemIndex) = 0 Then Return 0
    menu_Activate(m, itemIndex)
    Return -1
End Function


Private Function menu_ActivateShortcutBranch( _
    ByVal m As Widget Ptr, ByVal depth As Integer _
) As Integer
    If m = 0 OrElse m->data = 0 OrElse depth >= MENU_MAX_NESTING Then Return 0
    Dim As MenuData Ptr d = m->data
    For itemIndex As Integer = 0 To d->count - 1
        If d->item_visible(itemIndex) = 0 OrElse _
           d->item_enabled(itemIndex) = 0 OrElse _
           d->item_kinds(itemIndex) <> MENU_ITEM_KIND_NORMAL Then Continue For
        If d->submenus(itemIndex) = 0 AndAlso _
           d->shortcut_scan_codes(itemIndex) <> 0 AndAlso _
           input_ExactModifiedKeyPressEvent( _
               d->shortcut_scan_codes(itemIndex), _
               d->shortcut_modifiers(itemIndex) _
           ) Then
            menu_Activate(m, itemIndex)
            Return -1
        End If
    Next itemIndex

    For itemIndex As Integer = 0 To d->count - 1
        If d->submenus(itemIndex) = 0 OrElse _
           d->item_visible(itemIndex) = 0 OrElse _
           d->item_enabled(itemIndex) = 0 Then Continue For
        If menu_ActivateShortcutBranch(d->submenus(itemIndex), depth + 1) Then _
            Return -1
    Next itemIndex
    Return 0
End Function


Function menu_ActivateShortcut(ByVal m As Widget Ptr) As Integer
    Dim As Widget Ptr root = menu_GetRoot(m)
    If root = 0 OrElse root->data = 0 Then Return 0
    Return menu_ActivateShortcutBranch(root, 0)
End Function

Private Function menu_ProcessKeyboard(ByVal root As Widget Ptr, ByVal scanCode As Integer) As Integer
    Dim As Widget Ptr leaf = menu_GetOpenLeaf(root)
    If leaf = 0 Then Return 0
    Dim As MenuData Ptr d = leaf->data
    Dim As MenuData Ptr rootData = root->data
    If scanCode = KEY_DOWN Then
        menu_MoveSelection(leaf, 1)
    ElseIf scanCode = KEY_UP Then
        menu_MoveSelection(leaf, -1)
    ElseIf scanCode = KEY_HOME Then
        d->selected = menu_FirstEnabled(leaf)
        menu_EnsureSelectionVisible(leaf)
    ElseIf scanCode = KEY_END Then
        d->selected = 0
        menu_MoveSelection(leaf, -1)
    ElseIf scanCode = KEY_RIGHT Then
        If menu_OpenSubmenu(leaf, d->selected, -1) = 0 AndAlso rootData->menubar_handler <> 0 Then
            Cast(Sub(ByVal As Any Ptr, ByVal As Integer), rootData->menubar_handler)(rootData->menubar_context, 1)
        End If
    ElseIf scanCode = KEY_LEFT OrElse _
           scanCode = KEY_ESCAPE Then
        If d->parent_menu <> 0 Then
            Dim As MenuData Ptr parentData = d->parent_menu->data
            menu_HideBranch(leaf)
            parentData->open_submenu = -1
            rootData->hover_menu = 0
            rootData->hover_clock = Timer
        ElseIf scanCode = KEY_LEFT AndAlso rootData->menubar_handler <> 0 Then
            Cast(Sub(ByVal As Any Ptr, ByVal As Integer), rootData->menubar_handler)(rootData->menubar_context, -1)
        Else
            menu_CloseTree(root)
        End If
    ElseIf scanCode = KEY_RETURN OrElse _
           scanCode = FB.SC_SPACE Then
        If d->selected < 0 Then d->selected = menu_FirstEnabled(leaf)
        menu_Activate(leaf, d->selected)
    Else
        Dim As Integer mnemonicIndex = menu_FindMnemonic(leaf, scanCode)
        If mnemonicIndex < 0 Then Return 0
        d->selected = mnemonicIndex
        menu_EnsureSelectionVisible(leaf)
        If d->submenus(mnemonicIndex) <> 0 Then
            menu_OpenSubmenu(leaf, mnemonicIndex, -1)
        Else
            menu_Activate(leaf, mnemonicIndex)
        End If
    End If
    Return -1
End Function

Sub menu_Update(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As MenuData Ptr d = w->data
    If d->parent_menu <> 0 Then Exit Sub
    d->keyboard_handled = 0
    If w->has_focus <> 0 Then
        Dim As Integer scanCode, modifiers, handledKeys
        For eventIndex As Integer = 0 To input_KeyEventCount() - 1
            If input_KeyEvent(eventIndex, scanCode, modifiers) = 0 Then Continue For
            If modifiers <> INPUT_MODIFIER_NONE Then Continue For
            Select Case scanCode
            Case KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END, KEY_ESCAPE, KEY_RETURN, FB.SC_SPACE
                ' A callback may remove its own tree. After each event, compare
                ' the registered identity before touching this menu again.
                d->keyboard_handled = -1
                handledKeys = -1
                menu_ProcessKeyboard(w, scanCode)
                If gui_IsWidgetRegistered(w) = 0 Then Exit Sub
                If w->visible = 0 Then Exit Sub
            Case Else
                If menu_FindMnemonic(menu_GetOpenLeaf(w), scanCode) >= 0 Then
                    d->keyboard_handled = -1
                    handledKeys = -1
                    menu_ProcessKeyboard(w, scanCode)
                    If gui_IsWidgetRegistered(w) = 0 Then Exit Sub
                    If w->visible = 0 Then Exit Sub
                End If
            End Select
        Next eventIndex
        If handledKeys <> 0 Then Exit Sub
    End If

    Dim As Integer mouseX = input_MouseX()
    Dim As Integer mouseY = input_MouseY()
    Dim As Integer mouseButtons = input_MouseButtons()
    Dim As Widget Ptr pointerMenu = menu_NodeAtPoint(w, mouseX, mouseY)
    Dim As Integer pointerIndex = MENU_POINTER_OUTSIDE
    If pointerMenu <> 0 Then pointerIndex = menu_HitTest(pointerMenu, pointerMenu->data, mouseX, mouseY)
    Dim As Integer pointerMoved = IIf(mouseX <> d->last_pointer_x OrElse mouseY <> d->last_pointer_y, -1, 0)
    d->last_pointer_x = mouseX
    d->last_pointer_y = mouseY

    If pointerMenu <> 0 Then
        Dim As MenuData Ptr pointerData = pointerMenu->data
        If input_MouseWheel() <> 0 AndAlso pointerData->visible_rows > 0 Then
            pointerData->scroll_top -= input_MouseWheel() * 3
            menu_ConfigureViewport(pointerMenu)
            pointerMoved = -1
            pointerIndex = menu_HitTest(pointerMenu, pointerData, mouseX, mouseY)
        End If
        If pointerMoved <> 0 OrElse (mouseButtons And 1) <> 0 Then
            pointerData->selected = IIf(pointerIndex >= 0, pointerIndex, -1)
            d->hover_menu = pointerMenu
            d->hover_index = pointerIndex
            d->hover_clock = Timer
        End If
        Dim As Double elapsedSeconds = Timer - d->hover_clock
        If elapsedSeconds < 0 Then elapsedSeconds += 86400.0
        If d->pointer_latch = 0 AndAlso d->hover_menu = pointerMenu AndAlso _
           d->hover_index = pointerIndex AndAlso elapsedSeconds >= MENU_HOVER_DELAY_SECONDS Then
            If pointerIndex >= 0 AndAlso pointerData->submenus(pointerIndex) <> 0 Then
                menu_OpenSubmenu(pointerMenu, pointerIndex)
            ElseIf pointerData->open_submenu >= 0 AndAlso pointerData->open_submenu < pointerData->count Then
                menu_HideBranch(pointerData->submenus(pointerData->open_submenu))
                pointerData->open_submenu = -1
            End If
        End If
    End If

    If (mouseButtons And 1) <> 0 Then
        If d->pointer_latch = 0 Then
            d->pointer_latch = -1
            d->pointer_menu = pointerMenu
            d->pointer_index = pointerIndex
            If pointerMenu <> 0 AndAlso pointerIndex >= 0 Then menu_OpenSubmenu(pointerMenu, pointerIndex)
        End If
    ElseIf d->pointer_latch <> 0 Then
        Dim As Widget Ptr pressedMenu = d->pointer_menu
        Dim As Integer pressedIndex = d->pointer_index
        d->pointer_latch = 0
        d->pointer_menu = 0
        d->pointer_index = -1
        If pointerMenu = pressedMenu AndAlso pointerMenu <> 0 AndAlso pointerIndex = pressedIndex AndAlso pointerIndex >= 0 Then
            Dim As MenuData Ptr pointerData = pointerMenu->data
            If pointerData->submenus(pointerIndex) = 0 Then menu_Activate(pointerMenu, pointerIndex)
        ElseIf pressedMenu = 0 OrElse pointerMenu = 0 Then
            menu_CloseTree(w)
        End If
    End If
End Sub

Function menu_TakeKeyboardHandled(ByVal m As Widget Ptr) As Integer
    If gui_IsWidgetRegistered(m) = 0 OrElse m->data = 0 Then Return 0
    Dim As MenuData Ptr d = m->data
    Dim As Integer wasHandled = d->keyboard_handled
    d->keyboard_handled = 0
    Return wasHandled
End Function

Sub menu_CancelInput(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As MenuData Ptr d = w->data
    d->pointer_latch = 0
    d->pointer_menu = 0
    d->pointer_index = -1
End Sub

' -------------------------------------------------------------------------
' Lifecycle
' -------------------------------------------------------------------------

Sub menu_Destroy(ByVal w As Widget Ptr)
    If w = 0 Then Exit Sub
    If w->data <> 0 Then Delete Cast(MenuData Ptr, w->data)
    w->data = 0
End Sub

' fblint: disable-next-line FBL950 FBL-INC-002 -- Menu's companion shares its private node helpers in the implementation assembly.
#include once "src/widgets/menu_retained.bas"

' end of menu.bas
