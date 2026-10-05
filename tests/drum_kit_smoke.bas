/'
    Project: OpenSesh
    ---------------------------

    File: tests/drum_kit_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove every drum-pad label, MIDI note, touch target, gutter, and
        velocity choice independently of the graphical application.

    Responsibilities:

        - verify all twelve General MIDI percussion mappings
        - verify the matching spatial PC-key map in both directions
        - hit the center and every inside corner of every responsive pad
        - reject gutters, outer edges, undersized surfaces, and invalid pads
        - verify the named velocity choices

    This file intentionally does NOT contain:

        - an application window
        - sound output
        - document recording
'/

#lang "fb"

#include once "../drum_kit.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Dim As Integer expectedPitches(0 To OSE_DRUM_PAD_COUNT - 1) = { _
    49, 51, 46, 54, 50, 47, 43, 39, 36, 38, 37, 42 _
}
Dim As String expectedNames(0 To OSE_DRUM_PAD_COUNT - 1) = { _
    "Crash", "Ride", "Open Hi-Hat", "Tambourine", _
    "High Tom", "Mid Tom", "Low Tom", "Hand Clap", _
    "Kick", "Snare", "Side Stick", "Closed Hi-Hat" _
}
Dim As String expectedKeys(0 To OSE_DRUM_PAD_COUNT - 1) = { _
    "1", "2", "3", "4", "Q", "W", "E", "R", "A", "S", "D", "F" _
}

Const testSurfaceX As Integer = 17
Const testSurfaceY As Integer = 29
Const testSurfaceWidth As Integer = 803
Const testSurfaceHeight As Integer = 397

For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
    If drumKit_Pitch(padIndex) <> expectedPitches(padIndex) Then _
        test_Fail "wrong MIDI pitch at pad " + Str(padIndex)
    If drumKit_Name(padIndex) <> expectedNames(padIndex) Then _
        test_Fail "wrong name at pad " + Str(padIndex)
    If drumKit_KeyLabel(padIndex) <> expectedKeys(padIndex) OrElse _
        drumKit_PadForKeyLabel(LCase(expectedKeys(padIndex))) <> padIndex Then _
        test_Fail "wrong key map at pad " + Str(padIndex)

    Dim As OseDrumPadRectangle padRectangle
    drumKit_PadRectangle padIndex, testSurfaceX, testSurfaceY, _
        testSurfaceWidth, testSurfaceHeight, padRectangle
    If padRectangle.width < OSE_DRUM_MINIMUM_PAD_SIZE OrElse _
        padRectangle.height < OSE_DRUM_MINIMUM_PAD_SIZE Then _
        test_Fail "pad is smaller than the touch minimum"

    Dim As Integer probeX(0 To 2) = { _
        padRectangle.x, _
        padRectangle.x + padRectangle.width \ 2, _
        padRectangle.x + padRectangle.width - 1 _
    }
    Dim As Integer probeY(0 To 2) = { _
        padRectangle.y, _
        padRectangle.y + padRectangle.height \ 2, _
        padRectangle.y + padRectangle.height - 1 _
    }
    For probeIndex As Integer = 0 To 2
        If drumKit_PadAtPoint(probeX(probeIndex), probeY(probeIndex), _
            testSurfaceX, testSurfaceY, testSurfaceWidth, _
            testSurfaceHeight) <> padIndex Then _
            test_Fail "inside point missed pad " + Str(padIndex)
    Next
Next

Dim As OseDrumPadRectangle firstPad
drumKit_PadRectangle 0, testSurfaceX, testSurfaceY, testSurfaceWidth, _
    testSurfaceHeight, firstPad
If drumKit_PadAtPoint(firstPad.x + firstPad.width, firstPad.y, _
    testSurfaceX, testSurfaceY, testSurfaceWidth, testSurfaceHeight) <> -1 Then _
    test_Fail "horizontal gutter selected a pad"
If drumKit_PadAtPoint(firstPad.x, firstPad.y + firstPad.height, _
    testSurfaceX, testSurfaceY, testSurfaceWidth, testSurfaceHeight) <> -1 Then _
    test_Fail "vertical gutter selected a pad"
If drumKit_PadAtPoint(testSurfaceX - 1, testSurfaceY, testSurfaceX, _
    testSurfaceY, testSurfaceWidth, testSurfaceHeight) <> -1 OrElse _
    drumKit_PadAtPoint(testSurfaceX + testSurfaceWidth, testSurfaceY, _
        testSurfaceX, testSurfaceY, testSurfaceWidth, _
        testSurfaceHeight) <> -1 Then _
    test_Fail "point outside the surface selected a pad"

Dim As OseDrumPadRectangle invalidRectangle
drumKit_PadRectangle -1, testSurfaceX, testSurfaceY, testSurfaceWidth, _
    testSurfaceHeight, invalidRectangle
If invalidRectangle.width <> 0 OrElse drumKit_Pitch(-1) <> -1 OrElse _
    drumKit_Name(OSE_DRUM_PAD_COUNT) <> "" OrElse _
    drumKit_KeyLabel(OSE_DRUM_PAD_COUNT) <> "" OrElse _
    drumKit_PadForKeyLabel("X") <> -1 Then _
    test_Fail "invalid pad input was accepted"

drumKit_PadRectangle 0, 0, 0, _
    OSE_DRUM_COLUMN_COUNT * OSE_DRUM_MINIMUM_PAD_SIZE - 1, _
    OSE_DRUM_ROW_COUNT * OSE_DRUM_MINIMUM_PAD_SIZE - 1, invalidRectangle
If invalidRectangle.width <> 0 OrElse invalidRectangle.height <> 0 Then _
    test_Fail "undersized pad surface produced a rectangle"

If drumKit_VelocityName(OSE_DRUM_VELOCITY_SOFT) <> "Soft" OrElse _
    drumKit_VelocityName(OSE_DRUM_VELOCITY_MEDIUM) <> "Medium" OrElse _
    drumKit_VelocityName(OSE_DRUM_VELOCITY_HARD) <> "Hard" OrElse _
    drumKit_VelocityName(99) <> "" Then _
    test_Fail "velocity choices are not exact and bounded"

Print "drum_kit=ok"
Print "drum_pads="; OSE_DRUM_PAD_COUNT
End 0

/' end of tests/drum_kit_smoke.bas '/
