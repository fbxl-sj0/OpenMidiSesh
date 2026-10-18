<!-- Project: OpenMidiSesh; File: CONTRIBUTING.md; Purpose: contributor workflow. -->

# Contributing to OpenMidiSesh

Start with the [user guide](docs/USER_GUIDE.md), [architecture](docs/ARCHITECTURE.md),
and [build instructions](docs/BUILDING.md). Keep changes focused and describe
the behavior they change.

Use the modern FreeBASIC <code>fb</code> dialect and the existing four-space
indentation, names, and comment style. Maintained source files need a purpose
header and an identifying footer. Document ownership, binary layouts,
threading, and platform constraints where they affect correctness.

Keep document editing, file persistence, audio, MIDI adapters, and UI code in
their existing modules. Changes to the vendored GUI also require updating its
hash manifests and attribution.

Before submitting, build the affected target, run relevant regressions, and
run the strict linter described in [Linting](docs/LINTING.md). Report which
targets and device features you could not check. Tests should exercise user
behavior or a failure boundary. Keep generated fixtures and build outputs out
of maintained source files.

Contributions are distributed under GPL-3.0-or-later. Include third-party
attribution when adding externally authored material.

<!-- end of CONTRIBUTING.md -->