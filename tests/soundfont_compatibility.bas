/'
    Project: OpenSesh
    ---------------------------

    File: tests/soundfont_compatibility.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Exercise the native synth against a user-supplied General MIDI SF2.

    Responsibilities:

        - require complete General MIDI melodic and percussion preset coverage
        - resolve representative low, middle, and high notes for every program
        - render several instrument families and reject silent or invalid PCM
        - report bank metadata without copying the supplied SoundFont

    This file intentionally does NOT contain:

        - a bundled or downloaded third-party SoundFont
        - audio-device access
        - assumptions about a particular desktop environment
'/

#lang "fb"

#include once "../soundfont_bank.bi"
#include once "../soundfont_synth.bi"

Private Sub compatibility_Fail(ByVal messageText As String)
    soundfontSynth_Shutdown()
    Print "FAIL: "; messageText
    End 1
End Sub


Private Function compatibility_RenderPeak( _
    ByVal bankNumber As Integer, _
    ByVal programNumber As Integer, _
    ByVal keyNumber As Integer _
) As Single
    Const outputSampleRate As Integer = 48000
    Const frameCount As Integer = 24000
    Static As Single outputSamples(0 To frameCount * 2 - 1)
    Dim As OsePlaybackMixValues mixValues
    mixValues.channelGain = 0.9
    mixValues.meterGain = 0.9
    mixValues.voiceGain = 0.5
    If soundfontSynth_RenderPreview(0, keyNumber, bankNumber, programNumber, _
        8192, 0.25, mixValues, outputSampleRate, @outputSamples(0), _
        frameCount) = 0 Then Return -1.0
    Dim As Single peakValue
    For sampleIndex As Integer = 0 To frameCount * 2 - 1
        Dim As Single sampleValue = outputSamples(sampleIndex)
        If sampleValue <> sampleValue Then
            Return -1.0
        End If
        Dim As Single absoluteValue = Abs(sampleValue)
        If absoluteValue > peakValue Then
            peakValue = absoluteValue
        End If
    Next
    Return peakValue
End Function


Dim As String soundFontFilename = Trim(Command(1))
If soundFontFilename = "" Then
    Print "usage: soundfont_compatibility <general-midi-bank.sf2>"
    End 2
End If

Dim As String errorText
If soundfontBank_Load(soundFontFilename, errorText) = 0 Then _
    compatibility_Fail "SoundFont was rejected: " + errorText
If soundfontBank_GetName() = "" OrElse _
    soundfontBank_GetPresetCount() < 129 OrElse _
    soundfontBank_GetSampleHeaderCount() < 1 OrElse _
    soundfontBank_GetSamplePointCount() < 1 Then _
    compatibility_Fail "bank metadata is incomplete"

Dim As OseSoundFontVoiceRegion regions( _
    0 To OSE_SOUNDFONT_MAX_REGIONS_PER_NOTE - 1 _
)
Dim As Integer resolvedMelodicNotes
For programNumber As Integer = 0 To 127
    If soundfontBank_HasPreset(0, programNumber) = 0 Then _
        compatibility_Fail _
            "missing General MIDI program " + LTrim(Str(programNumber))
    For keyIndex As Integer = 0 To 2
        Dim As Integer keyNumbers(0 To 2) = {36, 60, 84}
        Dim As Integer regionCount = soundfontBank_Resolve( _
            0, programNumber, keyNumbers(keyIndex), 100, regions())
        If regionCount < 1 OrElse _
            regionCount > OSE_SOUNDFONT_MAX_REGIONS_PER_NOTE Then _
            compatibility_Fail _
                "unresolved program/key " + LTrim(Str(programNumber)) + _
                "/" + LTrim(Str(keyNumbers(keyIndex)))
        resolvedMelodicNotes += 1
    Next
Next

If soundfontBank_HasPreset(128, 0) = 0 Then _
    compatibility_Fail "missing General MIDI percussion preset"
Dim As Integer drumKeys(0 To 3) = {35, 38, 42, 49}
For keyIndex As Integer = 0 To 3
    If soundfontBank_Resolve(128, 0, drumKeys(keyIndex), 100, regions()) < 1 Then _
        compatibility_Fail _
            "unresolved percussion key " + LTrim(Str(drumKeys(keyIndex)))
Next

Dim As Integer renderPrograms(0 To 5) = {0, 24, 40, 56, 73, 118}
Dim As Single quietestPeak = 1.0
Dim As Single loudestPeak
For renderIndex As Integer = 0 To 5
    Dim As Single peakValue = compatibility_RenderPeak( _
        0, renderPrograms(renderIndex), 60)
    If peakValue < 0.0001 OrElse peakValue > 1.0 Then _
        compatibility_Fail _
            "invalid rendered peak for program " + _
            LTrim(Str(renderPrograms(renderIndex)))
    If peakValue < quietestPeak Then
        quietestPeak = peakValue
    End If
    If peakValue > loudestPeak Then
        loudestPeak = peakValue
    End If
Next
Dim As Single percussionPeak = compatibility_RenderPeak(128, 0, 38)
If percussionPeak < 0.0001 OrElse percussionPeak > 1.0 Then _
    compatibility_Fail "invalid rendered percussion peak"

Print "soundfont_compatibility=ok"
Print "bank_name="; soundfontBank_GetName()
Print "presets="; soundfontBank_GetPresetCount()
Print "sample_headers="; soundfontBank_GetSampleHeaderCount()
Print "sample_points="; soundfontBank_GetSamplePointCount()
Print "resolved_melodic_notes="; resolvedMelodicNotes
Print "quietest_peak="; quietestPeak
Print "loudest_peak="; loudestPeak
Print "percussion_peak="; percussionPeak
soundfontSynth_Shutdown()
End 0

/' end of tests/soundfont_compatibility.bas '/
