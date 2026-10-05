/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/song_meter.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Edit the song time signature.

    Responsibilities:

        - validate supported meter values
        - apply the chosen signature through document history

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_SONG_METER_BI__
#define __OSE_EDITOR_SONG_METER_BI__


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

#endif

/' end of src/editor/song_meter.bi '/
