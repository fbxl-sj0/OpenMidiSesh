<#
    Project: OpenSesh
    ----------------------------

    File: verify_windows_release.ps1

    Purpose:

        Produce fail-closed evidence for the automated Windows release gates.

    Responsibilities:

        - run the complete Windows test suite from current source
        - require strict Windows and Linux lint without warnings
        - build and inspect the versioned Windows editor executable
        - create and independently inspect the source-only release archive
        - retain logs, hashes, and a machine-readable evidence summary

    This file intentionally does NOT contain:

        - Linux runtime verification
        - physical MIDI loopback approval
        - accessibility, signing, licensing, or legal approval
        - permission to publish a commercial release
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $EvidenceDirectory,
    [string] $FreeBasicPath = 'C:\FreeBASIC\fbc.exe',
    [string] $OmaGuiPath = '',
    [string] $LinterPath = 'C:\fblint\fb_linter.exe',
    [ValidateRange(1, 3600)]
    [int] $TestTimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($OmaGuiPath)) {
    $OmaGuiPath = Join-Path $projectRoot 'vendor\omaGui'
}

$evidenceRoot = [System.IO.Path]::GetFullPath($EvidenceDirectory)
$projectBoundary = $projectRoot.TrimEnd('\') + '\'
if ([System.StringComparer]::OrdinalIgnoreCase.Equals(
        $evidenceRoot.TrimEnd('\'),
        $projectRoot.TrimEnd('\')) -or
    $evidenceRoot.StartsWith(
        $projectBoundary,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The evidence directory must be outside the project source tree.'
}
if ([System.StringComparer]::OrdinalIgnoreCase.Equals(
        $evidenceRoot.TrimEnd('\'),
        [System.IO.Path]::GetPathRoot($evidenceRoot).TrimEnd('\'))) {
    throw 'The evidence directory must not be a drive root.'
}
if (Test-Path -LiteralPath $evidenceRoot) {
    throw "Refusing to overwrite an existing evidence directory: $evidenceRoot"
}

$evidenceParent = Split-Path -Parent $evidenceRoot
if (-not (Test-Path -LiteralPath $evidenceParent -PathType Container)) {
    New-Item -ItemType Directory -Path $evidenceParent -Force | Out-Null
}
New-Item -ItemType Directory -Path $evidenceRoot | Out-Null

$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
$powerShellExecutable = (Get-Process -Id $PID).Path
$compilerPath = [System.IO.Path]::GetFullPath($FreeBasicPath)
$omaGuiRoot = [System.IO.Path]::GetFullPath($OmaGuiPath)
$strictLinter = [System.IO.Path]::GetFullPath($LinterPath)
$workingRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('opensesh-release-verify-' + [System.Guid]::NewGuid().ToString('N'))
$failureMessage = ''

$evidence = [ordered]@{
    schema_version = 1
    product = 'OpenSesh'
    started_utc = [DateTime]::UtcNow.ToString('o')
    completed_utc = $null
    host = $env:COMPUTERNAME
    status = 'running'
    automated_windows_gates = 'running'
    commercial_release_ready = $false
    remaining_gate_document = 'docs\RELEASE_CHECKLIST.md'
    source_file_count = 0
    vendored_source_file_count = 0
    windows_test_count = 0
    windows_lint_warning_count = 0
    linux_lint_warning_count = 0
    vendored_windows_lint_warning_count = 0
    vendored_linux_lint_warning_count = 0
    locked_windows_toolchain_file_count = 0
    artifacts = [ordered]@{}
}


# ---------------------------------------------------------------------------
# Command and report helpers
# ---------------------------------------------------------------------------

function Write-Utf8Text {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [AllowEmptyString()]
        [string] $Text
    )

    [System.IO.File]::WriteAllText($Path, $Text, $utf8WithoutBom)
}


function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,
        [string[]] $Arguments = @(),
        [Parameter(Mandatory = $true)]
        [string] $LogPath,
        [Parameter(Mandatory = $true)]
        [string] $Description,
        [switch] $SuppressConsoleOutput
    )

    Write-Output ("VERIFY " + $Description)
    $commandOutput = @(& $FilePath @Arguments 2>&1)
    $commandExitCode = $LASTEXITCODE
    $logLines = @($commandOutput | ForEach-Object { [string] $_ })
    $logText = $logLines -join [Environment]::NewLine
    if ($logLines.Count -gt 0) {
        $logText += [Environment]::NewLine
    }
    Write-Utf8Text -Path $LogPath -Text $logText
    if (-not $SuppressConsoleOutput) {
        foreach ($logLine in $logLines) {
            Write-Output $logLine
        }
    }
    if ($commandExitCode -ne 0) {
        throw "$Description exited with status $commandExitCode."
    }
}


function Get-SingleCapturedValue {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Lines,
        [Parameter(Mandatory = $true)]
        [string] $Pattern,
        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    $regularExpression = New-Object System.Text.RegularExpressions.Regex($Pattern)
    $foundMatches = @()
    foreach ($line in $Lines) {
        $candidateMatch = $regularExpression.Match($line)
        if ($candidateMatch.Success) {
            $foundMatches += $candidateMatch
        }
    }
    if ($foundMatches.Count -ne 1) {
        throw "$Description must appear exactly once; found $($foundMatches.Count)."
    }
    return $foundMatches[0].Groups[1].Value
}


function Get-LintSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Lines,
        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    $summaryPattern = '^FB-LINTER SUMMARY files=\s*(\d+) errors=\s*(\d+) ' +
        'warnings=\s*(\d+) info=\s*(\d+)\s*$'
    $summaryExpression = New-Object System.Text.RegularExpressions.Regex(
        $summaryPattern)
    $summaries = @()
    foreach ($line in $Lines) {
        $summaryMatch = $summaryExpression.Match($line)
        if ($summaryMatch.Success) {
            $summaries += $summaryMatch
        }
    }
    if ($summaries.Count -ne 1) {
        throw "$Description lint summary must appear exactly once."
    }

    return [pscustomobject]@{
        Files = [int] $summaries[0].Groups[1].Value
        Errors = [int] $summaries[0].Groups[2].Value
        Warnings = [int] $summaries[0].Groups[3].Value
        Info = [int] $summaries[0].Groups[4].Value
    }
}


function Get-DeclaredStringConstant {
    param(
        [Parameter(Mandatory = $true)]
        [string] $SourceText,
        [Parameter(Mandatory = $true)]
        [string] $ConstantName
    )

    $constantPattern = '(?m)^Const\s+' + [regex]::Escape($ConstantName) +
        '\s+As\s+String\s*=\s*"([^"]+)"\s*$'
    $constantMatches = [regex]::Matches($SourceText, $constantPattern)
    if ($constantMatches.Count -ne 1) {
        throw "Could not read the single $ConstantName declaration."
    }
    return $constantMatches[0].Groups[1].Value
}


function Get-StreamSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream] $Stream
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash($Stream)
        return ([System.BitConverter]::ToString($digest)).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
}


# ---------------------------------------------------------------------------
# Automated Windows release gates
# ---------------------------------------------------------------------------

try {
    if ($env:OS -ne 'Windows_NT') {
        throw 'This verifier requires Windows.'
    }
    foreach ($requiredFile in @(
            $powerShellExecutable,
            $compilerPath,
            $strictLinter,
            (Join-Path $projectRoot 'tests\run_tests.ps1'),
            (Join-Path $projectRoot 'build_editor.ps1'),
            (Join-Path $projectRoot 'prepare_source_release.ps1'))) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Required release input was not found: $requiredFile"
        }
    }
    if (-not (Test-Path -LiteralPath $omaGuiRoot -PathType Container)) {
        throw "omaGui include tree was not found: $omaGuiRoot"
    }

    New-Item -ItemType Directory -Path $workingRoot | Out-Null
    Push-Location $projectRoot
    try {
        $vendorRoot = [System.IO.Path]::GetFullPath(
            (Join-Path $projectRoot 'vendor\omaGui'))
        # Build directories can contain compiler probes and extracted source
        # archives. Only maintained application and test sources belong in
        # the release lint boundary, regardless of previous local builds.
        $sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src') `
            -Recurse -File |
            Where-Object { $_.Extension -in @('.bas', '.bi') })
        $sourceFiles += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') `
            -File | Where-Object { $_.Extension -in @('.bas', '.bi') })
        # The local dependency tree also contains examples and tests. Lint
        # the exact source subset shipped by the release manifest.
        $vendoredSourceFiles = @(Get-Content -LiteralPath `
            (Join-Path $vendorRoot 'SNAPSHOT.sha256') | ForEach-Object {
                if ($_ -match '^[0-9a-f]{64}  (.+\.(?:bas|bi))$') {
                    $sourcePath = Join-Path $vendorRoot `
                        $matches[1].Replace('/', '\')
                    Get-Item -LiteralPath $sourcePath
                }
            })
        if ($sourceFiles.Count -le 0) {
            throw 'No FreeBASIC source files were found.'
        }
        if ($vendoredSourceFiles.Count -le 0) {
            throw 'The reviewed GUI manifest contains no FreeBASIC sources.'
        }
        $evidence.source_file_count = $sourceFiles.Count
        $evidence.vendored_source_file_count = $vendoredSourceFiles.Count
        $lintSourcePaths = @($sourceFiles + $vendoredSourceFiles | ForEach-Object {
            $_.FullName.Substring($projectRoot.Length + 1)
        })
        $linterVersion = @(& $strictLinter '--version' 2>&1) -join ''
        if ($LASTEXITCODE -ne 0 -or
            $linterVersion -notmatch
                '^fb-linter [0-9.]+ \(ruleset [0-9.]+,') {
            throw "The linter identity could not be read: $linterVersion"
        }

        $evidence.linter_identity = $linterVersion
        $evidence.linter_sha256 = (Get-FileHash -LiteralPath $strictLinter `
            -Algorithm SHA256).Hash.ToLowerInvariant()

        $testLog = Join-Path $evidenceRoot 'windows-tests.log'
        $testArguments = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $projectRoot 'tests\run_tests.ps1'),
            '-FreeBasicPath', $compilerPath,
            '-OmaGuiPath', $omaGuiRoot,
            '-BuildDirectory', (Join-Path $workingRoot 'tests'),
            '-TestTimeoutSeconds', [string] $TestTimeoutSeconds
        )
        Invoke-LoggedCommand -FilePath $powerShellExecutable `
            -Arguments $testArguments -LogPath $testLog `
            -Description 'complete Windows test suite'
        $testLines = @(Get-Content -LiteralPath $testLog)
        $testsPassed = [int] (Get-SingleCapturedValue -Lines $testLines `
            -Pattern '^tests_passed=(\d+)\s*$' -Description 'tests_passed')
        $testsFailed = [int] (Get-SingleCapturedValue -Lines $testLines `
            -Pattern '^tests_failed=(\d+)\s*$' -Description 'tests_failed')
        if ($testsPassed -ne 68 -or $testsFailed -ne 0) {
            throw "Expected 68 passing Windows tests and zero failures; got $testsPassed/$testsFailed."
        }
        foreach ($requiredTestEvidence in @(
                'status=ok',
                'numeric_text=ok',
                'project_transaction_corrupt_journal_rejections=16',
                'music_symbol_malformed_masks=11',
                'text_controls=29',
                'list_controls=5',
                'behavior_checks=508',
                'startup_theme=Dark',
                'persisted_theme=Dark',
                'startup_interaction=Touch',
                'persisted_interaction=Touch',
                'total_controls=324',
                'visual_cases=49',
                'visual_failed=0',
                'visual_lifecycle=ok',
                'process_launches=60',
                'malformed_test_configuration_rejections=1',
                'sfx_runtime_lifecycle=ok',
                'sfx_runtime_process_launches=25',
                'sfx_runtime_driver_selection=default',
                'manifest_resource=present',
                'execution_level=asInvoker',
                'ui_access=false',
                'windows_generation=10_or_later',
                'dpi_awareness=System',
                'manifest_status=ok',
                'ui_smoothness_cases=8',
                'ui_smoothness_status=pass',
                'omagui_snapshot=ok',
                'omagui_payload_files=116',
                'omagui_licenses=MIT,OFL-1.1,LGPL-2.1-or-later,BSD-2-Clause',
                'windows_font_conversions=absent',
                'dependency_snapshot_status=ok',
                'windows_toolchain=locked',
                'windows_toolchain_files=14',
                'windows_toolchain_status=ok')) {
            if ($testLines -notcontains $requiredTestEvidence) {
                throw "Windows test evidence is missing: $requiredTestEvidence"
            }
        }
        $evidence.windows_test_count = $testsPassed

        $toolchainLog = Join-Path $evidenceRoot 'windows-toolchain.log'
        $toolchainArguments = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $projectRoot `
                'tests\verify_windows_toolchain.ps1'),
            '-FreeBasicPath', $compilerPath
        )
        Invoke-LoggedCommand -FilePath $powerShellExecutable `
            -Arguments $toolchainArguments -LogPath $toolchainLog `
            -Description 'locked Windows build toolchain'
        $toolchainLines = @(Get-Content -LiteralPath $toolchainLog)
        foreach ($requiredToolchainEvidence in @(
                'windows_toolchain=locked',
                'windows_toolchain_files=14',
                'windows_toolchain_status=ok')) {
            if ($toolchainLines -notcontains $requiredToolchainEvidence) {
                throw "Windows toolchain evidence is missing: $requiredToolchainEvidence"
            }
        }
        $evidence.locked_windows_toolchain_file_count = 14

        $windowsLintLog = Join-Path $evidenceRoot 'lint-windows.log'
        $linuxLintLog = Join-Path $evidenceRoot 'lint-linux-portability.log'
        foreach ($lintTarget in @('windows', 'linux')) {
            $lintLog = $windowsLintLog
            if ($lintTarget -eq 'linux') { $lintLog = $linuxLintLog }
            Invoke-LoggedCommand -FilePath $powerShellExecutable `
                -Arguments @('-NoProfile', '-NonInteractive', '-ExecutionPolicy',
                    'Bypass', '-File', (Join-Path $projectRoot 'tools\lint.ps1'),
                    '-LinterPath', $strictLinter, '-Target', $lintTarget) `
                -LogPath $lintLog -Description ('strict ' + $lintTarget + ' source lint')
            $lintSummary = Get-LintSummary -Lines @(Get-Content -LiteralPath $lintLog) `
                -Description $lintTarget
            if ($lintSummary.Files -ne ($sourceFiles.Count + $vendoredSourceFiles.Count) -or
                $lintSummary.Errors -ne 0 -or $lintSummary.Warnings -ne 0 -or
                $lintSummary.Info -ne 0) {
                throw "$lintTarget strict lint did not accept every release source without diagnostics."
            }
        }

        $versionTextSource = Get-Content -LiteralPath `
            (Join-Path $projectRoot 'src\version.bi') -Raw
        $releaseVersion = Get-DeclaredStringConstant `
            -SourceText $versionTextSource -ConstantName 'OSE_VERSION_TEXT'
        $productName = Get-DeclaredStringConstant `
            -SourceText $versionTextSource -ConstantName 'OSE_PRODUCT_NAME'
        $releaseExecutable = Join-Path $evidenceRoot `
            ('OpenSesh-' + $releaseVersion + '-windows.exe')
        $buildLog = Join-Path $evidenceRoot 'build-editor.log'
        $buildArguments = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $projectRoot 'build_editor.ps1'),
            '-FreeBasicPath', $compilerPath,
            '-OmaGuiPath', $omaGuiRoot,
            '-OutputPath', $releaseExecutable
        )
        Invoke-LoggedCommand -FilePath $powerShellExecutable `
            -Arguments $buildArguments -LogPath $buildLog `
            -Description 'versioned Windows editor build'
        if (-not (Test-Path -LiteralPath $releaseExecutable -PathType Leaf)) {
            throw 'The versioned Windows editor executable was not created.'
        }
        $versionInfo = (Get-Item -LiteralPath $releaseExecutable).VersionInfo
        if ($versionInfo.FileVersion -ne $releaseVersion -or
            $versionInfo.ProductVersion -ne $releaseVersion -or
            $versionInfo.ProductName -ne $productName) {
            throw 'The built editor version metadata does not match version.bi.'
        }
        & (Join-Path $projectRoot 'tests\verify_windows_manifest.ps1') `
            -ExecutablePath $releaseExecutable

        $binaryLog = Join-Path $evidenceRoot 'windows-binary.log'
        $binaryArguments = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $projectRoot `
                'tests\verify_windows_binary.ps1'),
            '-ExecutablePath', $releaseExecutable,
            '-RequireUnsignedDevelopmentBuild'
        )
        Invoke-LoggedCommand -FilePath $powerShellExecutable `
            -Arguments $binaryArguments -LogPath $binaryLog `
            -Description 'stripped and hardened Windows PE image'
        $binaryLogLines = @(Get-Content -LiteralPath $binaryLog)
        foreach ($requiredBinaryEvidence in @(
                'pe_architecture=x86_64',
                'pe_subsystem=windows_gui',
                'pe_hardening=high_entropy_va,dynamic_base,nx_compat',
                'pe_reproducible_timestamp=0',
                'pe_debug_sections=0',
                'pe_import_dlls=GDI32.dll,KERNEL32.dll,msvcrt.dll,ole32.dll,USER32.dll,WINMM.dll',
                'pe_overlay_bytes=0',
                'authenticode_status=unsigned_development',
                'windows_binary_status=ok')) {
            if ($binaryLogLines -notcontains $requiredBinaryEvidence) {
                throw "Windows binary evidence is missing: $requiredBinaryEvidence"
            }
        }

        $binaryNegativeLog = Join-Path $evidenceRoot `
            'windows-binary-negative.log'
        $binaryNegativeArguments = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $projectRoot `
                'tests\verify_windows_binary_negative.ps1'),
            '-ExecutablePath', $releaseExecutable
        )
        Invoke-LoggedCommand -FilePath $powerShellExecutable `
            -Arguments $binaryNegativeArguments -LogPath $binaryNegativeLog `
            -Description 'Windows PE verifier negative corpus'
        $binaryNegativeLines = @(Get-Content -LiteralPath $binaryNegativeLog)
        foreach ($requiredNegativeEvidence in @(
                'windows_binary_negative_status=ok',
                'windows_binary_negative_cases=8')) {
            if ($binaryNegativeLines -notcontains $requiredNegativeEvidence) {
                throw "Windows binary negative evidence is missing: $requiredNegativeEvidence"
            }
        }

        $reproducibilityExecutable = Join-Path $workingRoot `
            'OpenSesh-reproducibility.exe'
        $reproducibilityBuildLog = Join-Path $evidenceRoot `
            'build-editor-reproducibility.log'
        $reproducibilityBuildArguments = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $projectRoot 'build_editor.ps1'),
            '-FreeBasicPath', $compilerPath,
            '-OmaGuiPath', $omaGuiRoot,
            '-OutputPath', $reproducibilityExecutable
        )
        Invoke-LoggedCommand -FilePath $powerShellExecutable `
            -Arguments $reproducibilityBuildArguments `
            -LogPath $reproducibilityBuildLog `
            -Description 'independent reproducibility editor build'
        $releaseExecutableHash = (Get-FileHash -LiteralPath $releaseExecutable `
            -Algorithm SHA256).Hash
        $reproducibilityExecutableHash = (Get-FileHash `
            -LiteralPath $reproducibilityExecutable -Algorithm SHA256).Hash
        if ($releaseExecutableHash -ne $reproducibilityExecutableHash) {
            throw 'Independent Windows editor builds are not byte-identical.'
        }

        $sourceArchive = Join-Path $evidenceRoot `
            ('OpenSesh-source-' + $releaseVersion + '.zip')
        $archiveLog = Join-Path $evidenceRoot 'prepare-source-archive.log'
        $archiveArguments = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $projectRoot 'prepare_source_release.ps1'),
            '-OutputArchive', $sourceArchive
        )
        Invoke-LoggedCommand -FilePath $powerShellExecutable `
            -Arguments $archiveArguments -LogPath $archiveLog `
            -Description 'source-only release archive'
        if (-not (Test-Path -LiteralPath $sourceArchive -PathType Leaf)) {
            throw 'The source archive was not created.'
        }
        $archiveLogLines = @(Get-Content -LiteralPath $archiveLog)
        $declaredArchiveCount = [int] (Get-SingleCapturedValue `
            -Lines $archiveLogLines -Pattern '^source_files=(\d+)\s*$' `
            -Description 'source_files')

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($sourceArchive)
        $archiveManifestLines = New-Object System.Collections.Generic.List[string]
        $archivePathSet = New-Object 'System.Collections.Generic.HashSet[string]' `
            ([System.StringComparer]::OrdinalIgnoreCase)
        $archiveFileCount = 0
        $visualBaselineCount = 0
        $blockedExtensions = @(
            '.a', '.asm', '.bmp', '.c', '.dll', '.dylib', '.exe', '.lib',
            '.mask', '.mid', '.midi', '.mod', '.o', '.obj', '.ose', '.pdb',
            '.so', '.wav', '.wave', '.zip'
        )
        try {
            foreach ($archiveEntry in $zipArchive.Entries) {
                $entryName = $archiveEntry.FullName
                if ($entryName.Contains('\')) {
                    throw "Non-portable backslash in source archive path: $entryName"
                }
                if ($entryName.StartsWith('/') -or $entryName.Contains('//') -or
                    $entryName.Split('/') -contains '..') {
                    throw "Unsafe path in source archive: $entryName"
                }
                if ($entryName.EndsWith('/')) {
                    continue
                }
                if (-not $entryName.StartsWith('opensesh/')) {
                    throw "Unexpected source archive root: $entryName"
                }
                $relativeEntry = $entryName.Substring('opensesh/'.Length)
                if ($relativeEntry -eq '' -or
                    -not $archivePathSet.Add($relativeEntry)) {
                    throw "Duplicate or empty source archive path: $relativeEntry"
                }

                $entryExtension = [System.IO.Path]::GetExtension($relativeEntry).ToLowerInvariant()
                if ($blockedExtensions -contains $entryExtension) {
                    throw "Blocked release artifact in source archive: $relativeEntry"
                }
                if ($entryExtension -eq '.png') {
                    if (-not $relativeEntry.StartsWith(
                            'tests/visual_baselines/',
                            [System.StringComparison]::Ordinal)) {
                        throw "Unreviewed PNG in source archive: $relativeEntry"
                    }
                    $visualBaselineCount++
                }

                $sourcePath = [System.IO.Path]::GetFullPath((Join-Path `
                    $projectRoot $relativeEntry.Replace('/', '\')))
                if (-not $sourcePath.StartsWith(
                        $projectBoundary,
                        [System.StringComparison]::OrdinalIgnoreCase) -or
                    -not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                    throw "Archive entry has no safe current source file: $relativeEntry"
                }
                if ((Get-Item -LiteralPath $sourcePath).Length -ne $archiveEntry.Length) {
                    throw "Archive entry length differs from current source: $relativeEntry"
                }

                $entryStream = $archiveEntry.Open()
                try {
                    $entryHash = Get-StreamSha256 -Stream $entryStream
                }
                finally {
                    $entryStream.Dispose()
                }
                $sourceHash = (Get-FileHash -LiteralPath $sourcePath `
                    -Algorithm SHA256).Hash
                if ($entryHash -ne $sourceHash) {
                    throw "Archive entry differs from current source: $relativeEntry"
                }
                $archiveManifestLines.Add($entryHash + '  ' + $relativeEntry)
                $archiveFileCount++
            }
        }
        finally {
            $zipArchive.Dispose()
        }
        if ($archiveFileCount -ne $declaredArchiveCount) {
            throw "Source archive count mismatch: declared=$declaredArchiveCount actual=$archiveFileCount"
        }
        if ($visualBaselineCount -ne 49) {
            throw "Expected 49 reviewed visual baselines; found $visualBaselineCount."
        }
        foreach ($requiredArchiveFile in @(
                'build_editor_android.ps1',
                'src\opensesh_unity.bas',
                'src\midi_null.bas',
                'src\touch_gesture.bas',
                'src\touch_gesture.bi',
                'src\opensesh.manifest',
                'PORTABLE_README.txt',
                'docs\DEPENDENCIES.md',
                'src\midi_alsa.bas',
                'src\midi_input.bi',
                'src\midi_output.bi',
                'prepare_windows_portable_package.ps1',
                'src\sfx_runtime.bas',
                'src\sfx_runtime.bi',
                'tests/verify_windows_binary.ps1',
                'tests/verify_windows_binary_negative.ps1',
                'tests/verify_dependency_snapshot.ps1',
                'tests/verify_windows_manifest.ps1',
                'tests/verify_windows_portable_package.ps1',
                'tests/verify_windows_portable_package_negative.ps1',
                'tests/verify_windows_toolchain.ps1',
                'tests/run_visual_lifecycle_stress.ps1',
                'tests/run_android_device_smoke.ps1',
                'tests/run_sfx_runtime_lifecycle_stress.ps1',
                'tests/touch_gesture_smoke.bas',
                'tests/run_linux_ui_smoke.sh',
                'tests/run_linux_sanitizers.sh',
                'tests/linux_visual_baselines.sha256',
                'tests/visual_baselines/main-touch-y-zoom-1280x720.png',
                'vendor/omaGui/DEPENDENCY.md',
                'vendor/omaGui/SNAPSHOT.sha256',
                'vendor/omaGui/assets/fonts/OFL-1.1.txt',
                'windows_toolchain_lock.json',
                'tools/lint.ps1',
                'fblint.toml',
                'release_manifest.txt',
                '.gitattributes',
                'docs/ARCHITECTURE.md',
                'verify_linux_release_archive.sh',
                'verify_windows_release.ps1')) {
            if (-not $archivePathSet.Contains($requiredArchiveFile.Replace('\', '/'))) {
                throw "Source archive is missing release infrastructure: $requiredArchiveFile"
            }
        }
        $sortedArchiveManifest = @($archiveManifestLines | Sort-Object)
        Write-Utf8Text -Path (Join-Path $evidenceRoot 'source-archive-manifest.txt') `
            -Text (($sortedArchiveManifest -join [Environment]::NewLine) +
                [Environment]::NewLine)

        $portablePackage = Join-Path $evidenceRoot `
            ('OpenSesh-' + $releaseVersion +
                '-windows-portable.zip')
        $portableLog = Join-Path $evidenceRoot `
            'prepare-windows-portable-package.log'
        $portableArguments = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $projectRoot `
                'prepare_windows_portable_package.ps1'),
            '-ExecutablePath', $releaseExecutable,
            '-SourceArchivePath', $sourceArchive,
            '-OutputPackage', $portablePackage
        )
        Invoke-LoggedCommand -FilePath $powerShellExecutable `
            -Arguments $portableArguments -LogPath $portableLog `
            -Description 'deterministic Windows portable package'

        $reproducibilityPackage = Join-Path $workingRoot `
            'OpenSesh-portable-reproducibility.zip'
        $reproducibilityPackageLog = Join-Path $evidenceRoot `
            'prepare-windows-portable-package-reproducibility.log'
        $reproducibilityPackageArguments = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $projectRoot `
                'prepare_windows_portable_package.ps1'),
            '-ExecutablePath', $reproducibilityExecutable,
            '-SourceArchivePath', $sourceArchive,
            '-OutputPackage', $reproducibilityPackage
        )
        Invoke-LoggedCommand -FilePath $powerShellExecutable `
            -Arguments $reproducibilityPackageArguments `
            -LogPath $reproducibilityPackageLog `
            -Description 'independent reproducibility portable package'
        $portablePackageHash = (Get-FileHash -LiteralPath $portablePackage `
            -Algorithm SHA256).Hash
        $reproducibilityPackageHash = (Get-FileHash `
            -LiteralPath $reproducibilityPackage -Algorithm SHA256).Hash
        if ($portablePackageHash -ne $reproducibilityPackageHash) {
            throw 'Independent Windows portable packages are not byte-identical.'
        }

        $portableVerificationLog = Join-Path $evidenceRoot `
            'windows-portable-package.log'
        $portableVerificationArguments = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $projectRoot `
                'tests\verify_windows_portable_package.ps1'),
            '-PackagePath', $portablePackage,
            '-ExecutablePath', $releaseExecutable,
            '-SourceArchivePath', $sourceArchive
        )
        Invoke-LoggedCommand -FilePath $powerShellExecutable `
            -Arguments $portableVerificationArguments `
            -LogPath $portableVerificationLog `
            -Description 'Windows portable package contents'
        $portableVerificationLines = @(
            Get-Content -LiteralPath $portableVerificationLog)
        foreach ($requiredPortableEvidence in @(
                'portable_package_status=ok',
                'portable_package_files=9',
                'portable_package_notice_files=4',
                'portable_package_bundled_source=1')) {
            if ($portableVerificationLines -notcontains $requiredPortableEvidence) {
                throw "Windows portable package evidence is missing: $requiredPortableEvidence"
            }
        }

        $portableNegativeLog = Join-Path $evidenceRoot `
            'windows-portable-package-negative.log'
        $portableNegativeArguments = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $projectRoot `
                'tests\verify_windows_portable_package_negative.ps1'),
            '-PackagePath', $portablePackage,
            '-ExecutablePath', $releaseExecutable,
            '-SourceArchivePath', $sourceArchive
        )
        Invoke-LoggedCommand -FilePath $powerShellExecutable `
            -Arguments $portableNegativeArguments -LogPath $portableNegativeLog `
            -Description 'Windows portable package negative corpus'
        $portableNegativeLines = @(Get-Content -LiteralPath $portableNegativeLog)
        foreach ($requiredPortableNegativeEvidence in @(
                'portable_package_negative_status=ok',
                'portable_package_negative_cases=7')) {
            if ($portableNegativeLines -notcontains `
                $requiredPortableNegativeEvidence) {
                throw ('Windows portable package negative evidence is missing: ' +
                    $requiredPortableNegativeEvidence)
            }
        }

        $evidence.artifacts = [ordered]@{
            windows_test_log_sha256 = (Get-FileHash -LiteralPath $testLog `
                -Algorithm SHA256).Hash
            windows_toolchain_log_sha256 = (Get-FileHash `
                -LiteralPath $toolchainLog -Algorithm SHA256).Hash
            windows_toolchain_lock_sha256 = (Get-FileHash `
                -LiteralPath (Join-Path $projectRoot `
                    'windows_toolchain_lock.json') -Algorithm SHA256).Hash
            windows_lint_log_sha256 = (Get-FileHash -LiteralPath $windowsLintLog `
                -Algorithm SHA256).Hash
            linux_portability_lint_log_sha256 = (Get-FileHash `
                -LiteralPath $linuxLintLog -Algorithm SHA256).Hash
            windows_binary_log_sha256 = (Get-FileHash `
                -LiteralPath $binaryLog -Algorithm SHA256).Hash
            windows_binary_negative_log_sha256 = (Get-FileHash `
                -LiteralPath $binaryNegativeLog -Algorithm SHA256).Hash
            editor_file = [System.IO.Path]::GetFileName($releaseExecutable)
            editor_sha256 = $releaseExecutableHash
            editor_version = $releaseVersion
            reproducible_editor_builds = 2
            source_archive_file = [System.IO.Path]::GetFileName($sourceArchive)
            source_archive_sha256 = (Get-FileHash -LiteralPath $sourceArchive `
                -Algorithm SHA256).Hash
            source_archive_files = $archiveFileCount
            portable_package_file = [System.IO.Path]::GetFileName(
                $portablePackage)
            portable_package_sha256 = $portablePackageHash
            portable_package_files = 9
            portable_package_bundled_source = $true
            reproducible_portable_packages = 2
            visual_baselines = $visualBaselineCount
        }
        $evidence.status = 'pass'
        $evidence.automated_windows_gates = 'pass'
    }
    finally {
        Pop-Location
    }
}
catch {
    $failureMessage = $_.Exception.Message
    $evidence.status = 'fail'
    $evidence.automated_windows_gates = 'fail'
    $evidence.failure = $failureMessage
}
finally {
    if (Test-Path -LiteralPath $workingRoot -PathType Container) {
        try {
            $temporaryRoot = [System.IO.Path]::GetFullPath(
                [System.IO.Path]::GetTempPath())
            $resolvedWorkingRoot = [System.IO.Path]::GetFullPath($workingRoot)
            $temporaryBoundary = $temporaryRoot.TrimEnd('\') + '\'
            $workingLeaf = Split-Path -Leaf $resolvedWorkingRoot
            if (-not $resolvedWorkingRoot.StartsWith(
                    $temporaryBoundary,
                    [System.StringComparison]::OrdinalIgnoreCase) -or
                -not $workingLeaf.StartsWith('opensesh-release-verify-')) {
                throw "Refusing to remove an unexpected work directory: $resolvedWorkingRoot"
            }
            Remove-Item -LiteralPath $resolvedWorkingRoot -Recurse -Force
        }
        catch {
            $evidence.cleanup_failure = $_.Exception.Message
            $evidence.status = 'fail'
            $evidence.automated_windows_gates = 'fail'
            if ($failureMessage -eq '') {
                $failureMessage = $_.Exception.Message
                $evidence.failure = $failureMessage
            }
        }
    }
    $evidence.completed_utc = [DateTime]::UtcNow.ToString('o')
    $evidenceJson = $evidence | ConvertTo-Json -Depth 6
    Write-Utf8Text -Path (Join-Path $evidenceRoot 'release-evidence.json') `
        -Text ($evidenceJson + [Environment]::NewLine)
}

if ($failureMessage -ne '') {
    Write-Error $failureMessage
    Write-Output ('evidence_directory=' + $evidenceRoot)
    exit 1
}

Write-Output 'windows_release_verification_status=pass'
Write-Output 'commercial_release_ready=false'
Write-Output ('evidence_directory=' + $evidenceRoot)
exit 0

# end of verify_windows_release.ps1
