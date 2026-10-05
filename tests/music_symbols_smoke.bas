/'
    Project: OpenSesh
    ---------------------------

    File: tests/music_symbols_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Module API: Test executable accepting an executable-side music-screen-glyphs.mask
        fixture path; supplies backend_PSet to record the production glyph drawing.

    Purpose:

        Verify the optional music-symbol mask loader, staged commit behavior,
        query bounds, default discovery, drawing coordinates, and cleanup.

    Responsibilities:

        - load all required reference symbol slots from a generated mask
        - reject malformed, duplicate, incomplete, and oversized glyph data
        - prove a failed replacement cannot destroy the active glyph cache
        - verify centered pixel placement through a deterministic backend stub

    This file intentionally does NOT contain:

        - private Midisoft glyph artwork
        - a graphics screen or window
        - score fallback rendering
'/

#lang "fb"

#include once "../music_symbols.bi"

' -------------------------------------------------------------------------
' Deterministic backend boundary
' -------------------------------------------------------------------------

Dim Shared test_DrawCount As Integer
Dim Shared test_MinimumX As Integer
Dim Shared test_MaximumX As Integer
Dim Shared test_MinimumY As Integer
Dim Shared test_MaximumY As Integer


Sub backend_PSet( _
    ByVal pixelX As Integer, _
    ByVal pixelY As Integer, _
    ByVal pixelColor As ULong _
)
    If pixelColor <> RGB(10, 20, 30) Then
        Print "FAIL: drawing changed the requested glyph color"
        End 1
    End If
    If test_DrawCount = 0 Then
        test_MinimumX = pixelX
        test_MaximumX = pixelX
        test_MinimumY = pixelY
        test_MaximumY = pixelY
    Else
        If pixelX < test_MinimumX Then
            test_MinimumX = pixelX
        End If
        If pixelX > test_MaximumX Then
            test_MaximumX = pixelX
        End If
        If pixelY < test_MinimumY Then
            test_MinimumY = pixelY
        End If
        If pixelY > test_MaximumY Then
            test_MaximumY = pixelY
        End If
    End If
    test_DrawCount += 1
End Sub

' -------------------------------------------------------------------------
' Mask fixture helpers
' -------------------------------------------------------------------------

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Sub test_WriteText( _
    ByVal fixtureFilename As String, _
    ByVal fileText As String _
)
    Dim As Integer fileNumber = FreeFile()
    If Open(fixtureFilename For Output As #fileNumber) <> 0 Then _
        test_Fail "could not create music-symbol fixture"
    Print #fileNumber, fileText;
    Close #fileNumber
End Sub


Private Function test_GlyphWithHeader(ByVal headerText As String) As String
    Dim As String newLine = Chr(10)
    Return headerText + newLine + _
        ".#." + newLine + "###" + newLine + ".#." + newLine + _
        "END" + newLine
End Function


Private Function test_Glyph(ByVal codeText As String) As String
    Return test_GlyphWithHeader("GLYPH " + codeText + " 3 3")
End Function


Private Function test_MaskWithFirstHeader(ByVal headerText As String) As String
    Dim As String newLine = Chr(10)
    Return "MIDISOFT_MUSIC_SCREEN_MASKS 1" + newLine + _
        test_GlyphWithHeader(headerText) + _
        test_Glyph("23") + test_Glyph("24") + _
        test_Glyph("36") + test_Glyph("37") + test_Glyph("38")
End Function


Private Function test_ValidMask() As String
    Dim As String newLine = Chr(10)
    Return "MIDISOFT_MUSIC_SCREEN_MASKS 1" + newLine + _
        test_Glyph("22") + test_Glyph("23") + test_Glyph("24") + _
        test_Glyph("36") + test_Glyph("37") + test_Glyph("38")
End Function

' -------------------------------------------------------------------------
' Loading, querying, rendering, and staged replacement
' -------------------------------------------------------------------------

Dim As String fixtureFilename = Trim(Command(1))
If fixtureFilename = "" Then
    Print "usage: music_symbols_smoke.exe <music-screen-glyphs.mask>"
    End 2
End If

musicSymbols_Clear()
If musicSymbols_IsLoaded() <> 0 Then
    test_Fail "clear retained loaded state"
End If
If musicSymbols_Load(fixtureFilename + ".missing") <> 0 Then _
    test_Fail "missing mask file was accepted"

Dim As String validMask = test_ValidMask()
test_WriteText fixtureFilename, validMask
If musicSymbols_LoadDefault() = 0 Then _
    test_Fail "default mask discovery did not find the executable-side fixture"
If musicSymbols_IsLoaded() = 0 Then
    test_Fail "valid mask did not set loaded state"
End If

Dim As Integer requiredCodes(0 To 5) = { _
    MUSIC_SYMBOL_SHARP, MUSIC_SYMBOL_FLAT, MUSIC_SYMBOL_NATURAL, _
    MUSIC_SYMBOL_QUARTER_REST, MUSIC_SYMBOL_EIGHTH_REST, MUSIC_SYMBOL_DOT _
}
For requiredIndex As Integer = 0 To UBound(requiredCodes)
    Dim As Integer characterCode = requiredCodes(requiredIndex)
    If musicSymbols_HasGlyph(characterCode) = 0 OrElse _
        musicSymbols_GetWidth(characterCode) <> 3 OrElse _
        musicSymbols_GetHeight(characterCode) <> 3 Then _
        test_Fail "required glyph query returned the wrong bounds"
Next
If musicSymbols_HasGlyph(&H1F) <> 0 OrElse _
    musicSymbols_HasGlyph(&H40) <> 0 OrElse _
    musicSymbols_GetWidth(&H40) <> 0 OrElse _
    musicSymbols_GetHeight(&H1F) <> 0 Then _
    test_Fail "out-of-range glyph query was not bounded"

test_DrawCount = 0
musicSymbols_DrawCentered MUSIC_SYMBOL_SHARP, 10, 20, RGB(10, 20, 30)
If test_DrawCount <> 5 OrElse test_MinimumX <> 9 OrElse _
    test_MaximumX <> 11 OrElse test_MinimumY <> 19 OrElse _
    test_MaximumY <> 21 Then _
    test_Fail "centered glyph pixels used the wrong coordinates"

' Every rejected replacement must leave the already-validated cache intact.
Dim As String newLine = Chr(10)
Dim As String malformedMasks(0 To 10)
malformedMasks(0) = "WRONG HEADER" + newLine
malformedMasks(1) = "MIDISOFT_MUSIC_SCREEN_MASKS 1" + newLine + _
    test_Glyph("22")
malformedMasks(2) = validMask + test_Glyph("22")
malformedMasks(3) = "MIDISOFT_MUSIC_SCREEN_MASKS 1" + newLine + _
    "GLYPH 22 33 1" + newLine + "END" + newLine
malformedMasks(4) = "MIDISOFT_MUSIC_SCREEN_MASKS 1" + newLine + _
    "GLYPH 22 1 1" + newLine + "x" + newLine + "END" + newLine
malformedMasks(5) = test_MaskWithFirstHeader("GLYPH 22 3x 3")
malformedMasks(6) = test_MaskWithFirstHeader("GLYPH 22 3 3x")
malformedMasks(7) = test_MaskWithFirstHeader("GLYPH 22 +3 3")
malformedMasks(8) = test_MaskWithFirstHeader("GLYPH 22 3.0 3")
malformedMasks(9) = test_MaskWithFirstHeader("GLYPH 22 3 3 trailing")
malformedMasks(10) = test_MaskWithFirstHeader("GLYPH 2G 3 3")

For malformedIndex As Integer = 0 To UBound(malformedMasks)
    test_WriteText fixtureFilename, malformedMasks(malformedIndex)
    If musicSymbols_Load(fixtureFilename) <> 0 Then _
        test_Fail "malformed symbol mask was accepted"
    If musicSymbols_IsLoaded() = 0 OrElse _
        musicSymbols_HasGlyph(MUSIC_SYMBOL_SHARP) = 0 Then _
        test_Fail "failed mask replacement destroyed the active cache"
Next

musicSymbols_Clear()
If musicSymbols_IsLoaded() <> 0 OrElse _
    musicSymbols_HasGlyph(MUSIC_SYMBOL_SHARP) <> 0 OrElse _
    musicSymbols_GetWidth(MUSIC_SYMBOL_SHARP) <> 0 Then _
    test_Fail "clear did not release the glyph cache"

Print "music_symbols=ok"
Print "required_glyphs=6 malformed_masks=11 drawn_pixels=5"
Print "music_symbol_malformed_masks=11"
End 0

/' end of tests/music_symbols_smoke.bas '/
