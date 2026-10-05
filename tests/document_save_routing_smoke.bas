/'
    Project: OpenSesh
    ----------------------------

    File: tests/document_save_routing_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; host-independent test.

    Module API: no public application API; executable Save-routing test fixture.

    Purpose:

        Keep the open-project Save route ahead of a command-line MIDI path.

    Responsibilities:

        - check project-save priority over the command-line MIDI path
        - check MIDI and picker fallbacks for empty project paths
        - report assertion failures through the process exit status

    This file intentionally does NOT contain:

        - filesystem writes or project-file mutation
        - MIDI device access or GUI callbacks
'/

#lang "fb"

#include once "../src/document_save_routing.bi"

Dim As String projectFilename = "song.ose"
Dim As String commandLineMidiFilename = "render.mid"
If documentSave_SelectTarget(projectFilename, commandLineMidiFilename) <> _
    OSE_DOCUMENT_SAVE_PROJECT Then
    Print "FAIL: an open project did not own the Save destination"
    End 1
End If

projectFilename = ""
If documentSave_SelectTarget(projectFilename, commandLineMidiFilename) <> _
    OSE_DOCUMENT_SAVE_MIDI Then
    Print "FAIL: command-line MIDI fallback was ignored without a project"
    End 1
End If

commandLineMidiFilename = ""
If documentSave_SelectTarget(projectFilename, commandLineMidiFilename) <> _
    OSE_DOCUMENT_SAVE_PICKER Then
    Print "FAIL: an untitled document did not request a Save picker"
    End 1
End If

projectFilename = "  "
commandLineMidiFilename = "  "
If documentSave_SelectTarget(projectFilename, commandLineMidiFilename) <> _
    OSE_DOCUMENT_SAVE_PICKER Then
    Print "FAIL: blank paths were treated as usable Save destinations"
    End 1
End If

Print "document_save_routing=ok"
Print "project_priority=ok"
Print "midi_fallback=ok"
Print "picker_fallback=ok"
End 0

/' end of tests/document_save_routing_smoke.bas '/
