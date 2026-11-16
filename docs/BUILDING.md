<!--
    Project: OpenMidiSesh
    File: docs/BUILDING.md
    Purpose: Explain how to build OpenMidiSesh for supported targets.
    Responsibilities: list toolchain requirements, commands and output locations.
    This file does not provision compilers or certify a release.
-->

# Building OpenMidiSesh

The editor is written in FreeBASIC. The repository includes the omaGUI source
tree used by default. Build scripts compile the editor modules into a temporary
directory and publish the executable only after a successful link.

## Requirements

- FreeBASIC 1.20.x with the matching graphics and sound libraries.
- A native compiler toolchain and libraries for the target platform.
- The included <code>vendor/omaGui</code> directory, unless you deliberately
  select a different tree.
- ALSA development libraries when building Linux MIDI input/output support.
- The FreeBASIC Android wrapper and Android SDK/NDK for Android packages.

For Windows release builds, use the reviewed Win64 distribution described in
<code>windows_toolchain_lock.json</code>. Run
<code>tests/verify_windows_toolchain.ps1</code> to check that compiler and its
linked libraries match the reviewed identity.

## Windows

Build a 64-bit Windows executable with the installed FreeBASIC compiler:

~~~powershell
powershell -NoProfile -File ./build_editor.ps1 -OutputPath ./build/openmidisesh.exe
~~~

The script defaults to <code>C:/FreeBASIC/fbc.exe</code> and
<code>vendor/omaGui</code>. Override those paths when needed:

~~~powershell
./build_editor.ps1 -FreeBasicPath C:/FreeBASIC/fbc.exe -OmaGuiPath ./vendor/omaGui -OutputPath ./build/openmidisesh.exe
~~~

The Windows build also needs GNU <code>windres</code>, normally provided in
the compiler distribution. Use <code>-ResourceCompilerPath</code> if it is
installed elsewhere.

## Linux, BSD and Haiku

On Linux, run:

~~~bash
OUTPUT_PATH="$PWD/build/openmidisesh" bash ./build_editor.sh
~~~

The script also selects the native software-only MIDI adapter on FreeBSD,
NetBSD, OpenBSD, and Haiku. Run it with the target's native FreeBASIC,
graphics, and sound libraries. Linux uses ALSA Sequencer for MIDI input and
output and links against the host ALSA library.

Set <code>FREEBASIC_PATH</code>, <code>OMAGUI_PATH</code>, or
<code>OUTPUT_PATH</code> to override the compiler, GUI source tree, or
executable destination. Without overrides, the script uses <code>fbc</code>,
the included omaGUI tree, and an executable named <code>openmidisesh</code> in the
repository root.

## Android

Use the qualified sfxlib runtime described in [Android audio runtime](ANDROID_AUDIO.md).
It includes the OpenSL buffer fix and the generated-note release export.

Android shares the editor, score, gestures, and software synthesizer. Build an
ARM64 development APK with the installed Android wrapper:

~~~powershell
./build_editor_android.ps1 -Target android-aarch64 -ApiLevel 24 -OutputPath ./build/android/openmidisesh-debug.apk
~~~

The defaults are <code>C:/freebasic-android/fbc-android.cmd</code>,
<code>android-aarch64</code>, API 24, and
<code>build/android/openmidisesh-debug.apk</code>. The script also accepts
<code>android-arm</code> and <code>android-x86_64</code>. Add
<code>-Target universal</code> to include all three ABIs in one APK. Add
<code>-RunOnDevice</code> to install and launch the package on an attached
device. Packages require Android 6.0 (API 23) or later for the system MIDI API.
The build stages our Java/JNI input bridge alongside the NativeActivity template;
it does not modify the installed wrapper. USB class-compliant MIDI devices are
read through Android's MIDI service. External MIDI output remains unavailable.
The density-aware viewport also supports older wrapper runtimes which lack the
new gfxlib display-metrics operations. The package permits portrait and landscape.

After installing, attach a USB MIDI device through a host/OTG adapter, open
**MIDI In**, choose its input port, then press **Monitor**. Test hardware with
ADB over Wi-Fi or disconnect the ADB cable before using the USB port. Local
stream tests do not substitute for this hardware check.

## Outputs and checks

| Build script | Default output |
| --- | --- |
| <code>build_editor.ps1</code> | <code>openmidisesh.exe</code> |
| <code>build_editor.sh</code> | <code>openmidisesh</code> |
| <code>build_editor_android.ps1</code> | <code>build/android/openmidisesh-debug.apk</code> |

The desktop scripts reject compiler warnings and leave an existing executable
alone if compilation or linking fails. They do not install the compiler or
system libraries.

For full platform package coverage and release checks, see
[CI](CI.md) and the [release checklist](RELEASE_CHECKLIST.md).

<!-- end of docs/BUILDING.md -->
