/'
    Project: OpenSesh
    ---------------------------

    File: tests/ui_icons_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify every embedded UI icon as a bounded grayscale coverage mask.

    Responsibilities:

        - inspect all twelve score-tool and transport masks
        - require stable names, dimensions, alpha quantization, and padding
        - verify distinguishing opaque and transparent landmarks per icon
        - prove the pointer uses an antialiased outline instead of a solid blob
        - prove larger mouse and touch controls center their icon masks

    This file intentionally does NOT contain:

        - framebuffer rendering or screenshot comparison
        - widget hit testing
        - application theme colors
'/

#lang "fb"

#include once "../src/ui_icons.bi"

' -------------------------------------------------------------------------
' Test helpers and byte-level coverage contract
' -------------------------------------------------------------------------

' The atlas format is deliberately ASCII so its checked-in rows remain easy
' to review.  These byte values avoid treating the portable format as text.
Const OSE_ASCII_ZERO As Integer = 48
Const OSE_ASCII_EIGHT As Integer = 56
Const OSE_ASCII_UPPER_F As Integer = 70
Const OSE_ASCII_UPPER_X As Integer = 88

Private Sub test_Fail(ByVal messageText As String)
    Print "ERROR: "; messageText
    End 1
End Sub


Private Sub test_RequireCoverage( _
    ByVal iconId As Integer, _
    ByVal pixelX As Integer, _
    ByVal pixelY As Integer, _
    ByVal minimumCoverage As Integer, _
    ByVal landmarkName As String _
)
    If uiIcons_Coverage(iconId, pixelX, pixelY) < minimumCoverage Then _
        test_Fail landmarkName + " is missing"
End Sub


Private Sub test_RequireTransparent( _
    ByVal iconId As Integer, _
    ByVal pixelX As Integer, _
    ByVal pixelY As Integer, _
    ByVal landmarkName As String _
)
    If uiIcons_Coverage(iconId, pixelX, pixelY) <> 0 Then _
        test_Fail landmarkName + " should be transparent"
End Sub


Dim As String expectedNames(0 To OSE_UI_ICON_COUNT - 1) = { _
    "Pointer", "Add Note", "Delete", "Cut", "Paste", "Stop", _
    "Pause", "Rewind", "Play", "Fast Forward", "Record", "Step Record" _
}
Dim As Integer totalCoverageSamples
Dim As Integer antialiasedIconCount

If OSE_UI_ICON_SIZE <> 24 OrElse OSE_UI_ICON_COUNT <> 12 Then _
    test_Fail "icon atlas dimensions changed"

For iconId As Integer = 0 To OSE_UI_ICON_COUNT - 1
    If uiIcons_IsValid(iconId) = 0 Then
        test_Fail "valid icon ID was rejected"
    End If
    If uiIcons_Name(iconId) <> expectedNames(iconId) Then _
        test_Fail "icon name changed at index " + Str(iconId)

    For otherId As Integer = iconId + 1 To OSE_UI_ICON_COUNT - 1
        If uiIcons_Name(iconId) = uiIcons_Name(otherId) Then _
            test_Fail "two icons share one accessible name"
    Next

    Dim As Integer nonzeroSamples
    Dim As Integer partialSamples
    For pixelY As Integer = 0 To OSE_UI_ICON_SIZE - 1
        Dim As String rowText
        If uiIcons_GetRow(iconId, pixelY, rowText) = 0 OrElse _
            Len(rowText) <> OSE_UI_ICON_SIZE Then _
            test_Fail "icon row is missing or incorrectly sized"

        For pixelX As Integer = 0 To OSE_UI_ICON_SIZE - 1
            Dim As Integer coverage = uiIcons_Coverage( _
                iconId, pixelX, pixelY)
            If coverage < 0 OrElse coverage > 255 OrElse _
                (coverage Mod 17) <> 0 Then _
                test_Fail "icon coverage is outside its four-bit contract"
            If coverage > 0 Then
                nonzeroSamples += 1
                totalCoverageSamples += 1
            End If
            If coverage > 0 AndAlso coverage < 255 Then
                partialSamples += 1
            End If

            If (pixelX = 0 OrElse pixelX = OSE_UI_ICON_SIZE - 1 OrElse _
                pixelY = 0 OrElse pixelY = OSE_UI_ICON_SIZE - 1) AndAlso _
                coverage <> 0 Then _
                test_Fail "icon touches padding at " + Str(iconId) + ":" + _
                    Str(pixelX) + "," + Str(pixelY)
        Next
    Next

    If nonzeroSamples < 40 Then
        test_Fail "icon mask is effectively empty"
    End If
    If partialSamples > 0 Then
        antialiasedIconCount += 1
    End If
Next

If uiIcons_IsValid(-1) <> 0 OrElse _
    uiIcons_IsValid(OSE_UI_ICON_COUNT) <> 0 OrElse _
    uiIcons_Name(-1) <> "" Then test_Fail "invalid icon ID was accepted"
Dim As String invalidRow = "sentinel"
If uiIcons_GetRow(-1, 0, invalidRow) <> 0 OrElse invalidRow <> "" OrElse _
    uiIcons_GetRow(0, OSE_UI_ICON_SIZE, invalidRow) <> 0 Then _
    test_Fail "invalid icon row was accepted"
If uiIcons_DecodeCoverage(OSE_ASCII_ZERO) <> 0 OrElse _
    uiIcons_DecodeCoverage(OSE_ASCII_EIGHT) <> 136 OrElse _
    uiIcons_DecodeCoverage(OSE_ASCII_UPPER_F) <> 255 OrElse _
    uiIcons_DecodeCoverage(OSE_ASCII_UPPER_X) <> 0 Then _
    test_Fail "coverage decoder changed"
If antialiasedIconCount < 9 Then _
    test_Fail "the icon atlas lost grayscale edge coverage"
If uiIcons_CenteredOffset(24) <> 0 OrElse _
    uiIcons_CenteredOffset(30) <> 3 OrElse _
    uiIcons_CenteredOffset(48) <> 12 OrElse _
    uiIcons_CenteredOffset(20) <> 0 Then _
    test_Fail "icons are not centered safely inside control faces"

' Pointer: crisp northwest tip, outlined body, and diagonal handle.
test_RequireCoverage OSE_UI_ICON_POINTER, 3, 2, 128, "pointer tip"
test_RequireTransparent OSE_UI_ICON_POINTER, 8, 10, "pointer interior"
test_RequireCoverage OSE_UI_ICON_POINTER, 12, 21, 128, "pointer handle"

' Score tools retain symbols which remain distinct without their text labels.
test_RequireCoverage OSE_UI_ICON_NOTE, 8, 18, 240, "note head"
test_RequireCoverage OSE_UI_ICON_NOTE, 13, 8, 200, "note stem"
test_RequireCoverage OSE_UI_ICON_TRASH, 12, 5, 240, "trash lid"
test_RequireTransparent OSE_UI_ICON_TRASH, 9, 12, "trash interior"
test_RequireCoverage OSE_UI_ICON_CUT, 3, 18, 180, "left scissor ring"
test_RequireCoverage OSE_UI_ICON_CUT, 12, 11, 180, "scissor pivot"
test_RequireCoverage OSE_UI_ICON_PASTE, 12, 3, 240, "clipboard clip"
test_RequireTransparent OSE_UI_ICON_PASTE, 12, 9, "clipboard page"

' Transport masks retain the conventional, immediately readable silhouettes.
test_RequireCoverage OSE_UI_ICON_STOP, 12, 12, 255, "stop square"
test_RequireCoverage OSE_UI_ICON_PAUSE, 7, 12, 255, "pause left bar"
test_RequireTransparent OSE_UI_ICON_PAUSE, 12, 12, "pause gap"
test_RequireCoverage OSE_UI_ICON_REWIND, 7, 12, 200, "rewind triangle"
test_RequireCoverage OSE_UI_ICON_PLAY, 8, 12, 255, "play triangle"
test_RequireCoverage OSE_UI_ICON_FORWARD, 16, 12, 200, _
    "fast-forward triangle"
test_RequireCoverage OSE_UI_ICON_RECORD, 12, 12, 255, "record circle"
test_RequireCoverage OSE_UI_ICON_STEP, 18, 12, 255, "step boundary"

Print "ui icon smoke test passed"
Print "icons="; OSE_UI_ICON_COUNT
Print "coverage_samples="; totalCoverageSamples
Print "antialiased_icons="; antialiasedIconCount

' end of tests/ui_icons_smoke.bas
