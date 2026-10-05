<!--
    Project: OpenSesh
    ---------------------------

    File: CLEAN_ROOM.md

    Purpose:

        Define the intended provenance and release boundary for this GPL
        MIDI-editor implementation.

    Responsibilities:

        - separate behavioral observations from implementation material
        - identify files that must never enter a source release
        - state dependency and legal-review expectations

    This file intentionally does NOT contain:

        - legal advice or a guarantee about a particular jurisdiction
        - proprietary Midisoft source code
        - decompiler output copied into the application
-->

# Clean-room implementation boundary

OpenSesh is an independent implementation of a MIDI editor. Its source
should be written from:

- the public Standard MIDI File specification and public FreeBASIC/sfxlib/
  omaGui interfaces
- behavior observed from a locally owned reference application
- general UI ideas visible in the supplied screenshot

The audio extension is also independent. It uses a bounded public PCM WAV
inspection path, external WAV filenames, and the original `OSEPROJECT 1`
container described in the project README. It does not parse, reproduce, or
embed a Midisoft wave-track file format.

The MIDI-input extension is independent as well. It uses the public Windows
WinMM API and Linux ALSA Sequencer API to enumerate and open one selected
source and receive bounded short messages and complete SysEx messages. The
callback or polling adapters and fixed-size SysEx reassembler are isolated
from the MIDI model and UI. FreeBASIC's sfxlib MIDI surface is output-only, so
it is not used as an input dependency. The implementation does not copy a
reference callback, device protocol, or recording routine.

The MIDI-output extension is independent as well. On Windows it uses the
public sfxlib `MIDI OPEN`, `MIDI SEND`, and `MIDI CLOSE` commands. On Linux it
uses the public ALSA Sequencer subscription and direct-event APIs. It does not
copy a reference output routine or device protocol, and it remains separate
from native input. The editor may use this public boundary for MIDI Thru while
recording; native input handling still never edits the model directly.

The recording layer uses an unsigned monotonic millisecond timestamp supplied
by the native backend for hardware MIDI event timing. PC-keyboard recording
remains on the application clock because it has no device timestamp.

The optional audio-recording button uses only the public sfxlib `CAPTURE`
commands. It saves a new external WAV, validates it through the independent
RIFF/WAVE parser, and adds a normal user-owned audio clip reference. Captured
audio is not embedded in the project container and no recovered wave-track
implementation is used.

The export extensions are independent. The MOD writer follows the public
31-sample ProTracker `M.K.` layout and generates its own mathematical waveform
samples from the editable MIDI model. The WAV writer uses sfxlib's public
final-output capture API and the project's existing RIFF/WAVE validator. No
reference-application export code, sample data, or private file format is used.

Historical reverse-engineering material was used only as behavioral reference
and is not retained in the current project tree. If an archival workspace still
contains any of the following, it must not be copied into a GPL release:

- `E:\Midisoft\analysis\decompiled-*`
- `E:\Midisoft\analysis\midisoft4-extracted`
- the original Midisoft executables, DLLs, fonts, samples, help files, and
  screenshots
- guessed or translated decompiler function bodies

The score can optionally load an application-local monochrome mask generated
from a separately owned music font, but no such private mask or font is retained
by this project or used as a release input. The FreeBASIC source contains only a
bounded generic mask loader, character-slot identifiers, and independent
fallback drawings, so the editor builds and runs without any historical asset.

The distributable project is the `opensesh` source archive root. It contains original
FreeBASIC source, its own documentation, and the exact MIT-licensed omaGui
runtime subset compiled by the application. Its OFL-licensed generated bitmap
font subsets use neutral identifiers and include their license. sfxlib remains
part of the separately supplied FreeBASIC toolchain. Dependency licenses and
attribution requirements must still be reviewed before publishing a combined
binary distribution.

The project uses the SPDX identifier `GPL-3.0-or-later`. This document records
engineering provenance; it is not a legal opinion or a guarantee that a release
will be risk-free. A qualified attorney should review the final source,
dependencies, branding, screenshots, and release assets before publication.

<!-- end of CLEAN_ROOM.md -->
