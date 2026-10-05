/'
    Project: omaGUI
    ---------------

    File: menu.bi

    Purpose:

        Declare a bounded popup menu used directly and by imported dropdowns.

    Responsibilities:

        - retain menu labels, hover selection, and callbacks
        - support item separators and per-item callbacks
        - own nested popup trees with mouse and keyboard navigation
        - support per-item visibility, checked state, and keyboard shortcuts
        - support configurable item height and one context-aware handler
        - retain shared insets for drawing, placement, and pointer rows
        - expose item reset for reusable generated popups

    This file intentionally does NOT contain:

        - application command policy
        - imported-control ownership rules
        - global pointer-routing policy
'/

#ifndef __MENU_BI__
#define __MENU_BI__

#include once "src/widgets/widgets.bi"

Const MENU_MAX_ITEMS As Integer = 64
Const MENU_ITEM_KIND_NORMAL As Integer = 0
Const MENU_ITEM_KIND_SEPARATOR As Integer = 1
Const MENU_MAX_NESTING As Integer = 32

Type MenuData
    As String items(0 To MENU_MAX_ITEMS - 1)
    As Sub(ByVal As Integer) callbacks(0 To MENU_MAX_ITEMS - 1)
    As Integer item_kinds(0 To MENU_MAX_ITEMS - 1)
    As String shortcuts(0 To MENU_MAX_ITEMS - 1)
    As Integer shortcut_scan_codes(0 To MENU_MAX_ITEMS - 1)
    As Integer shortcut_modifiers(0 To MENU_MAX_ITEMS - 1)
    As Integer item_enabled(0 To MENU_MAX_ITEMS - 1)
    As Integer item_visible(0 To MENU_MAX_ITEMS - 1)
    As Integer item_checked(0 To MENU_MAX_ITEMS - 1)
    As Integer item_submenu(0 To MENU_MAX_ITEMS - 1)
    As Integer details_style
    As Integer command_ids(0 To MENU_MAX_ITEMS - 1)
    As Widget Ptr submenus(0 To MENU_MAX_ITEMS - 1)
    As Widget Ptr parent_menu
    As Widget Ptr restore_focus
    As Widget Ptr pointer_menu, hover_menu, menubar_owner
    As Integer hover_index
    As Double hover_clock
    As Integer open_submenu, scroll_top, visible_rows
    As Integer cascade_side
    As Integer keyboard_handled
    As Integer last_pointer_x, last_pointer_y
    As Any Ptr menubar_handler, menubar_context
    As Integer count, selected
    As Integer item_height
    ' Insets are shared by sizing, drawing, pointer rows, and submenu placement.
    As Integer vertical_inset, caption_inset, shortcut_inset, separator_inset
    ' Optional caption adjustment leaves the item hit areas and highlight fixed.
    As Integer text_y_offset
    /'
        Pointer activation is latched at press and published once on a
        matching release. Without these fields a held mouse button invokes
        the item callback on every GUI frame and can walk through generated
        menus before the user can react.
    '/
    As Integer pointer_latch, pointer_index
    As Any Ptr selection_handler, selection_context
End Type

Declare Function menu_Create( _
    ByVal nm As String, ByVal x As Integer, ByVal y As Integer _
) As Widget Ptr
Declare Sub menu_AddItem( _
    ByVal m As Widget Ptr, ByVal txt As String, _
    ByVal cb As Sub(ByVal As Integer) _
)
Declare Sub menu_AddSeparator(ByVal m As Widget Ptr)
Declare Sub menu_AddCommand(ByVal m As Widget Ptr, ByVal text As String, ByVal commandId As Integer)
/'
    Attaching transfers submenu lifetime to the parent widget tree. Add the
    root to the GUI registry, then use gui_RemoveWidget or menu_ClearItems to
    destroy the tree. Do not separately destroy an attached submenu.
'/
Declare Function menu_SetSubmenu(ByVal m As Widget Ptr, ByVal itemIndex As Integer, ByVal submenuWidget As Widget Ptr) As Integer
Declare Function menu_AddSubmenu(ByVal m As Widget Ptr, ByVal text As String, ByVal submenuWidget As Widget Ptr) As Integer
Declare Function menu_OpenSubmenu(ByVal m As Widget Ptr, ByVal itemIndex As Integer, ByVal selectFirst As Integer = 0) As Integer
Declare Sub menu_ShowAt(ByVal m As Widget Ptr, ByVal x As Integer, ByVal y As Integer, ByVal selectFirst As Integer = 0)
Declare Sub menu_CloseTree(ByVal m As Widget Ptr)
Declare Function menu_GetRoot(ByVal m As Widget Ptr) As Widget Ptr
Declare Function menu_GetOpenLeaf(ByVal m As Widget Ptr) As Widget Ptr
Declare Sub menu_SetMenuBarHandler(ByVal m As Widget Ptr, ByVal handler As Any Ptr, ByVal context As Any Ptr = 0)
Declare Sub menu_SetMenuBarOwner(ByVal m As Widget Ptr, ByVal owner As Widget Ptr)
Declare Function menu_GetItemCount(ByVal m As Widget Ptr) As Integer
Declare Function menu_GetVisibleItemCount(ByVal m As Widget Ptr) As Integer
Declare Function menu_GetItemVisible(ByVal m As Widget Ptr, ByVal itemIndex As Integer) As Integer
Declare Function menu_SetItemVisible(ByVal m As Widget Ptr, ByVal itemIndex As Integer, ByVal visibleValue As Integer) As Integer
Declare Function menu_SetItemLabel(ByVal m As Widget Ptr, ByVal itemIndex As Integer, ByVal itemText As String) As Integer
Declare Function menu_SetItemEnabled(ByVal m As Widget Ptr, ByVal itemIndex As Integer, ByVal enabledValue As Integer) As Integer
Declare Function menu_SetItemChecked(ByVal m As Widget Ptr, ByVal itemIndex As Integer, ByVal checkedValue As Integer) As Integer
Declare Function menu_SetItemShortcut( _
    ByVal m As Widget Ptr, ByVal itemIndex As Integer, _
    ByVal scanCode As Integer, ByVal modifiers As Integer, _
    ByVal shortcutText As String _
) As Integer
Declare Function menu_ActivateItem(ByVal m As Widget Ptr, ByVal itemIndex As Integer) As Integer
Declare Function menu_ActivateShortcut(ByVal m As Widget Ptr) As Integer
Declare Function menu_TakeKeyboardHandled(ByVal m As Widget Ptr) As Integer
Declare Sub menu_ClearItems(ByVal m As Widget Ptr)
Declare Sub menu_SetItemDetails( _
    ByVal m As Widget Ptr, ByVal itemIndex As Integer, _
    ByVal shortcutText As String, ByVal isEnabled As Integer = -1, _
    ByVal isChecked As Integer = 0, ByVal hasSubmenu As Integer = 0 _
)
Declare Sub menu_SetItemHeight( _
    ByVal m As Widget Ptr, _
    ByVal itemHeight As Integer _
)
Declare Sub menu_SetInsets( _
    ByVal m As Widget Ptr, ByVal verticalInset As Integer, _
    ByVal captionInset As Integer, ByVal shortcutInset As Integer, _
    ByVal separatorInset As Integer _
)
Declare Function menu_SetTextYOffset( _
    ByVal m As Widget Ptr, ByVal offsetPixels As Integer _
) As Integer
Declare Sub menu_SetSelectionHandler( _
    ByVal m As Widget Ptr, _
    ByVal selection_handler As Any Ptr, _
    ByVal selection_context As Any Ptr _
)
Declare Sub menu_Render(ByVal w As Widget Ptr)
Declare Sub menu_Update(ByVal w As Widget Ptr)
Declare Sub menu_CancelInput(ByVal w As Widget Ptr)
Declare Sub menu_Destroy(ByVal w As Widget Ptr)

#endif

/' end of menu.bi '/
