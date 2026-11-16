/'
    Project: OpenMidiSesh
    File: midi_input_stream.bi
    Targets: Shared MIDI decoder in the fb dialect.
    Module API: midiInputStream_Reset and midiInputStream_Process.
    Purpose: Declare the MIDI byte-stream decoder used by Android input.
    Responsibilities: Reset and feed one serialized stream to the protocol queue.
    This file intentionally does NOT contain: device handles, threads or recording policy.
'/
#ifndef __OSE_MIDI_INPUT_STREAM_BI__
#define __OSE_MIDI_INPUT_STREAM_BI__
Declare Sub midiInputStream_Reset()
Declare Sub midiInputStream_Process(ByVal bytes As Const UByte Ptr, _
    ByVal count As Integer, ByVal timestamp As ULong)
#endif
/' end of midi_input_stream.bi '/
