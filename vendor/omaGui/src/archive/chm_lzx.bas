/'
    Project: omaGUI CHM Reader
    -------------------------

    File: chm_lzx.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements chm_lzx.bi; declarations there define the interface.

    Purpose:

        Decode one bounded LZX reset interval from a CHM compressed stream.

    Responsibilities:

        - read the LZX MSB-first word bitstream
        - decode canonical Huffman trees and LZ matches
        - return only the requested reset interval in memory

    This file intentionally does NOT contain:

        - CHM directory parsing or file extraction
        - file-system access or platform compression APIs
        - LZX DELTA or CAB stream handling

    The implementation is a FreeBASIC port of the regular LZX decoding
    algorithm in libmspack, licensed under LGPL-2.1-or-later. See
    LICENSES/LGPL-2.1.txt.
'/

' -------------------------------------------------------------------------
' Implementation
' -------------------------------------------------------------------------


#include once "src/archive/chm_lzx.bi"

' -------------------------------------------------------------------------
' LZX decoding constants and state
' -------------------------------------------------------------------------

Private Const CHMLZX_NUM_CHARS As Integer = 256
Private Const CHMLZX_NUM_PRIMARY_LENGTHS As Integer = 7
Private Const CHMLZX_NUM_LENGTH_SYMBOLS As Integer = 249
Private Const CHMLZX_PRETREE_SYMBOLS As Integer = 20
Private Const CHMLZX_ALIGNED_SYMBOLS As Integer = 8
Private Const CHMLZX_MAX_TREE_SYMBOLS As Integer = 1024

Private Const CHMLZX_BLOCK_INVALID As Integer = 0
Private Const CHMLZX_BLOCK_VERBATIM As Integer = 1
Private Const CHMLZX_BLOCK_ALIGNED As Integer = 2
Private Const CHMLZX_BLOCK_UNCOMPRESSED As Integer = 3

Type ChmLzxHuffman
    As Integer symbolCount
    As Integer maximumBits
    As Integer isEmpty
    As UByte codeLengths(0 To CHMLZX_MAX_TREE_SYMBOLS - 1)
    As Integer codeCounts(0 To 16)
    As Integer firstSymbol(0 To 16)
    As ULong firstCode(0 To 16)
    As Integer orderedSymbols(0 To CHMLZX_MAX_TREE_SYMBOLS - 1)
End Type

Type ChmLzxDecoder
    As String inputText
    As Integer inputPosition
    As Integer syntheticBytes
    As ULong bitBuffer
    As Integer bitsLeft
    As UByte Ptr window
    As Integer windowBits
    As Integer windowSize
    As Integer numberOfOffsets
    As Integer resetFrameCount
    As Integer windowPosition
    As Integer blockType
    As Integer blockLength
    As Integer blockRemaining
    As Integer headerRead
    As Integer intelStarted
    As ULong intelFileSize
    As ULong r0, r1, r2
    As String errorText
    As ChmLzxHuffman pretree
    As ChmLzxHuffman maintree
    As ChmLzxHuffman lengthtree
    As ChmLzxHuffman alignedtree
End Type


Private Function chmlzx_SetError( _
    ByVal decoder As ChmLzxDecoder Ptr, ByRef message As Const String _
) As Integer

    If decoder <> 0 Then decoder->errorText = message
    Return 0

End Function


Private Function chmlzx_ReadBits( _
    ByVal decoder As ChmLzxDecoder Ptr, ByVal bitCount As Integer, _
    ByRef value As ULong _
) As Integer

    Dim As Integer shiftCount
    Dim As ULong wordValue

    value = 0
    If decoder = 0 OrElse bitCount < 0 OrElse bitCount > 17 Then _
        Return chmlzx_SetError(decoder, "invalid LZX bit count")
    If bitCount = 0 Then Return -1

    While decoder->bitsLeft < bitCount
        If decoder->inputPosition + 1 >= Len(decoder->inputText) Then
            If decoder->syntheticBytes >= 2 Then _
                Return chmlzx_SetError( _
                    decoder, "compressed LZX block ended before its header" _
                )
            wordValue = 0
            decoder->syntheticBytes += 2
        Else
            wordValue = Asc(Mid( _
                decoder->inputText, decoder->inputPosition + 1, 1 _
            ))
            wordValue = wordValue Or CULng(Asc(Mid( _
                decoder->inputText, decoder->inputPosition + 2, 1 _
            ))) Shl 8
            decoder->inputPosition += 2
        End If

        shiftCount = 16 - decoder->bitsLeft
        decoder->bitBuffer = decoder->bitBuffer Or (wordValue Shl shiftCount)
        decoder->bitsLeft += 16
    Wend

    value = decoder->bitBuffer Shr (32 - bitCount)
    decoder->bitBuffer = decoder->bitBuffer Shl bitCount
    decoder->bitsLeft -= bitCount
    Return -1

End Function


Private Function chmlzx_EnsureBits( _
    ByVal decoder As ChmLzxDecoder Ptr, ByVal bitCount As Integer _
) As Integer

    Dim As ULong wordValue

    If decoder = 0 OrElse bitCount < 0 OrElse bitCount > 16 Then _
        Return chmlzx_SetError(decoder, "invalid LZX bit buffer request")

    While decoder->bitsLeft < bitCount
        If decoder->inputPosition + 1 >= Len(decoder->inputText) Then
            If decoder->syntheticBytes >= 2 Then _
                Return chmlzx_SetError( _
                    decoder, "compressed LZX block ended before alignment" _
                )
            wordValue = 0
            decoder->syntheticBytes += 2
        Else
            wordValue = Asc(Mid( _
                decoder->inputText, decoder->inputPosition + 1, 1 _
            ))
            wordValue = wordValue Or (CULng(Asc(Mid( _
                decoder->inputText, decoder->inputPosition + 2, 1 _
            ))) Shl 8)
            decoder->inputPosition += 2
        End If

        decoder->bitBuffer = decoder->bitBuffer Or _
            (wordValue Shl (16 - decoder->bitsLeft))
        decoder->bitsLeft += 16
    Wend

    Return -1

End Function


Private Function chmlzx_ReadRawByte( _
    ByVal decoder As ChmLzxDecoder Ptr, ByRef value As UByte _
) As Integer

    If decoder = 0 OrElse _
       decoder->inputPosition >= Len(decoder->inputText) Then _
        Return chmlzx_SetError( _
            decoder, "compressed LZX block ended in an uncompressed run" _
        )
    value = Asc(Mid( _
        decoder->inputText, decoder->inputPosition + 1, 1 _
    ))
    decoder->inputPosition += 1
    Return -1

End Function


Private Function chmlzx_ReadRawU32( _
    ByVal decoder As ChmLzxDecoder Ptr, ByRef value As ULong _
) As Integer

    Dim As UByte byteValue

    value = 0
    For byteIndex As Integer = 0 To 3
        If chmlzx_ReadRawByte(decoder, byteValue) = 0 Then Return 0
        value Or= CULng(byteValue) Shl (byteIndex * 8)
    Next byteIndex
    Return -1

End Function


Private Function chmlzx_BuildHuffman( _
    ByVal decoder As ChmLzxDecoder Ptr, _
    ByVal tree As ChmLzxHuffman Ptr, _
    ByVal symbolCount As Integer, _
    ByVal allowEmpty As Integer _
) As Integer

    Dim As Integer lengthValue
    Dim As Integer symbolIndex
    Dim As Integer orderedIndex
    Dim As ULong codeValue
    Dim As ULong codeLimit

    If decoder = 0 OrElse tree = 0 OrElse _
       symbolCount < 1 OrElse symbolCount > CHMLZX_MAX_TREE_SYMBOLS Then _
        Return chmlzx_SetError(decoder, "invalid LZX Huffman tree size")

    tree->symbolCount = symbolCount
    tree->maximumBits = 0
    tree->isEmpty = 0
    For lengthValue = 0 To 16
        tree->codeCounts(lengthValue) = 0
        tree->firstSymbol(lengthValue) = 0
        tree->firstCode(lengthValue) = 0
    Next lengthValue

    For symbolIndex = 0 To symbolCount - 1
        lengthValue = tree->codeLengths(symbolIndex)
        If lengthValue > 16 Then _
            Return chmlzx_SetError( _
                decoder, "LZX Huffman code length exceeds 16 bits" _
            )
        If lengthValue > 0 Then
            tree->codeCounts(lengthValue) += 1
            If lengthValue > tree->maximumBits Then _
                tree->maximumBits = lengthValue
        End If
    Next symbolIndex

    If tree->maximumBits = 0 Then
        If allowEmpty <> 0 Then
            tree->isEmpty = -1
            Return -1
        End If
        Return chmlzx_SetError(decoder, "required LZX Huffman tree is empty")
    End If

    orderedIndex = 0
    codeValue = 0
    For lengthValue = 1 To tree->maximumBits
        codeValue = (codeValue + tree->codeCounts(lengthValue - 1)) Shl 1
        codeLimit = 1 Shl lengthValue
        If codeValue + tree->codeCounts(lengthValue) > codeLimit Then _
            Return chmlzx_SetError( _
                decoder, "oversubscribed LZX Huffman tree" _
            )

        tree->firstCode(lengthValue) = codeValue
        tree->firstSymbol(lengthValue) = orderedIndex
        For symbolIndex = 0 To symbolCount - 1
            If tree->codeLengths(symbolIndex) = lengthValue Then
                tree->orderedSymbols(orderedIndex) = symbolIndex
                orderedIndex += 1
            End If
        Next symbolIndex
    Next lengthValue

    Return -1

End Function


Private Function chmlzx_DecodeSymbol( _
    ByVal decoder As ChmLzxDecoder Ptr, _
    ByVal tree As ChmLzxHuffman Ptr, _
    ByRef symbolValue As Integer _
) As Integer

    Dim As Integer bitIndex
    Dim As Integer bitValue
    Dim As ULong bits
    Dim As ULong codeValue = 0
    Dim As ULong codeOffset

    If decoder = 0 OrElse tree = 0 OrElse tree->isEmpty <> 0 Then _
        Return chmlzx_SetError(decoder, "attempted to read an empty LZX tree")

    For bitIndex = 1 To tree->maximumBits
        If chmlzx_ReadBits(decoder, 1, bits) = 0 Then Return 0
        bitValue = CInt(bits)
        codeValue = (codeValue Shl 1) Or CULng(bitValue)
        If tree->codeCounts(bitIndex) > 0 AndAlso _
           codeValue >= tree->firstCode(bitIndex) Then
            codeOffset = codeValue - tree->firstCode(bitIndex)
            If codeOffset < CULng(tree->codeCounts(bitIndex)) Then
                symbolValue = tree->orderedSymbols( _
                    tree->firstSymbol(bitIndex) + CInt(codeOffset) _
                )
                Return -1
            End If
        End If
    Next bitIndex

    Return chmlzx_SetError(decoder, "invalid LZX Huffman code")

End Function


Private Function chmlzx_ReadLengths( _
    ByVal decoder As ChmLzxDecoder Ptr, _
    ByVal targetTree As ChmLzxHuffman Ptr, _
    ByVal firstIndex As Integer, ByVal endIndex As Integer _
) As Integer

    Dim As Integer symbolValue
    Dim As Integer repeatCount
    Dim As Integer decodedLength
    Dim As Integer targetIndex
    Dim As ULong bits

    If decoder = 0 OrElse targetTree = 0 OrElse _
       firstIndex < 0 OrElse endIndex < firstIndex OrElse _
       endIndex > CHMLZX_MAX_TREE_SYMBOLS Then _
        Return chmlzx_SetError(decoder, "invalid LZX code-length range")

    For targetIndex = 0 To CHMLZX_PRETREE_SYMBOLS - 1
        If chmlzx_ReadBits(decoder, 4, bits) = 0 Then Return 0
        decoder->pretree.codeLengths(targetIndex) = CByte(bits)
    Next targetIndex
    If chmlzx_BuildHuffman( _
        decoder, @decoder->pretree, CHMLZX_PRETREE_SYMBOLS, 0 _
    ) = 0 Then Return 0

    targetIndex = firstIndex
    While targetIndex < endIndex
        If chmlzx_DecodeSymbol( _
            decoder, @decoder->pretree, symbolValue _
        ) = 0 Then Return 0

        Select Case symbolValue
        Case 17
            If chmlzx_ReadBits(decoder, 4, bits) = 0 Then Return 0
            repeatCount = CInt(bits) + 4
            If repeatCount > endIndex - targetIndex Then _
                Return chmlzx_SetError( _
                    decoder, "LZX zero-length run exceeds its code table" _
                )
            ' fblint: disable-next-line FBL311 REASON: The loop counter bounds repeated work; the cursor or stream state supplies each value.
            For repeatIndex As Integer = 0 To repeatCount - 1
                targetTree->codeLengths(targetIndex) = 0
                targetIndex += 1
            Next repeatIndex

        Case 18
            If chmlzx_ReadBits(decoder, 5, bits) = 0 Then Return 0
            repeatCount = CInt(bits) + 20
            If repeatCount > endIndex - targetIndex Then _
                Return chmlzx_SetError( _
                    decoder, "LZX long zero run exceeds its code table" _
                )
            ' fblint: disable-next-line FBL311 REASON: The loop counter bounds repeated work; the cursor or stream state supplies each value.
            For repeatIndex As Integer = 0 To repeatCount - 1
                targetTree->codeLengths(targetIndex) = 0
                targetIndex += 1
            Next repeatIndex

        Case 19
            If chmlzx_ReadBits(decoder, 1, bits) = 0 Then Return 0
            repeatCount = CInt(bits) + 4
            If repeatCount > endIndex - targetIndex Then _
                Return chmlzx_SetError( _
                    decoder, "LZX repeated code exceeds its code table" _
                )
            If chmlzx_DecodeSymbol( _
                decoder, @decoder->pretree, decodedLength _
            ) = 0 Then Return 0
            decodedLength = _
                (CInt(targetTree->codeLengths(targetIndex)) - _
                 decodedLength + 17) Mod 17
            ' fblint: disable-next-line FBL311 REASON: The loop counter bounds repeated work; the cursor or stream state supplies each value.
            For repeatIndex As Integer = 0 To repeatCount - 1
                targetTree->codeLengths(targetIndex) = CByte(decodedLength)
                targetIndex += 1
            Next repeatIndex

        Case Else
            decodedLength = _
                (CInt(targetTree->codeLengths(targetIndex)) - _
                 symbolValue + 17) Mod 17
            targetTree->codeLengths(targetIndex) = CByte(decodedLength)
            targetIndex += 1
        End Select
    Wend

    Return -1

End Function


Private Sub chmlzx_ResetStreamState(ByVal decoder As ChmLzxDecoder Ptr)

    If decoder = 0 Then Exit Sub

    decoder->r0 = 1
    decoder->r1 = 1
    decoder->r2 = 1
    decoder->headerRead = 0
    decoder->intelStarted = 0
    decoder->intelFileSize = 0
    decoder->blockLength = 0
    decoder->blockRemaining = 0
    decoder->blockType = CHMLZX_BLOCK_INVALID
    decoder->pretree.isEmpty = 0
    decoder->maintree.isEmpty = 0
    decoder->lengthtree.isEmpty = 0
    decoder->alignedtree.isEmpty = 0

    For symbolIndex As Integer = 0 To decoder->maintree.symbolCount - 1
        decoder->maintree.codeLengths(symbolIndex) = 0
    Next symbolIndex
    For symbolIndex As Integer = 0 To CHMLZX_NUM_LENGTH_SYMBOLS - 1
        decoder->lengthtree.codeLengths(symbolIndex) = 0
    Next symbolIndex

End Sub


Private Function chmlzx_PositionExtraBits( _
    ByVal slotIndex As Integer _
) As Integer

    If slotIndex < 4 Then Return 0
    If slotIndex < 36 Then Return (slotIndex \ 2) - 1
    Return 17

End Function


Private Function chmlzx_PositionBase( _
    ByVal slotIndex As Integer _
) As ULong

    Dim As ULong baseValue = 0

    For index As Integer = 1 To slotIndex
        baseValue += 1 Shl chmlzx_PositionExtraBits(index - 1)
    Next index
    Return baseValue

End Function


Private Function chmlzx_ReadBlockHeader( _
    ByVal decoder As ChmLzxDecoder Ptr _
) As Integer

    Dim As Integer mainSymbolCount
    Dim As ULong bits
    Dim As ULong highLength
    Dim As ULong lowLength

    If chmlzx_ReadBits(decoder, 3, bits) = 0 Then Return 0
    decoder->blockType = CInt(bits)
    If decoder->blockType < CHMLZX_BLOCK_VERBATIM OrElse _
       decoder->blockType > CHMLZX_BLOCK_UNCOMPRESSED Then _
        Return chmlzx_SetError(decoder, "invalid LZX block type")

    If chmlzx_ReadBits(decoder, 16, highLength) = 0 OrElse _
       chmlzx_ReadBits(decoder, 8, lowLength) = 0 Then Return 0
    decoder->blockLength = CInt((highLength Shl 8) Or lowLength)
    If decoder->blockLength < 1 Then _
        Return chmlzx_SetError(decoder, "empty LZX block")
    decoder->blockRemaining = decoder->blockLength

    Select Case decoder->blockType
    Case CHMLZX_BLOCK_ALIGNED, CHMLZX_BLOCK_VERBATIM
        If decoder->blockType = CHMLZX_BLOCK_ALIGNED Then
            For symbolIndex As Integer = 0 To CHMLZX_ALIGNED_SYMBOLS - 1
                If chmlzx_ReadBits(decoder, 3, bits) = 0 Then Return 0
                decoder->alignedtree.codeLengths(symbolIndex) = CByte(bits)
            Next symbolIndex
            If chmlzx_BuildHuffman( _
                decoder, @decoder->alignedtree, CHMLZX_ALIGNED_SYMBOLS, 0 _
            ) = 0 Then Return 0
            ' The aligned header continues with the same trees as verbatim.
        End If

    Case CHMLZX_BLOCK_UNCOMPRESSED
        decoder->intelStarted = -1
        If decoder->bitsLeft = 0 Then
            If chmlzx_EnsureBits(decoder, 16) = 0 Then Return 0
        End If
        decoder->bitsLeft = 0
        decoder->bitBuffer = 0
        If chmlzx_ReadRawU32(decoder, decoder->r0) = 0 OrElse _
           chmlzx_ReadRawU32(decoder, decoder->r1) = 0 OrElse _
           chmlzx_ReadRawU32(decoder, decoder->r2) = 0 Then Return 0
        If decoder->r0 = 0 OrElse decoder->r1 = 0 OrElse _
           decoder->r2 = 0 Then _
            Return chmlzx_SetError( _
                decoder, "invalid repeated offsets in LZX block" _
            )
    End Select

    If decoder->blockType = CHMLZX_BLOCK_ALIGNED OrElse _
       decoder->blockType = CHMLZX_BLOCK_VERBATIM Then
        mainSymbolCount = CHMLZX_NUM_CHARS + decoder->numberOfOffsets
        If chmlzx_ReadLengths( _
            decoder, @decoder->maintree, 0, CHMLZX_NUM_CHARS _
        ) = 0 Then Return 0
        If chmlzx_ReadLengths( _
            decoder, @decoder->maintree, CHMLZX_NUM_CHARS, _
            mainSymbolCount _
        ) = 0 Then Return 0
        If chmlzx_BuildHuffman( _
            decoder, @decoder->maintree, mainSymbolCount, 0 _
        ) = 0 Then Return 0
        If decoder->maintree.codeLengths(&hE8) <> 0 Then _
            decoder->intelStarted = -1

        If chmlzx_ReadLengths( _
            decoder, @decoder->lengthtree, 0, CHMLZX_NUM_LENGTH_SYMBOLS _
        ) = 0 Then Return 0
        If chmlzx_BuildHuffman( _
            decoder, @decoder->lengthtree, CHMLZX_NUM_LENGTH_SYMBOLS, -1 _
        ) = 0 Then Return 0
    End If

    Return -1

End Function


Private Function chmlzx_ReadMatchOffset( _
    ByVal decoder As ChmLzxDecoder Ptr, ByVal offsetSlot As Integer, _
    ByRef matchOffset As ULong _
) As Integer

    Dim As ULong bits
    Dim As Integer extraBitCount

    Select Case offsetSlot
    Case 0
        matchOffset = decoder->r0
        Return -1
    Case 1
        matchOffset = decoder->r1
        decoder->r1 = decoder->r0
        decoder->r0 = matchOffset
        Return -1
    Case 2
        matchOffset = decoder->r2
        decoder->r2 = decoder->r0
        decoder->r0 = matchOffset
        Return -1
    End Select

    If offsetSlot < 3 OrElse offsetSlot >= decoder->numberOfOffsets Then _
        Return chmlzx_SetError(decoder, "LZX match offset slot is out of range")

    extraBitCount = chmlzx_PositionExtraBits(offsetSlot)
    matchOffset = chmlzx_PositionBase(offsetSlot) - 2
    If extraBitCount >= 3 AndAlso _
       decoder->blockType = CHMLZX_BLOCK_ALIGNED Then
        If extraBitCount > 3 Then
            If chmlzx_ReadBits( _
                decoder, extraBitCount - 3, bits _
            ) = 0 Then Return 0
            matchOffset += bits Shl 3
        End If
        Dim As Integer alignedValue
        If chmlzx_DecodeSymbol( _
            decoder, @decoder->alignedtree, alignedValue _
        ) = 0 Then Return 0
        matchOffset += alignedValue
    ElseIf extraBitCount > 0 Then
        If chmlzx_ReadBits(decoder, extraBitCount, bits) = 0 Then Return 0
        matchOffset += bits
    End If

    decoder->r2 = decoder->r1
    decoder->r1 = decoder->r0
    decoder->r0 = matchOffset
    Return -1

End Function


Private Function chmlzx_ReadMatchLength( _
    ByVal decoder As ChmLzxDecoder Ptr, ByVal lengthHeader As Integer, _
    ByRef matchLength As Integer _
) As Integer

    Dim As Integer lengthFooter

    matchLength = lengthHeader And CHMLZX_NUM_PRIMARY_LENGTHS
    If matchLength = CHMLZX_NUM_PRIMARY_LENGTHS Then
        If decoder->lengthtree.isEmpty <> 0 Then _
            Return chmlzx_SetError( _
                decoder, "LZX match requires an empty length tree" _
            )
        If chmlzx_DecodeSymbol( _
            decoder, @decoder->lengthtree, lengthFooter _
        ) = 0 Then Return 0
        matchLength += lengthFooter
    End If

    matchLength += 2
    Return -1

End Function


Private Function chmlzx_DecodeRun( _
    ByVal decoder As ChmLzxDecoder Ptr, _
    ByVal maximumBytes As Integer, _
    ByRef decodedBytes As Integer _
) As Integer

    Dim As Integer mainSymbol
    Dim As Integer matchLength
    Dim As Integer offsetSlot
    Dim As Integer bytesLeft = maximumBytes
    Dim As Integer windowPosition
    Dim As Integer sourcePosition
    Dim As ULong matchOffset

    decodedBytes = 0
    While bytesLeft > 0
        If chmlzx_DecodeSymbol( _
            decoder, @decoder->maintree, mainSymbol _
        ) = 0 Then Return 0

        If mainSymbol < CHMLZX_NUM_CHARS Then
            decoder->window[decoder->windowPosition] = CByte(mainSymbol)
            decoder->windowPosition += 1
            If decoder->windowPosition = decoder->windowSize Then _
                decoder->windowPosition = 0
            decodedBytes += 1
            bytesLeft -= 1
            decoder->blockRemaining -= 1
            Continue While
        End If

        mainSymbol -= CHMLZX_NUM_CHARS
        offsetSlot = mainSymbol Shr 3
        If chmlzx_ReadMatchLength( _
            decoder, mainSymbol And 7, matchLength _
        ) = 0 Then Return 0
        If chmlzx_ReadMatchOffset( _
            decoder, offsetSlot, matchOffset _
        ) = 0 Then Return 0

        If matchOffset < 1 OrElse matchOffset > CULng(decoder->windowSize) OrElse _
           matchOffset > CULng(CHM_LZX_MAX_RESET_BYTES) Then _
            Return chmlzx_SetError(decoder, "invalid LZX match distance")
        If matchLength < 2 OrElse matchLength > bytesLeft OrElse _
           matchLength > decoder->blockRemaining Then _
            Return chmlzx_SetError( _
                decoder, "LZX match exceeds its current output block" _
            )

        windowPosition = decoder->windowPosition
        If windowPosition + matchLength > decoder->windowSize Then _
            Return chmlzx_SetError( _
                decoder, "LZX match crosses its history window boundary" _
            )
        sourcePosition = windowPosition - CInt(matchOffset)
        If sourcePosition < 0 Then sourcePosition += decoder->windowSize
        ' fblint: disable-next-line FBL311 REASON: The loop counter bounds repeated work; the cursor or stream state supplies each value.
        For copyIndex As Integer = 0 To matchLength - 1
            decoder->window[windowPosition] = decoder->window[sourcePosition]
            windowPosition += 1
            sourcePosition += 1
            If windowPosition = decoder->windowSize Then windowPosition = 0
            If sourcePosition = decoder->windowSize Then sourcePosition = 0
        Next copyIndex
        decoder->windowPosition = windowPosition
        decoder->blockRemaining -= matchLength
        decodedBytes += matchLength
        bytesLeft -= matchLength
    Wend

    Return -1

End Function


Private Function chmlzx_DecodeUncompressedRun( _
    ByVal decoder As ChmLzxDecoder Ptr, ByVal byteCount As Integer _
) As Integer

    Dim As UByte byteValue

    If byteCount < 0 OrElse byteCount > decoder->blockRemaining Then _
        Return chmlzx_SetError( _
            decoder, "invalid raw LZX block length" _
        )

    ' fblint: disable-next-line FBL311 REASON: The loop counter bounds repeated work; the cursor or stream state supplies each value.
    For byteIndex As Integer = 0 To byteCount - 1
        If chmlzx_ReadRawByte(decoder, byteValue) = 0 Then Return 0
        decoder->window[decoder->windowPosition] = byteValue
        decoder->windowPosition += 1
        If decoder->windowPosition = decoder->windowSize Then _
            decoder->windowPosition = 0
    Next byteIndex
    decoder->blockRemaining -= byteCount
    Return -1

End Function


Private Sub chmlzx_ApplyE8( _
    ByRef outputText As String, ByVal frameStart As Integer, _
    ByVal frameLength As Integer, ByVal frameNumber As Integer, _
    ByVal intelFileSize As ULong _
)

    Dim As Integer scanPosition = 0
    Dim As Long currentPosition = frameNumber * CHM_LZX_FRAME_BYTES
    Dim As Long fileSize = CLng(intelFileSize)
    Dim As Long absoluteOffset
    Dim As Long relativeOffset
    Dim As ULong encodedOffset

    If intelFileSize = 0 OrElse frameLength <= 10 Then Exit Sub

    While scanPosition < frameLength - 10
        If outputText[frameStart + scanPosition] <> &hE8 Then
            scanPosition += 1
            currentPosition += 1
            Continue While
        End If

        encodedOffset = outputText[frameStart + scanPosition + 1]
        encodedOffset Or= CULng( _
            outputText[frameStart + scanPosition + 2] _
        ) Shl 8
        encodedOffset Or= CULng( _
            outputText[frameStart + scanPosition + 3] _
        ) Shl 16
        encodedOffset Or= CULng( _
            outputText[frameStart + scanPosition + 4] _
        ) Shl 24
        absoluteOffset = CLng(encodedOffset)

        If absoluteOffset >= -currentPosition AndAlso _
           absoluteOffset < fileSize Then
            If absoluteOffset >= 0 Then
                relativeOffset = absoluteOffset - currentPosition
            Else
                relativeOffset = absoluteOffset + fileSize
            End If
            encodedOffset = CULng(relativeOffset)
            outputText[frameStart + scanPosition + 1] = _
                CByte(encodedOffset And &hFF)
            outputText[frameStart + scanPosition + 2] = _
                CByte((encodedOffset Shr 8) And &hFF)
            outputText[frameStart + scanPosition + 3] = _
                CByte((encodedOffset Shr 16) And &hFF)
            outputText[frameStart + scanPosition + 4] = _
                CByte((encodedOffset Shr 24) And &hFF)
        End If

        scanPosition += 5
        currentPosition += 5
    Wend

End Sub


Private Function chmlzx_DecodeFrame( _
    ByVal decoder As ChmLzxDecoder Ptr, _
    ByRef outputText As String, ByVal outputOffset As Integer, _
    ByVal frameLength As Integer, ByVal frameNumber As Integer _
) As Integer

    Dim As Integer frameWindowStart
    Dim As Integer frameBytesLeft
    Dim As Integer runLength
    Dim As Integer decodedBytes
    Dim As Integer framePosition
    Dim As ULong bits
    Dim As Integer bitRemainder

    frameWindowStart = decoder->windowPosition
    frameBytesLeft = frameLength

    If decoder->headerRead = 0 Then
        If chmlzx_ReadBits(decoder, 1, bits) = 0 Then Return 0
        If bits <> 0 Then
            Dim As ULong upperFileSize
            If chmlzx_ReadBits(decoder, 16, upperFileSize) = 0 OrElse _
               chmlzx_ReadBits(decoder, 16, bits) = 0 Then Return 0
            decoder->intelFileSize = (upperFileSize Shl 16) Or bits
        End If
        decoder->headerRead = -1
    End If

    While frameBytesLeft > 0
        If decoder->blockRemaining = 0 Then
            If decoder->blockType = CHMLZX_BLOCK_UNCOMPRESSED AndAlso _
               (decoder->blockLength And 1) <> 0 Then
                If decoder->inputPosition >= Len(decoder->inputText) Then _
                    Return chmlzx_SetError( _
                        decoder, "missing LZX raw-block alignment byte" _
                    )
                decoder->inputPosition += 1
            End If
            If chmlzx_ReadBlockHeader(decoder) = 0 Then Return 0
        End If

        runLength = decoder->blockRemaining
        If runLength > frameBytesLeft Then runLength = frameBytesLeft
        If runLength < 1 Then _
            Return chmlzx_SetError(decoder, "invalid LZX frame run")

        If decoder->blockType = CHMLZX_BLOCK_UNCOMPRESSED Then
            If chmlzx_DecodeUncompressedRun(decoder, runLength) = 0 Then _
                Return 0
        Else
            If chmlzx_DecodeRun( _
                decoder, runLength, decodedBytes _
            ) = 0 Then Return 0
            If decodedBytes <> runLength Then _
                Return chmlzx_SetError( _
                    decoder, "LZX code did not fill its frame run" _
                )
        End If
        frameBytesLeft -= runLength
    Wend

    If decoder->bitsLeft > 0 Then
        If chmlzx_EnsureBits(decoder, 16) = 0 Then Return 0
        bitRemainder = decoder->bitsLeft And 15
        If bitRemainder > 0 Then
            decoder->bitBuffer = decoder->bitBuffer Shl bitRemainder
            decoder->bitsLeft -= bitRemainder
        End If
    End If

    For framePosition = 0 To frameLength - 1
        outputText[outputOffset + framePosition] = _
            decoder->window[ _
                (frameWindowStart + framePosition) Mod decoder->windowSize _ ' fblint: disable-line FBL406 REASON: Range checks keep the dividend nonnegative and the modulus positive before this calculation.
            ]
    Next framePosition

    If decoder->intelStarted <> 0 AndAlso frameNumber < 32768 Then _
        chmlzx_ApplyE8( _
            outputText, outputOffset, frameLength, frameNumber, _
            decoder->intelFileSize _
        )

    Return -1

End Function


Function chmlzx_DecompressReset( _
    ByRef compressedText As Const String, _
    ByVal outputLength As Integer, _
    ByVal windowBits As Integer, _
    ByVal resetFrameCount As Integer, _
    ByRef outputText As String, _
    ByRef errorText As String _
) As Integer

    Dim As ChmLzxDecoder Ptr decoder
    Dim As Integer positionSlots
    Dim As Integer frameCount
    Dim As Integer outputOffset
    Dim As Integer frameLength

    outputText = ""
    errorText = ""
    If Len(compressedText) < 2 Then
        errorText = "LZX reset interval has no compressed data"
        Return 0
    End If
    If outputLength < 1 OrElse outputLength > CHM_LZX_MAX_RESET_BYTES Then
        errorText = "LZX reset interval exceeds the 4 MiB safety limit"
        Return 0
    End If
    If windowBits < 15 OrElse windowBits > CHM_LZX_MAX_WINDOW_BITS Then
        errorText = "CHM LZX window size is outside the supported range"
        Return 0
    End If
    If resetFrameCount < 1 OrElse _
       resetFrameCount > CHM_LZX_MAX_RESET_BYTES \ CHM_LZX_FRAME_BYTES Then
        errorText = "invalid CHM LZX reset interval"
        Return 0
    End If

    Select Case windowBits
    Case 15: positionSlots = 30
    Case 16: positionSlots = 32
    Case 17: positionSlots = 34
    Case 18: positionSlots = 36
    Case 19: positionSlots = 38
    Case 20: positionSlots = 42
    Case 21: positionSlots = 50
    Case Else
        errorText = "unsupported CHM LZX window size"
        Return 0
    End Select

    decoder = New ChmLzxDecoder
    If decoder = 0 Then
        errorText = "could not allocate LZX decoder state"
        Return 0
    End If
    decoder->windowBits = windowBits
    decoder->windowSize = 1 Shl windowBits
    decoder->numberOfOffsets = positionSlots * 8
    decoder->resetFrameCount = resetFrameCount
    decoder->inputText = compressedText
    decoder->maintree.symbolCount = _
        CHMLZX_NUM_CHARS + decoder->numberOfOffsets
    decoder->window = Callocate(decoder->windowSize)
    If decoder->window = 0 Then
        errorText = "could not allocate the LZX history window"
        Delete decoder
        Return 0
    End If

    outputText = String(outputLength, Chr(0))
    frameCount = (outputLength + CHM_LZX_FRAME_BYTES - 1) \ _
        CHM_LZX_FRAME_BYTES
    outputOffset = 0

    For frameNumber As Integer = 0 To frameCount - 1
        If frameNumber Mod resetFrameCount = 0 Then _
            chmlzx_ResetStreamState(decoder)
        frameLength = outputLength - outputOffset
        If frameLength > CHM_LZX_FRAME_BYTES Then _
            frameLength = CHM_LZX_FRAME_BYTES
        If chmlzx_DecodeFrame( _
            decoder, outputText, outputOffset, frameLength, frameNumber _
        ) = 0 Then
            errorText = decoder->errorText
            If decoder->window <> 0 Then Deallocate decoder->window
            Delete decoder
            outputText = ""
            Return 0
        End If
        outputOffset += frameLength
    Next frameNumber

    If decoder->window <> 0 Then Deallocate decoder->window
    Delete decoder
    Return -1

End Function

/' end of chm_lzx.bas '/
