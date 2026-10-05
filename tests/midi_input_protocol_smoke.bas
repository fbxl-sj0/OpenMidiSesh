/'
    Project: OpenSesh
    ----------------------------

    File: midi_input_protocol_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Exercise the deterministic MIDI-input protocol path without requiring
        an operating-system MIDI device.

    Responsibilities:

        - verify channel and system-common short-message validation
        - verify bounded SysEx reassembly and reset behavior
        - verify queue capacity, FIFO order, and drop accounting
        - preserve initial silence and resolve clock wrap without accepting stale input

    This file intentionally does NOT contain:

        - a WinMM or ALSA device-open operation
        - editor recording or UI code
        - assumptions about a particular MIDI driver
'/

#lang "fb"

#include once "../midi_input.bi"
#include once "../midi_input_protocol.bi"

Private Sub test_Fail(ByVal message As String)
    Print "ERROR: " + message
    End 1
End Sub


Private Function test_InjectLongString( _
    ByVal payload As String, _
    ByVal timestamp As ULong _
) As Integer
    If Len(payload) <= 0 Then
        Return 0
    End If
    Return midiInputProtocol_ProcessLongChunk( _
        Cast(UByte Ptr, StrPtr(payload)), Len(payload), timestamp)
End Function


Private Sub test_ExpectNoMessage()
    Dim As OseMidiInputMessage message
    If midiInputProtocol_Poll(message) <> 0 Then
        Print "unexpected status="; message.status; _
            " data1="; message.data1; " data2="; message.data2
        test_Fail "unexpected MIDI input message"
    End If
End Sub


' Event time is measured from the captured recording origin, not from the
' first note. The native device may have been open long before Record.
Dim As ULongInt elapsedMilliseconds
If midiInputProtocol_ElapsedMilliseconds(900000, 905000, _
    elapsedMilliseconds) = 0 OrElse elapsedMilliseconds <> 5000 Then _
    test_Fail "recording clock discarded silence before the first event"
If midiInputProtocol_ElapsedMilliseconds(900000, 906250, _
    elapsedMilliseconds) = 0 OrElse elapsedMilliseconds <> 6250 Then _
    test_Fail "later event did not retain the same recording origin"
If midiInputProtocol_ElapsedMilliseconds(0, 0, _
    elapsedMilliseconds) = 0 OrElse elapsedMilliseconds <> 0 Then _
    test_Fail "a valid zero-valued clock was rejected"

If midiInputProtocol_RebaseTimestamp(&HFFFFFFF0UL, 36) <> 20 OrElse _
    midiInputProtocol_RebaseTimestamp(900000, 5000) <> 905000 Then _
    test_Fail "relative native timestamp was not rebased modulo 2^32"
If midiInputProtocol_ElapsedMilliseconds(&HFFFFFFF0UL, 20, _
    elapsedMilliseconds) = 0 OrElse elapsedMilliseconds <> 36 Then _
    test_Fail "ordinary native-clock rollover was rejected"
If midiInputProtocol_ElapsedMilliseconds(100, &H80000063UL, _
    elapsedMilliseconds) = 0 OrElse elapsedMilliseconds <> &H7FFFFFFFULL Then _
    test_Fail "last unambiguous forward timestamp was rejected"

elapsedMilliseconds = 123
If midiInputProtocol_ElapsedMilliseconds(900000, 899999, _
    elapsedMilliseconds) <> 0 OrElse elapsedMilliseconds <> 0 Then _
    test_Fail "a callback from before Record became a huge forward interval"
If midiInputProtocol_ElapsedMilliseconds(20, &HFFFFFFF0UL, _
    elapsedMilliseconds) <> 0 OrElse elapsedMilliseconds <> 0 Then _
    test_Fail "a stale event from before clock rollover was accepted"
If midiInputProtocol_ElapsedMilliseconds(100, &H80000064UL, _
    elapsedMilliseconds) <> 0 OrElse elapsedMilliseconds <> 0 Then _
    test_Fail "the ambiguous half-period timestamp was accepted"

midiInputProtocol_Initialize -1

If midiInputProtocol_ProcessShort(&H90, 60, 100, 1234) = 0 Then _
    test_Fail "valid note-on was rejected"
Dim As OseMidiInputMessage message
If midiInputProtocol_Poll(message) = 0 OrElse _
    message.messageKind <> OSE_MIDI_INPUT_SHORT_MESSAGE OrElse _
    message.status <> &H90 OrElse message.data1 <> 60 OrElse _
    message.data2 <> 100 OrElse message.timestampMilliseconds <> 1234 Then
    test_Fail "note-on message was not preserved"
End If

If midiInputProtocol_ProcessShort(&HF8, 0, 0, 1) <> 0 OrElse _
    midiInputProtocol_ProcessShort(&HF4, 0, 0, 2) <> 0 OrElse _
    midiInputProtocol_ProcessShort(&H90, 128, 0, 3) <> 0 OrElse _
    midiInputProtocol_ProcessShort(&HE0, 0, 128, 4) <> 0 OrElse _
    midiInputProtocol_ProcessShort(&HF2, 1, 128, 5) <> 0 Then
    test_Fail "invalid short message was accepted"
End If
test_ExpectNoMessage()

If midiInputProtocol_ProcessShort(&HF1, 7, 255, 10) = 0 OrElse _
    midiInputProtocol_ProcessShort(&HF2, 1, 2, 11) = 0 OrElse _
    midiInputProtocol_ProcessShort(&HF3, 9, 255, 12) = 0 OrElse _
    midiInputProtocol_ProcessShort(&HF6, 255, 255, 13) = 0 Then
    test_Fail "valid system-common message was rejected"
End If

For expectedStatus As Integer = &HF1 To &HF6
    If expectedStatus = &HF4 OrElse expectedStatus = &HF5 Then
        Continue For
    End If
    If midiInputProtocol_Poll(message) = 0 OrElse _
        message.status <> expectedStatus Then
        test_Fail "system-common FIFO order was not preserved"
    End If
Next
test_ExpectNoMessage()

' The protocol boundary owns device tagging and the close gate independently
' from either platform backend.
midiInputProtocol_Initialize 7
If midiInputProtocol_ProcessShort(&H90, 64, 99, 4000) = 0 OrElse _
    midiInputProtocol_Poll(message) = 0 OrElse message.deviceIndex <> 7 OrElse _
    message.data1 <> 64 Then _
    test_Fail "direct protocol initialization or short-message path failed"
midiInputProtocol_SetClosing -1
If midiInputProtocol_ProcessShort(&H90, 65, 99, 4001) <> 0 Then _
    test_Fail "closing protocol accepted a new short message"
midiInputProtocol_SetClosing 0
Dim As UByte directLongPayload(0 To 2) = {&HF0, &H7D, &HF7}
If midiInputProtocol_ProcessLongChunk( _
    @directLongPayload(0), 3, 4002) = 0 OrElse _
    midiInputProtocol_Poll(message) = 0 OrElse message.deviceIndex <> 7 OrElse _
    message.payloadLength <> 3 Then _
    test_Fail "direct protocol long-message path failed"
If midiInputProtocol_ProcessShort(&H90, 66, 99, 4003) = 0 Then _
    test_Fail "direct protocol pending-message setup failed"
midiInputProtocol_ClearPending()
If midiInputProtocol_Poll(message) <> 0 OrElse _
    midiInputProtocol_GetDroppedCount() <> 0 Then _
    test_Fail "direct protocol clear or drop accounting failed"

midiInputProtocol_Initialize -1
If test_InjectLongString( _
    Chr(&HF0) + Chr(&H7D) + Chr(&H01), 2000) = 0 Then _
    test_Fail "first SysEx chunk was rejected"
test_ExpectNoMessage()
If test_InjectLongString(Chr(&H02) + Chr(&HF7), 2001) = 0 OrElse _
    midiInputProtocol_Poll(message) = 0 Then
    test_Fail "completed SysEx message was not queued"
End If
If message.messageKind <> OSE_MIDI_INPUT_SYSEX_MESSAGE OrElse _
    message.payloadLength <> 5 OrElse _
    message.payload(0) <> &HF0 OrElse message.payload(1) <> &H7D OrElse _
    message.payload(2) <> &H01 OrElse message.payload(3) <> &H02 OrElse _
    message.payload(4) <> &HF7 OrElse _
    message.timestampMilliseconds <> 2000 Then
    test_Fail "SysEx payload or timestamp was not preserved"
End If
test_ExpectNoMessage()

midiInputProtocol_Initialize -1
If test_InjectLongString(Chr(&HF0) + Chr(&H01), 3000) = 0 Then _
    test_Fail "unterminated SysEx setup failed"
midiInputProtocol_Initialize -1
If test_InjectLongString(Chr(&H02) + Chr(&HF7), 3001) = 0 Then _
    test_Fail "post-reset SysEx chunk was rejected"
If midiInputProtocol_Poll(message) = 0 OrElse _
    message.messageKind <> OSE_MIDI_INPUT_SYSEX_MESSAGE OrElse _
    message.payloadLength <> 1 OrElse message.payload(0) <> &HF7 Then
    test_Fail "standalone F7 SysEx event was not preserved"
End If
test_ExpectNoMessage()

midiInputProtocol_Initialize -1
Dim As Integer acceptedMessages = 0
For messageIndex As Integer = 0 To OSE_MIDI_INPUT_QUEUE_CAPACITY + 15
    If midiInputProtocol_ProcessShort( _
        &H90, messageIndex Mod 128, 80, CULng(messageIndex)) <> 0 Then
        acceptedMessages += 1
    End If
Next
If acceptedMessages <> OSE_MIDI_INPUT_QUEUE_CAPACITY - 1 Then _
    test_Fail "queue accepted an unexpected number of messages"
If midiInputProtocol_GetDroppedCount() <> _
    OSE_MIDI_INPUT_QUEUE_CAPACITY + 16 - acceptedMessages Then _
    test_Fail "queue drop count was not bounded correctly"

For messageIndex As Integer = 0 To acceptedMessages - 1
    If midiInputProtocol_Poll(message) = 0 OrElse _
        message.data1 <> (messageIndex Mod 128) OrElse _
        message.timestampMilliseconds <> CULng(messageIndex) Then
        test_Fail "queue FIFO order was not preserved"
    End If
Next
test_ExpectNoMessage()

Print "midi_input_protocol=ok"
Print "accepted="; acceptedMessages
Print "dropped="; midiInputProtocol_GetDroppedCount()
End 0

/' end of midi_input_protocol_smoke.bas '/
