/'
    Project: omaGUI
    ---------------

    File: label.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements label.bi; declarations there define the interface.

    Purpose:

        Implement the noninteractive text-label widget.

    Responsibilities:

        - render static text with customizable colors and embedded fonts
        - distinguish theme-following text from literal 32-bit colors
        - render bounded portable text styles without host font services
        - optionally fill the label's bounded client rectangle
        - wrap configured labels at measured word and path boundaries
        - limit wrapped output so variable text cannot invade later controls
        - optionally clip fixed rectangles while retaining the caller's clip
        - align complete text blocks and each wrapped line in that rectangle
        - measure the same text layout without changing widget geometry
        - draw opt-in borders with a bounded text client rectangle

    This file intentionally does NOT contain:

        - text editing, selection, scrolling, or rich-text layout

    Ownership:

        - each label widget owns one LabelData allocation
'/

#lang "fb"
#include once "src/widgets/label.bi"
#include once "src/backend/theme.bi"

Const LABEL_WRAPPED_LINE_GAP As Integer = 2
' Keep new aligned-coordinate arithmetic within a portable signed range.
Const LABEL_LAYOUT_COORDINATE_LIMIT As Integer = 1000000

Private Function label_TextWidth( _
    ByRef textValue As Const String, ByVal fontId As Integer, _
    ByVal percent As Integer _
) As Integer
    If percent = 100 Then Return backend_GetTextWidthFont(textValue, fontId)
    Return backend_GetTextWidthFontPercent(textValue, fontId, percent)
End Function

Private Function label_TextHeight(ByVal fontId As Integer, ByVal percent As Integer) As Integer
    If percent = 100 Then Return backend_GetTextHeightFont(fontId)
    Return backend_GetTextHeightFontPercent(fontId, percent)
End Function

Private Sub label_PrintText( _
    ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, _
    ByRef textValue As Const String, ByVal fontId As Integer, _
    ByVal percent As Integer, ByVal textStyle As Integer, _
    ByVal textColorUsesTheme As Integer _
)
    If textColorUsesTheme Then clr = theme_GetColor(GUI_COLOR_TEXT)
    If textStyle = BACKEND_TEXT_STYLE_NORMAL AndAlso percent = 100 Then
        backend_PrintFont x, y, clr, textValue, fontId
        Exit Sub
    End If

    ' Keep advances unchanged; styles only add ink or draw within line height.
    If (textStyle And BACKEND_TEXT_STYLE_ITALIC) <> 0 Then
        backend_PrintItalicFontPercent x, y, clr, textValue, fontId, percent
    Else
        backend_PrintFontPercent x, y, clr, textValue, fontId, percent
    End If

    If (textStyle And BACKEND_TEXT_STYLE_BOLD) <> 0 Then
        Dim As Integer boldOffset = percent \ 100
        If boldOffset < 1 Then boldOffset = 1
        If (textStyle And BACKEND_TEXT_STYLE_ITALIC) <> 0 Then
            backend_PrintItalicFontPercent x + boldOffset, y, clr, _
                textValue, fontId, percent
        Else
            backend_PrintFontPercent x + boldOffset, y, clr, _
                textValue, fontId, percent
        End If
    End If

    Dim As Integer textWidth = _
        backend_GetTextWidthFontPercent(textValue, fontId, percent)
    Dim As Integer lineHeight = backend_GetTextHeightFontPercent( _
        fontId, percent)
    If textWidth > 0 AndAlso lineHeight > 1 Then
        If (textStyle And BACKEND_TEXT_STYLE_UNDERLINE) <> 0 Then _
            backend_Line x, y + lineHeight - 2, _
                x + textWidth - 1, y + lineHeight - 2, clr
        If (textStyle And BACKEND_TEXT_STYLE_STRIKEOUT) <> 0 Then _
            backend_Line x, y + lineHeight \ 2, _
                x + textWidth - 1, y + lineHeight \ 2, clr
    End If
End Sub


' -------------------------------------------------------------------------
' Private wrapping helpers
' -------------------------------------------------------------------------

Private Function label_IsWrapBoundary( _
    ByVal characterText As String _
) As Integer
    If characterText = " " OrElse characterText = Chr(9) OrElse _
       characterText = "/" OrElse characterText = "\" OrElse _
       characterText = "-" Then Return -1
    Return 0
End Function


Private Function label_FindLineLength( _
    ByVal sourceText As String, ByVal maximumWidth As Integer, _
    ByVal fontId As Integer, ByVal percent As Integer _
) As Long
    Dim As String characterText
    Dim As Long position
    Dim As Long lastBoundary
    Dim As Integer characterWidth
    Dim As Integer lineWidth

    If Len(sourceText) = 0 Then Return 0
    If maximumWidth < 1 Then Return Len(sourceText)

    For position = 1 To Len(sourceText)
        characterText = Mid(sourceText, position, 1)
        characterWidth = label_TextWidth(characterText, fontId, percent)
        If lineWidth + characterWidth > maximumWidth Then
            If lastBoundary > 0 Then Return lastBoundary
            If position > 1 Then Return position - 1
            Return 1
        End If
        lineWidth += characterWidth
        If label_IsWrapBoundary(characterText) Then lastBoundary = position
    Next position
    Return Len(sourceText)
End Function


Private Function label_Ellipsize( _
    ByVal sourceText As String, ByVal maximumWidth As Integer, _
    ByVal fontId As Integer, ByVal percent As Integer _
) As String
    Dim As String resultText = RTrim(sourceText)
    Dim As String suffixText = "..."

    While Len(suffixText) > 0 AndAlso _
          label_TextWidth(suffixText, fontId, percent) > maximumWidth
        suffixText = Left(suffixText, Len(suffixText) - 1)
    Wend
    While Len(resultText) > 0 AndAlso _
          label_TextWidth( _
              resultText & suffixText, fontId, percent _
          ) > maximumWidth
        resultText = RTrim(Left(resultText, Len(resultText) - 1))
    Wend
    Return resultText & suffixText
End Function


Private Sub label_TakeParagraph( _
    ByRef remainingText As String, ByRef paragraphText As String _
)
    Dim As Long carriagePosition
    Dim As Long lineFeedPosition
    Dim As Long newlinePosition
    Dim As Long newlineLength

    carriagePosition = InStr(remainingText, Chr(13))
    lineFeedPosition = InStr(remainingText, Chr(10))
    If carriagePosition > 0 AndAlso lineFeedPosition > 0 Then
        newlinePosition = IIf( _
            carriagePosition < lineFeedPosition, _
            carriagePosition, lineFeedPosition _
        )
    ElseIf carriagePosition > 0 Then
        newlinePosition = carriagePosition
    Else
        newlinePosition = lineFeedPosition
    End If

    If newlinePosition = 0 Then
        paragraphText = remainingText
        remainingText = ""
        Exit Sub
    End If

    paragraphText = Left(remainingText, newlinePosition - 1)
    newlineLength = 1
    If Mid(remainingText, newlinePosition, 1) = Chr(13) AndAlso _
       Mid(remainingText, newlinePosition + 1, 1) = Chr(10) Then
        newlineLength = 2
    End If
    remainingText = Mid( _
        remainingText, newlinePosition + newlineLength _
    )
End Sub


Private Sub label_DrawLayoutLine( _
    ByVal w As Widget Ptr, ByRef lineText As Const String, _
    ByVal topOffset As Integer, ByRef mnemonicDrawn As Integer _
)
    Dim As LabelData Ptr dataValue = Cast(LabelData Ptr, w->data)
    Dim As Integer drawX = w->ax
    Dim As Integer drawY = w->ay + topOffset
    Dim As Integer textWidth, characterIndex, glyphWidth, underlineX, underlineY

    If dataValue->alignmentOverride Then
        textWidth = label_TextWidth(lineText, dataValue->fontId, dataValue->fontPercent)
        Select Case dataValue->horizontalAlignment
        Case BACKEND_ALIGN_CENTER: drawX += (w->w - textWidth) \ 2
        Case BACKEND_ALIGN_RIGHT: drawX += w->w - textWidth
        End Select
    End If
    label_PrintText drawX, drawY, dataValue->clr, lineText, _
        dataValue->fontId, dataValue->fontPercent, dataValue->textStyle, _
        dataValue->textColorUsesTheme

    ' Aligned mnemonic decoration uses the same origin and embedded font as
    ' the glyphs. Draw only the first matching character across wrapped lines.
    If dataValue->alignmentOverride = 0 OrElse mnemonicDrawn OrElse w->mnemonic_key = 0 Then Exit Sub
    For characterIndex = 1 To Len(lineText)
        If gui_MnemonicScanCode(Asc(lineText, characterIndex)) <> w->mnemonic_key Then Continue For
        underlineX = drawX + label_TextWidth(Left(lineText, characterIndex - 1), dataValue->fontId, dataValue->fontPercent)
        glyphWidth = label_TextWidth(Mid(lineText, characterIndex, 1), dataValue->fontId, dataValue->fontPercent)
        underlineY = drawY + label_TextHeight(dataValue->fontId, dataValue->fontPercent) - 3
        If glyphWidth > 0 Then backend_Line underlineX, underlineY, _
            underlineX + glyphWidth - 1, underlineY, theme_GetClassicColor(GUI_CLASSIC_COLOR_ACCESS_TEXT)
        mnemonicDrawn = -1
        Exit For
    Next characterIndex
End Sub


Private Function label_LayoutWrapped( _
    ByVal w As Widget Ptr, ByVal renderText As Integer, _
    ByVal topOffset As Integer = 0, ByVal measuredWidth As Integer Ptr = 0 _
) As Integer
    Dim As LabelData Ptr dataValue
    Dim As String remainingText
    Dim As String paragraphText
    Dim As String lineText
    Dim As Long lineLength
    Dim As Integer lineCount
    Dim As Integer lineHeight
    Dim As Integer maximumLines
    Dim As Integer moreText
    Dim As Integer mnemonicDrawn

    If w = 0 OrElse w->data = 0 Then Return 0
    If measuredWidth <> 0 Then *measuredWidth = 0
    dataValue = Cast(LabelData Ptr, w->data)
    If dataValue->alignmentOverride AndAlso Len(dataValue->text) > LABEL_MAXIMUM_ALIGNED_TEXT_BYTES Then Return 0
    If (dataValue->wordWrap = 0 OrElse w->w < 1) AndAlso dataValue->alignmentOverride = 0 Then
        If measuredWidth <> 0 Then *measuredWidth = label_TextWidth(dataValue->text, dataValue->fontId, dataValue->fontPercent)
        If renderText Then
            label_PrintText _
                w->ax, w->ay, dataValue->clr, _
                dataValue->text, dataValue->fontId, dataValue->fontPercent, _
                dataValue->textStyle, dataValue->textColorUsesTheme
        End If
        Return IIf(Len(dataValue->text) > 0, 1, 0)
    End If

    maximumLines = dataValue->maximumLines
    If maximumLines < 1 OrElse _
       maximumLines > LABEL_MAXIMUM_WRAPPED_LINES Then
        maximumLines = LABEL_MAXIMUM_WRAPPED_LINES
    End If
    lineHeight = label_TextHeight(dataValue->fontId, dataValue->fontPercent) + _
        LABEL_WRAPPED_LINE_GAP
    If lineHeight < 1 Then lineHeight = 1
    remainingText = dataValue->text

    Do While Len(remainingText) > 0
        label_TakeParagraph remainingText, paragraphText

        If Len(paragraphText) = 0 Then
            lineText = ""
            moreText = IIf(Len(remainingText) > 0, -1, 0)
            If lineCount + 1 >= maximumLines AndAlso moreText Then
                lineText = label_Ellipsize( _
                    lineText, w->w, dataValue->fontId, dataValue->fontPercent _
                )
            End If
            lineCount += 1
            If measuredWidth <> 0 Then
                Dim As Integer lineWidth = label_TextWidth(lineText, dataValue->fontId, dataValue->fontPercent)
                If lineWidth > *measuredWidth Then *measuredWidth = lineWidth
            End If
            If renderText Then
                label_DrawLayoutLine w, lineText, _
                    topOffset + (lineCount - 1) * lineHeight, mnemonicDrawn
            End If
            If lineCount >= maximumLines Then Return lineCount
        Else
            Do While Len(paragraphText) > 0
                If dataValue->wordWrap Then
                    lineLength = label_FindLineLength( _
                        paragraphText, w->w, dataValue->fontId, dataValue->fontPercent _
                    )
                Else
                    lineLength = Len(paragraphText)
                End If
                If lineLength < 1 Then lineLength = 1
                lineText = Left(paragraphText, lineLength)
                If dataValue->wordWrap Then
                    lineText = RTrim(lineText)
                    If Len(lineText) = 0 Then lineText = Left(paragraphText, lineLength)
                End If
                paragraphText = Mid(paragraphText, lineLength + 1)
                While Left(paragraphText, 1) = " " OrElse _
                      Left(paragraphText, 1) = Chr(9)
                    paragraphText = Mid(paragraphText, 2)
                Wend

                moreText = IIf( _
                    Len(paragraphText) > 0 OrElse _
                    Len(remainingText) > 0, -1, 0 _
                )
                If lineCount + 1 >= maximumLines AndAlso moreText Then
                    lineText = label_Ellipsize( _
                        lineText, w->w, dataValue->fontId, dataValue->fontPercent _
                    )
                End If
                lineCount += 1
                If measuredWidth <> 0 Then
                    Dim As Integer lineWidth = label_TextWidth(lineText, dataValue->fontId, dataValue->fontPercent)
                    If lineWidth > *measuredWidth Then *measuredWidth = lineWidth
                End If
                If renderText Then
                    label_DrawLayoutLine w, lineText, _
                        topOffset + (lineCount - 1) * lineHeight, mnemonicDrawn
                End If
                If lineCount >= maximumLines Then Return lineCount
            Loop
        End If
    Loop
    Return lineCount
End Function

' -------------------------------------------------------------------------
' Construction
' -------------------------------------------------------------------------

Function label_Create( _
    ByVal nm As String, ByVal txt As String, ByVal x As Integer, _
    ByVal y As Integer, ByVal clr As ULong, ByVal fontId As Integer _
) As Widget Ptr
    Dim As Widget Ptr wgt = New Widget
    Dim As LabelData Ptr d = New LabelData

    If wgt = 0 Then
        If d <> 0 Then Delete d
        Return 0
    End If
    If d = 0 Then
        Delete wgt
        Return 0
    End If

    wgt->name = nm
    wgt->x = x
    wgt->y = y
    wgt->visible = 1
    wgt->enabled = 1
    wgt->render = @label_Render
    wgt->update = 0
    wgt->destroy = @label_Destroy

    d->text = gui_TransformText(txt)
    d->clr = clr
    d->fontId = fontId
    d->fontPercent = 100
    d->backgroundColorOverride = 0
    d->backgroundColor = 0
    d->clipToBounds = 0
    d->alignmentOverride = 0
    d->horizontalAlignment = BACKEND_ALIGN_LEFT
    d->verticalAlignment = BACKEND_ALIGN_TOP
    d->borderStyle = 0
    d->textStyle = BACKEND_TEXT_STYLE_NORMAL
    d->textColorUsesTheme = IIf(clr = LABEL_COLOR_THEME_TEXT, -1, 0)
    wgt->data = d
    Return wgt
End Function


Function label_CreateWithColor( _
    ByVal nm As String, ByVal txt As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal clr As ULong, ByVal fontId As Integer _
) As Widget Ptr
    Dim As Widget Ptr wgt = label_Create(nm, txt, x, y, clr, fontId)
    If wgt = 0 Then Return 0
    ' This constructor's contract treats every color bit pattern as literal.
    Cast(LabelData Ptr, wgt->data)->textColorUsesTheme = 0
    Return wgt
End Function

Sub label_SetFont(ByVal w As Widget Ptr, ByVal fontId As Integer)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    If backend_IsFontAvailable(fontId) = 0 Then Exit Sub
    Cast(LabelData Ptr, w->data)->fontId = fontId
End Sub

Sub label_SetFontScalePercent(ByVal w As Widget Ptr, ByVal percent As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then Exit Sub
    ' The backend accepts font scaling from 25 to 900 percent.
    If percent < 25 Then percent = 25
    If percent > 900 Then percent = 900
    Cast(LabelData Ptr, w->data)->fontPercent = percent
End Sub


Function label_SetTextStyle( _
    ByVal w As Widget Ptr, ByVal textStyle As Integer _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then Return 0
    If (textStyle And Not BACKEND_TEXT_STYLE_ALL) <> 0 Then Return 0
    Cast(LabelData Ptr, w->data)->textStyle = textStyle
    Return -1
End Function


Function label_GetTextStyle(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then Return 0
    Return Cast(LabelData Ptr, w->data)->textStyle
End Function


Function label_SetTextColor( _
    ByVal w As Widget Ptr, ByVal textColor As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(LabelData Ptr, w->data)->clr = textColor
    Cast(LabelData Ptr, w->data)->textColorUsesTheme = _
        IIf(textColor = LABEL_COLOR_THEME_TEXT, -1, 0)
    Return -1
End Function


Function label_SetTextColorLiteral( _
    ByVal w As Widget Ptr, ByVal textColor As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then Return 0
    Cast(LabelData Ptr, w->data)->clr = textColor
    Cast(LabelData Ptr, w->data)->textColorUsesTheme = 0
    Return -1
End Function


Function label_GetTextColor( _
    ByVal w As Widget Ptr, ByRef textColor As ULong _
) As Integer
    textColor = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    textColor = Cast(LabelData Ptr, w->data)->clr
    Return -1
End Function


Function label_SetBackgroundColor( _
    ByVal w As Widget Ptr, ByVal backgroundColor As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(LabelData Ptr, w->data)
        .backgroundColor = backgroundColor
        .backgroundColorOverride = -1
    End With
    Return -1
End Function


Function label_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(LabelData Ptr, w->data)->backgroundColorOverride = 0
    Return -1
End Function


Function label_GetBackgroundColor( _
    ByVal w As Widget Ptr, ByRef backgroundColor As ULong _
) As Integer
    Dim As LabelData Ptr dataValue

    backgroundColor = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    dataValue = Cast(LabelData Ptr, w->data)
    If dataValue->backgroundColorOverride = 0 Then Return 0
    backgroundColor = dataValue->backgroundColor
    Return -1
End Function


Sub label_SetWordWrap( _
    ByVal w As Widget Ptr, ByVal maximumWidth As Integer, _
    ByVal maximumLines As Integer _
)
    Dim As LabelData Ptr dataValue

    If w = 0 OrElse w->data = 0 Then Exit Sub
    dataValue = Cast(LabelData Ptr, w->data)
    If maximumWidth < 1 Then
        dataValue->wordWrap = 0
        dataValue->maximumLines = 0
        w->w = 0
        Exit Sub
    End If
    If maximumLines < 1 OrElse _
       maximumLines > LABEL_MAXIMUM_WRAPPED_LINES Then
        maximumLines = LABEL_MAXIMUM_WRAPPED_LINES
    End If
    dataValue->wordWrap = -1
    dataValue->maximumLines = maximumLines
    w->w = maximumWidth
End Sub


Function label_GetRenderedLineCount(ByVal w As Widget Ptr) As Integer
    If w <> 0 AndAlso w->data <> 0 AndAlso w->destroy = @label_Destroy Then
        If Cast(LabelData Ptr, w->data)->borderStyle Then
            Dim As Widget client = *w
            client.w -= 4
            If client.w < 1 Then Return 0
            Return label_LayoutWrapped(@client, 0)
        End If
    End If
    Return label_LayoutWrapped(w, 0)
End Function

' -------------------------------------------------------------------------
' Rendering
' -------------------------------------------------------------------------

Private Sub label_RenderContent(ByVal w As Widget Ptr)
    Dim As LabelData Ptr dataValue
    Dim As Integer lineCount, textHeight, topOffset

    If w = 0 OrElse w->data = 0 Then Exit Sub
    dataValue = Cast(LabelData Ptr, w->data)
    If dataValue->alignmentOverride Then
        ' New bounded layout requires a usable rectangle. Check before any
        ' clip push so early returns cannot disturb the caller's clip stack.
        If Len(dataValue->text) > LABEL_MAXIMUM_ALIGNED_TEXT_BYTES Then Exit Sub
        If w->w < 1 OrElse w->w > LABEL_LAYOUT_COORDINATE_LIMIT OrElse _
           w->h < 1 OrElse w->h > LABEL_LAYOUT_COORDINATE_LIMIT OrElse _
           w->ax < -LABEL_LAYOUT_COORDINATE_LIMIT OrElse w->ax > LABEL_LAYOUT_COORDINATE_LIMIT OrElse _
           w->ay < -LABEL_LAYOUT_COORDINATE_LIMIT OrElse w->ay > LABEL_LAYOUT_COORDINATE_LIMIT Then Exit Sub
        If dataValue->verticalAlignment <> BACKEND_ALIGN_TOP Then
            ' Count the same wrapped/ellipsized lines before positioning the
            ' whole block. No temporary image or platform text API is needed.
            lineCount = label_LayoutWrapped(w, 0)
            If lineCount > 0 Then
                textHeight = lineCount * (label_TextHeight(dataValue->fontId, dataValue->fontPercent) + _
                    LABEL_WRAPPED_LINE_GAP) - LABEL_WRAPPED_LINE_GAP
                Select Case dataValue->verticalAlignment
                Case BACKEND_ALIGN_MIDDLE: topOffset = (w->h - textHeight) \ 2
                Case BACKEND_ALIGN_BOTTOM: topOffset = w->h - textHeight
                End Select
            End If
        End If
    End If
    If dataValue->clipToBounds Then
        If w->w < 1 OrElse w->h < 1 Then Exit Sub
        backend_SetClip w->ax, w->ay, w->w, w->h
    End If
    If dataValue->backgroundColorOverride <> 0 AndAlso _
       w->w > 0 AndAlso w->h > 0 Then
        backend_Rect w->ax, w->ay, w->w, w->h, _
            dataValue->backgroundColor, -1
    End If
    label_LayoutWrapped w, -1, topOffset
    If dataValue->wordWrap = 0 AndAlso dataValue->alignmentOverride = 0 Then _
        gui_RenderMnemonicUnderline _
            w, dataValue->text, w->ax, w->ay, _
            label_TextHeight(dataValue->fontId, dataValue->fontPercent)
    If dataValue->clipToBounds Then backend_ResetClip
End Sub

Sub label_Render(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As LabelData Ptr dataValue = Cast(LabelData Ptr, w->data)
    If dataValue->borderStyle = 0 Then
        label_RenderContent w
        Exit Sub
    End If
    If w->w < 1 OrElse w->h < 1 OrElse w->w > LABEL_LAYOUT_COORDINATE_LIMIT OrElse _
       w->h > LABEL_LAYOUT_COORDINATE_LIMIT OrElse Abs(CLngInt(w->ax)) > LABEL_LAYOUT_COORDINATE_LIMIT OrElse _
       Abs(CLngInt(w->ay)) > LABEL_LAYOUT_COORDINATE_LIMIT Then Exit Sub
    backend_SetClip w->ax, w->ay, w->w, w->h
    If dataValue->backgroundColorOverride Then backend_Rect w->ax, w->ay, w->w, w->h, dataValue->backgroundColor, -1
    backend_Rect w->ax, w->ay, w->w, w->h, theme_GetClassicColor(GUI_CLASSIC_COLOR_WINDOW_FRAME), 0
    If w->w > 4 AndAlso w->h > 4 Then
        ' A borrowed stack copy changes only the layout rectangle, never the
        ' registry widget or its owned data. Two pixels separate text and frame.
        Dim As Widget client = *w
        client.ax += 2: client.ay += 2
        client.w -= 4: client.h -= 4
        label_RenderContent @client
    End If
    backend_ResetClip
End Sub

Function label_SetBorderStyle(ByVal w As Widget Ptr, ByVal borderStyle As Integer) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then Return 0
    If borderStyle < 0 OrElse borderStyle > 1 Then Return 0
    Cast(LabelData Ptr, w->data)->borderStyle = borderStyle
    Return -1
End Function

Function label_GetBorderStyle(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then Return 0
    Return Cast(LabelData Ptr, w->data)->borderStyle
End Function

Function label_GetTextSize(ByVal w As Widget Ptr, ByRef textWidth As Integer, ByRef textHeight As Integer) As Integer
    textWidth = 0: textHeight = 0
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then Return 0
    Dim As LabelData Ptr dataValue = Cast(LabelData Ptr, w->data)
    If Len(dataValue->text) > LABEL_MAXIMUM_ALIGNED_TEXT_BYTES Then Return 0
    If w->w < 0 OrElse w->w > LABEL_LAYOUT_COORDINATE_LIMIT Then Return 0
    Dim As Widget client = *w
    Dim As Integer inset = IIf(dataValue->borderStyle, 2, 0)
    client.w -= inset * 2
    If dataValue->wordWrap AndAlso client.w < 1 Then Return 0
    Dim As Integer lineCount = label_LayoutWrapped(@client, 0, 0, @textWidth)
    If lineCount = 0 Then lineCount = 1
    textWidth += inset * 2
    textHeight = lineCount * (label_TextHeight(dataValue->fontId, dataValue->fontPercent) + LABEL_WRAPPED_LINE_GAP) - LABEL_WRAPPED_LINE_GAP + inset * 2
    Return -1
End Function

Function label_SetClipToBounds(ByVal w As Widget Ptr, ByVal enabled As Integer) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then Return 0
    Cast(LabelData Ptr, w->data)->clipToBounds = IIf(enabled, -1, 0)
    Return -1
End Function

Function label_GetClipToBounds(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then Return 0
    Return Cast(LabelData Ptr, w->data)->clipToBounds
End Function

Function label_SetAlignment( _
    ByVal w As Widget Ptr, ByVal horizontalAlignment As Integer, _
    ByVal verticalAlignment As Integer _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then Return 0
    If horizontalAlignment < BACKEND_ALIGN_LEFT OrElse horizontalAlignment > BACKEND_ALIGN_RIGHT Then Return 0
    If verticalAlignment < BACKEND_ALIGN_TOP OrElse verticalAlignment > BACKEND_ALIGN_BOTTOM Then Return 0
    If Len(Cast(LabelData Ptr, w->data)->text) > LABEL_MAXIMUM_ALIGNED_TEXT_BYTES Then Return 0
    With *Cast(LabelData Ptr, w->data)
        .horizontalAlignment = horizontalAlignment
        .verticalAlignment = verticalAlignment
        .alignmentOverride = -1
    End With
    Return -1
End Function

Function label_GetAlignment( _
    ByVal w As Widget Ptr, ByRef horizontalAlignment As Integer, _
    ByRef verticalAlignment As Integer _
) As Integer
    horizontalAlignment = BACKEND_ALIGN_LEFT
    verticalAlignment = BACKEND_ALIGN_TOP
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then Return 0
    With *Cast(LabelData Ptr, w->data)
        horizontalAlignment = .horizontalAlignment
        verticalAlignment = .verticalAlignment
    End With
    Return -1
End Function

Function label_ClearAlignment(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then Return 0
    With *Cast(LabelData Ptr, w->data)
        .horizontalAlignment = BACKEND_ALIGN_LEFT
        .verticalAlignment = BACKEND_ALIGN_TOP
        .alignmentOverride = 0
    End With
    Return -1
End Function

' -------------------------------------------------------------------------
' Lifecycle
' -------------------------------------------------------------------------

Sub label_Destroy(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Delete Cast(LabelData Ptr, w->data)
    w->data = 0
End Sub

Function label_SetText( _
    ByVal w As Widget Ptr, ByRef text_value As Const String _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then _
        Return 0
    If Cast(LabelData Ptr, w->data)->alignmentOverride AndAlso _
       Len(text_value) > LABEL_MAXIMUM_ALIGNED_TEXT_BYTES Then Return 0
    Cast(LabelData Ptr, w->data)->text = gui_TransformText(text_value)
    Return -1
End Function

Function label_GetText(ByVal w As Widget Ptr) As String
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @label_Destroy Then _
        Return ""
    Return Cast(LabelData Ptr, w->data)->text
End Function

/' end of label.bas '/
