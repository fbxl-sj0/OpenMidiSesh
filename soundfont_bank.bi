/'
    Project: OpenSesh
    ---------------------------

    File: soundfont_bank.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: soundfontBank_* bank loading/resolution with OseSoundFontVoiceRegion and bounds.

    Purpose:

        Declare the bounded SoundFont 2 bank reader used by the native synth.

    Responsibilities:

        - load standard little-endian SF2 RIFF banks transactionally
        - retain 16-bit sample data and the nine required Hydra tables
        - resolve a MIDI bank, program, key, and velocity into voice regions
        - expose immutable sample data while one bank is active

    This file intentionally does NOT contain:

        - audio-device or worker-thread code
        - MIDI transport scheduling
        - widgets or preference storage
'/

#ifndef __OSE_SOUNDFONT_BANK_BI__
#define __OSE_SOUNDFONT_BANK_BI__

Const OSE_SOUNDFONT_MAX_PATH_BYTES As Integer = 4096
Const OSE_SOUNDFONT_MAX_NAME_BYTES As Integer = 255
Const OSE_SOUNDFONT_MAX_REGIONS_PER_NOTE As Integer = 32

' A resolved region contains no pointers into Hydra metadata. The synth may
' copy it into a voice while the bank's immutable PCM allocation stays loaded.
' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseSoundFontVoiceRegion
    As ULongInt leftStart
    As ULongInt leftEnd
    As ULongInt leftLoopStart
    As ULongInt leftLoopEnd
    As ULongInt rightStart
    As ULongInt rightEnd
    As ULongInt rightLoopStart
    As ULongInt rightLoopEnd
    As ULong sampleRate
    As Integer rootKey
    As Integer keyOverride
    As Integer velocityOverride
    As Integer tuneCents
    As Integer scaleTuning
    As Integer sampleModes
    As Integer exclusiveClass
    As Single pan
    As Single attenuationGain
    As Single attackSeconds
    As Single holdSeconds
    As Single decaySeconds
    As Single sustainLevel
    As Single releaseSeconds
End Type

Declare Function soundfontBank_Load( _
    ByVal filename As String, _
    ByRef errorText As String _
) As Integer

Declare Sub soundfontBank_Clear()
Declare Function soundfontBank_IsLoaded() As Integer
Declare Function soundfontBank_GetFilename() As String
Declare Function soundfontBank_GetName() As String
Declare Function soundfontBank_GetPresetCount() As Integer
Declare Function soundfontBank_GetSampleHeaderCount() As Integer
Declare Function soundfontBank_GetSamplePointCount() As ULongInt
Declare Function soundfontBank_GetSampleData() As Short Ptr
Declare Function soundfontBank_HasPreset( _
    ByVal bankNumber As Integer, _
    ByVal programNumber As Integer _
) As Integer

Declare Function soundfontBank_Resolve( _
    ByVal bankNumber As Integer, _
    ByVal programNumber As Integer, _
    ByVal keyNumber As Integer, _
    ByVal velocity As Integer, _
    regions() As OseSoundFontVoiceRegion _
) As Integer

#endif

/' end of soundfont_bank.bi '/
