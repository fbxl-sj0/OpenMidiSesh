/'
    Project: OpenSesh
    ---------------------------

    File: playback_mix.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements playback_mix.bi; declarations there define the shared interface.

    Purpose:

        Calculate the software synthesizer's independent note, channel, and
        meter gains from MIDI playback state.

    Responsibilities:

        - clamp caller values before converting them to normalized ratios
        - combine CC7, CC11, mute or solo state, and master volume once
        - preserve velocity as a separate per-note gain stage
        - map MIDI pan to sfxlib's signed pan range

    This file intentionally does NOT contain:

        - oscillator selection or note timing
        - calls into the audio driver
        - persistent application state
'/

#lang "fb"

#include once "playback_mix.bi"

' -------------------------------------------------------------------------
' Bounded value conversion
' -------------------------------------------------------------------------

Private Function playbackMix_MidiRatio(ByVal midiValue As Integer) As Single
    If midiValue <= 0 Then
        Return 0.0
    End If
    If midiValue >= 127 Then
        Return 1.0
    End If
    Return CSng(midiValue) / 127.0
End Function


Private Function playbackMix_MasterRatio(ByVal masterVolume As Single) As Single
    If masterVolume <= 0.0 Then
        Return 0.0
    End If
    If masterVolume >= 1.0 Then
        Return 1.0
    End If
    Return masterVolume
End Function

' -------------------------------------------------------------------------
' Playback mix calculation
' -------------------------------------------------------------------------

Public Sub playbackMix_Calculate( _
    ByRef values As OsePlaybackMixValues, _
    ByVal controllerVolume As Integer, _
    ByVal controllerExpression As Integer, _
    ByVal controllerPan As Integer, _
    ByVal noteVelocity As Integer, _
    ByVal masterVolume As Single, _
    ByVal audible As Integer _
)
    Dim As OsePlaybackMixValues emptyValues
    values = emptyValues

    If controllerPan <= 0 Then
        values.pan = -1.0
    ElseIf controllerPan >= 127 Then
        values.pan = 1.0
    Else
        values.pan = (CSng(controllerPan) - 64.0) / 63.0
    End If

    If audible = 0 Then
        Exit Sub
    End If

    values.meterGain = playbackMix_MidiRatio(controllerVolume) * _
        playbackMix_MidiRatio(controllerExpression)
    values.channelGain = values.meterGain * _
        playbackMix_MasterRatio(masterVolume)
    values.voiceGain = playbackMix_MidiRatio(noteVelocity) * _
        OSE_PLAYBACK_VOICE_HEADROOM
End Sub

/' end of playback_mix.bas '/
