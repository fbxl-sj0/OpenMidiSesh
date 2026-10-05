/'
    Project: OpenSesh
    ---------------------------

    File: tests/audio_formats_malformed_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Exercise malformed PCM WAV and OpenSesh project inputs against
        their production parsers with transactional-state assertions.

    Responsibilities:

        - validate RIFF sizing, PCM format fields, chunks, and whole frames
        - reject malformed project headers, counts, clip fields, and trailing data
        - prove rejected project files cannot replace the active clip list
        - retain valid odd-sized RIFF chunks and an empty project control
    Ownership: Writers close handles; callers own cleanup of fixture files.
    This file intentionally does NOT contain:

        - audio-device or sfxlib operations
        - MIDI document parsing
        - graphical error dialogs
'/

#lang "fb"

#include once "../audio_tracks.bi"

' -------------------------------------------------------------------------
' Binary and text fixture helpers
' -------------------------------------------------------------------------

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Function test_Le16(ByVal value As ULong) As String
    Return Chr(value And &HFF) + Chr((value Shr 8) And &HFF)
End Function


Private Function test_Le32(ByVal value As ULong) As String
    Return Chr(value And &HFF) + Chr((value Shr 8) And &HFF) + _
        Chr((value Shr 16) And &HFF) + Chr((value Shr 24) And &HFF)
End Function


Private Sub test_WriteBinary( _
    ByVal filename As String, _
    ByVal fileData As String _
)
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Output Access Write As #fileNumber) <> 0 Then _
        test_Fail "could not truncate an audio-format fixture"
    Close #fileNumber
    fileNumber = FreeFile()
    If Open(filename For Binary Access Write As #fileNumber) <> 0 Then _
        test_Fail "could not create an audio-format fixture"
    Put #fileNumber, 1, fileData
    Close #fileNumber
End Sub


Private Function test_FmtChunk( _
    ByVal audioFormat As Integer, _
    ByVal channelCount As Integer, _
    ByVal sampleRate As ULong, _
    ByVal bitsPerSample As Integer, _
    ByVal byteRate As ULong, _
    ByVal blockAlign As Integer _
) As String
    Dim As String formatData = test_Le16(audioFormat) + _
        test_Le16(channelCount) + test_Le32(sampleRate) + _
        test_Le32(byteRate) + test_Le16(blockAlign) + _
        test_Le16(bitsPerSample)
    Return "fmt " + test_Le32(Len(formatData)) + formatData
End Function


Private Function test_DataChunk(ByVal dataBytes As Integer) As String
    Dim As String result = "data" + test_Le32(dataBytes) + _
        String(dataBytes, Chr(0))
    If (dataBytes Mod 2) <> 0 Then
        result += Chr(0)
    End If
    Return result
End Function


Private Function test_Riff(ByVal chunks As String) As String
    Return "RIFF" + test_Le32(4 + Len(chunks)) + "WAVE" + chunks
End Function


Private Sub test_ExpectWaveReject( _
    ByVal waveFilename As String, _
    ByVal waveData As String, _
    ByVal caseName As String _
)
    test_WriteBinary waveFilename, waveData
    Dim As OseWaveInfo waveInfo
    If audio_InspectWave(waveFilename, waveInfo) <> 0 Then _
        test_Fail "malformed WAV was accepted: " + caseName
End Sub


Private Sub test_ExpectProjectReject( _
    ByVal projectFilename As String, _
    ByVal projectText As String, _
    ByVal caseName As String _
)
    test_WriteBinary projectFilename, projectText
    Dim As String midiFilename = "not cleared"
    If audio_LoadProject(projectFilename, midiFilename) <> 0 Then _
        test_Fail "malformed project was accepted: " + caseName
    If midiFilename <> "" Then _
        test_Fail "failed project load retained its MIDI filename: " + caseName
    If audio_GetCount() <> 1 Then _
        test_Fail "failed project load replaced active clips: " + caseName
End Sub

' -------------------------------------------------------------------------
' WAV rejection matrix
' -------------------------------------------------------------------------

Dim As String baseFilename = Trim(Command(1))
If baseFilename = "" Then
    Print "usage: audio_formats_malformed_smoke.exe <fixture-base>"
    End 2
End If
Dim As String waveFilename = baseFilename + ".wav"
Dim As String projectFilename = baseFilename + ".ose"

Const testSampleRate As ULong = 8000
Const testChannels As Integer = 2
Const testBits As Integer = 16
Const testBlockAlign As Integer = 4
Const testByteRate As ULong = testSampleRate * testBlockAlign

Dim As String validFormat = test_FmtChunk( _
    1, testChannels, testSampleRate, testBits, testByteRate, testBlockAlign)
Dim As String validData = test_DataChunk(32)
Dim As String validWave = test_Riff(validFormat + validData)
test_WriteBinary waveFilename, validWave
Dim As OseWaveInfo waveInfo
If audio_InspectWave(waveFilename, waveInfo) = 0 OrElse _
    waveInfo.sampleFrames <> 8 OrElse waveInfo.durationMilliseconds <> 1 Then _
    test_Fail "valid PCM WAV control was rejected"

Dim As String oddJunk = "JUNK" + test_Le32(1) + "X" + Chr(0)
test_WriteBinary waveFilename, test_Riff(oddJunk + validFormat + validData)
If audio_InspectWave(waveFilename, waveInfo) = 0 Then _
    test_Fail "valid padded odd-sized RIFF chunk was rejected"

test_ExpectWaveReject waveFilename, "NOPE" + Mid(validWave, 5), "RIFF tag"
test_ExpectWaveReject waveFilename, "RIFF" + test_Le32(4) + _
    Mid(validWave, 9), "RIFF container size"
test_ExpectWaveReject waveFilename, test_Riff(test_DataChunk(32)), _
    "missing fmt chunk"
test_ExpectWaveReject waveFilename, test_Riff( _
    validFormat + validFormat + validData), "duplicate fmt chunk"
test_ExpectWaveReject waveFilename, test_Riff( _
    "fmt " + test_Le32(14) + String(14, Chr(0)) + validData), _
    "short fmt chunk"
test_ExpectWaveReject waveFilename, test_Riff( _
    test_FmtChunk(2, 2, 8000, 16, 32000, 4) + validData), _
    "non-PCM format"
test_ExpectWaveReject waveFilename, test_Riff( _
    test_FmtChunk(1, 0, 8000, 16, 0, 0) + validData), _
    "zero channels"
test_ExpectWaveReject waveFilename, test_Riff( _
    test_FmtChunk(1, 9, 8000, 16, 144000, 18) + validData), _
    "excessive channels"
test_ExpectWaveReject waveFilename, test_Riff( _
    test_FmtChunk(1, 2, 0, 16, 0, 4) + validData), "zero sample rate"
test_ExpectWaveReject waveFilename, test_Riff( _
    test_FmtChunk(1, 2, 193000, 16, 772000, 4) + validData), _
    "excessive sample rate"
test_ExpectWaveReject waveFilename, test_Riff( _
    test_FmtChunk(1, 2, 8000, 12, 24000, 3) + validData), _
    "unsupported bit depth"
test_ExpectWaveReject waveFilename, test_Riff( _
    test_FmtChunk(1, 2, 8000, 16, 32000, 2) + validData), _
    "wrong block alignment"
test_ExpectWaveReject waveFilename, test_Riff( _
    test_FmtChunk(1, 2, 8000, 16, 16000, 4) + validData), _
    "wrong byte rate"
test_ExpectWaveReject waveFilename, test_Riff(validFormat + _
    test_DataChunk(33)), "partial sample frame"
test_ExpectWaveReject waveFilename, test_Riff(validFormat + _
    test_DataChunk(0)), "empty sample data"
test_ExpectWaveReject waveFilename, test_Riff( _
    "JUNK" + test_Le32(100) + String(32, Chr(0))), _
    "oversized RIFF chunk"

' -------------------------------------------------------------------------
' Project rejection matrix and staged commit
' -------------------------------------------------------------------------

test_WriteBinary waveFilename, validWave
audio_Clear()
If audio_AddClip(waveFilename, 0, 1000) <> 0 Then _
    test_Fail "could not create active-clip sentinel"

Dim As String missingProject = projectFilename + ".missing"
If Len(Dir(missingProject)) > 0 Then
    Kill missingProject
End If
Dim As String loadedMidi = "not cleared"
If audio_LoadProject(missingProject, loadedMidi) <> 0 OrElse _
    loadedMidi <> "" OrElse audio_GetCount() <> 1 Then _
    test_Fail "missing project changed active state"

Dim As String newLine = Chr(10)
Dim As String emptyProject = "OSEPROJECT 1" + newLine + _
    "MIDI 0" + newLine + newLine + "CLIPS 0" + newLine
test_ExpectProjectReject projectFilename, "short", "minimum file size"
test_ExpectProjectReject projectFilename, "OSEPROJECT 2" + newLine + _
    Mid(emptyProject, InStr(emptyProject, newLine) + 1), "project version"
test_ExpectProjectReject projectFilename, "OSEPROJECT 1" + newLine + _
    "WRONG 0" + newLine + newLine + "CLIPS 0" + newLine, "MIDI field"
test_ExpectProjectReject projectFilename, "OSEPROJECT 1" + newLine + _
    "MIDI x" + newLine + newLine + "CLIPS 0" + newLine, "MIDI length"
test_ExpectProjectReject projectFilename, "OSEPROJECT 1" + newLine + _
    "MIDI 2" + newLine + "x" + newLine + "CLIPS 0" + newLine, _
    "MIDI path length mismatch"
test_ExpectProjectReject projectFilename, "OSEPROJECT 1" + newLine + _
    "MIDI 0" + newLine + newLine + "WRONG 0" + newLine, "CLIPS field"
test_ExpectProjectReject projectFilename, "OSEPROJECT 1" + newLine + _
    "MIDI 0" + newLine + newLine + "CLIPS 65" + newLine, "clip count"
test_ExpectProjectReject projectFilename, "OSEPROJECT 1" + newLine + _
    "MIDI 0" + newLine + newLine + "CLIPS 1" + newLine, _
    "missing clip record"
test_ExpectProjectReject projectFilename, "OSEPROJECT 1" + newLine + _
    "MIDI 0" + newLine + newLine + "CLIPS 1" + newLine + _
    "CLIP 0 0 1000 1" + newLine + "x" + newLine, "zero duration"
test_ExpectProjectReject projectFilename, "OSEPROJECT 1" + newLine + _
    "MIDI 0" + newLine + newLine + "CLIPS 1" + newLine + _
    "CLIP 0 1 1001 1" + newLine + "x" + newLine, "excessive gain"
test_ExpectProjectReject projectFilename, "OSEPROJECT 1" + newLine + _
    "MIDI 0" + newLine + newLine + "CLIPS 1" + newLine + _
    "CLIP 0 1 1000 0" + newLine + newLine, "empty clip path"
test_ExpectProjectReject projectFilename, "OSEPROJECT 1" + newLine + _
    "MIDI 0" + newLine + newLine + "CLIPS 1" + newLine + _
    "CLIP 0 1 1000 1 extra" + newLine + "x" + newLine, _
    "extra clip fields"
test_ExpectProjectReject projectFilename, "OSEPROJECT 1" + newLine + _
    "MIDI 0" + newLine + newLine + "CLIPS 1" + newLine + _
    "CLIP 0 1 1000 2" + newLine + "x" + newLine, _
    "clip path length mismatch"
test_ExpectProjectReject projectFilename, emptyProject + _
    "TRAILING DATA" + newLine, "trailing project data"

test_WriteBinary projectFilename, emptyProject
If audio_LoadProject(projectFilename, loadedMidi) = 0 OrElse _
    loadedMidi <> "" OrElse audio_GetCount() <> 0 Then _
    test_Fail "valid empty project control was rejected"
If audio_Undo() = 0 OrElse audio_GetCount() <> 1 Then _
    test_Fail "valid project load did not retain a rollback snapshot"
If audio_Redo() = 0 OrElse audio_GetCount() <> 0 Then _
    test_Fail "project-load rollback could not return to the loaded state"

Print "audio_formats_malformed=ok"
Print "wav_rejections=16 project_rejections=15 valid_controls=3"
End 0

/' end of tests/audio_formats_malformed_smoke.bas '/
