/'
    Project: omaGUI
    ---------------

    File: groupbox.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for groupbox.

    Purpose:

        Declare a classic labeled group-frame widget.

    Responsibilities:

        - retain the frame caption
        - retain optional caller-supplied client and caption colors
        - expose construction and checked caption replacement
        - provide a stable visual container rectangle for child controls

    This file intentionally does NOT contain:

        - child registration or layout policy
        - pointer or keyboard behavior
        - platform-native control calls
'/

#ifndef __GROUPBOX_BI__
#define __GROUPBOX_BI__

#include once "src/widgets/widgets.bi"

Type GroupBoxData
    As String text
    As Integer background_color_override
    As ULong background_color
    As Integer foreground_color_override
    As ULong foreground_color
End Type

Declare Function groupbox_Create( _
    ByVal nm As String, ByVal txt As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer _
) As Widget Ptr
Declare Sub groupbox_Render(ByVal w As Widget Ptr)
Declare Sub groupbox_Destroy(ByVal w As Widget Ptr)
Declare Function groupbox_SetText( _
    ByVal w As Widget Ptr, ByRef txt As Const String _
) As Integer
Declare Function groupbox_SetBackgroundColor( _
    ByVal w As Widget Ptr, ByVal background_color As ULong _
) As Integer
Declare Function groupbox_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
Declare Function groupbox_GetBackgroundColor( _
    ByVal w As Widget Ptr, ByRef background_color As ULong _
) As Integer
Declare Function groupbox_SetForegroundColor( _
    ByVal w As Widget Ptr, ByVal foreground_color As ULong _
) As Integer
Declare Function groupbox_ClearForegroundColor(ByVal w As Widget Ptr) As Integer
Declare Function groupbox_GetForegroundColor( _
    ByVal w As Widget Ptr, ByRef foreground_color As ULong _
) As Integer

#endif

/' end of groupbox.bi '/
