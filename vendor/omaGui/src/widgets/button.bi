/'
    Project: omaGUI
    ---------------

    File: button.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for button.

    Purpose:

        Declare the classic push-button widget.

    Responsibilities:

        - retain the button label and pointer state
        - expose checked label replacement and retrieval
        - retain an optional caller-supplied face color
        - expose pointer, keyboard, mnemonic, and polled activation

    This file intentionally does NOT contain:

        - button rendering implementation
        - global focus or pointer-routing policy
        - application command handling
'/

#ifndef __BUTTON_BI__
#define __BUTTON_BI__

#include once "src/widgets/widgets.bi"

Type ButtonData
    As String text
    As Integer pressed, state
    As Integer flatStyle, selected
    As Integer default_button, arrow_direction
    As ULong normalForeground, normalBackground
    As ULong hotForeground, hotBackground
    As ULong selectedForeground, selectedBackground
    As Integer background_color_override
    As ULong background_color
    As Any Ptr clickHandler
    ' The Enter-key default action may omit its classic inner outline.
    As Integer default_outline_visible
End Type

Declare Function button_Create( _
    ByVal nm As String, ByVal txt As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, _
    ByVal clickHandler As Any Ptr = 0 _
) As Widget Ptr
Declare Sub button_SetFlatStyle( _
    ByVal w As Widget Ptr, _
    ByVal normalBackground As ULong, ByVal normalForeground As ULong, _
    ByVal hotBackground As ULong, ByVal hotForeground As ULong, _
    ByVal selectedBackground As ULong, ByVal selectedForeground As ULong _
)
Declare Sub button_SetSelected(ByVal w As Widget Ptr, ByVal selected As Integer)
Declare Sub button_SetDefault(ByVal w As Widget Ptr, ByVal isDefault As Integer)
Declare Sub button_SetDefaultOutline(ByVal w As Widget Ptr, ByVal visible As Integer)
Declare Sub button_SetArrow(ByVal w As Widget Ptr, ByVal direction As Integer)
Declare Sub button_CancelInput(ByVal w As Widget Ptr)
Declare Sub button_Render(ByVal w As Widget Ptr)
Declare Sub button_Update(ByVal w As Widget Ptr)
Declare Sub button_Activate(ByVal w As Widget Ptr)
Declare Sub button_Destroy(ByVal w As Widget Ptr)
Declare Function button_SetText( _
    ByVal w As Widget Ptr, ByRef text_value As Const String _
) As Integer
Declare Function button_GetText(ByVal w As Widget Ptr) As String
Declare Function button_SetBackgroundColor( _
    ByVal w As Widget Ptr, ByVal background_color As ULong _
) As Integer
Declare Function button_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
Declare Function button_GetBackgroundColor( _
    ByVal w As Widget Ptr, ByRef background_color As ULong _
) As Integer

#endif

' end of button.bi
