/'
    Project: OpenSesh
    ---------------------------

    File: midi_input_protocol.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: midiInputProtocol_* queue, message validation, and timestamp operations.

    Purpose:

        Declare the platform-neutral bounded MIDI input protocol queue used
        by the WinMM and ALSA backends and deterministic tests on every host.

    Responsibilities:

        - validate supported short MIDI messages
        - assemble bounded SysEx chunks into complete messages
        - publish messages through a fixed single-producer/single-consumer queue
        - expose queue reset, polling, and drop accounting operations
        - rebase native timestamps and reject backward elapsed-time intervals

    This file intentionally does NOT contain:

        - MIDI device enumeration or lifecycle operations
        - WinMM or ALSA handles, headers, or callback declarations
        - recording-model or graphical UI policy
'/

#ifndef __OSE_MIDI_INPUT_PROTOCOL_BI__
#define __OSE_MIDI_INPUT_PROTOCOL_BI__

#include once "midi_input.bi"

Declare Function midiInputProtocol_RebaseTimestamp( _
    ByVal clockOrigin As ULong, _
    ByVal elapsedMilliseconds As ULong _
) As ULong

' Accept forward intervals shorter than half the 32-bit clock period.
' This includes an ordinary wrap but rejects stale events from before origin.
' On rejection, elapsedMilliseconds is cleared and the function returns zero.
Declare Function midiInputProtocol_ElapsedMilliseconds( _
    ByVal clockOrigin As ULong, _
    ByVal timestampMilliseconds As ULong, _
    ByRef elapsedMilliseconds As ULongInt _
) As Integer

Declare Sub midiInputProtocol_Initialize(ByVal deviceIndex As Integer)

Declare Sub midiInputProtocol_SetClosing(ByVal closing As Integer)

Declare Sub midiInputProtocol_ClearPending()

Declare Function midiInputProtocol_ProcessShort( _
    ByVal statusByte As Integer, _
    ByVal data1Byte As Integer, _
    ByVal data2Byte As Integer, _
    ByVal timestamp As ULong _
) As Integer

Declare Function midiInputProtocol_ProcessLongChunk( _
    ByVal payload As UByte Ptr, _
    ByVal payloadLength As Integer, _
    ByVal timestamp As ULong _
) As Integer

Declare Function midiInputProtocol_Poll( _
    ByRef message As OseMidiInputMessage _
) As Integer

Declare Function midiInputProtocol_GetDroppedCount() As ULongInt

#endif

/' end of midi_input_protocol.bi '/
