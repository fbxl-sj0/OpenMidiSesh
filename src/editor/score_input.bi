/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/score_input.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Handle score selection and editing gestures.

    Responsibilities:

        - map bounded score coordinates to musical edits
        - coordinate selection, dragging, recording and automation input

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_SCORE_INPUT_BI__
#define __OSE_EDITOR_SCORE_INPUT_BI__


' -------------------------------------------------------------------------
' Selection and custom input
' -------------------------------------------------------------------------

Private Sub session_SynchronizeNoteSelection()
    noteSelection_SynchronizePrimary session_NoteSelection, _
        session_SelectedNote, midi_GetEditableNoteCount()
    session_SelectedNote = session_NoteSelection.primaryNoteIndex
End Sub


Private Sub session_ClearNoteSelection()
    noteSelection_Clear session_NoteSelection
    session_SelectedNote = -1
End Sub


Private Sub session_SelectOnlyNote(ByVal noteIndex As Integer)
    If noteSelection_SelectOnly(session_NoteSelection, noteIndex) = 0 Then _
        Exit Sub
    session_SelectedNote = session_NoteSelection.primaryNoteIndex
End Sub


Private Function session_NoteIsSelected(ByVal noteIndex As Integer) As Integer
    Return noteSelection_Contains(session_NoteSelection, noteIndex)
End Function


Private Function session_SelectionStatusText() As String
    Dim As NoteSelectionSummary selectionSummary
    If noteSelection_Summarize(session_NoteSelection, selectionSummary) = 0 Then _
        Return "No notes selected."

    Dim As String selectionName
    If selectionSummary.count = 1 Then
        selectionName = midi_KeyDisplayName(selectionSummary.minimumPitch) + _
            " selected"
    Else
        selectionName = LTrim(Str(selectionSummary.count)) + " notes selected"
    End If
    Return selectionName + " | " + _
        session_MusicalPositionText(selectionSummary.startTick) + " to " + _
        session_MusicalPositionText(selectionSummary.endTick) + " | " + _
        LTrim(Str(selectionSummary.endTick - selectionSummary.startTick)) + _
        " ticks."
End Function


Private Sub session_AnnounceSelection(ByVal instructionText As String)
    Dim As String statusText = session_SelectionStatusText()
    instructionText = Trim(instructionText)
    If instructionText <> "" AndAlso session_NoteSelection.count > 0 Then _
        statusText += " " + instructionText
    session_SetStatus statusText
End Sub


Public Sub session_SelectAllNotes()
    Dim As Integer noteCount = midi_GetEditableNoteCount()
    If noteCount <= 0 Then
        session_ClearNoteSelection()
        session_SetStatus "Select All ignored: the score has no notes."
        Exit Sub
    End If
    If noteCount > OSE_NOTE_SELECTION_CAPACITY Then
        session_SetStatus "Select All failed: the note limit was exceeded."
        Exit Sub
    End If

    noteSelection_Clear session_NoteSelection
    For noteIndex As Integer = 0 To noteCount - 1
        If noteSelection_Add(session_NoteSelection, noteIndex, -1) = 0 Then
            session_ClearNoteSelection()
            session_SetStatus "Select All failed: selection storage is full."
            Exit Sub
        End If
    Next
    session_SelectedNote = session_NoteSelection.primaryNoteIndex
    session_AnnounceSelection ""
End Sub


Private Sub session_SetSelectedTrackPreservingNotes(ByVal trackIndex As Integer)
    If trackIndex < 0 OrElse trackIndex >= session_Summary.trackCount Then
        Exit Sub
    End If
    If session_TrackList <> 0 AndAlso session_TrackList->data <> 0 Then
        Dim As ListBoxData Ptr trackData = Cast( _
            ListBoxData Ptr, session_TrackList->data)
        If trackIndex < trackData->item_count Then _
            trackData->selected_index = trackIndex
    End If
    session_SelectedTrack = trackIndex
End Sub


Public Sub session_CopySelectedNotes()
    session_SynchronizeNoteSelection()
    If session_NoteSelection.count <= 0 Then
        session_SetStatus "Copy ignored: no notes are selected."
        Exit Sub
    End If

    If noteClipboard_Capture(session_NoteClipboard, _
        session_NoteSelection) = 0 Then
        session_SetStatus "Copy failed: the note selection changed."
        Exit Sub
    End If
    session_SetStatus "Copied " + Str(session_NoteClipboard.count) + _
        IIf(session_NoteClipboard.count = 1, " note.", " notes.")
End Sub


Private Function session_ScoreSnapTicks() As ULongInt
    Dim As Integer denominators(0 To 4) = {4, 8, 16, 32, 12}
    If session_SnapIndex < 0 OrElse session_SnapIndex > 4 Then
        session_SnapIndex = 2
    End If
    Dim As ULongInt snapTicks = 1
    If session_Summary.division > 0 Then _
        snapTicks = CULngInt(session_Summary.division) * 4 \ denominators(session_SnapIndex)
    If snapTicks = 0 Then
        snapTicks = 1
    End If
    Return snapTicks
End Function


Public Sub session_PasteCopiedNotes()
    If session_NoteClipboard.count <= 0 OrElse _
        session_NoteClipboard.count > OSE_NOTE_SELECTION_CAPACITY Then
        session_SetStatus "Paste ignored: the note clipboard is empty."
        Exit Sub
    End If
    session_ActiveScoreTool = SESSION_SCORE_TOOL_PASTE
    session_AddPaletteVisible = 0
    session_SetStatus _
        "Paste tool: click the ruler location and destination staff."
End Sub


Public Sub session_DeleteSelectedNotes()
    session_SynchronizeNoteSelection()
    If session_NoteSelection.count <= 0 Then
        session_SetStatus "Delete ignored: no notes are selected."
        Exit Sub
    End If

    Dim As Integer deleteCount = session_NoteSelection.count
    session_StopPlayback()
    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If
    If midi_RemoveEditableNotes(session_Summary, _
        @session_NoteSelection.noteIndices(0), deleteCount) = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Delete failed: the note selection changed."
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If

    session_ClearNoteSelection()
    session_ScoreDragNote = -1
    session_Dirty = -1
    session_SetStatus "Deleted " + Str(deleteCount) + _
        IIf(deleteCount = 1, " note.", " notes.")
End Sub


Public Sub session_CutSelectedNotes()
    session_SynchronizeNoteSelection()
    If session_NoteSelection.count <= 0 Then
        session_SetStatus "Cut ignored: no notes are selected."
        Exit Sub
    End If

    If noteClipboard_Capture(session_NoteClipboard, _
        session_NoteSelection) = 0 Then
        session_SetStatus "Cut failed: the note selection changed."
        Exit Sub
    End If

    Dim As Integer cutCount = session_NoteSelection.count
    session_DeleteSelectedNotes()
    If session_NoteSelection.count <> 0 Then
        Exit Sub
    End If

    session_ActiveScoreTool = SESSION_SCORE_TOOL_PASTE
    session_AddPaletteVisible = 0
    session_SetStatus "Cut " + Str(cutCount) + _
        IIf(cutCount = 1, _
        " note. Click a staff location to paste it.", _
        " notes. Click a staff location to paste them.")
End Sub


Private Sub session_UpdateSelection()
    If session_TrackList = 0 Then
        Exit Sub
    End If
    Dim As Integer selectedIndex = listbox_GetSelectedIndex(session_TrackList)
    If selectedIndex >= 0 AndAlso selectedIndex < session_Summary.trackCount Then
        If selectedIndex <> session_SelectedTrack Then
            session_SelectedNote = -1
        End If
        session_SelectedTrack = selectedIndex
    End If
End Sub


Private Sub session_ToggleMute(ByVal channelIndex As Integer)
    If channelIndex < 0 OrElse channelIndex >= SESSION_CHANNEL_COUNT Then
        Exit Sub
    End If
    mixerState_ToggleMute session_MixerChannels, channelIndex
    If session_Playing <> 0 Then
        session_ResyncMidiOutput()
    End If
End Sub


Private Sub session_ToggleSolo(ByVal channelIndex As Integer)
    If channelIndex < 0 OrElse channelIndex >= SESSION_CHANNEL_COUNT Then
        Exit Sub
    End If
    mixerState_ToggleSolo session_MixerChannels, channelIndex
    session_ApplyMixerState()
    If session_Playing <> 0 Then
        session_ResyncMidiOutput()
    End If
End Sub


Private Sub session_ToggleRecord(ByVal channelIndex As Integer)
    If channelIndex < 0 OrElse channelIndex >= SESSION_CHANNEL_COUNT Then
        Exit Sub
    End If

    Dim As Integer nowArmed = _
        mixerState_ToggleRecord(session_MixerChannels, channelIndex)
    If nowArmed <> 0 Then
        session_StepEntryTick = session_Summary.durationTicks
        For keyIndex As Integer = 0 To 127
            session_StepEntryLastState(keyIndex) = 0
        Next
        session_SetStatus "Step recording armed on channel " + _
            Str(channelIndex + 1) + "."
    Else
        session_SetStatus "Step recording disarmed."
    End If
End Sub


Private Function session_RecordChannel() As Integer
    Return mixerState_RecordChannel(session_MixerChannels)
End Function


Private Function session_StepEntryPitch(ByVal scanCode As Integer) As Integer
    Dim As Integer noteOffset = -1
    Select Case scanCode
        Case FB.SC_Z
            noteOffset = 0
        Case FB.SC_S
            noteOffset = 1
        Case FB.SC_X
            noteOffset = 2
        Case FB.SC_D
            noteOffset = 3
        Case FB.SC_C
            noteOffset = 4
        Case FB.SC_V
            noteOffset = 5
        Case FB.SC_G
            noteOffset = 6
        Case FB.SC_B
            noteOffset = 7
        Case FB.SC_H
            noteOffset = 8
        Case FB.SC_N
            noteOffset = 9
        Case FB.SC_J
            noteOffset = 10
        Case FB.SC_M
            noteOffset = 11
        Case FB.SC_Q
            noteOffset = 12
        Case FB.SC_2
            noteOffset = 13
        Case FB.SC_W
            noteOffset = 14
        Case FB.SC_3
            noteOffset = 15
        Case FB.SC_E
            noteOffset = 16
        Case FB.SC_R
            noteOffset = 17
        Case FB.SC_5
            noteOffset = 18
        Case FB.SC_T
            noteOffset = 19
        Case FB.SC_6
            noteOffset = 20
        Case FB.SC_Y
            noteOffset = 21
        Case FB.SC_7
            noteOffset = 22
        Case FB.SC_U
            noteOffset = 23
    End Select
    If noteOffset < 0 Then
        Return -1
    End If
    Dim As Integer pitch = session_KeyboardBasePitch + noteOffset
    If pitch < 0 OrElse pitch > 127 Then
        Return -1
    End If
    Return pitch
End Function


Private Sub session_StopAuditionPitch(ByVal pitch As Integer)
    If pitch < 0 OrElse pitch > 127 Then
        Exit Sub
    End If
    Dim As Integer auditionChannel = session_AuditionChannelForPitch(pitch)
    If auditionChannel < 0 OrElse auditionChannel >= SESSION_CHANNEL_COUNT Then _
        Exit Sub
    generatedVoiceStop_Channel auditionChannel
    soundfontSynth_StopChannel auditionChannel
    mixerMeter_StopChannel session_MixerMeter, auditionChannel
    session_AuditionChannelForPitch(pitch) = -1
    If session_AuditionPitchForChannel(auditionChannel) = pitch Then _
        session_AuditionPitchForChannel(auditionChannel) = -1
End Sub


Private Sub session_StopAllAuditionNotes()
    For pitch As Integer = 0 To 127
        session_StopAuditionPitch pitch
    Next
End Sub


Private Function session_RestartAudioRuntime( _
    ByVal announceChange As Integer _
) As Integer
    /'
        A full sfxlib restart destroys synthesizer definitions, loaded sample
        slots, effect state, and channel mix values. Rebuild all four through
        their existing shared adapters so device recovery cannot leave a
        partially working editor. Active captures are left under operator
        control because tearing their input stream down would discard data.
    '/
    If session_WavExport.active <> 0 Then
        If announceChange <> 0 Then _
            session_SetStatus "Stop or finish the WAV export before restarting audio."
        Return 0
    End If
    If session_AudioCaptureActive <> 0 OrElse _
        session_MicCaptureActive <> 0 Then
        If announceChange <> 0 Then _
            session_SetStatus "Stop the active audio capture before restarting audio."
        Return 0
    End If

    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    session_StopPlayback()
    session_StopAllAuditionNotes()
    audioSampleSlots_Clear()
    masterEffect_Reset()
    soundfontSynth_SuspendOutput()

    If sfxRuntime_Restart() = 0 Then
        Dim As String failedRestartSoundFontError
        soundfontSynth_ResumeOutput failedRestartSoundFontError
        If announceChange <> 0 Then _
            session_SetStatus "Audio engine restart failed."
        Return 0
    End If

    session_ConfigureSynth()
    Dim As Integer samplesRestored = session_LoadAudioSamples()
    Dim As String effectError
    Dim As Integer effectRestored = masterEffect_Apply( _
        session_MasterEchoWet, session_MasterEchoFeedback, effectError)
    session_ApplyMixerState()
    Dim As String soundFontRestartError
    Dim As Integer soundFontRestored = _
        soundfontSynth_ResumeOutput(soundFontRestartError)

    If announceChange <> 0 Then
        If soundFontRestored = 0 Then
            session_SetStatus _
                "Audio engine restarted, but the SoundFont stream could not be restored: " + _
                soundFontRestartError
        ElseIf effectRestored = 0 Then
            session_SetStatus _
                "Audio engine restarted, but the master effect could not be restored: " + _
                effectError
        ElseIf samplesRestored = 0 Then
            session_SetStatus "Audio engine restarted." + _
                session_AudioAvailabilitySuffix()
        Else
            session_SetStatus "Audio engine restarted."
        End If
    End If
    Return -1
End Function


Private Sub session_StartAuditionPitch(ByVal pitch As Integer)
    If pitch < 0 OrElse pitch > 127 Then
        Exit Sub
    End If
    If session_Playing <> 0 OrElse session_WavExport.active <> 0 Then
        session_SetStatus "Stop playback before auditioning keyboard keys."
        Exit Sub
    End If
    If session_AuditionChannelForPitch(pitch) >= 0 Then
        Exit Sub
    End If

    Dim As Integer auditionChannel = -1
    For channelIndex As Integer = 0 To OSE_SOFTWARE_SYNTH_VOICE_COUNT - 1
        If session_AuditionPitchForChannel(channelIndex) < 0 Then
            auditionChannel = channelIndex
            Exit For
        End If
    Next
    If auditionChannel < 0 Then
        auditionChannel = pitch Mod OSE_SOFTWARE_SYNTH_VOICE_COUNT
        Dim As Integer displacedPitch = _
            session_AuditionPitchForChannel(auditionChannel)
        If displacedPitch >= 0 Then
            session_StopAuditionPitch displacedPitch
        End If
    End If

    session_AuditionChannelForPitch(pitch) = auditionChannel
    session_AuditionPitchForChannel(auditionChannel) = pitch
    Dim As OsePlaybackMixValues auditionMix
    playbackMix_Calculate auditionMix, 127, 127, 64, 85, _
        session_MasterVolume, -1
    Dim As OseSoftwareSynthPlayOptions auditionOptions
    auditionOptions.bankNumber = 0
    auditionOptions.fallbackVoiceChannel = auditionChannel
    softwareSynth_PlayMidiNote auditionChannel, pitch, _
        session_Summary.channelProgram(auditionChannel), _
        session_Summary.channelPitchBend(auditionChannel), _
        CSng(SESSION_MIC_MAX_SECONDS), auditionMix, auditionOptions
    mixerMeter_Trigger session_MixerMeter, auditionChannel, 0.67, _
        SESSION_MIC_MAX_SECONDS
End Sub


Private Function session_CloseLiveKeyboardNote( _
    ByVal pitch As Integer, _
    ByVal currentTick As ULongInt _
) As Integer
    If pitch < 0 OrElse pitch > 127 Then
        Return 0
    End If
    Dim As Integer noteIndex = session_LiveNoteIndex(pitch)
    If noteIndex < 0 Then
        Return 0
    End If

    Dim As Integer changedNote
    Dim As MidiEditableNote editableNote
    If midi_GetEditableNote(noteIndex, editableNote) <> 0 Then
        Dim As ULongInt durationTicks = 1
        If currentTick > session_LiveNoteStartTick(pitch) Then _
            durationTicks = currentTick - session_LiveNoteStartTick(pitch)
        Dim As ULongInt maximumDuration = OSE_MAX_MIDI_TICK - _
            editableNote.startTick
        If durationTicks > maximumDuration Then
            durationTicks = maximumDuration
        End If
        If durationTicks > 0 Then
            editableNote.durationTicks = durationTicks
            If midi_SetEditableNote(session_Summary, noteIndex, _
                editableNote) <> 0 Then changedNote = -1
        End If
    End If
    session_LiveNoteIndex(pitch) = -1
    Return changedNote
End Function


Private Function session_StartLiveKeyboardNote( _
    ByVal pitch As Integer, _
    ByVal currentTick As ULongInt _
) As Integer
    If session_LiveRecording = 0 OrElse pitch < 0 OrElse pitch > 127 OrElse _
        session_LiveNoteIndex(pitch) >= 0 OrElse _
        currentTick >= OSE_MAX_MIDI_TICK Then Return 0
    If session_SelectedTrack < 0 OrElse _
        session_SelectedTrack >= session_Summary.trackCount Then Return 0
    If session_BeginMidiEdit() = 0 Then
        Return 0
    End If

    Dim As Integer recordChannel = _
        session_SelectedTrack Mod SESSION_CHANNEL_COUNT
    Dim As Integer addedNote = midi_AddEditableNote( _
        session_Summary, session_SelectedTrack, currentTick, 1, pitch, _
        recordChannel, 100)
    If addedNote < 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Live recording stopped: note limit reached."
        session_EndLiveRecording()
        Return 0
    End If
    If session_CommitMidiEdit() = 0 Then
        Return 0
    End If
    session_LiveNoteIndex(pitch) = addedNote
    session_LiveNoteStartTick(pitch) = currentTick
    session_SelectOnlyNote addedNote
    session_Dirty = -1
    Return -1
End Function


Private Sub session_ProcessPcPerformanceKeys(ByVal recordNotes As Integer)
    Dim As Integer scanCodes(0 To SESSION_KEYBOARD_NOTE_COUNT - 1) = _
        {FB.SC_Z, FB.SC_S, FB.SC_X, FB.SC_D, FB.SC_C, FB.SC_V, _
         FB.SC_G, FB.SC_B, FB.SC_H, FB.SC_N, FB.SC_J, FB.SC_M, _
         FB.SC_Q, FB.SC_2, FB.SC_W, FB.SC_3, FB.SC_E, FB.SC_R, _
         FB.SC_5, FB.SC_T, FB.SC_6, FB.SC_Y, FB.SC_7, FB.SC_U}
    Dim As ULongInt currentTick
    If recordNotes <> 0 Then
        currentTick = session_LiveRecordingTick()
    End If

    For keyIndex As Integer = 0 To SESSION_KEYBOARD_NOTE_COUNT - 1
        Dim As Integer scanCode = scanCodes(keyIndex)
        Dim As Integer currentState = input_KeyPressed(scanCode)
        Dim As Integer previousState = session_StepEntryLastState(scanCode)
        Dim As Integer pitch = session_StepEntryPitch(scanCode)
        If currentState <> 0 AndAlso previousState = 0 Then
            session_StartAuditionPitch pitch
            If recordNotes <> 0 Then _
                session_StartLiveKeyboardNote pitch, currentTick
        ElseIf currentState = 0 AndAlso previousState <> 0 Then
            ' A physical key and an on-screen key may refer to the same pitch.
            ' Releasing either source must not end the note while the other is
            ' still held.
            If session_KeyboardMousePitch <> pitch Then
                If recordNotes <> 0 Then
                    If session_CloseLiveKeyboardNote(pitch, currentTick) <> 0 Then _
                        session_Dirty = -1
                End If
                session_StopAuditionPitch pitch
            End If
        End If
        session_StepEntryLastState(scanCode) = currentState
    Next
End Sub


Private Sub session_ResetLiveKeyboardState()
    For keyIndex As Integer = 0 To 127
        session_StepEntryLastState(keyIndex) = 0
        session_LiveNoteIndex(keyIndex) = -1
        session_LiveNoteStartTick(keyIndex) = 0
    Next
End Sub


Private Sub session_ResetLiveMidiState()
    For channelIndex As Integer = 0 To SESSION_CHANNEL_COUNT - 1
        session_LiveMidiSustain(channelIndex) = 0
        For keyNumber As Integer = 0 To 127
            Dim As Integer slotIndex = channelIndex * 128 + keyNumber
            session_LiveMidiNoteIndex(slotIndex) = -1
            session_LiveMidiNoteStartTick(slotIndex) = 0
            session_LiveMidiNoteReleased(slotIndex) = 0
        Next
    Next
End Sub


Private Function session_LiveRecordingTick() As ULongInt
    Dim As Double currentClock = Timer
    Dim As Double elapsedSeconds = currentClock - _
        session_LiveRecordingStartClock
    If elapsedSeconds < 0.0 Then
        elapsedSeconds += 86400.0
    End If
    If elapsedSeconds > SESSION_LIVE_RECORD_MAX_SECONDS Then _
        elapsedSeconds = SESSION_LIVE_RECORD_MAX_SECONDS

    Dim As Double startSeconds = midi_TicksToSeconds( _
        session_Summary, session_LiveRecordingStartTick)
    Dim As ULongInt currentTick = midi_SecondsToTicks( _
        session_Summary, startSeconds + elapsedSeconds)
    If currentTick < session_LiveRecordingStartTick Then _
        currentTick = session_LiveRecordingStartTick
    If currentTick > OSE_MAX_MIDI_TICK Then
        currentTick = OSE_MAX_MIDI_TICK
    End If
    Return currentTick
End Function


Private Function session_LiveRecordingTickForMidiTimestamp( _
    ByVal timestampMilliseconds As ULong, _
    ByRef currentTick As ULongInt _
) As Integer
    currentTick = session_LiveRecordingStartTick
    If session_LiveRecordingHasMidiTimestamp = 0 Then
        Return 0
    End If

    ' Record captures the origin before any event arrives. Preserve its initial
    ' silence, accept an ordinary DWORD wrap, and reject callbacks which began
    ' before this take instead of interpreting them as a 49-day interval.
    Dim As ULongInt elapsedMilliseconds
    If midiInputProtocol_ElapsedMilliseconds( _
        session_LiveRecordingStartMidiTimestamp, timestampMilliseconds, _
        elapsedMilliseconds) = 0 Then Return 0
    Dim As ULongInt maximumMilliseconds = _
        CULngInt(SESSION_LIVE_RECORD_MAX_SECONDS * 1000.0)
    If elapsedMilliseconds > maximumMilliseconds Then _
        elapsedMilliseconds = maximumMilliseconds

    Dim As Double startSeconds = midi_TicksToSeconds( _
        session_Summary, session_LiveRecordingStartTick)
    currentTick = midi_SecondsToTicks( _
        session_Summary, startSeconds + CDbl(elapsedMilliseconds) / 1000.0)
    If currentTick < session_LiveRecordingStartTick Then _
        currentTick = session_LiveRecordingStartTick
    If currentTick > OSE_MAX_MIDI_TICK Then
        currentTick = OSE_MAX_MIDI_TICK
    End If
    Return -1
End Function


Private Function session_CloseLiveMidiNote( _
    ByVal channelIndex As Integer, _
    ByVal keyNumber As Integer, _
    ByVal currentTick As ULongInt _
) As Integer
    If channelIndex < 0 OrElse channelIndex >= SESSION_CHANNEL_COUNT Then _
        Return 0
    If keyNumber < 0 OrElse keyNumber > 127 Then
        Return 0
    End If

    Dim As Integer slotIndex = channelIndex * 128 + keyNumber
    Dim As Integer noteIndex = session_LiveMidiNoteIndex(slotIndex)
    If noteIndex < 0 Then
        Return 0
    End If

    Dim As Integer changedNote = 0
    Dim As MidiEditableNote editableNote
    If midi_GetEditableNote(noteIndex, editableNote) <> 0 Then
        Dim As ULongInt durationTicks = 1
        If currentTick > session_LiveMidiNoteStartTick(slotIndex) Then _
            durationTicks = currentTick - session_LiveMidiNoteStartTick(slotIndex)
        Dim As ULongInt maximumDuration = OSE_MAX_MIDI_TICK - _
            editableNote.startTick
        If durationTicks > maximumDuration Then
            durationTicks = maximumDuration
        End If
        If durationTicks > 0 Then
            editableNote.durationTicks = durationTicks
            If midi_SetEditableNote(session_Summary, noteIndex, _
                editableNote) <> 0 Then changedNote = -1
        End If
    End If

    session_LiveMidiNoteIndex(slotIndex) = -1
    session_LiveMidiNoteReleased(slotIndex) = 0
    Return changedNote
End Function


Private Function session_CloseReleasedMidiNotes( _
    ByVal channelIndex As Integer, _
    ByVal currentTick As ULongInt _
) As Integer
    If channelIndex < 0 OrElse channelIndex >= SESSION_CHANNEL_COUNT Then _
        Return 0

    Dim As Integer changedNotes = 0
    For keyNumber As Integer = 0 To 127
        Dim As Integer slotIndex = channelIndex * 128 + keyNumber
        If session_LiveMidiNoteReleased(slotIndex) <> 0 Then
            If session_CloseLiveMidiNote( _
                channelIndex, keyNumber, currentTick) <> 0 Then changedNotes += 1
        End If
    Next
    Return changedNotes
End Function


Public Sub session_EndLiveRecording()
    If session_LiveRecording = 0 Then
        Exit Sub
    End If
    If session_LiveRecordingKeyboardOnly = 0 Then
        session_ProcessMidiInput()
    End If
    Dim As ULongInt currentTick = session_LiveRecordingTick()
    Dim As ULongInt midiCurrentTick = currentTick
    Dim As ULong midiStopTimestamp
    If session_LiveRecordingHasMidiTimestamp <> 0 AndAlso _
        midiInput_GetClockMilliseconds(midiStopTimestamp) <> 0 Then
        If session_LiveRecordingTickForMidiTimestamp( _
            midiStopTimestamp, midiCurrentTick) = 0 Then midiCurrentTick = currentTick
    End If
    Dim As Integer changedNotes = 0
    For keyNumber As Integer = 0 To 127
        If session_CloseLiveKeyboardNote(keyNumber, currentTick) <> 0 Then _
            changedNotes += 1
    Next

    For channelIndex As Integer = 0 To SESSION_CHANNEL_COUNT - 1
        For keyNumber As Integer = 0 To 127
            If session_CloseLiveMidiNote( _
                channelIndex, keyNumber, midiCurrentTick) <> 0 Then changedNotes += 1
        Next
    Next

    session_ResetLiveKeyboardState()
    session_ResetLiveMidiState()
    session_StopAllAuditionNotes()
    session_KeyboardMousePitch = -1
    If midiInput_IsOpen() <> 0 Then
        midiInput_ClearPending()
    End If
    If session_MidiInputAutoOpened <> 0 Then
        midiInput_Close()
    End If
    session_MidiInputAutoOpened = 0
    session_LiveRecordingKeyboardOnly = 0
    session_LiveRecording = 0
    session_LiveRecordingHasMidiTimestamp = 0
    If changedNotes > 0 Then
        session_Dirty = -1
    End If
End Sub


Private Function session_RecordIncomingSystemExclusive( _
    ByRef message As OseMidiInputMessage, _
    ByVal currentTick As ULongInt _
) As Integer
    If message.payloadLength <= 0 OrElse _
        message.payloadLength > OSE_MIDI_INPUT_MAX_LONG_BYTES OrElse _
        currentTick >= OSE_MAX_MIDI_TICK Then Return 0

    Dim As Integer sysexStatus = message.payload(0)
    If sysexStatus <> &HF0 AndAlso sysexStatus <> &HF7 Then
        Return 0
    End If
    Dim As Integer sysexLength = message.payloadLength - 1
    Dim As String sysexPayload = Space(sysexLength)
    For payloadIndex As Integer = 0 To sysexLength - 1
        ' The destination was allocated to exactly this size. FB-LINTER: DISABLE-NEXT-LINE FBL514 REASON: The destination was allocated to exactly this size.
        Mid(sysexPayload, payloadIndex + 1, 1) = _
            Chr(message.payload(payloadIndex + 1))
    Next

    If session_BeginMidiEdit() = 0 Then
        Return 0
    End If
    If midi_AddSystemExclusiveEvent(session_Summary, session_SelectedTrack, _
        currentTick, sysexStatus, sysexPayload) < 0 Then
        session_CancelMidiEdit()
        Return 0
    End If
    Return session_CommitMidiEdit()
End Function


Private Function session_RecordIncomingSystemCommon( _
    ByRef message As OseMidiInputMessage, _
    ByVal currentTick As ULongInt _
) As Integer
    If currentTick >= OSE_MAX_MIDI_TICK Then
        Return 0
    End If
    If session_BeginMidiEdit() = 0 Then
        Return 0
    End If
    If midi_AddSystemEvent(session_Summary, session_SelectedTrack, currentTick, _
        message.status, message.data1, message.data2) < 0 Then
        session_CancelMidiEdit()
        Return 0
    End If
    Return session_CommitMidiEdit()
End Function


Private Function session_ProcessRecordedMidiMessage( _
    ByRef message As OseMidiInputMessage, _
    ByVal monitorInput As Integer _
) As Integer
    Dim As ULongInt currentTick
    If session_LiveRecordingTickForMidiTimestamp( _
        message.timestampMilliseconds, currentTick) = 0 Then Return 0
    If message.messageKind = OSE_MIDI_INPUT_SYSEX_MESSAGE Then _
        Return session_RecordIncomingSystemExclusive(message, currentTick)

    If message.status = &HF1 OrElse message.status = &HF2 OrElse _
        message.status = &HF3 OrElse message.status = &HF6 Then _
        Return session_RecordIncomingSystemCommon(message, currentTick)

    Dim As Integer messageType = message.status And &HF0
    Dim As Integer channelIndex = message.status And &H0F
    Dim As Integer keyNumber = message.data1
    Dim As Integer velocity = message.data2

    ' Monitoring is separate from recording. The audit feeds complete messages
    ' through this dispatcher with monitoring disabled, without native devices.
    If monitorInput <> 0 AndAlso message.status >= &H80 AndAlso _
        message.status <= &HEF AndAlso midiOutput_IsOpen() <> 0 Then
        Dim As Integer thruData2 = velocity
        If messageType = &HC0 OrElse messageType = &HD0 Then
            thruData2 = 0
        End If
        midiOutput_Send message.status, keyNumber, thruData2
    End If

    If messageType = &H90 AndAlso velocity > 0 Then
        If currentTick >= OSE_MAX_MIDI_TICK Then
            Return 0
        End If
        Dim As Integer slotIndex = channelIndex * 128 + keyNumber
        If session_BeginMidiEdit() = 0 Then
            Return 0
        End If
        Dim As Integer previousNoteIndex = session_LiveMidiNoteIndex(slotIndex)
        Dim As ULongInt previousNoteStart = session_LiveMidiNoteStartTick(slotIndex)
        Dim As Integer previousNoteReleased = session_LiveMidiNoteReleased(slotIndex)
        ' Keep both strikes when a key is retriggered under the sustain pedal.
        ' This recorder has one active note per channel/key: the prior note
        ' ends at the retrigger, and the new note owns subsequent release events.
        If previousNoteIndex >= 0 Then _
            session_CloseLiveMidiNote channelIndex, keyNumber, currentTick
        Dim As Integer addedNote = midi_AddEditableNote( _
            session_Summary, session_SelectedTrack, currentTick, 1, _
            keyNumber, channelIndex, velocity)
        Dim As Integer committed = 0
        If addedNote >= 0 Then
            committed = session_CommitMidiEdit()
        Else
            session_CancelMidiEdit()
        End If
        If committed = 0 Then
            session_LiveMidiNoteIndex(slotIndex) = previousNoteIndex
            session_LiveMidiNoteStartTick(slotIndex) = previousNoteStart
            session_LiveMidiNoteReleased(slotIndex) = previousNoteReleased
            Return 0
        End If
        session_LiveMidiNoteIndex(slotIndex) = addedNote
        session_LiveMidiNoteStartTick(slotIndex) = currentTick
        session_LiveMidiNoteReleased(slotIndex) = 0
        If monitorInput <> 0 Then
            Dim As OsePlaybackMixValues liveInputMix
            playbackMix_Calculate liveInputMix, _
                session_Summary.channelVolume(channelIndex), _
                session_Summary.channelExpression(channelIndex), _
                session_Summary.channelPan(channelIndex), velocity, _
                session_MasterVolume, session_ChannelIsAudible(channelIndex)
            Dim As OseSoftwareSynthPlayOptions liveInputOptions
            liveInputOptions.bankNumber = IIf(channelIndex = 9, 128, 0)
            liveInputOptions.fallbackVoiceChannel = -1
            softwareSynth_PlayMidiNote channelIndex, keyNumber, _
                session_Summary.channelProgram(channelIndex), _
                session_Summary.channelPitchBend(channelIndex), _
                0.18, liveInputMix, liveInputOptions
            mixerMeter_Trigger session_MixerMeter, channelIndex, _
                CSng(velocity) / 127.0, 0.18
        End If
        Return -1
    ElseIf messageType = &H80 OrElse _
        (messageType = &H90 AndAlso velocity = 0) Then
        Dim As Integer slotIndex = channelIndex * 128 + keyNumber
        If session_LiveMidiSustain(channelIndex) <> 0 Then
            If session_LiveMidiNoteIndex(slotIndex) >= 0 Then _
                session_LiveMidiNoteReleased(slotIndex) = -1
        Else
            Return session_CloseLiveMidiNote(channelIndex, keyNumber, currentTick)
        End If
    ElseIf messageType = &HA0 OrElse messageType = &HB0 OrElse _
        messageType = &HC0 OrElse messageType = &HD0 OrElse _
        messageType = &HE0 Then
        Dim As Integer historyPrepared = 0
        Dim As Integer messageChanged = 0
        If messageType = &HB0 AndAlso keyNumber = 64 Then
            Dim As Integer sustainWasDown = session_LiveMidiSustain(channelIndex)
            Dim As Integer sustainIsDown = 0
            If velocity >= 64 Then
                sustainIsDown = -1
            End If
            session_LiveMidiSustain(channelIndex) = sustainIsDown
            If sustainWasDown <> 0 AndAlso sustainIsDown = 0 Then
                If session_BeginMidiEdit() <> 0 Then
                    historyPrepared = -1
                    If session_CloseReleasedMidiNotes( _
                        channelIndex, currentTick) > 0 Then messageChanged = -1
                End If
            End If
        End If

        If currentTick < OSE_MAX_MIDI_TICK Then
            If historyPrepared = 0 AndAlso session_BeginMidiEdit() <> 0 Then _
                historyPrepared = -1
            If historyPrepared <> 0 Then
                Dim As Integer addedEvent = midi_AddChannelEvent( _
                    session_Summary, session_SelectedTrack, currentTick, _
                    channelIndex, messageType, keyNumber, velocity)
                If addedEvent >= 0 Then
                    messageChanged = -1
                End If
            End If
        End If
        If historyPrepared <> 0 Then
            If messageChanged <> 0 Then
                Return session_CommitMidiEdit()
            End If
            session_CancelMidiEdit()
        End If
    End If
    Return 0
End Function


Public Sub session_ProcessMidiInput()
    If midiInput_IsOpen() = 0 Then
        Exit Sub
    End If

    Dim As OseMidiInputMessage message
    Dim As Integer changedModel = 0
    While midiInput_Poll(message) <> 0
        If session_ProcessRecordedMidiMessage(message, -1) <> 0 Then _
            changedModel = -1
    Wend

    Dim As ULongInt droppedCount = midiInput_GetDroppedCount()
    If droppedCount <> session_LastMidiInputDroppedCount Then
        session_LastMidiInputDroppedCount = droppedCount
        session_SetStatus "MIDI input queue dropped " + Str(droppedCount) + _
            " message(s)."
    End If
    If changedModel <> 0 Then
        session_Dirty = -1
    End If
End Sub


Private Sub session_ProcessLiveRecording()
    If session_LiveRecording = 0 Then
        Exit Sub
    End If
    Dim As Integer modalConflict = session_IsModalOpen()
    If (session_KeyboardWindow <> 0 OrElse session_DrumWindow <> 0) AndAlso _
        session_ConfirmDialog = 0 AndAlso session_FileDialog = 0 AndAlso _
        session_TempoMapWindow = 0 AndAlso session_TrackWindow = 0 AndAlso _
        session_AutomationWindow = 0 AndAlso session_NoteWindow = 0 AndAlso _
        session_AudioWindow = 0 AndAlso session_MidiInputWindow = 0 AndAlso _
        session_MidiOutputWindow = 0 AndAlso session_MicWindow = 0 AndAlso _
        session_AboutWindow = 0 Then _
        modalConflict = 0
    If session_Summary.trackCount <= 0 OrElse modalConflict <> 0 OrElse _
        input_KeyPressed(FB.SC_CONTROL) <> 0 Then
        session_EndLiveRecording()
        Exit Sub
    End If

    If session_LiveRecordingKeyboardOnly = 0 Then
        session_ProcessMidiInput()
    End If
    If session_KeyboardWindow <> 0 Then
        session_ProcessPcPerformanceKeys -1
    End If
End Sub


Private Sub session_ProcessStepRecording()
    If session_LiveRecording <> 0 Then
        session_ProcessLiveRecording()
        Exit Sub
    End If
    ' The Keys window already consumed this frame's physical-key transitions.
    ' Keep its previous-key state until the next frame so releases can stop
    ' auditions, and do not also interpret those keys as step entry.
    If session_KeyboardWindow <> 0 Then
        Exit Sub
    End If
    Dim As Integer recordChannel = session_RecordChannel()
    If recordChannel < 0 OrElse session_Summary.trackCount <= 0 Then
        For keyIndex As Integer = 0 To 127
            session_StepEntryLastState(keyIndex) = 0
        Next
        Exit Sub
    End If

    If input_KeyPressed(FB.SC_CONTROL) <> 0 Then
        For keyIndex As Integer = 0 To 127
            session_StepEntryLastState(keyIndex) = 0
        Next
        Exit Sub
    End If

    If session_FileDialog <> 0 OrElse session_TempoMapWindow <> 0 OrElse _
        session_TrackWindow <> 0 OrElse session_AutomationWindow <> 0 OrElse _
        session_NoteWindow <> 0 OrElse session_AudioWindow <> 0 OrElse _
        session_AboutWindow <> 0 Then
        For keyIndex As Integer = 0 To 127
            session_StepEntryLastState(keyIndex) = 0
        Next
        Exit Sub
    End If

    Dim As Integer scanCodes(0 To 23) = _
        {FB.SC_Z, FB.SC_S, FB.SC_X, FB.SC_D, FB.SC_C, FB.SC_V, _
         FB.SC_G, FB.SC_B, FB.SC_H, FB.SC_N, FB.SC_J, FB.SC_M, _
         FB.SC_Q, FB.SC_2, FB.SC_W, FB.SC_3, FB.SC_E, FB.SC_R, _
         FB.SC_5, FB.SC_T, FB.SC_6, FB.SC_Y, FB.SC_7, FB.SC_U}
    Dim As Integer noteWasAdded = 0
    For keyIndex As Integer = 0 To 23
        Dim As Integer scanCode = scanCodes(keyIndex)
        Dim As Integer currentState = input_KeyPressed(scanCode)
        Dim As Integer previousState = session_StepEntryLastState(scanCode)
        If currentState <> 0 AndAlso previousState = 0 Then
            Dim As Integer pitch = session_StepEntryPitch(scanCode)
            If pitch >= 0 Then
                Dim As ULongInt stepTicks = CULngInt(session_Summary.division) \ 2
                If stepTicks = 0 Then
                    stepTicks = 1
                End If
                If session_BeginMidiEdit() = 0 Then
                    Continue For
                End If
                Dim As Integer addedNote = midi_AddEditableNote( _
                    session_Summary, session_SelectedTrack, _
                    session_StepEntryTick, stepTicks, pitch, _
                    recordChannel, 100)
                If addedNote >= 0 Then
                    If session_CommitMidiEdit() = 0 Then
                        Continue For
                    End If
                    session_SelectedNote = addedNote
                    noteWasAdded = -1
                Else
                    session_CancelMidiEdit()
                    session_SetStatus "Step recording stopped: note limit reached."
                    session_MixerChannels.record(recordChannel) = 0
                End If
            End If
        End If
        session_StepEntryLastState(scanCode) = currentState
    Next

    If noteWasAdded <> 0 Then
        Dim As ULongInt advanceTicks = CULngInt(session_Summary.division) \ 2
        If advanceTicks = 0 Then
            advanceTicks = 1
        End If
        If session_StepEntryTick > SESSION_AUTOMATION_MAX_TICK - advanceTicks Then
            session_StepEntryTick = SESSION_AUTOMATION_MAX_TICK
        Else
            session_StepEntryTick += advanceTicks
        End If
        session_Dirty = -1
        session_SetStatus "Step-recorded note at tick " + _
            Str(session_StepEntryTick - advanceTicks) + "."
    End If
End Sub


Private Function session_IsModalOpen() As Integer
    If session_WavExport.active <> 0 OrElse _
        session_ConfirmDialog <> 0 OrElse session_FileDialog <> 0 OrElse _
        session_TempoMapWindow <> 0 OrElse _
        session_TrackWindow <> 0 OrElse session_AutomationWindow <> 0 OrElse _
        session_NoteWindow <> 0 OrElse session_AudioWindow <> 0 OrElse _
        session_MidiInputWindow <> 0 OrElse session_MidiOutputWindow <> 0 OrElse _
        session_KeyboardWindow <> 0 OrElse session_DrumWindow <> 0 OrElse _
        session_PhraseWindow <> 0 OrElse session_SongMeterWindow <> 0 OrElse _
        session_NoteToolsWindow <> 0 OrElse _
        session_MicWindow <> 0 OrElse _
        session_AboutWindow <> 0 Then
        Return -1
    End If
    Return 0
End Function


Private Sub session_RefreshAfterMidiHistory()
    session_PlaybackChannelOrderDirty = -1
    session_SelectedNote = -1
    session_ScoreDragNote = -1
    scoreLayout_SynchronizeTrackCount session_ScoreLayout, _
        session_Summary.trackCount
    session_RefreshTrackList()
    If session_Summary.trackCount > 0 Then
        If session_SelectedTrack >= session_Summary.trackCount Then
            session_SelectedTrack = session_Summary.trackCount - 1
        End If
        If session_SelectedTrack < 0 Then
            session_SelectedTrack = 0
        End If
        session_SelectTrack session_SelectedTrack
    End If
    session_RefreshMixerFromSummary()
    session_RefreshTempoBox()
    session_StepEntryTick = session_Summary.durationTicks
End Sub


Private Sub session_ApplyUndoEdit()
    session_StopPlayback()
    Dim As Integer appliedDomain = documentHistory_Undo( _
        session_DocumentHistory, session_Summary)
    If appliedDomain <> OSE_HISTORY_DOMAIN_NONE Then
        If appliedDomain = OSE_HISTORY_DOMAIN_AUDIO Then
            session_LoadAudioSamples()
            session_RefreshAudioList()
        Else
            session_RefreshAfterMidiHistory()
        End If
        session_Dirty = -1
        session_SetStatus "Undo applied." + session_AudioAvailabilitySuffix()
    Else
        session_SetStatus "Nothing to undo."
    End If
End Sub


Private Sub session_ApplyRedoEdit()
    session_StopPlayback()
    Dim As Integer appliedDomain = documentHistory_Redo( _
        session_DocumentHistory, session_Summary)
    If appliedDomain <> OSE_HISTORY_DOMAIN_NONE Then
        If appliedDomain = OSE_HISTORY_DOMAIN_AUDIO Then
            session_LoadAudioSamples()
            session_RefreshAudioList()
        Else
            session_RefreshAfterMidiHistory()
        End If
        session_Dirty = -1
        session_SetStatus "Redo applied." + session_AudioAvailabilitySuffix()
    Else
        session_SetStatus "Nothing to redo."
    End If
End Sub


Public Sub session_ProcessEditShortcuts()
    Dim As Integer undoState = 0
    Dim As Integer redoState = 0
    Dim As Integer copyState = 0
    Dim As Integer cutState = 0
    Dim As Integer pasteState = 0
    Dim As Integer selectAllState = 0
    Dim As Integer controlState = input_KeyPressed(FB.SC_CONTROL)
    Dim As Integer shiftState = _
        input_KeyPressed(FB.SC_LSHIFT) OrElse input_KeyPressed(FB.SC_RSHIFT)
    Dim As Integer quickEditMask = 0
    If controlState <> 0 Then
        If input_KeyPressed(FB.SC_D) <> 0 Then
            quickEditMask Or= 1
        End If
        If input_KeyPressed(FB.SC_Q) <> 0 Then
            quickEditMask Or= 2
        End If
    End If
    If controlState <> 0 Then
        undoState = input_KeyPressed(FB.SC_Z)
        redoState = input_KeyPressed(FB.SC_Y)
        If shiftState <> 0 AndAlso undoState <> 0 Then
            redoState = -1
            undoState = 0
        End If
        copyState = input_KeyPressed(FB.SC_C)
        cutState = input_KeyPressed(FB.SC_X)
        pasteState = input_KeyPressed(FB.SC_V)
        selectAllState = input_KeyPressed(FB.SC_A)
        If input_KeyPressed(FB.SC_INSERT) <> 0 Then
            copyState = -1
        End If
    End If
    If shiftState <> 0 AndAlso input_KeyPressed(FB.SC_DELETE) <> 0 Then _
        cutState = -1
    If shiftState <> 0 AndAlso input_KeyPressed(FB.SC_INSERT) <> 0 Then _
        pasteState = -1

    If session_LiveRecording <> 0 AndAlso _
        (undoState <> 0 OrElse redoState <> 0 OrElse _
        copyState <> 0 OrElse cutState <> 0 OrElse pasteState <> 0 OrElse _
        selectAllState <> 0) Then
        session_EndLiveRecording()
    End If

    If session_IsModalOpen() <> 0 Then
        session_LastQuickEditMask = quickEditMask
        session_LastUndoState = undoState
        session_LastRedoState = redoState
        session_LastCopyState = copyState
        session_LastCutState = cutState
        session_LastPasteState = pasteState
        session_LastSelectAllState = selectAllState
        Exit Sub
    End If

    Dim As Integer undoPressed = undoState <> 0 AndAlso _
        session_LastUndoState = 0
    Dim As Integer redoPressed = redoState <> 0 AndAlso _
        session_LastRedoState = 0
    Dim As Integer copyPressed = copyState <> 0 AndAlso _
        session_LastCopyState = 0
    Dim As Integer cutPressed = cutState <> 0 AndAlso _
        session_LastCutState = 0
    Dim As Integer pastePressed = pasteState <> 0 AndAlso _
        session_LastPasteState = 0
    Dim As Integer selectAllPressed = selectAllState <> 0 AndAlso _
        session_LastSelectAllState = 0
    If undoPressed <> 0 Then
        session_ApplyUndoEdit()
    ElseIf redoPressed <> 0 Then
        session_ApplyRedoEdit()
    ElseIf selectAllPressed <> 0 Then
        session_SelectAllNotes()
    ElseIf copyPressed <> 0 Then
        session_CopySelectedNotes()
    ElseIf cutPressed <> 0 Then
        session_CutSelectedNotes()
    ElseIf pastePressed <> 0 Then
        session_PasteCopiedNotes()
    ElseIf (quickEditMask And &H1) <> 0 AndAlso (session_LastQuickEditMask And &H1) = 0 Then
        session_ApplySelectionTool OSE_NOTE_EDIT_DUPLICATE
    ElseIf (quickEditMask And &H2) <> 0 AndAlso (session_LastQuickEditMask And &H2) = 0 Then
        session_ApplySelectionTool OSE_NOTE_EDIT_QUANTIZE
    End If

    session_LastQuickEditMask = quickEditMask
    session_LastUndoState = undoState
    session_LastRedoState = redoState
    session_LastCopyState = copyState
    session_LastCutState = cutState
    session_LastPasteState = pasteState
    session_LastSelectAllState = selectAllState
End Sub


Private Sub session_ProcessTransportShortcuts()
    Dim As Integer controlState = input_KeyPressed(FB.SC_CONTROL)
    Dim As Integer saveState = 0
    Dim As Integer selectedPlaybackState = 0
    If controlState <> 0 Then
        saveState = input_KeyPressed(FB.SC_S)
        selectedPlaybackState = input_KeyPressed(FB.SC_SPACE)
    End If
    Dim As Integer transportState = 0
    If controlState = 0 Then
        transportState = input_KeyPressed(FB.SC_SPACE)
    End If
    Dim As Integer transportMouseButtons = input_MouseButtons()
    Dim As Integer functionMask
    If input_KeyPressed(FB.SC_F2) <> 0 Then
        functionMask Or= 1
    End If
    If input_KeyPressed(FB.SC_F3) <> 0 Then
        functionMask Or= 2
    End If
    If input_KeyPressed(FB.SC_F4) <> 0 Then
        functionMask Or= 4
    End If
    If input_KeyPressed(FB.SC_F5) <> 0 Then
        functionMask Or= 8
    End If
    If input_KeyPressed(FB.SC_F6) <> 0 Then
        functionMask Or= 16
    End If
    If input_KeyPressed(FB.SC_F7) <> 0 Then
        functionMask Or= 32
    End If
    If input_KeyPressed(FB.SC_F8) <> 0 Then
        functionMask Or= 64
    End If
    If input_KeyPressed(FB.SC_F9) <> 0 Then
        functionMask Or= 128
    End If

    ' A WAV render locks score and mixer editing, but F2 must remain a reliable
    ' keyboard cancel path while that logical modal operation is active.
    If session_WavExport.active <> 0 Then
        Dim As Integer newExportFunctionMask = functionMask And _
            (Not session_LastFunctionShortcutMask)
        If (newExportFunctionMask And &H1) <> 0 Then
            session_OnStop 0
        End If
        session_LastSaveShortcutState = saveState
        session_LastTransportShortcutState = transportState
        session_LastSelectedPlaybackShortcutState = selectedPlaybackState
        session_LastFunctionShortcutMask = functionMask
        session_LastTransportMouseButtons = transportMouseButtons
        Exit Sub
    End If

    If session_IsModalOpen() <> 0 Then
        session_LastSaveShortcutState = saveState
        session_LastTransportShortcutState = transportState
        session_LastSelectedPlaybackShortcutState = selectedPlaybackState
        session_LastFunctionShortcutMask = functionMask
        session_LastTransportMouseButtons = transportMouseButtons
        Exit Sub
    End If

    Dim As Integer savePressed = saveState <> 0 AndAlso _
        session_LastSaveShortcutState = 0
    Dim As Integer transportPressed = transportState <> 0 AndAlso _
        session_LastTransportShortcutState = 0
    Dim As Integer selectedPlaybackPressed = selectedPlaybackState <> 0 AndAlso _
        session_LastSelectedPlaybackShortcutState = 0
    Dim As Integer newFunctionMask = functionMask And _
        (Not session_LastFunctionShortcutMask)
    Dim As Integer rightPressed = _
        (transportMouseButtons And 2) <> 0 AndAlso _
        (session_LastTransportMouseButtons And &H2) = 0

    If rightPressed <> 0 AndAlso _
        input_MouseX() >= SESSION_TRANSPORT_REWIND_LEFT AndAlso _
        input_MouseX() < SESSION_TRANSPORT_REWIND_LEFT + _
            SESSION_TRANSPORT_REWIND_WIDTH AndAlso _
        input_MouseY() >= SESSION_TOOLBAR_TOP + _
            SESSION_TOOLBAR_BUTTON_TOP_INSET AndAlso _
        input_MouseY() < SESSION_TOOLBAR_TOP + _
            SESSION_TOOLBAR_BUTTON_TOP_INSET + SESSION_TOOLBAR_BUTTON_HEIGHT Then
        session_OnRewind 0
    End If

    If savePressed <> 0 Then
        session_OnSave(0)
    End If
    If selectedPlaybackPressed <> 0 Then
        session_OnPlaySelectedNotes 0
    ElseIf transportPressed <> 0 Then
        If session_Playing = 0 Then
            session_OnPlay(0)
        Else
            session_OnPause(0)
        End If
    End If

    If (newFunctionMask And &H1) <> 0 Then
        session_OnStop 0
    ElseIf (newFunctionMask And &H2) <> 0 Then
        session_OnRewind 0
    ElseIf (newFunctionMask And &H4) <> 0 Then
        session_OnFastForward 0
    ElseIf (newFunctionMask And &H8) <> 0 Then
        session_OnPlay 0
    ElseIf (newFunctionMask And &H10) <> 0 Then
        session_OnLiveRecord 0
    ElseIf (newFunctionMask And &H20) <> 0 Then
        session_OnPause 0
    ElseIf (newFunctionMask And &H40) <> 0 Then
        session_OnStepRecord 0
    ElseIf (newFunctionMask And &H80) <> 0 Then
        session_OnPlay 0
        session_SetStatus "Step Play started."
    End If

    session_LastSaveShortcutState = saveState
    session_LastTransportShortcutState = transportState
    session_LastSelectedPlaybackShortcutState = selectedPlaybackState
    session_LastFunctionShortcutMask = functionMask
    session_LastTransportMouseButtons = transportMouseButtons
End Sub


Private Sub session_FinishMixerDrag()
    If session_MixerDragKind >= OSE_MIXER_CONTROL_CHANNEL_FADER AndAlso _
        session_MixerDragKind <= OSE_MIXER_CONTROL_CHANNEL_PAN Then
        If session_MixerDragMidiChanged <> 0 Then
            session_CommitMidiEdit()
        Else
            session_CancelMidiEdit()
            session_RefreshMixerFromSummary()
        End If
    End If
    session_MixerDragKind = OSE_MIXER_CONTROL_NONE
    session_MixerDragChannel = -1
    session_MixerDragMidiChanged = 0
End Sub


Private Function session_ApplyMidiMixerDragValue( _
    ByVal controlValue As Single, _
    ByVal announceChange As Integer _
) As Integer
    Dim As Integer channelIndex = session_MixerDragChannel
    If channelIndex < 0 OrElse channelIndex >= SESSION_CHANNEL_COUNT Then _
        Return -1

    Select Case session_MixerDragKind
        Case OSE_MIXER_CONTROL_CHANNEL_FADER
            Dim As Integer volumeValue = session_RoundNonnegative( _
                controlValue * 127.0)
            If volumeValue = session_Summary.channelVolume(channelIndex) Then _
                Return 0
            session_ChannelVolume(channelIndex) = controlValue
            If session_SyncChannelMix(channelIndex) = 0 Then
                Return -1
            End If
            session_ApplyMixerState()
            If announceChange <> 0 Then session_SetStatus _
                "Volume changed on channel " + Str(channelIndex + 1) + "."

        Case OSE_MIXER_CONTROL_CHANNEL_CHORUS
            Dim As Integer chorusValue = session_RoundNonnegative( _
                controlValue * 127.0)
            If chorusValue = session_Summary.channelChorus(channelIndex) Then _
                Return 0
            session_ChannelChorus(channelIndex) = controlValue
            If session_SyncChannelEffects(channelIndex) = 0 Then
                Return -1
            End If
            If announceChange <> 0 Then session_SetStatus _
                "MIDI chorus send changed on channel " + _
                Str(channelIndex + 1) + "."

        Case OSE_MIXER_CONTROL_CHANNEL_REVERB
            Dim As Integer reverbValue = session_RoundNonnegative( _
                controlValue * 127.0)
            If reverbValue = session_Summary.channelReverb(channelIndex) Then _
                Return 0
            session_ChannelReverb(channelIndex) = controlValue
            If session_SyncChannelEffects(channelIndex) = 0 Then
                Return -1
            End If
            If announceChange <> 0 Then session_SetStatus _
                "MIDI reverb send changed on channel " + _
                Str(channelIndex + 1) + "."

        Case OSE_MIXER_CONTROL_CHANNEL_PAN
            Dim As Integer panValue = session_RoundNonnegative( _
                controlValue * 127.0)
            If panValue = session_Summary.channelPan(channelIndex) Then
                Return 0
            End If
            session_ChannelPan(channelIndex) = controlValue * 2.0 - 1.0
            If session_SyncChannelMix(channelIndex) = 0 Then
                Return -1
            End If
            session_ApplyMixerState()
            If announceChange <> 0 Then session_SetStatus _
                "Pan changed on channel " + Str(channelIndex + 1) + "."

        Case Else
            Return -1
    End Select
    Return 1
End Function


Private Sub session_PageMixerChannels( _
    ByRef mixerLayout As OseMixerControlLayout, _
    ByVal pageDirection As Integer _
)
    If mixerLayout.visibleCount <= 0 OrElse _
        mixerLayout.visibleCount >= SESSION_CHANNEL_COUNT Then Exit Sub

    Dim As Integer maximumFirst = _
        SESSION_CHANNEL_COUNT - mixerLayout.visibleCount
    Dim As Integer targetFirst = mixerLayout.firstChannel + _
        IIf(pageDirection < 0, -1, 1) * mixerLayout.visibleCount
    If targetFirst < 0 Then
        targetFirst = 0
    End If
    If targetFirst > maximumFirst Then
        targetFirst = maximumFirst
    End If
    If targetFirst = 0 Then
        session_MixerPageAnchor = 0
    Else
        session_MixerPageAnchor = targetFirst + mixerLayout.visibleCount - 1
        If session_MixerPageAnchor >= SESSION_CHANNEL_COUNT Then _
            session_MixerPageAnchor = SESSION_CHANNEL_COUNT - 1
    End If
    session_SetStatus "Mixer channels " + Str(targetFirst + 1) + "-" + _
        Str(targetFirst + mixerLayout.visibleCount) + " of " + _
        Str(SESSION_CHANNEL_COUNT) + "."
End Sub


Private Sub session_UpdateMixerInput(ByVal screenWidth As Integer, ByVal screenHeight As Integer)
    If session_IsModalOpen() <> 0 Then
        If session_MixerDragKind <> OSE_MIXER_CONTROL_NONE Then _
            session_FinishMixerDrag()
        session_LastMouseButtons = input_MouseButtons()
        Exit Sub
    End If

    Dim As Integer mouseX = input_MouseX()
    Dim As Integer mouseY = input_MouseY()
    Dim As Integer mouseButtons = input_MouseButtons()
    Dim As Integer leftPressed = _
        ((mouseButtons And &H1) <> 0) AndAlso ((session_LastMouseButtons And &H1) = 0)

    Dim As OseMixerControlLayout mixerLayout
    Dim As Integer mixerLayoutAnchor = session_SelectedTrack
    If session_MixerPageAnchor >= 0 Then _
        mixerLayoutAnchor = session_MixerPageAnchor
    mixerControls_CalculateLayoutForInteraction mixerLayout, screenWidth, _
        screenHeight, mixerLayoutAnchor, session_InteractionMode
    Dim As Integer activeChannel = _
        mixerControls_ChannelAtX(mixerLayout, mouseX)
    Dim As OseMixerControlHit controlHit
    mixerControls_HitTest controlHit, mixerLayout, mouseX, mouseY

    ' Mixer strips and score rows represent the same working track. Selecting
    ' a strip before applying its control keeps both views visibly in sync.
    If leftPressed <> 0 AndAlso activeChannel >= 0 AndAlso _
        mouseY >= mixerLayout.mixerTop + SESSION_MIXER_TITLE_HEIGHT AndAlso _
        activeChannel < session_Summary.trackCount Then
        If activeChannel <> session_SelectedTrack Then _
            session_SelectTrack activeChannel
    End If

    If leftPressed <> 0 Then
        session_FinishMixerDrag()
        Select Case controlHit.kind
            Case OSE_MIXER_CONTROL_CHANNEL_FADER To _
                 OSE_MIXER_CONTROL_CHANNEL_PAN
                If session_BeginMidiEdit() = 0 Then
                    session_LastMouseButtons = mouseButtons
                    Exit Sub
                End If
                session_MixerDragKind = controlHit.kind
                session_MixerDragChannel = controlHit.channelIndex
                session_MixerDragMidiChanged = 0
            Case OSE_MIXER_CONTROL_MASTER_FADER, _
                 OSE_MIXER_CONTROL_MASTER_WET, _
                 OSE_MIXER_CONTROL_MASTER_FEEDBACK
                If controlHit.kind <> OSE_MIXER_CONTROL_MASTER_FADER AndAlso _
                    masterEffect_IsAvailable() = 0 Then
                    session_SetStatus _
                        "Master echo is unavailable in this audio backend."
                Else
                    session_MixerDragKind = controlHit.kind
                End If
            Case OSE_MIXER_CONTROL_CHANNEL_MUTE
                session_ToggleMute controlHit.channelIndex
                session_ApplyMixerState()
                session_SetStatus "Mute changed on channel " + _
                    Str(controlHit.channelIndex + 1) + "."
            Case OSE_MIXER_CONTROL_CHANNEL_SOLO
                session_ToggleSolo controlHit.channelIndex
                session_SetStatus "Solo changed on channel " + _
                    Str(controlHit.channelIndex + 1) + "."
            Case OSE_MIXER_CONTROL_CHANNEL_RECORD
                session_ToggleRecord controlHit.channelIndex
            Case OSE_MIXER_CONTROL_PAGE_PREVIOUS, _
                 OSE_MIXER_CONTROL_PAGE_NEXT
                Dim As Integer pageDirection = IIf( _
                    controlHit.kind = OSE_MIXER_CONTROL_PAGE_PREVIOUS, -1, 1)
                session_PageMixerChannels mixerLayout, pageDirection
        End Select
    End If

    If (mouseButtons And 1) <> 0 AndAlso _
        session_MixerDragKind <> OSE_MIXER_CONTROL_NONE Then
        Dim As Single controlValue = mixerControls_ValueForControl( _
            mixerLayout, session_MixerDragKind, session_MixerDragChannel, _
            mouseX, mouseY)
        Select Case session_MixerDragKind
            Case OSE_MIXER_CONTROL_CHANNEL_FADER To _
                 OSE_MIXER_CONTROL_CHANNEL_PAN
                Dim As Integer dragResult = session_ApplyMidiMixerDragValue( _
                    controlValue, leftPressed)
                If dragResult < 0 Then
                    session_CancelMidiEdit()
                    session_RefreshMixerFromSummary()
                    session_MixerDragKind = OSE_MIXER_CONTROL_NONE
                    session_MixerDragChannel = -1
                    session_MixerDragMidiChanged = 0
                ElseIf dragResult > 0 Then
                    session_MixerDragMidiChanged = -1
                End If
            Case OSE_MIXER_CONTROL_MASTER_FADER
                ' Master volume is a live software-mix stage and does not
                ' rewrite the document's per-channel MIDI CC7 values.
                session_MasterVolume = controlValue
                session_ApplyMixerState()
                If leftPressed <> 0 Then _
                    session_SetStatus "Master volume changed."
            Case OSE_MIXER_CONTROL_MASTER_WET
                session_MasterEchoWet = controlValue
                session_ApplyMasterEffect()
                If leftPressed <> 0 Then _
                    session_SetStatus "Master echo Wet changed."
            Case OSE_MIXER_CONTROL_MASTER_FEEDBACK
                session_MasterEchoFeedback = controlValue
                session_ApplyMasterEffect()
                If leftPressed <> 0 Then _
                    session_SetStatus "Master echo Feedback changed."
        End Select
    ElseIf (mouseButtons And &H1) = 0 Then
        session_FinishMixerDrag()
    End If

    session_LastMouseButtons = mouseButtons
End Sub


Private Function session_ScoreVisibleTrackCount( _
    ByVal screenHeight As Integer _
) As Integer
    If session_Summary.trackCount <= 0 Then
        Return 1
    End If

    Dim As Integer scoreHeight = screenHeight - SESSION_TOP_HEIGHT - _
        SESSION_MIXER_HEIGHT - 8
    If scoreHeight < 150 Then
        scoreHeight = 150
    End If

    Dim As Integer firstStaffY = SESSION_SCORE_TOP + _
        scoreLayout_FirstStaffOffset(session_ScoreTrackRowHeight)
    Dim As Integer scoreBottom = SESSION_SCORE_TOP + scoreHeight - 6
    If audio_GetCount() > 0 Then
        scoreBottom -= 30
    End If
    Dim As Integer usableHeight = scoreBottom - firstStaffY - _
        scoreLayout_StaffHeight(session_ScoreTrackRowHeight)
    Dim As Integer visibleCount = 1
    If usableHeight > 0 Then
        visibleCount = usableHeight \ session_ScoreTrackRowHeight + 1
    End If
    If visibleCount < 1 Then
        visibleCount = 1
    End If
    If visibleCount > session_Summary.trackCount Then _
        visibleCount = session_Summary.trackCount
    Return visibleCount
End Function


Private Function session_ScoreFirstTrackIndex( _
    ByVal screenHeight As Integer _
) As Integer
    If session_Summary.trackCount <= 0 Then
        Return 0
    End If

    Dim As Integer visibleCount = session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer maximumFirst = session_Summary.trackCount - visibleCount
    If maximumFirst < 0 Then
        maximumFirst = 0
    End If
    If session_ScoreFirstVisibleTrack < 0 Then _
        session_ScoreFirstVisibleTrack = 0
    If session_ScoreFirstVisibleTrack > maximumFirst Then _
        session_ScoreFirstVisibleTrack = maximumFirst

    ' Direct selection from the mixer or a menu keeps the selected track in
    ' view while leaving ordinary scrollbar movement independent of selection.
    If session_SelectedTrack < session_ScoreFirstVisibleTrack Then
        session_ScoreFirstVisibleTrack = session_SelectedTrack
    ElseIf session_SelectedTrack >= _
        session_ScoreFirstVisibleTrack + visibleCount Then
        session_ScoreFirstVisibleTrack = session_SelectedTrack - visibleCount + 1
    End If
    If session_ScoreFirstVisibleTrack < 0 Then _
        session_ScoreFirstVisibleTrack = 0
    If session_ScoreFirstVisibleTrack > maximumFirst Then _
        session_ScoreFirstVisibleTrack = maximumFirst
    Return session_ScoreFirstVisibleTrack
End Function


Private Function session_ScoreTrackFromY( _
    ByVal mouseY As Integer, _
    ByVal screenHeight As Integer _
) As Integer
    If session_Summary.trackCount <= 0 Then
        Return -1
    End If

    Dim As Integer firstStaffY = SESSION_SCORE_TOP + _
        scoreLayout_FirstStaffOffset(session_ScoreTrackRowHeight)
    Dim As Integer rowTop = firstStaffY - _
        scoreLayout_RowTopOffset(session_ScoreTrackRowHeight)
    If mouseY < rowTop Then
        Return -1
    End If

    Dim As Integer staffIndex = (mouseY - rowTop) \ _
        session_ScoreTrackRowHeight
    Dim As Integer visibleCount = session_ScoreVisibleTrackCount(screenHeight)
    If staffIndex < 0 OrElse staffIndex >= visibleCount Then
        Return -1
    End If

    Dim As Integer trackIndex = session_ScoreFirstTrackIndex(screenHeight) + _
        staffIndex
    If trackIndex < 0 OrElse trackIndex >= session_Summary.trackCount Then
        Return -1
    End If
    Return trackIndex
End Function


Private Function session_ScoreStaffYForTrack( _
    ByVal trackIndex As Integer, _
    ByVal screenHeight As Integer _
) As Integer
    Dim As Integer firstStaffY = SESSION_SCORE_TOP + _
        scoreLayout_FirstStaffOffset(session_ScoreTrackRowHeight)
    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Return firstStaffY + (trackIndex - firstTrack) * _
        session_ScoreTrackRowHeight
End Function


Private Sub session_PrepareScoreNoteCache(ByVal screenHeight As Integer)
    session_ScoreVisibleNoteCount = 0
    session_ScoreVisibleNoteOverflowed = 0
    If session_ScoreCacheGeneration = &hffffffffu Then
        ' This is a fixed array. Erase resets values but preserves its bounds.
        ' fblint: disable-next-line FBL-ARR-007 REASON: Erase resets this fixed array while preserving its bounds.
        Erase session_ScoreModelCacheGeneration
        session_ScoreCacheGeneration = 1
    Else
        session_ScoreCacheGeneration += 1
    End If

    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer visibleTrackCount = session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer lastTrack = firstTrack + visibleTrackCount - 1
    Dim As Integer modelNoteLimit = midi_GetEditableNoteCount() - 1

    For modelNoteIndex As Integer = 0 To modelNoteLimit
        Dim As MidiEditableNote editableNote
        If midi_GetEditableNote(modelNoteIndex, editableNote) = 0 Then _
            Continue For
        If editableNote.trackIndex < firstTrack OrElse _
            editableNote.trackIndex > lastTrack Then Continue For
        If session_NoteIsVisible(editableNote) = 0 Then
            Continue For
        End If

        If session_ScoreVisibleNoteCount >= _
            SESSION_SCORE_NOTE_CACHE_CAPACITY Then
            ' A pathological dense passage must not make the render loop
            ' allocate or iterate without a bound. The visible prefix remains
            ' useful, and the status line identifies that it was clipped.
            session_ScoreVisibleNoteOverflowed = -1
            Continue For
        End If
        session_ScoreVisibleNoteIndices(session_ScoreVisibleNoteCount) = _
            modelNoteIndex
        session_ScoreModelCacheGeneration(modelNoteIndex) = _
            session_ScoreCacheGeneration
        session_ScoreModelCachePosition(modelNoteIndex) = _
            session_ScoreVisibleNoteCount
        session_ScoreStemComputed(session_ScoreVisibleNoteCount) = 0
        session_ScoreBeamComputed(session_ScoreVisibleNoteCount) = 0
        session_ScoreBeamPartner(session_ScoreVisibleNoteCount) = -1
        session_ScoreVisibleNoteCount += 1
    Next
End Sub


Private Function session_ScoreCachePositionForModel( _
    ByVal noteIndex As Integer _
) As Integer
    If noteIndex < 0 OrElse noteIndex >= OSE_MAX_EDITABLE_NOTES Then
        Return -1
    End If
    If session_ScoreModelCacheGeneration(noteIndex) <> _
        session_ScoreCacheGeneration Then Return -1

    Dim As Integer cacheIndex = session_ScoreModelCachePosition(noteIndex)
    If cacheIndex < 0 OrElse cacheIndex >= session_ScoreVisibleNoteCount OrElse _
        session_ScoreVisibleNoteIndices(cacheIndex) <> noteIndex Then Return -1
    Return cacheIndex
End Function


Private Function session_TrackUsesBassClef(ByVal trackIndex As Integer) As Integer
    Return scoreLayout_UsesBassClef(session_ScoreLayout, trackIndex)
End Function


Private Sub session_NoteScreenPosition( _
    ByRef editableNote As MidiEditableNote, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByRef noteX As Integer, _
    ByRef noteY As Integer _
)
    Dim As Integer scoreWidth = screenWidth - SESSION_SCORE_LEFT - 4
    Dim As Integer scoreHeight = screenHeight - SESSION_TOP_HEIGHT - SESSION_MIXER_HEIGHT - 8
    If scoreWidth < 160 Then
        scoreWidth = 160
    End If
    If scoreHeight < 150 Then
        scoreHeight = 150
    End If

    Dim As ULongInt ticksPerView = session_ViewTicks()
    Dim As ULongInt visibleStart = editableNote.startTick
    Dim As ULongInt viewEndTick = session_ViewStartTick + ticksPerView
    If visibleStart < session_ViewStartTick Then
        visibleStart = session_ViewStartTick
    End If
    If visibleStart > viewEndTick Then
        visibleStart = viewEndTick
    End If
    Dim As ULongInt viewTick = visibleStart - session_ViewStartTick
    Dim As Integer timelineWidth = scoreWidth - SESSION_SCORE_NOTE_LEFT - _
        SESSION_SCORE_NOTE_RIGHT
    If timelineWidth <= 0 Then
        timelineWidth = 1
    End If
    noteX = SESSION_SCORE_LEFT + SESSION_SCORE_NOTE_LEFT + _
        CInt((CDbl(timelineWidth) * CDbl(viewTick)) / CDbl(ticksPerView))

    Dim As Integer staffY = session_ScoreStaffYForTrack( _
        editableNote.trackIndex, screenHeight)

    ' Each visible track owns one staff row. Treble F5 is the top line and
    ' lower or higher pitches use ledger lines, matching the compact
    ' instrument-by-instrument layout of the reference editor.
    Dim As Integer noteSharpsFlats = 0
    Dim As Integer noteKeyIndex = session_KeySignatureIndexForTick( _
        editableNote.startTick)
    If noteKeyIndex >= 0 AndAlso noteKeyIndex < _
        session_Summary.keySignatureCount Then
        noteSharpsFlats = session_Summary.keySignatureMap( _
            noteKeyIndex).sharpsFlats
    End If
    Dim As Integer diatonicStep = session_MidiDiatonicIndexForKey( _
        CInt(editableNote.keyNumber), noteSharpsFlats)
    noteY = scoreLayout_NoteY(session_ScoreLayout, _
        editableNote.trackIndex, staffY, diatonicStep, _
        session_ScoreTrackRowHeight)
End Sub


Private Function session_MidiDiatonicIndexForKey( _
    ByVal keyNumber As Integer, _
    ByVal sharpsFlats As Integer _
) As Integer
    If keyNumber < 0 Then
        keyNumber = 0
    End If
    If keyNumber > 127 Then
        keyNumber = 127
    End If

    Dim As Integer whiteOffset
    Select Case keyNumber Mod 12
        Case 0
            whiteOffset = 0
        Case 1
            If sharpsFlats < 0 Then
                whiteOffset = 1
            Else
                whiteOffset = 0
            End If
        Case 2
            whiteOffset = 1
        Case 3
            If sharpsFlats < 0 Then
                whiteOffset = 2
            Else
                whiteOffset = 1
            End If
        Case 4
            whiteOffset = 2
        Case 5
            whiteOffset = 3
        Case 6
            If sharpsFlats < 0 Then
                whiteOffset = 4
            Else
                whiteOffset = 3
            End If
        Case 7
            whiteOffset = 4
        Case 8
            If sharpsFlats < 0 Then
                whiteOffset = 5
            Else
                whiteOffset = 4
            End If
        Case 9
            whiteOffset = 5
        Case 10
            If sharpsFlats < 0 Then
                whiteOffset = 6
            Else
                whiteOffset = 5
            End If
        Case Else
            whiteOffset = 6
    End Select
    Return (keyNumber \ 12) * 7 + whiteOffset
End Function


Private Function session_KeyFromScreenYForTrack( _
    ByVal mouseY As Integer, _
    ByVal trackIndex As Integer, _
    ByVal noteTick As ULongInt, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
) As Integer
    Dim As Integer nearestKey = 60
    Dim As Integer nearestDistance = SESSION_MAX_INTEGER

    For keyNumber As Integer = 0 To 127
        Dim As MidiEditableNote probeNote
        probeNote.trackIndex = trackIndex
        probeNote.startTick = noteTick
        probeNote.keyNumber = CUByte(keyNumber)
        Dim As Integer ignoredX
        Dim As Integer keyY
        session_NoteScreenPosition probeNote, screenWidth, screenHeight, _
            ignoredX, keyY
        Dim As Integer distance = Abs(mouseY - keyY)
        If distance < nearestDistance Then
            nearestDistance = distance
            nearestKey = keyNumber
        End If
    Next

    Return nearestKey
End Function


Private Function session_KeyFromScreenY( _
    ByVal mouseY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
) As Integer
    Return session_KeyFromScreenYForTrack(mouseY, session_SelectedTrack, _
        session_ViewStartTick, screenWidth, screenHeight)
End Function


Private Function session_FindNoteAt( _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
) As Integer
    Dim As Integer nearestNote = -1
    Dim As Integer hitRadius = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 14)
    Dim As Integer hitHalfHeight = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 8)
    Dim As Integer hitHalfWidth = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 6)
    Dim As Integer nearestDistance = hitRadius * hitRadius

    For cacheIndex As Integer = 0 To session_ScoreVisibleNoteCount - 1
        Dim As Integer noteIndex = session_ScoreVisibleNoteIndices(cacheIndex)
        Dim As MidiEditableNote editableNote
        If midi_GetEditableNote(noteIndex, editableNote) = 0 Then
            Continue For
        End If
        If session_NoteIsVisible(editableNote) = 0 Then
            Continue For
        End If

        Dim As Integer noteX
        Dim As Integer noteY
        session_NoteScreenPosition editableNote, screenWidth, screenHeight, noteX, noteY
        Dim As Integer scoreWidth = screenWidth - SESSION_SCORE_LEFT - 4
        If scoreWidth < 160 Then
            scoreWidth = 160
        End If
        Dim As Integer noteWidth = session_NoteScreenWidth(editableNote, scoreWidth)
        If noteWidth < hitHalfWidth Then
            noteWidth = hitHalfWidth
        End If
        If mouseX < noteX - hitHalfWidth OrElse _
            mouseX > noteX + noteWidth OrElse _
            mouseY < noteY - hitHalfHeight OrElse _
            mouseY > noteY + hitHalfHeight Then Continue For
        Dim As Integer deltaX = mouseX - noteX
        Dim As Integer deltaY = mouseY - noteY
        Dim As Integer distance = deltaX * deltaX + deltaY * deltaY
        If distance < nearestDistance Then
            nearestDistance = distance
            nearestNote = noteIndex
        End If
    Next

    Return nearestNote
End Function


Private Sub session_ScoreEditBounds( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByRef editLeft As Integer, _
    ByRef editTop As Integer, _
    ByRef editRight As Integer, _
    ByRef editBottom As Integer _
)
    editLeft = SESSION_SCORE_LEFT + SESSION_SCORE_NOTE_LEFT
    editTop = SESSION_SCORE_TOP + 26
    editRight = screenWidth - 8
    editBottom = screenHeight - SESSION_MIXER_HEIGHT - _
        SESSION_SCORE_SCROLLBAR_SIZE - 5
    If editRight < editLeft Then
        editRight = editLeft
    End If
    If editBottom < editTop Then
        editBottom = editTop
    End If
End Sub


Private Function session_TickFromScreenX( _
    ByVal screenX As Integer, _
    ByVal screenWidth As Integer _
) As ULongInt
    Dim As Integer scoreWidth = screenWidth - SESSION_SCORE_LEFT - 4
    If scoreWidth < 160 Then
        scoreWidth = 160
    End If
    Dim As Integer timelineWidth = scoreWidth - SESSION_SCORE_NOTE_LEFT - _
        SESSION_SCORE_NOTE_RIGHT
    If timelineWidth <= 0 Then
        timelineWidth = 1
    End If

    Dim As Double tickRatio = CDbl(screenX - SESSION_SCORE_LEFT - _
        SESSION_SCORE_NOTE_LEFT) / CDbl(timelineWidth)
    If tickRatio < 0.0 Then
        tickRatio = 0.0
    End If
    If tickRatio > 1.0 Then
        tickRatio = 1.0
    End If
    Dim As ULongInt scoreTick = session_ViewStartTick + _
        CULngInt(tickRatio * CDbl(session_ViewTicks()))
    If scoreTick > OSE_MAX_MIDI_TICK Then
        scoreTick = OSE_MAX_MIDI_TICK
    End If

    Dim As ULongInt snapTicks = session_ScoreSnapTicks()
    Dim As ULongInt halfSnap = snapTicks \ 2
    If scoreTick <= OSE_MAX_MIDI_TICK - halfSnap Then _
        scoreTick += halfSnap
    scoreTick = (scoreTick \ snapTicks) * snapTicks
    If scoreTick > OSE_MAX_MIDI_TICK Then
        scoreTick = OSE_MAX_MIDI_TICK
    End If
    Return scoreTick
End Function


Private Sub session_BeginScoreMarquee( _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer, _
    ByVal additiveSelection As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal cutAfterSelection As Integer = 0 _
)
    Dim As Integer editLeft
    Dim As Integer editTop
    Dim As Integer editRight
    Dim As Integer editBottom
    session_ScoreEditBounds screenWidth, screenHeight, editLeft, editTop, _
        editRight, editBottom
    If mouseX < editLeft Then
        mouseX = editLeft
    End If
    If mouseX > editRight Then
        mouseX = editRight
    End If
    If mouseY < editTop Then
        mouseY = editTop
    End If
    If mouseY > editBottom Then
        mouseY = editBottom
    End If

    session_ScoreMarqueeActive = -1
    session_ScoreMarqueeAdditive = additiveSelection
    session_ScoreMarqueeCuts = cutAfterSelection
    session_ScoreMarqueeStartX = mouseX
    session_ScoreMarqueeStartY = mouseY
    session_ScoreMarqueeCurrentX = mouseX
    session_ScoreMarqueeCurrentY = mouseY
End Sub


Private Sub session_UpdateScoreMarquee( _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    If session_ScoreMarqueeActive = 0 Then
        Exit Sub
    End If
    Dim As Integer editLeft
    Dim As Integer editTop
    Dim As Integer editRight
    Dim As Integer editBottom
    session_ScoreEditBounds screenWidth, screenHeight, editLeft, editTop, _
        editRight, editBottom
    If mouseX < editLeft Then
        mouseX = editLeft
    End If
    If mouseX > editRight Then
        mouseX = editRight
    End If
    If mouseY < editTop Then
        mouseY = editTop
    End If
    If mouseY > editBottom Then
        mouseY = editBottom
    End If
    session_ScoreMarqueeCurrentX = mouseX
    session_ScoreMarqueeCurrentY = mouseY
End Sub


Private Sub session_FinishScoreMarquee( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    If session_ScoreMarqueeActive = 0 Then
        Exit Sub
    End If

    Dim As Integer selectionLeft = session_ScoreMarqueeStartX
    Dim As Integer selectionRight = session_ScoreMarqueeCurrentX
    Dim As Integer selectionTop = session_ScoreMarqueeStartY
    Dim As Integer selectionBottom = session_ScoreMarqueeCurrentY
    If selectionLeft > selectionRight Then
        Swap selectionLeft, selectionRight
    End If
    If selectionTop > selectionBottom Then
        Swap selectionTop, selectionBottom
    End If

    If session_ScoreMarqueeAdditive = 0 Then _
        session_ClearNoteSelection()
    Dim As Integer addedCount
    For cacheIndex As Integer = 0 To session_ScoreVisibleNoteCount - 1
        Dim As Integer noteIndex = session_ScoreVisibleNoteIndices(cacheIndex)
        Dim As MidiEditableNote editableNote
        If midi_GetEditableNote(noteIndex, editableNote) = 0 Then
            Continue For
        End If
        Dim As Integer noteX
        Dim As Integer noteY
        session_NoteScreenPosition editableNote, screenWidth, screenHeight, _
            noteX, noteY

        ' Selection intersects the visible notehead rather than the entire
        ' duration. A long tied note therefore has one unambiguous handle.
        If noteX + 11 < selectionLeft OrElse noteX - 3 > selectionRight OrElse _
            noteY + 8 < selectionTop OrElse noteY - 8 > selectionBottom Then _
            Continue For
        If noteSelection_Add(session_NoteSelection, noteIndex, -1) <> 0 Then _
            addedCount += 1
    Next

    session_SelectedNote = session_NoteSelection.primaryNoteIndex
    session_ScoreMarqueeActive = 0
    Dim As Integer cutAfterSelection = session_ScoreMarqueeCuts
    session_ScoreMarqueeCuts = 0
    If session_NoteSelection.count > 0 Then
        If cutAfterSelection <> 0 Then
            session_CutSelectedNotes()
        Else
            session_AnnounceSelection ""
        End If
    Else
        session_SetStatus "No notes selected."
    End If
End Sub


Private Sub session_DrawScoreMarquee()
    If session_ScoreMarqueeActive = 0 Then
        Exit Sub
    End If
    Dim As Integer selectionLeft = session_ScoreMarqueeStartX
    Dim As Integer selectionRight = session_ScoreMarqueeCurrentX
    Dim As Integer selectionTop = session_ScoreMarqueeStartY
    Dim As Integer selectionBottom = session_ScoreMarqueeCurrentY
    If selectionLeft > selectionRight Then
        Swap selectionLeft, selectionRight
    End If
    If selectionTop > selectionBottom Then
        Swap selectionTop, selectionBottom
    End If

    Dim As Integer selectionWidth = selectionRight - selectionLeft
    Dim As Integer selectionHeight = selectionBottom - selectionTop
    If selectionWidth < 1 Then
        selectionWidth = 1
    End If
    If selectionHeight < 1 Then
        selectionHeight = 1
    End If
    backend_RectEx selectionLeft, selectionTop, selectionWidth, selectionHeight, _
        session_ThemePalette.scoreNoteFillColor, 1, 1, 42
    backend_RectEx selectionLeft, selectionTop, selectionWidth, selectionHeight, _
        session_ThemePalette.scoreNoteBorderColor, 0, 1, 255
End Sub


Private Function session_BeginScoreNoteDrag( _
    ByVal noteIndex As Integer, _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
) As Integer
    If session_NoteSelection.count <= 0 OrElse _
        session_NoteSelection.count > OSE_NOTE_SELECTION_CAPACITY OrElse _
        session_NoteIsSelected(noteIndex) = 0 Then Return 0

    session_ScoreDragOriginalCount = session_NoteSelection.count
    session_ScoreDragMinimumStartTick = OSE_MAX_MIDI_TICK
    session_ScoreDragMaximumEndTick = 0
    session_ScoreDragMinimumKey = SESSION_MIDI_MAX_KEY
    session_ScoreDragMaximumKey = 0
    Dim As Integer anchorFound

    For selectionPosition As Integer = 0 To _
        session_NoteSelection.count - 1
        Dim As Integer selectedIndex = _
            session_NoteSelection.noteIndices(selectionPosition)
        Dim As MidiEditableNote editableNote
        If midi_GetEditableNote(selectedIndex, editableNote) = 0 Then
            session_ScoreDragOriginalCount = 0
            Return 0
        End If
        session_ScoreDragIndices(selectionPosition) = selectedIndex
        session_ScoreDragOriginalNotes(selectionPosition) = editableNote
        If editableNote.startTick < session_ScoreDragMinimumStartTick Then _
            session_ScoreDragMinimumStartTick = editableNote.startTick
        Dim As ULongInt noteEnd = editableNote.startTick + _
            editableNote.durationTicks
        If noteEnd > session_ScoreDragMaximumEndTick Then _
            session_ScoreDragMaximumEndTick = noteEnd
        If editableNote.keyNumber < session_ScoreDragMinimumKey Then _
            session_ScoreDragMinimumKey = editableNote.keyNumber
        If editableNote.keyNumber > session_ScoreDragMaximumKey Then _
            session_ScoreDragMaximumKey = editableNote.keyNumber
        If selectedIndex = noteIndex Then
            session_ScoreDragAnchorStartTick = editableNote.startTick
            session_ScoreDragAnchorDurationTicks = editableNote.durationTicks
            session_ScoreDragAnchorKey = editableNote.keyNumber
            session_ScoreDragAnchorTrack = editableNote.trackIndex
            anchorFound = -1
        End If
    Next
    If anchorFound = 0 Then
        session_ScoreDragOriginalCount = 0
        Return 0
    End If

    Dim As MidiEditableNote anchorNote
    If midi_GetEditableNote(noteIndex, anchorNote) = 0 Then
        Return 0
    End If
    Dim As Integer anchorX
    Dim As Integer anchorY
    session_NoteScreenPosition anchorNote, screenWidth, screenHeight, _
        anchorX, anchorY

    session_ScoreDragNote = noteIndex
    session_ScoreDragStartMouseX = mouseX
    session_ScoreDragStartMouseY = mouseY
    session_ScoreDragMouseOffsetX = mouseX - anchorX
    session_ScoreDragMouseOffsetY = mouseY - anchorY
    session_ScoreDragResizeMode = IIf( _
        input_KeyPressed(FB.SC_ALT) <> 0 AndAlso _
        session_ScoreDragOriginalCount = 1, -1, 0)
    session_ScoreDragHistoryCaptured = 0
    session_ScoreDragHasApplied = 0
    session_ScoreDragLastTickDelta = 0
    session_ScoreDragLastPitchDelta = 0
    Return -1
End Function


Private Sub session_ApplyScoreNoteDrag( _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    If session_ScoreDragNote < 0 OrElse _
        session_ScoreDragOriginalCount <= 0 Then Exit Sub
    If session_ScoreDragHasApplied = 0 AndAlso _
        Abs(mouseX - session_ScoreDragStartMouseX) < _
            SESSION_SCORE_DRAG_THRESHOLD AndAlso _
        Abs(mouseY - session_ScoreDragStartMouseY) < _
            SESSION_SCORE_DRAG_THRESHOLD Then Exit Sub

    If session_ScoreDragResizeMode <> 0 Then
        Dim As ULongInt endTick = session_TickFromScreenX(mouseX, screenWidth)
        Dim As ULongInt newDuration = session_ScoreSnapTicks()
        If endTick > session_ScoreDragAnchorStartTick Then _
            newDuration = endTick - session_ScoreDragAnchorStartTick
        Dim As ULongInt maximumDuration = OSE_MAX_MIDI_TICK - _
            session_ScoreDragAnchorStartTick
        If newDuration > maximumDuration Then
            newDuration = maximumDuration
        End If
        If newDuration = 0 Then
            newDuration = 1
        End If
        If newDuration = session_ScoreDragAnchorDurationTicks AndAlso _
            session_ScoreDragHasApplied = 0 Then Exit Sub
        If session_ScoreDragHistoryCaptured = 0 Then
            If session_BeginMidiEdit() = 0 Then
                session_ScoreDragNote = -1
                Exit Sub
            End If
            session_ScoreDragHistoryCaptured = -1
        End If
        session_ScoreDragAdjustedNotes(0) = session_ScoreDragOriginalNotes(0)
        session_ScoreDragAdjustedNotes(0).durationTicks = newDuration
        If midi_SetEditableNotes(session_Summary, _
            @session_ScoreDragIndices(0), _
            @session_ScoreDragAdjustedNotes(0), 1) <> 0 Then
            session_ScoreDragHasApplied = -1
            session_Dirty = -1
        Else
            session_CancelMidiEdit()
            session_ScoreDragHistoryCaptured = 0
            session_ScoreDragNote = -1
        End If
        Exit Sub
    End If

    Dim As ULongInt targetTick = session_TickFromScreenX( _
        mouseX - session_ScoreDragMouseOffsetX, screenWidth)
    Dim As LongInt tickDelta = CLngInt(targetTick) - _
        CLngInt(session_ScoreDragAnchorStartTick)
    Dim As LongInt minimumTickDelta = _
        -CLngInt(session_ScoreDragMinimumStartTick)
    Dim As LongInt maximumTickDelta = CLngInt(OSE_MAX_MIDI_TICK) - _
        CLngInt(session_ScoreDragMaximumEndTick)
    If tickDelta < minimumTickDelta Then
        tickDelta = minimumTickDelta
    End If
    If tickDelta > maximumTickDelta Then
        tickDelta = maximumTickDelta
    End If

    Dim As Integer targetKey = session_KeyFromScreenYForTrack( _
        mouseY - session_ScoreDragMouseOffsetY, _
        session_ScoreDragAnchorTrack, session_ScoreDragAnchorStartTick, _
        screenWidth, screenHeight)
    Dim As Integer pitchDelta = targetKey - session_ScoreDragAnchorKey
    If pitchDelta < -session_ScoreDragMinimumKey Then _
        pitchDelta = -session_ScoreDragMinimumKey
    If pitchDelta > SESSION_MIDI_MAX_KEY - session_ScoreDragMaximumKey Then _
        pitchDelta = SESSION_MIDI_MAX_KEY - session_ScoreDragMaximumKey

    If session_ScoreDragHasApplied <> 0 AndAlso _
        tickDelta = session_ScoreDragLastTickDelta AndAlso _
        pitchDelta = session_ScoreDragLastPitchDelta Then Exit Sub
    If session_ScoreDragHasApplied = 0 AndAlso tickDelta = 0 AndAlso _
        pitchDelta = 0 Then Exit Sub
    If session_ScoreDragHistoryCaptured = 0 Then
        If session_BeginMidiEdit() = 0 Then
            session_ScoreDragNote = -1
            Exit Sub
        End If
        session_ScoreDragHistoryCaptured = -1
    End If

    For dragPosition As Integer = 0 To session_ScoreDragOriginalCount - 1
        session_ScoreDragAdjustedNotes(dragPosition) = _
            session_ScoreDragOriginalNotes(dragPosition)
        session_ScoreDragAdjustedNotes(dragPosition).startTick = CULngInt( _
            CLngInt(session_ScoreDragOriginalNotes(dragPosition).startTick) + _
            tickDelta)
        session_ScoreDragAdjustedNotes(dragPosition).keyNumber = CUByte( _
            CInt(session_ScoreDragOriginalNotes(dragPosition).keyNumber) + _
            pitchDelta)
    Next
    If midi_SetEditableNotes(session_Summary, @session_ScoreDragIndices(0), _
        @session_ScoreDragAdjustedNotes(0), _
        session_ScoreDragOriginalCount) <> 0 Then
        session_ScoreDragHasApplied = -1
        session_ScoreDragLastTickDelta = tickDelta
        session_ScoreDragLastPitchDelta = pitchDelta
        session_Dirty = -1
    Else
        session_CancelMidiEdit()
        session_ScoreDragHistoryCaptured = 0
        session_ScoreDragNote = -1
    End If
End Sub


Private Sub session_EndScoreNoteDrag()
    If session_ScoreDragHistoryCaptured <> 0 Then
        Dim As Integer hasNetChange = session_ScoreDragHasApplied
        If session_ScoreDragResizeMode <> 0 Then
            If session_ScoreDragAdjustedNotes(0).durationTicks = _
                session_ScoreDragAnchorDurationTicks Then hasNetChange = 0
        ElseIf session_ScoreDragLastTickDelta = 0 AndAlso _
            session_ScoreDragLastPitchDelta = 0 Then
            hasNetChange = 0
        End If

        If hasNetChange = 0 Then
            session_CancelMidiEdit()
        ElseIf session_CommitMidiEdit() <> 0 Then
            If session_ScoreDragResizeMode <> 0 Then
                session_SetStatus "Resized selected note."
            Else
                session_SetStatus "Moved " + _
                    Str(session_ScoreDragOriginalCount) + _
                    IIf(session_ScoreDragOriginalCount = 1, " note.", " notes.")
            End If
        End If
    End If
    session_ScoreDragNote = -1
    session_ScoreDragOriginalCount = 0
    session_ScoreDragResizeMode = 0
    session_ScoreDragHistoryCaptured = 0
    session_ScoreDragHasApplied = 0
End Sub


Private Function session_AddScoreNoteAt( _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
) As Integer
    If session_Summary.trackCount <= 0 OrElse _
        session_SelectedTrack < 0 OrElse _
        session_SelectedTrack >= session_Summary.trackCount Then Return 0
    Dim As ULongInt newTick = session_TickFromScreenX(mouseX, screenWidth)
    Dim As ULongInt durationTicks = scoreAddTool_DurationTicks( _
        session_AddToolState, session_Summary.division)
    If durationTicks = 0 Then
        durationTicks = 1
    End If
    If durationTicks > OSE_MAX_MIDI_TICK Then
        Return 0
    End If
    If newTick > OSE_MAX_MIDI_TICK - durationTicks Then _
        newTick = OSE_MAX_MIDI_TICK - durationTicks

    Dim As Integer newKey = session_KeyFromScreenY( _
        mouseY, screenWidth, screenHeight)
    newKey = scoreAddTool_ApplyAccidental(newKey, session_AddToolState)

    If session_AddToolState.tied <> 0 Then
        For noteIndex As Integer = 0 To midi_GetEditableNoteCount() - 1
            Dim As MidiEditableNote tieSource
            If midi_GetEditableNote(noteIndex, tieSource) = 0 Then
                Continue For
            End If
            If tieSource.trackIndex <> session_SelectedTrack OrElse _
                tieSource.keyNumber <> newKey Then Continue For
            If tieSource.durationTicks > OSE_MAX_MIDI_TICK - _
                tieSource.startTick Then Continue For
            If tieSource.startTick + tieSource.durationTicks <> newTick Then _
                Continue For
            If tieSource.durationTicks > OSE_MAX_MIDI_TICK - durationTicks Then _
                Continue For

            If session_BeginMidiEdit() = 0 Then
                Return 0
            End If
            Dim As Integer tieIndex(0 To 0) = {noteIndex}
            Dim As MidiEditableNote tiedNote(0 To 0)
            tiedNote(0) = tieSource
            tiedNote(0).durationTicks += durationTicks
            If midi_SetEditableNotes(session_Summary, @tieIndex(0), _
                @tiedNote(0), 1) = 0 Then
                session_CancelMidiEdit()
                session_SetStatus "Tie failed: the source note changed."
                Return 0
            End If
            If session_CommitMidiEdit() = 0 Then
                Return 0
            End If
            session_SelectOnlyNote noteIndex
            session_Dirty = -1
            session_SetStatus "Tied " + midi_KeyDisplayName(CUByte(newKey)) + _
                " through tick " + Str(newTick + durationTicks) + "."
            Return -1
        Next
    End If

    If session_BeginMidiEdit() = 0 Then
        Return 0
    End If

    Dim As Integer addedNote = midi_AddEditableNote( _
        session_Summary, session_SelectedTrack, newTick, durationTicks, _
        newKey, session_SelectedTrack Mod SESSION_CHANNEL_COUNT, 100)
    If addedNote < 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Score insert failed: note or track limit reached."
        Return 0
    End If
    If session_CommitMidiEdit() = 0 Then
        Return 0
    End If

    session_SelectOnlyNote addedNote
    session_Dirty = -1
    session_SetStatus "Inserted " + _
        scoreAddTool_DurationName(session_AddToolState.durationIndex) + " " + _
        midi_KeyDisplayName(CUByte(newKey)) + " at tick " + Str(newTick) + "."
    Return -1
End Function


Private Function session_PasteCopiedNotesAt( _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
) As Integer
    If session_NoteClipboard.count <= 0 OrElse _
        session_NoteClipboard.count > OSE_NOTE_SELECTION_CAPACITY Then
        session_SetStatus "Paste ignored: the note clipboard is empty."
        Return 0
    End If
    If midi_GetEditableNoteCount() > OSE_MAX_EDITABLE_NOTES - _
        session_NoteClipboard.count Then
        session_SetStatus "Paste failed: the document note limit would be exceeded."
        Return 0
    End If

    Dim As Integer pasteTrack = session_ScoreTrackFromY(mouseY, screenHeight)
    If pasteTrack < 0 Then
        session_SetStatus "Paste ignored: click inside a destination staff."
        Return 0
    End If
    Dim As ULongInt pasteTick = session_TickFromScreenX(mouseX, screenWidth)

    If noteClipboard_PreparePaste(session_NoteClipboard, pasteTick, pasteTrack, _
        session_Summary.trackCount, @session_NotePasteBuffer(0), _
        OSE_NOTE_SELECTION_CAPACITY) = 0 Then
        session_SetStatus _
            "Paste failed: the copied phrase does not fit at that staff location."
        Return 0
    End If

    session_StopPlayback()
    If session_BeginMidiEdit() = 0 Then
        Return 0
    End If
    Dim As Integer firstAddedIndex = midi_AddEditableNotes( _
        session_Summary, @session_NotePasteBuffer(0), _
        session_NoteClipboard.count)
    If firstAddedIndex < 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Paste failed: copied notes could not be stored."
        Return 0
    End If
    If session_CommitMidiEdit() = 0 Then
        Return 0
    End If

    noteSelection_Clear session_NoteSelection
    For clipboardPosition As Integer = 0 To _
        session_NoteClipboard.count - 1
        noteSelection_Add session_NoteSelection, _
            firstAddedIndex + clipboardPosition, -1
    Next
    session_SelectedNote = session_NoteSelection.primaryNoteIndex
    session_SetSelectedTrackPreservingNotes pasteTrack
    session_Dirty = -1
    session_SetStatus "Pasted " + Str(session_NoteClipboard.count) + _
        IIf(session_NoteClipboard.count = 1, " note.", " notes.")
    Return -1
End Function


Private Function session_HandleAddPaletteClick( _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer _
) As Integer
    If session_ActiveScoreTool <> SESSION_SCORE_TOOL_ADD_NOTE OrElse _
        session_AddPaletteVisible = 0 Then Return 0

    Dim As OseScoreControlHit controlHit
    scoreControls_HitTestWithMetrics controlHit, mouseX, mouseY, -1, _
        session_InteractionMetrics
    If controlHit.kind = OSE_SCORE_CONTROL_NONE Then
        Return 0
    End If
    ' The visible palette and tool rail coexist. A rail hit must continue to
    ' the tool dispatcher instead of being consumed as palette background.
    If controlHit.kind = OSE_SCORE_CONTROL_TOOL Then
        Return 0
    End If
    If controlHit.kind = OSE_SCORE_CONTROL_PALETTE_BACKGROUND Then
        Return -1
    End If

    If controlHit.kind = OSE_SCORE_CONTROL_DURATION Then
        If scoreAddTool_SetDuration(session_AddToolState, _
            controlHit.index) <> 0 Then
            session_SetStatus "Add Note palette: " + _
                scoreAddTool_DurationName(controlHit.index) + " note selected."
        End If
        Return -1
    End If
    If controlHit.kind <> OSE_SCORE_CONTROL_MODIFIER Then
        Return -1
    End If

    Select Case controlHit.index
        Case 0
            Dim As Integer sharpCount = 1
            If session_AddToolState.accidentalSemitones > 0 Then _
                sharpCount = session_AddToolState.accidentalSemitones + 1
            If sharpCount > 2 Then
                sharpCount = 1
            End If
            scoreAddTool_SetAccidental session_AddToolState, sharpCount
            session_SetStatus IIf(sharpCount = 2, _
                "Double sharp selected.", "Sharp selected.")
        Case 1
            Dim As Integer flatCount = -1
            If session_AddToolState.accidentalSemitones < 0 Then _
                flatCount = session_AddToolState.accidentalSemitones - 1
            If flatCount < -2 Then
                flatCount = -1
            End If
            scoreAddTool_SetAccidental session_AddToolState, flatCount
            session_SetStatus IIf(flatCount = -2, _
                "Double flat selected.", "Flat selected.")
        Case 2
            scoreAddTool_SetAccidental session_AddToolState, 0
            session_SetStatus "Natural selected."
        Case 3
            scoreAddTool_ToggleModifier session_AddToolState, _
                OSE_SCORE_MODIFIER_DOT
            session_SetStatus IIf(session_AddToolState.dotted <> 0, _
                "Dot selected.", "Dot cleared.")
        Case 4
            scoreAddTool_ToggleModifier session_AddToolState, _
                OSE_SCORE_MODIFIER_TRIPLET
            session_SetStatus IIf(session_AddToolState.triplet <> 0, _
                "Triplet selected.", "Triplet cleared.")
        Case 5
            scoreAddTool_ToggleModifier session_AddToolState, _
                OSE_SCORE_MODIFIER_TIE
            session_SetStatus IIf(session_AddToolState.tied <> 0, _
                "Tie selected.", "Tie cleared.")
    End Select
    Return -1
End Function


Private Function session_HandleScoreToolClick( _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer _
) As Integer
    Dim As OseScoreControlHit controlHit
    scoreControls_HitTestWithMetrics controlHit, mouseX, mouseY, 0, _
        session_InteractionMetrics
    If controlHit.kind <> OSE_SCORE_CONTROL_TOOL Then
        Return 0
    End If
    Dim As Integer toolIndex = controlHit.index

    Select Case toolIndex
        Case SESSION_SCORE_TOOL_SELECT
            session_ActiveScoreTool = SESSION_SCORE_TOOL_SELECT
            session_AddPaletteVisible = 0
            session_SetStatus _
                "Select tool: click, Shift-click, marquee, or drag notes."
        Case SESSION_SCORE_TOOL_ADD_NOTE
            If session_ActiveScoreTool = SESSION_SCORE_TOOL_ADD_NOTE Then
                session_AddPaletteVisible = IIf( _
                    session_AddPaletteVisible = 0, -1, 0)
            Else
                session_ActiveScoreTool = SESSION_SCORE_TOOL_ADD_NOTE
                session_AddPaletteVisible = -1
            End If
            session_SetStatus "Add Note: choose a value, then click the score."
        Case SESSION_SCORE_TOOL_DELETE_NOTE
            session_ActiveScoreTool = SESSION_SCORE_TOOL_DELETE_NOTE
            session_AddPaletteVisible = 0
            session_SetStatus "Delete Note: click the note to remove."
        Case SESSION_SCORE_TOOL_CUT
            session_ActiveScoreTool = SESSION_SCORE_TOOL_CUT
            session_AddPaletteVisible = 0
            session_SetStatus "Cut: drag across the notes to remove and copy."
        Case SESSION_SCORE_TOOL_PASTE
            session_PasteCopiedNotes()
    End Select
    /'
        The palette is drawn after the cached score. Closing it must invalidate
        that underlying cache or its last pixels remain over the staff until an
        unrelated score change happens to force a redraw.
    '/
    session_InvalidateInterfaceCaches()
    Return -1
End Function

#endif

/' end of src/editor/score_input.bi '/
