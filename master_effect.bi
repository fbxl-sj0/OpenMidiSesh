/'
    Project: OpenSesh
    ---------------------------

    File: master_effect.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: masterEffect_* controls with OseMasterEffectSettings.

    Purpose:

        Declare the editor's bounded whole-mix echo controls.

    Responsibilities:

        - map normalized Wet and Feedback knobs to safe sfxlib settings
        - enable, update, and disable the whole-mix effect
        - report whether the linked audio backend provides the effect
        - expose calculated settings for deterministic tests

    This file intentionally does NOT contain:

        - mixer hit testing or rendering
        - per-channel MIDI reverb and chorus controllers
        - playback scheduling
'/

#ifndef __OSE_MASTER_EFFECT_BI__
#define __OSE_MASTER_EFFECT_BI__

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseMasterEffectSettings
    As Integer enabled
    As Single wet
    As Single delaySeconds
    As Single feedback
End Type

Declare Sub masterEffect_Calculate( _
    ByRef settings As OseMasterEffectSettings, _
    ByVal wetKnob As Single, _
    ByVal feedbackKnob As Single _
)

Declare Function masterEffect_Apply( _
    ByVal wetKnob As Single, _
    ByVal feedbackKnob As Single, _
    ByRef errorText As String _
) As Integer

Declare Sub masterEffect_Reset()
Declare Function masterEffect_IsAvailable() As Integer
Declare Function masterEffect_IsEnabled() As Integer

#endif

/' end of master_effect.bi '/
