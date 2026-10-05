/'
    Project: OpenSesh
    ---------------------------

    File: audio_tracks_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Exercise the independent WAV clip and OpenSesh project layer
        without starting the graphical editor or an audio device.

    Responsibilities:

        - create a small valid PCM WAV fixture at runtime
        - verify valid and malformed WAV inspection
        - verify clip editing and project save/load round trips

    Ownership:

        - this test overwrites only the fixture paths supplied by its runner
        - every opened fixture handle is closed before the test exits

    This file intentionally does NOT contain:

        - recovered Midisoft data or formats
        - sfxlib playback calls
        - omaGui widgets
        - permanent binary test fixtures
'/

#lang "fb"

#include once "../src/audio_tracks.bi"

Private Function test_Le16(ByVal value As ULong) As String
    Return Chr(CInt(value And &HFF)) + Chr(CInt((value Shr 8) And &HFF))
End Function


Private Function test_Le32(ByVal value As ULong) As String
    Return Chr(CInt(value And &HFF)) + _
        Chr(CInt((value Shr 8) And &HFF)) + _
        Chr(CInt((value Shr 16) And &HFF)) + _
        Chr(CInt((value Shr 24) And &HFF))
End Function


Private Function test_WriteWave(ByVal filename As String) As Integer
    Const sampleRate As ULong = 8000
    Const sampleFrames As ULong = 8000
    Const dataBytes As ULong = sampleFrames
    Dim As String waveData = "RIFF" + test_Le32(36 + dataBytes) + "WAVE" + _
        "fmt " + test_Le32(16) + test_Le16(1) + test_Le16(1) + _
        test_Le32(sampleRate) + test_Le32(sampleRate) + test_Le16(1) + _
        test_Le16(8) + "data" + test_Le32(dataBytes) + Space(dataBytes)

    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Write As #fileNumber) <> 0 Then
        Return 0
    End If
    Put #fileNumber, 1, waveData
    Close #fileNumber
    Return -1
End Function


Dim As LongInt savedProjectBytes = 0
Dim As String projectFilename = Trim(Command(1))
If projectFilename = "" Then
    Print "usage: audio_tracks_smoke.exe <output.ose>"
    End 2
End If

Dim As String waveFilename = projectFilename + ".wav"
If test_WriteWave(waveFilename) = 0 Then
    Print "ERROR: could not create the temporary WAV fixture"
    End 1
End If

Dim As OseWaveInfo waveInfo
If audio_InspectWave(waveFilename, waveInfo) = 0 OrElse _
    waveInfo.audioFormat <> 1 OrElse waveInfo.channelCount <> 1 OrElse _
    waveInfo.sampleRate <> 8000 OrElse waveInfo.bitsPerSample <> 8 OrElse _
    waveInfo.sampleFrames <> 8000 OrElse _
    waveInfo.durationMilliseconds <> 1000 Then
    Print "ERROR: valid PCM WAV was rejected or misread"
    End 1
End If

Dim As Integer fileNumber = FreeFile()
If Open(waveFilename For Binary Access Write As #fileNumber) <> 0 Then
    Print "ERROR: could not corrupt the temporary WAV fixture"
    End 1
End If
Put #fileNumber, 1, "not a RIFF file"
Close #fileNumber
If audio_InspectWave(waveFilename, waveInfo) <> 0 Then
    Print "ERROR: malformed WAV was accepted"
    End 1
End If

If test_WriteWave(waveFilename) = 0 Then
    Print "ERROR: could not restore the temporary WAV fixture"
    End 1
End If

audio_Clear()
Dim As Integer firstClip = audio_AddClip(waveFilename, 480, 1000)
Dim As Integer secondClip = audio_AddClip(waveFilename, 960, 750)
If firstClip <> 0 OrElse secondClip <> 1 OrElse audio_GetCount() <> 2 Then
    Print "ERROR: WAV clips were not added"
    End 1
End If

If audio_CaptureHistory() = 0 OrElse audio_RemoveClip(1) = 0 OrElse _
    audio_GetCount() <> 1 OrElse audio_Undo() = 0 OrElse _
    audio_GetCount() <> 2 OrElse audio_Redo() = 0 OrElse _
    audio_GetCount() <> 1 OrElse audio_Undo() = 0 OrElse _
    audio_GetCount() <> 2 Then
    Print "ERROR: audio history did not round-trip"
    End 1
End If
audio_HistoryClear()
If audio_Undo() <> 0 OrElse audio_Redo() <> 0 OrElse _
    audio_GetCount() <> 2 Then
    Print "ERROR: audio history clear retained a stale snapshot"
    End 1
End If

Dim As OseAudioClip editedClip
If audio_GetClip(1, editedClip) = 0 Then
    Print "ERROR: second WAV clip could not be read"
    End 1
End If
editedClip.startTick = 1440
editedClip.gainPermille = 500
If audio_SetClip(1, editedClip) = 0 Then
    Print "ERROR: WAV clip could not be edited"
    End 1
End If

fileNumber = FreeFile()
If Open(projectFilename For Output Access Write As #fileNumber) <> 0 Then
    Print "ERROR: could not create oversized project overwrite fixture"
    End 1
End If
Print #fileNumber, String(4096, "X");
Close #fileNumber
If audio_SaveProject(projectFilename, "recording.mid") = 0 Then
    Print "ERROR: OpenSesh project could not be saved"
    End 1
End If
fileNumber = FreeFile()
If Open(projectFilename For Binary Access Read As #fileNumber) <> 0 Then
    Print "ERROR: saved OpenSesh project could not be measured"
    End 1
End If
savedProjectBytes = Lof(fileNumber)
Close #fileNumber
If savedProjectBytes >= 4096 Then
    Print "ERROR: project save retained stale trailing bytes"
    End 1
End If

audio_Clear()
Dim As String loadedMidiFilename
If audio_LoadProject(projectFilename, loadedMidiFilename) = 0 OrElse _
    loadedMidiFilename <> "recording.mid" OrElse audio_GetCount() <> 2 Then
    Print "ERROR: OpenSesh project could not be loaded"
    End 1
End If

If audio_GetClip(1, editedClip) = 0 OrElse editedClip.startTick <> 1440 OrElse _
    editedClip.gainPermille <> 500 OrElse _
    editedClip.durationMilliseconds <> 1000 Then
    Print "ERROR: loaded WAV clip fields were not preserved"
    End 1
End If

If audio_RemoveClip(0) = 0 OrElse audio_GetCount() <> 1 Then
    Print "ERROR: WAV clip removal was not bounded"
    End 1
End If

' A coordinated load must be cancellable even when the undo ring is full,
' and must preserve an existing redo branch until the complete document loads.
audio_HistoryClear()
For historyIndex As Integer = 1 To OSE_AUDIO_HISTORY_DEPTH
    If audio_CaptureHistory() = 0 OrElse audio_GetClip(0, editedClip) = 0 Then
        Print "ERROR: full history fixture could not be prepared"
        End 1
    End If
    editedClip.startTick += 1
    If audio_SetClip(0, editedClip) = 0 Then
        End 1
    End If
Next
Dim As ULongInt retainedStartTick = editedClip.startTick
If audio_LoadProject(projectFilename, loadedMidiFilename, -1) = 0 OrElse _
    audio_CancelPreparedHistory() = 0 OrElse audio_GetCount() <> 1 OrElse _
    audio_HistoryUndoCount() <> OSE_AUDIO_HISTORY_DEPTH OrElse _
    audio_GetClip(0, editedClip) = 0 OrElse editedClip.startTick <> retainedStartTick Then
    Print "ERROR: cancelled project load changed a full undo history"
    End 1
End If
If audio_Undo() = 0 OrElse audio_HistoryRedoCount() <> 1 Then
    End 1
End If
If audio_LoadProject(projectFilename, loadedMidiFilename, -1) = 0 OrElse _
    audio_CancelPreparedHistory() = 0 OrElse audio_HistoryRedoCount() <> 1 OrElse _
    audio_Redo() = 0 OrElse audio_GetClip(0, editedClip) = 0 OrElse _
    editedClip.startTick <> retainedStartTick Then
    Print "ERROR: cancelled project load erased the redo branch"
    End 1
End If

Print "audio_tracks=ok"
Print "clips="; audio_GetCount()
Print "duration_ms="; editedClip.durationMilliseconds
End 0

/' end of audio_tracks_smoke.bas '/
