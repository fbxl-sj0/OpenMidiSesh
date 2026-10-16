<!--
    Project: OpenSesh
    File: docs/RELEASE_CHECKLIST.md
    Purpose: List the checks required before publishing a package.
    Responsibilities: tie release artifacts to their source, evidence and licenses.
    This file does not approve an unverified release.
-->

# Release checklist

Use a clean checkout and verify the exact commit that will be tagged.

## Source and build

- Run <code>python tools/check_repository.py</code> and confirm the source
  manifest, documentation links, and omaGUI snapshot are valid.
- Verify the Windows compiler identity with
  <code>tests/verify_windows_toolchain.ps1</code>.
- Run the strict Windows and Linux lint scopes. Require accepted semantic
  models, no unavailable scopes, no operational errors, and no warnings.
- Run the native Windows and Linux build and regression workflows. Review the
  complete workflow logs for the exact commit.

## Packages and publication

- Build each package from the reviewed source and verify its executable,
  corresponding source archive, license notices, and SHA-256 checksums.
- Confirm that the published version and supported platform notes match the
  included artifacts.
- Keep release files immutable and do not replace an existing release.
- Describe unsigned builds and device-specific limits accurately. Do not claim
  physical MIDI, microphone, audio, Android, or accessibility support without
  evidence from the corresponding target.

Windows package verification is driven by <code>verify_windows_release.ps1</code>.
Platform package jobs and their limits are described in [CI](CI.md). Android
has a separate development packaging path and no native external MIDI adapter.

<!-- end of docs/RELEASE_CHECKLIST.md -->