/'
    Project: OpenSesh
    ---------------------------

    File: midi_output_sfx.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows sfxlib/WinMM implementation guarded by __FB_WIN32__.

    Module API: Implements midi_output.bi through the Windows sfxlib/WinMM backend.

    Purpose:

        Adapt the Windows sfxlib short-message MIDI commands to the editor's
        platform-neutral output interface.

    Responsibilities:

        - open and close one sfxlib MIDI output device
        - enumerate output names through the standard Windows capability API
        - reject malformed status and data bytes before calling sfxlib
        - provide an all-notes-off safety operation for transport shutdown

    Threading:

        The editor calls this module from its main thread. No callback or
        background output state is introduced here.

    This file intentionally does NOT contain:

        - MIDI input, recording, or WinMM callback declarations
        - MIDI-file parsing or event scheduling
        - omaGui widgets or recovered Midisoft behavior
'/

#lang "fb"

#include once "midi_output.bi"

#if defined(__FB_WIN32__)
#include once "midi_output_stop_internal.bi"
#include once "windows.bi"
#include once "win/mmsystem.bi"

' -------------------------------------------------------------------------
' Private output state
' -------------------------------------------------------------------------

Private Dim Shared midiOutput_Opened As Integer
Private Dim Shared midiOutput_DeviceIndex As Integer = -1

#If Defined(OSE_MIDI_OUTPUT_TESTING)
Declare Function midiOutput_TestBackendOpen CDecl _
    Alias "midiOutput_TestBackendOpen" (ByVal deviceIndex As Long) As Long
Declare Sub midiOutput_TestBackendClose CDecl _
    Alias "midiOutput_TestBackendClose" ()
Declare Function midiOutput_TestBackendSend CDecl _
    Alias "midiOutput_TestBackendSend" ( _
        ByVal statusByte As Long, _
        ByVal data1 As Long, _
        ByVal data2 As Long _
    ) As Long
#EndIf


' -------------------------------------------------------------------------
' Public output interface
' -------------------------------------------------------------------------

Function midiOutput_GetDeviceCount() As Integer
#If Defined(OSE_MIDI_OUTPUT_TESTING)
    Return 1
#Else
    Dim As UInteger deviceCount = midiOutGetNumDevs()
    If deviceCount > CUInt(2147483647) Then Return 2147483647
    Return CInt(deviceCount)
#EndIf
End Function


Function midiOutput_GetDeviceName( _
    ByVal deviceIndex As Integer _
) As String
    If deviceIndex < 0 OrElse _
        deviceIndex >= midiOutput_GetDeviceCount() Then Return ""

#If Defined(OSE_MIDI_OUTPUT_TESTING)
    Return "Simulated MIDI output"
#Else
    Dim As MIDIOUTCAPSA capabilities
    ' WinMM reports MMSYSERR_NOERROR as zero for a successful capability read.
    If midiOutGetDevCapsA(CULngInt(deviceIndex), @capabilities, _
        SizeOf(capabilities)) <> 0 Then Return ""
    Return capabilities.szPname
#EndIf
End Function

Function midiOutput_Open(ByVal deviceIndex As Integer) As Integer
    If deviceIndex < 0 Then Return 0
    If deviceIndex >= midiOutput_GetDeviceCount() Then Return 0

    If midiOutput_Opened <> 0 Then
        If midiOutput_DeviceIndex = deviceIndex Then Return -1
        midiOutput_Close()
    End If

    ' sfxlib returns zero when the requested MIDI output opens successfully.
#If Defined(OSE_MIDI_OUTPUT_TESTING)
    Dim As Long result = midiOutput_TestBackendOpen(CLng(deviceIndex))
#Else
    Dim As Long result = MIDI OPEN(deviceIndex)
#EndIf
    If result <> 0 Then Return 0

    midiOutput_DeviceIndex = deviceIndex
    midiOutput_Opened = -1
    Return -1
End Function


Sub midiOutput_Close()
    If midiOutput_Opened <> 0 Then
#If Defined(OSE_MIDI_OUTPUT_TESTING)
        midiOutput_TestBackendClose()
#Else
        MIDI CLOSE
#EndIf
    End If
    midiOutput_Opened = 0
    midiOutput_DeviceIndex = -1
End Sub


Function midiOutput_IsOpen() As Integer
    Return midiOutput_Opened
End Function


Function midiOutput_Send( _
    ByVal statusByte As Integer, _
    ByVal data1 As Integer, _
    ByVal data2 As Integer _
) As Integer
    If midiOutput_Opened = 0 Then Return 0
    If statusByte < &H80 OrElse statusByte > &HEF Then Return 0
    If data1 < 0 OrElse data1 > 127 Then Return 0
    If data2 < 0 OrElse data2 > 127 Then Return 0

    ' MIDI SEND always accepts three data arguments. Program-change and
    ' channel-pressure messages ignore the third byte at the receiver.
#If Defined(OSE_MIDI_OUTPUT_TESTING)
    If midiOutput_TestBackendSend(CLng(statusByte), CLng(data1), _
        CLng(data2)) <> 0 Then
#Else
    If MIDI SEND(statusByte, data1, data2) <> 0 Then
#EndIf
        midiOutput_Close()
        Return 0
    End If
    Return -1
End Function


Sub midiOutput_AllNotesOff()
    If midiOutput_Opened = 0 Then Exit Sub

    midiOutput_SendStopSequence()
End Sub

#endif

/' end of midi_output_sfx.bas '/
