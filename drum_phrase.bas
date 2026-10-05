/'
    Project: OpenSesh
    File: drum_phrase.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements drum_phrase.bi; declarations there define the shared interface.
    Purpose: Store and arrange reusable drum-machine phrases.
    Responsibilities: Validate patterns, preserve them in MIDI text metadata,
        and expand independent meters into ordinary channel 10 notes.
    This file intentionally does NOT contain:

        - user-interface state or widget calls
        - audio playback or undo ownership
'/

#lang "fb"
#include once "drum_phrase.bi"

' -------------------------------------------------------------------------
' Phrase validation and rational timing
' -------------------------------------------------------------------------

Public Function drumPhrase_PadForRow(ByVal rowIndex As Integer) As Integer
    ' Put kick, snare and closed hat on the first page of a small step grid.
    ' Storage keeps the original playable-kit pad indices for compatibility.
    Dim As Integer padIndices(0 To OSE_DRUM_PAD_COUNT - 1) = {8, 9, 11, 10, 6, 5, 4, 7, 2, 1, 0, 3}
    If rowIndex < 0 OrElse rowIndex >= OSE_DRUM_PAD_COUNT Then
        Return -1
    End If
    Return padIndices(rowIndex)
End Function

Public Sub drumPhrase_Reset(ByRef phrase As OseDrumPhrase, ByVal slot As Integer)
    phrase.title = "Phrase " + LTrim(Str(slot + 1))
    phrase.numerator = 4
    phrase.denominator = 4
    phrase.subdivisions = 4
    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        For stepIndex As Integer = 0 To OSE_DRUM_PHRASE_STEPS - 1
            phrase.velocity(padIndex, stepIndex) = 0
        Next
    Next
End Sub

Public Function drumPhrase_Valid(ByRef phrase As OseDrumPhrase) As Integer
    If Len(phrase.title) < 1 OrElse Len(phrase.title) > OSE_DRUM_PHRASE_NAME_LENGTH Then
        Return 0
    End If
    For charIndex As Integer = 1 To Len(phrase.title)
        If Asc(phrase.title, charIndex) < 32 OrElse Mid(phrase.title, charIndex, 1) = "|" Then
            Return 0
        End If
    Next
    If phrase.numerator < 1 OrElse phrase.numerator > 16 Then
        Return 0
    End If
    If phrase.denominator < 1 OrElse phrase.denominator > 32 Then
        Return 0
    End If
    If phrase.subdivisions < 1 OrElse phrase.subdivisions > 4 Then
        Return 0
    End If
    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        For stepIndex As Integer = 0 To OSE_DRUM_PHRASE_STEPS - 1
            Select Case phrase.velocity(padIndex, stepIndex)
                Case 0, OSE_DRUM_VELOCITY_SOFT, OSE_DRUM_VELOCITY_MEDIUM, OSE_DRUM_VELOCITY_HARD
                Case Else
                    Return 0
            End Select
        Next
    Next
    Return -1
End Function

Public Function drumPhrase_StepTick(ByRef phrase As OseDrumPhrase, _
    ByVal division As Integer, ByVal stepIndex As Integer) As ULongInt
    If division < 1 OrElse division > 32767 OrElse stepIndex < 0 OrElse _
        stepIndex > OSE_DRUM_PHRASE_STEPS * OSE_DRUM_PHRASE_MAX_REPEATS Then
        Return 0
    End If
    If phrase.denominator < 1 OrElse phrase.denominator > 32 OrElse _
        phrase.subdivisions < 1 OrElse phrase.subdivisions > 4 Then
        Return 0
    End If
    /'
        MIDI division counts quarter notes. A denominator of 3 means a third
        of a whole note. Round each absolute step boundary, including repeats,
        instead of accumulating rounded step lengths and drifting off time.
    '/
    Dim As ULongInt divisor = phrase.denominator * phrase.subdivisions
    Return (CULngInt(stepIndex) * CULngInt(division) * 4 + divisor \ 2) \ divisor
End Function

' -------------------------------------------------------------------------
' Versioned MIDI text storage
' -------------------------------------------------------------------------

Private Function drumPhrase_Prefix(ByVal slot As Integer) As String
    Return "OpenSesh:DrumPhrase:1:" + LTrim(Str(slot)) + "|"
End Function

Private Function drumPhrase_Find(ByVal slot As Integer, ByRef textPoint As MidiTextEventPoint) As Integer
    Dim As String prefix = drumPhrase_Prefix(slot)
    For eventIndex As Integer = 0 To midi_GetTextEventCount() - 1
        If midi_GetTextEvent(eventIndex, textPoint) = 0 Then
            Continue For
        End If
        If textPoint.metaType = 1 AndAlso textPoint.tick = 0 AndAlso _
            Left(textPoint.textValue, Len(prefix)) = prefix Then
            Return -1
        End If
    Next
    Return 0
End Function

Private Function drumPhrase_Encode(ByVal slot As Integer, ByRef phrase As OseDrumPhrase) As String
    /'
        FF01 payload: version/slot prefix, three two-digit hexadecimal meter
        fields, title, then 12 rows of 64 velocity characters (-/s/m/h).
        Fixed rows retain hidden steps when the meter is shortened. The full
        record is below the model's 1024-byte text limit, and survives ordinary
        MIDI save/load and document undo. Other MIDI players ignore the text.
    '/
    Dim As String result = drumPhrase_Prefix(slot) + Hex(phrase.numerator, 2) + _
        Hex(phrase.denominator, 2) + Hex(phrase.subdivisions, 2) + "|" + phrase.title + "|"
    Dim As Integer position = Len(result) + 1
    result += String(OSE_DRUM_PAD_COUNT * OSE_DRUM_PHRASE_STEPS, "-")
    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        For stepIndex As Integer = 0 To OSE_DRUM_PHRASE_STEPS - 1
            Select Case phrase.velocity(padIndex, stepIndex)
                Case OSE_DRUM_VELOCITY_SOFT
                    Mid(result, position, 1) = "s"
                Case OSE_DRUM_VELOCITY_MEDIUM
                    Mid(result, position, 1) = "m"
                Case OSE_DRUM_VELOCITY_HARD
                    Mid(result, position, 1) = "h"
            End Select
            position += 1
        Next
    Next
    Return result
End Function

Private Function drumPhrase_HexByte(ByVal fieldText As String) As Integer
    If Len(fieldText) <> 2 Then
        Return -1
    End If
    Dim As Integer result = 0
    For charIndex As Integer = 1 To 2
        Dim As Integer digit = Instr("0123456789ABCDEF", Mid(fieldText, charIndex, 1)) - 1
        If digit < 0 Then
            Return -1
        End If
        result = result * 16 + digit
    Next
    Return result
End Function

Public Function drumPhrase_Load(ByVal slot As Integer, ByRef phrase As OseDrumPhrase) As Integer
    drumPhrase_Reset phrase, slot
    If slot < 0 OrElse slot >= OSE_DRUM_PHRASE_COUNT Then
        Return 0
    End If
    Dim As MidiTextEventPoint textPoint
    If drumPhrase_Find(slot, textPoint) = 0 Then
        Return 0
    End If
    Dim As String payload = Mid(textPoint.textValue, Len(drumPhrase_Prefix(slot)) + 1)
    If Len(payload) < 9 OrElse Mid(payload, 7, 1) <> "|" Then
        Return 0
    End If
    Dim As Integer titleEnd = Instr(8, payload, "|")
    If titleEnd < 9 OrElse titleEnd > 8 + OSE_DRUM_PHRASE_NAME_LENGTH Then
        Return 0
    End If
    If Len(payload) - titleEnd <> OSE_DRUM_PAD_COUNT * OSE_DRUM_PHRASE_STEPS Then
        Return 0
    End If
    Dim As OseDrumPhrase candidate
    candidate.numerator = drumPhrase_HexByte(Left(payload, 2))
    candidate.denominator = drumPhrase_HexByte(Mid(payload, 3, 2))
    candidate.subdivisions = drumPhrase_HexByte(Mid(payload, 5, 2))
    candidate.title = Mid(payload, 8, titleEnd - 8)
    Dim As Integer position = titleEnd + 1
    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        For stepIndex As Integer = 0 To OSE_DRUM_PHRASE_STEPS - 1
            Select Case Mid(payload, position, 1)
                Case "-"
                    candidate.velocity(padIndex, stepIndex) = 0
                Case "s"
                    candidate.velocity(padIndex, stepIndex) = OSE_DRUM_VELOCITY_SOFT
                Case "m"
                    candidate.velocity(padIndex, stepIndex) = OSE_DRUM_VELOCITY_MEDIUM
                Case "h"
                    candidate.velocity(padIndex, stepIndex) = OSE_DRUM_VELOCITY_HARD
                Case Else
                    Return 0
            End Select
            position += 1
        Next
    Next
    If drumPhrase_Valid(candidate) = 0 Then
        Return 0
    End If
    phrase = candidate
    Return -1
End Function

Public Function drumPhrase_Store(ByRef summary As MidiSummary, ByVal slot As Integer, _
    ByRef phrase As OseDrumPhrase) As Integer
    If slot < 0 OrElse slot >= OSE_DRUM_PHRASE_COUNT OrElse summary.trackCount < 1 Then
        Return 0
    End If
    If drumPhrase_Valid(phrase) = 0 Then
        Return 0
    End If
    Dim As MidiTextEventPoint textPoint
    Dim As Integer found = drumPhrase_Find(slot, textPoint)
    Dim As String encoded = drumPhrase_Encode(slot, phrase)
    If found <> 0 Then
        If textPoint.textValue = encoded Then
            Return -1
        End If
        textPoint.textValue = encoded
        Return midi_SetTextEvent(summary, textPoint.sourceIndex, textPoint)
    End If
    Return IIf(midi_AddTextEvent(summary, 0, 0, 1, encoded) >= 0, -1, 0)
End Function

' -------------------------------------------------------------------------
' Bounded placement into the shared song timeline
' -------------------------------------------------------------------------

Public Function drumPhrase_Insert(ByRef summary As MidiSummary, _
    ByRef phrase As OseDrumPhrase, ByVal trackIndex As Integer, _
    ByVal startTick As ULongInt, ByVal repeats As Integer, _
    ByRef endTick As ULongInt) As Integer
    endTick = startTick
    If drumPhrase_Valid(phrase) = 0 OrElse summary.division < 1 OrElse summary.division > 32767 Then
        Return 0
    End If
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return 0
    End If
    If repeats < 1 OrElse repeats > OSE_DRUM_PHRASE_MAX_REPEATS Then
        Return 0
    End If
    If startTick > OSE_MAX_MIDI_TICK Then
        Return 0
    End If
    Dim As Integer steps = phrase.numerator * phrase.subdivisions
    Dim As ULongInt duration = drumPhrase_StepTick(phrase, summary.division, steps * repeats)
    If duration = 0 OrElse duration > OSE_MAX_MIDI_TICK - startTick Then
        Return 0
    End If
    ' Every cell needs at least one MIDI tick, including at small PPQN values.
    If CULngInt(summary.division) * 4 < CULngInt(phrase.denominator * phrase.subdivisions) Then
        Return 0
    End If
    Dim As Integer hitCount = 0
    For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
        For stepIndex As Integer = 0 To steps - 1
            If phrase.velocity(padIndex, stepIndex) > 0 Then
                hitCount += 1
            End If
        Next
    Next
    hitCount *= repeats
    If hitCount = 0 OrElse hitCount > OSE_MAX_EDITABLE_NOTES - midi_GetEditableNoteCount() Then
        Return 0
    End If
    Dim As MidiEditableNote Ptr notes = Callocate(hitCount, SizeOf(MidiEditableNote))
    If notes = 0 Then
        Return 0
    End If
    Dim As Integer noteIndex = 0
    For absoluteStep As Integer = 0 To steps * repeats - 1
        Dim As ULongInt tick = drumPhrase_StepTick(phrase, summary.division, absoluteStep)
        Dim As ULongInt nextTick = drumPhrase_StepTick(phrase, summary.division, absoluteStep + 1)
        For padIndex As Integer = 0 To OSE_DRUM_PAD_COUNT - 1
            Dim As Integer velocity = phrase.velocity(padIndex, absoluteStep Mod steps)
            If velocity = 0 Then
                Continue For
            End If
            notes[noteIndex].startTick = startTick + tick
            notes[noteIndex].durationTicks = nextTick - tick
            notes[noteIndex].keyNumber = drumKit_Pitch(padIndex)
            notes[noteIndex].channel = 9
            notes[noteIndex].velocity = velocity
            notes[noteIndex].trackIndex = trackIndex
            noteIndex += 1
        Next
    Next
    Dim As Integer result = midi_AddEditableNotes(summary, notes, hitCount)
    Deallocate notes
    If result < 0 Then
        Return 0
    End If
    endTick = startTick + duration
    Return -1
End Function

/' end of drum_phrase.bas '/
