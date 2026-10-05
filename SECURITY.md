<!-- Project: OpenSesh; File: SECURITY.md; Purpose: vulnerability reporting. -->

# Security

OpenSesh opens untrusted MIDI, project, audio, and SoundFont files. Reports of
out-of-bounds access, arithmetic overflow, unexpected file replacement, unsafe
allocation, and resource-lifetime failures are useful even when they require a
malformed input.

For a vulnerability, use the repository's private vulnerability reporting
feature when available. If private reporting is unavailable, open an issue
requesting a private contact route without attaching an exploit or private
recording. Ordinary bugs belong in a public issue.

Include the application version, operating system, build or commit identity,
minimal reproduction steps, and the smallest shareable input. Describe the
observed impact and whether the failure occurs with a fresh configuration.
Do not include credentials, personal recordings, or third-party SoundFonts
without permission to redistribute them.

During the pre-1.0 development period, fixes target the current development
branch. Older development snapshots do not have a separate maintenance promise.

<!-- end of SECURITY.md -->
