' Project: OpenSesh validator regression checks
' File: tools/fblint/test_wire_copy.bas
' Purpose: Preserve byte-oriented semantic field decoding after the plain copy optimization.
' Responsibilities: Raw bytes, escaped bytes, embedded NULs and malformed escapes.
' Targets: FreeBASIC fb dialect, native semantic wire consumer.
' This file intentionally does NOT construct compiler facts or benchmark readers.
#Lang "fb"
' The wire's unsigned integer fields have a 32-bit ceiling and use decimal text.
Const FBLINT_SEMANTIC_MAX_INTEGER As LongInt = 4294967295
Const DECIMAL_RADIX As Integer = 10
#Include Once "src/fb_linter_semantic_wire.bi"

' -------------------------------------------------------------------------
' Successful decoding preserves every byte, including bytes after a NUL
' -------------------------------------------------------------------------

Private Sub RequireDecoded(ByRef FieldText As String, ByRef ExpectedText As String)
    Dim As String DecodedText
    If FblintSemanticDecodeField(FieldText, DecodedText) = 0 OrElse DecodedText <> ExpectedText Then
        Print "WIRE_COPY_FAIL: decoded bytes differ"
        End 1
    End If
End Sub

Dim As String RawBytes, EscapedBytes, AllBytes
For ByteValue As Integer = 0 To 255
    Dim As String ByteText = Chr(ByteValue)
    Dim As String EscapedText = "%" + Hex(ByteValue, 2)
    RequireDecoded EscapedText, ByteText
    AllBytes += ByteText
    EscapedBytes += EscapedText
    If ByteValue <> Asc("%") Then
        RequireDecoded ByteText, ByteText
        RawBytes += ByteText
    End If
Next ByteValue
RequireDecoded RawBytes, RawBytes
RequireDecoded EscapedBytes, AllBytes
Dim As String EmptyText
RequireDecoded EmptyText, EmptyText
Dim As String EscapedAfterNul = "a" + Chr(0) + "%25z"
Dim As String DecodedAfterNul = "a" + Chr(0) + "%z"
RequireDecoded EscapedAfterNul, DecodedAfterNul

' The wire reader must also preserve long fields without truncation.
Const LONG_FIELD_BYTES As Integer = 131072
Dim As String LongField = String(LONG_FIELD_BYTES, Asc("x")) + Chr(0) + Chr(255)
RequireDecoded LongField, LongField

' -------------------------------------------------------------------------
' A percent marker still requires two valid hexadecimal digits
' -------------------------------------------------------------------------

Dim As String InvalidFields(0 To 4) = { "%", "%A", "%G0", "%0G", "a" + Chr(0) + "%" }
For FieldIndex As Integer = 0 To UBound(InvalidFields)
    Dim As String DecodedText
    If FblintSemanticDecodeField(InvalidFields(FieldIndex), DecodedText) <> 0 Then
        Print "WIRE_COPY_FAIL: malformed escape accepted"
        End 1
    End If
Next FieldIndex
Print "WIRE_COPY_PASS: raw and escaped bytes, NULs, long fields, malformed escapes"
End 0
' end of tools/fblint/test_wire_copy.bas
