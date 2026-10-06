/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/state.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Own editor state, constants and callback declarations.

    Responsibilities:

        - group widget, document, playback and interaction state
        - declare callbacks before the private implementation includes

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

' -------------------------------------------------------------------------
' Shared declarations
' -------------------------------------------------------------------------


#ifndef __OSE_EDITOR_STATE_BI__
#define __OSE_EDITOR_STATE_BI__


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
Declare Sub session_DrawScoreToolCursor( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
Declare Sub session_DrawRoundedControl( _
    ByVal controlLeft As Integer, _
    ByVal controlTop As Integer, _
    ByVal controlWidth As Integer, _
    ByVal controlHeight As Integer, _
    ByRef controlStyle As OseUiControlStyle _
)

#endif

/' end of src/editor/state.bi '/
