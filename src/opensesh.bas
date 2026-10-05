/'
    Project: OpenSesh
    ---------------------------

    File: opensesh.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Executable entry point and widget callbacks; no supported library interface.

    Purpose:

        Provide a native FreeBASIC editor shell based on an observable
        desktop MIDI-editor layout. It presents a score preview, a track
        list, and a sixteen-channel mixer while routing transport through
        sfxlib.

    Responsibilities:

        - initialize the omaGui gfxlib backend and application widgets
        - load a bounded MIDI summary from the command line or file dialog
        - draw the score/ruler and mixer surfaces shown by the original UI
        - expose transport, track, note, timeline, automation, audio, and recording commands
        - provide bounded multi-note selection, movement, copy, paste, and delete
        - record MIDI from hardware, playable piano and drum surfaces, or microphone input
        - apply channel automation in bounded global tick order during playback
        - play a bounded snapshot of selected notes through the shared transport
        - route Ctrl+Z and Ctrl+Y through chronological MIDI/audio history
        - apply and persist the selected application theme
        - adapt shared controls and score gestures for coarse touch pointers

    Resource ownership:

        - this application module owns top-level widgets and explicitly tears
          down input, audio samples, sfxlib, and the display during shutdown

    This file intentionally does NOT contain:

        - a sample-accurate score engraver
        - private Midisoft file-format compatibility
        - native MIDI declarations or callback code; those remain isolated in
          midi_input_win.bas and midi_alsa.bas
        - a sample-based General MIDI voice library
        - a private Midisoft recording-session project format
        - preference-file parsing; that remains in user_preferences.bas
'/

' -------------------------------------------------------------------------
' Private editor modules and application lifecycle
' -------------------------------------------------------------------------


#lang "fb"

#If Defined(__FB_WIN32__)
#cmdline "-s gui"
#EndIf

#include once "omaGUI.bi"
#include once "version.bi"
#include once "midi_model.bi"
#include once "audio_tracks.bi"
#include once "audio_sample_slots.bi"
#include once "document_history.bi"
#include once "project_transaction.bi"
#include once "document_save_routing.bi"
#include once "midi_input.bi"
#include once "midi_input_protocol.bi"
#include once "midi_output.bi"
#include once "midi_output_setup_internal.bi"
#include once "pitch_transcriber.bi"
#include once "music_symbols.bi"
#include once "note_selection.bi"
#include once "selected_note_playback.bi"
#include once "score_tools.bi"
#include once "numeric_text.bi"
#include once "score_controls.bi"
#include once "capture_paths.bi"
#include once "score_scroll.bi"
#include once "score_layout.bi"
#include once "mixer_meter.bi"
#include once "mixer_controls.bi"
#include once "mixer_state.bi"
#include once "keyboard_controls.bi"
#include once "drum_kit.bi"
#include once "drum_phrase.bi"
#include once "playback_mix.bi"
#include once "playback_timing.bi"
#include once "ui_frame_pacing.bi"
#include once "software_synth.bi"
#include once "generated_voice_stop_internal.bi"
#include once "soundfont_synth.bi"
#include once "playback_state.bi"
#include once "master_effect.bi"
#include once "sfx_runtime.bi"
#include once "ui_style.bi"
#include once "ui_icons.bi"
#include once "ui_interaction.bi"
#include once "touch_gesture.bi"
#include once "user_preferences.bi"
#include once "music_export.bi"
#include once "wav_export_sfx.bi"

#include once "editor/state.bi"
#include once "editor/document_commands.bi"
#include once "editor/channel_state.bi"
#include once "editor/playback_source.bi"
#include once "editor/midi_transport.bi"
#include once "editor/score_input.bi"
#include once "editor/touch_input.bi"
#include once "editor/score_render.bi"
#include once "editor/keyboard.bi"
#include once "editor/drums.bi"
#include once "editor/drum_machine.bi"
#include once "editor/selection_tools.bi"
#include once "editor/song_meter.bi"
#include once "editor/microphone.bi"
#include once "editor/dialog_commands.bi"
#include once "editor/menus.bi"
#include once "editor/widgets_and_audits.bi"
#include once "editor/smoothness.bi"

session_MasterVolume = 1.0
session_MasterEchoWet = 0.0
session_MasterEchoFeedback = 0.30
mixerMeter_Initialize session_MixerMeter
mixerState_Initialize session_MixerChannels
For channelIndex As Integer = 0 To SESSION_CHANNEL_COUNT - 1
    session_ChannelVolume(channelIndex) = 0.82
    session_ChannelPan(channelIndex) = 0.0
    session_ChannelChorus(channelIndex) = 0.0
    session_ChannelReverb(channelIndex) = 40.0 / 127.0
    session_AuditionPitchForChannel(channelIndex) = -1
Next
For pitch As Integer = 0 To 127
    session_AuditionChannelForPitch(pitch) = -1
Next
noteSelection_Initialize session_NoteSelection
noteClipboard_Initialize session_NoteClipboard
selectedNotePlayback_Initialize session_SelectedNotePlayback
scoreAddTool_Initialize session_AddToolState
wavExport_Initialize session_WavExport
session_SelectedNote = -1
session_ScoreDragNote = -1
session_ActiveScoreTool = SESSION_SCORE_TOOL_SELECT
session_PlaybackSpeedScale = 1.0

/'
    Per-user theme preference

    Ordinary launches use the platform config directory. Automated launches
    disable persistence unless OSE_TEST_PREFERENCES_FILE names an isolated
    fixture, preventing test runs from changing the operator's chosen theme.
'/
Dim As String session_TestPreferencesFilename = Left( _
    Trim(Environ("OSE_TEST_PREFERENCES_FILE")), 4096) ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
Dim As String session_TestSmoothnessReport = Left( _
    Trim(Environ("OSE_TEST_SMOOTHNESS_REPORT")), 4096) ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
Dim As Integer session_AutomatedPreferencesRun = _
    Trim(Environ("OSE_TEST_SNAPSHOT")) <> "" OrElse _ ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
    Trim(Environ("OSE_TEST_CONTROL_REPORT")) <> "" OrElse _ ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
    session_TestSmoothnessReport <> ""
If session_TestPreferencesFilename <> "" Then
    session_PreferencesFilename = session_TestPreferencesFilename
    session_PreferencesEnabled = -1
ElseIf session_AutomatedPreferencesRun = 0 Then
    session_PreferencesFilename = userPreferences_DefaultFilename(0)
    session_PreferencesEnabled = IIf(session_PreferencesFilename <> "", -1, 0)
    session_PreferencesUseDefaultPath = session_PreferencesEnabled
End If

/'
    A packaging environment may choose an appropriate first-run profile
    without taking ownership of the setting. A valid saved preference below
    replaces this default, so Android and future coarse-pointer packages still
    honor the operator's selection from the Options menu after a restart.
'/
Dim As String session_DefaultInteractionText = Left( _
    Trim(Environ("OSE_DEFAULT_INTERACTION_MODE")), 32) ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
If session_DefaultInteractionText <> "" Then
    Dim As Integer defaultInteractionMode
    If uiInteraction_Parse(session_DefaultInteractionText, _
        defaultInteractionMode) <> 0 Then _
        session_InteractionMode = defaultInteractionMode
End If

If session_PreferencesEnabled <> 0 Then
    Dim As OseUserPreferences startupPreferences
    userPreferences_Default startupPreferences
    If userPreferences_Load( _
        session_PreferencesFilename, startupPreferences) = _
        OSE_PREFERENCES_LOAD_OK Then
        session_ThemeMode = startupPreferences.themeMode
        session_InteractionMode = startupPreferences.interactionMode
        session_SoundFontPath = startupPreferences.soundFontPath
    End If
End If
session_StartupThemeMode = session_ThemeMode

Dim As String session_InteractionOverride = Left( _
    Trim(Environ("OSE_INTERACTION_MODE")), 32) ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
If session_InteractionOverride <> "" Then
    Dim As Integer overriddenInteractionMode
    If uiInteraction_Parse(session_InteractionOverride, _
        overriddenInteractionMode) <> 0 Then _
        session_InteractionMode = overriddenInteractionMode
End If
session_StartupInteractionMode = session_InteractionMode
uiInteraction_Metrics session_InteractionMetrics, session_InteractionMode
touchGesture_Reset session_TouchGestureState

/'
    Deterministic visual-test hook

    A bounded environment-only hook lets the editor save its own framebuffer
    after layout has settled. Normal launches never enter this path. Keeping
    capture inside the gfxlib backend avoids desktop scaling and occlusion from
    changing visual-regression evidence.
'/
Dim As String session_TestSnapshotFilename = Left( _
    Trim(Environ("OSE_TEST_SNAPSHOT")), 4096) ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
Dim As Integer session_TestSnapshotFrame = session_TestEnvironmentInteger( _
    "OSE_TEST_SNAPSHOT_FRAME", 1, 600, 12)
Dim As Integer session_TestWindowWidth = SESSION_INITIAL_WIDTH
Dim As Integer session_TestWindowHeight = SESSION_INITIAL_HEIGHT
Dim As UInteger session_TestWindowFlags = BACKEND_WINDOW_RESIZABLE
#If Defined(__FB_HAIKU__)
    /'
        The pinned Haiku runtime initializes a resizable window with a 1x1
        framebuffer, which also invalidates widget hit testing. Its fixed
        window preserves the requested viewport and passes native rendering.
        Recheck the full native GUI audit before enabling resize with a newer
        toolchain. This policy does not alter other desktop window modes.
    '/
    session_TestWindowFlags = BACKEND_WINDOW_FIXED
#EndIf
Dim As Integer session_AutomatedRenderRun = _
    session_TestSnapshotFilename <> "" OrElse _
    session_TestSmoothnessReport <> ""
If session_AutomatedRenderRun <> 0 Then
    session_TestWindowWidth = session_TestEnvironmentInteger( _
        "OSE_TEST_WIDTH", 800, 3840, SESSION_INITIAL_WIDTH)
    session_ScoreTrackRowHeight = session_TestEnvironmentInteger( _
        "OSE_TEST_SCORE_ROW_HEIGHT", _
        SESSION_SCORE_TRACK_ROW_HEIGHT_MINIMUM, _
        SESSION_SCORE_TRACK_ROW_HEIGHT_MAXIMUM, _
        SESSION_SCORE_TRACK_ROW_HEIGHT_DEFAULT)
    session_TestWindowHeight = session_TestEnvironmentInteger( _
        "OSE_TEST_HEIGHT", 600, 2160, SESSION_INITIAL_HEIGHT)
    /'
        Some X11 window managers fit a resizable client to the desktop work
        area before the first frame. A fixed automated-capture window keeps
        the requested framebuffer dimensions independent of panels and launch
        order. Ordinary editor windows remain resizable.
    '/
    session_TestWindowFlags = BACKEND_WINDOW_FIXED
    Select Case LCase(Left(Trim(Environ("OSE_TEST_THEME")), 16)) ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
        Case "dark"
            session_ThemeMode = OSE_UI_THEME_DARK
        Case "black"
            session_ThemeMode = OSE_UI_THEME_BLACK
        Case Else
            session_ThemeMode = OSE_UI_THEME_LIGHT
    End Select
End If
Dim As Integer session_TestFrameCounter
If session_TestSnapshotFilename <> "" AndAlso _
    session_TestEnvironmentFlag("OSE_TEST_OPEN_ADD_PALETTE") <> 0 Then
    session_ActiveScoreTool = SESSION_SCORE_TOOL_ADD_NOTE
    session_AddPaletteVisible = -1
End If
If session_TestSnapshotFilename <> "" AndAlso _
    Environ("OSE_TEST_MIXER_PAGE_ANCHOR") <> "" Then ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
    session_MixerPageAnchor = session_TestEnvironmentInteger( _
        "OSE_TEST_MIXER_PAGE_ANCHOR", 0, SESSION_CHANNEL_COUNT - 1, 0)
End If
If session_AutomatedRenderRun <> 0 Then
    /'
        Framebuffer evidence must not depend on a person's pointer position,
        pressed keys, or pending native window events.  Reset all input sources
        to the deterministic test backend, then place the pointer over the score
        canvas where it cannot hover a toolbar or dialog control.
    '/
    input_ResetForTest()
    Dim As Integer session_TestMouseX = 400
    Dim As Integer session_TestMouseY = 150
    session_TestMouseX = session_TestEnvironmentInteger( _
        "OSE_TEST_MOUSE_X", 0, session_TestWindowWidth - 1, 400)
    session_TestMouseY = session_TestEnvironmentInteger( _
        "OSE_TEST_MOUSE_Y", 0, session_TestWindowHeight - 1, 150)
    input_MockMouse session_TestMouseX, session_TestMouseY, 0
End If

backend_Init session_TestWindowWidth, session_TestWindowHeight, 0, _
    session_TestWindowFlags
WindowTitle OSE_PRODUCT_NAME + " " + OSE_VERSION_TEXT
If session_TestEnvironmentFlag("OSE_TEST_HIDE_WINDOW") <> 0 Then _
    ScreenControl FB.SET_WINDOW_POS, -32000, -32000

gui_Init
session_ApplyTheme session_ThemeMode, 0
musicSymbols_LoadDefault()
session_CreateWidgets()

Dim As String initialFilename = Trim(Command(1))
If initialFilename <> "" Then
    If session_IsProjectFilename(initialFilename) <> 0 Then
        session_LoadProjectFile initialFilename
    Else
        session_LoadMidi initialFilename
    End If
Else
    session_CreateNewDocument()
    session_SetStatus "Ready. Click Note to draw, Drum machine for beats, or Open to load a song."
End If

If session_SoundFontPath <> "" AndAlso session_AutomatedRenderRun = 0 Then
    Dim As String startupSoundFontError
    If soundfontSynth_Load(session_SoundFontPath, startupSoundFontError) <> 0 Then
        session_UpdateThemeMenuLabels()
        session_SetStatus "Loaded SoundFont: " + soundfontSynth_GetName()
    Else
        session_SetStatus "Saved SoundFont could not be loaded: " + _
            startupSoundFontError
    End If
End If

Dim As String session_TestSmoothnessMode = LCase(Left( _
    Trim(Environ("OSE_TEST_SMOOTHNESS_MODE")), 16)) ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
Dim As Integer session_TestSmoothnessTargetFrames = _
    session_TestEnvironmentInteger("OSE_TEST_SMOOTHNESS_FRAMES", _
    OSE_UI_SMOOTHNESS_MINIMUM_SAMPLES, OSE_UI_TIMING_SAMPLE_CAPACITY, _
    SESSION_SMOOTHNESS_DEFAULT_FRAMES)
Dim As Integer session_TestSmoothnessFixtureValid = -1
Dim As OseUiSmoothnessMetrics session_TestSmoothnessMetrics
Dim As Integer session_TestSmoothnessFrameCounter
Dim As Double session_TestSmoothnessPreviousFlipClock
Dim As Integer session_TestSmoothnessPointerUpdates
Dim As Integer session_TestSmoothnessScoreScrollUpdates
Dim As Integer session_TestSmoothnessMixerDragUpdates
Dim As Integer session_TestSmoothnessPlaybackAdvances
Dim As Integer session_TestSmoothnessMeterChanges
If session_TestSmoothnessReport <> "" Then
    uiFramePacing_Initialize session_TestSmoothnessMetrics
    session_SmoothnessProfilingActive = -1
    session_TestSmoothnessFixtureValid = session_CreateSmoothnessFixture()
    If session_TestSmoothnessMode = "playback" AndAlso _
        session_TestSmoothnessFixtureValid <> 0 Then session_OnPlay 0
End If

If session_TestSnapshotFilename <> "" AndAlso _
    Environ("OSE_TEST_AUDITION_PITCH") <> "" Then ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
    /'
        Visual regression can hold one production audition voice long enough
        to capture the channel and master meter attack. The normal application
        never enters this environment-only path, and shutdown stops the voice.
    '/
    Dim As Integer session_TestAuditionPitch = session_TestEnvironmentInteger( _
        "OSE_TEST_AUDITION_PITCH", 0, 127, -1)
    If session_TestAuditionPitch >= 0 Then _
        session_StartAuditionPitch session_TestAuditionPitch
End If

If session_TestSnapshotFilename <> "" Then
    ' Modal snapshots use the real construction paths after the document and
    ' widget tree exist. Unknown names intentionally leave the main view open.
    Select Case LCase(Left(Trim(Environ("OSE_TEST_MODAL")), 32)) ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
        Case "audio"
            session_OnAudio 0
        Case "automation"
            session_OnAutomation 0
        Case "confirm"
            session_BeginDiscardConfirmation SESSION_CONFIRM_QUIT
        Case "file_open"
            session_OpenFileDialog()
        Case "keyboard"
            session_OnKeyboard 0
        Case "drums"
            session_OnDrumKit 0
        Case "drum_machine"
            session_OnDrumMachine 0
        Case "drum_starter"
            session_OnDrumMachine 0
            session_OnPhraseAction gui_FindWidget("phrase_starter")
        Case "song_meter"
            session_OnSongMeter 0
        Case "note_tools"
            session_OnNoteTools 0
        Case "quick_start"
            session_OnHelpMenu 1
        Case "microphone"
            session_OnMic 0
        Case "midi_save"
            session_OpenMidiSaveDialog()
        Case "midi_input"
            session_OnMidiInput 0
        Case "midi_output"
            session_OnMidiOutput 0
        Case "mod_export"
            session_OpenModExportDialog()
        Case "note"
            If midi_GetEditableNoteCount() > 0 Then
                session_SelectOnlyNote 0
                session_OnNoteProperties 0
            End If
        Case "options_menu"
            session_MenuKeyboardAccess = -1
            session_ShowDesktopMenuAt 2, session_TestWindowWidth
        Case "view_menu"
            session_MenuKeyboardAccess = -1
            session_ShowDesktopMenuAt 4, session_TestWindowWidth
        Case "project_save"
            session_OpenProjectSaveDialog()
        Case "tempo"
            session_OnTempoMap 0
        Case "track"
            session_OnTrackProperties 0
        Case "about"
            session_OnHelpMenu 0
        Case "wav_export"
            session_OpenWavExportDialog()
    End Select
End If

Dim As String session_TestControlReport = Left( _
    Trim(Environ("OSE_TEST_CONTROL_REPORT")), 4096) ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
If session_TestControlReport <> "" Then
    session_WriteControlAudit session_TestControlReport
    session_QuitRequested = -1
End If

Do
    Dim As Double session_FrameStartClock = Timer
    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight

    gui_SetViewportSize screenWidth, screenHeight
    session_LayoutToolbarWidgets screenWidth
    session_LayoutPaneScrollbars screenWidth, screenHeight
    Dim As Double session_TestSmoothnessInputClock = session_FrameStartClock
    Dim As ULongInt session_TestSmoothnessPreviousViewTick = session_ViewStartTick
    Dim As Single session_TestSmoothnessPreviousMaster = session_MasterVolume
    Dim As Double session_TestSmoothnessPreviousPlayback = session_PlaybackElapsed
    Dim As Double session_TestSmoothnessPreviousMeter = _
        session_SmoothnessMeterTotal()
    If session_TestSmoothnessReport <> "" Then
        session_TestSmoothnessInputClock = Timer
        session_InjectSmoothnessInput session_TestSmoothnessMode, _
            session_TestSmoothnessFrameCounter, screenWidth, screenHeight, _
            session_TestSmoothnessPointerUpdates
    End If
    gui_UpdateAll
    If session_AutomatedRenderRun = 0 AndAlso _
        backend_WindowCloseRequested() <> 0 Then session_RequestQuit()
    session_ProcessMenuBar()
    session_ProcessPaneScrollbars screenHeight
    session_ProcessDiscardConfirmation()
    session_ProcessNoteWindow()
    session_UpdateTempoMapSelection()
    session_ProcessTempoMapWindow()
    session_ProcessTrackPropertiesWindow()
    session_ProcessMidiInputWindow()
    session_ProcessMidiOutputWindow()
    session_ProcessAboutWindow()
    session_UpdateAutomationSelection()
    session_ProcessAutomationWindow()
    session_UpdateAudioSelection()
    session_ProcessAudioWindow()
    session_ProcessKeyboardWindow()
    session_ProcessDrumWindow()
    session_ProcessPhraseWindow()
    session_ProcessSongMeterWindow()
    session_ProcessNoteToolsWindow()
    session_ProcessMicWindow()
    session_ProcessFileDialog()
    session_UpdateSelection()
    session_UpdateScoreInput screenWidth, screenHeight
    session_UpdateMixerInput screenWidth, screenHeight
    session_ProcessEditShortcuts()
    session_ProcessViewShortcuts()
    session_ProcessTransportShortcuts()
    session_ProcessStepRecording()
    session_UpdateSoftwarePlayback()
    session_UpdateMixerMeters()

    If session_TestSmoothnessReport <> "" Then
        If session_ViewStartTick <> session_TestSmoothnessPreviousViewTick Then _
            session_TestSmoothnessScoreScrollUpdates += 1
        If Abs(session_MasterVolume - _
            session_TestSmoothnessPreviousMaster) > 0.0001 Then _
            session_TestSmoothnessMixerDragUpdates += 1
        If session_PlaybackElapsed > _
            session_TestSmoothnessPreviousPlayback Then _
            session_TestSmoothnessPlaybackAdvances += 1
        If Abs(session_SmoothnessMeterTotal() - _
            session_TestSmoothnessPreviousMeter) > 0.000001 Then _
            session_TestSmoothnessMeterChanges += 1
    End If

    Dim As Integer newDocumentState = 0
    If session_IsModalOpen() = 0 AndAlso _
        input_KeyPressed(FB.SC_CONTROL) <> 0 AndAlso _
        input_KeyPressed(FB.SC_N) <> 0 Then
        newDocumentState = -1
    End If
    If newDocumentState <> 0 AndAlso session_LastNewDocumentState = 0 Then
        session_OnNewDocument 0
    End If
    session_LastNewDocumentState = newDocumentState

    session_UpdateStatusWidget screenWidth
    Dim As Double session_TestSmoothnessRenderClock = Timer
    ' session_DrawApplication begins with an opaque full-window fill. Clearing
    ' the same two-million-pixel surface here duplicated that work at 1080p.
    session_DrawApplication screenWidth, screenHeight
    Dim As Double session_TestSmoothnessApplicationClock = Timer
    session_RenderWidgets screenWidth, screenHeight
    session_DrawKeyboardWindow()
    session_DrawDrumWindow()
    Dim As Double session_TestSmoothnessWidgetClock = Timer
    backend_Flip

    If session_TestSmoothnessReport <> "" Then
        Dim As Double session_TestSmoothnessFlipClock = Timer
        If session_TestSmoothnessPreviousFlipClock > 0.0 AndAlso _
            session_TestSmoothnessFrameCounter >= _
                SESSION_SMOOTHNESS_WARMUP_FRAMES Then
            uiFramePacing_Record _
                session_TestSmoothnessMetrics.frameIntervals, _
                uiFramePacing_ElapsedMilliseconds( _
                session_TestSmoothnessPreviousFlipClock, _
                session_TestSmoothnessFlipClock)
            uiFramePacing_Record session_TestSmoothnessMetrics.frameWork, _
                uiFramePacing_ElapsedMilliseconds( _
                session_FrameStartClock, session_TestSmoothnessWidgetClock)
            uiFramePacing_Record session_TestSmoothnessMetrics.inputLatency, _
                uiFramePacing_ElapsedMilliseconds( _
                session_TestSmoothnessInputClock, _
                session_TestSmoothnessFlipClock)
            uiFramePacing_Record session_TestSmoothnessMetrics.updateWork, _
                uiFramePacing_ElapsedMilliseconds( _
                session_FrameStartClock, session_TestSmoothnessRenderClock)
            uiFramePacing_Record _
                session_TestSmoothnessMetrics.applicationRender, _
                uiFramePacing_ElapsedMilliseconds( _
                session_TestSmoothnessRenderClock, _
                session_TestSmoothnessApplicationClock)
            uiFramePacing_Record session_TestSmoothnessMetrics.widgetRender, _
                uiFramePacing_ElapsedMilliseconds( _
                session_TestSmoothnessApplicationClock, _
                session_TestSmoothnessWidgetClock)
            uiFramePacing_Record session_TestSmoothnessMetrics.presentation, _
                uiFramePacing_ElapsedMilliseconds( _
                session_TestSmoothnessWidgetClock, _
                session_TestSmoothnessFlipClock)
            uiFramePacing_Record session_TestSmoothnessMetrics.scoreRender, _
                session_SmoothnessScoreRenderMs
            uiFramePacing_Record session_TestSmoothnessMetrics.scoreCache, _
                session_SmoothnessScoreCacheMs
            uiFramePacing_Record session_TestSmoothnessMetrics.scoreBase, _
                session_SmoothnessScoreBaseMs
            uiFramePacing_Record session_TestSmoothnessMetrics.scoreRests, _
                session_SmoothnessScoreRestsMs
            uiFramePacing_Record session_TestSmoothnessMetrics.scoreNotes, _
                session_SmoothnessScoreNotesMs
            uiFramePacing_Record session_TestSmoothnessMetrics.scoreToolRender, _
                session_SmoothnessScoreToolRenderMs
            uiFramePacing_Record session_TestSmoothnessMetrics.mixerRender, _
                session_SmoothnessMixerRenderMs
        End If
        session_TestSmoothnessPreviousFlipClock = _
            session_TestSmoothnessFlipClock
        session_TestSmoothnessFrameCounter += 1

        If session_TestSmoothnessMetrics.frameIntervals.count >= _
            session_TestSmoothnessTargetFrames Then
            session_WriteSmoothnessReport session_TestSmoothnessReport, _
                session_TestSmoothnessMode, screenWidth, screenHeight, _
                session_TestSmoothnessMetrics, _
                session_TestSmoothnessPointerUpdates, _
                session_TestSmoothnessScoreScrollUpdates, _
                session_TestSmoothnessMixerDragUpdates, _
                session_TestSmoothnessPlaybackAdvances, _
                session_TestSmoothnessMeterChanges, _
                session_TestSmoothnessFixtureValid
            session_QuitRequested = -1
        End If
    End If

    If session_TestSnapshotFilename <> "" Then
        session_TestFrameCounter += 1
        If session_TestFrameCounter >= session_TestSnapshotFrame Then
            backend_SaveSnapshot session_TestSnapshotFilename
            session_TestSnapshotFilename = ""
            session_QuitRequested = -1
        End If
    End If

    Dim As Integer escapeState = 0
    If session_AutomatedRenderRun = 0 Then _
        escapeState = IIf(MultiKey(FB.SC_ESCAPE), -1, 0)
    If escapeState <> 0 AndAlso session_LastEscapeState = 0 AndAlso _
        session_MenuEscapeConsumed = 0 Then session_RequestQuit()
    session_LastEscapeState = escapeState
Loop Until session_QuitRequested <> 0

If session_AudioCaptureActive <> 0 Then
    session_FinishAudioCapture()
End If
If session_MicCaptureActive <> 0 Then
    session_FinishMicCapture()
End If
session_StopAllAuditionNotes()
session_StopPlayback()
audioSampleSlots_Clear()
masterEffect_Reset()
midiInput_Close()
midiOutput_Close()
soundfontSynth_Shutdown()
sfxRuntime_Shutdown()
musicSymbols_Clear()
gui_ResetForTest()
backend_Exit()

/' end of opensesh.bas '/
