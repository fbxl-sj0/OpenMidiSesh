/'
    Project: OpenSesh
    ---------------------------

    File: touch_gesture.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: touchGesture_* updates with OseTouchContact, OseTouchGestureState, and OseTouchGestureResult.

    Purpose:

        Declare deterministic contact-to-gesture translation for shared UI.

    Responsibilities:

        - retain a stable primary contact by identifier
        - distinguish taps from intentional drags
        - report two-contact pan and independent axis pinch deltas
        - cancel taps after any multi-contact sequence

    This file intentionally does NOT contain:

        - gfxlib polling or platform event types
        - score, mixer, or widget behavior
        - timing-based long-press policy
'/

#ifndef __OSE_TOUCH_GESTURE_BI__
#define __OSE_TOUCH_GESTURE_BI__

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseTouchContact
    As Integer id
    As Integer x
    As Integer y
End Type

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseTouchGestureState
    As Integer active
    As Integer primaryId
    As Integer startX
    As Integer startY
    As Integer lastX
    As Integer lastY
    As Integer dragging
    As Integer multiContact
    As Integer multiInitialized
    As Double lastCenterX
    As Double lastCenterY
    As Double lastDistance
    As Double lastSpanX
    As Double lastSpanY
End Type

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseTouchGestureResult
    As Integer started
    As Integer tap
    As Integer dragStarted
    As Integer dragActive
    As Integer dragEnded
    As Integer multiActive
    As Integer x
    As Integer y
    As Integer startX
    As Integer startY
    As Integer deltaX
    As Integer deltaY
    As Double pinchDelta
    As Double pinchXDelta
    As Double pinchYDelta
End Type

Declare Sub touchGesture_Reset(ByRef state As OseTouchGestureState)

Declare Sub touchGesture_Update( _
    ByRef state As OseTouchGestureState, _
    ByVal contacts As OseTouchContact Ptr, _
    ByVal contactCount As Integer, _
    ByVal dragThreshold As Integer, _
    ByRef result As OseTouchGestureResult _
)

#endif

/' end of touch_gesture.bi '/
