/'
    Project: OpenSesh
    ---------------------------

    File: touch_gesture.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements touch_gesture.bi; declarations there define the shared interface.

    Purpose:

        Convert contact snapshots into stable, platform-neutral gestures.

    Responsibilities:

        - preserve contact identity when backend ordering changes
        - publish taps only after release and below the drag threshold
        - publish drag transitions and two-contact pan or axis pinch motion
        - reset all state after the final contact is released

    This file intentionally does NOT contain:

        - Android input APIs
        - rendering or application commands
        - frame-rate or wall-clock assumptions
'/

#lang "fb"

#include once "touch_gesture.bi"

' -------------------------------------------------------------------------
' Contact helpers
' -------------------------------------------------------------------------

Private Function touchGesture_FindContact( _
    ByVal contacts As OseTouchContact Ptr, _
    ByVal contactCount As Integer, _
    ByVal contactId As Integer _
) As Integer
    If contacts = 0 OrElse contactCount <= 0 Then
        Return -1
    End If
    For contactIndex As Integer = 0 To contactCount - 1
        If contacts[contactIndex].id = contactId Then
            Return contactIndex
        End If
    Next
    Return -1
End Function


Private Function touchGesture_Distance( _
    ByRef firstContact As OseTouchContact, _
    ByRef secondContact As OseTouchContact _
) As Double
    Dim As Double deltaX = CDbl(secondContact.x) - CDbl(firstContact.x)
    Dim As Double deltaY = CDbl(secondContact.y) - CDbl(firstContact.y)
    Return Sqr(deltaX * deltaX + deltaY * deltaY)
End Function


' -------------------------------------------------------------------------
' Public state machine
' -------------------------------------------------------------------------

Public Sub touchGesture_Reset(ByRef state As OseTouchGestureState)
    Dim As OseTouchGestureState emptyState
    state = emptyState
    state.primaryId = -1
End Sub


Public Sub touchGesture_Update( _
    ByRef state As OseTouchGestureState, _
    ByVal contacts As OseTouchContact Ptr, _
    ByVal contactCount As Integer, _
    ByVal dragThreshold As Integer, _
    ByRef result As OseTouchGestureResult _
)
    Dim As OseTouchGestureResult emptyResult
    result = emptyResult

    If contactCount < 0 Then
        contactCount = 0
    End If
    If contacts = 0 Then
        contactCount = 0
    End If
    If dragThreshold < 1 Then
        dragThreshold = 1
    End If

    If contactCount = 0 Then
        If state.active <> 0 Then
            result.x = state.lastX
            result.y = state.lastY
            result.startX = state.startX
            result.startY = state.startY
            If state.multiContact = 0 Then
                If state.dragging <> 0 Then
                    result.dragEnded = -1
                Else
                    result.tap = -1
                End If
            End If
        End If
        touchGesture_Reset state
        Exit Sub
    End If

    If state.active = 0 Then
        state.active = -1
        state.primaryId = contacts[0].id
        state.startX = contacts[0].x
        state.startY = contacts[0].y
        state.lastX = contacts[0].x
        state.lastY = contacts[0].y
        result.started = -1
    End If

    If contactCount >= 2 Then
        Dim As Double centerX = _
            (CDbl(contacts[0].x) + CDbl(contacts[1].x)) / 2.0
        Dim As Double centerY = _
            (CDbl(contacts[0].y) + CDbl(contacts[1].y)) / 2.0
        Dim As Double distance = touchGesture_Distance( _
            contacts[0], contacts[1])
        Dim As Double spanX = Abs( _
            CDbl(contacts[1].x) - CDbl(contacts[0].x))
        Dim As Double spanY = Abs( _
            CDbl(contacts[1].y) - CDbl(contacts[0].y))

        result.multiActive = -1
        result.x = CInt(centerX)
        result.y = CInt(centerY)
        result.startX = state.startX
        result.startY = state.startY
        If state.multiInitialized <> 0 Then
            result.deltaX = CInt(centerX - state.lastCenterX)
            result.deltaY = CInt(centerY - state.lastCenterY)
            result.pinchDelta = distance - state.lastDistance
            result.pinchXDelta = spanX - state.lastSpanX
            result.pinchYDelta = spanY - state.lastSpanY
        End If

        state.multiContact = -1
        state.multiInitialized = -1
        state.lastCenterX = centerX
        state.lastCenterY = centerY
        state.lastDistance = distance
        state.lastSpanX = spanX
        state.lastSpanY = spanY
        state.lastX = result.x
        state.lastY = result.y
        Exit Sub
    End If

    Dim As Integer primaryIndex = touchGesture_FindContact( _
        contacts, contactCount, state.primaryId)
    If primaryIndex < 0 Then
        primaryIndex = 0
    End If
    Dim As Integer currentX = contacts[primaryIndex].x
    Dim As Integer currentY = contacts[primaryIndex].y
    result.x = currentX
    result.y = currentY
    result.startX = state.startX
    result.startY = state.startY

    If state.multiContact = 0 Then
        Dim As Integer movedX = Abs(currentX - state.startX)
        Dim As Integer movedY = Abs(currentY - state.startY)
        If state.dragging = 0 AndAlso _
            (movedX >= dragThreshold OrElse movedY >= dragThreshold) Then
            state.dragging = -1
            result.dragStarted = -1
        End If
        If state.dragging <> 0 Then
            result.dragActive = -1
            result.deltaX = currentX - state.lastX
            result.deltaY = currentY - state.lastY
        End If
    End If

    state.lastX = currentX
    state.lastY = currentY
End Sub

/' end of touch_gesture.bas '/
