/'
    Project: OpenMidiSesh
    File: midi_input_stream.bas
    Targets: Shared MIDI decoder in the fb dialect.
    Module API: Implements midi_input_stream.bi; this module owns decoder state.
    Purpose: Decode fragmented MIDI 1.0 byte streams into the shared queue.
    Responsibilities: Running status, real-time interleaving and bounded SysEx.
    This file intentionally does NOT contain: device discovery, synthesis or editor state.
    One consumer thread owns decoder state; reset only between input batches.
'/
#lang "fb"
#include once "midi_input_stream.bi"
#include once "midi_input_protocol.bi"
Private Dim Shared stream_Status As Integer
Private Dim Shared stream_First As Integer
Private Dim Shared stream_HaveFirst As Integer
Private Dim Shared stream_SysEx As Integer

Public Sub midiInputStream_Reset()
    stream_Status = 0
    stream_First = 0
    stream_HaveFirst = 0
    stream_SysEx = 0
End Sub

Public Sub midiInputStream_Process(ByVal bytes As Const UByte Ptr, _
    ByVal count As Integer, ByVal timestamp As ULong)
    If bytes = 0 OrElse count < 1 OrElse count > 4096 Then Exit Sub
    For i As Integer = 0 To count - 1
        Dim As UByte value = bytes[i]
        ' Real-time status never cancels running status or interrupts SysEx.
        If value >= &HF8 Then Continue For
        If stream_SysEx <> 0 AndAlso (value < &H80 OrElse value = &HF7) Then
            midiInputProtocol_ProcessLongChunk @value, 1, timestamp
            If value = &HF7 Then stream_SysEx = 0
            Continue For
        End If
        If value >= &H80 Then
            stream_HaveFirst = 0
            stream_SysEx = 0
            stream_Status = value
            Select Case value
                Case &HF0
                    stream_SysEx = -1
                    stream_Status = 0
                    midiInputProtocol_ProcessLongChunk @value, 1, timestamp
                Case &HF6
                    midiInputProtocol_ProcessShort value, 0, 0, timestamp
                    stream_Status = 0
                Case &HF4, &HF5, &HF7
                    stream_Status = 0
            End Select
            Continue For
        End If
        If stream_Status = 0 Then Continue For
        Dim As Integer messageType = stream_Status And &HF0
        If messageType = &HC0 OrElse messageType = &HD0 OrElse _
            stream_Status = &HF1 OrElse stream_Status = &HF3 Then
            midiInputProtocol_ProcessShort stream_Status, value, 0, timestamp
            If stream_Status >= &HF0 Then stream_Status = 0
        ElseIf stream_HaveFirst = 0 Then
            stream_First = value
            stream_HaveFirst = -1
        Else
            midiInputProtocol_ProcessShort stream_Status, stream_First, value, timestamp
            stream_HaveFirst = 0
            If stream_Status >= &HF0 Then stream_Status = 0
        End If
    Next
End Sub
/' end of midi_input_stream.bas '/
