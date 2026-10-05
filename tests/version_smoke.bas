/'
    Project: OpenSesh
    ---------------------------

    File: tests/version_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Keep the public version constants internally consistent and bounded.

    Responsibilities:

        - validate numeric version component ranges
        - validate the display version and public identity strings
        - reject a release build that has lost its license expression

    This file intentionally does NOT contain:

        - Windows VERSIONINFO inspection
        - build timestamps
        - network update checks
'/

#lang "fb"

#include once "../version.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


If OSE_VERSION_MAJOR < 0 OrElse OSE_VERSION_MAJOR > 65535 OrElse _
    OSE_VERSION_MINOR < 0 OrElse OSE_VERSION_MINOR > 65535 OrElse _
    OSE_VERSION_PATCH < 0 OrElse OSE_VERSION_PATCH > 65535 OrElse _
    OSE_VERSION_BUILD < 0 OrElse OSE_VERSION_BUILD > 65535 Then _
    test_Fail "numeric version component is outside VERSIONINFO bounds"

Dim As String numericVersion = Str(OSE_VERSION_MAJOR) + "." + _
    Str(OSE_VERSION_MINOR) + "." + Str(OSE_VERSION_PATCH)
If Left(OSE_VERSION_TEXT, Len(numericVersion)) <> numericVersion Then _
    test_Fail "display version does not begin with its numeric components"
If OSE_PRODUCT_NAME <> "OpenSesh" Then _
    test_Fail "unexpected product name"
If InStr(OSE_COPYRIGHT_TEXT, "2026") = 0 Then _
    test_Fail "copyright string does not identify the release year"
If OSE_LICENSE_EXPRESSION <> "GPL-3.0-or-later" Then _
    test_Fail "unexpected SPDX license expression"

Print "version=ok"
Print "product="; OSE_PRODUCT_NAME
Print "display_version="; OSE_VERSION_TEXT
End 0

/' end of tests/version_smoke.bas '/
