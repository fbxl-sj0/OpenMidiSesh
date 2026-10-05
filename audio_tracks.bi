/'
    Project: OpenSesh
    ---------------------------

    File: audio_tracks.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: audio_* clip/history/persistence operations with OseWaveInfo and OseAudioClip.

    Purpose:

        Declare the independent audio-clip timeline used beside the Standard
        MIDI document. Clips reference user-owned PCM WAV files and remain
        separate from the MIDI event model.

    Responsibilities:

        - define bounded WAV metadata and audio-clip records
        - expose safe WAV inspection and clip editing
        - expose sixteen-step bounded audio undo and redo snapshots
        - prepare, commit, or cancel snapshots without losing redo on failure
        - expose the small OpenSesh project-file reader and writer

    This file intentionally does NOT contain:

        - audio-device calls or sfxlib playback statements
        - MIDI event parsing or Standard MIDI File writing
        - omaGui widgets or application-level project routing
'/

#ifndef __OSE_AUDIO_TRACKS_BI__
#define __OSE_AUDIO_TRACKS_BI__

Const OSE_AUDIO_MAX_CLIPS As Integer = 64
Const OSE_AUDIO_MAX_PATH_BYTES As Integer = 1024
Const OSE_AUDIO_MAX_WAV_BYTES As LongInt = 67108864
Const OSE_AUDIO_MAX_PROJECT_BYTES As LongInt = 1048576
Const OSE_AUDIO_MAX_DURATION_MILLISECONDS As ULongInt = 86400000
Const OSE_AUDIO_HISTORY_DEPTH As Integer = 16
' Standard MIDI variable-length tick ceiling used by the audio timeline.
Const OSE_AUDIO_TIMELINE_MAX_TICK As ULongInt = 268435455

Type OseWaveInfo
    As Integer audioFormat
    As Integer channelCount
    As Integer sampleRate
    As Integer bitsPerSample
    As ULongInt sampleFrames
    As ULongInt dataBytes
    As ULongInt durationMilliseconds
End Type

Type OseAudioClip
    As String filename
    As ULongInt startTick
    As ULongInt durationMilliseconds
    ' 0..1000, where 1000 represents unity gain.
    As Integer gainPermille
    As OseWaveInfo waveInfo
End Type

Declare Sub audio_Clear()

Declare Function audio_CaptureHistory() As Integer

Declare Function audio_PrepareHistory() As Integer

Declare Function audio_CommitPreparedHistory() As Integer

Declare Function audio_CancelPreparedHistory() As Integer

Declare Function audio_Undo() As Integer

Declare Function audio_Redo() As Integer

Declare Sub audio_HistoryClear()

Declare Function audio_HistoryUndoCount() As Integer

Declare Function audio_HistoryRedoCount() As Integer

Declare Sub audio_HistoryDiscardOldestUndo()

Declare Sub audio_HistoryRedoClear()

Declare Function audio_GetCount() As Integer

Declare Function audio_GetClip( _
    ByVal clipIndex As Integer, _
    ByRef clip As OseAudioClip _
) As Integer

Declare Function audio_InspectWave( _
    ByVal filename As String, _
    ByRef waveInfo As OseWaveInfo _
) As Integer

Declare Function audio_AddClip( _
    ByVal filename As String, _
    ByVal startTick As ULongInt, _
    ByVal gainPermille As Integer _
) As Integer

Declare Function audio_SetClip( _
    ByVal clipIndex As Integer, _
    ByRef clip As OseAudioClip _
) As Integer

Declare Function audio_RemoveClip(ByVal clipIndex As Integer) As Integer

Declare Function audio_SaveProject( _
    ByVal projectFilename As String, _
    ByVal midiFilename As String _
) As Integer

Declare Function audio_SerializeProject( _
    ByVal projectFilename As String, _
    ByVal midiFilename As String, _
    ByRef projectData As String _
) As Integer

' With prepareOnly, success must be followed by CancelPreparedHistory on
' failure or HistoryClear after the coordinated document load commits.
Declare Function audio_LoadProject( _
    ByVal projectFilename As String, _
    ByRef midiFilename As String, _
    ByVal prepareOnly As Integer = 0 _
) As Integer

#endif

/' end of audio_tracks.bi '/
