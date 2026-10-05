/'
    Project: omaGUI
    ---------------

    File: timerwidget.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements timerwidget.bi; declarations there define the interface.

    Purpose:

        Implement a portable nonvisual interval timer through the FreeBASIC
        runtime clock.

    Responsibilities:

        - sample elapsed time during the ordinary GUI update pass
        - handle the Timer function's midnight wrap
        - coalesce missed intervals after a delayed frame
        - invoke a caller-owned tick callback without retaining its context

    This file intentionally does NOT contain:

        - platform SDK declarations
        - background threads or asynchronous callbacks
        - rendering or input behavior

    Timing model:

        - callbacks run synchronously on the GUI thread
        - at most one callback is emitted per update or manual advance
        - excess elapsed time retains only the sub-interval remainder
'/

#lang "fb"

#include once "src/widgets/timerwidget.bi"

Const TIMERWIDGET_MILLISECONDS_PER_SECOND As Double = 1000.0
Const TIMERWIDGET_SECONDS_PER_DAY As Double = 86400.0
Const TIMERWIDGET_MAXIMUM_CLOCK_STEP_SECONDS As Double = 3600.0
Const TIMERWIDGET_MAXIMUM_ADVANCE_MS As Double = 86400000.0

' -------------------------------------------------------------------------
' Construction and lifecycle
' -------------------------------------------------------------------------

Function timerwidget_Create( _
    ByVal widget_name As String, _
    ByVal interval_ms As LongInt, _
    ByVal enabled_state As Integer, _
    ByVal tick_handler As Any Ptr _
) As Widget Ptr
    Dim As TimerWidgetData Ptr timer_data
    Dim As Widget Ptr timer_widget

    If interval_ms < 1 OrElse _
       interval_ms > TIMERWIDGET_MAXIMUM_INTERVAL_MS Then Return 0

    timer_widget = New Widget
    timer_data = New TimerWidgetData
    If timer_widget = 0 OrElse timer_data = 0 Then
        If timer_widget <> 0 Then Delete timer_widget
        If timer_data <> 0 Then Delete timer_data
        Return 0
    End If

    timer_widget->name = widget_name
    timer_widget->x = 0
    timer_widget->y = 0
    /'
        A zero-area rectangle keeps this nonvisual update widget out of the
        manager's pointer hit testing without requiring a special backend or
        an off-screen coordinate assumption.
    '/
    timer_widget->w = 0
    timer_widget->h = 0
    timer_widget->visible = -1
    timer_widget->enabled = -1
    timer_widget->update = @timerwidget_Update
    timer_widget->destroy = @timerwidget_Destroy
    timer_data->interval_ms = interval_ms
    timer_data->timer_enabled = IIf(enabled_state <> 0, -1, 0)
    timer_data->tick_handler = tick_handler
    timer_widget->data = timer_data
    Return timer_widget
End Function


Sub timerwidget_Destroy(ByVal timer_widget As Widget Ptr)
    If timer_widget = 0 Then Exit Sub
    If timer_widget->data <> 0 Then _
        Delete Cast(TimerWidgetData Ptr, timer_widget->data)
    timer_widget->data = 0
End Sub

' -------------------------------------------------------------------------
' Clock update and deterministic advancement
' -------------------------------------------------------------------------

Function timerwidget_Advance( _
    ByVal timer_widget As Widget Ptr, _
    ByVal elapsed_ms As Double _
) As Integer
    Dim As TimerWidgetData Ptr timer_data
    Dim As Double complete_intervals

    If timer_widget = 0 OrElse timer_widget->data = 0 Then Return 0
    If elapsed_ms <> elapsed_ms OrElse elapsed_ms < 0.0 OrElse _
       elapsed_ms > TIMERWIDGET_MAXIMUM_ADVANCE_MS Then Return 0
    timer_data = Cast(TimerWidgetData Ptr, timer_widget->data)
    If timer_data->timer_enabled = 0 Then Return 0

    timer_data->accumulated_ms += elapsed_ms
    If timer_data->accumulated_ms < CDbl(timer_data->interval_ms) Then Return 0

    /'
        A suspended or heavily loaded GUI may miss many nominal intervals.
        Emitting them as a burst would freeze input and can recursively mutate
        application state. Preserve phase through the remainder but coalesce
        every completed interval into one tick for this update.
    '/
    complete_intervals = Fix( _
        timer_data->accumulated_ms / CDbl(timer_data->interval_ms) _
    )
    timer_data->accumulated_ms -= _
        complete_intervals * CDbl(timer_data->interval_ms)
    timer_data->tick_count += 1
    If timer_data->tick_handler <> 0 Then
        Cast(Sub(ByVal As Widget Ptr), _
            timer_data->tick_handler)(timer_widget)
    End If
    Return -1
End Function


Sub timerwidget_Update(ByVal timer_widget As Widget Ptr)
    Dim As TimerWidgetData Ptr timer_data
    Dim As Double current_clock_seconds
    Dim As Double elapsed_seconds

    If timer_widget = 0 OrElse timer_widget->data = 0 Then Exit Sub
    timer_data = Cast(TimerWidgetData Ptr, timer_widget->data)
    current_clock_seconds = CDbl(Timer)

    If timer_data->clock_initialized = 0 Then
        timer_data->last_clock_seconds = current_clock_seconds
        timer_data->clock_initialized = -1
        Exit Sub
    End If

    elapsed_seconds = current_clock_seconds - timer_data->last_clock_seconds
    timer_data->last_clock_seconds = current_clock_seconds
    If elapsed_seconds < 0.0 Then _
        elapsed_seconds += TIMERWIDGET_SECONDS_PER_DAY

    /'
        Timer is seconds since midnight. A wall-clock correction or a resume
        after more than an hour is treated as one interval opportunity rather
        than an unbounded catch-up period.
    '/
    If elapsed_seconds > TIMERWIDGET_MAXIMUM_CLOCK_STEP_SECONDS Then
        elapsed_seconds = CDbl(timer_data->interval_ms) / _
            TIMERWIDGET_MILLISECONDS_PER_SECOND
    End If
    timerwidget_Advance _
        timer_widget, elapsed_seconds * TIMERWIDGET_MILLISECONDS_PER_SECOND
End Sub

' -------------------------------------------------------------------------
' Public timer state API
' -------------------------------------------------------------------------

Function timerwidget_SetInterval( _
    ByVal timer_widget As Widget Ptr, _
    ByVal interval_ms As LongInt _
) As Integer
    Dim As TimerWidgetData Ptr timer_data

    If timer_widget = 0 OrElse timer_widget->data = 0 Then Return 0
    If interval_ms < 1 OrElse _
       interval_ms > TIMERWIDGET_MAXIMUM_INTERVAL_MS Then Return 0

    timer_data = Cast(TimerWidgetData Ptr, timer_widget->data)
    timer_data->interval_ms = interval_ms
    timer_data->accumulated_ms = 0.0
    Return -1
End Function


Function timerwidget_GetInterval( _
    ByVal timer_widget As Widget Ptr _
) As LongInt
    If timer_widget = 0 OrElse timer_widget->data = 0 Then Return 0
    Return Cast(TimerWidgetData Ptr, timer_widget->data)->interval_ms
End Function


Function timerwidget_SetEnabled( _
    ByVal timer_widget As Widget Ptr, _
    ByVal enabled_state As Integer _
) As Integer
    Dim As TimerWidgetData Ptr timer_data

    If timer_widget = 0 OrElse timer_widget->data = 0 Then Return 0
    timer_data = Cast(TimerWidgetData Ptr, timer_widget->data)
    timer_data->timer_enabled = IIf(enabled_state <> 0, -1, 0)
    timer_data->accumulated_ms = 0.0
    timer_data->clock_initialized = 0
    Return -1
End Function


Function timerwidget_GetEnabled( _
    ByVal timer_widget As Widget Ptr _
) As Integer
    If timer_widget = 0 OrElse timer_widget->data = 0 Then Return 0
    Return Cast(TimerWidgetData Ptr, timer_widget->data)->timer_enabled
End Function


Function timerwidget_GetTickCount( _
    ByVal timer_widget As Widget Ptr _
) As ULongInt
    If timer_widget = 0 OrElse timer_widget->data = 0 Then Return 0
    Return Cast(TimerWidgetData Ptr, timer_widget->data)->tick_count
End Function


Sub timerwidget_Reset(ByVal timer_widget As Widget Ptr)
    Dim As TimerWidgetData Ptr timer_data

    If timer_widget = 0 OrElse timer_widget->data = 0 Then Exit Sub
    timer_data = Cast(TimerWidgetData Ptr, timer_widget->data)
    timer_data->accumulated_ms = 0.0
    timer_data->clock_initialized = 0
    timer_data->tick_count = 0
End Sub

/' end of timerwidget.bas '/
