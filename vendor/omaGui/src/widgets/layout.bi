/'
    Project: omaGUI
    ---------------

    File: layout.bi

    Purpose:

        Define lightweight row, column, and grid containers for interfaces
        that must remain usable at different text and display scales.

    Responsibilities:

        - describe container padding, gaps, and grid dimensions
        - expose preferred-size and weighted expansion layout
        - report layouts whose child minimum sizes cannot fit

    This file intentionally does NOT contain:

        - widget drawing
        - platform input handling
        - application-specific screen policy
'/

#ifndef __LAYOUT_BI__
#define __LAYOUT_BI__

#include once "src/widgets/widgets.bi"

Const GUI_LAYOUT_ROW As Integer = 1
Const GUI_LAYOUT_COLUMN As Integer = 2
Const GUI_LAYOUT_GRID As Integer = 3

Type LayoutData
    As Integer mode
    As Integer padding
    As Integer gap
    As Integer columns
    As Integer stretch_cross_axis
    As Integer overflowed
End Type

Declare Function layout_Create( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal w As Integer, _
    ByVal h As Integer, _
    ByVal mode As Integer, _
    ByVal padding As Integer = 0, _
    ByVal gap As Integer = 0, _
    ByVal columns As Integer = 1) As Widget Ptr
Declare Sub layout_SetStretchCrossAxis( _
    ByVal w As Widget Ptr, _
    ByVal enabled As Integer)
Declare Sub layout_Apply(ByVal w As Widget Ptr)
Declare Function layout_HasOverflow(ByVal w As Widget Ptr) As Integer
Declare Sub layout_Destroy(ByVal w As Widget Ptr)

#endif

/' end of layout.bi '/
