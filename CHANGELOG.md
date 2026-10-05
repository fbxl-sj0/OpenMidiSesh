<!-- Project: OpenSesh; File: CHANGELOG.md; Purpose: release-facing changes. -->

# Changelog

## Unreleased

- Add native package CI for Windows, Linux, FreeBSD, NetBSD, OpenBSD and Haiku
  x86_64, including tests, native editor launches and extracted-package checks.
- Publish a complete passing package set with matching corresponding source,
  checksums, licenses and per-target build evidence on version tags.
- Select the unavailable-endpoint MIDI adapter on BSD and Haiku and test its
  rejection and output-clearing contracts.

The 0.9.0 development editor is published on GitHub. Native downloadable
packages are being qualified. Release validation and platform claims are recorded with
the release artifacts; historical review notes describe earlier snapshots.

### Release preparation

- Move application sources into `src/` and reference documentation into
  `docs/`. Divide the editor implementation into focused private includes
  while preserving its compilation order and public interfaces.
- Require zero warnings from strict Windows and Linux source lint and enable
  all compiler warnings in native builds and tests. Record narrow reviewed
  suppressions and regression fixtures for two validator false positives.
- Reject empty CSS selectors and unallocated image arrays in the GUI runtime;
  cover truncated ICO input and masked textbox state in native safety tests.
- Add a reviewed source inventory, extraction safety checks, deterministic
  source packages, and CI for the public Linux compiler packages. Keep the
  complete Windows release gate on a trusted desktop runner.
- Preserve dependency licenses and exclude historical font conversions from
  release payloads. Document exact tool identities and validation boundaries.

### Existing capabilities

- Standard MIDI File loading, saving, bounded note and track editing, and
  chronological undo and redo across MIDI and audio edits.
- Score preview, sixteen-channel mixer, automation, drum phrases, and
  performance keyboard with Desktop and Touch interaction profiles.
- Built-in software synthesis and user-supplied SoundFont playback, WAV and
  ProTracker MOD export, and platform MIDI endpoints on Windows and Linux.
- Light, Dark, and Black themes, saved preferences, and deterministic model,
  parser, playback, persistence, and interface regression tests.

<!-- end of CHANGELOG.md -->
