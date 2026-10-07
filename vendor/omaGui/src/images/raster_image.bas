/'
    Project: omaGUI Portable Raster Images
    --------------------------------------

    File: raster_image.bas

    Purpose:

        Load the small raster format set used by omaGUI technical documents.

    Responsibilities:

        - identify images by file signature rather than filename extension
        - delegate BMP and PNG files to the FreeBASIC gfxlib loader
        - bridge in-memory BMP and PNG data through bounded transient files
        - decode GIF87a/GIF89a LZW images, including transparency
        - decode 8-bit baseline sequential JPEG images
        - decode classic ICO bitmaps and their transparent masks
        - return owned 32-bit gfxlib image buffers with checked dimensions

    Ownership:

        The caller owns a successfully loaded RasterImage and releases it with
        rasterimage_Destroy. The loader closes its file handles and transient
        files before returning.

    Targets:

        FreeBASIC builds with built-in gfxlib; gfxlib3 is optional when supplied by the compiler.

    Module API:

        Implementation unit assembled by omaGUI.bi when OMAGUI_IMPLEMENTATION is defined.

    This file intentionally does NOT contain:

        - progressive JPEG, animated GIF playback, or image encoding
        - networking, persistent image caching, or platform image APIs
        - HTML resource resolution or rendering policy
'/

#lang "fb"

#include once "src/images/raster_image.bi"

Const RASTERIMAGE_GIF_MAX_CODES As Integer = 4096
Const RASTERIMAGE_JPEG_MAX_COMPONENTS As Integer = 4
Const RASTERIMAGE_JPEG_MAX_TABLES As Integer = 4

#if defined(__FB_WIN32__) Or defined(__FB_DOS__)
Const RASTERIMAGE_PATH_SEPARATOR As String = "\"
#else
Const RASTERIMAGE_PATH_SEPARATOR As String = "/"
#endif

' -------------------------------------------------------------------------
' Shared checked byte helpers
' -------------------------------------------------------------------------

Private Function rasterimage_ReadU16LE( _
    bytes() As UByte, ByVal byteCount As LongInt, _
    ByVal byteOffset As LongInt, ByRef value As ULong _
) As Integer
    If byteOffset < 0 OrElse byteOffset > byteCount OrElse _
       byteCount - byteOffset < 2 Then Return 0
    value = CULng(bytes(byteOffset)) Or _
        (CULng(bytes(byteOffset + 1)) Shl 8)
    Return -1
End Function


Private Function rasterimage_ReadU16BE( _
    bytes() As UByte, ByVal byteCount As LongInt, _
    ByVal byteOffset As LongInt, ByRef value As ULong _
) As Integer
    If byteOffset < 0 OrElse byteOffset > byteCount OrElse _
       byteCount - byteOffset < 2 Then Return 0
    value = (CULng(bytes(byteOffset)) Shl 8) Or _
        CULng(bytes(byteOffset + 1))
    Return -1
End Function


Private Function rasterimage_ReadU32LE( _
    bytes() As UByte, ByVal byteCount As LongInt, _
    ByVal byteOffset As LongInt, ByRef value As ULong _
) As Integer
    If byteOffset < 0 OrElse byteOffset > byteCount OrElse _
       byteCount - byteOffset < 4 Then Return 0
    value = CULng(bytes(byteOffset)) Or _
        (CULng(bytes(byteOffset + 1)) Shl 8) Or _
        (CULng(bytes(byteOffset + 2)) Shl 16) Or _
        (CULng(bytes(byteOffset + 3)) Shl 24)
    Return -1
End Function


Private Function rasterimage_ReadU32BE( _
    bytes() As UByte, ByVal byteCount As LongInt, _
    ByVal byteOffset As LongInt, ByRef value As ULong _
) As Integer
    If byteOffset < 0 OrElse byteOffset > byteCount OrElse _
       byteCount - byteOffset < 4 Then Return 0
    value = (CULng(bytes(byteOffset)) Shl 24) Or _
        (CULng(bytes(byteOffset + 1)) Shl 16) Or _
        (CULng(bytes(byteOffset + 2)) Shl 8) Or _
        CULng(bytes(byteOffset + 3))
    Return -1
End Function


Private Function rasterimage_ValidateDimensions( _
    ByVal imageWidth As Long, ByVal imageHeight As Long, _
    ByRef errorMessage As String _
) As Integer
    Dim As ULongInt pixelCount

    If imageWidth < 1 OrElse imageHeight < 1 Then
        errorMessage = "image dimensions must be positive"
        Return 0
    End If
    If imageWidth > RASTERIMAGE_MAX_DIMENSION OrElse _
       imageHeight > RASTERIMAGE_MAX_DIMENSION Then
        errorMessage = "image dimension exceeds the 4,096 pixel safety limit"
        Return 0
    End If

    pixelCount = CULngInt(imageWidth) * CULngInt(imageHeight)
    If pixelCount > RASTERIMAGE_MAX_PIXELS Then
        errorMessage = "image exceeds the 16,777,216 pixel safety limit"
        Return 0
    End If
    Return -1
End Function


Private Function rasterimage_NewRecord( _
    ByVal imagePixels As Any Ptr, _
    ByVal imageWidth As Long, ByVal imageHeight As Long, _
    ByVal formatKind As Integer, ByVal hasAlpha As Integer, _
    ByRef loadedImage As RasterImage Ptr, _
    ByRef errorMessage As String _
) As Integer
    Dim As RasterImage Ptr imageRecord

    imageRecord = New RasterImage
    If imageRecord = 0 Then
        If imagePixels <> 0 Then ImageDestroy imagePixels
        errorMessage = "unable to allocate raster image metadata"
        Return 0
    End If

    imageRecord->pixels = imagePixels
    imageRecord->width = imageWidth
    imageRecord->height = imageHeight
    imageRecord->formatKind = formatKind
    imageRecord->hasAlpha = hasAlpha
    loadedImage = imageRecord
    Return -1
End Function


' -------------------------------------------------------------------------
' Format detection
' -------------------------------------------------------------------------

Function rasterimage_DetectFormat( _
    bytes() As UByte, ByVal byteCount As LongInt _
) As Integer
    ' Dimension zero safely reports whether the byte array is allocated.
    ' fblint: disable-next-line FBL-ARR-004 -- this query does not read an element bound.
    If UBound(bytes, 0) <> 1 Then Return RASTERIMAGE_FORMAT_UNKNOWN
    Dim As Integer firstIndex
    Dim As Integer lastIndex

    If byteCount < 1 Then Return RASTERIMAGE_FORMAT_UNKNOWN
    ' FreeBASIC reports UBound=-1 for an unallocated dynamic array.
    If UBound(bytes) < LBound(bytes) Then Return RASTERIMAGE_FORMAT_UNKNOWN
    firstIndex = LBound(bytes)
    lastIndex = UBound(bytes)
    If firstIndex <> 0 OrElse lastIndex < firstIndex OrElse _
       byteCount > CLngInt(lastIndex) + 1 Then Return RASTERIMAGE_FORMAT_UNKNOWN
    If byteCount >= 8 Then
        If bytes(0) = &h89 AndAlso bytes(1) = Asc("P") AndAlso _
           bytes(2) = Asc("N") AndAlso bytes(3) = Asc("G") AndAlso _
           bytes(4) = &h0D AndAlso bytes(5) = &h0A AndAlso _
           bytes(6) = &h1A AndAlso bytes(7) = &h0A Then
            Return RASTERIMAGE_FORMAT_PNG
        End If
    End If
    If byteCount >= 6 Then
        If bytes(0) = 0 AndAlso bytes(1) = 0 AndAlso _
           bytes(2) = 1 AndAlso bytes(3) = 0 Then Return RASTERIMAGE_FORMAT_ICO
        If bytes(0) = Asc("G") AndAlso bytes(1) = Asc("I") AndAlso _
           bytes(2) = Asc("F") AndAlso bytes(3) = Asc("8") AndAlso _
           (bytes(4) = Asc("7") OrElse bytes(4) = Asc("9")) AndAlso _
           bytes(5) = Asc("a") Then Return RASTERIMAGE_FORMAT_GIF
    End If
    If byteCount >= 3 Then
        If bytes(0) = &hFF AndAlso bytes(1) = &hD8 AndAlso _
           bytes(2) = &hFF Then Return RASTERIMAGE_FORMAT_JPEG
    End If
    If byteCount >= 2 Then
        If bytes(0) = Asc("B") AndAlso bytes(1) = Asc("M") Then
            Return RASTERIMAGE_FORMAT_BMP
        End If
    End If
    Return RASTERIMAGE_FORMAT_UNKNOWN
End Function


' -------------------------------------------------------------------------
' Classic icon decoder
' -------------------------------------------------------------------------

#include once "src/images/raster_ico.bi"

' -------------------------------------------------------------------------
' GIF LZW decoder
' -------------------------------------------------------------------------

Private Function rastergif_ReadCode( _
    compressedBytes() As UByte, ByVal compressedCount As Long, _
    ByRef bitPosition As Long, ByVal codeSize As Integer _
) As Integer
    Dim As ULong packedValue
    Dim As Long bytePosition
    Dim As Integer bitOffset
    Dim As Integer byteIndex

    If codeSize < 2 OrElse codeSize > 12 Then Return -1
    If bitPosition < 0 OrElse _
       bitPosition + codeSize > compressedCount * 8 Then Return -1

    bytePosition = bitPosition \ 8
    bitOffset = bitPosition And 7
    packedValue = 0
    For byteIndex = 0 To 2
        If bytePosition + byteIndex < compressedCount Then
            packedValue Or= _
                CULng(compressedBytes(bytePosition + byteIndex)) Shl _
                (byteIndex * 8)
        End If
    Next byteIndex

    bitPosition += codeSize
    Return (packedValue Shr bitOffset) And ((1 Shl codeSize) - 1)
End Function


Private Function rastergif_DecodeLzw( _
    compressedBytes() As UByte, ByVal compressedCount As Long, _
    ByVal minimumCodeSize As Integer, ByVal expectedCount As Long, _
    decodedIndices() As UByte, ByRef errorMessage As String _
) As Integer
    Dim As Integer prefix(0 To RASTERIMAGE_GIF_MAX_CODES - 1)
    Dim As UByte suffix(0 To RASTERIMAGE_GIF_MAX_CODES - 1)
    Dim As UByte pixelStack(0 To RASTERIMAGE_GIF_MAX_CODES - 1)
    Dim As Integer clearCode
    Dim As Integer endCode
    Dim As Integer nextCode
    Dim As Integer codeSize
    Dim As Integer codeLimit
    Dim As Integer code
    Dim As Integer oldCode
    Dim As Integer inputCode
    Dim As Integer firstValue
    Dim As Integer stackCount
    Dim As Long bitPosition
    Dim As Long outputCount
    Dim As Integer index

    If minimumCodeSize < 2 OrElse minimumCodeSize > 8 Then
        errorMessage = "GIF has an unsupported LZW minimum code size"
        Return 0
    End If
    If expectedCount < 1 Then
        errorMessage = "GIF image contains no pixels"
        Return 0
    End If

    ReDim decodedIndices(0 To expectedCount - 1)
    clearCode = 1 Shl minimumCodeSize
    endCode = clearCode + 1
    nextCode = endCode + 1
    codeSize = minimumCodeSize + 1
    codeLimit = 1 Shl codeSize
    oldCode = -1

    For index = 0 To clearCode - 1
        suffix(index) = index
    Next index

    Do While outputCount < expectedCount
        code = rastergif_ReadCode( _
            compressedBytes(), compressedCount, bitPosition, codeSize _
        )
        If code < 0 Then
            errorMessage = "GIF LZW stream ended before all pixels were decoded"
            Return 0
        End If

        If code = clearCode Then
            nextCode = endCode + 1
            codeSize = minimumCodeSize + 1
            codeLimit = 1 Shl codeSize
            oldCode = -1
            Continue Do
        End If
        If code = endCode Then Exit Do

        If oldCode < 0 Then
            If code >= clearCode Then
                errorMessage = "GIF LZW stream begins with an invalid code"
                Return 0
            End If
            decodedIndices(outputCount) = suffix(code)
            outputCount += 1
            firstValue = suffix(code)
            oldCode = code
            Continue Do
        End If

        inputCode = code
        stackCount = 0
        If code = nextCode Then
            pixelStack(stackCount) = firstValue
            stackCount += 1
            code = oldCode
        ElseIf code > nextCode Then
            errorMessage = "GIF LZW stream references an undefined code"
            Return 0
        End If

        While code >= clearCode
            If code >= nextCode OrElse stackCount >= RASTERIMAGE_GIF_MAX_CODES Then
                errorMessage = "GIF LZW dictionary chain is invalid"
                Return 0
            End If
            pixelStack(stackCount) = suffix(code)
            stackCount += 1
            code = prefix(code)
        Wend

        firstValue = suffix(code)
        If stackCount >= RASTERIMAGE_GIF_MAX_CODES Then
            errorMessage = "GIF LZW output stack exceeds its code limit"
            Return 0
        End If
        pixelStack(stackCount) = firstValue
        stackCount += 1

        While stackCount > 0
            stackCount -= 1
            If outputCount >= expectedCount Then Exit While
            decodedIndices(outputCount) = pixelStack(stackCount)
            outputCount += 1
        Wend

        If nextCode < RASTERIMAGE_GIF_MAX_CODES Then
            prefix(nextCode) = oldCode
            suffix(nextCode) = firstValue
            nextCode += 1
            If nextCode = codeLimit AndAlso codeSize < 12 Then
                codeSize += 1
                codeLimit = 1 Shl codeSize
            End If
        End If
        oldCode = inputCode
    Loop

    If outputCount <> expectedCount Then
        errorMessage = "GIF LZW stream produced the wrong pixel count"
        Return 0
    End If
    Return -1
End Function


Private Function rastergif_CollectSubBlocks( _
    bytes() As UByte, ByVal byteCount As LongInt, _
    ByRef position As LongInt, compressedBytes() As UByte, _
    ByRef compressedCount As Long, ByRef errorMessage As String _
) As Integer
    Dim As LongInt scanPosition
    Dim As LongInt copyPosition
    Dim As Long totalCount
    Dim As Integer blockCount
    Dim As Long outputPosition

    scanPosition = position
    Do
        If scanPosition >= byteCount Then
            errorMessage = "GIF data sub-block list is truncated"
            Return 0
        End If
        blockCount = bytes(scanPosition)
        scanPosition += 1
        If blockCount = 0 Then Exit Do
        If scanPosition > byteCount OrElse _
           blockCount > byteCount - scanPosition Then
            errorMessage = "GIF data sub-block extends beyond the file"
            Return 0
        End If
        If totalCount > RASTERIMAGE_MAX_FILE_BYTES - blockCount Then
            errorMessage = "GIF compressed data exceeds the file safety limit"
            Return 0
        End If
        totalCount += blockCount
        scanPosition += blockCount
    Loop

    If totalCount < 1 Then
        errorMessage = "GIF image has no compressed pixel data"
        Return 0
    End If

    ReDim compressedBytes(0 To totalCount - 1)
    copyPosition = position
    Do
        blockCount = bytes(copyPosition)
        copyPosition += 1
        If blockCount = 0 Then Exit Do
        For blockIndex As Integer = 0 To blockCount - 1
            compressedBytes(outputPosition) = bytes(copyPosition + blockIndex)
            outputPosition += 1
        Next blockIndex
        copyPosition += blockCount
    Loop

    position = scanPosition
    compressedCount = totalCount
    Return -1
End Function


' fblint: disable-next-line FBL110,FBL111 -- GIF block state and output bounds stay together in this decoder pass.
Private Function rastergif_Decode( _
    bytes() As UByte, ByVal byteCount As LongInt, _
    ByRef loadedImage As RasterImage Ptr, _
    ByRef errorMessage As String _
) As Integer
    Dim As ULong globalPalette(0 To 255)
    Dim As ULong activePalette(0 To 255)
    Dim As Integer globalPaletteCount
    Dim As Integer activePaletteCount
    Dim As ULong logicalWidthValue
    Dim As ULong logicalHeightValue
    Dim As ULong imageLeftValue
    Dim As ULong imageTopValue
    Dim As ULong imageWidthValue
    Dim As ULong imageHeightValue
    Dim As Long logicalWidth
    Dim As Long logicalHeight
    Dim As Long imageLeft
    Dim As Long imageTop
    Dim As Long imageWidth
    Dim As Long imageHeight
    Dim As Integer packedFields
    Dim As Integer backgroundIndex
    Dim As Integer transparentIndex = -1
    Dim As Integer colorTableIndex
    Dim As Integer localPaletteCount
    Dim As Integer extensionLabel
    Dim As Integer blockCount
    Dim As Integer lzwMinimumCodeSize
    Dim As Integer interlaced
    Dim As LongInt position
    Dim As Long paletteByteCount
    Dim As UByte compressedBytes()
    Dim As Long compressedCount
    Dim As UByte decodedIndices()
    Dim As Any Ptr imagePixels
    Dim As Any Ptr pixelData
    Dim As Long bufferWidth
    Dim As Long bufferHeight
    Dim As Long bytesPerPixel
    Dim As Long pitch
    Dim As Long imageBufferSize
    Dim As Long sourceRow
    Dim As Long destinationRow
    Dim As Long sourceIndex
    Dim As Long x
    Dim As Long y
    Dim As Integer passIndex
    Dim As Integer passStart(0 To 3) = {0, 4, 2, 1}
    Dim As Integer passStep(0 To 3) = {8, 8, 4, 2}
    Dim As UByte colorIndex
    Dim As ULong outputColor
    Dim As ULong backgroundColor
    Dim As Integer foundImage

    If byteCount < 13 Then
        errorMessage = "GIF logical screen descriptor is truncated"
        Return 0
    End If
    If Not rasterimage_ReadU16LE( _
        bytes(), byteCount, 6, logicalWidthValue _
    ) OrElse Not rasterimage_ReadU16LE( _
        bytes(), byteCount, 8, logicalHeightValue _
    ) Then
        errorMessage = "GIF dimensions are truncated"
        Return 0
    End If

    logicalWidth = logicalWidthValue
    logicalHeight = logicalHeightValue
    If Not rasterimage_ValidateDimensions( _
        logicalWidth, logicalHeight, errorMessage _
    ) Then Return 0

    packedFields = bytes(10)
    backgroundIndex = bytes(11)
    position = 13
    If packedFields And &h80 Then
        globalPaletteCount = 1 Shl ((packedFields And 7) + 1)
        paletteByteCount = globalPaletteCount * 3
        If position > byteCount OrElse paletteByteCount > byteCount - position Then
            errorMessage = "GIF global color table is truncated"
            Return 0
        End If
        For colorTableIndex = 0 To globalPaletteCount - 1
            Dim As UByte globalPaletteRed = bytes(position + colorTableIndex * 3)
            Dim As UByte globalPaletteGreen = bytes(position + colorTableIndex * 3 + 1)
            Dim As UByte globalPaletteBlue = bytes(position + colorTableIndex * 3 + 2)
            globalPalette(colorTableIndex) = RGB( _
                globalPaletteRed, globalPaletteGreen, globalPaletteBlue _
            )
        Next colorTableIndex
        position += paletteByteCount
    End If

    While position < byteCount
        Select Case bytes(position)
        Case &h3B
            Exit While
        Case &h21
            position += 1
            If position >= byteCount Then
                errorMessage = "GIF extension label is truncated"
                Return 0
            End If
            extensionLabel = bytes(position)
            position += 1

            If extensionLabel = &hF9 Then
                If position >= byteCount Then
                    errorMessage = "GIF graphics-control extension is truncated"
                    Return 0
                End If
                blockCount = bytes(position)
                position += 1
                If blockCount <> 4 OrElse position > byteCount OrElse _
                   blockCount > byteCount - position Then
                    errorMessage = "GIF graphics-control extension is malformed"
                    Return 0
                End If
                If bytes(position) And 1 Then
                    transparentIndex = bytes(position + 3)
                Else
                    transparentIndex = -1
                End If
                position += blockCount
                If position >= byteCount OrElse bytes(position) <> 0 Then
                    errorMessage = "GIF graphics-control terminator is missing"
                    Return 0
                End If
                position += 1
            Else
                Do
                    If position >= byteCount Then
                        errorMessage = "GIF extension sub-block list is truncated"
                        Return 0
                    End If
                    blockCount = bytes(position)
                    position += 1
                    If blockCount = 0 Then Exit Do
                    If position > byteCount OrElse blockCount > byteCount - position Then
                        errorMessage = "GIF extension sub-block extends beyond the file"
                        Return 0
                    End If
                    position += blockCount
                Loop
            End If
        Case &h2C
            position += 1
            If position > byteCount OrElse byteCount - position < 9 Then
                errorMessage = "GIF image descriptor is truncated"
                Return 0
            End If
            If Not rasterimage_ReadU16LE( _
                bytes(), byteCount, position, imageLeftValue _
            ) OrElse Not rasterimage_ReadU16LE( _
                bytes(), byteCount, position + 2, imageTopValue _
            ) OrElse Not rasterimage_ReadU16LE( _
                bytes(), byteCount, position + 4, imageWidthValue _
            ) OrElse Not rasterimage_ReadU16LE( _
                bytes(), byteCount, position + 6, imageHeightValue _
            ) Then
                errorMessage = "GIF image rectangle is truncated"
                Return 0
            End If

            imageLeft = imageLeftValue
            imageTop = imageTopValue
            imageWidth = imageWidthValue
            imageHeight = imageHeightValue
            packedFields = bytes(position + 8)
            interlaced = IIf(packedFields And &h40, -1, 0)
            position += 9

            If Not rasterimage_ValidateDimensions( _
                imageWidth, imageHeight, errorMessage _
            ) Then Return 0
            If imageLeft > logicalWidth OrElse imageTop > logicalHeight OrElse _
               imageWidth > logicalWidth - imageLeft OrElse _
               imageHeight > logicalHeight - imageTop Then
                errorMessage = "GIF image rectangle lies outside its logical screen"
                Return 0
            End If

            activePaletteCount = globalPaletteCount
            For colorTableIndex = 0 To globalPaletteCount - 1
                activePalette(colorTableIndex) = globalPalette(colorTableIndex)
            Next colorTableIndex

            If packedFields And &h80 Then
                localPaletteCount = 1 Shl ((packedFields And 7) + 1)
                paletteByteCount = localPaletteCount * 3
                If position > byteCount OrElse _
                   paletteByteCount > byteCount - position Then
                    errorMessage = "GIF local color table is truncated"
                    Return 0
                End If
                activePaletteCount = localPaletteCount
                For colorTableIndex = 0 To localPaletteCount - 1
                    Dim As UByte activePaletteRed = bytes(position + colorTableIndex * 3)
                    Dim As UByte activePaletteGreen = bytes(position + colorTableIndex * 3 + 1)
                    Dim As UByte activePaletteBlue = bytes(position + colorTableIndex * 3 + 2)
                    activePalette(colorTableIndex) = RGB( _
                        activePaletteRed, activePaletteGreen, activePaletteBlue _
                    )
                Next colorTableIndex
                position += paletteByteCount
            End If
            If activePaletteCount = 0 Then
                errorMessage = "GIF image has no color table"
                Return 0
            End If
            If position >= byteCount Then
                errorMessage = "GIF LZW code size is missing"
                Return 0
            End If

            lzwMinimumCodeSize = bytes(position)
            position += 1
            If Not rastergif_CollectSubBlocks( _
                bytes(), byteCount, position, compressedBytes(), _
                compressedCount, errorMessage _
            ) Then Return 0
            If Not rastergif_DecodeLzw( _
                compressedBytes(), compressedCount, lzwMinimumCodeSize, _
                imageWidth * imageHeight, decodedIndices(), errorMessage _
            ) Then Return 0

            foundImage = -1
            Exit While
        Case Else
            errorMessage = "GIF contains an unknown top-level block"
            Return 0
        End Select
    Wend

    If Not foundImage Then
        errorMessage = "GIF contains no image frame"
        Return 0
    End If

    backgroundColor = RGBA(0, 0, 0, 0)
    If transparentIndex < 0 AndAlso backgroundIndex < globalPaletteCount Then
        backgroundColor = &hFF000000UL Or globalPalette(backgroundIndex)
    End If
    imagePixels = backend_CreateImage( _
        logicalWidth, logicalHeight, backgroundColor, 32 _
    )
    If imagePixels = 0 Then
        errorMessage = "unable to allocate the GIF pixel buffer"
        Return 0
    End If
    If ImageInfo( _
        imagePixels, bufferWidth, bufferHeight, bytesPerPixel, pitch, _
        pixelData, imageBufferSize _
    ) <> 0 OrElse bytesPerPixel <> 4 OrElse pixelData = 0 Then
        ImageDestroy imagePixels
        errorMessage = "gfxlib returned an invalid GIF pixel buffer"
        Return 0
    End If

    sourceIndex = 0
    If interlaced Then
        For passIndex = 0 To 3
            destinationRow = passStart(passIndex)
            While destinationRow < imageHeight
                For x = 0 To imageWidth - 1
                    colorIndex = decodedIndices(sourceIndex)
                    sourceIndex += 1
                    If colorIndex = transparentIndex Then
                        outputColor = RGBA(0, 0, 0, 0)
                    ElseIf colorIndex < activePaletteCount Then
                        outputColor = &hFF000000UL Or activePalette(colorIndex)
                    Else
                        ImageDestroy imagePixels
                        errorMessage = "GIF pixel references a missing palette entry"
                        Return 0
                    End If
                    Cast(ULong Ptr, _
                        Cast(UByte Ptr, pixelData) + _
                        (imageTop + destinationRow) * pitch _
                    )[imageLeft + x] = outputColor
                Next x
                destinationRow += passStep(passIndex)
            Wend
        Next passIndex
    Else
        For y = 0 To imageHeight - 1
            For x = 0 To imageWidth - 1
                colorIndex = decodedIndices(sourceIndex)
                sourceIndex += 1
                If colorIndex = transparentIndex Then
                    outputColor = RGBA(0, 0, 0, 0)
                ElseIf colorIndex < activePaletteCount Then
                    outputColor = &hFF000000UL Or activePalette(colorIndex)
                Else
                    ImageDestroy imagePixels
                    errorMessage = "GIF pixel references a missing palette entry"
                    Return 0
                End If
                Cast(ULong Ptr, _
                    Cast(UByte Ptr, pixelData) + (imageTop + y) * pitch _
                )[imageLeft + x] = outputColor
            Next x
        Next y
    End If

    Return rasterimage_NewRecord( _
        imagePixels, logicalWidth, logicalHeight, RASTERIMAGE_FORMAT_GIF, _
        IIf(transparentIndex >= 0, -1, 0), loadedImage, errorMessage _
    )
End Function


' -------------------------------------------------------------------------
' Baseline JPEG decoder
' -------------------------------------------------------------------------

Type RasterJpegHuffmanTable
    As Integer present
    As Integer symbolCount
    As UByte counts(1 To 16)
    As UByte symbols(0 To 255)
End Type

Type RasterJpegComponent
    As Integer identifier
    As Integer horizontalSampling
    As Integer verticalSampling
    As Integer quantizationTable
    As Integer dcTable
    As Integer acTable
    As Long planeWidth
    As Long planeHeight
    As UByte Ptr samples
End Type

Type RasterJpegBitReader
    As UByte Ptr bytes
    As LongInt byteCount
    As LongInt position
    As ULong bitBuffer
    As Integer bitCount
    As Integer marker
End Type


Private Sub rasterjpeg_FreeComponents( _
    components() As RasterJpegComponent _
)
    For componentIndex As Integer = 0 To RASTERIMAGE_JPEG_MAX_COMPONENTS - 1
        If components(componentIndex).samples <> 0 Then
            Deallocate components(componentIndex).samples
            components(componentIndex).samples = 0
        End If
    Next componentIndex
End Sub


Private Function rasterjpeg_FailDecode( _
    components() As RasterJpegComponent, _
    ByVal imagePixels As Any Ptr _
) As Integer
    rasterjpeg_FreeComponents components()
    If imagePixels <> 0 Then ImageDestroy imagePixels
    Return 0
End Function


Private Function rasterjpeg_EntropyByte( _
    ByRef reader As RasterJpegBitReader _
) As Integer
    Dim As Integer value
    Dim As Integer markerValue

    If reader.position >= reader.byteCount Then Return -1
    value = reader.bytes[reader.position]
    reader.position += 1
    If value <> &hFF Then Return value

    Do While reader.position < reader.byteCount AndAlso _
        reader.bytes[reader.position] = &hFF
        reader.position += 1
    Loop
    If reader.position >= reader.byteCount Then Return -1

    markerValue = reader.bytes[reader.position]
    reader.position += 1
    If markerValue = 0 Then Return &hFF
    reader.marker = markerValue
    Return -1
End Function


Private Function rasterjpeg_ReadBits( _
    ByRef reader As RasterJpegBitReader, ByVal bitCount As Integer, _
    ByRef value As Integer _
) As Integer
    Dim As Integer nextByte

    If bitCount < 0 OrElse bitCount > 16 Then Return 0
    If bitCount = 0 Then
        value = 0
        Return -1
    End If

    While reader.bitCount < bitCount
        nextByte = rasterjpeg_EntropyByte(reader)
        If nextByte < 0 Then Return 0
        reader.bitBuffer = (reader.bitBuffer Shl 8) Or nextByte
        reader.bitCount += 8
    Wend

    value = (reader.bitBuffer Shr (reader.bitCount - bitCount)) And _
        ((1 Shl bitCount) - 1)
    reader.bitCount -= bitCount
    If reader.bitCount = 0 Then
        reader.bitBuffer = 0
    Else
        reader.bitBuffer And= (1 Shl reader.bitCount) - 1
    End If
    Return -1
End Function


Private Function rasterjpeg_DecodeHuffman( _
    ByRef reader As RasterJpegBitReader, _
    ByRef huffmanTable As RasterJpegHuffmanTable, _
    ByRef symbolValue As Integer _
) As Integer
    Dim As Integer code
    Dim As Integer firstCode
    Dim As Integer firstSymbol
    Dim As Integer length
    Dim As Integer bitValue
    Dim As Integer countAtLength
    Dim As Integer symbolIndex

    If huffmanTable.present = 0 Then Return 0
    For length = 1 To 16
        If Not rasterjpeg_ReadBits(reader, 1, bitValue) Then Return 0
        code = (code Shl 1) Or bitValue
        countAtLength = huffmanTable.counts(length)
        If code >= firstCode AndAlso code < firstCode + countAtLength Then
            symbolIndex = firstSymbol + code - firstCode
            If symbolIndex < 0 OrElse _
               symbolIndex >= huffmanTable.symbolCount Then Return 0
            symbolValue = huffmanTable.symbols(symbolIndex)
            Return -1
        End If
        firstSymbol += countAtLength
        firstCode = (firstCode + countAtLength) Shl 1
    Next length
    Return 0
End Function


Private Function rasterjpeg_ReceiveExtended( _
    ByRef reader As RasterJpegBitReader, ByVal bitCount As Integer, _
    ByRef signedValue As Integer _
) As Integer
    Dim As Integer rawValue
    Dim As Integer threshold

    If bitCount = 0 Then
        signedValue = 0
        Return -1
    End If
    If bitCount < 0 OrElse bitCount > 16 Then Return 0
    If Not rasterjpeg_ReadBits(reader, bitCount, rawValue) Then Return 0

    threshold = 1 Shl (bitCount - 1)
    If rawValue < threshold Then rawValue -= (1 Shl bitCount) - 1
    signedValue = rawValue
    Return -1
End Function


Private Function rasterjpeg_DecodeBlock( _
    ByRef reader As RasterJpegBitReader, _
    ByRef dcTable As RasterJpegHuffmanTable, _
    ByRef acTable As RasterJpegHuffmanTable, _
    quantizationValues() As UShort, _
    ByVal quantizationTable As Integer, _
    ByRef previousDc As Long, _
    coefficients() As Long, _
    ByRef errorMessage As String _
) As Integer
    Static As Integer zigZag(0 To 63) = { _
         0,  1,  8, 16,  9,  2,  3, 10, _
        17, 24, 32, 25, 18, 11,  4,  5, _
        12, 19, 26, 33, 40, 48, 41, 34, _
        27, 20, 13,  6,  7, 14, 21, 28, _
        35, 42, 49, 56, 57, 50, 43, 36, _
        29, 22, 15, 23, 30, 37, 44, 51, _
        58, 59, 52, 45, 38, 31, 39, 46, _
        53, 60, 61, 54, 47, 55, 62, 63 _
    }
    Dim As Integer symbolValue
    Dim As Integer decodedValue
    Dim As Integer runLength
    Dim As Integer valueBits
    Dim As Integer coefficientIndex
    Dim As Integer naturalIndex

    For naturalIndex = 0 To 63
        coefficients(naturalIndex) = 0
    Next naturalIndex

    If Not rasterjpeg_DecodeHuffman( _
        reader, dcTable, symbolValue _
    ) OrElse symbolValue > 16 Then
        errorMessage = "JPEG DC Huffman code is invalid"
        Return 0
    End If
    If Not rasterjpeg_ReceiveExtended( _
        reader, symbolValue, decodedValue _
    ) Then
        errorMessage = "JPEG DC coefficient is truncated"
        Return 0
    End If

    previousDc += decodedValue
    coefficients(0) = previousDc * _
        quantizationValues(quantizationTable * 64)
    coefficientIndex = 1

    While coefficientIndex < 64
        If Not rasterjpeg_DecodeHuffman( _
            reader, acTable, symbolValue _
        ) Then
            errorMessage = "JPEG AC Huffman code is invalid"
            Return 0
        End If
        If symbolValue = 0 Then Exit While
        If symbolValue = &hF0 Then
            coefficientIndex += 16
            Continue While
        End If

        runLength = symbolValue Shr 4
        valueBits = symbolValue And &h0F
        If valueBits = 0 Then
            errorMessage = "JPEG AC run has no coefficient bits"
            Return 0
        End If
        coefficientIndex += runLength
        If coefficientIndex >= 64 Then
            errorMessage = "JPEG AC run extends beyond one block"
            Return 0
        End If
        If Not rasterjpeg_ReceiveExtended( _
            reader, valueBits, decodedValue _
        ) Then
            errorMessage = "JPEG AC coefficient is truncated"
            Return 0
        End If
        naturalIndex = zigZag(coefficientIndex)
        coefficients(naturalIndex) = decodedValue * _
            quantizationValues(quantizationTable * 64 + coefficientIndex)
        coefficientIndex += 1
    Wend
    Return -1
End Function


Private Sub rasterjpeg_InverseDct( _
    coefficients() As Long, outputPixels() As UByte _
)
    Const JPEG_IDCT_ONE_OVER_ROOT_TWO As Double = _
        0.7071067811865475244
    Dim As Double temporary(0 To 63)
    Dim As Double accumulator
    Dim As Double coefficientScale
    Dim As Double piValue
    Dim As Long outputValue
    Dim As Integer x
    Dim As Integer y
    Dim As Integer u
    Dim As Integer v
    Dim As Integer nonzeroAc

    For u = 1 To 63
        If coefficients(u) <> 0 Then
            nonzeroAc = -1
            Exit For
        End If
    Next u
    If nonzeroAc = 0 Then
        outputValue = coefficients(0) \ 8 + 128
        If outputValue < 0 Then outputValue = 0
        If outputValue > 255 Then outputValue = 255
        For u = 0 To 63
            outputPixels(u) = outputValue
        Next u
        Exit Sub
    End If

    piValue = Atn(1.0) * 4.0
    For v = 0 To 7
        For x = 0 To 7
            accumulator = 0.0
            For u = 0 To 7
                coefficientScale = IIf( _
                    u = 0, JPEG_IDCT_ONE_OVER_ROOT_TWO, 1.0 _
                )
                accumulator += coefficientScale * _
                    coefficients(v * 8 + u) * _
                    Cos((2 * x + 1) * u * piValue / 16.0)
            Next u
            temporary(v * 8 + x) = accumulator
        Next x
    Next v

    For y = 0 To 7
        For x = 0 To 7
            accumulator = 0.0
            For v = 0 To 7
                coefficientScale = IIf( _
                    v = 0, JPEG_IDCT_ONE_OVER_ROOT_TWO, 1.0 _
                )
                accumulator += coefficientScale * temporary(v * 8 + x) * _
                    Cos((2 * y + 1) * v * piValue / 16.0)
            Next v
            outputValue = CLng(accumulator / 4.0 + 128.5)
            If outputValue < 0 Then outputValue = 0
            If outputValue > 255 Then outputValue = 255
            outputPixels(y * 8 + x) = outputValue
        Next x
    Next y
End Sub


Private Function rasterjpeg_ConsumeRestart( _
    ByRef reader As RasterJpegBitReader, ByVal expectedMarker As Integer _
) As Integer
    Dim As Integer markerValue

    reader.bitBuffer = 0
    reader.bitCount = 0
    If reader.marker <> 0 Then
        markerValue = reader.marker
        reader.marker = 0
        Return IIf(markerValue = expectedMarker, -1, 0)
    End If

    If reader.position >= reader.byteCount OrElse _
       reader.bytes[reader.position] <> &hFF Then Return 0
    Do While reader.position < reader.byteCount AndAlso _
        reader.bytes[reader.position] = &hFF
        reader.position += 1
    Loop
    If reader.position >= reader.byteCount Then Return 0
    markerValue = reader.bytes[reader.position]
    reader.position += 1
    Return IIf(markerValue = expectedMarker, -1, 0)
End Function


' fblint: disable-next-line FBL110,FBL111 -- JPEG marker, scan and output state stay together in this decoder pass.
Private Function rasterjpeg_Decode( _
    bytes() As UByte, ByVal byteCount As LongInt, _
    ByRef loadedImage As RasterImage Ptr, _
    ByRef errorMessage As String _
) As Integer
    Dim As RasterJpegComponent components( _
        0 To RASTERIMAGE_JPEG_MAX_COMPONENTS - 1 _
    )
    Dim As RasterJpegHuffmanTable huffmanTables( _
        0 To 1, 0 To RASTERIMAGE_JPEG_MAX_TABLES - 1 _
    )
    Dim As UShort quantizationValues( _
        0 To RASTERIMAGE_JPEG_MAX_TABLES * 64 - 1 _
    )
    Dim As Integer quantizationPresent( _
        0 To RASTERIMAGE_JPEG_MAX_TABLES - 1 _
    )
    Dim As Integer scanComponentIndex( _
        0 To RASTERIMAGE_JPEG_MAX_COMPONENTS - 1 _
    )
    Dim As Long dcPredictor(0 To RASTERIMAGE_JPEG_MAX_COMPONENTS - 1)
    Dim As Long coefficients(0 To 63)
    Dim As UByte blockPixels(0 To 63)
    Dim As RasterJpegBitReader reader
    Dim As LongInt position
    Dim As LongInt segmentStart
    Dim As LongInt segmentEnd
    Dim As LongInt segmentPosition
    Dim As ULong segmentLengthValue
    Dim As ULong imageWidthValue
    Dim As ULong imageHeightValue
    Dim As Long imageWidth
    Dim As Long imageHeight
    Dim As Integer markerValue
    Dim As Integer tableInfo
    Dim As Integer tableClass
    Dim As Integer tableIndex
    Dim As Integer precision
    Dim As Integer componentCount
    Dim As Integer scanComponentCount
    Dim As Integer componentIndex
    Dim As Integer scanIndex
    Dim As Integer symbolCount
    Dim As Integer symbolIndex
    Dim As Integer maxHorizontalSampling
    Dim As Integer maxVerticalSampling
    Dim As Integer restartInterval
    Dim As Integer restartIndex
    Dim As Long mcuWidth
    Dim As Long mcuHeight
    Dim As Long mcuColumns
    Dim As Long mcuRows
    Dim As Long mcuX
    Dim As Long mcuY
    Dim As Long mcuNumber
    Dim As Long totalMcus
    Dim As Integer blockX
    Dim As Integer blockY
    Dim As Long destinationX
    Dim As Long destinationY
    Dim As Long sampleCount
    Dim As UByte Ptr componentSamples
    Dim As Any Ptr imagePixels = 0
    Dim As Any Ptr pixelData = 0
    Dim As Long bufferWidth
    Dim As Long bufferHeight
    Dim As Long bytesPerPixel
    Dim As Long pitch
    Dim As Long imageBufferSize
    Dim As Long x
    Dim As Long y
    Dim As Long sampleX
    Dim As Long sampleY
    Dim As Integer luminance
    Dim As Integer blueDifference
    Dim As Integer redDifference
    Dim As Long redValue
    Dim As Long greenValue
    Dim As Long blueValue
    Dim As Integer frameFound
    Dim As Integer scanFound

    For componentIndex = 0 To RASTERIMAGE_JPEG_MAX_COMPONENTS - 1
        components(componentIndex).samples = 0
    Next componentIndex

    If byteCount < 4 OrElse bytes(0) <> &hFF OrElse bytes(1) <> &hD8 Then
        errorMessage = "JPEG start-of-image marker is missing"
        Return 0
    End If

    position = 2
    While position < byteCount AndAlso scanFound = 0
        Do While position < byteCount AndAlso bytes(position) <> &hFF
            position += 1
        Loop
        If position >= byteCount Then Exit While
        Do While position < byteCount AndAlso bytes(position) = &hFF
            position += 1
        Loop
        If position >= byteCount Then Exit While
        markerValue = bytes(position)
        position += 1

        If markerValue = &hD8 OrElse markerValue = &h01 OrElse _
           (markerValue >= &hD0 AndAlso markerValue <= &hD7) Then
            Continue While
        End If
        If markerValue = &hD9 Then Exit While
        If position > byteCount OrElse byteCount - position < 2 OrElse _
           Not rasterimage_ReadU16BE( _
               bytes(), byteCount, position, segmentLengthValue _
           ) Then
            errorMessage = "JPEG marker length is truncated"
            Return rasterjpeg_FailDecode(components(), imagePixels)
        End If
        If segmentLengthValue < 2 OrElse _
           segmentLengthValue > byteCount - position Then
            errorMessage = "JPEG marker segment extends beyond the file"
            Return rasterjpeg_FailDecode(components(), imagePixels)
        End If

        segmentStart = position + 2
        segmentEnd = position + segmentLengthValue
        Select Case markerValue
        Case &hDB
            segmentPosition = segmentStart
            While segmentPosition < segmentEnd
                tableInfo = bytes(segmentPosition)
                segmentPosition += 1
                precision = tableInfo Shr 4
                tableIndex = tableInfo And &h0F
                If tableIndex >= RASTERIMAGE_JPEG_MAX_TABLES OrElse _
                   precision > 1 Then
                    errorMessage = "JPEG quantization table is unsupported"
                    Return rasterjpeg_FailDecode(components(), imagePixels)
                End If
                If precision = 0 Then
                    If segmentEnd - segmentPosition < 64 Then
                        errorMessage = "JPEG quantization table is truncated"
                        Return rasterjpeg_FailDecode(components(), imagePixels)
                    End If
                    For symbolIndex = 0 To 63
                        quantizationValues(tableIndex * 64 + symbolIndex) = _
                            bytes(segmentPosition)
                        segmentPosition += 1
                    Next symbolIndex
                Else
                    If segmentEnd - segmentPosition < 128 Then
                        errorMessage = "JPEG 16-bit quantization table is truncated"
                        Return rasterjpeg_FailDecode(components(), imagePixels)
                    End If
                    For symbolIndex = 0 To 63
                        If Not rasterimage_ReadU16BE( _
                            bytes(), byteCount, segmentPosition, _
                            segmentLengthValue _
                        ) Then
                            errorMessage = "JPEG quantization value is truncated"
                            Return rasterjpeg_FailDecode(components(), imagePixels)
                        End If
                        quantizationValues(tableIndex * 64 + symbolIndex) = _
                            segmentLengthValue
                        segmentPosition += 2
                    Next symbolIndex
                End If
                quantizationPresent(tableIndex) = -1
            Wend
        Case &hC4
            segmentPosition = segmentStart
            While segmentPosition < segmentEnd
                tableInfo = bytes(segmentPosition)
                segmentPosition += 1
                tableClass = tableInfo Shr 4
                tableIndex = tableInfo And &h0F
                If tableClass > 1 OrElse _
                   tableIndex >= RASTERIMAGE_JPEG_MAX_TABLES OrElse _
                   segmentEnd - segmentPosition < 16 Then
                    errorMessage = "JPEG Huffman table header is invalid"
                    Return rasterjpeg_FailDecode(components(), imagePixels)
                End If

                symbolCount = 0
                For symbolIndex = 1 To 16
                    huffmanTables(tableClass, tableIndex).counts(symbolIndex) = _
                        bytes(segmentPosition)
                    symbolCount += bytes(segmentPosition)
                    segmentPosition += 1
                Next symbolIndex
                If symbolCount > 256 OrElse _
                   segmentEnd - segmentPosition < symbolCount Then
                    errorMessage = "JPEG Huffman symbol table is truncated"
                    Return rasterjpeg_FailDecode(components(), imagePixels)
                End If
                For symbolIndex = 0 To symbolCount - 1
                    huffmanTables(tableClass, tableIndex).symbols(symbolIndex) = _
                        bytes(segmentPosition)
                    segmentPosition += 1
                Next symbolIndex
                huffmanTables(tableClass, tableIndex).symbolCount = symbolCount
                huffmanTables(tableClass, tableIndex).present = -1
            Wend
        Case &hC0
            If segmentEnd - segmentStart < 6 Then
                errorMessage = "JPEG baseline frame header is truncated"
                Return rasterjpeg_FailDecode(components(), imagePixels)
            End If
            precision = bytes(segmentStart)
            If precision <> 8 Then
                errorMessage = "JPEG sample precision is not 8 bits"
                Return rasterjpeg_FailDecode(components(), imagePixels)
            End If
            If Not rasterimage_ReadU16BE( _
                bytes(), byteCount, segmentStart + 1, imageHeightValue _
            ) OrElse Not rasterimage_ReadU16BE( _
                bytes(), byteCount, segmentStart + 3, imageWidthValue _
            ) Then
                errorMessage = "JPEG frame dimensions are truncated"
                Return rasterjpeg_FailDecode(components(), imagePixels)
            End If
            imageWidth = imageWidthValue
            imageHeight = imageHeightValue
            If Not rasterimage_ValidateDimensions( _
                imageWidth, imageHeight, errorMessage _
            ) Then Return rasterjpeg_FailDecode(components(), imagePixels)

            componentCount = bytes(segmentStart + 5)
            If componentCount <> 1 AndAlso componentCount <> 3 Then
                errorMessage = "JPEG must contain one grayscale or three YCbCr components"
                Return rasterjpeg_FailDecode(components(), imagePixels)
            End If
            If segmentEnd - (segmentStart + 6) <> componentCount * 3 Then
                errorMessage = "JPEG frame component list has the wrong size"
                Return rasterjpeg_FailDecode(components(), imagePixels)
            End If

            segmentPosition = segmentStart + 6
            For componentIndex = 0 To componentCount - 1
                components(componentIndex).identifier = bytes(segmentPosition)
                tableInfo = bytes(segmentPosition + 1)
                components(componentIndex).horizontalSampling = tableInfo Shr 4
                components(componentIndex).verticalSampling = tableInfo And &h0F
                components(componentIndex).quantizationTable = _
                    bytes(segmentPosition + 2)
                If components(componentIndex).horizontalSampling < 1 OrElse _
                   components(componentIndex).horizontalSampling > 4 OrElse _
                   components(componentIndex).verticalSampling < 1 OrElse _
                   components(componentIndex).verticalSampling > 4 OrElse _
                   components(componentIndex).quantizationTable >= _
                       RASTERIMAGE_JPEG_MAX_TABLES Then
                    errorMessage = "JPEG component sampling or table selector is invalid"
                    Return rasterjpeg_FailDecode(components(), imagePixels)
                End If
                If components(componentIndex).horizontalSampling > _
                   maxHorizontalSampling Then
                    maxHorizontalSampling = _
                        components(componentIndex).horizontalSampling
                End If
                If components(componentIndex).verticalSampling > _
                   maxVerticalSampling Then
                    maxVerticalSampling = components(componentIndex).verticalSampling
                End If
                segmentPosition += 3
            Next componentIndex
            frameFound = -1
        Case &hC1 To &hC3, &hC5 To &hC7, &hC9 To &hCB, &hCD To &hCF
            errorMessage = "JPEG is not baseline sequential SOF0"
            Return rasterjpeg_FailDecode(components(), imagePixels)
        Case &hDD
            If segmentEnd - segmentStart <> 2 OrElse _
               Not rasterimage_ReadU16BE( _
                   bytes(), byteCount, segmentStart, segmentLengthValue _
               ) Then
                errorMessage = "JPEG restart interval is malformed"
                Return rasterjpeg_FailDecode(components(), imagePixels)
            End If
            restartInterval = segmentLengthValue
        Case &hDA
            If frameFound = 0 OrElse segmentEnd - segmentStart < 4 Then
                errorMessage = "JPEG scan appears before a valid frame"
                Return rasterjpeg_FailDecode(components(), imagePixels)
            End If
            scanComponentCount = bytes(segmentStart)
            If scanComponentCount <> componentCount Then
                errorMessage = "JPEG uses unsupported separate component scans"
                Return rasterjpeg_FailDecode(components(), imagePixels)
            End If
            If segmentEnd - (segmentStart + 1) <> _
               scanComponentCount * 2 + 3 Then
                errorMessage = "JPEG scan component list has the wrong size"
                Return rasterjpeg_FailDecode(components(), imagePixels)
            End If

            segmentPosition = segmentStart + 1
            For scanIndex = 0 To scanComponentCount - 1
                scanComponentIndex(scanIndex) = -1
                For componentIndex = 0 To componentCount - 1
                    If components(componentIndex).identifier = _
                       bytes(segmentPosition) Then
                        scanComponentIndex(scanIndex) = componentIndex
                        Exit For
                    End If
                Next componentIndex
                If scanComponentIndex(scanIndex) < 0 Then
                    errorMessage = "JPEG scan references an unknown component"
                    Return rasterjpeg_FailDecode(components(), imagePixels)
                End If
                tableInfo = bytes(segmentPosition + 1)
                components(scanComponentIndex(scanIndex)).dcTable = tableInfo Shr 4
                components(scanComponentIndex(scanIndex)).acTable = tableInfo And &h0F
                If components(scanComponentIndex(scanIndex)).dcTable >= _
                   RASTERIMAGE_JPEG_MAX_TABLES OrElse _
                   components(scanComponentIndex(scanIndex)).acTable >= _
                   RASTERIMAGE_JPEG_MAX_TABLES Then
                    errorMessage = "JPEG scan Huffman selector is invalid"
                    Return rasterjpeg_FailDecode(components(), imagePixels)
                End If
                segmentPosition += 2
            Next scanIndex
            If bytes(segmentPosition) <> 0 OrElse _
               bytes(segmentPosition + 1) <> 63 OrElse _
               bytes(segmentPosition + 2) <> 0 Then
                errorMessage = "JPEG scan parameters are not baseline sequential"
                Return rasterjpeg_FailDecode(components(), imagePixels)
            End If
            reader.bytes = @bytes(0)
            reader.byteCount = byteCount
            reader.position = segmentEnd
            scanFound = -1
        End Select
        position = segmentEnd
    Wend

    If frameFound = 0 OrElse scanFound = 0 Then
        errorMessage = "JPEG has no complete baseline frame and scan"
        Return rasterjpeg_FailDecode(components(), imagePixels)
    End If
    For componentIndex = 0 To componentCount - 1
        tableIndex = components(componentIndex).quantizationTable
        If quantizationPresent(tableIndex) = 0 Then
            errorMessage = "JPEG component references a missing quantization table"
            Return rasterjpeg_FailDecode(components(), imagePixels)
        End If
        If huffmanTables(0, components(componentIndex).dcTable).present = 0 OrElse _
           huffmanTables(1, components(componentIndex).acTable).present = 0 Then
            errorMessage = "JPEG component references a missing Huffman table"
            Return rasterjpeg_FailDecode(components(), imagePixels)
        End If
    Next componentIndex

    mcuWidth = maxHorizontalSampling * 8
    mcuHeight = maxVerticalSampling * 8
    mcuColumns = (imageWidth + mcuWidth - 1) \ mcuWidth
    mcuRows = (imageHeight + mcuHeight - 1) \ mcuHeight
    totalMcus = mcuColumns * mcuRows

    For componentIndex = 0 To componentCount - 1
        components(componentIndex).planeWidth = _
            mcuColumns * components(componentIndex).horizontalSampling * 8
        components(componentIndex).planeHeight = _
            mcuRows * components(componentIndex).verticalSampling * 8
        sampleCount = components(componentIndex).planeWidth * _
            components(componentIndex).planeHeight
        If sampleCount < 1 OrElse sampleCount > RASTERIMAGE_MAX_PIXELS Then
            errorMessage = "JPEG component plane exceeds the pixel safety limit"
            Return rasterjpeg_FailDecode(components(), imagePixels)
        End If
        componentSamples = Callocate(sampleCount)
        If componentSamples = 0 Then
            errorMessage = "unable to allocate a JPEG component plane"
            Return rasterjpeg_FailDecode(components(), imagePixels)
        End If
        components(componentIndex).samples = componentSamples
    Next componentIndex

    For mcuY = 0 To mcuRows - 1
        For mcuX = 0 To mcuColumns - 1
            For scanIndex = 0 To scanComponentCount - 1
                componentIndex = scanComponentIndex(scanIndex)
                For blockY = 0 To _
                    components(componentIndex).verticalSampling - 1
                    For blockX = 0 To _
                        components(componentIndex).horizontalSampling - 1
                        If Not rasterjpeg_DecodeBlock( _
                            reader, _
                            huffmanTables( _
                                0, components(componentIndex).dcTable _
                            ), _
                            huffmanTables( _
                                1, components(componentIndex).acTable _
                            ), _
                            quantizationValues(), _
                            components(componentIndex).quantizationTable, _
                            dcPredictor(componentIndex), coefficients(), _
                            errorMessage _
                        ) Then Return rasterjpeg_FailDecode(components(), imagePixels)
                        rasterjpeg_InverseDct coefficients(), blockPixels()

                        destinationX = ( _
                            mcuX * components(componentIndex).horizontalSampling + _
                            blockX _
                        ) * 8
                        destinationY = ( _
                            mcuY * components(componentIndex).verticalSampling + _
                            blockY _
                        ) * 8
                        For y = 0 To 7
                            For x = 0 To 7
                                components(componentIndex).samples[( _
                                    destinationY + y _
                                ) * components(componentIndex).planeWidth + _
                                    destinationX + x] = blockPixels(y * 8 + x)
                            Next x
                        Next y
                    Next blockX
                Next blockY
            Next scanIndex

            mcuNumber += 1
            If restartInterval > 0 AndAlso _
               (mcuNumber Mod restartInterval) = 0 AndAlso _
               mcuNumber < totalMcus Then
                If Not rasterjpeg_ConsumeRestart( _
                    reader, &hD0 + (restartIndex And 7) _
                ) Then
                    errorMessage = "JPEG restart marker is missing or out of order"
                    Return rasterjpeg_FailDecode(components(), imagePixels)
                End If
                restartIndex += 1
                For componentIndex = 0 To componentCount - 1
                    dcPredictor(componentIndex) = 0
                Next componentIndex
            End If
        Next mcuX
    Next mcuY

    imagePixels = backend_CreateImage( _
        imageWidth, imageHeight, RGB(0, 0, 0), 32 _
    )
    If imagePixels = 0 Then
        errorMessage = "unable to allocate the JPEG pixel buffer"
        Return rasterjpeg_FailDecode(components(), imagePixels)
    End If
    If ImageInfo( _
        imagePixels, bufferWidth, bufferHeight, bytesPerPixel, pitch, _
        pixelData, imageBufferSize _
    ) <> 0 OrElse bytesPerPixel <> 4 OrElse pixelData = 0 Then
        errorMessage = "gfxlib returned an invalid JPEG pixel buffer"
        Return rasterjpeg_FailDecode(components(), imagePixels)
    End If

    For y = 0 To imageHeight - 1
        For x = 0 To imageWidth - 1
            sampleX = x * components(0).horizontalSampling \ _
                maxHorizontalSampling
            sampleY = y * components(0).verticalSampling \ _
                maxVerticalSampling
            luminance = components(0).samples[ _
                sampleY * components(0).planeWidth + sampleX _
            ]

            If componentCount = 1 Then
                redValue = luminance
                greenValue = luminance
                blueValue = luminance
            Else
                sampleX = x * components(1).horizontalSampling \ _
                    maxHorizontalSampling
                sampleY = y * components(1).verticalSampling \ _
                    maxVerticalSampling
                blueDifference = components(1).samples[ _
                    sampleY * components(1).planeWidth + sampleX _
                ] - 128
                sampleX = x * components(2).horizontalSampling \ _
                    maxHorizontalSampling
                sampleY = y * components(2).verticalSampling \ _
                    maxVerticalSampling
                redDifference = components(2).samples[ _
                    sampleY * components(2).planeWidth + sampleX _
                ] - 128

                redValue = CLng(luminance + 1.402 * redDifference)
                greenValue = CLng( _
                    luminance - 0.344136 * blueDifference - _
                    0.714136 * redDifference _
                )
                blueValue = CLng(luminance + 1.772 * blueDifference)
                If redValue < 0 Then redValue = 0
                If redValue > 255 Then redValue = 255
                If greenValue < 0 Then greenValue = 0
                If greenValue > 255 Then greenValue = 255
                If blueValue < 0 Then blueValue = 0
                If blueValue > 255 Then blueValue = 255
            End If

            Cast(ULong Ptr, _
                Cast(UByte Ptr, pixelData) + y * pitch _
            )[x] = RGBA(redValue, greenValue, blueValue, 255)
        Next x
    Next y

    rasterjpeg_FreeComponents components()
    Return rasterimage_NewRecord( _
        imagePixels, imageWidth, imageHeight, RASTERIMAGE_FORMAT_JPEG, 0, _
        loadedImage, errorMessage _
    )

End Function


' -------------------------------------------------------------------------
' gfxlib BMP/PNG file loading
' -------------------------------------------------------------------------

Private Function rasterimage_LoadGfxFile( _
    ByVal filePath As String, bytes() As UByte, _
    ByVal byteCount As LongInt, ByVal formatKind As Integer, _
    ByRef loadedImage As RasterImage Ptr, _
    ByRef errorMessage As String _
) As Integer
    Dim As ULong widthValue
    Dim As ULong heightValue
    Dim As Long imageWidth
    Dim As Long imageHeight
    Dim As Long signedHeight
    Dim As Any Ptr imagePixels

    If formatKind = RASTERIMAGE_FORMAT_BMP Then
        If Not rasterimage_ReadU32LE( _
            bytes(), byteCount, 18, widthValue _
        ) OrElse Not rasterimage_ReadU32LE( _
            bytes(), byteCount, 22, heightValue _
        ) Then
            errorMessage = "BMP dimensions are truncated"
            Return 0
        End If
        imageWidth = CInt(widthValue)
        signedHeight = CInt(heightValue)
        If signedHeight = &h80000000 Then
            errorMessage = "BMP height cannot be represented safely"
            Return 0
        End If
        imageHeight = Abs(signedHeight)
    Else
        If byteCount < 24 OrElse _
           Not rasterimage_ReadU32BE( _
               bytes(), byteCount, 16, widthValue _
           ) OrElse Not rasterimage_ReadU32BE( _
               bytes(), byteCount, 20, heightValue _
           ) OrElse widthValue > &h7FFFFFFFUL OrElse _
           heightValue > &h7FFFFFFFUL Then
            errorMessage = "PNG dimensions are truncated or out of range"
            Return 0
        End If
        imageWidth = widthValue
        imageHeight = heightValue
    End If

    If Not rasterimage_ValidateDimensions( _
        imageWidth, imageHeight, errorMessage _
    ) Then Return 0

    /'
        BLoad requires an initialized graphics mode and a correctly sized
        destination image. omaGUI initializes gfxlib before widgets are
        created, so the raster loader follows the same lifecycle contract.
    '/
    imagePixels = backend_CreateImage( _
        imageWidth, imageHeight, RGBA(0, 0, 0, 0), 32 _
    )
    If imagePixels = 0 Then
        errorMessage = "unable to allocate the gfxlib image buffer"
        Return 0
    End If
    If backend_LoadImageFile(filePath, imagePixels) <> 0 Then
        ImageDestroy imagePixels
        errorMessage = "gfxlib could not decode the BMP or PNG file"
        Return 0
    End If

    Return rasterimage_NewRecord( _
        imagePixels, imageWidth, imageHeight, formatKind, _
        IIf(formatKind = RASTERIMAGE_FORMAT_PNG, -1, 0), _
        loadedImage, errorMessage _
    )
End Function


Private Function rasterimage_JoinPath( _
    ByVal directoryPath As String, ByVal fileName As String _
) As String
    Dim As String endingCharacter

    directoryPath = Trim(directoryPath)
    If Len(directoryPath) = 0 Then Return fileName
    endingCharacter = Right(directoryPath, 1)
    If endingCharacter = "/" OrElse endingCharacter = "\" Then
        Return directoryPath & fileName
    End If
    Return directoryPath & RASTERIMAGE_PATH_SEPARATOR & fileName
End Function


Private Function rasterimage_CreateScratchDirectory( _
    ByRef scratchDirectory As String, _
    ByRef errorMessage As String _
) As Integer
    Dim As String rootCandidates(0 To 3)
    Dim As String rootPath
    Dim As String directoryName
    Dim As Long rootIndex
    Dim As Long attemptIndex
    Dim As ULong timerPart

    scratchDirectory = ""
    rootCandidates(0) = Environ("TMPDIR")
    rootCandidates(1) = Environ("TEMP")
    rootCandidates(2) = Environ("TMP")
    rootCandidates(3) = CurDir
    timerPart = CULng(CLngInt(Timer * 1000.0) And &h7FFFFFFF)

    /'
        MkDir is the portable FreeBASIC operation that gives this loader an
        exclusive name. Two processes proposing the same directory name
        cannot both create it; the loser advances to the
        next suffix. No existing file or directory is ever reused or removed.
    '/
    For rootIndex = 0 To 3
        rootPath = Trim(rootCandidates(rootIndex))
        If Len(rootPath) = 0 OrElse Len(rootPath) > 768 Then Continue For
        For attemptIndex = 0 To 255
            directoryName = "omagui-raster-" & Hex(timerPart, 8) & "-" & _
                Hex(rootIndex, 2) & "-" & _
                Hex(attemptIndex, 2)
            scratchDirectory = rasterimage_JoinPath(rootPath, directoryName)
            If MkDir(scratchDirectory) = 0 Then Return -1
        Next attemptIndex
    Next rootIndex

    scratchDirectory = ""
    errorMessage = _
        "unable to create an exclusive scratch directory for gfxlib BLoad"
    Return 0
End Function


Private Function rasterimage_LoadGfxMemory( _
    bytes() As UByte, ByVal byteCount As LongInt, _
    ByVal formatKind As Integer, _
    ByRef loadedImage As RasterImage Ptr, _
    ByRef errorMessage As String _
) As Integer
    Dim As String scratchDirectory
    Dim As String scratchFile
    Dim As String extensionText
    Dim As Integer fileNumber
    Dim As Integer ioResult
    Dim As Integer loadResult
    Dim As Integer fileCreated
    Dim As Long removeFileResult
    Dim As Long removeDirectoryResult

    loadedImage = 0
    If Not rasterimage_CreateScratchDirectory( _
        scratchDirectory, errorMessage _
    ) Then Return 0

    extensionText = IIf(formatKind = RASTERIMAGE_FORMAT_PNG, ".png", ".bmp")
    scratchFile = rasterimage_JoinPath(scratchDirectory, "image" & extensionText)
    fileNumber = FreeFile
    ioResult = Open(scratchFile For Binary Access Write As #fileNumber)
    If ioResult = 0 Then
        fileCreated = -1
        ioResult = Put(#fileNumber, 1, bytes())
        Close #fileNumber
    End If

    If ioResult <> 0 Then
        If fileCreated Then removeFileResult = Kill(scratchFile)
        removeDirectoryResult = RmDir(scratchDirectory)
        errorMessage = "unable to write the transient gfxlib image file"
        Return 0
    End If

    loadResult = rasterimage_LoadGfxFile( _
        scratchFile, bytes(), byteCount, formatKind, _
        loadedImage, errorMessage _
    )

    /'
        The decoded gfxlib buffer is independent of the source file. Cleanup
        happens before this function returns, including every decoder-failure
        path, so DD image bytes are not left behind as a cache.
    '/
    removeFileResult = Kill(scratchFile)
    removeDirectoryResult = RmDir(scratchDirectory)
    If removeFileResult <> 0 OrElse removeDirectoryResult <> 0 Then
        If loadedImage <> 0 Then
            rasterimage_Destroy loadedImage
            loadedImage = 0
        End If
        errorMessage = "unable to remove the transient gfxlib image file"
        Return 0
    End If
    Return loadResult
End Function


' -------------------------------------------------------------------------
' Public loading and ownership API
' -------------------------------------------------------------------------

Private Function rasterimage_ScaledChannel(ByVal channelValue As Double) As UInteger
    If channelValue <= 0.0 Then Return 0
    If channelValue >= 255.0 Then Return 255
    Return CUInt(Int(channelValue + 0.5))
End Function

Private Function rasterimage_SmoothPixel( _
    ByVal firstRow As ULong Ptr, ByVal secondRow As ULong Ptr, _
    ByVal firstX As Long, ByVal secondX As Long, _
    ByVal fractionX As Double, ByVal fractionY As Double _
) As ULong
    Dim As ULong samples(0 To 3) = {firstRow[firstX], firstRow[secondX], secondRow[firstX], secondRow[secondX]}
    Dim As Double weights(0 To 3) = { _
        (1.0 - fractionX) * (1.0 - fractionY), fractionX * (1.0 - fractionY), _
        (1.0 - fractionX) * fractionY, fractionX * fractionY _
    }
    Dim As Double alphaValue, redValue, greenValue, blueValue
    ' Weight colors by alpha before interpolation. Transparent pixels often
    ' contain arbitrary RGB values that would otherwise create edge halos.
    For sampleIndex As Long = 0 To 3
        Dim As Double sampleAlpha = ((samples(sampleIndex) Shr 24) And &HFF) * weights(sampleIndex)
        alphaValue += sampleAlpha
        redValue += ((samples(sampleIndex) Shr 16) And &HFF) * sampleAlpha
        greenValue += ((samples(sampleIndex) Shr 8) And &HFF) * sampleAlpha
        blueValue += (samples(sampleIndex) And &HFF) * sampleAlpha
    Next sampleIndex
    If alphaValue <= 0.0 Then Return RGBA(0, 0, 0, 0)
    Return RGBA(rasterimage_ScaledChannel(redValue / alphaValue), _
        rasterimage_ScaledChannel(greenValue / alphaValue), _
        rasterimage_ScaledChannel(blueValue / alphaValue), rasterimage_ScaledChannel(alphaValue))
End Function

Function rasterimage_ScaleToFit( _
    ByVal loadedImage As RasterImage Ptr, _
    ByVal maximumWidth As Long, ByVal maximumHeight As Long, _
    ByRef errorMessage As String, ByVal allowEnlarge As Integer, ByVal smooth As Integer _
) As Integer
    Dim As Long sourceWidth
    Dim As Long sourceHeight
    Dim As Long sourceBytesPerPixel
    Dim As Long sourcePitch
    Dim As Long sourceSize
    Dim As Long actualSourceWidth
    Dim As Long actualSourceHeight
    Dim As Any Ptr sourcePixels
    Dim As Long targetWidth
    Dim As Long targetHeight
    Dim As Any Ptr scaledImage
    Dim As Long scaledWidth
    Dim As Long scaledHeight
    Dim As Long scaledBytesPerPixel
    Dim As Long scaledPitch
    Dim As Long scaledSize
    Dim As Any Ptr scaledPixels
    Dim As Long sourceX
    Dim As Long sourceY

    errorMessage = ""
    If loadedImage = 0 OrElse loadedImage->pixels = 0 Then
        errorMessage = "image is not initialized"
        Return 0
    End If
    If maximumWidth < 1 AndAlso maximumHeight < 1 Then Return -1

    sourceWidth = loadedImage->width
    sourceHeight = loadedImage->height
    If rasterimage_ValidateDimensions(sourceWidth, sourceHeight, errorMessage) = 0 Then Return 0
    targetWidth = sourceWidth
    targetHeight = sourceHeight

    ' Enlargement is explicit, so existing document images retain their size.
    If maximumWidth > 0 AndAlso (targetWidth > maximumWidth OrElse allowEnlarge <> 0) Then
        targetHeight = ( _
            CLngInt(sourceHeight) * maximumWidth _
        ) \ sourceWidth
        targetWidth = maximumWidth
        If targetHeight < 1 Then targetHeight = 1
    End If
    If maximumHeight > 0 AndAlso (targetHeight > maximumHeight OrElse _
       (allowEnlarge <> 0 AndAlso maximumWidth <= 0)) Then
        targetWidth = ( _
            CLngInt(targetWidth) * maximumHeight _
        ) \ targetHeight
        targetHeight = maximumHeight
        If targetWidth < 1 Then targetWidth = 1
    End If
    If targetWidth = sourceWidth AndAlso targetHeight = sourceHeight Then
        Return -1
    End If
    If Not rasterimage_ValidateDimensions( _
        targetWidth, targetHeight, errorMessage _
    ) Then Return 0

    If ImageInfo( _
        loadedImage->pixels, actualSourceWidth, actualSourceHeight, _
        sourceBytesPerPixel, sourcePitch, sourcePixels, sourceSize _
    ) <> 0 OrElse sourceBytesPerPixel <> 4 OrElse sourcePixels = 0 Then
        errorMessage = "source is not a valid 32-bit gfxlib image"
        Return 0
    End If
    If actualSourceWidth <> sourceWidth OrElse actualSourceHeight <> sourceHeight OrElse _
       sourcePitch < sourceWidth * 4 OrElse _
       CLngInt(sourcePitch) * CLngInt(sourceHeight) > sourceSize Then
        errorMessage = "source image dimensions or pitch are invalid"
        Return 0
    End If

    scaledImage = backend_CreateImage( _
        targetWidth, targetHeight, RGBA(0, 0, 0, 0), 32 _
    )
    If scaledImage = 0 Then
        errorMessage = "unable to allocate a scaled image buffer"
        Return 0
    End If
    If ImageInfo( _
        scaledImage, scaledWidth, scaledHeight, scaledBytesPerPixel, _
        scaledPitch, scaledPixels, scaledSize _
    ) <> 0 OrElse scaledBytesPerPixel <> 4 OrElse scaledPixels = 0 Then
        ImageDestroy scaledImage
        errorMessage = "gfxlib returned an invalid scaled image buffer"
        Return 0
    End If
    If scaledWidth <> targetWidth OrElse scaledHeight <> targetHeight OrElse _
       scaledPitch < scaledWidth * 4 OrElse _
       CLngInt(scaledPitch) * CLngInt(scaledHeight) > scaledSize Then
        ImageDestroy scaledImage
        errorMessage = "scaled image dimensions or pitch are invalid"
        Return 0
    End If

    /'
        Hard-edged diagrams retain nearest-neighbor sampling by default.
        Logos can request bilinear sampling with premultiplied alpha; both
        methods run once when loading and need no graphics dependency.
    '/
    For targetY As Long = 0 To targetHeight - 1
        sourceY = (CLngInt(targetY) * sourceHeight) \ targetHeight
        Dim As Double coordinateY = (CDbl(targetY) + 0.5) * sourceHeight / targetHeight - 0.5
        If coordinateY < 0.0 Then coordinateY = 0.0
        Dim As Long smoothY = Int(coordinateY)
        Dim As Long nextY = smoothY + 1
        If nextY >= sourceHeight Then nextY = sourceHeight - 1
        Dim As ULong Ptr targetRow = Cast(ULong Ptr, Cast(UByte Ptr, scaledPixels) + targetY * scaledPitch)
        Dim As ULong Ptr sourceRow = Cast(ULong Ptr, _
            Cast(UByte Ptr, sourcePixels) + sourceY * sourcePitch)
        For targetX As Long = 0 To targetWidth - 1
            sourceX = (CLngInt(targetX) * sourceWidth) \ targetWidth
            Dim As ULong pixelColor
            If smooth <> 0 Then
                Dim As Double coordinateX = (CDbl(targetX) + 0.5) * sourceWidth / targetWidth - 0.5
                If coordinateX < 0.0 Then coordinateX = 0.0
                Dim As Long smoothX = Int(coordinateX)
                Dim As Long nextX = smoothX + 1
                If nextX >= sourceWidth Then nextX = sourceWidth - 1
                pixelColor = rasterimage_SmoothPixel( _
                    Cast(ULong Ptr, Cast(UByte Ptr, sourcePixels) + smoothY * sourcePitch), _
                    Cast(ULong Ptr, Cast(UByte Ptr, sourcePixels) + nextY * sourcePitch), _
                    smoothX, nextX, coordinateX - smoothX, coordinateY - smoothY)
            Else
                ' Source row and column remain within the validated allocation.
                pixelColor = sourceRow[sourceX]
            End If
            ' Target row and column remain within the validated allocation.
            targetRow[targetX] = pixelColor
        Next targetX
    Next targetY

    ImageDestroy loadedImage->pixels
    loadedImage->pixels = scaledImage
    loadedImage->width = targetWidth
    loadedImage->height = targetHeight
    Return -1
End Function

Function rasterimage_LoadMemory( _
    bytes() As UByte, _
    ByVal byteCount As LongInt, _
    ByRef loadedImage As RasterImage Ptr, _
    ByRef errorMessage As String _
) As Integer
    Dim As Integer formatKind

    loadedImage = 0
    errorMessage = ""
    If byteCount < 1 OrElse byteCount > RASTERIMAGE_MAX_FILE_BYTES Then
        errorMessage = "image byte count is empty or exceeds the 32 MiB limit"
        Return 0
    End If

    formatKind = rasterimage_DetectFormat(bytes(), byteCount)
    Select Case formatKind
    Case RASTERIMAGE_FORMAT_ICO
        Return rasterico_Decode(bytes(), byteCount, loadedImage, errorMessage)
    Case RASTERIMAGE_FORMAT_GIF
        Return rastergif_Decode( _
            bytes(), byteCount, loadedImage, errorMessage _
        )
    Case RASTERIMAGE_FORMAT_JPEG
        Return rasterjpeg_Decode( _
            bytes(), byteCount, loadedImage, errorMessage _
        )
    Case RASTERIMAGE_FORMAT_BMP, RASTERIMAGE_FORMAT_PNG
        Return rasterimage_LoadGfxMemory( _
            bytes(), byteCount, formatKind, loadedImage, errorMessage _
        )
    End Select

    errorMessage = "unrecognized raster image signature"
    Return 0
End Function


Function rasterimage_LoadFile( _
    ByVal filePath As String, _
    ByRef loadedImage As RasterImage Ptr, _
    ByRef errorMessage As String _
) As Integer
    Dim As UByte bytes()
    Dim As Integer fileNumber
    Dim As Integer ioResult
    Dim As LongInt byteCount
    Dim As Integer formatKind

    loadedImage = 0
    errorMessage = ""
    If Len(Trim(filePath)) = 0 Then
        errorMessage = "image file path is empty"
        Return 0
    End If

    fileNumber = FreeFile
    ioResult = Open(filePath For Binary Access Read As #fileNumber)
    If ioResult <> 0 Then
        errorMessage = "cannot open image file: " & filePath
        Return 0
    End If
    byteCount = LOF(fileNumber)
    If byteCount < 1 OrElse byteCount > RASTERIMAGE_MAX_FILE_BYTES Then
        Close #fileNumber
        errorMessage = "image file is empty or exceeds the 32 MiB limit"
        Return 0
    End If

    ReDim bytes(0 To byteCount - 1)
    ioResult = Get(#fileNumber, 1, bytes())
    Close #fileNumber
    If ioResult <> 0 Then
        errorMessage = "failed while reading image file: " & filePath
        Return 0
    End If

    formatKind = rasterimage_DetectFormat(bytes(), byteCount)
    If formatKind = RASTERIMAGE_FORMAT_BMP OrElse _
       formatKind = RASTERIMAGE_FORMAT_PNG Then
        Return rasterimage_LoadGfxFile( _
            filePath, bytes(), byteCount, formatKind, loadedImage, errorMessage _
        )
    End If
    Return rasterimage_LoadMemory( _
        bytes(), byteCount, loadedImage, errorMessage _
    )
End Function


Sub rasterimage_Destroy(ByVal loadedImage As RasterImage Ptr)
    If loadedImage = 0 Then Exit Sub
    If loadedImage->pixels <> 0 Then
        ImageDestroy loadedImage->pixels
        loadedImage->pixels = 0
    End If
    Delete loadedImage
End Sub

/' end of raster_image.bas '/
