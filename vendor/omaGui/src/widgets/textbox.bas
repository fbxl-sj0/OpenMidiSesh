/'
    Project: omaGUI
    ---------------

    File: textbox.bas

    Purpose:

        Implement a reusable text editor widget for both compact controls and
        multiline authoring surfaces such as the JRPG object-script popup.

    Responsibilities:

        - insert and remove text at the active cursor position
        - dispatch ordered KeyDown and KeyUp callbacks around text editing
        - let callers transform or cancel character input before editing
        - enforce optional byte limits before insertion and history changes
        - place the cursor and select text with mouse or keyboard input
        - provide selection-aware Cut, Copy, Paste, and Select All commands
        - mask displayed text and metrics while preventing Copy/Cut export
        - route opt-in block indentation to one reusable edit transaction
        - route Ctrl+Z and Ctrl+Y to the textbox's local history
        - navigate logical lines with arrow, home, and end keys
        - keep the active cursor within the visible viewport
        - render and operate an optional multiline vertical scrollbar
        - use one visual-line model for wrapping, scrolling, and hit testing
        - optionally render fixed logical line numbers beside multiline text
        - honor optional per-widget client and text colors
        - style ordinary, selected, masked, and syntax-colored text consistently
        - optionally color FreeBASIC keywords, comments, strings, numbers,
          preprocessor directives, built-in types, commands, procedures,
          macros, variables, constants, members, and labels

    Targets:

        FreeBASIC builds with built-in gfxlib; gfxlib3 is optional when supplied by the compiler.

    Module API:

        Implementation unit assembled by omaGUI.bi when OMAGUI_IMPLEMENTATION is defined.

    This file intentionally does NOT contain:

        - application-specific text validation
        - platform clipboard implementation
'/

#lang "fb"

#include once "crt/string.bi"
#include once "src/widgets/textbox.bi"
#include once "src/widgets/menu.bi"
#include once "src/widgets/scrollbar.bi"
#include once "src/backend/clipboard.bi"
#include once "src/backend/theme.bi"

' -------------------------------------------------------------------------
' Text editing constants
' -------------------------------------------------------------------------

Const TEXTBOX_LINE_HEIGHT As Integer = 14
Const TEXTBOX_LINE_FEED As Integer = 10
Const TEXTBOX_CARRIAGE_RETURN As Integer = 13
Const TEXTBOX_TEXT_LEFT_PADDING As Integer = 5
Const TEXTBOX_TEXT_RIGHT_PADDING As Integer = 10
Const TEXTBOX_TEXT_BOTTOM_PADDING As Integer = 15
Const TEXTBOX_KEY_LATCH_BACKSPACE As Integer = 1
Const TEXTBOX_KEY_LATCH_DELETE As Integer = 2
Const TEXTBOX_KEY_LATCH_RETURN As Integer = 4
Const TEXTBOX_KEY_LATCH_LEFT As Integer = 8
Const TEXTBOX_KEY_LATCH_RIGHT As Integer = 16
Const TEXTBOX_KEY_LATCH_HOME As Integer = 32
Const TEXTBOX_KEY_LATCH_END As Integer = 64
Const TEXTBOX_KEY_LATCH_UP As Integer = 128
Const TEXTBOX_KEY_LATCH_DOWN As Integer = 256
Const TEXTBOX_KEY_LATCH_UNDO As Integer = 512
Const TEXTBOX_KEY_LATCH_REDO As Integer = 1024
Const TEXTBOX_KEY_LATCH_SELECT_ALL As Integer = 2048
Const TEXTBOX_KEY_LATCH_COPY As Integer = 4096
Const TEXTBOX_KEY_LATCH_CUT As Integer = 8192
Const TEXTBOX_KEY_LATCH_PASTE As Integer = 16384
Const TEXTBOX_KEY_LATCH_INDENT As Integer = 32768
Const TEXTBOX_KEY_LATCH_UNINDENT As Integer = 65536
Const TEXTBOX_HISTORY_IDLE_FRAME_LIMIT As Integer = 30
Const TEXTBOX_CURSOR_VISIBLE_WIDTH As Integer = 2
Const TEXTBOX_SCROLLBAR_WIDTH As Integer = 15
Const TEXTBOX_SCROLLBAR_INSET As Integer = 2
Const TEXTBOX_WHEEL_LINES As Integer = 3
Const TEXTBOX_LINE_NUMBER_PADDING As Integer = 4
Const TEXTBOX_LINE_NUMBER_SEPARATOR_WIDTH As Integer = 1
' ASCII double quote is kept as a constant so the lexer can recognize it
' without relying on a hard-to-read escaped BASIC string literal.
Const TEXTBOX_DOUBLE_QUOTE As Integer = 34

' -------------------------------------------------------------------------
' Shared widget state
' -------------------------------------------------------------------------

Dim Shared As Widget Ptr textbox_context_menu = 0
Dim Shared As Widget Ptr active_textbox = 0
' KeyDown callbacks run on the GUI thread. A nested Update must not dispatch
' the same input frame again while a callback is active.
Dim Shared As Integer textbox_key_down_dispatch_depth

' -------------------------------------------------------------------------
' Internal helpers
' -------------------------------------------------------------------------

Private Function textbox_IsMasked(ByVal text_data As TextBoxData Ptr) As Integer
    If text_data = 0 Then Return 0
    ' FB-LINTER: DISABLE-NEXT-LINE FBL008 FBL-SEC-004 REASON: This reads the display-mode flag only.
    Return text_data->password_character <> 0
End Function

Private Function textbox_MaskCharacter(ByVal text_data As TextBoxData Ptr) As Integer
    If text_data = 0 Then Return 0
    ' FB-LINTER: DISABLE-NEXT-LINE FBL008 FBL-SEC-004 REASON: This returns the selected display glyph only.
    Return text_data->password_character
End Function

Private Function textbox_MaskedText( _
    ByVal text_data As TextBoxData Ptr _
) ByRef As String
    ' FB-LINTER: DISABLE-NEXT-LINE FBL008 FBL-SEC-004 REASON: This checks the cached mask string length only.
    If Len(text_data->password_display) <> Len(text_data->text) Then
        ' FB-LINTER: DISABLE-NEXT-LINE FBL008 FBL-SEC-004 REASON: The cache stores repeated mask glyphs, not source text.
        text_data->password_display = String( _
            Len(text_data->text), textbox_MaskCharacter(text_data) _
        )
    End If
    ' FB-LINTER: DISABLE-NEXT-LINE FBL008 FBL-SEC-004 REASON: The returned cache contains only mask glyphs.
    Return text_data->password_display
End Function

Private Function textbox_VisualText( _
    ByVal textData As TextBoxData Ptr _
) ByRef As String
    /'
        All callers hold live TextBoxData on the GUI thread. Drawing, hit
        testing, selection widths, and scrolling borrow this same byte-indexed
        view. Real text and undo history never contain the mask. Cache only the
        mask, so ordinary editors incur no extra full-text copy here. Editor
        transforms use change_serial because comparing the whole source for
        every visual row makes long documents unnecessarily expensive.
    '/
    If textbox_IsMasked(textData) = 0 Then
        If textData->text_display_handler = 0 Then Return textData->text
        If textData->display_valid <> 0 AndAlso _
           textData->display_change_serial = textData->change_serial AndAlso _
           textData->display_source_length = Len(textData->text) Then _
            Return textData->display_text

        /'
            Direct TextBoxData text replacement must advance change_serial.
            Length is checked as a second guard for accidental omissions.
            Every transformed byte occupies its original source position.
        '/
        textData->display_text = textData->text
        Dim As Integer scanPosition
        Dim As Integer displayState
        While scanPosition < Len(textData->text)
            Dim As Integer lineEnd = scanPosition
            While lineEnd < Len(textData->text)
                If textData->text[lineEnd] = TEXTBOX_LINE_FEED OrElse _
                   textData->text[lineEnd] = TEXTBOX_CARRIAGE_RETURN Then _
                    Exit While
                lineEnd += 1
            Wend
            Dim As String lineText = Mid( _
                textData->text, scanPosition + 1, lineEnd - scanPosition _
            )
            For characterIndex As Integer = 0 To Len(lineText) - 1
                Dim As Integer displayByte = textData->text_display_handler( _
                    lineText, characterIndex, displayState _
                )
                If displayByte < 0 OrElse displayByte > 255 Then _
                    displayByte = lineText[characterIndex]
                Mid( _
                    textData->display_text, _
                    scanPosition + characterIndex + 1, 1 _
                ) = Chr(displayByte)
            Next characterIndex
            If displayState = 5 Then displayState = 0
            scanPosition = lineEnd
            If scanPosition < Len(textData->text) Then
                If textData->text[scanPosition] = TEXTBOX_CARRIAGE_RETURN AndAlso _
                   scanPosition + 1 < Len(textData->text) AndAlso _
                   textData->text[scanPosition + 1] = TEXTBOX_LINE_FEED Then
                    scanPosition += 2
                Else
                    scanPosition += 1
                End If
            End If
        Wend
        textData->display_change_serial = textData->change_serial
        textData->display_source_length = Len(textData->text)
        textData->display_valid = -1
        Return textData->display_text
    End If
    Return textbox_MaskedText(textData)
End Function


Private Function textbox_FontPercent(ByVal textData As TextBoxData Ptr) As Integer
    If textData = 0 Then Return 100
    Dim As Integer fontPercent = _
        (textData->font_scale_percent * textData->zoom_percent + 50) \ 100
    If fontPercent < BACKEND_MIN_FONT_PERCENT Then _
        fontPercent = BACKEND_MIN_FONT_PERCENT
    If fontPercent > BACKEND_MAX_FONT_PERCENT Then _
        fontPercent = BACKEND_MAX_FONT_PERCENT
    Return fontPercent
End Function


Private Function textbox_TextWidth( _
    ByVal textData As TextBoxData Ptr, ByRef textValue As Const String _
) As Integer
    If textData = 0 Then Return backend_GetTextWidth(textValue)
    Return backend_GetTextWidthFontPercent( _
        textValue, textData->font_id, textbox_FontPercent(textData) _
    )
End Function


Private Function textbox_LineHeight(ByVal textData As TextBoxData Ptr) As Integer
    If textData = 0 Then Return TEXTBOX_LINE_HEIGHT
    If textbox_FontPercent(textData) = 100 AndAlso _
       textData->font_id = BACKEND_FONT_DEFAULT AndAlso _
       textData->extra_line_spacing = 0 Then Return TEXTBOX_LINE_HEIGHT
    Dim As Integer height = backend_GetTextHeightFontPercent( _
        textData->font_id, textbox_FontPercent(textData) _
    )
    height += (textData->extra_line_spacing * _
        textData->zoom_percent + 50) \ 100
    If height < 1 Then height = 1
    Return height
End Function


Private Function textbox_TextPadding(ByVal textData As TextBoxData Ptr) As Integer
    If textData = 0 Then Return TEXTBOX_TEXT_LEFT_PADDING
    Dim As Integer padding = (TEXTBOX_TEXT_LEFT_PADDING * _
        textbox_FontPercent(textData) + 50) \ 100
    If padding < 1 Then padding = 1
    Return padding
End Function


Private Function textbox_TotalGutterWidth( _
    ByVal textData As TextBoxData Ptr _
) As Integer
    If textData = 0 Then Return 0
    Return textData->line_number_gutter_width + textData->fold_gutter_width
End Function


Private Function textbox_ScaledPadding( _
    ByVal textData As TextBoxData Ptr, ByVal basePixels As Integer _
) As Integer
    If textData = 0 Then Return basePixels
    Dim As Integer padding = _
        (basePixels * textbox_FontPercent(textData) + 50) \ 100
    If padding < 1 Then padding = 1
    Return padding
End Function


Private Sub textbox_PrintStyled( _
    ByVal textData As TextBoxData Ptr, _
    ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, _
    ByRef textValue As Const String, ByVal styleFlags As Integer _
)
    If textData = 0 Then Exit Sub
    Dim As Integer percent = textbox_FontPercent(textData)
    If percent = 100 Then
        backend_PrintStyled x, y, clr, textValue, styleFlags, textData->font_id
        Exit Sub
    End If

    If (styleFlags And BACKEND_TEXT_STYLE_ITALIC) <> 0 Then
        backend_PrintItalicFontPercent x, y, clr, textValue, _
            textData->font_id, percent
    Else
        backend_PrintFontPercent x, y, clr, textValue, _
            textData->font_id, percent
    End If
    If (styleFlags And BACKEND_TEXT_STYLE_BOLD) <> 0 Then
        Dim As Integer boldOffset = percent \ 100
        If boldOffset < 1 Then boldOffset = 1
        backend_PrintFontPercent x + boldOffset, y, clr, textValue, _
            textData->font_id, percent
    End If
    Dim As Integer textWidth = textbox_TextWidth(textData, textValue)
    Dim As Integer lineHeight = textbox_LineHeight(textData)
    If textWidth > 0 Then
        If (styleFlags And BACKEND_TEXT_STYLE_UNDERLINE) <> 0 Then _
            backend_Line x, y + lineHeight - 2, _
                x + textWidth - 1, y + lineHeight - 2, clr
        If (styleFlags And BACKEND_TEXT_STYLE_STRIKEOUT) <> 0 Then _
            backend_Line x, y + lineHeight \ 2, _
                x + textWidth - 1, y + lineHeight \ 2, clr
    End If
End Sub

Declare Function textbox_ClampPosition(ByRef textValue As Const String, ByVal position As Integer) As Integer
Declare Sub textbox_CollapseSelection(ByVal textData As TextBoxData Ptr, ByVal position As Integer)
Declare Sub textbox_ExtendSelection(ByVal textData As TextBoxData Ptr, ByVal position As Integer)
Declare Sub textbox_DeleteSelection(ByVal textData As TextBoxData Ptr)
Declare Function textbox_SelectedText(ByVal textData As TextBoxData Ptr) As String
Declare Sub textbox_InsertText(ByVal textData As TextBoxData Ptr, ByVal insertedText As String)
Declare Function textbox_ConstrainInput(ByVal textData As TextBoxData Ptr, ByRef insertedText As String) As Integer
Declare Sub textbox_ClearKeyLatch(ByVal textData As TextBoxData Ptr, ByVal keyCode As Integer, ByVal keyMask As Integer)
Declare Sub textbox_RefreshKeyLatch(ByVal textData As TextBoxData Ptr)
Declare Function textbox_KeyJustPressed(ByVal textData As TextBoxData Ptr, ByVal keyCode As Integer, ByVal keyMask As Integer) As Integer
Declare Function textbox_ControlShortcutJustPressed( _
    ByVal textData As TextBoxData Ptr, _
    ByVal keyCode As Integer, _
    ByVal keyMask As Integer _
) As Integer
Declare Function textbox_LineStart(ByRef textValue As Const String, ByVal position As Integer) As Integer
Declare Function textbox_LineEnd(ByRef textValue As Const String, ByVal position As Integer) As Integer
Declare Function textbox_LineStartByIndex( _
    ByRef textValue As Const String, _
    ByVal lineIndex As Integer _
) As Integer
Declare Function textbox_NextVisualLine( _
    ByRef textValue As Const String, _
    ByRef scanPosition As Integer, _
    ByVal wordwrap As Integer, _
    ByVal contentWidth As Integer, _
    ByRef lineStart As Integer, _
    ByRef lineEnd As Integer, _
    ByVal textData As TextBoxData Ptr = 0 _
) As Integer
Declare Function textbox_CountVisualLines( _
    ByRef textValue As Const String, _
    ByVal wordwrap As Integer, _
    ByVal contentWidth As Integer, _
    ByVal textData As TextBoxData Ptr = 0, _
    ByVal buildRowIndex As Integer = 0 _
) As Integer
Declare Function textbox_VisualLineAtPosition( _
    ByRef textValue As Const String, _
    ByVal position As Integer, _
    ByVal wordwrap As Integer, _
    ByVal contentWidth As Integer, _
    ByRef lineStart As Integer, _
    ByRef lineEnd As Integer, _
    ByRef boundsFound As Integer, _
    ByVal textData As TextBoxData Ptr _
) As Integer
Declare Function textbox_VisualLineForPosition( _
    ByRef textValue As Const String, _
    ByVal position As Integer, _
    ByVal wordwrap As Integer, _
    ByVal contentWidth As Integer, _
    ByVal textData As TextBoxData Ptr = 0 _
) As Integer
Declare Function textbox_VisualLineBounds( _
    ByRef textValue As Const String, _
    ByVal targetLine As Integer, _
    ByVal wordwrap As Integer, _
    ByVal contentWidth As Integer, _
    ByRef lineStart As Integer, _
    ByRef lineEnd As Integer, _
    ByVal textData As TextBoxData Ptr = 0 _
) As Integer
Declare Function textbox_VisibleLineCount( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr _
) As Integer
Declare Function textbox_ContentWidth( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr _
) As Integer
Declare Function textbox_LineNumberGutterWidth( _
    ByVal textData As TextBoxData Ptr _
) As Integer
Declare Sub textbox_RenderLineNumber( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr, _
    ByVal visualLine As Integer, ByVal logicalLine As Integer, _
    ByVal lineStart As Integer _
)
Declare Function textbox_MaximumLineWidth( _
    ByRef textValue As Const String, _
    ByVal textData As TextBoxData Ptr = 0 _
) As Integer
Declare Sub textbox_UpdateScrollMetrics( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr _
)
Declare Function textbox_PointInOwnedScrollbar( _
    ByVal scrollWidget As Widget Ptr, _
    ByVal mouseX As Integer, ByVal mouseY As Integer _
) As Integer
Declare Function textbox_HandleScrollInput( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr, _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer, _
    ByVal mouseButtons As Integer _
) As Integer
Declare Function textbox_PositionFromPoint( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr, _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer, _
    ByRef virtualSpace As Integer _
) As Integer
Declare Function textbox_ShiftPressed() As Integer
Declare Sub textbox_MoveCursorVertical( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr, _
    ByVal direction As Integer, _
    ByVal extendSelection As Integer _
)
Declare Function textbox_LineForPosition(ByVal textValue As String, ByVal position As Integer) As Integer
Declare Sub textbox_EnsureCursorVisible(ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr)
Declare Sub textbox_RenderLine( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr, _
    ByVal lineIndex As Integer, _
    ByVal lineStart As Integer, _
    ByVal lineText As String _
)
Declare Function textbox_IsIdentifierStart(ByVal character_code As Integer) As Integer
Declare Function textbox_IsIdentifierPart(ByVal character_code As Integer) As Integer
Declare Function textbox_IsFreeBasicType(ByVal token_text As String) As Integer
Declare Function textbox_IsFreeBasicKeyword(ByVal token_text As String) As Integer
Declare Function textbox_IsFreeBasicCommand(ByVal token_text As String) As Integer
Declare Function textbox_IsFreeBasicConstant(ByVal token_text As String) As Integer
Declare Function textbox_FreeBasicPreviousIdentifier( _
    ByRef line_text As Const String, ByVal position As Integer _
) As String
Declare Function textbox_FreeBasicNextSignificant( _
    ByRef line_text As Const String, ByVal position As Integer _
) As Integer
Declare Function textbox_IsFreeBasicMacroDefinition( _
    ByRef line_text As Const String, ByVal position As Integer _
) As Integer
Declare Function textbox_IsFreeBasicMacroDefined( _
    ByRef source_text As Const String, ByVal token_text As String _
) As Integer
Declare Function textbox_IsFreeBasicProcedureDefined( _
    ByRef source_text As Const String, ByVal token_text As String _
) As Integer
Declare Function textbox_IsFreeBasicDefinedType( _
    ByRef source_text As Const String, ByVal token_text As String _
) As Integer
Declare Function textbox_IsFreeBasicObjectVariableDefined( _
    ByRef source_text As Const String, ByVal token_text As String _
) As Integer
Declare Function textbox_ClassifyFreeBasicIdentifier( _
    ByRef source_text As Const String, ByRef line_text As Const String, _
    ByVal position As Integer, ByVal token_end As Integer, _
    ByRef token_text As Const String _
) As Integer
Declare Function textbox_GetSyntaxColorValue( _
    ByVal textData As TextBoxData Ptr, ByVal color_kind As Integer _
) As ULong
Declare Function textbox_FreeBasicBlockCommentBefore( _
    ByRef source_text As Const String, ByVal limit_position As Integer _
) As Integer
Declare Sub textbox_DrawTextPart( _
    ByVal textData As TextBoxData Ptr, _
    ByRef draw_x As Integer, ByVal draw_y As Integer, _
    ByVal part_text As String, ByVal text_color As ULong _
)
Declare Sub textbox_RenderTextSpan( _
    ByVal textData As TextBoxData Ptr, _
    ByRef draw_x As Integer, ByVal draw_y As Integer, _
    ByRef line_text As Const String, ByVal line_start As Integer, _
    ByVal span_start As Integer, ByVal span_end As Integer, _
    ByVal text_color As ULong, ByVal selected_start As Integer, _
    ByVal selected_end As Integer _
)
Declare Sub textbox_RenderSyntaxLine( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr, _
    ByVal draw_x As Integer, ByVal draw_y As Integer, _
    ByVal line_start As Integer, ByRef line_text As Const String, _
    ByVal text_color As ULong, ByVal selected_start As Integer, _
    ByVal selected_end As Integer _
)
Declare Sub textbox_HandleDeletionInput( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr _
)
Declare Sub textbox_HandleNavigationInput( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr _
)
Declare Sub textbox_HandleMouseInput( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr, _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer, _
    ByVal mouseButtons As Integer _
)
Declare Function textbox_HandleTabInput( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr _
) As Integer
Declare Function textbox_HandleControlInput( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr _
) As Integer


Private Function textbox_IsIdentifierStart(ByVal character_code As Integer) As Integer

    If character_code >= Asc("A") AndAlso character_code <= Asc("Z") Then Return -1
    If character_code >= Asc("a") AndAlso character_code <= Asc("z") Then Return -1
    If character_code = Asc("_") Then Return -1
    Return 0

End Function


Private Function textbox_IsIdentifierPart(ByVal character_code As Integer) As Integer

    If textbox_IsIdentifierStart(character_code) <> 0 Then Return -1
    If character_code >= Asc("0") AndAlso character_code <= Asc("9") Then Return -1
    Return 0

End Function


Private Function textbox_IsFreeBasicType(ByVal token_text As String) As Integer

    Select Case UCase(token_text)
        Case "ANY", "BOOLEAN", "BYTE", "DOUBLE", "FBSTRING", "INTEGER", _
             "LONG", "LONGINT", "OBJECT", "SINGLE", "SHORT", "STRING", _
             "UBYTE", "UINTEGER", "ULONG", "ULONGINT", "USHORT", "WSTRING", _
             "ZSTRING"
            Return -1
    End Select

    Return 0

End Function


Private Function textbox_IsFreeBasicKeyword(ByVal token_text As String) As Integer

    Select Case UCase(token_text)
        Case "ABSTRACT", "ALIAS", "AND", "ANDALSO", "AS", "ASM", _
             "BASE", "BYDESC", "BYREF", "BYVAL", "CASE", "CLASS", _
             "COMMON", "CONSTRUCTOR", "CONTINUE", "DATA", "DECLARE", _
             "DESTRUCTOR", "DIM", "DO", "ELSE", "ELSEIF", "END", _
             "ENUM", "ERROR", "EXIT", "EXTERN", "FOR", "FUNCTION", _
             "GOSUB", "GOTO", "IF", "IMPLEMENTS", "IMPORT", "INHERITS", _
             "LET", "LIB", "LOOP", "MOD", "NAMESPACE", "NEXT", "NOT", _
             "OBJECT", "OF", "ON", "OPERATOR", "OPTION", "OR", "ORELSE", _
             "OVERRIDE", "PRIVATE", "PROPERTY", "PUBLIC", "REDIM", _
             "RESUME", "RETURN", "SCOPE", "SELECT", "SHARED", "STATIC", _
             "STEP", "SUB", "SWAP", "THEN", "TO", "TYPE", "UNION", _
             "UNTIL", "USING", "VIRTUAL", "WEND", "WHILE", "WITH", _
             "XOR"
            Return -1
    End Select

    Return 0

End Function


Private Function textbox_IsFreeBasicCommand(ByVal token_text As String) As Integer

    Select Case UCase(token_text)
        Case "ABS", "ACOS", "ASC", "ASIN", "ATAN", "ATN", "BEEP", _
             "CALLOCATE", "CBYTE", "CBOOL", "CDBL", "CINT", "CLNG", _
             "COSH", "CSNG", "CSHORT", "CSRLIN", "CUBYTE", _
             "CUINT", "CULONG", "CULONGINT", "CUSHORT", "CVD", "CVI", _
             "CVL", "CVS", "CHDIR", "CHDRIVE", "CHR", "CIRCLE", _
             "CLEAR", "CLOSE", "CLS", "COLOR", "COMMAND", "COS", _
             "DATE", "ENVIRON", "EOF", "ERASE", "ERR", "ERROR", "EXP", _
             "FILES", "FIX", "FRE", "GET", "HEX", "INKEY", "INP", _
             "INPUT", "INSTR", "INT", "KILL", "LBOUND", "LEFT", "LEN", _
             "LINE", "LOC", "LOCATE", "LOG", "LPRINT", "LTRIM", "MKDIR", _
             "MID", "NAME", "OCT", "OPEN", "PAINT", "PEEK", "PLAY", _
             "POKE", "POS", "PRINT", "PSET", "PUT", "RANDOMIZE", "RMDIR", _
             "RIGHT", "RINSTR", "RND", "RTRIM", "SCREEN", "SETMEM", _
             "SGN", "SHELL", "SIN", "SLEEP", "SOUND", "SPACE", "SQR", _
             "STR", "TAN", "TIME", "TIMER", "UBOUND", "VAL", "VARPTR", _
             "VIEW", "VPOS", "WIDTH", "WINDOW", "WRITE"
            Return -1
    End Select

    Return 0

End Function


Private Function textbox_IsFreeBasicConstant(ByVal token_text As String) As Integer

    Select Case UCase(token_text)
        Case "FALSE", "TRUE", "NULL", "NOTHING", "PI"
            Return -1
    End Select

    Return 0

End Function


Private Function textbox_FreeBasicPreviousIdentifier( _
    ByRef line_text As Const String, ByVal position As Integer _
) As String

    Dim As Integer scan_position = position - 1
    Dim As Integer end_position

    While scan_position >= 0 AndAlso _
          (line_text[scan_position] = 32 OrElse _
           line_text[scan_position] = 9)
        scan_position -= 1
    Wend
    If scan_position < 0 OrElse _
       textbox_IsIdentifierPart(line_text[scan_position]) = 0 Then Return ""

    end_position = scan_position + 1
    While scan_position >= 0 AndAlso _
          textbox_IsIdentifierPart(line_text[scan_position]) <> 0
        scan_position -= 1
    Wend

    Return Mid(line_text, scan_position + 2, end_position - scan_position - 1)

End Function


Private Function textbox_FreeBasicNextSignificant( _
    ByRef line_text As Const String, ByVal position As Integer _
) As Integer

    While position < Len(line_text) AndAlso _
          (line_text[position] = 32 OrElse line_text[position] = 9)
        position += 1
    Wend
    If position >= Len(line_text) Then Return 0
    Return line_text[position]

End Function


Private Function textbox_IsFreeBasicMacroDefinition( _
    ByRef line_text As Const String, ByVal position As Integer _
) As Integer

    Dim As Integer scan_position
    Dim As Integer directive_start
    Dim As String directive_text

    scan_position = 0
    While scan_position < Len(line_text) AndAlso _
          (line_text[scan_position] = 32 OrElse _
           line_text[scan_position] = 9)
        scan_position += 1
    Wend
    If scan_position >= Len(line_text) OrElse _
       line_text[scan_position] <> Asc("#") Then Return 0

    directive_start = scan_position + 1
    scan_position = directive_start
    While scan_position < Len(line_text) AndAlso _
          textbox_IsIdentifierPart(line_text[scan_position]) <> 0
        scan_position += 1
    Wend
    directive_text = Mid( _
        line_text, directive_start + 1, scan_position - directive_start _
    )
    If UCase(directive_text) <> "DEFINE" Then Return 0

    While scan_position < Len(line_text) AndAlso _
          (line_text[scan_position] = 32 OrElse _
           line_text[scan_position] = 9)
        scan_position += 1
    Wend
    Return IIf(scan_position = position, -1, 0)

End Function


Private Function textbox_IsFreeBasicMacroDefined( _
    ByRef source_text As Const String, ByVal token_text As String _
) As Integer

    Dim As Integer line_start
    Dim As Integer line_end
    Dim As Integer scan_position
    Dim As Integer directive_start
    Dim As Integer macro_start
    Dim As String directive_text
    Dim As String macro_text

    While line_start < Len(source_text)
        line_end = line_start
        While line_end < Len(source_text) AndAlso _
              source_text[line_end] <> 10 AndAlso _
              source_text[line_end] <> 13
            line_end += 1
        Wend

        scan_position = line_start
        While scan_position < line_end AndAlso _
              (source_text[scan_position] = 32 OrElse _
               source_text[scan_position] = 9)
            scan_position += 1
        Wend
        If scan_position < line_end AndAlso _
           source_text[scan_position] = Asc("#") Then
            directive_start = scan_position + 1
            scan_position = directive_start
            While scan_position < line_end AndAlso _
                  textbox_IsIdentifierPart(source_text[scan_position]) <> 0
                scan_position += 1
            Wend
            directive_text = Mid( _
                source_text, directive_start + 1, scan_position - directive_start _
            )
            If UCase(directive_text) = "DEFINE" Then
                While scan_position < line_end AndAlso _
                      (source_text[scan_position] = 32 OrElse _
                       source_text[scan_position] = 9)
                    scan_position += 1
                Wend
                macro_start = scan_position
                While scan_position < line_end AndAlso _
                      textbox_IsIdentifierPart(source_text[scan_position]) <> 0
                    scan_position += 1
                Wend
                macro_text = Mid( _
                    source_text, macro_start + 1, scan_position - macro_start _
                )
                If UCase(macro_text) = UCase(token_text) Then Return -1
            End If
        End If

        If line_end >= Len(source_text) Then Exit While
        line_start = line_end + 1
        If source_text[line_end] = 13 AndAlso _
           line_start < Len(source_text) AndAlso _
           source_text[line_start] = 10 Then line_start += 1
    Wend

    Return 0

End Function


Private Function textbox_IsFreeBasicProcedureDefined( _
    ByRef source_text As Const String, ByVal token_text As String _
) As Integer

    Dim As Integer line_start
    Dim As Integer line_end
    Dim As Integer scan_position
    Dim As Integer token_end
    Dim As Integer declaration_name_start
    Dim As Integer block_close
    Dim As Integer character_code
    Dim As String declaration_text
    Dim As String declaration_name

    While line_start < Len(source_text)
        line_end = line_start
        While line_end < Len(source_text) AndAlso _
              source_text[line_end] <> 10 AndAlso _
              source_text[line_end] <> 13
            line_end += 1
        Wend

        scan_position = line_start
        If textbox_FreeBasicBlockCommentBefore(source_text, line_start) <> 0 Then
            block_close = InStr(line_start + 1, source_text, "'/") - 1
            If block_close < 0 OrElse block_close >= line_end Then
                scan_position = line_end
            Else
                scan_position = block_close + 2
            End If
        End If

        While scan_position < line_end
            character_code = source_text[scan_position]
            If character_code = Asc("'") Then Exit While
            If character_code = TEXTBOX_DOUBLE_QUOTE Then
                scan_position += 1
                While scan_position < line_end
                    If source_text[scan_position] = TEXTBOX_DOUBLE_QUOTE Then
                        If scan_position + 1 < line_end AndAlso _
                           source_text[scan_position + 1] = TEXTBOX_DOUBLE_QUOTE Then
                            scan_position += 2
                        Else
                            scan_position += 1
                            Exit While
                        End If
                    Else
                        scan_position += 1
                    End If
                Wend
                Continue While
            End If
            If textbox_IsIdentifierStart(character_code) = 0 Then
                scan_position += 1
                Continue While
            End If

            token_end = scan_position + 1
            While token_end < line_end AndAlso _
                  textbox_IsIdentifierPart(source_text[token_end]) <> 0
                token_end += 1
            Wend
            declaration_text = Mid( _
                source_text, scan_position + 1, token_end - scan_position _
            )
            Select Case UCase(declaration_text)
                Case "SUB", "FUNCTION", "PROPERTY", "CONSTRUCTOR", _
                     "DESTRUCTOR", "OPERATOR"
                    declaration_name_start = token_end
                    While declaration_name_start < line_end AndAlso _
                          (source_text[declaration_name_start] = 32 OrElse _
                           source_text[declaration_name_start] = 9)
                        declaration_name_start += 1
                    Wend
                    If declaration_name_start < line_end AndAlso _
                       textbox_IsIdentifierStart( _
                           source_text[declaration_name_start] _
                       ) <> 0 Then
                        token_end = declaration_name_start + 1
                        While token_end < line_end AndAlso _
                              textbox_IsIdentifierPart(source_text[token_end]) <> 0
                            token_end += 1
                        Wend
                        declaration_name = Mid( _
                            source_text, declaration_name_start + 1, _
                            token_end - declaration_name_start _
                        )
                        If UCase(declaration_name) = UCase(token_text) Then _
                            Return -1
                    End If
            End Select
            scan_position = token_end
        Wend

        If line_end >= Len(source_text) Then Exit While
        line_start = line_end + 1
        If source_text[line_end] = 13 AndAlso _
           line_start < Len(source_text) AndAlso _
           source_text[line_start] = 10 Then line_start += 1
    Wend

    Return 0

End Function


Private Function textbox_IsFreeBasicDefinedType( _
    ByRef source_text As Const String, ByVal token_text As String _
) As Integer

    Dim As Integer line_start
    Dim As Integer line_end
    Dim As Integer scan_position
    Dim As Integer token_end
    Dim As Integer block_close
    Dim As Integer character_code
    Dim As String declaration_text
    Dim As String previous_identifier

    /'
        This is deliberately a small declaration scan rather than a full
        parser. It catches the declaration forms that matter to coloring and
        also lets a type be used before its declaration in the same editor
        buffer, which is common while a file is being written.
    '/
    While line_start < Len(source_text)
        line_end = line_start
        While line_end < Len(source_text) AndAlso _
              source_text[line_end] <> 10 AndAlso _
              source_text[line_end] <> 13
            line_end += 1
        Wend

        previous_identifier = ""
        scan_position = line_start
        If textbox_FreeBasicBlockCommentBefore(source_text, line_start) <> 0 Then
            block_close = InStr(line_start + 1, source_text, "'/") - 1
            If block_close < 0 OrElse block_close >= line_end Then
                scan_position = line_end
            Else
                scan_position = block_close + 2
            End If
        End If

        While scan_position < line_end
            character_code = source_text[scan_position]
            If character_code = Asc("'") Then Exit While
            If character_code = TEXTBOX_DOUBLE_QUOTE Then
                scan_position += 1
                While scan_position < line_end
                    If source_text[scan_position] = TEXTBOX_DOUBLE_QUOTE Then
                        If scan_position + 1 < line_end AndAlso _
                           source_text[scan_position + 1] = TEXTBOX_DOUBLE_QUOTE Then
                            scan_position += 2
                        Else
                            scan_position += 1
                            Exit While
                        End If
                    Else
                        scan_position += 1
                    End If
                Wend
                Continue While
            End If
            If textbox_IsIdentifierStart(character_code) = 0 Then
                scan_position += 1
                Continue While
            End If

            token_end = scan_position + 1
            While token_end < line_end AndAlso _
                  textbox_IsIdentifierPart(source_text[token_end]) <> 0
                token_end += 1
            Wend
            declaration_text = Mid( _
                source_text, scan_position + 1, token_end - scan_position _
            )
            Select Case UCase(previous_identifier)
                Case "TYPE", "CLASS", "ENUM", "UNION"
                    If UCase(declaration_text) = UCase(token_text) Then _
                        Return -1
            End Select
            previous_identifier = declaration_text
            scan_position = token_end
        Wend

        If line_end >= Len(source_text) Then Exit While
        line_start = line_end + 1
        If source_text[line_end] = 13 AndAlso _
           line_start < Len(source_text) AndAlso _
           source_text[line_start] = 10 Then line_start += 1
    Wend

    Return 0

End Function


Private Function textbox_IsFreeBasicObjectVariableDefined( _
    ByRef source_text As Const String, ByVal token_text As String _
) As Integer

    Dim As Integer line_start
    Dim As Integer line_end
    Dim As Integer scan_position
    Dim As Integer token_end
    Dim As Integer block_close
    Dim As Integer character_code
    Dim As Integer object_type_pending
    Dim As String declaration_text
    Dim As String previous_identifier
    Dim As String previous_previous_identifier

    /'
        A user-defined object is identified from declarations such as
        "DIM master AS Calculator" and "DIM AS Calculator master". The
        declaration is enough to distinguish an object instance from an
        ordinary scalar variable without making the widget depend on the
        compiler's symbol table.
    '/
    While line_start < Len(source_text)
        line_end = line_start
        While line_end < Len(source_text) AndAlso _
              source_text[line_end] <> 10 AndAlso _
              source_text[line_end] <> 13
            line_end += 1
        Wend

        previous_previous_identifier = ""
        previous_identifier = ""
        object_type_pending = 0
        scan_position = line_start
        If textbox_FreeBasicBlockCommentBefore(source_text, line_start) <> 0 Then
            block_close = InStr(line_start + 1, source_text, "'/") - 1
            If block_close < 0 OrElse block_close >= line_end Then
                scan_position = line_end
            Else
                scan_position = block_close + 2
            End If
        End If

        While scan_position < line_end
            character_code = source_text[scan_position]
            If character_code = Asc("'") Then Exit While
            If character_code = TEXTBOX_DOUBLE_QUOTE Then
                scan_position += 1
                While scan_position < line_end
                    If source_text[scan_position] = TEXTBOX_DOUBLE_QUOTE Then
                        If scan_position + 1 < line_end AndAlso _
                           source_text[scan_position + 1] = TEXTBOX_DOUBLE_QUOTE Then
                            scan_position += 2
                        Else
                            scan_position += 1
                            Exit While
                        End If
                    Else
                        scan_position += 1
                    End If
                Wend
                Continue While
            End If
            If textbox_IsIdentifierStart(character_code) = 0 Then
                scan_position += 1
                Continue While
            End If

            token_end = scan_position + 1
            While token_end < line_end AndAlso _
                  textbox_IsIdentifierPart(source_text[token_end]) <> 0
                token_end += 1
            Wend
            declaration_text = Mid( _
                source_text, scan_position + 1, token_end - scan_position _
            )

            If object_type_pending <> 0 Then
                If UCase(declaration_text) = UCase(token_text) Then Return -1
                If UCase(declaration_text) <> "PTR" Then _
                    object_type_pending = 0
            End If

            If UCase(previous_identifier) = "AS" AndAlso _
               textbox_IsFreeBasicDefinedType( _
                   source_text, declaration_text _
               ) <> 0 Then
                If UCase(previous_previous_identifier) = UCase(token_text) Then _
                    Return -1
                object_type_pending = -1
            End If

            previous_previous_identifier = previous_identifier
            previous_identifier = declaration_text
            scan_position = token_end
        Wend

        If line_end >= Len(source_text) Then Exit While
        line_start = line_end + 1
        If source_text[line_end] = 13 AndAlso _
           line_start < Len(source_text) AndAlso _
           source_text[line_start] = 10 Then line_start += 1
    Wend

    Return 0

End Function


Private Function textbox_ClassifyFreeBasicIdentifier( _
    ByRef source_text As Const String, ByRef line_text As Const String, _
    ByVal position As Integer, ByVal token_end As Integer, _
    ByRef token_text As Const String _
) As Integer

    Dim As Integer first_nonspace
    Dim As Integer is_line_start
    Dim As Integer next_character
    Dim As String previous_identifier

    If textbox_IsFreeBasicMacroDefinition(line_text, position) <> 0 OrElse _
       textbox_IsFreeBasicMacroDefined(source_text, token_text) <> 0 Then _
        Return TEXTBOX_SYNTAX_COLOR_MACRO

    first_nonspace = 0
    While first_nonspace < position AndAlso _
          (line_text[first_nonspace] = 32 OrElse _
           line_text[first_nonspace] = 9)
        first_nonspace += 1
    Wend
    is_line_start = IIf(first_nonspace = position, -1, 0)
    next_character = textbox_FreeBasicNextSignificant(line_text, token_end)
    If is_line_start <> 0 AndAlso next_character = Asc(":") Then _
        Return TEXTBOX_SYNTAX_COLOR_LABEL

    If position > 0 AndAlso line_text[position - 1] = Asc(".") Then _
        Return TEXTBOX_SYNTAX_COLOR_MEMBER
    If position > 1 AndAlso line_text[position - 1] = Asc(">") AndAlso _
       line_text[position - 2] = Asc("-") Then _
        Return TEXTBOX_SYNTAX_COLOR_MEMBER

    If textbox_IsFreeBasicCommand(token_text) <> 0 Then _
        Return TEXTBOX_SYNTAX_COLOR_COMMAND
    If textbox_IsFreeBasicConstant(token_text) <> 0 Then _
        Return TEXTBOX_SYNTAX_COLOR_CONSTANT
    If textbox_IsFreeBasicDefinedType(source_text, token_text) <> 0 Then _
        Return TEXTBOX_SYNTAX_COLOR_TYPE
    If textbox_IsFreeBasicObjectVariableDefined(source_text, token_text) <> 0 Then _
        Return TEXTBOX_SYNTAX_COLOR_OBJECT
    If textbox_IsFreeBasicProcedureDefined(source_text, token_text) <> 0 Then _
        Return TEXTBOX_SYNTAX_COLOR_PROCEDURE

    previous_identifier = textbox_FreeBasicPreviousIdentifier( _
        line_text, position _
    )
    Select Case UCase(previous_identifier)
        Case "SUB", "FUNCTION", "PROPERTY", "CONSTRUCTOR", "DESTRUCTOR", _
             "OPERATOR"
            Return TEXTBOX_SYNTAX_COLOR_PROCEDURE
        Case "TYPE", "ENUM", "UNION", "CLASS"
            Return TEXTBOX_SYNTAX_COLOR_TYPE
    End Select

    If next_character = Asc("(") Then _
        Return TEXTBOX_SYNTAX_COLOR_PROCEDURE

    Return TEXTBOX_SYNTAX_COLOR_VARIABLE

End Function


Private Function textbox_GetSyntaxColorValue( _
    ByVal textData As TextBoxData Ptr, ByVal color_kind As Integer _
) As ULong

    If textData = 0 Then Return current_theme.text_main
    If (textData->syntax_color_overrides And (1 Shl color_kind)) = 0 Then
        Select Case color_kind
            Case TEXTBOX_SYNTAX_COLOR_KEYWORD
                Return current_theme.syntax_keyword_color
            Case TEXTBOX_SYNTAX_COLOR_COMMENT
                Return current_theme.syntax_comment_color
            Case TEXTBOX_SYNTAX_COLOR_STRING
                Return current_theme.syntax_string_color
            Case TEXTBOX_SYNTAX_COLOR_NUMBER
                Return current_theme.syntax_number_color
            Case TEXTBOX_SYNTAX_COLOR_PREPROCESSOR
                Return current_theme.syntax_preprocessor_color
            Case TEXTBOX_SYNTAX_COLOR_TYPE
                Return current_theme.syntax_type_color
            Case TEXTBOX_SYNTAX_COLOR_COMMAND
                Return current_theme.syntax_command_color
            Case TEXTBOX_SYNTAX_COLOR_PROCEDURE
                Return current_theme.syntax_procedure_color
            Case TEXTBOX_SYNTAX_COLOR_MACRO
                Return current_theme.syntax_macro_color
            Case TEXTBOX_SYNTAX_COLOR_VARIABLE
                Return current_theme.syntax_variable_color
            Case TEXTBOX_SYNTAX_COLOR_CONSTANT
                Return current_theme.syntax_constant_color
            Case TEXTBOX_SYNTAX_COLOR_MEMBER
                Return current_theme.syntax_member_color
            Case TEXTBOX_SYNTAX_COLOR_LABEL
                Return current_theme.syntax_label_color
            Case TEXTBOX_SYNTAX_COLOR_OBJECT
                Return current_theme.syntax_object_color
        End Select
    End If

    Select Case color_kind
        Case TEXTBOX_SYNTAX_COLOR_KEYWORD
            Return textData->syntax_keyword_color
        Case TEXTBOX_SYNTAX_COLOR_COMMENT
            Return textData->syntax_comment_color
        Case TEXTBOX_SYNTAX_COLOR_STRING
            Return textData->syntax_string_color
        Case TEXTBOX_SYNTAX_COLOR_NUMBER
            Return textData->syntax_number_color
        Case TEXTBOX_SYNTAX_COLOR_PREPROCESSOR
            Return textData->syntax_preprocessor_color
        Case TEXTBOX_SYNTAX_COLOR_TYPE
            Return textData->syntax_type_color
        Case TEXTBOX_SYNTAX_COLOR_COMMAND
            Return textData->syntax_command_color
        Case TEXTBOX_SYNTAX_COLOR_PROCEDURE
            Return textData->syntax_procedure_color
        Case TEXTBOX_SYNTAX_COLOR_MACRO
            Return textData->syntax_macro_color
        Case TEXTBOX_SYNTAX_COLOR_VARIABLE
            Return textData->syntax_variable_color
        Case TEXTBOX_SYNTAX_COLOR_CONSTANT
            Return textData->syntax_constant_color
        Case TEXTBOX_SYNTAX_COLOR_MEMBER
            Return textData->syntax_member_color
        Case TEXTBOX_SYNTAX_COLOR_LABEL
            Return textData->syntax_label_color
        Case TEXTBOX_SYNTAX_COLOR_OBJECT
            Return textData->syntax_object_color
    End Select

    Return current_theme.text_main

End Function


Private Function textbox_FreeBasicBlockCommentBefore( _
    ByRef source_text As Const String, ByVal limit_position As Integer _
) As Integer

    Dim As Integer in_block_comment
    Dim As Integer in_string
    Dim As Integer position
    Dim As Integer source_length = Len(source_text)
    Dim As Integer character_code

    If limit_position < 0 Then limit_position = 0
    If limit_position > source_length Then limit_position = source_length

    While position < limit_position
        character_code = source_text[position]

        If in_block_comment <> 0 Then
            If character_code = Asc("'") AndAlso _
               position + 1 < limit_position AndAlso _
               source_text[position + 1] = Asc("/") Then
                in_block_comment = 0
                position += 2
            Else
                position += 1
            End If
        Elseif in_string <> 0 Then
            If character_code = TEXTBOX_DOUBLE_QUOTE Then
                If position + 1 < limit_position AndAlso _
                   source_text[position + 1] = TEXTBOX_DOUBLE_QUOTE Then
                    position += 2
                Else
                    in_string = 0
                    position += 1
                End If
            Else
                position += 1
            End If
        Elseif character_code = TEXTBOX_DOUBLE_QUOTE Then
            in_string = -1
            position += 1
        Elseif character_code = Asc("'") Then
            While position < limit_position AndAlso _
                  source_text[position] <> 10 AndAlso _
                  source_text[position] <> 13
                position += 1
            Wend
        Elseif character_code = Asc("/") AndAlso _
               position + 1 < limit_position AndAlso _
               source_text[position + 1] = Asc("'") Then
            in_block_comment = -1
            position += 2
        Else
            position += 1
        End If
    Wend

    Return in_block_comment

End Function


Private Sub textbox_DrawTextPart( _
    ByVal textData As TextBoxData Ptr, _
    ByRef draw_x As Integer, ByVal draw_y As Integer, _
    ByVal part_text As String, ByVal text_color As ULong _
)

    If Len(part_text) = 0 Then Exit Sub
    textbox_PrintStyled textData, draw_x, draw_y, text_color, _
        part_text, textData->text_style
    draw_x += textbox_TextWidth(textData, part_text)

End Sub


Private Sub textbox_RenderTextSpan( _
    ByVal textData As TextBoxData Ptr, _
    ByRef draw_x As Integer, ByVal draw_y As Integer, _
    ByRef line_text As Const String, ByVal line_start As Integer, _
    ByVal span_start As Integer, ByVal span_end As Integer, _
    ByVal text_color As ULong, ByVal selected_start As Integer, _
    ByVal selected_end As Integer _
)

    Dim As Integer local_start
    Dim As Integer local_end
    Dim As Integer selection_start_in_span
    Dim As Integer selection_end_in_span
    Dim As String part_text
    Dim As Integer part_length
    Dim As Integer selected_width

    If span_end <= span_start Then Exit Sub

    local_start = span_start - line_start
    local_end = span_end - line_start
    If local_start < 0 Then local_start = 0
    If local_end > Len(line_text) Then local_end = Len(line_text)
    If local_end <= local_start Then Exit Sub

    selection_start_in_span = selected_start
    If selection_start_in_span < span_start Then _
        selection_start_in_span = span_start
    selection_end_in_span = selected_end
    If selection_end_in_span > span_end Then _
        selection_end_in_span = span_end

    If selection_end_in_span <= selection_start_in_span Then
        textbox_DrawTextPart textData, draw_x, draw_y, _
            Mid(line_text, local_start + 1, local_end - local_start), _
            text_color
        Exit Sub
    End If

    If selection_start_in_span > span_start Then
        part_length = selection_start_in_span - span_start
        textbox_DrawTextPart textData, draw_x, draw_y, _
            Mid(line_text, local_start + 1, part_length), text_color
    End If

    part_length = selection_end_in_span - selection_start_in_span
    part_text = Mid( _
        line_text, selection_start_in_span - line_start + 1, part_length _
    )
    selected_width = textbox_TextWidth(textData, part_text)
    If selected_width > 0 Then
        backend_Rect draw_x, draw_y, selected_width, _
            textbox_LineHeight(textData), current_theme.bg_select, 1
    End If
    textbox_DrawTextPart textData, draw_x, draw_y, part_text, current_theme.text_select

    If selection_end_in_span < span_end Then
        part_length = span_end - selection_end_in_span
        textbox_DrawTextPart textData, draw_x, draw_y, _
            Mid(line_text, selection_end_in_span - line_start + 1, part_length), _
            text_color
    End If

End Sub


Private Sub textbox_RenderSyntaxLine( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr, _
    ByVal draw_x As Integer, ByVal draw_y As Integer, _
    ByVal line_start As Integer, ByRef line_text As Const String, _
    ByVal text_color As ULong, ByVal selected_start As Integer, _
    ByVal selected_end As Integer _
)

    Dim As Integer block_comment
    Dim As Integer close_position
    Dim As Integer line_length = Len(line_text)
    Dim As Integer position
    Dim As Integer token_end
    Dim As Integer character_code
    Dim As Integer at_line_start
    Dim As String token_text
    Dim As Integer token_kind
    Dim As ULong token_color
    Dim As Integer current_x = draw_x

    If w = 0 OrElse textData = 0 Then Exit Sub

    block_comment = textbox_FreeBasicBlockCommentBefore( _
        textData->text, line_start _
    )

    While position < line_length
        If block_comment <> 0 Then
            close_position = InStr(position + 1, line_text, "'/")
            If close_position = 0 Then
                textbox_RenderTextSpan textData, current_x, draw_y, line_text, line_start, _
                    line_start + position, line_start + line_length, _
                    textbox_GetSyntaxColorValue( _
                        textData, TEXTBOX_SYNTAX_COLOR_COMMENT _
                    ), selected_start, selected_end
                Exit Sub
            End If
            close_position -= 1
            textbox_RenderTextSpan textData, current_x, draw_y, line_text, line_start, _
                line_start + position, line_start + close_position + 2, _
                textbox_GetSyntaxColorValue( _
                    textData, TEXTBOX_SYNTAX_COLOR_COMMENT _
                ), selected_start, selected_end
            position = close_position + 2
            block_comment = 0
            Continue While
        End If

        character_code = line_text[position]

        If character_code = Asc("'") Then
            textbox_RenderTextSpan textData, current_x, draw_y, line_text, line_start, _
                line_start + position, line_start + line_length, _
                textbox_GetSyntaxColorValue( _
                    textData, TEXTBOX_SYNTAX_COLOR_COMMENT _
                ), selected_start, selected_end
            Exit Sub
        End If

        If character_code = Asc("/") AndAlso position + 1 < line_length AndAlso _
           line_text[position + 1] = Asc("'") Then
            block_comment = -1
            textbox_RenderTextSpan textData, current_x, draw_y, line_text, line_start, _
                line_start + position, line_start + position + 2, _
                textbox_GetSyntaxColorValue( _
                    textData, TEXTBOX_SYNTAX_COLOR_COMMENT _
                ), selected_start, selected_end
            position += 2
            Continue While
        End If

        If character_code = TEXTBOX_DOUBLE_QUOTE Then
            token_end = position + 1
            While token_end < line_length
                If line_text[token_end] = TEXTBOX_DOUBLE_QUOTE Then
                    If token_end + 1 < line_length AndAlso _
                       line_text[token_end + 1] = TEXTBOX_DOUBLE_QUOTE Then
                        token_end += 2
                    Else
                        token_end += 1
                        Exit While
                    End If
                Else
                    token_end += 1
                End If
            Wend
            textbox_RenderTextSpan textData, current_x, draw_y, line_text, line_start, _
                line_start + position, line_start + token_end, _
                textbox_GetSyntaxColorValue( _
                    textData, TEXTBOX_SYNTAX_COLOR_STRING _
                ), selected_start, selected_end
            position = token_end
            Continue While
        End If

        If character_code = Asc("#") Then
            at_line_start = 1
            For scan_position As Integer = 0 To position - 1
                If line_text[scan_position] <> 32 AndAlso _
                   line_text[scan_position] <> 9 Then
                    at_line_start = 0
                    Exit For
                End If
            Next scan_position
        End If

        If character_code = Asc("#") AndAlso at_line_start <> 0 Then
            token_end = position + 1
            While token_end < line_length AndAlso _
                  textbox_IsIdentifierPart(line_text[token_end]) <> 0
                token_end += 1
            Wend
            textbox_RenderTextSpan textData, current_x, draw_y, line_text, line_start, _
                line_start + position, line_start + token_end, _
                textbox_GetSyntaxColorValue( _
                    textData, TEXTBOX_SYNTAX_COLOR_PREPROCESSOR _
                ), selected_start, selected_end
            position = token_end
            Continue While
        End If

        If textbox_IsIdentifierStart(character_code) <> 0 Then
            token_end = position + 1
            While token_end < line_length AndAlso _
                  textbox_IsIdentifierPart(line_text[token_end]) <> 0
                token_end += 1
            Wend
            token_text = Mid(line_text, position + 1, token_end - position)
            If textbox_IsFreeBasicType(token_text) <> 0 Then
                token_kind = TEXTBOX_SYNTAX_COLOR_TYPE
            Elseif textbox_IsFreeBasicKeyword(token_text) <> 0 Then
                token_kind = TEXTBOX_SYNTAX_COLOR_KEYWORD
            Else
                token_kind = textbox_ClassifyFreeBasicIdentifier( _
                    textData->text, line_text, position, token_end, token_text _
                )
            End If
            token_color = textbox_GetSyntaxColorValue(textData, token_kind)
            textbox_RenderTextSpan textData, current_x, draw_y, line_text, line_start, _
                line_start + position, line_start + token_end, token_color, _
                selected_start, selected_end
            position = token_end
            Continue While
        End If

        If (character_code >= Asc("0") AndAlso character_code <= Asc("9")) OrElse _
           (character_code = Asc("&") AndAlso position + 1 < line_length AndAlso _
            (LCase(Mid(line_text, position + 2, 1)) = "h" OrElse _
             LCase(Mid(line_text, position + 2, 1)) = "b" OrElse _
             LCase(Mid(line_text, position + 2, 1)) = "o")) Then
            token_end = position + 1
            While token_end < line_length
                character_code = line_text[token_end]
                If textbox_IsIdentifierPart(character_code) <> 0 OrElse _
                   character_code = Asc(".") OrElse character_code = Asc("&") Then
                    token_end += 1
                Else
                    Exit While
                End If
            Wend
            textbox_RenderTextSpan textData, current_x, draw_y, line_text, line_start, _
                line_start + position, line_start + token_end, _
                textbox_GetSyntaxColorValue( _
                    textData, TEXTBOX_SYNTAX_COLOR_NUMBER _
                ), selected_start, selected_end
            position = token_end
            Continue While
        End If

        token_end = position + 1
        While token_end < line_length
            character_code = line_text[token_end]
            If character_code = Asc("'") OrElse _
               character_code = TEXTBOX_DOUBLE_QUOTE OrElse _
               (character_code = Asc("/") AndAlso _
                token_end + 1 < line_length AndAlso _
                line_text[token_end + 1] = Asc("'")) OrElse _
               textbox_IsIdentifierStart(character_code) <> 0 OrElse _
               (character_code >= Asc("0") AndAlso _
                character_code <= Asc("9")) Then
                Exit While
            End If
            token_end += 1
        Wend
        textbox_RenderTextSpan textData, current_x, draw_y, line_text, line_start, _
            line_start + position, line_start + token_end, text_color, _
            selected_start, selected_end
        position = token_end
    Wend

End Sub


' Read-only position helpers borrow the source. Copying an entire document
' for each caret clamp or row lookup makes otherwise small edits expensive.
Private Function textbox_ClampPosition(ByRef textValue As Const String, ByVal position As Integer) As Integer

    If position < 0 Then Return 0
    If position > Len(textValue) Then Return Len(textValue)
    Return position

End Function


' Malformed UTF-8 advances one byte; valid sequences remain indivisible for
' caret movement, wrapping, pointer hits, and destructive edits.
Private Function textbox_UTF8LengthAt( _
    ByRef textValue As Const String, ByVal bytePosition As Integer _
) As Integer
    Dim As Integer textLength = Len(textValue)
    If bytePosition < 0 OrElse bytePosition >= textLength Then Return 0
    Dim As Integer firstByte = textValue[bytePosition]
    If firstByte < &H80 Then Return 1
    Dim As Integer sequenceLength
    If firstByte >= &HC2 AndAlso firstByte <= &HDF Then
        sequenceLength = 2
    ElseIf firstByte >= &HE0 AndAlso firstByte <= &HEF Then
        sequenceLength = 3
    ElseIf firstByte >= &HF0 AndAlso firstByte <= &HF4 Then
        sequenceLength = 4
    Else
        Return 1
    End If
    If bytePosition > textLength - sequenceLength Then Return 1
    Dim As Integer secondByte = textValue[bytePosition + 1]
    If secondByte < &H80 OrElse secondByte > &HBF Then Return 1
    For byteIndex As Integer = 2 To sequenceLength - 1
        If textValue[bytePosition + byteIndex] < &H80 OrElse _
           textValue[bytePosition + byteIndex] > &HBF Then Return 1
    Next byteIndex
    If (firstByte = &HE0 AndAlso secondByte < &HA0) OrElse _
       (firstByte = &HED AndAlso secondByte > &H9F) OrElse _
       (firstByte = &HF0 AndAlso secondByte < &H90) OrElse _
       (firstByte = &HF4 AndAlso secondByte > &H8F) Then Return 1
    Return sequenceLength
End Function


Private Function textbox_ClampCharacterPosition( _
    ByRef textValue As Const String, ByVal position As Integer _
) As Integer
    position = textbox_ClampPosition(textValue, position)
    If position <= 0 OrElse position >= Len(textValue) Then Return position
    If (textValue[position] And &HC0) <> &H80 Then Return position
    Dim As Integer candidatePosition = position
    While candidatePosition > 0 AndAlso _
          position - candidatePosition < 3 AndAlso _
          (textValue[candidatePosition] And &HC0) = &H80
        candidatePosition -= 1
    Wend
    If candidatePosition + textbox_UTF8LengthAt( _
           textValue, candidatePosition _
       ) > position Then Return candidatePosition
    Return position
End Function


Private Function textbox_NextCharacterPosition( _
    ByRef textValue As Const String, ByVal position As Integer _
) As Integer
    position = textbox_ClampCharacterPosition(textValue, position)
    If position >= Len(textValue) Then Return Len(textValue)
    Return position + textbox_UTF8LengthAt(textValue, position)
End Function


Private Function textbox_PreviousCharacterPosition( _
    ByRef textValue As Const String, ByVal position As Integer _
) As Integer
    position = textbox_ClampCharacterPosition(textValue, position)
    If position <= 0 Then Return 0
    Dim As Integer candidatePosition = position - 1
    While candidatePosition > 0 AndAlso _
          position - candidatePosition < 4 AndAlso _
          (textValue[candidatePosition] And &HC0) = &H80
        candidatePosition -= 1
    Wend
    If candidatePosition + textbox_UTF8LengthAt( _
           textValue, candidatePosition _
       ) = position Then Return candidatePosition
    Return position - 1
End Function


Private Function textbox_ClampVirtualSpace( _
    ByVal textData As TextBoxData Ptr, _
    ByVal position As Integer, ByVal virtualSpace As Integer _
) As Integer
    If textData = 0 OrElse textData->virtual_space_enabled = 0 OrElse _
       textData->wordwrap <> 0 Then Return 0
    position = textbox_ClampCharacterPosition(textData->text, position)
    If position <> textbox_LineEnd(textData->text, position) Then Return 0
    If virtualSpace < 0 Then Return 0
    If virtualSpace > TEXTBOX_MAX_VIRTUAL_SPACE Then _
        virtualSpace = TEXTBOX_MAX_VIRTUAL_SPACE
    Return virtualSpace
End Function


Private Function textbox_ComparePositions( _
    ByVal firstPosition As Integer, ByVal firstVirtualSpace As Integer, _
    ByVal secondPosition As Integer, ByVal secondVirtualSpace As Integer _
) As Integer
    If firstPosition < secondPosition Then Return -1
    If firstPosition > secondPosition Then Return 1
    If firstVirtualSpace < secondVirtualSpace Then Return -1
    If firstVirtualSpace > secondVirtualSpace Then Return 1
    Return 0
End Function


Private Function textbox_HasSelectionData( _
    ByVal textData As TextBoxData Ptr _
) As Integer
    If textData = 0 Then Return 0
    Return IIf(textbox_ComparePositions( _
        textData->sel_start, textData->sel_start_virtual_space, _
        textData->sel_end, textData->sel_end_virtual_space _
    ) <> 0, -1, 0)
End Function


Private Function textbox_NextVisualLine( _
    ByRef textValue As Const String, _
    ByRef scanPosition As Integer, _
    ByVal wordwrap As Integer, _
    ByVal contentWidth As Integer, _
    ByRef lineStart As Integer, _
    ByRef lineEnd As Integer, _
    ByVal textData As TextBoxData Ptr _
) As Integer
    Dim As Integer characterWidth
    Dim As Integer ch
    Dim As Integer lastSpace = -1
    Dim As Integer lineWidth
    Dim As Integer position
    Dim As Integer sequenceLength
    Dim As Integer textLength = Len(textValue)

    If scanPosition < 0 Then scanPosition = 0
    If scanPosition > textLength Then Return 0
    If contentWidth < 1 Then contentWidth = 1

    lineStart = scanPosition

    /'
        A scan positioned exactly at the end represents the final empty row of
        an empty string or a string ending in a newline. Advancing past the end
        guarantees that every successful call makes progress.
    '/
    If scanPosition = textLength Then
        lineEnd = textLength
        scanPosition = textLength + 1
        Return -1
    End If

    position = scanPosition
    While position < textLength
        ch = textValue[position]

        If ch = TEXTBOX_LINE_FEED OrElse _
           ch = TEXTBOX_CARRIAGE_RETURN Then
            lineEnd = position
            scanPosition = position + 1

            If ch = TEXTBOX_CARRIAGE_RETURN AndAlso _
               scanPosition < textLength AndAlso _
               textValue[scanPosition] = TEXTBOX_LINE_FEED Then
                scanPosition += 1
            End If

            Return -1
        End If

        ' Unwrapped rows end at byte-level CR/LF boundaries. Measuring each
        ' glyph here repeats font work for every scrollbar and caret scan.
        ' UTF-8 continuation bytes cannot contain either newline byte.
        If wordwrap = 0 Then
            position += 1
            Continue While
        End If

        sequenceLength = textbox_UTF8LengthAt(textValue, position)
        characterWidth = textbox_TextWidth( textData, _
            Mid(textValue, position + 1, sequenceLength) _
        )
        lineWidth += characterWidth

        If ch = Asc(" ") Then lastSpace = position

        If wordwrap <> 0 AndAlso lineWidth > contentWidth Then
            If lastSpace >= lineStart Then
                lineEnd = lastSpace
                scanPosition = lastSpace + 1
            ElseIf position > lineStart Then
                lineEnd = position
                scanPosition = position
            Else
                /'
                    A single glyph can be wider than a very narrow widget.
                    Keep it on one row instead of emitting an empty row and
                    repeating the same scan position forever.
                '/
                lineEnd = position + sequenceLength
                scanPosition = lineEnd
            End If

            Return -1
        End If

        position += sequenceLength
    Wend

    lineEnd = textLength
    scanPosition = textLength + 1
    Return -1
End Function


/'
    Fold visibility is evaluated in the shared visual-row walk. The caller
    retains source line state, so wrapped rows do not rescan the buffer to
    recover a line number and every layout pass sees the same visible rows.
'/
Private Function textbox_NextVisibleVisualLine( _
    ByRef textValue As Const String, ByRef scanPosition As Integer, _
    ByVal wordwrap As Integer, ByVal contentWidth As Integer, _
    ByRef lineStart As Integer, ByRef lineEnd As Integer, _
    ByVal textData As TextBoxData Ptr, _
    ByRef sourceLineNumber As Integer, ByRef sourceLineStart As Integer, _
    ByRef rowLineNumber As Integer, ByRef rowLineStart As Integer _
) As Integer
    While textbox_NextVisualLine( _
        textValue, scanPosition, wordwrap, contentWidth, _
        lineStart, lineEnd, textData _
    ) <> 0
        rowLineNumber = sourceLineNumber
        rowLineStart = sourceLineStart
        If lineEnd < Len(textValue) Then
            If textValue[lineEnd] = TEXTBOX_LINE_FEED OrElse _
               textValue[lineEnd] = TEXTBOX_CARRIAGE_RETURN Then
                sourceLineNumber += 1
                sourceLineStart = scanPosition
            End If
        End If
        If textData = 0 OrElse _
           textData->line_visibility_handler = 0 Then Return -1
        If textData->line_visibility_handler( _
            textData->owner, rowLineNumber, rowLineStart _
        ) <> 0 Then Return -1
    Wend
    Return 0
End Function


Private Function textbox_CountVisualLines( _
    ByRef textValue As Const String, _
    ByVal wordwrap As Integer, _
    ByVal contentWidth As Integer, _
    ByVal textData As TextBoxData Ptr, _
    ByVal buildRowIndex As Integer _
) As Integer
    Dim As Integer lineEnd
    Dim As Integer lineStart
    Dim As Integer scanPosition
    Dim As Integer visualLines
    Dim As Integer sourceLineNumber, sourceLineStart
    Dim As Integer rowLineNumber, rowLineStart
    Dim As Integer nextCheckpoint, checkpointStride
    If buildRowIndex <> 0 AndAlso textData <> 0 Then
        textData->metrics_row_count = 0
        If wordwrap <> 0 OrElse Len(textValue) < 4096 Then
            buildRowIndex = 0
        Else
            checkpointStride = Len(textValue) \ 31 + 1
        End If
    End If

    While textbox_NextVisibleVisualLine( _
        textValue, scanPosition, wordwrap, contentWidth, _
        lineStart, lineEnd, textData, _
        sourceLineNumber, sourceLineStart, rowLineNumber, rowLineStart _
    )
        If buildRowIndex <> 0 AndAlso lineStart >= nextCheckpoint AndAlso _
           textData->metrics_row_count < 32 Then
            Dim As Integer entryIndex = textData->metrics_row_count
            textData->metrics_row_index(entryIndex) = visualLines
            textData->metrics_row_position(entryIndex) = lineStart
            textData->metrics_row_source_number(entryIndex) = rowLineNumber
            textData->metrics_row_count += 1
            nextCheckpoint = lineStart + checkpointStride
        End If
        visualLines += 1
    Wend

    If visualLines < 1 Then visualLines = 1
    Return visualLines
End Function

/'
    Render row index

    Call only after textbox_UpdateScrollMetrics validated the exact source,
    dimensions, font generation and application visibility observation. No
    string or syntax state is cached here. A lexer provider must still restore
    syntax state independently; declining it retains ordinary replay from zero.
'/
Private Sub textbox_RestoreRenderRow( _
    ByVal textData As TextBoxData Ptr, ByVal targetRow As Integer, _
    ByRef rowIndex As Integer, ByRef scanPosition As Integer, _
    ByRef sourceLineNumber As Integer, ByRef sourceLineStart As Integer _
)
    #If Defined(OMAGUI_DISABLE_ROW_INDEX)
        Exit Sub
    #EndIf
    If textData = 0 OrElse textData->wordwrap <> 0 OrElse _
       textData->metrics_row_count < 1 OrElse textData->metrics_row_count > 32 Then Exit Sub
    For entryIndex As Integer = textData->metrics_row_count - 1 To 0 Step -1
        If textData->metrics_row_index(entryIndex) <= targetRow Then
            rowIndex = textData->metrics_row_index(entryIndex)
            scanPosition = textData->metrics_row_position(entryIndex)
            sourceLineNumber = textData->metrics_row_source_number(entryIndex)
            sourceLineStart = scanPosition
            Exit Sub
        End If
    Next entryIndex
End Sub


/'
    Input helpers may run before the next metrics refresh. Validate the exact
    text retained at the end of metrics_key before borrowing its row index.
    This also catches legacy direct writes which bypass the change serial.
    Callback layouts require the same callback identity and visibility key,
    or the existing explicit viewport_dirty contract for opt-in caching.
'/
Private Function textbox_CanRestoreRow( _
    ByVal textData As TextBoxData Ptr, ByRef textValue As Const String _
) As Integer
    #If Defined(OMAGUI_DISABLE_ROW_INDEX)
        Return 0
    #EndIf
    If textData = 0 OrElse textData->metrics_valid = 0 OrElse _
       textData->wordwrap <> 0 OrElse textData->metrics_row_count < 1 OrElse _
       textData->metrics_row_count > 32 Then Return 0
    Dim As Integer sourceLength = Len(textValue)
    Dim As Integer keyLength = Len(textData->metrics_key)
    If sourceLength <> textData->metrics_row_source_length OrElse _
       sourceLength < 4096 OrElse keyLength < sourceLength Then Return 0
    If textData->line_visibility_handler <> textData->metrics_row_visibility_handler OrElse _
       textData->metrics_state_handler <> textData->metrics_row_state_handler Then Return 0
    If textData->line_visibility_handler <> 0 Then
        If textData->metrics_state_handler <> 0 Then
            If textData->metrics_state_handler(textData->owner) <> _
               textData->metrics_row_visibility_key Then Return 0
        ElseIf textData->metrics_cache_callbacks = 0 OrElse textData->viewport_dirty <> 0 Then
            Return 0
        End If
    End If
    Dim As Integer comparison = oma_BytesEqual( _
        StrPtr(textData->metrics_key) + keyLength - sourceLength, _
        StrPtr(textValue), sourceLength _
    )
    Return IIf(comparison <> 0, -1, 0)
End Function

Private Function textbox_VisualLineForPosition( _
    ByRef textValue As Const String, _
    ByVal position As Integer, _
    ByVal wordwrap As Integer, _
    ByVal contentWidth As Integer, _
    ByVal textData As TextBoxData Ptr _
) As Integer
    Dim As Integer lineStart, lineEnd, boundsFound
    Return textbox_VisualLineAtPosition(textValue, position, wordwrap, _
        contentWidth, lineStart, lineEnd, boundsFound, textData)
End Function


Private Function textbox_VisualLineAtPosition( _
    ByRef textValue As Const String, _
    ByVal position As Integer, _
    ByVal wordwrap As Integer, _
    ByVal contentWidth As Integer, _
    ByRef lineStart As Integer, _
    ByRef lineEnd As Integer, _
    ByRef boundsFound As Integer, _
    ByVal textData As TextBoxData Ptr _
) As Integer
    Dim As Integer lineIndex
    Dim As Integer nextStart, nextEnd
    Dim As Integer scanPosition
    Dim As Integer sourceLineNumber, sourceLineStart
    Dim As Integer rowLineNumber, rowLineStart

    ' Return the row bounds from the same walk that locates the caret.
    ' Callers may reuse them only while the measured layout is unchanged.
    boundsFound = 0
    lineStart = 0
    lineEnd = 0
    position = textbox_ClampPosition(textValue, position)

    If wordwrap = 0 AndAlso textbox_CanRestoreRow(textData, textValue) <> 0 Then
        For entryIndex As Integer = textData->metrics_row_count - 1 To 0 Step -1
            If textData->metrics_row_position(entryIndex) <= position Then
                lineIndex = textData->metrics_row_index(entryIndex)
                scanPosition = textData->metrics_row_position(entryIndex)
                sourceLineNumber = textData->metrics_row_source_number(entryIndex)
                sourceLineStart = scanPosition
                Exit For
            End If
        Next entryIndex
    End If

    While textbox_NextVisibleVisualLine( _
        textValue, scanPosition, wordwrap, contentWidth, _
        nextStart, nextEnd, textData, _
        sourceLineNumber, sourceLineStart, rowLineNumber, rowLineStart _
    )
        lineStart = nextStart
        lineEnd = nextEnd
        boundsFound = -1
        If position <= lineEnd Then Return lineIndex
        lineIndex += 1
    Wend

    If lineIndex > 0 Then Return lineIndex - 1
    Return 0
End Function


Private Function textbox_VisualLineBounds( _
    ByRef textValue As Const String, _
    ByVal targetLine As Integer, _
    ByVal wordwrap As Integer, _
    ByVal contentWidth As Integer, _
    ByRef lineStart As Integer, _
    ByRef lineEnd As Integer, _
    ByVal textData As TextBoxData Ptr _
) As Integer
    Dim As Integer lineIndex
    Dim As Integer scanPosition
    Dim As Integer sourceLineNumber, sourceLineStart
    Dim As Integer rowLineNumber, rowLineStart

    If targetLine < 0 Then targetLine = 0

    If wordwrap = 0 AndAlso textbox_CanRestoreRow(textData, textValue) <> 0 Then
        textbox_RestoreRenderRow textData, targetLine, _
            lineIndex, scanPosition, sourceLineNumber, sourceLineStart
    End If

    While textbox_NextVisibleVisualLine( _
        textValue, scanPosition, wordwrap, contentWidth, _
        lineStart, lineEnd, textData, _
        sourceLineNumber, sourceLineStart, rowLineNumber, rowLineStart _
    )
        If lineIndex = targetLine Then Return -1
        lineIndex += 1
    Wend

    Return 0
End Function


Private Function textbox_VisibleLineCount( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr _
) As Integer
    Dim As Integer visibleLines
    Dim As Integer contentHeight

    If w = 0 Then Return 1

    contentHeight = w->h - _
        textbox_ScaledPadding(textData, TEXTBOX_TEXT_BOTTOM_PADDING)
    If textData <> 0 AndAlso _
       textData->horizontal_scrollbar_visible <> 0 Then
        contentHeight -= TEXTBOX_SCROLLBAR_WIDTH + TEXTBOX_SCROLLBAR_INSET
    End If
    visibleLines = contentHeight \ textbox_LineHeight(textData)
    If visibleLines < 1 Then visibleLines = 1
    Return visibleLines
End Function


Private Function textbox_MaximumLineWidth( _
    ByRef textValue As Const String, _
    ByVal textData As TextBoxData Ptr _
) As Integer
    Dim As Integer lineEnd
    Dim As Integer lineStart
    Dim As Integer lineWidth
    Dim As Integer maximumWidth
    Dim As Integer scanPosition
    Dim As Integer sourceLineNumber, sourceLineStart
    Dim As Integer rowLineNumber, rowLineStart

    ' Font advances are additive. Resolve the ASCII table once for long
    ' documents, rather than looking up the same glyph for every source byte.
    ' Rebuild it on each pass so font reloads and zoom need no cache lifetime.
    Dim As Integer asciiWidth(0 To 127)
    Dim As Integer useAsciiWidths = IIf(Len(textValue) >= 128, -1, 0)
    If useAsciiWidths Then
        For characterCode As Integer = 0 To 127
            asciiWidth(characterCode) = textbox_TextWidth(textData, Chr(characterCode))
        Next characterCode
    End If

    While textbox_NextVisibleVisualLine( _
        textValue, scanPosition, 0, 1, lineStart, lineEnd, textData, _
        sourceLineNumber, sourceLineStart, rowLineNumber, rowLineStart _
    )
        If useAsciiWidths Then
            lineWidth = 0
            Dim As Integer position = lineStart
            While position < lineEnd
                Dim As Integer characterCode = textValue[position]
                If characterCode < 128 Then
                    lineWidth += asciiWidth(characterCode)
                    position += 1
                Else
                    Dim As Integer sequenceLength = textbox_UTF8LengthAt(textValue, position)
                    lineWidth += textbox_TextWidth(textData, _
                        Mid(textValue, position + 1, sequenceLength))
                    position += sequenceLength
                End If
            Wend
        Else
            lineWidth = textbox_TextWidth(textData, _
                Mid(textValue, lineStart + 1, lineEnd - lineStart))
        End If
        If lineWidth > maximumWidth Then maximumWidth = lineWidth
    Wend
    Return maximumWidth
End Function


Private Function textbox_LineNumberGutterWidth( _
    ByVal textData As TextBoxData Ptr _
) As Integer
    Dim As Integer characterCode
    Dim As Integer digitCount
    Dim As Integer logicalLineCount = 1
    Dim As Integer position

    If textData = 0 OrElse textData->multiline = 0 OrElse _
       textData->line_numbers = 0 Then Return 0

    /'
        Count logical breaks directly so calculating the fixed gutter does not
        copy the document or depend on cursor-oriented line helpers. CRLF is
        one break, matching navigation and status coordinates.
    '/
    ' LEN releases possible string temporaries through the runtime. Borrow a
    ' stable length for this read-only scan instead of calling it per byte.
    Dim As Integer textLength = Len(textData->text)
    While position < textLength
        characterCode = textData->text[position]
        If characterCode = TEXTBOX_LINE_FEED Then
            logicalLineCount += 1
        Elseif characterCode = TEXTBOX_CARRIAGE_RETURN Then
            logicalLineCount += 1
            If position + 1 < textLength AndAlso _
               textData->text[position + 1] = TEXTBOX_LINE_FEED Then
                position += 1
            End If
        End If
        position += 1
    Wend
    digitCount = Len(LTrim(Str(logicalLineCount)))
    If digitCount < 1 Then digitCount = 1

    Return textbox_TextWidth(textData, String(digitCount, Asc("0"))) + _
        (TEXTBOX_LINE_NUMBER_PADDING * 2) + _
        TEXTBOX_LINE_NUMBER_SEPARATOR_WIDTH
End Function


Private Function textbox_ContentWidth( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr _
) As Integer
    Dim As Integer contentWidth

    If w = 0 Then Return 1

    contentWidth = w->w - textbox_TextPadding(textData) - _
        textbox_ScaledPadding(textData, TEXTBOX_TEXT_RIGHT_PADDING)

    If textData <> 0 Then
        contentWidth -= textbox_TotalGutterWidth(textData)

        If textData->scrollbar_visible <> 0 Then
            contentWidth -= TEXTBOX_SCROLLBAR_WIDTH + _
                TEXTBOX_SCROLLBAR_INSET
        End If
    End If

    If contentWidth < 1 Then contentWidth = 1
    Return contentWidth
End Function


/'
    A single unwrapped row edit can retain line counts and scrollbar geometry.
    Prove the unchanged layout header and both source ends byte for byte. Never
    reuse a width when the former widest row shrinks, or when line breaks or
    unmanaged visibility callbacks could change the layout. The ordinary full
    walk remains the fallback; no document history or extra snapshot is kept.
'/
#Ifdef OMAGUI_PROFILE_METRICS
' Qualification counters are GUI-thread owned and absent from production.
Private Dim Shared As Integer textbox_ProfileMetricsFull, textbox_ProfileMetricsRow
#EndIf

Private Const TEXTBOX_METRICS_COMPARE_BLOCK_BYTES As Integer = 4096

Private Function textbox_MatchingPrefixLength( _
    ByVal oldBytes As Const UByte Ptr, ByVal newBytes As Const UByte Ptr, _
    ByVal compareLength As Integer _
) As Integer
    Dim As Integer prefixLength
    Dim As Integer low
    Dim As Integer high

    ' Fixed blocks avoid repeatedly rescanning long prefixes on DOS.
    While compareLength - prefixLength >= TEXTBOX_METRICS_COMPARE_BLOCK_BYTES
        If oma_BytesEqual(oldBytes + prefixLength, newBytes + prefixLength, _
            TEXTBOX_METRICS_COMPARE_BLOCK_BYTES) = 0 Then Exit While
        prefixLength += TEXTBOX_METRICS_COMPARE_BLOCK_BYTES
    Wend

    high = compareLength - prefixLength
    If high > TEXTBOX_METRICS_COMPARE_BLOCK_BYTES Then _
        high = TEXTBOX_METRICS_COMPARE_BLOCK_BYTES
    While low < high
        Dim As Integer middle = low + (high - low + 1) \ 2
        If oma_BytesEqual(oldBytes + prefixLength, newBytes + prefixLength, middle) <> 0 Then
            low = middle
        Else
            high = middle - 1
        End If
    Wend

    Return prefixLength + low
End Function

Private Function textbox_MatchingSuffixLength( _
    ByVal oldBytes As Const UByte Ptr, ByVal newBytes As Const UByte Ptr, _
    ByVal oldLength As Integer, ByVal newLength As Integer, _
    ByVal compareLength As Integer, ByVal prefixLength As Integer _
) As Integer
    Dim As Integer suffixLength
    Dim As Integer remainingLength = compareLength - prefixLength
    Dim As Integer low
    Dim As Integer high

    While remainingLength - suffixLength >= TEXTBOX_METRICS_COMPARE_BLOCK_BYTES
        If oma_BytesEqual(oldBytes + oldLength - suffixLength - _
            TEXTBOX_METRICS_COMPARE_BLOCK_BYTES, _
            newBytes + newLength - suffixLength - _
            TEXTBOX_METRICS_COMPARE_BLOCK_BYTES, _
            TEXTBOX_METRICS_COMPARE_BLOCK_BYTES) = 0 Then Exit While
        suffixLength += TEXTBOX_METRICS_COMPARE_BLOCK_BYTES
    Wend

    high = remainingLength - suffixLength
    If high > TEXTBOX_METRICS_COMPARE_BLOCK_BYTES Then _
        high = TEXTBOX_METRICS_COMPARE_BLOCK_BYTES
    While low < high
        Dim As Integer middle = low + (high - low + 1) \ 2
        If oma_BytesEqual(oldBytes + oldLength - suffixLength - middle, _
            newBytes + newLength - suffixLength - middle, middle) <> 0 Then
            low = middle
        Else
            high = middle - 1
        End If
    Wend

    Return suffixLength + low
End Function

Private Function textbox_ChangedRangeHasNoNewlines( _
    ByVal oldBytes As Const UByte Ptr, ByVal newBytes As Const UByte Ptr, _
    ByVal prefixLength As Integer, ByVal oldChangedEnd As Integer, _
    ByVal newChangedEnd As Integer _
) As Integer
    If memchr(oldBytes + prefixLength, 10, _
        oldChangedEnd - prefixLength) <> 0 OrElse _
       memchr(oldBytes + prefixLength, 13, _
        oldChangedEnd - prefixLength) <> 0 OrElse _
       memchr(newBytes + prefixLength, 10, _
        newChangedEnd - prefixLength) <> 0 OrElse _
       memchr(newBytes + prefixLength, 13, _
        newChangedEnd - prefixLength) <> 0 Then Return 0
    Return -1
End Function

Private Function textbox_ChangedLineIsVisible( _
    ByVal textData As TextBoxData Ptr, ByVal oldBytes As Const UByte Ptr, _
    ByVal lineStart As Integer _
) As Integer
    If textData->line_visibility_handler = 0 Then Return -1

    Dim As Integer position
    Dim As Integer sourceRow
    For entryIndex As Integer = textData->metrics_row_count - 1 To 0 Step -1
        If textData->metrics_row_position(entryIndex) <= lineStart Then
            position = textData->metrics_row_position(entryIndex)
            sourceRow = textData->metrics_row_source_number(entryIndex)
            Exit For
        End If
    Next entryIndex

    ' Unwrapped checkpoint positions are source-line starts. Count intervening
    ' CR, LF, and CRLF sequences to restore the callback's original row number.
    While position < lineStart
        If oldBytes[position] = 13 Then
            sourceRow += 1
            If position + 1 < lineStart AndAlso oldBytes[position + 1] = 10 Then _
                position += 1
        ElseIf oldBytes[position] = 10 Then
            sourceRow += 1
        End If
        position += 1
    Wend

    Return IIf(textData->line_visibility_handler( _
        textData->owner, sourceRow, lineStart _
    ) <> 0, -1, 0)
End Function

Private Function textbox_TryUpdateLineMetrics(ByVal textData As TextBoxData Ptr, _
    ByRef displayText As Const String, ByRef metricsKey As Const String) As Integer
#Ifdef OMAGUI_DISABLE_INCREMENTAL_METRICS
    Return 0
#Else
    If textData->metrics_valid = 0 OrElse textData->wordwrap <> 0 OrElse _
       textData->multiline = 0 OrElse textData->metrics_row_count < 1 OrElse _
       textData->metrics_row_count > 32 Then Return 0
    If textData->line_visibility_handler <> 0 AndAlso textData->metrics_state_handler = 0 Then Return 0
    If textData->metrics_key = metricsKey Then Return 0
    Dim As Integer oldLength = textData->metrics_row_source_length
    Dim As Integer newLength = Len(displayText)
    Dim As Integer oldHeader = Len(textData->metrics_key) - oldLength
    Dim As Integer newHeader = Len(metricsKey) - newLength
    If oldLength < 4096 OrElse newLength < 4096 OrElse oldHeader < 0 OrElse oldHeader <> newHeader Then Return 0
    If oma_BytesEqual(StrPtr(textData->metrics_key), StrPtr(metricsKey), oldHeader) = 0 Then Return 0
    Dim As Const UByte Ptr oldBytes = StrPtr(textData->metrics_key) + oldHeader
    Dim As Const UByte Ptr newBytes = StrPtr(displayText)
    Dim As Integer minimumLength = IIf(oldLength < newLength, oldLength, newLength)
    Dim As Integer prefixLength = textbox_MatchingPrefixLength( _
        oldBytes, newBytes, minimumLength _
    )
    Dim As Integer suffixLength = textbox_MatchingSuffixLength( _
        oldBytes, newBytes, oldLength, newLength, _
        minimumLength, prefixLength _
    )
    Dim As Integer oldChangedEnd = oldLength - suffixLength
    Dim As Integer newChangedEnd = newLength - suffixLength
    If prefixLength = oldLength AndAlso prefixLength = newLength Then Return 0
    If textbox_ChangedRangeHasNoNewlines( _
        oldBytes, newBytes, prefixLength, _
        oldChangedEnd, newChangedEnd _
    ) = 0 Then Return 0
    Dim As Integer lineStart = prefixLength
    Dim As Integer oldLineEnd = oldChangedEnd
    Dim As Integer newLineEnd = newChangedEnd
    While lineStart > 0
        If oldBytes[lineStart - 1] = 10 OrElse oldBytes[lineStart - 1] = 13 Then Exit While
        lineStart -= 1
    Wend
    While oldLineEnd < oldLength
        If oldBytes[oldLineEnd] = 10 OrElse oldBytes[oldLineEnd] = 13 Then Exit While
        oldLineEnd += 1
    Wend
    While newLineEnd < newLength
        If newBytes[newLineEnd] = 10 OrElse newBytes[newLineEnd] = 13 Then Exit While
        newLineEnd += 1
    Wend
    If textbox_ChangedLineIsVisible(textData, oldBytes, lineStart) = 0 Then Return 0
    ' MID reads only this row. The old document stays borrowed from metrics_key.
    Dim As Integer oldWidth = textbox_TextWidth(textData, _
        Mid(textData->metrics_key, oldHeader + lineStart + 1, oldLineEnd - lineStart))
    Dim As Integer newWidth = textbox_TextWidth(textData, _
        Mid(displayText, lineStart + 1, newLineEnd - lineStart))
    If oldWidth >= textData->metrics_maximum_width AndAlso newWidth < oldWidth Then Return 0
    Dim As Integer maximumWidth = textData->metrics_maximum_width
    If newWidth > maximumWidth Then maximumWidth = newWidth
    ' A bar appearing or disappearing changes the client area. Let the full
    ' two-pass layout handle that transition, including automatic vertical bars.
    If textData->horizontal_scrollbar_mode = TEXTBOX_SCROLLBAR_AUTO Then
        Dim As Integer needsBar = IIf(maximumWidth > textbox_ContentWidth(textData->owner, textData), -1, 0)
        If needsBar <> textData->metrics_horizontal_visible Then Return 0
    End If
    Dim As Integer lengthDelta = newLength - oldLength
    For entryIndex As Integer = 0 To textData->metrics_row_count - 1
        If textData->metrics_row_position(entryIndex) > oldLineEnd Then _
            textData->metrics_row_position(entryIndex) += lengthDelta
    Next entryIndex
    textData->metrics_row_source_length = newLength
    textData->metrics_maximum_width = maximumWidth
    textData->metrics_key = metricsKey
#Ifdef OMAGUI_PROFILE_METRICS
    textbox_ProfileMetricsRow += 1
#EndIf
    Return -1
#EndIf
End Function

Private Sub textbox_UpdateScrollMetrics( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr _
)
    Dim As Integer contentWidth
    Dim As Integer horizontalMaximum
    Dim As Integer horizontalMode
    Dim As ScrollBarData Ptr horizontalData
    Dim As Integer iteration
    Dim As Integer maximumLineWidth
    Dim As Integer maximumScroll
    Dim As Integer mode
    Dim As ScrollBarData Ptr scrollData
    Dim As Integer visibleLines

    If w = 0 OrElse textData = 0 Then Exit Sub
    Dim ByRef displayText As String = textbox_VisualText(textData)

    mode = textData->scrollbar_mode
    If mode < TEXTBOX_SCROLLBAR_NONE OrElse _
       mode > TEXTBOX_SCROLLBAR_ALWAYS Then
        mode = TEXTBOX_SCROLLBAR_AUTO
        textData->scrollbar_mode = mode
    End If
    horizontalMode = textData->horizontal_scrollbar_mode
    If horizontalMode < TEXTBOX_SCROLLBAR_NONE OrElse _
       horizontalMode > TEXTBOX_SCROLLBAR_ALWAYS Then
        horizontalMode = TEXTBOX_SCROLLBAR_AUTO
        textData->horizontal_scrollbar_mode = horizontalMode
    End If

    Dim As String visibilityKey
    Dim As String metricsKey = MKLongInt(w->w) & MKLongInt(w->h) & _
        MKLongInt(backend_GetFontGeneration())
    #define METRICS_FIELD(field) metricsKey &= MKLongInt(textData->field)
    METRICS_FIELD(multiline)
    METRICS_FIELD(wordwrap)
    METRICS_FIELD(scrollbar_mode)
    METRICS_FIELD(horizontal_scrollbar_mode)
    METRICS_FIELD(line_numbers)
    METRICS_FIELD(line_numbers_visible)
    METRICS_FIELD(fold_gutter_width)
    METRICS_FIELD(font_id)
    METRICS_FIELD(font_scale_percent)
    METRICS_FIELD(zoom_percent)
    METRICS_FIELD(extra_line_spacing)
    METRICS_FIELD(text_style)
    #undef METRICS_FIELD
    ' Pointer-sized conversion supports ARM32 while preserving 8-byte key fields.
    metricsKey &= MKLongInt(CLngInt(CUInt(textData->line_visibility_handler)))
    metricsKey &= MKLongInt(CLngInt(CUInt(textData->metrics_state_handler)))
    If textData->line_visibility_handler <> 0 Then
        If textData->metrics_state_handler <> 0 Then
            visibilityKey = textData->metrics_state_handler(w)
            metricsKey &= MKLongInt(Len(visibilityKey)) & visibilityKey
        Else
            metricsKey &= MKLongInt(textData->cursor_pos)
        End If
    End If
    ' Most calls only confirm the existing layout. Compare the short header
    ' and borrowed document separately before allocating another full key.
    ' Exact bytes still detect same-length edits made through legacy fields.
    Dim As Integer unchangedMetrics
    Dim As Integer retainedRowMetrics
    Dim As Integer headerLength = Len(metricsKey)
    If textData->metrics_valid <> 0 AndAlso _
       Len(textData->metrics_key) >= headerLength AndAlso _
       Len(textData->metrics_key) - headerLength = Len(displayText) Then
        If oma_BytesEqual(StrPtr(textData->metrics_key), StrPtr(metricsKey), headerLength) <> 0 AndAlso _
           oma_BytesEqual(StrPtr(textData->metrics_key) + headerLength, StrPtr(displayText), Len(displayText)) <> 0 Then _
            unchangedMetrics = -1
    End If
    If unchangedMetrics = 0 Then
        metricsKey &= displayText
        retainedRowMetrics = textbox_TryUpdateLineMetrics(textData, displayText, metricsKey)
        If retainedRowMetrics <> 0 Then unchangedMetrics = -1
    End If
    ' With exact source/layout state, viewport_dirty requests caret placement,
    ' not another full measurement. Unmanaged opt-in callbacks still use that
    ' flag as their explicit invalidation contract.
    Dim As Integer exactLayoutState = IIf(textData->line_visibility_handler = 0 OrElse _
        textData->metrics_state_handler <> 0, -1, 0)
    If textData->metrics_valid <> 0 AndAlso (textData->viewport_dirty = 0 OrElse _
       retainedRowMetrics <> 0 OrElse exactLayoutState <> 0) AndAlso _
       (textData->line_visibility_handler = 0 OrElse _
        textData->metrics_cache_callbacks <> 0 OrElse _
        textData->metrics_state_handler <> 0) AndAlso _
       unchangedMetrics <> 0 Then
        maximumLineWidth = textData->metrics_maximum_width
        textData->line_number_gutter_width = textData->metrics_gutter_width
        textData->total_visual_lines = textData->metrics_total_lines
        textData->scrollbar_visible = textData->metrics_vertical_visible
        textData->horizontal_scrollbar_visible = textData->metrics_horizontal_visible
        contentWidth = textbox_ContentWidth(w, textData)
        visibleLines = textbox_VisibleLineCount(w, textData)
    Else
        ' An unmanaged callback can require a fresh measurement even when its
        ' key bytes match. The retained snapshot must still contain the source.
        If unchangedMetrics <> 0 AndAlso retainedRowMetrics = 0 Then metricsKey &= displayText
        textData->metrics_row_source_length = Len(displayText)
        textData->metrics_row_visibility_key = visibilityKey
        textData->metrics_row_visibility_handler = textData->line_visibility_handler
        textData->metrics_row_state_handler = textData->metrics_state_handler
        textData->line_number_gutter_width = _
            textbox_LineNumberGutterWidth(textData)

        textData->scrollbar_visible = 0
        textData->horizontal_scrollbar_visible = 0
#Ifdef OMAGUI_PROFILE_METRICS
        textbox_ProfileMetricsFull += 1
#EndIf
        maximumLineWidth = textbox_MaximumLineWidth(displayText, textData)

        /'
            Vertical and horizontal bars reserve space from one another. Two passes
            are sufficient because each visibility decision can only reduce the
            remaining client area; neither pass can make a previously required bar
            unnecessary. Word-wrapped controls never expose horizontal scrolling.
        '/
        If textData->multiline <> 0 Then
            For iteration = 0 To 1
                contentWidth = textbox_ContentWidth(w, textData)
                visibleLines = textbox_VisibleLineCount(w, textData)

                If mode = TEXTBOX_SCROLLBAR_ALWAYS Then
                    textData->scrollbar_visible = -1
                ElseIf mode = TEXTBOX_SCROLLBAR_AUTO AndAlso _
                       textbox_CountVisualLines( _
                           displayText, textData->wordwrap, contentWidth, textData _
                       ) > visibleLines Then
                    textData->scrollbar_visible = -1
                End If

                If textData->wordwrap = 0 Then
                    contentWidth = textbox_ContentWidth(w, textData)
                    If horizontalMode = TEXTBOX_SCROLLBAR_ALWAYS Then
                        textData->horizontal_scrollbar_visible = -1
                    ElseIf horizontalMode = TEXTBOX_SCROLLBAR_AUTO AndAlso _
                           maximumLineWidth > contentWidth _
                           Then
                        textData->horizontal_scrollbar_visible = -1
                    End If
                End If
            Next iteration
        End If

        contentWidth = textbox_ContentWidth(w, textData)
        visibleLines = textbox_VisibleLineCount(w, textData)
        textData->metrics_row_count = 0
        Dim As Integer buildRowIndex = IIf(textData->line_visibility_handler = 0 OrElse _
            textData->metrics_cache_callbacks <> 0 OrElse textData->metrics_state_handler <> 0, -1, 0)
        textData->total_visual_lines = textbox_CountVisualLines( _
            displayText, textData->wordwrap, contentWidth, textData, buildRowIndex _
        )
        textData->metrics_key = metricsKey
        textData->metrics_valid = -1
        textData->metrics_maximum_width = maximumLineWidth
        textData->metrics_gutter_width = textData->line_number_gutter_width
        textData->metrics_total_lines = textData->total_visual_lines
        textData->metrics_vertical_visible = textData->scrollbar_visible
        textData->metrics_horizontal_visible = textData->horizontal_scrollbar_visible
    End If
    maximumScroll = textData->total_visual_lines - visibleLines
    If maximumScroll < 0 Then maximumScroll = 0

    If textData->v_scroll < 0 Then textData->v_scroll = 0
    If textData->v_scroll > maximumScroll Then _
        textData->v_scroll = maximumScroll

    If textData->vertical_scrollbar = 0 OrElse _
       textData->vertical_scrollbar->data = 0 Then
        Exit Sub
    End If

    textData->vertical_scrollbar->ax = w->ax + w->w - _
        TEXTBOX_SCROLLBAR_WIDTH - TEXTBOX_SCROLLBAR_INSET
    textData->vertical_scrollbar->ay = w->ay + TEXTBOX_SCROLLBAR_INSET
    textData->vertical_scrollbar->w = TEXTBOX_SCROLLBAR_WIDTH
    textData->vertical_scrollbar->h = w->h - _
        (TEXTBOX_SCROLLBAR_INSET * 2)
    If textData->horizontal_scrollbar_visible <> 0 Then
        textData->vertical_scrollbar->h -= _
            TEXTBOX_SCROLLBAR_WIDTH + TEXTBOX_SCROLLBAR_INSET
    End If

    If textData->vertical_scrollbar->h < 1 Then _
        textData->vertical_scrollbar->h = 1

    scrollData = Cast( _
        ScrollBarData Ptr, textData->vertical_scrollbar->data _
    )
    scrollData->value = textData->v_scroll
    scrollData->max_val = maximumScroll
    scrollData->page_size = visibleLines
    scrollData->vertical = -1
    textData->vertical_scrollbar->enabled = IIf(maximumScroll > 0, -1, 0)

    If textData->horizontal_scrollbar = 0 OrElse _
       textData->horizontal_scrollbar->data = 0 Then Exit Sub
    horizontalMaximum = maximumLineWidth + _
        TEXTBOX_CURSOR_VISIBLE_WIDTH - contentWidth
    If horizontalMaximum < 0 Then horizontalMaximum = 0
    If textData->scroll_offset < 0 Then textData->scroll_offset = 0
    If textData->scroll_offset > horizontalMaximum Then _
        textData->scroll_offset = horizontalMaximum
    textData->horizontal_scrollbar->ax = w->ax + TEXTBOX_SCROLLBAR_INSET + _
        textbox_TotalGutterWidth(textData)
    textData->horizontal_scrollbar->ay = w->ay + w->h - _
        TEXTBOX_SCROLLBAR_WIDTH - TEXTBOX_SCROLLBAR_INSET
    textData->horizontal_scrollbar->w = w->w - _
        (TEXTBOX_SCROLLBAR_INSET * 2) - _
        textbox_TotalGutterWidth(textData)
    If textData->scrollbar_visible <> 0 Then
        textData->horizontal_scrollbar->w -= _
            TEXTBOX_SCROLLBAR_WIDTH + TEXTBOX_SCROLLBAR_INSET
    End If
    If textData->horizontal_scrollbar->w < 1 Then _
        textData->horizontal_scrollbar->w = 1
    textData->horizontal_scrollbar->h = TEXTBOX_SCROLLBAR_WIDTH
    horizontalData = Cast( _
        ScrollBarData Ptr, textData->horizontal_scrollbar->data _
    )
    horizontalData->value = textData->scroll_offset
    horizontalData->max_val = horizontalMaximum
    horizontalData->page_size = contentWidth
    horizontalData->small_change = 8
    horizontalData->large_change = contentWidth
    horizontalData->vertical = 0
    textData->horizontal_scrollbar->enabled = _
        IIf(horizontalMaximum > 0, -1, 0)
End Sub


Private Function textbox_PointInOwnedScrollbar( _
    ByVal scrollWidget As Widget Ptr, _
    ByVal mouseX As Integer, ByVal mouseY As Integer _
) As Integer
    If scrollWidget = 0 Then Return 0

    Return IIf( _
        mouseX >= scrollWidget->ax AndAlso _
        mouseX < scrollWidget->ax + scrollWidget->w AndAlso _
        mouseY >= scrollWidget->ay AndAlso _
        mouseY < scrollWidget->ay + scrollWidget->h, _
        1, 0 _
    )
End Function


Private Function textbox_HandleScrollInput( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr, _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer, _
    ByVal mouseButtons As Integer _
) As Integer
    Dim As ScrollBarData Ptr horizontalData
    Dim As Integer horizontalMaximum
    Dim As Widget Ptr horizontalWidget
    Dim As Integer insideWidget
    Dim As Integer maximumScroll
    Dim As ScrollBarData Ptr scrollData
    Dim As Widget Ptr scrollWidget
    Dim As Integer wheelDelta

    If w = 0 OrElse textData = 0 Then Return 0
    If textData->multiline = 0 Then Return 0

    insideWidget = IIf( _
        mouseX >= w->ax AndAlso mouseX < w->ax + w->w AndAlso _
        mouseY >= w->ay AndAlso mouseY < w->ay + w->h, _
        1, 0 _
    )
    maximumScroll = textData->total_visual_lines - _
        textbox_VisibleLineCount(w, textData)
    If maximumScroll < 0 Then maximumScroll = 0

    wheelDelta = input_MouseWheel()
    If insideWidget <> 0 AndAlso wheelDelta <> 0 AndAlso _
       maximumScroll > 0 Then
        textData->v_scroll -= wheelDelta * TEXTBOX_WHEEL_LINES
        textbox_UpdateScrollMetrics w, textData
    End If

    If (mouseButtons And 1) = 0 Then
        textData->scrollbar_dragging = 0
        textData->horizontal_scrollbar_dragging = 0
        Return 0
    End If

    scrollWidget = textData->vertical_scrollbar
    If scrollWidget = 0 OrElse scrollWidget->data = 0 OrElse _
       textData->scrollbar_visible = 0 Then
        textData->scrollbar_dragging = 0
    ElseIf textData->scrollbar_dragging <> 0 OrElse _
           textbox_PointInOwnedScrollbar( _
               scrollWidget, mouseX, mouseY _
           ) <> 0 Then
        textData->scrollbar_dragging = -1
        textData->horizontal_scrollbar_dragging = 0
        textData->mouse_latch = 1
        textData->mouse_selecting = 0
        scrollData = Cast(ScrollBarData Ptr, scrollWidget->data)

        If maximumScroll > 0 AndAlso scrollWidget->h > 0 Then
            scrollData->value = _
                ((mouseY - scrollWidget->ay) * maximumScroll) \ _
                scrollWidget->h
            If scrollData->value < 0 Then scrollData->value = 0
            If scrollData->value > maximumScroll Then _
                scrollData->value = maximumScroll
            textData->v_scroll = scrollData->value
        End If
        Return 1
    End If

    horizontalWidget = textData->horizontal_scrollbar
    If horizontalWidget = 0 OrElse horizontalWidget->data = 0 OrElse _
       textData->horizontal_scrollbar_visible = 0 Then
        textData->horizontal_scrollbar_dragging = 0
        Return 0
    End If
    If textData->horizontal_scrollbar_dragging = 0 AndAlso _
       textbox_PointInOwnedScrollbar( _
           horizontalWidget, mouseX, mouseY _
       ) = 0 Then Return 0

    textData->horizontal_scrollbar_dragging = -1
    textData->scrollbar_dragging = 0
    textData->mouse_latch = 1
    textData->mouse_selecting = 0
    horizontalData = Cast(ScrollBarData Ptr, horizontalWidget->data)
    horizontalMaximum = horizontalData->max_val
    If horizontalMaximum > 0 AndAlso horizontalWidget->w > 0 Then
        horizontalData->value = _
            ((mouseX - horizontalWidget->ax) * horizontalMaximum) \ _
            horizontalWidget->w
        If horizontalData->value < 0 Then horizontalData->value = 0
        If horizontalData->value > horizontalMaximum Then _
            horizontalData->value = horizontalMaximum
        textData->scroll_offset = horizontalData->value
    End If

    Return 1
End Function


Private Sub textbox_CollapseSelectionAt( _
    ByVal textData As TextBoxData Ptr, _
    ByVal position As Integer, ByVal virtualSpace As Integer _
)
    If textData = 0 Then Exit Sub
    position = textbox_ClampCharacterPosition(textData->text, position)
    virtualSpace = textbox_ClampVirtualSpace( _
        textData, position, virtualSpace _
    )
    textData->cursor_pos = position
    textData->sel_start = position
    textData->sel_end = position
    textData->selection_anchor = position
    textData->cursor_virtual_space = virtualSpace
    textData->sel_start_virtual_space = virtualSpace
    textData->sel_end_virtual_space = virtualSpace
    textData->selection_anchor_virtual_space = virtualSpace
End Sub


Private Sub textbox_CollapseSelection( _
    ByVal textData As TextBoxData Ptr, ByVal position As Integer _
)
    textbox_CollapseSelectionAt textData, position, 0
End Sub


Private Sub textbox_ExtendSelectionAt( _
    ByVal textData As TextBoxData Ptr, _
    ByVal position As Integer, ByVal virtualSpace As Integer _
)
    If textData = 0 Then Exit Sub
    position = textbox_ClampCharacterPosition(textData->text, position)
    textData->selection_anchor = textbox_ClampCharacterPosition( _
        textData->text, textData->selection_anchor _
    )
    textData->selection_anchor_virtual_space = _
        textbox_ClampVirtualSpace( _
            textData, textData->selection_anchor, _
            textData->selection_anchor_virtual_space _
        )
    virtualSpace = textbox_ClampVirtualSpace( _
        textData, position, virtualSpace _
    )
    textData->cursor_pos = position
    textData->cursor_virtual_space = virtualSpace
    If textbox_ComparePositions( _
        position, virtualSpace, textData->selection_anchor, _
        textData->selection_anchor_virtual_space _
    ) < 0 Then
        textData->sel_start = position
        textData->sel_end = textData->selection_anchor
        textData->sel_start_virtual_space = virtualSpace
        textData->sel_end_virtual_space = _
            textData->selection_anchor_virtual_space
    Else
        textData->sel_start = textData->selection_anchor
        textData->sel_end = position
        textData->sel_start_virtual_space = _
            textData->selection_anchor_virtual_space
        textData->sel_end_virtual_space = virtualSpace
    End If
End Sub


Private Sub textbox_ExtendSelection( _
    ByVal textData As TextBoxData Ptr, ByVal position As Integer _
)
    textbox_ExtendSelectionAt textData, position, 0
End Sub


Private Sub textbox_DeleteSelection(ByVal textData As TextBoxData Ptr)
    Dim As Integer startPosition, endPosition
    Dim As Integer startVirtualSpace, endVirtualSpace
    If textData = 0 Then Exit Sub
    startPosition = textbox_ClampCharacterPosition( _
        textData->text, textData->sel_start _
    )
    endPosition = textbox_ClampCharacterPosition( _
        textData->text, textData->sel_end _
    )
    startVirtualSpace = textbox_ClampVirtualSpace( _
        textData, startPosition, textData->sel_start_virtual_space _
    )
    endVirtualSpace = textbox_ClampVirtualSpace( _
        textData, endPosition, textData->sel_end_virtual_space _
    )
    If textbox_ComparePositions( _
        endPosition, endVirtualSpace, startPosition, startVirtualSpace _
    ) < 0 Then
        Swap startPosition, endPosition
        Swap startVirtualSpace, endVirtualSpace
    End If
    If textbox_ComparePositions( _
        startPosition, startVirtualSpace, endPosition, endVirtualSpace _
    ) = 0 Then
        textbox_CollapseSelectionAt _
            textData, startPosition, startVirtualSpace
        Exit Sub
    End If
    If endPosition > startPosition Then
        textData->text = Left(textData->text, startPosition) & _
            Mid(textData->text, endPosition + 1)
        textData->change_serial += 1
    End If
    textbox_CollapseSelectionAt _
        textData, startPosition, startVirtualSpace
End Sub


Private Function textbox_SelectedText( _
    ByVal textData As TextBoxData Ptr _
) As String
    Dim As Integer startPosition, endPosition
    Dim As Integer startVirtualSpace, endVirtualSpace
    If textData = 0 Then Return ""
    startPosition = textbox_ClampCharacterPosition( _
        textData->text, textData->sel_start _
    )
    endPosition = textbox_ClampCharacterPosition( _
        textData->text, textData->sel_end _
    )
    startVirtualSpace = textbox_ClampVirtualSpace( _
        textData, startPosition, textData->sel_start_virtual_space _
    )
    endVirtualSpace = textbox_ClampVirtualSpace( _
        textData, endPosition, textData->sel_end_virtual_space _
    )
    If textbox_ComparePositions( _
        endPosition, endVirtualSpace, startPosition, startVirtualSpace _
    ) < 0 Then
        Swap startPosition, endPosition
        Swap startVirtualSpace, endVirtualSpace
    End If
    If textbox_ComparePositions( _
        startPosition, startVirtualSpace, endPosition, endVirtualSpace _
    ) = 0 Then Return ""
    If endPosition = startPosition Then _
        Return Space(endVirtualSpace - startVirtualSpace)
    Return Mid( _
        textData->text, startPosition + 1, endPosition - startPosition _
    ) & Space(endVirtualSpace)
End Function


Private Function textbox_ConstrainInput(ByVal textData As TextBoxData Ptr, ByRef insertedText As String) As Integer
    If textData = 0 OrElse Len(insertedText) = 0 Then Return 0
    If textData->input_limit = 0 Then Return -1
    Dim As Integer selectionStart = textbox_ClampCharacterPosition( _
        textData->text, textData->sel_start _
    )
    Dim As Integer selectionEnd = textbox_ClampCharacterPosition( _
        textData->text, textData->sel_end _
    )
    Dim As Integer startVirtualSpace = textbox_ClampVirtualSpace( _
        textData, selectionStart, textData->sel_start_virtual_space _
    )
    Dim As Integer endVirtualSpace = textbox_ClampVirtualSpace( _
        textData, selectionEnd, textData->sel_end_virtual_space _
    )
    If textbox_ComparePositions( _
        selectionEnd, endVirtualSpace, selectionStart, startVirtualSpace _
    ) < 0 Then
        Swap selectionStart, selectionEnd
        Swap startVirtualSpace, endVirtualSpace
    End If
    Dim As Integer virtualPadding = textbox_ClampVirtualSpace( _
        textData, textData->cursor_pos, textData->cursor_virtual_space _
    )
    If textbox_HasSelectionData(textData) <> 0 Then _
        virtualPadding = startVirtualSpace
    Dim As LongInt room = CLngInt(textData->input_limit) - _
        Len(textData->text) + selectionEnd - selectionStart - _
        virtualPadding
    ' Do this before deleting the selection or opening an undo transaction.
    ' Source-assigned text may already exceed the newly selected input limit.
    If room <= 0 Then Return 0
    If Len(insertedText) > room Then insertedText = Left(insertedText, CInt(room))
    Return -1
End Function


Private Function textbox_InsertionResultLength( _
    ByVal textData As TextBoxData Ptr, ByVal insertedBytes As Integer _
) As LongInt
    Dim As Integer startPosition = textbox_ClampCharacterPosition( _
        textData->text, textData->sel_start _
    )
    Dim As Integer endPosition = textbox_ClampCharacterPosition( _
        textData->text, textData->sel_end _
    )
    Dim As Integer startVirtualSpace = textbox_ClampVirtualSpace( _
        textData, startPosition, textData->sel_start_virtual_space _
    )
    Dim As Integer endVirtualSpace = textbox_ClampVirtualSpace( _
        textData, endPosition, textData->sel_end_virtual_space _
    )
    If textbox_ComparePositions( _
        endPosition, endVirtualSpace, startPosition, startVirtualSpace _
    ) < 0 Then
        Swap startPosition, endPosition
        Swap startVirtualSpace, endVirtualSpace
    End If

    Dim As Integer padding = textbox_ClampVirtualSpace( _
        textData, textData->cursor_pos, textData->cursor_virtual_space _
    )
    If textbox_HasSelectionData(textData) <> 0 Then _
        padding = startVirtualSpace

    If insertedBytes = 0 Then padding = 0
    Return CLngInt(Len(textData->text)) - _
        (endPosition - startPosition) + padding + insertedBytes
End Function

Private Sub textbox_InsertText(ByVal textData As TextBoxData Ptr, ByVal insertedText As String)

    If textData = 0 OrElse insertedText = "" Then Exit Sub

    textbox_DeleteSelection textData
    Dim As Integer position = textbox_ClampCharacterPosition( _
        textData->text, textData->cursor_pos _
    )
    Dim As Integer virtualSpace = textbox_ClampVirtualSpace( _
        textData, position, textData->cursor_virtual_space _
    )
    Dim As String materializedText = Space(virtualSpace) & insertedText
    If textData->input_limit > 0 AndAlso _
       CLngInt(Len(textData->text)) + Len(materializedText) > _
           textData->input_limit Then Exit Sub
    textData->text = Left(textData->text, position) & materializedText & _
        Mid(textData->text, position + 1)
    textData->change_serial += 1
    textbox_CollapseSelection textData, position + Len(materializedText)

End Sub


Private Sub textbox_ClearKeyLatch(ByVal textData As TextBoxData Ptr, ByVal keyCode As Integer, ByVal keyMask As Integer)

    If textData = 0 Then Exit Sub
    If input_KeyPressed(keyCode) <> 0 Then Exit Sub

    If (textData->key_latch And keyMask) <> 0 Then textData->key_latch -= keyMask

End Sub


Private Sub textbox_RefreshKeyLatch(ByVal textData As TextBoxData Ptr)

    If textData = 0 Then Exit Sub

    textbox_ClearKeyLatch textData, KEY_BACKSPACE, TEXTBOX_KEY_LATCH_BACKSPACE
    textbox_ClearKeyLatch textData, KEY_DELETE, TEXTBOX_KEY_LATCH_DELETE
    textbox_ClearKeyLatch textData, KEY_RETURN, TEXTBOX_KEY_LATCH_RETURN
    textbox_ClearKeyLatch textData, KEY_LEFT, TEXTBOX_KEY_LATCH_LEFT
    textbox_ClearKeyLatch textData, KEY_RIGHT, TEXTBOX_KEY_LATCH_RIGHT
    textbox_ClearKeyLatch textData, KEY_HOME, TEXTBOX_KEY_LATCH_HOME
    textbox_ClearKeyLatch textData, KEY_END, TEXTBOX_KEY_LATCH_END
    textbox_ClearKeyLatch textData, KEY_UP, TEXTBOX_KEY_LATCH_UP
    textbox_ClearKeyLatch textData, KEY_DOWN, TEXTBOX_KEY_LATCH_DOWN
    textbox_ClearKeyLatch textData, FB.SC_Z, TEXTBOX_KEY_LATCH_UNDO
    textbox_ClearKeyLatch textData, FB.SC_Y, TEXTBOX_KEY_LATCH_REDO
    textbox_ClearKeyLatch textData, FB.SC_A, TEXTBOX_KEY_LATCH_SELECT_ALL
    textbox_ClearKeyLatch textData, FB.SC_C, TEXTBOX_KEY_LATCH_COPY
    textbox_ClearKeyLatch textData, FB.SC_X, TEXTBOX_KEY_LATCH_CUT
    textbox_ClearKeyLatch textData, FB.SC_V, TEXTBOX_KEY_LATCH_PASTE
    textbox_ClearKeyLatch textData, FB.SC_RIGHTBRACKET, TEXTBOX_KEY_LATCH_INDENT
    textbox_ClearKeyLatch textData, FB.SC_LEFTBRACKET, TEXTBOX_KEY_LATCH_UNINDENT

End Sub


Private Function textbox_KeyJustPressed(ByVal textData As TextBoxData Ptr, ByVal keyCode As Integer, ByVal keyMask As Integer) As Integer

    If textData = 0 Then Return 0
    If input_KeyPressed(keyCode) = 0 Then Return 0
    If (textData->key_latch And keyMask) <> 0 Then Return 0

    textData->key_latch Or= keyMask
    Return 1

End Function


Private Function textbox_ControlShortcutJustPressed( _
    ByVal textData As TextBoxData Ptr, _
    ByVal keyCode As Integer, _
    ByVal keyMask As Integer _
) As Integer

    If textData = 0 Then Return 0
    If (textData->key_latch And keyMask) <> 0 Then Return 0

    If input_ControlShortcutPressed(keyCode) <> 0 OrElse _
       (input_KeyPressed(FB.SC_CONTROL) <> 0 AndAlso _
        input_KeyPressed(keyCode) <> 0) Then
        textData->key_latch Or= keyMask
        Return 1
    End If

    Return 0

End Function


Private Function textbox_LineStart(ByRef textValue As Const String, ByVal position As Integer) As Integer

    position = textbox_ClampPosition(textValue, position)

    While position > 0
        If textValue[position - 1] = TEXTBOX_LINE_FEED OrElse _
           textValue[position - 1] = TEXTBOX_CARRIAGE_RETURN Then
            Exit While
        End If
        position -= 1
    Wend

    Return position

End Function


Private Function textbox_LineEnd(ByRef textValue As Const String, ByVal position As Integer) As Integer

    position = textbox_ClampPosition(textValue, position)

    While position < Len(textValue)
        If textValue[position] = TEXTBOX_LINE_FEED OrElse _
           textValue[position] = TEXTBOX_CARRIAGE_RETURN Then
            Exit While
        End If
        position += 1
    Wend

    Return position

End Function


Private Function textbox_LineStartByIndex( _
    ByRef textValue As Const String, _
    ByVal lineIndex As Integer _
) As Integer

    Dim currentLine As Integer
    Dim position As Integer

    If lineIndex <= 0 Then Return 0

    While position < Len(textValue)
        If textValue[position] = TEXTBOX_LINE_FEED Then
            currentLine += 1
            position += 1
        Elseif textValue[position] = TEXTBOX_CARRIAGE_RETURN Then
            currentLine += 1
            position += 1

            If position < Len(textValue) AndAlso _
               textValue[position] = TEXTBOX_LINE_FEED Then
                position += 1
            End If
        Else
            position += 1
        End If

        If currentLine >= lineIndex Then Return position
    Wend

    Return Len(textValue)

End Function


Private Function textbox_PositionFromPoint( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr, _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer, _
    ByRef virtualSpace As Integer _
) As Integer

    Dim characterWidth As Integer
    Dim lineEnd As Integer
    Dim contentWidth As Integer
    Dim lineIndex As Integer
    Dim lineStart As Integer
    Dim targetX As Integer
    Dim textWidth As Integer

    virtualSpace = 0
    If w = 0 OrElse textData = 0 Then Return 0
    Dim ByRef displayText As String = textbox_VisualText(textData)

    lineIndex = textData->v_scroll + _
        (mouseY - w->ay - textbox_TextPadding(textData)) \ _
        textbox_LineHeight(textData)
    If lineIndex < 0 Then lineIndex = 0

    contentWidth = textbox_ContentWidth(w, textData)
    If textbox_VisualLineBounds( _
        displayText, lineIndex, textData->wordwrap, contentWidth, _
        lineStart, lineEnd, textData _
    ) = 0 Then
        Return Len(displayText)
    End If
    targetX = mouseX - w->ax - textbox_TextPadding(textData) - _
        textbox_TotalGutterWidth(textData)

    If textData->wordwrap = 0 Then targetX += textData->scroll_offset
    If targetX <= 0 Then Return lineStart

    Dim As Integer position = lineStart
    While position < lineEnd
        Dim As Integer sequenceLength = textbox_UTF8LengthAt(displayText, position)
        characterWidth = textbox_TextWidth(textData, _
            Mid(displayText, position + 1, sequenceLength) _
        )

        If targetX < textWidth + (characterWidth + 1) \ 2 Then _
            Return position
        textWidth += characterWidth
        position += sequenceLength
    Wend

    If textData->virtual_space_enabled <> 0 AndAlso _
       textData->wordwrap = 0 AndAlso _
       textbox_LineEnd(textData->text, lineEnd) = lineEnd AndAlso _
       targetX > textWidth Then
        Dim As Integer spaceWidth = textbox_TextWidth(textData, " ")
        If spaceWidth < 1 Then spaceWidth = 1
        virtualSpace = _
            (targetX - textWidth + spaceWidth \ 2) \ spaceWidth
        If virtualSpace > TEXTBOX_MAX_VIRTUAL_SPACE Then _
            virtualSpace = TEXTBOX_MAX_VIRTUAL_SPACE
    End If
    Return lineEnd

End Function


Private Function textbox_ShiftPressed() As Integer

    Return IIf( _
        input_KeyPressed(FB.SC_LSHIFT) <> 0 OrElse _
        input_KeyPressed(FB.SC_RSHIFT) <> 0, _
        1, 0 _
    )

End Function


Private Sub textbox_MoveCursorVertical( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr, _
    ByVal direction As Integer, _
    ByVal extendSelection As Integer _
)

    Dim contentWidth As Integer
    Dim currentEnd As Integer
    Dim currentLine As Integer
    Dim currentStart As Integer
    Dim currentColumn As Integer
    Dim targetLine As Integer
    Dim targetPosition As Integer
    Dim targetStart As Integer
    Dim targetEnd As Integer
    Dim As Integer targetVirtualSpace

    If w = 0 OrElse textData = 0 OrElse direction = 0 Then Exit Sub
    Dim ByRef displayText As String = textbox_VisualText(textData)

    textData->cursor_pos = textbox_ClampPosition(displayText, textData->cursor_pos)
    contentWidth = textbox_ContentWidth(w, textData)
    currentLine = textbox_VisualLineForPosition( _
        displayText, textData->cursor_pos, _
        textData->wordwrap, contentWidth, textData _
    )
    targetLine = currentLine + direction
    If targetLine < 0 Then Exit Sub

    If textbox_VisualLineBounds( _
        displayText, currentLine, textData->wordwrap, contentWidth, _
        currentStart, currentEnd, textData _
    ) = 0 Then
        Exit Sub
    End If
    If textbox_VisualLineBounds( _
        displayText, targetLine, textData->wordwrap, contentWidth, _
        targetStart, targetEnd, textData _
    ) = 0 Then
        Exit Sub
    End If

    /'
        Keep the visual x coordinate when moving between rows. A byte column
        can land inside UTF-8 and does not match proportional glyph advances.
    '/
    Dim As Integer asciiRows = -1
    For byteIndex As Integer = currentStart To currentEnd - 1
        If displayText[byteIndex] >= &H80 Then asciiRows = 0
    Next byteIndex
    For byteIndex As Integer = targetStart To targetEnd - 1
        If displayText[byteIndex] >= &H80 Then asciiRows = 0
    Next byteIndex
    If asciiRows <> 0 AndAlso textData->cursor_virtual_space = 0 Then
        ' Preserve the established logical-column behavior for ASCII rows.
        currentColumn = textData->cursor_pos - currentStart
        targetPosition = targetStart + currentColumn
        If targetPosition > targetEnd Then targetPosition = targetEnd
    Else
        currentColumn = textbox_TextWidth(textData, _
            Mid(displayText, currentStart + 1, _
                textData->cursor_pos - currentStart) _
        )
        Dim As Integer spaceWidth = textbox_TextWidth(textData, " ")
        If spaceWidth < 1 Then spaceWidth = 1
        currentColumn += textData->cursor_virtual_space * spaceWidth
        Dim As Integer targetX = w->ax + textbox_TextPadding(textData) + _
            textbox_TotalGutterWidth(textData) + currentColumn
        If textData->wordwrap = 0 Then targetX -= textData->scroll_offset
        Dim As Integer targetY = w->ay + textbox_TextPadding(textData) + _
            (targetLine - textData->v_scroll) * textbox_LineHeight(textData)
        targetPosition = textbox_PositionFromPoint( _
            w, textData, targetX, targetY, targetVirtualSpace _
        )
    End If

    If extendSelection <> 0 Then
        textbox_ExtendSelectionAt _
            textData, targetPosition, targetVirtualSpace
    Else
        textbox_CollapseSelectionAt _
            textData, targetPosition, targetVirtualSpace
    End If

End Sub


Private Function textbox_LineForPosition(ByVal textValue As String, ByVal position As Integer) As Integer

    Dim lineIndex As Integer

    position = textbox_ClampPosition(textValue, position)

    For i As Integer = 0 To position - 1
        If textValue[i] = TEXTBOX_LINE_FEED Then
            lineIndex += 1
        Elseif textValue[i] = TEXTBOX_CARRIAGE_RETURN Then
            lineIndex += 1

            If i + 1 < position AndAlso textValue[i + 1] = TEXTBOX_LINE_FEED Then
                i += 1
            End If
        End If
    Next i

    Return lineIndex

End Function


Private Function textbox_GetLeadingIndent( _
    ByVal textValue As String, ByVal position As Integer _
) As String
    Dim As Integer lineStart = textbox_LineStart(textValue, position)
    Dim As Integer lineEnd = textbox_LineEnd(textValue, position)
    Dim As String indentText
    For charPosition As Integer = lineStart To lineEnd - 1
        If textValue[charPosition] = 32 OrElse textValue[charPosition] = 9 Then
            indentText &= Chr(textValue[charPosition])
        Else
            Exit For
        End If
    Next charPosition
    Return indentText
End Function


Private Sub textbox_EnsureCursorVisible(ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr)

    Dim cursorColumnWidth As Integer
    Dim cursorLine As Integer
    Dim cursorLineEnd As Integer
    Dim cursorLineStart As Integer
    Dim cursorBoundsFound As Integer
    Dim visibleWidth As Integer
    Dim visibleLines As Integer

    If w = 0 OrElse textData = 0 Then Exit Sub
    Dim ByRef displayText As String = textbox_VisualText(textData)

    textData->cursor_pos = textbox_ClampPosition(displayText, textData->cursor_pos)
    textData->sel_start = textbox_ClampPosition(displayText, textData->sel_start)
    textData->sel_end = textbox_ClampPosition(displayText, textData->sel_end)
    textData->selection_anchor = textbox_ClampPosition( _
        displayText, textData->selection_anchor _
    )

    textbox_UpdateScrollMetrics w, textData
    visibleWidth = textbox_ContentWidth(w, textData)
    cursorLine = textbox_VisualLineAtPosition( _
        displayText, textData->cursor_pos, _
        textData->wordwrap, visibleWidth, cursorLineStart, cursorLineEnd, _
        cursorBoundsFound, textData _
    )
    visibleLines = textbox_VisibleLineCount(w, textData)

    Dim As Integer previousScroll = textData->v_scroll
    If textData->v_scroll < 0 Then textData->v_scroll = 0
    If cursorLine < textData->v_scroll Then textData->v_scroll = cursorLine
    If cursorLine >= textData->v_scroll + visibleLines Then textData->v_scroll = cursorLine - visibleLines + 1
    ' The first measurement already synchronized the bars. Revisit it only
    ' after moving the viewport, or for unmanaged visibility callbacks whose
    ' external layout state cannot be proved unchanged within this GUI call.
    If textData->v_scroll <> previousScroll OrElse _
       (textData->line_visibility_handler <> 0 AndAlso _
        textData->metrics_state_handler = 0) Then
        textbox_UpdateScrollMetrics w, textData
        cursorBoundsFound = 0
    End If

    If textData->wordwrap <> 0 Then
        textData->scroll_offset = 0
        Exit Sub
    End If

    If cursorBoundsFound = 0 Then
        If textbox_VisualLineBounds( _
            displayText, cursorLine, textData->wordwrap, visibleWidth, _
            cursorLineStart, cursorLineEnd, textData _
        ) = 0 Then
            cursorLineStart = textbox_LineStart( _
                displayText, textData->cursor_pos _
            )
        End If
    End If
    cursorColumnWidth = textbox_TextWidth(textData, _
        Mid( _
            displayText, cursorLineStart + 1, _
            textData->cursor_pos - cursorLineStart _
        ) _
    )
    Dim As Integer cursorVirtual = textbox_ClampVirtualSpace( _
        textData, textData->cursor_pos, textData->cursor_virtual_space _
    )
    If cursorVirtual > 0 Then
        Dim As Integer spaceWidth = textbox_TextWidth(textData, " ")
        If spaceWidth < 1 Then spaceWidth = 1
        cursorColumnWidth += cursorVirtual * spaceWidth
    End If
    If visibleWidth < TEXTBOX_CURSOR_VISIBLE_WIDTH Then _
        visibleWidth = TEXTBOX_CURSOR_VISIBLE_WIDTH

    If textData->scroll_offset < 0 OrElse _
       cursorColumnWidth < textData->scroll_offset Then
        textData->scroll_offset = cursorColumnWidth
    Elseif cursorColumnWidth + TEXTBOX_CURSOR_VISIBLE_WIDTH > _
           textData->scroll_offset + visibleWidth Then
        textData->scroll_offset = cursorColumnWidth + _
            TEXTBOX_CURSOR_VISIBLE_WIDTH - visibleWidth
    End If
    If textData->horizontal_scrollbar <> 0 AndAlso _
       textData->horizontal_scrollbar->data <> 0 Then
        Cast( _
            ScrollBarData Ptr, textData->horizontal_scrollbar->data _
        )->value = textData->scroll_offset
    End If

End Sub


Private Sub textbox_RenderIndicators( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr, _
    ByVal lineStart As Integer, ByRef displayLine As Const String, _
    ByVal drawX As Integer, ByVal drawY As Integer _
)
    If textData->text_indicator_handler = 0 Then Exit Sub
    Dim As String sourceLine = Mid( _
        textData->text, lineStart + 1, Len(displayLine) _
    )
    Dim As Integer bytePosition, columnWidth, groupWidth, groupStartX
    Dim As Integer groupAlpha, groupStyle
    Dim As ULong groupColor
    While bytePosition < Len(sourceLine)
        Dim As Integer characterLength = _
            textbox_UTF8LengthAt(sourceLine, bytePosition)
        If characterLength < 1 Then Exit While
        Dim As Integer characterWidth = textbox_TextWidth( _
            textData, Mid(displayLine, bytePosition + 1, characterLength) _
        )
        Dim As Integer active = 0
        Dim As Integer currentAlpha = 255
        Dim As Integer currentStyle = TEXTBOX_INDICATOR_STYLE_BOX
        Dim As ULong currentColor
        For sourceByte As Integer = 0 To characterLength - 1
            If textData->text_indicator_handler( _
                w, lineStart + bytePosition + sourceByte, currentColor, _
                currentAlpha, currentStyle _
            ) <> 0 Then
                active = -1
                Exit For
            End If
        Next sourceByte
        If currentAlpha < 0 Then currentAlpha = 0
        If currentAlpha > 255 Then currentAlpha = 255
        If currentStyle <> TEXTBOX_INDICATOR_STYLE_FILL Then _
            currentStyle = TEXTBOX_INDICATOR_STYLE_BOX

        If active <> 0 Then
            If groupWidth > 0 AndAlso currentColor = groupColor AndAlso _
               currentAlpha = groupAlpha AndAlso _
               currentStyle = groupStyle Then
                groupWidth += characterWidth
            Else
                If groupWidth > 0 Then _
                    backend_RectEx groupStartX, drawY, groupWidth, _
                        textbox_LineHeight(textData), groupColor, _
                        IIf(groupStyle = TEXTBOX_INDICATOR_STYLE_FILL, 1, 0), _
                        1, groupAlpha
                groupStartX = drawX + columnWidth
                groupWidth = characterWidth
                groupColor = currentColor
                groupAlpha = currentAlpha
                groupStyle = currentStyle
            End If
        ElseIf groupWidth > 0 Then
            backend_RectEx groupStartX, drawY, groupWidth, _
                textbox_LineHeight(textData), groupColor, _
                IIf(groupStyle = TEXTBOX_INDICATOR_STYLE_FILL, 1, 0), _
                1, groupAlpha
            groupWidth = 0
        End If
        columnWidth += characterWidth
        bytePosition += characterLength
    Wend
    If groupWidth > 0 Then _
        backend_RectEx groupStartX, drawY, groupWidth, _
            textbox_LineHeight(textData), groupColor, _
            IIf(groupStyle = TEXTBOX_INDICATOR_STYLE_FILL, 1, 0), _
            1, groupAlpha
End Sub


Private Sub textbox_RenderCallbackLine( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr, _
    ByVal lineStart As Integer, ByRef displayLine As Const String, _
    ByVal drawX As Integer, ByVal drawY As Integer, _
    ByVal defaultColor As ULong, ByVal drawVisible As Integer _
)
    Dim As String sourceLine = Mid( _
        textData->text, lineStart + 1, Len(displayLine) _
    )
    Dim As Integer position
    While position < Len(displayLine)
        Dim As Integer glyphBytes = textbox_UTF8LengthAt(displayLine, position)
        If glyphBytes < 1 Then Exit While
        Dim As ULong glyphColor = defaultColor
        Dim As ULong glyphBackground = TEXTBOX_TEXT_STYLE_BACKGROUND_DEFAULT
        Dim As Integer glyphStyle = textData->text_style
        For byteIndex As Integer = position To position + glyphBytes - 1
            If textData->text_color_handler <> 0 Then
                Dim As ULong callbackColor = textData->text_color_handler( _
                    sourceLine, byteIndex, textData->render_color_state _
                )
                If byteIndex = position Then glyphColor = callbackColor
            End If
            If textData->text_style_handler <> 0 Then
                Dim As TextBoxCharacterStyle characterStyle
                characterStyle.foreground = glyphColor
                characterStyle.background = _
                    TEXTBOX_TEXT_STYLE_BACKGROUND_DEFAULT
                characterStyle.flags = glyphStyle
                If textData->text_style_handler( _
                    sourceLine, byteIndex, textData->render_style_state, _
                    characterStyle _
                ) <> 0 AndAlso byteIndex = position Then
                    glyphColor = characterStyle.foreground
                    glyphBackground = characterStyle.background
                    glyphStyle = characterStyle.flags
                End If
            End If
        Next byteIndex

        ' Hidden rows above the viewport only advance callback state. Their
        ' glyph widths and drawing coordinates are not used by any caller.
        If drawVisible = 0 Then
            position += glyphBytes
            Continue While
        End If

        Dim As String glyphText = Mid( _
            displayLine, position + 1, glyphBytes _
        )
        Dim As Integer glyphWidth = textbox_TextWidth(textData, glyphText)
        If drawVisible <> 0 Then
            Dim As Integer sourcePosition = lineStart + position
            Dim As Integer selected = IIf( _
                sourcePosition >= textData->sel_start AndAlso _
                sourcePosition < textData->sel_end, -1, 0 _
            )
            If textData->hide_selection_on_blur <> 0 AndAlso _
               w->has_focus = 0 Then selected = 0
            If selected <> 0 Then
                If glyphWidth > 0 Then backend_Rect drawX, drawY, _
                    glyphWidth, textbox_LineHeight(textData), _
                    current_theme.bg_select, 1
                glyphColor = current_theme.text_select
            ElseIf glyphBackground <> _
                   TEXTBOX_TEXT_STYLE_BACKGROUND_DEFAULT Then
                If glyphWidth > 0 Then backend_Rect drawX, drawY, _
                    glyphWidth, textbox_LineHeight(textData), _
                    glyphBackground, 1
            End If
            textbox_PrintStyled textData, drawX, drawY, glyphColor, _
                glyphText, glyphStyle
        End If
        drawX += glyphWidth
        position += glyphBytes
    Wend
End Sub


' fblint: disable-next-line FBL111 -- One line pass owns UTF-8 decoding, style and clipped glyph drawing.
Private Sub textbox_RenderLine( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr, _
    ByVal lineIndex As Integer, _
    ByVal lineStart As Integer, _
    ByVal lineText As String _
)

    Dim drawX As Integer
    Dim drawY As Integer
    Dim postText As String
    Dim prefixText As String
    Dim selectedEnd As Integer
    Dim selectedStart As Integer
    Dim selectedText As String
    Dim selectedWidth As Integer
    Dim selectedX As Integer
    Dim textColor As ULong
    Dim indentColumns As Integer
    Dim guideColumn As Integer
    Dim guideX As Integer
    Dim spaceWidth As Integer

    If w = 0 OrElse textData = 0 Then Exit Sub
    Dim As Integer drawVisible = IIf( _
        lineIndex >= textData->v_scroll, -1, 0 _
    )
    textColor = current_theme.text_main
    If textData->foreground_color_override <> 0 Then _
        textColor = textData->foreground_color
    If textData->surface_text_color <> TEXTBOX_WIDGET_COLOR_DEFAULT Then _
        textColor = textData->surface_text_color

    drawY = w->ay + textbox_TextPadding(textData) + _
        (lineIndex - textData->v_scroll) * textbox_LineHeight(textData)
    ' Compact single-line controls may be shorter than the multiline row
    ' reservation. Their existing client clip limits glyphs to the interior.
    If textData->multiline <> 0 AndAlso _
       drawY > w->ay + w->h - _
           textbox_ScaledPadding(textData, TEXTBOX_TEXT_BOTTOM_PADDING) Then _
        drawVisible = 0

    drawX = w->ax + textbox_TextPadding(textData) + _
        textbox_TotalGutterWidth(textData)
    If textData->wordwrap = 0 Then drawX -= textData->scroll_offset

    Dim As Integer clipX, clipY, clipWidth, clipHeight
    backend_GetClip clipX, clipY, clipWidth, clipHeight
    If drawY >= clipY + clipHeight OrElse _
       drawY + textbox_LineHeight(textData) <= clipY Then drawVisible = 0

    If drawVisible = 0 Then
        If textData->text_color_handler <> 0 OrElse _
           textData->text_style_handler <> 0 Then
            textbox_RenderCallbackLine w, textData, lineStart, lineText, _
                drawX, drawY, textColor, 0
        End If
        Exit Sub
    End If

    If textData->current_line_highlight AndAlso _
       textData->cursor_pos >= lineStart AndAlso _
       textData->cursor_pos <= lineStart + Len(lineText) Then
        Dim As Integer highlight_width = textbox_ContentWidth(w, textData)
        If highlight_width > 0 Then backend_Rect _
            w->ax + 2 + textbox_TotalGutterWidth(textData), drawY, _
            highlight_width, textbox_LineHeight(textData), _
            textData->current_line_background_color, 1
    End If
    If textData->line_range_highlight Then
        Dim As Integer source_line = textbox_LineForPosition(textData->text, lineStart)
        If source_line >= textData->line_range_highlight_first AndAlso _
           source_line <= textData->line_range_highlight_last Then
            Dim As Integer highlight_width = textbox_ContentWidth(w, textData)
            If highlight_width > 0 Then backend_Rect _
                w->ax + 2 + textbox_TotalGutterWidth(textData), drawY, _
                highlight_width, textbox_LineHeight(textData), current_theme.bg_select, 1
        End If
    End If

    textbox_RenderIndicators w, textData, lineStart, lineText, drawX, drawY

    /'
        Guides follow source indentation. The text itself is still drawn from
        the stored bytes, so tab stops and selection positions stay unchanged.
    '/
    If textData->indent_guides_enabled <> 0 AndAlso _
       textData->indent_width > 0 Then
        indentColumns = 0
        For indentPosition As Integer = 0 To Len(lineText) - 1
            Select Case lineText[indentPosition]
            Case 32
                indentColumns += 1
            Case 9
                indentColumns += textData->indent_width - _
                    (indentColumns Mod textData->indent_width)
            Case Else
                Exit For
            End Select
        Next indentPosition

        If indentColumns > 0 Then
            spaceWidth = textbox_TextWidth(textData, " ")
            If spaceWidth < 1 Then spaceWidth = 1
            guideColumn = textData->indent_width
            While guideColumn <= indentColumns
                guideX = w->ax + textbox_TextPadding(textData) + _
                    textbox_TotalGutterWidth(textData) + guideColumn * spaceWidth
                If textData->wordwrap = 0 Then _
                    guideX -= textData->scroll_offset
                backend_Line guideX, drawY, guideX, _
                    drawY + textbox_LineHeight(textData) - 1, _
                    textData->indent_guides_color
                guideColumn += textData->indent_width
            Wend
        End If
    End If

    Dim As Integer visualEnd = lineStart + Len(lineText)
    If textData->virtual_space_enabled <> 0 AndAlso _
       textData->wordwrap = 0 AndAlso _
       textbox_LineEnd(textData->text, visualEnd) = visualEnd AndAlso _
       textData->sel_end = visualEnd AndAlso _
       textData->sel_end_virtual_space > 0 AndAlso _
       (textData->hide_selection_on_blur = 0 OrElse w->has_focus <> 0) Then
        Dim As Integer virtualStart
        If textData->sel_start = visualEnd Then _
            virtualStart = textData->sel_start_virtual_space
        Dim As Integer virtualEnd = textData->sel_end_virtual_space
        If virtualStart < 0 Then virtualStart = 0
        If virtualEnd > TEXTBOX_MAX_VIRTUAL_SPACE Then _
            virtualEnd = TEXTBOX_MAX_VIRTUAL_SPACE
        If virtualEnd > virtualStart Then
            Dim As Integer spaceWidth = textbox_TextWidth(textData, " ")
            If spaceWidth < 1 Then spaceWidth = 1
            Dim As Integer virtualX = drawX + _
                textbox_TextWidth(textData, lineText) + _
                virtualStart * spaceWidth
            backend_Rect virtualX, drawY, _
                (virtualEnd - virtualStart) * spaceWidth, _
                textbox_LineHeight(textData), current_theme.bg_select, 1
        End If
    End If

    If textData->text_color_handler <> 0 OrElse _
       textData->text_style_handler <> 0 Then
        textbox_RenderCallbackLine w, textData, lineStart, lineText, _
            drawX, drawY, textColor, -1
        Exit Sub
    End If

    selectedStart = textData->sel_start
    selectedEnd = textData->sel_end
    If textData->hide_selection_on_blur AndAlso w->has_focus = 0 Then selectedEnd = selectedStart
    If selectedEnd < selectedStart Then Swap selectedStart, selectedEnd
    If selectedStart < lineStart Then selectedStart = lineStart
    If selectedEnd > lineStart + Len(lineText) Then _
        selectedEnd = lineStart + Len(lineText)

    If selectedEnd <= selectedStart Then
        If textbox_IsMasked(textData) = 0 AndAlso _
           textData->syntax_mode = TEXTBOX_SYNTAX_FREEBASIC Then
            textbox_RenderSyntaxLine _
                w, textData, drawX, drawY, lineStart, lineText, _
                textColor, selectedStart, selectedEnd
        Else
            textbox_PrintStyled textData, drawX, drawY, textColor, _
                lineText, textData->text_style
        End If
        Exit Sub
    End If

    If textbox_IsMasked(textData) = 0 AndAlso _
       textData->syntax_mode = TEXTBOX_SYNTAX_FREEBASIC Then
        textbox_RenderSyntaxLine _
            w, textData, drawX, drawY, lineStart, lineText, _
            textColor, selectedStart, selectedEnd
        Exit Sub
    End If

    prefixText = Left(lineText, selectedStart - lineStart)
    selectedText = Mid( _
        lineText, selectedStart - lineStart + 1, _
        selectedEnd - selectedStart _
    )
    postText = Mid(lineText, selectedEnd - lineStart + 1)
    selectedX = drawX + textbox_TextWidth(textData, prefixText)
    selectedWidth = textbox_TextWidth(textData, selectedText)

    textbox_PrintStyled textData, drawX, drawY, textColor, _
        prefixText, textData->text_style

    If selectedWidth > 0 Then
        backend_Rect selectedX, drawY, selectedWidth, _
            textbox_LineHeight(textData), current_theme.bg_select, 1
    End If

    textbox_PrintStyled textData, selectedX, drawY, current_theme.text_select, _
        selectedText, textData->text_style
    textbox_PrintStyled textData, selectedX + selectedWidth, drawY, _
        textColor, postText, textData->text_style

End Sub


Private Sub textbox_RenderLineNumber( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr, _
    ByVal visualLine As Integer, ByVal logicalLine As Integer, _
    ByVal lineStart As Integer _
)
    Dim As Integer drawX
    Dim As Integer drawY
    Dim As Integer numberRight
    Dim As String numberText

    If w = 0 OrElse textData = 0 OrElse _
       textbox_TotalGutterWidth(textData) <= 0 Then Exit Sub
    If visualLine < textData->v_scroll Then Exit Sub

    drawY = w->ay + textbox_TextPadding(textData) + _
        (visualLine - textData->v_scroll) * textbox_LineHeight(textData)
    If drawY > w->ay + w->h - _
        textbox_ScaledPadding(textData, TEXTBOX_TEXT_BOTTOM_PADDING) Then Exit Sub

    If textData->line_number_gutter_width > 0 AndAlso _
       textData->line_numbers_visible <> 0 Then
    numberText = LTrim(Str(logicalLine))
    numberRight = w->ax + 2 + _
        textData->line_number_gutter_width - _
        TEXTBOX_LINE_NUMBER_PADDING - _
        TEXTBOX_LINE_NUMBER_SEPARATOR_WIDTH
    drawX = numberRight - textbox_TextWidth(textData, numberText)
    Dim As Integer number_style
    If (textData->line_number_text_style_flags And TEXTBOX_TEXT_STYLE_BOLD) Then _
        number_style Or= BACKEND_TEXT_STYLE_BOLD
    If (textData->line_number_text_style_flags And TEXTBOX_TEXT_STYLE_UNDERLINE) Then _
        number_style Or= BACKEND_TEXT_STYLE_UNDERLINE
    If (textData->line_number_text_style_flags And TEXTBOX_TEXT_STYLE_ITALIC) Then _
        number_style Or= BACKEND_TEXT_STYLE_ITALIC
    textbox_PrintStyled textData, drawX, drawY, _
        textData->line_number_text_color, numberText, number_style
    End If

    If textData->line_number_gutter_width > 0 Then
        Dim As Integer markerVisible
        Dim As ULong markerForeground, markerBackground
        If textData->gutter_marker_style_handler <> 0 Then
            markerVisible = textData->gutter_marker_style_handler( _
                w, logicalLine - 1, lineStart, _
                markerForeground, markerBackground _
            )
        ElseIf textData->gutter_marker_handler <> 0 Then
            markerForeground = textData->gutter_marker_handler( _
                w, logicalLine - 1, lineStart _
            )
            markerBackground = markerForeground
            markerVisible = IIf(markerForeground <> 0, -1, 0)
        End If
        If markerVisible <> 0 Then
            Dim As Integer markerRadius = _
                (3 * textbox_FontPercent(textData) + 50) \ 100
            If markerRadius < 2 Then markerRadius = 2
            backend_Circle w->ax + 10, _
                drawY + textbox_LineHeight(textData) \ 2, _
                markerRadius, markerBackground, -1
            backend_Circle w->ax + 10, _
                drawY + textbox_LineHeight(textData) \ 2, _
                markerRadius, markerForeground, 0
        End If
    End If

    If textData->fold_gutter_width > 0 AndAlso _
       textData->fold_marker_handler <> 0 Then
        Dim As Integer foldState = textData->fold_marker_handler( _
            w, logicalLine - 1, lineStart _
        )
        If foldState <> 0 Then
            Dim As Integer foldX = w->ax + 2 + _
                textData->line_number_gutter_width + _
                textData->fold_gutter_width \ 2
            Dim As Integer foldY = drawY + textbox_LineHeight(textData) \ 2
            backend_Rect foldX - 4, foldY - 4, 9, 9, _
                textData->fold_symbol_background_color, 1
            backend_Rect foldX - 4, foldY - 4, 9, 9, _
                textData->fold_symbol_foreground_color, 0
            backend_Line foldX - 2, foldY, foldX + 2, foldY, _
                textData->fold_symbol_foreground_color
            If foldState < 0 Then _
                backend_Line foldX, foldY - 2, foldX, foldY + 2, _
                    textData->fold_symbol_foreground_color
        End If
    End If
End Sub


Private Sub textbox_HandleDeletionInput( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr _
)

    Dim position As Integer

    If textData = 0 OrElse textData->read_only <> 0 Then Exit Sub

    If textbox_KeyJustPressed(textData, KEY_BACKSPACE, TEXTBOX_KEY_LATCH_BACKSPACE) <> 0 Then
        If textbox_HasSelectionData(textData) <> 0 Then
            textbox_BeginEdit w, TEXTBOX_HISTORY_GROUP_BACKSPACE
            textbox_DeleteSelection textData
        Else
            position = textbox_ClampCharacterPosition(textData->text, textData->cursor_pos)

            If textData->cursor_virtual_space > 0 Then
                textbox_CollapseSelectionAt textData, position, _
                    textData->cursor_virtual_space - 1
            ElseIf position > 0 Then
                textbox_BeginEdit w, TEXTBOX_HISTORY_GROUP_BACKSPACE
                Dim As Integer previousPosition = _
                    textbox_PreviousCharacterPosition(textData->text, position)
                textData->text = Left(textData->text, previousPosition) & _
                    Mid(textData->text, position + 1)
                textData->change_serial += 1
                textbox_CollapseSelection textData, previousPosition
            End If
        End If
    Elseif textbox_KeyJustPressed(textData, KEY_DELETE, TEXTBOX_KEY_LATCH_DELETE) <> 0 Then
        If textbox_HasSelectionData(textData) <> 0 Then
            textbox_BeginEdit w, TEXTBOX_HISTORY_GROUP_DELETE
            textbox_DeleteSelection textData
        Else
            position = textbox_ClampCharacterPosition(textData->text, textData->cursor_pos)

            If textData->cursor_virtual_space = 0 AndAlso _
               position < Len(textData->text) Then
                textbox_BeginEdit w, TEXTBOX_HISTORY_GROUP_DELETE
                Dim As Integer nextPosition = _
                    textbox_NextCharacterPosition(textData->text, position)
                textData->text = Left(textData->text, position) & _
                    Mid(textData->text, nextPosition + 1)
                textData->change_serial += 1
                textbox_CollapseSelection textData, position
            End If
        End If
    End If

End Sub


' A callback may close its editor's owning window. Check the registration ID
' before ordinary input handling touches the borrowed widget again.
Private Function textbox_CallbackTargetGone( _
    ByVal w As Widget Ptr, ByVal registryId As ULongInt _
) As Integer
    If w = 0 Then Return -1
    If registryId = 0 Then Return 0
    If gui_IsWidgetRegistered(w) = 0 Then Return -1
    Return IIf(w->registry_id <> registryId, -1, 0)
End Function


Private Function textbox_NavigationOverride( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr, _
    ByVal keyCode As Integer _
) As Integer
    If textData->navigation_handler = 0 Then Return 0
    Dim As ULongInt registryId = w->registry_id
    Dim As Integer handled = textData->navigation_handler(w, keyCode)
    If textbox_CallbackTargetGone(w, registryId) Then Return -1
    Return handled
End Function


Private Function textbox_ControlOverride( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr, _
    ByVal keyCode As Integer _
) As Integer
    If textData->control_shortcut_handler = 0 Then Return 0
    Dim As ULongInt registryId = w->registry_id
    Dim As Integer handled = textData->control_shortcut_handler(w, keyCode)
    If textbox_CallbackTargetGone(w, registryId) Then Return -1
    Return handled
End Function


Private Sub textbox_HandleNavigationInput( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr _
)

    Dim extendSelection As Integer

    If textData = 0 Then Exit Sub
    extendSelection = textbox_ShiftPressed()

    If textbox_KeyJustPressed(textData, KEY_RETURN, TEXTBOX_KEY_LATCH_RETURN) <> 0 Then
        If textbox_NavigationOverride(w, textData, KEY_RETURN) Then Exit Sub
        If textData->multiline <> 0 Then
            If textData->read_only = 0 Then
                Dim As String returnText = Chr(TEXTBOX_LINE_FEED)
                If textData->auto_indent Then _
                    returnText &= textbox_GetLeadingIndent(textData->text, textData->cursor_pos)
                If textbox_ConstrainInput(textData, returnText) Then
                    textbox_BeginEdit w, TEXTBOX_HISTORY_GROUP_RETURN
                    textbox_InsertText textData, returnText
                End If
            End If
        Else
            textData->active = 0
        End If
    Elseif textbox_KeyJustPressed(textData, KEY_LEFT, TEXTBOX_KEY_LATCH_LEFT) <> 0 Then
        If textbox_NavigationOverride(w, textData, KEY_LEFT) Then Exit Sub
        textbox_EndEditGroup w
        If extendSelection <> 0 Then
            If textData->cursor_virtual_space > 0 Then
                textbox_ExtendSelectionAt textData, textData->cursor_pos, _
                    textData->cursor_virtual_space - 1
            Else
                textbox_ExtendSelection textData, _
                    textbox_PreviousCharacterPosition( _
                        textData->text, textData->cursor_pos _
                    )
            End If
        ElseIf textbox_HasSelectionData(textData) <> 0 Then
            textbox_CollapseSelectionAt textData, textData->sel_start, _
                textData->sel_start_virtual_space
        ElseIf textData->cursor_virtual_space > 0 Then
            textbox_CollapseSelectionAt textData, textData->cursor_pos, _
                textData->cursor_virtual_space - 1
        Else
            textbox_CollapseSelection textData, _
                textbox_PreviousCharacterPosition(textData->text, textData->cursor_pos)
        End If
    Elseif textbox_KeyJustPressed(textData, KEY_RIGHT, TEXTBOX_KEY_LATCH_RIGHT) <> 0 Then
        If textbox_NavigationOverride(w, textData, KEY_RIGHT) Then Exit Sub
        textbox_EndEditGroup w
        If extendSelection <> 0 Then
            If textData->virtual_space_enabled <> 0 AndAlso _
               textData->wordwrap = 0 AndAlso _
               textData->cursor_pos = textbox_LineEnd( _
                   textData->text, textData->cursor_pos _
               ) Then
                textbox_ExtendSelectionAt textData, textData->cursor_pos, _
                    textData->cursor_virtual_space + 1
            Else
                textbox_ExtendSelection textData, _
                    textbox_NextCharacterPosition( _
                        textData->text, textData->cursor_pos _
                    )
            End If
        ElseIf textbox_HasSelectionData(textData) <> 0 Then
            textbox_CollapseSelectionAt textData, textData->sel_end, _
                textData->sel_end_virtual_space
        ElseIf textData->virtual_space_enabled <> 0 AndAlso _
               textData->wordwrap = 0 AndAlso _
               textData->cursor_pos = textbox_LineEnd( _
                   textData->text, textData->cursor_pos _
               ) Then
            textbox_CollapseSelectionAt textData, textData->cursor_pos, _
                textData->cursor_virtual_space + 1
        Else
            textbox_CollapseSelection textData, _
                textbox_NextCharacterPosition(textData->text, textData->cursor_pos)
        End If
    Elseif textbox_KeyJustPressed(textData, KEY_HOME, TEXTBOX_KEY_LATCH_HOME) <> 0 Then
        If textbox_NavigationOverride(w, textData, KEY_HOME) Then Exit Sub
        textbox_EndEditGroup w
        If extendSelection <> 0 Then
            textbox_ExtendSelection textData, _
                textbox_LineStart(textbox_VisualText(textData), textData->cursor_pos)
        Else
            textbox_CollapseSelection textData, _
                textbox_LineStart(textbox_VisualText(textData), textData->cursor_pos)
        End If
    Elseif textbox_KeyJustPressed(textData, KEY_END, TEXTBOX_KEY_LATCH_END) <> 0 Then
        If textbox_NavigationOverride(w, textData, KEY_END) Then Exit Sub
        textbox_EndEditGroup w
        If extendSelection <> 0 Then
            textbox_ExtendSelection textData, _
                textbox_LineEnd(textbox_VisualText(textData), textData->cursor_pos)
        Else
            textbox_CollapseSelection textData, _
                textbox_LineEnd(textbox_VisualText(textData), textData->cursor_pos)
        End If
    Elseif textData->multiline <> 0 AndAlso textbox_KeyJustPressed(textData, KEY_UP, TEXTBOX_KEY_LATCH_UP) <> 0 Then
        If textbox_NavigationOverride(w, textData, KEY_UP) Then Exit Sub
        textbox_EndEditGroup w
        textbox_MoveCursorVertical w, textData, -1, extendSelection
    Elseif textData->multiline <> 0 AndAlso textbox_KeyJustPressed(textData, KEY_DOWN, TEXTBOX_KEY_LATCH_DOWN) <> 0 Then
        If textbox_NavigationOverride(w, textData, KEY_DOWN) Then Exit Sub
        textbox_EndEditGroup w
        textbox_MoveCursorVertical w, textData, 1, extendSelection
    End If

End Sub


' -------------------------------------------------------------------------
' Context menu callbacks
' -------------------------------------------------------------------------

Private Sub ctx_copy(ByVal idx As Integer)
    textbox_Copy active_textbox
End Sub


Private Sub ctx_cut(ByVal idx As Integer)
    textbox_Cut active_textbox
End Sub


Private Sub ctx_paste(ByVal idx As Integer)
    textbox_Paste active_textbox
End Sub


' -------------------------------------------------------------------------
' Mouse and control-key routing
' -------------------------------------------------------------------------

Private Sub textbox_HandleMouseInput( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr, _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer, _
    ByVal mouseButtons As Integer _
)

    Dim insideWidget As Integer
    Dim As Integer mouseVirtualSpace

    If w = 0 OrElse textData = 0 Then Exit Sub

    insideWidget = IIf( _
        mouseX >= w->ax AndAlso mouseX < w->ax + w->w AndAlso _
        mouseY >= w->ay AndAlso mouseY < w->ay + w->h, _
        1, 0 _
    )

    If (mouseButtons And 1) <> 0 Then
        If textData->mouse_latch = 0 Then
            textData->mouse_latch = 1
            textbox_EndEditGroup w

            If insideWidget <> 0 Then
                textData->active = 1
                active_textbox = w

                Dim As Integer gutterWidth = textbox_TotalGutterWidth(textData)
                If gutterWidth > 0 AndAlso _
                   mouseX < w->ax + 2 + gutterWidth AndAlso _
                   mouseY >= w->ay + textbox_TextPadding(textData) Then
                    Dim As Integer foldHit = IIf( _
                        textData->fold_gutter_width > 0 AndAlso _
                        mouseX >= w->ax + 2 + _
                            textData->line_number_gutter_width, -1, 0 _
                    )
                    If (foldHit <> 0 AndAlso _
                        textData->fold_click_handler <> 0) OrElse _
                       (foldHit = 0 AndAlso _
                        textData->gutter_click_handler <> 0) Then
                        Dim As Integer visualLine = textData->v_scroll + _
                            (mouseY - w->ay - _
                            textbox_TextPadding(textData)) \ _
                            textbox_LineHeight(textData)
                        Dim As Integer visualStart, visualEnd
                        Dim ByRef displayText As String = _
                            textbox_VisualText(textData)
                        If textbox_VisualLineBounds( _
                            displayText, visualLine, textData->wordwrap, _
                            textbox_ContentWidth(w, textData), _
                            visualStart, visualEnd, textData _
                        ) <> 0 Then
                            Dim As Integer sourceLine = textbox_LineForPosition( _
                                textData->text, visualStart _
                            )
                            Dim As Integer sourceStart = _
                                textbox_LineStartByIndex( _
                                    textData->text, sourceLine _
                                )
                            textData->mouse_selecting = 0
                            If foldHit <> 0 Then
                                textData->fold_click_handler( _
                                    w, sourceLine, sourceStart _
                                )
                            Else
                                textData->gutter_click_handler( _
                                    w, sourceLine, sourceStart _
                                )
                            End If
                            Exit Sub
                        End If
                    End If
                End If

                If textbox_ShiftPressed() <> 0 Then
                    Dim As Integer mousePosition = textbox_PositionFromPoint( _
                        w, textData, mouseX, mouseY, mouseVirtualSpace _
                    )
                    textbox_ExtendSelectionAt _
                        textData, mousePosition, mouseVirtualSpace
                Else
                    Dim As Integer mousePosition = textbox_PositionFromPoint( _
                        w, textData, mouseX, mouseY, mouseVirtualSpace _
                    )
                    textbox_CollapseSelectionAt _
                        textData, mousePosition, mouseVirtualSpace
                End If

                textData->mouse_selecting = 1
            Else
                textData->active = 0
                textData->mouse_selecting = 0
                If active_textbox = w Then active_textbox = 0
            End If
        Elseif textData->mouse_selecting <> 0 Then
            Dim As Integer mousePosition = textbox_PositionFromPoint( _
                w, textData, mouseX, mouseY, mouseVirtualSpace _
            )
            textbox_ExtendSelectionAt _
                textData, mousePosition, mouseVirtualSpace
        End If
    Else
        textData->mouse_latch = 0
        textData->mouse_selecting = 0
    End If

    If (mouseButtons And 2) = 0 Then
        textData->context_menu_latch = 0
        Exit Sub
    End If
    If insideWidget = 0 OrElse textData->context_menu_latch <> 0 Then Exit Sub
    textData->context_menu_latch = -1
    ' The ordinary menu offers Copy and Cut. Masked fields retain pointer
    ' selection above, but do not open this unrestricted editor menu.
    If textbox_IsMasked(textData) Then Exit Sub

    textData->active = 1
    active_textbox = w

    If textData->context_menu_handler <> 0 Then
        textData->context_menu_handler(w, mouseX, mouseY)
        Exit Sub
    End If

    If textbox_context_menu = 0 Then
        textbox_context_menu = menu_Create("tb_ctx", mouseX, mouseY)
        menu_AddItem textbox_context_menu, "Copy", @ctx_copy
        menu_AddItem textbox_context_menu, "Cut", @ctx_cut
        menu_AddItem textbox_context_menu, "Paste", @ctx_paste
        gui_AddWidget textbox_context_menu
    End If

    textbox_context_menu->x = mouseX
    textbox_context_menu->y = mouseY
    textbox_context_menu->visible = 1
    gui_BringToFront textbox_context_menu

End Sub


Private Function textbox_HandleTabInput( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr _
) As Integer
    Dim As Integer columnNumber
    Dim As Integer lineNumber
    Dim As Integer spaceCount

    If w = 0 OrElse textData = 0 Then Return 0
    If textData->accepts_tab = 0 OrElse textData->multiline = 0 OrElse _
       textData->read_only <> 0 Then Return 0
    If input_KeyPressEvent(FB.SC_TAB) = 0 Then Return 0
    If input_ModifiedKeyPressEvent( _
        FB.SC_TAB, INPUT_MODIFIER_CONTROL _
    ) <> 0 Then Return 0
    If input_ModifiedKeyPressEvent( _
        FB.SC_TAB, INPUT_MODIFIER_ALT _
    ) <> 0 Then Return 0
    If input_ModifiedKeyPressEvent( _
        FB.SC_TAB, INPUT_MODIFIER_SHIFT _
    ) <> 0 Then Return 0

    If textData->block_indent AndAlso textbox_HasSelection(w) Then
        ' A rejected oversized block edit must not fall back to replacing
        ' the selected source with spaces.
        textbox_IndentSelection w
        Return -1
    End If
    If textbox_GetLineColumn(w, lineNumber, columnNumber) = 0 Then Return 0
    Dim As Integer tabColumns = textData->indent_width
    If tabColumns < 1 Then tabColumns = TEXTBOX_TAB_COLUMNS
    spaceCount = tabColumns - ((columnNumber - 1) Mod tabColumns)
    Dim As String tabText = Space(spaceCount)
    If textData->indent_with_tabs Then tabText = Chr(9)
    If textbox_ConstrainInput(textData, tabText) = 0 Then Return -1
    If textbox_BeginEdit(w, TEXTBOX_HISTORY_GROUP_TAB) = 0 Then Return 0
    textbox_InsertText textData, tabText
    Return -1
End Function


Private Function textbox_HandleControlInput( _
    ByVal w As Widget Ptr, _
    ByVal textData As TextBoxData Ptr _
) As Integer

    If w = 0 OrElse textData = 0 Then Return 0

    If textData->block_indent Then
        If input_KeyPressed(FB.SC_ALT) = 0 AndAlso _
           input_ModifiedKeyPressEvent(FB.SC_RIGHTBRACKET, INPUT_MODIFIER_ALT) = 0 AndAlso _
           textbox_ControlShortcutJustPressed(textData, FB.SC_RIGHTBRACKET, TEXTBOX_KEY_LATCH_INDENT) Then
            textbox_IndentSelection w
            Return 1
        End If
        If input_KeyPressed(FB.SC_ALT) = 0 AndAlso _
           input_ModifiedKeyPressEvent(FB.SC_LEFTBRACKET, INPUT_MODIFIER_ALT) = 0 AndAlso _
           textbox_ControlShortcutJustPressed(textData, FB.SC_LEFTBRACKET, TEXTBOX_KEY_LATCH_UNINDENT) Then
            textbox_UnindentSelection w
            Return 1
        End If
    End If

    If textbox_ControlShortcutJustPressed( _
        textData, FB.SC_Z, TEXTBOX_KEY_LATCH_UNDO _
    ) <> 0 Then
        If textbox_ControlOverride(w, textData, FB.SC_Z) Then Return 1
        textbox_EndEditGroup w
        textbox_Undo w
        textbox_EnsureCursorVisible w, textData
        Return 1
    End If

    If textbox_ControlShortcutJustPressed( _
        textData, FB.SC_Y, TEXTBOX_KEY_LATCH_REDO _
    ) <> 0 Then
        If textbox_ControlOverride(w, textData, FB.SC_Y) Then Return 1
        textbox_EndEditGroup w
        textbox_Redo w
        textbox_EnsureCursorVisible w, textData
        Return 1
    End If

    If textbox_ControlShortcutJustPressed( _
        textData, FB.SC_A, TEXTBOX_KEY_LATCH_SELECT_ALL _
    ) <> 0 Then
        If textbox_ControlOverride(w, textData, FB.SC_A) Then Return 1
        textbox_EndEditGroup w
        textData->selection_anchor = 0
        textbox_ExtendSelection textData, Len(textData->text)
        textbox_EnsureCursorVisible w, textData
        Return 1
    End If

    If textbox_ControlShortcutJustPressed( _
        textData, FB.SC_C, TEXTBOX_KEY_LATCH_COPY _
    ) <> 0 Then
        If textbox_ControlOverride(w, textData, FB.SC_C) Then Return 1
        textbox_EndEditGroup w
        ctx_copy 0
        textbox_EnsureCursorVisible w, textData
        Return 1
    End If

    If textbox_ControlShortcutJustPressed( _
        textData, FB.SC_X, TEXTBOX_KEY_LATCH_CUT _
    ) <> 0 Then
        If textbox_ControlOverride(w, textData, FB.SC_X) Then Return 1
        textbox_EndEditGroup w
        ctx_cut 0
        textbox_EnsureCursorVisible w, textData
        Return 1
    End If

    If textbox_ControlShortcutJustPressed( _
        textData, FB.SC_V, TEXTBOX_KEY_LATCH_PASTE _
    ) <> 0 Then
        If textbox_ControlOverride(w, textData, FB.SC_V) Then Return 1
        textbox_EndEditGroup w
        ctx_paste 0
        textbox_EnsureCursorVisible w, textData
        Return 1
    End If

End Function


' Ordered shortcuts run before control commands and text input. The caller
' can consume an event without altering the stored editor text.
Private Function textbox_HandleKeyEventInput( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr _
) As Integer
    If w = 0 OrElse textData = 0 OrElse _
       textData->key_event_handler = 0 Then Return 0
    Dim As ULongInt registryId = w->registry_id

    For eventIndex As Integer = 0 To input_KeyEventCount() - 1
        Dim As Integer keyCode, modifierFlags
        If input_KeyEvent(eventIndex, keyCode, modifierFlags) = 0 Then _
            Continue For
        Dim As Integer handled = textData->key_event_handler( _
            w, keyCode, modifierFlags _
        )
        If textbox_CallbackTargetGone(w, registryId) Then Return -1
        If handled <> 0 Then Return -1
    Next eventIndex
    Return 0
End Function


' The source KeyDown handler runs before standard editor commands so its
' remapped scan code or cancellation applies to this same input frame.
Private Function textbox_DispatchKeyDown( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr, _
    ByVal registryId As ULongInt _
) As Integer
    If w = 0 OrElse textData = 0 Then Return 0
    If textbox_key_down_dispatch_depth <> 0 Then Return 0
    If w->has_focus = 0 OrElse textData->key_down_handler = 0 Then Return -1

    Dim As Long event_count = input_KeyEventCount()
    For event_index As Long = 0 To event_count - 1
        Dim As InputKeyEvent ordered_event
        If input_ReadKeyEvent(event_index, ordered_event) = 0 Then Continue For
        If ordered_event.event_kind <> INPUT_KEY_EVENT_PRESS AndAlso _
           ordered_event.event_kind <> INPUT_KEY_EVENT_REPEAT Then Continue For
        Dim As Integer callback_key = ordered_event.scan_code
        Dim As Integer callback_modifiers = ordered_event.modifiers
        textbox_key_down_dispatch_depth += 1
        Cast(Sub(ByVal As Widget Ptr, ByRef As Integer, ByRef As Integer), _
            textData->key_down_handler)(w, callback_key, callback_modifiers)
        textbox_key_down_dispatch_depth -= 1
        If textbox_CallbackTargetGone(w, registryId) OrElse _
           w->has_focus = 0 Then Return 0
        If input_SetKeyEventMapping( _
            ordered_event.scan_code, callback_key _
        ) = 0 Then Return 0
    Next event_index
    Return -1
End Function


' -------------------------------------------------------------------------
' Public widget API
' -------------------------------------------------------------------------

Function textbox_GetText(ByVal w As Widget Ptr) As String
    If w = 0 OrElse w->destroy <> @textbox_Destroy OrElse _
       w->data = 0 Then Return ""
    Return Cast(TextBoxData Ptr, w->data)->text
End Function


Function textbox_GetPasswordChar(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->destroy <> @textbox_Destroy OrElse _
       w->data = 0 Then Return 0
    Return textbox_MaskCharacter(Cast(TextBoxData Ptr, w->data))
End Function


Function textbox_SetPlaceholder( _
    ByVal w As Widget Ptr, ByRef placeholder_text As Const String _
) As Integer
    Dim As TextBoxData Ptr text_data

    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @textbox_Destroy Then Return 0
    If Len(placeholder_text) > TEXTBOX_PLACEHOLDER_MAX_LENGTH Then Return 0
    text_data = Cast(TextBoxData Ptr, w->data)
    text_data->placeholder_text = placeholder_text
    Return -1
End Function

Function textbox_GetPlaceholder(ByVal w As Widget Ptr) As String
    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @textbox_Destroy Then Return ""
    Return Cast(TextBoxData Ptr, w->data)->placeholder_text
End Function

' FB-LINTER: DISABLE-NEXT-LINE FBL008 FBL-SEC-004 REASON: This public API name identifies a display-mask control.
Function textbox_SetPasswordChar( _
    ByVal w As Widget Ptr, ByVal character_code As Integer _
) As Integer
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->destroy <> @textbox_Destroy OrElse _
       w->data = 0 Then Return 0
    ' Zero disables masking. Exclude whitespace and control bytes which would
    ' leave no visible glyph or introduce another visual line in the mask.
    If character_code <> 0 AndAlso _
       (character_code < 33 OrElse character_code > 126) Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    If character_code <> 0 AndAlso textData->multiline <> 0 Then Return 0
    If textbox_MaskCharacter(textData) = character_code Then Return -1

    If textbox_IsMasked(textData) = 0 Then
        ' FB-LINTER: DISABLE-NEXT-LINE FBL008 FBL-SEC-004 REASON: The field retains the prior wrapping setting for mask mode.
        textData->password_saved_wordwrap = textData->wordwrap
    End If
    ' FB-LINTER: DISABLE-NEXT-LINE FBL008 FBL-SEC-004 REASON: The field stores a display glyph selector only.
    textData->password_character = character_code
    ' FB-LINTER: DISABLE-NEXT-LINE FBL008 FBL-SEC-004 REASON: Clearing this cache leaves source text unchanged.
    textData->password_display = ""
    If character_code = 0 Then
        ' FB-LINTER: DISABLE-NEXT-LINE FBL008 FBL-SEC-004 REASON: Restore the wrap setting saved when mask mode began.
        textData->wordwrap = textData->password_saved_wordwrap
    Else
        textData->wordwrap = 0
    End If
    ' Keep editor contents, selection, and undo transactions. Only visual
    ' state changes; a new glyph can have a different width in the same font.
    textData->scroll_offset = 0
    textData->v_scroll = 0
    textData->viewport_dirty = -1
    textbox_EnsureCursorVisible w, textData
    If active_textbox = w AndAlso textbox_context_menu <> 0 Then
        textbox_context_menu->visible = 0
    End If
    Return -1
End Function


Function textbox_SelectAll(ByVal w As Widget Ptr) As Integer
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    textbox_EndEditGroup w
    textData->selection_anchor = 0
    textbox_ExtendSelection textData, Len(textData->text)
    textbox_EnsureCursorVisible w, textData
    Return -1
End Function


Function textbox_HasSelection(ByVal w As Widget Ptr) As Integer
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 OrElse w->enabled = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    Return textbox_HasSelectionData(textData)
End Function


Function textbox_GetCursorPosition(ByVal w As Widget Ptr) As Integer
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    If textData->cursor_pos < 0 Then Return 0
    If textData->cursor_pos > Len(textData->text) Then Return Len(textData->text)
    Return textData->cursor_pos
End Function


Function textbox_SetCursorPosition( _
    ByVal w As Widget Ptr, _
    ByVal cursor_position As Integer, _
    ByVal extend_selection As Integer _
) As Integer
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 OrElse w->enabled = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    cursor_position = textbox_ClampPosition(textData->text, cursor_position)
    textbox_EndEditGroup w
    If extend_selection Then
        textbox_ExtendSelection textData, cursor_position
    Else
        textbox_CollapseSelection textData, cursor_position
    End If
    textbox_EnsureCursorVisible w, textData
    Return -1
End Function


Function textbox_GetSelectionStart(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Return 0
    Dim As TextBoxData Ptr textData = w->data
    Dim As Integer start_position = textData->sel_start
    If textData->sel_end < start_position Then start_position = textData->sel_end
    Return textbox_ClampPosition(textData->text, start_position)
End Function

Function textbox_SetSelectionRange(ByVal w As Widget Ptr, _
    ByVal start_position As Integer, ByVal selection_length As Integer) As Integer
    ' Range updates are atomic and programmatic, including disabled controls.
    ' Clamp before adding, so callers cannot overflow the end position.
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Return 0
    If start_position < 0 OrElse selection_length < 0 Then Return 0
    Dim As TextBoxData Ptr textData = w->data
    start_position = textbox_ClampPosition(textData->text, start_position)
    If selection_length > Len(textData->text) - start_position Then selection_length = Len(textData->text) - start_position
    textbox_EndEditGroup w
    textbox_CollapseSelection textData, start_position
    textbox_ExtendSelection textData, start_position + selection_length
    textbox_EnsureCursorVisible w, textData
    Return -1
End Function

Function textbox_SetHideSelection(ByVal w As Widget Ptr, ByVal hide_selection As Integer) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Return 0
    Cast(TextBoxData Ptr, w->data)->hide_selection_on_blur = IIf(hide_selection, -1, 0)
    Return -1
End Function

Function textbox_GetHideSelection(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Return 0
    Return IIf(Cast(TextBoxData Ptr, w->data)->hide_selection_on_blur, -1, 0)
End Function

Function textbox_GetSelectionLength(ByVal w As Widget Ptr) As Integer
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    Return Len(textbox_SelectedText(textData))
End Function


Function textbox_GotoLine( _
    ByVal w As Widget Ptr, _
    ByVal line_number As Integer, _
    ByVal column_number As Integer _
) As Integer
    Dim As Integer character_index
    Dim As Integer current_line
    Dim As Integer line_end
    Dim As Integer line_start
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 OrElse w->enabled = 0 Then Return 0
    If line_number < 1 OrElse column_number < 1 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    current_line = 1
    line_start = 0
    character_index = 1
    While character_index <= Len(textData->text) AndAlso _
          current_line < line_number
        If Asc(Mid(textData->text, character_index, 1)) = 13 Then
            current_line += 1
            character_index += 1
            If character_index <= Len(textData->text) AndAlso _
               Asc(Mid(textData->text, character_index, 1)) = 10 Then _
                character_index += 1
            line_start = character_index - 1
        ElseIf Asc(Mid(textData->text, character_index, 1)) = 10 Then
            current_line += 1
            character_index += 1
            line_start = character_index - 1
        Else
            character_index += 1
        End If
    Wend
    If current_line <> line_number Then Return 0

    line_end = line_start
    While line_end < Len(textData->text)
        If textData->text[line_end] = 13 OrElse _
           textData->text[line_end] = 10 Then Exit While
        line_end += 1
    Wend
    character_index = line_start + column_number - 1
    If character_index > line_end Then character_index = line_end
    Return textbox_SetCursorPosition(w, character_index, 0)
End Function


Function textbox_GetSelectedText(ByVal w As Widget Ptr) As String
    If w = 0 OrElse w->data = 0 Then Return ""
    Return textbox_SelectedText(Cast(TextBoxData Ptr, w->data))
End Function


Function textbox_GetLineColumn( _
    ByVal w As Widget Ptr, _
    ByRef line_number As Integer, _
    ByRef column_number As Integer _
) As Integer
    Dim As Integer character_index
    Dim As Integer character_value
    Dim As Integer cursor_position
    Dim As TextBoxData Ptr textData

    line_number = 0
    column_number = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    cursor_position = textbox_GetCursorPosition(w)
    line_number = 1
    column_number = 1
    character_index = 1
    While character_index <= cursor_position
        character_value = Asc(Mid(textData->text, character_index, 1))
        If character_value = 13 Then
            line_number += 1
            column_number = 1
            If character_index < cursor_position AndAlso _
               Asc(Mid(textData->text, character_index + 1, 1)) = 10 Then _
                character_index += 1
        ElseIf character_value = 10 Then
            line_number += 1
            column_number = 1
        Else
            column_number += 1
        End If
        character_index += 1
    Wend
    Return -1
End Function


Function textbox_FindText( _
    ByVal w As Widget Ptr, _
    ByVal search_text As String, _
    ByVal start_position As Integer, _
    ByVal match_case As Integer, _
    ByVal wrap_search As Integer _
) As Integer
    Dim As Integer found_position
    Dim As String haystack
    Dim As String needle
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 OrElse w->enabled = 0 Then Return -1
    If Len(search_text) = 0 Then Return -1
    textData = Cast(TextBoxData Ptr, w->data)
    If start_position < 0 Then start_position = 0
    If start_position > Len(textData->text) Then _
        start_position = Len(textData->text)
    If match_case Then
        haystack = textData->text
        needle = search_text
    Else
        haystack = LCase(textData->text)
        needle = LCase(search_text)
    End If

    found_position = InStr(start_position + 1, haystack, needle) - 1
    If found_position < 0 AndAlso wrap_search <> 0 AndAlso _
       start_position > 0 Then found_position = InStr(haystack, needle) - 1
    If found_position < 0 Then Return -1

    textbox_EndEditGroup w
    textData->selection_anchor = found_position
    textData->sel_start = found_position
    textData->sel_end = found_position + Len(search_text)
    textData->cursor_pos = textData->sel_end
    textbox_EnsureCursorVisible w, textData
    Return found_position
End Function


Function textbox_InsertAtSelection(ByVal w As Widget Ptr, _
    ByRef replacement_text As Const String) As Integer
    ' Unlike ReplaceSelection, an empty range inserts at the caret. Preserve
    ' the older command's no-selection result for existing editor callers.
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Return 0
    Dim As TextBoxData Ptr textData = w->data
    If textData->read_only Then Return 0
    Dim As String acceptedText = replacement_text
    If Len(acceptedText) > 0 AndAlso textbox_ConstrainInput(textData, acceptedText) = 0 Then Return 0
    Dim As LongInt result_length = textbox_InsertionResultLength( _
        textData, Len(acceptedText) _
    )
    If result_length < 0 OrElse result_length > TEXTBOX_HISTORY_MAX_STORED_BYTES Then Return 0
    If textbox_BeginEdit(w, TEXTBOX_HISTORY_GROUP_NONE) = 0 Then Return 0
    textbox_DeleteSelection textData
    textbox_InsertText textData, acceptedText
    textbox_EnsureCursorVisible w, textData
    Return -1
End Function

Function textbox_ReplaceSelection( _
    ByVal w As Widget Ptr, _
    ByVal replacement_text As String _
) As Integer
    Dim As Integer selection_present
    Dim As LongInt result_length
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 OrElse w->enabled = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    If textData->read_only <> 0 Then Return 0
    selection_present = textbox_HasSelectionData(textData)
    If selection_present = 0 Then Return 0
    If Len(replacement_text) > 0 AndAlso textbox_ConstrainInput(textData, replacement_text) = 0 Then Return 0
    result_length = textbox_InsertionResultLength( _
        textData, Len(replacement_text) _
    )
    If result_length > TEXTBOX_HISTORY_MAX_STORED_BYTES Then Return 0
    If textbox_BeginEdit(w, TEXTBOX_HISTORY_GROUP_NONE) = 0 Then Return 0
    textbox_DeleteSelection textData
    textbox_InsertText textData, replacement_text
    textbox_EnsureCursorVisible w, textData
    Return -1
End Function


Private Function textbox_CopyTextRange( _
    ByRef destination_text As String, _
    ByVal destination_position As Integer, _
    ByRef source_text As Const String, _
    ByVal source_position As Integer, _
    ByVal copy_length As Integer _
) As Integer
    If copy_length < 0 OrElse destination_position < 1 OrElse _
       source_position < 1 Then Return 0
    If copy_length = 0 Then Return -1
    If destination_position > Len(destination_text) OrElse _
       copy_length > Len(destination_text) - destination_position + 1 Then _
        Return 0
    If source_position > Len(source_text) OrElse _
       copy_length > Len(source_text) - source_position + 1 Then Return 0

    For byte_offset As Integer = 0 To copy_length - 1
        destination_text[destination_position - 1 + byte_offset] = _
            source_text[source_position - 1 + byte_offset]
    Next byte_offset
    Return -1
End Function


Function textbox_ReplaceAll( _
    ByVal w As Widget Ptr, _
    ByVal search_text As String, _
    ByVal replacement_text As String, _
    ByVal match_case As Integer _
) As Integer
    Dim As Integer copied_length
    Dim As Integer destination_position
    Dim As Integer found_position
    Dim As Integer match_count
    Dim As Integer search_position
    Dim As Integer source_position
    Dim As LongInt result_length
    Dim As String haystack
    Dim As String needle
    Dim As String result_text
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 OrElse w->enabled = 0 Then Return 0
    If Len(search_text) = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    If textData->read_only <> 0 Then Return 0
    If match_case Then
        haystack = textData->text
        needle = search_text
    Else
        haystack = LCase(textData->text)
        needle = LCase(search_text)
    End If

    result_length = Len(textData->text)
    search_position = 1
    Do
        found_position = InStr(search_position, haystack, needle)
        If found_position = 0 Then Exit Do
        match_count += 1
        result_length += Len(replacement_text) - Len(search_text)
        If result_length < 0 OrElse _
           result_length > TEXTBOX_HISTORY_MAX_STORED_BYTES Then Return 0
        search_position = found_position + Len(search_text)
    Loop
    If match_count = 0 Then Return 0
    ' Bulk commands stay atomic. Do not truncate their suffix or stop halfway
    ' through a document. Shrinking pre-existing oversized text remains useful.
    If textData->input_limit > 0 AndAlso result_length > textData->input_limit AndAlso _
       result_length > Len(textData->text) Then Return 0
    If textbox_BeginEdit(w, TEXTBOX_HISTORY_GROUP_NONE) = 0 Then Return 0

    result_text = Space(CInt(result_length))
    source_position = 1
    destination_position = 1
    search_position = 1
    Do
        found_position = InStr(search_position, haystack, needle)
        If found_position = 0 Then Exit Do
        copied_length = found_position - source_position
        If copied_length > 0 Then
            If textbox_CopyTextRange( _
                result_text, destination_position, _
                textData->text, source_position, copied_length _
            ) = 0 Then Return 0
            destination_position += copied_length
        End If
        If Len(replacement_text) > 0 Then
            If textbox_CopyTextRange( _
                result_text, destination_position, replacement_text, 1, _
                Len(replacement_text) _
            ) = 0 Then Return 0
            destination_position += Len(replacement_text)
        End If
        source_position = found_position + Len(search_text)
        search_position = source_position
    Loop
    copied_length = Len(textData->text) - source_position + 1
    If copied_length > 0 Then
        If textbox_CopyTextRange( _
            result_text, destination_position, _
            textData->text, source_position, copied_length _
        ) = 0 Then Return 0
    End If

    textData->text = result_text
    textData->change_serial += 1
    textbox_CollapseSelection textData, Len(result_text)
    textbox_EnsureCursorVisible w, textData
    Return match_count
End Function


Function textbox_Copy(ByVal w As Widget Ptr) As Integer
    Dim As String selectedText
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    If textbox_IsMasked(textData) Then Return 0
    selectedText = textbox_SelectedText(textData)
    If Len(selectedText) = 0 Then Return 0
    clipboard_SetText selectedText
    Return -1
End Function


Function textbox_Cut(ByVal w As Widget Ptr) As Integer
    Dim As String selectedText
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 OrElse w->enabled = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    If textbox_IsMasked(textData) Then Return 0
    If textData->read_only <> 0 Then Return 0
    selectedText = textbox_SelectedText(textData)
    If Len(selectedText) = 0 Then Return 0
    If textbox_BeginEdit(w, TEXTBOX_HISTORY_GROUP_NONE) = 0 Then Return 0
    clipboard_SetText selectedText
    textbox_DeleteSelection textData
    textbox_EnsureCursorVisible w, textData
    Return -1
End Function


Function textbox_Paste(ByVal w As Widget Ptr) As Integer
    Dim As String pastedText
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 OrElse w->enabled = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    If textData->read_only <> 0 Then Return 0
    pastedText = clipboard_GetText()
    If Len(pastedText) = 0 Then Return 0
    If textbox_ConstrainInput(textData, pastedText) = 0 Then Return 0
    If textbox_BeginEdit(w, TEXTBOX_HISTORY_GROUP_NONE) = 0 Then Return 0
    textbox_InsertText textData, pastedText
    textbox_EnsureCursorVisible w, textData
    Return -1
End Function

Function textbox_Create( _
    ByVal nm As String, ByVal txt As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, _
    ByVal m As Integer, ByVal ww As Integer, _
    ByVal scrollbarMode As Integer _
) As Widget Ptr

    Dim wgt As Widget Ptr
    Dim textData As TextBoxData Ptr

    wgt = New Widget
    If wgt = 0 Then Return 0

    textData = New TextBoxData
    If textData = 0 Then
        Delete wgt
        Return 0
    End If

    textData->metrics_valid = 0
    textData->metrics_key = ""
    textData->metrics_cache_callbacks = 0
    textData->metrics_state_handler = 0
    textData->metrics_row_count = 0
    textData->metrics_row_source_length = 0
    textData->metrics_row_visibility_key = ""
    textData->metrics_row_visibility_handler = 0
    textData->metrics_row_state_handler = 0

    wgt->name = nm
    wgt->x = x
    wgt->y = y
    wgt->w = w
    wgt->h = h
    wgt->visible = 1
    wgt->enabled = 1
    wgt->accepts_focus = -1
    wgt->captures_return = IIf(m <> 0, -1, 0)
    wgt->render = @textbox_Render
    wgt->update = @textbox_Update
    wgt->destroy = @textbox_Destroy

    textData->text = txt
    textData->owner = wgt
    textData->active = 0
    textData->multiline = m
    textData->wordwrap = ww
    textData->read_only = 0
    textData->input_limit = 0
    textData->max_text_bytes = 0
    textData->text_style = BACKEND_TEXT_STYLE_NORMAL
    textData->font_id = BACKEND_FONT_DEFAULT
    textData->font_scale_percent = 100
    textData->zoom_percent = 100
    textData->extra_line_spacing = 0
    textData->accepts_tab = 0
    textData->block_indent = 0
    textData->line_numbers = 0
    textData->line_number_gutter_width = 0
    textData->fold_gutter_width = 0
    textData->fold_margin_background_color = current_theme.bg_face
    textData->fold_symbol_foreground_color = current_theme.text_main
    textData->fold_symbol_background_color = current_theme.bg_face
    textData->observed_has_focus = 0
    textData->cursor_pos = Len(txt)
    textData->sel_start = textData->cursor_pos
    textData->sel_end = textData->cursor_pos
    textData->selection_anchor = textData->cursor_pos
    textData->scroll_offset = 0
    textData->v_scroll = 0
    textData->key_latch = 0
    textData->mouse_latch = 0
    textData->mouse_selecting = 0
    textData->scrollbar_dragging = 0
    textData->horizontal_scrollbar_dragging = 0
    textData->scrollbar_mode = scrollbarMode
    textData->scrollbar_visible = 0
    textData->horizontal_scrollbar_mode = TEXTBOX_SCROLLBAR_NONE
    textData->horizontal_scrollbar_visible = 0
    textData->total_visual_lines = 1
    textData->viewport_dirty = -1
    textData->observed_text_length = Len(txt)
    textData->observed_cursor_pos = textData->cursor_pos
    textData->background_color_override = 0
    textData->foreground_color_override = 0
    textData->background_color = 0
    textData->foreground_color = 0
    textData->caret_color = TEXTBOX_WIDGET_COLOR_DEFAULT
    textData->caret_visible = -1
    textData->surface_border_color = TEXTBOX_WIDGET_COLOR_DEFAULT
    textData->surface_background_color = TEXTBOX_WIDGET_COLOR_DEFAULT
    textData->surface_text_color = TEXTBOX_WIDGET_COLOR_DEFAULT
    textData->border_style = TEXTBOX_BORDER_SINGLE
    textData->line_range_highlight_first = -1
    textData->line_range_highlight_last = -1
    textData->line_numbers_visible = -1
    textData->line_number_text_color = current_theme.classic_disabled_text
    textData->line_number_background_color = TEXTBOX_WIDGET_COLOR_DEFAULT
    textData->indent_width = TEXTBOX_TAB_COLUMNS
    textData->syntax_mode = TEXTBOX_SYNTAX_NONE
    textData->syntax_color_overrides = 0
    textData->syntax_keyword_color = current_theme.syntax_keyword_color
    textData->syntax_comment_color = current_theme.syntax_comment_color
    textData->syntax_string_color = current_theme.syntax_string_color
    textData->syntax_number_color = current_theme.syntax_number_color
    textData->syntax_preprocessor_color = current_theme.syntax_preprocessor_color
    textData->syntax_type_color = current_theme.syntax_type_color
    textData->syntax_command_color = current_theme.syntax_command_color
    textData->syntax_procedure_color = current_theme.syntax_procedure_color
    textData->syntax_macro_color = current_theme.syntax_macro_color
    textData->syntax_variable_color = current_theme.syntax_variable_color
    textData->syntax_constant_color = current_theme.syntax_constant_color
    textData->syntax_member_color = current_theme.syntax_member_color
    textData->syntax_label_color = current_theme.syntax_label_color
    textData->syntax_object_color = current_theme.syntax_object_color
    textData->key_down_handler = 0
    textData->key_press_handler = 0
    textData->key_up_handler = 0
    textData->vertical_scrollbar = scrollbar_Create( _
        nm & "_vertical_scrollbar", 0, 0, _
        TEXTBOX_SCROLLBAR_WIDTH, h, 0, 1, -1 _
    )
    If textData->vertical_scrollbar = 0 Then
        Delete textData
        Delete wgt
        Return 0
    End If

    textData->horizontal_scrollbar = scrollbar_Create( _
        nm & "_horizontal_scrollbar", 0, 0, _
        w, TEXTBOX_SCROLLBAR_WIDTH, 0, 1, 0 _
    )
    If textData->horizontal_scrollbar = 0 Then
        If textData->vertical_scrollbar->destroy <> 0 Then _
            textData->vertical_scrollbar->destroy( _
                textData->vertical_scrollbar _
            )
        Delete textData->vertical_scrollbar
        Delete textData
        Delete wgt
        Return 0
    End If

    textData->undoCount = 0
    textData->redoCount = 0
    textData->historyStoredBytes = 0
    textData->historyGroup = TEXTBOX_HISTORY_GROUP_NONE
    textData->historyIdleFrames = 0
    wgt->data = textData

    Return wgt

End Function


' One fixed-width field list owns the process-local MKLongInt header.
' Stack fields avoid temporary strings on idle comparisons. Keep pointer
' values widened through the native unsigned width, as the original key does.
Private Type Textbox_RenderFields
    As LongInt values(0 To 69)
End Type
#assert SizeOf(Textbox_RenderFields) = 70 * SizeOf(LongInt)
Private Sub textbox_RenderFillFields(ByVal d As TextBoxData Ptr, ByRef fields As Textbox_RenderFields)
    fields.values(0) = d->active
    fields.values(1) = d->multiline
    fields.values(2) = d->wordwrap
    fields.values(3) = d->scroll_offset
    fields.values(4) = d->v_scroll
    fields.values(5) = d->line_number_gutter_width
    fields.values(6) = d->scrollbar_visible
    fields.values(7) = d->horizontal_scrollbar_visible
    fields.values(8) = d->background_color_override
    fields.values(9) = d->foreground_color_override
    fields.values(10) = d->background_color
    fields.values(11) = d->foreground_color
    fields.values(12) = d->syntax_mode
    fields.values(13) = d->syntax_color_overrides
    fields.values(14) = d->syntax_keyword_color
    fields.values(15) = d->syntax_comment_color
    fields.values(16) = d->syntax_string_color
    fields.values(17) = d->syntax_number_color
    fields.values(18) = d->syntax_preprocessor_color
    fields.values(19) = d->syntax_type_color
    fields.values(20) = d->syntax_command_color
    fields.values(21) = d->syntax_procedure_color
    fields.values(22) = d->syntax_macro_color
    fields.values(23) = d->syntax_variable_color
    fields.values(24) = d->syntax_constant_color
    fields.values(25) = d->syntax_member_color
    fields.values(26) = d->syntax_label_color
    fields.values(27) = d->syntax_object_color
    fields.values(28) = d->password_character ' FB-LINTER: DISABLE-LINE FBL008 FBL-SEC-004 REASON: Render identity tracks changes to mask mode.
    fields.values(29) = d->hide_selection_on_blur
    fields.values(30) = d->text_style
    fields.values(31) = d->cue_banner_color
    fields.values(32) = d->caret_color
    fields.values(33) = d->surface_border_color
    fields.values(34) = d->surface_background_color
    fields.values(35) = d->surface_text_color
    fields.values(36) = d->current_line_highlight
    fields.values(37) = d->current_line_background_color
    fields.values(38) = d->line_range_highlight
    fields.values(39) = d->line_range_highlight_first
    fields.values(40) = d->line_range_highlight_last
    fields.values(41) = d->line_numbers_visible
    fields.values(42) = d->line_number_text_style_flags
    fields.values(43) = d->line_number_text_color
    fields.values(44) = d->line_number_background_color
    fields.values(45) = d->indent_guides_enabled
    fields.values(46) = d->indent_width
    fields.values(47) = d->virtual_space_enabled
    fields.values(48) = d->indent_guides_color
    fields.values(49) = d->right_edge_column
    fields.values(50) = d->right_edge_color
    fields.values(51) = d->fold_gutter_width
    fields.values(52) = d->fold_margin_background_color
    fields.values(53) = d->fold_symbol_foreground_color
    fields.values(54) = d->fold_symbol_background_color
    fields.values(55) = d->font_id
    fields.values(56) = d->font_scale_percent
    fields.values(57) = d->zoom_percent
    fields.values(58) = d->extra_line_spacing
    fields.values(59) = d->caret_visible
    fields.values(60) = CLngInt(CUInt(d->text_display_handler))
    fields.values(61) = CLngInt(CUInt(d->text_color_handler))
    fields.values(62) = CLngInt(CUInt(d->text_style_handler))
    fields.values(63) = CLngInt(CUInt(d->text_indicator_handler))
    fields.values(64) = CLngInt(CUInt(d->gutter_marker_handler))
    fields.values(65) = CLngInt(CUInt(d->gutter_marker_style_handler))
    fields.values(66) = CLngInt(CUInt(d->fold_marker_handler))
    fields.values(67) = CLngInt(CUInt(d->line_visibility_handler))
    fields.values(68) = CLngInt(CUInt(d->render_state_handler))
    fields.values(69) = d->border_style
End Sub

Private Function textbox_RenderObservationHeader(ByVal w As Widget Ptr) As String
    If w = 0 OrElse w->data = 0 Then Return ""
    Dim As TextBoxData Ptr d = w->data
    Dim As Textbox_RenderFields fields
    textbox_RenderFillFields d, fields
    Dim As String result = String(SizeOf(fields), 0)
    If Len(result) <> SizeOf(fields) Then
        gui_InvalidateAll
        Return ""
    End If
    ' MKLongInt retains native byte order. The explicit 8-byte fields avoid
    ' structure padding and preserve the key consumed by row-damage handlers.
    memcpy StrPtr(result), @fields.values(0), SizeOf(fields)
    Return result & MKLongInt(Len(d->cue_banner_text)) & d->cue_banner_text
End Function

Private Function textbox_RenderObservationMovement(ByVal d As TextBoxData Ptr) As String
    Dim As String result
    ' The length locates the movement fields without parsing the source text.
    result &= MKLongInt(Len(d->text))
    ' The final six 8-byte fields describe caret and selection movement.
    ' An opted-in row damage handler compares the exact stable prefix first.
    result &= MKLongInt(d->cursor_pos)
    result &= MKLongInt(d->sel_start)
    result &= MKLongInt(d->sel_end)
    result &= MKLongInt(d->cursor_virtual_space)
    result &= MKLongInt(d->sel_start_virtual_space)
    result &= MKLongInt(d->sel_end_virtual_space)
    result &= Chr(IIf(d->active <> 0 AndAlso d->caret_visible <> 0 AndAlso _
        gui_CaretBlinkVisible(Timer) <> 0, 1, 0))
    Return result
End Function

Function textbox_GetRenderObservation(ByVal w As Widget Ptr) As String
    If w = 0 OrElse w->data = 0 Then Return ""
    Dim As TextBoxData Ptr d = w->data
    ' Keep exact source bytes in changed observations, including legacy writes
    ' which did not advance change_serial. The matcher borrows them on idle frames.
    Return textbox_RenderObservationHeader(w) & MKLongInt(Len(d->text)) & _
        d->text & textbox_RenderObservationMovement(d)
End Function

Function textbox_RenderObservationMatches(ByVal w As Widget Ptr, _
    ByRef previousKey As Const String, ByVal observationOffset As Integer) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    If observationOffset < 0 OrElse observationOffset > Len(previousKey) Then Return 0
    Dim As TextBoxData Ptr d = w->data
    Dim As Textbox_RenderFields fields
    Const suffixBytes As Integer = 65
    ' fblint: disable-next-line FBL310 -- this private type is declared above and compiled here.
    Const fixedHeaderBytes As Integer = SizeOf(Textbox_RenderFields) + 8
    Dim As Integer available = Len(previousKey) - observationOffset
    If available < fixedHeaderBytes + suffixBytes Then Return 0
    available -= fixedHeaderBytes + suffixBytes
    ' Subtract bounded lengths before adding offsets. A malformed key must
    ' decline reuse before any byte read, including a negative or huge offset.
    If Len(d->cue_banner_text) > available Then Return 0
    available -= Len(d->cue_banner_text)
    If Len(d->text) <> available Then Return 0
    textbox_RenderFillFields d, fields
    Dim As Const UByte Ptr retainedBytes = StrPtr(previousKey) + observationOffset
    If oma_BytesEqual(retainedBytes, @fields.values(0), SizeOf(fields)) = 0 Then Return 0
    retainedBytes += SizeOf(fields)
    Dim As LongInt cueLength = Len(d->cue_banner_text)
    If oma_BytesEqual(retainedBytes, @cueLength, 8) = 0 Then Return 0
    retainedBytes += 8
    If oma_BytesEqual(retainedBytes, StrPtr(d->cue_banner_text), Len(d->cue_banner_text)) = 0 Then Return 0
    retainedBytes += Len(d->cue_banner_text)
    Dim As LongInt sourceLength = Len(d->text)
    If oma_BytesEqual(retainedBytes, @sourceLength, 8) = 0 Then Return 0
    retainedBytes += 8
    ' Read exact source bytes so same-length legacy writes still invalidate.
    If oma_BytesEqual(retainedBytes, StrPtr(d->text), Len(d->text)) = 0 Then Return 0
    retainedBytes += Len(d->text)
    Dim As LongInt movement(0 To 6)
    movement(0) = Len(d->text)
    movement(1) = d->cursor_pos
    movement(2) = d->sel_start
    movement(3) = d->sel_end
    movement(4) = d->cursor_virtual_space
    movement(5) = d->sel_start_virtual_space
    movement(6) = d->sel_end_virtual_space
    Const movementBytes As Integer = 7 * SizeOf(LongInt)
    If oma_BytesEqual(retainedBytes, @movement(0), movementBytes) = 0 Then Return 0
    Dim As UByte blink = IIf(d->active <> 0 AndAlso d->caret_visible <> 0 AndAlso _
        gui_CaretBlinkVisible(Timer) <> 0, 1, 0)
    Return IIf(retainedBytes[movementBytes] = blink, -1, 0)
End Function


Function textbox_GetRenderDamage(ByVal w As Widget Ptr, _
    ByRef previousKey As Const String, ByRef nextKey As Const String, _
    ByRef x As Integer, ByRef y As Integer, _
    ByRef widthValue As Integer, ByRef heightValue As Integer) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    ' The textbox observation ends with blink phase. Geometry, base-widget
    ' state and application observations precede it in the manager's key.
    ' A caret-only repaint is safe only when all those bytes still match.
    Dim As Integer keyLength = Len(previousKey)
    If keyLength < 1 OrElse Len(nextKey) <> keyLength Then Return 0
    ' Compare borrowed bytes directly instead of copying the source-sized prefix.
    If oma_BytesEqual(StrPtr(previousKey), StrPtr(nextKey), keyLength - 1) = 0 Then Return 0
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    x = d->rendered_caret_x: y = d->rendered_caret_y
    widthValue = d->rendered_caret_w: heightValue = d->rendered_caret_h
    Return IIf(widthValue > 0 AndAlso heightValue > 0, -1, 0)
End Function


Function textbox_GetCursorRowRenderDamage(ByVal w As Widget Ptr, _
    ByRef previousKey As Const String, ByRef nextKey As Const String, _
    ByRef x As Integer, ByRef y As Integer, _
    ByRef widthValue As Integer, ByRef heightValue As Integer) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    ' Six 8-byte movement fields and one blink byte terminate the observation.
    ' The caller must observe every callback-owned visual dependency before it
    ' opts into this handler. Default textboxes retain conservative repainting.
    Const MOVEMENT_BYTES As Integer = 49
    Dim As Integer keyLength = Len(previousKey)
    If keyLength < MOVEMENT_BYTES Then Return textbox_GetRenderDamage( _
        w, previousKey, nextKey, x, y, widthValue, heightValue)
    If Len(nextKey) <> keyLength Then Return 0
    If oma_BytesEqual(StrPtr(previousKey), StrPtr(nextKey), keyLength - MOVEMENT_BYTES) = 0 Then Return 0
    ' Compare the document prefix once. The small suffix then distinguishes
    ' blinking from movement without another complete source comparison.
    If oma_BytesEqual(StrPtr(previousKey) + keyLength - MOVEMENT_BYTES, _
        StrPtr(nextKey) + keyLength - MOVEMENT_BYTES, MOVEMENT_BYTES - 1) <> 0 Then
        x = d->rendered_caret_x
        y = d->rendered_caret_y
        widthValue = d->rendered_caret_w
        heightValue = d->rendered_caret_h
        If widthValue > 0 AndAlso heightValue > 0 Then Return -1
    End If
    If d->wordwrap <> 0 OrElse d->rendered_caret_h <= 0 Then Return 0
    Dim As Integer movementStart = keyLength - MOVEMENT_BYTES + 1
    Dim As LongInt oldCursor = CVLongInt(Mid(previousKey, movementStart, 8))
    Dim As LongInt oldSelectionStart = CVLongInt(Mid(previousKey, movementStart + 8, 8))
    Dim As LongInt oldSelectionEnd = CVLongInt(Mid(previousKey, movementStart + 16, 8))
    Dim As LongInt oldVirtualStart = CVLongInt(Mid(previousKey, movementStart + 32, 8))
    Dim As LongInt oldVirtualEnd = CVLongInt(Mid(previousKey, movementStart + 40, 8))
    If oldSelectionStart <> oldSelectionEnd OrElse oldVirtualStart <> oldVirtualEnd OrElse _
       d->sel_start <> d->sel_end OrElse d->sel_start_virtual_space <> d->sel_end_virtual_space Then Return 0
    If oldCursor < 0 OrElse oldCursor > Len(d->text) OrElse _
       d->cursor_pos < 0 OrElse d->cursor_pos > Len(d->text) Then Return 0
    If textbox_LineStart(d->text, CInt(oldCursor)) <> textbox_LineStart(d->text, d->cursor_pos) Then Return 0
    ' The old caret records the row's screen coordinate, including hidden rows.
    ' Replay the full row so the old caret, glyph overhang and line decorations
    ' are restored without measuring the document again to find the new caret.
    x = w->ax
    y = d->rendered_caret_y
    widthValue = w->w
    heightValue = d->rendered_caret_h
    Return IIf(widthValue > 0 AndAlso heightValue > 0, -1, 0)
End Function


Private Sub textbox_RenderFrame( _
    ByVal w As Widget Ptr, ByVal textData As TextBoxData Ptr, _
    ByVal backgroundColor As ULong, ByVal borderColor As ULong _
)
    If w = 0 OrElse textData = 0 Then Exit Sub
    If textData->border_style = TEXTBOX_BORDER_NONE Then
        backend_Rect w->ax, w->ay, w->w, w->h, backgroundColor, 1
    Else
        ' BorderStyle changes only the frame; the existing two-pixel content
        ' inset keeps caret and selection metrics stable across property writes.
        backend_Rect w->ax, w->ay, w->w, w->h, borderColor, 0
        backend_Rect w->ax + 1, w->ay + 1, w->w - 2, w->h - 2, _
            backgroundColor, 1
    End If
End Sub



' fblint: disable-next-line FBL111 -- Visible rows, caret and scrollbars share one frame layout state.
Sub textbox_Render(ByVal w As Widget Ptr)

    Dim textData As TextBoxData Ptr
    Dim lineText As String
    Dim lineStart As Integer
    Dim lineIndex As Integer
    Dim lineEnd As Integer
    Dim scanPosition As Integer
    Dim As Integer sourceLineNumber, sourceLineStart
    Dim As Integer rowLineNumber, rowLineStart
    Dim textClipHeight As Integer
    Dim textClipWidth As Integer
    Dim textClipX As Integer
    Dim contentWidth As Integer
    Dim cursorLine As Integer
    Dim cursorX As Integer
    Dim cursorY As Integer
    Dim cursorRecorded As Integer
    Dim backgroundColor As ULong
    Dim foregroundColor As ULong

    If w = 0 Then Exit Sub
    textData = Cast(TextBoxData Ptr, w->data)
    If textData = 0 Then Exit Sub
    Dim ByRef displayText As String = textbox_VisualText(textData)

    If w->has_focus = 0 Then
        textData->active = 0
        If active_textbox = w Then active_textbox = 0
    End If

    textbox_UpdateScrollMetrics w, textData

    backgroundColor = current_theme.bg_light
    foregroundColor = current_theme.text_main
    If textData->background_color_override <> 0 Then _
        backgroundColor = textData->background_color
    If textData->foreground_color_override <> 0 Then _
        foregroundColor = textData->foreground_color
    If textData->surface_background_color <> TEXTBOX_WIDGET_COLOR_DEFAULT Then _
        backgroundColor = textData->surface_background_color
    If textData->surface_text_color <> TEXTBOX_WIDGET_COLOR_DEFAULT Then _
        foregroundColor = textData->surface_text_color
    Dim As ULong borderColor = current_theme.bg_dark
    If textData->surface_border_color <> TEXTBOX_WIDGET_COLOR_DEFAULT Then _
        borderColor = textData->surface_border_color
    textbox_RenderFrame w, textData, backgroundColor, borderColor
    textClipWidth = w->w - 4
    If textData->scrollbar_visible <> 0 Then
        textClipWidth -= TEXTBOX_SCROLLBAR_WIDTH + TEXTBOX_SCROLLBAR_INSET
    End If
    If textClipWidth < 1 Then textClipWidth = 1
    textClipHeight = w->h - 4
    If textData->horizontal_scrollbar_visible <> 0 Then
        textClipHeight -= TEXTBOX_SCROLLBAR_WIDTH + TEXTBOX_SCROLLBAR_INSET
    End If
    If textClipHeight < 1 Then textClipHeight = 1
    backend_SetClip w->ax + 2, w->ay + 2, _
        textClipWidth, textClipHeight
    contentWidth = textbox_ContentWidth(w, textData)

    If textbox_TotalGutterWidth(textData) > 0 Then
        If textData->line_number_gutter_width > 0 AndAlso _
           textData->line_number_background_color <> TEXTBOX_WIDGET_COLOR_DEFAULT Then _
            backend_Rect w->ax + 2, w->ay + 2, _
                textData->line_number_gutter_width - 1, textClipHeight, _
                textData->line_number_background_color, 1
        If textData->fold_gutter_width > 0 Then _
            backend_Rect w->ax + 2 + textData->line_number_gutter_width, _
                w->ay + 2, textData->fold_gutter_width, textClipHeight, _
                textData->fold_margin_background_color, 1
        Dim As Integer separatorX = w->ax + 2 + _
            textbox_TotalGutterWidth(textData) - 1
        backend_Line separatorX, w->ay + 2, _
            separatorX, w->ay + textClipHeight + 1, _
            current_theme.bg_dark

        textbox_RestoreRenderRow textData, textData->v_scroll, _
            lineIndex, scanPosition, sourceLineNumber, sourceLineStart
        While textbox_NextVisibleVisualLine( _
            displayText, scanPosition, textData->wordwrap, _
            contentWidth, lineStart, lineEnd, textData, _
            sourceLineNumber, sourceLineStart, _
            rowLineNumber, rowLineStart _
        )
            If w->ay + textbox_TextPadding(textData) + _
               (lineIndex - textData->v_scroll) * textbox_LineHeight(textData) > _
               w->ay + textClipHeight Then Exit While
            If lineStart = rowLineStart Then
                textbox_RenderLineNumber _
                    w, textData, lineIndex, rowLineNumber + 1, rowLineStart
            End If
            lineIndex += 1
        Wend
    End If

    backend_ResetClip()
    textClipX = w->ax + 2 + textbox_TotalGutterWidth(textData)
    textClipWidth -= textbox_TotalGutterWidth(textData)
    If textClipWidth < 1 Then textClipWidth = 1
    backend_SetClip textClipX, w->ay + 2, textClipWidth, textClipHeight

    If Len(displayText) = 0 AndAlso textData->active = 0 AndAlso _
       Len(textData->placeholder_text) > 0 Then
        backend_Print textClipX + 2, w->ay + TEXTBOX_TEXT_LEFT_PADDING, _
            current_theme.classic_disabled_text, textData->placeholder_text
    End If

    textData->cursor_pos = textbox_ClampPosition(displayText, textData->cursor_pos)
    scanPosition = 0
    lineIndex = 0
    sourceLineNumber = 0
    sourceLineStart = 0
    textData->render_color_state = 0
    textData->render_style_state = 0

    Dim As Integer preparedState = 0
    Dim As Integer firstRenderRow = textData->v_scroll
    Dim As Integer lastRenderPixel
    If textData->render_state_handler <> 0 AndAlso textData->wordwrap = 0 Then
        Dim As Integer probePosition, probeStart, probeEnd, probeRow
        Dim As Integer probeSourceNumber, probeSourceStart, probeNumber, probeLogicalStart
        Dim As Integer clipX, clipY, clipWidth, clipHeight
        backend_GetClip clipX, clipY, clipWidth, clipHeight
        lastRenderPixel = clipY + clipHeight
        Dim As Integer lineHeight = textbox_LineHeight(textData)
        Dim As Integer skippedPixels = clipY - w->ay - textbox_TextPadding(textData)
        If skippedPixels > 0 AndAlso lineHeight > 0 Then firstRenderRow += skippedPixels \ lineHeight
        textbox_RestoreRenderRow textData, firstRenderRow, _
            probeRow, probePosition, probeSourceNumber, probeSourceStart
        While textbox_NextVisibleVisualLine( _
            displayText, probePosition, 0, contentWidth, probeStart, probeEnd, _
            textData, probeSourceNumber, probeSourceStart, probeNumber, probeLogicalStart _
        )
            If probeRow = firstRenderRow Then
                preparedState = textData->render_state_handler( _
                    w, probeStart, textData->render_color_state, _
                    textData->render_style_state _
                )
                Exit While
            End If
            probeRow += 1
        Wend
        ' A provider may decline a viewport; normal replay starts from zero.
        If preparedState = 0 Then
            textData->render_color_state = 0
            textData->render_style_state = 0
        Else
            ' The provider restored syntax state at this exact visible row.
            ' Resume the source walk there rather than allocating and visiting
            ' every earlier line again. Wrapped rows retain ordinary replay.
            scanPosition = probeStart
            lineIndex = probeRow
            sourceLineNumber = probeNumber
            sourceLineStart = probeLogicalStart
        End If
    End If

    While textbox_NextVisibleVisualLine( _
        displayText, scanPosition, textData->wordwrap, contentWidth, _
        lineStart, lineEnd, textData, _
        sourceLineNumber, sourceLineStart, rowLineNumber, rowLineStart _
    )
        ' Syntax callbacks need the rows before the viewport to establish
        ' multiline state. Rows below it cannot affect this frame, so avoid
        ' classifying and measuring the rest of the document on every redraw.
        If textData->multiline <> 0 AndAlso _
           w->ay + textbox_TextPadding(textData) + _
               (lineIndex - textData->v_scroll) * textbox_LineHeight(textData) > _
           w->ay + w->h - _
               textbox_ScaledPadding(textData, TEXTBOX_TEXT_BOTTOM_PADDING) Then _
            Exit While

        ' A checkpoint provider restores syntax before each repaint. Once the
        ' caret is located, rows below the paint clip need no further callbacks.
        ' Providers that decline restoration retain the complete viewport walk.
        If preparedState <> 0 AndAlso cursorRecorded <> 0 AndAlso _
           w->ay + textbox_TextPadding(textData) + _
               (lineIndex - textData->v_scroll) * textbox_LineHeight(textData) >= _
           lastRenderPixel Then Exit While

        If cursorRecorded = 0 AndAlso _
           textData->cursor_pos >= lineStart AndAlso _
           textData->cursor_pos <= lineEnd Then
            cursorLine = lineIndex
            cursorX = w->ax + textbox_TextPadding(textData) + _
                textbox_TotalGutterWidth(textData) + _
                textbox_TextWidth(textData, _
                    Mid( _
                        displayText, lineStart + 1, _
                        textData->cursor_pos - lineStart _
                    ) _
                )
            Dim As Integer cursorVirtual = textbox_ClampVirtualSpace( _
                textData, textData->cursor_pos, _
                textData->cursor_virtual_space _
            )
            If cursorVirtual > 0 Then
                Dim As Integer spaceWidth = textbox_TextWidth(textData, " ")
                If spaceWidth < 1 Then spaceWidth = 1
                cursorX += cursorVirtual * spaceWidth
            End If
            If textData->wordwrap = 0 Then _
                cursorX -= textData->scroll_offset
            cursorY = w->ay + textbox_TextPadding(textData) + _
                (lineIndex - textData->v_scroll) * textbox_LineHeight(textData)
            cursorRecorded = 1
        End If

        If preparedState = 0 OrElse lineIndex >= firstRenderRow Then
            lineText = Mid(displayText, lineStart + 1, lineEnd - lineStart)
            textbox_RenderLine w, textData, lineIndex, lineStart, lineText
        End If
        If (preparedState = 0 OrElse lineIndex >= firstRenderRow) AndAlso _
           lineEnd < Len(displayText) Then
            If displayText[lineEnd] = TEXTBOX_LINE_FEED OrElse _
               displayText[lineEnd] = TEXTBOX_CARRIAGE_RETURN Then
                If textData->render_color_state = 5 Then _
                    textData->render_color_state = 0
                If textData->render_style_state = 5 Then _
                    textData->render_style_state = 0
            End If
        End If
        lineIndex += 1
    Wend

    If textData->right_edge_column > 0 Then
        Dim As Integer spaceWidth = textbox_TextWidth(textData, " ")
        If spaceWidth < 1 Then spaceWidth = 1
        Dim As Integer edgeX = w->ax + textbox_TextPadding(textData) + _
            textbox_TotalGutterWidth(textData) + _
            textData->right_edge_column * spaceWidth
        If textData->wordwrap = 0 Then edgeX -= textData->scroll_offset
        backend_Line edgeX, w->ay + 2, edgeX, _
            w->ay + w->h - 3, textData->right_edge_color
    End If

    ' The damage box includes font overhang. Scene replay restores underlying
    ' text when the caret turns off, including selection and line highlights.
    textData->rendered_caret_w = 0
    textData->rendered_caret_h = 0
    If cursorRecorded <> 0 AndAlso cursorLine >= textData->v_scroll AndAlso _
       cursorY <= w->ay + w->h - _
           textbox_ScaledPadding(textData, TEXTBOX_TEXT_BOTTOM_PADDING) Then
        textData->rendered_caret_x = cursorX - 3
        textData->rendered_caret_y = cursorY - 2
        textData->rendered_caret_w = textbox_LineHeight(textData) + 6
        textData->rendered_caret_h = textbox_LineHeight(textData) + 4
    End If

    If textData->caret_visible <> 0 AndAlso _
       cursorRecorded <> 0 AndAlso textData->active <> 0 AndAlso _
       cursorLine >= textData->v_scroll AndAlso _
       (textData->multiline = 0 OrElse cursorY <= w->ay + w->h - _
        textbox_ScaledPadding(textData, TEXTBOX_TEXT_BOTTOM_PADDING)) AndAlso _
       gui_CaretBlinkVisible(Timer) <> 0 Then
        Dim As ULong caretColor = foregroundColor
        If textData->caret_color <> TEXTBOX_WIDGET_COLOR_DEFAULT Then _
            caretColor = textData->caret_color
        textbox_PrintStyled textData, cursorX, cursorY, caretColor, "|", 0
    End If

    If textData->multiline = 0 AndAlso Len(displayText) = 0 AndAlso _
       Len(textData->cue_banner_text) > 0 Then _
        textbox_PrintStyled textData, _
            w->ax + textbox_TextPadding(textData), _
            w->ay + textbox_TextPadding(textData), _
            textData->cue_banner_color, textData->cue_banner_text, 0

    backend_ResetClip()

    If textData->scrollbar_visible <> 0 AndAlso _
       textData->vertical_scrollbar <> 0 Then
        textData->vertical_scrollbar->render(textData->vertical_scrollbar)
    End If
    If textData->horizontal_scrollbar_visible <> 0 AndAlso _
       textData->horizontal_scrollbar <> 0 Then
        textData->horizontal_scrollbar->render(textData->horizontal_scrollbar)
    End If

End Sub


' fblint: disable-next-line FBL111 -- Focus, pointer and key transitions apply in editor event order.
Sub textbox_Update(ByVal w As Widget Ptr)

    Dim controlInputHandled As Integer
    Dim textData As TextBoxData Ptr
    Dim mouseX As Integer
    Dim mouseY As Integer
    Dim mouseButtons As Integer
    Dim previousCursor As Integer
    Dim As Integer previousCursorVirtualSpace
    Dim previousText As String
    Dim typedText As String
    Dim viewportChanged As Integer
    Dim As ULongInt updateRegistryId

    If w = 0 Then Exit Sub
    textData = Cast(TextBoxData Ptr, w->data)
    If textData = 0 Then Exit Sub
    updateRegistryId = w->registry_id
    If textData->cursor_pos <> textData->observed_cursor_pos Then _
        textData->cursor_virtual_space = 0

    If w->has_focus <> 0 AndAlso textData->observed_has_focus = 0 Then
        /'
            A textbox reached through keyboard traversal must accept editing
            without requiring a second mouse click. The transition check
            preserves the single-line Enter behavior, which ends editing
            while leaving the logical focus in place.
        '/
        textData->active = -1
    End If
    textData->observed_has_focus = IIf(w->has_focus <> 0, -1, 0)

    mouseX = input_MouseX()
    mouseY = input_MouseY()
    mouseButtons = input_MouseButtons()
    previousCursor = textData->cursor_pos
    previousCursorVirtualSpace = textData->cursor_virtual_space
    previousText = textData->text
    viewportChanged = IIf( _
        textData->viewport_dirty <> 0 OrElse _
        textData->observed_text_length <> Len(textData->text) OrElse _
        textData->observed_cursor_pos <> textData->cursor_pos OrElse _
        textData->observed_cursor_virtual_space <> _
            textData->cursor_virtual_space, _
        1, 0 _
    )
    textbox_UpdateScrollMetrics w, textData

    If textbox_HandleScrollInput( _
        w, textData, mouseX, mouseY, mouseButtons _
    ) = 0 Then
        textbox_HandleMouseInput w, textData, mouseX, mouseY, mouseButtons
    End If
    If textbox_CallbackTargetGone(w, updateRegistryId) Then Exit Sub

    If textData->active = 0 Then
        If active_textbox = w Then active_textbox = 0
        textData->key_latch = 0
        textbox_EndEditGroup w
        If viewportChanged <> 0 Then textbox_EnsureCursorVisible w, textData
        textData->viewport_dirty = 0
        textData->observed_text_length = Len(textData->text)
        textData->observed_cursor_pos = textData->cursor_pos
        textData->observed_cursor_virtual_space = _
            textData->cursor_virtual_space
        Exit Sub
    End If

    active_textbox = w
    textbox_RefreshKeyLatch textData

    If textbox_DispatchKeyDown(w, textData, updateRegistryId) = 0 Then _
        Exit Sub

    If textbox_HandleKeyEventInput(w, textData) <> 0 Then Exit Sub
    If textbox_CallbackTargetGone(w, updateRegistryId) Then Exit Sub

    controlInputHandled = textbox_HandleControlInput(w, textData)
    If textbox_CallbackTargetGone(w, updateRegistryId) Then Exit Sub

    If textbox_HandleTabInput(w, textData) <> 0 Then _
        controlInputHandled = -1

    typedText = input_PollTextInput()
    If w->has_focus <> 0 AndAlso textData->key_press_handler <> 0 Then
        ' Two extra bytes cover transformed Return and Backspace events.
        Dim As String accepted_text = Space(Len(typedText) + 2)
        Dim As Integer accepted_bytes
        For character_index As Integer = 1 To Len(typedText)
            Dim As Integer callback_character = Asc(typedText, character_index)
            Cast(Sub(ByVal As Widget Ptr, ByRef As Integer), _
                textData->key_press_handler)(w, callback_character)
            If textbox_CallbackTargetGone(w, updateRegistryId) Then Exit Sub
            If callback_character > 0 AndAlso callback_character <= 255 Then
                accepted_bytes += 1
                Mid(accepted_text, accepted_bytes, 1) = Chr(callback_character)
            End If
        Next character_index

        If input_KeyPressEvent(KEY_RETURN) Then
            Dim As Integer callback_return = 13
            Cast(Sub(ByVal As Widget Ptr, ByRef As Integer), _
                textData->key_press_handler)(w, callback_return)
            If textbox_CallbackTargetGone(w, updateRegistryId) Then Exit Sub
            If callback_return <> 13 Then
                ' Mark Return observed so navigation cannot apply it again.
                textData->key_latch Or= TEXTBOX_KEY_LATCH_RETURN
                If callback_return > 0 AndAlso callback_return <= 255 Then
                    accepted_bytes += 1
                    Mid(accepted_text, accepted_bytes, 1) = Chr(callback_return)
                End If
            End If
        End If
        If input_KeyPressEvent(KEY_BACKSPACE) Then
            Dim As Integer callback_backspace = 8
            Cast(Sub(ByVal As Widget Ptr, ByRef As Integer), _
                textData->key_press_handler)(w, callback_backspace)
            If textbox_CallbackTargetGone(w, updateRegistryId) Then Exit Sub
            If callback_backspace <> 8 Then
                textData->key_latch Or= TEXTBOX_KEY_LATCH_BACKSPACE
                If callback_backspace > 0 AndAlso callback_backspace <= 255 Then
                    accepted_bytes += 1
                    Mid(accepted_text, accepted_bytes, 1) = Chr(callback_backspace)
                End If
            End If
        End If
        typedText = Left(accepted_text, accepted_bytes)
    End If
    If typedText <> "" AndAlso textData->read_only = 0 AndAlso textbox_ConstrainInput(textData, typedText) Then
        textbox_BeginEdit w, TEXTBOX_HISTORY_GROUP_TYPING
        textbox_InsertText textData, typedText
        If textData->typed_text_handler <> 0 Then
            Dim As ULongInt callbackRegistryId = w->registry_id
            textData->typed_text_handler(w, typedText)
            If textbox_CallbackTargetGone(w, callbackRegistryId) Then Exit Sub
        End If
    End If

    If controlInputHandled = 0 Then
        textbox_HandleDeletionInput w, textData
        textbox_HandleNavigationInput w, textData
        If textbox_CallbackTargetGone(w, updateRegistryId) Then Exit Sub
    End If

    If textData->historyGroup <> TEXTBOX_HISTORY_GROUP_NONE Then
        textData->historyIdleFrames += 1

        If textData->historyIdleFrames >= _
           TEXTBOX_HISTORY_IDLE_FRAME_LIMIT Then
            textbox_EndEditGroup w
        End If
    End If

    If viewportChanged <> 0 OrElse _
       previousCursor <> textData->cursor_pos OrElse _
       previousCursorVirtualSpace <> textData->cursor_virtual_space OrElse _
       previousText <> textData->text Then
        textbox_EnsureCursorVisible w, textData
        textData->viewport_dirty = 0
    Else
        textbox_UpdateScrollMetrics w, textData
    End If

    /'
        Release callbacks run after character and navigation processing. This
        preserves the VBDOS KeyDown, KeyPress, KeyUp lifecycle while keeping
        text mutation inside the textbox rather than application handlers.
    '/
    If w->has_focus <> 0 AndAlso textData->key_up_handler <> 0 Then
        Dim As Long event_count = input_KeyEventCount()
        For event_index As Long = 0 To event_count - 1
            Dim As InputKeyEvent ordered_event
            If input_ReadKeyEvent(event_index, ordered_event) = 0 Then Continue For
            If ordered_event.event_kind <> INPUT_KEY_EVENT_RELEASE Then Continue For
            Dim As Integer callback_key = ordered_event.scan_code
            Dim As Integer callback_modifiers = ordered_event.modifiers
            Cast(Sub(ByVal As Widget Ptr, ByRef As Integer, ByRef As Integer), _
                textData->key_up_handler)(w, callback_key, callback_modifiers)
        Next event_index
    End If
    textData->observed_text_length = Len(textData->text)
    textData->observed_cursor_pos = textData->cursor_pos
    textData->observed_cursor_virtual_space = _
        textData->cursor_virtual_space

End Sub


Function textbox_SetKeyDownHandler( _
    ByVal w As Widget Ptr, ByVal key_down_handler As Any Ptr _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(TextBoxData Ptr, w->data)->key_down_handler = key_down_handler
    Return -1
End Function


Function textbox_SetKeyPressHandler( _
    ByVal w As Widget Ptr, ByVal key_press_handler As Any Ptr _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(TextBoxData Ptr, w->data)->key_press_handler = key_press_handler
    Return -1
End Function


Function textbox_SetKeyUpHandler( _
    ByVal w As Widget Ptr, ByVal key_up_handler As Any Ptr _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(TextBoxData Ptr, w->data)->key_up_handler = key_up_handler
    Return -1
End Function


Function textbox_SetTextStyle(ByVal w As Widget Ptr, ByVal text_style As Integer) As Integer
    If w = 0 OrElse w->destroy <> @textbox_Destroy OrElse w->data = 0 Then Return 0
    If (text_style And Not BACKEND_TEXT_STYLE_ALL) <> 0 Then Return 0
    ' Style affects glyph coverage only. Retain text, caret, selection, scroll
    ' position, and undo grouping; the existing advance metrics still apply.
    Cast(TextBoxData Ptr, w->data)->text_style = text_style
    Return -1
End Function

Function textbox_GetTextStyle(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->destroy <> @textbox_Destroy OrElse w->data = 0 Then Return 0
    Return Cast(TextBoxData Ptr, w->data)->text_style
End Function

Function textbox_SetBorderStyle( _
    ByVal w As Widget Ptr, ByVal border_style As Integer _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Return 0
    If border_style < TEXTBOX_BORDER_NONE OrElse _
       border_style > TEXTBOX_BORDER_SINGLE Then Return 0
    Cast(TextBoxData Ptr, w->data)->border_style = border_style
    Return -1
End Function


Function textbox_GetBorderStyle(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Return 0
    Return Cast(TextBoxData Ptr, w->data)->border_style
End Function

Function textbox_SetInputLimit(ByVal w As Widget Ptr, ByVal byte_limit As Long) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy OrElse byte_limit < 0 Then Return 0
    Dim As TextBoxData Ptr textData = w->data
    If textData->input_limit <> byte_limit Then textbox_EndEditGroup w
    textData->input_limit = byte_limit
    textData->max_text_bytes = byte_limit
    Return -1
End Function

Function textbox_GetInputLimit(ByVal w As Widget Ptr) As Long
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Return 0
    Return Cast(TextBoxData Ptr, w->data)->input_limit
End Function

Sub textbox_SetReadOnly( _
    ByVal w As Widget Ptr, ByVal read_only As Integer _
)
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 Then Exit Sub
    textData = Cast(TextBoxData Ptr, w->data)
    textData->read_only = IIf(read_only <> 0, -1, 0)
    w->captures_tab = IIf( _
        textData->accepts_tab <> 0 AndAlso textData->read_only = 0, _
        -1, 0 _
    )
    If textData->read_only <> 0 Then textbox_EndEditGroup w
End Sub


Function textbox_GetReadOnly(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Return Cast(TextBoxData Ptr, w->data)->read_only
End Function


Function textbox_SetBackgroundColor( _
    ByVal w As Widget Ptr, ByVal background_color As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(TextBoxData Ptr, w->data)
        .background_color = background_color
        .background_color_override = -1
    End With
    Return -1
End Function


Function textbox_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(TextBoxData Ptr, w->data)->background_color_override = 0
    Return -1
End Function


Function textbox_GetBackgroundColor( _
    ByVal w As Widget Ptr, ByRef background_color As ULong _
) As Integer
    Dim As TextBoxData Ptr textData

    background_color = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    If textData->background_color_override = 0 Then Return 0
    background_color = textData->background_color
    Return -1
End Function


Function textbox_SetForegroundColor( _
    ByVal w As Widget Ptr, ByVal foreground_color As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(TextBoxData Ptr, w->data)
        .foreground_color = foreground_color
        .foreground_color_override = -1
    End With
    Return -1
End Function


Function textbox_ClearForegroundColor(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(TextBoxData Ptr, w->data)->foreground_color_override = 0
    Return -1
End Function


Function textbox_GetForegroundColor( _
    ByVal w As Widget Ptr, ByRef foreground_color As ULong _
) As Integer
    Dim As TextBoxData Ptr textData

    foreground_color = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    If textData->foreground_color_override = 0 Then Return 0
    foreground_color = textData->foreground_color
    Return -1
End Function


Function textbox_SetSyntaxMode( _
    ByVal w As Widget Ptr, ByVal syntax_mode As Integer _
) As Integer

    If w = 0 OrElse w->data = 0 Then Return 0
    If syntax_mode <> TEXTBOX_SYNTAX_NONE AndAlso _
       syntax_mode <> TEXTBOX_SYNTAX_FREEBASIC Then Return 0
    Cast(TextBoxData Ptr, w->data)->syntax_mode = syntax_mode
    Return -1

End Function


Function textbox_GetSyntaxMode(ByVal w As Widget Ptr) As Integer

    If w = 0 OrElse w->data = 0 Then Return TEXTBOX_SYNTAX_NONE
    Return Cast(TextBoxData Ptr, w->data)->syntax_mode

End Function


Function textbox_SetSyntaxColor( _
    ByVal w As Widget Ptr, _
    ByVal color_kind As Integer, _
    ByVal syntax_color As ULong _
) As Integer

    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)

    Select Case color_kind
        Case TEXTBOX_SYNTAX_COLOR_KEYWORD
            textData->syntax_keyword_color = syntax_color
        Case TEXTBOX_SYNTAX_COLOR_COMMENT
            textData->syntax_comment_color = syntax_color
        Case TEXTBOX_SYNTAX_COLOR_STRING
            textData->syntax_string_color = syntax_color
        Case TEXTBOX_SYNTAX_COLOR_NUMBER
            textData->syntax_number_color = syntax_color
        Case TEXTBOX_SYNTAX_COLOR_PREPROCESSOR
            textData->syntax_preprocessor_color = syntax_color
        Case TEXTBOX_SYNTAX_COLOR_TYPE
            textData->syntax_type_color = syntax_color
        Case TEXTBOX_SYNTAX_COLOR_COMMAND
            textData->syntax_command_color = syntax_color
        Case TEXTBOX_SYNTAX_COLOR_PROCEDURE
            textData->syntax_procedure_color = syntax_color
        Case TEXTBOX_SYNTAX_COLOR_MACRO
            textData->syntax_macro_color = syntax_color
        Case TEXTBOX_SYNTAX_COLOR_VARIABLE
            textData->syntax_variable_color = syntax_color
        Case TEXTBOX_SYNTAX_COLOR_CONSTANT
            textData->syntax_constant_color = syntax_color
        Case TEXTBOX_SYNTAX_COLOR_MEMBER
            textData->syntax_member_color = syntax_color
        Case TEXTBOX_SYNTAX_COLOR_LABEL
            textData->syntax_label_color = syntax_color
        Case TEXTBOX_SYNTAX_COLOR_OBJECT
            textData->syntax_object_color = syntax_color
        Case Else
            Return 0
    End Select

    textData->syntax_color_overrides Or= (1 Shl color_kind)

    Return -1

End Function


Function textbox_GetSyntaxColor( _
    ByVal w As Widget Ptr, _
    ByVal color_kind As Integer, _
    ByRef syntax_color As ULong _
) As Integer

    Dim As TextBoxData Ptr textData

    syntax_color = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)

    If color_kind < TEXTBOX_SYNTAX_COLOR_KEYWORD OrElse _
       color_kind > TEXTBOX_SYNTAX_COLOR_OBJECT Then Return 0
    syntax_color = textbox_GetSyntaxColorValue(textData, color_kind)

    Return -1

End Function


Function textbox_ClearSyntaxColor( _
    ByVal w As Widget Ptr, ByVal color_kind As Integer _
) As Integer

    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 Then Return 0
    If color_kind < TEXTBOX_SYNTAX_COLOR_KEYWORD OrElse _
       color_kind > TEXTBOX_SYNTAX_COLOR_OBJECT Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    textData->syntax_color_overrides And= Not (1 Shl color_kind)
    Return -1

End Function


Function textbox_SetAcceptsTab( _
    ByVal w As Widget Ptr, ByVal accepts_tab As Integer _
) As Integer
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)

    If accepts_tab <> 0 AndAlso textData->multiline = 0 Then
        textData->accepts_tab = 0
        w->captures_tab = 0
        Return 0
    End If

    textData->accepts_tab = IIf(accepts_tab <> 0, -1, 0)
    w->captures_tab = IIf( _
        textData->accepts_tab <> 0 AndAlso textData->read_only = 0, _
        -1, 0 _
    )
    Return -1
End Function


Function textbox_GetAcceptsTab(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Return Cast(TextBoxData Ptr, w->data)->accepts_tab
End Function


Function textbox_SetLineNumbers( _
    ByVal w As Widget Ptr, ByVal line_numbers As Integer _
) As Integer
    Dim As Integer normalizedValue
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 Then Return 0
    textData = Cast(TextBoxData Ptr, w->data)
    normalizedValue = IIf(line_numbers <> 0, -1, 0)

    If normalizedValue <> 0 AndAlso textData->multiline = 0 Then
        textData->line_numbers = 0
        textData->line_number_gutter_width = 0
        Return 0
    End If

    textData->line_numbers = normalizedValue
    textData->line_number_gutter_width = _
        textbox_LineNumberGutterWidth(textData)
    textData->viewport_dirty = -1
    textbox_EnsureCursorVisible w, textData
    Return -1
End Function


Function textbox_GetLineNumbers(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Return Cast(TextBoxData Ptr, w->data)->line_numbers
End Function


Sub textbox_SetVerticalScrollbar( _
    ByVal w As Widget Ptr, ByVal scrollbarMode As Integer _
)
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 Then Exit Sub
    textData = Cast(TextBoxData Ptr, w->data)

    If scrollbarMode < TEXTBOX_SCROLLBAR_NONE OrElse _
       scrollbarMode > TEXTBOX_SCROLLBAR_ALWAYS Then
        scrollbarMode = TEXTBOX_SCROLLBAR_AUTO
    End If

    textData->scrollbar_mode = scrollbarMode
    If scrollbarMode = TEXTBOX_SCROLLBAR_NONE Then textData->v_scroll = 0
    textbox_UpdateScrollMetrics w, textData
End Sub


Function textbox_GetVerticalScrollbarMode( _
    ByVal w As Widget Ptr _
) As Integer
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 Then Return TEXTBOX_SCROLLBAR_NONE
    textData = Cast(TextBoxData Ptr, w->data)
    Return textData->scrollbar_mode
End Function


Sub textbox_SetHorizontalScrollbar( _
    ByVal w As Widget Ptr, ByVal scrollbarMode As Integer _
)
    Dim As TextBoxData Ptr textData

    If w = 0 OrElse w->data = 0 Then Exit Sub
    textData = Cast(TextBoxData Ptr, w->data)
    If scrollbarMode < TEXTBOX_SCROLLBAR_NONE OrElse _
       scrollbarMode > TEXTBOX_SCROLLBAR_ALWAYS Then
        scrollbarMode = TEXTBOX_SCROLLBAR_AUTO
    End If

    textData->horizontal_scrollbar_mode = scrollbarMode
    textbox_UpdateScrollMetrics w, textData
End Sub


Function textbox_GetHorizontalScrollbarMode( _
    ByVal w As Widget Ptr _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return TEXTBOX_SCROLLBAR_NONE
    Return Cast(TextBoxData Ptr, w->data)->horizontal_scrollbar_mode
End Function


Sub textbox_Destroy(ByVal w As Widget Ptr)

    Dim As TextBoxData Ptr textData

    If w = 0 Then Exit Sub
    If active_textbox = w Then active_textbox = 0
    textData = Cast(TextBoxData Ptr, w->data)

    If textData <> 0 Then
        If textData->vertical_scrollbar <> 0 Then
            If textData->vertical_scrollbar->destroy <> 0 Then _
                textData->vertical_scrollbar->destroy( _
                    textData->vertical_scrollbar _
                )
            Delete textData->vertical_scrollbar
            textData->vertical_scrollbar = 0
        End If
        If textData->horizontal_scrollbar <> 0 Then
            If textData->horizontal_scrollbar->destroy <> 0 Then _
                textData->horizontal_scrollbar->destroy( _
                    textData->horizontal_scrollbar _
                )
            Delete textData->horizontal_scrollbar
            textData->horizontal_scrollbar = 0
        End If

        Delete textData
        w->data = 0
    End If

End Sub

Sub textbox_SetScrollbarColors( _
    ByVal w As Widget Ptr, ByVal trackColor As ULong, _
    ByVal thumbColor As ULong, ByVal thumbBorderColor As ULong _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    scrollbar_SetColors d->vertical_scrollbar, trackColor, thumbColor, thumbBorderColor
    scrollbar_SetColors d->horizontal_scrollbar, trackColor, thumbColor, thumbBorderColor
End Sub


Sub textbox_SetMaxTextBytes(ByVal w As Widget Ptr, ByVal maximumBytes As Integer)
    If maximumBytes < 0 Then maximumBytes = 0
    textbox_SetInputLimit w, maximumBytes
End Sub


Sub textbox_SetCaretColor(ByVal w As Widget Ptr, ByVal caretColor As ULong)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Cast(TextBoxData Ptr, w->data)->caret_color = caretColor
End Sub


Sub textbox_SetCaretVisible(ByVal w As Widget Ptr, ByVal visible As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Cast(TextBoxData Ptr, w->data)->caret_visible = IIf(visible <> 0, -1, 0)
End Sub


Sub textbox_SetSurfaceColors( _
    ByVal w As Widget Ptr, ByVal borderColor As ULong, _
    ByVal backgroundColor As ULong, ByVal textColor As ULong _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    d->surface_border_color = borderColor
    d->surface_background_color = backgroundColor
    d->surface_text_color = textColor
End Sub


Sub textbox_SetCueBanner( _
    ByVal w As Widget Ptr, ByVal cueText As String, ByVal cueColor As ULong _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    If Len(cueText) > TEXTBOX_CUE_BANNER_MAX_BYTES Then _
        cueText = Left(cueText, TEXTBOX_CUE_BANNER_MAX_BYTES)
    If InStr(cueText, Chr(0)) OrElse InStr(cueText, Chr(10)) OrElse _
       InStr(cueText, Chr(13)) Then cueText = ""
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    d->cue_banner_text = cueText
    d->cue_banner_color = cueColor
End Sub


Sub textbox_SetCurrentLineHighlight( _
    ByVal w As Widget Ptr, ByVal enabled As Integer, _
    ByVal backgroundColor As ULong _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    d->current_line_highlight = IIf(enabled, -1, 0)
    d->current_line_background_color = backgroundColor
End Sub


Sub textbox_SetLineRangeHighlight( _
    ByVal w As Widget Ptr, ByVal firstLine As Integer, _
    ByVal lastLine As Integer, ByVal enabled As Integer _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    If enabled = 0 OrElse firstLine < 0 OrElse lastLine < firstLine Then
        d->line_range_highlight = 0
        d->line_range_highlight_first = -1
        d->line_range_highlight_last = -1
    Else
        d->line_range_highlight = -1
        d->line_range_highlight_first = firstLine
        d->line_range_highlight_last = lastLine
    End If
End Sub


Sub textbox_CenterPosition(ByVal w As Widget Ptr, ByVal position As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    Dim ByRef displayText As String = textbox_VisualText(d)
    position = textbox_ClampPosition(displayText, position)
    textbox_UpdateScrollMetrics w, d
    Dim As Integer contentWidth = textbox_ContentWidth(w, d)
    Dim As Integer targetLine = textbox_VisualLineForPosition( _
        displayText, position, d->wordwrap, contentWidth, d)
    Dim As Integer visibleLines = textbox_VisibleLineCount(w, d)
    If visibleLines < 1 Then visibleLines = 1
    d->v_scroll = targetLine - ((visibleLines - 1) \ 2)
    d->viewport_dirty = -1
    textbox_UpdateScrollMetrics w, d
End Sub


Sub textbox_SetLineNumberGutter( _
    ByVal w As Widget Ptr, ByVal gutterWidth As Integer, _
    ByVal textColor As ULong, ByVal backgroundColor As ULong _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    If gutterWidth < 0 Then gutterWidth = 0
    If gutterWidth > 0 AndAlso gutterWidth < 24 Then gutterWidth = 24
    Dim As Integer maximumWidth = w->w - 24
    If maximumWidth < 0 Then maximumWidth = 0
    If gutterWidth > maximumWidth Then gutterWidth = maximumWidth
    d->line_number_gutter_width = gutterWidth
    d->line_number_text_color = textColor
    d->line_number_background_color = backgroundColor
    d->line_numbers = IIf(gutterWidth > 0, -1, 0)
    d->viewport_dirty = -1
End Sub


Sub textbox_SetLineNumberTextStyle(ByVal w As Widget Ptr, ByVal styleFlags As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As Integer allowed = TEXTBOX_TEXT_STYLE_BOLD Or _
        TEXTBOX_TEXT_STYLE_UNDERLINE Or TEXTBOX_TEXT_STYLE_ITALIC
    Cast(TextBoxData Ptr, w->data)->line_number_text_style_flags = styleFlags And allowed
End Sub


Sub textbox_SetLineNumberVisibility(ByVal w As Widget Ptr, ByVal visible As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Cast(TextBoxData Ptr, w->data)->line_numbers_visible = IIf(visible, -1, 0)
End Sub


Sub textbox_SetIndentBehavior( _
    ByVal w As Widget Ptr, ByVal indentWidth As Integer, _
    ByVal autoIndent As Integer, ByVal useTabs As Integer _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    If d->multiline = 0 Then Exit Sub
    If indentWidth < 0 Then indentWidth = 0
    If indentWidth > 16 Then indentWidth = 16
    If indentWidth = 0 Then
        indentWidth = TEXTBOX_TAB_COLUMNS
        useTabs = -1
    End If
    d->indent_width = indentWidth
    d->indent_with_tabs = IIf(useTabs, -1, 0)
    d->auto_indent = IIf(autoIndent, -1, 0)
    textbox_SetAcceptsTab w, -1
End Sub


Sub textbox_SetIndentGuides( _
    ByVal w As Widget Ptr, ByVal enabled As Integer, _
    ByVal guideColor As ULong _
)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Dim As TextBoxData Ptr textData = Cast(TextBoxData Ptr, w->data)
    textData->indent_guides_enabled = IIf(enabled <> 0, -1, 0)
    textData->indent_guides_color = guideColor
End Sub


Sub textbox_SetRightEdge( _
    ByVal w As Widget Ptr, ByVal columnNumber As Integer, _
    ByVal edgeColor As ULong _
)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    If columnNumber < 0 Then columnNumber = 0
    ' Keep the pixel coordinate bounded even on a narrow screen.
    If columnNumber > 1024 Then columnNumber = 1024
    Dim As TextBoxData Ptr textData = Cast(TextBoxData Ptr, w->data)
    textData->right_edge_column = columnNumber
    textData->right_edge_color = edgeColor
End Sub


Sub textbox_SetTypedTextHandler( _
    ByVal w As Widget Ptr, ByVal typedTextHandler As TextBoxTypedTextHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Cast(TextBoxData Ptr, w->data)->typed_text_handler = typedTextHandler
End Sub


Sub textbox_SetContextMenuHandler( _
    ByVal w As Widget Ptr, ByVal contextMenuHandler As TextBoxContextMenuHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Cast(TextBoxData Ptr, w->data)->context_menu_handler = contextMenuHandler
End Sub


Sub textbox_SetNavigationHandler( _
    ByVal w As Widget Ptr, ByVal navigationHandler As TextBoxNavigationHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Cast(TextBoxData Ptr, w->data)->navigation_handler = navigationHandler
End Sub


Sub textbox_SetControlShortcutHandler( _
    ByVal w As Widget Ptr, _
    ByVal shortcutHandler As TextBoxControlShortcutHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Cast(TextBoxData Ptr, w->data)->control_shortcut_handler = shortcutHandler
End Sub


Sub textbox_SetKeyEventHandler( _
    ByVal w As Widget Ptr, ByVal keyEventHandler As TextBoxKeyEventHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Cast(TextBoxData Ptr, w->data)->key_event_handler = keyEventHandler
End Sub


Sub textbox_SetZoomPercent(ByVal w As Widget Ptr, ByVal percent As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    If percent < 50 Then percent = 50
    If percent > 300 Then percent = 300
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    If d->zoom_percent = percent Then Exit Sub
    d->zoom_percent = percent
    d->viewport_dirty = -1
    textbox_EnsureCursorVisible w, d
End Sub


Sub textbox_SetFontScalePercent( _
    ByVal w As Widget Ptr, ByVal fontPercent As Integer _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    If fontPercent < 50 OrElse fontPercent > 300 Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    If d->font_scale_percent = fontPercent Then Exit Sub
    d->font_scale_percent = fontPercent
    d->viewport_dirty = -1
    textbox_EnsureCursorVisible w, d
End Sub


Sub textbox_SetLineSpacing( _
    ByVal w As Widget Ptr, ByVal extraPixels As Integer _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    If extraPixels < 0 OrElse extraPixels > 16 Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    If d->extra_line_spacing = extraPixels Then Exit Sub
    d->extra_line_spacing = extraPixels
    d->viewport_dirty = -1
    textbox_EnsureCursorVisible w, d
End Sub


Sub textbox_SetFont(ByVal w As Widget Ptr, ByVal font_id As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    If font_id < BACKEND_FONT_DEFAULT OrElse _
       font_id > BACKEND_FONT_TERMINAL Then font_id = BACKEND_FONT_DEFAULT
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    If d->font_id = font_id Then Exit Sub
    d->font_id = font_id
    d->viewport_dirty = -1
    textbox_EnsureCursorVisible w, d
End Sub


Sub textbox_SetVirtualSpace(ByVal w As Widget Ptr, ByVal enabled As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    enabled = IIf(enabled <> 0, -1, 0)
    If d->virtual_space_enabled = enabled Then Exit Sub
    d->virtual_space_enabled = enabled
    If enabled = 0 Then textbox_ClearVirtualSpace w
    d->observed_cursor_virtual_space = d->cursor_virtual_space
    d->viewport_dirty = -1
End Sub


Sub textbox_ClearVirtualSpace(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    d->cursor_virtual_space = 0
    d->sel_start_virtual_space = 0
    d->sel_end_virtual_space = 0
    d->selection_anchor_virtual_space = 0
    d->observed_cursor_virtual_space = 0
    d->viewport_dirty = -1
End Sub


Sub textbox_SetTextDisplayHandler( _
    ByVal w As Widget Ptr, ByVal displayHandler As TextBoxTextDisplayHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    d->text_display_handler = displayHandler
    d->display_valid = 0
    d->display_source_length = 0
    d->display_text = ""
    d->viewport_dirty = -1
    textbox_EnsureCursorVisible w, d
End Sub


Sub textbox_SetTextColorHandler( _
    ByVal w As Widget Ptr, ByVal colorHandler As TextBoxTextColorHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Cast(TextBoxData Ptr, w->data)->text_color_handler = colorHandler
End Sub


Sub textbox_SetRenderStateHandler( _
    ByVal w As Widget Ptr, ByVal stateHandler As TextBoxRenderStateHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Cast(TextBoxData Ptr, w->data)->render_state_handler = stateHandler
End Sub


Sub textbox_SetMetricsStateHandler( _
    ByVal w As Widget Ptr, ByVal stateHandler As TextBoxMetricsStateHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr textData = Cast(TextBoxData Ptr, w->data)
    textData->metrics_state_handler = stateHandler
    textData->metrics_valid = 0
End Sub


Sub textbox_SetTextStyleHandler( _
    ByVal w As Widget Ptr, ByVal styleHandler As TextBoxTextStyleHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Cast(TextBoxData Ptr, w->data)->text_style_handler = styleHandler
End Sub


Sub textbox_SetTextIndicatorHandler( _
    ByVal w As Widget Ptr, _
    ByVal indicatorHandler As TextBoxTextIndicatorHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Cast(TextBoxData Ptr, w->data)->text_indicator_handler = indicatorHandler
End Sub


Sub textbox_SetGutterMarkerHandler( _
    ByVal w As Widget Ptr, ByVal markerHandler As TextBoxGutterMarkerHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    d->gutter_marker_handler = markerHandler
    d->gutter_marker_style_handler = 0
End Sub


Sub textbox_SetGutterMarkerStyleHandler( _
    ByVal w As Widget Ptr, _
    ByVal markerHandler As TextBoxGutterMarkerStyleHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    d->gutter_marker_handler = 0
    d->gutter_marker_style_handler = markerHandler
End Sub


Sub textbox_SetGutterClickHandler( _
    ByVal w As Widget Ptr, ByVal clickHandler As TextBoxGutterClickHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Cast(TextBoxData Ptr, w->data)->gutter_click_handler = clickHandler
End Sub


Sub textbox_SetFoldGutter( _
    ByVal w As Widget Ptr, ByVal gutterWidth As Integer, _
    ByVal markerHandler As TextBoxFoldMarkerHandler, _
    ByVal clickHandler As TextBoxFoldClickHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    Dim As Integer maximumWidth = w->w - 24 - d->line_number_gutter_width
    If maximumWidth < 0 Then maximumWidth = 0
    If gutterWidth < 0 Then gutterWidth = 0
    If gutterWidth > maximumWidth Then gutterWidth = maximumWidth
    d->fold_gutter_width = gutterWidth
    d->fold_marker_handler = markerHandler
    d->fold_click_handler = clickHandler
    d->viewport_dirty = -1
    textbox_EnsureCursorVisible w, d
End Sub


Sub textbox_SetFoldColors( _
    ByVal w As Widget Ptr, ByVal marginBackgroundColor As ULong, _
    ByVal symbolForegroundColor As ULong, _
    ByVal symbolBackgroundColor As ULong _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    d->fold_margin_background_color = marginBackgroundColor
    d->fold_symbol_foreground_color = symbolForegroundColor
    d->fold_symbol_background_color = symbolBackgroundColor
End Sub


Sub textbox_SetLineVisibilityHandler( _
    ByVal w As Widget Ptr, _
    ByVal visibilityHandler As TextBoxLineVisibilityHandler _
)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @textbox_Destroy Then Exit Sub
    Dim As TextBoxData Ptr d = Cast(TextBoxData Ptr, w->data)
    d->line_visibility_handler = visibilityHandler
    d->viewport_dirty = -1
    textbox_EnsureCursorVisible w, d
End Sub

' end of textbox.bas
