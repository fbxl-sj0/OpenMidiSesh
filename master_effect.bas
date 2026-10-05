/'
    Project: OpenSesh
    ---------------------------

    File: master_effect.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements master_effect.bi; declarations there define the shared interface.

    Purpose:

        Turn the master Wet and Feedback controls into a real stereo echo on
        the completed sfxlib mix.

    Responsibilities:

        - clamp normalized UI values before they reach the audio library
        - keep effect parameters inside the documented sfxlib ranges
        - disable and clear the delay line when Wet reaches zero
        - report effect initialization failures to the caller

    This file intentionally does NOT contain:

        - application status messages
        - UI coordinates or drawing
        - note, sample, or MIDI channel state
'/

#lang "fb"

#inclib "sfx"
#include once "master_effect.bi"

#Ifndef OSE_SFX_ECHO_AVAILABLE
#Define OSE_SFX_ECHO_AVAILABLE 1
#EndIf

' These are the stable public C aliases behind sfxlib_effects.bi. Declaring
' only the three calls owned by this adapter keeps its dependency boundary
' explicit and allows the module to remain independently lintable.
#If OSE_SFX_ECHO_AVAILABLE <> 0
Declare Function fb_sfxEchoCmd CDecl Alias "fb_sfxEchoCmd" ( _
    ByVal wet As Single, _
    ByVal delaySeconds As Single, _
    ByVal feedback As Single _
) As Long
Declare Sub fb_sfxEchoReset CDecl Alias "fb_sfxEchoReset" ()
Declare Function fb_sfxEchoEnabled CDecl Alias "fb_sfxEchoEnabled" () As Long
#EndIf

' -------------------------------------------------------------------------
' Parameter mapping
' -------------------------------------------------------------------------

Private Function masterEffect_ClampKnob(ByVal knobValue As Single) As Single
    If knobValue <= 0.0 Then
        Return 0.0
    End If
    If knobValue >= 1.0 Then
        Return 1.0
    End If
    Return knobValue
End Function


Public Sub masterEffect_Calculate( _
    ByRef settings As OseMasterEffectSettings, _
    ByVal wetKnob As Single, _
    ByVal feedbackKnob As Single _
)
    Dim As OseMasterEffectSettings emptySettings
    settings = emptySettings

    wetKnob = masterEffect_ClampKnob(wetKnob)
    feedbackKnob = masterEffect_ClampKnob(feedbackKnob)

    ' Half-wet is the practical maximum for an editor monitor mix. The fixed
    ' 140 ms delay remains clearly audible while keeping the second knob free
    ' to control the length of the repeat tail directly.
    settings.wet = wetKnob * 0.50
    settings.delaySeconds = 0.14
    settings.feedback = feedbackKnob * 0.75
    settings.enabled = IIf(settings.wet > 0.0001, -1, 0)
End Sub

' -------------------------------------------------------------------------
' sfxlib effect lifecycle
' -------------------------------------------------------------------------

Public Function masterEffect_Apply( _
    ByVal wetKnob As Single, _
    ByVal feedbackKnob As Single, _
    ByRef errorText As String _
) As Integer
    errorText = ""
    Dim As OseMasterEffectSettings settings
    masterEffect_Calculate settings, wetKnob, feedbackKnob

#If OSE_SFX_ECHO_AVAILABLE = 0
    If settings.enabled <> 0 Then
        errorText = "The audio backend does not provide a master echo."
        Return 0
    End If
    Return -1
#Else
    If settings.enabled = 0 Then
        fb_sfxEchoReset()
        Return -1
    End If

    If fb_sfxEchoCmd(settings.wet, settings.delaySeconds, _
        settings.feedback) <> 0 Then
        errorText = "sfxlib could not apply the master echo settings."
        Return 0
    End If
    Return -1
#EndIf
End Function


Public Sub masterEffect_Reset()
#If OSE_SFX_ECHO_AVAILABLE <> 0
    fb_sfxEchoReset()
#EndIf
End Sub


Public Function masterEffect_IsAvailable() As Integer
#If OSE_SFX_ECHO_AVAILABLE <> 0
    Return -1
#Else
    Return 0
#EndIf
End Function


Public Function masterEffect_IsEnabled() As Integer
#If OSE_SFX_ECHO_AVAILABLE <> 0
    Return IIf(fb_sfxEchoEnabled() <> 0, -1, 0)
#Else
    Return 0
#EndIf
End Function

/' end of master_effect.bas '/
