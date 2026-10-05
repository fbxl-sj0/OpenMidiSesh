/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/selection_tools.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Apply selection tools and the musical snap grid.

    Responsibilities:

        - validate note-tool values before applying edits
        - keep displayed snap choices consistent with score coordinates

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_SELECTION_TOOLS_BI__
#define __OSE_EDITOR_SELECTION_TOOLS_BI__


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

#endif

/' end of src/editor/selection_tools.bi '/
