/'
    Project: omaGUI
    ---------------

    File: scrollbar.bi

    Purpose:
        Declare horizontal and vertical scrollbar widgets.

    Responsibilities:
        - retain bounded value, signed range, increments, and orientation
        - expose scrollbar construction, rendering, pointer, and key handling
        - expose checked property setters for imported form metadata
        - expose repeat timing and private pointer-state cancellation

    This file intentionally does NOT contain:
        - list ownership
        - global wheel dispatch
        - application-specific value interpretation
'/

#ifndef __SCROLLBAR_BI__
#define __SCROLLBAR_BI__
#include once "src/widgets/widgets.bi"
Type ScrollBarData
    As Integer min_val
    As Integer max_val
    As Integer value
    As Integer page_size
    As Integer small_change
    As Integer large_change
    As Integer vertical
    As Integer reverse_direction
    As Integer arrow_buttons
    As Integer last_buttons
    As Integer dragging
    As Integer drag_offset
    As LongInt drag_origin
    As Integer drag_start_value
    As Integer pressed_part, repeat_started
    As Long repeat_delay_ms, repeat_interval_ms
    As Double repeat_elapsed_ms, repeat_clock
    As Integer automatic_repeat, repeat_clock_initialized
    ' Optional colors for a scrollbar embedded in a styled control.
    As Integer custom_colors_enabled
    As ULong track_color, thumb_color, thumb_border_color
End Type
Declare Function scrollbar_Create(ByVal nm As String, ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, ByVal mv As Integer, ByVal ps As Integer = 10, ByVal v As Integer = 1) As Widget Ptr
Declare Sub scrollbar_Render(ByVal w As Widget Ptr)
Declare Sub scrollbar_Update(ByVal w As Widget Ptr)
Declare Sub scrollbar_Destroy(ByVal w As Widget Ptr)
Declare Sub scrollbar_SetColors( _
    ByVal w As Widget Ptr, ByVal trackColor As ULong, _
    ByVal thumbColor As ULong, ByVal thumbBorderColor As ULong _
)
Declare Function scrollbar_SetRange( _
    ByVal w As Widget Ptr, _
    ByVal minimumValue As Integer, _
    ByVal maximumValue As Integer _
) As Integer
Declare Function scrollbar_SetValue( _
    ByVal w As Widget Ptr, _
    ByVal valueNumber As Integer _
) As Integer
Declare Function scrollbar_GetValue(ByVal w As Widget Ptr) As Integer
Declare Function scrollbar_SetChanges( _
    ByVal w As Widget Ptr, _
    ByVal smallChange As Integer, _
    ByVal largeChange As Integer _
) As Integer
Declare Function scrollbar_SetReverse(ByVal w As Widget Ptr, ByVal reversed As Integer) As Integer
Declare Function scrollbar_SetArrowButtons(ByVal w As Widget Ptr, ByVal enabled As Integer) As Integer
Declare Function scrollbar_IsDragging(ByVal w As Widget Ptr) As Integer
Declare Sub scrollbar_CancelPointer(ByVal w As Widget Ptr)
Declare Function scrollbar_SetRepeat( _
    ByVal w As Widget Ptr, ByVal delayMs As Long, ByVal intervalMs As Long _
) As Integer
Declare Sub scrollbar_SetAutomaticRepeat(ByVal w As Widget Ptr, ByVal enabledState As Integer)
Declare Function scrollbar_AdvanceRepeat(ByVal w As Widget Ptr, ByVal elapsedMs As Double) As Integer
#endif

/' end of scrollbar.bi '/
