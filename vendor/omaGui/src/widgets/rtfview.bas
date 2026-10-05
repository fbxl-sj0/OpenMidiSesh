/'
    Project: omaGUI
    ---------------

    File: rtfview.bas

    Purpose:

        Parse and display bounded, read-only RTF documents.

    Responsibilities:

        - retain visible text as character-format runs and paragraphs
        - preserve bounded font and color tables and Unicode scalars
        - wrap document runs into lines using embedded omaGUI fonts
        - provide scrolling, clipping, rendering, and widget lifecycle

    This file intentionally does NOT contain:

        - document file access or navigation
        - rich text editing or hyperlink activation
        - platform-native rich text controls
'/ 

#lang "fb"
#include once "src/widgets/rtfview.bi"
#include once "src/widgets/scrollbar.bi"
#include once "src/backend/theme.bi"

Const RTFVIEW_SCROLLBAR_WIDTH As Integer = 15
Const RTFVIEW_CONTENT_INSET As Integer = 4
Const RTFVIEW_WHEEL_LINES As Integer = 3
Const RTFVIEW_TWIPS_PER_PIXEL As Integer = 15
' Two pixels of leading keep neighboring RTF text rows visually separate.
Const RTFVIEW_LINE_EXTRA_HEIGHT As Integer = 2
Const RTFVIEW_TABLE_FONTS As Integer = 1
Const RTFVIEW_TABLE_COLORS As Integer = 2
Const RTFVIEW_METRIC_CACHE_COUNT As Integer = 32

Private Type RtfViewParserState
    As Integer skip_destination
    As Integer ignorable_next
    As Integer unicode_fallback
    As Integer unicode_fallback_count
    As Integer bold
    As Integer italic
    As Integer underline
    As Integer hidden
    As Integer color_index
    As Integer alignment
    As Integer left_indent
    As Integer first_indent
    As Integer right_indent
    As Integer font_number, font_halfpoints, resolved_font_id
    ' Table destinations have their own group-scoped state and never emit text.
    As Integer table_kind, table_ignored, table_font_number, table_monospaced
    As String table_font_name
    As Integer color_red, color_green, color_blue, color_has_components
End Type

' -------------------------------------------------------------------------
' Font substitution and document tables
' -------------------------------------------------------------------------

Private Function rtfview_FontNumberIndex(ByVal d As RtfViewData Ptr, ByVal number As Integer) As Integer
    For fontIndex As Integer = 0 To d->font_count - 1
        If d->fonts(fontIndex).number = number Then Return fontIndex
    Next fontIndex
    Return -1
End Function

Private Function rtfview_ResolveFont(ByVal d As RtfViewData Ptr, ByRef parserState As RtfViewParserState) As Integer
    If parserState.resolved_font_id >= 0 Then Return parserState.resolved_font_id
    Dim As Integer fontIndex = rtfview_FontNumberIndex(d, parserState.font_number)
    Dim As Integer isMonospaced
    If fontIndex >= 0 Then isMonospaced = d->fonts(fontIndex).monospaced
    If isMonospaced <> 0 AndAlso backend_IsFontAvailable(BACKEND_FONT_CASCADIA_MONO) <> 0 Then
        parserState.resolved_font_id = BACKEND_FONT_CASCADIA_MONO
    ElseIf isMonospaced <> 0 AndAlso backend_IsFontAvailable(BACKEND_FONT_TERMINAL) <> 0 Then
        parserState.resolved_font_id = BACKEND_FONT_TERMINAL
    ElseIf parserState.bold <> 0 Then
        parserState.resolved_font_id = BACKEND_FONT_ARIAL_12_BOLD
    Else
        parserState.resolved_font_id = BACKEND_FONT_DEFAULT
    End If
    Return parserState.resolved_font_id
End Function

Private Function rtfview_FontPercent(ByVal fontId As Integer, ByVal halfpoints As Integer) As Integer
    ' RTF fs values are half-points. OGF1 retains the source face's point size,
    ' so nominal size changes apply equally to measurement and bitmap drawing.
    ' https://learn.microsoft.com/en-us/windows/win32/controls/about-text-object-model
    Dim As Integer basePointSize = backend_GetFontPointSize(fontId)
    If basePointSize < 1 Then basePointSize = 10
    Dim As Integer percent = (halfpoints * 50 + basePointSize \ 2) \ basePointSize
    If percent < 25 Then percent = 25
    If percent > 900 Then percent = 900
    Return percent
End Function

Private Function rtfview_StoreFont(ByVal d As RtfViewData Ptr, ByRef parserState As RtfViewParserState) As Integer
    If parserState.table_font_number < 0 Then Return -1
    Dim As Integer fontIndex = rtfview_FontNumberIndex(d, parserState.table_font_number)
    If fontIndex < 0 Then
        If d->font_count >= RTFVIEW_MAX_FONTS Then
            d->parse_error = "The RTF document exceeds the font table limit"
            Return 0
        End If
        fontIndex = d->font_count
        d->font_count += 1
    End If
    Dim As String fontName = LCase(Trim(parserState.table_font_name))
    Dim As Integer isMonospaced = parserState.table_monospaced
    ' Writers often label Consolas and Courier as fnil. Recognize common
    ' fixed-pitch names while keeping font substitution independent of the OS.
    If InStr(fontName, "consolas") > 0 OrElse InStr(fontName, "courier") > 0 OrElse _
       InStr(fontName, "mono") > 0 OrElse InStr(fontName, "cascadia") > 0 OrElse _
       InStr(fontName, "terminal") > 0 OrElse InStr(fontName, "fixed") > 0 OrElse _
       InStr(fontName, "menlo") > 0 OrElse InStr(fontName, "lucida console") > 0 Then isMonospaced = -1
    d->fonts(fontIndex).number = parserState.table_font_number
    d->fonts(fontIndex).name = Trim(parserState.table_font_name)
    d->fonts(fontIndex).monospaced = isMonospaced
    parserState.table_font_name = ""
    parserState.table_font_number = -1
    Return -1
End Function

Private Sub rtfview_TableControl(ByRef parserState As RtfViewParserState, ByRef controlWord As String, ByVal numberValue As Integer, ByVal hasNumber As Integer)
    If parserState.ignorable_next <> 0 Then parserState.table_ignored = -1
    If parserState.table_ignored <> 0 Then Exit Sub
    If parserState.table_kind = RTFVIEW_TABLE_FONTS Then
        Select Case controlWord
        Case "f"
            If hasNumber <> 0 AndAlso numberValue >= 0 AndAlso numberValue <= 65535 Then
                parserState.table_font_number = numberValue
                parserState.table_font_name = ""
                parserState.table_monospaced = 0
            End If
        Case "fmodern"
            parserState.table_monospaced = -1
        Case "fprq"
            If hasNumber <> 0 AndAlso numberValue = 1 Then parserState.table_monospaced = -1
        End Select
    ElseIf parserState.table_kind = RTFVIEW_TABLE_COLORS Then
        If numberValue < 0 Then numberValue = 0
        If numberValue > 255 Then numberValue = 255
        Select Case controlWord
        Case "red": parserState.color_red = numberValue : parserState.color_has_components = -1
        Case "green": parserState.color_green = numberValue : parserState.color_has_components = -1
        Case "blue": parserState.color_blue = numberValue : parserState.color_has_components = -1
        End Select
    End If
End Sub

Private Function rtfview_TableCharacter(ByVal d As RtfViewData Ptr, ByRef parserState As RtfViewParserState, ByVal characterCode As Integer) As Integer
    If parserState.table_ignored <> 0 Then Return -1
    If parserState.table_kind = RTFVIEW_TABLE_FONTS Then
        If characterCode = 59 Then Return rtfview_StoreFont(d, parserState)
        If parserState.table_font_number < 0 OrElse characterCode < 32 Then Return -1
        If Len(parserState.table_font_name) >= RTFVIEW_MAX_FONT_NAME_BYTES Then
            d->parse_error = "The RTF document contains an overlong font name"
            Return 0
        End If
        parserState.table_font_name &= Chr(characterCode)
    ElseIf parserState.table_kind = RTFVIEW_TABLE_COLORS AndAlso characterCode = 59 Then
        If d->color_count >= RTFVIEW_MAX_COLORS Then
            d->parse_error = "The RTF document exceeds the color table limit"
            Return 0
        End If
        d->colors(d->color_count).color = RGB(parserState.color_red, parserState.color_green, parserState.color_blue)
        d->colors(d->color_count).automatic = IIf(parserState.color_has_components = 0, -1, 0)
        d->color_count += 1
        parserState.color_red = 0 : parserState.color_green = 0 : parserState.color_blue = 0
        parserState.color_has_components = 0
    End If
    Return -1
End Function

' -------------------------------------------------------------------------
' RTF syntax and character decoding
' -------------------------------------------------------------------------

Private Function rtfview_IsAlpha(ByVal characterCode As Integer) As Integer
    If (characterCode >= 65 AndAlso characterCode <= 90) OrElse _
       (characterCode >= 97 AndAlso characterCode <= 122) Then
        Return -1
    End If
    Return 0
End Function


Private Function rtfview_IsDigit(ByVal characterCode As Integer) As Integer
    If characterCode >= 48 AndAlso characterCode <= 57 Then Return -1
    Return 0
End Function


Private Function rtfview_HexValue(ByVal characterCode As Integer) As Integer
    If characterCode >= 48 AndAlso characterCode <= 57 Then _
        Return characterCode - 48
    If characterCode >= 65 AndAlso characterCode <= 70 Then _
        Return characterCode - 55
    If characterCode >= 97 AndAlso characterCode <= 102 Then _
        Return characterCode - 87
    Return -1
End Function


Private Function rtfview_DecodeCp1252( _
    ByVal characterCode As Integer _
) As Integer

    Select Case characterCode
    Case &H80: Return &H20AC
    Case &H82: Return &H201A
    Case &H83: Return &H192
    Case &H84: Return &H201E
    Case &H85: Return &H2026
    Case &H86: Return &H2020
    Case &H87: Return &H2021
    Case &H88: Return &H2C6
    Case &H89: Return &H2030
    Case &H8A: Return &H160
    Case &H8B: Return &H2039
    Case &H8C: Return &H152
    Case &H8E: Return &H17D
    Case &H91: Return &H2018
    Case &H92: Return &H2019
    Case &H93: Return &H201C
    Case &H94: Return &H201D
    Case &H95: Return &H2022
    Case &H96: Return &H2013
    Case &H97: Return &H2014
    Case &H98: Return &H2DC
    Case &H99: Return &H2122
    Case &H9A: Return &H161
    Case &H9B: Return &H203A
    Case &H9C: Return &H153
    Case &H9E: Return &H17E
    Case &H9F: Return &H178
    Case Else: Return characterCode
    End Select

End Function


Private Function rtfview_IsDestination(ByRef controlWord As String) As Integer
    Select Case controlWord
    Case "fonttbl", "colortbl", "stylesheet", "info", "pict", "object", _
         "header", "headerl", "headerr", "footer", "footerl", _
         "footerr", "annotation", "datastore", "xmlopen", "xmlattrname", _
         "xmlattrvalue", "listtable", "listoverridetable", "generator", _
         "filetbl", "revtbl", "rsidtbl", "themedata", _
         "colorschememapping", "latentstyles", "ftnsep", "ftnsepc", _
         "aftnsep", "aftnsepc", "nonshppict", "shppict", "fldinst"
        Return -1
    End Select
    Return 0
End Function


Private Function rtfview_DisplayCharacter( _
    ByVal codePoint As Integer _
) As String

    If codePoint < 32 OrElse codePoint = 127 Then Return ""
    If codePoint > &H10FFFF OrElse (codePoint >= &HD800 AndAlso codePoint <= &HDFFF) Then codePoint = &HFFFD
    If codePoint < &H80 Then Return Chr(codePoint)
    If codePoint < &H800 Then Return Chr(&HC0 Or (codePoint Shr 6), &H80 Or (codePoint And &H3F))
    If codePoint < &H10000 Then Return Chr(&HE0 Or (codePoint Shr 12), _
        &H80 Or ((codePoint Shr 6) And &H3F), &H80 Or (codePoint And &H3F))
    Return Chr(&HF0 Or (codePoint Shr 18), &H80 Or ((codePoint Shr 12) And &H3F), _
        &H80 Or ((codePoint Shr 6) And &H3F), &H80 Or (codePoint And &H3F))

End Function


Private Sub rtfview_SyncParagraph( _
    ByVal d As RtfViewData Ptr, ByRef parserState As RtfViewParserState _
)

    Dim As Integer paragraphIndex

    If d = 0 OrElse d->paragraph_count <= 0 Then Exit Sub
    paragraphIndex = d->paragraph_count - 1
    d->paragraphs(paragraphIndex).alignment = parserState.alignment
    d->paragraphs(paragraphIndex).left_indent = parserState.left_indent
    d->paragraphs(paragraphIndex).first_indent = parserState.first_indent
    d->paragraphs(paragraphIndex).right_indent = parserState.right_indent
    If d->paragraphs(paragraphIndex).run_count = 0 Then
        d->paragraphs(paragraphIndex).font_id = rtfview_ResolveFont(d, parserState)
        d->paragraphs(paragraphIndex).font_percent = rtfview_FontPercent( _
            d->paragraphs(paragraphIndex).font_id, parserState.font_halfpoints)
    End If

End Sub


Private Function rtfview_StartParagraph( _
    ByVal d As RtfViewData Ptr, ByRef parserState As RtfViewParserState _
) As Integer

    Dim As Integer paragraphIndex

    If d = 0 Then Return 0
    If d->paragraph_count >= RTFVIEW_MAX_PARAGRAPHS Then
        d->parse_error = "The RTF document exceeds the paragraph limit"
        Return 0
    End If

    paragraphIndex = d->paragraph_count
    d->paragraphs(paragraphIndex).first_run = d->run_count
    d->paragraphs(paragraphIndex).run_count = 0
    d->paragraphs(paragraphIndex).alignment = parserState.alignment
    d->paragraphs(paragraphIndex).left_indent = parserState.left_indent
    d->paragraphs(paragraphIndex).first_indent = parserState.first_indent
    d->paragraphs(paragraphIndex).right_indent = parserState.right_indent
    d->paragraphs(paragraphIndex).font_id = rtfview_ResolveFont(d, parserState)
    d->paragraphs(paragraphIndex).font_percent = rtfview_FontPercent( _
        d->paragraphs(paragraphIndex).font_id, parserState.font_halfpoints)
    d->paragraph_count += 1
    Return -1

End Function


Private Function rtfview_EnsureDisplayCapacity( _
    ByVal d As RtfViewData Ptr, ByVal additionalBytes As Integer _
) As Integer

    Dim As Integer requiredBytes
    Dim As Integer newCapacity

    If d = 0 OrElse additionalBytes < 0 Then Return 0
    requiredBytes = d->display_text_length + additionalBytes
    If requiredBytes > RTFVIEW_MAX_OUTPUT_BYTES Then
        d->parse_error = "The visible RTF text exceeds the output limit"
        Return 0
    End If
    If requiredBytes <= d->display_text_capacity Then Return -1

    newCapacity = d->display_text_capacity
    If newCapacity < 256 Then newCapacity = 256
    While newCapacity < requiredBytes
        If newCapacity > RTFVIEW_MAX_OUTPUT_BYTES \ 2 Then
            newCapacity = RTFVIEW_MAX_OUTPUT_BYTES
        Else
            newCapacity *= 2
        End If
        If newCapacity < requiredBytes AndAlso _
           newCapacity = RTFVIEW_MAX_OUTPUT_BYTES Then
            d->parse_error = "The visible RTF text exceeds the output limit"
            Return 0
        End If
    Wend

    d->display_text &= String( _
        newCapacity - d->display_text_capacity, Chr(0) _
    )
    d->display_text_capacity = newCapacity
    Return -1

End Function


Private Function rtfview_AppendCodePoint( _
    ByVal d As RtfViewData Ptr, ByRef parserState As RtfViewParserState, _
    ByVal codePoint As Integer _
) As Integer

    Dim As Integer paragraphIndex
    Dim As Integer runIndex
    Dim As Integer fontId
    Dim As Integer fontPercent
    Dim As Integer automaticColor = -1
    Dim As Integer continueRun
    Dim As Integer displayPosition
    Dim As Integer displayStart
    Dim As ULong runColor
    Dim As String displayText
    Dim As RtfViewRun Ptr runData

    If d = 0 OrElse d->parse_error <> "" Then Return 0
    If parserState.skip_destination <> 0 OrElse _
       parserState.hidden <> 0 Then Return -1
    If d->pending_surrogate <> 0 Then
        d->pending_surrogate = 0
        If rtfview_AppendCodePoint(d, parserState, &HFFFD) = 0 Then Return 0
    End If

    displayText = rtfview_DisplayCharacter(codePoint)
    If displayText = "" Then Return -1
    If d->paragraph_count <= 0 Then
        If rtfview_StartParagraph(d, parserState) = 0 Then Return 0
    End If

    paragraphIndex = d->paragraph_count - 1
    fontId = rtfview_ResolveFont(d, parserState)
    fontPercent = rtfview_FontPercent(fontId, parserState.font_halfpoints)
    rtfview_SyncParagraph(d, parserState)

    runColor = 0
    If parserState.color_index >= 0 AndAlso parserState.color_index < d->color_count Then
        runColor = d->colors(parserState.color_index).color
        automaticColor = d->colors(parserState.color_index).automatic
    End If

    continueRun = 0
    If d->paragraphs(paragraphIndex).run_count > 0 Then
        runIndex = d->paragraphs(paragraphIndex).first_run + _
            d->paragraphs(paragraphIndex).run_count - 1
        runData = @d->runs(runIndex)
        If runData->font_id = fontId AndAlso _
           runData->font_percent = fontPercent AndAlso _
           runData->bold = parserState.bold AndAlso runData->italic = parserState.italic AndAlso _
           runData->automatic_color = automaticColor AndAlso _
           runData->color = runColor AndAlso _
           runData->underline = parserState.underline Then
            continueRun = -1
        End If
    End If

    If continueRun = 0 AndAlso d->run_count >= RTFVIEW_MAX_RUNS Then
        d->parse_error = "The RTF document exceeds the character-format run limit"
        Return 0
    End If

    If rtfview_EnsureDisplayCapacity(d, Len(displayText)) = 0 Then _
        Return 0
    displayStart = d->display_text_length
    For displayPosition = 1 To Len(displayText)
        d->display_text[d->display_text_length] = _
            Asc(Mid(displayText, displayPosition, 1))
        d->display_text_length += 1
    Next displayPosition

    If continueRun <> 0 Then
        d->runs(runIndex).byte_length += Len(displayText)
    Else
        runIndex = d->run_count
        d->runs(runIndex).start_byte = displayStart
        d->runs(runIndex).byte_length = Len(displayText)
        d->runs(runIndex).color = runColor
        d->runs(runIndex).font_id = fontId
        d->runs(runIndex).font_percent = fontPercent
        d->runs(runIndex).bold = parserState.bold
        d->runs(runIndex).italic = parserState.italic
        d->runs(runIndex).automatic_color = automaticColor
        d->runs(runIndex).underline = parserState.underline
        d->run_count += 1
        d->paragraphs(paragraphIndex).run_count += 1
    End If
    Return -1

End Function

Private Function rtfview_AppendUnicode(ByVal d As RtfViewData Ptr, ByRef parserState As RtfViewParserState, ByVal codeUnit As Integer) As Integer
    ' The RTF u control stores signed UTF-16 units, including surrogate pairs.
    ' UTF-8 output only receives complete scalars; broken pairs stay visible.
    If codeUnit >= &HD800 AndAlso codeUnit <= &HDBFF Then
        If d->pending_surrogate <> 0 Then
            d->pending_surrogate = 0
            If rtfview_AppendCodePoint(d, parserState, &HFFFD) = 0 Then Return 0
        End If
        d->pending_surrogate = codeUnit
        Return -1
    End If
    If codeUnit >= &HDC00 AndAlso codeUnit <= &HDFFF Then
        If d->pending_surrogate <> 0 Then
            Dim As Integer codePoint = &H10000 + (d->pending_surrogate - &HD800) * 1024 + codeUnit - &HDC00
            d->pending_surrogate = 0
            Return rtfview_AppendCodePoint(d, parserState, codePoint)
        End If
        codeUnit = &HFFFD
    End If
    Return rtfview_AppendCodePoint(d, parserState, codeUnit)
End Function


Private Function rtfview_AppendTab( _
    ByVal d As RtfViewData Ptr, ByRef parserState As RtfViewParserState _
) As Integer

    For spaceIndex As Integer = 1 To 4
        If rtfview_AppendCodePoint(d, parserState, 32) = 0 Then Return 0
    Next spaceIndex
    Return -1

End Function


Private Sub rtfview_SetError( _
    ByVal d As RtfViewData Ptr, ByRef message As String _
)

    If d = 0 Then Exit Sub
    If d->parse_error = "" Then d->parse_error = message

End Sub


Private Function rtfview_ParseRtf( _
    ByVal d As RtfViewData Ptr, ByRef rtfText As Const String _
) As Integer

    Dim As RtfViewParserState parserState
    Dim As RtfViewParserState groupStack( _
        0 To RTFVIEW_MAX_GROUP_DEPTH - 1 _
    )
    Dim As Integer depth
    Dim As Integer bytePosition = 1
    Dim As Integer inputLength = Len(rtfText)
    Dim As Integer characterCode
    Dim As Integer wordStart
    Dim As Integer wordLength
    Dim As Integer numberValue
    Dim As Integer numberSign
    Dim As Integer hasNumber
    Dim As Integer hexHigh
    Dim As Integer hexLow
    Dim As Integer decodedCodePoint
    Dim As Integer signedUnicode
    Dim As Integer controlSymbol
    Dim As String controlWord
    Dim As String errorText

    parserState.unicode_fallback = 1
    parserState.font_halfpoints = 24
    parserState.resolved_font_id = -1
    parserState.table_font_number = -1
    If rtfview_StartParagraph(d, parserState) = 0 Then Return 0

    While bytePosition <= inputLength
        characterCode = Asc(Mid(rtfText, bytePosition, 1))

        Select Case characterCode
        Case 123
            If depth >= RTFVIEW_MAX_GROUP_DEPTH Then
                errorText = "The RTF document exceeds the group nesting limit"
                rtfview_SetError(d, errorText)
                Return 0
            End If
            groupStack(depth) = parserState
            depth += 1
            bytePosition += 1

        Case 125
            If depth <= 0 Then
                errorText = "The RTF document has an unmatched closing brace"
                rtfview_SetError(d, errorText)
                Return 0
            End If
            Dim As Integer closedTableKind = parserState.table_kind
            If depth = 1 AndAlso d->pending_surrogate <> 0 AndAlso parserState.skip_destination = 0 Then
                d->pending_surrogate = 0
                If rtfview_AppendCodePoint(d, parserState, &HFFFD) = 0 Then Return 0
            End If
            depth -= 1
            parserState = groupStack(depth)
            If closedTableKind <> 0 AndAlso parserState.table_kind = 0 Then parserState.resolved_font_id = -1
            bytePosition += 1
            If depth > 0 Then rtfview_SyncParagraph(d, parserState)

        Case 92
            bytePosition += 1
            If bytePosition > inputLength Then Exit While
            controlSymbol = Asc(Mid(rtfText, bytePosition, 1))

            If rtfview_IsAlpha(controlSymbol) <> 0 Then
                wordStart = bytePosition
                While bytePosition <= inputLength AndAlso _
                      rtfview_IsAlpha(Asc(Mid(rtfText, bytePosition, 1))) <> 0
                    bytePosition += 1
                Wend
                wordLength = bytePosition - wordStart
                controlWord = LCase(Mid(rtfText, wordStart, wordLength))

                numberValue = 0
                numberSign = 1
                hasNumber = 0
                If bytePosition <= inputLength AndAlso _
                   Asc(Mid(rtfText, bytePosition, 1)) = 45 Then
                    numberSign = -1
                    bytePosition += 1
                End If
                While bytePosition <= inputLength AndAlso _
                      rtfview_IsDigit(Asc(Mid(rtfText, bytePosition, 1))) <> 0
                    hasNumber = -1
                    If numberValue < 1000000 Then
                        numberValue = numberValue * 10 + _
                            Asc(Mid(rtfText, bytePosition, 1)) - 48
                    End If
                    bytePosition += 1
                Wend
                numberValue *= numberSign

                If bytePosition <= inputLength AndAlso _
                   Asc(Mid(rtfText, bytePosition, 1)) = 32 Then _
                    bytePosition += 1

                If controlWord = "bin" AndAlso hasNumber <> 0 Then
                    ' Binary destinations may contain braces and backslashes.
                    ' Consume their bounded byte count before interpreting syntax.
                    If numberValue < 0 OrElse numberValue > inputLength - bytePosition + 1 Then
                        rtfview_SetError(d, "The RTF document has an invalid binary byte count")
                        Return 0
                    End If
                    bytePosition += numberValue
                    parserState.ignorable_next = 0
                    Continue While
                End If
                If parserState.skip_destination = 0 Then
                    If controlWord = "fonttbl" Then
                        parserState.table_kind = RTFVIEW_TABLE_FONTS
                        parserState.skip_destination = -1
                    ElseIf controlWord = "colortbl" Then
                        parserState.table_kind = RTFVIEW_TABLE_COLORS
                        parserState.skip_destination = -1
                    End If
                End If
                If parserState.table_kind <> 0 Then
                    rtfview_TableControl(parserState, controlWord, numberValue, hasNumber)
                ElseIf parserState.skip_destination = 0 Then
                    If parserState.ignorable_next <> 0 OrElse _
                       rtfview_IsDestination(controlWord) <> 0 Then
                        parserState.skip_destination = -1
                    Else
                        Select Case controlWord
                        Case "b"
                            parserState.bold = IIf( _
                                hasNumber <> 0 AndAlso numberValue = 0, 0, -1 _
                            )
                            parserState.resolved_font_id = -1
                        Case "i"
                            parserState.italic = IIf(hasNumber <> 0 AndAlso numberValue = 0, 0, -1)
                        Case "deff"
                            If hasNumber <> 0 AndAlso numberValue >= 0 Then
                                d->default_font_number = numberValue
                                parserState.font_number = numberValue
                                parserState.resolved_font_id = -1
                            End If
                        Case "f"
                            If hasNumber <> 0 AndAlso numberValue >= 0 Then
                                parserState.font_number = numberValue
                                parserState.resolved_font_id = -1
                            End If
                        Case "fs"
                            If hasNumber <> 0 Then
                                If numberValue < RTFVIEW_MIN_FONT_HALFPOINTS Then numberValue = RTFVIEW_MIN_FONT_HALFPOINTS
                                If numberValue > RTFVIEW_MAX_FONT_HALFPOINTS Then numberValue = RTFVIEW_MAX_FONT_HALFPOINTS
                                parserState.font_halfpoints = numberValue
                            End If
                        Case "ul"
                            parserState.underline = IIf( _
                                hasNumber <> 0 AndAlso numberValue = 0, 0, -1 _
                            )
                        Case "ulnone"
                            parserState.underline = 0
                        Case "v"
                            parserState.hidden = IIf( _
                                hasNumber <> 0 AndAlso numberValue = 0, 0, -1 _
                            )
                        Case "cf"
                            parserState.color_index = numberValue
                            If parserState.color_index < 0 Then _
                                parserState.color_index = 0
                        Case "uc"
                            parserState.unicode_fallback = numberValue
                            If parserState.unicode_fallback < 0 Then _
                                parserState.unicode_fallback = 0
                            If parserState.unicode_fallback > 16 Then _
                                parserState.unicode_fallback = 16
                        Case "u"
                            If hasNumber <> 0 Then
                                signedUnicode = numberValue
                                If signedUnicode < 0 Then _
                                    signedUnicode += 65536
                                If signedUnicode < 0 OrElse signedUnicode > 65535 Then signedUnicode = &HFFFD
                                If rtfview_AppendUnicode( _
                                    d, parserState, signedUnicode _
                                ) = 0 Then Return 0
                                parserState.unicode_fallback_count = _
                                    parserState.unicode_fallback
                            End If
                        Case "par", "line"
                            If rtfview_StartParagraph(d, parserState) = 0 _
                                Then Return 0
                        Case "tab"
                            If parserState.unicode_fallback_count > 0 Then
                                parserState.unicode_fallback_count -= 1
                            Elseif rtfview_AppendTab(d, parserState) = 0 Then
                                Return 0
                            End If
                        Case "emdash"
                            If parserState.unicode_fallback_count > 0 Then
                                parserState.unicode_fallback_count -= 1
                            Elseif rtfview_AppendCodePoint( _
                                d, parserState, &H2014 _
                            ) = 0 Then
                                Return 0
                            End If
                        Case "endash"
                            If parserState.unicode_fallback_count > 0 Then
                                parserState.unicode_fallback_count -= 1
                            Elseif rtfview_AppendCodePoint( _
                                d, parserState, &H2013 _
                            ) = 0 Then
                                Return 0
                            End If
                        Case "bullet"
                            If parserState.unicode_fallback_count > 0 Then
                                parserState.unicode_fallback_count -= 1
                            Elseif rtfview_AppendCodePoint( _
                                d, parserState, &H2022 _
                            ) = 0 Then
                                Return 0
                            End If
                        Case "lquote"
                            If parserState.unicode_fallback_count > 0 Then
                                parserState.unicode_fallback_count -= 1
                            Elseif rtfview_AppendCodePoint( _
                                d, parserState, &H2018 _
                            ) = 0 Then
                                Return 0
                            End If
                        Case "rquote"
                            If parserState.unicode_fallback_count > 0 Then
                                parserState.unicode_fallback_count -= 1
                            Elseif rtfview_AppendCodePoint( _
                                d, parserState, &H2019 _
                            ) = 0 Then
                                Return 0
                            End If
                        Case "ldblquote"
                            If parserState.unicode_fallback_count > 0 Then
                                parserState.unicode_fallback_count -= 1
                            Elseif rtfview_AppendCodePoint( _
                                d, parserState, &H201C _
                            ) = 0 Then
                                Return 0
                            End If
                        Case "rdblquote"
                            If parserState.unicode_fallback_count > 0 Then
                                parserState.unicode_fallback_count -= 1
                            Elseif rtfview_AppendCodePoint( _
                                d, parserState, &H201D _
                            ) = 0 Then
                                Return 0
                            End If
                        Case "pard"
                            parserState.alignment = BACKEND_ALIGN_LEFT
                            parserState.left_indent = 0
                            parserState.first_indent = 0
                            parserState.right_indent = 0
                            rtfview_SyncParagraph(d, parserState)
                        Case "ql"
                            parserState.alignment = BACKEND_ALIGN_LEFT
                            rtfview_SyncParagraph(d, parserState)
                        Case "qc"
                            parserState.alignment = BACKEND_ALIGN_CENTER
                            rtfview_SyncParagraph(d, parserState)
                        Case "qr"
                            parserState.alignment = BACKEND_ALIGN_RIGHT
                            rtfview_SyncParagraph(d, parserState)
                        Case "qj"
                            parserState.alignment = BACKEND_ALIGN_LEFT
                            rtfview_SyncParagraph(d, parserState)
                        Case "li"
                            If hasNumber <> 0 Then _
                                parserState.left_indent = numberValue
                            rtfview_SyncParagraph(d, parserState)
                        Case "fi"
                            If hasNumber <> 0 Then _
                                parserState.first_indent = numberValue
                            rtfview_SyncParagraph(d, parserState)
                        Case "ri"
                            If hasNumber <> 0 Then _
                                parserState.right_indent = numberValue
                            rtfview_SyncParagraph(d, parserState)
                        Case "plain"
                            parserState.bold = 0
                            parserState.italic = 0
                            parserState.underline = 0
                            parserState.hidden = 0
                            parserState.color_index = 0
                            parserState.font_number = d->default_font_number
                            parserState.font_halfpoints = 24
                            parserState.resolved_font_id = -1
                        End Select
                    End If
                End If

                parserState.ignorable_next = 0
            Else
                Select Case controlSymbol
                Case 39
                    bytePosition += 1
                    If bytePosition + 1 > inputLength Then
                        errorText = "The RTF document ends inside a hex escape"
                        rtfview_SetError(d, errorText)
                        Return 0
                    End If
                    hexHigh = rtfview_HexValue( _
                        Asc(Mid(rtfText, bytePosition, 1)) _
                    )
                    hexLow = rtfview_HexValue( _
                        Asc(Mid(rtfText, bytePosition + 1, 1)) _
                    )
                    If hexHigh < 0 OrElse hexLow < 0 Then
                        errorText = "The RTF document contains an invalid hex escape"
                        rtfview_SetError(d, errorText)
                        Return 0
                    End If
                    decodedCodePoint = rtfview_DecodeCp1252( _
                        hexHigh * 16 + hexLow _
                    )
                    bytePosition += 2
                    If parserState.unicode_fallback_count > 0 Then
                        parserState.unicode_fallback_count -= 1
                    Elseif parserState.skip_destination = 0 Then
                        If rtfview_AppendCodePoint( _
                            d, parserState, decodedCodePoint _
                        ) = 0 Then Return 0
                    End If
                    parserState.ignorable_next = 0

                Case 92, 123, 125
                    If parserState.unicode_fallback_count > 0 Then
                        parserState.unicode_fallback_count -= 1
                    Elseif parserState.skip_destination = 0 Then
                        If rtfview_AppendCodePoint( _
                            d, parserState, controlSymbol _
                        ) = 0 Then Return 0
                    End If
                    bytePosition += 1
                    parserState.ignorable_next = 0

                Case 42
                    parserState.ignorable_next = -1
                    bytePosition += 1

                Case 126
                    If parserState.unicode_fallback_count > 0 Then
                        parserState.unicode_fallback_count -= 1
                    Elseif parserState.skip_destination = 0 Then
                        If rtfview_AppendCodePoint(d, parserState, 32) = 0 _
                            Then Return 0
                    End If
                    bytePosition += 1
                    parserState.ignorable_next = 0

                Case 95
                    If parserState.unicode_fallback_count > 0 Then
                        parserState.unicode_fallback_count -= 1
                    Elseif parserState.skip_destination = 0 Then
                        If rtfview_AppendCodePoint(d, parserState, 45) = 0 _
                            Then Return 0
                    End If
                    bytePosition += 1
                    parserState.ignorable_next = 0

                Case 45
                    bytePosition += 1
                    parserState.ignorable_next = 0

                Case Else
                    bytePosition += 1
                    parserState.ignorable_next = 0
                End Select
            End If

        Case 13, 10
            bytePosition += 1

        Case Else
            If parserState.table_kind <> 0 Then
                If rtfview_TableCharacter(d, parserState, characterCode) = 0 Then Return 0
                bytePosition += 1
            ElseIf parserState.unicode_fallback_count > 0 Then
                parserState.unicode_fallback_count -= 1
                bytePosition += 1
            Elseif parserState.skip_destination = 0 Then
                If characterCode = 0 Then
                    bytePosition += 1
                Else
                    If characterCode >= &H80 AndAlso _
                       characterCode <= &H9F Then
                        characterCode = _
                            rtfview_DecodeCp1252(characterCode)
                    End If
                    If rtfview_AppendCodePoint( _
                        d, parserState, characterCode _
                    ) = 0 Then Return 0
                    bytePosition += 1
                End If
            Else
                bytePosition += 1
            End If
            parserState.ignorable_next = 0
        End Select
    Wend

    If depth <> 0 Then
        errorText = "The RTF document has an unmatched opening brace"
        rtfview_SetError(d, errorText)
        Return 0
    End If

    Return -1

End Function


Private Function rtfview_ParsePlainText( _
    ByVal d As RtfViewData Ptr, ByRef plainText As Const String _
) As Integer

    Dim As RtfViewParserState parserState
    Dim As Integer characterCode
    Dim As Integer textLength = Len(plainText)
    Dim As Integer bytePosition

    parserState.unicode_fallback = 1
    parserState.font_halfpoints = 20
    parserState.resolved_font_id = -1
    If rtfview_StartParagraph(d, parserState) = 0 Then Return 0

    While bytePosition < textLength
        characterCode = backend_ReadUTF8Codepoint(plainText, bytePosition)
        Select Case characterCode
        Case 13
            If bytePosition < textLength AndAlso plainText[bytePosition] = 10 Then _
                bytePosition += 1
            If rtfview_StartParagraph(d, parserState) = 0 Then Return 0
        Case 10
            If rtfview_StartParagraph(d, parserState) = 0 Then Return 0
        Case 9
            If rtfview_AppendTab(d, parserState) = 0 Then Return 0
        Case 0
            ' File readers may retain the conventional trailing NUL byte.
        Case Else
            If rtfview_AppendCodePoint(d, parserState, characterCode) = 0 _
                Then Return 0
        End Select
    Wend

    Return -1

End Function


' -------------------------------------------------------------------------
' Font metrics, wrapping, and vertical layout
' -------------------------------------------------------------------------

Private Type RtfViewFontMetric
    As Integer font_id, percent
    As Integer widths(32 To 126)
End Type

Private Function rtfview_MeasureCharacter( _
    ByVal d As RtfViewData Ptr, ByVal runData As RtfViewRun Ptr, _
    ByVal bytePosition As Integer, ByRef nextPosition As Integer, _
    ByRef codePoint As Integer, metrics() As RtfViewFontMetric, _
    ByRef metricCount As Integer _
) As Integer
    nextPosition = bytePosition
    codePoint = backend_ReadUTF8Codepoint(d->display_text, nextPosition)
    If nextPosition <= bytePosition OrElse nextPosition > d->display_text_length Then
        nextPosition = bytePosition + 1
        codePoint = Asc("?")
    End If

    If codePoint >= 32 AndAlso codePoint <= 126 Then
        Dim As Integer metricIndex = -1
        For index As Integer = 0 To metricCount - 1
            If metrics(index).font_id = runData->font_id AndAlso metrics(index).percent = runData->font_percent Then
                metricIndex = index
                Exit For
            End If
        Next index
        If metricIndex < 0 AndAlso metricCount < RTFVIEW_METRIC_CACHE_COUNT Then
            metricIndex = metricCount
            metricCount += 1
            metrics(metricIndex).font_id = runData->font_id
            metrics(metricIndex).percent = runData->font_percent
            For characterCode As Integer = 32 To 126
                metrics(metricIndex).widths(characterCode) = backend_GetTextWidthFontPercent( _
                    Chr(characterCode), runData->font_id, runData->font_percent)
            Next characterCode
        End If
        If metricIndex >= 0 Then Return metrics(metricIndex).widths(codePoint)
    End If

    Return backend_GetTextWidthFontPercent( _
        Mid(d->display_text, bytePosition + 1, nextPosition - bytePosition), _
        runData->font_id, runData->font_percent)
End Function

Private Sub rtfview_LineMetrics(ByVal lineData As RtfViewLine Ptr, ByVal fontId As Integer, ByVal percent As Integer)
    Dim As Integer ascent = (backend_GetFontAscent(fontId) * percent + 50) \ 100
    Dim As Integer height = backend_GetTextHeightFontPercent(fontId, percent)
    Dim As Integer descent = height - ascent
    If descent < 0 Then descent = 0
    If ascent > lineData->ascent Then lineData->ascent = ascent
    If descent > lineData->descent Then lineData->descent = descent
    lineData->height = lineData->ascent + lineData->descent
    If lineData->height < 1 Then lineData->height = 1
End Sub

Private Sub rtfview_AddLine( _
    ByVal d As RtfViewData Ptr, ByRef paragraph As RtfViewParagraph, _
    ByVal leftIndent As Integer, ByVal rightIndent As Integer _
)
    If d->visual_line_count >= RTFVIEW_MAX_LINES Then
        d->parse_error = "The RTF document exceeds the visual line limit"
        Exit Sub
    End If
    Dim As Integer lineIndex = d->visual_line_count
    Dim As RtfViewLine Ptr lineData = @d->lines(lineIndex)
    lineData->first_fragment = d->line_fragment_count
    lineData->fragment_count = 0
    lineData->alignment = paragraph.alignment
    lineData->left_indent = leftIndent
    lineData->right_indent = rightIndent
    lineData->text_width = 0
    lineData->ascent = 0 : lineData->descent = 0 : lineData->height = 0
    rtfview_LineMetrics(lineData, paragraph.font_id, paragraph.font_percent)
    d->visual_line_count += 1
End Sub

Private Function rtfview_BuildLayout( _
    ByVal w As Widget Ptr, ByVal d As RtfViewData Ptr _
) As Integer
    Dim As RtfViewFontMetric metrics(0 To RTFVIEW_METRIC_CACHE_COUNT - 1)
    Dim As Integer metricCount
    Dim As Integer contentWidth, availableWidth
    Dim As Integer leftIndent, firstIndent, rightIndent, lineIndent
    Dim As Integer lineIndex, bytePosition, nextPosition, codePoint, charWidth
    Dim As Integer wordWidth, wordPosition, wordNextPosition, wordCodePoint
    Dim As Integer atWordStart, fragmentIndex
    Dim As RtfViewParagraph Ptr paragraphData
    Dim As RtfViewRun Ptr runData, wordRunData
    Dim As RtfViewLine Ptr lineData
    Dim As RtfViewLineFragment Ptr fragmentData

    If w = 0 OrElse d = 0 OrElse d->parse_error <> "" Then Return 0
    d->visual_line_count = 0 : d->line_fragment_count = 0
    d->document_height = 0
    d->layout_width = w->w
    contentWidth = w->w - RTFVIEW_SCROLLBAR_WIDTH - d->content_left - d->content_right
    If contentWidth < 1 Then contentWidth = 1

    For paragraphIndex As Integer = 0 To d->paragraph_count - 1
        paragraphData = @d->paragraphs(paragraphIndex)
        leftIndent = paragraphData->left_indent \ RTFVIEW_TWIPS_PER_PIXEL
        firstIndent = paragraphData->first_indent \ RTFVIEW_TWIPS_PER_PIXEL
        rightIndent = paragraphData->right_indent \ RTFVIEW_TWIPS_PER_PIXEL
        If leftIndent < 0 Then leftIndent = 0
        If leftIndent >= contentWidth Then leftIndent = contentWidth - 1
        If rightIndent < 0 Then rightIndent = 0
        If rightIndent >= contentWidth Then rightIndent = contentWidth - 1
        lineIndent = leftIndent + firstIndent
        If lineIndent < 0 Then lineIndent = 0
        If lineIndent >= contentWidth Then lineIndent = contentWidth - 1
        rtfview_AddLine(d, paragraphData[0], lineIndent, rightIndent)
        If d->parse_error <> "" Then Return 0
        lineIndex = d->visual_line_count - 1
        availableWidth = contentWidth - lineIndent - rightIndent
        If availableWidth < 1 Then availableWidth = 1
        atWordStart = -1

        For runOffset As Integer = 0 To paragraphData->run_count - 1
            Dim As Integer runIndex = paragraphData->first_run + runOffset
            runData = @d->runs(runIndex)
            bytePosition = runData->start_byte
            Dim As Integer runEnd = runData->start_byte + runData->byte_length
            While bytePosition < runEnd
                charWidth = rtfview_MeasureCharacter(d, runData, bytePosition, nextPosition, codePoint, metrics(), metricCount)
                lineData = @d->lines(lineIndex)
                If codePoint <> 32 AndAlso atWordStart <> 0 Then
                    wordWidth = 0
                    For wordRunOffset As Integer = runOffset To paragraphData->run_count - 1
                        wordRunData = @d->runs(paragraphData->first_run + wordRunOffset)
                        wordPosition = wordRunData->start_byte
                        If wordRunOffset = runOffset Then wordPosition = bytePosition
                        While wordPosition < wordRunData->start_byte + wordRunData->byte_length
                            Dim As Integer glyphWidth = rtfview_MeasureCharacter(d, wordRunData, wordPosition, _
                                wordNextPosition, wordCodePoint, metrics(), metricCount)
                            If wordCodePoint = 32 Then Exit While
                            wordWidth += glyphWidth
                            wordPosition = wordNextPosition
                            ' A word wider than the view wraps by scalar below.
                            ' Stop counting it here rather than summing unbounded widths.
                            If wordWidth > availableWidth Then Exit While
                        Wend
                        If wordWidth > availableWidth OrElse wordPosition < wordRunData->start_byte + wordRunData->byte_length Then Exit For
                    Next wordRunOffset
                    If lineData->fragment_count > 0 AndAlso lineData->text_width + wordWidth > availableWidth Then
                        rtfview_AddLine(d, paragraphData[0], leftIndent, rightIndent)
                        If d->parse_error <> "" Then Return 0
                        lineIndex = d->visual_line_count - 1
                        availableWidth = contentWidth - leftIndent - rightIndent
                        If availableWidth < 1 Then availableWidth = 1
                        lineData = @d->lines(lineIndex)
                    End If
                    atWordStart = 0
                ElseIf codePoint = 32 Then
                    atWordStart = -1
                End If

                If lineData->fragment_count > 0 AndAlso lineData->text_width + charWidth > availableWidth Then
                    rtfview_AddLine(d, paragraphData[0], leftIndent, rightIndent)
                    If d->parse_error <> "" Then Return 0
                    lineIndex = d->visual_line_count - 1
                    availableWidth = contentWidth - leftIndent - rightIndent
                    If availableWidth < 1 Then availableWidth = 1
                    lineData = @d->lines(lineIndex)
                End If

                fragmentData = 0
                If lineData->fragment_count > 0 Then
                    fragmentIndex = lineData->first_fragment + lineData->fragment_count - 1
                    fragmentData = @d->fragments(fragmentIndex)
                    If fragmentData->run_index <> runIndex OrElse _
                       fragmentData->start_byte + fragmentData->byte_length <> bytePosition Then fragmentData = 0
                End If
                If fragmentData = 0 Then
                    If d->line_fragment_count >= RTFVIEW_MAX_LINE_FRAGMENTS Then
                        d->parse_error = "The RTF document exceeds the line fragment limit"
                        Return 0
                    End If
                    fragmentData = @d->fragments(d->line_fragment_count)
                    fragmentData->run_index = runIndex
                    fragmentData->start_byte = bytePosition
                    fragmentData->byte_length = 0
                    d->line_fragment_count += 1
                    lineData->fragment_count += 1
                End If
                ' Append complete UTF-8 scalars. Formatting and wrapping can
                ' never split a continuation byte into a different line.
                fragmentData->byte_length += nextPosition - bytePosition
                lineData->text_width += charWidth
                rtfview_LineMetrics(lineData, runData->font_id, runData->font_percent)
                bytePosition = nextPosition
            Wend
        Next runOffset
    Next paragraphIndex

    If d->visual_line_count = 0 Then
        rtfview_AddLine(d, d->paragraphs(0), 0, 0)
        If d->parse_error <> "" Then Return 0
    End If
    For index As Integer = 0 To d->visual_line_count - 1
        d->lines(index).top = d->document_height
        d->document_height += d->lines(index).height
    Next index
    d->layout_dirty = 0
    Return -1
End Function

Private Sub rtfview_ClampScroll(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As RtfViewData Ptr d = w->data
    Dim As Integer contentHeight = w->h - d->content_top - d->content_bottom
    If contentHeight < 1 Then contentHeight = 1
    Dim As Integer maximumScroll = d->document_height - contentHeight
    If maximumScroll < 0 Then maximumScroll = 0

    ' scroll_top remains a line index for existing callers. The actual
    ' scrollbar uses pixels so a large heading and short final line can share
    ' the last page without an unreachable tail or a mostly blank viewport.
    If d->scroll_top <> d->last_scroll_top AndAlso d->visual_line_count > 0 Then
        If d->scroll_top < 0 Then d->scroll_top = 0
        If d->scroll_top >= d->visual_line_count Then d->scroll_top = d->visual_line_count - 1
        d->scroll_offset = d->lines(d->scroll_top).top
    End If
    If d->scroll_offset < 0 Then d->scroll_offset = 0
    If d->scroll_offset > maximumScroll Then d->scroll_offset = maximumScroll
    d->scroll_top = 0
    While d->scroll_top + 1 < d->visual_line_count
        If d->lines(d->scroll_top + 1).top > d->scroll_offset Then Exit While
        d->scroll_top += 1
    Wend
    d->last_scroll_top = d->scroll_top

    If d->scrollbar <> 0 AndAlso d->scrollbar->data <> 0 Then
        Dim As ScrollBarData Ptr scrollData = d->scrollbar->data
        scrollData->max_val = maximumScroll
        scrollData->page_size = contentHeight
        scrollData->value = d->scroll_offset
        d->scrollbar->visible = IIf(maximumScroll > 0, -1, 0)
    End If
End Sub


Sub rtfview_Update(ByVal w As Widget Ptr)

    Dim As RtfViewData Ptr d
    Dim As Integer mouseX
    Dim As Integer mouseY
    Dim As Integer wheelDelta

    If w = 0 OrElse w->data = 0 Then Exit Sub
    d = Cast(RtfViewData Ptr, w->data)
    If d->layout_dirty <> 0 OrElse d->layout_width <> w->w Then
        If rtfview_BuildLayout(w, d) = 0 Then Exit Sub
    End If

    mouseX = input_MouseX()
    mouseY = input_MouseY()
    wheelDelta = input_MouseWheel()
    If wheelDelta <> 0 AndAlso _
       mouseX >= w->ax AndAlso _
       mouseX < w->ax + w->w - RTFVIEW_SCROLLBAR_WIDTH AndAlso _
       mouseY >= w->ay AndAlso mouseY < w->ay + w->h Then
        Dim As Integer lineHeight = 16
        If d->visual_line_count > 0 Then lineHeight = d->lines(d->scroll_top).height
        d->scroll_offset -= wheelDelta * RTFVIEW_WHEEL_LINES * lineHeight
        rtfview_ClampScroll(w)
    End If

    If d->scrollbar <> 0 Then
        d->scrollbar->ax = w->ax + w->w - RTFVIEW_SCROLLBAR_WIDTH
        d->scrollbar->ay = w->ay
        d->scrollbar->w = RTFVIEW_SCROLLBAR_WIDTH
        d->scrollbar->h = w->h
        rtfview_ClampScroll(w)
        d->scrollbar->update(d->scrollbar)
        d->scroll_offset = Cast( _
            ScrollBarData Ptr, d->scrollbar->data _
        )->value
        rtfview_ClampScroll(w)
    End If

End Sub


Sub rtfview_Render(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As RtfViewData Ptr d = w->data
    If d->layout_dirty <> 0 OrElse d->layout_width <> w->w Then
        If rtfview_BuildLayout(w, d) = 0 Then
            backend_Rect(w->ax, w->ay, w->w, w->h, theme_GetColor(GUI_COLOR_WIDGET_BG), 1)
            backend_SetClip(w->ax + 2, w->ay + 2, w->w - 4, w->h - 4)
            backend_Print(w->ax + RTFVIEW_CONTENT_INSET, w->ay + RTFVIEW_CONTENT_INSET, _
                theme_GetColor(GUI_COLOR_TEXT), d->parse_error)
            backend_ResetClip
            Exit Sub
        End If
    End If
    rtfview_ClampScroll(w)
    backend_Rect(w->ax, w->ay, w->w, w->h, theme_GetColor(GUI_COLOR_WIDGET_BG), 1)
    backend_Rect(w->ax, w->ay, w->w, w->h, theme_GetColor(GUI_COLOR_BORDER), 0)
    Dim As Integer clipWidth = w->w - RTFVIEW_SCROLLBAR_WIDTH - 2
    If clipWidth < 1 OrElse w->h <= d->content_top + d->content_bottom Then Exit Sub
    backend_SetClip(w->ax + 1, w->ay + d->content_top, clipWidth, w->h - d->content_top - d->content_bottom)
    Dim As Integer contentWidth = w->w - RTFVIEW_SCROLLBAR_WIDTH - d->content_left - d->content_right
    If contentWidth < 1 Then contentWidth = 1

    For lineIndex As Integer = d->scroll_top To d->visual_line_count - 1
        Dim As RtfViewLine Ptr lineData = @d->lines(lineIndex)
        Dim As Integer lineY = w->ay + d->content_top + lineData->top - d->scroll_offset
        If lineY >= w->ay + w->h - d->content_bottom Then Exit For
        Dim As Integer availableWidth = contentWidth - lineData->left_indent - lineData->right_indent
        If availableWidth < 1 Then availableWidth = 1
        Dim As Integer textX = w->ax + d->content_left + lineData->left_indent
        If lineData->alignment = BACKEND_ALIGN_CENTER Then
            textX += (availableWidth - lineData->text_width) \ 2
        ElseIf lineData->alignment = BACKEND_ALIGN_RIGHT Then
            textX += availableWidth - lineData->text_width
        End If

        For fragmentOffset As Integer = 0 To lineData->fragment_count - 1
            Dim As RtfViewLineFragment Ptr fragmentData = @d->fragments(lineData->first_fragment + fragmentOffset)
            Dim As RtfViewRun Ptr runData = @d->runs(fragmentData->run_index)
            Dim As String fragmentText = Mid(d->display_text, fragmentData->start_byte + 1, fragmentData->byte_length)
            Dim As ULong textColor = runData->color
            If runData->automatic_color <> 0 Then textColor = theme_GetColor(GUI_COLOR_TEXT)
            Dim As Integer ascent = (backend_GetFontAscent(runData->font_id) * runData->font_percent + 50) \ 100
            Dim As Integer textY = lineY + lineData->ascent - ascent
            If runData->italic <> 0 Then
                backend_PrintItalicFontPercent(textX, textY, textColor, fragmentText, runData->font_id, runData->font_percent)
            Else
                backend_PrintFontPercent(textX, textY, textColor, fragmentText, runData->font_id, runData->font_percent)
            End If
            If runData->bold <> 0 AndAlso runData->font_id <> BACKEND_FONT_ARIAL_12_BOLD Then
                ' A fixed-pitch face keeps its advance when emboldened. Sans
                ' text uses the backend's separate bold face instead.
                If runData->italic <> 0 Then
                    backend_PrintItalicFontPercent(textX + 1, textY, textColor, fragmentText, runData->font_id, runData->font_percent)
                Else
                    backend_PrintFontPercent(textX + 1, textY, textColor, fragmentText, runData->font_id, runData->font_percent)
                End If
            End If
            Dim As Integer fragmentWidth = backend_GetTextWidthFontPercent(fragmentText, runData->font_id, runData->font_percent)
            If runData->underline <> 0 AndAlso fragmentWidth > 0 Then
                backend_Line(textX, lineY + lineData->ascent + 1, textX + fragmentWidth - 1, _
                    lineY + lineData->ascent + 1, textColor)
            End If
            textX += fragmentWidth
        Next fragmentOffset
    Next lineIndex
    backend_ResetClip
    If d->scrollbar <> 0 AndAlso d->scrollbar->visible <> 0 Then d->scrollbar->render(d->scrollbar)
End Sub


Sub rtfview_Destroy(ByVal w As Widget Ptr)

    Dim As RtfViewData Ptr d

    If w = 0 OrElse w->data = 0 Then Exit Sub
    d = Cast(RtfViewData Ptr, w->data)
    If d->scrollbar <> 0 Then
        If d->scrollbar->destroy <> 0 Then _
            d->scrollbar->destroy(d->scrollbar)
        Delete d->scrollbar
        d->scrollbar = 0
    End If
    Delete d
    w->data = 0

End Sub


Function rtfview_Create( _
    ByVal nm As String, ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer _
) As Widget Ptr

    Dim As Widget Ptr result = New Widget
    Dim As RtfViewData Ptr d = New RtfViewData

    result->name = nm
    result->x = x
    result->y = y
    result->w = w
    result->h = h
    result->render = @rtfview_Render
    result->update = @rtfview_Update
    result->destroy = @rtfview_Destroy
    result->visible = -1
    result->enabled = -1
    d->scrollbar = scrollbar_Create( _
        nm & "_sb", x + w - RTFVIEW_SCROLLBAR_WIDTH, y, _
        RTFVIEW_SCROLLBAR_WIDTH, h, 0, 1, -1 _
    )
    If d->scrollbar = 0 Then
        Delete d
        Delete result
        Return 0
    End If
    d->layout_dirty = -1
    d->content_left = RTFVIEW_CONTENT_INSET
    d->content_right = RTFVIEW_CONTENT_INSET
    d->content_top = 1
    d->content_bottom = 1
    result->data = d
    Return result

End Function

Sub rtfview_SetColors(ByVal w As Widget Ptr, ByVal backgroundColor As ULong, ByVal textColor As ULong)

    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As RtfViewData Ptr d = w->data
    theme_InitDialog(d->appearance)
    d->appearance.bg_widget = backgroundColor
    d->appearance.bg_light = backgroundColor
    d->appearance.text_main = textColor
    w->appearance = @d->appearance

End Sub

Sub rtfview_SetMargins( _
    ByVal w As Widget Ptr, ByVal leftMargin As Integer, ByVal topMargin As Integer, _
    ByVal rightMargin As Integer, ByVal bottomMargin As Integer _
)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    ' This is a view inset, independent of paragraph indents stored in twips.
    If leftMargin < 0 OrElse leftMargin > 512 OrElse topMargin < 0 OrElse topMargin > 512 OrElse _
       rightMargin < 0 OrElse rightMargin > 512 OrElse bottomMargin < 0 OrElse bottomMargin > 512 Then Exit Sub
    Dim As RtfViewData Ptr d = w->data
    d->content_left = leftMargin : d->content_top = topMargin
    d->content_right = rightMargin : d->content_bottom = bottomMargin
    d->layout_dirty = -1
End Sub


Function rtfview_SetRtf( _
    ByVal w As Widget Ptr, ByVal rtfText As String _
) As Integer

    Dim As RtfViewData Ptr d

    If w = 0 OrElse w->data = 0 Then Return 0
    d = Cast(RtfViewData Ptr, w->data)
    d->source_text = rtfText
    d->source_is_rtf = -1
    d->display_text_length = 0
    d->parse_error = ""
    d->paragraph_count = 0
    d->run_count = 0
    d->visual_line_count = 0
    d->line_fragment_count = 0
    d->scroll_top = 0 : d->last_scroll_top = 0 : d->scroll_offset = 0
    d->layout_dirty = -1
    d->font_count = 0 : d->color_count = 0 : d->default_font_number = 0
    d->document_height = 0
    d->pending_surrogate = 0

    If Len(rtfText) > RTFVIEW_MAX_INPUT_BYTES Then
        d->parse_error = "The RTF document exceeds the 1 MiB input limit"
        Return 0
    End If
    If rtfview_ParseRtf(d, rtfText) = 0 Then Return 0
    Return -1

End Function


Function rtfview_SetPlainText( _
    ByVal w As Widget Ptr, ByVal text As String _
) As Integer

    Dim As RtfViewData Ptr d

    If w = 0 OrElse w->data = 0 Then Return 0
    d = Cast(RtfViewData Ptr, w->data)
    d->source_text = text
    d->source_is_rtf = 0
    d->display_text_length = 0
    d->parse_error = ""
    d->paragraph_count = 0
    d->run_count = 0
    d->visual_line_count = 0
    d->line_fragment_count = 0
    d->scroll_top = 0 : d->last_scroll_top = 0 : d->scroll_offset = 0
    d->layout_dirty = -1
    d->font_count = 0 : d->color_count = 0 : d->default_font_number = 0
    d->document_height = 0
    d->pending_surrogate = 0

    If Len(text) > RTFVIEW_MAX_INPUT_BYTES Then
        d->parse_error = "The text document exceeds the 1 MiB input limit"
        Return 0
    End If
    If rtfview_ParsePlainText(d, text) = 0 Then Return 0
    Return -1

End Function


Function rtfview_GetError(ByVal w As Widget Ptr) As String

    If w = 0 OrElse w->data = 0 Then Return "Invalid RTF viewer widget"
    Return Cast(RtfViewData Ptr, w->data)->parse_error

End Function

/' end of rtfview.bas '/
