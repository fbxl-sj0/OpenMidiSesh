<!--
    Project: OpenMidiSesh
    File: docs/ANDROID_AUDIO.md
    Purpose: Document Android audio runtime requirements and their regression tests.
    Responsibilities: Buffer ownership, generated-note release and build provenance.
    This file intentionally does NOT contain MIDI transport or UI implementation.
-->

# Android audio runtime

Android builds require sfxlib with FIFO OpenSL buffer reclamation and the
`fb_sfxGeneratedReleaseChannel(int channel)` export. The Android build enables
`OSE_SFX_GENERATED_RELEASE_AVAILABLE=1`; an older runtime fails at native linking
instead of silently retaining abrupt MIDI note-off. Other platform packages can
enable the same definition after qualifying this export in their runtime.
Their default remains compatible with older sfxlib installations.

The compatibility patch is
[android-sfx-audio.patch](../tools/patches/android-sfx-audio.patch). It targets
the runtime sources supplied with the FreeBASIC Android 1.20.4 package. Apply
it to that matching source tree with `git apply --check` followed by `git apply`,
then rebuild and install sfxlib for each packaged Android ABI using the
toolchain's build instructions. Preserve the original archives for rollback.
Both `libsfxpic.a` and `libsfxmtpic.a` need the correction. A newer source tree
may already contain these changes or use different internal identifiers; port
the change there instead of forcing an incompatible patch or mixing headers
from another runtime version. Application code keeps no private voice layouts.

## Buffer lifetime

OpenSL keeps the submitted PCM memory until the corresponding completion
callback. The old driver searched for the first busy slot on completion and
the first free slot on submission. After submitting buffers 0, 1, 2, completing
0 and submitting 0 again, the next completion incorrectly freed 0 instead of 1.
The producer then overwrote PCM which was still queued for playback. This
corruption can click even when Android's AudioTrack reports zero underruns.

The corrected driver advances separate submission and completion cursors in
FIFO order. A failed enqueue leaves the submission cursor unchanged. The
runtime lock serializes producers; the buffer mutex protects ownership against
the callback. Enqueue runs outside that mutex, so an early callback cannot
deadlock against the producer. Shutdown ignores late completion notifications.
See [Android's OpenSL programming notes](https://developer.android.com/ndk/guides/audio/opensl/opensl-prog-notes)
for the callback threading and buffer queue contracts.

The patch includes `tests/sfx/opensl-queue.c`, which compiles the production
driver against the NDK's real interface declarations and a fake playback sink.
The sink retains PCM pointers and verifies they remain unchanged until
completion. On a host with GCC, pthreads and the NDK, compile it with:

```sh
cc -std=c11 -Wall -Wextra -Werror -pthread \
  -idirafter "$NDK_HEADERS" tests/sfx/opensl-queue.c -o opensl-queue
./opensl-queue
```

`NDK_HEADERS` is the NDK LLVM sysroot's `usr/include` directory. The test covers
10,000 submissions, full queues, rejected enqueues, callbacks preceding enqueue
return, shutdown and restart. The old driver fails the retained-PCM assertion.

## MIDI note release

A normal key release uses the instrument's existing envelope, preserving its
current phase and gain until it reaches silence. Immediately deactivating a
nonzero oscillator sample creates a separate release click. The runtime helper
selects only SOUND and NOISE voices belonging to the requested mixer channel
under the runtime lock. It leaves sample voices and other channels untouched.
Voice stealing and transport stops retain their explicit immediate-stop path.

`tests/midi_monitor_audio_smoke.bas` checks the production synth with the null
driver. Build with `OSE_SFX_GENERATED_RELEASE_AVAILABLE=1` and a qualified
runtime to require audible release PCM followed by complete silence, alongside
held-note, controller and stolen-voice ownership checks. The normal test build
also checks compatibility with older runtimes. Neither null-driver test proves
the physical speaker output; the Galaxy S10 listening check is separate.

<!-- end of docs/ANDROID_AUDIO.md -->
