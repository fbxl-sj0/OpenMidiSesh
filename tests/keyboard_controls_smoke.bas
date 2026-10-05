/'
    Project: OpenSesh
    ---------------------------

    File: tests/keyboard_controls_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove the pitch, hit area, and printed legend of every performance
        keyboard key.

    Responsibilities:

        - probe all fourteen white and ten black key faces
        - verify black keys win in the area overlapping white keys
        - verify all twenty-four PC-key labels
        - exercise outer boundaries and invalid pitch ranges

    This file intentionally does NOT contain:

        - an application window
        - audio output
        - live recording
'/

#lang "fb"

#include once "../src/keyboard_controls.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Const testBasePitch As Integer = 60
For whiteIndex As Integer = 0 To OSE_KEYBOARD_WHITE_KEY_COUNT - 1
    Dim As Integer pitch = keyboardControls_WhitePitch(testBasePitch, whiteIndex)
    Dim As Integer keyCenterX = OSE_KEYBOARD_LEFT + _
        whiteIndex * OSE_KEYBOARD_WHITE_KEY_WIDTH + _
        OSE_KEYBOARD_WHITE_KEY_WIDTH \ 2
    Dim As Integer lowerKeyY = OSE_KEYBOARD_TOP + _
        OSE_KEYBOARD_BLACK_KEY_HEIGHT + 10
    If pitch < testBasePitch OrElse _
        keyboardControls_PitchAtPoint(testBasePitch, keyCenterX, lowerKeyY) <> _
            pitch Then _
        test_Fail "wrong white-key pitch at index " + Str(whiteIndex)
Next

For blackIndex As Integer = 0 To OSE_KEYBOARD_BLACK_KEY_COUNT - 1
    Dim As Integer pitch = keyboardControls_BlackPitch(testBasePitch, blackIndex)
    Dim As Integer keyCenterX = keyboardControls_BlackLeft(blackIndex) + _
        OSE_KEYBOARD_BLACK_KEY_WIDTH \ 2
    Dim As Integer upperKeyY = OSE_KEYBOARD_TOP + 10
    If pitch < testBasePitch OrElse _
        keyboardControls_PitchAtPoint(testBasePitch, keyCenterX, upperKeyY) <> _
            pitch Then _
        test_Fail "wrong black-key pitch at index " + Str(blackIndex)
Next

Dim As String expectedLabels = "ZSXDCVGBHNJMQ2W3ER5T6Y7U"
For noteOffset As Integer = 0 To OSE_KEYBOARD_NOTE_COUNT - 1
    If keyboardControls_KeyLabel(noteOffset) <> _
        Mid(expectedLabels, noteOffset + 1, 1) Then _
        test_Fail "wrong printed PC-key label"
Next

If keyboardControls_KeyLabel(-1) <> "" OrElse _
    keyboardControls_KeyLabel(OSE_KEYBOARD_NOTE_COUNT) <> "" Then _
    test_Fail "invalid label index was accepted"
If keyboardControls_PitchAtPoint(testBasePitch, OSE_KEYBOARD_LEFT - 1, _
    OSE_KEYBOARD_TOP) <> -1 OrElse _
    keyboardControls_PitchAtPoint(testBasePitch, OSE_KEYBOARD_LEFT, _
        OSE_KEYBOARD_TOP + OSE_KEYBOARD_WHITE_KEY_HEIGHT) <> -1 Then _
    test_Fail "coordinate outside the piano selected a key"
If keyboardControls_WhitePitch(127, 1) <> -1 OrElse _
    keyboardControls_BlackPitch(-10, 0) <> -1 Then _
    test_Fail "out-of-range MIDI pitch was accepted"

Print "keyboard_controls=ok"
Print "piano_keys="; OSE_KEYBOARD_NOTE_COUNT
End 0

/' end of tests/keyboard_controls_smoke.bas '/
