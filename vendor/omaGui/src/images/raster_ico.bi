/'
    Project: omaGUI Portable Raster Images
    File: raster_ico.bi
    Purpose: Decode classic ICO bitmaps without platform image APIs.
    Responsibilities:
        - validate the directory and first image's DIB, palette, and masks
        - convert opaque pixels and transparent AND-mask pixels to RGBA
    Targets:

        FreeBASIC builds with built-in gfxlib; gfxlib3 is optional when supplied by the compiler.

    Module API:

        Declarations for the raster_ico component in the omaGUI include graph.

    This file intentionally does NOT contain:
        - cursor loading, PNG icons, or destination-dependent XOR drawing

    Private implementation included by raster_image.bas after its byte helpers.
    ICO starts with a six-byte directory header and 16 bytes per entry.
    Entry offsets are absolute. A 40-byte BITMAPINFOHEADER is followed by
    BGR0 palette entries, bottom-up XOR rows, then bottom-up 1-bit AND rows.
    Both row types are padded to four bytes; DIB height counts both masks.
    The first directory entry is selected, independent of display resolution.

    Directory entry fields: width/height/color count/reserved at 0..3,
    planes/depth at 4/6, byte length at 8, absolute file offset at 12.
    DIB fields: header size at 0, width/height at 4/8, planes/depth at 12/14,
    compression at 16, and used palette entries at 32.
'/

Private Function rasterico_Decode( _
    bytes() As UByte, ByVal byteCount As LongInt, _
    ByRef loadedImage As RasterImage Ptr, ByRef errorMessage As String _
) As Integer
    Dim As ULong entryCount, imageOffset, imageLength, headerSize
    Dim As ULong dibWidth, dibHeight, planes, bitCount, compression, colorCount
    Dim As Long imageWidth, imageHeight, xorStride, andStride
    Dim As LongInt paletteOffset, xorOffset, andOffset
    Dim As ULong paletteColors(0 To 255)
    Dim As Any Ptr imagePixels, pixelBytes
    Dim As Integer bufferWidth, bufferHeight, bytesPerPixel, pitch, bufferSize
    Const RASTERICO_DIRECTORY_HEADER_BYTES As LongInt = 6
    Const RASTERICO_DIRECTORY_ENTRY_BYTES As LongInt = 16

    errorMessage = "ICO directory is truncated or invalid"
    If byteCount < RASTERICO_DIRECTORY_HEADER_BYTES + _
        RASTERICO_DIRECTORY_ENTRY_BYTES Then Return 0
    rasterimage_ReadU16LE bytes(), byteCount, 4, entryCount
    If entryCount = 0 OrElse entryCount > _
        (byteCount - RASTERICO_DIRECTORY_HEADER_BYTES) \ _
        RASTERICO_DIRECTORY_ENTRY_BYTES Then Return 0
    ' Check every entry span even though only the first frame is decoded.
    For entryIndex As Long = 0 To entryCount - 1
        Dim As LongInt wideEntryIndex = entryIndex
        Dim As LongInt entryOffset = RASTERICO_DIRECTORY_HEADER_BYTES + _
            (wideEntryIndex * RASTERICO_DIRECTORY_ENTRY_BYTES)
        Dim As ULong spanOffset, spanLength
        rasterimage_ReadU32LE bytes(), byteCount, entryOffset + 8, spanLength
        rasterimage_ReadU32LE bytes(), byteCount, entryOffset + 12, spanOffset
        If spanOffset < RASTERICO_DIRECTORY_HEADER_BYTES + _
            CLngInt(entryCount) * RASTERICO_DIRECTORY_ENTRY_BYTES OrElse _
           spanOffset > byteCount OrElse spanLength = 0 OrElse _
           spanLength > byteCount - spanOffset Then Return 0
        If bytes(entryOffset + 3) <> 0 Then Return 0
    Next entryIndex
    rasterimage_ReadU32LE bytes(), byteCount, 14, imageLength
    rasterimage_ReadU32LE bytes(), byteCount, 18, imageOffset
    errorMessage = "ICO requires a 40-byte uncompressed bitmap header"
    If imageLength < 40 Then Return 0
    rasterimage_ReadU32LE bytes(), byteCount, imageOffset, headerSize
    If headerSize <> 40 Then Return 0
    rasterimage_ReadU32LE bytes(), byteCount, imageOffset + 4, dibWidth
    rasterimage_ReadU32LE bytes(), byteCount, imageOffset + 8, dibHeight
    rasterimage_ReadU16LE bytes(), byteCount, imageOffset + 12, planes
    rasterimage_ReadU16LE bytes(), byteCount, imageOffset + 14, bitCount
    rasterimage_ReadU32LE bytes(), byteCount, imageOffset + 16, compression
    rasterimage_ReadU32LE bytes(), byteCount, imageOffset + 32, colorCount
    If planes <> 1 OrElse compression <> 0 Then Return 0
    imageWidth = IIf(bytes(6) = 0, 256, bytes(6))
    imageHeight = IIf(bytes(7) = 0, 256, bytes(7))
    errorMessage = "ICO directory and bitmap dimensions disagree"
    If dibWidth <> imageWidth OrElse dibHeight <> imageHeight * 2 Then Return 0
    errorMessage = "ICO bitmap depth is not supported (expected 1, 4, 8, or 24 bits)"
    Select Case bitCount
    Case 1, 4, 8
        If colorCount = 0 Then colorCount = 1 Shl bitCount
        If colorCount > (1 Shl bitCount) Then Return 0
    Case 24
        If colorCount <> 0 Then Return 0
    Case Else
        Return 0
    End Select
    paletteOffset = CLngInt(imageOffset) + 40
    xorStride = ((imageWidth * bitCount + 31) \ 32) * 4
    andStride = ((imageWidth + 31) \ 32) * 4
    xorOffset = paletteOffset + colorCount * 4
    andOffset = xorOffset + CLngInt(xorStride) * imageHeight
    errorMessage = "ICO bitmap palette or masks are truncated"
    If andOffset + CLngInt(andStride) * imageHeight > CLngInt(imageOffset) + imageLength Then Return 0
    For colorIndex As Long = 0 To CLng(colorCount) - 1
        Dim As LongInt offsetValue = _
            paletteOffset + CLngInt(colorIndex) * 4LL
        Dim As UByte paletteRed = bytes(offsetValue + 2)
        Dim As UByte paletteGreen = bytes(offsetValue + 1)
        Dim As UByte paletteBlue = bytes(offsetValue)
        paletteColors(colorIndex) = RGB(paletteRed, paletteGreen, paletteBlue)
    Next colorIndex

    imagePixels = backend_CreateImage(imageWidth, imageHeight, RGBA(0, 0, 0, 0), 32)
    errorMessage = "unable to allocate ICO pixels"
    If imagePixels = 0 Then Return 0
    If ImageInfo(imagePixels, bufferWidth, bufferHeight, bytesPerPixel, pitch, pixelBytes, bufferSize) <> 0 OrElse _
       bytesPerPixel <> 4 OrElse pixelBytes = 0 OrElse bufferWidth <> imageWidth OrElse _
       bufferHeight <> imageHeight OrElse pitch < imageWidth * 4 OrElse _
       CLngInt(pitch) * imageHeight > bufferSize Then
        ImageDestroy imagePixels
        Return 0
    End If
    For rowIndex As Long = 0 To imageHeight - 1
        Dim As LongInt xorRow = xorOffset + _
            CLngInt(imageHeight - 1 - rowIndex) * CLngInt(xorStride)
        Dim As LongInt andRow = andOffset + _
            CLngInt(imageHeight - 1 - rowIndex) * CLngInt(andStride)
        Dim As ULong Ptr destinationRow = Cast(ULong Ptr, _
            Cast(UByte Ptr, pixelBytes) + CLngInt(rowIndex) * pitch)
        For columnIndex As Long = 0 To imageWidth - 1
            Dim As ULong pixelColor
            If bitCount = 24 Then
                Dim As LongInt offsetValue = _
                    xorRow + CLngInt(columnIndex) * 3LL
                Dim As UByte pixelRed = bytes(offsetValue + 2)
                Dim As UByte pixelGreen = bytes(offsetValue + 1)
                Dim As UByte pixelBlue = bytes(offsetValue)
                pixelColor = RGB(pixelRed, pixelGreen, pixelBlue)
            Else
                Dim As Long bitOffset = columnIndex * bitCount
                Dim As Long colorIndex = (bytes(xorRow + bitOffset \ 8) Shr _
                    (8 - bitCount - (bitOffset And 7))) And ((1 Shl bitCount) - 1)
                If colorIndex >= colorCount Then
                    ImageDestroy imagePixels
                    errorMessage = "ICO pixel refers outside its palette"
                    Return 0
                End If
                pixelColor = paletteColors(colorIndex)
            End If
            If (bytes(andRow + columnIndex \ 8) And (128 Shr (columnIndex And 7))) <> 0 Then
                ' AND=1/XOR=0 preserves the destination. Nonzero XOR needs
                ' destination-dependent compositing, which RGBA cannot express.
                If (pixelColor And &hFFFFFFUL) <> 0 Then
                    ImageDestroy imagePixels
                    errorMessage = "ICO destination-dependent XOR pixels are not supported"
                    Return 0
                End If
                pixelColor = 0
            Else
                pixelColor Or= &hFF000000UL
            End If
            ' ImageInfo validated the buffer size and pitch above.
            destinationRow[columnIndex] = pixelColor
        Next columnIndex
    Next rowIndex
    errorMessage = ""
    Return rasterimage_NewRecord(imagePixels, imageWidth, imageHeight, _
        RASTERIMAGE_FORMAT_ICO, -1, loadedImage, errorMessage)
End Function

/' end of raster_ico.bi '/
