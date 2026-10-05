/'
    Project: OpenSesh
    ---------------------------

    File: version.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: OSE_VERSION_*, OSE_PRODUCT_NAME, OSE_COPYRIGHT_TEXT, and OSE_LICENSE_EXPRESSION constants.

    Purpose:

        Define the public product identity used by the application, tests,
        release documentation, and platform metadata.

    Responsibilities:

        - provide bounded numeric version components
        - provide the display and copyright strings shown to users
        - identify the project's SPDX license expression

    This file intentionally does NOT contain:

        - build timestamps or machine-specific identifiers
        - operating-system resource syntax
        - release-channel update logic
'/

#ifndef __OSE_VERSION_BI__
#define __OSE_VERSION_BI__

Const OSE_VERSION_MAJOR As Integer = 0
Const OSE_VERSION_MINOR As Integer = 9
Const OSE_VERSION_PATCH As Integer = 0
Const OSE_VERSION_BUILD As Integer = 0
Const OSE_VERSION_TEXT As String = "0.9.0-dev"
Const OSE_PRODUCT_NAME As String = "OpenSesh"
Const OSE_COPYRIGHT_TEXT As String = _
    "Copyright (C) 2026 OpenSesh contributors"
Const OSE_LICENSE_EXPRESSION As String = "GPL-3.0-or-later"

#endif

/' end of version.bi '/
