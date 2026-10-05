/'
    Project: OpenSesh
    ---------------------------

    File: numeric_text.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements numeric_text.bi; declarations there define the shared interface.

    Purpose:

        Parse bounded decimal text without accepting a valid prefix followed
        by malformed input.

    Responsibilities:

        - trim harmless leading and trailing whitespace
        - require every remaining character to belong to the decimal grammar
        - detect range overflow before multiplication and addition
        - commit output values only after the complete text is valid

    Parsing contract:

        Unsigned values contain at most twenty ASCII digits, the decimal width
        of ULongInt. Signed values contain at most nineteen digits plus one
        optional sign, covering the widest Integer representation supported by
        the maintained 64-bit targets.

    This file intentionally does NOT contain:

        - field-specific minimums, maximums, or error messages
        - Unicode digit normalization or locale-dependent separators
        - textbox or application state
'/

#lang "fb"

#include once "numeric_text.bi"

Const NUMERIC_TEXT_UNSIGNED_MAX_CHARACTERS As Integer = 20
Const NUMERIC_TEXT_SIGNED_MAX_CHARACTERS As Integer = 20


Public Function numericText_ParseUnsigned( _
    ByVal textValue As String, _
    ByRef parsedValue As ULongInt, _
    ByVal maximumValue As ULongInt _
) As Integer
    Dim As String cleanText = Trim(textValue)
    If Len(cleanText) <= 0 OrElse _
        Len(cleanText) > NUMERIC_TEXT_UNSIGNED_MAX_CHARACTERS Then
        Return 0
    End If

    Dim As ULongInt maximumQuotient = maximumValue \ 10ULL
    Dim As ULongInt maximumRemainder = maximumValue Mod 10ULL
    Dim As ULongInt workingValue
    For characterIndex As Integer = 1 To Len(cleanText)
        Dim As Integer characterCode = Asc( _
            Mid(cleanText, characterIndex, 1))
        If characterCode < 48 OrElse characterCode > 57 Then
            Return 0
        End If

        Dim As ULongInt digitValue = CULngInt(characterCode - 48)
        If workingValue > maximumQuotient OrElse _
            (workingValue = maximumQuotient AndAlso _
             digitValue > maximumRemainder) Then
            Return 0
        End If
        workingValue = workingValue * 10ULL + digitValue
    Next

    parsedValue = workingValue
    Return -1
End Function


Public Function numericText_ParseSigned( _
    ByVal textValue As String, _
    ByRef parsedValue As Integer, _
    ByVal maximumMagnitude As Integer _
) As Integer
    If maximumMagnitude < 0 Then
        Return 0
    End If

    Dim As String cleanText = Trim(textValue)
    If Len(cleanText) <= 0 OrElse _
        Len(cleanText) > NUMERIC_TEXT_SIGNED_MAX_CHARACTERS Then
        Return 0
    End If

    Dim As Integer signValue = 1
    Dim As Integer firstDigit = 1
    Dim As String signText = Left(cleanText, 1)
    If signText = "-" Then
        signValue = -1
        firstDigit = 2
    ElseIf signText = "+" Then
        firstDigit = 2
    End If
    If firstDigit > Len(cleanText) Then
        Return 0
    End If

    Dim As ULongInt boundedMaximum = CULngInt(maximumMagnitude)
    Dim As ULongInt maximumQuotient = boundedMaximum \ 10ULL
    Dim As ULongInt maximumRemainder = boundedMaximum Mod 10ULL
    Dim As ULongInt workingMagnitude
    For characterIndex As Integer = firstDigit To Len(cleanText)
        Dim As Integer characterCode = Asc( _
            Mid(cleanText, characterIndex, 1))
        If characterCode < 48 OrElse characterCode > 57 Then
            Return 0
        End If

        Dim As ULongInt digitValue = CULngInt(characterCode - 48)
        If workingMagnitude > maximumQuotient OrElse _
            (workingMagnitude = maximumQuotient AndAlso _
             digitValue > maximumRemainder) Then
            Return 0
        End If
        workingMagnitude = workingMagnitude * 10ULL + digitValue
    Next

    parsedValue = CInt(workingMagnitude) * signValue
    Return -1
End Function

/' end of numeric_text.bas '/
