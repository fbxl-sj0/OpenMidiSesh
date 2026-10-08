/'
    Project: omaGUI
    ---------------
    File: input_gfxlib.bas

    Purpose:
        Implement the input abstraction with FreeBASIC gfxlib calls.

    Responsibilities:
        - poll mouse position, buttons, wheel movement, keys, and text input
        - buffer native mouse transitions which occur between GUI frames
        - retain ordered key transitions, repeats, and individual modifier chords
        - retain a native window-close request until the application reads it
        - expose per-widget pointer and keyboard dispatch masks
        - provide deterministic input values for GUI tests

    Targets:

        FreeBASIC builds with built-in gfxlib; gfxlib3 is optional when supplied by the compiler.

    Module API:

        Implementation unit assembled by omaGUI.bi when OMAGUI_IMPLEMENTATION is defined.

    This file intentionally does NOT contain:
        - widget-specific input behavior
        - graphics rendering
'/

#lang "fb"
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
Dim Shared omagui_nav_nav_key_consumed(0 To 255) As Integer
#endif

#include once "src/widgets/widgets.bi"

/'
    The backend is compiled into omaGUI as a collection of include modules,
    so its private polling state must be shared with the accessor routines in
    this file.  It is not part of the public input API.
'/
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer mX, mY, mButtons, mWheelDelta
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer previousWheelPosition, wheelPositionInitialized
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer mockX, mockY, mockButtons, mockWheelDelta
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer useMockMouse, useMockTouch, useMockKeys, useMockText
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer pointerDispatchEnabled = -1, keyboardDispatchEnabled = -1
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As String textBuffer, mockText

' Ten contacts bound both native polling and deterministic input fixtures.
Dim Shared As Integer inputTouchContactCount, mockTouchContactCount
Dim Shared As Integer inputTouchX(0 To INPUT_TOUCH_CAPACITY - 1)
Dim Shared As Integer inputTouchY(0 To INPUT_TOUCH_CAPACITY - 1)
Dim Shared As Integer inputTouchId(0 To INPUT_TOUCH_CAPACITY - 1)
Dim Shared As Integer inputTouchPointerActive, inputTouchPointerId = -1
Dim Shared As Integer inputTouchPointerX, inputTouchPointerY
Dim Shared As Integer mockTouchX(0 To INPUT_TOUCH_CAPACITY - 1)
Dim Shared As Integer mockTouchY(0 To INPUT_TOUCH_CAPACITY - 1)
Dim Shared As Integer mockTouchId(0 To INPUT_TOUCH_CAPACITY - 1)

' FreeBASIC gfxlib scan codes are represented by one unsigned byte.
Const INPUT_KEY_LAST = 255
' The GUI thread owns this callback-free input frame. Public mock/mapping
' setters and standalone native translators keep their immediate view.
Private Dim Shared As Integer inputKeyBatchActive

/'
    Keyboard controls need edge retention for the same reason as pointer
    clicks. A complete Tab, Enter, arrow key, or Alt shortcut may occur while
    an application is parsing a document or formatting live data. MultiKey
    only reports the final state, so ScreenEvent records each press together
    with the modifier state that existed at that instant.
'/
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputNativeModifiers
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputKeyPressEvents(0 To INPUT_KEY_LAST)
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputKeyPressChords(0 To INPUT_KEY_LAST)
' KeyDown callbacks can change a physical key's meaning for its focused
' control. Raw ordered records remain intact so KeyUp still sees the real key.
Dim Shared As Integer inputKeyOverrideActive(0 To INPUT_KEY_LAST)
Dim Shared As Integer inputKeyOverrideTarget(0 To INPUT_KEY_LAST)
Dim Shared As Integer inputEffectiveKeyPressed(0 To INPUT_KEY_LAST)
Dim Shared As Integer inputEffectiveKeyPressEvents(0 To INPUT_KEY_LAST)
Dim Shared As Integer inputEffectiveKeyPressChords(0 To INPUT_KEY_LAST)
' Track both Shift keys separately. Releasing one must not release the other.
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputNativeModifierKeys(0 To INPUT_KEY_LAST)

' All event storage belongs to the GUI input thread. No callback or pointer
' escapes these fixed buffers. Mock records become visible only at Update.
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As InputKeyEvent inputKeyEvents(0 To INPUT_KEY_EVENT_CAPACITY - 1)
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As InputKeyEvent mockKeyEvents(0 To INPUT_KEY_EVENT_CAPACITY - 1)
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Long inputKeyEventLength, mockKeyEventLength
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputKeyEventOverflow, mockKeyEventOverflow

/'
    GetMouse exposes only current state. A complete click can otherwise vanish
    when DD rendering takes longer than the press. ScreenEvent supplies the
    missing edges; one queued state is replayed per GUI frame so existing
    release-driven widgets keep their ordinary capture semantics.
'/
Const INPUT_POINTER_EVENT_CAPACITY As Long = 64
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Long inputPointerEventX(0 To INPUT_POINTER_EVENT_CAPACITY - 1)
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Long inputPointerEventY(0 To INPUT_POINTER_EVENT_CAPACITY - 1)
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputPointerEventButtons( _
    0 To INPUT_POINTER_EVENT_CAPACITY - 1 _
)
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Long inputPointerEventHead, inputPointerEventTail
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Long inputPointerEventCount
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputNativeButtons, inputNativeButtonsInitialized
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputNativeX, inputNativeY
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputWindowCloseRequested

' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer mockKeys(0 To INPUT_KEY_LAST)
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer mockPreviousKeys(0 To INPUT_KEY_LAST)
' A restored GUI must not interpret the key/button that ended external drawing
' as a new activation. This suppression belongs to the GUI input thread.
Dim Shared As Integer inputSuppressedKeys(0 To INPUT_KEY_LAST)
Dim Shared As Integer inputSuppressButtons, inputSuppressText

' Printable single-byte input is intentionally limited to the ASCII range.
Const INPUT_TEXT_BYTE_INDEX = 0
Const INPUT_TEXT_BYTE_COUNT = 1
Const INPUT_TEXT_ASCII_FIRST = 32
Const INPUT_TEXT_ASCII_LAST = 126


' -------------------------------------------------------------------------
' Native transition collection
' -------------------------------------------------------------------------

Private Sub input_QueuePointerEvent( _
    ByVal x As Long, _
    ByVal y As Long, _
    ByVal buttons As Integer _
)
    If inputPointerEventCount >= INPUT_POINTER_EVENT_CAPACITY Then
        /'
            Recover to the newest physical state if an application was unable
            to render for an extreme number of transitions. This may discard
            old clicks, but it cannot leave a widget permanently pressed.
        '/
        inputPointerEventHead = 0
        inputPointerEventTail = 0
        inputPointerEventCount = 0
    End If

    inputPointerEventX(inputPointerEventTail) = x
    inputPointerEventY(inputPointerEventTail) = y
    inputPointerEventButtons(inputPointerEventTail) = buttons
    inputPointerEventTail += 1
    If inputPointerEventTail >= INPUT_POINTER_EVENT_CAPACITY Then _
        inputPointerEventTail = 0
    inputPointerEventCount += 1
End Sub


Private Function input_ModifierForScanCode( _
    ByVal scanCode As Integer _
) As Integer
    Select Case scanCode
    Case FB.SC_CONTROL
        Return INPUT_MODIFIER_CONTROL
    Case FB.SC_ALT
        Return INPUT_MODIFIER_ALT
    Case FB.SC_LSHIFT, FB.SC_RSHIFT
        Return INPUT_MODIFIER_SHIFT
    End Select

    Return INPUT_MODIFIER_NONE
End Function


Private Function input_RawKeyPressed(ByVal scanCode As Integer) As Integer
    If scanCode < 0 OrElse scanCode > INPUT_KEY_LAST Then Return 0
    If useMockKeys Then Return IIf(mockKeys(scanCode) <> 0, -1, 0)
    Return IIf(MultiKey(scanCode) <> 0, -1, 0)
End Function


Private Function input_MappedScanCode(ByVal scanCode As Integer) As Integer
    If scanCode < 0 OrElse scanCode > INPUT_KEY_LAST Then Return 0
    If inputKeyOverrideActive(scanCode) Then _
        Return inputKeyOverrideTarget(scanCode)
    Return scanCode
End Function


Private Sub input_RebuildKeyView()
    For scan_code As Integer = 0 To INPUT_KEY_LAST
        inputEffectiveKeyPressed(scan_code) = 0
        inputEffectiveKeyPressEvents(scan_code) = 0
        inputEffectiveKeyPressChords(scan_code) = 0
    Next scan_code

    For source_code As Integer = 0 To INPUT_KEY_LAST
        Dim As Integer target_code = input_MappedScanCode(source_code)
        If target_code <= 0 Then Continue For
        If inputSuppressedKeys(source_code) = 0 AndAlso _
           input_RawKeyPressed(source_code) Then _
            inputEffectiveKeyPressed(target_code) = -1
        If inputKeyPressEvents(source_code) Then
            inputEffectiveKeyPressEvents(target_code) = -1
            inputEffectiveKeyPressChords(target_code) Or= _
                inputKeyPressChords(source_code)
        End If
    Next source_code
End Sub


Private Sub input_RecordKeyEvent( _
    ByVal eventKind As Long, ByVal scanCode As Long, _
    ByVal characterByte As Long, ByVal modifiers As Long _
)
    If scanCode < 0 OrElse scanCode > INPUT_KEY_LAST Then Exit Sub
    If inputSuppressedKeys(scanCode) Then Exit Sub
    If eventKind = INPUT_KEY_EVENT_PRESS Then
        inputKeyPressEvents(scanCode) = -1
        ' One bit per complete chord (0..7), not an OR of unrelated presses.
        inputKeyPressChords(scanCode) Or= 1 Shl (modifiers And 7)
    End If
    If inputKeyBatchActive = 0 Then input_RebuildKeyView
    If inputKeyEventLength >= INPUT_KEY_EVENT_CAPACITY Then
        inputKeyEventOverflow = -1
        Exit Sub
    End If
    With inputKeyEvents(inputKeyEventLength)
        .event_kind = eventKind
        .scan_code = scanCode
        .character_byte = IIf(eventKind = INPUT_KEY_EVENT_RELEASE, 0, characterByte)
        .modifiers = modifiers And 7
    End With
    inputKeyEventLength += 1
End Sub


Private Sub input_CollectNativeKey(ByRef eventRecord As Const FB.Event)
    Dim As Long scanCode = eventRecord.scancode
    If scanCode < 0 OrElse scanCode > INPUT_KEY_LAST Then Exit Sub
    If input_ModifierForScanCode(scanCode) <> INPUT_MODIFIER_NONE Then
        inputNativeModifierKeys(scanCode) = IIf(eventRecord.type = FB.EVENT_KEY_RELEASE, 0, -1)
        inputNativeModifiers = INPUT_MODIFIER_NONE
        If inputNativeModifierKeys(FB.SC_CONTROL) Then inputNativeModifiers Or= INPUT_MODIFIER_CONTROL
        If inputNativeModifierKeys(FB.SC_ALT) Then inputNativeModifiers Or= INPUT_MODIFIER_ALT
        If inputNativeModifierKeys(FB.SC_LSHIFT) OrElse inputNativeModifierKeys(FB.SC_RSHIFT) Then _
            inputNativeModifiers Or= INPUT_MODIFIER_SHIFT
    End If
    ' Public gfxlib events use the same three kind values. Extended keys have
    ' no character byte. Guard the byte boundary without narrowing first.
    Dim As Long characterByte = eventRecord.ascii
    If characterByte < 0 OrElse characterByte > 255 Then characterByte = 0
    input_RecordKeyEvent eventRecord.type, scanCode, characterByte, CLng(inputNativeModifiers)
End Sub


Private Sub input_CollectNativeEvents()
    Dim As FB.Event eventRecord

    While ScreenEvent(@eventRecord)
        Select Case eventRecord.type
        Case FB.EVENT_KEY_PRESS, FB.EVENT_KEY_RELEASE, FB.EVENT_KEY_REPEAT
            input_CollectNativeKey eventRecord
        Case FB.EVENT_MOUSE_MOVE
            inputNativeX = eventRecord.x
            inputNativeY = eventRecord.y
        Case FB.EVENT_MOUSE_BUTTON_PRESS, FB.EVENT_MOUSE_DOUBLE_CLICK
            inputNativeButtons Or= eventRecord.button
            input_QueuePointerEvent _
                inputNativeX, inputNativeY, inputNativeButtons
        Case FB.EVENT_MOUSE_BUTTON_RELEASE
            inputNativeButtons And= Not eventRecord.button
            input_QueuePointerEvent _
                inputNativeX, inputNativeY, inputNativeButtons
        Case FB.EVENT_WINDOW_CLOSE
            inputWindowCloseRequested = -1
        Case FB.EVENT_WINDOW_LOST_FOCUS
            inputNativeModifiers = INPUT_MODIFIER_NONE
            Erase inputNativeModifierKeys
        End Select
    Wend
End Sub


Private Function input_PopPointerEvent( _
    ByRef x As Integer, _
    ByRef y As Integer, _
    ByRef buttons As Integer _
) As Integer
    If inputPointerEventCount <= 0 Then Return 0

    x = inputPointerEventX(inputPointerEventHead)
    y = inputPointerEventY(inputPointerEventHead)
    buttons = inputPointerEventButtons(inputPointerEventHead)
    inputPointerEventHead += 1
    If inputPointerEventHead >= INPUT_POINTER_EVENT_CAPACITY Then _
        inputPointerEventHead = 0
    inputPointerEventCount -= 1
    Return -1
End Function

Private Sub input_CollectTouchContacts()
    inputTouchContactCount = 0

    If useMockTouch <> 0 Then
        inputTouchContactCount = mockTouchContactCount
        For contactIndex As Integer = 0 To inputTouchContactCount - 1
            inputTouchX(contactIndex) = mockTouchX(contactIndex)
            inputTouchY(contactIndex) = mockTouchY(contactIndex)
            inputTouchId(contactIndex) = mockTouchId(contactIndex)
        Next
        Exit Sub
    End If

#If __FB_VERSION__ >= "1.20.0"
    ' Native touch polling is absent from the stable 1.10 gfxlib headers.
    Dim As Integer nativeCount = GetTouchCount()
    If nativeCount < 0 Then nativeCount = 0
    If nativeCount > INPUT_TOUCH_CAPACITY Then _
        nativeCount = INPUT_TOUCH_CAPACITY

    For nativeIndex As Integer = 0 To nativeCount - 1
        Dim As Integer contactX, contactY, contactId
        If GetTouch(nativeIndex, contactX, contactY, contactId) = 0 Then
            inputTouchX(inputTouchContactCount) = contactX
            inputTouchY(inputTouchContactCount) = contactY
            inputTouchId(inputTouchContactCount) = contactId
            inputTouchContactCount += 1
        End If
    Next
#EndIf
End Sub

Private Sub input_ApplyTouchCompatibilityPointer()
    /'
        Some targets report correct logical positions through the touch API
        while their emulated mouse is stale. Keep one contact on the ordinary
        widget pointer stream, then synthesize its release at contact end.
    '/
    If inputTouchContactCount > 0 Then
        Dim As Integer pointerContactIndex = 0
        If inputTouchPointerActive <> 0 Then
            For contactIndex As Integer = 0 To inputTouchContactCount - 1
                If inputTouchId(contactIndex) = inputTouchPointerId Then
                    pointerContactIndex = contactIndex
                    Exit For
                End If
            Next
        End If
        inputTouchPointerX = inputTouchX(pointerContactIndex)
        inputTouchPointerY = inputTouchY(pointerContactIndex)
        inputTouchPointerId = inputTouchId(pointerContactIndex)
        inputTouchPointerActive = -1
        mX = inputTouchPointerX
        mY = inputTouchPointerY
        mButtons Or= 1
    ElseIf inputTouchPointerActive <> 0 Then
        mX = inputTouchPointerX
        mY = inputTouchPointerY
        mButtons And= Not 1
        inputTouchPointerActive = 0
        inputTouchPointerId = -1
    End If
End Sub

Sub input_Update()
    Dim As Long MouseStatus
    Dim As Integer currentWheelPosition
    Dim As Integer mockModifiers
    Dim As Integer replayedPointerEvent
    Dim As String KeyText

    pointerDispatchEnabled = -1
    keyboardDispatchEnabled = -1
    inputKeyEventLength = 0
    inputKeyEventOverflow = 0
    inputKeyBatchActive = -1

    For keyIndex As Integer = 0 To INPUT_KEY_LAST
        inputKeyPressEvents(keyIndex) = 0
        inputKeyPressChords(keyIndex) = 0
    Next keyIndex

    If useMockMouse Then
        mX = mockX
        mY = mockY
        mButtons = mockButtons
        mWheelDelta = mockWheelDelta
        mockWheelDelta = 0
    Else
        /'
            gfxlib returns nonzero when no mouse is available and writes -1
            into every output.  The coordinate sentinel is useful to callers,
            but -1 is an invalid button bitmask that would read as every button
            pressed unless it is cleared here.
        '/
        MouseStatus = GetMouse(mX, mY, currentWheelPosition, mButtons)
        If inputNativeButtonsInitialized = 0 Then
            inputNativeButtons = IIf(MouseStatus = 0, mButtons, 0)
            inputNativeX = IIf(MouseStatus = 0, mX, -1)
            inputNativeY = IIf(MouseStatus = 0, mY, -1)
            inputNativeButtonsInitialized = -1
        End If
        input_CollectNativeEvents
        If MouseStatus <> 0 Then
            mX = -1
            mY = -1
            mButtons = 0
            mWheelDelta = 0
            wheelPositionInitialized = 0
        Else
            If wheelPositionInitialized <> 0 Then
                mWheelDelta = currentWheelPosition - previousWheelPosition
            Else
                mWheelDelta = 0
                wheelPositionInitialized = -1
            End If

            previousWheelPosition = currentWheelPosition
        End If
        ' A queued transition remains valid even if current mouse polling is
        ' unavailable, as with a drawable test surface or a disconnected device.
        replayedPointerEvent = input_PopPointerEvent(mX, mY, mButtons)
        If replayedPointerEvent = 0 AndAlso MouseStatus = 0 Then
            inputNativeButtons = mButtons
            inputNativeX = mX
            inputNativeY = mY
        End If
    End If

    ' Touch remains visible to gesture code and also drives old mouse widgets.
    input_CollectTouchContacts
    ' Some drivers expose the mouse as a touch contact too. Its latest sampled
    ' release must not erase an older queued press being replayed this frame.
    ' Gesture callers still receive all contacts; native pointer edges own the
    ' compatibility pointer until the queue is drained.
    If replayedPointerEvent = 0 Then
        input_ApplyTouchCompatibilityPointer
    Else
        inputTouchPointerActive = 0
        inputTouchPointerId = -1
    End If

    If useMockKeys Then
        If mockKeyEventOverflow Then inputKeyEventOverflow = -1
        For eventIndex As Long = 0 To mockKeyEventLength - 1
            With mockKeyEvents(eventIndex)
                input_RecordKeyEvent .event_kind, .scan_code, .character_byte, .modifiers
            End With
        Next eventIndex
        mockKeyEventLength = 0
        mockKeyEventOverflow = 0
        If mockKeys(FB.SC_CONTROL) <> 0 Then _
            mockModifiers Or= INPUT_MODIFIER_CONTROL
        If mockKeys(FB.SC_ALT) <> 0 Then _
            mockModifiers Or= INPUT_MODIFIER_ALT
        If mockKeys(FB.SC_LSHIFT) <> 0 OrElse _
           mockKeys(FB.SC_RSHIFT) <> 0 Then _
            mockModifiers Or= INPUT_MODIFIER_SHIFT

        For keyIndex As Integer = 0 To INPUT_KEY_LAST
            ' Held-state fixtures have no timestamp. Their edges follow the
            ' explicit queue in scan-code order, as the old snapshot did.
            If mockKeys(keyIndex) <> 0 AndAlso _
               mockPreviousKeys(keyIndex) = 0 Then
                input_RecordKeyEvent INPUT_KEY_EVENT_PRESS, CLng(keyIndex), 0, CLng(mockModifiers)
            ElseIf mockKeys(keyIndex) = 0 AndAlso mockPreviousKeys(keyIndex) <> 0 Then
                input_RecordKeyEvent INPUT_KEY_EVENT_RELEASE, CLng(keyIndex), 0, CLng(mockModifiers)
            End If
            mockPreviousKeys(keyIndex) = mockKeys(keyIndex)
        Next keyIndex
    End If

    If inputSuppressButtons Then
        If mButtons = 0 Then inputSuppressButtons = 0
        mButtons = 0
    End If
    inputSuppressText = 0
    For keyIndex As Integer = 0 To INPUT_KEY_LAST
        If inputKeyOverrideActive(keyIndex) AndAlso _
           input_RawKeyPressed(keyIndex) = 0 Then
            inputKeyOverrideActive(keyIndex) = 0
            inputKeyOverrideTarget(keyIndex) = 0
        End If
        If inputSuppressedKeys(keyIndex) Then
            Dim As Integer held_key = input_RawKeyPressed(keyIndex)
            If held_key = 0 Then
                inputSuppressedKeys(keyIndex) = 0
            Else
                inputSuppressText = -1
            End If
            inputKeyPressEvents(keyIndex) = 0
        End If
        If inputKeyOverrideActive(keyIndex) AndAlso _
           inputKeyOverrideTarget(keyIndex) = 0 AndAlso _
           input_RawKeyPressed(keyIndex) Then inputSuppressText = -1
    Next keyIndex
    ' Publish held keys and all queued chords once before widget dispatch.
    inputKeyBatchActive = 0
    input_RebuildKeyView
    If useMockText Then
        textBuffer = IIf(inputSuppressText, "", mockText)
        mockText = ""
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
        input_NavigationUpdate
#endif
        Exit Sub
    End If

    textBuffer = ""
    KeyText = Inkey

    While KeyText <> ""
        If Len(KeyText) = INPUT_TEXT_BYTE_COUNT Then
            If KeyText[INPUT_TEXT_BYTE_INDEX] >= INPUT_TEXT_ASCII_FIRST And _
               KeyText[INPUT_TEXT_BYTE_INDEX] <= INPUT_TEXT_ASCII_LAST Then
                If inputSuppressText = 0 Then textBuffer &= KeyText
            End If
        End If

        KeyText = Inkey
    Wend
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
    input_NavigationUpdate
#endif
End Sub

' -------------------------------------------------------------------------
' Per-frame state and dispatch accessors
' -------------------------------------------------------------------------

Function input_MouseX() As Integer
    If pointerDispatchEnabled = 0 Then Return -1
    Return mX
End Function

Function input_MouseY() As Integer
    If pointerDispatchEnabled = 0 Then Return -1
    Return mY
End Function

Function input_MouseButtons() As Integer
    If pointerDispatchEnabled = 0 Then Return 0
    Return mButtons
End Function

Function input_UnmaskedMouseButtons() As Integer
    Return mButtons
End Function

Function input_MouseWheel() As Integer
    If pointerDispatchEnabled = 0 Then Return 0
    Return mWheelDelta
End Function

Function input_TouchCount() As Integer
    If pointerDispatchEnabled = 0 Then Return 0
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
    Return input_NavigationTouchCount()
#else
    Return inputTouchContactCount
#endif
End Function

Function input_Touch( _
    ByVal contactIndex As Integer, _
    ByRef x As Integer, ByRef y As Integer, ByRef id As Integer _
) As Integer
    x = -1
    y = -1
    id = -1
    If pointerDispatchEnabled = 0 Then Return 0
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
    Return input_NavigationTouch(contactIndex, x, y, id)
#endif
    If contactIndex < 0 OrElse contactIndex >= inputTouchContactCount Then Return 0
    x = inputTouchX(contactIndex)
    y = inputTouchY(contactIndex)
    id = inputTouchId(contactIndex)
    Return -1
End Function

Function input_AnyKeyPressed() As Integer
    Dim As Integer keyIndex

    If keyboardDispatchEnabled = 0 Then Return 0
    For keyIndex = 0 To INPUT_KEY_LAST
        ' Held state and buffered press edges are both valid modal input.
        If input_KeyPressed(keyIndex) <> 0 OrElse _
           inputKeyPressEvents(keyIndex) <> 0 Then Return -1
    Next keyIndex
    Return 0
End Function


Function input_KeyPressed(ByVal k As Integer) As Integer
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
    If k >= 0 AndAlso k <= 255 Then
        If omagui_nav_nav_key_consumed(k) Then Return 0
    End If
#endif
    If k < 0 OrElse k > INPUT_KEY_LAST Then Return 0
    If keyboardDispatchEnabled = 0 Then Return 0
    Return inputEffectiveKeyPressed(k)
End Function

Function input_KeyPressEvent(ByVal k As Integer) As Integer
    If k < 0 OrElse k > INPUT_KEY_LAST Then Return 0
    If keyboardDispatchEnabled = 0 Then Return 0
    Return inputEffectiveKeyPressEvents(k)
End Function


Function input_SetKeyEventMapping( _
    ByVal sourceScanCode As Integer, ByVal targetScanCode As Integer _
) As Integer
    If sourceScanCode < 0 OrElse sourceScanCode > INPUT_KEY_LAST OrElse _
       targetScanCode < 0 OrElse targetScanCode > INPUT_KEY_LAST Then Return 0

    If sourceScanCode = targetScanCode Then
        inputKeyOverrideActive(sourceScanCode) = 0
        inputKeyOverrideTarget(sourceScanCode) = 0
    Else
        inputKeyOverrideActive(sourceScanCode) = -1
        inputKeyOverrideTarget(sourceScanCode) = targetScanCode
        If targetScanCode = 0 Then
            inputSuppressText = -1
            textBuffer = ""
        End If
    End If
    input_RebuildKeyView
    Return -1
End Function

Function input_KeyEventCount() As Long
    If keyboardDispatchEnabled = 0 Then Return 0
    Return inputKeyEventLength
End Function

Function input_ReadKeyEvent(ByVal eventIndex As Long, ByRef eventValue As InputKeyEvent) As Integer
    ' Clear even on failure so stale caller storage cannot masquerade as input.
    eventValue = Type<InputKeyEvent>(0, 0, 0, 0)
    If keyboardDispatchEnabled = 0 Then Return 0
    If eventIndex < 0 OrElse eventIndex >= inputKeyEventLength Then Return 0
    eventValue = inputKeyEvents(eventIndex)
    Return -1
End Function

' The editor's navigation API is a view over the richer ordered event stream.
Function input_KeyEvent( _
    ByVal eventIndex As Integer, _
    ByRef scanCode As Integer, ByRef modifiers As Integer _
) As Integer
    Dim As InputKeyEvent eventValue
    scanCode = 0
    modifiers = INPUT_MODIFIER_NONE
    If input_ReadKeyEvent(CLng(eventIndex), eventValue) = 0 Then Return 0
    If eventValue.event_kind = INPUT_KEY_EVENT_RELEASE Then Return 0
    scanCode = input_MappedScanCode(eventValue.scan_code)
    If scanCode = 0 Then Return 0
    modifiers = eventValue.modifiers
    Return -1
End Function

Function input_KeyEventsOverflowed() As Integer
    If keyboardDispatchEnabled = 0 Then Return 0
    Return inputKeyEventOverflow
End Function

Function input_ModifiedKeyPressEvent( _
    ByVal k As Integer, _
    ByVal requiredModifiers As Integer _
) As Integer
    If input_KeyPressEvent(k) = 0 Then Return 0
    If requiredModifiers = INPUT_MODIFIER_NONE Then Return -1
    If requiredModifiers < 0 OrElse requiredModifiers > 7 Then Return 0
    ' Three independent modifier bits give eight possible chords.
    For modifierChordIndex As Integer = 0 To 7
        If (modifierChordIndex And requiredModifiers) = requiredModifiers AndAlso _
           (inputEffectiveKeyPressChords(k) And _
            (1 Shl modifierChordIndex)) <> 0 Then Return -1
    Next modifierChordIndex
    Return 0
End Function

Function input_ExactModifiedKeyPressEvent( _
    ByVal k As Integer, _
    ByVal modifiers As Integer _
) As Integer
    If input_KeyPressEvent(k) = 0 Then Return 0
    If modifiers < INPUT_MODIFIER_NONE OrElse modifiers > 7 Then Return 0

    /'
        inputKeyPressChords keeps one bit for each chord that pressed this
        scan code in the sampled frame. Exact matching matters for retained
        menu bindings: a Ctrl+Shift chord must not activate a Ctrl-only item.
    '/
    Return IIf( _
        (inputEffectiveKeyPressChords(k) And (1 Shl modifiers)) <> 0, -1, 0 _
    )
End Function


Function input_ControlShortcutPressed(ByVal k As Integer) As Integer
    Return input_ModifiedKeyPressEvent(k, INPUT_MODIFIER_CONTROL)
End Function

Function input_AltShortcutPressed(ByVal k As Integer) As Integer
    Return input_ModifiedKeyPressEvent(k, INPUT_MODIFIER_ALT)
End Function

Function input_PollTextInput() As String
    If keyboardDispatchEnabled = 0 Then Return ""
    Return textBuffer
End Function


Function input_TakeWindowCloseRequested() As Integer
    Dim As Integer requested

    requested = inputWindowCloseRequested
    inputWindowCloseRequested = 0
    Return requested
End Function

Sub input_SetDispatchMask( _
    ByVal pointerEnabled As Integer, _
    ByVal keyboardEnabled As Integer _
)
    pointerDispatchEnabled = IIf(pointerEnabled <> 0, -1, 0)
    keyboardDispatchEnabled = IIf(keyboardEnabled <> 0, -1, 0)
End Sub

Sub input_MockMouse( _
    ByVal x As Integer, ByVal y As Integer, ByVal b As Integer, _
    ByVal wheelDelta As Integer _
)
    mockX = x
    mockY = y
    mockButtons = b
    mockWheelDelta = wheelDelta
    useMockMouse = 1
End Sub

Sub input_MockTouchCount(ByVal contactCount As Integer)
    If contactCount < 0 Then contactCount = 0
    If contactCount > INPUT_TOUCH_CAPACITY Then _
        contactCount = INPUT_TOUCH_CAPACITY
    mockTouchContactCount = contactCount
    useMockTouch = 1
End Sub

Sub input_MockTouch( _
    ByVal contactIndex As Integer, _
    ByVal x As Integer, ByVal y As Integer, ByVal id As Integer _
)
    If contactIndex < 0 OrElse contactIndex >= INPUT_TOUCH_CAPACITY Then Exit Sub
    mockTouchX(contactIndex) = x
    mockTouchY(contactIndex) = y
    mockTouchId(contactIndex) = id
    If mockTouchContactCount <= contactIndex Then _
        mockTouchContactCount = contactIndex + 1
    useMockTouch = 1
End Sub

Sub input_MockKey(ByVal k As Integer, ByVal state As Integer)
    If k < 0 Or k > INPUT_KEY_LAST Then Exit Sub

    mockKeys(k) = state
    useMockKeys = 1
    ' Held mock keys are observable immediately, like native MultiKey state.
    input_RebuildKeyView
End Sub

Sub input_MockKeyPress( _
    ByVal k As Integer, _
    ByVal modifiers As Integer _
)
    If k < 0 OrElse k > INPUT_KEY_LAST Then Exit Sub
    If modifiers < 0 OrElse modifiers > 7 Then Exit Sub
    input_MockKeyEvent INPUT_KEY_EVENT_PRESS, CLng(k), 0, CLng(modifiers)
End Sub

Function input_MockKeyEvent( _
    ByVal eventKind As Long, ByVal scanCode As Long, _
    ByVal characterByte As Long, ByVal modifiers As Long _
) As Integer
    If eventKind < INPUT_KEY_EVENT_PRESS OrElse eventKind > INPUT_KEY_EVENT_REPEAT Then Return 0
    If scanCode < 0 OrElse scanCode > INPUT_KEY_LAST Then Return 0
    If characterByte < 0 OrElse characterByte > 255 Then Return 0
    If modifiers < 0 OrElse modifiers > 7 Then Return 0
    useMockKeys = 1
    If mockKeyEventLength >= INPUT_KEY_EVENT_CAPACITY Then
        mockKeyEventOverflow = -1
        Return 0
    End If
    With mockKeyEvents(mockKeyEventLength)
        .event_kind = eventKind
        .scan_code = scanCode
        .character_byte = IIf(eventKind = INPUT_KEY_EVENT_RELEASE, 0, characterByte)
        .modifiers = modifiers
    End With
    mockKeyEventLength += 1
    Return -1
End Function

Sub input_MockControlShortcut(ByVal k As Integer)
    input_MockKeyPress k, INPUT_MODIFIER_CONTROL
End Sub

Sub input_MockText(ByVal txt As String)
    mockText = txt
    useMockText = 1
End Sub

' -------------------------------------------------------------------------
' Test reset and display handoff
' -------------------------------------------------------------------------

Sub input_ResetForTest()
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
    input_NavigationReset
#endif
    inputKeyBatchActive = 0
    ' A test reset owns every input source. Native mouse-as-touch contacts
    ' must not override mocked coordinates on targets such as Haiku.
    useMockTouch = 1
    mockTouchContactCount = 0
    inputTouchContactCount = 0
    inputTouchPointerActive = 0
    inputTouchPointerId = -1
    inputKeyEventLength = 0
    mockKeyEventLength = 0
    inputKeyEventOverflow = 0
    mockKeyEventOverflow = 0
    Erase inputNativeModifierKeys
    inputSuppressButtons = 0
    inputSuppressText = 0
    mX = 0
    mY = 0
    mWheelDelta = 0
    mButtons = 0
    mockX = 0
    mockY = 0
    mockButtons = 0
    mockWheelDelta = 0
    previousWheelPosition = 0
    wheelPositionInitialized = 0
    useMockMouse = 1
    useMockKeys = 1
    useMockText = 1
    textBuffer = ""
    mockText = ""
    pointerDispatchEnabled = -1
    keyboardDispatchEnabled = -1
    inputPointerEventHead = 0
    inputPointerEventTail = 0
    inputPointerEventCount = 0
    inputNativeButtons = 0
    inputNativeButtonsInitialized = 0
    inputNativeX = 0
    inputNativeY = 0
    inputWindowCloseRequested = 0
    inputNativeModifiers = INPUT_MODIFIER_NONE

    For keyIndex As Integer = 0 To INPUT_KEY_LAST
        mockKeys(keyIndex) = 0
        inputSuppressedKeys(keyIndex) = 0
        mockPreviousKeys(keyIndex) = 0
        inputKeyPressEvents(keyIndex) = 0
        inputKeyPressChords(keyIndex) = 0
        inputKeyOverrideActive(keyIndex) = 0
        inputKeyOverrideTarget(keyIndex) = 0
        inputEffectiveKeyPressed(keyIndex) = 0
        inputEffectiveKeyPressEvents(keyIndex) = 0
        inputEffectiveKeyPressChords(keyIndex) = 0
    Next keyIndex
End Sub

Sub input_ResumeAfterScreenChange()
    inputTouchContactCount = 0
    inputTouchPointerActive = 0
    inputTouchPointerId = -1
    Const MAX_DISCARDED_EVENTS As Integer = 1024 ' Bound a concurrent native event producer.
    Dim As FB.Event event_value
    inputKeyEventLength = 0
    mockKeyEventLength = 0
    inputKeyEventOverflow = 0
    mockKeyEventOverflow = 0
    Erase inputNativeModifierKeys
    mButtons = 0
    mWheelDelta = 0
    previousWheelPosition = 0
    wheelPositionInitialized = 0
    mockWheelDelta = 0
    textBuffer = ""
    mockText = ""
    inputPointerEventHead = 0
    inputPointerEventTail = 0
    inputPointerEventCount = 0
    inputNativeButtonsInitialized = 0
    inputNativeButtons = 0
    inputNativeModifiers = INPUT_MODIFIER_NONE
    inputWindowCloseRequested = 0
    pointerDispatchEnabled = -1
    keyboardDispatchEnabled = -1
    inputSuppressButtons = -1
    inputSuppressText = 0
    If ScreenPtr <> 0 Then
        For event_index As Integer = 1 To MAX_DISCARDED_EVENTS
            If ScreenEvent(@event_value) = 0 Then Exit For
            ' A close request on the new window still belongs to the owner.
            If event_value.type = FB.EVENT_WINDOW_CLOSE Then inputWindowCloseRequested = -1
        Next event_index
        If useMockText = 0 Then
            ' fblint: disable-next-line FBL311 REASON: This counted drain is bounded even if the producer keeps supplying text.
            For key_index As Integer = 1 To MAX_DISCARDED_EVENTS
                If Len(Inkey) = 0 Then Exit For
            Next key_index
        End If
    End If
    For keyIndex As Integer = 0 To INPUT_KEY_LAST
        inputKeyPressEvents(keyIndex) = 0
        inputKeyPressChords(keyIndex) = 0
        mockPreviousKeys(keyIndex) = mockKeys(keyIndex)
        inputSuppressedKeys(keyIndex) = IIf(useMockKeys, mockKeys(keyIndex), MultiKey(keyIndex))
        inputKeyOverrideActive(keyIndex) = 0
        inputKeyOverrideTarget(keyIndex) = 0
        inputEffectiveKeyPressed(keyIndex) = 0
        inputEffectiveKeyPressEvents(keyIndex) = 0
        inputEffectiveKeyPressChords(keyIndex) = 0
    Next keyIndex
End Sub

' end of input_gfxlib.bas
