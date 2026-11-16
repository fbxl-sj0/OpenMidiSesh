/'
    Project: OpenMidiSesh
    ---------------------------

    File: ui_interaction.bas

    Copyright (C) 2026 OpenMidiSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements ui_interaction.bi; declarations there define the shared interface.

    Purpose:

        Define shared interface geometry for precise and coarse pointers.

    Responsibilities:

        - preserve the established desktop geometry for mouse and pen input
        - provide larger controls for fingers without naming a platform
        - validate persistent and environment-provided interaction names

    This file intentionally does NOT contain:

        - operating-system detection
        - editor widgets or rendering calls
        - contact history or gesture state
'/

#lang "fb"

#include once "ui_interaction.bi"

Const UI_INTERACTION_TOUCH_TRANSPORT_FIRST_LEFT As Integer = 198
Const UI_INTERACTION_TOUCH_TRANSPORT_STEP As Integer = 60
Const UI_INTERACTION_TOUCH_TRANSPORT_WIDTH As Integer = 56

' -------------------------------------------------------------------------
' Stable desktop geometry
' -------------------------------------------------------------------------

Private Sub uiInteraction_DesktopMetrics( _
    ByRef metrics As OseUiInteractionMetrics _
)
    metrics.menuHeight = 22
    metrics.menuItemHeight = 20
    metrics.toolbarTop = 24
    metrics.toolbarHeight = 46
    metrics.toolbarButtonTopInset = 3
    metrics.toolbarButtonHeight = 30
    metrics.topHeight = 78
    metrics.scoreTop = 82
    metrics.scoreScrollbarSize = 15
    metrics.scoreRailLeft = 6
    metrics.scoreRailFirstTop = 107
    metrics.scoreRailWidth = 82
    metrics.scoreRailHeight = 29
    metrics.scoreRailStep = 31
    metrics.scorePaletteLeft = 90
    metrics.scorePaletteTop = 138
    metrics.scorePaletteColumnWidth = 86
    metrics.scorePaletteRowHeight = 27
    metrics.scorePaletteFaceWidth = 84
    metrics.scorePaletteFaceHeight = 25
    metrics.scorePaletteWidth = 180
    metrics.scorePaletteHeight = 197
    metrics.dragThreshold = 4

    metrics.fileButtonLeft(0) = 8
    metrics.fileButtonLeft(1) = 58
    metrics.fileButtonLeft(2) = 108
    For buttonIndex As Integer = 0 To OSE_UI_FILE_BUTTON_COUNT - 1
        metrics.fileButtonWidth(buttonIndex) = 46
    Next

    Dim As Integer transportLeft(0 To OSE_UI_TRANSPORT_BUTTON_COUNT - 1) = { _
        168, 218, 270, 318, 366, 410, 460 _
    }
    Dim As Integer transportWidth(0 To OSE_UI_TRANSPORT_BUTTON_COUNT - 1) = { _
        46, 48, 44, 44, 40, 46, 46 _
    }
    For buttonIndex As Integer = 0 To OSE_UI_TRANSPORT_BUTTON_COUNT - 1
        metrics.transportButtonLeft(buttonIndex) = transportLeft(buttonIndex)
        metrics.transportButtonWidth(buttonIndex) = transportWidth(buttonIndex)
    Next
End Sub


' -------------------------------------------------------------------------
' Coarse-pointer geometry
' -------------------------------------------------------------------------

Private Sub uiInteraction_TouchMetrics( _
    ByRef metrics As OseUiInteractionMetrics _
)
    /'
        The coarse layout is intentionally expressed in framebuffer units.
        gfxlib maps those units to the physical display on every backend, so
        the application does not need Android density calls or platform UI.
    '/
    metrics.menuHeight = 38
    metrics.menuItemHeight = 44
    metrics.toolbarTop = 40
    metrics.toolbarHeight = 70
    metrics.toolbarButtonTopInset = 5
    metrics.toolbarButtonHeight = 56
    metrics.topHeight = 112
    metrics.scoreTop = 116
    metrics.scoreScrollbarSize = 28
    metrics.scoreRailLeft = 6
    metrics.scoreRailFirstTop = 141
    metrics.scoreRailWidth = 98
    metrics.scoreRailHeight = 44
    metrics.scoreRailStep = 48
    metrics.scorePaletteLeft = 110
    metrics.scorePaletteTop = 156
    metrics.scorePaletteColumnWidth = 120
    metrics.scorePaletteRowHeight = 38
    metrics.scorePaletteFaceWidth = 116
    metrics.scorePaletteFaceHeight = 36
    metrics.scorePaletteWidth = 248
    metrics.scorePaletteHeight = 274
    metrics.dragThreshold = 10

    metrics.fileButtonLeft(0) = 8
    metrics.fileButtonLeft(1) = 70
    metrics.fileButtonLeft(2) = 132
    For buttonIndex As Integer = 0 To OSE_UI_FILE_BUTTON_COUNT - 1
        metrics.fileButtonWidth(buttonIndex) = 58
    Next

    For buttonIndex As Integer = 0 To OSE_UI_TRANSPORT_BUTTON_COUNT - 1
        metrics.transportButtonLeft(buttonIndex) = _
            UI_INTERACTION_TOUCH_TRANSPORT_FIRST_LEFT + _
            buttonIndex * UI_INTERACTION_TOUCH_TRANSPORT_STEP
        metrics.transportButtonWidth(buttonIndex) = _
            UI_INTERACTION_TOUCH_TRANSPORT_WIDTH
    Next
End Sub


' -------------------------------------------------------------------------
' Public profile API
' -------------------------------------------------------------------------

Public Sub uiInteraction_Metrics( _
    ByRef metrics As OseUiInteractionMetrics, _
    ByVal interactionMode As Integer _
)
    Dim As OseUiInteractionMetrics emptyMetrics
    metrics = emptyMetrics
    metrics.scoreNoteLeft = 174

    If interactionMode = OSE_UI_INTERACTION_TOUCH Then
        uiInteraction_TouchMetrics metrics
    Else
        uiInteraction_DesktopMetrics metrics
    End If
End Sub


Public Sub uiInteraction_ViewportMetrics(ByRef metrics As OseUiInteractionMetrics, _
    ByVal interactionMode As Integer, ByVal viewportWidth As Integer)
    uiInteraction_Metrics metrics, interactionMode
    Dim As Integer firstTop = metrics.toolbarTop + metrics.toolbarButtonTopInset
    For i As Integer = 0 To OSE_UI_FILE_BUTTON_COUNT - 1
        metrics.fileButtonTop(i) = firstTop
    Next
    For i As Integer = 0 To OSE_UI_TRANSPORT_BUTTON_COUNT - 1
        metrics.transportButtonTop(i) = firstTop
    Next
    metrics.monitorLeft = 516
    metrics.monitorTop = firstTop
    metrics.inputLeft = 852
    metrics.inputTop = firstTop
    If interactionMode = OSE_UI_INTERACTION_FINE AndAlso viewportWidth >= 1040 Then
        ' Keep the desktop's musical-position readout. Wide windows fit the
        ' monitor after device setup; smaller desktop windows use the menu row.
        metrics.monitorLeft = 734
        metrics.monitorTop = 1
        If viewportWidth >= 1180 Then
            metrics.monitorLeft = 996
            metrics.monitorTop = firstTop
        End If
        Exit Sub
    End If

    ' Keep primary transport and device controls reachable without reducing
    ' touch targets. File commands and secondary transport remain in the menus.
    If viewportWidth < 320 Then viewportWidth = 320
    Dim As Integer oldTop = metrics.scoreTop
    Dim As Integer rowHeight = metrics.toolbarButtonHeight + 6
    If viewportWidth < 640 Then
        metrics.scoreNoteLeft = 112
        metrics.menuHeight *= 2
        metrics.toolbarTop = metrics.menuHeight + 2
    End If
    firstTop = metrics.toolbarTop + metrics.toolbarButtonTopInset
    Dim As Integer leftValue = 8
    Dim As Integer topValue = firstTop
    For i As Integer = 0 To OSE_UI_FILE_BUTTON_COUNT - 1
        metrics.fileButtonWidth(i) = 0
    Next
    For i As Integer = 0 To OSE_UI_TRANSPORT_BUTTON_COUNT - 1
        Dim As Integer widthValue = metrics.transportButtonWidth(i)
        If viewportWidth < 800 AndAlso (i = 2 OrElse i = 4 OrElse i = 6) Then
            metrics.transportButtonWidth(i) = 0
            Continue For
        End If
        If leftValue + widthValue > viewportWidth - 8 Then
            leftValue = 8
            topValue += rowHeight
        End If
        metrics.transportButtonLeft(i) = leftValue
        metrics.transportButtonTop(i) = topValue
        leftValue += widthValue + 6
    Next
    If leftValue + 92 > viewportWidth - 8 Then
        leftValue = 8
        topValue += rowHeight
    End If
    metrics.monitorLeft = leftValue
    metrics.monitorTop = topValue
    leftValue += 98
    If leftValue + 76 > viewportWidth - 8 Then
        leftValue = 8
        topValue += rowHeight
    End If
    metrics.inputLeft = leftValue
    metrics.inputTop = topValue
    metrics.toolbarHeight = topValue + metrics.toolbarButtonHeight + 6 - metrics.toolbarTop
    metrics.topHeight = metrics.toolbarTop + metrics.toolbarHeight + 2
    metrics.scoreTop = metrics.topHeight + 4
    Dim As Integer delta = metrics.scoreTop - oldTop
    metrics.scoreRailFirstTop += delta
    metrics.scorePaletteTop += delta
End Sub

Public Function uiInteraction_Parse( _
    ByVal modeText As String, _
    ByRef interactionMode As Integer _
) As Integer
    Select Case LCase(Trim(modeText))
        Case "fine", "mouse", "desktop"
            interactionMode = OSE_UI_INTERACTION_FINE
        Case "touch", "coarse"
            interactionMode = OSE_UI_INTERACTION_TOUCH
        Case Else
            Return 0
    End Select
    Return -1
End Function


Public Function uiInteraction_PreferenceText( _
    ByVal interactionMode As Integer _
) As String
    uiInteraction_PreferenceText = ""

    Select Case interactionMode
        Case OSE_UI_INTERACTION_FINE
            uiInteraction_PreferenceText = "fine"
        Case OSE_UI_INTERACTION_TOUCH
            uiInteraction_PreferenceText = "touch"
        Case Else
            Exit Function
    End Select
End Function


Public Function uiInteraction_Name( _
    ByVal interactionMode As Integer _
) As String
    If interactionMode = OSE_UI_INTERACTION_TOUCH Then
        Return "Touch"
    End If
    Return "Desktop"
End Function

/' end of ui_interaction.bas '/
