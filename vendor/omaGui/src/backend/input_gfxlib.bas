/'
    Project: omaGUI
    ---------------
    File: input_gfxlib.bas

    Purpose:
        Implement the input abstraction with FreeBASIC gfxlib calls.

    Responsibilities:
        - poll mouse position, buttons, wheel movement, keys, and text input
        - collect native and browser touch contacts for shared pointer gestures
        - buffer native mouse transitions which occur between GUI frames
        - retain ordered key transitions, repeats, and individual modifier chords
        - keep console printable text and editor commands in ordered delivery batches
        - retain a native window-close request until the application reads it
        - retain native window focus for host-owned controller input
        - expose per-widget pointer and keyboard dispatch masks
        - track shared vertical drag-to-scroll gestures with bounded coordinates
        - read browser touch contacts when an Emscripten runtime has no touch events
        - consume action edges without changing held keys or raw notifications
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
' The navigation dispatcher and input accessor share this consumed-key table
' within the single omaGUI implementation on the GUI thread.
' fblint: disable-next-line FBL301
Dim Shared omagui_nav_nav_key_consumed(0 To 255) As Integer
#endif

#include once "src/widgets/widgets.bi"

/'
    The backend is compiled into omaGUI as a collection of include modules,
    so its private polling state must be shared with the accessor routines in
    this file.  It is not part of the public input API.
'/

Dim Shared As Integer mX, mY, mButtons, mWheelDelta
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer mDoubleClick
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer previousWheelPosition, wheelPositionInitialized

Dim Shared As Integer mockX, mockY, mockButtons, mockWheelDelta

Dim Shared As Integer useMockMouse, useMockTouch, useMockKeys, useMockText

Dim Shared As Integer pointerDispatchEnabled = -1, keyboardDispatchEnabled = -1
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As String textBuffer, mockText, inputOrderedTextBuffer

' Ten contacts bound both native polling and deterministic input fixtures.
Dim Shared As Integer inputTouchContactCount, mockTouchContactCount
Dim Shared As Integer inputTouchX(0 To INPUT_TOUCH_CAPACITY - 1)
Dim Shared As Integer inputTouchY(0 To INPUT_TOUCH_CAPACITY - 1)
Dim Shared As Integer inputTouchId(0 To INPUT_TOUCH_CAPACITY - 1)
Dim Shared As Integer inputTouchPointerActive, inputTouchPointerId = -1
' Keep a second finger from becoming a synthetic click after the primary lifts.
Dim Shared As Integer inputTouchPointerSuppressed
' Native mouse events own their matching touch contacts until all fingers lift.
Dim Shared As Integer inputNativeTouchOwner
Dim Shared As Integer inputTouchPointerX, inputTouchPointerY
Dim Shared As Integer mockTouchX(0 To INPUT_TOUCH_CAPACITY - 1)
Dim Shared As Integer mockTouchY(0 To INPUT_TOUCH_CAPACITY - 1)
Dim Shared As Integer mockTouchId(0 To INPUT_TOUCH_CAPACITY - 1)

#if defined(__FB_JS__)
Extern "C"
    Declare Function emscripten_run_script_int _
        Alias "emscripten_run_script_int" _
        (ByVal script As Const ZString Ptr) As Integer
End Extern

Dim Shared As Integer inputJavaScriptTouchBridgeInstalled
Dim Shared As String inputJavaScriptTouchBridgeScript
Dim Shared As String inputJavaScriptTouchCountScript
Dim Shared As String inputJavaScriptTouchQueries( _
    0 To INPUT_TOUCH_CAPACITY * 3 - 1 _
)
#endif

' FreeBASIC gfxlib scan codes are represented by one unsigned byte.
Const INPUT_KEY_LAST = 255
' Bound native event work to the retained press/release event capacity.
Const INPUT_NATIVE_EVENT_CAPACITY As Long = INPUT_KEY_EVENT_CAPACITY * 2
Const INPUT_TEXT_BOUNDARY_CHARACTER_LIMIT As Long = INPUT_KEY_EVENT_CAPACITY
Private Dim Shared As Integer inputTextBoundaryKeys(0 To INPUT_KEY_LAST)
Private Dim Shared As Integer inputTextBoundaryReached
Private Dim Shared As Long inputTextBoundaryCharacterCount
' The GUI thread owns this callback-free input frame. Public mock/mapping
' setters and standalone native translators keep their immediate view.
' GUI-thread logical mapping belongs to the active renderer mode.
Private Dim Shared As Integer inputLogicalMappingActive
Private Dim Shared As Integer inputPhysicalLeft, inputPhysicalTop
Private Dim Shared As Integer inputPhysicalWidth, inputPhysicalHeight
Private Dim Shared As Integer inputLogicalWidth, inputLogicalHeight
Private Dim Shared As Integer inputKeyBatchActive
Private Dim Shared As Integer inputFrameActivity
Private Dim Shared As UInteger inputFrameActivityFlags
Private Dim Shared As Integer inputActivitySnapshotValid
Private Dim Shared As Integer inputActivityMouseX, inputActivityMouseY
Private Dim Shared As Integer inputActivityMouseButtons
Private Dim Shared As Integer inputActivityTouchCount
Private Dim Shared As Integer inputActivityTouchX(0 To INPUT_TOUCH_CAPACITY - 1)
Private Dim Shared As Integer inputActivityTouchY(0 To INPUT_TOUCH_CAPACITY - 1)
Private Dim Shared As Integer inputActivityTouchId(0 To INPUT_TOUCH_CAPACITY - 1)

/'
    Keyboard controls need edge retention for the same reason as pointer
    clicks. A complete Tab, Enter, arrow key, or Alt shortcut may occur while
    an application is parsing a document or formatting live data. MultiKey
    requires a driver lock for every query, so ScreenEvent keeps the current
    held state alongside each press and release. It also preserves the
    modifier state that existed at that instant.
'/

Dim Shared As Integer inputNativeModifiers
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputNativeKeys(0 To INPUT_KEY_LAST)
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputKeyPressEvents(0 To INPUT_KEY_LAST)

Dim Shared As Integer inputKeyPressChords(0 To INPUT_KEY_LAST)
' KeyDown callbacks can change a physical key's meaning for its focused
' control. Raw ordered records remain intact so KeyUp still sees the real key.
Dim Shared As Integer inputKeyOverrideActive(0 To INPUT_KEY_LAST)
Dim Shared As Integer inputKeyOverrideTarget(0 To INPUT_KEY_LAST)
Dim Shared As Integer inputEffectiveKeyPressed(0 To INPUT_KEY_LAST)
Dim Shared As Integer inputEffectiveKeyPressEvents(0 To INPUT_KEY_LAST)
Dim Shared As Integer inputEffectiveKeyPressChords(0 To INPUT_KEY_LAST)
Private Dim Shared As Integer inputActivityKeys(0 To INPUT_KEY_LAST)
' Track both Shift keys separately. Releasing one must not release the other.

Dim Shared As Integer inputNativeModifierKeys(0 To INPUT_KEY_LAST)

' All event storage belongs to the GUI input thread. No callback or pointer
' escapes these fixed buffers. Mock records become visible only at Update.

Dim Shared As InputKeyEvent inputKeyEvents(0 To INPUT_KEY_EVENT_CAPACITY - 1)

Dim Shared As InputKeyEvent mockKeyEvents(0 To INPUT_KEY_EVENT_CAPACITY - 1)

Dim Shared As Long inputKeyEventLength, mockKeyEventLength

Dim Shared As Integer inputKeyEventOverflow, mockKeyEventOverflow

#if defined(__FB_LINUX__) and not defined(__FB_JS__)
' SCREENEVENT can carry Unicode committed by a Linux input method. The graphics
' queue admits 255 committed characters, even when their press/release pairs
' overflow the smaller public key-event snapshot. Keep text separately in order.
' Once Unicode selects event text, keep using events until the screen changes:
' a legacy byte drained after polling can otherwise vanish from the next frame.
Const INPUT_NATIVE_TEXT_CAPACITY As Integer = 255
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Long inputNativeTextScalars(0 To INPUT_NATIVE_TEXT_CAPACITY - 1)
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputNativeTextLength
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputNativeUseEventText
#endif

#if defined(__FB_DOS__) Or defined(__FB_WII__)
/'
    DOS and Wii have a sixteen-slot legacy Inkey ring, separate from ScreenEvent.
    Draining both after a long frame can lose text and move Tab focus before
    delivering characters typed for the preceding control. Keep native key
    records together and publish text up to the next editor command. A command
    gets its own frame; the widget manager still owns its meaning and focus.

    This bounded queue belongs only to the GUI thread. The native driver owns
    gfxlib's queue; ScreenEvent copies records out of it.
'/
Private Dim Shared As FB.Event inputDOSKeyQueue(0 To INPUT_KEY_EVENT_CAPACITY - 1)
Private Dim Shared As Integer inputDOSKeyHead, inputDOSKeyTail, inputDOSKeyCount
Private Dim Shared As String inputDOSFrameText
#endif

' Snapshot identity is GUI-thread state, independent of mutable key mappings.
' Zero is the initial unsampled view; replacement advances without wrapping
' back to zero so nested consumers can distinguish that state as well.
Private Dim Shared As ULongInt inputFrameSerial

Private Sub input_AdvanceFrameSerial()
    If inputFrameSerial = &hFFFFFFFFFFFFFFFFULL Then
        inputFrameSerial = 1
    Else
        inputFrameSerial += 1
    End If
End Sub

Function input_FrameSerial() As ULongInt
    Return inputFrameSerial
End Function

/'
    GetMouse exposes only current state. A complete click can otherwise vanish
    when DD rendering takes longer than the press. ScreenEvent supplies the
    missing edges and the native double-click marker; one queued state is
    replayed per GUI frame so existing widgets keep their capture semantics.
'/
Const INPUT_POINTER_EVENT_CAPACITY As Long = 64

Dim Shared As Long inputPointerEventX(0 To INPUT_POINTER_EVENT_CAPACITY - 1)

Dim Shared As Long inputPointerEventY(0 To INPUT_POINTER_EVENT_CAPACITY - 1)

Dim Shared As Integer inputPointerEventButtons( _
    0 To INPUT_POINTER_EVENT_CAPACITY - 1 _
)
' A held-button move may be replaced by a newer move, but a press or release
' must keep its own queue slot so a short drag survives a slow GUI frame.
Dim Shared As Integer inputPointerEventIsMotion( _
    0 To INPUT_POINTER_EVENT_CAPACITY - 1 _
)
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputPointerEventDoubleClick( _
    0 To INPUT_POINTER_EVENT_CAPACITY - 1 _
)
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Long inputPointerEventHead, inputPointerEventTail

Dim Shared As Long inputPointerEventCount

Dim Shared As Integer inputNativeButtons, inputNativeButtonsInitialized
' The GUI thread tracks window entry so idle frames do not poll outside it.
Dim Shared As Integer inputNativePointerInside
Dim Shared As Integer inputNativeScreenWidth, inputNativeScreenHeight
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputNativeX, inputNativeY
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputNativeMouseResync, inputNativePointerEventPending
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputNativeWheelEventPending
' FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared As Integer inputWindowCloseRequested
' Unknown targets start active until gfxlib reports a focus transition.
Dim Shared As Integer inputWindowFocused = -1


Dim Shared As Integer mockKeys(0 To INPUT_KEY_LAST)

Dim Shared As Integer mockPreviousKeys(0 To INPUT_KEY_LAST)
' A restored GUI must not interpret the key/button that ended external drawing
' as a new activation. This suppression belongs to the GUI input thread.
Dim Shared As Integer inputSuppressedKeys(0 To INPUT_KEY_LAST)
Dim Shared As Integer inputSuppressButtons, inputSuppressText

' The legacy INKEY fallback accepts printable ASCII. Linux Unicode commits
' use the separate SCREENEVENT text buffer above.
Const INPUT_TEXT_BYTE_INDEX = 0
Const INPUT_TEXT_BYTE_COUNT = 1
Const INPUT_TEXT_ASCII_FIRST = 32
Const INPUT_TEXT_ASCII_LAST = 126

' -------------------------------------------------------------------------
' Physical-to-logical pointer mapping
' -------------------------------------------------------------------------

Private Function input_MapPhysicalPoint(ByRef x As Integer, ByRef y As Integer) As Integer
    If inputLogicalMappingActive = 0 Then Return -1
    If x < inputPhysicalLeft OrElse y < inputPhysicalTop OrElse _
       x >= inputPhysicalLeft + inputPhysicalWidth OrElse _
       y >= inputPhysicalTop + inputPhysicalHeight Then
        x = -1
        y = -1
        Return 0
    End If

    ' Public dimensions are signed Integers. Widen before multiplication so a
    ' valid large viewport cannot overflow while it is reduced to logical space.
    x = CInt((CLngInt(x - inputPhysicalLeft) * inputLogicalWidth) \ inputPhysicalWidth)
    y = CInt((CLngInt(y - inputPhysicalTop) * inputLogicalHeight) \ inputPhysicalHeight)
    If x >= inputLogicalWidth Then x = inputLogicalWidth - 1
    If y >= inputLogicalHeight Then y = inputLogicalHeight - 1
    Return -1
End Function


Function input_SetLogicalViewport( _
    ByVal viewportPhysicalLeft As Integer, ByVal viewportPhysicalTop As Integer, _
    ByVal viewportPhysicalWidth As Integer, ByVal viewportPhysicalHeight As Integer, _
    ByVal viewportLogicalWidth As Integer, ByVal viewportLogicalHeight As Integer _
) As Integer
    If viewportPhysicalLeft < 0 OrElse viewportPhysicalTop < 0 OrElse viewportPhysicalWidth < 1 OrElse _
       viewportPhysicalHeight < 1 OrElse viewportLogicalWidth < 1 OrElse viewportLogicalHeight < 1 Then Return 0
    If viewportPhysicalLeft > &H3FFFFFFF - viewportPhysicalWidth OrElse _
       viewportPhysicalTop > &H3FFFFFFF - viewportPhysicalHeight Then Return 0

    inputPhysicalLeft = viewportPhysicalLeft
    inputPhysicalTop = viewportPhysicalTop
    inputPhysicalWidth = viewportPhysicalWidth
    inputPhysicalHeight = viewportPhysicalHeight
    inputLogicalWidth = viewportLogicalWidth
    inputLogicalHeight = viewportLogicalHeight
    inputLogicalMappingActive = -1
    Return -1
End Function


Sub input_ClearLogicalViewport()
    inputLogicalMappingActive = 0
    inputPhysicalLeft = 0
    inputPhysicalTop = 0
    inputPhysicalWidth = 0
    inputPhysicalHeight = 0
    inputLogicalWidth = 0
    inputLogicalHeight = 0
End Sub


Function input_MapNativeToLogical(ByRef x As Integer, ByRef y As Integer) As Integer
    Return input_MapPhysicalPoint(x, y)
End Function


Function input_MapLogicalToNative(ByRef x As Integer, ByRef y As Integer) As Integer
    If inputLogicalMappingActive = 0 Then Return -1
    If x < 0 OrElse y < 0 OrElse x >= inputLogicalWidth OrElse y >= inputLogicalHeight Then Return 0

    x = inputPhysicalLeft + CInt((CLngInt(x) * inputPhysicalWidth + _
        inputLogicalWidth \ 2) \ inputLogicalWidth)
    y = inputPhysicalTop + CInt((CLngInt(y) * inputPhysicalHeight + _
        inputLogicalHeight \ 2) \ inputLogicalHeight)
    If x >= inputPhysicalLeft + inputPhysicalWidth Then x = inputPhysicalLeft + inputPhysicalWidth - 1
    If y >= inputPhysicalTop + inputPhysicalHeight Then y = inputPhysicalTop + inputPhysicalHeight - 1
    Return -1
End Function


' -------------------------------------------------------------------------
' Native transition collection
' -------------------------------------------------------------------------

Private Sub input_QueuePointerEvent( _
    ByVal x As Long, _
    ByVal y As Long, _
    ByVal buttons As Integer, _
    ByVal doubleClick As Integer = 0 _
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
    inputPointerEventIsMotion(inputPointerEventTail) = 0
    inputPointerEventDoubleClick(inputPointerEventTail) = doubleClick
    inputPointerEventTail += 1
    If inputPointerEventTail >= INPUT_POINTER_EVENT_CAPACITY Then _
        inputPointerEventTail = 0
    inputPointerEventCount += 1
End Sub

Private Sub input_QueuePointerMove(ByVal x As Long, ByVal y As Long)
    If inputNativeButtons = 0 Then Exit Sub

    Dim previous As Long = inputPointerEventTail - 1
    If previous < 0 Then previous = INPUT_POINTER_EVENT_CAPACITY - 1
    If inputPointerEventCount > 0 AndAlso _
       inputPointerEventIsMotion(previous) <> 0 AndAlso _
       inputPointerEventButtons(previous) = inputNativeButtons Then
        inputPointerEventX(previous) = x
        inputPointerEventY(previous) = y
        Exit Sub
    End If

    input_QueuePointerEvent x, y, inputNativeButtons
    previous = inputPointerEventTail - 1
    If previous < 0 Then previous = INPUT_POINTER_EVENT_CAPACITY - 1
    inputPointerEventIsMotion(previous) = -1
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


#Ifdef OMAGUI_ORDERED_TEXT_INPUT
Private Function input_EncodeTextByte(ByVal value As UInteger) As String
    ' Native gfxlib bytes become UTF-8 before they enter FreeBASIC strings.
    Dim As UInteger codePoint = value
#If Defined(__FB_DOS__)
    Static As UInteger pcCodePoints(0 To 127) = { _
        &hC7,&hFC,&hE9,&hE2,&hE4,&hE0,&hE5,&hE7,&hEA,&hEB,&hE8,&hEF,&hEE,&hEC,&hC4,&hC5, _
        &hC9,&hE6,&hC6,&hF4,&hF6,&hF2,&hFB,&hF9,&hFF,&hD6,&hDC,&hA2,&hA3,&hA5,&h20A7,&h192, _
        &hE1,&hED,&hF3,&hFA,&hF1,&hD1,&hAA,&hBA,&hBF,&h2310,&hAC,&hBD,&hBC,&hA1,&hAB,&hBB, _
        &h2591,&h2592,&h2593,&h2502,&h2524,&h2561,&h2562,&h2556,&h2555,&h2563,&h2551,&h2557,&h255D,&h255C,&h255B,&h2510, _
        &h2514,&h2534,&h252C,&h251C,&h2500,&h253C,&h255E,&h255F,&h255A,&h2554,&h2569,&h2566,&h2560,&h2550,&h256C,&h2567, _
        &h2568,&h2564,&h2565,&h2559,&h2558,&h2552,&h2553,&h256B,&h256A,&h2518,&h250C,&h2588,&h2584,&h258C,&h2590,&h2580, _
        &h3B1,&hDF,&h393,&h3C0,&h3A3,&h3C3,&hB5,&h3C4,&h3A6,&h398,&h3A9,&h3B4,&h221E,&h3C6,&h3B5,&h2229, _
        &h2261,&hB1,&h2265,&h2264,&h2320,&h2321,&hF7,&h2248,&hB0,&h2219,&hB7,&h221A,&h207F,&hB2,&h25A0,&hA0 _
    }
    If value >= 128 AndAlso value <= 255 Then codePoint = pcCodePoints(value - 128)
#ElseIf Defined(__FB_WIN32__) And Not Defined(__FB_JS__)
    Static As UInteger ansiCodePoints(0 To 31) = { _
        &h20AC,&h81,&h201A,&h192,&h201E,&h2026,&h2020,&h2021,&h2C6,&h2030,&h160,&h2039,&h152,&h8D,&h17D,&h8F, _
        &h90,&h2018,&h2019,&h201C,&h201D,&h2022,&h2013,&h2014,&h2DC,&h2122,&h161,&h203A,&h153,&h9D,&h17E,&h178 _
    }
    If value >= 128 AndAlso value <= 159 Then codePoint = ansiCodePoints(value - 128)
#EndIf
#If Defined(__FB_JS__)
    If codePoint <= 255 Then Return Chr(codePoint)
#EndIf
    If codePoint > &h10FFFF OrElse (codePoint >= &hD800 AndAlso codePoint <= &hDFFF) Then Return ""
    If codePoint < 128 Then Return Chr(codePoint)
    If codePoint < &h800 Then _
        Return Chr(&hC0 + codePoint \ 64) & Chr(&h80 + codePoint Mod 64)
    If codePoint < &h10000 Then Return Chr(&hE0 + codePoint \ 4096) & _
        Chr(&h80 + (codePoint \ 64) Mod 64) & Chr(&h80 + codePoint Mod 64)
    Return Chr(&hF0 + codePoint \ 262144) & _
        Chr(&h80 + (codePoint \ 4096) Mod 64) & _
        Chr(&h80 + (codePoint \ 64) Mod 64) & Chr(&h80 + codePoint Mod 64)
End Function
#EndIf


Private Function input_RawKeyPressed(ByVal scanCode As Integer) As Integer
    If scanCode < 0 OrElse scanCode > INPUT_KEY_LAST Then Return 0
    If useMockKeys Then Return IIf(mockKeys(scanCode) <> 0, -1, 0)
    Return IIf(inputNativeKeys(scanCode) <> 0, -1, 0)
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
    inputNativeKeys(scanCode) = IIf(eventRecord.type = FB.EVENT_KEY_RELEASE, 0, -1)
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
#if defined(__FB_LINUX__) and not defined(__FB_JS__)
    If inputSuppressedKeys(scanCode) = 0 AndAlso eventRecord.type <> FB.EVENT_KEY_RELEASE Then
        Dim As Long scalar = eventRecord.ascii
        If scalar >= &H20 AndAlso scalar <= &H10FFFF AndAlso _
           (scalar < &H7F OrElse scalar >= &HA0) AndAlso _
           (scalar < &HD800 OrElse scalar > &HDFFF) Then
            If inputNativeTextLength < INPUT_NATIVE_TEXT_CAPACITY Then
                inputNativeTextScalars(inputNativeTextLength) = scalar
                inputNativeTextLength += 1
            Else
                inputKeyEventOverflow = -1
            End If
            If scalar >= &HA0 Then inputNativeUseEventText = -1
        End If
    End If
#endif
    input_RecordKeyEvent eventRecord.type, scanCode, characterByte, CLng(inputNativeModifiers)
End Sub

#if defined(__FB_LINUX__) and not defined(__FB_JS__)
' Encode Unicode scalar values using the standard UTF-8 lead and continuation bits.
Private Function input_EncodeUTF8Scalar(ByVal scalar As ULong) As String
    If scalar < &H80 Then Return Chr(scalar)
    If scalar < &H800 Then _
        Return Chr(&HC0 Or (scalar Shr 6), &H80 Or (scalar And &H3F))
    If scalar < &H10000 Then _
        Return Chr(&HE0 Or (scalar Shr 12), &H80 Or ((scalar Shr 6) And &H3F), _
            &H80 Or (scalar And &H3F))
    Return Chr(&HF0 Or (scalar Shr 18), &H80 Or ((scalar Shr 12) And &H3F), _
        &H80 Or ((scalar Shr 6) And &H3F), &H80 Or (scalar And &H3F))
End Function

Private Function input_NativeUnicodeFrameText() As String
    Dim As String frameText
    For eventIndex As Integer = 0 To inputNativeTextLength - 1
        Dim As Long scalar = inputNativeTextScalars(eventIndex)
        If scalar > 0 Then frameText &= input_EncodeUTF8Scalar(CULng(scalar))
    Next eventIndex
    Return frameText
End Function
#endif


#if defined(__FB_DOS__) Or defined(__FB_WII__)
Private Sub input_DOSClearKeyQueue()
    inputDOSKeyHead = 0
    inputDOSKeyTail = 0
    inputDOSKeyCount = 0
    inputDOSFrameText = ""
End Sub


Private Sub input_DOSQueueKey(ByRef eventRecord As Const FB.Event)
    If eventRecord.scancode < 0 OrElse eventRecord.scancode > INPUT_KEY_LAST Then Exit Sub
    If inputKeyEventOverflow <> 0 Then Exit Sub
    If inputDOSKeyCount >= INPUT_KEY_EVENT_CAPACITY Then
        ' A truncated chord must not leave a modifier logically pressed.
        ' Refuse this pending batch and report the loss through the public API.
        input_DOSClearKeyQueue
        inputNativeModifiers = INPUT_MODIFIER_NONE
        Erase inputNativeModifierKeys
        inputKeyEventOverflow = -1
        Exit Sub
    End If
    inputDOSKeyQueue(inputDOSKeyTail) = eventRecord
    inputDOSKeyTail += 1
    If inputDOSKeyTail >= INPUT_KEY_EVENT_CAPACITY Then inputDOSKeyTail = 0
    inputDOSKeyCount += 1
End Sub


Private Sub input_DOSReplayKeyFrame()
    Dim As Integer hasText, hasCommand
    While inputDOSKeyCount > 0
        Dim eventRecord As FB.Event = inputDOSKeyQueue(inputDOSKeyHead)
        Dim isPress As Integer = IIf(eventRecord.type = FB.EVENT_KEY_PRESS OrElse eventRecord.type = FB.EVENT_KEY_REPEAT, -1, 0)
        Dim isModifier As Integer = input_ModifierForScanCode(eventRecord.scancode)
        Dim isText As Integer
        If isPress <> 0 AndAlso isModifier = INPUT_MODIFIER_NONE Then
            isText = IIf( _
                eventRecord.ascii >= INPUT_TEXT_ASCII_FIRST AndAlso _
                eventRecord.ascii <= INPUT_TEXT_ASCII_LAST AndAlso _
                (inputNativeModifiers And (INPUT_MODIFIER_CONTROL Or INPUT_MODIFIER_ALT)) = 0, -1, 0)
            If hasCommand <> 0 Then Exit While
            If isText = 0 AndAlso hasText <> 0 Then Exit While
            If isText <> 0 Then hasText = -1 Else hasCommand = -1
        End If

        inputDOSKeyHead += 1
        If inputDOSKeyHead >= INPUT_KEY_EVENT_CAPACITY Then inputDOSKeyHead = 0
        inputDOSKeyCount -= 1
        input_CollectNativeKey eventRecord
        If isText <> 0 AndAlso inputSuppressedKeys(eventRecord.scancode) = 0 Then
            ' At most one byte per queued press can reach this frame.
            If Len(inputDOSFrameText) < INPUT_KEY_EVENT_CAPACITY Then _
                inputDOSFrameText &= Chr(eventRecord.ascii)
        End If
    Wend
End Sub
#endif


Private Function input_CheckTextBoundary( _
    ByRef eventRecord As Const FB.Event _
) As Integer

    If eventRecord.type <> FB.EVENT_KEY_PRESS AndAlso _
       eventRecord.type <> FB.EVENT_KEY_REPEAT Then Return 0

    Dim As Long scanCode = eventRecord.scancode
    Dim As Long characterByte = eventRecord.ascii
    Dim As Integer isBoundary = 0

    If scanCode >= 0 AndAlso scanCode <= INPUT_KEY_LAST Then _
        isBoundary = inputTextBoundaryKeys(scanCode)

    If (inputNativeModifiers And _
        (INPUT_MODIFIER_CONTROL Or INPUT_MODIFIER_ALT)) = 0 Then
        If (characterByte >= INPUT_TEXT_ASCII_FIRST AndAlso _
            characterByte <= INPUT_TEXT_ASCII_LAST) OrElse isBoundary <> 0 Then
            If inputTextBoundaryCharacterCount < _
               INPUT_TEXT_BOUNDARY_CHARACTER_LIMIT Then _
                inputTextBoundaryCharacterCount += 1
        End If
    End If

    Select Case scanCode
    Case KEY_RETURN, KEY_ESCAPE, FB.SC_TAB, KEY_BACKSPACE, KEY_DELETE, _
         KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_HOME, KEY_END, _
         FB.SC_F2, FB.SC_F3, FB.SC_F7, FB.SC_F8, FB.SC_F9, FB.SC_F10, _
         FB.SC_F11
        Return -1
    End Select
    If (inputNativeModifiers And _
        (INPUT_MODIFIER_CONTROL Or INPUT_MODIFIER_ALT)) <> 0 Then Return -1

    Return isBoundary
End Function


Private Sub input_CollectNativeEvents()
    Dim As FB.Event eventRecord
    Dim As Long nativeEventCount = 0

    While nativeEventCount < INPUT_NATIVE_EVENT_CAPACITY AndAlso _
          ScreenEvent(@eventRecord)
        nativeEventCount += 1
        Select Case eventRecord.type
        Case FB.EVENT_MOUSE_MOVE, FB.EVENT_MOUSE_ENTER, FB.EVENT_MOUSE_EXIT, _
             FB.EVENT_MOUSE_BUTTON_PRESS, FB.EVENT_MOUSE_BUTTON_RELEASE, _
             FB.EVENT_MOUSE_DOUBLE_CLICK
        End Select
        Select Case eventRecord.type
        Case FB.EVENT_KEY_PRESS, FB.EVENT_KEY_RELEASE, FB.EVENT_KEY_REPEAT
            #if defined(__FB_DOS__) Or defined(__FB_WII__)
            input_DOSQueueKey eventRecord
            #else
            input_CollectNativeKey eventRecord
            #endif
#Ifdef OMAGUI_ORDERED_TEXT_INPUT
            If (eventRecord.type = FB.EVENT_KEY_PRESS OrElse _
                eventRecord.type = FB.EVENT_KEY_REPEAT) AndAlso _
               useMockKeys = 0 AndAlso useMockText = 0 AndAlso _
               (inputNativeModifiers And _
                (INPUT_MODIFIER_CONTROL Or INPUT_MODIFIER_ALT)) = 0 Then
                If eventRecord.ascii >= INPUT_TEXT_ASCII_FIRST AndAlso _
                   eventRecord.ascii <= &h10FFFF AndAlso eventRecord.ascii <> 127 Then
                    inputOrderedTextBuffer &= _
                        input_EncodeTextByte(CUInt(eventRecord.ascii))
                End If
            End If
#EndIf
#If Defined(OMAGUI_ORDERED_TEXT_INPUT) And Not Defined(__FB_DOS__) And Not Defined(__FB_WII__)
            If input_CheckTextBoundary(eventRecord) <> 0 Then
                inputTextBoundaryReached = -1
                Exit While
            End If
#EndIf
        Case FB.EVENT_MOUSE_MOVE
            inputNativeX = eventRecord.x
            inputNativeY = eventRecord.y
            input_QueuePointerMove inputNativeX, inputNativeY
            inputNativePointerInside = CInt( _
                eventRecord.x >= 0 AndAlso eventRecord.x < inputNativeScreenWidth AndAlso _
                eventRecord.y >= 0 AndAlso eventRecord.y < inputNativeScreenHeight _
            )
            inputNativePointerEventPending = -1
        Case FB.EVENT_MOUSE_ENTER
            inputNativeX = eventRecord.x
            inputNativeY = eventRecord.y
            inputNativePointerInside = -1
            inputNativeMouseResync = -1
            inputNativePointerEventPending = -1
        Case FB.EVENT_MOUSE_EXIT
            inputNativeX = -1
            inputNativeY = -1
            inputNativePointerInside = 0
            inputNativePointerEventPending = -1
        Case FB.EVENT_MOUSE_WHEEL
            inputNativeWheelEventPending = -1
        Case FB.EVENT_MOUSE_BUTTON_PRESS, FB.EVENT_MOUSE_DOUBLE_CLICK
            ' EVENT.button shares storage with EVENT.x/y. Keep the last motion
            ' point instead of interpreting the button mask as a coordinate.
            If inputNativeX < 0 OrElse inputNativeY < 0 Then _
                inputNativeMouseResync = -1
            inputNativeButtons Or= eventRecord.button
            inputNativePointerEventPending = -1
            input_QueuePointerEvent _
                inputNativeX, inputNativeY, inputNativeButtons, _
                CInt(eventRecord.type = FB.EVENT_MOUSE_DOUBLE_CLICK)
        Case FB.EVENT_MOUSE_BUTTON_RELEASE
            ' A release carries a button mask, not a second pointer sample.
            inputNativeButtons And= Not eventRecord.button
            inputNativePointerEventPending = -1
            input_QueuePointerEvent _
                inputNativeX, inputNativeY, inputNativeButtons, 0
        Case FB.EVENT_WINDOW_CLOSE
            inputWindowCloseRequested = -1
        Case FB.EVENT_WINDOW_GOT_FOCUS
            inputWindowFocused = -1
        Case FB.EVENT_WINDOW_LOST_FOCUS
            inputWindowFocused = 0
            #if defined(__FB_DOS__) Or defined(__FB_WII__)
            input_DOSClearKeyQueue
            #endif
            If inputNativeButtons <> 0 Then _
                input_QueuePointerEvent inputNativeX, inputNativeY, 0, 0
            inputNativeButtons = 0
            inputNativeX = -1
            inputNativeY = -1
            inputNativePointerInside = 0
            inputNativePointerEventPending = -1
            inputNativeModifiers = INPUT_MODIFIER_NONE
            Erase inputNativeModifierKeys
            Erase inputNativeKeys
        End Select
    Wend
    #if defined(__FB_DOS__) Or defined(__FB_WII__)
    input_DOSReplayKeyFrame
    #endif
End Sub


Private Function input_PopPointerEvent( _
    ByRef x As Integer, _
    ByRef y As Integer, _
    ByRef buttons As Integer, _
    ByRef doubleClick As Integer _
) As Integer
    If inputPointerEventCount <= 0 Then Return 0

    x = inputPointerEventX(inputPointerEventHead)
    y = inputPointerEventY(inputPointerEventHead)
    buttons = inputPointerEventButtons(inputPointerEventHead)
    doubleClick = inputPointerEventDoubleClick(inputPointerEventHead)
    inputPointerEventHead += 1
    If inputPointerEventHead >= INPUT_POINTER_EVENT_CAPACITY Then _
        inputPointerEventHead = 0
    inputPointerEventCount -= 1
    Return -1
End Function

#if defined(__FB_JS__)
Private Function input_JavaScriptWheel() As Integer
    /'
        The browser gfxlib driver currently returns zero for GetMouse's wheel.
        Keep a canvas-owned counter independent of touch contacts. DOM pixels
        and lines can arrive in fractions, so retain the unused fraction.
        Native targets continue to use the gfxlib counter.
    '/
    Return emscripten_run_script_int( _
        "(function(){var c=Module.canvas;if(!c)return 0;" & _
        "var b=Module.omaGUIWheel;if(!b||b.canvas!==c){" & _
        "if(b)b.canvas.removeEventListener('wheel',b.handler);" & _
        "b={canvas:c,pending:0};b.handler=function(e){" & _
        "if(e.ctrlKey)return;var d=-e.deltaY;" & _
        "if(e.deltaMode===0)d/=100;else if(e.deltaMode===1)d/=3;" & _
        "else if(e.deltaMode!==2)return;" & _
        "if(!Number.isFinite(d))return;" & _
        "b.pending=Math.max(-128,Math.min(128,b.pending+d));" & _
        "if(e.cancelable)e.preventDefault();};" & _
        "c.addEventListener('wheel',b.handler,{passive:false});Module.omaGUIWheel=b;}" & _
        "var n=Math.trunc(b.pending);b.pending-=n;return n;})()" _
    )
End Function

Private Sub input_EnsureJavaScriptTouchBridge()
    If inputJavaScriptTouchBridgeInstalled <> 0 Then Exit Sub

    If Len(inputJavaScriptTouchBridgeScript) = 0 Then
        inputJavaScriptTouchBridgeScript = "(function(){"
        inputJavaScriptTouchBridgeScript &= _
            "var module=(typeof Module!=='undefined')?Module:window.Module;"
        inputJavaScriptTouchBridgeScript &= _
            "var canvas=module&&module.canvas;"
        inputJavaScriptTouchBridgeScript &= _
            "if(!canvas||!canvas.addEventListener)return 0;"
        inputJavaScriptTouchBridgeScript &= _
            "var old=window.__omaGUI_TouchBridge;"
        inputJavaScriptTouchBridgeScript &= _
            "if(old&&old.canvas===canvas&&old.handler&&old.version===2)return 1;"
        inputJavaScriptTouchBridgeScript &= _
            "if(old&&old.canvas&&old.handler){" & _
            "var oldNames=['touchstart','touchmove','touchend','touchcancel'," & _
            "'pointerdown','pointermove','pointerup','pointercancel','lostpointercapture'];" & _
            "for(var j=0;j<oldNames.length;j++)" & _
            "old.canvas.removeEventListener(oldNames[j],old.handler,false);}"
        inputJavaScriptTouchBridgeScript &= _
            "var capacity=" & LTrim(Str(INPUT_TOUCH_CAPACITY)) & ";"
        inputJavaScriptTouchBridgeScript &= _
            "var bridge={canvas:canvas,handler:null,contacts:[],version:2," & _
            "pointerEvents:typeof window.PointerEvent==='function'};"
        ' Pointer Events keep stable pointer IDs; Touch Events support older browsers.
        inputJavaScriptTouchBridgeScript &= _
            "var handler=function(event){"
        inputJavaScriptTouchBridgeScript &= _
            "if(bridge.pointerEvents&&event.pointerType==='mouse')return;"
        inputJavaScriptTouchBridgeScript &= _
            "if(event.cancelable)event.preventDefault();"
        inputJavaScriptTouchBridgeScript &= _
            "var rect=canvas.getBoundingClientRect();"
        inputJavaScriptTouchBridgeScript &= _
            "var width=canvas.width|0;var height=canvas.height|0;"
        inputJavaScriptTouchBridgeScript &= _
            "if(bridge.pointerEvents){" & _
            "var id=event.pointerId|0;var contactIndex=-1;" & _
            "for(var p=0;p<bridge.contacts.length;p++)" & _
            "if(bridge.contacts[p].id===id){contactIndex=p;break;}" & _
            "if(event.type==='pointerdown'&&contactIndex<0&&" & _
            "bridge.contacts.length<capacity){" & _
            "bridge.contacts.push({x:0,y:0,id:id});" & _
            "contactIndex=bridge.contacts.length-1;}" & _
            "if(event.type==='pointerdown'&&canvas.setPointerCapture){" & _
            "try{canvas.setPointerCapture(event.pointerId);}catch(error){}}" & _
            "if(event.type==='pointerup'||event.type==='pointercancel'||" & _
            "event.type==='lostpointercapture'){" & _
            "if(contactIndex>=0)bridge.contacts.splice(contactIndex,1);return;}" & _
            "if(contactIndex<0||!(width>0&&height>0&&" & _
            "rect.width>0&&rect.height>0))return;" & _
            "var x=Math.floor((event.clientX-rect.left)*width/rect.width);" & _
            "var y=Math.floor((event.clientY-rect.top)*height/rect.height);" & _
            "if(!isFinite(x)||!isFinite(y))return;" & _
            "if(x<0)x=0;if(x>=width)x=width-1;" & _
            "if(y<0)y=0;if(y>=height)y=height-1;" & _
            "bridge.contacts[contactIndex].x=x;" & _
            "bridge.contacts[contactIndex].y=y;return;}"
        inputJavaScriptTouchBridgeScript &= _
            "var touches=event.touches||[];" & _
            "var count=(width>0&&height>0&&rect.width>0&&" & _
            "rect.height>0)?Math.min(touches.length,capacity):0;"
        inputJavaScriptTouchBridgeScript &= "var contacts=[];"
        inputJavaScriptTouchBridgeScript &= _
            "for(var i=0;i<count;i++){var touch=touches[i];" & _
            "var x=Math.floor((touch.clientX-rect.left)*width/rect.width);" & _
            "var y=Math.floor((touch.clientY-rect.top)*height/rect.height);"
        inputJavaScriptTouchBridgeScript &= _
            "if(x<0)x=0;if(x>=width)x=width-1;" & _
            "if(y<0)y=0;if(y>=height)y=height-1;"
        inputJavaScriptTouchBridgeScript &= _
            "contacts.push({x:x,y:y,id:touch.identifier|0});}"
        inputJavaScriptTouchBridgeScript &= _
            "bridge.contacts=contacts;};bridge.handler=handler;"
        inputJavaScriptTouchBridgeScript &= _
            "var names=bridge.pointerEvents?" & _
            "['pointerdown','pointermove','pointerup','pointercancel','lostpointercapture']:" & _
            "['touchstart','touchmove','touchend','touchcancel'];"
        inputJavaScriptTouchBridgeScript &= _
            "if(canvas.style)canvas.style.touchAction='none';"
        inputJavaScriptTouchBridgeScript &= _
            "for(var i=0;i<names.length;i++){try{" & _
            "canvas.addEventListener(names[i],handler,{passive:false});" & _
            "}catch(error){canvas.addEventListener(names[i],handler,false);}}"
        inputJavaScriptTouchBridgeScript &= _
            "window.__omaGUI_TouchBridge=bridge;return 1;})()"
    End If

    If emscripten_run_script_int( _
        StrPtr(inputJavaScriptTouchBridgeScript) _
    ) <> 0 Then
        inputJavaScriptTouchBridgeInstalled = -1
        inputJavaScriptTouchCountScript = _
            "(window.__omaGUI_TouchBridge&&" & _
            "window.__omaGUI_TouchBridge.contacts.length)|0"

        For contactIndex As Integer = 0 To INPUT_TOUCH_CAPACITY - 1
            Dim As String contactIndexText = LTrim(Str(contactIndex))
            Dim As String contactExpression = _
                "window.__omaGUI_TouchBridge.contacts[" & _
                contactIndexText & "]"
            Dim As Integer queryIndex = contactIndex * 3

            inputJavaScriptTouchQueries(queryIndex) = _
                "(function(){var p=" & contactExpression & ";" & _
                "return p?(p.x|0):0;})()"
            inputJavaScriptTouchQueries(queryIndex + 1) = _
                "(function(){var p=" & contactExpression & ";" & _
                "return p?(p.y|0):0;})()"
            inputJavaScriptTouchQueries(queryIndex + 2) = _
                "(function(){var p=" & contactExpression & ";" & _
                "return p?(p.id|0):0;})()"
        Next contactIndex
    End If
End Sub
#endif

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

#if defined(__FB_JS__)
    input_EnsureJavaScriptTouchBridge
#endif

#if defined(__FB_JS__)
    ' Pointer Events and gfxlib Touch Events use different contact IDs. Keep
    ' one source for the entire browser gesture, including its first frame.
    ' The canvas bridge also works with SDKs that omit native touch callbacks.
    If inputJavaScriptTouchBridgeInstalled <> 0 Then
        Dim As Integer bridgeCount = emscripten_run_script_int( _
            StrPtr(inputJavaScriptTouchCountScript) _
        )
        If bridgeCount < 0 Then bridgeCount = 0
        If bridgeCount > INPUT_TOUCH_CAPACITY Then _
            bridgeCount = INPUT_TOUCH_CAPACITY

        For contactIndex As Integer = 0 To bridgeCount - 1
            Dim As Integer queryIndex = contactIndex * 3
            inputTouchX(contactIndex) = emscripten_run_script_int( _
                StrPtr(inputJavaScriptTouchQueries(queryIndex)) _
            )
            inputTouchY(contactIndex) = emscripten_run_script_int( _
                StrPtr(inputJavaScriptTouchQueries(queryIndex + 1)) _
            )
            inputTouchId(contactIndex) = emscripten_run_script_int( _
                StrPtr(inputJavaScriptTouchQueries(queryIndex + 2)) _
            )
            inputTouchContactCount += 1
        Next
        Exit Sub
    End If
#endif

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
        A second contact waits until all fingers lift instead of taking over.
    '/
    If inputNativeTouchOwner <> 0 Then
        If inputTouchContactCount > 0 Then
            ' A gap between native events is still the same held gesture.
            ' Retain its last native sample even when GetMouse is unavailable.
            mX = inputNativeX
            mY = inputNativeY
            mButtons = inputNativeButtons
            Exit Sub
        End If
        inputNativeTouchOwner = 0
    End If

    If inputTouchPointerSuppressed <> 0 Then
        If inputTouchContactCount > 0 Then
            mX = inputTouchPointerX
            mY = inputTouchPointerY
            mButtons And= Not 1
            Exit Sub
        End If
        inputTouchPointerSuppressed = 0
    End If

    If inputTouchContactCount > 0 Then
        Dim As Integer pointerContactIndex = -1
        If inputTouchPointerActive = 0 Then
            pointerContactIndex = 0
        Else
            For contactIndex As Integer = 0 To inputTouchContactCount - 1
                If inputTouchId(contactIndex) = inputTouchPointerId Then
                    pointerContactIndex = contactIndex
                    Exit For
                End If
            Next
        End If

        If pointerContactIndex < 0 Then
            mX = inputTouchPointerX
            mY = inputTouchPointerY
            mButtons And= Not 1
            inputTouchPointerActive = 0
            inputTouchPointerId = -1
            inputTouchPointerSuppressed = -1
            Exit Sub
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

/'
    Compare the current sample with the last published input frame. The IDE
    uses this to avoid transmitting unchanged screens while the normal GUI
    update continues polling, dispatching queued transitions, and timers.
'/
Private Sub input_UpdateFrameActivity()
    Dim As UInteger activityFlags

    If inputActivitySnapshotValid = 0 Then
        activityFlags Or= INPUT_ACTIVITY_INITIAL
    Else
        If mX <> inputActivityMouseX OrElse mY <> inputActivityMouseY Then _
            activityFlags Or= INPUT_ACTIVITY_POINTER_MOTION
        If mButtons <> inputActivityMouseButtons Then _
            activityFlags Or= INPUT_ACTIVITY_MOUSE_BUTTONS
        If mWheelDelta <> 0 Then _
            activityFlags Or= INPUT_ACTIVITY_MOUSE_WHEEL
    End If

    If inputKeyEventLength > 0 OrElse inputKeyEventOverflow <> 0 Then _
        activityFlags Or= INPUT_ACTIVITY_KEYBOARD
    If Len(textBuffer) > 0 Then activityFlags Or= INPUT_ACTIVITY_TEXT
    If inputWindowCloseRequested <> 0 Then _
        activityFlags Or= INPUT_ACTIVITY_WINDOW_CLOSE

    For keyIndex As Integer = 0 To INPUT_KEY_LAST
        Dim As Integer pressed = IIf(inputEffectiveKeyPressed(keyIndex) <> 0, -1, 0)
        If pressed <> inputActivityKeys(keyIndex) OrElse _
           inputKeyPressEvents(keyIndex) <> 0 Then _
            activityFlags Or= INPUT_ACTIVITY_KEYBOARD
        inputActivityKeys(keyIndex) = pressed
    Next keyIndex

    If inputTouchContactCount <> inputActivityTouchCount Then _
        activityFlags Or= INPUT_ACTIVITY_TOUCH
    For contactIndex As Integer = 0 To INPUT_TOUCH_CAPACITY - 1
        If contactIndex < inputTouchContactCount Then
            If inputActivitySnapshotValid = 0 OrElse _
               contactIndex >= inputActivityTouchCount OrElse _
               inputTouchX(contactIndex) <> inputActivityTouchX(contactIndex) OrElse _
               inputTouchY(contactIndex) <> inputActivityTouchY(contactIndex) OrElse _
               inputTouchId(contactIndex) <> inputActivityTouchId(contactIndex) Then _
                activityFlags Or= INPUT_ACTIVITY_TOUCH
            inputActivityTouchX(contactIndex) = inputTouchX(contactIndex)
            inputActivityTouchY(contactIndex) = inputTouchY(contactIndex)
            inputActivityTouchId(contactIndex) = inputTouchId(contactIndex)
        Else
            inputActivityTouchX(contactIndex) = 0
            inputActivityTouchY(contactIndex) = 0
            inputActivityTouchId(contactIndex) = -1
        End If
    Next contactIndex

    inputActivityMouseX = mX
    inputActivityMouseY = mY
    inputActivityMouseButtons = mButtons
    inputActivityTouchCount = inputTouchContactCount
    inputActivitySnapshotValid = -1
    inputFrameActivityFlags = activityFlags
    inputFrameActivity = IIf(activityFlags <> 0, -1, 0)
End Sub


Sub input_Update()
    input_AdvanceFrameSerial
    Dim As Long MouseStatus
    Dim As Integer currentWheelPosition
    Dim As Integer polledMouseX, polledMouseY, polledMouseButtons
    Dim As Integer mockModifiers
    Dim As Integer replayedPointerEvent
    Dim As String KeyText

    pointerDispatchEnabled = -1
    keyboardDispatchEnabled = -1
    inputKeyEventLength = 0
    inputKeyEventOverflow = 0
#if defined(__FB_LINUX__) and not defined(__FB_JS__)
    inputNativeTextLength = 0
#endif
    inputKeyBatchActive = -1
    #if defined(__FB_DOS__) Or defined(__FB_WII__)
    inputDOSFrameText = ""
    #endif
    inputTextBoundaryReached = 0
    inputTextBoundaryCharacterCount = 0
    inputOrderedTextBuffer = ""
    mDoubleClick = 0

    For keyIndex As Integer = 0 To INPUT_KEY_LAST
        inputKeyPressEvents(keyIndex) = 0
        inputKeyPressChords(keyIndex) = 0
    Next keyIndex

    If useMockMouse Then
        mX = mockX
        mY = mockY
        mButtons = mockButtons
        mWheelDelta = mockWheelDelta
        mDoubleClick = 0
        mockWheelDelta = 0
    Else
        ' ScreenEvent reports pointer motion and button transitions. Poll a
        ' stationary pointer only while no native button is held. Some gfxlib
        ' drivers return a stale zero button mask from GetMouse after a press;
        ' that snapshot must not erase the event-derived held state.
        mWheelDelta = 0
        inputNativePointerEventPending = 0
        inputNativeWheelEventPending = 0
        Dim As Integer pollNativeMouse
#Ifdef __FB_GFXLIB3__
        pollNativeMouse = (inputNativeButtonsInitialized = 0 OrElse _
            inputNativeMouseResync <> 0)
#Else
        ' GFX2 still needs the current mouse snapshot to keep pointer
        ' coordinates aligned with the visible framebuffer.
        pollNativeMouse = (inputNativeButtonsInitialized = 0 OrElse _
            (inputNativePointerInside <> 0 AndAlso inputPointerEventCount = 0 AndAlso _
             inputNativeButtons = 0))
#EndIf
        Dim As Integer nativeMousePollSkipped = (pollNativeMouse = 0)
        If pollNativeMouse <> 0 Then
            If inputNativeButtonsInitialized = 0 Then
                Dim As Integer screenDepth
                ScreenInfo inputNativeScreenWidth, inputNativeScreenHeight, screenDepth
            End If
            MouseStatus = GetMouse( _
                polledMouseX, polledMouseY, currentWheelPosition, polledMouseButtons _
            )
            If MouseStatus = 0 Then
                mX = polledMouseX
                mY = polledMouseY
                mButtons = polledMouseButtons
                inputNativeX = polledMouseX
                inputNativeY = polledMouseY
                inputNativeButtons = polledMouseButtons
                If inputNativeMouseResync <> 0 AndAlso _
                   inputNativeWheelEventPending = 0 Then
                    previousWheelPosition = currentWheelPosition
                    wheelPositionInitialized = -1
                End If
                If inputNativeButtonsInitialized = 0 Then
                    inputNativePointerInside = CInt( _
                        polledMouseX >= 0 AndAlso _
                        polledMouseX < inputNativeScreenWidth AndAlso _
                        polledMouseY >= 0 AndAlso _
                        polledMouseY < inputNativeScreenHeight _
                    )
                    previousWheelPosition = currentWheelPosition
                    wheelPositionInitialized = -1
                End If
                inputNativeMouseResync = 0
            Else
                inputNativeButtons = 0
                inputNativeX = -1
                inputNativeY = -1
            End If
            inputNativeButtonsInitialized = -1
        Else
            ' Event records already carry button state and pointer location.
            ' MouseStatus selects that path below without an outside query.
            MouseStatus = 1
            polledMouseX = inputNativeX
            polledMouseY = inputNativeY
            polledMouseButtons = inputNativeButtons
        End If
        input_CollectNativeEvents
#If Defined(OMAGUI_CLIPBOARD_BROWSER)
        /'
            SDL can lose a complete clipboard chord between browser frames.
            The clipboard bridge captures only canvas-owned C/X/V commands
            and stops their SDL delivery, so each enters this ordered queue
            exactly once. Packed records use bits 0..7 for gfxlib's scan code
            and bits 8..10 for INPUT_MODIFIER flags. A command has no text byte.
            Sixty-four browser records fit as 128 transitions in our 256 slots.
        '/
        If useMockKeys = 0 Then
            Dim As Long browserKey
            For browserIndex As Integer = 1 To 64
                browserKey = emscripten_run_script_int( _
                    "Module.omaGUIClipboard?Module.omaGUIClipboard.nextKey():0" _
                )
                If browserKey = 0 Then Exit For
                input_RecordKeyEvent INPUT_KEY_EVENT_PRESS, browserKey And 255, 0, (browserKey Shr 8) And 7
                input_RecordKeyEvent INPUT_KEY_EVENT_RELEASE, browserKey And 255, 0, (browserKey Shr 8) And 7
            Next browserIndex
            If emscripten_run_script_int( _
                "(function(){var b=Module.omaGUIClipboard;if(!b)return 0;var v=b.overflow;b.overflow=false;return v?1:0;})()" _
            ) Then inputKeyEventOverflow = -1
        End If
#EndIf
        ' ScreenEvent may add the wheel after the pre-frame sample. Refresh
        ' only for that edge so the first tick is visible without restoring the
        ' idle outside-window query on every frame.
        If inputNativeWheelEventPending <> 0 Then
            MouseStatus = GetMouse( _
                polledMouseX, polledMouseY, currentWheelPosition, polledMouseButtons _
            )
            If MouseStatus = 0 Then
                inputNativeX = polledMouseX
                inputNativeY = polledMouseY
                inputNativeButtons = polledMouseButtons
                inputNativeMouseResync = 0
            End If
        End If
        If MouseStatus = 0 Then
            If wheelPositionInitialized <> 0 Then
                ' The pre-event GetMouse sample may already include a notch.
                ' A second sample after ScreenEvent must add newer movement,
                ' not replace that delta with zero.
                mWheelDelta += currentWheelPosition - previousWheelPosition
            Else
                wheelPositionInitialized = -1
            End If
            previousWheelPosition = currentWheelPosition
        Else
            If nativeMousePollSkipped = 0 Then wheelPositionInitialized = 0
        End If
        #if defined(__FB_JS__)
        ' One source avoids counting the same event again if SDL gains wheel support.
        mWheelDelta = input_JavaScriptWheel()
        #endif
        ' A pointer sample taken before ScreenEvent can predate a queued edge.
        ' Keep event-derived state until every recorded transition is replayed.
        If MouseStatus = 0 AndAlso inputNativePointerEventPending = 0 AndAlso _
           inputPointerEventCount = 0 Then
            mX = polledMouseX
            mY = polledMouseY
            mButtons = polledMouseButtons
            inputNativeX = mX
            inputNativeY = mY
            inputNativeButtons = mButtons
            inputPointerEventHead = 0
            inputPointerEventTail = 0
            inputPointerEventCount = 0
            replayedPointerEvent = 0
        Else
            If inputNativePointerEventPending <> 0 OrElse _
               inputNativeButtons <> 0 OrElse inputNativePointerInside <> 0 Then
                mX = inputNativeX
                mY = inputNativeY
            Else
                mX = -1
                mY = -1
            End If
            mButtons = inputNativeButtons
            replayedPointerEvent = input_PopPointerEvent( _
                mX, mY, mButtons, mDoubleClick _
            )
        End If
        If replayedPointerEvent = 0 AndAlso MouseStatus <> 0 Then
            inputNativeButtons = mButtons
            inputNativeX = mX
            inputNativeY = mY
        End If
    End If


    ' Touch remains visible to gesture code and also drives old mouse widgets.
    input_CollectTouchContacts
    #if defined(__FB_JS__)
    ' SDL's compatibility press can retain the previous mouse location while
    ' the browser has already delivered accurate contact coordinates. Preserve
    ' its ordered button edge, but hit-test that edge at the active contact.
    ' Touch owns the single compatibility pointer until all contacts end.
    If replayedPointerEvent <> 0 AndAlso inputTouchContactCount > 0 Then
        mX = inputTouchX(0): mY = inputTouchY(0)
        inputNativeX = mX: inputNativeY = mY
    End If
    #endif
    ' Some drivers expose the mouse as a touch contact too. Its latest sampled
    ' release must not erase an older queued press being replayed this frame.
    ' Gesture callers still receive all contacts; native pointer edges own the
    ' compatibility pointer until every matching contact has ended.
    If replayedPointerEvent = 0 Then
        input_ApplyTouchCompatibilityPointer
    Else
        inputTouchPointerActive = 0
        inputTouchPointerId = -1
        inputTouchPointerSuppressed = 0
        If inputTouchContactCount > 0 Then inputNativeTouchOwner = -1
    End If

    If useMockMouse = 0 Then input_MapPhysicalPoint mX, mY
    If useMockTouch = 0 Then
        For contactIndex As Integer = 0 To inputTouchContactCount - 1
            input_MapPhysicalPoint inputTouchX(contactIndex), inputTouchY(contactIndex)
        Next
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
        mDoubleClick = 0
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
           inputKeyOverrideTarget(keyIndex) = 0 AndAlso keyIndex <> KEY_RETURN AndAlso _
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
        input_UpdateFrameActivity
        Exit Sub
    End If

    #if defined(OMAGUI_ORDERED_TEXT_INPUT) And Not defined(__FB_DOS__) And Not defined(__FB_WII__) And Not defined(__FB_JS__)
    textBuffer = IIf(inputSuppressText, "", inputOrderedTextBuffer)
    For legacyIndex As Integer = 1 To INPUT_NATIVE_EVENT_CAPACITY
        If Len(Inkey) = 0 Then Exit For
    Next legacyIndex
    #elseif defined(__FB_DOS__) Or defined(__FB_WII__)
    textBuffer = IIf(inputSuppressText, "", inputDOSFrameText)
    ' The native records supply console text. Drain the separate legacy ring so
    ' old bytes cannot reappear after a later focus or display handoff.
    For legacy_index As Integer = 1 To INPUT_KEY_EVENT_CAPACITY
        If Len(Inkey) = 0 Then Exit For
    Next legacy_index
    #else
    ' Browser gfxlib keeps typed bytes in the legacy Inkey ring. ScreenEvent
    ' owns command edges, so this text path must remain available separately.
    textBuffer = ""
#if defined(__FB_LINUX__) and not defined(__FB_JS__)
    If inputNativeUseEventText <> 0 Then
        textBuffer = IIf(inputSuppressText, "", input_NativeUnicodeFrameText())
        For legacy_index As Integer = 1 To INPUT_NATIVE_EVENT_CAPACITY
            If Len(Inkey) = 0 Then Exit For
        Next legacy_index
    Else
#endif
        Dim As Long textCharactersRead = 0
    If inputTextBoundaryReached = 0 OrElse _
       inputTextBoundaryCharacterCount > 0 Then KeyText = Inkey

    While KeyText <> ""
        If Len(KeyText) = INPUT_TEXT_BYTE_COUNT Then
            If KeyText[INPUT_TEXT_BYTE_INDEX] >= INPUT_TEXT_ASCII_FIRST And _
               KeyText[INPUT_TEXT_BYTE_INDEX] <= INPUT_TEXT_ASCII_LAST Then
                If inputSuppressText = 0 Then textBuffer &= KeyText
                textCharactersRead += 1
            End If
        End If

        If inputTextBoundaryReached <> 0 AndAlso _
           textCharactersRead >= inputTextBoundaryCharacterCount Then Exit While
        KeyText = Inkey
    Wend
#if defined(__FB_LINUX__) and not defined(__FB_JS__)
    End If
#endif
    #endif
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
    input_NavigationUpdate
#endif
    input_UpdateFrameActivity
End Sub


Function input_FrameActivity() As Integer
    Return inputFrameActivity
End Function

Function input_FrameActivityFlags() As UInteger
    Return inputFrameActivityFlags
End Function

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

Sub input_GetPointerPosition(ByRef x As Integer, ByRef y As Integer)
    ' The sampled coordinates are independent of dispatch ownership so an
    ' application can render a cursor while a modal widget masks input.
    x = mX
    y = mY
End Sub

Function input_UnmaskedMouseX() As Integer
    Return mX
End Function

Function input_UnmaskedMouseY() As Integer
    Return mY
End Function

Function input_MouseButtons() As Integer
    If pointerDispatchEnabled = 0 Then Return 0
    Return mButtons
End Function

Function input_MouseDoubleClick() As Integer
    If pointerDispatchEnabled = 0 Then Return 0
    Return mDoubleClick
End Function

Function input_UnmaskedMouseButtons() As Integer
    Return mButtons
End Function


Function input_MouseWheel() As Integer
    If pointerDispatchEnabled = 0 Then Return 0
    Return mWheelDelta
End Function

Function input_UpdateVerticalScrollGesture( _
    ByRef gesture As InputVerticalScrollGesture, _
    ByVal viewportX As Integer, ByVal viewportY As Integer, _
    ByVal viewportWidth As Integer, ByVal viewportHeight As Integer, _
    ByRef scrollPosition As Integer, ByVal maximumScroll As Integer, _
    ByVal dragThreshold As Integer _
) As Integer
    Dim As Integer pointerX, pointerY, pointerButtons
    Dim As Integer maximum, threshold
    Dim As Integer touchCount, touchIndex, touchX, touchY, touchId
    Dim As Integer foundTouch, draggedBeforeReset
    Dim As LongInt deltaY, distanceY, nextScroll

    maximum = maximumScroll
    If maximum < 0 Then maximum = 0
    If viewportWidth <= 0 OrElse viewportHeight <= 0 OrElse maximum = 0 Then
        draggedBeforeReset = gesture.dragging
        input_ResetVerticalScrollGesture gesture
        Return IIf(draggedBeforeReset <> 0, -1, 0)
    End If

    If gesture.tracking = 0 Then
        touchCount = input_TouchCount()
        If gesture.touch_blocked <> 0 Then
            If touchCount > 0 Then Return 0
            gesture.touch_blocked = 0
        End If

        For touchIndex = 0 To touchCount - 1
            If input_Touch(touchIndex, touchX, touchY, touchId) <> 0 Then
                If CLngInt(touchX) >= CLngInt(viewportX) AndAlso _
                   CLngInt(touchX) < CLngInt(viewportX) + CLngInt(viewportWidth) AndAlso _
                   CLngInt(touchY) >= CLngInt(viewportY) AndAlso _
                   CLngInt(touchY) < CLngInt(viewportY) + CLngInt(viewportHeight) Then
                    gesture.tracking = -1
                    gesture.dragging = 0
                    gesture.source = INPUT_SCROLL_SOURCE_TOUCH
                    gesture.touch_id = touchId
                    gesture.origin_y = touchY
                    If scrollPosition < 0 Then scrollPosition = 0
                    If scrollPosition > maximum Then scrollPosition = maximum
                    gesture.origin_scroll = scrollPosition
                    Return 0
                End If
            End If
        Next touchIndex

        pointerX = input_MouseX()
        pointerY = input_MouseY()
        pointerButtons = input_MouseButtons()
        If (pointerButtons And 1) = 0 Then Return 0
        If CLngInt(pointerX) < CLngInt(viewportX) OrElse _
           CLngInt(pointerX) >= CLngInt(viewportX) + CLngInt(viewportWidth) OrElse _
           CLngInt(pointerY) < CLngInt(viewportY) OrElse _
           CLngInt(pointerY) >= CLngInt(viewportY) + CLngInt(viewportHeight) Then Return 0

        gesture.tracking = -1
        gesture.dragging = 0
        gesture.source = INPUT_SCROLL_SOURCE_MOUSE
        gesture.touch_id = -1
        gesture.origin_y = pointerY
        If scrollPosition < 0 Then scrollPosition = 0
        If scrollPosition > maximum Then scrollPosition = maximum
        gesture.origin_scroll = scrollPosition
        Return 0
    End If

    If gesture.source = INPUT_SCROLL_SOURCE_TOUCH Then
        touchCount = input_TouchCount()
        foundTouch = 0
        For touchIndex = 0 To touchCount - 1
            If input_Touch(touchIndex, touchX, touchY, touchId) <> 0 AndAlso _
               touchId = gesture.touch_id Then
                foundTouch = -1
                Exit For
            End If
        Next touchIndex

        If foundTouch = 0 Then
            draggedBeforeReset = gesture.dragging
            input_ResetVerticalScrollGesture gesture
            If touchCount > 0 Then gesture.touch_blocked = -1
            Return IIf(draggedBeforeReset <> 0, -1, 0)
        End If
        pointerY = touchY
    ElseIf gesture.source = INPUT_SCROLL_SOURCE_MOUSE Then
        pointerButtons = input_MouseButtons()
        If (pointerButtons And 1) = 0 Then
            draggedBeforeReset = gesture.dragging
            input_ResetVerticalScrollGesture gesture
            Return IIf(draggedBeforeReset <> 0, -1, 0)
        End If
        pointerY = input_MouseY()
    Else
        input_ResetVerticalScrollGesture gesture
        Return 0
    End If

    threshold = dragThreshold
    If threshold <= 0 Then threshold = INPUT_SCROLL_GESTURE_THRESHOLD
    deltaY = CLngInt(pointerY) - CLngInt(gesture.origin_y)
    If gesture.dragging = 0 Then
        distanceY = Abs(deltaY)
        If distanceY < threshold Then Return 0
        gesture.dragging = -1
    End If

    ' Moving the finger up advances the document; clamp before narrowing back
    ' to the public gfxlib coordinate-sized Integer type.
    nextScroll = CLngInt(gesture.origin_scroll) - deltaY
    If nextScroll < 0 Then nextScroll = 0
    If nextScroll > maximum Then nextScroll = maximum
    scrollPosition = CInt(nextScroll)
    Return -1
End Function

Sub input_ApplyVerticalScrollDelta( _
    ByRef gesture As InputVerticalScrollGesture, _
    ByRef scrollPosition As Integer, _
    ByVal scrollDelta As LongInt, _
    ByVal maximumScroll As Integer _
)
    Dim As LongInt maximum, nextScroll

    maximum = maximumScroll
    If maximum < 0 Then maximum = 0

    nextScroll = CLngInt(scrollPosition) + scrollDelta
    If nextScroll < 0 Then nextScroll = 0
    If nextScroll > maximum Then nextScroll = maximum
    scrollPosition = CInt(nextScroll)

    If gesture.tracking <> 0 Then
        ' Keep an active finger or pointer drag anchored after a wheel step.
        nextScroll = CLngInt(gesture.origin_scroll) + scrollDelta
        If nextScroll < 0 Then nextScroll = 0
        If nextScroll > maximum Then nextScroll = maximum
        gesture.origin_scroll = CInt(nextScroll)
    End If
End Sub

Sub input_ResetVerticalScrollGesture( _
    ByRef gesture As InputVerticalScrollGesture _
)
    gesture.tracking = 0
    gesture.dragging = 0
    gesture.origin_y = 0
    gesture.origin_scroll = 0
    gesture.source = INPUT_SCROLL_SOURCE_NONE
    gesture.touch_id = -1
    gesture.touch_blocked = 0
End Sub

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


Function input_KeyRepeatEvent(ByVal k As Integer) As Integer
    If k <= 0 OrElse k > INPUT_KEY_LAST Then Return 0
    If keyboardDispatchEnabled = 0 Then Return 0
    ' Use the same mapping as held keys and press edges. A KeyDown handler
    ' can cancel or redirect an editor repeat without altering raw KeyUp data.
    For eventIndex As Long = 0 To inputKeyEventLength - 1
        If inputKeyEvents(eventIndex).event_kind <> INPUT_KEY_EVENT_REPEAT Then _
            Continue For
        If input_MappedScanCode(inputKeyEvents(eventIndex).scan_code) = k Then _
            Return -1
    Next eventIndex
    Return 0
End Function


Function input_ConsumeKeyPressEvent(ByVal scanCode As Integer) As Integer
    If scanCode < 1 OrElse scanCode > INPUT_KEY_LAST Then Return 0
    ' Consume source edges behind the mapped view, so a later mapping rebuild
    ' cannot resurrect this action. Raw ordered notifications still describe
    ' the physical press/repeat and eventual release for event subscribers.
    For sourceCode As Integer = 0 To INPUT_KEY_LAST
        If input_MappedScanCode(sourceCode) <> scanCode Then Continue For
        inputKeyPressEvents(sourceCode) = 0
        inputKeyPressChords(sourceCode) = 0
    Next sourceCode
    input_RebuildKeyView
    Return -1
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
        ' Return has no printable byte. Consuming its editor command must
        ' preserve characters collected in the same frame, including a chat
        ' message's final character immediately before Enter.
        If targetScanCode = 0 Then
            If sourceScanCode = KEY_RETURN Then
                ' Cancel the Return control byte without losing adjacent text.
                Dim As String filteredText = Space(Len(textBuffer))
                Dim As Integer outputLength = 0
                For byteIndex As Integer = 0 To Len(textBuffer) - 1
                    If textBuffer[byteIndex] = 13 Then Continue For
                    filteredText[outputLength] = textBuffer[byteIndex]
                    outputLength += 1
                Next byteIndex
                textBuffer = Left(filteredText, outputLength)
            Else
                inputSuppressText = -1
                textBuffer = ""
            End If
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


Sub input_SetTextBoundaryKey(ByVal scanCode As Integer, ByVal enabled As Integer)
    If scanCode < 0 OrElse scanCode > INPUT_KEY_LAST Then Exit Sub
    inputTextBoundaryKeys(scanCode) = IIf(enabled <> 0, -1, 0)
End Sub


Function input_TakeWindowCloseRequested() As Integer
    Dim As Integer requested

    requested = inputWindowCloseRequested
    inputWindowCloseRequested = 0
    Return requested
End Function


Function input_WindowHasFocus() As Integer
    Return inputWindowFocused
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
    #if defined(__FB_DOS__) Or defined(__FB_WII__)
    input_DOSClearKeyQueue
    #endif
    input_AdvanceFrameSerial
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
    input_NavigationReset
#endif
    input_ClearLogicalViewport
    inputKeyBatchActive = 0
    inputFrameActivity = 0
    inputFrameActivityFlags = 0
    inputActivitySnapshotValid = 0
    inputOrderedTextBuffer = ""
    inputTextBoundaryReached = 0
    inputTextBoundaryCharacterCount = 0
    ' A test reset owns every input source. Native mouse-as-touch contacts
    ' must not override mocked coordinates on targets such as Haiku.
    useMockTouch = 1
    mockTouchContactCount = 0
    inputTouchContactCount = 0
    inputTouchPointerActive = 0
    inputTouchPointerId = -1
    inputTouchPointerSuppressed = 0
    inputNativeTouchOwner = 0
    inputKeyEventLength = 0
    mockKeyEventLength = 0
    inputKeyEventOverflow = 0
    mockKeyEventOverflow = 0
#if defined(__FB_LINUX__) and not defined(__FB_JS__)
    inputNativeTextLength = 0
    inputNativeUseEventText = 0
#endif
    Erase inputNativeModifierKeys
    Erase inputNativeKeys
    inputSuppressButtons = 0
    inputSuppressText = 0
    mX = 0
    mY = 0
    mWheelDelta = 0
    mButtons = 0
    mDoubleClick = 0
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
    inputNativePointerInside = 0
    inputNativeScreenWidth = 0
    inputNativeScreenHeight = 0
    inputNativeX = 0
    inputNativeY = 0
    inputNativeMouseResync = 0
    inputNativePointerEventPending = 0
    inputNativeWheelEventPending = 0
    inputWindowCloseRequested = 0
    inputWindowFocused = -1
    inputNativeModifiers = INPUT_MODIFIER_NONE

    For keyIndex As Integer = 0 To INPUT_KEY_LAST
        mockKeys(keyIndex) = 0
        inputTextBoundaryKeys(keyIndex) = 0
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
    #if defined(__FB_DOS__) Or defined(__FB_WII__)
    input_DOSClearKeyQueue
    #endif
    input_AdvanceFrameSerial
    inputTouchContactCount = 0
    inputTouchPointerActive = 0
    inputTouchPointerId = -1
    inputTouchPointerSuppressed = 0
    inputNativeTouchOwner = 0
    inputFrameActivity = 0
    inputFrameActivityFlags = 0
    inputActivitySnapshotValid = 0
    Const MAX_DISCARDED_EVENTS As Integer = 1024 ' Bound a concurrent native event producer.
    Dim As FB.Event event_value
    inputKeyEventLength = 0
    mockKeyEventLength = 0
    inputKeyEventOverflow = 0
    mockKeyEventOverflow = 0
#if defined(__FB_LINUX__) and not defined(__FB_JS__)
    inputNativeTextLength = 0
    inputNativeUseEventText = 0
#endif
    Erase inputNativeModifierKeys
    Erase inputNativeKeys
    mButtons = 0
    mDoubleClick = 0
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
    inputNativePointerInside = 0
    inputNativeScreenWidth = 0
    inputNativeScreenHeight = 0
    inputNativeMouseResync = 0
    inputNativePointerEventPending = 0
    inputNativeWheelEventPending = 0
    inputNativeModifiers = INPUT_MODIFIER_NONE
    inputWindowCloseRequested = 0
    inputWindowFocused = -1
    pointerDispatchEnabled = -1
    keyboardDispatchEnabled = -1
    inputSuppressButtons = -1
    inputSuppressText = 0
    If ScreenPtr <> 0 Then
        For event_index As Integer = 1 To MAX_DISCARDED_EVENTS
            If ScreenEvent(@event_value) = 0 Then Exit For
            ' A close request on the new window still belongs to the owner.
            Select Case event_value.type
            Case FB.EVENT_WINDOW_CLOSE
                inputWindowCloseRequested = -1
            Case FB.EVENT_WINDOW_GOT_FOCUS
                inputWindowFocused = -1
            Case FB.EVENT_WINDOW_LOST_FOCUS
                inputWindowFocused = 0
            End Select
        Next event_index
        If useMockText = 0 Then
            ' This counted drain is bounded even if the producer keeps supplying text.
            For key_index As Integer = 1 To MAX_DISCARDED_EVENTS
                If Len(Inkey) = 0 Then Exit For
            Next key_index
        End If
    End If
    For keyIndex As Integer = 0 To INPUT_KEY_LAST
        inputKeyPressEvents(keyIndex) = 0
        inputKeyPressChords(keyIndex) = 0
        mockPreviousKeys(keyIndex) = mockKeys(keyIndex)
        ' Screen replacement discards native events. Sample held keys once at
        ' this boundary so a later repeat cannot bypass release suppression.
        If useMockKeys = 0 AndAlso ScreenPtr <> 0 Then _
            inputNativeKeys(keyIndex) = IIf(MultiKey(keyIndex) <> 0, -1, 0)
        inputSuppressedKeys(keyIndex) = input_RawKeyPressed(keyIndex)
        inputKeyOverrideActive(keyIndex) = 0
        inputKeyOverrideTarget(keyIndex) = 0
        inputEffectiveKeyPressed(keyIndex) = 0
        inputEffectiveKeyPressEvents(keyIndex) = 0
        inputEffectiveKeyPressChords(keyIndex) = 0
    Next keyIndex
End Sub

' end of input_gfxlib.bas
