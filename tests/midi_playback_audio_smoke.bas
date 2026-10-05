/'
    Project: OpenSesh
    ---------------------------

    File: tests/midi_playback_audio_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Module API: Test executable accepting MIDI and WAV fixture paths; drives
        the software-synth capture through sfxlib's foreground-feed entry points.

    Purpose:

        Prove that notes parsed from a real MIDI file reach non-silent PCM
        through the same software-synth adapter used by the editor.

    Responsibilities:

        - save and reload a deterministic Standard MIDI fixture
        - schedule every editable note by tick time
        - route program, pitch, velocity, volume, expression, and pan
        - keep fallback voices attached to their source MIDI mixer channels
        - advance sfxlib deterministically without an audio device callback
        - validate the captured WAV and require a meaningful sample peak
        - retain audible sustained notes beyond eight seconds
        - write an AROS sidecar report when shell redirection drops Print output

    Resource ownership:

        - every file opened by this test is closed before its helper returns
        - sfxlib owns capture storage; the adapter stops capture before saving

    This file intentionally does NOT contain:

        - omaGUI or a desktop window
        - external MIDI hardware assumptions
        - a duplicate oscillator implementation
'/

#lang "fb"

#include once "../midi_model.bi"
#include once "../audio_tracks.bi"
#include once "../wav_export_sfx.bi"
#include once "../playback_mix.bi"
#include once "../playback_timing.bi"
#include once "../software_synth.bi"
#include once "../mixer_state.bi"

Const TEST_FEED_BLOCK_FRAMES As Long = 256
Const TEST_RENDER_TAIL_SECONDS As Double = 0.50

Declare Sub fb_sfxUpdate CDecl Alias "fb_sfxUpdate" (ByVal frames As Long)
Declare Sub fb_sfxForegroundFeedBegin CDecl _
    Alias "fb_sfxForegroundFeedBegin" ()
Declare Sub fb_sfxForegroundFeedEnd CDecl _
    Alias "fb_sfxForegroundFeedEnd" ()

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


#If Defined(__FB_AROS__)
Private Function test_WriteReport( _
    ByRef filename As String, _
    ByVal noteCount As Integer, _
    ByVal frameCount As Long, _
    ByVal peakValue As Integer, _
    ByVal underrunCount As ULongInt _
) As Integer
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Output As #fileNumber) <> 0 Then Return 0
    Print #fileNumber, "midi_playback_audio=ok"
    Print #fileNumber, "notes="; noteCount
    Print #fileNumber, "frames="; frameCount
    Print #fileNumber, "peak="; peakValue
    Print #fileNumber, "underruns="; underrunCount
    Close #fileNumber
    Return -1
End Function
#EndIf


Private Function test_WavePeak( _
    ByVal filename As String, _
    ByVal firstSample As LongInt = 0 _
) As Integer
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then
        Return -1
    End If

    Dim As LongInt fileLength = Lof(fileNumber)
    If fileLength <= 44 Then
        Close #fileNumber
        Return -1
    End If

    Dim As Integer peakValue
    Dim As LongInt sampleCount = (fileLength - 44) \ SizeOf(Short)
    If sampleCount <= 0 OrElse sampleCount > 2147483647 Then
        Close #fileNumber
        Return -1
    End If
    Dim As Short sampleValues()
    Redim sampleValues(0 To CInt(sampleCount - 1))
    If Get(#fileNumber, 45, sampleValues()) <> 0 Then
        Close #fileNumber
        Return -1
    End If
    Close #fileNumber

    If firstSample < 0 OrElse firstSample >= sampleCount Then
        Return -1
    End If
    For sampleIndex As LongInt = firstSample To sampleCount - 1
        Dim As Integer absoluteValue = CInt(sampleValues(sampleIndex))
        If absoluteValue < 0 Then
            absoluteValue = -absoluteValue
        End If
        If absoluteValue > peakValue Then
            peakValue = absoluteValue
        End If
    Next
    Return peakValue
End Function


Private Function test_ToneMagnitude( _
    ByRef filename As String, _
    ByVal sampleRate As Integer, _
    ByVal channelCount As Integer, _
    ByVal targetFrequency As Double, _
    ByVal firstFrame As LongInt, _
    ByVal frameCount As Integer _
) As Double
    If sampleRate <= 0 OrElse channelCount < 1 OrElse _
        targetFrequency <= 0.0 OrElse firstFrame < 0 OrElse _
        frameCount < 32 Then
        Return -1.0
    End If

    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then
        Return -1.0
    End If
    Dim As LongInt sampleCount = CLngInt(frameCount) * CLngInt(channelCount)
    Dim As Short samples()
    Redim samples(0 To CInt(sampleCount - 1))
    Dim As LongInt firstByte = 45 + firstFrame * _
        CLngInt(channelCount) * CLngInt(SizeOf(Short))
    If Get(#fileNumber, firstByte, samples()) <> 0 Then
        Close #fileNumber
        Return -1.0
    End If
    Close #fileNumber

    Dim As Double pi = 3.141592653589793
    Dim As Double omega = 2.0 * pi * targetFrequency / sampleRate
    Dim As Double coefficient = 2.0 * Cos(omega)
    Dim As Double previousSample
    Dim As Double previousPreviousSample
    For frameIndex As Integer = 0 To frameCount - 1
        Dim As Double currentSample = _
            CDbl(samples(frameIndex * channelCount)) + _
            coefficient * previousSample - previousPreviousSample
        previousPreviousSample = previousSample
        previousSample = currentSample
    Next
    Dim As Double power = previousSample * previousSample + _
        previousPreviousSample * previousPreviousSample - _
        coefficient * previousSample * previousPreviousSample
    If power < 0.0 Then power = 0.0
    Return Sqr(power)
End Function


Dim As String midiFilename = Trim(Command(1))
Dim As String outputFilename = Trim(Command(2))
If midiFilename = "" OrElse outputFilename = "" Then
    Print "usage: midi_playback_audio_smoke <input.mid> <output.wav>"
    End 2
End If

If softwareSynth_NoteFrequency(69) <> 440 OrElse _
    softwareSynth_NoteFrequencyWithBend(69, 8192) <> 440 OrElse _
    softwareSynth_NoteFrequencyWithBend(69, 0) <> 392 OrElse _
    softwareSynth_NoteFrequencyWithBend(69, 16383) <> 494 Then _
    test_Fail "software-synth MIDI pitch conversion was inaccurate"
If softwareSynth_NoteFrequency(-1) <> 20 OrElse _
    softwareSynth_NoteFrequency(128) <> _
        softwareSynth_NoteFrequency(127) OrElse _
    softwareSynth_NoteFrequencyWithBend(69, -1) <> _
        softwareSynth_NoteFrequencyWithBend(69, 0) OrElse _
    softwareSynth_NoteFrequencyWithBend(69, 20000) <> _
        softwareSynth_NoteFrequencyWithBend(69, 16383) Then _
    test_Fail "software-synth pitch bounds were not clamped"

Dim As MidiSummary fixtureSummary
If midi_AddTrack(fixtureSummary) <> 0 Then _
    test_Fail "could not create the MIDI fixture track"
If midi_AddEditableNote(fixtureSummary, 0, 0, 480, 60, 0, 100) < 0 OrElse _
    midi_AddEditableNote(fixtureSummary, 0, 0, 480, 64, 0, 100) < 0 OrElse _
    midi_AddEditableNote(fixtureSummary, 0, 0, 480, 72, 1, 96) < 0 OrElse _
    midi_AddEditableNote(fixtureSummary, 0, 480, 9600, 67, 0, 92) < 0 Then _
    test_Fail "could not create the MIDI fixture notes"
If Not midi_SetInitialTempoBpm(fixtureSummary, 120) OrElse _
    Not midi_SetChannelMix(fixtureSummary, 0, 104, 64) OrElse _
    Not midi_SetChannelMix(fixtureSummary, 1, 96, 100) Then _
    test_Fail "could not configure the MIDI fixture"
If Not midi_SaveDocument(fixtureSummary, midiFilename) Then _
    test_Fail "could not save the MIDI fixture"

Dim As MidiSummary summary
If midi_LoadSummary(summary, midiFilename) = 0 Then _
    test_Fail "MIDI load failed: " + summary.errorText
Dim As Integer noteCount = midi_GetEditableNoteCount()
If noteCount <> 4 Then
    test_Fail "fixture MIDI did not reload the chord, second channel, and sustained note"
End If

If noteCount > OSE_MAX_EDITABLE_NOTES Then _
    test_Fail "MIDI note count exceeded the bounded test storage"
Dim As MidiEditableNote notes()
Dim As Integer started()
Redim notes(0 To noteCount - 1)
Redim started(0 To noteCount - 1)
For noteIndex As Integer = 0 To noteCount - 1
    If midi_GetEditableNote(noteIndex, notes(noteIndex)) = 0 Then _
        test_Fail "editable note lookup failed"
Next

Dim As Double timelineSeconds = midi_TicksToSeconds( _
    summary, summary.durationTicks)
If timelineSeconds <= 0.0 Then
    test_Fail "MIDI timeline is empty"
End If
Dim As Double renderSeconds = timelineSeconds + TEST_RENDER_TAIL_SECONDS

SetEnviron "SFXLIB_DRIVER=null"
If LCase(Trim(Environ("SFXLIB_DRIVER"))) <> "null" Then _
    test_Fail "null output driver selection could not be established"
softwareSynth_Configure()
Dim As OseWavExportState exportState
wavExport_Initialize exportState
Dim As String errorText
If Not wavExport_Begin(exportState, outputFilename, _
    renderSeconds, errorText) Then _
    test_Fail "capture could not start: " + errorText

fb_sfxForegroundFeedBegin()
Dim As Long totalFrames = CLng(renderSeconds * CDbl(exportState.sampleRate))
Dim As Long currentFrame
Dim As Integer startedCount
While currentFrame < totalFrames
    Dim As Double currentSeconds = CDbl(currentFrame) / _
        CDbl(exportState.sampleRate)
    For noteIndex As Integer = 0 To noteCount - 1
        If started(noteIndex) <> 0 Then
            Continue For
        End If
        Dim As Double noteStartSeconds = midi_TicksToSeconds( _
            summary, notes(noteIndex).startTick)
        If noteStartSeconds > currentSeconds Then
            Continue For
        End If

        Dim As ULongInt noteEndTick = notes(noteIndex).startTick + _
            notes(noteIndex).durationTicks
        If noteEndTick < notes(noteIndex).startTick Then _
            noteEndTick = summary.durationTicks
        Dim As Double noteDuration = playbackTiming_WallDuration( _
            midi_TicksToSeconds(summary, noteEndTick), currentSeconds, 1.0)

        Dim As Integer channelIndex = notes(noteIndex).channel
        Dim As OsePlaybackMixValues mixValues
        playbackMix_Calculate mixValues, _
            summary.channelVolume(channelIndex), _
            summary.channelExpression(channelIndex), _
            summary.channelPan(channelIndex), notes(noteIndex).velocity, 1.0, -1
        Dim As OseSoftwareSynthPlayOptions playOptions
        playOptions.bankNumber = 0
        playOptions.fallbackVoiceChannel = -1
        If Not softwareSynth_PlayMidiNote(channelIndex, _
            notes(noteIndex).keyNumber, summary.channelProgram(channelIndex), _
            summary.channelPitchBend(channelIndex), CSng(noteDuration), _
            mixValues, playOptions) Then _
            test_Fail "production synth rejected a valid MIDI note"
        started(noteIndex) = -1
        startedCount += 1
    Next

    Dim As Long framesToFeed = TEST_FEED_BLOCK_FRAMES
    If framesToFeed > totalFrames - currentFrame Then _
        framesToFeed = totalFrames - currentFrame
    fb_sfxUpdate framesToFeed
    currentFrame += framesToFeed
Wend
fb_sfxForegroundFeedEnd()

If startedCount <> noteCount Then
    test_Fail "not every MIDI note was scheduled"
End If
Dim As ULongInt underrunCount
If Not wavExport_Finish(exportState, underrunCount, errorText) Then _
    test_Fail "capture could not finish: " + errorText

Dim As OseWaveInfo waveInfo
If Not audio_InspectWave(outputFilename, waveInfo) Then _
    test_Fail "captured MIDI output is not a valid PCM WAV"
Dim As Integer peakValue = test_WavePeak(outputFilename)
If peakValue < 200 Then _
    test_Fail "captured MIDI output is silent or below the useful test floor"
' At 120 BPM and 480 PPQN the final note sustains for ten seconds. Inspect
' PCM after nine seconds so a transport or synth duration clamp cannot hide
' behind the earlier, correctly rendered part of the file.
' Each factor is widened before multiplication.
' fblint: disable-next-line FBL-NUM-002 REASON: Both operands are widened before the sample-position multiplication.
Dim As LongInt sustainedStartSample = CLngInt(waveInfo.sampleRate) * _
    CLngInt(waveInfo.channelCount) * 9
If test_WavePeak(outputFilename, sustainedStartSample) < 200 Then _
    test_Fail "sustained MIDI note stopped before its score duration"

Dim As Double c4Magnitude = test_ToneMagnitude(outputFilename, _
    waveInfo.sampleRate, waveInfo.channelCount, 262.0, _
    CLngInt(waveInfo.sampleRate) * 4 / 100, _
    CInt(waveInfo.sampleRate) / 6)
Dim As Double e4Magnitude = test_ToneMagnitude(outputFilename, _
    waveInfo.sampleRate, waveInfo.channelCount, 330.0, _
    CLngInt(waveInfo.sampleRate) * 4 / 100, _
    CInt(waveInfo.sampleRate) / 6)
If c4Magnitude < 1000.0 OrElse e4Magnitude < 1000.0 OrElse _
    c4Magnitude < e4Magnitude * 0.20 Then
    test_Fail "same-channel chord did not retain both simultaneous pitches"
End If

Dim As Integer fallbackVoiceCounts(0 To 15)
For voiceIndex As Integer = 0 To OSE_SOFTWARE_SYNTH_VOICE_COUNT - 1
    Dim As Integer mixerChannel = _
        softwareSynth_MixerChannelForVoice(voiceIndex)
    If mixerChannel < 0 OrElse mixerChannel > 15 Then _
        test_Fail "fallback voice returned an invalid source MIDI channel"
    fallbackVoiceCounts(mixerChannel) += 1
Next
If fallbackVoiceCounts(0) <> 3 OrElse fallbackVoiceCounts(1) <> 1 Then _
    test_Fail "rotating fallback voices lost their source MIDI channel"

Dim As OseMixerChannelState mixerFixture
mixerState_Initialize mixerFixture
If mixerState_ToggleMute(mixerFixture, 1) = 0 Then _
    test_Fail "could not mute the second MIDI channel in the routing fixture"
For voiceIndex As Integer = 0 To OSE_SOFTWARE_SYNTH_VOICE_COUNT - 1
    Dim As Integer mixerChannel = _
        softwareSynth_MixerChannelForVoice(voiceIndex)
    If mixerChannel = 1 AndAlso _
        mixerState_IsAudible(mixerFixture, mixerChannel) <> 0 Then _
        test_Fail "mute state did not resolve through the fallback voice owner"
    If mixerChannel = 0 AndAlso _
        mixerState_IsAudible(mixerFixture, mixerChannel) = 0 Then _
        test_Fail "mute state leaked from channel one to channel zero voices"
Next
If mixerState_ToggleSolo(mixerFixture, 0) = 0 Then _
    test_Fail "could not solo channel zero in the routing fixture"
For voiceIndex As Integer = 0 To OSE_SOFTWARE_SYNTH_VOICE_COUNT - 1
    Dim As Integer mixerChannel = _
        softwareSynth_MixerChannelForVoice(voiceIndex)
    Dim As Integer expectedAudible = 0
    If mixerChannel = 0 Then expectedAudible = -1
    If mixerState_IsAudible(mixerFixture, mixerChannel) <> _
        expectedAudible Then _
        test_Fail "solo state did not resolve through the fallback voice owner"
Next

Print "midi_playback_audio=ok"
Print "notes="; startedCount
Print "frames="; waveInfo.sampleFrames
Print "peak="; peakValue
Print "same_channel_chord=ok c4_magnitude="; c4Magnitude; _
    " e4_magnitude="; e4Magnitude
Print "fallback_voice_mixer_routing=ok channel0="; _
    fallbackVoiceCounts(0); " channel1="; fallbackVoiceCounts(1)
Print "underruns="; underrunCount
#If Defined(__FB_AROS__)
Dim As String reportFilename = outputFilename + ".report"
If Not test_WriteReport(reportFilename, startedCount, waveInfo.sampleFrames, _
    peakValue, underrunCount) Then _
    test_Fail "could not write the AROS sidecar report"
#EndIf
End 0

/' end of tests/midi_playback_audio_smoke.bas '/
