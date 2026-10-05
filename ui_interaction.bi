/'
    Project: OpenSesh
    ---------------------------

    File: ui_interaction.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: uiInteraction_* preference/metric operations with OseUiInteractionMetrics.

    Purpose:

        Declare the platform-neutral interaction profiles used by the editor.

    Responsibilities:

        - identify precise-pointer and coarse-pointer interface modes
        - expose complete geometry for the shared desktop and touch layouts
        - parse and format the persistent interaction preference

    This file intentionally does NOT contain:

        - Android, Windows, or Linux conditionals
        - widget creation or application-global state
        - touch-contact polling or gesture recognition
'/

#ifndef __OSE_UI_INTERACTION_BI__
#define __OSE_UI_INTERACTION_BI__

Const OSE_UI_INTERACTION_FINE As Integer = 0
Const OSE_UI_INTERACTION_TOUCH As Integer = 1
Const OSE_UI_INTERACTION_COUNT As Integer = 2

Const OSE_UI_FILE_BUTTON_COUNT As Integer = 3
Const OSE_UI_TRANSPORT_BUTTON_COUNT As Integer = 7

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseUiInteractionMetrics
    As Integer menuHeight
    As Integer menuItemHeight
    As Integer toolbarTop
    As Integer toolbarHeight
    As Integer toolbarButtonTopInset
    As Integer toolbarButtonHeight
    As Integer topHeight
    As Integer scoreTop
    As Integer scoreScrollbarSize
    As Integer scoreRailLeft
    As Integer scoreRailFirstTop
    As Integer scoreRailWidth
    As Integer scoreRailHeight
    As Integer scoreRailStep
    As Integer scorePaletteLeft
    As Integer scorePaletteTop
    As Integer scorePaletteColumnWidth
    As Integer scorePaletteRowHeight
    As Integer scorePaletteFaceWidth
    As Integer scorePaletteFaceHeight
    As Integer scorePaletteWidth
    As Integer scorePaletteHeight
    As Integer dragThreshold
    As Integer fileButtonLeft(0 To OSE_UI_FILE_BUTTON_COUNT - 1)
    As Integer fileButtonWidth(0 To OSE_UI_FILE_BUTTON_COUNT - 1)
    As Integer transportButtonLeft(0 To OSE_UI_TRANSPORT_BUTTON_COUNT - 1)
    As Integer transportButtonWidth(0 To OSE_UI_TRANSPORT_BUTTON_COUNT - 1)
End Type

Declare Sub uiInteraction_Metrics( _
    ByRef metrics As OseUiInteractionMetrics, _
    ByVal interactionMode As Integer _
)

Declare Function uiInteraction_Parse( _
    ByVal modeText As String, _
    ByRef interactionMode As Integer _
) As Integer

Declare Function uiInteraction_PreferenceText( _
    ByVal interactionMode As Integer _
) As String

Declare Function uiInteraction_Name( _
    ByVal interactionMode As Integer _
) As String

#endif

/' end of ui_interaction.bi '/
