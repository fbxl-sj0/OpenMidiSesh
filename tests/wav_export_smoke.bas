/'
    Project: OpenSesh
    ---------------------------

    File: wav_export_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Module API: Test executable accepting one output WAV path; uses sfxlib
        foreground-feed entry points to drive capture with the null driver.

    Purpose:

        Verify the sfxlib final-output capture wrapper with a generated tone
        and a hardware-independent null output driver.

    Responsibilities:

        - reject an unbounded capture before sfxlib state changes
        - capture one generated software-synth tone
        - validate the resulting 16-bit PCM WAV through the project parser
        - require a meaningful PCM peak so a silent WAV cannot pass

    This file intentionally does NOT contain:

        - microphone/input-device capture
        - MIDI playback scheduling
        - omaGui widgets
'/

#lang "fb"

#include once "../audio_tracks.bi"
#include once "../wav_export_sfx.bi"

' The null driver has no hardware callback. These public sfxlib runtime hooks
' let the smoke test advance exactly one quarter-second of mixer output.
Declare Sub fb_sfxUpdate CDecl Alias "fb_sfxUpdate" (ByVal frames As Long)
Declare Sub fb_sfxForegroundFeedBegin CDecl _
    Alias "fb_sfxForegroundFeedBegin" ()
Declare Sub fb_sfxForegroundFeedEnd CDecl _
    Alias "fb_sfxForegroundFeedEnd" ()

Private Sub test_Fail(ByVal messageText As String)
    Print "ERROR: "; messageText
    End 1
End Sub


Private Function test_WavePeak(ByVal filename As String) As Integer
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then
        Return -1
    End If

    ' sfxlib's output saver writes a canonical 44-byte PCM header. The project
    ' parser validates that container before this helper examines its samples.
    Dim As LongInt fileLength = Lof(fileNumber)
    If fileLength <= 44 Then
        Close #fileNumber
        Return -1
    End If

    Dim As Integer peakValue
    Dim As Short sampleValue
    Seek #fileNumber, 45
    While Loc(fileNumber) + 1 < fileLength
        Get #fileNumber, , sampleValue
        Dim As Integer absoluteValue = CInt(sampleValue)
        If absoluteValue < 0 Then
            absoluteValue = -absoluteValue
        End If
        If absoluteValue > peakValue Then
            peakValue = absoluteValue
        End If
    Wend
    Close #fileNumber
    Return peakValue
End Function


Dim As String outputFilename = Trim(Command(1))
If outputFilename = "" Then
    Print "usage: wav_export_smoke.exe <output.wav>"
    End 2
End If

Dim As OseWavExportState exportState
wavExport_Initialize exportState
Dim As String errorText
If wavExport_Begin(exportState, outputFilename, _
    OSE_WAV_EXPORT_MAX_SECONDS + 1.0, errorText) <> 0 OrElse _
    exportState.active <> 0 Then _
    test_Fail "oversized capture was accepted"

' fblint: disable-next-line FBL407,FBL-NUM-013 REASON: the integer return value is tested; the Real duration is not compared.
If wavExport_Begin(exportState, outputFilename, 0.05, errorText) = 0 Then _
    test_Fail "cancellation fixture could not start"
wavExport_Cancel exportState
Dim As ULongInt cancelledUnderruns
If exportState.active <> 0 OrElse exportState.filename <> "" OrElse _
    exportState.sampleRate <> 0 OrElse _
    wavExport_Finish(exportState, cancelledUnderruns, errorText) <> 0 Then _
    test_Fail "cancel did not clear capture state"

wave 0, 2
envelope 0, 0.005, 0.08, 0.55, 0.08
instrument 0, 0, 0
volume 0, 0.35
pan 0, 0.0

' The tested procedure returns Integer; the decimal argument confuses the
' linter's expression-only floating-equality heuristic.
' fblint: disable-next-line FBL407,FBL-NUM-013 REASON: The integer success result is compared; the floating duration argument is not compared.
If wavExport_Begin(exportState, outputFilename, 0.25, errorText) = 0 Then _
    test_Fail "WAV capture could not start: " + errorText
fb_sfxForegroundFeedBegin()
' Match the editor's Music > Audition A4 command exactly.
sound 440, 0.12
fb_sfxUpdate exportState.sampleRate \ 4
SFX STOP CHANNEL, 0
fb_sfxForegroundFeedEnd()

Dim As ULongInt underrunCount
If wavExport_Finish(exportState, underrunCount, errorText) = 0 Then _
    test_Fail "WAV capture could not finish: " + errorText
If exportState.active <> 0 Then
    test_Fail "capture state remained active"
End If

Dim As OseWaveInfo waveInfo
If audio_InspectWave(outputFilename, waveInfo) = 0 Then _
    test_Fail "captured output is not a valid PCM WAV"
If waveInfo.audioFormat <> 1 OrElse waveInfo.bitsPerSample <> 16 OrElse _
    waveInfo.channelCount < 1 OrElse waveInfo.sampleFrames = 0 Then _
    test_Fail "captured WAV properties are incorrect"
Dim As Integer peakValue = test_WavePeak(outputFilename)
If peakValue < 200 Then _
    test_Fail "captured A4 audition is silent or below the useful test floor"

Print "wav_export=ok"
Print "sample_rate="; waveInfo.sampleRate
Print "channels="; waveInfo.channelCount
Print "frames="; waveInfo.sampleFrames
Print "peak="; peakValue
Print "underruns="; underrunCount
End 0

/' end of wav_export_smoke.bas '/
