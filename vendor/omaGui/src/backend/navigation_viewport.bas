/'
    Project: omaGUI
    File: navigation_viewport.bas
    Purpose: Maintain a logical canvas over a scaled physical gfxlib surface.
    Responsibilities: Fit the viewport, map pointer coordinates and accessibility.
    This file does not contain widgets, event polling or application settings.

    VIEW SCREEN clips in physical pixels. This module translates logical
    geometry before submission. WINDOW stays disabled: it transforms positions
    but does not scale PSET coverage or PUT image dimensions. Keeping one
    physical raster space also lets GPU point batches use the same bounds.
    Logical pixels occupy areas, not only transformed coordinate points. Scaled
    glyph cells and image pixels cover those areas; identity transforms retain
    the optimized font path. All calls belong to the GUI thread. Resampled image
    storage is bounded and borrowed only until the caller completes PUT.
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
    If omagui_nav_fullscreen Then flags Or= BACKEND_WINDOW_FULLSCREEN
    #if defined(__FB_JS__) Or defined(__FB_ANDROID__)
    If (flags And (BACKEND_WINDOW_FULLSCREEN Or BACKEND_WINDOW_FILL Or _
        BACKEND_WINDOW_RESIZABLE)) <> 0 Then
    #else
    If (flags And (BACKEND_WINDOW_FULLSCREEN Or BACKEND_WINDOW_FILL)) <> 0 Then
    #endif
        /'
            Browser and Android resizable windows use the available activity
            area as their physical surface. Keep those dimensions and apply
            the user's display scale to the logical viewport instead of
            shrinking the surface to an unrelated desktop mode.
        '/
        omagui_nav_logical_w = CInt(w * 100.0 / omagui_nav_display_scale)
        omagui_nav_logical_h = CInt(h * 100.0 / omagui_nav_display_scale)
        omagui_nav_logical_w = IIf(omagui_nav_logical_w < 2, 2, _
            IIf(omagui_nav_logical_w > 32767, 32767, omagui_nav_logical_w))
        omagui_nav_logical_h = IIf(omagui_nav_logical_h < 2, 2, _
            IIf(omagui_nav_logical_h > 32767, 32767, omagui_nav_logical_h))
        omagui_nav_view_w = w: omagui_nav_view_h = h
#if defined(__FB_LINUX__) And Not defined(__FB_JS__)
        ' The X11 backend cannot combine fullscreen and resizable modes.
        If (flags And BACKEND_WINDOW_FULLSCREEN) <> 0 Then _
            flags And= Not BACKEND_WINDOW_RESIZABLE
#endif
        Exit Sub
    End If
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
End Sub

Sub backend_NavigationClip(ByVal x1 As Integer, ByVal y1 As Integer, ByVal x2 As Integer, ByVal y2 As Integer)
    Dim As Integer physicalWidth, physicalHeight
    ScreenInfo physicalWidth, physicalHeight
    If physicalWidth < 2 OrElse physicalHeight < 2 Then Exit Sub
    omagui_nav_view_w = physicalWidth: omagui_nav_view_h = physicalHeight
    Dim As Double xFactor = physicalWidth / CDbl(omagui_nav_logical_w)
    Dim As Double yFactor = physicalHeight / CDbl(omagui_nav_logical_h)
    Dim As Integer px1 = CInt(Int(x1 * xFactor)), py1 = CInt(Int(y1 * yFactor))
    Dim As Integer px2 = CInt(Int((x2 + 1) * xFactor)) - 1, py2 = CInt(Int((y2 + 1) * yFactor)) - 1
    If px2 < px1 Then px2 = px1
    If py2 < py1 Then py2 = py1
    View Screen (px1, py1)-(px2, py2)
    Window
End Sub

Function backend_NavigationBounds(ByVal x1 As Integer, ByVal y1 As Integer, ByVal x2 As Integer, ByVal y2 As Integer, ByRef leftPixel As Integer, ByRef topPixel As Integer, ByRef rightPixel As Integer, ByRef bottomPixel As Integer) As Integer
    If omagui_nav_view_w < 2 OrElse omagui_nav_view_h < 2 OrElse omagui_nav_logical_w < 2 OrElse omagui_nav_logical_h < 2 Then Return 0
    If x2 < x1 OrElse y2 < y1 OrElse x2 < 0 OrElse y2 < 0 OrElse x1 >= omagui_nav_logical_w OrElse y1 >= omagui_nav_logical_h Then Return 0
    If x1 < 0 Then x1 = 0
    If y1 < 0 Then y1 = 0
    If x2 >= omagui_nav_logical_w Then x2 = omagui_nav_logical_w - 1
    If y2 >= omagui_nav_logical_h Then y2 = omagui_nav_logical_h - 1
    Dim xf As Double = omagui_nav_view_w / CDbl(omagui_nav_logical_w)
    Dim yf As Double = omagui_nav_view_h / CDbl(omagui_nav_logical_h)
    leftPixel = Int(x1 * xf): topPixel = Int(y1 * yf)
    rightPixel = Int((x2 + 1) * xf) - 1: bottomPixel = Int((y2 + 1) * yf) - 1
    If rightPixel >= omagui_nav_view_w Then rightPixel = omagui_nav_view_w - 1
    If bottomPixel >= omagui_nav_view_h Then bottomPixel = omagui_nav_view_h - 1
    Return CLng(rightPixel >= leftPixel AndAlso bottomPixel >= topPixel)
End Function

Sub backend_NavigationFill(ByVal x1 As Integer, ByVal y1 As Integer, ByVal x2 As Integer, ByVal y2 As Integer, ByVal clr As ULong)
    Dim leftPixel As Integer, topPixel As Integer, rightPixel As Integer, bottomPixel As Integer
    If backend_NavigationBounds(x1,y1,x2,y2,leftPixel,topPixel,rightPixel,bottomPixel) = 0 Then Exit Sub
    ' A logical pixel owns a complete physical area, including fractional DPI
    ' boundaries. The active VIEW retains nested widget clipping.
    Line (leftPixel, topPixel)-(rightPixel, bottomPixel), clr, BF
End Sub

Sub backend_NavigationLine(ByVal x1 As Integer, ByVal y1 As Integer, ByVal x2 As Integer, ByVal y2 As Integer, ByVal clr As ULong)
    Dim xf As Double = omagui_nav_view_w / CDbl(omagui_nav_logical_w)
    Dim yf As Double = omagui_nav_view_h / CDbl(omagui_nav_logical_h)
    Line (x1 * xf, y1 * yf)-(x2 * xf, y2 * yf), clr
End Sub

Sub backend_NavigationCircle(ByVal x As Integer, ByVal y As Integer, ByVal radius As Integer, ByVal clr As ULong, ByVal filled As Integer)
    If radius < 0 Then Exit Sub
    Dim xf As Double = omagui_nav_view_w / CDbl(omagui_nav_logical_w)
    Dim yf As Double = omagui_nav_view_h / CDbl(omagui_nav_logical_h)
    If filled Then
        Circle (x * xf, y * yf), radius * xf, clr, , , yf / xf, F
    Else
        Circle (x * xf, y * yf), radius * xf, clr, , , yf / xf
    End If
End Sub

Function backend_NavigationImage(ByVal sourceImage As Any Ptr, ByVal x As Integer, ByVal y As Integer, ByRef drawX As Single, ByRef drawY As Single) As Any Ptr
    Const maxScaledPixels As Integer = 8388608 ' At most 32 MiB, matching one bounded display page.
    drawX = x: drawY = y
    If omagui_nav_view_w = omagui_nav_logical_w AndAlso omagui_nav_view_h = omagui_nav_logical_h Then Return sourceImage
    If omagui_nav_view_w < 2 OrElse omagui_nav_view_h < 2 OrElse omagui_nav_logical_w < 2 OrElse omagui_nav_logical_h < 2 Then Return 0
    Dim widthValue As Integer, heightValue As Integer, pixelBytes As Integer, pitchBytes As Integer, imageBytes As Integer
    Dim sourcePixels As Any Ptr
    If ImageInfo(sourceImage, widthValue, heightValue, pixelBytes, pitchBytes, sourcePixels, imageBytes) <> 0 Then Return 0
    If widthValue <= 0 OrElse heightValue <= 0 OrElse pixelBytes <> 4 OrElse sourcePixels = 0 Then Return 0
    If CLngInt(widthValue) * 4 > pitchBytes Then Return 0
    ' Decoders own and validate the borrowed source image. Check its reported
    ' layout before pointer arithmetic; source photographs may exceed a page.
    If imageBytes <= 0 OrElse CLngInt(pitchBytes) * heightValue > imageBytes Then Return 0
    Dim xf As Double = omagui_nav_view_w / CDbl(omagui_nav_logical_w)
    Dim yf As Double = omagui_nav_view_h / CDbl(omagui_nav_logical_h)
    ' Crop to the physical canvas before allocation. The ordinary PUT retains
    ' widget clipping, alpha and color-key behavior. Only one temporary image
    ' is owned by this call; the caller destroys it after synchronous PUT.
    Dim leftValue As Double = Int(CDbl(x) * xf), topValue As Double = Int(CDbl(y) * yf)
    Dim rightValue As Double = Int((CDbl(x) + widthValue) * xf)
    Dim bottomValue As Double = Int((CDbl(y) + heightValue) * yf)
    If leftValue < 0 Then leftValue = 0
    If topValue < 0 Then topValue = 0
    If rightValue > omagui_nav_view_w Then rightValue = omagui_nav_view_w
    If bottomValue > omagui_nav_view_h Then bottomValue = omagui_nav_view_h
    If rightValue <= leftValue OrElse bottomValue <= topValue Then Return 0
    Dim targetW As Integer = rightValue - leftValue, targetH As Integer = bottomValue - topValue
    If CLngInt(targetW) * targetH > maxScaledPixels Then Return 0
    Dim scaled As Any Ptr = ImageCreate(targetW, targetH, 0, 32)
    If scaled = 0 Then Return 0
    Dim targetPixels As Any Ptr, targetPitch As Integer
    Dim actualW As Integer, actualH As Integer, actualPixelBytes As Integer
    If ImageInfo(scaled, actualW, actualH, actualPixelBytes, targetPitch, targetPixels) <> 0 OrElse targetPixels = 0 OrElse actualW <> targetW OrElse actualH <> targetH OrElse actualPixelBytes <> 4 OrElse CLngInt(targetW) * 4 > targetPitch Then
        ImageDestroy scaled
        Return 0
    End If
    For rowIndex As Integer = 0 To targetH - 1
        Dim sourceY As Integer = -Int(-((topValue + rowIndex + 1) / yf)) - 1 - y
        If sourceY < 0 Then sourceY = 0
        If sourceY >= heightValue Then sourceY = heightValue - 1
        Dim sourceRow As ULong Ptr = CPtr(ULong Ptr, CPtr(UByte Ptr, sourcePixels) + sourceY * pitchBytes)
        Dim targetRow As ULong Ptr = CPtr(ULong Ptr, CPtr(UByte Ptr, targetPixels) + rowIndex * targetPitch)
        For columnIndex As Integer = 0 To targetW - 1
            Dim sourceX As Integer = -Int(-((leftValue + columnIndex + 1) / xf)) - 1 - x
            If sourceX < 0 Then sourceX = 0
            If sourceX >= widthValue Then sourceX = widthValue - 1
            targetRow[columnIndex] = sourceRow[sourceX]
        Next columnIndex
    Next rowIndex
    drawX = leftValue: drawY = topValue
    Return scaled
End Function

Function backend_PhysicalToLogicalX(ByVal x As Integer) As Integer
    If omagui_nav_view_w < 2 OrElse omagui_nav_logical_w < 2 Then Return -1
    If x < 0 OrElse x >= omagui_nav_view_w Then Return -1
    ' Invert the half-open bounds used when drawing each logical pixel.
    Return CInt(((CLngInt(x) + 1) * omagui_nav_logical_w - 1) \ omagui_nav_view_w)
End Function

Function backend_PhysicalToLogicalY(ByVal y As Integer) As Integer
    If omagui_nav_view_h < 2 OrElse omagui_nav_logical_h < 2 Then Return -1
    If y < 0 OrElse y >= omagui_nav_view_h Then Return -1
    Return CInt(((CLngInt(y) + 1) * omagui_nav_logical_h - 1) \ omagui_nav_view_h)
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
Sub backend_NavigationPlotPixel(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong)
    backend_NavigationFill x, y, x, y, clr
End Sub
' end of navigation_viewport.bas
