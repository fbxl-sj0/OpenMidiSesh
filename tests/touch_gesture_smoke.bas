/'
    Project: OpenSesh
    ---------------------------

    File: tests/touch_gesture_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify deterministic touch gesture recognition without a display.

    Responsibilities:

        - publish a tap only after a stationary contact is released
        - distinguish a drag using the configured movement threshold
        - retain the primary contact when backend ordering changes
        - report two-contact pan and independent axis pinch deltas
        - suppress accidental taps after a multi-contact sequence

    This file intentionally does NOT contain:

        - operating-system input calls
        - editor commands or document mutation
        - graphical rendering
'/

#lang "fb"

#include once "../touch_gesture.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Dim As OseTouchGestureState state
Dim As OseTouchGestureResult gesture
Dim As OseTouchContact contacts(0 To 1)
touchGesture_Reset state

' A press is not a tap until release. This lets a second finger join without
' allowing the first contact to activate the score beneath it.
contacts(0).id = 7
contacts(0).x = 100
contacts(0).y = 120
touchGesture_Update state, @contacts(0), 1, 10, gesture
If gesture.started = 0 OrElse gesture.tap <> 0 Then _
    test_Fail "initial contact was not delayed"
contacts(0).x = 106
contacts(0).y = 125
touchGesture_Update state, @contacts(0), 1, 10, gesture
If gesture.dragActive <> 0 Then _
    test_Fail "sub-threshold movement started a drag"
touchGesture_Update state, 0, 0, 10, gesture
If gesture.tap = 0 OrElse gesture.x <> 106 OrElse gesture.y <> 125 Then _
    test_Fail "stationary release did not publish one tap"

' The configured threshold starts a drag, which ends once and never becomes a
' tap on release.
contacts(0).id = 9
contacts(0).x = 200
contacts(0).y = 220
touchGesture_Update state, @contacts(0), 1, 10, gesture
contacts(0).x = 210
contacts(0).y = 221
touchGesture_Update state, @contacts(0), 1, 10, gesture
If gesture.dragStarted = 0 OrElse gesture.dragActive = 0 OrElse _
    gesture.deltaX <> 10 OrElse gesture.deltaY <> 1 Then _
    test_Fail "threshold movement did not start the expected drag"
contacts(0).x = 216
contacts(0).y = 225
touchGesture_Update state, @contacts(0), 1, 10, gesture
If gesture.dragStarted <> 0 OrElse gesture.dragActive = 0 OrElse _
    gesture.deltaX <> 6 OrElse gesture.deltaY <> 4 Then _
    test_Fail "active drag delta was not incremental"
touchGesture_Update state, 0, 0, 10, gesture
If gesture.dragEnded = 0 OrElse gesture.tap <> 0 Then _
    test_Fail "drag release was mistaken for a tap"

' Reordering contacts must not replace the primary finger used for drag state.
contacts(0).id = 31
contacts(0).x = 300
contacts(0).y = 200
touchGesture_Update state, @contacts(0), 1, 8, gesture
contacts(1) = contacts(0)
contacts(0).id = 32
contacts(0).x = 360
contacts(0).y = 200
touchGesture_Update state, @contacts(0), 2, 8, gesture
If gesture.multiActive = 0 Then
    test_Fail "second contact did not start multi-touch"
End If

' Moving both contacts together reports pan. Increasing their separation also
' reports a positive pinch delta.
contacts(0).x = 374
contacts(1).x = 306
contacts(0).y = 206
contacts(1).y = 206
touchGesture_Update state, @contacts(0), 2, 8, gesture
If gesture.multiActive = 0 OrElse gesture.deltaX <> 10 OrElse _
    gesture.deltaY <> 6 OrElse gesture.pinchDelta <= 0.0 OrElse _
    gesture.pinchXDelta <= 0.0 OrElse gesture.pinchYDelta <> 0.0 Then _
    test_Fail "multi-touch pan or pinch delta was wrong"

' Vertical separation is independent of horizontal separation. Human fingers
' may move diagonally, so neither axis is inferred from total distance alone.
contacts(0).x = 374
contacts(1).x = 306
contacts(0).y = 214
contacts(1).y = 198
touchGesture_Update state, @contacts(0), 2, 8, gesture
If gesture.pinchXDelta <> 0.0 OrElse gesture.pinchYDelta <= 0.0 OrElse _
    gesture.pinchDelta <= 0.0 Then _
    test_Fail "vertical pinch was not isolated from horizontal span"

' Returning to one contact after multi-touch must retain its stable identifier
' and must never generate a tap for that sequence.
contacts(0) = contacts(1)
contacts(0).x = 314
contacts(0).y = 208
touchGesture_Update state, @contacts(0), 1, 8, gesture
If gesture.x <> 314 OrElse gesture.y <> 208 OrElse _
    gesture.tap <> 0 OrElse gesture.dragActive <> 0 Then _
    test_Fail "primary contact was not retained after contact reordering"
touchGesture_Update state, 0, 0, 8, gesture
If gesture.tap <> 0 OrElse gesture.dragEnded <> 0 OrElse state.active <> 0 Then _
    test_Fail "multi-touch release leaked a single-contact action"

' Invalid input is bounded and simply behaves like an empty snapshot.
touchGesture_Update state, 0, -5, 0, gesture
If state.active <> 0 OrElse gesture.tap <> 0 Then _
    test_Fail "invalid contact input was not safely bounded"

Print "touch_gesture=ok"
Print "tap=1 drag=1 reordered_primary=1 pan=1 pinch_x=1 pinch_y=1 cancelled_tap=1"
End 0

/' end of tests/touch_gesture_smoke.bas '/
