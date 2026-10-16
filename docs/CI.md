<!--
    Project: OpenSesh
    File: docs/CI.md
    Purpose: Summarize automated build and package coverage.
    Responsibilities: describe the native workflows and their limits.
    This file does not claim that unreviewed or local changes passed CI.
-->

# CI and releases

The repository has three GitHub Actions workflows:

| Workflow | Purpose |
| --- | --- |
| <code>platform-packages.yml</code> | Build, test, launch, and package Windows, Linux, FreeBSD, NetBSD, OpenBSD, and Haiku x86_64 releases on native hosts. |
| <code>native-linux.yml</code> | Build the Linux editor and run the native Linux test suite on pushes, pull requests, and version tags. |
| <code>windows-release.yml</code> | Run the full Windows release gate when a maintainer manually dispatches it from <code>main</code> on the trusted desktop runner. |

The package workflows build from the source tree, run deterministic regressions,
and launch the packaged editor. Linux and BSD UI checks use virtual displays;
Haiku uses its native desktop. A successful package job is required before
that workflow uploads a package.

CI does not have physical MIDI hardware, speakers, microphones, or a real
Android device. Its GUI checks cannot establish physical-device audio,
screen-reader compatibility, or human accessibility. See
[Dependencies](DEPENDENCIES.md) for per-platform feature boundaries and the
[release checklist](RELEASE_CHECKLIST.md) for publication requirements.

<!-- end of docs/CI.md -->