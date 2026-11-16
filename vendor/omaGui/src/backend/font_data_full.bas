/'
    Project: omaGUI
    ---------------
    File: font_data_full.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI font_data_full implementation imported through omaGUI.bi.
    Purpose:
        Own embedded bitmap glyph data and initialize font pointers.

    Responsibilities:
        - select the default or redistributable font tables at compile time
        - provide the small Latin-1 fallback on non-DOS targets
        - initialize the glyph pointers once for the backend

    This file intentionally does NOT contain:
        - text layout or rasterization
        - runtime font-pack loading
'/
#lang "fb"
#include once "src/backend/backend.bi"
#include once "src/backend/font_data.bi"

#ifndef __FONT_DATA_FULL_IMPL__
#define __FONT_DATA_FULL_IMPL__
' Shared state boundary: the renderer reads this lookup table after font_init_pointers builds it once.
Dim Shared As UByte Ptr font_chars(32 To 126)
#ifndef __FB_DOS__
#include "assets/fonts/font_latin1_fallback.bi"
#endif
#ifdef OMAGUI_REDISTRIBUTABLE_FONTS
#include "assets/fonts/font_omagui_sans_10_regular.bi"
#include "assets/fonts/font_omagui_sans_12_bold.bi"
#include "assets/fonts/font_omagui_sans_18_bold.bi"
#include "assets/fonts/font_omagui_serif_18_regular.bi"
#else
#include "src/backend/font_data_impl.bi"
#include "assets/fonts/font_arial_10_regular.bi"
#include "assets/fonts/font_arial_12_bold.bi"
#include "assets/fonts/font_liberation_sans_18_bold.bi"
#include "assets/fonts/font_liberation_serif_18_regular.bi"
#endif
#endif

Sub font_init_pointers()
#ifndef __FB_DOS__
    font_latin1_init_unicode_pointers()
#endif
#ifdef OMAGUI_REDISTRIBUTABLE_FONTS
    font_omagui_sans_10_regular_init_pointers()
    font_omagui_sans_12_bold_init_pointers()
    font_omagui_sans_18_bold_init_pointers()
    font_omagui_serif_18_regular_init_pointers()
    For characterCode As Integer = 32 To 126
        font_chars(characterCode) = _
            font_omagui_sans_10_regular_chars(characterCode)
    Next characterCode
#else
    /' Assign character data addresses to the global lookup array '/
    #include "src/backend/font_init.bi"
    font_arial_10_regular_init_pointers()
    font_arial_12_bold_init_pointers()
    font_liberation_sans_18_bold_init_pointers()
    font_liberation_serif_18_regular_init_pointers()
#endif
End Sub

#ifndef __FB_DOS__
Function font_latin1_glyph(ByVal codepoint As Integer) As UByte Ptr
    Dim As Integer lowerIndex = 0
    Dim As Integer upperIndex = font_latin1_unicode_glyph_count - 1

    If codepoint < 0 Then Return 0
    While lowerIndex <= upperIndex
        Dim As Integer middleIndex = lowerIndex + (upperIndex - lowerIndex) \ 2
        Dim As UInteger candidate = font_latin1_unicode_codepoints(middleIndex)
        If candidate = CUInt(codepoint) Then Return font_latin1_unicode_glyphs(middleIndex)
        If candidate < CUInt(codepoint) Then
            lowerIndex = middleIndex + 1
        Else
            upperIndex = middleIndex - 1
        End If
    Wend
    Return 0
End Function
#endif

/' end of font_data_full.bas '/
