/'
    Project: OpenSesh
    ---------------------------

    File: midi_model.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements midi_model.bi; declarations there define the shared interface.

    Purpose:

        Parse the Standard MIDI File container used by the editor and expose
        safe summary data to the application shell.

    Responsibilities:

        - validate MThd and MTrk chunks before reading them
        - parse channel, meta, and system events with running status
        - count tracks, events, notes, and song ticks
        - retain a bounded summary preview and a complete editable note set
        - apply validated bulk note edits with one document reconciliation
        - retain the latest basic channel controls for the synth and writer
        - retain standard chorus and reverb controller state
        - expose validated editing for stored non-note channel events
        - expose validated editing for supported system-common events
        - expose validated editing for standard text-family meta events
        - build a bounded sorted tempo map for musical-time conversion
        - build a bounded sorted time-signature map for score layout
        - quantize note starts without changing note durations
        - provide sixteen-step undo and redo snapshots without exposing storage
        - stage undo snapshots until the caller confirms a successful edit
        - update tick-zero tempo and channel-mix events without flattening
          later automation

    Ownership:

        The module owns its binary input buffer, editable-note array, and
        non-note event sidecar. A successful load replaces all three arrays,
        and callers access notes only through the public query and edit
        procedures below. After an edit, document counts are reconciled to the
        events the writer will emit, including regenerated note pairs and EOT.

    This file intentionally does NOT contain:

        - synthesized voices or wave loading
        - operating-system MIDI calls
        - GUI drawing or input handling
        - assumptions about the original Midisoft private data structures
'/

#lang "fb"

#include once "midi_model.bi"
#include once "atomic_file_internal.bi"

' fblint: disable-next-line FBL301 REASON: parser storage is owned by this module and is never exposed.
Dim Shared midi_Data() As UByte
Dim Shared midi_DataSize As Integer
Dim Shared midi_EditableNotes() As MidiEditableNote
Dim Shared midi_EditableNoteCount As Integer
Dim Shared midi_EditableNoteCapacity As Integer
Const OSE_MAX_STORED_EVENTS As Integer = 1000000
Const OSE_EVENT_CHANNEL As UByte = 0
Const OSE_EVENT_META As UByte = 1
Const OSE_EVENT_SYSEX As UByte = 2
Const OSE_EVENT_SYSTEM As UByte = 3

Declare Sub midi_RecalculateDuration(ByRef summary As MidiSummary)
Declare Sub midi_RecalculateDocumentCounts(ByRef summary As MidiSummary)
Declare Sub midi_RebuildTextMetadata(ByRef summary As MidiSummary)

Type MidiStoredEvent
    As ULongInt tick
    As Integer trackIndex
    As UByte eventKind
    As UByte statusByte
    As UByte data1
    As UByte data2
    As Integer order
    As String payload
End Type

Dim Shared midi_StoredEvents() As MidiStoredEvent
Dim Shared midi_StoredEventCount As Integer
Dim Shared midi_StoredEventCapacity As Integer

/'
    Bounded edit history

    Each slot owns independent dynamic arrays because stored events contain
    managed payload strings. The undo and redo rings cap the number of complete
    document snapshots without moving or shallow-copying array descriptors.
'/
Type MidiHistorySnapshot
    As MidiSummary summary
    As Integer noteCount
    As Integer eventCount
    notes(Any) As MidiEditableNote
    events(Any) As MidiStoredEvent
    As Integer valid
End Type

/'
    One physical spare slot lets a full logical ring stage its next snapshot
    without overwriting the oldest committed undo entry. A failed edit can
    therefore be cancelled without losing either end of the history branch.
'/
Const OSE_MIDI_HISTORY_STORAGE As Integer = OSE_MIDI_HISTORY_DEPTH + 1
Dim Shared midi_HistoryUndo(0 To OSE_MIDI_HISTORY_STORAGE - 1) As _
    MidiHistorySnapshot
Dim Shared midi_HistoryUndoStart As Integer
Dim Shared midi_HistoryUndoCountValue As Integer
Dim Shared midi_HistoryRedo(0 To OSE_MIDI_HISTORY_STORAGE - 1) As _
    MidiHistorySnapshot
Dim Shared midi_HistoryRedoStart As Integer
Dim Shared midi_HistoryRedoCountValue As Integer
Dim Shared midi_HistoryPreparedIndex As Integer = -1

Declare Function midi_CopyCurrentState( _
    ByRef sourceSummary As MidiSummary, _
    ByRef destinationSummary As MidiSummary, _
    destinationNotes() As MidiEditableNote, _
    ByRef destinationNoteCount As Integer, _
    destinationEvents() As MidiStoredEvent, _
    ByRef destinationEventCount As Integer _
) As Integer

Declare Function midi_RestoreState( _
    ByRef destinationSummary As MidiSummary, _
    ByRef sourceSummary As MidiSummary, _
    sourceNotes() As MidiEditableNote, _
    ByVal sourceNoteCount As Integer, _
    sourceEvents() As MidiStoredEvent, _
    ByVal sourceEventCount As Integer _
) As Integer

' -------------------------------------------------------------------------
' Bounded storage and binary readers
' -------------------------------------------------------------------------

Private Sub midi_SetError(ByRef summary As MidiSummary, ByVal message As String)
    If summary.errorText = "" Then
        summary.errorText = message
    End If
End Sub


Private Function midi_ReserveEditableNotes(ByVal requiredCount As Integer) As Integer
    If requiredCount < 0 OrElse requiredCount > OSE_MAX_EDITABLE_NOTES Then
        Return 0
    End If
    If requiredCount <= midi_EditableNoteCapacity Then
        Return -1
    End If

    Dim As Integer newCapacity = midi_EditableNoteCapacity
    If newCapacity < 512 Then
        newCapacity = 512
    End If
    While newCapacity < requiredCount
        If newCapacity > OSE_MAX_EDITABLE_NOTES \ 2 Then
            newCapacity = OSE_MAX_EDITABLE_NOTES
        Else
            newCapacity *= 2
        End If
    Wend

    Redim Preserve midi_EditableNotes(0 To newCapacity - 1)
    midi_EditableNoteCapacity = newCapacity
    Return -1
End Function


Private Function midi_ReserveStoredEvents(ByVal requiredCount As Integer) As Integer
    If requiredCount < 0 OrElse requiredCount > OSE_MAX_STORED_EVENTS Then
        Return 0
    End If
    If requiredCount <= midi_StoredEventCapacity Then
        Return -1
    End If

    Dim As Integer newCapacity = midi_StoredEventCapacity
    If newCapacity < 1024 Then
        newCapacity = 1024
    End If
    While newCapacity < requiredCount
        If newCapacity > OSE_MAX_STORED_EVENTS \ 2 Then
            newCapacity = OSE_MAX_STORED_EVENTS
        Else
            newCapacity *= 2
        End If
    Wend

    Redim Preserve midi_StoredEvents(0 To newCapacity - 1)
    midi_StoredEventCapacity = newCapacity
    Return -1
End Function


Function midi_CopyCurrentState( _
    ByRef sourceSummary As MidiSummary, _
    ByRef destinationSummary As MidiSummary, _
    destinationNotes() As MidiEditableNote, _
    ByRef destinationNoteCount As Integer, _
    destinationEvents() As MidiStoredEvent, _
    ByRef destinationEventCount As Integer _
) As Integer
    If midi_EditableNoteCount < 0 OrElse _
        midi_EditableNoteCount > OSE_MAX_EDITABLE_NOTES OrElse _
        midi_StoredEventCount < 0 OrElse _
        midi_StoredEventCount > OSE_MAX_STORED_EVENTS Then Return 0

    destinationSummary = sourceSummary
    destinationNoteCount = midi_EditableNoteCount
    destinationEventCount = midi_StoredEventCount

    If destinationNoteCount = 0 Then
        Erase destinationNotes
    Else
        Redim destinationNotes(0 To destinationNoteCount - 1)
        For noteIndex As Integer = 0 To destinationNoteCount - 1
            destinationNotes(noteIndex) = midi_EditableNotes(noteIndex)
        Next
    End If

    If destinationEventCount = 0 Then
        Erase destinationEvents
    Else
        Redim destinationEvents(0 To destinationEventCount - 1)
        For eventIndex As Integer = 0 To destinationEventCount - 1
            destinationEvents(eventIndex) = midi_StoredEvents(eventIndex)
        Next
    End If
    Return -1
End Function


Function midi_RestoreState( _
    ByRef destinationSummary As MidiSummary, _
    ByRef sourceSummary As MidiSummary, _
    sourceNotes() As MidiEditableNote, _
    ByVal sourceNoteCount As Integer, _
    sourceEvents() As MidiStoredEvent, _
    ByVal sourceEventCount As Integer _
) As Integer
    If sourceNoteCount < 0 OrElse _
        sourceNoteCount > OSE_MAX_EDITABLE_NOTES OrElse _
        sourceEventCount < 0 OrElse _
        sourceEventCount > OSE_MAX_STORED_EVENTS Then Return 0

    If sourceNoteCount > 0 AndAlso midi_ReserveEditableNotes( _
        sourceNoteCount) = 0 Then Return 0
    If sourceEventCount > 0 AndAlso midi_ReserveStoredEvents( _
        sourceEventCount) = 0 Then Return 0

    destinationSummary = sourceSummary
    Erase midi_Data
    midi_DataSize = 0

    If sourceNoteCount = 0 Then
        midi_EditableNoteCount = 0
        ' Keep the allocation. The count makes stale slots inaccessible and
        ' avoids invalidating array bounds while restoring the other side.
    Else
        For noteIndex As Integer = 0 To sourceNoteCount - 1
            midi_EditableNotes(noteIndex) = sourceNotes(noteIndex)
        Next
    End If
    midi_EditableNoteCount = sourceNoteCount

    If sourceEventCount = 0 Then
        midi_StoredEventCount = 0
        ' Keep the allocation for the same bounded-history restore rule.
    Else
        For eventIndex As Integer = 0 To sourceEventCount - 1
            midi_StoredEvents(eventIndex) = sourceEvents(eventIndex)
        Next
    End If
    midi_StoredEventCount = sourceEventCount
    Return -1
End Function


Private Sub midi_HistorySnapshotClear( _
    ByRef historySnapshot As MidiHistorySnapshot _
)
    Erase historySnapshot.notes
    Erase historySnapshot.events
    Dim As MidiSummary emptySummary
    historySnapshot.summary = emptySummary
    historySnapshot.noteCount = 0
    historySnapshot.eventCount = 0
    historySnapshot.valid = 0
End Sub


Private Function midi_HistorySnapshotCapture( _
    ByRef historySnapshot As MidiHistorySnapshot, _
    ByRef summary As MidiSummary _
) As Integer
    If midi_EditableNoteCount < 0 OrElse _
        midi_EditableNoteCount > OSE_MAX_EDITABLE_NOTES OrElse _
        midi_StoredEventCount < 0 OrElse _
        midi_StoredEventCount > OSE_MAX_STORED_EVENTS Then Return 0

    midi_HistorySnapshotClear historySnapshot
    If midi_CopyCurrentState(summary, historySnapshot.summary, _
        historySnapshot.notes(), historySnapshot.noteCount, _
        historySnapshot.events(), historySnapshot.eventCount) = 0 Then
        midi_HistorySnapshotClear historySnapshot
        Return 0
    End If
    historySnapshot.valid = -1
    Return -1
End Function


Private Sub midi_HistoryStackClear( _
    historyStack() As MidiHistorySnapshot, _
    ByRef stackStart As Integer, _
    ByRef stackCount As Integer _
)
    For historyIndex As Integer = 0 To OSE_MIDI_HISTORY_STORAGE - 1
        midi_HistorySnapshotClear historyStack(historyIndex)
    Next
    stackStart = 0
    stackCount = 0
End Sub


Private Function midi_HistoryStackNewestIndex( _
    ByVal stackStart As Integer, _
    ByVal stackCount As Integer _
) As Integer
    If stackStart < 0 OrElse stackStart >= OSE_MIDI_HISTORY_STORAGE OrElse _
        stackCount <= 0 OrElse stackCount > OSE_MIDI_HISTORY_DEPTH Then Return -1
    Return (stackStart + stackCount - 1) Mod OSE_MIDI_HISTORY_STORAGE ' fblint: disable-line FBL406 REASON: Range checks keep the dividend nonnegative and the modulus positive before this calculation.
End Function


Private Function midi_HistoryStackPushCurrent( _
    historyStack() As MidiHistorySnapshot, _
    ByRef stackStart As Integer, _
    ByRef stackCount As Integer, _
    ByRef summary As MidiSummary _
) As Integer
    If stackStart < 0 OrElse stackStart >= OSE_MIDI_HISTORY_STORAGE OrElse _
        stackCount < 0 OrElse stackCount > OSE_MIDI_HISTORY_DEPTH Then Return 0

    Dim As Integer targetIndex = (stackStart + stackCount) Mod _
        OSE_MIDI_HISTORY_STORAGE
    If midi_HistorySnapshotCapture(historyStack(targetIndex), summary) = 0 Then _
        Return 0

    If stackCount = OSE_MIDI_HISTORY_DEPTH Then
        midi_HistorySnapshotClear historyStack(stackStart)
        stackStart = (stackStart + 1) Mod OSE_MIDI_HISTORY_STORAGE
    Else
        stackCount += 1
    End If
    Return -1
End Function


Private Sub midi_HistoryStackRemoveNewest( _
    historyStack() As MidiHistorySnapshot, _
    ByRef stackStart As Integer, _
    ByRef stackCount As Integer _
)
    Dim As Integer newestIndex = midi_HistoryStackNewestIndex( _
        stackStart, stackCount)
    If newestIndex < 0 Then
        Exit Sub
    End If
    midi_HistorySnapshotClear historyStack(newestIndex)
    stackCount -= 1
    If stackCount = 0 Then
        stackStart = 0
    End If
End Sub


Private Sub midi_HistoryStackRemoveOldest( _
    historyStack() As MidiHistorySnapshot, _
    ByRef stackStart As Integer, _
    ByRef stackCount As Integer _
)
    If stackStart < 0 OrElse stackStart >= OSE_MIDI_HISTORY_STORAGE OrElse _
        stackCount <= 0 OrElse stackCount > OSE_MIDI_HISTORY_DEPTH Then Exit Sub
    midi_HistorySnapshotClear historyStack(stackStart)
    stackCount -= 1
    If stackCount = 0 Then
        stackStart = 0
    Else
        stackStart = (stackStart + 1) Mod OSE_MIDI_HISTORY_STORAGE
    End If
End Sub


Private Function midi_HistorySnapshotPrepareRestore( _
    ByRef historySnapshot As MidiHistorySnapshot _
) As Integer
    If historySnapshot.valid = 0 OrElse historySnapshot.noteCount < 0 OrElse _
        historySnapshot.noteCount > OSE_MAX_EDITABLE_NOTES OrElse _
        historySnapshot.eventCount < 0 OrElse _
        historySnapshot.eventCount > OSE_MAX_STORED_EVENTS Then Return 0
    If historySnapshot.noteCount > 0 AndAlso _
        midi_ReserveEditableNotes(historySnapshot.noteCount) = 0 Then Return 0
    If historySnapshot.eventCount > 0 AndAlso _
        midi_ReserveStoredEvents(historySnapshot.eventCount) = 0 Then Return 0
    Return -1
End Function


Sub midi_HistoryClear()
    midi_HistoryStackClear midi_HistoryUndo(), midi_HistoryUndoStart, _
        midi_HistoryUndoCountValue
    midi_HistoryStackClear midi_HistoryRedo(), midi_HistoryRedoStart, _
        midi_HistoryRedoCountValue
    midi_HistoryPreparedIndex = -1
End Sub


Function midi_HistoryUndoCount() As Integer
    Return midi_HistoryUndoCountValue
End Function


Function midi_HistoryRedoCount() As Integer
    Return midi_HistoryRedoCountValue
End Function


Sub midi_HistoryDiscardOldestUndo()
    midi_HistoryStackRemoveOldest midi_HistoryUndo(), _
        midi_HistoryUndoStart, midi_HistoryUndoCountValue
End Sub


Sub midi_HistoryRedoClear()
    midi_HistoryStackClear midi_HistoryRedo(), midi_HistoryRedoStart, _
        midi_HistoryRedoCountValue
End Sub


Function midi_CaptureHistory(ByRef summary As MidiSummary) As Integer
    If midi_PrepareHistory(summary) = 0 Then
        Return 0
    End If
    If midi_CommitPreparedHistory() <> 0 Then
        Return -1
    End If
    midi_CancelPreparedHistory summary
    Return 0
End Function


Function midi_PrepareHistory(ByRef summary As MidiSummary) As Integer
    If midi_HistoryPreparedIndex >= 0 OrElse _
        midi_HistoryUndoStart < 0 OrElse _
        midi_HistoryUndoStart >= OSE_MIDI_HISTORY_STORAGE OrElse _
        midi_HistoryUndoCountValue < 0 OrElse _
        midi_HistoryUndoCountValue > OSE_MIDI_HISTORY_DEPTH Then Return 0

    Dim As Integer targetIndex = (midi_HistoryUndoStart + _
        midi_HistoryUndoCountValue) Mod OSE_MIDI_HISTORY_STORAGE
    If midi_HistorySnapshotCapture(midi_HistoryUndo(targetIndex), summary) = 0 Then _
        Return 0
    midi_HistoryPreparedIndex = targetIndex
    Return -1
End Function


Function midi_CommitPreparedHistory() As Integer
    If midi_HistoryPreparedIndex < 0 OrElse _
        midi_HistoryPreparedIndex >= OSE_MIDI_HISTORY_STORAGE Then Return 0

    If midi_HistoryUndoCountValue = OSE_MIDI_HISTORY_DEPTH Then
        midi_HistorySnapshotClear midi_HistoryUndo(midi_HistoryUndoStart)
        midi_HistoryUndoStart = (midi_HistoryUndoStart + 1) Mod _
            OSE_MIDI_HISTORY_STORAGE
    Else
        midi_HistoryUndoCountValue += 1
    End If
    midi_HistoryPreparedIndex = -1
    midi_HistoryStackClear midi_HistoryRedo(), midi_HistoryRedoStart, _
        midi_HistoryRedoCountValue
    Return -1
End Function


Function midi_CancelPreparedHistory(ByRef summary As MidiSummary) As Integer
    If midi_HistoryPreparedIndex < 0 OrElse _
        midi_HistoryPreparedIndex >= OSE_MIDI_HISTORY_STORAGE Then Return 0

    Dim As Integer preparedIndex = midi_HistoryPreparedIndex
    If midi_HistorySnapshotPrepareRestore( _
        midi_HistoryUndo(preparedIndex)) = 0 OrElse _
        midi_RestoreState(summary, midi_HistoryUndo(preparedIndex).summary, _
            midi_HistoryUndo(preparedIndex).notes(), _
            midi_HistoryUndo(preparedIndex).noteCount, _
            midi_HistoryUndo(preparedIndex).events(), _
            midi_HistoryUndo(preparedIndex).eventCount) = 0 Then Return 0

    midi_HistorySnapshotClear midi_HistoryUndo(preparedIndex)
    midi_HistoryPreparedIndex = -1
    Return -1
End Function


Function midi_Undo(ByRef summary As MidiSummary) As Integer
    If midi_HistoryPreparedIndex >= 0 Then
        Return 0
    End If
    Dim As Integer undoIndex = midi_HistoryStackNewestIndex( _
        midi_HistoryUndoStart, midi_HistoryUndoCountValue)
    If undoIndex < 0 OrElse _
        midi_HistorySnapshotPrepareRestore(midi_HistoryUndo(undoIndex)) = 0 Then _
        Return 0
    If midi_HistoryStackPushCurrent(midi_HistoryRedo(), _
        midi_HistoryRedoStart, midi_HistoryRedoCountValue, summary) = 0 Then _
        Return 0
    If midi_RestoreState(summary, midi_HistoryUndo(undoIndex).summary, _
        midi_HistoryUndo(undoIndex).notes(), _
        midi_HistoryUndo(undoIndex).noteCount, _
        midi_HistoryUndo(undoIndex).events(), _
        midi_HistoryUndo(undoIndex).eventCount) = 0 Then
        midi_HistoryStackRemoveNewest midi_HistoryRedo(), _
            midi_HistoryRedoStart, midi_HistoryRedoCountValue
        Return 0
    End If
    midi_HistoryStackRemoveNewest midi_HistoryUndo(), _
        midi_HistoryUndoStart, midi_HistoryUndoCountValue
    Return -1
End Function


Function midi_Redo(ByRef summary As MidiSummary) As Integer
    If midi_HistoryPreparedIndex >= 0 Then
        Return 0
    End If
    Dim As Integer redoIndex = midi_HistoryStackNewestIndex( _
        midi_HistoryRedoStart, midi_HistoryRedoCountValue)
    If redoIndex < 0 OrElse _
        midi_HistorySnapshotPrepareRestore(midi_HistoryRedo(redoIndex)) = 0 Then _
        Return 0
    If midi_HistoryStackPushCurrent(midi_HistoryUndo(), _
        midi_HistoryUndoStart, midi_HistoryUndoCountValue, summary) = 0 Then _
        Return 0
    If midi_RestoreState(summary, midi_HistoryRedo(redoIndex).summary, _
        midi_HistoryRedo(redoIndex).notes(), _
        midi_HistoryRedo(redoIndex).noteCount, _
        midi_HistoryRedo(redoIndex).events(), _
        midi_HistoryRedo(redoIndex).eventCount) = 0 Then
        midi_HistoryStackRemoveNewest midi_HistoryUndo(), _
            midi_HistoryUndoStart, midi_HistoryUndoCountValue
        Return 0
    End If
    midi_HistoryStackRemoveNewest midi_HistoryRedo(), _
        midi_HistoryRedoStart, midi_HistoryRedoCountValue
    Return -1
End Function


Private Function midi_AppendStoredEvent( _
    ByVal trackIndex As Integer, _
    ByVal eventTick As ULongInt, _
    ByVal eventKind As UByte, _
    ByVal statusByte As UByte, _
    ByVal data1 As UByte, _
    ByVal data2 As UByte, _
    ByVal eventOrder As Integer, _
    ByRef payload As String _
) As Integer
    If midi_ReserveStoredEvents(midi_StoredEventCount + 1) = 0 Then
        Return 0
    End If

    With midi_StoredEvents(midi_StoredEventCount)
        .tick = eventTick
        .trackIndex = trackIndex
        .eventKind = eventKind
        .statusByte = statusByte
        .data1 = data1
        .data2 = data2
        .order = eventOrder
        .payload = payload
    End With
    midi_StoredEventCount += 1
    Return -1
End Function


Private Function midi_AppendEditableNote( _
    ByVal trackIndex As Integer, _
    ByVal startTick As ULongInt, _
    ByVal durationTicks As ULongInt, _
    ByVal keyNumber As UByte, _
    ByVal midiChannel As UByte, _
    ByVal noteVelocity As UByte _
) As Integer
    If midi_ReserveEditableNotes(midi_EditableNoteCount + 1) = 0 Then
        Return -1
    End If

    With midi_EditableNotes(midi_EditableNoteCount)
        .startTick = startTick
        .durationTicks = durationTicks
        .keyNumber = keyNumber
        .channel = midiChannel
        .velocity = noteVelocity
        .trackIndex = trackIndex
        .startEventOrder = 0
        .endEventOrder = 0
    End With
    midi_EditableNoteCount += 1
    Return midi_EditableNoteCount - 1
End Function


Private Function midi_HasBytes( _
    ByVal offset As Integer, _
    ByVal count As Integer, _
    ByVal limit As Integer _
) As Integer
    If offset < 0 OrElse count < 0 Then
        Return 0
    End If
    If offset > limit Then
        Return 0
    End If
    If count > limit - offset Then
        Return 0
    End If
    Return -1
End Function


Private Function midi_MatchesChunk( _
    ByVal offset As Integer, _
    ByVal chunkName As String, _
    ByVal limit As Integer _
) As Integer
    If Len(chunkName) <> 4 Then
        Return 0
    End If
    If midi_HasBytes(offset, 4, limit) = 0 Then
        Return 0
    End If

    For index As Integer = 0 To 3
        If midi_Data(offset + index) <> _
            CUInt(Asc(Mid(chunkName, index + 1, 1))) Then
            Return 0
        End If
    Next

    Return -1
End Function


Private Function midi_ReadBe16(ByVal offset As Integer) As Integer
    Return (CInt(midi_Data(offset)) Shl 8) Or CInt(midi_Data(offset + 1))
End Function


Private Function midi_ReadBe32(ByVal offset As Integer) As ULong
    Return (CULng(midi_Data(offset)) Shl OSE_BE32_SHIFT_24) Or _
           (CULng(midi_Data(offset + 1)) Shl OSE_BE32_SHIFT_16) Or _
           (CULng(midi_Data(offset + 2)) Shl OSE_BE32_SHIFT_8) Or _
           CULng(midi_Data(offset + 3))
End Function


Private Function midi_ReadVariableLength( _
    ByRef offset As Integer, _
    ByVal limit As Integer, _
    ByRef value As ULong _
) As Integer
    Dim As ULongInt result = 0

    For byteIndex As Integer = 0 To OSE_MAX_VLQ_BYTES - 1 ' fblint: disable-line FBL311 REASON: SMF variable-length quantities contain at most four bytes.
        If midi_HasBytes(offset, 1, limit) = 0 Then
            Return 0
        End If

        Dim As UByte nextByte = midi_Data(offset)
        offset += 1
        result = (result Shl 7) Or CULngInt(nextByte And &H7F)

        If (nextByte And &H80) = 0 Then
            value = CULng(result)
            Return -1
        End If
    Next

    Return 0
End Function


Private Function midi_ReadText( _
    ByVal offset As Integer, _
    ByVal length As Integer, _
    ByVal limit As Integer _
) As String
    Dim As Integer safeLength = length

    If safeLength > OSE_MAX_TRACK_NAME Then _
        safeLength = OSE_MAX_TRACK_NAME
    If safeLength < 0 Then
        safeLength = 0
    End If
    If midi_HasBytes(offset, safeLength, limit) = 0 Then
        Return ""
    End If

    Dim As String result = Space(safeLength)

    For index As Integer = 0 To safeLength - 1
        Dim As UByte characterCode = midi_Data(offset + index)
        If characterCode >= 32 AndAlso characterCode <= 126 Then
            Mid(result, index + 1, 1) = Chr(characterCode)
        ElseIf characterCode = 9 Then
            Mid(result, index + 1, 1) = " "
        End If
    Next

    Return Trim(result)
End Function


Private Function midi_ReadBinaryString( _
    ByVal offset As Integer, _
    ByVal length As Integer, _
    ByVal limit As Integer _
) As String
    If length < 0 OrElse midi_HasBytes(offset, length, limit) = 0 Then
        Return ""
    End If
    If length = 0 Then
        Return ""
    End If

    Dim As String result = Space(length)
    For index As Integer = 0 To length - 1
        Mid(result, index + 1, 1) = Chr(midi_Data(offset + index))
    Next
    Return result
End Function


Private Function midi_IsTextMetaType(ByVal metaType As UByte) As Integer
    Select Case metaType
        Case &H01 To &H07
            Return -1
    End Select
    Return 0
End Function


Private Function midi_SanitizeTextValue(ByRef sourceValue As String) As String
    Dim As Integer safeLength = Len(sourceValue)
    If safeLength > OSE_MAX_TEXT_EVENT_BYTES Then _
        safeLength = OSE_MAX_TEXT_EVENT_BYTES
    If safeLength <= 0 Then
        Return ""
    End If

    Dim As String result = Space(safeLength)
    For index As Integer = 1 To safeLength
        Dim As Integer characterCode = Asc(Mid(sourceValue, index, 1))
        If characterCode >= 32 AndAlso characterCode <= 126 Then
            Mid(result, index, 1) = Chr(characterCode)
        ElseIf characterCode = 9 Then
            Mid(result, index, 1) = " "
        Else
            Mid(result, index, 1) = " "
        End If
    Next
    Return Trim(result)
End Function


Private Function midi_SystemDataLength(ByVal statusByte As UByte) As Integer
    Select Case statusByte
    Case &HF1, &HF3
        Return 1
    Case &HF2
        Return 2
    Case &HF6, &HF8 To &HFE
        Return 0
    Case Else
        Return -1
    End Select
End Function


Private Sub midi_SortTempoMap(ByRef summary As MidiSummary)
    For pointIndex As Integer = 1 To summary.tempoCount - 1
        Dim As MidiTempoPoint tempoPoint = summary.tempoMap(pointIndex)
        Dim As Integer insertIndex = pointIndex - 1
        While insertIndex >= 0 AndAlso _
            summary.tempoMap(insertIndex).tick > tempoPoint.tick
            summary.tempoMap(insertIndex + 1) = summary.tempoMap(insertIndex)
            insertIndex -= 1
        Wend
        summary.tempoMap(insertIndex + 1) = tempoPoint
    Next
End Sub


Private Sub midi_SortTimeSignatureMap(ByRef summary As MidiSummary)
    For pointIndex As Integer = 1 To summary.timeSignatureCount - 1
        Dim As MidiTimeSignaturePoint timeSignaturePoint = _
            summary.timeSignatureMap(pointIndex)
        Dim As Integer insertIndex = pointIndex - 1
        While insertIndex >= 0 AndAlso _
            summary.timeSignatureMap(insertIndex).tick > _
                timeSignaturePoint.tick
            summary.timeSignatureMap(insertIndex + 1) = _
                summary.timeSignatureMap(insertIndex)
            insertIndex -= 1
        Wend
        summary.timeSignatureMap(insertIndex + 1) = timeSignaturePoint
    Next
End Sub


Private Sub midi_SortKeySignatureMap(ByRef summary As MidiSummary)
    For pointIndex As Integer = 1 To summary.keySignatureCount - 1
        Dim As MidiKeySignaturePoint keySignaturePoint = _
            summary.keySignatureMap(pointIndex)
        Dim As Integer insertIndex = pointIndex - 1
        While insertIndex >= 0 AndAlso _
            summary.keySignatureMap(insertIndex).tick > keySignaturePoint.tick
            summary.keySignatureMap(insertIndex + 1) = _
                summary.keySignatureMap(insertIndex)
            insertIndex -= 1
        Wend
        summary.keySignatureMap(insertIndex + 1) = keySignaturePoint
    Next
End Sub


Private Function midi_FinalizeTimingMaps(ByRef summary As MidiSummary) As Integer
    If summary.tempoCount = 0 Then
        summary.tempoCount = 1
        summary.tempoMap(0).tick = 0
        summary.tempoMap(0).microsecondsPerQuarter = 500000
        summary.tempoMicrosecondsPerQuarter = 500000
    Else
        midi_SortTempoMap summary
        If summary.tempoMap(0).tick > 0 Then
            If summary.tempoCount >= OSE_MAX_TEMPO_EVENTS Then
                midi_SetError summary, "MIDI tempo-map limit exceeded"
                Return 0
            End If
            For pointIndex As Integer = summary.tempoCount To 1 Step -1
                summary.tempoMap(pointIndex) = summary.tempoMap(pointIndex - 1)
            Next
            summary.tempoMap(0).tick = 0
            summary.tempoMap(0).microsecondsPerQuarter = 500000
            summary.tempoCount += 1
        End If
    End If
    If summary.timeSignatureCount = 0 Then
        summary.timeSignatureCount = 1
        summary.timeSignatureMap(0).tick = 0
        summary.timeSignatureMap(0).numerator = 4
        summary.timeSignatureMap(0).denominatorPower = 2
        summary.timeSignatureMap(0).clocksPerMetronome = 24
        summary.timeSignatureMap(0).thirtySecondNotesPerQuarter = 8
    Else
        midi_SortTimeSignatureMap summary
        If summary.timeSignatureMap(0).tick > 0 Then
            If summary.timeSignatureCount >= OSE_MAX_TIME_SIGNATURE_EVENTS Then
                midi_SetError summary, "MIDI time-signature map limit exceeded"
                Return 0
            End If
            For pointIndex As Integer = summary.timeSignatureCount To 1 Step -1
                summary.timeSignatureMap(pointIndex) = _
                    summary.timeSignatureMap(pointIndex - 1)
            Next
            summary.timeSignatureMap(0).tick = 0
            summary.timeSignatureMap(0).numerator = 4
            summary.timeSignatureMap(0).denominatorPower = 2
            summary.timeSignatureMap(0).clocksPerMetronome = 24
            summary.timeSignatureMap(0).thirtySecondNotesPerQuarter = 8
            summary.timeSignatureCount += 1
        End If
    End If
    If summary.keySignatureCount = 0 Then
        summary.keySignatureCount = 1
        summary.keySignatureMap(0).tick = 0
        summary.keySignatureMap(0).sharpsFlats = 0
        summary.keySignatureMap(0).minor = 0
    Else
        midi_SortKeySignatureMap summary
        If summary.keySignatureMap(0).tick > 0 Then
            If summary.keySignatureCount >= OSE_MAX_KEY_SIGNATURE_EVENTS Then
                midi_SetError summary, "MIDI key-signature map limit exceeded"
                Return 0
            End If
            For pointIndex As Integer = summary.keySignatureCount To 1 Step -1
                summary.keySignatureMap(pointIndex) = _
                    summary.keySignatureMap(pointIndex - 1)
            Next
            summary.keySignatureMap(0).tick = 0
            summary.keySignatureMap(0).sharpsFlats = 0
            summary.keySignatureMap(0).minor = 0
            summary.keySignatureCount += 1
        End If
    End If
    Return -1
End Function


Private Function midi_StoredEventComesBefore( _
    ByRef leftEvent As MidiStoredEvent, _
    ByRef rightEvent As MidiStoredEvent _
) As Integer
    If leftEvent.trackIndex <> rightEvent.trackIndex Then _
        Return IIf(leftEvent.trackIndex < rightEvent.trackIndex, -1, 0)
    If leftEvent.tick <> rightEvent.tick Then _
        Return IIf(leftEvent.tick < rightEvent.tick, -1, 0)
    Return IIf(leftEvent.order < rightEvent.order, -1, 0)
End Function


Private Function midi_RebuildTimingMaps( _
    ByRef summary As MidiSummary, _
    ByVal excludedTrackIndex As Integer _
) As Integer
    summary.tempoCount = 0
    summary.timeSignatureCount = 0
    summary.keySignatureCount = 0
    summary.tempoMicrosecondsPerQuarter = 0
    Dim As Integer timingIndices(0 To OSE_MAX_TEMPO_EVENTS + _
        OSE_MAX_TIME_SIGNATURE_EVENTS + OSE_MAX_KEY_SIGNATURE_EVENTS - 1)
    Dim As Integer timingCount = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .trackIndex = excludedTrackIndex OrElse _
                .eventKind <> OSE_EVENT_META OrElse .statusByte <> &HFF Then _
                Continue For
            If .data1 <> &H51 AndAlso .data1 <> &H58 AndAlso .data1 <> &H59 Then _
                Continue For
        End With
        If timingCount > UBound(timingIndices) Then
            Return 0
        End If
        ' The event array may contain later editor insertions. Match the
        ' writer's track/tick/order sequence before building stable tick maps.
        Dim As Integer insertIndex = timingCount - 1
        While insertIndex >= 0 AndAlso midi_StoredEventComesBefore( _
            midi_StoredEvents(storedIndex), _
            midi_StoredEvents(timingIndices(insertIndex))) <> 0
            timingIndices(insertIndex + 1) = timingIndices(insertIndex)
            insertIndex -= 1
        Wend
        timingIndices(insertIndex + 1) = storedIndex
        timingCount += 1
    Next

    For timingIndex As Integer = 0 To timingCount - 1
        With midi_StoredEvents(timingIndices(timingIndex))
            Select Case .data1
            Case &H51
                If Len(.payload) <> 3 OrElse _
                    summary.tempoCount >= OSE_MAX_TEMPO_EVENTS Then Return 0
                Dim As ULong tempoValue = _
                    (CULng(Asc(Mid(.payload, 1, 1))) Shl 16) Or _
                    (CULng(Asc(Mid(.payload, 2, 1))) Shl 8) Or _
                    CULng(Asc(Mid(.payload, 3, 1)))
                summary.tempoMap(summary.tempoCount).tick = .tick
                summary.tempoMap(summary.tempoCount).microsecondsPerQuarter = _
                    tempoValue
                summary.tempoCount += 1
                If summary.tempoMicrosecondsPerQuarter = 0 Then _
                    summary.tempoMicrosecondsPerQuarter = tempoValue
            Case &H58
                If Len(.payload) <> 4 OrElse summary.timeSignatureCount >= _
                    OSE_MAX_TIME_SIGNATURE_EVENTS Then Return 0
                Dim As MidiTimeSignaturePoint signaturePoint
                signaturePoint.tick = .tick
                signaturePoint.numerator = CUByte(Asc(Mid(.payload, 1, 1)))
                signaturePoint.denominatorPower = CUByte(Asc(Mid(.payload, 2, 1)))
                signaturePoint.clocksPerMetronome = CUByte(Asc(Mid(.payload, 3, 1)))
                signaturePoint.thirtySecondNotesPerQuarter = CUByte(Asc(Mid(.payload, 4, 1)))
                summary.timeSignatureMap(summary.timeSignatureCount) = signaturePoint
                summary.timeSignatureCount += 1
            Case &H59
                If Len(.payload) <> 2 OrElse _
                    summary.keySignatureCount >= OSE_MAX_KEY_SIGNATURE_EVENTS Then _
                    Return 0
                Dim As Integer sharpsFlats = Asc(Mid(.payload, 1, 1))
                If sharpsFlats > 127 Then
                    sharpsFlats -= 256
                End If
                summary.keySignatureMap(summary.keySignatureCount).tick = .tick
                summary.keySignatureMap(summary.keySignatureCount).sharpsFlats = _
                    sharpsFlats
                summary.keySignatureMap(summary.keySignatureCount).minor = _
                    CUByte(Asc(Mid(.payload, 2, 1)))
                summary.keySignatureCount += 1
            End Select
        End With
    Next
    ' Defaults are cached points, never replacement source events. Explicit
    ' initial values survive through their retained events; removing their
    ' owning track restores the same fallbacks used when loading a file.
    Return midi_FinalizeTimingMaps(summary)
End Function


' Meta parsing owns structural-event validation and timing-map updates.
' The result distinguishes a normal event from EOT without exposing loop control.
Enum MidiMetaParseResult
    OSE_META_PARSE_FAILED = 0
    OSE_META_PARSE_CONTINUE = 1
    OSE_META_PARSE_END_TRACK = 2
End Enum

Private Function midi_ParseMetaEvent( _
    ByRef summary As MidiSummary, _
    ByRef track As MidiTrackSummary, _
    ByVal trackIndex As Integer, _
    ByRef offset As Integer, _
    ByVal trackEnd As Integer, _
    ByVal absoluteTick As ULongInt, _
    ByVal currentEventOrder As Integer _
) As MidiMetaParseResult
    If midi_HasBytes(offset, 1, trackEnd) = 0 Then
        midi_SetError summary, "truncated MIDI meta-event type"
        Return 0
    End If

    Dim As UByte metaType = midi_Data(offset)
    offset += 1
    Dim As ULong metaLength
    If midi_ReadVariableLength(offset, trackEnd, metaLength) = 0 Then
        midi_SetError summary, "truncated MIDI meta-event length"
        Return 0
    End If
    If metaLength > CULng(trackEnd - offset) Then
        midi_SetError summary, "MIDI meta-event exceeds its track"
        Return 0
    End If

    /'
        SMF assigns fixed payload sizes to these structural events.
        Accepting a different length can hide a damaged stream and
        causes the following bytes to be interpreted inconsistently
        by stricter sequencers when the document is saved again.
    '/
    If metaType = &H2F AndAlso metaLength <> 0 Then
        midi_SetError summary, "MIDI end-of-track event length is invalid"
        Return 0
    ElseIf metaType = &H51 AndAlso metaLength <> 3 Then
        midi_SetError summary, "MIDI tempo event length is invalid"
        Return 0
    ElseIf metaType = &H58 AndAlso metaLength <> 4 Then
        midi_SetError summary, _
            "MIDI time-signature event length is invalid"
        Return 0
    ElseIf metaType = &H59 AndAlso metaLength <> 2 Then
        midi_SetError summary, _
            "MIDI key-signature event length is invalid"
        Return 0
    End If

    track.eventCount += 1
    summary.eventCount += 1
    If metaType <> &H2F Then
        Dim As String metaPayload = midi_ReadBinaryString( _
            offset, CInt(metaLength), trackEnd)
        If midi_AppendStoredEvent(trackIndex, absoluteTick, _
            OSE_EVENT_META, &HFF, metaType, 0, _
            currentEventOrder, metaPayload) = 0 Then
            midi_SetError summary, "MIDI stored-event limit exceeded"
            Return 0
        End If
    End If
    If metaType = &H03 Then
        track.name = midi_ReadText(offset, CInt(metaLength), trackEnd)
    ElseIf metaType = &H01 AndAlso summary.documentTitle = "" Then
        summary.documentTitle = midi_ReadText(offset, CInt(metaLength), _
            trackEnd)
    ElseIf metaType = &H02 AndAlso summary.copyrightText = "" Then
        summary.copyrightText = midi_ReadText(offset, CInt(metaLength), _
            trackEnd)
    ElseIf metaType = &H05 AndAlso summary.lyricText = "" Then
        summary.lyricText = midi_ReadText(offset, CInt(metaLength), _
            trackEnd)
    ElseIf metaType = &H06 AndAlso summary.markerText = "" Then
        summary.markerText = midi_ReadText(offset, CInt(metaLength), _
            trackEnd)
    ElseIf metaType = &H51 AndAlso metaLength = 3 Then
        Dim As ULong tempoValue = _
            (CULng(midi_Data(offset)) Shl 16) Or _
            (CULng(midi_Data(offset + 1)) Shl 8) Or _
            CULng(midi_Data(offset + 2))
        If tempoValue = 0 Then
            midi_SetError summary, "MIDI tempo event has a zero value"
            Return 0
        End If
        If summary.tempoCount >= OSE_MAX_TEMPO_EVENTS Then
            midi_SetError summary, "MIDI tempo-map limit exceeded"
            Return 0
        End If
        With summary.tempoMap(summary.tempoCount)
            .tick = absoluteTick
            .microsecondsPerQuarter = tempoValue
        End With
        summary.tempoCount += 1
        If summary.tempoMicrosecondsPerQuarter = 0 Then
            summary.tempoMicrosecondsPerQuarter = tempoValue
        End If
    ElseIf metaType = &H58 AndAlso metaLength = 4 Then
        If midi_Data(offset) = 0 OrElse midi_Data(offset + 1) > 7 Then
            midi_SetError summary, "MIDI time-signature event is invalid"
            Return 0
        End If
        If summary.timeSignatureCount >= _
            OSE_MAX_TIME_SIGNATURE_EVENTS Then
            midi_SetError summary, "MIDI time-signature map limit exceeded"
            Return 0
        End If
        With summary.timeSignatureMap(summary.timeSignatureCount)
            .tick = absoluteTick
            .numerator = midi_Data(offset)
            .denominatorPower = midi_Data(offset + 1)
            .clocksPerMetronome = midi_Data(offset + 2)
            .thirtySecondNotesPerQuarter = midi_Data(offset + 3)
        End With
        summary.timeSignatureCount += 1
    ElseIf metaType = &H59 AndAlso metaLength = 2 Then
        Dim As Integer sharpsFlats = CInt(midi_Data(offset))
        If sharpsFlats > 127 Then
            sharpsFlats -= 256
        End If
        If sharpsFlats < -7 OrElse sharpsFlats > 7 OrElse _
            midi_Data(offset + 1) > 1 Then
            midi_SetError summary, "MIDI key-signature event is invalid"
            Return 0
        End If
        If summary.keySignatureCount >= _
            OSE_MAX_KEY_SIGNATURE_EVENTS Then
            midi_SetError summary, "MIDI key-signature map limit exceeded"
            Return 0
        End If
        With summary.keySignatureMap(summary.keySignatureCount)
            .tick = absoluteTick
            .sharpsFlats = sharpsFlats
            .minor = midi_Data(offset + 1)
        End With
        summary.keySignatureCount += 1
    End If

    offset += CInt(metaLength)
    If metaType = &H2F Then
        offset = trackEnd
        Return OSE_META_PARSE_END_TRACK
    End If
    Return OSE_META_PARSE_CONTINUE
End Function


' fblint: disable-next-line FBL111 REASON: one dispatcher must cover all Standard MIDI event families.
Private Function midi_ParseTrack( _
    ByRef summary As MidiSummary, _
    ByRef track As MidiTrackSummary, _
    ByVal trackIndex As Integer, _
    ByVal trackOffset As Integer, _
    ByVal trackLength As Integer _
) As Integer
    Dim As Integer trackEnd = trackOffset + trackLength
    Dim As Integer offset = trackOffset
    Dim As ULongInt absoluteTick = 0
    Dim As UByte runningStatus = 0
    Dim As Integer eventOrder = 0
    ' Standard MIDI note-off events identify only channel and key. A FIFO
    ' queue gives overlapping same-key notes deterministic ownership.
    Dim As Integer activeNoteHead(0 To 15, 0 To 127)
    Dim As Integer activeNoteTail(0 To 15, 0 To 127)
    Dim As Integer activeNoteNext()
    Redim activeNoteNext(0 To OSE_MAX_EDITABLE_NOTES - 1)

    For channelIndex As Integer = 0 To 15
        For keyIndex As Integer = 0 To 127
            activeNoteHead(channelIndex, keyIndex) = -1
            activeNoteTail(channelIndex, keyIndex) = -1
        Next
    Next

    While offset < trackEnd
        Dim As ULong deltaTick
        If midi_ReadVariableLength(offset, trackEnd, deltaTick) = 0 Then
            midi_SetError summary, "truncated MIDI delta-time"
            Return 0
        End If
        Dim As ULongInt deltaAsTick = CULngInt(deltaTick)
        If absoluteTick > OSE_MAX_MIDI_TICK OrElse _
            deltaAsTick > OSE_MAX_MIDI_TICK - absoluteTick Then
            midi_SetError summary, "MIDI track tick exceeds the supported range"
            Return 0
        End If
        absoluteTick += deltaAsTick

        If midi_HasBytes(offset, 1, trackEnd) = 0 Then
            midi_SetError summary, "truncated MIDI event status"
            Return 0
        End If

        Dim As Integer currentEventOrder = eventOrder
        eventOrder += 1

        Dim As UByte statusByte = midi_Data(offset)
        Dim As UByte firstDataByte = 0
        Dim As Integer hasFirstData = 0

        If statusByte < &H80 Then
            If runningStatus = 0 Then
                midi_SetError summary, "MIDI data byte without running status"
                Return 0
            End If
            firstDataByte = statusByte
            hasFirstData = -1
            statusByte = runningStatus
            ' The status byte was omitted, but its first data byte was already
            ' consumed above. Both one-byte and two-byte messages advance here.
            offset += 1
        Else
            offset += 1
            If statusByte >= &H80 AndAlso statusByte <= &HEF Then
                runningStatus = statusByte
            End If
        End If

        If statusByte >= &H80 AndAlso statusByte <= &HEF Then
            Dim As UByte eventType = statusByte And &HF0
            Dim As UByte midiChannel = statusByte And &H0F
            Dim As Integer dataCount = 2
            If eventType = &HC0 OrElse eventType = &HD0 Then
                dataCount = 1
            End If

            Dim As UByte data1 = firstDataByte
            Dim As UByte data2 = 0
            If hasFirstData = 0 Then
                If midi_HasBytes(offset, 1, trackEnd) = 0 Then
                    midi_SetError summary, "truncated MIDI event data"
                    Return 0
                End If
                data1 = midi_Data(offset)
                offset += 1
            End If
            If dataCount = 2 Then
                If midi_HasBytes(offset, 1, trackEnd) = 0 Then
                    midi_SetError summary, "truncated MIDI event data"
                    Return 0
                End If
                data2 = midi_Data(offset)
                offset += 1
            End If

            If data1 > 127 OrElse data2 > 127 Then
                midi_SetError summary, "MIDI channel data contains a status byte"
                Return 0
            End If

            track.eventCount += 1
            summary.eventCount += 1

            If eventType <> &H80 AndAlso eventType <> &H90 Then
                Dim As String emptyPayload = ""
                If midi_AppendStoredEvent(trackIndex, absoluteTick, _
                    OSE_EVENT_CHANNEL, statusByte, data1, data2, _
                    currentEventOrder, emptyPayload) = 0 Then
                    midi_SetError summary, "MIDI stored-event limit exceeded"
                    Return 0
                End If
            End If

            If eventType = &H90 AndAlso data2 <> 0 Then
                Dim As ULongInt previewDuration = 1
                If summary.division > 0 Then
                    previewDuration = CULngInt(summary.division) \ 4
                    If previewDuration = 0 Then
                        previewDuration = 1
                    End If
                End If

                Dim As Integer editableNoteIndex = midi_AppendEditableNote( _
                    trackIndex, absoluteTick, previewDuration, data1, _
                    midiChannel, data2)
                If editableNoteIndex < 0 Then
                    midi_SetError summary, "MIDI note limit exceeded"
                    Return 0
                End If
                midi_EditableNotes(editableNoteIndex).startEventOrder = _
                    currentEventOrder + 1
                activeNoteNext(editableNoteIndex) = -1
                Dim As Integer previousTail = activeNoteTail(midiChannel, data1)
                If previousTail >= 0 Then
                    activeNoteNext(previousTail) = editableNoteIndex
                Else
                    activeNoteHead(midiChannel, data1) = editableNoteIndex
                End If
                activeNoteTail(midiChannel, data1) = editableNoteIndex

                track.noteCount += 1
                summary.noteCount += 1
                If summary.previewCount < OSE_MAX_PREVIEW_NOTES Then
                    With summary.preview(summary.previewCount)
                        .tick = absoluteTick
                        .durationTicks = previewDuration
                        .keyNumber = data1
                        .channel = midiChannel
                        .trackIndex = trackIndex
                    End With
                    summary.previewCount += 1
                End If
            ElseIf eventType = &HB0 Then
                Select Case data1
                Case 7
                    summary.channelVolume(midiChannel) = data2
                Case 10
                    summary.channelPan(midiChannel) = data2
                Case 11
                    summary.channelExpression(midiChannel) = data2
                Case 91
                    summary.channelReverb(midiChannel) = data2
                Case 93
                    summary.channelChorus(midiChannel) = data2
                End Select
            ElseIf eventType = &HC0 Then
                summary.channelProgram(midiChannel) = data1
            ElseIf eventType = &HE0 Then
                summary.channelPitchBend(midiChannel) = _
                    CInt(data1) Or (CInt(data2) Shl 7)
            ElseIf eventType = &H80 OrElse _
                (eventType = &H90 AndAlso data2 = 0) Then
                Dim As Integer editableNoteIndex = _
                    activeNoteHead(midiChannel, data1)
                If editableNoteIndex >= 0 Then
                    Dim As ULongInt noteDuration = absoluteTick - _
                        midi_EditableNotes(editableNoteIndex).startTick
                    If noteDuration = 0 Then
                        noteDuration = 1
                    End If
                    midi_EditableNotes(editableNoteIndex).durationTicks = noteDuration
                    midi_EditableNotes(editableNoteIndex).endEventOrder = _
                        currentEventOrder + 1
                    activeNoteHead(midiChannel, data1) = _
                        activeNoteNext(editableNoteIndex)
                    activeNoteNext(editableNoteIndex) = -1
                    If activeNoteHead(midiChannel, data1) < 0 Then
                        activeNoteTail(midiChannel, data1) = -1
                    End If
                End If
            End If
            Continue While
        End If

        If statusByte = &HFF Then
            Dim As MidiMetaParseResult metaResult = midi_ParseMetaEvent( _
                summary, track, trackIndex, offset, trackEnd, _
                absoluteTick, currentEventOrder)
            If metaResult = OSE_META_PARSE_FAILED Then Return 0
            runningStatus = 0
            If metaResult = OSE_META_PARSE_END_TRACK Then Exit While
            Continue While
        End If

        If statusByte = &HF0 OrElse statusByte = &HF7 Then
            Dim As ULong sysexLength
            If midi_ReadVariableLength(offset, trackEnd, sysexLength) = 0 Then
                midi_SetError summary, "truncated MIDI system-exclusive length"
                Return 0
            End If
            If sysexLength > CULng(trackEnd - offset) Then
                midi_SetError summary, "MIDI system-exclusive event exceeds its track"
                Return 0
            End If
            Dim As String sysexPayload = midi_ReadBinaryString( _
                offset, CInt(sysexLength), trackEnd)
            If midi_AppendStoredEvent(trackIndex, absoluteTick, _
                OSE_EVENT_SYSEX, statusByte, 0, 0, _
                currentEventOrder, sysexPayload) = 0 Then
                midi_SetError summary, "MIDI stored-event limit exceeded"
                Return 0
            End If
            track.eventCount += 1
            summary.eventCount += 1
            offset += CInt(sysexLength)
            runningStatus = 0
            Continue While
        End If

        Dim As Integer systemDataLength = midi_SystemDataLength(statusByte)
        If systemDataLength < 0 OrElse _
            midi_HasBytes(offset, systemDataLength, trackEnd) = 0 Then
            midi_SetError summary, "unsupported or truncated MIDI system event"
            Return 0
        End If
        Dim As String systemPayload = midi_ReadBinaryString( _
            offset, systemDataLength, trackEnd)
        If midi_AppendStoredEvent(trackIndex, absoluteTick, _
            OSE_EVENT_SYSTEM, statusByte, 0, 0, _
            currentEventOrder, systemPayload) = 0 Then
            midi_SetError summary, "MIDI stored-event limit exceeded"
            Return 0
        End If
        offset += systemDataLength
        track.eventCount += 1
        summary.eventCount += 1
        runningStatus = 0
    Wend

    track.endTick = absoluteTick
    For channelIndex As Integer = 0 To 15
        For keyIndex As Integer = 0 To 127
            Dim As Integer editableNoteIndex = activeNoteHead(channelIndex, keyIndex)
            While editableNoteIndex >= 0
                Dim As ULongInt noteDuration = absoluteTick - _
                    midi_EditableNotes(editableNoteIndex).startTick
                If noteDuration = 0 Then
                    noteDuration = 1
                End If
                midi_EditableNotes(editableNoteIndex).durationTicks = noteDuration
                editableNoteIndex = activeNoteNext(editableNoteIndex)
            Wend
            activeNoteHead(channelIndex, keyIndex) = -1
            activeNoteTail(channelIndex, keyIndex) = -1
        Next
    Next
    If absoluteTick > summary.durationTicks Then
        summary.durationTicks = absoluteTick
    End If
    Return -1
End Function


' -------------------------------------------------------------------------
' Public document loading and display helpers
' -------------------------------------------------------------------------

Private Function midi_LoadSummaryIntoCurrent( _
    ByRef summary As MidiSummary, _
    ByVal filename As String _
) As Integer
    /'
        FileNumber and fileSize survive multiple checked runtime calls. Their
        declarations precede every generated error-resume label so both the
        FreeBASIC runtime and GCC see an initialized value on every path.
    '/
    Dim As Integer fileNumber = 0
    Dim As LongInt fileSize = 0

    summary.formatNumber = 0
    summary.trackCount = 0
    summary.division = 0
    summary.fileSize = 0
    summary.eventCount = 0
    summary.preservedEventCount = 0
    summary.noteCount = 0
    summary.previewCount = 0
    summary.tempoCount = 0
    summary.timeSignatureCount = 0
    summary.keySignatureCount = 0
    summary.tempoMicrosecondsPerQuarter = 0
    summary.durationTicks = 0
    summary.documentTitle = ""
    summary.copyrightText = ""
    summary.lyricText = ""
    summary.markerText = ""
    summary.errorText = ""

    For channelIndex As Integer = 0 To 15
        summary.channelProgram(channelIndex) = 0
        summary.channelVolume(channelIndex) = 127
        summary.channelExpression(channelIndex) = 127
        summary.channelPan(channelIndex) = 64
        summary.channelChorus(channelIndex) = 0
        summary.channelReverb(channelIndex) = 40
        summary.channelPitchBend(channelIndex) = 8192
    Next

    For index As Integer = 0 To OSE_MAX_MIDI_TRACKS - 1
        summary.tracks(index).name = ""
        summary.tracks(index).eventCount = 0
        summary.tracks(index).noteCount = 0
        summary.tracks(index).endTick = 0
    Next

    Erase midi_Data
    midi_DataSize = 0
    Erase midi_EditableNotes
    midi_EditableNoteCount = 0
    midi_EditableNoteCapacity = 0
    Erase midi_StoredEvents
    midi_StoredEventCount = 0
    midi_StoredEventCapacity = 0

    fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then
        midi_SetError summary, "could not open MIDI file: " + filename
        Return 0
    End If

    fileSize = LOF(fileNumber)
    If fileSize < 14 OrElse fileSize > OSE_MAX_MIDI_FILE_BYTES Then
        Close #fileNumber
        midi_SetError summary, "MIDI file size is outside the supported range"
        Return 0
    End If

    midi_DataSize = CInt(fileSize)
    Redim midi_Data(0 To midi_DataSize - 1)
    If binaryFile_ReadExact(fileNumber, 1, @midi_Data(0), midi_DataSize) = 0 Then
        Close #fileNumber
        midi_SetError summary, "MIDI file could not be read completely"
        Return 0
    End If
    Close #fileNumber
    summary.fileSize = fileSize

    If midi_MatchesChunk(0, "MThd", midi_DataSize) = 0 Then
        midi_SetError summary, "file does not begin with an MThd chunk"
        Return 0
    End If

    Dim As ULong headerLength = midi_ReadBe32(4)
    If headerLength < 6 OrElse headerLength > CULng(midi_DataSize - 8) Then
        midi_SetError summary, "invalid MIDI header length"
        Return 0
    End If

    summary.formatNumber = midi_ReadBe16(8)
    summary.trackCount = midi_ReadBe16(10)
    summary.division = midi_ReadBe16(12)

    If summary.formatNumber < 0 OrElse summary.formatNumber > 1 Then
        midi_SetError summary, "only MIDI formats 0 and 1 are supported"
        Return 0
    End If
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then
        midi_SetError summary, "MIDI track count is outside the supported range"
        Return 0
    End If
    If summary.formatNumber = 0 AndAlso summary.trackCount <> 1 Then
        midi_SetError summary, "MIDI format 0 must contain exactly one track"
        Return 0
    End If
    If (summary.division And &H8000) <> 0 OrElse summary.division = 0 Then
        midi_SetError summary, "SMPTE-time MIDI division is not supported"
        Return 0
    End If

    Dim As Integer offset = 8 + CInt(headerLength)
    For trackIndex As Integer = 0 To summary.trackCount - 1
        If midi_HasBytes(offset, 8, midi_DataSize) = 0 Then
            midi_SetError summary, "MIDI file ends before all tracks"
            Return 0
        End If
        If midi_MatchesChunk(offset, "MTrk", midi_DataSize) = 0 Then
            midi_SetError summary, "declared MIDI track does not begin with MTrk"
            Return 0
        End If

        Dim As ULong rawTrackLength = midi_ReadBe32(offset + 4)
        offset += 8
        If rawTrackLength > CULng(midi_DataSize - offset) Then
            midi_SetError summary, "MIDI track length exceeds the file"
            Return 0
        End If

        If midi_ParseTrack(summary, summary.tracks(trackIndex), trackIndex, _
                           offset, CInt(rawTrackLength)) = 0 Then
            Return 0
        End If
        offset += CInt(rawTrackLength)
    Next

    If midi_FinalizeTimingMaps(summary) = 0 Then
        Return 0
    End If
    midi_RebuildTextMetadata summary
    summary.preservedEventCount = midi_StoredEventCount

    Return -1
End Function


Function midi_LoadSummary( _
    ByRef summary As MidiSummary, _
    ByVal filename As String _
) As Integer
    /'
        Loading is transactional because Open can target an arbitrary user
        file. Parsing may rebuild every global model array before detecting a
        late malformed event, so the current document is staged first and
        restored on every rejection. Undo history is cleared only after a
        successful document boundary.
    '/
    Dim As MidiSummary previousSummary
    Dim previousNotes() As MidiEditableNote
    Dim previousEvents() As MidiStoredEvent
    Dim As Integer previousNoteCount
    Dim As Integer previousEventCount
    If midi_CopyCurrentState(summary, previousSummary, previousNotes(), _
        previousNoteCount, previousEvents(), previousEventCount) = 0 Then
        midi_SetError summary, "could not preserve the current MIDI document"
        Return 0
    End If

    If midi_LoadSummaryIntoCurrent(summary, filename) <> 0 Then
        midi_HistoryClear()
        Return -1
    End If

    Dim As String failureError = summary.errorText
    If midi_RestoreState(summary, previousSummary, previousNotes(), _
        previousNoteCount, previousEvents(), previousEventCount) = 0 Then
        summary.errorText = "MIDI load failed and the previous document " + _
            "could not be restored: " + failureError
        Return 0
    End If
    summary.errorText = failureError
    Return 0
End Function


Function midi_TrackDisplayName( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer _
) As String
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return ""
    End If
    If summary.tracks(trackIndex).name <> "" Then
        Return summary.tracks(trackIndex).name
    End If
    Return "Track " + Str(trackIndex + 1)
End Function


Function midi_SetTrackName( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal trackName As String _
) As Integer
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return 0
    End If
    If Len(trackName) > OSE_MAX_TRACK_NAME Then
        Return 0
    End If
    For characterIndex As Integer = 1 To Len(trackName)
        If Asc(Mid(trackName, characterIndex, 1)) = 0 Then
            Return 0
        End If
    Next

    Dim As Integer foundNameEvent = 0
    Dim As Integer storedIndex = 0
    While storedIndex < midi_StoredEventCount
        With midi_StoredEvents(storedIndex)
            If .trackIndex = trackIndex AndAlso _
                .eventKind = OSE_EVENT_META AndAlso .statusByte = &HFF AndAlso _
                .data1 = &H03 Then
                If trackName = "" Then
                    For shiftIndex As Integer = storedIndex To _
                        midi_StoredEventCount - 2
                        midi_StoredEvents(shiftIndex) = _
                            midi_StoredEvents(shiftIndex + 1)
                    Next
                    midi_StoredEventCount -= 1
                    Continue While
                End If
                .payload = trackName
                foundNameEvent = -1
            End If
        End With
        storedIndex += 1
    Wend

    If trackName <> "" AndAlso foundNameEvent = 0 Then
        If midi_StoredEventCount >= OSE_MAX_STORED_EVENTS Then
            Return 0
        End If
        Dim As Integer nextOrder = 0
        For storedIndex = 0 To midi_StoredEventCount - 1
            If midi_StoredEvents(storedIndex).trackIndex = trackIndex AndAlso _
                midi_StoredEvents(storedIndex).order >= nextOrder Then
                nextOrder = midi_StoredEvents(storedIndex).order + 1
            End If
        Next
        Dim As String namePayload = trackName
        If midi_AppendStoredEvent(trackIndex, 0, OSE_EVENT_META, &HFF, &H03, _
            0, nextOrder, namePayload) = 0 Then Return 0
    End If

    summary.tracks(trackIndex).name = trackName
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_KeyDisplayName(ByVal keyNumber As Integer) As String
    If keyNumber < 0 OrElse keyNumber > 127 Then
        Return "?"
    End If
    Dim As String noteNames(0 To 11) = _
        {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
    Dim As Integer octaveNumber = (keyNumber \ 12) - 1
    Return noteNames(keyNumber Mod 12) + Str(octaveNumber)
End Function


Function midi_EstimatedSeconds(ByRef summary As MidiSummary) As Double
    Return midi_TicksToSeconds(summary, summary.durationTicks)
End Function


Function midi_TicksToSeconds( _
    ByRef summary As MidiSummary, _
    ByVal targetTick As ULongInt _
) As Double
    If summary.division <= 0 OrElse targetTick = 0 Then
        Return 0.0
    End If

    Dim As Double seconds = 0.0
    Dim As ULongInt segmentStart = 0
    Dim As ULong tempoValue = 500000

    For pointIndex As Integer = 0 To summary.tempoCount - 1
        Dim As MidiTempoPoint tempoPoint = summary.tempoMap(pointIndex)
        If tempoPoint.tick > targetTick Then
            Exit For
        End If
        If tempoPoint.tick > segmentStart Then
            seconds += (CDbl(tempoPoint.tick - segmentStart) / _
                CDbl(summary.division)) * (CDbl(tempoValue) / 1000000.0)
        End If
        segmentStart = tempoPoint.tick
        tempoValue = tempoPoint.microsecondsPerQuarter
        If tempoValue = 0 Then
            tempoValue = 500000
        End If
    Next

    If targetTick > segmentStart Then
        seconds += (CDbl(targetTick - segmentStart) / _
            CDbl(summary.division)) * (CDbl(tempoValue) / 1000000.0)
    End If
    Return seconds
End Function


Function midi_SecondsToTicks( _
    ByRef summary As MidiSummary, _
    ByVal targetSeconds As Double _
) As ULongInt
    If summary.division <= 0 OrElse targetSeconds <= 0.0 Then
        Return 0
    End If

    Dim As Double remainingSeconds = targetSeconds
    Dim As ULongInt segmentStart = 0
    Dim As ULong tempoValue = 500000

    For pointIndex As Integer = 0 To summary.tempoCount - 1
        Dim As MidiTempoPoint tempoPoint = summary.tempoMap(pointIndex)
        If tempoPoint.tick < segmentStart Then
            Continue For
        End If

        Dim As ULongInt segmentTicks = tempoPoint.tick - segmentStart
        If segmentTicks > 0 Then
            Dim As Double segmentSeconds = _
                (CDbl(segmentTicks) / CDbl(summary.division)) * _
                (CDbl(tempoValue) / 1000000.0)
            If remainingSeconds < segmentSeconds Then
                Return segmentStart + CULngInt((remainingSeconds * _
                    CDbl(summary.division) * 1000000.0) / CDbl(tempoValue))
            End If
            remainingSeconds -= segmentSeconds
        End If

        segmentStart = tempoPoint.tick
        tempoValue = tempoPoint.microsecondsPerQuarter
        If tempoValue = 0 Then
            tempoValue = 500000
        End If
    Next

    Return segmentStart + CULngInt((remainingSeconds * _
        CDbl(summary.division) * 1000000.0) / CDbl(tempoValue))
End Function


' -------------------------------------------------------------------------
' Editable note model
' -------------------------------------------------------------------------

Function midi_NewDocument(ByRef summary As MidiSummary) As Integer
    ' Reset the private arrays together with the public summary. This keeps a
    ' newly created document from retaining notes or sidecar events from the
    ' document that was previously loaded in the process.
    Erase midi_Data
    midi_DataSize = 0
    Erase midi_EditableNotes
    midi_EditableNoteCount = 0
    midi_EditableNoteCapacity = 0
    Erase midi_StoredEvents
    midi_StoredEventCount = 0
    midi_StoredEventCapacity = 0
    midi_HistoryClear()

    Dim As MidiSummary emptySummary
    summary = emptySummary
    If midi_AddTrack(summary) < 0 Then
        Return 0
    End If
    Return -1
End Function


Function midi_AddTrack(ByRef summary As MidiSummary) As Integer
    If summary.trackCount < 0 OrElse _
        summary.trackCount >= OSE_MAX_MIDI_TRACKS Then Return -1

    If summary.trackCount = 0 Then
        summary.formatNumber = 0
        ' 480 pulses per quarter is a conventional editable-document default.
        summary.division = 480
        summary.fileSize = 0
        summary.eventCount = 0
        summary.preservedEventCount = 0
        summary.noteCount = 0
        summary.previewCount = 0
        summary.durationTicks = 0
        summary.errorText = ""
        summary.tempoCount = 1
        summary.tempoMap(0).tick = 0
        summary.tempoMap(0).microsecondsPerQuarter = 500000
        summary.tempoMicrosecondsPerQuarter = 500000
        summary.timeSignatureCount = 1
        summary.timeSignatureMap(0).tick = 0
        summary.timeSignatureMap(0).numerator = 4
        summary.timeSignatureMap(0).denominatorPower = 2
        summary.timeSignatureMap(0).clocksPerMetronome = 24
        summary.timeSignatureMap(0).thirtySecondNotesPerQuarter = 8
        summary.keySignatureCount = 1
        summary.keySignatureMap(0).tick = 0
        summary.keySignatureMap(0).sharpsFlats = 0
        summary.keySignatureMap(0).minor = 0
        For channelIndex As Integer = 0 To 15
            summary.channelProgram(channelIndex) = 0
            summary.channelVolume(channelIndex) = 127
            summary.channelExpression(channelIndex) = 127
            summary.channelPan(channelIndex) = 64
            summary.channelChorus(channelIndex) = 0
            summary.channelReverb(channelIndex) = 40
            summary.channelPitchBend(channelIndex) = 8192
        Next
        Erase midi_EditableNotes
        midi_EditableNoteCount = 0
        midi_EditableNoteCapacity = 0
        Erase midi_StoredEvents
        midi_StoredEventCount = 0
        midi_StoredEventCapacity = 0
    End If

    Dim As Integer newTrackIndex = summary.trackCount
    summary.tracks(newTrackIndex).name = ""
    summary.tracks(newTrackIndex).eventCount = 0
    summary.tracks(newTrackIndex).noteCount = 0
    summary.tracks(newTrackIndex).endTick = 0
    summary.trackCount += 1
    If summary.trackCount > 1 Then
        summary.formatNumber = 1
    End If
    Return newTrackIndex
End Function


Private Sub midi_RecalculateDuration(ByRef summary As MidiSummary)
    summary.durationTicks = 0
    For trackIndex As Integer = 0 To summary.trackCount - 1
        If summary.tracks(trackIndex).endTick > summary.durationTicks Then
            summary.durationTicks = summary.tracks(trackIndex).endTick
        End If
    Next
    For noteIndex As Integer = 0 To midi_EditableNoteCount - 1
        Dim As ULongInt noteEnd = midi_EditableNotes(noteIndex).startTick + _
            midi_EditableNotes(noteIndex).durationTicks
        If noteEnd > summary.durationTicks Then
            summary.durationTicks = noteEnd
        End If
    Next
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        If midi_StoredEvents(storedIndex).tick > summary.durationTicks Then
            summary.durationTicks = midi_StoredEvents(storedIndex).tick
        End If
    Next
End Sub


Private Sub midi_RecalculateDocumentCounts(ByRef summary As MidiSummary)
    Dim As Integer storedCount(0 To OSE_MAX_MIDI_TRACKS - 1)
    Dim As Integer noteCount(0 To OSE_MAX_MIDI_TRACKS - 1)

    For trackIndex As Integer = 0 To summary.trackCount - 1
        storedCount(trackIndex) = 0
        noteCount(trackIndex) = 0
    Next

    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        Dim As Integer storedTrack = midi_StoredEvents(storedIndex).trackIndex
        If storedTrack >= 0 AndAlso storedTrack < summary.trackCount Then
            storedCount(storedTrack) += 1
        End If
    Next

    For noteIndex As Integer = 0 To midi_EditableNoteCount - 1
        Dim As Integer noteTrack = midi_EditableNotes(noteIndex).trackIndex
        If noteTrack >= 0 AndAlso noteTrack < summary.trackCount Then
            noteCount(noteTrack) += 1
        End If
    Next

    summary.eventCount = 0
    summary.noteCount = midi_EditableNoteCount
    summary.preservedEventCount = midi_StoredEventCount
    summary.previewCount = 0
    For trackIndex As Integer = 0 To summary.trackCount - 1
        summary.tracks(trackIndex).noteCount = noteCount(trackIndex)
        ' The writer emits two channel events per editable note and one EOT.
        summary.tracks(trackIndex).eventCount = _
            storedCount(trackIndex) + noteCount(trackIndex) * 2 + 1
        summary.eventCount += summary.tracks(trackIndex).eventCount
    Next

    For noteIndex As Integer = 0 To midi_EditableNoteCount - 1
        If summary.previewCount >= OSE_MAX_PREVIEW_NOTES Then
            Exit For
        End If
        With summary.preview(summary.previewCount)
            .tick = midi_EditableNotes(noteIndex).startTick
            .durationTicks = midi_EditableNotes(noteIndex).durationTicks
            .keyNumber = midi_EditableNotes(noteIndex).keyNumber
            .channel = midi_EditableNotes(noteIndex).channel
            .trackIndex = midi_EditableNotes(noteIndex).trackIndex
        End With
        summary.previewCount += 1
    Next
End Sub


Private Function midi_ChannelEventIsLater( _
    ByRef storedEvent As MidiStoredEvent, _
    ByRef hasEvent As Integer, _
    ByRef lastTick As ULongInt, _
    ByRef lastTrack As Integer, _
    ByRef lastOrder As Integer _
) As Integer
    ' The loader processes complete tracks in file order. The writer sorts
    ' events within each track, so state comparison follows that same
    ' track-first ordering rather than global tick order.
    If hasEvent <> 0 AndAlso _
        (storedEvent.trackIndex < lastTrack OrElse _
        (storedEvent.trackIndex = lastTrack AndAlso _
            (storedEvent.tick < lastTick OrElse _
            (storedEvent.tick = lastTick AndAlso _
            storedEvent.order < lastOrder)))) Then
        Return 0
    End If

    hasEvent = -1
    lastTick = storedEvent.tick
    lastTrack = storedEvent.trackIndex
    lastOrder = storedEvent.order
    Return -1
End Function


Private Sub midi_RebuildChannelState(ByRef summary As MidiSummary)
    Dim As Integer hasProgram(0 To 15)
    Dim As Integer hasVolume(0 To 15)
    Dim As Integer hasExpression(0 To 15)
    Dim As Integer hasPan(0 To 15)
    Dim As Integer hasChorus(0 To 15)
    Dim As Integer hasReverb(0 To 15)
    Dim As Integer hasPitchBend(0 To 15)
    Dim As ULongInt lastProgramTick(0 To 15)
    Dim As ULongInt lastVolumeTick(0 To 15)
    Dim As ULongInt lastExpressionTick(0 To 15)
    Dim As ULongInt lastPanTick(0 To 15)
    Dim As ULongInt lastChorusTick(0 To 15)
    Dim As ULongInt lastReverbTick(0 To 15)
    Dim As ULongInt lastPitchBendTick(0 To 15)
    Dim As Integer lastProgramTrack(0 To 15)
    Dim As Integer lastVolumeTrack(0 To 15)
    Dim As Integer lastExpressionTrack(0 To 15)
    Dim As Integer lastPanTrack(0 To 15)
    Dim As Integer lastChorusTrack(0 To 15)
    Dim As Integer lastReverbTrack(0 To 15)
    Dim As Integer lastPitchBendTrack(0 To 15)
    Dim As Integer lastProgramOrder(0 To 15)
    Dim As Integer lastVolumeOrder(0 To 15)
    Dim As Integer lastExpressionOrder(0 To 15)
    Dim As Integer lastPanOrder(0 To 15)
    Dim As Integer lastChorusOrder(0 To 15)
    Dim As Integer lastReverbOrder(0 To 15)
    Dim As Integer lastPitchBendOrder(0 To 15)

    For channelIndex As Integer = 0 To 15
        summary.channelProgram(channelIndex) = 0
        summary.channelVolume(channelIndex) = 127
        summary.channelExpression(channelIndex) = 127
        summary.channelPan(channelIndex) = 64
        summary.channelChorus(channelIndex) = 0
        summary.channelReverb(channelIndex) = 40
        summary.channelPitchBend(channelIndex) = 8192
        hasProgram(channelIndex) = 0
        hasVolume(channelIndex) = 0
        hasExpression(channelIndex) = 0
        hasPan(channelIndex) = 0
        hasChorus(channelIndex) = 0
        hasReverb(channelIndex) = 0
        hasPitchBend(channelIndex) = 0
        lastProgramTrack(channelIndex) = -1
        lastVolumeTrack(channelIndex) = -1
        lastExpressionTrack(channelIndex) = -1
        lastPanTrack(channelIndex) = -1
        lastChorusTrack(channelIndex) = -1
        lastReverbTrack(channelIndex) = -1
        lastPitchBendTrack(channelIndex) = -1
        lastProgramOrder(channelIndex) = -1
        lastVolumeOrder(channelIndex) = -1
        lastExpressionOrder(channelIndex) = -1
        lastPanOrder(channelIndex) = -1
        lastChorusOrder(channelIndex) = -1
        lastReverbOrder(channelIndex) = -1
        lastPitchBendOrder(channelIndex) = -1
    Next

    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        Dim As MidiStoredEvent storedEvent = midi_StoredEvents(storedIndex)
        If storedEvent.eventKind <> OSE_EVENT_CHANNEL Then
            Continue For
        End If
        Dim As Integer channelIndex = storedEvent.statusByte And &H0F
        If channelIndex < 0 OrElse channelIndex > 15 Then
            Continue For
        End If

        Select Case storedEvent.statusByte And &HF0
        Case &HB0
            Select Case storedEvent.data1
            Case 7
                If midi_ChannelEventIsLater(storedEvent, hasVolume(channelIndex), _
                    lastVolumeTick(channelIndex), lastVolumeTrack(channelIndex), _
                    lastVolumeOrder(channelIndex)) <> 0 Then
                    summary.channelVolume(channelIndex) = storedEvent.data2
                End If
            Case 10
                If midi_ChannelEventIsLater(storedEvent, hasPan(channelIndex), _
                    lastPanTick(channelIndex), lastPanTrack(channelIndex), _
                    lastPanOrder(channelIndex)) <> 0 Then
                    summary.channelPan(channelIndex) = storedEvent.data2
                End If
            Case 11
                If midi_ChannelEventIsLater(storedEvent, hasExpression(channelIndex), _
                    lastExpressionTick(channelIndex), _
                    lastExpressionTrack(channelIndex), _
                    lastExpressionOrder(channelIndex)) <> 0 Then
                    summary.channelExpression(channelIndex) = storedEvent.data2
                End If
            Case 91
                If midi_ChannelEventIsLater(storedEvent, hasReverb(channelIndex), _
                    lastReverbTick(channelIndex), lastReverbTrack(channelIndex), _
                    lastReverbOrder(channelIndex)) <> 0 Then
                    summary.channelReverb(channelIndex) = storedEvent.data2
                End If
            Case 93
                If midi_ChannelEventIsLater(storedEvent, hasChorus(channelIndex), _
                    lastChorusTick(channelIndex), lastChorusTrack(channelIndex), _
                    lastChorusOrder(channelIndex)) <> 0 Then
                    summary.channelChorus(channelIndex) = storedEvent.data2
                End If
            End Select
        Case &HC0
            If midi_ChannelEventIsLater(storedEvent, hasProgram(channelIndex), _
                lastProgramTick(channelIndex), lastProgramTrack(channelIndex), _
                lastProgramOrder(channelIndex)) <> 0 Then
                summary.channelProgram(channelIndex) = storedEvent.data1
            End If
        Case &HE0
            If midi_ChannelEventIsLater(storedEvent, hasPitchBend(channelIndex), _
                lastPitchBendTick(channelIndex), _
                lastPitchBendTrack(channelIndex), _
                lastPitchBendOrder(channelIndex)) <> 0 Then
                summary.channelPitchBend(channelIndex) = _
                    CInt(storedEvent.data1) Or (CInt(storedEvent.data2) Shl 7)
            End If
        End Select
    Next
End Sub


Private Function midi_FindInitialTempoEvent() As Integer
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .trackIndex = 0 AndAlso .eventKind = OSE_EVENT_META AndAlso _
                .statusByte = &HFF AndAlso .data1 = &H51 AndAlso _
                .tick = 0 AndAlso Len(.payload) = 3 Then
                Return storedIndex
            End If
        End With
    Next
    Return -1
End Function


Private Function midi_FindInitialControllerEvent( _
    ByVal channelIndex As Integer, _
    ByVal controllerNumber As Integer _
) As Integer
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .trackIndex = 0 AndAlso .eventKind = OSE_EVENT_CHANNEL AndAlso _
                (.statusByte And &HF0) = &HB0 AndAlso _
                (.statusByte And &H0F) = channelIndex AndAlso _
                .data1 = controllerNumber AndAlso .tick = 0 Then
                Return storedIndex
            End If
        End With
    Next
    Return -1
End Function


Private Function midi_NextTrackEventOrder(ByVal trackIndex As Integer) As Integer
    Dim As Integer nextOrder = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        If midi_StoredEvents(storedIndex).trackIndex = trackIndex AndAlso _
            midi_StoredEvents(storedIndex).order >= nextOrder Then
            nextOrder = midi_StoredEvents(storedIndex).order + 1
        End If
    Next
    Return nextOrder
End Function


Private Function midi_UpsertInitialController( _
    ByVal channelIndex As Integer, _
    ByVal controllerNumber As Integer, _
    ByVal controllerValue As Integer _
) As Integer
    Dim As Integer firstEventIndex = -1
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .trackIndex = 0 AndAlso .eventKind = OSE_EVENT_CHANNEL AndAlso _
                (.statusByte And &HF0) = &HB0 AndAlso _
                (.statusByte And &H0F) = channelIndex AndAlso _
                .data1 = controllerNumber AndAlso .tick = 0 Then
                If firstEventIndex < 0 Then
                    firstEventIndex = storedIndex
                End If
                .data2 = CUByte(controllerValue)
            End If
        End With
    Next
    If firstEventIndex >= 0 Then
        Return -1
    End If

    Dim As String emptyPayload = ""
    If midi_AppendStoredEvent( _
        0, 0, OSE_EVENT_CHANNEL, CUByte(&HB0 Or channelIndex), _
        CUByte(controllerNumber), CUByte(controllerValue), _
        midi_NextTrackEventOrder(0), emptyPayload) = 0 Then
        Return 0
    End If

    Return -1
End Function


Function midi_SetInitialTempoBpm( _
    ByRef summary As MidiSummary, _
    ByVal beatsPerMinute As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return 0
    If beatsPerMinute < 20 OrElse beatsPerMinute > 400 Then
        Return 0
    End If

    Dim As ULong tempoValue = CULng(60000000 \ beatsPerMinute)
    If tempoValue = 0 OrElse tempoValue > &HFFFFFF Then
        Return 0
    End If

    Dim As Integer tempoMapIndex = -1
    For pointIndex As Integer = 0 To summary.tempoCount - 1
        If summary.tempoMap(pointIndex).tick = 0 Then
            tempoMapIndex = pointIndex
            Exit For
        End If
    Next
    If tempoMapIndex < 0 AndAlso _
        summary.tempoCount >= OSE_MAX_TEMPO_EVENTS Then Return 0
    If midi_StoredEventCount >= OSE_MAX_STORED_EVENTS AndAlso _
        midi_FindInitialTempoEvent() < 0 Then Return 0

    Dim As String tempoPayload = Chr(CInt((tempoValue Shr 16) And &HFF)) + _
        Chr(CInt((tempoValue Shr 8) And &HFF)) + _
        Chr(CInt(tempoValue And &HFF))
    Dim As Integer tempoEventIndex = -1
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .trackIndex = 0 AndAlso .eventKind = OSE_EVENT_META AndAlso _
                .statusByte = &HFF AndAlso .data1 = &H51 AndAlso _
                .tick = 0 AndAlso Len(.payload) = 3 Then
                If tempoEventIndex < 0 Then
                    tempoEventIndex = storedIndex
                End If
                .payload = tempoPayload
            End If
        End With
    Next
    If tempoEventIndex < 0 Then
        If midi_AppendStoredEvent( _
            0, 0, OSE_EVENT_META, &HFF, &H51, 0, _
            midi_NextTrackEventOrder(0), tempoPayload) = 0 Then
            Return 0
        End If
    End If

    If tempoMapIndex < 0 Then
        For pointIndex As Integer = summary.tempoCount To 1 Step -1
            summary.tempoMap(pointIndex) = summary.tempoMap(pointIndex - 1)
        Next
        summary.tempoMap(0).tick = 0
        summary.tempoCount += 1
        tempoMapIndex = 0
    Else
        /'
            A legal MIDI file may contain more than one tick-zero tempo event.
            The stored-event loop above updates every such event, so every
            matching cached map entry must change as well. Updating only the
            first entry lets sorting expose a stale BPM in the UI and timing
            conversion even though the serialized events contain the new BPM.
        '/
        For pointIndex As Integer = 0 To summary.tempoCount - 1
            If summary.tempoMap(pointIndex).tick = 0 Then _
                summary.tempoMap(pointIndex).microsecondsPerQuarter = tempoValue
        Next
    End If
    summary.tempoMap(tempoMapIndex).microsecondsPerQuarter = tempoValue
    midi_SortTempoMap summary
    summary.tempoMicrosecondsPerQuarter = _
        summary.tempoMap(0).microsecondsPerQuarter
    midi_RecalculateDocumentCounts summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_SetChannelMix( _
    ByRef summary As MidiSummary, _
    ByVal channelIndex As Integer, _
    ByVal volumeValue As Integer, _
    ByVal panValue As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return 0
    If channelIndex < 0 OrElse channelIndex > 15 Then
        Return 0
    End If
    If volumeValue < 0 OrElse volumeValue > 127 OrElse _
        panValue < 0 OrElse panValue > 127 Then Return 0

    Dim As Integer missingEvents = 0
    If midi_FindInitialControllerEvent(channelIndex, 7) < 0 Then _
        missingEvents += 1
    If midi_FindInitialControllerEvent(channelIndex, 10) < 0 Then _
        missingEvents += 1
    If missingEvents > OSE_MAX_STORED_EVENTS - midi_StoredEventCount Then _
        Return 0

    If midi_UpsertInitialController(channelIndex, 7, volumeValue) = 0 Then _
        Return 0
    If midi_UpsertInitialController(channelIndex, 10, panValue) = 0 Then _
        Return 0

    summary.channelVolume(channelIndex) = CUByte(volumeValue)
    summary.channelPan(channelIndex) = CUByte(panValue)
    midi_RecalculateDocumentCounts summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_SetChannelEffects( _
    ByRef summary As MidiSummary, _
    ByVal channelIndex As Integer, _
    ByVal chorusValue As Integer, _
    ByVal reverbValue As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return 0
    If channelIndex < 0 OrElse channelIndex > 15 Then
        Return 0
    End If
    If chorusValue < 0 OrElse chorusValue > 127 OrElse _
        reverbValue < 0 OrElse reverbValue > 127 Then Return 0

    Dim As Integer missingEvents = 0
    If midi_FindInitialControllerEvent(channelIndex, 93) < 0 Then _
        missingEvents += 1
    If midi_FindInitialControllerEvent(channelIndex, 91) < 0 Then _
        missingEvents += 1
    If missingEvents > OSE_MAX_STORED_EVENTS - midi_StoredEventCount Then _
        Return 0

    If midi_UpsertInitialController(channelIndex, 93, chorusValue) = 0 OrElse _
        midi_UpsertInitialController(channelIndex, 91, reverbValue) = 0 Then
        Return 0
    End If

    summary.channelChorus(channelIndex) = CUByte(chorusValue)
    summary.channelReverb(channelIndex) = CUByte(reverbValue)
    midi_RecalculateDocumentCounts summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_SetTempoPointBpm( _
    ByRef summary As MidiSummary, _
    ByVal tempoIndex As Integer, _
    ByVal beatsPerMinute As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return 0
    If tempoIndex < 0 OrElse tempoIndex >= summary.tempoCount Then
        Return 0
    End If
    If beatsPerMinute < 20 OrElse beatsPerMinute > 400 Then
        Return 0
    End If

    Dim As ULong tempoValue = CULng(60000000 \ beatsPerMinute)
    If tempoValue = 0 OrElse tempoValue > &HFFFFFF Then
        Return 0
    End If

    Dim As ULongInt targetTick = summary.tempoMap(tempoIndex).tick
    Dim As String tempoPayload = Chr(CInt((tempoValue Shr 16) And &HFF)) + _
        Chr(CInt((tempoValue Shr 8) And &HFF)) + _
        Chr(CInt(tempoValue And &HFF))
    Dim As Integer foundTempoEvent = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .eventKind = OSE_EVENT_META AndAlso .statusByte = &HFF AndAlso _
                .data1 = &H51 AndAlso .tick = targetTick AndAlso _
                Len(.payload) = 3 Then
                .payload = tempoPayload
                foundTempoEvent = -1
            End If
        End With
    Next
    If foundTempoEvent = 0 Then
        If midi_StoredEventCount >= OSE_MAX_STORED_EVENTS Then
            Return 0
        End If
        If midi_AppendStoredEvent( _
            0, targetTick, OSE_EVENT_META, &HFF, &H51, 0, _
            midi_NextTrackEventOrder(0), tempoPayload) = 0 Then
            Return 0
        End If
    End If

    For pointIndex As Integer = 0 To summary.tempoCount - 1
        If summary.tempoMap(pointIndex).tick = targetTick Then
            summary.tempoMap(pointIndex).microsecondsPerQuarter = tempoValue
        End If
    Next
    summary.tempoMicrosecondsPerQuarter = _
        summary.tempoMap(0).microsecondsPerQuarter
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_AddTempoPointBpm( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal beatsPerMinute As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return -1
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return -1
    End If
    If tick > OSE_MAX_MIDI_TICK Then
        Return -1
    End If
    If beatsPerMinute < 20 OrElse beatsPerMinute > 400 Then
        Return -1
    End If

    For pointIndex As Integer = 0 To summary.tempoCount - 1
        If summary.tempoMap(pointIndex).tick = tick Then
            Return -1
        End If
    Next

    If summary.tempoCount >= OSE_MAX_TEMPO_EVENTS OrElse _
        midi_StoredEventCount >= OSE_MAX_STORED_EVENTS Then Return -1

    Dim As ULong tempoValue = CULng(60000000 \ beatsPerMinute)
    If tempoValue = 0 OrElse tempoValue > &HFFFFFF Then
        Return -1
    End If
    Dim As String tempoPayload = Chr(CInt((tempoValue Shr 16) And &HFF)) + _
        Chr(CInt((tempoValue Shr 8) And &HFF)) + _
        Chr(CInt(tempoValue And &HFF))
    If midi_AppendStoredEvent( _
        trackIndex, tick, OSE_EVENT_META, &HFF, &H51, 0, _
        midi_NextTrackEventOrder(trackIndex), tempoPayload) = 0 Then
        Return -1
    End If

    With summary.tempoMap(summary.tempoCount)
        .tick = tick
        .microsecondsPerQuarter = tempoValue
    End With
    summary.tempoCount += 1
    midi_SortTempoMap summary
    summary.tempoMicrosecondsPerQuarter = _
        summary.tempoMap(0).microsecondsPerQuarter
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0

    For pointIndex As Integer = 0 To summary.tempoCount - 1
        If summary.tempoMap(pointIndex).tick = tick Then
            Return pointIndex
        End If
    Next
    Return -1
End Function


Function midi_RemoveTempoPoint( _
    ByRef summary As MidiSummary, _
    ByVal tempoIndex As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return 0
    If tempoIndex <= 0 OrElse tempoIndex >= summary.tempoCount Then
        Return 0
    End If

    Dim As ULongInt targetTick = summary.tempoMap(tempoIndex).tick
    Dim As Integer storedWriteIndex = 0
    For storedReadIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedReadIndex)
            If .eventKind = OSE_EVENT_META AndAlso _
                .statusByte = &HFF AndAlso .data1 = &H51 AndAlso _
                .tick = targetTick AndAlso Len(.payload) = 3 Then
                Continue For
            End If
            midi_StoredEvents(storedWriteIndex) = midi_StoredEvents(storedReadIndex)
            storedWriteIndex += 1
        End With
    Next
    midi_StoredEventCount = storedWriteIndex

    For pointIndex As Integer = tempoIndex To summary.tempoCount - 2
        summary.tempoMap(pointIndex) = summary.tempoMap(pointIndex + 1)
    Next
    summary.tempoCount -= 1
    summary.tempoMicrosecondsPerQuarter = _
        summary.tempoMap(0).microsecondsPerQuarter
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_SetTimeSignaturePoint( _
    ByRef summary As MidiSummary, _
    ByVal signatureIndex As Integer, _
    ByVal numerator As Integer, _
    ByVal denominatorPower As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return 0
    If signatureIndex < 0 OrElse _
        signatureIndex >= summary.timeSignatureCount Then Return 0
    If numerator < 1 OrElse numerator > 255 OrElse _
        denominatorPower < 0 OrElse denominatorPower > 7 Then Return 0

    Dim As ULongInt targetTick = _
        summary.timeSignatureMap(signatureIndex).tick
    Dim As Integer foundSignatureEvent = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .eventKind = OSE_EVENT_META AndAlso .statusByte = &HFF AndAlso _
                .data1 = &H58 AndAlso .tick = targetTick AndAlso _
                Len(.payload) = 4 Then
                Mid(.payload, 1, 1) = Chr(numerator)
                Mid(.payload, 2, 1) = Chr(denominatorPower)
                foundSignatureEvent = -1
            End If
        End With
    Next
    If foundSignatureEvent = 0 Then
        If midi_StoredEventCount >= OSE_MAX_STORED_EVENTS Then
            Return 0
        End If
        Dim As String signaturePayload = Chr(numerator) + _
            Chr(denominatorPower) + Chr(24) + Chr(8)
        If midi_AppendStoredEvent( _
            0, targetTick, OSE_EVENT_META, &HFF, &H58, 0, _
            midi_NextTrackEventOrder(0), signaturePayload) = 0 Then
            Return 0
        End If
    End If

    For pointIndex As Integer = 0 To summary.timeSignatureCount - 1
        If summary.timeSignatureMap(pointIndex).tick = targetTick Then
            summary.timeSignatureMap(pointIndex).numerator = CUByte(numerator)
            summary.timeSignatureMap(pointIndex).denominatorPower = _
                CUByte(denominatorPower)
        End If
    Next
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_AddTimeSignaturePoint( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal numerator As Integer, _
    ByVal denominatorPower As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return -1
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return -1
    End If
    If tick > OSE_MAX_MIDI_TICK Then
        Return -1
    End If
    If numerator < 1 OrElse numerator > 255 OrElse _
        denominatorPower < 0 OrElse denominatorPower > 7 Then Return -1

    For pointIndex As Integer = 0 To summary.timeSignatureCount - 1
        If summary.timeSignatureMap(pointIndex).tick = tick Then
            Return -1
        End If
    Next

    If summary.timeSignatureCount >= OSE_MAX_TIME_SIGNATURE_EVENTS OrElse _
        midi_StoredEventCount >= OSE_MAX_STORED_EVENTS Then Return -1

    Dim As String signaturePayload = Chr(numerator) + _
        Chr(denominatorPower) + Chr(24) + Chr(8)
    If midi_AppendStoredEvent( _
        trackIndex, tick, OSE_EVENT_META, &HFF, &H58, 0, _
        midi_NextTrackEventOrder(trackIndex), signaturePayload) = 0 Then
        Return -1
    End If

    With summary.timeSignatureMap(summary.timeSignatureCount)
        .tick = tick
        .numerator = CUByte(numerator)
        .denominatorPower = CUByte(denominatorPower)
        .clocksPerMetronome = 24
        .thirtySecondNotesPerQuarter = 8
    End With
    summary.timeSignatureCount += 1
    midi_SortTimeSignatureMap summary
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0

    For pointIndex As Integer = 0 To summary.timeSignatureCount - 1
        If summary.timeSignatureMap(pointIndex).tick = tick Then
            Return pointIndex
        End If
    Next
    Return -1
End Function


Function midi_RemoveTimeSignaturePoint( _
    ByRef summary As MidiSummary, _
    ByVal signatureIndex As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return 0
    If signatureIndex <= 0 OrElse _
        signatureIndex >= summary.timeSignatureCount Then Return 0

    Dim As ULongInt targetTick = _
        summary.timeSignatureMap(signatureIndex).tick
    Dim As Integer storedWriteIndex = 0
    For storedReadIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedReadIndex)
            If .eventKind = OSE_EVENT_META AndAlso _
                .statusByte = &HFF AndAlso .data1 = &H58 AndAlso _
                .tick = targetTick AndAlso Len(.payload) = 4 Then
                Continue For
            End If
            midi_StoredEvents(storedWriteIndex) = midi_StoredEvents(storedReadIndex)
            storedWriteIndex += 1
        End With
    Next
    midi_StoredEventCount = storedWriteIndex

    For pointIndex As Integer = signatureIndex To _
        summary.timeSignatureCount - 2
        summary.timeSignatureMap(pointIndex) = _
            summary.timeSignatureMap(pointIndex + 1)
    Next
    summary.timeSignatureCount -= 1
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_SetKeySignaturePoint( _
    ByRef summary As MidiSummary, _
    ByVal signatureIndex As Integer, _
    ByVal sharpsFlats As Integer, _
    ByVal minor As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return 0
    If signatureIndex < 0 OrElse _
        signatureIndex >= summary.keySignatureCount Then Return 0
    If sharpsFlats < -7 OrElse sharpsFlats > 7 OrElse _
        (minor <> 0 AndAlso minor <> 1) Then Return 0

    Dim As ULongInt targetTick = _
        summary.keySignatureMap(signatureIndex).tick
    Dim As Integer foundKeySignatureEvent = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .eventKind = OSE_EVENT_META AndAlso .statusByte = &HFF AndAlso _
                .data1 = &H59 AndAlso .tick = targetTick AndAlso _
                Len(.payload) = 2 Then
                Mid(.payload, 1, 1) = Chr(CInt(sharpsFlats And &HFF))
                Mid(.payload, 2, 1) = Chr(minor)
                foundKeySignatureEvent = -1
            End If
        End With
    Next

    If foundKeySignatureEvent = 0 Then
        If midi_StoredEventCount >= OSE_MAX_STORED_EVENTS Then
            Return 0
        End If
        Dim As String keySignaturePayload = _
            Chr(CInt(sharpsFlats And &HFF)) + Chr(minor)
        If midi_AppendStoredEvent( _
            0, targetTick, OSE_EVENT_META, &HFF, &H59, 0, _
            midi_NextTrackEventOrder(0), keySignaturePayload) = 0 Then
            Return 0
        End If
    End If

    For pointIndex As Integer = 0 To summary.keySignatureCount - 1
        If summary.keySignatureMap(pointIndex).tick = targetTick Then
            summary.keySignatureMap(pointIndex).sharpsFlats = sharpsFlats
            summary.keySignatureMap(pointIndex).minor = CUByte(minor)
        End If
    Next
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_AddKeySignaturePoint( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal sharpsFlats As Integer, _
    ByVal minor As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return -1
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return -1
    End If
    If tick > OSE_MAX_MIDI_TICK Then
        Return -1
    End If
    If sharpsFlats < -7 OrElse sharpsFlats > 7 OrElse _
        (minor <> 0 AndAlso minor <> 1) Then Return -1

    For pointIndex As Integer = 0 To summary.keySignatureCount - 1
        If summary.keySignatureMap(pointIndex).tick = tick Then
            Return -1
        End If
    Next
    If summary.keySignatureCount >= OSE_MAX_KEY_SIGNATURE_EVENTS OrElse _
        midi_StoredEventCount >= OSE_MAX_STORED_EVENTS Then Return -1

    Dim As String keySignaturePayload = _
        Chr(CInt(sharpsFlats And &HFF)) + Chr(minor)
    If midi_AppendStoredEvent( _
        trackIndex, tick, OSE_EVENT_META, &HFF, &H59, 0, _
        midi_NextTrackEventOrder(trackIndex), keySignaturePayload) = 0 Then
        Return -1
    End If

    With summary.keySignatureMap(summary.keySignatureCount)
        .tick = tick
        .sharpsFlats = sharpsFlats
        .minor = CUByte(minor)
    End With
    summary.keySignatureCount += 1
    midi_SortKeySignatureMap summary
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0

    For pointIndex As Integer = 0 To summary.keySignatureCount - 1
        If summary.keySignatureMap(pointIndex).tick = tick Then
            Return pointIndex
        End If
    Next
    Return -1
End Function


Function midi_RemoveKeySignaturePoint( _
    ByRef summary As MidiSummary, _
    ByVal signatureIndex As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return 0
    If signatureIndex <= 0 OrElse _
        signatureIndex >= summary.keySignatureCount Then Return 0

    Dim As ULongInt targetTick = _
        summary.keySignatureMap(signatureIndex).tick
    Dim As Integer storedWriteIndex = 0
    For storedReadIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedReadIndex)
            If .eventKind = OSE_EVENT_META AndAlso .statusByte = &HFF AndAlso _
                .data1 = &H59 AndAlso .tick = targetTick AndAlso _
                Len(.payload) = 2 Then
                Continue For
            End If
            midi_StoredEvents(storedWriteIndex) = midi_StoredEvents(storedReadIndex)
            storedWriteIndex += 1
        End With
    Next
    midi_StoredEventCount = storedWriteIndex

    For pointIndex As Integer = signatureIndex To _
        summary.keySignatureCount - 2
        summary.keySignatureMap(pointIndex) = _
            summary.keySignatureMap(pointIndex + 1)
    Next
    summary.keySignatureCount -= 1
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Private Sub midi_RebuildTrackNames(ByRef summary As MidiSummary)
    For trackIndex As Integer = 0 To summary.trackCount - 1
        summary.tracks(trackIndex).name = ""
    Next

    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .eventKind <> OSE_EVENT_META OrElse .statusByte <> &HFF OrElse _
                .data1 <> &H03 Then Continue For
            If .trackIndex < 0 OrElse .trackIndex >= summary.trackCount Then _
                Continue For
            Dim As String trackName = midi_SanitizeTextValue(.payload)
            If Len(trackName) > OSE_MAX_TRACK_NAME Then _
                trackName = Left(trackName, OSE_MAX_TRACK_NAME)
            summary.tracks(.trackIndex).name = trackName
        End With
    Next
End Sub


Private Sub midi_RebuildDocumentText(ByRef summary As MidiSummary)
    summary.documentTitle = ""
    summary.copyrightText = ""
    summary.lyricText = ""
    summary.markerText = ""

    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .eventKind <> OSE_EVENT_META OrElse .statusByte <> &HFF OrElse _
                midi_IsTextMetaType(.data1) = 0 Then Continue For
            Dim As String textValue = midi_SanitizeTextValue(.payload)
            Select Case .data1
                Case &H01
                    If summary.documentTitle = "" Then _
                        summary.documentTitle = textValue
                Case &H02
                    If summary.copyrightText = "" Then _
                        summary.copyrightText = textValue
                Case &H05
                    If summary.lyricText = "" Then
                        summary.lyricText = textValue
                    End If
                Case &H06
                    If summary.markerText = "" Then
                        summary.markerText = textValue
                    End If
            End Select
        End With
    Next
End Sub


Private Sub midi_RebuildTextMetadata(ByRef summary As MidiSummary)
    midi_RebuildTrackNames summary
    midi_RebuildDocumentText summary
End Sub


Function midi_GetTextEventCount() As Integer
    Dim As Integer textEventCount = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .eventKind = OSE_EVENT_META AndAlso .statusByte = &HFF AndAlso _
                midi_IsTextMetaType(.data1) <> 0 Then
                textEventCount += 1
            End If
        End With
    Next
    Return textEventCount
End Function


Function midi_GetTextEvent( _
    ByVal eventIndex As Integer, _
    ByRef textEvent As MidiTextEventPoint _
) As Integer
    If eventIndex < 0 Then
        Return 0
    End If

    Dim As Integer visibleIndex = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .eventKind <> OSE_EVENT_META OrElse .statusByte <> &HFF OrElse _
                midi_IsTextMetaType(.data1) = 0 Then Continue For
            If visibleIndex = eventIndex Then
                textEvent.tick = .tick
                textEvent.trackIndex = .trackIndex
                textEvent.metaType = .data1
                textEvent.textValue = midi_SanitizeTextValue(.payload)
                textEvent.sourceIndex = storedIndex
                Return -1
            End If
            visibleIndex += 1
        End With
    Next
    Return 0
End Function


Function midi_SetTextEvent( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer, _
    ByRef textEvent As MidiTextEventPoint _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return 0
    If sourceIndex < 0 OrElse sourceIndex >= midi_StoredEventCount Then
        Return 0
    End If
    If textEvent.trackIndex < 0 OrElse _
        textEvent.trackIndex >= summary.trackCount Then Return 0
    If textEvent.tick > OSE_MAX_MIDI_TICK Then
        Return 0
    End If
    If midi_IsTextMetaType(textEvent.metaType) = 0 Then
        Return 0
    End If
    If textEvent.metaType = &H03 AndAlso _
        Len(textEvent.textValue) > OSE_MAX_TRACK_NAME Then Return 0
    If Len(textEvent.textValue) > OSE_MAX_TEXT_EVENT_BYTES Then
        Return 0
    End If
    For characterIndex As Integer = 1 To Len(textEvent.textValue)
        If Asc(Mid(textEvent.textValue, characterIndex, 1)) = 0 Then
            Return 0
        End If
    Next

    With midi_StoredEvents(sourceIndex)
        If .eventKind <> OSE_EVENT_META OrElse .statusByte <> &HFF OrElse _
            midi_IsTextMetaType(.data1) = 0 Then Return 0
        If .trackIndex <> textEvent.trackIndex Then
            .order = midi_NextTrackEventOrder(textEvent.trackIndex)
        End If
        .tick = textEvent.tick
        .trackIndex = textEvent.trackIndex
        .data1 = textEvent.metaType
        .data2 = 0
        .payload = textEvent.textValue
    End With
    textEvent.sourceIndex = sourceIndex
    midi_RebuildTextMetadata summary
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_AddTextEvent( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal metaType As Integer, _
    ByVal textValue As String _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return -1
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return -1
    End If
    If tick > OSE_MAX_MIDI_TICK Then
        Return -1
    End If
    If metaType < &H01 OrElse metaType > &H07 Then
        Return -1
    End If
    If metaType = &H03 AndAlso Len(textValue) > OSE_MAX_TRACK_NAME Then
        Return -1
    End If
    If Len(textValue) > OSE_MAX_TEXT_EVENT_BYTES Then
        Return -1
    End If
    For characterIndex As Integer = 1 To Len(textValue)
        If Asc(Mid(textValue, characterIndex, 1)) = 0 Then
            Return -1
        End If
    Next
    If midi_StoredEventCount >= OSE_MAX_STORED_EVENTS Then
        Return -1
    End If

    Dim As Integer sourceIndex = midi_StoredEventCount
    Dim As String payload = textValue
    If midi_AppendStoredEvent(trackIndex, tick, OSE_EVENT_META, &HFF, _
        CUByte(metaType), 0, midi_NextTrackEventOrder(trackIndex), payload) = 0 Then
        Return -1
    End If
    midi_RebuildTextMetadata summary
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return sourceIndex
End Function


Function midi_RemoveTextEvent( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer _
) As Integer
    If sourceIndex < 0 OrElse sourceIndex >= midi_StoredEventCount Then
        Return 0
    End If
    With midi_StoredEvents(sourceIndex)
        If .eventKind <> OSE_EVENT_META OrElse .statusByte <> &HFF OrElse _
            midi_IsTextMetaType(.data1) = 0 Then Return 0
    End With

    For storedIndex As Integer = sourceIndex To midi_StoredEventCount - 2
        midi_StoredEvents(storedIndex) = midi_StoredEvents(storedIndex + 1)
    Next
    midi_StoredEventCount -= 1
    midi_RebuildTextMetadata summary
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_GetControllerPointCount() As Integer
    Dim As Integer pointCount = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        If midi_StoredEvents(storedIndex).eventKind = OSE_EVENT_CHANNEL AndAlso _
            (midi_StoredEvents(storedIndex).statusByte And &HF0) = &HB0 Then
            pointCount += 1
        End If
    Next
    Return pointCount
End Function


Function midi_GetControllerPoint( _
    ByVal pointIndex As Integer, _
    ByRef controllerPoint As MidiControllerPoint _
) As Integer
    If pointIndex < 0 Then
        Return 0
    End If

    Dim As Integer visibleIndex = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .eventKind = OSE_EVENT_CHANNEL AndAlso _
                (.statusByte And &HF0) = &HB0 Then
                If visibleIndex = pointIndex Then
                    controllerPoint.tick = .tick
                    controllerPoint.channel = .statusByte And &H0F
                    controllerPoint.controllerNumber = .data1
                    controllerPoint.controllerValue = .data2
                    controllerPoint.trackIndex = .trackIndex
                    controllerPoint.sourceIndex = storedIndex
                    Return -1
                End If
                visibleIndex += 1
            End If
        End With
    Next
    Return 0
End Function


Function midi_SetControllerPoint( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer, _
    ByRef controllerPoint As MidiControllerPoint _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return 0
    If sourceIndex < 0 OrElse sourceIndex >= midi_StoredEventCount Then
        Return 0
    End If
    If controllerPoint.trackIndex < 0 OrElse _
        controllerPoint.trackIndex >= summary.trackCount Then Return 0
    If controllerPoint.tick > OSE_MAX_MIDI_TICK Then
        Return 0
    End If
    If controllerPoint.channel > 15 OrElse _
        controllerPoint.controllerNumber > 127 OrElse _
        controllerPoint.controllerValue > 127 Then Return 0

    With midi_StoredEvents(sourceIndex)
        If .eventKind <> OSE_EVENT_CHANNEL OrElse _
            (.statusByte And &HF0) <> &HB0 Then Return 0
        If .trackIndex <> controllerPoint.trackIndex Then
            .order = midi_NextTrackEventOrder(controllerPoint.trackIndex)
        End If
        .tick = controllerPoint.tick
        .trackIndex = controllerPoint.trackIndex
        .statusByte = CUByte(&HB0 Or controllerPoint.channel)
        .data1 = controllerPoint.controllerNumber
        .data2 = controllerPoint.controllerValue
    End With
    controllerPoint.sourceIndex = sourceIndex
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    midi_RebuildChannelState summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_AddControllerPoint( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal channelIndex As Integer, _
    ByVal controllerNumber As Integer, _
    ByVal controllerValue As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return -1
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return -1
    End If
    If tick > OSE_MAX_MIDI_TICK Then
        Return -1
    End If
    If channelIndex < 0 OrElse channelIndex > 15 Then
        Return -1
    End If
    If controllerNumber < 0 OrElse controllerNumber > 127 OrElse _
        controllerValue < 0 OrElse controllerValue > 127 Then Return -1
    If midi_StoredEventCount >= OSE_MAX_STORED_EVENTS Then
        Return -1
    End If

    Dim As String emptyPayload = ""
    Dim As Integer sourceIndex = midi_StoredEventCount
    If midi_AppendStoredEvent( _
        trackIndex, tick, OSE_EVENT_CHANNEL, CUByte(&HB0 Or channelIndex), _
        CUByte(controllerNumber), CUByte(controllerValue), _
        midi_NextTrackEventOrder(trackIndex), emptyPayload) = 0 Then
        Return -1
    End If
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    midi_RebuildChannelState summary
    summary.fileSize = 0
    Return sourceIndex
End Function


Function midi_RemoveControllerPoint( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer _
) As Integer
    If sourceIndex < 0 OrElse sourceIndex >= midi_StoredEventCount Then
        Return 0
    End If
    If midi_StoredEvents(sourceIndex).eventKind <> OSE_EVENT_CHANNEL OrElse _
        (midi_StoredEvents(sourceIndex).statusByte And &HF0) <> &HB0 Then Return 0

    For storedIndex As Integer = sourceIndex To midi_StoredEventCount - 2
        midi_StoredEvents(storedIndex) = midi_StoredEvents(storedIndex + 1)
    Next
    midi_StoredEventCount -= 1
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    midi_RebuildChannelState summary
    summary.fileSize = 0
    Return -1
End Function


Private Function midi_ChannelMessageTypeIsEditable( _
    ByVal messageType As Integer _
) As Integer
    Select Case messageType
        Case &HA0, &HB0, &HC0, &HD0, &HE0
            Return -1
    End Select
    Return 0
End Function


Function midi_GetChannelEventCount() As Integer
    Dim As Integer channelEventCount = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        If midi_StoredEvents(storedIndex).eventKind = OSE_EVENT_CHANNEL Then
            channelEventCount += 1
        End If
    Next
    Return channelEventCount
End Function


Function midi_GetChannelEvent( _
    ByVal eventIndex As Integer, _
    ByRef channelEvent As MidiChannelEventPoint _
) As Integer
    If eventIndex < 0 Then
        Return 0
    End If

    Dim As Integer visibleIndex = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .eventKind <> OSE_EVENT_CHANNEL Then
                Continue For
            End If
            If visibleIndex = eventIndex Then
                channelEvent.tick = .tick
                channelEvent.channel = .statusByte And &H0F
                channelEvent.messageType = .statusByte And &HF0
                channelEvent.data1 = .data1
                channelEvent.data2 = .data2
                channelEvent.trackIndex = .trackIndex
                channelEvent.sourceIndex = storedIndex
                Return -1
            End If
            visibleIndex += 1
        End With
    Next
    Return 0
End Function


Function midi_SetChannelEvent( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer, _
    ByRef channelEvent As MidiChannelEventPoint _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return 0
    If sourceIndex < 0 OrElse sourceIndex >= midi_StoredEventCount Then
        Return 0
    End If
    If channelEvent.trackIndex < 0 OrElse _
        channelEvent.trackIndex >= summary.trackCount Then Return 0
    If channelEvent.tick > OSE_MAX_MIDI_TICK Then
        Return 0
    End If
    If channelEvent.channel > 15 OrElse _
        midi_ChannelMessageTypeIsEditable(channelEvent.messageType) = 0 Then _
        Return 0
    If channelEvent.data1 > 127 OrElse channelEvent.data2 > 127 Then
        Return 0
    End If

    With midi_StoredEvents(sourceIndex)
        If .eventKind <> OSE_EVENT_CHANNEL OrElse _
            midi_ChannelMessageTypeIsEditable(.statusByte And &HF0) = 0 Then _
            Return 0
        If .trackIndex <> channelEvent.trackIndex Then
            .order = midi_NextTrackEventOrder(channelEvent.trackIndex)
        End If
        .tick = channelEvent.tick
        .trackIndex = channelEvent.trackIndex
        .statusByte = CUByte(channelEvent.messageType Or channelEvent.channel)
        .data1 = channelEvent.data1
        If channelEvent.messageType = &HC0 OrElse _
            channelEvent.messageType = &HD0 Then
            .data2 = 0
        Else
            .data2 = channelEvent.data2
        End If
        channelEvent.data2 = .data2
    End With
    channelEvent.sourceIndex = sourceIndex
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    midi_RebuildChannelState summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_AddChannelEvent( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal channelIndex As Integer, _
    ByVal messageType As Integer, _
    ByVal data1 As Integer, _
    ByVal data2 As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return -1
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return -1
    End If
    If tick > OSE_MAX_MIDI_TICK Then
        Return -1
    End If
    If channelIndex < 0 OrElse channelIndex > 15 Then
        Return -1
    End If
    If midi_ChannelMessageTypeIsEditable(messageType) = 0 Then
        Return -1
    End If
    If data1 < 0 OrElse data1 > 127 OrElse data2 < 0 OrElse data2 > 127 Then _
        Return -1
    If midi_StoredEventCount >= OSE_MAX_STORED_EVENTS Then
        Return -1
    End If

    Dim As UByte storedData2 = CUByte(data2)
    If messageType = &HC0 OrElse messageType = &HD0 Then
        storedData2 = 0
    End If

    Dim As String emptyPayload = ""
    Dim As Integer sourceIndex = midi_StoredEventCount
    If midi_AppendStoredEvent( _
        trackIndex, tick, OSE_EVENT_CHANNEL, _
        CUByte(messageType Or channelIndex), CUByte(data1), storedData2, _
        midi_NextTrackEventOrder(trackIndex), emptyPayload) = 0 Then
        Return -1
    End If
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    midi_RebuildChannelState summary
    summary.fileSize = 0
    Return sourceIndex
End Function


Function midi_AddSystemExclusiveEvent( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal statusByte As Integer, _
    ByVal payload As String _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return -1
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return -1
    End If
    If tick > OSE_MAX_MIDI_TICK Then
        Return -1
    End If
    If statusByte <> &HF0 AndAlso statusByte <> &HF7 Then
        Return -1
    End If
    If Len(payload) > OSE_MAX_SYSEX_EVENT_BYTES Then
        Return -1
    End If
    If midi_StoredEventCount >= OSE_MAX_STORED_EVENTS Then
        Return -1
    End If

    Dim As Integer sourceIndex = midi_StoredEventCount
    Dim As String sysexPayload = payload
    If midi_AppendStoredEvent( _
        trackIndex, tick, OSE_EVENT_SYSEX, CUByte(statusByte), 0, 0, _
        midi_NextTrackEventOrder(trackIndex), sysexPayload) = 0 Then
        Return -1
    End If
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return sourceIndex
End Function


Function midi_GetSystemExclusiveEventCount() As Integer
    Dim As Integer sysexEventCount = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        If midi_StoredEvents(storedIndex).eventKind = OSE_EVENT_SYSEX Then _
            sysexEventCount += 1
    Next
    Return sysexEventCount
End Function


Function midi_GetSystemExclusiveEvent( _
    ByVal eventIndex As Integer, _
    ByRef sysexEvent As MidiSystemExclusivePoint _
) As Integer
    If eventIndex < 0 Then
        Return 0
    End If

    Dim As Integer visibleIndex = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .eventKind <> OSE_EVENT_SYSEX Then
                Continue For
            End If
            If visibleIndex = eventIndex Then
                sysexEvent.tick = .tick
                sysexEvent.trackIndex = .trackIndex
                sysexEvent.statusByte = .statusByte
                sysexEvent.payload = .payload
                sysexEvent.sourceIndex = storedIndex
                Return -1
            End If
            visibleIndex += 1
        End With
    Next
    Return 0
End Function


Private Function midi_IsEditableSystemStatus( _
    ByVal statusByte As Integer, _
    ByRef dataLength As Integer _
) As Integer
    Select Case statusByte
        Case &HF1, &HF3
            dataLength = 1
        Case &HF2
            dataLength = 2
        Case &HF6
            dataLength = 0
        Case Else
            dataLength = 0
            Return 0
    End Select
    Return -1
End Function


Function midi_GetSystemEventCount() As Integer
    Dim As Integer systemEventCount = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        If midi_StoredEvents(storedIndex).eventKind = OSE_EVENT_SYSTEM Then _
            systemEventCount += 1
    Next
    Return systemEventCount
End Function


Function midi_GetSystemEvent( _
    ByVal eventIndex As Integer, _
    ByRef systemEvent As MidiSystemEventPoint _
) As Integer
    If eventIndex < 0 Then
        Return 0
    End If

    Dim As Integer visibleIndex = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .eventKind <> OSE_EVENT_SYSTEM Then
                Continue For
            End If
            If visibleIndex = eventIndex Then
                systemEvent.tick = .tick
                systemEvent.trackIndex = .trackIndex
                systemEvent.statusByte = .statusByte
                systemEvent.dataLength = Len(.payload)
                If systemEvent.dataLength > 2 Then _
                    systemEvent.dataLength = 2
                systemEvent.data1 = 0
                systemEvent.data2 = 0
                If systemEvent.dataLength >= 1 Then _
                    systemEvent.data1 = CByte(Asc(Mid(.payload, 1, 1)))
                If systemEvent.dataLength >= 2 Then _
                    systemEvent.data2 = CByte(Asc(Mid(.payload, 2, 1)))
                systemEvent.sourceIndex = storedIndex
                Return -1
            End If
            visibleIndex += 1
        End With
    Next
    Return 0
End Function


Function midi_SetSystemEvent( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer, _
    ByRef systemEvent As MidiSystemEventPoint _
) As Integer
    If sourceIndex < 0 OrElse sourceIndex >= midi_StoredEventCount Then
        Return 0
    End If
    If midi_StoredEvents(sourceIndex).eventKind <> OSE_EVENT_SYSTEM Then _
        Return 0
    If systemEvent.trackIndex < 0 OrElse _
        systemEvent.trackIndex >= summary.trackCount Then Return 0
    If systemEvent.tick > OSE_MAX_MIDI_TICK Then
        Return 0
    End If
    If systemEvent.data1 > 127 OrElse systemEvent.data2 > 127 Then
        Return 0
    End If

    Dim As Integer expectedDataLength
    If midi_IsEditableSystemStatus( _
        CInt(systemEvent.statusByte), expectedDataLength) = 0 Then Return 0
    If systemEvent.dataLength <> expectedDataLength Then
        Return 0
    End If

    Dim As String systemPayload = ""
    If expectedDataLength > 0 Then
        systemPayload = Space(expectedDataLength)
        Mid(systemPayload, 1, 1) = Chr(systemEvent.data1)
        If expectedDataLength > 1 Then _
            Mid(systemPayload, 2, 1) = Chr(systemEvent.data2)
    End If

    With midi_StoredEvents(sourceIndex)
        .trackIndex = systemEvent.trackIndex
        .tick = systemEvent.tick
        .statusByte = systemEvent.statusByte
        .data1 = systemEvent.data1
        .data2 = systemEvent.data2
        .payload = systemPayload
    End With
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_AddSystemEvent( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal tick As ULongInt, _
    ByVal statusByte As Integer, _
    ByVal data1 As Integer, _
    ByVal data2 As Integer _
) As Integer
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return -1
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return -1
    End If
    If tick > OSE_MAX_MIDI_TICK Then
        Return -1
    End If
    If data1 < 0 OrElse data1 > 127 OrElse _
        data2 < 0 OrElse data2 > 127 Then Return -1

    Dim As Integer dataLength
    If midi_IsEditableSystemStatus(statusByte, dataLength) = 0 Then
        Return -1
    End If
    If midi_StoredEventCount >= OSE_MAX_STORED_EVENTS Then
        Return -1
    End If

    Dim As String systemPayload = ""
    If dataLength > 0 Then
        systemPayload = Space(dataLength)
        Mid(systemPayload, 1, 1) = Chr(data1)
        If dataLength > 1 Then
            Mid(systemPayload, 2, 1) = Chr(data2)
        End If
    End If

    Dim As Integer sourceIndex = midi_StoredEventCount
    If midi_AppendStoredEvent( _
        trackIndex, tick, OSE_EVENT_SYSTEM, CUByte(statusByte), _
        CUByte(data1), CUByte(data2), midi_NextTrackEventOrder(trackIndex), _
        systemPayload) = 0 Then
        Return -1
    End If
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return sourceIndex
End Function


Function midi_RemoveSystemEvent( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer _
) As Integer
    If sourceIndex < 0 OrElse sourceIndex >= midi_StoredEventCount Then
        Return 0
    End If
    If midi_StoredEvents(sourceIndex).eventKind <> OSE_EVENT_SYSTEM Then
        Return 0
    End If

    For storedIndex As Integer = sourceIndex To midi_StoredEventCount - 2
        midi_StoredEvents(storedIndex) = midi_StoredEvents(storedIndex + 1)
    Next
    midi_StoredEventCount -= 1
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_RemoveChannelEvent( _
    ByRef summary As MidiSummary, _
    ByVal sourceIndex As Integer _
) As Integer
    If sourceIndex < 0 OrElse sourceIndex >= midi_StoredEventCount Then
        Return 0
    End If
    If midi_StoredEvents(sourceIndex).eventKind <> OSE_EVENT_CHANNEL Then
        Return 0
    End If

    For storedIndex As Integer = sourceIndex To midi_StoredEventCount - 2
        midi_StoredEvents(storedIndex) = midi_StoredEvents(storedIndex + 1)
    Next
    midi_StoredEventCount -= 1
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    midi_RebuildChannelState summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_RemoveTrack( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer _
) As Integer
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return 0
    End If

    ' Stage every retained timing point before changing either model array.
    ' A required default must also fit, so rejection leaves the document intact.
    Dim As MidiSummary retainedSummary = summary
    If midi_RebuildTimingMaps(retainedSummary, trackIndex) = 0 Then
        Return 0
    End If
    summary = retainedSummary

    Dim As Integer noteWriteIndex = 0
    For noteReadIndex As Integer = 0 To midi_EditableNoteCount - 1
        If midi_EditableNotes(noteReadIndex).trackIndex = trackIndex Then
            Continue For
        End If
        If midi_EditableNotes(noteReadIndex).trackIndex > trackIndex Then
            midi_EditableNotes(noteReadIndex).trackIndex -= 1
        End If
        midi_EditableNotes(noteWriteIndex) = midi_EditableNotes(noteReadIndex)
        noteWriteIndex += 1
    Next
    midi_EditableNoteCount = noteWriteIndex

    Dim As Integer storedWriteIndex = 0
    For storedReadIndex As Integer = 0 To midi_StoredEventCount - 1
        If midi_StoredEvents(storedReadIndex).trackIndex = trackIndex Then
            Continue For
        End If
        If midi_StoredEvents(storedReadIndex).trackIndex > trackIndex Then
            midi_StoredEvents(storedReadIndex).trackIndex -= 1
        End If
        midi_StoredEvents(storedWriteIndex) = midi_StoredEvents(storedReadIndex)
        storedWriteIndex += 1
    Next
    midi_StoredEventCount = storedWriteIndex

    For summaryIndex As Integer = trackIndex To summary.trackCount - 2
        summary.tracks(summaryIndex) = summary.tracks(summaryIndex + 1)
    Next
    summary.trackCount -= 1
    summary.tracks(summary.trackCount).name = ""
    summary.tracks(summary.trackCount).eventCount = 0
    summary.tracks(summary.trackCount).noteCount = 0
    summary.tracks(summary.trackCount).endTick = 0

    summary.fileSize = 0
    If summary.trackCount <= 1 Then
        summary.formatNumber = 0
    Else
        summary.formatNumber = 1
    End If
    midi_RebuildChannelState summary
    midi_RebuildTextMetadata summary
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    Return -1
End Function

Function midi_GetEditableNoteCount() As Integer
    Return midi_EditableNoteCount
End Function


Function midi_GetEditableNote( _
    ByVal noteIndex As Integer, _
    ByRef editableNote As MidiEditableNote _
) As Integer
    If noteIndex < 0 OrElse noteIndex >= midi_EditableNoteCount Then
        Return 0
    End If
    editableNote = midi_EditableNotes(noteIndex)
    Return -1
End Function


Private Function midi_EditableNoteIsValid( _
    ByRef summary As MidiSummary, _
    ByRef editableNote As MidiEditableNote _
) As Integer
    If editableNote.trackIndex < 0 OrElse _
        editableNote.trackIndex >= summary.trackCount Then Return 0
    If editableNote.keyNumber > 127 OrElse editableNote.channel > 15 OrElse _
        editableNote.velocity = 0 Then Return 0
    If editableNote.startTick > OSE_MAX_MIDI_TICK Then
        Return 0
    End If
    If editableNote.durationTicks = 0 Then
        editableNote.durationTicks = 1
    End If
    If editableNote.durationTicks > OSE_MAX_MIDI_TICK - _
        editableNote.startTick Then Return 0
    Return -1
End Function


Function midi_SetEditableNote( _
    ByRef summary As MidiSummary, _
    ByVal noteIndex As Integer, _
    ByRef editableNote As MidiEditableNote _
) As Integer
    If noteIndex < 0 OrElse noteIndex >= midi_EditableNoteCount Then
        Return 0
    End If
    If midi_EditableNoteIsValid(summary, editableNote) = 0 Then
        Return 0
    End If
    editableNote.startEventOrder = midi_EditableNotes(noteIndex).startEventOrder
    editableNote.endEventOrder = midi_EditableNotes(noteIndex).endEventOrder
    midi_EditableNotes(noteIndex) = editableNote
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_SetEditableNotes( _
    ByRef summary As MidiSummary, _
    ByVal noteIndices As Integer Ptr, _
    ByVal editableNotes As MidiEditableNote Ptr, _
    ByVal noteCount As Integer _
) As Integer
    If noteIndices = 0 OrElse editableNotes = 0 OrElse noteCount <= 0 OrElse _
        noteCount > OSE_MAX_EDITABLE_NOTES Then Return 0

    Dim As Integer previousIndex = -1
    For notePosition As Integer = 0 To noteCount - 1
        Dim As Integer noteIndex = noteIndices[notePosition]
        If noteIndex <= previousIndex OrElse _
            noteIndex >= midi_EditableNoteCount Then Return 0
        Dim As MidiEditableNote candidateNote = editableNotes[notePosition]
        If midi_EditableNoteIsValid(summary, candidateNote) = 0 Then
            Return 0
        End If
        previousIndex = noteIndex
    Next

    For notePosition As Integer = 0 To noteCount - 1
        Dim As MidiEditableNote candidateNote = editableNotes[notePosition]
        If candidateNote.durationTicks = 0 Then
            candidateNote.durationTicks = 1
        End If
        candidateNote.startEventOrder = _
            midi_EditableNotes(noteIndices[notePosition]).startEventOrder
        candidateNote.endEventOrder = _
            midi_EditableNotes(noteIndices[notePosition]).endEventOrder
        midi_EditableNotes(noteIndices[notePosition]) = candidateNote
    Next
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_AddEditableNote( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal startTick As ULongInt, _
    ByVal durationTicks As ULongInt, _
    ByVal keyNumber As Integer, _
    ByVal midiChannel As Integer, _
    ByVal noteVelocity As Integer _
) As Integer
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return -1
    End If
    If keyNumber < 0 OrElse keyNumber > 127 Then
        Return -1
    End If
    If midiChannel < 0 OrElse midiChannel > 15 Then
        Return -1
    End If
    If noteVelocity < 1 OrElse noteVelocity > 127 Then
        Return -1
    End If
    If startTick > OSE_MAX_MIDI_TICK Then
        Return -1
    End If
    If durationTicks = 0 Then
        durationTicks = 1
    End If
    If durationTicks > OSE_MAX_MIDI_TICK - startTick Then
        Return -1
    End If

    Dim As Integer noteIndex = midi_AppendEditableNote( _
        trackIndex, startTick, durationTicks, CUByte(keyNumber), _
        CUByte(midiChannel), CUByte(noteVelocity))
    If noteIndex < 0 Then
        Return -1
    End If

    Dim As ULongInt noteEnd = startTick + durationTicks
    If noteEnd > summary.durationTicks Then
        summary.durationTicks = noteEnd
    End If
    midi_RecalculateDocumentCounts summary
    summary.fileSize = 0

    Return noteIndex
End Function


Function midi_AddEditableNotes( _
    ByRef summary As MidiSummary, _
    ByVal editableNotes As MidiEditableNote Ptr, _
    ByVal noteCount As Integer _
) As Integer
    If editableNotes = 0 OrElse noteCount <= 0 OrElse _
        noteCount > OSE_MAX_EDITABLE_NOTES OrElse _
        midi_EditableNoteCount > OSE_MAX_EDITABLE_NOTES - noteCount Then Return -1

    For notePosition As Integer = 0 To noteCount - 1
        Dim As MidiEditableNote candidateNote = editableNotes[notePosition]
        If midi_EditableNoteIsValid(summary, candidateNote) = 0 Then
            Return -1
        End If
    Next
    If midi_ReserveEditableNotes(midi_EditableNoteCount + noteCount) = 0 Then _
        Return -1

    Dim As Integer firstAddedIndex = midi_EditableNoteCount
    For notePosition As Integer = 0 To noteCount - 1
        Dim As MidiEditableNote candidateNote = editableNotes[notePosition]
        If candidateNote.durationTicks = 0 Then
            candidateNote.durationTicks = 1
        End If
        ' Copies create new events; their source ordinals belong to the old notes.
        candidateNote.startEventOrder = 0
        candidateNote.endEventOrder = 0
        midi_EditableNotes(midi_EditableNoteCount) = candidateNote
        midi_EditableNoteCount += 1
    Next
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return firstAddedIndex
End Function


Function midi_RemoveEditableNote( _
    ByRef summary As MidiSummary, _
    ByVal noteIndex As Integer _
) As Integer
    If noteIndex < 0 OrElse noteIndex >= midi_EditableNoteCount Then
        Return 0
    End If

    For index As Integer = noteIndex To midi_EditableNoteCount - 2
        midi_EditableNotes(index) = midi_EditableNotes(index + 1)
    Next
    midi_EditableNoteCount -= 1
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_RemoveEditableNotes( _
    ByRef summary As MidiSummary, _
    ByVal noteIndices As Integer Ptr, _
    ByVal noteCount As Integer _
) As Integer
    If noteIndices = 0 OrElse noteCount <= 0 OrElse _
        noteCount > midi_EditableNoteCount Then Return 0

    Dim As Integer previousIndex = -1
    For notePosition As Integer = 0 To noteCount - 1
        Dim As Integer noteIndex = noteIndices[notePosition]
        If noteIndex <= previousIndex OrElse _
            noteIndex >= midi_EditableNoteCount Then Return 0
        previousIndex = noteIndex
    Next

    Dim As Integer removePosition = 0
    Dim As Integer writeIndex = 0
    For readIndex As Integer = 0 To midi_EditableNoteCount - 1
        If removePosition < noteCount AndAlso _
            readIndex = noteIndices[removePosition] Then
            removePosition += 1
        Else
            If writeIndex <> readIndex Then _
                midi_EditableNotes(writeIndex) = midi_EditableNotes(readIndex)
            writeIndex += 1
        End If
    Next
    midi_EditableNoteCount = writeIndex
    midi_RecalculateDocumentCounts summary
    midi_RecalculateDuration summary
    summary.fileSize = 0
    Return -1
End Function


Function midi_QuantizeTrack( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByVal gridTicks As ULongInt _
) As Integer
    ' Quantization changes note starts only. Keeping each duration unchanged
    ' makes the operation predictable for legato lines and avoids rewriting
    ' note-off intent as a side effect of a grid edit.
    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return -1
    End If
    If gridTicks = 0 OrElse gridTicks > OSE_MAX_MIDI_TICK Then
        Return -1
    End If

    ' Validate the existing note invariants before changing any note. This
    ' prevents a partial quantization if a caller supplied a damaged model.
    For noteIndex As Integer = 0 To midi_EditableNoteCount - 1
        With midi_EditableNotes(noteIndex)
            If .trackIndex <> trackIndex Then
                Continue For
            End If
            If .startTick > OSE_MAX_MIDI_TICK OrElse _
                .durationTicks > OSE_MAX_MIDI_TICK - .startTick Then Return -1
        End With
    Next

    Dim As Integer changedCount = 0
    For noteIndex As Integer = 0 To midi_EditableNoteCount - 1
        With midi_EditableNotes(noteIndex)
            If .trackIndex <> trackIndex Then
                Continue For
            End If

            Dim As ULongInt lowerGridTick = _
                (.startTick \ gridTicks) * gridTicks
            Dim As ULongInt tickRemainder = .startTick Mod gridTicks
            Dim As ULongInt quantizedTick = lowerGridTick
            Dim As ULongInt roundThreshold = (gridTicks + 1) \ 2
            If tickRemainder >= roundThreshold Then
                If lowerGridTick <= OSE_MAX_MIDI_TICK - gridTicks Then
                    quantizedTick = lowerGridTick + gridTicks
                Else
                    quantizedTick = OSE_MAX_MIDI_TICK
                End If
            End If

            ' A note cannot end beyond the representable MIDI tick range. If
            ' rounding would move its start too far right, clamp only the
            ' start and preserve its duration.
            Dim As ULongInt latestStart = _
                OSE_MAX_MIDI_TICK - .durationTicks
            If quantizedTick > latestStart Then
                quantizedTick = latestStart
            End If

            If quantizedTick <> .startTick Then
                .startTick = quantizedTick
                changedCount += 1
            End If
        End With
    Next

    If changedCount > 0 Then
        midi_RecalculateDocumentCounts summary
        midi_RecalculateDuration summary
        summary.fileSize = 0
    End If
    Return changedCount
End Function


' -------------------------------------------------------------------------
' Standard MIDI File writer
' -------------------------------------------------------------------------

Type MidiSaveEvent
    As ULongInt tick
    As UByte eventKind
    As UByte statusByte
    As UByte data1
    As UByte data2
    As Integer order
    As Integer insertionOrder
    As String payload
End Type


Private Sub midi_AppendByte(ByRef buffer As String, ByVal byteValue As Integer)
    ' fblint: disable-next-line FBL503 REASON: binary output is assembled in bounded track buffers.
    buffer += Chr(byteValue And &HFF)
End Sub


Private Sub midi_AppendStringBytes(ByRef buffer As String, ByRef sourceData As String)
    For index As Integer = 1 To Len(sourceData)
        midi_AppendByte buffer, Asc(Mid(sourceData, index, 1))
    Next
End Sub


Private Sub midi_AppendBe16(ByRef buffer As String, ByVal value As Integer)
    midi_AppendByte buffer, (value Shr 8) And &HFF
    midi_AppendByte buffer, value And &HFF
End Sub


Private Sub midi_AppendBe32(ByRef buffer As String, ByVal value As ULongInt)
    midi_AppendByte buffer, CInt((value Shr 24) And &HFF)
    midi_AppendByte buffer, CInt((value Shr 16) And &HFF)
    midi_AppendByte buffer, CInt((value Shr 8) And &HFF)
    midi_AppendByte buffer, CInt(value And &HFF)
End Sub


Private Sub midi_AppendVariableLength( _
    ByRef buffer As String, _
    ByVal sourceValue As ULongInt _
)
    Const MIDI_MAX_VARIABLE_VALUE As ULongInt = 268435455
    Dim As ULongInt value = sourceValue
    If value > MIDI_MAX_VARIABLE_VALUE Then
        value = MIDI_MAX_VARIABLE_VALUE
    End If

    Dim As UByte encoded(0 To OSE_MAX_VLQ_BYTES - 1)
    Dim As Integer byteCount = 1
    encoded(0) = CUByte(value And &H7F)
    While value > &H7F AndAlso byteCount < OSE_MAX_VLQ_BYTES
        value Shr= 7
        encoded(byteCount) = CUByte((value And &H7F) Or &H80)
        byteCount += 1
    Wend

    For index As Integer = byteCount - 1 To 0 Step -1
        midi_AppendByte buffer, encoded(index)
    Next
End Sub


Private Sub midi_AppendSaveEvent( _
    events() As MidiSaveEvent, _
    ByRef eventCount As Integer, _
    ByRef eventCapacity As Integer, _
    ByVal tick As ULongInt, _
    ByVal statusByte As UByte, _
    ByVal data1 As UByte, _
    ByVal data2 As UByte, _
    ByVal order As Integer _
)
    Dim As Integer newCapacity = 512

    If eventCount >= eventCapacity Then
        If eventCapacity >= 256 Then
            newCapacity = eventCapacity * 2
        End If
        Redim Preserve events(0 To newCapacity - 1)
        eventCapacity = newCapacity
    End If

    With events(eventCount)
        .tick = tick
        .eventKind = OSE_EVENT_CHANNEL
        .statusByte = statusByte
        .data1 = data1
        .data2 = data2
        .order = order
        .insertionOrder = eventCount
        .payload = ""
    End With
    eventCount += 1
End Sub


Private Sub midi_AppendSpecialSaveEvent( _
    events() As MidiSaveEvent, _
    ByRef eventCount As Integer, _
    ByRef eventCapacity As Integer, _
    ByVal tick As ULongInt, _
    ByVal eventKind As UByte, _
    ByVal statusByte As UByte, _
    ByVal data1 As UByte, _
    ByVal data2 As UByte, _
    ByRef payload As String, _
    ByVal order As Integer _
)
    Dim As Integer newCapacity = 512

    If eventCount >= eventCapacity Then
        If eventCapacity >= 256 Then
            newCapacity = eventCapacity * 2
        End If
        Redim Preserve events(0 To newCapacity - 1)
        eventCapacity = newCapacity
    End If

    With events(eventCount)
        .tick = tick
        .eventKind = eventKind
        .statusByte = statusByte
        .data1 = data1
        .data2 = data2
        .order = order
        .insertionOrder = eventCount
        .payload = payload
    End With
    eventCount += 1
End Sub


Private Function midi_CompareSaveEvents( _
    ByRef leftEvent As MidiSaveEvent, _
    ByRef rightEvent As MidiSaveEvent _
) As Integer
    If leftEvent.tick < rightEvent.tick Then
        Return -1
    End If
    If leftEvent.tick > rightEvent.tick Then
        Return 1
    End If
    If leftEvent.order < rightEvent.order Then
        Return -1
    End If
    If leftEvent.order > rightEvent.order Then
        Return 1
    End If
    If leftEvent.insertionOrder < rightEvent.insertionOrder Then
        Return -1
    End If
    If leftEvent.insertionOrder > rightEvent.insertionOrder Then
        Return 1
    End If
    Return 0
End Function


Private Sub midi_SortSaveEvents( _
    events() As MidiSaveEvent, _
    ByVal lowIndex As Integer, _
    ByVal highIndex As Integer _
)
    If lowIndex >= highIndex Then
        Exit Sub
    End If

    Dim As Integer leftIndex = lowIndex
    Dim As Integer rightIndex = highIndex
    Dim As MidiSaveEvent pivot = events(lowIndex + (highIndex - lowIndex) \ 2)

    Do
        While leftIndex <= highIndex AndAlso _
            midi_CompareSaveEvents(events(leftIndex), pivot) < 0
            leftIndex += 1
        Wend
        While rightIndex >= lowIndex AndAlso _
            midi_CompareSaveEvents(events(rightIndex), pivot) > 0
            rightIndex -= 1
        Wend
        If leftIndex <= rightIndex Then
            Swap events(leftIndex), events(rightIndex)
            leftIndex += 1
            rightIndex -= 1
        End If
    Loop While leftIndex <= rightIndex

    If lowIndex < rightIndex Then
        midi_SortSaveEvents events(), lowIndex, rightIndex
    End If
    If leftIndex < highIndex Then
        midi_SortSaveEvents events(), leftIndex, highIndex
    End If
End Sub


Private Function midi_BuildTrackData( _
    ByRef summary As MidiSummary, _
    ByVal trackIndex As Integer, _
    ByRef outputData As String _
) As Integer
    Dim As MidiSaveEvent events()
    Dim As Integer eventCount = 0
    Dim As Integer eventCapacity = 0

    If trackIndex < 0 OrElse trackIndex >= summary.trackCount Then
        Return 0
    End If

    Dim As Integer generatedOrder = 0
    For storedIndex As Integer = 0 To midi_StoredEventCount - 1
        With midi_StoredEvents(storedIndex)
            If .trackIndex = trackIndex Then
                midi_AppendSpecialSaveEvent events(), eventCount, eventCapacity, _
                    .tick, .eventKind, .statusByte, .data1, .data2, _
                    .payload, .order
                If .order >= generatedOrder Then
                    generatedOrder = .order + 1
                End If
            End If
        End With
    Next

    For noteIndex As Integer = 0 To midi_EditableNoteCount - 1
        With midi_EditableNotes(noteIndex)
            If .trackIndex <> trackIndex Then
                Continue For
            End If
            If .startEventOrder > generatedOrder Then _
                generatedOrder = .startEventOrder
            If .endEventOrder > generatedOrder Then _
                generatedOrder = .endEventOrder
        End With
    Next

    For noteIndex As Integer = 0 To midi_EditableNoteCount - 1
        With midi_EditableNotes(noteIndex)
            If .trackIndex = trackIndex Then
                Dim As ULongInt noteEnd = .startTick + .durationTicks
                ' Imported endpoints keep their order among every event kind.
                ' New notes follow same-tick setup events, with generated offs
                ' before generated ons and equal endpoints in insertion order.
                Dim As Integer startOrder = generatedOrder + 1
                Dim As Integer endOrder = generatedOrder
                If .startEventOrder > 0 Then
                    startOrder = .startEventOrder - 1
                End If
                If .endEventOrder > 0 Then
                    endOrder = .endEventOrder - 1
                End If
                midi_AppendSaveEvent events(), eventCount, eventCapacity, _
                    .startTick, CUByte(&H90 Or .channel), .keyNumber, .velocity, startOrder
                midi_AppendSaveEvent events(), eventCount, eventCapacity, _
                    noteEnd, CUByte(&H80 Or .channel), .keyNumber, 0, endOrder
            End If
        End With
    Next

    If eventCount > 1 Then
        midi_SortSaveEvents events(), 0, eventCount - 1
    End If
    outputData = ""

    Dim As ULongInt previousTick = 0
    For eventIndex As Integer = 0 To eventCount - 1
        If events(eventIndex).tick < previousTick Then
            Return 0
        End If
        midi_AppendVariableLength outputData, events(eventIndex).tick - previousTick
        Select Case events(eventIndex).eventKind
        Case OSE_EVENT_CHANNEL
            midi_AppendByte outputData, events(eventIndex).statusByte
            midi_AppendByte outputData, events(eventIndex).data1
            If (events(eventIndex).statusByte And &HF0) <> &HC0 AndAlso _
                (events(eventIndex).statusByte And &HF0) <> &HD0 Then
                midi_AppendByte outputData, events(eventIndex).data2
            End If
        Case OSE_EVENT_META
            midi_AppendByte outputData, &HFF
            midi_AppendByte outputData, events(eventIndex).data1
            midi_AppendVariableLength outputData, _
                CULngInt(Len(events(eventIndex).payload))
            midi_AppendStringBytes outputData, events(eventIndex).payload
        Case OSE_EVENT_SYSEX
            midi_AppendByte outputData, events(eventIndex).statusByte
            midi_AppendVariableLength outputData, _
                CULngInt(Len(events(eventIndex).payload))
            midi_AppendStringBytes outputData, events(eventIndex).payload
        Case OSE_EVENT_SYSTEM
            midi_AppendByte outputData, events(eventIndex).statusByte
            midi_AppendStringBytes outputData, events(eventIndex).payload
        Case Else
            Return 0
        End Select
        previousTick = events(eventIndex).tick
    Next

    Dim As ULongInt endTick = summary.tracks(trackIndex).endTick
    If endTick < previousTick Then
        endTick = previousTick
    End If
    midi_AppendVariableLength outputData, endTick - previousTick
    midi_AppendByte outputData, &HFF
    midi_AppendByte outputData, &H2F
    midi_AppendByte outputData, 0
    Return -1
End Function


Function midi_SerializeDocument( _
    ByRef summary As MidiSummary, _
    ByRef outputData As String _
) As Integer
    outputData = ""
    If summary.trackCount <= 0 OrElse _
        summary.trackCount > OSE_MAX_MIDI_TRACKS Then Return 0

    outputData = "MThd"
    midi_AppendBe32 outputData, 6
    midi_AppendBe16 outputData, summary.formatNumber
    midi_AppendBe16 outputData, summary.trackCount
    midi_AppendBe16 outputData, summary.division

    For trackIndex As Integer = 0 To summary.trackCount - 1
        Dim As String trackData
        If midi_BuildTrackData(summary, trackIndex, trackData) = 0 Then
            Return 0
        End If
        midi_AppendByte outputData, Asc("M")
        midi_AppendByte outputData, Asc("T")
        midi_AppendByte outputData, Asc("r")
        midi_AppendByte outputData, Asc("k")
        midi_AppendBe32 outputData, CULngInt(Len(trackData))
        ' fblint: disable-next-line FBL503 REASON: one bounded track is appended to the output image.
        outputData += trackData
    Next

    If CLngInt(Len(outputData)) > OSE_MAX_MIDI_FILE_BYTES Then
        Return 0
    End If

    Return -1
End Function


Function midi_SaveDocument( _
    ByRef summary As MidiSummary, _
    ByVal filename As String _
) As Integer
    If filename = "" Then
        Return 0
    End If
    Dim As String outputData
    If midi_SerializeDocument(summary, outputData) = 0 Then
        Return 0
    End If

    Return atomicFile_WriteVerified(filename, outputData)
End Function

/' end of midi_model.bas '/
