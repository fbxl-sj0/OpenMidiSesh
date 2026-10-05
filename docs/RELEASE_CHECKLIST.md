<!--
    Project: OpenSesh
    File: docs/RELEASE_CHECKLIST.md
    Purpose: define reproducible release checks and the evidence they produce.
    Responsibilities: identify release inputs, automated gates and platform limits.
    This file does not certify an untested build or approve publication.
-->

# Release checklist

Run checks against the same Git commit that will be tagged. Preserve the tool
identity, source hash, logs and artifact hashes with the release. Earlier review
notes and screenshots describe their recorded snapshots, not a new build.

## Source and tooling

- Run `python tools/check_repository.py` from a clean checkout. The explicit
  `release_manifest.txt` must cover the maintained project files. The exact
  omaGUI payload must match `SNAPSHOT.sha256`, including its license notices.
- Run `python tests/source_archive_safety.py` and, on Linux,
  `bash tests/dependency_snapshot_negative.sh`. Require rejection of unsafe ZIP
  metadata, duplicate paths, altered dependencies and symbolic links.
- Run `powershell -NoProfile -File tools/lint.ps1` with the supported fblint.
  Require strict headers, strict tabs, zero errors and zero warnings. This is
  source lint; compiler-backed semantic lint is a separate check.
- Check the Linux target with `tools/lint.ps1 -Target linux`. Resolve genuine
  findings in source and document each rejected finding narrowly. Do not use
  a historical warning total as a passing gate.
- Verify the Windows compiler identity with `tests/verify_windows_toolchain.ps1`.
  Review a lock change before comparing artifacts from a different compiler.

## Windows release

Run `verify_windows_release.ps1 -EvidenceDirectory ../OpenSesh-release-evidence`
with a new directory outside the source tree. Require
`windows_release_verification_status=pass`. The verifier runs the full test
suite, strict lint, two byte-identical builds, PE validation, source archive
inspection, portable-package validation and deliberately malformed package
checks. Compiler warnings fail builds and tests.

The runtime suite includes deterministic parsers, persistence and rollback,
chronological history, malformed files, synth capture and shutdown, 324 control
contracts and 508 behavior checks in both Desktop and Touch modes, 49 reviewed
framebuffers, repeated process lifecycles and eight frame-pacing workloads.
Run timing checks on an idle host. Investigate recurring failures; do not relax
limits or silently refresh baselines to obtain a pass.

## Linux release

Run `bash tests/run_tests.sh` and `bash build_editor.sh` using the supported
FreeBASIC toolchain. The default suite has 60 tests. Supply both
`OSE_MIDI_INPUT_INDEX=auto` and `OSE_MIDI_OUTPUT_INDEX=auto` on a host with the
ALSA Midi Through port to require the sixty-first test and seven-message loopback.
This virtual loopback does not qualify physical MIDI hardware.

Exercise the exact packaged source with `verify_linux_release_archive.sh`,
providing its SHA-256 and entry count. Use `REQUIRE_LINUX_UI_RUNTIME=1`, an
authenticated `LINUX_UI_DISPLAY` and `LINUX_UI_XAUTHORITY` for real window,
framebuffer, control and frame-pacing checks. Use
`REQUIRE_LINUX_MIDI_LOOPBACK=1` to require ALSA loopback as well.

On the same authenticated display, run `tests/run_linux_sanitizers.sh` for
checked FreeBASIC code and GCC address, leak and undefined-behavior analysis.
The sanitizer suite deliberately does not establish frame-pacing performance.

## Publish

- Review the changelog, product version, supported platforms and known limits.
- Run GitHub CI on the exact commit and inspect complete logs, not just badges.
- Publish the corresponding source with binaries, license documents, build
  identity and SHA-256 checksums. Keep the tag and artifacts immutable.
- Describe unsigned builds and experimental platforms accurately. Signing,
  physical audio/MIDI devices, microphone input, accessibility and Android
  device qualification need their own evidence before claiming support.

The current Android path shares the editor source but has no native external
MIDI backend. A metadata test does not prove installation or device operation.
The custom sfxlib archive identity and corresponding-source requirements are
listed in DEPENDENCIES.md and THIRD_PARTY_NOTICES.md. A successful automated
check does not resolve that provenance question.

<!-- end of docs/RELEASE_CHECKLIST.md -->
