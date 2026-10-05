<!--
    Project: OpenSesh
    File: docs/LINTING.md
    Purpose: describe the strict lint boundary and validator corrections.
    Responsibilities: make the source policy and its verification reproducible.
    This file does not claim compiler-backed semantic or runtime validation.
-->

# Strict lint

Run `tools/lint.ps1` from PowerShell for Windows, and repeat with `-Target linux`.
Supply `-LinterPath` when fblint is installed elsewhere. The runner includes all
application modules, internal editor includes, root test sources and the exact
GUI source subset in `SNAPSHOT.sha256`. Generated directories and intentional
validator regression inputs in `tools/fblint` are outside that boundary.

The strict profile uses strict headers, strict tabs, honored line suppressions
and failure on warnings. It disables no rule family and accepts no warning
baseline. Compiler-backed semantic checks are unavailable through this runner
because fblint does not accept the application's include-path context. Native
compilation with all compiler warnings and target execution remain separate
required checks.

Keep a line suppression only for a reviewed false positive or documented API
constraint. Typical examples are bounded framebuffer pointer copies, a shared
decoder cleanup path, optional environment overrides with a defined fallback,
and password-mask widget state which contains no credential literal. Prefer a
source repair whenever the finding identifies a real failure boundary.

## Validator correction

The release preparation found two false positives in fblint ruleset
`2026.10.058`. The patch in `tools/fblint/fixed-width-and-environment.patch`
records both corrections:

- The old FBL423 rule treated every spelling containing `Long` as a native C
  `long`. FreeBASIC `Long` and `ULong` have 32 bits, and `LongInt` and `ULongInt`
  have 64 bits. The compiler assertions in `fixed_width_safe.bas` verify these
  widths. ABI-layout checks still report native-sized fields at a binary
  boundary through FBL422.
- FBL750 matched `Environment` inside ordinary identifiers. It now recognizes
  the `Environ` token. An actual environment read still produces the warning.

With the corrected validator, select `FBL423,FBL422,FBL750` and lint the two
fixtures under `tools/fblint`. The safe fixture must have zero findings; the
boundary fixture must produce exactly one FBL422 and one FBL750 finding and
fail a warning gate. Compile and run the safe fixture as well. These are
validator tests, not application source or examples of an accepted binary ABI.

Record the validator's complete `--version` output and executable SHA-256 with
release evidence. The locally verified correction uses fblint 1.0.0, ruleset
2026.10.058, built 2026-10-05 07:54:10, executable SHA-256
`13a0689f3118f8e85ace480018bcff76e3f660779a7c423c4bf71a7f2f7f1c0c`.
A newer validator needs a fresh regression and full strict scan. Do not treat
the version number alone as proof that a correction is present.

<!-- end of docs/LINTING.md -->
