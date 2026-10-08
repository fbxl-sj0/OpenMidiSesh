' Project: OpenSesh validator regression checks
' File: tools/fblint/test_callback_cast_inputs.bas
' Purpose: Check callback cast receipts with the production model reader.
' Responsibilities: Accept owned void calls and reject a mismatched signature.
' Targets: FreeBASIC fb dialect, native schema-27 reader.
' Module API: Command-line model path and expected validation outcome.
' This file intentionally does NOT infer callback types from source text.
#Lang "fb"
#Include Once "test_fixture_symbol_classes.bi"
Const FBLINT_MAX_SEMANTIC_SYMBOL_TYPES As LongInt = 250000
Const FBLINT_MAX_SEMANTIC_MODEL_IDENTITIES As LongInt = 1000000
Const FBLINT_MAX_SEMANTIC_PROCEDURE_PARAMETERS As LongInt = 1024
Const FBLINT_SEMANTIC_MAX_INTEGER As LongInt = 4294967295
Const DECIMAL_RADIX As Integer = 10
#Include Once "src/fb_linter_semantic_wire.bi"
#Include Once "src/fb_linter_semantic_schema20.bi"
#Include Once "src/fb_linter_semantic_schema27.bi"

Dim As String ModelPath = Command(1), Expected = Command(2), LatestTypes()
Dim As LongInt CanonicalIds()
If Expected <> "valid" AndAlso Expected <> "callback-invalid" Then End 2
Dim As Integer Accepted = FblintValidateSchema27Metadata(ModelPath, LatestTypes(), CanonicalIds())
If Expected = "valid" Then
    If Accepted = 0 Then
        Print "Callback model rejected: "; Schema27Failure
        End 1
    End If
Else
    If Accepted <> 0 OrElse Schema27Failure <> "procedure callback inputs" Then
        Print "Unexpected callback result: "; Accepted; ", "; Schema27Failure
        End 1
    End If
End If
Print "CALLBACK_CAST_MODEL_PASS "; Expected
End 0
' end of tools/fblint/test_callback_cast_inputs.bas
