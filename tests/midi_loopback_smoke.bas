/'
    Project: OpenSesh
    ---------------------------

    File: midi_loopback_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify the native output-to-input path through a selected physical or
        virtual MIDI endpoint on Windows or Linux.

    Responsibilities:

        - list the available input and output endpoint names
        - open explicitly selected endpoint indices
        - select explicit indices or discover ALSA Midi Through automatically
        - send every supported channel-message family through the OS backend
        - require the matching input sequence within a finite timeout

    This file intentionally does NOT contain:

        - a MIDI driver installer, module loader, or device configuration step
        - editor model mutation or omaGui widgets
'/

#lang "fb"

#include once "../midi_input.bi"
#include once "../midi_output.bi"

Private Sub test_CloseDevices()
    midiOutput_AllNotesOff()
    midiOutput_Close()
    midiInput_Close()
End Sub


Private Sub test_Fail(ByVal message As String)
    test_CloseDevices()
    Print "ERROR: "; message
    End 1
End Sub


Private Sub test_ListDevices()
    Dim As Integer inputCount = midiInput_GetDeviceCount()
    Dim As Integer outputCount = midiOutput_GetDeviceCount()

    Print "input_devices="; inputCount
    For deviceIndex As Integer = 0 To inputCount - 1
        Print "input_"; deviceIndex; "="; _
            midiInput_GetDeviceName(deviceIndex)
    Next
    Print "output_devices="; outputCount
    For deviceIndex As Integer = 0 To outputCount - 1
        Print "output_"; deviceIndex; "="; _
            midiOutput_GetDeviceName(deviceIndex)
    Next
End Sub


Private Function test_FindMidiThrough(ByVal inputEndpoint As Integer) As Integer
    Dim As Integer endpointCount
    If inputEndpoint <> 0 Then
        endpointCount = midiInput_GetDeviceCount()
    Else
        endpointCount = midiOutput_GetDeviceCount()
    End If

    For endpointIndex As Integer = 0 To endpointCount - 1
        Dim As String endpointName
        If inputEndpoint <> 0 Then
            endpointName = midiInput_GetDeviceName(endpointIndex)
        Else
            endpointName = midiOutput_GetDeviceName(endpointIndex)
        End If
        If InStr(LCase(endpointName), "midi through") > 0 Then _
            Return endpointIndex
    Next
    Return -1
End Function


Private Function test_ParseEndpointIndex( _
    ByVal argumentText As String, _
    ByVal inputEndpoint As Integer _
) As Integer
    Dim As String trimmedArgument = Trim(argumentText)
    If LCase(trimmedArgument) = "auto" Then _
        Return test_FindMidiThrough(inputEndpoint)
    If Len(trimmedArgument) <= 0 Then
        Return -1
    End If

    Dim As ULongInt parsedValue
    For characterIndex As Integer = 1 To Len(trimmedArgument)
        Dim As Integer characterValue = Asc( _
            Mid(trimmedArgument, characterIndex, 1))
        If characterValue < 48 OrElse characterValue > 57 Then
            Return -1
        End If
        parsedValue = parsedValue * 10ULL + CULngInt(characterValue - 48)
        If parsedValue > 2147483647ULL Then
            Return -1
        End If
    Next
    Return CInt(parsedValue)
End Function


Private Sub test_VerifyEndpointParser()
    If test_ParseEndpointIndex("0", -1) <> 0 OrElse _
        test_ParseEndpointIndex(" 42 ", 0) <> 42 OrElse _
        test_ParseEndpointIndex("2147483647", -1) <> 2147483647 Then _
        test_Fail "valid endpoint index parsing changed"

    Dim As String invalidArguments(0 To 5) = { _
        "", "-1", "+1", "1x", "1.0", "2147483648" _
    }
    For argumentIndex As Integer = 0 To UBound(invalidArguments)
        If test_ParseEndpointIndex(invalidArguments(argumentIndex), -1) <> _
            -1 Then test_Fail "invalid endpoint index was accepted"
    Next
End Sub


test_VerifyEndpointParser()
Dim As String inputArgument = Trim(Command(1))
Dim As String outputArgument = Trim(Command(2))
If inputArgument = "" OrElse outputArgument = "" Then
    test_ListDevices()
    Print "usage: midi_loopback_smoke.exe <input-index|auto> <output-index|auto>"
    End 2
End If

Dim As Integer inputIndex = test_ParseEndpointIndex(inputArgument, -1)
Dim As Integer outputIndex = test_ParseEndpointIndex(outputArgument, 0)
Dim As Integer inputCount = midiInput_GetDeviceCount()
Dim As Integer outputCount = midiOutput_GetDeviceCount()
If inputIndex < 0 OrElse inputIndex >= inputCount Then _
    test_Fail "input index is outside the enumerated range"
If outputIndex < 0 OrElse outputIndex >= outputCount Then _
    test_Fail "output index is outside the enumerated range"

If midiInput_Open(inputIndex) = 0 Then _
    test_Fail "selected MIDI input could not be opened"
If midiInput_GetOpenDeviceIndex() <> inputIndex OrElse _
    midiInput_IsOpen() = 0 OrElse midiInput_Open(inputIndex) = 0 Then _
    test_Fail "selected MIDI input did not remain idempotently open"
If midiOutput_Open(outputIndex) = 0 Then _
    test_Fail "selected MIDI output could not be opened"
If midiOutput_IsOpen() = 0 OrElse midiOutput_Open(outputIndex) = 0 Then _
    test_Fail "selected MIDI output did not remain idempotently open"
midiInput_ClearPending()

Const TEST_MESSAGE_COUNT As Integer = 7
Dim As Integer expectedStatus(0 To TEST_MESSAGE_COUNT - 1) = { _
    &H90, &HA0, &HB0, &HC0, &HD0, &HE0, &H80 _
}
Dim As Integer expectedData1(0 To TEST_MESSAGE_COUNT - 1) = { _
    60, 60, 7, 42, 77, 0, 60 _
}
Dim As Integer expectedData2(0 To TEST_MESSAGE_COUNT - 1) = { _
    100, 55, 99, 0, 0, 64, 0 _
}
For messageIndex As Integer = 0 To TEST_MESSAGE_COUNT - 1
    If midiOutput_Send(expectedStatus(messageIndex), _
        expectedData1(messageIndex), expectedData2(messageIndex)) = 0 Then _
        test_Fail "native MIDI output rejected a channel message"
Next

Dim As Integer receivedMessageCount
Dim As ULong previousTimestamp
Dim As Double startTime = Timer
Dim As OseMidiInputMessage message
Do
    ' The subtraction is followed by explicit midnight normalization below.
    ' Timer wraps at midnight.
    Dim As Double elapsed = Timer - startTime
    If elapsed < 0.0 Then
        elapsed += 86400.0
    End If
    If elapsed >= 2.0 Then
        Exit Do
    End If

    While midiInput_Poll(message) <> 0
        If message.messageKind = OSE_MIDI_INPUT_SHORT_MESSAGE AndAlso _
            receivedMessageCount < TEST_MESSAGE_COUNT AndAlso _
            message.status = expectedStatus(receivedMessageCount) AndAlso _
            message.data1 = expectedData1(receivedMessageCount) AndAlso _
            message.data2 = expectedData2(receivedMessageCount) Then
            If receivedMessageCount > 0 Then
                Dim As ULong timestampDelta = _
                    message.timestampMilliseconds - previousTimestamp
                If timestampDelta > &H7FFFFFFFUL Then _
                    test_Fail "input timestamps moved backwards"
            End If
            previousTimestamp = message.timestampMilliseconds
            receivedMessageCount += 1
        End If
    Wend

    If receivedMessageCount = TEST_MESSAGE_COUNT Then
        Exit Do
    End If
    Sleep 1, 1
Loop

If receivedMessageCount <> TEST_MESSAGE_COUNT Then _
    test_Fail "loopback did not return every channel message within two seconds"

Print "midi_loopback=ok"
Print "input="; inputIndex; " output="; outputIndex
Print "messages="; receivedMessageCount
Print "input_name="; midiInput_GetDeviceName(inputIndex)
Print "output_name="; midiOutput_GetDeviceName(outputIndex)
test_CloseDevices()
End 0

/' end of midi_loopback_smoke.bas '/
