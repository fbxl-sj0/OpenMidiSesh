/'
    Project: OpenSesh
    ---------------------------

    File: midi_input_win.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows WinMM implementation guarded by __FB_WIN32__.

    Module API: Implements midi_input.bi through WinMM; queue policy is in midi_input_protocol.bi.

    Purpose:

        Adapt one optional Windows WinMM MIDI-input device to the shared,
        platform-neutral input protocol queue.

    Responsibilities:

        - enumerate and open one Windows MIDI input device
        - forward WinMM short messages and long buffers to the protocol module
        - prepare, recycle, and release a bounded set of SysEx input buffers
        - isolate WinMM callback and buffer behavior from other platforms

    Threading:

        WinMM invokes the callback on a system-owned thread. This adapter never
        calls the model or UI there. midi_input_protocol.bas owns validation,
        SysEx assembly, queue storage, and the interlocked publication rules;
        the editor thread remains the sole consumer.

    This file intentionally does NOT contain:

        - note insertion, recording timing policy, or undo handling
        - protocol validation, queue storage, or SysEx assembly
        - omaGui widgets, sfxlib calls, or recovered Midisoft code
'/

#lang "fb"

#include once "midi_input.bi"
#include once "midi_input_protocol.bi"

#if defined(__FB_WIN32__)

#include once "windows.bi"
#include once "win/mmsystem.bi"
#include once "win/intrin.bi"

' -------------------------------------------------------------------------
' WinMM device buffers and state
' -------------------------------------------------------------------------

Const MIDI_INPUT_LONG_BUFFER_COUNT As Integer = 4
Const MIDI_INPUT_LONG_BUFFER_BYTES As Integer = _
    OSE_MIDI_INPUT_MAX_LONG_BYTES
' These values are the public WinMM callback message identifiers.
Const MIDI_INPUT_CALLBACK_DATA As Integer = &H3C3
Const MIDI_INPUT_CALLBACK_LONG_DATA As Integer = &H3C4
Const MIDI_INPUT_MMRESULT_OK As Integer = 0

Private Dim Shared midiInput_LongStorage( _
    0 To MIDI_INPUT_LONG_BUFFER_COUNT - 1, _
    0 To MIDI_INPUT_LONG_BUFFER_BYTES - 1 _
) As UByte
Private Dim Shared midiInput_LongHeaders( _
    0 To MIDI_INPUT_LONG_BUFFER_COUNT - 1 _
) As MIDIHDR
Private Dim Shared midiInput_LongPrepared( _
    0 To MIDI_INPUT_LONG_BUFFER_COUNT - 1 _
) As Integer
Private Dim Shared midiInput_Opened As Integer
Private Dim Shared midiInput_DeviceIndex As Integer = -1
Private Dim Shared midiInput_Closing As Long
Private Dim Shared midiInput_Handle As HMIDIIN
' Written before midiInStart enables callbacks; unchanged until close has
' drained them. WinMM callback timestamps are relative to that start call.
Private Dim Shared midiInput_TimestampOrigin As ULong

' -------------------------------------------------------------------------
' WinMM callback and device lifecycle
' -------------------------------------------------------------------------


Private Function midiInput_FindLongHeader( _
    ByVal header As MIDIHDR Ptr _
) As Integer
    If header = 0 Then Return -1
    For headerIndex As Integer = 0 To MIDI_INPUT_LONG_BUFFER_COUNT - 1
        If @midiInput_LongHeaders(headerIndex) = header Then _
            Return headerIndex
    Next
    Return -1
End Function


Private Function midiInput_PrepareLongBuffers() As Integer
    For bufferIndex As Integer = 0 To MIDI_INPUT_LONG_BUFFER_COUNT - 1
        With midiInput_LongHeaders(bufferIndex)
            .lpData = @midiInput_LongStorage(bufferIndex, 0)
            .dwBufferLength = MIDI_INPUT_LONG_BUFFER_BYTES
            .dwBytesRecorded = 0
            .dwUser = 0
            .dwFlags = 0
            .lpNext = 0
            .reserved = 0
            .dwOffset = 0
            For reservedIndex As Integer = 0 To 7
                .dwReserved(reservedIndex) = 0
            Next
        End With

        Dim As MMRESULT result = midiInPrepareHeader( _
            midiInput_Handle, @midiInput_LongHeaders(bufferIndex), _
            SizeOf(midiInput_LongHeaders(bufferIndex)))
        If result <> MIDI_INPUT_MMRESULT_OK Then Return 0
        midiInput_LongPrepared(bufferIndex) = -1

        result = midiInAddBuffer( _
            midiInput_Handle, @midiInput_LongHeaders(bufferIndex), _
            SizeOf(midiInput_LongHeaders(bufferIndex)))
        If result <> MIDI_INPUT_MMRESULT_OK Then Return 0
    Next
    Return -1
End Function


Private Sub midiInput_UnprepareLongBuffers()
    For bufferIndex As Integer = 0 To MIDI_INPUT_LONG_BUFFER_COUNT - 1
        If midiInput_LongPrepared(bufferIndex) <> 0 Then
            midiInUnprepareHeader( _
                midiInput_Handle, @midiInput_LongHeaders(bufferIndex), _
                SizeOf(midiInput_LongHeaders(bufferIndex)))
            midiInput_LongPrepared(bufferIndex) = 0
        End If
    Next
End Sub


Private Sub midiInput_Callback( _
    ByVal hdrvr As HDRVR, _
    ByVal uMsg As UINT, _
    ByVal dwUser As DWORD_PTR, _
    ByVal dw1 As DWORD_PTR, _
    ByVal dw2 As DWORD_PTR _
)
    ' WinMM can report open/close/error/long-data notifications here. The
    ' callback only copies complete bounded messages into the application
    ' queue; model and UI work remains on the main thread.
    If uMsg = MIDI_INPUT_CALLBACK_DATA Then
        Dim As UByte statusByte = CByte(dw1 And &HFF)
        Dim As UByte data1Byte = CByte((dw1 Shr 8) And &HFF)
        Dim As UByte data2Byte = CByte((dw1 Shr 16) And &HFF)

        ' Realtime bytes have no stable event-time meaning in a Standard MIDI
        ' track. Supported system-common messages do have a defined payload
        ' and are passed through; F4/F5 and other undefined statuses remain
        ' outside the short-message contract.
        midiInputProtocol_ProcessShort(statusByte, data1Byte, data2Byte, _
            midiInputProtocol_RebaseTimestamp(midiInput_TimestampOrigin, _
                CULng(dw2 And &HFFFFFFFF)))
        Exit Sub
    End If

    If uMsg <> MIDI_INPUT_CALLBACK_LONG_DATA Then Exit Sub
    If _InterlockedCompareExchange(@midiInput_Closing, 0, 0) <> 0 Then _
        Exit Sub

    Dim As MIDIHDR Ptr longHeader = Cast(MIDIHDR Ptr, dw1)
    Dim As Integer headerIndex = midiInput_FindLongHeader(longHeader)
    If headerIndex < 0 Then Exit Sub

    Dim As Integer byteCount = CInt(longHeader->dwBytesRecorded)
    If byteCount < 0 OrElse byteCount > MIDI_INPUT_LONG_BUFFER_BYTES Then _
        byteCount = MIDI_INPUT_LONG_BUFFER_BYTES
    midiInputProtocol_ProcessLongChunk( _
        Cast(UByte Ptr, longHeader->lpData), byteCount, _
        midiInputProtocol_RebaseTimestamp(midiInput_TimestampOrigin, _
            CULng(dw2 And &HFFFFFFFF)))

    If _InterlockedCompareExchange(@midiInput_Closing, 0, 0) = 0 AndAlso _
        midiInput_Opened <> 0 Then
        midiInAddBuffer(midiInput_Handle, longHeader, _
            SizeOf(midiInput_LongHeaders(headerIndex)))
    End If
End Sub


' -------------------------------------------------------------------------
' Public MIDI-input interface
' -------------------------------------------------------------------------

Function midiInput_GetDeviceCount() As Integer
    Dim As ULong deviceCount = midiInGetNumDevs()
    If deviceCount > 2147483647 Then Return 2147483647
    Return CInt(deviceCount)
End Function


Function midiInput_GetDeviceName(ByVal deviceIndex As Integer) As String
    If deviceIndex < 0 OrElse deviceIndex >= midiInput_GetDeviceCount() Then _
        Return ""

    Dim As MIDIINCAPSA capabilities
    ' UINT_PTR is declared by the WinMM include on the selected Windows target. FB-LINTER: DISABLE-NEXT-LINE FBL310 REASON: UINT_PTR is declared by the WinMM include on the selected Windows target.
    If midiInGetDevCapsA( _
        Cast(UINT_PTR, deviceIndex), _
        @capabilities, _
        SizeOf(capabilities) _
    ) <> MMSYSERR_NOERROR Then Return "" ' WinMM result constant. FB-LINTER: DISABLE-LINE FBL310 REASON: MMSYSERR_NOERROR is declared by the selected WinMM include.

    Return capabilities.szPname
End Function


Function midiInput_Open(ByVal deviceIndex As Integer) As Integer
    If deviceIndex < 0 OrElse deviceIndex >= midiInput_GetDeviceCount() Then _
        Return 0

    If midiInput_Opened <> 0 Then
        If midiInput_DeviceIndex = deviceIndex Then Return -1
        midiInput_Close()
    End If

    midiInputProtocol_Initialize deviceIndex
    _InterlockedExchange(@midiInput_Closing, 0)

    Dim As HMIDIIN openedHandle
    Dim As MMRESULT result = midiInOpen( _
        @openedHandle, _
        CUInt(deviceIndex), _
        Cast(DWORD_PTR, @midiInput_Callback), _
        0, _
        CALLBACK_FUNCTION _
    )
    If result <> MMSYSERR_NOERROR Then Return 0 ' WinMM result constant. FB-LINTER: DISABLE-LINE FBL310 REASON: MMSYSERR_NOERROR is declared by the selected WinMM include.

    midiInput_Handle = openedHandle
    midiInput_DeviceIndex = deviceIndex
    midiInput_Opened = -1

    If midiInput_PrepareLongBuffers() = 0 Then
        midiInput_Close()
        Return 0
    End If

    ' midiInStart resets its event timestamp to zero. Rebase that epoch onto
    ' timeGetTime so a later Record command can sample it before any note.
    midiInput_TimestampOrigin = timeGetTime()
    result = midiInStart(midiInput_Handle)
    If result = MMSYSERR_NOERROR Then Return -1 ' WinMM result constant. FB-LINTER: DISABLE-LINE FBL310 REASON: MMSYSERR_NOERROR is declared by the selected WinMM include.

    midiInput_Close()
    Return 0
End Function


Sub midiInput_Close()
    If midiInput_Opened = 0 Then
        midiInput_DeviceIndex = -1
        midiInput_TimestampOrigin = 0
        midiInputProtocol_Initialize -1
        Exit Sub
    End If

    ' Prevent callbacks that are already queued by WinMM from adding new
    ' slots while the handle is being stopped and reset.
    _InterlockedExchange(@midiInput_Closing, -1)
    midiInputProtocol_SetClosing -1
    midiInStop(midiInput_Handle)
    midiInReset(midiInput_Handle)
    midiInput_UnprepareLongBuffers()
    midiInClose(midiInput_Handle)
    midiInput_Handle = 0
    midiInput_Opened = 0
    midiInput_DeviceIndex = -1
    midiInput_TimestampOrigin = 0
    midiInputProtocol_Initialize -1
End Sub


Function midiInput_IsOpen() As Integer
    Return midiInput_Opened
End Function


Function midiInput_GetOpenDeviceIndex() As Integer
    Return midiInput_DeviceIndex
End Function


Sub midiInput_ClearPending()
    ' The consumer can discard everything published so far without touching
    ' a slot that the callback has not yet published. A callback racing this
    ' operation may publish one event immediately afterward; that event is
    ' compared with the next recording's clock origin before it is accepted.
    midiInputProtocol_ClearPending()
End Sub


Function midiInput_GetClockMilliseconds( _
    ByRef timestampMilliseconds As ULong _
) As Integer
    timestampMilliseconds = 0
    If midiInput_Opened = 0 Then Return 0
    timestampMilliseconds = timeGetTime()
    Return -1
End Function


Function midiInput_Poll( _
    ByRef message As OseMidiInputMessage _
) As Integer
    Return midiInputProtocol_Poll(message)
End Function


Function midiInput_GetDroppedCount() As ULongInt
    Return midiInputProtocol_GetDroppedCount()
End Function


#endif

/' end of midi_input_win.bas '/
