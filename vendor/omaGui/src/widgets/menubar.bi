/'
    Project: omaGUI
    ---------------

    File: menubar.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for menubar.

    Purpose:

        Declare a portable Windows-style menu bar with bounded drop-downs.

    Responsibilities:

        - retain top-level headings and their child commands
        - render one active drop-down without a platform-native menu API
        - optionally attach a bounded nested popup tree to each heading
        - support pointer, keyboard, separator, and callback behavior
        - expose mutable labels, visibility, checked, enabled, and shortcuts

    This file intentionally does NOT contain:

        - application command policy
        - recursive submenu storage
        - operating-system window or menu declarations
'/

#ifndef __MENUBAR_BI__
#define __MENUBAR_BI__

#include once "src/widgets/widgets.bi"

Const MENUBAR_MAX_MENUS As Integer = 16
Const MENUBAR_MAX_ITEMS As Integer = 32

Type MenuBarData
    As String menu_labels(0 To MENUBAR_MAX_MENUS - 1)
    ' MenuBar owns attached popup roots through the GUI widget tree.
    As Widget Ptr menu_popups(0 To MENUBAR_MAX_MENUS - 1)
    As Integer menu_left(0 To MENUBAR_MAX_MENUS - 1)
    As Integer menu_width(0 To MENUBAR_MAX_MENUS - 1)
    As String item_labels( _
        0 To MENUBAR_MAX_MENUS - 1, _
        0 To MENUBAR_MAX_ITEMS - 1 _
    )
    As Integer item_checked( _
        0 To MENUBAR_MAX_MENUS - 1, _
        0 To MENUBAR_MAX_ITEMS - 1 _
    )
    As Integer item_enabled( _
        0 To MENUBAR_MAX_MENUS - 1, _
        0 To MENUBAR_MAX_ITEMS - 1 _
    )
    As Integer item_visible( _
        0 To MENUBAR_MAX_MENUS - 1, _
        0 To MENUBAR_MAX_ITEMS - 1 _
    )
    As String item_shortcuts( _
        0 To MENUBAR_MAX_MENUS - 1, _
        0 To MENUBAR_MAX_ITEMS - 1 _
    )
    ' A zero scan code intentionally represents a presentation-only hint.
    As Integer item_shortcut_scan_codes( _
        0 To MENUBAR_MAX_MENUS - 1, _
        0 To MENUBAR_MAX_ITEMS - 1 _
    )
    As Integer item_shortcut_modifiers( _
        0 To MENUBAR_MAX_MENUS - 1, _
        0 To MENUBAR_MAX_ITEMS - 1 _
    )
    As Integer item_count(0 To MENUBAR_MAX_MENUS - 1)
    As Integer popup_width(0 To MENUBAR_MAX_MENUS - 1)
    As Integer menu_count
    As Integer open_menu
    As Integer hot_menu
    As Integer hot_item
    As Integer pointer_latch
    As Integer pointer_menu
    As Integer pointer_item
    As Integer pointer_open_menu
    As Any Ptr selection_handler
    As Any Ptr selection_context
    ' Heading state is independent of the saved state of its child commands.
    As Integer menu_enabled(0 To MENUBAR_MAX_MENUS - 1)
    As Integer menu_visible(0 To MENUBAR_MAX_MENUS - 1)
End Type

Declare Function menubar_SetMenuLabel( _
    ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer, _
    ByVal menu_text As String _
) As Integer
Declare Function menubar_SetMenuVisible( _
    ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer, _
    ByVal visible_value As Integer _
) As Integer
Declare Function menubar_GetMenuVisible( _
    ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer _
) As Integer
Declare Function menubar_SetMenuEnabled( _
    ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer, _
    ByVal enabled_value As Integer _
) As Integer
Declare Function menubar_GetMenuEnabled( _
    ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer _
) As Integer
Declare Sub menubar_CancelInput(ByVal bar_widget As Widget Ptr)

Declare Function menubar_Create( _
    ByVal widget_name As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal bar_width As Integer _
) As Widget Ptr
Declare Function menubar_AddMenu( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_text As String _
) As Integer
/'
    Attaching transfers popup lifetime to the MenuBar widget tree. The root
    must be a detached Menu widget; nested descendants are owned by that root.
'/
Declare Function menubar_SetMenuPopup( _
    ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer, _
    ByVal popup_root As Widget Ptr _
) As Integer
Declare Function menubar_GetMenuPopup( _
    ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer _
) As Widget Ptr
Declare Function menubar_AddItem( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_text As String _
) As Integer
Declare Sub menubar_SetSelectionHandler( _
    ByVal bar_widget As Widget Ptr, _
    ByVal selection_handler As Any Ptr, _
    ByVal selection_context As Any Ptr _
)
Declare Function menubar_SetOpenMenu( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer _
) As Integer
Declare Function menubar_GetOpenMenu( _
    ByVal bar_widget As Widget Ptr _
) As Integer
Declare Function menubar_GetMenuCount( _
    ByVal bar_widget As Widget Ptr _
) As Integer
Declare Function menubar_GetItemCount( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer _
) As Integer
Declare Function menubar_GetMenuLabel( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer _
) As String
Declare Function menubar_GetItemLabel( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer _
) As String
Declare Function menubar_SetItemLabel( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByVal item_text As String _
) As Integer
Declare Function menubar_SetItemVisible( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByVal visible_value As Integer _
) As Integer
Declare Function menubar_GetItemVisible( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer _
) As Integer
Declare Function menubar_SetItemChecked( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByVal checked_value As Integer _
) As Integer
Declare Function menubar_GetItemChecked( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer _
) As Integer
Declare Function menubar_SetItemEnabled( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByVal enabled_value As Integer _
) As Integer
Declare Function menubar_GetItemEnabled( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer _
) As Integer
Declare Function menubar_SetItemShortcutText( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByVal shortcut_text As String _
) As Integer
Declare Function menubar_GetItemShortcutText( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer _
) As String
' Bind one exact gfxlib scan-code chord and its visible hint. A zero scan code
' with no modifiers and an empty hint clears a prior binding. The MenuBar owns
' dispatch through omaGUI's active form scope; no host menu API is involved.
Declare Function menubar_SetItemShortcut( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByVal scan_code As Integer, _
    ByVal modifiers As Integer, _
    ByVal shortcut_text As String _
) As Integer
Declare Function menubar_GetItemShortcut( _
    ByVal bar_widget As Widget Ptr, _
    ByVal menu_index As Integer, _
    ByVal item_index As Integer, _
    ByRef scan_code As Integer, _
    ByRef modifiers As Integer _
) As Integer
Declare Sub menubar_Activate(ByVal bar_widget As Widget Ptr)
Declare Function menubar_ActivateItem( _
    ByVal bar_widget As Widget Ptr, ByVal menu_index As Integer, _
    ByVal item_index As Integer _
) As Integer
Declare Sub menubar_Update(ByVal bar_widget As Widget Ptr)
Declare Sub menubar_Render(ByVal bar_widget As Widget Ptr)
Declare Sub menubar_Destroy(ByVal bar_widget As Widget Ptr)

#endif

/' end of menubar.bi '/
