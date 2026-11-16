<!--
    Project: Optical FreeBASIC / omaGUI
    File: UPSTREAM_SYNC.md
    Purpose: Record the reference copy and decisions behind local integration.
    Responsibilities: Identify imported fixes, retained extensions, and checks.
    This file intentionally does NOT contain a release-wide compatibility claim.
-->

# Reference integration, 2026-09-13

Reference: `C:\Nextcloud\games\newjrpg\omaGui`

Destination: `C:\Nextcloud\games\FreeBASIC_packages\Optical-Freebasic\omaGui`

The reference was read-only. Of its 158 non-ignored files, 122 matched locally
and 36 differed. Every reference file already had a local counterpart.
The source, header, test, documentation, and master-include differences were
reviewed individually; differing files were not copied wholesale.

## Imported fix

`src/widgets/button.bas` now uses the reference's `button_Update` implementation:

- Null widgets and released private data return before dereferencing them.
- Pointer release stores the final hover state before calling application code.
- Pointer and keyboard activation return immediately after the callback, which
  may have destroyed the button or its entire parent tree.

Reference `button.bas` SHA-256:
`4F9C92F72BB8FE89EB19480F4C89E641C10FD61A4E2F117DC2DB6553DF561588`

The remaining button differences are the local semantic palette and mnemonic
underline rendering. No public signature or data layout changed in this merge.

## Retained local work

The other differences were local additions or replacements supporting those
additions, not missing reference improvements. These remain intact:

- Splitters, block indentation, line-number gutters, and KeyUp callbacks.
- Independent classic widget colors and access-key underlines.
- Resizable child windows, title controls, and minimize/maximize state.
- List item data, replacement, scrolling, and observable ComboBox opening.
- Multi-pattern file lists, root-directory handling, and label layout/clipping.
- Extended message dialogs and their checked allocation/layout handling.
- Local tests, documentation, and master includes for these features.

Unchanged reference assets, examples, and tools needed no copying. Compiler
outputs and local executables were not imported from the reference directory.
The fix uses only FreeBASIC and the existing input layer, with no SDK or new
platform dependency.

## Regression coverage

`tests/button_lifetime_smoke.bas` first detaches live button data in a callback.
This detects incorrect post-callback writes without relying on freed-memory
contents. That check failed against the old implementation and passed after
the fix. Further cases cover immediate destruction, registry-owned tree removal,
Enter/Space, simultaneous pointer/key input, null arguments, and polled results.

Both the full project gate and `tools/verify_omagui_workspace.ps1` include the
new test. The focused verifier also builds the linked IDE, checks its layout and
editor commands, emits Linux C, and runs strict fblint. Linux C generation is
not a Linux link or runtime test.

The focused verifier passed all nine widget tests, both linked IDE checks, all
four Linux C-generation checks, and strict Windows lint with zero errors and
zero warnings. Additional parent-modal, extended-message-dialog (429 checks),
and semantic title-color/rendering tests passed using the null display driver.
The full sample-translation gate was not rerun for this focused merge.
The normal root `vbdos_studio.exe` was rebuilt with the installed
`C:\FreeBASIC\fbc.exe` (1.20.2-14); its layout and editor smoke checks also
passed. Those checks left the sample project and source hashes unchanged.

Verification logs:
`build/omagui_workspace_3f9fa091360445a9b59969d2ca192a4f` and
`build/omagui_sync_95c2a380ea9a4fe39e81f1b01e851ba9`, relative to the project root.

## Synchronization and editor update, 2026-10-23

The local and linked trees were compared by source path before merging. Three
files differed: `src/widgets/widgets.bas`, `src/widgets/widgets.bi`, and
`tests/widget_registry_smoke.bas`. The local versions contained a public
application cursor override plus registry-safe inherited-cursor lookup and
coverage for those behaviors. Those reviewed changes are now integrated into
the linked copy. The TextBox update below was also applied identically to both
copies.

`textbox_Update` now snapshots `change_serial` to detect edits. The former
path copied and compared the entire document string on every active-editor
update, including updates where no text had changed. This removes that
document-sized allocation and comparison from the repeated path. Code that
replaces TextBox source directly must continue to increment `change_serial`,
as documented by the widget data contract.

Both generated manifests matched after the source integration: 240 FreeBASIC
source files, 135 snapshot files, and 283 tree files. The focused local TextBox
suite passed all 16 native checks, Linux C emission passed for four inputs,
and strict source-only Windows lint on `textbox.bas` reported zero errors,
warnings, or info. The maintained verifier's semantic-lint phase was stopped
while competing lint jobs were active, so that verifier did not complete. A
broader four-file source-only lint and a separate linked registry-smoke compile
were also stopped before completion to avoid sustained compiler load; linked
runtime behavior is therefore not claimed by this pass.
No Guacamole latency measurement was available, so the improvement is a
source-level reduction in repeated work, not a measured end-to-end result.

## Interactive host clipboard policy, 2026-10-27

The clipboard backend now exposes `clipboard_SetHostEnabled`. A zero value
selects omaGUI's bounded local text store; a nonzero value restores the native
host bridge when one was compiled. VBDOS enables the bridge for interactive
runs and disables it for event-script runs, keeping scripted clipboard checks
away from the user's desktop clipboard. The implementation remains FreeBASIC
and uses omaGUI's existing platform declarations without a Windows SDK.

Strict Windows and Linux FBLint passed for the clipboard implementation, and
strict Windows FBLint passed for the VBDOS runtime. A host-enabled HELPUTIL
sample compiled and passed all 15 scripted events with empty stderr. That run
exercised the local store selected by script mode; a live host clipboard write
was not attempted. No installed compiler or Studio binary was rebuilt by this
change. The Optical and NewJRPG trees were synchronized for the reviewed
clipboard sources and manual, then their source, snapshot and tree manifests
were refreshed and compared.

## Portable clipboard opt-in, 2026-10-27

The VBDOS runtime and Studio define OMAGUI_PORTABLE_ONLY and separately opt in
to OMAGUI_ENABLE_HOST_CLIPBOARD. The clipboard switch enables only omaGUI's
host clipboard bridge; filesystem and input backends retain their portable
paths. OMAGUI_DISABLE_HOST_CLIPBOARD still forces the bounded local store.
This keeps the feature opt-in without broadening native platform behavior.

Strict source-only FBLint passed on Windows and Linux for clipboard.bas,
vbdos_runtime.bas, and vbdos_studio.bas with zero errors, warnings, and
informational findings. The HELPUTIL candidate
E:\codex-build-temp\vbdoscli01\clipboard_scope_narrowing_20261027\candidate\helputil_clipboard_scope_native_20261027.exe
(SHA-256 0C104489791FEBD151354F1E982028D217FA1F265F86416BBE88DD81FEBDD9D5)
passed all 15 scripted event lines with empty stderr. Script mode selected the
process-local clipboard; no live host clipboard exchange was attempted.

The isolated Studio candidate
E:\codex-build-temp\vbdoscli01\studio_clipboard_scope_20261027\candidate\vbdos_studio_clipboard_scope_20261027.exe
(SHA-256 6BD882F79A3A8E8F988F10D3A3A921CA1983E386F470F54F38B9E02B9F28828D)
compiled successfully and passed the four headless startup-profile smokes. It
was not launched or installed. The installed 478AD/3B pair was not rebuilt;
the earlier full VBDOS gate predates this clipboard source change. Build and
test receipts remain under E:\codex-build-temp\vbdoscli01.
<!-- end of UPSTREAM_SYNC.md -->
