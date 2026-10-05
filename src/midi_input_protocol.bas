/'
    Project: OpenSesh
    ---------------------------

    File: midi_input_protocol.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements midi_input_protocol.bi; declarations there define the shared interface.

    Purpose:

        Validate and queue MIDI input messages independently from the native
        device API which delivered them.

    Responsibilities:

        - accept bounded channel-voice and supported system-common messages
        - assemble split SysEx chunks and reject oversized messages safely
        - preserve FIFO order in a fixed single-producer/single-consumer queue
        - publish queue indices atomically when a WinMM callback is active
        - provide the same validated queue to the serialized ALSA poller
        - resolve bounded clock intervals without confusing old events with wrap

    Threading:

        On Windows, the WinMM callback is the sole producer and the editor
        thread is the sole consumer. Interlocked publication prevents the
        consumer from seeing a partially written queue slot. Linux ALSA input
        is pumped by the editor thread, so the same queue uses ordinary index
        access there and in single-threaded deterministic protocol tests.

    This file intentionally does NOT contain:

        - native MIDI device enumeration, opening, or closing
        - recording-model changes or UI callbacks
        - Standard MIDI File parsing
'/

#lang "fb"

#include once "midi_input_protocol.bi"

#if defined(__FB_WIN32__)
#include once "windows.bi"
#include once "win/intrin.bi"
#endif

' -------------------------------------------------------------------------
' Wrapping native millisecond clocks
' -------------------------------------------------------------------------

Public Function midiInputProtocol_RebaseTimestamp( _
    ByVal clockOrigin As ULong, _
    ByVal elapsedMilliseconds As ULong _
) As ULong
    Return CULng((CULngInt(clockOrigin) + CULngInt(elapsedMilliseconds)) And _
        &HFFFFFFFFULL)
End Function


Public Function midiInputProtocol_ElapsedMilliseconds( _
    ByVal clockOrigin As ULong, _
    ByVal timestampMilliseconds As ULong, _
    ByRef elapsedMilliseconds As ULongInt _
) As Integer
    elapsedMilliseconds = 0
    ' Widen before subtracting so 32- and 64-bit targets have identical wrap
    ' behavior. A take is bounded to one day, well below the half-period limit.
    Dim As ULongInt elapsedValue = (CULngInt(timestampMilliseconds) + _
        &H100000000ULL - CULngInt(clockOrigin)) And &HFFFFFFFFULL
    If elapsedValue >= &H80000000ULL Then
        Return 0
    End If
    elapsedMilliseconds = elapsedValue
    Return -1
End Function

' -------------------------------------------------------------------------
' Fixed queue and SysEx assembly state
' -------------------------------------------------------------------------

Private Type OseMidiInputProtocolQueueSlot
    As OseMidiInputMessage message
End Type

Private Dim Shared protocol_Queue( _
    0 To OSE_MIDI_INPUT_QUEUE_CAPACITY - 1 _
) As OseMidiInputProtocolQueueSlot
Private Dim Shared protocol_LongAssembly( _
    0 To OSE_MIDI_INPUT_MAX_LONG_BYTES - 1 _
) As UByte
Private Dim Shared protocol_LongAssemblyLength As Integer
Private Dim Shared protocol_LongAssemblyTimestamp As ULong
Private Dim Shared protocol_LongAssemblyActive As Integer
Private Dim Shared protocol_LongAssemblyOverflowed As Integer
Private Dim Shared protocol_LongAssemblyResetRequested As Long
Private Dim Shared protocol_ReadIndex As Long
Private Dim Shared protocol_WriteIndex As Long
Private Dim Shared protocol_DroppedCount As Long
Private Dim Shared protocol_Closing As Long
Private Dim Shared protocol_DeviceIndex As Integer = -1


' -------------------------------------------------------------------------
' Target-aware atomic publication
' -------------------------------------------------------------------------

Private Function protocol_AtomicRead(ByRef value As Long) As Long
#if defined(__FB_WIN32__)
    Return _InterlockedCompareExchange(@value, 0, 0)
#else
    Return value
#endif
End Function


Private Sub protocol_AtomicWrite(ByRef target As Long, ByVal value As Long)
#if defined(__FB_WIN32__)
    ' Only the exchange side effect is required at this publication point.
    ' fblint: disable-next-line FBL310 REASON: Win32 supplies this atomic intrinsic through windows.bi.
    _InterlockedExchange @target, value
#else
    target = value
#endif
End Sub


Private Sub protocol_AtomicIncrement(ByRef target As Long)
#if defined(__FB_WIN32__)
    ' Only the increment side effect is required by the saturating counter.
    ' fblint: disable-next-line FBL310 REASON: Win32 supplies this atomic intrinsic through windows.bi.
    _InterlockedIncrement @target
#else
    target += 1
#endif
End Sub


' -------------------------------------------------------------------------
' Queue operations
' -------------------------------------------------------------------------

Private Sub protocol_ClearQueue()
    protocol_AtomicWrite protocol_ReadIndex, 0
    protocol_AtomicWrite protocol_WriteIndex, 0
    protocol_AtomicWrite protocol_DroppedCount, 0
End Sub


Private Sub protocol_ResetLongAssembly()
    protocol_LongAssemblyLength = 0
    protocol_LongAssemblyTimestamp = 0
    protocol_LongAssemblyActive = 0
    protocol_LongAssemblyOverflowed = 0
End Sub


Private Sub protocol_ApplyLongAssemblyResetRequest()
    If protocol_AtomicRead(protocol_LongAssemblyResetRequested) = 0 Then
        Exit Sub
    End If
    protocol_AtomicWrite protocol_LongAssemblyResetRequested, 0
    protocol_ResetLongAssembly()
End Sub


Private Sub protocol_RecordDrop()
    ' A signed 32-bit counter can be published atomically on supported WinMM
    ' targets. Saturation prevents an indefinitely busy input from wrapping.
    If protocol_AtomicRead(protocol_DroppedCount) < 2147483647 Then
        protocol_AtomicIncrement protocol_DroppedCount
    End If
End Sub


Private Function protocol_BeginEnqueue(ByRef writeIndex As Long) As Integer
    If protocol_AtomicRead(protocol_Closing) <> 0 Then
        Return 0
    End If

    writeIndex = protocol_AtomicRead(protocol_WriteIndex)
    Dim As Long readIndex = protocol_AtomicRead(protocol_ReadIndex)
    Dim As Long nextIndex = writeIndex + 1
    If nextIndex >= OSE_MIDI_INPUT_QUEUE_CAPACITY Then
        nextIndex = 0
    End If

    If nextIndex = readIndex Then
        ' Drop the newest event so unread messages retain their FIFO order.
        protocol_RecordDrop()
        Return 0
    End If
    Return -1
End Function


Private Sub protocol_Publish(ByVal writeIndex As Long)
    Dim As Long nextIndex = writeIndex + 1
    If nextIndex >= OSE_MIDI_INPUT_QUEUE_CAPACITY Then
        nextIndex = 0
    End If
    protocol_AtomicWrite protocol_WriteIndex, nextIndex
End Sub


Private Function protocol_EnqueueShort( _
    ByVal statusByte As UByte, _
    ByVal data1Byte As UByte, _
    ByVal data2Byte As UByte, _
    ByVal timestamp As ULong _
) As Integer
    Dim As Long writeIndex
    If protocol_BeginEnqueue(writeIndex) = 0 Then
        Return 0
    End If

    With protocol_Queue(writeIndex).message
        .messageKind = OSE_MIDI_INPUT_SHORT_MESSAGE
        .status = statusByte
        .data1 = data1Byte
        .data2 = data2Byte
        .timestampMilliseconds = timestamp
        .deviceIndex = protocol_DeviceIndex
        .payloadLength = 0
    End With

    protocol_Publish writeIndex
    Return -1
End Function


Private Sub protocol_EnqueueLong( _
    ByVal payload As UByte Ptr, _
    ByVal payloadLength As Integer, _
    ByVal timestamp As ULong _
)
    If payloadLength < 0 OrElse _
        payloadLength > OSE_MIDI_INPUT_MAX_LONG_BYTES Then
        Exit Sub
    End If
    If payloadLength > 0 AndAlso payload = 0 Then
        Exit Sub
    End If

    Dim As Long writeIndex
    If protocol_BeginEnqueue(writeIndex) = 0 Then
        Exit Sub
    End If

    With protocol_Queue(writeIndex).message
        .messageKind = OSE_MIDI_INPUT_SYSEX_MESSAGE
        .status = 0
        .data1 = 0
        .data2 = 0
        .timestampMilliseconds = timestamp
        .deviceIndex = protocol_DeviceIndex
        .payloadLength = payloadLength
        For payloadIndex As Integer = 0 To payloadLength - 1
            .payload(payloadIndex) = payload[payloadIndex]
        Next
    End With

    protocol_Publish writeIndex
End Sub


' -------------------------------------------------------------------------
' MIDI message validation and assembly
' -------------------------------------------------------------------------

Private Function protocol_IsSupportedShortMessage( _
    ByVal statusByte As UByte, _
    ByVal data1Byte As UByte, _
    ByVal data2Byte As UByte _
) As Integer
    Dim As Integer statusClass = statusByte And &HF0

    If statusClass >= &H80 AndAlso statusClass <= &HE0 Then
        If data1Byte > 127 Then
            Return 0
        End If
        If statusClass <> &HC0 AndAlso statusClass <> &HD0 AndAlso _
            data2Byte > 127 Then
            Return 0
        End If
        Return -1
    End If

    Select Case statusByte
        Case &HF1, &HF3
            If data1Byte > 127 Then
                Return 0
            End If
            Return -1
        Case &HF2
            If data1Byte > 127 OrElse data2Byte > 127 Then
                Return 0
            End If
            Return -1
        Case &HF6
            Return -1
    End Select
    Return 0
End Function


Public Sub midiInputProtocol_Initialize(ByVal deviceIndex As Integer)
    protocol_AtomicWrite protocol_Closing, 0
    protocol_AtomicWrite protocol_LongAssemblyResetRequested, 0
    protocol_DeviceIndex = deviceIndex
    protocol_ClearQueue()
    protocol_ResetLongAssembly()
End Sub


Public Sub midiInputProtocol_SetClosing(ByVal closing As Integer)
    protocol_AtomicWrite protocol_Closing, IIf(closing <> 0, -1, 0)
End Sub


Public Sub midiInputProtocol_ClearPending()
    ' The consumer discards only events already published. A callback racing
    ' this operation may publish the first valid event of the next pass.
    Dim As Long writeIndex = protocol_AtomicRead(protocol_WriteIndex)
    protocol_AtomicWrite protocol_ReadIndex, writeIndex
    protocol_AtomicWrite protocol_LongAssemblyResetRequested, -1
End Sub


Public Function midiInputProtocol_ProcessShort( _
    ByVal statusByte As Integer, _
    ByVal data1Byte As Integer, _
    ByVal data2Byte As Integer, _
    ByVal timestamp As ULong _
) As Integer
    If statusByte < 0 OrElse statusByte > 255 OrElse _
        data1Byte < 0 OrElse data1Byte > 255 OrElse _
        data2Byte < 0 OrElse data2Byte > 255 Then
        Return 0
    End If

    Dim As UByte statusValue = CByte(statusByte)
    Dim As UByte data1Value = CByte(data1Byte)
    Dim As UByte data2Value = CByte(data2Byte)
    If protocol_IsSupportedShortMessage( _
        statusValue, data1Value, data2Value) = 0 Then
        Return 0
    End If

    Return protocol_EnqueueShort( _
        statusValue, data1Value, data2Value, timestamp)
End Function


Public Function midiInputProtocol_ProcessLongChunk( _
    ByVal payload As UByte Ptr, _
    ByVal payloadLength As Integer, _
    ByVal timestamp As ULong _
) As Integer
    If payload = 0 OrElse payloadLength <= 0 OrElse _
        payloadLength > OSE_MIDI_INPUT_MAX_LONG_BYTES Then
        Return 0
    End If

    protocol_ApplyLongAssemblyResetRequest()

    For payloadIndex As Integer = 0 To payloadLength - 1
        Dim As UByte dataByte = payload[payloadIndex]

        ' F0 is a safe resynchronization point after an interrupted message.
        If dataByte = &HF0 Then
            protocol_LongAssemblyLength = 0
            protocol_LongAssemblyTimestamp = timestamp
            protocol_LongAssemblyActive = -1
            protocol_LongAssemblyOverflowed = 0
        ElseIf protocol_LongAssemblyActive = 0 Then
            If dataByte = &HF7 Then
                protocol_LongAssembly(0) = dataByte
                protocol_EnqueueLong @protocol_LongAssembly(0), 1, timestamp
            End If
            Continue For
        End If

        If dataByte = &HF0 OrElse protocol_LongAssemblyActive <> 0 Then
            If protocol_LongAssemblyOverflowed = 0 Then
                If protocol_LongAssemblyLength < _
                    OSE_MIDI_INPUT_MAX_LONG_BYTES Then
                    protocol_LongAssembly(protocol_LongAssemblyLength) = _
                        dataByte
                    protocol_LongAssemblyLength += 1
                Else
                    protocol_LongAssemblyOverflowed = -1
                End If
            End If

            If dataByte = &HF7 Then
                If protocol_LongAssemblyOverflowed = 0 AndAlso _
                    protocol_LongAssemblyLength > 0 Then
                    protocol_EnqueueLong @protocol_LongAssembly(0), _
                        protocol_LongAssemblyLength, _
                        protocol_LongAssemblyTimestamp
                End If
                protocol_ResetLongAssembly()
            End If
        End If
    Next
    Return -1
End Function


Public Function midiInputProtocol_Poll( _
    ByRef message As OseMidiInputMessage _
) As Integer
    Dim As Long readIndex = protocol_AtomicRead(protocol_ReadIndex)
    Dim As Long writeIndex = protocol_AtomicRead(protocol_WriteIndex)
    If readIndex = writeIndex Then
        Return 0
    End If

    message = protocol_Queue(readIndex).message

    Dim As Long nextIndex = readIndex + 1
    If nextIndex >= OSE_MIDI_INPUT_QUEUE_CAPACITY Then
        nextIndex = 0
    End If
    protocol_AtomicWrite protocol_ReadIndex, nextIndex
    Return -1
End Function


Public Function midiInputProtocol_GetDroppedCount() As ULongInt
    Dim As Long droppedCount = protocol_AtomicRead(protocol_DroppedCount)
    If droppedCount < 0 Then
        Return 2147483647
    End If
    Return CULngInt(droppedCount)
End Function

/' end of midi_input_protocol.bas '/
