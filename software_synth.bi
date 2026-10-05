/'
    Project: OpenSesh
    ---------------------------

    File: software_synth.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: softwareSynth_* configuration, pitch conversion, voice routing,
        and MIDI-note playback.

    Purpose:

        Declare the selected SoundFont or fallback voice adapter used for MIDI.

    Responsibilities:

        - configure the bounded General MIDI program-family approximation
        - allocate fallback notes from the mixer channels not reserved for audio clips
        - report which MIDI channel owns each rotating fallback voice
        - rebuild retained definitions after the sound runtime is restarted
        - map MIDI keys and pitch bend to audible frequencies
        - start melodic or percussion voices with explicit mix values
        - prefer the active native SoundFont engine before oscillator fallback
        - reject invalid channels, timing, and silent note requests

    This file intentionally does NOT contain:

        - MIDI file parsing or event scheduling
        - channel automation state
        - graphical meters or transport controls
        - SoundFont parsing or sample mixing
'/

#ifndef __OSE_SOFTWARE_SYNTH_BI__
#define __OSE_SOFTWARE_SYNTH_BI__

#include once "playback_mix.bi"

Type OseSoftwareSynthPlayOptions
    As Integer bankNumber
    As Integer fallbackVoiceChannel
End Type

Declare Sub softwareSynth_Configure()
Declare Function softwareSynth_NoteFrequency(ByVal keyNumber As Integer) As Integer
Declare Function softwareSynth_NoteFrequencyWithBend( _
    ByVal keyNumber As Integer, _
    ByVal pitchBend As Integer _
) As Integer

Const OSE_SOFTWARE_SYNTH_VOICE_COUNT As Integer = 15

Declare Function softwareSynth_MixerChannelForVoice( _
    ByVal voiceChannel As Integer _
) As Integer

Declare Function softwareSynth_PlayMidiNote( _
    ByVal channelIndex As Integer, _
    ByVal keyNumber As Integer, _
    ByVal programNumber As Integer, _
    ByVal pitchBend As Integer, _
    ByVal durationSeconds As Single, _
    ByRef mixValues As OsePlaybackMixValues, _
    ByRef playOptions As OseSoftwareSynthPlayOptions _
) As Integer

#endif

/' end of software_synth.bi '/
