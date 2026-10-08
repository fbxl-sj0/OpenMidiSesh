' Project: OpenSesh validator regression checks
' File: tools/fblint/test_anonymous_enum_replay.bas
' Purpose: Exercise production anonymous enum replay keys on compiler exports.
' Responsibilities: Retain distinct enum identities and leave source names and records intact.
' This file intentionally does NOT replace the full replay frame comparison.
#Lang "fb"
#Include Once "test_fixture_symbol_classes.bi"
Const FBLINT_MAX_SEMANTIC_SYMBOL_TYPES As LongInt = 250000
Const FBLINT_MAX_SEMANTIC_MODEL_IDENTITIES As LongInt = 1000000
Const FBLINT_MAX_SEMANTIC_PROCEDURE_PARAMETERS As LongInt = 1024
Const FBLINT_SEMANTIC_MAX_INTEGER As LongInt = 4294967295
Const FBLINT_SEMANTIC_NODE_CLASS_CONST As LongInt = 16
Const FBLINT_SEMANTIC_NODE_CLASS_VAR As LongInt = 17
Const DECIMAL_RADIX As Integer = 10
#Include Once "src/fb_linter_semantic_wire.bi"
#Include Once "src/fb_linter_semantic_schema20.bi"
#Include Once "src/fb_linter_semantic_schema27.bi"
#Include Once "src/fb_linter_boolean_replay_enums.bi"

Dim As String ModelPath = Command(1), LatestTypes()
Dim As LongInt CanonicalIds()
Dim As Long Ordinals()
If FblintValidateSchema27Metadata(ModelPath, LatestTypes(), CanonicalIds()) = 0 Then End 2
Dim As String OriginalRecords = Schema27LinePool
If BooleanReplayEnumOrdinals(Ordinals()) = 0 Then End 3
Dim As LongInt RowIndex = Schema27First("T"), SubtypeRow
Dim As Long EnumCount, TemporaryCount, NamedCount
Do While RowIndex > 0
    If Schema27Value(RowIndex, 3) = "enum" Then
        If Schema27Value(RowIndex, 18) = "compiler" Then
            EnumCount += 1
            Print "anonymous_enum_key="; BooleanReplayBindingType(RowIndex, Ordinals())
        ElseIf UCase(Schema27Value(RowIndex, 2)) = "NAMEDKEYS" Then
            If BooleanReplayBindingType(RowIndex, Ordinals()) <> Schema27Value(RowIndex, 5) Then End 4
            NamedCount += 1
        End If
    ElseIf Schema27Value(RowIndex, 3) = "variable" AndAlso Schema27Value(RowIndex, 18) = "compiler" Then
        SubtypeRow = Schema27Find("T", Schema27Value(RowIndex, 7))
        If Schema27Value(SubtypeRow, 3) = "enum" AndAlso Schema27Value(SubtypeRow, 18) = "compiler" Then
            TemporaryCount += 1
            Print "temporary_enum_key="; BooleanReplayBindingType(RowIndex, Ordinals())
        End If
    End If
    RowIndex = Schema27Rows(RowIndex).NextTag
Loop
If EnumCount <> 2 OrElse TemporaryCount <> 1 OrElse NamedCount <> 1 Then
    Print "unexpected_fixture_counts="; EnumCount; ","; TemporaryCount; ","; NamedCount
    End 5
End If
If Schema27LinePool <> OriginalRecords Then End 6
Print "ANONYMOUS_ENUM_KEYS_PASS"
End 0
' end of test_anonymous_enum_replay.bas
