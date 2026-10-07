<!--
    Project: OpenSesh
    ---------------------------

    File: docs/DEPENDENCIES.md

    Purpose:

        Define the dependency identities used for audited release builds.

    Responsibilities:

        - distinguish vendored source from host-supplied build tools
        - identify the Windows release toolchain lock
        - identify the Android packaging toolchain boundary
        - state the remaining sfxlib provenance limitation

    This file intentionally does NOT contain:

        - dependency installation instructions
        - a legal opinion
        - credentials or private package locations
-->

# Dependency identities

## Vendored source

The editor defaults to its maintained `vendor/omaGui` snapshot. Its downstream
changes are described in `vendor/omaGui/DEPENDENCY.md`. A full local development
tree may also contain `TREE.sha256`, which checks examples, tools and historical
fonts. That larger tree is not published with OpenSesh.
`SNAPSHOT.sha256` selects the 122-file redistributable runtime subset for
source archives and release lint. The subset includes omaGUI's MIT license,
the licenses for its generated bitmap-font subsets, the CHM decoder license,
and Unicode font packs. OpenSesh selects its neutral font tables with
`OMAGUI_REDISTRIBUTABLE_FONTS`. The release subset omits historical
Arial-derived tables, examples, tools, and generated binaries.

The October 7 equalization incorporates the optimized omaGUI tree from Tiko
commit `09f5d5081195c6aa67a84ff17c73d236c5a9149d`, retaining the OpenSesh CSS
and image-array safety checks, label styles and literal-color support. The
local development tree is identical to Tiko's shared copy. Both manifests
record the merged bytes.

The October 7 performance overlay preserves those downstream changes and adds
bounded menu updates, cached display captions, clipped popup replay, checked
direct glyph-span writes, batched key events and registry mutation tracking. The
maintained snapshot passed the native editor smoke and focused font/render
checks. DOSBox-X timed idle remains opt-in with its matching gfxlib.

## Audited Windows build tools

`windows_toolchain_lock.json` identifies the release-critical files from the
release-locked Win64 FreeBASIC 1.20.4-3 distribution. The lock covers the compiler,
assembler, linker, resource compiler, gfxlib and sfxlib interfaces, and the
static FreeBASIC, gfxlib, and sfxlib archives selected by native builds.

`tests/verify_windows_toolchain.ps1` rejects a length, hash, path, or compiler
banner mismatch. Updating the compiler or any locked library requires a
reviewed lock update and new Windows and Linux evidence. The lock is an exact
audit identity for this build host, not a claim that every support file in the
FreeBASIC installation affects the linked executable.

## Linux build tools

The original Midcom audit used FreeBASIC 1.20.3-1. The isolated October 2
review checkpoint used FreeBASIC 1.20.4-1 on Linux x86_64; its tested source
snapshot and coverage limits are recorded in FRONTIER_REVIEW_2026-10-02.md.
The current native release-candidate checks use FreeBASIC 1.20.4-3.
Linux distribution executables and archives are platform-specific and are
recorded in cross-platform evidence rather than compared with the Windows
byte lock.

Linux MIDI input and output link the system `libasound` ALSA Sequencer API.
The backend declares only the narrow public ABI it uses and asserts the event
record sizes at compile time. Midcom release verification requires the ALSA
headers, shared library, sequencer device, and `Midi Through` loopback port.

## Android build tools

`build_editor_android.ps1` uses the installed FreeBASIC Android wrapper, Android
SDK/NDK toolchain, and debug signing support to package the same shared source
as the desktop builds. The wrapper and Android SDK/NDK are host-supplied build
tools and are not included in the source archive. Android currently substitutes
the small `src/midi_null.bas` capability adapter because no native external-MIDI
endpoint backend is implemented; the editor UI, touch gestures, document
model, renderer, and software synth are shared source.

## Generated-voice stop dependency

`src/generated_voice_stop_internal.bi` calls the exported sfxlib C entrypoints
`fb_sfxSoundStopChannel`, `fb_sfxNoiseStop`, `fb_sfxRuntimeLock`, and
`fb_sfxRuntimeUnlock`. These exports are not documented BASIC STOP keywords.
Their availability and 32-bit C `int` channel ABI must be rechecked when
upgrading the supported Windows, Linux, or Android runtime archives. The
application does not depend on private voice structures or retain voice
pointers. The null-driver PCM regression verifies generated SOUND/NOISE stop
behavior and channel isolation with the linked runtime.

## Remaining provenance gate

The local FreeBASIC distribution contains a custom sfxlib with MIDI fallback,
output capture, effects, and decoder support. Its exact archive bytes are now
locked, and decoder notices are preserved in `THIRD_PARTY_NOTICES.md`, but the
distributor's authoritative provenance and redistribution statement is still
required before a commercial 1.0 binary release.

<!-- end of DEPENDENCIES.md -->
