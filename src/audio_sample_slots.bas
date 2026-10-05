/'
    Project: OpenSesh
    ---------------------------

    File: audio_sample_slots.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements audio_sample_slots.bi; declarations there define the shared interface.

    Purpose:

        Own the sfxlib sample slots corresponding to the current audio-clip
        document.

    Responsibilities:

        - revalidate each referenced PCM WAV before decoding its slot
        - unload every previously owned slot before rebuilding the table
        - reload clips so compacted document indexes retain audible identity
        - keep valid clips playable when another referenced file is offline
        - reject invalid mixer channels, pitches, stale, and unavailable indexes

    This file intentionally does NOT contain:

        - audio timeline mutation or persistence
        - transport scheduling
        - volume, pan, or meter policy
'/

#lang "fb"

#inclib "sfx" ' fblint: disable-line FBL930 REASON: The supported FreeBASIC toolchain supplies sfx on Windows and Linux.
#include once "audio_sample_slots.bi"

' FreeBASIC exposes SFX LOAD but has no matching source-level unload command.
' This public sfxlib entry point stops voices using the slot, clears its table
' record under the runtime lock, and releases the decoded sample allocation.
Declare Sub fb_sfxSfxUnload CDecl Alias "fb_sfxSfxUnload" ( _
    ByVal sampleId As Integer _
)

' fblint: disable-next-line FBL301 REASON: private state owns the module's bounded sfxlib slot table.
Dim Shared audioSampleSlots_LoadedCount As Integer
' fblint: disable-next-line FBL301 REASON: the synchronized count belongs to the same private slot table.
Dim Shared audioSampleSlots_SynchronizedClipCount As Integer
' fblint: disable-next-line FBL301 REASON: availability flags own no resources outside this module.
Dim Shared audioSampleSlots_Available( _
    0 To OSE_AUDIO_MAX_CLIPS - 1 _
) As Integer
' fblint: disable-next-line FBL301 REASON: filenames reject stale mappings after unsynchronized edits.
Dim Shared audioSampleSlots_Filename( _
    0 To OSE_AUDIO_MAX_CLIPS - 1 _
) As String

' -------------------------------------------------------------------------
' Sample-table ownership
' -------------------------------------------------------------------------

Public Sub audioSampleSlots_Clear()
    For sampleIndex As Integer = 0 To OSE_AUDIO_MAX_CLIPS - 1
        If audioSampleSlots_Available(sampleIndex) <> 0 Then
            fb_sfxSfxUnload OSE_AUDIO_SAMPLE_SLOT_BASE + sampleIndex
        End If
        audioSampleSlots_Available(sampleIndex) = 0
        audioSampleSlots_Filename(sampleIndex) = ""
    Next
    audioSampleSlots_LoadedCount = 0
    audioSampleSlots_SynchronizedClipCount = 0
End Sub


Public Function audioSampleSlots_Synchronize() As Integer
    Dim As Integer clipCount = audio_GetCount()
    If clipCount < 0 OrElse clipCount > OSE_AUDIO_MAX_CLIPS OrElse _
        OSE_AUDIO_SAMPLE_SLOT_BASE + clipCount > _
        OSE_SFX_SAMPLE_SLOT_COUNT Then
        audioSampleSlots_Clear()
        Return 0
    End If

    /'
        Offline-file isolation

        Clips refer to user-owned files that can move or become damaged after
        entering the document. The old table is cleared first so no failed
        slot can replay stale PCM. Each valid clip is then restored at its
        matching document index; a bad file leaves only that slot unavailable.
    '/
    audioSampleSlots_Clear()
    audioSampleSlots_SynchronizedClipCount = clipCount
    Dim As Integer completeResult = -1
    For clipIndex As Integer = 0 To clipCount - 1
        Dim As OseAudioClip clip
        Dim As OseWaveInfo currentWaveInfo
        If audio_GetClip(clipIndex, clip) = 0 OrElse _
            audio_InspectWave(clip.filename, currentWaveInfo) = 0 Then
            completeResult = 0
            Continue For
        End If
        SFX LOAD OSE_AUDIO_SAMPLE_SLOT_BASE + clipIndex, clip.filename
        audioSampleSlots_Available(clipIndex) = -1
        audioSampleSlots_Filename(clipIndex) = clip.filename
        audioSampleSlots_LoadedCount += 1
    Next
    Return completeResult
End Function


Public Function audioSampleSlots_GetLoadedCount() As Integer
    Return audioSampleSlots_LoadedCount
End Function


Public Function audioSampleSlots_GetUnavailableCount() As Integer
    If audioSampleSlots_SynchronizedClipCount < 0 OrElse _
        audioSampleSlots_SynchronizedClipCount > OSE_AUDIO_MAX_CLIPS OrElse _
        audioSampleSlots_LoadedCount < 0 OrElse _
        audioSampleSlots_LoadedCount > _
        audioSampleSlots_SynchronizedClipCount Then
        Return 0
    End If
    Return audioSampleSlots_SynchronizedClipCount - _
        audioSampleSlots_LoadedCount
End Function


Public Function audioSampleSlots_IsAvailable( _
    ByVal clipIndex As Integer _
) As Integer
    If clipIndex < 0 OrElse _
        clipIndex >= audioSampleSlots_SynchronizedClipCount OrElse _
        clipIndex >= audio_GetCount() OrElse _
        audioSampleSlots_Available(clipIndex) = 0 Then
        Return 0
    End If

    /'
        A document edit can occur before its caller requests synchronization.
        Matching the retained filename prevents a compacted or replaced clip
        from briefly addressing PCM that belonged to the old document index.
    '/
    Dim As OseAudioClip clip
    If audio_GetClip(clipIndex, clip) = 0 OrElse _
        clip.filename <> audioSampleSlots_Filename(clipIndex) Then
        Return 0
    End If
    Return -1
End Function

' -------------------------------------------------------------------------
' Bounded playback
' -------------------------------------------------------------------------

Public Function audioSampleSlots_Play( _
    ByVal mixerChannel As Integer, _
    ByVal clipIndex As Integer, _
    ByVal pitch As Single _
) As Integer
    If mixerChannel < 0 OrElse _
        mixerChannel >= OSE_SFX_MIXER_CHANNEL_COUNT Then
        Return 0
    End If
    If audioSampleSlots_IsAvailable(clipIndex) = 0 Then
        Return 0
    End If
    If pitch <= 0.0 OrElse pitch > 8.0 Then
        Return 0
    End If

    SFX PLAY mixerChannel, OSE_AUDIO_SAMPLE_SLOT_BASE + clipIndex, pitch
    Return -1
End Function

/' end of audio_sample_slots.bas '/
