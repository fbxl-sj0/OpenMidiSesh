/'
    Project: OpenSesh
    ---------------------------

    File: sfxlib_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Exercise the sfxlib commands used by the editor's software-synth
        transport without opening a window or requiring an audio device.

    Responsibilities:

        - configure one generated wave, envelope, and instrument
        - start SOUND and NOISE voices with channel controls
        - save and validate a short capture when the backend exposes input
        - stop the test voices and report a successful command path

    This file intentionally does NOT contain:

        - MIDI parsing or file output
        - omaGui widgets
        - the editor's playback clock
        - sample-based instrument assets
'/

#lang "fb"

#include once "../src/sfx_runtime.bi"

Dim As LongInt captureBytes = 0

Private Sub test_Fail(ByVal messageText As String)
    CAPTURE STOP
    SFX STOP
    sfxRuntime_Shutdown()
    Print "ERROR: "; messageText
    End 1
End Sub


Print "sfxlib software-synth smoke test"

wave 0, 2
envelope 0, 0.005, 0.12, 0.45, 0.12
instrument 0, 0, 0
volume 0, 0.35
pan 0, -0.25
sound 0, 440, 0.05, 0.25

noise 1, 0.05, 0.12
SFX STOP CHANNEL, 0
SFX STOP CHANNEL, 1

Dim As Integer captureResult = CAPTURE START()
Dim As Integer captureSaveChecks
If captureResult = 0 Then
    ' Backends may fill their input buffer on a 10 to 20 ms callback. One
    ' second comfortably crosses several callbacks without making this smoke
    ' test a long-running recording.
    Sleep 1000
    Dim As String captureFilename = Trim(Command(1))
    Dim As Integer saveResult = -1
    If captureFilename <> "" Then
        saveResult = CAPTURE SAVE(captureFilename)
    End If
    CAPTURE STOP
    If captureFilename <> "" AndAlso saveResult = 0 Then
        Dim As Integer fileNumber = FreeFile()
        If Open(captureFilename For Binary Access Read As #fileNumber) <> 0 Then
            test_Fail "saved sfxlib capture could not be reopened"
        End If
        Dim As String waveHeader = Space(12)
        Get #fileNumber, 1, waveHeader
        captureBytes = Lof(fileNumber)
        Close #fileNumber
        If captureBytes <= 44 OrElse Left(waveHeader, 4) <> "RIFF" OrElse _
            Mid(waveHeader, 9, 4) <> "WAVE" Then
            test_Fail "saved sfxlib capture is not a bounded RIFF/WAVE file"
        End If
        captureSaveChecks = 1
        Print "sfxlib_capture=available"
    Else
        Print "sfxlib_capture=unavailable"
    End If
Else
    Print "sfxlib_capture=unavailable"
End If

sfxRuntime_Shutdown()
sfxRuntime_Shutdown()
Print "sfxlib_smoke=ok"
Print "capture_save_checks="; captureSaveChecks
End 0

/' end of sfxlib_smoke.bas '/
