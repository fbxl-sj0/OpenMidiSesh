/'
    Project: OpenSesh
    ---------------------------

    File: tests/mixer_controls_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove that every visible mixer fader, knob, and M/S/R button maps to
        the semantic control and channel printed beside it.

    Responsibilities:

        - probe all seven controls on every one of sixteen channel strips
        - probe the master fader, Wet knob, and Feedback knob
        - probe the responsive previous/next channel-page controls
        - verify normalized endpoint values and responsive channel paging
        - reject coordinates outside the mixer controls
        - require finger-sized mixer targets in the touch profile

    This file intentionally does NOT contain:

        - MIDI mutation
        - audio output
        - graphical rendering
'/

#lang "fb"

#include once "../src/mixer_controls.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Sub test_ExpectHit( _
    ByRef layout As OseMixerControlLayout, _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer, _
    ByVal expectedKind As Integer, _
    ByVal expectedChannel As Integer _
)
    Dim As OseMixerControlHit controlHit
    mixerControls_HitTest controlHit, layout, pointerX, pointerY
    If controlHit.kind <> expectedKind OrElse _
        controlHit.channelIndex <> expectedChannel Then
        test_Fail "wrong control at channel " + Str(expectedChannel) + _
            ", kind " + Str(expectedKind)
    End If
End Sub


Dim As OseMixerControlLayout layout
Dim As OseMixerControlHit controlHit
mixerControls_CalculateLayout layout, 1280, 720, 0
If layout.visibleCount <> OSE_MIXER_CHANNEL_COUNT OrElse _
    layout.firstChannel <> 0 Then _
    test_Fail "normal window did not expose all sixteen channel strips"

For channelIndex As Integer = 0 To OSE_MIXER_CHANNEL_COUNT - 1
    Dim As Integer slotIndex = channelIndex - layout.firstChannel
    Dim As Integer stripLeft = mixerControls_StripLeft(layout, slotIndex)
    Dim As Integer stripRight = mixerControls_StripRight(layout, slotIndex)
    Dim As Integer faderX = mixerControls_ChannelFaderX(layout, slotIndex)
    Dim As Integer stripWidth = stripRight - stripLeft + 1

    test_ExpectHit layout, faderX, (layout.faderTop + layout.faderBottom) \ 2, _
        OSE_MIXER_CONTROL_CHANNEL_FADER, channelIndex
    For knobIndex As Integer = 0 To 2
        Dim As Integer knobX = stripLeft + _
            ((knobIndex * 2 + 1) * stripWidth) \ 6
        test_ExpectHit layout, knobX, layout.knobTop + 3, _
            OSE_MIXER_CONTROL_CHANNEL_CHORUS + knobIndex, channelIndex
        Dim As Integer knobCellLeft = stripLeft + _
            (knobIndex * stripWidth) \ 3
        Dim As Integer knobCellRight = stripLeft + _
            ((knobIndex + 1) * stripWidth) \ 3 - 1
        test_ExpectHit layout, knobCellLeft, layout.knobTop + 3, _
            OSE_MIXER_CONTROL_CHANNEL_CHORUS + knobIndex, channelIndex
        test_ExpectHit layout, knobCellRight, layout.knobTop + 3, _
            OSE_MIXER_CONTROL_CHANNEL_CHORUS + knobIndex, channelIndex
        mixerControls_HitTest controlHit, layout, knobCellLeft, _
            layout.knobTop + 3
        If Abs(controlHit.normalizedValue) > 0.0001 Then _
            test_Fail "knob left edge did not map to zero"
        mixerControls_HitTest controlHit, layout, knobCellRight, _
            layout.knobTop + 3
        If Abs(controlHit.normalizedValue - 1.0) > 0.0001 Then _
            test_Fail "knob right edge did not map to full value"
    Next
    For buttonIndex As Integer = 0 To 2
        Dim As Integer buttonX = stripLeft + _
            ((buttonIndex * 2 + 1) * (layout.stripWidth - 2)) \ 6
        test_ExpectHit layout, buttonX, layout.buttonTop + 3, _
            OSE_MIXER_CONTROL_CHANNEL_MUTE + buttonIndex, channelIndex
    Next
Next

test_ExpectHit layout, layout.masterLeft + 31, layout.faderTop, _
    OSE_MIXER_CONTROL_MASTER_FADER, -1
test_ExpectHit layout, layout.masterLeft + 103, layout.faderTop + 22, _
    OSE_MIXER_CONTROL_MASTER_WET, -1
test_ExpectHit layout, layout.masterLeft + 128, layout.faderTop + 22, _
    OSE_MIXER_CONTROL_MASTER_FEEDBACK, -1
mixerControls_HitTest controlHit, layout, layout.pagePreviousLeft + 2, _
    layout.pageButtonTop + 2
If controlHit.kind <> OSE_MIXER_CONTROL_NONE Then _
    test_Fail "full-width layout exposed an unnecessary page control"

mixerControls_HitTest controlHit, layout, layout.masterLeft + 31, _
    layout.faderTop
If Abs(controlHit.normalizedValue - 1.0) > 0.0001 Then _
    test_Fail "master fader top did not map to full volume"
mixerControls_HitTest controlHit, layout, layout.masterLeft + 31, _
    layout.faderBottom
If Abs(controlHit.normalizedValue) > 0.0001 Then _
    test_Fail "master fader bottom did not map to silence"
mixerControls_HitTest controlHit, layout, layout.masterLeft + 127, _
    layout.faderTop + 22
If Abs(controlHit.normalizedValue - 1.0) > 0.0001 Then _
    test_Fail "Wet knob right edge did not map to full value"
If Abs(mixerControls_ValueForControl(layout, _
    OSE_MIXER_CONTROL_MASTER_FADER, -1, 0, layout.faderTop - 100) - 1.0) _
    > 0.0001 OrElse _
    Abs(mixerControls_ValueForControl(layout, _
        OSE_MIXER_CONTROL_MASTER_WET, -1, layout.masterLeft, 0)) > 0.0001 _
    Then test_Fail "drag values outside a control were not clamped"

mixerControls_CalculateLayout layout, 600, 480, 15
If layout.visibleCount >= OSE_MIXER_CHANNEL_COUNT OrElse _
    layout.firstChannel + layout.visibleCount <> OSE_MIXER_CHANNEL_COUNT Then _
    test_Fail "narrow layout did not keep the selected last channel visible"
test_ExpectHit layout, layout.pagePreviousLeft + 2, _
    layout.pageButtonTop + 2, OSE_MIXER_CONTROL_PAGE_PREVIOUS, -1
test_ExpectHit layout, layout.pageNextLeft + 2, _
    layout.pageButtonTop + 2, OSE_MIXER_CONTROL_PAGE_NEXT, -1
If mixerControls_ChannelAtX(layout, layout.mixerLeft - 1) <> -1 OrElse _
    mixerControls_ChannelAtX(layout, layout.masterLeft) <> -1 Then _
    test_Fail "coordinates outside channel strips selected a channel"
mixerControls_HitTest controlHit, layout, 0, 0
If controlHit.kind <> OSE_MIXER_CONTROL_NONE Then _
    test_Fail "coordinate outside the mixer selected a control"

mixerControls_CalculateLayoutForInteraction layout, 1280, 720, 15, _
    OSE_UI_INTERACTION_TOUCH
If layout.stripWidth < 88 OrElse layout.buttonHeight < 32 OrElse _
    layout.knobBottom - layout.knobTop < 40 OrElse _
    layout.pageButtonWidth < 40 Then _
    test_Fail "touch mixer targets are not finger-sized"
If layout.visibleCount >= OSE_MIXER_CHANNEL_COUNT OrElse _
    layout.firstChannel + layout.visibleCount <> OSE_MIXER_CHANNEL_COUNT Then _
    test_Fail "touch mixer paging did not keep the selected channel visible"
test_ExpectHit layout, layout.pagePreviousLeft + layout.pageButtonWidth - 1, _
    layout.pageButtonTop + layout.pageButtonHeight - 1, _
    OSE_MIXER_CONTROL_PAGE_PREVIOUS, -1
test_ExpectHit layout, layout.pageNextLeft + layout.pageButtonWidth - 1, _
    layout.pageButtonTop + layout.pageButtonHeight - 1, _
    OSE_MIXER_CONTROL_PAGE_NEXT, -1
Dim As Integer touchStripLeft = mixerControls_StripLeft(layout, 0)
Dim As Integer touchStripRight = mixerControls_StripRight(layout, 0)
For buttonIndex As Integer = 0 To 2
    Dim As Integer buttonX = touchStripLeft + _
        ((buttonIndex * 2 + 1) * (touchStripRight - touchStripLeft + 1)) \ 6
    test_ExpectHit layout, buttonX, layout.buttonTop + layout.buttonHeight - 1, _
        OSE_MIXER_CONTROL_CHANNEL_MUTE + buttonIndex, layout.firstChannel
Next

Print "mixer_controls=ok"
Print "channel_controls="; OSE_MIXER_CHANNEL_COUNT * 7; _
    " master_controls=3 page_controls=2 profiles=2"
End 0

/' end of tests/mixer_controls_smoke.bas '/
