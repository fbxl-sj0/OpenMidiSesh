' Project: OpenSesh validator regression checks
' File: tools/fblint/test_boolean_index_cache.bas
' Purpose: Compare retained Boolean scratch with the original production pass.
' Responsibilities: Scratch ownership, replacement models and snapshot lifetime.
' Targets: FreeBASIC fb dialect, native schema-27 consumer.
' Module API: Two genuine compiler model paths on the command line.
' This file intentionally does NOT construct semantic records or infer source types.
#Lang "fb"
#Include Once "test_fixture_symbol_classes.bi"
Const FBLINT_MAX_SEMANTIC_SYMBOL_TYPES As LongInt = 250000
Const FBLINT_MAX_SEMANTIC_MODEL_IDENTITIES As LongInt = 1000000
Const FBLINT_MAX_SEMANTIC_PROCEDURE_PARAMETERS As LongInt = 1024
Const FBLINT_SEMANTIC_MAX_INTEGER As LongInt = 4294967295
Const DECIMAL_RADIX As Integer = 10
Const FBLINT_SEMANTIC_AST_CODES_VERSION As String = "1.20.4"
' Compiler AST classes pinned by the production semantic reader for 1.20.4.
Const FBLINT_SEMANTIC_NODE_CLASS_CONST As LongInt = 16
Const FBLINT_SEMANTIC_NODE_CLASS_VAR As LongInt = 17
Dim Shared As Integer FblintSemanticAuthoritative
Dim Shared As String FblintSemanticCompilerVersion
#Include Once "src/fb_linter_semantic_wire.bi"
#Include Once "src/fb_linter_semantic_schema20.bi"
#Include Once "src/fb_linter_semantic_schema27.bi"
#Include Once "src/fb_linter_boolean_model.bi"

Private Sub RequireModel(ByRef ModelPath As String)
    Dim As String LatestTypes()
    Dim As LongInt CanonicalIds()
    If Len(ModelPath) = 0 OrElse FblintValidateSchema27Metadata(ModelPath, LatestTypes(), CanonicalIds()) = 0 Then End 1
    FblintSemanticAuthoritative = Schema27FactsComplete
    FblintSemanticCompilerVersion = Schema27Value(Schema27First("FBCSEM"), 2)
End Sub

Private Sub CompareIndex()
    Dim Expected() As BooleanExpressionWork
    ReDim Expected(0 To Schema27RowCount)
    Dim As String FailureText
    If BuildCompilerBooleanExpressions(FailureText) = 0 Then
        Print "BOOLEAN_INDEX_CACHE_FAIL: original pass: "; FailureText
        End 1
    End If
    For RowIndex As Long = 1 To Schema27RowCount
        Expected(RowIndex).WorkCount = Schema27Rows(RowIndex).WorkCount
        Expected(RowIndex).WorkValue = Schema27Rows(RowIndex).WorkValue
        Expected(RowIndex).WorkOrdinal = Schema27Rows(RowIndex).WorkOrdinal
    Next RowIndex
    ' The first call publishes a copy; the second must restore scratch after
    ' another family overwrites it. ST count and ordinal belong to that family.
    For Attempt As Integer = 1 To 2
        Dim As LongInt RowIndex = Schema27First("E")
        Do While RowIndex > 0
            Schema27Rows(RowIndex).WorkCount = 123
            Schema27Rows(RowIndex).WorkValue = 456
            Schema27Rows(RowIndex).WorkOrdinal = 789
            RowIndex = Schema27Rows(RowIndex).NextTag
        Loop
        RowIndex = Schema27First("ST")
        Do While RowIndex > 0
            Schema27Rows(RowIndex).WorkCount = 123
            Schema27Rows(RowIndex).WorkValue = 456
            Schema27Rows(RowIndex).WorkOrdinal = 789
            RowIndex = Schema27Rows(RowIndex).NextTag
        Loop
        FailureText = "stale failure"
        If IndexCompilerBooleanExpressions(FailureText) = 0 OrElse FailureText <> "" Then End 1
        For Index As Long = 1 To Schema27RowCount
            Select Case Schema27Value(Index, 0)
            Case "E"
                If Schema27Rows(Index).WorkCount <> Expected(Index).WorkCount OrElse _
                   Schema27Rows(Index).WorkValue <> Expected(Index).WorkValue OrElse _
                   Schema27Rows(Index).WorkOrdinal <> Expected(Index).WorkOrdinal Then End 1
            Case "ST"
                If Schema27Rows(Index).WorkCount <> 123 OrElse Schema27Rows(Index).WorkOrdinal <> 789 OrElse _
                   Schema27Rows(Index).WorkValue <> Expected(Index).WorkValue Then End 1
            Case Else
                If Schema27Rows(Index).WorkCount <> Expected(Index).WorkCount OrElse _
                   Schema27Rows(Index).WorkValue <> Expected(Index).WorkValue OrElse _
                   Schema27Rows(Index).WorkOrdinal <> Expected(Index).WorkOrdinal Then End 1
            End Select
        Next Index
    Next Attempt
    Dim As LongInt RetainedBytes = (CLngInt(BooleanIndexExpressionCount) + 1) * Sizeof(BooleanExpressionWork) + _
        (CLngInt(BooleanIndexStatementCount) + 1) * Sizeof(BooleanStatementWork)
    If RetainedBytes > BOOLEAN_INDEX_CACHE_BYTES Then End 1
End Sub

Dim As String FirstModel = Command(1), SecondModel = Command(2)
Dim Saved As Schema27IndexSnapshot
RequireModel FirstModel
CompareIndex
If BooleanIndexOwner <> Schema27IndexNonce Then End 1
Dim As LongInt FirstNonce = Schema27IndexNonce
If Schema27SuspendIndex(Saved) = 0 Then End 1
RequireModel SecondModel
If Schema27IndexNonce = FirstNonce Then End 1
CompareIndex
Schema27ResumeIndex Saved
CompareIndex
If BooleanIndexOwner <> FirstNonce Then End 1
' Unknown producers and exhausted identities use the unchanged original pass.
BooleanIndexOwner = 0
FblintSemanticCompilerVersion = "unknown"
CompareIndex
If BooleanIndexOwner <> 0 Then End 1
Schema27IndexSequence = SCHEMA27_INDEX_NONCE_MAX
RequireModel SecondModel
If Schema27IndexNonce <> 0 Then End 1
CompareIndex
If BooleanIndexOwner <> 0 Then End 1
Print "BOOLEAN_INDEX_CACHE_PASS: scratch, ownership, replacement, resume, producer, exhaustion"
End 0
' end of tools/fblint/test_boolean_index_cache.bas
