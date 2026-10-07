<!--
    Project: OpenSesh
    File: docs/LINTING.md
    Purpose: describe the strict lint boundary and validator corrections.
    Responsibilities: make the source policy and its verification reproducible.
    This file does not claim native target execution or release qualification.
-->

# Strict lint

Run `tools/lint.ps1` from PowerShell for Windows, and repeat with `-Target linux`.
Supply `-LinterPath`, `-CompilerPath` and `-CompilerIncludePath` when the tools
are installed elsewhere.
The compiler must export complete schema-27 models and structured diagnostics.
The runner includes all
application modules, internal editor includes, root test sources and the exact
GUI source subset in `SNAPSHOT.sha256`. Generated directories and intentional
validator regression inputs in `tools/fblint` are outside that boundary.

The strict profile uses strict headers, strict tabs, honored line suppressions
and failure on warnings. It disables no rule family and accepts no warning
baseline. `--require-semantic` rejects missing or incomplete compiler facts.
The runner supplies the native target, GCC backend, multithreaded mode, GUI
include directory and compiler headers. The real GUI and safety-test roots
select redistributable fonts in their own source definitions.

omaGUI's `.bas` implementation files are compiled through
`src/omagui_runtime.bas`, then analyzed using their own physical source paths.
The semantic context must contain every selected GUI input. The linter reuses
one model within that invocation and verifies the compiler-recorded SHA-256
of every source before reuse. Application and test `.bas` files are separate
compiler roots. Each application header is assigned to an actual including
root and must have compiler facts; it has no include-only exemption.
The runner produces one summary for each compilation context. `-ListScopes`
lists those contexts without running a scan.

The context-aware validator patch is retained in
`tools/fblint/semantic-context.patch`. It adds typed build-context options and
keeps source-specific rule indexes separate from reusable graph metadata.
Its baseline is the current linter source with compiler-backed CASE and
declaration typing rules. Preserve `fb_linter_case_rules.bi` and
`fb_linter_declaration_type_rules.bi` when applying the patch.
`tools/fblint/test_semantic_context.py` checks included files, absent files,
inactive includes, inline returns and included macro replay against real
compiler exports. These checks also cover paths containing spaces. Macro
replay preprocesses the compilation root so an included implementation retains
the declarations and definitions that made its initial export valid.

Conditional expression and branch-node arrays use their validated record counts.
An unrelated 250,000-entry symbol-type limit previously rejected valid large
GUI models. Their existing expression and node limits remain in place.

These exports are compiler front-end checks on the selected Windows or Linux
target. Native compilation with all warnings and target execution remain
separate required checks. In particular, a Linux export on Windows is not a
native Linux test.

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

With the corrected validator, use `--target linux`, select `FBL423,FBL422,FBL750` and lint the two
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

The safe/boundary fixtures and both complete strict target scans also pass
with ruleset 2026.10.059, built 2026-10-05 08:53:03, executable SHA-256
`1b23d127f61dac67987648aa93483b487b20a69e769c2a01fe483ca803af0e66`.
Retain a private copy of the selected executable for release verification
when other tasks may update the shared installation.

<!-- end of docs/LINTING.md -->
