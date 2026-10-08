' Project: OpenSesh validator regression checks
' File: tools/fblint/test_field_cache.bas
' Purpose: Compare cached field boundaries with the original production reader.
' Responsibilities: Every field, memory caps, replacement models and snapshots.
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

Private Function MeasureFields(ByVal DirectRead As Integer, ByRef Checksum As LongInt) As Double
    Const REPEATS As Integer = 20
    Dim As Double StartedAt = Timer
    Checksum = 0
    For RepeatIndex As Integer = 1 To REPEATS
        For RowIndex As Long = 1 To Schema27RowCount
            Dim As String LineText = Schema27LineText(RowIndex)
            For FieldIndex As Integer = 0 To FblintTsvFieldCount(LineText) - 1
                If DirectRead Then
                    Checksum += Len(Schema27Value(RowIndex, FieldIndex))
                Else
                    Checksum += Len(Schema27UncachedValue(RowIndex, FieldIndex))
                End If
            Next FieldIndex
        Next RowIndex
    Next RepeatIndex
    Dim As Double Seconds = Timer - StartedAt
    ' Timer wraps at midnight; this is elapsed time, not a clock timestamp.
    If Seconds < 0 Then Seconds += 86400
    Return Seconds
End Function


Private Sub RequireModel(ByRef ModelPath As String)
    Dim As String LatestTypes()
    Dim As LongInt CanonicalIds()
    If Len(ModelPath) = 0 OrElse FblintValidateSchema27Metadata(ModelPath, LatestTypes(), CanonicalIds()) = 0 Then End 1
End Sub

Private Sub CompareFields()
    If Schema27Value(0, 0) <> "" OrElse Schema27Value(Schema27RowCount + 1, 0) <> "" Then End 1
    For RowIndex As Long = 1 To Schema27RowCount
        Dim As String LineText = Schema27LineText(RowIndex)
        If Schema27Value(RowIndex, -1) <> "" Then End 1
        For FieldIndex As Integer = 0 To FblintTsvFieldCount(LineText) + 1
            If Schema27Value(RowIndex, FieldIndex) <> Schema27UncachedValue(RowIndex, FieldIndex) Then
                Print "FIELD_CACHE_FAIL: row="; RowIndex; ", field="; FieldIndex
                End 1
            End If
        Next FieldIndex
    Next RowIndex
    If Schema27FieldCacheDisabled = 0 Then
        Dim As LongInt RetainedBytes = (CLngInt(Schema27FieldCacheRows) + 1) * Sizeof(Long) + _
            CLngInt(Schema27FieldCacheCapacity) * Sizeof(ULong)
        If RetainedBytes > Schema27FieldCacheBudget OrElse RetainedBytes > SCHEMA27_FIELD_CACHE_BYTES Then End 1
        If Schema27FieldCacheCapacity > 0 AndAlso Schema27FieldCacheUsed > Schema27FieldCacheCapacity Then End 1
    End If
End Sub

Dim As String FirstModel = Command(1), SecondModel = Command(2)
Dim Saved As Schema27IndexSnapshot
For ModelIndex As Integer = 1 To 2
    Dim As String ModelPath = IIf(ModelIndex = 1, FirstModel, SecondModel)
    RequireModel ModelPath
    ' A cap too small for the map, a filled small cache, and an out-of-range
    ' cap must all preserve uncached reads rather than accept partial facts.
    For PolicyIndex As Integer = 0 To 4
        Select Case PolicyIndex
        Case 0: Schema27FieldCacheBudget = 0
        Case 1: Schema27FieldCacheBudget = 1024
        Case 2: Schema27FieldCacheBudget = (CLngInt(Schema27RowCount) + 1) * Sizeof(Long) + 1024
        Case 3: Schema27FieldCacheBudget = SCHEMA27_FIELD_CACHE_BYTES + 1
        Case 4: Schema27FieldCacheBudget = SCHEMA27_FIELD_CACHE_BYTES
        End Select
        CompareFields
    Next PolicyIndex
    Dim As LongInt OriginalChecksum, CachedChecksum
    Dim As Double OriginalSeconds = MeasureFields(0, OriginalChecksum)
    Dim As Double CachedSeconds = MeasureFields(-1, CachedChecksum)
    If OriginalChecksum <> CachedChecksum Then End 1
    Print "FIELD_CACHE_TIMING: rows="; Schema27RowCount; ", original="; OriginalSeconds; ", cached="; CachedSeconds
    If ModelIndex = 1 AndAlso Schema27SuspendIndex(Saved) = 0 Then End 1
Next ModelIndex
Schema27ResumeIndex Saved
CompareFields
If Schema27FieldCacheOwner <> Schema27IndexNonce Then End 1
' Exhaustion disables derived caches without wrapping an index identity.
Schema27IndexSequence = SCHEMA27_INDEX_NONCE_MAX
RequireModel SecondModel
If Schema27IndexNonce <> 0 Then End 1
CompareFields
Print "FIELD_CACHE_PASS: every field, missing fields, budgets, replacement, resume, exhaustion"
End 0
' end of tools/fblint/test_field_cache.bas
