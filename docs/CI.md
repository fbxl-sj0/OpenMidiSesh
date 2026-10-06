<!--
    Project: OpenSesh
    File: docs/CI.md
    Purpose: describe CI coverage, provisioning and trusted release execution.
    Responsibilities: distinguish hosted tests from desktop and hardware checks.
    This file does not claim a workflow passed before its logs are reviewed.
-->

# Continuous integration

`platform-packages.yml` runs on public branches, pull requests and version tags.
All builds execute on disposable native hosts or full native OS guests, including
the Haiku desktop. Nothing runs public contributions on a trusted workstation.

| Archive | Native qualification host | Runtime requirements |
| --- | --- | --- |
| Windows x86_64 ZIP | Windows Server 2025 | 64-bit Windows 10 or newer |
| Linux x86_64 tar.gz | Ubuntu 26.04 | glibc 2.43, X11, ALSA, PulseAudio client and terminfo libraries |
| FreeBSD x86_64 tar.gz | FreeBSD 15.1 | X11 desktop and base ncursesw/terminfo libraries |
| NetBSD x86_64 tar.gz | NetBSD 11.0 | Base X11 sets and pkgsrc ncurses (`libncurses.so.6`) |
| OpenBSD x86_64 tar.gz | OpenBSD 7.8 | Base system and X11 sets |
| Haiku x86_64 tar.gz | Haiku r1beta6 | Native desktop, ncurses6, fixed editor window |

Each archive contains runtime installation commands in `README.txt`, also
recorded in its build evidence. No compiler is needed to run the executable.
The requirements were checked against native executable library imports;
review them whenever the pinned compiler or target OS changes.

The public FreeBASIC 1.20.4 packages are pinned by name, length and SHA-256 in
`tools/ci_toolchains.toml`. BSD and Haiku use `midi_null.bas`, which explicitly
reports unavailable external MIDI endpoints. Editing, software synthesis and
file exports remain available. No separate original BeOS package is built.
The pinned Haiku runtime initializes resizable windows at 1x1, so the editor
uses a fixed window there. Native CI still requires the complete GUI audit
and framebuffer checks. Enable resizing only after qualifying a newer runtime.

Each job checks source integrity and archive/download failure fixtures, compiles
with all warnings enabled, and runs the deterministic native tests. The Windows
hosted profile uses `-CoreOnly`; its public compiler archive is hash-verified and
the same fourteen linked toolchain inputs are checked against a generated lock.
The default Windows test profile still includes desktop timing and reviewed pixels.

Every package job launches the real editor in Desktop and Touch modes, checks
648 control contracts, 1016 behaviors and 140 retained-score rendering checks,
and captures a native framebuffer. The score checks compare moving and hidden
tool cursors with fresh pixels on both work pages and test note removal near
the header boundary.
It repeats those checks with the executable extracted from the verified package.
Linux and BSD use Xvfb; Haiku uses app_server. These checks do not certify physical
presentation timing, devices or human accessibility. Diagnostics are retained for
fourteen days; only passing jobs upload packages.

A tag release requires all six jobs to pass. The publisher verifies every package
hash and source commit, requires identical corresponding-source hashes, and
publishes archives, per-target evidence, `CI-SUMMARY.json` and `SHA256SUMS.txt`.
It never replaces an existing release. Package revisions can retain the same
application version; the release notes identify both versions explicitly.
Each archive includes GPL/LGPL license text, notices and the complete reviewed
corresponding source. SoundFonts and personal recordings are user supplied.

Provisioners refuse execution outside GitHub Actions. They use ephemeral guest
package managers and private compiler staging, never the developer's C:\FreeBASIC.
Python 3.11 or newer is required for the package tools. Windows provisioning
deletes the large compiler download after extracting it and does not retain a cache.

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
