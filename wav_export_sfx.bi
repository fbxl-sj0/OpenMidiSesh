/'
    Project: OpenSesh
    ---------------------------

    File: wav_export_sfx.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: wavExport_* capture lifecycle with OseWavExportState and duration bounds.

    Purpose:

        Declare the small state machine used to record the editor's final
        sfxlib output as a PCM WAV file.

    Responsibilities:

        - start a bounded output-side capture
        - reserve capture memory for the known timeline duration
        - finish or cancel capture without leaving stale active state
        - report output-driver underruns to the application

    This file intentionally does NOT contain:

        - MIDI scheduling or synthesizer configuration
        - microphone/input-device capture
        - omaGui widgets or file dialogs
'/

#ifndef __OSE_WAV_EXPORT_SFX_BI__
#define __OSE_WAV_EXPORT_SFX_BI__

' sfxlib retains floating-point capture samples until the final WAV is saved.
' Ten minutes of 48 kHz stereo output uses about 220 MiB, so the editor refuses
' unbounded captures that could exhaust a normal desktop process.
Const OSE_WAV_EXPORT_MAX_SECONDS As Double = 600.0
Const OSE_WAV_EXPORT_RESERVE_TAIL_SECONDS As Double = 0.10

' Logical fields only; this state is never written as a raw binary layout.
' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseWavExportState
    As Integer active
    As String filename
    As Double expectedSeconds
    As Integer sampleRate
    As ULongInt underrunsBefore
End Type

Declare Sub wavExport_Initialize(ByRef state As OseWavExportState)

Declare Function wavExport_Begin( _
    ByRef state As OseWavExportState, _
    ByVal filename As String, _
    ByVal expectedSeconds As Double, _
    ByRef errorText As String _
) As Integer

Declare Function wavExport_Finish( _
    ByRef state As OseWavExportState, _
    ByRef underrunCount As ULongInt, _
    ByRef errorText As String _
) As Integer

Declare Sub wavExport_Cancel(ByRef state As OseWavExportState)

#endif

/' end of wav_export_sfx.bi '/
