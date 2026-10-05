<!--
    Project: OpenSesh
    File: docs/CI.md
    Purpose: describe CI coverage, provisioning and trusted release execution.
    Responsibilities: distinguish hosted tests from desktop and hardware checks.
    This file does not claim a workflow passed before its logs are reviewed.
-->

# Continuous integration

`native-linux.yml` builds pull requests, `main` and version tags on disposable
GitHub-hosted Linux runners. Its Ubuntu 26.04 container matches the published
FreeBASIC 1.20.4-3 package ABI. Four package downloads are SHA-256 verified
before installation. The job checks the tracked source boundary and archive
and dependency corruption fixtures, compiles the
whole editor with all warnings enabled and runs the deterministic Linux suite.
Build and test logs are retained for fourteen days.

The hosted job does not have a physical MIDI device, speakers, microphone or
authenticated desktop. It does not establish GUI frame pacing, physical audio,
Android device operation or the Windows toolchain lock.

`windows-release.yml` is manually dispatched from `main` and needs an
interactive self-hosted Windows x64 desktop labelled `opensesh-release`.
Use Actions Runner 2.327.1 or newer for the pinned Node.js 24 actions.
Configure the supported compiler at `C:\FreeBASIC\fbc.exe`, the corrected
fblint at `C:\fblint\fb_linter.exe`, and Python 3.9 or newer on PATH. See
LINTING.md for the validator regression and exact reviewed identity. Verify
the compiler lock before running the complete release gate.

The runner must execute as the desktop user because frame-pacing checks measure
real visible presentation. Do not add a pull-request trigger to this workflow.
Review and merge changes before dispatching; neither a public fork nor an
arbitrary revision should execute on a trusted workstation. Evidence is written
outside the checkout and uploaded with the exact commit identity.

Action versions are pinned to commit hashes. Validate workflow edits with
`actionlint`; `.github/actionlint.yaml` declares the custom runner label. A
locally valid workflow and a local build remain different evidence from a
successful GitHub run. Inspect the full run logs before tagging a release.

<!-- end of docs/CI.md -->
