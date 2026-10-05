/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/microphone.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Coordinate monophonic microphone transcription.

    Responsibilities:

        - validate capture and quantization choices
        - route captured audio and detected notes through owned document state

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_MICROPHONE_BI__
#define __OSE_EDITOR_MICROPHONE_BI__


' -------------------------------------------------------------------------
' Monophonic microphone transcription
' -------------------------------------------------------------------------

Private Sub session_MicAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_MicWindow = 0 Then
        Exit Sub
    End If
    gui_AddGeneratedWidget child
    gui_SetParent child, session_MicWindow
End Sub


Private Sub session_SetMicState(ByVal message As String)
    If session_MicStateLabel = 0 OrElse session_MicStateLabel->data = 0 Then _
        Exit Sub
    Dim As LabelData Ptr labelData = Cast(LabelData Ptr, _
        session_MicStateLabel->data)
    labelData->text = message
End Sub


Private Function session_NewMicCaptureFilename() As String
    Return capturePaths_NewFilename( _
        session_CaptureDirectory(), "session-mic-take", ".wav")
End Function


Private Function session_ReadMicSettings( _
    ByRef denominator As Integer, _
    ByRef minimumNoteMilliseconds As ULong _
) As Integer
    If session_MicQuantizeBox = 0 OrElse _
        session_MicMinimumNoteBox = 0 Then Return 0
    Dim As ULongInt parsedDenominator
    Dim As ULongInt parsedMinimum
    If numericText_ParseUnsigned(textbox_GetText(session_MicQuantizeBox), _
        parsedDenominator, 32) = 0 OrElse _
        numericText_ParseUnsigned(textbox_GetText(session_MicMinimumNoteBox), _
        parsedMinimum, SESSION_MIC_MINIMUM_NOTE_MAX_MS) = 0 Then Return 0
    If parsedDenominator <> 4 AndAlso parsedDenominator <> 8 AndAlso _
        parsedDenominator <> 16 AndAlso parsedDenominator <> 32 Then Return 0
    If parsedMinimum < SESSION_MIC_MINIMUM_NOTE_MIN_MS Then
        Return 0
    End If
    denominator = CInt(parsedDenominator)
    minimumNoteMilliseconds = CULng(parsedMinimum)
    Return -1
End Function


Private Function session_QuantizeTick( _
    ByVal tick As ULongInt, _
    ByVal gridTicks As ULongInt _
) As ULongInt
    If gridTicks = 0 Then
        Return tick
    End If
    Dim As ULongInt quotient = tick \ gridTicks
    Dim As ULongInt tickRemainder = tick Mod gridTicks
    Dim As ULongInt halfGrid = (gridTicks + 1) \ 2
    If tickRemainder >= halfGrid AndAlso _
        quotient < OSE_MAX_MIDI_TICK \ gridTicks Then quotient += 1
    Dim As ULongInt quantizedTick = quotient * gridTicks
    If quantizedTick > OSE_MAX_MIDI_TICK Then _
        quantizedTick = OSE_MAX_MIDI_TICK
    Return quantizedTick
End Function


Private Function session_QuantizeTickUp( _
    ByVal tick As ULongInt, _
    ByVal gridTicks As ULongInt _
) As ULongInt
    If gridTicks = 0 Then
        Return tick
    End If
    Dim As ULongInt quotient = tick \ gridTicks
    If tick Mod gridTicks <> 0 Then
        If quotient >= OSE_MAX_MIDI_TICK \ gridTicks Then _
            Return OSE_MAX_MIDI_TICK
        quotient += 1
    End If
    Return quotient * gridTicks
End Function


Private Function session_TranscribeMicTake( _
    ByVal filename As String, _
    ByVal captureStartTick As ULongInt, _
    ByVal trackIndex As Integer _
) As Integer
    Dim As Integer denominator
    Dim As ULong minimumNoteMilliseconds
    If session_ReadMicSettings(denominator, minimumNoteMilliseconds) = 0 Then
        session_SetMicState "Take saved, but settings are invalid. Use grid 4/8/16/32 and minimum 40..5000 ms."
        session_SetStatus "Microphone take saved, but transcription settings are invalid."
        Return 0
    End If

    Dim As PitchTranscribeConfig config
    pitchTranscribe_DefaultConfig config
    config.minimumNoteMilliseconds = minimumNoteMilliseconds
    Dim As PitchTranscribeSummary analysis
    If pitchTranscribe_AnalyzeWave(filename, config, analysis) = 0 Then
        session_SetMicState "Take saved. " + analysis.errorText
        session_SetStatus "Microphone transcription failed: " + analysis.errorText
        Return 0
    End If
    If analysis.noteCount <= 0 Then
        session_SetMicState "Take saved, but no stable single-note tones were detected."
        session_SetStatus "No stable monophonic tones were detected."
        Return 0
    End If
    If trackIndex < 0 OrElse trackIndex >= session_Summary.trackCount Then
        session_SetStatus "Microphone transcription lost its destination track."
        Return 0
    End If

    Dim As ULongInt wholeNoteTicks = CULngInt(session_Summary.division) * 4
    Dim As ULongInt gridTicks = wholeNoteTicks \ CULngInt(denominator)
    If gridTicks = 0 Then
        gridTicks = 1
    End If
    Dim As ULongInt placementTick = _
        session_QuantizeTickUp(captureStartTick, gridTicks)
    If placementTick >= OSE_MAX_MIDI_TICK Then
        session_SetStatus "Microphone transcription cannot fit on the MIDI timeline."
        Return 0
    End If
    If session_BeginMidiEdit() = 0 Then
        Return 0
    End If

    Dim As Double captureStartSeconds = midi_TicksToSeconds( _
        session_Summary, captureStartTick)
    Dim As Integer recordChannel = trackIndex Mod SESSION_CHANNEL_COUNT
    Dim As Integer addedCount
    Dim As Integer previousAddedIndex = -1
    Dim As ULongInt previousEndTick = placementTick
    For noteIndex As Integer = 0 To analysis.noteCount - 1
        Dim As PitchTranscribedNote transcribedNote
        If pitchTranscribe_GetNote(noteIndex, transcribedNote) = 0 Then _
            Continue For
        Dim As Double noteStartSeconds = captureStartSeconds + _
            CDbl(transcribedNote.startMilliseconds) / 1000.0
        Dim As Double noteEndSeconds = noteStartSeconds + _
            CDbl(transcribedNote.durationMilliseconds) / 1000.0
        Dim As ULongInt rawStartTick = midi_SecondsToTicks( _
            session_Summary, noteStartSeconds)
        Dim As ULongInt rawEndTick = midi_SecondsToTicks( _
            session_Summary, noteEndSeconds)
        Dim As ULongInt noteStartTick = session_QuantizeTick( _
            rawStartTick, gridTicks)
        Dim As ULongInt noteEndTick = session_QuantizeTick( _
            rawEndTick, gridTicks)
        If noteStartTick < placementTick Then
            noteStartTick = placementTick
        End If
        If noteStartTick < previousEndTick Then
            noteStartTick = previousEndTick
        End If
        If noteEndTick <= noteStartTick Then
            If noteStartTick > OSE_MAX_MIDI_TICK - gridTicks Then
                Exit For
            End If
            noteEndTick = noteStartTick + gridTicks
        End If
        If noteEndTick > OSE_MAX_MIDI_TICK Then
            noteEndTick = OSE_MAX_MIDI_TICK
        End If
        If noteEndTick <= noteStartTick Then
            Exit For
        End If

        ' Adjacent identical estimates are one performed tone after grid
        ' rounding. Extending the previous note avoids an artificial reattack.
        If previousAddedIndex >= 0 Then
            Dim As MidiEditableNote previousNote
            If midi_GetEditableNote(previousAddedIndex, previousNote) <> 0 AndAlso _
                previousNote.keyNumber = transcribedNote.keyNumber AndAlso _
                noteStartTick <= previousNote.startTick + _
                    previousNote.durationTicks Then
                previousNote.durationTicks = noteEndTick - previousNote.startTick
                If midi_SetEditableNote(session_Summary, previousAddedIndex, _
                    previousNote) <> 0 Then
                    previousEndTick = noteEndTick
                    Continue For
                End If
            End If
        End If

        Dim As Integer addedNote = midi_AddEditableNote( _
            session_Summary, trackIndex, noteStartTick, _
            noteEndTick - noteStartTick, transcribedNote.keyNumber, _
            recordChannel, transcribedNote.velocity)
        If addedNote < 0 Then
            Exit For
        End If
        previousAddedIndex = addedNote
        previousEndTick = noteEndTick
        session_SelectedNote = addedNote
        addedCount += 1
    Next

    If addedCount <= 0 Then
        session_CancelMidiEdit()
        session_SetMicState "Take saved, but no quantized notes fit on the timeline."
        session_SetStatus "No transcribed notes fit on the MIDI timeline."
        Return 0
    End If
    If session_CommitMidiEdit() = 0 Then
        Return 0
    End If
    session_Dirty = -1
    session_PlaybackChannelOrderDirty = -1
    session_RefreshTrackList()
    session_SetMicState "Take saved. Added " + Str(addedCount) + _
        " quantized notes to track " + Str(trackIndex + 1) + "."
    session_SetStatus "Microphone transcription added " + Str(addedCount) + _
        " notes on a 1/" + Str(denominator) + " grid."
    Return addedCount
End Function


Public Sub session_FinishMicCapture()
    If session_MicCaptureActive = 0 Then
        Exit Sub
    End If
    Dim As String capturedFilename = session_MicCaptureFilename
    Dim As ULongInt captureStartTick = session_MicCaptureStartTick
    Dim As Integer captureTrack = session_MicCaptureTrack
    Dim As Integer captureResult = CAPTURE SAVE(capturedFilename)
    ' sfxlib must save while capture is active so the backend can pull its
    ' final input block. Stopping first discards that opportunity and can
    ' leave a zero-byte file even though CAPTURE SAVE reports success.
    CAPTURE STOP
    session_MicCaptureActive = 0
    session_MicCaptureFilename = ""
    If captureResult <> 0 Then
        session_SetMicState "The microphone take could not be saved."
        session_SetStatus "Microphone capture could not be saved."
        Exit Sub
    End If
    session_SetMicState "Analyzing the saved microphone take..."
    session_TranscribeMicTake capturedFilename, captureStartTick, captureTrack
End Sub


Private Sub session_CloseMicWindow()
    If session_MicWindow = 0 Then
        Exit Sub
    End If
    If session_MicCaptureActive <> 0 Then
        session_FinishMicCapture()
    End If
    Dim As String windowName = session_MicWindow->name
    gui_RemoveWidget windowName
    gui_ClearModalRoot()
    session_MicWindow = 0
    session_MicQuantizeBox = 0
    session_MicMinimumNoteBox = 0
    session_MicStateLabel = 0
End Sub


Public Sub session_OnMicClose(ByVal source As Widget Ptr)
    If source = 0 Then
        Exit Sub
    End If
End Sub


Public Sub session_OnMicCapture(ByVal source As Widget Ptr)
    If session_MicCaptureActive <> 0 Then
        session_FinishMicCapture()
        Exit Sub
    End If
    If session_MicWindow = 0 Then
        Exit Sub
    End If
    Dim As Integer denominator
    Dim As ULong minimumNoteMilliseconds
    If session_ReadMicSettings(denominator, minimumNoteMilliseconds) = 0 Then
        session_SetStatus "Use grid 4, 8, 16, or 32 and minimum note 40..5000 ms."
        Exit Sub
    End If
    If session_Summary.trackCount <= 0 OrElse session_SelectedTrack < 0 OrElse _
        session_SelectedTrack >= session_Summary.trackCount Then
        session_SetStatus "Add or select a MIDI track before microphone recording."
        Exit Sub
    End If
    If session_AudioCaptureActive <> 0 Then
        session_SetStatus "Stop the WAV clip recorder before microphone transcription."
        Exit Sub
    End If
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    session_StopPlayback()

    Dim As String captureFilename = session_NewMicCaptureFilename()
    If captureFilename = "" Then
        session_SetStatus "No unused microphone-take filename is available."
        Exit Sub
    End If
    If CAPTURE START() <> 0 Then
        session_SetMicState "The default sfxlib microphone/line input is unavailable."
        session_SetStatus "The sfxlib microphone input is unavailable."
        Exit Sub
    End If
    session_MicCaptureFilename = captureFilename
    session_MicCaptureStartTick = session_TimelineDurationTicks()
    session_MicCaptureStartClock = Timer
    session_MicCaptureTrack = session_SelectedTrack
    session_MicCaptureActive = -1
    session_SetMicState "Listening now. Hum or whistle one stable note at a time."
    session_SetStatus "Microphone listening. Press Stop & Transcribe when finished."
End Sub


Public Sub session_OnMic(ByVal source As Widget Ptr)
    If session_MicWindow <> 0 Then
        gui_BringToFront session_MicWindow
        Exit Sub
    End If
    If session_IsModalOpen() <> 0 Then
        session_SetStatus "Close the current modal window first."
        Exit Sub
    End If
    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As Integer windowX = (screenWidth - SESSION_MIC_WINDOW_WIDTH) \ 2
    Dim As Integer windowY = (screenHeight - SESSION_MIC_WINDOW_HEIGHT) \ 2
    If windowX < 0 Then
        windowX = 0
    End If
    If windowY < 0 Then
        windowY = 0
    End If
    session_MicWindow = session_CreateEditorWindow( _
        "microphone_transcription", "Hum / Whistle Transcription", _
        windowX, windowY, SESSION_MIC_WINDOW_WIDTH, SESSION_MIC_WINDOW_HEIGHT)
    If session_MicWindow = 0 Then
        session_SetStatus "Could not create the microphone transcription window."
        Exit Sub
    End If
    gui_AddWidget session_MicWindow
    subwindow_SetCloseHandler session_MicWindow, @session_OnMicClose
    session_MicAddChild session_CreateEditorLabel( _
        "mic_hint_1", _
        "Uses sfxlib's default microphone/line input. Perform one clear note at a time.", _
        14, 34)
    session_MicAddChild session_CreateEditorLabel( _
        "mic_hint_2", _
        "The WAV take is retained beside the project or in your capture folder.", _
        14, 54)
    session_MicAddChild session_CreateEditorLabel( _
        "mic_grid_label", "Quantize grid (1/4, 1/8, 1/16, 1/32)", 14, 88)
    session_MicQuantizeBox = session_CreateEditorTextBox( _
        "mic_grid", "16", 14, 106, 180, 24, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_MicAddChild session_MicQuantizeBox
    session_MicAddChild session_CreateEditorLabel( _
        "mic_minimum_label", "Minimum stable note (milliseconds)", 350, 88)
    session_MicMinimumNoteBox = session_CreateEditorTextBox( _
        "mic_minimum", "90", 350, 106, 180, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_MicAddChild session_MicMinimumNoteBox
    session_MicAddChild button_Create( _
        "mic_capture", "Start Listening / Stop & Transcribe", 14, 152, 254, 30, _
        @session_OnMicCapture)
    session_MicStateLabel = session_CreateEditorLabel( _
        "mic_state", "Ready for a take of up to 120 seconds.", 14, 204)
    session_MicAddChild session_MicStateLabel
    gui_SetModalRoot session_MicWindow
    session_SetStatus "Microphone transcription ready."
End Sub


Private Sub session_ProcessMicWindow()
    If session_MicWindow = 0 Then
        Exit Sub
    End If
    If subwindow_CloseRequested(session_MicWindow) <> 0 Then
        session_CloseMicWindow()
        session_SetStatus "Microphone transcription closed."
        Exit Sub
    End If
    If session_MicCaptureActive = 0 Then
        Exit Sub
    End If
    Dim As Double currentClock = Timer
    Dim As Double elapsedSeconds = currentClock - session_MicCaptureStartClock
    If elapsedSeconds < 0.0 Then
        elapsedSeconds += 86400.0
    End If
    If elapsedSeconds >= SESSION_MIC_MAX_SECONDS Then
        session_FinishMicCapture()
        session_SetStatus "Microphone take reached 120 seconds and was transcribed."
    End If
End Sub

#endif

/' end of src/editor/microphone.bi '/
