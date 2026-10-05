/'
    Project: OpenSesh
    ---------------------------

    File: pitch_transcriber_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify monophonic PCM WAV pitch transcription without a microphone.

    Responsibilities:

        - create a deterministic silence, A4, silence, C5 WAV fixture
        - verify that both tones become bounded MIDI-note results
        - verify that malformed input is rejected with an explanation
        - reject NaN settings without retaining a previous transcription

    Resource ownership:

        The test owns its caller-supplied fixture path. Every file handle is
        closed before the production parser opens that path for reading.

    This file intentionally does NOT contain:

        - microphone-device access
        - musical-grid quantization
        - graphical user-interface code
'/

#lang "fb"

#include once "../pitch_transcriber.bi"

' -------------------------------------------------------------------------
' Deterministic PCM WAV fixture
' -------------------------------------------------------------------------

Private Function test_Le16(ByVal value As ULong) As String
    Return Chr(CInt(value And &HFF)) + Chr(CInt((value Shr 8) And &HFF))
End Function


Private Function test_Le32(ByVal value As ULong) As String
    Return Chr(CInt(value And &HFF)) + _
        Chr(CInt((value Shr 8) And &HFF)) + _
        Chr(CInt((value Shr 16) And &HFF)) + _
        Chr(CInt((value Shr 24) And &HFF))
End Function


Private Sub test_ExpectMalformedWave( _
    ByVal filename As String, _
    ByVal waveData As String, _
    ByVal caseName As String _
)
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Output Access Write As #fileNumber) <> 0 Then
        End 1
    End If
    Close #fileNumber
    If Open(filename For Binary Access Write As #fileNumber) <> 0 Then
        End 1
    End If
    Put #fileNumber, 1, waveData
    Close #fileNumber
    Dim As PitchTranscribeConfig config
    Dim As PitchTranscribeSummary summary
    pitchTranscribe_DefaultConfig config
    If pitchTranscribe_AnalyzeWave(filename, config, summary) <> 0 OrElse _
        summary.errorText = "" OrElse pitchTranscribe_GetNoteCount() <> 0 Then
        Print "ERROR: malformed WAV was accepted: "; caseName
        End 1
    End If
End Sub


Private Sub test_SetWaveField( _
    ByRef waveData As String, _
    ByVal bytePosition As Integer, _
    ByVal fieldData As String _
)
    If bytePosition < 1 OrElse bytePosition > Len(waveData) OrElse _
        Len(fieldData) > Len(waveData) - bytePosition + 1 Then End 1
    ' fblint: disable-next-line FBL514 REASON: the complete binary field fits the existing allocation.
    Mid(waveData, bytePosition, Len(fieldData)) = fieldData
End Sub


Private Function test_WriteToneWave(ByVal filename As String) As Integer
    Const sampleRate As Integer = 16000
    Const silenceBeforeFrames As Integer = 3200
    Const firstToneFrames As Integer = 9600
    Const middleSilenceFrames As Integer = 2560
    Const secondToneFrames As Integer = 9600
    Const silenceAfterFrames As Integer = 3200
    Const sampleFrames As Integer = silenceBeforeFrames + firstToneFrames + _
        middleSilenceFrames + secondToneFrames + silenceAfterFrames
    Const dataBytes As ULong = sampleFrames * 2

    Dim As String waveData = "RIFF" + test_Le32(36 + dataBytes) + "WAVE" + _
        "fmt " + test_Le32(16) + test_Le16(1) + test_Le16(1) + _
        test_Le32(sampleRate) + test_Le32(sampleRate * 2) + test_Le16(2) + _
        test_Le16(16) + "data" + test_Le32(dataBytes) + Space(dataBytes)

    Dim As Integer firstToneEnd = silenceBeforeFrames + firstToneFrames
    Dim As Integer secondToneStart = firstToneEnd + middleSilenceFrames
    Dim As Integer secondToneEnd = secondToneStart + secondToneFrames
    For sampleIndex As Integer = 0 To sampleFrames - 1
        Dim As Double frequency
        Dim As Integer toneOffset
        If sampleIndex >= silenceBeforeFrames AndAlso sampleIndex < firstToneEnd Then
            frequency = 440.0
            toneOffset = sampleIndex - silenceBeforeFrames
        ElseIf sampleIndex >= secondToneStart AndAlso sampleIndex < secondToneEnd Then
            frequency = 523.2511306
            toneOffset = sampleIndex - secondToneStart
        End If

        Dim As Long signedSample
        If frequency > 0.0 Then
            signedSample = CLng(Sin(8.0 * Atn(1.0) * frequency * _
                CDbl(toneOffset) / CDbl(sampleRate)) * 18000.0)
        End If
        Dim As ULong sampleWord
        If signedSample < 0 Then
            sampleWord = CULng(signedSample + 65536)
        Else
            sampleWord = CULng(signedSample)
        End If
        ' The fixture is allocated to its exact RIFF length above. FB-LINTER: DISABLE-NEXT-LINE FBL514 REASON: The fixture is allocated to its exact RIFF length above.
        Mid(waveData, 45 + sampleIndex * 2, 2) = test_Le16(sampleWord)
    Next

    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Output Access Write As #fileNumber) <> 0 Then
        Return 0
    End If
    Close #fileNumber
    If Open(filename For Binary Access Write As #fileNumber) <> 0 Then
        Return 0
    End If
    Put #fileNumber, 1, waveData
    Close #fileNumber
    Return -1
End Function


' -------------------------------------------------------------------------
' Transcription checks
' -------------------------------------------------------------------------

Dim As String waveFilename = Trim(Command(1))
If waveFilename = "" Then
    Print "usage: pitch_transcriber_smoke.exe <output.wav>"
    End 2
End If

If test_WriteToneWave(waveFilename) = 0 Then
    Print "ERROR: could not create the temporary tone WAV"
    End 1
End If

Dim As PitchTranscribeConfig config
pitchTranscribe_DefaultConfig config
Dim As PitchTranscribeSummary summary
If pitchTranscribe_AnalyzeWave(waveFilename, config, summary) = 0 Then
    Print "ERROR: generated tone WAV was rejected: "; summary.errorText
    End 1
End If

Dim As Integer foundA4
Dim As Integer foundC5
Dim As Integer detectedNoteCount = pitchTranscribe_GetNoteCount()
For noteIndex As Integer = 0 To detectedNoteCount - 1
    Dim As PitchTranscribedNote transcribedNote
    If pitchTranscribe_GetNote(noteIndex, transcribedNote) = 0 Then
        Print "ERROR: retained transcription result could not be read"
        End 1
    End If
    Print "note="; noteIndex; " key="; transcribedNote.keyNumber; _
        " start_ms="; transcribedNote.startMilliseconds; _
        " duration_ms="; transcribedNote.durationMilliseconds
    If transcribedNote.keyNumber = 69 AndAlso _
        transcribedNote.durationMilliseconds >= 400 AndAlso _
        transcribedNote.durationMilliseconds <= 800 Then foundA4 = -1
    If transcribedNote.keyNumber = 72 AndAlso _
        transcribedNote.durationMilliseconds >= 400 AndAlso _
        transcribedNote.durationMilliseconds <= 800 Then foundC5 = -1
Next

If detectedNoteCount < 2 OrElse foundA4 = 0 OrElse foundC5 = 0 Then
    Print "ERROR: A4 and C5 were not transcribed with plausible durations"
    End 1
End If

pitchTranscribe_Clear()
Dim As PitchTranscribedNote clearedNote
If pitchTranscribe_GetNoteCount() <> 0 OrElse _
    pitchTranscribe_GetNote(0, clearedNote) <> 0 Then
    Print "ERROR: transcription clear retained note data"
    End 1
End If

' Use the same portable IEEE-754 fixture as the playback timing tests.
' Each rejection starts with real retained notes, so stale output is visible.
Dim As Double quietNan = CvD(MkLongInt(&H7FF8000000000000))
If quietNan = quietNan Then
    Print "ERROR: the NaN settings fixture is not NaN"
    End 1
End If
For configField As Integer = 0 To 3
    pitchTranscribe_DefaultConfig config
    If pitchTranscribe_AnalyzeWave(waveFilename, config, summary) = 0 OrElse _
        pitchTranscribe_GetNoteCount() < 2 Then
        Print "ERROR: valid settings could not seed the rejection fixture"
        End 1
    End If
    Select Case configField
        Case 0
            config.minimumFrequency = quietNan
        Case 1
            config.maximumFrequency = quietNan
        Case 2
            config.silenceThreshold = quietNan
        Case 3
            config.correlationThreshold = quietNan
    End Select
    If pitchTranscribe_AnalyzeWave(waveFilename, config, summary) <> 0 OrElse _
        summary.errorText <> _
            "Pitch-analysis settings are outside their supported ranges." OrElse _
        summary.noteCount <> 0 OrElse summary.frameCount <> 0 OrElse _
        pitchTranscribe_GetNoteCount() <> 0 OrElse _
        pitchTranscribe_GetNote(0, clearedNote) <> 0 Then
        Print "ERROR: NaN setting was accepted or retained notes: "; configField
        End 1
    End If
Next

Dim As Integer fileNumber = FreeFile()
If Open(waveFilename For Binary Access Read As #fileNumber) <> 0 Then
    End 1
End If
Dim As String validWave = Space(LOF(fileNumber))
Get #fileNumber, 1, validWave
Close #fileNumber

test_ExpectMalformedWave waveFilename, "not a RIFF/WAVE file", "signature"
Dim As String malformedWave = validWave
test_SetWaveField malformedWave, 5, test_Le32(Len(validWave) - 9)
test_ExpectMalformedWave waveFilename, malformedWave, "RIFF length"
malformedWave = validWave
test_SetWaveField malformedWave, 29, test_Le32(16000)
test_ExpectMalformedWave waveFilename, malformedWave, "byte rate"
malformedWave = validWave
test_SetWaveField malformedWave, 33, test_Le16(1)
test_ExpectMalformedWave waveFilename, malformedWave, "block alignment"
malformedWave = validWave
test_SetWaveField malformedWave, 41, test_Le32(Len(validWave) - 45)
test_ExpectMalformedWave waveFilename, malformedWave, "partial PCM frame"
malformedWave = validWave + Mid(validWave, 13, 24)
test_SetWaveField malformedWave, 5, test_Le32(Len(malformedWave) - 8)
test_ExpectMalformedWave waveFilename, malformedWave, "duplicate format"
malformedWave = validWave + "JUNK"
test_SetWaveField malformedWave, 5, test_Le32(Len(malformedWave) - 8)
test_ExpectMalformedWave waveFilename, malformedWave, "partial chunk header"
malformedWave = validWave + "JUNK" + test_Le32(1) + "x"
test_SetWaveField malformedWave, 5, test_Le32(Len(malformedWave) - 8)
test_ExpectMalformedWave waveFilename, malformedWave, "missing odd-chunk padding"

Print "pitch_transcriber=ok"
Print "notes="; detectedNoteCount
Print "malformed_wave_rejections=8"
Print "nan_config_rejections=4"
End 0

/' end of pitch_transcriber_smoke.bas '/
