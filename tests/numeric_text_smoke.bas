/'
    Project: OpenSesh
    ---------------------------

    File: numeric_text_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove that editable numeric text is accepted only when the complete
        bounded decimal representation is valid.

    Responsibilities:

        - cover exact unsigned and signed range boundaries
        - reject numeric prefixes, separators, signs, and oversized text
        - prove the zero maximum does not underflow during range checking
        - prove every rejection preserves the caller's output value

    This file intentionally does NOT contain:

        - textbox widgets or graphical input simulation
        - field-specific status messages
        - locale-dependent or floating-point syntax
'/

#lang "fb"

#include once "../src/numeric_text.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "ERROR: "; messageText
    End 1
End Sub


Private Sub test_UnsignedAccepted( _
    ByVal textValue As String, _
    ByVal maximumValue As ULongInt, _
    ByVal expectedValue As ULongInt, _
    ByRef caseCount As Integer _
)
    Dim As ULongInt parsedValue = 123456789ULL
    If numericText_ParseUnsigned( _
        textValue, parsedValue, maximumValue) = 0 OrElse _
        parsedValue <> expectedValue Then _
        test_Fail "valid unsigned decimal was not preserved"
    caseCount += 1
End Sub


Private Sub test_UnsignedRejected( _
    ByVal textValue As String, _
    ByVal maximumValue As ULongInt, _
    ByRef caseCount As Integer _
)
    Const SENTINEL As ULongInt = 987654321ULL
    Dim As ULongInt parsedValue = SENTINEL
    If numericText_ParseUnsigned( _
        textValue, parsedValue, maximumValue) <> 0 OrElse _
        parsedValue <> SENTINEL Then _
        test_Fail "invalid unsigned decimal changed caller state"
    caseCount += 1
End Sub


Private Sub test_SignedAccepted( _
    ByVal textValue As String, _
    ByVal maximumMagnitude As Integer, _
    ByVal expectedValue As Integer, _
    ByRef caseCount As Integer _
)
    Dim As Integer parsedValue = 123456789
    If numericText_ParseSigned( _
        textValue, parsedValue, maximumMagnitude) = 0 OrElse _
        parsedValue <> expectedValue Then _
        test_Fail "valid signed decimal was not preserved"
    caseCount += 1
End Sub


Private Sub test_SignedRejected( _
    ByVal textValue As String, _
    ByVal maximumMagnitude As Integer, _
    ByRef caseCount As Integer _
)
    Const SENTINEL As Integer = 987654321
    Dim As Integer parsedValue = SENTINEL
    If numericText_ParseSigned( _
        textValue, parsedValue, maximumMagnitude) <> 0 OrElse _
        parsedValue <> SENTINEL Then _
        test_Fail "invalid signed decimal changed caller state"
    caseCount += 1
End Sub


Dim As Integer acceptedCases
Dim As Integer rejectedCases

test_UnsignedAccepted "0", 0ULL, 0ULL, acceptedCases
test_UnsignedAccepted " 42 ", 42ULL, 42ULL, acceptedCases
test_UnsignedAccepted "00042", 100ULL, 42ULL, acceptedCases
test_UnsignedAccepted "400", 400ULL, 400ULL, acceptedCases
test_UnsignedAccepted "18446744073709551615", _
    &HFFFFFFFFFFFFFFFFULL, &HFFFFFFFFFFFFFFFFULL, acceptedCases

Dim As String unsignedRejections(0 To 10) = { _
    "", " ", "+1", "-1", "1x", "1.0", "1 0", "&H10", _
    "401", "18446744073709551616", "000000000000000000000" _
}
Dim As ULongInt unsignedMaximums(0 To 10) = { _
    100ULL, 100ULL, 100ULL, 100ULL, 100ULL, 100ULL, 100ULL, 100ULL, _
    400ULL, &HFFFFFFFFFFFFFFFFULL, &HFFFFFFFFFFFFFFFFULL _
}
For caseIndex As Integer = 0 To UBound(unsignedRejections)
    test_UnsignedRejected unsignedRejections(caseIndex), _
        unsignedMaximums(caseIndex), rejectedCases
Next
test_UnsignedRejected "1", 0ULL, rejectedCases

test_SignedAccepted "0", 0, 0, acceptedCases
test_SignedAccepted "-0", 0, 0, acceptedCases
test_SignedAccepted "+7", 7, 7, acceptedCases
test_SignedAccepted " -7 ", 7, -7, acceptedCases
test_SignedAccepted "2147483647", 2147483647, _
    2147483647, acceptedCases
test_SignedAccepted "-2147483647", 2147483647, _
    -2147483647, acceptedCases

Dim As String signedRejections(0 To 11) = { _
    "", " ", "+", "-", "++1", "--1", "+-1", "1x", "1.0", _
    "8", "2147483648", "000000000000000000000" _
}
Dim As Integer signedMaximums(0 To 11) = { _
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 2147483647, 2147483647 _
}
For caseIndex As Integer = 0 To UBound(signedRejections)
    test_SignedRejected signedRejections(caseIndex), _
        signedMaximums(caseIndex), rejectedCases
Next
test_SignedRejected "0", -1, rejectedCases

Print "numeric_text=ok"
Print "accepted_cases="; acceptedCases
Print "rejected_cases="; rejectedCases
End 0

/' end of numeric_text_smoke.bas '/
