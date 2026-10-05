/'
    Project: omaGUI
    ---------------

    File: timerwidget.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for timerwidget.

    Purpose:

        Declare a portable nonvisual interval timer widget.

    Responsibilities:

        - retain a checked interval and enabled state
        - accumulate elapsed milliseconds without platform timer APIs
        - coalesce delayed frames into one safe callback
        - expose deterministic manual advancement for tests and simulations

    This file intentionally does NOT contain:

        - worker threads or synchronization
        - operating-system timer handles
        - application-specific scheduling policy
'/

#ifndef __TIMERWIDGET_BI__
#define __TIMERWIDGET_BI__

#include once "src/widgets/widgets.bi"

Const TIMERWIDGET_MAXIMUM_INTERVAL_MS As LongInt = 86400000

Type TimerWidgetData
    As LongInt interval_ms
    As Double accumulated_ms
    As Double last_clock_seconds
    As Integer clock_initialized
    As Integer timer_enabled
    As ULongInt tick_count
    As Any Ptr tick_handler
End Type

Declare Function timerwidget_Create( _
    ByVal widget_name As String, _
    ByVal interval_ms As LongInt, _
    ByVal enabled_state As Integer = -1, _
    ByVal tick_handler As Any Ptr = 0 _
) As Widget Ptr
Declare Sub timerwidget_Update(ByVal timer_widget As Widget Ptr)
Declare Sub timerwidget_Destroy(ByVal timer_widget As Widget Ptr)
Declare Function timerwidget_Advance( _
    ByVal timer_widget As Widget Ptr, _
    ByVal elapsed_ms As Double _
) As Integer
Declare Function timerwidget_SetInterval( _
    ByVal timer_widget As Widget Ptr, _
    ByVal interval_ms As LongInt _
) As Integer
Declare Function timerwidget_GetInterval( _
    ByVal timer_widget As Widget Ptr _
) As LongInt
Declare Function timerwidget_SetEnabled( _
    ByVal timer_widget As Widget Ptr, _
    ByVal enabled_state As Integer _
) As Integer
Declare Function timerwidget_GetEnabled( _
    ByVal timer_widget As Widget Ptr _
) As Integer
Declare Function timerwidget_GetTickCount( _
    ByVal timer_widget As Widget Ptr _
) As ULongInt
Declare Sub timerwidget_Reset(ByVal timer_widget As Widget Ptr)

#endif

/' end of timerwidget.bi '/
