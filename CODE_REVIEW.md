<!--
    Project: OpenSesh
    File: CODE_REVIEW.md
    Purpose: Record the September 2026 correctness review and its evidence.
    Responsibilities: Describe confirmed defects, repairs, coverage, and limits.
    This file does not certify third-party redistribution or untested hardware.
-->

# Code reviews, September 2026

The review covered the application, document and history models, MIDI and
audio boundaries, score and mixer helpers, input handling, dependency identity,
and build and release scripts. Static analysis covered 199 FreeBASIC source
and include files, including the tests and 54 vendored omaGui source files.
Manual review concentrated on parsing, state restoration, event scheduling,
resource ownership, and the recent drum, meter, and note-editing workflows.

## Confirmed defects repaired

| Area | Defect and resulting correction |
| --- | --- |
| MIDI import | Running-status events reused their first data byte without advancing the file cursor. Valid files could load incorrect notes and controllers. Both message lengths now consume that byte correctly. A fixture covers all seven channel-message families and a save/reload round trip. |
| SoundFont resolution | Preset and instrument generators were combined with the wrong precedence. Local values now replace globals at their own level, preset offsets add to instrument values, and their key/velocity ranges intersect. Fine and coarse sample offsets remain separate until resolution. |
| SoundFont percussion | A later layer of a stereo drum note could choke the layer just started. Exclusive-class choking now finishes before any layers of the new note are allocated. |
| SoundFont velocity | Rounding could select the next velocity zone, and the forced-velocity generator was discarded before rendering. Exact velocity boundaries and per-region velocity overrides now reach the synth. |
| SoundFont lifecycle | Resuming after a worker failure could replace an unjoined thread handle. Restart now closes and joins the previous output worker first. Sample loading also checks read completion before committing the bank. |
| External MIDI stop | All Notes Off alone left pedal-held notes sounding. Both native backends now release sustain and sostenuto, send All Notes Off, and send All Sound Off, stopping immediately if the endpoint fails. |
| Pitch transcription | Damaged WAV lengths, duplicate format chunks, inconsistent PCM frame sizes, and missing chunk padding were accepted. The reader now rejects them before decoding and checks file-read completion. |
| Source packaging | The drum-phrase test and twelve current Windows visual baselines were missing from the archive. They are included, and packaging now checks that maintained source, test runners, and visual baselines appear in its explicit manifest. |
| Release verification | Windows, Linux, and sanitizer checks retained obsolete test and UI totals. Their expectations now match the current suite. Release lint explicitly selects maintained source and excludes generated build trees. |
| Dependency identity | The omaGui backend differed from its recorded hash. Comparison with the matching archived source identified the existing RISC OS and AROS platform changes. Those changes were reviewed and documented, and the hash now identifies the retained source. |

The MIDI, SoundFont hierarchy, and WAV regression tests failed against the
previous implementations and pass after the fixes. The SoundFont fixture also
checks stereo PCM output and exact velocity-zone selection. The MIDI stop
test covers sixteen channels, two receiver capability models, and failure at
each of the 64 send positions.

The SoundFont hierarchy follows sections 8.5 and 9.4 of the
[SoundFont 2.04 specification](https://www.synthfont.com/sfspec24.pdf). The stop
sequence uses the standard pedal and channel-mode assignments in the
[MIDI control-change table](https://midi.org/midi-1-0-control-change-messages).

## First-pass verification, 2026-09-08

- Linux: 54 ordinary tests passed, followed by 55 tests with FreeBASIC runtime
  checks, AddressSanitizer, UndefinedBehaviorSanitizer, and ALSA loopback. The
  instrumented editor also passed its 468 behavior checks and 324 control
  contracts without a sanitizer error.
- Linux UI: 21 screenshots, 27 process launches, desktop and touch control
  audits, and all eight frame-pacing cases passed. The refreshed screenshot
  hashes were checked after retrieval and the main and drum views inspected.
- Windows: all 49 visual comparisons and both 468-check UI behavior audits
  passed, as did 60 GUI lifecycle launches and 25 audio lifecycle launches.
  The suite passed 61 of 62 tests. Its remaining failure is the touch
  interaction timing gate: accepted measurements reached about 30.6 ms at
  the 99th percentile against a 25 ms limit. Drawing work remained below
  6 ms. The frame-timing thresholds have not been relaxed.
- Static analysis: all 199 source/include files passed without errors.
  Windows has no maintained-source warnings and 47 existing dependency
  warnings. Linux has 861 reviewed portability findings in maintained
  source and 365 in the dependency. The exact per-file/rule fingerprint is
  recorded in `portability_lint_baseline.txt`; unexpected changes fail release
  verification. All 18 maintained PowerShell scripts and seven shell scripts
  passed syntax parsing. The dependency verifier passed all 57 payload files.
- Source packaging: a deliberately unlisted source file in an isolated
  extracted archive was rejected before an output archive was created.

Two Windows presentation alternatives were staged outside the maintained
source tree. Explicit cadence with page swapping made idle timing worse and
was rejected. A fixed work-page copy variant could not obtain the required
five-second compiler-free window within the runner's 300-second bound. Neither
experimental renderer was adopted during that pass. The Windows touch timing
gate remained unresolved, so that run did not qualify as a complete
release-verification pass.

Detailed results are retained under `build/code-review-final`,
`build/review-linux-ui`, and the `build/review-*.txt` logs. These are generated
review artifacts, not source-release inputs. The Linux run used an isolated
temporary directory on Midcom with FreeBASIC 1.20.4-1; it did not replace the
installed Linux editor.

The retained sanitizer summary still prints the previous 279-control total.
Its actual `sanitized-control-report.txt` records 324 controls and 468 behavior
checks. The summary constant was corrected after that successful run.

The pre-change workspace was copied to the location recorded in
`build/review-backup-path.txt` before editing.

## Follow-up review, 2026-09-09

The follow-up reviewed the current tree, with additional attention to failed
operations, sustained playback, binary I/O, native frame timing, and stale
verification documentation. The maintained tree now contains 202 FreeBASIC
source/include files, including the same 54 vendored source files.

| Area | Defect and resulting correction |
| --- | --- |
| Note clipboard | Capture copied notes before validating the whole selection. A later stale index left new notes paired with the previous clipboard's timing and track origins. Capture now validates the complete selection before replacing any stored notes. A rejected copy preserves a usable previous phrase. |
| Sustained notes | Both transport timing and the built-in synth cut notes off after eight seconds. Notes now retain their scored duration, bounded to one hour per voice. The MIDI-to-PCM regression renders a ten-second note and checks for audible PCM after nine seconds. |
| WAV export | The native saver truncates its output and can fail after a partial write. Export now saves beside the destination and atomically replaces it only after successful saving. Fault injection proves preservation of the previous file, recovery after failure, rejection of a directory destination, and cleanup of temporary files. Invalid paths and NaN durations are rejected before capture starts. |
| Binary reads | Several readers ignored read results, and checking GET's return code alone still accepts a short read at EOF. A shared private helper checks both status and the actual transferred byte count for MIDI, audio inspection, pitch transcription, SoundFont fields and samples, preferences, atomic-file verification, and project recovery. Its real-runtime test covers scalar, array, and string reads, EOF, short reads, invalid spans, and closed handles. |
| Playback clock | Subtracting two infinite clock inputs produced NaN even after the original input checks. The elapsed-time boundary now rejects that result; note-duration calculation and synthesis also reject NaN inputs. |
| Windows presentation | A local probe measured a requested 10 ms sleep at approximately 15.6 ms under the default timer resolution. The legacy backend now requests millisecond sleep precision for the window lifetime and includes rendering in the shared 60 Hz frame budget. Successful timer requests are paired with release during shutdown or reinitialization. Headless mode and gfxlib3 keep their existing paths. |
| Verification tooling | The timing runner can select named scenarios with the same thresholds and sample requirements. Invalid or repeated names fail before output creation. Default release runs still exercise the complete matrix. Test dependencies, suite totals, archive inputs, and the README's visual count were updated. |

The clipboard, sustained-note, and partial-WAV regressions each failed against
the previous implementations and pass with the repairs. The exact-read helper
uses the actual byte-count output of FreeBASIC GET; its contract follows the
compiler's file-I/O parser and runtime implementations. The Windows timer
lifecycle follows Microsoft's
[timeBeginPeriod documentation](https://learn.microsoft.com/en-us/windows/win32/api/timeapi/nf-timeapi-timebeginperiod).

The expanded Linux suite passed 57 tests with runtime checks, AddressSanitizer,
UndefinedBehaviorSanitizer, and ALSA loopback. Its instrumented editor passed
468 behavior checks and 324 control contracts. This run includes the shared
exact-read helper and every caller. A subsequent Linux build with the final
backend also passed the same GUI audit.

Windows passed 63 of 64 tests, including all functional regressions, both
468-check desktop and touch audits, all 49 visual comparisons, 60 GUI lifecycle
launches, and 25 audio lifecycle launches. The only incomplete gate was the
timing matrix: the compiler/linter contention guard reached its 300-second
limit. The initial full-suite attempt overlapped review linting. A final
standalone attempt after all review compilers, linters, and other tests had
finished also reached the 300-second limit while unrelated compiler jobs
continued. It produced no accepted measurements. The complete timing gate
remains unverified, so this is not a complete release-verification pass.

Before promotion, the timer candidate passed two uncontended 480-frame idle
measurements in each of Light, Dark, and Black themes, at approximately
59.8 to 60.0 FPS with 99th-percentile intervals of 16.7 to 17.7 ms. These six
measurements support the idle improvement; they do not certify the remaining
interaction, playback, or full-HD scenarios. Acceptance thresholds were not
changed.

Both strict lint targets scanned all 202 source/include files without errors.
Windows has zero maintained-source warnings and the same 47 dependency
warnings. Linux has 862 reviewed maintained-source portability warnings and
365 dependency warnings. The updated per-file/rule fingerprint passed exact
comparison. New ownership documentation and focused test cleanup resolved
the additional maintained-source Windows findings. All 18 PowerShell scripts
parsed successfully, and all 57 dependency payload files passed verification.

The verified Windows executable replaced `opensesh.exe`; the previous build
remains in the follow-up backup. PE and embedded-manifest checks passed,
including the restricted DLL import list, ASLR/NX flags, and ordinary-user
execution level. Its installation hash is recorded in
`build/review-second-installation.txt`.

The source archive is
`build/OpenSesh-source-review-second-20260909-final.zip`. Its entry-by-entry
comparison with the maintained source tree is recorded in
`build/review-second-source-verification.txt`.

The follow-up backup is recorded in `build/review-second-backup-path.txt`.
Its reproduction, build, lint, and native UI logs use the `build/review-second-`
prefix. Linux ran in another isolated temporary source tree on Midcom.

## Boundaries

This is a correctness review with automated and manual evidence, not proof
that every possible input or device is covered. Android, AROS, and RISC OS
were not run during this review. The SoundFont renderer retains its documented
subset of synthesis features; this work does not add full SF2 modulation or
filter support. The sfxlib redistribution provenance gate in
`DEPENDENCIES.md` remains open.

<!-- end of CODE_REVIEW.md -->
