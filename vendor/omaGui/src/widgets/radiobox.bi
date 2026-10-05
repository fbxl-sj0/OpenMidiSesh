/'
    Project: omaGUI
    ---------------

    File: radiobox.bi

    Purpose:

        Declare a labeled radio-button widget with registry-wide grouping.

    Responsibilities:

        - retain group and selected state
        - expose checked label replacement and retrieval
        - retain optional caller-supplied background and foreground colors
        - expose pointer and keyboard selection behavior
        - expose radio-button creation and widget lifecycle entry points

    This file intentionally does NOT contain:

        - group traversal implementation
        - application-specific option semantics
'/

#ifndef __RADIOBOX_BI__
#define __RADIOBOX_BI__

#include once "src/widgets/widgets.bi"

Type RadioBoxData
    As String label
    As Integer group_id, selected, last_mb, pointer_armed
    As ULongInt activation_count
    As Integer background_color_override, foreground_color_override
    As ULong background_color, foreground_color
End Type

Declare Function radiobox_Create( _
    ByVal nm As String, ByVal lbl As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal gid As Integer, ByVal s As Integer = 0 _
) As Widget Ptr
Declare Sub radiobox_Render(ByVal w As Widget Ptr)
Declare Sub radiobox_Update(ByVal w As Widget Ptr)
Declare Sub radiobox_Activate(ByVal w As Widget Ptr)
Declare Sub radiobox_Destroy(ByVal w As Widget Ptr)
Declare Function radiobox_SetText( _
    ByVal w As Widget Ptr, ByRef text_value As Const String _
) As Integer
Declare Function radiobox_GetText(ByVal w As Widget Ptr) As String
' SetSelected preserves group exclusivity without reporting user activation.
' GetSelected returns 0 or -1; retained selected state keeps the legacy 0/1 ABI.
Declare Function radiobox_SetSelected(ByVal w As Widget Ptr, ByVal selected As Integer) As Integer
Declare Function radiobox_GetSelected(ByVal w As Widget Ptr) As Integer
Declare Function radiobox_GetActivationCount(ByVal w As Widget Ptr) As ULongInt
Declare Function radiobox_SetBackgroundColor( _
    ByVal w As Widget Ptr, ByVal background_color As ULong _
) As Integer
Declare Function radiobox_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
Declare Function radiobox_GetBackgroundColor( _
    ByVal w As Widget Ptr, ByRef background_color As ULong _
) As Integer
Declare Function radiobox_SetForegroundColor( _
    ByVal w As Widget Ptr, ByVal foreground_color As ULong _
) As Integer
Declare Function radiobox_ClearForegroundColor(ByVal w As Widget Ptr) As Integer
Declare Function radiobox_GetForegroundColor( _
    ByVal w As Widget Ptr, ByRef foreground_color As ULong _
) As Integer

#endif

' end of radiobox.bi
