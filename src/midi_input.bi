/'
    Project: OpenSesh
    ---------------------------

    File: midi_input.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: midiInput_* endpoint operations with OseMidiInputMessage and queue limits.

    Purpose:

        Declare the platform-neutral MIDI-input device boundary used by the
        recording layer.

    Responsibilities:

        - expose bounded channel, system-common, and SysEx messages
        - enumerate native MIDI input endpoints on supported platforms
        - expose explicit open, close, polling, and drop-count operations
        - sample the same wrapping millisecond clock carried by input messages

    Ownership:

        Each backend owns its operating-system handle and releases it during
        midiInput_Close. Returned messages are complete value copies owned by
        the caller.

    This file intentionally does NOT contain:

        - WinMM or ALSA declarations
        - MIDI-file parsing or writing
        - omaGui widgets or recording policy
'/

#ifndef __OSE_MIDI_INPUT_BI__
#define __OSE_MIDI_INPUT_BI__

Const OSE_MIDI_INPUT_QUEUE_CAPACITY As Integer = 1024
Const OSE_MIDI_INPUT_MAX_LONG_BYTES As Integer = 4096
Const OSE_MIDI_INPUT_SHORT_MESSAGE As UByte = 0
Const OSE_MIDI_INPUT_SYSEX_MESSAGE As UByte = 1

Type OseMidiInputMessage
    As UByte messageKind
    As UByte status
    As UByte data1
    As UByte data2
    ' The backend's current clock and queued messages use the same epoch.
    ' Compare them using bounded modulo-2^32 elapsed-time arithmetic.
    As ULong timestampMilliseconds
    As Integer deviceIndex
    ' For a SysEx message this includes the leading F0 or F7 status byte.
    As Integer payloadLength
    As UByte payload(0 To OSE_MIDI_INPUT_MAX_LONG_BYTES - 1)
End Type

Declare Function midiInput_GetDeviceCount() As Integer

Declare Function midiInput_GetDeviceName( _
    ByVal deviceIndex As Integer _
) As String

Declare Function midiInput_Open(ByVal deviceIndex As Integer) As Integer

Declare Sub midiInput_Close()

Declare Function midiInput_IsOpen() As Integer

Declare Function midiInput_GetOpenDeviceIndex() As Integer

Declare Sub midiInput_ClearPending()

' Returns zero when no input is open. A successful clock may itself be zero.
' Capture after clearing pending messages to anchor a new recording before
' its first event; later callbacks can still publish older, rejectable events.
Declare Function midiInput_GetClockMilliseconds( _
    ByRef timestampMilliseconds As ULong _
) As Integer

Declare Function midiInput_Poll( _
    ByRef message As OseMidiInputMessage _
) As Integer

Declare Function midiInput_GetDroppedCount() As ULongInt

#endif

/' end of midi_input.bi '/
