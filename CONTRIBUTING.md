<!-- Project: OpenSesh; File: CONTRIBUTING.md; Purpose: contributor workflow. -->

# Contributing to OpenSesh

Use small changes that preserve the editor's existing behavior. Describe the
problem, the resulting behavior, and the checks you ran in each pull request.

Use the modern FreeBASIC `fb` dialect and the existing four-space indentation,
names, and comment style. Every maintained source file needs a purpose header
and an identifying footer. Explain ownership, binary layouts, threading, and
platform constraints where they affect correctness. Prefer readable bounds
checks and explicit cleanup to compact expressions.

Keep model, file persistence, audio, platform MIDI, and user-interface code
separate. Avoid changing the vendored GUI while working on unrelated editor
features. Changes to a dependency require updated hash manifests, attribution,
and regression checks.

Before submitting, build from current source, run the relevant tests, and run
the strict lint gate. Compiler errors, compiler warnings, and lint warnings
must fail validation. Suppress only a specific proven false positive at the
affected line, with a short explanation; do not add warning baselines or
disable whole rule families. Describe any hardware checks you could not run.

Tests should exercise behavior or a failure boundary. Use generated fixtures
outside the source tree and reuse one build directory. Remove disposable
outputs after recording the result. Do not commit executables, user recordings,
private reference material, SoundFonts, or historical font conversions.

Contributions are distributed under the project's GPL-3.0-or-later license.
Include third-party attribution when introducing externally authored material.

<!-- end of CONTRIBUTING.md -->
