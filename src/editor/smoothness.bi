/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/smoothness.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Measure interactive frame pacing and assemble editor widgets.

    Responsibilities:

        - exercise scrolling, dragging and playback benchmark workloads
        - create the production widget hierarchy used by those workloads

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_SMOOTHNESS_BI__
#define __OSE_EDITOR_SMOOTHNESS_BI__


' -------------------------------------------------------------------------
' Interactive smoothness benchmark
' -------------------------------------------------------------------------

Private Function session_CreateSmoothnessFixture() As Integer
    If session_CreateNewDocument() = 0 Then
        Return 0
    End If

    While session_Summary.trackCount < SESSION_SMOOTHNESS_TRACK_COUNT
        If midi_AddTrack(session_Summary) < 0 Then
            Return 0
        End If
    Wend
    If session_Summary.trackCount <> SESSION_SMOOTHNESS_TRACK_COUNT Then
        Return 0
    End If

    /'
        The fixture keeps all sixteen mixer strips active and extends beyond
        the sixteen-beat score viewport. Every other beat starts one note per
        channel, so playback continuously exercises scheduling, synthesis,
        metering, score drawing, and mixer drawing throughout the timed run.
        Quarter notes leave a full-beat release interval, proving that the
        VU bars animate instead of merely reaching one steady mock level.
    '/
    Dim As MidiEditableNote notes(0 To SESSION_SMOOTHNESS_NOTE_COUNT - 1)
    For noteIndex As Integer = 0 To SESSION_SMOOTHNESS_NOTE_COUNT - 1
        Dim As Integer sequenceIndex = noteIndex \ SESSION_SMOOTHNESS_TRACK_COUNT
        Dim As Integer trackIndex = noteIndex Mod SESSION_SMOOTHNESS_TRACK_COUNT
        notes(noteIndex).startTick = CULngInt(sequenceIndex) * 960
        notes(noteIndex).durationTicks = 480
        notes(noteIndex).keyNumber = CUByte(48 + _
            ((sequenceIndex + trackIndex) Mod 24))
        notes(noteIndex).channel = CUByte(trackIndex)
        notes(noteIndex).velocity = CUByte(48 + _
            ((sequenceIndex * 11 + trackIndex * 3) Mod 80))
        notes(noteIndex).trackIndex = trackIndex
    Next

    If midi_AddEditableNotes( _
        session_Summary, @notes(0), SESSION_SMOOTHNESS_NOTE_COUNT) <> 0 Then _
        Return 0
    If midi_GetEditableNoteCount() <> SESSION_SMOOTHNESS_NOTE_COUNT Then
        Return 0
    End If

    session_ViewStartTick = 0
    session_ScoreFirstVisibleTrack = 0
    session_SelectedTrack = 0
    session_PlaybackChannelOrderDirty = -1
    session_RebuildScoreLayout()
    session_RefreshTrackList()
    session_SelectTrack 0
    documentHistory_Clear session_DocumentHistory
    session_Dirty = 0
    Return -1
End Function


Private Function session_SmoothnessMeterTotal() As Double
    Dim As Double levelTotal = _
        mixerMeter_MasterLeftLevel(session_MixerMeter) + _
        mixerMeter_MasterRightLevel(session_MixerMeter)
    For channelIndex As Integer = 0 To SESSION_CHANNEL_COUNT - 1
        levelTotal += mixerMeter_ChannelLevel(session_MixerMeter, channelIndex)
    Next
    Return levelTotal
End Function


Private Sub session_InjectSmoothnessInput( _
    ByVal modeName As String, _
    ByVal frameIndex As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByRef pointerUpdateCount As Integer _
)
    Dim As Integer pointerX = SESSION_SCORE_LEFT + 40
    Dim As Integer pointerY = SESSION_SCORE_TOP + 40
    Dim As Integer pointerButtons
    Dim As Integer wheelDelta

    input_MockTouchCount 0
    If modeName = "interaction" Then
        Dim As Integer phaseIndex = frameIndex Mod 120
        If phaseIndex < 60 Then
            If session_InteractionMode = OSE_UI_INTERACTION_TOUCH Then
                /'
                    Two opposing finger drags exercise pan. The final twenty
                    frames expand horizontal and vertical contact spans in
                    separate gestures, covering both zoom axes under the same
                    timing gate as real interaction.
                '/
                If phaseIndex < 40 Then
                    Dim As Integer touchPhase = phaseIndex Mod 20
                    If touchPhase < 19 Then
                        pointerY = SESSION_SCORE_TOP + 70
                        If phaseIndex < 20 Then
                            pointerX = 720 - touchPhase * 14
                        Else
                            pointerX = 460 + touchPhase * 14
                        End If
                        input_MockTouch 0, pointerX, pointerY, 1
                        input_MockTouchCount 1
                    End If
                ElseIf phaseIndex < 49 Then
                    Dim As Integer spanGrowth = (phaseIndex - 40) * 8
                    pointerY = SESSION_SCORE_TOP + 70
                    input_MockTouch 0, 620 - (100 + spanGrowth) \ 2, _
                        pointerY - 40, 11
                    input_MockTouch 1, 620 + (100 + spanGrowth) \ 2, _
                        pointerY + 40, 12
                    input_MockTouchCount 2
                ElseIf phaseIndex >= 50 AndAlso phaseIndex < 59 Then
                    Dim As Integer spanGrowth = (phaseIndex - 50) * 8
                    pointerY = SESSION_SCORE_TOP + 100
                    input_MockTouch 0, 560, _
                        pointerY - (80 + spanGrowth) \ 2, 21
                    input_MockTouch 1, 680, _
                        pointerY + (80 + spanGrowth) \ 2, 22
                    input_MockTouchCount 2
                End If
            Else
                ' Twelve-frame sweeps move both double-buffer pages through
                ' distinct score states, then reverse before an endpoint can
                ' hide later input.
                wheelDelta = IIf((phaseIndex Mod 24) < 12, -1, 1) ' fblint: disable-line FBL406 REASON: The Mod operands are nonnegative; the minus sign belongs to a different expression.
            End If
        Else
            Dim As OseMixerControlLayout mixerLayout
            mixerControls_CalculateLayoutForInteraction mixerLayout, _
                screenWidth, screenHeight, session_SelectedTrack, _
                session_InteractionMode
            pointerX = mixerLayout.masterLeft + 31
            pointerY = mixerLayout.faderTop + _
                ((mixerLayout.faderBottom - mixerLayout.faderTop) * _
                (phaseIndex - 60)) \ 59
            ' Release on the final phase so the production drag lifecycle is
            ' exercised repeatedly rather than leaving capture stuck on exit.
            pointerButtons = IIf(phaseIndex < 119, 1, 0)
        End If
    Else
        ' A moving pointer forces ordinary hover hit-testing in idle and
        ' playback runs while staying clear of clickable toolbar controls.
        Dim As Integer sweepWidth = screenWidth - pointerX - 20
        If sweepWidth < 1 Then
            sweepWidth = 1
        End If
        pointerX += frameIndex Mod sweepWidth
    End If

    input_MockMouse pointerX, pointerY, pointerButtons, wheelDelta
    pointerUpdateCount += 1
End Sub


Private Function session_WriteSmoothnessReport( _
    ByVal reportFilename As String, _
    ByVal modeName As String, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByRef metrics As OseUiSmoothnessMetrics, _
    ByVal pointerUpdateCount As Integer, _
    ByVal scoreScrollUpdateCount As Integer, _
    ByVal mixerDragUpdateCount As Integer, _
    ByVal playbackAdvanceCount As Integer, _
    ByVal meterChangeCount As Integer, _
    ByVal fixtureValid As Integer _
) As Integer
    reportFilename = Left(Trim(reportFilename), 4096)
    If reportFilename = "" Then
        Return 0
    End If

    Dim As Integer workloadValid = fixtureValid
    Dim As Integer expectedInputFrames = SESSION_SMOOTHNESS_WARMUP_FRAMES + _
        metrics.frameIntervals.count
    If modeName <> "idle" AndAlso modeName <> "interaction" AndAlso _
        modeName <> "playback" Then workloadValid = 0
    If pointerUpdateCount < expectedInputFrames Then
        workloadValid = 0
    End If
    If modeName = "interaction" Then
        If scoreScrollUpdateCount < metrics.frameIntervals.count \ 4 OrElse _
            mixerDragUpdateCount < metrics.frameIntervals.count \ 4 Then _
            workloadValid = 0
    ElseIf modeName = "playback" Then
        If playbackAdvanceCount < metrics.frameIntervals.count OrElse _
            meterChangeCount < metrics.frameIntervals.count \ 2 Then _
            workloadValid = 0
    End If

    Dim As OseUiSmoothnessResult result
    uiFramePacing_Evaluate metrics, workloadValid, result

    Dim As Integer fileNumber = FreeFile()
    If Open(reportFilename For Output As #fileNumber) <> 0 Then
        Return 0
    End If
    Print #fileNumber, "format=OpenSeshUiSmoothness"
    Print #fileNumber, "version=1"
    Print #fileNumber, "status=" + IIf(result.passed <> 0, "pass", "fail")
    Print #fileNumber, "scenario=" + modeName
    Print #fileNumber, "width=" + LTrim(Str(screenWidth))
    Print #fileNumber, "height=" + LTrim(Str(screenHeight))
    Print #fileNumber, "theme=" + LCase(uiStyle_ThemeName(session_ThemeMode))
    Print #fileNumber, "interaction=" + _
        LCase(uiInteraction_Name(session_InteractionMode))
    Print #fileNumber, "tracks=" + LTrim(Str(session_Summary.trackCount))
    Print #fileNumber, "notes=" + LTrim(Str(midi_GetEditableNoteCount()))
    Print #fileNumber, "samples=" + LTrim(Str(metrics.frameIntervals.count))
    Print #fileNumber, "average_fps=" + LTrim(Str(result.averageFps))
    Print #fileNumber, "interval_p50_ms=" + LTrim(Str(result.intervalP50Ms))
    Print #fileNumber, "interval_p95_ms=" + LTrim(Str(result.intervalP95Ms))
    Print #fileNumber, "interval_p99_ms=" + LTrim(Str(result.intervalP99Ms))
    Print #fileNumber, "interval_max_ms=" + LTrim(Str(result.intervalMaximumMs))
    Print #fileNumber, "work_p95_ms=" + LTrim(Str(result.workP95Ms))
    Print #fileNumber, "input_p95_ms=" + LTrim(Str(result.inputP95Ms))
    Print #fileNumber, "update_p95_ms=" + LTrim(Str( _
        uiFramePacing_Percentile(metrics.updateWork, 95.0)))
    Print #fileNumber, "application_render_p95_ms=" + LTrim(Str( _
        uiFramePacing_Percentile(metrics.applicationRender, 95.0)))
    Print #fileNumber, "widget_render_p95_ms=" + LTrim(Str( _
        uiFramePacing_Percentile(metrics.widgetRender, 95.0)))
    Print #fileNumber, "presentation_p95_ms=" + LTrim(Str( _
        uiFramePacing_Percentile(metrics.presentation, 95.0)))
    Print #fileNumber, "score_render_p95_ms=" + LTrim(Str( _
        uiFramePacing_Percentile(metrics.scoreRender, 95.0)))
    Print #fileNumber, "score_cache_p95_ms=" + LTrim(Str( _
        uiFramePacing_Percentile(metrics.scoreCache, 95.0)))
    Print #fileNumber, "score_base_p95_ms=" + LTrim(Str( _
        uiFramePacing_Percentile(metrics.scoreBase, 95.0)))
    Print #fileNumber, "score_rests_p95_ms=" + LTrim(Str( _
        uiFramePacing_Percentile(metrics.scoreRests, 95.0)))
    Print #fileNumber, "score_notes_p95_ms=" + LTrim(Str( _
        uiFramePacing_Percentile(metrics.scoreNotes, 95.0)))
    Print #fileNumber, "score_tool_render_p95_ms=" + LTrim(Str( _
        uiFramePacing_Percentile(metrics.scoreToolRender, 95.0)))
    Print #fileNumber, "mixer_render_p95_ms=" + LTrim(Str( _
        uiFramePacing_Percentile(metrics.mixerRender, 95.0)))
    Print #fileNumber, "hitches_over_33_34_ms=" + _
        LTrim(Str(result.hitchCount))
    Print #fileNumber, "hitches_over_50_ms=" + _
        LTrim(Str(result.longHitchCount))
    Print #fileNumber, "pointer_updates=" + LTrim(Str(pointerUpdateCount))
    Print #fileNumber, "score_scroll_updates=" + _
        LTrim(Str(scoreScrollUpdateCount))
    Print #fileNumber, "mixer_drag_updates=" + _
        LTrim(Str(mixerDragUpdateCount))
    Print #fileNumber, "playback_advance_frames=" + _
        LTrim(Str(playbackAdvanceCount))
    Print #fileNumber, "meter_change_frames=" + LTrim(Str(meterChangeCount))
    Print #fileNumber, "rejected_samples=" + _
        LTrim(Str(metrics.frameIntervals.rejectedCount + _
        metrics.frameWork.rejectedCount + metrics.inputLatency.rejectedCount + _
        metrics.updateWork.rejectedCount + _
        metrics.applicationRender.rejectedCount + _
        metrics.widgetRender.rejectedCount + _
        metrics.presentation.rejectedCount + metrics.scoreRender.rejectedCount + _
        metrics.scoreCache.rejectedCount + metrics.scoreBase.rejectedCount + _
        metrics.scoreRests.rejectedCount + metrics.scoreNotes.rejectedCount + _
        metrics.scoreToolRender.rejectedCount + _
        metrics.mixerRender.rejectedCount))
    Print #fileNumber, "minimum_fps=" + _
        LTrim(Str(OSE_UI_SMOOTHNESS_MINIMUM_FPS))
    Print #fileNumber, "maximum_interval_p95_ms=" + _
        LTrim(Str(OSE_UI_SMOOTHNESS_INTERVAL_P95_MS))
    Print #fileNumber, "maximum_interval_p99_ms=" + _
        LTrim(Str(OSE_UI_SMOOTHNESS_INTERVAL_P99_MS))
    Print #fileNumber, "maximum_interval_ms=" + _
        LTrim(Str(OSE_UI_SMOOTHNESS_INTERVAL_MAX_MS))
    Print #fileNumber, "maximum_work_p95_ms=" + _
        LTrim(Str(OSE_UI_SMOOTHNESS_WORK_P95_MS))
    Print #fileNumber, "maximum_input_p95_ms=" + _
        LTrim(Str(OSE_UI_SMOOTHNESS_INPUT_P95_MS))
    Print #fileNumber, "maximum_hitches=" + _
        LTrim(Str(OSE_UI_SMOOTHNESS_MAXIMUM_HITCHES))
    Print #fileNumber, "workload_valid=" + _
        IIf(workloadValid <> 0, "yes", "no")
    Close #fileNumber
    Return result.passed
End Function


Private Sub session_CreateWidgets()
    session_AddToolbarTextButton "new", "New", _
        session_InteractionMetrics.fileButtonLeft(0), _
        SESSION_TOOLBAR_TOP + SESSION_TOOLBAR_BUTTON_TOP_INSET, _
        session_InteractionMetrics.fileButtonWidth(0), _
        SESSION_TOOLBAR_BUTTON_HEIGHT, @session_OnNewDocument
    session_AddToolbarTextButton "open", "Open", _
        session_InteractionMetrics.fileButtonLeft(1), _
        SESSION_TOOLBAR_TOP + SESSION_TOOLBAR_BUTTON_TOP_INSET, _
        session_InteractionMetrics.fileButtonWidth(1), _
        SESSION_TOOLBAR_BUTTON_HEIGHT, @session_OnOpen
    session_AddToolbarTextButton "save", "Save", _
        session_InteractionMetrics.fileButtonLeft(2), _
        SESSION_TOOLBAR_TOP + SESSION_TOOLBAR_BUTTON_TOP_INSET, _
        session_InteractionMetrics.fileButtonWidth(2), _
        SESSION_TOOLBAR_BUTTON_HEIGHT, @session_OnSave
    session_AddTransportButton "stop", SESSION_TRANSPORT_STOP_LEFT, _
        SESSION_TRANSPORT_STOP_WIDTH, @session_OnStop
    session_AddTransportButton "pause", SESSION_TRANSPORT_PAUSE_LEFT, _
        SESSION_TRANSPORT_PAUSE_WIDTH, @session_OnPause
    session_AddTransportButton "rewind", SESSION_TRANSPORT_REWIND_LEFT, _
        SESSION_TRANSPORT_REWIND_WIDTH, @session_OnRewind
    session_AddTransportButton "play", SESSION_TRANSPORT_PLAY_LEFT, _
        SESSION_TRANSPORT_PLAY_WIDTH, @session_OnPlay
    session_AddTransportButton "fast_forward", _
        SESSION_TRANSPORT_FAST_FORWARD_LEFT, _
        SESSION_TRANSPORT_FAST_FORWARD_WIDTH, @session_OnFastForward
    session_AddTransportButton "live_record", SESSION_TRANSPORT_RECORD_LEFT, _
        SESSION_TRANSPORT_RECORD_WIDTH, @session_OnLiveRecord
    session_AddTransportButton "step_record", SESSION_TRANSPORT_STEP_LEFT, _
        SESSION_TRANSPORT_STEP_WIDTH, @session_OnStepRecord
    session_TempoLabel = session_CreateEditorLabel("tempo_label", "Tempo", 654, _
        SESSION_TOOLBAR_TOP + 13)
    If session_TempoLabel <> 0 Then
        session_TempoLabel->render = 0
    End If
    gui_AddWidget session_TempoLabel
    session_TempoBox = session_CreateEditorTextBox("tempo", "120", 696, _
        SESSION_TOOLBAR_TOP + 6, 50, 24, 0, 0, _
        TEXTBOX_SCROLLBAR_NONE)
    gui_AddWidget session_TempoBox
    session_ApplyTempoButton = button_Create("apply_tempo", "Set", 750, _
        SESSION_TOOLBAR_TOP + 5, 44, 26, _
        @session_OnApplyTempo)
    If session_ApplyTempoButton <> 0 Then _
        session_ApplyTempoButton->render = @session_RenderToolbarTextButton
    gui_AddWidget session_ApplyTempoButton
    session_TempoMapButton = button_Create("tempo_map", "Map", 798, _
        SESSION_TOOLBAR_TOP + 5, 44, 26, _
        @session_OnTempoMap)
    If session_TempoMapButton <> 0 Then _
        session_TempoMapButton->render = @session_RenderToolbarTextButton
    gui_AddWidget session_TempoMapButton
    session_MidiInputButton = button_Create("midi_input", "MIDI In", 852, _
        SESSION_TOOLBAR_TOP + 5, 62, 26, _
        @session_OnMidiInput)
    If session_MidiInputButton <> 0 Then _
        session_MidiInputButton->render = @session_RenderToolbarTextButton
    gui_AddWidget session_MidiInputButton
    session_MidiOutputButton = button_Create("midi_output", "MIDI Out", 918, _
        SESSION_TOOLBAR_TOP + 5, 66, 26, _
        @session_OnMidiOutput)
    If session_MidiOutputButton <> 0 Then _
        session_MidiOutputButton->render = @session_RenderToolbarTextButton
    gui_AddWidget session_MidiOutputButton

    session_StatusLabel = session_CreateEditorLabel("status", "Ready", 996, _
        SESSION_TOOLBAR_TOP + 13)
    If session_StatusLabel <> 0 Then
        session_StatusLabel->render = 0
    End If
    gui_AddWidget session_StatusLabel

    session_DrumMachineButton = button_Create("drum_machine_button", "Drum machine", _
        358, 1, 126, SESSION_MENU_HEIGHT - 2, @session_OnDrumMachine)
    If session_DrumMachineButton <> 0 Then _
        session_DrumMachineButton->render = @session_RenderToolbarTextButton
    gui_AddWidget session_DrumMachineButton
    session_SongMeterButton = button_Create("song_meter_button", "Time 4/4...", _
        490, 1, 126, SESSION_MENU_HEIGHT - 2, @session_OnSongMeter)
    If session_SongMeterButton <> 0 Then _
        session_SongMeterButton->render = @session_RenderToolbarTextButton
    gui_AddWidget session_SongMeterButton

    session_NoteToolsButton = button_Create("note_tools_button", "Note tools...", _
        622, 1, 110, SESSION_MENU_HEIGHT - 2, @session_OnNoteTools)
    If session_NoteToolsButton <> 0 Then _
        session_NoteToolsButton->render = @session_RenderToolbarTextButton
    gui_AddWidget session_NoteToolsButton

    session_ScoreHorizontalScrollbar = scrollbar_Create( _
        "score_horizontal", SESSION_SCORE_LEFT, SESSION_SCORE_TOP + 200, _
        400, SESSION_SCORE_SCROLLBAR_SIZE, SESSION_SCORE_SCROLL_RANGE, _
        SESSION_SCORE_SCROLL_PAGE, 0)
    gui_AddWidget session_ScoreHorizontalScrollbar
    session_ScoreVerticalScrollbar = scrollbar_Create( _
        "score_vertical", SESSION_INITIAL_WIDTH - SESSION_SCORE_SCROLLBAR_SIZE, _
        SESSION_SCORE_TOP + 24, SESSION_SCORE_SCROLLBAR_SIZE, 200, 0, 1, -1)
    gui_AddWidget session_ScoreVerticalScrollbar

    session_FileMenu = session_CreateEditorMenu("file_menu", 6, SESSION_MENU_HEIGHT)
    menu_AddItem session_FileMenu, "New", @session_OnFileMenu
    menu_AddItem session_FileMenu, "Open...", @session_OnFileMenu
    menu_AddItem session_FileMenu, "Save MIDI...", @session_OnFileMenu
    menu_AddItem session_FileMenu, "Save Project...", @session_OnFileMenu
    menu_AddItem session_FileMenu, "Export ProTracker MOD...", @session_OnFileMenu
    menu_AddItem session_FileMenu, "Export WAV Mix...", @session_OnFileMenu
    menu_AddItem session_FileMenu, "Exit", @session_OnFileMenu
    gui_AddWidget session_FileMenu
    session_EditMenu = session_CreateEditorMenu("edit_menu", 46, SESSION_MENU_HEIGHT)
    menu_AddItem session_EditMenu, "Undo", @session_OnEditMenu
    menu_AddItem session_EditMenu, "Redo", @session_OnEditMenu
    menu_AddItem session_EditMenu, "Select All", @session_OnEditMenu
    menu_AddItem session_EditMenu, "Cut", @session_OnEditMenu
    menu_AddItem session_EditMenu, "Copy", @session_OnEditMenu
    menu_AddItem session_EditMenu, "Paste", @session_OnEditMenu
    menu_AddItem session_EditMenu, "Note Properties...", @session_OnEditMenu
    menu_AddItem session_EditMenu, "Delete Selected Notes", @session_OnEditMenu
    menu_AddItem session_EditMenu, "Note Tools...", @session_OnEditMenu
    menu_AddItem session_EditMenu, "Duplicate        Ctrl+D", @session_OnEditMenu
    menu_AddItem session_EditMenu, "Quantize         Ctrl+Q", @session_OnEditMenu
    gui_AddWidget session_EditMenu
    session_OptionsMenu = session_CreateEditorMenu("options_menu", 86, SESSION_MENU_HEIGHT)
    menu_AddItem session_OptionsMenu, "Tempo / Meter Map...", @session_OnOptionsMenu
    menu_AddItem session_OptionsMenu, "MIDI Events...", @session_OnOptionsMenu
    menu_AddItem session_OptionsMenu, "Audio Clips...", @session_OnOptionsMenu
    menu_AddItem session_OptionsMenu, "Performance Keyboard...", @session_OnOptionsMenu
    menu_AddItem session_OptionsMenu, "Hum / Whistle Input...", @session_OnOptionsMenu
    menu_AddItem session_OptionsMenu, "[x] Light Theme", @session_OnOptionsMenu
    menu_AddItem session_OptionsMenu, "[ ] Dark Theme", @session_OnOptionsMenu
    menu_AddItem session_OptionsMenu, "[ ] Black Theme", @session_OnOptionsMenu
    menu_AddItem session_OptionsMenu, "[ ] Touch Interface", @session_OnOptionsMenu
    menu_AddItem session_OptionsMenu, "Load SoundFont...", @session_OnOptionsMenu
    menu_AddItem session_OptionsMenu, "[x] Built-in Synth", @session_OnOptionsMenu
    gui_AddWidget session_OptionsMenu
    session_UpdateThemeMenuLabels()
    session_SetupMenu = session_CreateEditorMenu("setup_menu", 150, SESSION_MENU_HEIGHT)
    menu_AddItem session_SetupMenu, "MIDI Input...", @session_OnSetupMenu
    menu_AddItem session_SetupMenu, "MIDI Output...", @session_OnSetupMenu
    menu_AddItem session_SetupMenu, "Document Information...", @session_OnSetupMenu
    menu_AddItem session_SetupMenu, "Apply Tempo", @session_OnSetupMenu
    menu_AddItem session_SetupMenu, "Restart Audio Engine", @session_OnSetupMenu
    gui_AddWidget session_SetupMenu
    session_WindowMenu = session_CreateEditorMenu("view_menu", 206, SESSION_MENU_HEIGHT)
    menu_AddItem session_WindowMenu, "Zoom In        Ctrl+1", @session_OnWindowMenu
    menu_AddItem session_WindowMenu, "Zoom Normal    Ctrl+2", @session_OnWindowMenu
    menu_AddItem session_WindowMenu, "Zoom Out       Ctrl+3", @session_OnWindowMenu
    menu_AddItem session_WindowMenu, "Zoom Selection Ctrl+E", @session_OnWindowMenu
    menu_AddItem session_WindowMenu, "Fit Project    Ctrl+F", @session_OnWindowMenu
    menu_AddItem session_WindowMenu, "Fit Tracks Ctrl+Shift+F", @session_OnWindowMenu
    menu_AddItem session_WindowMenu, "MIDI Event List...", @session_OnWindowMenu
    gui_AddWidget session_WindowMenu
    session_TrackMenu = session_CreateEditorMenu("track_menu", 254, SESSION_MENU_HEIGHT)
    menu_AddItem session_TrackMenu, "Add Track", @session_OnTrackMenu
    menu_AddItem session_TrackMenu, "Remove Track", @session_OnTrackMenu
    menu_AddItem session_TrackMenu, "Track Properties...", @session_OnTrackMenu
    gui_AddWidget session_TrackMenu
    session_MusicMenu = session_CreateEditorMenu("music_menu", 308, SESSION_MENU_HEIGHT)
    menu_AddItem session_MusicMenu, "Add Note", @session_OnMusicMenu
    menu_AddItem session_MusicMenu, "Delete Note", @session_OnMusicMenu
    menu_AddItem session_MusicMenu, "Note Properties...", @session_OnMusicMenu
    menu_AddItem session_MusicMenu, "Play Selected Notes", @session_OnMusicMenu
    menu_AddItem session_MusicMenu, "Audition A4", @session_OnMusicMenu
    menu_AddItem session_MusicMenu, "Drum Kit...", @session_OnMusicMenu
    menu_AddItem session_MusicMenu, "Drum Machine / Phrases...", @session_OnMusicMenu
    gui_AddWidget session_MusicMenu
    session_HelpMenu = session_CreateEditorMenu("help_menu", _
        SESSION_INITIAL_WIDTH - 210, SESSION_MENU_HEIGHT)
    menu_AddItem session_HelpMenu, "About OpenSesh", @session_OnHelpMenu
    menu_AddItem session_HelpMenu, "Quick start / shortcuts", @session_OnHelpMenu
    gui_AddWidget session_HelpMenu
    session_ApplyMenuInteractionMetrics()
    session_UpdateThemeMenuLabels()
End Sub

#endif

/' end of src/editor/smoothness.bi '/
