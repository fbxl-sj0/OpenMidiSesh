/'
    Project: omaGUI
    ---------------

    File: checkbox.bi

    Purpose:

        Declare a labeled boolean checkbox widget.

    Responsibilities:

        - retain the displayed label and checked state
        - expose checked label replacement and retrieval
        - retain optional caller-supplied background and foreground colors
        - expose pointer and keyboard toggle behavior
        - expose checkbox creation and widget lifecycle entry points

    This file intentionally does NOT contain:

        - rendering or pointer-update implementation
        - application-specific state synchronization
'/

#ifndef __CHECKBOX_BI__
#define __CHECKBOX_BI__

#include once "src/widgets/widgets.bi"

Type CheckBoxData
    As String label
    ' Mixed is retained independently of the ordinary Boolean state so legacy
    ' callers of GetChecked keep their established 0/-1 contract.
    As Integer checked, mixed, last_mb, pointer_armed
    As ULongInt activation_count
    As Integer background_color_override, foreground_color_override
    As ULong background_color, foreground_color
End Type

Declare Function checkbox_Create( _
    ByVal nm As String, ByVal lbl As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal checked As Integer = 0 _
) As Widget Ptr
Declare Sub checkbox_Render(ByVal w As Widget Ptr)
Declare Sub checkbox_Update(ByVal w As Widget Ptr)
Declare Sub checkbox_Activate(ByVal w As Widget Ptr)
Declare Sub checkbox_Destroy(ByVal w As Widget Ptr)
Declare Function checkbox_SetText( _
    ByVal w As Widget Ptr, ByRef text_value As Const String _
) As Integer
Declare Function checkbox_GetText(ByVal w As Widget Ptr) As String
' State setters do not report user activation. GetChecked returns 0 or -1.
Declare Function checkbox_SetChecked(ByVal w As Widget Ptr, ByVal checked As Integer) As Integer
Declare Function checkbox_GetChecked(ByVal w As Widget Ptr) As Integer
' Value is a portable tri-state contract: 0 unchecked, 1 checked, 2 mixed.
' Invalid values leave the widget unchanged and return zero.
Declare Function checkbox_SetValue(ByVal w As Widget Ptr, ByVal value As Integer) As Integer
Declare Function checkbox_GetValue(ByVal w As Widget Ptr) As Integer
Declare Function checkbox_GetActivationCount(ByVal w As Widget Ptr) As ULongInt
Declare Function checkbox_SetBackgroundColor( _
    ByVal w As Widget Ptr, ByVal background_color As ULong _
) As Integer
Declare Function checkbox_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
Declare Function checkbox_GetBackgroundColor( _
    ByVal w As Widget Ptr, ByRef background_color As ULong _
) As Integer
Declare Function checkbox_SetForegroundColor( _
    ByVal w As Widget Ptr, ByVal foreground_color As ULong _
) As Integer
Declare Function checkbox_ClearForegroundColor(ByVal w As Widget Ptr) As Integer
Declare Function checkbox_GetForegroundColor( _
    ByVal w As Widget Ptr, ByRef foreground_color As ULong _
) As Integer

#endif

' end of checkbox.bi
