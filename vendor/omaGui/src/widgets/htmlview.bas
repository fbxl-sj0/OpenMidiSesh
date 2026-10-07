/'
    Project: omaGUI
    ---------------

    File: htmlview.bas

    Purpose:

        Implement a bounded, display-only HTML viewer with omaGUI primitives.

    Responsibilities:

        - tokenize a conservative HTML subset without external libraries
        - decode entities and lay out styled, wrapped text
        - apply a bounded subset of local CSS tag, class, and id rules
        - render headings, paragraphs, lists, tables, rules, links, and images
        - resolve named fragments for application-routed local navigation
        - resolve application-owned image schemes through a checked callback
        - build replacement documents cooperatively on the GUI thread
        - scroll through pointer, wheel, scrollbar, and keyboard input
        - report activated links without opening them

    Targets:

        FreeBASIC builds with built-in gfxlib; gfxlib3 is optional when supplied by the compiler.

    Module API:

        Implementation unit assembled by omaGUI.bi when OMAGUI_IMPLEMENTATION is defined.

    This file intentionally does NOT contain:

        - networking, URL resolution, or external process launching
        - JavaScript, executable CSS, forms, cookies, or browser storage
        - platform-native web controls or operating-system APIs

    Ownership:

        - each HtmlViewData owns its completed render-item list and images
        - a cooperative load context owns one private staging HtmlViewData
        - successful completion transfers the staging item list to the widget
        - cancellation, failure, and destruction release all staged resources
'/

#lang "fb"

#include once "src/widgets/htmlview.bi"
#include once "src/widgets/scrollbar.bi"
#include once "src/backend/theme.bi"

Const HTMLVIEW_SCROLLBAR_WIDTH As Integer = 15
Const HTMLVIEW_DEFAULT_PADDING As Integer = 8
Const HTMLVIEW_MINIMUM_LAYOUT_WIDTH As Integer = 24
Const HTMLVIEW_DEFAULT_LINE_HEIGHT As Integer = 14
Const HTMLVIEW_PARAGRAPH_GAP As Integer = 5
Const HTMLVIEW_LIST_INDENT As Integer = 20
Const HTMLVIEW_MAX_STYLE_DEPTH As Integer = 64
Const HTMLVIEW_MAX_LIST_DEPTH As Integer = 16
Const HTMLVIEW_WHEEL_PIXELS As Integer = 42
Const HTMLVIEW_MAX_TABLE_COLUMNS As Integer = 32
Const HTMLVIEW_MAX_FRAME_LINKS As Integer = 32
Const HTMLVIEW_TABLE_CELL_PADDING As Integer = 4
Const HTMLVIEW_TABLE_MINIMUM_COLUMN_WIDTH As Integer = 12
Const HTMLVIEW_TABLE_MEASURE_TEXT_LIMIT As Integer = 1024
Const HTMLVIEW_DECORATIVE_IMAGE_MAXIMUM_DIMENSION As Integer = 32
Const HTMLVIEW_MAX_PARSE_SECONDS As Double = 3.0
Const HTMLVIEW_PARSE_TIME_CHECK_INTERVAL As Long = 16
Const HTMLVIEW_SECONDS_PER_DAY As Double = 86400.0
Const HTMLVIEW_DEFAULT_LOAD_BUDGET_MS As Integer = 4
Const HTMLVIEW_MAXIMUM_LOAD_BUDGET_MS As Integer = 100

Const HTMLVIEW_ALIGN_LEFT As Integer = 0
Const HTMLVIEW_ALIGN_CENTER As Integer = 1
Const HTMLVIEW_ALIGN_RIGHT As Integer = 2

Const HTMLVIEW_KEY_UP_BIT As Integer = 1
Const HTMLVIEW_KEY_DOWN_BIT As Integer = 2
Const HTMLVIEW_KEY_HOME_BIT As Integer = 4
Const HTMLVIEW_KEY_END_BIT As Integer = 8
Const HTMLVIEW_KEY_PAGE_UP_BIT As Integer = 16
Const HTMLVIEW_KEY_PAGE_DOWN_BIT As Integer = 32


' -------------------------------------------------------------------------
' Private layout model
' -------------------------------------------------------------------------

Type HtmlViewLayoutStyle
    As Integer fontId
    As Integer scaleX, scaleY
    As Integer underline
    As Integer preformatted
    As Integer codeBackground
    As Integer indent
    As Integer alignment
    As Integer hasBackground
    As ULong color
    As ULong backgroundColor
    As String href
End Type

Type HtmlViewStyleFrame
    As String tagName
    As HtmlViewLayoutStyle previousStyle
End Type

Type HtmlViewLayoutState
    As HtmlViewData Ptr viewData
    As Integer availableWidth
    As Integer cursorX, cursorY
    As Integer lineHeight
    As Integer lineHasContent
    As Integer pendingSpace
    As Integer styleDepth
    As Integer listDepth
    As Integer navigationDepth
    As Integer definitionDepth
    As Integer listOrdered(0 To HTMLVIEW_MAX_LIST_DEPTH - 1)
    As Integer listCounter(0 To HTMLVIEW_MAX_LIST_DEPTH - 1)
    As String definitionTags(0 To HTMLVIEW_MAX_LIST_DEPTH - 1)
    As Integer tableActive
    As Integer tableNestedDepth
    As Integer tableLayoutDepth
    As Integer tableColumnCount
    As Integer tableCurrentColumn
    As Integer tableCellSpan
    As Integer tableX
    As Integer tableWidth
    As Integer tableRowTop
    As Integer tableRowBottom
    As Integer tableRowOpen
    As Integer tableCellOpen
    As Integer tableCellBoxCount
    As Integer tableSavedAvailableWidth
    As Integer tableColumnWidths(0 To HTMLVIEW_MAX_TABLE_COLUMNS - 1)
    As HtmlViewItem Ptr tableCellBoxes(0 To HTMLVIEW_MAX_TABLE_COLUMNS - 1)
    As String tableCellTag
    As Integer inHead
    As Integer inTitle
    As Integer bodyStarted
    As Integer documentTitleSeen
    As Integer ignoredTitleDepth
    As Integer ignoredDepth
    As Integer interactiveFallbackNeeded
    As Integer frameSourceCount
    As String frameSources(0 To HTMLVIEW_MAX_FRAME_LINKS - 1)
    As ULongInt decodedImagePixels
    As String ignoredTag
    As HtmlViewItem Ptr lineFirstItem
    As HtmlViewLayoutStyle style
    As HtmlViewStyleFrame styleStack(0 To HTMLVIEW_MAX_STYLE_DEPTH - 1)
End Type

Type HtmlViewParseContext
    As HtmlViewLayoutState state
    As Long position
    As Long parseIteration
    As Double workSeconds
    As Integer complete
End Type

Type HtmlViewLoadContext
    As HtmlViewData Ptr stagingData
    As HtmlViewParseContext parser
    As Integer layoutWidth
End Type


' -------------------------------------------------------------------------
' Data ownership and diagnostics
' -------------------------------------------------------------------------

Private Function htmlview_Data(ByVal htmlWidget As Widget Ptr) As HtmlViewData Ptr
    If htmlWidget = 0 OrElse htmlWidget->data = 0 Then Return 0
    Return Cast(HtmlViewData Ptr, htmlWidget->data)
End Function


Private Sub htmlview_SetError( _
    ByVal viewData As HtmlViewData Ptr, ByVal message As String _
)
    If viewData = 0 OrElse Len(viewData->lastError) > 0 Then Exit Sub
    viewData->lastError = message
End Sub


Private Sub htmlview_DeleteItems(ByVal viewData As HtmlViewData Ptr)
    Dim As HtmlViewItem Ptr currentItem
    Dim As HtmlViewItem Ptr nextItem

    If viewData = 0 Then Exit Sub

    currentItem = viewData->firstItem
    While currentItem <> 0
        nextItem = currentItem->nextItem
        If currentItem->image <> 0 Then
            rasterimage_Destroy currentItem->image
            currentItem->image = 0
        End If
        Delete currentItem
        currentItem = nextItem
    Wend

    viewData->firstItem = 0
    viewData->lastItem = 0
    viewData->itemCount = 0
End Sub


Private Sub htmlview_AppendPlain( _
    ByVal viewData As HtmlViewData Ptr, ByVal textValue As String _
)
    If viewData = 0 OrElse Len(textValue) = 0 Then Exit Sub
    viewData->plainText &= textValue
End Sub


Private Sub htmlview_AppendPlainLine(ByVal viewData As HtmlViewData Ptr)
    Dim As Long textLength

    If viewData = 0 Then Exit Sub
    textLength = Len(viewData->plainText)
    If textLength = 0 Then Exit Sub
    If Right(viewData->plainText, 1) <> Chr(10) Then
        viewData->plainText &= Chr(10)
    End If
End Sub


' -------------------------------------------------------------------------
' Text, entity, color, and attribute helpers
' -------------------------------------------------------------------------

Private Function htmlview_IsWhiteSpace(ByVal character As UByte) As Integer
    Return character = 9 OrElse character = 10 OrElse _
        character = 12 OrElse character = 13 OrElse character = 32
End Function


Private Function htmlview_ReplaceAll( _
    ByVal sourceText As String, ByVal findText As String, _
    ByVal replacementText As String _
) As String
    Dim As String result
    Dim As Long matchPosition
    Dim As Long searchPosition

    If Len(findText) = 0 Then Return sourceText

    searchPosition = 1
    Do
        matchPosition = InStr(searchPosition, sourceText, findText)
        If matchPosition = 0 Then Exit Do
        result &= Mid(sourceText, searchPosition, matchPosition - searchPosition)
        result &= replacementText
        searchPosition = matchPosition + Len(findText)
    Loop

    result &= Mid(sourceText, searchPosition)
    Return result
End Function


Private Function htmlview_TrimPlainEnd(ByVal sourceText As String) As String
    Dim As Long finalPosition
    Dim As UByte character

    finalPosition = Len(sourceText)
    While finalPosition > 0
        character = Asc(Mid(sourceText, finalPosition, 1))
        If character <> 10 AndAlso character <> 13 AndAlso character <> 32 Then
            Exit While
        End If
        finalPosition -= 1
    Wend

    Return Left(sourceText, finalPosition)
End Function


Private Function htmlview_Utf8CodePoint(ByVal codePoint As ULong) As String
    If codePoint <= &h7FUL Then
        Return Chr(codePoint)
    ElseIf codePoint <= &h7FFUL Then
        Return Chr(&hC0 Or (codePoint Shr 6)) & _
            Chr(&h80 Or (codePoint And &h3F))
    ElseIf codePoint >= &hD800UL AndAlso codePoint <= &hDFFFUL Then
        Return "?"
    ElseIf codePoint <= &hFFFFUL Then
        Return Chr(&hE0 Or (codePoint Shr 12)) & _
            Chr(&h80 Or ((codePoint Shr 6) And &h3F)) & _
            Chr(&h80 Or (codePoint And &h3F))
    ElseIf codePoint <= &h10FFFFUL Then
        Return Chr(&hF0 Or (codePoint Shr 18)) & _
            Chr(&h80 Or ((codePoint Shr 12) And &h3F)) & _
            Chr(&h80 Or ((codePoint Shr 6) And &h3F)) & _
            Chr(&h80 Or (codePoint And &h3F))
    End If
    Return "?"
End Function


Private Function htmlview_DisplayCodePoint(ByVal codePoint As ULong) As String
    /'
        The embedded omaGUI fonts contain printable ASCII glyphs.  HTML can
        still carry UTF-8 or legacy Latin-1 text, so common punctuation and
        Western European letters are reduced to readable ASCII equivalents.
        Unknown scripts use one visible replacement character instead of
        occupying zero pixels and silently deleting content.
    '/
    If codePoint = 9 OrElse codePoint = 10 OrElse codePoint = 13 Then
        Return Chr(codePoint)
    End If
    If codePoint >= 32 AndAlso codePoint <= 126 Then Return Chr(codePoint)

    Select Case codePoint
    Case 133, &h2026UL: Return "..."
    Case 145, 146, &h2018UL, &h2019UL, &h2032UL: Return "'"
    Case 147, 148, &h201CUL, &h201DUL, &h2033UL: Return Chr(34)
    Case 150, 151, &h2010UL, &h2011UL, &h2012UL, &h2013UL, _
         &h2014UL, &h2212UL: Return "-"
    Case 160, &h2000UL To &h200AUL, &h202FUL, &h205FUL, &h3000UL
        Return " "
    Case &h200BUL, &h200CUL, &h200DUL, &h2060UL, _
         &h2066UL To &h2069UL, &hFEFFUL
        Return ""
    Case 169: Return "(c)"
    Case 174: Return "(R)"
    Case &h2022UL, &h25CFUL: Return "*"
    Case &h2039UL: Return "<"
    Case &h203AUL: Return ">"
    Case &h2044UL: Return "/"
    Case &h2190UL: Return "<-"
    Case &h2192UL, &h2197UL: Return "->"
    Case &h2191UL: Return "^"
    Case &h2193UL: Return "v"
    Case &h00C0UL To &h00C5UL: Return "A"
    Case &h00C6UL: Return "AE"
    Case &h00C7UL: Return "C"
    Case &h00C8UL To &h00CBUL: Return "E"
    Case &h00CCUL To &h00CFUL: Return "I"
    Case &h00D0UL: Return "D"
    Case &h00D1UL: Return "N"
    Case &h00D2UL To &h00D6UL, &h00D8UL: Return "O"
    Case &h00D9UL To &h00DCUL: Return "U"
    Case &h00DDUL: Return "Y"
    Case &h00DEUL: Return "TH"
    Case &h00DFUL: Return "ss"
    Case &h00E0UL To &h00E5UL: Return "a"
    Case &h00E6UL: Return "ae"
    Case &h00E7UL: Return "c"
    Case &h00E8UL To &h00EBUL: Return "e"
    Case &h00ECUL To &h00EFUL: Return "i"
    Case &h00F0UL: Return "d"
    Case &h00F1UL: Return "n"
    Case &h00F2UL To &h00F6UL, &h00F8UL: Return "o"
    Case &h00F9UL To &h00FCUL: Return "u"
    Case &h00FDUL, &h00FFUL: Return "y"
    Case &h00FEUL: Return "th"
    End Select
    Return "?"
End Function


Private Function htmlview_DisplaySafeText(ByVal sourceText As String) As String
    Dim As String result
    Dim As String replacementText
    Dim As Long position
    Dim As Long sequenceLength
    Dim As ULong codePoint
    Dim As UByte firstByte
    Dim As UByte secondByte
    Dim As UByte thirdByte
    Dim As UByte fourthByte
    Dim As Integer validSequence

    position = 1
    While position <= Len(sourceText)
        firstByte = Asc(Mid(sourceText, position, 1))
        codePoint = firstByte
        sequenceLength = 1
        validSequence = 0

        If firstByte < &h80 Then
            validSequence = -1
        ElseIf firstByte >= &hC2 AndAlso firstByte <= &hDF AndAlso _
               position + 1 <= Len(sourceText) Then
            secondByte = Asc(Mid(sourceText, position + 1, 1))
            If secondByte >= &h80 AndAlso secondByte <= &hBF Then
                codePoint = ((firstByte And &h1F) Shl 6) Or _
                    (secondByte And &h3F)
                sequenceLength = 2
                validSequence = -1
            End If
        ElseIf firstByte >= &hE0 AndAlso firstByte <= &hEF AndAlso _
               position + 2 <= Len(sourceText) Then
            secondByte = Asc(Mid(sourceText, position + 1, 1))
            thirdByte = Asc(Mid(sourceText, position + 2, 1))
            If secondByte >= &h80 AndAlso secondByte <= &hBF AndAlso _
               thirdByte >= &h80 AndAlso thirdByte <= &hBF AndAlso _
               Not (firstByte = &hE0 AndAlso secondByte < &hA0) AndAlso _
               Not (firstByte = &hED AndAlso secondByte >= &hA0) Then
                codePoint = ((firstByte And &h0F) Shl 12) Or _
                    ((secondByte And &h3F) Shl 6) Or (thirdByte And &h3F)
                sequenceLength = 3
                validSequence = -1
            End If
        ElseIf firstByte >= &hF0 AndAlso firstByte <= &hF4 AndAlso _
               position + 3 <= Len(sourceText) Then
            secondByte = Asc(Mid(sourceText, position + 1, 1))
            thirdByte = Asc(Mid(sourceText, position + 2, 1))
            fourthByte = Asc(Mid(sourceText, position + 3, 1))
            If secondByte >= &h80 AndAlso secondByte <= &hBF AndAlso _
               thirdByte >= &h80 AndAlso thirdByte <= &hBF AndAlso _
               fourthByte >= &h80 AndAlso fourthByte <= &hBF AndAlso _
               Not (firstByte = &hF0 AndAlso secondByte < &h90) AndAlso _
               Not (firstByte = &hF4 AndAlso secondByte > &h8F) Then
                codePoint = ((firstByte And &h07) Shl 18) Or _
                    ((secondByte And &h3F) Shl 12) Or _
                    ((thirdByte And &h3F) Shl 6) Or (fourthByte And &h3F)
                sequenceLength = 4
                validSequence = -1
            End If
        End If

        /'
            An invalid multi-byte sequence is treated as one Latin-1 byte.
            This also covers old pages which declare ISO-8859-1 and are loaded
            from disk without an encoding conversion layer.
        '/
        If validSequence = 0 Then
            codePoint = firstByte
            sequenceLength = 1
        End If
        replacementText = htmlview_DisplayCodePoint(codePoint)
        If replacementText <> "?" OrElse _
           Len(result) = 0 OrElse Right(result, 1) <> "?" Then
            result &= replacementText
        End If
        position += sequenceLength
    Wend
    Return result
End Function


Private Function htmlview_ParseUnsigned( _
    ByVal textValue As String, ByVal baseValue As Integer, _
    ByRef parsedValue As ULong _
) As Integer
    Dim As ULongInt accumulator
    Dim As Long position
    Dim As Long digit
    Dim As UByte character

    If Len(textValue) = 0 Then Return 0
    accumulator = 0

    For position = 1 To Len(textValue)
        character = Asc(Mid(textValue, position, 1))
        If character >= Asc("0") AndAlso character <= Asc("9") Then
            digit = character - Asc("0")
        ElseIf character >= Asc("a") AndAlso character <= Asc("f") Then
            digit = character - Asc("a") + 10
        ElseIf character >= Asc("A") AndAlso character <= Asc("F") Then
            digit = character - Asc("A") + 10
        Else
            Return 0
        End If

        If digit >= baseValue Then Return 0
        If accumulator > (&h10FFFFULL - digit) \ baseValue Then Return 0
        accumulator = accumulator * baseValue + digit
    Next position

    parsedValue = CULng(accumulator)
    Return -1
End Function


Private Function htmlview_DecodeEntities(ByVal sourceText As String) As String
    Dim As String result
    Dim As String entityText
    Dim As String entityName
    Dim As Long position
    Dim As Long delimiterPosition
    Dim As ULong codePoint
    Dim As Integer parsed

    position = 1
    While position <= Len(sourceText)
        If Mid(sourceText, position, 1) <> "&" Then
            result &= Mid(sourceText, position, 1)
            position += 1
            Continue While
        End If

        delimiterPosition = InStr(position + 1, sourceText, ";")
        If delimiterPosition = 0 OrElse delimiterPosition - position > 16 Then
            result &= "&"
            position += 1
            Continue While
        End If

        entityText = Mid( _
            sourceText, position + 1, delimiterPosition - position - 1 _
        )
        entityName = LCase(entityText)
        parsed = 0

        Select Case entityName
        Case "amp"
            result &= "&"
            parsed = -1
        Case "lt"
            result &= "<"
            parsed = -1
        Case "gt"
            result &= ">"
            parsed = -1
        Case "quot"
            result &= Chr(34)
            parsed = -1
        Case "apos"
            result &= "'"
            parsed = -1
        Case "nbsp"
            result &= " "
            parsed = -1
        Case "copy"
            result &= htmlview_Utf8CodePoint(169)
            parsed = -1
        Case "reg"
            result &= htmlview_Utf8CodePoint(174)
            parsed = -1
        Case "hellip"
            result &= htmlview_Utf8CodePoint(&h2026)
            parsed = -1
        Case "ndash"
            result &= htmlview_Utf8CodePoint(&h2013)
            parsed = -1
        Case "mdash"
            result &= htmlview_Utf8CodePoint(&h2014)
            parsed = -1
        Case "lsquo": result &= htmlview_Utf8CodePoint(&h2018): parsed = -1
        Case "rsquo": result &= htmlview_Utf8CodePoint(&h2019): parsed = -1
        Case "ldquo": result &= htmlview_Utf8CodePoint(&h201C): parsed = -1
        Case "rdquo": result &= htmlview_Utf8CodePoint(&h201D): parsed = -1
        Case "bull": result &= htmlview_Utf8CodePoint(&h2022): parsed = -1
        Case "middot": result &= "*": parsed = -1
        Case "laquo": result &= "<<": parsed = -1
        Case "raquo": result &= ">>": parsed = -1
        Case "trade": result &= "(TM)": parsed = -1
        Case "cent": result &= "cent": parsed = -1
        Case "pound": result &= "GBP": parsed = -1
        Case "yen": result &= "YEN": parsed = -1
        Case "euro": result &= "EUR": parsed = -1
        Case "deg": result &= " deg": parsed = -1
        Case "plusmn": result &= "+/-": parsed = -1
        Case "times": result &= "x": parsed = -1
        Case "divide": result &= "/": parsed = -1
        Case Else
            If Left(entityName, 2) = "#x" Then
                parsed = htmlview_ParseUnsigned(Mid(entityName, 3), 16, codePoint)
            ElseIf Left(entityName, 1) = "#" Then
                parsed = htmlview_ParseUnsigned(Mid(entityName, 2), 10, codePoint)
            End If

            If parsed Then result &= htmlview_Utf8CodePoint(codePoint)
        End Select

        If parsed Then
            position = delimiterPosition + 1
        Else
            result &= "&"
            position += 1
        End If
    Wend

    Return result
End Function


Private Function htmlview_CollapseWhitespace(ByVal sourceText As String) As String
    Dim As String result
    Dim As Long position
    Dim As Integer pendingSpace
    Dim As UByte character

    For position = 1 To Len(sourceText)
        character = Asc(Mid(sourceText, position, 1))
        If htmlview_IsWhiteSpace(character) Then
            pendingSpace = -1
        Else
            If pendingSpace AndAlso Len(result) > 0 Then result &= " "
            result &= Mid(sourceText, position, 1)
            pendingSpace = 0
        End If
    Next position
    Return result
End Function


Private Function htmlview_HexDigit(ByVal character As UByte) As Integer
    If character >= Asc("0") AndAlso character <= Asc("9") Then
        Return character - Asc("0")
    End If
    If character >= Asc("a") AndAlso character <= Asc("f") Then
        Return character - Asc("a") + 10
    End If
    If character >= Asc("A") AndAlso character <= Asc("F") Then
        Return character - Asc("A") + 10
    End If
    Return -1
End Function


Private Function htmlview_ParseColor( _
    ByVal colorText As String, ByRef colorValue As ULong _
) As Integer
    Dim As String cleanText
    Dim As Integer digits(0 To 5)
    Dim As Long index

    cleanText = LCase(Trim(colorText))
    Select Case cleanText
    Case "black": colorValue = RGB(0, 0, 0): Return -1
    Case "white": colorValue = RGB(255, 255, 255): Return -1
    Case "red": colorValue = RGB(192, 0, 0): Return -1
    Case "green": colorValue = RGB(0, 128, 0): Return -1
    Case "blue": colorValue = RGB(0, 0, 192): Return -1
    Case "navy": colorValue = RGB(0, 0, 128): Return -1
    Case "yellow": colorValue = RGB(255, 255, 0): Return -1
    Case "gray", "grey": colorValue = RGB(128, 128, 128): Return -1
    Case "maroon": colorValue = RGB(128, 0, 0): Return -1
    Case "purple": colorValue = RGB(128, 0, 128): Return -1
    Case "teal": colorValue = RGB(0, 128, 128): Return -1
    End Select

    If Left(cleanText, 1) <> "#" Then Return 0
    cleanText = Mid(cleanText, 2)
    If Len(cleanText) = 3 Then
        For index = 0 To 2
            digits(index) = htmlview_HexDigit(Asc(Mid(cleanText, index + 1, 1)))
            If digits(index) < 0 Then Return 0
        Next index
        colorValue = RGB( _
            digits(0) * 17, digits(1) * 17, digits(2) * 17 _
        )
        Return -1
    End If

    If Len(cleanText) <> 6 Then Return 0
    For index = 0 To 5
        digits(index) = htmlview_HexDigit(Asc(Mid(cleanText, index + 1, 1)))
        If digits(index) < 0 Then Return 0
    Next index
    colorValue = RGB( _
        digits(0) * 16 + digits(1), _
        digits(2) * 16 + digits(3), _
        digits(4) * 16 + digits(5) _
    )
    Return -1
End Function


Private Function htmlview_FindAttribute( _
    ByVal attributeText As String, _
    ByVal requestedName As String, _
    ByRef foundValue As String _
) As Integer
    Dim As Long position
    Dim As Long nameStart
    Dim As Long valueStart
    Dim As Long textLength
    Dim As UByte character
    Dim As String attributeName
    Dim As String attributeValue
    Dim As String quoteCharacter

    position = 1
    textLength = Len(attributeText)
    requestedName = LCase(requestedName)
    foundValue = ""

    While position <= textLength
        Do While position <= textLength
            character = Asc(Mid(attributeText, position, 1))
            If Not htmlview_IsWhiteSpace(character) AndAlso character <> Asc("/") Then
                Exit Do
            End If
            position += 1
        Loop
        If position > textLength Then Exit While

        nameStart = position
        Do While position <= textLength
            character = Asc(Mid(attributeText, position, 1))
            If htmlview_IsWhiteSpace(character) OrElse character = Asc("=") OrElse _
               character = Asc("/") Then Exit Do
            position += 1
        Loop
        attributeName = LCase(Mid(attributeText, nameStart, position - nameStart))

        Do While position <= textLength AndAlso _
            htmlview_IsWhiteSpace(Asc(Mid(attributeText, position, 1)))
            position += 1
        Loop

        attributeValue = ""
        If position <= textLength AndAlso Mid(attributeText, position, 1) = "=" Then
            position += 1
            Do While position <= textLength AndAlso _
                htmlview_IsWhiteSpace(Asc(Mid(attributeText, position, 1)))
                position += 1
            Loop

            If position <= textLength AndAlso _
               (Mid(attributeText, position, 1) = Chr(34) OrElse _
                Mid(attributeText, position, 1) = "'") Then
                quoteCharacter = Mid(attributeText, position, 1)
                position += 1
                valueStart = position
                Do While position <= textLength AndAlso _
                    Mid(attributeText, position, 1) <> quoteCharacter
                    position += 1
                Loop
                attributeValue = Mid(attributeText, valueStart, position - valueStart)
                If position <= textLength Then position += 1
            Else
                valueStart = position
                Do While position <= textLength
                    character = Asc(Mid(attributeText, position, 1))
                    If htmlview_IsWhiteSpace(character) OrElse character = Asc("/") Then
                        Exit Do
                    End If
                    position += 1
                Loop
                attributeValue = Mid(attributeText, valueStart, position - valueStart)
            End If
        End If

        If attributeName = requestedName Then
            foundValue = htmlview_DecodeEntities(attributeValue)
            Return -1
        End If
    Wend
    Return 0
End Function


Private Function htmlview_GetAttribute( _
    ByVal attributeText As String, ByVal requestedName As String _
) As String
    Dim As String foundValue

    htmlview_FindAttribute attributeText, requestedName, foundValue
    Return foundValue
End Function


Private Function htmlview_HasAttribute( _
    ByVal attributeText As String, ByVal requestedName As String _
) As Integer
    Dim As String ignoredValue

    Return htmlview_FindAttribute(attributeText, requestedName, ignoredValue)
End Function


Private Function htmlview_GetCssValue( _
    ByVal styleText As String, ByVal requestedProperty As String _
) As String
    Dim As Long position
    Dim As Long delimiterPosition
    Dim As Long colonPosition
    Dim As String declaration
    Dim As String propertyName

    position = 1
    requestedProperty = LCase(requestedProperty)
    While position <= Len(styleText) + 1
        delimiterPosition = InStr(position, styleText, ";")
        If delimiterPosition = 0 Then delimiterPosition = Len(styleText) + 1
        declaration = Trim(Mid(styleText, position, delimiterPosition - position))
        colonPosition = InStr(declaration, ":")
        If colonPosition > 1 Then
            propertyName = LCase(Trim(Left(declaration, colonPosition - 1)))
            If propertyName = requestedProperty Then
                Return Trim(Mid(declaration, colonPosition + 1))
            End If
        End If
        If delimiterPosition > Len(styleText) Then Exit While
        position = delimiterPosition + 1
    Wend
    Return ""
End Function


Private Sub htmlview_AddCssRule( _
    ByVal viewData As HtmlViewData Ptr, ByVal selectorText As String, _
    ByVal declarationText As String _
)

    Dim As Integer selectorPosition
    Dim As String selectorPart

    If viewData = 0 OrElse _
       viewData->cssRuleCount >= HTMLVIEW_MAX_CSS_RULES Then Exit Sub

    selectorText = LCase(Trim(selectorText))
    If selectorText = "" Then Exit Sub

    /'
        This viewer supports simple tag, class, and id selectors.  For a
        descendant selector, the final component still gives useful styling
        without pretending to implement a browser's full selector engine.
    '/
    For selectorPosition = Len(selectorText) To 1 Step -1
        Select Case Mid(selectorText, selectorPosition, 1)
        Case " ", Chr(9), ">", "+", "~"
            selectorText = Trim(Mid(selectorText, selectorPosition + 1))
            Exit For
        End Select
    Next selectorPosition

    selectorPosition = InStr(selectorText, ":")
    If selectorPosition > 0 Then Exit Sub
    selectorText = Trim(selectorText)
    If selectorText = "" OrElse selectorText = "*" Then Exit Sub

    selectorPart = selectorText
    With viewData->cssRules(viewData->cssRuleCount)
        .selectorText = selectorPart
        .declarationText = declarationText
    End With
    viewData->cssRuleCount += 1

End Sub


Private Sub htmlview_ParseStylesheet( _
    ByVal viewData As HtmlViewData Ptr, ByVal styleSheetText As String _
)

    Dim As Integer commaPosition
    Dim As Long openPosition
    Dim As Long closePosition
    Dim As Long position
    Dim As String selectorText
    Dim As String declarationText

    If viewData = 0 Then Exit Sub
    viewData->styleSheetText = ""
    viewData->cssRuleCount = 0
    If Len(styleSheetText) > HTMLVIEW_MAX_STYLESHEET_BYTES Then Exit Sub
    viewData->styleSheetText = styleSheetText

    position = 1
    While position <= Len(styleSheetText) AndAlso _
          viewData->cssRuleCount < HTMLVIEW_MAX_CSS_RULES
        openPosition = InStr(position, styleSheetText, "{")
        If openPosition = 0 Then Exit While
        closePosition = InStr(openPosition + 1, styleSheetText, "}")
        If closePosition = 0 Then Exit While

        selectorText = Trim(Mid( _
            styleSheetText, position, openPosition - position _
        ))
        declarationText = Trim(Mid( _
            styleSheetText, openPosition + 1, _
            closePosition - openPosition - 1 _
        ))
        While Len(selectorText) > 0
            commaPosition = InStr(selectorText, ",")
            If commaPosition = 0 Then
                htmlview_AddCssRule viewData, selectorText, declarationText
                Exit While
            End If
            htmlview_AddCssRule _
                viewData, Left(selectorText, commaPosition - 1), declarationText
            selectorText = Mid(selectorText, commaPosition + 1)
        Wend
        position = closePosition + 1
    Wend

End Sub


Private Function htmlview_CssSelectorMatches( _
    ByVal selectorText As String, ByVal tagName As String, _
    ByVal attributeText As String _
) As Integer

    Dim As String attributeValue
    Dim As String classList
    Dim As String className

    selectorText = LCase(Trim(selectorText))
    If Left(selectorText, 1) = "." Then
        ' A class selector must name a class; a bare prefix matches nothing.
        If Len(selectorText) < 2 Then Return 0
        className = Mid(selectorText, 2)
        classList = LCase(htmlview_GetAttribute(attributeText, "class"))
        Return IIf( _
            InStr(" " & classList & " ", " " & className & " ") > 0, -1, 0 _
        )
    End If
    If Left(selectorText, 1) = "#" Then
        If Len(selectorText) < 2 Then Return 0
        attributeValue = LCase(htmlview_GetAttribute(attributeText, "id"))
        Return IIf( _
            "#" & attributeValue = selectorText, -1, 0 _
        )
    End If
    Return IIf(selectorText = LCase(tagName), -1, 0)

End Function


Private Function htmlview_CssLengthPixels(ByVal valueText As String) As Integer

    Dim As Double lengthValue

    valueText = LCase(Trim(valueText))
    lengthValue = Val(valueText)
    If InStr(valueText, "pt") > 0 Then lengthValue *= 4.0 / 3.0
    If lengthValue < 0.0 Then Return 0
    If lengthValue > 1024.0 Then Return 1024
    Return CInt(lengthValue)

End Function


Private Function htmlview_CssPaddingLeft( _
    ByVal styleText As String _
) As Integer

    Dim As Integer position
    Dim As Integer valueCount
    Dim As String values(0 To 3)
    Dim As String paddingText
    Dim As String valueText

    valueText = htmlview_GetCssValue(styleText, "padding-left")
    If valueText <> "" Then Return htmlview_CssLengthPixels(valueText)

    valueText = htmlview_GetCssValue(styleText, "margin-left")
    If valueText <> "" Then Return htmlview_CssLengthPixels(valueText)

    paddingText = Trim(htmlview_GetCssValue(styleText, "padding"))
    If paddingText = "" Then Return 0

    position = 1
    valueCount = 0
    Do While position <= Len(paddingText)
        Do While position <= Len(paddingText) AndAlso _
            (Mid(paddingText, position, 1) = " " OrElse _
             Mid(paddingText, position, 1) = Chr(9))
            position += 1
        Loop
        If position > Len(paddingText) Then Exit Do
        valueCount += 1
        valueText = ""
        Do While position <= Len(paddingText) AndAlso _
            Mid(paddingText, position, 1) <> " " AndAlso _
            Mid(paddingText, position, 1) <> Chr(9)
            valueText &= Mid(paddingText, position, 1)
            position += 1
        Loop
        If valueCount <= 4 Then values(valueCount - 1) = valueText
        If valueCount > 4 Then Exit Do
    Loop

    If valueCount = 1 Then _
        Return htmlview_CssLengthPixels(values(0))
    If valueCount = 2 OrElse valueCount = 3 Then _
        Return htmlview_CssLengthPixels(values(1))
    If valueCount = 4 Then _
        Return htmlview_CssLengthPixels(values(3))
    Return 0

End Function


Private Function htmlview_ParseAlignment(ByVal alignmentText As String) As Integer
    Select Case LCase(Trim(alignmentText))
    Case "center": Return HTMLVIEW_ALIGN_CENTER
    Case "right": Return HTMLVIEW_ALIGN_RIGHT
    End Select
    Return HTMLVIEW_ALIGN_LEFT
End Function


Private Function htmlview_PathDirectory(ByVal filePath As String) As String
    Dim As Long position

    For position = Len(filePath) To 1 Step -1
        If Mid(filePath, position, 1) = "/" OrElse _
           Mid(filePath, position, 1) = "\" Then
            Return Left(filePath, position - 1)
        End If
    Next position
    Return ""
End Function


Private Function htmlview_PathIsAbsolute(ByVal filePath As String) As Integer
    If Len(filePath) = 0 Then Return 0
    If Left(filePath, 1) = "/" OrElse Left(filePath, 1) = "\" Then Return -1
    If Len(filePath) >= 2 AndAlso Mid(filePath, 2, 1) = ":" Then Return -1
    Return 0
End Function


Private Function htmlview_PathHasScheme(ByVal resourcePath As String) As Integer
    Dim As Long colonPosition
    Dim As Long position
    Dim As UByte character

    colonPosition = InStr(resourcePath, ":")
    If colonPosition <= 1 Then Return 0

    /'
        A drive letter is an absolute local path, not a URI scheme. This
        exception is harmless on non-Windows systems and keeps one parser.
    '/
    If colonPosition = 2 Then
        character = Asc(Left(resourcePath, 1))
        If (character >= Asc("A") AndAlso character <= Asc("Z")) OrElse _
           (character >= Asc("a") AndAlso character <= Asc("z")) Then Return 0
    End If

    For position = 1 To colonPosition - 1
        character = Asc(Mid(resourcePath, position, 1))
        If Not ((character >= Asc("A") AndAlso character <= Asc("Z")) OrElse _
                (character >= Asc("a") AndAlso character <= Asc("z")) OrElse _
                (character >= Asc("0") AndAlso character <= Asc("9")) OrElse _
                character = Asc("+") OrElse character = Asc("-") OrElse _
                character = Asc(".")) Then Return 0
    Next position
    Return -1
End Function


Private Function htmlview_ResolveImagePath( _
    ByVal basePath As String, ByVal sourcePath As String _
) As String
    Dim As Integer firstCode
    Dim As Integer secondCode

    sourcePath = Trim(sourcePath)
    If Len(sourcePath) = 0 OrElse Left(sourcePath, 1) = "#" Then Return ""

    /'
        The viewer is deliberately local-only. URI schemes, including data,
        http, and file, are left to an application-level resource policy.
        Protocol-relative URLs and UNC paths are remote resources too.  They
        must be rejected before a filesystem call can trigger a blocking
        network-share lookup on Windows.
    '/
    If Len(sourcePath) >= 2 Then
        firstCode = Asc(Mid(sourcePath, 1, 1))
        secondCode = Asc(Mid(sourcePath, 2, 1))
        If (firstCode = Asc("/") AndAlso secondCode = Asc("/")) OrElse _
           (firstCode = Asc("\") AndAlso secondCode = Asc("\")) Then Return ""
    End If
    If htmlview_PathHasScheme(sourcePath) Then Return ""
    If htmlview_PathIsAbsolute(sourcePath) OrElse Len(basePath) = 0 Then
        Return sourcePath
    End If
    If Right(basePath, 1) = "/" OrElse Right(basePath, 1) = "\" Then
        Return basePath & sourcePath
    End If
    Return basePath & "/" & sourcePath
End Function


Private Function htmlview_ResolveResourcePath( _
    ByVal basePath As String, ByVal sourcePath As String, _
    ByVal hasResourceHandler As Integer _
) As String

    Dim As Integer schemePosition

    sourcePath = Trim(sourcePath)
    If sourcePath = "" Then Return ""
    If htmlview_PathHasScheme(sourcePath) <> 0 Then Return sourcePath

    If hasResourceHandler <> 0 AndAlso _
       htmlview_PathHasScheme(basePath) <> 0 Then
        If Len(sourcePath) >= 2 AndAlso _
           Left(sourcePath, 2) = "//" Then Return ""
        schemePosition = InStr(basePath, "://")
        If schemePosition = 0 Then Return ""
        If htmlview_PathIsAbsolute(sourcePath) <> 0 Then
            While Len(sourcePath) > 0 AndAlso Left(sourcePath, 1) = "/"
                sourcePath = Mid(sourcePath, 2)
            Wend
            Return Left(basePath, schemePosition + 2) & sourcePath
        End If
        If Right(basePath, 1) = "/" Then Return basePath & sourcePath
        Return basePath & "/" & sourcePath
    End If

    Return htmlview_ResolveImagePath(basePath, sourcePath)

End Function


' -------------------------------------------------------------------------
' Layout item construction
' -------------------------------------------------------------------------

Declare Sub htmlview_NextLine( _
    ByRef state As HtmlViewLayoutState, ByVal extraGap As Integer = 0 _
)


Private Function htmlview_TextWidth( _
    ByRef style As HtmlViewLayoutStyle, ByVal textValue As String _
) As Integer
    Return backend_GetTextWidthScaledFont( _
        textValue, style.fontId, style.scaleX _
    )
End Function


Private Function htmlview_TextHeight( _
    ByRef style As HtmlViewLayoutStyle _
) As Integer
    Return backend_GetTextHeightScaledFont(style.fontId, style.scaleY)
End Function


Private Function htmlview_AddTextItem( _
    ByRef state As HtmlViewLayoutState, ByVal textValue As String _
) As Integer
    Dim As HtmlViewItem Ptr item
    Dim As Integer itemWidth
    Dim As Integer itemHeight

    If Len(textValue) = 0 Then Return -1
    If state.viewData->itemCount >= HTMLVIEW_MAX_LAYOUT_ITEMS Then
        state.viewData->layoutIncomplete = -1
        htmlview_SetError state.viewData, _
            "HTML layout reached the 65,536 item safety limit"
        Return 0
    End If

    item = New HtmlViewItem
    If item = 0 Then
        state.viewData->layoutIncomplete = -1
        htmlview_SetError state.viewData, "unable to allocate an HTML layout item"
        Return 0
    End If

    itemWidth = htmlview_TextWidth(state.style, textValue)
    itemHeight = htmlview_TextHeight(state.style)
    If itemHeight < 1 Then itemHeight = HTMLVIEW_DEFAULT_LINE_HEIGHT

    item->itemKind = HTMLVIEW_ITEM_TEXT
    item->x = state.cursorX
    item->y = state.cursorY
    item->w = itemWidth
    item->h = itemHeight
    item->fontId = state.style.fontId
    item->scaleX = state.style.scaleX
    item->scaleY = state.style.scaleY
    item->underline = state.style.underline
    item->codeBackground = state.style.codeBackground
    item->color = state.style.color
    item->backgroundColor = state.style.backgroundColor
    item->text = textValue
    item->href = state.style.href
    item->nextItem = 0

    If state.viewData->firstItem = 0 Then
        state.viewData->firstItem = item
    Else
        state.viewData->lastItem->nextItem = item
    End If
    state.viewData->lastItem = item
    state.viewData->itemCount += 1

    If state.lineFirstItem = 0 Then state.lineFirstItem = item
    state.cursorX += itemWidth
    If itemHeight > state.lineHeight Then state.lineHeight = itemHeight
    state.lineHasContent = -1
    htmlview_AppendPlain state.viewData, textValue
    Return -1
End Function


Private Function htmlview_AddImageItem( _
    ByRef state As HtmlViewLayoutState, _
    ByVal sourcePath As String, ByVal alternativeText As String _
) As Integer
    Dim As HtmlViewItem Ptr item
    Dim As RasterImage Ptr loadedImage
    Dim As String resolvedPath
    Dim As String imageError
    Dim As ULongInt imagePixels
    Dim As Integer imageProvided

    If state.viewData->imageHandler <> 0 Then
        imageProvided = Cast(Function( _
            ByVal As String, ByVal As Any Ptr, _
            ByRef As RasterImage Ptr, ByRef As String _
        ) As Integer, state.viewData->imageHandler)( _
            sourcePath, state.viewData->imageContext, loadedImage, imageError _
        )
        If imageProvided AndAlso loadedImage = 0 Then Return 0
        If imageProvided = 0 AndAlso loadedImage <> 0 Then
            /'
                A provider returning zero did not transfer ownership. Guard
                against an inconsistent callback so an accidental allocation
                cannot leak or bypass normal local-file resolution.
            '/
            rasterimage_Destroy loadedImage
            loadedImage = 0
        End If
    End If

    If loadedImage = 0 Then
        resolvedPath = htmlview_ResolveImagePath( _
            state.viewData->basePath, sourcePath _
        )
        If Len(resolvedPath) = 0 Then Return 0
        If Not rasterimage_LoadFile( _
            resolvedPath, loadedImage, imageError _
        ) Then Return 0
    End If
    If Not rasterimage_ScaleToFit( _
        loadedImage, state.availableWidth - state.style.indent, 0, imageError _
    ) Then
        rasterimage_Destroy loadedImage
        Return 0
    End If

    imagePixels = CULngInt(loadedImage->width) * loadedImage->height
    If state.decodedImagePixels > HTMLVIEW_MAX_IMAGE_PIXELS OrElse _
       imagePixels > HTMLVIEW_MAX_IMAGE_PIXELS - state.decodedImagePixels Then
        rasterimage_Destroy loadedImage
        state.viewData->layoutIncomplete = -1
        htmlview_SetError state.viewData, _
            "HTML images exceed the 33,554,432 pixel document safety limit"
        Return 0
    End If
    If state.viewData->itemCount >= HTMLVIEW_MAX_LAYOUT_ITEMS Then
        rasterimage_Destroy loadedImage
        state.viewData->layoutIncomplete = -1
        htmlview_SetError state.viewData, _
            "HTML layout reached the 65,536 item safety limit"
        Return 0
    End If

    If state.lineHasContent Then htmlview_NextLine state
    item = New HtmlViewItem
    If item = 0 Then
        rasterimage_Destroy loadedImage
        state.viewData->layoutIncomplete = -1
        htmlview_SetError state.viewData, "unable to allocate an HTML image item"
        Return 0
    End If

    item->itemKind = HTMLVIEW_ITEM_IMAGE
    item->x = state.style.indent
    item->y = state.cursorY
    item->w = loadedImage->width
    item->h = loadedImage->height
    item->text = alternativeText
    item->href = state.style.href
    item->image = loadedImage
    item->nextItem = 0

    If state.viewData->firstItem = 0 Then
        state.viewData->firstItem = item
    Else
        state.viewData->lastItem->nextItem = item
    End If
    state.viewData->lastItem = item
    state.viewData->itemCount += 1
    state.decodedImagePixels += imagePixels
    state.lineFirstItem = item
    state.cursorX = state.style.indent + item->w
    state.lineHeight = item->h
    state.lineHasContent = -1
    If Len(alternativeText) > 0 Then
        htmlview_AppendPlain state.viewData, "[" & alternativeText & "]"
    End If
    Return -1
End Function


Private Function htmlview_IsSmallPresentationImage( _
    ByVal attributeText As String _
) As Integer
    Dim As String widthText
    Dim As String heightText
    Dim As Integer imageWidth
    Dim As Integer imageHeight

    widthText = htmlview_GetAttribute(attributeText, "width")
    heightText = htmlview_GetAttribute(attributeText, "height")
    If Len(widthText) = 0 OrElse Len(heightText) = 0 Then Return 0

    imageWidth = Val(widthText)
    imageHeight = Val(heightText)
    If imageWidth < 0 OrElse imageHeight < 0 Then Return 0
    If imageWidth <= HTMLVIEW_DECORATIVE_IMAGE_MAXIMUM_DIMENSION AndAlso _
       imageHeight <= HTMLVIEW_DECORATIVE_IMAGE_MAXIMUM_DIMENSION Then
        Return -1
    End If
    Return 0
End Function


Private Sub htmlview_AlignCurrentLine(ByRef state As HtmlViewLayoutState)
    Dim As HtmlViewItem Ptr item
    Dim As Integer shiftAmount
    Dim As Integer usableWidth
    Dim As Integer usedWidth

    If state.lineFirstItem = 0 OrElse _
       state.style.alignment = HTMLVIEW_ALIGN_LEFT Then Exit Sub

    usableWidth = state.availableWidth - state.style.indent
    usedWidth = state.cursorX - state.style.indent
    If usableWidth <= usedWidth Then Exit Sub

    If state.style.alignment = HTMLVIEW_ALIGN_CENTER Then
        shiftAmount = (usableWidth - usedWidth) \ 2
    ElseIf state.style.alignment = HTMLVIEW_ALIGN_RIGHT Then
        shiftAmount = usableWidth - usedWidth
    End If

    item = state.lineFirstItem
    While item <> 0
        item->x += shiftAmount
        item = item->nextItem
    Wend
End Sub


Private Sub htmlview_NextLine( _
    ByRef state As HtmlViewLayoutState, ByVal extraGap As Integer _
)
    Dim As Integer advanceHeight

    htmlview_AlignCurrentLine state
    advanceHeight = state.lineHeight
    If advanceHeight < HTMLVIEW_DEFAULT_LINE_HEIGHT Then
        advanceHeight = HTMLVIEW_DEFAULT_LINE_HEIGHT
    End If

    state.cursorY += advanceHeight + extraGap
    state.cursorX = state.style.indent
    state.lineHeight = 0
    state.lineHasContent = 0
    state.pendingSpace = 0
    state.lineFirstItem = 0
    If state.tableActive AndAlso state.tableCellOpen Then
        /'
            A visual wrap inside a cell is not a new record in the plain-text
            representation.  Preserve one separating space so copied table
            data remains a useful tab-separated row.
        '/
        If Len(state.viewData->plainText) > 0 AndAlso _
           Not htmlview_IsWhiteSpace( _
               Asc(Right(state.viewData->plainText, 1)) _
           ) Then htmlview_AppendPlain state.viewData, " "
    Else
        htmlview_AppendPlainLine state.viewData
    End If
End Sub


Private Sub htmlview_BeginBlock( _
    ByRef state As HtmlViewLayoutState, ByVal marginBefore As Integer _
)
    If state.lineHasContent Then htmlview_NextLine state
    If state.cursorY > 0 Then state.cursorY += marginBefore
    state.cursorX = state.style.indent
End Sub


Private Sub htmlview_EndBlock( _
    ByRef state As HtmlViewLayoutState, ByVal marginAfter As Integer _
)
    If state.lineHasContent Then
        htmlview_NextLine state, marginAfter
    Else
        state.cursorY += marginAfter
        htmlview_AppendPlainLine state.viewData
    End If
End Sub


Private Function htmlview_AddRawFitted( _
    ByRef state As HtmlViewLayoutState, ByVal textValue As String _
) As Integer
    Dim As String chunk
    Dim As String character
    Dim As Long position
    Dim As Integer characterWidth

    position = 1
    While position <= Len(textValue)
        character = Mid(textValue, position, 1)
        characterWidth = htmlview_TextWidth(state.style, character)

        If state.cursorX > state.style.indent AndAlso _
           state.cursorX + characterWidth > state.availableWidth Then
            If Len(chunk) > 0 Then
                If Not htmlview_AddTextItem(state, chunk) Then Return 0
                chunk = ""
            End If
            htmlview_NextLine state
        End If

        If Len(chunk) > 0 AndAlso _
           state.cursorX + htmlview_TextWidth(state.style, chunk & character) > _
           state.availableWidth Then
            If Not htmlview_AddTextItem(state, chunk) Then Return 0
            chunk = ""
            htmlview_NextLine state
        End If

        chunk &= character
        position += 1
    Wend

    If Len(chunk) > 0 Then Return htmlview_AddTextItem(state, chunk)
    Return -1
End Function


Private Function htmlview_AddWord( _
    ByRef state As HtmlViewLayoutState, ByVal wordText As String _
) As Integer
    Dim As String displayText
    Dim As Integer wordWidth
    Dim As Integer spaceWidth

    If Len(wordText) = 0 Then Return -1
    displayText = wordText
    wordWidth = htmlview_TextWidth(state.style, wordText)

    If state.pendingSpace AndAlso state.lineHasContent Then
        spaceWidth = htmlview_TextWidth(state.style, " ")
        If state.cursorX + spaceWidth + wordWidth <= state.availableWidth Then
            displayText = " " & wordText
            wordWidth += spaceWidth
        Else
            htmlview_NextLine state
        End If
    End If

    If state.lineHasContent AndAlso _
       state.cursorX + wordWidth > state.availableWidth Then
        htmlview_NextLine state
        displayText = wordText
        wordWidth = htmlview_TextWidth(state.style, wordText)
    End If

    state.pendingSpace = 0
    If state.cursorX + wordWidth <= state.availableWidth OrElse _
       Len(wordText) = 1 Then
        Return htmlview_AddTextItem(state, displayText)
    End If

    Return htmlview_AddRawFitted(state, wordText)
End Function


Private Sub htmlview_LayoutNormalText( _
    ByRef state As HtmlViewLayoutState, ByVal sourceText As String, _
    ByVal decodeEntities As Integer = -1 _
)
    Dim As String decodedText
    Dim As String wordText
    Dim As Long position
    Dim As Long wordStart
    Dim As UByte character

    If decodeEntities Then
        decodedText = htmlview_DisplaySafeText( _
            htmlview_DecodeEntities(sourceText) _
        )
    Else
        decodedText = htmlview_DisplaySafeText(sourceText)
    End If
    position = 1

    While position <= Len(decodedText)
        character = Asc(Mid(decodedText, position, 1))
        If htmlview_IsWhiteSpace(character) Then
            state.pendingSpace = -1
            position += 1
            Continue While
        End If

        wordStart = position
        Do While position <= Len(decodedText)
            character = Asc(Mid(decodedText, position, 1))
            If htmlview_IsWhiteSpace(character) Then Exit Do
            position += 1
        Loop
        wordText = Mid(decodedText, wordStart, position - wordStart)
        If Not htmlview_AddWord(state, wordText) Then Exit Sub
    Wend
End Sub


Private Sub htmlview_LayoutPreText( _
    ByRef state As HtmlViewLayoutState, ByVal sourceText As String _
)
    Dim As String decodedText
    Dim As String lineText
    Dim As String character
    Dim As Long position
    Dim As Long lineStart

    decodedText = htmlview_DisplaySafeText( _
        htmlview_DecodeEntities(sourceText) _
    )
    position = 1
    lineStart = 1

    While position <= Len(decodedText) + 1
        If position > Len(decodedText) OrElse _
           Mid(decodedText, position, 1) = Chr(10) Then
            lineText = Mid(decodedText, lineStart, position - lineStart)
            lineText = htmlview_ReplaceAll(lineText, Chr(9), "    ")
            lineText = htmlview_ReplaceAll(lineText, Chr(13), "")
            If Len(lineText) > 0 Then
                If Not htmlview_AddRawFitted(state, lineText) Then Exit Sub
            End If
            htmlview_NextLine state
            lineStart = position + 1
        End If
        position += 1
    Wend
End Sub


Private Sub htmlview_AddRule(ByRef state As HtmlViewLayoutState)
    Dim As HtmlViewItem Ptr item

    If state.lineHasContent Then htmlview_NextLine state
    If state.viewData->itemCount >= HTMLVIEW_MAX_LAYOUT_ITEMS Then
        state.viewData->layoutIncomplete = -1
        htmlview_SetError state.viewData, _
            "HTML layout reached the 65,536 item safety limit"
        Exit Sub
    End If

    item = New HtmlViewItem
    If item = 0 Then
        state.viewData->layoutIncomplete = -1
        htmlview_SetError state.viewData, "unable to allocate an HTML rule item"
        Exit Sub
    End If

    item->itemKind = HTMLVIEW_ITEM_RULE
    item->x = state.style.indent
    item->y = state.cursorY + 4
    item->w = state.availableWidth - state.style.indent
    If item->w < 1 Then item->w = 1
    item->h = 1
    item->color = state.viewData->documentTextColor

    If state.viewData->firstItem = 0 Then
        state.viewData->firstItem = item
    Else
        state.viewData->lastItem->nextItem = item
    End If
    state.viewData->lastItem = item
    state.viewData->itemCount += 1
    state.cursorY += 10
    htmlview_AppendPlainLine state.viewData
End Sub


Private Function htmlview_AddTableCellBox( _
    ByRef state As HtmlViewLayoutState, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal boxWidth As Integer, ByVal backgroundColor As ULong _
) As HtmlViewItem Ptr
    Dim As HtmlViewItem Ptr item

    If state.viewData->itemCount >= HTMLVIEW_MAX_LAYOUT_ITEMS Then
        state.viewData->layoutIncomplete = -1
        htmlview_SetError state.viewData, _
            "HTML layout reached the 65,536 item safety limit"
        Return 0
    End If

    item = New HtmlViewItem
    If item = 0 Then
        state.viewData->layoutIncomplete = -1
        htmlview_SetError state.viewData, _
            "unable to allocate an HTML table cell item"
        Return 0
    End If

    item->itemKind = HTMLVIEW_ITEM_BOX
    item->x = x
    item->y = y
    item->w = boxWidth
    item->h = HTMLVIEW_DEFAULT_LINE_HEIGHT + _
        HTMLVIEW_TABLE_CELL_PADDING * 2
    item->color = theme_GetColor(GUI_COLOR_BORDER)
    item->backgroundColor = backgroundColor
    item->nextItem = 0

    If state.viewData->firstItem = 0 Then
        state.viewData->firstItem = item
    Else
        state.viewData->lastItem->nextItem = item
    End If
    state.viewData->lastItem = item
    state.viewData->itemCount += 1
    Return item
End Function


' -------------------------------------------------------------------------
' HTML tokenizer and tag handling
' -------------------------------------------------------------------------

Private Function htmlview_FindTagEnd( _
    ByVal htmlText As String, ByVal startPosition As Long _
) As Long
    Dim As Long position
    Dim As String character
    Dim As String quoteCharacter

    position = startPosition + 1
    While position <= Len(htmlText)
        character = Mid(htmlText, position, 1)
        If Len(quoteCharacter) > 0 Then
            If character = quoteCharacter Then quoteCharacter = ""
        ElseIf character = Chr(34) OrElse character = "'" Then
            quoteCharacter = character
        ElseIf character = ">" Then
            Return position
        End If
        position += 1
    Wend
    Return 0
End Function


Private Sub htmlview_TagInfo( _
    ByVal tagText As String, _
    ByRef tagName As String, _
    ByRef attributeText As String, _
    ByRef closingTag As Integer, _
    ByRef selfClosing As Integer _
)
    Dim As Long position
    Dim As Long nameStart
    Dim As UByte character

    tagText = Trim(tagText)
    tagName = ""
    attributeText = ""
    closingTag = 0
    selfClosing = 0
    If Len(tagText) = 0 Then Exit Sub

    If Left(tagText, 1) = "/" Then
        closingTag = -1
        tagText = LTrim(Mid(tagText, 2))
    End If
    If Right(tagText, 1) = "/" Then
        selfClosing = -1
        tagText = RTrim(Left(tagText, Len(tagText) - 1))
    End If

    position = 1
    nameStart = 1
    Do While position <= Len(tagText)
        character = Asc(Mid(tagText, position, 1))
        If htmlview_IsWhiteSpace(character) OrElse character = Asc("/") Then Exit Do
        position += 1
    Loop

    tagName = LCase(Mid(tagText, nameStart, position - nameStart))
    attributeText = Mid(tagText, position)
End Sub


' -------------------------------------------------------------------------
' Table measurement and layout
' -------------------------------------------------------------------------

Declare Sub htmlview_PopStyle( _
    ByRef state As HtmlViewLayoutState, ByVal tagName As String _
)
Declare Sub htmlview_OpenStyledTag( _
    ByRef state As HtmlViewLayoutState, _
    ByVal tagName As String, ByVal attributeText As String _
)

Private Function htmlview_TableSpan(ByVal attributeText As String) As Integer
    Dim As Integer spanValue

    spanValue = Val(htmlview_GetAttribute(attributeText, "colspan"))
    If spanValue < 1 Then spanValue = 1
    If spanValue > HTMLVIEW_MAX_TABLE_COLUMNS Then
        spanValue = HTMLVIEW_MAX_TABLE_COLUMNS
    End If
    Return spanValue
End Function


Private Sub htmlview_TableAppendMeasuredText( _
    ByRef cellText As String, ByVal textValue As String _
)
    Dim As Long remainingLength

    If Len(cellText) >= HTMLVIEW_TABLE_MEASURE_TEXT_LIMIT Then Exit Sub
    remainingLength = HTMLVIEW_TABLE_MEASURE_TEXT_LIMIT - Len(cellText)
    cellText &= Left(textValue, remainingLength)
End Sub


Private Function htmlview_IsLayoutTable( _
    ByVal htmlText As String, ByVal startPosition As Long, _
    ByVal attributeText As String _
) As Integer
    Dim As String roleText
    Dim As String borderText
    Dim As String tagText
    Dim As String tagName
    Dim As String nestedAttributes
    Dim As Long position
    Dim As Long tagStart
    Dim As Long tagEnd
    Dim As Long commentEnd
    Dim As Integer tableDepth = 1
    Dim As Integer closingTag
    Dim As Integer selfClosing
    Dim As Integer hasNestedTable
    Dim As Integer hasHeaderCell
    Dim As Integer hasCaption

    /'
        HTML 4 sites commonly use tables as a page-layout primitive.  Drawing
        those tables as data grids can leave a navigation column most of the
        viewport and squeeze the actual article into a few pixels.  Explicit
        presentation roles and nested tables are reliable layout signals.

        An explicit border of zero is also treated as presentation markup when
        the table has no header cells or caption.  A modern borderless data
        table normally omits the obsolete BORDER attribute entirely and keeps
        its TH or CAPTION structure, so it continues through the grid renderer.
    '/
    roleText = LCase(Trim(htmlview_GetAttribute(attributeText, "role")))
    If roleText = "presentation" OrElse roleText = "none" Then Return -1

    position = startPosition
    While position <= Len(htmlText) AndAlso tableDepth > 0
        tagStart = InStr(position, htmlText, "<")
        If tagStart = 0 Then Exit While
        If Mid(htmlText, tagStart, 4) = "<!--" Then
            commentEnd = InStr(tagStart + 4, htmlText, "-->")
            If commentEnd = 0 Then Exit While
            position = commentEnd + 3
            Continue While
        End If

        tagEnd = htmlview_FindTagEnd(htmlText, tagStart)
        If tagEnd = 0 Then Exit While
        tagText = Mid(htmlText, tagStart + 1, tagEnd - tagStart - 1)
        htmlview_TagInfo _
            tagText, tagName, nestedAttributes, closingTag, selfClosing
        position = tagEnd + 1

        If tagName = "table" Then
            If closingTag Then
                tableDepth -= 1
            Else
                If tableDepth = 1 Then hasNestedTable = -1
                If selfClosing = 0 Then tableDepth += 1
            End If
        ElseIf tableDepth = 1 Then
            If tagName = "th" AndAlso closingTag = 0 Then hasHeaderCell = -1
            If tagName = "caption" AndAlso closingTag = 0 Then hasCaption = -1
        End If
    Wend

    If hasHeaderCell OrElse hasCaption Then Return 0
    If hasNestedTable Then Return -1

    If htmlview_HasAttribute(attributeText, "border") Then
        borderText = Trim(htmlview_GetAttribute(attributeText, "border"))
        If Len(borderText) = 0 OrElse Val(borderText) = 0 Then Return -1
    End If
    Return 0
End Function


Private Sub htmlview_TableMeasureCell( _
    ByVal cellText As String, ByVal headerCell As Integer, _
    ByVal firstColumn As Integer, ByVal columnSpan As Integer, _
    preferredWidths() As Integer, minimumWidths() As Integer _
)
    Dim As String cleanText
    Dim As String wordText
    Dim As Long position
    Dim As Long wordStart
    Dim As Integer fontId
    Dim As Integer preferredWidth
    Dim As Integer minimumWidth
    Dim As Integer wordWidth
    Dim As Integer widthPerColumn
    Dim As Integer columnIndex

    If firstColumn < 0 OrElse _
       firstColumn >= HTMLVIEW_MAX_TABLE_COLUMNS Then Exit Sub
    If columnSpan < 1 Then columnSpan = 1
    If firstColumn + columnSpan > HTMLVIEW_MAX_TABLE_COLUMNS Then
        columnSpan = HTMLVIEW_MAX_TABLE_COLUMNS - firstColumn
    End If

    cleanText = htmlview_CollapseWhitespace( _
        htmlview_DisplaySafeText(htmlview_DecodeEntities(cellText)) _
    )
    fontId = BACKEND_FONT_ARIAL_10_REGULAR
    If headerCell Then fontId = BACKEND_FONT_ARIAL_12_BOLD
    preferredWidth = backend_GetTextWidthScaledFont(cleanText, fontId, 1) + _
        HTMLVIEW_TABLE_CELL_PADDING * 2
    minimumWidth = HTMLVIEW_TABLE_MINIMUM_COLUMN_WIDTH

    position = 1
    While position <= Len(cleanText)
        Do While position <= Len(cleanText) AndAlso _
            htmlview_IsWhiteSpace(Asc(Mid(cleanText, position, 1)))
            position += 1
        Loop
        wordStart = position
        Do While position <= Len(cleanText) AndAlso _
            Not htmlview_IsWhiteSpace(Asc(Mid(cleanText, position, 1)))
            position += 1
        Loop
        wordText = Mid(cleanText, wordStart, position - wordStart)
        If Len(wordText) > 0 Then
            wordWidth = backend_GetTextWidthScaledFont(wordText, fontId, 1) + _
                HTMLVIEW_TABLE_CELL_PADDING * 2
            If wordWidth > minimumWidth Then minimumWidth = wordWidth
        End If
    Wend

    widthPerColumn = (preferredWidth + columnSpan - 1) \ columnSpan
    wordWidth = (minimumWidth + columnSpan - 1) \ columnSpan
    For columnIndex = firstColumn To firstColumn + columnSpan - 1
        If widthPerColumn > preferredWidths(columnIndex) Then
            preferredWidths(columnIndex) = widthPerColumn
        End If
        If wordWidth > minimumWidths(columnIndex) Then
            minimumWidths(columnIndex) = wordWidth
        End If
    Next columnIndex
End Sub


Private Sub htmlview_TableFinishInspectionCell( _
    ByRef cellOpen As Integer, ByRef cellText As String, _
    ByVal headerCell As Integer, ByVal cellColumn As Integer, _
    ByVal cellSpan As Integer, preferredWidths() As Integer, _
    minimumWidths() As Integer _
)
    If cellOpen = 0 Then Exit Sub
    htmlview_TableMeasureCell _
        cellText, headerCell, cellColumn, cellSpan, _
        preferredWidths(), minimumWidths()
    cellOpen = 0
End Sub


Private Sub htmlview_TableInspectTag( _
    ByVal tagName As String, ByVal attributeText As String, _
    ByVal closingTag As Integer, ByVal selfClosing As Integer, _
    ByRef tableDepth As Integer, ByRef currentColumn As Integer, _
    ByRef maximumColumns As Integer, ByRef cellColumn As Integer, _
    ByRef cellSpan As Integer, ByRef cellOpen As Integer, _
    ByRef headerCell As Integer, ByRef cellText As String, _
    preferredWidths() As Integer, minimumWidths() As Integer _
)
    If tagName = "table" Then
        If closingTag Then
            tableDepth -= 1
        ElseIf selfClosing = 0 Then
            tableDepth += 1
        End If
        Exit Sub
    End If
    If tableDepth <> 1 Then Exit Sub

    If tagName = "tr" AndAlso closingTag = 0 Then
        htmlview_TableFinishInspectionCell _
            cellOpen, cellText, headerCell, cellColumn, cellSpan, _
            preferredWidths(), minimumWidths()
        currentColumn = 0
        Exit Sub
    End If
    If (tagName = "td" OrElse tagName = "th") AndAlso _
       closingTag = 0 Then
        htmlview_TableFinishInspectionCell _
            cellOpen, cellText, headerCell, cellColumn, cellSpan, _
            preferredWidths(), minimumWidths()
        If currentColumn >= HTMLVIEW_MAX_TABLE_COLUMNS Then Exit Sub

        cellColumn = currentColumn
        cellSpan = htmlview_TableSpan(attributeText)
        If cellColumn + cellSpan > HTMLVIEW_MAX_TABLE_COLUMNS Then
            cellSpan = HTMLVIEW_MAX_TABLE_COLUMNS - cellColumn
        End If
        currentColumn += cellSpan
        If currentColumn > maximumColumns Then maximumColumns = currentColumn
        cellText = ""
        headerCell = IIf(tagName = "th", -1, 0)
        cellOpen = -1
        If selfClosing Then htmlview_TableFinishInspectionCell _
            cellOpen, cellText, headerCell, cellColumn, cellSpan, _
            preferredWidths(), minimumWidths()
        Exit Sub
    End If
    If (tagName = "td" OrElse tagName = "th" OrElse tagName = "tr") AndAlso _
       closingTag Then
        htmlview_TableFinishInspectionCell _
            cellOpen, cellText, headerCell, cellColumn, cellSpan, _
            preferredWidths(), minimumWidths()
    ElseIf cellOpen AndAlso tagName = "br" Then
        htmlview_TableAppendMeasuredText cellText, " "
    End If
End Sub


Private Sub htmlview_TableAllocateColumns( _
    ByRef state As HtmlViewLayoutState, ByVal maximumColumns As Integer, _
    preferredWidths() As Integer, minimumWidths() As Integer _
)
    Dim As Integer columnIndex
    Dim As Integer preferredTotal
    Dim As Integer minimumTotal
    Dim As Integer flexibleTotal
    Dim As Integer remainingWidth
    Dim As Integer allocatedWidth
    Dim As Integer extraWidth
    Dim As Integer weight

    If maximumColumns < 1 Then maximumColumns = 1
    If maximumColumns > HTMLVIEW_MAX_TABLE_COLUMNS Then
        maximumColumns = HTMLVIEW_MAX_TABLE_COLUMNS
    End If
    state.tableColumnCount = maximumColumns

    For columnIndex = 0 To maximumColumns - 1
        If preferredWidths(columnIndex) < minimumWidths(columnIndex) Then
            preferredWidths(columnIndex) = minimumWidths(columnIndex)
        End If
        If preferredWidths(columnIndex) < HTMLVIEW_TABLE_MINIMUM_COLUMN_WIDTH Then
            preferredWidths(columnIndex) = HTMLVIEW_TABLE_MINIMUM_COLUMN_WIDTH
        End If
        If minimumWidths(columnIndex) < HTMLVIEW_TABLE_MINIMUM_COLUMN_WIDTH Then
            minimumWidths(columnIndex) = HTMLVIEW_TABLE_MINIMUM_COLUMN_WIDTH
        End If
        preferredTotal += preferredWidths(columnIndex)
        minimumTotal += minimumWidths(columnIndex)
    Next columnIndex

    remainingWidth = state.tableWidth
    If preferredTotal <= state.tableWidth Then
        extraWidth = state.tableWidth - preferredTotal
        For columnIndex = 0 To maximumColumns - 1
            allocatedWidth = preferredWidths(columnIndex)
            If preferredTotal > 0 Then allocatedWidth += _
                extraWidth * preferredWidths(columnIndex) \ preferredTotal
            If columnIndex = maximumColumns - 1 Then allocatedWidth = remainingWidth
            state.tableColumnWidths(columnIndex) = allocatedWidth
            remainingWidth -= allocatedWidth
        Next columnIndex
        Exit Sub
    End If
    If minimumTotal < state.tableWidth Then
        extraWidth = state.tableWidth - minimumTotal
        flexibleTotal = preferredTotal - minimumTotal
        For columnIndex = 0 To maximumColumns - 1
            weight = preferredWidths(columnIndex) - minimumWidths(columnIndex)
            allocatedWidth = minimumWidths(columnIndex)
            If flexibleTotal > 0 Then allocatedWidth += _
                extraWidth * weight \ flexibleTotal
            If columnIndex = maximumColumns - 1 Then allocatedWidth = remainingWidth
            state.tableColumnWidths(columnIndex) = allocatedWidth
            remainingWidth -= allocatedWidth
        Next columnIndex
        Exit Sub
    End If

    For columnIndex = 0 To maximumColumns - 1
        allocatedWidth = state.tableWidth \ maximumColumns
        If columnIndex = maximumColumns - 1 Then allocatedWidth = remainingWidth
        If allocatedWidth < 1 Then allocatedWidth = 1
        state.tableColumnWidths(columnIndex) = allocatedWidth
        remainingWidth -= allocatedWidth
    Next columnIndex
End Sub


Private Sub htmlview_InspectTable( _
    ByRef state As HtmlViewLayoutState, _
    ByVal htmlText As String, ByVal startPosition As Long _
)
    Dim As Integer preferredWidths(0 To HTMLVIEW_MAX_TABLE_COLUMNS - 1)
    Dim As Integer minimumWidths(0 To HTMLVIEW_MAX_TABLE_COLUMNS - 1)
    Dim As String tagText
    Dim As String tagName
    Dim As String attributeText
    Dim As String cellText
    Dim As Long position
    Dim As Long tagStart
    Dim As Long tagEnd
    Dim As Long commentEnd
    Dim As Integer closingTag
    Dim As Integer selfClosing
    Dim As Integer tableDepth = 1
    Dim As Integer currentColumn
    Dim As Integer maximumColumns
    Dim As Integer cellColumn
    Dim As Integer cellSpan = 1
    Dim As Integer cellOpen
    Dim As Integer headerCell

    position = startPosition
    While position <= Len(htmlText) AndAlso tableDepth > 0
        tagStart = InStr(position, htmlText, "<")
        If tagStart = 0 Then Exit While
        If cellOpen AndAlso tableDepth = 1 AndAlso tagStart > position Then
            htmlview_TableAppendMeasuredText _
                cellText, Mid(htmlText, position, tagStart - position)
        End If

        If Mid(htmlText, tagStart, 4) = "<!--" Then
            commentEnd = InStr(tagStart + 4, htmlText, "-->")
            If commentEnd = 0 Then Exit While
            position = commentEnd + 3
            Continue While
        End If
        tagEnd = htmlview_FindTagEnd(htmlText, tagStart)
        If tagEnd = 0 Then Exit While
        tagText = Mid(htmlText, tagStart + 1, tagEnd - tagStart - 1)
        htmlview_TagInfo _
            tagText, tagName, attributeText, closingTag, selfClosing
        position = tagEnd + 1
        htmlview_TableInspectTag _
            tagName, attributeText, closingTag, selfClosing, _
            tableDepth, currentColumn, maximumColumns, cellColumn, _
            cellSpan, cellOpen, headerCell, cellText, _
            preferredWidths(), minimumWidths()
    Wend

    htmlview_TableFinishInspectionCell _
        cellOpen, cellText, headerCell, cellColumn, cellSpan, _
        preferredWidths(), minimumWidths()
    htmlview_TableAllocateColumns _
        state, maximumColumns, preferredWidths(), minimumWidths()
End Sub


Private Sub htmlview_EndTableCell(ByRef state As HtmlViewLayoutState)
    Dim As Integer contentHeight
    Dim As Integer contentBottom

    If state.tableCellOpen = 0 Then Exit Sub
    If state.lineHasContent Then htmlview_AlignCurrentLine state
    contentHeight = state.lineHeight
    If contentHeight < HTMLVIEW_DEFAULT_LINE_HEIGHT Then
        contentHeight = HTMLVIEW_DEFAULT_LINE_HEIGHT
    End If
    contentBottom = state.cursorY + contentHeight + _
        HTMLVIEW_TABLE_CELL_PADDING
    If contentBottom > state.tableRowBottom Then
        state.tableRowBottom = contentBottom
    End If

    htmlview_PopStyle state, state.tableCellTag
    state.availableWidth = state.tableSavedAvailableWidth
    state.tableCurrentColumn += state.tableCellSpan
    state.tableCellOpen = 0
    state.tableCellTag = ""
    state.cursorX = state.tableX
    state.cursorY = state.tableRowTop
    state.lineHeight = 0
    state.lineHasContent = 0
    state.pendingSpace = 0
    state.lineFirstItem = 0
End Sub


Private Sub htmlview_EndTableRow(ByRef state As HtmlViewLayoutState)
    Dim As Integer boxIndex
    Dim As Integer rowHeight

    If state.tableRowOpen = 0 Then Exit Sub
    htmlview_EndTableCell state
    rowHeight = state.tableRowBottom - state.tableRowTop
    If rowHeight < 1 Then rowHeight = 1
    For boxIndex = 0 To state.tableCellBoxCount - 1
        If state.tableCellBoxes(boxIndex) <> 0 Then
            state.tableCellBoxes(boxIndex)->h = rowHeight
        End If
        state.tableCellBoxes(boxIndex) = 0
    Next boxIndex

    state.tableCellBoxCount = 0
    state.tableRowOpen = 0
    state.cursorX = state.tableX
    state.cursorY = state.tableRowBottom
    state.lineHeight = 0
    state.lineHasContent = 0
    state.pendingSpace = 0
    state.lineFirstItem = 0
    htmlview_AppendPlainLine state.viewData
End Sub


Private Sub htmlview_BeginTableRow(ByRef state As HtmlViewLayoutState)
    If state.tableRowOpen Then htmlview_EndTableRow state
    state.tableRowTop = state.cursorY
    state.tableRowBottom = state.cursorY + HTMLVIEW_DEFAULT_LINE_HEIGHT + _
        HTMLVIEW_TABLE_CELL_PADDING * 2
    state.tableCurrentColumn = 0
    state.tableCellBoxCount = 0
    state.tableRowOpen = -1
End Sub


Private Sub htmlview_BeginTableCell( _
    ByRef state As HtmlViewLayoutState, _
    ByVal tagName As String, ByVal attributeText As String _
)
    Dim As Integer cellX
    Dim As Integer cellWidth
    Dim As Integer columnIndex
    Dim As ULong backgroundColor
    Dim As HtmlViewItem Ptr cellBox

    If state.tableRowOpen = 0 Then htmlview_BeginTableRow state
    If state.tableCellOpen Then htmlview_EndTableCell state
    If state.tableCurrentColumn >= state.tableColumnCount Then Exit Sub

    If state.tableCurrentColumn > 0 Then
        htmlview_AppendPlain state.viewData, Chr(9)
    End If
    state.tableCellSpan = htmlview_TableSpan(attributeText)
    If state.tableCurrentColumn + state.tableCellSpan > _
       state.tableColumnCount Then
        state.tableCellSpan = _
            state.tableColumnCount - state.tableCurrentColumn
    End If
    If state.tableCellSpan < 1 Then state.tableCellSpan = 1

    cellX = state.tableX
    For columnIndex = 0 To state.tableCurrentColumn - 1
        cellX += state.tableColumnWidths(columnIndex)
    Next columnIndex
    For columnIndex = state.tableCurrentColumn To _
        state.tableCurrentColumn + state.tableCellSpan - 1
        cellWidth += state.tableColumnWidths(columnIndex)
    Next columnIndex
    If cellWidth < 1 Then cellWidth = 1

    state.tableSavedAvailableWidth = state.availableWidth
    state.tableCellTag = tagName
    htmlview_OpenStyledTag state, tagName, attributeText
    backgroundColor = state.viewData->documentBackgroundColor
    If tagName = "th" Then backgroundColor = state.viewData->codeBackgroundColor
    If state.style.hasBackground Then backgroundColor = state.style.backgroundColor
    cellBox = htmlview_AddTableCellBox( _
        state, cellX, state.tableRowTop, cellWidth, backgroundColor _
    )
    If state.tableCellBoxCount < HTMLVIEW_MAX_TABLE_COLUMNS Then
        state.tableCellBoxes(state.tableCellBoxCount) = cellBox
        state.tableCellBoxCount += 1
    End If

    state.style.indent = cellX + HTMLVIEW_TABLE_CELL_PADDING
    state.availableWidth = cellX + cellWidth - HTMLVIEW_TABLE_CELL_PADDING
    If state.availableWidth <= state.style.indent Then
        state.availableWidth = state.style.indent + 1
    End If
    state.cursorX = state.style.indent
    state.cursorY = state.tableRowTop + HTMLVIEW_TABLE_CELL_PADDING
    state.lineHeight = 0
    state.lineHasContent = 0
    state.pendingSpace = 0
    state.lineFirstItem = 0
    state.tableCellOpen = -1
End Sub


Private Sub htmlview_BeginTable( _
    ByRef state As HtmlViewLayoutState, _
    ByVal htmlText As String, ByVal contentStart As Long _
)
    htmlview_BeginBlock state, HTMLVIEW_PARAGRAPH_GAP
    state.tableActive = -1
    state.tableNestedDepth = 0
    state.tableX = state.style.indent
    state.tableWidth = state.availableWidth - state.tableX
    If state.tableWidth < 1 Then state.tableWidth = 1
    htmlview_InspectTable state, htmlText, contentStart
    state.cursorX = state.tableX
End Sub


Private Sub htmlview_EndTable(ByRef state As HtmlViewLayoutState)
    If state.tableActive = 0 Then Exit Sub
    htmlview_EndTableRow state
    state.tableActive = 0
    state.tableNestedDepth = 0
    state.cursorX = state.style.indent
    state.cursorY += HTMLVIEW_PARAGRAPH_GAP
    htmlview_AppendPlainLine state.viewData
End Sub


Private Sub htmlview_PushStyle( _
    ByRef state As HtmlViewLayoutState, ByVal tagName As String _
)
    If state.styleDepth >= HTMLVIEW_MAX_STYLE_DEPTH Then
        state.viewData->layoutIncomplete = -1
        htmlview_SetError state.viewData, _
            "HTML nesting reached the 64-level style safety limit"
        Exit Sub
    End If

    state.styleStack(state.styleDepth).tagName = tagName
    state.styleStack(state.styleDepth).previousStyle = state.style
    state.styleDepth += 1
End Sub


Private Sub htmlview_PopStyle( _
    ByRef state As HtmlViewLayoutState, ByVal tagName As String _
)
    Dim As Long frameIndex

    For frameIndex = state.styleDepth - 1 To 0 Step -1
        If state.styleStack(frameIndex).tagName = tagName Then
            state.style = state.styleStack(frameIndex).previousStyle
            state.styleDepth = frameIndex
            Exit Sub
        End If
    Next frameIndex
End Sub


Declare Sub htmlview_ApplyCssDeclarations( _
    ByRef state As HtmlViewLayoutState, ByVal styleText As String, _
    ByVal tagName As String _
)


Private Sub htmlview_ApplyInlineStyle( _
    ByRef state As HtmlViewLayoutState, ByVal attributeText As String _
)
    Dim As String styleText

    styleText = htmlview_GetAttribute(attributeText, "style")
    If Len(styleText) = 0 Then Exit Sub
    htmlview_ApplyCssDeclarations state, styleText, ""
End Sub


Private Sub htmlview_ApplyCssDeclarations( _
    ByRef state As HtmlViewLayoutState, ByVal styleText As String, _
    ByVal tagName As String _
)

    Dim As String valueText
    Dim As ULong colorValue
    Dim As Integer leftSpacing
    If Len(styleText) = 0 Then Exit Sub

    valueText = htmlview_GetCssValue(styleText, "color")
    If htmlview_ParseColor(valueText, colorValue) Then state.style.color = colorValue

    valueText = htmlview_GetCssValue(styleText, "background-color")
    If valueText = "" Then valueText = htmlview_GetCssValue(styleText, "background")
    If htmlview_ParseColor(valueText, colorValue) Then
        If tagName = "body" Then
            state.viewData->documentBackgroundColor = colorValue
        Else
            state.style.backgroundColor = colorValue
            state.style.hasBackground = -1
            state.style.codeBackground = -1
        End If
    End If

    valueText = LCase(htmlview_GetCssValue(styleText, "font-weight"))
    If valueText = "bold" OrElse Val(valueText) >= 600 Then
        state.style.fontId = BACKEND_FONT_ARIAL_12_BOLD
    ElseIf valueText = "normal" Then
        state.style.fontId = BACKEND_FONT_ARIAL_10_REGULAR
    End If

    valueText = LCase(htmlview_GetCssValue(styleText, "text-decoration"))
    If valueText <> "" Then _
        state.style.underline = IIf(InStr(valueText, "underline") > 0, -1, 0)

    valueText = LCase(htmlview_GetCssValue(styleText, "white-space"))
    If valueText = "pre" OrElse valueText = "pre-wrap" Then
        state.style.preformatted = -1
    End If

    valueText = LCase(htmlview_GetCssValue(styleText, "font-family"))
    If InStr(valueText, "courier") > 0 OrElse _
       InStr(valueText, "monospace") > 0 Then
        state.style.fontId = BACKEND_FONT_DEFAULT
    End If

    valueText = htmlview_GetCssValue(styleText, "text-align")
    If Len(valueText) > 0 Then state.style.alignment = _
        htmlview_ParseAlignment(valueText)

    leftSpacing = htmlview_CssPaddingLeft(styleText)
    If leftSpacing > 0 Then
        state.style.indent += leftSpacing
        If state.style.indent > state.availableWidth - 8 Then _
            state.style.indent = state.availableWidth - 8
        If state.style.indent < 0 Then state.style.indent = 0
        state.cursorX = state.style.indent
    End If
End Sub


Private Sub htmlview_ApplyStylesheet( _
    ByRef state As HtmlViewLayoutState, ByVal tagName As String, _
    ByVal attributeText As String _
)

    Dim As HtmlViewData Ptr viewData

    viewData = state.viewData
    If viewData = 0 Then Exit Sub
    For ruleIndex As Integer = 0 To viewData->cssRuleCount - 1
        If htmlview_CssSelectorMatches( _
            viewData->cssRules(ruleIndex).selectorText, _
            tagName, attributeText _
        ) Then
            htmlview_ApplyCssDeclarations _
                state, viewData->cssRules(ruleIndex).declarationText, tagName
        End If
    Next ruleIndex
End Sub


Private Sub htmlview_OpenStyledTag( _
    ByRef state As HtmlViewLayoutState, _
    ByVal tagName As String, ByVal attributeText As String _
)
    Dim As String valueText
    Dim As ULong colorValue

    htmlview_PushStyle state, tagName

    Select Case tagName
    Case "b", "strong", "th"
        state.style.fontId = BACKEND_FONT_ARIAL_12_BOLD
    Case "big"
        state.style.scaleX = 2
        state.style.scaleY = 2
    Case "u", "ins"
        state.style.underline = -1
    Case "mark"
        state.style.codeBackground = -1
        state.style.backgroundColor = RGB(255, 244, 160)
    Case "code", "tt", "kbd", "samp"
        state.style.fontId = BACKEND_FONT_DEFAULT
        state.style.codeBackground = -1
        state.style.backgroundColor = state.viewData->codeBackgroundColor
    Case "a"
        state.style.href = htmlview_GetAttribute(attributeText, "href")
        If Len(state.style.href) > 0 Then
            state.style.color = state.viewData->documentLinkColor
            state.style.underline = -1
        End If
    Case "font"
        valueText = htmlview_GetAttribute(attributeText, "color")
        If htmlview_ParseColor(valueText, colorValue) Then
            state.style.color = colorValue
        End If
        valueText = Trim(htmlview_GetAttribute(attributeText, "size"))
        If Left(valueText, 1) = "+" OrElse Val(valueText) >= 5 Then
            state.style.scaleX = 2
            state.style.scaleY = 2
        End If
    End Select

    htmlview_ApplyStylesheet state, tagName, attributeText
    htmlview_ApplyInlineStyle state, attributeText
End Sub


Private Sub htmlview_HandleBody( _
    ByRef state As HtmlViewLayoutState, ByVal attributeText As String _
)
    Dim As String valueText
    Dim As ULong colorValue

    htmlview_ApplyStylesheet state, "body", attributeText

    valueText = htmlview_GetAttribute(attributeText, "bgcolor")
    If htmlview_ParseColor(valueText, colorValue) Then
        state.viewData->documentBackgroundColor = colorValue
    End If
    valueText = htmlview_GetAttribute(attributeText, "text")
    If htmlview_ParseColor(valueText, colorValue) Then
        state.viewData->documentTextColor = colorValue
        state.style.color = colorValue
    End If
    valueText = htmlview_GetAttribute(attributeText, "link")
    If htmlview_ParseColor(valueText, colorValue) Then
        state.viewData->documentLinkColor = colorValue
    End If
End Sub


Private Function htmlview_HandleSemanticTag( _
    ByRef state As HtmlViewLayoutState, _
    ByVal tagName As String, ByVal attributeText As String, _
    ByVal closingTag As Integer, ByVal selfClosing As Integer _
) As Integer
    Dim As Integer blockGap
    Dim As String valueText

    Select Case tagName
    Case "header", "main", "section", "article", "aside", "footer"
        blockGap = HTMLVIEW_PARAGRAPH_GAP
    Case "nav", "details", "figure", "figcaption", "address"
        blockGap = 2
    Case "summary"
        blockGap = 1
    Case Else
        Return 0
    End Select

    If closingTag Then
        htmlview_EndBlock state, blockGap
        htmlview_PopStyle state, tagName
        If tagName = "nav" AndAlso state.navigationDepth > 0 Then
            state.navigationDepth -= 1
        End If
        Return -1
    End If

    htmlview_BeginBlock state, blockGap
    htmlview_PushStyle state, tagName
    If tagName = "nav" Then state.navigationDepth += 1
    If tagName = "summary" Then
        state.style.fontId = BACKEND_FONT_ARIAL_12_BOLD
    ElseIf tagName = "figcaption" Then
        state.style.fontId = BACKEND_FONT_ARIAL_10_REGULAR
    End If
    htmlview_ApplyStylesheet state, tagName, attributeText
    valueText = htmlview_GetAttribute(attributeText, "align")
    If Len(valueText) > 0 Then state.style.alignment = _
        htmlview_ParseAlignment(valueText)
    htmlview_ApplyInlineStyle state, attributeText

    If selfClosing Then
        htmlview_EndBlock state, blockGap
        htmlview_PopStyle state, tagName
        If tagName = "nav" AndAlso state.navigationDepth > 0 Then
            state.navigationDepth -= 1
        End If
    End If
    Return -1
End Function


Private Sub htmlview_HandleImageTag( _
    ByRef state As HtmlViewLayoutState, ByVal attributeText As String _
)
    Dim As String alternativeText
    Dim As Integer alternativeTextPresent

    alternativeTextPresent = htmlview_HasAttribute(attributeText, "alt")
    alternativeText = htmlview_GetAttribute(attributeText, "alt")
    If alternativeTextPresent = 0 Then
        alternativeText = htmlview_GetAttribute(attributeText, "title")
        If Len(alternativeText) = 0 AndAlso _
           htmlview_IsSmallPresentationImage(attributeText) = 0 Then
            alternativeText = "Image"
        End If
    End If

    If htmlview_AddImageItem( _
        state, htmlview_GetAttribute(attributeText, "src"), alternativeText _
    ) Then
        htmlview_NextLine state, 2
        Exit Sub
    End If

    /'
        Attribute values are decoded by htmlview_GetAttribute.  Passing ALT
        through the entity decoder again would turn a literal "&amp;" sequence
        into just "&".
    '/
    If Len(alternativeText) > 0 Then
        htmlview_LayoutNormalText state, "[" & alternativeText & "]", 0
    End If
End Sub


Private Function htmlview_FrameLabel( _
    ByVal attributeText As String, ByVal sourceText As String _
) As String
    Dim As String labelText

    labelText = Trim(htmlview_GetAttribute(attributeText, "title"))
    If Len(labelText) = 0 Then
        labelText = Trim(htmlview_GetAttribute(attributeText, "name"))
    End If

    /'
        The archived FBXL issues use the conventional frame names "index"
        and "main".  Human labels make their flattened fallback immediately
        understandable while arbitrary frame names remain intact.
    '/
    Select Case LCase(labelText)
    Case "index"
        labelText = "Contents"
    Case "main"
        labelText = "Main page"
    End Select

    If Len(labelText) = 0 Then labelText = sourceText
    If Len(labelText) = 0 Then labelText = "Embedded page"
    Return htmlview_DisplaySafeText(labelText)
End Function


Private Sub htmlview_HandleFrameTag( _
    ByRef state As HtmlViewLayoutState, ByVal attributeText As String _
)
    Dim As String sourceText
    Dim As String labelText
    Dim As Integer sourceIndex

    sourceText = Trim(htmlview_GetAttribute(attributeText, "src"))
    If Len(sourceText) = 0 Then
        state.interactiveFallbackNeeded = -1
        Exit Sub
    End If

    /'
        FRAME elements are obsolete, but silently ignoring them makes an
        entire frameset document blank.  Expose each unique source as an
        ordinary application-routed link.  The viewer still performs no
        network access and does not create nested browsing contexts.
    '/
    For sourceIndex = 0 To state.frameSourceCount - 1
        If state.frameSources(sourceIndex) = sourceText Then Exit Sub
    Next sourceIndex
    If state.frameSourceCount >= HTMLVIEW_MAX_FRAME_LINKS Then Exit Sub

    state.frameSources(state.frameSourceCount) = sourceText
    state.frameSourceCount += 1
    labelText = htmlview_FrameLabel(attributeText, sourceText)

    htmlview_BeginBlock state, 1
    htmlview_PushStyle state, "frame-link"
    state.style.href = sourceText
    state.style.underline = -1
    state.style.color = state.viewData->documentLinkColor
    htmlview_LayoutNormalText state, labelText, 0
    htmlview_PopStyle state, "frame-link"
    htmlview_EndBlock state, 1
End Sub


Private Sub htmlview_HandleDefinitionTag( _
    ByRef state As HtmlViewLayoutState, ByVal tagName As String, _
    ByVal closingTag As Integer _
)
    Dim As Integer definitionIndex

    If tagName = "dl" Then
        If closingTag Then
            If state.definitionDepth > 0 Then
                definitionIndex = state.definitionDepth - 1
            Else
                definitionIndex = -1
            End If
            If definitionIndex >= 0 AndAlso _
               Len(state.definitionTags(definitionIndex)) > 0 Then
                htmlview_EndBlock state, 1
                htmlview_PopStyle _
                    state, state.definitionTags(definitionIndex)
                state.definitionTags(definitionIndex) = ""
            End If
            If state.definitionDepth > 0 Then state.definitionDepth -= 1
            htmlview_EndBlock state, HTMLVIEW_PARAGRAPH_GAP
        Else
            htmlview_BeginBlock state, HTMLVIEW_PARAGRAPH_GAP
            If state.definitionDepth < HTMLVIEW_MAX_LIST_DEPTH Then
                state.definitionTags(state.definitionDepth) = ""
                state.definitionDepth += 1
            Else
                state.viewData->layoutIncomplete = -1
                htmlview_SetError state.viewData, _
                    "HTML definition lists reached the 16-level nesting safety limit"
            End If
        End If
        Exit Sub
    End If

    If state.definitionDepth > 0 Then
        definitionIndex = state.definitionDepth - 1
    Else
        definitionIndex = -1
    End If
    If closingTag Then
        If definitionIndex >= 0 AndAlso _
           state.definitionTags(definitionIndex) = tagName Then
            htmlview_EndBlock state, 1
            htmlview_PopStyle state, tagName
            state.definitionTags(definitionIndex) = ""
        End If
        Exit Sub
    End If

    If definitionIndex >= 0 AndAlso _
       Len(state.definitionTags(definitionIndex)) > 0 Then
        htmlview_EndBlock state, 1
        htmlview_PopStyle state, state.definitionTags(definitionIndex)
    End If
    htmlview_BeginBlock state, 1
    htmlview_PushStyle state, tagName
    If tagName = "dt" Then
        state.style.fontId = BACKEND_FONT_ARIAL_12_BOLD
    Else
        state.style.indent += HTMLVIEW_LIST_INDENT
        state.cursorX = state.style.indent
    End If
    If definitionIndex >= 0 Then _
        state.definitionTags(definitionIndex) = tagName
End Sub


Private Sub htmlview_RecordAnchor( _
    ByRef state As HtmlViewLayoutState, _
    ByVal tagName As String, ByVal attributeText As String _
)

    Dim As String anchorName

    If state.viewData = 0 Then Exit Sub
    anchorName = htmlview_GetAttribute(attributeText, "id")
    If Len(anchorName) = 0 AndAlso tagName = "a" Then _
        anchorName = htmlview_GetAttribute(attributeText, "name")
    If Len(anchorName) = 0 Then Exit Sub

    For anchorIndex As Integer = 0 To state.viewData->anchorCount - 1
        If LCase(state.viewData->anchors(anchorIndex).nameText) = _
           LCase(anchorName) Then Exit Sub
    Next anchorIndex

    If state.viewData->anchorCount >= HTMLVIEW_MAX_ANCHORS Then Exit Sub
    With state.viewData->anchors(state.viewData->anchorCount)
        .nameText = anchorName
        .y = state.cursorY
    End With
    state.viewData->anchorCount += 1

End Sub


Private Sub htmlview_HandleTag( _
    ByRef state As HtmlViewLayoutState, _
    ByVal tagName As String, ByVal attributeText As String, _
    ByVal closingTag As Integer, ByVal selfClosing As Integer _
)
    Dim As String valueText
    Dim As String prefixText
    Dim As Integer headingLevel

    If closingTag = 0 Then _
        htmlview_RecordAnchor(state, tagName, attributeText)

    If htmlview_HandleSemanticTag( _
        state, tagName, attributeText, closingTag, selfClosing _
    ) Then Exit Sub

    Select Case tagName
    Case "br"
        htmlview_NextLine state
    Case "hr"
        htmlview_AddRule state
    Case "img"
        htmlview_HandleImageTag state, attributeText
    Case "frame", "iframe"
        If closingTag = 0 Then htmlview_HandleFrameTag state, attributeText
    Case "canvas", "object", "embed"
        If closingTag = 0 Then state.interactiveFallbackNeeded = -1
    Case "body"
        If Not closingTag Then htmlview_HandleBody state, attributeText
    Case "p", "div", "center", "blockquote"
        If closingTag Then
            htmlview_EndBlock state, HTMLVIEW_PARAGRAPH_GAP
            htmlview_PopStyle state, tagName
        Else
            htmlview_BeginBlock state, HTMLVIEW_PARAGRAPH_GAP
            htmlview_PushStyle state, tagName
            If tagName = "center" Then
                state.style.alignment = HTMLVIEW_ALIGN_CENTER
            ElseIf tagName = "blockquote" Then
                state.style.indent += HTMLVIEW_LIST_INDENT
                state.cursorX = state.style.indent
            End If
            htmlview_ApplyStylesheet state, tagName, attributeText
            valueText = htmlview_GetAttribute(attributeText, "align")
            If Len(valueText) > 0 Then state.style.alignment = _
                htmlview_ParseAlignment(valueText)
            htmlview_ApplyInlineStyle state, attributeText
        End If
    Case "h1", "h2", "h3", "h4", "h5", "h6"
        If closingTag Then
            htmlview_EndBlock state, HTMLVIEW_PARAGRAPH_GAP
            htmlview_PopStyle state, tagName
        Else
            htmlview_BeginBlock state, HTMLVIEW_PARAGRAPH_GAP
            htmlview_PushStyle state, tagName
            headingLevel = Val(Mid(tagName, 2))
            state.style.fontId = BACKEND_FONT_ARIAL_12_BOLD
            If headingLevel = 1 Then
                ' Keep the local document heading face while applying CSS.
                state.style.fontId = BACKEND_FONT_LIBERATION_SERIF_18_REGULAR
            End If
            htmlview_ApplyStylesheet state, tagName, attributeText
            valueText = htmlview_GetAttribute(attributeText, "align")
            If Len(valueText) > 0 Then state.style.alignment = _
                htmlview_ParseAlignment(valueText)
            htmlview_ApplyInlineStyle state, attributeText
        End If
    Case "pre"
        If closingTag Then
            htmlview_EndBlock state, HTMLVIEW_PARAGRAPH_GAP
            htmlview_PopStyle state, tagName
        Else
            htmlview_BeginBlock state, HTMLVIEW_PARAGRAPH_GAP
            htmlview_PushStyle state, tagName
            state.style.preformatted = -1
            state.style.fontId = BACKEND_FONT_DEFAULT
            state.style.codeBackground = -1
            state.style.backgroundColor = state.viewData->codeBackgroundColor
            htmlview_ApplyStylesheet state, tagName, attributeText
            htmlview_ApplyInlineStyle state, attributeText
        End If
    Case "ul", "ol"
        If closingTag Then
            htmlview_EndBlock state, 2
            htmlview_PopStyle state, tagName
            If state.listDepth > 0 Then state.listDepth -= 1
        Else
            htmlview_BeginBlock state, 2
            htmlview_PushStyle state, tagName
            If state.listDepth < HTMLVIEW_MAX_LIST_DEPTH Then
                state.listOrdered(state.listDepth) = IIf(tagName = "ol", -1, 0)
                state.listCounter(state.listDepth) = 0
                state.listDepth += 1
            Else
                state.viewData->layoutIncomplete = -1
                htmlview_SetError state.viewData, _
                    "HTML lists reached the 16-level nesting safety limit"
            End If
            state.style.indent += HTMLVIEW_LIST_INDENT
            state.cursorX = state.style.indent
            htmlview_ApplyStylesheet state, tagName, attributeText
        End If
    Case "li"
        If closingTag Then
            htmlview_EndBlock state, 1
        Else
            htmlview_BeginBlock state, 1
            prefixText = "* "
            If state.listDepth > 0 AndAlso _
               state.listOrdered(state.listDepth - 1) Then
                state.listCounter(state.listDepth - 1) += 1
                prefixText = LTrim(Str(state.listCounter(state.listDepth - 1))) & ". "
            End If
            htmlview_AddWord state, prefixText
        End If
    Case "dl", "dt", "dd"
        htmlview_HandleDefinitionTag state, tagName, closingTag
    Case "b", "strong", "u", "ins", "i", "em", "small", "big", _
         "code", "tt", "kbd", "samp", "a", "font", "span", _
         "mark", "s", "del", "sub", "sup", "q", "cite", "abbr", _
         "time", "data", "var", "dfn", "bdi", "bdo"
        If closingTag Then
            htmlview_PopStyle state, tagName
        Else
            If tagName = "a" AndAlso state.navigationDepth > 0 AndAlso _
               state.lineHasContent Then htmlview_NextLine state
            If tagName = "a" AndAlso state.navigationDepth = 0 AndAlso _
               state.lineHasContent AndAlso state.viewData->lastItem <> 0 AndAlso _
               Len(state.viewData->lastItem->href) > 0 Then
                state.pendingSpace = -1
            End If
            If (tagName = "em" OrElse tagName = "cite") AndAlso _
               state.lineHasContent Then state.pendingSpace = -1
            htmlview_OpenStyledTag state, tagName, attributeText
            If selfClosing Then htmlview_PopStyle state, tagName
        End If
    End Select
End Sub


Private Function htmlview_ConsumeEmptyContainer( _
    ByVal htmlText As String, ByRef position As Long, _
    ByVal containerName As String _
) As Integer
    Dim As String tagText
    Dim As String tagName
    Dim As String attributeText
    Dim As Long scanPosition
    Dim As Long tagEnd
    Dim As Integer closingTag
    Dim As Integer selfClosing

    /'
        Empty DIV elements are frequently graphical controls or CSS spacers.
        They have no content to preserve, so a display-only viewer should not
        allocate a blank paragraph for them.  Only an immediately closing tag
        separated by ordinary whitespace is consumed here; nested or textual
        containers continue through the normal parser.
    '/
    scanPosition = position
    While scanPosition <= Len(htmlText) AndAlso _
          htmlview_IsWhiteSpace(Asc(Mid(htmlText, scanPosition, 1)))
        scanPosition += 1
    Wend
    If scanPosition > Len(htmlText) OrElse _
       Mid(htmlText, scanPosition, 2) <> "</" Then Return 0

    tagEnd = htmlview_FindTagEnd(htmlText, scanPosition)
    If tagEnd = 0 Then Return 0
    tagText = Mid(htmlText, scanPosition + 1, tagEnd - scanPosition - 1)
    htmlview_TagInfo _
        tagText, tagName, attributeText, closingTag, selfClosing
    If closingTag = 0 OrElse tagName <> containerName Then Return 0

    position = tagEnd + 1
    Return -1
End Function


Private Function htmlview_FindRawClosingTag( _
    ByVal htmlText As String, ByVal startPosition As Long, _
    ByVal tagName As String _
) As Long
    Dim As String closingText
    Dim As Long position
    Dim As Long textOffset
    Dim As Long boundaryPosition
    Dim As Integer sourceCode
    Dim As Integer expectedCode
    Dim As Integer matched

    /'
        SCRIPT and STYLE are raw-text elements.  Less-than and greater-than
        characters inside their content are data, not HTML tags.  Searching
        only for the ASCII case-insensitive closing name avoids both false
        tokenization and a costly scan of large JavaScript application state.
    '/
    closingText = "</" & LCase(tagName)
    position = startPosition
    Do
        position = InStr(position, htmlText, "<")
        If position = 0 Then Return 0
        If position + Len(closingText) - 1 <= Len(htmlText) Then
            matched = -1
            For textOffset = 1 To Len(closingText)
                sourceCode = Asc(Mid( _
                    htmlText, position + textOffset - 1, 1 _
                ))
                If sourceCode >= Asc("A") AndAlso sourceCode <= Asc("Z") Then
                    sourceCode = sourceCode + (Asc("a") - Asc("A"))
                End If
                expectedCode = Asc(Mid(closingText, textOffset, 1))
                If sourceCode <> expectedCode Then
                    matched = 0
                    Exit For
                End If
            Next textOffset
            If matched Then
                boundaryPosition = position + Len(closingText)
                If boundaryPosition > Len(htmlText) Then Return position
                sourceCode = Asc(Mid(htmlText, boundaryPosition, 1))
                If sourceCode = Asc(">") OrElse _
                   htmlview_IsWhiteSpace(sourceCode) Then Return position
            End If
        End If
        position += 1
    Loop
End Function


Private Sub htmlview_SkipElementContent( _
    ByRef state As HtmlViewLayoutState, ByVal htmlText As String, _
    ByRef position As Long, ByVal tagName As String _
)
    Dim As Long closingStart
    Dim As Long closingEnd

    closingStart = htmlview_FindRawClosingTag( _
        htmlText, position, tagName _
    )
    If closingStart > 0 Then
        closingEnd = htmlview_FindTagEnd(htmlText, closingStart)
    End If
    If closingStart = 0 OrElse closingEnd = 0 Then
        state.viewData->layoutIncomplete = -1
        htmlview_SetError state.viewData, _
            "unterminated HTML " & UCase(tagName) & " element"
        position = Len(htmlText) + 1
        Exit Sub
    End If
    position = closingEnd + 1
End Sub


Private Function htmlview_ParseElapsedSeconds( _
    ByVal startTime As Double _
) As Double
    Dim As Double currentTime = Timer

    /'
        TIMER wraps at midnight on the supported runtimes.  Layout operations
        last seconds rather than days, so one wrap can be normalized safely.
    '/
    If currentTime < startTime Then currentTime += HTMLVIEW_SECONDS_PER_DAY
    Return currentTime - startTime
End Function


Private Sub htmlview_InitializeParseContext( _
    ByRef parseContext As HtmlViewParseContext, _
    ByVal viewData As HtmlViewData Ptr, ByVal availableWidth As Integer _
)
    /'
        The parser owns no hidden global cursor.  Keeping its complete state in
        this context lets the ordinary GUI update call resume parsing without
        a worker thread or access to partially built render items.
    '/
    parseContext.state.viewData = viewData
    parseContext.state.availableWidth = availableWidth
    parseContext.state.style.fontId = BACKEND_FONT_ARIAL_10_REGULAR
    parseContext.state.style.scaleX = 1
    parseContext.state.style.scaleY = 1
    parseContext.state.style.color = viewData->documentTextColor
    parseContext.state.style.backgroundColor = viewData->codeBackgroundColor
    parseContext.state.style.alignment = HTMLVIEW_ALIGN_LEFT
    parseContext.state.cursorX = 0
    parseContext.position = 1
    parseContext.parseIteration = 0
    parseContext.workSeconds = 0.0
    parseContext.complete = 0
End Sub


' fblint: disable-next-line FBL110,FBL111 -- This bounded step advances markup and style-stack state together.
Private Function htmlview_ParseContextStep( _
    ByRef parseContext As HtmlViewParseContext, _
    ByVal timeBudgetMilliseconds As Integer _
) As Integer
    Dim As HtmlViewLayoutState state
    Dim As HtmlViewData Ptr viewData
    Dim As String htmlText
    Dim As String textValue
    Dim As String tagText
    Dim As String tagName
    Dim As String attributeText
    Dim As Long position
    Dim As Long tagStart
    Dim As Long tagEnd
    Dim As Long commentEnd
    Dim As Integer closingTag
    Dim As Integer selfClosing
    Dim As Long parseIteration
    Dim As Double parseStartTime
    Dim As Double elapsedSeconds
    Dim As Double sliceSeconds
    Dim As Integer parseDone
    Dim As Integer yielded

    If parseContext.complete Then Return -1
    state = parseContext.state
    viewData = state.viewData
    If viewData = 0 Then
        parseContext.complete = -1
        Return -1
    End If

    If timeBudgetMilliseconds < 1 Then timeBudgetMilliseconds = 1
    If timeBudgetMilliseconds > HTMLVIEW_MAXIMUM_LOAD_BUDGET_MS Then
        timeBudgetMilliseconds = HTMLVIEW_MAXIMUM_LOAD_BUDGET_MS
    End If
    sliceSeconds = CDbl(timeBudgetMilliseconds) / 1000.0
    htmlText = viewData->sourceHtml
    position = parseContext.position
    parseIteration = parseContext.parseIteration
    parseStartTime = Timer

    While position <= Len(htmlText)
        parseIteration += 1
        If parseIteration Mod HTMLVIEW_PARSE_TIME_CHECK_INTERVAL = 0 Then
            elapsedSeconds = htmlview_ParseElapsedSeconds(parseStartTime)
            If parseContext.workSeconds + elapsedSeconds > _
               HTMLVIEW_MAX_PARSE_SECONDS Then
                viewData->layoutIncomplete = -1
                htmlview_SetError viewData, _
                    "HTML layout exceeded the 3-second safety budget"
                parseDone = -1
                Exit While
            End If
            If elapsedSeconds >= sliceSeconds Then
                yielded = -1
                Exit While
            End If
        End If
        tagStart = InStr(position, htmlText, "<")
        If tagStart = 0 Then
            textValue = Mid(htmlText, position)
            If state.inTitle Then
                viewData->titleText &= htmlview_DisplaySafeText( _
                    htmlview_DecodeEntities(textValue) _
                )
            ElseIf state.inHead = 0 AndAlso state.ignoredDepth = 0 AndAlso _
                   state.ignoredTitleDepth = 0 AndAlso _
                   (state.tableActive = 0 OrElse state.tableCellOpen) Then
                If state.style.preformatted Then
                    htmlview_LayoutPreText state, textValue
                Else
                    htmlview_LayoutNormalText state, textValue
                End If
            End If
            parseDone = -1
            Exit While
        End If

        If tagStart > position Then
            textValue = Mid(htmlText, position, tagStart - position)
            If state.inTitle Then
                viewData->titleText &= htmlview_DisplaySafeText( _
                    htmlview_DecodeEntities(textValue) _
                )
            ElseIf state.inHead = 0 AndAlso state.ignoredDepth = 0 AndAlso _
                   state.ignoredTitleDepth = 0 AndAlso _
                   (state.tableActive = 0 OrElse state.tableCellOpen) Then
                If state.style.preformatted Then
                    htmlview_LayoutPreText state, textValue
                Else
                    htmlview_LayoutNormalText state, textValue
                End If
            End If
        End If

        If Mid(htmlText, tagStart, 4) = "<!--" Then
            commentEnd = InStr(tagStart + 4, htmlText, "-->")
            If commentEnd = 0 Then
                parseDone = -1
                Exit While
            End If
            position = commentEnd + 3
            Continue While
        End If

        tagEnd = htmlview_FindTagEnd(htmlText, tagStart)
        If tagEnd = 0 Then
            textValue = Mid(htmlText, tagStart)
            If state.inHead = 0 AndAlso state.ignoredDepth = 0 AndAlso _
               state.ignoredTitleDepth = 0 AndAlso _
               (state.tableActive = 0 OrElse state.tableCellOpen) Then
                htmlview_LayoutNormalText state, textValue
            End If
            parseDone = -1
            Exit While
        End If

        tagText = Mid(htmlText, tagStart + 1, tagEnd - tagStart - 1)
        htmlview_TagInfo _
            tagText, tagName, attributeText, closingTag, selfClosing
        position = tagEnd + 1

        If Len(tagName) = 0 OrElse Left(tagName, 1) = "!" OrElse _
           Left(tagName, 1) = "?" Then Continue While

        If state.ignoredDepth > 0 Then
            If tagName = state.ignoredTag Then
                If closingTag Then
                    state.ignoredDepth -= 1
                    If state.ignoredDepth = 0 Then state.ignoredTag = ""
                ElseIf Not selfClosing Then
                    state.ignoredDepth += 1
                End If
            End If
            Continue While
        End If

        If tagName = "script" OrElse tagName = "style" Then
            If tagName = "script" AndAlso closingTag = 0 Then
                state.interactiveFallbackNeeded = -1
            End If
            If Not closingTag AndAlso Not selfClosing Then
                htmlview_SkipElementContent _
                    state, htmlText, position, tagName
            End If
            Continue While
        End If
        If tagName = "template" Then
            If Not closingTag AndAlso Not selfClosing Then
                state.ignoredTag = tagName
                state.ignoredDepth = 1
            End If
            Continue While
        End If
        If tagName = "svg" Then
            If Not closingTag AndAlso Not selfClosing Then
                htmlview_SkipElementContent _
                    state, htmlText, position, tagName
            End If
            Continue While
        End If

        If tagName = "head" Then
            state.inHead = IIf(closingTag, 0, -1)
            Continue While
        End If
        If tagName = "title" Then
            If closingTag Then
                If state.inTitle Then
                    state.inTitle = 0
                ElseIf state.ignoredTitleDepth > 0 Then
                    state.ignoredTitleDepth -= 1
                End If
            ElseIf Not selfClosing Then
                If state.bodyStarted = 0 AndAlso _
                   state.documentTitleSeen = 0 Then
                    state.inTitle = -1
                    state.documentTitleSeen = -1
                Else
                    state.ignoredTitleDepth += 1
                End If
            End If
            Continue While
        End If
        If state.inHead Then Continue While

        If tagName = "body" AndAlso closingTag = 0 Then
            state.bodyStarted = -1
        End If

        If tagName = "div" AndAlso closingTag = 0 AndAlso _
           selfClosing = 0 AndAlso _
           htmlview_ConsumeEmptyContainer(htmlText, position, tagName) Then
            Continue While
        End If

        /'
            Tables need the complete first row before column widths can be
            chosen.  The opening TABLE tag therefore starts a bounded
            measurement pass, while the ordinary tokenizer continues to lay
            out cell contents and retain live links.

            Legacy presentation tables are flattened into normal document
            flow.  Nested tables inside a data grid are flattened into their
            parent cell.  Both fallbacks preserve links and inline markup
            without creating ambiguous recursive geometry.
        '/
        If tagName = "table" Then
            If state.tableActive Then
                If state.tableNestedDepth > 0 Then
                    If closingTag Then
                        state.tableNestedDepth -= 1
                    ElseIf Not selfClosing Then
                        state.tableNestedDepth += 1
                    End If
                ElseIf closingTag Then
                    htmlview_EndTable state
                ElseIf Not selfClosing Then
                    state.tableNestedDepth = 1
                End If
            ElseIf state.tableLayoutDepth > 0 Then
                If closingTag Then
                    htmlview_BeginBlock state, 1
                    htmlview_PopStyle state, "table-layout"
                    state.tableLayoutDepth -= 1
                ElseIf Not selfClosing Then
                    If htmlview_IsLayoutTable( _
                        htmlText, position, attributeText _
                    ) Then
                        htmlview_BeginBlock state, 1
                        htmlview_PushStyle state, "table-layout"
                        state.style.alignment = HTMLVIEW_ALIGN_LEFT
                        state.tableLayoutDepth += 1
                    Else
                        htmlview_BeginTable state, htmlText, position
                    End If
                End If
            ElseIf Not closingTag Then
                If htmlview_IsLayoutTable( _
                    htmlText, position, attributeText _
                ) Then
                    htmlview_BeginBlock state, HTMLVIEW_PARAGRAPH_GAP
                    htmlview_PushStyle state, "table-layout"
                    state.style.alignment = HTMLVIEW_ALIGN_LEFT
                    state.tableLayoutDepth = 1
                Else
                    htmlview_BeginTable state, htmlText, position
                    If selfClosing Then htmlview_EndTable state
                End If
            End If
            Continue While
        End If
        If state.tableActive AndAlso state.tableNestedDepth > 0 Then
            /'
                A nested table does not create another grid, but its inline
                markup still carries useful links, emphasis, line breaks, and
                image alternatives.  Ignore only the recursive table
                structure and lay the remaining content into the outer cell.
            '/
            Select Case tagName
            Case "thead", "tbody", "tfoot", "tr", "th", "td", _
                 "caption", "colgroup", "col"
                Continue While
            End Select
            If state.tableCellOpen Then
                htmlview_HandleTag _
                    state, tagName, attributeText, closingTag, selfClosing
            End If
            Continue While
        End If
        If state.tableActive Then
            Select Case tagName
            Case "tr"
                If closingTag Then
                    htmlview_EndTableRow state
                Else
                    htmlview_BeginTableRow state
                End If
                Continue While
            Case "td", "th"
                If closingTag Then
                    htmlview_EndTableCell state
                Else
                    htmlview_BeginTableCell state, tagName, attributeText
                    If selfClosing Then htmlview_EndTableCell state
                End If
                Continue While
            Case "thead", "tbody", "tfoot", "caption", "colgroup", "col"
                Continue While
            End Select
            If state.tableCellOpen = 0 Then Continue While
        End If
        If state.tableLayoutDepth > 0 Then
            Select Case tagName
            Case "thead", "tbody", "tfoot", "caption", "colgroup", "col"
                Continue While
            Case "tr"
                htmlview_BeginBlock state, 1
                Continue While
            Case "td", "th"
                If state.lineHasContent Then state.pendingSpace = -1
                Continue While
            End Select
        End If

        htmlview_HandleTag _
            state, tagName, attributeText, closingTag, selfClosing
    Wend

    elapsedSeconds = htmlview_ParseElapsedSeconds(parseStartTime)
    parseContext.workSeconds += elapsedSeconds
    parseContext.state = state
    parseContext.position = position
    parseContext.parseIteration = parseIteration

    If parseDone = 0 AndAlso yielded = 0 AndAlso _
       position > Len(htmlText) Then parseDone = -1
    If parseDone = 0 Then Return 0

    If state.tableActive Then htmlview_EndTable state
    If Len(htmlview_TrimPlainEnd(viewData->plainText)) = 0 AndAlso _
       state.interactiveFallbackNeeded Then
        /'
            A script, canvas, or embedded application with no author-provided
            fallback would otherwise produce a featureless white document.
            State the capability boundary without exposing executable source
            or pretending that the application was rendered successfully.
        '/
        htmlview_LayoutNormalText _
            state, "Interactive page content requires a full browser.", 0
    End If
    If state.lineHasContent Then
        htmlview_AlignCurrentLine state
        state.cursorY += IIf( _
            state.lineHeight > 0, state.lineHeight, HTMLVIEW_DEFAULT_LINE_HEIGHT _
        )
    End If

    viewData->titleText = Trim( _
        htmlview_CollapseWhitespace(viewData->titleText) _
    )
    viewData->plainText = htmlview_TrimPlainEnd(viewData->plainText)
    viewData->contentHeight = state.cursorY
    If viewData->contentHeight < 1 Then viewData->contentHeight = 1
    parseContext.state = state
    parseContext.complete = -1
    Return -1
End Function


Private Sub htmlview_ParseAndLayout( _
    ByVal viewData As HtmlViewData Ptr, ByVal availableWidth As Integer _
)
    Dim As HtmlViewParseContext parseContext

    If viewData = 0 Then Exit Sub
    htmlview_InitializeParseContext parseContext, viewData, availableWidth
    Do
        If htmlview_ParseContextStep( _
            parseContext, HTMLVIEW_MAXIMUM_LOAD_BUDGET_MS _
        ) Then Exit Do
    Loop
End Sub


' -------------------------------------------------------------------------
' Scroll state and public document API
' -------------------------------------------------------------------------

Private Function htmlview_CalculateLayoutWidth( _
    ByVal htmlWidget As Widget Ptr, ByVal viewData As HtmlViewData Ptr _
) As Integer
    Dim As Integer availableWidth

    If htmlWidget = 0 OrElse viewData = 0 Then
        Return HTMLVIEW_MINIMUM_LAYOUT_WIDTH
    End If

    availableWidth = htmlWidget->w - HTMLVIEW_SCROLLBAR_WIDTH - _
        viewData->padding * 2 - 2
    If availableWidth < HTMLVIEW_MINIMUM_LAYOUT_WIDTH Then
        availableWidth = HTMLVIEW_MINIMUM_LAYOUT_WIDTH
    End If
    Return availableWidth
End Function


Private Function htmlview_ViewportHeight(ByVal htmlWidget As Widget Ptr) As Integer
    Dim As HtmlViewData Ptr viewData
    Dim As Integer result

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return 1
    result = htmlWidget->h - viewData->padding * 2 - 2
    If result < 1 Then result = 1
    Return result
End Function


Private Sub htmlview_ClampScroll(ByVal htmlWidget As Widget Ptr)
    Dim As HtmlViewData Ptr viewData
    Dim As ScrollBarData Ptr scrollData
    Dim As Integer maximumScroll
    Dim As Integer viewportHeight

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Exit Sub

    viewportHeight = htmlview_ViewportHeight(htmlWidget)
    maximumScroll = viewData->contentHeight - viewportHeight
    If maximumScroll < 0 Then maximumScroll = 0
    If viewData->scrollY < 0 Then viewData->scrollY = 0
    If viewData->scrollY > maximumScroll Then viewData->scrollY = maximumScroll

    If viewData->verticalScrollbar <> 0 AndAlso _
       viewData->verticalScrollbar->data <> 0 Then
        scrollData = Cast(ScrollBarData Ptr, viewData->verticalScrollbar->data)
        scrollData->max_val = maximumScroll
        scrollData->page_size = viewportHeight
        scrollData->value = viewData->scrollY
    End If
End Sub


Private Sub htmlview_DestroyLoadContext( _
    ByVal loadContext As HtmlViewLoadContext Ptr _
)
    If loadContext = 0 Then Exit Sub
    If loadContext->stagingData <> 0 Then
        htmlview_DeleteItems loadContext->stagingData
        Delete loadContext->stagingData
        loadContext->stagingData = 0
    End If
    Delete loadContext
End Sub


Private Function htmlview_CreateLoadContext( _
    ByVal activeData As HtmlViewData Ptr, _
    ByVal htmlText As String, ByVal basePath As String, _
    ByVal styleSheetText As String, _
    ByVal availableWidth As Integer _
) As HtmlViewLoadContext Ptr
    Dim As HtmlViewLoadContext Ptr loadContext
    Dim As HtmlViewData Ptr stagingData

    If activeData = 0 Then Return 0
    loadContext = New HtmlViewLoadContext
    If loadContext = 0 Then Return 0
    stagingData = New HtmlViewData
    If stagingData = 0 Then
        Delete loadContext
        Return 0
    End If

    /'
        A staging document deliberately has no scrollbar.  Parsing and image
        ownership belong to it, while all visible widget state stays in the
        active document until the final ownership transfer.
    '/
    stagingData->sourceHtml = htmlText
    stagingData->basePath = basePath
    stagingData->styleSheetText = styleSheetText
    htmlview_ParseStylesheet stagingData, styleSheetText
    stagingData->padding = activeData->padding
    stagingData->backgroundColor = activeData->backgroundColor
    stagingData->textColor = activeData->textColor
    stagingData->linkColor = activeData->linkColor
    stagingData->codeBackgroundColor = activeData->codeBackgroundColor
    stagingData->documentBackgroundColor = activeData->backgroundColor
    stagingData->documentTextColor = activeData->textColor
    stagingData->documentLinkColor = activeData->linkColor
    stagingData->contentHeight = 1
    stagingData->layoutWidth = availableWidth
    stagingData->imageHandler = activeData->imageHandler
    stagingData->imageContext = activeData->imageContext
    stagingData->resourceHandler = activeData->resourceHandler
    stagingData->resourceContext = activeData->resourceContext

    loadContext->stagingData = stagingData
    loadContext->layoutWidth = availableWidth
    htmlview_InitializeParseContext _
        loadContext->parser, stagingData, availableWidth
    Return loadContext
End Function


Private Function htmlview_ReadFileText( _
    ByVal filePath As String, ByRef htmlText As String, _
    ByRef errorMessage As String _
) As Integer
    Dim As Integer fileNumber
    Dim As Integer ioResult
    Dim As LongInt fileSize

    htmlText = ""
    errorMessage = ""
    fileNumber = FreeFile
    ioResult = Open(filePath For Binary Access Read As #fileNumber)
    If ioResult <> 0 Then
        errorMessage = "cannot open HTML file: " & filePath
        Return 0
    End If

    fileSize = LOF(fileNumber)
    If fileSize < 0 OrElse fileSize > HTMLVIEW_MAX_DOCUMENT_BYTES Then
        Close #fileNumber
        errorMessage = "HTML file exceeds the 2 MiB safety limit"
        Return 0
    End If

    If fileSize > 0 Then
        htmlText = Space(fileSize)
        ioResult = Get(#fileNumber, 1, htmlText)
        If ioResult <> 0 Then
            Close #fileNumber
            htmlText = ""
            errorMessage = "failed while reading HTML file: " & filePath
            Return 0
        End If
    End If
    Close #fileNumber
    Return -1
End Function


Private Function htmlview_ReadResourceText( _
    ByVal viewData As HtmlViewData Ptr, ByVal resourcePath As String, _
    ByRef resourceText As String, ByRef errorMessage As String _
) As Integer

    Dim As Integer resourceProvided

    resourceText = ""
    errorMessage = ""
    If viewData = 0 Then Return 0
    If viewData->resourceHandler <> 0 Then
        resourceProvided = Cast(Function( _
            ByVal As String, ByVal As Any Ptr, _
            ByRef As String, ByRef As String _
        ) As Integer, viewData->resourceHandler)( _
            resourcePath, viewData->resourceContext, resourceText, errorMessage _
        )
        If resourceProvided <> 0 Then
            If Len(resourceText) > HTMLVIEW_MAX_DOCUMENT_BYTES Then
                resourceText = ""
                errorMessage = "application resource exceeds the 2 MiB limit"
                Return 0
            End If
            Return -1
        End If
    End If

    If htmlview_PathHasScheme(resourcePath) <> 0 Then
        resourceText = ""
        If errorMessage = "" Then _
            errorMessage = "HTML viewer cannot load a URI resource"
        Return 0
    End If
    Return htmlview_ReadFileText(resourcePath, resourceText, errorMessage)

End Function


Private Function htmlview_LoadLinkedStyleSheets( _
    ByVal viewData As HtmlViewData Ptr, ByVal htmlText As String, _
    ByVal basePath As String _
) As String

    Dim As Integer tagEnd
    Dim As Integer hrefPosition
    Dim As Integer afterName
    Dim As Long position
    Dim As String attributeText
    Dim As String cssText
    Dim As String errorMessage
    Dim As String href
    Dim As String lowerHtml
    Dim As String relText
    Dim As String result
    Dim As String resolvedPath

    lowerHtml = LCase(htmlText)
    If viewData = 0 Then Return ""
    position = 1
    While position <= Len(htmlText)
        position = InStr(position, lowerHtml, "<link")
        If position = 0 Then Exit While
        afterName = position + 5
        If afterName <= Len(htmlText) AndAlso _
           Not htmlview_IsWhiteSpace(Asc(Mid(htmlText, afterName, 1))) AndAlso _
           Mid(htmlText, afterName, 1) <> "/" AndAlso _
           Mid(htmlText, afterName, 1) <> ">" Then
            position = afterName
            Continue While
        End If

        tagEnd = htmlview_FindTagEnd(htmlText, position)
        If tagEnd = 0 Then Exit While
        attributeText = Mid(htmlText, position + 5, tagEnd - position - 5)
        relText = LCase(htmlview_GetAttribute(attributeText, "rel"))
        If InStr(relText, "stylesheet") > 0 Then
            href = Trim(htmlview_GetAttribute(attributeText, "href"))
            hrefPosition = InStr(href, "#")
            If hrefPosition > 0 Then href = Left(href, hrefPosition - 1)
            hrefPosition = InStr(href, "?")
            If hrefPosition > 0 Then href = Left(href, hrefPosition - 1)
            If href <> "" AndAlso htmlview_PathHasScheme(href) = 0 Then
                resolvedPath = htmlview_ResolveResourcePath( _
                    basePath, href, IIf(viewData->resourceHandler <> 0, -1, 0) _
                )
                If resolvedPath <> "" AndAlso _
                   htmlview_ReadResourceText( _
                       viewData, resolvedPath, cssText, errorMessage _
                   ) <> 0 Then
                    If Len(cssText) <= _
                       HTMLVIEW_MAX_STYLESHEET_BYTES - Len(result) Then
                        result &= Chr(10) & cssText
                    End If
                End If
            End If
        End If
        position = tagEnd + 1
    Wend

    Return result

End Function


Private Sub htmlview_SetLoadFailure( _
    ByVal viewData As HtmlViewData Ptr, ByVal errorMessage As String _
)
    If viewData = 0 Then Exit Sub
    If Len(errorMessage) = 0 Then
        errorMessage = "HTML document could not be laid out"
    End If
    viewData->lastError = errorMessage
    viewData->loadError = errorMessage
    viewData->loadState = HTMLVIEW_LOAD_FAILED
End Sub


Private Function htmlview_BeginDocument( _
    ByVal htmlWidget As Widget Ptr, ByVal htmlText As String, _
    ByVal basePath As String, ByVal styleSheetText As String _
) As Integer
    Dim As HtmlViewData Ptr viewData
    Dim As HtmlViewLoadContext Ptr loadContext
    Dim As Integer availableWidth

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return 0
    htmlview_CancelLoad htmlWidget
    If Len(htmlText) > HTMLVIEW_MAX_DOCUMENT_BYTES Then
        viewData->loadProgress = 0
        htmlview_SetLoadFailure _
            viewData, "HTML document exceeds the 2 MiB safety limit"
        Return 0
    End If

    availableWidth = htmlview_CalculateLayoutWidth(htmlWidget, viewData)
    loadContext = htmlview_CreateLoadContext( _
        viewData, htmlText, basePath, styleSheetText, availableWidth _
    )
    If loadContext = 0 Then
        viewData->loadProgress = 0
        htmlview_SetLoadFailure viewData, _
            "could not allocate the HTML loading context"
        Return 0
    End If

    viewData->loadContext = loadContext
    viewData->loadError = ""
    viewData->lastError = ""
    viewData->loadState = HTMLVIEW_LOAD_LOADING
    viewData->loadProgress = 0
    Return -1
End Function


Private Sub htmlview_CommitLoad( _
    ByVal htmlWidget As Widget Ptr, _
    ByVal loadContext As HtmlViewLoadContext Ptr _
)
    Dim As HtmlViewData Ptr viewData
    Dim As HtmlViewData Ptr stagingData

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 OrElse loadContext = 0 Then Exit Sub
    stagingData = loadContext->stagingData
    If stagingData = 0 Then Exit Sub

    htmlview_DeleteItems viewData
    viewData->sourceHtml = stagingData->sourceHtml
    viewData->basePath = stagingData->basePath
    viewData->styleSheetText = stagingData->styleSheetText
    viewData->titleText = stagingData->titleText
    viewData->plainText = stagingData->plainText
    viewData->lastError = stagingData->lastError
    viewData->firstItem = stagingData->firstItem
    viewData->lastItem = stagingData->lastItem
    viewData->itemCount = stagingData->itemCount
    viewData->cssRuleCount = stagingData->cssRuleCount
    For ruleIndex As Integer = 0 To viewData->cssRuleCount - 1
        viewData->cssRules(ruleIndex).selectorText = _
            stagingData->cssRules(ruleIndex).selectorText
        viewData->cssRules(ruleIndex).declarationText = _
            stagingData->cssRules(ruleIndex).declarationText
    Next ruleIndex
    viewData->anchorCount = stagingData->anchorCount
    For anchorIndex As Integer = 0 To viewData->anchorCount - 1
        viewData->anchors(anchorIndex).nameText = _
            stagingData->anchors(anchorIndex).nameText
        viewData->anchors(anchorIndex).y = _
            stagingData->anchors(anchorIndex).y
    Next anchorIndex
    viewData->contentHeight = stagingData->contentHeight
    viewData->layoutWidth = stagingData->layoutWidth
    viewData->layoutIncomplete = stagingData->layoutIncomplete
    viewData->documentBackgroundColor = _
        stagingData->documentBackgroundColor
    viewData->documentTextColor = stagingData->documentTextColor
    viewData->documentLinkColor = stagingData->documentLinkColor
    viewData->scrollY = 0
    viewData->pendingLink = ""
    viewData->armedLink = ""

    /'
        The item list is transferred, not copied.  Clearing the staging
        pointers prevents its destructor from freeing the newly active page.
    '/
    stagingData->firstItem = 0
    stagingData->lastItem = 0
    stagingData->itemCount = 0
    stagingData->anchorCount = 0
    viewData->loadContext = 0
    htmlview_DestroyLoadContext loadContext
    viewData->loadError = ""
    viewData->loadState = HTMLVIEW_LOAD_COMPLETE
    viewData->loadProgress = 100
    htmlview_ClampScroll htmlWidget
End Sub


Private Function htmlview_RestartLoadForWidth( _
    ByVal htmlWidget As Widget Ptr, ByVal availableWidth As Integer _
) As Integer
    Dim As HtmlViewData Ptr viewData
    Dim As HtmlViewLoadContext Ptr oldContext
    Dim As HtmlViewLoadContext Ptr newContext
    Dim As String htmlText
    Dim As String basePath
    Dim As String styleSheetText

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 OrElse viewData->loadContext = 0 Then Return 0
    oldContext = Cast(HtmlViewLoadContext Ptr, viewData->loadContext)
    If oldContext->stagingData = 0 Then Return 0
    htmlText = oldContext->stagingData->sourceHtml
    basePath = oldContext->stagingData->basePath
    styleSheetText = oldContext->stagingData->styleSheetText
    newContext = htmlview_CreateLoadContext( _
        viewData, htmlText, basePath, styleSheetText, availableWidth _
    )
    If newContext = 0 Then
        viewData->loadContext = 0
        htmlview_DestroyLoadContext oldContext
        viewData->loadProgress = 0
        htmlview_SetLoadFailure viewData, _
            "could not restart HTML layout after a size change"
        Return 0
    End If

    viewData->loadContext = newContext
    viewData->loadProgress = 0
    htmlview_DestroyLoadContext oldContext
    Return -1
End Function


Function htmlview_Reflow(ByVal htmlWidget As Widget Ptr) As Integer
    Dim As HtmlViewData Ptr viewData
    Dim As Integer availableWidth
    Dim As Integer previousScroll

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return 0
    htmlview_CancelLoad htmlWidget

    availableWidth = htmlview_CalculateLayoutWidth(htmlWidget, viewData)

    previousScroll = viewData->scrollY
    htmlview_DeleteItems viewData
    viewData->titleText = ""
    viewData->plainText = ""
    viewData->lastError = ""
    viewData->anchorCount = 0
    viewData->layoutIncomplete = 0
    viewData->layoutWidth = availableWidth
    viewData->documentBackgroundColor = viewData->backgroundColor
    viewData->documentTextColor = viewData->textColor
    viewData->documentLinkColor = viewData->linkColor

    htmlview_ParseAndLayout viewData, availableWidth
    viewData->scrollY = previousScroll
    htmlview_ClampScroll htmlWidget
    If viewData->layoutIncomplete Then
        viewData->loadProgress = 0
        htmlview_SetLoadFailure viewData, viewData->lastError
        Return 0
    End If
    viewData->loadError = ""
    viewData->loadState = HTMLVIEW_LOAD_COMPLETE
    viewData->loadProgress = 100
    Return -1
End Function


Function htmlview_SetHtml( _
    ByVal htmlWidget As Widget Ptr, ByVal htmlText As String _
) As Integer
    Dim As HtmlViewData Ptr viewData

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return 0
    htmlview_CancelLoad htmlWidget
    If Len(htmlText) > HTMLVIEW_MAX_DOCUMENT_BYTES Then
        viewData->loadProgress = 0
        htmlview_SetLoadFailure _
            viewData, "HTML document exceeds the 2 MiB safety limit"
        Return 0
    End If

    viewData->sourceHtml = htmlText
    viewData->scrollY = 0
    viewData->pendingLink = ""
    viewData->armedLink = ""
    Return htmlview_Reflow(htmlWidget)
End Function


Function htmlview_LoadFile( _
    ByVal htmlWidget As Widget Ptr, ByVal filePath As String _
) As Integer
    Dim As HtmlViewData Ptr viewData
    Dim As String htmlText
    Dim As String errorMessage
    Dim As String styleSheetText

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return 0
    htmlview_CancelLoad htmlWidget

    If htmlview_ReadFileText(filePath, htmlText, errorMessage) = 0 Then
        viewData->loadProgress = 0
        htmlview_SetLoadFailure viewData, errorMessage
        Return 0
    End If

    viewData->basePath = htmlview_PathDirectory(filePath)
    styleSheetText = htmlview_LoadLinkedStyleSheets( _
        viewData, htmlText, htmlview_PathDirectory(filePath) _
    )
    htmlview_ParseStylesheet viewData, styleSheetText
    Return htmlview_SetHtml(htmlWidget, htmlText)
End Function


Function htmlview_BeginSetHtml( _
    ByVal htmlWidget As Widget Ptr, ByVal htmlText As String _
) As Integer
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)

    If viewData = 0 Then Return 0
    Return htmlview_BeginSetHtmlAtPath( _
        htmlWidget, htmlText, viewData->basePath _
    )
End Function


Function htmlview_BeginSetHtmlAtPath( _
    ByVal htmlWidget As Widget Ptr, ByVal htmlText As String, _
    ByVal basePath As String _
) As Integer

    Dim As HtmlViewData Ptr viewData
    Dim As String styleSheetText

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return 0
    styleSheetText = htmlview_LoadLinkedStyleSheets( _
        viewData, htmlText, basePath _
    )
    Return htmlview_BeginDocument( _
        htmlWidget, htmlText, basePath, styleSheetText _
    )
End Function


Function htmlview_BeginLoadFile( _
    ByVal htmlWidget As Widget Ptr, ByVal filePath As String _
) As Integer
    Dim As HtmlViewData Ptr viewData
    Dim As String htmlText
    Dim As String errorMessage
    Dim As String styleSheetText

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return 0
    If htmlview_ReadFileText(filePath, htmlText, errorMessage) = 0 Then
        htmlview_CancelLoad htmlWidget
        viewData->loadProgress = 0
        htmlview_SetLoadFailure viewData, errorMessage
        Return 0
    End If
    styleSheetText = htmlview_LoadLinkedStyleSheets( _
        viewData, htmlText, htmlview_PathDirectory(filePath) _
    )
    Return htmlview_BeginDocument( _
        htmlWidget, htmlText, htmlview_PathDirectory(filePath), styleSheetText _
    )
End Function


Function htmlview_UpdateLoad( _
    ByVal htmlWidget As Widget Ptr, _
    ByVal timeBudgetMilliseconds As Integer _
) As Integer
    Dim As HtmlViewData Ptr viewData
    Dim As HtmlViewLoadContext Ptr loadContext
    Dim As HtmlViewData Ptr stagingData
    Dim As Integer availableWidth
    Dim As Integer sourceLength
    Dim As Integer parseComplete
    Dim As Long calculatedProgress
    Dim As String errorMessage

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return HTMLVIEW_LOAD_FAILED
    If viewData->loadState <> HTMLVIEW_LOAD_LOADING OrElse _
       viewData->loadContext = 0 Then Return viewData->loadState

    availableWidth = htmlview_CalculateLayoutWidth(htmlWidget, viewData)
    loadContext = Cast(HtmlViewLoadContext Ptr, viewData->loadContext)
    If loadContext->layoutWidth <> availableWidth Then
        If htmlview_RestartLoadForWidth(htmlWidget, availableWidth) = 0 Then
            Return viewData->loadState
        End If
        loadContext = Cast(HtmlViewLoadContext Ptr, viewData->loadContext)
    End If

    parseComplete = htmlview_ParseContextStep( _
        loadContext->parser, timeBudgetMilliseconds _
    )
    stagingData = loadContext->stagingData
    sourceLength = Len(stagingData->sourceHtml)
    If sourceLength > 0 Then
        calculatedProgress = _
            CLngInt(loadContext->parser.position) * 100 \ _
            sourceLength
        If calculatedProgress < 0 Then calculatedProgress = 0
        If calculatedProgress > 99 Then calculatedProgress = 99
        viewData->loadProgress = calculatedProgress
    End If

    If parseComplete = 0 Then Return HTMLVIEW_LOAD_LOADING
    If stagingData->layoutIncomplete Then
        errorMessage = stagingData->lastError
        viewData->loadContext = 0
        htmlview_DestroyLoadContext loadContext
        htmlview_SetLoadFailure viewData, errorMessage
        Return viewData->loadState
    End If

    htmlview_CommitLoad htmlWidget, loadContext
    Return viewData->loadState
End Function


Function htmlview_IsLoading(ByVal htmlWidget As Widget Ptr) As Integer
    Return IIf( _
        htmlview_GetLoadState(htmlWidget) = HTMLVIEW_LOAD_LOADING, -1, 0 _
    )
End Function


Function htmlview_GetLoadState(ByVal htmlWidget As Widget Ptr) As Integer
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return HTMLVIEW_LOAD_FAILED
    Return viewData->loadState
End Function


Function htmlview_GetLoadProgress(ByVal htmlWidget As Widget Ptr) As Integer
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return 0
    Return viewData->loadProgress
End Function


Function htmlview_GetLoadError(ByVal htmlWidget As Widget Ptr) As String
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return "HTML viewer is not initialized"
    Return viewData->loadError
End Function


Sub htmlview_CancelLoad(ByVal htmlWidget As Widget Ptr)
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)
    Dim As HtmlViewLoadContext Ptr loadContext

    If viewData = 0 OrElse viewData->loadContext = 0 Then Exit Sub
    loadContext = Cast(HtmlViewLoadContext Ptr, viewData->loadContext)
    viewData->loadContext = 0
    htmlview_DestroyLoadContext loadContext
    viewData->loadError = ""
    viewData->loadState = HTMLVIEW_LOAD_CANCELLED
    viewData->loadProgress = 0
End Sub


Sub htmlview_Clear(ByVal htmlWidget As Widget Ptr)
    Dim As HtmlViewData Ptr viewData

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Exit Sub
    htmlview_CancelLoad htmlWidget
    viewData->sourceHtml = ""
    viewData->titleText = ""
    viewData->plainText = ""
    viewData->lastError = ""
    viewData->pendingLink = ""
    viewData->armedLink = ""
    viewData->styleSheetText = ""
    viewData->cssRuleCount = 0
    viewData->scrollY = 0
    viewData->anchorCount = 0
    viewData->contentHeight = 1
    viewData->loadError = ""
    viewData->loadState = HTMLVIEW_LOAD_IDLE
    viewData->loadProgress = 0
    htmlview_DeleteItems viewData
    htmlview_ClampScroll htmlWidget
End Sub


Sub htmlview_SetBasePath( _
    ByVal htmlWidget As Widget Ptr, ByVal directoryPath As String _
)
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)

    If viewData = 0 Then Exit Sub
    viewData->basePath = Trim(directoryPath)
    htmlview_Reflow htmlWidget
End Sub


Sub htmlview_SetColors( _
    ByVal htmlWidget As Widget Ptr, _
    ByVal backgroundColor As ULong, _
    ByVal textColor As ULong, _
    ByVal linkColor As ULong _
)
    Dim As HtmlViewData Ptr viewData

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Exit Sub
    viewData->backgroundColor = backgroundColor
    viewData->textColor = textColor
    viewData->linkColor = linkColor
    htmlview_Reflow htmlWidget
End Sub


Sub htmlview_SetLinkHandler( _
    ByVal htmlWidget As Widget Ptr, _
    ByVal handler As Any Ptr, _
    ByVal context As Any Ptr _
)
    Dim As HtmlViewData Ptr viewData

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Exit Sub
    viewData->linkHandler = handler
    viewData->linkContext = context
End Sub


Sub htmlview_SetImageHandler( _
    ByVal htmlWidget As Widget Ptr, _
    ByVal handler As Any Ptr, _
    ByVal context As Any Ptr _
)
    Dim As HtmlViewData Ptr viewData

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Exit Sub
    viewData->imageHandler = handler
    viewData->imageContext = context
    htmlview_Reflow htmlWidget
End Sub


Sub htmlview_SetResourceHandler( _
    ByVal htmlWidget As Widget Ptr, ByVal handler As Any Ptr, _
    ByVal context As Any Ptr _
)

    Dim As HtmlViewData Ptr viewData

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Exit Sub
    viewData->resourceHandler = handler
    viewData->resourceContext = context

End Sub


Function htmlview_GetTitle(ByVal htmlWidget As Widget Ptr) As String
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return ""
    Return viewData->titleText
End Function


Function htmlview_GetPlainText(ByVal htmlWidget As Widget Ptr) As String
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return ""
    Return viewData->plainText
End Function


Function htmlview_GetLastError(ByVal htmlWidget As Widget Ptr) As String
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return "HTML viewer is not initialized"
    Return viewData->lastError
End Function


Function htmlview_GetBasePath(ByVal htmlWidget As Widget Ptr) As String
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return ""
    Return viewData->basePath
End Function


Function htmlview_GetContentHeight(ByVal htmlWidget As Widget Ptr) As Integer
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return 0
    Return viewData->contentHeight
End Function


Function htmlview_GetScroll(ByVal htmlWidget As Widget Ptr) As Integer
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return 0
    Return viewData->scrollY
End Function


Sub htmlview_SetScroll(ByVal htmlWidget As Widget Ptr, ByVal pixelOffset As Integer)
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Exit Sub
    viewData->scrollY = pixelOffset
    htmlview_ClampScroll htmlWidget
End Sub


Function htmlview_GotoAnchor( _
    ByVal htmlWidget As Widget Ptr, ByVal anchorName As String _
) As Integer

    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)

    If viewData = 0 OrElse Len(anchorName) = 0 Then Return 0
    For anchorIndex As Integer = 0 To viewData->anchorCount - 1
        If LCase(viewData->anchors(anchorIndex).nameText) = LCase(anchorName) Then
            viewData->scrollY = viewData->anchors(anchorIndex).y
            htmlview_ClampScroll htmlWidget
            Return -1
        End If
    Next anchorIndex
    Return 0

End Function


Function htmlview_PopLink( _
    ByVal htmlWidget As Widget Ptr, ByRef href As String _
) As Integer
    Dim As HtmlViewData Ptr viewData = htmlview_Data(htmlWidget)

    href = ""
    If viewData = 0 OrElse Len(viewData->pendingLink) = 0 Then Return 0
    href = viewData->pendingLink
    viewData->pendingLink = ""
    Return -1
End Function


' -------------------------------------------------------------------------
' Pointer, keyboard, and rendering
' -------------------------------------------------------------------------

Private Function htmlview_LinkAt( _
    ByVal htmlWidget As Widget Ptr, ByVal mouseX As Integer, ByVal mouseY As Integer _
) As String
    Dim As HtmlViewData Ptr viewData
    Dim As HtmlViewItem Ptr item
    Dim As Integer contentX
    Dim As Integer contentY
    Dim As Integer itemY

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Return ""

    contentX = htmlWidget->ax + 1 + viewData->padding
    contentY = htmlWidget->ay + 1 + viewData->padding
    If mouseX < contentX OrElse mouseX >= _
       htmlWidget->ax + htmlWidget->w - HTMLVIEW_SCROLLBAR_WIDTH - viewData->padding Then
        Return ""
    End If
    If mouseY < contentY OrElse mouseY >= _
       htmlWidget->ay + htmlWidget->h - viewData->padding - 1 Then Return ""

    item = viewData->firstItem
    While item <> 0
        If Len(item->href) > 0 Then
            itemY = contentY + item->y - viewData->scrollY
            If mouseX >= contentX + item->x AndAlso _
               mouseX < contentX + item->x + item->w AndAlso _
               mouseY >= itemY AndAlso mouseY < itemY + item->h Then
                Return item->href
            End If
        End If
        item = item->nextItem
    Wend
    Return ""
End Function


Private Sub htmlview_ActivateLink( _
    ByVal htmlWidget As Widget Ptr, ByVal href As String _
)
    Dim As HtmlViewData Ptr viewData

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 OrElse Len(href) = 0 Then Exit Sub
    viewData->pendingLink = href

    If viewData->linkHandler <> 0 Then
        Cast(Sub( _
            ByVal As Widget Ptr, ByVal As String, ByVal As Any Ptr _
        ), viewData->linkHandler)(htmlWidget, href, viewData->linkContext)
    End If
End Sub


Private Sub htmlview_ReadKeyState( _
    ByVal keyCode As Integer, _
    ByVal keyBit As Integer, _
    ByRef heldState As Integer, _
    ByRef pressState As Integer _
)
    If input_KeyPressed(keyCode) <> 0 Then heldState Or= keyBit
    If input_KeyPressEvent(keyCode) <> 0 Then pressState Or= keyBit
End Sub


Private Function htmlview_KeyActivated( _
    ByVal heldState As Integer, _
    ByVal pressState As Integer, _
    ByVal previousHeldState As Integer, _
    ByVal keyBit As Integer _
) As Integer
    If (pressState And keyBit) <> 0 Then Return -1
    If (heldState And keyBit) <> 0 AndAlso _
       (previousHeldState And keyBit) = 0 Then Return -1
    Return 0
End Function


Private Sub htmlview_UpdateKeyboard( _
    ByVal viewData As HtmlViewData Ptr, _
    ByVal viewportHeight As Integer _
)
    Dim As Integer keyPressState
    Dim As Integer keyState

    htmlview_ReadKeyState _
        KEY_UP, HTMLVIEW_KEY_UP_BIT, keyState, keyPressState
    htmlview_ReadKeyState _
        KEY_DOWN, HTMLVIEW_KEY_DOWN_BIT, keyState, keyPressState
    htmlview_ReadKeyState _
        KEY_HOME, HTMLVIEW_KEY_HOME_BIT, keyState, keyPressState
    htmlview_ReadKeyState _
        KEY_END, HTMLVIEW_KEY_END_BIT, keyState, keyPressState
    htmlview_ReadKeyState _
        FB.SC_PAGEUP, HTMLVIEW_KEY_PAGE_UP_BIT, keyState, keyPressState
    htmlview_ReadKeyState _
        FB.SC_PAGEDOWN, HTMLVIEW_KEY_PAGE_DOWN_BIT, keyState, keyPressState

    If htmlview_KeyActivated( _
        keyState, keyPressState, viewData->keyLatch, HTMLVIEW_KEY_UP_BIT _
    ) Then
        viewData->scrollY -= HTMLVIEW_DEFAULT_LINE_HEIGHT
    End If
    If htmlview_KeyActivated( _
        keyState, keyPressState, viewData->keyLatch, HTMLVIEW_KEY_DOWN_BIT _
    ) Then
        viewData->scrollY += HTMLVIEW_DEFAULT_LINE_HEIGHT
    End If
    If htmlview_KeyActivated( _
        keyState, keyPressState, viewData->keyLatch, HTMLVIEW_KEY_HOME_BIT _
    ) Then
        viewData->scrollY = 0
    End If
    If htmlview_KeyActivated( _
        keyState, keyPressState, viewData->keyLatch, HTMLVIEW_KEY_END_BIT _
    ) Then
        viewData->scrollY = viewData->contentHeight
    End If
    If htmlview_KeyActivated( _
        keyState, keyPressState, viewData->keyLatch, _
        HTMLVIEW_KEY_PAGE_UP_BIT _
    ) Then
        viewData->scrollY -= viewportHeight
    End If
    If htmlview_KeyActivated( _
        keyState, keyPressState, viewData->keyLatch, _
        HTMLVIEW_KEY_PAGE_DOWN_BIT _
    ) Then
        viewData->scrollY += viewportHeight
    End If

    viewData->keyLatch = keyState
End Sub


Sub htmlview_Update(ByVal htmlWidget As Widget Ptr)
    Dim As HtmlViewData Ptr viewData
    Dim As ScrollBarData Ptr scrollData
    Dim As Integer mouseX
    Dim As Integer mouseY
    Dim As Integer mouseButtons
    Dim As Integer leftButtonDown
    Dim As Integer wheelDelta
    Dim As Integer viewportHeight
    Dim As String hoveredLink

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 OrElse htmlWidget->enabled = 0 Then Exit Sub

    If viewData->loadState = HTMLVIEW_LOAD_LOADING Then
        htmlview_UpdateLoad htmlWidget, HTMLVIEW_DEFAULT_LOAD_BUDGET_MS
    End If

    If viewData->loadState <> HTMLVIEW_LOAD_LOADING AndAlso _
       viewData->layoutWidth <> _
       htmlview_CalculateLayoutWidth(htmlWidget, viewData) Then
        htmlview_Reflow htmlWidget
    End If

    viewData->verticalScrollbar->ax = _
        htmlWidget->ax + htmlWidget->w - HTMLVIEW_SCROLLBAR_WIDTH
    viewData->verticalScrollbar->ay = htmlWidget->ay
    viewData->verticalScrollbar->w = HTMLVIEW_SCROLLBAR_WIDTH
    viewData->verticalScrollbar->h = htmlWidget->h
    viewData->verticalScrollbar->enabled = htmlWidget->enabled
    viewData->verticalScrollbar->update(viewData->verticalScrollbar)
    scrollData = Cast(ScrollBarData Ptr, viewData->verticalScrollbar->data)
    viewData->scrollY = scrollData->value

    mouseX = input_MouseX()
    mouseY = input_MouseY()
    mouseButtons = input_MouseButtons()
    wheelDelta = input_MouseWheel()
    leftButtonDown = mouseButtons And 1
    viewportHeight = htmlview_ViewportHeight(htmlWidget)

    If wheelDelta <> 0 AndAlso mouseX >= htmlWidget->ax AndAlso _
       mouseX < htmlWidget->ax + htmlWidget->w - HTMLVIEW_SCROLLBAR_WIDTH AndAlso _
       mouseY >= htmlWidget->ay AndAlso mouseY < htmlWidget->ay + htmlWidget->h Then
        viewData->scrollY -= wheelDelta * HTMLVIEW_WHEEL_PIXELS
    End If

    hoveredLink = htmlview_LinkAt(htmlWidget, mouseX, mouseY)
    If leftButtonDown AndAlso viewData->mouseLatch = 0 Then
        viewData->armedLink = hoveredLink
    ElseIf leftButtonDown = 0 AndAlso viewData->mouseLatch <> 0 Then
        If Len(viewData->armedLink) > 0 AndAlso _
           viewData->armedLink = hoveredLink Then
            htmlview_ActivateLink htmlWidget, hoveredLink
        End If
        viewData->armedLink = ""
    End If
    viewData->mouseLatch = leftButtonDown

    If htmlWidget->has_focus Then
        htmlview_UpdateKeyboard viewData, viewportHeight
    Else
        viewData->keyLatch = 0
    End If

    htmlview_ClampScroll htmlWidget
End Sub


Sub htmlview_Render(ByVal htmlWidget As Widget Ptr)
    Dim As HtmlViewData Ptr viewData
    Dim As HtmlViewItem Ptr item
    Dim As Integer contentX
    Dim As Integer contentY
    Dim As Integer viewportWidth
    Dim As Integer viewportHeight
    Dim As Integer itemY
    Dim As Integer loadingTop
    Dim As String loadingText

    viewData = htmlview_Data(htmlWidget)
    If viewData = 0 Then Exit Sub

    backend_Rect _
        htmlWidget->ax, htmlWidget->ay, htmlWidget->w, htmlWidget->h, _
        viewData->documentBackgroundColor, 1
    backend_Rect _
        htmlWidget->ax, htmlWidget->ay, htmlWidget->w, htmlWidget->h, _
        theme_GetColor(GUI_COLOR_BORDER), 0

    contentX = htmlWidget->ax + 1 + viewData->padding
    contentY = htmlWidget->ay + 1 + viewData->padding
    viewportWidth = htmlWidget->w - HTMLVIEW_SCROLLBAR_WIDTH - _
        viewData->padding * 2 - 2
    viewportHeight = htmlview_ViewportHeight(htmlWidget)
    If viewportWidth < 1 Then viewportWidth = 1

    backend_SetClip contentX, contentY, viewportWidth, viewportHeight
    item = viewData->firstItem
    While item <> 0
        itemY = contentY + item->y - viewData->scrollY
        If itemY + item->h >= contentY AndAlso _
           itemY < contentY + viewportHeight Then
            If item->itemKind = HTMLVIEW_ITEM_BOX Then
                backend_Rect _
                    contentX + item->x, itemY, item->w, item->h, _
                    item->backgroundColor, 1
                backend_Rect _
                    contentX + item->x, itemY, item->w, item->h, _
                    item->color, 0
            ElseIf item->itemKind = HTMLVIEW_ITEM_RULE Then
                backend_Line _
                    contentX + item->x, itemY, _
                    contentX + item->x + item->w, itemY, item->color
            ElseIf item->itemKind = HTMLVIEW_ITEM_IMAGE AndAlso _
                   item->image <> 0 Then
                backend_DrawImage _
                    contentX + item->x, itemY, item->image->pixels, _
                    item->image->hasAlpha
            ElseIf item->itemKind = HTMLVIEW_ITEM_TEXT Then
                If item->codeBackground Then
                    backend_Rect _
                        contentX + item->x - 1, itemY - 1, _
                        item->w + 2, item->h + 2, item->backgroundColor, 1
                End If
                backend_PrintScaledFont _
                    contentX + item->x, itemY, item->color, item->text, _
                    item->fontId, item->scaleX, item->scaleY
                If item->underline Then
                    backend_Line _
                        contentX + item->x, itemY + item->h - 1, _
                        contentX + item->x + item->w, _
                        itemY + item->h - 1, item->color
                End If
            End If
        End If
        item = item->nextItem
    Wend
    backend_ResetClip

    If viewData->loadState = HTMLVIEW_LOAD_LOADING Then
        /'
            The overlay describes background work without replacing the last
            completed document.  It is intentionally small so navigation and
            already known values remain readable throughout the load.
        '/
        loadingTop = contentY + viewportHeight - 18
        If loadingTop < contentY Then loadingTop = contentY
        loadingText = "Loading " & _
            LTrim(Str(viewData->loadProgress)) & "%"
        backend_Rect _
            contentX, loadingTop, viewportWidth, 18, _
            viewData->codeBackgroundColor, 1
        backend_Rect _
            contentX, loadingTop, viewportWidth, 18, _
            theme_GetColor(GUI_COLOR_BORDER), 0
        backend_PrintFont _
            contentX + 4, loadingTop + 2, viewData->textColor, _
            loadingText, BACKEND_FONT_ARIAL_10_REGULAR
    End If

    htmlview_ClampScroll htmlWidget
    viewData->verticalScrollbar->render(viewData->verticalScrollbar)
End Sub


' -------------------------------------------------------------------------
' Construction and lifecycle
' -------------------------------------------------------------------------

Function htmlview_Create( _
    ByVal nm As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer _
) As Widget Ptr
    Dim As Widget Ptr htmlWidget
    Dim As HtmlViewData Ptr viewData

    If w < 1 Then w = 1
    If h < 1 Then h = 1

    htmlWidget = New Widget
    If htmlWidget = 0 Then Return 0
    viewData = New HtmlViewData
    If viewData = 0 Then
        Delete htmlWidget
        Return 0
    End If

    htmlWidget->name = nm
    htmlWidget->x = x
    htmlWidget->y = y
    htmlWidget->w = w
    htmlWidget->h = h
    htmlWidget->visible = 1
    htmlWidget->enabled = 1
    htmlWidget->accepts_focus = -1
    htmlWidget->render = @htmlview_Render
    htmlWidget->update = @htmlview_Update
    htmlWidget->destroy = @htmlview_Destroy
    htmlWidget->data = viewData

    viewData->padding = HTMLVIEW_DEFAULT_PADDING
    viewData->backgroundColor = theme_GetColor(GUI_COLOR_WIDGET_BG)
    viewData->textColor = theme_GetColor(GUI_COLOR_TEXT)
    viewData->linkColor = RGB(25, 72, 170)
    viewData->codeBackgroundColor = RGB(232, 234, 238)
    viewData->documentBackgroundColor = viewData->backgroundColor
    viewData->documentTextColor = viewData->textColor
    viewData->documentLinkColor = viewData->linkColor
    viewData->contentHeight = 1
    viewData->loadState = HTMLVIEW_LOAD_IDLE
    viewData->loadProgress = 0
    viewData->verticalScrollbar = scrollbar_Create( _
        nm & "_sb", x + w - HTMLVIEW_SCROLLBAR_WIDTH, y, _
        HTMLVIEW_SCROLLBAR_WIDTH, h, 0, 1, -1 _
    )
    If viewData->verticalScrollbar = 0 Then
        Delete viewData
        Delete htmlWidget
        Return 0
    End If

    htmlview_Reflow htmlWidget
    viewData->loadState = HTMLVIEW_LOAD_IDLE
    viewData->loadProgress = 0
    Return htmlWidget
End Function


Sub htmlview_Destroy(ByVal htmlWidget As Widget Ptr)
    Dim As HtmlViewData Ptr viewData

    If htmlWidget = 0 OrElse htmlWidget->data = 0 Then Exit Sub
    viewData = Cast(HtmlViewData Ptr, htmlWidget->data)
    If viewData->loadContext <> 0 Then
        htmlview_DestroyLoadContext _
            Cast(HtmlViewLoadContext Ptr, viewData->loadContext)
        viewData->loadContext = 0
    End If
    htmlview_DeleteItems viewData

    If viewData->verticalScrollbar <> 0 Then
        If viewData->verticalScrollbar->destroy <> 0 Then
            viewData->verticalScrollbar->destroy(viewData->verticalScrollbar)
        End If
        Delete viewData->verticalScrollbar
        viewData->verticalScrollbar = 0
    End If

    Delete viewData
    htmlWidget->data = 0
End Sub

/' end of htmlview.bas '/
