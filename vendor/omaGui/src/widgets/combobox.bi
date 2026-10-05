/'
    Project: omaGUI
    ---------------

    File: combobox.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for combobox.

    Purpose:

        Declare a bounded classic ComboBox with DropDown and Simple layouts.

    Responsibilities:

        - retain a fixed-capacity item list, selected index, and optional text
        - expose checked list, selection, and open-state operations
        - provide pointer, keyboard, and type-ahead selection
        - support editable drop-down, editable Simple, and fixed-list styles
        - expose user activity without conflating it with programmatic state
        - retain optional normal client and text colors
        - keep application item values attached to rows during mutations

    This file intentionally does NOT contain:

        - editable text autocomplete
        - application-specific item loading
        - platform-native control calls
'/

#ifndef __COMBOBOX_BI__
#define __COMBOBOX_BI__

#include once "src/widgets/widgets.bi"

Const COMBOBOX_MAX_ITEMS As Integer = 256
Const COMBOBOX_MAX_VISIBLE_ROWS As Integer = 16
Const COMBOBOX_MAX_TEXT_BYTES As Integer = 4194304 ' Total retained item text.

Type ComboBoxData
    As String items(0 To COMBOBOX_MAX_ITEMS - 1)
    As Integer item_count
    As Integer selected_index
    As Integer pending_index
    As Integer scroll_top
    As Integer maximum_rows
    As Integer is_open
    As Integer pointer_latch
    As Integer pointer_target
    As ULongInt change_count
    As Any Ptr change_handler
    As Integer background_color_override
    As ULong background_color
    As Integer foreground_color_override
    As ULong foreground_color
    As ULongInt activation_count
    ' Hosts poll this count to distinguish user-opened popups from SetOpen.
    As ULongInt dropdown_count
    ' Opaque signed values, not owned pointers. LongInt keeps the same range
    ' on 32-bit and 64-bit targets. New rows start at zero.
    As LongInt item_data(0 To COMBOBOX_MAX_ITEMS - 1)
    ' Editable mode retains independent user text. Its selected index remains
    ' -1 until the text exactly matches a retained list row.
    As Integer editable
    ' Simple mode keeps the edit field above an always-visible bounded list.
    As Integer simple_mode
    As String edit_text
    As Integer edit_cursor
    ' Choice-only controls retain a bounded incremental prefix for keyboard
    ' type-ahead. The clock is Timer seconds since midnight, like other widgets.
    As String type_ahead_text
    As Double type_ahead_clock
    As Integer type_ahead_clock_initialized
End Type

Declare Function combobox_Create( _
    ByVal widget_name As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal combo_width As Integer, _
    ByVal combo_height As Integer, _
    ByVal maximum_rows As Integer = 6, _
    ByVal change_handler As Any Ptr = 0 _
) As Widget Ptr
Declare Sub combobox_Render(ByVal combo_widget As Widget Ptr)
Declare Sub combobox_Update(ByVal combo_widget As Widget Ptr)
Declare Sub combobox_Activate(ByVal combo_widget As Widget Ptr)
Declare Sub combobox_Destroy(ByVal combo_widget As Widget Ptr)
Declare Sub combobox_CancelInput(ByVal combo_widget As Widget Ptr)
Declare Function combobox_AddItem( _
    ByVal combo_widget As Widget Ptr, _
    ByRef item_text As Const String _
) As Integer
Declare Function combobox_InsertItem( _
    ByVal combo_widget As Widget Ptr, ByRef item_text As Const String, _
    ByVal item_index As Integer = -1 _
) As Integer
Declare Function combobox_RemoveItem(ByVal combo_widget As Widget Ptr, ByVal item_index As Integer) As Integer
Declare Function combobox_GetItem( _
    ByVal combo_widget As Widget Ptr, ByVal item_index As Integer, ByRef item_text As String _
) As Integer
Declare Function combobox_GetItemCount(ByVal combo_widget As Widget Ptr) As Integer
Declare Function combobox_GetActivationCount(ByVal combo_widget As Widget Ptr) As ULongInt
Declare Function combobox_GetDropDownCount(ByVal combo_widget As Widget Ptr) As ULongInt
Declare Sub combobox_Clear(ByVal combo_widget As Widget Ptr)
' GUI-thread item writes never invoke a selection callback. SetItem preserves
' selection, pending row, scroll, popup state and item data; failed writes
' change none. A successful replacement cancels a pending pointer gesture.
Declare Function combobox_SetItem( _
    ByVal combo_widget As Widget Ptr, ByVal item_index As Integer, ByRef item_text As Const String _
) As Integer
Declare Function combobox_SetItemData( _
    ByVal combo_widget As Widget Ptr, ByVal item_index As Integer, ByVal data_value As LongInt _
) As Integer
' GetItemData returns zero in data_value on failure, distinguished by its status.
Declare Function combobox_GetItemData( _
    ByVal combo_widget As Widget Ptr, ByVal item_index As Integer, ByRef data_value As LongInt _
) As Integer
Declare Function combobox_GetSelectedIndex( _
    ByVal combo_widget As Widget Ptr _
) As Integer
Declare Function combobox_GetSelectedItem( _
    ByVal combo_widget As Widget Ptr _
) As String
Declare Function combobox_SetSelectedIndex( _
    ByVal combo_widget As Widget Ptr, _
    ByVal selected_index As Integer _
) As Integer
Declare Function combobox_SetOpen( _
    ByVal combo_widget As Widget Ptr, _
    ByVal open_state As Integer _
) As Integer
Declare Function combobox_IsOpen( _
    ByVal combo_widget As Widget Ptr _
) As Integer
' Editable mode remains opt-in so existing choice-only ComboBoxes retain their
' original keyboard and Text behavior. Changing the mode does not alter rows.
Declare Function combobox_SetEditable( _
    ByVal combo_widget As Widget Ptr, _
    ByVal editable_state As Integer _
) As Integer
Declare Function combobox_SetStyle( _
    ByVal combo_widget As Widget Ptr, _
    ByVal style_value As Integer _
) As Integer
Declare Function combobox_GetStyle( _
    ByVal combo_widget As Widget Ptr _
) As Integer
Declare Function combobox_IsEditable( _
    ByVal combo_widget As Widget Ptr _
) As Integer
' Text is the selected row for a choice-only ComboBox and independently typed
' content for an editable ComboBox. Programmatic writes never invoke handlers.
Declare Function combobox_GetText( _
    ByVal combo_widget As Widget Ptr _
) As String
Declare Function combobox_SetText( _
    ByVal combo_widget As Widget Ptr, _
    ByRef text_value As Const String _
) As Integer
Declare Function combobox_SetBackgroundColor( _
    ByVal combo_widget As Widget Ptr, _
    ByVal color_value As ULong _
) As Integer
Declare Function combobox_ClearBackgroundColor( _
    ByVal combo_widget As Widget Ptr _
) As Integer
Declare Function combobox_GetBackgroundColor( _
    ByVal combo_widget As Widget Ptr, _
    ByRef color_value As ULong _
) As Integer
Declare Function combobox_SetForegroundColor( _
    ByVal combo_widget As Widget Ptr, _
    ByVal color_value As ULong _
) As Integer
Declare Function combobox_ClearForegroundColor( _
    ByVal combo_widget As Widget Ptr _
) As Integer
Declare Function combobox_GetForegroundColor( _
    ByVal combo_widget As Widget Ptr, _
    ByRef color_value As ULong _
) As Integer

#endif

/' end of combobox.bi '/
