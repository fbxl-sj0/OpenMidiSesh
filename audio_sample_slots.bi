/'
    Project: OpenSesh
    ---------------------------

    File: audio_sample_slots.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: audioSampleSlots_* operations and bounded sample/mixer slot constants.

    Purpose:

        Declare the bounded bridge between document audio clips and sfxlib's
        process-wide sound-effect sample table.

    Responsibilities:

        - expose the complete 64-slot capacity used by the audio document
        - synchronize compacted clip indexes with matching sfxlib sample IDs
        - isolate missing or damaged files without muting unrelated clips
        - reject unavailable or stale playback indexes
        - expose explicit, idempotent sample-table teardown

    This file intentionally does NOT contain:

        - audio-clip editing or history
        - playback timing or mixer automation
        - GUI state
'/

#ifndef __OSE_AUDIO_SAMPLE_SLOTS_BI__
#define __OSE_AUDIO_SAMPLE_SLOTS_BI__

#include once "audio_tracks.bi"

' sfxlib's public sound-effect table contains IDs 0 through 63. The editor
' does not load unrelated effects, so document clips own the complete table.
Const OSE_AUDIO_SAMPLE_SLOT_BASE As Integer = 0
Const OSE_SFX_SAMPLE_SLOT_COUNT As Integer = 64
Const OSE_SFX_MIXER_CHANNEL_COUNT As Integer = 16
#assert OSE_AUDIO_SAMPLE_SLOT_BASE + OSE_AUDIO_MAX_CLIPS <= _
    OSE_SFX_SAMPLE_SLOT_COUNT

Declare Function audioSampleSlots_Synchronize() As Integer

Declare Sub audioSampleSlots_Clear()

Declare Function audioSampleSlots_GetLoadedCount() As Integer

Declare Function audioSampleSlots_GetUnavailableCount() As Integer

Declare Function audioSampleSlots_IsAvailable( _
    ByVal clipIndex As Integer _
) As Integer

Declare Function audioSampleSlots_Play( _
    ByVal mixerChannel As Integer, _
    ByVal clipIndex As Integer, _
    ByVal pitch As Single = 1.0 _
) As Integer

#endif

/' end of audio_sample_slots.bi '/
