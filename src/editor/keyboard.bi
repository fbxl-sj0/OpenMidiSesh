/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/keyboard.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Present the playable performance keyboard.

    Responsibilities:

        - draw the keyboard and route mouse and PC-key input
        - coordinate audition and real-duration note recording

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_KEYBOARD_BI__
#define __OSE_EDITOR_KEYBOARD_BI__


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

#endif

/' end of src/editor/keyboard.bi '/
