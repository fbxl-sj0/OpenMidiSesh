' Project: OpenSesh validator regression checks
' File: tools/fblint/test_expression_provenance_cache.bas
' Purpose: Compare cached provenance with the original production traversal.
' Responsibilities: Real model validation, copied arrays, budgets and index lifetime.
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
Dim Shared As Integer FblintSemanticAuthoritative
Dim Shared As String FblintSemanticCompilerVersion
#Include Once "src/fb_linter_semantic_wire.bi"
#Include Once "src/fb_linter_semantic_schema20.bi"
#Include Once "src/fb_linter_semantic_schema27.bi"
#Include Once "src/fb_linter_expression_provenance.bi"

Const TEST_WORK_BUDGET As LongInt = 1000000

Private Sub RequireModel(ByRef ModelPath As String)
    Dim As String LatestTypes()
    Dim As LongInt CanonicalIds()
    If FblintValidateSchema27Metadata(ModelPath, LatestTypes(), CanonicalIds()) = 0 Then
        Print "Invalid compiler fixture: "; Schema27Failure
        End 1
    End If
    FblintSemanticAuthoritative = Schema27FactsComplete
    FblintSemanticCompilerVersion = Schema27Value(Schema27First("FBCSEM"), 2)
    If Schema27CurrentProducerAvailable() = 0 Then End 1
End Sub

Private Sub CompareIndex(ByVal InitialMax As LongInt = 0)
    Dim As LongInt ExpectedMax = InitialMax
    Dim As LongInt ActualMax = InitialMax
    Dim As LongInt ExpectedWork = TEST_WORK_BUDGET
    Dim As LongInt ActualWork = TEST_WORK_BUDGET
    Dim ExpectedUnevaluated() As UByte
    Dim ActualUnevaluated() As UByte
    Dim ExpectedHeads() As LongInt
    Dim ActualHeads() As LongInt
    Dim ExpectedNext() As LongInt
    Dim ActualNext() As LongInt
    ExpressionProvenanceBuildIndex ExpectedMax, ExpectedUnevaluated(), ExpectedHeads(), ExpectedNext(), ExpectedWork
    ExpressionProvenanceIndex ActualMax, ActualUnevaluated(), ActualHeads(), ActualNext(), ActualWork
    If ExpectedWork < 0 OrElse ActualWork <> ExpectedWork OrElse ActualMax <> ExpectedMax Then End 1
    For Index As LongInt = 0 To ExpectedMax
        If ActualUnevaluated(Index) <> ExpectedUnevaluated(Index) OrElse ActualHeads(Index) <> ExpectedHeads(Index) Then End 1
    Next Index
    For Index As LongInt = 0 To Schema27RowCount
        If ActualNext(Index) <> ExpectedNext(Index) Then End 1
    Next Index
    ' A consumer owns these arrays; edits must not alter the retained copy.
    ActualUnevaluated(0) = 255
    ActualHeads(0) = -1
    ActualNext(0) = -1
    ActualMax = InitialMax
    ActualWork = TEST_WORK_BUDGET
    ExpressionProvenanceIndex ActualMax, ActualUnevaluated(), ActualHeads(), ActualNext(), ActualWork
    If ActualWork <> ExpectedWork OrElse ActualMax <> ExpectedMax Then End 1
    For Index As LongInt = 0 To ExpectedMax
        If ActualUnevaluated(Index) <> ExpectedUnevaluated(Index) OrElse ActualHeads(Index) <> ExpectedHeads(Index) Then End 1
    Next Index
    For Index As LongInt = 0 To Schema27RowCount
        If ActualNext(Index) <> ExpectedNext(Index) Then End 1
    Next Index
    ' A cache hit still charges the complete original traversal cost.
    ActualMax = InitialMax
    ActualWork = TEST_WORK_BUDGET - ExpectedWork - 1
    ExpressionProvenanceIndex ActualMax, ActualUnevaluated(), ActualHeads(), ActualNext(), ActualWork
    If ActualWork >= 0 Then End 1
End Sub

Dim As String FirstModel = Command(1)
Dim As String SecondModel = Command(2)
If Len(FirstModel) = 0 OrElse Len(SecondModel) = 0 Then End 2
RequireModel FirstModel
CompareIndex
If ExpressionProvenanceCacheNonce <> Schema27IndexNonce Then End 1
CompareIndex ExpressionProvenanceCacheMax + 5
Dim As LongInt FirstNonce = Schema27IndexNonce
Dim Saved As Schema27IndexSnapshot
If Schema27SuspendIndex(Saved) = 0 Then End 1
RequireModel SecondModel
If Schema27IndexNonce = FirstNonce Then End 1
CompareIndex
Schema27ResumeIndex Saved
If Schema27IndexNonce <> FirstNonce Then End 1
CompareIndex
ResetSchema27Facts
RequireModel FirstModel
If Schema27IndexNonce = FirstNonce Then End 1
CompareIndex
' Counter exhaustion disables caching and cannot overflow or reuse a nonce.
Schema27IndexSequence = SCHEMA27_INDEX_NONCE_MAX
RequireModel SecondModel
If Schema27IndexNonce <> 0 Then End 1
CompareIndex
Print "EXPRESSION_PROVENANCE_CACHE_PASS: copies, budgets, replacement, resume, exhaustion"
End 0
' end of tools/fblint/test_expression_provenance_cache.bas
