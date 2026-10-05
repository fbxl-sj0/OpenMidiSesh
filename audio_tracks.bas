/'
    Project: OpenSesh
    ---------------------------

    File: audio_tracks.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements audio_tracks.bi; declarations there define the shared interface.

    Purpose:

        Own the bounded audio-clip timeline and its PCM WAV/project-file
        validation without coupling the audio layer to the MIDI parser or UI.

    Responsibilities:

        - inspect RIFF/WAVE chunks and calculate clip durations
        - add, edit, enumerate, and remove user-referenced audio clips
        - keep bounded multi-step audio undo and redo history
        - stage audio undo snapshots until an edit succeeds
        - save and load the text-based OpenSesh project container

    Ownership:

        This module owns the clip records. It never owns the referenced WAV
        files; filenames remain external paths and are revalidated when a clip
        is added or edited.

    This file intentionally does NOT contain:

        - sfxlib playback or audio-device initialization
        - MIDI event parsing or MIDI timeline conversion
        - omaGui widget creation
'/

#lang "fb"

#include once "audio_tracks.bi"
#include once "atomic_file_internal.bi"

Dim Shared audio_Clips(0 To OSE_AUDIO_MAX_CLIPS - 1) As OseAudioClip
Dim Shared audio_ClipCount As Integer

Type AudioHistorySnapshot
    clips(0 To OSE_AUDIO_MAX_CLIPS - 1) As OseAudioClip
    As Integer clipCount
    As Integer valid
End Type

Const OSE_AUDIO_HISTORY_STORAGE As Integer = OSE_AUDIO_HISTORY_DEPTH + 1
Dim Shared audio_HistoryUndo(0 To OSE_AUDIO_HISTORY_STORAGE - 1) As _
    AudioHistorySnapshot
Dim Shared audio_HistoryUndoStart As Integer
Dim Shared audio_HistoryUndoCountValue As Integer
Dim Shared audio_HistoryRedo(0 To OSE_AUDIO_HISTORY_STORAGE - 1) As _
    AudioHistorySnapshot
Dim Shared audio_HistoryRedoStart As Integer
Dim Shared audio_HistoryRedoCountValue As Integer
Dim Shared audio_HistoryPreparedIndex As Integer = -1

Const AUDIO_WAV_PCM_FORMAT As Integer = 1
Const AUDIO_WAV_FORMAT_BYTES As Integer = 16
Const AUDIO_WAV_BYTE_RATE_OFFSET As Integer = 8
Const AUDIO_WAV_BLOCK_ALIGN_OFFSET As Integer = 12
Const AUDIO_WAV_BITS_PER_SAMPLE_OFFSET As Integer = 14

' -------------------------------------------------------------------------
' Bounded binary and text helpers
' -------------------------------------------------------------------------

Private Function audio_HasBytes( _
    ByVal offset As Integer, _
    ByVal count As Integer, _
    ByVal limit As Integer _
) As Integer
    If offset < 0 OrElse count < 0 OrElse offset > limit Then
        Return 0
    End If
    If count > limit - offset Then
        Return 0
    End If
    Return -1
End Function


Private Function audio_ReadLe16( _
    ByRef binaryData As String, _
    ByVal offset As Integer _
) As ULong
    Return CULng(Asc(Mid(binaryData, offset + 1, 1))) Or _
        (CULng(Asc(Mid(binaryData, offset + 2, 1))) Shl 8)
End Function


Private Function audio_ReadLe32( _
    ByRef binaryData As String, _
    ByVal offset As Integer _
) As ULong
    Return CULng(Asc(Mid(binaryData, offset + 1, 1))) Or _
        (CULng(Asc(Mid(binaryData, offset + 2, 1))) Shl 8) Or _
        (CULng(Asc(Mid(binaryData, offset + 3, 1))) Shl 16) Or _
        (CULng(Asc(Mid(binaryData, offset + 4, 1))) Shl 24)
End Function


Private Function audio_Matches( _
    ByRef binaryData As String, _
    ByVal offset As Integer, _
    ByVal tagText As String, _
    ByVal limit As Integer _
) As Integer
    If Len(tagText) <> 4 OrElse audio_HasBytes(offset, 4, limit) = 0 Then _
        Return 0
    For index As Integer = 0 To 3
        If Asc(Mid(binaryData, offset + index + 1, 1)) <> _
            Asc(Mid(tagText, index + 1, 1)) Then Return 0
    Next
    Return -1
End Function


Private Function audio_PathIsSafe(ByVal filename As String) As Integer
    If Len(filename) <= 0 OrElse Len(filename) > OSE_AUDIO_MAX_PATH_BYTES Then _
        Return 0
    For index As Integer = 1 To Len(filename)
        Dim As Integer characterCode = Asc(Mid(filename, index, 1))
        If characterCode = 0 OrElse characterCode = 10 OrElse _
            characterCode = 13 Then Return 0
    Next
    Return -1
End Function


Private Function audio_ParseUnsigned( _
    ByVal textValue As String, _
    ByRef value As ULongInt, _
    ByVal maximumValue As ULongInt _
) As Integer
    Dim As String cleanText = Trim(textValue)
    If cleanText = "" Then
        Return 0
    End If
    value = 0
    For index As Integer = 1 To Len(cleanText)
        Dim As Integer characterCode = Asc(Mid(cleanText, index, 1))
        If characterCode < Asc("0") OrElse characterCode > Asc("9") Then _
            Return 0
        Dim As ULongInt digitValue = CULngInt(characterCode - Asc("0"))
        If value > (maximumValue - digitValue) \ 10 Then
            Return 0
        End If
        value = value * 10 + digitValue
    Next
    Return -1
End Function


Private Function audio_NextUnsigned( _
    ByRef sourceText As String, _
    ByRef cursor As Integer, _
    ByRef value As ULongInt, _
    ByVal maximumValue As ULongInt _
) As Integer
    While cursor <= Len(sourceText) AndAlso _
        Mid(sourceText, cursor, 1) = " "
        cursor += 1
    Wend
    Dim As Integer firstDigit = cursor
    While cursor <= Len(sourceText)
        Dim As Integer characterCode = Asc(Mid(sourceText, cursor, 1))
        If characterCode < Asc("0") OrElse characterCode > Asc("9") Then
            Exit While
        End If
        cursor += 1
    Wend
    If cursor = firstDigit Then
        Return 0
    End If
    Return audio_ParseUnsigned(Mid(sourceText, firstDigit, cursor - firstDigit), _
        value, maximumValue)
End Function


Private Function audio_ProjectLine( _
    ByRef lineText As String, _
    ByVal tagText As String, _
    ByRef valueText As String _
) As Integer
    If Len(lineText) < Len(tagText) + 1 OrElse _
        Left(lineText, Len(tagText) + 1) <> tagText + " " Then Return 0
    valueText = Mid(lineText, Len(tagText) + 2)
    Return -1
End Function


Private Sub audio_AppendProjectLine( _
    ByRef projectData As String, _
    ByVal lineText As String _
)
    projectData += lineText + Chr(13) + Chr(10)
End Sub


Private Sub audio_ClearClipStorage(clips() As OseAudioClip)
    For clipIndex As Integer = 0 To OSE_AUDIO_MAX_CLIPS - 1
        clips(clipIndex).filename = ""
        clips(clipIndex).startTick = 0
        clips(clipIndex).durationMilliseconds = 0
        clips(clipIndex).gainPermille = 0
        Dim As OseWaveInfo emptyInfo
        clips(clipIndex).waveInfo = emptyInfo
    Next
End Sub


Private Sub audio_CopyClips( _
    sourceClips() As OseAudioClip, _
    ByVal sourceCount As Integer, _
    destinationClips() As OseAudioClip, _
    ByRef destinationCount As Integer _
)
    destinationCount = sourceCount
    For clipIndex As Integer = 0 To sourceCount - 1
        destinationClips(clipIndex) = sourceClips(clipIndex)
    Next
End Sub


Private Function audio_RestoreClips( _
    sourceClips() As OseAudioClip, _
    ByVal sourceCount As Integer _
) As Integer
    If sourceCount < 0 OrElse sourceCount > OSE_AUDIO_MAX_CLIPS Then
        Return 0
    End If
    audio_ClearClipStorage(audio_Clips())
    For clipIndex As Integer = 0 To sourceCount - 1
        audio_Clips(clipIndex) = sourceClips(clipIndex)
    Next
    audio_ClipCount = sourceCount
    Return -1
End Function


' -------------------------------------------------------------------------
' WAV inspection and clip storage
' -------------------------------------------------------------------------

Function audio_InspectWave( _
    ByVal filename As String, _
    ByRef waveInfo As OseWaveInfo _
) As Integer
    Dim As OseWaveInfo emptyInfo
    waveInfo = emptyInfo
    If audio_PathIsSafe(filename) = 0 Then
        Return 0
    End If

    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then
        Return 0
    End If
    Dim As LongInt fileSize = LOF(fileNumber)
    If fileSize < 44 OrElse fileSize > OSE_AUDIO_MAX_WAV_BYTES Then
        Close #fileNumber
        Return 0
    End If

    Dim As String binaryData = Space(CInt(fileSize))
    If binaryFile_ReadExact(fileNumber, 1, StrPtr(binaryData), _
        Len(binaryData)) = 0 Then
        Close #fileNumber
        Return 0
    End If
    Close #fileNumber

    Dim As Integer dataLimit = Len(binaryData)
    If audio_Matches(binaryData, 0, "RIFF", dataLimit) = 0 OrElse _
        audio_Matches(binaryData, 8, "WAVE", dataLimit) = 0 Then Return 0
    /'
        RIFF's container length covers every byte after the size field. An
        exact comparison prevents hidden trailing bytes and prevents a
        truncated declared container from being parsed as a complete WAV.
    '/
    If audio_ReadLe32(binaryData, 4) <> CULng(dataLimit - 8) Then
        Return 0
    End If

    Dim As Integer offset = 12
    Dim As Integer foundFormat = 0
    Dim As Integer foundData = 0
    Dim As ULong waveByteRate
    Dim As Integer waveBlockAlign
    While offset <= dataLimit - 8
        Dim As ULong chunkLength = audio_ReadLe32(binaryData, offset + 4)
        If chunkLength > CULng(dataLimit - (offset + 8)) Then
            Return 0
        End If
        Dim As Integer payloadOffset = offset + 8
        Dim As Integer payloadLength = CInt(chunkLength)

        If audio_Matches(binaryData, offset, "fmt ", dataLimit) <> 0 Then
            If payloadLength < AUDIO_WAV_FORMAT_BYTES OrElse foundFormat <> 0 Then
                Return 0
            End If
            waveInfo.audioFormat = CInt(audio_ReadLe16(binaryData, payloadOffset))
            waveInfo.channelCount = CInt(audio_ReadLe16(binaryData, payloadOffset + 2))
            waveInfo.sampleRate = CInt(audio_ReadLe32(binaryData, payloadOffset + 4))
            waveByteRate = audio_ReadLe32(binaryData, _
                payloadOffset + AUDIO_WAV_BYTE_RATE_OFFSET)
            waveBlockAlign = CInt(audio_ReadLe16(binaryData, _
                payloadOffset + AUDIO_WAV_BLOCK_ALIGN_OFFSET))
            waveInfo.bitsPerSample = CInt(audio_ReadLe16(binaryData, _
                payloadOffset + AUDIO_WAV_BITS_PER_SAMPLE_OFFSET))
            foundFormat = -1
        ElseIf audio_Matches(binaryData, offset, "data", dataLimit) <> 0 Then
            If foundData = 0 Then
                waveInfo.dataBytes = chunkLength
                foundData = -1
            End If
        End If

        Dim As ULongInt paddedLength = chunkLength + (chunkLength Mod 2)
        If paddedLength > CULngInt(dataLimit - payloadOffset) Then
            Return 0
        End If
        offset = payloadOffset + CInt(paddedLength)
    Wend
    If offset <> dataLimit Then
        Return 0
    End If

    If foundFormat = 0 OrElse foundData = 0 OrElse _
        waveInfo.audioFormat <> AUDIO_WAV_PCM_FORMAT OrElse waveInfo.channelCount < 1 OrElse _
        waveInfo.channelCount > 8 OrElse waveInfo.sampleRate < 1 OrElse _
        waveInfo.sampleRate > 192000 Then Return 0
    Select Case waveInfo.bitsPerSample
        Case 8, 16, 24, 32
        Case Else
            Return 0
    End Select

    Dim As ULongInt bytesPerFrame = CULngInt(waveInfo.channelCount) * _
        CULngInt(waveInfo.bitsPerSample \ 8)
    Dim As ULongInt expectedByteRate = CULngInt(waveInfo.sampleRate) * _
        bytesPerFrame
    If bytesPerFrame = 0 OrElse _
        CULngInt(waveBlockAlign) <> bytesPerFrame OrElse _
        CULngInt(waveByteRate) <> expectedByteRate OrElse _
        waveInfo.dataBytes < bytesPerFrame OrElse _
        (waveInfo.dataBytes Mod bytesPerFrame) <> 0 Then Return 0
    waveInfo.sampleFrames = waveInfo.dataBytes \ bytesPerFrame
    If waveInfo.sampleFrames = 0 Then
        Return 0
    End If
    waveInfo.durationMilliseconds = (waveInfo.sampleFrames * 1000) \ _
        CULngInt(waveInfo.sampleRate)
    If waveInfo.durationMilliseconds = 0 OrElse _
        waveInfo.durationMilliseconds > OSE_AUDIO_MAX_DURATION_MILLISECONDS Then _
        Return 0
    Return -1
End Function


Private Sub audio_HistorySnapshotClear( _
    ByRef historySnapshot As AudioHistorySnapshot _
)
    audio_ClearClipStorage historySnapshot.clips()
    historySnapshot.clipCount = 0
    historySnapshot.valid = 0
End Sub


Private Function audio_HistorySnapshotCapture( _
    ByRef historySnapshot As AudioHistorySnapshot _
) As Integer
    If audio_ClipCount < 0 OrElse audio_ClipCount > OSE_AUDIO_MAX_CLIPS Then _
        Return 0
    audio_HistorySnapshotClear historySnapshot
    audio_CopyClips audio_Clips(), audio_ClipCount, _
        historySnapshot.clips(), historySnapshot.clipCount
    historySnapshot.valid = -1
    Return -1
End Function


Private Sub audio_HistoryStackClear( _
    historyStack() As AudioHistorySnapshot, _
    ByRef stackStart As Integer, _
    ByRef stackCount As Integer _
)
    For historyIndex As Integer = 0 To OSE_AUDIO_HISTORY_STORAGE - 1
        audio_HistorySnapshotClear historyStack(historyIndex)
    Next
    stackStart = 0
    stackCount = 0
End Sub


Private Function audio_HistoryStackNewestIndex( _
    ByVal stackStart As Integer, _
    ByVal stackCount As Integer _
) As Integer
    If stackStart < 0 OrElse stackStart >= OSE_AUDIO_HISTORY_STORAGE OrElse _
        stackCount <= 0 OrElse stackCount > OSE_AUDIO_HISTORY_DEPTH Then Return -1
    Return (stackStart + stackCount - 1) Mod OSE_AUDIO_HISTORY_STORAGE
End Function


Private Function audio_HistoryStackPushCurrent( _
    historyStack() As AudioHistorySnapshot, _
    ByRef stackStart As Integer, _
    ByRef stackCount As Integer _
) As Integer
    If stackStart < 0 OrElse stackStart >= OSE_AUDIO_HISTORY_STORAGE OrElse _
        stackCount < 0 OrElse stackCount > OSE_AUDIO_HISTORY_DEPTH Then Return 0

    Dim As Integer targetIndex = (stackStart + stackCount) Mod _
        OSE_AUDIO_HISTORY_STORAGE
    If audio_HistorySnapshotCapture(historyStack(targetIndex)) = 0 Then
        Return 0
    End If

    If stackCount = OSE_AUDIO_HISTORY_DEPTH Then
        audio_HistorySnapshotClear historyStack(stackStart)
        stackStart = (stackStart + 1) Mod OSE_AUDIO_HISTORY_STORAGE
    Else
        stackCount += 1
    End If
    Return -1
End Function


Private Sub audio_HistoryStackRemoveNewest( _
    historyStack() As AudioHistorySnapshot, _
    ByRef stackStart As Integer, _
    ByRef stackCount As Integer _
)
    Dim As Integer newestIndex = audio_HistoryStackNewestIndex( _
        stackStart, stackCount)
    If newestIndex < 0 Then
        Exit Sub
    End If
    audio_HistorySnapshotClear historyStack(newestIndex)
    stackCount -= 1
    If stackCount = 0 Then
        stackStart = 0
    End If
End Sub


Private Sub audio_HistoryStackRemoveOldest( _
    historyStack() As AudioHistorySnapshot, _
    ByRef stackStart As Integer, _
    ByRef stackCount As Integer _
)
    If stackStart < 0 OrElse stackStart >= OSE_AUDIO_HISTORY_STORAGE OrElse _
        stackCount <= 0 OrElse stackCount > OSE_AUDIO_HISTORY_DEPTH Then Exit Sub
    audio_HistorySnapshotClear historyStack(stackStart)
    stackCount -= 1
    If stackCount = 0 Then
        stackStart = 0
    Else
        stackStart = (stackStart + 1) Mod OSE_AUDIO_HISTORY_STORAGE
    End If
End Sub


Sub audio_HistoryClear()
    audio_HistoryStackClear audio_HistoryUndo(), audio_HistoryUndoStart, _
        audio_HistoryUndoCountValue
    audio_HistoryStackClear audio_HistoryRedo(), audio_HistoryRedoStart, _
        audio_HistoryRedoCountValue
    audio_HistoryPreparedIndex = -1
End Sub


Function audio_HistoryUndoCount() As Integer
    Return audio_HistoryUndoCountValue
End Function


Function audio_HistoryRedoCount() As Integer
    Return audio_HistoryRedoCountValue
End Function


Sub audio_HistoryDiscardOldestUndo()
    audio_HistoryStackRemoveOldest audio_HistoryUndo(), _
        audio_HistoryUndoStart, audio_HistoryUndoCountValue
End Sub


Sub audio_HistoryRedoClear()
    audio_HistoryStackClear audio_HistoryRedo(), audio_HistoryRedoStart, _
        audio_HistoryRedoCountValue
End Sub


Function audio_CaptureHistory() As Integer
    If audio_PrepareHistory() = 0 Then
        Return 0
    End If
    If audio_CommitPreparedHistory() <> 0 Then
        Return -1
    End If
    audio_CancelPreparedHistory()
    Return 0
End Function


Function audio_PrepareHistory() As Integer
    If audio_HistoryPreparedIndex >= 0 OrElse _
        audio_HistoryUndoStart < 0 OrElse _
        audio_HistoryUndoStart >= OSE_AUDIO_HISTORY_STORAGE OrElse _
        audio_HistoryUndoCountValue < 0 OrElse _
        audio_HistoryUndoCountValue > OSE_AUDIO_HISTORY_DEPTH Then Return 0

    Dim As Integer targetIndex = (audio_HistoryUndoStart + _
        audio_HistoryUndoCountValue) Mod OSE_AUDIO_HISTORY_STORAGE
    If audio_HistorySnapshotCapture(audio_HistoryUndo(targetIndex)) = 0 Then _
        Return 0
    audio_HistoryPreparedIndex = targetIndex
    Return -1
End Function


Function audio_CommitPreparedHistory() As Integer
    If audio_HistoryPreparedIndex < 0 OrElse _
        audio_HistoryPreparedIndex >= OSE_AUDIO_HISTORY_STORAGE Then Return 0

    If audio_HistoryUndoCountValue = OSE_AUDIO_HISTORY_DEPTH Then
        audio_HistorySnapshotClear audio_HistoryUndo(audio_HistoryUndoStart)
        audio_HistoryUndoStart = (audio_HistoryUndoStart + 1) Mod _
            OSE_AUDIO_HISTORY_STORAGE
    Else
        audio_HistoryUndoCountValue += 1
    End If
    audio_HistoryPreparedIndex = -1
    audio_HistoryStackClear audio_HistoryRedo(), audio_HistoryRedoStart, _
        audio_HistoryRedoCountValue
    Return -1
End Function


Function audio_CancelPreparedHistory() As Integer
    If audio_HistoryPreparedIndex < 0 OrElse _
        audio_HistoryPreparedIndex >= OSE_AUDIO_HISTORY_STORAGE Then Return 0

    Dim As Integer preparedIndex = audio_HistoryPreparedIndex
    If audio_HistoryUndo(preparedIndex).valid = 0 OrElse _
        audio_RestoreClips(audio_HistoryUndo(preparedIndex).clips(), _
            audio_HistoryUndo(preparedIndex).clipCount) = 0 Then Return 0
    audio_HistorySnapshotClear audio_HistoryUndo(preparedIndex)
    audio_HistoryPreparedIndex = -1
    Return -1
End Function


Function audio_Undo() As Integer
    If audio_HistoryPreparedIndex >= 0 Then
        Return 0
    End If
    Dim As Integer undoIndex = audio_HistoryStackNewestIndex( _
        audio_HistoryUndoStart, audio_HistoryUndoCountValue)
    If undoIndex < 0 OrElse audio_HistoryUndo(undoIndex).valid = 0 OrElse _
        audio_HistoryUndo(undoIndex).clipCount < 0 OrElse _
        audio_HistoryUndo(undoIndex).clipCount > OSE_AUDIO_MAX_CLIPS Then Return 0
    If audio_HistoryStackPushCurrent(audio_HistoryRedo(), _
        audio_HistoryRedoStart, audio_HistoryRedoCountValue) = 0 Then Return 0
    If audio_RestoreClips(audio_HistoryUndo(undoIndex).clips(), _
        audio_HistoryUndo(undoIndex).clipCount) = 0 Then
        audio_HistoryStackRemoveNewest audio_HistoryRedo(), _
            audio_HistoryRedoStart, audio_HistoryRedoCountValue
        Return 0
    End If
    audio_HistoryStackRemoveNewest audio_HistoryUndo(), _
        audio_HistoryUndoStart, audio_HistoryUndoCountValue
    Return -1
End Function


Function audio_Redo() As Integer
    If audio_HistoryPreparedIndex >= 0 Then
        Return 0
    End If
    Dim As Integer redoIndex = audio_HistoryStackNewestIndex( _
        audio_HistoryRedoStart, audio_HistoryRedoCountValue)
    If redoIndex < 0 OrElse audio_HistoryRedo(redoIndex).valid = 0 OrElse _
        audio_HistoryRedo(redoIndex).clipCount < 0 OrElse _
        audio_HistoryRedo(redoIndex).clipCount > OSE_AUDIO_MAX_CLIPS Then Return 0
    If audio_HistoryStackPushCurrent(audio_HistoryUndo(), _
        audio_HistoryUndoStart, audio_HistoryUndoCountValue) = 0 Then Return 0
    If audio_RestoreClips(audio_HistoryRedo(redoIndex).clips(), _
        audio_HistoryRedo(redoIndex).clipCount) = 0 Then
        audio_HistoryStackRemoveNewest audio_HistoryUndo(), _
            audio_HistoryUndoStart, audio_HistoryUndoCountValue
        Return 0
    End If
    audio_HistoryStackRemoveNewest audio_HistoryRedo(), _
        audio_HistoryRedoStart, audio_HistoryRedoCountValue
    Return -1
End Function


Sub audio_Clear()
    audio_ClearClipStorage(audio_Clips())
    audio_ClipCount = 0
    audio_HistoryClear()
End Sub


Function audio_GetCount() As Integer
    Return audio_ClipCount
End Function


Function audio_GetClip( _
    ByVal clipIndex As Integer, _
    ByRef clip As OseAudioClip _
) As Integer
    If clipIndex < 0 OrElse clipIndex >= audio_ClipCount Then
        Return 0
    End If
    clip = audio_Clips(clipIndex)
    Return -1
End Function


Function audio_AddClip( _
    ByVal filename As String, _
    ByVal startTick As ULongInt, _
    ByVal gainPermille As Integer _
) As Integer
    If audio_ClipCount >= OSE_AUDIO_MAX_CLIPS OrElse _
        startTick > OSE_AUDIO_TIMELINE_MAX_TICK OrElse gainPermille < 0 OrElse _
        gainPermille > 1000 Then Return -1
    Dim As OseWaveInfo waveInfo
    If audio_InspectWave(filename, waveInfo) = 0 Then
        Return -1
    End If

    With audio_Clips(audio_ClipCount)
        .filename = filename
        .startTick = startTick
        .durationMilliseconds = waveInfo.durationMilliseconds
        .gainPermille = gainPermille
        .waveInfo = waveInfo
    End With
    audio_ClipCount += 1
    Return audio_ClipCount - 1
End Function


Function audio_SetClip( _
    ByVal clipIndex As Integer, _
    ByRef clip As OseAudioClip _
) As Integer
    If clipIndex < 0 OrElse clipIndex >= audio_ClipCount Then
        Return 0
    End If
    If audio_PathIsSafe(clip.filename) = 0 OrElse _
        clip.startTick > OSE_AUDIO_TIMELINE_MAX_TICK OrElse _
        clip.durationMilliseconds = 0 OrElse _
        clip.durationMilliseconds > OSE_AUDIO_MAX_DURATION_MILLISECONDS OrElse _
        clip.gainPermille < 0 OrElse clip.gainPermille > 1000 Then Return 0

    Dim As OseWaveInfo waveInfo
    If audio_InspectWave(clip.filename, waveInfo) = 0 Then
        Return 0
    End If
    clip.durationMilliseconds = waveInfo.durationMilliseconds
    clip.waveInfo = waveInfo
    audio_Clips(clipIndex) = clip
    Return -1
End Function


Function audio_RemoveClip(ByVal clipIndex As Integer) As Integer
    If clipIndex < 0 OrElse clipIndex >= audio_ClipCount Then
        Return 0
    End If
    For index As Integer = clipIndex To audio_ClipCount - 2
        audio_Clips(index) = audio_Clips(index + 1)
    Next
    audio_ClipCount -= 1
    audio_Clips(audio_ClipCount).filename = ""
    audio_Clips(audio_ClipCount).durationMilliseconds = 0
    audio_Clips(audio_ClipCount).gainPermille = 0
    Return -1
End Function


' -------------------------------------------------------------------------
' OpenSesh project file
' -------------------------------------------------------------------------

Function audio_SerializeProject( _
    ByVal projectFilename As String, _
    ByVal midiFilename As String, _
    ByRef projectData As String _
) As Integer
    projectData = ""
    If audio_PathIsSafe(projectFilename) = 0 OrElse _
        Len(midiFilename) > OSE_AUDIO_MAX_PATH_BYTES Then Return 0
    If Len(midiFilename) > 0 AndAlso audio_PathIsSafe(midiFilename) = 0 Then _
        Return 0

    audio_AppendProjectLine projectData, "OSEPROJECT 1"
    audio_AppendProjectLine projectData, "MIDI " + Str(Len(midiFilename))
    audio_AppendProjectLine projectData, midiFilename
    audio_AppendProjectLine projectData, "CLIPS " + Str(audio_ClipCount)
    For clipIndex As Integer = 0 To audio_ClipCount - 1
        With audio_Clips(clipIndex)
            If audio_PathIsSafe(.filename) = 0 OrElse _
                .startTick > OSE_AUDIO_TIMELINE_MAX_TICK OrElse _
                .durationMilliseconds = 0 OrElse _
                .durationMilliseconds > OSE_AUDIO_MAX_DURATION_MILLISECONDS OrElse _
                .gainPermille < 0 OrElse .gainPermille > 1000 Then Return 0
            audio_AppendProjectLine projectData, "CLIP " + Str(.startTick) + " " + _
                Str(.durationMilliseconds) + " " + Str(.gainPermille) + " " + _
                Str(Len(.filename))
            audio_AppendProjectLine projectData, .filename
        End With
    Next
    If Len(projectData) > OSE_AUDIO_MAX_PROJECT_BYTES Then
        Return 0
    End If

    Return -1
End Function


Function audio_SaveProject( _
    ByVal projectFilename As String, _
    ByVal midiFilename As String _
) As Integer
    Dim As String projectData
    If audio_SerializeProject(projectFilename, midiFilename, projectData) = 0 _
        Then Return 0

    Return atomicFile_WriteVerified(projectFilename, projectData)
End Function


Function audio_LoadProject( _
    ByVal projectFilename As String, _
    ByRef midiFilename As String, _
    ByVal prepareOnly As Integer _
) As Integer
    ' Declare retained scalar state before checked file-I/O resume labels.
    Dim As Integer loadedCount = 0

    midiFilename = ""
    If audio_PathIsSafe(projectFilename) = 0 Then
        Return 0
    End If

    Dim As Integer fileNumber = FreeFile()
    If Open(projectFilename For Input Access Read As #fileNumber) <> 0 Then
        Return 0
    End If
    Dim As LongInt fileSize = LOF(fileNumber)
    If fileSize < 20 OrElse fileSize > OSE_AUDIO_MAX_PROJECT_BYTES Then
        Close #fileNumber
        Return 0
    End If

    Dim As String lineText
    Line Input #fileNumber, lineText
    If lineText <> "OSEPROJECT 1" Then
        Close #fileNumber
        Return 0
    End If

    Dim As String valueText
    Dim As ULongInt expectedLength
    Line Input #fileNumber, lineText
    If audio_ProjectLine(lineText, "MIDI", valueText) = 0 OrElse _
        audio_ParseUnsigned(valueText, expectedLength, _
            CULngInt(OSE_AUDIO_MAX_PATH_BYTES)) = 0 Then
        Close #fileNumber
        Return 0
    End If
    Line Input #fileNumber, midiFilename
    If Len(midiFilename) <> expectedLength OrElse _
        (Len(midiFilename) > 0 AndAlso audio_PathIsSafe(midiFilename) = 0) Then
        Close #fileNumber
        midiFilename = ""
        Return 0
    End If

    Dim As ULongInt expectedClipCount
    Line Input #fileNumber, lineText
    If audio_ProjectLine(lineText, "CLIPS", valueText) = 0 OrElse _
        audio_ParseUnsigned(valueText, expectedClipCount, _
            CULngInt(OSE_AUDIO_MAX_CLIPS)) = 0 Then
        Close #fileNumber
        midiFilename = ""
        Return 0
    End If

    Dim loadedClips(0 To OSE_AUDIO_MAX_CLIPS - 1) As OseAudioClip
    loadedCount = CInt(expectedClipCount)
    For clipIndex As Integer = 0 To loadedCount - 1
        Line Input #fileNumber, lineText
        If Left(lineText, 5) <> "CLIP " Then
            Close #fileNumber
            midiFilename = ""
            Return 0
        End If
        Dim As Integer cursor = 6
        Dim As ULongInt startTick
        Dim As ULongInt durationMilliseconds
        Dim As ULongInt gainPermille
        Dim As ULongInt pathLength
        If audio_NextUnsigned(lineText, cursor, startTick, _
            OSE_AUDIO_TIMELINE_MAX_TICK) = 0 OrElse _
            audio_NextUnsigned(lineText, cursor, durationMilliseconds, _
                OSE_AUDIO_MAX_DURATION_MILLISECONDS) = 0 OrElse _
            audio_NextUnsigned(lineText, cursor, gainPermille, 1000) = 0 OrElse _
            audio_NextUnsigned(lineText, cursor, pathLength, _
                CULngInt(OSE_AUDIO_MAX_PATH_BYTES)) = 0 OrElse _
            durationMilliseconds = 0 OrElse pathLength = 0 Then
            Close #fileNumber
            midiFilename = ""
            Return 0
        End If
        While cursor <= Len(lineText) AndAlso Mid(lineText, cursor, 1) = " "
            cursor += 1
        Wend
        If cursor <= Len(lineText) Then
            Close #fileNumber
            midiFilename = ""
            Return 0
        End If

        Line Input #fileNumber, loadedClips(clipIndex).filename
        If Len(loadedClips(clipIndex).filename) <> pathLength OrElse _
            audio_PathIsSafe(loadedClips(clipIndex).filename) = 0 Then
            Close #fileNumber
            midiFilename = ""
            Return 0
        End If
        loadedClips(clipIndex).startTick = startTick
        loadedClips(clipIndex).durationMilliseconds = durationMilliseconds
        loadedClips(clipIndex).gainPermille = CInt(gainPermille)
    Next

    /'
        Project loading is transactional. Reject unknown records after the
        declared clip list before committing the staged clips so a future or
        damaged format cannot be partially interpreted as version 1.
    '/
    While Eof(fileNumber) = 0
        Line Input #fileNumber, lineText
        If Len(Trim(lineText)) > 0 Then
            Close #fileNumber
            midiFilename = ""
            Return 0
        End If
    Wend
    Close #fileNumber

    /'
        A coordinated project load keeps a prepared snapshot until its MIDI
        document also loads. Preparation preserves both history stacks even at
        capacity; cancellation restores clips without losing undo or redo.
        Standalone callers retain the ordinary undoable-load behavior.
    '/
    If audio_PrepareHistory() = 0 Then
        midiFilename = ""
        Return 0
    End If
    If prepareOnly = 0 Then
        If audio_CommitPreparedHistory() = 0 Then
            audio_CancelPreparedHistory()
            midiFilename = ""
            Return 0
        End If
    End If
    audio_ClearClipStorage(audio_Clips())
    For clipIndex As Integer = 0 To loadedCount - 1
        audio_Clips(clipIndex) = loadedClips(clipIndex)
    Next
    audio_ClipCount = loadedCount
    Return -1
End Function

/' end of audio_tracks.bas '/
