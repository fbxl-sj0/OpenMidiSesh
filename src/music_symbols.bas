/'
    Project: OpenSesh
    ---------------------------

    File: music_symbols.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements music_symbols.bi; declarations there define the shared interface.

    Purpose:

        Load a bounded monochrome music-symbol mask generated from a locally
        owned reference font and draw those symbols through omaGUI's backend.

    Responsibilities:

        - validate the external mask header, glyph bounds, rows, and terminators
        - commit glyph state only after the complete file passes validation
        - locate an optional application-local mask without a system font install
        - draw loaded glyph pixels in the score's requested color

    This file intentionally does NOT contain:

        - embedded Midisoft glyph data
        - FON decompression or Windows GDI calls
        - fallback notation drawing; the score renderer owns that policy
'/

#lang "fb"

#include once "music_symbols.bi"
#include once "numeric_text.bi"
#include once "src/backend/backend.bi"

Const MUSIC_SYMBOL_FIRST_CODE As Integer = &H20
Const MUSIC_SYMBOL_LAST_CODE As Integer = &H3F
Const MUSIC_SYMBOL_MAXIMUM_WIDTH As Integer = 32
Const MUSIC_SYMBOL_MAXIMUM_HEIGHT As Integer = 32
Const MUSIC_SYMBOL_MAXIMUM_PIXELS As Integer = _
    MUSIC_SYMBOL_MAXIMUM_WIDTH * MUSIC_SYMBOL_MAXIMUM_HEIGHT
Const MUSIC_SYMBOL_MASK_HEADER As String = "MIDISOFT_MUSIC_SCREEN_MASKS 1"
' The mask format is an ASCII interchange file. Named byte values keep its
' hexadecimal grammar explicit without depending on locale or Unicode digits.
Const MUSIC_SYMBOL_ASCII_ZERO As Integer = 48
Const MUSIC_SYMBOL_ASCII_NINE As Integer = 57
Const MUSIC_SYMBOL_ASCII_UPPER_A As Integer = 65
Const MUSIC_SYMBOL_ASCII_UPPER_F As Integer = 70
Const MUSIC_SYMBOL_ASCII_LOWER_A As Integer = 97
Const MUSIC_SYMBOL_ASCII_LOWER_F As Integer = 102

Type MusicSymbolGlyph
    As Integer available
    As Integer glyphWidth
    As Integer glyphHeight
    As UByte pixels(0 To MUSIC_SYMBOL_MAXIMUM_PIXELS - 1)
End Type

' fblint: disable-next-line FBL301 REASON: the loaded glyph cache is owned by this module.
Dim Shared musicSymbols_Glyphs( _
    MUSIC_SYMBOL_FIRST_CODE To MUSIC_SYMBOL_LAST_CODE _
) As MusicSymbolGlyph
' fblint: disable-next-line FBL301 REASON: this flag belongs to the same module-owned cache.
Dim Shared musicSymbols_Loaded As Integer


' -------------------------------------------------------------------------
' Mask parsing
' -------------------------------------------------------------------------

Private Function musicSymbols_ParseHexCode( _
    ByVal codeText As String, _
    ByRef characterCode As Integer _
) As Integer
    If Len(codeText) <> 2 Then
        Return 0
    End If

    Dim As Integer workingCode
    For characterIndex As Integer = 1 To Len(codeText)
        Dim As Integer characterValue = Asc(Mid(codeText, characterIndex, 1))
        Dim As Integer digitValue
        Select Case characterValue
            Case MUSIC_SYMBOL_ASCII_ZERO To MUSIC_SYMBOL_ASCII_NINE
                digitValue = characterValue - MUSIC_SYMBOL_ASCII_ZERO
            Case MUSIC_SYMBOL_ASCII_UPPER_A To MUSIC_SYMBOL_ASCII_UPPER_F
                digitValue = characterValue - MUSIC_SYMBOL_ASCII_UPPER_A + 10
            Case MUSIC_SYMBOL_ASCII_LOWER_A To MUSIC_SYMBOL_ASCII_LOWER_F
                digitValue = characterValue - MUSIC_SYMBOL_ASCII_LOWER_A + 10
            Case Else
                Return 0
        End Select
        workingCode = workingCode * 16 + digitValue
    Next

    characterCode = workingCode
    Return -1
End Function


Private Function musicSymbols_ParseGlyphHeader( _
    ByVal lineText As String, _
    ByRef characterCode As Integer, _
    ByRef glyphWidth As Integer, _
    ByRef glyphHeight As Integer _
) As Integer
    Const GLYPH_PREFIX As String = "GLYPH "

    If Left(lineText, Len(GLYPH_PREFIX)) <> GLYPH_PREFIX Then
        Return 0
    End If

    Dim As String lineRemainder = Trim(Mid(lineText, Len(GLYPH_PREFIX) + 1))
    Dim As Integer firstSeparator = InStr(lineRemainder, " ")
    If firstSeparator <= 1 Then
        Return 0
    End If

    Dim As String codeText = Left(lineRemainder, firstSeparator - 1)
    lineRemainder = Trim(Mid(lineRemainder, firstSeparator + 1))
    Dim As Integer secondSeparator = InStr(lineRemainder, " ")
    If secondSeparator <= 1 Then
        Return 0
    End If

    Dim As String widthText = Left(lineRemainder, secondSeparator - 1)
    Dim As String heightText = Trim(Mid(lineRemainder, secondSeparator + 1))
    If Len(codeText) <> 2 OrElse widthText = "" OrElse _
        heightText = "" Then
        Return 0
    End If

    Dim As Integer parsedCode
    Dim As ULongInt parsedWidth
    Dim As ULongInt parsedHeight
    If musicSymbols_ParseHexCode(codeText, parsedCode) = 0 OrElse _
        parsedCode < MUSIC_SYMBOL_FIRST_CODE OrElse _
        parsedCode > MUSIC_SYMBOL_LAST_CODE Then
        Return 0
    End If
    If numericText_ParseUnsigned( _
        widthText, parsedWidth, MUSIC_SYMBOL_MAXIMUM_WIDTH) = 0 OrElse _
        parsedWidth < 1ULL Then
        Return 0
    End If
    If numericText_ParseUnsigned( _
        heightText, parsedHeight, MUSIC_SYMBOL_MAXIMUM_HEIGHT) = 0 OrElse _
        parsedHeight < 1ULL Then
        Return 0
    End If

    characterCode = parsedCode
    glyphWidth = CInt(parsedWidth)
    glyphHeight = CInt(parsedHeight)
    Return -1
End Function


Private Function musicSymbols_RequiredGlyphsPresent( _
    stagedGlyphs() As MusicSymbolGlyph _
) As Integer
    Dim As Integer requiredCodes(0 To 5) = { _
        MUSIC_SYMBOL_SHARP, MUSIC_SYMBOL_FLAT, MUSIC_SYMBOL_NATURAL, _
        MUSIC_SYMBOL_QUARTER_REST, MUSIC_SYMBOL_EIGHTH_REST, _
        MUSIC_SYMBOL_DOT _
    }

    For requiredIndex As Integer = 0 To UBound(requiredCodes)
        If stagedGlyphs(requiredCodes(requiredIndex)).available = 0 Then
            Return 0
        End If
    Next

    Return -1
End Function


Public Function musicSymbols_Load(ByVal filePath As String) As Integer
    If Len(Trim(filePath)) = 0 Then
        Return 0
    End If

    Dim As Integer fileNumber = FreeFile
    If Open(filePath For Input As #fileNumber) <> 0 Then
        Return 0
    End If

    Dim As MusicSymbolGlyph stagedGlyphs( _
        MUSIC_SYMBOL_FIRST_CODE To MUSIC_SYMBOL_LAST_CODE _
    )
    Dim As Integer inputValid = -1
    Dim As String lineText

    If Eof(fileNumber) <> 0 Then
        inputValid = 0
    Else
        Line Input #fileNumber, lineText
        If Trim(lineText) <> MUSIC_SYMBOL_MASK_HEADER Then
            inputValid = 0
        End If
    End If

    While inputValid <> 0 AndAlso Eof(fileNumber) = 0
        Line Input #fileNumber, lineText
        lineText = Trim(lineText)
        If lineText = "" Then
            Continue While
        End If

        Dim As Integer characterCode
        Dim As Integer glyphWidth
        Dim As Integer glyphHeight
        If musicSymbols_ParseGlyphHeader( _
            lineText, characterCode, glyphWidth, glyphHeight _
        ) = 0 Then
            inputValid = 0
            Exit While
        End If
        If stagedGlyphs(characterCode).available <> 0 Then
            inputValid = 0
            Exit While
        End If

        For rowIndex As Integer = 0 To glyphHeight - 1
            If Eof(fileNumber) <> 0 Then
                inputValid = 0
                Exit For
            End If

            Dim As String rowText
            Line Input #fileNumber, rowText
            If Len(rowText) <> glyphWidth Then
                inputValid = 0
                Exit For
            End If

            For columnIndex As Integer = 0 To glyphWidth - 1
                Dim As String pixelText = Mid(rowText, columnIndex + 1, 1)
                Select Case pixelText
                    Case "#"
                        stagedGlyphs(characterCode).pixels( _
                            rowIndex * MUSIC_SYMBOL_MAXIMUM_WIDTH + columnIndex _
                        ) = 1
                    Case "."
                    Case Else
                        inputValid = 0
                        Exit For
                End Select
            Next
            If inputValid = 0 Then
                Exit For
            End If
        Next
        If inputValid = 0 Then
            Exit While
        End If

        If Eof(fileNumber) <> 0 Then
            inputValid = 0
            Exit While
        End If
        Line Input #fileNumber, lineText
        If Trim(lineText) <> "END" Then
            inputValid = 0
            Exit While
        End If

        stagedGlyphs(characterCode).glyphWidth = glyphWidth
        stagedGlyphs(characterCode).glyphHeight = glyphHeight
        stagedGlyphs(characterCode).available = -1
    Wend

    Close #fileNumber

    If inputValid = 0 OrElse _
        musicSymbols_RequiredGlyphsPresent(stagedGlyphs()) = 0 Then
        Return 0
    End If

    musicSymbols_Clear
    For characterCode As Integer = MUSIC_SYMBOL_FIRST_CODE To _
        MUSIC_SYMBOL_LAST_CODE
        musicSymbols_Glyphs(characterCode) = stagedGlyphs(characterCode)
    Next
    musicSymbols_Loaded = -1
    Return -1
End Function


' -------------------------------------------------------------------------
' Default asset discovery
' -------------------------------------------------------------------------

Public Function musicSymbols_LoadDefault() As Integer
    Dim As String executableDirectory = ExePath
    Dim As String currentDirectory = CurDir
    Dim As String candidates(0 To 1)
    Dim As Integer pathIndex

    /'
        Runtime asset discovery is deliberately local to the application.
        Development analysis trees are not release inputs and must never make
        an editor launched from a source checkout render differently from the
        exact same executable in a package or test directory.
    '/
    candidates(0) = executableDirectory + "/music-screen-glyphs.mask"
    candidates(1) = currentDirectory + "/music-screen-glyphs.mask"

    For pathIndex = 0 To UBound(candidates)
        If Len(Dir(candidates(pathIndex))) > 0 Then
            If musicSymbols_Load(candidates(pathIndex)) <> 0 Then
                Return -1
            End If
        End If
    Next

    Return 0
End Function


' -------------------------------------------------------------------------
' Glyph queries and rendering
' -------------------------------------------------------------------------

Public Function musicSymbols_IsLoaded() As Integer
    Return musicSymbols_Loaded
End Function


Public Function musicSymbols_HasGlyph(ByVal characterCode As Integer) As Integer
    If musicSymbols_Loaded = 0 Then
        Return 0
    End If
    If characterCode < MUSIC_SYMBOL_FIRST_CODE OrElse _
        characterCode > MUSIC_SYMBOL_LAST_CODE Then
        Return 0
    End If
    Return musicSymbols_Glyphs(characterCode).available
End Function


Public Function musicSymbols_GetWidth(ByVal characterCode As Integer) As Integer
    If musicSymbols_HasGlyph(characterCode) = 0 Then
        Return 0
    End If
    Return musicSymbols_Glyphs(characterCode).glyphWidth
End Function


Public Function musicSymbols_GetHeight(ByVal characterCode As Integer) As Integer
    If musicSymbols_HasGlyph(characterCode) = 0 Then
        Return 0
    End If
    Return musicSymbols_Glyphs(characterCode).glyphHeight
End Function


Public Sub musicSymbols_DrawCentered( _
    ByVal characterCode As Integer, _
    ByVal centerX As Integer, ByVal centerY As Integer, _
    ByVal glyphColor As ULong _
)
    If musicSymbols_HasGlyph(characterCode) = 0 Then
        Exit Sub
    End If

    Dim As MusicSymbolGlyph Ptr glyph = @musicSymbols_Glyphs(characterCode)
    Dim As Integer glyphLeft = centerX - glyph->glyphWidth \ 2
    Dim As Integer glyphTop = centerY - glyph->glyphHeight \ 2

    For rowIndex As Integer = 0 To glyph->glyphHeight - 1
        For columnIndex As Integer = 0 To glyph->glyphWidth - 1
            If glyph->pixels( _
                rowIndex * MUSIC_SYMBOL_MAXIMUM_WIDTH + columnIndex _
            ) <> 0 Then
                backend_PSet glyphLeft + columnIndex, glyphTop + rowIndex, _
                    glyphColor
            End If
        Next
    Next
End Sub


Public Sub musicSymbols_Clear()
    For characterCode As Integer = MUSIC_SYMBOL_FIRST_CODE To _
        MUSIC_SYMBOL_LAST_CODE
        musicSymbols_Glyphs(characterCode).available = 0
        musicSymbols_Glyphs(characterCode).glyphWidth = 0
        musicSymbols_Glyphs(characterCode).glyphHeight = 0
        For pixelIndex As Integer = 0 To MUSIC_SYMBOL_MAXIMUM_PIXELS - 1
            musicSymbols_Glyphs(characterCode).pixels(pixelIndex) = 0
        Next
    Next
    musicSymbols_Loaded = 0
End Sub

/' end of music_symbols.bas '/
