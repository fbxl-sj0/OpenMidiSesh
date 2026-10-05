/'
    Project: OpenSesh
    ---------------------------

    File: empty_document_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify that the editor can create, populate, and save a new MIDI
        document without first importing a file.

    Responsibilities:

        - create two bounded tracks from an empty summary
        - add overlapping editable notes and remove a track with index compaction
        - add and remove tempo and time-signature points with duplicate guards
        - save and reload the resulting Standard MIDI File

    This file intentionally does NOT contain:

        - GUI startup or input simulation
        - audio playback
        - recovered reference-application data
        - private file-format assumptions
'/

#lang "fb"

#include once "../src/midi_model.bi"

Dim As String outputFilename = Trim(Command(1))
If outputFilename = "" Then
    Print "usage: empty_document_smoke.exe <output.mid>"
    End 2
End If

Dim As MidiSummary summary
If midi_AddTrack(summary) <> 0 Then
    Print "ERROR: could not create the first track"
    End 1
End If

If midi_AddEditableNote(summary, 0, 0, 240, 60, 0, 100) < 0 Then
    Print "ERROR: could not add the new-document note"
    End 1
End If

If midi_AddTrack(summary) <> 1 Then
    Print "ERROR: could not create the second track"
    End 1
End If

If midi_AddEditableNote(summary, 1, 480, 120, 67, 1, 80) < 0 Then
    Print "ERROR: could not add the second-track note"
    End 1
End If

If midi_RemoveTrack(summary, 1) = 0 Then
    Print "ERROR: could not remove the second track"
    End 1
End If

If summary.trackCount <> 1 OrElse summary.formatNumber <> 0 OrElse _
    summary.noteCount <> 1 OrElse summary.previewCount <> 1 Then
    Print "ERROR: track removal did not compact the new document"
    End 1
End If

Dim As MidiEditableNote remainingNote
If midi_GetEditableNote(0, remainingNote) = 0 OrElse _
    remainingNote.trackIndex <> 0 OrElse remainingNote.keyNumber <> 60 Then
    Print "ERROR: track removal changed the remaining note"
    End 1
End If

If midi_AddTrack(summary) <> 1 Then
    Print "ERROR: could not recreate the removed track"
    End 1
End If

If midi_AddEditableNote(summary, 0, 120, 240, 60, 0, 80) < 0 Then
    Print "ERROR: could not add the overlapping note"
    End 1
End If

If midi_SetInitialTempoBpm(summary, 96) = 0 OrElse _
    midi_SetChannelMix(summary, 0, 102, 32) = 0 OrElse _
    midi_SetChannelEffects(summary, 0, 22, 55) = 0 Then
    Print "ERROR: could not edit new-document tempo or mix"
    End 1
End If

Dim As Integer automationSource = midi_AddControllerPoint( _
    summary, 1, 240, 1, 74, 55)
If automationSource < 0 Then
    Print "ERROR: could not add the automation point"
    End 1
End If
Dim As MidiControllerPoint automationPoint
automationPoint.tick = 360
automationPoint.channel = 1
automationPoint.controllerNumber = 74
automationPoint.controllerValue = 64
automationPoint.trackIndex = 1
If midi_SetControllerPoint(summary, automationSource, automationPoint) = 0 Then
    Print "ERROR: could not edit the automation point"
    End 1
End If

Dim As Integer programSource = midi_AddChannelEvent( _
    summary, 1, 240, 2, &HC0, 41, 0)
If programSource < 0 Then
    Print "ERROR: could not add a program-change event"
    End 1
End If
Dim As MidiChannelEventPoint programEvent
If midi_GetChannelEvent( _
    midi_GetChannelEventCount() - 1, programEvent) = 0 Then
    Print "ERROR: could not read the program-change event"
    End 1
End If
programEvent.tick = 360
programEvent.data1 = 42
If midi_SetChannelEvent(summary, programSource, programEvent) = 0 Then
    Print "ERROR: could not edit the program-change event"
    End 1
End If

If midi_SetTrackName(summary, 1, "Lead Synth") = 0 Then
    Print "ERROR: could not set the track name"
    End 1
End If
If midi_SetTimeSignaturePoint(summary, 0, 3, 2) = 0 Then
    Print "ERROR: could not set the time signature"
    End 1
End If

Dim As Integer addedTempoPoint = midi_AddTempoPointBpm( _
    summary, 1, 960, 140)
If addedTempoPoint < 0 OrElse _
    midi_AddTempoPointBpm(summary, 1, 960, 140) >= 0 Then
    Print "ERROR: could not enforce unique tempo-map insertion"
    End 1
End If
Dim As Integer addedSignaturePoint = midi_AddTimeSignaturePoint( _
    summary, 1, 960, 6, 3)
If addedSignaturePoint < 0 OrElse _
    midi_AddTimeSignaturePoint(summary, 1, 960, 6, 3) >= 0 Then
    Print "ERROR: could not enforce unique meter-map insertion"
    End 1
End If

Dim As Integer temporaryAutomation = midi_AddControllerPoint( _
    summary, 1, 120, 1, 75, 12)
If temporaryAutomation < 0 OrElse _
    midi_RemoveControllerPoint(summary, temporaryAutomation) = 0 Then
    Print "ERROR: could not remove the temporary automation point"
    End 1
End If

If midi_SaveDocument(summary, outputFilename) = 0 Then
    Print "ERROR: could not save the new document"
    End 1
End If

Dim As MidiSummary reloadedSummary
If midi_LoadSummary(reloadedSummary, outputFilename) = 0 Then
    Print "ERROR: new document did not reload: "; reloadedSummary.errorText
    End 1
End If

If reloadedSummary.formatNumber <> 1 OrElse _
    reloadedSummary.trackCount <> 2 OrElse _
    reloadedSummary.division <> 480 OrElse _
    reloadedSummary.noteCount <> 2 OrElse _
    reloadedSummary.eventCount <> 17 OrElse _
    reloadedSummary.tracks(1).name <> "Lead Synth" OrElse _
    reloadedSummary.tempoCount <> 2 OrElse _
    reloadedSummary.timeSignatureCount <> 2 OrElse _
    reloadedSummary.timeSignatureMap(0).numerator <> 3 OrElse _
    reloadedSummary.timeSignatureMap(0).denominatorPower <> 2 OrElse _
    reloadedSummary.timeSignatureMap(1).tick <> 960 OrElse _
    reloadedSummary.timeSignatureMap(1).numerator <> 6 OrElse _
    reloadedSummary.timeSignatureMap(1).denominatorPower <> 3 OrElse _
    reloadedSummary.tempoMap(0).microsecondsPerQuarter <> 625000 OrElse _
    reloadedSummary.tempoMap(1).tick <> 960 OrElse _
    reloadedSummary.tempoMap(1).microsecondsPerQuarter <> 428571 OrElse _
    reloadedSummary.channelVolume(0) <> 102 OrElse _
    reloadedSummary.channelPan(0) <> 32 OrElse _
    reloadedSummary.channelChorus(0) <> 22 OrElse _
    reloadedSummary.channelReverb(0) <> 55 OrElse _
    reloadedSummary.channelProgram(2) <> 42 Then
    Print "ERROR: new document defaults were not preserved"
    End 1
End If

Dim As Integer foundFirstOverlapNote = 0
Dim As Integer foundSecondOverlapNote = 0
Dim As MidiEditableNote loadedNote
For noteIndex As Integer = 0 To midi_GetEditableNoteCount() - 1
    If midi_GetEditableNote(noteIndex, loadedNote) <> 0 Then
        If loadedNote.startTick = 0 AndAlso _
            loadedNote.durationTicks = 240 AndAlso loadedNote.keyNumber = 60 Then
            foundFirstOverlapNote = -1
        ElseIf loadedNote.startTick = 120 AndAlso _
            loadedNote.durationTicks = 240 AndAlso loadedNote.keyNumber = 60 Then
            foundSecondOverlapNote = -1
        End If
    End If
Next
If foundFirstOverlapNote = 0 OrElse foundSecondOverlapNote = 0 Then
    Print "ERROR: overlapping note durations were not preserved"
    End 1
End If

Dim As Integer foundProgramEvent = 0
Dim As MidiChannelEventPoint loadedChannelEvent
For eventIndex As Integer = 0 To midi_GetChannelEventCount() - 1
    If midi_GetChannelEvent(eventIndex, loadedChannelEvent) <> 0 AndAlso _
        loadedChannelEvent.messageType = &HC0 AndAlso _
        loadedChannelEvent.tick = 360 AndAlso _
        loadedChannelEvent.trackIndex = 1 AndAlso _
        loadedChannelEvent.channel = 2 AndAlso _
        loadedChannelEvent.data1 = 42 Then
        foundProgramEvent = -1
        Exit For
    End If
Next
If foundProgramEvent = 0 Then
    Print "ERROR: edited program-change event did not survive save"
    End 1
End If

Dim As Integer foundAutomationPoint = 0
Dim As MidiControllerPoint loadedController
For pointIndex As Integer = 0 To midi_GetControllerPointCount() - 1
    If midi_GetControllerPoint(pointIndex, loadedController) <> 0 Then
        If loadedController.tick = 360 AndAlso _
            loadedController.channel = 1 AndAlso _
            loadedController.controllerNumber = 74 AndAlso _
            loadedController.controllerValue = 64 AndAlso _
            loadedController.trackIndex = 1 Then
            foundAutomationPoint = -1
            Exit For
        End If
    End If
Next
If foundAutomationPoint = 0 Then
    Print "ERROR: edited automation point was not preserved"
    End 1
End If

If midi_RemoveTempoPoint(reloadedSummary, 0) <> 0 OrElse _
    midi_RemoveTimeSignaturePoint(reloadedSummary, 0) <> 0 OrElse _
    midi_RemoveTempoPoint(reloadedSummary, 1) = 0 OrElse _
    midi_RemoveTimeSignaturePoint(reloadedSummary, 1) = 0 OrElse _
    reloadedSummary.tempoCount <> 1 OrElse _
    reloadedSummary.timeSignatureCount <> 1 Then
    Print "ERROR: tempo or meter point deletion was not bounded"
    End 1
End If

If midi_NewDocument(reloadedSummary) = 0 OrElse _
    reloadedSummary.trackCount <> 1 OrElse _
    reloadedSummary.noteCount <> 0 OrElse _
    midi_GetEditableNoteCount() <> 0 OrElse _
    midi_GetChannelEventCount() <> 0 Then
    Print "ERROR: new-document reset retained old private data"
    End 1
End If

Print "empty_document=ok"
Print "tracks="; reloadedSummary.trackCount
Print "notes="; reloadedSummary.noteCount
Print "division="; reloadedSummary.division
End 0

/' end of empty_document_smoke.bas '/
