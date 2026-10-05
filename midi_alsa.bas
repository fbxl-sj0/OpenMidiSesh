/'
    Project: OpenSesh
    ---------------------------

    File: midi_alsa.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Linux ALSA implementation guarded by __FB_LINUX__.

    Module API: Implements midi_input.bi and midi_output.bi through one Linux ALSA backend.

    Purpose:

        Implement MIDI input and output on Linux through ALSA Sequencer.

    Responsibilities:

        - enumerate bounded MIDI 1.0 source and destination ports
        - own one nonblocking input subscription and one output subscription
        - translate ALSA events to and from bounded MIDI byte messages
        - feed input through the shared validated protocol queue
        - close every ALSA port, parser, subscription, and client explicitly

    External API behavior:

        ALSA names ports from the application's perspective. A source port is
        readable and can be subscribed from; a destination port is writable
        and can be subscribed to. The capability directions therefore look
        reversed when creating this application's local input and output ports.

        snd_seq_event_t is a stable ALSA public ABI record. Fixed-width fields
        and compile-time size assertions below protect the layout used by
        snd_midi_event_encode and snd_seq_event_output_direct.

    Ownership:

        ALSA allocates input events returned by snd_seq_event_input; this file
        releases each with snd_seq_free_event. Parser and sequencer handles are
        released on every failed open and by the idempotent close operations.

    Threading:

        The editor polls this nonblocking backend on its main thread. ALSA does
        not call application code from a worker callback, so protocol queue
        publication and consumption remain serialized on Linux.

    This file intentionally does NOT contain:

        - Windows WinMM or sfxlib operations
        - recording timing, MIDI-file parsing, or transport scheduling
        - omaGui widgets or application dialog policy
'/

#lang "fb"

#include once "midi_input.bi"
#include once "midi_input_protocol.bi"
#include once "midi_output.bi"

#if defined(__FB_LINUX__)

#include once "midi_output_stop_internal.bi"

#inclib "asound"

' -------------------------------------------------------------------------
' ALSA public constants and ABI records
' -------------------------------------------------------------------------

Const OSE_ALSA_OPEN_OUTPUT As Long = 1
Const OSE_ALSA_OPEN_INPUT As Long = 2
Const OSE_ALSA_OPEN_DUPLEX As Long = 3
Const OSE_ALSA_NONBLOCK As Long = 1

Const OSE_ALSA_PORT_CAP_READ As ULong = 1 Shl 0
Const OSE_ALSA_PORT_CAP_WRITE As ULong = 1 Shl 1
Const OSE_ALSA_PORT_CAP_SUBS_READ As ULong = 1 Shl 5
Const OSE_ALSA_PORT_CAP_SUBS_WRITE As ULong = 1 Shl 6
Const OSE_ALSA_PORT_TYPE_MIDI_GENERIC As ULong = 1 Shl 1
Const OSE_ALSA_PORT_TYPE_APPLICATION As ULong = 1 Shl 20

Const OSE_ALSA_ADDRESS_UNKNOWN As UByte = 253
Const OSE_ALSA_ADDRESS_SUBSCRIBERS As UByte = 254
Const OSE_ALSA_QUEUE_DIRECT As UByte = 253
Const OSE_ALSA_CLOCK_MONOTONIC As Long = 1

Const OSE_ALSA_ENDPOINT_INPUT As Integer = 1
Const OSE_ALSA_ENDPOINT_OUTPUT As Integer = 2
Const OSE_ALSA_MAX_ENDPOINTS As Integer = 1024
Const OSE_ALSA_MAX_PUMP_EVENTS As Integer = _
    OSE_MIDI_INPUT_QUEUE_CAPACITY * 2

Type OseAlsaSeqAddress
    As UByte clientId
    As UByte portId
End Type

Type OseAlsaSeqRealTime
    As ULong secondsValue
    As ULong nanosecondsValue
End Type

Union OseAlsaSeqTimestamp
    As ULong tickValue
    As OseAlsaSeqRealTime realValue
End Union

Type OseAlsaSeqNote
    As UByte channelValue
    As UByte noteValue
    As UByte velocityValue
    As UByte offVelocityValue
    As ULong durationValue
End Type

Type OseAlsaSeqControl
    As UByte channelValue
    As UByte reserved(0 To 2)
    As ULong parameterValue
    As Long value
End Type

Union OseAlsaSeqEventData
    As OseAlsaSeqNote noteValue
    As OseAlsaSeqControl controlValue
    As UByte rawBytes(0 To 11)
End Union

Type OseAlsaSeqEvent
    As UByte eventType
    As UByte flags
    As UByte tag
    As UByte queueId
    As OseAlsaSeqTimestamp timestampValue
    As OseAlsaSeqAddress source
    As OseAlsaSeqAddress destination
    As OseAlsaSeqEventData dataValue
End Type

Type OseAlsaTimespec
    ' Linux time_t and long both follow the target's native integer width.
    As Integer secondsValue
    As Integer nanosecondsValue
End Type

Type OseAlsaMidiEndpoint
    As Long clientId
    As Long portId
    As String displayName
End Type

#assert SizeOf(OseAlsaSeqTimestamp) = 8
#assert SizeOf(OseAlsaSeqEventData) = 12
#assert SizeOf(OseAlsaSeqEvent) = 28
#assert SizeOf(OseAlsaTimespec) = SizeOf(Integer) * 2

' -------------------------------------------------------------------------
' Narrow ALSA and libc declarations
' -------------------------------------------------------------------------

Extern "C"
    Declare Function snd_seq_open CDecl Alias "snd_seq_open"( _
        ByVal sequencerHandle As Any Ptr Ptr, _
        ByVal deviceName As ZString Ptr, _
        ByVal streamFlags As Long, _
        ByVal modeFlags As Long _
    ) As Long
    Declare Function snd_seq_close CDecl Alias "snd_seq_close"( _
        ByVal sequencerHandle As Any Ptr _
    ) As Long
    Declare Function snd_seq_client_id CDecl Alias "snd_seq_client_id"( _
        ByVal sequencerHandle As Any Ptr _
    ) As Long
    Declare Function snd_seq_set_client_name CDecl _
        Alias "snd_seq_set_client_name"( _
        ByVal sequencerHandle As Any Ptr, _
        ByVal clientName As ZString Ptr _
    ) As Long
    Declare Function snd_seq_create_simple_port CDecl _
        Alias "snd_seq_create_simple_port"( _
        ByVal sequencerHandle As Any Ptr, _
        ByVal portName As ZString Ptr, _
        ByVal capabilities As ULong, _
        ByVal portType As ULong _
    ) As Long
    Declare Function snd_seq_delete_simple_port CDecl _
        Alias "snd_seq_delete_simple_port"( _
        ByVal sequencerHandle As Any Ptr, _
        ByVal localPort As Long _
    ) As Long
    Declare Function snd_seq_connect_from CDecl _
        Alias "snd_seq_connect_from"( _
        ByVal sequencerHandle As Any Ptr, _
        ByVal localPort As Long, _
        ByVal sourceClient As Long, _
        ByVal sourcePort As Long _
    ) As Long
    Declare Function snd_seq_connect_to CDecl Alias "snd_seq_connect_to"( _
        ByVal sequencerHandle As Any Ptr, _
        ByVal localPort As Long, _
        ByVal destinationClient As Long, _
        ByVal destinationPort As Long _
    ) As Long
    Declare Function snd_seq_disconnect_from CDecl _
        Alias "snd_seq_disconnect_from"( _
        ByVal sequencerHandle As Any Ptr, _
        ByVal localPort As Long, _
        ByVal sourceClient As Long, _
        ByVal sourcePort As Long _
    ) As Long
    Declare Function snd_seq_disconnect_to CDecl _
        Alias "snd_seq_disconnect_to"( _
        ByVal sequencerHandle As Any Ptr, _
        ByVal localPort As Long, _
        ByVal destinationClient As Long, _
        ByVal destinationPort As Long _
    ) As Long

    Declare Function snd_seq_client_info_malloc CDecl _
        Alias "snd_seq_client_info_malloc"( _
        ByVal clientInfo As Any Ptr Ptr _
    ) As Long
    Declare Sub snd_seq_client_info_free CDecl _
        Alias "snd_seq_client_info_free"( _
        ByVal clientInfo As Any Ptr _
    )
    Declare Sub snd_seq_client_info_set_client CDecl _
        Alias "snd_seq_client_info_set_client"( _
        ByVal clientInfo As Any Ptr, _
        ByVal clientId As Long _
    )
    Declare Function snd_seq_client_info_get_client CDecl _
        Alias "snd_seq_client_info_get_client"( _
        ByVal clientInfo As Any Ptr _
    ) As Long
    Declare Function snd_seq_client_info_get_name CDecl _
        Alias "snd_seq_client_info_get_name"( _
        ByVal clientInfo As Any Ptr _
    ) As ZString Ptr
    Declare Function snd_seq_query_next_client CDecl _
        Alias "snd_seq_query_next_client"( _
        ByVal sequencerHandle As Any Ptr, _
        ByVal clientInfo As Any Ptr _
    ) As Long

    Declare Function snd_seq_port_info_malloc CDecl _
        Alias "snd_seq_port_info_malloc"( _
        ByVal portInfo As Any Ptr Ptr _
    ) As Long
    Declare Sub snd_seq_port_info_free CDecl _
        Alias "snd_seq_port_info_free"( _
        ByVal portInfo As Any Ptr _
    )
    Declare Sub snd_seq_port_info_set_client CDecl _
        Alias "snd_seq_port_info_set_client"( _
        ByVal portInfo As Any Ptr, _
        ByVal clientId As Long _
    )
    Declare Sub snd_seq_port_info_set_port CDecl _
        Alias "snd_seq_port_info_set_port"( _
        ByVal portInfo As Any Ptr, _
        ByVal portId As Long _
    )
    Declare Function snd_seq_port_info_get_port CDecl _
        Alias "snd_seq_port_info_get_port"( _
        ByVal portInfo As Any Ptr _
    ) As Long
    Declare Function snd_seq_port_info_get_name CDecl _
        Alias "snd_seq_port_info_get_name"( _
        ByVal portInfo As Any Ptr _
    ) As ZString Ptr
    Declare Function snd_seq_port_info_get_capability CDecl _
        Alias "snd_seq_port_info_get_capability"( _
        ByVal portInfo As Any Ptr _
    ) As ULong
    Declare Function snd_seq_port_info_get_type CDecl _
        Alias "snd_seq_port_info_get_type"( _
        ByVal portInfo As Any Ptr _
    ) As ULong
    Declare Function snd_seq_query_next_port CDecl _
        Alias "snd_seq_query_next_port"( _
        ByVal sequencerHandle As Any Ptr, _
        ByVal portInfo As Any Ptr _
    ) As Long

    Declare Function snd_seq_event_output_direct CDecl _
        Alias "snd_seq_event_output_direct"( _
        ByVal sequencerHandle As Any Ptr, _
        ByVal midiEvent As OseAlsaSeqEvent Ptr _
    ) As Long
    Declare Function snd_seq_event_input CDecl Alias "snd_seq_event_input"( _
        ByVal sequencerHandle As Any Ptr, _
        ByVal midiEvent As Any Ptr Ptr _
    ) As Long
    Declare Function snd_seq_free_event CDecl Alias "snd_seq_free_event"( _
        ByVal midiEvent As Any Ptr _
    ) As Long
    Declare Function snd_seq_drop_input CDecl Alias "snd_seq_drop_input"( _
        ByVal sequencerHandle As Any Ptr _
    ) As Long
    Declare Function snd_seq_drop_input_buffer CDecl _
        Alias "snd_seq_drop_input_buffer"( _
        ByVal sequencerHandle As Any Ptr _
    ) As Long

    Declare Function snd_midi_event_new CDecl Alias "snd_midi_event_new"( _
        ByVal bufferSize As UInteger, _
        ByVal parserHandle As Any Ptr Ptr _
    ) As Long
    Declare Sub snd_midi_event_free CDecl Alias "snd_midi_event_free"( _
        ByVal parserHandle As Any Ptr _
    )
    Declare Sub snd_midi_event_reset_encode CDecl _
        Alias "snd_midi_event_reset_encode"( _
        ByVal parserHandle As Any Ptr _
    )
    Declare Sub snd_midi_event_reset_decode CDecl _
        Alias "snd_midi_event_reset_decode"( _
        ByVal parserHandle As Any Ptr _
    )
    Declare Sub snd_midi_event_no_status CDecl _
        Alias "snd_midi_event_no_status"( _
        ByVal parserHandle As Any Ptr, _
        ByVal noRunningStatus As Long _
    )
    Declare Function snd_midi_event_encode CDecl _
        Alias "snd_midi_event_encode"( _
        ByVal parserHandle As Any Ptr, _
        ByVal midiBytes As UByte Ptr, _
        ByVal byteCount As Integer, _
        ByVal midiEvent As OseAlsaSeqEvent Ptr _
    ) As Integer
    Declare Function snd_midi_event_decode CDecl _
        Alias "snd_midi_event_decode"( _
        ByVal parserHandle As Any Ptr, _
        ByVal midiBytes As UByte Ptr, _
        ByVal byteCapacity As Integer, _
        ByVal midiEvent As Any Ptr _
    ) As Integer

    Declare Function clock_gettime CDecl Alias "clock_gettime"( _
        ByVal clockId As Long, _
        ByVal timeValue As OseAlsaTimespec Ptr _
    ) As Long
End Extern

' -------------------------------------------------------------------------
' Shared ALSA endpoint and device state
' -------------------------------------------------------------------------

Private Dim Shared midiAlsa_Endpoints( _
    0 To OSE_ALSA_MAX_ENDPOINTS - 1 _
) As OseAlsaMidiEndpoint
Private Dim Shared midiAlsa_EndpointCount As Integer

Private Dim Shared midiAlsa_InputHandle As Any Ptr
Private Dim Shared midiAlsa_InputParser As Any Ptr
Private Dim Shared midiAlsa_InputPort As Long = -1
Private Dim Shared midiAlsa_InputTargetClient As Long = -1
Private Dim Shared midiAlsa_InputTargetPort As Long = -1
Private Dim Shared midiAlsa_InputDeviceIndex As Integer = -1
Private Dim Shared midiAlsa_InputOpened As Integer

Private Dim Shared midiAlsa_OutputHandle As Any Ptr
Private Dim Shared midiAlsa_OutputParser As Any Ptr
Private Dim Shared midiAlsa_OutputPort As Long = -1
Private Dim Shared midiAlsa_OutputTargetClient As Long = -1
Private Dim Shared midiAlsa_OutputTargetPort As Long = -1
Private Dim Shared midiAlsa_OutputOpened As Integer

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
' Endpoint enumeration and timestamp helpers
' -------------------------------------------------------------------------

Private Function midiAlsa_ReadName(ByVal namePointer As ZString Ptr) As String
    If namePointer = 0 Then Return ""
    Return *namePointer
End Function


Private Function midiAlsa_EndpointDisplayName( _
    ByVal clientName As String, _
    ByVal portName As String, _
    ByVal clientId As Long, _
    ByVal portId As Long _
) As String
    Dim As String safeClientName = Trim(clientName)
    Dim As String safePortName = Trim(portName)
    If safeClientName = "" Then _
        safeClientName = "ALSA client " + LTrim(Str(clientId))
    If safePortName = "" Then _
        safePortName = "port " + LTrim(Str(portId))
    Return safeClientName + " / " + safePortName + " [" + _
        LTrim(Str(clientId)) + ":" + LTrim(Str(portId)) + "]"
End Function


Private Function midiAlsa_RefreshEndpoints( _
    ByVal endpointDirection As Integer _
) As Integer
    midiAlsa_EndpointCount = 0
    If endpointDirection <> OSE_ALSA_ENDPOINT_INPUT AndAlso _
        endpointDirection <> OSE_ALSA_ENDPOINT_OUTPUT Then Return 0

    Dim As Any Ptr scanHandle
    Dim As ZString * 8 defaultDevice = "default"
    If snd_seq_open(@scanHandle, @defaultDevice, _
        OSE_ALSA_OPEN_DUPLEX, OSE_ALSA_NONBLOCK) < 0 OrElse _
        scanHandle = 0 Then Return 0

    Dim As Any Ptr clientInfo
    If snd_seq_client_info_malloc(@clientInfo) < 0 OrElse _
        clientInfo = 0 Then
        snd_seq_close scanHandle
        Return 0
    End If

    Dim As Any Ptr portInfo
    If snd_seq_port_info_malloc(@portInfo) < 0 OrElse portInfo = 0 Then
        snd_seq_client_info_free clientInfo
        snd_seq_close scanHandle
        Return 0
    End If

    Dim As Long scanClientId = snd_seq_client_id(scanHandle)
    Dim As ULong requiredCapabilities
    If endpointDirection = OSE_ALSA_ENDPOINT_INPUT Then
        requiredCapabilities = OSE_ALSA_PORT_CAP_READ Or _
            OSE_ALSA_PORT_CAP_SUBS_READ
    Else
        requiredCapabilities = OSE_ALSA_PORT_CAP_WRITE Or _
            OSE_ALSA_PORT_CAP_SUBS_WRITE
    End If

    snd_seq_client_info_set_client clientInfo, -1
    Do While snd_seq_query_next_client(scanHandle, clientInfo) >= 0
        Dim As Long clientId = snd_seq_client_info_get_client(clientInfo)
        If clientId = scanClientId Then Continue Do

        Dim As String clientName = midiAlsa_ReadName( _
            snd_seq_client_info_get_name(clientInfo))
        snd_seq_port_info_set_client portInfo, clientId
        snd_seq_port_info_set_port portInfo, -1
        Do While snd_seq_query_next_port(scanHandle, portInfo) >= 0
            Dim As ULong capabilities = _
                snd_seq_port_info_get_capability(portInfo)
            Dim As ULong portType = snd_seq_port_info_get_type(portInfo)
            If (capabilities And requiredCapabilities) <> _
                requiredCapabilities Then Continue Do
            If (portType And OSE_ALSA_PORT_TYPE_MIDI_GENERIC) = 0 Then _
                Continue Do
            If midiAlsa_EndpointCount >= OSE_ALSA_MAX_ENDPOINTS Then Exit Do

            Dim As Long portId = snd_seq_port_info_get_port(portInfo)
            Dim As String portName = midiAlsa_ReadName( _
                snd_seq_port_info_get_name(portInfo))
            With midiAlsa_Endpoints(midiAlsa_EndpointCount)
                .clientId = clientId
                .portId = portId
                .displayName = midiAlsa_EndpointDisplayName( _
                    clientName, portName, clientId, portId)
            End With
            midiAlsa_EndpointCount += 1
        Loop
        If midiAlsa_EndpointCount >= OSE_ALSA_MAX_ENDPOINTS Then Exit Do
    Loop

    snd_seq_port_info_free portInfo
    snd_seq_client_info_free clientInfo
    snd_seq_close scanHandle
    Return midiAlsa_EndpointCount
End Function


Private Function midiAlsa_TimestampMilliseconds() As ULong
    Dim As OseAlsaTimespec timeValue
    If clock_gettime(OSE_ALSA_CLOCK_MONOTONIC, @timeValue) = 0 AndAlso _
        timeValue.secondsValue >= 0 AndAlso _
        timeValue.nanosecondsValue >= 0 Then
        Dim As ULongInt milliseconds = _
            CULngInt(timeValue.secondsValue) * 1000ULL + _
            CULngInt(timeValue.nanosecondsValue) \ 1000000ULL
        Return CULng(milliseconds And &HFFFFFFFFULL)
    End If

    ' Timer is only a fallback for an unexpected libc clock failure. The
    ' normal monotonic path has the same unsigned 32-bit wrap contract as
    ' WinMM, which the recording layer already handles.
    Dim As ULongInt fallbackMilliseconds = CULngInt(Timer * 1000.0)
    Return CULng(fallbackMilliseconds And &HFFFFFFFFULL)
End Function

' -------------------------------------------------------------------------
' ALSA MIDI input backend
' -------------------------------------------------------------------------

Function midiInput_GetDeviceCount() As Integer
    Return midiAlsa_RefreshEndpoints(OSE_ALSA_ENDPOINT_INPUT)
End Function


Function midiInput_GetDeviceName(ByVal deviceIndex As Integer) As String
    If midiAlsa_RefreshEndpoints(OSE_ALSA_ENDPOINT_INPUT) <= 0 OrElse _
        deviceIndex < 0 OrElse deviceIndex >= midiAlsa_EndpointCount Then _
        Return ""
    Return midiAlsa_Endpoints(deviceIndex).displayName
End Function


Function midiInput_Open(ByVal deviceIndex As Integer) As Integer
    If midiAlsa_RefreshEndpoints(OSE_ALSA_ENDPOINT_INPUT) <= 0 OrElse _
        deviceIndex < 0 OrElse deviceIndex >= midiAlsa_EndpointCount Then _
        Return 0

    Dim As Long targetClient = midiAlsa_Endpoints(deviceIndex).clientId
    Dim As Long targetPort = midiAlsa_Endpoints(deviceIndex).portId
    If midiAlsa_InputOpened <> 0 AndAlso _
        midiAlsa_InputTargetClient = targetClient AndAlso _
        midiAlsa_InputTargetPort = targetPort Then Return -1
    midiInput_Close()

    Dim As Any Ptr openedHandle
    Dim As ZString * 8 defaultDevice = "default"
    If snd_seq_open(@openedHandle, @defaultDevice, _
        OSE_ALSA_OPEN_INPUT, OSE_ALSA_NONBLOCK) < 0 OrElse _
        openedHandle = 0 Then Return 0

    Dim As ZString * 32 clientName = "OpenSesh Input"
    Dim As ZString * 16 portName = "MIDI Input"
    If snd_seq_set_client_name(openedHandle, @clientName) < 0 Then
        snd_seq_close openedHandle
        Return 0
    End If

    Dim As Long localPort = snd_seq_create_simple_port( _
        openedHandle, @portName, _
        OSE_ALSA_PORT_CAP_WRITE Or OSE_ALSA_PORT_CAP_SUBS_WRITE, _
        OSE_ALSA_PORT_TYPE_MIDI_GENERIC Or OSE_ALSA_PORT_TYPE_APPLICATION)
    If localPort < 0 Then
        snd_seq_close openedHandle
        Return 0
    End If

    Dim As Any Ptr parserHandle
    If snd_midi_event_new(OSE_MIDI_INPUT_MAX_LONG_BYTES, _
        @parserHandle) < 0 OrElse parserHandle = 0 Then
        snd_seq_delete_simple_port openedHandle, localPort
        snd_seq_close openedHandle
        Return 0
    End If
    snd_midi_event_no_status parserHandle, 1

    If snd_seq_connect_from(openedHandle, localPort, _
        targetClient, targetPort) < 0 Then
        snd_midi_event_free parserHandle
        snd_seq_delete_simple_port openedHandle, localPort
        snd_seq_close openedHandle
        Return 0
    End If

    midiAlsa_InputHandle = openedHandle
    midiAlsa_InputParser = parserHandle
    midiAlsa_InputPort = localPort
    midiAlsa_InputTargetClient = targetClient
    midiAlsa_InputTargetPort = targetPort
    midiAlsa_InputDeviceIndex = deviceIndex
    midiAlsa_InputOpened = -1
    midiInputProtocol_Initialize deviceIndex
    midiInputProtocol_SetClosing 0
    Return -1
End Function


Sub midiInput_Close()
    midiInputProtocol_SetClosing -1
    If midiAlsa_InputHandle <> 0 Then
        If midiAlsa_InputPort >= 0 AndAlso _
            midiAlsa_InputTargetClient >= 0 AndAlso _
            midiAlsa_InputTargetPort >= 0 Then
            snd_seq_disconnect_from midiAlsa_InputHandle, _
                midiAlsa_InputPort, midiAlsa_InputTargetClient, _
                midiAlsa_InputTargetPort
        End If
        If midiAlsa_InputPort >= 0 Then _
            snd_seq_delete_simple_port midiAlsa_InputHandle, midiAlsa_InputPort
    End If
    If midiAlsa_InputParser <> 0 Then _
        snd_midi_event_free midiAlsa_InputParser
    If midiAlsa_InputHandle <> 0 Then snd_seq_close midiAlsa_InputHandle

    midiAlsa_InputHandle = 0
    midiAlsa_InputParser = 0
    midiAlsa_InputPort = -1
    midiAlsa_InputTargetClient = -1
    midiAlsa_InputTargetPort = -1
    midiAlsa_InputDeviceIndex = -1
    midiAlsa_InputOpened = 0
    midiInputProtocol_Initialize -1
End Sub


Function midiInput_IsOpen() As Integer
    Return midiAlsa_InputOpened
End Function


Function midiInput_GetOpenDeviceIndex() As Integer
    Return midiAlsa_InputDeviceIndex
End Function


Sub midiInput_ClearPending()
    If midiAlsa_InputHandle <> 0 Then
        snd_seq_drop_input midiAlsa_InputHandle
        snd_seq_drop_input_buffer midiAlsa_InputHandle
    End If
    If midiAlsa_InputParser <> 0 Then _
        snd_midi_event_reset_decode midiAlsa_InputParser
    midiInputProtocol_ClearPending()
End Sub


Function midiInput_GetClockMilliseconds( _
    ByRef timestampMilliseconds As ULong _
) As Integer
    timestampMilliseconds = 0
    If midiAlsa_InputOpened = 0 Then Return 0
    timestampMilliseconds = midiAlsa_TimestampMilliseconds()
    Return -1
End Function


Private Sub midiAlsa_PumpInput()
    If midiAlsa_InputOpened = 0 OrElse midiAlsa_InputHandle = 0 OrElse _
        midiAlsa_InputParser = 0 Then Exit Sub

    For eventIndex As Integer = 0 To OSE_ALSA_MAX_PUMP_EVENTS - 1
        Dim As Any Ptr receivedEvent
        Dim As Long inputResult = snd_seq_event_input( _
            midiAlsa_InputHandle, @receivedEvent)
        If inputResult < 0 OrElse receivedEvent = 0 Then Exit For

        Dim As UByte midiBytes(0 To OSE_MIDI_INPUT_MAX_LONG_BYTES - 1)
        snd_midi_event_reset_decode midiAlsa_InputParser
        Dim As Integer decodedLength = snd_midi_event_decode( _
            midiAlsa_InputParser, @midiBytes(0), _
            OSE_MIDI_INPUT_MAX_LONG_BYTES, receivedEvent)
        snd_seq_free_event receivedEvent
        If decodedLength <= 0 OrElse _
            decodedLength > OSE_MIDI_INPUT_MAX_LONG_BYTES Then Continue For

        Dim As ULong timestamp = midiAlsa_TimestampMilliseconds()
        If decodedLength > 3 OrElse midiBytes(0) = &HF0 OrElse _
            midiBytes(0) = &HF7 Then
            midiInputProtocol_ProcessLongChunk( _
                @midiBytes(0), decodedLength, timestamp)
        Else
            Dim As Integer data1Value
            Dim As Integer data2Value
            If decodedLength >= 2 Then data1Value = midiBytes(1)
            If decodedLength >= 3 Then data2Value = midiBytes(2)
            midiInputProtocol_ProcessShort( _
                midiBytes(0), data1Value, data2Value, timestamp)
        End If
    Next
End Sub


Function midiInput_Poll(ByRef message As OseMidiInputMessage) As Integer
    If midiInputProtocol_Poll(message) <> 0 Then Return -1
    midiAlsa_PumpInput()
    Return midiInputProtocol_Poll(message)
End Function


Function midiInput_GetDroppedCount() As ULongInt
    Return midiInputProtocol_GetDroppedCount()
End Function

' -------------------------------------------------------------------------
' ALSA MIDI output backend
' -------------------------------------------------------------------------

Function midiOutput_GetDeviceCount() As Integer
#If Defined(OSE_MIDI_OUTPUT_TESTING)
    Return 1
#Else
    Return midiAlsa_RefreshEndpoints(OSE_ALSA_ENDPOINT_OUTPUT)
#EndIf
End Function


Function midiOutput_GetDeviceName(ByVal deviceIndex As Integer) As String
#If Defined(OSE_MIDI_OUTPUT_TESTING)
    If deviceIndex = 0 Then Return "Simulated MIDI output"
    Return ""
#Else
    If midiAlsa_RefreshEndpoints(OSE_ALSA_ENDPOINT_OUTPUT) <= 0 OrElse _
        deviceIndex < 0 OrElse deviceIndex >= midiAlsa_EndpointCount Then _
        Return ""
    Return midiAlsa_Endpoints(deviceIndex).displayName
#EndIf
End Function


Function midiOutput_Open(ByVal deviceIndex As Integer) As Integer
#If Defined(OSE_MIDI_OUTPUT_TESTING)
    If deviceIndex <> 0 Then Return 0
    If midiAlsa_OutputOpened <> 0 Then Return -1
    If midiOutput_TestBackendOpen(CLng(deviceIndex)) <> 0 Then Return 0
    midiAlsa_OutputOpened = -1
    Return -1
#Else
    If midiAlsa_RefreshEndpoints(OSE_ALSA_ENDPOINT_OUTPUT) <= 0 OrElse _
        deviceIndex < 0 OrElse deviceIndex >= midiAlsa_EndpointCount Then _
        Return 0

    Dim As Long targetClient = midiAlsa_Endpoints(deviceIndex).clientId
    Dim As Long targetPort = midiAlsa_Endpoints(deviceIndex).portId
    If midiAlsa_OutputOpened <> 0 AndAlso _
        midiAlsa_OutputTargetClient = targetClient AndAlso _
        midiAlsa_OutputTargetPort = targetPort Then Return -1
    midiOutput_Close()

    Dim As Any Ptr openedHandle
    Dim As ZString * 8 defaultDevice = "default"
    If snd_seq_open(@openedHandle, @defaultDevice, _
        OSE_ALSA_OPEN_OUTPUT, OSE_ALSA_NONBLOCK) < 0 OrElse _
        openedHandle = 0 Then Return 0

    Dim As ZString * 32 clientName = "OpenSesh Output"
    Dim As ZString * 16 portName = "MIDI Output"
    If snd_seq_set_client_name(openedHandle, @clientName) < 0 Then
        snd_seq_close openedHandle
        Return 0
    End If

    Dim As Long localPort = snd_seq_create_simple_port( _
        openedHandle, @portName, _
        OSE_ALSA_PORT_CAP_READ Or OSE_ALSA_PORT_CAP_SUBS_READ, _
        OSE_ALSA_PORT_TYPE_MIDI_GENERIC Or OSE_ALSA_PORT_TYPE_APPLICATION)
    If localPort < 0 Then
        snd_seq_close openedHandle
        Return 0
    End If

    Dim As Any Ptr parserHandle
    If snd_midi_event_new(16, @parserHandle) < 0 OrElse _
        parserHandle = 0 Then
        snd_seq_delete_simple_port openedHandle, localPort
        snd_seq_close openedHandle
        Return 0
    End If
    snd_midi_event_no_status parserHandle, 1

    If snd_seq_connect_to(openedHandle, localPort, _
        targetClient, targetPort) < 0 Then
        snd_midi_event_free parserHandle
        snd_seq_delete_simple_port openedHandle, localPort
        snd_seq_close openedHandle
        Return 0
    End If

    midiAlsa_OutputHandle = openedHandle
    midiAlsa_OutputParser = parserHandle
    midiAlsa_OutputPort = localPort
    midiAlsa_OutputTargetClient = targetClient
    midiAlsa_OutputTargetPort = targetPort
    midiAlsa_OutputOpened = -1
    Return -1
#EndIf
End Function


Sub midiOutput_Close()
#If Defined(OSE_MIDI_OUTPUT_TESTING)
    If midiAlsa_OutputOpened <> 0 Then midiOutput_TestBackendClose()
#Else
    If midiAlsa_OutputHandle <> 0 Then
        If midiAlsa_OutputPort >= 0 AndAlso _
            midiAlsa_OutputTargetClient >= 0 AndAlso _
            midiAlsa_OutputTargetPort >= 0 Then
            snd_seq_disconnect_to midiAlsa_OutputHandle, _
                midiAlsa_OutputPort, midiAlsa_OutputTargetClient, _
                midiAlsa_OutputTargetPort
        End If
        If midiAlsa_OutputPort >= 0 Then _
            snd_seq_delete_simple_port midiAlsa_OutputHandle, _
                midiAlsa_OutputPort
    End If
    If midiAlsa_OutputParser <> 0 Then _
        snd_midi_event_free midiAlsa_OutputParser
    If midiAlsa_OutputHandle <> 0 Then snd_seq_close midiAlsa_OutputHandle
#EndIf
    midiAlsa_OutputHandle = 0
    midiAlsa_OutputParser = 0
    midiAlsa_OutputPort = -1
    midiAlsa_OutputTargetClient = -1
    midiAlsa_OutputTargetPort = -1
    midiAlsa_OutputOpened = 0
End Sub


Function midiOutput_IsOpen() As Integer
    Return midiAlsa_OutputOpened
End Function


Function midiOutput_Send( _
    ByVal statusByte As Integer, _
    ByVal data1 As Integer, _
    ByVal data2 As Integer _
) As Integer
    If midiAlsa_OutputOpened = 0 Then Return 0
    If statusByte < &H80 OrElse statusByte > &HEF Then Return 0
    If data1 < 0 OrElse data1 > 127 Then Return 0
    If data2 < 0 OrElse data2 > 127 Then Return 0
#If Defined(OSE_MIDI_OUTPUT_TESTING)
    If midiOutput_TestBackendSend(CLng(statusByte), CLng(data1), _
        CLng(data2)) <> 0 Then
        midiOutput_Close()
        Return 0
    End If
    Return -1
#Else
    If midiAlsa_OutputHandle = 0 OrElse midiAlsa_OutputParser = 0 Then _
        Return 0

    Dim As UByte midiBytes(0 To 2)
    midiBytes(0) = CByte(statusByte)
    midiBytes(1) = CByte(data1)
    midiBytes(2) = CByte(data2)
    Dim As Integer byteCount = 3
    Dim As Integer messageFamily = statusByte And &HF0
    If messageFamily = &HC0 OrElse messageFamily = &HD0 Then byteCount = 2

    Dim As OseAlsaSeqEvent midiEvent
    Clear midiEvent, 0, SizeOf(midiEvent)
    snd_midi_event_reset_encode midiAlsa_OutputParser
    If snd_midi_event_encode(midiAlsa_OutputParser, _
        @midiBytes(0), byteCount, @midiEvent) <> byteCount Then Return 0

    midiEvent.queueId = OSE_ALSA_QUEUE_DIRECT
    midiEvent.source.portId = CByte(midiAlsa_OutputPort)
    midiEvent.destination.clientId = OSE_ALSA_ADDRESS_SUBSCRIBERS
    midiEvent.destination.portId = OSE_ALSA_ADDRESS_UNKNOWN
    If snd_seq_event_output_direct( _
        midiAlsa_OutputHandle, @midiEvent) < 0 Then
        midiOutput_Close()
        Return 0
    End If
    Return -1
#EndIf
End Function


Sub midiOutput_AllNotesOff()
    If midiAlsa_OutputOpened = 0 Then Exit Sub

    midiOutput_SendStopSequence()
End Sub

#endif

/' end of midi_alsa.bas '/
