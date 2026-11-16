/'
    Project: OpenMidiSesh
    File: src/editor/input_monitor.bi
    Targets: Shared editor implementation in the fb dialect.
    Module API: Private editor include; state.bi owns the monitor state.
    Purpose: Play incoming MIDI independently of recording and the document.
    Responsibilities: Monitor toggle, note ownership, sustain and channel setup.
    This file intentionally does NOT contain: device callbacks, synthesis or capture timestamps.
    All state lives in state.bi and is accessed only on the editor thread.
'/
#ifndef __OSE_INPUT_MONITOR_BI__
#define __OSE_INPUT_MONITOR_BI__

Private Sub session_ReleaseMonitorChannel(ByVal channelIndex As Integer)
    For keyNumber As Integer = 0 To 127
        If session_MonitorHeld(channelIndex, keyNumber) <> 0 Then _
            softwareSynth_StopMidiNote channelIndex, keyNumber
        session_MonitorHeld(channelIndex, keyNumber) = 0
        session_MonitorReleased(channelIndex, keyNumber) = 0
    Next
    session_MonitorSustain(channelIndex) = 0
    If midiOutput_IsOpen() <> 0 Then
        midiOutput_Send &HB0 Or channelIndex, 64, 0
        midiOutput_Send &HB0 Or channelIndex, 123, 0
    End If
End Sub

Private Sub session_ResetInputMonitor()
    For channelIndex As Integer = 0 To 15
        session_ReleaseMonitorChannel channelIndex
        session_LiveInputProgram(channelIndex) = 0
        session_MonitorVolume(channelIndex) = 100
        session_MonitorExpression(channelIndex) = 127
        session_MonitorPan(channelIndex) = 64
        session_MonitorBend(channelIndex) = 8192
    Next
End Sub

Public Sub session_OnMonitor(ByVal source As Widget Ptr)
    If session_MonitorEnabled <> 0 Then
        session_MonitorEnabled = 0
        session_MonitorInputWasOpen = 0
        session_ResetInputMonitor()
        If session_MonitorAutoOpened <> 0 AndAlso session_LiveRecording = 0 Then _
            midiInput_Close()
        session_MonitorAutoOpened = 0
        session_SetStatus "MIDI monitor off."
        Exit Sub
    End If
    If midiInput_IsOpen() = 0 Then
        Dim As Integer deviceCount = midiInput_GetDeviceCount()
        If deviceCount <= 0 Then
            session_SetStatus "Connect a MIDI input, then press Monitor."
            Exit Sub
        End If
        If session_MidiInputDeviceIndex < 0 OrElse _
            session_MidiInputDeviceIndex >= deviceCount Then session_MidiInputDeviceIndex = 0
        If midiInput_Open(session_MidiInputDeviceIndex) = 0 Then
            session_SetStatus "Could not open MIDI input. Choose MIDI In to try another device."
            Exit Sub
        End If
        session_MonitorAutoOpened = -1
    End If
    If session_LiveRecording = 0 Then midiInput_ClearPending()
    session_ResetInputMonitor()
    session_MonitorEnabled = -1
    session_SetStatus "MIDI monitor on. Play the connected input."
End Sub

Private Sub session_MonitorMidiInput(ByRef message As OseMidiInputMessage)
    If message.messageKind <> OSE_MIDI_INPUT_SHORT_MESSAGE OrElse _
        message.status < &H80 OrElse message.status > &HEF OrElse _
        message.data1 > 127 OrElse message.data2 > 127 Then Exit Sub
    Dim As Integer channelIndex = message.status And &H0F
    Dim As Integer messageType = message.status And &HF0
    Dim As Integer keyNumber = message.data1
    Dim As Integer value = message.data2
    If midiOutput_IsOpen() <> 0 Then _
        midiOutput_Send message.status, keyNumber, value

    Select Case messageType
        Case &HC0
            session_LiveInputProgram(channelIndex) = keyNumber
        Case &HE0
            session_MonitorBend(channelIndex) = keyNumber + value * 128
        Case &HB0
            Select Case keyNumber
                Case 7 : session_MonitorVolume(channelIndex) = value
                Case 10 : session_MonitorPan(channelIndex) = value
                Case 11 : session_MonitorExpression(channelIndex) = value
                Case 64
                    session_MonitorSustain(channelIndex) = IIf(value >= 64, -1, 0)
                    If value < 64 Then
                        For pitch As Integer = 0 To 127
                            If session_MonitorReleased(channelIndex, pitch) <> 0 Then
                                softwareSynth_StopMidiNote channelIndex, pitch
                                session_MonitorHeld(channelIndex, pitch) = 0
                                session_MonitorReleased(channelIndex, pitch) = 0
                            End If
                        Next
                    End If
                Case 120, 123
                    session_ReleaseMonitorChannel channelIndex
                Case 121
                    session_ReleaseMonitorChannel channelIndex
                    session_MonitorExpression(channelIndex) = 127
                    session_MonitorBend(channelIndex) = 8192
            End Select
        Case &H80, &H90
            If messageType = &H80 OrElse value = 0 Then
                If session_MonitorSustain(channelIndex) <> 0 Then
                    session_MonitorReleased(channelIndex, keyNumber) = -1
                Else
                    softwareSynth_StopMidiNote channelIndex, keyNumber
                    session_MonitorHeld(channelIndex, keyNumber) = 0
                End If
                Exit Sub
            End If
            softwareSynth_StopMidiNote channelIndex, keyNumber
            session_MonitorReleased(channelIndex, keyNumber) = 0
            Dim As OsePlaybackMixValues mixValues
            playbackMix_Calculate mixValues, session_MonitorVolume(channelIndex), _
                session_MonitorExpression(channelIndex), session_MonitorPan(channelIndex), _
                value, session_MasterVolume, -1
            Dim As OseSoftwareSynthPlayOptions options
            options.bankNumber = IIf(channelIndex = 9, 128, 0)
            options.fallbackVoiceChannel = -1
            ' A live voice is stopped by note-off or panic, not a short preview
            ' timer. The synth's one-hour bound also limits malformed held notes.
            session_MonitorHeld(channelIndex, keyNumber) = softwareSynth_PlayMidiNote( _
                channelIndex, keyNumber, session_LiveInputProgram(channelIndex), _
                session_MonitorBend(channelIndex), 3600.0, mixValues, options)
            mixerMeter_Trigger session_MixerMeter, channelIndex, CSng(value) / 127.0, 0.18
    End Select
    If messageType = &HE0 OrElse messageType = &HB0 Then
        Dim As OsePlaybackMixValues channelMix
        playbackMix_Calculate channelMix, session_MonitorVolume(channelIndex), _
            session_MonitorExpression(channelIndex), session_MonitorPan(channelIndex), _
            127, session_MasterVolume, -1
        softwareSynth_UpdateMidiChannel channelIndex, session_MonitorBend(channelIndex), channelMix
    End If
End Sub
#endif
/' end of src/editor/input_monitor.bi '/
