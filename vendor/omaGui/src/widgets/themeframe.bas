/'
    Project: omaGUI
    ---------------

    File: themeframe.bas

    Targets:

        FreeBASIC FB dialect. Desktop gfxlib2 builds use the platform backend
        selected by the including project.

    Module API:

        Theme-aware frame constructor and renderer implementation.

    Purpose:

        Render theme-aware panel surfaces and structural frame motifs.

    Responsibilities:

        - retain classic rectangle compatibility
        - update a classic frame color without replacing the widget
        - render bounded borders and corner brackets
        - preserve application fills and use semantic colors for outlines

    This file intentionally does NOT contain:

        - application-specific panel names or faction policy
        - pointer interaction or child ownership
        - platform-specific drawing calls outside the backend API
'/

#lang "fb"
#include once "src/widgets/themeframe.bi"

' -------------------------------------------------------------------------
' Frame geometry helpers
' -------------------------------------------------------------------------

Private Sub themeframe_DrawCornerBrackets( _
    ByVal leftValue As Integer, ByVal topValue As Integer, _
    ByVal rightValue As Integer, ByVal bottomValue As Integer, _
    ByVal cornerLength As Integer, ByVal clr As ULong)
    backend_Line leftValue, topValue, leftValue + cornerLength, topValue, clr
    backend_Line leftValue, topValue, leftValue, topValue + cornerLength, clr
    backend_Line rightValue - cornerLength, topValue, rightValue, topValue, clr
    backend_Line rightValue, topValue, rightValue, topValue + cornerLength, clr
    backend_Line leftValue, bottomValue, leftValue + cornerLength, bottomValue, clr
    backend_Line leftValue, bottomValue - cornerLength, leftValue, bottomValue, clr
    backend_Line rightValue - cornerLength, bottomValue, rightValue, bottomValue, clr
    backend_Line rightValue, bottomValue - cornerLength, rightValue, bottomValue, clr
End Sub


Private Sub themeframe_DrawStyledOutline(ByVal w As Widget Ptr)
    Const FRAME_CORNER_LENGTH As Integer = 18
    Const FRAME_INNER_INSET As Integer = 3
    Dim As Integer leftValue
    Dim As Integer topValue
    Dim As Integer rightValue
    Dim As Integer bottomValue
    Dim As ULong borderColor
    Dim As ULong accentColor
    Dim As ULong secondaryColor

    If w = 0 OrElse w->w < 1 OrElse w->h < 1 Then Exit Sub

    leftValue = w->ax
    topValue = w->ay
    rightValue = w->ax + w->w - 1
    bottomValue = w->ay + w->h - 1
    borderColor = theme_GetColor(GUI_COLOR_BORDER)
    accentColor = theme_GetColor(GUI_COLOR_SELECT_BG)
    secondaryColor = current_theme.bg_light

    /'
        The current omaGUI palette intentionally has semantic control colors
        rather than application-specific faction-style fields. A structural
        frame therefore keeps one portable motif: the semantic border remains
        readable at every theme depth, while corner brackets identify a panel
        without borrowing a menu or selection color as its fill.
    '/
    backend_Rect w->ax, w->ay, w->w, w->h, borderColor, 0
    If w->w > FRAME_INNER_INSET * 2 AndAlso _
       w->h > FRAME_INNER_INSET * 2 Then
        backend_Rect w->ax + FRAME_INNER_INSET, _
            w->ay + FRAME_INNER_INSET, _
            w->w - FRAME_INNER_INSET * 2, _
            w->h - FRAME_INNER_INSET * 2, secondaryColor, 0
    End If
    themeframe_DrawCornerBrackets _
        leftValue, topValue, rightValue, bottomValue, _
        IIf(w->w < FRAME_CORNER_LENGTH, w->w \ 2, _
            IIf(w->h < FRAME_CORNER_LENGTH, w->h \ 2, _
                FRAME_CORNER_LENGTH)), accentColor
End Sub

' -------------------------------------------------------------------------
' Widget lifecycle
' -------------------------------------------------------------------------

Sub themeframe_SetClassicColor( _
    ByVal w As Widget Ptr, ByVal classicColor As ULong)
    Dim As ThemeFrameData Ptr frameData

    If w = 0 OrElse w->data = 0 OrElse _
       w->render <> @themeframe_Render OrElse _
       w->destroy <> @themeframe_Destroy Then Exit Sub
    frameData = Cast(ThemeFrameData Ptr, w->data)
    frameData->classicColor = classicColor
End Sub


Sub themeframe_Render(ByVal w As Widget Ptr)
    Dim As ThemeFrameData Ptr frameData

    If w = 0 OrElse w->data = 0 Then Exit Sub
    If w->w <= 0 OrElse w->h <= 0 Then Exit Sub

    frameData = Cast(ThemeFrameData Ptr, w->data)
    If frameData->filled <> 0 Then
        /'
            ThemeFrame is retained for TurboTrek's faction-panel surfaces.
            Its supplied color is an application design token, so it remains
            the fill after the generic omaGUI theme upgrade.
        '/
        backend_Rect w->ax, w->ay, w->w, w->h, _
            frameData->classicColor, -1
    Else
        themeframe_DrawStyledOutline w
    End If
End Sub

Sub themeframe_Destroy(ByVal w As Widget Ptr)
    If w = 0 Then Exit Sub
    If w->data <> 0 Then Delete Cast(ThemeFrameData Ptr, w->data)
End Sub


Function themeframe_Create( _
    ByVal nm As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, _
    ByVal classicColor As ULong, ByVal filled As Integer) As Widget Ptr
    Dim As ThemeFrameData Ptr frameData
    Dim As Widget Ptr result = New Widget

    If result = 0 Then Return 0
    frameData = New ThemeFrameData
    If frameData = 0 Then
        Delete result
        Return 0
    End If

    result->name = nm
    result->x = x
    result->y = y
    result->w = w
    result->h = h
    result->visible = -1
    result->enabled = -1
    result->render = @themeframe_Render
    result->destroy = @themeframe_Destroy
    frameData->classicColor = classicColor
    frameData->filled = IIf(filled <> 0, -1, 0)
    result->data = frameData
    Return result
End Function

/' end of themeframe.bas '/
