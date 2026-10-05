# Release checklist

This file separates automated release gates from work that requires a human,
specific hardware, or release credentials. A binary is not a commercial
release merely because it compiles.

## Automated gates

- Run `verify_windows_release.ps1` into a new evidence directory and require
  `windows_release_verification_status=pass`. The generated JSON must still
  state `commercial_release_ready=false` until every human gate below is met.
- Run `tests/run_tests.ps1` on Windows and require all 66 tests with zero
  failures.
- Run `bash tests/run_tests.sh` on Linux and require zero failures.
- On the authenticated Midcom X11 display, run
  `REQUIRE_LINUX_MIDI_LOOPBACK=1 bash tests/run_linux_sanitizers.sh` and
  require all 59 tests, including the seven-message ALSA `Midi Through`
  loopback, the complete
  324-control and 508-behavior GUI audit in Desktop and Touch profiles, zero generated-C
  `maybe-uninitialized` warnings, and leak, address, and undefined-behavior
  analysis to pass.
- Verify the full local omaGUI tree against `TREE.sha256` and the 116-file
  release subset against `SNAPSHOT.sha256`. Reject extra archive files and
  historical Arial-derived tables, and preserve both MIT and OFL license
  documents in the source archive.
- Verify the 14 release-critical Windows compiler, binutils, interface, and
  static-library files against `windows_toolchain_lock.json`.
- Require the application-level audit to report 324 working UI control
  contracts and 508 passing semantic behavior checks. All 29 text fields and
  five lists must pass real focus plus edit or row-selection input. All 171
  code-drawn controls must pass through the application's real pointer handlers.
- Require all twelve embedded score-tool and transport icon masks to pass
  dimensions, padding, accessible-name, landmark, and grayscale-coverage tests.
- Require the Options audit to load an isolated Dark startup preference, then
  atomically persist Light, Dark, and Black selections without touching the
  real user profile. Reject malformed, duplicate, oversized, or binary settings.
- Require both Windows and Midcom to pass all eight 480-frame UI smoothness
  cases. The 2,048-note workload must prove real scrolling, fader dragging,
  playback advancement, and changing VU levels. Require the 59 FPS floor,
  20 ms p95, 25 ms p99, 50 ms absolute maximum, bounded render and input
  latency, no rejected samples, and no more than two 33.34 ms hitches.
- Require the touch gesture state-machine test and both application audits to
  prove taps, drags, one-finger pan, two-finger center pan, independent
  horizontal time zoom, independent vertical track zoom, contact reordering,
  cancellation, and bounded zoom limits without moving existing notes.
- Build the shared-source Android APK and run
  `tests/run_android_device_smoke.ps1` on an attached arm64 device. Require
  install and launch, note-palette interaction, note insertion and dragging,
  playback, OpenSL audio warmup, and no fatal process log.
- Require all 102 reviewed semantic color pairings across Light, Dark, and
  Black to meet 4.5:1 for normal text and control glyphs, or 3:1 for the
  deliberately subdued disabled-label state.
- Require the MIDI, audio, timeline, and cross-domain history stress tests to
  pass after exceeding the sixteen-step bound and creating a new branch.
- Require the 8,192-operation document endurance oracle to match exact
  serialized MIDI and audio states through repeated ring eviction, undo, redo,
  cancellation, branching, and complete lifecycle resets.
- Require the deterministic 1,916-case MIDI mutation corpus to preserve the
  active document and history on every rejection and serialize every accepted
  mutation.
- Require project-pair fault injection to prove rollback at both commits and
  restart recovery from all three journal states.
- Require the accelerated 30-second playback endurance render to schedule more
  than ten thousand production-synth notes, remain audible without full-scale
  clipping near both ends, preserve its exact frame count, and report zero
  underruns.
- Require all 49 reviewed Windows framebuffer cases to match decoded pixels,
  including both mixer pages at the 800 x 600 minimum, Light, Dark, and Black
  main, Options-popup, and dialog coverage, and an active audition lighting its channel plus
  both master VU meters. Reject any requested/captured dimension mismatch
  before comparing a baseline.
- On Midcom's authenticated X11 display, require twenty-one byte-pinned Linux
  framebuffers. The 800 x 600 set covers sixteen reviewed cases: Light, Dark,
  and Black main, Options, About, and drums views; one View menu; and active
  meters in all three themes. Five reviewed 1920 x 1080 cases additionally cover
  every main theme, the Dark Options theme menu, the full 16-channel mixer, and
  an active meter. Require thirty-one bounded editor launches (21 captures,
  two control audits, and eight smoothness cases), with one passing 480-frame
  measurement per case, plus the same 324 control contracts and 508 behavior
  checks in both Desktop and Touch interaction profiles.
- Run strict Windows and Linux-target fblint with `--no-semantic` over every
  maintained project `.bas` and `.bi` file. Require zero errors and info
  diagnostics, and compare project warning groups exactly against
  `windows_lint_baseline.txt` and `portability_lint_baseline.txt`. Classify the
  byte-pinned omaGui snapshot separately within the combined scan. The
  current reviewed totals are 24 project and 154 vendored warnings on Windows,
  and 698 project and 615 vendored warnings on Linux. These counts use
  fb-linter 1.0.0 ruleset 2026.10.036. The current linter
  reports advisory source patterns that the previous ruleset did not emit;
  these exact fingerprints prevent new findings from hiding in those totals.
- Build through `build_editor.ps1` and verify the `0.9.0-dev` Windows file and
  product metadata. Extract the executable's RT_MANIFEST resource and require
  the reviewed `asInvoker`, no-UIAccess, Windows 10-or-later, and system-DPI
  declarations.
- Require two independent Windows builds to be byte-identical. Parse the PE
  image directly and require AMD64, GUI subsystem, relocations, high-entropy
  and dynamic ASLR, NX compatibility, a zero build timestamp, no debug
  sections, no overlay, no local build path, and only the six reviewed Windows
  system DLLs. Require all eight unsafe PE mutations to fail closed.
- Create a source archive through `prepare_source_release.ps1`, inspect its
  explicit manifest, verify that it contains no binaries or private test data,
  require the exact vendored omaGui snapshot, and require `unzip -tq` to
  accept it on Linux without path warnings. Run
  `verify_linux_release_archive.sh` against the exact archive SHA-256 and
  entry count with `REQUIRE_LINUX_UI_RUNTIME=1` and
  `REQUIRE_LINUX_MIDI_LOOPBACK=1`, then require 59 passing Linux tests, the
  native ALSA loopback, the Linux GUI runtime contract, and a complete editor
  build from only the extracted source.
- Create the Windows portable package twice and require byte-identical ZIPs.
  Independently require exactly nine fixed-timestamp files: the verified
  executable, user readme, four notice/license files, build identity, internal
  SHA-256 manifest, and exact corresponding source archive. Require all seven
  unsafe package mutations to fail closed.

## Automated engineering coverage

- Native file completion, physical microphone capture, microphone
  transcription, and model-backed generated-dialog New, Apply, Delete,
  quantize, device-open, device-close, no-op, and chronological undo paths
  are covered.
- Retained keyboard events prove Tab and Shift+Tab traversal, focused-command
  activation, all eight Alt menu routes, arrow navigation, Escape dismissal,
  and modal shortcut isolation.
- Explicit gfxlib display teardown is exercised by every UI and framebuffer
  process; the focused lifecycle stress check must complete sixty sequential
  Windows GUI launches on the null audio backend without a timeout and must
  reject malformed numeric framebuffer configuration before accepting display
  shutdown changes. A separate gate must complete twenty-five
  default-audio process launches with explicit sfxlib shutdown. Linux adds
  twenty-seven authenticated-X11 launches from extracted source.
- Master-effect, capture, and full-editor exits must call the idempotent sfxlib
  shutdown boundary explicitly so driver or capture workers cannot outlive the
  process test that started them.
- Audio clip mutations must resynchronize the complete sfxlib sample-slot
  table after list compaction. A damaged backing file must leave only its own
  slot offline while valid neighboring clips remain audibly renderable, and a
  repaired file must reload current PCM without reviving stale data. All loaded
  sample slots must be explicitly unloaded before sfxlib shutdown; the Linux
  sanitizer gate enforces this ownership boundary with leak detection.

## Required before a 1.0 binary release

- Replace `0.9.0-dev` only as part of a reviewed release-version change.
- Complete a physical MIDI input/output loopback on the supported Windows and
  Linux hardware matrix. The Windows audit host has no MIDI input. Midcom's
  automated ALSA `Midi Through` loopback proves the Linux native API and all
  supported channel-message families, but it is not an external controller or
  synthesizer.
- Implement and physically verify an Android external-MIDI endpoint adapter if
  Android MIDI input or output is included in the supported 1.0 capability
  matrix. Until then the Android build must report those endpoints unavailable
  while retaining software-synth playback.
- Confirm the exact provenance and redistribution terms of the custom
  FreeBASIC 1.20.x sfxlib build with its distributor. The linked decoder
  notices are preserved in `THIRD_PARTY_NOTICES.md`.
- Perform a final hands-on keyboard-only pass plus high-DPI, screen-reader,
  audio-device-loss, suspend, and multi-hour playback sessions on the
  supported hardware matrix.
- Obtain the release signing identity, sign the executable and installer, and
  verify signatures on a clean machine.
- Have the final binary package and notices reviewed by the release owner or
  qualified counsel. This checklist is engineering evidence, not legal advice.

<!-- end of RELEASE_CHECKLIST.md -->
