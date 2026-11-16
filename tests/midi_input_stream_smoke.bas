/'
    Project: OpenMidiSesh
    File: tests/midi_input_stream_smoke.bas
    Targets: Windows/Linux test runners in the fb dialect.
    Module API: Test executable; failed assertions return a nonzero process status.
    Purpose: Exercise byte-stream input without Android or MIDI hardware.
    Responsibilities: Fragmentation, running status, SysEx and resynchronization.
    This file intentionally does NOT contain: open a device or synthesize audio.
'/
#lang "fb"
#include once "../src/midi_input_protocol.bi"
#include once "../src/midi_input_stream.bi"
Private Sub test_Require(ByVal condition As Integer, ByVal messageText As String)
    If condition <> 0 Then Exit Sub
    Print "FAIL: " + messageText
    End 1
End Sub
Private Sub test_Feed(ByVal bytes As String)
    midiInputStream_Process Cast(Const UByte Ptr, StrPtr(bytes)), Len(bytes), 1234
End Sub
Dim As OseMidiInputMessage message
midiInputProtocol_Initialize 3
midiInputStream_Reset()
test_Feed Chr(&H92, 60)
test_Require midiInputProtocol_Poll(message) = 0, "partial note was published"
test_Feed Chr(&HF8, 100, 61, 101)
test_Require midiInputProtocol_Poll(message) <> 0 AndAlso message.status = &H92 AndAlso _
    message.data1 = 60 AndAlso message.data2 = 100 AndAlso message.deviceIndex = 3, "fragmented note"
test_Require midiInputProtocol_Poll(message) <> 0 AndAlso message.data1 = 61, "running status"
test_Feed Chr(&HC2, 10, 11, &HF2, 1, 2, 64, 100)
test_Require midiInputProtocol_Poll(message) <> 0 AndAlso message.data1 = 10, "program change"
test_Require midiInputProtocol_Poll(message) <> 0 AndAlso message.data1 = 11, "one-byte running status"
test_Require midiInputProtocol_Poll(message) <> 0 AndAlso message.status = &HF2, "system common"
test_Require midiInputProtocol_Poll(message) = 0, "system status incorrectly retained"
test_Feed Chr(&HF0, 1, 2, &HF8)
test_Feed Chr(3, &HF7)
test_Require midiInputProtocol_Poll(message) <> 0 AndAlso message.payloadLength = 5 AndAlso _
    message.payload(3) = 3 AndAlso message.payload(4) = &HF7, "SysEx and real-time interleaving"
test_Feed Chr(&H90, 60)
midiInputStream_Reset()
test_Feed Chr(100)
test_Require midiInputProtocol_Poll(message) = 0, "reset retained partial note"
test_Feed Chr(&HF0, 1, &H80, 60, 0)
test_Require midiInputProtocol_Poll(message) <> 0 AndAlso message.status = &H80, "interrupted SysEx"
Print "midi_input_stream=ok"
End 0
/' end of tests/midi_input_stream_smoke.bas '/
