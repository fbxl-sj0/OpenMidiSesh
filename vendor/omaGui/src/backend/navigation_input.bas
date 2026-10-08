/'
    Project: omaGUI
    File: navigation_input.bas
    Purpose: Map the current input frame to controller actions.
    Responsibilities: Bound controller polling, repeat timers and deterministic fixtures.
    This file does not contain application commands or a second event queue.

    The navigation profile is opt-in through OMAGUI_NAVIGATION_EXTENSIONS.
    All state belongs to the GUI thread, like the core registry and input frame.
'/

#lang "fb"
Using FB

#include once "src/backend/navigation_input.bi"
Private Dim Shared As Integer omagui_nav_touch_count, omagui_nav_touch_previous_count
Private Dim Shared As Integer omagui_nav_touch_id(0 To INPUT_TOUCH_CAPACITY - 1)
Private Dim Shared As Integer omagui_nav_touch_x(0 To INPUT_TOUCH_CAPACITY - 1)
Private Dim Shared As Integer omagui_nav_touch_y(0 To INPUT_TOUCH_CAPACITY - 1)
Private Dim Shared As Integer omagui_nav_touch_phase(0 To INPUT_TOUCH_CAPACITY - 1)
Private Dim Shared As Integer omagui_nav_touch_previous_id(0 To INPUT_TOUCH_CAPACITY - 1)
Private Dim Shared As Integer omagui_nav_touch_previous_x(0 To INPUT_TOUCH_CAPACITY - 1)
Private Dim Shared As Integer omagui_nav_touch_previous_y(0 To INPUT_TOUCH_CAPACITY - 1)


Private Dim Shared As Integer omagui_nav_action_held(0 To INPUT_ACTION_COUNT - 1)
Private Dim Shared As Integer omagui_nav_action_pressed(0 To INPUT_ACTION_COUNT - 1)
Private Dim Shared As Integer omagui_nav_action_consumed(0 To INPUT_ACTION_COUNT - 1)
Private Dim Shared As Double omagui_nav_action_hold_started(0 To INPUT_ACTION_COUNT - 1)
Private Dim Shared As Double omagui_nav_action_last_repeated(0 To INPUT_ACTION_COUNT - 1)
Private Dim Shared As Integer omagui_nav_last_device = INPUT_DEVICE_KEYBOARD
Private Dim Shared As Integer omagui_nav_controller_connected
Private Dim Shared As Integer omagui_nav_mock_pad_buttons
Private Dim Shared As Integer omagui_nav_mock_pad_dpad
Private Dim Shared As Single omagui_nav_mock_pad_left_x
Private Dim Shared As Single omagui_nav_mock_pad_left_y
Private Dim Shared As Integer omagui_nav_previous_mouse_x
Private Dim Shared As Integer omagui_nav_previous_mouse_y
Private Dim Shared As Integer omagui_nav_previous_mouse_b
Private Dim Shared As Integer omagui_nav_pointer_pressed
Private Dim Shared As Integer omagui_nav_pointer_released
Private Dim Shared As Integer omagui_nav_pointer_press_x
Private Dim Shared As Integer omagui_nav_pointer_press_y
Private Dim Shared As Integer omagui_nav_pointer_release_x
Private Dim Shared As Integer omagui_nav_pointer_release_y
Private Dim Shared As Integer omagui_nav_nav_mock_active

Const INPUT_CONTROLLER_LIMIT As Integer = 4
Const INPUT_ANALOG_THRESHOLD As Single = 0.45
Const INPUT_REPEAT_DELAY As Double = 0.32
Const INPUT_REPEAT_INTERVAL As Double = 0.11

#ifdef __FB_JS__
Extern "C"
    Declare Function emscripten_run_script_int Alias "emscripten_run_script_int" (ByVal scriptText As Const ZString Ptr) As Integer
End Extern
Const INPUT_BROWSER_GAMEPAD_SCRIPT As String = _
    "(()=>{const g=navigator.getGamepads?navigator.getGamepads():[];const p=g&&g[0];if(!p||!p.connected)return 0;" & _
    "const d=i=>p.buttons[i]&&(p.buttons[i].pressed||p.buttons[i].value>.5);const a=p.axes||[];let m=512;" & _
    "if(d(12)||(a[1]||0)<-.45)m|=1;if(d(13)||(a[1]||0)>.45)m|=2;if(d(14)||(a[0]||0)<-.45)m|=4;" & _
    "if(d(15)||(a[0]||0)>.45)m|=8;if(d(0))m|=16;if(d(1))m|=32;if(d(4)||d(6))m|=64;" & _
    "if(d(5)||d(7))m|=128;if(d(8)||d(9))m|=256;return m})()"
#endif

Private Function input_Elapsed( _
    ByVal currentTime As Double, _
    ByVal earlierTime As Double) As Double

    Dim As Double elapsedTime

    elapsedTime = currentTime - earlierTime
    If elapsedTime < 0.0 Then elapsedTime += 86400.0
    Return elapsedTime
End Function


Private Function input_KeyboardActionHeld(ByVal action As Integer) As Integer
    Select Case action
        Case INPUT_ACTION_UP
            Return input_KeyPressed(KEY_UP) Or input_KeyPressed(KEY_W)
        Case INPUT_ACTION_DOWN
            Return input_KeyPressed(KEY_DOWN) Or input_KeyPressed(KEY_S)
        Case INPUT_ACTION_LEFT
            Return input_KeyPressed(KEY_LEFT) Or input_KeyPressed(KEY_A)
        Case INPUT_ACTION_RIGHT
            Return input_KeyPressed(KEY_RIGHT) Or input_KeyPressed(KEY_D)
        Case INPUT_ACTION_ACCEPT
            Return input_KeyPressed(KEY_RETURN) Or input_KeyPressed(KEY_KP_ENTER)
        Case INPUT_ACTION_CANCEL
            Return input_KeyPressed(KEY_ESCAPE)
        Case INPUT_ACTION_PAGE_PREVIOUS
            Return input_KeyPressed(KEY_PAGEUP)
        Case INPUT_ACTION_PAGE_NEXT
            Return input_KeyPressed(KEY_PAGEDOWN) Or input_KeyPressed(KEY_TAB)
        Case INPUT_ACTION_MENU
            Return input_KeyPressed(KEY_ESCAPE)
    End Select

    Return 0
End Function


Private Sub input_AddControllerActions( _
    ByVal buttons As Integer, _
    ByVal dpad As Integer, _
    ByVal leftX As Single, _
    ByVal leftY As Single, _
    controllerAction() As Integer)

    If (dpad And XPAD_DPAD_UP) <> 0 OrElse _
            leftY <= -INPUT_ANALOG_THRESHOLD Then _
        controllerAction(INPUT_ACTION_UP) = -1
    If (dpad And XPAD_DPAD_DOWN) <> 0 OrElse _
            leftY >= INPUT_ANALOG_THRESHOLD Then _
        controllerAction(INPUT_ACTION_DOWN) = -1
    If (dpad And XPAD_DPAD_LEFT) <> 0 OrElse _
            leftX <= -INPUT_ANALOG_THRESHOLD Then _
        controllerAction(INPUT_ACTION_LEFT) = -1
    If (dpad And XPAD_DPAD_RIGHT) <> 0 OrElse _
            leftX >= INPUT_ANALOG_THRESHOLD Then _
        controllerAction(INPUT_ACTION_RIGHT) = -1

    If (buttons And XPAD_BUTTON_A) <> 0 Then _
        controllerAction(INPUT_ACTION_ACCEPT) = -1
    If (buttons And XPAD_BUTTON_B) <> 0 Then _
        controllerAction(INPUT_ACTION_CANCEL) = -1
    If (buttons And (XPAD_BUTTON_L1 Or XPAD_BUTTON_L2)) <> 0 Then _
        controllerAction(INPUT_ACTION_PAGE_PREVIOUS) = -1
    If (buttons And (XPAD_BUTTON_R1 Or XPAD_BUTTON_R2)) <> 0 Then _
        controllerAction(INPUT_ACTION_PAGE_NEXT) = -1
    If (buttons And (XPAD_BUTTON_START Or XPAD_BUTTON_SELECT)) <> 0 Then _
        controllerAction(INPUT_ACTION_MENU) = -1
End Sub


Private Sub input_UpdateActions()
    Dim As Integer action
    Dim As Integer controllerAction(0 To INPUT_ACTION_COUNT - 1)
    Dim As Integer keyboardHeld
    Dim As Integer newHeld
    Dim As Integer padIndex
    Dim As Integer padStatus
    Dim As Integer padButtons
    Dim As Integer padDpad
    Dim As Single leftX
    Dim As Single leftY
    Dim As Single rightX
    Dim As Single rightY
    Dim As Single leftTrigger
    Dim As Single rightTrigger
    Dim As Double currentTime
#ifdef __FB_JS__
    Dim As Integer packedBrowserGamepad
#endif

    omagui_nav_controller_connected = 0

    If omagui_nav_nav_mock_active <> 0 Then
        If omagui_nav_mock_pad_buttons <> 0 OrElse omagui_nav_mock_pad_dpad <> 0 OrElse _
                Abs(omagui_nav_mock_pad_left_x) > 0.001 OrElse _
                Abs(omagui_nav_mock_pad_left_y) > 0.001 Then omagui_nav_controller_connected = -1
        input_AddControllerActions omagui_nav_mock_pad_buttons, omagui_nav_mock_pad_dpad, _
            omagui_nav_mock_pad_left_x, omagui_nav_mock_pad_left_y, controllerAction()
    Else
#ifdef __FB_JS__
        /'
            The Emscripten gfxlib runtime initializes SDL video but does not
            open a joystick table for GetXPad. Poll the browser's standard
            mapping here and translate it directly into the same semantic bits
            used by native controllers.
        '/
        packedBrowserGamepad = emscripten_run_script_int( _
            StrPtr(INPUT_BROWSER_GAMEPAD_SCRIPT))
        If (packedBrowserGamepad And 512) <> 0 Then
            omagui_nav_controller_connected = -1
            For action = 0 To INPUT_ACTION_COUNT - 1
                If (packedBrowserGamepad And (1 Shl action)) <> 0 Then _
                    controllerAction(action) = -1
            Next action
        End If
#else
        For padIndex = 0 To INPUT_CONTROLLER_LIMIT - 1
            padButtons = 0
            padDpad = 0
            leftX = 0.0
            leftY = 0.0
            rightX = 0.0
            rightY = 0.0
            leftTrigger = 0.0
            rightTrigger = 0.0

            padStatus = GetXPad(padIndex, padButtons, leftX, leftY, _
                rightX, rightY, leftTrigger, rightTrigger, padDpad)
            If padStatus = XPAD_STATUS_CONNECTED Then
                omagui_nav_controller_connected = -1
                input_AddControllerActions padButtons, padDpad, _
                leftX, leftY, controllerAction()
            End If
        Next padIndex
#endif
    End If

    currentTime = Timer
    For action = 0 To INPUT_ACTION_COUNT - 1
        keyboardHeld = IIf(input_KeyboardActionHeld(action) <> 0, -1, 0)
        newHeld = keyboardHeld Or controllerAction(action)
        omagui_nav_action_pressed(action) = 0

        If newHeld <> 0 AndAlso omagui_nav_action_held(action) = 0 Then
            omagui_nav_action_pressed(action) = -1
            omagui_nav_action_hold_started(action) = currentTime
            omagui_nav_action_last_repeated(action) = currentTime
        ElseIf newHeld <> 0 AndAlso action <= INPUT_ACTION_RIGHT Then
            If input_Elapsed(currentTime, omagui_nav_action_hold_started(action)) >= _
                    INPUT_REPEAT_DELAY AndAlso _
               input_Elapsed(currentTime, omagui_nav_action_last_repeated(action)) >= _
                    INPUT_REPEAT_INTERVAL Then
                omagui_nav_action_pressed(action) = -1
                omagui_nav_action_last_repeated(action) = currentTime
            End If
        End If

        omagui_nav_action_held(action) = newHeld
        If controllerAction(action) <> 0 Then
            omagui_nav_last_device = INPUT_DEVICE_GAMEPAD
        ElseIf keyboardHeld <> 0 Then
            omagui_nav_last_device = INPUT_DEVICE_KEYBOARD
        End If
    Next action
End Sub


Sub input_NavigationUpdate()
    If useMockMouse = 0 Then
        mX = backend_PhysicalToLogicalX(mX): mY = backend_PhysicalToLogicalY(mY)
    End If
    For action As Integer = 0 To INPUT_ACTION_COUNT - 1
        omagui_nav_action_consumed(action) = 0
    Next
    For keyIndex As Integer = 0 To 255
        omagui_nav_nav_key_consumed(keyIndex) = 0
    Next
    omagui_nav_pointer_pressed = IIf((mButtons And 1) <> 0 AndAlso (omagui_nav_previous_mouse_b And 1) = 0, -1, 0)
    omagui_nav_pointer_released = IIf((mButtons And 1) = 0 AndAlso (omagui_nav_previous_mouse_b And 1) <> 0, -1, 0)
    If omagui_nav_pointer_pressed Then omagui_nav_pointer_press_x = mX: omagui_nav_pointer_press_y = mY
    If omagui_nav_pointer_released Then omagui_nav_pointer_release_x = mX: omagui_nav_pointer_release_y = mY
    If mX <> omagui_nav_previous_mouse_x OrElse mY <> omagui_nav_previous_mouse_y OrElse mButtons <> omagui_nav_previous_mouse_b Then
        omagui_nav_last_device = IIf(inputTouchContactCount > 0, INPUT_DEVICE_TOUCH, INPUT_DEVICE_POINTER)
    End If
    omagui_nav_previous_mouse_x = mX: omagui_nav_previous_mouse_y = mY: omagui_nav_previous_mouse_b = mButtons
    input_NavigationTouchUpdate
    input_UpdateActions
End Sub

Sub input_NavigationReset()
    For action As Integer = 0 To INPUT_ACTION_COUNT - 1
        omagui_nav_action_held(action) = 0: omagui_nav_action_pressed(action) = 0: omagui_nav_action_consumed(action) = 0
        omagui_nav_action_hold_started(action) = 0: omagui_nav_action_last_repeated(action) = 0
    Next
    For keyIndex As Integer = 0 To 255
        omagui_nav_nav_key_consumed(keyIndex) = 0
    Next
    omagui_nav_nav_mock_active = -1
    omagui_nav_mock_pad_buttons = 0: omagui_nav_mock_pad_dpad = 0: omagui_nav_mock_pad_left_x = 0: omagui_nav_mock_pad_left_y = 0
    omagui_nav_previous_mouse_b = 0: omagui_nav_previous_mouse_x = 0: omagui_nav_previous_mouse_y = 0
    omagui_nav_pointer_pressed = 0: omagui_nav_pointer_released = 0
    omagui_nav_last_device = INPUT_DEVICE_KEYBOARD: omagui_nav_controller_connected = 0
    omagui_nav_touch_count = 0: omagui_nav_touch_previous_count = 0
End Sub

Function input_PeekTextInput() As String
    Return textBuffer
End Function
Function input_ActionPressed(ByVal action As Integer) As Integer
    If action < 0 OrElse action >= INPUT_ACTION_COUNT Then Return 0
    If omagui_nav_action_consumed(action) <> 0 Then Return 0
    Return omagui_nav_action_pressed(action)
End Function


Function input_ActionHeld(ByVal action As Integer) As Integer
    If action < 0 OrElse action >= INPUT_ACTION_COUNT Then Return 0
    If omagui_nav_action_consumed(action) <> 0 Then Return 0
    Return omagui_nav_action_held(action)
End Function


Sub input_ConsumeAction(ByVal action As Integer)
    If action < 0 OrElse action >= INPUT_ACTION_COUNT Then Exit Sub
    omagui_nav_action_consumed(action) = -1
End Sub


Sub input_ConsumeKey(ByVal k As Integer)
    If k < 0 OrElse k > 255 Then Exit Sub
    omagui_nav_nav_key_consumed(k) = -1
End Sub


Function input_LastDevice() As Integer
    Return omagui_nav_last_device
End Function


Function input_DeviceName() As String
    Select Case omagui_nav_last_device
        Case INPUT_DEVICE_POINTER
            Return "Mouse"
        Case INPUT_DEVICE_TOUCH
            Return "Touch"
        Case INPUT_DEVICE_GAMEPAD
            Return "Controller"
    End Select

    Return "Keyboard"
End Function


Function input_ControllerConnected() As Integer
    Return omagui_nav_controller_connected
End Function


Sub input_MockGamepad( _
    ByVal buttons As Integer, _
    ByVal dpad As Integer, _
    ByVal leftX As Single, _
    ByVal leftY As Single)

    omagui_nav_nav_mock_active = 1
    omagui_nav_mock_pad_buttons = buttons
    omagui_nav_mock_pad_dpad = dpad
    omagui_nav_mock_pad_left_x = leftX
    omagui_nav_mock_pad_left_y = leftY
End Sub


Function input_PointerPressed() As Integer
    Return omagui_nav_pointer_pressed
End Function

Function input_PointerReleased() As Integer
    Return omagui_nav_pointer_released
End Function

Function input_PointerPressX() As Integer
    Return omagui_nav_pointer_press_x
End Function

Function input_PointerPressY() As Integer
    Return omagui_nav_pointer_press_y
End Function

Function input_PointerReleaseX() As Integer
    Return omagui_nav_pointer_release_x
End Function

Function input_PointerReleaseY() As Integer
    Return omagui_nav_pointer_release_y
End Function

Function input_TouchId(ByVal index As Integer) As Integer
    Dim As Integer x, y, id
    If input_Touch(index, x, y, id) = 0 Then Return -1
    Return id
End Function

Function input_TouchX(ByVal index As Integer) As Integer
    Dim As Integer x, y, id
    If input_Touch(index, x, y, id) = 0 Then Return -1
    Return x
End Function

Function input_TouchY(ByVal index As Integer) As Integer
    Dim As Integer x, y, id
    If input_Touch(index, x, y, id) = 0 Then Return -1
    Return y
End Function

Function input_TouchPhase(ByVal index As Integer) As Integer
    If index < 0 OrElse index >= omagui_nav_touch_count Then Return INPUT_TOUCH_ENDED
    Return omagui_nav_touch_phase(index)
End Function

Function input_PrimaryTouchIndex() As Integer
    For index As Integer = 0 To omagui_nav_touch_count - 1
        If omagui_nav_touch_phase(index) <> INPUT_TOUCH_ENDED AndAlso omagui_nav_touch_phase(index) <> INPUT_TOUCH_CANCELLED Then Return index
    Next
    Return -1
End Function

' Snapshot active contacts before comparing IDs; expired contacts remain in
' this profile's read-only frame once, but never drive the compatibility mouse.

Sub input_NavigationTouchUpdate()
    omagui_nav_touch_count = inputTouchContactCount
    For index As Integer = 0 To inputTouchContactCount - 1
        omagui_nav_touch_id(index) = inputTouchId(index)
        omagui_nav_touch_x(index) = inputTouchX(index)
        omagui_nav_touch_y(index) = inputTouchY(index)
        If useMockTouch = 0 Then
            omagui_nav_touch_x(index) = backend_PhysicalToLogicalX(inputTouchX(index))
            omagui_nav_touch_y(index) = backend_PhysicalToLogicalY(inputTouchY(index))
        End If
        omagui_nav_touch_phase(index) = INPUT_TOUCH_BEGAN
        For previousIndex As Integer = 0 To omagui_nav_touch_previous_count - 1
            If omagui_nav_touch_previous_id(previousIndex) = inputTouchId(index) Then
                omagui_nav_touch_phase(index) = INPUT_TOUCH_STATIONARY
                If omagui_nav_touch_previous_x(previousIndex) <> omagui_nav_touch_x(index) OrElse omagui_nav_touch_previous_y(previousIndex) <> omagui_nav_touch_y(index) Then omagui_nav_touch_phase(index) = INPUT_TOUCH_MOVED
                Exit For
            End If
        Next
    Next
    For previousIndex As Integer = 0 To omagui_nav_touch_previous_count - 1
        Dim As Integer foundContact = 0
        For index As Integer = 0 To inputTouchContactCount - 1
            If inputTouchId(index) = omagui_nav_touch_previous_id(previousIndex) Then foundContact = -1: Exit For
        Next
        If foundContact = 0 AndAlso omagui_nav_touch_count < INPUT_TOUCH_CAPACITY Then
            Dim As Integer slot = omagui_nav_touch_count
            omagui_nav_touch_id(slot) = omagui_nav_touch_previous_id(previousIndex)
            omagui_nav_touch_x(slot) = omagui_nav_touch_previous_x(previousIndex)
            omagui_nav_touch_y(slot) = omagui_nav_touch_previous_y(previousIndex)
            omagui_nav_touch_phase(slot) = INPUT_TOUCH_ENDED
            omagui_nav_touch_count += 1
        End If
    Next
    omagui_nav_touch_previous_count = inputTouchContactCount
    For index As Integer = 0 To inputTouchContactCount - 1
        omagui_nav_touch_previous_id(index) = omagui_nav_touch_id(index)
        omagui_nav_touch_previous_x(index) = omagui_nav_touch_x(index)
        omagui_nav_touch_previous_y(index) = omagui_nav_touch_y(index)
    Next
End Sub

Function input_NavigationTouchCount() As Integer
    Return omagui_nav_touch_count
End Function

Function input_NavigationTouch(ByVal index As Integer, ByRef x As Integer, ByRef y As Integer, ByRef id As Integer) As Integer
    If index < 0 OrElse index >= omagui_nav_touch_count Then Return 0
    x = omagui_nav_touch_x(index): y = omagui_nav_touch_y(index): id = omagui_nav_touch_id(index)
    Return -1
End Function

' end of navigation_input.bas
