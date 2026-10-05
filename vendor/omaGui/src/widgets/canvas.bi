/'
    Project: omaGUI
    ---------------

    File: canvas.bi

    Purpose:

        Declare a clipped application-rendered canvas widget.

    Responsibilities:

        - retain non-owning render/update callbacks and caller context
        - expose pointer coordinates relative to the canvas
        - participate in ordinary widget layout, visibility, and input routing
        - optionally count complete primary-pointer clicks for host event loops

    This file intentionally does NOT contain:

        - application drawing policy
        - pixel storage or image ownership
        - platform-specific window or input calls
'/

#ifndef __CANVAS_BI__
#define __CANVAS_BI__

#include once "src/widgets/widgets.bi"

Type CanvasData
    As Any Ptr render_handler
    As Any Ptr update_handler
    As Any Ptr context
    As Integer pointer_x
    As Integer pointer_y
    As Integer pointer_buttons
    As Integer previous_pointer_buttons
    ' Opt-in activation does not change the existing relative pointer API.
    As Integer clickable, click_armed, click_previous_buttons
    As ULongInt activation_count
End Type

Declare Function canvas_Create( _
    ByVal widget_name As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal canvas_width As Integer, _
    ByVal canvas_height As Integer, _
    ByVal render_handler As Any Ptr, _
    ByVal update_handler As Any Ptr = 0, _
    ByVal context As Any Ptr = 0 _
) As Widget Ptr
Declare Sub canvas_Render(ByVal canvas_widget As Widget Ptr)
Declare Sub canvas_Update(ByVal canvas_widget As Widget Ptr)
Declare Sub canvas_Destroy(ByVal canvas_widget As Widget Ptr)
Declare Sub canvas_CancelInput(ByVal canvas_widget As Widget Ptr)
Declare Function canvas_SetClickable(ByVal canvas_widget As Widget Ptr, ByVal enabled As Integer) As Integer
Declare Function canvas_GetActivationCount(ByVal canvas_widget As Widget Ptr) As ULongInt
Declare Function canvas_GetPointerX(ByVal canvas_widget As Widget Ptr) As Integer
Declare Function canvas_GetPointerY(ByVal canvas_widget As Widget Ptr) As Integer
Declare Function canvas_GetPointerButtons( _
    ByVal canvas_widget As Widget Ptr _
) As Integer
Declare Function canvas_GetPreviousPointerButtons( _
    ByVal canvas_widget As Widget Ptr _
) As Integer
Declare Function canvas_GetContext(ByVal canvas_widget As Widget Ptr) As Any Ptr
Declare Sub canvas_SetContext( _
    ByVal canvas_widget As Widget Ptr, _
    ByVal context As Any Ptr _
)
' A drawing surface is deliberately nonfocusable by default. Interactive
' callers can opt in without making display-only canvases tab stops.
Declare Sub canvas_SetFocusable( _
    ByVal canvas_widget As Widget Ptr, _
    ByVal focusable As Integer _
)

#endif

/' end of canvas.bi '/
