<!--
    Project: OpenSesh
    File: docs/DEPENDENCIES.md
    Purpose: Identify components used by the editor and packaged builds.
    Responsibilities: distinguish bundled source from host-provided tools and media.
    This file does not contain an installation guide or a release audit.
-->

# Dependencies

## Included with the source

The repository includes the reviewed omaGUI runtime under
<code>vendor/omaGui</code>. <code>vendor/omaGui/SNAPSHOT.sha256</code>
identifies the exact source files used by the editor and source packages. You
normally do not need another omaGUI checkout.

OpenSesh is licensed under GPL-3.0-or-later. The vendored GUI and other
components retain their own license terms. See
<code>THIRD_PARTY_NOTICES.md</code> and the license files in the repository
before redistributing a combined package.

## Provided by the build host

| Component | Used for |
| --- | --- |
| FreeBASIC 1.20.x | Compile the editor. Windows release builds use the exact Win64 toolchain recorded in <code>windows_toolchain_lock.json</code>. |
| gfxlib and sfxlib | Native windows, drawing, audio playback, and capture. These libraries are distributed with the FreeBASIC toolchain used for each target. |
| GNU binutils and <code>windres</code> | Assemble, link, and add Windows version resources. |
| ALSA Sequencer library | Native MIDI input and output in Linux builds. |
| Android FreeBASIC wrapper and Android SDK/NDK | Build and sign a development APK. |

Build instructions are in [Building OpenSesh](BUILDING.md).

## User-provided media and devices

SoundFonts and WAV clips are selected by the user and are not included in
packages. OpenSesh project files store WAV paths rather than embedding the
recordings. A system audio output is used for software playback.

Native MIDI input and output are available on Windows and Linux. The current
FreeBSD, NetBSD, OpenBSD, Haiku, and Android builds use a software-only MIDI
adapter; their editor, built-in sound, and file export remain available.

<!-- end of docs/DEPENDENCIES.md -->