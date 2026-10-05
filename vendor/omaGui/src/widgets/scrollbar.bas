/'
    Project: omaGUI
    ---------------
    File: scrollbar.bas

    Purpose:
        ScrollBar widget implementation.

    Responsibilities:
         Render a proportional scroll track and thumb
         Handle signed-range changes through pointer and keyboard input
         Repeat held arrow/page steps with bounded GUI-thread timing
         Validate imported range, value, and increment properties

    This file intentionally does NOT contain:
         List selection behavior
         Global pointer dispatch policy
'/

#lang "fb"
#include once "src/widgets/scrollbar.bi"
#include once "src/backend/theme.bi"

Const SCROLLBAR_MINIMUM_THUMB_SIZE As Integer = 12
Const SCROLLBAR_MINIMUM_WHEEL_STEP As Integer = 1
Const SCROLLBAR_ARROW_MAXIMUM As Integer = 4 ' Keep triangles legible on narrow bars.
Const SCROLLBAR_VALUE_MINIMUM As LongInt = -2147483648ll
Const SCROLLBAR_VALUE_MAXIMUM As LongInt = 2147483647ll
' UI pacing, not DOS timer ticks: pause after the press, then repeat steadily.
Const SCROLLBAR_REPEAT_DELAY_MS As Long = 400
Const SCROLLBAR_REPEAT_INTERVAL_MS As Long = 50
Const SCROLLBAR_PART_NONE As Integer = 0
Const SCROLLBAR_PART_SMALL_BEFORE As Integer = 1
Const SCROLLBAR_PART_SMALL_AFTER As Integer = 2
Const SCROLLBAR_PART_PAGE_BEFORE As Integer = 3
Const SCROLLBAR_PART_PAGE_AFTER As Integer = 4

Type ScrollBarGeometry
    As Integer length, arrows, track_length, thumb_size, thumb_start, extent
End Type

Private Function scrollbar_GetGeometry( _
    ByVal w As Widget Ptr, ByVal d As ScrollBarData Ptr, _
    ByRef geometry As ScrollBarGeometry _
) As Integer
    Dim As LongInt value_range, relative_value
    geometry = Type<ScrollBarGeometry>(0, 0, 0, 0, 0, 0)
    geometry.length = IIf(d->vertical, w->h, w->w)
    If geometry.length < 1 OrElse geometry.length > SCROLLBAR_VALUE_MAXIMUM Then Return 0
    If d->arrow_buttons Then
        geometry.arrows = IIf(d->vertical, w->w, w->h)
        If geometry.arrows < 0 Then Return 0
        ' Even a short bar reserves at least one third for its thumb track.
        If geometry.arrows > geometry.length \ 3 Then geometry.arrows = geometry.length \ 3
    End If
    geometry.track_length = geometry.length - geometry.arrows * 2
    value_range = CLngInt(d->max_val) - CLngInt(d->min_val)
    geometry.thumb_size = CInt(CLngInt(d->page_size) * geometry.track_length \ (value_range + d->page_size))
    If geometry.thumb_size < SCROLLBAR_MINIMUM_THUMB_SIZE Then geometry.thumb_size = SCROLLBAR_MINIMUM_THUMB_SIZE
    If geometry.thumb_size > geometry.track_length Then geometry.thumb_size = geometry.track_length
    geometry.extent = geometry.track_length - geometry.thumb_size
    geometry.thumb_start = geometry.arrows
    If value_range > 0 AndAlso geometry.extent > 0 Then
        relative_value = CLngInt(d->value) - CLngInt(d->min_val)
        If d->reverse_direction Then relative_value = value_range - relative_value
        geometry.thumb_start += CInt(relative_value * geometry.extent \ value_range)
    End If
    Return -1
End Function

Private Sub scrollbar_ClampValue(ByVal scrollData As ScrollBarData Ptr)
    If scrollData = 0 Then Exit Sub
    ' Older owners mutate this public record directly. Normalize their values
    ' before geometry arithmetic; checked setters reject out-of-range requests.
    If scrollData->min_val < SCROLLBAR_VALUE_MINIMUM Then scrollData->min_val = SCROLLBAR_VALUE_MINIMUM
    If scrollData->min_val > SCROLLBAR_VALUE_MAXIMUM Then scrollData->min_val = SCROLLBAR_VALUE_MAXIMUM
    If scrollData->max_val < SCROLLBAR_VALUE_MINIMUM Then scrollData->max_val = SCROLLBAR_VALUE_MINIMUM
    If scrollData->max_val > SCROLLBAR_VALUE_MAXIMUM Then scrollData->max_val = SCROLLBAR_VALUE_MAXIMUM
    If scrollData->max_val < scrollData->min_val Then _
        scrollData->max_val = scrollData->min_val
    If scrollData->value < scrollData->min_val Then _
        scrollData->value = scrollData->min_val
    If scrollData->value > scrollData->max_val Then _
        scrollData->value = scrollData->max_val
    If scrollData->page_size < 1 Then scrollData->page_size = 1
    If scrollData->small_change < 1 Then scrollData->small_change = 1
    If scrollData->large_change < 1 Then scrollData->large_change = 1
    If scrollData->page_size > SCROLLBAR_VALUE_MAXIMUM Then scrollData->page_size = SCROLLBAR_VALUE_MAXIMUM
    If scrollData->small_change > SCROLLBAR_VALUE_MAXIMUM Then scrollData->small_change = SCROLLBAR_VALUE_MAXIMUM
    If scrollData->large_change > SCROLLBAR_VALUE_MAXIMUM Then scrollData->large_change = SCROLLBAR_VALUE_MAXIMUM
End Sub


Private Sub scrollbar_ApplyDelta( _
    ByVal scrollData As ScrollBarData Ptr, _
    ByVal valueDelta As LongInt _
)
    Dim As LongInt requestedValue

    If scrollData = 0 Then Exit Sub
    If scrollData->reverse_direction Then valueDelta = -valueDelta
    requestedValue = CLngInt(scrollData->value) + valueDelta
    If requestedValue < scrollData->min_val Then
        scrollData->value = scrollData->min_val
    ElseIf requestedValue > scrollData->max_val Then
        scrollData->value = scrollData->max_val
    Else
        scrollData->value = CInt(requestedValue)
    End If
End Sub


Private Function scrollbar_PointerPart( _
    ByVal w As Widget Ptr, ByVal d As ScrollBarData Ptr, _
    ByRef geometry As Const ScrollBarGeometry _
) As Integer
    Dim As LongInt local_x = CLngInt(input_MouseX()) - w->ax
    Dim As LongInt local_y = CLngInt(input_MouseY()) - w->ay
    If local_x < 0 OrElse local_x >= w->w OrElse _
       local_y < 0 OrElse local_y >= w->h Then Return SCROLLBAR_PART_NONE
    Dim As LongInt position = IIf(d->vertical, local_y, local_x)
    If position < geometry.arrows Then Return SCROLLBAR_PART_SMALL_BEFORE
    If position >= geometry.length - geometry.arrows Then Return SCROLLBAR_PART_SMALL_AFTER
    If position < geometry.thumb_start Then Return SCROLLBAR_PART_PAGE_BEFORE
    If position >= geometry.thumb_start + geometry.thumb_size Then Return SCROLLBAR_PART_PAGE_AFTER
    Return SCROLLBAR_PART_NONE
End Function

Private Sub scrollbar_ApplyPart(ByVal d As ScrollBarData Ptr, ByVal part As Integer)
    Select Case part
    Case SCROLLBAR_PART_SMALL_BEFORE
        scrollbar_ApplyDelta d, -CLngInt(d->small_change)
    Case SCROLLBAR_PART_SMALL_AFTER
        scrollbar_ApplyDelta d, CLngInt(d->small_change)
    Case SCROLLBAR_PART_PAGE_BEFORE
        scrollbar_ApplyDelta d, -CLngInt(d->large_change)
    Case SCROLLBAR_PART_PAGE_AFTER
        scrollbar_ApplyDelta d, CLngInt(d->large_change)
    End Select
End Sub

Private Sub scrollbar_UpdateRepeat(ByVal w As Widget Ptr, ByVal d As ScrollBarData Ptr)
    If d->automatic_repeat = 0 OrElse d->pressed_part = SCROLLBAR_PART_NONE Then Exit Sub
    Dim As Double clock_now = CDbl(Timer)
    If d->repeat_clock_initialized = 0 Then
        d->repeat_clock = clock_now
        d->repeat_clock_initialized = -1
        Exit Sub
    End If
    Dim As Double elapsed_ms = (clock_now - d->repeat_clock) * 1000.0
    d->repeat_clock = clock_now
    ' TIMER wraps at midnight. Long pauses coalesce to one step, never a burst.
    If elapsed_ms < 0 Then elapsed_ms += 86400000.0
    If elapsed_ms > 3600000.0 Then elapsed_ms = d->repeat_delay_ms + d->repeat_interval_ms
    scrollbar_AdvanceRepeat w, elapsed_ms
End Sub

Private Sub scrollbar_StopPointer(ByVal d As ScrollBarData Ptr)
    d->dragging = 0
    d->pressed_part = SCROLLBAR_PART_NONE
    d->repeat_started = 0
    d->repeat_elapsed_ms = 0
    d->repeat_clock_initialized = 0
End Sub


Private Sub scrollbar_HandleKeyboardInput( _
    ByVal w As Widget Ptr, _
    ByVal scrollData As ScrollBarData Ptr _
)
    If w = 0 OrElse scrollData = 0 OrElse w->has_focus = 0 Then Exit Sub

    If input_KeyPressEvent(KEY_HOME) Then
        scrollData->value = IIf(scrollData->reverse_direction, scrollData->max_val, scrollData->min_val)
    ElseIf input_KeyPressEvent(KEY_END) Then
        scrollData->value = IIf(scrollData->reverse_direction, scrollData->min_val, scrollData->max_val)
    ElseIf input_KeyPressEvent(FB.SC_PAGEUP) Then
        scrollbar_ApplyDelta scrollData, -CLngInt(scrollData->large_change)
    ElseIf input_KeyPressEvent(FB.SC_PAGEDOWN) Then
        scrollbar_ApplyDelta scrollData, CLngInt(scrollData->large_change)
    ElseIf scrollData->vertical <> 0 Then
        If input_KeyPressEvent(KEY_UP) Then
            scrollbar_ApplyDelta scrollData, -CLngInt(scrollData->small_change)
        ElseIf input_KeyPressEvent(KEY_DOWN) Then
            scrollbar_ApplyDelta scrollData, CLngInt(scrollData->small_change)
        End If
    Else
        If input_KeyPressEvent(KEY_LEFT) Then
            scrollbar_ApplyDelta scrollData, -CLngInt(scrollData->small_change)
        ElseIf input_KeyPressEvent(KEY_RIGHT) Then
            scrollbar_ApplyDelta scrollData, CLngInt(scrollData->small_change)
        End If
    End If
End Sub

' -------------------------------------------------------------------------
' Construction
' -------------------------------------------------------------------------

Function scrollbar_Create(ByVal nm As String, ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, ByVal mv As Integer, ByVal ps As Integer, ByVal v As Integer) As Widget Ptr
    Dim As Widget Ptr wgt
    Dim As ScrollBarData Ptr d

    If mv < SCROLLBAR_VALUE_MINIMUM OrElse mv > SCROLLBAR_VALUE_MAXIMUM OrElse _
       ps < SCROLLBAR_VALUE_MINIMUM OrElse ps > SCROLLBAR_VALUE_MAXIMUM Then Return 0
    wgt = New Widget
    If wgt = 0 Then Return 0
    d = New ScrollBarData
    If d = 0 Then
        Delete wgt
        Return 0
    End If

    wgt->name = nm : wgt->x = x : wgt->y = y : wgt->w = w : wgt->h = h
    wgt->visible = 1 : wgt->enabled = 1 : wgt->render = @scrollbar_Render : wgt->update = @scrollbar_Update : wgt->destroy = @scrollbar_Destroy
    wgt->accepts_focus = -1
    wgt->cancel_input = @scrollbar_CancelPointer

    d->min_val = 0
    d->max_val = mv
    d->value = 0
    d->page_size = ps
    d->small_change = 1
    d->large_change = ps
    d->vertical = v
    d->repeat_delay_ms = SCROLLBAR_REPEAT_DELAY_MS
    d->repeat_interval_ms = SCROLLBAR_REPEAT_INTERVAL_MS
    d->automatic_repeat = -1
    scrollbar_ClampValue d

    wgt->data = d
    Return wgt
End Function

' -------------------------------------------------------------------------
' Rendering
' -------------------------------------------------------------------------

Sub scrollbar_Render(ByVal w As Widget Ptr)
    Dim As ULong background_color
    Dim As ScrollBarData Ptr d
    Dim As ULong foreground_color
    Dim As Integer thumbPosition
    Dim As Integer thumbSize
    Dim As ScrollBarGeometry geometry
    Dim As LongInt valueRange

    If w = 0 Then Exit Sub
    d = Cast(ScrollBarData Ptr, w->data)
    If d = 0 Then Exit Sub
    background_color = theme_GetClassicColor( _
        GUI_CLASSIC_COLOR_SCROLLBAR_BACKGROUND _
    )
    foreground_color = theme_GetClassicColor( _
        GUI_CLASSIC_COLOR_SCROLLBAR_TEXT _
    )
    Dim As ULong thumb_color = background_color
    Dim As ULong thumb_border_color = current_theme.bg_light
    If d->custom_colors_enabled Then
        background_color = d->track_color
        thumb_color = d->thumb_color
        thumb_border_color = d->thumb_border_color
    End If
    scrollbar_ClampValue d
    If scrollbar_GetGeometry(w, d, geometry) = 0 Then Exit Sub

    /'
        A zero-range scrollbar remains visible for controls using an
        always-present policy, but its uniform face color communicates that
        there is no movable content.
    '/
    valueRange = CLngInt(d->max_val) - CLngInt(d->min_val)
    If valueRange = 0 OrElse w->enabled = 0 Then
        backend_Rect w->ax, w->ay, w->w, w->h, background_color, 1
        backend_Rect w->ax, w->ay, w->w, w->h, _
            IIf(d->custom_colors_enabled, thumb_border_color, current_theme.bg_dark), 0
        Exit Sub
    End If

    ' Track
    backend_Rect w->ax, w->ay, w->w, w->h, background_color, 1

    thumbSize = geometry.thumb_size
    thumbPosition = geometry.thumb_start
    If geometry.arrows > 0 Then
        For arrow_index As Integer = 0 To 1
            Dim As Integer part_x = w->ax
            Dim As Integer part_y = w->ay
            Dim As Integer part_width = w->w
            Dim As Integer part_height = w->h
            If d->vertical Then
                part_height = geometry.arrows
                part_y += arrow_index * (geometry.length - geometry.arrows)
            Else
                part_width = geometry.arrows
                part_x += arrow_index * (geometry.length - geometry.arrows)
            End If
            backend_Rect part_x, part_y, part_width, part_height, background_color, 1
            backend_Rect part_x, part_y, part_width, part_height, current_theme.bg_light, 0
            Dim As Integer center_x = part_x + part_width \ 2
            Dim As Integer center_y = part_y + part_height \ 2
            Dim As Integer arrow_size = geometry.arrows \ 4
            If arrow_size > SCROLLBAR_ARROW_MAXIMUM Then arrow_size = SCROLLBAR_ARROW_MAXIMUM
            For arrow_line As Integer = 0 To arrow_size - 1
                Dim As Integer direction = IIf(arrow_index, -1, 1)
                If d->vertical Then
                    backend_Line center_x - arrow_line, center_y + arrow_line * direction, _
                        center_x + arrow_line, center_y + arrow_line * direction, _
                        foreground_color
                Else
                    backend_Line center_x + arrow_line * direction, center_y - arrow_line, _
                        center_x + arrow_line * direction, center_y + arrow_line, _
                        foreground_color
                End If
            Next arrow_line
        Next arrow_index
    End If

    If d->vertical Then
        backend_Rect w->ax + 2, w->ay + thumbPosition, _
            w->w - 4, thumbSize, thumb_color, 1
        backend_Rect w->ax + 2, w->ay + thumbPosition, _
            w->w - 4, thumbSize, thumb_border_color, 0
    Else
        backend_Rect w->ax + thumbPosition, w->ay + 2, _
            thumbSize, w->h - 4, thumb_color, 1
        backend_Rect w->ax + thumbPosition, w->ay + 2, _
            thumbSize, w->h - 4, thumb_border_color, 0
    End If
End Sub

Sub scrollbar_SetColors( _
    ByVal w As Widget Ptr, ByVal trackColor As ULong, _
    ByVal thumbColor As ULong, ByVal thumbBorderColor As ULong _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @scrollbar_Destroy Then Exit Sub
    Dim As ScrollBarData Ptr d = Cast(ScrollBarData Ptr, w->data)
    d->track_color = trackColor
    d->thumb_color = thumbColor
    d->thumb_border_color = thumbBorderColor
    d->custom_colors_enabled = -1
End Sub

' -------------------------------------------------------------------------
' Processing
' -------------------------------------------------------------------------

Sub scrollbar_Update(ByVal w As Widget Ptr)
    Dim As ScrollBarData Ptr d
    Dim As Integer mx
    Dim As Integer my
    Dim As Integer mb
    Dim As Integer wheelDelta
    Dim As Integer wheelStep
    Dim As LongInt valueRange
    Dim As LongInt pointerPosition, requestedPosition
    Dim As ScrollBarGeometry geometry
    Dim As Integer inside_widget

    If w = 0 Then Exit Sub
    d = Cast(ScrollBarData Ptr, w->data)
    If d = 0 Then Exit Sub
    If w->enabled = 0 OrElse w->visible = 0 Then
        scrollbar_CancelPointer w
        Exit Sub
    End If
    mx = input_MouseX()
    my = input_MouseY()
    mb = input_MouseButtons()
    wheelDelta = input_MouseWheel()
    scrollbar_ClampValue d
    If scrollbar_GetGeometry(w, d, geometry) = 0 Then
        scrollbar_CancelPointer w
        Exit Sub
    End If

    scrollbar_HandleKeyboardInput w, d

    inside_widget = mx >= w->ax AndAlso CLngInt(mx) - w->ax < w->w AndAlso _
        my >= w->ay AndAlso CLngInt(my) - w->ay < w->h
    If inside_widget Then
        If wheelDelta <> 0 Then
            wheelStep = d->small_change
            If wheelStep < SCROLLBAR_MINIMUM_WHEEL_STEP Then _
                wheelStep = SCROLLBAR_MINIMUM_WHEEL_STEP
            ' Physical wheel input and public values are signed 32-bit. Widen
            ' before multiplying so extreme mock input cannot wrap the value.
            If wheelDelta < SCROLLBAR_VALUE_MINIMUM Then wheelDelta = SCROLLBAR_VALUE_MINIMUM
            If wheelDelta > SCROLLBAR_VALUE_MAXIMUM Then wheelDelta = SCROLLBAR_VALUE_MAXIMUM
            scrollbar_ApplyDelta d, -CLngInt(wheelDelta) * wheelStep
        End If

        If (mb And 1) AndAlso (d->last_buttons And 1) = 0 Then
            ' Keyboard/wheel changes above may have moved the thumb this frame.
            scrollbar_GetGeometry w, d, geometry
            pointerPosition = IIf(d->vertical, CLngInt(my) - w->ay, CLngInt(mx) - w->ax)
            d->pressed_part = scrollbar_PointerPart(w, d, geometry)
            d->repeat_elapsed_ms = 0
            d->repeat_started = 0
            d->repeat_clock = CDbl(Timer)
            d->repeat_clock_initialized = -1
            If d->pressed_part <> SCROLLBAR_PART_NONE Then
                scrollbar_ApplyPart d, d->pressed_part
            Else
                ' Preserve the grab offset. Pressing a stationary thumb must
                ' not jump it to the pointer or manufacture a Change event.
                d->dragging = -1
                d->drag_offset = CInt(pointerPosition - geometry.thumb_start)
                d->drag_origin = pointerPosition
                d->drag_start_value = d->value
            End If
        End If
    End If
    If (mb And 1) = 0 Then
        scrollbar_CancelPointer w
    ElseIf (d->last_buttons And 1) <> 0 Then
        scrollbar_UpdateRepeat w, d
    End If
    If d->dragging AndAlso geometry.extent > 0 Then
        pointerPosition = IIf(d->vertical, CLngInt(my) - w->ay, CLngInt(mx) - w->ax)
        requestedPosition = pointerPosition - geometry.arrows - d->drag_offset
        If requestedPosition < 0 Then requestedPosition = 0
        If requestedPosition > geometry.extent Then requestedPosition = geometry.extent
        valueRange = CLngInt(d->max_val) - CLngInt(d->min_val)
        If pointerPosition <> d->drag_origin Then
            If requestedPosition = 0 Then
                d->value = IIf(d->reverse_direction, d->max_val, d->min_val)
            ElseIf requestedPosition = geometry.extent Then
                d->value = IIf(d->reverse_direction, d->min_val, d->max_val)
            Else
                ' Anchor to the exact starting value, not its rounded pixel.
                ' Returning to the grab point must restore the original value.
                Dim As LongInt value_delta = pointerPosition - d->drag_origin
                value_delta *= valueRange
                value_delta \= geometry.extent
                If d->reverse_direction Then value_delta = -value_delta
                Dim As LongInt requested_value = CLngInt(d->drag_start_value) + value_delta
                If requested_value < d->min_val Then requested_value = d->min_val
                If requested_value > d->max_val Then requested_value = d->max_val
                d->value = CInt(requested_value)
            End If
        Else
            d->value = d->drag_start_value
        End If
    End If
    d->last_buttons = mb
    scrollbar_ClampValue d
End Sub

' -------------------------------------------------------------------------
' Checked property interface
' -------------------------------------------------------------------------

Function scrollbar_SetRange( _
    ByVal w As Widget Ptr, _
    ByVal minimumValue As Integer, _
    ByVal maximumValue As Integer _
) As Integer
    Dim As ScrollBarData Ptr scrollData

    If w = 0 OrElse w->data = 0 Then Return 0
    If minimumValue > maximumValue Then Return 0
    If minimumValue < SCROLLBAR_VALUE_MINIMUM OrElse maximumValue > SCROLLBAR_VALUE_MAXIMUM Then Return 0

    scrollData = Cast(ScrollBarData Ptr, w->data)
    If scrollData->min_val <> minimumValue OrElse scrollData->max_val <> maximumValue Then scrollbar_StopPointer scrollData
    scrollData->min_val = minimumValue
    scrollData->max_val = maximumValue
    scrollbar_ClampValue scrollData
    Return -1
End Function


Function scrollbar_SetValue( _
    ByVal w As Widget Ptr, _
    ByVal valueNumber As Integer _
) As Integer
    Dim As ScrollBarData Ptr scrollData

    If w = 0 OrElse w->data = 0 Then Return 0
    scrollData = Cast(ScrollBarData Ptr, w->data)
    If valueNumber < scrollData->min_val OrElse _
       valueNumber > scrollData->max_val Then Return 0

    If scrollData->value <> valueNumber Then scrollbar_StopPointer scrollData
    scrollData->value = valueNumber
    Return -1
End Function


Function scrollbar_GetValue(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Return Cast(ScrollBarData Ptr, w->data)->value
End Function


Function scrollbar_SetChanges( _
    ByVal w As Widget Ptr, _
    ByVal smallChange As Integer, _
    ByVal largeChange As Integer _
) As Integer
    Dim As ScrollBarData Ptr scrollData

    If w = 0 OrElse w->data = 0 Then Return 0
    If smallChange < 1 OrElse largeChange < 1 OrElse _
       smallChange > SCROLLBAR_VALUE_MAXIMUM OrElse largeChange > SCROLLBAR_VALUE_MAXIMUM Then Return 0

    scrollData = Cast(ScrollBarData Ptr, w->data)
    If scrollData->small_change <> smallChange OrElse scrollData->large_change <> largeChange Then scrollbar_StopPointer scrollData
    scrollData->small_change = smallChange
    scrollData->large_change = largeChange
    scrollData->page_size = largeChange
    Return -1
End Function

Function scrollbar_SetReverse(ByVal w As Widget Ptr, ByVal reversed As Integer) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(ScrollBarData Ptr, w->data)->reverse_direction = IIf(reversed, -1, 0)
    scrollbar_StopPointer Cast(ScrollBarData Ptr, w->data)
    Return -1
End Function

Function scrollbar_SetArrowButtons(ByVal w As Widget Ptr, ByVal enabled As Integer) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(ScrollBarData Ptr, w->data)->arrow_buttons = IIf(enabled, -1, 0)
    scrollbar_StopPointer Cast(ScrollBarData Ptr, w->data)
    Return -1
End Function

Function scrollbar_IsDragging(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Return Cast(ScrollBarData Ptr, w->data)->dragging
End Function

' -------------------------------------------------------------------------
' Held-pointer repetition
' -------------------------------------------------------------------------

Sub scrollbar_CancelPointer(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    scrollbar_StopPointer Cast(ScrollBarData Ptr, w->data)
    With *Cast(ScrollBarData Ptr, w->data)
        ' Suppress only a button already held at cancellation, not the next
        ' fresh press. Read sampled state without polling the platform; the
        ' manager may still have another widget's dispatch mask active.
        .last_buttons = input_UnmaskedMouseButtons()
    End With
End Sub

Function scrollbar_SetRepeat(ByVal w As Widget Ptr, ByVal delayMs As Long, ByVal intervalMs As Long) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    ' A zero interval disables repetition without changing single-click steps.
    If delayMs < 0 OrElse delayMs > 65535 OrElse intervalMs < 0 OrElse intervalMs > 65535 Then Return 0
    With *Cast(ScrollBarData Ptr, w->data)
        .repeat_delay_ms = delayMs
        .repeat_interval_ms = intervalMs
    End With
    scrollbar_StopPointer Cast(ScrollBarData Ptr, w->data)
    Return -1
End Function

Sub scrollbar_SetAutomaticRepeat(ByVal w As Widget Ptr, ByVal enabledState As Integer)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    With *Cast(ScrollBarData Ptr, w->data)
        .automatic_repeat = IIf(enabledState, -1, 0)
        .repeat_clock_initialized = 0
    End With
End Sub

Function scrollbar_AdvanceRepeat(ByVal w As Widget Ptr, ByVal elapsedMs As Double) As Integer
    Dim As ScrollBarData Ptr d
    Dim As ScrollBarGeometry geometry
    Dim As Double threshold_ms
    If w = 0 OrElse w->data = 0 Then Return 0
    If elapsedMs <> elapsedMs OrElse elapsedMs < 0 OrElse elapsedMs > 86400000.0 Then Return 0
    d = Cast(ScrollBarData Ptr, w->data)
    If w->enabled = 0 OrElse w->visible = 0 OrElse w->een = 0 OrElse w->evis = 0 Then
        scrollbar_CancelPointer w
        Return 0
    End If
    If (input_MouseButtons() And 1) = 0 Then
        scrollbar_StopPointer d
        d->last_buttons = 0
        Return 0
    End If
    If d->pressed_part = SCROLLBAR_PART_NONE OrElse d->repeat_interval_ms <= 0 Then Return 0
    scrollbar_ClampValue d
    If scrollbar_GetGeometry(w, d, geometry) = 0 Then Return 0
    ' Repeat only within the originally pressed region. Paging pauses when
    ' the moving thumb reaches the pointer; crossing to the opposite side
    ' must not reverse it. Returning to the same region restarts the delay.
    If scrollbar_PointerPart(w, d, geometry) <> d->pressed_part Then
        d->repeat_elapsed_ms = 0
        d->repeat_started = 0
        Return 0
    End If
    threshold_ms = IIf(d->repeat_started, d->repeat_interval_ms, d->repeat_delay_ms)
    d->repeat_elapsed_ms += elapsedMs
    If d->repeat_elapsed_ms < threshold_ms Then Return 0
    d->repeat_elapsed_ms -= threshold_ms
    d->repeat_started = -1
    d->repeat_elapsed_ms -= Fix(d->repeat_elapsed_ms / d->repeat_interval_ms) * d->repeat_interval_ms
    Dim As Integer old_value = d->value
    scrollbar_ApplyPart d, d->pressed_part
    Return d->value <> old_value
End Function

' -------------------------------------------------------------------------
' Lifecycle
' -------------------------------------------------------------------------

Sub scrollbar_Destroy(ByVal w As Widget Ptr)
    Delete Cast(ScrollBarData Ptr, w->data)
End Sub

' end of scrollbar.bas
