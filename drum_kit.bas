/'
    Project: OpenSesh
    ---------------------------

    File: drum_kit.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements drum_kit.bi; declarations there define the shared interface.

    Purpose:

        Keep drum-pad drawing, pointer input, and keyboard input on one
        portable percussion map.

    Responsibilities:

        - map twelve pads to standard General MIDI percussion notes
        - expose matching spatial key labels
        - divide a bounded surface into evenly distributed touch targets
        - reject points in pad gutters or outside the surface
        - describe the three supported strike velocities

    This file intentionally does NOT contain:

        - application or modal-window state
        - audio voices
        - live-recording state
'/

#lang "fb"

#include once "drum_kit.bi"

' -------------------------------------------------------------------------
' General MIDI kit map
' -------------------------------------------------------------------------

Public Function drumKit_Pitch(ByVal padIndex As Integer) As Integer
    Dim As Integer pitches(0 To OSE_DRUM_PAD_COUNT - 1) = { _
        49, 51, 46, 54, _
        50, 47, 43, 39, _
        36, 38, 37, 42 _
    }
    If padIndex < 0 OrElse padIndex > UBound(pitches) Then
        Return -1
    End If
    Return pitches(padIndex)
End Function


Public Function drumKit_Name(ByVal padIndex As Integer) As String
    Dim As String names(0 To OSE_DRUM_PAD_COUNT - 1) = { _
        "Crash", "Ride", "Open Hi-Hat", "Tambourine", _
        "High Tom", "Mid Tom", "Low Tom", "Hand Clap", _
        "Kick", "Snare", "Side Stick", "Closed Hi-Hat" _
    }
    If padIndex < 0 OrElse padIndex > UBound(names) Then
        Return ""
    End If
    Return names(padIndex)
End Function


Public Function drumKit_KeyLabel(ByVal padIndex As Integer) As String
    Dim As String labels(0 To OSE_DRUM_PAD_COUNT - 1) = { _
        "1", "2", "3", "4", _
        "Q", "W", "E", "R", _
        "A", "S", "D", "F" _
    }
    If padIndex < 0 OrElse padIndex > UBound(labels) Then
        Return ""
    End If
    Return labels(padIndex)
End Function


Public Function drumKit_PadForKeyLabel(ByVal keyLabel As String) As Integer
    Dim As String wantedLabel = UCase(Trim(keyLabel))
    If Len(wantedLabel) <> 1 Then
        Return -1
    End If
    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        If drumKit_KeyLabel(padIndex) = wantedLabel Then
            Return padIndex
        End If
    Next
    Return -1
End Function


Public Function drumKit_VelocityName(ByVal velocity As Integer) As String
    Select Case velocity
        Case OSE_DRUM_VELOCITY_SOFT
            Return "Soft"
        Case OSE_DRUM_VELOCITY_MEDIUM
            Return "Medium"
        Case OSE_DRUM_VELOCITY_HARD
            Return "Hard"
    End Select
    Return ""
End Function

' -------------------------------------------------------------------------
' Responsive pad geometry
' -------------------------------------------------------------------------

Private Function drumKit_DistributedOffset( _
    ByVal itemIndex As Integer, _
    ByVal baseSize As Integer, _
    ByVal remainder As Integer, _
    ByVal gapSize As Integer _
) As Integer
    Dim As Integer precedingExtra = itemIndex
    If precedingExtra > remainder Then
        precedingExtra = remainder
    End If
    Return itemIndex * (baseSize + gapSize) + precedingExtra
End Function


Public Sub drumKit_PadRectangle( _
    ByVal padIndex As Integer, _
    ByVal surfaceX As Integer, _
    ByVal surfaceY As Integer, _
    ByVal surfaceWidth As Integer, _
    ByVal surfaceHeight As Integer, _
    ByRef padRectangle As OseDrumPadRectangle _
)
    padRectangle.x = 0
    padRectangle.y = 0
    padRectangle.width = 0
    padRectangle.height = 0

    If padIndex < 0 OrElse padIndex >= OSE_DRUM_PAD_COUNT Then
        Exit Sub
    End If
    Dim As Integer horizontalGutters = _
        (OSE_DRUM_COLUMN_COUNT - 1) * OSE_DRUM_PAD_GAP
    Dim As Integer verticalGutters = _
        (OSE_DRUM_ROW_COUNT - 1) * OSE_DRUM_PAD_GAP
    Dim As Integer minimumWidth = _
        OSE_DRUM_COLUMN_COUNT * OSE_DRUM_MINIMUM_PAD_SIZE + horizontalGutters
    Dim As Integer minimumHeight = _
        OSE_DRUM_ROW_COUNT * OSE_DRUM_MINIMUM_PAD_SIZE + verticalGutters
    If surfaceWidth < minimumWidth OrElse surfaceHeight < minimumHeight Then
        Exit Sub
    End If

    Dim As Integer availableWidth = surfaceWidth - horizontalGutters
    Dim As Integer availableHeight = surfaceHeight - verticalGutters
    Dim As Integer baseWidth = availableWidth \ OSE_DRUM_COLUMN_COUNT
    Dim As Integer baseHeight = availableHeight \ OSE_DRUM_ROW_COUNT
    Dim As Integer extraColumns = availableWidth Mod OSE_DRUM_COLUMN_COUNT
    Dim As Integer extraRows = availableHeight Mod OSE_DRUM_ROW_COUNT
    Dim As Integer columnIndex = padIndex Mod OSE_DRUM_COLUMN_COUNT
    Dim As Integer rowIndex = padIndex \ OSE_DRUM_COLUMN_COUNT

    padRectangle.x = surfaceX + drumKit_DistributedOffset( _
        columnIndex, baseWidth, extraColumns, OSE_DRUM_PAD_GAP)
    padRectangle.y = surfaceY + drumKit_DistributedOffset( _
        rowIndex, baseHeight, extraRows, OSE_DRUM_PAD_GAP)
    padRectangle.width = baseWidth
    If columnIndex < extraColumns Then
        padRectangle.width += 1
    End If
    padRectangle.height = baseHeight
    If rowIndex < extraRows Then
        padRectangle.height += 1
    End If
End Sub


Public Function drumKit_PadAtPoint( _
    ByVal pointX As Integer, _
    ByVal pointY As Integer, _
    ByVal surfaceX As Integer, _
    ByVal surfaceY As Integer, _
    ByVal surfaceWidth As Integer, _
    ByVal surfaceHeight As Integer _
) As Integer
    If pointX < surfaceX OrElse pointY < surfaceY OrElse _
        pointX >= surfaceX + surfaceWidth OrElse _
        pointY >= surfaceY + surfaceHeight Then
        Return -1
    End If

    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        Dim As OseDrumPadRectangle padRectangle
        drumKit_PadRectangle padIndex, surfaceX, surfaceY, surfaceWidth, _
            surfaceHeight, padRectangle
        If padRectangle.width > 0 AndAlso padRectangle.height > 0 AndAlso _
            pointX >= padRectangle.x AndAlso _
            pointX < padRectangle.x + padRectangle.width AndAlso _
            pointY >= padRectangle.y AndAlso _
            pointY < padRectangle.y + padRectangle.height Then
            Return padIndex
        End If
    Next
    Return -1
End Function

/' end of drum_kit.bas '/
