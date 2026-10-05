/'
    Project: OpenSesh
    ---------------------------

    File: tests/master_effect_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify that both visible master-effect knobs map to a working sfxlib
        effect and that a zero Wet setting disables it again.

    Responsibilities:

        - test knob clamping and documented parameter bounds
        - enable the real whole-mix effect through the production adapter
        - verify the effect reports enabled, then reset it cleanly

    This file intentionally does NOT contain:

        - audio capture or audible-output assumptions
        - mixer drawing
        - MIDI playback
'/

#lang "fb"

#include once "../src/master_effect.bi"
#include once "../src/sfx_runtime.bi"

Private Sub test_Fail(ByVal messageText As String)
    masterEffect_Reset()
    sfxRuntime_Shutdown()
    Print "FAIL: "; messageText
    End 1
End Sub


Dim As OseMasterEffectSettings settings
masterEffect_Calculate settings, 0.40, 0.60
If Abs(settings.wet - 0.20) > 0.0001 Then _
    test_Fail "Wet knob mapping changed"
If Abs(settings.delaySeconds - 0.14) > 0.0001 Then _
    test_Fail "echo delay changed"
If Abs(settings.feedback - 0.45) > 0.0001 Then _
    test_Fail "Feedback knob mapping changed"
If settings.enabled = 0 Then
    test_Fail "nonzero Wet did not enable the effect"
End If

masterEffect_Calculate settings, 2.0, -1.0
If Abs(settings.wet - 0.50) > 0.0001 OrElse _
    Abs(settings.feedback) > 0.0001 Then _
    test_Fail "out-of-range knob values were not clamped"

Dim As String errorText
If Not masterEffect_Apply(0.40, 0.60, errorText) Then _
    test_Fail "effect apply failed: " + errorText
If masterEffect_IsEnabled() = 0 Then _
    test_Fail "sfxlib did not report the master effect as enabled"

If Not masterEffect_Apply(0.0, 0.60, errorText) Then _
    test_Fail "zero-Wet reset failed: " + errorText
If masterEffect_IsEnabled() <> 0 Then _
    test_Fail "zero Wet left the master effect enabled"

sfxRuntime_Shutdown()
sfxRuntime_Shutdown()
Print "master_effect=ok"
Print "wet=0.20 feedback=0.45 delay=0.14"
End 0

/' end of tests/master_effect_smoke.bas '/
