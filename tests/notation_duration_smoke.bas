/'
    Project: OpenSesh
    ---------------------------

    File: notation_duration_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Create a deterministic MIDI fixture containing every note value drawn
        by the score's polygon notation family.

    Responsibilities:

        - create whole, half, quarter, 8th, 16th, 32nd, and 64th notes
        - isolate flagged values on separate tracks so automatic beaming cannot
          hide their individual flags
        - provide explicit down-stem and up-stem eighth-note beam runs
        - save and reload the fixture through the public MIDI model
        - verify every requested duration survived the round trip

    This file intentionally does NOT contain:

        - GUI automation or screenshot capture
        - private score-renderer calls
        - recovered reference-application data
'/

#lang "fb"

#include once "../midi_model.bi"

Dim As String outputFilename = Trim(Command(1))
If outputFilename = "" Then
    Print "usage: notation_duration_smoke.exe <output.mid>"
    End 2
End If

Dim As MidiSummary summary
If midi_NewDocument(summary) = 0 Then
    Print "ERROR: could not create notation document"
    End 1
End If

Dim As ULongInt quarterTicks = CULngInt(summary.division)
If quarterTicks = 0 Then
    Print "ERROR: new document has no timing division"
    End 1
End If

If midi_SetTrackName(summary, 0, "Whole Half Quarter") = 0 Then
    Print "ERROR: could not name the long-note track"
    End 1
End If

If midi_AddEditableNote(summary, 0, 0, quarterTicks * 4, 64, 0, 100) < 0 OrElse _
    midi_AddEditableNote(summary, 0, quarterTicks * 5, quarterTicks * 2, _
        65, 0, 100) < 0 OrElse _
    midi_AddEditableNote(summary, 0, quarterTicks * 8, quarterTicks, _
        67, 0, 100) < 0 Then
    Print "ERROR: could not add long notation values"
    End 1
End If

Dim As String shortTrackName(0 To 3) = { _
    "Eighth - 1 flag", "Sixteenth - 2 flags", _
    "Thirty-second - 3 flags", "Sixty-fourth - 4 flags" _
}
Dim As ULongInt shortDuration(0 To 3) = { _
    quarterTicks \ 2, quarterTicks \ 4, _
    quarterTicks \ 8, quarterTicks \ 16 _
}

For shortIndex As Integer = 0 To 3
    If shortDuration(shortIndex) = 0 Then
        Print "ERROR: timing division is too small for notation fixture"
        End 1
    End If

    Dim As Integer trackIndex = midi_AddTrack(summary)
    If trackIndex <> shortIndex + 1 Then
        Print "ERROR: could not add short-note track"; shortIndex
        End 1
    End If
    If midi_SetTrackName(summary, trackIndex, shortTrackName(shortIndex)) = 0 Then
        Print "ERROR: could not name short-note track"; shortIndex
        End 1
    End If
    If midi_AddEditableNote(summary, trackIndex, quarterTicks * 2, _
        shortDuration(shortIndex), 60 + shortIndex * 2, trackIndex, 100) < 0 Then
        Print "ERROR: could not add short notation value"; shortIndex
        End 1
    End If
Next

Dim As Integer downBeamTrack = midi_AddTrack(summary)
If downBeamTrack <> 5 OrElse _
    midi_SetTrackName(summary, downBeamTrack, "Down-stem beam run") = 0 Then
    Print "ERROR: could not create down-stem beam track"
    End 1
End If
Dim As Integer downBeamPitch(0 To 3) = {72, 71, 69, 71}
For beamIndex As Integer = 0 To UBound(downBeamPitch)
    If midi_AddEditableNote(summary, downBeamTrack, _
        CULngInt(beamIndex) * (quarterTicks \ 2), quarterTicks \ 2, _
        downBeamPitch(beamIndex), downBeamTrack, 100) < 0 Then
        Print "ERROR: could not add down-stem beam note"; beamIndex
        End 1
    End If
Next

Dim As Integer upBeamTrack = midi_AddTrack(summary)
If upBeamTrack <> 6 OrElse _
    midi_SetTrackName(summary, upBeamTrack, "Up-stem beam run") = 0 Then
    Print "ERROR: could not create up-stem beam track"
    End 1
End If
Dim As Integer upBeamPitch(0 To 3) = {59, 58, 59, 57}
For beamIndex As Integer = 0 To 3
    If midi_AddEditableNote(summary, upBeamTrack, _
        CULngInt(beamIndex) * (quarterTicks \ 2), quarterTicks \ 2, _
        upBeamPitch(beamIndex), upBeamTrack, 100) < 0 Then
        Print "ERROR: could not add up-stem beam note"; beamIndex
        End 1
    End If
Next
' This note stays outside the initial score view. It keeps the track's average
' at the treble-clef boundary so the visible B3 run exercises up-stem beams.
If midi_AddEditableNote(summary, upBeamTrack, quarterTicks * 20, _
    quarterTicks, 90, upBeamTrack, 100) < 0 Then
    Print "ERROR: could not add up-stem clef anchor"
    End 1
End If

If midi_SaveDocument(summary, outputFilename) = 0 Then
    Print "ERROR: could not save notation fixture"
    End 1
End If

Dim As MidiSummary reloadedSummary
If midi_LoadSummary(reloadedSummary, outputFilename) = 0 Then
    Print "ERROR: could not reload notation fixture"
    End 1
End If
If reloadedSummary.trackCount <> 7 OrElse _
    midi_GetEditableNoteCount() <> 16 Then
    Print "ERROR: notation fixture counts changed during round trip"
    End 1
End If

Dim As Integer foundDuration(0 To 6)
Dim As ULongInt expectedDuration(0 To 6) = { _
    quarterTicks * 4, quarterTicks * 2, quarterTicks, _
    quarterTicks \ 2, quarterTicks \ 4, quarterTicks \ 8, _
    quarterTicks \ 16 _
}
For noteIndex As Integer = 0 To midi_GetEditableNoteCount() - 1
    Dim As MidiEditableNote editableNote
    If midi_GetEditableNote(noteIndex, editableNote) = 0 Then
        Print "ERROR: could not read notation fixture note"; noteIndex
        End 1
    End If
    For durationIndex As Integer = 0 To UBound(expectedDuration)
        If editableNote.durationTicks = expectedDuration(durationIndex) Then
            foundDuration(durationIndex) = -1
        End If
    Next
Next

For durationIndex As Integer = 0 To UBound(foundDuration)
    If foundDuration(durationIndex) = 0 Then
        Print "ERROR: notation duration was not preserved"; durationIndex
        End 1
    End If
Next

Print "notation_duration=ok"
Print "tracks="; reloadedSummary.trackCount
Print "notes="; midi_GetEditableNoteCount()
Print "shortest_ticks="; expectedDuration(6)
End 0

/' end of notation_duration_smoke.bas '/
