/'
    Project: omaGUI gfxlib backend
    File: backend_font_span.bi
    Purpose: Present glyph coverage with one gfxlib blit per glyph.
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
    PUT owns framebuffer locking and clipping. Its synchronous custom blender
    borrows the caller's color only until PUT returns. The mask remains owned
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

Private Function backend_FontSpanBegin(ByVal widthValue As Integer, _
    ByVal heightValue As Integer) As Integer
#If Defined(__FB_GFXLIB3__) Or Defined(OMAGUI_DISABLE_FONT_SPANS)
    ' GPU pages retain their existing drawing path. The disabling define also
    ' lets pixel comparisons qualify the new blit against the original path.
    Return 0
#Else
    If widthValue <= 0 OrElse heightValue <= 0 Then Return 0
    Dim As Integer screenWidth, screenHeight, screenDepth
    ScreenInfo screenWidth, screenHeight, screenDepth
    If screenWidth <= 0 OrElse screenHeight <= 0 OrElse screenDepth <> 32 Then Return 0
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

Private Sub backend_FontSpanEnd(ByVal x As Integer, ByVal y As Integer, _
    ByVal widthValue As Integer, ByVal heightValue As Integer, ByVal clr As ULong)
    If backend_FontSpanImage = 0 OrElse widthValue <= 0 OrElse heightValue <= 0 OrElse _
       widthValue > backend_FontSpanWidth OrElse heightValue > backend_FontSpanHeight Then Exit Sub
    Put (x, y), backend_FontSpanImage, (0, 0)-(widthValue - 1, heightValue - 1), _
        Custom, @backend_FontSpanBlend, @clr
End Sub

' end of backend_font_span.bi
