/'
    Project: OpenMidiSesh
    File: midi_input_android.bas
    Targets: Android ARM, AArch64 and x86_64 in the fb dialect.
    Module API: Implements midi_input.bi; selected by the Android unity build.
    Purpose: Implement portable input operations through the Android MIDI service.
    Responsibilities: Bridge calls, byte decoding, monotonic clock and drop counts.
    This file intentionally does NOT contain: Java callbacks, USB drivers, output or editor policy.
    Only the editor thread calls JNI and the decoder. Java callbacks publish to
    their own bounded queue. An accepted open may still be pending or fail later.
'/
#lang "fb"
#include once "midi_input.bi"
#include once "midi_input_protocol.bi"
#include once "midi_input_stream.bi"
Extern "C"
    Declare Function ose_midi_call(ByVal methodName As Const ZString Ptr, _
        ByVal argument As Long, ByVal hasArgument As Long) As Long
    Declare Function ose_midi_read(ByVal target As UByte Ptr) As Long
    Declare Sub ose_midi_name(ByVal index As Long, ByVal target As ZString Ptr, ByVal capacity As Long)
    Declare Function ose_midi_clock() As ULong
End Extern
' The editor thread owns this endpoint index and last observed producer drop count.
Private Dim Shared androidMidi_Index As Integer = -1
Private Dim Shared androidMidi_Drops As ULong

Public Function midiInput_GetDeviceCount() As Integer
    Return ose_midi_call("refresh", 0, 0)
End Function
Public Function midiInput_GetDeviceName(ByVal deviceIndex As Integer) As String
    Dim As ZString * 256 labelText
    If deviceIndex < 0 OrElse deviceIndex > 2147483647 Then Return ""
    ose_midi_name CLng(deviceIndex), @labelText, SizeOf(labelText)
    Return labelText
End Function
Public Sub midiInput_Close()
    ose_midi_call "close", 0, 0
    androidMidi_Index = -1
    midiInputStream_Reset()
    midiInputProtocol_SetClosing -1
End Sub
Public Function midiInput_Open(ByVal deviceIndex As Integer) As Integer
    midiInput_Close()
    If deviceIndex < 0 OrElse deviceIndex >= midiInput_GetDeviceCount() Then Return 0
    midiInputProtocol_Initialize deviceIndex
    If midiInputProtocol_IsReady() = 0 Then Return 0
    If ose_midi_call("open", CLng(deviceIndex), 1) = 0 Then Return 0
    androidMidi_Index = deviceIndex
    androidMidi_Drops = 0
    Return -1
End Function
Public Function midiInput_IsOpen() As Integer
    Return IIf(androidMidi_Index >= 0 AndAlso ose_midi_call("status", 0, 0) > 0, -1, 0)
End Function
Public Function midiInput_GetOpenDeviceIndex() As Integer
    If midiInput_IsOpen() = 0 Then Return -1
    Return androidMidi_Index
End Function
Public Sub midiInput_ClearPending()
    ose_midi_call "clear", 0, 0
    midiInputStream_Reset()
    midiInputProtocol_ClearPending()
End Sub
Public Function midiInput_GetClockMilliseconds(ByRef timestampMilliseconds As ULong) As Integer
    timestampMilliseconds = ose_midi_clock()
    Return midiInput_IsOpen()
End Function
Public Function midiInput_GetDroppedCount() As ULongInt
    Return CULng(ose_midi_call("drops", 0, 0)) + midiInputProtocol_GetDroppedCount()
End Function
Public Function midiInput_Poll(ByRef message As OseMidiInputMessage) As Integer
    If midiInput_IsOpen() = 0 Then Return 0
    Dim As ULong drops = CULng(ose_midi_call("drops", 0, 0))
    If drops <> androidMidi_Drops Then
        ' A missing byte may be a status byte. Discard running status and SysEx
        ' before decoding more input instead of inventing notes from fragments.
        midiInput_ClearPending()
        androidMidi_Drops = drops
    End If
    If midiInputProtocol_Poll(message) <> 0 Then Return -1
    Dim As UByte packet(0 To 259)
    ' Bound work per GUI frame even if the device continuously sends data.
    For batch As Integer = 1 To 32
        Dim As Integer size = ose_midi_read(@packet(0))
        If size < 5 OrElse size > 260 Then Exit For
        Dim As ULong timestamp = CULng(packet(0)) Or (CULng(packet(1)) Shl 8) Or _
            (CULng(packet(2)) Shl 16) Or (CULng(packet(3)) Shl 24)
        midiInputStream_Process @packet(4), size - 4, timestamp
        If midiInputProtocol_Poll(message) <> 0 Then Return -1
    Next
    Return 0
End Function
/' end of midi_input_android.bas '/
