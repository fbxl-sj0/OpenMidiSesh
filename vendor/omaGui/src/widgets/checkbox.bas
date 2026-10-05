/'
    Project: omaGUI
    ---------------
    File: checkbox.bas

    Purpose:
        Checkbox widget implementation.

    Responsibilities:
        - render a standard checkbox with bevel effects
        - toggle through pointer, keyboard, or mnemonic activation
        - retain the checked state
        - honor optional per-widget background and foreground colors

    This file intentionally does NOT contain:
        - application-specific boolean semantics
        - global focus and shortcut routing
'/

#lang "fb"
#include once "src/widgets/checkbox.bi"
#include once "src/backend/theme.bi"

Const CHECKBOX_SIZE As Integer = 12
Const CHECKBOX_BORDER_WIDTH As Integer = 1
Const CHECKBOX_INNER_SIZE As Integer = CHECKBOX_SIZE - CHECKBOX_BORDER_WIDTH * 2
Const CHECKBOX_TICK_INSET As Integer = CHECKBOX_BORDER_WIDTH * 2
Const CHECKBOX_TICK_END_OFFSET As Integer = CHECKBOX_SIZE - CHECKBOX_TICK_INSET - 1
Const CHECKBOX_MIXED_WIDTH As Integer = 6
Const CHECKBOX_MIXED_HEIGHT As Integer = 2

' -------------------------------------------------------------------------
' Construction
' -------------------------------------------------------------------------

Function checkbox_Create(ByVal nm As String, ByVal lbl As String, ByVal x As Integer, ByVal y As Integer, ByVal checked As Integer) As Widget Ptr
    Dim As Widget Ptr wgt = New Widget
    Dim As CheckBoxData Ptr d = New CheckBoxData

    If wgt = 0 OrElse d = 0 Then
        If wgt <> 0 Then Delete wgt
        If d <> 0 Then Delete d
        Return 0
    End If

    wgt->name = nm : wgt->x = x : wgt->y = y : wgt->w = CHECKBOX_SIZE : wgt->h = CHECKBOX_SIZE
    wgt->visible = 1 : wgt->enabled = 1 : wgt->render = @checkbox_Render : wgt->update = @checkbox_Update : wgt->destroy = @checkbox_Destroy
    wgt->accepts_focus = -1
    wgt->activate = @checkbox_Activate

    d->label = gui_TransformText(lbl) : d->checked = IIf(checked, -1, 0) : d->last_mb = 0
    ' The label is part of the pointer target, not just decoration.
    wgt->w = CHECKBOX_SIZE + 4 + backend_GetTextWidth(d->label)
    wgt->h = backend_GetTextHeight()
    If wgt->h < CHECKBOX_SIZE Then wgt->h = CHECKBOX_SIZE
    d->background_color_override = 0
    d->foreground_color_override = 0
    d->background_color = 0
    d->foreground_color = 0

    wgt->data = d
    Return wgt
End Function

' -------------------------------------------------------------------------
' Rendering
' -------------------------------------------------------------------------

Sub checkbox_Render(ByVal w As Widget Ptr)
    Dim As ULong background_color
    Dim As CheckBoxData Ptr d
    Dim As ULong foreground_color

    If w = 0 OrElse w->data = 0 Then Exit Sub
    d = Cast(CheckBoxData Ptr, w->data)
    background_color = current_theme.bg_light
    foreground_color = current_theme.text_main
    If d->background_color_override <> 0 Then
        background_color = d->background_color
        If w->w > 0 AndAlso w->h > 0 Then _
            backend_Rect w->ax, w->ay, w->w, w->h, background_color, 1
    End If
    If d->foreground_color_override <> 0 Then _
        foreground_color = d->foreground_color

    If current_theme.control_style = GUI_CONTROL_STYLE_FLAT Then
        Dim As ULong boxColor = current_theme.bg_face
        Dim As ULong borderColor = current_theme.bg_dark
        Dim As ULong tickColor = foreground_color
        If d->checked <> 0 Then
            boxColor = current_theme.bg_select
            borderColor = current_theme.bg_select
            If d->foreground_color_override = 0 Then tickColor = current_theme.text_select
        ElseIf w->has_focus <> 0 Then
            borderColor = current_theme.bg_select
        End If
        If w->enabled = 0 Then borderColor = current_theme.bg_dark
        backend_RoundRect(w->ax, w->ay, CHECKBOX_SIZE, CHECKBOX_SIZE, 2, boxColor, 1)
        backend_RoundRect(w->ax, w->ay, CHECKBOX_SIZE, CHECKBOX_SIZE, 2, borderColor, 0)
        If d->mixed Then
            backend_Rect( _
                w->ax + (CHECKBOX_SIZE - CHECKBOX_MIXED_WIDTH) \ 2, _
                w->ay + (CHECKBOX_SIZE - CHECKBOX_MIXED_HEIGHT) \ 2, _
                CHECKBOX_MIXED_WIDTH, CHECKBOX_MIXED_HEIGHT, tickColor, 1 _
            )
        ElseIf d->checked <> 0 Then
            backend_Line(w->ax + 2, w->ay + 6, w->ax + 4, w->ay + 8, tickColor)
            backend_Line(w->ax + 4, w->ay + 8, w->ax + 9, w->ay + 3, tickColor)
        End If
        backend_PrintFontAlpha( _
            w->ax + 16, w->ay, foreground_color, d->label, _
            BACKEND_FONT_DEFAULT, IIf(w->enabled <> 0, 255, 140) _
        )
        If w->enabled <> 0 Then gui_RenderMnemonicUnderline _
            w, d->label, w->ax + 16, w->ay, backend_GetTextHeight()
        Exit Sub
    End If

    backend_Rect(w->ax, w->ay, CHECKBOX_SIZE, CHECKBOX_SIZE, current_theme.bg_dark, 0)
    backend_Rect(w->ax + CHECKBOX_BORDER_WIDTH, w->ay + CHECKBOX_BORDER_WIDTH, CHECKBOX_INNER_SIZE, CHECKBOX_INNER_SIZE, background_color, 1)

    If d->mixed Then
        backend_Rect( _
            w->ax + (CHECKBOX_SIZE - CHECKBOX_MIXED_WIDTH) \ 2, _
            w->ay + (CHECKBOX_SIZE - CHECKBOX_MIXED_HEIGHT) \ 2, _
            CHECKBOX_MIXED_WIDTH, CHECKBOX_MIXED_HEIGHT, foreground_color, 1 _
        )
    ElseIf d->checked Then
        backend_Line(w->ax + CHECKBOX_TICK_INSET, w->ay + CHECKBOX_TICK_INSET, w->ax + CHECKBOX_TICK_END_OFFSET, w->ay + CHECKBOX_TICK_END_OFFSET, foreground_color)
        backend_Line(w->ax + CHECKBOX_TICK_END_OFFSET, w->ay + CHECKBOX_TICK_INSET, w->ax + CHECKBOX_TICK_INSET, w->ay + CHECKBOX_TICK_END_OFFSET, foreground_color)
    End If

    backend_Print(w->ax + 16, w->ay, foreground_color, d->label)
    gui_RenderMnemonicUnderline _
        w, d->label, w->ax + 16, w->ay, backend_GetTextHeight()
End Sub

' -------------------------------------------------------------------------
' Public color API
' -------------------------------------------------------------------------

Function checkbox_SetBackgroundColor( _
    ByVal w As Widget Ptr, ByVal background_color As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(CheckBoxData Ptr, w->data)
        .background_color = background_color
        .background_color_override = -1
    End With
    Return -1
End Function


Function checkbox_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(CheckBoxData Ptr, w->data)->background_color_override = 0
    Return -1
End Function


Function checkbox_GetBackgroundColor( _
    ByVal w As Widget Ptr, ByRef background_color As ULong _
) As Integer
    Dim As CheckBoxData Ptr check_data

    background_color = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    check_data = Cast(CheckBoxData Ptr, w->data)
    If check_data->background_color_override = 0 Then Return 0
    background_color = check_data->background_color
    Return -1
End Function


Function checkbox_SetForegroundColor( _
    ByVal w As Widget Ptr, ByVal foreground_color As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(CheckBoxData Ptr, w->data)
        .foreground_color = foreground_color
        .foreground_color_override = -1
    End With
    Return -1
End Function


Function checkbox_ClearForegroundColor(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(CheckBoxData Ptr, w->data)->foreground_color_override = 0
    Return -1
End Function


Function checkbox_GetForegroundColor( _
    ByVal w As Widget Ptr, ByRef foreground_color As ULong _
) As Integer
    Dim As CheckBoxData Ptr check_data

    foreground_color = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    check_data = Cast(CheckBoxData Ptr, w->data)
    If check_data->foreground_color_override = 0 Then Return 0
    foreground_color = check_data->foreground_color
    Return -1
End Function

' -------------------------------------------------------------------------
' Processing
' -------------------------------------------------------------------------

Sub checkbox_Activate(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As CheckBoxData Ptr d = Cast(CheckBoxData Ptr, w->data)
    ' A mixed checkbox represents an indeterminate value. A deliberate user
    ' action resolves it to checked before subsequent actions toggle normally.
    d->mixed = 0
    d->checked = IIf(d->checked, 0, -1)
    d->activation_count += 1
End Sub

Function checkbox_SetChecked(ByVal w As Widget Ptr, ByVal checked As Integer) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(CheckBoxData Ptr, w->data)
        .checked = IIf(checked, -1, 0)
        .mixed = 0
    End With
    Return -1
End Function

Function checkbox_GetChecked(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Return IIf(Cast(CheckBoxData Ptr, w->data)->checked, -1, 0)
End Function


Function checkbox_SetValue(ByVal w As Widget Ptr, ByVal value As Integer) As Integer
    Dim As CheckBoxData Ptr check_data

    If w = 0 OrElse w->data = 0 OrElse _
       (value <> 0 AndAlso value <> 1 AndAlso value <> 2) Then Return 0
    check_data = Cast(CheckBoxData Ptr, w->data)
    check_data->checked = IIf(value = 1, -1, 0)
    check_data->mixed = IIf(value = 2, -1, 0)
    Return -1
End Function


Function checkbox_GetValue(ByVal w As Widget Ptr) As Integer
    Dim As CheckBoxData Ptr check_data

    If w = 0 OrElse w->data = 0 Then Return 0
    check_data = Cast(CheckBoxData Ptr, w->data)
    If check_data->mixed Then Return 2
    Return IIf(check_data->checked, 1, 0)
End Function

Function checkbox_GetActivationCount(ByVal w As Widget Ptr) As ULongInt
    If w = 0 OrElse w->data = 0 Then Return 0
    Return Cast(CheckBoxData Ptr, w->data)->activation_count
End Function

Sub checkbox_Update(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As CheckBoxData Ptr d = w->data
    Dim As Integer mx = input_MouseX()
    Dim As Integer my = input_MouseY()
    Dim As Integer mb = (input_MouseButtons() And 1)

    Dim As Integer inside_control = mx >= w->ax AndAlso mx < w->ax + w->w AndAlso _
        my >= w->ay AndAlso my < w->ay + w->h
    ' The label participates in the hit rectangle. Keep the same captured,
    ' release-inside contract as buttons, including cancellation outside.
    If mb <> 0 AndAlso d->last_mb = 0 Then
        d->pointer_armed = inside_control
    ElseIf mb = 0 AndAlso d->last_mb <> 0 Then
        If d->pointer_armed AndAlso inside_control Then checkbox_Activate w
        d->pointer_armed = 0
    End If
    d->last_mb = mb

    If w->has_focus <> 0 AndAlso _
       input_KeyPressEvent(FB.SC_SPACE) <> 0 Then
        checkbox_Activate w
    End If
End Sub

' -------------------------------------------------------------------------
' Lifecycle
' -------------------------------------------------------------------------

Sub checkbox_Destroy(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Delete Cast(CheckBoxData Ptr, w->data)
    w->data = 0
End Sub

Function checkbox_SetText( _
    ByVal w As Widget Ptr, ByRef text_value As Const String _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @checkbox_Destroy Then _
        Return 0
    Cast(CheckBoxData Ptr, w->data)->label = text_value
    Return -1
End Function

Function checkbox_GetText(ByVal w As Widget Ptr) As String
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @checkbox_Destroy Then _
        Return ""
    Return Cast(CheckBoxData Ptr, w->data)->label
End Function

' end of checkbox.bas
