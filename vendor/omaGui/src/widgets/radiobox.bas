/'
    Project: omaGUI
    ---------------
    File: radiobox.bas

    Purpose:
        RadioBox widget implementation with exclusivity logic.

    Responsibilities:
        - Render circular selection buttons
        - select through pointer, keyboard, or mnemonic activation
        - manage exclusive group selection logic
        - honor optional per-widget background and foreground colors

    This file intentionally does NOT contain:
        - application-specific option semantics
        - global focus and shortcut routing
'/

#lang "fb"

#include once "src/widgets/radiobox.bi"
#include once "src/backend/theme.bi"

Const RADIOBOX_DIAMETER As Integer = 12
Const RADIOBOX_CENTER_OFFSET As Integer = RADIOBOX_DIAMETER \ 2
Const RADIOBOX_OUTER_RADIUS As Integer = RADIOBOX_CENTER_OFFSET
Const RADIOBOX_INNER_RADIUS As Integer = RADIOBOX_OUTER_RADIUS - 1
Const RADIOBOX_SELECTED_RADIUS As Integer = RADIOBOX_INNER_RADIUS - 2

' -------------------------------------------------------------------------
' Construction
' -------------------------------------------------------------------------

Function radiobox_Create(ByVal nm As String, ByVal lbl As String, ByVal x As Integer, ByVal y As Integer, ByVal gid As Integer, ByVal s As Integer) As Widget Ptr
    Dim As Widget Ptr wgt = New Widget
    Dim As RadioBoxData Ptr d = New RadioBoxData

    If wgt = 0 OrElse d = 0 Then
        If wgt <> 0 Then Delete wgt
        If d <> 0 Then Delete d
        Return 0
    End If

    wgt->name = nm : wgt->x = x : wgt->y = y : wgt->w = RADIOBOX_DIAMETER : wgt->h = RADIOBOX_DIAMETER
    wgt->visible = 1 : wgt->enabled = 1 : wgt->render = @radiobox_Render : wgt->update = @radiobox_Update : wgt->destroy = @radiobox_Destroy
    wgt->accepts_focus = -1
    wgt->activate = @radiobox_Activate

    d->label = gui_TransformText(lbl) : d->group_id = gid : d->selected = IIf(s, 1, 0) : d->last_mb = 0
    wgt->w = RADIOBOX_DIAMETER + 4 + backend_GetTextWidth(d->label)
    wgt->h = backend_GetTextHeight()
    If wgt->h < RADIOBOX_DIAMETER Then wgt->h = RADIOBOX_DIAMETER
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

Sub radiobox_Render(ByVal w As Widget Ptr)
    Dim As ULong background_color
    Dim As RadioBoxData Ptr d
    Dim As ULong foreground_color

    If w = 0 OrElse w->data = 0 Then Exit Sub
    d = Cast(RadioBoxData Ptr, w->data)
    background_color = current_theme.bg_light
    foreground_color = current_theme.text_main
    If d->background_color_override <> 0 Then
        background_color = d->background_color
        If w->w > 0 AndAlso w->h > 0 Then _
            backend_Rect w->ax, w->ay, w->w, w->h, background_color, 1
    End If
    If d->foreground_color_override <> 0 Then _
        foreground_color = d->foreground_color

    backend_Circle(w->ax + RADIOBOX_CENTER_OFFSET, w->ay + RADIOBOX_CENTER_OFFSET, RADIOBOX_OUTER_RADIUS, current_theme.bg_dark, 0)
    backend_Circle(w->ax + RADIOBOX_CENTER_OFFSET, w->ay + RADIOBOX_CENTER_OFFSET, RADIOBOX_INNER_RADIUS, background_color, 1)

    If d->selected Then
        Dim As ULong dot_color = foreground_color
        If d->foreground_color_override = 0 AndAlso _
           current_theme.control_style = GUI_CONTROL_STYLE_FLAT Then _
            dot_color = current_theme.bg_select
        backend_Circle(w->ax + RADIOBOX_CENTER_OFFSET, w->ay + RADIOBOX_CENTER_OFFSET, RADIOBOX_SELECTED_RADIUS, dot_color, 1)
    End If

    backend_Print(w->ax + 16, w->ay, foreground_color, d->label)
    gui_RenderMnemonicUnderline _
        w, d->label, w->ax + 16, w->ay, backend_GetTextHeight()
End Sub

' -------------------------------------------------------------------------
' Public color API
' -------------------------------------------------------------------------

Function radiobox_SetBackgroundColor( _
    ByVal w As Widget Ptr, ByVal background_color As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(RadioBoxData Ptr, w->data)
        .background_color = background_color
        .background_color_override = -1
    End With
    Return -1
End Function


Function radiobox_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(RadioBoxData Ptr, w->data)->background_color_override = 0
    Return -1
End Function


Function radiobox_GetBackgroundColor( _
    ByVal w As Widget Ptr, ByRef background_color As ULong _
) As Integer
    Dim As RadioBoxData Ptr radio_data

    background_color = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    radio_data = Cast(RadioBoxData Ptr, w->data)
    If radio_data->background_color_override = 0 Then Return 0
    background_color = radio_data->background_color
    Return -1
End Function


Function radiobox_SetForegroundColor( _
    ByVal w As Widget Ptr, ByVal foreground_color As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(RadioBoxData Ptr, w->data)
        .foreground_color = foreground_color
        .foreground_color_override = -1
    End With
    Return -1
End Function


Function radiobox_ClearForegroundColor(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(RadioBoxData Ptr, w->data)->foreground_color_override = 0
    Return -1
End Function


Function radiobox_GetForegroundColor( _
    ByVal w As Widget Ptr, ByRef foreground_color As ULong _
) As Integer
    Dim As RadioBoxData Ptr radio_data

    foreground_color = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    radio_data = Cast(RadioBoxData Ptr, w->data)
    If radio_data->foreground_color_override = 0 Then Return 0
    foreground_color = radio_data->foreground_color
    Return -1
End Function

' -------------------------------------------------------------------------
' Processing
' -------------------------------------------------------------------------

Sub radiobox_Activate(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As RadioBoxData Ptr d = Cast(RadioBoxData Ptr, w->data)
    d->selected = 1
    d->activation_count += 1
    gui_DeselectRadioGroup d->group_id, w
End Sub

Function radiobox_SetSelected(ByVal w As Widget Ptr, ByVal selected As Integer) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Dim As RadioBoxData Ptr d = w->data
    d->selected = IIf(selected, 1, 0)
    If d->selected Then gui_DeselectRadioGroup d->group_id, w
    Return -1
End Function

Function radiobox_GetSelected(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Return IIf(Cast(RadioBoxData Ptr, w->data)->selected, -1, 0)
End Function

Function radiobox_GetActivationCount(ByVal w As Widget Ptr) As ULongInt
    If w = 0 OrElse w->data = 0 Then Return 0
    Return Cast(RadioBoxData Ptr, w->data)->activation_count
End Function

Sub radiobox_Update(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As RadioBoxData Ptr d = w->data
    Dim As Integer mx = input_MouseX()
    Dim As Integer my = input_MouseY()
    Dim As Integer mb = (input_MouseButtons() And 1)

    Dim As Integer inside_control = mx >= w->ax AndAlso mx < w->ax + w->w AndAlso _
        my >= w->ay AndAlso my < w->ay + w->h
    ' Include the label without squaring unbounded pointer coordinates.
    ' Selection is published only on a captured release inside this control.
    If mb <> 0 AndAlso d->last_mb = 0 Then
        d->pointer_armed = inside_control
    ElseIf mb = 0 AndAlso d->last_mb <> 0 Then
        If d->pointer_armed AndAlso inside_control Then radiobox_Activate w
        d->pointer_armed = 0
    End If
    d->last_mb = mb

    If w->has_focus <> 0 AndAlso _
       input_KeyPressEvent(FB.SC_SPACE) <> 0 Then
        radiobox_Activate w
    End If
End Sub

' -------------------------------------------------------------------------
' Lifecycle
' -------------------------------------------------------------------------

Sub radiobox_Destroy(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Delete Cast(RadioBoxData Ptr, w->data)
    w->data = 0
End Sub

Function radiobox_SetText( _
    ByVal w As Widget Ptr, ByRef text_value As Const String _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @radiobox_Destroy Then _
        Return 0
    Cast(RadioBoxData Ptr, w->data)->label = gui_TransformText(text_value)
    w->w = RADIOBOX_DIAMETER + 4 + backend_GetTextWidth(Cast(RadioBoxData Ptr, w->data)->label)
    w->h = backend_GetTextHeight()
    If w->h < RADIOBOX_DIAMETER Then w->h = RADIOBOX_DIAMETER
    Return -1
End Function

Function radiobox_GetText(ByVal w As Widget Ptr) As String
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @radiobox_Destroy Then _
        Return ""
    Return Cast(RadioBoxData Ptr, w->data)->label
End Function

' end of radiobox.bas
