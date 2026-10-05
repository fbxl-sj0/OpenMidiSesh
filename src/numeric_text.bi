/'
    Project: OpenSesh
    ---------------------------

    File: numeric_text.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: numericText_ParseUnsigned and numericText_ParseSigned with complete-input validation.

    Purpose:

        Declare strict bounded decimal parsing for editable numeric fields.

    Responsibilities:

        - accept complete ASCII decimal representations only
        - reject overflow before arithmetic can wrap
        - preserve caller output values when parsing fails
        - support unsigned and explicitly signed field contracts

    This file intentionally does NOT contain:

        - locale-dependent number formats or floating-point parsing
        - textbox widgets, validation messages, or application policy
        - hexadecimal, exponent, or numeric-prefix compatibility
'/

#ifndef __OSE_NUMERIC_TEXT_BI__
#define __OSE_NUMERIC_TEXT_BI__

Declare Function numericText_ParseUnsigned( _
    ByVal textValue As String, _
    ByRef parsedValue As ULongInt, _
    ByVal maximumValue As ULongInt _
) As Integer

Declare Function numericText_ParseSigned( _
    ByVal textValue As String, _
    ByRef parsedValue As Integer, _
    ByVal maximumMagnitude As Integer _
) As Integer

#endif

/' end of numeric_text.bi '/
