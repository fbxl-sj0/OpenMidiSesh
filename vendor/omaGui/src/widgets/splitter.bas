/'
    Project: omaGUI
    File: splitter.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements splitter.bi; declarations there define the interface.
    Purpose: Implement a portable divider controlled by mouse or keyboard.
    Responsibilities:
        - preserve the grab offset and clamp movement to the host's range
        - cancel captures across hidden, disabled, and modal transitions
        - draw the grip using the active theme and backend primitives
        - notify application layout code safely on the GUI thread
    This file intentionally does NOT contain:
        - sibling ownership, persisted pane sizes, or native host controls
'/

#lang "fb"
#include once "src/widgets/splitter.bi"
#include once "src/backend/theme.bi"

Const SPLITTER_KEY_STEP As Integer = 4
Const SPLITTER_LARGE_KEY_STEP As Integer = 16

' -------------------------------------------------------------------------
' Checked metadata and programmatic geometry
' -------------------------------------------------------------------------

Private Function splitter_Data(ByVal w As Widget Ptr) As SplitterData Ptr
    If w = 0 Then Return 0
    If w->destroy <> @splitter_Destroy Then Return 0
    Return Cast(SplitterData Ptr, w->data)
End Function

Private Sub splitter_CancelInput(ByVal w As Widget Ptr)
    Dim As SplitterData Ptr d = splitter_Data(w)
    If d = 0 Then Exit Sub
    d->dragging = 0
    ' A press interrupted by a modal dialog must be released before it can
    ' start another drag, even if the divider becomes available while held.
    d->pointer_latch = IIf((input_UnmaskedMouseButtons() And 1) <> 0, -1, 0)
End Sub

Function splitter_GetPosition(ByVal w As Widget Ptr) As Integer
    Dim As SplitterData Ptr d = splitter_Data(w)
    If d = 0 Then Return -1
    If d->orientation = SPLITTER_VERTICAL Then Return w->x
    Return w->y
End Function

Function splitter_SetPosition( _
    ByVal w As Widget Ptr, ByVal position As Integer _
) As Integer
    Dim As SplitterData Ptr d = splitter_Data(w)
    If d = 0 Then Return 0
    If position < d->minimum_position Then position = d->minimum_position
    If position > d->maximum_position Then position = d->maximum_position
    If position = splitter_GetPosition(w) Then Return -1
    If d->orientation = SPLITTER_VERTICAL Then
        w->x = position
    Else
        w->y = position
    End If
    ' Rebase opt-in anchors after a manual move, just as the manager does
    ' for rectangles changed inside an update callback.
    If w->layout_initialized Then gui_SetAnchors w, w->anchor_flags
    gui_SynchronizeLayout
    Return -1
End Function

Function splitter_SetRange( _
    ByVal w As Widget Ptr, _
    ByVal minimum_position As Integer, ByVal maximum_position As Integer _
) As Integer
    Dim As SplitterData Ptr d = splitter_Data(w)
    If d = 0 Then Return 0
    If minimum_position < 0 OrElse maximum_position < minimum_position OrElse _
       maximum_position > SPLITTER_MAXIMUM_EXTENT Then Return 0
    d->minimum_position = minimum_position
    d->maximum_position = maximum_position
    Return splitter_SetPosition(w, splitter_GetPosition(w))
End Function

Function splitter_GetRange( _
    ByVal w As Widget Ptr, _
    ByRef minimum_position As Integer, ByRef maximum_position As Integer _
) As Integer
    Dim As SplitterData Ptr d = splitter_Data(w)
    minimum_position = 0
    maximum_position = 0
    If d = 0 Then Return 0
    minimum_position = d->minimum_position
    maximum_position = d->maximum_position
    Return -1
End Function

Function splitter_IsDragging(ByVal w As Widget Ptr) As Integer
    Dim As SplitterData Ptr d = splitter_Data(w)
    If d = 0 Then Return 0
    Return d->dragging
End Function

Function splitter_SetChangeHandler( _
    ByVal w As Widget Ptr, ByVal handler As SplitterChangeHandler, _
    ByVal context As Any Ptr _
) As Integer
    Dim As SplitterData Ptr d = splitter_Data(w)
    If d = 0 Then Return 0
    d->change_handler = handler
    d->change_context = context
    Return -1
End Function

' -------------------------------------------------------------------------
' Input, capture, and callbacks
' -------------------------------------------------------------------------

Private Sub splitter_ChangePosition(ByVal w As Widget Ptr, ByVal position As Double)
    Dim As SplitterData Ptr d = splitter_Data(w)
    Dim As SplitterChangeHandler handler
    Dim As Any Ptr context
    Dim As Integer bounded_position
    If d = 0 Then Exit Sub
    ' Widen pointer arithmetic before subtracting. Extreme mocked coordinates
    ' must reach a range endpoint without overflowing a native-sized integer.
    If position < d->minimum_position Then position = d->minimum_position
    If position > d->maximum_position Then position = d->maximum_position
    bounded_position = CInt(position)
    If bounded_position = splitter_GetPosition(w) Then Exit Sub
    handler = d->change_handler
    context = d->change_context
    splitter_SetPosition w, bounded_position
    ' A callback may delete this divider or its complete window. Do not touch
    ' either allocation after invoking it, including from the caller.
    If handler <> 0 Then handler(context, bounded_position)
End Sub

Private Sub splitter_Keyboard(ByVal w As Widget Ptr, ByVal d As SplitterData Ptr)
    Dim As Integer decrease_key, increase_key, pressed_key, step_size
    Dim As Double position = splitter_GetPosition(w)
    If w->has_focus = 0 Then Exit Sub
    If input_KeyPressed(FB.SC_CONTROL) OrElse input_KeyPressed(FB.SC_ALT) Then Exit Sub
    decrease_key = IIf(d->orientation = SPLITTER_VERTICAL, KEY_LEFT, KEY_UP)
    increase_key = IIf(d->orientation = SPLITTER_VERTICAL, KEY_RIGHT, KEY_DOWN)
    If input_KeyPressEvent(KEY_HOME) Then
        pressed_key = KEY_HOME
    ElseIf input_KeyPressEvent(KEY_END) Then
        pressed_key = KEY_END
    ElseIf input_KeyPressEvent(decrease_key) Then
        pressed_key = decrease_key
    ElseIf input_KeyPressEvent(increase_key) Then
        pressed_key = increase_key
    Else
        Exit Sub
    End If
    If input_ModifiedKeyPressEvent(pressed_key, INPUT_MODIFIER_CONTROL) OrElse _
       input_ModifiedKeyPressEvent(pressed_key, INPUT_MODIFIER_ALT) Then Exit Sub
    Select Case pressed_key
    Case KEY_HOME
        position = d->minimum_position
    Case KEY_END
        position = d->maximum_position
    Case Else
        step_size = SPLITTER_KEY_STEP
        If input_ModifiedKeyPressEvent(pressed_key, INPUT_MODIFIER_SHIFT) Then _
            step_size = SPLITTER_LARGE_KEY_STEP
        If pressed_key = decrease_key Then step_size = -step_size
        position += step_size
    End Select
    splitter_ChangePosition w, position
End Sub

Sub splitter_Update(ByVal w As Widget Ptr)
    Dim As SplitterData Ptr d = splitter_Data(w)
    Dim As Integer pointer_axis, buttons, inside_widget
    Dim As Double position
    If d = 0 Then Exit Sub
    If w->visible = 0 OrElse w->enabled = 0 Then
        splitter_CancelInput w
        Exit Sub
    End If
    buttons = input_MouseButtons()
    pointer_axis = IIf(d->orientation = SPLITTER_VERTICAL, input_MouseX(), input_MouseY())
    If d->dragging Then
        If gui_IsPointerTarget(w) = 0 Then
            splitter_CancelInput w
            Exit Sub
        End If
        position = CDbl(d->drag_start_position) + CDbl(pointer_axis) - CDbl(d->drag_origin)
        If (buttons And 1) = 0 Then
            d->dragging = 0
            d->pointer_latch = 0
        End If
        splitter_ChangePosition w, position
        Exit Sub
    End If
    If (input_UnmaskedMouseButtons() And 1) = 0 Then d->pointer_latch = 0
    inside_widget = input_MouseX() >= w->ax AndAlso _
        CDbl(input_MouseX()) - w->ax < w->w AndAlso _
        input_MouseY() >= w->ay AndAlso CDbl(input_MouseY()) - w->ay < w->h
    If (buttons And 1) <> 0 AndAlso d->pointer_latch = 0 AndAlso _
       gui_IsPointerTarget(w) AndAlso inside_widget Then
        d->pointer_latch = -1
        d->dragging = -1
        d->drag_origin = pointer_axis
        d->drag_start_position = splitter_GetPosition(w)
        Exit Sub
    End If
    splitter_Keyboard w, d
End Sub

' -------------------------------------------------------------------------
' Rendering and lifetime
' -------------------------------------------------------------------------

Sub splitter_Render(ByVal w As Widget Ptr)
    Dim As SplitterData Ptr d = splitter_Data(w)
    Dim As Integer middle_x, middle_y
    Dim As ULong grip_color
    If d = 0 OrElse w->w < 1 OrElse w->h < 1 Then Exit Sub
    grip_color = current_theme.bg_dark
    If d->dragging OrElse (w->has_focus AndAlso gui_IsKeyboardNavigationActive()) Then _
        grip_color = current_theme.bg_select
    backend_Rect w->ax, w->ay, w->w, w->h, current_theme.bg_face, -1
    middle_x = w->ax + w->w \ 2
    middle_y = w->ay + w->h \ 2
    ' Short paired strokes provide a visible grab point in both orientations.
    If d->orientation = SPLITTER_VERTICAL Then
        If w->w < 4 OrElse w->h < 18 Then Exit Sub
        For offset As Integer = -6 To 6 Step 6
            backend_Line middle_x - 1, middle_y + offset, middle_x + 1, middle_y + offset, grip_color
            backend_Line middle_x - 1, middle_y + offset + 1, middle_x + 1, middle_y + offset + 1, current_theme.bg_light
        Next offset
    Else
        If w->h < 4 OrElse w->w < 18 Then Exit Sub
        For offset As Integer = -6 To 6 Step 6
            backend_Line middle_x + offset, middle_y - 1, middle_x + offset, middle_y + 1, grip_color
            backend_Line middle_x + offset + 1, middle_y - 1, middle_x + offset + 1, middle_y + 1, current_theme.bg_light
        Next offset
    End If
End Sub

Function splitter_Create( _
    ByVal widget_name As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, ByVal orientation As Integer _
) As Widget Ptr
    Dim As Widget Ptr result
    Dim As SplitterData Ptr d
    If orientation <> SPLITTER_VERTICAL AndAlso orientation <> SPLITTER_HORIZONTAL Then Return 0
    If x < 0 OrElse y < 0 OrElse x > SPLITTER_MAXIMUM_EXTENT OrElse _
       y > SPLITTER_MAXIMUM_EXTENT OrElse w < 1 OrElse h < 1 OrElse _
       w > SPLITTER_MAXIMUM_EXTENT OrElse h > SPLITTER_MAXIMUM_EXTENT Then Return 0
    result = New Widget
    If result = 0 Then Return 0
    d = New SplitterData
    If d = 0 Then
        Delete result
        Return 0
    End If
    result->name = widget_name
    result->x = x
    result->y = y
    result->ax = x
    result->ay = y
    result->w = w
    result->h = h
    result->visible = -1
    result->enabled = -1
    result->accepts_focus = -1
    result->data = d
    result->update = @splitter_Update
    result->render = @splitter_Render
    result->destroy = @splitter_Destroy
    result->cancel_input = @splitter_CancelInput
    d->orientation = orientation
    d->maximum_position = SPLITTER_MAXIMUM_EXTENT
    Return result
End Function

Sub splitter_Destroy(ByVal w As Widget Ptr)
    Dim As SplitterData Ptr d = splitter_Data(w)
    If d = 0 Then Exit Sub
    Delete d
    w->data = 0
End Sub

/' end of splitter.bas '/
