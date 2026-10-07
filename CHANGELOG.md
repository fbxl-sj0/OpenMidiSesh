<!-- Project: OpenSesh; File: CHANGELOG.md; Purpose: release-facing changes. -->

# Changelog

## Unreleased

- Equalize the optimized omaGUI tree with Tiko while retaining our CSS and
  image-array safety checks, label styles and literal-color support.
- Require compiler semantic models for lint, including omaGUI's shared
  implementation context and the actual native build settings.
- Update omaGUI from Tiko with batched glyph rendering, cached text metrics,
  retained palette tracking and theme-frame controls. Preserve our GUI safety
  checks, label styles, literal colors and score redraw fixes.
- Capture score pixels in bulk during native rendering audits so Haiku checks
  retain their full coverage within the existing editor timeout.
- Restore the score background when note-tool cursors move or disappear, and
  clip notation to the score body so notes cannot overwrite the title bar.
- Compare retained score pixels with fresh native rendering on both work pages
  in the Desktop and Touch control audits.
- Add native package CI for Windows, Linux, FreeBSD, NetBSD, OpenBSD and Haiku
  x86_64, including tests, native editor launches and extracted-package checks.
- Publish a complete passing package set with matching corresponding source,
  checksums, licenses and per-target build evidence on version tags.
- Select the unavailable-endpoint MIDI adapter on BSD and Haiku and test its
  rejection and output-clearing contracts.
- Include target-specific runtime dependency installation commands in each
  native download and its build evidence.

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
