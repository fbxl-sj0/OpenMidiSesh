/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/midi_transport.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Coordinate native MIDI transport and audition voices.

    Responsibilities:

        - open and close the selected native MIDI endpoint
        - track audition-note ownership and stop active voices

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_MIDI_TRANSPORT_BI__
#define __OSE_EDITOR_MIDI_TRANSPORT_BI__


' -------------------------------------------------------------------------
' Optional native MIDI output transport
' -------------------------------------------------------------------------

Private Sub session_SendMidiOutputDefaultSetup()
    If midiOutput_IsOpen() = 0 Then
        Exit Sub
    End If
    midiOutput_SendDefaultSetupSequence()
End Sub

Private Sub session_SendMidiOutputSetup()
    If midiOutput_IsOpen() = 0 Then
        Exit Sub
    End If

    For channelIndex As Integer = 0 To SESSION_CHANNEL_COUNT - 1
        midiOutput_Send &HC0 Or channelIndex, _
            session_Summary.channelProgram(channelIndex), 0
        midiOutput_Send &HB0 Or channelIndex, 7, _
            session_Summary.channelVolume(channelIndex)
        midiOutput_Send &HB0 Or channelIndex, 10, _
            session_Summary.channelPan(channelIndex)
        midiOutput_Send &HB0 Or channelIndex, 11, _
            session_Summary.channelExpression(channelIndex)
        midiOutput_Send &HB0 Or channelIndex, 91, _
            session_Summary.channelReverb(channelIndex)
        midiOutput_Send &HB0 Or channelIndex, 93, _
            session_Summary.channelChorus(channelIndex)

        Dim As Integer pitchBend = session_Summary.channelPitchBend(channelIndex)
        If pitchBend < 0 Then
            pitchBend = 0
        End If
        If pitchBend > 16383 Then
            pitchBend = 16383
        End If
        midiOutput_Send &HE0 Or channelIndex, _
            pitchBend And &H7F, (pitchBend Shr 7) And &H7F
    Next
End Sub


Private Sub session_ResyncMidiOutput()
    If midiOutput_IsOpen() = 0 Then
        Exit Sub
    End If

    midiOutput_AllNotesOff()
    If session_Playing = 0 OrElse session_Paused <> 0 Then
        session_SendMidiOutputSetup()
        Exit Sub
    End If

    Dim As ULongInt currentTick = midi_SecondsToTicks( _
        session_Summary, session_PlaybackElapsed)
    If session_SelectedNotePlaybackActive <> 0 AndAlso _
        currentTick < session_SelectedNotePlayback.startTick Then _
        currentTick = session_SelectedNotePlayback.startTick
    session_SendMidiOutputRange currentTick, 0, -1
End Sub


Private Sub session_SendMidiOutputRange( _
    ByVal currentTick As ULongInt, _
    ByVal previousTick As ULongInt, _
    ByVal firstUpdate As Integer _
)
    ' A file render is local-only. It must not replay the whole arrangement
    ' through a connected external synthesizer merely because MIDI Thru is on.
    If session_WavExport.active <> 0 Then
        Exit Sub
    End If
    If midiOutput_IsOpen() = 0 Then
        Exit Sub
    End If

    session_RebuildPlaybackChannelEventOrder()
    If firstUpdate <> 0 Then
        session_SendMidiOutputDefaultSetup()
    End If

    ' Release notes before starting notes at the same tick. This avoids a
    ' hardware synthesizer treating a same-key replacement as a stuck note.
    If firstUpdate = 0 Then
        For noteIndex As Integer = 0 To session_PlaybackNoteCount() - 1
            Dim As MidiEditableNote editableNote
            If session_GetPlaybackNote(noteIndex, editableNote) = 0 Then _
                Continue For
            If editableNote.channel >= SESSION_CHANNEL_COUNT OrElse _
                session_ChannelIsAudible(editableNote.channel) = 0 Then Continue For
            Dim As ULongInt noteEndTick = editableNote.startTick + _
                editableNote.durationTicks
            If noteEndTick < editableNote.startTick Then _
                noteEndTick = OSE_MAX_MIDI_TICK
            If noteEndTick > previousTick AndAlso noteEndTick <= currentTick Then
                midiOutput_Send &H80 Or editableNote.channel, _
                    editableNote.keyNumber, 0
            End If
        Next
    End If

    For eventIndex As Integer = 0 To _
        session_PlaybackOrderedChannelEventCount - 1
        Dim As MidiChannelEventPoint channelEvent = _
            session_PlaybackOrderedChannelEvents(eventIndex)
        If channelEvent.channel >= SESSION_CHANNEL_COUNT OrElse _
            session_ChannelIsAudible(channelEvent.channel) = 0 Then Continue For

        Dim As Integer inRange = 0
        If firstUpdate <> 0 Then
            If channelEvent.tick <= currentTick Then
                inRange = -1
            End If
        ElseIf channelEvent.tick > previousTick AndAlso _
            channelEvent.tick <= currentTick Then
            inRange = -1
        End If
        If inRange = 0 Then
            Continue For
        End If

        Dim As Integer data2 = channelEvent.data2
        If channelEvent.messageType = &HC0 OrElse _
            channelEvent.messageType = &HD0 Then data2 = 0
        midiOutput_Send CInt(channelEvent.messageType) Or _
            CInt(channelEvent.channel), channelEvent.data1, data2
    Next

    For noteIndex As Integer = 0 To session_PlaybackNoteCount() - 1
        Dim As MidiEditableNote editableNote
        If session_GetPlaybackNote(noteIndex, editableNote) = 0 Then
            Continue For
        End If
        If editableNote.channel >= SESSION_CHANNEL_COUNT OrElse _
            session_ChannelIsAudible(editableNote.channel) = 0 Then Continue For

        Dim As ULongInt noteEndTick = editableNote.startTick + _
            editableNote.durationTicks
        If noteEndTick < editableNote.startTick Then _
            noteEndTick = OSE_MAX_MIDI_TICK
        If noteEndTick <= currentTick Then
            Continue For
        End If

        Dim As Integer inRange = 0
        If firstUpdate <> 0 Then
            If editableNote.startTick <= currentTick Then
                inRange = -1
            End If
        ElseIf editableNote.startTick > previousTick AndAlso _
            editableNote.startTick <= currentTick Then
            inRange = -1
        End If
        If inRange <> 0 Then
            midiOutput_Send &H90 Or editableNote.channel, _
                editableNote.keyNumber, editableNote.velocity
        End If
    Next
End Sub


Private Sub session_PlayAudioClips(ByVal currentTick As ULongInt)
    For clipIndex As Integer = 0 To audio_GetCount() - 1
        Dim As OseAudioClip clip
        If audio_GetClip(clipIndex, clip) = 0 Then
            Continue For
        End If
        Dim As Integer shouldStart = 0
        If session_PlaybackFirstUpdate <> 0 Then
            If clip.startTick <= currentTick Then
                shouldStart = -1
            End If
        ElseIf clip.startTick > session_PlaybackLastTick AndAlso _
            clip.startTick <= currentTick Then
            shouldStart = -1
        End If
        If shouldStart = 0 Then
            Continue For
        End If

        ' sfxlib sample playback shares the channel controls with the synth.
        ' The dedicated sample lane is intentionally documented as channel 16.
        Dim As OsePlaybackMixValues playbackValues
        playbackMix_Calculate playbackValues, _
            session_PlaybackState.controllerVolume(SESSION_AUDIO_CHANNEL), _
            session_PlaybackState.controllerExpression(SESSION_AUDIO_CHANNEL), _
            session_PlaybackState.controllerPan(SESSION_AUDIO_CHANNEL), 127, _
            session_MasterVolume, _
            session_ChannelIsAudible(SESSION_AUDIO_CHANNEL)
        Dim As Single clipGain = CSng(clip.gainPermille) / 1000.0
        volume SESSION_AUDIO_CHANNEL, playbackValues.channelGain * clipGain
        pan SESSION_AUDIO_CHANNEL, 0.0
        If audioSampleSlots_Play(SESSION_AUDIO_CHANNEL, clipIndex, 1.0) <> 0 Then
            mixerMeter_Trigger session_MixerMeter, SESSION_AUDIO_CHANNEL, _
                clipGain, _
                CDbl(clip.durationMilliseconds) / 1000.0
        End If
    Next
End Sub


Private Sub session_UpdateMixerMeters()
    Dim As Double currentClock = Timer
    Dim As Double elapsedSeconds
    If session_MixerMeterLastClock > 0.0 Then
        elapsedSeconds = currentClock - session_MixerMeterLastClock
        If elapsedSeconds < 0.0 Then
            elapsedSeconds += 86400.0
        End If
        If elapsedSeconds > 1.0 Then
            elapsedSeconds = 0.0
        End If
    End If
    session_MixerMeterLastClock = currentClock

    session_ApplyMixerState()
    mixerMeter_Update session_MixerMeter, elapsedSeconds, session_Paused
End Sub


Private Sub session_WrapSelectedLoop()
    If session_SelectedNoteLooping = 0 OrElse session_SelectedNotePlaybackActive = 0 Then
        Exit Sub
    End If
    Dim As Double startSeconds = midi_TicksToSeconds(session_Summary, session_SelectedNotePlayback.startTick)
    Dim As Double endSeconds = midi_TicksToSeconds(session_Summary, session_SelectedNoteLoopEnd)
    Dim As Double loopSeconds = endSeconds - startSeconds
    If loopSeconds <= 0 Then
        session_StopPlayback()
        Exit Sub
    End If
    If session_PlaybackElapsed < endSeconds Then
        Exit Sub
    End If
    ' Keep the fraction left after crossing the boundary. Restarting the clock
    ' at zero on each GUI frame would slowly lengthen the phrase. After a late
    ' frame, skip missed cycles instead of emitting a burst of overdue notes.
    Dim As Double relativeSeconds = session_PlaybackElapsed - startSeconds
    session_PlaybackElapsed = startSeconds + relativeSeconds - Int(relativeSeconds / loopSeconds) * loopSeconds
    For voiceChannel As Integer = 0 To SESSION_CHANNEL_COUNT - 1
        SFX STOP CHANNEL, voiceChannel
        generatedVoiceStop_Channel voiceChannel
    Next
    soundfontSynth_StopAll()
    midiOutput_AllNotesOff()
    mixerMeter_StopAll session_MixerMeter
    session_ResetPlaybackChannelState()
    session_PlaybackLastTick = session_SelectedNotePlayback.startTick
    session_PlaybackFirstUpdate = -1
End Sub

Private Sub session_UpdateSoftwarePlayback()
    If session_Playing = 0 Then
        Exit Sub
    End If
    ' Imports and completed captures can add clips during a run. Check the
    ' shared boundary before scheduling any note or clip, including on pause.
    If session_SelectedNotePlaybackActive = 0 Then
        If session_RequireArrangementAudioSpeed() = 0 Then
            session_StopPlayback()
            Exit Sub
        End If
    End If
    If session_Paused <> 0 Then
        session_PlaybackLastClock = Timer
        Exit Sub
    End If

    Dim As Double currentClock = Timer
    Dim As Double elapsedDelta = playbackTiming_ElapsedDelta( _
        session_PlaybackLastClock, currentClock)
    session_PlaybackLastClock = currentClock
    session_PlaybackElapsed += elapsedDelta * session_PlaybackSpeedScale
    session_WrapSelectedLoop()
    If session_Playing = 0 Then
        Exit Sub
    End If

    Dim As ULongInt currentTick = midi_SecondsToTicks( _
        session_Summary, session_PlaybackElapsed)
    If session_SelectedNotePlaybackActive <> 0 AndAlso _
        currentTick < session_SelectedNotePlayback.startTick Then _
        currentTick = session_SelectedNotePlayback.startTick
    If session_WavExport.active <> 0 Then
        Dim As ULongInt timelineTicks = session_TimelineDurationTicks()
        Dim As Integer exportPercent
        If timelineTicks > 0 Then
            exportPercent = CInt((CDbl(currentTick) * _
                CDbl(SESSION_PERCENT_COMPLETE)) / _
                CDbl(timelineTicks))
        End If
        If exportPercent < 0 Then
            exportPercent = 0
        End If
        If exportPercent > SESSION_PERCENT_COMPLETE Then _
            exportPercent = SESSION_PERCENT_COMPLETE
        If exportPercent <> session_WavExportLastPercent Then
            session_WavExportLastPercent = exportPercent
            session_SetStatus "Exporting WAV through sfxlib: " + _
                LTrim(Str(exportPercent)) + "%" + _
                session_AudioAvailabilitySuffix()
        End If
    End If
    Dim As Integer firstUpdate = session_PlaybackFirstUpdate
    session_ApplyPlaybackChannelEvents currentTick, session_PlaybackLastTick, _
        firstUpdate
    ' CC7, CC10, and CC11 automation changes the shared channel stage. The
    ' individual SOUND command below receives velocity only, so CC7 is not
    ' accidentally applied twice.
    session_ApplyMixerState()
    session_SendMidiOutputRange currentTick, session_PlaybackLastTick, _
        firstUpdate

    For noteIndex As Integer = 0 To session_PlaybackNoteCount() - 1
        Dim As MidiEditableNote editableNote
        If session_GetPlaybackNote(noteIndex, editableNote) = 0 Then
            Continue For
        End If

        Dim As ULongInt noteEndTick = editableNote.startTick + _
            editableNote.durationTicks
        If noteEndTick < editableNote.startTick Then _
            noteEndTick = OSE_MAX_MIDI_TICK
        If playbackTiming_ShouldStart(editableNote.startTick, noteEndTick, _
            session_PlaybackLastTick, currentTick, _
            session_PlaybackFirstUpdate) = 0 Then Continue For
        If editableNote.channel >= SESSION_CHANNEL_COUNT Then
            Continue For
        End If
        If session_ChannelIsAudible(editableNote.channel) = 0 Then
            Continue For
        End If

        Dim As OsePlaybackMixValues playbackValues
        playbackMix_Calculate playbackValues, _
            session_PlaybackState.controllerVolume(editableNote.channel), _
            session_PlaybackState.controllerExpression(editableNote.channel), _
            session_PlaybackState.controllerPan(editableNote.channel), _
            editableNote.velocity, session_MasterVolume, _
            session_ChannelIsAudible(editableNote.channel)
        Dim As Single voiceVolume = playbackValues.voiceGain
        If voiceVolume <= 0.001 Then
            Continue For
        End If

        Dim As Double durationSeconds = _
            playbackTiming_WallDuration( _
                midi_TicksToSeconds(session_Summary, noteEndTick), _
                session_PlaybackElapsed, session_PlaybackSpeedScale)
        If durationSeconds <= 0.0 Then
            Continue For
        End If

        Dim As OseSoftwareSynthPlayOptions playOptions
        playOptions.bankNumber = playbackState_BankNumber( _
            session_PlaybackState, editableNote.channel)
        playOptions.fallbackVoiceChannel = -1
        If softwareSynth_PlayMidiNote(editableNote.channel, _
            editableNote.keyNumber, _
            session_PlaybackState.programNumber(editableNote.channel), _
            session_PlaybackState.pitchBend(editableNote.channel), _
            CSng(durationSeconds), playbackValues, playOptions) = 0 Then _
            Continue For
        ' The note source feeds velocity to the meter. CC7, expression, pan,
        ' mute or solo state, and master volume are applied by the meter mix.
        mixerMeter_Trigger session_MixerMeter, editableNote.channel, _
            voiceVolume / OSE_PLAYBACK_VOICE_HEADROOM, durationSeconds
    Next

    ' A selected-note audition is deliberately note-only. Arrangement audio
    ' clips remain tied to Play so an isolated phrase cannot start unrelated
    ' recorded material which happens to share its score range.
    If session_SelectedNotePlaybackActive = 0 Then _
        session_PlayAudioClips currentTick

    session_PlaybackLastTick = currentTick
    session_PlaybackFirstUpdate = 0
    If currentTick >= session_PlaybackEndTick() AndAlso session_SelectedNoteLooping = 0 Then
        If session_WavExport.active <> 0 Then
            Dim As String outputFilename = session_WavExport.filename
            session_WavExportFinishing = -1
            session_StopPlayback()
            session_WavExportFinishing = 0

            Dim As ULongInt underrunCount
            Dim As String exportError
            If wavExport_Finish(session_WavExport, underrunCount, _
                exportError) = 0 Then
                session_SetStatus "WAV export failed: " + exportError
            Else
                Dim As OseWaveInfo exportedWave
                If audio_InspectWave(outputFilename, exportedWave) = 0 Then
                    session_SetStatus "WAV export failed validation: " + _
                        outputFilename
                ElseIf underrunCount > 0 Then
                    session_SetStatus "Exported WAV with " + _
                        LTrim(Str(underrunCount)) + " output underruns: " + _
                        outputFilename
                Else
                    session_SetStatus "Exported WAV: " + outputFilename + _
                        session_AudioAvailabilitySuffix()
                End If
            End If
            session_WavExportLastPercent = -1
        ElseIf session_SelectedNotePlaybackActive <> 0 Then
            Dim As Integer completedNoteCount = _
                session_SelectedNotePlayback.count
            session_StopPlayback()
            If completedNoteCount = 1 Then
                session_SetStatus "Selected note finished."
            Else
                session_SetStatus LTrim(Str(completedNoteCount)) + _
                    " selected notes finished."
            End If
        Else
            session_StopPlayback()
            session_SetStatus "Playback finished."
        End If
    End If
End Sub

#endif

/' end of src/editor/midi_transport.bi '/
