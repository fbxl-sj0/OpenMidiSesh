/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/document_commands.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Route document, status and transport commands.

    Responsibilities:

        - coordinate file choices and document transactions
        - apply themes, preferences and generated-window styling

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_DOCUMENT_COMMANDS_BI__
#define __OSE_EDITOR_DOCUMENT_COMMANDS_BI__


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
    userDirectory = Trim(Environ("USERPROFILE")) ' fblint: disable-line FBL750 REASON: The directory is validated below; an absent user directory falls back to CurDir.
    Dim As String musicDirectory = capturePaths_Join(userDirectory, "Music")
    If session_DirectoryExists(musicDirectory) <> 0 Then _
        userDirectory = musicDirectory
#Else
    userDirectory = Trim(Environ("HOME")) ' fblint: disable-line FBL750 REASON: The directory is validated below; an absent user directory falls back to CurDir.
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
    If Environ("OSE_TEST_SNAPSHOT") <> "" Then _ ' fblint: disable-line FBL750 REASON: This optional test/profile override treats an absent value as the documented normal default.
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
    For powerIndex As Integer = 1 To denominatorPower ' fblint: disable-line FBL311 REASON: The counter bounds the power-of-two denominator calculation.
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
    If statusByte <> &HF1 AndAlso statusByte <> &HF2 AndAlso _
        statusByte <> &HF3 AndAlso statusByte <> &HF6 Then Return 0
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
    ' The menu assigns exact preset multipliers. 1.0 is the exact normal-speed preset.
    If audio_GetCount() = 0 OrElse session_PlaybackSpeedScale = 1.0 Then ' fblint: disable-line FBL-NUM-013 REASON: This compares an exactly representable preset, not a computed measurement.
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

#endif

/' end of src/editor/document_commands.bi '/
