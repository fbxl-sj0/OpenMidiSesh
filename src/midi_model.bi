/'
    Project: OpenSesh
    ---------------------------

    File: midi_model.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: midi_* document, event, edit/history, and serialization operations; Midi* records and limits.

    Purpose:

        Declare the bounded Standard MIDI File reader used by the editor
        shell. The reader supplies track metadata, a bounded summary preview,
        and the complete editable note set used by the score view.

    Responsibilities:

        - define the in-memory MIDI summary, preview, and tempo records
        - expose file loading and display-format helpers
        - expose safe creation of a fresh editable document
        - expose tempo conversion and bounded initial-tempo editing
        - expose bounded tempo-point and controller-point editing
        - expose bounded time-signature editing
        - expose bounded non-note channel-event editing
        - expose bounded Standard MIDI text-event editing
        - expose duration-preserving track quantization
        - expose bounded channel-mix editing while retaining automation
        - expose bounded chorus and reverb editing while retaining automation
        - expose sixteen-step bounded undo and redo snapshots for document edits
        - prepare, commit, or cancel a snapshot without losing redo on failure
        - keep parser limits visible to the application layer

    This file intentionally does NOT contain:

        - audio-device access
        - MIDI playback scheduling
        - score engraving rules
        - omaGui widget creation
'/

#ifndef __OSE_MIDI_MODEL_BI__
#define __OSE_MIDI_MODEL_BI__

' -------------------------------------------------------------------------
' Public limits and MIDI data records
' -------------------------------------------------------------------------

Const OSE_MAX_MIDI_TRACKS As Integer = 256
Const OSE_MAX_PREVIEW_NOTES As Integer = 192
Const OSE_MAX_MIDI_FILE_BYTES As LongInt = 67108864
Const OSE_MAX_TRACK_NAME As Integer = 63
Const OSE_MAX_EDITABLE_NOTES As Integer = 100000
Const OSE_MAX_TEMPO_EVENTS As Integer = 4096
Const OSE_MAX_TIME_SIGNATURE_EVENTS As Integer = 256
Const OSE_MAX_KEY_SIGNATURE_EVENTS As Integer = 128
Const OSE_MIDI_HISTORY_DEPTH As Integer = 16
Const OSE_MAX_TEXT_EVENT_BYTES As Integer = 1024
Const OSE_MAX_SYSEX_EVENT_BYTES As Integer = 4096
Const OSE_MAX_MIDI_TICK As ULongInt = 268435455
Const OSE_MAX_VLQ_BYTES As Integer = 4
Const OSE_BE32_SHIFT_24 As Integer = 24
Const OSE_BE32_SHIFT_16 As Integer = 16
Const OSE_BE32_SHIFT_8 As Integer = 8

Type MidiPreviewNote
    As ULongInt tick
    As ULongInt durationTicks
    As UByte keyNumber
    As UByte channel
    As Integer trackIndex
End Type

Type MidiTrackSummary
    As String name
    As Integer eventCount
    As Integer noteCount
    As ULongInt endTick
End Type

Type MidiEditableNote
    As ULongInt startTick
    As ULongInt durationTicks
    As UByte keyNumber
    As UByte channel
    As UByte velocity
    As Integer trackIndex
    ' Module-owned source ordinals plus one; zero identifies a generated event.
    ' Keeping both ends preserves same-tick ordering with channel/meta events.
    As Integer startEventOrder
    As Integer endEventOrder
End Type

Type MidiTempoPoint
    As ULongInt tick
    As ULong microsecondsPerQuarter
End Type

Type MidiTimeSignaturePoint
    As ULongInt tick
    As UByte numerator
    As UByte denominatorPower
    As UByte clocksPerMetronome
    As UByte thirtySecondNotesPerQuarter
End Type

Type MidiKeySignaturePoint
    As ULongInt tick
    ' Signed number of sharps (positive) or flats (negative), -7..7.
    As Integer sharpsFlats
    ' 0 = major, 1 = minor, matching the SMF FF59 layout.
    As UByte minor
End Type

Type MidiTextEventPoint
    As ULongInt tick
    As Integer trackIndex
    ' Standard text-family meta type: 01..07, excluding unsupported types.
    As UByte metaType
    As String textValue
    ' Valid only until the next structural edit to the stored-event array.
    As Integer sourceIndex
End Type

Type MidiControllerPoint
    As ULongInt tick
    As UByte channel
    As UByte controllerNumber
    As UByte controllerValue
    As Integer trackIndex
    ' Valid only until the next structural edit to the stored-event array.
    As Integer sourceIndex
End Type

Type MidiChannelEventPoint
    As ULongInt tick
    As UByte channel
    ' High nibble only: A0, B0, C0, D0, or E0.
    As UByte messageType
    As UByte data1
    As UByte data2
    As Integer trackIndex
    ' Valid only until the next structural edit to the stored-event array.
    As Integer sourceIndex
End Type

Type MidiSystemExclusivePoint
    As ULongInt tick
    As Integer trackIndex
    As UByte statusByte
    As String payload
    ' Valid only until the next structural edit to the stored-event array.
    As Integer sourceIndex
End Type

Type MidiSystemEventPoint
    As ULongInt tick
    As Integer trackIndex
    As UByte statusByte
    As UByte data1
    As UByte data2
    As Integer dataLength
    ' Valid only until the next structural edit to the stored-event array.
    As Integer sourceIndex
End Type

Type MidiSummary
    As Integer formatNumber
    As Integer trackCount
    As Integer division
    As LongInt fileSize
    As Integer eventCount
    As Integer preservedEventCount
    As Integer noteCount
    As Integer previewCount
    As Integer tempoCount
    As Integer timeSignatureCount
    As Integer keySignatureCount
    As String documentTitle
    As String copyrightText
    As String lyricText
    As String markerText
    As ULong tempoMicrosecondsPerQuarter
    As ULongInt durationTicks
    As UByte channelProgram(0 To 15)
    As UByte channelVolume(0 To 15)
    As UByte channelExpression(0 To 15)
    As UByte channelPan(0 To 15)
    As UByte channelChorus(0 To 15)
    As UByte channelReverb(0 To 15)
    As Integer channelPitchBend(0 To 15)
    As String errorText
    As MidiTempoPoint tempoMap(0 To OSE_MAX_TEMPO_EVENTS - 1)
    As MidiTimeSignaturePoint timeSignatureMap(0 To OSE_MAX_TIME_SIGNATURE_EVENTS - 1)
    As MidiKeySignaturePoint keySignatureMap(0 To OSE_MAX_KEY_SIGNATURE_EVENTS - 1)
    As MidiTrackSummary tracks(0 To OSE_MAX_MIDI_TRACKS - 1)
    As MidiPreviewNote preview(0 To OSE_MAX_PREVIEW_NOTES - 1)
End Type

' -------------------------------------------------------------------------
' Public model procedures
' -------------------------------------------------------------------------

Declare Function midi_LoadSummary( _
    ByRef summary As MidiSummary, _
    ByVal filename As String _
) As Integer

Declare Function midi_TrackDisplayName( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer _
) As String

Declare Function midi_SetTrackName( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal trackName As String _
) As Integer

Declare Function midi_NewDocument( _
    ByRef summary As MidiSummary _
) As Integer

Declare Function midi_CaptureHistory( _
    ByRef summary As MidiSummary _
) As Integer

Declare Function midi_PrepareHistory( _
    ByRef summary As MidiSummary _
) As Integer

Declare Function midi_CommitPreparedHistory() As Integer

Declare Function midi_CancelPreparedHistory( _
    ByRef summary As MidiSummary _
) As Integer

Declare Function midi_Undo( _
    ByRef summary As MidiSummary _
) As Integer

Declare Function midi_Redo( _
    ByRef summary As MidiSummary _
) As Integer

Declare Sub midi_HistoryClear()

Declare Function midi_HistoryUndoCount() As Integer

Declare Function midi_HistoryRedoCount() As Integer

Declare Sub midi_HistoryDiscardOldestUndo()

Declare Sub midi_HistoryRedoClear()

Declare Function midi_KeyDisplayName(ByVal keyNumber As Integer) As String

Declare Function midi_EstimatedSeconds( _
    ByRef summary As MidiSummary _
) As Double

Declare Function midi_TicksToSeconds( _
    ByRef summary As MidiSummary, _
    ByVal tick As ULongInt _
) As Double

Declare Function midi_SecondsToTicks( _
    ByRef summary As MidiSummary, _
    ByVal seconds As Double _
) As ULongInt

Declare Function midi_SetInitialTempoBpm( _
    ByRef summary As MidiSummary, _
    ByVal beatsPerMinute As Integer _
) As Integer

Declare Function midi_SetTempoPointBpm( _
    ByRef summary As MidiSummary, _
    ByVal tempoIndex As Integer, _
    ByVal beatsPerMinute As Integer _
) As Integer

Declare Function midi_AddTempoPointBpm( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal beatsPerMinute As Integer _
) As Integer

Declare Function midi_RemoveTempoPoint( _
    ByRef summary As MidiSummary, _
    ByVal tempoIndex As Integer _
) As Integer

Declare Function midi_SetTimeSignaturePoint( _
    ByRef summary As MidiSummary, _
    ByVal signatureIndex As Integer, _
    ByVal numerator As Integer, _
    ByVal denominatorPower As Integer _
) As Integer

Declare Function midi_AddTimeSignaturePoint( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal numerator As Integer, _
    ByVal denominatorPower As Integer _
) As Integer

Declare Function midi_RemoveTimeSignaturePoint( _
    ByRef summary As MidiSummary, _
    ByVal signatureIndex As Integer _
) As Integer

Declare Function midi_SetKeySignaturePoint( _
    ByRef summary As MidiSummary, _
    ByVal signatureIndex As Integer, _
    ByVal sharpsFlats As Integer, _
    ByVal minor As Integer _
) As Integer

Declare Function midi_AddKeySignaturePoint( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal sharpsFlats As Integer, _
    ByVal minor As Integer _
) As Integer

Declare Function midi_RemoveKeySignaturePoint( _
    ByRef summary As MidiSummary, _
    ByVal signatureIndex As Integer _
) As Integer

Declare Function midi_GetTextEventCount() As Integer

Declare Function midi_GetTextEvent( _
    ByVal eventIndex As Integer, _
    ByRef textEvent As MidiTextEventPoint _
) As Integer

Declare Function midi_SetTextEvent( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer, _
    ByRef textEvent As MidiTextEventPoint _
) As Integer

Declare Function midi_AddTextEvent( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal metaType As Integer, _
    ByVal textValue As String _
) As Integer

Declare Function midi_RemoveTextEvent( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer _
) As Integer

Declare Function midi_SetChannelMix( _
    ByRef summary As MidiSummary, _
    ByVal channelIndex As Integer, _
    ByVal volumeValue As Integer, _
    ByVal panValue As Integer _
) As Integer

Declare Function midi_SetChannelEffects( _
    ByRef summary As MidiSummary, _
    ByVal channelIndex As Integer, _
    ByVal chorusValue As Integer, _
    ByVal reverbValue As Integer _
) As Integer

Declare Function midi_GetControllerPointCount() As Integer

Declare Function midi_GetControllerPoint( _
    ByVal pointIndex As Integer, _
    ByRef controllerPoint As MidiControllerPoint _
) As Integer

Declare Function midi_SetControllerPoint( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer, _
    ByRef controllerPoint As MidiControllerPoint _
) As Integer

Declare Function midi_AddControllerPoint( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal channelIndex As Integer, _
    ByVal controllerNumber As Integer, _
    ByVal controllerValue As Integer _
) As Integer

Declare Function midi_RemoveControllerPoint( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer _
) As Integer

Declare Function midi_GetChannelEventCount() As Integer

Declare Function midi_GetChannelEvent( _
    ByVal eventIndex As Integer, _
    ByRef channelEvent As MidiChannelEventPoint _
) As Integer

Declare Function midi_SetChannelEvent( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer, _
    ByRef channelEvent As MidiChannelEventPoint _
) As Integer

Declare Function midi_AddChannelEvent( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal channelIndex As Integer, _
    ByVal messageType As Integer, _
    ByVal data1 As Integer, _
    ByVal data2 As Integer _
) As Integer

Declare Function midi_AddSystemExclusiveEvent( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal statusByte As Integer, _
    ByVal payload As String _
) As Integer

Declare Function midi_GetSystemExclusiveEventCount() As Integer

Declare Function midi_GetSystemExclusiveEvent( _
    ByVal eventIndex As Integer, _
    ByRef sysexEvent As MidiSystemExclusivePoint _
) As Integer

Declare Function midi_GetSystemEventCount() As Integer

Declare Function midi_GetSystemEvent( _
    ByVal eventIndex As Integer, _
    ByRef systemEvent As MidiSystemEventPoint _
) As Integer

Declare Function midi_SetSystemEvent( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer, _
    ByRef systemEvent As MidiSystemEventPoint _
) As Integer

Declare Function midi_AddSystemEvent( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal statusByte As Integer, _
    ByVal data1 As Integer, _
    ByVal data2 As Integer _
) As Integer

Declare Function midi_RemoveSystemEvent( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer _
) As Integer

Declare Function midi_RemoveChannelEvent( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer _
) As Integer

Declare Function midi_GetEditableNoteCount() As Integer

Declare Function midi_GetEditableNote( _
    ByVal noteIndex As Integer, _
    ByRef editableNote As MidiEditableNote _
) As Integer

Declare Function midi_SetEditableNote( _
    ByRef summary As MidiSummary, _
    ByVal noteIndex As Integer, _
    ByRef editableNote As MidiEditableNote _
) As Integer

Declare Function midi_SetEditableNotes( _
    ByRef summary As MidiSummary, _
    ByVal noteIndices As Integer Ptr, _
    ByVal editableNotes As MidiEditableNote Ptr, _
    ByVal noteCount As Integer _
) As Integer

Declare Function midi_AddEditableNote( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal startTick As ULongInt, _
    ByVal durationTicks As ULongInt, _
    ByVal keyNumber As Integer, _
    ByVal midiChannel As Integer, _
    ByVal noteVelocity As Integer _
) As Integer

Declare Function midi_AddEditableNotes( _
    ByRef summary As MidiSummary, _
    ByVal editableNotes As MidiEditableNote Ptr, _
    ByVal noteCount As Integer _
) As Integer

Declare Function midi_AddTrack( _
    ByRef summary As MidiSummary _
) As Integer

Declare Function midi_RemoveTrack( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer _
) As Integer

Declare Function midi_RemoveEditableNote( _
    ByRef summary As MidiSummary, _
    ByVal noteIndex As Integer _
) As Integer

Declare Function midi_RemoveEditableNotes( _
    ByRef summary As MidiSummary, _
    ByVal noteIndices As Integer Ptr, _
    ByVal noteCount As Integer _
) As Integer

Declare Function midi_QuantizeTrack( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal gridTicks As ULongInt _
) As Integer

Declare Function midi_SaveDocument( _
    ByRef summary As MidiSummary, _
    ByVal filename As String _
) As Integer

Declare Function midi_SerializeDocument( _
    ByRef summary As MidiSummary, _
    ByRef outputData As String _
) As Integer

#endif

/' end of midi_model.bi '/
