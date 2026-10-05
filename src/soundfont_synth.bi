/'
    Project: OpenSesh
    ---------------------------

    File: soundfont_synth.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: soundfontSynth_* playback, channel controls, worker/output lifecycle, and preview.

    Purpose:

        Declare the pure FreeBASIC polyphonic SoundFont playback engine.

    Responsibilities:

        - load and unload user-selected SF2 banks
        - render bounded sample voices with pitch, loops, envelopes, and pan
        - feed the existing sfxlib mixer and SoundFont voices through one stream
        - expose channel, pause, stop, and runtime-restart controls

    This file intentionally does NOT contain:

        - RIFF or Hydra parsing
        - MIDI transport scheduling
        - graphical controls or preference storage
'/

#ifndef __OSE_SOUNDFONT_SYNTH_BI__
#define __OSE_SOUNDFONT_SYNTH_BI__

#include once "playback_mix.bi"

Declare Function soundfontSynth_Load( _
    ByVal filename As String, _
    ByRef errorText As String _
) As Integer
Declare Sub soundfontSynth_Unload()
Declare Sub soundfontSynth_Shutdown()
Declare Function soundfontSynth_IsActive() As Integer
Declare Function soundfontSynth_GetName() As String
Declare Function soundfontSynth_GetFilename() As String

Declare Function soundfontSynth_PlayMidiNote( _
    ByVal channelIndex As Integer, _
    ByVal keyNumber As Integer, _
    ByVal bankNumber As Integer, _
    ByVal programNumber As Integer, _
    ByVal pitchBend As Integer, _
    ByVal durationSeconds As Single, _
    ByRef mixValues As OsePlaybackMixValues _
) As Integer

Declare Sub soundfontSynth_SetChannelMix( _
    ByVal channelIndex As Integer, _
    ByVal channelGain As Single, _
    ByVal channelPan As Single _
)
Declare Sub soundfontSynth_SetPaused(ByVal paused As Integer)
Declare Sub soundfontSynth_StopChannel(ByVal channelIndex As Integer)
Declare Sub soundfontSynth_StopAll()

Declare Sub soundfontSynth_SuspendOutput()
Declare Function soundfontSynth_ResumeOutput( _
    ByRef errorText As String _
) As Integer

' Render one note without opening a device. This is also the bounded building
' block for future offline preview and export paths.
Declare Function soundfontSynth_RenderPreview( _
    ByVal channelIndex As Integer, _
    ByVal keyNumber As Integer, _
    ByVal bankNumber As Integer, _
    ByVal programNumber As Integer, _
    ByVal pitchBend As Integer, _
    ByVal durationSeconds As Single, _
    ByRef mixValues As OsePlaybackMixValues, _
    ByVal outputSampleRate As Integer, _
    ByVal outputSamples As Single Ptr, _
    ByVal frameCount As Integer _
) As Integer

#endif

/' end of soundfont_synth.bi '/
