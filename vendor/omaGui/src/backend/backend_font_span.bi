/'
    Project: omaGUI gfxlib backend
    File: backend_font_span.bi
    Purpose: Present clipped glyph coverage through the gfxlib framebuffer.
    Responsibilities: Own a bounded reusable mask image and preserve the
        existing font alpha arithmetic, clipping and dirty-row notification.
    Targets:

        FreeBASIC gfxlib builds with 32-bit images. gfxlib3 and
        OMAGUI_DISABLE_FONT_SPANS use the existing per-pixel renderer.

    Module API:

        Private implementation included by backend_gfxlib.bas.

    This file intentionally does NOT contain:

        - glyph selection
        - font scaling
        - display-page lifecycle

    All calls belong to the GUI thread, like the other backend drawing calls.
    Screen locks protect direct writes and report changed rows on unlock.
    PUT owns locking and clipping for the fallback. Both paths borrow the
    caller's color only during the synchronous call. The mask remains owned
    by this module and is released by backend_Exit.
'/

Private Const BACKEND_FONT_SPAN_MAX_PIXELS As Integer = 262144 ' At most 1 MiB of RGBA pixels.
Private Dim Shared As Any Ptr backend_FontSpanImage
Private Dim Shared As ULong Ptr backend_FontSpanPixels
Private Dim Shared As Integer backend_FontSpanWidth, backend_FontSpanHeight
Private Dim Shared As Integer backend_FontSpanPitch

' Skip raster work outside the backend clip before filling a mask. LongInt
' inputs keep extreme signed bearings from wrapping before the clip check. PUT
' still owns clipping for glyphs which intersect it, including negative ones.
Private Function backend_FontSpanVisible(ByVal x As LongInt, ByVal y As LongInt, _
    ByVal widthValue As LongInt, ByVal heightValue As LongInt) As Integer
#If Defined(OMAGUI_DISABLE_FONT_SPANS)
    Return -1
#Else
    If widthValue <= 0 OrElse heightValue <= 0 Then Return 0
    If backend_ClipDepth <= 0 Then Return -1
    Dim As Integer clipIndex = backend_ClipDepth - 1
    Return IIf(CLngInt(x) + widthValue > backend_ClipX1(clipIndex) AndAlso _
        CLngInt(y) + heightValue > backend_ClipY1(clipIndex) AndAlso _
        x <= backend_ClipX2(clipIndex) AndAlso y <= backend_ClipY2(clipIndex), -1, 0)
#EndIf
End Function

Private Sub backend_FontSpanRelease()
    If backend_FontSpanImage <> 0 Then ImageDestroy backend_FontSpanImage
    backend_FontSpanImage = 0
    backend_FontSpanPixels = 0
    backend_FontSpanWidth = 0
    backend_FontSpanHeight = 0
    backend_FontSpanPitch = 0
End Sub

Private Function backend_FontSpanDepth() As Integer
    ' Mode changes belong to the GUI thread. Sample depth once for this text
    ' draw; no application callbacks or display-page changes occur inside it.
    ' SCREENINFO also applies a pending native resize. The direct writer still
    ' revalidates dimensions, pitch and the current page under its own lock.
    Dim As Integer screenWidth, screenHeight, screenDepth
    ScreenInfo screenWidth, screenHeight, screenDepth
    If screenWidth <= 0 OrElse screenHeight <= 0 Then Return 0
    Return screenDepth
End Function

Private Function backend_FontSpanBegin(ByVal widthValue As Integer, _
    ByVal heightValue As Integer, ByVal screenDepth As Integer = 0) As Integer
#If Defined(__FB_GFXLIB3__) Or Defined(OMAGUI_DISABLE_FONT_SPANS)
    ' GPU pages retain their existing drawing path. The disabling define also
    ' lets pixel comparisons qualify the new blit against the original path.
    Return 0
#Else
    If widthValue <= 0 OrElse heightValue <= 0 Then Return 0
    If screenDepth = 0 Then screenDepth = backend_FontSpanDepth()
    If screenDepth <> 32 Then Return 0
    If widthValue <= backend_FontSpanWidth AndAlso heightValue <= backend_FontSpanHeight Then Return -1

    Dim As Integer newWidth = widthValue
    Dim As Integer newHeight = heightValue
    If newWidth < backend_FontSpanWidth Then newWidth = backend_FontSpanWidth
    If newHeight < backend_FontSpanHeight Then newHeight = backend_FontSpanHeight
    ' IMAGECREATE aligns each RGBA row to 16 bytes. Include that padding in
    ' the pixel budget before allocating; narrow tall images need it too.
    If newWidth > BACKEND_FONT_SPAN_MAX_PIXELS - 3 Then Return 0
    Dim As Integer paddedWidth = ((newWidth + 3) \ 4) * 4
    If paddedWidth > BACKEND_FONT_SPAN_MAX_PIXELS \ newHeight Then Return 0
    Dim As Any Ptr newImage = ImageCreate(newWidth, newHeight, 0, 32)
    If newImage = 0 Then Return 0
    Dim As Integer actualWidth, actualHeight, bytesPerPixel, pitchBytes, imageBytes
    Dim As Any Ptr pixels
    If ImageInfo(newImage, actualWidth, actualHeight, bytesPerPixel, pitchBytes, pixels, imageBytes) <> 0 OrElse _
       actualWidth <> newWidth OrElse actualHeight <> newHeight OrElse bytesPerPixel <> 4 OrElse _
       pixels = 0 OrElse pitchBytes < newWidth * 4 OrElse (pitchBytes Mod 4) <> 0 OrElse _
       CLngInt(pitchBytes) * newHeight > imageBytes OrElse _
       CLngInt(pitchBytes) * newHeight > CLngInt(BACKEND_FONT_SPAN_MAX_PIXELS) * 4 Then
        ImageDestroy newImage
        Return 0
    End If
    backend_FontSpanRelease
    backend_FontSpanImage = newImage
    backend_FontSpanPixels = pixels
    backend_FontSpanWidth = newWidth
    backend_FontSpanHeight = newHeight
    backend_FontSpanPitch = pitchBytes \ 4
    Return -1
#EndIf
End Function

Private Function backend_FontSpanBlend(ByVal sourcePixel As ULong, _
    ByVal destinationPixel As ULong, ByVal userData As Any Ptr) As ULong
    If userData = 0 Then Return destinationPixel
    Dim As ULong coverage = sourcePixel Shr 24
    If coverage = 0 Then Return destinationPixel
    Dim As ULong clr = *Cast(ULong Ptr, userData)
    If coverage = 255 Then Return clr
    Dim As ULong inverseCoverage = 255 - coverage
    ' Match backend_PSetAlpha exactly. PUT ALPHA uses different rounding.
    Dim As ULong redValue = (((clr Shr 16) And 255) * coverage + _
        ((destinationPixel Shr 16) And 255) * inverseCoverage)
    Dim As ULong greenValue = (((clr Shr 8) And 255) * coverage + _
        ((destinationPixel Shr 8) And 255) * inverseCoverage)
    Dim As ULong blueValue = ((clr And 255) * coverage + _
        (destinationPixel And 255) * inverseCoverage)
    ' Each weighted channel lies in 0..65025 because its weights sum to 255.
    ' This exact quotient avoids three integer divisions per covered pixel on
    ' the DOS assembly backend, which cannot strength-reduce constant division.
    redValue = (redValue + 1 + (redValue Shr 8)) Shr 8
    greenValue = (greenValue + 1 + (greenValue Shr 8)) Shr 8
    blueValue = (blueValue + 1 + (blueValue Shr 8)) Shr 8
    Return RGB(redValue, greenValue, blueValue)
End Function

' Direct access is confined to this backend's absolute screen coordinates.
' SCREENPTR selects the current work page. The GUI owns the clip stack; each
' write takes a balanced screen lock and reports the touched rows on unlock.
' Validate the pitch and page before deriving pointers. PUT remains the fallback.
Private Function backend_FontSpanDirect(ByVal x As Integer, ByVal y As Integer, _
    ByVal widthValue As Integer, ByVal heightValue As Integer, ByVal clr As ULong) As Integer
#If Defined(__FB_GFXLIB3__) Or Defined(OMAGUI_DISABLE_FONT_SPANS)
    Return 0
#Else
    If backend_FontSpanPixels = 0 OrElse widthValue <= 0 OrElse heightValue <= 0 OrElse _
       widthValue > backend_FontSpanWidth OrElse heightValue > backend_FontSpanHeight Then Return 0
    ScreenLock
    Dim As Integer screenWidth, screenHeight, screenDepth, bytesPerPixel, pitchBytes
    ScreenInfo screenWidth, screenHeight, screenDepth, bytesPerPixel, pitchBytes
    Dim As UByte Ptr pageBytes = ScreenPtr
    Dim As Integer result = 0
    Dim As Integer dirtyFirstRow = 1
    Dim As Integer dirtyLastRow = 0
    ' Limit the page extent to signed 32-bit byte offsets on every target.
    ' This covers GUI pages and avoids target-dependent pointer arithmetic.
    If pageBytes <> 0 AndAlso screenWidth > 0 AndAlso screenHeight > 0 AndAlso _
       screenDepth = 32 AndAlso bytesPerPixel = 4 AndAlso pitchBytes > 0 AndAlso _
       (pitchBytes Mod 4) = 0 AndAlso CLngInt(screenWidth) * 4 <= pitchBytes AndAlso _
       CLngInt(pitchBytes) * screenHeight <= &H7FFFFFFF Then
        result = -1
        ' Reject distant coordinates before adding dimensions, including the
        ' minimum/maximum signed INTEGER values supplied by a malformed caller.
        If CLngInt(x) > -CLngInt(widthValue) AndAlso x < screenWidth AndAlso _
           CLngInt(y) > -CLngInt(heightValue) AndAlso y < screenHeight Then
            Dim As Integer firstX = IIf(x < 0, 0, x)
            Dim As Integer firstY = IIf(y < 0, 0, y)
            Dim As Integer lastX = CInt(CLngInt(x) + widthValue - 1)
            Dim As Integer lastY = CInt(CLngInt(y) + heightValue - 1)
            If lastX >= screenWidth Then lastX = screenWidth - 1
            If lastY >= screenHeight Then lastY = screenHeight - 1
            If backend_ClipDepth > 0 Then
                Dim As Integer clipIndex = backend_ClipDepth - 1
                If firstX < backend_ClipX1(clipIndex) Then firstX = backend_ClipX1(clipIndex)
                If firstY < backend_ClipY1(clipIndex) Then firstY = backend_ClipY1(clipIndex)
                If lastX > backend_ClipX2(clipIndex) Then lastX = backend_ClipX2(clipIndex)
                If lastY > backend_ClipY2(clipIndex) Then lastY = backend_ClipY2(clipIndex)
            End If
            If firstX <= lastX AndAlso firstY <= lastY Then
                For rowIndex As Integer = firstY To lastY
                    Dim As ULong Ptr destinationRow = _
                        Cast(ULong Ptr, pageBytes + rowIndex * pitchBytes)
                    Dim As ULong Ptr coverageRow = backend_FontSpanPixels + _
                        (rowIndex - y) * backend_FontSpanPitch + (firstX - x)
                    For columnIndex As Integer = 0 To lastX - firstX
                        Dim As Integer targetX = firstX + columnIndex
                        Dim As ULong sourcePixel = coverageRow[columnIndex]
                        ' Sparse masks avoid a callback and a store for transparent pixels.
                        If (sourcePixel Shr 24) <> 0 Then _
                            destinationRow[targetX] = backend_FontSpanBlend( _
                                sourcePixel, destinationRow[targetX], @clr _
                            )
                    Next columnIndex
                Next rowIndex
                dirtyFirstRow = firstY
                dirtyLastRow = lastY
            End If
        End If
    End If
    ScreenUnlock dirtyFirstRow, dirtyLastRow
    Return result
#EndIf
End Function

Private Sub backend_FontSpanEnd(ByVal x As Integer, ByVal y As Integer, _
    ByVal widthValue As Integer, ByVal heightValue As Integer, ByVal clr As ULong)
    If backend_FontSpanImage = 0 OrElse widthValue <= 0 OrElse heightValue <= 0 OrElse _
       widthValue > backend_FontSpanWidth OrElse heightValue > backend_FontSpanHeight Then Exit Sub
#Ifndef OMAGUI_DISABLE_FONT_DIRECT
    If backend_FontSpanDirect(x, y, widthValue, heightValue, clr) <> 0 Then Exit Sub
#EndIf
    Put (x, y), backend_FontSpanImage, (0, 0)-(widthValue - 1, heightValue - 1), _
        Custom, @backend_FontSpanBlend, @clr
End Sub

' end of backend_font_span.bi
