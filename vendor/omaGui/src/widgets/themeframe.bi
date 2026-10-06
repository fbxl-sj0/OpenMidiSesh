/'
    Project: omaGUI
    ---------------

    File: themeframe.bi

    Targets:

        FreeBASIC FB dialect. Desktop gfxlib2 builds use the platform backend
        selected by the including project.

    Module API:

        Theme-aware frame constructor and draw declaration.

    Purpose:

        Declare a non-interactive panel that follows the effective GUI theme.

    Responsibilities:

        - fill panel surfaces with the semantic panel color
        - draw one of the bounded reusable frame construction styles
        - preserve a caller color for the classic compatibility style
        - permit bounded runtime updates to that classic color

    This file intentionally does NOT contain:

        - application or faction names
        - child layout or input handling
        - graphics-backend lifecycle management
'/

#ifndef __THEMEFRAME_BI__
#define __THEMEFRAME_BI__

#include once "src/widgets/widgets.bi"

Type ThemeFrameData
    As ULong classicColor
    As Integer filled
End Type

Declare Function themeframe_Create( _
    ByVal nm As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, _
    ByVal classicColor As ULong, ByVal filled As Integer _
) As Widget Ptr
Declare Sub themeframe_SetClassicColor( _
    ByVal w As Widget Ptr, ByVal classicColor As ULong)
Declare Sub themeframe_Render(ByVal w As Widget Ptr)
Declare Sub themeframe_Destroy(ByVal w As Widget Ptr)

#endif

/' end of themeframe.bi '/
