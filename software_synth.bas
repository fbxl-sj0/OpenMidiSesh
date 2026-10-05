/'
    Project: OpenSesh
    ---------------------------

    File: software_synth.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements software_synth.bi; declarations there define the shared interface.

    Purpose:

        Route a validated MIDI note through the selected software synthesizer.

    Responsibilities:

        - configure sixteen bounded oscillator and envelope families per runtime
        - allocate fallback notes over fifteen channels with deterministic voice stealing
        - retain each fallback voice's source MIDI channel for mixer updates
        - detect and repair configuration invalidated by an audio restart
        - apply MIDI program family, pitch bend, gain, and pan
        - use the percussion noise voice for General MIDI channel ten
        - route GM and GS bank selections through the native SoundFont engine
        - retain oscillator playback when a bank or preset is unavailable
        - provide the same production note path to the editor and audio tests

    This file intentionally does NOT contain:

        - SoundFont parsing, sample storage, or realtime sample mixing
        - transport timing or note ordering
        - external MIDI-device output
'/

#lang "fb"

#inclib "sfx"
#include once "software_synth.bi"
#include once "sfx_runtime.bi"
#include once "soundfont_synth.bi"
#include once "generated_voice_stop_internal.bi"

' fblint: disable-next-line FBL301 REASON: retained configuration belongs to the process-wide synth adapter.
Dim Shared softwareSynth_ConfiguredGeneration As Integer
' fblint: disable-next-line FBL301 REASON: this cursor selects the next module-owned fallback voice.
Dim Shared softwareSynth_NextFallbackVoice As Integer
Dim Shared softwareSynth_FallbackVoiceChannel( _
    0 To OSE_SOFTWARE_SYNTH_VOICE_COUNT - 1 _
) As Integer
Dim Shared softwareSynth_FallbackVoiceAssigned( _
    0 To OSE_SOFTWARE_SYNTH_VOICE_COUNT - 1 _
) As Integer

' -------------------------------------------------------------------------
' Voice-family configuration
' -------------------------------------------------------------------------

Public Sub softwareSynth_Configure()
    If sfxRuntime_EnsureReady() = 0 Then
        Exit Sub
    End If
    Dim As Integer runtimeGeneration = sfxRuntime_GetGeneration()
    If softwareSynth_ConfiguredGeneration = runtimeGeneration Then
        Exit Sub
    End If
    softwareSynth_NextFallbackVoice = 0
    For voiceIndex As Integer = 0 To OSE_SOFTWARE_SYNTH_VOICE_COUNT - 1
        softwareSynth_FallbackVoiceAssigned(voiceIndex) = 0
    Next

    Dim As Integer waveType(0 To 15) = _
        {2, 0, 1, 3, 1, 3, 3, 3, 1, 0, 1, 2, 3, 2, 1, 4}
    Dim As Single attack(0 To 15) = _
        {.005, .002, .020, .005, .005, .080, .060, .025, _
         .020, .030, .005, .120, .080, .010, .002, .001}
    Dim As Single decay(0 To 15) = _
        {.180, .120, .080, .120, .080, .250, .220, .120, _
         .120, .100, .080, .350, .300, .180, .100, .080}
    Dim As Single sustain(0 To 15) = _
        {.35, .15, .80, .40, .50, .65, .60, .65, _
         .55, .75, .65, .65, .40, .45, .20, .05}
    Dim As Single releaseTime(0 To 15) = _
        {.12, .08, .12, .10, .08, .30, .35, .18, _
         .15, .18, .12, .40, .30, .16, .08, .05}

    For familyIndex As Integer = 0 To 15
        wave familyIndex, waveType(familyIndex)
        envelope familyIndex, attack(familyIndex), decay(familyIndex), _
            sustain(familyIndex), releaseTime(familyIndex)
        instrument familyIndex, familyIndex, familyIndex
    Next
    softwareSynth_ConfiguredGeneration = runtimeGeneration
End Sub


Public Function softwareSynth_MixerChannelForVoice( _
    ByVal voiceChannel As Integer _
) As Integer
    If voiceChannel < 0 OrElse _
        voiceChannel >= OSE_SOFTWARE_SYNTH_VOICE_COUNT Then
        Return -1
    End If
    If softwareSynth_FallbackVoiceAssigned(voiceChannel) = 0 Then
        Return voiceChannel
    End If
    Return softwareSynth_FallbackVoiceChannel(voiceChannel)
End Function

' -------------------------------------------------------------------------
' MIDI pitch conversion
' -------------------------------------------------------------------------

Public Function softwareSynth_NoteFrequency(ByVal keyNumber As Integer) As Integer
    Return softwareSynth_NoteFrequencyWithBend(keyNumber, 8192)
End Function


Public Function softwareSynth_NoteFrequencyWithBend( _
    ByVal keyNumber As Integer, _
    ByVal pitchBend As Integer _
) As Integer
    If keyNumber < 0 Then
        keyNumber = 0
    End If
    If keyNumber > 127 Then
        keyNumber = 127
    End If
    If pitchBend < 0 Then
        pitchBend = 0
    End If
    If pitchBend > 16383 Then
        pitchBend = 16383
    End If

    ' Standard MIDI pitch bend is interpreted as a two-semitone range around
    ' the 8192 center value. This matches the editor's prior playback rule.
    Dim As Double bendSemitones = _
        ((CDbl(pitchBend) - 8192.0) / 8192.0) * 2.0
    Dim As Double frequency = 440.0 * _
        (2.0 ^ ((CDbl(keyNumber) - 69.0 + bendSemitones) / 12.0))
    If frequency < 20.0 Then
        frequency = 20.0
    End If
    If frequency > 20000.0 Then
        frequency = 20000.0
    End If
    Return CInt(frequency)
End Function

' -------------------------------------------------------------------------
' Note routing
' -------------------------------------------------------------------------

Public Function softwareSynth_PlayMidiNote( _
    ByVal channelIndex As Integer, _
    ByVal keyNumber As Integer, _
    ByVal programNumber As Integer, _
    ByVal pitchBend As Integer, _
    ByVal durationSeconds As Single, _
    ByRef mixValues As OsePlaybackMixValues, _
    ByRef playOptions As OseSoftwareSynthPlayOptions _
) As Integer
    If channelIndex < 0 OrElse channelIndex > 15 Then
        Return 0
    End If
    If keyNumber < 0 OrElse keyNumber > 127 Then
        Return 0
    End If
    If durationSeconds <> durationSeconds OrElse durationSeconds <= 0.0 OrElse _
        durationSeconds > 3600.0 Then
        Return 0
    End If
    If mixValues.channelGain <= 0.0 OrElse mixValues.voiceGain <= 0.0 Then
        Return 0
    End If

    If programNumber < 0 Then
        programNumber = 0
    End If
    If programNumber > 127 Then
        programNumber = 127
    End If
    Dim As Integer bankNumber = playOptions.bankNumber
    If bankNumber < 0 Then
        bankNumber = 0
    End If
    If bankNumber > 16383 Then
        bankNumber = 16383
    End If
    If channelIndex = 9 Then
        bankNumber = 128
    End If
    If soundfontSynth_IsActive() <> 0 Then
        If soundfontSynth_PlayMidiNote(channelIndex, keyNumber, bankNumber, _
            programNumber, pitchBend, durationSeconds, mixValues) <> 0 Then
            Return -1
        End If
    End If

    softwareSynth_Configure()
    Dim As Integer instrumentFamily = programNumber \ 8
    If channelIndex = 9 Then
        instrumentFamily = 15
    End If

    Dim As Integer audioChannelIndex = playOptions.fallbackVoiceChannel
    If audioChannelIndex = -1 Then
        audioChannelIndex = softwareSynth_NextFallbackVoice
        softwareSynth_NextFallbackVoice += 1
        If softwareSynth_NextFallbackVoice >= _
            OSE_SOFTWARE_SYNTH_VOICE_COUNT Then _
            softwareSynth_NextFallbackVoice = 0
    ElseIf audioChannelIndex < 0 OrElse _
        audioChannelIndex >= OSE_SOFTWARE_SYNTH_VOICE_COUNT Then
        Return 0
    End If

    ' sfxlib SOUND and NOISE each replace the current voice on their channel.
    ' Allocate one bounded mixer channel per note, stealing in round-robin
    ' order when the fixed pool is full. Channel 15 stays reserved for the
    ' editor's dedicated audio-clip lane.
    generatedVoiceStop_Channel audioChannelIndex
    softwareSynth_FallbackVoiceChannel(audioChannelIndex) = channelIndex
    softwareSynth_FallbackVoiceAssigned(audioChannelIndex) = -1

    instrument audioChannelIndex, instrumentFamily
    volume audioChannelIndex, mixValues.channelGain
    pan audioChannelIndex, mixValues.pan
    If channelIndex = 9 Then
        noise audioChannelIndex, durationSeconds, mixValues.voiceGain
    Else
        sound audioChannelIndex, _
            softwareSynth_NoteFrequencyWithBend(keyNumber, pitchBend), _
            durationSeconds, mixValues.voiceGain
    End If
    Return -1
End Function

/' end of software_synth.bas '/
