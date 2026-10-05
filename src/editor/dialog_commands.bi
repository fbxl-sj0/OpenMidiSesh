/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/dialog_commands.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Route application callbacks and generated dialogs.

    Responsibilities:

        - validate dialog input before committing changes
        - coordinate modal commands with playback and chronological history

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_DIALOG_COMMANDS_BI__
#define __OSE_EDITOR_DIALOG_COMMANDS_BI__


' -------------------------------------------------------------------------
' Application callbacks and dialog routing
' -------------------------------------------------------------------------

Private Sub session_AudioAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_AudioWindow = 0 Then
        Exit Sub
    End If
    gui_AddGeneratedWidget child
    gui_SetParent child, session_AudioWindow
End Sub


Private Function session_NewAudioCaptureFilename() As String
    Return capturePaths_NewFilename( _
        session_CaptureDirectory(), "session-recording", ".wav")
End Function


Public Sub session_FinishAudioCapture()
    If session_AudioCaptureActive = 0 Then
        Exit Sub
    End If

    Dim As String capturedFilename = session_AudioCaptureFilename
    Dim As ULongInt capturedStartTick = session_AudioCaptureStartTick
    Dim As Integer captureResult = CAPTURE SAVE(capturedFilename)
    ' Save before Stop as required by sfxlib's input-capture contract. This
    ' lets backends that do not fill asynchronously provide their final block.
    CAPTURE STOP
    session_AudioCaptureActive = 0
    session_AudioCaptureFilename = ""

    ' CAPTURE commands use native status codes: zero is success.
    If captureResult <> 0 Then
        session_SetStatus "Audio capture could not be saved."
        Exit Sub
    End If
    If session_BeginAudioEdit() = 0 Then
        Exit Sub
    End If

    Dim As Integer clipIndex = audio_AddClip( _
        capturedFilename, capturedStartTick, 1000)
    If clipIndex < 0 Then
        session_CancelAudioEdit()
        session_SetStatus "Captured WAV failed PCM validation."
        Exit Sub
    End If
    If session_CommitAudioEdit() = 0 Then
        Exit Sub
    End If

    session_LoadAudioSamples()
    If session_AudioWindow <> 0 Then
        session_RefreshAudioList()
        session_AudioSelectedIndex = clipIndex
        If session_AudioList->data <> 0 Then
            Dim As ListBoxData Ptr listData = Cast( _
                ListBoxData Ptr, session_AudioList->data)
            listData->selected_index = clipIndex
        End If
        Dim As OseAudioClip capturedClip
        If audio_GetClip(clipIndex, capturedClip) <> 0 Then _
            session_SetAudioFields capturedClip
    End If
    session_Dirty = -1
    session_SetStatus "Captured WAV clip " + Str(clipIndex + 1) + "." + _
        session_AudioAvailabilitySuffix()
End Sub


Private Sub session_CloseAudioWindow()
    If session_AudioWindow = 0 Then
        Exit Sub
    End If
    If session_AudioCaptureActive <> 0 Then
        session_FinishAudioCapture()
    End If
    Dim As String windowName = session_AudioWindow->name
    gui_RemoveWidget windowName
    gui_ClearModalRoot()
    session_AudioWindow = 0
    session_AudioList = 0
    session_AudioTickBox = 0
    session_AudioGainBox = 0
    session_AudioSelectedIndex = -1
End Sub


Public Sub session_OnAudioClose(ByVal source As Widget Ptr)
    ' The manager records close_requested before invoking this callback.
    If source = 0 Then
        Exit Sub
    End If
End Sub


Private Sub session_ProcessAudioWindow()
    If session_AudioWindow = 0 Then
        Exit Sub
    End If
    If subwindow_CloseRequested(session_AudioWindow) = 0 Then
        Exit Sub
    End If
    session_CloseAudioWindow()
    session_SetStatus "Audio clip editor closed."
End Sub


Public Sub session_OnAudio(ByVal source As Widget Ptr)
    If session_AudioWindow <> 0 Then
        gui_BringToFront session_AudioWindow
        Exit Sub
    End If
    If session_FileDialog <> 0 OrElse session_TempoMapWindow <> 0 OrElse _
        session_TrackWindow <> 0 OrElse session_AutomationWindow <> 0 OrElse _
        session_NoteWindow <> 0 Then
        session_SetStatus "Close the current modal window first."
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As Integer windowX = (screenWidth - SESSION_AUDIO_WINDOW_WIDTH) \ 2
    Dim As Integer windowY = (screenHeight - SESSION_AUDIO_WINDOW_HEIGHT) \ 2
    If windowX < 0 Then
        windowX = 0
    End If
    If windowY < 0 Then
        windowY = 0
    End If

    session_AudioWindow = session_CreateEditorWindow( _
        "audio_window", "Audio Clips", windowX, windowY, _
        SESSION_AUDIO_WINDOW_WIDTH, SESSION_AUDIO_WINDOW_HEIGHT)
    If session_AudioWindow = 0 Then
        session_SetStatus "Could not create the audio clip editor."
        Exit Sub
    End If
    gui_AddWidget session_AudioWindow
    subwindow_SetCloseHandler session_AudioWindow, @session_OnAudioClose

    session_AudioList = listbox_Create("audio_list", 10, 28, 700, 194)
    session_AudioAddChild session_AudioList

    Dim As Widget Ptr child
    child = session_CreateEditorLabel("audio_tick_label", "Start tick", 10, 234)
    session_AudioAddChild child
    child = session_CreateEditorLabel("audio_gain_label", "Gain (0..1000)", 250, 234)
    session_AudioAddChild child
    session_AudioTickBox = session_CreateEditorTextBox( _
        "audio_tick", "0", 10, 250, 220, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_AudioAddChild session_AudioTickBox
    session_AudioGainBox = session_CreateEditorTextBox( _
        "audio_gain", "1000", 250, 250, 220, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_AudioAddChild session_AudioGainBox

    child = button_Create("audio_add", "Add WAV", 10, 292, 86, 26, _
        @session_OnAddAudio)
    session_AudioAddChild child
    child = button_Create("audio_apply", "Apply", 104, 292, 78, 26, _
        @session_OnApplyAudio)
    session_AudioAddChild child
    child = button_Create("audio_delete", "Delete", 190, 292, 78, 26, _
        @session_OnDeleteAudio)
    session_AudioAddChild child
    child = button_Create("audio_capture", "Record Mic WAV", 276, 292, 122, 26, _
        @session_OnCaptureAudio)
    session_AudioAddChild child
    child = session_CreateEditorLabel("audio_hint", _
        "Add PCM WAV files or record the default sfxlib microphone; channel 16 is the sample lane.", _
        10, 330)
    session_AudioAddChild child

    session_RefreshAudioList()
    gui_SetModalRoot session_AudioWindow
    session_SetStatus "Audio clip editor open."
End Sub


Public Sub session_OnAddAudio(ByVal source As Widget Ptr)
    If session_AudioWindow = 0 OrElse session_FileDialog <> 0 Then
        Exit Sub
    End If
    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    session_FileDialog = session_CreateEditorOpenDialog( _
        "audio_open_dialog", (screenWidth - 400) \ 2, _
        (screenHeight - 340) \ 2, CurDir)
    If session_FileDialog = 0 Then
        session_SetStatus "Could not create the WAV file dialog."
        Exit Sub
    End If
    session_FileDialogMode = SESSION_DIALOG_AUDIO_ADD
    gui_AddWidget session_FileDialog
    gui_SetModalRoot session_FileDialog
    session_SetStatus "Choose a PCM WAV file."
End Sub


Public Sub session_OnCaptureAudio(ByVal source As Widget Ptr)
    If session_AudioCaptureActive <> 0 Then
        session_FinishAudioCapture()
        Exit Sub
    End If
    If session_AudioWindow = 0 Then
        Exit Sub
    End If
    If session_MicCaptureActive <> 0 Then
        session_SetStatus "Stop microphone transcription before recording a WAV clip."
        Exit Sub
    End If
    If session_LiveRecording <> 0 Then
        session_SetStatus "Stop MIDI recording before capturing audio."
        Exit Sub
    End If

    Dim As String captureFilename = session_NewAudioCaptureFilename()
    If captureFilename = "" Then
        session_SetStatus "No unused WAV filename is available."
        Exit Sub
    End If
    If CAPTURE START() <> 0 Then
        session_SetStatus "The sfxlib audio capture device is unavailable."
        Exit Sub
    End If

    session_AudioCaptureFilename = captureFilename
    session_AudioCaptureStartTick = session_TimelineDurationTicks()
    session_AudioCaptureActive = -1
    session_SetStatus "Microphone WAV capture started. Press Record Mic WAV again to stop."
End Sub


Public Sub session_OnApplyAudio(ByVal source As Widget Ptr)
    Dim As OseAudioClip previousClip
    If session_AudioSelectedIndex < 0 OrElse _
        audio_GetClip(session_AudioSelectedIndex, previousClip) = 0 Then
        session_SetStatus "Audio apply ignored: select a clip first."
        Exit Sub
    End If
    Dim As OseAudioClip clip
    If session_ReadAudioFields(clip) = 0 Then
        session_SetStatus "Audio fields are outside their supported ranges."
        Exit Sub
    End If
    If session_AudioClipFieldsEqual(previousClip, clip) <> 0 Then
        session_SetStatus "Audio clip already has those values."
        Exit Sub
    End If
    session_StopPlayback()
    If session_BeginAudioEdit() = 0 Then
        Exit Sub
    End If
    If audio_SetClip(session_AudioSelectedIndex, clip) = 0 Then
        session_CancelAudioEdit()
        session_SetStatus "Audio clip could not be revalidated."
        Exit Sub
    End If
    If session_CommitAudioEdit() = 0 Then
        Exit Sub
    End If
    session_LoadAudioSamples()
    session_RefreshAudioList()
    session_Dirty = -1
    session_SetStatus "Updated audio clip." + session_AudioAvailabilitySuffix()
End Sub


Public Sub session_OnDeleteAudio(ByVal source As Widget Ptr)
    If session_AudioSelectedIndex < 0 Then
        session_SetStatus "Audio delete ignored: select a clip first."
        Exit Sub
    End If
    session_StopPlayback()
    If session_BeginAudioEdit() = 0 Then
        Exit Sub
    End If
    If audio_RemoveClip(session_AudioSelectedIndex) = 0 Then
        session_CancelAudioEdit()
        session_SetStatus "Audio clip delete failed."
        Exit Sub
    End If
    If session_CommitAudioEdit() = 0 Then
        Exit Sub
    End If
    session_LoadAudioSamples()
    session_AudioSelectedIndex = -1
    session_RefreshAudioList()
    session_Dirty = -1
    session_SetStatus "Deleted audio clip." + session_AudioAvailabilitySuffix()
End Sub


Private Sub session_AutomationAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_AutomationWindow = 0 Then
        Exit Sub
    End If
    gui_AddGeneratedWidget child
    gui_SetParent child, session_AutomationWindow
End Sub


Public Sub session_OnAutomationClose(ByVal source As Widget Ptr)
    ' The manager records close_requested before invoking this callback. The
    ' application loop removes the complete window tree after widget updates.
    If source = 0 Then
        Exit Sub
    End If
End Sub


Public Sub session_OnNotePropertiesClose(ByVal source As Widget Ptr)
    ' The manager records close_requested before invoking this callback. The
    ' application loop removes the complete window tree after widget updates.
    If source = 0 Then
        Exit Sub
    End If
End Sub


Public Sub session_OnAutomation(ByVal source As Widget Ptr)
    If session_Summary.trackCount <= 0 Then
        session_SetStatus "Automation ignored: add or load a MIDI track first."
        Exit Sub
    End If
    If session_AutomationWindow <> 0 Then
        gui_BringToFront session_AutomationWindow
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As Integer windowX = (screenWidth - SESSION_AUTOMATION_WINDOW_WIDTH) \ 2
    Dim As Integer windowY = (screenHeight - SESSION_AUTOMATION_WINDOW_HEIGHT) \ 2
    If windowX < 0 Then
        windowX = 0
    End If
    If windowY < 0 Then
        windowY = 0
    End If

    session_AutomationWindow = session_CreateEditorWindow( _
        "automation_window", "MIDI Channel Events", windowX, windowY, _
        SESSION_AUTOMATION_WINDOW_WIDTH, SESSION_AUTOMATION_WINDOW_HEIGHT)
    If session_AutomationWindow = 0 Then
        session_SetStatus "Could not create the automation editor."
        Exit Sub
    End If
    gui_AddWidget session_AutomationWindow
    subwindow_SetCloseHandler session_AutomationWindow, _
        @session_OnAutomationClose

    session_AutomationList = listbox_Create( _
        "automation_list", 10, 28, 558, 218)
    session_AutomationAddChild session_AutomationList

    Dim As Widget Ptr child
    child = session_CreateEditorLabel("automation_tick_label", "Tick", 10, 251)
    session_AutomationAddChild child
    child = session_CreateEditorLabel("automation_track_label", "Track", 120, 251)
    session_AutomationAddChild child
    child = session_CreateEditorLabel("automation_channel_label", "Channel", 214, 251)
    session_AutomationAddChild child
    child = session_CreateEditorLabel("automation_type_label", "Type", 308, 251)
    session_AutomationAddChild child
    child = session_CreateEditorLabel("automation_data1_label", "Data 1", 402, 251)
    session_AutomationAddChild child
    child = session_CreateEditorLabel("automation_data2_label", "Data 2", 490, 251)
    session_AutomationAddChild child

    session_AutomationTickBox = session_CreateEditorTextBox( _
        "automation_tick", "0", 10, 267, 100, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_AutomationAddChild session_AutomationTickBox
    session_AutomationTrackBox = session_CreateEditorTextBox( _
        "automation_track", Str(session_SelectedTrack + 1), 120, 267, _
        84, 24, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_AutomationAddChild session_AutomationTrackBox
    session_AutomationChannelBox = session_CreateEditorTextBox( _
        "automation_channel", Str((session_SelectedTrack Mod 16) + 1), _
        214, 267, 84, 24, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_AutomationAddChild session_AutomationChannelBox
    session_AutomationTypeBox = session_CreateEditorTextBox( _
        "automation_type", "176", 308, 267, 84, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_AutomationAddChild session_AutomationTypeBox
    session_AutomationData1Box = session_CreateEditorTextBox( _
        "automation_data1", "7", 402, 267, 84, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_AutomationAddChild session_AutomationData1Box
    session_AutomationData2Box = session_CreateEditorTextBox( _
        "automation_data2", "100", 490, 267, 84, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_AutomationAddChild session_AutomationData2Box

    child = button_Create("automation_new", "New", 10, 310, 70, 26, _
        @session_OnAddAutomation)
    session_AutomationAddChild child
    child = button_Create("automation_apply", "Apply", 88, 310, 70, 26, _
        @session_OnApplyAutomation)
    session_AutomationAddChild child
    child = button_Create("automation_delete", "Delete", 166, 310, 70, 26, _
        @session_OnDeleteAutomation)
    session_AutomationAddChild child
    child = session_CreateEditorLabel("automation_hint", _
        "Type: A0..E0 channel event or F1/F2/F3/F6 system-common | data 0..127", _
        10, 350)
    session_AutomationAddChild child

    session_AutomationSelectedSource = -1
    session_AutomationSelectedKind = 0
    session_AutomationEventRefCount = 0
    Dim As MidiChannelEventPoint defaultPoint
    defaultPoint.tick = 0
    defaultPoint.trackIndex = session_SelectedTrack
    defaultPoint.channel = CUByte(session_SelectedTrack Mod 16)
    defaultPoint.messageType = &HB0
    defaultPoint.data1 = 7
    defaultPoint.data2 = 100
    session_SetAutomationFields defaultPoint
    session_RefreshAutomationList()
    gui_SetModalRoot session_AutomationWindow
    session_SetStatus "Controller automation editor open."
End Sub


Public Sub session_OnAddAutomation(ByVal source As Widget Ptr)
    If session_AutomationWindow = 0 Then
        Exit Sub
    End If
    Dim As ULongInt typeValue
    If session_AutomationTypeBox = 0 OrElse _
        numericText_ParseUnsigned( _
            textbox_GetText(session_AutomationTypeBox), typeValue, 255) = 0 Then
        session_SetStatus "MIDI event fields are outside their supported ranges."
        Exit Sub
    End If
    Dim As Integer newSource = -1
    Dim As Integer addedSystemEvent = 0
    If typeValue = &HF1 OrElse typeValue = &HF2 OrElse _
        typeValue = &HF3 OrElse typeValue = &HF6 Then
        Dim As MidiSystemEventPoint systemEvent
        If session_ReadSystemAutomationFields(systemEvent) = 0 Then
            session_SetStatus "System-common event fields are outside their supported ranges."
            Exit Sub
        End If
        If session_BeginMidiEdit() = 0 Then
            Exit Sub
        End If
        newSource = midi_AddSystemEvent( _
            session_Summary, systemEvent.trackIndex, systemEvent.tick, _
            systemEvent.statusByte, systemEvent.data1, systemEvent.data2)
        addedSystemEvent = -1
    Else
        Dim As MidiChannelEventPoint channelEvent
        If session_ReadAutomationFields(channelEvent) = 0 Then
            session_SetStatus "MIDI event fields are outside their supported ranges."
            Exit Sub
        End If
        If session_BeginMidiEdit() = 0 Then
            Exit Sub
        End If
        newSource = midi_AddChannelEvent( _
            session_Summary, channelEvent.trackIndex, channelEvent.tick, _
            channelEvent.channel, channelEvent.messageType, channelEvent.data1, _
            channelEvent.data2)
    End If
    If newSource < 0 Then
        session_CancelMidiEdit()
        session_SetStatus "MIDI event add failed: storage or track limit reached."
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If

    session_AutomationSelectedSource = newSource
    session_AutomationSelectedKind = addedSystemEvent
    session_Dirty = -1
    session_RefreshAutomationList()
    If addedSystemEvent <> 0 Then
        session_SetStatus "Added MIDI system-common event."
    Else
        session_SetStatus "Added MIDI channel event."
    End If
End Sub


Public Sub session_OnApplyAutomation(ByVal source As Widget Ptr)
    If session_AutomationWindow = 0 OrElse _
        session_AutomationSelectedSource < 0 Then
        session_SetStatus "Automation apply ignored: no point is selected."
        Exit Sub
    End If

    If session_AutomationSelectedKind <> 0 Then
        Dim As MidiSystemEventPoint systemEvent
        If session_ReadSystemAutomationFields(systemEvent) = 0 Then
            session_SetStatus "System-common event fields are outside their supported ranges."
            Exit Sub
        End If
        Dim As MidiSystemEventPoint previousSystemEvent
        If session_GetSelectedSystemAutomation(previousSystemEvent) = 0 Then
            session_SetStatus "MIDI event apply failed: event is no longer valid."
            session_RefreshAutomationList()
            Exit Sub
        End If
        If session_SystemAutomationEqual(previousSystemEvent, systemEvent) <> 0 Then
            session_SetStatus "MIDI system-common event already has those values."
            Exit Sub
        End If
        If session_BeginMidiEdit() = 0 Then
            Exit Sub
        End If
        If midi_SetSystemEvent(session_Summary, _
            session_AutomationSelectedSource, systemEvent) = 0 Then
            session_CancelMidiEdit()
            session_SetStatus "MIDI event apply failed: event is no longer valid."
            session_RefreshAutomationList()
            Exit Sub
        End If
        If session_CommitMidiEdit() = 0 Then
            Exit Sub
        End If
        session_Dirty = -1
        session_RefreshAutomationList()
        session_SetStatus "Updated MIDI system-common event."
        Exit Sub
    End If

    Dim As MidiChannelEventPoint channelEvent
    If session_ReadAutomationFields(channelEvent) = 0 Then
        session_SetStatus "MIDI event fields are outside their supported ranges."
        Exit Sub
    End If
    Dim As MidiChannelEventPoint previousChannelEvent
    If session_GetSelectedChannelAutomation(previousChannelEvent) = 0 Then
        session_SetStatus "MIDI event apply failed: event is no longer valid."
        session_RefreshAutomationList()
        Exit Sub
    End If
    If session_ChannelAutomationEqual(previousChannelEvent, channelEvent) <> 0 Then
        session_SetStatus "MIDI channel event already has those values."
        Exit Sub
    End If
    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If
    If midi_SetChannelEvent(session_Summary, _
        session_AutomationSelectedSource, channelEvent) = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "MIDI event apply failed: event is no longer valid."
        session_RefreshAutomationList()
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If

    session_Dirty = -1
    session_RefreshAutomationList()
    session_SetStatus "Updated MIDI channel event."
End Sub


Public Sub session_OnDeleteAutomation(ByVal source As Widget Ptr)
    If session_AutomationWindow = 0 OrElse _
        session_AutomationSelectedSource < 0 Then
        session_SetStatus "MIDI event delete ignored: no event is selected."
        Exit Sub
    End If
    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If
    Dim As Integer removedEvent = 0
    If session_AutomationSelectedKind <> 0 Then
        removedEvent = midi_RemoveSystemEvent(session_Summary, _
            session_AutomationSelectedSource)
    Else
        removedEvent = midi_RemoveChannelEvent(session_Summary, _
            session_AutomationSelectedSource)
    End If
    If removedEvent = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "MIDI event delete failed: event is no longer valid."
        session_RefreshAutomationList()
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If

    session_AutomationSelectedSource = -1
    session_AutomationSelectedKind = 0
    session_Dirty = -1
    session_RefreshAutomationList()
    session_SetStatus "Deleted MIDI event."
End Sub


Private Sub session_CloseAutomationWindow()
    If session_AutomationWindow = 0 Then
        Exit Sub
    End If
    Dim As String windowName = session_AutomationWindow->name
    gui_RemoveWidget windowName
    gui_ClearModalRoot()
    session_AutomationWindow = 0
    session_AutomationList = 0
    session_AutomationTickBox = 0
    session_AutomationTrackBox = 0
    session_AutomationChannelBox = 0
    session_AutomationTypeBox = 0
    session_AutomationData1Box = 0
    session_AutomationData2Box = 0
    session_AutomationSelectedSource = -1
    session_AutomationSelectedKind = 0
    session_AutomationEventRefCount = 0
End Sub


Private Sub session_ProcessAutomationWindow()
    If session_AutomationWindow = 0 Then
        Exit Sub
    End If
    If subwindow_CloseRequested(session_AutomationWindow) = 0 Then
        Exit Sub
    End If

    session_CloseAutomationWindow()
    session_SetStatus "MIDI event editor closed."
End Sub


Private Sub session_CloseNoteWindow()
    If session_NoteWindow = 0 Then
        Exit Sub
    End If

    Dim As String windowName = session_NoteWindow->name
    gui_RemoveWidget windowName
    gui_ClearModalRoot()
    session_NoteWindow = 0
    session_NoteTickBox = 0
    session_NoteDurationBox = 0
    session_NoteTrackBox = 0
    session_NoteChannelBox = 0
    session_NotePitchBox = 0
    session_NoteVelocityBox = 0
End Sub


Private Sub session_ProcessNoteWindow()
    If session_NoteWindow = 0 Then
        Exit Sub
    End If
    If subwindow_CloseRequested(session_NoteWindow) = 0 Then
        Exit Sub
    End If

    session_CloseNoteWindow()
    session_SetStatus "Note properties closed."
End Sub


Public Sub session_OnNoteProperties(ByVal source As Widget Ptr)
    If session_SelectedNote < 0 Then
        session_SetStatus "Note properties ignored: select a note first."
        Exit Sub
    End If
    If session_NoteWindow <> 0 Then
        gui_BringToFront session_NoteWindow
        Exit Sub
    End If
    If session_AutomationWindow <> 0 OrElse session_FileDialog <> 0 Then
        session_SetStatus "Close the current modal window first."
        Exit Sub
    End If

    Dim As MidiEditableNote editableNote
    If midi_GetEditableNote(session_SelectedNote, editableNote) = 0 Then
        session_SetStatus "Note properties ignored: selected note is no longer valid."
        session_ClearNoteSelection()
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As Integer windowX = (screenWidth - SESSION_NOTE_WINDOW_WIDTH) \ 2
    Dim As Integer windowY = (screenHeight - SESSION_NOTE_WINDOW_HEIGHT) \ 2
    If windowX < 0 Then
        windowX = 0
    End If
    If windowY < 0 Then
        windowY = 0
    End If

    session_NoteWindow = session_CreateEditorWindow( _
        "note_properties_window", "Note Properties", windowX, windowY, _
        SESSION_NOTE_WINDOW_WIDTH, SESSION_NOTE_WINDOW_HEIGHT)
    If session_NoteWindow = 0 Then
        session_SetStatus "Could not create the note properties editor."
        Exit Sub
    End If
    gui_AddWidget session_NoteWindow
    subwindow_SetCloseHandler session_NoteWindow, @session_OnNotePropertiesClose

    Dim As Widget Ptr child
    child = session_CreateEditorLabel("note_tick_label", "Start tick", 10, 28)
    session_NoteAddChild child
    child = session_CreateEditorLabel("note_duration_label", "Duration", 260, 28)
    session_NoteAddChild child
    child = session_CreateEditorLabel("note_track_label", "Track", 10, 84)
    session_NoteAddChild child
    child = session_CreateEditorLabel("note_channel_label", "Channel", 260, 84)
    session_NoteAddChild child
    child = session_CreateEditorLabel("note_pitch_label", "Pitch", 10, 140)
    session_NoteAddChild child
    child = session_CreateEditorLabel("note_velocity_label", "Velocity", 260, 140)
    session_NoteAddChild child

    session_NoteTickBox = session_CreateEditorTextBox( _
        "note_tick", "0", 10, 44, 220, 24, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_NoteAddChild session_NoteTickBox
    session_NoteDurationBox = session_CreateEditorTextBox( _
        "note_duration", "1", 260, 44, 220, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_NoteAddChild session_NoteDurationBox
    session_NoteTrackBox = session_CreateEditorTextBox( _
        "note_track", "1", 10, 100, 220, 24, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_NoteAddChild session_NoteTrackBox
    session_NoteChannelBox = session_CreateEditorTextBox( _
        "note_channel", "1", 260, 100, 220, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_NoteAddChild session_NoteChannelBox
    session_NotePitchBox = session_CreateEditorTextBox( _
        "note_pitch", "60", 10, 156, 220, 24, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_NoteAddChild session_NotePitchBox
    session_NoteVelocityBox = session_CreateEditorTextBox( _
        "note_velocity", "100", 260, 156, 220, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_NoteAddChild session_NoteVelocityBox

    child = button_Create("note_apply", "Apply", 10, 200, 78, 26, _
        @session_OnApplyNoteProperties)
    session_NoteAddChild child
    child = button_Create("note_delete", "Delete", 98, 200, 78, 26, _
        @session_OnDeleteNoteProperties)
    session_NoteAddChild child
    child = session_CreateEditorLabel("note_hint", _
        "Tick/duration 0..268435455 | track/channel 1-based | pitch 0..127", _
        10, 238)
    session_NoteAddChild child

    session_SetNoteFields editableNote
    gui_SetModalRoot session_NoteWindow
    session_SetStatus "Editing note " + Str(session_SelectedNote + 1) + "."
End Sub


Public Sub session_OnApplyNoteProperties(ByVal source As Widget Ptr)
    If session_NoteWindow = 0 OrElse session_SelectedNote < 0 Then
        Exit Sub
    End If

    Dim As MidiEditableNote editableNote
    If session_ReadNoteFields(editableNote) = 0 Then
        session_SetStatus "Note fields are outside their supported ranges."
        Exit Sub
    End If
    Dim As MidiEditableNote previousNote
    If midi_GetEditableNote(session_SelectedNote, previousNote) = 0 Then
        session_SetStatus "Note properties could not be read."
        Exit Sub
    End If
    If previousNote.startTick = editableNote.startTick AndAlso _
        previousNote.durationTicks = editableNote.durationTicks AndAlso _
        previousNote.trackIndex = editableNote.trackIndex AndAlso _
        previousNote.channel = editableNote.channel AndAlso _
        previousNote.keyNumber = editableNote.keyNumber AndAlso _
        previousNote.velocity = editableNote.velocity Then
        session_SetStatus "Note already has those values."
        Exit Sub
    End If
    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If
    If midi_SetEditableNote(session_Summary, session_SelectedNote, _
        editableNote) = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Note properties could not be stored."
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If

    session_SelectedTrack = editableNote.trackIndex
    If session_TrackList <> 0 AndAlso session_TrackList->data <> 0 Then
        Dim As ListBoxData Ptr trackData = Cast( _
            ListBoxData Ptr, session_TrackList->data)
        If editableNote.trackIndex < trackData->item_count Then
            trackData->selected_index = editableNote.trackIndex
        End If
    End If
    session_Dirty = -1
    session_SetStatus "Updated note properties."
End Sub


Public Sub session_OnDeleteNoteProperties(ByVal source As Widget Ptr)
    If session_NoteWindow = 0 OrElse session_SelectedNote < 0 Then
        Exit Sub
    End If
    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If
    If midi_RemoveEditableNote(session_Summary, session_SelectedNote) = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Note delete failed: selected note is no longer valid."
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If

    session_ClearNoteSelection()
    session_ScoreDragNote = -1
    session_Dirty = -1
    session_CloseNoteWindow()
    session_SetStatus "Deleted selected note."
End Sub


Public Sub session_OnTempoMapClose(ByVal source As Widget Ptr)
    ' The manager records close_requested before invoking this callback. The
    ' application loop removes the complete window tree after widget updates.
    If source = 0 Then
        Exit Sub
    End If
End Sub


Private Sub session_CloseTempoMapWindow()
    If session_TempoMapWindow = 0 Then
        Exit Sub
    End If

    Dim As String windowName = session_TempoMapWindow->name
    gui_RemoveWidget windowName
    gui_ClearModalRoot()
    session_TempoMapWindow = 0
    session_TempoMapList = 0
    session_TempoMapTickValueLabel = 0
    session_TempoMapBpmBox = 0
    session_TempoMapNumeratorBox = 0
    session_TempoMapDenominatorBox = 0
    session_TempoMapKeyBox = 0
    session_TempoMapMinorBox = 0
    session_TempoMapSelectedIndex = -1
End Sub


Private Sub session_ProcessTempoMapWindow()
    If session_TempoMapWindow = 0 Then
        Exit Sub
    End If
    If subwindow_CloseRequested(session_TempoMapWindow) = 0 Then
        Exit Sub
    End If

    session_CloseTempoMapWindow()
    session_SetStatus "Tempo map closed."
End Sub


Public Sub session_OnTempoMap(ByVal source As Widget Ptr)
    If session_Summary.trackCount <= 0 OrElse _
        session_Summary.tempoCount <= 0 Then
        session_SetStatus "Tempo map ignored: load or create a MIDI track first."
        Exit Sub
    End If
    If session_TempoMapWindow <> 0 Then
        gui_BringToFront session_TempoMapWindow
        Exit Sub
    End If
    If session_AutomationWindow <> 0 OrElse session_NoteWindow <> 0 OrElse _
        session_FileDialog <> 0 Then
        session_SetStatus "Close the current modal window first."
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As Integer windowX = (screenWidth - SESSION_TEMPO_MAP_WINDOW_WIDTH) \ 2
    Dim As Integer windowY = (screenHeight - SESSION_TEMPO_MAP_WINDOW_HEIGHT) \ 2
    If windowX < 0 Then
        windowX = 0
    End If
    If windowY < 0 Then
        windowY = 0
    End If

    session_TempoMapWindow = session_CreateEditorWindow( _
        "tempo_map_window", "Tempo Map", windowX, windowY, _
        SESSION_TEMPO_MAP_WINDOW_WIDTH, SESSION_TEMPO_MAP_WINDOW_HEIGHT)
    If session_TempoMapWindow = 0 Then
        session_SetStatus "Could not create the tempo map editor."
        Exit Sub
    End If
    gui_AddWidget session_TempoMapWindow
    subwindow_SetCloseHandler session_TempoMapWindow, @session_OnTempoMapClose

    session_TempoMapList = listbox_Create("tempo_map_list", 10, 28, 480, 218)
    session_TempoMapAddChild session_TempoMapList

    Dim As Widget Ptr child
    child = session_CreateEditorLabel("tempo_map_tick_label", "Tick", 10, 252)
    session_TempoMapAddChild child
    session_TempoMapTickValueLabel = session_CreateEditorTextBox( _
        "tempo_map_tick_value", "0", 48, 247, 220, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_TempoMapAddChild session_TempoMapTickValueLabel
    child = session_CreateEditorLabel("tempo_map_bpm_label", "BPM", 300, 252)
    session_TempoMapAddChild child
    session_TempoMapBpmBox = session_CreateEditorTextBox( _
        "tempo_map_bpm", "120", 340, 247, 140, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_TempoMapAddChild session_TempoMapBpmBox

    child = session_CreateEditorLabel("tempo_map_meter_label", "Meter", 10, 290)
    session_TempoMapAddChild child
    session_TempoMapNumeratorBox = session_CreateEditorTextBox( _
        "tempo_map_numerator", "4", 58, 285, 84, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_TempoMapAddChild session_TempoMapNumeratorBox
    child = session_CreateEditorLabel("tempo_map_separator_label", "/", 150, 290)
    session_TempoMapAddChild child
    session_TempoMapDenominatorBox = session_CreateEditorTextBox( _
        "tempo_map_denominator", "4", 166, 285, 84, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_TempoMapAddChild session_TempoMapDenominatorBox
    child = session_CreateEditorLabel("tempo_map_key_label", "Key", 270, 290)
    session_TempoMapAddChild child
    session_TempoMapKeyBox = session_CreateEditorTextBox( _
        "tempo_map_key", "0", 304, 285, 64, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_TempoMapAddChild session_TempoMapKeyBox
    child = session_CreateEditorLabel("tempo_map_minor_label", "m", 376, 290)
    session_TempoMapAddChild child
    session_TempoMapMinorBox = session_CreateEditorTextBox( _
        "tempo_map_minor", "0", 394, 285, 86, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_TempoMapAddChild session_TempoMapMinorBox

    child = button_Create("tempo_map_apply", "Apply", 10, 330, 78, 26, _
        @session_OnApplyTempoMap)
    session_TempoMapAddChild child
    child = button_Create("tempo_map_new", "New", 98, 330, 78, 26, _
        @session_OnAddTempoMap)
    session_TempoMapAddChild child
    child = button_Create("tempo_map_delete", "Delete", 186, 330, 78, 26, _
        @session_OnDeleteTempoMap)
    session_TempoMapAddChild child
    child = session_CreateEditorLabel("tempo_map_hint", _
        "Key -7..7 sharps/flats | minor 0=major, 1=minor", _
        10, 365)
    session_TempoMapAddChild child

    session_TempoMapSelectedIndex = 0
    session_RefreshTempoMapList()
    gui_SetModalRoot session_TempoMapWindow
    session_SetStatus "Tempo map editor open."
End Sub


Public Sub session_OnApplyTempoMap(ByVal source As Widget Ptr)
    If session_TempoMapWindow = 0 OrElse _
        session_TempoMapSelectedIndex < 0 Then Exit Sub

    Dim As ULongInt ignoredTick
    Dim As Integer beatsPerMinute
    Dim As Integer numerator
    Dim As Integer denominatorPower
    Dim As Integer sharpsFlats
    Dim As Integer minor
    If session_ReadTempoMapFields(ignoredTick, beatsPerMinute, _
        numerator, denominatorPower, sharpsFlats, minor) = 0 Then
        session_SetStatus "Tempo and meter fields are outside their supported ranges."
        Exit Sub
    End If

    Dim As ULongInt targetTick = session_Summary.tempoMap( _
        session_TempoMapSelectedIndex).tick
    Dim As Integer signatureIndex = session_TimeSignatureIndexExactForTick( _
        targetTick)
    Dim As Integer effectiveSignatureIndex = session_TimeSignatureIndexForTick( _
        targetTick)
    Dim As Integer keyIndex = session_KeySignatureIndexExactForTick(targetTick)
    Dim As Integer effectiveKeyIndex = session_KeySignatureIndexForTick(targetTick)
    If session_TempoPointBpm(session_TempoMapSelectedIndex) = beatsPerMinute _
        AndAlso effectiveSignatureIndex >= 0 AndAlso _
        session_Summary.timeSignatureMap(effectiveSignatureIndex).numerator = _
            numerator AndAlso _
        session_Summary.timeSignatureMap( _
            effectiveSignatureIndex).denominatorPower = denominatorPower _
        AndAlso effectiveKeyIndex >= 0 AndAlso _
        session_Summary.keySignatureMap(effectiveKeyIndex).sharpsFlats = _
            sharpsFlats AndAlso _
        session_Summary.keySignatureMap(effectiveKeyIndex).minor = minor Then
        session_SetStatus "Tempo map point already has those values."
        Exit Sub
    End If
    If session_RequireStoppedTiming() = 0 Then
        session_SetTempoMapFields session_TempoMapSelectedIndex
        Exit Sub
    End If
    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If
    If signatureIndex >= 0 Then
        If midi_SetTimeSignaturePoint(session_Summary, signatureIndex, _
            numerator, denominatorPower) = 0 Then
            session_CancelMidiEdit()
            session_SetStatus "Time signature could not be stored."
            Exit Sub
        End If
    Else
        signatureIndex = midi_AddTimeSignaturePoint(session_Summary, 0, _
            targetTick, numerator, denominatorPower)
        If signatureIndex < 0 Then
            session_CancelMidiEdit()
            session_SetStatus "Time signature could not be stored."
            Exit Sub
        End If
    End If
    If keyIndex >= 0 Then
        If midi_SetKeySignaturePoint(session_Summary, keyIndex, _
            sharpsFlats, minor) = 0 Then
            session_CancelMidiEdit()
            session_SetStatus "Key signature could not be stored."
            Exit Sub
        End If
    Else
        keyIndex = midi_AddKeySignaturePoint(session_Summary, 0, targetTick, _
            sharpsFlats, minor)
        If keyIndex < 0 Then
            session_CancelMidiEdit()
            session_SetStatus "Key signature could not be stored."
            Exit Sub
        End If
    End If
    If midi_SetTempoPointBpm(session_Summary, _
        session_TempoMapSelectedIndex, beatsPerMinute) = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Tempo point could not be stored."
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If

    session_Dirty = -1
    session_RefreshTempoMapList()
    If session_TempoMapSelectedIndex = 0 Then
        session_RefreshTempoBox()
    End If
    session_SetStatus "Updated tempo map point."
End Sub


Public Sub session_OnAddTempoMap(ByVal source As Widget Ptr)
    If session_TempoMapWindow = 0 Then
        Exit Sub
    End If

    Dim As ULongInt targetTick
    Dim As Integer beatsPerMinute
    Dim As Integer numerator
    Dim As Integer denominatorPower
    Dim As Integer sharpsFlats
    Dim As Integer minor
    If session_ReadTempoMapFields(targetTick, beatsPerMinute, _
        numerator, denominatorPower, sharpsFlats, minor) = 0 Then
        session_SetStatus "Tempo and meter fields are outside their supported ranges."
        Exit Sub
    End If

    If session_TempoIndexExactForTick(targetTick) >= 0 Then
        session_SetStatus "A tempo point already exists at that tick."
        Exit Sub
    End If
    If session_RequireStoppedTiming() = 0 Then
        session_SetTempoMapFields session_TempoMapSelectedIndex
        Exit Sub
    End If
    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If

    Dim As Integer tempoIndex = midi_AddTempoPointBpm(session_Summary, 0, _
        targetTick, beatsPerMinute)
    If tempoIndex < 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Tempo point could not be added."
        Exit Sub
    End If

    Dim As Integer signatureIndex = session_TimeSignatureIndexExactForTick( _
        targetTick)
    If signatureIndex >= 0 Then
        If midi_SetTimeSignaturePoint(session_Summary, signatureIndex, _
            numerator, denominatorPower) = 0 Then signatureIndex = -1
    Else
        signatureIndex = midi_AddTimeSignaturePoint( _
            session_Summary, 0, targetTick, numerator, denominatorPower)
    End If
    If signatureIndex < 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Time signature could not be added; edit rolled back."
        Exit Sub
    End If

    Dim As Integer keyIndex = session_KeySignatureIndexExactForTick(targetTick)
    If keyIndex >= 0 Then
        If midi_SetKeySignaturePoint(session_Summary, keyIndex, _
            sharpsFlats, minor) = 0 Then keyIndex = -1
    Else
        keyIndex = midi_AddKeySignaturePoint(session_Summary, 0, targetTick, _
            sharpsFlats, minor)
    End If
    If keyIndex < 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Key signature could not be added; edit rolled back."
        Exit Sub
    End If

    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If

    session_TempoMapSelectedIndex = tempoIndex
    session_Dirty = -1
    session_RefreshTempoMapList()
    If tempoIndex >= 0 AndAlso tempoIndex < session_Summary.tempoCount Then
        session_TempoMapSelectedIndex = tempoIndex
        session_SetTempoMapFields tempoIndex
    End If
    session_SetStatus "Added tempo and meter point at tick " + Str(targetTick) + "."
End Sub


Public Sub session_OnDeleteTempoMap(ByVal source As Widget Ptr)
    If session_TempoMapWindow = 0 OrElse _
        session_TempoMapSelectedIndex <= 0 Then
        session_SetStatus "The initial tempo point cannot be deleted."
        Exit Sub
    End If
    If session_RequireStoppedTiming() = 0 Then
        session_SetTempoMapFields session_TempoMapSelectedIndex
        Exit Sub
    End If

    Dim As ULongInt targetTick = session_Summary.tempoMap( _
        session_TempoMapSelectedIndex).tick
    Dim As Integer signatureIndex = session_TimeSignatureIndexExactForTick( _
        targetTick)
    Dim As Integer keyIndex = session_KeySignatureIndexExactForTick(targetTick)
    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If

    If midi_RemoveTempoPoint(session_Summary, _
        session_TempoMapSelectedIndex) = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Tempo point could not be deleted."
        Exit Sub
    End If
    If signatureIndex > 0 AndAlso _
        midi_RemoveTimeSignaturePoint(session_Summary, signatureIndex) = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Tempo-map meter point could not be deleted."
        Exit Sub
    End If
    If keyIndex > 0 AndAlso _
        midi_RemoveKeySignaturePoint(session_Summary, keyIndex) = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Tempo-map key point could not be deleted."
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If

    session_Dirty = -1
    session_RefreshTempoMapList()
    session_SetStatus "Deleted tempo, meter, and key point."
End Sub


Public Sub session_OnTrackPropertiesClose(ByVal source As Widget Ptr)
    ' The manager records close_requested before invoking this callback. The
    ' application loop removes the complete window tree after widget updates.
    If source = 0 Then
        Exit Sub
    End If
End Sub


Private Sub session_CloseTrackPropertiesWindow()
    If session_TrackWindow = 0 Then
        Exit Sub
    End If

    Dim As String windowName = session_TrackWindow->name
    gui_RemoveWidget windowName
    gui_ClearModalRoot()
    session_TrackWindow = 0
    session_TrackNameBox = 0
    session_DocumentTitleBox = 0
    session_CopyrightBox = 0
    session_LyricBox = 0
    session_MarkerBox = 0
    session_QuantizeGridBox = 0
End Sub


Private Sub session_ProcessTrackPropertiesWindow()
    If session_TrackWindow = 0 Then
        Exit Sub
    End If
    If subwindow_CloseRequested(session_TrackWindow) = 0 Then
        Exit Sub
    End If

    session_CloseTrackPropertiesWindow()
    session_SetStatus "Track properties closed."
End Sub


Private Function session_DocumentTextValue(ByVal metaType As Integer) As String
    For textIndex As Integer = 0 To midi_GetTextEventCount() - 1
        Dim As MidiTextEventPoint textEvent
        If midi_GetTextEvent(textIndex, textEvent) = 0 Then
            Continue For
        End If
        If textEvent.metaType = metaType Then
            Return textEvent.textValue
        End If
    Next
    Return ""
End Function


Private Function session_SetDocumentTextValue( _
    ByVal metaType As Integer, _
    ByVal textValue As String _
) As Integer
    Dim As MidiTextEventPoint foundEvent
    Dim As Integer found = 0
    For textIndex As Integer = 0 To midi_GetTextEventCount() - 1
        Dim As MidiTextEventPoint textEvent
        If midi_GetTextEvent(textIndex, textEvent) = 0 Then
            Continue For
        End If
        If textEvent.metaType = metaType Then
            foundEvent = textEvent
            found = -1
            Exit For
        End If
    Next

    If textValue = "" Then
        If found = 0 Then
            Return -1
        End If
        Return midi_RemoveTextEvent(session_Summary, foundEvent.sourceIndex)
    End If

    If found <> 0 Then
        foundEvent.textValue = textValue
        Return midi_SetTextEvent(session_Summary, foundEvent.sourceIndex, _
            foundEvent)
    End If

    If midi_AddTextEvent(session_Summary, 0, 0, metaType, textValue) < 0 Then _
        Return 0
    Return -1
End Function


Public Sub session_OnTrackProperties(ByVal source As Widget Ptr)
    If session_SelectedTrack < 0 OrElse _
        session_SelectedTrack >= session_Summary.trackCount Then
        session_SetStatus "Track properties ignored: select a track first."
        Exit Sub
    End If
    If session_TrackWindow <> 0 Then
        gui_BringToFront session_TrackWindow
        Exit Sub
    End If
    If session_AutomationWindow <> 0 OrElse session_NoteWindow <> 0 OrElse _
        session_TempoMapWindow <> 0 OrElse session_FileDialog <> 0 Then
        session_SetStatus "Close the current modal window first."
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As Integer windowX = (screenWidth - SESSION_TRACK_WINDOW_WIDTH) \ 2
    Dim As Integer windowY = (screenHeight - SESSION_TRACK_WINDOW_HEIGHT) \ 2
    If windowX < 0 Then
        windowX = 0
    End If
    If windowY < 0 Then
        windowY = 0
    End If

    session_TrackWindow = session_CreateEditorWindow( _
        "track_properties_window", "Track Properties", windowX, windowY, _
        SESSION_TRACK_WINDOW_WIDTH, SESSION_TRACK_WINDOW_HEIGHT)
    If session_TrackWindow = 0 Then
        session_SetStatus "Could not create the track properties editor."
        Exit Sub
    End If
    gui_AddWidget session_TrackWindow
    subwindow_SetCloseHandler session_TrackWindow, _
        @session_OnTrackPropertiesClose

    Dim As Widget Ptr child
    child = session_CreateEditorLabel("track_properties_label", "Track name", 12, 32)
    session_TrackPropertiesAddChild child
    session_TrackNameBox = session_CreateEditorTextBox( _
        "track_name", session_Summary.tracks(session_SelectedTrack).name, _
        12, 50, 496, 24, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_TrackPropertiesAddChild session_TrackNameBox

    child = session_CreateEditorLabel("track_properties_title_label", "Document title", 12, 84)
    session_TrackPropertiesAddChild child
    session_DocumentTitleBox = session_CreateEditorTextBox( _
        "document_title", session_DocumentTextValue(&H01), 12, 102, 496, _
        24, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_TrackPropertiesAddChild session_DocumentTitleBox

    child = session_CreateEditorLabel("track_properties_copyright_label", "Copyright", 12, 136)
    session_TrackPropertiesAddChild child
    session_CopyrightBox = session_CreateEditorTextBox( _
        "copyright_text", session_DocumentTextValue(&H02), 12, 154, 496, _
        24, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_TrackPropertiesAddChild session_CopyrightBox

    child = session_CreateEditorLabel("track_properties_lyric_label", "First lyric", 12, 188)
    session_TrackPropertiesAddChild child
    session_LyricBox = session_CreateEditorTextBox( _
        "lyric_text", session_DocumentTextValue(&H05), 12, 206, 496, _
        24, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_TrackPropertiesAddChild session_LyricBox

    child = session_CreateEditorLabel("track_properties_marker_label", "First marker", 12, 240)
    session_TrackPropertiesAddChild child
    session_MarkerBox = session_CreateEditorTextBox( _
        "marker_text", session_DocumentTextValue(&H06), 12, 258, 496, _
        24, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_TrackPropertiesAddChild session_MarkerBox

    child = session_CreateEditorLabel("track_properties_quantize_label", _
        "Quantize grid (ticks)", 12, 290)
    session_TrackPropertiesAddChild child
    Dim As ULongInt defaultGrid = CULngInt(session_Summary.division) \ 4
    If defaultGrid = 0 Then
        defaultGrid = 1
    End If
    session_QuantizeGridBox = session_CreateEditorTextBox( _
        "quantize_grid", Str(defaultGrid), 12, 308, 220, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    session_TrackPropertiesAddChild session_QuantizeGridBox

    child = button_Create("track_properties_apply", "Apply", 12, 342, 78, 26, _
        @session_OnApplyTrackProperties)
    session_TrackPropertiesAddChild child
    child = button_Create("track_properties_quantize", "Quantize", 98, 342, _
        86, 26, @session_OnQuantizeTrack)
    session_TrackPropertiesAddChild child
    child = session_CreateEditorLabel("track_properties_hint", _
        "Track names: 63 characters. Text metadata: 1024 characters.", _
        12, 378)
    session_TrackPropertiesAddChild child
    child = session_CreateEditorLabel("track_properties_empty_hint", _
        "Empty metadata fields remove the stored value.", 12, 398)
    session_TrackPropertiesAddChild child

    gui_SetModalRoot session_TrackWindow
    ' The properties window opens without an editing caret. Tab still moves
    ' into its text fields when the user starts keyboard navigation.
    gui_SetFocus 0
    session_SetStatus "Editing track " + Str(session_SelectedTrack + 1) + "."
End Sub


Public Sub session_OnQuantizeTrack(ByVal source As Widget Ptr)
    If session_TrackWindow = 0 OrElse session_QuantizeGridBox = 0 Then
        Exit Sub
    End If
    If session_SelectedTrack < 0 OrElse _
        session_SelectedTrack >= session_Summary.trackCount Then Exit Sub

    Dim As ULongInt gridTicks
    If numericText_ParseUnsigned( _
        textbox_GetText(session_QuantizeGridBox), gridTicks, _
        OSE_MAX_MIDI_TICK) = 0 OrElse gridTicks = 0 Then
        session_SetStatus "Quantize grid must be between 1 and 268435455 ticks."
        Exit Sub
    End If

    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If
    Dim As Integer changedCount = midi_QuantizeTrack( _
        session_Summary, session_SelectedTrack, gridTicks)
    If changedCount < 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Quantize failed: the track contains invalid note data."
        Exit Sub
    End If
    If changedCount = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Quantize made no changes on track " + _
            Str(session_SelectedTrack + 1) + "."
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If
    session_Dirty = -1
    session_SetStatus "Quantized " + Str(changedCount) + _
        " note starts on track " + Str(session_SelectedTrack + 1) + "."
End Sub


Public Sub session_OnApplyTrackProperties(ByVal source As Widget Ptr)
    If session_TrackWindow = 0 OrElse session_TrackNameBox = 0 OrElse _
        session_DocumentTitleBox = 0 OrElse session_CopyrightBox = 0 OrElse _
        session_LyricBox = 0 OrElse session_MarkerBox = 0 Then Exit Sub
    If session_SelectedTrack < 0 OrElse _
        session_SelectedTrack >= session_Summary.trackCount Then Exit Sub

    Dim As String trackName = Trim(textbox_GetText(session_TrackNameBox))
    Dim As String documentTitle = Trim(textbox_GetText(session_DocumentTitleBox))
    Dim As String copyrightText = Trim(textbox_GetText(session_CopyrightBox))
    Dim As String lyricText = Trim(textbox_GetText(session_LyricBox))
    Dim As String markerText = Trim(textbox_GetText(session_MarkerBox))
    If Len(trackName) > OSE_MAX_TRACK_NAME OrElse _
        Len(documentTitle) > OSE_MAX_TEXT_EVENT_BYTES OrElse _
        Len(copyrightText) > OSE_MAX_TEXT_EVENT_BYTES OrElse _
        Len(lyricText) > OSE_MAX_TEXT_EVENT_BYTES OrElse _
        Len(markerText) > OSE_MAX_TEXT_EVENT_BYTES Then
        session_SetStatus "Document text is outside the supported range."
        Exit Sub
    End If
    If trackName = session_Summary.tracks(session_SelectedTrack).name AndAlso _
        documentTitle = session_DocumentTextValue(&H01) AndAlso _
        copyrightText = session_DocumentTextValue(&H02) AndAlso _
        lyricText = session_DocumentTextValue(&H05) AndAlso _
        markerText = session_DocumentTextValue(&H06) Then
        session_SetStatus "Track and document information are unchanged."
        Exit Sub
    End If

    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If
    If midi_SetTrackName(session_Summary, session_SelectedTrack, trackName) = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Track name is outside the supported range."
        Exit Sub
    End If
    If session_SetDocumentTextValue(&H01, documentTitle) = 0 OrElse _
        session_SetDocumentTextValue(&H02, copyrightText) = 0 OrElse _
        session_SetDocumentTextValue(&H05, lyricText) = 0 OrElse _
        session_SetDocumentTextValue(&H06, markerText) = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Document text could not be stored."
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If

    session_RefreshTrackList()
    session_Dirty = -1
    session_SetStatus "Updated track and document information."
End Sub


Private Sub session_OpenFileDialog()
    If session_FileDialog <> 0 Then
        session_SetStatus "A file dialog is already open."
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    session_FileDialog = session_CreateEditorOpenDialog( _
        "session_open_dialog", _
        (screenWidth - 400) \ 2, _
        (screenHeight - 340) \ 2, _
        CurDir)
    If session_FileDialog = 0 Then
        session_SetStatus "Could not create the Open dialog."
        Exit Sub
    End If
    session_FileDialogMode = SESSION_DIALOG_OPEN
    gui_AddWidget session_FileDialog
    gui_SetModalRoot session_FileDialog
    session_SetStatus "Choose a Standard MIDI file or OpenSesh project."
End Sub


Private Sub session_OpenProjectSaveDialog()
    If session_FileDialog <> 0 Then
        session_SetStatus "A file dialog is already open."
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    session_FileDialog = session_CreateEditorSaveDialog( _
        "project_save_dialog", (screenWidth - 400) \ 2, _
        (screenHeight - 340) \ 2, CurDir, "session-project.ose")
    If session_FileDialog = 0 Then
        session_SetStatus "Could not create the project save dialog."
        Exit Sub
    End If
    session_FileDialogMode = SESSION_DIALOG_PROJECT_SAVE
    gui_AddWidget session_FileDialog
    gui_SetModalRoot session_FileDialog
    session_SetStatus "Choose an OpenSesh project filename."
End Sub


Private Sub session_OpenMidiSaveDialog()
    If session_FileDialog <> 0 Then
        session_SetStatus "A file dialog is already open."
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    session_FileDialog = session_CreateEditorSaveDialog( _
        "midi_save_dialog", (screenWidth - 400) \ 2, _
        (screenHeight - 340) \ 2, CurDir, "session-edited.mid")
    If session_FileDialog = 0 Then
        session_SetStatus "Could not create the MIDI save dialog."
        Exit Sub
    End If
    session_FileDialogMode = SESSION_DIALOG_MIDI_SAVE
    gui_AddWidget session_FileDialog
    gui_SetModalRoot session_FileDialog
    session_SetStatus "Choose a Standard MIDI output filename."
End Sub


Private Sub session_OpenModExportDialog()
    If session_FileDialog <> 0 Then
        session_SetStatus "A file dialog is already open."
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    session_FileDialog = session_CreateEditorSaveDialog( _
        "mod_export_dialog", (screenWidth - 400) \ 2, _
        (screenHeight - 340) \ 2, CurDir, "session-export.mod")
    If session_FileDialog = 0 Then
        session_SetStatus "Could not create the MOD export dialog."
        Exit Sub
    End If
    session_FileDialogMode = SESSION_DIALOG_MOD_EXPORT
    gui_AddWidget session_FileDialog
    gui_SetModalRoot session_FileDialog
    session_SetStatus "Choose a four-channel ProTracker MOD filename."
End Sub


Private Sub session_OpenWavExportDialog()
    If session_FileDialog <> 0 Then
        session_SetStatus "A file dialog is already open."
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    session_FileDialog = session_CreateEditorSaveDialog( _
        "wav_export_dialog", (screenWidth - 400) \ 2, _
        (screenHeight - 340) \ 2, CurDir, "session-export.wav")
    If session_FileDialog = 0 Then
        session_SetStatus "Could not create the WAV export dialog."
        Exit Sub
    End If
    session_FileDialogMode = SESSION_DIALOG_WAV_EXPORT
    gui_AddWidget session_FileDialog
    gui_SetModalRoot session_FileDialog
    session_SetStatus "Choose a WAV filename for the complete playback mix."
End Sub


Public Sub session_OnSoundFont(ByVal source As Widget Ptr)
    If session_FileDialog <> 0 Then
        session_SetStatus "A file dialog is already open."
        Exit Sub
    End If
    If session_WavExport.active <> 0 OrElse session_AudioCaptureActive <> 0 OrElse _
        session_MicCaptureActive <> 0 Then
        session_SetStatus "Finish the active audio operation before changing SoundFonts."
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As String initialDirectory = CurDir
    If session_SoundFontPath <> "" Then
        Dim As Integer separatorPosition = InStrRev(session_SoundFontPath, "/")
        Dim As Integer windowsSeparator = InStrRev(session_SoundFontPath, "\")
        If windowsSeparator > separatorPosition Then
            separatorPosition = windowsSeparator
        End If
        If separatorPosition > 1 Then _
            initialDirectory = Left(session_SoundFontPath, separatorPosition - 1)
    End If
    session_FileDialog = session_CreateEditorOpenDialog( _
        "soundfont_open_dialog", (screenWidth - 400) \ 2, _
        (screenHeight - 340) \ 2, initialDirectory)
    If session_FileDialog = 0 Then
        session_SetStatus "Could not create the SoundFont file dialog."
        Exit Sub
    End If
    session_FileDialogMode = SESSION_DIALOG_SOUNDFONT
    gui_AddWidget session_FileDialog
    gui_SetModalRoot session_FileDialog
    session_SetStatus "Choose a SoundFont 2 (.sf2) bank."
End Sub


Public Sub session_OnUseBuiltInSynth(ByVal source As Widget Ptr)
    If soundfontSynth_IsActive() = 0 AndAlso session_SoundFontPath = "" Then
        session_SetStatus "The built-in software synth is already selected."
        Exit Sub
    End If
    If session_WavExport.active <> 0 OrElse session_AudioCaptureActive <> 0 OrElse _
        session_MicCaptureActive <> 0 Then
        session_SetStatus "Finish the active audio operation before changing synths."
        Exit Sub
    End If
    session_StopPlayback()
    session_StopAllAuditionNotes()
    soundfontSynth_Unload()
    session_SoundFontPath = ""
    session_ConfigureSynth()
    session_UpdateThemeMenuLabels()
    If session_SaveThemePreference() <> 0 Then
        session_SetStatus "Using the built-in software synth."
    Else
        session_SetStatus "Using the built-in synth, but the preference could not be saved."
    End If
End Sub


Private Function session_SaveMidiTo(ByVal midiFilename As String) As Integer
    Dim As String normalizedFilename = session_NormalizeMidiSaveFilename( _
        midiFilename)
    If normalizedFilename = "" Then
        Return 0
    End If

    If midi_SaveDocument(session_Summary, normalizedFilename) = 0 Then
        session_SetStatus "Save failed: " + normalizedFilename
        Return 0
    End If

    session_Filename = normalizedFilename
    session_Dirty = 0
    session_SetStatus "Saved standard MIDI file: " + normalizedFilename
    Return -1
End Function


Private Function session_SaveProjectTo(ByVal projectFilename As String) As Integer
    If projectFilename = "" Then
        Return 0
    End If
    Dim As String midiFilename = session_PathWithExtension( _
        projectFilename, ".mid")
    Dim As String midiData
    If midi_SerializeDocument(session_Summary, midiData) = 0 Then
        session_SetStatus "Project MIDI serialization failed."
        Return 0
    End If
    Dim As String projectData
    If audio_SerializeProject(projectFilename, midiFilename, projectData) = 0 Then
        session_SetStatus "Project container serialization failed."
        Return 0
    End If
    Dim As String transactionError
    If projectTransaction_SavePair(midiFilename, midiData, projectFilename, _
        projectData, transactionError) = 0 Then
        session_SetStatus "Project save failed: " + transactionError
        Return 0
    End If
    session_Filename = midiFilename
    session_ProjectFilename = projectFilename
    session_Dirty = 0
    session_SetStatus "Saved OpenSesh project: " + projectFilename
    Return -1
End Function


Private Function session_SaveModTo(ByVal modFilename As String) As Integer
    Dim As String normalizedFilename = Trim(modFilename)
    If normalizedFilename = "" Then
        Return 0
    End If
    normalizedFilename = session_PathWithExtension(normalizedFilename, ".mod")

    Dim As OseModExportReport exportReport
    If musicExport_SaveMod(session_Summary, normalizedFilename, _
        exportReport) = 0 Then
        session_SetStatus "MOD export failed: " + exportReport.errorText
        Return 0
    End If

    Dim As String reductionText
    Dim As Integer reducedNotes = exportReport.notesDropped + _
        exportReport.notesTruncated
    If reducedNotes > 0 OrElse exportReport.voiceSteals > 0 OrElse _
        exportReport.octaveFoldedNotes > 0 Then
        reductionText = " | reduced " + LTrim(Str(reducedNotes)) + _
            ", steals " + LTrim(Str(exportReport.voiceSteals)) + _
            ", octave-folded " + _
            LTrim(Str(exportReport.octaveFoldedNotes))
    End If
    session_SetStatus "Exported ProTracker MOD: " + normalizedFilename + _
        " | " + LTrim(Str(exportReport.notesWritten)) + " notes, " + _
        LTrim(Str(exportReport.patternCount)) + " patterns" + reductionText
    Return -1
End Function


Private Function session_BeginWavExportTo( _
    ByVal wavFilename As String _
) As Integer
    Dim As String normalizedFilename = Trim(wavFilename)
    If normalizedFilename = "" Then
        Return 0
    End If
    normalizedFilename = session_PathWithExtension(normalizedFilename, ".wav")

    Dim As ULongInt timelineTicks = session_TimelineDurationTicks()
    Dim As Double timelineSeconds = midi_TicksToSeconds( _
        session_Summary, timelineTicks)
    If timelineTicks = 0 OrElse timelineSeconds <= 0.0 Then
        session_SetStatus "WAV export ignored: the project timeline is empty."
        Return 0
    End If

    session_StopPlayback()
    session_StopAllAuditionNotes()
    session_ConfigureSynth()
    session_LoadAudioSamples()

    Dim As String exportError
    If wavExport_Begin(session_WavExport, normalizedFilename, _
        timelineSeconds, exportError) = 0 Then
        session_SetStatus "WAV export failed: " + exportError
        Return 0
    End If

    session_ResetPlaybackChannelState()
    session_PlaybackElapsed = 0.0
    session_PlaybackSpeedScale = 1.0
    session_PlaybackLastTick = 0
    session_PlaybackLastClock = Timer
    session_PlaybackFirstUpdate = -1
    session_Playing = -1
    session_Paused = 0
    session_ApplyMixerState()
    session_WavExportLastPercent = -1
    session_SetStatus "Exporting WAV through sfxlib: 0%" + _
        session_AudioAvailabilitySuffix()
    Return -1
End Function


Private Sub session_BeginDiscardConfirmation(ByVal action As Integer)
    If session_ConfirmDialog <> 0 Then
        gui_BringToFront session_ConfirmDialog
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    session_ConfirmDialog = session_CreateEditorConfirmDialog( _
        "discard_changes", "Unsaved changes", _
        "Discard the current unsaved session changes?", _
        (screenWidth - 400) \ 2, (screenHeight - 150) \ 2, "Discard")
    If session_ConfirmDialog = 0 Then
        session_SetStatus "Could not create the discard confirmation dialog."
        Exit Sub
    End If
    session_ConfirmAction = action
    gui_AddWidget session_ConfirmDialog
    session_SetStatus "Confirm whether to discard unsaved changes."
End Sub


Private Sub session_CloseDiscardConfirmation()
    If session_ConfirmDialog = 0 Then
        Exit Sub
    End If

    Dim As String dialogName = session_ConfirmDialog->name
    gui_RemoveWidget dialogName
    gui_ClearModalRoot()
    session_ConfirmDialog = 0
    session_ConfirmAction = SESSION_CONFIRM_NONE
End Sub


Private Sub session_ApplyConfirmedDiscard(ByVal requestedAction As Integer)
    If requestedAction = SESSION_CONFIRM_NEW Then
        session_CreateNewDocument()
    ElseIf requestedAction = SESSION_CONFIRM_OPEN Then
        session_OpenFileDialog()
    ElseIf requestedAction = SESSION_CONFIRM_QUIT Then
        session_QuitRequested = -1
    End If
End Sub


Private Sub session_ProcessDiscardConfirmation()
    If session_ConfirmDialog = 0 Then
        Exit Sub
    End If
    Dim As Integer resultState = _
        confirmdialog_GetResultState(session_ConfirmDialog)
    If resultState = 0 Then
        Exit Sub
    End If

    Dim As Integer requestedAction = session_ConfirmAction
    session_CloseDiscardConfirmation()

    If resultState < 0 Then
        session_SetStatus "Discard cancelled."
        Exit Sub
    End If
    session_ApplyConfirmedDiscard requestedAction
End Sub


Private Sub session_RequestQuit()
    If session_ConfirmDialog <> 0 Then
        gui_BringToFront session_ConfirmDialog
        session_SetStatus "Confirm the current discard prompt first."
        Exit Sub
    End If
    If session_IsModalOpen() <> 0 Then
        session_SetStatus "Close the current dialog before exiting."
        Exit Sub
    End If

    If session_Dirty <> 0 Then
        session_BeginDiscardConfirmation SESSION_CONFIRM_QUIT
    Else
        session_QuitRequested = -1
    End If
End Sub


Public Sub session_OnNewDocument(ByVal source As Widget Ptr)
    If session_ConfirmDialog <> 0 Then
        session_SetStatus "Confirm the current discard prompt first."
        Exit Sub
    End If
    If session_Dirty <> 0 Then
        session_BeginDiscardConfirmation SESSION_CONFIRM_NEW
    Else
        session_CreateNewDocument()
    End If
End Sub


Public Sub session_OnOpen(ByVal source As Widget Ptr)
    If session_ConfirmDialog <> 0 Then
        session_SetStatus "Confirm the current discard prompt first."
        Exit Sub
    End If
    If session_Dirty <> 0 Then
        session_BeginDiscardConfirmation SESSION_CONFIRM_OPEN
    Else
        session_OpenFileDialog()
    End If
End Sub


Public Sub session_OnPlay(ByVal source As Widget Ptr)
    If session_WavExport.active <> 0 Then
        session_SetStatus "WAV export is already playing the complete mix."
        Exit Sub
    End If
    If session_Summary.trackCount <= 0 Then
        session_SetStatus "Play ignored: add or load a MIDI track first."
        Exit Sub
    End If
    If session_RequireArrangementAudioSpeed() = 0 Then
        Exit Sub
    End If

    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    session_StopPlayback()
    session_StopAllAuditionNotes()
    session_ConfigureSynth()
    session_LoadAudioSamples()
    session_ResetPlaybackChannelState()
    session_PlaybackElapsed = 0.0
    session_PlaybackLastTick = 0
    session_PlaybackLastClock = Timer
    session_PlaybackFirstUpdate = -1
    session_Playing = -1
    session_Paused = 0
    session_ApplyMixerState()
    Dim As String speedDescription
    If session_PlaybackSpeedScale > 1.0 Then _
        speedDescription = " (" + LTrim(Str(session_PlaybackSpeedScale)) + "x)"
    If soundfontSynth_IsActive() <> 0 Then
        session_SetStatus "Playing through SoundFont: " + _
            soundfontSynth_GetName() + speedDescription + _
            session_AudioAvailabilitySuffix()
    Else
        session_SetStatus "Playing through the built-in software synth" + _
            speedDescription + "." + session_AudioAvailabilitySuffix()
    End If
End Sub


Public Sub session_OnPlaySelectedNotes(ByVal source As Widget Ptr)
    If session_WavExport.active <> 0 Then
        session_SetStatus _
            "WAV export is already playing the complete mix."
        Exit Sub
    End If

    session_SynchronizeNoteSelection()
    If session_NoteSelection.count <= 0 Then
        session_SetStatus "Select one or more notes to play."
        Exit Sub
    End If

    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    Dim As Double requestedSpeed = session_PlaybackSpeedScale
    If requestedSpeed < 0.125 OrElse requestedSpeed > 16.0 Then _
        requestedSpeed = 1.0
    session_StopPlayback()
    If selectedNotePlayback_Capture( _
        session_SelectedNotePlayback, session_NoteSelection) = 0 Then
        session_SetStatus _
            "Selected notes could not be prepared for playback."
        Exit Sub
    End If

    session_StopAllAuditionNotes()
    session_ConfigureSynth()
    session_ResetPlaybackChannelState()
    session_PlaybackElapsed = midi_TicksToSeconds( _
        session_Summary, session_SelectedNotePlayback.startTick)
    session_PlaybackSpeedScale = requestedSpeed
    session_PlaybackLastTick = session_SelectedNotePlayback.startTick
    session_PlaybackLastClock = Timer
    session_PlaybackFirstUpdate = -1
    session_SelectedNotePlaybackActive = -1
    session_Playing = -1
    session_Paused = 0
    session_ApplyMixerState()

    Dim As String speedDescription = " at score tempo"
    If Abs(session_PlaybackSpeedScale - 1.0) > 0.000001 Then
        speedDescription += " (" + _
            LTrim(Str(session_PlaybackSpeedScale)) + "x)"
    End If
    If session_SelectedNotePlayback.count = 1 Then
        session_SetStatus "Playing selected note" + speedDescription + "."
    Else
        session_SetStatus "Playing " + _
            LTrim(Str(session_SelectedNotePlayback.count)) + _
            " selected notes" + speedDescription + "."
    End If
End Sub


Private Function session_BeginLiveRecording( _
    ByVal includeMidiInput As Integer _
) As Integer
    If session_Summary.trackCount <= 0 Then
        session_SetStatus "Record ignored: add or load a MIDI track first."
        Return 0
    End If
    If session_Summary.durationTicks >= OSE_MAX_MIDI_TICK Then
        session_SetStatus "Record ignored: the MIDI timeline is full."
        Return 0
    End If
    If session_AudioCaptureActive <> 0 OrElse session_MicCaptureActive <> 0 Then
        session_SetStatus "Stop the active audio capture before recording notes."
        Return 0
    End If

    session_StopPlayback()
    session_StopAllAuditionNotes()
    session_MidiInputAutoOpened = 0
    If includeMidiInput <> 0 AndAlso midiInput_IsOpen() = 0 Then
        Dim As Integer deviceCount = midiInput_GetDeviceCount()
        If deviceCount > 0 Then
            If session_MidiInputDeviceIndex < 0 OrElse _
                session_MidiInputDeviceIndex >= deviceCount Then _
                session_MidiInputDeviceIndex = 0
            If midiInput_Open(session_MidiInputDeviceIndex) <> 0 Then
                session_MidiInputAutoOpened = -1
            End If
        End If
    End If
    If includeMidiInput <> 0 AndAlso midiInput_IsOpen() <> 0 Then _
        midiInput_ClearPending()
    session_LiveRecordingStartTick = session_Summary.durationTicks
    session_LiveRecordingStartClock = Timer
    session_LiveRecordingStartMidiTimestamp = 0
    session_LiveRecordingHasMidiTimestamp = 0
    If includeMidiInput <> 0 AndAlso midiInput_IsOpen() <> 0 Then _
        session_LiveRecordingHasMidiTimestamp = midiInput_GetClockMilliseconds( _
            session_LiveRecordingStartMidiTimestamp)
    session_ResetLiveKeyboardState()
    session_ResetLiveMidiState()
    session_LastMidiInputDroppedCount = midiInput_GetDroppedCount()
    session_LiveRecordingKeyboardOnly = IIf(includeMidiInput = 0, -1, 0)
    session_LiveRecording = -1
    If includeMidiInput <> 0 AndAlso midiInput_IsOpen() <> 0 Then
        session_SetStatus "Live recording with MIDI input on track " + _
            Str(session_SelectedTrack + 1) + ". Press Rec to stop."
    Else
        session_SetStatus "Performance keyboard recording on track " + _
            Str(session_SelectedTrack + 1) + ". Press Record again to stop."
    End If
    Return -1
End Function


Public Sub session_OnLiveRecord(ByVal source As Widget Ptr)
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
        session_SetStatus "Live recording stopped."
        Exit Sub
    End If
    session_BeginLiveRecording -1
End Sub


Private Sub session_MidiInputAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_MidiInputWindow = 0 Then
        Exit Sub
    End If
    gui_AddGeneratedWidget child
    gui_SetParent child, session_MidiInputWindow
End Sub


Private Function session_TestEnvironmentInteger( _
    ByVal variableName As String, _
    ByVal minimumValue As Integer, _
    ByVal maximumValue As Integer, _
    ByVal fallbackValue As Integer _
) As Integer
    If minimumValue < 0 OrElse maximumValue < minimumValue Then _
        Return fallbackValue

    Dim As String valueText = Environ(variableName) ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
    If valueText = "" OrElse valueText <> Trim(valueText) Then _
        Return fallbackValue

    Dim As ULongInt parsedValue
    If numericText_ParseUnsigned( _
        valueText, parsedValue, CULngInt(maximumValue)) = 0 OrElse _
        parsedValue < CULngInt(minimumValue) Then Return fallbackValue
    Return CInt(parsedValue)
End Function


Private Function session_TestEnvironmentFlag( _
    ByVal variableName As String _
) As Integer
    Return IIf(session_TestEnvironmentInteger( _
        variableName, 0, 1, 0) = 1, -1, 0)
End Function


Private Function session_UseVisualDeviceFixtures() As Integer
    ' Device inventories are machine-specific. Framebuffer regression runs
    ' opt into stable representative rows while normal and semantic tests keep
    ' exercising the real platform enumeration paths.
    If Trim(Environ("OSE_TEST_SNAPSHOT")) = "" Then ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
        Return 0
    End If
    Return session_TestEnvironmentFlag("OSE_TEST_VISUAL_DEVICES")
End Function


Private Sub session_RefreshMidiInputList()
    If session_MidiInputList = 0 Then
        Exit Sub
    End If

    listbox_Clear session_MidiInputList
    If session_UseVisualDeviceFixtures() <> 0 Then
        listbox_AddItem session_MidiInputList, _
            "1  Visual regression MIDI input"
        session_MidiInputSelectedIndex = 0
        Dim As ListBoxData Ptr visualListData = Cast( _
            ListBoxData Ptr, session_MidiInputList->data)
        If visualListData <> 0 Then
            visualListData->selected_index = 0
        End If
        Exit Sub
    End If

    Dim As Integer deviceCount = midiInput_GetDeviceCount()
    If deviceCount <= 0 Then
        listbox_AddItem session_MidiInputList, "No Windows MIDI input devices"
        session_MidiInputSelectedIndex = -1
        Exit Sub
    End If

    If session_MidiInputDeviceIndex < 0 OrElse _
        session_MidiInputDeviceIndex >= deviceCount Then _
        session_MidiInputDeviceIndex = 0
    session_MidiInputSelectedIndex = session_MidiInputDeviceIndex

    For deviceIndex As Integer = 0 To deviceCount - 1
        Dim As String deviceName = midiInput_GetDeviceName(deviceIndex)
        If deviceName = "" Then deviceName = "device " + _
            Str(deviceIndex + 1)
        listbox_AddItem session_MidiInputList, _
            Str(deviceIndex + 1) + "  " + deviceName
    Next

    Dim As ListBoxData Ptr listData = Cast( _
        ListBoxData Ptr, session_MidiInputList->data)
    If listData <> 0 AndAlso session_MidiInputSelectedIndex >= 0 AndAlso _
        session_MidiInputSelectedIndex < listData->item_count Then
        listData->selected_index = session_MidiInputSelectedIndex
    End If
End Sub


Private Sub session_CloseMidiInputWindow()
    If session_MidiInputWindow = 0 Then
        Exit Sub
    End If

    Dim As String windowName = session_MidiInputWindow->name
    gui_RemoveWidget windowName
    gui_ClearModalRoot()
    session_MidiInputWindow = 0
    session_MidiInputList = 0
    session_MidiInputSelectedIndex = -1
End Sub


Public Sub session_OnMidiInputWindowClose(ByVal source As Widget Ptr)
    ' The manager records close_requested before invoking this callback. The
    ' application loop removes the complete child tree after widget updates.
    If source = 0 Then
        Exit Sub
    End If
End Sub


Private Sub session_ProcessMidiInputWindow()
    If session_MidiInputWindow = 0 OrElse _
        subwindow_CloseRequested(session_MidiInputWindow) = 0 Then Exit Sub

    session_CloseMidiInputWindow()
    session_SetStatus "MIDI input chooser closed."
End Sub


Public Sub session_OnMidiInputOpenSelected(ByVal source As Widget Ptr)
    If session_MidiInputWindow = 0 OrElse session_LiveRecording <> 0 Then
        Exit Sub
    End If

    Dim As Integer deviceCount = midiInput_GetDeviceCount()
    If deviceCount <= 0 Then
        session_SetStatus "No Windows MIDI input devices are available."
        session_RefreshMidiInputList()
        Exit Sub
    End If

    Dim As Integer selectedIndex = listbox_GetSelectedIndex( _
        session_MidiInputList)
    If selectedIndex < 0 OrElse selectedIndex >= deviceCount Then _
        selectedIndex = session_MidiInputDeviceIndex
    If selectedIndex < 0 OrElse selectedIndex >= deviceCount Then _
        selectedIndex = 0

    If midiInput_IsOpen() <> 0 Then
        midiInput_Close()
    End If
    If midiInput_Open(selectedIndex) = 0 Then
        session_SetStatus "Could not open MIDI input device " + _
            Str(selectedIndex + 1) + "."
        Exit Sub
    End If

    session_MidiInputDeviceIndex = selectedIndex
    session_MidiInputSelectedIndex = selectedIndex
    Dim As String deviceName = midiInput_GetDeviceName(selectedIndex)
    If deviceName = "" Then
        deviceName = "device " + Str(selectedIndex + 1)
    End If
    session_SetStatus "MIDI input ready: " + deviceName + _
        ". Press Rec to record."
End Sub


Public Sub session_OnMidiInputCloseSelected(ByVal source As Widget Ptr)
    If session_MidiInputWindow = 0 Then
        Exit Sub
    End If
    If midiInput_IsOpen() <> 0 Then
        midiInput_Close()
        session_SetStatus "MIDI input closed."
    Else
        session_SetStatus "MIDI input is already closed."
    End If
End Sub


Public Sub session_OnMidiInput(ByVal source As Widget Ptr)
    If session_LiveRecording <> 0 Then
        session_SetStatus "Stop live recording before changing MIDI input."
        Exit Sub
    End If

    If session_MidiInputWindow <> 0 Then
        gui_BringToFront session_MidiInputWindow
        Exit Sub
    End If

    If midiInput_IsOpen() <> 0 Then
        midiInput_Close()
        session_SetStatus "MIDI input closed."
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As Integer windowX = (screenWidth - _
        SESSION_MIDI_INPUT_WINDOW_WIDTH) \ 2
    Dim As Integer windowY = (screenHeight - _
        SESSION_MIDI_INPUT_WINDOW_HEIGHT) \ 2
    If windowX < 0 Then
        windowX = 0
    End If
    If windowY < 0 Then
        windowY = 0
    End If

    session_MidiInputWindow = session_CreateEditorWindow( _
        "midi_input_window", "MIDI Input Devices", windowX, windowY, _
        SESSION_MIDI_INPUT_WINDOW_WIDTH, SESSION_MIDI_INPUT_WINDOW_HEIGHT)
    If session_MidiInputWindow = 0 Then
        session_SetStatus "Could not create the MIDI input chooser."
        Exit Sub
    End If
    gui_AddWidget session_MidiInputWindow
    subwindow_SetCloseHandler session_MidiInputWindow, _
        @session_OnMidiInputWindowClose

    session_MidiInputList = listbox_Create( _
        "midi_input_list", 10, 28, 440, 146)
    session_MidiInputAddChild session_MidiInputList

    Dim As Widget Ptr child
    child = button_Create("midi_input_open", "Open", 10, 184, 78, 26, _
        @session_OnMidiInputOpenSelected)
    session_MidiInputAddChild child
    child = button_Create("midi_input_close", "Close", 96, 184, 78, 26, _
        @session_OnMidiInputCloseSelected)
    session_MidiInputAddChild child
    #if defined(__FB_LINUX__)
        child = session_CreateEditorLabel("midi_input_hint", _
            "Select an ALSA Sequencer source port.", 10, 224)
    #else
        child = session_CreateEditorLabel("midi_input_hint", _
            "Select a WinMM device. sfxlib MIDI is output-only.", 10, 224)
    #endif
    session_MidiInputAddChild child

    session_MidiInputSelectedIndex = session_MidiInputDeviceIndex
    session_RefreshMidiInputList()
    gui_SetModalRoot session_MidiInputWindow
    session_SetStatus "Select a MIDI input device."
End Sub


Private Sub session_MidiOutputAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_MidiOutputWindow = 0 Then
        Exit Sub
    End If
    gui_AddGeneratedWidget child
    gui_SetParent child, session_MidiOutputWindow
End Sub


Private Sub session_RefreshMidiOutputList()
    If session_MidiOutputList = 0 Then
        Exit Sub
    End If

    listbox_Clear session_MidiOutputList
    If session_UseVisualDeviceFixtures() <> 0 Then
        listbox_AddItem session_MidiOutputList, _
            "1  Visual regression MIDI output"
        session_MidiOutputSelectedIndex = 0
        Dim As ListBoxData Ptr visualListData = Cast( _
            ListBoxData Ptr, session_MidiOutputList->data)
        If visualListData <> 0 Then
            visualListData->selected_index = 0
        End If
        Exit Sub
    End If

    Dim As Integer deviceCount = midiOutput_GetDeviceCount()
    If deviceCount <= 0 Then
        listbox_AddItem session_MidiOutputList, _
            "No MIDI output devices"
        session_MidiOutputSelectedIndex = -1
        Exit Sub
    End If

    If session_MidiOutputDeviceIndex < 0 OrElse _
        session_MidiOutputDeviceIndex >= deviceCount Then _
        session_MidiOutputDeviceIndex = 0
    session_MidiOutputSelectedIndex = session_MidiOutputDeviceIndex

    For deviceIndex As Integer = 0 To deviceCount - 1
        Dim As String deviceName = midiOutput_GetDeviceName(deviceIndex)
        If deviceName = "" Then deviceName = "device " + _
            Str(deviceIndex + 1)
        listbox_AddItem session_MidiOutputList, _
            Str(deviceIndex + 1) + "  " + deviceName
    Next

    Dim As ListBoxData Ptr listData = Cast( _
        ListBoxData Ptr, session_MidiOutputList->data)
    If listData <> 0 AndAlso session_MidiOutputSelectedIndex >= 0 AndAlso _
        session_MidiOutputSelectedIndex < listData->item_count Then
        listData->selected_index = session_MidiOutputSelectedIndex
    End If
End Sub


Private Sub session_CloseMidiOutputWindow()
    If session_MidiOutputWindow = 0 Then
        Exit Sub
    End If

    Dim As String windowName = session_MidiOutputWindow->name
    gui_RemoveWidget windowName
    gui_ClearModalRoot()
    session_MidiOutputWindow = 0
    session_MidiOutputList = 0
    session_MidiOutputSelectedIndex = -1
End Sub


Public Sub session_OnMidiOutputWindowClose(ByVal source As Widget Ptr)
    ' The manager records close_requested before invoking this callback. The
    ' application loop removes the complete child tree after widget updates.
    If source = 0 Then
        Exit Sub
    End If
End Sub


Private Sub session_ProcessMidiOutputWindow()
    If session_MidiOutputWindow = 0 OrElse _
        subwindow_CloseRequested(session_MidiOutputWindow) = 0 Then Exit Sub

    session_CloseMidiOutputWindow()
    session_SetStatus "MIDI output chooser closed."
End Sub


Public Sub session_OnMidiOutputOpenSelected(ByVal source As Widget Ptr)
    If session_MidiOutputWindow = 0 OrElse session_LiveRecording <> 0 Then _
        Exit Sub

    Dim As Integer deviceCount = midiOutput_GetDeviceCount()
    If deviceCount <= 0 Then
        session_SetStatus "No MIDI output devices are available."
        session_RefreshMidiOutputList()
        Exit Sub
    End If

    Dim As Integer selectedIndex = listbox_GetSelectedIndex( _
        session_MidiOutputList)
    If selectedIndex < 0 OrElse selectedIndex >= deviceCount Then _
        selectedIndex = session_MidiOutputDeviceIndex
    If selectedIndex < 0 OrElse selectedIndex >= deviceCount Then _
        selectedIndex = 0

    If midiOutput_IsOpen() <> 0 Then
        midiOutput_AllNotesOff()
        midiOutput_Close()
    End If
    If midiOutput_Open(selectedIndex) = 0 Then
        session_MidiOutputOpened = 0
        session_SetStatus "Could not open MIDI output device " + _
            Str(selectedIndex + 1) + "."
        Exit Sub
    End If

    session_MidiOutputDeviceIndex = selectedIndex
    session_MidiOutputSelectedIndex = selectedIndex
    session_MidiOutputOpened = -1
    session_SendMidiOutputSetup()
    If session_Playing <> 0 Then
        session_ResyncMidiOutput()
    End If
    Dim As String deviceName = midiOutput_GetDeviceName(selectedIndex)
    If deviceName = "" Then
        deviceName = "device " + Str(selectedIndex + 1)
    End If
    session_SetStatus "MIDI output ready: " + deviceName + "."
End Sub


Public Sub session_OnMidiOutputCloseSelected(ByVal source As Widget Ptr)
    If session_MidiOutputWindow = 0 Then
        Exit Sub
    End If
    If midiOutput_IsOpen() <> 0 Then
        midiOutput_AllNotesOff()
        midiOutput_Close()
        session_MidiOutputOpened = 0
        session_SetStatus "MIDI output closed."
    Else
        session_SetStatus "MIDI output is already closed."
    End If
End Sub


Public Sub session_OnMidiOutput(ByVal source As Widget Ptr)
    If midiOutput_IsOpen() <> 0 Then
        midiOutput_AllNotesOff()
        midiOutput_Close()
        session_MidiOutputOpened = 0
        session_SetStatus "MIDI output closed."
        Exit Sub
    End If

    If session_MidiOutputWindow <> 0 Then
        gui_BringToFront session_MidiOutputWindow
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As Integer windowX = (screenWidth - _
        SESSION_MIDI_OUTPUT_WINDOW_WIDTH) \ 2
    Dim As Integer windowY = (screenHeight - _
        SESSION_MIDI_OUTPUT_WINDOW_HEIGHT) \ 2
    If windowX < 0 Then
        windowX = 0
    End If
    If windowY < 0 Then
        windowY = 0
    End If

    session_MidiOutputWindow = session_CreateEditorWindow( _
        "midi_output_window", "MIDI Output Devices", windowX, windowY, _
        SESSION_MIDI_OUTPUT_WINDOW_WIDTH, SESSION_MIDI_OUTPUT_WINDOW_HEIGHT)
    If session_MidiOutputWindow = 0 Then
        session_SetStatus "Could not create the MIDI output chooser."
        Exit Sub
    End If
    gui_AddWidget session_MidiOutputWindow
    subwindow_SetCloseHandler session_MidiOutputWindow, _
        @session_OnMidiOutputWindowClose

    session_MidiOutputList = listbox_Create( _
        "midi_output_list", 10, 28, 480, 146)
    session_MidiOutputAddChild session_MidiOutputList

    Dim As Widget Ptr child
    child = button_Create("midi_output_open", "Open", 10, 184, 78, 26, _
        @session_OnMidiOutputOpenSelected)
    session_MidiOutputAddChild child
    child = button_Create("midi_output_close", "Close", 96, 184, 78, 26, _
        @session_OnMidiOutputCloseSelected)
    session_MidiOutputAddChild child
    child = session_CreateEditorLabel("midi_output_hint", _
        "Playback sends through the selected MIDI output.", 10, 224)
    session_MidiOutputAddChild child

    session_MidiOutputSelectedIndex = session_MidiOutputDeviceIndex
    session_RefreshMidiOutputList()
    gui_SetModalRoot session_MidiOutputWindow
    session_SetStatus "Select a MIDI output device."
End Sub


Public Sub session_OnPause(ByVal source As Widget Ptr)
    If session_WavExport.active <> 0 Then
        session_SetStatus "WAV export cannot be paused. Press Stop to cancel it."
        Exit Sub
    End If
    If session_Playing = 0 Then
        session_SetStatus "Pause ignored: playback is not active."
        Exit Sub
    End If

    If session_Paused = 0 Then
        For voiceChannel As Integer = 0 To SESSION_CHANNEL_COUNT - 1
            SFX PAUSE CHANNEL, voiceChannel
        Next
        soundfontSynth_SetPaused -1
        midiOutput_AllNotesOff()
        session_Paused = -1
        If session_SelectedNotePlaybackActive <> 0 Then
            session_SetStatus "Selected-note playback paused."
        Else
            session_SetStatus "Playback paused."
        End If
    Else
        For voiceChannel As Integer = 0 To SESSION_CHANNEL_COUNT - 1
            SFX RESUME CHANNEL, voiceChannel
        Next
        soundfontSynth_SetPaused 0
        session_Paused = 0
        session_PlaybackLastClock = Timer
        session_ResyncMidiOutput()
        If session_SelectedNotePlaybackActive <> 0 Then
            session_SetStatus "Selected-note playback resumed."
        Else
            session_SetStatus "Playback resumed."
        End If
    End If
End Sub


Public Sub session_OnStop(ByVal source As Widget Ptr)
    Dim As Integer cancelledWavExport = session_WavExport.active
    Dim As Integer stoppedSelectedNotes = session_SelectedNotePlaybackActive
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
        session_SetStatus "Live recording stopped."
    End If
    session_StopPlayback()
    session_PlaybackSpeedScale = 1.0
    If cancelledWavExport <> 0 Then
        session_WavExportLastPercent = -1
        session_SetStatus "WAV export cancelled; captured output was discarded."
    ElseIf stoppedSelectedNotes <> 0 Then
        session_SetStatus "Selected-note playback stopped."
    Else
        session_SetStatus "Playback stopped."
    End If
End Sub


Public Sub session_OnRewind(ByVal source As Widget Ptr)
    If session_Playing <> 0 OrElse session_LiveRecording <> 0 Then _
        session_OnStop 0
    session_ViewStartTick = 0
    session_SetStatus "Score returned to the beginning."
End Sub


Public Sub session_OnFastForward(ByVal source As Widget Ptr)
    ' The toolbar button and F4 share this stopped-only speed selection.
    If session_RequireStoppedTiming() = 0 Then
        Exit Sub
    End If
    If session_PlaybackSpeedScale > 1.0 Then
        session_PlaybackSpeedScale = 1.0
        session_SetStatus "Normal playback selected (1x). Press Play."
    Else
        session_PlaybackSpeedScale = 4.0
        session_SetStatus "Fast playback selected (4x). Press Play."
    End If
End Sub


Public Sub session_OnStepRecord(ByVal source As Widget Ptr)
    If session_Summary.trackCount <= 0 Then
        session_SetStatus "Step record ignored: add or load a MIDI track first."
        Exit Sub
    End If
    Dim As Integer channelIndex = session_SelectedTrack
    If channelIndex < 0 Then
        channelIndex = 0
    End If
    If channelIndex >= SESSION_CHANNEL_COUNT Then _
        channelIndex = SESSION_CHANNEL_COUNT - 1
    session_ToggleRecord channelIndex
End Sub


Public Sub session_OnTone(ByVal source As Widget Ptr)
    sound 440, 0.12
    mixerMeter_Trigger session_MixerMeter, 0, 0.75, 0.12
    session_SetStatus "sfxlib tone audition: A4"
End Sub


Public Sub session_OnSave(ByVal source As Widget Ptr)
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    If session_AudioCaptureActive <> 0 Then
        session_FinishAudioCapture()
    End If

    ' A command-line output path remains a useful unattended-build path. An
    ' open OSE project owns its sibling MIDI file, so Save must update both
    ' sides of that project instead of silently writing an unrelated file.
    Dim As String commandLineFilename = Trim(Command(2))
    Dim As Integer saveTarget = documentSave_SelectTarget( _
        session_ProjectFilename, commandLineFilename)
    Select Case saveTarget
    Case OSE_DOCUMENT_SAVE_PROJECT
        session_SaveProjectTo session_ProjectFilename
    Case OSE_DOCUMENT_SAVE_MIDI
        session_SaveMidiTo commandLineFilename
    Case Else
        session_OpenMidiSaveDialog()
    End Select
End Sub


Public Sub session_OnSaveProject(ByVal source As Widget Ptr)
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    If session_AudioCaptureActive <> 0 Then
        session_FinishAudioCapture()
    End If
    Dim As String projectFilename = session_ProjectFilename
    If projectFilename = "" Then
        projectFilename = Trim(Command(3))
    End If
    If projectFilename = "" Then
        session_OpenProjectSaveDialog()
        Exit Sub
    End If
    If session_IsProjectFilename(projectFilename) = 0 Then _
        projectFilename = session_PathWithExtension(projectFilename, ".ose")
    session_SaveProjectTo projectFilename
End Sub


Public Sub session_OnExportMod(ByVal source As Widget Ptr)
    If midi_GetEditableNoteCount() <= 0 Then
        session_SetStatus "MOD export ignored: the score has no notes."
        Exit Sub
    End If
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    If session_AudioCaptureActive <> 0 Then
        session_FinishAudioCapture()
    End If
    If session_MicCaptureActive <> 0 Then
        session_FinishMicCapture()
    End If
    session_StopPlayback()
    session_OpenModExportDialog()
End Sub


Public Sub session_OnExportWav(ByVal source As Widget Ptr)
    If session_WavExport.active <> 0 Then
        session_SetStatus "A WAV export is already in progress. Press Stop to cancel it."
        Exit Sub
    End If
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    If session_AudioCaptureActive <> 0 Then
        session_FinishAudioCapture()
    End If
    If session_MicCaptureActive <> 0 Then
        session_FinishMicCapture()
    End If
    session_StopPlayback()
    session_OpenWavExportDialog()
End Sub


Public Sub session_OnApplyTempo(ByVal source As Widget Ptr)
    If session_TempoBox = 0 Then
        Exit Sub
    End If
    If session_Summary.trackCount <= 0 Then
        session_SetStatus "Tempo ignored: add or load a MIDI track first."
        Exit Sub
    End If

    Dim As ULongInt parsedTempo
    If numericText_ParseUnsigned( _
        textbox_GetText(session_TempoBox), parsedTempo, 400ULL) = 0 OrElse _
        parsedTempo < 20ULL Then
        session_SetStatus "Tempo must be an integer from 20 to 400 BPM."
        Exit Sub
    End If
    Dim As Integer beatsPerMinute = CInt(parsedTempo)

    If beatsPerMinute = session_InitialTempoBpm() Then
        session_SetStatus "Initial tempo is already " + _
            Str(beatsPerMinute) + " BPM."
        Exit Sub
    End If
    If session_RequireStoppedTiming() = 0 Then
        session_RefreshTempoBox()
        Exit Sub
    End If
    session_StopPlayback()
    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If
    If midi_SetInitialTempoBpm(session_Summary, beatsPerMinute) = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Tempo edit could not be stored."
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If

    textbox_SetText session_TempoBox, Str(beatsPerMinute), -1
    session_Dirty = -1
    session_SetStatus "Initial tempo set to " + _
        Str(beatsPerMinute) + " BPM."
End Sub


Public Sub session_OnAddTrack(ByVal source As Widget Ptr)
    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If
    Dim As Integer newTrackIndex = midi_AddTrack(session_Summary)
    If newTrackIndex < 0 Then
        session_CancelMidiEdit()
        session_SetStatus "New track failed: track limit reached."
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If
    If scoreLayout_AddTrack(session_ScoreLayout) <> newTrackIndex Then _
        session_RebuildScoreLayout()

    session_RefreshTrackList()
    session_SelectTrack newTrackIndex
    session_Dirty = -1
    session_SetStatus "Added track " + Str(newTrackIndex + 1) + "."
End Sub


Public Sub session_OnRemoveTrack(ByVal source As Widget Ptr)
    If session_Summary.trackCount <= 0 Then
        session_SetStatus "Track- ignored: no tracks are loaded."
        Exit Sub
    End If

    Dim As Integer removeIndex = session_SelectedTrack
    If removeIndex < 0 OrElse removeIndex >= session_Summary.trackCount Then
        removeIndex = session_Summary.trackCount - 1
    End If
    Dim As Integer removedDisplayIndex = removeIndex + 1
    session_StopPlayback()
    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If
    If midi_RemoveTrack(session_Summary, removeIndex) = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Track- failed: invalid track selection."
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If
    If scoreLayout_RemoveTrack(session_ScoreLayout, removeIndex) = 0 Then _
        session_RebuildScoreLayout()

    session_RefreshTrackList()
    If session_Summary.trackCount > 0 Then
        If removeIndex >= session_Summary.trackCount Then
            removeIndex = session_Summary.trackCount - 1
        End If
        session_SelectTrack removeIndex
    Else
        session_SelectedTrack = 0
        session_SelectedNote = -1
        session_ScoreDragNote = -1
    End If
    session_Dirty = -1
    session_SetStatus "Removed track " + Str(removedDisplayIndex) + "."
End Sub


Public Sub session_OnDeleteNote(ByVal source As Widget Ptr)
    session_DeleteSelectedNotes()
End Sub


Private Sub session_CompleteFileSelection( _
    ByVal dialogMode As Integer, _
    ByVal resultState As Integer, _
    ByVal selectedFile As String _
)
    If resultState < 0 OrElse selectedFile = "" Then
        If dialogMode = SESSION_DIALOG_AUDIO_ADD AndAlso session_AudioWindow <> 0 Then
            gui_SetModalRoot session_AudioWindow
        End If
        session_SetStatus "File selection cancelled."
        Exit Sub
    End If

    If dialogMode = SESSION_DIALOG_PROJECT_SAVE Then
        session_SaveProjectTo selectedFile
        Exit Sub
    End If

    If dialogMode = SESSION_DIALOG_MIDI_SAVE Then
        session_SaveMidiTo selectedFile
        Exit Sub
    End If

    If dialogMode = SESSION_DIALOG_MOD_EXPORT Then
        session_SaveModTo selectedFile
        Exit Sub
    End If

    If dialogMode = SESSION_DIALOG_WAV_EXPORT Then
        session_BeginWavExportTo selectedFile
        Exit Sub
    End If

    If dialogMode = SESSION_DIALOG_SOUNDFONT Then
        If LCase(Right(Trim(selectedFile), 4)) <> ".sf2" Then
            session_SetStatus "SoundFont load failed: choose an .sf2 bank."
            Exit Sub
        End If
        session_StopPlayback()
        session_StopAllAuditionNotes()
        Dim As String soundFontError
        If soundfontSynth_Load(selectedFile, soundFontError) = 0 Then
            session_UpdateThemeMenuLabels()
            session_SetStatus "SoundFont load failed: " + soundFontError
            Exit Sub
        End If
        session_SoundFontPath = selectedFile
        session_UpdateThemeMenuLabels()
        If session_SaveThemePreference() <> 0 Then
            session_SetStatus "Loaded SoundFont: " + _
                soundfontSynth_GetName()
        Else
            session_SetStatus "Loaded SoundFont, but the preference could not be saved: " + _
                soundfontSynth_GetName()
        End If
        Exit Sub
    End If

    If dialogMode = SESSION_DIALOG_AUDIO_ADD Then
        Dim As OseWaveInfo candidateWave
        If audio_InspectWave(selectedFile, candidateWave) = 0 Then
            If session_AudioWindow <> 0 Then
                gui_SetModalRoot session_AudioWindow
            End If
            session_SetStatus "Audio add failed: choose a PCM WAV file."
            Exit Sub
        End If
        If session_BeginAudioEdit() = 0 Then
            If session_AudioWindow <> 0 Then
                gui_SetModalRoot session_AudioWindow
            End If
            Exit Sub
        End If
        Dim As Integer addedClip = audio_AddClip( _
            selectedFile, session_ViewStartTick, 1000)
        If addedClip < 0 Then
            session_CancelAudioEdit()
            If session_AudioWindow <> 0 Then
                gui_SetModalRoot session_AudioWindow
            End If
            session_SetStatus "Audio add failed: choose a PCM WAV file."
            Exit Sub
        End If
        If session_CommitAudioEdit() = 0 Then
            If session_AudioWindow <> 0 Then
                gui_SetModalRoot session_AudioWindow
            End If
            Exit Sub
        End If
        session_LoadAudioSamples()
        Dim As OseAudioClip addedAudioClip
        session_RefreshAudioList()
        session_AudioSelectedIndex = addedClip
        If session_AudioList <> 0 AndAlso session_AudioList->data <> 0 Then
            Dim As ListBoxData Ptr audioData = Cast( _
                ListBoxData Ptr, session_AudioList->data)
            If addedClip < audioData->item_count Then _
                audioData->selected_index = addedClip
        End If
        If audio_GetClip(addedClip, addedAudioClip) <> 0 Then _
            session_SetAudioFields addedAudioClip
        session_Dirty = -1
        If session_AudioWindow <> 0 Then
            gui_SetModalRoot session_AudioWindow
        End If
        session_SetStatus "Added audio clip: " + selectedFile + _
            session_AudioAvailabilitySuffix()
        Exit Sub
    End If

    session_StopPlayback()
    If session_IsProjectFilename(selectedFile) <> 0 Then
        session_LoadProjectFile selectedFile
    ElseIf session_LoadMidi(selectedFile) <> 0 Then
        session_SetStatus "Loaded " + selectedFile
    End If
End Sub


Private Sub session_ProcessFileDialog()
    If session_FileDialog = 0 Then
        Exit Sub
    End If

    Dim As Integer resultState = filedialog_GetResultState(session_FileDialog)
    If resultState = 0 Then
        Exit Sub
    End If

    Dim As String dialogName = session_FileDialog->name
    Dim As String selectedFile = filedialog_GetSelectedFile(session_FileDialog)
    Dim As Integer dialogMode = session_FileDialogMode
    gui_RemoveWidget dialogName
    gui_ClearModalRoot()
    session_FileDialog = 0
    session_FileDialogMode = SESSION_DIALOG_NONE
    session_CompleteFileSelection dialogMode, resultState, selectedFile
End Sub

#endif

/' end of src/editor/dialog_commands.bi '/
