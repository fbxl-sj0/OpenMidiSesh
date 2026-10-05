/'
    Project: omaGUI
    ---------------

    File: spinbutton.bas

    Purpose:

        Implement the portable classic spin-button widget.

    Responsibilities:

        - draw two directional button halves with the current theme
        - route pointer releases and arrow keys to one bounded value change
        - wrap or clamp at configured range endpoints
        - provide validated programmatic range and value operations
        - coalesce opt-in held-input repeats on the GUI thread

    This file intentionally does NOT contain:

        - a textbox or numeric-string parser
        - background timer threads or application event dispatch
        - platform-native control calls
'/

#lang "fb"

#include once "src/widgets/spinbutton.bi"
#include once "src/backend/theme.bi"

Const SPINBUTTON_MINIMUM_SIZE As Integer = 8
Const SPINBUTTON_PART_DECREMENT As Integer = 0
Const SPINBUTTON_PART_INCREMENT As Integer = 1
Const SPINBUTTON_NO_PART As Integer = -1
Const SPINBUTTON_ARROW_MAXIMUM As Integer = 5

' -------------------------------------------------------------------------
' Value handling
' -------------------------------------------------------------------------

Private Sub spinbutton_ChangeValue( _
    ByVal w As Widget Ptr, ByVal directionValue As Integer _
)
    Dim As SpinButtonData Ptr spin_data
    Dim As LongInt next_value
    Dim As Integer value_changed

    If w = 0 OrElse w->data = 0 Then Exit Sub
    spin_data = Cast(SpinButtonData Ptr, w->data)

    next_value = CLngInt(spin_data->current_value) + _
        CLngInt(directionValue) * spin_data->increment_value
    If next_value > spin_data->maximum_value Then
        If spin_data->wrap_enabled Then
            next_value = spin_data->minimum_value
        Else
            next_value = spin_data->maximum_value
        End If
    ElseIf next_value < spin_data->minimum_value Then
        If spin_data->wrap_enabled Then
            next_value = spin_data->maximum_value
        Else
            next_value = spin_data->minimum_value
        End If
    End If

    value_changed = IIf(next_value <> spin_data->current_value, -1, 0)
    spin_data->current_value = CInt(next_value)
    If value_changed = 0 AndAlso spin_data->step_handler = 0 Then Exit Sub
    spin_data->activation_count += 1
    ' A callback may destroy the widget. All state changes precede this call.
    If spin_data->step_handler <> 0 Then
        Cast(Sub(ByVal As Widget Ptr, ByVal As Integer), _
            spin_data->step_handler)(w, directionValue)
    ElseIf spin_data->change_handler <> 0 Then
        Cast(Sub(ByVal As Widget Ptr), spin_data->change_handler)(w)
    End If
End Sub


Private Function spinbutton_PointerPart( _
    ByVal w As Widget Ptr, ByVal pointerX As Integer, ByVal pointerY As Integer _
) As Integer
    Dim As SpinButtonData Ptr spin_data

    If w = 0 OrElse w->data = 0 Then Return SPINBUTTON_NO_PART
    If pointerX < w->ax OrElse pointerX >= w->ax + w->w OrElse _
       pointerY < w->ay OrElse pointerY >= w->ay + w->h Then
        Return SPINBUTTON_NO_PART
    End If

    spin_data = Cast(SpinButtonData Ptr, w->data)
    If spin_data->orientation = SPINBUTTON_HORIZONTAL Then
        If pointerX < w->ax + w->w \ 2 Then _
            Return SPINBUTTON_PART_DECREMENT
    Else
        If pointerY >= w->ay + w->h \ 2 Then _
            Return SPINBUTTON_PART_DECREMENT
    End If

    Return SPINBUTTON_PART_INCREMENT
End Function

' -------------------------------------------------------------------------
' Rendering
' -------------------------------------------------------------------------

Private Sub spinbutton_DrawPart( _
    ByVal partX As Integer, ByVal partY As Integer, _
    ByVal partWidth As Integer, ByVal partHeight As Integer, _
    ByVal directionX As Integer, ByVal directionY As Integer, _
    ByVal pressedValue As Integer _
)
    Dim As ULong dark_color
    Dim As ULong light_color
    Dim As Integer arrow_size
    Dim As Integer center_x
    Dim As Integer center_y
    Dim As Integer line_index

    dark_color = current_theme.bg_dark
    light_color = current_theme.bg_light
    If pressedValue Then Swap dark_color, light_color

    backend_Rect partX, partY, partWidth, partHeight, _
        current_theme.win_border, 0
    backend_Rect partX + 1, partY + 1, partWidth - 2, partHeight - 2, _
        current_theme.bg_face, -1
    backend_Line partX + 1, partY + 1, partX + partWidth - 2, _
        partY + 1, light_color
    backend_Line partX + 1, partY + 1, partX + 1, _
        partY + partHeight - 2, light_color
    backend_Line partX + 1, partY + partHeight - 2, _
        partX + partWidth - 2, partY + partHeight - 2, dark_color
    backend_Line partX + partWidth - 2, partY + 1, _
        partX + partWidth - 2, partY + partHeight - 2, dark_color

    center_x = partX + partWidth \ 2
    center_y = partY + partHeight \ 2
    arrow_size = partWidth \ 4
    If partHeight \ 4 < arrow_size Then arrow_size = partHeight \ 4
    If arrow_size < 1 Then arrow_size = 1
    If arrow_size > SPINBUTTON_ARROW_MAXIMUM Then _
        arrow_size = SPINBUTTON_ARROW_MAXIMUM

    For line_index = 0 To arrow_size - 1
        If directionY < 0 Then
            backend_Line center_x - line_index, center_y + line_index, _
                center_x + line_index, center_y + line_index, _
                current_theme.text_main
        ElseIf directionY > 0 Then
            backend_Line center_x - line_index, center_y - line_index, _
                center_x + line_index, center_y - line_index, _
                current_theme.text_main
        ElseIf directionX < 0 Then
            backend_Line center_x + line_index, center_y - line_index, _
                center_x + line_index, center_y + line_index, _
                current_theme.text_main
        Else
            backend_Line center_x - line_index, center_y - line_index, _
                center_x - line_index, center_y + line_index, _
                current_theme.text_main
        End If
    Next line_index
End Sub


Sub spinbutton_Render(ByVal w As Widget Ptr)
    Dim As SpinButtonData Ptr spin_data
    Dim As Integer first_width
    Dim As Integer first_height

    If w = 0 OrElse w->data = 0 Then Exit Sub
    spin_data = Cast(SpinButtonData Ptr, w->data)

    If spin_data->orientation = SPINBUTTON_HORIZONTAL Then
        first_width = w->w \ 2
        spinbutton_DrawPart w->ax, w->ay, first_width, w->h, -1, 0, _
            spin_data->pressed_part = SPINBUTTON_PART_DECREMENT
        spinbutton_DrawPart w->ax + first_width, w->ay, _
            w->w - first_width, w->h, 1, 0, _
            spin_data->pressed_part = SPINBUTTON_PART_INCREMENT
    Else
        first_height = w->h \ 2
        spinbutton_DrawPart w->ax, w->ay, w->w, first_height, 0, -1, _
            spin_data->pressed_part = SPINBUTTON_PART_INCREMENT
        spinbutton_DrawPart w->ax, w->ay + first_height, w->w, _
            w->h - first_height, 0, 1, _
            spin_data->pressed_part = SPINBUTTON_PART_DECREMENT
    End If
End Sub

' -------------------------------------------------------------------------
' Input and lifecycle
' -------------------------------------------------------------------------

Sub spinbutton_Activate(ByVal w As Widget Ptr)
    spinbutton_Step w, 1
End Sub


Sub spinbutton_Update(ByVal w As Widget Ptr)
    Dim As SpinButtonData Ptr spin_data
    Dim As Integer pointer_part
    Dim As Integer mouse_buttons
    Dim As Integer step_direction, held_direction
    Dim As Double clock_now, elapsed_ms

    If w = 0 OrElse w->data = 0 Then Exit Sub
    spin_data = Cast(SpinButtonData Ptr, w->data)
    mouse_buttons = input_MouseButtons()
    pointer_part = spinbutton_PointerPart( _
        w, input_MouseX(), input_MouseY() _
    )

    If (mouse_buttons And 1) <> 0 Then
        If spin_data->pointer_latch = 0 Then
            spin_data->pointer_latch = -1
            spin_data->pressed_part = pointer_part
            If spin_data->activate_on_press AndAlso pointer_part >= 0 Then _
                step_direction = IIf(pointer_part = SPINBUTTON_PART_INCREMENT, 1, -1)
        End If
        If pointer_part >= 0 Then _
            held_direction = IIf(pointer_part = SPINBUTTON_PART_INCREMENT, 1, -1)
    ElseIf spin_data->pointer_latch Then
        If pointer_part = spin_data->pressed_part AndAlso spin_data->activate_on_press = 0 Then
            If pointer_part = SPINBUTTON_PART_INCREMENT Then
                step_direction = 1
            ElseIf pointer_part = SPINBUTTON_PART_DECREMENT Then
                step_direction = -1
            End If
        End If
        spin_data->pointer_latch = 0
        spin_data->pressed_part = SPINBUTTON_NO_PART
    End If

    If w->has_focus Then
        If input_KeyPressEvent(KEY_UP) OrElse _
           input_KeyPressEvent(KEY_RIGHT) Then
            step_direction = 1
        ElseIf input_KeyPressEvent(KEY_DOWN) OrElse _
               input_KeyPressEvent(KEY_LEFT) Then
            step_direction = -1
        End If
        If input_KeyPressed(KEY_UP) OrElse input_KeyPressed(KEY_RIGHT) Then
            held_direction = 1
        ElseIf input_KeyPressed(KEY_DOWN) OrElse input_KeyPressed(KEY_LEFT) Then
            held_direction = -1
        End If
    End If
    If held_direction <> spin_data->repeat_direction OrElse step_direction <> 0 Then
        spin_data->repeat_direction = held_direction
        spin_data->repeat_elapsed_ms = 0
        spin_data->repeat_clock_initialized = 0
    End If
    If step_direction <> 0 Then
        spinbutton_Step w, step_direction
        Exit Sub
    End If
    If spin_data->automatic_repeat = 0 OrElse spin_data->repeat_interval_ms = 0 Then Exit Sub
    clock_now = CDbl(Timer)
    If spin_data->repeat_clock_initialized = 0 Then
        spin_data->repeat_clock = clock_now
        spin_data->repeat_clock_initialized = -1
        Exit Sub
    End If
    elapsed_ms = (clock_now - spin_data->repeat_clock) * 1000.0
    spin_data->repeat_clock = clock_now
    ' TIMER wraps at midnight; a long suspension coalesces to one opportunity.
    If elapsed_ms < 0 Then elapsed_ms += 86400000.0
    If elapsed_ms > 3600000.0 Then elapsed_ms = spin_data->repeat_interval_ms
    spinbutton_AdvanceRepeat w, elapsed_ms
End Sub


Sub spinbutton_Destroy(ByVal w As Widget Ptr)
    If w = 0 Then Exit Sub
    If w->data <> 0 Then Delete Cast(SpinButtonData Ptr, w->data)
    w->data = 0
End Sub


Function spinbutton_Create( _
    ByVal nm As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, _
    ByVal minimumValue As Integer, _
    ByVal maximumValue As Integer, _
    ByVal initialValue As Integer, _
    ByVal orientation As Integer, _
    ByVal changeHandler As Any Ptr _
) As Widget Ptr
    Dim As Widget Ptr result_widget
    Dim As SpinButtonData Ptr spin_data

    If minimumValue > maximumValue Then Return 0
    If initialValue < minimumValue OrElse initialValue > maximumValue Then _
        Return 0
    If orientation <> SPINBUTTON_VERTICAL AndAlso _
       orientation <> SPINBUTTON_HORIZONTAL Then Return 0
    If w < SPINBUTTON_MINIMUM_SIZE Then w = SPINBUTTON_MINIMUM_SIZE
    If h < SPINBUTTON_MINIMUM_SIZE Then h = SPINBUTTON_MINIMUM_SIZE

    result_widget = New Widget
    spin_data = New SpinButtonData
    If result_widget = 0 OrElse spin_data = 0 Then
        If result_widget <> 0 Then Delete result_widget
        If spin_data <> 0 Then Delete spin_data
        Return 0
    End If

    result_widget->name = nm
    result_widget->x = x
    result_widget->y = y
    result_widget->w = w
    result_widget->h = h
    result_widget->visible = -1
    result_widget->enabled = -1
    result_widget->accepts_focus = -1
    result_widget->render = @spinbutton_Render
    result_widget->update = @spinbutton_Update
    result_widget->activate = @spinbutton_Activate
    result_widget->destroy = @spinbutton_Destroy

    spin_data->minimum_value = minimumValue
    spin_data->maximum_value = maximumValue
    spin_data->current_value = initialValue
    spin_data->increment_value = 1
    spin_data->orientation = orientation
    spin_data->wrap_enabled = -1
    spin_data->pressed_part = SPINBUTTON_NO_PART
    spin_data->change_handler = changeHandler
    spin_data->automatic_repeat = -1
    result_widget->data = spin_data
    Return result_widget
End Function

' -------------------------------------------------------------------------
' Programmatic API
' -------------------------------------------------------------------------

Function spinbutton_GetValue(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Return Cast(SpinButtonData Ptr, w->data)->current_value
End Function


Function spinbutton_SetValue( _
    ByVal w As Widget Ptr, ByVal newValue As Integer _
) As Integer
    Dim As SpinButtonData Ptr spin_data

    If w = 0 OrElse w->data = 0 Then Return 0
    spin_data = Cast(SpinButtonData Ptr, w->data)
    If newValue < spin_data->minimum_value OrElse _
       newValue > spin_data->maximum_value Then Return 0
    spin_data->current_value = newValue
    Return -1
End Function


Function spinbutton_SetRange( _
    ByVal w As Widget Ptr, _
    ByVal minimumValue As Integer, ByVal maximumValue As Integer _
) As Integer
    Dim As SpinButtonData Ptr spin_data

    If w = 0 OrElse w->data = 0 Then Return 0
    If minimumValue > maximumValue Then Return 0

    spin_data = Cast(SpinButtonData Ptr, w->data)
    spin_data->minimum_value = minimumValue
    spin_data->maximum_value = maximumValue
    If spin_data->current_value < minimumValue Then _
        spin_data->current_value = minimumValue
    If spin_data->current_value > maximumValue Then _
        spin_data->current_value = maximumValue
    Return -1
End Function


Function spinbutton_SetIncrement( _
    ByVal w As Widget Ptr, ByVal incrementValue As Integer _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse incrementValue < 1 Then Return 0
    Cast(SpinButtonData Ptr, w->data)->increment_value = incrementValue
    Return -1
End Function


Sub spinbutton_SetWrap( _
    ByVal w As Widget Ptr, ByVal wrapEnabled As Integer _
)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Cast(SpinButtonData Ptr, w->data)->wrap_enabled = _
        IIf(wrapEnabled <> 0, -1, 0)
End Sub

Function spinbutton_SetOrientation(ByVal w As Widget Ptr, ByVal orientation As Integer) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    If orientation <> SPINBUTTON_VERTICAL AndAlso orientation <> SPINBUTTON_HORIZONTAL Then Return 0
    Cast(SpinButtonData Ptr, w->data)->orientation = orientation
    Return -1
End Function

Function spinbutton_SetStepHandler(ByVal w As Widget Ptr, ByVal stepHandler As Any Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(SpinButtonData Ptr, w->data)->step_handler = stepHandler
    Return -1
End Function

Function spinbutton_Step(ByVal w As Widget Ptr, ByVal directionValue As Integer) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    If w->enabled = 0 OrElse w->visible = 0 Then Return 0
    If directionValue <> -1 AndAlso directionValue <> 1 Then Return 0
    spinbutton_ChangeValue w, directionValue
    Return -1
End Function

Function spinbutton_SetRepeat(ByVal w As Widget Ptr, ByVal intervalMs As Long) As Integer
    If w = 0 OrElse w->data = 0 OrElse intervalMs < 0 OrElse intervalMs > 65535 Then Return 0
    With *Cast(SpinButtonData Ptr, w->data)
        .activate_on_press = -1
        If .repeat_interval_ms <> intervalMs Then
            .repeat_interval_ms = intervalMs
            .repeat_elapsed_ms = 0
            .repeat_clock_initialized = 0
        End If
    End With
    Return -1
End Function

Sub spinbutton_SetAutomaticRepeat(ByVal w As Widget Ptr, ByVal enabledState As Integer)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    With *Cast(SpinButtonData Ptr, w->data)
        .automatic_repeat = IIf(enabledState, -1, 0)
        .repeat_clock_initialized = 0
    End With
End Sub

Function spinbutton_AdvanceRepeat(ByVal w As Widget Ptr, ByVal elapsedMs As Double) As Integer
    Dim As SpinButtonData Ptr spin_data
    Dim As Integer direction_value
    If w = 0 OrElse w->data = 0 Then Return 0
    If elapsedMs <> elapsedMs OrElse elapsedMs < 0 OrElse elapsedMs > 86400000.0 Then Return 0
    spin_data = Cast(SpinButtonData Ptr, w->data)
    If w->enabled = 0 OrElse w->visible = 0 OrElse _
       spin_data->repeat_direction = 0 OrElse spin_data->repeat_interval_ms = 0 Then Return 0
    spin_data->repeat_elapsed_ms += elapsedMs
    If spin_data->repeat_elapsed_ms < spin_data->repeat_interval_ms Then Return 0
    ' Match TimerWidget: at most one callback per update, retaining the remainder.
    spin_data->repeat_elapsed_ms -= Fix(spin_data->repeat_elapsed_ms / _
        spin_data->repeat_interval_ms) * spin_data->repeat_interval_ms
    direction_value = spin_data->repeat_direction
    Return spinbutton_Step(w, direction_value)
End Function

/' end of spinbutton.bas '/
