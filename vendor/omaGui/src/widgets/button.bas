/'
    Project: omaGUI
    ---------------

    File: button.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements button.bi; declarations there define the interface.

    Purpose:

        Implement the classic push-button widget.

    Responsibilities:

        - render normal, hover, and pressed button states
        - honor an optional caller-supplied face color
        - keep classic button labels readable across mixed palette colors
        - convert a completed pointer press or keyboard command into activation
        - invoke the optional application callback
        - deliver mutable keyboard bytes before the default activation
        - bracket byte processing with scan-code Down/Up notifications

    This file intentionally does NOT contain:

        - global pointer routing
        - application command policy
'/

#lang "fb"
#include once "src/widgets/button.bi"
#include once "src/backend/theme.bi"
#include once "src/widgets/control_keyevents.bi"

' Callbacks may enter a nested GUI update. Do not recursively deliver the
' same button notifications while their owning GUI-thread callback is active.
Dim Shared As Integer button_key_event_depth

' -------------------------------------------------------------------------
' Construction
' -------------------------------------------------------------------------

Function button_Create(ByVal nm As String, ByVal txt As String, ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, ByVal clickHandler As Any Ptr) As Widget Ptr
    Dim As Widget Ptr wgt = New Widget
    Dim As ButtonData Ptr d = New ButtonData

    If wgt = 0 OrElse d = 0 Then
        If wgt <> 0 Then Delete wgt
        If d <> 0 Then Delete d
        Return 0
    End If
    wgt->name = nm
    wgt->x = x
    wgt->y = y
    wgt->w = w
    wgt->h = h
    wgt->visible = 1
    wgt->enabled = 1
    wgt->render = @button_Render
    wgt->update = @button_Update
    wgt->activate = @button_Activate
    wgt->cancel_input = @button_CancelInput
    wgt->destroy = @button_Destroy
    wgt->accepts_focus = -1
    wgt->captures_return = -1
    d->text = gui_TransformText(txt)
    d->pressed = 0
    d->state = 0
    d->background_color_override = 0
    d->background_color = 0
    d->default_outline_visible = -1
    d->clickHandler = clickHandler
    d->key_press_handler = 0
    d->key_down_handler = 0
    d->key_up_handler = 0
    wgt->data = d
    Return wgt
End Function

' -------------------------------------------------------------------------
' Rendering and input
' -------------------------------------------------------------------------

' Ordinary button labels use the 4.5:1 text target. Disabled labels aim a
' little higher so integer channel rounding cannot drop them below that target.
Private Const BUTTON_TEXT_MINIMUM_CONTRAST As Double = 4.5
Private Const BUTTON_DISABLED_TARGET_CONTRAST As Double = 5.0
Private Const BUTTON_CONTRAST_LUMINANCE_OFFSET As Double = 0.05

Private Function button_LinearColorChannel(ByVal channel_value As ULong) As Double
    Const SRGB_LOW_LIMIT As Double = 0.04045
    Const SRGB_LOW_SCALE As Double = 12.92
    Const SRGB_OFFSET As Double = 0.055
    Const SRGB_SCALE As Double = 1.055
    Const SRGB_EXPONENT As Double = 2.4
    Dim As Double normalized_value = CDbl(channel_value) / 255.0

    ' These constants are the standard sRGB transfer curve used by relative
    ' luminance. Linear channels are required before colors can be compared.
    If normalized_value <= SRGB_LOW_LIMIT Then _
        Return normalized_value / SRGB_LOW_SCALE
    Return ((normalized_value + SRGB_OFFSET) / SRGB_SCALE) ^ SRGB_EXPONENT
End Function


Private Function button_RelativeLuminance(ByVal color_value As ULong) As Double
    Const RED_WEIGHT As Double = 0.2126
    Const GREEN_WEIGHT As Double = 0.7152
    Const BLUE_WEIGHT As Double = 0.0722
    Dim As Double red_value
    Dim As Double green_value
    Dim As Double blue_value

    red_value = button_LinearColorChannel((color_value Shr 16) And &HFFUL)
    green_value = button_LinearColorChannel((color_value Shr 8) And &HFFUL)
    blue_value = button_LinearColorChannel(color_value And &HFFUL)
    Return RED_WEIGHT * red_value + _
        GREEN_WEIGHT * green_value + BLUE_WEIGHT * blue_value
End Function


Private Function button_ColorChannelFromLinear( _
    ByVal linear_value As Double _
) As ULong
    Const SRGB_LINEAR_LIMIT As Double = 0.0031308
    Const SRGB_LOW_SCALE As Double = 12.92
    Const SRGB_OFFSET As Double = 0.055
    Const SRGB_SCALE As Double = 1.055
    Const SRGB_EXPONENT As Double = 2.4
    Dim As Double normalized_value

    If linear_value < 0.0 Then linear_value = 0.0
    If linear_value > 1.0 Then linear_value = 1.0
    If linear_value <= SRGB_LINEAR_LIMIT Then
        normalized_value = linear_value * SRGB_LOW_SCALE
    Else
        normalized_value = SRGB_SCALE * _
            (linear_value ^ (1.0 / SRGB_EXPONENT)) - SRGB_OFFSET
    End If
    Return CULng(Int(normalized_value * 255.0 + 0.5))
End Function


Private Function button_LuminanceContrast( _
    ByVal first_luminance As Double, ByVal second_luminance As Double _
) As Double
    If first_luminance < second_luminance Then _
        Swap first_luminance, second_luminance
    Return (first_luminance + BUTTON_CONTRAST_LUMINANCE_OFFSET) / _
        (second_luminance + BUTTON_CONTRAST_LUMINANCE_OFFSET)
End Function


Private Function button_ReadableTextColor( _
    ByVal preferred_color As ULong, ByVal background_color As ULong _
) As ULong
    Dim As ULong black_color = RGB(0, 0, 0)
    Dim As ULong white_color = RGB(255, 255, 255)
    Dim As Double background_luminance = _
        button_RelativeLuminance(background_color)
    Dim As Double preferred_luminance = _
        button_RelativeLuminance(preferred_color)
    Dim As Double black_contrast
    Dim As Double white_contrast

    /'
        Classic button faces and semantic command text can be supplied by
        separate application settings. Preserve the requested text color when
        it meets the ordinary-text contrast target. Otherwise black or white
        guarantees a readable result for every opaque RGB background.
    '/
    If button_LuminanceContrast( _
        preferred_luminance, background_luminance _
    ) >= BUTTON_TEXT_MINIMUM_CONTRAST Then Return preferred_color

    black_contrast = button_LuminanceContrast(0.0, background_luminance)
    white_contrast = button_LuminanceContrast(1.0, background_luminance)
    If black_contrast >= white_contrast Then Return black_color
    Return white_color
End Function


Private Function button_ReadableDisabledTextColor( _
    ByVal preferred_color As ULong, ByVal background_color As ULong _
) As ULong
    Dim As Double background_luminance = _
        button_RelativeLuminance(background_color)
    Dim As Double preferred_luminance = _
        button_RelativeLuminance(preferred_color)
    Dim As Double target_luminance
    Dim As ULong channel_value
    Dim As ULong muted_color

    If button_LuminanceContrast( _
        preferred_luminance, background_luminance _
    ) >= BUTTON_TEXT_MINIMUM_CONTRAST Then Return preferred_color

    /'
        A black or white fallback would make an unreadable disabled label
        indistinguishable from enabled text. Move a neutral gray only as far
        from the face as needed for readable text, using a small safety margin
        for conversion back to an 8-bit sRGB channel.
    '/
    If button_LuminanceContrast(0.0, background_luminance) >= _
       button_LuminanceContrast(1.0, background_luminance) Then
        target_luminance = _
            (background_luminance + BUTTON_CONTRAST_LUMINANCE_OFFSET) / _
            BUTTON_DISABLED_TARGET_CONTRAST - _
            BUTTON_CONTRAST_LUMINANCE_OFFSET
    Else
        target_luminance = BUTTON_DISABLED_TARGET_CONTRAST * _
            (background_luminance + BUTTON_CONTRAST_LUMINANCE_OFFSET) - _
            BUTTON_CONTRAST_LUMINANCE_OFFSET
    End If

    channel_value = button_ColorChannelFromLinear(target_luminance)
    muted_color = RGB(channel_value, channel_value, channel_value)
    Return button_ReadableTextColor(muted_color, background_color)
End Function

Sub button_SetFlatStyle( _
    ByVal w As Widget Ptr, _
    ByVal normalBackground As ULong, ByVal normalForeground As ULong, _
    ByVal hotBackground As ULong, ByVal hotForeground As ULong, _
    ByVal selectedBackground As ULong, ByVal selectedForeground As ULong _
)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As ButtonData Ptr d = w->data
    d->flatStyle = -1
    d->normalBackground = normalBackground
    d->normalForeground = normalForeground
    d->hotBackground = hotBackground
    d->hotForeground = hotForeground
    d->selectedBackground = selectedBackground
    d->selectedForeground = selectedForeground
End Sub

Sub button_SetSelected(ByVal w As Widget Ptr, ByVal selected As Integer)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Cast(ButtonData Ptr, w->data)->selected = IIf(selected <> 0, -1, 0)
End Sub

Sub button_SetDefault(ByVal w As Widget Ptr, ByVal isDefault As Integer)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Cast(ButtonData Ptr, w->data)->default_button = IIf(isDefault <> 0, -1, 0)
    w->is_default_action = IIf(isDefault <> 0, -1, 0)
End Sub

Sub button_SetDefaultOutline(ByVal w As Widget Ptr, ByVal visible As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @button_Destroy Then Exit Sub
    Cast(ButtonData Ptr, w->data)->default_outline_visible = _
        IIf(visible <> 0, -1, 0)
End Sub

Sub button_SetArrow(ByVal w As Widget Ptr, ByVal direction As Integer)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    If direction < -1 OrElse direction > 1 Then Exit Sub
    Cast(ButtonData Ptr, w->data)->arrow_direction = direction
End Sub

Private Sub button_RenderContent(ByVal w As Widget Ptr, ByVal textColor As ULong, ByVal alpha As Integer = 255)
    Dim As ButtonData Ptr d = w->data
    If d->arrow_direction <> 0 Then
        Dim As Integer centerX = w->ax + w->w \ 2
        Dim As Integer centerY = w->ay + w->h \ 2
        Dim As Integer pointY = centerY + d->arrow_direction * 2
        Dim As Integer wingY = centerY - d->arrow_direction * 2
        backend_LineEx(centerX - 4, wingY, centerX, pointY, textColor, 1, alpha)
        backend_LineEx(centerX, pointY, centerX + 4, wingY, textColor, 1, alpha)
    Else
        backend_PrintAlignedAlpha( _
            w->ax, w->ay, w->w, w->h, textColor, d->text, _
            BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE, alpha _
        )
        If alpha = 255 Then
            Dim As Integer textHeight = backend_GetTextHeight()
            gui_RenderMnemonicUnderline _
                w, d->text, w->ax + (w->w - backend_GetTextWidth(d->text)) \ 2, _
                w->ay + (w->h - textHeight) \ 2, textHeight
        End If
    End If
End Sub

Sub button_Render(ByVal w As Widget Ptr)
    Const BUTTON_EDGE_INSET As Integer = 1
    Const BUTTON_BEVEL_REDUCTION As Integer = 2
    Const BUTTON_INNER_BEVEL_REDUCTION As Integer = 3
    Const BUTTON_FACE_INSET As Integer = 2
    Const BUTTON_FACE_REDUCTION As Integer = 4
    Dim As ButtonData Ptr d
    Dim As ULong c_f
    Dim As ULong c_d = current_theme.bg_dark
    Dim As ULong c_l = current_theme.bg_light
    Dim As ULong text_color
    Dim As Integer text_height
    Dim As Integer text_left
    Dim As Integer text_top

    If w = 0 OrElse w->data = 0 Then Exit Sub
    d = Cast(ButtonData Ptr, w->data)

    If d->flatStyle <> 0 Then
        Dim As ULong flatBackground = d->normalBackground
        Dim As ULong flatForeground = d->normalForeground
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
        If d->selected <> 0 OrElse gui_ShouldShowFocus(w) Then
#else
        If d->selected <> 0 Then
#endif
            flatBackground = d->selectedBackground
            flatForeground = d->selectedForeground
        ElseIf d->state <> 0 Then
            flatBackground = d->hotBackground
            flatForeground = d->hotForeground
        End If
        backend_Rect(w->ax, w->ay, w->w, w->h, flatBackground, 1)
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
        backend_Rect(w->ax, w->ay, w->w, w->h, current_theme.win_border, 0)
#endif
        button_RenderContent w, flatForeground
        Exit Sub
    End If

    If current_theme.control_style = GUI_CONTROL_STYLE_FLAT Then
        Dim As ULong faceColor = current_theme.bg_widget
        Dim As ULong borderColor = current_theme.win_border
        If w->enabled = 0 Then
            faceColor = current_theme.bg_face
        ElseIf d->default_button <> 0 OrElse w->has_focus <> 0 Then
            borderColor = current_theme.bg_select
        End If
        If w->enabled <> 0 AndAlso d->state = 1 Then
            faceColor = RGB(229, 241, 251)
            borderColor = current_theme.bg_select
        ElseIf w->enabled <> 0 AndAlso d->state = 2 Then
            faceColor = RGB(204, 228, 247)
            borderColor = current_theme.bg_select
        End If
        backend_RoundRect(w->ax, w->ay, w->w, w->h, 3, faceColor, 1)
        backend_RoundRect(w->ax, w->ay, w->w, w->h, 3, borderColor, 0)
        button_RenderContent w, current_theme.text_main, IIf(w->enabled <> 0, 255, 140)
        Exit Sub
    End If
    c_f = current_theme.bg_face
    If d->background_color_override <> 0 Then c_f = d->background_color
    text_color = theme_GetClassicColor(GUI_CLASSIC_COLOR_COMMAND_TEXT)
    If w->enabled = 0 Then
        text_color = theme_GetClassicColor(GUI_CLASSIC_COLOR_DISABLED_TEXT)
        text_color = button_ReadableDisabledTextColor(text_color, c_f)
    Else
        text_color = button_ReadableTextColor(text_color, c_f)
    End If
    If d->state = 2 OrElse d->selected <> 0 Then Swap c_d, c_l
    backend_Rect(w->ax, w->ay, w->w, w->h, current_theme.win_border, 0)
    If theme_GetClassicThreeD() Then
        backend_Rect(w->ax+BUTTON_EDGE_INSET, w->ay+BUTTON_EDGE_INSET, w->w-BUTTON_BEVEL_REDUCTION, w->h-BUTTON_BEVEL_REDUCTION, c_l, 0)
        backend_Rect(w->ax+BUTTON_EDGE_INSET, w->ay+BUTTON_EDGE_INSET, w->w-BUTTON_INNER_BEVEL_REDUCTION, w->h-BUTTON_INNER_BEVEL_REDUCTION, c_l, 0)
        backend_Line(w->ax+BUTTON_EDGE_INSET, w->ay+w->h-BUTTON_BEVEL_REDUCTION, w->ax+w->w-BUTTON_BEVEL_REDUCTION, w->ay+w->h-BUTTON_BEVEL_REDUCTION, c_d)
        backend_Line(w->ax+w->w-BUTTON_BEVEL_REDUCTION, w->ay+BUTTON_EDGE_INSET, w->ax+w->w-BUTTON_BEVEL_REDUCTION, w->ay+w->h-BUTTON_BEVEL_REDUCTION, c_d)
    End If
    backend_Rect(w->ax+BUTTON_FACE_INSET, w->ay+BUTTON_FACE_INSET, w->w-BUTTON_FACE_REDUCTION, w->h-BUTTON_FACE_REDUCTION, c_f, 1)
    If w->is_default_action <> 0 AndAlso _
       d->default_outline_visible <> 0 AndAlso _
       w->w > 8 AndAlso w->h > 8 Then
        backend_Rect( _
            w->ax + 3, w->ay + 3, w->w - 6, w->h - 6, _
            current_theme.win_border, 0 _
        )
    End If
    backend_PrintAligned( _
        w->ax, w->ay, w->w, w->h, text_color, d->text, _
        BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE _
    )
    text_height = backend_GetTextHeight()
    text_left = w->ax + (w->w - backend_GetTextWidth(d->text)) \ 2
    text_top = w->ay + (w->h - text_height) \ 2
    gui_RenderMnemonicUnderline _
        w, d->text, text_left, text_top, text_height
End Sub

Sub button_CancelInput(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As ButtonData Ptr d = w->data
    d->pressed = 0
    d->state = 0
End Sub

' -------------------------------------------------------------------------
' Public color API
' -------------------------------------------------------------------------

Function button_SetBackgroundColor( _
    ByVal w As Widget Ptr, ByVal background_color As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(ButtonData Ptr, w->data)
        .background_color = background_color
        .background_color_override = -1
    End With
    Return -1
End Function


Function button_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(ButtonData Ptr, w->data)->background_color_override = 0
    Return -1
End Function


Function button_GetBackgroundColor( _
    ByVal w As Widget Ptr, ByRef background_color As ULong _
) As Integer
    Dim As ButtonData Ptr button_data

    background_color = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    button_data = Cast(ButtonData Ptr, w->data)
    If button_data->background_color_override = 0 Then Return 0
    background_color = button_data->background_color
    Return -1
End Function

' -------------------------------------------------------------------------
' Lifecycle and polled activation
' -------------------------------------------------------------------------

Sub button_Activate(ByVal w As Widget Ptr)
    Dim As ButtonData Ptr d

    If w = 0 OrElse w->data = 0 Then Exit Sub
    d = Cast(ButtonData Ptr, w->data)
    If d->pressed <> 0 Then Exit Sub
    d->pressed = -1

    If d->clickHandler <> 0 Then
        Cast(Sub(ByVal As Widget Ptr), d->clickHandler)(w)
    End If
End Sub

Function button_SetKeyPressHandler( _
    ByVal w As Widget Ptr, _
    ByVal handler As Sub(ByVal As Widget Ptr, ByRef As Integer) _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @button_Destroy Then Return 0
    Cast(ButtonData Ptr, w->data)->key_press_handler = handler
    Return -1
End Function

Function button_SetKeyDownHandler( _
    ByVal w As Widget Ptr, _
    ByVal handler As Sub(ByVal As Widget Ptr, ByRef As Integer, ByRef As Integer) _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @button_Destroy Then Return 0
    Cast(ButtonData Ptr, w->data)->key_down_handler = handler
    Return -1
End Function

Function button_SetKeyUpHandler( _
    ByVal w As Widget Ptr, _
    ByVal handler As Sub(ByVal As Widget Ptr, ByRef As Integer, ByRef As Integer) _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @button_Destroy Then Return 0
    Cast(ButtonData Ptr, w->data)->key_up_handler = handler
    Return -1
End Function

Private Function button_KeyTargetIsCurrent( _
    ByVal w As Widget Ptr, ByVal d As ButtonData Ptr, ByVal registry_id As ULongInt, _
    ByVal frame_serial As ULongInt _
) As Integer
    Return control_KeyTargetIsCurrent(w, d, registry_id, frame_serial)
End Function

Private Function button_KeyNotifications(ByVal w As Widget Ptr, ByVal d As ButtonData Ptr, _
    ByVal release_events As Integer) As Integer
    If release_events Then
        Return control_KeyNotifications(w, d, d->key_up_handler, -1, button_key_event_depth)
    End If
    Return control_KeyNotifications(w, d, d->key_down_handler, 0, button_key_event_depth)
End Function

Private Function button_KeyPressInput(ByVal w As Widget Ptr, ByVal d As ButtonData Ptr) As Integer
    Dim As ULongInt registry_id = w->registry_id
    Dim As ULongInt frame_serial = input_FrameSerial()
    Dim As String text_value = input_PollTextInput()
    ' Some backends supply only a scan-code edge for these control bytes.
    ' Do not deliver Space twice when it also appears in the text snapshot.
    Dim As Integer scan_codes(0 To 3) = {KEY_RETURN, FB.SC_SPACE, KEY_BACKSPACE, KEY_ESCAPE}
    Dim As Integer characters(0 To 3) = {13, 32, 8, 27}
    For key_index As Integer = 0 To 3
        If input_KeyPressEvent(scan_codes(key_index)) AndAlso _
            InStr(text_value, Chr(characters(key_index))) = 0 Then text_value &= Chr(characters(key_index))
    Next key_index
    For position As Integer = 1 To Len(text_value)
        If d->key_press_handler = 0 Then Exit For
        Dim As Integer original_character = Asc(text_value, position)
        Dim As Integer character_code = original_character
        Cast(Sub(ByVal As Widget Ptr, ByRef As Integer), d->key_press_handler)(w, character_code)
        ' A callback can free this address and immediately reuse it for a
        ' replacement button. Registration identity, not the pointer alone,
        ' determines whether the rest of this frame still belongs here.
        ' A nested GUI update owns a new snapshot. Do not consume or map its
        ' edges in response to the old callback's character.
        If input_FrameSerial() <> frame_serial Then Return 0
        Dim As Integer target_gone = (button_KeyTargetIsCurrent(w, d, registry_id, frame_serial) = 0)
        If character_code <> original_character OrElse target_gone Then
            For key_index As Integer = 0 To 3
                If original_character <> characters(key_index) Then Continue For
                ' Consume the original edge through the common input view,
                ' including a later manager-owned Escape/cancel action. Raw
                ' events and text stay intact; cancellation does not latch
                ' until key release or swallow another character in a repeat.
                If input_ConsumeKeyPressEvent(scan_codes(key_index)) = 0 Then Return 0
            Next key_index
        End If
        If target_gone Then Return 0
        If character_code = 13 OrElse character_code = 32 Then
            ' Each accepted byte is a separate input action. Commit its Click
            ' before delivering the next byte, rather than collapsing a batch
            ' into one activation. The public latch still records that input.
            d->pressed = 0
            button_Activate w
            If button_KeyTargetIsCurrent(w, d, registry_id, frame_serial) = 0 Then Return 0
        End If
    Next position
    Return -1
End Function

Sub button_Update(ByVal w As Widget Ptr)
    Dim As ButtonData Ptr d
    Dim As Integer mx = input_MouseX()
    Dim As Integer my = input_MouseY()
    Dim As Integer mb = input_MouseButtons()

    If w = 0 OrElse w->data = 0 Then Exit Sub
    d = Cast(ButtonData Ptr, w->data)
    d->pressed = 0
    If mx >= w->ax And mx < w->ax + w->w And my >= w->ay And my < w->ay + w->h Then
        If mb And 1 Then
            d->state = 2
        Else
            If d->state = 2 Then
                /'
                    The callback may remove this button and its complete
                    parent tree. Commit the final pointer state first and
                    return immediately after activation so neither w nor d is
                    dereferenced after application code regains control.
                '/
                d->state = 1
                button_Activate w
                Exit Sub
            End If
            d->state = 1
        End If
    Else
        d->state = 0
    End If

    If w->has_focus <> 0 AndAlso d->pressed = 0 Then
        Dim As ULongInt registry_id = w->registry_id
        Dim As ULongInt frame_serial = input_FrameSerial()
        If button_KeyNotifications(w, d, 0) = 0 Then Exit Sub
        If d->key_press_handler <> 0 Then
            If button_KeyPressInput(w, d) = 0 Then Exit Sub
        ElseIf input_KeyPressEvent(KEY_RETURN) <> 0 OrElse _
           input_KeyPressEvent(FB.SC_SPACE) <> 0 Then
            button_Activate w
            If button_KeyTargetIsCurrent(w, d, registry_id, frame_serial) = 0 Then Exit Sub
        End If
        button_KeyNotifications w, d, -1
    End If
End Sub
Sub button_Destroy(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Delete Cast(ButtonData Ptr, w->data)
    w->data = 0
End Sub

Function button_SetText( _
    ByVal w As Widget Ptr, ByRef text_value As Const String _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @button_Destroy Then _
        Return 0
    Cast(ButtonData Ptr, w->data)->text = text_value
    Return -1
End Function

Function button_GetText(ByVal w As Widget Ptr) As String
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @button_Destroy Then _
        Return ""
    Return Cast(ButtonData Ptr, w->data)->text
End Function
Function gui_ButtonPressed(ByVal nm As String) As Integer
    Dim As ButtonData Ptr d
    Dim As Widget Ptr w

    w = gui_FindWidget(nm)
    If w = 0 Then Return 0
    If w->data = 0 OrElse w->destroy <> @button_Destroy Then Return 0
    Dim As Widget Ptr owner = w
    Dim As Integer ownerDepth
    ' A release event belongs to a live, eligible control tree. Visibility
    ' can change after the update, before application code polls the event.
    While owner <> 0 AndAlso ownerDepth < GUI_MODAL_ROOT_MAXIMUM_DEPTH
        If owner->visible = 0 OrElse owner->enabled = 0 Then Return 0
        owner = owner->parent
        ownerDepth += 1
    Wend
    If owner <> 0 Then Return 0
    d = Cast(ButtonData Ptr, w->data)
    Return d->pressed
End Function

' end of button.bas
