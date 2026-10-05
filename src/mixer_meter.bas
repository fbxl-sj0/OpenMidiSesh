/'
    Project: OpenSesh
    ---------------------------

    File: mixer_meter.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements mixer_meter.bi; declarations there define the shared interface.

    Purpose:

        Convert scheduled sound activity into responsive channel and stereo
        master VU levels.

    Responsibilities:

        - retain bounded per-channel activity for each scheduled sound span
        - attack immediately so short percussion notes remain visible
        - release smoothly after sound ends or a channel becomes inaudible
        - derive stereo master levels from channel pan and master volume

    This file intentionally does NOT contain:

        - synthetic idle levels derived from fader positions
        - direct audio-buffer inspection
        - widget input or drawing code
'/

#lang "fb"

#include once "mixer_meter.bi"

' A full-scale meter falls to zero in roughly half a second after sound ends.
Const MIXER_METER_RELEASE_PER_SECOND As Double = 2.0
Const MIXER_METER_MAX_ELAPSED_SECONDS As Double = 1.0


Private Function mixerMeter_ClampUnit(ByVal value As Single) As Single
    If value < 0.0 Then
        Return 0.0
    End If
    If value > 1.0 Then
        Return 1.0
    End If
    Return value
End Function


Private Function mixerMeter_ClampPan(ByVal value As Single) As Single
    If value < -1.0 Then
        Return -1.0
    End If
    If value > 1.0 Then
        Return 1.0
    End If
    Return value
End Function


Public Sub mixerMeter_Initialize(ByRef state As OseMixerMeterState)
    For channelIndex As Integer = 0 To OSE_MIXER_METER_CHANNEL_COUNT - 1
        state.sourceLevel(channelIndex) = 0.0
        state.sourceSeconds(channelIndex) = 0.0
        state.displayLevel(channelIndex) = 0.0
        state.channelVolume(channelIndex) = 1.0
        state.channelPan(channelIndex) = 0.0
        state.channelAudible(channelIndex) = -1
    Next
    state.masterVolume = 1.0
    state.masterLeftLevel = 0.0
    state.masterRightLevel = 0.0
End Sub


Public Sub mixerMeter_SetChannelMix( _
    ByRef state As OseMixerMeterState, _
    ByVal channelIndex As Integer, _
    ByVal volumeLevel As Single, _
    ByVal panPosition As Single, _
    ByVal audible As Integer _
)
    If channelIndex < 0 OrElse _
        channelIndex >= OSE_MIXER_METER_CHANNEL_COUNT Then
        Exit Sub
    End If
    state.channelVolume(channelIndex) = mixerMeter_ClampUnit(volumeLevel)
    state.channelPan(channelIndex) = mixerMeter_ClampPan(panPosition)
    state.channelAudible(channelIndex) = IIf(audible <> 0, -1, 0)
End Sub


Public Sub mixerMeter_SetMasterVolume( _
    ByRef state As OseMixerMeterState, _
    ByVal volumeLevel As Single _
)
    state.masterVolume = mixerMeter_ClampUnit(volumeLevel)
End Sub


Public Function mixerMeter_Trigger( _
    ByRef state As OseMixerMeterState, _
    ByVal channelIndex As Integer, _
    ByVal sourceLevel As Single, _
    ByVal durationSeconds As Double _
) As Integer
    If channelIndex < 0 OrElse _
        channelIndex >= OSE_MIXER_METER_CHANNEL_COUNT Then
        Return 0
    End If
    If durationSeconds <= 0.0 Then
        Return 0
    End If
    If durationSeconds > 86400.0 Then
        durationSeconds = 86400.0
    End If

    Dim As Single boundedLevel = mixerMeter_ClampUnit(sourceLevel)
    If boundedLevel <= 0.0 Then
        Return 0
    End If
    If boundedLevel > state.sourceLevel(channelIndex) Then
        state.sourceLevel(channelIndex) = boundedLevel
    End If
    If durationSeconds > state.sourceSeconds(channelIndex) Then
        state.sourceSeconds(channelIndex) = durationSeconds
    End If
    Return -1
End Function


Public Sub mixerMeter_StopChannel( _
    ByRef state As OseMixerMeterState, _
    ByVal channelIndex As Integer _
)
    If channelIndex < 0 OrElse _
        channelIndex >= OSE_MIXER_METER_CHANNEL_COUNT Then
        Exit Sub
    End If
    state.sourceLevel(channelIndex) = 0.0
    state.sourceSeconds(channelIndex) = 0.0
End Sub


Public Sub mixerMeter_StopAll(ByRef state As OseMixerMeterState)
    For channelIndex As Integer = 0 To OSE_MIXER_METER_CHANNEL_COUNT - 1
        state.sourceLevel(channelIndex) = 0.0
        state.sourceSeconds(channelIndex) = 0.0
    Next
End Sub


Public Sub mixerMeter_Update( _
    ByRef state As OseMixerMeterState, _
    ByVal elapsedSeconds As Double, _
    ByVal paused As Integer _
)
    If elapsedSeconds < 0.0 Then
        elapsedSeconds = 0.0
    End If
    If elapsedSeconds > MIXER_METER_MAX_ELAPSED_SECONDS Then
        elapsedSeconds = MIXER_METER_MAX_ELAPSED_SECONDS
    End If

    Dim As Single masterLeft
    Dim As Single masterRight
    For channelIndex As Integer = 0 To OSE_MIXER_METER_CHANNEL_COUNT - 1
        Dim As Single targetLevel
        If paused = 0 AndAlso state.sourceSeconds(channelIndex) > 0.0 AndAlso _
            state.channelAudible(channelIndex) <> 0 Then
            targetLevel = state.sourceLevel(channelIndex) * _
                state.channelVolume(channelIndex)
        End If
        targetLevel = mixerMeter_ClampUnit(targetLevel)

        If targetLevel >= state.displayLevel(channelIndex) Then
            ' Immediate attack keeps very short notes from disappearing
            ' between ten-millisecond UI frames.
            state.displayLevel(channelIndex) = targetLevel
        Else
            state.displayLevel(channelIndex) -= _
                CSng(elapsedSeconds * MIXER_METER_RELEASE_PER_SECOND)
            If state.displayLevel(channelIndex) < targetLevel Then
                state.displayLevel(channelIndex) = targetLevel
            End If
            If state.displayLevel(channelIndex) < 0.0 Then
                state.displayLevel(channelIndex) = 0.0
            End If
        End If

        If paused = 0 AndAlso state.sourceSeconds(channelIndex) > 0.0 Then
            state.sourceSeconds(channelIndex) -= elapsedSeconds
            If state.sourceSeconds(channelIndex) <= 0.0 Then
                state.sourceSeconds(channelIndex) = 0.0
                state.sourceLevel(channelIndex) = 0.0
            End If
        End If

        Dim As Single pannedLeft = state.displayLevel(channelIndex)
        Dim As Single pannedRight = state.displayLevel(channelIndex)
        If state.channelPan(channelIndex) > 0.0 Then
            pannedLeft *= 1.0 - state.channelPan(channelIndex)
        ElseIf state.channelPan(channelIndex) < 0.0 Then
            pannedRight *= 1.0 + state.channelPan(channelIndex)
        End If
        If pannedLeft > masterLeft Then
            masterLeft = pannedLeft
        End If
        If pannedRight > masterRight Then
            masterRight = pannedRight
        End If
    Next

    state.masterLeftLevel = mixerMeter_ClampUnit( _
        masterLeft * state.masterVolume)
    state.masterRightLevel = mixerMeter_ClampUnit( _
        masterRight * state.masterVolume)
End Sub


Public Function mixerMeter_ChannelLevel( _
    ByRef state As OseMixerMeterState, _
    ByVal channelIndex As Integer _
) As Single
    If channelIndex < 0 OrElse _
        channelIndex >= OSE_MIXER_METER_CHANNEL_COUNT Then
        Return 0.0
    End If
    Return mixerMeter_ClampUnit(state.displayLevel(channelIndex))
End Function


Public Function mixerMeter_MasterLeftLevel( _
    ByRef state As OseMixerMeterState _
) As Single
    Return mixerMeter_ClampUnit(state.masterLeftLevel)
End Function


Public Function mixerMeter_MasterRightLevel( _
    ByRef state As OseMixerMeterState _
) As Single
    Return mixerMeter_ClampUnit(state.masterRightLevel)
End Function

/' end of mixer_meter.bas '/
