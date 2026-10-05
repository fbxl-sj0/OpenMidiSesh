/'
    Project: OpenSesh
    ---------------------------

    File: wav_export_sfx.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements wav_export_sfx.bi; declarations there define the shared interface.

    Purpose:

        Adapt sfxlib's final-output recorder to a small, explicit WAV export
        lifecycle owned by the editor.

    Responsibilities:

        - validate output paths and bounded capture durations
        - reserve enough output-capture frames for the project timeline
        - stop capture before saving the stable 16-bit PCM WAV image
        - preserve the previous destination if saving or replacement fails
        - leave a reusable inactive state after success, failure, or cancel

    This file intentionally does NOT contain:

        - playback timing or MIDI note scheduling
        - microphone capture commands
        - file dialogs or application rendering
'/

#lang "fb"

#inclib "sfx" ' fblint: disable-line FBL930 REASON: The supported FreeBASIC toolchain supplies sfx on Windows and Linux.
#include once "wav_export_sfx.bi"
#include once "atomic_file_internal.bi"

#Ifndef OSE_SFX_OUTPUT_TELEMETRY_AVAILABLE
#Define OSE_SFX_OUTPUT_TELEMETRY_AVAILABLE 1
#EndIf

' sfxlib exposes these output-side routines through its opt-in raw include.
' Keeping the exact C aliases here lets this adapter remain independently
' lintable while preserving the public sfxlib ABI.
#If OSE_SFX_OUTPUT_TELEMETRY_AVAILABLE <> 0
Declare Function fb_sfxOutputSampleRate CDecl Alias "fb_sfxOutputSampleRate" () As Long
Declare Function fb_sfxOutputUnderruns CDecl Alias "fb_sfxOutputUnderruns" () As ULongInt
#EndIf
Declare Function fb_sfxOutputCaptureStart CDecl Alias "fb_sfxOutputCaptureStart" () As Long
Declare Function fb_sfxOutputCaptureReserve CDecl Alias "fb_sfxOutputCaptureReserve" (ByVal frames As Long) As Long
Declare Sub fb_sfxOutputCaptureStop CDecl Alias "fb_sfxOutputCaptureStop" ()
Declare Function fb_sfxOutputCaptureSave CDecl Alias "fb_sfxOutputCaptureSave" ( _
        ByVal filename As Const ZString Ptr _
) As Long

' -------------------------------------------------------------------------
' Output capability helpers
' -------------------------------------------------------------------------

Private Function wavExport_OutputSampleRate() As Long
#If OSE_SFX_OUTPUT_TELEMETRY_AVAILABLE <> 0
    Return fb_sfxOutputSampleRate()
#Else
    /'
        Older mobile sfxlib builds can record the final mix but do not expose
        their negotiated rate. They currently render at 48 kHz; this value is
        used only to reserve a bounded capture buffer. The recorder writes its
        own actual rate into the completed WAV header.
    '/
    Return 48000
#EndIf
End Function


Private Function wavExport_OutputUnderruns() As ULongInt
#If OSE_SFX_OUTPUT_TELEMETRY_AVAILABLE <> 0
    Return fb_sfxOutputUnderruns()
#Else
    Return 0
#EndIf
End Function

' -------------------------------------------------------------------------
' State helpers
' -------------------------------------------------------------------------

Public Sub wavExport_Initialize(ByRef state As OseWavExportState)
    Dim As OseWavExportState emptyState
    state = emptyState
End Sub


Private Sub wavExport_ClearState(ByRef state As OseWavExportState)
    state.active = 0
    state.filename = ""
    state.expectedSeconds = 0.0
    state.sampleRate = 0
    state.underrunsBefore = 0
End Sub

' -------------------------------------------------------------------------
' Capture lifecycle
' -------------------------------------------------------------------------

Public Function wavExport_Begin( _
    ByRef state As OseWavExportState, _
    ByVal filename As String, _
    ByVal expectedSeconds As Double, _
    ByRef errorText As String _
) As Integer
    errorText = ""
    filename = Trim(filename)
    If state.active <> 0 Then
        errorText = "A WAV export is already active."
        Return 0
    End If
    If filename = "" Then
        errorText = "No WAV output filename was supplied."
        Return 0
    End If
    If Len(filename) > ATOMIC_FILE_MAX_PATH_BYTES OrElse _
        InStr(filename, Chr(0)) > 0 Then
        errorText = "The WAV output filename is invalid."
        Return 0
    End If
    If expectedSeconds <> expectedSeconds Then
        errorText = "The WAV capture duration is invalid."
        Return 0
    End If
    If expectedSeconds <= 0.0 Then
        errorText = "The project timeline is empty."
        Return 0
    End If
    If expectedSeconds > OSE_WAV_EXPORT_MAX_SECONDS Then
        errorText = "WAV export is limited to ten minutes per render."
        Return 0
    End If

    Dim As Long sampleRate = wavExport_OutputSampleRate()
    If sampleRate <= 0 Then
        errorText = "sfxlib could not initialize an output driver."
        Return 0
    End If

    Dim As Double reserveSeconds = expectedSeconds + _
        OSE_WAV_EXPORT_RESERVE_TAIL_SECONDS
    Dim As Double exactReserveFrames = reserveSeconds * CDbl(sampleRate)
    If exactReserveFrames <= 0.0 OrElse exactReserveFrames > 2147483647.0 Then
        errorText = "The WAV capture frame count is outside sfxlib's limits."
        Return 0
    End If

    If fb_sfxOutputCaptureStart() <> 0 Then
        errorText = "sfxlib could not start final-output capture."
        Return 0
    End If
    state.active = -1

    Dim As Long reserveFrames = CLng(Int(exactReserveFrames + 0.5))
    If fb_sfxOutputCaptureReserve(reserveFrames) <> 0 Then
        fb_sfxOutputCaptureStop()
        wavExport_ClearState state
        errorText = "sfxlib could not reserve the WAV capture buffer."
        Return 0
    End If

    state.filename = filename
    state.expectedSeconds = expectedSeconds
    state.sampleRate = sampleRate
    state.underrunsBefore = wavExport_OutputUnderruns()
    Return -1
End Function


Public Function wavExport_Finish( _
    ByRef state As OseWavExportState, _
    ByRef underrunCount As ULongInt, _
    ByRef errorText As String _
) As Integer
    underrunCount = 0
    errorText = ""
    If state.active = 0 Then
        errorText = "No WAV export is active."
        Return 0
    End If

    Dim As String outputFilename = state.filename
    Dim As ULongInt underrunsAfter = wavExport_OutputUnderruns()
    If underrunsAfter >= state.underrunsBefore Then
        underrunCount = underrunsAfter - state.underrunsBefore
    End If

    fb_sfxOutputCaptureStop()
    state.active = 0
    /'
        The sfxlib saver opens its path with truncation and can fail after a
        partial write. Save beside the destination, then commit through the
        same atomic replacement primitive used by document persistence. This
        avoids copying a long capture into another full-size memory buffer.
    '/
    Dim As String temporaryFilename
    If atomicFile_TemporaryName(outputFilename, temporaryFilename) = 0 Then
        wavExport_ClearState state
        errorText = "Could not prepare the WAV output file."
        Return 0
    End If
    If fb_sfxOutputCaptureSave(StrPtr(temporaryFilename)) <> 0 Then
        atomicFile_RemoveTemporary temporaryFilename
        wavExport_ClearState state
        errorText = "sfxlib could not write the captured WAV file."
        Return 0
    End If
    If atomicFile_Replace(temporaryFilename, outputFilename) = 0 Then
        atomicFile_RemoveTemporary temporaryFilename
        wavExport_ClearState state
        errorText = "Could not replace the WAV destination."
        Return 0
    End If

    wavExport_ClearState state
    Return -1
End Function


Public Sub wavExport_Cancel(ByRef state As OseWavExportState)
    If state.active <> 0 Then
        fb_sfxOutputCaptureStop()
    End If
    wavExport_ClearState state
End Sub

/' end of wav_export_sfx.bas '/
