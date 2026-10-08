/'
    Project: omaGUI
    File: navigation_input.bi
    Purpose: Declare portable controller navigation.
    Responsibilities: Expose semantic actions over the existing sampled input frame.
    This file does not contain application commands or a second event queue.

    The navigation profile is opt-in through OMAGUI_NAVIGATION_EXTENSIONS.
    All state belongs to the GUI thread, like the core registry and input frame.
'/

#ifndef __OMAGUI_NAVIGATION_INPUT_BI__
#define __OMAGUI_NAVIGATION_INPUT_BI__

Const INPUT_ACTION_UP As Integer = 0
Const INPUT_ACTION_DOWN As Integer = 1
Const INPUT_ACTION_LEFT As Integer = 2
Const INPUT_ACTION_RIGHT As Integer = 3
Const INPUT_ACTION_ACCEPT As Integer = 4
Const INPUT_ACTION_CANCEL As Integer = 5
Const INPUT_ACTION_PAGE_PREVIOUS As Integer = 6
Const INPUT_ACTION_PAGE_NEXT As Integer = 7
Const INPUT_ACTION_MENU As Integer = 8
Const INPUT_ACTION_COUNT As Integer = 9

Const INPUT_DEVICE_KEYBOARD As Integer = 0
Const INPUT_DEVICE_POINTER As Integer = 1
Const INPUT_DEVICE_TOUCH As Integer = 2
Const INPUT_DEVICE_GAMEPAD As Integer = 3

Const INPUT_TOUCH_MAX_CONTACTS As Integer = 10
Const INPUT_TOUCH_BEGAN As Integer = 1
Const INPUT_TOUCH_MOVED As Integer = 2
Const INPUT_TOUCH_STATIONARY As Integer = 3
Const INPUT_TOUCH_ENDED As Integer = 4
Const INPUT_TOUCH_CANCELLED As Integer = 5

#define KEY_PAGEUP FB.SC_PAGEUP
#define KEY_PAGEDOWN FB.SC_PAGEDOWN
#define KEY_TAB FB.SC_TAB
#define KEY_W FB.SC_W
#define KEY_A FB.SC_A
#define KEY_S FB.SC_S
#define KEY_D FB.SC_D
Extern omagui_nav_nav_key_consumed(0 To 255) As Integer
Declare Sub input_NavigationUpdate()
Declare Sub input_NavigationReset()
Declare Function input_PeekTextInput() As String
Declare Function input_ActionPressed(ByVal action As Integer) As Integer
Declare Function input_ActionHeld(ByVal action As Integer) As Integer
Declare Sub input_ConsumeAction(ByVal action As Integer)
Declare Sub input_ConsumeKey(ByVal k As Integer)
Declare Function input_LastDevice() As Integer
Declare Function input_DeviceName() As String
Declare Function input_ControllerConnected() As Integer
Declare Sub input_MockGamepad(ByVal buttons As Integer, ByVal dpad As Integer, _
    ByVal leftX As Single = 0.0, ByVal leftY As Single = 0.0)
Declare Function input_PointerPressed() As Integer
Declare Function input_PointerReleased() As Integer
Declare Function input_PointerPressX() As Integer
Declare Function input_PointerPressY() As Integer
Declare Function input_PointerReleaseX() As Integer
Declare Function input_PointerReleaseY() As Integer
Declare Function input_TouchId(ByVal index As Integer) As Integer
Declare Function input_TouchX(ByVal index As Integer) As Integer
Declare Function input_TouchY(ByVal index As Integer) As Integer
Declare Sub input_NavigationTouchUpdate()
Declare Function input_NavigationTouchCount() As Integer
Declare Function input_NavigationTouch(ByVal index As Integer, ByRef x As Integer, ByRef y As Integer, ByRef id As Integer) As Integer
Declare Function input_TouchPhase(ByVal index As Integer) As Integer
Declare Function input_PrimaryTouchIndex() As Integer
#endif
' end of navigation_input.bi
