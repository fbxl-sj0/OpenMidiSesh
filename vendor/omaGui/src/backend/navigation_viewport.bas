/'
    Project: omaGUI
    File: navigation_viewport.bas
    Purpose: Maintain a logical canvas over a scaled physical gfxlib surface.
    Responsibilities: Fit the viewport, map pointer coordinates and accessibility.
    This file does not contain widgets, event polling or application settings.

    VIEW SCREEN clips in physical pixels; WINDOW SCREEN supplies the logical
    transform. Reapplying a narrower clip must preserve that same transform,
    otherwise each widget would stretch to fill its own clipping rectangle.
    Direct framebuffer and GPU point writers bypass WINDOW, so this optional
    profile selects their portable drawing fallback. Standard applications retain
    the optimized native pixel path. All calls belong to the GUI thread.
'/
#lang "fb"
Private Dim Shared As Integer omagui_nav_display_scale = 100
Private Dim Shared As Integer omagui_nav_fullscreen, omagui_nav_contrast
Private Dim Shared As Integer omagui_nav_view_w = 1, omagui_nav_view_h = 1

Sub backend_SetDisplayOptions(ByVal fullscreen As Integer, ByVal scalePercent As Integer)
    omagui_nav_fullscreen = IIf(fullscreen, -1, 0)
    omagui_nav_display_scale = IIf(scalePercent < 50, 50, IIf(scalePercent > 150, 150, scalePercent))
End Sub

Sub backend_SetTextScale(ByVal textScale As Integer)
    omagui_nav_text_scale = IIf(textScale > 1, 2, 1)
End Sub

Function backend_GetTextScale() As Integer
    Return omagui_nav_text_scale
End Function

Sub backend_SetHighContrast(ByVal enabled As Integer)
    omagui_nav_contrast = IIf(enabled, -1, 0)
End Sub

Sub backend_NavigationCreate(ByRef w As Integer, ByRef h As Integer, ByRef flags As UInteger)
    ' Bound dimensions before multiplying or creating a native screen.
    w = IIf(w < 2, 2, IIf(w > 32767, 32767, w))
    h = IIf(h < 2, 2, IIf(h > 32767, 32767, h))
    omagui_nav_logical_w = w: omagui_nav_logical_h = h
    Dim As Double scaleFactor = omagui_nav_display_scale / 100.0
    Dim As Long desktopWidth, desktopHeight
    ScreenControl FB.GET_DESKTOP_SIZE, desktopWidth, desktopHeight
    If desktopWidth > 0 AndAlso desktopHeight > 0 Then
        Dim As Double widthScale = (desktopWidth * 0.94) / w
        Dim As Double heightScale = (desktopHeight * 0.90) / h
        If scaleFactor > widthScale Then scaleFactor = widthScale
        If scaleFactor > heightScale Then scaleFactor = heightScale
    End If
    If scaleFactor <= 0 Then scaleFactor = 1
    w = CInt(omagui_nav_logical_w * scaleFactor)
    h = CInt(omagui_nav_logical_h * scaleFactor)
    If w < 2 Then w = 2
    If h < 2 Then h = 2
    omagui_nav_view_w = w: omagui_nav_view_h = h
    If omagui_nav_fullscreen Then flags Or= FB.GFX_FULLSCREEN
End Sub

Sub backend_NavigationClip(ByVal x1 As Integer, ByVal y1 As Integer, ByVal x2 As Integer, ByVal y2 As Integer)
    Dim As Integer physicalWidth, physicalHeight
    ScreenInfo physicalWidth, physicalHeight
    If physicalWidth < 2 OrElse physicalHeight < 2 Then Exit Sub
    omagui_nav_view_w = physicalWidth: omagui_nav_view_h = physicalHeight
    Dim As Double xFactor = (physicalWidth - 1) / CDbl(omagui_nav_logical_w - 1)
    Dim As Double yFactor = (physicalHeight - 1) / CDbl(omagui_nav_logical_h - 1)
    Dim As Integer px1 = CInt(Int(x1 * xFactor)), py1 = CInt(Int(y1 * yFactor))
    Dim As Integer px2 = CInt(Int(x2 * xFactor)), py2 = CInt(Int(y2 * yFactor))
    ' WINDOW requires a nondegenerate range even for a one-pixel clip.
    Dim As Double logicalRight = IIf(px2 > px1, px2 / xFactor, (px1 + 1) / xFactor)
    Dim As Double logicalBottom = IIf(py2 > py1, py2 / yFactor, (py1 + 1) / yFactor)
    View Screen (px1, py1)-(px2, py2)
    Window Screen (px1 / xFactor, py1 / yFactor)-(logicalRight, logicalBottom)
End Sub

Function backend_PhysicalToLogicalX(ByVal x As Integer) As Integer
    If omagui_nav_view_w < 2 OrElse omagui_nav_logical_w < 2 Then Return -1
    If x < 0 OrElse x >= omagui_nav_view_w Then Return -1
    Return CInt((CLngInt(x) * (omagui_nav_logical_w - 1)) \ (omagui_nav_view_w - 1))
End Function

Function backend_PhysicalToLogicalY(ByVal y As Integer) As Integer
    If omagui_nav_view_h < 2 OrElse omagui_nav_logical_h < 2 Then Return -1
    If y < 0 OrElse y >= omagui_nav_view_h Then Return -1
    Return CInt((CLngInt(y) * (omagui_nav_logical_h - 1)) \ (omagui_nav_view_h - 1))
End Function

Function backend_NavigationColor(ByVal clr As ULong) As ULong
    If omagui_nav_contrast = 0 Then Return clr
    Dim As Integer redValue = (clr Shr 16) And 255
    Dim As Integer greenValue = (clr Shr 8) And 255
    Dim As Integer blueValue = clr And 255
    Dim As Integer luminance = (redValue * 30 + greenValue * 59 + blueValue * 11) \ 100
    If redValue > 200 AndAlso greenValue > 150 AndAlso blueValue < 160 Then Return RGB(255,255,0)
    If luminance < 90 Then Return RGB(0,0,0)
    If luminance < 180 Then Return RGB(0,255,255)
    Return RGB(255,255,255)
End Function
' end of navigation_viewport.bas
