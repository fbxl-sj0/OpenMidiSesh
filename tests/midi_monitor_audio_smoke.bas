/'
    Project: OpenMidiSesh
    File: tests/midi_monitor_audio_smoke.bas
    Targets: FreeBASIC fb dialect; Windows/Linux with the null audio driver.
    Module API: Test executable for the production software-synth adapter.
    Purpose: Verify live voices remain audible and stop on MIDI note-off.
    Responsibilities: PCM energy, controller updates and stolen-voice isolation.
    This file intentionally does NOT contain: MIDI devices or replacement mixers.
'/
#lang "fb"
#include once "sfxlib_raw.bi"
#include once "../src/software_synth.bi"
#include once "../src/sfx_runtime.bi"
Declare Sub test_RuntimeLock CDecl Alias "fb_sfxRuntimeLock" ()
Declare Sub test_RuntimeUnlock CDecl Alias "fb_sfxRuntimeUnlock" ()
Declare Sub test_MixerProcess CDecl Alias "fb_sfxMixerProcess" (ByVal frames As Long)
Declare Function test_MixBufferRead CDecl Alias "fb_sfxMixBufferRead" ( _
    ByVal samples As Single Ptr, ByVal frames As Long) As Long
Const TEST_FRAMES As Integer = 256
Private Sub test_Require(ByVal condition As Integer, ByVal messageText As String)
    If condition <> 0 Then Exit Sub
    Print "FAIL: " + messageText
    End 1
End Sub
Private Function test_Energy() As Double
    Dim As Single samples(0 To TEST_FRAMES * 2 - 1)
    test_RuntimeLock()
    test_MixerProcess TEST_FRAMES
    Dim As Long copiedFrames = test_MixBufferRead(@samples(0), TEST_FRAMES)
    test_RuntimeUnlock()
    test_Require copiedFrames = TEST_FRAMES, "short audio render"
    Dim As Double energy
    For i As Integer = 0 To TEST_FRAMES * 2 - 1
        energy += CDbl(samples(i)) * samples(i)
    Next
    Return energy
End Function
Private Sub test_ExpectNoteOff()
    #if OSE_SFX_GENERATED_RELEASE_AVAILABLE
        test_Require test_Energy() > 0.000001, "note-off cut the waveform abruptly"
        ' All configured release envelopes finish within 0.4 seconds. Render
        ' more than that at either the 44.1 or 48 kHz runtime default rate.
        For batch As Integer = 1 To 128
            test_Energy()
        Next
    #endif
    test_Require test_Energy() = 0.0, "note-off left audible PCM after release"
End Sub
SetEnviron "SFXLIB_DRIVER=null"
test_Require sfxlib.RawOpen() > 0, "null output did not open"
softwareSynth_Configure()
Dim As OsePlaybackMixValues mixValues
playbackMix_Calculate mixValues, 100, 127, 64, 100, 1.0, -1
Dim As OseSoftwareSynthPlayOptions options
options.fallbackVoiceChannel = 0
test_Require softwareSynth_PlayMidiNote(0, 60, 16, 8192, 3600.0, mixValues, options) <> 0, "note start"
' Render over a quarter second, longer than the old fixed 0.18-second preview.
For batch As Integer = 1 To 64
    test_Energy()
Next
test_Require test_Energy() > 0.000001, "held note became silent"
Dim As OsePlaybackMixValues silentMix = mixValues
silentMix.channelGain = 0.0
softwareSynth_UpdateMidiChannel 0, 8192, silentMix
test_Require test_Energy() = 0.0, "live volume did not mute the held voice"
softwareSynth_UpdateMidiChannel 0, 12288, mixValues
test_Require test_Energy() > 0.000001, "bend or volume restore silenced voice"
softwareSynth_StopMidiNote 0, 60
test_ExpectNoteOff()
#if OSE_SFX_GENERATED_RELEASE_AVAILABLE
    softwareSynth_UpdateMidiChannel 0, 8192, mixValues
    test_Require test_Energy() = 0.0, "pitch bend restarted a released note"
#endif
test_Require softwareSynth_PlayMidiNote(0, 60, 16, 8192, 3600.0, mixValues, options) <> 0, "second note start"
test_Require softwareSynth_PlayMidiNote(1, 67, 16, 8192, 3600.0, mixValues, options) <> 0, "voice steal"
softwareSynth_StopMidiNote 0, 60
test_Require test_Energy() > 0.000001, "old note-off stopped a stolen voice"
softwareSynth_StopMidiNote 1, 67
test_ExpectNoteOff()
#if OSE_SFX_GENERATED_RELEASE_AVAILABLE
    test_Require softwareSynth_PlayMidiNote(7, 60, 16, 8192, 3600.0, mixValues, options) <> 0, "release ownership note"
    test_Energy()
    softwareSynth_StopMidiNote 7, 60
    test_Require softwareSynth_MixerChannelForVoice(0) = 7, "release lost source mix ownership"
    test_ExpectNoteOff()
#endif
sfxlib.RawClose()
sfxRuntime_Shutdown()
Print "midi_monitor_audio=ok held=1 note_off=1 controls=1 stealing=1"
End 0
/' end of tests/midi_monitor_audio_smoke.bas '/
