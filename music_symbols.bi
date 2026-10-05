/'
    Project: OpenSesh
    ---------------------------

    File: music_symbols.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: musicSymbols_* glyph loading/rendering and MUSIC_SYMBOL_* character codes.

    Purpose:

        Declare the optional bitmap music-symbol loader used by the score.

    Responsibilities:

        - define the observed Music Screen character slots used by the editor
        - expose bounded loading and drawing operations for an external mask
        - report whether an exact reference glyph is available

    This file intentionally does NOT contain:

        - a copy of Midisoft's font or glyph bitmap data
        - Windows font installation calls
        - score layout or MIDI-duration policy
'/

#ifndef __OPENSESH_MUSIC_SYMBOLS_BI__
#define __OPENSESH_MUSIC_SYMBOLS_BI__

Const MUSIC_SYMBOL_NOTE_FILLED As Integer = &H20
Const MUSIC_SYMBOL_NOTE_HOLLOW As Integer = &H21
Const MUSIC_SYMBOL_SHARP As Integer = &H22
Const MUSIC_SYMBOL_FLAT As Integer = &H23
Const MUSIC_SYMBOL_NATURAL As Integer = &H24
Const MUSIC_SYMBOL_DOUBLE_SHARP As Integer = &H25
Const MUSIC_SYMBOL_DOUBLE_FLAT As Integer = &H26
Const MUSIC_SYMBOL_QUARTER_REST As Integer = &H36
Const MUSIC_SYMBOL_EIGHTH_REST As Integer = &H37
Const MUSIC_SYMBOL_DOT As Integer = &H38

Declare Function musicSymbols_Load(ByVal filePath As String) As Integer
Declare Function musicSymbols_LoadDefault() As Integer
Declare Function musicSymbols_IsLoaded() As Integer
Declare Function musicSymbols_HasGlyph(ByVal characterCode As Integer) As Integer
Declare Function musicSymbols_GetWidth(ByVal characterCode As Integer) As Integer
Declare Function musicSymbols_GetHeight(ByVal characterCode As Integer) As Integer
Declare Sub musicSymbols_DrawCentered( _
    ByVal characterCode As Integer, _
    ByVal centerX As Integer, ByVal centerY As Integer, _
    ByVal glyphColor As ULong _
)
Declare Sub musicSymbols_Clear()

#endif

/' end of music_symbols.bi '/
