/'
    Project: omaGUI
    ---------------

    File: toolbar.bi

    Purpose:

        Declare a portable classic command toolbar.

    Responsibilities:

        - retain a bounded row of text commands and separators
        - expose checked enabled-state and metadata access
        - dispatch one shared callback after release-inside activation

    This file intentionally does NOT contain:

        - application command policy
        - image resource loading
        - platform-native toolbar declarations
'/

#ifndef __TOOLBAR_BI__
#define __TOOLBAR_BI__

#include once "src/widgets/widgets.bi"

Const TOOLBAR_MAX_ITEMS As Integer = 32
Const TOOLBAR_MAX_TEXT_BYTES As Integer = 160
Const TOOLBAR_ITEM_BUTTON As Integer = 1
Const TOOLBAR_ITEM_SEPARATOR As Integer = 2

Type ToolBarData
    As String item_text(0 To TOOLBAR_MAX_ITEMS - 1)
    As Integer item_kind(0 To TOOLBAR_MAX_ITEMS - 1)
    As Integer item_left(0 To TOOLBAR_MAX_ITEMS - 1)
    As Integer item_width(0 To TOOLBAR_MAX_ITEMS - 1)
    As Integer item_enabled(0 To TOOLBAR_MAX_ITEMS - 1)
    As Integer item_count
    As Integer hot_item
    As Integer pressed_item
    As Integer pointer_latch
    As Any Ptr selection_handler
    As Any Ptr selection_context
End Type

Declare Function toolbar_Create( _
    ByVal widget_name As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal bar_width As Integer, _
    ByVal bar_height As Integer = 34 _
) As Widget Ptr
Declare Function toolbar_AddButton( _
    ByVal bar_widget As Widget Ptr, _
    ByVal button_text As String, _
    ByVal button_width As Integer = 0 _
) As Integer
Declare Function toolbar_AddSeparator( _
    ByVal bar_widget As Widget Ptr _
) As Integer
Declare Sub toolbar_SetSelectionHandler( _
    ByVal bar_widget As Widget Ptr, _
    ByVal selection_handler As Any Ptr, _
    ByVal selection_context As Any Ptr _
)
Declare Function toolbar_SetItemEnabled( _
    ByVal bar_widget As Widget Ptr, _
    ByVal item_index As Integer, _
    ByVal enabled_value As Integer _
) As Integer
Declare Function toolbar_GetItemEnabled( _
    ByVal bar_widget As Widget Ptr, _
    ByVal item_index As Integer _
) As Integer
Declare Function toolbar_GetItemCount( _
    ByVal bar_widget As Widget Ptr _
) As Integer
Declare Function toolbar_GetItemLabel( _
    ByVal bar_widget As Widget Ptr, _
    ByVal item_index As Integer _
) As String
Declare Function toolbar_ActivateItem( _
    ByVal bar_widget As Widget Ptr, _
    ByVal item_index As Integer _
) As Integer
Declare Sub toolbar_Update(ByVal bar_widget As Widget Ptr)
Declare Sub toolbar_Render(ByVal bar_widget As Widget Ptr)
Declare Sub toolbar_Destroy(ByVal bar_widget As Widget Ptr)

#endif

/' end of toolbar.bi '/
