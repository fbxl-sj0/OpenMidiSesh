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

' The initial client area fits a 1366 x 768 desktop with a normal title bar
' and taskbar. The window remains resizable for larger arrangements.
Const SESSION_INITIAL_WIDTH As Integer = 1280
Const SESSION_INITIAL_HEIGHT As Integer = 720
Const SESSION_DESKTOP_MENU_COUNT As Integer = 8
Const SESSION_MIXER_HEIGHT As Integer = OSE_MIXER_HEIGHT
Const SESSION_CHANNEL_COUNT As Integer = OSE_MIXER_CHANNEL_COUNT
Const SESSION_MIDI_MAX_KEY As Integer = 127
Const SESSION_SCORE_BEATS As Integer = 16
Const SESSION_SCORE_MINIMUM_VIEW_BEATS As Integer = 4
Const SESSION_SCORE_ZOOM_STEP As Integer = 4
Const SESSION_SCORE_NOTE_LEFT As Integer = 174
Const SESSION_SCORE_NOTE_RIGHT As Integer = 20
Const SESSION_SCORE_TRACK_LABEL_CHARACTERS As Integer = 19
Const SESSION_DEFAULT_FONT_CHARACTER_WIDTH As Integer = 8
Const SESSION_SCORE_NOTE_CACHE_CAPACITY As Integer = 8192
Const SESSION_SMOOTHNESS_NOTE_COUNT As Integer = 2048
Const SESSION_SMOOTHNESS_TRACK_COUNT As Integer = 16
Const SESSION_SMOOTHNESS_WARMUP_FRAMES As Integer = 60
Const SESSION_SMOOTHNESS_DEFAULT_FRAMES As Integer = 480
' A sustained note is split visually at no more than this many measure lines.
Const SESSION_MAX_SCORE_NOTE_SEGMENTS As Integer = 64
Const SESSION_SCORE_TRACK_ROW_HEIGHT_DEFAULT As Integer = _
    OSE_SCORE_ROW_HEIGHT_DEFAULT
Const SESSION_SCORE_TRACK_ROW_HEIGHT_MINIMUM As Integer = _
    OSE_SCORE_ROW_HEIGHT_MINIMUM
Const SESSION_SCORE_TRACK_ROW_HEIGHT_MAXIMUM As Integer = _
    OSE_SCORE_ROW_HEIGHT_MAXIMUM
Const SESSION_SCORE_TRACK_ROW_ZOOM_STEP As Integer = 8
Const SESSION_MIXER_MASTER_WIDTH As Integer = OSE_MIXER_MASTER_WIDTH
Const SESSION_MIXER_MINIMUM_STRIP_WIDTH As Integer = _
    OSE_MIXER_MINIMUM_STRIP_WIDTH
Const SESSION_MIXER_TITLE_HEIGHT As Integer = OSE_MIXER_TITLE_HEIGHT
Const SESSION_SCORE_SCROLL_RANGE As Integer = 1000
Const SESSION_SCORE_SCROLL_PAGE As Integer = 250
Const SESSION_SCORE_TOOL_COUNT As Integer = OSE_SCORE_CONTROL_TOOL_COUNT
Const SESSION_SCORE_TOOL_SELECT As Integer = OSE_SCORE_CONTROL_TOOL_SELECT
Const SESSION_SCORE_TOOL_ADD_NOTE As Integer = OSE_SCORE_CONTROL_TOOL_ADD_NOTE
Const SESSION_SCORE_TOOL_DELETE_NOTE As Integer = _
    OSE_SCORE_CONTROL_TOOL_DELETE_NOTE
Const SESSION_SCORE_TOOL_CUT As Integer = OSE_SCORE_CONTROL_TOOL_CUT
Const SESSION_SCORE_TOOL_PASTE As Integer = OSE_SCORE_CONTROL_TOOL_PASTE
Const SESSION_SCORE_PALETTE_COLUMN_COUNT As Integer = _
    OSE_SCORE_CONTROL_PALETTE_COLUMNS
Const SESSION_SCORE_PALETTE_ROW_COUNT As Integer = _
    OSE_SCORE_CONTROL_PALETTE_ROWS
Const SESSION_VIEW_ZOOM_IN As Integer = 0
Const SESSION_VIEW_ZOOM_NORMAL As Integer = 1
Const SESSION_VIEW_ZOOM_OUT As Integer = 2
Const SESSION_VIEW_ZOOM_SELECTION As Integer = 3
Const SESSION_VIEW_FIT_PROJECT As Integer = 4
Const SESSION_VIEW_FIT_TRACKS As Integer = 5
Const SESSION_VIEW_MIDI_EVENTS As Integer = 6

/'
    Runtime interaction geometry

    These names preserve the established layout vocabulary throughout the
    editor while resolving through one selected profile. Both desktop and
    touch builds therefore execute the same source and rendering paths.
'/
#define SESSION_MENU_HEIGHT (session_InteractionMetrics.menuHeight)
#define SESSION_TOOLBAR_TOP (session_InteractionMetrics.toolbarTop)
#define SESSION_TOOLBAR_HEIGHT (session_InteractionMetrics.toolbarHeight)
#define SESSION_TOOLBAR_BUTTON_TOP_INSET (session_InteractionMetrics.toolbarButtonTopInset)
#define SESSION_TOOLBAR_BUTTON_HEIGHT (session_InteractionMetrics.toolbarButtonHeight)
#define SESSION_TRANSPORT_STOP_LEFT (session_InteractionMetrics.transportButtonLeft(0))
#define SESSION_TRANSPORT_STOP_WIDTH (session_InteractionMetrics.transportButtonWidth(0))
#define SESSION_TRANSPORT_PAUSE_LEFT (session_InteractionMetrics.transportButtonLeft(1))
#define SESSION_TRANSPORT_PAUSE_WIDTH (session_InteractionMetrics.transportButtonWidth(1))
#define SESSION_TRANSPORT_REWIND_LEFT (session_InteractionMetrics.transportButtonLeft(2))
#define SESSION_TRANSPORT_REWIND_WIDTH (session_InteractionMetrics.transportButtonWidth(2))
#define SESSION_TRANSPORT_PLAY_LEFT (session_InteractionMetrics.transportButtonLeft(3))
#define SESSION_TRANSPORT_PLAY_WIDTH (session_InteractionMetrics.transportButtonWidth(3))
#define SESSION_TRANSPORT_FAST_FORWARD_LEFT (session_InteractionMetrics.transportButtonLeft(4))
#define SESSION_TRANSPORT_FAST_FORWARD_WIDTH (session_InteractionMetrics.transportButtonWidth(4))
#define SESSION_TRANSPORT_RECORD_LEFT (session_InteractionMetrics.transportButtonLeft(5))
#define SESSION_TRANSPORT_RECORD_WIDTH (session_InteractionMetrics.transportButtonWidth(5))
#define SESSION_TRANSPORT_STEP_LEFT (session_InteractionMetrics.transportButtonLeft(6))
#define SESSION_TRANSPORT_STEP_WIDTH (session_InteractionMetrics.transportButtonWidth(6))
#define SESSION_TOP_HEIGHT (session_InteractionMetrics.topHeight)
#define SESSION_SCORE_LEFT (session_InteractionMetrics.scoreRailLeft + session_InteractionMetrics.scoreRailWidth + 6)
#define SESSION_SCORE_TOP (session_InteractionMetrics.scoreTop)
#define SESSION_SCORE_SCROLLBAR_SIZE (session_InteractionMetrics.scoreScrollbarSize)
#define SESSION_SCORE_PALETTE_LEFT (session_InteractionMetrics.scorePaletteLeft)
#define SESSION_SCORE_PALETTE_TOP (session_InteractionMetrics.scorePaletteTop)
#define SESSION_SCORE_PALETTE_COLUMN_WIDTH (session_InteractionMetrics.scorePaletteColumnWidth)
#define SESSION_SCORE_PALETTE_ROW_HEIGHT (session_InteractionMetrics.scorePaletteRowHeight)
#define SESSION_SCORE_PALETTE_FACE_WIDTH (session_InteractionMetrics.scorePaletteFaceWidth)
#define SESSION_SCORE_PALETTE_FACE_HEIGHT (session_InteractionMetrics.scorePaletteFaceHeight)
#define SESSION_SCORE_PALETTE_WIDTH (session_InteractionMetrics.scorePaletteWidth)
#define SESSION_SCORE_PALETTE_HEIGHT (session_InteractionMetrics.scorePaletteHeight)
#define SESSION_SCORE_DRAG_THRESHOLD (session_InteractionMetrics.dragThreshold)
Const SESSION_TOUCH_INTENT_NONE As Integer = 0
Const SESSION_TOUCH_INTENT_TAP As Integer = 1
Const SESSION_TOUCH_INTENT_PAN As Integer = 2
Const SESSION_TOUCH_INTENT_NOTE_DRAG As Integer = 3
Const SESSION_DIALOG_NONE As Integer = 0
Const SESSION_DIALOG_OPEN As Integer = 1
Const SESSION_DIALOG_AUDIO_ADD As Integer = 2
Const SESSION_DIALOG_PROJECT_SAVE As Integer = 3
Const SESSION_DIALOG_MIDI_SAVE As Integer = 4
Const SESSION_DIALOG_MOD_EXPORT As Integer = 5
Const SESSION_DIALOG_WAV_EXPORT As Integer = 6
Const SESSION_DIALOG_SOUNDFONT As Integer = 7
Const SESSION_CONFIRM_NONE As Integer = 0
Const SESSION_CONFIRM_NEW As Integer = 1
Const SESSION_CONFIRM_OPEN As Integer = 2
Const SESSION_CONFIRM_QUIT As Integer = 3
Const SESSION_AUTOMATION_MAX_TICK As ULongInt = OSE_MAX_MIDI_TICK
Const SESSION_AUTOMATION_WINDOW_WIDTH As Integer = 580
Const SESSION_AUTOMATION_WINDOW_HEIGHT As Integer = 390
Const SESSION_AUTOMATION_EVENT_MAX As Integer = 512
Const SESSION_NOTE_WINDOW_WIDTH As Integer = 500
Const SESSION_NOTE_WINDOW_HEIGHT As Integer = 270
Const SESSION_TEMPO_MAP_WINDOW_WIDTH As Integer = 500
Const SESSION_TEMPO_MAP_WINDOW_HEIGHT As Integer = 390
Const SESSION_TRACK_WINDOW_WIDTH As Integer = 520
Const SESSION_TRACK_WINDOW_HEIGHT As Integer = 434
Const SESSION_AUDIO_WINDOW_WIDTH As Integer = 720
Const SESSION_AUDIO_WINDOW_HEIGHT As Integer = 360
Const SESSION_MIDI_INPUT_WINDOW_WIDTH As Integer = 460
Const SESSION_MIDI_INPUT_WINDOW_HEIGHT As Integer = 270
Const SESSION_MIDI_OUTPUT_WINDOW_WIDTH As Integer = 500
Const SESSION_MIDI_OUTPUT_WINDOW_HEIGHT As Integer = 270
Const SESSION_KEYBOARD_WINDOW_WIDTH As Integer = 810
Const SESSION_KEYBOARD_WINDOW_HEIGHT As Integer = 330
Const SESSION_DRUM_WINDOW_MAXIMUM_WIDTH As Integer = 920
Const SESSION_DRUM_WINDOW_MAXIMUM_HEIGHT As Integer = 650
Const SESSION_DRUM_WINDOW_MINIMUM_WIDTH As Integer = 620
Const SESSION_DRUM_WINDOW_MINIMUM_HEIGHT As Integer = 500
Const SESSION_DRUM_SURFACE_LEFT As Integer = 18
Const SESSION_DRUM_SURFACE_TOP As Integer = 142
Const SESSION_DRUM_SURFACE_RIGHT_MARGIN As Integer = 18
Const SESSION_DRUM_SURFACE_BOTTOM_MARGIN As Integer = 18
Const SESSION_MIC_WINDOW_WIDTH As Integer = 620
Const SESSION_MIC_WINDOW_HEIGHT As Integer = 270
Const SESSION_ABOUT_WINDOW_WIDTH As Integer = 620
Const SESSION_ABOUT_WINDOW_HEIGHT As Integer = 250
Const SESSION_KEYBOARD_NOTE_COUNT As Integer = OSE_KEYBOARD_NOTE_COUNT
Const SESSION_KEYBOARD_WHITE_KEY_COUNT As Integer = _
    OSE_KEYBOARD_WHITE_KEY_COUNT
Const SESSION_KEYBOARD_WHITE_KEY_WIDTH As Integer = OSE_KEYBOARD_WHITE_KEY_WIDTH
Const SESSION_KEYBOARD_WHITE_KEY_HEIGHT As Integer = _
    OSE_KEYBOARD_WHITE_KEY_HEIGHT
Const SESSION_KEYBOARD_BLACK_KEY_WIDTH As Integer = OSE_KEYBOARD_BLACK_KEY_WIDTH
Const SESSION_KEYBOARD_BLACK_KEY_HEIGHT As Integer = _
    OSE_KEYBOARD_BLACK_KEY_HEIGHT
Const SESSION_KEYBOARD_LEFT As Integer = OSE_KEYBOARD_LEFT
Const SESSION_KEYBOARD_TOP As Integer = OSE_KEYBOARD_TOP
Const SESSION_MIC_MAX_SECONDS As Double = 120.0
Const SESSION_MIC_MINIMUM_NOTE_MIN_MS As ULongInt = 40
Const SESSION_MIC_MINIMUM_NOTE_MAX_MS As ULongInt = 5000
' sfxlib exposes sixteen channel control lanes. Channel 16 is reserved for
' document audio clips, leaving fifteen generated-voice channels.
Const SESSION_AUDIO_CHANNEL As Integer = 15
#assert OSE_SOFTWARE_SYNTH_VOICE_COUNT = SESSION_AUDIO_CHANNEL
Const SESSION_LIVE_RECORD_MAX_SECONDS As Double = 86400.0
Const SESSION_PERCENT_COMPLETE As Integer = 100
' Used as the initial distance sentinel while searching all 128 MIDI keys.
Const SESSION_MAX_INTEGER As Integer = 2147483647

' fblint: disable-next-line FBL301 REASON: application state is intentionally centralized in this module.
Dim Shared session_Summary As MidiSummary
Dim Shared session_Filename As String
Dim Shared session_ProjectFilename As String
Dim Shared session_StatusText As String
Dim Shared session_StatusLabel As Widget Ptr
Dim Shared session_FileMenu As Widget Ptr
Dim Shared session_EditMenu As Widget Ptr
Dim Shared session_OptionsMenu As Widget Ptr
Dim Shared session_SetupMenu As Widget Ptr
Dim Shared session_TrackMenu As Widget Ptr
Dim Shared session_MusicMenu As Widget Ptr
Dim Shared session_WindowMenu As Widget Ptr
Dim Shared session_HelpMenu As Widget Ptr
Dim Shared session_ThemeMode As Integer = OSE_UI_THEME_LIGHT
Dim Shared session_StartupThemeMode As Integer = OSE_UI_THEME_LIGHT
Dim Shared session_ThemePalette As OseUiThemePalette
Dim Shared session_InteractionMode As Integer = OSE_UI_INTERACTION_FINE
Dim Shared session_StartupInteractionMode As Integer = OSE_UI_INTERACTION_FINE
Dim Shared session_InteractionMetrics As OseUiInteractionMetrics
Dim Shared session_PreferencesFilename As String
Dim Shared session_PreferencesEnabled As Integer
Dim Shared session_PreferencesUseDefaultPath As Integer
Dim Shared session_SoundFontPath As String
Dim Shared session_MenuLastMouseButtons As Integer
Dim Shared session_MenuEscapeConsumed As Integer
Dim Shared session_MenuKeyboardAccess As Integer
Dim Shared session_MenuKeyboardSelection As Integer
Dim Shared session_ScoreHorizontalScrollbar As Widget Ptr
Dim Shared session_ScoreVerticalScrollbar As Widget Ptr
Dim Shared session_LastScoreHorizontalValue As Integer
Dim Shared session_LastScoreVerticalValue As Integer
Dim Shared session_ScoreFirstVisibleTrack As Integer
Dim Shared session_TempoLabel As Widget Ptr
Dim Shared session_TempoBox As Widget Ptr
Dim Shared session_ApplyTempoButton As Widget Ptr
Dim Shared session_TempoMapButton As Widget Ptr
Dim Shared session_DrumMachineButton As Widget Ptr
Dim Shared session_SongMeterButton As Widget Ptr
' The simple meter picker edits only the song signature. Drum phrase meters
' remain independent and continue to live in the drum-machine editor.
Dim Shared session_SongMeterWindow As Widget Ptr
Dim Shared session_NoteToolsWindow As Widget Ptr
Dim Shared session_NoteToolsButton As Widget Ptr
Dim Shared session_NoteToolsInfo As Widget Ptr
Dim Shared session_NoteToolsStatus As Widget Ptr
' Editing preferences belong to the session, not to the saved MIDI events.
Dim Shared session_SnapIndex As Integer = 2
Dim Shared session_LastQuickEditMask As Integer
Dim Shared session_SongMeterNumeratorBox As Widget Ptr
Dim Shared session_SongMeterDenominatorBox As Widget Ptr
Dim Shared session_SongMeterInfo As Widget Ptr
Dim Shared session_SongMeterStatus As Widget Ptr
Dim Shared session_SongMeterTick As ULongInt
Dim Shared session_SongMeterViewTick As ULongInt
Dim Shared session_SongMeterCloseRequested As Integer
Dim Shared session_MidiInputButton As Widget Ptr
Dim Shared session_MidiOutputButton As Widget Ptr
Dim Shared session_TempoMapWindow As Widget Ptr
Dim Shared session_TempoMapList As Widget Ptr
Dim Shared session_TempoMapTickValueLabel As Widget Ptr
Dim Shared session_TempoMapBpmBox As Widget Ptr
Dim Shared session_TempoMapNumeratorBox As Widget Ptr
Dim Shared session_TempoMapDenominatorBox As Widget Ptr
Dim Shared session_TempoMapKeyBox As Widget Ptr
Dim Shared session_TempoMapMinorBox As Widget Ptr
Dim Shared session_TempoMapSelectedIndex As Integer
Dim Shared session_TrackList As Widget Ptr
Dim Shared session_TrackWindow As Widget Ptr
Dim Shared session_TrackNameBox As Widget Ptr
Dim Shared session_DocumentTitleBox As Widget Ptr
Dim Shared session_CopyrightBox As Widget Ptr
Dim Shared session_LyricBox As Widget Ptr
Dim Shared session_MarkerBox As Widget Ptr
Dim Shared session_QuantizeGridBox As Widget Ptr
Dim Shared session_AutomationWindow As Widget Ptr
Dim Shared session_AutomationList As Widget Ptr
Dim Shared session_AutomationTickBox As Widget Ptr
Dim Shared session_AutomationTrackBox As Widget Ptr
Dim Shared session_AutomationChannelBox As Widget Ptr
Dim Shared session_AutomationTypeBox As Widget Ptr
Dim Shared session_AutomationData1Box As Widget Ptr
Dim Shared session_AutomationData2Box As Widget Ptr
Dim Shared session_AutomationSelectedSource As Integer
Dim Shared session_AutomationSelectedKind As Integer
Dim Shared session_AutomationEventRefCount As Integer
Dim Shared session_NoteWindow As Widget Ptr
Dim Shared session_NoteTickBox As Widget Ptr
Dim Shared session_NoteDurationBox As Widget Ptr
Dim Shared session_NoteTrackBox As Widget Ptr
Dim Shared session_NoteChannelBox As Widget Ptr
Dim Shared session_NotePitchBox As Widget Ptr
Dim Shared session_NoteVelocityBox As Widget Ptr
Dim Shared session_AudioWindow As Widget Ptr
Dim Shared session_AudioList As Widget Ptr
Dim Shared session_AudioTickBox As Widget Ptr
Dim Shared session_AudioGainBox As Widget Ptr
Dim Shared session_AudioSelectedIndex As Integer
Dim Shared session_AudioCaptureActive As Integer
Dim Shared session_AudioCaptureStartTick As ULongInt
Dim Shared session_AudioCaptureFilename As String
Dim Shared session_MidiInputWindow As Widget Ptr
Dim Shared session_MidiInputList As Widget Ptr
Dim Shared session_MidiInputSelectedIndex As Integer
Dim Shared session_MidiOutputWindow As Widget Ptr
Dim Shared session_MidiOutputList As Widget Ptr
Dim Shared session_MidiOutputSelectedIndex As Integer
Dim Shared session_MidiOutputDeviceIndex As Integer
Dim Shared session_AboutWindow As Widget Ptr
Dim Shared session_KeyboardWindow As Widget Ptr
Dim Shared session_KeyboardBasePitch As Integer = 60
Dim Shared session_KeyboardMousePitch As Integer = -1
Dim Shared session_KeyboardLastMouseButtons As Integer
Dim Shared session_DrumWindow As Widget Ptr
Dim Shared session_DrumSoftButton As Widget Ptr
Dim Shared session_DrumMediumButton As Widget Ptr
Dim Shared session_DrumHardButton As Widget Ptr
Dim Shared session_DrumVelocity As Integer = OSE_DRUM_VELOCITY_MEDIUM
Dim Shared session_DrumPadHeld(0 To OSE_DRUM_PAD_COUNT - 1) As Integer

' The phrase draft belongs to its modal editor. Saved slots live in MIDI text
' events, so switching documents and undo never leave a separate stale bank.
Dim Shared session_PhraseWindow As Widget Ptr
Dim Shared session_Phrase As OseDrumPhrase
Dim Shared session_PhraseSlot As Integer
Dim Shared session_PhraseChanged As Integer
Dim Shared session_PhraseNameBox As Widget Ptr
Dim Shared session_PhraseBeatsBox As Widget Ptr
Dim Shared session_PhraseUnitBox As Widget Ptr
Dim Shared session_PhraseDivisionBox As Widget Ptr
Dim Shared session_PhraseTickBox As Widget Ptr
Dim Shared session_PhraseRepeatBox As Widget Ptr
Dim Shared session_PhraseInfo As Widget Ptr
Dim Shared session_PhraseStatus As Widget Ptr
Dim Shared session_PhraseCells(0 To 11, 0 To 15) As Widget Ptr
Dim Shared session_PhraseRows(0 To 11) As Widget Ptr
Dim Shared session_PhraseColumns(0 To 15) As Widget Ptr
Dim Shared session_PhraseVisibleRows As Integer
Dim Shared session_PhraseVisibleColumns As Integer
Dim Shared session_PhraseFirstRow As Integer
Dim Shared session_PhraseFirstStep As Integer
Dim Shared session_PhraseLooping As Integer
Dim Shared session_PhraseLoopClock As Double
Dim Shared session_PhraseLoopElapsed As Double
Dim Shared session_PhraseLoopStep As Integer = -1
Dim Shared session_PhraseClearArmed As Integer
' Widget callbacks only request window changes. The frame loop performs the
' removal after omaGUI has finished using the activating button's data.
Dim Shared session_PhraseOpenRequested As Integer
Dim Shared session_PhraseSongMeterRequested As Integer
Dim Shared session_AuditionChannelForPitch(0 To 127) As Integer
Dim Shared session_AuditionPitchForChannel(0 To SESSION_CHANNEL_COUNT - 1) As Integer
Dim Shared session_MicWindow As Widget Ptr
Dim Shared session_MicQuantizeBox As Widget Ptr
Dim Shared session_MicMinimumNoteBox As Widget Ptr
Dim Shared session_MicStateLabel As Widget Ptr
Dim Shared session_MicCaptureActive As Integer
Dim Shared session_MicCaptureStartTick As ULongInt
Dim Shared session_MicCaptureStartClock As Double
Dim Shared session_MicCaptureFilename As String
Dim Shared session_MicCaptureTrack As Integer
Dim Shared session_FileDialog As Widget Ptr
Dim Shared session_FileDialogMode As Integer
Dim Shared session_WavExport As OseWavExportState
Dim Shared session_WavExportFinishing As Integer
Dim Shared session_WavExportLastPercent As Integer = -1
Dim Shared session_ConfirmDialog As Widget Ptr
Dim Shared session_ConfirmAction As Integer
Dim Shared session_Playing As Integer
Dim Shared session_Paused As Integer
Dim Shared session_QuitRequested As Integer
Dim Shared session_LastEscapeState As Integer
Dim Shared session_SelectedTrack As Integer
Dim Shared session_SelectedNote As Integer
Dim Shared session_NoteSelection As NoteSelectionState
Dim Shared session_NoteClipboard As NoteClipboardState
Dim Shared session_SelectedNotePlayback As OseSelectedNotePlaybackState
Dim Shared session_SelectedNotePlaybackActive As Integer
Dim Shared session_SelectedNoteLooping As Integer
Dim Shared session_SelectedNoteLoopEnd As ULongInt
Dim Shared session_AddToolState As ScoreAddToolState
Dim Shared session_NotePasteBuffer( _
    0 To OSE_NOTE_SELECTION_CAPACITY - 1) As MidiEditableNote
Dim Shared session_Dirty As Integer
Dim Shared session_DocumentHistory As OseDocumentHistory
Dim Shared session_PreparedEditDirtyState As Integer
Dim Shared session_LastMouseButtons As Integer
Dim Shared session_LastScoreButtons As Integer
Dim Shared session_LastUndoState As Integer
Dim Shared session_LastRedoState As Integer
Dim Shared session_LastCopyState As Integer
Dim Shared session_LastPasteState As Integer
Dim Shared session_LastCutState As Integer
Dim Shared session_LastSelectAllState As Integer
Dim Shared session_LastSaveShortcutState As Integer
Dim Shared session_LastTransportShortcutState As Integer
Dim Shared session_LastSelectedPlaybackShortcutState As Integer
Dim Shared session_LastFunctionShortcutMask As Integer
Dim Shared session_LastViewShortcutMask As Integer
Dim Shared session_LastTransportMouseButtons As Integer
Dim Shared session_ScoreDragNote As Integer
Dim Shared session_ActiveScoreTool As Integer
Dim Shared session_ScoreDragStartMouseX As Integer
Dim Shared session_ScoreDragStartMouseY As Integer
Dim Shared session_ScoreDragMouseOffsetX As Integer
Dim Shared session_ScoreDragMouseOffsetY As Integer
Dim Shared session_ScoreDragResizeMode As Integer
Dim Shared session_ScoreDragHistoryCaptured As Integer
Dim Shared session_ScoreDragHasApplied As Integer
Dim Shared session_ScoreDragLastTickDelta As LongInt
Dim Shared session_ScoreDragLastPitchDelta As Integer
Dim Shared session_ScoreDragOriginalCount As Integer
Dim Shared session_ScoreDragAnchorStartTick As ULongInt
Dim Shared session_ScoreDragAnchorDurationTicks As ULongInt
Dim Shared session_ScoreDragAnchorKey As Integer
Dim Shared session_ScoreDragAnchorTrack As Integer
Dim Shared session_ScoreDragMinimumStartTick As ULongInt
Dim Shared session_ScoreDragMaximumEndTick As ULongInt
Dim Shared session_ScoreDragMinimumKey As Integer
Dim Shared session_ScoreDragMaximumKey As Integer
Dim Shared session_ScoreDragIndices( _
    0 To OSE_NOTE_SELECTION_CAPACITY - 1) As Integer
Dim Shared session_ScoreDragOriginalNotes( _
    0 To OSE_NOTE_SELECTION_CAPACITY - 1) As MidiEditableNote
Dim Shared session_ScoreDragAdjustedNotes( _
    0 To OSE_NOTE_SELECTION_CAPACITY - 1) As MidiEditableNote
Dim Shared session_ScoreMarqueeActive As Integer
Dim Shared session_ScoreMarqueeAdditive As Integer
Dim Shared session_ScoreMarqueeStartX As Integer
Dim Shared session_ScoreMarqueeStartY As Integer
Dim Shared session_ScoreMarqueeCurrentX As Integer
Dim Shared session_ScoreMarqueeCurrentY As Integer
Dim Shared session_ScoreMarqueeCuts As Integer
Dim Shared session_AddPaletteVisible As Integer
Dim Shared session_ViewStartTick As ULongInt
Dim Shared session_ViewBeatCount As Integer = SESSION_SCORE_BEATS
Dim Shared session_ScoreTrackRowHeight As Integer = _
    SESSION_SCORE_TRACK_ROW_HEIGHT_DEFAULT
Dim Shared session_TouchGestureState As OseTouchGestureState
Dim Shared session_TouchContacts(0 To INPUT_TOUCH_CAPACITY - 1) As OseTouchContact
Dim Shared session_TouchIntent As Integer
Dim Shared session_TouchStartNote As Integer = -1
Dim Shared session_TouchStartTrack As Integer = -1
Dim Shared session_TouchPanStartTick As ULongInt
Dim Shared session_TouchPanStartTrack As Integer
Dim Shared session_TouchTrackPixelRemainder As Integer
Dim Shared session_TouchPinchXAccumulator As Double
Dim Shared session_TouchPinchYAccumulator As Double
Dim Shared session_LastDeleteState As Integer
Dim Shared session_LastNewDocumentState As Integer
Dim Shared session_PlaybackElapsed As Double
Dim Shared session_PlaybackSpeedScale As Double
Dim Shared session_PlaybackLastClock As Double
Dim Shared session_PlaybackLastTick As ULongInt
Dim Shared session_PlaybackFirstUpdate As Integer
Dim Shared session_PlaybackState As OsePlaybackChannelState
Dim Shared session_PlaybackOrderedChannelEvents() As MidiChannelEventPoint
Dim Shared session_PlaybackOrderedChannelEventCount As Integer
Dim Shared session_PlaybackChannelOrderDirty As Integer
Dim Shared session_ChannelVolume(0 To SESSION_CHANNEL_COUNT - 1) As Single
Dim Shared session_ChannelPan(0 To SESSION_CHANNEL_COUNT - 1) As Single
Dim Shared session_ChannelChorus(0 To SESSION_CHANNEL_COUNT - 1) As Single
Dim Shared session_ChannelReverb(0 To SESSION_CHANNEL_COUNT - 1) As Single
Dim Shared session_MasterVolume As Single
Dim Shared session_MasterEchoWet As Single
Dim Shared session_MasterEchoFeedback As Single
Dim Shared session_MixerMeter As OseMixerMeterState
Dim Shared session_MixerMeterLastClock As Double
Dim Shared session_MixerChannels As OseMixerChannelState
Dim Shared session_MixerDragKind As Integer
Dim Shared session_MixerDragChannel As Integer = -1
Dim Shared session_MixerDragMidiChanged As Integer
Dim Shared session_MixerPageAnchor As Integer = -1
Dim Shared session_StepEntryTick As ULongInt
Dim Shared session_StepEntryLastState(0 To 127) As Integer
Dim Shared session_LiveRecording As Integer
Dim Shared session_LiveRecordingStartTick As ULongInt
Dim Shared session_LiveRecordingStartClock As Double
Dim Shared session_LiveRecordingStartMidiTimestamp As ULong
Dim Shared session_LiveRecordingHasMidiTimestamp As Integer
Dim Shared session_LiveRecordingKeyboardOnly As Integer
Dim Shared session_ScoreLayout As OseScoreLayoutState
Dim Shared session_ScoreVisibleNoteIndices( _
    0 To SESSION_SCORE_NOTE_CACHE_CAPACITY - 1) As Integer
Dim Shared session_ScoreVisibleNoteCount As Integer
Dim Shared session_ScoreVisibleNoteOverflowed As Integer
Dim Shared session_ScoreCacheGeneration As UInteger
Dim Shared session_ScoreModelCacheGeneration( _
    0 To OSE_MAX_EDITABLE_NOTES - 1) As UInteger
Dim Shared session_ScoreModelCachePosition( _
    0 To OSE_MAX_EDITABLE_NOTES - 1) As Integer
Dim Shared session_ScoreStemComputed( _
    0 To SESSION_SCORE_NOTE_CACHE_CAPACITY - 1) As Integer
Dim Shared session_ScoreStemDirection( _
    0 To SESSION_SCORE_NOTE_CACHE_CAPACITY - 1) As Integer
Dim Shared session_ScoreBeamComputed( _
    0 To SESSION_SCORE_NOTE_CACHE_CAPACITY - 1) As Integer
Dim Shared session_ScoreBeamPartner( _
    0 To SESSION_SCORE_NOTE_CACHE_CAPACITY - 1) As Integer
Dim Shared session_LiveNoteIndex(0 To 127) As Integer
Dim Shared session_LiveNoteStartTick(0 To 127) As ULongInt
Dim Shared session_LiveMidiNoteIndex(0 To 2047) As Integer
Dim Shared session_LiveMidiNoteStartTick(0 To 2047) As ULongInt
Dim Shared session_LiveMidiNoteReleased(0 To 2047) As Integer
Dim Shared session_LiveMidiSustain(0 To SESSION_CHANNEL_COUNT - 1) As Integer
Dim Shared session_MidiInputDeviceIndex As Integer
Dim Shared session_MidiInputAutoOpened As Integer
Dim Shared session_LastMidiInputDroppedCount As ULongInt
Dim Shared session_MidiOutputOpened As Integer
Dim Shared session_SmoothnessProfilingActive As Integer
Dim Shared session_SmoothnessScoreRenderMs As Double
Dim Shared session_SmoothnessScoreCacheMs As Double
Dim Shared session_SmoothnessScoreBaseMs As Double
Dim Shared session_SmoothnessScoreRestsMs As Double
Dim Shared session_SmoothnessScoreNotesMs As Double
Dim Shared session_SmoothnessScoreToolRenderMs As Double
Dim Shared session_SmoothnessMixerRenderMs As Double
Dim Shared session_ChromePageWidth(0 To 1) As Integer
Dim Shared session_ChromePageHeight(0 To 1) As Integer
Dim Shared session_ChromePageTheme(0 To 1) As Integer
Dim Shared session_ChromePageKeyboardAccess(0 To 1) As Integer
Dim Shared session_ChromePageVisibleMenu(0 To 1) As Integer
Dim Shared session_ChromePageModalState(0 To 1) As Integer
Dim Shared session_ChromePageStatus(0 To 1) As Integer
Dim Shared session_StatusPageValid(0 To 1) As Integer
Dim Shared session_StatusPageFingerprint(0 To 1) As ULongInt
Dim Shared session_ScoreStaticPageWidth(0 To 1) As Integer
Dim Shared session_ScoreStaticPageHeight(0 To 1) As Integer
Dim Shared session_ScoreStaticPageTheme(0 To 1) As Integer
Dim Shared session_ScoreStaticPageFingerprint(0 To 1) As UInteger
Dim Shared session_ScorePageValid(0 To 1) As Integer
Dim Shared session_ScorePageFingerprint(0 To 1) As ULongInt
Dim Shared session_ScoreHeaderPageValid(0 To 1) As Integer
Dim Shared session_ScoreHeaderPageFingerprint(0 To 1) As ULongInt
Dim Shared session_MixerPageValid(0 To 1) As Integer
Dim Shared session_MixerPageFingerprint(0 To 1) As ULongInt
Dim Shared session_MixerStaticPageFingerprint(0 To 1) As ULongInt
Dim Shared session_MixerPageMasterVolume(0 To 1) As Single
Dim Shared session_ScoreToolPageValid(0 To 1) As Integer
Dim Shared session_ScoreToolPageFingerprint(0 To 1) As ULongInt
Dim Shared session_WidgetPageValid(0 To 1) As Integer
Dim Shared session_WidgetPageFingerprint(0 To 1) As ULongInt

Type SessionAutomationEventReference
    As Integer eventKind
    As Integer eventIndex
    As Integer sourceIndex
End Type

Dim Shared session_AutomationEventRefs( _
    0 To SESSION_AUTOMATION_EVENT_MAX - 1) As SessionAutomationEventReference

Declare Sub session_OnNewDocument(ByVal source As Widget Ptr)
Declare Sub session_OnOpen(ByVal source As Widget Ptr)
Declare Sub session_OnPlay(ByVal source As Widget Ptr)
Declare Sub session_OnPlaySelectedNotes(ByVal source As Widget Ptr)
Declare Sub session_OnPause(ByVal source As Widget Ptr)
Declare Sub session_OnStop(ByVal source As Widget Ptr)
Declare Sub session_OnRewind(ByVal source As Widget Ptr)
Declare Sub session_OnFastForward(ByVal source As Widget Ptr)
Declare Sub session_OnStepRecord(ByVal source As Widget Ptr)
Declare Sub session_OnLiveRecord(ByVal source As Widget Ptr)
Declare Sub session_OnKeyboard(ByVal source As Widget Ptr)
Declare Sub session_OnKeyboardClose(ByVal source As Widget Ptr)
Declare Sub session_OnKeyboardRecord(ByVal source As Widget Ptr)
Declare Sub session_OnKeyboardOctaveDown(ByVal source As Widget Ptr)
Declare Sub session_OnKeyboardOctaveUp(ByVal source As Widget Ptr)
Declare Sub session_OnDrumKit(ByVal source As Widget Ptr)
Declare Sub session_OnDrumMachine(ByVal source As Widget Ptr)
Declare Sub session_OnSongMeter(ByVal source As Widget Ptr)
Declare Sub session_OnSongMeterAction(ByVal source As Widget Ptr)
Declare Sub session_OnPhraseAction(ByVal source As Widget Ptr)
Declare Sub session_OnPhraseCell(ByVal source As Widget Ptr)
Declare Sub session_OnDrumClose(ByVal source As Widget Ptr)
Declare Sub session_OnDrumRecord(ByVal source As Widget Ptr)
Declare Sub session_OnDrumSoft(ByVal source As Widget Ptr)
Declare Sub session_OnDrumMedium(ByVal source As Widget Ptr)
Declare Sub session_OnDrumHard(ByVal source As Widget Ptr)
Declare Sub session_OnMic(ByVal source As Widget Ptr)
Declare Sub session_OnMicClose(ByVal source As Widget Ptr)
Declare Sub session_OnMicCapture(ByVal source As Widget Ptr)
Declare Sub session_OnMidiInput(ByVal source As Widget Ptr)
Declare Sub session_OnMidiOutput(ByVal source As Widget Ptr)
Declare Sub session_OnTone(ByVal source As Widget Ptr)
Declare Sub session_OnSave(ByVal source As Widget Ptr)
Declare Sub session_OnSaveProject(ByVal source As Widget Ptr)
Declare Sub session_OnExportMod(ByVal source As Widget Ptr)
Declare Sub session_OnExportWav(ByVal source As Widget Ptr)
Declare Sub session_OnSoundFont(ByVal source As Widget Ptr)
Declare Sub session_OnUseBuiltInSynth(ByVal source As Widget Ptr)
Declare Sub session_OnAudio(ByVal source As Widget Ptr)
Declare Sub session_OnAudioClose(ByVal source As Widget Ptr)
Declare Sub session_OnAddAudio(ByVal source As Widget Ptr)
Declare Sub session_OnCaptureAudio(ByVal source As Widget Ptr)
Declare Sub session_OnApplyAudio(ByVal source As Widget Ptr)
Declare Sub session_OnDeleteAudio(ByVal source As Widget Ptr)
Declare Sub session_OnMidiInputWindowClose(ByVal source As Widget Ptr)
Declare Sub session_OnMidiInputOpenSelected(ByVal source As Widget Ptr)
Declare Sub session_OnMidiInputCloseSelected(ByVal source As Widget Ptr)
Declare Sub session_OnMidiOutputWindowClose(ByVal source As Widget Ptr)
Declare Sub session_OnMidiOutputOpenSelected(ByVal source As Widget Ptr)
Declare Sub session_OnMidiOutputCloseSelected(ByVal source As Widget Ptr)
Declare Sub session_OnApplyTempo(ByVal source As Widget Ptr)
Declare Sub session_OnTempoMap(ByVal source As Widget Ptr)
Declare Sub session_OnTempoMapClose(ByVal source As Widget Ptr)
Declare Sub session_OnApplyTempoMap(ByVal source As Widget Ptr)
Declare Sub session_OnAddTempoMap(ByVal source As Widget Ptr)
Declare Sub session_OnDeleteTempoMap(ByVal source As Widget Ptr)
Declare Sub session_OnTrackProperties(ByVal source As Widget Ptr)
Declare Sub session_OnTrackPropertiesClose(ByVal source As Widget Ptr)
Declare Sub session_OnApplyTrackProperties(ByVal source As Widget Ptr)
Declare Sub session_OnQuantizeTrack(ByVal source As Widget Ptr)
Declare Sub session_OnAutomation(ByVal source As Widget Ptr)
Declare Sub session_OnAddAutomation(ByVal source As Widget Ptr)
Declare Sub session_OnApplyAutomation(ByVal source As Widget Ptr)
Declare Sub session_OnDeleteAutomation(ByVal source As Widget Ptr)
Declare Sub session_OnNoteProperties(ByVal source As Widget Ptr)
Declare Sub session_OnNotePropertiesClose(ByVal source As Widget Ptr)
Declare Sub session_OnApplyNoteProperties(ByVal source As Widget Ptr)
Declare Sub session_OnDeleteNoteProperties(ByVal source As Widget Ptr)
Declare Sub session_OnAddTrack(ByVal source As Widget Ptr)
Declare Sub session_OnRemoveTrack(ByVal source As Widget Ptr)
Declare Sub session_OnDeleteNote(ByVal source As Widget Ptr)
Declare Sub session_EndLiveRecording()
Declare Sub session_ProcessMidiInput()
Declare Sub session_ProcessEditShortcuts()
Declare Sub session_ProcessViewShortcuts()
Declare Sub session_ApplyMixerState()
Declare Function session_RestartAudioRuntime( _
    ByVal announceChange As Integer _
) As Integer
Declare Sub session_CopySelectedNotes()
Declare Sub session_CutSelectedNotes()
Declare Sub session_PasteCopiedNotes()
Declare Sub session_DeleteSelectedNotes()
Declare Sub session_SelectAllNotes()
Declare Function session_LiveRecordingTick() As ULongInt
Declare Function session_BeginLiveRecording( _
    ByVal includeMidiInput As Integer _
) As Integer
Declare Sub session_SendMidiOutputRange( _
    ByVal currentTick As ULongInt, _
    ByVal previousTick As ULongInt, _
    ByVal firstUpdate As Integer _
)
Declare Function session_IsModalOpen() As Integer
Declare Sub session_OnNoteTools(ByVal source As Widget Ptr)
Declare Sub session_OnNoteToolAction(ByVal source As Widget Ptr)
Declare Sub session_ApplySelectionTool(ByVal operation As Integer, ByVal amount As Integer = 0)
Declare Function session_SnapName() As String
Declare Function session_VisibleDesktopMenuIndex() As Integer
Declare Function session_ScoreVisibleTrackCount( _
    ByVal screenHeight As Integer _
) As Integer
Declare Function session_MidiDiatonicIndexForKey( _
    ByVal keyNumber As Integer, _
    ByVal sharpsFlats As Integer _
) As Integer
Declare Function session_ScoreMeasureNumber(ByVal tick As ULongInt) As ULongInt
Declare Sub session_MusicalPosition( _
    ByVal tick As ULongInt, _
    ByRef measureNumber As ULongInt, _
    ByRef beatNumber As ULongInt, _
    ByRef subTick As ULongInt _
)
Declare Function session_MusicalPositionText( _
    ByVal tick As ULongInt _
) As String
Declare Function session_ScoreNextMeasureBoundary( _
    ByVal tick As ULongInt _
) As ULongInt
Declare Sub session_FinishAudioCapture()
Declare Sub session_FinishMicCapture()
Declare Function session_LoadAudioSamples() As Integer
Declare Function session_AudioAvailabilitySuffix() As String
Declare Sub session_OnFileMenu(ByVal selectedIndex As Integer)
Declare Sub session_OnEditMenu(ByVal selectedIndex As Integer)
Declare Sub session_OnOptionsMenu(ByVal selectedIndex As Integer)
Declare Sub session_OnSetupMenu(ByVal selectedIndex As Integer)
Declare Sub session_OnTrackMenu(ByVal selectedIndex As Integer)
Declare Sub session_OnMusicMenu(ByVal selectedIndex As Integer)
Declare Sub session_OnWindowMenu(ByVal selectedIndex As Integer)
Declare Sub session_OnHelpMenu(ByVal selectedIndex As Integer)
Declare Sub session_ApplyInteractionMode( _
    ByVal interactionMode As Integer, _
    ByVal announceChange As Integer _
)
Declare Sub session_DrawRaisedPanel( _
    ByVal panelLeft As Integer, _
    ByVal panelTop As Integer, _
    ByVal panelWidth As Integer, _
    ByVal panelHeight As Integer, _
    ByVal faceColor As ULong _
)
Declare Sub session_DrawRoundedControl( _
    ByVal controlLeft As Integer, _
    ByVal controlTop As Integer, _
    ByVal controlWidth As Integer, _
    ByVal controlHeight As Integer, _
    ByRef controlStyle As OseUiControlStyle _
)

' -------------------------------------------------------------------------
' File, status, and transport helpers
' -------------------------------------------------------------------------

Private Function session_LeafFilename(ByVal filename As String) As String
    Dim As Integer separatorPosition = InStrRev(filename, "\")
    Dim As Integer slashPosition = InStrRev(filename, "/")
    If slashPosition > separatorPosition Then
        separatorPosition = slashPosition
    End If
    If separatorPosition > 0 AndAlso separatorPosition < Len(filename) Then
        Return Mid(filename, separatorPosition + 1)
    End If
    Return filename
End Function


Private Function session_ClipText( _
    ByVal textValue As String, _
    ByVal maximumCharacters As Integer _
) As String
    If maximumCharacters < 1 Then
        Return ""
    End If
    If Len(textValue) <= maximumCharacters Then
        Return textValue
    End If
    If maximumCharacters <= 3 Then
        Return Left(textValue, maximumCharacters)
    End If
    Return Left(textValue, maximumCharacters - 3) + "..."
End Function


Private Function session_PathWithExtension( _
    ByVal filename As String, _
    ByVal extensionText As String _
) As String
    Dim As Integer separatorPosition = InStrRev(filename, "\")
    Dim As Integer slashPosition = InStrRev(filename, "/")
    If slashPosition > separatorPosition Then
        separatorPosition = slashPosition
    End If
    Dim As Integer dotPosition = InStrRev(filename, ".")
    If dotPosition <= separatorPosition Then
        Return filename + extensionText
    End If
    Return Left(filename, dotPosition - 1) + extensionText
End Function


Private Function session_IsProjectFilename(ByVal filename As String) As Integer
    If Len(filename) < 4 Then
        Return 0
    End If
    If LCase(Right(filename, 4)) = ".ose" Then
        Return -1
    End If
    Return 0
End Function


Private Function session_NormalizeMidiSaveFilename( _
    ByVal filename As String _
) As String
    Dim As String normalizedFilename = Trim(filename)
    If normalizedFilename = "" Then
        Return ""
    End If

    Dim As String lowerFilename = LCase(normalizedFilename)
    If Right(lowerFilename, 4) = ".mid" OrElse _
        Right(lowerFilename, 5) = ".midi" Then
        Return normalizedFilename
    End If
    Return normalizedFilename + ".mid"
End Function


Private Function session_DirectoryExists(ByVal directoryName As String) As Integer
    directoryName = Trim(directoryName)
    If directoryName = "" Then
        Return 0
    End If
    If Dir(directoryName, fbDirectory) <> "" Then
        Return -1
    End If
    Return 0
End Function


Private Function session_CaptureDirectory() As String
    ' Existing projects keep their external WAV references portable by placing
    ' new takes beside the project or standalone MIDI document when possible.
    Dim As String projectDirectory = capturePaths_ParentDirectory( _
        session_ProjectFilename)
    If session_DirectoryExists(projectDirectory) <> 0 Then
        Return projectDirectory
    End If
    Dim As String midiDirectory = capturePaths_ParentDirectory(session_Filename)
    If session_DirectoryExists(midiDirectory) <> 0 Then
        Return midiDirectory
    End If

    Dim As String userDirectory
#If Defined(__FB_WIN32__)
    userDirectory = Trim(Environ("USERPROFILE"))
    Dim As String musicDirectory = capturePaths_Join(userDirectory, "Music")
    If session_DirectoryExists(musicDirectory) <> 0 Then _
        userDirectory = musicDirectory
#Else
    userDirectory = Trim(Environ("HOME"))
#EndIf
    If session_DirectoryExists(userDirectory) <> 0 Then
        Dim As String captureDirectory = capturePaths_Join( _
            userDirectory, "OpenSesh Captures")
        If session_DirectoryExists(captureDirectory) = 0 Then _
            MkDir captureDirectory
        If session_DirectoryExists(captureDirectory) <> 0 Then _
            Return captureDirectory
    End If

    ' CurDir is a last resort for restricted or unusually configured accounts.
    ' Unlike ExePath it is not inherently the read-only installation directory.
    If session_DirectoryExists(CurDir) <> 0 Then
        Return CurDir
    End If
    Return ""
End Function


Private Sub session_SetStatus(ByVal message As String)
    session_StatusText = message
    If session_StatusLabel = 0 OrElse session_StatusLabel->data = 0 Then
        Exit Sub
    End If
    Dim As LabelData Ptr statusData = Cast(LabelData Ptr, session_StatusLabel->data)
    statusData->text = message
End Sub


Private Sub session_UpdateThemeMenuLabels()
    If session_OptionsMenu = 0 OrElse session_OptionsMenu->data = 0 Then
        Exit Sub
    End If
    Dim As MenuData Ptr menuState = Cast(MenuData Ptr, session_OptionsMenu->data)
    If menuState->count < 8 Then
        Exit Sub
    End If

    menuState->items(5) = IIf(session_ThemeMode = OSE_UI_THEME_LIGHT, _
        "[x] Light Theme", "[ ] Light Theme")
    menuState->items(6) = IIf(session_ThemeMode = OSE_UI_THEME_DARK, _
        "[x] Dark Theme", "[ ] Dark Theme")
    menuState->items(7) = IIf(session_ThemeMode = OSE_UI_THEME_BLACK, _
        "[x] Black Theme", "[ ] Black Theme")
    If menuState->count >= 9 Then
        menuState->items(8) = IIf( _
            session_InteractionMode = OSE_UI_INTERACTION_TOUCH, _
            "[x] Touch Interface", "[ ] Touch Interface")
    End If
    If menuState->count >= 11 Then
        If soundfontSynth_IsActive() <> 0 Then
            menuState->items(9) = "SoundFont: " + _
                Left(soundfontSynth_GetName(), 30) + "..."
            menuState->items(10) = "Use Built-in Synth"
        Else
            menuState->items(9) = "Load SoundFont..."
            menuState->items(10) = "[x] Built-in Synth"
        End If
    End If
End Sub


Private Function session_SaveThemePreference() As Integer
    ' Automated visual and control runs opt out unless their runner supplies a
    ' dedicated file. This keeps deterministic tests away from a person's real
    ' profile while still allowing the application save route to be audited.
    If session_PreferencesEnabled = 0 Then
        Return -1
    End If

    Dim As String preferenceFilename = session_PreferencesFilename
    If session_PreferencesUseDefaultPath <> 0 Then
        preferenceFilename = userPreferences_DefaultFilename(-1)
        If preferenceFilename = "" Then
            Return 0
        End If
        session_PreferencesFilename = preferenceFilename
    End If

    Dim As OseUserPreferences preferences
    userPreferences_Default preferences
    preferences.themeMode = session_ThemeMode
    preferences.interactionMode = session_InteractionMode
    preferences.soundFontPath = session_SoundFontPath
    Return userPreferences_Save(preferenceFilename, preferences)
End Function


Private Sub session_ApplyTheme( _
    ByVal themeMode As Integer, _
    ByVal announceChange As Integer _
)
    If themeMode < OSE_UI_THEME_LIGHT OrElse _
        themeMode >= OSE_UI_THEME_COUNT Then themeMode = OSE_UI_THEME_LIGHT
    session_ThemeMode = themeMode
    uiStyle_EditorTheme session_ThemePalette, session_ThemeMode

    ' omaGUI reads these public colors at render time. Theme-derived labels use
    ' the same live text color, so already-open generated dialogs switch without
    ' being destroyed and recreated.
    current_theme.bg_face = session_ThemePalette.faceColor
    current_theme.bg_dark = session_ThemePalette.shadowColor
    current_theme.bg_light = session_ThemePalette.highlightColor
    current_theme.text_main = session_ThemePalette.textColor
    current_theme.text_select = session_ThemePalette.selectedTextColor
    current_theme.bg_select = session_ThemePalette.selectedFillColor
    current_theme.win_border = session_ThemePalette.borderColor
    current_theme.bg_widget = session_ThemePalette.highlightColor
    current_theme.menu_background = session_ThemePalette.faceColor
    current_theme.menu_text = session_ThemePalette.textColor
    current_theme.menu_selected_background = _
        session_ThemePalette.selectedFillColor
    current_theme.menu_selected_text = _
        session_ThemePalette.selectedTextColor
    current_theme.menu_separator = session_ThemePalette.shadowColor
    current_theme.menu_disabled_text = session_ThemePalette.shadowColor
    current_theme.title_background = session_ThemePalette.faceColor
    current_theme.title_text = session_ThemePalette.textColor
    ' Shared classic widgets keep semantic palette roles of their own. Refresh
    ' those roles when the application changes the public theme fields.
    theme_SetClassicColor GUI_CLASSIC_COLOR_ACCESS_TEXT, _
        session_ThemePalette.textColor
    theme_SetClassicColor GUI_CLASSIC_COLOR_ACTIVE_BORDER_BACKGROUND, _
        session_ThemePalette.faceColor
    theme_SetClassicColor GUI_CLASSIC_COLOR_ACTIVE_BORDER_TEXT, _
        session_ThemePalette.borderColor
    theme_SetClassicColor GUI_CLASSIC_COLOR_COMMAND_TEXT, _
        session_ThemePalette.textColor
    theme_SetClassicColor GUI_CLASSIC_COLOR_DISABLED_TEXT, _
        session_ThemePalette.shadowColor
    theme_SetClassicColor GUI_CLASSIC_COLOR_MENU_BACKGROUND, _
        session_ThemePalette.faceColor
    theme_SetClassicColor GUI_CLASSIC_COLOR_MENU_TEXT, _
        session_ThemePalette.textColor
    theme_SetClassicColor GUI_CLASSIC_COLOR_MENU_SELECTED_BACKGROUND, _
        session_ThemePalette.selectedFillColor
    theme_SetClassicColor GUI_CLASSIC_COLOR_MENU_SELECTED_TEXT, _
        session_ThemePalette.selectedTextColor
    theme_SetClassicColor GUI_CLASSIC_COLOR_SCROLLBAR_BACKGROUND, _
        session_ThemePalette.faceColor
    theme_SetClassicColor GUI_CLASSIC_COLOR_SCROLLBAR_TEXT, _
        session_ThemePalette.textColor
    session_UpdateThemeMenuLabels()

    If announceChange <> 0 Then
        If session_SaveThemePreference() <> 0 Then
            session_SetStatus uiStyle_ThemeName(session_ThemeMode) + _
                " theme selected."
        Else
            session_SetStatus uiStyle_ThemeName(session_ThemeMode) + _
                " theme selected, but the preference could not be saved."
        End If
    End If
End Sub


Private Function session_CreateEditorWindow( _
    ByVal windowName As String, ByVal captionText As String, _
    ByVal windowX As Integer, ByVal windowY As Integer, _
    ByVal windowWidth As Integer, ByVal windowHeight As Integer, _
    ByVal closable As Integer = -1 _
) As Widget Ptr
    ' Editor dialogs keep the single close control used by the original UI.
    Dim As Widget Ptr editorWindow = subwindow_Create( _
        windowName, captionText, windowX, windowY, _
        windowWidth, windowHeight, closable _
    )
    If editorWindow = 0 Then Return 0

    subwindow_SetMinButton editorWindow, 0
    subwindow_SetMaxButton editorWindow, 0
    subwindow_SetTitleTextYOffset editorWindow, 1
    Return editorWindow
End Function


Private Function session_CreateEditorMenu( _
    ByVal menuName As String, ByVal menuX As Integer, _
    ByVal menuY As Integer _
) As Widget Ptr
    ' Keep caption placement from OpenSesh's reviewed popup geometry.
    Dim As Widget Ptr editorMenu = menu_Create(menuName, menuX, menuY)
    If editorMenu = 0 Then Return 0

    menu_SetTextYOffset editorMenu, -2
    Return editorMenu
End Function


Private Function session_CreateEditorLabel( _
    ByVal labelName As String, ByVal labelText As String, _
    ByVal labelX As Integer, ByVal labelY As Integer, _
    ByVal textColor As ULong = LABEL_COLOR_THEME_TEXT, _
    ByVal fontId As Integer = BACKEND_FONT_DEFAULT _
) As Widget Ptr
    ' Theme-bound labels retain their color when an open dialog changes theme.
    Return label_Create( _
        labelName, labelText, labelX, labelY, textColor, fontId _
    )
End Function


Private Function session_CreateEditorTextBox( _
    ByVal boxName As String, ByVal initialText As String, _
    ByVal boxX As Integer, ByVal boxY As Integer, _
    ByVal boxWidth As Integer, ByVal boxHeight As Integer, _
    ByVal multiline As Integer, ByVal wordWrap As Integer, _
    ByVal scrollbarMode As Integer = TEXTBOX_SCROLLBAR_AUTO _
) As Widget Ptr
    Dim As Widget Ptr editorBox = textbox_Create( _
        boxName, initialText, boxX, boxY, boxWidth, boxHeight, _
        multiline, wordWrap, scrollbarMode)
    If editorBox = 0 Then Return 0

    ' Snapshot tests compare every pixel. Keep the host clock from changing
    ' an otherwise identical frame when a focused caret blinks.
    If Environ("OSE_TEST_SNAPSHOT") <> "" Then _
        textbox_SetCaretVisible editorBox, 0
    Return editorBox
End Function


Private Sub session_StyleEditorGeneratedWindow(ByVal editorWindow As Widget Ptr)
    If editorWindow = 0 Then Exit Sub

    ' Generated modal windows use the same close-only title as hand-built
    ' editor windows. Keep the shared factories free of editor palette policy.
    subwindow_SetMinButton editorWindow, 0
    subwindow_SetMaxButton editorWindow, 0
    subwindow_SetTitleTextYOffset editorWindow, 1
End Sub


Private Function session_CreateEditorOpenDialog( _
    ByVal dialogName As String, ByVal dialogX As Integer, _
    ByVal dialogY As Integer, ByVal initialPath As String _
) As Widget Ptr
    Dim As Widget Ptr dialogRoot = filedialog_CreateAtPath( _
        dialogName, dialogX, dialogY, initialPath)
    session_StyleEditorGeneratedWindow filedialog_GetWindow(dialogRoot)
    Return dialogRoot
End Function


Private Function session_CreateEditorSaveDialog( _
    ByVal dialogName As String, ByVal dialogX As Integer, _
    ByVal dialogY As Integer, ByVal initialPath As String, _
    ByVal initialFilename As String _
) As Widget Ptr
    Dim As Widget Ptr dialogRoot = filedialog_CreateSaveAtPath( _
        dialogName, dialogX, dialogY, initialPath, initialFilename)
    session_StyleEditorGeneratedWindow filedialog_GetWindow(dialogRoot)
    Return dialogRoot
End Function


Private Function session_CreateEditorConfirmDialog( _
    ByVal dialogName As String, ByVal titleText As String, _
    ByVal messageText As String, ByVal dialogX As Integer, _
    ByVal dialogY As Integer, ByVal confirmText As String _
) As Widget Ptr
    Dim As Widget Ptr dialogRoot = confirmdialog_Create( _
        dialogName, titleText, messageText, dialogX, dialogY, confirmText)
    session_StyleEditorGeneratedWindow confirmdialog_GetWindow(dialogRoot)
    Dim As Widget Ptr messageLabel = confirmdialog_GetMessageLabel(dialogRoot)
    If messageLabel <> 0 Then _
        label_SetTextColor messageLabel, LABEL_COLOR_THEME_TEXT
    Return dialogRoot
End Function


Private Sub session_InvalidateInterfaceCaches()
    For pageIndex As Integer = 0 To 1
        session_ChromePageWidth(pageIndex) = 0
        session_ScoreStaticPageWidth(pageIndex) = 0
        session_ScorePageValid(pageIndex) = 0
        session_ScoreHeaderPageValid(pageIndex) = 0
        session_MixerPageValid(pageIndex) = 0
        session_ScoreToolPageValid(pageIndex) = 0
        session_StatusPageValid(pageIndex) = 0
        session_WidgetPageValid(pageIndex) = 0
    Next
End Sub


Private Sub session_ApplyMenuInteractionMetrics()
    Dim As Widget Ptr menus(0 To SESSION_DESKTOP_MENU_COUNT - 1) = { _
        session_FileMenu, session_EditMenu, session_OptionsMenu, _
        session_SetupMenu, session_WindowMenu, session_TrackMenu, _
        session_MusicMenu, session_HelpMenu _
    }
    For menuIndex As Integer = 0 To SESSION_DESKTOP_MENU_COUNT - 1
        If menus(menuIndex) <> 0 Then _
            menu_SetItemHeight menus(menuIndex), _
                session_InteractionMetrics.menuItemHeight
    Next
End Sub


Sub session_ApplyInteractionMode( _
    ByVal interactionMode As Integer, _
    ByVal announceChange As Integer _
)
    If interactionMode < OSE_UI_INTERACTION_FINE OrElse _
        interactionMode >= OSE_UI_INTERACTION_COUNT Then _
        interactionMode = OSE_UI_INTERACTION_FINE

    session_InteractionMode = interactionMode
    uiInteraction_Metrics session_InteractionMetrics, session_InteractionMode
    touchGesture_Reset session_TouchGestureState
    session_TouchIntent = 0
    session_TouchStartNote = -1
    session_TouchStartTrack = -1
    session_TouchPinchXAccumulator = 0.0
    session_TouchPinchYAccumulator = 0.0
    session_ApplyMenuInteractionMetrics()
    session_UpdateThemeMenuLabels()
    session_InvalidateInterfaceCaches()

    If announceChange <> 0 Then
        If session_SaveThemePreference() <> 0 Then
            session_SetStatus uiInteraction_Name(session_InteractionMode) + _
                " interface selected."
        Else
            session_SetStatus uiInteraction_Name(session_InteractionMode) + _
                " interface selected, but the preference could not be saved."
        End If
    End If
End Sub


Private Function textbox_GetText(ByVal textWidget As Widget Ptr) As String
    /'
        omaGUI textbox compatibility

        The current omaGUI keeps TextBoxData public and exposes the checked
        textbox_SetText mutator, but no longer declares the former read helper.
        Centralizing the read here avoids spreading data casts throughout the
        editor and preserves the existing validation call sites.
    '/
    If textWidget = 0 OrElse textWidget->data = 0 Then
        Return ""
    End If
    Dim As TextBoxData Ptr textData = Cast(TextBoxData Ptr, textWidget->data)
    Return textData->text
End Function


Private Sub session_UpdateStatusWidget(ByVal screenWidth As Integer)
    If session_StatusLabel = 0 OrElse session_StatusLabel->data = 0 Then
        Exit Sub
    End If

    ' The shelf's lower line is reserved for feedback in both profiles.
    ' Validation errors and selection hints must survive a narrow window.
    session_StatusLabel->visible = -1
    session_StatusLabel->x = 8
    session_StatusLabel->y = SESSION_SCORE_TOP - 12

    Dim As Integer reservedRight = 54
    Dim As Integer availablePixels = screenWidth - session_StatusLabel->x - _
        reservedRight
    Dim As Integer maximumCharacters = availablePixels \ 8
    If maximumCharacters < 8 Then
        maximumCharacters = 8
    End If

    Dim As LabelData Ptr statusData = Cast(LabelData Ptr, session_StatusLabel->data)
    statusData->text = session_ClipText(session_StatusText, maximumCharacters)
End Sub


Private Function session_BeginMidiEdit() As Integer
    If documentHistory_PrepareMidi(session_DocumentHistory, _
        session_Summary) = 0 Then
        session_SetStatus "Edit history snapshot could not be allocated."
        Return 0
    End If
    session_PreparedEditDirtyState = session_Dirty
    Return -1
End Function


Private Function session_CommitMidiEdit() As Integer
    If documentHistory_CommitMidi(session_DocumentHistory) = 0 Then
        If documentHistory_CancelMidi( _
            session_DocumentHistory, session_Summary) <> 0 Then _
            session_Dirty = session_PreparedEditDirtyState
        session_PlaybackChannelOrderDirty = -1
        session_SetStatus "MIDI edit history could not be committed."
        Return 0
    End If
    session_PlaybackChannelOrderDirty = -1
    Return -1
End Function


Private Function session_CancelMidiEdit() As Integer
    Dim As Integer cancelled = documentHistory_CancelMidi( _
        session_DocumentHistory, session_Summary)
    session_PlaybackChannelOrderDirty = -1
    If cancelled <> 0 Then
        session_Dirty = session_PreparedEditDirtyState
    End If
    Return cancelled
End Function


Private Function session_BeginAudioEdit() As Integer
    If documentHistory_PrepareAudio(session_DocumentHistory) = 0 Then
        session_SetStatus "Audio edit history snapshot could not be allocated."
        Return 0
    End If
    session_PreparedEditDirtyState = session_Dirty
    Return -1
End Function


Private Function session_CommitAudioEdit() As Integer
    If documentHistory_CommitAudio(session_DocumentHistory) = 0 Then
        If documentHistory_CancelAudio(session_DocumentHistory) <> 0 Then _
            session_Dirty = session_PreparedEditDirtyState
        session_SetStatus "Audio edit history could not be committed."
        Return 0
    End If
    Return -1
End Function


Private Sub session_CancelAudioEdit()
    Dim As Integer cancelled = documentHistory_CancelAudio( _
        session_DocumentHistory)
    If cancelled <> 0 Then
        session_Dirty = session_PreparedEditDirtyState
    End If
End Sub


Private Sub session_RefreshMixerFromSummary()
    For channelIndex As Integer = 0 To SESSION_CHANNEL_COUNT - 1
        session_ChannelVolume(channelIndex) = _
            CSng(session_Summary.channelVolume(channelIndex)) / 127.0
        session_ChannelPan(channelIndex) = _
            (CSng(session_Summary.channelPan(channelIndex)) - 64.0) / 63.0
        If session_ChannelPan(channelIndex) < -1.0 Then _
            session_ChannelPan(channelIndex) = -1.0
        If session_ChannelPan(channelIndex) > 1.0 Then _
            session_ChannelPan(channelIndex) = 1.0
        session_ChannelChorus(channelIndex) = _
            CSng(session_Summary.channelChorus(channelIndex)) / 127.0
        session_ChannelReverb(channelIndex) = _
            CSng(session_Summary.channelReverb(channelIndex)) / 127.0
    Next
End Sub


Private Function session_RoundNonnegative( _
    ByVal numericValue As Double _
) As Integer
    /'
        FreeBASIC CInt already rounds floating-point values. Adding 0.5 before
        CInt rounds twice and can turn an exact odd integer into the following
        even integer because CInt uses tie-to-even behavior. Int performs the
        intended single half-up conversion for these nonnegative UI values.
    '/
    If numericValue <= 0.0 Then
        Return 0
    End If
    If numericValue >= 2147483647.0 Then
        Return 2147483647
    End If
    Return CInt(Int(numericValue + 0.5))
End Function


Private Function session_InitialTempoBpm() As Integer
    Dim As ULong tempoValue = session_Summary.tempoMicrosecondsPerQuarter
    If session_Summary.tempoCount > 0 AndAlso _
        session_Summary.tempoMap(0).microsecondsPerQuarter > 0 Then
        tempoValue = session_Summary.tempoMap(0).microsecondsPerQuarter
    End If
    If tempoValue = 0 Then
        Return 120
    End If

    Dim As Integer beatsPerMinute = session_RoundNonnegative( _
        60000000.0 / CDbl(tempoValue))
    If beatsPerMinute < 20 Then
        beatsPerMinute = 20
    End If
    If beatsPerMinute > 400 Then
        beatsPerMinute = 400
    End If
    Return beatsPerMinute
End Function


Private Sub session_RefreshTempoBox()
    If session_TempoBox = 0 Then
        Exit Sub
    End If
    textbox_SetText session_TempoBox, Str(session_InitialTempoBpm()), -1
End Sub


Private Function session_TempoPointBpm(ByVal tempoIndex As Integer) As Integer
    If tempoIndex < 0 OrElse tempoIndex >= session_Summary.tempoCount Then _
        Return 120
    Dim As ULong tempoValue = _
        session_Summary.tempoMap(tempoIndex).microsecondsPerQuarter
    If tempoValue = 0 Then
        Return 120
    End If
    Dim As Integer beatsPerMinute = session_RoundNonnegative( _
        60000000.0 / CDbl(tempoValue))
    If beatsPerMinute < 20 Then
        beatsPerMinute = 20
    End If
    If beatsPerMinute > 400 Then
        beatsPerMinute = 400
    End If
    Return beatsPerMinute
End Function


Private Function session_TempoDenominatorValue( _
    ByVal denominatorPower As Integer _
) As Integer
    If denominatorPower < 0 OrElse denominatorPower > 7 Then
        Return 4
    End If
    Dim As Integer denominatorValue = 1
    For powerIndex As Integer = 1 To denominatorPower
        denominatorValue *= 2
    Next
    Return denominatorValue
End Function


Private Function session_TimeSignatureIndexForTick( _
    ByVal tick As ULongInt _
) As Integer
    If session_Summary.timeSignatureCount <= 0 Then
        Return -1
    End If
    Dim As Integer selectedIndex = 0
    For signatureIndex As Integer = 0 To _
        session_Summary.timeSignatureCount - 1
        If session_Summary.timeSignatureMap(signatureIndex).tick > tick Then _
            Exit For
        selectedIndex = signatureIndex
    Next
    Return selectedIndex
End Function


Private Function session_TimeSignatureIndexExactForTick( _
    ByVal tick As ULongInt _
) As Integer
    For signatureIndex As Integer = 0 To _
        session_Summary.timeSignatureCount - 1
        If session_Summary.timeSignatureMap(signatureIndex).tick = tick Then
            Return signatureIndex
        End If
    Next
    Return -1
End Function


Private Function session_TempoIndexExactForTick( _
    ByVal tick As ULongInt _
) As Integer
    For tempoIndex As Integer = 0 To session_Summary.tempoCount - 1
        If session_Summary.tempoMap(tempoIndex).tick = tick Then
            Return tempoIndex
        End If
    Next
    Return -1
End Function


Private Function session_KeySignatureIndexForTick( _
    ByVal tick As ULongInt _
) As Integer
    If session_Summary.keySignatureCount <= 0 Then
        Return -1
    End If
    Dim As Integer selectedIndex = 0
    For signatureIndex As Integer = 0 To _
        session_Summary.keySignatureCount - 1
        If session_Summary.keySignatureMap(signatureIndex).tick > tick Then _
            Exit For
        selectedIndex = signatureIndex
    Next
    Return selectedIndex
End Function


Private Function session_KeySignatureIndexExactForTick( _
    ByVal tick As ULongInt _
) As Integer
    For signatureIndex As Integer = 0 To _
        session_Summary.keySignatureCount - 1
        If session_Summary.keySignatureMap(signatureIndex).tick = tick Then
            Return signatureIndex
        End If
    Next
    Return -1
End Function


Private Function session_KeySignatureText( _
    ByVal sharpsFlats As Integer, _
    ByVal minor As Integer _
) As String
    Dim As String majorNames(0 To 14) = _
        {"Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", _
         "G", "D", "A", "E", "B", "F#", "C#"}
    Dim As String minorNames(0 To 14) = _
        {"Abm", "Ebm", "Bbm", "Fm", "Cm", "Gm", "Dm", "Am", _
         "Em", "Bm", "F#m", "C#m", "G#m", "D#m", "A#m"}
    Dim As Integer nameIndex = sharpsFlats + 7
    If nameIndex < 0 OrElse nameIndex > 14 Then
        nameIndex = 7
    End If
    If minor <> 0 Then
        Return minorNames(nameIndex)
    End If
    Return majorNames(nameIndex)
End Function


Private Sub session_SetTempoMapFields(ByVal tempoIndex As Integer)
    If tempoIndex < 0 OrElse tempoIndex >= session_Summary.tempoCount Then
        Exit Sub
    End If

    If session_TempoMapTickValueLabel <> 0 Then
        textbox_SetText session_TempoMapTickValueLabel, _
            Str(session_Summary.tempoMap(tempoIndex).tick), -1
    End If
    If session_TempoMapBpmBox <> 0 Then
        textbox_SetText session_TempoMapBpmBox, _
            Str(session_TempoPointBpm(tempoIndex)), -1
    End If
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick( _
        session_Summary.tempoMap(tempoIndex).tick)
    If signatureIndex < 0 Then
        signatureIndex = 0
    End If
    If session_TempoMapNumeratorBox <> 0 Then
        textbox_SetText session_TempoMapNumeratorBox, _
            Str(session_Summary.timeSignatureMap(signatureIndex).numerator), -1
    End If
    If session_TempoMapDenominatorBox <> 0 Then
        textbox_SetText session_TempoMapDenominatorBox, _
            Str(session_TempoDenominatorValue( _
                session_Summary.timeSignatureMap(signatureIndex).denominatorPower)), _
            -1
    End If
    Dim As Integer keyIndex = session_KeySignatureIndexForTick( _
        session_Summary.tempoMap(tempoIndex).tick)
    If keyIndex < 0 Then
        keyIndex = 0
    End If
    If keyIndex < session_Summary.keySignatureCount Then
        If session_TempoMapKeyBox <> 0 Then
            textbox_SetText session_TempoMapKeyBox, _
                Str(session_Summary.keySignatureMap(keyIndex).sharpsFlats), -1
        End If
        If session_TempoMapMinorBox <> 0 Then
            textbox_SetText session_TempoMapMinorBox, _
                Str(session_Summary.keySignatureMap(keyIndex).minor), -1
        End If
    End If
End Sub


Private Sub session_RefreshTempoMapList()
    If session_TempoMapList = 0 Then
        Exit Sub
    End If

    listbox_Clear session_TempoMapList
    Dim As Integer visibleCount = session_Summary.tempoCount
    If visibleCount > LISTBOX_MAX_ITEMS Then
        visibleCount = LISTBOX_MAX_ITEMS
    End If
    For tempoIndex As Integer = 0 To visibleCount - 1
        Dim As Integer signatureIndex = session_TimeSignatureIndexForTick( _
            session_Summary.tempoMap(tempoIndex).tick)
        If signatureIndex < 0 Then
            signatureIndex = 0
        End If
        Dim As Integer keyIndex = session_KeySignatureIndexForTick( _
            session_Summary.tempoMap(tempoIndex).tick)
        If keyIndex < 0 OrElse keyIndex >= session_Summary.keySignatureCount Then _
            keyIndex = -1
        Dim As String keyText = ""
        If keyIndex >= 0 Then
            keyText = "  Key " + session_KeySignatureText( _
                session_Summary.keySignatureMap(keyIndex).sharpsFlats, _
                session_Summary.keySignatureMap(keyIndex).minor)
        End If
        Dim As String rowText = Str(tempoIndex + 1) + "  Tick " + _
            Str(session_Summary.tempoMap(tempoIndex).tick) + "  BPM " + _
            Str(session_TempoPointBpm(tempoIndex)) + "  Meter " + _
            Str(session_Summary.timeSignatureMap(signatureIndex).numerator) + "/" + _
            Str(session_TempoDenominatorValue( _
                session_Summary.timeSignatureMap(signatureIndex).denominatorPower)) + _
            keyText
        listbox_AddItem session_TempoMapList, rowText
    Next

    If visibleCount <= 0 Then
        session_TempoMapSelectedIndex = -1
        Exit Sub
    End If
    If session_TempoMapSelectedIndex < 0 OrElse _
        session_TempoMapSelectedIndex >= visibleCount Then
        session_TempoMapSelectedIndex = 0
    End If

    If session_TempoMapList->data <> 0 Then
        Dim As ListBoxData Ptr listData = Cast( _
            ListBoxData Ptr, session_TempoMapList->data)
        listData->selected_index = session_TempoMapSelectedIndex
    End If
    session_SetTempoMapFields session_TempoMapSelectedIndex
End Sub


Private Sub session_UpdateTempoMapSelection()
    If session_TempoMapList = 0 Then
        Exit Sub
    End If
    Dim As Integer selectedIndex = listbox_GetSelectedIndex(session_TempoMapList)
    If selectedIndex < 0 OrElse _
        selectedIndex >= session_Summary.tempoCount Then Exit Sub
    If selectedIndex <> session_TempoMapSelectedIndex Then
        session_TempoMapSelectedIndex = selectedIndex
        session_SetTempoMapFields selectedIndex
    End If
End Sub


Private Function session_SyncChannelMix(ByVal channelIndex As Integer) As Integer
    If channelIndex < 0 OrElse channelIndex >= SESSION_CHANNEL_COUNT Then
        Return 0
    End If

    Dim As Integer volumeValue = session_RoundNonnegative( _
        session_ChannelVolume(channelIndex) * 127.0)
    Dim As Integer panValue = session_RoundNonnegative( _
        (session_ChannelPan(channelIndex) + 1.0) * 63.5)
    If volumeValue < 0 Then
        volumeValue = 0
    End If
    If volumeValue > 127 Then
        volumeValue = 127
    End If
    If panValue < 0 Then
        panValue = 0
    End If
    If panValue > 127 Then
        panValue = 127
    End If

    If midi_SetChannelMix(session_Summary, channelIndex, _
        volumeValue, panValue) <> 0 Then
        session_Dirty = -1
        Return -1
    Else
        session_SetStatus "Mixer edit could not be stored."
        Return 0
    End If
End Function


Private Function session_SyncChannelEffects( _
    ByVal channelIndex As Integer _
) As Integer
    If channelIndex < 0 OrElse channelIndex >= SESSION_CHANNEL_COUNT Then
        Return 0
    End If

    Dim As Integer chorusValue = session_RoundNonnegative( _
        session_ChannelChorus(channelIndex) * 127.0)
    Dim As Integer reverbValue = session_RoundNonnegative( _
        session_ChannelReverb(channelIndex) * 127.0)
    If chorusValue < 0 Then
        chorusValue = 0
    End If
    If chorusValue > 127 Then
        chorusValue = 127
    End If
    If reverbValue < 0 Then
        reverbValue = 0
    End If
    If reverbValue > 127 Then
        reverbValue = 127
    End If

    If midi_SetChannelEffects(session_Summary, channelIndex, _
        chorusValue, reverbValue) <> 0 Then
        session_Dirty = -1
        Return -1
    Else
        session_SetStatus "Effect edit could not be stored."
        Return 0
    End If
End Function


Private Function session_ReadTempoMapFields( _
    ByRef tick As ULongInt, _
    ByRef beatsPerMinute As Integer, _
    ByRef numerator As Integer, _
    ByRef denominatorPower As Integer, _
    ByRef sharpsFlats As Integer, _
    ByRef minor As Integer _
) As Integer
    If session_TempoMapTickValueLabel = 0 OrElse _
        session_TempoMapBpmBox = 0 OrElse _
        session_TempoMapNumeratorBox = 0 OrElse _
        session_TempoMapDenominatorBox = 0 OrElse _
        session_TempoMapKeyBox = 0 OrElse _
        session_TempoMapMinorBox = 0 Then Return 0

    Dim As ULongInt parsedValue
    If numericText_ParseUnsigned( _
        textbox_GetText(session_TempoMapTickValueLabel), parsedValue, _
        SESSION_AUTOMATION_MAX_TICK) = 0 Then Return 0
    tick = parsedValue

    If numericText_ParseUnsigned( _
        textbox_GetText(session_TempoMapBpmBox), parsedValue, 400) = 0 OrElse _
        parsedValue < 20 Then Return 0
    beatsPerMinute = CInt(parsedValue)

    If numericText_ParseUnsigned( _
        textbox_GetText(session_TempoMapNumeratorBox), parsedValue, 255) = 0 _
        OrElse parsedValue = 0 Then Return 0
    numerator = CInt(parsedValue)

    If numericText_ParseUnsigned( _
        textbox_GetText(session_TempoMapDenominatorBox), parsedValue, 128) = 0 _
        OrElse parsedValue = 0 Then Return 0
    Dim As Integer denominator = CInt(parsedValue)
    denominatorPower = 0
    Dim As Integer denominatorCursor = 1
    While denominatorCursor < denominator AndAlso denominatorPower < 8
        denominatorCursor *= 2
        denominatorPower += 1
    Wend
    If denominatorCursor <> denominator OrElse denominatorPower > 7 Then _
        Return 0

    If numericText_ParseSigned( _
        textbox_GetText(session_TempoMapKeyBox), sharpsFlats, 7) = 0 Then _
        Return 0
    If numericText_ParseUnsigned( _
        textbox_GetText(session_TempoMapMinorBox), parsedValue, 1) = 0 Then _
        Return 0
    minor = CInt(parsedValue)
    Return -1
End Function


Private Function session_ChannelMessageName(ByVal messageType As UByte) As String
    Select Case messageType And &HF0
        Case &HA0
            Return "Poly"
        Case &HB0
            Return "CC"
        Case &HC0
            Return "Program"
        Case &HD0
            Return "Pressure"
        Case &HE0
            Return "Pitch"
    End Select
    Return "Other"
End Function


Private Function session_SystemMessageName(ByVal statusByte As UByte) As String
    Select Case statusByte
        Case &HF1
            Return "MTC"
        Case &HF2
            Return "Song Pos"
        Case &HF3
            Return "Song Sel"
        Case &HF6
            Return "Tune Req"
    End Select
    Return "System"
End Function


Private Sub session_SetAutomationFields( _
    ByRef channelEvent As MidiChannelEventPoint _
)
    If session_AutomationTickBox = 0 Then
        Exit Sub
    End If
    session_AutomationSelectedKind = 0
    textbox_SetText session_AutomationTickBox, Str(channelEvent.tick), -1
    textbox_SetText session_AutomationTrackBox, _
        Str(channelEvent.trackIndex + 1), -1
    textbox_SetText session_AutomationChannelBox, _
        Str(channelEvent.channel + 1), -1
    textbox_SetText session_AutomationTypeBox, _
        Str(channelEvent.messageType), -1
    textbox_SetText session_AutomationData1Box, _
        Str(channelEvent.data1), -1
    textbox_SetText session_AutomationData2Box, _
        Str(channelEvent.data2), -1
End Sub


Private Sub session_SetSystemAutomationFields( _
    ByRef systemEvent As MidiSystemEventPoint _
)
    If session_AutomationTickBox = 0 Then
        Exit Sub
    End If
    session_AutomationSelectedKind = 1
    textbox_SetText session_AutomationTickBox, Str(systemEvent.tick), -1
    textbox_SetText session_AutomationTrackBox, _
        Str(systemEvent.trackIndex + 1), -1
    ' System-common events do not have a MIDI channel. Keep the field
    ' explicit so a later channel-event edit cannot inherit stale input.
    textbox_SetText session_AutomationChannelBox, "0", -1
    textbox_SetText session_AutomationTypeBox, _
        Str(systemEvent.statusByte), -1
    textbox_SetText session_AutomationData1Box, Str(systemEvent.data1), -1
    textbox_SetText session_AutomationData2Box, Str(systemEvent.data2), -1
End Sub


Private Function session_ReadAutomationFields( _
    ByRef channelEvent As MidiChannelEventPoint _
) As Integer
    If session_AutomationTickBox = 0 OrElse _
        session_AutomationTrackBox = 0 OrElse _
        session_AutomationChannelBox = 0 OrElse _
        session_AutomationTypeBox = 0 OrElse _
        session_AutomationData1Box = 0 OrElse _
        session_AutomationData2Box = 0 Then Return 0

    Dim As ULongInt parsedValue
    If numericText_ParseUnsigned( _
        textbox_GetText(session_AutomationTickBox), parsedValue, _
        SESSION_AUTOMATION_MAX_TICK) = 0 Then Return 0
    channelEvent.tick = parsedValue

    If numericText_ParseUnsigned( _
        textbox_GetText(session_AutomationTrackBox), parsedValue, _
        CULngInt(OSE_MAX_MIDI_TRACKS)) = 0 OrElse _
        parsedValue < 1 OrElse parsedValue > CULngInt(session_Summary.trackCount) _
        Then Return 0
    channelEvent.trackIndex = CInt(parsedValue - 1)

    If numericText_ParseUnsigned( _
        textbox_GetText(session_AutomationChannelBox), parsedValue, 16) = 0 _
        OrElse parsedValue < 1 Then Return 0
    channelEvent.channel = CUByte(parsedValue - 1)

    If numericText_ParseUnsigned( _
        textbox_GetText(session_AutomationTypeBox), parsedValue, 255) = 0 _
        Then Return 0
    Select Case CInt(parsedValue)
        Case &HA0, &HB0, &HC0, &HD0, &HE0
            channelEvent.messageType = CUByte(parsedValue)
        Case Else
            Return 0
    End Select

    If numericText_ParseUnsigned( _
        textbox_GetText(session_AutomationData1Box), parsedValue, 127) = 0 _
        Then Return 0
    channelEvent.data1 = CUByte(parsedValue)

    If numericText_ParseUnsigned( _
        textbox_GetText(session_AutomationData2Box), parsedValue, 127) = 0 _
        Then Return 0
    channelEvent.data2 = CUByte(parsedValue)
    Return -1
End Function


Private Function session_ReadSystemAutomationFields( _
    ByRef systemEvent As MidiSystemEventPoint _
) As Integer
    If session_AutomationTickBox = 0 OrElse _
        session_AutomationTrackBox = 0 OrElse _
        session_AutomationTypeBox = 0 OrElse _
        session_AutomationData1Box = 0 OrElse _
        session_AutomationData2Box = 0 Then Return 0

    Dim As ULongInt parsedValue
    If numericText_ParseUnsigned( _
        textbox_GetText(session_AutomationTickBox), parsedValue, _
        SESSION_AUTOMATION_MAX_TICK) = 0 Then Return 0
    systemEvent.tick = parsedValue

    If numericText_ParseUnsigned( _
        textbox_GetText(session_AutomationTrackBox), parsedValue, _
        CULngInt(OSE_MAX_MIDI_TRACKS)) = 0 OrElse _
        parsedValue < 1 OrElse parsedValue > CULngInt(session_Summary.trackCount) _
        Then Return 0
    systemEvent.trackIndex = CInt(parsedValue - 1)

    If numericText_ParseUnsigned( _
        textbox_GetText(session_AutomationTypeBox), parsedValue, 255) = 0 _
        Then Return 0
    Dim As Integer statusByte = CInt(parsedValue)
    Select Case statusByte
        Case &HF1, &HF2, &HF3, &HF6
        Case Else
            Return 0
    End Select
    systemEvent.statusByte = CUByte(statusByte)
    systemEvent.dataLength = 0
    If statusByte = &HF1 OrElse statusByte = &HF3 Then
        systemEvent.dataLength = 1
    ElseIf statusByte = &HF2 Then
        systemEvent.dataLength = 2
    End If

    systemEvent.data1 = 0
    systemEvent.data2 = 0
    If numericText_ParseUnsigned( _
        textbox_GetText(session_AutomationData1Box), parsedValue, 127) = 0 _
        Then Return 0
    systemEvent.data1 = CUByte(parsedValue)
    If numericText_ParseUnsigned( _
        textbox_GetText(session_AutomationData2Box), parsedValue, 127) = 0 _
        Then Return 0
    systemEvent.data2 = CUByte(parsedValue)
    Return -1
End Function


Private Sub session_RefreshAutomationList()
    If session_AutomationList = 0 Then
        Exit Sub
    End If

    Dim As Integer previousSource = session_AutomationSelectedSource
    listbox_Clear session_AutomationList
    session_AutomationSelectedSource = -1
    session_AutomationSelectedKind = 0
    session_AutomationEventRefCount = 0

    Dim As Integer channelEventCount = midi_GetChannelEventCount()
    Dim As Integer systemEventCount = midi_GetSystemEventCount()
    Dim As Integer channelIndex = 0
    Dim As Integer systemIndex = 0
    Dim As Integer hasChannelEvent = 0
    Dim As Integer hasSystemEvent = 0
    Dim As MidiChannelEventPoint nextChannelEvent
    Dim As MidiSystemEventPoint nextSystemEvent
    If channelIndex < channelEventCount AndAlso _
        midi_GetChannelEvent(channelIndex, nextChannelEvent) <> 0 Then _
        hasChannelEvent = -1
    If systemIndex < systemEventCount AndAlso _
        midi_GetSystemEvent(systemIndex, nextSystemEvent) <> 0 Then _
        hasSystemEvent = -1

    Dim As Integer selectedListIndex = -1
    While session_AutomationEventRefCount < _
        SESSION_AUTOMATION_EVENT_MAX AndAlso _
        (hasChannelEvent <> 0 OrElse hasSystemEvent <> 0)
        Dim As Integer chooseSystem = 0
        If hasSystemEvent <> 0 AndAlso _
            (hasChannelEvent = 0 OrElse _
             nextSystemEvent.sourceIndex < nextChannelEvent.sourceIndex) Then
            chooseSystem = -1
        End If

        Dim As Integer listIndex = session_AutomationEventRefCount
        Dim As String rowText
        If chooseSystem = 0 Then
            session_AutomationEventRefs(listIndex).eventKind = 0
            session_AutomationEventRefs(listIndex).eventIndex = channelIndex
            session_AutomationEventRefs(listIndex).sourceIndex = _
                nextChannelEvent.sourceIndex
            rowText = Str(listIndex + 1) + "  CH T" + _
                Str(nextChannelEvent.trackIndex + 1) + "  t=" + _
                Str(nextChannelEvent.tick) + "  CH" + _
                Str(nextChannelEvent.channel + 1) + "  " + _
                session_ChannelMessageName(nextChannelEvent.messageType) + _
                " d1=" + Str(nextChannelEvent.data1) + " d2=" + _
                Str(nextChannelEvent.data2)
            If nextChannelEvent.sourceIndex = previousSource Then _
                selectedListIndex = listIndex
            channelIndex += 1
            hasChannelEvent = 0
            If channelIndex < channelEventCount AndAlso _
                midi_GetChannelEvent(channelIndex, nextChannelEvent) <> 0 Then _
                hasChannelEvent = -1
        Else
            session_AutomationEventRefs(listIndex).eventKind = 1
            session_AutomationEventRefs(listIndex).eventIndex = systemIndex
            session_AutomationEventRefs(listIndex).sourceIndex = _
                nextSystemEvent.sourceIndex
            rowText = Str(listIndex + 1) + "  SYS T" + _
                Str(nextSystemEvent.trackIndex + 1) + "  t=" + _
                Str(nextSystemEvent.tick) + "  " + _
                session_SystemMessageName(nextSystemEvent.statusByte) + _
                " (" + Str(nextSystemEvent.statusByte) + ") d1=" + _
                Str(nextSystemEvent.data1) + " d2=" + _
                Str(nextSystemEvent.data2)
            If nextSystemEvent.sourceIndex = previousSource Then _
                selectedListIndex = listIndex
            systemIndex += 1
            hasSystemEvent = 0
            If systemIndex < systemEventCount AndAlso _
                midi_GetSystemEvent(systemIndex, nextSystemEvent) <> 0 Then _
                hasSystemEvent = -1
        End If
        listbox_AddItem session_AutomationList, rowText
        session_AutomationEventRefCount += 1
    Wend

    If session_AutomationEventRefCount > 0 Then
        If selectedListIndex < 0 Then
            selectedListIndex = 0
        End If
        Dim As ListBoxData Ptr listData = Cast( _
            ListBoxData Ptr, session_AutomationList->data)
        listData->selected_index = selectedListIndex
        Dim As SessionAutomationEventReference selectedReference = _
            session_AutomationEventRefs(selectedListIndex)
        session_AutomationSelectedSource = selectedReference.sourceIndex
        session_AutomationSelectedKind = selectedReference.eventKind
        If selectedReference.eventKind = 0 Then
            Dim As MidiChannelEventPoint selectedChannelEvent
            If midi_GetChannelEvent(selectedReference.eventIndex, _
                selectedChannelEvent) <> 0 Then
                session_SetAutomationFields selectedChannelEvent
            End If
        Else
            Dim As MidiSystemEventPoint selectedSystemEvent
            If midi_GetSystemEvent(selectedReference.eventIndex, _
                selectedSystemEvent) <> 0 Then
                session_SetSystemAutomationFields selectedSystemEvent
            End If
        End If
    End If
End Sub


Private Sub session_UpdateAutomationSelection()
    If session_AutomationList = 0 Then
        Exit Sub
    End If
    Dim As Integer eventIndex = listbox_GetSelectedIndex(session_AutomationList)
    If eventIndex < 0 OrElse _
        eventIndex >= session_AutomationEventRefCount Then Exit Sub

    Dim As SessionAutomationEventReference selectedReference = _
        session_AutomationEventRefs(eventIndex)
    If selectedReference.sourceIndex <> session_AutomationSelectedSource OrElse _
        selectedReference.eventKind <> session_AutomationSelectedKind Then
        session_AutomationSelectedSource = selectedReference.sourceIndex
        session_AutomationSelectedKind = selectedReference.eventKind
        If selectedReference.eventKind = 0 Then
            Dim As MidiChannelEventPoint channelEvent
            If midi_GetChannelEvent(selectedReference.eventIndex, channelEvent) _
                <> 0 Then session_SetAutomationFields channelEvent
        Else
            Dim As MidiSystemEventPoint systemEvent
            If midi_GetSystemEvent(selectedReference.eventIndex, systemEvent) _
                <> 0 Then session_SetSystemAutomationFields systemEvent
        End If
    End If
End Sub


Private Function session_GetSelectedChannelAutomation( _
    ByRef channelEvent As MidiChannelEventPoint _
) As Integer
    For referenceIndex As Integer = 0 To session_AutomationEventRefCount - 1
        With session_AutomationEventRefs(referenceIndex)
            If .eventKind = 0 AndAlso _
                .sourceIndex = session_AutomationSelectedSource Then
                Return midi_GetChannelEvent(.eventIndex, channelEvent)
            End If
        End With
    Next
    Return 0
End Function


Private Function session_GetSelectedSystemAutomation( _
    ByRef systemEvent As MidiSystemEventPoint _
) As Integer
    For referenceIndex As Integer = 0 To session_AutomationEventRefCount - 1
        With session_AutomationEventRefs(referenceIndex)
            If .eventKind <> 0 AndAlso _
                .sourceIndex = session_AutomationSelectedSource Then
                Return midi_GetSystemEvent(.eventIndex, systemEvent)
            End If
        End With
    Next
    Return 0
End Function


Private Function session_ChannelAutomationEqual( _
    ByRef firstEvent As MidiChannelEventPoint, _
    ByRef secondEvent As MidiChannelEventPoint _
) As Integer
    If firstEvent.tick <> secondEvent.tick Then
        Return 0
    End If
    If firstEvent.trackIndex <> secondEvent.trackIndex Then
        Return 0
    End If
    If firstEvent.channel <> secondEvent.channel Then
        Return 0
    End If
    If firstEvent.messageType <> secondEvent.messageType Then
        Return 0
    End If
    If firstEvent.data1 <> secondEvent.data1 Then
        Return 0
    End If
    If firstEvent.messageType <> &HC0 AndAlso _
        firstEvent.messageType <> &HD0 AndAlso _
        firstEvent.data2 <> secondEvent.data2 Then Return 0
    Return -1
End Function


Private Function session_SystemAutomationEqual( _
    ByRef firstEvent As MidiSystemEventPoint, _
    ByRef secondEvent As MidiSystemEventPoint _
) As Integer
    If firstEvent.tick <> secondEvent.tick Then
        Return 0
    End If
    If firstEvent.trackIndex <> secondEvent.trackIndex Then
        Return 0
    End If
    If firstEvent.statusByte <> secondEvent.statusByte Then
        Return 0
    End If
    If firstEvent.dataLength <> secondEvent.dataLength Then
        Return 0
    End If
    If firstEvent.dataLength >= 1 AndAlso _
        firstEvent.data1 <> secondEvent.data1 Then Return 0
    If firstEvent.dataLength >= 2 AndAlso _
        firstEvent.data2 <> secondEvent.data2 Then Return 0
    Return -1
End Function


Private Sub session_NoteAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_NoteWindow = 0 Then
        Exit Sub
    End If
    gui_AddGeneratedWidget child
    gui_SetParent child, session_NoteWindow
End Sub


Private Sub session_TempoMapAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_TempoMapWindow = 0 Then
        Exit Sub
    End If
    gui_AddGeneratedWidget child
    gui_SetParent child, session_TempoMapWindow
End Sub


Private Sub session_TrackPropertiesAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_TrackWindow = 0 Then
        Exit Sub
    End If
    gui_AddGeneratedWidget child
    gui_SetParent child, session_TrackWindow
End Sub


Private Sub session_SetNoteFields(ByRef editableNote As MidiEditableNote)
    If session_NoteWindow = 0 Then
        Exit Sub
    End If
    textbox_SetText session_NoteTickBox, Str(editableNote.startTick), -1
    textbox_SetText session_NoteDurationBox, Str(editableNote.durationTicks), -1
    textbox_SetText session_NoteTrackBox, Str(editableNote.trackIndex + 1), -1
    textbox_SetText session_NoteChannelBox, Str(editableNote.channel + 1), -1
    textbox_SetText session_NotePitchBox, Str(editableNote.keyNumber), -1
    textbox_SetText session_NoteVelocityBox, Str(editableNote.velocity), -1
End Sub


Private Function session_ReadNoteFields( _
    ByRef editableNote As MidiEditableNote _
) As Integer
    If session_NoteWindow = 0 OrElse _
        session_NoteTickBox = 0 OrElse session_NoteDurationBox = 0 OrElse _
        session_NoteTrackBox = 0 OrElse session_NoteChannelBox = 0 OrElse _
        session_NotePitchBox = 0 OrElse session_NoteVelocityBox = 0 Then
        Return 0
    End If

    Dim As ULongInt parsedValue
    If numericText_ParseUnsigned( _
        textbox_GetText(session_NoteTickBox), parsedValue, _
        SESSION_AUTOMATION_MAX_TICK) = 0 Then Return 0
    editableNote.startTick = parsedValue

    Dim As ULongInt maximumDuration = _
        SESSION_AUTOMATION_MAX_TICK - editableNote.startTick
    If maximumDuration = 0 OrElse numericText_ParseUnsigned( _
        textbox_GetText(session_NoteDurationBox), parsedValue, _
        maximumDuration) = 0 OrElse parsedValue = 0 Then Return 0
    editableNote.durationTicks = parsedValue

    If numericText_ParseUnsigned( _
        textbox_GetText(session_NoteTrackBox), parsedValue, _
        CULngInt(session_Summary.trackCount)) = 0 OrElse parsedValue = 0 Then _
        Return 0
    editableNote.trackIndex = CInt(parsedValue - 1)

    If numericText_ParseUnsigned( _
        textbox_GetText(session_NoteChannelBox), parsedValue, 16) = 0 OrElse _
        parsedValue = 0 Then Return 0
    editableNote.channel = CUByte(parsedValue - 1)

    If numericText_ParseUnsigned( _
        textbox_GetText(session_NotePitchBox), parsedValue, 127) = 0 Then _
        Return 0
    editableNote.keyNumber = CUByte(parsedValue)

    If numericText_ParseUnsigned( _
        textbox_GetText(session_NoteVelocityBox), parsedValue, 127) = 0 OrElse _
        parsedValue = 0 Then Return 0
    editableNote.velocity = CUByte(parsedValue)
    Return -1
End Function


Private Sub session_RefreshTrackList()
    If session_TrackList = 0 Then
        Exit Sub
    End If
    Dim As Integer previousTrack = session_SelectedTrack
    listbox_Clear session_TrackList
    For trackIndex As Integer = 0 To session_Summary.trackCount - 1
        Dim As String trackText = Str(trackIndex + 1) + "  " + _
            midi_TrackDisplayName(session_Summary, trackIndex)
        listbox_AddItem session_TrackList, trackText
    Next
    If session_TrackList->data <> 0 AndAlso _
        previousTrack >= 0 AndAlso previousTrack < session_Summary.trackCount Then
        Dim As ListBoxData Ptr listData = Cast( _
            ListBoxData Ptr, session_TrackList->data)
        If previousTrack < listData->item_count Then
            listData->selected_index = previousTrack
        End If
    End If
End Sub


Private Sub session_SelectTrack(ByVal trackIndex As Integer)
    If trackIndex < 0 OrElse trackIndex >= session_Summary.trackCount Then
        Exit Sub
    End If
    If session_TrackList <> 0 AndAlso session_TrackList->data <> 0 Then
        Dim As ListBoxData Ptr trackData = Cast( _
            ListBoxData Ptr, session_TrackList->data)
        If trackIndex < trackData->item_count Then
            trackData->selected_index = trackIndex
        End If
    End If
    session_SelectedTrack = trackIndex
    session_SelectedNote = -1
    session_ScoreDragNote = -1
End Sub


Private Sub session_RebuildScoreLayout()
    scoreLayout_BeginDocument session_ScoreLayout, session_Summary.trackCount
    For noteIndex As Integer = 0 To midi_GetEditableNoteCount() - 1
        Dim As MidiEditableNote editableNote
        If midi_GetEditableNote(noteIndex, editableNote) <> 0 Then
            scoreLayout_ObserveInitialPitch session_ScoreLayout, _
                editableNote.trackIndex, editableNote.keyNumber
        End If
    Next
    scoreLayout_FinalizeDocument session_ScoreLayout
End Sub


Private Function session_LoadMidi( _
    ByVal filename As String, _
    ByVal preserveAudio As Integer = 0 _
) As Integer
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    If session_AudioCaptureActive <> 0 Then
        session_FinishAudioCapture()
    End If
    If midi_LoadSummary(session_Summary, filename) = 0 Then
        session_SetStatus "Load failed: " + session_Summary.errorText
        Return 0
    End If

    If preserveAudio = 0 Then
        audio_Clear()
        session_LoadAudioSamples()
        session_ProjectFilename = ""
    End If
    session_Filename = filename
    If midiInput_IsOpen() <> 0 Then
        midiInput_ClearPending()
    End If
    session_SelectedTrack = 0
    session_SelectedNote = -1
    session_ScoreDragNote = -1
    session_ViewStartTick = 0
    session_ScoreFirstVisibleTrack = 0
    session_Dirty = 0
    documentHistory_Clear session_DocumentHistory
    session_PlaybackChannelOrderDirty = -1
    session_RebuildScoreLayout()
    mixerState_Initialize session_MixerChannels
    For channelIndex As Integer = 0 To SESSION_CHANNEL_COUNT - 1
        session_ChannelVolume(channelIndex) = _
            CSng(session_Summary.channelVolume(channelIndex)) / 127.0
        session_ChannelPan(channelIndex) = _
            (CSng(session_Summary.channelPan(channelIndex)) - 64.0) / 63.0
        If session_ChannelPan(channelIndex) < -1.0 Then _
            session_ChannelPan(channelIndex) = -1.0
        If session_ChannelPan(channelIndex) > 1.0 Then _
            session_ChannelPan(channelIndex) = 1.0
        session_ChannelChorus(channelIndex) = _
            CSng(session_Summary.channelChorus(channelIndex)) / 127.0
        session_ChannelReverb(channelIndex) = _
            CSng(session_Summary.channelReverb(channelIndex)) / 127.0
    Next
    session_StepEntryTick = session_Summary.durationTicks
    For keyIndex As Integer = 0 To 127
        session_StepEntryLastState(keyIndex) = 0
    Next
    session_RefreshTrackList()
    session_SelectTrack 0
    session_RefreshTempoBox()
    session_SetStatus "Loaded " + session_LeafFilename(filename) + " | " + _
        Str(session_Summary.trackCount) + " tracks | " + _
        Str(session_Summary.noteCount) + " notes"
    Return -1
End Function


Private Function session_LoadAudioSamples() As Integer
    Return audioSampleSlots_Synchronize()
End Function


Private Function session_AudioAvailabilitySuffix() As String
    Dim As Integer unavailableCount = _
        audioSampleSlots_GetUnavailableCount()
    If unavailableCount <= 0 Then
        Return ""
    End If
    If unavailableCount = 1 Then
        Return " | 1 audio clip offline"
    End If
    Return " | " + LTrim(Str(unavailableCount)) + " audio clips offline"
End Function


Private Sub session_SetAudioFields(ByRef clip As OseAudioClip)
    If session_AudioTickBox = 0 OrElse session_AudioGainBox = 0 Then
        Exit Sub
    End If
    textbox_SetText session_AudioTickBox, Str(clip.startTick), -1
    textbox_SetText session_AudioGainBox, Str(clip.gainPermille), -1
End Sub


Private Sub session_RefreshAudioList()
    If session_AudioList = 0 Then
        Exit Sub
    End If
    Dim As Integer previousIndex = session_AudioSelectedIndex
    listbox_Clear session_AudioList
    session_AudioSelectedIndex = -1
    For clipIndex As Integer = 0 To audio_GetCount() - 1
        Dim As OseAudioClip clip
        If audio_GetClip(clipIndex, clip) = 0 Then
            Continue For
        End If
        Dim As String displayName = clip.filename
        If Len(displayName) > 72 Then
            displayName = Left(displayName, 69) + "..."
        End If
        Dim As String availabilityText
        If audioSampleSlots_IsAvailable(clipIndex) = 0 Then _
            availabilityText = "  [offline]"
        listbox_AddItem session_AudioList, Str(clipIndex + 1) + _
            "  tick=" + Str(clip.startTick) + "  " + displayName + _
            availabilityText
    Next
    If audio_GetCount() > 0 AndAlso session_AudioList->data <> 0 Then
        Dim As ListBoxData Ptr listData = Cast( _
            ListBoxData Ptr, session_AudioList->data)
        If previousIndex < 0 Then
            previousIndex = 0
        End If
        If previousIndex >= audio_GetCount() Then _
            previousIndex = audio_GetCount() - 1
        listData->selected_index = previousIndex
        session_AudioSelectedIndex = previousIndex
        Dim As OseAudioClip selectedClip
        If audio_GetClip(previousIndex, selectedClip) <> 0 Then _
            session_SetAudioFields selectedClip
    End If
End Sub


Private Sub session_UpdateAudioSelection()
    If session_AudioList = 0 Then
        Exit Sub
    End If
    Dim As Integer selectedIndex = listbox_GetSelectedIndex(session_AudioList)
    If selectedIndex < 0 OrElse selectedIndex >= audio_GetCount() Then
        Exit Sub
    End If
    If selectedIndex = session_AudioSelectedIndex Then
        Exit Sub
    End If
    Dim As OseAudioClip clip
    If audio_GetClip(selectedIndex, clip) = 0 Then
        Exit Sub
    End If
    session_AudioSelectedIndex = selectedIndex
    session_SetAudioFields clip
End Sub


Private Function session_ReadAudioFields( _
    ByRef clip As OseAudioClip _
) As Integer
    If session_AudioWindow = 0 OrElse session_AudioTickBox = 0 OrElse _
        session_AudioGainBox = 0 OrElse session_AudioSelectedIndex < 0 Then _
        Return 0
    If audio_GetClip(session_AudioSelectedIndex, clip) = 0 Then
        Return 0
    End If

    Dim As ULongInt parsedValue
    If numericText_ParseUnsigned(textbox_GetText(session_AudioTickBox), _
        parsedValue, OSE_AUDIO_TIMELINE_MAX_TICK) = 0 Then Return 0
    clip.startTick = parsedValue
    If numericText_ParseUnsigned(textbox_GetText(session_AudioGainBox), _
        parsedValue, 1000) = 0 Then Return 0
    clip.gainPermille = CInt(parsedValue)
    Return -1
End Function


Private Function session_AudioClipFieldsEqual( _
    ByRef firstClip As OseAudioClip, _
    ByRef secondClip As OseAudioClip _
) As Integer
    If firstClip.filename <> secondClip.filename Then
        Return 0
    End If
    If firstClip.startTick <> secondClip.startTick Then
        Return 0
    End If
    If firstClip.durationMilliseconds <> secondClip.durationMilliseconds Then _
        Return 0
    If firstClip.gainPermille <> secondClip.gainPermille Then
        Return 0
    End If
    If firstClip.waveInfo.audioFormat <> secondClip.waveInfo.audioFormat Then _
        Return 0
    If firstClip.waveInfo.channelCount <> secondClip.waveInfo.channelCount Then _
        Return 0
    If firstClip.waveInfo.sampleRate <> secondClip.waveInfo.sampleRate Then
        Return 0
    End If
    If firstClip.waveInfo.bitsPerSample <> secondClip.waveInfo.bitsPerSample Then _
        Return 0
    If firstClip.waveInfo.sampleFrames <> secondClip.waveInfo.sampleFrames Then _
        Return 0
    If firstClip.waveInfo.dataBytes <> secondClip.waveInfo.dataBytes Then
        Return 0
    End If
    If firstClip.waveInfo.durationMilliseconds <> _
        secondClip.waveInfo.durationMilliseconds Then Return 0
    Return -1
End Function


Private Function session_LoadProjectFile(ByVal projectFilename As String) As Integer
    Dim As String transactionError
    If projectTransaction_Recover(projectFilename, transactionError) = 0 Then
        session_SetStatus "Project recovery failed: " + transactionError
        Return 0
    End If
    Dim As String midiFilename
    If audio_LoadProject(projectFilename, midiFilename, -1) = 0 Then
        session_SetStatus "Project load failed: " + projectFilename
        Return 0
    End If
    If midiFilename = "" OrElse session_LoadMidi(midiFilename, -1) = 0 Then
        audio_CancelPreparedHistory()
        session_LoadAudioSamples()
        session_SetStatus "Project MIDI file could not be loaded: " + midiFilename
        Return 0
    End If
    documentHistory_Clear session_DocumentHistory
    session_ProjectFilename = projectFilename
    session_LoadAudioSamples()
    session_RefreshAudioList()
    session_Dirty = 0
    session_SetStatus "Loaded OpenSesh project: " + projectFilename + _
        session_AudioAvailabilitySuffix()
    Return -1
End Function


Private Sub session_StopPlayback()
    For voiceChannel As Integer = 0 To SESSION_CHANNEL_COUNT - 1
        ' SFX STOP handles loaded samples; generated tones and percussion have
        ' separate runtime stop operations and must end before timing changes.
        SFX STOP CHANNEL, voiceChannel
        generatedVoiceStop_Channel voiceChannel
    Next
    soundfontSynth_StopAll()
    midiOutput_AllNotesOff()
    If session_WavExport.active <> 0 AndAlso _
        session_WavExportFinishing = 0 Then _
        wavExport_Cancel session_WavExport
    session_Playing = 0
    session_Paused = 0
    session_PlaybackElapsed = 0.0
    session_PlaybackLastTick = 0
    session_PlaybackFirstUpdate = 0
    session_SelectedNotePlaybackActive = 0
    session_SelectedNoteLooping = 0
    session_SelectedNoteLoopEnd = 0
    selectedNotePlayback_Initialize session_SelectedNotePlayback
    mixerMeter_StopAll session_MixerMeter
    session_ApplyMixerState()
End Sub


Private Function session_RequireStoppedTiming() As Integer
    ' Both synth backends receive a duration when a note starts. Pausing keeps
    ' those voices, so a new speed or tempo is accepted only between runs.
    If session_Playing <> 0 OrElse session_Paused <> 0 OrElse _
        session_WavExport.active <> 0 Then
        session_SetStatus "Press Stop before changing playback speed or tempo."
        Return 0
    End If
    If session_LiveRecording <> 0 Then
        session_SetStatus "Stop recording before changing playback speed or tempo."
        Return 0
    End If
    If session_PhraseLooping <> 0 Then
        session_SetStatus "Stop the drum loop before changing playback speed or tempo."
        Return 0
    End If
    ' Piano and one-shot drum previews use fixed wall durations. They do not
    ' read this transport multiplier; Play stops previews before a new run.
    Return -1
End Function


Private Function session_RequireArrangementAudioSpeed() As Integer
    ' WAV clips retain their original sample rate and duration. A faster
    ' score clock would move their starts and cut their tails short.
    If audio_GetCount() = 0 OrElse session_PlaybackSpeedScale = 1.0 Then
        Return -1
    End If
    session_SetStatus "Full playback with WAV clips requires 1x. Press Stop, then Play."
    Return 0
End Function


Private Function session_CreateNewDocument() As Integer
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    If session_AudioCaptureActive <> 0 Then
        session_FinishAudioCapture()
    End If
    session_StopPlayback()
    If midi_NewDocument(session_Summary) = 0 Then
        session_SetStatus "Could not create a new MIDI document."
        Return 0
    End If

    session_Filename = ""
    session_ProjectFilename = ""
    If midiInput_IsOpen() <> 0 Then
        midiInput_ClearPending()
    End If
    audio_Clear()
    session_LoadAudioSamples()
    session_SelectedTrack = 0
    session_SelectedNote = -1
    session_ScoreDragNote = -1
    session_ViewStartTick = 0
    session_ScoreFirstVisibleTrack = 0
    session_Dirty = 0
    documentHistory_Clear session_DocumentHistory
    session_PlaybackChannelOrderDirty = -1
    session_RebuildScoreLayout()
    mixerState_Initialize session_MixerChannels
    For channelIndex As Integer = 0 To SESSION_CHANNEL_COUNT - 1
        session_ChannelVolume(channelIndex) = _
            CSng(session_Summary.channelVolume(channelIndex)) / 127.0
        session_ChannelPan(channelIndex) = _
            (CSng(session_Summary.channelPan(channelIndex)) - 64.0) / 63.0
        session_ChannelChorus(channelIndex) = _
            CSng(session_Summary.channelChorus(channelIndex)) / 127.0
        session_ChannelReverb(channelIndex) = _
            CSng(session_Summary.channelReverb(channelIndex)) / 127.0
    Next
    session_StepEntryTick = 0
    For keyIndex As Integer = 0 To 127
        session_StepEntryLastState(keyIndex) = 0
    Next
    session_RefreshTrackList()
    session_SelectTrack 0
    session_RefreshTempoBox()
    session_SetStatus "New empty MIDI document."
    Return -1
End Function


Private Function session_ViewTicks() As ULongInt
    Dim As ULongInt ticks = CULngInt(session_Summary.division) * _
        CULngInt(session_ViewBeatCount)
    If ticks = 0 Then
        ticks = CULngInt(session_ViewBeatCount)
    End If
    Return ticks
End Function


Private Function session_NoteIsVisible( _
    ByRef editableNote As MidiEditableNote _
) As Integer
    Dim As ULongInt viewEndTick = session_ViewStartTick + session_ViewTicks()
    Dim As ULongInt noteEndTick = editableNote.startTick + _
        editableNote.durationTicks
    If noteEndTick < editableNote.startTick Then
        noteEndTick = viewEndTick
    End If
    If editableNote.startTick > viewEndTick Then
        Return 0
    End If
    If noteEndTick < session_ViewStartTick Then
        Return 0
    End If
    Return -1
End Function


Private Function session_NoteScreenWidth( _
    ByRef editableNote As MidiEditableNote, _
    ByVal scoreWidth As Integer _
) As Integer
    Dim As ULongInt ticksInView = session_ViewTicks()
    Dim As ULongInt noteEndTick = editableNote.startTick + _
        editableNote.durationTicks
    Dim As ULongInt visibleStart = editableNote.startTick
    Dim As ULongInt visibleEnd = noteEndTick
    Dim As ULongInt viewEndTick = session_ViewStartTick + ticksInView
    If visibleStart < session_ViewStartTick Then
        visibleStart = session_ViewStartTick
    End If
    If visibleEnd > viewEndTick Then
        visibleEnd = viewEndTick
    End If
    If visibleEnd <= visibleStart Then
        Return 4
    End If

    Dim As Integer timelineWidth = scoreWidth - SESSION_SCORE_NOTE_LEFT - _
        SESSION_SCORE_NOTE_RIGHT
    If timelineWidth <= 0 Then
        Return 4
    End If
    Dim As Integer noteWidthPixels = CInt((CDbl(timelineWidth) * _
        CDbl(visibleEnd - visibleStart)) / CDbl(ticksInView))
    If noteWidthPixels < 4 Then
        noteWidthPixels = 4
    End If
    Return noteWidthPixels
End Function


Private Function session_TimelineDurationTicks() As ULongInt
    Dim As ULongInt timelineDuration = session_Summary.durationTicks
    For clipIndex As Integer = 0 To audio_GetCount() - 1
        Dim As OseAudioClip clip
        If audio_GetClip(clipIndex, clip) = 0 Then
            Continue For
        End If
        Dim As Double clipEndSeconds = midi_TicksToSeconds( _
            session_Summary, clip.startTick) + _
            CDbl(clip.durationMilliseconds) / 1000.0
        Dim As ULongInt clipEndTick = midi_SecondsToTicks( _
            session_Summary, clipEndSeconds)
        If clipEndTick < clip.startTick Then _
            clipEndTick = OSE_MAX_MIDI_TICK
        If clipEndTick > timelineDuration Then
            timelineDuration = clipEndTick
        End If
    Next
    Return timelineDuration
End Function


Private Sub session_ScrollScore(ByVal wheelDelta As Integer)
    If wheelDelta = 0 OrElse session_Summary.division <= 0 Then
        Exit Sub
    End If

    Dim As ULongInt stepTicks = CULngInt(session_Summary.division) * 4
    Dim As ULongInt viewTicks = session_ViewTicks()
    Dim As ULongInt maximumStart = 0
    Dim As ULongInt timelineDuration = session_TimelineDurationTicks()
    If timelineDuration > viewTicks Then
        maximumStart = timelineDuration - viewTicks
    End If

    If wheelDelta > 0 Then
        If session_ViewStartTick > stepTicks Then
            session_ViewStartTick -= stepTicks
        Else
            session_ViewStartTick = 0
        End If
    Else
        If session_ViewStartTick >= maximumStart Then
            session_ViewStartTick = maximumStart
        ElseIf maximumStart - session_ViewStartTick < stepTicks Then
            session_ViewStartTick = maximumStart
        Else
            session_ViewStartTick += stepTicks
        End If
    End If
End Sub


Private Sub session_ScrollScoreTracks( _
    ByVal wheelDelta As Integer, _
    ByVal screenHeight As Integer _
)
    If wheelDelta = 0 OrElse session_Summary.trackCount <= 0 Then
        Exit Sub
    End If
    Dim As Integer visibleCount = session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer maximumFirst = session_Summary.trackCount - visibleCount
    If maximumFirst < 0 Then
        maximumFirst = 0
    End If
    If wheelDelta > 0 Then
        If session_ScoreFirstVisibleTrack > 0 Then _
            session_ScoreFirstVisibleTrack -= 1
    Else
        If session_ScoreFirstVisibleTrack < maximumFirst Then _
            session_ScoreFirstVisibleTrack += 1
    End If
End Sub


Private Sub session_ConfigureSynth()
    softwareSynth_Configure()
End Sub


Private Function session_ChannelIsAudible(ByVal channelIndex As Integer) As Integer
    Return mixerState_IsAudible(session_MixerChannels, channelIndex)
End Function


Private Sub session_ApplyMixerState()
    For voiceChannel As Integer = 0 To SESSION_CHANNEL_COUNT - 1
        Dim As Integer channelAudible = session_ChannelIsAudible(voiceChannel)
        If session_Playing <> 0 Then
            Dim As OsePlaybackMixValues playbackValues
            playbackMix_Calculate playbackValues, _
                session_PlaybackState.controllerVolume(voiceChannel), _
                session_PlaybackState.controllerExpression(voiceChannel), _
                session_PlaybackState.controllerPan(voiceChannel), 127, _
                session_MasterVolume, channelAudible
            volume voiceChannel, playbackValues.channelGain
            pan voiceChannel, playbackValues.pan
            soundfontSynth_SetChannelMix voiceChannel, _
                playbackValues.channelGain, playbackValues.pan
            mixerMeter_SetChannelMix session_MixerMeter, voiceChannel, _
                playbackValues.meterGain, playbackValues.pan, channelAudible
        Else
            Dim As Single channelVolume = session_ChannelVolume(voiceChannel) * _
                session_MasterVolume
            If channelAudible = 0 Then
                channelVolume = 0.0
            End If
            volume voiceChannel, channelVolume
            pan voiceChannel, session_ChannelPan(voiceChannel)
            soundfontSynth_SetChannelMix voiceChannel, channelVolume, _
                session_ChannelPan(voiceChannel)
            mixerMeter_SetChannelMix session_MixerMeter, voiceChannel, _
                session_ChannelVolume(voiceChannel), _
                session_ChannelPan(voiceChannel), channelAudible
        End If
    Next
    ' Fallback notes use physical mixer channels as a rotating voice pool.
    ' Reapply the source MIDI channel's live controls so mute, solo, CC mix,
    ' and pan continue to follow the track that owns each sustained voice.
    For fallbackVoice As Integer = 0 To OSE_SOFTWARE_SYNTH_VOICE_COUNT - 1
        Dim As Integer mixerChannel = _
            softwareSynth_MixerChannelForVoice(fallbackVoice)
        If mixerChannel < 0 OrElse _
            mixerChannel >= SESSION_CHANNEL_COUNT Then
            Continue For
        End If
        Dim As Integer channelAudible = _
            session_ChannelIsAudible(mixerChannel)
        If session_Playing <> 0 Then
            Dim As OsePlaybackMixValues playbackValues
            playbackMix_Calculate playbackValues, _
                session_PlaybackState.controllerVolume(mixerChannel), _
                session_PlaybackState.controllerExpression(mixerChannel), _
                session_PlaybackState.controllerPan(mixerChannel), 127, _
                session_MasterVolume, channelAudible
            volume fallbackVoice, playbackValues.channelGain
            pan fallbackVoice, playbackValues.pan
        Else
            Dim As Single channelVolume = _
                session_ChannelVolume(mixerChannel) * session_MasterVolume
            If channelAudible = 0 Then channelVolume = 0.0
            volume fallbackVoice, channelVolume
            pan fallbackVoice, session_ChannelPan(mixerChannel)
        End If
    Next
    mixerMeter_SetMasterVolume session_MixerMeter, session_MasterVolume
End Sub


Private Sub session_ApplyMasterEffect()
    Dim As String effectError
    If masterEffect_Apply(session_MasterEchoWet, _
        session_MasterEchoFeedback, effectError) = 0 Then
        session_SetStatus "Master effect failed: " + effectError
    End If
End Sub


' -------------------------------------------------------------------------
' Playback channel state
' -------------------------------------------------------------------------

Private Function session_PlaybackChannelEventBefore( _
    ByRef leftEvent As MidiChannelEventPoint, _
    ByRef rightEvent As MidiChannelEventPoint _
) As Integer
    If leftEvent.tick < rightEvent.tick Then
        Return -1
    End If
    If leftEvent.tick > rightEvent.tick Then
        Return 0
    End If
    If leftEvent.trackIndex < rightEvent.trackIndex Then
        Return -1
    End If
    If leftEvent.trackIndex > rightEvent.trackIndex Then
        Return 0
    End If
    Return leftEvent.sourceIndex < rightEvent.sourceIndex
End Function


Private Sub session_SortPlaybackChannelEvents( _
    events() As MidiChannelEventPoint, _
    ByVal lowIndex As Integer, _
    ByVal highIndex As Integer _
)
    If lowIndex >= highIndex Then
        Exit Sub
    End If

    Dim As Integer leftIndex = lowIndex
    Dim As Integer rightIndex = highIndex
    Dim As MidiChannelEventPoint pivot = _
        events(lowIndex + (highIndex - lowIndex) \ 2)

    Do
        While leftIndex <= highIndex AndAlso _
            session_PlaybackChannelEventBefore(events(leftIndex), pivot) <> 0
            leftIndex += 1
        Wend
        While rightIndex >= lowIndex AndAlso _
            session_PlaybackChannelEventBefore(pivot, events(rightIndex)) <> 0
            rightIndex -= 1
        Wend
        If leftIndex <= rightIndex Then
            Swap events(leftIndex), events(rightIndex)
            leftIndex += 1
            rightIndex -= 1
        End If
    Loop While leftIndex <= rightIndex

    If lowIndex < rightIndex Then _
        session_SortPlaybackChannelEvents events(), lowIndex, rightIndex
    If leftIndex < highIndex Then _
        session_SortPlaybackChannelEvents events(), leftIndex, highIndex
End Sub


Private Sub session_RebuildPlaybackChannelEventOrder()
    If session_PlaybackChannelOrderDirty = 0 Then
        Exit Sub
    End If

    Erase session_PlaybackOrderedChannelEvents
    session_PlaybackOrderedChannelEventCount = 0
    Dim As Integer eventCount = midi_GetChannelEventCount()
    If eventCount <= 0 Then
        session_PlaybackChannelOrderDirty = 0
        Exit Sub
    End If

    Redim session_PlaybackOrderedChannelEvents(0 To eventCount - 1)
    For eventIndex As Integer = 0 To eventCount - 1
        Dim As MidiChannelEventPoint channelEvent
        If midi_GetChannelEvent(eventIndex, channelEvent) = 0 Then
            Continue For
        End If
        session_PlaybackOrderedChannelEvents( _
            session_PlaybackOrderedChannelEventCount) = channelEvent
        session_PlaybackOrderedChannelEventCount += 1
    Next

    If session_PlaybackOrderedChannelEventCount > 1 Then
        session_SortPlaybackChannelEvents _
            session_PlaybackOrderedChannelEvents(), 0, _
            session_PlaybackOrderedChannelEventCount - 1
    End If
    session_PlaybackChannelOrderDirty = 0
End Sub


Private Sub session_ResetPlaybackChannelState()
    playbackState_Initialize session_PlaybackState
End Sub


Private Sub session_ApplyPlaybackChannelEvent( _
    ByRef channelEvent As MidiChannelEventPoint _
)
    playbackState_Apply session_PlaybackState, channelEvent
End Sub


Private Sub session_ApplyPlaybackChannelEvents( _
    ByVal currentTick As ULongInt, _
    ByVal previousTick As ULongInt, _
    ByVal firstUpdate As Integer _
)
    session_RebuildPlaybackChannelEventOrder()
    For eventIndex As Integer = 0 To _
        session_PlaybackOrderedChannelEventCount - 1
        Dim As MidiChannelEventPoint channelEvent = _
            session_PlaybackOrderedChannelEvents(eventIndex)

        Dim As Integer inRange = 0
        If firstUpdate <> 0 Then
            If channelEvent.tick <= currentTick Then
                inRange = -1
            End If
        ElseIf channelEvent.tick > previousTick AndAlso _
            channelEvent.tick <= currentTick Then
            inRange = -1
        End If
        If inRange <> 0 Then
            session_ApplyPlaybackChannelEvent channelEvent
        End If
    Next
End Sub


' -------------------------------------------------------------------------
' Arrangement and selected-note playback source
' -------------------------------------------------------------------------

Private Function session_PlaybackNoteCount() As Integer
    If session_SelectedNotePlaybackActive <> 0 Then _
        Return session_SelectedNotePlayback.count
    Return midi_GetEditableNoteCount()
End Function


Private Function session_GetPlaybackNote( _
    ByVal playbackIndex As Integer, _
    ByRef editableNote As MidiEditableNote _
) As Integer
    If session_SelectedNotePlaybackActive <> 0 Then
        Return selectedNotePlayback_GetNote( _
            session_SelectedNotePlayback, playbackIndex, editableNote)
    End If
    Return midi_GetEditableNote(playbackIndex, editableNote)
End Function


Private Function session_PlaybackEndTick() As ULongInt
    If session_SelectedNotePlaybackActive <> 0 AndAlso session_SelectedNoteLooping <> 0 Then _
        Return session_SelectedNoteLoopEnd
    If session_SelectedNotePlaybackActive <> 0 Then _
        Return session_SelectedNotePlayback.endTick
    Return session_TimelineDurationTicks()
End Function


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


' -------------------------------------------------------------------------
' Coarse-pointer score gestures
' -------------------------------------------------------------------------

Private Sub session_HandleTouchScoreTap( _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    If session_HandleAddPaletteClick(pointerX, pointerY) <> 0 Then
        Exit Sub
    End If
    If session_HandleScoreToolClick(pointerX, pointerY) <> 0 Then
        Exit Sub
    End If

    Dim As Integer scoreBottom = screenHeight - SESSION_MIXER_HEIGHT
    If pointerX < SESSION_SCORE_LEFT + 12 OrElse _
        pointerX >= screenWidth - 8 OrElse _
        pointerY < SESSION_SCORE_TOP + 26 OrElse _
        pointerY >= scoreBottom - SESSION_SCORE_SCROLLBAR_SIZE - 4 Then _
        Exit Sub

    Dim As Integer clickedTrack = session_ScoreTrackFromY( _
        pointerY, screenHeight)
    If clickedTrack >= 0 Then _
        session_SetSelectedTrackPreservingNotes clickedTrack
    Dim As Integer clickedNote = session_FindNoteAt( _
        pointerX, pointerY, screenWidth, screenHeight)

    Select Case session_ActiveScoreTool
        Case SESSION_SCORE_TOOL_ADD_NOTE
            If clickedTrack >= 0 Then
                session_SelectTrack clickedTrack
                session_AddScoreNoteAt pointerX, pointerY, _
                    screenWidth, screenHeight
            End If

        Case SESSION_SCORE_TOOL_DELETE_NOTE
            If clickedNote >= 0 Then
                session_SelectOnlyNote clickedNote
                session_DeleteSelectedNotes()
            Else
                session_SetStatus "Delete Note ignored: no note was tapped."
            End If

        Case SESSION_SCORE_TOOL_CUT
            If clickedNote >= 0 Then
                session_SelectOnlyNote clickedNote
                session_CutSelectedNotes()
            Else
                session_SetStatus "Cut ignored: no note was tapped."
            End If

        Case SESSION_SCORE_TOOL_PASTE
            session_PasteCopiedNotesAt pointerX, pointerY, _
                screenWidth, screenHeight

        Case SESSION_SCORE_TOOL_SELECT
            If clickedNote >= 0 Then
                Dim As MidiEditableNote clickedEditableNote
                If midi_GetEditableNote( _
                    clickedNote, clickedEditableNote) <> 0 Then _
                    session_SetSelectedTrackPreservingNotes _
                        clickedEditableNote.trackIndex
                session_SelectOnlyNote clickedNote
                session_AnnounceSelection "Drag to move it."
            Else
                session_ClearNoteSelection()
                session_SetStatus "No notes selected. Drag the score to pan."
            End If
    End Select
End Sub


Private Sub session_PanScoreByPixels( _
    ByVal deltaX As Integer, _
    ByVal deltaY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    Dim As Integer timelineWidth = screenWidth - SESSION_SCORE_LEFT - _
        SESSION_SCORE_NOTE_LEFT - SESSION_SCORE_NOTE_RIGHT - 4
    If timelineWidth < 1 Then
        timelineWidth = 1
    End If

    If deltaX <> 0 Then
        Dim As LongInt tickDelta = CLngInt( _
            (CDbl(deltaX) * CDbl(session_ViewTicks())) / _
            CDbl(timelineWidth))
        Dim As LongInt requestedStart = _
            CLngInt(session_ViewStartTick) - tickDelta
        Dim As ULongInt maximumStart = scoreScroll_MaximumStart( _
            session_TimelineDurationTicks(), session_ViewTicks())
        If requestedStart < 0 Then
            requestedStart = 0
        End If
        If CULngInt(requestedStart) > maximumStart Then _
            requestedStart = CLngInt(maximumStart)
        session_ViewStartTick = CULngInt(requestedStart)
    End If

    If deltaY <> 0 Then
        session_TouchTrackPixelRemainder += deltaY
        Dim As Integer visibleTracks = _
            session_ScoreVisibleTrackCount(screenHeight)
        Dim As Integer maximumFirst = scoreScroll_MaximumFirstTrack( _
            session_Summary.trackCount, visibleTracks)
        While Abs(session_TouchTrackPixelRemainder) >= _
            session_ScoreTrackRowHeight
            If session_TouchTrackPixelRemainder > 0 Then
                session_ScoreFirstVisibleTrack -= 1
                session_TouchTrackPixelRemainder -= _
                    session_ScoreTrackRowHeight
            Else
                session_ScoreFirstVisibleTrack += 1
                session_TouchTrackPixelRemainder += _
                    session_ScoreTrackRowHeight
            End If
            session_ScoreFirstVisibleTrack = scoreScroll_ClampFirstTrack( _
                session_ScoreFirstVisibleTrack, maximumFirst)
        Wend
    End If
End Sub


Private Function session_MaximumViewBeatCount() As Integer
    Dim As ULongInt divisionTicks = 1
    If session_Summary.division > 0 Then _
        divisionTicks = CULngInt(session_Summary.division)

    Dim As ULongInt maximumBeats = OSE_MAX_MIDI_TICK \ divisionTicks
    If OSE_MAX_MIDI_TICK Mod divisionTicks <> 0 Then
        maximumBeats += 1
    End If
    If maximumBeats < SESSION_SCORE_MINIMUM_VIEW_BEATS Then _
        maximumBeats = SESSION_SCORE_MINIMUM_VIEW_BEATS
    Return CInt(maximumBeats)
End Function


Private Function session_ClampViewBeatCount( _
    ByVal beatCount As Integer _
) As Integer
    If beatCount < SESSION_SCORE_MINIMUM_VIEW_BEATS Then _
        beatCount = SESSION_SCORE_MINIMUM_VIEW_BEATS
    Dim As Integer maximumBeatCount = session_MaximumViewBeatCount()
    If beatCount > maximumBeatCount Then
        beatCount = maximumBeatCount
    End If
    Return beatCount
End Function


Private Function session_ViewFocusTick() As ULongInt
    Dim As NoteSelectionSummary selectionSummary
    If noteSelection_Summarize(session_NoteSelection, selectionSummary) <> 0 Then
        Return selectionSummary.startTick + _
            (selectionSummary.endTick - selectionSummary.startTick) \ 2
    End If
    Return session_ViewStartTick + session_ViewTicks() \ 2
End Function


Private Sub session_SetHorizontalViewCentered( _
    ByVal focusTick As ULongInt, _
    ByVal beatCount As Integer, _
    ByVal statusText As String _
)
    session_ViewBeatCount = session_ClampViewBeatCount(beatCount)
    Dim As ULongInt viewTicks = session_ViewTicks()
    Dim As ULongInt halfViewTicks = viewTicks \ 2
    If focusTick > halfViewTicks Then
        session_ViewStartTick = focusTick - halfViewTicks
    Else
        session_ViewStartTick = 0
    End If

    Dim As ULongInt maximumStart = scoreScroll_MaximumStart( _
        session_TimelineDurationTicks(), viewTicks)
    If session_ViewStartTick > maximumStart Then _
        session_ViewStartTick = maximumStart
    session_SetStatus statusText
End Sub


Private Sub session_ZoomScoreIn()
    Dim As Integer nextBeatCount = session_ViewBeatCount \ 2
    session_SetHorizontalViewCentered session_ViewFocusTick(), _
        nextBeatCount, "Zoom In: " + _
        LTrim(Str(session_ClampViewBeatCount(nextBeatCount))) + _
        " beats across."
End Sub


Private Sub session_ZoomScoreNormal()
    session_SetHorizontalViewCentered session_ViewFocusTick(), _
        SESSION_SCORE_BEATS, "Zoom Normal: " + _
        LTrim(Str(SESSION_SCORE_BEATS)) + " beats across."
End Sub


Private Sub session_ZoomScoreOut()
    Dim As Integer maximumBeatCount = session_MaximumViewBeatCount()
    Dim As Integer nextBeatCount
    If session_ViewBeatCount > maximumBeatCount \ 2 Then
        nextBeatCount = maximumBeatCount
    Else
        nextBeatCount = session_ViewBeatCount * 2
    End If
    session_SetHorizontalViewCentered session_ViewFocusTick(), _
        nextBeatCount, "Zoom Out: " + LTrim(Str(nextBeatCount)) + _
        " beats across."
End Sub


Private Sub session_ZoomScoreToSelection()
    Dim As NoteSelectionSummary selectionSummary
    If noteSelection_Summarize(session_NoteSelection, selectionSummary) = 0 Then
        session_SetStatus _
            "Zoom to Selection ignored: no notes are selected."
        Exit Sub
    End If

    Dim As ULongInt divisionTicks = 1
    If session_Summary.division > 0 Then _
        divisionTicks = CULngInt(session_Summary.division)
    Dim As ULongInt selectionTicks = _
        selectionSummary.endTick - selectionSummary.startTick
    Dim As ULongInt requiredBeats = selectionTicks \ divisionTicks
    If selectionTicks Mod divisionTicks <> 0 Then
        requiredBeats += 1
    End If
    If requiredBeats <= CULngInt(session_MaximumViewBeatCount() - 2) Then
        requiredBeats += 2
    Else
        requiredBeats = CULngInt(session_MaximumViewBeatCount())
    End If

    session_ViewBeatCount = session_ClampViewBeatCount(CInt(requiredBeats))
    If selectionSummary.startTick > divisionTicks Then
        session_ViewStartTick = selectionSummary.startTick - divisionTicks
    Else
        session_ViewStartTick = 0
    End If
    Dim As ULongInt maximumStart = scoreScroll_MaximumStart( _
        session_TimelineDurationTicks(), session_ViewTicks())
    If session_ViewStartTick > maximumStart Then _
        session_ViewStartTick = maximumStart
    session_SetStatus "Zoomed to selection. " + session_SelectionStatusText()
End Sub


Private Sub session_FitScoreProject()
    Dim As ULongInt divisionTicks = 1
    If session_Summary.division > 0 Then _
        divisionTicks = CULngInt(session_Summary.division)
    Dim As ULongInt timelineTicks = session_TimelineDurationTicks()
    Dim As ULongInt requiredBeats = timelineTicks \ divisionTicks
    If timelineTicks Mod divisionTicks <> 0 Then
        requiredBeats += 1
    End If
    If requiredBeats < SESSION_SCORE_MINIMUM_VIEW_BEATS Then _
        requiredBeats = SESSION_SCORE_MINIMUM_VIEW_BEATS
    Dim As Integer fittedBeats = session_ClampViewBeatCount( _
        CInt(requiredBeats))
    session_ViewBeatCount = fittedBeats
    session_ViewStartTick = 0
    session_SetStatus "Fit Project: " + LTrim(Str(fittedBeats)) + _
        " beats across."
End Sub


Private Sub session_FitScoreTracks()
    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight

    Dim As Integer fittedRowHeight = SESSION_SCORE_TRACK_ROW_HEIGHT_MINIMUM
    For candidateHeight As Integer = _
        SESSION_SCORE_TRACK_ROW_HEIGHT_MAXIMUM To _
        SESSION_SCORE_TRACK_ROW_HEIGHT_MINIMUM Step -1
        session_ScoreTrackRowHeight = candidateHeight
        If session_ScoreVisibleTrackCount(screenHeight) >= _
            session_Summary.trackCount Then
            fittedRowHeight = candidateHeight
            Exit For
        End If
    Next
    session_ScoreTrackRowHeight = fittedRowHeight
    session_ScoreFirstVisibleTrack = 0
    session_TouchTrackPixelRemainder = 0
    session_InvalidateInterfaceCaches()

    Dim As Integer visibleTracks = session_ScoreVisibleTrackCount(screenHeight)
    If visibleTracks >= session_Summary.trackCount Then
        session_SetStatus "Fit Tracks: all " + _
            LTrim(Str(session_Summary.trackCount)) + " tracks visible."
    Else
        session_SetStatus "Fit Tracks: " + LTrim(Str(visibleTracks)) + _
            " of " + LTrim(Str(session_Summary.trackCount)) + _
            " tracks visible at minimum height."
    End If
End Sub


Private Sub session_ZoomScoreAt( _
    ByVal pointerX As Integer, _
    ByVal beatDelta As Integer, _
    ByVal screenWidth As Integer _
)
    Dim As Integer nextBeatCount = session_ViewBeatCount + beatDelta
    nextBeatCount = session_ClampViewBeatCount(nextBeatCount)
    If nextBeatCount = session_ViewBeatCount Then
        Exit Sub
    End If

    Dim As Integer timelineLeft = SESSION_SCORE_LEFT + SESSION_SCORE_NOTE_LEFT
    Dim As Integer timelineWidth = screenWidth - timelineLeft - _
        SESSION_SCORE_NOTE_RIGHT - 4
    If timelineWidth < 1 Then
        timelineWidth = 1
    End If
    Dim As Double anchorRatio = _
        CDbl(pointerX - timelineLeft) / CDbl(timelineWidth)
    If anchorRatio < 0.0 Then
        anchorRatio = 0.0
    End If
    If anchorRatio > 1.0 Then
        anchorRatio = 1.0
    End If

    Dim As ULongInt oldViewTicks = session_ViewTicks()
    Dim As ULongInt anchorTick = session_ViewStartTick + _
        CULngInt(anchorRatio * CDbl(oldViewTicks))
    session_ViewBeatCount = nextBeatCount
    Dim As ULongInt newViewTicks = session_ViewTicks()
    Dim As ULongInt beforeAnchor = _
        CULngInt(anchorRatio * CDbl(newViewTicks))
    If anchorTick > beforeAnchor Then
        session_ViewStartTick = anchorTick - beforeAnchor
    Else
        session_ViewStartTick = 0
    End If
    Dim As ULongInt maximumStart = scoreScroll_MaximumStart( _
        session_TimelineDurationTicks(), newViewTicks)
    If session_ViewStartTick > maximumStart Then _
        session_ViewStartTick = maximumStart
    session_SetStatus "Score zoom: " + LTrim(Str(session_ViewBeatCount)) + _
        " beats across."
End Sub


Private Sub session_ZoomScoreVerticallyAt( _
    ByVal pointerY As Integer, _
    ByVal rowHeightDelta As Integer, _
    ByVal screenHeight As Integer _
)
    Dim As Integer nextRowHeight = _
        session_ScoreTrackRowHeight + rowHeightDelta
    If nextRowHeight < SESSION_SCORE_TRACK_ROW_HEIGHT_MINIMUM Then _
        nextRowHeight = SESSION_SCORE_TRACK_ROW_HEIGHT_MINIMUM
    If nextRowHeight > SESSION_SCORE_TRACK_ROW_HEIGHT_MAXIMUM Then _
        nextRowHeight = SESSION_SCORE_TRACK_ROW_HEIGHT_MAXIMUM
    If nextRowHeight = session_ScoreTrackRowHeight Then
        Exit Sub
    End If

    /'
        Preserve the track under the gesture center where integer scrolling
        permits it. The score owns whole track rows, so no fractional hidden
        row is retained after the gesture ends.
    '/
    Dim As Integer firstStaffY = SESSION_SCORE_TOP + _
        scoreLayout_FirstStaffOffset(session_ScoreTrackRowHeight)
    Dim As Integer rowTop = firstStaffY - _
        scoreLayout_RowTopOffset(session_ScoreTrackRowHeight)
    Dim As Integer oldFirstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer oldRowIndex = (pointerY - rowTop) \ _
        session_ScoreTrackRowHeight
    If oldRowIndex < 0 Then
        oldRowIndex = 0
    End If
    Dim As Integer oldVisibleCount = _
        session_ScoreVisibleTrackCount(screenHeight)
    If oldRowIndex >= oldVisibleCount Then
        oldRowIndex = oldVisibleCount - 1
    End If
    Dim As Integer anchorTrack = oldFirstTrack + oldRowIndex

    session_ScoreTrackRowHeight = nextRowHeight
    Dim As Integer newRowIndex = (pointerY - rowTop) \ _
        session_ScoreTrackRowHeight
    If newRowIndex < 0 Then
        newRowIndex = 0
    End If
    session_ScoreFirstVisibleTrack = anchorTrack - newRowIndex
    Dim As Integer newVisibleCount = _
        session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer maximumFirst = scoreScroll_MaximumFirstTrack( _
        session_Summary.trackCount, newVisibleCount)
    session_ScoreFirstVisibleTrack = scoreScroll_ClampFirstTrack( _
        session_ScoreFirstVisibleTrack, maximumFirst)
    session_TouchTrackPixelRemainder = 0
    session_InvalidateInterfaceCaches()
    session_SetStatus "Score vertical zoom: " + _
        Str(session_ScoreTrackRowHeight) + " pixels per track."
End Sub


Public Sub session_ProcessViewShortcuts()
    Dim As Integer shortcutMask
    Dim As Integer controlState = input_KeyPressed(FB.SC_CONTROL)
    Dim As Integer shiftState = _
        input_KeyPressed(FB.SC_LSHIFT) OrElse input_KeyPressed(FB.SC_RSHIFT)
    If controlState <> 0 Then
        If input_KeyPressed(FB.SC_1) <> 0 Then
            shortcutMask Or= 1
        End If
        If input_KeyPressed(FB.SC_2) <> 0 Then
            shortcutMask Or= 2
        End If
        If input_KeyPressed(FB.SC_3) <> 0 Then
            shortcutMask Or= 4
        End If
        If input_KeyPressed(FB.SC_E) <> 0 Then
            shortcutMask Or= 8
        End If
        If input_KeyPressed(FB.SC_F) <> 0 Then
            If shiftState <> 0 Then
                shortcutMask Or= 32
            Else
                shortcutMask Or= 16
            End If
        End If
    End If

    If session_IsModalOpen() <> 0 Then
        session_LastViewShortcutMask = shortcutMask
        Exit Sub
    End If

    Dim As Integer newShortcutMask = shortcutMask And _
        (Not session_LastViewShortcutMask)
    If (newShortcutMask And &H1) <> 0 Then
        session_OnWindowMenu SESSION_VIEW_ZOOM_IN
    ElseIf (newShortcutMask And &H2) <> 0 Then
        session_OnWindowMenu SESSION_VIEW_ZOOM_NORMAL
    ElseIf (newShortcutMask And &H4) <> 0 Then
        session_OnWindowMenu SESSION_VIEW_ZOOM_OUT
    ElseIf (newShortcutMask And &H8) <> 0 Then
        session_OnWindowMenu SESSION_VIEW_ZOOM_SELECTION
    ElseIf (newShortcutMask And &H10) <> 0 Then
        session_OnWindowMenu SESSION_VIEW_FIT_PROJECT
    ElseIf (newShortcutMask And &H20) <> 0 Then
        session_OnWindowMenu SESSION_VIEW_FIT_TRACKS
    End If
    session_LastViewShortcutMask = shortcutMask
End Sub


Private Sub session_UpdateTouchScoreInput( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    Dim As Integer contactCount = input_TouchCount()
    If contactCount > INPUT_TOUCH_CAPACITY Then _
        contactCount = INPUT_TOUCH_CAPACITY
    Dim As Integer validContactCount
    For contactIndex As Integer = 0 To contactCount - 1
        Dim As Integer contactX
        Dim As Integer contactY
        Dim As Integer contactId
        If input_Touch(contactIndex, contactX, contactY, contactId) <> 0 Then
            session_TouchContacts(validContactCount).id = contactId
            session_TouchContacts(validContactCount).x = contactX
            session_TouchContacts(validContactCount).y = contactY
            validContactCount += 1
        End If
    Next

    ' Deterministic desktop tests and non-touch backends retain the same
    ' left-button fallback promised by gfxlib's public touch API.
    If validContactCount = 0 AndAlso _
        (input_MouseButtons() And &H1) <> 0 Then
        session_TouchContacts(0).id = 0
        session_TouchContacts(0).x = input_MouseX()
        session_TouchContacts(0).y = input_MouseY()
        validContactCount = 1
    End If

    Dim As OseTouchGestureResult gesture
    touchGesture_Update session_TouchGestureState, _
        @session_TouchContacts(0), validContactCount, _
        SESSION_SCORE_DRAG_THRESHOLD, gesture

    Dim As Integer scoreBottom = screenHeight - SESSION_MIXER_HEIGHT
    If gesture.started <> 0 Then
        session_TouchIntent = SESSION_TOUCH_INTENT_TAP
        session_TouchStartNote = -1
        session_TouchStartTrack = -1
        If gesture.x >= SESSION_SCORE_LEFT + 12 AndAlso _
            gesture.x < screenWidth - 8 AndAlso _
            gesture.y >= SESSION_SCORE_TOP + 26 AndAlso _
            gesture.y < scoreBottom - SESSION_SCORE_SCROLLBAR_SIZE - 4 Then
            session_TouchStartTrack = session_ScoreTrackFromY( _
                gesture.y, screenHeight)
            session_TouchStartNote = session_FindNoteAt( _
                gesture.x, gesture.y, screenWidth, screenHeight)
            If session_ActiveScoreTool = SESSION_SCORE_TOOL_SELECT Then
                If session_TouchStartNote >= 0 Then
                    session_TouchIntent = SESSION_TOUCH_INTENT_NOTE_DRAG
                Else
                    session_TouchIntent = SESSION_TOUCH_INTENT_PAN
                End If
            End If
        End If
        session_TouchTrackPixelRemainder = 0
    End If

    If gesture.multiActive <> 0 Then
        If session_ScoreDragNote >= 0 Then
            session_EndScoreNoteDrag()
        End If
        session_TouchIntent = SESSION_TOUCH_INTENT_PAN
        If gesture.x >= SESSION_SCORE_LEFT AndAlso _
            gesture.x < screenWidth AndAlso _
            gesture.y >= SESSION_SCORE_TOP AndAlso _
            gesture.y < scoreBottom Then
            session_PanScoreByPixels gesture.deltaX, gesture.deltaY, _
                screenWidth, screenHeight
            session_TouchPinchXAccumulator += gesture.pinchXDelta
            While session_TouchPinchXAccumulator >= 18.0
                session_ZoomScoreAt gesture.x, _
                    -SESSION_SCORE_ZOOM_STEP, screenWidth
                session_TouchPinchXAccumulator -= 18.0
            Wend
            While session_TouchPinchXAccumulator <= -18.0
                session_ZoomScoreAt gesture.x, _
                    SESSION_SCORE_ZOOM_STEP, screenWidth
                session_TouchPinchXAccumulator += 18.0
            Wend
            session_TouchPinchYAccumulator += gesture.pinchYDelta
            While session_TouchPinchYAccumulator >= 18.0
                session_ZoomScoreVerticallyAt gesture.y, _
                    SESSION_SCORE_TRACK_ROW_ZOOM_STEP, screenHeight
                session_TouchPinchYAccumulator -= 18.0
            Wend
            While session_TouchPinchYAccumulator <= -18.0
                session_ZoomScoreVerticallyAt gesture.y, _
                    -SESSION_SCORE_TRACK_ROW_ZOOM_STEP, screenHeight
                session_TouchPinchYAccumulator += 18.0
            Wend
        End If
    ElseIf gesture.dragStarted <> 0 AndAlso _
        session_TouchIntent = SESSION_TOUCH_INTENT_NOTE_DRAG Then
        If session_TouchStartNote >= 0 Then
            If session_NoteIsSelected(session_TouchStartNote) = 0 Then _
                session_SelectOnlyNote session_TouchStartNote
            session_BeginScoreNoteDrag session_TouchStartNote, _
                gesture.startX, gesture.startY, screenWidth, screenHeight
        End If
    End If

    If gesture.dragActive <> 0 Then
        If session_TouchIntent = SESSION_TOUCH_INTENT_NOTE_DRAG AndAlso _
            session_ScoreDragNote >= 0 Then
            session_ApplyScoreNoteDrag gesture.x, gesture.y, _
                screenWidth, screenHeight
        ElseIf session_TouchIntent = SESSION_TOUCH_INTENT_PAN Then
            session_PanScoreByPixels gesture.deltaX, gesture.deltaY, _
                screenWidth, screenHeight
        End If
    End If

    If gesture.dragEnded <> 0 Then
        If session_ScoreDragNote >= 0 Then
            session_EndScoreNoteDrag()
        End If
        session_TouchIntent = SESSION_TOUCH_INTENT_NONE
    ElseIf gesture.tap <> 0 Then
        session_HandleTouchScoreTap gesture.x, gesture.y, _
            screenWidth, screenHeight
        session_TouchIntent = SESSION_TOUCH_INTENT_NONE
    End If
    If validContactCount = 0 Then
        session_TouchPinchXAccumulator = 0.0
        session_TouchPinchYAccumulator = 0.0
    End If

    Dim As Integer deleteState = input_KeyPressed(FB.SC_DELETE)
    If deleteState <> 0 AndAlso session_LastDeleteState = 0 Then _
        session_DeleteSelectedNotes()
    session_LastDeleteState = deleteState
    session_LastScoreButtons = input_MouseButtons()
End Sub


Private Sub session_UpdateScoreInput(ByVal screenWidth As Integer, ByVal screenHeight As Integer)
    If session_IsModalOpen() <> 0 Then
        session_LastScoreButtons = input_MouseButtons()
        session_LastDeleteState = input_KeyPressed(FB.SC_DELETE)
        session_EndScoreNoteDrag()
        session_ScoreMarqueeActive = 0
        session_ScoreMarqueeCuts = 0
        touchGesture_Reset session_TouchGestureState
        session_TouchIntent = SESSION_TOUCH_INTENT_NONE
        Exit Sub
    End If

    session_SynchronizeNoteSelection()

    ' The click hit-test shares the same bounded visible-note set as the
    ' renderer. Refresh it after track selection and timeline movement from
    ' the preceding frame.
    session_PrepareScoreNoteCache(screenHeight)

    If session_InteractionMode = OSE_UI_INTERACTION_TOUCH Then
        session_UpdateTouchScoreInput screenWidth, screenHeight
        Exit Sub
    End If

    Dim As Integer mouseX = input_MouseX()
    Dim As Integer mouseY = input_MouseY()
    Dim As Integer mouseButtons = input_MouseButtons()
    Dim As Integer leftPressed = _
        ((mouseButtons And &H1) <> 0) AndAlso ((session_LastScoreButtons And &H1) = 0)
    Dim As Integer leftReleased = _
        ((mouseButtons And &H1) = 0) AndAlso ((session_LastScoreButtons And &H1) <> 0)
    Dim As Integer scoreBottom = screenHeight - SESSION_MIXER_HEIGHT
    Dim As Integer wheelDelta = input_MouseWheel()

    If wheelDelta <> 0 AndAlso mouseX >= SESSION_SCORE_LEFT AndAlso _
        mouseX < screenWidth AndAlso mouseY >= SESSION_SCORE_TOP AndAlso _
        mouseY < scoreBottom Then
        Dim As Integer controlZoom = input_KeyPressed(FB.SC_CONTROL)
        Dim As Integer shiftState = _
            input_KeyPressed(FB.SC_LSHIFT) OrElse _
            input_KeyPressed(FB.SC_RSHIFT)
        If controlZoom <> 0 AndAlso shiftState <> 0 Then
            session_ZoomScoreVerticallyAt mouseY, _
                IIf(wheelDelta > 0, SESSION_SCORE_TRACK_ROW_ZOOM_STEP, _
                    -SESSION_SCORE_TRACK_ROW_ZOOM_STEP), screenHeight
        ElseIf controlZoom <> 0 Then
            session_ZoomScoreAt mouseX, _
                IIf(wheelDelta > 0, -SESSION_SCORE_ZOOM_STEP, _
                    SESSION_SCORE_ZOOM_STEP), screenWidth
        ElseIf shiftState <> 0 Then
            session_ScrollScoreTracks wheelDelta, screenHeight
        Else
            session_ScrollScore wheelDelta
        End If
    End If

    Dim As Integer scoreClickConsumed
    If leftPressed <> 0 Then
        scoreClickConsumed = session_HandleAddPaletteClick(mouseX, mouseY)
        If scoreClickConsumed = 0 Then _
            scoreClickConsumed = session_HandleScoreToolClick(mouseX, mouseY)
    End If

    If scoreClickConsumed = 0 AndAlso leftPressed AndAlso _
        mouseX >= SESSION_SCORE_LEFT + 12 AndAlso _
        mouseX < screenWidth - 8 AndAlso mouseY >= SESSION_SCORE_TOP + 26 AndAlso _
        mouseY < scoreBottom - SESSION_SCORE_SCROLLBAR_SIZE - 4 Then
        Dim As Integer clickedTrack = session_ScoreTrackFromY( _
            mouseY, screenHeight)
        If clickedTrack >= 0 Then _
            session_SetSelectedTrackPreservingNotes clickedTrack

        Dim As Integer clickedNote = session_FindNoteAt( _
            mouseX, mouseY, screenWidth, screenHeight)
        Select Case session_ActiveScoreTool
            Case SESSION_SCORE_TOOL_ADD_NOTE
                If clickedTrack >= 0 Then
                    session_SelectTrack clickedTrack
                    session_AddScoreNoteAt mouseX, mouseY, screenWidth, screenHeight
                End If

            Case SESSION_SCORE_TOOL_DELETE_NOTE
                If clickedNote >= 0 Then
                    session_SelectOnlyNote clickedNote
                    session_DeleteSelectedNotes()
                Else
                    session_SetStatus "Delete Note ignored: no note was clicked."
                End If

            Case SESSION_SCORE_TOOL_CUT
                session_ClearNoteSelection()
                session_BeginScoreMarquee mouseX, mouseY, 0, screenWidth, _
                    screenHeight, -1

            Case SESSION_SCORE_TOOL_PASTE
                session_PasteCopiedNotesAt mouseX, mouseY, screenWidth, screenHeight

            Case SESSION_SCORE_TOOL_SELECT
                Dim As Integer shiftSelection = _
                    input_KeyPressed(FB.SC_LSHIFT) OrElse _
                    input_KeyPressed(FB.SC_RSHIFT)
                If clickedNote >= 0 Then
                    Dim As MidiEditableNote clickedEditableNote
                    If midi_GetEditableNote(clickedNote, clickedEditableNote) <> 0 Then _
                        session_SetSelectedTrackPreservingNotes _
                            clickedEditableNote.trackIndex

                    If shiftSelection <> 0 Then
                        noteSelection_Toggle session_NoteSelection, clickedNote
                        session_SelectedNote = _
                            session_NoteSelection.primaryNoteIndex
                    ElseIf session_NoteIsSelected(clickedNote) = 0 Then
                        session_SelectOnlyNote clickedNote
                    Else
                        session_NoteSelection.primaryNoteIndex = clickedNote
                        session_SelectedNote = clickedNote
                    End If

                    If session_NoteIsSelected(clickedNote) <> 0 Then
                        session_BeginScoreNoteDrag clickedNote, mouseX, mouseY, _
                            screenWidth, screenHeight
                        session_AnnounceSelection IIf( _
                            session_NoteSelection.count = 1, _
                            "Alt-drag resizes it.", "Drag to move them.")
                    ElseIf session_NoteSelection.count > 0 Then
                        session_AnnounceSelection ""
                    Else
                        session_SetStatus "No notes selected."
                    End If
                ElseIf mouseX >= SESSION_SCORE_LEFT + _
                    SESSION_SCORE_NOTE_LEFT AndAlso _
                    input_KeyPressed(FB.SC_CONTROL) <> 0 Then
                    If clickedTrack >= 0 Then
                        session_SelectTrack clickedTrack
                    End If
                    session_AddScoreNoteAt mouseX, mouseY, screenWidth, screenHeight
                ElseIf mouseX >= SESSION_SCORE_LEFT + _
                    SESSION_SCORE_NOTE_LEFT Then
                    If shiftSelection = 0 Then
                        session_ClearNoteSelection()
                    End If
                    session_BeginScoreMarquee mouseX, mouseY, shiftSelection, _
                        screenWidth, screenHeight
                End If
        End Select
    End If

    If (mouseButtons And &H1) <> 0 Then
        If session_ScoreDragNote >= 0 Then
            session_ApplyScoreNoteDrag mouseX, mouseY, screenWidth, screenHeight
        ElseIf session_ScoreMarqueeActive <> 0 Then
            session_UpdateScoreMarquee mouseX, mouseY, screenWidth, screenHeight
        End If
    End If

    If leftReleased <> 0 Then
        If session_ScoreMarqueeActive <> 0 Then _
            session_FinishScoreMarquee screenWidth, screenHeight
        session_EndScoreNoteDrag()
    End If

    Dim As Integer deleteState = input_KeyPressed(FB.SC_DELETE)
    If input_KeyPressed(FB.SC_LSHIFT) <> 0 OrElse _
        input_KeyPressed(FB.SC_RSHIFT) <> 0 Then deleteState = 0
    If deleteState <> 0 AndAlso session_LastDeleteState = 0 Then _
        session_DeleteSelectedNotes()

    session_LastDeleteState = deleteState
    session_LastScoreButtons = mouseButtons
End Sub


' -------------------------------------------------------------------------
' Score and mixer rendering
' -------------------------------------------------------------------------

Private Sub session_DrawNoteLedgerLines( _
    ByVal noteX As Integer, _
    ByVal noteY As Integer, _
    ByVal staffY As Integer, _
    ByVal clr As ULong _
)
    Dim As Integer lineSpacing = scoreLayout_LineSpacing( _
        session_ScoreTrackRowHeight)
    Dim As Integer staffHeight = lineSpacing * 4
    Dim As Integer ledgerHalfWidth = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 8)
    Dim As Integer ledgerTolerance = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 3)
    If noteY < staffY Then
        For ledgerIndex As Integer = 1 To 8
            Dim As Integer ledgerY = staffY - ledgerIndex * lineSpacing
            If ledgerY < noteY - ledgerTolerance Then
                Exit For
            End If
            backend_Line noteX - ledgerHalfWidth, ledgerY, _
                noteX + ledgerHalfWidth, ledgerY, clr
        Next
    ElseIf noteY > staffY + staffHeight Then
        For ledgerIndex As Integer = 1 To 8
            Dim As Integer ledgerY = staffY + staffHeight + _
                ledgerIndex * lineSpacing
            If ledgerY > noteY + ledgerTolerance Then
                Exit For
            End If
            backend_Line noteX - ledgerHalfWidth, ledgerY, _
                noteX + ledgerHalfWidth, ledgerY, clr
        Next
    End If
End Sub


Private Function session_NoteAccidental( _
    ByVal keyNumber As Integer, _
    ByVal sharpsFlats As Integer _
) As String
    If keyNumber < 0 Then
        keyNumber = 0
    End If
    If keyNumber > 127 Then
        keyNumber = 127
    End If
    If sharpsFlats < -7 Then
        sharpsFlats = -7
    End If
    If sharpsFlats > 7 Then
        sharpsFlats = 7
    End If

    Dim As Integer pitchClass = keyNumber Mod 12
    Dim As Integer diatonicIndex = session_MidiDiatonicIndexForKey( _
        keyNumber, sharpsFlats)
    Dim As Integer naturalPitchClass(0 To 6) = {0, 2, 4, 5, 7, 9, 11}
    Dim As Integer letterIndex = diatonicIndex Mod 7
    Dim As Integer naturalClass = naturalPitchClass(letterIndex)
    Dim As Integer defaultAlteration = 0

    If sharpsFlats > 0 Then
        Dim As Integer sharpOrder(0 To 6) = {6, 1, 8, 3, 10, 5, 0}
        For orderIndex As Integer = 0 To sharpsFlats - 1
            Dim As Integer alteredClass = sharpOrder(orderIndex)
            If alteredClass = (naturalClass + 1) Mod 12 Then
                defaultAlteration = 1
                Exit For
            End If
        Next
    ElseIf sharpsFlats < 0 Then
        Dim As Integer flatOrder(0 To 6) = {10, 3, 8, 1, 6, 11, 4}
        For orderIndex As Integer = 0 To (-sharpsFlats) - 1
            Dim As Integer alteredClass = flatOrder(orderIndex)
            If alteredClass = (naturalClass + 11) Mod 12 Then
                defaultAlteration = -1
                Exit For
            End If
        Next
    End If

    Dim As Integer actualAlteration = 0
    If pitchClass = (naturalClass + 1) Mod 12 Then
        actualAlteration = 1
    ElseIf pitchClass = (naturalClass + 11) Mod 12 Then
        actualAlteration = -1
    ElseIf pitchClass <> naturalClass Then
        ' MIDI does not preserve enharmonic spelling. Use the key's preferred
        ' spelling and avoid inventing a symbol for an unrepresentable case.
        Return ""
    End If

    If actualAlteration = defaultAlteration Then
        Return ""
    End If
    If actualAlteration = 0 Then
        Return "n"
    End If
    If actualAlteration > 0 Then
        Return "#"
    End If
    Return "b"
End Function


Private Sub session_DrawAccidental( _
    ByVal accidentalText As String, _
    ByVal accidentalX As Integer, ByVal accidentalY As Integer, _
    ByVal accidentalColor As ULong _
)
    Dim As Integer symbolCode = -1
    Select Case accidentalText
        Case "#"
            symbolCode = MUSIC_SYMBOL_SHARP
        Case "b"
            symbolCode = MUSIC_SYMBOL_FLAT
        Case "n"
            symbolCode = MUSIC_SYMBOL_NATURAL
    End Select

    If symbolCode >= 0 AndAlso musicSymbols_HasGlyph(symbolCode) <> 0 Then
        musicSymbols_DrawCentered symbolCode, accidentalX, accidentalY, _
            accidentalColor
    Else
        backend_Print accidentalX - 4, accidentalY - 6, accidentalColor, _
            accidentalText
    End If
End Sub


Private Sub session_DrawScaledNotationPolygon( _
    ByVal originX As Integer, ByVal originY As Integer, _
    ByVal targetWidth As Integer, ByVal targetHeight As Integer, _
    ByVal designWidth As Integer, ByVal designHeight As Integer, _
    ByVal pointCount As Integer, designX() As Integer, _
    designY() As Integer, ByVal polygonColor As ULong _
)
    /'
        Notation outlines are authored on a large integer grid and reduced to
        their final score size only here. The same guarded path serves clefs,
        noteheads, stems, and flags so those symbols share omaGUI's filled
        polygon rendering behavior.

        omaGUI limits a polygon to GRAPHICSHAPE_MAX_POINTS. Invalid dimensions
        and paths are rejected before scaling to prevent divide-by-zero and
        out-of-range array access in malformed symbol data.
    '/
    If targetWidth < 2 Or targetHeight < 2 Then
        Exit Sub
    End If
    If designWidth < 1 Or designHeight < 1 Then
        Exit Sub
    End If
    If pointCount < 3 Or pointCount > GRAPHICSHAPE_MAX_POINTS Then
        Exit Sub
    End If

    Dim As GraphicShapeRenderOptions options
    Dim As Integer pointX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer pointY(1 To GRAPHICSHAPE_MAX_POINTS)

    For pointIndex As Integer = 1 To pointCount
        Dim As Integer boundedX = designX(pointIndex)
        Dim As Integer boundedY = designY(pointIndex)
        If boundedX < 0 Then
            boundedX = 0
        End If
        If boundedX > designWidth Then
            boundedX = designWidth
        End If
        If boundedY < 0 Then
            boundedY = 0
        End If
        If boundedY > designHeight Then
            boundedY = designHeight
        End If

        pointX(pointIndex) = (boundedX * (targetWidth - 1) + _
            designWidth \ 2) \ designWidth
        pointY(pointIndex) = (boundedY * (targetHeight - 1) + _
            designHeight \ 2) \ designHeight
    Next

    graphicshape_DefaultOptions options, GUI_SHAPE_POLYGON
    options.stroke_clr = polygonColor
    options.fill_clr = polygonColor
    options.filled = -1
    options.line_width = 0
    options.object_alpha = 255
    options.stroke_alpha = 255
    options.fill_alpha = 255
    options.clip_to_bounds = -1

    graphicshape_RenderWithOptions originX, originY, targetWidth, targetHeight, _
        options, "", pointCount, pointX(), pointY()
End Sub


Private Sub session_DrawVectorNoteHead( _
    ByVal centerX As Integer, ByVal centerY As Integer, _
    ByVal headWidth As Integer, ByVal headHeight As Integer, _
    ByVal headFilled As Integer, ByVal noteColor As ULong _
)
    /'
        The slanted 100 by 70 design follows the broad, calligraphic heads in
        the reference score. Hollow heads are two overlapping closed ribbons,
        not an outer shape painted over with a guessed row color. Staff and
        ledger lines therefore remain visible through the center as they did
        through the original monochrome glyph mask.
    '/
    Const DESIGN_WIDTH As Integer = 100
    Const DESIGN_HEIGHT As Integer = 70

    If headWidth < 2 Or headHeight < 2 Then
        Exit Sub
    End If
    Dim As Integer originX = centerX - headWidth \ 2
    Dim As Integer originY = centerY - headHeight \ 2
    Dim As Integer designX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer designY(1 To GRAPHICSHAPE_MAX_POINTS)

    If headFilled <> 0 Then
        designX(1) = 0
        designY(1) = 45
        designX(2) = 6
        designY(2) = 28
        designX(3) = 22
        designY(3) = 14
        designX(4) = 45
        designY(4) = 4
        designX(5) = 70
        designY(5) = 0
        designX(6) = 92
        designY(6) = 12
        designX(7) = 100
        designY(7) = 29
        designX(8) = 93
        designY(8) = 50
        designX(9) = 75
        designY(9) = 63
        designX(10) = 50
        designY(10) = 70
        designX(11) = 25
        designY(11) = 68
        designX(12) = 5
        designY(12) = 58
        session_DrawScaledNotationPolygon originX, originY, headWidth, _
            headHeight, DESIGN_WIDTH, DESIGN_HEIGHT, 12, designX(), _
            designY(), noteColor
        Exit Sub
    End If

    ' Upper ribbon of a whole or half-note head.
    designX(1) = 0
    designY(1) = 45
    designX(2) = 6
    designY(2) = 28
    designX(3) = 22
    designY(3) = 14
    designX(4) = 45
    designY(4) = 4
    designX(5) = 70
    designY(5) = 0
    designX(6) = 92
    designY(6) = 12
    designX(7) = 100
    designY(7) = 29
    designX(8) = 84
    designY(8) = 27
    designX(9) = 67
    designY(9) = 19
    designX(10) = 48
    designY(10) = 17
    designX(11) = 28
    designY(11) = 23
    designX(12) = 15
    designY(12) = 39
    session_DrawScaledNotationPolygon originX, originY, headWidth, headHeight, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 12, designX(), designY(), noteColor

    ' Lower ribbon closes the ends while preserving the hollow center.
    designX(1) = 0
    designY(1) = 42
    designX(2) = 5
    designY(2) = 58
    designX(3) = 25
    designY(3) = 68
    designX(4) = 50
    designY(4) = 70
    designX(5) = 75
    designY(5) = 63
    designX(6) = 93
    designY(6) = 50
    designX(7) = 100
    designY(7) = 30
    designX(8) = 84
    designY(8) = 32
    designX(9) = 74
    designY(9) = 46
    designX(10) = 56
    designY(10) = 53
    designX(11) = 35
    designY(11) = 52
    designX(12) = 16
    designY(12) = 46
    session_DrawScaledNotationPolygon originX, originY, headWidth, headHeight, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 12, designX(), designY(), noteColor
End Sub


Private Sub session_DrawVectorNoteStem( _
    ByVal stemX As Integer, ByVal noteY As Integer, _
    ByVal stemEndY As Integer, ByVal stemWidth As Integer, _
    ByVal noteColor As ULong _
)
    Dim As Integer stemTop = noteY
    If stemEndY < stemTop Then
        stemTop = stemEndY
    End If
    Dim As Integer stemHeight = Abs(stemEndY - noteY) + 1
    If stemHeight < 2 Then
        Exit Sub
    End If

    If stemWidth < 1 Then
        stemWidth = 1
    End If
    ' A stem is one axis-aligned rectangle. Sending one rectangle to
    ' gfxlib preserves the vector silhouette while avoiding one draw command
    ' per scanline for every visible note.
    backend_Rect stemX - stemWidth \ 2, stemTop, stemWidth, _
        stemHeight - 1, noteColor, 1
End Sub


Private Sub session_DrawVectorNoteFlag( _
    ByVal stemX As Integer, ByVal flagAnchorY As Integer, _
    ByVal stemUp As Integer, ByVal flagWidth As Integer, _
    ByVal flagHeight As Integer, ByVal noteColor As ULong _
)
    /'
        One tapered ribbon represents one flag. Mirroring both axes gives the
        standard down-stem form without maintaining a second independent path.
        Repetition at six-pixel intervals produces 8th through 64th notes.
    '/
    If flagWidth < 2 OrElse flagHeight < 2 Then
        Exit Sub
    End If

    Dim As Integer designX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer designY(1 To GRAPHICSHAPE_MAX_POINTS)
    designX(1) = 0
    designY(1) = 0
    designX(2) = 16
    designY(2) = 10
    designX(3) = 38
    designY(3) = 25
    designX(4) = 62
    designY(4) = 43
    designX(5) = 84
    designY(5) = 66
    designX(6) = 96
    designY(6) = 88
    designX(7) = 100
    designY(7) = 100
    designX(8) = 83
    designY(8) = 85
    designX(9) = 65
    designY(9) = 72
    designX(10) = 44
    designY(10) = 59
    designX(11) = 22
    designY(11) = 52
    designX(12) = 0
    designY(12) = 42

    Dim As Integer originX = stemX
    Dim As Integer originY = flagAnchorY
    If stemUp = 0 Then
        For pointIndex As Integer = 1 To 12
            designY(pointIndex) = 100 - designY(pointIndex)
        Next
        originY = flagAnchorY - flagHeight + 1
    End If

    session_DrawScaledNotationPolygon originX, originY, flagWidth, _
        flagHeight, 100, 100, 12, designX(), designY(), noteColor
End Sub


Private Sub session_ClassifyNoteDuration( _
    ByRef editableNote As MidiEditableNote, _
    ByVal quarterTicks As ULongInt, _
    ByRef durationCode As Integer, _
    ByRef headFilled As Integer, _
    ByRef stemRequired As Integer, _
    ByRef flagCount As Integer, _
    ByRef dotted As Integer _
)
    durationCode = 2
    headFilled = 1
    stemRequired = 1
    flagCount = 4
    dotted = 0
    If quarterTicks = 0 Then
        quarterTicks = 1
    End If

    Dim As ULongInt eighthTicks = quarterTicks \ 2
    Dim As ULongInt sixteenthTicks = quarterTicks \ 4
    Dim As ULongInt thirtySecondTicks = quarterTicks \ 8
    Dim As ULongInt sixtyFourthTicks = quarterTicks \ 16
    If eighthTicks = 0 Then
        eighthTicks = 1
    End If
    If sixteenthTicks = 0 Then
        sixteenthTicks = 1
    End If
    If thirtySecondTicks = 0 Then
        thirtySecondTicks = 1
    End If
    If sixtyFourthTicks = 0 Then
        sixtyFourthTicks = 1
    End If

    Dim As ULongInt durationValue(0 To 6) = _
        {quarterTicks * 4, quarterTicks * 2, quarterTicks, _
         eighthTicks, sixteenthTicks, thirtySecondTicks, sixtyFourthTicks}
    Dim As Integer matchedDuration = 0
    For durationIndex As Integer = 0 To 6
        If durationValue(durationIndex) = 0 Then
            Continue For
        End If
        If editableNote.durationTicks = durationValue(durationIndex) Then
            durationCode = durationIndex
            matchedDuration = -1
            Exit For
        End If
        Dim As ULongInt dottedValue = durationValue(durationIndex) + _
            durationValue(durationIndex) \ 2
        If editableNote.durationTicks = dottedValue Then
            durationCode = durationIndex
            dotted = -1
            matchedDuration = -1
            Exit For
        End If
    Next

    If matchedDuration = 0 Then
        If editableNote.durationTicks >= quarterTicks * 4 Then
            durationCode = 0
        ElseIf editableNote.durationTicks >= quarterTicks * 2 Then
            durationCode = 1
        ElseIf editableNote.durationTicks >= quarterTicks Then
            durationCode = 2
        ElseIf editableNote.durationTicks >= eighthTicks Then
            durationCode = 3
        ElseIf editableNote.durationTicks >= sixteenthTicks Then
            durationCode = 4
        ElseIf editableNote.durationTicks >= thirtySecondTicks Then
            durationCode = 5
        Else
            durationCode = 6
        End If
    End If

    Select Case durationCode
        Case 0
            headFilled = 0
            stemRequired = 0
            flagCount = 0
        Case 1
            headFilled = 0
            stemRequired = 1
            flagCount = 0
        Case 2
            headFilled = 1
            stemRequired = 1
            flagCount = 0
        Case 3
            headFilled = 1
            stemRequired = 1
            flagCount = 1
        Case 4
            headFilled = 1
            stemRequired = 1
            flagCount = 2
        Case 5
            headFilled = 1
            stemRequired = 1
            flagCount = 3
        Case Else
            headFilled = 1
            stemRequired = 1
            flagCount = 4
    End Select
End Sub


Private Function session_ScoreBeamBaselineY( _
    ByVal staffY As Integer, ByVal stemUp As Integer _
) As Integer
    /'
        Beamed runs use one shared horizontal baseline one scaled staff-space
        outside the five lines. This keeps every stem attached to one coherent
        beam instead of creating a kink at each change of pitch.
    '/
    Dim As Integer lineSpacing = scoreLayout_LineSpacing( _
        session_ScoreTrackRowHeight)
    Dim As Integer staffBottomOffset = lineSpacing * 4

    If stemUp <> 0 Then
        Return staffY - lineSpacing
    End If
    Return staffY + staffBottomOffset + lineSpacing
End Function


Private Sub session_DrawScoreNote( _
    ByRef editableNote As MidiEditableNote, _
    ByVal noteX As Integer, _
    ByVal noteY As Integer, _
    ByVal staffY As Integer, _
    ByVal noteColor As ULong, _
    ByVal quarterTicks As ULongInt, _
    ByVal sharpsFlats As Integer, _
    ByVal beamed As Integer, _
    ByVal stemDirection As Integer, _
    ByVal suppressAccidental As Integer _
)
    Dim As Integer lineSpacing = scoreLayout_LineSpacing( _
        session_ScoreTrackRowHeight)
    Dim As Integer headOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 4)
    Dim As Integer stemLength = lineSpacing * 4
    Dim As Integer stemWidth = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 2)
    Dim As Integer flagWidth = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 11)
    Dim As Integer flagHeight = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 11)
    Dim As Integer durationCode
    Dim As Integer headFilled
    Dim As Integer stemRequired
    Dim As Integer flagCount
    Dim As Integer dotted
    session_ClassifyNoteDuration editableNote, quarterTicks, durationCode, _
        headFilled, stemRequired, flagCount, dotted

    session_DrawNoteLedgerLines noteX, noteY, staffY, noteColor
    If suppressAccidental = 0 Then
        Dim As String accidental = session_NoteAccidental( _
            editableNote.keyNumber, sharpsFlats)
        If accidental <> "" Then
            session_DrawAccidental accidental, noteX - _
                scoreLayout_ScalePixels(session_ScoreTrackRowHeight, 12), _
                noteY, noteColor
        End If
    End If
    Dim As Integer noteHeadWidth = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 10)
    Dim As Integer noteHeadHeight = lineSpacing
    If durationCode = 0 Then
        noteHeadWidth = scoreLayout_ScalePixels( _
            session_ScoreTrackRowHeight, 12)
        noteHeadHeight = scoreLayout_ScalePixels( _
            session_ScoreTrackRowHeight, 8)
    ElseIf durationCode = 1 Then
        noteHeadWidth = scoreLayout_ScalePixels( _
            session_ScoreTrackRowHeight, 11)
    End If
    session_DrawVectorNoteHead noteX, noteY, noteHeadWidth, noteHeadHeight, _
        headFilled, noteColor

    ' Dotted whole notes have no stem, so the dot must be drawn before the
    ' stemless early exit.
    If dotted <> 0 Then
        Dim As Integer dotX = noteX + scoreLayout_ScalePixels( _
            session_ScoreTrackRowHeight, 10)
        If musicSymbols_HasGlyph(MUSIC_SYMBOL_DOT) <> 0 Then
            musicSymbols_DrawCentered MUSIC_SYMBOL_DOT, dotX, noteY, _
                noteColor
        Else
            backend_Circle dotX, noteY, scoreLayout_ScalePixels( _
                session_ScoreTrackRowHeight, 2), noteColor, 1
        End If
    End If

    If stemRequired = 0 Then
        Exit Sub
    End If

    Dim As Integer stemUp = 1
    If noteY < staffY + lineSpacing * 2 Then
        stemUp = 0
    End If
    If stemDirection = 0 Then
        stemUp = 0
    End If
    If stemDirection = 1 Then
        stemUp = 1
    End If

    Dim As Integer stemX = noteX + headOffset
    Dim As Integer stemEndY = noteY - stemLength
    If stemUp = 0 Then
        stemX = noteX - headOffset
        stemEndY = noteY + stemLength
    End If
    If beamed <> 0 Then
        stemEndY = session_ScoreBeamBaselineY(staffY, stemUp)
    End If
    session_DrawVectorNoteStem stemX, noteY, stemEndY, stemWidth, noteColor

    If beamed = 0 Then
        For flagIndex As Integer = 0 To flagCount - 1
            Dim As Integer flagOffset = flagIndex * _
                scoreLayout_ScalePixels(session_ScoreTrackRowHeight, 6)
            If stemUp <> 0 Then
                session_DrawVectorNoteFlag stemX, stemEndY + flagOffset, _
                    stemUp, flagWidth, flagHeight, noteColor
            Else
                session_DrawVectorNoteFlag stemX, stemEndY - flagOffset, _
                    stemUp, flagWidth, flagHeight, noteColor
            End If
        Next
    End If
End Sub


Private Function session_NoteStemDirection( _
    ByVal sourceIndex As Integer, _
    ByRef sourceNote As MidiEditableNote, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
) As Integer
    Dim As Integer sourceCacheIndex = _
        session_ScoreCachePositionForModel(sourceIndex)
    If sourceCacheIndex >= 0 AndAlso _
        session_ScoreStemComputed(sourceCacheIndex) <> 0 Then _
        Return session_ScoreStemDirection(sourceCacheIndex)

    Dim As Integer sourceX
    Dim As Integer sourceY
    session_NoteScreenPosition sourceNote, screenWidth, screenHeight, _
        sourceX, sourceY
    Dim As Integer sourceStaffY = session_ScoreStaffYForTrack( _
        sourceNote.trackIndex, screenHeight)
    Dim As Integer staffMiddleOffset = scoreLayout_LineSpacing( _
        session_ScoreTrackRowHeight) * 2
    Dim As Integer automaticDirection = 1
    If sourceY < sourceStaffY + staffMiddleOffset Then
        automaticDirection = 0
    End If

    Dim As Integer hasLowerNote = 0
    Dim As Integer hasHigherNote = 0
    Dim As Integer chordNoteCount = 1
    Dim As Long chordYTotal = sourceY
    For candidateCacheIndex As Integer = 0 To _
        session_ScoreVisibleNoteCount - 1
        Dim As Integer candidateIndex = _
            session_ScoreVisibleNoteIndices(candidateCacheIndex)
        If candidateIndex = sourceIndex Then
            Continue For
        End If
        Dim As MidiEditableNote candidateNote
        If midi_GetEditableNote(candidateIndex, candidateNote) = 0 Then
            Continue For
        End If
        If candidateNote.trackIndex <> sourceNote.trackIndex OrElse _
            candidateNote.channel <> sourceNote.channel OrElse _
            candidateNote.startTick <> sourceNote.startTick Then Continue For
        If candidateNote.keyNumber < sourceNote.keyNumber OrElse _
            (candidateNote.keyNumber = sourceNote.keyNumber AndAlso _
             candidateIndex < sourceIndex) Then
            hasLowerNote = -1
        Else
            hasHigherNote = -1
        End If

        Dim As Integer candidateY
        session_NoteScreenPosition candidateNote, screenWidth, screenHeight, _
            sourceX, candidateY
        chordYTotal += candidateY
        chordNoteCount += 1
    Next

    Dim As Integer resolvedDirection = automaticDirection
    If chordNoteCount > 1 Then
        ' A chord is one visual voice in this preview. Average its notehead
        ' positions so every note receives the same stem direction instead of
        ' producing opposing stems for the upper and lower chord members.
        Dim As Integer chordAverageY = CInt(chordYTotal \ chordNoteCount)
        automaticDirection = 1
        If chordAverageY < sourceStaffY + staffMiddleOffset Then _
            automaticDirection = 0
        resolvedDirection = automaticDirection
    ElseIf hasHigherNote <> 0 AndAlso hasLowerNote = 0 Then
        resolvedDirection = 1
    ElseIf hasLowerNote <> 0 AndAlso hasHigherNote = 0 Then
        resolvedDirection = 0
    End If

    If sourceCacheIndex >= 0 Then
        session_ScoreStemDirection(sourceCacheIndex) = resolvedDirection
        session_ScoreStemComputed(sourceCacheIndex) = -1
    End If
    Return resolvedDirection
End Function


Private Function session_FindBeamPartner( _
    ByVal sourceIndex As Integer, _
    ByRef sourceNote As MidiEditableNote, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal quarterTicks As ULongInt, _
    ByRef partnerIndex As Integer _
) As Integer
    partnerIndex = -1
    Dim As Integer sourceCacheIndex = _
        session_ScoreCachePositionForModel(sourceIndex)
    If sourceCacheIndex >= 0 AndAlso _
        session_ScoreBeamComputed(sourceCacheIndex) <> 0 Then
        partnerIndex = session_ScoreBeamPartner(sourceCacheIndex)
        Return IIf(partnerIndex >= 0, -1, 0)
    End If
    If quarterTicks = 0 Then
        If sourceCacheIndex >= 0 Then _
            session_ScoreBeamComputed(sourceCacheIndex) = -1
        Return 0
    End If

    Dim As Integer sourceStemUp = session_NoteStemDirection(sourceIndex, _
        sourceNote, screenWidth, screenHeight)
    Dim As ULongInt sourceEnd = sourceNote.startTick
    If sourceNote.durationTicks > OSE_MAX_MIDI_TICK - sourceEnd Then
        sourceEnd = OSE_MAX_MIDI_TICK
    Else
        sourceEnd += sourceNote.durationTicks
    End If
    If sourceEnd > session_ScoreNextMeasureBoundary(sourceNote.startTick) Then
        If sourceCacheIndex >= 0 Then _
            session_ScoreBeamComputed(sourceCacheIndex) = -1
        Return 0
    End If

    Dim As Integer sourceDurationCode
    Dim As Integer sourceHeadFilled
    Dim As Integer sourceStemRequired
    Dim As Integer sourceFlagCount
    Dim As Integer sourceDotted
    session_ClassifyNoteDuration sourceNote, quarterTicks, _
        sourceDurationCode, sourceHeadFilled, sourceStemRequired, _
        sourceFlagCount, sourceDotted
    If sourceFlagCount <= 0 Then
        If sourceCacheIndex >= 0 Then _
            session_ScoreBeamComputed(sourceCacheIndex) = -1
        Return 0
    End If

    Dim As ULongInt sourceMeasure = session_ScoreMeasureNumber( _
        sourceNote.startTick)
    Dim As ULongInt nearestForwardGap = CULngInt(-1)
    Dim As Integer nearestForwardIndex = -1
    Dim As ULongInt nearestBackwardGap = CULngInt(-1)
    Dim As Integer nearestBackwardIndex = -1

    For candidateCacheIndex As Integer = 0 To _
        session_ScoreVisibleNoteCount - 1
        Dim As Integer candidateIndex = _
            session_ScoreVisibleNoteIndices(candidateCacheIndex)
        If candidateIndex = sourceIndex Then
            Continue For
        End If
        Dim As MidiEditableNote candidateNote
        If midi_GetEditableNote(candidateIndex, candidateNote) = 0 Then
            Continue For
        End If
        If candidateNote.trackIndex <> sourceNote.trackIndex OrElse _
            candidateNote.channel <> sourceNote.channel Then Continue For
        If session_NoteIsVisible(candidateNote) = 0 Then
            Continue For
        End If
        If candidateNote.startTick = sourceNote.startTick Then
            Continue For
        End If
        Dim As ULongInt candidateEnd = candidateNote.startTick
        If candidateNote.durationTicks > OSE_MAX_MIDI_TICK - candidateEnd Then
            candidateEnd = OSE_MAX_MIDI_TICK
        Else
            candidateEnd += candidateNote.durationTicks
        End If
        If candidateEnd > session_ScoreNextMeasureBoundary( _
            candidateNote.startTick) Then Continue For

        Dim As ULongInt candidateMeasure = session_ScoreMeasureNumber( _
            candidateNote.startTick)
        If candidateMeasure <> sourceMeasure Then
            Continue For
        End If

        Dim As ULongInt noteGap
        If candidateNote.startTick > sourceNote.startTick Then
            noteGap = candidateNote.startTick - sourceNote.startTick
        Else
            noteGap = sourceNote.startTick - candidateNote.startTick
        End If
        If noteGap = 0 OrElse noteGap > quarterTicks Then
            Continue For
        End If

        Dim As Integer candidateStemUp = session_NoteStemDirection( _
            candidateIndex, candidateNote, screenWidth, screenHeight)
        If candidateStemUp <> sourceStemUp Then
            Continue For
        End If

        Dim As Integer candidateDurationCode
        Dim As Integer candidateHeadFilled
        Dim As Integer candidateStemRequired
        Dim As Integer candidateFlagCount
        Dim As Integer candidateDotted
        session_ClassifyNoteDuration candidateNote, quarterTicks, _
            candidateDurationCode, candidateHeadFilled, candidateStemRequired, _
            candidateFlagCount, candidateDotted
        If candidateFlagCount <= 0 Then
            Continue For
        End If

        If candidateNote.startTick > sourceNote.startTick Then
            If noteGap < nearestForwardGap Then
                nearestForwardGap = noteGap
                nearestForwardIndex = candidateIndex
            End If
        ElseIf noteGap < nearestBackwardGap Then
            nearestBackwardGap = noteGap
            nearestBackwardIndex = candidateIndex
        End If
    Next

    ' Prefer a forward neighbor so a run of three or more notes is rendered
    ' as one connected beam chain. A final note still counts as beamed through
    ' its backward neighbor, whose beam was drawn by the preceding note.
    Dim As Integer nearestIndex = nearestForwardIndex
    If nearestIndex < 0 Then
        nearestIndex = nearestBackwardIndex
    End If
    If sourceCacheIndex >= 0 Then
        session_ScoreBeamPartner(sourceCacheIndex) = nearestIndex
        session_ScoreBeamComputed(sourceCacheIndex) = -1
    End If
    If nearestIndex < 0 Then
        Return 0
    End If
    partnerIndex = nearestIndex
    Return -1
End Function


Private Sub session_DrawScoreBeams( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal quarterTicks As ULongInt _
)
    Dim As Integer drawnBeamCount = 0
    Dim As Integer headOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 4)
    Dim As Integer beamSeparation = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 5)
    Dim As Integer beamThickness = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 3)
    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer visibleTrackCount = session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer lastTrack = firstTrack + visibleTrackCount - 1
    For cacheIndex As Integer = 0 To session_ScoreVisibleNoteCount - 1
        Dim As Integer noteIndex = session_ScoreVisibleNoteIndices(cacheIndex)
        Dim As MidiEditableNote firstNote
        If midi_GetEditableNote(noteIndex, firstNote) = 0 Then
            Continue For
        End If
        If firstNote.trackIndex < firstTrack OrElse _
            firstNote.trackIndex > lastTrack Then Continue For
        If session_NoteIsVisible(firstNote) = 0 Then
            Continue For
        End If

        Dim As Integer secondIndex
        If session_FindBeamPartner(noteIndex, firstNote, screenWidth, _
            screenHeight, quarterTicks, secondIndex) = 0 Then
            Continue For
        End If
        Dim As MidiEditableNote secondNote
        If midi_GetEditableNote(secondIndex, secondNote) = 0 Then
            Continue For
        End If
        If session_NoteIsVisible(secondNote) = 0 Then
            Continue For
        End If
        ' Draw each forward-time connection once. The editable-note array is
        ' not required to be sorted after user edits, so array indices cannot
        ' determine which note is first on the staff.
        If secondNote.startTick <= firstNote.startTick Then
            Continue For
        End If

        Dim As Integer firstX
        Dim As Integer firstY
        Dim As Integer secondX
        Dim As Integer secondY
        session_NoteScreenPosition firstNote, screenWidth, screenHeight, _
            firstX, firstY
        session_NoteScreenPosition secondNote, screenWidth, screenHeight, _
            secondX, secondY
        Dim As Integer stemUp = session_NoteStemDirection(noteIndex, firstNote, _
            screenWidth, screenHeight)

        Dim As Integer firstDurationCode
        Dim As Integer firstHeadFilled
        Dim As Integer firstStemRequired
        Dim As Integer firstFlagCount
        Dim As Integer firstDotted
        session_ClassifyNoteDuration firstNote, quarterTicks, _
            firstDurationCode, firstHeadFilled, firstStemRequired, _
            firstFlagCount, firstDotted
        Dim As Integer secondDurationCode
        Dim As Integer secondHeadFilled
        Dim As Integer secondStemRequired
        Dim As Integer secondFlagCount
        Dim As Integer secondDotted
        session_ClassifyNoteDuration secondNote, quarterTicks, _
            secondDurationCode, secondHeadFilled, secondStemRequired, _
            secondFlagCount, secondDotted
        Dim As Integer beamCount = firstFlagCount
        If secondFlagCount < beamCount Then
            beamCount = secondFlagCount
        End If
        If beamCount <= 0 Then
            Continue For
        End If

        Dim As Integer beamStaffY = session_ScoreStaffYForTrack( _
            firstNote.trackIndex, screenHeight)
        Dim As Integer firstStemEndY = session_ScoreBeamBaselineY( _
            beamStaffY, stemUp)
        Dim As Integer firstStemX = firstX + headOffset
        Dim As Integer secondStemX = secondX + headOffset
        If stemUp = 0 Then
            firstStemX = firstX - headOffset
            secondStemX = secondX - headOffset
        End If

        For beamIndex As Integer = 0 To beamCount - 1
            Dim As Integer beamOffset = beamIndex * beamSeparation
            Dim As Integer beamY1 = firstStemEndY + beamOffset
            If stemUp = 0 Then
                beamY1 = firstStemEndY - beamOffset
            End If
            Dim As Integer beamLeft = firstStemX
            Dim As Integer beamRight = secondStemX
            If beamLeft > beamRight Then
                Swap beamLeft, beamRight
            End If
            backend_Rect beamLeft, beamY1 - beamThickness \ 2, _
                beamRight - beamLeft + 1, beamThickness, _
                session_ThemePalette.textColor, 1
        Next
        drawnBeamCount += 1
        If drawnBeamCount >= 512 Then
            Exit For
        End If
    Next
End Sub


Private Sub session_DrawScorePartialBeams( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal quarterTicks As ULongInt _
)
    Dim As Integer headOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 4)
    Dim As Integer beamSeparation = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 5)
    Dim As Integer partialBeamLength = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 10)
    Dim As Integer beamThickness = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 3)
    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer visibleTrackCount = session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer lastTrack = firstTrack + visibleTrackCount - 1
    Dim As Integer drawnPartialCount = 0

    For cacheIndex As Integer = 0 To session_ScoreVisibleNoteCount - 1
        Dim As Integer noteIndex = session_ScoreVisibleNoteIndices(cacheIndex)
        Dim As MidiEditableNote sourceNote
        If midi_GetEditableNote(noteIndex, sourceNote) = 0 Then
            Continue For
        End If
        If sourceNote.trackIndex < firstTrack OrElse _
            sourceNote.trackIndex > lastTrack Then Continue For
        If session_NoteIsVisible(sourceNote) = 0 Then
            Continue For
        End If

        Dim As Integer partnerIndex
        If session_FindBeamPartner(noteIndex, sourceNote, screenWidth, _
            screenHeight, quarterTicks, partnerIndex) = 0 Then Continue For
        Dim As MidiEditableNote partnerNote
        If midi_GetEditableNote(partnerIndex, partnerNote) = 0 Then
            Continue For
        End If

        Dim As Integer sourceDurationCode
        Dim As Integer sourceHeadFilled
        Dim As Integer sourceStemRequired
        Dim As Integer sourceFlagCount
        Dim As Integer sourceDotted
        session_ClassifyNoteDuration sourceNote, quarterTicks, _
            sourceDurationCode, sourceHeadFilled, sourceStemRequired, _
            sourceFlagCount, sourceDotted
        If sourceFlagCount <= 0 Then
            Continue For
        End If

        Dim As Integer partnerDurationCode
        Dim As Integer partnerHeadFilled
        Dim As Integer partnerStemRequired
        Dim As Integer partnerFlagCount
        Dim As Integer partnerDotted
        session_ClassifyNoteDuration partnerNote, quarterTicks, _
            partnerDurationCode, partnerHeadFilled, partnerStemRequired, _
            partnerFlagCount, partnerDotted
        Dim As Integer commonBeamCount = sourceFlagCount
        If partnerFlagCount < commonBeamCount Then _
            commonBeamCount = partnerFlagCount
        If sourceFlagCount <= commonBeamCount Then
            Continue For
        End If

        Dim As Integer sourceX
        Dim As Integer sourceY
        session_NoteScreenPosition sourceNote, screenWidth, screenHeight, _
            sourceX, sourceY
        Dim As Integer stemUp = session_NoteStemDirection(noteIndex, _
            sourceNote, screenWidth, screenHeight)
        Dim As Integer stemX = sourceX + headOffset
        Dim As Integer beamStaffY = session_ScoreStaffYForTrack( _
            sourceNote.trackIndex, screenHeight)
        Dim As Integer stemEndY = session_ScoreBeamBaselineY( _
            beamStaffY, stemUp)
        If stemUp = 0 Then
            stemX = sourceX - headOffset
        End If
        Dim As Integer towardRight = 0
        If partnerNote.startTick > sourceNote.startTick Then
            towardRight = -1
        End If
        For beamIndex As Integer = commonBeamCount To sourceFlagCount - 1
            Dim As Integer beamY = stemEndY + beamIndex * beamSeparation
            If stemUp = 0 Then _
                beamY = stemEndY - beamIndex * beamSeparation
            Dim As Integer beamEndX = stemX - partialBeamLength
            If towardRight <> 0 Then
                beamEndX = stemX + partialBeamLength
            End If
            Dim As Integer beamLeft = stemX
            Dim As Integer beamRight = beamEndX
            If beamLeft > beamRight Then
                Swap beamLeft, beamRight
            End If
            backend_Rect beamLeft, beamY - beamThickness \ 2, _
                beamRight - beamLeft + 1, beamThickness, _
                session_ThemePalette.textColor, 1
            drawnPartialCount += 1
            If drawnPartialCount >= 1024 Then
                Exit For
            End If
        Next
        If drawnPartialCount >= 1024 Then
            Exit For
        End If
    Next
End Sub


Private Sub session_DrawScoreTies( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal noteColor As ULong _
)
    Dim As Integer drawnTieCount = 0
    Dim As Integer tieHeadInset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 5)
    Dim As Integer tieMinimumSpan = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 12)
    Dim As Integer tieCurveOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 9)
    Dim As Integer tieControlOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 8)
    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer visibleTrackCount = session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer lastTrack = firstTrack + visibleTrackCount - 1
    For cacheIndex As Integer = 0 To session_ScoreVisibleNoteCount - 1
        Dim As Integer noteIndex = session_ScoreVisibleNoteIndices(cacheIndex)
        Dim As MidiEditableNote firstNote
        If midi_GetEditableNote(noteIndex, firstNote) = 0 Then
            Continue For
        End If
        If firstNote.trackIndex < firstTrack OrElse _
            firstNote.trackIndex > lastTrack Then Continue For
        If session_NoteIsVisible(firstNote) = 0 Then
            Continue For
        End If

        Dim As ULongInt firstEnd = firstNote.startTick + _
            firstNote.durationTicks
        If firstEnd < firstNote.startTick Then
            Continue For
        End If
        Dim As Integer successorIndex = -1
        For candidateCacheIndex As Integer = 0 To _
            session_ScoreVisibleNoteCount - 1
            Dim As Integer candidateIndex = _
                session_ScoreVisibleNoteIndices(candidateCacheIndex)
            If candidateIndex = noteIndex Then
                Continue For
            End If
            Dim As MidiEditableNote candidateNote
            If midi_GetEditableNote(candidateIndex, candidateNote) = 0 Then
                Continue For
            End If
            If candidateNote.trackIndex <> firstNote.trackIndex OrElse _
                candidateNote.channel <> firstNote.channel OrElse _
                candidateNote.keyNumber <> firstNote.keyNumber Then Continue For
            If candidateNote.startTick <> firstEnd Then
                Continue For
            End If
            successorIndex = candidateIndex
            Exit For
        Next
        If successorIndex < 0 Then
            Continue For
        End If

        Dim As MidiEditableNote secondNote
        If midi_GetEditableNote(successorIndex, secondNote) = 0 Then
            Continue For
        End If
        If session_NoteIsVisible(secondNote) = 0 Then
            Continue For
        End If

        Dim As Integer firstX
        Dim As Integer firstY
        Dim As Integer secondX
        Dim As Integer secondY
        session_NoteScreenPosition firstNote, screenWidth, screenHeight, _
            firstX, firstY
        session_NoteScreenPosition secondNote, screenWidth, screenHeight, _
            secondX, secondY
        If secondX <= firstX + tieMinimumSpan Then
            Continue For
        End If

        Dim As Integer curveY = firstY + tieCurveOffset
        If secondY > curveY Then
            curveY = secondY + tieCurveOffset
        End If
        Dim As Integer controlX = (firstX + secondX) \ 2
        backend_Curve firstX + tieHeadInset, firstY + tieHeadInset, _
            controlX, curveY + tieControlOffset, _
            secondX - tieHeadInset, secondY + tieHeadInset, noteColor
        drawnTieCount += 1
        If drawnTieCount >= 512 Then
            Exit For
        End If
    Next
End Sub


Private Sub session_DrawScoreNotes( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal quarterTicks As ULongInt, _
    ByVal sharpsFlats As Integer _
)
    Dim As Integer tieMinimumSpan = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 4)
    Dim As Integer tieHeadInset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 5)
    Dim As Integer tieCurveOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 9)
    Dim As Integer tieControlOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 8)
    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer visibleTrackCount = session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer lastTrack = firstTrack + visibleTrackCount - 1
    For cacheIndex As Integer = 0 To session_ScoreVisibleNoteCount - 1
        Dim As Integer noteIndex = session_ScoreVisibleNoteIndices(cacheIndex)
        Dim As MidiEditableNote editableNote
        If midi_GetEditableNote(noteIndex, editableNote) = 0 Then
            Continue For
        End If
        If editableNote.trackIndex < firstTrack OrElse _
            editableNote.trackIndex > lastTrack Then Continue For
        If session_NoteIsVisible(editableNote) = 0 Then
            Continue For
        End If

        Dim As ULong noteColor = Iif(session_NoteIsSelected(noteIndex) <> 0, _
            session_ThemePalette.warningColor, session_ThemePalette.textColor)

        Dim As Integer noteStaffY = session_ScoreStaffYForTrack( _
            editableNote.trackIndex, screenHeight)
        Dim As Integer beamPartnerIndex
        Dim As Integer isBeamed = session_FindBeamPartner(noteIndex, _
            editableNote, screenWidth, screenHeight, quarterTicks, beamPartnerIndex)
        Dim As Integer stemDirection = session_NoteStemDirection(noteIndex, _
            editableNote, screenWidth, screenHeight)

        Dim As ULongInt noteEnd = editableNote.startTick
        If editableNote.durationTicks > OSE_MAX_MIDI_TICK - noteEnd Then
            noteEnd = OSE_MAX_MIDI_TICK
        Else
            noteEnd += editableNote.durationTicks
        End If
        If noteEnd <= editableNote.startTick Then
            Continue For
        End If

        Dim As Integer splitNote = 0
        If session_ScoreNextMeasureBoundary(editableNote.startTick) < noteEnd Then _
            splitNote = -1
        Dim As ULongInt segmentStart = editableNote.startTick
        Dim As Integer segmentIndex = 0
        Dim As Integer previousX = -1
        Dim As Integer previousY = 0
        While segmentStart < noteEnd
            Dim As ULongInt segmentEnd = noteEnd
            If segmentIndex < SESSION_MAX_SCORE_NOTE_SEGMENTS - 1 Then
                Dim As ULongInt measureBoundary = _
                    session_ScoreNextMeasureBoundary(segmentStart)
                If measureBoundary > segmentStart AndAlso _
                    measureBoundary < segmentEnd Then
                    segmentEnd = measureBoundary
                End If
            End If
            If segmentEnd <= segmentStart Then
                Exit While
            End If

            Dim As MidiEditableNote displayNote = editableNote
            displayNote.startTick = segmentStart
            displayNote.durationTicks = segmentEnd - segmentStart

            Dim As Integer segmentNoteX
            Dim As Integer segmentNoteY
            session_NoteScreenPosition displayNote, screenWidth, screenHeight, _
                segmentNoteX, segmentNoteY

            Dim As Integer segmentSharpsFlats = sharpsFlats
            Dim As Integer segmentKeyIndex = session_KeySignatureIndexForTick( _
                segmentStart)
            If segmentKeyIndex >= 0 AndAlso segmentKeyIndex < _
                session_Summary.keySignatureCount Then
                segmentSharpsFlats = session_Summary.keySignatureMap( _
                    segmentKeyIndex).sharpsFlats
            End If

            Dim As Integer segmentBeamed = isBeamed
            If splitNote <> 0 Then
                segmentBeamed = 0
            End If
            Dim As Integer suppressAccidental = 0
            If segmentIndex > 0 Then
                suppressAccidental = -1
            End If
            session_DrawScoreNote displayNote, segmentNoteX, segmentNoteY, _
                noteStaffY, noteColor, quarterTicks, segmentSharpsFlats, _
                segmentBeamed, stemDirection, suppressAccidental

            If previousX >= 0 AndAlso _
                segmentNoteX > previousX + tieMinimumSpan Then
                Dim As Integer curveY = previousY + tieCurveOffset
                If segmentNoteY > curveY Then _
                    curveY = segmentNoteY + tieCurveOffset
                Dim As Integer controlX = (previousX + segmentNoteX) \ 2
                backend_Curve previousX + tieHeadInset, _
                    previousY + tieHeadInset, controlX, _
                    curveY + tieControlOffset, _
                    segmentNoteX - tieHeadInset, _
                    segmentNoteY + tieHeadInset, noteColor
            End If
            previousX = segmentNoteX
            previousY = segmentNoteY
            segmentIndex += 1
            If segmentEnd >= noteEnd Then
                Exit While
            End If
            segmentStart = segmentEnd
        Wend
    Next

    session_DrawScoreBeams screenWidth, screenHeight, quarterTicks
    session_DrawScorePartialBeams screenWidth, screenHeight, quarterTicks
    session_DrawScoreTies screenWidth, screenHeight, session_ThemePalette.textColor
End Sub


Private Function session_TimeSignatureBeatTicks( _
    ByRef signaturePoint As MidiTimeSignaturePoint _
) As ULongInt
    If session_Summary.division <= 0 Then
        Return 1
    End If

    Dim As ULongInt beatTicks = CULngInt(session_Summary.division) * 4
    For powerIndex As Integer = 1 To signaturePoint.denominatorPower
        beatTicks \= 2
    Next
    If beatTicks = 0 Then
        beatTicks = 1
    End If
    Return beatTicks
End Function


Private Function session_TimeSignatureMeasureTicks( _
    ByRef signaturePoint As MidiTimeSignaturePoint _
) As ULongInt
    Dim As ULongInt measureTicks = _
        session_TimeSignatureBeatTicks(signaturePoint) * _
        CULngInt(signaturePoint.numerator)
    If measureTicks = 0 Then
        measureTicks = 1
    End If
    Return measureTicks
End Function


Private Function session_ScoreTickToX( _
    ByVal tick As ULongInt, _
    ByVal scoreLeft As Integer, _
    ByVal scoreRight As Integer, _
    ByVal ticksPerView As ULongInt _
) As Integer
    If tick <= session_ViewStartTick Then
        Return scoreLeft
    End If
    If tick >= session_ViewStartTick + ticksPerView Then
        Return scoreRight
    End If
    Return scoreLeft + CInt((CDbl(scoreRight - scoreLeft) * _
        CDbl(tick - session_ViewStartTick)) / CDbl(ticksPerView))
End Function


Private Sub session_DrawKeySignature( _
    ByVal scoreLeft As Integer, _
    ByVal firstStaffY As Integer, _
    ByVal staffGap As Integer, _
    ByVal staffCount As Integer, _
    ByVal firstTrack As Integer, _
    ByVal sharpsFlats As Integer _
)
    If sharpsFlats < -7 Then
        sharpsFlats = -7
    End If
    If sharpsFlats > 7 Then
        sharpsFlats = 7
    End If
    If sharpsFlats = 0 Then
        Exit Sub
    End If

    Dim As Integer accidentalCount = Abs(sharpsFlats)
    Dim As String accidentalText = "#"
    If sharpsFlats < 0 Then
        accidentalText = "b"
    End If
    Dim As Integer trebleSharpY(0 To 6) = {0, 7, -7, 4, 11, -3, 18}
    Dim As Integer trebleFlatY(0 To 6) = {14, 7, 21, 4, 28, 11, 18}
    Dim As Integer bassSharpY(0 To 6) = {7, 21, 4, 18, 0, 14, 28}
    Dim As Integer bassFlatY(0 To 6) = {0, 14, 7, 21, 4, 18, 11}

    For staffIndex As Integer = 0 To staffCount - 1
        Dim As Integer staffY = firstStaffY + staffIndex * staffGap
        Dim As Integer trackIndex = firstTrack + staffIndex
        Dim As Integer usesBassClef = session_TrackUsesBassClef(trackIndex)
        For accidentalIndex As Integer = 0 To accidentalCount - 1
            Dim As Integer accidentalY
            If usesBassClef = 0 Then
                If sharpsFlats > 0 Then
                    accidentalY = trebleSharpY(accidentalIndex)
                Else
                    accidentalY = trebleFlatY(accidentalIndex)
                End If
            Else
                If sharpsFlats > 0 Then
                    accidentalY = bassSharpY(accidentalIndex)
                Else
                    accidentalY = bassFlatY(accidentalIndex)
                End If
            End If
            accidentalY = scoreLayout_ScalePixels( _
                session_ScoreTrackRowHeight, accidentalY)
            session_DrawAccidental accidentalText, _
                scoreLeft + 15 + accidentalIndex * 7, _
                staffY + accidentalY, session_ThemePalette.textColor
        Next
    Next
End Sub


Private Sub session_DrawStaffTimeSignature( _
    ByVal staffY As Integer, ByVal numerator As Integer, ByVal denominator As Integer _
)
    ' The fixed gutter already reserves space after the clef and up to seven
    ' key accidentals. Stack the two numbers there, before the note timeline.
    Dim As Integer halfHeight = scoreLayout_LineSpacing(session_ScoreTrackRowHeight) * 2
    Dim As Integer fontId = BACKEND_FONT_UI_12_BOLD
    If backend_GetTextHeightFont(fontId) > halfHeight Then
        fontId = BACKEND_FONT_DEFAULT
    End If
    If backend_GetTextHeightFont(BACKEND_FONT_UI_18_BOLD) <= halfHeight Then _
        fontId = BACKEND_FONT_UI_18_BOLD
    backend_PrintAligned SESSION_SCORE_LEFT + 112, staffY, 42, halfHeight, _
        session_ThemePalette.textColor, LTrim(Str(numerator)), fontId, _
        BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE
    backend_PrintAligned SESSION_SCORE_LEFT + 112, staffY + halfHeight, 42, halfHeight, _
        session_ThemePalette.textColor, LTrim(Str(denominator)), fontId, _
        BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE
End Sub


Private Function session_ScoreIsMeasureStart(ByVal tick As ULongInt) As Integer
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick(tick)
    If signatureIndex < 0 OrElse _
        signatureIndex >= session_Summary.timeSignatureCount Then Return 0
    Dim As MidiTimeSignaturePoint signaturePoint = _
        session_Summary.timeSignatureMap(signatureIndex)
    Dim As ULongInt measureTicks = _
        session_TimeSignatureMeasureTicks(signaturePoint)
    If tick < signaturePoint.tick OrElse measureTicks = 0 Then
        Return 0
    End If
    If (tick - signaturePoint.tick) Mod measureTicks = 0 Then
        Return -1
    End If
    Return 0
End Function


Private Function session_ScoreMeasureNumber(ByVal tick As ULongInt) As ULongInt
    If session_Summary.timeSignatureCount <= 0 Then
        Return 1
    End If

    Dim As ULongInt completedMeasures = 0
    For signatureIndex As Integer = 0 To _
        session_Summary.timeSignatureCount - 1
        Dim As MidiTimeSignaturePoint signaturePoint = _
            session_Summary.timeSignatureMap(signatureIndex)
        Dim As ULongInt segmentStart = signaturePoint.tick
        If tick < segmentStart Then
            Exit For
        End If
        Dim As ULongInt segmentEnd = tick
        If signatureIndex + 1 < session_Summary.timeSignatureCount Then
            Dim As ULongInt nextTick = _
                session_Summary.timeSignatureMap(signatureIndex + 1).tick
            If nextTick < segmentEnd Then
                segmentEnd = nextTick
            End If
        End If
        Dim As ULongInt measureTicks = _
            session_TimeSignatureMeasureTicks(signaturePoint)
        If measureTicks > 0 AndAlso segmentEnd >= segmentStart Then
            completedMeasures += (segmentEnd - segmentStart) \ measureTicks
        End If
        If segmentEnd = tick Then
            Exit For
        End If
    Next
    Return completedMeasures + 1
End Function


Private Sub session_MusicalPosition( _
    ByVal tick As ULongInt, _
    ByRef measureNumber As ULongInt, _
    ByRef beatNumber As ULongInt, _
    ByRef subTick As ULongInt _
)
    measureNumber = session_ScoreMeasureNumber(tick)
    beatNumber = 1
    subTick = 0

    Dim As ULongInt segmentStart
    Dim As ULongInt beatTicks = 1
    If session_Summary.division > 0 Then _
        beatTicks = CULngInt(session_Summary.division)
    Dim As ULongInt measureTicks = beatTicks * 4
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick(tick)
    If signatureIndex >= 0 AndAlso _
        signatureIndex < session_Summary.timeSignatureCount Then
        Dim As MidiTimeSignaturePoint signaturePoint = _
            session_Summary.timeSignatureMap(signatureIndex)
        segmentStart = signaturePoint.tick
        beatTicks = session_TimeSignatureBeatTicks(signaturePoint)
        measureTicks = session_TimeSignatureMeasureTicks(signaturePoint)
    End If
    If beatTicks = 0 Then
        beatTicks = 1
    End If
    If measureTicks = 0 Then
        measureTicks = beatTicks
    End If
    If tick < segmentStart Then
        Exit Sub
    End If

    Dim As ULongInt offsetInMeasure = _
        (tick - segmentStart) Mod measureTicks
    beatNumber = offsetInMeasure \ beatTicks + 1
    subTick = offsetInMeasure Mod beatTicks
End Sub


Private Function session_MusicalPositionText( _
    ByVal tick As ULongInt _
) As String
    Dim As ULongInt measureNumber
    Dim As ULongInt beatNumber
    Dim As ULongInt subTick
    session_MusicalPosition tick, measureNumber, beatNumber, subTick
    Return LTrim(Str(measureNumber)) + ":" + LTrim(Str(beatNumber)) + _
        ":" + LTrim(Str(subTick))
End Function


Private Function session_ScoreNextMeasureBoundary( _
    ByVal tick As ULongInt _
) As ULongInt
    If tick >= OSE_MAX_MIDI_TICK Then
        Return OSE_MAX_MIDI_TICK
    End If

    Dim As ULongInt segmentStart = 0
    Dim As ULongInt measureTicks = CULngInt(session_Summary.division) * 4
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick(tick)
    If signatureIndex >= 0 AndAlso signatureIndex < _
        session_Summary.timeSignatureCount Then
        Dim As MidiTimeSignaturePoint signaturePoint = _
            session_Summary.timeSignatureMap(signatureIndex)
        segmentStart = signaturePoint.tick
        measureTicks = session_TimeSignatureMeasureTicks(signaturePoint)
    End If
    If measureTicks = 0 Then
        measureTicks = 1
    End If
    If tick < segmentStart Then
        Return segmentStart
    End If

    Dim As ULongInt elapsedTicks = tick - segmentStart
    Dim As ULongInt measureIndex = elapsedTicks \ measureTicks
    Dim As ULongInt measureStep = measureIndex + 1
    Dim As ULongInt nextBoundary = OSE_MAX_MIDI_TICK
    If measureStep <= (OSE_MAX_MIDI_TICK - segmentStart) \ measureTicks Then
        nextBoundary = segmentStart + measureStep * measureTicks
    End If

    If signatureIndex >= 0 AndAlso signatureIndex + 1 < _
        session_Summary.timeSignatureCount Then
        Dim As ULongInt nextSignatureTick = _
            session_Summary.timeSignatureMap(signatureIndex + 1).tick
        If nextSignatureTick < nextBoundary Then
            nextBoundary = nextSignatureTick
        End If
    End If

    If nextBoundary <= tick Then
        nextBoundary = tick + 1
    End If
    If nextBoundary > OSE_MAX_MIDI_TICK Then _
        nextBoundary = OSE_MAX_MIDI_TICK
    Return nextBoundary
End Function


Private Sub session_DrawScoreMeterGuides( _
    ByVal scoreLeft As Integer, _
    ByVal scoreRight As Integer, _
    ByVal firstStaffY As Integer, _
    ByVal staffGap As Integer, _
    ByVal staffCount As Integer, _
    ByVal ticksPerView As ULongInt _
)
    If session_Summary.timeSignatureCount <= 0 Then
        Exit Sub
    End If
    Dim As Integer lineSpacing = scoreLayout_LineSpacing( _
        session_ScoreTrackRowHeight)
    Dim As Integer staffHeight = lineSpacing * 4
    Dim As Integer guideMargin = (lineSpacing + 1) \ 2

    Dim As ULongInt viewEndTick = session_ViewStartTick + ticksPerView
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick( _
        session_ViewStartTick)
    If signatureIndex < 0 Then
        signatureIndex = 0
    End If
    Dim As ULongInt segmentStart = session_ViewStartTick
    Dim As Integer drawnGuideCount = 0

    While signatureIndex < session_Summary.timeSignatureCount
        Dim As MidiTimeSignaturePoint signaturePoint = _
            session_Summary.timeSignatureMap(signatureIndex)
        Dim As ULongInt segmentEnd = viewEndTick
        If signatureIndex + 1 < session_Summary.timeSignatureCount Then
            Dim As ULongInt nextSignatureTick = _
                session_Summary.timeSignatureMap(signatureIndex + 1).tick
            If nextSignatureTick < segmentEnd Then
                segmentEnd = nextSignatureTick
            End If
        End If

        Dim As ULongInt beatTicks = _
            session_TimeSignatureBeatTicks(signaturePoint)
        Dim As ULongInt measureTicks = _
            session_TimeSignatureMeasureTicks(signaturePoint)
        Dim As ULongInt firstGuideTick = signaturePoint.tick
        If firstGuideTick < segmentStart Then
            Dim As ULongInt elapsedTicks = segmentStart - firstGuideTick
            Dim As ULongInt beatNumber = elapsedTicks \ beatTicks
            If elapsedTicks Mod beatTicks <> 0 Then
                beatNumber += 1
            End If
            firstGuideTick += beatNumber * beatTicks
        End If

        Dim As ULongInt guideTick = firstGuideTick
        While guideTick <= segmentEnd AndAlso guideTick <= viewEndTick
            Dim As Integer beatX = session_ScoreTickToX(guideTick, _
                scoreLeft, scoreRight, ticksPerView)
            Dim As ULong guideColor = session_ThemePalette.scoreGuideColor
            Dim As Integer isMeasureStart = 0
            If (guideTick - signaturePoint.tick) Mod measureTicks = 0 Then
                guideColor = session_ThemePalette.scoreStrongGuideColor
                isMeasureStart = -1
            End If
            For staffIndex As Integer = 0 To staffCount - 1
                Dim As Integer staffY = firstStaffY + staffIndex * staffGap
                If isMeasureStart <> 0 Then
                    backend_LineEx beatX, staffY - lineSpacing, beatX, _
                        staffY + staffHeight + lineSpacing, _
                        session_ThemePalette.scoreStrongGuideColor, 2
                Else
                    backend_Line beatX, staffY - guideMargin, beatX, _
                        staffY + staffHeight + guideMargin, _
                        guideColor
                End If
            Next
            If isMeasureStart <> 0 AndAlso staffCount > 1 Then
                ' Join the individual staff segments so a grand visual system
                ' still reads as one measure boundary across every track row.
                backend_LineEx beatX, firstStaffY - lineSpacing, beatX, _
                    firstStaffY + (staffCount - 1) * staffGap + _
                    staffHeight + lineSpacing, _
                    session_ThemePalette.scoreStrongGuideColor, 2
            End If
            drawnGuideCount += 1
            If drawnGuideCount >= 256 Then
                Exit Sub
            End If
            If beatTicks > viewEndTick - guideTick Then
                Exit While
            End If
            guideTick += beatTicks
        Wend

        If signatureIndex + 1 >= session_Summary.timeSignatureCount Then
            Exit While
        End If
        Dim As ULongInt nextTick = _
            session_Summary.timeSignatureMap(signatureIndex + 1).tick
        If nextTick > viewEndTick Then
            Exit While
        End If
        If nextTick <= segmentStart Then
            signatureIndex += 1
            Continue While
        End If
        Dim As MidiTimeSignaturePoint nextSignature = _
            session_Summary.timeSignatureMap(signatureIndex + 1)
        Dim As Integer signatureX = session_ScoreTickToX(nextTick, _
            scoreLeft, scoreRight, ticksPerView)
        backend_Line signatureX, SESSION_SCORE_TOP + 25, signatureX, _
            SESSION_SCORE_TOP + 34, session_ThemePalette.mutedTextColor
        backend_Print signatureX + 2, SESSION_SCORE_TOP + 26, _
            session_ThemePalette.textColor, Str(nextSignature.numerator) + "/" + _
            Str(session_TempoDenominatorValue(nextSignature.denominatorPower))
        segmentStart = nextTick
        signatureIndex += 1
    Wend
End Sub


Private Sub session_DrawWholeRest( _
    ByVal restX As Integer, _
    ByVal staffY As Integer, _
    ByVal restColor As ULong _
)
    ' The small hanging block is a readable whole-rest glyph at this scale.
    backend_Rect restX - 5, staffY + 7, 10, 5, restColor, 1
    backend_Line restX, staffY + 12, restX, staffY + 20, restColor
End Sub


Private Sub session_DrawRestGlyph( _
    ByVal restX As Integer, _
    ByVal staffY As Integer, _
    ByVal durationCode As Integer, _
    ByVal dotted As Integer, _
    ByVal restColor As ULong _
)
    Select Case durationCode
        Case 0
            session_DrawWholeRest restX, staffY, restColor
        Case 1
            backend_Rect restX - 5, staffY + 3, 10, 5, restColor, 1
            backend_Line restX - 5, staffY + 3, restX + 5, staffY + 3, _
                restColor
        Case 2
            If musicSymbols_HasGlyph(MUSIC_SYMBOL_QUARTER_REST) <> 0 Then
                musicSymbols_DrawCentered MUSIC_SYMBOL_QUARTER_REST, restX, _
                    staffY + 12, restColor
            Else
                backend_Line restX - 4, staffY + 5, restX + 3, _
                    staffY + 9, restColor
                backend_Line restX + 3, staffY + 9, restX - 3, _
                    staffY + 14, restColor
                backend_Line restX - 3, staffY + 14, restX + 4, _
                    staffY + 19, restColor
            End If
        Case 3
            If musicSymbols_HasGlyph(MUSIC_SYMBOL_EIGHTH_REST) <> 0 Then
                musicSymbols_DrawCentered MUSIC_SYMBOL_EIGHTH_REST, restX, _
                    staffY + 12, restColor
            Else
                backend_Line restX, staffY + 5, restX, staffY + 20, restColor
                backend_Line restX, staffY + 5, restX + 8, _
                    staffY + 10, restColor
            End If
        Case Else
            Const REST_FLAG_RISE As Integer = 6
            backend_Line restX, staffY + 5, restX, staffY + 20, restColor
            backend_Line restX, staffY + 5, restX + 8, _
                staffY + 5 + REST_FLAG_RISE, restColor
            If durationCode >= 4 Then
                backend_Line restX, staffY + 9, restX + 8, _
                    staffY + 9 + REST_FLAG_RISE, restColor
            End If
            If durationCode >= 5 Then
                backend_Line restX, staffY + 13, restX + 8, _
                    staffY + 13 + REST_FLAG_RISE, restColor
            End If
            If durationCode >= 6 Then
                backend_Line restX, staffY + 17, restX + 8, _
                    staffY + 17 + REST_FLAG_RISE, restColor
            End If
    End Select

    If dotted <> 0 Then
        If musicSymbols_HasGlyph(MUSIC_SYMBOL_DOT) <> 0 Then
            musicSymbols_DrawCentered MUSIC_SYMBOL_DOT, restX + 10, _
                staffY + 14, restColor
        Else
            backend_Circle restX + 11, staffY + 14, 2, restColor, 1
        End If
    End If
End Sub


Private Sub session_DrawRestSpan( _
    ByVal rangeStart As ULongInt, _
    ByVal rangeEnd As ULongInt, _
    ByVal scoreLeft As Integer, _
    ByVal scoreRight As Integer, _
    ByVal firstStaffY As Integer, _
    ByVal staffIndex As Integer, _
    ByVal staffGap As Integer, _
    ByVal ticksPerView As ULongInt, _
    ByVal quarterTicks As ULongInt, _
    ByVal restColor As ULong, _
    ByRef drawnRestCount As Integer _
)
    If rangeEnd <= rangeStart OrElse quarterTicks = 0 Then
        Exit Sub
    End If

    Dim As ULongInt cursorTick = rangeStart
    While cursorTick < rangeEnd
        Dim As ULongInt remainingTicks = rangeEnd - cursorTick
        Dim As ULongInt chosenTicks = 1
        Dim As Integer chosenCode = 6
        Dim As Integer chosenDotted = 0

        For durationCode As Integer = 0 To 6
            Dim As ULongInt baseTicks = quarterTicks
            Select Case durationCode
                Case 0
                    baseTicks = quarterTicks * 4
                Case 1
                    baseTicks = quarterTicks * 2
                Case 2
                    baseTicks = quarterTicks
                Case 3
                    baseTicks = quarterTicks \ 2
                Case 4
                    baseTicks = quarterTicks \ 4
                Case 5
                    baseTicks = quarterTicks \ 8
                Case Else
                    baseTicks = quarterTicks \ 16
            End Select
            If baseTicks = 0 Then
                Continue For
            End If

            If baseTicks <= remainingTicks AndAlso baseTicks > chosenTicks Then
                chosenTicks = baseTicks
                chosenCode = durationCode
                chosenDotted = 0
            End If
            Dim As ULongInt dottedTicks = baseTicks + baseTicks \ 2
            If dottedTicks <= remainingTicks AndAlso dottedTicks > chosenTicks Then
                chosenTicks = dottedTicks
                chosenCode = durationCode
                chosenDotted = -1
            End If
        Next

        ' A non-standard remainder shorter than a 64th is represented once.
        ' Advancing one tick at a time would stack many glyphs on one pixel and
        ' can produce an opaque blot beside a measure line.
        If chosenTicks = 1 AndAlso remainingTicks > 1 Then
            chosenTicks = remainingTicks
            chosenCode = 6
            chosenDotted = 0
        End If
        If chosenTicks > remainingTicks Then
            chosenTicks = remainingTicks
        End If
        If chosenTicks = 0 Then
            Exit While
        End If
        Dim As ULongInt restEnd = cursorTick + chosenTicks
        If restEnd < cursorTick Then
            restEnd = rangeEnd
        End If
        Dim As ULongInt restCenter = cursorTick + _
            (restEnd - cursorTick) \ 2
        If restCenter >= session_ViewStartTick AndAlso _
            restCenter <= session_ViewStartTick + ticksPerView Then
            Dim As Integer restX = session_ScoreTickToX(restCenter, _
                scoreLeft, scoreRight, ticksPerView)
            Dim As Integer staffY = firstStaffY + staffIndex * staffGap
            session_DrawRestGlyph restX, staffY, chosenCode, chosenDotted, _
                restColor
            drawnRestCount += 1
        End If
        If drawnRestCount >= 1024 Then
            Exit Sub
        End If
        cursorTick = restEnd
    Wend
End Sub


Private Sub session_DrawScoreRests( _
    ByVal scoreLeft As Integer, _
    ByVal scoreRight As Integer, _
    ByVal screenHeight As Integer, _
    ByVal firstStaffY As Integer, _
    ByVal staffGap As Integer, _
    ByVal ticksPerView As ULongInt _
)
    If session_Summary.timeSignatureCount <= 0 OrElse _
        session_Summary.trackCount <= 0 Then Exit Sub

    Dim As ULongInt viewEndTick = session_ViewStartTick + ticksPerView
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick( _
        session_ViewStartTick)
    If signatureIndex < 0 Then
        signatureIndex = 0
    End If
    Dim As ULongInt segmentStart = session_ViewStartTick
    Dim As Integer drawnRestCount = 0
    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer visibleTrackCount = session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer lastTrack = firstTrack + visibleTrackCount - 1

    While signatureIndex < session_Summary.timeSignatureCount
        Dim As MidiTimeSignaturePoint signaturePoint = _
            session_Summary.timeSignatureMap(signatureIndex)
        Dim As ULongInt segmentEnd = viewEndTick
        If signatureIndex + 1 < session_Summary.timeSignatureCount Then
            Dim As ULongInt nextSignatureTick = _
                session_Summary.timeSignatureMap(signatureIndex + 1).tick
            If nextSignatureTick < segmentEnd Then
                segmentEnd = nextSignatureTick
            End If
        End If

        Dim As ULongInt measureTicks = _
            session_TimeSignatureMeasureTicks(signaturePoint)
        If measureTicks = 0 Then
            Exit While
        End If
        Dim As ULongInt firstMeasure = signaturePoint.tick
        If firstMeasure < segmentStart Then
            Dim As ULongInt elapsedTicks = segmentStart - firstMeasure
            Dim As ULongInt measureNumber = elapsedTicks \ measureTicks
            If elapsedTicks Mod measureTicks <> 0 Then
                measureNumber += 1
            End If
            firstMeasure += measureNumber * measureTicks
        End If

        Dim As ULongInt measureStart = firstMeasure
        While measureStart < segmentEnd
            Dim As ULongInt measureEnd = measureStart + measureTicks
            If measureEnd < measureStart OrElse measureEnd > segmentEnd Then _
                measureEnd = segmentEnd
            If measureEnd <= measureStart Then
                Exit While
            End If

            For trackIndex As Integer = firstTrack To lastTrack
                Dim As Integer staffIndex = trackIndex - firstTrack
                Dim As ULongInt cursorTick = measureStart
                While cursorTick < measureEnd
                    Dim As ULongInt occupiedUntil = cursorTick
                    Dim As ULongInt nextNoteTick = measureEnd
                    Dim As Integer hasOverlap = 0

                    For cacheIndex As Integer = 0 To _
                        session_ScoreVisibleNoteCount - 1
                        Dim As Integer noteIndex = _
                            session_ScoreVisibleNoteIndices(cacheIndex)
                        Dim As MidiEditableNote editableNote
                        If midi_GetEditableNote(noteIndex, editableNote) = 0 Then _
                            Continue For
                        If editableNote.trackIndex <> trackIndex Then
                            Continue For
                        End If
                        Dim As ULongInt noteEnd = editableNote.startTick + _
                            editableNote.durationTicks
                        If noteEnd < editableNote.startTick Then
                            noteEnd = measureEnd
                        End If
                        If editableNote.startTick <= cursorTick AndAlso _
                            noteEnd > cursorTick Then
                            hasOverlap = -1
                            If noteEnd > occupiedUntil Then
                                occupiedUntil = noteEnd
                            End If
                        ElseIf editableNote.startTick > cursorTick AndAlso _
                            editableNote.startTick < nextNoteTick Then
                            nextNoteTick = editableNote.startTick
                        End If
                    Next

                    If hasOverlap <> 0 Then
                        If occupiedUntil > measureEnd Then
                            occupiedUntil = measureEnd
                        End If
                        If occupiedUntil <= cursorTick Then
                            Exit While
                        End If
                        cursorTick = occupiedUntil
                    Else
                        If nextNoteTick > measureEnd Then
                            nextNoteTick = measureEnd
                        End If
                        If nextNoteTick <= cursorTick Then
                            Exit While
                        End If
                        session_DrawRestSpan cursorTick, nextNoteTick, scoreLeft, _
                            scoreRight, firstStaffY, staffIndex, staffGap, _
                            ticksPerView, CULngInt(session_Summary.division), _
                            session_ThemePalette.textColor, drawnRestCount
                        cursorTick = nextNoteTick
                    End If
                    If drawnRestCount >= 1024 Then
                        Exit Sub
                    End If
                Wend
            Next
            If measureTicks > segmentEnd - measureStart Then
                Exit While
            End If
            measureStart += measureTicks
        Wend

        If signatureIndex + 1 >= session_Summary.timeSignatureCount Then
            Exit While
        End If
        Dim As ULongInt nextTick = _
            session_Summary.timeSignatureMap(signatureIndex + 1).tick
        If nextTick > viewEndTick Then
            Exit While
        End If
        If nextTick <= segmentStart Then
            signatureIndex += 1
            Continue While
        End If
        segmentStart = nextTick
        signatureIndex += 1
    Wend
End Sub


Private Sub session_DrawAudioClips( _
    ByVal scoreLeft As Integer, _
    ByVal scoreRight As Integer, _
    ByVal scoreHeight As Integer, _
    ByVal ticksPerView As ULongInt _
)
    If audio_GetCount() <= 0 OrElse ticksPerView = 0 OrElse _
        scoreRight <= scoreLeft Then Exit Sub
    Dim As Integer laneY = SESSION_SCORE_TOP + scoreHeight - 28
    backend_Print scoreLeft, laneY - 13, _
        session_ThemePalette.audioLabelColor, "Audio"
    backend_Line scoreLeft, laneY + 18, scoreRight, laneY + 18, _
        session_ThemePalette.audioGuideColor

    Dim As ULongInt viewEndTick = session_ViewStartTick + ticksPerView
    If viewEndTick < session_ViewStartTick Then _
        viewEndTick = OSE_MAX_MIDI_TICK
    For clipIndex As Integer = 0 To audio_GetCount() - 1
        Dim As OseAudioClip clip
        If audio_GetClip(clipIndex, clip) = 0 Then
            Continue For
        End If
        Dim As Double clipEndSeconds = midi_TicksToSeconds( _
            session_Summary, clip.startTick) + _
            CDbl(clip.durationMilliseconds) / 1000.0
        Dim As ULongInt clipEndTick = midi_SecondsToTicks( _
            session_Summary, clipEndSeconds)
        If clipEndTick <= clip.startTick Then
            clipEndTick = clip.startTick + 1
        End If
        If clip.startTick > viewEndTick OrElse clipEndTick < session_ViewStartTick Then _
            Continue For

        Dim As ULongInt visibleStart = clip.startTick
        Dim As ULongInt visibleEnd = clipEndTick
        If visibleStart < session_ViewStartTick Then
            visibleStart = session_ViewStartTick
        End If
        If visibleEnd > viewEndTick Then
            visibleEnd = viewEndTick
        End If
        If visibleEnd <= visibleStart Then
            Continue For
        End If
        Dim As Integer clipX = scoreLeft + CInt((CDbl(scoreRight - scoreLeft) * _
            CDbl(visibleStart - session_ViewStartTick)) / CDbl(ticksPerView))
        Dim As Integer clipWidth = CInt((CDbl(scoreRight - scoreLeft) * _
            CDbl(visibleEnd - visibleStart)) / CDbl(ticksPerView))
        If clipWidth < 4 Then
            clipWidth = 4
        End If
        backend_Rect clipX, laneY, clipWidth, 16, _
            session_ThemePalette.audioClipColor, 1
        backend_Print clipX + 3, laneY + 3, _
            session_ThemePalette.audioClipTextColor, Str(clipIndex + 1)
    Next
End Sub


Private Sub session_DrawClefOctagon( _
    ByVal octagonLeft As Integer, ByVal octagonTop As Integer, _
    ByVal octagonWidth As Integer, ByVal octagonHeight As Integer, _
    ByVal polygonColor As ULong _
)
    /'
        A regular octagon remains circular at the sizes used for a bass-clef
        head and dots, while keeping every part of the clef in omaGUI's filled
        polygon path.
    '/
    Dim As Integer designX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer designY(1 To GRAPHICSHAPE_MAX_POINTS)

    designX(1) = 29
    designY(1) = 0
    designX(2) = 71
    designY(2) = 0
    designX(3) = 100
    designY(3) = 29
    designX(4) = 100
    designY(4) = 71
    designX(5) = 71
    designY(5) = 100
    designX(6) = 29
    designY(6) = 100
    designX(7) = 0
    designY(7) = 71
    designX(8) = 0
    designY(8) = 29

    session_DrawScaledNotationPolygon octagonLeft, octagonTop, _
        octagonWidth, octagonHeight, _
        100, 100, 8, designX(), designY(), polygonColor
End Sub


Private Sub session_DrawTrebleClef( _
    ByVal clefX As Integer, ByVal staffY As Integer, ByVal clefColor As ULong _
)
    /'
        The treble clef is a set of overlapping closed ribbons. Its 190 by 430
        design grid is roughly ten times the final raster size, so the upper
        loop, G-line spiral, descending spine, and lower hook can be tuned as
        coherent silhouettes instead of disconnected screen-sized strokes.
    '/
    Const DESIGN_WIDTH As Integer = 190
    Const DESIGN_HEIGHT As Integer = 430
    Const TARGET_WIDTH As Integer = 20
    Const TARGET_HEIGHT As Integer = 44

    Dim As Integer originX = clefX - 10
    Dim As Integer originY = staffY - 11
    Dim As Integer designX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer designY(1 To GRAPHICSHAPE_MAX_POINTS)

    ' Left half of the narrow upper loop.
    designX(1) = 100
    designY(1) = 0
    designX(2) = 70
    designY(2) = 10
    designX(3) = 50
    designY(3) = 40
    designX(4) = 40
    designY(4) = 80
    designX(5) = 50
    designY(5) = 120
    designX(6) = 80
    designY(6) = 150
    designX(7) = 100
    designY(7) = 130
    designX(8) = 80
    designY(8) = 110
    designX(9) = 70
    designY(9) = 80
    designX(10) = 70
    designY(10) = 50
    designX(11) = 90
    designY(11) = 20
    designX(12) = 110
    designY(12) = 10
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 12, designX(), designY(), clefColor

    ' Right half closes the loop while preserving its white center.
    designX(1) = 100
    designY(1) = 0
    designX(2) = 120
    designY(2) = 10
    designX(3) = 130
    designY(3) = 30
    designX(4) = 130
    designY(4) = 60
    designX(5) = 120
    designY(5) = 90
    designX(6) = 100
    designY(6) = 120
    designX(7) = 80
    designY(7) = 150
    designX(8) = 70
    designY(8) = 130
    designX(9) = 90
    designY(9) = 100
    designX(10) = 100
    designY(10) = 70
    designX(11) = 110
    designY(11) = 40
    designX(12) = 110
    designY(12) = 20
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 12, designX(), designY(), clefColor

    ' Upper and right side of the spiral around the G line.
    designX(1) = 0
    designY(1) = 220
    designX(2) = 10
    designY(2) = 190
    designX(3) = 30
    designY(3) = 170
    designX(4) = 60
    designY(4) = 150
    designX(5) = 100
    designY(5) = 150
    designX(6) = 140
    designY(6) = 170
    designX(7) = 170
    designY(7) = 200
    designX(8) = 180
    designY(8) = 230
    designX(9) = 150
    designY(9) = 230
    designX(10) = 140
    designY(10) = 210
    designX(11) = 110
    designY(11) = 190
    designX(12) = 70
    designY(12) = 180
    designX(13) = 40
    designY(13) = 190
    designX(14) = 30
    designY(14) = 220
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 14, designX(), designY(), clefColor

    ' Lower left and lower right ribbons complete the open spiral.
    designX(1) = 0
    designY(1) = 210
    designX(2) = 0
    designY(2) = 250
    designX(3) = 20
    designY(3) = 280
    designX(4) = 60
    designY(4) = 300
    designX(5) = 90
    designY(5) = 300
    designX(6) = 90
    designY(6) = 270
    designX(7) = 60
    designY(7) = 270
    designX(8) = 30
    designY(8) = 260
    designX(9) = 20
    designY(9) = 240
    designX(10) = 30
    designY(10) = 220
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 10, designX(), designY(), clefColor

    designX(1) = 50
    designY(1) = 300
    designX(2) = 100
    designY(2) = 310
    designX(3) = 140
    designY(3) = 290
    designX(4) = 170
    designY(4) = 260
    designX(5) = 180
    designY(5) = 220
    designX(6) = 150
    designY(6) = 210
    designX(7) = 150
    designY(7) = 240
    designX(8) = 130
    designY(8) = 270
    designX(9) = 100
    designY(9) = 280
    designX(10) = 60
    designY(10) = 270
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 10, designX(), designY(), clefColor

    ' The diagonal spine crosses the spiral and descends into the tail.
    designX(1) = 100
    designY(1) = 70
    designX(2) = 120
    designY(2) = 80
    designX(3) = 110
    designY(3) = 120
    designX(4) = 90
    designY(4) = 160
    designX(5) = 80
    designY(5) = 200
    designX(6) = 80
    designY(6) = 240
    designX(7) = 100
    designY(7) = 290
    designX(8) = 120
    designY(8) = 340
    designX(9) = 110
    designY(9) = 400
    designX(10) = 90
    designY(10) = 400
    designX(11) = 100
    designY(11) = 350
    designX(12) = 80
    designY(12) = 300
    designX(13) = 60
    designY(13) = 250
    designX(14) = 60
    designY(14) = 210
    designX(15) = 70
    designY(15) = 160
    designX(16) = 90
    designY(16) = 110
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 16, designX(), designY(), clefColor

    ' Bottom hook, kept broad enough to survive the final 20-pixel reduction.
    designX(1) = 105
    designY(1) = 350
    designX(2) = 125
    designY(2) = 365
    designX(3) = 135
    designY(3) = 390
    designX(4) = 120
    designY(4) = 410
    designX(5) = 90
    designY(5) = 430
    designX(6) = 55
    designY(6) = 420
    designX(7) = 30
    designY(7) = 400
    designX(8) = 25
    designY(8) = 380
    designX(9) = 45
    designY(9) = 375
    designX(10) = 45
    designY(10) = 393
    designX(11) = 60
    designY(11) = 405
    designX(12) = 82
    designY(12) = 410
    designX(13) = 103
    designY(13) = 398
    designX(14) = 110
    designY(14) = 385
    designX(15) = 103
    designY(15) = 370
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 15, designX(), designY(), clefColor
End Sub


Private Sub session_DrawBassClef( _
    ByVal clefX As Integer, ByVal staffY As Integer, ByVal clefColor As ULong _
)
    /'
        The bass clef uses a tapered comma silhouette and three octagons. The
        same normalized polygon path is used for its head and dots, avoiding a
        visual mismatch between a vector body and unrelated circle primitives.
    '/
    Const DESIGN_WIDTH As Integer = 190
    Const DESIGN_HEIGHT As Integer = 290
    Const TARGET_WIDTH As Integer = 20
    Const TARGET_HEIGHT As Integer = 30

    Dim As Integer originX = clefX - 10
    Dim As Integer originY = staffY
    Dim As Integer designX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer designY(1 To GRAPHICSHAPE_MAX_POINTS)

    designX(1) = 20
    designY(1) = 60
    designX(2) = 35
    designY(2) = 20
    designX(3) = 65
    designY(3) = 0
    designX(4) = 95
    designY(4) = 10
    designX(5) = 120
    designY(5) = 40
    designX(6) = 140
    designY(6) = 90
    designX(7) = 125
    designY(7) = 150
    designX(8) = 90
    designY(8) = 210
    designX(9) = 20
    designY(9) = 280
    designX(10) = 55
    designY(10) = 240
    designX(11) = 80
    designY(11) = 200
    designX(12) = 100
    designY(12) = 160
    designX(13) = 105
    designY(13) = 110
    designX(14) = 100
    designY(14) = 70
    designX(15) = 75
    designY(15) = 50
    designX(16) = 45
    designY(16) = 70
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 16, designX(), designY(), clefColor

    session_DrawClefOctagon originX, originY + 2, 8, 9, clefColor
    ' The dots occupy the spaces immediately above and below the F line.
    session_DrawClefOctagon originX + 16, originY + 2, 4, 4, clefColor
    session_DrawClefOctagon originX + 16, originY + 9, 4, 4, clefColor
End Sub


Private Sub session_DrawScoreClef( _
    ByVal trackIndex As Integer, ByVal staffY As Integer, _
    ByVal clefColor As ULong _
)
    Dim As Integer clefCenterX = SESSION_SCORE_LEFT + 17

    If session_TrackUsesBassClef(trackIndex) <> 0 Then
        session_DrawBassClef clefCenterX, staffY, clefColor
    Else
        session_DrawTrebleClef clefCenterX, staffY, clefColor
    End If
End Sub


Private Function session_VisualFingerprintMix( _
    ByVal fingerprint As ULongInt, _
    ByVal value As ULongInt _
) As ULongInt
    Return ((fingerprint Shl 7) Or (fingerprint Shr 57)) Xor value Xor _
        &h9e3779b97f4a7c15ull
End Function


Private Function session_VisualFingerprintText( _
    ByVal fingerprint As ULongInt, _
    ByRef textValue As String _
) As ULongInt
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(Len(textValue)))
    For characterIndex As Integer = 0 To Len(textValue) - 1
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, CULngInt(textValue[characterIndex]))
    Next characterIndex
    Return fingerprint
End Function


Private Function session_ScoreStaticFingerprintValue( _
    ByVal firstTrack As Integer, _
    ByVal staffCount As Integer, _
    ByVal keySharpsFlats As Integer, _
    ByVal keyMinor As Integer _
) As UInteger
    Dim As UInteger fingerprint = &h811c9dc5u

    fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
        CUInt(firstTrack + 1)
    fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
        CUInt(staffCount + 1)
    fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
        CUInt(session_ScoreTrackRowHeight)
    fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
        CUInt(session_SelectedTrack + 2)
    fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
        CUInt(keySharpsFlats + 8)
    fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
        CUInt(keyMinor And &H1)

    ' Meter changes and scrolling across a signature boundary must invalidate
    ' the cached staff gutter as well as the timeline and small header label.
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick(session_ViewStartTick)
    If signatureIndex >= 0 Then
        fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
            CUInt(session_Summary.timeSignatureMap(signatureIndex).numerator)
        fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
            CUInt(session_Summary.timeSignatureMap(signatureIndex).denominatorPower)
    End If

    For trackIndex As Integer = firstTrack To firstTrack + staffCount - 1
        Dim As String trackName = midi_TrackDisplayName( _
            session_Summary, trackIndex)
        fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
            CUInt(trackIndex + 1)
        fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
            CUInt(session_TrackUsesBassClef(trackIndex) And &H1)
        For characterIndex As Integer = 0 To Len(trackName) - 1
            fingerprint = ((fingerprint Shl 5) Or _
                (fingerprint Shr 27)) Xor CUInt(trackName[characterIndex])
        Next characterIndex
    Next trackIndex

    Return fingerprint
End Function


Private Function session_ScoreVisualFingerprint( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal ticksPerView As ULongInt, _
    ByVal staticFingerprint As UInteger _
) As ULongInt
    Dim As ULongInt fingerprint = &hcbf29ce484222325ull

    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(screenWidth))
    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(screenHeight))
    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(session_ThemeMode))
    fingerprint = session_VisualFingerprintMix(fingerprint, session_ViewStartTick)
    fingerprint = session_VisualFingerprintMix(fingerprint, ticksPerView)
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(staticFingerprint))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Dirty And &H1))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_ScoreVisibleNoteOverflowed And &H1))
    fingerprint = session_VisualFingerprintText( _
        fingerprint, session_Summary.documentTitle)
    fingerprint = session_VisualFingerprintText( _
        fingerprint, session_ProjectFilename)
    fingerprint = session_VisualFingerprintText( _
        fingerprint, session_Filename)

    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_ScoreVisibleNoteCount))
    For cacheIndex As Integer = 0 To session_ScoreVisibleNoteCount - 1
        Dim As Integer noteIndex = session_ScoreVisibleNoteIndices(cacheIndex)
        Dim As MidiEditableNote editableNote
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, CULngInt(noteIndex + 1))
        If midi_GetEditableNote(noteIndex, editableNote) <> 0 Then
            fingerprint = session_VisualFingerprintMix( _
                fingerprint, editableNote.startTick)
            fingerprint = session_VisualFingerprintMix( _
                fingerprint, editableNote.durationTicks)
            fingerprint = session_VisualFingerprintMix(fingerprint, _
                CULngInt(editableNote.keyNumber) Or _
                (CULngInt(editableNote.channel) Shl 8) Or _
                (CULngInt(editableNote.velocity) Shl 16) Or _
                (CULngInt(editableNote.trackIndex + 1) Shl 24))
        End If
    Next cacheIndex

    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_NoteSelection.count))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_NoteSelection.primaryNoteIndex + 1))
    For selectionIndex As Integer = 0 To session_NoteSelection.count - 1
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(session_NoteSelection.noteIndices(selectionIndex) + 1))
    Next selectionIndex

    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_ScoreMarqueeActive And &H1))
    If session_ScoreMarqueeActive <> 0 Then
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CUInt(session_ScoreMarqueeStartX)))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CUInt(session_ScoreMarqueeStartY)))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CUInt(session_ScoreMarqueeCurrentX)))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CUInt(session_ScoreMarqueeCurrentY)))
    End If

    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Summary.timeSignatureCount))
    For signatureIndex As Integer = 0 To _
        session_Summary.timeSignatureCount - 1
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, session_Summary.timeSignatureMap(signatureIndex).tick)
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(session_Summary.timeSignatureMap(signatureIndex).numerator) Or _
            (CULngInt(session_Summary.timeSignatureMap( _
            signatureIndex).denominatorPower) Shl 8))
    Next signatureIndex
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Summary.keySignatureCount))
    For keyIndex As Integer = 0 To session_Summary.keySignatureCount - 1
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, session_Summary.keySignatureMap(keyIndex).tick)
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CUInt(session_Summary.keySignatureMap( _
            keyIndex).sharpsFlats)) Or _
            (CULngInt(session_Summary.keySignatureMap(keyIndex).minor) Shl 32))
    Next keyIndex

    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(audio_GetCount()))
    For clipIndex As Integer = 0 To audio_GetCount() - 1
        Dim As OseAudioClip clip
        If audio_GetClip(clipIndex, clip) <> 0 Then
            fingerprint = session_VisualFingerprintMix(fingerprint, clip.startTick)
            fingerprint = session_VisualFingerprintMix( _
                fingerprint, clip.durationMilliseconds)
            fingerprint = session_VisualFingerprintMix( _
                fingerprint, CULngInt(clip.gainPermille))
        End If
    Next clipIndex

    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Playing And &H1))
    If session_Playing <> 0 Then
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            midi_SecondsToTicks(session_Summary, session_PlaybackElapsed))
    End If
    Return fingerprint
End Function


' Score drawing branches by notation feature but owns no input or mutation.
' fblint: disable-next-line FBL111 REASON: Score rendering branches by notation feature without mutating document state.
Private Sub session_DrawScore(ByVal screenWidth As Integer, ByVal screenHeight As Integer)
    Dim As Integer scoreWidth = screenWidth - SESSION_SCORE_LEFT - 4
    Dim As Integer scoreHeight = screenHeight - SESSION_TOP_HEIGHT - SESSION_MIXER_HEIGHT - 8
    If scoreWidth < 160 Then
        scoreWidth = 160
    End If
    If scoreHeight < 150 Then
        scoreHeight = 150
    End If

    Dim As Double scoreSectionClock
    If session_SmoothnessProfilingActive <> 0 Then
        scoreSectionClock = Timer
    End If
    session_PrepareScoreNoteCache(screenHeight)
    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessScoreCacheMs = uiFramePacing_ElapsedMilliseconds( _
            scoreSectionClock, Timer)
        scoreSectionClock = Timer
    End If

    Dim As Integer firstStaffY = SESSION_SCORE_TOP + _
        scoreLayout_FirstStaffOffset(session_ScoreTrackRowHeight)
    Dim As Integer staffGap = session_ScoreTrackRowHeight
    Dim As Integer lineSpacing = scoreLayout_LineSpacing( _
        session_ScoreTrackRowHeight)
    Dim As Integer rowTopOffset = scoreLayout_RowTopOffset( _
        session_ScoreTrackRowHeight)
    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer staffCount = session_ScoreVisibleTrackCount(screenHeight)

    Dim As Integer scoreLeft = SESSION_SCORE_LEFT + 28
    Dim As Integer scoreRight = SESSION_SCORE_LEFT + scoreWidth - 14
    Dim As Integer noteScoreLeft = SESSION_SCORE_LEFT + SESSION_SCORE_NOTE_LEFT
    Dim As Integer noteScoreRight = SESSION_SCORE_LEFT + scoreWidth - _
        SESSION_SCORE_NOTE_RIGHT
    If noteScoreRight <= noteScoreLeft Then
        Exit Sub
    End If
    If session_Summary.division <= 0 Then
        Exit Sub
    End If

    Dim As Integer activeSignatureIndex = _
        session_TimeSignatureIndexForTick(session_ViewStartTick)
    If activeSignatureIndex < 0 Then
        activeSignatureIndex = 0
    End If
    Dim As MidiTimeSignaturePoint activeSignature
    activeSignature.numerator = 4
    activeSignature.denominatorPower = 2
    If activeSignatureIndex < session_Summary.timeSignatureCount Then
        activeSignature = session_Summary.timeSignatureMap(activeSignatureIndex)
    End If
    Dim As MidiKeySignaturePoint activeKeySignature
    activeKeySignature.sharpsFlats = 0
    activeKeySignature.minor = 0
    Dim As Integer activeKeyIndex = session_KeySignatureIndexForTick( _
        session_ViewStartTick)
    If activeKeyIndex >= 0 AndAlso _
        activeKeyIndex < session_Summary.keySignatureCount Then
        activeKeySignature = session_Summary.keySignatureMap(activeKeyIndex)
    End If
    Dim As ULongInt ticksPerView = session_ViewTicks()

    Dim As Integer workPage = backend_GetWorkPage()
    If workPage < 0 OrElse workPage > 1 Then
        workPage = 0
    End If
    Dim As UInteger staticFingerprint = _
        session_ScoreStaticFingerprintValue(firstTrack, staffCount, _
        activeKeySignature.sharpsFlats, activeKeySignature.minor)
    Dim As ULongInt visualFingerprint = session_ScoreVisualFingerprint( _
        screenWidth, screenHeight, ticksPerView, staticFingerprint)
    If session_ScorePageValid(workPage) <> 0 AndAlso _
        session_ScorePageFingerprint(workPage) = visualFingerprint Then
        session_SmoothnessScoreBaseMs = 0.0
        session_SmoothnessScoreRestsMs = 0.0
        session_SmoothnessScoreNotesMs = 0.0
        Exit Sub
    End If
    Dim As Integer redrawScoreStatic = _
        session_ScoreStaticPageWidth(workPage) <> screenWidth OrElse _
        session_ScoreStaticPageHeight(workPage) <> screenHeight OrElse _
        session_ScoreStaticPageTheme(workPage) <> session_ThemeMode OrElse _
        session_ScoreStaticPageFingerprint(workPage) <> staticFingerprint
    Dim As Integer dynamicScoreLeft = noteScoreLeft - 16
    If dynamicScoreLeft < SESSION_SCORE_LEFT + 1 Then _
        dynamicScoreLeft = SESSION_SCORE_LEFT + 1

    If redrawScoreStatic <> 0 Then
        backend_Rect SESSION_SCORE_LEFT, SESSION_SCORE_TOP, scoreWidth, _
            scoreHeight, session_ThemePalette.scorePaperColor, 1
        backend_Rect SESSION_SCORE_LEFT, SESSION_SCORE_TOP, scoreWidth, _
            scoreHeight, session_ThemePalette.borderColor, 0
        session_ScoreHeaderPageValid(workPage) = 0
    Else
        ' Clear only the changing timeline. The page-local labels and clefs to
        ' its left remain valid and avoid rebuilding identical glyphs.
        backend_Rect dynamicScoreLeft, SESSION_SCORE_TOP + 24, _
            SESSION_SCORE_LEFT + scoreWidth - 1 - dynamicScoreLeft, _
            scoreHeight - 25, session_ThemePalette.scorePaperColor, 1
    End If

    Dim As ULongInt headerFingerprint = &h27d4eb2full
    headerFingerprint = session_VisualFingerprintMix( _
        headerFingerprint, CULngInt(screenWidth))
    headerFingerprint = session_VisualFingerprintMix( _
        headerFingerprint, CULngInt(session_ThemeMode))
    headerFingerprint = session_VisualFingerprintMix(headerFingerprint, _
        CULngInt(activeSignature.numerator) Or _
        (CULngInt(activeSignature.denominatorPower) Shl 8))
    headerFingerprint = session_VisualFingerprintMix(headerFingerprint, _
        CULngInt(CUInt(activeKeySignature.sharpsFlats)) Or _
        (CULngInt(activeKeySignature.minor) Shl 32))
    headerFingerprint = session_VisualFingerprintMix( _
        headerFingerprint, CULngInt(session_Dirty And &H1))
    headerFingerprint = session_VisualFingerprintMix(headerFingerprint, _
        CULngInt(session_ScoreVisibleNoteOverflowed And &H1))
    headerFingerprint = session_VisualFingerprintText( _
        headerFingerprint, session_Summary.documentTitle)
    headerFingerprint = session_VisualFingerprintText( _
        headerFingerprint, session_ProjectFilename)
    headerFingerprint = session_VisualFingerprintText( _
        headerFingerprint, session_Filename)
    If session_ScoreHeaderPageValid(workPage) = 0 OrElse _
        session_ScoreHeaderPageFingerprint(workPage) <> headerFingerprint Then
        ' The title can change after a save or edit without invalidating the body.
        backend_Rect SESSION_SCORE_LEFT + 1, SESSION_SCORE_TOP + 1, _
            scoreWidth - 2, 22, session_ThemePalette.headerColor, 1
        backend_Line SESSION_SCORE_LEFT + 1, SESSION_SCORE_TOP + 23, _
            SESSION_SCORE_LEFT + scoreWidth - 2, SESSION_SCORE_TOP + 23, _
            session_ThemePalette.dividerColor
        Dim As String scoreTitle = session_Summary.documentTitle
        If scoreTitle = "" Then _
            scoreTitle = session_LeafFilename(session_ProjectFilename)
        If scoreTitle = "" Then
            scoreTitle = session_LeafFilename(session_Filename)
        End If
        If scoreTitle = "" Then
            scoreTitle = "Untitled"
        End If
        If session_Dirty <> 0 Then
            scoreTitle += " *"
        End If
        If session_ScoreVisibleNoteOverflowed <> 0 Then _
            scoreTitle += " [dense view clipped]"
        Dim As Integer scoreTitleCharacters = (scoreWidth - 280) \ 8
        If scoreTitleCharacters < 12 Then
            scoreTitleCharacters = 12
        End If
        scoreTitle = session_ClipText(scoreTitle, scoreTitleCharacters)
        backend_PrintAligned SESSION_SCORE_LEFT + 4, SESSION_SCORE_TOP + 5, _
            scoreWidth - 8, 14, session_ThemePalette.textColor, _
            "Score View - " + scoreTitle, _
            BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP

        backend_Print SESSION_SCORE_LEFT + 8, SESSION_SCORE_TOP + 6, _
            session_ThemePalette.mutedTextColor, "Grid " + session_SnapName()

        backend_Print SESSION_SCORE_LEFT + scoreWidth - 70, _
            SESSION_SCORE_TOP + 6, session_ThemePalette.textColor, _
            Str(activeSignature.numerator) + "/" + _
            Str(session_TempoDenominatorValue(activeSignature.denominatorPower))
        backend_Print SESSION_SCORE_LEFT + scoreWidth - 150, _
            SESSION_SCORE_TOP + 6, session_ThemePalette.textColor, _
            "Key " + session_KeySignatureText(activeKeySignature.sharpsFlats, _
            activeKeySignature.minor)
        session_ScoreHeaderPageFingerprint(workPage) = headerFingerprint
        session_ScoreHeaderPageValid(workPage) = -1
    End If

    ' Alternating rows keep dense arrangements readable. The selected row uses
    ' the same accent family as its mixer strip so the two views stay related.
    Dim As Integer rowLeft = IIf( _
        redrawScoreStatic <> 0, SESSION_SCORE_LEFT + 1, dynamicScoreLeft)
    Dim As Integer rowWidth = SESSION_SCORE_LEFT + scoreWidth - 1 - rowLeft
    For rowTrackIndex As Integer = firstTrack To firstTrack + staffCount - 1
        Dim As Integer rowIndex = rowTrackIndex - firstTrack
        Dim As Integer rowY = firstStaffY + rowIndex * staffGap
        Dim As ULong rowColor = session_ThemePalette.scorePaperColor
        If (rowIndex And 1) <> 0 Then _
            rowColor = session_ThemePalette.scoreAlternateColor
        If rowTrackIndex = session_SelectedTrack Then _
            rowColor = session_ThemePalette.scoreSelectedColor
        backend_Rect rowLeft, rowY - rowTopOffset, rowWidth, _
            staffGap - 2, rowColor, 1
        If redrawScoreStatic <> 0 AndAlso _
            rowTrackIndex = session_SelectedTrack Then
            backend_Rect SESSION_SCORE_LEFT + 1, rowY - rowTopOffset, 3, _
                staffGap - 2, session_ThemePalette.accentColor, 1
        End If
    Next

    ' Each time-signature segment owns its own beat and measure alignment.
    session_DrawScoreMeterGuides noteScoreLeft, noteScoreRight, firstStaffY, _
        staffGap, staffCount, ticksPerView

    Dim As Integer staffLineLeft = IIf( _
        redrawScoreStatic <> 0, scoreLeft, dynamicScoreLeft)
    For trackIndex As Integer = firstTrack To firstTrack + staffCount - 1
        Dim As Integer staffIndex = trackIndex - firstTrack
        Dim As Integer staffY = firstStaffY + staffIndex * staffGap
        For lineIndex As Integer = 0 To 4
            backend_Line staffLineLeft, staffY + lineIndex * lineSpacing, _
                scoreRight, staffY + lineIndex * lineSpacing, _
                session_ThemePalette.dividerColor
        Next
        If redrawScoreStatic <> 0 Then
            Dim As String trackLabel = Str(trackIndex + 1) + " " + _
                midi_TrackDisplayName(session_Summary, trackIndex)
            If Len(trackLabel) > SESSION_SCORE_TRACK_LABEL_CHARACTERS Then _
                trackLabel = Left(trackLabel, SESSION_SCORE_TRACK_LABEL_CHARACTERS)
            Dim As ULong trackLabelColor = session_ThemePalette.textColor
            If trackIndex = session_SelectedTrack Then _
                trackLabelColor = session_ThemePalette.accentBrightColor
            backend_Print SESSION_SCORE_LEFT + 5, _
                staffY - rowTopOffset + 3, _
                trackLabelColor, trackLabel
            session_DrawScoreClef trackIndex, staffY, _
                session_ThemePalette.textColor
            session_DrawStaffTimeSignature staffY, activeSignature.numerator, _
                session_TempoDenominatorValue(activeSignature.denominatorPower)
        End If
    Next

    ' The clef and key signature occupy a fixed gutter before the editable timeline.
    If redrawScoreStatic <> 0 Then
        session_DrawKeySignature scoreLeft, firstStaffY, staffGap, staffCount, _
            firstTrack, activeKeySignature.sharpsFlats
        session_ScoreStaticPageWidth(workPage) = screenWidth
        session_ScoreStaticPageHeight(workPage) = screenHeight
        session_ScoreStaticPageTheme(workPage) = session_ThemeMode
        session_ScoreStaticPageFingerprint(workPage) = staticFingerprint
    End If

    ' Draw absolute grid positions so changing snap or scrolling between beats
    ' cannot stretch ruler marks away from the notes they describe. Thin dense
    ' grids before drawing, while retaining their actual time coordinates.
    Dim As ULongInt rulerStepTicks = session_ScoreSnapTicks()
    While ticksPerView \ rulerStepTicks > 256
        rulerStepTicks *= 2
    Wend
    Dim As ULongInt firstRulerTick = _
        ((session_ViewStartTick + rulerStepTicks - 1) \ rulerStepTicks) * rulerStepTicks
    Dim As Integer rulerDivisionCount = CInt(ticksPerView \ rulerStepTicks)
    For rulerDivision As Integer = 0 To rulerDivisionCount
        Dim As ULongInt rulerTick = firstRulerTick + _
            CULngInt(rulerDivision) * rulerStepTicks
        If rulerTick > session_ViewStartTick + ticksPerView Then
            Exit For
        End If
        Dim As Integer rulerX = noteScoreLeft + _
            CInt(CDbl(noteScoreRight - noteScoreLeft) * _
            CDbl(rulerTick - session_ViewStartTick) / CDbl(ticksPerView))
        Dim As Integer rulerTickHeight = 4
        If session_Summary.division > 0 AndAlso _
            rulerTick Mod CULngInt(session_Summary.division) = 0 Then _
            rulerTickHeight = 7
        If session_ScoreIsMeasureStart(rulerTick) <> 0 Then _
            rulerTickHeight = 10
        backend_Line rulerX, SESSION_SCORE_TOP + 24, rulerX, _
            SESSION_SCORE_TOP + 24 + rulerTickHeight, _
            session_ThemePalette.dividerColor
        If rulerDivision < rulerDivisionCount Then
            If session_ScoreIsMeasureStart(rulerTick) <> 0 Then
                Dim As ULongInt measureNumber = _
                    session_ScoreMeasureNumber(rulerTick)
                backend_Print rulerX + 3, SESSION_SCORE_TOP + 34, _
                    session_ThemePalette.textColor, Str(measureNumber)
            End If
        End If
    Next

    If session_Playing <> 0 Then
        Dim As ULongInt playheadTick = midi_SecondsToTicks( _
            session_Summary, session_PlaybackElapsed)
        If playheadTick >= session_ViewStartTick AndAlso _
            playheadTick <= session_ViewStartTick + ticksPerView Then
            Dim As ULongInt viewTick = playheadTick - session_ViewStartTick
            Dim As Integer playheadX = noteScoreLeft + _
                CInt((CDbl(noteScoreRight - noteScoreLeft) * CDbl(viewTick)) / _
                CDbl(ticksPerView))
            backend_Line playheadX, SESSION_SCORE_TOP + 25, playheadX, _
                SESSION_SCORE_TOP + scoreHeight - 8, _
                session_ThemePalette.scorePlayheadColor
        End If
    End If

    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessScoreBaseMs = uiFramePacing_ElapsedMilliseconds( _
            scoreSectionClock, Timer)
        scoreSectionClock = Timer
    End If
    session_DrawScoreRests noteScoreLeft, noteScoreRight, screenHeight, _
        firstStaffY, staffGap, ticksPerView
    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessScoreRestsMs = uiFramePacing_ElapsedMilliseconds( _
            scoreSectionClock, Timer)
        scoreSectionClock = Timer
    End If
    session_DrawScoreNotes screenWidth, screenHeight, _
        CULngInt(session_Summary.division), activeKeySignature.sharpsFlats
    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessScoreNotesMs = uiFramePacing_ElapsedMilliseconds( _
            scoreSectionClock, Timer)
    End If
    session_DrawAudioClips noteScoreLeft, noteScoreRight, scoreHeight, ticksPerView
    session_DrawScoreMarquee()
    session_ScorePageFingerprint(workPage) = visualFingerprint
    session_ScorePageValid(workPage) = -1
End Sub


Private Sub session_DrawMixerMeter( _
    ByVal meterLeft As Integer, _
    ByVal meterTop As Integer, _
    ByVal meterWidth As Integer, _
    ByVal meterHeight As Integer, _
    ByVal level As Single _
)
    If level < 0.0 Then
        level = 0.0
    End If
    If level > 1.0 Then
        level = 1.0
    End If

    Const segmentCount As Integer = 12
    Dim As Integer segmentHeight = (meterHeight - segmentCount + 1) \ segmentCount
    If segmentHeight < 2 Then
        segmentHeight = 2
    End If
    Dim As Integer activeSegments = CInt(level * segmentCount)
    backend_Rect meterLeft, meterTop, meterWidth, meterHeight, _
        session_ThemePalette.meterWellColor, 1

    For segmentIndex As Integer = 0 To segmentCount - 1
        Dim As Integer segmentY = meterTop + meterHeight - 2 - _
            (segmentIndex + 1) * segmentHeight - segmentIndex
        Dim As ULong segmentColor = session_ThemePalette.meterIdleGreenColor
        If segmentIndex >= 9 Then
            segmentColor = session_ThemePalette.meterIdleRedColor
        ElseIf segmentIndex >= 7 Then
            segmentColor = session_ThemePalette.meterIdleYellowColor
        End If
        If segmentIndex < activeSegments Then
            If segmentIndex >= 9 Then
                segmentColor = session_ThemePalette.meterActiveRedColor
            ElseIf segmentIndex >= 7 Then
                segmentColor = session_ThemePalette.meterActiveYellowColor
            Else
                segmentColor = session_ThemePalette.meterActiveGreenColor
            End If
        End If
        backend_Rect meterLeft + 1, segmentY, meterWidth - 2, _
            segmentHeight, segmentColor, 1
    Next
End Sub


Private Sub session_DrawMixerKnob( _
    ByVal centerX As Integer, _
    ByVal centerY As Integer, _
    ByVal normalizedValue As Single _
)
    If normalizedValue < 0.0 Then
        normalizedValue = 0.0
    End If
    If normalizedValue > 1.0 Then
        normalizedValue = 1.0
    End If
    backend_Circle centerX + 1, centerY + 1, 7, _
        session_ThemePalette.knobOuterColor, 1
    backend_Circle centerX, centerY, 7, _
        session_ThemePalette.knobFaceColor, 1
    backend_Circle centerX, centerY, 7, _
        session_ThemePalette.knobBorderColor, 0
    backend_Circle centerX, centerY, 4, _
        session_ThemePalette.knobInsetColor, 1

    ' The pointer sweeps through 270 degrees, matching small hardware knobs.
    Dim As Double pointerAngle = -2.35 + CDbl(normalizedValue) * 4.70
    Dim As Integer pointerX = centerX + CInt(Sin(pointerAngle) * 5.0)
    Dim As Integer pointerY = centerY - CInt(Cos(pointerAngle) * 5.0)
    backend_Line centerX, centerY, pointerX, pointerY, _
        session_ThemePalette.accentBrightColor
    backend_Circle pointerX, pointerY, 1, _
        session_ThemePalette.highlightColor, 1
End Sub


Private Sub session_DrawMixerPageButton( _
    ByVal buttonLeft As Integer, _
    ByVal buttonTop As Integer, _
    ByVal buttonWidth As Integer, _
    ByVal buttonHeight As Integer, _
    ByVal direction As Integer, _
    ByVal enabledState As Integer _
)
    Dim As ULong faceColor = session_ThemePalette.panelColor
    Dim As ULong borderColor = session_ThemePalette.borderColor
    Dim As ULong iconColor = session_ThemePalette.accentBrightColor
    If enabledState = 0 Then
        faceColor = session_ThemePalette.alternatePanelColor
        borderColor = session_ThemePalette.shadowColor
        iconColor = session_ThemePalette.faintTextColor
    End If

    backend_Rect buttonLeft, buttonTop, buttonWidth, buttonHeight, faceColor, 1
    backend_Rect buttonLeft, buttonTop, buttonWidth, buttonHeight, borderColor, 0
    Dim As Integer centerX = buttonLeft + buttonWidth \ 2
    Dim As Integer centerY = buttonTop + buttonHeight \ 2
    backend_Line centerX - direction * 3, centerY - 4, _
        centerX + direction * 2, centerY, iconColor
    backend_Line centerX + direction * 2, centerY, _
        centerX - direction * 3, centerY + 4, iconColor
End Sub


Private Function session_MixerVisualFingerprint( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal includeMeterLevels As Integer _
) As ULongInt
    Dim As ULongInt fingerprint = &h84222325cbf29ce4ull

    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(screenWidth))
    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(screenHeight))
    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(session_ThemeMode))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_SelectedTrack + 1))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_MixerPageAnchor + 1))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Summary.trackCount))
    fingerprint = session_VisualFingerprintText(fingerprint, session_Filename)

    For channelIndex As Integer = 0 To SESSION_CHANNEL_COUNT - 1
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CInt(session_ChannelVolume(channelIndex) * 100000.0)))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CUInt(CInt((session_ChannelPan(channelIndex) + 1.0) * _
            100000.0))))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CInt(session_ChannelChorus(channelIndex) * 100000.0)))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CInt(session_ChannelReverb(channelIndex) * 100000.0)))
        If includeMeterLevels <> 0 Then
            fingerprint = session_VisualFingerprintMix(fingerprint, _
                CULngInt(CInt(mixerMeter_ChannelLevel( _
                session_MixerMeter, channelIndex) * 100000.0)))
        End If
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(session_Summary.channelProgram(channelIndex)) Or _
            (CULngInt(session_MixerChannels.mute(channelIndex) And 1) Shl 8) Or _
            (CULngInt(session_MixerChannels.solo(channelIndex) And 1) Shl 9) Or _
            (CULngInt(session_MixerChannels.record(channelIndex) And &H1) Shl 10))
        If channelIndex < session_Summary.trackCount Then
            Dim As String trackName = midi_TrackDisplayName( _
                session_Summary, channelIndex)
            fingerprint = session_VisualFingerprintText(fingerprint, trackName)
        End If
    Next channelIndex

    If includeMeterLevels <> 0 Then
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CInt(session_MasterVolume * 100000.0)))
    End If
    fingerprint = session_VisualFingerprintMix(fingerprint, _
        CULngInt(CInt(session_MasterEchoWet * 100000.0)))
    fingerprint = session_VisualFingerprintMix(fingerprint, _
        CULngInt(CInt(session_MasterEchoFeedback * 100000.0)))
    If includeMeterLevels <> 0 Then
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CInt(mixerMeter_MasterLeftLevel( _
            session_MixerMeter) * 100000.0)))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CInt(mixerMeter_MasterRightLevel( _
            session_MixerMeter) * 100000.0)))
    End If
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(midiInput_IsOpen() And &H1))
    Return fingerprint
End Function


Private Sub session_DrawMixerMasterBlock( _
    ByRef mixerLayout As OseMixerControlLayout, _
    ByVal screenHeight As Integer _
)
    Dim As Integer mixerTop = mixerLayout.mixerTop
    Dim As Integer masterLeft = mixerLayout.masterLeft
    Dim As Integer faderTop = mixerLayout.faderTop
    Dim As Integer faderBottom = mixerLayout.faderBottom

    ' The master block owns its background so a live fader update erases the
    ' previous handle without forcing all sixteen channel strips to redraw.
    backend_Rect masterLeft, mixerTop + SESSION_MIXER_TITLE_HEIGHT, _
        SESSION_MIXER_MASTER_WIDTH - 4, SESSION_MIXER_HEIGHT - _
        SESSION_MIXER_TITLE_HEIGHT - 3, session_ThemePalette.panelColor, 1
    backend_Rect masterLeft, mixerTop + SESSION_MIXER_TITLE_HEIGHT, _
        SESSION_MIXER_MASTER_WIDTH - 4, SESSION_MIXER_HEIGHT - _
        SESSION_MIXER_TITLE_HEIGHT - 3, session_ThemePalette.borderColor, 0
    backend_PrintAligned masterLeft + 2, mixerTop + 31, _
        SESSION_MIXER_MASTER_WIDTH - 8, 14, session_ThemePalette.textColor, _
        "MASTER", _
        BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP

    Dim As Integer masterFaderX = masterLeft + 31
    Dim As Integer masterFaderY = faderBottom - CInt( _
        session_MasterVolume * CSng(faderBottom - faderTop))
    backend_Line masterFaderX - 1, faderTop, masterFaderX - 1, faderBottom, _
        session_ThemePalette.faderRailShadowColor
    backend_Line masterFaderX, faderTop, masterFaderX, faderBottom, _
        session_ThemePalette.faderRailColor
    backend_Rect masterFaderX - 11, masterFaderY - 5, 22, 10, _
        session_ThemePalette.faderHandleSelectedColor, 1
    backend_Rect masterFaderX - 11, masterFaderY - 5, 22, 10, _
        session_ThemePalette.faderHandleOutlineColor, 0
    backend_Line masterFaderX - 9, masterFaderY, masterFaderX + 9, _
        masterFaderY, session_ThemePalette.faderHandleLineColor

    session_DrawMixerMeter masterLeft + 63, faderTop, 11, _
        faderBottom - faderTop + 1, _
        mixerMeter_MasterLeftLevel(session_MixerMeter)
    session_DrawMixerMeter masterLeft + 80, faderTop, 11, _
        faderBottom - faderTop + 1, _
        mixerMeter_MasterRightLevel(session_MixerMeter)

    If masterEffect_IsAvailable() <> 0 Then
        session_DrawMixerKnob masterLeft + 116, faderTop + 31, _
            session_MasterEchoWet
        session_DrawMixerKnob masterLeft + 141, faderTop + 31, _
            session_MasterEchoFeedback
        backend_Print masterLeft + 104, faderTop + 42, _
            session_ThemePalette.mutedTextColor, "Wet"
        backend_Print masterLeft + 130, faderTop + 42, _
            session_ThemePalette.mutedTextColor, "Fbk"
    Else
        backend_PrintAligned masterLeft + 101, faderTop + 25, 52, 28, _
            session_ThemePalette.mutedTextColor, "Echo N/A", _
            BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE
    End If
    backend_Print masterLeft + 10, screenHeight - 29, _
        session_ThemePalette.mutedTextColor, "MIDI IN"
    backend_Rect masterLeft + 83, screenHeight - 28, 16, 10, _
        session_ThemePalette.borderColor, 0
    backend_Rect masterLeft + 87, screenHeight - 25, 8, 4, _
        Iif(midiInput_IsOpen() <> 0, session_ThemePalette.activityOnColor, _
        session_ThemePalette.activityOffColor), 1
End Sub


Private Sub session_DrawMixer(ByVal screenWidth As Integer, ByVal screenHeight As Integer)
    Dim As OseMixerControlLayout mixerLayout
    Dim As Integer mixerLayoutAnchor = session_SelectedTrack
    If session_MixerPageAnchor >= 0 Then _
        mixerLayoutAnchor = session_MixerPageAnchor
    mixerControls_CalculateLayoutForInteraction mixerLayout, screenWidth, _
        screenHeight, mixerLayoutAnchor, session_InteractionMode
    Dim As Integer mixerTop = mixerLayout.mixerTop
    Dim As Integer mixerLeft = mixerLayout.mixerLeft
    Dim As Integer masterLeft = mixerLayout.masterLeft
    Dim As Integer visibleCount = mixerLayout.visibleCount
    Dim As Integer firstChannel = mixerLayout.firstChannel

    Dim As Integer workPage = backend_GetWorkPage()
    If workPage < 0 OrElse workPage > 1 Then
        workPage = 0
    End If
    Dim As ULongInt staticFingerprint = session_MixerVisualFingerprint( _
        screenWidth, screenHeight, 0)
    Dim As ULongInt visualFingerprint = session_MixerVisualFingerprint( _
        screenWidth, screenHeight, -1)
    If session_MixerPageValid(workPage) <> 0 AndAlso _
        session_MixerPageFingerprint(workPage) = visualFingerprint Then Exit Sub
    If session_MixerPageValid(workPage) <> 0 AndAlso _
        session_MixerStaticPageFingerprint(workPage) = staticFingerprint Then
        For visibleIndex As Integer = 0 To visibleCount - 1
            Dim As Integer channelIndex = firstChannel + visibleIndex
            Dim As Integer stripRight = _
                mixerControls_StripRight(mixerLayout, visibleIndex)
            Const meterWidth As Integer = 9
            session_DrawMixerMeter stripRight - meterWidth - 4, _
                mixerLayout.faderTop, meterWidth, _
                mixerLayout.faderBottom - mixerLayout.faderTop + 1, _
                mixerMeter_ChannelLevel(session_MixerMeter, channelIndex)
        Next visibleIndex
        If Abs(session_MixerPageMasterVolume(workPage) - _
            session_MasterVolume) > 0.000001 Then
            session_DrawMixerMasterBlock mixerLayout, screenHeight
        Else
            session_DrawMixerMeter masterLeft + 63, mixerLayout.faderTop, 11, _
                mixerLayout.faderBottom - mixerLayout.faderTop + 1, _
                mixerMeter_MasterLeftLevel(session_MixerMeter)
            session_DrawMixerMeter masterLeft + 80, mixerLayout.faderTop, 11, _
                mixerLayout.faderBottom - mixerLayout.faderTop + 1, _
                mixerMeter_MasterRightLevel(session_MixerMeter)
        End If
        session_MixerPageMasterVolume(workPage) = session_MasterVolume
        session_MixerPageFingerprint(workPage) = visualFingerprint
        Exit Sub
    End If

    backend_Rect 0, mixerTop, screenWidth, SESSION_MIXER_HEIGHT, _
        session_ThemePalette.windowColor, 1
    backend_Line 0, mixerTop, screenWidth - 1, mixerTop, _
        session_ThemePalette.dividerColor
    backend_Line 0, mixerTop + 1, screenWidth - 1, mixerTop + 1, _
        session_ThemePalette.shadowColor
    backend_Rect mixerLeft, mixerTop + 3, screenWidth - mixerLeft * 2, _
        SESSION_MIXER_TITLE_HEIGHT - 4, session_ThemePalette.headerColor, 1
    backend_Line mixerLeft, mixerTop + SESSION_MIXER_TITLE_HEIGHT - 1, _
        screenWidth - 5, mixerTop + SESSION_MIXER_TITLE_HEIGHT - 1, _
        session_ThemePalette.dividerColor

    Dim As String mixerTitle = "Mixer View"
    If session_Filename <> "" Then _
        mixerTitle += " - " + session_LeafFilename(session_Filename)
    backend_PrintAligned 6, mixerTop + 5, screenWidth - 12, 15, _
        session_ThemePalette.textColor, mixerTitle, BACKEND_FONT_DEFAULT, _
        BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP

    If visibleCount < SESSION_CHANNEL_COUNT Then
        Dim As Integer maximumFirst = SESSION_CHANNEL_COUNT - visibleCount
        session_DrawMixerPageButton mixerLayout.pagePreviousLeft, _
            mixerLayout.pageButtonTop, mixerLayout.pageButtonWidth, _
            mixerLayout.pageButtonHeight, -1, IIf(firstChannel > 0, -1, 0)
        session_DrawMixerPageButton mixerLayout.pageNextLeft, _
            mixerLayout.pageButtonTop, mixerLayout.pageButtonWidth, _
            mixerLayout.pageButtonHeight, 1, _
            IIf(firstChannel < maximumFirst, -1, 0)
        backend_Print mixerLayout.pageNextLeft + _
            mixerLayout.pageButtonWidth + 7, mixerTop + 8, _
            session_ThemePalette.mutedTextColor, _
            "Channels " + Str(firstChannel + 1) + _
            "-" + Str(firstChannel + visibleCount) + " of " + _
            Str(SESSION_CHANNEL_COUNT)
    End If

    Dim As Integer faderTop = mixerLayout.faderTop
    Dim As Integer faderBottom = mixerLayout.faderBottom
    Dim As Integer knobY = mixerLayout.knobCenterY
    Dim As Integer nameBoxTop = mixerLayout.nameBoxTop
    Dim As Integer buttonTop = mixerLayout.buttonTop

    For visibleIndex As Integer = 0 To visibleCount - 1
        Dim As Integer channelIndex = firstChannel + visibleIndex
        Dim As Integer stripLeft = _
            mixerControls_StripLeft(mixerLayout, visibleIndex)
        Dim As Integer stripRight = _
            mixerControls_StripRight(mixerLayout, visibleIndex)
        Dim As ULong stripColor = session_ThemePalette.panelColor
        Dim As ULong channelTextColor = session_ThemePalette.textColor
        If channelIndex >= session_Summary.trackCount Then
            stripColor = session_ThemePalette.alternatePanelColor
            channelTextColor = session_ThemePalette.faintTextColor
        ElseIf channelIndex = session_SelectedTrack Then
            stripColor = session_ThemePalette.selectedPanelColor
        End If
        backend_Rect stripLeft, mixerTop + SESSION_MIXER_TITLE_HEIGHT, _
            stripRight - stripLeft + 1, SESSION_MIXER_HEIGHT - _
            SESSION_MIXER_TITLE_HEIGHT - 3, stripColor, 1
        backend_Rect stripLeft, mixerTop + SESSION_MIXER_TITLE_HEIGHT, _
            stripRight - stripLeft + 1, SESSION_MIXER_HEIGHT - _
            SESSION_MIXER_TITLE_HEIGHT - 3, session_ThemePalette.borderColor, 0
        If channelIndex = session_SelectedTrack AndAlso _
            channelIndex < session_Summary.trackCount Then
            backend_Rect stripLeft + 2, mixerTop + SESSION_MIXER_TITLE_HEIGHT + 2, _
                stripRight - stripLeft - 3, 3, _
                session_ThemePalette.accentBrightColor, 1
        End If

        Dim As String channelName = "Track " + Str(channelIndex + 1)
        If channelIndex < session_Summary.trackCount Then
            channelName = Str(channelIndex + 1) + " - " + _
                midi_TrackDisplayName(session_Summary, channelIndex)
        End If
        Dim As Integer maximumNameCharacters = (stripRight - stripLeft - 4) \ 8
        If maximumNameCharacters < 3 Then
            maximumNameCharacters = 3
        End If
        channelName = session_ClipText(channelName, maximumNameCharacters)
        backend_PrintAligned stripLeft + 2, mixerTop + 30, _
            stripRight - stripLeft - 3, 13, channelTextColor, channelName, _
            BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP

        Dim As Integer meterWidth = 9
        Dim As Integer meterLeft = stripRight - meterWidth - 4
        Dim As Integer faderX = _
            mixerControls_ChannelFaderX(mixerLayout, visibleIndex)
        backend_Line faderX - 1, faderTop, faderX - 1, faderBottom, _
            session_ThemePalette.faderRailShadowColor
        backend_Line faderX, faderTop, faderX, faderBottom, _
            session_ThemePalette.faderRailColor
        For tickIndex As Integer = 0 To 4
            Dim As Integer tickY = faderTop + _
                ((faderBottom - faderTop) * tickIndex) \ 4
            backend_Line faderX - 6, tickY, faderX - 3, tickY, _
                session_ThemePalette.faderTickColor
        Next

        Dim As Integer faderY = faderBottom - CInt( _
            session_ChannelVolume(channelIndex) * CSng(faderBottom - faderTop))
        Dim As ULong faderColor = session_ThemePalette.faderHandleColor
        If channelIndex = session_SelectedTrack Then _
            faderColor = session_ThemePalette.faderHandleSelectedColor
        backend_Rect faderX - 9, faderY - 5, 18, 10, faderColor, 1
        backend_Rect faderX - 9, faderY - 5, 18, 10, _
            session_ThemePalette.faderHandleOutlineColor, 0
        backend_Line faderX - 7, faderY, faderX + 7, faderY, _
            session_ThemePalette.faderHandleLineColor

        Dim As Single meterLevel = mixerMeter_ChannelLevel( _
            session_MixerMeter, channelIndex)
        session_DrawMixerMeter meterLeft, faderTop, meterWidth, _
            faderBottom - faderTop + 1, meterLevel

        backend_Rect stripLeft + 3, nameBoxTop, stripRight - stripLeft - 5, _
            17, session_ThemePalette.insetColor, 1
        backend_Rect stripLeft + 3, nameBoxTop, stripRight - stripLeft - 5, _
            17, session_ThemePalette.borderColor, 0
        Dim As String instrumentName = "Prog " + _
            Str(CInt(session_Summary.channelProgram(channelIndex)) + 1)
        If channelIndex = 9 Then
            instrumentName = "Drums"
        End If
        instrumentName = session_ClipText(instrumentName, maximumNameCharacters)
        backend_PrintAligned stripLeft + 4, nameBoxTop + 3, _
            stripRight - stripLeft - 7, 12, channelTextColor, instrumentName, _
            BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP

        Dim As Integer knobCellWidth = (stripRight - stripLeft + 1) \ 3
        Dim As Single knobValue(0 To 2)
        knobValue(0) = session_ChannelChorus(channelIndex)
        knobValue(1) = session_ChannelReverb(channelIndex)
        knobValue(2) = (session_ChannelPan(channelIndex) + 1.0) * 0.5
        Dim As String knobLabel(0 To 2) = {"Ch", "Rv", "Pn"}
        For knobIndex As Integer = 0 To 2
            Dim As Integer knobCenterX = stripLeft + knobCellWidth * knobIndex + _
                knobCellWidth \ 2
            session_DrawMixerKnob knobCenterX, knobY, knobValue(knobIndex)
            backend_PrintAligned knobCenterX - knobCellWidth \ 2, knobY + 8, _
                knobCellWidth, 9, session_ThemePalette.mutedTextColor, _
                knobLabel(knobIndex), _
                BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP
        Next

        Dim As Integer buttonSpan = stripRight - stripLeft + 1
        For buttonIndex As Integer = 0 To 2
            Dim As Integer buttonLeft = stripLeft + _
                (buttonIndex * buttonSpan) \ 3
            Dim As Integer buttonRight = stripLeft + _
                ((buttonIndex + 1) * buttonSpan) \ 3 - 1
            Dim As Integer buttonState = 0
            Dim As String buttonLabel = "M"
            Select Case buttonIndex
                Case 0
                    buttonState = session_MixerChannels.mute(channelIndex)
                    buttonLabel = "M"
                Case 1
                    buttonState = session_MixerChannels.solo(channelIndex)
                    buttonLabel = "S"
                Case 2
                    buttonState = session_MixerChannels.record(channelIndex)
                    buttonLabel = "R"
            End Select
            Dim As OseUiControlStyle buttonStyle
            uiStyle_MixerButton buttonStyle, session_ThemePalette, _
                buttonIndex, buttonState
            session_DrawRoundedControl buttonLeft, buttonTop, _
                buttonRight - buttonLeft + 1, _
                mixerLayout.buttonHeight, buttonStyle
            backend_PrintAligned buttonLeft, _
                buttonTop + (mixerLayout.buttonHeight - 8) \ 2, _
                buttonRight - buttonLeft + 1, 10, buttonStyle.contentColor, _
                buttonLabel, BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, _
                BACKEND_ALIGN_TOP
        Next
    Next

    ' The right-hand master block is deliberately wider than a channel strip,
    ' matching the Recording Session layout and keeping transport state legible.
    session_DrawMixerMasterBlock mixerLayout, screenHeight
    session_MixerPageFingerprint(workPage) = visualFingerprint
    session_MixerStaticPageFingerprint(workPage) = staticFingerprint
    session_MixerPageMasterVolume(workPage) = session_MasterVolume
    session_MixerPageValid(workPage) = -1
End Sub


Private Sub session_DrawRaisedPanel( _
    ByVal panelLeft As Integer, _
    ByVal panelTop As Integer, _
    ByVal panelWidth As Integer, _
    ByVal panelHeight As Integer, _
    ByVal faceColor As ULong _
)
    If panelWidth <= 1 OrElse panelHeight <= 1 Then
        Exit Sub
    End If
    backend_Rect panelLeft, panelTop, panelWidth, panelHeight, faceColor, 1
    backend_Line panelLeft, panelTop, panelLeft + panelWidth - 1, _
        panelTop, session_ThemePalette.highlightColor
    backend_Line panelLeft, panelTop, panelLeft, panelTop + panelHeight - 1, _
        session_ThemePalette.highlightColor
    backend_Line panelLeft, panelTop + panelHeight - 1, _
        panelLeft + panelWidth - 1, panelTop + panelHeight - 1, _
        session_ThemePalette.shadowColor
    backend_Line panelLeft + panelWidth - 1, panelTop, _
        panelLeft + panelWidth - 1, panelTop + panelHeight - 1, _
        session_ThemePalette.shadowColor
End Sub


Private Sub session_DrawUiIcon( _
    ByVal iconId As Integer, _
    ByVal iconLeft As Integer, _
    ByVal iconTop As Integer, _
    ByVal iconColor As ULong _
)
    If uiIcons_IsValid(iconId) = 0 Then
        Exit Sub
    End If

    /'
        The atlas stores grayscale coverage, not RGB subpixels. Alpha blending
        preserves its hand-hinted edge on BGR, RGB, rotated, and scaled displays
        without baking a monitor-specific color fringe into the application.
    '/
    Dim As UByte iconCoverage(0 To OSE_UI_ICON_SIZE * OSE_UI_ICON_SIZE - 1)
    For pixelY As Integer = 0 To OSE_UI_ICON_SIZE - 1
        Dim As String rowText
        If uiIcons_GetRow(iconId, pixelY, rowText) = 0 Then
            Exit Sub
        End If
        For pixelX As Integer = 0 To OSE_UI_ICON_SIZE - 1
            iconCoverage(pixelY * OSE_UI_ICON_SIZE + pixelX) = _
                uiIcons_DecodeCoverage(rowText[pixelX])
        Next
    Next
    If backend_DrawAlphaMask(iconLeft, iconTop, OSE_UI_ICON_SIZE, _
        OSE_UI_ICON_SIZE, @iconCoverage(0), iconColor) <> 0 Then Exit Sub

    For pixelY As Integer = 0 To OSE_UI_ICON_SIZE - 1
        For pixelX As Integer = 0 To OSE_UI_ICON_SIZE - 1
            Dim As Integer coverage = _
                iconCoverage(pixelY * OSE_UI_ICON_SIZE + pixelX)
            If coverage > 0 Then backend_PSetAlpha iconLeft + pixelX, _
                iconTop + pixelY, iconColor, coverage
        Next pixelX
    Next pixelY
End Sub


Private Sub session_DrawFilledEllipse( _
    ByVal ellipseLeft As Integer, _
    ByVal ellipseTop As Integer, _
    ByVal ellipseWidth As Integer, _
    ByVal ellipseHeight As Integer, _
    ByVal ellipseColor As ULong _
)
    If ellipseWidth <= 0 OrElse ellipseHeight <= 0 Then
        Exit Sub
    End If

    Dim As GraphicShapeRenderOptions options
    Dim As Integer pointX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer pointY(1 To GRAPHICSHAPE_MAX_POINTS)
    graphicshape_DefaultOptions options, GUI_SHAPE_ELLIPSE
    options.stroke_clr = ellipseColor
    options.fill_clr = ellipseColor
    options.filled = -1
    options.line_width = 1
    options.object_alpha = 255
    options.stroke_alpha = 255
    options.fill_alpha = 255
    options.clip_to_bounds = -1
    graphicshape_RenderWithOptions ellipseLeft, ellipseTop, ellipseWidth, _
        ellipseHeight, options, "", 0, pointX(), pointY()
End Sub


Private Sub session_DrawRoundedControl( _
    ByVal controlLeft As Integer, _
    ByVal controlTop As Integer, _
    ByVal controlWidth As Integer, _
    ByVal controlHeight As Integer, _
    ByRef controlStyle As OseUiControlStyle _
)
    If controlWidth <= 0 OrElse controlHeight <= 0 Then
        Exit Sub
    End If

    Dim As GraphicShapeRenderOptions options
    Dim As Integer pointX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer pointY(1 To GRAPHICSHAPE_MAX_POINTS)
    graphicshape_DefaultOptions options, GUI_SHAPE_ROUNDED_RECTANGLE
    options.stroke_clr = controlStyle.borderColor
    options.fill_clr = controlStyle.fillColor
    options.filled = -1
    options.line_width = 1
    options.corner_radius = controlStyle.cornerRadius
    options.object_alpha = 255
    options.stroke_alpha = 255
    options.fill_alpha = 255
    options.clip_to_bounds = -1
    graphicshape_RenderWithOptions controlLeft, controlTop, controlWidth, _
        controlHeight, options, "", 0, pointX(), pointY()
End Sub


Private Sub session_DrawScoreToolRail(ByVal screenHeight As Integer)
    Dim As Integer workPage = backend_GetWorkPage()
    If workPage < 0 OrElse workPage > 1 Then
        workPage = 0
    End If
    Dim As ULongInt visualFingerprint = &h519e7a4dull
    visualFingerprint = session_VisualFingerprintMix( _
        visualFingerprint, CULngInt(screenHeight))
    visualFingerprint = session_VisualFingerprintMix( _
        visualFingerprint, CULngInt(session_ThemeMode))
    visualFingerprint = session_VisualFingerprintMix( _
        visualFingerprint, CULngInt(session_ActiveScoreTool + 1))
    visualFingerprint = session_VisualFingerprintMix( _
        visualFingerprint, CULngInt(session_NoteClipboard.count))
    If session_ScoreToolPageValid(workPage) <> 0 AndAlso _
        session_ScoreToolPageFingerprint(workPage) = visualFingerprint Then _
        Exit Sub

    Dim As Integer railBottom = screenHeight - SESSION_MIXER_HEIGHT - 4
    backend_Rect 2, SESSION_SCORE_TOP, SESSION_SCORE_LEFT - 4, _
        railBottom - SESSION_SCORE_TOP, session_ThemePalette.railColor, 1
    For toolIndex As Integer = 0 To SESSION_SCORE_TOOL_COUNT - 1
        Dim As Integer toolTop = session_InteractionMetrics.scoreRailFirstTop + _
            toolIndex * session_InteractionMetrics.scoreRailStep
        Dim As Integer toolEnabled = -1
        If toolIndex = SESSION_SCORE_TOOL_PASTE AndAlso _
            session_NoteClipboard.count <= 0 Then toolEnabled = 0
        Dim As OseUiControlStyle toolStyle
        uiStyle_ScoreTool toolStyle, session_ThemePalette, _
            IIf(toolIndex = session_ActiveScoreTool, -1, 0), toolEnabled
        session_DrawRoundedControl session_InteractionMetrics.scoreRailLeft, _
            toolTop, session_InteractionMetrics.scoreRailWidth, _
            session_InteractionMetrics.scoreRailHeight, _
            toolStyle

        Dim As ULong iconColor = toolStyle.contentColor
        Dim As Integer iconLeft = session_InteractionMetrics.scoreRailLeft + _
            uiIcons_CenteredOffset(32)
        Dim As Integer iconTop = toolTop + uiIcons_CenteredOffset( _
            session_InteractionMetrics.scoreRailHeight)

        Select Case toolIndex
            Case SESSION_SCORE_TOOL_SELECT
                session_DrawUiIcon OSE_UI_ICON_POINTER, iconLeft, iconTop, _
                    iconColor
            Case SESSION_SCORE_TOOL_ADD_NOTE
                session_DrawUiIcon OSE_UI_ICON_NOTE, iconLeft, iconTop, iconColor

            Case SESSION_SCORE_TOOL_DELETE_NOTE
                session_DrawUiIcon OSE_UI_ICON_TRASH, iconLeft, iconTop, _
                    iconColor

            Case SESSION_SCORE_TOOL_CUT
                session_DrawUiIcon OSE_UI_ICON_CUT, iconLeft, iconTop, iconColor

            Case SESSION_SCORE_TOOL_PASTE
                session_DrawUiIcon OSE_UI_ICON_PASTE, iconLeft, iconTop, _
                    iconColor
        End Select

        ' The icon and stable text name form one accessible visual control.
        ' Users never have to infer an editing action from a tiny glyph alone.
        backend_Print session_InteractionMetrics.scoreRailLeft + 32, _
            toolTop + (session_InteractionMetrics.scoreRailHeight - 8) \ 2, _
            iconColor, scoreControls_ToolLabel(toolIndex)
    Next
    session_ScoreToolPageFingerprint(workPage) = visualFingerprint
    session_ScoreToolPageValid(workPage) = -1
End Sub


Private Function session_DrawPaletteButton( _
    ByVal buttonLeft As Integer, ByVal buttonTop As Integer, _
    ByVal selected As Integer _
) As ULong
    Dim As OseUiControlStyle buttonStyle
    uiStyle_ScoreTool buttonStyle, session_ThemePalette, selected, -1
    buttonStyle.cornerRadius = 4
    session_DrawRoundedControl buttonLeft, buttonTop, _
        SESSION_SCORE_PALETTE_FACE_WIDTH, _
        SESSION_SCORE_PALETTE_FACE_HEIGHT, buttonStyle
    Return buttonStyle.contentColor
End Function


Private Sub session_DrawPaletteDurationIcon( _
    ByVal durationIndex As Integer, _
    ByVal buttonLeft As Integer, _
    ByVal buttonTop As Integer, _
    ByVal iconColor As ULong _
)
    Dim As Integer noteX = buttonLeft + 8
    Dim As Integer noteY = buttonTop + 15
    Dim As Integer filledHead = IIf( _
        durationIndex >= OSE_SCORE_DURATION_QUARTER, -1, 0)
    session_DrawVectorNoteHead noteX, noteY, 8, 6, filledHead, iconColor
    If durationIndex = OSE_SCORE_DURATION_WHOLE Then
        Exit Sub
    End If

    Dim As Integer stemX = noteX + 3
    Dim As Integer stemTop = buttonTop + 3
    session_DrawVectorNoteStem stemX, noteY, stemTop, 2, iconColor
    Dim As Integer flagCount = durationIndex - OSE_SCORE_DURATION_QUARTER
    If flagCount < 0 Then
        flagCount = 0
    End If
    For flagIndex As Integer = 0 To flagCount - 1
        session_DrawVectorNoteFlag stemX, stemTop + flagIndex * 3, -1, _
            11, 11, iconColor
    Next
End Sub


Private Sub session_DrawPaletteModifierIcon( _
    ByVal modifierRow As Integer, _
    ByVal buttonLeft As Integer, _
    ByVal buttonTop As Integer, _
    ByVal iconColor As ULong _
)
    Select Case modifierRow
        Case 0
            backend_Line buttonLeft + 7, buttonTop + 3, _
                buttonLeft + 5, buttonTop + 18, iconColor
            backend_Line buttonLeft + 14, buttonTop + 3, _
                buttonLeft + 12, buttonTop + 18, iconColor
            backend_Line buttonLeft + 3, buttonTop + 8, _
                buttonLeft + 17, buttonTop + 6, iconColor
            backend_Line buttonLeft + 3, buttonTop + 14, _
                buttonLeft + 17, buttonTop + 12, iconColor
        Case 1
            backend_Line buttonLeft + 8, buttonTop + 2, _
                buttonLeft + 8, buttonTop + 18, iconColor
            backend_Line buttonLeft + 9, buttonTop + 10, _
                buttonLeft + 15, buttonTop + 8, iconColor
            backend_Line buttonLeft + 15, buttonTop + 8, _
                buttonLeft + 14, buttonTop + 15, iconColor
            backend_Line buttonLeft + 14, buttonTop + 15, _
                buttonLeft + 8, buttonTop + 18, iconColor
        Case 2
            backend_Line buttonLeft + 6, buttonTop + 3, _
                buttonLeft + 6, buttonTop + 17, iconColor
            backend_Line buttonLeft + 14, buttonTop + 2, _
                buttonLeft + 14, buttonTop + 16, iconColor
            backend_Line buttonLeft + 6, buttonTop + 8, _
                buttonLeft + 14, buttonTop + 5, iconColor
            backend_Line buttonLeft + 6, buttonTop + 14, _
                buttonLeft + 14, buttonTop + 11, iconColor
        Case 3
            session_DrawFilledEllipse buttonLeft + 8, buttonTop + 8, 5, 5, _
                iconColor
        Case 4
            backend_Print buttonLeft + 7, buttonTop + 5, iconColor, "3"
        Case 5
            backend_Line buttonLeft + 3, buttonTop + 11, _
                buttonLeft + 7, buttonTop + 15, iconColor
            backend_Line buttonLeft + 7, buttonTop + 15, _
                buttonLeft + 14, buttonTop + 15, iconColor
            backend_Line buttonLeft + 14, buttonTop + 15, _
                buttonLeft + 18, buttonTop + 11, iconColor
            backend_Line buttonLeft + 4, buttonTop + 12, _
                buttonLeft + 17, buttonTop + 12, iconColor
    End Select
End Sub


Private Sub session_DrawAddNotePalette()
    If session_ActiveScoreTool <> SESSION_SCORE_TOOL_ADD_NOTE OrElse _
        session_AddPaletteVisible = 0 Then Exit Sub

    session_DrawRaisedPanel SESSION_SCORE_PALETTE_LEFT, _
        SESSION_SCORE_PALETTE_TOP, SESSION_SCORE_PALETTE_WIDTH, _
        SESSION_SCORE_PALETTE_HEIGHT, session_ThemePalette.paletteColor

    For rowIndex As Integer = 0 To SESSION_SCORE_PALETTE_ROW_COUNT - 1
        Dim As Integer buttonTop = SESSION_SCORE_PALETTE_TOP + 4 + _
            rowIndex * SESSION_SCORE_PALETTE_ROW_HEIGHT
        Dim As Integer durationLeft = SESSION_SCORE_PALETTE_LEFT + 4
        Dim As Integer contentTop = buttonTop + _
            (SESSION_SCORE_PALETTE_FACE_HEIGHT - 25) \ 2
        Dim As Integer durationSelected = IIf( _
            session_AddToolState.durationIndex = rowIndex, -1, 0)
        Dim As ULong durationColor = session_DrawPaletteButton( _
            durationLeft, buttonTop, durationSelected)
        session_DrawPaletteDurationIcon rowIndex, durationLeft, contentTop, _
            durationColor
        backend_Print durationLeft + 28, contentTop + 8, durationColor, _
            scoreControls_DurationLabel(rowIndex)

        If rowIndex < 6 Then
            Dim As Integer modifierLeft = durationLeft + _
                SESSION_SCORE_PALETTE_COLUMN_WIDTH
            Dim As Integer modifierSelected
            Select Case rowIndex
                Case 0
                    modifierSelected = session_AddToolState.accidentalSemitones > 0
                Case 1
                    modifierSelected = session_AddToolState.accidentalSemitones < 0
                Case 2
                    modifierSelected = session_AddToolState.accidentalSemitones = 0
                Case 3
                    modifierSelected = session_AddToolState.dotted
                Case 4
                    modifierSelected = session_AddToolState.triplet
                Case 5
                    modifierSelected = session_AddToolState.tied
            End Select
            Dim As ULong modifierColor = session_DrawPaletteButton( _
                modifierLeft, buttonTop, modifierSelected)
            session_DrawPaletteModifierIcon rowIndex, modifierLeft, _
                contentTop, _
                modifierColor
            backend_Print modifierLeft + 28, contentTop + 8, modifierColor, _
                scoreControls_ModifierLabel(rowIndex)
        End If
    Next
End Sub


Private Sub session_DrawScoreToolCursor( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    If session_IsModalOpen() <> 0 OrElse _
        session_ActiveScoreTool = SESSION_SCORE_TOOL_SELECT Then Exit Sub

    Dim As Integer mouseX = input_MouseX()
    Dim As Integer mouseY = input_MouseY()
    Dim As Integer editLeft
    Dim As Integer editTop
    Dim As Integer editRight
    Dim As Integer editBottom
    session_ScoreEditBounds screenWidth, screenHeight, editLeft, editTop, _
        editRight, editBottom
    If mouseX < editLeft OrElse mouseX > editRight OrElse _
        mouseY < editTop OrElse mouseY > editBottom Then Exit Sub

    Select Case session_ActiveScoreTool
        Case SESSION_SCORE_TOOL_ADD_NOTE
            Dim As ULongInt guideTick = session_TickFromScreenX(mouseX, screenWidth)
            Dim As Integer guideX = session_ScoreTickToX(guideTick, editLeft, _
                editRight, session_ViewTicks())
            backend_Line guideX, SESSION_SCORE_TOP + 25, guideX, editBottom, _
                session_ThemePalette.accentBrightColor
            session_DrawVectorNoteHead guideX - 4, mouseY + 3, 9, 6, -1, _
                session_ThemePalette.accentColor
            session_DrawVectorNoteStem guideX, mouseY + 3, mouseY - 10, _
                2, session_ThemePalette.accentColor
        Case SESSION_SCORE_TOOL_DELETE_NOTE
            session_DrawUiIcon OSE_UI_ICON_TRASH, mouseX - 12, mouseY - 12, _
                session_ThemePalette.textColor
        Case SESSION_SCORE_TOOL_CUT
            session_DrawUiIcon OSE_UI_ICON_CUT, mouseX - 12, mouseY - 12, _
                session_ThemePalette.textColor
        Case SESSION_SCORE_TOOL_PASTE
            session_DrawUiIcon OSE_UI_ICON_PASTE, mouseX - 12, mouseY - 12, _
                session_ThemePalette.textColor
    End Select
End Sub


Private Sub session_DrawApplication(ByVal screenWidth As Integer, ByVal screenHeight As Integer)
    Dim As Integer workPage = backend_GetWorkPage()
    If workPage < 0 OrElse workPage > 1 Then
        workPage = 0
    End If
    Dim As Integer visibleMenu = session_VisibleDesktopMenuIndex()
    Dim As Integer modalState = session_IsModalOpen()
    Dim As Integer chromeStatus = _
        IIf(session_LiveRecording <> 0 OrElse _
        session_MicCaptureActive <> 0, 1, 0) Or _
        IIf(session_MidiOutputOpened <> 0, 2, 0)
    Dim As Integer redrawStaticChrome = _
        session_ChromePageWidth(workPage) <> screenWidth OrElse _
        session_ChromePageHeight(workPage) <> screenHeight OrElse _
        session_ChromePageTheme(workPage) <> session_ThemeMode OrElse _
        session_ChromePageKeyboardAccess(workPage) <> _
            session_MenuKeyboardAccess OrElse _
        session_ChromePageVisibleMenu(workPage) <> visibleMenu OrElse _
        session_ChromePageModalState(workPage) <> modalState OrElse _
        session_ChromePageStatus(workPage) <> chromeStatus

    /'
        Double-buffered static chrome

        Each work page retains pixels from its previous presentation. Menu and
        toolbar chrome therefore needs rebuilding only when page-local state
        changes. Score, mixer, widgets, and live indicators still redraw below.
        Tracking both pages avoids stale pixels when overlays open or close.
    '/
    If redrawStaticChrome <> 0 Then
        backend_Rect 0, 0, screenWidth, screenHeight, _
            session_ThemePalette.windowColor, 1
        session_ScoreStaticPageWidth(workPage) = 0
        session_ScorePageValid(workPage) = 0
        session_ScoreHeaderPageValid(workPage) = 0
        session_MixerPageValid(workPage) = 0
        session_ScoreToolPageValid(workPage) = 0
        session_StatusPageValid(workPage) = 0

        ' The menu and command shelf retain the compact desktop layout while using
        ' a flat neutral surface that lets interactive states carry the hierarchy.
        backend_Rect 0, 0, screenWidth, SESSION_MENU_HEIGHT, _
            session_ThemePalette.menuBarColor, 1
        backend_Line 0, SESSION_MENU_HEIGHT - 1, screenWidth - 1, _
            SESSION_MENU_HEIGHT - 1, session_ThemePalette.dividerColor
        Dim As Integer menuTextY = (SESSION_MENU_HEIGHT - 8) \ 2
        backend_Print 10, menuTextY, session_ThemePalette.textColor, "File"
        backend_Print 50, menuTextY, session_ThemePalette.textColor, "Edit"
        backend_Print 90, menuTextY, session_ThemePalette.textColor, "Options"
        backend_Print 154, menuTextY, session_ThemePalette.textColor, "Setup"
        backend_Print 210, menuTextY, session_ThemePalette.textColor, "View"
        backend_Print 258, menuTextY, session_ThemePalette.textColor, "Track"
        backend_Print 312, menuTextY, session_ThemePalette.textColor, "Music"
        backend_Print screenWidth - 42, menuTextY, _
            session_ThemePalette.textColor, "Help"

        If session_MenuKeyboardAccess <> 0 Then
            ' Underline each mnemonic only while the menu bar is being operated
            ' from the keyboard, matching contemporary desktop focus-cue policy.
            Dim As Integer mnemonicX(0 To SESSION_DESKTOP_MENU_COUNT - 1) = { _
                10, 50, 90, 154, 210, 258, 312, screenWidth - 42 _
            }
            For mnemonicIndex As Integer = 0 To SESSION_DESKTOP_MENU_COUNT - 1
                backend_Line mnemonicX(mnemonicIndex), menuTextY + 9, _
                    mnemonicX(mnemonicIndex) + 6, menuTextY + 9, _
                    session_ThemePalette.textColor
            Next
        End If

        backend_Rect 0, SESSION_TOOLBAR_TOP, screenWidth, _
            SESSION_TOOLBAR_HEIGHT, session_ThemePalette.toolbarColor, 1
        backend_Line 0, SESSION_TOOLBAR_TOP + SESSION_TOOLBAR_HEIGHT - 1, _
            screenWidth - 1, SESSION_TOOLBAR_TOP + SESSION_TOOLBAR_HEIGHT - 1, _
            session_ThemePalette.dividerColor
        Dim As Integer dividerCount = IIf( _
            session_InteractionMode = OSE_UI_INTERACTION_TOUCH, 2, 5)
        For dividerIndex As Integer = 0 To dividerCount - 1
            Dim As Integer dividerX
            If session_InteractionMode = OSE_UI_INTERACTION_TOUCH Then
                dividerX = IIf(dividerIndex = 0, 194, 618)
            Else
                Select Case dividerIndex
                    Case 0
                        dividerX = 160
                    Case 1
                        dividerX = 508
                    Case 2
                        dividerX = 648
                    Case 3
                        dividerX = 846
                    Case Else
                        dividerX = 990
                End Select
            End If
            backend_Line dividerX, SESSION_TOOLBAR_TOP + 4, dividerX, _
                SESSION_TOOLBAR_TOP + SESSION_TOOLBAR_HEIGHT - 5, _
                session_ThemePalette.shadowColor
        Next

        If screenWidth >= 1040 AndAlso _
            session_InteractionMode = OSE_UI_INTERACTION_FINE Then
            backend_Print 654, SESSION_TOOLBAR_TOP + 13, _
                session_ThemePalette.textColor, "Tempo"
        End If

        If screenWidth >= 1040 AndAlso _
            session_InteractionMode = OSE_UI_INTERACTION_FINE Then
            backend_PrintAligned 510, SESSION_TOOLBAR_TOP + 2, 136, 12, _
                session_ThemePalette.textColor, "MEASURE  BEAT  TICK", _
                BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP
        End If
        If screenWidth >= 1100 AndAlso _
            session_InteractionMode = OSE_UI_INTERACTION_FINE Then
            Dim As ULong statusColor = session_ThemePalette.activityOffColor
            If (chromeStatus And 1) <> 0 Then _
                statusColor = session_ThemePalette.dangerColor
            backend_Circle screenWidth - 18, SESSION_TOOLBAR_TOP + 13, 5, _
                statusColor, 1
            backend_Print screenWidth - 28, SESSION_TOOLBAR_TOP + 24, _
                session_ThemePalette.mutedTextColor, "In"
            backend_Circle screenWidth - 18, SESSION_TOOLBAR_TOP + 36, 5, _
                IIf((chromeStatus And 2) <> 0, _
                session_ThemePalette.activityOnColor, _
                session_ThemePalette.activityOffColor), 1
            backend_Print screenWidth - 30, SESSION_TOOLBAR_TOP + 44, _
                session_ThemePalette.mutedTextColor, "Out"
        End If

        session_ChromePageWidth(workPage) = screenWidth
        session_ChromePageHeight(workPage) = screenHeight
        session_ChromePageTheme(workPage) = session_ThemeMode
        session_ChromePageKeyboardAccess(workPage) = session_MenuKeyboardAccess
        session_ChromePageVisibleMenu(workPage) = visibleMenu
        session_ChromePageModalState(workPage) = modalState
        session_ChromePageStatus(workPage) = chromeStatus
    End If

    /'
        The status label is transparent and changes independently of the rest
        of the toolbar. Own its small background explicitly so repeated modal
        widget passes cannot accumulate antialiased coverage into bold text.
    '/
    If session_StatusLabel <> 0 AndAlso _
        session_StatusLabel->data <> 0 Then
        Dim As LabelData Ptr statusData = Cast( _
            LabelData Ptr, session_StatusLabel->data)
        Dim As ULongInt statusFingerprint = session_VisualFingerprintText( _
            &h27d4eb2f165667c5ull, statusData->text)
        If session_StatusPageValid(workPage) = 0 OrElse _
            session_StatusPageFingerprint(workPage) <> statusFingerprint Then
            Dim As Integer statusWidth = screenWidth - 54 - _
                session_StatusLabel->x
            If statusWidth > 0 Then
                backend_Rect 0, session_StatusLabel->y - 1, screenWidth, 12, _
                    session_ThemePalette.toolbarColor, 1
                backend_Line 0, session_StatusLabel->y + 10, screenWidth - 1, _
                    session_StatusLabel->y + 10, session_ThemePalette.dividerColor
                backend_Print session_StatusLabel->x, _
                    session_StatusLabel->y, session_ThemePalette.textColor, _
                    statusData->text
            End If
            session_StatusPageFingerprint(workPage) = statusFingerprint
            session_StatusPageValid(workPage) = -1
        End If
    End If

    Dim As ULongInt displayTick = session_ViewStartTick
    If session_Playing <> 0 Then displayTick = midi_SecondsToTicks( _
        session_Summary, session_PlaybackElapsed)
    Dim As ULongInt displayMeasure
    Dim As ULongInt displayBeat
    Dim As ULongInt displaySubTick
    session_MusicalPosition displayTick, displayMeasure, displayBeat, _
        displaySubTick
    If screenWidth >= 1040 AndAlso _
        session_InteractionMode = OSE_UI_INTERACTION_FINE Then
        backend_Rect 510, SESSION_TOOLBAR_TOP + 16, 136, 25, _
            session_ThemePalette.timelineFillColor, 1
        backend_Rect 510, SESSION_TOOLBAR_TOP + 16, 136, 25, _
            session_ThemePalette.timelineBorderColor, 0
        backend_PrintAligned 510, SESSION_TOOLBAR_TOP + 22, 136, 12, _
            session_ThemePalette.timelineTextColor, _
            LTrim(Str(displayMeasure)) + " : " + LTrim(Str(displayBeat)) + _
            " : " + LTrim(Str(displaySubTick)), BACKEND_FONT_DEFAULT, _
            BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP
    End If

    Dim As Double smoothnessSectionClock
    If session_SmoothnessProfilingActive <> 0 Then _
        smoothnessSectionClock = Timer
    session_DrawScore screenWidth, screenHeight
    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessScoreRenderMs = uiFramePacing_ElapsedMilliseconds( _
            smoothnessSectionClock, Timer)
        smoothnessSectionClock = Timer
    End If
    session_DrawScoreToolRail screenHeight
    session_DrawAddNotePalette()
    session_DrawScoreToolCursor screenWidth, screenHeight
    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessScoreToolRenderMs = _
            uiFramePacing_ElapsedMilliseconds(smoothnessSectionClock, Timer)
        smoothnessSectionClock = Timer
    End If
    session_DrawMixer screenWidth, screenHeight
    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessMixerRenderMs = uiFramePacing_ElapsedMilliseconds( _
            smoothnessSectionClock, Timer)
    End If
End Sub


Private Function session_MainWidgetFingerprint( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
) As ULongInt
    Dim As ULongInt fingerprint = &h27d4eb2f165667c5ull

    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(screenWidth))
    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(screenHeight))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_ThemeMode))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Playing And &H1))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Paused And &H1))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_LiveRecording And &H1))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_MenuKeyboardAccess And &H1))
    If session_TempoBox <> 0 Then fingerprint = session_VisualFingerprintText( _
        fingerprint, textbox_GetText(session_TempoBox))

    /'
        Pointer movement over the menu or toolbar may change hover and pressed
        faces even when document state is unchanged. Below the toolbar, the
        main widgets are stable except for the two score scrollbars, which the
        cached renderer refreshes separately.
    '/
    If input_MouseY() < SESSION_SCORE_TOP Then
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, CULngInt(CUInt(input_MouseX())))
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, CULngInt(CUInt(input_MouseY())))
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, CULngInt(CUInt(input_MouseButtons())))
    End If
    Return fingerprint
End Function


Private Sub session_RenderTopLevelWidget(ByVal targetWidget As Widget Ptr)
    If targetWidget = 0 OrElse targetWidget->evis = 0 OrElse _
        targetWidget->render = 0 Then Exit Sub
    If targetWidget->w <= 0 OrElse targetWidget->h <= 0 Then
        Exit Sub
    End If

    backend_SetClip targetWidget->ax, targetWidget->ay, _
        targetWidget->w, targetWidget->h
    targetWidget->render(targetWidget)
    backend_ResetClip
End Sub


Private Sub session_RenderWidgets( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    Dim As Integer workPage = backend_GetWorkPage()
    If workPage < 0 OrElse workPage > 1 Then
        workPage = 0
    End If

    /'
        Menus, dialogs, and keyboard focus can alter arbitrary registered
        controls, so those states retain omaGUI's complete ordered render.
        The normal editor desktop keeps identical toolbar pixels on each work
        page and refreshes only the scrollbars layered over the changing score.
    '/
    If session_IsModalOpen() <> 0 OrElse _
        session_VisibleDesktopMenuIndex() >= 0 OrElse _
        gui_GetFocus() <> 0 OrElse _
        gui_IsKeyboardNavigationActive() <> 0 Then
        gui_RenderAll
        session_WidgetPageValid(workPage) = 0
        Exit Sub
    End If

    Dim As ULongInt fingerprint = session_MainWidgetFingerprint( _
        screenWidth, screenHeight)
    If session_WidgetPageValid(workPage) = 0 OrElse _
        session_WidgetPageFingerprint(workPage) <> fingerprint Then
        gui_RenderAll
        session_WidgetPageFingerprint(workPage) = fingerprint
        session_WidgetPageValid(workPage) = -1
        Exit Sub
    End If

    session_RenderTopLevelWidget session_ScoreHorizontalScrollbar
    session_RenderTopLevelWidget session_ScoreVerticalScrollbar
End Sub


' -------------------------------------------------------------------------
' Playable performance keyboard
' -------------------------------------------------------------------------

Private Sub session_KeyboardAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_KeyboardWindow = 0 Then
        Exit Sub
    End If
    gui_AddGeneratedWidget child
    gui_SetParent child, session_KeyboardWindow
End Sub


Private Function session_KeyboardWhitePitch(ByVal whiteIndex As Integer) As Integer
    Return keyboardControls_WhitePitch(session_KeyboardBasePitch, whiteIndex)
End Function


Private Function session_KeyboardBlackPitch(ByVal blackIndex As Integer) As Integer
    Return keyboardControls_BlackPitch(session_KeyboardBasePitch, blackIndex)
End Function


Private Function session_KeyboardBlackLeft(ByVal blackIndex As Integer) As Integer
    Return keyboardControls_BlackLeft(blackIndex)
End Function


Private Function session_KeyboardKeyLabel(ByVal noteOffset As Integer) As String
    Return keyboardControls_KeyLabel(noteOffset)
End Function


Private Function session_KeyboardPcPitchHeld(ByVal pitch As Integer) As Integer
    Dim As Integer scanCodes(0 To 23) = _
        {FB.SC_Z, FB.SC_S, FB.SC_X, FB.SC_D, FB.SC_C, FB.SC_V, _
         FB.SC_G, FB.SC_B, FB.SC_H, FB.SC_N, FB.SC_J, FB.SC_M, _
         FB.SC_Q, FB.SC_2, FB.SC_W, FB.SC_3, FB.SC_E, FB.SC_R, _
         FB.SC_5, FB.SC_T, FB.SC_6, FB.SC_Y, FB.SC_7, FB.SC_U}
    For keyIndex As Integer = 0 To 23
        If session_StepEntryPitch(scanCodes(keyIndex)) = pitch AndAlso _
            input_KeyPressed(scanCodes(keyIndex)) <> 0 Then Return -1
    Next
    Return 0
End Function


Private Function session_KeyboardPitchAtPoint( _
    ByVal mouseX As Integer, _
    ByVal mouseY As Integer _
) As Integer
    If session_KeyboardWindow = 0 Then
        Return -1
    End If
    Dim As Integer localX = mouseX - session_KeyboardWindow->ax
    Dim As Integer localY = mouseY - session_KeyboardWindow->ay
    Return keyboardControls_PitchAtPoint(session_KeyboardBasePitch, localX, localY)
End Function


Private Sub session_DrawKeyboardWindow()
    If session_KeyboardWindow = 0 Then
        Exit Sub
    End If
    Dim As Integer pianoLeft = session_KeyboardWindow->ax + SESSION_KEYBOARD_LEFT
    Dim As Integer pianoTop = session_KeyboardWindow->ay + SESSION_KEYBOARD_TOP

    For whiteIndex As Integer = 0 To SESSION_KEYBOARD_WHITE_KEY_COUNT - 1
        Dim As Integer pitch = session_KeyboardWhitePitch(whiteIndex)
        Dim As ULong keyColor = session_ThemePalette.keyboardWhiteColor
        If pitch >= 0 AndAlso session_AuditionChannelForPitch(pitch) >= 0 Then _
            keyColor = session_ThemePalette.keyboardWhitePressedColor
        Dim As Integer keyLeft = pianoLeft + _
            whiteIndex * SESSION_KEYBOARD_WHITE_KEY_WIDTH
        backend_Rect keyLeft, pianoTop, SESSION_KEYBOARD_WHITE_KEY_WIDTH, _
            SESSION_KEYBOARD_WHITE_KEY_HEIGHT, keyColor, 1
        backend_Rect keyLeft, pianoTop, SESSION_KEYBOARD_WHITE_KEY_WIDTH, _
            SESSION_KEYBOARD_WHITE_KEY_HEIGHT, session_ThemePalette.borderColor, 0
        backend_PrintAligned keyLeft, pianoTop + _
            SESSION_KEYBOARD_WHITE_KEY_HEIGHT - 23, _
            SESSION_KEYBOARD_WHITE_KEY_WIDTH, 12, _
            session_ThemePalette.keyboardWhiteTextColor, _
            session_KeyboardKeyLabel(pitch - session_KeyboardBasePitch), _
            BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP
    Next

    For blackIndex As Integer = 0 To OSE_KEYBOARD_BLACK_KEY_COUNT - 1
        Dim As Integer pitch = session_KeyboardBlackPitch(blackIndex)
        Dim As ULong keyColor = session_ThemePalette.keyboardBlackColor
        If pitch >= 0 AndAlso session_AuditionChannelForPitch(pitch) >= 0 Then _
            keyColor = session_ThemePalette.keyboardBlackPressedColor
        Dim As Integer keyLeft = session_KeyboardWindow->ax + _
            session_KeyboardBlackLeft(blackIndex)
        backend_Rect keyLeft, pianoTop, SESSION_KEYBOARD_BLACK_KEY_WIDTH, _
            SESSION_KEYBOARD_BLACK_KEY_HEIGHT, keyColor, 1
        backend_Rect keyLeft, pianoTop, SESSION_KEYBOARD_BLACK_KEY_WIDTH, _
            SESSION_KEYBOARD_BLACK_KEY_HEIGHT, session_ThemePalette.shadowColor, 0
        backend_PrintAligned keyLeft, pianoTop + _
            SESSION_KEYBOARD_BLACK_KEY_HEIGHT - 20, _
            SESSION_KEYBOARD_BLACK_KEY_WIDTH, 12, _
            session_ThemePalette.keyboardBlackTextColor, _
            session_KeyboardKeyLabel(pitch - session_KeyboardBasePitch), _
            BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP
    Next
End Sub


Private Sub session_ProcessKeyboardMouse()
    If session_KeyboardWindow = 0 Then
        Exit Sub
    End If
    Dim As Integer mouseButtons = input_MouseButtons() And &H1
    Dim As Integer nextPitch = -1
    If mouseButtons <> 0 Then nextPitch = session_KeyboardPitchAtPoint( _
        input_MouseX(), input_MouseY())
    If nextPitch = session_KeyboardMousePitch Then
        session_KeyboardLastMouseButtons = mouseButtons
        Exit Sub
    End If

    Dim As ULongInt currentTick
    If session_LiveRecording <> 0 Then
        currentTick = session_LiveRecordingTick()
    End If
    Dim As Integer previousPitch = session_KeyboardMousePitch
    session_KeyboardMousePitch = nextPitch
    If previousPitch >= 0 AndAlso _
        session_KeyboardPcPitchHeld(previousPitch) = 0 Then
        If session_LiveRecording <> 0 Then
            If session_CloseLiveKeyboardNote(previousPitch, currentTick) <> 0 Then _
                session_Dirty = -1
        End If
        session_StopAuditionPitch previousPitch
    End If
    If nextPitch >= 0 Then
        session_StartAuditionPitch nextPitch
        If session_LiveRecording <> 0 Then _
            session_StartLiveKeyboardNote nextPitch, currentTick
    End If
    session_KeyboardLastMouseButtons = mouseButtons
End Sub


Private Sub session_CloseKeyboardWindow()
    If session_KeyboardWindow = 0 Then
        Exit Sub
    End If
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    session_StopAllAuditionNotes()
    session_ResetLiveKeyboardState()
    session_KeyboardMousePitch = -1
    Dim As String windowName = session_KeyboardWindow->name
    gui_RemoveWidget windowName
    gui_ClearModalRoot()
    session_KeyboardWindow = 0
End Sub


Public Sub session_OnKeyboardClose(ByVal source As Widget Ptr)
    If source = 0 Then
        Exit Sub
    End If
End Sub


Public Sub session_OnKeyboardRecord(ByVal source As Widget Ptr)
    If session_KeyboardWindow = 0 Then
        Exit Sub
    End If
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
        session_SetStatus "Performance keyboard recording stopped."
        Exit Sub
    End If
    session_BeginLiveRecording 0
End Sub


Public Sub session_OnKeyboardOctaveDown(ByVal source As Widget Ptr)
    If session_LiveRecording <> 0 Then
        session_SetStatus "Stop recording before changing the keyboard range."
        Exit Sub
    End If
    If session_KeyboardBasePitch <= 36 Then
        session_SetStatus "The performance keyboard is already at its lowest range."
        Exit Sub
    End If
    session_StopAllAuditionNotes()
    session_ResetLiveKeyboardState()
    session_KeyboardBasePitch -= 12
    session_SetStatus "Performance keyboard lowered one octave."
End Sub


Public Sub session_OnKeyboardOctaveUp(ByVal source As Widget Ptr)
    If session_LiveRecording <> 0 Then
        session_SetStatus "Stop recording before changing the keyboard range."
        Exit Sub
    End If
    If session_KeyboardBasePitch >= 84 Then
        session_SetStatus "The performance keyboard is already at its highest range."
        Exit Sub
    End If
    session_StopAllAuditionNotes()
    session_ResetLiveKeyboardState()
    session_KeyboardBasePitch += 12
    session_SetStatus "Performance keyboard raised one octave."
End Sub


Public Sub session_OnKeyboard(ByVal source As Widget Ptr)
    If session_KeyboardWindow <> 0 Then
        gui_BringToFront session_KeyboardWindow
        Exit Sub
    End If
    If session_IsModalOpen() <> 0 Then
        session_SetStatus "Close the current modal window first."
        Exit Sub
    End If
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As Integer windowX = (screenWidth - SESSION_KEYBOARD_WINDOW_WIDTH) \ 2
    Dim As Integer windowY = (screenHeight - SESSION_KEYBOARD_WINDOW_HEIGHT) \ 2
    If windowX < 0 Then
        windowX = 0
    End If
    If windowY < 0 Then
        windowY = 0
    End If
    session_KeyboardWindow = session_CreateEditorWindow( _
        "performance_keyboard", "Performance Keyboard", windowX, windowY, _
        SESSION_KEYBOARD_WINDOW_WIDTH, SESSION_KEYBOARD_WINDOW_HEIGHT)
    If session_KeyboardWindow = 0 Then
        session_SetStatus "Could not create the performance keyboard."
        Exit Sub
    End If
    gui_AddWidget session_KeyboardWindow
    subwindow_SetCloseHandler session_KeyboardWindow, @session_OnKeyboardClose
    session_KeyboardAddChild button_Create( _
        "keyboard_record", "Record / Stop", 16, 34, 120, 28, _
        @session_OnKeyboardRecord)
    session_KeyboardAddChild button_Create( _
        "keyboard_octave_down", "Octave -", 148, 34, 86, 28, _
        @session_OnKeyboardOctaveDown)
    session_KeyboardAddChild button_Create( _
        "keyboard_octave_up", "Octave +", 242, 34, 86, 28, _
        @session_OnKeyboardOctaveUp)
    session_KeyboardAddChild session_CreateEditorLabel( _
        "keyboard_hint", _
        "Play with the mouse or Z S X D C V G B H N J M / Q 2 W 3 E R 5 T 6 Y 7 U.", _
        16, 78)
    session_KeyboardAddChild session_CreateEditorLabel( _
        "keyboard_record_hint", _
        "Record appends real note lengths to the selected track. Octave buttons shift both input rows.", _
        16, 98)
    session_ResetLiveKeyboardState()
    session_StopAllAuditionNotes()
    gui_SetModalRoot session_KeyboardWindow
    session_SetStatus "Performance keyboard open."
End Sub


Private Sub session_ProcessKeyboardWindow()
    If session_KeyboardWindow = 0 Then
        Exit Sub
    End If
    If subwindow_CloseRequested(session_KeyboardWindow) <> 0 Then
        session_CloseKeyboardWindow()
        session_SetStatus "Performance keyboard closed."
        Exit Sub
    End If
    If session_LiveRecording = 0 Then
        session_ProcessPcPerformanceKeys 0
    End If
    session_ProcessKeyboardMouse()
End Sub


' -------------------------------------------------------------------------
' Playable General MIDI drum kit
' -------------------------------------------------------------------------

Private Sub session_DrumAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_DrumWindow = 0 Then
        Exit Sub
    End If
    gui_AddGeneratedWidget child
    gui_SetParent child, session_DrumWindow
End Sub


Private Sub session_DrumSurface( _
    ByRef surfaceX As Integer, _
    ByRef surfaceY As Integer, _
    ByRef surfaceWidth As Integer, _
    ByRef surfaceHeight As Integer _
)
    surfaceX = 0
    surfaceY = 0
    surfaceWidth = 0
    surfaceHeight = 0
    If session_DrumWindow = 0 Then
        Exit Sub
    End If
    surfaceX = session_DrumWindow->ax + SESSION_DRUM_SURFACE_LEFT
    surfaceY = session_DrumWindow->ay + SESSION_DRUM_SURFACE_TOP
    surfaceWidth = session_DrumWindow->w - SESSION_DRUM_SURFACE_LEFT - _
        SESSION_DRUM_SURFACE_RIGHT_MARGIN
    surfaceHeight = session_DrumWindow->h - SESSION_DRUM_SURFACE_TOP - _
        SESSION_DRUM_SURFACE_BOTTOM_MARGIN
End Sub


Private Function session_DrumPadAtPoint( _
    ByVal pointX As Integer, _
    ByVal pointY As Integer _
) As Integer
    Dim As Integer surfaceX
    Dim As Integer surfaceY
    Dim As Integer surfaceWidth
    Dim As Integer surfaceHeight
    session_DrumSurface surfaceX, surfaceY, surfaceWidth, surfaceHeight
    Return drumKit_PadAtPoint(pointX, pointY, surfaceX, surfaceY, _
        surfaceWidth, surfaceHeight)
End Function


Private Sub session_UpdateDrumVelocityButtons()
    Dim As Widget Ptr velocityButtons(0 To 2) = { _
        session_DrumSoftButton, session_DrumMediumButton, _
        session_DrumHardButton _
    }
    Dim As Integer velocities(0 To 2) = { _
        OSE_DRUM_VELOCITY_SOFT, OSE_DRUM_VELOCITY_MEDIUM, _
        OSE_DRUM_VELOCITY_HARD _
    }
    For buttonIndex As Integer = 0 To 2
        If velocityButtons(buttonIndex) = 0 OrElse _
            velocityButtons(buttonIndex)->data = 0 Then Continue For
        Dim As String marker = "[ ] "
        If velocities(buttonIndex) = session_DrumVelocity Then
            marker = "[x] "
        End If
        Cast(ButtonData Ptr, velocityButtons(buttonIndex)->data)->text = _
            marker + drumKit_VelocityName(velocities(buttonIndex))
    Next
End Sub


Private Sub session_SetDrumVelocity(ByVal velocity As Integer)
    If drumKit_VelocityName(velocity) = "" Then
        Exit Sub
    End If
    session_DrumVelocity = velocity
    session_UpdateDrumVelocityButtons()
    session_SetStatus "Drum velocity: " + drumKit_VelocityName(velocity) + _
        " (" + LTrim(Str(velocity)) + ")."
End Sub


Public Sub session_OnDrumSoft(ByVal source As Widget Ptr)
    session_SetDrumVelocity OSE_DRUM_VELOCITY_SOFT
End Sub


Public Sub session_OnDrumMedium(ByVal source As Widget Ptr)
    session_SetDrumVelocity OSE_DRUM_VELOCITY_MEDIUM
End Sub


Public Sub session_OnDrumHard(ByVal source As Widget Ptr)
    session_SetDrumVelocity OSE_DRUM_VELOCITY_HARD
End Sub


Private Sub session_DrawDrumWindow()
    If session_DrumWindow = 0 Then
        Exit Sub
    End If
    Const pitchLabelBottomInset As Integer = 27
    Dim As Integer surfaceX
    Dim As Integer surfaceY
    Dim As Integer surfaceWidth
    Dim As Integer surfaceHeight
    session_DrumSurface surfaceX, surfaceY, surfaceWidth, surfaceHeight

    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        Dim As OseDrumPadRectangle padRectangle
        drumKit_PadRectangle padIndex, surfaceX, surfaceY, surfaceWidth, _
            surfaceHeight, padRectangle
        If padRectangle.width <= 0 OrElse padRectangle.height <= 0 Then _
            Continue For

        Dim As ULong padColor
        Select Case padIndex \ OSE_DRUM_COLUMN_COUNT
            Case 0
                padColor = session_ThemePalette.alternatePanelColor
            Case 1
                padColor = session_ThemePalette.panelColor
            Case Else
                padColor = session_ThemePalette.insetColor
        End Select
        Dim As ULong padTextColor = session_ThemePalette.textColor
        Dim As ULong stripeColor = session_ThemePalette.accentColor
        Dim As Integer contentOffset
        If session_DrumPadHeld(padIndex) <> 0 Then
            padColor = session_ThemePalette.selectedPanelColor
            padTextColor = session_ThemePalette.selectedTextColor
            stripeColor = session_ThemePalette.accentBrightColor
            contentOffset = 2
        End If

        backend_Rect padRectangle.x, padRectangle.y, padRectangle.width, _
            padRectangle.height, padColor, 1
        backend_Rect padRectangle.x, padRectangle.y, padRectangle.width, _
            padRectangle.height, session_ThemePalette.borderColor, 0
        backend_Rect padRectangle.x + 1, padRectangle.y + 1, _
            padRectangle.width - 2, 6, stripeColor, 1

        Dim As Integer keyBoxWidth = 30
        Dim As Integer keyBoxHeight = 24
        Dim As Integer keyBoxX = padRectangle.x + padRectangle.width - _
            keyBoxWidth - 10 + contentOffset
        Dim As Integer keyBoxY = padRectangle.y + 13 + contentOffset
        backend_Rect keyBoxX, keyBoxY, keyBoxWidth, keyBoxHeight, _
            session_ThemePalette.headerColor, 1
        backend_Rect keyBoxX, keyBoxY, keyBoxWidth, keyBoxHeight, _
            stripeColor, 0
        backend_PrintAligned keyBoxX, keyBoxY, keyBoxWidth, keyBoxHeight, _
            padTextColor, drumKit_KeyLabel(padIndex), BACKEND_FONT_DEFAULT, _
            BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE

        backend_PrintAligned padRectangle.x + 10 + contentOffset, _
            padRectangle.y + padRectangle.height \ 2 - 14 + contentOffset, _
            padRectangle.width - 20, 22, padTextColor, _
            drumKit_Name(padIndex), BACKEND_FONT_DEFAULT, _
            BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE
        backend_PrintAligned padRectangle.x + 10 + contentOffset, _
            padRectangle.y + padRectangle.height - pitchLabelBottomInset + _
                contentOffset, _
            padRectangle.width - 20, 16, _
            session_ThemePalette.mutedTextColor, _
            "GM " + LTrim(Str(drumKit_Pitch(padIndex))), _
            BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE
    Next
End Sub


Private Sub session_TriggerDrumPad(ByVal padIndex As Integer)
    Dim As Integer pitch = drumKit_Pitch(padIndex)
    If pitch < 0 Then
        Exit Sub
    End If
    Const drumChannel As Integer = 9
    Dim As OsePlaybackMixValues drumMix
    playbackMix_Calculate drumMix, _
        session_Summary.channelVolume(drumChannel), _
        session_Summary.channelExpression(drumChannel), _
        session_Summary.channelPan(drumChannel), session_DrumVelocity, _
        session_MasterVolume, session_ChannelIsAudible(drumChannel)
    Dim As OseSoftwareSynthPlayOptions drumOptions
    drumOptions.bankNumber = 128
    drumOptions.fallbackVoiceChannel = -1
    softwareSynth_PlayMidiNote drumChannel, pitch, _
        session_Summary.channelProgram(drumChannel), 8192, 0.35, drumMix, _
        drumOptions
    mixerMeter_Trigger session_MixerMeter, drumChannel, _
        CSng(session_DrumVelocity) / 127.0, 0.35

    /'
        Percussion voices are one-shots. An immediate note-off is valid for
        General MIDI drums and prevents a connected endpoint from retaining a
        note if it uses a non-percussion patch on channel ten.
    '/
    If midiOutput_IsOpen() <> 0 Then
        midiOutput_Send &H99, pitch, session_DrumVelocity
        midiOutput_Send &H89, pitch, 0
    End If
End Sub


Private Function session_StartLiveDrumNote( _
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

    Const drumChannel As Integer = 9
    Dim As Integer addedNote = midi_AddEditableNote( _
        session_Summary, session_SelectedTrack, currentTick, 1, pitch, _
        drumChannel, session_DrumVelocity)
    If addedNote < 0 Then
        session_CancelMidiEdit()
        session_SetStatus "Drum recording stopped: note limit reached."
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


Private Sub session_ResetDrumPadState()
    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        session_DrumPadHeld(padIndex) = 0
    Next
End Sub


Private Sub session_ProcessDrumInput()
    If session_DrumWindow = 0 Then
        Exit Sub
    End If
    Dim As Integer nextHeld(0 To OSE_DRUM_PAD_COUNT - 1)
    Dim As Integer scanCodes(0 To OSE_DRUM_PAD_COUNT - 1) = { _
        FB.SC_1, FB.SC_2, FB.SC_3, FB.SC_4, _
        FB.SC_Q, FB.SC_W, FB.SC_E, FB.SC_R, _
        FB.SC_A, FB.SC_S, FB.SC_D, FB.SC_F _
    }

    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        If input_KeyPressed(scanCodes(padIndex)) <> 0 Then _
            nextHeld(padIndex) = -1
    Next

    Dim As Integer touchCount = input_TouchCount()
    If touchCount > INPUT_TOUCH_CAPACITY Then
        touchCount = INPUT_TOUCH_CAPACITY
    End If
    For contactIndex As Integer = 0 To touchCount - 1
        Dim As Integer touchX
        Dim As Integer touchY
        Dim As Integer touchId
        If input_Touch(contactIndex, touchX, touchY, touchId) <> 0 Then
            Dim As Integer touchedPad = session_DrumPadAtPoint(touchX, touchY)
            If touchedPad >= 0 Then
                nextHeld(touchedPad) = -1
            End If
        End If
    Next

    ' A native touch is also the compatibility mouse used by omaGUI. Ignore
    ' that duplicate while contacts are available, but keep ordinary mice and
    ' styli working through the same pad map.
    If touchCount = 0 AndAlso (input_MouseButtons() And &H1) <> 0 Then
        Dim As Integer mousePad = session_DrumPadAtPoint( _
            input_MouseX(), input_MouseY())
        If mousePad >= 0 Then
            nextHeld(mousePad) = -1
        End If
    End If

    Dim As ULongInt currentTick
    If session_LiveRecording <> 0 Then
        currentTick = session_LiveRecordingTick()
    End If
    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        Dim As Integer pitch = drumKit_Pitch(padIndex)
        If nextHeld(padIndex) <> 0 AndAlso _
            session_DrumPadHeld(padIndex) = 0 Then
            session_TriggerDrumPad padIndex
            If session_LiveRecording <> 0 Then _
                session_StartLiveDrumNote pitch, currentTick
        ElseIf nextHeld(padIndex) = 0 AndAlso _
            session_DrumPadHeld(padIndex) <> 0 Then
            If session_LiveRecording <> 0 Then
                If session_CloseLiveKeyboardNote(pitch, currentTick) <> 0 Then _
                    session_Dirty = -1
            End If
        End If
        session_DrumPadHeld(padIndex) = nextHeld(padIndex)
    Next
End Sub


Private Sub session_CloseDrumWindow()
    If session_DrumWindow = 0 Then
        Exit Sub
    End If
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    session_ResetDrumPadState()
    Dim As String windowName = session_DrumWindow->name
    gui_RemoveWidget windowName
    gui_ClearModalRoot()
    session_DrumWindow = 0
    session_DrumSoftButton = 0
    session_DrumMediumButton = 0
    session_DrumHardButton = 0
End Sub


Public Sub session_OnDrumClose(ByVal source As Widget Ptr)
    If source = 0 Then
        Exit Sub
    End If
End Sub


Public Sub session_OnDrumRecord(ByVal source As Widget Ptr)
    If session_DrumWindow = 0 Then
        Exit Sub
    End If
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
        session_SetStatus "Drum recording stopped."
        Exit Sub
    End If
    If session_BeginLiveRecording(0) <> 0 Then
        session_SetStatus "Drum recording on track " + _
            Str(session_SelectedTrack + 1) + ". Strike a pad to add channel 10 notes."
    End If
End Sub


Public Sub session_OnDrumKit(ByVal source As Widget Ptr)
    If session_DrumWindow <> 0 Then
        gui_BringToFront session_DrumWindow
        Exit Sub
    End If
    If session_IsModalOpen() <> 0 Then
        session_SetStatus "Close the current modal window first."
        Exit Sub
    End If
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As Integer windowWidth = screenWidth - 24
    Dim As Integer windowHeight = screenHeight - 24
    If windowWidth > SESSION_DRUM_WINDOW_MAXIMUM_WIDTH Then _
        windowWidth = SESSION_DRUM_WINDOW_MAXIMUM_WIDTH
    If windowHeight > SESSION_DRUM_WINDOW_MAXIMUM_HEIGHT Then _
        windowHeight = SESSION_DRUM_WINDOW_MAXIMUM_HEIGHT
    If windowWidth < SESSION_DRUM_WINDOW_MINIMUM_WIDTH Then
        windowWidth = screenWidth
    End If
    If windowHeight < SESSION_DRUM_WINDOW_MINIMUM_HEIGHT Then _
        windowHeight = screenHeight
    Dim As Integer windowX = (screenWidth - windowWidth) \ 2
    Dim As Integer windowY = (screenHeight - windowHeight) \ 2
    If windowX < 0 Then
        windowX = 0
    End If
    If windowY < 0 Then
        windowY = 0
    End If

    session_DrumWindow = session_CreateEditorWindow( _
        "drum_kit", "Drum Kit", windowX, windowY, windowWidth, windowHeight)
    If session_DrumWindow = 0 Then
        session_SetStatus "Could not create the drum kit."
        Exit Sub
    End If
    gui_AddWidget session_DrumWindow
    subwindow_SetCloseHandler session_DrumWindow, @session_OnDrumClose
    session_DrumAddChild button_Create( _
        "drum_record", "Record / Stop", 16, 36, 132, 44, _
        @session_OnDrumRecord)
    session_DrumSoftButton = button_Create( _
        "drum_soft", "Soft", 162, 36, 98, 44, @session_OnDrumSoft)
    session_DrumAddChild session_DrumSoftButton
    session_DrumMediumButton = button_Create( _
        "drum_medium", "Medium", 270, 36, 108, 44, @session_OnDrumMedium)
    session_DrumAddChild session_DrumMediumButton
    session_DrumHardButton = button_Create( _
        "drum_hard", "Hard", 388, 36, 98, 44, @session_OnDrumHard)
    session_DrumAddChild session_DrumHardButton
    session_DrumAddChild button_Create( _
        "drum_machine_open", "Beat phrases...", 498, 36, 160, 44, @session_OnDrumMachine)
    session_DrumAddChild session_CreateEditorLabel( _
        "drum_hint", _
        "Strike pads with mouse, multitouch, or the matching 1-4 / Q-R / A-F keys.", _
        16, 94)
    session_DrumAddChild session_CreateEditorLabel( _
        "drum_record_hint", _
        "Record appends each strike to the selected track as General MIDI channel 10.", _
        16, 116)
    session_ResetDrumPadState()
    session_UpdateDrumVelocityButtons()
    gui_SetModalRoot session_DrumWindow
    session_SetStatus "Drum kit open."
End Sub


Private Sub session_ProcessDrumWindow()
    If session_DrumWindow = 0 Then
        Exit Sub
    End If
    If session_PhraseOpenRequested <> 0 Then
        session_PhraseOpenRequested = 0
        session_CloseDrumWindow()
        session_OnDrumMachine 0
        Exit Sub
    End If
    If subwindow_CloseRequested(session_DrumWindow) <> 0 Then
        session_CloseDrumWindow()
        session_SetStatus "Drum kit closed."
        Exit Sub
    End If
    session_ProcessDrumInput()
End Sub


' -------------------------------------------------------------------------
' Drum-machine phrase editor
' -------------------------------------------------------------------------

Private Sub session_PhraseMessage(ByVal messageText As String)
    If session_PhraseStatus <> 0 AndAlso session_PhraseStatus->data <> 0 Then _
        Cast(LabelData Ptr, session_PhraseStatus->data)->text = messageText
    session_SetStatus messageText
End Sub

Private Sub session_PhraseAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_PhraseWindow = 0 Then
        Exit Sub
    End If
    gui_AddGeneratedWidget child
    gui_SetParent child, session_PhraseWindow
End Sub

Private Function session_PhraseReadFields() As Integer
    Dim As ULongInt beats
    Dim As ULongInt unitValue
    Dim As ULongInt divisions
    If numericText_ParseUnsigned(textbox_GetText(session_PhraseBeatsBox), beats, 16) = 0 OrElse _
        numericText_ParseUnsigned(textbox_GetText(session_PhraseUnitBox), unitValue, 32) = 0 OrElse _
        numericText_ParseUnsigned(textbox_GetText(session_PhraseDivisionBox), divisions, 4) = 0 OrElse _
        beats < 1 OrElse unitValue < 1 OrElse divisions < 1 Then
        session_PhraseMessage "Use 1-16 beats, a denominator of 1-32, and 1-4 steps per beat."
        Return 0
    End If
    Dim As String title = Trim(textbox_GetText(session_PhraseNameBox))
    If Len(title) < 1 OrElse Len(title) > OSE_DRUM_PHRASE_NAME_LENGTH OrElse Instr(title, "|") > 0 Then
        session_PhraseMessage "Name needs 1-32 characters and cannot contain |."
        Return 0
    End If
    For charIndex As Integer = 1 To Len(title)
        If Asc(title, charIndex) < 32 Then
            Return 0
        End If
    Next
    If session_Phrase.numerator <> beats OrElse session_Phrase.denominator <> unitValue OrElse _
        session_Phrase.subdivisions <> divisions OrElse session_Phrase.title <> title Then
        session_Phrase.numerator = beats
        session_Phrase.denominator = unitValue
        session_Phrase.subdivisions = divisions
        session_Phrase.title = title
        session_PhraseChanged = -1
        session_PhraseLooping = 0
        session_PhraseLoopStep = -1
    End If
    Return -1
End Function

Private Sub session_PhraseWriteFields()
    textbox_SetText session_PhraseNameBox, session_Phrase.title, -1
    textbox_SetText session_PhraseBeatsBox, LTrim(Str(session_Phrase.numerator)), -1
    textbox_SetText session_PhraseUnitBox, LTrim(Str(session_Phrase.denominator)), -1
    textbox_SetText session_PhraseDivisionBox, LTrim(Str(session_Phrase.subdivisions)), -1
End Sub

Private Function session_PhraseSave() As Integer
    If session_PhraseReadFields() = 0 Then
        Return 0
    End If
    If session_PhraseChanged = 0 Then
        Return -1
    End If
    If session_BeginMidiEdit() = 0 Then
        Return 0
    End If
    If drumPhrase_Store(session_Summary, session_PhraseSlot, session_Phrase) = 0 Then
        session_CancelMidiEdit()
        session_PhraseMessage "Could not store this phrase."
        Return 0
    End If
    If session_CommitMidiEdit() = 0 Then
        Return 0
    End If
    session_Dirty = -1
    session_PhraseChanged = 0
    session_PhraseMessage "Phrase stored in the song. Save the MIDI file to keep it on disk."
    Return -1
End Function

Private Sub session_PhraseRefreshGrid()
    If session_PhraseWindow = 0 Then
        Exit Sub
    End If
    Dim As Integer steps = session_Phrase.numerator * session_Phrase.subdivisions
    If session_PhraseFirstStep >= steps Then
        session_PhraseFirstStep = 0
    End If
    For rowIndex As Integer = 0 To session_PhraseVisibleRows - 1
        Dim As Integer padIndex = drumPhrase_PadForRow(session_PhraseFirstRow + rowIndex)
        session_PhraseRows(rowIndex)->visible = IIf(padIndex >= 0, -1, 0)
        If padIndex >= 0 Then _
            Cast(ButtonData Ptr, session_PhraseRows(rowIndex)->data)->text = drumKit_Name(padIndex)
        For columnIndex As Integer = 0 To session_PhraseVisibleColumns - 1
            Dim As Widget Ptr cell = session_PhraseCells(rowIndex, columnIndex)
            cell->visible = IIf(padIndex >= 0 AndAlso _
                session_PhraseFirstStep + columnIndex < steps, -1, 0)
        Next
    Next
    For columnIndex As Integer = 0 To session_PhraseVisibleColumns - 1
        Dim As Integer stepIndex = session_PhraseFirstStep + columnIndex
        session_PhraseColumns(columnIndex)->visible = IIf(stepIndex < steps, -1, 0)
        Dim As String caption = LTrim(Str(stepIndex \ session_Phrase.subdivisions + 1))
        If stepIndex Mod session_Phrase.subdivisions <> 0 Then caption = "." + _
            LTrim(Str(stepIndex Mod session_Phrase.subdivisions + 1))
        Cast(LabelData Ptr, session_PhraseColumns(columnIndex)->data)->text = caption
    Next
    Dim As ULongInt tick
    If numericText_ParseUnsigned(textbox_GetText(session_PhraseTickBox), tick, OSE_MAX_MIDI_TICK) = 0 Then
        tick = 0
    End If
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick(tick)
    Dim As String songMeter = "4/4"
    If signatureIndex >= 0 Then songMeter = _
        LTrim(Str(session_Summary.timeSignatureMap(signatureIndex).numerator)) + "/" + _
        LTrim(Str(1 Shl session_Summary.timeSignatureMap(signatureIndex).denominatorPower))
    Cast(LabelData Ptr, session_PhraseInfo->data)->text = _
        "Slot " + LTrim(Str(session_PhraseSlot + 1)) + "/16   Song: " + songMeter + _
        "   Drums: " + LTrim(Str(session_Phrase.numerator)) + "/" + LTrim(Str(session_Phrase.denominator)) + _
        "   Steps " + LTrim(Str(session_PhraseFirstStep + 1)) + "-" + _
        LTrim(Str(IIf(session_PhraseFirstStep + session_PhraseVisibleColumns < steps, _
            session_PhraseFirstStep + session_PhraseVisibleColumns, steps))) + "/" + LTrim(Str(steps)) + _
        "   At " + session_MusicalPositionText(tick)
    Dim As Widget Ptr loopButton = gui_FindWidget("phrase_loop")
    If loopButton <> 0 AndAlso loopButton->data <> 0 Then _
        Cast(ButtonData Ptr, loopButton->data)->text = IIf(session_PhraseLooping <> 0, "Stop loop", "Loop phrase")
End Sub

Private Function session_PhraseCellIndex(ByVal source As Widget Ptr) As Integer
    For rowIndex As Integer = 0 To session_PhraseVisibleRows - 1
        For columnIndex As Integer = 0 To session_PhraseVisibleColumns - 1
            If session_PhraseCells(rowIndex, columnIndex) = source Then
                Return rowIndex * 16 + columnIndex
            End If
        Next
    Next
    Return -1
End Function

Private Sub session_RenderPhraseCell(ByVal source As Widget Ptr)
    Dim As Integer cellIndex = session_PhraseCellIndex(source)
    If cellIndex < 0 Then
        Exit Sub
    End If
    Dim As Integer padIndex = drumPhrase_PadForRow(session_PhraseFirstRow + cellIndex \ 16)
    Dim As Integer stepIndex = session_PhraseFirstStep + cellIndex Mod 16
    If padIndex < 0 OrElse stepIndex >= OSE_DRUM_PHRASE_STEPS Then
        Exit Sub
    End If
    Dim As Integer velocity = session_Phrase.velocity(padIndex, stepIndex)
    Dim As ULong fillColor = session_ThemePalette.insetColor
    Dim As ULong textColor = session_ThemePalette.textColor
    Dim As String caption = "-"
    If velocity > 0 Then
        fillColor = session_ThemePalette.accentColor
        textColor = session_ThemePalette.selectedTextColor
        Select Case velocity
            Case OSE_DRUM_VELOCITY_SOFT
                caption = "s"
            Case OSE_DRUM_VELOCITY_MEDIUM
                caption = "M"
            Case Else
                caption = "H"
        End Select
    ElseIf stepIndex Mod session_Phrase.subdivisions = 0 Then
        fillColor = session_ThemePalette.alternatePanelColor
    End If
    backend_Rect source->ax, source->ay, source->w, source->h, fillColor, 1
    Dim As ULong borderColor = session_ThemePalette.borderColor
    If source->has_focus <> 0 OrElse _
        (session_PhraseLooping <> 0 AndAlso session_PhraseLoopStep = stepIndex) Then _
        borderColor = session_ThemePalette.accentBrightColor
    backend_Rect source->ax, source->ay, source->w, source->h, borderColor, 0
    backend_PrintAligned source->ax, source->ay, source->w, source->h, _
        textColor, caption, BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE
End Sub

Public Sub session_OnPhraseCell(ByVal source As Widget Ptr)
    session_PhraseClearArmed = 0
    Dim As Integer cellIndex = session_PhraseCellIndex(source)
    If cellIndex < 0 OrElse session_PhraseReadFields() = 0 Then
        Exit Sub
    End If
    Dim As Integer padIndex = drumPhrase_PadForRow(session_PhraseFirstRow + cellIndex \ 16)
    Dim As Integer stepIndex = session_PhraseFirstStep + cellIndex Mod 16
    If padIndex < 0 OrElse _
        stepIndex >= session_Phrase.numerator * session_Phrase.subdivisions Then Exit Sub
    If session_Phrase.velocity(padIndex, stepIndex) = 0 Then
        session_Phrase.velocity(padIndex, stepIndex) = session_DrumVelocity
        session_TriggerDrumPad padIndex
    Else
        session_Phrase.velocity(padIndex, stepIndex) = 0
    End If
    session_PhraseChanged = -1
    session_PhraseRefreshGrid()
End Sub

Private Sub session_PhraseInsert()
    If session_PhraseReadFields() = 0 Then
        Exit Sub
    End If
    Dim As ULongInt tick
    Dim As ULongInt repeats
    Dim As ULongInt endTick
    If numericText_ParseUnsigned(textbox_GetText(session_PhraseTickBox), tick, OSE_MAX_MIDI_TICK) = 0 OrElse _
        numericText_ParseUnsigned(textbox_GetText(session_PhraseRepeatBox), repeats, OSE_DRUM_PHRASE_MAX_REPEATS) = 0 OrElse repeats < 1 Then
        session_PhraseMessage "Use a valid start tick and 1-64 repeats."
        Exit Sub
    End If
    session_PhraseLooping = 0
    session_PhraseLoopStep = -1
    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If
    ' A dedicated track leaves melodic parts intact, even when the selected
    ' score track contains a mixture of channels. MIDI channel 10 is index 9.
    Dim As Integer drumTrack = -1
    For trackIndex As Integer = 0 To session_Summary.trackCount - 1
        If session_Summary.tracks(trackIndex).name = "Drum phrases" Then
            drumTrack = trackIndex
            Exit For
        End If
    Next
    If drumTrack < 0 Then
        drumTrack = midi_AddTrack(session_Summary)
        If drumTrack >= 0 Then
            If midi_SetTrackName(session_Summary, drumTrack, "Drum phrases") = 0 Then
                drumTrack = -1
            End If
        End If
    End If
    Dim As Integer inserted = 0
    If drumTrack >= 0 Then
        inserted = drumPhrase_Insert(session_Summary, session_Phrase, drumTrack, tick, CInt(repeats), endTick)
    End If
    If inserted <> 0 Then
        inserted = drumPhrase_Store(session_Summary, session_PhraseSlot, session_Phrase)
    End If
    If inserted <> 0 Then
        Dim As String marker = "Drums: " + session_Phrase.title + " (" + _
            LTrim(Str(session_Phrase.numerator)) + "/" + LTrim(Str(session_Phrase.denominator)) + ") x" + LTrim(Str(repeats))
        If midi_AddTextEvent(session_Summary, drumTrack, tick, 6, marker) < 0 Then
            inserted = 0
        End If
        ' Preserve the phrase's trailing silence in the document duration.
        If midi_AddTextEvent(session_Summary, drumTrack, endTick, 6, "Drums end: " + session_Phrase.title) < 0 Then
            inserted = 0
        End If
    End If
    If inserted = 0 Then
        session_CancelMidiEdit()
        session_PhraseMessage "Could not insert: check for an empty phrase, tick resolution or song limits."
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If
    session_Dirty = -1
    session_PhraseChanged = 0
    session_SelectedTrack = drumTrack
    session_RefreshAfterMidiHistory()
    session_StepEntryTick = endTick
    textbox_SetText session_PhraseTickBox, LTrim(Str(endTick)), -1
    session_PhraseRefreshGrid()
    session_PhraseMessage "Inserted on channel 10. Start tick advanced for the next phrase. Undo removes the placement."
End Sub

Private Sub session_ClosePhraseWindow()
    If session_PhraseWindow = 0 Then
        Exit Sub
    End If
    session_PhraseLooping = 0
    session_PhraseLoopStep = -1
    If session_PhraseSave() = 0 Then
        subwindow_Reopen session_PhraseWindow
        Exit Sub
    End If
    gui_RemoveWidget session_PhraseWindow->name
    gui_ClearModalRoot()
    session_PhraseWindow = 0
    session_PhraseStatus = 0
    session_SetStatus "Drum machine closed. Phrases are kept with the song."
End Sub

Public Sub session_OnPhraseAction(ByVal source As Widget Ptr)
    If source = 0 OrElse session_PhraseWindow = 0 Then
        Exit Sub
    End If
    If source->name <> "phrase_clear" Then
        session_PhraseClearArmed = 0
    End If
    Select Case source->name
        Case "phrase_at_view"
            textbox_SetText session_PhraseTickBox, LTrim(Str(session_ViewStartTick)), -1
            session_PhraseMessage "Placement set to the left edge of the score."
        Case "phrase_at_end"
            textbox_SetText session_PhraseTickBox, LTrim(Str(session_Summary.durationTicks)), -1
            session_PhraseMessage "Placement set to the end of the song."
        Case "phrase_starter"
            If session_PhraseSave() = 0 Then
                Exit Sub
            End If
            Dim As OseDrumPhrase existingPhrase
            Dim As Integer emptySlot = -1
            For slotIndex As Integer = 0 To OSE_DRUM_PHRASE_COUNT - 1
                If drumPhrase_Load(slotIndex, existingPhrase) = 0 Then
                    emptySlot = slotIndex
                    Exit For
                End If
            Next
            If emptySlot < 0 Then
                session_PhraseMessage "All 16 slots are used. Edit an existing phrase."
                Exit Sub
            End If
            session_PhraseSlot = emptySlot
            drumPhrase_Reset session_Phrase, emptySlot
            session_Phrase.title = "Basic beat " + LTrim(Str(emptySlot + 1))
            ' Straight eighth-note hats with kick on 1/3 and snare on 2/4.
            ' Use the shared row map so kit storage order remains private.
            For stepIndex As Integer = 0 To 14 Step 2
                session_Phrase.velocity(drumPhrase_PadForRow(2), stepIndex) = OSE_DRUM_VELOCITY_SOFT
            Next
            session_Phrase.velocity(drumPhrase_PadForRow(0), 0) = OSE_DRUM_VELOCITY_HARD
            session_Phrase.velocity(drumPhrase_PadForRow(0), 8) = OSE_DRUM_VELOCITY_HARD
            session_Phrase.velocity(drumPhrase_PadForRow(1), 4) = OSE_DRUM_VELOCITY_MEDIUM
            session_Phrase.velocity(drumPhrase_PadForRow(1), 12) = OSE_DRUM_VELOCITY_MEDIUM
            session_PhraseChanged = -1
            session_PhraseFirstRow = 0
            session_PhraseFirstStep = 0
            session_PhraseLooping = 0
            session_PhraseLoopStep = -1
            session_PhraseWriteFields()
            session_PhraseMessage "New 4/4 starter beat. Loop to listen, edit cells, then Insert into song."
        Case "phrase_save"
            session_PhraseSave()
        Case "phrase_song_meter"
            session_PhraseSongMeterRequested = -1
            Exit Sub
        Case "phrase_insert"
            session_PhraseInsert()
        Case "phrase_apply"
            If session_PhraseReadFields() <> 0 Then
                session_PhraseMessage "Drum meter applied. Hidden steps are retained when shortening a phrase."
            End If
        Case "phrase_velocity"
            Select Case session_DrumVelocity
                Case OSE_DRUM_VELOCITY_SOFT
                    session_DrumVelocity = OSE_DRUM_VELOCITY_MEDIUM
                Case OSE_DRUM_VELOCITY_MEDIUM
                    session_DrumVelocity = OSE_DRUM_VELOCITY_HARD
                Case Else
                    session_DrumVelocity = OSE_DRUM_VELOCITY_SOFT
            End Select
            Cast(ButtonData Ptr, source->data)->text = drumKit_VelocityName(session_DrumVelocity)
        Case "phrase_prev", "phrase_next", "phrase_copy"
            If session_PhraseSave() = 0 Then
                Exit Sub
            End If
            Dim As Integer nextSlot = (session_PhraseSlot + 1) Mod OSE_DRUM_PHRASE_COUNT
            If source->name = "phrase_prev" Then
                nextSlot = (session_PhraseSlot + OSE_DRUM_PHRASE_COUNT - 1) Mod OSE_DRUM_PHRASE_COUNT
            End If
            If source->name = "phrase_copy" Then
                ' Copy goes to an unused slot, so it cannot silently replace a beat.
                Dim As OseDrumPhrase existingPhrase
                Dim As Integer foundSlot = -1
                For offset As Integer = 1 To OSE_DRUM_PHRASE_COUNT - 1
                    nextSlot = (session_PhraseSlot + offset) Mod OSE_DRUM_PHRASE_COUNT
                    If drumPhrase_Load(nextSlot, existingPhrase) = 0 Then
                        foundSlot = nextSlot
                        Exit For
                    End If
                Next
                If foundSlot < 0 Then
                    session_PhraseMessage "All 16 phrase slots are in use."
                    Exit Sub
                End If
                session_Phrase.title = Left(session_Phrase.title, OSE_DRUM_PHRASE_NAME_LENGTH - 5) + " copy"
                session_PhraseChanged = -1
            Else
                drumPhrase_Load nextSlot, session_Phrase
                session_PhraseChanged = 0
            End If
            session_PhraseSlot = nextSlot
            session_PhraseLooping = 0
            session_PhraseLoopStep = -1
            session_PhraseFirstStep = 0
            session_PhraseWriteFields()
        Case "phrase_clear"
            If session_PhraseClearArmed = 0 Then
                session_PhraseClearArmed = -1
                session_PhraseMessage "Clear this phrase? Click Clear again to remove its hits."
                Exit Sub
            End If
            session_PhraseClearArmed = 0
            For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
                For stepIndex As Integer = 0 To OSE_DRUM_PHRASE_STEPS - 1
                    session_Phrase.velocity(padIndex, stepIndex) = 0
                Next
            Next
            session_PhraseChanged = -1
        Case "phrase_steps_prev"
            session_PhraseFirstStep -= session_PhraseVisibleColumns
            If session_PhraseFirstStep < 0 Then
                session_PhraseFirstStep = 0
            End If
        Case "phrase_steps_next"
            If session_PhraseFirstStep + session_PhraseVisibleColumns < session_Phrase.numerator * session_Phrase.subdivisions Then _
                session_PhraseFirstStep += session_PhraseVisibleColumns
        Case "phrase_rows"
            session_PhraseFirstRow += session_PhraseVisibleRows
            If session_PhraseFirstRow >= OSE_DRUM_PAD_COUNT Then
                session_PhraseFirstRow = 0
            End If
        Case "phrase_loop"
            If session_PhraseLooping <> 0 Then
                session_PhraseLooping = 0
                session_PhraseLoopStep = -1
            ElseIf session_PhraseReadFields() <> 0 Then
                If session_Summary.division * 4 < session_Phrase.denominator * session_Phrase.subdivisions Then
                    session_PhraseMessage "This song's tick resolution is too small for the selected grid."
                    Exit Sub
                End If
                session_PhraseLooping = -1
                session_PhraseLoopStep = -1
                session_PhraseLoopClock = Timer
                session_PhraseLoopElapsed = 0
            End If
        Case Else
            For rowIndex As Integer = 0 To session_PhraseVisibleRows - 1
                If source = session_PhraseRows(rowIndex) Then _
                    session_TriggerDrumPad drumPhrase_PadForRow(session_PhraseFirstRow + rowIndex)
            Next
    End Select
    session_PhraseRefreshGrid()
End Sub

Public Sub session_OnDrumMachine(ByVal source As Widget Ptr)
    If source <> 0 AndAlso source->name = "drum_machine_open" Then
        session_PhraseOpenRequested = -1
        Exit Sub
    End If
    If session_PhraseWindow <> 0 Then
        gui_BringToFront session_PhraseWindow
        Exit Sub
    End If
    If session_IsModalOpen() <> 0 Then
        session_SetStatus "Close the current modal window first."
        Exit Sub
    End If
    If session_Summary.division < 1 OrElse session_Summary.division > 32767 Then
        session_SetStatus "Drum phrases require a song with musical tick timing."
        Exit Sub
    End If
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    session_StopPlayback()
    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As Integer windowWidth = screenWidth - 16
    Dim As Integer windowHeight = screenHeight - 16
    If windowWidth > 1040 Then
        windowWidth = 1040
    End If
    If windowHeight > 780 Then
        windowHeight = 780
    End If
    session_PhraseWindow = session_CreateEditorWindow("drum_machine", "Drum Machine - Beat Phrases", _
        (screenWidth - windowWidth) \ 2, (screenHeight - windowHeight) \ 2, windowWidth, windowHeight)
    If session_PhraseWindow = 0 Then
        Exit Sub
    End If
    gui_AddWidget session_PhraseWindow
    subwindow_SetCloseHandler session_PhraseWindow, @session_OnDrumClose
    session_PhraseSlot = 0
    session_PhraseChanged = 0
    session_PhraseFirstRow = 0
    session_PhraseFirstStep = 0
    session_PhraseLooping = 0
    session_PhraseLoopStep = -1
    drumPhrase_Load 0, session_Phrase

    session_PhraseClearArmed = 0
    Dim As String actionNames(0 To 6) = {"prev", "next", "copy", "save", "loop", "clear", "starter"}
    Dim As String actionLabels(0 To 6) = {"< Phrase", "Phrase >", "Copy", "Store phrase", "Loop / Stop", "Clear", "New beat"}
    Dim As Integer actionWidth = (windowWidth - 32) \ 7
    For actionIndex As Integer = 0 To 6
        session_PhraseAddChild button_Create("phrase_" + actionNames(actionIndex), actionLabels(actionIndex), _
            16 + actionIndex * actionWidth, 34, actionWidth - 4, 44, @session_OnPhraseAction)
    Next
    session_PhraseAddChild session_CreateEditorLabel("phrase_name_label", "Phrase name", 16, 84)
    session_PhraseAddChild session_CreateEditorLabel("phrase_meter_label", "Drum meter", 230, 84)
    session_PhraseAddChild session_CreateEditorLabel("phrase_division_label", "Steps / beat", 374, 84)
    session_PhraseAddChild session_CreateEditorLabel("phrase_velocity_label", "Hit strength", 604, 84)
    session_PhraseNameBox = session_CreateEditorTextBox("phrase_name", "", 16, 102, 202, 40, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_PhraseBeatsBox = session_CreateEditorTextBox("phrase_beats", "4", 230, 102, 52, 40, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_PhraseAddChild session_CreateEditorLabel("phrase_slash", "/", 289, 114)
    session_PhraseUnitBox = session_CreateEditorTextBox("phrase_unit", "4", 308, 102, 52, 40, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_PhraseDivisionBox = session_CreateEditorTextBox("phrase_divisions", "4", 374, 102, 80, 40, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_PhraseAddChild session_PhraseNameBox
    session_PhraseAddChild session_PhraseBeatsBox
    session_PhraseAddChild session_PhraseUnitBox
    session_PhraseAddChild session_PhraseDivisionBox
    session_PhraseAddChild button_Create("phrase_apply", "Apply meter", 468, 100, 124, 44, @session_OnPhraseAction)
    session_PhraseAddChild button_Create("phrase_velocity", drumKit_VelocityName(session_DrumVelocity), 604, 100, 132, 44, @session_OnPhraseAction)
    session_PhraseInfo = session_CreateEditorLabel("phrase_info", "", 16, 154)
    session_PhraseAddChild session_PhraseInfo
    ' Include the three-pixel gutter when enforcing the target's hit size.
    Const touchCellPixels As Integer = 48 + 3
    Dim As Integer minimumCell = 35
    If session_InteractionMode = OSE_UI_INTERACTION_TOUCH Then
        minimumCell = touchCellPixels
    End If
    session_PhraseVisibleColumns = 16
    If (windowWidth - 184) \ 16 < minimumCell Then
        session_PhraseVisibleColumns = 8
    End If
    session_PhraseVisibleRows = (windowHeight - 340) \ minimumCell
    If session_PhraseVisibleRows > 12 Then
        session_PhraseVisibleRows = 12
    End If
    If session_PhraseVisibleRows < 1 Then
        session_PhraseVisibleRows = 1
    End If
    Dim As Integer cellWidth = (windowWidth - 184) \ session_PhraseVisibleColumns
    Dim As Integer rowHeight = (windowHeight - 340) \ session_PhraseVisibleRows
    For columnIndex As Integer = 0 To session_PhraseVisibleColumns - 1
        session_PhraseColumns(columnIndex) = session_CreateEditorLabel("phrase_column_" + Str(columnIndex), "", _
            168 + columnIndex * cellWidth + 8, 182)
        session_PhraseAddChild session_PhraseColumns(columnIndex)
    Next
    For rowIndex As Integer = 0 To session_PhraseVisibleRows - 1
        session_PhraseRows(rowIndex) = button_Create("phrase_pad_" + Str(rowIndex), "", _
            16, 204 + rowIndex * rowHeight, 144, rowHeight - 3, @session_OnPhraseAction)
        session_PhraseAddChild session_PhraseRows(rowIndex)
        For columnIndex As Integer = 0 To session_PhraseVisibleColumns - 1
            Dim As Widget Ptr cell = button_Create("phrase_cell_" + Str(rowIndex * 16 + columnIndex), "", _
                168 + columnIndex * cellWidth, 204 + rowIndex * rowHeight, cellWidth - 3, rowHeight - 3, @session_OnPhraseCell)
            session_PhraseCells(rowIndex, columnIndex) = cell
            If cell <> 0 Then
                cell->render = @session_RenderPhraseCell
            End If
            session_PhraseAddChild cell
        Next
    Next
    session_PhraseAddChild button_Create("phrase_rows", "More drums", 16, windowHeight - 126, 144, 44, @session_OnPhraseAction)
    session_PhraseAddChild button_Create("phrase_steps_prev", "< Steps", 168, windowHeight - 126, 104, 44, @session_OnPhraseAction)
    session_PhraseAddChild button_Create("phrase_steps_next", "Steps >", 278, windowHeight - 126, 104, 44, @session_OnPhraseAction)
    session_PhraseAddChild button_Create("phrase_song_meter", "Song meter...", 396, windowHeight - 126, 144, 44, @session_OnPhraseAction)
    session_PhraseAddChild button_Create("phrase_at_view", "At view", 552, windowHeight - 126, 90, 44, @session_OnPhraseAction)
    session_PhraseAddChild button_Create("phrase_at_end", "At end", 648, windowHeight - 126, 90, 44, @session_OnPhraseAction)
    session_PhraseAddChild session_CreateEditorLabel("phrase_tick_label", "Start tick", 16, windowHeight - 62)
    session_PhraseTickBox = session_CreateEditorTextBox("phrase_tick", LTrim(Str(session_StepEntryTick)), 98, windowHeight - 76, 150, 44, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_PhraseAddChild session_PhraseTickBox
    session_PhraseAddChild session_CreateEditorLabel("phrase_repeat_label", "Repeats", 268, windowHeight - 62)
    session_PhraseRepeatBox = session_CreateEditorTextBox("phrase_repeats", "1", 336, windowHeight - 76, 66, 44, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_PhraseAddChild session_PhraseRepeatBox
    session_PhraseAddChild button_Create("phrase_insert", "Insert into song (Ch 10)", 420, windowHeight - 76, 300, 44, @session_OnPhraseAction)
    session_PhraseStatus = session_CreateEditorLabel("phrase_status", "New beat starts a pattern. Click cells for hits; Loop to listen; Insert to arrange.", 16, windowHeight - 24)
    session_PhraseAddChild session_PhraseStatus
    session_PhraseWriteFields()
    session_PhraseRefreshGrid()
    gui_SetModalRoot session_PhraseWindow
End Sub

Private Sub session_ProcessPhraseWindow()
    If session_PhraseWindow = 0 Then
        Exit Sub
    End If
    If session_PhraseSongMeterRequested <> 0 Then
        session_PhraseSongMeterRequested = 0
        session_ClosePhraseWindow()
        If session_PhraseWindow = 0 Then
            session_OnTempoMap 0
        End If
        Exit Sub
    End If
    If subwindow_CloseRequested(session_PhraseWindow) <> 0 Then
        session_ClosePhraseWindow()
        Exit Sub
    End If
    session_PhraseRefreshGrid()
    If session_PhraseLooping = 0 Then
        Exit Sub
    End If
    Dim As ULongInt anchorTick
    If numericText_ParseUnsigned(textbox_GetText(session_PhraseTickBox), anchorTick, OSE_MAX_MIDI_TICK) = 0 Then
        session_PhraseLooping = 0
        Exit Sub
    End If
    Dim As Integer steps = session_Phrase.numerator * session_Phrase.subdivisions
    Dim As ULongInt durationTicks = drumPhrase_StepTick(session_Phrase, session_Summary.division, steps)
    If durationTicks = 0 OrElse durationTicks > OSE_MAX_MIDI_TICK - anchorTick Then
        session_PhraseLooping = 0
        Exit Sub
    End If
    Dim As Double anchorSeconds = midi_TicksToSeconds(session_Summary, anchorTick)
    Dim As Double loopSeconds = midi_TicksToSeconds(session_Summary, anchorTick + durationTicks) - anchorSeconds
    If loopSeconds <= 0 Then
        session_PhraseLooping = 0
        Exit Sub
    End If
    Dim As Double currentClock = Timer
    session_PhraseLoopElapsed += playbackTiming_ElapsedDelta(session_PhraseLoopClock, currentClock)
    session_PhraseLoopClock = currentClock
    Dim As Double elapsed = session_PhraseLoopElapsed
    Dim As Double loopPosition = elapsed - Int(elapsed / loopSeconds) * loopSeconds
    Dim As ULongInt absoluteTick = midi_SecondsToTicks(session_Summary, anchorSeconds + loopPosition)
    Dim As ULongInt currentTick = 0
    If absoluteTick > anchorTick Then
        currentTick = absoluteTick - anchorTick
    End If
    Dim As Integer currentStep = 0
    For stepIndex As Integer = 1 To steps - 1
        If drumPhrase_StepTick(session_Phrase, session_Summary.division, stepIndex) > currentTick Then
            Exit For
        End If
        currentStep = stepIndex
    Next
    ' A late UI frame sounds the current column once, never a burst of stale
    ' hits. Placement uses exact MIDI ticks independently of preview frame rate.
    Static As Double previousPosition
    If currentStep = session_PhraseLoopStep AndAlso loopPosition >= previousPosition Then
        previousPosition = loopPosition
        Exit Sub
    End If
    previousPosition = loopPosition
    session_PhraseLoopStep = currentStep
    Dim As Integer savedVelocity = session_DrumVelocity
    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        If session_Phrase.velocity(padIndex, currentStep) = 0 Then
            Continue For
        End If
        session_DrumVelocity = session_Phrase.velocity(padIndex, currentStep)
        session_TriggerDrumPad padIndex
    Next
    session_DrumVelocity = savedVelocity
End Sub

' -------------------------------------------------------------------------
' Selection tools and musical snap grid
' -------------------------------------------------------------------------

Private Function session_SnapName() As String
    Dim As String captions(0 To 4) = {"1/4", "1/8", "1/16", "1/32", "1/8 triplet"}
    If session_SnapIndex < 0 OrElse session_SnapIndex > 4 Then
        Return "1/16"
    End If
    Return captions(session_SnapIndex)
End Function

Private Sub session_RefreshNoteTools()
    If session_NoteToolsWindow = 0 Then
        Exit Sub
    End If
    If session_NoteToolsInfo = 0 OrElse session_NoteToolsInfo->data = 0 Then
        Exit Sub
    End If
    session_SynchronizeNoteSelection()
    Cast(LabelData Ptr, session_NoteToolsInfo->data)->text = _
        LTrim(Str(session_NoteSelection.count)) + " selected  |  Grid " + session_SnapName() + _
        "  |  Track " + LTrim(Str(session_SelectedTrack + 1))
    For gridIndex As Integer = 0 To 4
        Dim As Widget Ptr gridButton = gui_FindWidget("note_grid_" + LTrim(Str(gridIndex)))
        If gridButton <> 0 Then
            Dim As String captions(0 To 4) = {"1/4", "1/8", "1/16", "1/32", "1/8 triplet"}
            Cast(ButtonData Ptr, gridButton->data)->text = _
                IIf(gridIndex = session_SnapIndex, "[x] ", "") + captions(gridIndex)
        End If
    Next
    Dim As String selectionActions(0 To 8) = {"duplicate", "quantize", "down", "up", _
        "octave_down", "octave_up", "soft", "loud", "listen"}
    For actionIndex As Integer = 0 To 8
        Dim As Widget Ptr actionButton = gui_FindWidget("note_tools_" + selectionActions(actionIndex))
        If actionButton <> 0 Then
            actionButton->enabled = IIf(session_NoteSelection.count > 0, -1, 0)
        End If
    Next
    Dim As Widget Ptr undoButton = gui_FindWidget("note_tools_undo")
    Dim As Widget Ptr redoButton = gui_FindWidget("note_tools_redo")
    Dim As Widget Ptr listenButton = gui_FindWidget("note_tools_listen")
    If undoButton <> 0 Then
        undoButton->enabled = IIf(documentHistory_UndoCount(session_DocumentHistory) > 0, -1, 0)
    End If
    If redoButton <> 0 Then
        redoButton->enabled = IIf(documentHistory_RedoCount(session_DocumentHistory) > 0, -1, 0)
    End If
    If listenButton <> 0 Then Cast(ButtonData Ptr, listenButton->data)->text = _
        IIf(session_SelectedNotePlaybackActive <> 0, "Stop listening", "Listen to selection")
    Dim As Widget Ptr loopButton = gui_FindWidget("note_tools_loop")
    If loopButton <> 0 Then
        loopButton->enabled = IIf(session_NoteSelection.count > 0 OrElse session_SelectedNoteLooping <> 0, -1, 0)
        Cast(ButtonData Ptr, loopButton->data)->text = IIf(session_SelectedNoteLooping <> 0, "Stop loop", "Loop selection")
    End If
End Sub

Public Sub session_ApplySelectionTool(ByVal operation As Integer, ByVal amount As Integer)
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    session_SynchronizeNoteSelection()
    If session_NoteSelection.count = 0 Then
        session_SetStatus "Select notes first: click a note, Shift-click more, or drag across a phrase."
        Exit Sub
    End If
    Dim As Integer selectedCount = session_NoteSelection.count
    Dim As MidiEditableNote Ptr editedNotes = Callocate(selectedCount * SizeOf(MidiEditableNote))
    If editedNotes = 0 Then
        session_SetStatus "Not enough memory for this edit."
        Exit Sub
    End If
    Dim As Integer changedCount = noteSelection_PrepareEdit(session_NoteSelection, _
        operation, amount, session_ScoreSnapTicks(), editedNotes, selectedCount)
    If changedCount <= 0 Then
        Deallocate editedNotes
        If changedCount < 0 Then
            session_SetStatus "Edit would exceed the pitch or song limits. Nothing changed."
        Else
            session_SetStatus "Nothing to change. Pitch tools leave channel 10 drums unchanged."
        End If
        Exit Sub
    End If
    session_StopPlayback()
    If session_BeginMidiEdit() = 0 Then
        Deallocate editedNotes
        Exit Sub
    End If
    Dim As Integer firstNewNote = midi_GetEditableNoteCount()
    Dim As Integer applied
    If operation = OSE_NOTE_EDIT_DUPLICATE Then
        applied = IIf(midi_AddEditableNotes(session_Summary, editedNotes, selectedCount) >= 0, -1, 0)
    Else
        applied = midi_SetEditableNotes(session_Summary, @session_NoteSelection.noteIndices(0), _
            editedNotes, selectedCount)
    End If
    Dim As ULongInt firstTick = editedNotes[0].startTick
    For notePosition As Integer = 1 To selectedCount - 1
        If editedNotes[notePosition].startTick < firstTick Then
            firstTick = editedNotes[notePosition].startTick
        End If
    Next
    Deallocate editedNotes
    If applied = 0 Then
        session_CancelMidiEdit()
        session_SetStatus "The edit could not be stored. Nothing changed."
        Exit Sub
    End If
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If
    If operation = OSE_NOTE_EDIT_DUPLICATE Then
        session_ClearNoteSelection()
        For noteIndex As Integer = firstNewNote To firstNewNote + selectedCount - 1
            noteSelection_Add session_NoteSelection, noteIndex, -1
        Next
        session_SelectedNote = session_NoteSelection.primaryNoteIndex
        session_ViewStartTick = firstTick
    End If
    session_Dirty = -1
    session_InvalidateInterfaceCaches()
    Dim As String operationName
    Select Case operation
        Case OSE_NOTE_EDIT_DUPLICATE
            operationName = "Duplicated"
        Case OSE_NOTE_EDIT_QUANTIZE
            operationName = "Quantized to " + session_SnapName() + ":"
        Case OSE_NOTE_EDIT_PITCH
            operationName = "Transposed"
        Case Else
            operationName = IIf(amount > 0, "Made louder:", "Made softer:")
    End Select
    session_SetStatus operationName + " " + LTrim(Str(changedCount)) + " notes. Ctrl+Z undoes this edit."
End Sub

Private Sub session_RenderNoteToolButton(ByVal source As Widget Ptr)
    If source = 0 OrElse source->data = 0 Then
        Exit Sub
    End If
    Dim As ButtonData Ptr buttonState = Cast(ButtonData Ptr, source->data)
    Dim As OseUiControlStyle controlStyle
    Dim As Integer activeButton
    If Left(buttonState->text, 3) = "[x]" Then
        activeButton = -1
    End If
    uiStyle_Toolbar controlStyle, session_ThemePalette, buttonState->state, -1, _
        activeButton
    If source->enabled = 0 Then
        controlStyle.fillColor = session_ThemePalette.faceColor
        controlStyle.contentColor = session_ThemePalette.mutedTextColor
        controlStyle.borderColor = session_ThemePalette.dividerColor
    End If
    session_DrawRoundedControl source->ax, source->ay, source->w, source->h, controlStyle
    backend_PrintAligned source->ax, source->ay, source->w, source->h, _
        controlStyle.contentColor, buttonState->text, BACKEND_FONT_DEFAULT, _
        BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE
End Sub

Private Sub session_NoteToolsAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_NoteToolsWindow = 0 Then
        Exit Sub
    End If
    If child->render = @button_Render Then
        child->render = @session_RenderNoteToolButton
    End If
    gui_AddWidget child
    gui_SetParent child, session_NoteToolsWindow
End Sub

Private Sub session_NoteToolsHistory(ByVal redoEdit As Integer)
    Dim As NoteSelectionState previousSelection = session_NoteSelection
    Dim As Integer previousNoteCount = midi_GetEditableNoteCount()
    If redoEdit <> 0 Then
        session_ApplyRedoEdit()
    Else
        session_ApplyUndoEdit()
    End If
    ' A nonstructural edit retains note indices. Keep the phrase selected for
    ' comparison after pitch, timing and velocity changes. Structural undo
    ' still clears selection because indices may now refer to other notes.
    If midi_GetEditableNoteCount() = previousNoteCount Then
        session_NoteSelection = previousSelection
        session_SelectedNote = previousSelection.primaryNoteIndex
        session_SynchronizeNoteSelection()
    End If
End Sub

Public Sub session_OnNoteToolAction(ByVal source As Widget Ptr)
    If source = 0 OrElse session_NoteToolsWindow = 0 Then
        Exit Sub
    End If
    If Left(source->name, 10) = "note_grid_" Then
        Dim As Integer gridIndex = ValInt(Mid(source->name, 11))
        If gridIndex >= 0 AndAlso gridIndex <= 4 Then
            session_SnapIndex = gridIndex
            session_InvalidateInterfaceCaches()
            session_SetStatus "Grid " + session_SnapName() + " applies to note placement, dragging and quantize."
        End If
    Else
        Select Case source->name
            Case "note_tools_duplicate"
                session_ApplySelectionTool OSE_NOTE_EDIT_DUPLICATE
            Case "note_tools_quantize"
                session_ApplySelectionTool OSE_NOTE_EDIT_QUANTIZE
            Case "note_tools_down"
                session_ApplySelectionTool OSE_NOTE_EDIT_PITCH, -1
            Case "note_tools_up"
                session_ApplySelectionTool OSE_NOTE_EDIT_PITCH, 1
            Case "note_tools_octave_down"
                session_ApplySelectionTool OSE_NOTE_EDIT_PITCH, -12
            Case "note_tools_octave_up"
                session_ApplySelectionTool OSE_NOTE_EDIT_PITCH, 12
            Case "note_tools_soft"
                session_ApplySelectionTool OSE_NOTE_EDIT_VELOCITY, -10
            Case "note_tools_loud"
                session_ApplySelectionTool OSE_NOTE_EDIT_VELOCITY, 10
            Case "note_tools_undo"
                session_NoteToolsHistory 0
            Case "note_tools_redo"
                session_NoteToolsHistory -1
            Case "note_tools_loop"
                If session_SelectedNoteLooping <> 0 Then
                    session_StopPlayback()
                    session_SetStatus "Selection loop stopped."
                Else
                    session_OnPlaySelectedNotes 0
                    If session_SelectedNotePlaybackActive <> 0 Then
                        Dim As ULongInt loopStart = session_SelectedNotePlayback.startTick
                        Dim As ULongInt loopSpan = session_SelectedNotePlayback.endTick - loopStart
                        Dim As ULongInt gridTicks = session_ScoreSnapTicks()
                        loopSpan = ((loopSpan + gridTicks - 1) \ gridTicks) * gridTicks
                        If loopSpan > OSE_MAX_MIDI_TICK - loopStart Then
                            session_StopPlayback()
                            session_SetStatus "The loop would extend beyond the song's timing limit."
                        Else
                            session_SelectedNoteLoopEnd = loopStart + loopSpan
                            session_SelectedNoteLooping = -1
                            session_SetStatus "Looping selection. Length rounds up to the snap grid; Stop loop ends playback."
                        End If
                    End If
                End If
            Case "note_tools_listen"
                If session_SelectedNotePlaybackActive <> 0 Then
                    session_StopPlayback()
                    session_SetStatus "Selection playback stopped."
                Else
                    session_OnPlaySelectedNotes 0
                End If
            Case "note_tools_track"
                session_ClearNoteSelection()
                For noteIndex As Integer = 0 To midi_GetEditableNoteCount() - 1
                    Dim As MidiEditableNote editableNote
                    If midi_GetEditableNote(noteIndex, editableNote) <> 0 AndAlso _
                        editableNote.trackIndex = session_SelectedTrack Then
                        If noteSelection_Add(session_NoteSelection, noteIndex, -1) = 0 Then
                            session_ClearNoteSelection()
                            session_SetStatus "This track exceeds the selection limit. Select a smaller phrase."
                            Exit Sub
                        End If
                    End If
                Next
                session_SelectedNote = session_NoteSelection.primaryNoteIndex
                session_AnnounceSelection ""
            Case "note_tools_close"
                ' Remove widgets only after omaGUI finishes dispatching input.
                Cast(SubWindowData Ptr, session_NoteToolsWindow->data)->close_requested = -1
        End Select
    End If
    session_RefreshNoteTools()
    If session_NoteToolsStatus <> 0 AndAlso session_NoteToolsStatus->data <> 0 Then _
        Cast(LabelData Ptr, session_NoteToolsStatus->data)->text = session_ClipText(session_StatusText, 76)
End Sub

Public Sub session_OnNoteTools(ByVal source As Widget Ptr)
    If session_NoteToolsWindow <> 0 Then
        gui_BringToFront session_NoteToolsWindow
        Exit Sub
    End If
    If session_IsModalOpen() <> 0 Then
        session_SetStatus "Close the current window first."
        Exit Sub
    End If
    If session_LiveRecording <> 0 Then
        session_EndLiveRecording()
    End If
    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    session_NoteToolsWindow = session_CreateEditorWindow("note_tools", "Note tools", _
        (screenWidth - 620) \ 2, (screenHeight - 430) \ 2, 620, 430)
    If session_NoteToolsWindow = 0 Then
        Exit Sub
    End If
    gui_AddWidget session_NoteToolsWindow
    subwindow_SetCloseHandler session_NoteToolsWindow, @session_OnDrumClose
    session_NoteToolsInfo = session_CreateEditorLabel("note_tools_info", "", 16, 34)
    session_NoteToolsAddChild session_NoteToolsInfo
    session_NoteToolsAddChild session_CreateEditorLabel("note_tools_grid_label", "Snap grid", 16, 62)
    For gridIndex As Integer = 0 To 4
        session_NoteToolsAddChild button_Create("note_grid_" + LTrim(Str(gridIndex)), "", _
            16 + gridIndex * 118, 82, 112, 44, @session_OnNoteToolAction)
    Next
    session_NoteToolsAddChild button_Create("note_tools_duplicate", "Duplicate  Ctrl+D", 16, 142, 190, 44, @session_OnNoteToolAction)
    session_NoteToolsAddChild button_Create("note_tools_quantize", "Quantize  Ctrl+Q", 212, 142, 190, 44, @session_OnNoteToolAction)
    session_NoteToolsAddChild button_Create("note_tools_track", "Select track notes", 408, 142, 196, 44, @session_OnNoteToolAction)
    Dim As String pitchNames(0 To 3) = {"down", "up", "octave_down", "octave_up"}
    Dim As String pitchLabels(0 To 3) = {"Pitch -1", "Pitch +1", "Octave -1", "Octave +1"}
    For pitchIndex As Integer = 0 To 3
        session_NoteToolsAddChild button_Create("note_tools_" + pitchNames(pitchIndex), pitchLabels(pitchIndex), _
            16 + pitchIndex * 148, 196, 142, 44, @session_OnNoteToolAction)
    Next
    session_NoteToolsAddChild button_Create("note_tools_soft", "Softer", 16, 250, 142, 44, @session_OnNoteToolAction)
    session_NoteToolsAddChild button_Create("note_tools_loud", "Louder", 164, 250, 142, 44, @session_OnNoteToolAction)
    session_NoteToolsAddChild button_Create("note_tools_listen", "Listen to selection", 312, 250, 290, 44, @session_OnNoteToolAction)
    session_NoteToolsAddChild session_CreateEditorLabel("note_tools_hint", "Edits apply immediately. Quantize keeps note lengths; pitch keeps drum sounds.", 16, 308)
    session_NoteToolsAddChild button_Create("note_tools_undo", "Undo", 16, 332, 142, 44, @session_OnNoteToolAction)
    session_NoteToolsAddChild button_Create("note_tools_redo", "Redo", 164, 332, 142, 44, @session_OnNoteToolAction)
    session_NoteToolsAddChild button_Create("note_tools_loop", "Loop selection", 312, 332, 142, 44, @session_OnNoteToolAction)
    session_NoteToolsAddChild button_Create("note_tools_close", "Done", 460, 332, 142, 44, @session_OnNoteToolAction)
    session_NoteToolsStatus = session_CreateEditorLabel("note_tools_status", "Choose selected notes or Select track notes to work on this track.", 16, 398)
    session_NoteToolsAddChild session_NoteToolsStatus
    session_RefreshNoteTools()
    gui_SetModalRoot session_NoteToolsWindow
End Sub

Private Sub session_ProcessNoteToolsWindow()
    If session_NoteToolsWindow = 0 Then
        Exit Sub
    End If
    session_RefreshNoteTools()
    If subwindow_CloseRequested(session_NoteToolsWindow) <> 0 Then
        session_StopPlayback()
        gui_RemoveWidget session_NoteToolsWindow->name
        gui_ClearModalRoot()
        session_NoteToolsWindow = 0
        session_NoteToolsInfo = 0
        session_NoteToolsStatus = 0
    End If
End Sub

' -------------------------------------------------------------------------
' Direct song time-signature picker
' -------------------------------------------------------------------------

Private Sub session_SongMeterAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_SongMeterWindow = 0 Then
        Exit Sub
    End If
    gui_AddGeneratedWidget child
    gui_SetParent child, session_SongMeterWindow
End Sub

Private Sub session_SongMeterRefreshFields()
    Dim As Integer numerator = 4
    Dim As Integer denominator = 4
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick(session_SongMeterTick)
    If signatureIndex >= 0 Then
        numerator = session_Summary.timeSignatureMap(signatureIndex).numerator
        denominator = session_TempoDenominatorValue( _
            session_Summary.timeSignatureMap(signatureIndex).denominatorPower)
    End If
    textbox_SetText session_SongMeterNumeratorBox, LTrim(Str(numerator)), -1
    textbox_SetText session_SongMeterDenominatorBox, LTrim(Str(denominator)), -1
    Cast(LabelData Ptr, session_SongMeterInfo->data)->text = _
        "Active here: " + LTrim(Str(numerator)) + "/" + LTrim(Str(denominator)) + _
        "   Change from bar " + LTrim(Str(session_ScoreMeasureNumber(session_SongMeterTick)))
    Dim As Widget Ptr startButton = gui_FindWidget("song_meter_start")
    Dim As Widget Ptr viewButton = gui_FindWidget("song_meter_view")
    Cast(ButtonData Ptr, startButton->data)->text = IIf(session_SongMeterTick = 0, "[x] Song start", "Song start")
    Cast(ButtonData Ptr, viewButton->data)->text = IIf(session_SongMeterTick <> 0, "[x] Current view", "Current view")
End Sub

Public Sub session_OnSongMeterAction(ByVal source As Widget Ptr)
    If source = 0 OrElse session_SongMeterWindow = 0 Then
        Exit Sub
    End If
    Select Case source->name
        Case "song_meter_start"
            session_SongMeterTick = 0
            session_SongMeterRefreshFields()
        Case "song_meter_view"
            session_SongMeterTick = session_SongMeterViewTick
            session_SongMeterRefreshFields()
        Case "song_meter_34", "song_meter_44", "song_meter_68"
            Dim As String numeratorText = "4"
            Dim As String denominatorText = "4"
            If source->name = "song_meter_34" Then
                numeratorText = "3"
            End If
            If source->name = "song_meter_68" Then
                numeratorText = "6"
                denominatorText = "8"
            End If
            textbox_SetText session_SongMeterNumeratorBox, numeratorText, -1
            textbox_SetText session_SongMeterDenominatorBox, denominatorText, -1
        Case "song_meter_close"
            session_SongMeterCloseRequested = -1
        Case "song_meter_apply"
            Dim As ULongInt numerator
            Dim As ULongInt denominator
            Dim As Integer valid = numericText_ParseUnsigned( _
                textbox_GetText(session_SongMeterNumeratorBox), numerator, 255)
            valid And= numericText_ParseUnsigned( _
                textbox_GetText(session_SongMeterDenominatorBox), denominator, 128)
            If numerator < 1 OrElse denominator < 1 Then
                valid = 0
            End If
            Dim As Integer denominatorPower = 0
            Dim As ULongInt denominatorValue = 1
            While denominatorValue < denominator AndAlso denominatorPower < 7
                denominatorValue *= 2
                denominatorPower += 1
            Wend
            If denominatorValue <> denominator Then
                valid = 0
            End If
            If valid = 0 Then
                Cast(LabelData Ptr, session_SongMeterStatus->data)->text = _
                    "Use 1-255 beats and a denominator of 1, 2, 4, 8, 16, 32, 64 or 128."
                Exit Sub
            End If
            Dim As Integer signatureIndex = session_TimeSignatureIndexExactForTick(session_SongMeterTick)
            Dim As Integer needsEdit = -1
            If signatureIndex >= 0 Then needsEdit = _
                session_Summary.timeSignatureMap(signatureIndex).numerator <> numerator OrElse _
                session_Summary.timeSignatureMap(signatureIndex).denominatorPower <> denominatorPower
            If needsEdit <> 0 Then
                If session_BeginMidiEdit() = 0 Then
                    Exit Sub
                End If
                Dim As Integer stored
                If signatureIndex >= 0 Then
                    stored = midi_SetTimeSignaturePoint(session_Summary, signatureIndex, CInt(numerator), denominatorPower)
                Else
                    stored = IIf(midi_AddTimeSignaturePoint(session_Summary, 0, session_SongMeterTick, _
                        CInt(numerator), denominatorPower) >= 0, -1, 0)
                End If
                If stored = 0 Then
                    session_CancelMidiEdit()
                    Cast(LabelData Ptr, session_SongMeterStatus->data)->text = "The song time signature could not be stored."
                    Exit Sub
                End If
                If session_CommitMidiEdit() = 0 Then
                    Exit Sub
                End If
                session_Dirty = -1
            End If
            ' Apply & show moves to the edited segment. Selecting a preset by
            ' itself only changes the fields, and leaves the song untouched.
            session_ViewStartTick = session_SongMeterTick
            session_InvalidateInterfaceCaches()
            session_SetStatus "Song time signature " + LTrim(Str(numerator)) + "/" + _
                LTrim(Str(denominator)) + " is active here. Drum phrases keep their own meter."
            session_SongMeterCloseRequested = -1
    End Select
End Sub

Public Sub session_OnSongMeter(ByVal source As Widget Ptr)
    If session_SongMeterWindow <> 0 Then
        gui_BringToFront session_SongMeterWindow
        Exit Sub
    End If
    If session_IsModalOpen() <> 0 Then
        session_SetStatus "Close the current window first."
        Exit Sub
    End If
    If session_Summary.division < 1 OrElse session_Summary.division > 32767 Then
        session_SetStatus "Time signatures require musical tick timing."
        Exit Sub
    End If
    session_StopPlayback()
    session_SongMeterViewTick = session_ViewStartTick
    session_SongMeterTick = session_ViewStartTick
    session_SongMeterCloseRequested = 0
    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    session_SongMeterWindow = session_CreateEditorWindow("song_meter", "Song time signature", _
        (screenWidth - 540) \ 2, (screenHeight - 300) \ 2, 540, 300)
    If session_SongMeterWindow = 0 Then
        Exit Sub
    End If
    gui_AddWidget session_SongMeterWindow
    subwindow_SetCloseHandler session_SongMeterWindow, @session_OnDrumClose
    session_SongMeterInfo = session_CreateEditorLabel("song_meter_info", "", 16, 32)
    session_SongMeterAddChild session_SongMeterInfo
    session_SongMeterAddChild button_Create("song_meter_start", "Song start", 16, 54, 180, 44, @session_OnSongMeterAction)
    session_SongMeterAddChild button_Create("song_meter_view", "Current view", 208, 54, 180, 44, @session_OnSongMeterAction)
    session_SongMeterAddChild session_CreateEditorLabel("song_meter_label", "Time signature", 16, 120)
    session_SongMeterNumeratorBox = session_CreateEditorTextBox("song_meter_numerator", "4", 164, 108, 80, 44, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_SongMeterAddChild session_SongMeterNumeratorBox
    session_SongMeterAddChild session_CreateEditorLabel("song_meter_slash", "/", 254, 120)
    session_SongMeterDenominatorBox = session_CreateEditorTextBox("song_meter_denominator", "4", 274, 108, 80, 44, 0, 0, TEXTBOX_SCROLLBAR_NONE)
    session_SongMeterAddChild session_SongMeterDenominatorBox
    session_SongMeterAddChild button_Create("song_meter_34", "3/4", 16, 162, 100, 44, @session_OnSongMeterAction)
    session_SongMeterAddChild button_Create("song_meter_44", "4/4", 126, 162, 100, 44, @session_OnSongMeterAction)
    session_SongMeterAddChild button_Create("song_meter_68", "6/8", 236, 162, 100, 44, @session_OnSongMeterAction)
    session_SongMeterAddChild button_Create("song_meter_apply", "Apply & show", 16, 216, 210, 44, @session_OnSongMeterAction)
    session_SongMeterAddChild button_Create("song_meter_close", "Cancel", 236, 216, 100, 44, @session_OnSongMeterAction)
    session_SongMeterStatus = session_CreateEditorLabel("song_meter_status", "Choose a meter, then Apply & show. Drums have their own meter.", 16, 276)
    session_SongMeterAddChild session_SongMeterStatus
    session_SongMeterRefreshFields()
    gui_SetModalRoot session_SongMeterWindow
End Sub

Private Sub session_ProcessSongMeterWindow()
    If session_SongMeterWindow = 0 Then
        Exit Sub
    End If
    If session_SongMeterCloseRequested <> 0 OrElse subwindow_CloseRequested(session_SongMeterWindow) <> 0 Then
        ' Defer destruction until the widget dispatcher has returned.
        gui_RemoveWidget session_SongMeterWindow->name
        gui_ClearModalRoot()
        session_SongMeterWindow = 0
        session_SongMeterCloseRequested = 0
    End If
End Sub

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
    Select Case parsedDenominator
        Case 4, 8, 16, 32
        Case Else
            Return 0
    End Select
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

    Dim As String valueText = Environ(variableName)
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
    If Trim(Environ("OSE_TEST_SNAPSHOT")) = "" Then
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


' -------------------------------------------------------------------------
' Classic application menus and pane scrollbars
' -------------------------------------------------------------------------

Private Sub session_HideDesktopMenus()
    Dim As Widget Ptr menus(0 To 7) = {session_FileMenu, session_EditMenu, _
        session_OptionsMenu, session_SetupMenu, session_TrackMenu, _
        session_MusicMenu, session_WindowMenu, session_HelpMenu}
    For menuIndex As Integer = 0 To 7
        If menus(menuIndex) <> 0 Then
            menus(menuIndex)->visible = 0
        End If
    Next
End Sub


Private Sub session_ShowDesktopMenu( _
    ByVal menuWidget As Widget Ptr, _
    ByVal menuLeft As Integer _
)
    If menuWidget = 0 Then
        Exit Sub
    End If
    session_HideDesktopMenus()
    menuWidget->x = menuLeft
    menuWidget->y = SESSION_MENU_HEIGHT
    menuWidget->visible = -1
    gui_BringToFront menuWidget
End Sub


Private Function session_DesktopMenuAt( _
    ByVal menuIndex As Integer _
) As Widget Ptr
    Select Case menuIndex
        Case 0
            Return session_FileMenu
        Case 1
            Return session_EditMenu
        Case 2
            Return session_OptionsMenu
        Case 3
            Return session_SetupMenu
        Case 4
            Return session_WindowMenu
        Case 5
            Return session_TrackMenu
        Case 6
            Return session_MusicMenu
        Case 7
            Return session_HelpMenu
    End Select
    Return 0
End Function


Private Function session_VisibleDesktopMenuIndex() As Integer
    For menuIndex As Integer = 0 To SESSION_DESKTOP_MENU_COUNT - 1
        Dim As Widget Ptr menuWidget = session_DesktopMenuAt(menuIndex)
        If menuWidget <> 0 AndAlso menuWidget->visible <> 0 Then _
            Return menuIndex
    Next
    Return -1
End Function


Private Sub session_ShowDesktopMenuAt( _
    ByVal menuIndex As Integer, _
    ByVal screenWidth As Integer _
)
    Dim As Integer menuLeft
    Select Case menuIndex
        Case 0
            menuLeft = 6
        Case 1
            menuLeft = 46
        Case 2
            menuLeft = 86
        Case 3
            menuLeft = 150
        Case 4
            menuLeft = 206
        Case 5
            menuLeft = 254
        Case 6
            menuLeft = 308
        Case 7
            menuLeft = screenWidth - 210
        Case Else
            Exit Sub
    End Select

    Dim As Widget Ptr menuWidget = session_DesktopMenuAt(menuIndex)
    session_ShowDesktopMenu menuWidget, menuLeft
    If menuWidget <> 0 AndAlso menuWidget->data <> 0 Then
        Dim As MenuData Ptr menuState = Cast(MenuData Ptr, menuWidget->data)
        menuState->selected = IIf(menuState->count > 0, 0, -1)
        session_MenuKeyboardSelection = menuState->selected
    End If
End Sub


Private Function session_DesktopMenuShortcutIndex() As Integer
    If input_AltShortcutPressed(FB.SC_F) <> 0 Then
        Return 0
    End If
    If input_AltShortcutPressed(FB.SC_E) <> 0 Then
        Return 1
    End If
    If input_AltShortcutPressed(FB.SC_O) <> 0 Then
        Return 2
    End If
    If input_AltShortcutPressed(FB.SC_S) <> 0 Then
        Return 3
    End If
    If input_AltShortcutPressed(FB.SC_V) <> 0 Then
        Return 4
    End If
    If input_AltShortcutPressed(FB.SC_T) <> 0 Then
        Return 5
    End If
    If input_AltShortcutPressed(FB.SC_M) <> 0 Then
        Return 6
    End If
    If input_AltShortcutPressed(FB.SC_H) <> 0 Then
        Return 7
    End If
    Return -1
End Function


Private Sub session_MoveDesktopMenuSelection( _
    ByVal menuWidget As Widget Ptr, _
    ByVal direction As Integer _
)
    If menuWidget = 0 OrElse menuWidget->data = 0 Then
        Exit Sub
    End If
    Dim As MenuData Ptr menuState = Cast(MenuData Ptr, menuWidget->data)
    If menuState->count <= 0 Then
        menuState->selected = -1
        Exit Sub
    End If

    If menuState->selected < 0 OrElse menuState->selected >= menuState->count Then
        menuState->selected = IIf(direction < 0, menuState->count - 1, 0)
    Else
        menuState->selected += direction
        If menuState->selected < 0 Then
            menuState->selected = menuState->count - 1
        End If
        If menuState->selected >= menuState->count Then
            menuState->selected = 0
        End If
    End If
    session_MenuKeyboardSelection = menuState->selected
End Sub


Private Sub session_ActivateDesktopMenuSelection( _
    ByVal menuWidget As Widget Ptr _
)
    If menuWidget = 0 OrElse menuWidget->data = 0 Then
        Exit Sub
    End If
    Dim As MenuData Ptr menuState = Cast(MenuData Ptr, menuWidget->data)
    Dim As Integer selectedIndex = menuState->selected
    If selectedIndex < 0 OrElse selectedIndex >= menuState->count Then
        Exit Sub
    End If

    session_HideDesktopMenus()
    session_MenuKeyboardAccess = 0
    If menuState->callbacks(selectedIndex) <> 0 Then _
        menuState->callbacks(selectedIndex)(selectedIndex)
End Sub


Private Sub session_ProcessMenuBar()
    Dim As Integer menuScreenWidth
    Dim As Integer menuScreenHeight
    backend_GetSize menuScreenWidth, menuScreenHeight
    Dim As Integer mouseButtons = input_MouseButtons()
    session_MenuEscapeConsumed = 0

    /'
        Desktop menu keyboard model

        Alt plus the first letter opens each top-level menu. Once open, the
        arrow keys move within or between menus, Enter activates the selected
        command, and Escape dismisses the popup without quitting the editor.
        This mirrors the pointer routes below while keeping one command table.
    '/
    Dim As Integer shortcutMenuIndex = session_DesktopMenuShortcutIndex()
    If shortcutMenuIndex >= 0 AndAlso session_IsModalOpen() = 0 Then
        ' The popup owns navigation until it closes. Clearing the previous
        ' widget focus prevents Enter from activating both a toolbar command
        ' and the selected menu item in the same retained input frame.
        gui_SetFocus 0
        session_ShowDesktopMenuAt shortcutMenuIndex, menuScreenWidth
        session_MenuKeyboardAccess = -1
    End If

    Dim As Integer visibleMenuIndex = session_VisibleDesktopMenuIndex()
    If visibleMenuIndex >= 0 Then
        Dim As Widget Ptr visibleMenu = session_DesktopMenuAt(visibleMenuIndex)
        If session_MenuKeyboardAccess <> 0 AndAlso visibleMenu <> 0 AndAlso _
            visibleMenu->data <> 0 Then
            Dim As MenuData Ptr visibleMenuState = _
                Cast(MenuData Ptr, visibleMenu->data)
            If session_MenuKeyboardSelection >= 0 AndAlso _
                session_MenuKeyboardSelection < visibleMenuState->count Then _
                visibleMenuState->selected = session_MenuKeyboardSelection
        End If
        If input_KeyPressEvent(KEY_ESCAPE) <> 0 Then
            session_HideDesktopMenus()
            session_MenuEscapeConsumed = -1
            session_MenuKeyboardAccess = 0
        ElseIf input_KeyPressEvent(KEY_LEFT) <> 0 Then
            visibleMenuIndex -= 1
            If visibleMenuIndex < 0 Then _
                visibleMenuIndex = SESSION_DESKTOP_MENU_COUNT - 1
            session_ShowDesktopMenuAt visibleMenuIndex, menuScreenWidth
            session_MenuKeyboardAccess = -1
        ElseIf input_KeyPressEvent(KEY_RIGHT) <> 0 Then
            visibleMenuIndex += 1
            If visibleMenuIndex >= SESSION_DESKTOP_MENU_COUNT Then _
                visibleMenuIndex = 0
            session_ShowDesktopMenuAt visibleMenuIndex, menuScreenWidth
            session_MenuKeyboardAccess = -1
        ElseIf input_KeyPressEvent(KEY_UP) <> 0 Then
            session_MoveDesktopMenuSelection visibleMenu, -1
            session_MenuKeyboardAccess = -1
        ElseIf input_KeyPressEvent(KEY_DOWN) <> 0 Then
            session_MoveDesktopMenuSelection visibleMenu, 1
            session_MenuKeyboardAccess = -1
        ElseIf input_KeyPressEvent(KEY_RETURN) <> 0 Then
            session_ActivateDesktopMenuSelection visibleMenu
        End If
    End If

    ' Popup menus close themselves on any mouse-down outside their rectangle.
    ' Opening on release prevents the menu-bar click from immediately closing
    ' the popup on the following widget update.
    Dim As Integer leftReleased = ((mouseButtons And 1) = 0) AndAlso _
        ((session_MenuLastMouseButtons And &H1) <> 0)
    If leftReleased <> 0 AndAlso session_IsModalOpen() = 0 AndAlso _
        input_MouseY() >= 0 AndAlso input_MouseY() < SESSION_MENU_HEIGHT Then
        Dim As Integer mouseX = input_MouseX()
        session_MenuKeyboardAccess = 0
        If mouseX >= 6 AndAlso mouseX < 44 Then
            session_ShowDesktopMenuAt 0, menuScreenWidth
        ElseIf mouseX < 84 Then
            session_ShowDesktopMenuAt 1, menuScreenWidth
        ElseIf mouseX < 148 Then
            session_ShowDesktopMenuAt 2, menuScreenWidth
        ElseIf mouseX < 204 Then
            session_ShowDesktopMenuAt 3, menuScreenWidth
        ElseIf mouseX < 252 Then
            session_ShowDesktopMenuAt 4, menuScreenWidth
        ElseIf mouseX < 306 Then
            session_ShowDesktopMenuAt 5, menuScreenWidth
        ElseIf mouseX < 370 Then
            session_ShowDesktopMenuAt 6, menuScreenWidth
        ElseIf mouseX >= menuScreenWidth - 54 Then
            session_ShowDesktopMenuAt 7, menuScreenWidth
        End If
    End If
    session_MenuLastMouseButtons = mouseButtons
End Sub


Public Sub session_OnFileMenu(ByVal selectedIndex As Integer)
    Select Case selectedIndex
        Case 0
            session_OnNewDocument 0
        Case 1
            session_OnOpen 0
        Case 2
            session_OnSave 0
        Case 3
            session_OnSaveProject 0
        Case 4
            session_OnExportMod 0
        Case 5
            session_OnExportWav 0
        Case 6
            session_RequestQuit()
    End Select
End Sub


Public Sub session_OnEditMenu(ByVal selectedIndex As Integer)
    Select Case selectedIndex
        Case 0
            session_ApplyUndoEdit()
        Case 1
            session_ApplyRedoEdit()
        Case 2
            session_SelectAllNotes()
        Case 3
            session_CutSelectedNotes()
        Case 4
            session_CopySelectedNotes()
        Case 5
            session_PasteCopiedNotes()
        Case 6
            session_OnNoteProperties 0
        Case 7
            session_OnDeleteNote 0
        Case 8
            session_OnNoteTools 0
        Case 9
            session_ApplySelectionTool OSE_NOTE_EDIT_DUPLICATE
        Case 10
            session_ApplySelectionTool OSE_NOTE_EDIT_QUANTIZE
    End Select
End Sub


Public Sub session_OnOptionsMenu(ByVal selectedIndex As Integer)
    Select Case selectedIndex
        Case 0
            session_OnTempoMap 0
        Case 1
            session_OnAutomation 0
        Case 2
            session_OnAudio 0
        Case 3
            session_OnKeyboard 0
        Case 4
            session_OnMic 0
        Case 5
            session_ApplyTheme OSE_UI_THEME_LIGHT, -1
        Case 6
            session_ApplyTheme OSE_UI_THEME_DARK, -1
        Case 7
            session_ApplyTheme OSE_UI_THEME_BLACK, -1
        Case 8
            session_ApplyInteractionMode IIf( _
                session_InteractionMode = OSE_UI_INTERACTION_TOUCH, _
                OSE_UI_INTERACTION_FINE, OSE_UI_INTERACTION_TOUCH), -1
        Case 9
            session_OnSoundFont 0
        Case 10
            session_OnUseBuiltInSynth 0
    End Select
End Sub


Public Sub session_OnSetupMenu(ByVal selectedIndex As Integer)
    Select Case selectedIndex
        Case 0
            session_OnMidiInput 0
        Case 1
            session_OnMidiOutput 0
        Case 2
            session_OnTrackProperties 0
        Case 3
            session_OnApplyTempo 0
        Case 4
            session_RestartAudioRuntime -1
    End Select
End Sub


Public Sub session_OnTrackMenu(ByVal selectedIndex As Integer)
    Select Case selectedIndex
        Case 0
            session_OnAddTrack 0
        Case 1
            session_OnRemoveTrack 0
        Case 2
            session_OnTrackProperties 0
    End Select
End Sub


Public Sub session_OnMusicMenu(ByVal selectedIndex As Integer)
    Select Case selectedIndex
        Case 0
            session_ActiveScoreTool = SESSION_SCORE_TOOL_ADD_NOTE
            session_AddPaletteVisible = -1
            session_SetStatus "Add Note: choose a value, then click the score."
        Case 1
            session_ActiveScoreTool = SESSION_SCORE_TOOL_DELETE_NOTE
            session_AddPaletteVisible = 0
            session_SetStatus "Delete Note: click the note to remove."
        Case 2
            session_OnNoteProperties 0
        Case 3
            session_OnPlaySelectedNotes 0
        Case 4
            session_OnTone 0
        Case 5
            session_OnDrumKit 0
        Case 6
            session_OnDrumMachine 0
    End Select
End Sub


Public Sub session_OnWindowMenu(ByVal selectedIndex As Integer)
    Select Case selectedIndex
        Case SESSION_VIEW_ZOOM_IN
            session_ZoomScoreIn()
        Case SESSION_VIEW_ZOOM_NORMAL
            session_ZoomScoreNormal()
        Case SESSION_VIEW_ZOOM_OUT
            session_ZoomScoreOut()
        Case SESSION_VIEW_ZOOM_SELECTION
            session_ZoomScoreToSelection()
        Case SESSION_VIEW_FIT_PROJECT
            session_FitScoreProject()
        Case SESSION_VIEW_FIT_TRACKS
            session_FitScoreTracks()
        Case SESSION_VIEW_MIDI_EVENTS
            session_OnAutomation 0
    End Select
End Sub


Private Sub session_AboutAddChild(ByVal child As Widget Ptr)
    If child = 0 OrElse session_AboutWindow = 0 Then
        Exit Sub
    End If
    gui_AddGeneratedWidget child
    gui_SetParent child, session_AboutWindow
End Sub


Private Sub session_CloseAboutWindow()
    If session_AboutWindow = 0 Then
        Exit Sub
    End If

    Dim As String windowName = session_AboutWindow->name
    gui_RemoveWidget windowName
    gui_ClearModalRoot()
    session_AboutWindow = 0
End Sub


Public Sub session_OnAboutWindowClose(ByVal source As Widget Ptr)
    ' The application loop removes the full generated child tree safely.
    If source = 0 Then
        Exit Sub
    End If
End Sub


Private Sub session_ProcessAboutWindow()
    If session_AboutWindow = 0 OrElse _
        subwindow_CloseRequested(session_AboutWindow) = 0 Then Exit Sub

    session_CloseAboutWindow()
    session_SetStatus "About window closed."
End Sub


Public Sub session_OnAboutClose(ByVal source As Widget Ptr)
    session_CloseAboutWindow()
    session_SetStatus "About window closed."
End Sub


Public Sub session_OnHelpMenu(ByVal selectedIndex As Integer)
    If selectedIndex < 0 OrElse selectedIndex > 1 Then
        Exit Sub
    End If
    If session_AboutWindow <> 0 Then
        gui_BringToFront session_AboutWindow
        Exit Sub
    End If
    If session_IsModalOpen() <> 0 Then
        session_SetStatus "Close the current modal window first."
        Exit Sub
    End If

    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    If selectedIndex = 1 Then
        session_AboutWindow = session_CreateEditorWindow("quick_start", "Quick start and shortcuts", _
            (screenWidth - 640) \ 2, (screenHeight - 442) \ 2, 640, 442)
        If session_AboutWindow = 0 Then
            Exit Sub
        End If
        gui_AddWidget session_AboutWindow
        subwindow_SetCloseHandler session_AboutWindow, @session_OnAboutWindowClose
        Dim As String guideLines(0 To 13) = { _
            "WRITE A MELODY", _
            "Click Note on the left, choose a note length, then click a staff.", _
            "Select a note, Shift-click more, or drag empty space to select a phrase.", _
            "Drag selected notes to move them. Alt-drag a single note to resize it.", _
            "BUILD AND ARRANGE BEATS", _
            "Drum machine > New beat gives you a starter pattern. Click cells to edit.", _
            "Loop phrase listens. At view / At end chooses where Insert puts the beat.", _
            "Copy makes a variation. Drum meter can differ from the song's Time meter.", _
            "WORK WITH A PHRASE", _
            "Note tools offers snap, quantize, pitch, loudness, listen and looping.", _
            "Ctrl+D repeats your selection; Ctrl+Q quantizes it to the selected grid.", _
            "Space plays/pauses. Ctrl+Space listens to selection. F2 stops playback.", _
            "Ctrl+Z undoes; Ctrl+Y or Ctrl+Shift+Z redoes. Ctrl+S saves your work.", _
            "Ctrl+E frames selected notes. Ctrl+F fits the song. Wheel scrolls the score." _
        }
        For lineIndex As Integer = 0 To 13
            session_AboutAddChild session_CreateEditorLabel("quick_start_line_" + LTrim(Str(lineIndex)), _
                guideLines(lineIndex), 18, 38 + lineIndex * 23)
        Next
        session_AboutAddChild button_Create("quick_start_close", "Got it", 18, 376, 140, 44, @session_OnAboutClose)
        gui_SetModalRoot session_AboutWindow
        session_SetStatus "Quick start: writing, beats, arranging and essential shortcuts."
        Exit Sub
    End If
    Dim As Integer windowX = (screenWidth - SESSION_ABOUT_WINDOW_WIDTH) \ 2
    Dim As Integer windowY = (screenHeight - SESSION_ABOUT_WINDOW_HEIGHT) \ 2
    If windowX < 0 Then
        windowX = 0
    End If
    If windowY < 0 Then
        windowY = 0
    End If

    session_AboutWindow = session_CreateEditorWindow( _
        "about_window", "About OpenSesh", windowX, windowY, _
        SESSION_ABOUT_WINDOW_WIDTH, SESSION_ABOUT_WINDOW_HEIGHT)
    If session_AboutWindow = 0 Then
        session_SetStatus "Could not create the About window."
        Exit Sub
    End If
    gui_AddWidget session_AboutWindow
    subwindow_SetCloseHandler session_AboutWindow, @session_OnAboutWindowClose

    Dim As Widget Ptr child
    child = session_CreateEditorLabel("about_product", _
        OSE_PRODUCT_NAME + " " + OSE_VERSION_TEXT, 18, 38)
    session_AboutAddChild child
    child = session_CreateEditorLabel("about_description", _
        "Independent MIDI and audio workstation", 18, 68)
    session_AboutAddChild child
    child = session_CreateEditorLabel("about_copyright", OSE_COPYRIGHT_TEXT, 18, 98)
    session_AboutAddChild child
    child = session_CreateEditorLabel("about_license", _
        OSE_LICENSE_EXPRESSION + ". See LICENSE and COPYING.", 18, 128)
    session_AboutAddChild child
    child = session_CreateEditorLabel("about_dependencies", _
        "Built with FreeBASIC, omaGUI, and sfxlib. See THIRD_PARTY_NOTICES.md.", _
        18, 158)
    session_AboutAddChild child
    child = button_Create("about_close", "Close", 18, 192, 90, 28, _
        @session_OnAboutClose)
    session_AboutAddChild child

    gui_SetModalRoot session_AboutWindow
    session_SetStatus OSE_PRODUCT_NAME + " " + OSE_VERSION_TEXT
End Sub


Private Sub session_LayoutToolbarWidgets(ByVal screenWidth As Integer)
    If session_NoteToolsButton <> 0 Then
        session_NoteToolsButton->y = 1
        session_NoteToolsButton->h = SESSION_MENU_HEIGHT - 2
    End If
    ' These two entry points remain visible in the menu bar even when the
    ' narrow-window layout hides the tempo and device setup controls.
    If session_DrumMachineButton <> 0 Then
        session_DrumMachineButton->y = 1
        session_DrumMachineButton->h = SESSION_MENU_HEIGHT - 2
    End If
    If session_SongMeterButton <> 0 Then
        session_SongMeterButton->y = 1
        session_SongMeterButton->h = SESSION_MENU_HEIGHT - 2
        Dim As Integer numerator = 4
        Dim As Integer denominator = 4
        Dim As Integer signatureIndex = session_TimeSignatureIndexForTick(session_ViewStartTick)
        If signatureIndex >= 0 Then
            numerator = session_Summary.timeSignatureMap(signatureIndex).numerator
            denominator = session_TempoDenominatorValue( _
                session_Summary.timeSignatureMap(signatureIndex).denominatorPower)
        End If
        Cast(ButtonData Ptr, session_SongMeterButton->data)->text = _
            "Time " + LTrim(Str(numerator)) + "/" + LTrim(Str(denominator)) + "..."
    End If
    ' The original 640-pixel layout devoted its compact toolbar to transport.
    ' Hide setup controls as a group when they cannot fit instead of clipping
    ' half-buttons against the right edge of a resized window.
    Dim As String fileNames(0 To OSE_UI_FILE_BUTTON_COUNT - 1) = { _
        "new", "open", "save" _
    }
    For buttonIndex As Integer = 0 To OSE_UI_FILE_BUTTON_COUNT - 1
        Dim As Widget Ptr fileButton = gui_FindWidget(fileNames(buttonIndex))
        If fileButton <> 0 Then
            fileButton->x = session_InteractionMetrics.fileButtonLeft(buttonIndex)
            fileButton->y = SESSION_TOOLBAR_TOP + _
                SESSION_TOOLBAR_BUTTON_TOP_INSET
            fileButton->w = session_InteractionMetrics.fileButtonWidth(buttonIndex)
            fileButton->h = SESSION_TOOLBAR_BUTTON_HEIGHT
        End If
    Next

    Dim As String transportNames( _
        0 To OSE_UI_TRANSPORT_BUTTON_COUNT - 1) = { _
        "stop", "pause", "rewind", "play", "fast_forward", _
        "live_record", "step_record" _
    }
    For buttonIndex As Integer = 0 To OSE_UI_TRANSPORT_BUTTON_COUNT - 1
        Dim As Widget Ptr transportButton = _
            gui_FindWidget(transportNames(buttonIndex))
        If transportButton <> 0 Then
            transportButton->x = _
                session_InteractionMetrics.transportButtonLeft(buttonIndex)
            transportButton->y = SESSION_TOOLBAR_TOP + _
                SESSION_TOOLBAR_BUTTON_TOP_INSET
            transportButton->w = _
                session_InteractionMetrics.transportButtonWidth(buttonIndex)
            transportButton->h = SESSION_TOOLBAR_BUTTON_HEIGHT
        End If
    Next

    Dim As Integer showSetupControls = Iif( _
        screenWidth >= 1040 AndAlso _
        session_InteractionMode = OSE_UI_INTERACTION_FINE, -1, 0)
    If session_TempoLabel <> 0 Then _
        session_TempoLabel->visible = showSetupControls
    If session_TempoBox <> 0 Then _
        session_TempoBox->visible = showSetupControls
    If session_ApplyTempoButton <> 0 Then _
        session_ApplyTempoButton->visible = showSetupControls
    If session_TempoMapButton <> 0 Then _
        session_TempoMapButton->visible = showSetupControls
    If session_MidiInputButton <> 0 Then _
        session_MidiInputButton->visible = showSetupControls
    If session_MidiOutputButton <> 0 Then _
        session_MidiOutputButton->visible = showSetupControls
End Sub


Private Sub session_LayoutPaneScrollbars( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    Dim As Integer scoreWidth = screenWidth - SESSION_SCORE_LEFT - 4
    Dim As Integer scoreHeight = screenHeight - SESSION_TOP_HEIGHT - _
        SESSION_MIXER_HEIGHT - 8
    If scoreWidth < 160 Then
        scoreWidth = 160
    End If
    If scoreHeight < 150 Then
        scoreHeight = 150
    End If
    If session_ScoreHorizontalScrollbar <> 0 Then
        session_ScoreHorizontalScrollbar->x = SESSION_SCORE_LEFT
        session_ScoreHorizontalScrollbar->y = SESSION_SCORE_TOP + scoreHeight - _
            SESSION_SCORE_SCROLLBAR_SIZE
        session_ScoreHorizontalScrollbar->w = scoreWidth - _
            SESSION_SCORE_SCROLLBAR_SIZE
        session_ScoreHorizontalScrollbar->h = SESSION_SCORE_SCROLLBAR_SIZE
    End If
    If session_ScoreVerticalScrollbar <> 0 Then
        session_ScoreVerticalScrollbar->x = SESSION_SCORE_LEFT + scoreWidth - _
            SESSION_SCORE_SCROLLBAR_SIZE
        session_ScoreVerticalScrollbar->y = SESSION_SCORE_TOP + 24
        session_ScoreVerticalScrollbar->w = SESSION_SCORE_SCROLLBAR_SIZE
        session_ScoreVerticalScrollbar->h = scoreHeight - 24 - _
            SESSION_SCORE_SCROLLBAR_SIZE
    End If
End Sub


Private Sub session_ProcessPaneScrollbars(ByVal screenHeight As Integer)
    If session_ScoreHorizontalScrollbar <> 0 AndAlso _
        session_ScoreHorizontalScrollbar->data <> 0 Then
        Dim As ScrollBarData Ptr horizontalData = Cast( _
            ScrollBarData Ptr, session_ScoreHorizontalScrollbar->data)
        Dim As ULongInt viewTicks = session_ViewTicks()
        Dim As ULongInt timelineTicks = session_TimelineDurationTicks()
        Dim As ULongInt maximumStart = _
            scoreScroll_MaximumStart(timelineTicks, viewTicks)
        horizontalData->max_val = IIf(maximumStart > 0, _
            SESSION_SCORE_SCROLL_RANGE, 0)
        horizontalData->page_size = SESSION_SCORE_SCROLL_PAGE
        If horizontalData->value <> session_LastScoreHorizontalValue AndAlso _
            maximumStart > 0 Then
            horizontalData->value = scoreScroll_ClampValue( _
                horizontalData->value, SESSION_SCORE_SCROLL_RANGE)
            session_ViewStartTick = scoreScroll_ValueToTick( _
                maximumStart, horizontalData->value, _
                SESSION_SCORE_SCROLL_RANGE)
        ElseIf maximumStart > 0 Then
            If session_ViewStartTick > maximumStart Then _
                session_ViewStartTick = maximumStart
            horizontalData->value = scoreScroll_TickToValue( _
                maximumStart, session_ViewStartTick, _
                SESSION_SCORE_SCROLL_RANGE)
        Else
            horizontalData->value = 0
        End If
        session_LastScoreHorizontalValue = horizontalData->value
    End If

    If session_ScoreVerticalScrollbar <> 0 AndAlso _
        session_ScoreVerticalScrollbar->data <> 0 Then
        Dim As ScrollBarData Ptr verticalData = Cast( _
            ScrollBarData Ptr, session_ScoreVerticalScrollbar->data)
        Dim As Integer visibleTracks = session_ScoreVisibleTrackCount(screenHeight)
        Dim As Integer maximumFirst = scoreScroll_MaximumFirstTrack( _
            session_Summary.trackCount, visibleTracks)
        verticalData->max_val = maximumFirst
        verticalData->page_size = visibleTracks
        If verticalData->value <> session_LastScoreVerticalValue Then
            verticalData->value = scoreScroll_ClampFirstTrack( _
                verticalData->value, maximumFirst)
            session_ScoreFirstVisibleTrack = verticalData->value
            If session_SelectedTrack < session_ScoreFirstVisibleTrack OrElse _
                session_SelectedTrack >= _
                    session_ScoreFirstVisibleTrack + visibleTracks Then
                session_SelectTrack session_ScoreFirstVisibleTrack
            End If
        Else
            verticalData->value = scoreScroll_ClampFirstTrack( _
                session_ScoreFirstTrackIndex(screenHeight), maximumFirst)
        End If
        session_LastScoreVerticalValue = verticalData->value
    End If
End Sub


' -------------------------------------------------------------------------
' Widget assembly and application loop
' -------------------------------------------------------------------------

Private Function session_TransportButtonIsActive(ByVal widgetName As String) As Integer
    Select Case widgetName
        Case "pause"
            Return session_Paused
        Case "play"
            Return IIf(session_Playing <> 0 AndAlso session_Paused = 0, -1, 0)
        Case "fast_forward"
            Return IIf(session_PlaybackSpeedScale > 1.0, -1, 0)
        Case "live_record"
            Return session_LiveRecording
        Case "step_record"
            Dim As Integer channelIndex = session_SelectedTrack
            If channelIndex >= 0 AndAlso channelIndex < SESSION_CHANNEL_COUNT Then _
                Return session_MixerChannels.record(channelIndex)
    End Select
    Return 0
End Function


Private Sub session_RenderToolbarTextButton(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then
        Exit Sub
    End If

    Dim As ButtonData Ptr buttonState = Cast(ButtonData Ptr, w->data)
    Dim As OseUiControlStyle controlStyle
    uiStyle_Toolbar controlStyle, session_ThemePalette, _
        buttonState->state, 0, 0
    session_DrawRoundedControl w->ax, w->ay, w->w, w->h, controlStyle
    backend_PrintAligned w->ax, w->ay, w->w, w->h, _
        controlStyle.contentColor, buttonState->text, BACKEND_FONT_DEFAULT, _
        BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE
End Sub


Private Function session_TransportIconId( _
    ByVal buttonName As String _
) As Integer
    Select Case buttonName
        Case "stop"
            Return OSE_UI_ICON_STOP
        Case "pause"
            Return OSE_UI_ICON_PAUSE
        Case "rewind"
            Return OSE_UI_ICON_REWIND
        Case "play"
            Return OSE_UI_ICON_PLAY
        Case "fast_forward"
            Return OSE_UI_ICON_FORWARD
        Case "live_record"
            Return OSE_UI_ICON_RECORD
        Case "step_record"
            Return OSE_UI_ICON_STEP
    End Select
    Return -1
End Function


Private Sub session_RenderTransportButton(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then
        Exit Sub
    End If

    Dim As ButtonData Ptr buttonState = Cast(ButtonData Ptr, w->data)
    Dim As OseUiControlStyle controlStyle
    uiStyle_Toolbar controlStyle, session_ThemePalette, _
        buttonState->state, -1, _
        session_TransportButtonIsActive(w->name)
    session_DrawRoundedControl w->ax, w->ay, w->w, w->h, controlStyle

    Dim As Integer pressedOffset = 0
    If buttonState <> 0 AndAlso buttonState->state = 2 Then
        pressedOffset = 1
    End If

    Dim As Integer iconLeft = w->ax + uiIcons_CenteredOffset(w->w) + _
        pressedOffset
    Dim As Integer iconTop = w->ay + uiIcons_CenteredOffset(w->h) + _
        pressedOffset
    Dim As Integer iconId = session_TransportIconId(w->name)
    Dim As ULong iconColor = controlStyle.contentColor
    If w->name = "live_record" Then
        iconColor = session_ThemePalette.dangerColor
    End If
    session_DrawUiIcon iconId, iconLeft, iconTop, iconColor
End Sub


Private Sub session_AddToolbarTextButton( _
    ByVal widgetName As String, _
    ByVal buttonText As String, _
    ByVal buttonLeft As Integer, _
    ByVal buttonTop As Integer, _
    ByVal buttonWidth As Integer, _
    ByVal buttonHeight As Integer, _
    ByVal clickHandler As Any Ptr _
)
    Dim As Widget Ptr toolbarButton = button_Create( _
        widgetName, buttonText, buttonLeft, buttonTop, buttonWidth, _
        buttonHeight, clickHandler)
    If toolbarButton = 0 Then
        Exit Sub
    End If
    toolbarButton->render = @session_RenderToolbarTextButton
    gui_AddWidget toolbarButton
End Sub


Private Sub session_AddTransportButton( _
    ByVal widgetName As String, ByVal buttonLeft As Integer, _
    ByVal buttonWidth As Integer, ByVal clickHandler As Any Ptr _
)
    Dim As Widget Ptr transportButton = button_Create( _
        widgetName, "", buttonLeft, _
        SESSION_TOOLBAR_TOP + SESSION_TOOLBAR_BUTTON_TOP_INSET, _
        buttonWidth, SESSION_TOOLBAR_BUTTON_HEIGHT, clickHandler _
    )
    If transportButton = 0 Then
        Exit Sub
    End If

    transportButton->render = @session_RenderTransportButton
    gui_AddWidget transportButton
End Sub


Private Sub session_AppendControlAuditError( _
    ByRef errorText As String, _
    ByVal nextError As String _
)
    If Len(errorText) >= 2048 Then
        Exit Sub
    End If
    If errorText <> "" Then
        errorText += " | "
    End If
    errorText += nextError
    If Len(errorText) > 2048 Then
        errorText = Left(errorText, 2048)
    End If
End Sub


Private Sub session_AuditActionButton( _
    ByVal buttonName As String, _
    ByVal expectedHandler As Any Ptr, _
    ByRef actionCount As Integer, _
    ByRef errorText As String _
)
    Dim As Widget Ptr buttonWidget = gui_FindWidget(buttonName)
    If buttonWidget = 0 OrElse buttonWidget->data = 0 Then
        session_AppendControlAuditError errorText, _
            "missing button " + buttonName
        Exit Sub
    End If

    Dim As ButtonData Ptr buttonData = Cast(ButtonData Ptr, buttonWidget->data)
    If buttonData->clickHandler = 0 Then
        session_AppendControlAuditError errorText, _
            "button has no action " + buttonName
    ElseIf buttonData->clickHandler <> expectedHandler Then
        session_AppendControlAuditError errorText, _
            "button has wrong action " + buttonName
    ElseIf buttonWidget->update = 0 OrElse buttonWidget->render = 0 Then
        session_AppendControlAuditError errorText, _
            "button has no interaction path " + buttonName
    Else
        actionCount += 1
    End If
End Sub


Private Sub session_AuditBehavior( _
    ByVal conditionState As Integer, _
    ByVal failureText As String, _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    If conditionState = 0 Then
        session_AppendControlAuditError errorText, failureText
    Else
        behaviorCheckCount += 1
    End If
End Sub


Private Sub session_AuditTextControl( _
    ByVal textWidget As Widget Ptr, _
    ByVal expectedName As String, _
    ByVal expectedParent As Widget Ptr, _
    ByRef textControlCount As Integer, _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    Dim As TextBoxData Ptr textData
    Dim As String originalText
    Dim As Integer pointerX
    Dim As Integer pointerY
    Dim As Integer structureValid = -1

    If textWidget = 0 OrElse gui_FindWidget(expectedName) <> textWidget Then
        session_AppendControlAuditError errorText, _
            "missing text control " + expectedName
        Exit Sub
    End If

    If textWidget->name <> expectedName OrElse textWidget->data = 0 OrElse _
        textWidget->parent <> expectedParent OrElse _
        textWidget->update <> @textbox_Update OrElse _
        textWidget->render <> @textbox_Render OrElse _
        textWidget->destroy <> @textbox_Destroy OrElse _
        textWidget->accepts_focus = 0 OrElse _
        textWidget->visible = 0 OrElse textWidget->enabled = 0 Then
        structureValid = 0
    End If

    input_MockMouse -1, -1, 0
    gui_UpdateAll()
    If textWidget->evis = 0 OrElse textWidget->een = 0 Then _
        structureValid = 0

    If structureValid = 0 Then
        session_AppendControlAuditError errorText, _
            "unwired text control " + expectedName
        Exit Sub
    End If
    textControlCount += 1

    textData = Cast(TextBoxData Ptr, textWidget->data)
    originalText = textData->text
    pointerX = textWidget->ax + 4
    pointerY = textWidget->ay + textWidget->h \ 2

    input_MockMouse pointerX, pointerY, 1
    gui_UpdateAll()
    session_AuditBehavior gui_GetFocus() = textWidget AndAlso _
        textData->active <> 0, _
        "pointer did not focus text control " + expectedName, _
        behaviorCheckCount, errorText

    input_MockMouse pointerX, pointerY, 0
    gui_UpdateAll()
    input_MockText "~"
    gui_UpdateAll()
    session_AuditBehavior Len(textData->text) = Len(originalText) + 1, _
        "typed input did not edit text control " + expectedName, _
        behaviorCheckCount, errorText

    ' Each dialog is a test fixture. Restore its exact value and empty history
    ' so the audit cannot influence the semantic action tests which follow.
    textbox_SetText textWidget, originalText, -1
    textData->active = 0
    gui_SetFocus 0
End Sub


Private Sub session_AuditListControl( _
    ByVal listWidget As Widget Ptr, _
    ByVal expectedName As String, _
    ByVal expectedParent As Widget Ptr, _
    ByRef listControlCount As Integer, _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    Dim As ListBoxData Ptr listData
    Dim As Integer originalActivationCount
    Dim As Integer originalScrollTop
    Dim As Integer originalSelectedIndex
    Dim As Integer pointerX
    Dim As Integer pointerY
    Dim As Integer structureValid = -1

    If listWidget = 0 OrElse gui_FindWidget(expectedName) <> listWidget Then
        session_AppendControlAuditError errorText, _
            "missing list control " + expectedName
        Exit Sub
    End If

    If listWidget->name <> expectedName OrElse listWidget->data = 0 OrElse _
        listWidget->parent <> expectedParent OrElse _
        listWidget->update <> @listbox_Update OrElse _
        listWidget->render <> @listbox_Render OrElse _
        listWidget->destroy <> @listbox_Destroy OrElse _
        listWidget->accepts_focus = 0 OrElse _
        listWidget->visible = 0 OrElse listWidget->enabled = 0 Then
        structureValid = 0
    End If

    input_MockMouse -1, -1, 0
    gui_UpdateAll()
    If listWidget->evis = 0 OrElse listWidget->een = 0 Then _
        structureValid = 0

    If structureValid = 0 Then
        session_AppendControlAuditError errorText, _
            "unwired list control " + expectedName
        Exit Sub
    End If
    listControlCount += 1

    listData = Cast(ListBoxData Ptr, listWidget->data)
    originalSelectedIndex = listData->selected_index
    originalScrollTop = listData->scroll_top
    originalActivationCount = listData->activation_count
    listData->scroll_top = 0
    pointerX = listWidget->ax + 4
    pointerY = listWidget->ay + 4

    input_MockMouse pointerX, pointerY, 1
    gui_UpdateAll()
    session_AuditBehavior gui_GetFocus() = listWidget, _
        "pointer did not focus list control " + expectedName, _
        behaviorCheckCount, errorText

    input_MockMouse pointerX, pointerY, 0
    gui_UpdateAll()
    If listData->item_count > 0 Then
        session_AuditBehavior listData->selected_index = 0 AndAlso _
            listData->activation_count = originalActivationCount + 1, _
            "pointer did not select list row in " + expectedName, _
            behaviorCheckCount, errorText
    Else
        session_AuditBehavior _
            listData->selected_index = originalSelectedIndex AndAlso _
            listData->activation_count = originalActivationCount, _
            "empty list fabricated a selection in " + expectedName, _
            behaviorCheckCount, errorText
    End If

    listData->selected_index = originalSelectedIndex
    listData->scroll_top = originalScrollTop
    listData->activation_count = originalActivationCount
    listData->pointer_latch = 0
    listData->pointer_index = -1
    gui_SetFocus 0
End Sub


Private Sub session_AuditCloseFileDialog()
    ' Semantic menu tests create the real omaGUI dialogs but do not drive the
    ' native filesystem picker. Remove the complete generated tree exactly as
    ' the normal result path does before exercising the next modal command.
    If session_FileDialog = 0 Then
        Exit Sub
    End If
    Dim As String dialogName = session_FileDialog->name
    gui_RemoveWidget dialogName
    gui_ClearModalRoot()
    session_FileDialog = 0
    session_FileDialogMode = SESSION_DIALOG_NONE
End Sub


Private Sub session_AuditMockScoreClick( _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    input_MockMouse pointerX, pointerY, 1
    input_Update()
    session_UpdateScoreInput screenWidth, screenHeight
    input_MockMouse pointerX, pointerY, 0
    input_Update()
    session_UpdateScoreInput screenWidth, screenHeight
End Sub


Private Sub session_AuditMockTouchPair( _
    ByVal firstX As Integer, _
    ByVal firstY As Integer, _
    ByVal secondX As Integer, _
    ByVal secondY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    input_MockMouse -1, -1, 0
    input_MockTouch 0, firstX, firstY, 101
    input_MockTouch 1, secondX, secondY, 202
    input_MockTouchCount 2
    input_Update()
    session_UpdateScoreInput screenWidth, screenHeight
End Sub


Private Sub session_AuditReleaseTouches( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    input_MockTouchCount 0
    input_Update()
    session_UpdateScoreInput screenWidth, screenHeight
End Sub


Private Sub session_AuditMockMixerPress( _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    input_MockMouse pointerX, pointerY, 1
    input_Update()
    session_UpdateMixerInput screenWidth, screenHeight
End Sub


Private Sub session_AuditMockMixerRelease( _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    input_MockMouse pointerX, pointerY, 0
    input_Update()
    session_UpdateMixerInput screenWidth, screenHeight
End Sub


Private Sub session_AuditMockMixerClick( _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    session_AuditMockMixerPress pointerX, pointerY, screenWidth, screenHeight
    session_AuditMockMixerRelease pointerX, pointerY, screenWidth, screenHeight
End Sub


Private Function session_AuditMixerMidiValue( _
    ByVal controlKind As Integer, _
    ByVal channelIndex As Integer _
) As Integer
    If channelIndex < 0 OrElse channelIndex >= SESSION_CHANNEL_COUNT Then _
        Return -1
    Select Case controlKind
        Case OSE_MIXER_CONTROL_CHANNEL_FADER
            Return session_Summary.channelVolume(channelIndex)
        Case OSE_MIXER_CONTROL_CHANNEL_CHORUS
            Return session_Summary.channelChorus(channelIndex)
        Case OSE_MIXER_CONTROL_CHANNEL_REVERB
            Return session_Summary.channelReverb(channelIndex)
        Case OSE_MIXER_CONTROL_CHANNEL_PAN
            Return session_Summary.channelPan(channelIndex)
    End Select
    Return -1
End Function


Private Sub session_AuditSemanticMenuRoutes( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    /'
        Opening the concrete window through each menu proves more than callback
        identity: the selected index must route to the promised application
        context and establish modal ownership. Each window is closed before
        the next route so one modal cannot make a later command appear broken.
    '/
    session_OnOptionsMenu 0
    session_AuditBehavior session_TempoMapWindow <> 0, _
        "Options tempo-map command did not open its editor", _
        behaviorCheckCount, errorText
    session_CloseTempoMapWindow()
    session_OnOptionsMenu 1
    session_AuditBehavior session_AutomationWindow <> 0, _
        "Options MIDI-events command did not open its editor", _
        behaviorCheckCount, errorText
    session_CloseAutomationWindow()
    session_OnOptionsMenu 2
    session_AuditBehavior session_AudioWindow <> 0, _
        "Options audio command did not open its editor", _
        behaviorCheckCount, errorText
    session_CloseAudioWindow()
    session_OnOptionsMenu 3
    session_AuditBehavior session_KeyboardWindow <> 0, _
        "Options keyboard command did not open its editor", _
        behaviorCheckCount, errorText
    session_CloseKeyboardWindow()
    session_OnOptionsMenu 4
    session_AuditBehavior session_MicWindow <> 0, _
        "Options microphone command did not open its editor", _
        behaviorCheckCount, errorText
    session_CloseMicWindow()

    ' Theme entries are ordinary menu commands, not startup-only paint flags.
    ' Exercise the actual route and verify both the active palette and the
    ' mutually exclusive menu mark before restoring the user's original mode.
    Dim As Integer originalThemeMode = session_ThemeMode
    Dim As MenuData Ptr themeMenuState = 0
    If session_OptionsMenu <> 0 Then _
        themeMenuState = Cast(MenuData Ptr, session_OptionsMenu->data)
    For themeMode As Integer = OSE_UI_THEME_LIGHT To OSE_UI_THEME_BLACK
        Dim As OseUiThemePalette expectedTheme
        uiStyle_EditorTheme expectedTheme, themeMode
        session_OnOptionsMenu 5 + themeMode
        Dim As Integer preferenceIsCorrect = -1
        If session_PreferencesEnabled <> 0 Then
            Dim As OseUserPreferences storedPreferences
            preferenceIsCorrect = _
                userPreferences_Load( _
                    session_PreferencesFilename, storedPreferences) = _
                    OSE_PREFERENCES_LOAD_OK AndAlso _
                storedPreferences.themeMode = themeMode
        End If
        Dim As Integer menuMarkIsCorrect
        If themeMenuState <> 0 AndAlso themeMenuState->count >= 8 Then
            menuMarkIsCorrect = Left(themeMenuState->items(5 + themeMode), 3) = _
                "[x]"
        End If
        session_AuditBehavior _
            session_ThemeMode = themeMode AndAlso _
            session_ThemePalette.windowColor = expectedTheme.windowColor AndAlso _
            session_ThemePalette.textColor = expectedTheme.textColor AndAlso _
            menuMarkIsCorrect <> 0 AndAlso _
            preferenceIsCorrect <> 0 AndAlso _
            session_StatusText = uiStyle_ThemeName(themeMode) + _
                " theme selected.", _
            "Options did not apply, mark, and persist the " + _
                uiStyle_ThemeName(themeMode) + " theme", _
            behaviorCheckCount, errorText
    Next
    ' Restore both the active palette and the retained preference before the
    ' interaction-profile audit. Saving a later interaction change must never
    ' resurrect the temporary Black theme used by the checks above.
    session_ApplyTheme originalThemeMode, -1

    Dim As Integer originalInteractionMode = session_InteractionMode
    Dim As Integer toggledInteractionMode = IIf( _
        originalInteractionMode = OSE_UI_INTERACTION_TOUCH, _
        OSE_UI_INTERACTION_FINE, OSE_UI_INTERACTION_TOUCH)
    session_OnOptionsMenu 8
    Dim As Integer interactionPreferenceIsCorrect = -1
    If session_PreferencesEnabled <> 0 Then
        Dim As OseUserPreferences storedInteractionPreferences
        interactionPreferenceIsCorrect = userPreferences_Load( _
            session_PreferencesFilename, storedInteractionPreferences) = _
            OSE_PREFERENCES_LOAD_OK AndAlso _
            storedInteractionPreferences.interactionMode = _
                toggledInteractionMode
    End If
    session_AuditBehavior _
        session_InteractionMode = toggledInteractionMode AndAlso _
        themeMenuState <> 0 AndAlso themeMenuState->count >= 9 AndAlso _
        Left(themeMenuState->items(8), 3) = IIf( _
            toggledInteractionMode = OSE_UI_INTERACTION_TOUCH, _
            "[x]", "[ ]") AndAlso _
        interactionPreferenceIsCorrect <> 0, _
        "Options did not apply, mark, and persist the interaction profile", _
        behaviorCheckCount, errorText
    session_OnOptionsMenu 8
    session_AuditBehavior _
        session_InteractionMode = originalInteractionMode, _
        "Options did not restore the original interaction profile", _
        behaviorCheckCount, errorText

    session_OnOptionsMenu 9
    session_AuditBehavior session_FileDialog <> 0 AndAlso _
        session_FileDialogMode = SESSION_DIALOG_SOUNDFONT, _
        "Options SoundFont command did not open its bank chooser", _
        behaviorCheckCount, errorText
    If session_FileDialog <> 0 Then
        Dim As String soundFontDialogName = session_FileDialog->name
        gui_RemoveWidget soundFontDialogName
        gui_ClearModalRoot()
        session_FileDialog = 0
        session_FileDialogMode = SESSION_DIALOG_NONE
    End If
    session_OnOptionsMenu 10
    session_AuditBehavior soundfontSynth_IsActive() = 0 AndAlso _
        session_StatusText = "The built-in software synth is already selected.", _
        "Options built-in synth command did not retain the fallback engine", _
        behaviorCheckCount, errorText

    session_OnSetupMenu 0
    session_AuditBehavior session_MidiInputWindow <> 0, _
        "Setup MIDI-input command did not open its chooser", _
        behaviorCheckCount, errorText
    session_CloseMidiInputWindow()
    session_OnSetupMenu 1
    session_AuditBehavior session_MidiOutputWindow <> 0, _
        "Setup MIDI-output command did not open its chooser", _
        behaviorCheckCount, errorText
    session_CloseMidiOutputWindow()
    Dim As Integer originalAudioGeneration = sfxRuntime_GetGeneration()
    session_OnSetupMenu 4
    session_AuditBehavior _
        sfxRuntime_GetGeneration() <> originalAudioGeneration AndAlso _
        session_StatusText = "Audio engine restarted.", _
        "Setup restart-audio command did not rebuild the sound runtime", _
        behaviorCheckCount, errorText
    session_OnSetupMenu 2
    session_AuditBehavior session_TrackWindow <> 0, _
        "Setup document-information command did not open its editor", _
        behaviorCheckCount, errorText
    session_CloseTrackPropertiesWindow()
    session_OnWindowMenu SESSION_VIEW_MIDI_EVENTS
    session_AuditBehavior session_AutomationWindow <> 0, _
        "Window MIDI-event command did not open its editor", _
        behaviorCheckCount, errorText
    session_CloseAutomationWindow()
    session_OnTrackMenu 2
    session_AuditBehavior session_TrackWindow <> 0, _
        "Track properties command did not open its editor", _
        behaviorCheckCount, errorText
    session_CloseTrackPropertiesWindow()
    session_OnHelpMenu 0
    session_AuditBehavior session_AboutWindow <> 0 AndAlso _
        session_StatusText = OSE_PRODUCT_NAME + " " + OSE_VERSION_TEXT, _
        "Help command did not open versioned About information", _
        behaviorCheckCount, errorText
    session_CloseAboutWindow()

    ' Every File command that promises a picker must open the expected dialog
    ' mode. No path is selected, so the audit cannot write user or fixture data.
    Dim As Integer fileMenuIndices(0 To 4) = {1, 2, 3, 4, 5}
    Dim As Integer fileDialogModes(0 To 4) = { _
        SESSION_DIALOG_OPEN, SESSION_DIALOG_MIDI_SAVE, _
        SESSION_DIALOG_PROJECT_SAVE, SESSION_DIALOG_MOD_EXPORT, _
        SESSION_DIALOG_WAV_EXPORT _
    }
    For fileRoute As Integer = 0 To 4
        session_OnFileMenu fileMenuIndices(fileRoute)
        session_AuditBehavior session_FileDialog <> 0 AndAlso _
            session_FileDialogMode = fileDialogModes(fileRoute), _
            "File menu opened the wrong dialog for index " + _
            Str(fileMenuIndices(fileRoute)), behaviorCheckCount, errorText
        session_AuditCloseFileDialog()
    Next
End Sub


Private Sub session_AuditPressViewShortcut( _
    ByVal scanCode As Integer, _
    ByVal includeShift As Integer _
)
    input_ResetForTest()
    session_ProcessViewShortcuts()
    input_MockKey FB.SC_CONTROL, -1
    If includeShift <> 0 Then
        input_MockKey FB.SC_LSHIFT, -1
    End If
    input_MockKey scanCode, -1
    session_ProcessViewShortcuts()
    input_ResetForTest()
    session_ProcessViewShortcuts()
End Sub


Private Sub session_AuditSemanticViewWorkflow( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    /'
        View commands are navigation only. They may change score geometry and
        anchors, but must leave the document and note selection untouched.
        The same checks run through menu indices and keyboard shortcuts.
    '/
    Dim As ULongInt originalViewStartTick = session_ViewStartTick
    Dim As Integer originalViewBeatCount = session_ViewBeatCount
    Dim As Integer originalTrackRowHeight = session_ScoreTrackRowHeight
    Dim As Integer originalFirstVisibleTrack = session_ScoreFirstVisibleTrack
    Dim As NoteSelectionState originalSelection = session_NoteSelection
    Dim As Integer originalSelectedNote = session_SelectedNote

    If midi_GetEditableNoteCount() >= 2 Then
        session_SelectOnlyNote 0
        noteSelection_Add session_NoteSelection, 1, 0
        session_SelectedNote = session_NoteSelection.primaryNoteIndex
    End If
    Dim As NoteSelectionSummary selectionSummary
    Dim As Integer hasSelectionSummary = _
        noteSelection_Summarize(session_NoteSelection, selectionSummary)

    ' The position display must follow the document meter instead of assuming
    ' four quarter-note beats. Four quarters into 3/4 is measure 2, beat 2.
    Dim As Integer originalTimeSignatureCount = _
        session_Summary.timeSignatureCount
    Dim As MidiTimeSignaturePoint originalTimeSignature
    If originalTimeSignatureCount > 0 Then _
        originalTimeSignature = session_Summary.timeSignatureMap(0)
    session_Summary.timeSignatureCount = 1
    With session_Summary.timeSignatureMap(0)
        .tick = 0
        .numerator = 3
        .denominatorPower = 2
        .clocksPerMetronome = 24
        .thirtySecondNotesPerQuarter = 8
    End With
    Dim As ULongInt auditMeasure
    Dim As ULongInt auditBeat
    Dim As ULongInt auditSubTick
    session_MusicalPosition CULngInt(session_Summary.division) * 4, _
        auditMeasure, auditBeat, auditSubTick
    session_AuditBehavior auditMeasure = 2 AndAlso auditBeat = 2 AndAlso _
        auditSubTick = 0, _
        "Musical position display assumed 4/4 in a 3/4 document", _
        behaviorCheckCount, errorText
    session_Summary.timeSignatureCount = originalTimeSignatureCount
    If originalTimeSignatureCount > 0 Then _
        session_Summary.timeSignatureMap(0) = originalTimeSignature

    session_ViewBeatCount = SESSION_SCORE_BEATS
    session_OnWindowMenu SESSION_VIEW_ZOOM_IN
    session_AuditBehavior _
        session_ViewBeatCount = SESSION_SCORE_BEATS \ 2, _
        "View Zoom In did not increase time detail", _
        behaviorCheckCount, errorText
    session_OnWindowMenu SESSION_VIEW_ZOOM_NORMAL
    session_AuditBehavior session_ViewBeatCount = SESSION_SCORE_BEATS, _
        "View Zoom Normal did not restore the standard time scale", _
        behaviorCheckCount, errorText
    session_OnWindowMenu SESSION_VIEW_ZOOM_OUT
    session_AuditBehavior _
        session_ViewBeatCount = SESSION_SCORE_BEATS * 2, _
        "View Zoom Out did not decrease time detail", _
        behaviorCheckCount, errorText

    session_OnWindowMenu SESSION_VIEW_ZOOM_SELECTION
    session_AuditBehavior hasSelectionSummary <> 0 AndAlso _
        session_ViewStartTick <= selectionSummary.startTick AndAlso _
        session_ViewStartTick + session_ViewTicks() >= _
            selectionSummary.endTick, _
        "View Zoom Selection did not contain the selected phrase", _
        behaviorCheckCount, errorText
    session_OnWindowMenu SESSION_VIEW_FIT_PROJECT
    session_AuditBehavior session_ViewStartTick = 0 AndAlso _
        session_ViewTicks() >= session_TimelineDurationTicks(), _
        "View Fit Project did not contain the complete timeline", _
        behaviorCheckCount, errorText
    session_OnWindowMenu SESSION_VIEW_FIT_TRACKS
    Dim As Integer screenWidth
    Dim As Integer screenHeight
    backend_GetSize screenWidth, screenHeight
    Dim As Integer fittedVisibleTracks = _
        session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer largerHeightFits
    If session_ScoreTrackRowHeight < SESSION_SCORE_TRACK_ROW_HEIGHT_MAXIMUM Then
        session_ScoreTrackRowHeight += 1
        largerHeightFits = IIf(session_ScoreVisibleTrackCount(screenHeight) >= _
            session_Summary.trackCount, -1, 0)
        session_ScoreTrackRowHeight -= 1
    End If
    session_AuditBehavior session_ScoreFirstVisibleTrack = 0 AndAlso _
        (fittedVisibleTracks >= session_Summary.trackCount OrElse _
        session_ScoreTrackRowHeight = _
            SESSION_SCORE_TRACK_ROW_HEIGHT_MINIMUM) AndAlso _
        largerHeightFits = 0, _
        "View Fit Tracks did not choose the largest complete track view", _
        behaviorCheckCount, errorText

    session_ViewBeatCount = SESSION_SCORE_BEATS
    session_AuditPressViewShortcut FB.SC_1, 0
    session_AuditBehavior _
        session_ViewBeatCount = SESSION_SCORE_BEATS \ 2, _
        "Ctrl+1 did not route to Zoom In", behaviorCheckCount, errorText
    session_AuditPressViewShortcut FB.SC_2, 0
    session_AuditBehavior session_ViewBeatCount = SESSION_SCORE_BEATS, _
        "Ctrl+2 did not route to Zoom Normal", behaviorCheckCount, errorText
    session_AuditPressViewShortcut FB.SC_3, 0
    session_AuditBehavior _
        session_ViewBeatCount = SESSION_SCORE_BEATS * 2, _
        "Ctrl+3 did not route to Zoom Out", behaviorCheckCount, errorText
    session_AuditPressViewShortcut FB.SC_E, 0
    session_AuditBehavior hasSelectionSummary <> 0 AndAlso _
        session_ViewStartTick <= selectionSummary.startTick AndAlso _
        session_ViewStartTick + session_ViewTicks() >= _
            selectionSummary.endTick, _
        "Ctrl+E did not route to Zoom Selection", _
        behaviorCheckCount, errorText
    session_AuditPressViewShortcut FB.SC_F, 0
    session_AuditBehavior session_ViewStartTick = 0 AndAlso _
        session_ViewTicks() >= session_TimelineDurationTicks(), _
        "Ctrl+F did not route to Fit Project", behaviorCheckCount, errorText
    session_ScoreFirstVisibleTrack = 1
    session_AuditPressViewShortcut FB.SC_F, -1
    session_AuditBehavior session_ScoreFirstVisibleTrack = 0, _
        "Ctrl+Shift+F did not route to Fit Tracks", _
        behaviorCheckCount, errorText

    session_ViewStartTick = originalViewStartTick
    session_ViewBeatCount = originalViewBeatCount
    session_ScoreTrackRowHeight = originalTrackRowHeight
    session_ScoreFirstVisibleTrack = originalFirstVisibleTrack
    session_NoteSelection = originalSelection
    session_SelectedNote = originalSelectedNote
    session_LastViewShortcutMask = 0
    session_InvalidateInterfaceCaches()
    input_ResetForTest()
End Sub


Private Sub session_AuditSemanticTransportAndDialogs( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    session_OnPlay 0
    session_StartAuditionPitch 60
    session_AuditBehavior session_Playing <> 0 AndAlso session_Paused = 0 _
        AndAlso session_AuditionChannelForPitch(60) < 0 AndAlso _
        session_StatusText = _
            "Stop playback before auditioning keyboard keys.", _
        "Play did not start safely or allowed keyboard audition to claim a transport voice", _
        behaviorCheckCount, errorText
    session_OnPause 0
    session_AuditBehavior session_Paused <> 0, _
        "Pause did not suspend active transport", behaviorCheckCount, errorText
    session_OnPause 0
    session_AuditBehavior session_Paused = 0, _
        "Pause did not resume suspended transport", behaviorCheckCount, errorText
    Dim As Double runningElapsed = session_PlaybackElapsed
    Dim As ULongInt runningTick = session_PlaybackLastTick
    session_OnFastForward 0
    session_AuditBehavior session_Playing <> 0 AndAlso session_Paused = 0 _
        AndAlso session_PlaybackSpeedScale = 1.0 AndAlso _
        session_PlaybackElapsed = runningElapsed AndAlso _
        session_PlaybackLastTick = runningTick AndAlso _
        session_TransportButtonIsActive("fast_forward") = 0 AndAlso _
        session_StatusText = "Press Stop before changing playback speed or tempo.", _
        "Fast Forward changed an active run instead of requiring Stop", _
        behaviorCheckCount, errorText
    session_OnStop 0
    session_AuditBehavior session_Playing = 0 AndAlso session_Paused = 0 AndAlso _
        session_PlaybackSpeedScale = 1.0, _
        "Stop did not reset transport", behaviorCheckCount, errorText
    Dim As ULongInt stoppedViewTick = session_ViewStartTick
    session_OnFastForward 0
    session_AuditBehavior session_Playing = 0 AndAlso session_Paused = 0 AndAlso _
        session_PlaybackSpeedScale = 4.0 AndAlso _
        session_ViewStartTick = stoppedViewTick AndAlso _
        session_TransportButtonIsActive("fast_forward") <> 0, _
        "Stopped Fast Forward did not visibly select the next run's speed", _
        behaviorCheckCount, errorText
    session_OnPlay 0
    session_AuditBehavior session_Playing <> 0 AndAlso _
        session_PlaybackSpeedScale = 4.0 AndAlso _
        session_TransportButtonIsActive("fast_forward") <> 0, _
        "Play discarded the speed selected while stopped", _
        behaviorCheckCount, errorText
    session_OnPause 0
    runningElapsed = session_PlaybackElapsed
    runningTick = session_PlaybackLastTick
    session_OnFastForward 0
    session_AuditBehavior session_Playing <> 0 AndAlso session_Paused <> 0 _
        AndAlso session_PlaybackSpeedScale = 4.0 AndAlso _
        session_PlaybackElapsed = runningElapsed AndAlso _
        session_PlaybackLastTick = runningTick AndAlso _
        session_TransportButtonIsActive("fast_forward") <> 0 AndAlso _
        session_StatusText = "Press Stop before changing playback speed or tempo.", _
        "Paused Fast Forward changed retained voices or its selected indicator", _
        behaviorCheckCount, errorText
    session_OnPause 0
    input_ResetForTest()
    session_LastFunctionShortcutMask = 0
    input_MockKey FB.SC_F4, -1
    session_ProcessTransportShortcuts()
    session_AuditBehavior session_Playing <> 0 AndAlso session_Paused = 0 _
        AndAlso session_PlaybackSpeedScale = 4.0 AndAlso _
        session_PlaybackElapsed = runningElapsed AndAlso _
        session_TransportButtonIsActive("fast_forward") <> 0 AndAlso _
        session_StatusText = "Press Stop before changing playback speed or tempo.", _
        "F4 bypassed the active-transport timing boundary", _
        behaviorCheckCount, errorText
    input_ResetForTest()
    session_LastFunctionShortcutMask = 0
    session_OnStop 0
    session_OnFastForward 0
    session_OnFastForward 0
    session_AuditBehavior session_Playing = 0 AndAlso _
        session_PlaybackSpeedScale = 1.0 AndAlso _
        session_TransportButtonIsActive("fast_forward") = 0, _
        "Stopped Fast Forward did not restore the normal-speed selection", _
        behaviorCheckCount, errorText
    session_ViewStartTick = 1
    session_OnRewind 0
    session_AuditBehavior session_ViewStartTick = 0, _
        "Rewind did not return the score to tick zero", _
        behaviorCheckCount, errorText
    session_OnStepRecord 0
    Dim As Integer auditRecordChannel = session_RecordChannel()
    session_OnStepRecord 0
    session_AuditBehavior auditRecordChannel >= 0 AndAlso _
        session_RecordChannel() < 0, _
        "Step button did not arm and disarm one mixer channel", _
        behaviorCheckCount, errorText

    session_OnKeyboard 0
    Dim As Integer originalKeyboardBase = session_KeyboardBasePitch
    session_OnKeyboardOctaveDown 0
    session_AuditBehavior _
        session_KeyboardBasePitch = originalKeyboardBase - 12, _
        "Keyboard Octave - did not lower the pitch map", _
        behaviorCheckCount, errorText
    session_OnKeyboardOctaveUp 0
    session_AuditBehavior session_KeyboardBasePitch = originalKeyboardBase, _
        "Keyboard Octave + did not restore the pitch map", _
        behaviorCheckCount, errorText
    session_OnKeyboardRecord 0
    session_AuditBehavior session_LiveRecording <> 0 AndAlso _
        session_LiveRecordingKeyboardOnly <> 0, _
        "Keyboard Record did not start keyboard-only recording", _
        behaviorCheckCount, errorText
    session_OnKeyboardRecord 0
    session_AuditBehavior session_LiveRecording = 0, _
        "Keyboard Record did not stop active recording", _
        behaviorCheckCount, errorText

    ' Saving while a note is held clears Dirty before Stop finishes its
    ' duration. That final duration change must mark the document dirty again.
    Dim As Integer keyboardOriginalNoteCount = midi_GetEditableNoteCount()
    Dim As Integer keyboardOriginalDirty = session_Dirty
    session_OnKeyboardRecord 0
    Dim As ULongInt keyboardAuditTick = session_LiveRecordingStartTick
    Dim As Integer keyboardNoteAdded = session_StartLiveKeyboardNote( _
        originalKeyboardBase, keyboardAuditTick)
    session_LiveRecordingStartClock = Timer - 1.0
    session_Dirty = 0
    session_OnStop 0
    Dim As MidiEditableNote keyboardAuditNote
    session_AuditBehavior keyboardNoteAdded <> 0 AndAlso _
        session_LiveRecording = 0 AndAlso session_Dirty <> 0 AndAlso _
        midi_GetEditableNote(keyboardOriginalNoteCount, keyboardAuditNote) <> 0 _
        AndAlso keyboardAuditNote.startTick = keyboardAuditTick AndAlso _
        keyboardAuditNote.durationTicks > 1, _
        "Stop failed to mark a held note dirty after saving during recording", _
        behaviorCheckCount, errorText
    If keyboardNoteAdded <> 0 Then
        session_OnEditMenu 0
    End If
    session_AuditBehavior midi_GetEditableNoteCount() = keyboardOriginalNoteCount, _
        "Held-note Stop audit did not undo its recording", _
        behaviorCheckCount, errorText
    session_Dirty = keyboardOriginalDirty
    session_CloseKeyboardWindow()

    session_OnDrumKit 0
    session_OnDrumSoft 0
    session_AuditBehavior session_DrumVelocity = OSE_DRUM_VELOCITY_SOFT, _
        "Drum Soft did not select its advertised velocity", _
        behaviorCheckCount, errorText
    session_OnDrumMedium 0
    session_AuditBehavior session_DrumVelocity = OSE_DRUM_VELOCITY_MEDIUM, _
        "Drum Medium did not select its advertised velocity", _
        behaviorCheckCount, errorText
    session_OnDrumHard 0
    session_AuditBehavior session_DrumVelocity = OSE_DRUM_VELOCITY_HARD, _
        "Drum Hard did not select its advertised velocity", _
        behaviorCheckCount, errorText
    Dim As Integer drumOriginalNoteCount = midi_GetEditableNoteCount()
    session_OnDrumRecord 0
    Dim As ULongInt drumAuditTick = session_LiveRecordingStartTick
    Dim As Integer drumAuditPitch = drumKit_Pitch(8)
    session_StartLiveDrumNote drumAuditPitch, drumAuditTick
    session_CloseLiveKeyboardNote drumAuditPitch, drumAuditTick + 1
    session_OnDrumRecord 0
    Dim As MidiEditableNote drumAuditNote
    Dim As Integer hasDrumAuditNote = _
        midi_GetEditableNote(drumOriginalNoteCount, drumAuditNote)
    session_AuditBehavior hasDrumAuditNote <> 0 AndAlso _
        drumAuditNote.keyNumber = drumAuditPitch AndAlso _
        drumAuditNote.channel = 9 AndAlso _
        drumAuditNote.velocity = OSE_DRUM_VELOCITY_HARD, _
        "Drum Record did not append the strike on MIDI channel 10", _
        behaviorCheckCount, errorText
    If hasDrumAuditNote <> 0 Then
        session_OnEditMenu 0
    End If
    session_AuditBehavior _
        midi_GetEditableNoteCount() = drumOriginalNoteCount, _
        "Recorded drum strike did not undo cleanly", _
        behaviorCheckCount, errorText
    session_CloseDrumWindow()

    ' Device-independent audio actions retain useful empty-list behavior.
    session_OnAudio 0
    session_OnAddAudio 0
    session_AuditBehavior session_FileDialog <> 0 AndAlso _
        session_FileDialogMode = SESSION_DIALOG_AUDIO_ADD, _
        "Audio Add did not open its PCM WAV chooser", _
        behaviorCheckCount, errorText
    session_AuditCloseFileDialog()
    If session_AudioWindow <> 0 Then
        gui_SetModalRoot session_AudioWindow
    End If
    session_OnApplyAudio 0
    session_AuditBehavior session_StatusText = _
        "Audio apply ignored: select a clip first.", _
        "Audio Apply did not reject an absent clip selection", _
        behaviorCheckCount, errorText
    session_OnDeleteAudio 0
    session_AuditBehavior session_StatusText = _
        "Audio delete ignored: select a clip first.", _
        "Audio Delete did not reject an absent clip selection", _
        behaviorCheckCount, errorText
    session_CloseAudioWindow()
End Sub


Private Sub session_AuditMidiRecordingClock( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    ' Inject clock snapshots, not native devices. Exercise the production
    ' timestamp-to-score conversion and note closure inside a cancelled edit.
    If session_BeginMidiEdit() = 0 Then
        session_AppendControlAuditError errorText, _
            "MIDI recording clock audit could not snapshot the document"
        Exit Sub
    End If
    Dim As ULongInt originalStartTick = session_LiveRecordingStartTick
    Dim As ULong originalOrigin = session_LiveRecordingStartMidiTimestamp
    Dim As Integer originalHasOrigin = session_LiveRecordingHasMidiTimestamp
    Const auditPitch As Integer = 60
    Dim As Integer originalNoteIndex = session_LiveMidiNoteIndex(auditPitch)
    Dim As ULongInt originalNoteStart = session_LiveMidiNoteStartTick(auditPitch)
    Dim As Integer originalNoteReleased = session_LiveMidiNoteReleased(auditPitch)

    session_LiveRecordingStartTick = 0
    session_LiveRecordingHasMidiTimestamp = 0
    Dim As ULongInt eventTick
    session_AuditBehavior session_LiveRecordingTickForMidiTimestamp( _
        905000, eventTick) = 0 AndAlso session_LiveRecordingHasMidiTimestamp = 0, _
        "a first MIDI message invented the recording clock origin", _
        behaviorCheckCount, errorText

    session_LiveRecordingStartMidiTimestamp = 900000
    session_LiveRecordingHasMidiTimestamp = -1
    Dim As Integer mapped = session_LiveRecordingTickForMidiTimestamp( _
        905000, eventTick)
    Dim As ULongInt firstNoteTick = eventTick
    session_AuditBehavior mapped <> 0 AndAlso firstNoteTick = _
        midi_SecondsToTicks(session_Summary, 5.0), _
        "MIDI recording discarded five seconds before the first note", _
        behaviorCheckCount, errorText

    Dim As Integer addedNote = midi_AddEditableNote( _
        session_Summary, 0, firstNoteTick, 1, auditPitch, 0, 100)
    session_LiveMidiNoteIndex(auditPitch) = addedNote
    session_LiveMidiNoteStartTick(auditPitch) = firstNoteTick
    mapped = session_LiveRecordingTickForMidiTimestamp(905750, eventTick)
    Dim As Integer closedNote = session_CloseLiveMidiNote(0, auditPitch, eventTick)
    Dim As MidiEditableNote recordedNote
    session_AuditBehavior mapped <> 0 AndAlso closedNote <> 0 AndAlso _
        midi_GetEditableNote(addedNote, recordedNote) <> 0 AndAlso _
        recordedNote.startTick = firstNoteTick AndAlso _
        recordedNote.durationTicks = _
            midi_SecondsToTicks(session_Summary, 5.75) - firstNoteTick, _
        "MIDI note-off changed the take's origin or recorded duration", _
        behaviorCheckCount, errorText

    ' A held note closed by Stop uses a current sample of the same input
    ' clock, so it must retain the same initial silence and note duration.
    session_LiveMidiNoteIndex(auditPitch) = addedNote
    session_LiveMidiNoteStartTick(auditPitch) = firstNoteTick
    mapped = session_LiveRecordingTickForMidiTimestamp(906000, eventTick)
    closedNote = session_CloseLiveMidiNote(0, auditPitch, eventTick)
    session_AuditBehavior mapped <> 0 AndAlso closedNote <> 0 AndAlso _
        midi_GetEditableNote(addedNote, recordedNote) <> 0 AndAlso _
        recordedNote.durationTicks = _
            midi_SecondsToTicks(session_Summary, 6.0) - firstNoteTick, _
        "Stop extended a held MIDI note by the silence before its onset", _
        behaviorCheckCount, errorText

    session_LiveRecordingStartMidiTimestamp = &HFFFFFFF0UL
    mapped = session_LiveRecordingTickForMidiTimestamp(20, eventTick)
    session_AuditBehavior mapped <> 0 AndAlso eventTick = _
        midi_SecondsToTicks(session_Summary, 0.036), _
        "MIDI recording did not preserve time across DWORD rollover", _
        behaviorCheckCount, errorText
    session_LiveRecordingStartMidiTimestamp = 900000
    session_AuditBehavior session_LiveRecordingTickForMidiTimestamp( _
        899999, eventTick) = 0 AndAlso eventTick = session_LiveRecordingStartTick, _
        "a pre-record callback became a full-day MIDI recording jump", _
        behaviorCheckCount, errorText

    session_LiveRecordingStartTick = originalStartTick
    session_LiveRecordingStartMidiTimestamp = originalOrigin
    session_LiveRecordingHasMidiTimestamp = originalHasOrigin
    session_LiveMidiNoteIndex(auditPitch) = originalNoteIndex
    session_LiveMidiNoteStartTick(auditPitch) = originalNoteStart
    session_LiveMidiNoteReleased(auditPitch) = originalNoteReleased
    If session_CancelMidiEdit() = 0 Then _
        session_AppendControlAuditError errorText, _
            "MIDI recording clock audit could not restore the document"
End Sub


Private Sub session_AuditMidiRecordingDispatch( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    ' Run the actual recorder with complete synthetic messages and monitoring
    ' disabled. No input endpoint, MIDI output, or synthesizer is involved.
    Dim As ULongInt originalStartTick = session_LiveRecordingStartTick
    Dim As ULong originalOrigin = session_LiveRecordingStartMidiTimestamp
    Dim As Integer originalHasOrigin = session_LiveRecordingHasMidiTimestamp
    Dim As Integer originalTrack = session_SelectedTrack
    Dim As Integer originalDirty = session_Dirty
    Dim As Integer originalSustain = session_LiveMidiSustain(0)
    Dim As Integer originalNoteCount = midi_GetEditableNoteCount()
    Dim As Integer originalEventCount = midi_GetChannelEventCount()
    Dim As Integer originalIndices(0 To 127)
    Dim As Integer originalReleased(0 To 127)
    Dim As ULongInt originalStarts(0 To 127)
    For keyNumber As Integer = 0 To 127
        originalIndices(keyNumber) = session_LiveMidiNoteIndex(keyNumber)
        originalStarts(keyNumber) = session_LiveMidiNoteStartTick(keyNumber)
        originalReleased(keyNumber) = session_LiveMidiNoteReleased(keyNumber)
        session_LiveMidiNoteIndex(keyNumber) = -1
        session_LiveMidiNoteStartTick(keyNumber) = 0
        session_LiveMidiNoteReleased(keyNumber) = 0
    Next
    session_LiveMidiSustain(0) = 0
    session_SelectedTrack = 0
    session_LiveRecordingStartTick = 0
    session_LiveRecordingStartMidiTimestamp = 900000
    session_LiveRecordingHasMidiTimestamp = -1
    Const auditPitch As Integer = 60
    Dim As Integer committedEdits = 0
    Dim As OseMidiInputMessage message
    message.status = &H90
    message.data1 = auditPitch
    message.data2 = 100
    message.timestampMilliseconds = 899999
    Dim As Integer changed = session_ProcessRecordedMidiMessage(message, 0)
    If changed <> 0 Then
        committedEdits += 1
    End If
    session_AuditBehavior changed = 0 AndAlso _
        midi_GetEditableNoteCount() = originalNoteCount AndAlso _
        session_LiveMidiNoteIndex(auditPitch) = -1, _
        "recording dispatch accepted a message from before the take", _
        behaviorCheckCount, errorText

    message.status = &HB0
    message.data1 = 64
    message.data2 = 127
    message.timestampMilliseconds = 905000
    If session_ProcessRecordedMidiMessage(message, 0) <> 0 Then
        committedEdits += 1
    End If
    message.status = &H90
    message.data1 = auditPitch
    message.data2 = 100
    message.timestampMilliseconds = 905100
    If session_ProcessRecordedMidiMessage(message, 0) <> 0 Then
        committedEdits += 1
    End If
    Dim As Integer firstNoteIndex = session_LiveMidiNoteIndex(auditPitch)
    message.status = &H80
    message.data2 = 0
    message.timestampMilliseconds = 905200
    session_ProcessRecordedMidiMessage message, 0
    Dim As MidiEditableNote firstNote
    Dim As MidiEditableNote secondNote
    session_AuditBehavior session_LiveMidiSustain(0) <> 0 AndAlso _
        session_LiveMidiNoteReleased(auditPitch) <> 0 AndAlso _
        midi_GetEditableNote(firstNoteIndex, firstNote) <> 0 AndAlso _
        firstNote.startTick = midi_SecondsToTicks(session_Summary, 5.1) AndAlso _
        firstNote.durationTicks = 1, _
        "pedal-held note-off lost its note or the silence before recording", _
        behaviorCheckCount, errorText

    message.status = &H90
    message.data2 = 90
    message.timestampMilliseconds = 905300
    If session_ProcessRecordedMidiMessage(message, 0) <> 0 Then
        committedEdits += 1
    End If
    Dim As Integer secondNoteIndex = session_LiveMidiNoteIndex(auditPitch)
    Dim As ULongInt retriggerTick = midi_SecondsToTicks(session_Summary, 5.3)
    session_AuditBehavior midi_GetEditableNoteCount() = originalNoteCount + 2 _
        AndAlso firstNoteIndex <> secondNoteIndex AndAlso _
        session_LiveMidiNoteReleased(auditPitch) = 0 AndAlso _
        midi_GetEditableNote(firstNoteIndex, firstNote) <> 0 AndAlso _
        midi_GetEditableNote(secondNoteIndex, secondNote) <> 0 AndAlso _
        firstNote.durationTicks = retriggerTick - firstNote.startTick AndAlso _
        secondNote.startTick = retriggerTick AndAlso secondNote.velocity = 90, _
        "a pedal-held retrigger failed to retain both note starts", _
        behaviorCheckCount, errorText

    message.status = &H80
    message.data2 = 0
    message.timestampMilliseconds = 905400
    session_ProcessRecordedMidiMessage message, 0
    message.status = &HB0
    message.data1 = 64
    message.timestampMilliseconds = 905500
    changed = session_ProcessRecordedMidiMessage(message, 0)
    If changed <> 0 Then
        committedEdits += 1
    End If
    session_AuditBehavior changed <> 0 AndAlso session_LiveMidiSustain(0) = 0 _
        AndAlso session_LiveMidiNoteIndex(auditPitch) = -1 AndAlso _
        midi_GetEditableNote(secondNoteIndex, secondNote) <> 0 AndAlso _
        secondNote.durationTicks = _
            midi_SecondsToTicks(session_Summary, 5.5) - retriggerTick, _
        "pedal release did not finish the retriggered note", _
        behaviorCheckCount, errorText

    ' At the timeline limit no controller event can be appended. A successful
    ' note closure alone must commit instead of being mistaken for zero edits
    ' because FreeBASIC's true value is negative.
    session_LiveMidiNoteIndex(auditPitch) = secondNoteIndex
    session_LiveMidiNoteStartTick(auditPitch) = retriggerTick
    session_LiveMidiNoteReleased(auditPitch) = -1
    session_LiveMidiSustain(0) = -1
    session_LiveRecordingStartTick = OSE_MAX_MIDI_TICK
    message.timestampMilliseconds = 900000
    changed = session_ProcessRecordedMidiMessage(message, 0)
    If changed <> 0 Then
        committedEdits += 1
    End If
    session_AuditBehavior changed <> 0 AndAlso _
        midi_GetEditableNote(secondNoteIndex, secondNote) <> 0 AndAlso _
        secondNote.durationTicks = OSE_MAX_MIDI_TICK - retriggerTick, _
        "pedal release cancelled a successful note closure at the timeline limit", _
        behaviorCheckCount, errorText

    For editIndex As Integer = 1 To committedEdits
        If documentHistory_Undo(session_DocumentHistory, session_Summary) = 0 Then
            session_AppendControlAuditError errorText, _
                "MIDI recording dispatch audit could not undo its edit"
            Exit For
        End If
    Next
    If midi_GetEditableNoteCount() <> originalNoteCount OrElse _
        midi_GetChannelEventCount() <> originalEventCount Then _
        session_AppendControlAuditError errorText, _
            "MIDI recording dispatch audit did not restore its fixture"
    For keyNumber As Integer = 0 To 127
        session_LiveMidiNoteIndex(keyNumber) = originalIndices(keyNumber)
        session_LiveMidiNoteStartTick(keyNumber) = originalStarts(keyNumber)
        session_LiveMidiNoteReleased(keyNumber) = originalReleased(keyNumber)
    Next
    session_LiveMidiSustain(0) = originalSustain
    session_SelectedTrack = originalTrack
    session_LiveRecordingStartTick = originalStartTick
    session_LiveRecordingStartMidiTimestamp = originalOrigin
    session_LiveRecordingHasMidiTimestamp = originalHasOrigin
    session_Dirty = originalDirty
    session_PlaybackChannelOrderDirty = -1
End Sub


Private Sub session_AuditSemanticEdits( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    Dim As Integer originalNoteCount = midi_GetEditableNoteCount()
    If originalNoteCount <= 0 OrElse _
        originalNoteCount > OSE_NOTE_SELECTION_CAPACITY Then
        session_AppendControlAuditError errorText, _
            "semantic edit fixture has no bounded notes"
    Else
        session_OnEditMenu 2
        session_AuditBehavior _
            session_NoteSelection.count = originalNoteCount, _
            "Select All did not select every note", _
            behaviorCheckCount, errorText
        session_OnEditMenu 4
        session_AuditBehavior _
            session_NoteClipboard.count = originalNoteCount, _
            "Copy did not populate the note clipboard", _
            behaviorCheckCount, errorText
        session_OnEditMenu 5
        session_AuditBehavior _
            session_ActiveScoreTool = SESSION_SCORE_TOOL_PASTE, _
            "Paste did not arm the score paste tool", _
            behaviorCheckCount, errorText
        session_OnEditMenu 3
        session_AuditBehavior midi_GetEditableNoteCount() = 0 AndAlso _
            session_NoteClipboard.count = originalNoteCount, _
            "Cut did not remove and retain the selected notes", _
            behaviorCheckCount, errorText
        session_OnEditMenu 0
        session_AuditBehavior _
            midi_GetEditableNoteCount() = originalNoteCount, _
            "Edit Undo did not restore a cut", behaviorCheckCount, errorText
        session_OnEditMenu 1
        session_AuditBehavior midi_GetEditableNoteCount() = 0, _
            "Edit Redo did not reapply a cut", behaviorCheckCount, errorText
        session_OnEditMenu 0
        session_AuditBehavior _
            midi_GetEditableNoteCount() = originalNoteCount, _
            "second Edit Undo did not restore the fixture", _
            behaviorCheckCount, errorText

        session_SelectOnlyNote 0
        session_OnEditMenu 6
        session_AuditBehavior session_NoteWindow <> 0, _
            "Edit Note Properties did not open for a selection", _
            behaviorCheckCount, errorText
        session_CloseNoteWindow()
        session_SelectOnlyNote 0
        session_OnEditMenu 7
        session_AuditBehavior _
            midi_GetEditableNoteCount() = originalNoteCount - 1, _
            "Delete Selected Notes removed the wrong note count", _
            behaviorCheckCount, errorText
        session_OnEditMenu 0
        session_AuditBehavior _
            midi_GetEditableNoteCount() = originalNoteCount, _
            "Undo did not restore a menu delete", behaviorCheckCount, errorText
    End If

    Dim As Integer originalTrackCount = session_Summary.trackCount
    session_OnTrackMenu 0
    session_AuditBehavior _
        session_Summary.trackCount = originalTrackCount + 1, _
        "Track Add did not append one track", behaviorCheckCount, errorText
    session_OnTrackMenu 1
    session_AuditBehavior session_Summary.trackCount = originalTrackCount, _
        "Track Remove did not remove the selected appended track", _
        behaviorCheckCount, errorText

    session_OnMusicMenu 0
    session_AuditBehavior _
        session_ActiveScoreTool = SESSION_SCORE_TOOL_ADD_NOTE AndAlso _
        session_AddPaletteVisible <> 0, _
        "Music Add Note did not expose the note palette", _
        behaviorCheckCount, errorText
    session_OnMusicMenu 1
    session_AuditBehavior _
        session_ActiveScoreTool = SESSION_SCORE_TOOL_DELETE_NOTE AndAlso _
        session_AddPaletteVisible = 0, _
        "Music Delete Note did not arm its score tool", _
        behaviorCheckCount, errorText
    session_SelectOnlyNote 0
    session_OnMusicMenu 2
    session_AuditBehavior session_NoteWindow <> 0, _
        "Music Note Properties did not open for a selection", _
        behaviorCheckCount, errorText
    session_CloseNoteWindow()

    session_ClearNoteSelection()
    session_OnMusicMenu 3
    session_AuditBehavior _
        session_StatusText = "Select one or more notes to play." AndAlso _
        session_Playing = 0, _
        "Play Selected Notes did not reject an empty selection", _
        behaviorCheckCount, errorText

    Dim As MidiEditableNote auditionFirstNote
    Dim As Integer hasAuditionFirstNote = _
        midi_GetEditableNote(0, auditionFirstNote)
    session_SelectOnlyNote 0
    session_PlaybackSpeedScale = 1.0
    session_OnMusicMenu 3
    session_AuditBehavior _
        hasAuditionFirstNote <> 0 AndAlso session_Playing <> 0 AndAlso _
        session_SelectedNotePlaybackActive <> 0 AndAlso _
        session_SelectedNotePlayback.count = 1, _
        "Play Selected Notes did not start one selected note", _
        behaviorCheckCount, errorText
    session_AuditBehavior _
        session_SelectedNotePlayback.startTick = auditionFirstNote.startTick AndAlso _
        session_SelectedNotePlayback.endTick = auditionFirstNote.startTick + _
            auditionFirstNote.durationTicks AndAlso _
        session_SelectedNotePlayback.entries(0).sourceNoteIndex = 0, _
        "single selected-note playback captured the wrong phrase", _
        behaviorCheckCount, errorText
    session_OnPause 0
    session_AuditBehavior session_Paused <> 0 AndAlso _
        session_StatusText = "Selected-note playback paused.", _
        "Pause did not suspend selected-note playback", _
        behaviorCheckCount, errorText
    session_OnPause 0
    session_AuditBehavior session_Paused = 0 AndAlso _
        session_StatusText = "Selected-note playback resumed.", _
        "Pause did not resume selected-note playback", _
        behaviorCheckCount, errorText
    session_OnStop 0
    session_AuditBehavior session_Playing = 0 AndAlso _
        session_SelectedNotePlaybackActive = 0 AndAlso _
        session_SelectedNotePlayback.count = 0 AndAlso _
        session_StatusText = "Selected-note playback stopped.", _
        "Stop did not clear selected-note playback", _
        behaviorCheckCount, errorText

    Dim As MidiEditableNote auditionSecondNote
    Dim As Integer hasAuditionSecondNote = _
        midi_GetEditableNote(1, auditionSecondNote)
    session_SelectOnlyNote 0
    noteSelection_Add session_NoteSelection, 1, 0
    session_PlaybackSpeedScale = 4.0
    session_OnMusicMenu 3
    Dim As ULongInt expectedAuditionStart = auditionFirstNote.startTick
    If auditionSecondNote.startTick < expectedAuditionStart Then _
        expectedAuditionStart = auditionSecondNote.startTick
    session_AuditBehavior _
        hasAuditionFirstNote <> 0 AndAlso hasAuditionSecondNote <> 0 AndAlso _
        session_SelectedNotePlaybackActive <> 0 AndAlso _
        session_SelectedNotePlayback.count = 2 AndAlso _
        session_PlaybackSpeedScale = 4.0 AndAlso _
        session_SelectedNotePlayback.entries(0).note.startTick <= _
            session_SelectedNotePlayback.entries(1).note.startTick AndAlso _
        session_SelectedNotePlayback.startTick = expectedAuditionStart AndAlso _
        Abs(session_PlaybackElapsed - midi_TicksToSeconds( _
            session_Summary, expectedAuditionStart)) < 0.000001, _
        "multi-note playback did not preserve score order, origin, or speed", _
        behaviorCheckCount, errorText
    session_OnStop 0

    session_SelectOnlyNote 0
    session_PlaybackSpeedScale = 1.0
    session_LastTransportShortcutState = 0
    session_LastSelectedPlaybackShortcutState = 0
    input_ResetForTest()
    input_MockKey FB.SC_CONTROL, -1
    input_MockKey FB.SC_SPACE, -1
    session_ProcessTransportShortcuts()
    session_AuditBehavior session_SelectedNotePlaybackActive <> 0 AndAlso _
        session_SelectedNotePlayback.count = 1, _
        "Ctrl+Space did not route to selected-note playback", _
        behaviorCheckCount, errorText
    input_MockKey FB.SC_CONTROL, 0
    input_MockKey FB.SC_SPACE, 0
    session_ProcessTransportShortcuts()
    session_OnStop 0
    input_ResetForTest()
    session_SelectOnlyNote 0

    session_OnMusicMenu 4
    session_AuditBehavior session_StatusText = "sfxlib tone audition: A4", _
        "Music Audition A4 did not trigger its status", _
        behaviorCheckCount, errorText

    session_OnMusicMenu 5
    session_AuditBehavior session_DrumWindow <> 0, _
        "Music Drum Kit did not open its performance surface", _
        behaviorCheckCount, errorText
    session_CloseDrumWindow()

    Dim As Integer originalTempo = session_InitialTempoBpm()
    Dim As Integer auditTempo = originalTempo + 1
    If auditTempo > 400 Then
        auditTempo = originalTempo - 1
    End If
    textbox_SetText session_TempoBox, Str(auditTempo), -1
    session_OnSetupMenu 3
    session_AuditBehavior session_InitialTempoBpm() = auditTempo, _
        "Setup Apply Tempo did not change the initial tempo", _
        behaviorCheckCount, errorText
    session_OnEditMenu 0
    session_AuditBehavior session_InitialTempoBpm() = originalTempo, _
        "Undo did not restore the audited tempo", behaviorCheckCount, errorText
    session_RefreshTempoBox()

    Dim As Integer auditDirtyState = session_Dirty
    session_Dirty = -1
    session_OnFileMenu 0
    session_AuditBehavior session_ConfirmDialog <> 0 AndAlso _
        session_ConfirmAction = SESSION_CONFIRM_NEW, _
        "File New did not protect dirty work", behaviorCheckCount, errorText
    session_CloseDiscardConfirmation()
    session_Dirty = auditDirtyState
End Sub


Private Sub session_AuditSemanticScorePointerControls( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    /'
        The score rail and note palette are drawn directly rather than owned by
        omaGUI widgets. Drive every visible face through the application's real
        pointer loop so a correct geometry helper cannot hide a disconnected
        editing action.
    '/
    Const auditWidth As Integer = SESSION_INITIAL_WIDTH
    Const auditHeight As Integer = SESSION_INITIAL_HEIGHT
    Dim As Integer originalTool = session_ActiveScoreTool
    Dim As Integer originalPaletteVisible = session_AddPaletteVisible
    Dim As ScoreAddToolState originalAddState = session_AddToolState
    Dim As NoteSelectionState originalSelection = session_NoteSelection
    Dim As Integer originalSelectedNote = session_SelectedNote
    Dim As Integer originalSelectedTrack = session_SelectedTrack
    Dim As Integer originalFirstVisibleTrack = session_ScoreFirstVisibleTrack
    Dim As ULongInt originalViewStartTick = session_ViewStartTick
    Dim As Integer originalViewBeatCount = session_ViewBeatCount
    Dim As Integer originalTrackRowHeight = session_ScoreTrackRowHeight
    Dim As Integer originalInteractionMode = session_InteractionMode

    input_ResetForTest()
    session_LastScoreButtons = 0
    scoreAddTool_Initialize session_AddToolState

    Dim As Integer toolX = session_InteractionMetrics.scoreRailLeft + _
        session_InteractionMetrics.scoreRailWidth \ 2
    Dim As Integer toolY = session_InteractionMetrics.scoreRailFirstTop + _
        session_InteractionMetrics.scoreRailHeight \ 2
    session_AuditMockScoreClick toolX, toolY, auditWidth, auditHeight
    session_AuditBehavior _
        session_ActiveScoreTool = SESSION_SCORE_TOOL_SELECT AndAlso _
        session_AddPaletteVisible = 0, _
        "Score Select face did not activate Select", _
        behaviorCheckCount, errorText

    toolY = session_InteractionMetrics.scoreRailFirstTop + _
        session_InteractionMetrics.scoreRailStep + _
        session_InteractionMetrics.scoreRailHeight \ 2
    session_AuditMockScoreClick toolX, toolY, auditWidth, auditHeight
    session_AuditBehavior _
        session_ActiveScoreTool = SESSION_SCORE_TOOL_ADD_NOTE AndAlso _
        session_AddPaletteVisible <> 0, _
        "Score Note face did not open the Add Note palette", _
        behaviorCheckCount, errorText

    For durationIndex As Integer = 0 To OSE_SCORE_DURATION_COUNT - 1
        Dim As Integer durationX = _
            session_InteractionMetrics.scorePaletteLeft + 4 + _
            session_InteractionMetrics.scorePaletteFaceWidth \ 2
        Dim As Integer durationY = _
            session_InteractionMetrics.scorePaletteTop + 4 + _
            durationIndex * _
                session_InteractionMetrics.scorePaletteRowHeight + _
            session_InteractionMetrics.scorePaletteFaceHeight \ 2
        session_AuditMockScoreClick durationX, durationY, auditWidth, auditHeight
        session_AuditBehavior _
            session_AddToolState.durationIndex = durationIndex, _
            "Score duration face " + Str(durationIndex) + _
                " did not select its note value", _
            behaviorCheckCount, errorText
    Next

    For modifierIndex As Integer = 0 To 5
        Dim As Integer modifierX = _
            session_InteractionMetrics.scorePaletteLeft + 4 + _
            session_InteractionMetrics.scorePaletteColumnWidth + _
            session_InteractionMetrics.scorePaletteFaceWidth \ 2
        Dim As Integer modifierY = _
            session_InteractionMetrics.scorePaletteTop + 4 + _
            modifierIndex * _
                session_InteractionMetrics.scorePaletteRowHeight + _
            session_InteractionMetrics.scorePaletteFaceHeight \ 2
        session_AuditMockScoreClick modifierX, modifierY, auditWidth, auditHeight
        Dim As Integer modifierChanged
        Select Case modifierIndex
            Case 0
                modifierChanged = _
                session_AddToolState.accidentalSemitones = 1
            Case 1
                modifierChanged = _
                session_AddToolState.accidentalSemitones = -1
            Case 2
                modifierChanged = _
                session_AddToolState.accidentalSemitones = 0
            Case 3
                modifierChanged = session_AddToolState.dotted <> 0
            Case 4
                modifierChanged = session_AddToolState.triplet <> 0
            Case 5
                modifierChanged = session_AddToolState.tied <> 0
        End Select
        session_AuditBehavior modifierChanged, _
            "Score modifier face " + Str(modifierIndex) + _
                " did not change its note option", _
            behaviorCheckCount, errorText
    Next

    toolY = session_InteractionMetrics.scoreRailFirstTop + _
        SESSION_SCORE_TOOL_DELETE_NOTE * _
            session_InteractionMetrics.scoreRailStep + _
        session_InteractionMetrics.scoreRailHeight \ 2
    session_AuditMockScoreClick toolX, toolY, auditWidth, auditHeight
    session_AuditBehavior _
        session_ActiveScoreTool = SESSION_SCORE_TOOL_DELETE_NOTE AndAlso _
        session_AddPaletteVisible = 0, _
        "Score Delete face did not arm note deletion (tool " + _
            Str(session_ActiveScoreTool) + ", status " + _
            session_StatusText + ")", _
        behaviorCheckCount, errorText

    toolY = session_InteractionMetrics.scoreRailFirstTop + _
        SESSION_SCORE_TOOL_CUT * session_InteractionMetrics.scoreRailStep + _
        session_InteractionMetrics.scoreRailHeight \ 2
    session_AuditMockScoreClick toolX, toolY, auditWidth, auditHeight
    session_AuditBehavior _
        session_ActiveScoreTool = SESSION_SCORE_TOOL_CUT AndAlso _
        session_AddPaletteVisible = 0, _
        "Score Cut face did not arm marquee cutting (tool " + _
            Str(session_ActiveScoreTool) + ", status " + _
            session_StatusText + ")", _
        behaviorCheckCount, errorText

    toolY = session_InteractionMetrics.scoreRailFirstTop + _
        SESSION_SCORE_TOOL_PASTE * session_InteractionMetrics.scoreRailStep + _
        session_InteractionMetrics.scoreRailHeight \ 2
    session_AuditMockScoreClick toolX, toolY, auditWidth, auditHeight
    session_AuditBehavior _
        session_NoteClipboard.count > 0 AndAlso _
        session_ActiveScoreTool = SESSION_SCORE_TOOL_PASTE AndAlso _
        session_AddPaletteVisible = 0, _
        "Score Paste face did not arm location-based pasting (tool " + _
            Str(session_ActiveScoreTool) + ", clipboard " + _
            Str(session_NoteClipboard.count) + ", status " + _
            session_StatusText + ")", _
        behaviorCheckCount, errorText

    /'
        A pointer insertion must append one note without moving the existing
        phrase or changing the vertical and timeline view anchors. This is the
        application-level regression for the former whole-song shift.
    '/
    Dim As Integer originalNoteCount = midi_GetEditableNoteCount()
    Dim As MidiEditableNote originalFirstNote
    Dim As Integer hasOriginalFirstNote = _
        midi_GetEditableNote(0, originalFirstNote)
    session_ActiveScoreTool = SESSION_SCORE_TOOL_ADD_NOTE
    session_AddPaletteVisible = -1
    scoreAddTool_Initialize session_AddToolState
    session_SelectedTrack = 0
    session_ScoreFirstVisibleTrack = 0
    Dim As Integer insertionFirstVisibleTrack = session_ScoreFirstVisibleTrack
    Dim As ULongInt insertionViewStartTick = session_ViewStartTick
    session_AuditMockScoreClick 600, _
        SESSION_SCORE_TOP + _
        scoreLayout_FirstStaffOffset(session_ScoreTrackRowHeight), _
        auditWidth, auditHeight

    session_AuditBehavior originalNoteCount > 0 AndAlso _
        midi_GetEditableNoteCount() = originalNoteCount + 1, _
        "Score pointer insertion did not append exactly one note", _
        behaviorCheckCount, errorText
    Dim As MidiEditableNote currentFirstNote
    session_AuditBehavior hasOriginalFirstNote <> 0 AndAlso _
        midi_GetEditableNote(0, currentFirstNote) <> 0 AndAlso _
        currentFirstNote.startTick = originalFirstNote.startTick AndAlso _
        currentFirstNote.durationTicks = originalFirstNote.durationTicks AndAlso _
        currentFirstNote.keyNumber = originalFirstNote.keyNumber AndAlso _
        currentFirstNote.channel = originalFirstNote.channel AndAlso _
        currentFirstNote.velocity = originalFirstNote.velocity AndAlso _
        currentFirstNote.trackIndex = originalFirstNote.trackIndex AndAlso _
        session_ScoreFirstVisibleTrack = insertionFirstVisibleTrack AndAlso _
        session_ViewStartTick = insertionViewStartTick, _
        "Adding a score note moved existing music or the score view", _
        behaviorCheckCount, errorText
    session_ApplyUndoEdit()
    session_AuditBehavior _
        midi_GetEditableNoteCount() = originalNoteCount, _
        "Undo did not remove the pointer-inserted score note", _
        behaviorCheckCount, errorText

    /'
        Axis pinches are separate application controls. Expanding only the
        horizontal span changes time density, while expanding only the
        vertical span changes track density. Both contacts deliberately have
        nonzero separation on the other axis to represent real fingers.
    '/
    session_ApplyInteractionMode OSE_UI_INTERACTION_TOUCH, 0
    session_ViewBeatCount = SESSION_SCORE_BEATS
    session_ScoreTrackRowHeight = SESSION_SCORE_TRACK_ROW_HEIGHT_DEFAULT
    touchGesture_Reset session_TouchGestureState
    session_AuditMockTouchPair 540, 240, 660, 320, _
        auditWidth, auditHeight
    session_AuditMockTouchPair 520, 240, 680, 320, _
        auditWidth, auditHeight
    session_AuditBehavior _
        session_ViewBeatCount < SESSION_SCORE_BEATS AndAlso _
        session_ScoreTrackRowHeight = SESSION_SCORE_TRACK_ROW_HEIGHT_DEFAULT, _
        "Horizontal pinch changed the wrong score axis", _
        behaviorCheckCount, errorText
    session_AuditReleaseTouches auditWidth, auditHeight

    session_ViewBeatCount = SESSION_SCORE_BEATS
    session_ScoreTrackRowHeight = SESSION_SCORE_TRACK_ROW_HEIGHT_DEFAULT
    touchGesture_Reset session_TouchGestureState
    session_AuditMockTouchPair 540, 240, 660, 320, _
        auditWidth, auditHeight
    session_AuditMockTouchPair 540, 220, 660, 340, _
        auditWidth, auditHeight
    session_AuditBehavior _
        session_ViewBeatCount = SESSION_SCORE_BEATS AndAlso _
        session_ScoreTrackRowHeight > SESSION_SCORE_TRACK_ROW_HEIGHT_DEFAULT _
        AndAlso scoreLayout_LineSpacing(session_ScoreTrackRowHeight) > _
            scoreLayout_LineSpacing(SESSION_SCORE_TRACK_ROW_HEIGHT_DEFAULT) _
        AndAlso scoreLayout_ScalePixels(session_ScoreTrackRowHeight, 10) > 10 _
        AndAlso scoreLayout_ScalePixels(session_ScoreTrackRowHeight, 14) > 14, _
        "Vertical pinch changed the wrong score axis", _
        behaviorCheckCount, errorText
    session_AuditReleaseTouches auditWidth, auditHeight

    ' Desktop wheel zoom follows the same independent axes as touch pinch.
    ' Control owns time density; adding Shift changes only track density.
    session_ApplyInteractionMode OSE_UI_INTERACTION_FINE, 0
    session_ViewBeatCount = SESSION_SCORE_BEATS
    session_ScoreTrackRowHeight = SESSION_SCORE_TRACK_ROW_HEIGHT_DEFAULT
    session_LastScoreButtons = 0
    input_ResetForTest()
    input_MockKey FB.SC_CONTROL, -1
    input_MockMouse 600, 280, 0, 1
    input_Update()
    session_UpdateScoreInput auditWidth, auditHeight
    session_AuditBehavior _
        session_ViewBeatCount = _
            SESSION_SCORE_BEATS - SESSION_SCORE_ZOOM_STEP AndAlso _
        session_ScoreTrackRowHeight = SESSION_SCORE_TRACK_ROW_HEIGHT_DEFAULT, _
        "Ctrl+wheel changed the wrong score axis", _
        behaviorCheckCount, errorText

    session_ViewBeatCount = SESSION_SCORE_BEATS
    session_ScoreTrackRowHeight = SESSION_SCORE_TRACK_ROW_HEIGHT_DEFAULT
    input_ResetForTest()
    input_MockKey FB.SC_CONTROL, -1
    input_MockKey FB.SC_LSHIFT, -1
    input_MockMouse 600, 280, 0, 1
    input_Update()
    session_UpdateScoreInput auditWidth, auditHeight
    session_AuditBehavior _
        session_ViewBeatCount = SESSION_SCORE_BEATS AndAlso _
        session_ScoreTrackRowHeight = SESSION_SCORE_TRACK_ROW_HEIGHT_DEFAULT + _
            SESSION_SCORE_TRACK_ROW_ZOOM_STEP, _
        "Ctrl+Shift+wheel changed the wrong score axis", _
        behaviorCheckCount, errorText
    input_ResetForTest()

    Dim As Integer zoomStepIndex
    For zoomStepIndex = 0 To 20
        session_ZoomScoreVerticallyAt 280, _
            SESSION_SCORE_TRACK_ROW_ZOOM_STEP, auditHeight
    Next
    session_AuditBehavior _
        session_ScoreTrackRowHeight = _
            SESSION_SCORE_TRACK_ROW_HEIGHT_MAXIMUM, _
        "Vertical score zoom exceeded or missed its maximum", _
        behaviorCheckCount, errorText
    For zoomStepIndex = 0 To 20
        session_ZoomScoreVerticallyAt 280, _
            -SESSION_SCORE_TRACK_ROW_ZOOM_STEP, auditHeight
    Next
    session_AuditBehavior _
        session_ScoreTrackRowHeight = _
            SESSION_SCORE_TRACK_ROW_HEIGHT_MINIMUM, _
        "Vertical score zoom exceeded or missed its minimum", _
        behaviorCheckCount, errorText

    session_ActiveScoreTool = originalTool
    session_AddPaletteVisible = originalPaletteVisible
    session_AddToolState = originalAddState
    session_SelectedTrack = originalSelectedTrack
    session_SelectedNote = originalSelectedNote
    session_NoteSelection = originalSelection
    session_ScoreFirstVisibleTrack = originalFirstVisibleTrack
    session_ViewStartTick = originalViewStartTick
    session_ViewBeatCount = originalViewBeatCount
    session_ScoreTrackRowHeight = originalTrackRowHeight
    session_ApplyInteractionMode originalInteractionMode, 0
    session_LastScoreButtons = 0
    input_ResetForTest()
End Sub


Private Sub session_AuditHistoryUnchanged( _
    ByVal expectedUndoCount As Integer, _
    ByVal expectedRedoCount As Integer, _
    ByVal expectedDirtyState As Integer, _
    ByVal failureText As String, _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    session_AuditBehavior _
        documentHistory_UndoCount(session_DocumentHistory) = expectedUndoCount _
        AndAlso _
        documentHistory_RedoCount(session_DocumentHistory) = expectedRedoCount _
        AndAlso session_Dirty = expectedDirtyState, failureText, _
        behaviorCheckCount, errorText
End Sub


Private Sub session_AuditSemanticAutomationMutations( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    /'
        Apply buttons are allowed to report that nothing changed, but they must
        not manufacture undo entries or discard a valid redo branch. Temporary
        automation events also prove that channel and system-common selections
        reach their distinct mutation paths.
    '/
    Dim As Integer originalChannelCount = midi_GetChannelEventCount()
    Dim As Integer originalSystemCount = midi_GetSystemEventCount()
    Dim As Integer originalDirtyState = session_Dirty
    Dim As Integer channelSource = -1
    Dim As Integer systemSource = -1
    If session_BeginMidiEdit() <> 0 Then
        channelSource = midi_AddChannelEvent( _
            session_Summary, 0, 17, 0, &HB0, 11, 77)
        systemSource = midi_AddSystemEvent( _
            session_Summary, 0, 19, &HF2, 3, 4)
        If channelSource < 0 OrElse systemSource < 0 Then
            session_CancelMidiEdit()
        Else
            session_CommitMidiEdit()
        End If
    End If
    session_AuditBehavior channelSource >= 0 AndAlso systemSource >= 0, _
        "Automation audit fixtures could not be added", _
        behaviorCheckCount, errorText

    If channelSource >= 0 AndAlso systemSource >= 0 Then
        session_OnAutomation 0
        Dim As ListBoxData Ptr automationListData = 0
        If session_AutomationList <> 0 Then _
            automationListData = Cast(ListBoxData Ptr, session_AutomationList->data)
        Dim As Integer channelListIndex = -1
        Dim As Integer systemListIndex = -1
        For referenceIndex As Integer = 0 To _
            session_AutomationEventRefCount - 1
            With session_AutomationEventRefs(referenceIndex)
                If .sourceIndex = channelSource Then
                    channelListIndex = referenceIndex
                End If
                If .sourceIndex = systemSource Then
                    systemListIndex = referenceIndex
                End If
            End With
        Next

        session_AuditBehavior automationListData <> 0 AndAlso _
            channelListIndex >= 0 AndAlso systemListIndex >= 0, _
            "Automation fixtures were not exposed in the event list", _
            behaviorCheckCount, errorText
        If automationListData <> 0 AndAlso channelListIndex >= 0 Then
            automationListData->selected_index = channelListIndex
            session_UpdateAutomationSelection()
            Dim As Integer undoCount = _
                documentHistory_UndoCount(session_DocumentHistory)
            Dim As Integer redoCount = _
                documentHistory_RedoCount(session_DocumentHistory)
            Dim As Integer dirtyState = session_Dirty
            session_OnApplyAutomation 0
            session_AuditHistoryUnchanged undoCount, redoCount, dirtyState, _
                "Unchanged channel event altered document history", _
                behaviorCheckCount, errorText
            session_AuditBehavior session_StatusText = _
                "MIDI channel event already has those values.", _
                "Unchanged channel event was not reported", _
                behaviorCheckCount, errorText

            textbox_SetText session_AutomationData2Box, "78", -1
            session_OnApplyAutomation 0
            Dim As MidiChannelEventPoint changedChannelEvent
            session_AuditBehavior _
                session_GetSelectedChannelAutomation(changedChannelEvent) <> 0 _
                AndAlso changedChannelEvent.data2 = 78, _
                "Channel-event Apply did not store its new value", _
                behaviorCheckCount, errorText
        End If

        If automationListData <> 0 AndAlso systemListIndex >= 0 Then
            automationListData->selected_index = systemListIndex
            session_UpdateAutomationSelection()
            session_AuditBehavior session_AutomationSelectedKind <> 0, _
                "System-common selection was routed as a channel event", _
                behaviorCheckCount, errorText
            Dim As Integer undoCount = _
                documentHistory_UndoCount(session_DocumentHistory)
            Dim As Integer redoCount = _
                documentHistory_RedoCount(session_DocumentHistory)
            Dim As Integer dirtyState = session_Dirty
            session_OnApplyAutomation 0
            session_AuditHistoryUnchanged undoCount, redoCount, dirtyState, _
                "Unchanged system-common event altered document history", _
                behaviorCheckCount, errorText
            session_AuditBehavior session_StatusText = _
                "MIDI system-common event already has those values.", _
                "Unchanged system-common event was not reported", _
                behaviorCheckCount, errorText

            textbox_SetText session_AutomationData1Box, "5", -1
            session_OnApplyAutomation 0
            Dim As MidiSystemEventPoint changedSystemEvent
            session_AuditBehavior _
                session_GetSelectedSystemAutomation(changedSystemEvent) <> 0 _
                AndAlso changedSystemEvent.data1 = 5, _
                "System-common Apply did not store its new value", _
                behaviorCheckCount, errorText
            session_OnDeleteAutomation 0
            session_AuditBehavior _
                midi_GetSystemEventCount() = originalSystemCount, _
                "MIDI Event Delete did not remove the selected system event", _
                behaviorCheckCount, errorText
        End If

        textbox_SetText session_AutomationTickBox, "23", -1
        textbox_SetText session_AutomationTrackBox, "1", -1
        textbox_SetText session_AutomationChannelBox, "1", -1
        textbox_SetText session_AutomationTypeBox, Str(&HB0), -1
        textbox_SetText session_AutomationData1Box, "10", -1
        textbox_SetText session_AutomationData2Box, "20", -1
        session_AutomationSelectedKind = 0
        session_OnAddAutomation 0
        session_AuditBehavior _
            midi_GetChannelEventCount() = originalChannelCount + 2, _
            "MIDI Event New did not add the requested channel event", _
            behaviorCheckCount, errorText
        session_OnDeleteAutomation 0
        session_AuditBehavior _
            midi_GetChannelEventCount() = originalChannelCount + 1, _
            "MIDI Event Delete did not remove the selected channel event", _
            behaviorCheckCount, errorText
        session_CloseAutomationWindow()

        ' Undo the two Apply operations, both Delete operations, the New
        ' operation, and the fixture insertion. The resulting redo branch is
        ' intentionally retained for all no-op checks below.
        session_OnEditMenu 0
        session_OnEditMenu 0
        session_OnEditMenu 0
        session_OnEditMenu 0
        session_OnEditMenu 0
        session_OnEditMenu 0
        session_AuditBehavior _
            midi_GetChannelEventCount() = originalChannelCount AndAlso _
            midi_GetSystemEventCount() = originalSystemCount AndAlso _
            documentHistory_RedoCount(session_DocumentHistory) >= 6, _
            "Automation audit edits did not undo as one chronological sequence", _
            behaviorCheckCount, errorText
    End If

    session_Dirty = originalDirtyState
End Sub


Private Sub session_AuditSemanticAudioMutations( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    Dim As Integer originalDirtyState = session_Dirty
    Dim As ULongInt originalViewStartTick = session_ViewStartTick
    Dim As NoteSelectionState originalNoteSelection = session_NoteSelection
    Dim As Integer originalSelectedNote = session_SelectedNote
    Dim As String audioFixture = Left( _
        Trim(Environ("OSE_TEST_AUDIO_FIXTURE")), OSE_AUDIO_MAX_PATH_BYTES)
    Dim As Integer originalAudioCount = audio_GetCount()
    Dim As Integer auditAudioIndex = -1
    If audioFixture <> "" Then
        session_OnStop 0
        session_OnFastForward 0
        session_OnPlay 0
        session_AuditBehavior session_Playing <> 0 AndAlso _
            session_PlaybackSpeedScale = 4.0 AndAlso audio_GetCount() = 0, _
            "Audio boundary fixture did not start a fast MIDI-only arrangement", _
            behaviorCheckCount, errorText
        session_ViewStartTick = 23
        session_OnAudio 0
        session_CompleteFileSelection _
            SESSION_DIALOG_AUDIO_ADD, 1, audioFixture
        If audio_GetCount() = originalAudioCount + 1 Then _
            auditAudioIndex = originalAudioCount
        session_UpdateSoftwarePlayback()
        session_AuditBehavior session_Playing = 0 AndAlso session_Paused = 0 _
            AndAlso session_PlaybackSpeedScale = 4.0 AndAlso _
            session_StatusText = _
                "Full playback with WAV clips requires 1x. Press Stop, then Play.", _
            "Adding a WAV during fast playback bypassed its transport boundary", _
            behaviorCheckCount, errorText
    End If
    session_AuditBehavior auditAudioIndex = originalAudioCount AndAlso _
        audioSampleSlots_GetLoadedCount() = audio_GetCount(), _
        "Audio audit fixture could not be added", _
        behaviorCheckCount, errorText
    If auditAudioIndex >= 0 Then
        If session_AudioList <> 0 AndAlso session_AudioList->data <> 0 Then
            Dim As ListBoxData Ptr audioListData = Cast( _
                ListBoxData Ptr, session_AudioList->data)
            audioListData->selected_index = auditAudioIndex
            session_UpdateAudioSelection()
        End If

        Dim As Integer undoCount = _
            documentHistory_UndoCount(session_DocumentHistory)
        Dim As Integer redoCount = _
            documentHistory_RedoCount(session_DocumentHistory)
        Dim As Integer dirtyState = session_Dirty
        session_OnPlay 0
        session_AuditBehavior session_Playing = 0 AndAlso _
            session_PlaybackSpeedScale = 4.0 AndAlso _
            session_TransportButtonIsActive("fast_forward") <> 0 AndAlso _
            session_StatusText = _
                "Full playback with WAV clips requires 1x. Press Stop, then Play.", _
            "Full Play accepted fast WAV playback or silently changed its speed", _
            behaviorCheckCount, errorText
        session_AuditHistoryUnchanged undoCount, redoCount, dirtyState, _
            "Rejected fast WAV playback altered document history", _
            behaviorCheckCount, errorText
        session_SelectOnlyNote 0
        session_OnPlaySelectedNotes 0
        session_AuditBehavior session_Playing <> 0 AndAlso _
            session_SelectedNotePlaybackActive <> 0 AndAlso _
            session_PlaybackSpeedScale = 4.0, _
            "WAV clip presence blocked fast selected-note playback", _
            behaviorCheckCount, errorText
        session_OnStop 0
        session_OnPlay 0
        session_AuditBehavior session_Playing <> 0 AndAlso _
            session_SelectedNotePlaybackActive = 0 AndAlso _
            session_PlaybackSpeedScale = 1.0, _
            "Stop then Play did not restore normal-speed WAV playback", _
            behaviorCheckCount, errorText
        session_OnStop 0
        session_OnApplyAudio 0
        session_AuditHistoryUnchanged undoCount, redoCount, dirtyState, _
            "Unchanged audio fields altered document history", _
            behaviorCheckCount, errorText
        session_AuditBehavior session_StatusText = _
            "Audio clip already has those values.", _
            "Unchanged audio fields were not reported", _
            behaviorCheckCount, errorText

        textbox_SetText session_AudioGainBox, "900", -1
        session_OnApplyAudio 0
        Dim As OseAudioClip changedAudioClip
        session_AuditBehavior _
            audio_GetClip(auditAudioIndex, changedAudioClip) <> 0 AndAlso _
            changedAudioClip.gainPermille = 900 AndAlso _
            audioSampleSlots_GetLoadedCount() = audio_GetCount(), _
            "Audio Apply did not store its new gain", _
            behaviorCheckCount, errorText
        session_OnDeleteAudio 0
        session_AuditBehavior audio_GetCount() = originalAudioCount AndAlso _
            audioSampleSlots_GetLoadedCount() = audio_GetCount(), _
            "Audio Delete did not remove the selected clip", _
            behaviorCheckCount, errorText
        session_CloseAudioWindow()

        session_OnEditMenu 0
        Dim As Integer restoredDelete = audio_GetCount() = originalAudioCount + 1
        session_OnEditMenu 0
        Dim As OseAudioClip restoredAudioClip
        Dim As Integer restoredApply = _
            audio_GetClip(auditAudioIndex, restoredAudioClip) <> 0 AndAlso _
            restoredAudioClip.gainPermille = 1000
        session_OnEditMenu 0
        session_AuditBehavior restoredDelete <> 0 AndAlso _
            restoredApply <> 0 AndAlso audio_GetCount() = originalAudioCount _
            AndAlso audioSampleSlots_GetLoadedCount() = audio_GetCount() _
            AndAlso documentHistory_RedoCount(session_DocumentHistory) >= 3, _
            "Audio Add, Apply, and Delete did not undo chronologically", _
            behaviorCheckCount, errorText

        Dim As String missingMidiProject = audioFixture + ".missing-midi.ose"
        Dim As String missingMidiFile = audioFixture + ".missing-midi.mid"
        undoCount = documentHistory_UndoCount(session_DocumentHistory)
        redoCount = documentHistory_RedoCount(session_DocumentHistory)
        dirtyState = session_Dirty
        Dim As Integer savedProject = audio_SaveProject(missingMidiProject, missingMidiFile)
        Dim As Integer rejectedProject = 0
        If savedProject <> 0 Then
            rejectedProject = session_LoadProjectFile(missingMidiProject) = 0
        End If
        session_AuditBehavior savedProject <> 0 AndAlso rejectedProject <> 0 AndAlso _
            audio_GetCount() = originalAudioCount, _
            "Missing project MIDI did not preserve the current document", _
            behaviorCheckCount, errorText
        session_AuditHistoryUnchanged undoCount, redoCount, dirtyState, _
            "Failed project opening erased document undo or redo", _
            behaviorCheckCount, errorText
        If savedProject <> 0 Then
            Dim As Long cleanupStatus = Kill(missingMidiProject)
            If cleanupStatus <> 0 Then
                session_AppendControlAuditError errorText, _
                    "Could not remove missing-MIDI project audit fixture " + _
                    missingMidiProject + " (error " + LTrim(Str(cleanupStatus)) + ")."
            End If
        End If
    End If

    session_ViewStartTick = originalViewStartTick
    session_NoteSelection = originalNoteSelection
    session_SelectedNote = originalSelectedNote
    session_Dirty = originalDirtyState
End Sub


Private Sub session_AuditSemanticNoteMutations( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    Dim As Integer originalDirtyState = session_Dirty
    If midi_GetEditableNoteCount() > 0 Then
        session_SelectOnlyNote 0
        session_OnNoteProperties 0
        Dim As MidiEditableNote originalNote
        midi_GetEditableNote 0, originalNote
        Dim As Integer undoCount = _
            documentHistory_UndoCount(session_DocumentHistory)
        Dim As Integer redoCount = _
            documentHistory_RedoCount(session_DocumentHistory)
        Dim As Integer dirtyState = session_Dirty
        session_OnApplyNoteProperties 0
        session_AuditHistoryUnchanged undoCount, redoCount, dirtyState, _
            "Unchanged note properties altered document history", _
            behaviorCheckCount, errorText
        session_AuditBehavior session_StatusText = _
            "Note already has those values.", _
            "Unchanged note properties were not reported", _
            behaviorCheckCount, errorText

        Dim As Integer changedVelocity = originalNote.velocity + 1
        If changedVelocity > 127 Then
            changedVelocity = originalNote.velocity - 1
        End If
        textbox_SetText session_NoteVelocityBox, Str(changedVelocity), -1
        session_OnApplyNoteProperties 0
        Dim As MidiEditableNote changedNote
        session_AuditBehavior _
            midi_GetEditableNote(0, changedNote) <> 0 AndAlso _
            changedNote.velocity = changedVelocity, _
            "Note Apply did not store its new velocity", _
            behaviorCheckCount, errorText
        session_CloseNoteWindow()
        session_OnEditMenu 0
        Dim As MidiEditableNote restoredNote
        session_AuditBehavior _
            midi_GetEditableNote(0, restoredNote) <> 0 AndAlso _
            restoredNote.velocity = originalNote.velocity, _
            "Undo did not restore the Note Apply mutation", _
            behaviorCheckCount, errorText
    End If

    session_Dirty = originalDirtyState
End Sub


Private Sub session_AuditSemanticTempoMapMutations( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    Dim As Integer originalDirtyState = session_Dirty
    session_OnTempoMap 0
    If session_TempoMapWindow <> 0 Then
        Dim As Integer originalTempoCount = session_Summary.tempoCount
        Dim As Integer originalMeterCount = session_Summary.timeSignatureCount
        Dim As Integer originalKeyCount = session_Summary.keySignatureCount
        Dim As Integer undoCount = _
            documentHistory_UndoCount(session_DocumentHistory)
        Dim As Integer redoCount = _
            documentHistory_RedoCount(session_DocumentHistory)
        Dim As Integer dirtyState = session_Dirty
        session_OnApplyTempoMap 0
        session_AuditHistoryUnchanged undoCount, redoCount, dirtyState, _
            "Unchanged tempo-map fields altered document history", _
            behaviorCheckCount, errorText
        session_AuditBehavior session_StatusText = _
            "Tempo map point already has those values.", _
            "Unchanged tempo-map fields were not reported", _
            behaviorCheckCount, errorText

        Dim As ULongInt auditTempoTick = session_Summary.durationTicks + _
            CULngInt(session_Summary.division)
        If auditTempoTick > OSE_MAX_MIDI_TICK Then
            auditTempoTick = 1
        End If
        While session_TempoIndexExactForTick(auditTempoTick) >= 0 OrElse _
            session_TimeSignatureIndexExactForTick(auditTempoTick) >= 0 OrElse _
            session_KeySignatureIndexExactForTick(auditTempoTick) >= 0
            If auditTempoTick >= OSE_MAX_MIDI_TICK Then
                auditTempoTick = 1
            Else
                auditTempoTick += 1
            End If
        Wend
        Dim As Integer addedTempoBpm = session_InitialTempoBpm() + 2
        If addedTempoBpm > 399 Then
            addedTempoBpm = session_InitialTempoBpm() - 2
        End If
        textbox_SetText session_TempoMapTickValueLabel, _
            Str(auditTempoTick), -1
        textbox_SetText session_TempoMapBpmBox, Str(addedTempoBpm), -1
        session_OnAddTempoMap 0
        session_AuditBehavior _
            session_Summary.tempoCount = originalTempoCount + 1 AndAlso _
            session_Summary.timeSignatureCount = originalMeterCount + 1 AndAlso _
            session_Summary.keySignatureCount = originalKeyCount + 1 AndAlso _
            session_Summary.tempoMap( _
                session_TempoMapSelectedIndex).tick = auditTempoTick, _
            "Tempo Map New did not add one complete map point", _
            behaviorCheckCount, errorText

        ' Each mutation route must leave a running transport and the model
        ' intact, including restoring any edited controls to stored values.
        undoCount = documentHistory_UndoCount(session_DocumentHistory)
        redoCount = documentHistory_RedoCount(session_DocumentHistory)
        dirtyState = session_Dirty
        session_OnPlay 0
        Dim As Double runningElapsed = session_PlaybackElapsed
        textbox_SetText session_TempoMapBpmBox, Str(addedTempoBpm + 1), -1
        session_OnApplyTempoMap 0
        session_AuditBehavior session_Playing <> 0 AndAlso _
            session_PlaybackElapsed = runningElapsed AndAlso _
            session_TempoPointBpm(session_TempoMapSelectedIndex) = addedTempoBpm _
            AndAlso Trim(textbox_GetText(session_TempoMapBpmBox)) = _
                Trim(Str(addedTempoBpm)) AndAlso session_StatusText = _
                "Press Stop before changing playback speed or tempo.", _
            "Tempo Map Apply changed a running tempo or retained a rejected BPM", _
            behaviorCheckCount, errorText

        Dim As ULongInt blockedTempoTick = auditTempoTick
        Do
            If blockedTempoTick >= OSE_MAX_MIDI_TICK Then
                blockedTempoTick = 1
            Else
                blockedTempoTick += 1
            End If
        Loop While session_TempoIndexExactForTick(blockedTempoTick) >= 0
        textbox_SetText session_TempoMapTickValueLabel, Str(blockedTempoTick), -1
        session_OnAddTempoMap 0
        session_AuditBehavior session_Playing <> 0 AndAlso _
            session_PlaybackElapsed = runningElapsed AndAlso _
            session_Summary.tempoCount = originalTempoCount + 1 AndAlso _
            Trim(textbox_GetText(session_TempoMapTickValueLabel)) = _
                Trim(Str(auditTempoTick)) AndAlso session_StatusText = _
                "Press Stop before changing playback speed or tempo.", _
            "Tempo Map New changed a running map or retained its rejected tick", _
            behaviorCheckCount, errorText
        session_OnDeleteTempoMap 0
        session_AuditBehavior session_Playing <> 0 AndAlso _
            session_PlaybackElapsed = runningElapsed AndAlso _
            session_Summary.tempoCount = originalTempoCount + 1 AndAlso _
            session_TempoIndexExactForTick(auditTempoTick) >= 0 AndAlso _
            session_StatusText = "Press Stop before changing playback speed or tempo.", _
            "Tempo Map Delete removed a point from a running map", _
            behaviorCheckCount, errorText
        session_AuditHistoryUnchanged undoCount, redoCount, dirtyState, _
            "Rejected active tempo-map changes altered document history", _
            behaviorCheckCount, errorText
        session_OnStop 0

        Dim As Integer changedTempoBpm = addedTempoBpm + 1
        textbox_SetText session_TempoMapBpmBox, Str(changedTempoBpm), -1
        session_OnApplyTempoMap 0
        session_AuditBehavior _
            session_TempoPointBpm(session_TempoMapSelectedIndex) = _
                changedTempoBpm, _
            "Tempo Map Apply did not store its new BPM", _
            behaviorCheckCount, errorText

        session_OnDeleteTempoMap 0
        session_AuditBehavior _
            session_Summary.tempoCount = originalTempoCount AndAlso _
            session_Summary.timeSignatureCount = originalMeterCount AndAlso _
            session_Summary.keySignatureCount = originalKeyCount, _
            "Tempo Map Delete left an orphaned tempo, meter, or key point", _
            behaviorCheckCount, errorText
        session_CloseTempoMapWindow()

        session_OnEditMenu 0
        Dim As Integer restoredTempoDelete = _
            session_Summary.tempoCount = originalTempoCount + 1 AndAlso _
            session_Summary.timeSignatureCount = originalMeterCount + 1 AndAlso _
            session_Summary.keySignatureCount = originalKeyCount + 1
        session_OnEditMenu 0
        Dim As Integer restoredTempoApply = _
            session_TempoPointBpm( _
                session_TempoIndexExactForTick(auditTempoTick)) = addedTempoBpm
        session_OnEditMenu 0
        session_AuditBehavior restoredTempoDelete <> 0 AndAlso _
            restoredTempoApply <> 0 AndAlso _
            session_Summary.tempoCount = originalTempoCount AndAlso _
            session_Summary.timeSignatureCount = originalMeterCount AndAlso _
            session_Summary.keySignatureCount = originalKeyCount, _
            "Tempo Map New, Apply, and Delete did not undo chronologically", _
            behaviorCheckCount, errorText
    End If

    session_Dirty = originalDirtyState
End Sub


Private Sub session_AuditSemanticTrackMutations( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    Dim As Integer originalDirtyState = session_Dirty
    Dim As MidiEditableNote quantizeOriginalNote
    Dim As Integer quantizeFixtureReady = 0
    If midi_GetEditableNoteCount() > 0 AndAlso _
        midi_GetEditableNote(0, quantizeOriginalNote) <> 0 Then
        Dim As MidiEditableNote unquantizedNote = quantizeOriginalNote
        unquantizedNote.startTick = 1
        If quantizeOriginalNote.startTick = 1 Then
            unquantizedNote.startTick = 2
        End If
        If session_BeginMidiEdit() <> 0 Then
            If midi_SetEditableNote(session_Summary, 0, unquantizedNote) <> 0 _
                AndAlso session_CommitMidiEdit() <> 0 Then
                quantizeFixtureReady = -1
                session_SelectTrack unquantizedNote.trackIndex
            Else
                session_CancelMidiEdit()
            End If
        End If
    End If

    Dim As String originalTrackName = _
        session_Summary.tracks(session_SelectedTrack).name
    session_OnTrackProperties 0
    If session_TrackWindow <> 0 Then
        Dim As Integer undoCount = _
            documentHistory_UndoCount(session_DocumentHistory)
        Dim As Integer redoCount = _
            documentHistory_RedoCount(session_DocumentHistory)
        Dim As Integer dirtyState = session_Dirty
        session_OnApplyTrackProperties 0
        session_AuditHistoryUnchanged undoCount, redoCount, dirtyState, _
            "Unchanged track properties altered document history", _
            behaviorCheckCount, errorText
        session_AuditBehavior session_StatusText = _
            "Track and document information are unchanged.", _
            "Unchanged track properties were not reported", _
            behaviorCheckCount, errorText

        If quantizeFixtureReady <> 0 Then
            textbox_SetText session_QuantizeGridBox, "120", -1
            session_OnQuantizeTrack 0
            Dim As MidiEditableNote quantizedNote
            session_AuditBehavior _
                midi_GetEditableNote(0, quantizedNote) <> 0 AndAlso _
                quantizedNote.startTick = 0, _
                "Quantize did not move the off-grid note to its nearest grid", _
                behaviorCheckCount, errorText

            undoCount = documentHistory_UndoCount(session_DocumentHistory)
            redoCount = documentHistory_RedoCount(session_DocumentHistory)
            dirtyState = session_Dirty
            textbox_SetText session_QuantizeGridBox, "1", -1
            session_OnQuantizeTrack 0
            session_AuditHistoryUnchanged undoCount, redoCount, dirtyState, _
                "No-op quantize altered document history", _
                behaviorCheckCount, errorText
            session_AuditBehavior Left(session_StatusText, 24) = _
                "Quantize made no changes", _
                "No-op quantize was not reported", behaviorCheckCount, errorText
        End If

        Dim As String changedTrackName = "Audit Track"
        If originalTrackName = changedTrackName Then _
            changedTrackName = "Audit Track 2"
        textbox_SetText session_TrackNameBox, changedTrackName, -1
        session_OnApplyTrackProperties 0
        session_AuditBehavior _
            session_Summary.tracks(session_SelectedTrack).name = changedTrackName, _
            "Track Properties Apply did not store its new name", _
            behaviorCheckCount, errorText
        session_CloseTrackPropertiesWindow()

        session_OnEditMenu 0
        Dim As Integer restoredTrackName = _
            session_Summary.tracks(session_SelectedTrack).name = originalTrackName
        If quantizeFixtureReady <> 0 Then
            session_OnEditMenu 0
            Dim As MidiEditableNote restoredUnquantizedNote
            Dim As Integer restoredQuantize = _
                midi_GetEditableNote(0, restoredUnquantizedNote) <> 0 AndAlso _
                restoredUnquantizedNote.startTick <> 0
            session_OnEditMenu 0
            Dim As MidiEditableNote restoredQuantizeFixture
            session_AuditBehavior restoredTrackName <> 0 AndAlso _
                restoredQuantize <> 0 AndAlso _
                midi_GetEditableNote(0, restoredQuantizeFixture) <> 0 AndAlso _
                restoredQuantizeFixture.startTick = _
                    quantizeOriginalNote.startTick, _
                "Track and quantize edits did not undo chronologically", _
                behaviorCheckCount, errorText
        Else
            session_AuditBehavior restoredTrackName <> 0, _
                "Undo did not restore Track Properties Apply", _
                behaviorCheckCount, errorText
        End If
    End If

    session_Dirty = originalDirtyState
End Sub


Private Sub session_AuditSemanticToolbarNoOp( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    Dim As Integer originalDirtyState = session_Dirty
    textbox_SetText session_TempoBox, Str(session_InitialTempoBpm()), -1
    session_OnPlay 0
    Dim As Integer undoCount = documentHistory_UndoCount(session_DocumentHistory)
    Dim As Integer redoCount = documentHistory_RedoCount(session_DocumentHistory)
    Dim As Integer dirtyState = session_Dirty
    session_OnApplyTempo 0
    session_AuditHistoryUnchanged undoCount, redoCount, dirtyState, _
        "Unchanged toolbar tempo altered document history", _
        behaviorCheckCount, errorText
    session_AuditBehavior session_Playing <> 0, _
        "Unchanged toolbar tempo stopped active transport", _
        behaviorCheckCount, errorText
    session_AuditBehavior Left(session_StatusText, 24) = _
        "Initial tempo is already", _
        "Unchanged toolbar tempo was not reported", _
        behaviorCheckCount, errorText

    Dim As Integer originalTempo = session_InitialTempoBpm()
    undoCount = documentHistory_UndoCount(session_DocumentHistory)
    redoCount = documentHistory_RedoCount(session_DocumentHistory)
    dirtyState = session_Dirty
    textbox_SetText session_TempoBox, Str(originalTempo) + "bpm", -1
    session_OnApplyTempo 0
    session_AuditHistoryUnchanged undoCount, redoCount, dirtyState, _
        "Malformed toolbar tempo altered document history", _
        behaviorCheckCount, errorText
    session_AuditBehavior session_InitialTempoBpm() = originalTempo, _
        "Malformed toolbar tempo changed the document", _
        behaviorCheckCount, errorText
    session_AuditBehavior session_Playing <> 0, _
        "Malformed toolbar tempo stopped active transport", _
        behaviorCheckCount, errorText
    session_AuditBehavior session_StatusText = _
        "Tempo must be an integer from 20 to 400 BPM.", _
        "Malformed toolbar tempo was not rejected", _
        behaviorCheckCount, errorText

    Dim As Integer requestedTempo = originalTempo + 1
    If requestedTempo > 400 Then
        requestedTempo = originalTempo - 1
    End If
    Dim As Double runningElapsed = session_PlaybackElapsed
    textbox_SetText session_TempoBox, Str(requestedTempo), -1
    session_OnApplyTempo 0
    session_AuditBehavior session_Playing <> 0 AndAlso _
        session_PlaybackElapsed = runningElapsed AndAlso _
        session_InitialTempoBpm() = originalTempo AndAlso _
        Trim(textbox_GetText(session_TempoBox)) = Trim(Str(originalTempo)) AndAlso _
        session_StatusText = "Press Stop before changing playback speed or tempo.", _
        "Toolbar tempo changed an active run or retained its rejected BPM", _
        behaviorCheckCount, errorText
    session_AuditHistoryUnchanged undoCount, redoCount, dirtyState, _
        "Rejected active toolbar tempo altered document history", _
        behaviorCheckCount, errorText
    session_OnStop 0
    textbox_SetText session_TempoBox, Str(requestedTempo), -1
    session_OnApplyTempo 0
    session_AuditBehavior session_Playing = 0 AndAlso _
        session_InitialTempoBpm() = requestedTempo AndAlso _
        Trim(textbox_GetText(session_TempoBox)) = Trim(Str(requestedTempo)), _
        "Toolbar tempo did not accept the same edit after Stop", _
        behaviorCheckCount, errorText
    session_OnEditMenu 0
    session_AuditBehavior session_InitialTempoBpm() = originalTempo, _
        "Stopped toolbar tempo edit did not undo cleanly", _
        behaviorCheckCount, errorText
    textbox_SetText session_TempoBox, Str(originalTempo), -1
    session_OnStop 0
    session_Dirty = originalDirtyState
End Sub


Private Sub session_AuditSemanticMixerPointerControls( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    /'
        Exercise every code-drawn mixer face through session_UpdateMixerInput.
        MIDI drag edits are inspected while pressed and then cancelled so this
        exhaustive audit cannot consume the user's bounded undo history.
    '/
    Const fullWidth As Integer = SESSION_INITIAL_WIDTH
    Const fullHeight As Integer = SESSION_INITIAL_HEIGHT
    Dim As Integer originalPageAnchor = session_MixerPageAnchor
    Dim As Integer originalSelectedTrack = session_SelectedTrack
    Dim As OseMixerChannelState originalMixerState = session_MixerChannels
    Dim As Single originalMasterVolume = session_MasterVolume
    Dim As Single originalMasterWet = session_MasterEchoWet
    Dim As Single originalMasterFeedback = session_MasterEchoFeedback

    input_ResetForTest()
    session_LastMouseButtons = 0
    session_MixerPageAnchor = 0
    Dim As OseMixerControlLayout fullLayout
    mixerControls_CalculateLayoutForInteraction fullLayout, fullWidth, _
        fullHeight, session_MixerPageAnchor, session_InteractionMode
    If fullLayout.visibleCount <= 0 OrElse _
        fullLayout.visibleCount > SESSION_CHANNEL_COUNT OrElse _
        fullLayout.firstChannel <> 0 Then
        session_AppendControlAuditError errorText, _
            "full-width mixer pointer audit has invalid initial paging"
    Else
        For channelIndex As Integer = 0 To SESSION_CHANNEL_COUNT - 1
            session_MixerPageAnchor = channelIndex
            mixerControls_CalculateLayoutForInteraction fullLayout, fullWidth, _
                fullHeight, session_MixerPageAnchor, session_InteractionMode
            Dim As Integer slotIndex = channelIndex - fullLayout.firstChannel
            Dim As Integer stripLeft = mixerControls_StripLeft( _
                fullLayout, slotIndex)
            Dim As Integer stripRight = mixerControls_StripRight( _
                fullLayout, slotIndex)
            Dim As Integer stripWidth = stripRight - stripLeft + 1

            For controlKind As Integer = _
                OSE_MIXER_CONTROL_CHANNEL_FADER To _
                OSE_MIXER_CONTROL_CHANNEL_PAN
                Dim As Integer originalValue = session_AuditMixerMidiValue( _
                    controlKind, channelIndex)
                Dim As Integer pointerX
                Dim As Integer pointerY
                If controlKind = OSE_MIXER_CONTROL_CHANNEL_FADER Then
                    pointerX = mixerControls_ChannelFaderX(fullLayout, slotIndex)
                    pointerY = IIf(originalValue > 63, _
                        fullLayout.faderBottom, fullLayout.faderTop)
                Else
                    Dim As Integer knobIndex = controlKind - _
                        OSE_MIXER_CONTROL_CHANNEL_CHORUS
                    Dim As Integer knobCellLeft = stripLeft + _
                        (knobIndex * stripWidth) \ 3
                    Dim As Integer knobCellRight = stripLeft + _
                        ((knobIndex + 1) * stripWidth) \ 3 - 1
                    pointerX = IIf(originalValue > 63, _
                        knobCellLeft, knobCellRight)
                    pointerY = fullLayout.knobTop + 1
                End If

                Dim As Integer expectedValue = session_RoundNonnegative( _
                    mixerControls_ValueForControl(fullLayout, controlKind, _
                        channelIndex, pointerX, pointerY) * 127.0)
                session_AuditMockMixerPress pointerX, pointerY, _
                    fullWidth, fullHeight
                Dim As Integer changedAsExpected = _
                    expectedValue <> originalValue AndAlso _
                    session_AuditMixerMidiValue(controlKind, channelIndex) = _
                        expectedValue AndAlso _
                    session_MixerDragKind = controlKind AndAlso _
                    session_MixerDragChannel = channelIndex AndAlso _
                    session_MixerDragMidiChanged <> 0
                Dim As Integer cancelled = session_CancelMidiEdit()
                session_MixerDragKind = OSE_MIXER_CONTROL_NONE
                session_MixerDragChannel = -1
                session_MixerDragMidiChanged = 0
                session_RefreshMixerFromSummary()
                session_AuditMockMixerRelease pointerX, pointerY, _
                    fullWidth, fullHeight
                session_AuditBehavior changedAsExpected <> 0 AndAlso _
                    cancelled <> 0 AndAlso _
                    session_AuditMixerMidiValue(controlKind, channelIndex) = _
                        originalValue, _
                    "Mixer MIDI pointer face " + Str(controlKind) + _
                        " on channel " + Str(channelIndex + 1) + _
                        " did not mutate and cancel cleanly (expected " + _
                        Str(expectedValue) + ", changed " + _
                        Str(changedAsExpected) + ", cancel " + _
                        Str(cancelled) + ")", _
                    behaviorCheckCount, errorText
            Next
        Next
    End If

    /'
        Mute, Solo, and Record are independent faces on every strip. Start from
        a neutral state so Record's exclusive-channel rule has an unambiguous
        round trip for each of the sixteen channels.
    '/
    mixerState_Initialize session_MixerChannels
    session_ApplyMixerState()
    For channelIndex As Integer = 0 To SESSION_CHANNEL_COUNT - 1
        session_MixerPageAnchor = channelIndex
        mixerControls_CalculateLayoutForInteraction fullLayout, fullWidth, _
            fullHeight, session_MixerPageAnchor, session_InteractionMode
        Dim As Integer slotIndex = channelIndex - fullLayout.firstChannel
        Dim As Integer stripLeft = mixerControls_StripLeft(fullLayout, slotIndex)
        Dim As Integer stripRight = mixerControls_StripRight(fullLayout, slotIndex)
        Dim As Integer stripWidth = stripRight - stripLeft + 1
        For buttonIndex As Integer = 0 To 2
            Dim As Integer buttonCellLeft = stripLeft + _
                (buttonIndex * stripWidth) \ 3
            Dim As Integer buttonCellRight = stripLeft + _
                ((buttonIndex + 1) * stripWidth) \ 3 - 1
            Dim As Integer pointerX = _
                (buttonCellLeft + buttonCellRight) \ 2
            Dim As Integer pointerY = fullLayout.buttonTop + 8
            session_AuditMockMixerClick pointerX, pointerY, _
                fullWidth, fullHeight
            Dim As Integer activated
            Select Case buttonIndex
                Case 0
                    activated = session_MixerChannels.mute(channelIndex)
                Case 1
                    activated = session_MixerChannels.solo(channelIndex)
                Case 2
                    activated = session_MixerChannels.record(channelIndex)
            End Select
            session_AuditMockMixerClick pointerX, pointerY, _
                fullWidth, fullHeight
            Dim As Integer restored
            Select Case buttonIndex
                Case 0
                    restored = _
                    session_MixerChannels.mute(channelIndex) = 0
                Case 1
                    restored = _
                    session_MixerChannels.solo(channelIndex) = 0
                Case 2
                    restored = _
                    session_MixerChannels.record(channelIndex) = 0
            End Select
            session_AuditBehavior activated <> 0 AndAlso restored <> 0, _
                "Mixer button face " + Str(buttonIndex) + _
                    " on channel " + Str(channelIndex + 1) + _
                    " did not toggle and restore", _
                behaviorCheckCount, errorText
        Next
    Next

    For masterKind As Integer = OSE_MIXER_CONTROL_MASTER_FADER To _
        OSE_MIXER_CONTROL_MASTER_FEEDBACK
        Dim As Integer pointerX
        Dim As Integer pointerY
        Dim As Single originalValue
        Select Case masterKind
            Case OSE_MIXER_CONTROL_MASTER_FADER
                originalValue = session_MasterVolume
                pointerX = fullLayout.masterLeft + 31
                pointerY = IIf(originalValue > 0.5, _
                    fullLayout.faderBottom, fullLayout.faderTop)
            Case OSE_MIXER_CONTROL_MASTER_WET
                originalValue = session_MasterEchoWet
                pointerX = fullLayout.masterLeft + 103 + _
                    IIf(originalValue > 0.5, 0, 24)
                pointerY = fullLayout.faderTop + 21
            Case OSE_MIXER_CONTROL_MASTER_FEEDBACK
                originalValue = session_MasterEchoFeedback
                pointerX = fullLayout.masterLeft + 128 + _
                    IIf(originalValue > 0.5, 0, 24)
                pointerY = fullLayout.faderTop + 21
        End Select
        Dim As Single expectedValue = mixerControls_ValueForControl( _
            fullLayout, masterKind, -1, pointerX, pointerY)
        session_AuditMockMixerClick pointerX, pointerY, fullWidth, fullHeight
        Dim As Single currentValue
        Select Case masterKind
            Case OSE_MIXER_CONTROL_MASTER_FADER
                currentValue = session_MasterVolume
                session_MasterVolume = originalValue
            Case OSE_MIXER_CONTROL_MASTER_WET
                currentValue = session_MasterEchoWet
                session_MasterEchoWet = originalValue
            Case OSE_MIXER_CONTROL_MASTER_FEEDBACK
                currentValue = session_MasterEchoFeedback
                session_MasterEchoFeedback = originalValue
        End Select
        session_AuditBehavior Abs(currentValue - expectedValue) < 0.0001 _
            AndAlso Abs(expectedValue - originalValue) > 0.0001, _
            "Mixer master pointer face " + Str(masterKind) + _
                " did not set its advertised value", _
            behaviorCheckCount, errorText
    Next

    session_MixerPageAnchor = 0
    Dim As OseMixerControlLayout narrowLayout
    mixerControls_CalculateLayoutForInteraction narrowLayout, 800, 600, _
        session_MixerPageAnchor, session_InteractionMode
    session_AuditMockMixerClick narrowLayout.pageNextLeft + _
        narrowLayout.pageButtonWidth \ 2, narrowLayout.pageButtonTop + _
        narrowLayout.pageButtonHeight \ 2, 800, 600
    mixerControls_CalculateLayoutForInteraction narrowLayout, 800, 600, _
        session_MixerPageAnchor, session_InteractionMode
    Dim As Integer pagingAdvanced = narrowLayout.firstChannel > 0
    Dim As Integer pageAuditGuard
    While narrowLayout.firstChannel + narrowLayout.visibleCount < _
        SESSION_CHANNEL_COUNT AndAlso pageAuditGuard < SESSION_CHANNEL_COUNT
        session_AuditMockMixerClick narrowLayout.pageNextLeft + _
            narrowLayout.pageButtonWidth \ 2, narrowLayout.pageButtonTop + _
            narrowLayout.pageButtonHeight \ 2, 800, 600
        mixerControls_CalculateLayoutForInteraction narrowLayout, 800, 600, _
            session_MixerPageAnchor, session_InteractionMode
        pageAuditGuard += 1
    Wend
    session_AuditBehavior pagingAdvanced <> 0 AndAlso _
        narrowLayout.firstChannel + narrowLayout.visibleCount = _
            SESSION_CHANNEL_COUNT, _
        "Mixer Next page did not expose the final channels", _
        behaviorCheckCount, errorText

    pageAuditGuard = 0
    While narrowLayout.firstChannel > 0 AndAlso _
        pageAuditGuard < SESSION_CHANNEL_COUNT
        session_AuditMockMixerClick narrowLayout.pagePreviousLeft + _
            narrowLayout.pageButtonWidth \ 2, narrowLayout.pageButtonTop + _
            narrowLayout.pageButtonHeight \ 2, 800, 600
        mixerControls_CalculateLayoutForInteraction narrowLayout, 800, 600, _
            session_MixerPageAnchor, session_InteractionMode
        pageAuditGuard += 1
    Wend
    session_AuditBehavior narrowLayout.firstChannel = 0, _
        "Mixer Previous page did not restore the first channels", _
        behaviorCheckCount, errorText

    session_MixerPageAnchor = originalPageAnchor
    session_MixerChannels = originalMixerState
    session_MasterVolume = originalMasterVolume
    session_MasterEchoWet = originalMasterWet
    session_MasterEchoFeedback = originalMasterFeedback
    session_SelectedTrack = originalSelectedTrack
    session_ApplyMixerState()
    session_ApplyMasterEffect()
    session_LastMouseButtons = 0
    input_ResetForTest()
End Sub


Private Sub session_AuditSemanticMidiDevices( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    session_OnMidiInput 0
    If session_MidiInputWindow <> 0 Then
        Dim As Integer inputDeviceCount = midiInput_GetDeviceCount()
        session_OnMidiInputOpenSelected 0
        If inputDeviceCount > 0 Then
            session_AuditBehavior midiInput_IsOpen() <> 0, _
                "MIDI Input Open did not open the selected device", _
                behaviorCheckCount, errorText
        Else
            session_AuditBehavior session_StatusText = _
                "No Windows MIDI input devices are available.", _
                "MIDI Input Open did not report unavailable hardware", _
                behaviorCheckCount, errorText
        End If
        session_OnMidiInputCloseSelected 0
        session_AuditBehavior midiInput_IsOpen() = 0, _
            "MIDI Input Close left a device open", _
            behaviorCheckCount, errorText
        session_CloseMidiInputWindow()
    End If

    session_OnMidiOutput 0
    If session_MidiOutputWindow <> 0 Then
        Dim As Integer outputDeviceCount = midiOutput_GetDeviceCount()
        session_OnMidiOutputOpenSelected 0
        If outputDeviceCount > 0 Then
            session_AuditBehavior midiOutput_IsOpen() <> 0 AndAlso _
                session_MidiOutputOpened <> 0, _
                "MIDI Output Open did not open the selected device", _
                behaviorCheckCount, errorText
        Else
            session_AuditBehavior session_StatusText = _
                "No MIDI output devices are available.", _
                "MIDI Output Open did not report unavailable hardware", _
                behaviorCheckCount, errorText
        End If
        session_OnMidiOutputCloseSelected 0
        session_AuditBehavior midiOutput_IsOpen() = 0 AndAlso _
            session_MidiOutputOpened = 0, _
            "MIDI Output Close left a device open", _
            behaviorCheckCount, errorText
        session_CloseMidiOutputWindow()
    End If
End Sub


Private Sub session_AuditSemanticKeyboardNavigation( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    /'
        Exercise the same retained input events used by a physical keyboard.
        These checks prove focus traversal and command activation instead of
        assuming that a non-null callback makes a control keyboard usable.
    '/
    input_ResetForTest()
    gui_SetFocus 0
    gui_UpdateAll()

    input_MockKeyPress FB.SC_TAB
    gui_UpdateAll()
    Dim As Widget Ptr focusedWidget = gui_GetFocus()
    session_AuditBehavior focusedWidget <> 0 AndAlso _
        focusedWidget->name = "new" AndAlso _
        gui_IsKeyboardNavigationActive() <> 0, _
        "Tab did not focus the first toolbar command", _
        behaviorCheckCount, errorText

    input_MockKeyPress FB.SC_TAB
    gui_UpdateAll()
    focusedWidget = gui_GetFocus()
    session_AuditBehavior focusedWidget <> 0 AndAlso _
        focusedWidget->name = "open", _
        "second Tab did not advance toolbar focus", _
        behaviorCheckCount, errorText

    input_MockKeyPress KEY_RETURN
    gui_UpdateAll()
    session_AuditBehavior session_FileDialog <> 0 AndAlso _
        session_FileDialogMode = SESSION_DIALOG_OPEN, _
        "Enter did not activate the focused Open command", _
        behaviorCheckCount, errorText
    session_AuditCloseFileDialog()

    gui_SetFocus(gui_FindWidget("new"))
    input_MockKeyPress FB.SC_TAB, INPUT_MODIFIER_SHIFT
    gui_UpdateAll()
    focusedWidget = gui_GetFocus()
    session_AuditBehavior focusedWidget <> 0 AndAlso _
        focusedWidget->name <> "new", _
        "Shift+Tab did not wrap backward through eligible controls", _
        behaviorCheckCount, errorText

    gui_SetFocus(gui_FindWidget("open"))
    input_MockKeyPress FB.SC_F, INPUT_MODIFIER_ALT
    gui_UpdateAll()
    session_ProcessMenuBar()
    Dim As MenuData Ptr fileMenuState = Cast(MenuData Ptr, session_FileMenu->data)
    session_AuditBehavior session_FileMenu->visible <> 0 AndAlso _
        fileMenuState->selected = 0 AndAlso gui_GetFocus() = 0, _
        "Alt+F did not open and select the File menu", _
        behaviorCheckCount, errorText

    input_MockKeyPress KEY_DOWN
    gui_UpdateAll()
    session_ProcessMenuBar()
    session_AuditBehavior fileMenuState->selected = 1, _
        "Down did not advance the keyboard menu selection", _
        behaviorCheckCount, errorText

    input_MockKeyPress KEY_RIGHT
    gui_UpdateAll()
    session_ProcessMenuBar()
    Dim As MenuData Ptr editMenuState = Cast(MenuData Ptr, session_EditMenu->data)
    session_AuditBehavior session_EditMenu->visible <> 0 AndAlso _
        session_FileMenu->visible = 0 AndAlso editMenuState->selected = 0, _
        "Right did not switch to the next desktop menu", _
        behaviorCheckCount, errorText

    input_MockKeyPress KEY_LEFT
    gui_UpdateAll()
    session_ProcessMenuBar()
    input_MockKeyPress KEY_DOWN
    gui_UpdateAll()
    session_ProcessMenuBar()
    input_MockKeyPress KEY_RETURN
    gui_UpdateAll()
    session_ProcessMenuBar()
    session_AuditBehavior session_FileDialog <> 0 AndAlso _
        session_FileDialogMode = SESSION_DIALOG_OPEN AndAlso _
        session_FileMenu->visible = 0, _
        "Enter did not activate a keyboard-selected menu command", _
        behaviorCheckCount, errorText
    session_AuditCloseFileDialog()

    input_MockKeyPress FB.SC_H, INPUT_MODIFIER_ALT
    gui_UpdateAll()
    session_ProcessMenuBar()
    input_MockKeyPress KEY_RETURN
    gui_UpdateAll()
    session_ProcessMenuBar()
    session_AuditBehavior session_AboutWindow <> 0, _
        "Alt+H and Enter did not open About", _
        behaviorCheckCount, errorText
    session_CloseAboutWindow()

    input_MockKeyPress FB.SC_F, INPUT_MODIFIER_ALT
    gui_UpdateAll()
    session_ProcessMenuBar()
    input_MockKeyPress KEY_ESCAPE
    gui_UpdateAll()
    session_ProcessMenuBar()
    session_AuditBehavior session_VisibleDesktopMenuIndex() < 0 AndAlso _
        session_MenuEscapeConsumed <> 0, _
        "Escape did not dismiss the menu without requesting exit", _
        behaviorCheckCount, errorText

    session_OnHelpMenu 0
    input_MockKeyPress FB.SC_F, INPUT_MODIFIER_ALT
    gui_UpdateAll()
    session_ProcessMenuBar()
    session_AuditBehavior session_FileMenu->visible = 0, _
        "a modal window did not block desktop menu shortcuts", _
        behaviorCheckCount, errorText
    session_CloseAboutWindow()
    session_HideDesktopMenus()
    session_MenuKeyboardAccess = 0
    gui_SetFocus 0
End Sub


Private Sub session_AuditSemanticKeyboardPointerControls( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    /'
        The performance keys are also code-drawn controls. Press and release
        every white and black face through the window's real pointer handler,
        then require both the advertised pitch and its audition lifetime.
        Physical-key checks also run step-record dispatch in main-loop order,
        because both input paths retain state across complete UI frames.
    '/
    Dim As Integer originalBasePitch = session_KeyboardBasePitch
    session_KeyboardBasePitch = 60
    input_ResetForTest()
    session_OnKeyboard 0
    If session_KeyboardWindow = 0 Then
        session_AppendControlAuditError errorText, _
            "performance keyboard pointer audit could not open its window"
        session_KeyboardBasePitch = originalBasePitch
        Exit Sub
    End If
    gui_UpdateAll()

    For whiteIndex As Integer = 0 To OSE_KEYBOARD_WHITE_KEY_COUNT - 1
        Dim As Integer expectedPitch = keyboardControls_WhitePitch( _
            session_KeyboardBasePitch, whiteIndex)
        Dim As Integer pointerX = session_KeyboardWindow->ax + _
            OSE_KEYBOARD_LEFT + whiteIndex * OSE_KEYBOARD_WHITE_KEY_WIDTH + _
            OSE_KEYBOARD_WHITE_KEY_WIDTH \ 2
        Dim As Integer pointerY = session_KeyboardWindow->ay + _
            OSE_KEYBOARD_TOP + OSE_KEYBOARD_BLACK_KEY_HEIGHT + 12
        input_MockMouse pointerX, pointerY, 1
        input_Update()
        session_ProcessKeyboardWindow()
        Dim As Integer started = _
            session_KeyboardMousePitch = expectedPitch AndAlso _
            expectedPitch >= 0 AndAlso _
            session_AuditionChannelForPitch(expectedPitch) >= 0
        input_MockMouse pointerX, pointerY, 0
        input_Update()
        session_ProcessKeyboardWindow()
        Dim As Integer stopped = session_KeyboardMousePitch = -1 AndAlso _
            session_AuditionChannelForPitch(expectedPitch) = -1
        session_AuditBehavior started <> 0 AndAlso stopped <> 0, _
            "Performance keyboard white face " + Str(whiteIndex) + _
                " did not audition and release its pitch", _
            behaviorCheckCount, errorText
    Next

    For blackIndex As Integer = 0 To OSE_KEYBOARD_BLACK_KEY_COUNT - 1
        Dim As Integer blackExpectedPitch = keyboardControls_BlackPitch( _
            session_KeyboardBasePitch, blackIndex)
        Dim As Integer blackPointerX = session_KeyboardWindow->ax + _
            keyboardControls_BlackLeft(blackIndex) + _
            OSE_KEYBOARD_BLACK_KEY_WIDTH \ 2
        Dim As Integer blackPointerY = session_KeyboardWindow->ay + _
            OSE_KEYBOARD_TOP + 12
        input_MockMouse blackPointerX, blackPointerY, 1
        input_Update()
        session_ProcessKeyboardWindow()
        Dim As Integer blackStarted = _
            session_KeyboardMousePitch = blackExpectedPitch AndAlso _
            blackExpectedPitch >= 0 AndAlso _
            session_AuditionChannelForPitch(blackExpectedPitch) >= 0
        input_MockMouse blackPointerX, blackPointerY, 0
        input_Update()
        session_ProcessKeyboardWindow()
        Dim As Integer blackStopped = session_KeyboardMousePitch = -1 AndAlso _
            session_AuditionChannelForPitch(blackExpectedPitch) = -1
        session_AuditBehavior blackStarted <> 0 AndAlso blackStopped <> 0, _
            "Performance keyboard black face " + Str(blackIndex) + _
                " did not audition and release its pitch", _
            behaviorCheckCount, errorText
    Next

    Dim As OseMixerChannelState originalMixerState = session_MixerChannels
    Dim As Integer notesBeforePcKeys = midi_GetEditableNoteCount()
    For recordMode As Integer = 0 To 1
        For channelIndex As Integer = 0 To SESSION_CHANNEL_COUNT - 1
            session_MixerChannels.record(channelIndex) = 0
        Next
        session_MixerChannels.record(0) = IIf(recordMode <> 0, -1, 0)
        session_StopAllAuditionNotes()
        session_ResetLiveKeyboardState()
        input_ResetForTest()
        input_MockKey FB.SC_Z, -1
        gui_UpdateAll()
        session_ProcessKeyboardWindow()
        session_ProcessStepRecording()
        Dim As Integer pcPitch = session_StepEntryPitch(FB.SC_Z)
        Dim As Integer pcChannel = session_AuditionChannelForPitch(pcPitch)
        session_AuditBehavior pcChannel >= 0, _
            "PC piano key did not start in record-arm mode " + Str(recordMode), _
            behaviorCheckCount, errorText

        gui_UpdateAll()
        session_ProcessKeyboardWindow()
        session_ProcessStepRecording()
        session_AuditBehavior _
            session_AuditionChannelForPitch(pcPitch) = pcChannel AndAlso _
            midi_GetEditableNoteCount() = notesBeforePcKeys, _
            "held PC piano key changed its audition or inserted a step note", _
            behaviorCheckCount, errorText

        input_MockKey FB.SC_Z, 0
        gui_UpdateAll()
        session_ProcessKeyboardWindow()
        session_ProcessStepRecording()
        session_AuditBehavior session_AuditionChannelForPitch(pcPitch) = -1, _
            "PC piano key release retained its audition in record-arm mode " + _
                Str(recordMode), behaviorCheckCount, errorText
    Next
    session_MixerChannels = originalMixerState
    session_CloseKeyboardWindow()
    session_KeyboardBasePitch = originalBasePitch
    input_ResetForTest()
End Sub


Private Sub session_AuditNoteTools( _
    ByRef widgetActionCount As Integer, ByRef behaviorCheckCount As Integer, ByRef errorText As String _
)
    Dim As Integer originalNotes = midi_GetEditableNoteCount()
    Dim As Integer originalSnap = session_SnapIndex
    Dim As ULongInt originalView = session_ViewStartTick
    If session_BeginMidiEdit() = 0 Then
        Exit Sub
    End If
    midi_AddEditableNote session_Summary, 0, 13, 90, 60, 0, 100
    midi_AddEditableNote session_Summary, 0, 133, 70, 38, 9, 100
    If session_CommitMidiEdit() = 0 Then
        Exit Sub
    End If
    session_SelectOnlyNote originalNotes
    noteSelection_Add session_NoteSelection, originalNotes + 1, 0
    input_ResetForTest()
    gui_UpdateAll()
    input_MockMouse session_NoteToolsButton->ax + 10, session_NoteToolsButton->ay + 10, 1
    gui_UpdateAll()
    input_MockMouse session_NoteToolsButton->ax + 10, session_NoteToolsButton->ay + 10, 0
    gui_UpdateAll()
    session_ProcessMenuBar()
    session_AuditBehavior session_NoteToolsWindow <> 0, _
        "Main Note tools button did not open its panel", behaviorCheckCount, errorText
    If session_NoteToolsWindow = 0 Then
        session_ApplyUndoEdit()
        Exit Sub
    End If
    For gridIndex As Integer = 0 To 4
        session_AuditActionButton "note_grid_" + LTrim(Str(gridIndex)), @session_OnNoteToolAction, widgetActionCount, errorText
    Next
    Dim As String actions(0 To 13) = {"duplicate", "quantize", "track", "down", "up", "octave_down", _
        "octave_up", "soft", "loud", "listen", "undo", "redo", "close", "loop"}
    For actionIndex As Integer = 0 To 13
        session_AuditActionButton "note_tools_" + actions(actionIndex), @session_OnNoteToolAction, widgetActionCount, errorText
    Next
    Dim As Integer undoCount = documentHistory_UndoCount(session_DocumentHistory)
    session_OnNoteToolAction gui_FindWidget("note_grid_0")
    session_AuditBehavior session_ScoreSnapTicks() = CULngInt(session_Summary.division) AndAlso _
        documentHistory_UndoCount(session_DocumentHistory) = undoCount, _
        "Grid did not change independently of the document", behaviorCheckCount, errorText
    session_OnNoteToolAction gui_FindWidget("note_grid_2")
    session_OnNoteToolAction gui_FindWidget("note_tools_duplicate")
    session_AuditBehavior midi_GetEditableNoteCount() = originalNotes + 4 AndAlso _
        session_NoteSelection.count = 2 AndAlso session_NoteSelection.noteIndices(0) = originalNotes + 2 AndAlso _
        documentHistory_UndoCount(session_DocumentHistory) = undoCount + 1, _
        "Duplicate did not select the new notes as one edit", behaviorCheckCount, errorText
    session_OnNoteToolAction gui_FindWidget("note_tools_listen")
    session_AuditBehavior session_SelectedNotePlaybackActive <> 0, _
        "Note tools did not audition the selection", behaviorCheckCount, errorText
    session_OnNoteToolAction gui_FindWidget("note_tools_listen")
    session_AuditBehavior session_Playing = 0, _
        "Note tools did not stop audition", behaviorCheckCount, errorText
    session_OnNoteToolAction gui_FindWidget("note_tools_loop")
    session_AuditBehavior session_SelectedNoteLooping <> 0 AndAlso session_SelectedNotePlaybackActive <> 0 AndAlso _
        session_SelectedNoteLoopEnd >= session_SelectedNotePlayback.endTick, _
        "Loop selection did not start a bounded phrase", behaviorCheckCount, errorText
    Dim As Double loopStartSeconds = midi_TicksToSeconds(session_Summary, session_SelectedNotePlayback.startTick)
    Dim As Double loopEndSeconds = midi_TicksToSeconds(session_Summary, session_SelectedNoteLoopEnd)
    Dim As Double loopDuration = loopEndSeconds - loopStartSeconds
    session_PlaybackElapsed = loopStartSeconds + loopDuration * 3 + 0.001
    session_WrapSelectedLoop()
    session_AuditBehavior Abs(session_PlaybackElapsed - loopStartSeconds - 0.001) < 0.000001 AndAlso _
        session_PlaybackFirstUpdate <> 0 AndAlso session_SelectedNoteLooping <> 0, _
        "A late loop frame lost its fractional time or failed to restart", behaviorCheckCount, errorText
    session_PlaybackLastClock = Timer
    session_UpdateSoftwarePlayback()
    session_AuditBehavior session_Playing <> 0 AndAlso session_SelectedNoteLooping <> 0 AndAlso _
        session_PlaybackFirstUpdate = 0, _
        "Loop did not resume through the normal playback scheduler", behaviorCheckCount, errorText
    session_OnPause 0
    Dim As Double pausedElapsed = session_PlaybackElapsed
    session_UpdateSoftwarePlayback()
    session_AuditBehavior session_Paused <> 0 AndAlso session_PlaybackElapsed = pausedElapsed AndAlso _
        session_SelectedNoteLooping <> 0, "Pause advanced the selection loop", behaviorCheckCount, errorText
    session_OnPause 0
    session_OnNoteToolAction gui_FindWidget("note_tools_loop")
    session_AuditBehavior session_Playing = 0 AndAlso session_SelectedNoteLooping = 0 AndAlso _
        documentHistory_UndoCount(session_DocumentHistory) = undoCount + 1, _
        "Stopping a loop retained voices or changed the document", behaviorCheckCount, errorText
    session_OnNoteToolAction gui_FindWidget("note_tools_undo")
    session_AuditBehavior midi_GetEditableNoteCount() = originalNotes + 2, _
        "Note tools Undo did not remove the duplicate", behaviorCheckCount, errorText
    session_OnNoteToolAction gui_FindWidget("note_tools_redo")
    session_AuditBehavior midi_GetEditableNoteCount() = originalNotes + 4, _
        "Note tools Redo did not restore the duplicate", behaviorCheckCount, errorText
    session_OnNoteToolAction gui_FindWidget("note_tools_undo")
    session_SelectOnlyNote originalNotes
    noteSelection_Add session_NoteSelection, originalNotes + 1, 0
    session_OnNoteToolAction gui_FindWidget("note_tools_up")
    Dim As MidiEditableNote melodyNote
    Dim As MidiEditableNote drumNote
    midi_GetEditableNote originalNotes, melodyNote
    midi_GetEditableNote originalNotes + 1, drumNote
    session_AuditBehavior melodyNote.keyNumber = 61 AndAlso drumNote.keyNumber = 38, _
        "Pitch tool changed drum assignments or missed the melody", behaviorCheckCount, errorText
    session_OnNoteToolAction gui_FindWidget("note_tools_undo")
    session_AuditBehavior session_NoteSelection.count = 2 AndAlso _
        session_NoteSelection.noteIndices(0) = originalNotes, _
        "Undo lost a nonstructural note selection", behaviorCheckCount, errorText
    session_OnNoteToolAction gui_FindWidget("note_tools_redo")
    session_AuditBehavior session_NoteSelection.count = 2, _
        "Redo lost a nonstructural note selection", behaviorCheckCount, errorText
    session_OnNoteToolAction gui_FindWidget("note_tools_undo")
    session_SelectOnlyNote originalNotes
    session_OnNoteToolAction gui_FindWidget("note_tools_quantize")
    midi_GetEditableNote originalNotes, melodyNote
    session_AuditBehavior melodyNote.startTick = 0 AndAlso melodyNote.durationTicks = 90, _
        "Selection quantize changed duration or missed the grid", behaviorCheckCount, errorText
    session_OnNoteToolAction gui_FindWidget("note_tools_undo")
    session_OnNoteToolAction gui_FindWidget("note_tools_close")
    session_ProcessNoteToolsWindow()
    session_AuditBehavior session_NoteToolsWindow = 0, _
        "Note tools Done did not close safely", behaviorCheckCount, errorText
    session_SelectOnlyNote originalNotes
    input_ResetForTest()
    input_MockKey FB.SC_CONTROL, -1
    input_MockKey FB.SC_D, -1
    session_ProcessEditShortcuts()
    session_ProcessEditShortcuts()
    session_AuditBehavior midi_GetEditableNoteCount() = originalNotes + 3, _
        "Ctrl+D did not duplicate once per key press", behaviorCheckCount, errorText
    input_ResetForTest()
    session_ProcessEditShortcuts()
    session_ApplyUndoEdit()
    session_ApplyUndoEdit()
    session_AuditBehavior midi_GetEditableNoteCount() = originalNotes, _
        "Note tools audit could not restore its fixture", behaviorCheckCount, errorText
    session_ClearNoteSelection()
    undoCount = documentHistory_UndoCount(session_DocumentHistory)
    session_ApplySelectionTool OSE_NOTE_EDIT_DUPLICATE
    session_AuditBehavior documentHistory_UndoCount(session_DocumentHistory) = undoCount, _
        "Empty selection created a history entry", behaviorCheckCount, errorText
    session_OnDrumMachine 0
    If session_PhraseWindow <> 0 Then
        session_OnPhraseAction gui_FindWidget("phrase_starter")
        Dim As Integer hitCount = 0
        For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
            For stepIndex As Integer = 0 To 15
                If session_Phrase.velocity(padIndex, stepIndex) > 0 Then
                    hitCount += 1
                End If
            Next
        Next
        session_AuditBehavior hitCount = 12 AndAlso session_Phrase.numerator = 4 AndAlso session_Phrase.denominator = 4, _
            "Starter beat did not create a complete 4/4 pattern", behaviorCheckCount, errorText
        session_OnPhraseAction gui_FindWidget("phrase_at_view")
        session_AuditBehavior textbox_GetText(session_PhraseTickBox) = LTrim(Str(session_ViewStartTick)), _
            "Drum placement did not use the visible score position", behaviorCheckCount, errorText
        session_OnPhraseAction gui_FindWidget("phrase_at_end")
        session_AuditBehavior textbox_GetText(session_PhraseTickBox) = LTrim(Str(session_Summary.durationTicks)), _
            "Drum placement did not use the song end", behaviorCheckCount, errorText
        session_OnPhraseAction gui_FindWidget("phrase_clear")
        session_AuditBehavior session_Phrase.velocity(drumPhrase_PadForRow(0), 0) > 0, _
            "Clear removed the phrase without confirmation", behaviorCheckCount, errorText
        session_OnPhraseAction gui_FindWidget("phrase_clear")
        session_AuditBehavior session_Phrase.velocity(drumPhrase_PadForRow(0), 0) = 0, _
            "Confirmed Clear did not remove the hit", behaviorCheckCount, errorText
        ' This audit's unsaved starter is intentionally discarded.
        session_PhraseChanged = 0
        session_ClosePhraseWindow()
    End If
    session_SnapIndex = originalSnap
    session_ViewStartTick = originalView
    session_UpdateStatusWidget 800
    session_AuditBehavior session_StatusLabel->visible <> 0 AndAlso session_StatusLabel->x = 8, _
        "Feedback is hidden in a narrow window", behaviorCheckCount, errorText
    session_OnHelpMenu 1
    session_AuditActionButton "quick_start_close", @session_OnAboutClose, widgetActionCount, errorText
    session_AuditBehavior session_AboutWindow <> 0 AndAlso gui_FindWidget("quick_start_line_13") <> 0, _
        "Help did not open the complete quick-start guide", behaviorCheckCount, errorText
    session_CloseAboutWindow()
    session_InvalidateInterfaceCaches()
    input_ResetForTest()
End Sub

Private Sub session_AuditSongMeterControls( _
    ByRef behaviorCheckCount As Integer, ByRef errorText As String _
)
    Dim As ULongInt originalView = session_ViewStartTick
    Dim As Integer originalNotes = midi_GetEditableNoteCount()
    Dim As Integer originalNumerator = session_Summary.timeSignatureMap(0).numerator
    Dim As Integer originalDenominatorPower = session_Summary.timeSignatureMap(0).denominatorPower
    Dim As ULong originalTempo = session_Summary.tempoMicrosecondsPerQuarter
    session_ViewStartTick = 0
    input_ResetForTest()
    gui_UpdateAll()
    input_MockMouse session_SongMeterButton->ax + 10, session_SongMeterButton->ay + 10, 1
    gui_UpdateAll()
    input_MockMouse session_SongMeterButton->ax + 10, session_SongMeterButton->ay + 10, 0
    gui_UpdateAll()
    session_ProcessMenuBar()
    session_AuditBehavior session_SongMeterWindow <> 0, _
        "Main time-signature button did not open its picker", behaviorCheckCount, errorText
    If session_SongMeterWindow = 0 Then
        Exit Sub
    End If
    Dim As UInteger originalFingerprint = session_ScoreStaticFingerprintValue(0, 1, 0, 0)
    Dim As Integer wantedNumerator = IIf(originalNumerator = 4, 3, 4)
    Dim As Widget Ptr presetButton = gui_FindWidget(IIf(wantedNumerator = 3, "song_meter_34", "song_meter_44"))
    session_OnSongMeterAction presetButton
    session_AuditBehavior session_Summary.timeSignatureMap(0).numerator = originalNumerator AndAlso _
        textbox_GetText(session_SongMeterNumeratorBox) = LTrim(Str(wantedNumerator)), _
        "Meter preset changed the song before Apply", behaviorCheckCount, errorText
    session_OnSongMeterAction gui_FindWidget("song_meter_apply")
    session_ProcessSongMeterWindow()
    session_AuditBehavior session_SongMeterWindow = 0 AndAlso _
        session_Summary.timeSignatureMap(0).numerator = wantedNumerator AndAlso _
        session_Summary.timeSignatureMap(0).denominatorPower = 2 AndAlso _
        session_ViewStartTick = 0, _
        "Apply & show did not activate the chosen meter", behaviorCheckCount, errorText
    session_AuditBehavior session_ScoreStaticFingerprintValue(0, 1, 0, 0) <> originalFingerprint, _
        "Staff meter cache did not change after a meter edit", behaviorCheckCount, errorText
    session_AuditBehavior midi_GetEditableNoteCount() = originalNotes AndAlso _
        session_Summary.tempoMicrosecondsPerQuarter = originalTempo, _
        "Song-meter edit changed notes or tempo", behaviorCheckCount, errorText
    session_ApplyUndoEdit()
    session_AuditBehavior session_Summary.timeSignatureMap(0).numerator = originalNumerator AndAlso _
        session_Summary.timeSignatureMap(0).denominatorPower = originalDenominatorPower, _
        "Song-meter edit did not undo", behaviorCheckCount, errorText
    session_OnSongMeter 0
    textbox_SetText session_SongMeterDenominatorBox, "3", -1
    session_OnSongMeterAction gui_FindWidget("song_meter_apply")
    session_AuditBehavior session_SongMeterWindow <> 0 AndAlso session_SongMeterCloseRequested = 0, _
        "Song-meter picker accepted an unsupported MIDI denominator", behaviorCheckCount, errorText
    session_OnSongMeterAction gui_FindWidget("song_meter_close")
    session_ProcessSongMeterWindow()
    gui_UpdateAll()
    input_MockMouse session_DrumMachineButton->ax + 10, session_DrumMachineButton->ay + 10, 1
    gui_UpdateAll()
    input_MockMouse session_DrumMachineButton->ax + 10, session_DrumMachineButton->ay + 10, 0
    gui_UpdateAll()
    session_ProcessMenuBar()
    session_AuditBehavior session_PhraseWindow <> 0, _
        "Main drum-machine button did not open the sequencer", behaviorCheckCount, errorText
    session_ClosePhraseWindow()
    session_ViewStartTick = originalView
    session_InvalidateInterfaceCaches()
    input_ResetForTest()
End Sub

Private Sub session_AuditDrumPhraseControls( _
    ByRef behaviorCheckCount As Integer, ByRef errorText As String _
)
    Dim As Integer originalNotes = midi_GetEditableNoteCount()
    Dim As Integer originalTracks = session_Summary.trackCount
    Dim As Integer originalSignatureCount = session_Summary.timeSignatureCount
    session_OnDrumKit 0
    input_ResetForTest()
    gui_UpdateAll()
    Dim As Widget Ptr phraseOpenButton = gui_FindWidget("drum_machine_open")
    If phraseOpenButton = 0 Then
        session_AppendControlAuditError errorText, "Drum kit has no phrase editor button"
        session_CloseDrumWindow()
        Exit Sub
    End If
    input_MockMouse phraseOpenButton->ax + 10, phraseOpenButton->ay + 10, 1
    gui_UpdateAll()
    input_MockMouse phraseOpenButton->ax + 10, phraseOpenButton->ay + 10, 0
    gui_UpdateAll()
    session_ProcessDrumWindow()
    session_AuditBehavior session_PhraseWindow <> 0, _
        "Drum kit phrase button did not open the machine", behaviorCheckCount, errorText
    If session_PhraseWindow = 0 Then
        Exit Sub
    End If
    drumPhrase_Reset session_Phrase, 0
    session_PhraseWriteFields()
    textbox_SetText session_PhraseUnitBox, "3", -1
    textbox_SetText session_PhraseTickBox, "0", -1
    textbox_SetText session_PhraseRepeatBox, "2", -1
    session_DrumVelocity = OSE_DRUM_VELOCITY_HARD
    input_ResetForTest()
    gui_UpdateAll()
    Dim As Widget Ptr firstCell = session_PhraseCells(0, 0)
    input_MockMouse firstCell->ax + firstCell->w \ 2, firstCell->ay + firstCell->h \ 2, 1
    gui_UpdateAll()
    input_MockMouse firstCell->ax + firstCell->w \ 2, firstCell->ay + firstCell->h \ 2, 0
    gui_UpdateAll()
    session_AuditBehavior session_Phrase.velocity(8, 0) = OSE_DRUM_VELOCITY_HARD AndAlso _
        session_Phrase.denominator = 3, "Drum grid click did not create a 4/3 hit", behaviorCheckCount, errorText
    session_OnPhraseAction gui_FindWidget("phrase_save")
    session_OnPhraseAction gui_FindWidget("phrase_next")
    session_OnPhraseAction gui_FindWidget("phrase_prev")
    session_AuditBehavior session_PhraseSlot = 0 AndAlso session_Phrase.denominator = 3 AndAlso _
        session_Phrase.velocity(8, 0) = OSE_DRUM_VELOCITY_HARD, _
        "Switching phrases lost the saved grid or meter", behaviorCheckCount, errorText
    session_OnPhraseAction gui_FindWidget("phrase_loop")
    session_ProcessPhraseWindow()
    session_AuditBehavior session_PhraseLooping <> 0 AndAlso session_PhraseLoopStep = 0, _
        "Phrase preview did not start its first step", behaviorCheckCount, errorText
    session_OnPhraseAction gui_FindWidget("phrase_loop")
    session_PhraseInsert()
    Dim As MidiEditableNote insertedNote
    Dim As Integer noteFound = midi_GetEditableNote(originalNotes, insertedNote)
    session_AuditBehavior midi_GetEditableNoteCount() = originalNotes + 2 AndAlso noteFound <> 0 AndAlso _
        insertedNote.channel = 9 AndAlso insertedNote.keyNumber = drumKit_Pitch(8) AndAlso _
        session_Summary.timeSignatureCount = originalSignatureCount, _
        "Phrase insertion did not preserve channel or song meter", behaviorCheckCount, errorText
    Dim As ULongInt insertionEnd
    numericText_ParseUnsigned textbox_GetText(session_PhraseTickBox), insertionEnd, OSE_MAX_MIDI_TICK
    session_AuditBehavior insertionEnd = drumPhrase_StepTick(session_Phrase, session_Summary.division, 32), _
        "Phrase insertion did not advance through both repeats", behaviorCheckCount, errorText
    textbox_SetText session_PhraseUnitBox, "0", -1
    session_ClosePhraseWindow()
    session_AuditBehavior session_PhraseWindow <> 0, _
        "Invalid phrase fields silently closed and lost the draft", behaviorCheckCount, errorText
    textbox_SetText session_PhraseUnitBox, "3", -1
    session_ClosePhraseWindow()
    session_ApplyUndoEdit()
    session_ApplyUndoEdit()
    session_AuditBehavior midi_GetEditableNoteCount() = originalNotes AndAlso session_Summary.trackCount = originalTracks, _
        "Phrase insertion and phrase save did not undo cleanly", behaviorCheckCount, errorText
    session_OnMusicMenu 6
    gui_UpdateAll()
    Dim As Widget Ptr songMeterButton = gui_FindWidget("phrase_song_meter")
    If songMeterButton <> 0 Then
        input_MockMouse songMeterButton->ax + 10, songMeterButton->ay + 10, 1
        gui_UpdateAll()
        input_MockMouse songMeterButton->ax + 10, songMeterButton->ay + 10, 0
        gui_UpdateAll()
        session_ProcessPhraseWindow()
    End If
    session_AuditBehavior session_PhraseWindow = 0 AndAlso session_TempoMapWindow <> 0, _
        "Phrase song-meter button did not open the notation editor", behaviorCheckCount, errorText
    session_CloseTempoMapWindow()
    input_ResetForTest()
End Sub

Private Sub session_AuditSemanticDrumPointerControls( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    /'
        Drum pads share one geometry map across rendering, mouse input, and
        independent touch contacts. Exercise each pointer face and then hold
        two contacts together so a compatibility mouse cannot mask missing
        multitouch support.
    '/
    input_ResetForTest()
    session_OnDrumKit 0
    If session_DrumWindow = 0 Then
        session_AppendControlAuditError errorText, _
            "drum pointer audit could not open its window"
        Exit Sub
    End If
    gui_UpdateAll()

    session_SetDrumVelocity OSE_DRUM_VELOCITY_HARD
    input_MockTouch 0, _
        session_DrumSoftButton->ax + session_DrumSoftButton->w \ 2, _
        session_DrumSoftButton->ay + session_DrumSoftButton->h \ 2, 77
    input_MockTouchCount 1
    gui_UpdateAll()
    input_MockTouchCount 0
    gui_UpdateAll()
    session_AuditBehavior _
        session_DrumVelocity = OSE_DRUM_VELOCITY_SOFT AndAlso _
        input_MouseX() = session_DrumSoftButton->ax + _
            session_DrumSoftButton->w \ 2 AndAlso _
        input_MouseY() = session_DrumSoftButton->ay + _
            session_DrumSoftButton->h \ 2 AndAlso _
        (input_MouseButtons() And 1) = 0, _
        "Primary touch did not activate the generated Soft button at its contact", _
        behaviorCheckCount, errorText
    session_SetDrumVelocity OSE_DRUM_VELOCITY_MEDIUM
    input_ResetForTest()

    Dim As Integer surfaceX
    Dim As Integer surfaceY
    Dim As Integer surfaceWidth
    Dim As Integer surfaceHeight
    session_DrumSurface surfaceX, surfaceY, surfaceWidth, surfaceHeight
    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        Dim As OseDrumPadRectangle padRectangle
        drumKit_PadRectangle padIndex, surfaceX, surfaceY, surfaceWidth, _
            surfaceHeight, padRectangle
        Dim As Integer pointerX = padRectangle.x + padRectangle.width \ 2
        Dim As Integer pointerY = padRectangle.y + padRectangle.height \ 2
        mixerMeter_StopChannel session_MixerMeter, 9
        input_MockMouse pointerX, pointerY, 1
        input_Update()
        session_ProcessDrumWindow()
        Dim As Integer started = session_DrumPadHeld(padIndex) <> 0 AndAlso _
            session_MixerMeter.sourceLevel(9) > 0.0
        input_MockMouse pointerX, pointerY, 0
        input_Update()
        session_ProcessDrumWindow()
        Dim As Integer stopped = session_DrumPadHeld(padIndex) = 0
        session_AuditBehavior started <> 0 AndAlso stopped <> 0, _
            "Drum pad " + Str(padIndex) + _
                " did not trigger and release through pointer input", _
            behaviorCheckCount, errorText
    Next

    Dim As Integer drumScanCodes(0 To OSE_DRUM_PAD_COUNT - 1) = { _
        FB.SC_1, FB.SC_2, FB.SC_3, FB.SC_4, _
        FB.SC_Q, FB.SC_W, FB.SC_E, FB.SC_R, _
        FB.SC_A, FB.SC_S, FB.SC_D, FB.SC_F _
    }
    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        input_ResetForTest()
        mixerMeter_StopChannel session_MixerMeter, 9
        input_MockKey drumScanCodes(padIndex), -1
        input_Update()
        session_ProcessDrumWindow()
        Dim As Integer keyStarted = _
            session_DrumPadHeld(padIndex) <> 0 AndAlso _
            session_MixerMeter.sourceLevel(9) > 0.0
        input_MockKey drumScanCodes(padIndex), 0
        input_Update()
        session_ProcessDrumWindow()
        session_AuditBehavior keyStarted <> 0 AndAlso _
            session_DrumPadHeld(padIndex) = 0, _
            "Drum shortcut " + drumKit_KeyLabel(padIndex) + _
                " did not trigger its printed pad", _
            behaviorCheckCount, errorText
    Next

    Dim As OseDrumPadRectangle firstTouchPad
    Dim As OseDrumPadRectangle secondTouchPad
    drumKit_PadRectangle 8, surfaceX, surfaceY, surfaceWidth, surfaceHeight, _
        firstTouchPad
    drumKit_PadRectangle 9, surfaceX, surfaceY, surfaceWidth, surfaceHeight, _
        secondTouchPad
    input_ResetForTest()
    input_MockTouchCount 2
    input_MockTouch 0, firstTouchPad.x + firstTouchPad.width \ 2, _
        firstTouchPad.y + firstTouchPad.height \ 2, 101
    input_MockTouch 1, secondTouchPad.x + secondTouchPad.width \ 2, _
        secondTouchPad.y + secondTouchPad.height \ 2, 202
    input_Update()
    session_ProcessDrumWindow()
    Dim As Integer twoPadsHeld = session_DrumPadHeld(8) <> 0 AndAlso _
        session_DrumPadHeld(9) <> 0
    input_MockTouchCount 0
    input_Update()
    session_ProcessDrumWindow()
    session_AuditBehavior twoPadsHeld <> 0 AndAlso _
        session_DrumPadHeld(8) = 0 AndAlso session_DrumPadHeld(9) = 0, _
        "Drum kit did not retain two independent touch contacts", _
        behaviorCheckCount, errorText

    session_CloseDrumWindow()
    input_ResetForTest()
End Sub


Private Sub session_AuditSemanticMixerMeters( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    /'
        The meter model has independent unit coverage, but that alone cannot
        prove the application routes an audible command into it. Exercise the
        public A4 audition action, the production mixer update, and the idle
        release path while preserving the document's current mix settings.

        sfxlib does not expose live post-mix samples or a peak callback. The
        meter therefore follows the exact sound actions accepted by sfxlib;
        the output-capture smoke test separately requires those actions to
        produce non-silent PCM.
    '/
    Dim As OseMixerMeterState originalMeter = session_MixerMeter
    Dim As OseMixerChannelState originalMixerChannels = session_MixerChannels
    Dim As Double originalMeterClock = session_MixerMeterLastClock
    Dim As Single originalChannelVolume = session_ChannelVolume(0)
    Dim As Single originalChannelPan = session_ChannelPan(0)
    Dim As Single originalMasterVolume = session_MasterVolume
    Dim As Integer originalPlaying = session_Playing
    Dim As Integer originalPaused = session_Paused

    session_Playing = 0
    session_Paused = 0
    mixerState_Initialize session_MixerChannels
    session_ChannelVolume(0) = 0.82
    session_ChannelPan(0) = 0.0
    session_MasterVolume = 1.0
    mixerMeter_Initialize session_MixerMeter
    session_MixerMeterLastClock = Timer

    session_OnTone 0
    session_UpdateMixerMeters()
    session_AuditBehavior _
        mixerMeter_ChannelLevel(session_MixerMeter, 0) > 0.60 AndAlso _
        mixerMeter_MasterLeftLevel(session_MixerMeter) > 0.60 AndAlso _
        mixerMeter_MasterRightLevel(session_MixerMeter) > 0.60 AndAlso _
        mixerMeter_ChannelLevel(session_MixerMeter, 1) = 0.0, _
        "Audition A4 did not drive its channel and stereo master meters", _
        behaviorCheckCount, errorText

    mixerMeter_StopAll session_MixerMeter
    Dim As Double releaseClock = Timer
    If releaseClock >= 0.60 Then
        releaseClock -= 0.60
    Else
        releaseClock += 86399.40
    End If
    session_MixerMeterLastClock = releaseClock
    session_UpdateMixerMeters()
    session_AuditBehavior _
        mixerMeter_ChannelLevel(session_MixerMeter, 0) = 0.0 AndAlso _
        mixerMeter_MasterLeftLevel(session_MixerMeter) = 0.0 AndAlso _
        mixerMeter_MasterRightLevel(session_MixerMeter) = 0.0, _
        "stopped sound activity did not return the VU meters to zero", _
        behaviorCheckCount, errorText

    session_MixerMeter = originalMeter
    session_MixerChannels = originalMixerChannels
    session_MixerMeterLastClock = originalMeterClock
    session_ChannelVolume(0) = originalChannelVolume
    session_ChannelPan(0) = originalChannelPan
    session_MasterVolume = originalMasterVolume
    session_Playing = originalPlaying
    session_Paused = originalPaused
    session_ApplyMixerState()
End Sub


Private Function session_AuditFileHasBytes(ByVal filename As String) As Integer
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then
        Return 0
    End If
    Dim As LongInt fileBytes = Lof(fileNumber)
    Close #fileNumber
    Return IIf(fileBytes > 0, -1, 0)
End Function


Private Sub session_AuditSemanticFileCompletions( _
    ByVal reportFilename As String, _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    /'
        The native picker owns navigation and selection. Its accepted path is
        completed here through the same dispatcher used by the live dialog, so
        every file-menu destination is exercised without desktop automation.
        All artifacts remain beside the caller-selected temporary report.
    '/
    Dim As String outputDirectory = capturePaths_ParentDirectory(reportFilename)
    Dim As String originalFilename = session_Filename
    Dim As String originalProjectFilename = session_ProjectFilename
    Dim As Integer originalDirtyState = session_Dirty
    Dim As Integer originalTrackCount = session_Summary.trackCount
    Dim As Integer originalNoteCount = midi_GetEditableNoteCount()

    session_CompleteFileSelection SESSION_DIALOG_OPEN, -1, ""
    session_AuditBehavior session_StatusText = "File selection cancelled.", _
        "Cancelled file selection was not reported", _
        behaviorCheckCount, errorText

    Dim As String midiFilename = capturePaths_Join( _
        outputDirectory, "ui-file-completion.mid")
    session_CompleteFileSelection SESSION_DIALOG_MIDI_SAVE, 1, midiFilename
    session_AuditBehavior session_AuditFileHasBytes(midiFilename) <> 0 AndAlso _
        session_Filename = midiFilename AndAlso session_Dirty = 0, _
        "MIDI Save selection did not create and adopt a MIDI file", _
        behaviorCheckCount, errorText

    Dim As String projectFilename = capturePaths_Join( _
        outputDirectory, "ui-project-completion.ose")
    Dim As String projectMidiFilename = session_PathWithExtension( _
        projectFilename, ".mid")
    session_CompleteFileSelection _
        SESSION_DIALOG_PROJECT_SAVE, 1, projectFilename
    session_AuditBehavior _
        session_AuditFileHasBytes(projectFilename) <> 0 AndAlso _
        session_AuditFileHasBytes(projectMidiFilename) <> 0 AndAlso _
        session_ProjectFilename = projectFilename AndAlso _
        session_Filename = projectMidiFilename, _
        "Project Save selection did not commit its project/MIDI pair", _
        behaviorCheckCount, errorText

    session_CompleteFileSelection SESSION_DIALOG_OPEN, 1, projectFilename
    session_AuditBehavior _
        session_ProjectFilename = projectFilename AndAlso _
        session_Filename = projectMidiFilename AndAlso _
        session_Summary.trackCount = originalTrackCount AndAlso _
        midi_GetEditableNoteCount() = originalNoteCount, _
        "Open selection did not reload the saved project pair", _
        behaviorCheckCount, errorText

    Dim As String modFilename = capturePaths_Join( _
        outputDirectory, "ui-file-completion.mod")
    session_CompleteFileSelection SESSION_DIALOG_MOD_EXPORT, 1, modFilename
    session_AuditBehavior session_AuditFileHasBytes(modFilename) <> 0, _
        "MOD Export selection did not create a module", _
        behaviorCheckCount, errorText

    Dim As String wavFilename = capturePaths_Join( _
        outputDirectory, "ui-file-completion.wav")
    session_CompleteFileSelection SESSION_DIALOG_WAV_EXPORT, 1, wavFilename
    session_AuditBehavior session_WavExport.active <> 0 AndAlso _
        session_Playing <> 0 AndAlso session_WavExport.filename = wavFilename, _
        "WAV Export selection did not start bounded mix capture", _
        behaviorCheckCount, errorText
    session_StopPlayback()
    session_AuditBehavior session_WavExport.active = 0 AndAlso _
        session_Playing = 0, _
        "Stopping a selected WAV export did not cancel capture", _
        behaviorCheckCount, errorText

    session_CompleteFileSelection SESSION_DIALOG_OPEN, 1, midiFilename
    session_AuditBehavior session_Filename = midiFilename AndAlso _
        session_ProjectFilename = "" AndAlso _
        session_Summary.trackCount = originalTrackCount AndAlso _
        midi_GetEditableNoteCount() = originalNoteCount, _
        "Open selection did not reload the saved MIDI document", _
        behaviorCheckCount, errorText

    If originalFilename <> "" AndAlso originalFilename <> midiFilename Then _
        session_CompleteFileSelection _
            SESSION_DIALOG_OPEN, 1, originalFilename
    session_ProjectFilename = originalProjectFilename
    session_Dirty = originalDirtyState
End Sub


Private Sub session_AuditSemanticCaptureActions( _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    /'
        These checks record only into the test document's temporary directory.
        A one-second take crosses several backend callbacks and is long enough
        to distinguish a real RIFF/WAVE save from a zero-byte placeholder.
    '/
    Dim As Integer originalDirtyState = session_Dirty
    Dim As Integer originalAudioCount = audio_GetCount()
    session_OnAudio 0
    session_OnCaptureAudio 0
    Dim As Integer audioCaptureStarted = session_AudioCaptureActive <> 0
    session_AuditBehavior audioCaptureStarted <> 0 OrElse _
        session_StatusText = "The sfxlib audio capture device is unavailable.", _
        "Record Mic WAV neither started nor reported unavailable input", _
        behaviorCheckCount, errorText
    Dim As String audioCaptureFilename = session_AudioCaptureFilename
    If audioCaptureStarted <> 0 Then
        Sleep 1000
        session_OnCaptureAudio 0
        Dim As Integer audioCaptureCompleted = _
            session_AuditFileHasBytes(audioCaptureFilename) <> 0 AndAlso _
            audio_GetCount() = originalAudioCount + 1
        Dim As Integer audioCaptureLostDevice = _
            audio_GetCount() = originalAudioCount AndAlso _
            (session_StatusText = "Audio capture could not be saved." OrElse _
                session_StatusText = "Captured WAV failed PCM validation.")
        session_AuditBehavior session_AudioCaptureActive = 0 AndAlso _
            (audioCaptureCompleted <> 0 OrElse audioCaptureLostDevice <> 0), _
            "Record Mic WAV neither committed a valid clip nor handled device loss", _
            behaviorCheckCount, errorText
        If audioCaptureCompleted <> 0 Then
            session_OnEditMenu 0
        End If
    Else
        session_AuditBehavior session_AudioCaptureActive = 0 AndAlso _
            audio_GetCount() = originalAudioCount, _
            "Unavailable WAV capture changed the audio document", _
            behaviorCheckCount, errorText
    End If
    session_AuditBehavior audio_GetCount() = originalAudioCount, _
        "Captured WAV clip did not undo cleanly", _
        behaviorCheckCount, errorText
    session_CloseAudioWindow()

    Dim As Integer originalNoteCount = midi_GetEditableNoteCount()
    session_OnMic 0
    session_OnMicCapture 0
    Dim As Integer micCaptureStarted = session_MicCaptureActive <> 0
    session_AuditBehavior micCaptureStarted <> 0 OrElse _
        session_StatusText = "The sfxlib microphone input is unavailable.", _
        "Microphone transcription neither started nor reported unavailable input", _
        behaviorCheckCount, errorText
    Dim As String micCaptureFilename = session_MicCaptureFilename
    If micCaptureStarted <> 0 Then
        Sleep 1000
        session_OnMicCapture 0
        Dim As Integer micCaptureCompleted = _
            session_AuditFileHasBytes(micCaptureFilename) <> 0 AndAlso _
            session_StatusText <> "Microphone capture could not be saved."
        Dim As Integer micCaptureLostDevice = _
            session_StatusText = "Microphone capture could not be saved." AndAlso _
            midi_GetEditableNoteCount() = originalNoteCount
        session_AuditBehavior session_MicCaptureActive = 0 AndAlso _
            (micCaptureCompleted <> 0 OrElse micCaptureLostDevice <> 0), _
            "Microphone transcription neither retained a take nor handled device loss", _
            behaviorCheckCount, errorText
        If midi_GetEditableNoteCount() > originalNoteCount Then _
            session_OnEditMenu 0
    Else
        session_AuditBehavior session_MicCaptureActive = 0 AndAlso _
            midi_GetEditableNoteCount() = originalNoteCount, _
            "Unavailable microphone transcription changed the MIDI document", _
            behaviorCheckCount, errorText
    End If
    session_AuditBehavior midi_GetEditableNoteCount() = originalNoteCount, _
        "Transcribed microphone notes did not undo cleanly", _
        behaviorCheckCount, errorText
    session_CloseMicWindow()
    session_Dirty = originalDirtyState
End Sub


Private Sub session_AuditGeneratedControls( _
    ByRef widgetActionCount As Integer, _
    ByRef textControlCount As Integer, _
    ByRef listControlCount As Integer, _
    ByRef behaviorCheckCount As Integer, _
    ByRef errorText As String _
)
    /'
        Generated dialog controls exist only while their owning context is
        open. Audit each real widget tree, then close it before the next modal
        so one context cannot mask missing controls in another.
    '/
    ' Open each context that owns generated action buttons, inspect the real
    ' widget tree, and close it before moving to the next modal context.
    session_OnKeyboard 0
    session_AuditActionButton "keyboard_record", @session_OnKeyboardRecord, _
        widgetActionCount, errorText
    session_AuditActionButton "keyboard_octave_down", _
        @session_OnKeyboardOctaveDown, widgetActionCount, errorText
    session_AuditActionButton "keyboard_octave_up", _
        @session_OnKeyboardOctaveUp, widgetActionCount, errorText
    session_CloseKeyboardWindow()

    session_OnDrumKit 0
    session_AuditActionButton "drum_record", @session_OnDrumRecord, _
        widgetActionCount, errorText
    session_AuditActionButton "drum_soft", @session_OnDrumSoft, _
        widgetActionCount, errorText
    session_AuditActionButton "drum_medium", @session_OnDrumMedium, _
        widgetActionCount, errorText
    session_AuditActionButton "drum_hard", @session_OnDrumHard, _
        widgetActionCount, errorText
    session_CloseDrumWindow()

    session_OnMic 0
    session_AuditActionButton "mic_capture", @session_OnMicCapture, _
        widgetActionCount, errorText
    session_AuditTextControl session_MicQuantizeBox, "mic_grid", _
        session_MicWindow, textControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_MicMinimumNoteBox, "mic_minimum", _
        session_MicWindow, textControlCount, behaviorCheckCount, errorText
    session_CloseMicWindow()

    session_OnAudio 0
    session_AuditActionButton "audio_add", @session_OnAddAudio, _
        widgetActionCount, errorText
    session_AuditActionButton "audio_apply", @session_OnApplyAudio, _
        widgetActionCount, errorText
    session_AuditActionButton "audio_delete", @session_OnDeleteAudio, _
        widgetActionCount, errorText
    session_AuditActionButton "audio_capture", @session_OnCaptureAudio, _
        widgetActionCount, errorText
    session_AuditListControl session_AudioList, "audio_list", _
        session_AudioWindow, listControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_AudioTickBox, "audio_tick", _
        session_AudioWindow, textControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_AudioGainBox, "audio_gain", _
        session_AudioWindow, textControlCount, behaviorCheckCount, errorText
    session_CloseAudioWindow()

    session_OnAutomation 0
    session_AuditActionButton "automation_new", @session_OnAddAutomation, _
        widgetActionCount, errorText
    session_AuditActionButton "automation_apply", @session_OnApplyAutomation, _
        widgetActionCount, errorText
    session_AuditActionButton "automation_delete", @session_OnDeleteAutomation, _
        widgetActionCount, errorText
    session_AuditListControl session_AutomationList, "automation_list", _
        session_AutomationWindow, listControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_AutomationTickBox, "automation_tick", _
        session_AutomationWindow, textControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_AutomationTrackBox, "automation_track", _
        session_AutomationWindow, textControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_AutomationChannelBox, _
        "automation_channel", session_AutomationWindow, textControlCount, _
        behaviorCheckCount, errorText
    session_AuditTextControl session_AutomationTypeBox, "automation_type", _
        session_AutomationWindow, textControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_AutomationData1Box, "automation_data1", _
        session_AutomationWindow, textControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_AutomationData2Box, "automation_data2", _
        session_AutomationWindow, textControlCount, behaviorCheckCount, errorText
    session_CloseAutomationWindow()

    If midi_GetEditableNoteCount() > 0 Then
        session_SelectOnlyNote 0
        session_OnNoteProperties 0
        session_AuditActionButton "note_apply", _
            @session_OnApplyNoteProperties, widgetActionCount, errorText
        session_AuditActionButton "note_delete", _
            @session_OnDeleteNoteProperties, widgetActionCount, errorText
        session_AuditTextControl session_NoteTickBox, "note_tick", _
            session_NoteWindow, textControlCount, behaviorCheckCount, errorText
        session_AuditTextControl session_NoteDurationBox, "note_duration", _
            session_NoteWindow, textControlCount, behaviorCheckCount, errorText
        session_AuditTextControl session_NoteTrackBox, "note_track", _
            session_NoteWindow, textControlCount, behaviorCheckCount, errorText
        session_AuditTextControl session_NoteChannelBox, "note_channel", _
            session_NoteWindow, textControlCount, behaviorCheckCount, errorText
        session_AuditTextControl session_NotePitchBox, "note_pitch", _
            session_NoteWindow, textControlCount, behaviorCheckCount, errorText
        session_AuditTextControl session_NoteVelocityBox, "note_velocity", _
            session_NoteWindow, textControlCount, behaviorCheckCount, errorText
        session_CloseNoteWindow()
    Else
        session_AppendControlAuditError errorText, _
            "note-property context has no fixture note"
    End If

    session_OnTempoMap 0
    session_AuditActionButton "tempo_map_apply", @session_OnApplyTempoMap, _
        widgetActionCount, errorText
    session_AuditActionButton "tempo_map_new", @session_OnAddTempoMap, _
        widgetActionCount, errorText
    session_AuditActionButton "tempo_map_delete", @session_OnDeleteTempoMap, _
        widgetActionCount, errorText
    session_AuditListControl session_TempoMapList, "tempo_map_list", _
        session_TempoMapWindow, listControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_TempoMapTickValueLabel, _
        "tempo_map_tick_value", session_TempoMapWindow, textControlCount, _
        behaviorCheckCount, errorText
    session_AuditTextControl session_TempoMapBpmBox, "tempo_map_bpm", _
        session_TempoMapWindow, textControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_TempoMapNumeratorBox, _
        "tempo_map_numerator", session_TempoMapWindow, textControlCount, _
        behaviorCheckCount, errorText
    session_AuditTextControl session_TempoMapDenominatorBox, _
        "tempo_map_denominator", session_TempoMapWindow, textControlCount, _
        behaviorCheckCount, errorText
    session_AuditTextControl session_TempoMapKeyBox, "tempo_map_key", _
        session_TempoMapWindow, textControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_TempoMapMinorBox, "tempo_map_minor", _
        session_TempoMapWindow, textControlCount, behaviorCheckCount, errorText
    session_CloseTempoMapWindow()

    session_OnTrackProperties 0
    session_AuditActionButton "track_properties_apply", _
        @session_OnApplyTrackProperties, widgetActionCount, errorText
    session_AuditActionButton "track_properties_quantize", _
        @session_OnQuantizeTrack, widgetActionCount, errorText
    session_AuditTextControl session_TrackNameBox, "track_name", _
        session_TrackWindow, textControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_DocumentTitleBox, "document_title", _
        session_TrackWindow, textControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_CopyrightBox, "copyright_text", _
        session_TrackWindow, textControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_LyricBox, "lyric_text", _
        session_TrackWindow, textControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_MarkerBox, "marker_text", _
        session_TrackWindow, textControlCount, behaviorCheckCount, errorText
    session_AuditTextControl session_QuantizeGridBox, "quantize_grid", _
        session_TrackWindow, textControlCount, behaviorCheckCount, errorText
    session_CloseTrackPropertiesWindow()

    session_OnMidiInput 0
    session_AuditActionButton "midi_input_open", _
        @session_OnMidiInputOpenSelected, widgetActionCount, errorText
    session_AuditActionButton "midi_input_close", _
        @session_OnMidiInputCloseSelected, widgetActionCount, errorText
    session_AuditListControl session_MidiInputList, "midi_input_list", _
        session_MidiInputWindow, listControlCount, behaviorCheckCount, errorText
    session_CloseMidiInputWindow()

    session_OnMidiOutput 0
    session_AuditActionButton "midi_output_open", _
        @session_OnMidiOutputOpenSelected, widgetActionCount, errorText
    session_AuditActionButton "midi_output_close", _
        @session_OnMidiOutputCloseSelected, widgetActionCount, errorText
    session_AuditListControl session_MidiOutputList, "midi_output_list", _
        session_MidiOutputWindow, listControlCount, behaviorCheckCount, errorText
    session_CloseMidiOutputWindow()

    session_OnHelpMenu 0
    session_AuditActionButton "about_close", @session_OnAboutClose, _
        widgetActionCount, errorText
    If session_StatusText <> OSE_PRODUCT_NAME + " " + OSE_VERSION_TEXT Then _
        session_AppendControlAuditError errorText, _
            "About action did not expose the product version"
    session_CloseAboutWindow()
End Sub


Private Function session_WriteControlAudit(ByVal reportFilename As String) As Integer
    reportFilename = Left(Trim(reportFilename), 4096)
    If reportFilename = "" Then
        Return 0
    End If

    Dim As String errorText
    Dim As Integer widgetActionCount = 0
    Dim As Integer textControlCount = 0
    Dim As Integer listControlCount = 0
    Dim As Integer behaviorCheckCount = 0
    Dim As String buttonNames(0 To 16) = { _
        "new", "open", "save", "stop", "pause", "rewind", "play", _
        "fast_forward", "live_record", "step_record", "apply_tempo", _
        "tempo_map", "midi_input", "midi_output", "drum_machine_button", "song_meter_button", "note_tools_button" _
    }
    Dim As Any Ptr buttonHandlers(0 To 16) = { _
        @session_OnNewDocument, @session_OnOpen, @session_OnSave, _
        @session_OnStop, @session_OnPause, @session_OnRewind, _
        @session_OnPlay, @session_OnFastForward, @session_OnLiveRecord, _
        @session_OnStepRecord, @session_OnApplyTempo, @session_OnTempoMap, _
        @session_OnMidiInput, @session_OnMidiOutput, @session_OnDrumMachine, @session_OnSongMeter, @session_OnNoteTools _
    }
    For buttonIndex As Integer = LBound(buttonNames) To UBound(buttonNames)
        session_AuditActionButton buttonNames(buttonIndex), _
            buttonHandlers(buttonIndex), widgetActionCount, errorText
    Next

    Dim As Widget Ptr menuWidgets(0 To 7) = { _
        session_FileMenu, session_EditMenu, session_OptionsMenu, _
        session_SetupMenu, session_WindowMenu, session_TrackMenu, _
        session_MusicMenu, session_HelpMenu _
    }
    Dim As Integer expectedMenuItems(0 To 7) = {7, 11, 11, 5, 7, 3, 7, 2}
    Dim As Any Ptr expectedMenuCallbacks(0 To 7) = { _
        @session_OnFileMenu, @session_OnEditMenu, @session_OnOptionsMenu, _
        @session_OnSetupMenu, @session_OnWindowMenu, @session_OnTrackMenu, _
        @session_OnMusicMenu, @session_OnHelpMenu _
    }
    For menuIndex As Integer = LBound(menuWidgets) To UBound(menuWidgets)
        If menuWidgets(menuIndex) = 0 OrElse menuWidgets(menuIndex)->data = 0 Then
            session_AppendControlAuditError errorText, _
                "missing menu index " + Str(menuIndex)
            Continue For
        End If
        Dim As MenuData Ptr menuState = Cast(MenuData Ptr, menuWidgets(menuIndex)->data)
        If menuState->count <> expectedMenuItems(menuIndex) Then
            session_AppendControlAuditError errorText, _
                "wrong item count in menu index " + Str(menuIndex)
            Continue For
        End If
        For itemIndex As Integer = 0 To menuState->count - 1
            If Trim(menuState->items(itemIndex)) = "" OrElse _
                menuState->callbacks(itemIndex) = 0 Then
                session_AppendControlAuditError errorText, _
                    "unwired menu item " + Str(menuIndex) + ":" + Str(itemIndex)
            ElseIf menuState->callbacks(itemIndex) <> _
                expectedMenuCallbacks(menuIndex) Then
                session_AppendControlAuditError errorText, _
                    "wrong menu action " + Str(menuIndex) + ":" + Str(itemIndex)
            Else
                widgetActionCount += 1
            End If
        Next
    Next

    ' The toolbar tempo editor is the only persistent editable control. Dialog
    ' fields and lists are audited while their owning modal tree is open below.
    session_AuditTextControl session_TempoBox, "tempo", 0, _
        textControlCount, behaviorCheckCount, errorText

    session_AuditGeneratedControls widgetActionCount, textControlCount, _
        listControlCount, behaviorCheckCount, errorText

    Dim As Integer scrollControlCount
    Dim As Widget Ptr scrollWidgets(0 To 1) = { _
        session_ScoreHorizontalScrollbar, session_ScoreVerticalScrollbar _
    }
    For scrollIndex As Integer = LBound(scrollWidgets) To UBound(scrollWidgets)
        If scrollWidgets(scrollIndex) = 0 OrElse _
            scrollWidgets(scrollIndex)->data = 0 OrElse _
            scrollWidgets(scrollIndex)->update = 0 OrElse _
            scrollWidgets(scrollIndex)->render = 0 Then
            session_AppendControlAuditError errorText, _
                "unwired score scrollbar " + Str(scrollIndex)
        Else
            scrollControlCount += 1
        End If
    Next

    ' Code-drawn controls do not appear in omaGUI's widget tree. Their bounded
    ' contract covers five score tools, thirteen visible note-palette choices,
    ' seven controls on each of sixteen mixer strips, three master controls,
    ' two responsive channel-page controls, twenty-four performance keys, and
    ' twelve drum pads.
    Dim As Integer customControlCount = SESSION_SCORE_TOOL_COUNT + _
        OSE_SCORE_DURATION_COUNT + 6 + SESSION_CHANNEL_COUNT * 7 + 5 + _
        SESSION_KEYBOARD_NOTE_COUNT + OSE_DRUM_PAD_COUNT
    If SESSION_SCORE_TOOL_COUNT <> 5 OrElse _
        SESSION_SCORE_PALETTE_ROW_COUNT <> OSE_SCORE_DURATION_COUNT OrElse _
        SESSION_CHANNEL_COUNT <> 16 OrElse _
        SESSION_KEYBOARD_NOTE_COUNT <> 24 OrElse _
        OSE_DRUM_PAD_COUNT <> 12 OrElse _
        OSE_MIXER_CONTROL_PAGE_NEXT <> 12 Then
        session_AppendControlAuditError errorText, _
            "code-drawn control contract constants changed"
    End If

    Dim As Integer labelRight = SESSION_SCORE_LEFT + 5 + _
        SESSION_SCORE_TRACK_LABEL_CHARACTERS * _
        SESSION_DEFAULT_FONT_CHARACTER_WIDTH
    Dim As Integer timelineLeft = SESSION_SCORE_LEFT + SESSION_SCORE_NOTE_LEFT
    If labelRight >= timelineLeft Then
        session_AppendControlAuditError errorText, _
            "score track labels overlap the editable timeline"
    Else
        behaviorCheckCount += 1
    End If

    session_AuditSemanticMenuRoutes behaviorCheckCount, errorText
    session_AuditSemanticViewWorkflow behaviorCheckCount, errorText
    session_AuditSemanticKeyboardNavigation behaviorCheckCount, errorText
    session_AuditMidiRecordingClock behaviorCheckCount, errorText
    session_AuditMidiRecordingDispatch behaviorCheckCount, errorText
    session_AuditSemanticKeyboardPointerControls _
        behaviorCheckCount, errorText
    session_AuditSemanticDrumPointerControls behaviorCheckCount, errorText
    session_AuditDrumPhraseControls behaviorCheckCount, errorText
    session_AuditSongMeterControls behaviorCheckCount, errorText
    session_AuditNoteTools widgetActionCount, behaviorCheckCount, errorText
    session_AuditSemanticMixerMeters behaviorCheckCount, errorText
    session_AuditSemanticTransportAndDialogs behaviorCheckCount, errorText
    session_AuditSemanticEdits behaviorCheckCount, errorText
    session_AuditSemanticScorePointerControls behaviorCheckCount, errorText
    session_AuditSemanticAutomationMutations behaviorCheckCount, errorText
    session_AuditSemanticAudioMutations behaviorCheckCount, errorText
    session_AuditSemanticNoteMutations behaviorCheckCount, errorText
    session_AuditSemanticTempoMapMutations behaviorCheckCount, errorText
    session_AuditSemanticTrackMutations behaviorCheckCount, errorText
    session_AuditSemanticToolbarNoOp behaviorCheckCount, errorText
    session_AuditSemanticMixerPointerControls behaviorCheckCount, errorText
    session_AuditSemanticMidiDevices behaviorCheckCount, errorText
    session_AuditSemanticFileCompletions _
        reportFilename, behaviorCheckCount, errorText
    session_AuditSemanticCaptureActions behaviorCheckCount, errorText

    ' Exit uses one request path for the File menu, Escape, and the native
    ' window close event. Exercise dirty, clean, and confirmed decisions without
    ' terminating this bounded audit process.
    Dim As Integer originalDirty = session_Dirty
    Dim As Integer originalQuitRequested = session_QuitRequested
    session_Dirty = -1
    session_QuitRequested = 0
    session_OnFileMenu 6
    If session_ConfirmDialog = 0 OrElse _
        session_ConfirmAction <> SESSION_CONFIRM_QUIT OrElse _
        session_QuitRequested <> 0 Then
        session_AppendControlAuditError errorText, _
            "dirty exit did not request discard confirmation"
    Else
        behaviorCheckCount += 1
    End If
    session_CloseDiscardConfirmation()

    session_Dirty = 0
    session_QuitRequested = 0
    session_RequestQuit()
    If session_QuitRequested = 0 Then
        session_AppendControlAuditError errorText, _
            "clean exit did not request application shutdown"
    Else
        behaviorCheckCount += 1
    End If

    session_QuitRequested = 0
    session_ApplyConfirmedDiscard SESSION_CONFIRM_QUIT
    If session_QuitRequested = 0 Then
        session_AppendControlAuditError errorText, _
            "confirmed discard did not request application shutdown"
    Else
        behaviorCheckCount += 1
    End If
    session_Dirty = originalDirty
    session_QuitRequested = originalQuitRequested

    Dim As Integer fileNumber = FreeFile()
    If Open(reportFilename For Output As #fileNumber) <> 0 Then
        Return 0
    End If
    Print #fileNumber, "status=" + IIf(errorText = "", "ok", "failed")
    Print #fileNumber, "widget_actions=" + LTrim(Str(widgetActionCount))
    Print #fileNumber, "text_controls=" + LTrim(Str(textControlCount))
    Print #fileNumber, "list_controls=" + LTrim(Str(listControlCount))
    Print #fileNumber, "scroll_controls=" + LTrim(Str(scrollControlCount))
    Print #fileNumber, "custom_controls=" + LTrim(Str(customControlCount))
    Print #fileNumber, "behavior_checks=" + LTrim(Str(behaviorCheckCount))
    Print #fileNumber, "startup_theme=" + _
        uiStyle_ThemeName(session_StartupThemeMode)
    Print #fileNumber, "startup_interaction=" + _
        uiInteraction_Name(session_StartupInteractionMode)
    Dim As OseUserPreferences retainedPreferences
    Dim As Integer retainedPreferenceStatus = userPreferences_Load( _
        session_PreferencesFilename, retainedPreferences)
    Print #fileNumber, "persisted_theme=" + IIf( _
        retainedPreferenceStatus = OSE_PREFERENCES_LOAD_OK, _
        uiStyle_ThemeName(retainedPreferences.themeMode), "Unavailable")
    Print #fileNumber, "persisted_interaction=" + IIf( _
        retainedPreferenceStatus = OSE_PREFERENCES_LOAD_OK, _
        uiInteraction_Name(retainedPreferences.interactionMode), "Unavailable")
    Print #fileNumber, "total_controls=" + _
        LTrim(Str(widgetActionCount + textControlCount + listControlCount + _
        scrollControlCount + customControlCount))
    If errorText <> "" Then
        Print #fileNumber, "errors=" + errorText
    End If
    Close #fileNumber
    Return IIf(errorText = "", -1, 0)
End Function


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
                wheelDelta = IIf((phaseIndex Mod 24) < 12, -1, 1)
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
    Trim(Environ("OSE_TEST_PREFERENCES_FILE")), 4096)
Dim As String session_TestSmoothnessReport = Left( _
    Trim(Environ("OSE_TEST_SMOOTHNESS_REPORT")), 4096)
Dim As Integer session_AutomatedPreferencesRun = _
    Trim(Environ("OSE_TEST_SNAPSHOT")) <> "" OrElse _
    Trim(Environ("OSE_TEST_CONTROL_REPORT")) <> "" OrElse _
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
    Trim(Environ("OSE_DEFAULT_INTERACTION_MODE")), 32)
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
    Trim(Environ("OSE_INTERACTION_MODE")), 32)
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
    Trim(Environ("OSE_TEST_SNAPSHOT")), 4096)
Dim As Integer session_TestSnapshotFrame = session_TestEnvironmentInteger( _
    "OSE_TEST_SNAPSHOT_FRAME", 1, 600, 12)
Dim As Integer session_TestWindowWidth = SESSION_INITIAL_WIDTH
Dim As Integer session_TestWindowHeight = SESSION_INITIAL_HEIGHT
Dim As UInteger session_TestWindowFlags = BACKEND_WINDOW_RESIZABLE
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
    Select Case LCase(Left(Trim(Environ("OSE_TEST_THEME")), 16))
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
    Environ("OSE_TEST_MIXER_PAGE_ANCHOR") <> "" Then
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
    Trim(Environ("OSE_TEST_SMOOTHNESS_MODE")), 16))
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
    Environ("OSE_TEST_AUDITION_PITCH") <> "" Then
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
    Select Case LCase(Left(Trim(Environ("OSE_TEST_MODAL")), 32))
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
    Trim(Environ("OSE_TEST_CONTROL_REPORT")), 4096)
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
