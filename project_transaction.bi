/'
    Project: OpenSesh
    ---------------------------

    File: project_transaction.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: projectTransaction_SavePair/Recover; fault injection only in the explicit test build.

    Purpose:

        Declare recoverable two-file commits for a project container and its
        sibling Standard MIDI File.

    Responsibilities:

        - commit pre-serialized sibling files as one recoverable operation
        - restore exact prior bytes when either commit fails
        - recover interrupted prepared or completed transactions on restart
        - expose deterministic interruption injection to the test build

    This file intentionally does NOT contain:

        - MIDI or project serialization
        - application status messages
        - user-interface code
'/

#ifndef __OSE_PROJECT_TRANSACTION_BI__
#define __OSE_PROJECT_TRANSACTION_BI__

Declare Function projectTransaction_SavePair( _
    ByVal midiFilename As String, _
    ByRef midiData As String, _
    ByVal projectFilename As String, _
    ByRef projectData As String, _
    ByRef errorText As String _
) As Integer

Declare Function projectTransaction_Recover( _
    ByVal projectFilename As String, _
    ByRef errorText As String _
) As Integer

#If Defined(OSE_PROJECT_TRANSACTION_TESTING)

Const OSE_PROJECT_TRANSACTION_FAIL_NONE As Integer = 0
Const OSE_PROJECT_TRANSACTION_FAIL_FIRST_COMMIT As Integer = 1
Const OSE_PROJECT_TRANSACTION_FAIL_SECOND_COMMIT As Integer = 2
Const OSE_PROJECT_TRANSACTION_INTERRUPT_AFTER_FIRST As Integer = 3
Const OSE_PROJECT_TRANSACTION_INTERRUPT_AFTER_SECOND As Integer = 4
Const OSE_PROJECT_TRANSACTION_INTERRUPT_AFTER_COMMITTED As Integer = 5

Declare Sub projectTransaction_TestInject(ByVal injectionMode As Integer)

#EndIf

#endif

/' end of project_transaction.bi '/
