/'
    Project: fb-linter procedure input regression
    File: test_procedure_keyword_fields.bas
    Purpose: Distinguish keyword-named fields from named procedure headers.
    Responsibilities: Exercise unions, member prototypes and definitions.
    Targets: fb dialect, native win64, strict semantic profile.
    Module API: KeywordFields and KeywordContainer are fixture-local types.
    This file intentionally does NOT contain:
        Windows header imports or UI execution.
'/
#Lang "fb"
Const EXPECTED_VALUE As Long = 7
Union KeywordFields
    Function As Long
    Sub As Long
End Union
Type KeywordContainer
    Fields As KeywordFields
    Declare Function Value() As Long
End Type
Function KeywordContainer.Value() As Long
    Return This.Fields.Function
End Function
Private Function ModuleValue() As Long
    Return EXPECTED_VALUE
End Function
Dim As KeywordContainer Sample
Sample.Fields.Function = ModuleValue()
If Sample.Value() <> EXPECTED_VALUE Then End 1
End 0
' end of test_procedure_keyword_fields.bas
