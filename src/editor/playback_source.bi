/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/playback_source.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Select the current arrangement or note playback source.

    Responsibilities:

        - route transport to the active playback snapshot
        - keep selection playback separate from the saved document

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_PLAYBACK_SOURCE_BI__
#define __OSE_EDITOR_PLAYBACK_SOURCE_BI__


' -------------------------------------------------------------------------
' Arrangement and selected-note playback source
' -------------------------------------------------------------------------

Private Function session_PlaybackNoteCount() As Integer
    If session_SelectedNotePlaybackActive <> 0 Then _
        Return session_SelectedNotePlayback.count
    Return midi_GetEditableNoteCount()
End Function


Private Function session_GetPlaybackNote( _
    ByVal playbackIndex As Integer, _
    ByRef editableNote As MidiEditableNote _
) As Integer
    If session_SelectedNotePlaybackActive <> 0 Then
        Return selectedNotePlayback_GetNote( _
            session_SelectedNotePlayback, playbackIndex, editableNote)
    End If
    Return midi_GetEditableNote(playbackIndex, editableNote)
End Function


Private Function session_PlaybackEndTick() As ULongInt
    If session_SelectedNotePlaybackActive <> 0 AndAlso session_SelectedNoteLooping <> 0 Then _
        Return session_SelectedNoteLoopEnd
    If session_SelectedNotePlaybackActive <> 0 Then _
        Return session_SelectedNotePlayback.endTick
    Return session_TimelineDurationTicks()
End Function

#endif

/' end of src/editor/playback_source.bi '/
