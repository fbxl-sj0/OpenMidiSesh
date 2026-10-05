/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/drum_machine.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Edit and play bounded drum phrases.

    Responsibilities:

        - manage phrase draft controls and saved phrase slots
        - route phrase insertion and looping through the document and transport

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_DRUM_MACHINE_BI__
#define __OSE_EDITOR_DRUM_MACHINE_BI__


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
                nextSlot = (session_PhraseSlot + OSE_DRUM_PHRASE_COUNT - 1) Mod OSE_DRUM_PHRASE_COUNT ' fblint: disable-line FBL406 REASON: Range checks keep the dividend nonnegative and the modulus positive before this calculation.
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

#endif

/' end of src/editor/drum_machine.bi '/
