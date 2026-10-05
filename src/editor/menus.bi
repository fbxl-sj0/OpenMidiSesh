/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/menus.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Assemble menu commands and pane scrollbar routes.

    Responsibilities:

        - map menu selections to existing application commands
        - keep pane scrollbars synchronized with bounded view state

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_MENUS_BI__
#define __OSE_EDITOR_MENUS_BI__


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

#endif

/' end of src/editor/menus.bi '/
