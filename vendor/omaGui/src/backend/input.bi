/'
    Project: omaGUI
    ---------------
    File: input.bi

    Purpose:
        Declare the gfxlib input and deterministic test-input interface.

    Responsibilities:
        - expose mouse position, buttons, wheel movement, keys, and text
        - expose pointer coordinates independently of dispatch masking
        - retain native pointer, key, and modifier transitions between frames
        - expose native double-click markers
        - allow the GUI manager to route one pointer event to one widget
        - track bounded vertical drag-to-scroll gestures by stable pointer identity
        - preserve active gestures when a wheel delta changes the scroll offset
        - provide deterministic mouse, wheel, keyboard, and text test input

    Targets:

        FreeBASIC builds with built-in gfxlib; gfxlib3 is optional when supplied by the compiler.

    Module API:

        Declarations for the input component in the omaGUI include graph.

    This file intentionally does NOT contain:
        - platform polling implementation
        - widget hit testing
        - window focus policy
'/

#pragma once
#ifndef __INPUT_BI__
#define __INPUT_BI__

#include "fbgfx.bi"

' -------------------------------------------------------------------------
' Input API
' -------------------------------------------------------------------------

Const INPUT_MODIFIER_NONE As Integer = 0
Const INPUT_MODIFIER_CONTROL As Integer = 1
Const INPUT_MODIFIER_ALT As Integer = 2
Const INPUT_MODIFIER_SHIFT As Integer = 4

' Ordered raw records remain immutable until input_Update. Legacy key views
' can be mapped or consumed by the GUI thread. Read copies, not retained pointers.
' These are gfxlib scan codes and byte characters, not Windows virtual keys or
' VBDOS KeyCode values. Only PRESS and REPEAT can carry character bytes.
Const INPUT_KEY_EVENT_PRESS As Long = 1
Const INPUT_KEY_EVENT_RELEASE As Long = 2
Const INPUT_KEY_EVENT_REPEAT As Long = 3
Const INPUT_KEY_EVENT_CAPACITY As Long = 256
Const INPUT_TOUCH_CAPACITY As Integer = 10
' A few pixels of finger jitter must not turn a tap into a scroll.
Const INPUT_SCROLL_GESTURE_THRESHOLD As Integer = 6
Const INPUT_SCROLL_SOURCE_NONE As Integer = 0
Const INPUT_SCROLL_SOURCE_MOUSE As Integer = 1
Const INPUT_SCROLL_SOURCE_TOUCH As Integer = 2
Type InputKeyEvent
    As Long event_kind, scan_code, character_byte, modifiers
End Type

' Shared gesture state preserves contact identity and suppresses clicks after a drag.
' A second contact cannot take over until all fingers have lifted.
Type InputVerticalScrollGesture
    As Integer tracking, dragging, origin_y, origin_scroll
    As Integer source, touch_id, touch_blocked
End Type

' Ordered events are separate from the existing per-key edge/held snapshots.
' Keyboard dispatch masks apply to both. Overflow is reported for this frame;
' a caller must not treat a truncated stream as whole. DOS also bounds pending
' native batches, delivering text before the following editor command.
Declare Function input_KeyEventCount() As Long
Declare Function input_ReadKeyEvent(ByVal eventIndex As Long, ByRef eventValue As InputKeyEvent) As Integer
Declare Function input_KeyEvent( _
    ByVal eventIndex As Integer, _
    ByRef scanCode As Integer, ByRef modifiers As Integer _ ' fblint: disable-line FBL-API-001 -- Input codes, text, state and modifiers retain their event API order.
) As Integer
Declare Function input_KeyEventsOverflowed() As Integer
' Identity of the current raw snapshot. Update, test reset and screen handoff
' advance it. A GUI-thread callback may replace the snapshot; callers must stop
' the old batch when this value changes, even if widget identity is unchanged.
Declare Function input_FrameSerial() As ULongInt

Declare Sub input_Update()
' Nonzero after new pointer, touch, key, text, wheel, or close activity.
' The first sample after startup or screen handoff is always active.
Declare Function input_FrameActivity() As Integer
Const INPUT_ACTIVITY_INITIAL As UInteger = &H1
Const INPUT_ACTIVITY_POINTER_MOTION As UInteger = &H2
Const INPUT_ACTIVITY_MOUSE_BUTTONS As UInteger = &H4
Const INPUT_ACTIVITY_MOUSE_WHEEL As UInteger = &H8
Const INPUT_ACTIVITY_KEYBOARD As UInteger = &H10
Const INPUT_ACTIVITY_TEXT As UInteger = &H20
Const INPUT_ACTIVITY_WINDOW_CLOSE As UInteger = &H40
Const INPUT_ACTIVITY_TOUCH As UInteger = &H80
' Frame flags separate pointer motion from actions while preserving the
' existing Boolean activity query for callers that only need a wakeup signal.
Declare Function input_FrameActivityFlags() As UInteger
Declare Function input_MouseX() As Integer
Declare Function input_MouseY() As Integer
' Rendering may still need the pointer position while widget dispatch is masked.
Declare Sub input_GetPointerPosition(ByRef x As Integer, ByRef y As Integer)
' A renderer may letterbox a fixed logical GUI inside a larger drawable.
' Set or clear this GUI-thread mapping during a display-mode transition.
Declare Function input_SetLogicalViewport( _
    ByVal viewportPhysicalLeft As Integer, ByVal viewportPhysicalTop As Integer, _
    ByVal viewportPhysicalWidth As Integer, ByVal viewportPhysicalHeight As Integer, _
    ByVal viewportLogicalWidth As Integer, ByVal viewportLogicalHeight As Integer _
) As Integer
Declare Sub input_ClearLogicalViewport()
Declare Function input_MapNativeToLogical(ByRef x As Integer, ByRef y As Integer) As Integer
Declare Function input_MapLogicalToNative(ByRef x As Integer, ByRef y As Integer) As Integer
Declare Function input_MouseButtons() As Integer
' Raw coordinates serve a captured application gesture outside the widget dispatch mask.
Declare Function input_UnmaskedMouseX() As Integer
Declare Function input_UnmaskedMouseY() As Integer
' True for a native pointer press the window system identified as a double click.
Declare Function input_MouseDoubleClick() As Integer
' Cancellation only: inspect the already sampled frame state without granting
' a widget input ownership. Activation still uses the masked accessor above.
Declare Function input_UnmaskedMouseButtons() As Integer
Declare Function input_MouseWheel() As Integer
Declare Function input_UpdateVerticalScrollGesture( _
    ByRef gesture As InputVerticalScrollGesture, _
    ByVal viewportX As Integer, ByVal viewportY As Integer, _
    ByVal viewportWidth As Integer, ByVal viewportHeight As Integer, _
    ByRef scrollPosition As Integer, ByVal maximumScroll As Integer, _
    ByVal dragThreshold As Integer = INPUT_SCROLL_GESTURE_THRESHOLD _
) As Integer
Declare Sub input_ApplyVerticalScrollDelta( _
    ByRef gesture As InputVerticalScrollGesture, _
    ByRef scrollPosition As Integer, _
    ByVal scrollDelta As LongInt, _
    ByVal maximumScroll As Integer _
)
Declare Sub input_ResetVerticalScrollGesture( _
    ByRef gesture As InputVerticalScrollGesture _
)
Declare Function input_TouchCount() As Integer
Declare Function input_Touch( _
    ByVal contactIndex As Integer, _
    ByRef x As Integer, ByRef y As Integer, ByRef id As Integer _ ' fblint: disable-line FBL-API-001 -- Pointer/contact fields retain their published input order.
) As Integer
Declare Function input_AnyKeyPressed() As Integer
Declare Function input_KeyPressed(ByVal k As Integer) As Integer
Declare Function input_KeyPressEvent(ByVal k As Integer) As Integer
' Native repeats are separate from press edges so editors can repeat without
' reactivating buttons, menu commands, or a chat application's Return action.
Declare Function input_KeyRepeatEvent(ByVal k As Integer) As Integer
' Consume this key's current mapped press/chord edges. Held state, character
' bytes, and ordered raw events remain intact; the next input_Update samples
' fresh edges normally, even while the physical key remains held.
Declare Function input_ConsumeKeyPressEvent(ByVal scanCode As Integer) As Integer
' A focused control may remap its current key or suppress it by mapping to 0.
' The mapping remains active while the physical key is held and is cleared
' when that key is released. Ordered raw events remain unchanged for KeyUp.
Declare Function input_SetKeyEventMapping( _
    ByVal sourceScanCode As Integer, ByVal targetScanCode As Integer _ ' fblint: disable-line FBL-API-001 -- Routing retains source then destination order.
) As Integer
Declare Function input_ModifiedKeyPressEvent( _
    ByVal k As Integer, _ ' fblint: disable-line FBL-API-001 -- Input codes, text, state and modifiers retain their event API order.
    ByVal requiredModifiers As Integer _
) As Integer
' Match one complete chord, rather than accepting a press that includes
' additional modifier bits. Menu accelerators use this to avoid treating
' Ctrl+Shift+F5 as an ordinary F5 binding.
Declare Function input_ExactModifiedKeyPressEvent( _
    ByVal k As Integer, _ ' fblint: disable-line FBL-API-001 -- Input codes, text, state and modifiers retain their event API order.
    ByVal modifiers As Integer _
) As Integer
Declare Function input_ControlShortcutPressed(ByVal k As Integer) As Integer
Declare Function input_AltShortcutPressed(ByVal k As Integer) As Integer
Declare Function input_PollTextInput() As String
' Preserve characters entered after a printable command boundary for the next
' GUI update, after the application has applied the prompt or focus transition.
Declare Sub input_SetTextBoundaryKey( _
    ByVal scanCode As Integer, ByVal enabled As Integer _
)
Declare Function input_TakeWindowCloseRequested() As Integer
' Focus state comes from native gfxlib window events. Targets without focus
' events remain active by default.
Declare Function input_WindowHasFocus() As Integer
Declare Sub input_SetDispatchMask( _
    ByVal pointerEnabled As Integer, _ ' fblint: disable-line FBL-API-001 -- Pointer policy precedes keyboard policy.
    ByVal keyboardEnabled As Integer _
)

Declare Sub input_MockMouse( _
    ByVal x As Integer, ByVal y As Integer, ByVal b As Integer, _ ' fblint: disable-line FBL-API-001 -- Pointer/contact fields retain their published input order.
    ByVal wheelDelta As Integer = 0 _
)
Declare Sub input_MockTouchCount(ByVal contactCount As Integer)
Declare Sub input_MockTouch( _
    ByVal contactIndex As Integer, _ ' fblint: disable-line FBL-API-001 -- Pointer/contact fields retain their published input order.
    ByVal x As Integer, ByVal y As Integer, ByVal id As Integer _ ' fblint: disable-line FBL-API-001 -- Pointer/contact fields retain their published input order.
)
Declare Sub input_MockKey(ByVal k As Integer, ByVal state As Integer) ' fblint: disable-line FBL-API-001 -- Input codes, text, state and modifiers retain their event API order.
Declare Sub input_MockKeyPress( _
    ByVal k As Integer, _ ' fblint: disable-line FBL-API-001 -- Input codes, text, state and modifiers retain their event API order.
    ByVal modifiers As Integer = INPUT_MODIFIER_NONE _
)
' Explicit events retain call order and modifiers. They do not change held
' mock keys or synthesize text; use MockKey/MockText for those separate views.
Declare Function input_MockKeyEvent( _
    ByVal eventKind As Long, ByVal scanCode As Long, _ ' fblint: disable-line FBL-API-001 -- Input codes, text, state and modifiers retain their event API order.
    ByVal characterByte As Long = 0, ByVal modifiers As Long = 0 _ ' fblint: disable-line FBL-API-001 -- Input codes, text, state and modifiers retain their event API order.
) As Integer
Declare Sub input_MockControlShortcut(ByVal k As Integer)
Declare Sub input_MockText(ByVal txt As String)
Declare Sub input_ResetForTest()
' Native gamepads can still report input after the gfxlib window loses focus.
' Hosts use this observed window state when assigning their input ownership.

' Drop transitions belonging to the previous graphics screen without enabling
' mock input. Keys/buttons observed as held are suppressed until release.
Declare Sub input_ResumeAfterScreenChange()

#define KEY_BACKSPACE FB.SC_BACKSPACE
#define KEY_ESCAPE    FB.SC_ESCAPE
#define KEY_RETURN    FB.SC_ENTER
' gfxlib exposes one Enter scan code on the portable FreeBASIC input surface.
#define KEY_KP_ENTER  FB.SC_ENTER
#define KEY_DELETE    FB.SC_DELETE
#define KEY_HOME      FB.SC_HOME
#define KEY_END       FB.SC_END
#define KEY_UP        FB.SC_UP
#define KEY_DOWN      FB.SC_DOWN
#define KEY_LEFT      FB.SC_LEFT
#define KEY_RIGHT     FB.SC_RIGHT

#endif

' end of input.bi
