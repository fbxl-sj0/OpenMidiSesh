/'
    Project: omaGUI
    ---------------
    File: input.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for input.

    Purpose:
        Declare the gfxlib input and deterministic test-input interface.

    Responsibilities:
        - expose mouse position, buttons, wheel movement, keys, and text
        - retain native pointer, key, and modifier transitions between frames
        - allow the GUI manager to route one pointer event to one widget
        - provide deterministic mouse, wheel, keyboard, and text test input

    This file intentionally does NOT contain:
        - platform polling implementation
        - widget hit testing
        - window focus policy
'/

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

' A frame is immutable until input_Update. Read copies, not retained pointers.
' These are gfxlib scan codes and byte characters, not Windows virtual keys or
' VBDOS KeyCode values. Only PRESS and REPEAT can carry character bytes.
Const INPUT_KEY_EVENT_PRESS As Long = 1
Const INPUT_KEY_EVENT_RELEASE As Long = 2
Const INPUT_KEY_EVENT_REPEAT As Long = 3
Const INPUT_KEY_EVENT_CAPACITY As Long = 256
Const INPUT_TOUCH_CAPACITY As Integer = 10
Type InputKeyEvent
    As Long event_kind, scan_code, character_byte, modifiers
End Type

' Ordered events are separate from the existing per-key edge/held snapshots.
' Keyboard dispatch masks apply to both. Overflow drops newest records and is
' reported for this frame; a caller must not treat a truncated stream as whole.
Declare Function input_KeyEventCount() As Long
Declare Function input_ReadKeyEvent(ByVal eventIndex As Long, ByRef eventValue As InputKeyEvent) As Integer
Declare Function input_KeyEvent( _
    ByVal eventIndex As Integer, _
    ByRef scanCode As Integer, ByRef modifiers As Integer _
) As Integer
Declare Function input_KeyEventsOverflowed() As Integer

Declare Sub input_Update()
Declare Function input_MouseX() As Integer
Declare Function input_MouseY() As Integer
Declare Function input_MouseButtons() As Integer
' Cancellation only: inspect the already sampled frame state without granting
' a widget input ownership. Activation still uses the masked accessor above.
Declare Function input_UnmaskedMouseButtons() As Integer
Declare Function input_MouseWheel() As Integer
Declare Function input_TouchCount() As Integer
Declare Function input_Touch( _
    ByVal contactIndex As Integer, _
    ByRef x As Integer, ByRef y As Integer, ByRef id As Integer _
) As Integer
Declare Function input_AnyKeyPressed() As Integer
Declare Function input_KeyPressed(ByVal k As Integer) As Integer
Declare Function input_KeyPressEvent(ByVal k As Integer) As Integer
Declare Function input_ModifiedKeyPressEvent( _
    ByVal k As Integer, _
    ByVal requiredModifiers As Integer _
) As Integer
' Match one complete chord, rather than accepting a press that includes
' additional modifier bits. Menu accelerators use this to avoid treating
' Ctrl+Shift+F5 as an ordinary F5 binding.
Declare Function input_ExactModifiedKeyPressEvent( _
    ByVal k As Integer, _
    ByVal modifiers As Integer _
) As Integer
Declare Function input_ControlShortcutPressed(ByVal k As Integer) As Integer
Declare Function input_AltShortcutPressed(ByVal k As Integer) As Integer
Declare Function input_PollTextInput() As String
Declare Function input_TakeWindowCloseRequested() As Integer
Declare Sub input_SetDispatchMask( _
    ByVal pointerEnabled As Integer, _
    ByVal keyboardEnabled As Integer _
)

Declare Sub input_MockMouse( _
    ByVal x As Integer, ByVal y As Integer, ByVal b As Integer, _
    ByVal wheelDelta As Integer = 0 _
)
Declare Sub input_MockTouchCount(ByVal contactCount As Integer)
Declare Sub input_MockTouch( _
    ByVal contactIndex As Integer, _
    ByVal x As Integer, ByVal y As Integer, ByVal id As Integer _
)
Declare Sub input_MockKey(ByVal k As Integer, ByVal state As Integer)
Declare Sub input_MockKeyPress( _
    ByVal k As Integer, _
    ByVal modifiers As Integer = INPUT_MODIFIER_NONE _
)
' Explicit events retain call order and modifiers. They do not change held
' mock keys or synthesize text; use MockKey/MockText for those separate views.
Declare Function input_MockKeyEvent( _
    ByVal eventKind As Long, ByVal scanCode As Long, _
    ByVal characterByte As Long = 0, ByVal modifiers As Long = 0 _
) As Integer
Declare Sub input_MockControlShortcut(ByVal k As Integer)
Declare Sub input_MockText(ByVal txt As String)
Declare Sub input_ResetForTest()
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
