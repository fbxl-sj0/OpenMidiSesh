/'
    Project: omaGUI
    ---------------

    File: menubar.bas

    Purpose:

        Implement a portable Windows-style menu bar with bounded drop-downs.

    Responsibilities:

        - calculate stable heading and pop-up geometry
        - render mutable visible labels, check marks, shortcuts, and separators
        - route release-inside pointer activation exactly once
        - dispatch explicit portable accelerators and keyboard navigation

    This file intentionally does NOT contain:

        - application-specific menu commands
        - recursive submenu behavior
        - native Windows menu handles or SDK declarations

    Ownership:

        - each widget owns one MenuBarData allocation and all label strings
'/

#lang "fb"

#include once "src/widgets/menubar.bi"
#include once "src/widgets/menu.bi"
#include once "src/backend/theme.bi"

Const MENUBAR_HEIGHT As Integer = 22
Const MENUBAR_MINIMUM_WIDTH As Integer = 40
Const MENUBAR_MINIMUM_HEADING_WIDTH As Integer = 36
Const MENUBAR_MINIMUM_POPUP_WIDTH As Integer = 96
Const MENUBAR_HEADING_PADDING As Integer = 16
Const MENUBAR_ITEM_PADDING As Integer = 40
Const MENUBAR_CHECK_GUTTER_WIDTH As Integer = 22
Const MENUBAR_SHORTCUT_GAP As Integer = 24
Const MENUBAR_POPUP_RIGHT_PADDING As Integer = 8
Const MENUBAR_ROW_HEIGHT As Integer = 20
Const MENUBAR_POPUP_BORDER As Integer = 1
Const MENUBAR_MAXIMUM_LABEL_BYTES As Integer = 160

' -------------------------------------------------------------------------
' Text and geometry helpers
' -------------------------------------------------------------------------

Private Function menubar_DisplayText( _
    ByRef source_text As Const String _
) As String
    Dim As String display_text
    Dim As Integer display_index, scan_code
    gui_ParseMnemonicCaption source_text, display_text, scan_code, display_index
    Return display_text
End Function


Private Function menubar_IsSeparator( _
    ByRef item_text As Const String _
) As Integer
    Return IIf(Trim(item_text) = "-", -1, 0)
End Function


Private Function menubar_IsSelectable( _
    ByVal bar_data As MenuBarData Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer _
) As Integer
    If bar_data = 0 OrElse menu_index < 0 OrElse _
       menu_index >= bar_data->menu_count Then Return 0
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Return 0
    If bar_data->menu_visible(menu_index) = 0 OrElse bar_data->menu_enabled(menu_index) = 0 Then Return 0
    If bar_data->item_visible(menu_index, item_index) = 0 Then Return 0
    If bar_data->item_enabled(menu_index, item_index) = 0 Then Return 0
    If menubar_IsSeparator( _
        bar_data->item_labels(menu_index, item_index) _
    ) Then Return 0
    Return -1
End Function


Private Function menubar_MnemonicDisplayIndex( _
    ByRef source_text As Const String, _
    ByRef scan_code As Integer _
) As Integer
    Dim As String display_text
    Dim As Integer display_index
    If gui_ParseMnemonicCaption( _
        source_text, display_text, scan_code, display_index _
    ) = 0 Then Return -1
    Return display_index
End Function


Private Sub menubar_RenderMnemonic( _
    ByRef source_text As Const String, _
    ByVal text_left As Integer, _
    ByVal text_top As Integer, _
    ByVal text_height As Integer _
)
    Dim As Integer glyph_width
    Dim As Integer mnemonic_index
    Dim As Integer scan_code
    Dim As Integer underline_left
    Dim As String display_text

    mnemonic_index = menubar_MnemonicDisplayIndex(source_text, scan_code)
    If mnemonic_index < 0 OrElse scan_code = 0 Then Exit Sub
    display_text = menubar_DisplayText(source_text)
    underline_left = text_left + backend_GetTextWidth( _
        Left(display_text, mnemonic_index) _
    )
    glyph_width = backend_GetTextWidth( _
        Mid(display_text, mnemonic_index + 1, 1) _
    )
    If glyph_width < 1 Then Exit Sub
    backend_Line _
        underline_left, text_top + text_height - 3, _
        underline_left + glyph_width - 1, text_top + text_height - 3, _
        theme_GetClassicColor(GUI_CLASSIC_COLOR_ACCESS_TEXT)
End Sub


Private Sub menubar_RecalculatePopupWidth( _
    ByVal bar_data As MenuBarData Ptr, _
    ByVal menu_index As Integer _
)
    Dim As Integer candidate_width
    Dim As Integer item_index
    Dim As Integer popup_width

    If bar_data = 0 OrElse menu_index < 0 OrElse _
       menu_index >= bar_data->menu_count Then Exit Sub
    popup_width = MENUBAR_MINIMUM_POPUP_WIDTH
    For item_index = 0 To bar_data->item_count(menu_index) - 1
        If bar_data->item_visible(menu_index, item_index) = 0 Then Continue For
        If menubar_IsSeparator( _
            bar_data->item_labels(menu_index, item_index) _
        ) Then Continue For
        candidate_width = backend_GetTextWidth(menubar_DisplayText( _
            bar_data->item_labels(menu_index, item_index) _
        )) + MENUBAR_ITEM_PADDING
        If Len(bar_data->item_shortcuts(menu_index, item_index)) > 0 Then
            candidate_width += MENUBAR_SHORTCUT_GAP + backend_GetTextWidth( _
                bar_data->item_shortcuts(menu_index, item_index) _
            )
        End If
        If candidate_width > popup_width Then popup_width = candidate_width
    Next item_index
    bar_data->popup_width(menu_index) = popup_width
End Sub


Private Function menubar_VisibleItemCount( _
    ByVal bar_data As MenuBarData Ptr, _
    ByVal menu_index As Integer _
) As Integer
    Dim As Integer visible_count
    If bar_data = 0 OrElse menu_index < 0 OrElse _
       menu_index >= bar_data->menu_count Then Return 0
    For item_index As Integer = 0 To bar_data->item_count(menu_index) - 1
        If bar_data->item_visible(menu_index, item_index) Then visible_count += 1
    Next item_index
    Return visible_count
End Function


Private Function menubar_ItemAtVisibleRow( _
    ByVal bar_data As MenuBarData Ptr, _
    ByVal menu_index As Integer, _
    ByVal visible_row As Integer _
) As Integer
    Dim As Integer current_row
    If visible_row < 0 Then Return -1
    For item_index As Integer = 0 To bar_data->item_count(menu_index) - 1
        If bar_data->item_visible(menu_index, item_index) = 0 Then Continue For
        If current_row = visible_row Then Return item_index
        current_row += 1
    Next item_index
    Return -1
End Function


Private Function menubar_FirstSelectableItem( _
    ByVal bar_data As MenuBarData Ptr, _
    ByVal menu_index As Integer _
) As Integer
    Dim As Integer item_index

    If bar_data = 0 OrElse menu_index < 0 OrElse _
       menu_index >= bar_data->menu_count Then Return -1

    For item_index = 0 To bar_data->item_count(menu_index) - 1
        If menubar_IsSelectable(bar_data, menu_index, item_index) Then _
            Return item_index
    Next item_index
    Return -1
End Function


Private Function menubar_LastSelectableItem( _
    ByVal bar_data As MenuBarData Ptr, _
    ByVal menu_index As Integer _
) As Integer
    Dim As Integer item_index

    If bar_data = 0 OrElse menu_index < 0 OrElse _
       menu_index >= bar_data->menu_count Then Return -1

    For item_index = bar_data->item_count(menu_index) - 1 To 0 Step -1
        If menubar_IsSelectable(bar_data, menu_index, item_index) Then _
            Return item_index
    Next item_index
    Return -1
End Function


Private Function menubar_MoveSelectableItem( _
    ByVal bar_data As MenuBarData Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByVal direction_value As Integer _
) As Integer
    Dim As Integer candidate_index
    Dim As Integer remaining_items

    If bar_data = 0 OrElse menu_index < 0 OrElse _
       menu_index >= bar_data->menu_count OrElse _
       bar_data->item_count(menu_index) < 1 Then Return -1

    candidate_index = item_index
    remaining_items = bar_data->item_count(menu_index)
    Do While remaining_items > 0
        candidate_index += direction_value
        If candidate_index < 0 Then _
            candidate_index = bar_data->item_count(menu_index) - 1
        If candidate_index >= bar_data->item_count(menu_index) Then _
            candidate_index = 0
        If menubar_IsSelectable( _
            bar_data, menu_index, candidate_index _
        ) Then Return candidate_index
        remaining_items -= 1
    Loop

    Return -1
End Function


Private Function menubar_PopupLeft( _
    ByVal bar_widget As Widget Ptr, _
    ByVal bar_data As MenuBarData Ptr, _
    ByVal menu_index As Integer _
) As Integer
    Dim As Integer popup_left
    Dim As Integer viewport_height
    Dim As Integer viewport_width

    If bar_widget = 0 OrElse bar_data = 0 Then Return 0
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0

    popup_left = bar_widget->ax + bar_data->menu_left(menu_index)
    backend_GetSize viewport_width, viewport_height
    If popup_left + bar_data->popup_width(menu_index) > viewport_width Then _
        popup_left = viewport_width - bar_data->popup_width(menu_index)
    If popup_left < 0 Then popup_left = 0
    Return popup_left
End Function


Private Function menubar_PopupHeight( _
    ByVal bar_data As MenuBarData Ptr, _
    ByVal menu_index As Integer _
) As Integer
    If bar_data = 0 OrElse menu_index < 0 OrElse _
       menu_index >= bar_data->menu_count Then Return 0
    Return menubar_VisibleItemCount(bar_data, menu_index) * MENUBAR_ROW_HEIGHT + _
        MENUBAR_POPUP_BORDER * 2
End Function


Private Sub menubar_SetOpenState( _
    ByVal bar_widget As Widget Ptr, _
    ByVal bar_data As MenuBarData Ptr, _
    ByVal menu_index As Integer _
)
    If bar_widget = 0 OrElse bar_data = 0 Then Exit Sub

    Dim As Integer previous_menu = bar_data->open_menu
    If menu_index = previous_menu AndAlso previous_menu >= 0 AndAlso _
       previous_menu < bar_data->menu_count AndAlso _
       bar_data->menu_popups(previous_menu) <> 0 AndAlso _
       bar_data->menu_popups(previous_menu)->visible <> 0 Then Exit Sub
    If previous_menu >= 0 AndAlso previous_menu < bar_data->menu_count AndAlso _
       previous_menu <> menu_index AndAlso _
       bar_data->menu_popups(previous_menu) <> 0 Then
        Dim As Widget Ptr previous_popup = bar_data->menu_popups(previous_menu)
        bar_data->open_menu = -1
        bar_data->hot_item = -1
        bar_widget->pointer_global = 0
        menu_CloseTree previous_popup
        previous_menu = -1
    End If

    If menu_index >= 0 AndAlso menu_index < bar_data->menu_count AndAlso _
       bar_data->menu_visible(menu_index) AndAlso bar_data->menu_enabled(menu_index) AndAlso _
       ((bar_data->menu_popups(menu_index) <> 0 AndAlso _
         menu_GetVisibleItemCount(bar_data->menu_popups(menu_index)) > 0) OrElse _
        menubar_VisibleItemCount(bar_data, menu_index) > 0) Then
        bar_data->open_menu = menu_index
        bar_data->hot_menu = menu_index
        bar_data->hot_item = menubar_FirstSelectableItem( _
            bar_data, menu_index _
        )
        bar_widget->pointer_global = -1
        If bar_data->menu_popups(menu_index) <> 0 Then
            menu_ShowAt bar_data->menu_popups(menu_index), _
                bar_widget->ax + bar_data->menu_left(menu_index), _
                bar_widget->ay + MENUBAR_HEIGHT, -1
        Else
            gui_SetFocus bar_widget
            gui_BringToFront bar_widget
        End If
    Else
        bar_data->open_menu = -1
        bar_data->hot_item = -1
        bar_widget->pointer_global = 0
        If menu_index < 0 AndAlso previous_menu >= 0 AndAlso _
           previous_menu < bar_data->menu_count AndAlso _
           bar_data->menu_popups(previous_menu) <> 0 Then _
            menu_CloseTree bar_data->menu_popups(previous_menu)
    End If
End Sub


#include once "src/widgets/menubar_headings.bi"

Private Sub menubar_PopupNavigation( _
    ByVal callback_context As Any Ptr, ByVal direction As Integer _
)
    Dim As Widget Ptr bar_widget = callback_context
    If gui_IsWidgetRegistered(bar_widget) = 0 OrElse bar_widget->data = 0 Then Exit Sub
    Dim As MenuBarData Ptr bar_data = bar_widget->data
    If direction = 0 Then
        If bar_data->open_menu >= 0 Then _
            menubar_SetOpenState bar_widget, bar_data, -1
        Exit Sub
    End If
    If direction <> -1 AndAlso direction <> 1 Then Exit Sub
    Dim As Integer next_menu = menubar_NextHeading( _
        bar_data, bar_data->open_menu, direction _
    )
    If next_menu >= 0 AndAlso next_menu <> bar_data->open_menu Then _
        menubar_SetOpenState bar_widget, bar_data, next_menu
End Sub


Function menubar_SetMenuPopup( _
    ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer, _
    ByVal popup_root As Widget Ptr _
) As Integer
    Dim As MenuBarData Ptr bar_data = _
        menubar_HeadingData(bar_widget, menu_index)
    If bar_data = 0 OrElse popup_root = 0 Then Return 0
    If bar_data->menu_popups(menu_index) = popup_root Then Return -1
    If bar_data->menu_popups(menu_index) <> 0 OrElse _
       popup_root->render <> @menu_Render OrElse _
       popup_root->data = 0 OrElse popup_root->parent <> 0 OrElse _
       menu_GetRoot(popup_root) <> popup_root OrElse _
       menu_GetItemCount(popup_root) < 1 Then Return 0

    If gui_IsWidgetRegistered(popup_root) = 0 Then gui_AddWidget popup_root
    If gui_IsWidgetRegistered(popup_root) = 0 Then Return 0
    gui_SetParent popup_root, bar_widget
    If popup_root->parent <> bar_widget Then Return 0
    menu_SetMenuBarOwner popup_root, bar_widget
    menu_SetMenuBarHandler( _
        popup_root, @menubar_PopupNavigation, bar_widget _
    )
    bar_data->menu_popups(menu_index) = popup_root
    Return -1
End Function


Function menubar_GetMenuPopup( _
    ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer _
) As Widget Ptr
    Dim As MenuBarData Ptr bar_data = _
        menubar_HeadingData(bar_widget, menu_index)
    If bar_data = 0 Then Return 0
    Return bar_data->menu_popups(menu_index)
End Function

Private Sub menubar_PointerTarget( _
    ByVal bar_widget As Widget Ptr, _
    ByVal bar_data As MenuBarData Ptr, _
    ByVal pointer_x As Integer, _
    ByVal pointer_y As Integer, _
    ByRef menu_index As Integer, _
    ByRef item_index As Integer _
)
    Dim As Integer candidate_index
    Dim As Integer popup_height
    Dim As Integer popup_left
    Dim As Integer popup_width

    menu_index = -1
    item_index = -1
    If bar_widget = 0 OrElse bar_data = 0 Then Exit Sub

    If pointer_y >= bar_widget->ay AndAlso _
       pointer_y < bar_widget->ay + MENUBAR_HEIGHT Then
        For candidate_index = 0 To bar_data->menu_count - 1
            If menubar_HeadingAvailable(bar_data, candidate_index) = 0 Then Continue For
            If pointer_x >= _
                   bar_widget->ax + bar_data->menu_left(candidate_index) _
               AndAlso pointer_x < _
                   bar_widget->ax + bar_data->menu_left(candidate_index) + _
                       bar_data->menu_width(candidate_index) Then
                menu_index = candidate_index
                Exit Sub
            End If
        Next candidate_index
    End If

    candidate_index = bar_data->open_menu
    If candidate_index < 0 OrElse candidate_index >= bar_data->menu_count Then _
        Exit Sub
    If bar_data->menu_popups(candidate_index) <> 0 Then Exit Sub
    popup_left = menubar_PopupLeft(bar_widget, bar_data, candidate_index)
    popup_width = bar_data->popup_width(candidate_index)
    popup_height = menubar_PopupHeight(bar_data, candidate_index)
    If pointer_x < popup_left OrElse pointer_x >= popup_left + popup_width OrElse _
       pointer_y < bar_widget->ay + MENUBAR_HEIGHT + MENUBAR_POPUP_BORDER OrElse _
       pointer_y >= bar_widget->ay + MENUBAR_HEIGHT + popup_height - _
           MENUBAR_POPUP_BORDER Then Exit Sub

    menu_index = candidate_index
    Dim As Integer visible_row = (pointer_y - bar_widget->ay - _
        MENUBAR_HEIGHT - MENUBAR_POPUP_BORDER) \ MENUBAR_ROW_HEIGHT
    item_index = menubar_ItemAtVisibleRow( _
        bar_data, candidate_index, visible_row)
    If item_index < 0 Then
        menu_index = -1
        item_index = -1
    End If
End Sub

' -------------------------------------------------------------------------
' Construction and public metadata API
' -------------------------------------------------------------------------

Function menubar_Create( _
    ByVal widget_name As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal bar_width As Integer _
) As Widget Ptr
    Dim As MenuBarData Ptr bar_data
    Dim As Widget Ptr bar_widget

    If Len(widget_name) = 0 OrElse _
       Len(widget_name) > MENUBAR_MAXIMUM_LABEL_BYTES Then Return 0
    If bar_width < MENUBAR_MINIMUM_WIDTH Then _
        bar_width = MENUBAR_MINIMUM_WIDTH

    bar_widget = New Widget
    bar_data = New MenuBarData
    If bar_widget = 0 OrElse bar_data = 0 Then
        Delete bar_data
        Delete bar_widget
        Return 0
    End If
    bar_widget->name = widget_name
    bar_widget->x = left_position
    bar_widget->y = top_position
    bar_widget->w = bar_width
    bar_widget->h = MENUBAR_HEIGHT
    bar_widget->visible = -1
    bar_widget->enabled = -1
    bar_widget->accepts_focus = -1
    bar_widget->captures_return = -1
    bar_widget->captures_escape = -1
    /'
        Menu accelerators must remain available while a textbox or another
        control owns focus. widgets.bas narrows this process-wide input to the
        active modal/form tree and chooses one eligible MenuBar.
    '/
    bar_widget->keyboard_global = -1
    bar_widget->activate = @menubar_Activate
    bar_widget->update = @menubar_Update
    bar_widget->render = @menubar_Render
    bar_widget->destroy = @menubar_Destroy
    bar_widget->cancel_input = @menubar_CancelInput
    bar_widget->data = bar_data
    bar_data->open_menu = -1
    bar_data->hot_menu = -1
    bar_data->hot_item = -1
    bar_data->pointer_menu = -1
    bar_data->pointer_item = -1
    bar_data->pointer_open_menu = -1
    Return bar_widget
End Function


Function menubar_AddMenu( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_text As String _
) As Integer
    Dim As MenuBarData Ptr bar_data
    Dim As Integer menu_index
    Dim As Integer menu_left
    Dim As Integer menu_width
    Dim As String display_text

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return -1
    If Len(menu_text) < 1 OrElse _
       Len(menu_text) > MENUBAR_MAXIMUM_LABEL_BYTES Then Return -1
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If bar_data->menu_count >= MENUBAR_MAX_MENUS Then Return -1

    menu_index = bar_data->menu_count
    display_text = menubar_DisplayText(menu_text)
    menu_width = backend_GetTextWidth(display_text) + MENUBAR_HEADING_PADDING
    If menu_width < MENUBAR_MINIMUM_HEADING_WIDTH Then _
        menu_width = MENUBAR_MINIMUM_HEADING_WIDTH
    If menu_index > 0 Then
        menu_left = bar_data->menu_left(menu_index - 1) + _
            bar_data->menu_width(menu_index - 1)
    End If

    bar_data->menu_labels(menu_index) = menu_text
    bar_data->menu_visible(menu_index) = -1
    bar_data->menu_enabled(menu_index) = -1
    bar_data->menu_left(menu_index) = menu_left
    bar_data->menu_width(menu_index) = menu_width
    bar_data->popup_width(menu_index) = MENUBAR_MINIMUM_POPUP_WIDTH
    bar_data->menu_count += 1
    menubar_RecalculateHeadings(bar_data)
    Return menu_index
End Function


Function menubar_AddItem( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_text As String _
) As Integer
    Dim As MenuBarData Ptr bar_data
    Dim As Integer item_index

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return -1
    If Len(item_text) < 1 OrElse _
       Len(item_text) > MENUBAR_MAXIMUM_LABEL_BYTES Then Return -1
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return -1
    If bar_data->item_count(menu_index) >= MENUBAR_MAX_ITEMS Then Return -1

    item_index = bar_data->item_count(menu_index)
    bar_data->item_labels(menu_index, item_index) = item_text
    bar_data->item_enabled(menu_index, item_index) = -1
    bar_data->item_visible(menu_index, item_index) = -1
    bar_data->item_count(menu_index) += 1
    menubar_RecalculatePopupWidth bar_data, menu_index
    Return item_index
End Function


Sub menubar_SetSelectionHandler( _
    ByVal bar_widget As Widget Ptr, _
    ByVal selection_handler As Any Ptr, _
    ByVal selection_context As Any Ptr _
)
    Dim As MenuBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Exit Sub
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    bar_data->selection_handler = selection_handler
    bar_data->selection_context = selection_context
End Sub


Function menubar_SetOpenMenu( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer _
) As Integer
    Dim As MenuBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < -1 OrElse menu_index >= bar_data->menu_count Then Return 0
    If menu_index >= 0 AndAlso _
       bar_data->menu_popups(menu_index) <> 0 Then
        If menu_GetVisibleItemCount(bar_data->menu_popups(menu_index)) < 1 Then _
            Return 0
    ElseIf menu_index >= 0 AndAlso bar_data->item_count(menu_index) < 1 Then
        Return 0
    End If
    menubar_SetOpenState bar_widget, bar_data, menu_index
    Return -1
End Function


Function menubar_GetOpenMenu( _
    ByVal bar_widget As Widget Ptr _
) As Integer
    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return -1
    Return Cast(MenuBarData Ptr, bar_widget->data)->open_menu
End Function


Function menubar_GetMenuCount( _
    ByVal bar_widget As Widget Ptr _
) As Integer
    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    Return Cast(MenuBarData Ptr, bar_widget->data)->menu_count
End Function


Function menubar_GetItemCount( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer _
) As Integer
    Dim As MenuBarData Ptr bar_data
    Dim As Widget Ptr popup_root

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    ' Attached trees own the popup rows; inline counts remain for legacy menus.
    popup_root = bar_data->menu_popups(menu_index)
    If popup_root <> 0 Then Return menu_GetItemCount(popup_root)
    Return bar_data->item_count(menu_index)
End Function


Function menubar_GetMenuLabel( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer _
) As String
    Dim As MenuBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return ""
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return ""
    Return bar_data->menu_labels(menu_index)
End Function


Function menubar_GetItemLabel( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer _
) As String
    Dim As MenuBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return ""
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return ""
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Return ""
    Return bar_data->item_labels(menu_index, item_index)
End Function


Function menubar_SetItemLabel( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByVal item_text As String _
) As Integer
    Dim As MenuBarData Ptr bar_data
    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    If Len(item_text) < 1 OrElse _
       Len(item_text) > MENUBAR_MAXIMUM_LABEL_BYTES Then Return 0
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Return 0
    bar_data->item_labels(menu_index, item_index) = item_text
    menubar_RecalculatePopupWidth bar_data, menu_index
    If menubar_IsSelectable(bar_data, menu_index, bar_data->hot_item) = 0 Then _
        bar_data->hot_item = menubar_FirstSelectableItem(bar_data, menu_index)
    Return -1
End Function


Function menubar_SetItemVisible( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByVal visible_value As Integer _
) As Integer
    Dim As MenuBarData Ptr bar_data
    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Return 0
    bar_data->item_visible(menu_index, item_index) = _
        IIf(visible_value <> 0, -1, 0)
    menubar_RecalculatePopupWidth bar_data, menu_index
    If menubar_IsSelectable(bar_data, menu_index, bar_data->hot_item) = 0 Then _
        bar_data->hot_item = menubar_FirstSelectableItem(bar_data, menu_index)
    If menubar_VisibleItemCount(bar_data, menu_index) = 0 AndAlso _
       bar_data->open_menu = menu_index Then _
        menubar_SetOpenState bar_widget, bar_data, -1
    Return -1
End Function


Function menubar_GetItemVisible( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer _
) As Integer
    Dim As MenuBarData Ptr bar_data
    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Return 0
    Return bar_data->item_visible(menu_index, item_index)
End Function


Function menubar_SetItemChecked( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByVal checked_value As Integer _
) As Integer
    Dim As MenuBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Return 0
    If menubar_IsSeparator( _
        bar_data->item_labels(menu_index, item_index) _
    ) Then Return 0

    bar_data->item_checked(menu_index, item_index) = _
        IIf(checked_value <> 0, -1, 0)
    Return -1
End Function


Function menubar_GetItemChecked( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer _
) As Integer
    Dim As MenuBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Return 0
    Return bar_data->item_checked(menu_index, item_index)
End Function


Function menubar_SetItemEnabled( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByVal enabled_value As Integer _
) As Integer
    Dim As MenuBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Return 0
    If menubar_IsSeparator( _
        bar_data->item_labels(menu_index, item_index) _
    ) Then Return 0

    bar_data->item_enabled(menu_index, item_index) = _
        IIf(enabled_value <> 0, -1, 0)
    If menu_index = bar_data->open_menu AndAlso _
       item_index = bar_data->hot_item AndAlso enabled_value = 0 Then
        bar_data->hot_item = menubar_MoveSelectableItem( _
            bar_data, menu_index, item_index, 1 _
        )
    End If
    Return -1
End Function


Function menubar_GetItemEnabled( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer _
) As Integer
    Dim As MenuBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Return 0
    Return bar_data->item_enabled(menu_index, item_index)
End Function


Function menubar_SetItemShortcutText( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByVal shortcut_text As String _
) As Integer
    Dim As MenuBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    If Len(shortcut_text) > MENUBAR_MAXIMUM_LABEL_BYTES Then Return 0
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Return 0
    If menubar_IsSeparator( _
        bar_data->item_labels(menu_index, item_index) _
    ) Then Return 0

    bar_data->item_shortcuts(menu_index, item_index) = shortcut_text
    menubar_RecalculatePopupWidth bar_data, menu_index
    Return -1
End Function


Function menubar_GetItemShortcutText( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer _
) As String
    Dim As MenuBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return ""
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return ""
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Return ""
    Return bar_data->item_shortcuts(menu_index, item_index)
End Function

Function menubar_SetItemShortcut( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByVal scan_code As Integer, _
    ByVal modifiers As Integer, _
    ByVal shortcut_text As String _
) As Integer
    Dim As MenuBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    If scan_code < 0 OrElse scan_code > 255 OrElse _
       modifiers < INPUT_MODIFIER_NONE OrElse modifiers > 7 OrElse _
       Len(shortcut_text) > MENUBAR_MAXIMUM_LABEL_BYTES Then Return 0
    If scan_code = 0 AndAlso _
       (modifiers <> INPUT_MODIFIER_NONE OrElse Len(shortcut_text) <> 0) Then _
        Return 0
    If scan_code <> 0 AndAlso Len(shortcut_text) = 0 Then Return 0
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Return 0
    If menubar_IsSeparator( _
        bar_data->item_labels(menu_index, item_index) _
    ) Then Return 0

    bar_data->item_shortcut_scan_codes(menu_index, item_index) = scan_code
    bar_data->item_shortcut_modifiers(menu_index, item_index) = modifiers
    bar_data->item_shortcuts(menu_index, item_index) = shortcut_text
    menubar_RecalculatePopupWidth bar_data, menu_index
    Return -1
End Function


Function menubar_GetItemShortcut( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByRef scan_code As Integer, _
    ByRef modifiers As Integer _
) As Integer
    Dim As MenuBarData Ptr bar_data

    scan_code = 0
    modifiers = INPUT_MODIFIER_NONE
    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Return 0
    scan_code = bar_data->item_shortcut_scan_codes(menu_index, item_index)
    modifiers = bar_data->item_shortcut_modifiers(menu_index, item_index)
    Return IIf(scan_code <> 0, -1, 0)
End Function


' -------------------------------------------------------------------------
' Input and activation
' -------------------------------------------------------------------------

Private Sub menubar_NotifySelection( _
    ByVal bar_widget As Widget Ptr, _
    ByVal bar_data As MenuBarData Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer _
)
    Dim As Any Ptr callback_context
    Dim As Any Ptr callback_handler

    If bar_widget = 0 OrElse bar_data = 0 Then Exit Sub
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Exit Sub
    If item_index < 0 OrElse _
       item_index >= bar_data->item_count(menu_index) Then Exit Sub
    If menubar_IsSelectable(bar_data, menu_index, item_index) = 0 Then Exit Sub

    /'
        Close before application code runs. The callback may remove the bar
        or rebuild its owning window, so no widget storage is touched after
        dispatch.
    '/
    callback_handler = bar_data->selection_handler
    callback_context = bar_data->selection_context
    menubar_SetOpenState bar_widget, bar_data, -1
    If callback_handler <> 0 Then
        Cast( _
            Sub(ByVal As Any Ptr, ByVal As Integer, ByVal As Integer), _
            callback_handler _
        )(callback_context, menu_index, item_index)
    End If
End Sub


Function menubar_ActivateItem( _
    ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer, _
    ByVal item_index As Integer _
) As Integer
    Dim As MenuBarData Ptr bar_data
    If bar_widget = 0 OrElse bar_widget->data = 0 Then Return 0
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Return 0
    If item_index < 0 OrElse item_index >= bar_data->item_count(menu_index) Then Return 0
    If menubar_IsSelectable(bar_data, menu_index, item_index) = 0 Then Return 0
    ' Use the pointer/keyboard route, including closing before callback dispatch.
    menubar_NotifySelection bar_widget, bar_data, menu_index, item_index
    Return -1
End Function


Private Function menubar_ActivateShortcut( _
    ByVal bar_widget As Widget Ptr, _
    ByVal bar_data As MenuBarData Ptr _
) As Integer
    Dim As Integer item_index
    Dim As Integer menu_index
    Dim As Integer shortcut_code

    If bar_widget = 0 OrElse bar_data = 0 Then Return 0
    For menu_index = 0 To bar_data->menu_count - 1
        For item_index = 0 To bar_data->item_count(menu_index) - 1
            shortcut_code = bar_data->item_shortcut_scan_codes( _
                menu_index, item_index _
            )
            If shortcut_code = 0 OrElse _
               menubar_IsSelectable(bar_data, menu_index, item_index) = 0 Then _
                Continue For
            If input_ExactModifiedKeyPressEvent( _
                shortcut_code, _
                bar_data->item_shortcut_modifiers(menu_index, item_index) _
            ) Then
                /'
                    Menu order owns duplicates. Selection is finalized before
                    application code runs, as it is for pointer activation.
                '/
                menubar_NotifySelection _
                    bar_widget, bar_data, menu_index, item_index
                Return -1
            End If
        Next item_index
    Next menu_index
    For menu_index = 0 To bar_data->menu_count - 1
        If menubar_HeadingAvailable(bar_data, menu_index) = 0 OrElse _
           bar_data->menu_popups(menu_index) = 0 Then Continue For
        If menu_ActivateShortcut(bar_data->menu_popups(menu_index)) Then _
            Return -1
    Next menu_index
    Return 0
End Function


Sub menubar_Activate(ByVal bar_widget As Widget Ptr)
    Dim As MenuBarData Ptr bar_data

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Exit Sub
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    If bar_data->open_menu >= 0 Then
        menubar_SetOpenState bar_widget, bar_data, -1
    ElseIf bar_data->menu_count > 0 Then
        menubar_SetOpenState bar_widget, bar_data, menubar_NextHeading(bar_data, -1, 1)
    End If
End Sub


Sub menubar_Update(ByVal bar_widget As Widget Ptr)
    Dim As MenuBarData Ptr bar_data
    Dim As Integer activation_item
    Dim As Integer activation_menu
    Dim As Integer next_menu
    Dim As Integer mnemonic_index
    Dim As Integer mnemonic_key
    Dim As Integer pointer_buttons
    Dim As Integer pointer_item
    Dim As Integer pointer_menu

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Exit Sub
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    pointer_buttons = input_MouseButtons()
    menubar_PointerTarget _
        bar_widget, bar_data, input_MouseX(), input_MouseY(), _
        pointer_menu, pointer_item

    If menubar_ActivateShortcut(bar_widget, bar_data) Then Exit Sub

    /'
        An Alt mnemonic opens its heading even when another control owns
        focus. Duplicate letters retain predictable first-heading ownership.
    '/
    For mnemonic_index = 0 To bar_data->menu_count - 1
        If menubar_HeadingAvailable(bar_data, mnemonic_index) = 0 Then Continue For
        menubar_MnemonicDisplayIndex _
            bar_data->menu_labels(mnemonic_index), mnemonic_key
        If mnemonic_key <> 0 AndAlso _
           input_AltShortcutPressed(mnemonic_key) Then
            menubar_SetOpenState bar_widget, bar_data, mnemonic_index
            Exit Sub
        End If
    Next mnemonic_index

    If bar_data->open_menu >= 0 AndAlso pointer_buttons = 0 Then
        If pointer_menu >= 0 AndAlso pointer_item < 0 AndAlso _
           pointer_menu <> bar_data->open_menu Then
            menubar_SetOpenState bar_widget, bar_data, pointer_menu
        ElseIf pointer_menu = bar_data->open_menu AndAlso pointer_item >= 0 Then
            If menubar_IsSelectable( _
                bar_data, pointer_menu, pointer_item _
            ) = 0 Then
                bar_data->hot_item = -1
            Else
                bar_data->hot_item = pointer_item
            End If
        End If
    ElseIf bar_data->open_menu < 0 Then
        bar_data->hot_menu = pointer_menu
    End If

    If (pointer_buttons And 1) <> 0 Then
        If bar_data->pointer_latch = 0 Then
            bar_data->pointer_latch = -1
            bar_data->pointer_menu = pointer_menu
            bar_data->pointer_item = pointer_item
            bar_data->pointer_open_menu = bar_data->open_menu
        End If
    ElseIf bar_data->pointer_latch <> 0 Then
        activation_menu = -1
        activation_item = -1
        If pointer_menu = bar_data->pointer_menu AndAlso _
           pointer_item = bar_data->pointer_item Then
            If pointer_menu >= 0 AndAlso pointer_item >= 0 Then
                activation_menu = pointer_menu
                activation_item = pointer_item
            ElseIf pointer_menu >= 0 Then
                If bar_data->pointer_open_menu = pointer_menu Then
                    menubar_SetOpenState bar_widget, bar_data, -1
                Else
                    menubar_SetOpenState bar_widget, bar_data, pointer_menu
                End If
            End If
        ElseIf bar_data->open_menu >= 0 Then
            menubar_SetOpenState bar_widget, bar_data, -1
        End If

        bar_data->pointer_latch = 0
        bar_data->pointer_menu = -1
        bar_data->pointer_item = -1
        bar_data->pointer_open_menu = -1
        If activation_menu >= 0 Then
            menubar_NotifySelection _
                bar_widget, bar_data, activation_menu, activation_item
            Exit Sub
        End If
    End If

    If bar_widget->has_focus = 0 Then Exit Sub
    If input_KeyPressEvent(KEY_ESCAPE) <> 0 Then
        menubar_SetOpenState bar_widget, bar_data, -1
        Exit Sub
    End If

    If bar_data->open_menu < 0 Then
        If input_KeyPressEvent(KEY_RETURN) <> 0 OrElse _
           input_KeyPressEvent(FB.SC_SPACE) <> 0 OrElse _
           input_KeyPressEvent(KEY_DOWN) <> 0 Then
            If menubar_HeadingAvailable(bar_data, bar_data->hot_menu) = 0 Then _
                bar_data->hot_menu = menubar_NextHeading(bar_data, -1, 1)
            menubar_SetOpenState _
                bar_widget, bar_data, bar_data->hot_menu
        ElseIf input_KeyPressEvent(KEY_LEFT) <> 0 Then
            bar_data->hot_menu = menubar_NextHeading(bar_data, 0, -1)
        ElseIf input_KeyPressEvent(KEY_RIGHT) <> 0 Then
            bar_data->hot_menu = menubar_NextHeading(bar_data, -1, 1)
        End If
        Exit Sub
    End If

    If input_KeyPressEvent(KEY_LEFT) <> 0 OrElse _
       input_KeyPressEvent(KEY_RIGHT) <> 0 Then
        next_menu = bar_data->open_menu
        If input_KeyPressEvent(KEY_LEFT) <> 0 Then
            next_menu = menubar_NextHeading(bar_data, next_menu, -1)
        Else
            next_menu = menubar_NextHeading(bar_data, next_menu, 1)
        End If
        menubar_SetOpenState bar_widget, bar_data, next_menu
    ElseIf input_KeyPressEvent(KEY_UP) <> 0 Then
        bar_data->hot_item = menubar_MoveSelectableItem( _
            bar_data, bar_data->open_menu, bar_data->hot_item, -1 _
        )
    ElseIf input_KeyPressEvent(KEY_DOWN) <> 0 Then
        bar_data->hot_item = menubar_MoveSelectableItem( _
            bar_data, bar_data->open_menu, bar_data->hot_item, 1 _
        )
    ElseIf input_KeyPressEvent(KEY_HOME) <> 0 Then
        bar_data->hot_item = menubar_FirstSelectableItem( _
            bar_data, bar_data->open_menu _
        )
    ElseIf input_KeyPressEvent(KEY_END) <> 0 Then
        bar_data->hot_item = menubar_LastSelectableItem( _
            bar_data, bar_data->open_menu _
        )
    ElseIf input_KeyPressEvent(KEY_RETURN) <> 0 OrElse _
           input_KeyPressEvent(FB.SC_SPACE) <> 0 Then
        menubar_NotifySelection _
            bar_widget, bar_data, bar_data->open_menu, bar_data->hot_item
    End If
End Sub

' -------------------------------------------------------------------------
' Rendering and lifecycle
' -------------------------------------------------------------------------

Sub menubar_Render(ByVal bar_widget As Widget Ptr)
    Dim As MenuBarData Ptr bar_data
    Dim As Integer item_index
    Dim As Integer menu_index
    Dim As Integer popup_height
    Dim As Integer popup_left
    Dim As Integer popup_top
    Dim As Integer popup_width
    Dim As Integer row_top
    Dim As Integer shortcut_width
    Dim As Integer text_left
    Dim As Integer text_width
    Dim As ULong fill_color
    Dim As ULong text_color
    Dim As String display_text

    If bar_widget = 0 OrElse bar_widget->data = 0 Then Exit Sub
    bar_data = Cast(MenuBarData Ptr, bar_widget->data)
    backend_Rect _
        bar_widget->ax, bar_widget->ay, bar_widget->w, MENUBAR_HEIGHT, _
        theme_GetClassicColor(GUI_CLASSIC_COLOR_MENU_BACKGROUND), -1
    backend_Line _
        bar_widget->ax, bar_widget->ay + MENUBAR_HEIGHT - 1, _
        bar_widget->ax + bar_widget->w - 1, _
        bar_widget->ay + MENUBAR_HEIGHT - 1, _
        theme_GetClassicColor(GUI_CLASSIC_COLOR_ACTIVE_BORDER_TEXT)

    For menu_index = 0 To bar_data->menu_count - 1
        If bar_data->menu_visible(menu_index) = 0 Then Continue For
        If menu_index = bar_data->open_menu OrElse _
           (bar_data->open_menu < 0 AndAlso menu_index = bar_data->hot_menu) Then
            fill_color = theme_GetClassicColor( _
                GUI_CLASSIC_COLOR_MENU_SELECTED_BACKGROUND _
            )
            text_color = theme_GetClassicColor( _
                GUI_CLASSIC_COLOR_MENU_SELECTED_TEXT _
            )
            backend_Rect _
                bar_widget->ax + bar_data->menu_left(menu_index), _
                bar_widget->ay + 1, bar_data->menu_width(menu_index), _
                MENUBAR_HEIGHT - 2, fill_color, -1
        Else
            text_color = theme_GetClassicColor(GUI_CLASSIC_COLOR_MENU_TEXT)
        End If
        If bar_data->menu_enabled(menu_index) = 0 Then text_color = theme_GetClassicColor(GUI_CLASSIC_COLOR_DISABLED_TEXT)
        display_text = menubar_DisplayText(bar_data->menu_labels(menu_index))
        backend_PrintAligned _
            bar_widget->ax + bar_data->menu_left(menu_index), bar_widget->ay, _
            bar_data->menu_width(menu_index), MENUBAR_HEIGHT - 1, _
            text_color, display_text, BACKEND_FONT_DEFAULT, _
            BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE
        text_left = bar_widget->ax + bar_data->menu_left(menu_index) + _
            (bar_data->menu_width(menu_index) - _
                backend_GetTextWidth(display_text)) \ 2
        menubar_RenderMnemonic _
            bar_data->menu_labels(menu_index), text_left, bar_widget->ay, _
            MENUBAR_HEIGHT - 1
    Next menu_index

    menu_index = bar_data->open_menu
    If menu_index < 0 OrElse menu_index >= bar_data->menu_count Then Exit Sub
    If bar_data->menu_popups(menu_index) <> 0 Then Exit Sub
    popup_left = menubar_PopupLeft(bar_widget, bar_data, menu_index)
    popup_top = bar_widget->ay + MENUBAR_HEIGHT
    popup_width = bar_data->popup_width(menu_index)
    popup_height = menubar_PopupHeight(bar_data, menu_index)
    backend_Rect _
        popup_left, popup_top, popup_width, popup_height, _
        theme_GetClassicColor(GUI_CLASSIC_COLOR_MENU_BACKGROUND), -1
    backend_Rect _
        popup_left, popup_top, popup_width, popup_height, _
        theme_GetClassicColor(GUI_CLASSIC_COLOR_ACTIVE_BORDER_TEXT), 0

    Dim As Integer visible_row
    For item_index = 0 To bar_data->item_count(menu_index) - 1
        If bar_data->item_visible(menu_index, item_index) = 0 Then Continue For
        row_top = popup_top + MENUBAR_POPUP_BORDER + _
            visible_row * MENUBAR_ROW_HEIGHT
        If menubar_IsSeparator( _
            bar_data->item_labels(menu_index, item_index) _
        ) Then
            backend_Line _
                popup_left + 6, row_top + MENUBAR_ROW_HEIGHT \ 2, _
                popup_left + popup_width - 7, _
                row_top + MENUBAR_ROW_HEIGHT \ 2, _
                theme_GetClassicColor(GUI_CLASSIC_COLOR_ACTIVE_BORDER_TEXT)
        Else
            If bar_data->item_enabled(menu_index, item_index) = 0 Then
                text_color = theme_GetClassicColor( _
                    GUI_CLASSIC_COLOR_DISABLED_TEXT _
                )
            ElseIf item_index = bar_data->hot_item Then
                fill_color = theme_GetClassicColor( _
                    GUI_CLASSIC_COLOR_MENU_SELECTED_BACKGROUND _
                )
                text_color = theme_GetClassicColor( _
                    GUI_CLASSIC_COLOR_MENU_SELECTED_TEXT _
                )
                backend_Rect _
                    popup_left + MENUBAR_POPUP_BORDER, row_top, _
                    popup_width - MENUBAR_POPUP_BORDER * 2, _
                    MENUBAR_ROW_HEIGHT, fill_color, -1
            Else
                text_color = theme_GetClassicColor( _
                    GUI_CLASSIC_COLOR_MENU_TEXT _
                )
            End If
            display_text = menubar_DisplayText( _
                bar_data->item_labels(menu_index, item_index) _
            )
            If bar_data->item_checked(menu_index, item_index) Then
                /'
                    Two strokes form a check mark without depending on a
                    particular font or an operating-system symbol glyph.
                '/
                backend_Line _
                    popup_left + 6, row_top + 10, _
                    popup_left + 9, row_top + 13, text_color
                backend_Line _
                    popup_left + 9, row_top + 13, _
                    popup_left + 15, row_top + 6, text_color
            End If
            shortcut_width = backend_GetTextWidth( _
                bar_data->item_shortcuts(menu_index, item_index) _
            )
            text_width = popup_width - MENUBAR_CHECK_GUTTER_WIDTH - _
                MENUBAR_POPUP_RIGHT_PADDING
            If shortcut_width > 0 Then _
                text_width -= shortcut_width + MENUBAR_SHORTCUT_GAP
            If text_width < 1 Then text_width = 1
            backend_PrintAligned _
                popup_left + MENUBAR_CHECK_GUTTER_WIDTH, row_top, _
                text_width, _
                MENUBAR_ROW_HEIGHT, text_color, display_text, _
                BACKEND_FONT_DEFAULT, BACKEND_ALIGN_LEFT, BACKEND_ALIGN_MIDDLE
            menubar_RenderMnemonic _
                bar_data->item_labels(menu_index, item_index), _
                popup_left + MENUBAR_CHECK_GUTTER_WIDTH, row_top, _
                MENUBAR_ROW_HEIGHT
            If shortcut_width > 0 Then
                backend_PrintAligned _
                    popup_left + popup_width - _
                        MENUBAR_POPUP_RIGHT_PADDING - shortcut_width, _
                    row_top, shortcut_width, MENUBAR_ROW_HEIGHT, text_color, _
                    bar_data->item_shortcuts(menu_index, item_index), _
                    BACKEND_FONT_DEFAULT, BACKEND_ALIGN_RIGHT, _
                    BACKEND_ALIGN_MIDDLE
            End If
        End If
        visible_row += 1
    Next item_index
End Sub


Sub menubar_Destroy(ByVal bar_widget As Widget Ptr)
    If bar_widget = 0 Then Exit Sub
    If bar_widget->data <> 0 Then _
        Delete Cast(MenuBarData Ptr, bar_widget->data)
    bar_widget->data = 0
End Sub

/' end of menubar.bas '/
