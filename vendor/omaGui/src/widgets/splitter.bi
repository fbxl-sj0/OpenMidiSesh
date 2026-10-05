/'
    Project: omaGUI
    File: splitter.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for splitter.
    Purpose: Declare a movable divider for application panes.
    Responsibilities:
        - expose bounded parent-relative positions and input notifications
        - retain one pointer drag and a borrowed GUI-thread callback
    This file intentionally does NOT contain:
        - pane ownership, application layout policy, or platform declarations
'/

#ifndef __SPLITTER_BI__
#define __SPLITTER_BI__

#include once "src/widgets/widgets.bi"

Const SPLITTER_HORIZONTAL As Integer = 0
Const SPLITTER_VERTICAL As Integer = 1
Const SPLITTER_DEFAULT_THICKNESS As Integer = 8
' A million local pixels leaves ample headroom for geometry on 32-bit hosts.
Const SPLITTER_MAXIMUM_EXTENT As Integer = 1048576

Type SplitterChangeHandler As Sub(ByVal As Any Ptr, ByVal As Integer)

Type SplitterData
    As Integer orientation, minimum_position, maximum_position
    As Integer dragging, pointer_latch, drag_origin, drag_start_position
    As SplitterChangeHandler change_handler
    As Any Ptr change_context
End Type

' A vertical divider moves left/right; a horizontal divider moves up/down.
' Its position is the local x or y of the Widget rectangle, not a ratio.
Declare Function splitter_Create( _
    ByVal widget_name As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, _
    ByVal orientation As Integer = SPLITTER_VERTICAL _
) As Widget Ptr
Declare Function splitter_SetRange( _
    ByVal w As Widget Ptr, _
    ByVal minimum_position As Integer, ByVal maximum_position As Integer _
) As Integer
Declare Function splitter_GetRange( _
    ByVal w As Widget Ptr, _
    ByRef minimum_position As Integer, ByRef maximum_position As Integer _
) As Integer
' Setters clamp silently. Only pointer/keyboard changes notify the callback,
' allowing the host to relayout panes without recursive notifications.
Declare Function splitter_SetPosition( _
    ByVal w As Widget Ptr, ByVal position As Integer _
) As Integer
Declare Function splitter_GetPosition(ByVal w As Widget Ptr) As Integer
Declare Function splitter_IsDragging(ByVal w As Widget Ptr) As Integer
Declare Function splitter_SetChangeHandler( _
    ByVal w As Widget Ptr, ByVal handler As SplitterChangeHandler, _
    ByVal context As Any Ptr = 0 _
) As Integer
Declare Sub splitter_Update(ByVal w As Widget Ptr)
Declare Sub splitter_Render(ByVal w As Widget Ptr)
Declare Sub splitter_Destroy(ByVal w As Widget Ptr)

#endif

/' end of splitter.bi '/
