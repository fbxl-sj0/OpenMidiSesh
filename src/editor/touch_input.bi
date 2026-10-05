/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/touch_input.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Adapt score gestures to coarse pointers.

    Responsibilities:

        - track touch gesture state and its movement thresholds
        - route completed gestures through the existing score commands

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_TOUCH_INPUT_BI__
#define __OSE_EDITOR_TOUCH_INPUT_BI__


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

#endif

/' end of src/editor/touch_input.bi '/
