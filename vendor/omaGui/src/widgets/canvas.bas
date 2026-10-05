/'
    Project: omaGUI
    ---------------

    File: canvas.bas

    Purpose:

        Implement a safe custom-drawing surface in the widget registry.

    Responsibilities:

        - clip caller rendering to the canvas rectangle
        - translate routed pointer input into canvas-relative coordinates
        - invoke optional caller render and update callbacks
        - count opt-in clicks after a routed press and release inside the canvas
        - release canvas metadata without taking ownership of caller context

    This file intentionally does NOT contain:

        - retained drawing commands
        - application geometry or animation state
        - backend selection

    Ownership:

        - the widget owns CanvasData and releases it during destruction
        - callback pointers and context are borrowed and never released here
'/

#lang "fb"

#include once "src/widgets/canvas.bi"

Const CANVAS_MINIMUM_DIMENSION As Integer = 1

' -------------------------------------------------------------------------
' Construction and callback dispatch
' -------------------------------------------------------------------------

Function canvas_Create( _
    ByVal widget_name As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal canvas_width As Integer, _
    ByVal canvas_height As Integer, _
    ByVal render_handler As Any Ptr, _
    ByVal update_handler As Any Ptr, _
    ByVal context As Any Ptr _
) As Widget Ptr
    Dim As CanvasData Ptr canvas_data
    Dim As Widget Ptr canvas_widget

    If canvas_width < CANVAS_MINIMUM_DIMENSION OrElse _
       canvas_height < CANVAS_MINIMUM_DIMENSION Then Return 0

    canvas_widget = New Widget
    canvas_data = New CanvasData
    If canvas_widget = 0 OrElse canvas_data = 0 Then
        If canvas_widget <> 0 Then Delete canvas_widget
        If canvas_data <> 0 Then Delete canvas_data
        Return 0
    End If

    canvas_widget->name = widget_name
    canvas_widget->x = left_position
    canvas_widget->y = top_position
    canvas_widget->w = canvas_width
    canvas_widget->h = canvas_height
    canvas_widget->visible = -1
    canvas_widget->enabled = -1
    canvas_widget->render = @canvas_Render
    canvas_widget->update = @canvas_Update
    canvas_widget->destroy = @canvas_Destroy
    canvas_widget->cancel_input = @canvas_CancelInput

    canvas_data->render_handler = render_handler
    canvas_data->update_handler = update_handler
    canvas_data->context = context
    canvas_data->pointer_x = -1
    canvas_data->pointer_y = -1
    canvas_widget->data = canvas_data
    Return canvas_widget
End Function


Sub canvas_Render(ByVal canvas_widget As Widget Ptr)
    Dim As CanvasData Ptr canvas_data

    If canvas_widget = 0 OrElse canvas_widget->data = 0 Then Exit Sub
    canvas_data = Cast(CanvasData Ptr, canvas_widget->data)
    If canvas_data->render_handler = 0 Then Exit Sub

    /'
        The manager clips against windows and the display. This nested clip
        additionally guarantees that application drawing cannot escape the
        canvas itself. The backend clip stack restores the manager's clip.
    '/
    backend_SetClip( _
        canvas_widget->ax, canvas_widget->ay, _
        canvas_widget->w, canvas_widget->h _
    )
    Cast(Sub(ByVal As Widget Ptr, ByVal As Any Ptr), _
        canvas_data->render_handler)(canvas_widget, canvas_data->context)
    backend_ResetClip
End Sub


Sub canvas_Update(ByVal canvas_widget As Widget Ptr)
    Dim As CanvasData Ptr canvas_data
    Dim As Integer pointer_x
    Dim As Integer pointer_y

    If canvas_widget = 0 OrElse canvas_widget->data = 0 Then Exit Sub
    canvas_data = Cast(CanvasData Ptr, canvas_widget->data)
    canvas_data->previous_pointer_buttons = canvas_data->pointer_buttons
    canvas_data->pointer_x = -1
    canvas_data->pointer_y = -1
    canvas_data->pointer_buttons = 0

    /'
        The GUI manager masks pointer getters for every widget except the
        routed target. A negative value therefore also means that a higher
        z-order widget owns this frame's pointer input.
    '/
    pointer_x = input_MouseX()
    pointer_y = input_MouseY()
    If pointer_x >= canvas_widget->ax AndAlso _
       pointer_x < canvas_widget->ax + canvas_widget->w AndAlso _
       pointer_y >= canvas_widget->ay AndAlso _
       pointer_y < canvas_widget->ay + canvas_widget->h Then
        canvas_data->pointer_x = pointer_x - canvas_widget->ax
        canvas_data->pointer_y = pointer_y - canvas_widget->ay
        canvas_data->pointer_buttons = input_MouseButtons()
    End If

    If canvas_data->clickable Then
        ' The manager retains pointer ownership through release, even outside
        ' this rectangle. Use its routed button state rather than the public
        ' inside-only canvas buttons, or leaving the rectangle looks like release.
        Dim As Integer buttons = input_MouseButtons()
        Dim As Integer inside = (canvas_data->pointer_x >= 0 AndAlso canvas_data->pointer_y >= 0)
        If (buttons And 1) AndAlso (canvas_data->click_previous_buttons And 1) = 0 Then
            canvas_data->click_armed = inside
        ElseIf (buttons And 1) = 0 AndAlso (canvas_data->click_previous_buttons And 1) Then
            If canvas_data->click_armed AndAlso inside Then canvas_data->activation_count += 1
            canvas_data->click_armed = 0
        End If
        canvas_data->click_previous_buttons = buttons
    End If

    If canvas_data->update_handler <> 0 Then
        Cast(Sub(ByVal As Widget Ptr, ByVal As Any Ptr), _
            canvas_data->update_handler)(canvas_widget, canvas_data->context)
    End If
End Sub

' -------------------------------------------------------------------------
' State access and lifecycle
' -------------------------------------------------------------------------

Sub canvas_CancelInput(ByVal canvas_widget As Widget Ptr)
    If canvas_widget = 0 OrElse canvas_widget->data = 0 OrElse canvas_widget->destroy <> @canvas_Destroy Then Exit Sub
    With *Cast(CanvasData Ptr, canvas_widget->data)
        .click_armed = 0
        ' Cancellation may run under another widget's dispatch mask. Retain
        ' physical buttons so re-enabling during this press cannot re-arm it.
        .click_previous_buttons = input_UnmaskedMouseButtons()
    End With
End Sub

Function canvas_SetClickable(ByVal canvas_widget As Widget Ptr, ByVal enabled As Integer) As Integer
    If canvas_widget = 0 OrElse canvas_widget->data = 0 OrElse canvas_widget->destroy <> @canvas_Destroy Then Return 0
    With *Cast(CanvasData Ptr, canvas_widget->data)
        .clickable = IIf(enabled, -1, 0)
        .click_armed = 0
        .click_previous_buttons = input_UnmaskedMouseButtons()
    End With
    Return -1
End Function

Function canvas_GetActivationCount(ByVal canvas_widget As Widget Ptr) As ULongInt
    If canvas_widget = 0 OrElse canvas_widget->data = 0 OrElse canvas_widget->destroy <> @canvas_Destroy Then Return 0
    Return Cast(CanvasData Ptr, canvas_widget->data)->activation_count
End Function

Sub canvas_Destroy(ByVal canvas_widget As Widget Ptr)
    If canvas_widget = 0 OrElse canvas_widget->data = 0 Then Exit Sub
    Delete Cast(CanvasData Ptr, canvas_widget->data)
    canvas_widget->data = 0
End Sub


Function canvas_GetPointerX(ByVal canvas_widget As Widget Ptr) As Integer
    If canvas_widget = 0 OrElse canvas_widget->data = 0 Then Return -1
    Return Cast(CanvasData Ptr, canvas_widget->data)->pointer_x
End Function


Function canvas_GetPointerY(ByVal canvas_widget As Widget Ptr) As Integer
    If canvas_widget = 0 OrElse canvas_widget->data = 0 Then Return -1
    Return Cast(CanvasData Ptr, canvas_widget->data)->pointer_y
End Function


Function canvas_GetPointerButtons( _
    ByVal canvas_widget As Widget Ptr _
) As Integer
    If canvas_widget = 0 OrElse canvas_widget->data = 0 Then Return 0
    Return Cast(CanvasData Ptr, canvas_widget->data)->pointer_buttons
End Function


Function canvas_GetPreviousPointerButtons( _
    ByVal canvas_widget As Widget Ptr _
) As Integer
    If canvas_widget = 0 OrElse canvas_widget->data = 0 Then Return 0
    Return Cast(CanvasData Ptr, canvas_widget->data)->previous_pointer_buttons
End Function


Function canvas_GetContext(ByVal canvas_widget As Widget Ptr) As Any Ptr
    If canvas_widget = 0 OrElse canvas_widget->data = 0 Then Return 0
    Return Cast(CanvasData Ptr, canvas_widget->data)->context
End Function


Sub canvas_SetContext( _
    ByVal canvas_widget As Widget Ptr, _
    ByVal context As Any Ptr _
)
    If canvas_widget = 0 OrElse canvas_widget->data = 0 Then Exit Sub
    Cast(CanvasData Ptr, canvas_widget->data)->context = context
End Sub


Sub canvas_SetFocusable( _
    ByVal canvas_widget As Widget Ptr, _
    ByVal focusable As Integer _
)
    If canvas_widget = 0 OrElse canvas_widget->data = 0 Then Exit Sub
    canvas_widget->accepts_focus = IIf(focusable, -1, 0)
    ' Removing keyboard ownership must not leave a hidden focus target that
    ' keeps receiving routed key events after the caller changes interaction.
    If canvas_widget->accepts_focus = 0 AndAlso canvas_widget->has_focus Then _
        gui_SetFocus 0
End Sub

/' end of canvas.bas '/
