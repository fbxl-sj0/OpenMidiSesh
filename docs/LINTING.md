<!--
    Project: OpenSesh
    File: docs/LINTING.md
    Purpose: Explain the strict source lint entry point for contributors.
    Responsibilities: document required semantic coverage and useful summaries.
    This file does not substitute lint results for native builds or runtime checks.
-->

# Linting

Run <code>tools/lint.ps1</code> from PowerShell for the Windows target. Run it
again with <code>-Target linux</code> to check the Linux configuration. Use
<code>-ListScopes</code> to print the compilation contexts without starting a
scan.

~~~powershell
./tools/lint.ps1
./tools/lint.ps1 -Target linux
./tools/lint.ps1 -ListScopes
~~~

The project script runs fblint in strict mode with compiler-backed semantic
analysis required, strict headers and tabs, suppressions enabled, and warnings
treated as failures. It uses the selected FreeBASIC compiler, include tree,
target backend, multithreaded mode, and the exact omaGUI payload manifest.

A zero process exit is not enough to claim semantic coverage. Review the
<code>FB-LINTER SUMMARY</code> for accepted, unavailable, and skipped model
counts and operational errors. An unavailable model or an operational error
means the scope was not fully checked. For Windows release runs, verify the
compiler against <code>windows_toolchain_lock.json</code> first.

The linter and compiler may be installed elsewhere. Use
<code>-LinterPath</code>, <code>-CompilerPath</code>, and
<code>-CompilerIncludePath</code> to select those installations.
Compiler-backed lint remains separate from compilation, tests, and native
platform qualification.

<!-- end of docs/LINTING.md -->