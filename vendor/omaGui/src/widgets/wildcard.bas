/'
    Project: omaGUI
    ---------------

    File: wildcard.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements wildcard.bi; declarations there define the interface.

    Purpose:

        Match filename patterns consistently on every supported backend.

    Responsibilities:

        - implement bounded, iterative '*' and '?' wildcard matching
        - apply Windows-style case-insensitive comparisons on every target
        - preserve the common DOS meaning of '*.*' as every filename

    This file intentionally does NOT contain:

        - filesystem enumeration or path validation
        - semicolon-separated pattern parsing
        - Windows SDK or host-specific APIs
'/

#lang "fb"

#include once "src/widgets/wildcard.bi"

Const OMAGUI_WILDCARD_MAX_PATTERN_BYTES As Integer = 1024

Function omaguiinternal_WildcardMatches( _
    ByRef fileName As Const String, _
    ByRef patternText As Const String _
) As Integer
    Dim As Integer fileIndex
    Dim As Integer retryFileIndex
    Dim As Integer starPatternIndex
    Dim As Integer patternIndex
    Dim As Integer fileCharacter
    Dim As Integer patternCharacter
    Dim As String foldedFileName
    Dim As String foldedPattern

    If Len(patternText) = 0 OrElse _
       Len(patternText) > OMAGUI_WILDCARD_MAX_PATTERN_BYTES Then Return 0

    /'
        Matching after enumeration avoids the host-dependent case rules of
        Dir. Keeping the matcher iterative also bounds stack use for patterns
        supplied by applications or VBDOS forms.
    '/
    foldedFileName = UCase(fileName)
    foldedPattern = UCase(patternText)
    If foldedPattern = "*.*" Then foldedPattern = "*"

    fileIndex = 1
    patternIndex = 1
    While fileIndex <= Len(foldedFileName)
        fileCharacter = foldedFileName[fileIndex - 1]
        If patternIndex <= Len(foldedPattern) Then
            patternCharacter = foldedPattern[patternIndex - 1]
        Else
            patternCharacter = 0
        End If
        If patternIndex <= Len(foldedPattern) Then
            If patternCharacter = Asc("?") OrElse _
               patternCharacter = fileCharacter Then
                fileIndex += 1
                patternIndex += 1
            ElseIf patternCharacter = Asc("*") Then
                starPatternIndex = patternIndex
                patternIndex += 1
                retryFileIndex = fileIndex
            ElseIf starPatternIndex > 0 Then
                retryFileIndex += 1
                fileIndex = retryFileIndex
                patternIndex = starPatternIndex + 1
            Else
                Return 0
            End If
        ElseIf starPatternIndex > 0 Then
            retryFileIndex += 1
            fileIndex = retryFileIndex
            patternIndex = starPatternIndex + 1
        Else
            Return 0
        End If
    Wend
    While patternIndex <= Len(foldedPattern) AndAlso _
          Mid(foldedPattern, patternIndex, 1) = "*"
        patternIndex += 1
    Wend
    Return IIf(patternIndex > Len(foldedPattern), -1, 0)
End Function

/' end of wildcard.bas '/
