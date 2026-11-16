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
        - expose a mutable byte callback before keyboard activation
        - notify scan-code press/repeat and release around byte processing

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
    ' Append callback storage so the existing data members retain their offsets.
    As Any Ptr key_press_handler
    As Any Ptr key_down_handler, key_up_handler
End Type

Declare Function button_Create( _
    ByVal nm As String, ByVal txt As String, _ ' fblint: disable-line FBL-API-001 -- Widget identity precedes its displayed caption.
    ByVal x As Integer, ByVal y As Integer, _ ' fblint: disable-line FBL-API-001 -- Coordinates, extents and creation options retain the public API order.
    ByVal w As Integer, ByVal h As Integer, _ ' fblint: disable-line FBL-API-001 -- Coordinates, extents and creation options retain the public API order.
    ByVal clickHandler As Any Ptr = 0 _
) As Widget Ptr
Declare Sub button_SetFlatStyle( _
    ByVal w As Widget Ptr, _
    ByVal normalBackground As ULong, ByVal normalForeground As ULong, _ ' fblint: disable-line FBL-API-001 -- Color roles retain the published drawing/widget order.
    ByVal hotBackground As ULong, ByVal hotForeground As ULong, _ ' fblint: disable-line FBL-API-001 -- Color roles retain the published drawing/widget order.
    ByVal selectedBackground As ULong, ByVal selectedForeground As ULong _ ' fblint: disable-line FBL-API-001 -- Color roles retain the published drawing/widget order.
)
Declare Sub button_SetSelected(ByVal w As Widget Ptr, ByVal selected As Integer)
Declare Sub button_SetDefault(ByVal w As Widget Ptr, ByVal isDefault As Integer)
Declare Sub button_SetDefaultOutline(ByVal w As Widget Ptr, ByVal visible As Integer)
Declare Sub button_SetArrow(ByVal w As Widget Ptr, ByVal direction As Integer)
Declare Sub button_CancelInput(ByVal w As Widget Ptr)
Declare Sub button_Render(ByVal w As Widget Ptr)
Declare Sub button_Update(ByVal w As Widget Ptr)
/'
    The focused button receives text bytes and Return, Space, Backspace, and
    Escape. Zero cancels the byte; returned Return/Space requests activation.
    This GUI-thread callback may hide, remove, or redirect focus. Input
    handling checks registry identity again before touching borrowed state.
    Tab and mnemonic routing remain owned by the GUI manager.
'/
Declare Function button_SetKeyPressHandler( _
    ByVal w As Widget Ptr, _
    ByVal handler As Sub(ByVal As Widget Ptr, ByRef As Integer) _
) As Integer
/'
    Down receives portable scan codes before KeyPress/default activation and
    may map or cancel the source key through the common input view. Up is a
    release notification after byte/activation processing. Modifier arguments
    describe that raw event; changing them does not rewrite the input snapshot.
    Both callbacks use the same GUI-thread lifetime checks as KeyPress.
'/
Declare Function button_SetKeyDownHandler( _
    ByVal w As Widget Ptr, _
    ByVal handler As Sub(ByVal As Widget Ptr, ByRef As Integer, ByRef As Integer) _
) As Integer
Declare Function button_SetKeyUpHandler( _
    ByVal w As Widget Ptr, _
    ByVal handler As Sub(ByVal As Widget Ptr, ByRef As Integer, ByRef As Integer) _
) As Integer
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
