/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/drums.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Present playable General MIDI drum pads.

    Responsibilities:

        - draw and activate the bounded drum-pad set
        - route drum audition through the shared voice ownership rules

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_DRUMS_BI__
#define __OSE_EDITOR_DRUMS_BI__


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

#endif

/' end of src/editor/drums.bi '/
