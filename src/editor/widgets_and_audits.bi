/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/widgets_and_audits.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Render toolbar controls and verify UI command contracts.

    Responsibilities:

        - draw state-aware toolbar buttons
        - exercise bounded Desktop and Touch control behavior

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_WIDGETS_AND_AUDITS_BI__
#define __OSE_EDITOR_WIDGETS_AND_AUDITS_BI__


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

    For editIndex As Integer = 1 To committedEdits ' fblint: disable-line FBL311 REASON: The counter bounds repeated recording edits in this audit.
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

    Dim As Integer zoomStepIndex ' fblint: disable-line FBL311 REASON: This counter bounds repeated zoom steps in the audit.
    For zoomStepIndex = 0 To 20 ' fblint: disable-line FBL311 REASON: The counter bounds repeated zoom steps in this audit.
        session_ZoomScoreVerticallyAt 280, _
            SESSION_SCORE_TRACK_ROW_ZOOM_STEP, auditHeight
    Next
    session_AuditBehavior _
        session_ScoreTrackRowHeight = _
            SESSION_SCORE_TRACK_ROW_HEIGHT_MAXIMUM, _
        "Vertical score zoom exceeded or missed its maximum", _
        behaviorCheckCount, errorText
    For zoomStepIndex = 0 To 20 ' fblint: disable-line FBL311 REASON: The counter bounds repeated zoom steps in this audit.
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
        Trim(Environ("OSE_TEST_AUDIO_FIXTURE")), OSE_AUDIO_MAX_PATH_BYTES) ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
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

#endif

/' end of src/editor/widgets_and_audits.bi '/
