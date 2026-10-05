/'
    Project: omaGUI
    File: textbox_indent.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI textbox_indent implementation imported through omaGUI.bi.
    Purpose: Indent logical source lines as one bounded textbox transaction.
    Responsibilities:
        - preserve mixed line endings, non-whitespace bytes, and selection direction
        - construct the replacement before changing document or history state
        - keep caret and selection endpoints attached to their original text
        - expose opt-in keyboard policy without changing ordinary text controls
    This file intentionally does NOT contain:
        - input polling, rendering, application menus, or language-specific parsing
'/

#lang "fb"
#include once "src/widgets/textbox.bi"

' -------------------------------------------------------------------------
' Checked widget state and logical line boundaries
' -------------------------------------------------------------------------

Type TextBoxIndentSelectionState
    As Integer cursor_pos, selection_anchor, sel_start, sel_end
End Type

Private Function textboxIndent_Data(ByVal w As Widget Ptr) As TextBoxData Ptr
    If w = 0 Then Return 0
    If w->destroy <> @textbox_Destroy Then Return 0
    Return Cast(TextBoxData Ptr, w->data)
End Function

Private Function textboxIndent_Clamp(ByVal position As Integer, ByVal text_length As Integer) As Integer
    If position < 0 Then Return 0
    If position > text_length Then Return text_length
    Return position
End Function

Private Function textboxIndent_LineStart(ByRef source_text As Const String, ByVal position As Integer) As Integer
    ' A caret between CR and LF belongs to the preceding logical line. Never
    ' insert indentation between the two bytes of a DOS line ending.
    If position > 0 AndAlso position < Len(source_text) AndAlso _
       source_text[position - 1] = 13 AndAlso source_text[position] = 10 Then position -= 1
    While position > 0
        If source_text[position - 1] = 10 OrElse source_text[position - 1] = 13 Then Exit While
        position -= 1
    Wend
    Return position
End Function

Private Function textboxIndent_NextLine(ByRef source_text As Const String, ByVal position As Integer) As Integer
    While position < Len(source_text)
        If source_text[position] = 13 Then
            position += 1
            If position < Len(source_text) AndAlso source_text[position] = 10 Then position += 1
            Return position
        End If
        If source_text[position] = 10 Then Return position + 1
        position += 1
    Wend
    Return position
End Function

Private Function textboxIndent_PrefixLength(ByRef source_text As Const String, ByVal line_start As Integer) As Integer
    Dim As Integer removed_bytes, removed_columns, character_code
    ' ASCII space (32) advances one column; Tab (9) advances to a tab stop.
    While line_start + removed_bytes < Len(source_text) AndAlso removed_columns < TEXTBOX_TAB_COLUMNS
        character_code = source_text[line_start + removed_bytes]
        If character_code = 32 Then
            removed_columns += 1
        ElseIf character_code = 9 Then
            removed_columns += TEXTBOX_TAB_COLUMNS - (removed_columns Mod TEXTBOX_TAB_COLUMNS) ' fblint: disable-line FBL406 REASON: The Mod operands are nonnegative; the minus sign belongs to a different expression.
        Else
            Exit While
        End If
        removed_bytes += 1
    Wend
    Return removed_bytes
End Function

' -------------------------------------------------------------------------
' Position mapping and checked copying
' -------------------------------------------------------------------------

Private Sub textboxIndent_MapPoint( _
    ByVal original_position As Integer, ByRef mapped_position As Integer, _
    ByVal line_start As Integer, ByVal byte_change As Integer _
)
    Dim As Integer removed_before
    If original_position < line_start Then Exit Sub
    If byte_change >= 0 Then
        mapped_position += byte_change
    Else
        removed_before = original_position - line_start
        If removed_before > -byte_change Then removed_before = -byte_change
        mapped_position -= removed_before
    End If
End Sub

Private Sub textboxIndent_MapSelection( _
    ByRef original As Const TextBoxIndentSelectionState, _
    ByRef mapped As TextBoxIndentSelectionState, _
    ByVal line_start As Integer, ByVal byte_change As Integer _
)
    ' Compare against original positions, not already-shifted ones. Each
    ' preceding line contributes exactly once, including an excluded end line.
    textboxIndent_MapPoint original.cursor_pos, mapped.cursor_pos, line_start, byte_change
    textboxIndent_MapPoint original.selection_anchor, mapped.selection_anchor, line_start, byte_change
    textboxIndent_MapPoint original.sel_start, mapped.sel_start, line_start, byte_change
    textboxIndent_MapPoint original.sel_end, mapped.sel_end, line_start, byte_change
End Sub

Private Function textboxIndent_CopySpan( _
    ByRef destination_text As String, ByRef destination_position As Integer, _
    ByRef source_text As Const String, ByVal span_start As Integer, ByVal span_end As Integer _
) As Integer
    Dim As Integer byte_count = span_end - span_start
    If span_start < 0 OrElse span_end < span_start OrElse span_end > Len(source_text) Then Return 0
    If destination_position < 0 OrElse destination_position > Len(destination_text) Then Return 0
    If byte_count > Len(destination_text) - destination_position Then Return 0
    ' Copy into one exact-size buffer. Concatenating the whole document once
    ' per line would make a large selection quadratic in time and allocation.
    For byte_index As Integer = 0 To byte_count - 1
        destination_text[destination_position + byte_index] = source_text[span_start + byte_index]
    Next byte_index
    destination_position += byte_count
    Return -1
End Function

Private Function textboxIndent_ResultLength( _
    ByRef source_text As Const String, ByVal first_line As Integer, _
    ByVal last_line As Integer, ByVal remove_indent As Integer _
) As Integer
    Dim As Integer line_start = first_line
    Dim As Integer next_line, byte_change, changed_lines
    Dim As LongInt result_length = Len(source_text)
    Do
        byte_change = TEXTBOX_TAB_COLUMNS
        If remove_indent Then byte_change = -textboxIndent_PrefixLength(source_text, line_start)
        If byte_change <> 0 Then changed_lines += 1
        result_length += byte_change
        If result_length > TEXTBOX_HISTORY_MAX_STORED_BYTES OrElse result_length < 0 Then Return -1
        If line_start = last_line Then Exit Do
        next_line = textboxIndent_NextLine(source_text, line_start)
        If next_line <= line_start OrElse next_line > last_line Then Return -1
        line_start = next_line
    Loop
    If changed_lines = 0 Then Return -1
    Return CInt(result_length)
End Function

' -------------------------------------------------------------------------
' One undo transaction for the complete affected block
' -------------------------------------------------------------------------

Private Function textboxIndent_Apply(ByVal w As Widget Ptr, ByVal remove_indent As Integer) As Integer
    Dim As TextBoxData Ptr textData = textboxIndent_Data(w)
    Dim As TextBoxIndentSelectionState original, mapped
    Dim As Integer text_length, first_line, last_line, selection_start, selection_end
    Dim As Integer line_start, next_line, removed_bytes, byte_change
    Dim As Integer result_length, destination_position
    Dim As String result_text
    If textData = 0 Then Return 0
    If w->enabled = 0 OrElse textData->read_only OrElse textData->multiline = 0 Then Return 0
    text_length = Len(textData->text)
    ' The old document must fit one undo snapshot as well as the new document.
    If text_length > TEXTBOX_HISTORY_MAX_STORED_BYTES Then Return 0
    original.cursor_pos = textboxIndent_Clamp(textData->cursor_pos, text_length)
    original.selection_anchor = textboxIndent_Clamp(textData->selection_anchor, text_length)
    original.sel_start = textboxIndent_Clamp(textData->sel_start, text_length)
    original.sel_end = textboxIndent_Clamp(textData->sel_end, text_length)
    mapped = original
    selection_start = original.sel_start
    selection_end = original.sel_end
    If selection_start > selection_end Then Swap selection_start, selection_end
    If selection_start = selection_end Then
        first_line = textboxIndent_LineStart(textData->text, original.cursor_pos)
        last_line = first_line
    Else
        first_line = textboxIndent_LineStart(textData->text, selection_start)
        ' The exclusive end does not select the following line when it stops
        ' at that line's first byte, or in the middle of a CRLF pair.
        last_line = textboxIndent_LineStart(textData->text, selection_end - 1)
    End If
    result_length = textboxIndent_ResultLength(textData->text, first_line, last_line, remove_indent)
    If result_length < 0 Then Return 0
    ' An optional input limit must not leave a block half-indented. Outdenting
    ' oversized source remains permitted because it only releases space.
    If textData->input_limit > 0 AndAlso result_length > textData->input_limit AndAlso result_length > text_length Then Return 0
    result_text = Space(result_length)
    If Len(result_text) <> result_length Then Return 0
    If textboxIndent_CopySpan(result_text, destination_position, textData->text, 0, first_line) = 0 Then Return 0
    line_start = first_line
    Do
        next_line = textboxIndent_NextLine(textData->text, line_start)
        removed_bytes = 0
        byte_change = TEXTBOX_TAB_COLUMNS
        If remove_indent Then
            removed_bytes = textboxIndent_PrefixLength(textData->text, line_start)
            byte_change = -removed_bytes
        Else
            ' Space() already supplied the indentation bytes.
            destination_position += TEXTBOX_TAB_COLUMNS
        End If
        textboxIndent_MapSelection original, mapped, line_start, byte_change
        If textboxIndent_CopySpan(result_text, destination_position, textData->text, _
            line_start + removed_bytes, next_line) = 0 Then Return 0
        If line_start = last_line Then Exit Do
        line_start = next_line
    Loop
    If textboxIndent_CopySpan(result_text, destination_position, textData->text, next_line, text_length) = 0 Then Return 0
    If destination_position <> result_length Then Return 0

    ' All validation and allocation precede history changes. No-op outdents
    ' and capacity failures therefore preserve a pending redo transaction.
    If textbox_BeginEdit(w, TEXTBOX_HISTORY_GROUP_NONE) = 0 Then Return 0
    Swap textData->text, result_text
    textData->change_serial += 1
    textData->selection_anchor = mapped.selection_anchor
    textbox_SetCursorPosition w, mapped.cursor_pos, -1
    textData->sel_start = mapped.sel_start
    textData->sel_end = mapped.sel_end
    textData->viewport_dirty = -1
    Return -1
End Function

Function textbox_IndentSelection(ByVal w As Widget Ptr) As Integer
    Return textboxIndent_Apply(w, 0)
End Function

Function textbox_UnindentSelection(ByVal w As Widget Ptr) As Integer
    Return textboxIndent_Apply(w, -1)
End Function

Function textbox_SetBlockIndent(ByVal w As Widget Ptr, ByVal block_indent As Integer) As Integer
    Dim As TextBoxData Ptr textData = textboxIndent_Data(w)
    If textData = 0 Then Return 0
    If block_indent <> 0 AndAlso textData->multiline = 0 Then Return 0
    textData->block_indent = IIf(block_indent <> 0, -1, 0)
    Return -1
End Function

Function textbox_GetBlockIndent(ByVal w As Widget Ptr) As Integer
    Dim As TextBoxData Ptr textData = textboxIndent_Data(w)
    If textData = 0 Then Return 0
    Return textData->block_indent
End Function

' end of textbox_indent.bas
