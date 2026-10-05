# OpenSesh frontier review - 2026-10-02

The final reviewed application passes its functional and visual checks on Windows.
It is **not approved for release**: preserved release gates and platform limits are
listed below. The full Windows suite and native/Android builds use the exact final
production source. Three later test-only follow-ups were individually rebuilt and
rerun; their scope is explained below. Final strict lint and packages use the entire
final snapshot. No publication, push or deployment occurred.

## Scope and reproducibility

The project is `E:\Midisoft\midisoft-fb`; `C:\fblint` is the authoritative linter
source/tooling tree. Neither initial tree contained Git metadata, so no branch,
HEAD or Git-clean claim is made. Original source hashes and bytes are retained.
The cumulative application change set is 175 changed/new files;
phase three changes 74 code/test files within that set. Exact paths and original,
phase-two and final hashes are in `build/frontier-review-20261002/review-work/phase3/changed-files.json`
and its CSV companion. Final documentation hashes are refreshed before packaging.

Evidence below is relative to `build/frontier-review-20261002/review-work`.
`phase3/final-release-inputs.json` freezes 233 build, test and lint inputs;
all 304 source-package entries are separately checked. Original bytes, reviewed
patches, reverse checks, command receipts and disposable fixtures remain available.
Concurrent app bytes were guarded at every application step. No local memories,
unrelated project, infrastructure or personal compositions were edited.
All explicit review scratch and temporary files use E: after the documented early
staging relocation. Earlier staging/key cleanup incidents remain documented in the
preserved phase-two report; no new credential was retained.

Three independent reviewers were explicitly selected as `gpt-6-astra` with maximum
reasoning effort. The lead runtime's exact model identity is not exposed by these
tools; a local default is not treated as proof. No silent model downgrade was made.

## Application changes

- Preserve imported same-tick MIDI setup/sustain/note ordering, FIFO overlapping
  note velocities, and end-of-track silence through edits, history, and reload.
- Rebuild tempo, time/key signature, channel, and text caches after track removal.
- Use the shared verified atomic writer for MOD export. Failed replacement
  retains the destination and removes temporary output.
- Prepare audio-project loads without evicting undo entries or clearing redo;
  failed MIDI loading restores content, full history, and dirty state.
- Restrict recovery backup names to owned decimal process/counter suffixes and
  reject Windows case-only destination aliases before recovery writes.
- Preserve PC keyboard key-up transitions in the Keys window.
- Close SoundFont raw output again after joining its renderer, covering a
  pending write that can reopen output after the first close.
- Capture the input backend clock before recording's first event, preserving
  initial silence and handling DWORD wrap, stale timestamps, and zero elapsed time.
- Retain repeated strikes under sustain and count completed notes correctly for
  dirty-state updates. Synthetic recording tests avoid hardware/audio output.
- Send bank MSB and LSB before the initial MIDI Program Change; fake-receiver
  tests cover all 144 setup-message failure positions.
- Reject NaN in all four pitch-transcription configuration fields before arithmetic.
- Select 1x/4x speed while stopped. Playback, pause, recording, and drum loops
  reject speed/global-tempo changes; rejected tempo controls revert. Play and
  selected-note audition retain the chosen speed.
- Require 1x for full-song playback containing WAV clips. A shared scheduling
  guard also stops fast full-song playback if clips appear later. Selected-note
  audition retains 4x. Rejection does not mutate document history.
- Stop generated SOUND/NOISE at transport and selection-loop boundaries, under
  the runtime's recursive mixer lock. The exported C functions use 32-bit `Long`
  parameters and platform guards. These exports are a verified runtime dependency,
  not documented BASIC STOP keywords or a promise of a stable public API.
- Stage Android version metadata in disposable template copies. The version name
  comes from `src/version.bi`; an explicit validated version-code parameter supports
  upgrades. Original templates and absent/empty/nonempty environment values are
  preserved, subject to the host PowerShell's empty-environment support.
- Fix the release verifier to hash the selected compiler rather than a neighboring
  `fbc.exe`; require its lock entry and reject case/dot path aliases.
- Correct six headers, remove obsolete suppression IDs, update test/package
  expectations, and document the shell wrapper's actual Linux/ALSA target.

Four new defect regressions fail against original code and pass with fixes:
MIDI ordering/tails, MOD replacement failure, recovery-journal validation, and
the SoundFont close race. A further null-renderer regression exposes sample-only
Stop leaving generated PCM, verifies immediate silence and channel isolation,
and proves concurrent exclusion. Removing the new lock makes that regression
fail; the production helper passes. Full undo/redo-ring and NaN checks also pass.


The second pass adds checked copyright/SPDX/target metadata, 93 meaningful API
headers, and explicit rationale markers on existing suppression comments. No new
selector was added; final strict lint ignores all suppressions. It expands 94 inline
branches, makes 35 existing public definitions explicit (including continued
signatures), and uses equivalent small hexadecimal masks at 56 flagged lines.
All 64 mask tokens preserve their value and compiler literal category. The meter
calculation now consistently uses an unsigned 64-bit denominator. Three newline/
terminal-blank findings and stale compiler wording are corrected. Reverse edits,
source-body comparisons and hashes record the bounded scope.

Vendor changes affect only leading comments in four generated font includes and
`theme.bas`. Glyph data, pointer initializers, code and license notices are byte-identical.
Five of 57 payload hashes were refreshed. The retained-patch note documents absent
font-generator inputs and does not claim regeneration. Snapshot/license checks pass.

Phase three completes the reviewed maintained-code layout/API cleanup, removes
three unreferenced private wrappers and unused/pass-through private parameters,
and preserves external callbacks and ABI signatures. Twenty-eight guarded batches
record 2,138 focused warning removals and
92 passing test executions. These include 11 stub-visibility
findings exposed only by a selected-rule scan and one unused test parameter;
they are not blindly subtracted from the earlier whole-tree total. Ten targeted
private-helper diagnostics were left for the final full count rather than claimed
from an unrun focused scan. No new suppressions or disabled rules were introduced.

The first complete phase-three scan measured 49,315 warnings and exposed one new
compiler-model failure in `tests/ui_style_smoke.bas`. The compiler's own schema 20
reader independently rejected a generated label without completed type metadata.
A local-value rewrite did not repair that exporter defect and was discarded.
Restoring only the original one-line If/Return restored valid required semantics;
the Swap block remains. This intentionally retains one `STYLE004` advisory and
restores five existing `NUM022` advisories. It is a source compatibility fallback,
not a relaxed consumer check or a claim that the compiler defect is repaired.
See `phase3/owners/linter/ui-style-semantic-regression01/final-diagnosis.json`.

Two malformed-file fixture headers now state ownership accurately: writers close
handles; callers own fixture cleanup. Each replaces one blank header line, with
identical line counts and byte-identical post-header bodies. The three affected
fixtures were rebuilt and passed after application, including 102 contrast checks.
All 230 other build/test/script inputs, every production source and all product
artifacts retain their verified hashes. The original full-suite input manifest is
preserved as `phase3/final-source-inputs.json`; `phase3/final-release-inputs.json`
and `phase3/release-followup/result.json` connect that evidence to the final snapshot.
The later full scan is measured directly; the earlier 49,315 result is retained.

The large main-file formatting batch did not produce an identical object. That
failed equality check is preserved. Independent inspection accounts for all 389
functions: 382 differ only through relocation addresses, and seven have explained
layout, register-allocation or padding changes totaling 64 fewer code bytes.
Symbol bindings and callback targets remain unchanged. Limited CFG comparisons use
explicit documented normalizations, not a formal all-platform equivalence claim.
The actual desktop/touch contracts and final 49-image visual comparison pass.
See `phase3/owners/playback/object-review/root-main-combo-object-review.json`.

## Linter improvements and integration hold

The initial installed linter was 1.0.0 / ruleset 2026.10.020. Final verification uses
an isolated, frozen candidate built from the captured review source,
retaining 509 rule IDs. Candidate SHA-256:
`D426BF8C3C8F147695A69360E304D121E0521DFA14E93D5811F4D6F4C7C44300`.
Concurrent canonical work was observed at ruleset 2026.10.026 and advanced to
2026.10.028 at the final read-only comparison. The tested candidate has not
overwritten that newer tree or executable. The stable 40-path comparison and
current source/executable hashes are in `phase3/canonical-linter-observation.json`. This report certifies the
isolated candidate, not the untested combined canonical version.

General improvements contain no project-name exceptions:

- `FBL-IO-005`: built-in function-form output opens; temporary-name heuristics apply
  to the filename. Comments, strings, members, device syntax, macros and unsupported
  spans retain conservative handling.
- Suppression parsing stops before rationale prose; incidental `all` is no blanket
  exemption. Real `ALL`/`*` and documented selector forms remain supported.
- `FBL030`: exact basenames after relative paths in standalone footer comments;
  reject wrong-file suffix/prefix traps and executable strings.
- `FBL404`: logical integer declarations and explicit integer conversions; bounds-only
  division and quoted text are not initializer evidence.
- `FBL-ARR-007`: compiler-bound fixed/dynamic/descriptor evidence; prose is no exemption.
  Multiple ERASE/REDIM operands retain evaluation order; uncertain facts remain conservative.
- `FBL-DOC-FILE-007`: actual outward declaration boundaries; private-only bodies do not
  inherit an API requirement just from included public headers. Unknown visibility and
  declaration macros remain conservative.
- Precedence retention: preserve pointer dtype/subtype in a distinct category, excluded
  from integer-only advice; reject invalid or unknown types.
- Nested-shadow ownership: exclude only validated compiler-generated global initializer/
  destructor spans. Source declarations override the exemption; unknown origin/status
  and real source overlaps still fail. Other consumers retain original procedure spans.
- `FBL-IO-004`: recognize an evaluated, compiler-proven function-form Close of
  the same unchanged owned handle. Short-circuit, branch/loop, macro/member,
  mismatched-handle and unknown-model controls retain conservative warnings.
- `FBL-NUM-013`: recognize a plain local floating variable's same-symbol `x <> x`
  NaN guard. Ordinary equality, distinct operands, ByRef/shared/static/call/indexed
  or unknown-storage/type cases remain diagnosed. `FBL-NUM-038` remains active.

The candidate builds with `-w all` and an empty build log. All 16 existing suites,
74 earlier focused controls and 47 new diagnostic/model controls pass, plus 31 new
fixture parser checks. All 666 source hashes and both compiler identities remain
unchanged. Existing suites include target-model, malformed-model, native behavior,
exact-location/negative and bounded concurrency checks. Target-model tests do not
mean native Linux execution. Deliberately malformed fixture compiler warnings are
preserved. See `phase3/owners/linter/verification/full01/verification.json`.

A separate strict self-check of the seven cumulatively changed production files
completed with **five diagnostic errors, 828 warnings and exit 2**. The main linter
root could not obtain required compiler semantics; six include-only headers were
skipped. This scan is separate from application counts and does not establish
complete linter-source cleanliness. The five errors were header-policy omissions:
three newly introduced fields in `fb_linter_declaration_policy.bi`, and two
unchanged baseline exclusions labels in other headers.

A separate comment-only three-header overlay addresses those errors without
changing any byte after the leading comments. Its measured strict comparison is
five errors/110 warnings before and zero errors/110 warnings after. An identical
small anchor root supplies accepted compiler semantics and adds two unchanged
warnings to both commands; the headers remain include-only. Both commands exit 1.
No original receipt, frozen implementation source or candidate binary was changed.
The full combined self-scan was not rerun; do not infer global cleanliness by
subtracting these results. Apply the overlay during the eventual canonical merge.
See `phase3/owners/linter/self-lint/attempt01/receipt.json` and
`phase3/owners/linter/header-followup/validation02/receipt.json`.
The current delivery index is `phase3/owners/linter/current-linter-delivery-summary.json`;
the earlier summary remains preserved as historical evidence.

The byte-exact phase-three delta is in
`phase3/owners/linter/exports/phase3-delta`, with 40 deliverable paths (35 new/five
modified). The final recorded comparison found that all five existing canonical
files differ from both review base and proposal; a three-way merge is required. Earlier reviewed fixes remain in
`../review-patches/fblint` and `../review-patches/fblint-phase2-complete`.
Do not copy the 509-rule review catalog over newer canonical additions. Merge,
regenerate catalog/docs and rerun combined verification before installation.
The three-header overlay is in `phase3/owners/linter/header-followup`; it applies
after the exported implementation patches. The cumulative implementation exports
cover 90 distinct paths; the header overlay touches three of those same paths.

## Strict lint baseline and final result

The policy is identical across full scans. Working directory is each isolated
source tree's `vendor/omaGui`; generated artifacts are outside the input tree.
The final invocation uses the above candidate with these settings (paths
abbreviated here):

```text
--no-config --profile strict --select FBL --target windows --no-suppressions
--strict-headers --strict-tabs --max-nesting 8 --fail-on-warning
--require-semantic --compiler C:\FreeBASIC\fbc.exe --format jsonl --timings
--output-file phase3-release-strict-windows.jsonl <phase3/work/app>
```

These are discovered supported options, not invented strictness settings. All
rules and severities remain enabled; suppression comments are ignored. Raw JSONL,
per-rule/per-severity CSVs, complete commands and hashes are retained.
`strict-arguments.json` preserves the original argument vector and
`baseline-settings.txt` the resolved baseline settings, including no config,
no ignored/excluded rules or paths, unlimited warnings, four-space indentation,
400-column lines, 280-line routines, 1,000-line modules and nesting limit eight.
`run-phase3-release-lint.ps1` and `phase3/final-release-lint-run.json` record the final invocation,
source/output paths and immutable tool identities.

| Full input scope | Initial | Phase-two checkpoint | Final phase three |
|---|---:|---:|---:|
| FreeBASIC files |202|206|206|
| Diagnostic errors |51|0|0|
| Warnings |52,175|51,422|49,319|
| Informational |1|1|1|

| Warning ownership | Initial | Phase two | Final |
|---|---:|---:|---:|
| maintained | 3,905 | 3,153 | 1,050 |
| vendor | 48,269 | 48,268 | 48,268 |
| external-toolchain | 1 | 1 | 1 |

Common maintained-input warnings fall from 3,905 to 1,048;
new maintained inputs contribute 2. The four added
FreeBASIC inputs are explicitly separated in `phase3-release-lint-comparison.json`;
`phase3-release-lint-rule-comparison.csv` contains every rule/severity delta. The final
count is measured directly; it is not an arithmetic estimate from batch counts.

A historical coverage caveat remains: 29 earlier `src/music_export.bas` numeric
findings disappeared when the corrected atomic writer brought in `windows.bi`
and required compiler-model export became unavailable. This comprises the 28
previously documented findings plus one `NUM029` on an unchanged decimal-mask
expression. The original and reviewed rule helper/emission gate are identical;
unavailable compiler facts explain the disappearance. This is coverage loss, not
a demonstrated quality improvement. The phase-two coverage receipt also records
`tests/music_export_smoke.bas` changing from accepted to compiler-failed. Final
semantic coverage is reported separately below. See
`phase3/owners/io/music-export-numeric-coverage-loss.json`.

Most remaining whole-tree warnings belong to bundled omaGui. Its code and font
data are retained to keep upstream provenance and future merges reviewable; the
small metadata corrections have separate body-hash proofs. Those vendor findings
remain in the raw report and per-rule CSV for future upstream maintenance. Their
presence is not treated as proof that the vendor code is defect-free.

Remaining maintained diagnostics are listed in full below. Opt-in numeric,
style/structural and explicit-read advice is retained where a mechanical change
would add casts, conflict with another selected preference or disturb a valid ABI,
range convention or deliberate side effect. In particular, LOOP014/015 express
opposing STEP 1 preferences. No blanket false-positive classification or suppression
was used. Detailed source evidence is in `phase3/owners/io/numeric-advice-residual-review.json`
and `phase3/owners/playback/residual-diagnostics-review.json`; every remaining
finding is preserved in raw output. The numeric pass screened all 461 earlier
expressions across 43 files, with surrounding context for all 33 cast sites and
deeper divisor/index/DSP checks. This is bounded review, not an exhaustive
interprocedural range proof. The mixed pass reviewed 195 findings and led to the
private-helper/test-parameter cleanup; no additional reachable runtime defect was
confirmed. Numeric rationale: NUM009 concerns naming valid domain literals;
NUM015 covers intentional cyclic/index remainder arithmetic; NUM022 covers DSP,
timing and geometry arithmetic; NUM024 covers bounded conversions and deliberate
sample/pixel quantization; NUM027 covers layout/index rounding and overflow limits.
The follow-up audit reviewed three newly exposed naming advisories on unchanged
SoundFont key/velocity/root-key bounds. It also verified 33 additional `DATA004`
findings across 24 routines: their ByVal assignments already existed and deliberately
normalize local copies. Return values, ByRef outputs or module state carry results;
no caller-writeback defect was found. `Session_DrawScore` crossed the 280-line
advisory threshold through block expansion (263 to 286 code lines). One newly
visible `IO014` points to guarded audit-fixture cleanup after successful atomic
save; its unchecked Kill result is a small existing cleanup-reporting gap, not an
unguarded production deletion. These findings remain visible. See
`phase3/owners/playback/phase3-new-data004-review.json` and
`phase3/owners/io/numeric-advice-residual-addendum.json`.

| Rule | Final maintained warnings |
|---|---:|
| `FBL-API-001` | 7 |
| `FBL-API-004` | 6 |
| `FBL-API-006` | 4 |
| `FBL-CASE-010` | 6 |
| `FBL-DATA-001` | 4 |
| `FBL-DATA-004` | 52 |
| `FBL-DATA-005` | 2 |
| `FBL-DECL-016` | 12 |
| `FBL-DESIGN-001` | 34 |
| `FBL-DESIGN-003` | 4 |
| `FBL-DESIGN-004` | 4 |
| `FBL-DESIGN-005` | 3 |
| `FBL-IO-005` | 6 |
| `FBL-IO-014` | 2 |
| `FBL-LOOP-015` | 371 |
| `FBL-LOOP-016` | 5 |
| `FBL-METH-001` | 4 |
| `FBL-NUM-002` | 3 |
| `FBL-NUM-009` | 50 |
| `FBL-NUM-015` | 59 |
| `FBL-NUM-022` | 144 |
| `FBL-NUM-024` | 33 |
| `FBL-NUM-027` | 178 |
| `FBL-NUM-030` | 6 |
| `FBL-STR-013` | 1 |
| `FBL-STR-017` | 2 |
| `FBL-STYLE-004` | 1 |
| `FBL-STYLE-009` | 2 |
| `FBL110` | 2 |
| `FBL111` | 3 |
| `FBL301` | 7 |
| `FBL310` | 6 |
| `FBL311` | 14 |
| `FBL404` | 1 |
| `FBL514` | 5 |
| `FBL761` | 2 |
| `FBL911` | 5 |

Compiler-semantic coverage is 90 accepted roots,
40 required but unavailable/incomplete roots and
76 include-only headers. Final reasons: compiler-failed: 20, model-invalid: 20.
Strict lint exits 2 with 40
operational errors; required semantics are not disabled to obtain a clean exit.

Two installed FreeBASIC 1.20.4-3 binaries reproduce representative export failures:
a Print control exports/validates, while adding windows.bi parses but fails model
export. A binary-reader fixture exports class-7 labels missing completed metadata/
canonical relations; the compiler-owned independent schema 20 reader rejects it too.
See `phase2-compiler-comparison` and `phase2-semantic-label-proof.json`. These prove
representative defects, not one identical cause for every unavailable root.
No compiler source or installed toolchain was changed. Windows lint requests Win32
facts; the product build is Win64, whose native compiler lacks the model option.
Inactive platform branches and malformed models are not certified by this scan.

## Final verification and platform limits

The completed original-source Windows baseline recorded 62 passes and two failures
out of 64 checks, with all 49 visual comparisons passing. Its failures were the
release-toolchain lock and pacing blocked by compiler contention. The final suite
contains two additional regression tests; its pacing evidence includes a clean
threshold miss and is evaluated separately below. See `baseline-tests-working.log`
and `phase3/baseline-windows-summary.json`. The earlier unsuccessful invocation,
which encountered toolchain-path and temporary-directory errors, is preserved in
`baseline-tests.log`; it is not counted as the completed baseline.

| Check | Result |
|---|---|
| Windows suite |64 passed, 2 failed /66; 12.84 minutes|
| Later test-only follow-up |3 affected fixtures rebuilt and passed; production inputs unchanged|
| Reported failures |windows_toolchain_smoke Locked toolchain length differs: fbc.exe; ui_smoothness_smoke idle-black-1280x720 encountered compiler contention on all attempts.|
| Actual editor contracts |324 controls and 508 behaviors each in Desktop/Touch|
| Visual regression |49/49 pass; unchanged references|
| Lifecycle |60 editor launches and 25 default-audio launches checked by the full suite|
| Optional external fixtures |SoundFont compatibility and physical MIDI loopback compiled only; neither fixture ran|
| Native reproduction |Two byte-identical final builds; unsigned-development PE checks pass|
| Linter |16 existing suites +121 focused controls +31 parser checks pass|
| Windows native target |x86-64, FreeBASIC 1.20.4-1, actual Fastcom execution|
| Windows semantic target |Win32 model facts, FreeBASIC 1.20.4-3; incomplete as above|
| Linux approved checkpoint |Earlier 301-file snapshot: 57/57 core tests, native x86-64 build, FreeBASIC 1.20.4-1|
| Linux virtual MIDI checkpoint |Seven message families on verified unconnected virtual 14:0; no physical loopback|
| Final Linux source |Not transferred or runtime tested; expanded-payload authorization unresolved|

Final pacing did not pass. Light and Dark each obtained two accepted measurements.
Black had one accepted clean pass and one clean threshold miss (58.23 fps,
35.59 ms p99, 64.18 ms maximum, seven frames above 33.34 ms); three other Black
launches were contaminated by external compiler activity; one Light launch was
also discarded. Across ten launches there were five accepted measurements, one
clean miss and four contention discards. The terminal exception
summarizes the exhausted contention allowance and must not erase that clean miss.
Later interaction, playback and full-HD scenarios were not reached. Thresholds
remain unchanged. See `phase3/owners/playback/final-pacing-evidence.json` for exact
attempts and report provenance. No task-owned compiler was running during pacing.

Final executable SHA-256: `48A504DAEA4D01A6C1F1648E06C5C3AC59A207263DC5DD0FA46DA8590F622E75`.
The 14 release-critical native toolchain files retain the earlier reviewed hashes.
The preserved release lock specifies 1.20.2-14; selected fbc64.exe is 1.20.4-1.
The compiler and six runtime archives differ from that lock, while seven entries
match. `phase3/native-toolchain-identity.json` records exact hashes. The release
identity gate is not claimed to pass, and provenance is not invented to refresh it.

Android builds use FreeBASIC 1.20.4-1, compile API 24, minimum 21, target 35,
version 0.9.0-dev/code 1. Existing signing key and installed manifest template remain
unchanged; no APK was installed or run. Android external MIDI deliberately uses
the existing null adapter; software synthesis remains available.

| Android ABI | Verification | APK SHA-256 |
|---|---|---|
| armeabi-v7a | Build, signature and metadata pass; no device runtime | `0A4BB7FF3B03F7F6EDED7BB5ADB2E1B18DE5030FEA2DDB67C4FA410464812CDB` |
| arm64-v8a | Build, signature and metadata pass; no device runtime | `AC42635B34B8316524912CCAE073A91B83CAC5E16C72EB394F40B9BC02CD6D0D` |
| x86_64 | Build, signature and metadata pass; no device runtime | `D4343DA93665BE5262E252CEDA8204E57DD36473F45BE315A525A16484707BA7` |

Source/portable package results are in `../package-phase3/package-review.json`
because the source archive includes this report. Verification compares all source
bytes, corresponding source/notices, paths/duplicates, two independent source and
portable archives, and seven corrupt-package controls. Package approval remains
false. No release package was published or uploaded.

The earlier approved Midcom archive SHA-256 is
`2e8db9f291058539f8e44b7a0c9345dc27a922863a007a1d51c91f42fb3b6be8`.
It ran in the approved isolated directory with null audio. Later generated-stop,
speed and phase-three edits are not claimed Linux-runtime tested. Linux GUI and
sanitizers, Android runtime, physical MIDI latency/device loss, screen readers,
per-monitor DPI and long interactive sessions remain unverified. The shell wrapper
supports Linux/ALSA; other Unix targets are not claimed supported. The Windows
manifest is System DPI aware, not PerMonitorV2.

## Remaining release work

- Select the intended Windows release toolchain and establish dependency
  redistribution provenance before refreshing its lock.
- Repair demonstrated compiler model/export defects for complete required semantics.
- Merge the reviewed linter changes with current canonical work and retest the result.
- Test the exact final source on Linux and run Android device checks.
- Investigate the clean Black pacing miss and complete all scenarios in a quiet environment, preserving
  the existing thresholds. Earlier successful timing runs do not replace final checks.
- ALSA input timestamps are assigned when polled; long polling stalls can compress
  recording timing. The clock-origin correction does not provide kernel timestamps.

Automatic approval review rejected the expanded 304-file Midcom transfer because
explicit authorization covered the earlier 301-file payload. The later approval
again names that earlier payload. No broader transfer was retried or bypassed;
final-source Linux verification remains blocked by that scope distinction.


## Continuation verification (2026-10-03)

This dated update supersedes only the earlier statements in this report that the final UI smoothness run remained incomplete and that transfer of the reviewed 301-file payload had not been approved. It does not replace the historical 64/66 full Windows matrix, the earlier 301-file Linux checkpoint, or the release-toolchain lock.

The final-source Windows UI smoothness rerun passed all eight configured cases with the original test script and thresholds: idle Light, Dark and Black; Dark interaction and Touch interaction; Dark playback and Touch playback; and 1920 x 1080 idle Dark. The runner recovered one isolated threshold miss and one unrelated compiler-contention retry with later accepted measurements. This is an 8-case pacing pass, not a rerun of the complete release matrix. The tested UI executable SHA-256 was 54ED7BA39136155FE77B56514EEC81EEB985925B4693EE867EA6177CD4E63193.

The final strict Windows-source FBLint scan covered 206 FreeBASIC roots with zero diagnostic errors, 49,739 warnings and one informational finding. Its required-semantic result was 122 accepted, 8 unavailable and 76 include-only roots; it exited 2 under the unchanged fail-on-warning and require-semantic gates. The comparison baseline was 90 accepted and 40 unavailable roots with 49,319 warnings. The increase of 420 warnings came with 32 additional accepted semantic models; it was not removed by suppressions or weakened rules. Six unavailable roots were reproduced as single-file build-context failures: five omaGui implementation fragments that are included under OMAGUI_IMPLEMENTATION, and a project-transaction smoke test that requires its test define and companion modules. Two aggregate roots, src/omagui_runtime.bas and src/opensesh_unity.bas, remain model-invalid. A possible reader limit mismatch (the linter's documented 250,000 identity cap versus the schema producer's documented 1,000,000 model limit) has not been proven to cause those two models; their preserved sidecars were not available for diagnosis, and follow-up compiles were held during sustained unrelated compiler activity. No FBC change was made on that unverified hypothesis.

The linter's documented Windows semantic target maps to FreeBASIC win32, while the application release build targets x86-64 Windows. Therefore the strict scan remains an x86 semantic scan, not full ABI-matched x64 semantic verification. The installed compiler is FreeBASIC 1.20.4-3 at C:\FreeBASIC\fbc.exe, SHA-256 84E66418E27299F90F550536852C233301C76CFA7FCFB8BD1EEFBC1B394936A6. The pinned Windows release toolchain still has 7 of 14 identity mismatches, so no portable executable package was certified.

The user approved transfer and null-audio Linux testing of the earlier reviewed 301-file archive only. The verified Midcom SSH host-key fingerprint is still pending. The expanded final-source archive has 304 regular-file entries and has not been transferred or runtime-tested on Linux; the historical 57/57 Linux result applies only to the earlier 301-file snapshot. A local final-source archive was regenerated reproducibly for review, but it is not a release approval.

Commercial release readiness remains false until the toolchain, required semantic coverage, exact final-source Linux runtime/build and other checklist gates are closed.