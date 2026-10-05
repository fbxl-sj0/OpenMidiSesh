/'
    Project: OpenSesh
    ---------------------------

    File: keyboard_controls.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements keyboard_controls.bi; declarations there define the shared interface.

    Purpose:

        Keep performance-keyboard drawing and mouse input on one pitch map.

    Responsibilities:

        - calculate white and black MIDI pitches from a bounded base range
        - calculate black-key positions between their neighboring white keys
        - hit-test black keys before the white keys underneath them
        - return the PC keyboard legend for each semitone

    This file intentionally does NOT contain:

        - keyboard-window state
        - audio audition voices
        - live-recording state
'/

#lang "fb"

#include once "keyboard_controls.bi"

' -------------------------------------------------------------------------
' Piano pitch geometry
' -------------------------------------------------------------------------

Public Function keyboardControls_WhitePitch( _
    ByVal basePitch As Integer, _
    ByVal whiteIndex As Integer _
) As Integer
    If whiteIndex < 0 OrElse whiteIndex >= OSE_KEYBOARD_WHITE_KEY_COUNT Then
        Return -1
    End If
    Dim As Integer whiteOffsets(0 To 6) = {0, 2, 4, 5, 7, 9, 11}
    Dim As Integer pitch = basePitch + (whiteIndex \ 7) * 12 + _
        whiteOffsets(whiteIndex Mod 7)
    If pitch < 0 OrElse pitch > 127 Then
        Return -1
    End If
    Return pitch
End Function


Public Function keyboardControls_BlackPitch( _
    ByVal basePitch As Integer, _
    ByVal blackIndex As Integer _
) As Integer
    Dim As Integer blackOffsets(0 To OSE_KEYBOARD_BLACK_KEY_COUNT - 1) = _
        {1, 3, 6, 8, 10, 13, 15, 18, 20, 22}
    If blackIndex < 0 OrElse blackIndex > UBound(blackOffsets) Then
        Return -1
    End If
    Dim As Integer pitch = basePitch + blackOffsets(blackIndex)
    If pitch < 0 OrElse pitch > 127 Then
        Return -1
    End If
    Return pitch
End Function


Public Function keyboardControls_BlackLeft( _
    ByVal blackIndex As Integer _
) As Integer
    Dim As Integer precedingWhite(0 To OSE_KEYBOARD_BLACK_KEY_COUNT - 1) = _
        {0, 1, 3, 4, 5, 7, 8, 10, 11, 12}
    If blackIndex < 0 OrElse blackIndex > UBound(precedingWhite) Then
        Return -1
    End If
    Return OSE_KEYBOARD_LEFT + _
        (precedingWhite(blackIndex) + 1) * OSE_KEYBOARD_WHITE_KEY_WIDTH - _
        OSE_KEYBOARD_BLACK_KEY_WIDTH \ 2
End Function


Public Function keyboardControls_PitchAtPoint( _
    ByVal basePitch As Integer, _
    ByVal localX As Integer, _
    ByVal localY As Integer _
) As Integer
    Dim As Integer pianoWidth = OSE_KEYBOARD_WHITE_KEY_COUNT * _
        OSE_KEYBOARD_WHITE_KEY_WIDTH
    If localX < OSE_KEYBOARD_LEFT OrElse _
        localX >= OSE_KEYBOARD_LEFT + pianoWidth OrElse _
        localY < OSE_KEYBOARD_TOP OrElse _
        localY >= OSE_KEYBOARD_TOP + OSE_KEYBOARD_WHITE_KEY_HEIGHT Then
        Return -1
    End If

    If localY < OSE_KEYBOARD_TOP + OSE_KEYBOARD_BLACK_KEY_HEIGHT Then
        For blackIndex As Integer = 0 To OSE_KEYBOARD_BLACK_KEY_COUNT - 1
            Dim As Integer blackLeft = keyboardControls_BlackLeft(blackIndex)
            If localX >= blackLeft AndAlso _
                localX < blackLeft + OSE_KEYBOARD_BLACK_KEY_WIDTH Then
                Return keyboardControls_BlackPitch(basePitch, blackIndex)
            End If
        Next
    End If

    Dim As Integer whiteIndex = _
        (localX - OSE_KEYBOARD_LEFT) \ OSE_KEYBOARD_WHITE_KEY_WIDTH
    Return keyboardControls_WhitePitch(basePitch, whiteIndex)
End Function

' -------------------------------------------------------------------------
' Printed PC-key legend
' -------------------------------------------------------------------------

Public Function keyboardControls_KeyLabel(ByVal noteOffset As Integer) As String
    Dim As String labels(0 To OSE_KEYBOARD_NOTE_COUNT - 1) = { _
        "Z", "S", "X", "D", "C", "V", "G", "B", "H", "N", "J", "M", _
        "Q", "2", "W", "3", "E", "R", "5", "T", "6", "Y", "7", "U" _
    }
    If noteOffset < 0 OrElse noteOffset > UBound(labels) Then
        Return ""
    End If
    Return labels(noteOffset)
End Function

/' end of keyboard_controls.bas '/
