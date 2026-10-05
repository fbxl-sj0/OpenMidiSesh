/'
    Project: OpenSesh
    ---------------------------

    File: tests/midi_output_stop_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Module API: Test executable supplying midiOutput_Send as a simulated receiver
        for the production stop and default-setup helpers.

    Purpose:

        Verify transport stop and default setup against a simulated receiver.

    Responsibilities:

        - simulate receivers with and without All Sound Off support
        - verify held pedals are released on every channel
        - prove a failed send terminates the stop sequence
        - prevent a previous song's bank from surviving default program setup

    This file intentionally does NOT contain:

        - native device access or sound generation
        - MIDI file parsing
'/

#lang "fb"

#include once "../midi_output_stop_internal.bi"
#include once "../midi_output_setup_internal.bi"

Dim Shared test_Sustain(0 To 15) As Integer
Dim Shared test_Sostenuto(0 To 15) As Integer
Dim Shared test_Notes(0 To 15) As Integer
Dim Shared test_ReleaseTails(0 To 15) As Integer
Dim Shared test_SupportsSoundOff As Integer
Dim Shared test_SendCount As Integer
Dim Shared test_FailAtSend As Integer
Dim Shared test_DefaultSetupMode As Integer
Dim Shared test_BankMsb(0 To 15) As Integer
Dim Shared test_BankLsb(0 To 15) As Integer
Dim Shared test_ProgramSelected(0 To 15) As Integer

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub

Function midiOutput_Send( _
    ByVal statusByte As Integer, _
    ByVal data1 As Integer, _
    ByVal data2 As Integer _
) As Integer
    test_SendCount += 1
    If test_FailAtSend > 0 AndAlso test_SendCount >= test_FailAtSend Then
        Return 0
    End If
    Dim As Integer channelIndex = statusByte And 15
    If test_DefaultSetupMode <> 0 Then
        Select Case statusByte And &HF0
            Case &HB0
                Select Case data1
                    Case 0
                        test_BankMsb(channelIndex) = data2
                    Case 32
                        test_BankLsb(channelIndex) = data2
                    Case 7, 11
                        If data2 <> 127 Then
                            test_Fail "setup did not restore volume/expression"
                        End If
                    Case 10
                        If data2 <> 64 Then
                            test_Fail "setup did not center pan"
                        End If
                    Case 91
                        If data2 <> 40 Then
                            test_Fail "setup did not restore reverb"
                        End If
                    Case 93
                        If data2 <> 0 Then
                            test_Fail "setup did not clear chorus"
                        End If
                    Case Else
                        test_Fail "setup changed an unrelated controller"
                End Select
            Case &HC0
                If test_BankMsb(channelIndex) <> 0 OrElse _
                    test_BankLsb(channelIndex) <> 0 OrElse data1 <> 0 Then _
                    test_Fail "setup selected its program before clearing both banks"
                test_ProgramSelected(channelIndex) += 1
            Case &HE0
                If data1 <> 0 OrElse data2 <> 64 Then _
                    test_Fail "setup did not center pitch bend"
            Case Else
                test_Fail "setup emitted an invalid message"
        End Select
        Return -1
    End If
    If statusByte < &HB0 OrElse statusByte > &HBF OrElse data2 <> 0 Then _
        test_Fail "stop emitted an invalid channel-mode or pedal message"
    Select Case data1
        Case 64
            test_Sustain(channelIndex) = 0
        Case 66
            test_Sostenuto(channelIndex) = 0
        Case 123
            If test_Sustain(channelIndex) = 0 AndAlso _
                test_Sostenuto(channelIndex) = 0 Then test_Notes(channelIndex) = 0
        Case 120
            If test_SupportsSoundOff <> 0 Then
                test_Notes(channelIndex) = 0
                test_ReleaseTails(channelIndex) = 0
            End If
        Case Else
            test_Fail "stop changed an unrelated controller"
    End Select
    Return -1
End Function

For receiverMode As Integer = 0 To 1
    test_SupportsSoundOff = receiverMode
    For channelIndex As Integer = 0 To 15
        test_Sustain(channelIndex) = -1
        test_Sostenuto(channelIndex) = -1
        test_Notes(channelIndex) = 4
        test_ReleaseTails(channelIndex) = 2
    Next
    midiOutput_SendStopSequence()
    For channelIndex As Integer = 0 To 15
        If test_Sustain(channelIndex) <> 0 OrElse _
            test_Sostenuto(channelIndex) <> 0 OrElse test_Notes(channelIndex) <> 0 Then _
            test_Fail "a held pedal or note survived transport stop"
        If receiverMode <> 0 AndAlso test_ReleaseTails(channelIndex) <> 0 Then _
            test_Fail "a receiver with All Sound Off retained release tails"
    Next
Next

For failurePosition As Integer = 1 To 64
    test_SendCount = 0
    test_FailAtSend = failurePosition
    midiOutput_SendStopSequence()
    If test_SendCount <> failurePosition Then _
        test_Fail "stop continued sending after the endpoint failed"
Next

Print "midi_output_stop=ok channels=16 receiver_modes=2 failure_positions=64"

test_DefaultSetupMode = -1
test_SendCount = 0
test_FailAtSend = 0
For channelIndex As Integer = 0 To 15
    test_BankMsb(channelIndex) = 17
    test_BankLsb(channelIndex) = 29
    test_ProgramSelected(channelIndex) = 0
Next
midiOutput_SendDefaultSetupSequence()
If test_SendCount <> 144 Then
    test_Fail "setup emitted the wrong message count"
End If
For channelIndex As Integer = 0 To 15
    If test_ProgramSelected(channelIndex) <> 1 Then _
        test_Fail "setup did not select a default program on every channel"
Next
For failurePosition As Integer = 1 To 144
    test_SendCount = 0
    test_FailAtSend = failurePosition
    midiOutput_SendDefaultSetupSequence()
    If test_SendCount <> failurePosition Then _
        test_Fail "setup continued sending after the endpoint failed"
Next
Print "midi_output_setup=ok channels=16 failure_positions=144"
End 0

/' end of tests/midi_output_stop_smoke.bas '/
