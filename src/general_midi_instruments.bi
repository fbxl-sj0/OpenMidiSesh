/'
    Project: OpenMidiSesh
    ---------------------------

    File: src/general_midi_instruments.bi

    Targets: FreeBASIC fb dialect; included by the editor application.
    Module API: General MIDI program-name lookup for editor controls.

    Purpose:

        Provide the standard General MIDI Level 1 program names in program
        order so users can choose sounds by name instead of memorizing numbers.

    Responsibilities:

        - own the bounded 128-entry instrument-name table
        - expose checked name and one-based display-label lookups

    This file intentionally does NOT contain:

        - MIDI program-change event handling
        - synthesizer or SoundFont implementation
        - editor window layout

    Included once by openmidisesh.bas.
'/

#ifndef __OSE_GENERAL_MIDI_INSTRUMENTS_BI__
#define __OSE_GENERAL_MIDI_INSTRUMENTS_BI__

Const OSE_GENERAL_MIDI_PROGRAM_COUNT As Integer = 128
Const OSE_GENERAL_MIDI_PROGRAM_NAME_BYTES As Integer = 32

Private Dim Shared generalMidiInstrument_Names( _
    0 To OSE_GENERAL_MIDI_PROGRAM_COUNT - 1) As _
    ZString * OSE_GENERAL_MIDI_PROGRAM_NAME_BYTES = { _
    "Acoustic Grand Piano", "Bright Acoustic Piano", _
    "Electric Grand Piano", "Honky-tonk Piano", "Electric Piano 1", _
    "Electric Piano 2", "Harpsichord", "Clavinet", "Celesta", _
    "Glockenspiel", "Music Box", "Vibraphone", "Marimba", "Xylophone", _
    "Tubular Bells", "Dulcimer", "Drawbar Organ", "Percussive Organ", _
    "Rock Organ", "Church Organ", "Reed Organ", "Accordion", "Harmonica", _
    "Tango Accordion", "Acoustic Guitar (nylon)", _
    "Acoustic Guitar (steel)", "Electric Guitar (jazz)", _
    "Electric Guitar (clean)", "Electric Guitar (muted)", _
    "Overdriven Guitar", "Distortion Guitar", "Guitar harmonics", _
    "Acoustic Bass", "Electric Bass (finger)", "Electric Bass (pick)", _
    "Fretless Bass", "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", _
    "Synth Bass 2", "Violin", "Viola", "Cello", "Contrabass", _
    "Tremolo Strings", "Pizzicato Strings", "Orchestral Harp", "Timpani", _
    "String Ensemble 1", "String Ensemble 2", "SynthStrings 1", _
    "SynthStrings 2", "Choir Aahs", "Voice Oohs", "Synth Voice", _
    "Orchestra Hit", "Trumpet", "Trombone", "Tuba", "Muted Trumpet", _
    "French Horn", "Brass Section", "SynthBrass 1", "SynthBrass 2", _
    "Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax", "Oboe", _
    "English Horn", "Bassoon", "Clarinet", "Piccolo", "Flute", _
    "Recorder", "Pan Flute", "Blown Bottle", "Shakuhachi", "Whistle", _
    "Ocarina", "Lead 1 (square)", "Lead 2 (sawtooth)", _
    "Lead 3 (calliope)", "Lead 4 (chiff)", "Lead 5 (charang)", _
    "Lead 6 (voice)", "Lead 7 (fifths)", "Lead 8 (bass + lead)", _
    "Pad 1 (new age)", "Pad 2 (warm)", "Pad 3 (polysynth)", _
    "Pad 4 (choir)", "Pad 5 (bowed)", "Pad 6 (metallic)", _
    "Pad 7 (halo)", "Pad 8 (sweep)", "FX 1 (rain)", "FX 2 (soundtrack)", _
    "FX 3 (crystal)", "FX 4 (atmosphere)", "FX 5 (brightness)", _
    "FX 6 (goblins)", "FX 7 (echoes)", "FX 8 (sci-fi)", "Sitar", _
    "Banjo", "Shamisen", "Koto", "Kalimba", "Bag pipe", "Fiddle", _
    "Shanai", "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock", _
    "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal", _
    "Guitar Fret Noise", "Breath Noise", "Seashore", "Bird Tweet", _
    "Telephone Ring", "Helicopter", "Applause", "Gunshot" _
}

Public Function generalMidiInstrument_GetName( _
    ByVal programNumber As Integer _
) As String
    If programNumber < 0 OrElse _
        programNumber >= OSE_GENERAL_MIDI_PROGRAM_COUNT Then Return ""
    Return generalMidiInstrument_Names(programNumber)
End Function


Public Function generalMidiInstrument_GetDisplayName( _
    ByVal programNumber As Integer _
) As String
    If programNumber < 0 OrElse _
        programNumber >= OSE_GENERAL_MIDI_PROGRAM_COUNT Then Return ""

    ' MIDI stores zero-based programs; the selector shows human-facing numbers.
    Return Right("000" + LTrim(Str(programNumber + 1)), 3) + _
        "  " + generalMidiInstrument_GetName(programNumber)
End Function

#endif

/' end of src/general_midi_instruments.bi '/
