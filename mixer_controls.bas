/'
    Project: OpenSesh
    ---------------------------

    File: mixer_controls.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements mixer_controls.bi; declarations there define the shared interface.

    Purpose:

        Keep mixer drawing and pointer interaction on one bounded coordinate
        system so a visible control cannot silently acquire a dead hit area.

    Responsibilities:

        - calculate visible strips around the selected channel
        - derive channel and master control rectangles
        - return a semantic control identity for a pointer position
        - clamp fader and knob values to the documented zero-to-one range

    This file intentionally does NOT contain:

        - application globals
        - history or status handling
        - audio or MIDI side effects
'/

#lang "fb"

#include once "mixer_controls.bi"

Const OSE_MIXER_LEFT_INSET As Integer = 4
Const OSE_MIXER_MASTER_GAP As Integer = 3
Const OSE_MIXER_METER_WIDTH As Integer = 9

' -------------------------------------------------------------------------
' Bounded layout
' -------------------------------------------------------------------------

Public Sub mixerControls_CalculateLayout( _
    ByRef layout As OseMixerControlLayout, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal selectedChannel As Integer _
)
    mixerControls_CalculateLayoutForInteraction layout, screenWidth, _
        screenHeight, selectedChannel, OSE_UI_INTERACTION_FINE
End Sub


Public Sub mixerControls_CalculateLayoutForInteraction( _
    ByRef layout As OseMixerControlLayout, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal selectedChannel As Integer, _
    ByVal interactionMode As Integer _
)
    Dim As OseMixerControlLayout emptyLayout
    layout = emptyLayout

    If screenWidth < OSE_MIXER_MASTER_WIDTH + 16 Then
        screenWidth = OSE_MIXER_MASTER_WIDTH + 16
    End If
    If screenHeight < OSE_MIXER_HEIGHT Then
        screenHeight = OSE_MIXER_HEIGHT
    End If

    layout.mixerTop = screenHeight - OSE_MIXER_HEIGHT
    layout.mixerLeft = OSE_MIXER_LEFT_INSET
    layout.masterLeft = screenWidth - OSE_MIXER_MASTER_WIDTH
    layout.channelAreaWidth = layout.masterLeft - layout.mixerLeft - _
        OSE_MIXER_MASTER_GAP

    Dim As Integer minimumStripWidth = OSE_MIXER_MINIMUM_STRIP_WIDTH
    If interactionMode = OSE_UI_INTERACTION_TOUCH Then
        minimumStripWidth = OSE_MIXER_TOUCH_MINIMUM_STRIP_WIDTH
    End If
    layout.visibleCount = _
        (screenWidth - OSE_MIXER_MASTER_WIDTH - 8) \ _
        minimumStripWidth
    If layout.visibleCount < 1 Then
        layout.visibleCount = 1
    End If
    If layout.visibleCount > OSE_MIXER_CHANNEL_COUNT Then
        layout.visibleCount = OSE_MIXER_CHANNEL_COUNT
    End If

    If selectedChannel < 0 Then
        selectedChannel = 0
    End If
    If selectedChannel >= OSE_MIXER_CHANNEL_COUNT Then
        selectedChannel = OSE_MIXER_CHANNEL_COUNT - 1
    End If
    If selectedChannel >= layout.visibleCount Then
        layout.firstChannel = selectedChannel - layout.visibleCount + 1
    End If
    Dim As Integer maximumFirst = _
        OSE_MIXER_CHANNEL_COUNT - layout.visibleCount
    If layout.firstChannel > maximumFirst Then
        layout.firstChannel = maximumFirst
    End If
    If layout.firstChannel < 0 Then
        layout.firstChannel = 0
    End If

    layout.stripWidth = layout.channelAreaWidth \ layout.visibleCount
    If layout.stripWidth < 1 Then
        layout.stripWidth = 1
    End If
    layout.faderTop = layout.mixerTop + 52
    If interactionMode = OSE_UI_INTERACTION_TOUCH Then
        layout.faderBottom = screenHeight - 110
        layout.nameBoxTop = screenHeight - 105
        layout.knobTop = screenHeight - 82
        layout.knobBottom = screenHeight - 40
        layout.knobCenterY = layout.knobTop + 15
        layout.buttonTop = screenHeight - 36
        layout.buttonHeight = 32
        layout.pageButtonWidth = 40
        layout.pageButtonHeight = 20
    Else
        layout.faderBottom = screenHeight - 76
        layout.nameBoxTop = screenHeight - 71
        layout.knobTop = screenHeight - 62
        layout.knobBottom = screenHeight - 35
        layout.knobCenterY = layout.knobTop + 14
        layout.buttonTop = screenHeight - 21
        layout.buttonHeight = 16
        layout.pageButtonWidth = OSE_MIXER_PAGE_BUTTON_WIDTH
        layout.pageButtonHeight = OSE_MIXER_PAGE_BUTTON_HEIGHT
    End If
    layout.pagePreviousLeft = layout.mixerLeft + 4
    layout.pageNextLeft = layout.pagePreviousLeft + _
        layout.pageButtonWidth + 4
    layout.pageButtonTop = layout.mixerTop + 4
End Sub


Public Function mixerControls_ChannelAtX( _
    ByRef layout As OseMixerControlLayout, _
    ByVal pointerX As Integer _
) As Integer
    If layout.visibleCount <= 0 OrElse layout.stripWidth <= 0 Then
        Return -1
    End If
    If pointerX < layout.mixerLeft OrElse _
        pointerX >= layout.masterLeft - OSE_MIXER_MASTER_GAP Then
        Return -1
    End If

    Dim As Integer slotIndex = _
        (pointerX - layout.mixerLeft) \ layout.stripWidth
    If slotIndex < 0 Then
        Return -1
    End If
    If slotIndex >= layout.visibleCount Then
        slotIndex = layout.visibleCount - 1
    End If
    Return layout.firstChannel + slotIndex
End Function


Public Function mixerControls_StripLeft( _
    ByRef layout As OseMixerControlLayout, _
    ByVal slotIndex As Integer _
) As Integer
    If slotIndex < 0 OrElse slotIndex >= layout.visibleCount Then
        Return -1
    End If
    Return layout.mixerLeft + slotIndex * layout.stripWidth
End Function


Public Function mixerControls_StripRight( _
    ByRef layout As OseMixerControlLayout, _
    ByVal slotIndex As Integer _
) As Integer
    Dim As Integer stripLeft = mixerControls_StripLeft(layout, slotIndex)
    If stripLeft < 0 Then
        Return -1
    End If
    Return stripLeft + layout.stripWidth - 2
End Function


Public Function mixerControls_ChannelFaderX( _
    ByRef layout As OseMixerControlLayout, _
    ByVal slotIndex As Integer _
) As Integer
    Dim As Integer stripLeft = mixerControls_StripLeft(layout, slotIndex)
    Dim As Integer stripRight = mixerControls_StripRight(layout, slotIndex)
    If stripLeft < 0 OrElse stripRight <= stripLeft Then
        Return -1
    End If
    Dim As Integer meterLeft = stripRight - OSE_MIXER_METER_WIDTH - 4
    Return stripLeft + (meterLeft - stripLeft) \ 2
End Function

' -------------------------------------------------------------------------
' Semantic hit testing
' -------------------------------------------------------------------------

Private Function mixerControls_ClampRatio(ByVal ratio As Single) As Single
    If ratio < 0.0 Then
        Return 0.0
    End If
    If ratio > 1.0 Then
        Return 1.0
    End If
    Return ratio
End Function


Public Function mixerControls_ValueForControl( _
    ByRef layout As OseMixerControlLayout, _
    ByVal controlKind As Integer, _
    ByVal channelIndex As Integer, _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer _
) As Single
    Select Case controlKind
        Case OSE_MIXER_CONTROL_CHANNEL_FADER, _
             OSE_MIXER_CONTROL_MASTER_FADER
            Return mixerControls_ClampRatio( _
                CSng(layout.faderBottom - pointerY) / _
                CSng(layout.faderBottom - layout.faderTop))

        Case OSE_MIXER_CONTROL_CHANNEL_CHORUS To _
             OSE_MIXER_CONTROL_CHANNEL_PAN
            Dim As Integer slotIndex = channelIndex - layout.firstChannel
            Dim As Integer stripLeft = mixerControls_StripLeft(layout, slotIndex)
            Dim As Integer stripRight = mixerControls_StripRight(layout, slotIndex)
            If stripLeft < 0 OrElse stripRight <= stripLeft Then
                Return 0.0
            End If
            Dim As Integer knobIndex = _
                controlKind - OSE_MIXER_CONTROL_CHANNEL_CHORUS
            Dim As Integer knobCellLeft = stripLeft + _
                (knobIndex * (stripRight - stripLeft + 1)) \ 3
            Dim As Integer knobCellRight = stripLeft + _
                ((knobIndex + 1) * (stripRight - stripLeft + 1)) \ 3 - 1
            If knobCellRight <= knobCellLeft Then
                Return 0.5
            End If
            Return mixerControls_ClampRatio( _
                CSng(pointerX - knobCellLeft) / _
                CSng(knobCellRight - knobCellLeft))

        Case OSE_MIXER_CONTROL_MASTER_WET, _
             OSE_MIXER_CONTROL_MASTER_FEEDBACK
            Dim As Integer knobIndex = _
                controlKind - OSE_MIXER_CONTROL_MASTER_WET
            Dim As Integer knobCellLeft = layout.masterLeft + 103 + _
                knobIndex * 25
            Return mixerControls_ClampRatio( _
                CSng(pointerX - knobCellLeft) / 24.0)
    End Select
    Return 0.0
End Function


Public Sub mixerControls_HitTest( _
    ByRef controlHit As OseMixerControlHit, _
    ByRef layout As OseMixerControlLayout, _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer _
)
    Dim As OseMixerControlHit emptyHit
    controlHit = emptyHit
    controlHit.channelIndex = -1
    controlHit.slotIndex = -1

    If layout.visibleCount < OSE_MIXER_CHANNEL_COUNT AndAlso _
        pointerY >= layout.pageButtonTop AndAlso _
        pointerY < layout.pageButtonTop + layout.pageButtonHeight Then
        If pointerX >= layout.pagePreviousLeft AndAlso _
            pointerX < layout.pagePreviousLeft + layout.pageButtonWidth Then
            controlHit.kind = OSE_MIXER_CONTROL_PAGE_PREVIOUS
            Exit Sub
        End If
        If pointerX >= layout.pageNextLeft AndAlso _
            pointerX < layout.pageNextLeft + layout.pageButtonWidth Then
            controlHit.kind = OSE_MIXER_CONTROL_PAGE_NEXT
            Exit Sub
        End If
    End If

    Dim As Integer channelIndex = mixerControls_ChannelAtX(layout, pointerX)
    If channelIndex >= 0 Then
        Dim As Integer slotIndex = channelIndex - layout.firstChannel
        Dim As Integer stripLeft = mixerControls_StripLeft(layout, slotIndex)
        Dim As Integer stripRight = mixerControls_StripRight(layout, slotIndex)
        Dim As Integer faderX = mixerControls_ChannelFaderX(layout, slotIndex)
        controlHit.channelIndex = channelIndex
        controlHit.slotIndex = slotIndex

        If pointerX >= faderX - 9 AndAlso pointerX <= faderX + 9 AndAlso _
            pointerY >= layout.faderTop - 7 AndAlso _
            pointerY <= layout.faderBottom + 7 Then
            controlHit.kind = OSE_MIXER_CONTROL_CHANNEL_FADER
            controlHit.normalizedValue = mixerControls_ValueForControl( _
                layout, controlHit.kind, channelIndex, pointerX, pointerY)
            Exit Sub
        End If

        If pointerY >= layout.knobTop AndAlso pointerY < layout.knobBottom Then
            Dim As Integer knobIndex = -1
            Dim As Integer knobStripWidth = stripRight - stripLeft + 1
            ' Use the same integer boundaries as ValueForControl. Otherwise a
            ' remainder pixel at a cell edge can operate the neighboring knob.
            For candidateIndex As Integer = 0 To 2
                Dim As Integer knobCellLeft = stripLeft + _
                    (candidateIndex * knobStripWidth) \ 3
                Dim As Integer knobCellRight = stripLeft + _
                    ((candidateIndex + 1) * knobStripWidth) \ 3 - 1
                If pointerX >= knobCellLeft AndAlso _
                    pointerX <= knobCellRight Then
                    knobIndex = candidateIndex
                    Exit For
                End If
            Next
            If knobIndex < 0 Then
                Exit Sub
            End If
            controlHit.kind = OSE_MIXER_CONTROL_CHANNEL_CHORUS + knobIndex
            controlHit.normalizedValue = mixerControls_ValueForControl( _
                layout, controlHit.kind, channelIndex, pointerX, pointerY)
            Exit Sub
        End If

        If pointerY >= layout.buttonTop AndAlso _
            pointerY < layout.buttonTop + layout.buttonHeight Then
            Dim As Integer buttonWidth = stripRight - stripLeft + 1
            If buttonWidth <= 0 Then
                Exit Sub
            End If
            Dim As Integer buttonIndex = ((pointerX - stripLeft) * 3) \ _
                buttonWidth
            If buttonIndex < 0 Then
                buttonIndex = 0
            End If
            If buttonIndex > 2 Then
                buttonIndex = 2
            End If
            controlHit.kind = OSE_MIXER_CONTROL_CHANNEL_MUTE + buttonIndex
            Exit Sub
        End If
        Exit Sub
    End If

    Dim As Integer masterFaderX = layout.masterLeft + 31
    If pointerX >= masterFaderX - 10 AndAlso _
        pointerX <= masterFaderX + 10 AndAlso _
        pointerY >= layout.faderTop - 7 AndAlso _
        pointerY <= layout.faderBottom + 7 Then
        controlHit.kind = OSE_MIXER_CONTROL_MASTER_FADER
        controlHit.normalizedValue = mixerControls_ValueForControl( _
            layout, controlHit.kind, -1, pointerX, pointerY)
        Exit Sub
    End If

    Dim As Integer knobLeft = layout.masterLeft + 103
    Const knobCellWidth As Integer = 25
    If pointerX >= knobLeft AndAlso pointerX < knobLeft + knobCellWidth * 2 _
        AndAlso pointerY >= layout.faderTop + 20 AndAlso _
        pointerY < layout.faderTop + 44 Then
        Dim As Integer knobIndex = (pointerX - knobLeft) \ knobCellWidth
        controlHit.kind = OSE_MIXER_CONTROL_MASTER_WET + knobIndex
        controlHit.normalizedValue = mixerControls_ValueForControl( _
            layout, controlHit.kind, -1, pointerX, pointerY)
    End If
End Sub

/' end of mixer_controls.bas '/
