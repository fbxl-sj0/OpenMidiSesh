/'
    Project: OpenSesh
    ---------------------------

    File: music_export.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: musicExport_SaveMod with OseModExportReport and bounded MOD format limits.

    Purpose:

        Declare bounded conversions from the editable MIDI document to
        interchange formats that are not part of the MIDI model itself.

    Responsibilities:

        - describe losses caused by ProTracker's four-channel limitations
        - expose a standards-compatible 31-sample ProTracker MOD writer
        - keep conversion limits visible to the application and tests

    This file intentionally does NOT contain:

        - sfxlib playback or WAV capture
        - omaGui widgets or file dialogs
        - Standard MIDI File parsing or editing
'/

#ifndef __OSE_MUSIC_EXPORT_BI__
#define __OSE_MUSIC_EXPORT_BI__

#include once "midi_model.bi"

' -------------------------------------------------------------------------
' Public conversion limits and reports
' -------------------------------------------------------------------------

Const OSE_MOD_EXPORT_CHANNELS As Integer = 4
Const OSE_MOD_EXPORT_ROWS_PER_PATTERN As Integer = 64
Const OSE_MOD_EXPORT_MAX_PATTERNS As Integer = 128
Const OSE_MOD_EXPORT_MAX_ROWS As Integer = _
    OSE_MOD_EXPORT_ROWS_PER_PATTERN * OSE_MOD_EXPORT_MAX_PATTERNS

' Logical fields only; this report is never written as a raw binary layout.
' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseModExportReport
    As Integer notesConsidered
    As Integer notesWritten
    As Integer notesDropped
    As Integer notesTruncated
    As Integer voiceSteals
    As Integer octaveFoldedNotes
    As Integer tempoEventsWritten
    As Integer tempoEventsClamped
    As Integer patternCount
    As Integer durationRows
    As String errorText
End Type

' -------------------------------------------------------------------------
' Public exporter
' -------------------------------------------------------------------------

Declare Function musicExport_SaveMod( _
    ByRef summary As MidiSummary, _
    ByVal filename As String, _
    ByRef report As OseModExportReport _
) As Integer

#endif

/' end of music_export.bi '/
