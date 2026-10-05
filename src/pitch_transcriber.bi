/'
    Project: OpenSesh
    ---------------------------

    File: pitch_transcriber.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: pitchTranscribe_* analysis/result operations with PitchTranscribe* records and limits.

    Purpose:

        Declare the bounded monophonic PCM-to-note transcription interface.

    Responsibilities:

        - describe pitch-analysis settings and results
        - expose one analyzed note list at a time
        - define stable limits shared by the editor and regression tests

    This file intentionally does NOT contain:

        - microphone device control
        - MIDI-model mutation
        - polyphonic source separation
'/

#ifndef OPENSESH_PITCH_TRANSCRIBER_BI
#define OPENSESH_PITCH_TRANSCRIBER_BI

Const PITCH_TRANSCRIBE_MAX_NOTES As Integer = 4096
Const PITCH_TRANSCRIBE_MAX_FILE_BYTES As ULongInt = 67108864
Const PITCH_TRANSCRIBE_MAX_MILLISECONDS As ULong = 120000

Type PitchTranscribeConfig
    As Double minimumFrequency
    As Double maximumFrequency
    As Double silenceThreshold
    As Double correlationThreshold
    As ULong minimumNoteMilliseconds
End Type

Type PitchTranscribedNote
    As ULong startMilliseconds
    As ULong durationMilliseconds
    As UByte keyNumber
    As UByte velocity
    As Single confidence
End Type

Type PitchTranscribeSummary
    As Integer noteCount
    As Integer frameCount
    As Integer voicedFrameCount
    As Integer sourceSampleRate
    As Integer analysisSampleRate
    As Integer channelCount
    As Integer bitsPerSample
    As ULong durationMilliseconds
    As String errorText
End Type

Declare Sub pitchTranscribe_DefaultConfig(ByRef config As PitchTranscribeConfig)
Declare Sub pitchTranscribe_Clear()
Declare Function pitchTranscribe_AnalyzeWave( _
    ByVal filename As String, _
    ByRef config As PitchTranscribeConfig, _
    ByRef summary As PitchTranscribeSummary _
) As Integer
Declare Function pitchTranscribe_GetNoteCount() As Integer
Declare Function pitchTranscribe_GetNote( _
    ByVal noteIndex As Integer, _
    ByRef transcribedNote As PitchTranscribedNote _
) As Integer

#endif

/' end of pitch_transcriber.bi '/
