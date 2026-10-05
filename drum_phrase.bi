/'
    Project: OpenSesh
    File: drum_phrase.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: drumPhrase_* validation/storage/insertion with OseDrumPhrase.
    Purpose: Declare reusable drum-machine phrases with independent meters.
    Responsibilities: Bound pattern storage, MIDI persistence and note placement.
    This file intentionally does NOT contain:

        - widget implementations
        - playback voices
'/

#ifndef __OSE_DRUM_PHRASE_BI__
#define __OSE_DRUM_PHRASE_BI__

#include once "midi_model.bi"
#include once "drum_kit.bi"

Const OSE_DRUM_PHRASE_COUNT As Integer = 16
Const OSE_DRUM_PHRASE_STEPS As Integer = 64
Const OSE_DRUM_PHRASE_NAME_LENGTH As Integer = 32
Const OSE_DRUM_PHRASE_MAX_REPEATS As Integer = 64

Type OseDrumPhrase
    As String title
    As Integer numerator
    As Integer denominator
    As Integer subdivisions
    As UByte velocity(0 To OSE_DRUM_PAD_COUNT - 1, 0 To OSE_DRUM_PHRASE_STEPS - 1)
End Type

Declare Sub drumPhrase_Reset(ByRef phrase As OseDrumPhrase, ByVal slot As Integer)
Declare Function drumPhrase_PadForRow(ByVal rowIndex As Integer) As Integer
Declare Function drumPhrase_Valid(ByRef phrase As OseDrumPhrase) As Integer
Declare Function drumPhrase_StepTick(ByRef phrase As OseDrumPhrase, _
    ByVal division As Integer, ByVal stepIndex As Integer) As ULongInt
Declare Function drumPhrase_Load(ByVal slot As Integer, ByRef phrase As OseDrumPhrase) As Integer
Declare Function drumPhrase_Store(ByRef summary As MidiSummary, ByVal slot As Integer, _
    ByRef phrase As OseDrumPhrase) As Integer
' The caller owns the document-history transaction for Store and Insert.
' Insert always writes channel 10 notes, and never changes the song meter.
Declare Function drumPhrase_Insert(ByRef summary As MidiSummary, _
    ByRef phrase As OseDrumPhrase, ByVal trackIndex As Integer, _
    ByVal startTick As ULongInt, ByVal repeats As Integer, _
    ByRef endTick As ULongInt) As Integer

#endif

/' end of drum_phrase.bi '/
