/'
    Project: omaGUI
    ---------------

    File: listbox.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for listbox.

    Purpose:

        Declare the fixed-capacity scrolling list widget used by editor
        catalogs and choice dialogs.

    Responsibilities:

        - define bounded list item, selection, and scroll state
        - retain one pointer press until release or cancellation
        - expose list creation, update, rendering, and item operations
        - expose checked programmatic selection without leaking widget data
        - expose bounded item, single-activation, and double-activation queries
        - retain optional normal client and text colors
        - keep application item values attached to rows during mutations

    This file intentionally does NOT contain:

        - list rendering implementation
        - application-specific filtering or persistence
        - keyboard or mouse backend implementation
'/

#ifndef __LISTBOX_BI__
#define __LISTBOX_BI__

#include once "src/widgets/widgets.bi"

Const LISTBOX_MAX_ITEMS As Integer = 4096
Const LISTBOX_MAX_TEXT_BYTES As Integer = 4194304 ' Total retained item text, excluding descriptors.
Const LISTBOX_SELECTION_SINGLE As Integer = 0
Const LISTBOX_SELECTION_SIMPLE As Integer = 1
Const LISTBOX_SELECTION_EXTENDED As Integer = 2
Const LISTBOX_MAX_COLUMNS As Integer = 32767 ' Bounded signed designer property.
Const LISTBOX_MAX_TABLE_COLUMNS As Integer = 4

Type ListBoxData
    As String items(0 To LISTBOX_MAX_ITEMS - 1)
    As Integer item_count
    As Integer selected_index
    As Integer scroll_top
    As Integer key_latch
    As Integer pointer_latch
    As Integer pointer_index
    As ULongInt activation_count
    As ULongInt double_activation_count
    As Integer double_click_armed
    As Integer double_click_index
    As Double double_click_clock
    As Widget Ptr scrollbar
    As Integer background_color_override
    As ULong background_color
    As Integer foreground_color_override
    As ULong foreground_color
    As Integer border_color_override
    As ULong border_color
    As Integer selected_background_color_override
    As ULong selected_background_color
    As Integer selected_foreground_color_override
    As ULong selected_foreground_color
    As Integer right_column_offset
    ' Opaque signed values, not owned pointers. LongInt keeps the same range
    ' on 32-bit and 64-bit targets. New rows start at zero.
    As LongInt item_data(0 To LISTBOX_MAX_ITEMS - 1)
    ' Appended state keeps earlier field offsets intact. In multiple selection
    ' selected_index is the caret; selection belongs to each retained row.
    As Integer selection_mode, selection_anchor
    As UByte selected_rows(0 To LISTBOX_MAX_ITEMS - 1)
    As ULongInt selection_change_count
    As Integer pointer_shift, pointer_control
    As Integer column_count
    ' Editor list styles are independent of the local multi-column flow mode.
    As Integer row_height, text_inset, navigation_style
    As Integer table_column_count
    As Integer table_column_widths(0 To LISTBOX_MAX_TABLE_COLUMNS - 1)
    As String table_column_titles(0 To LISTBOX_MAX_TABLE_COLUMNS - 1)
    As Integer dropdown_style, checklist_style
    As Widget Ptr dropdown_popup
    As UByte checked_items(0 To LISTBOX_MAX_ITEMS - 1)
End Type

' Zero retains the vertical list. Positive counts divide its width into
' columns filled from top to bottom, with a horizontal scrollbar underneath.
' Geometry smaller than the request uses at least one pixel per column.
Declare Function listbox_SetColumnCount(ByVal w As Widget Ptr, ByVal column_count As Integer) As Integer
Declare Function listbox_GetColumnCount(ByVal w As Widget Ptr) As Integer

' GUI-thread APIs. Programmatic changes never increment activation counters.
' SetSelectedIndex moves only the caret in multiple-selection modes; -1 clears
' all selection. SetItemSelected preserves the caret and viewport in those modes.
' GetItemSelected returns status separately from the normalized selected value.
Declare Function listbox_SetSelectionMode(ByVal w As Widget Ptr, ByVal mode_value As Integer) As Integer
Declare Function listbox_GetSelectionMode(ByVal w As Widget Ptr) As Integer
Declare Function listbox_SetItemSelected(ByVal w As Widget Ptr, ByVal item_index As Integer, ByVal selected_value As Integer) As Integer
Declare Function listbox_GetItemSelected(ByVal w As Widget Ptr, ByVal item_index As Integer, ByRef selected_value As Integer) As Integer
Declare Function listbox_GetSelectedCount(ByVal w As Widget Ptr) As Integer
' An invalidation token, not an event count. Row insertion/removal, clear and
' mode changes also invalidate indexed selection observations. Compare for
' inequality and refresh after application-owned mutations without firing input.
Declare Function listbox_GetSelectionChangeCount(ByVal w As Widget Ptr) As ULongInt

Declare Function listbox_Create(ByVal nm As String, ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer) As Widget Ptr
Declare Sub listbox_Render(ByVal w As Widget Ptr)
Declare Sub listbox_Update(ByVal w As Widget Ptr)
Declare Sub listbox_Destroy(ByVal w As Widget Ptr)
Declare Sub listbox_AddItem(ByVal w As Widget Ptr, ByVal lbl As String)
Declare Function listbox_InsertItem( _
    ByVal w As Widget Ptr, ByRef item_text As Const String, ByVal item_index As Integer = -1 _
) As Integer
Declare Function listbox_RemoveItem(ByVal w As Widget Ptr, ByVal item_index As Integer) As Integer
Declare Function listbox_GetItem( _
    ByVal w As Widget Ptr, ByVal item_index As Integer, ByRef item_text As String _
) As Integer
Declare Sub listbox_Clear(ByVal w As Widget Ptr)
Declare Sub listbox_SetNavigationStyle(ByVal w As Widget Ptr)
Declare Sub listbox_SetRowHeight(ByVal w As Widget Ptr, ByVal rowHeight As Integer)
Declare Sub listbox_SetTextInset(ByVal w As Widget Ptr, ByVal inset As Integer)
Declare Sub listbox_SetColumn( _
    ByVal w As Widget Ptr, ByVal columnIndex As Integer, _
    ByVal title As String, ByVal columnWidth As Integer _
)
Declare Sub listbox_SetDropdownStyle(ByVal w As Widget Ptr)
Declare Sub listbox_SetChecklistStyle(ByVal w As Widget Ptr)
Declare Sub listbox_SetChecked(ByVal w As Widget Ptr, ByVal itemIndex As Integer, ByVal isChecked As Integer)
Declare Function listbox_IsChecked(ByVal w As Widget Ptr, ByVal itemIndex As Integer) As Integer
Declare Sub listbox_SetScrollbarColors( _
    ByVal w As Widget Ptr, ByVal trackColor As ULong, _
    ByVal thumbColor As ULong, ByVal thumbBorderColor As ULong _
)
' Item operations run on the GUI thread and do not notify selection handlers.
' SetItem preserves selection, scroll and item data; failed writes change none.
Declare Function listbox_SetItem( _
    ByVal w As Widget Ptr, ByVal item_index As Integer, ByRef item_text As Const String _
) As Integer
Declare Function listbox_SetItemData( _
    ByVal w As Widget Ptr, ByVal item_index As Integer, ByVal data_value As LongInt _
) As Integer
' GetItemData returns zero in data_value on failure, distinguished by its status.
Declare Function listbox_GetItemData( _
    ByVal w As Widget Ptr, ByVal item_index As Integer, ByRef data_value As LongInt _
) As Integer
' TopIndex uses zero-based rows. Set requires an existing row and clamps to
' the last full page without changing selection; Get returns -1 for no widget.
' In column mode it aligns to the first row of the leftmost visible column.
Declare Function listbox_SetTopIndex(ByVal w As Widget Ptr, ByVal item_index As Integer) As Integer
Declare Function listbox_GetTopIndex(ByVal w As Widget Ptr) As Integer
Declare Function listbox_GetSelectedIndex(ByVal w As Widget Ptr) As Integer
Declare Function listbox_GetSelectedItem(ByVal w As Widget Ptr) As String
Declare Function listbox_GetItemCount(ByVal w As Widget Ptr) As Integer
Declare Function listbox_GetActivationCount(ByVal w As Widget Ptr) As ULongInt
Declare Function listbox_GetDoubleActivationCount(ByVal w As Widget Ptr) As ULongInt
Declare Function listbox_ActivateSelected(ByVal w As Widget Ptr) As Integer
Declare Function listbox_DoubleActivateSelected(ByVal w As Widget Ptr) As Integer
Declare Function listbox_SetSelectedIndex( _
    ByVal w As Widget Ptr, _
    ByVal selectedIndex As Integer _
) As Integer
Declare Function listbox_SetBackgroundColor( _
    ByVal w As Widget Ptr, _
    ByVal color_value As ULong _
) As Integer
Declare Function listbox_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
Declare Function listbox_GetBackgroundColor( _
    ByVal w As Widget Ptr, _
    ByRef color_value As ULong _
) As Integer
Declare Function listbox_SetForegroundColor( _
    ByVal w As Widget Ptr, _
    ByVal color_value As ULong _
) As Integer
Declare Function listbox_ClearForegroundColor(ByVal w As Widget Ptr) As Integer
Declare Function listbox_GetForegroundColor( _
    ByVal w As Widget Ptr, _
    ByRef color_value As ULong _
) As Integer

' SetColors retains TurboTrek's existing five-role list presentation API.
' The more granular background and foreground calls remain available.
Declare Sub listbox_SetColors( _
    ByVal w As Widget Ptr, _
    ByVal background_color As ULong, ByVal border_color As ULong, _
    ByVal foreground_color As ULong, _
    ByVal selected_background_color As ULong, _
    ByVal selected_foreground_color As ULong _
)
' A non-negative offset aligns the text after the first tab in a row. This is
' used for compact name/value lists without creating a second widget column.
Declare Function listbox_SetRightColumn( _
    ByVal w As Widget Ptr, ByVal column_offset As Integer _
) As Integer

#endif

/' end of listbox.bi '/
