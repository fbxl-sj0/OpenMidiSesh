/'
    Project: OpenSesh
    ----------------------------

    File: document_save_routing.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: documentSave_SelectTarget and OSE_DOCUMENT_SAVE_* constants for editor Save routing.

    Purpose:

        Select the Save destination while respecting an open project.

    Responsibilities:

        - keep an open project as the destination for Save
        - use command-line MIDI output only when no project is open
        - request a picker when neither destination is available

    This file intentionally does NOT contain:

        - filesystem operations
        - MIDI serialization or project persistence
        - GUI callbacks
'/

#ifndef __OSE_DOCUMENT_SAVE_ROUTING_BI__
#define __OSE_DOCUMENT_SAVE_ROUTING_BI__

Const OSE_DOCUMENT_SAVE_PICKER As Integer = 0
Const OSE_DOCUMENT_SAVE_PROJECT As Integer = 1
Const OSE_DOCUMENT_SAVE_MIDI As Integer = 2

Private Function documentSave_SelectTarget( _
    ByRef projectFilename As String, _
    ByRef commandLineMidiFilename As String _
) As Integer
    If Trim(projectFilename) <> "" Then
        Return OSE_DOCUMENT_SAVE_PROJECT
    End If
    If Trim(commandLineMidiFilename) <> "" Then
        Return OSE_DOCUMENT_SAVE_MIDI
    End If
    Return OSE_DOCUMENT_SAVE_PICKER
End Function

#endif

/' end of document_save_routing.bi '/
