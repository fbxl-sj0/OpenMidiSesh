<#
    Project: OpenSesh
    File: tools/lint.ps1

    Purpose:

        Gate every maintained FreeBASIC source and the exact GUI release subset
        with the installed strict linter, rejecting warnings as well as errors.

    Responsibilities:

        - include application, internal headers and deterministic test sources
        - derive third-party source inputs from the reviewed SHA-256 manifest
        - preserve the native linter status and report its selected identity

    This file intentionally does NOT contain:

        - warning baselines or disabled rule families
        - dependency updates or source rewriting
        - a claim that source lint replaces compilation or target execution
#>

[CmdletBinding()]
param(
    [string] $LinterPath = 'C:\fblint\fb_linter.exe',
    [ValidateSet('windows', 'linux')]
    [string] $Target = 'windows',
    [string] $OutputPath = '',
    [ValidateSet('text', 'jsonl', 'github')]
    [string] $Format = 'text'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$linter = [System.IO.Path]::GetFullPath($LinterPath)
if (-not (Test-Path -LiteralPath $linter -PathType Leaf)) {
    throw "Configured FreeBASIC linter was not found: $linter"
}

$sources = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src') `
    -Recurse -File | Where-Object { $_.Extension -in @('.bas', '.bi') })
$sources += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') `
    -File | Where-Object { $_.Extension -in @('.bas', '.bi') })
$vendorRoot = Join-Path $projectRoot 'vendor\omaGui'
foreach ($line in Get-Content -LiteralPath (Join-Path $vendorRoot 'SNAPSHOT.sha256')) {
    if ($line -match '^[0-9a-f]{64}  ([^\\]+\.(bas|bi))$') {
        $relativePath = $Matches[1]
        if ($relativePath.StartsWith('/') -or
            $relativePath.Split('/') -contains '..') {
            throw "Unsafe dependency source path: $relativePath"
        }
        $sources += Get-Item -LiteralPath (Join-Path $vendorRoot $relativePath)
    }
}
if ($sources.Count -eq 0) {
    throw 'The strict lint source boundary is empty.'
}

$arguments = @('--profile', 'strict', '--target', $Target,
    '--no-semantic', '--honor-suppressions', '--fail-on-warning',
    '--strict-headers', '--strict-tabs', '--format', $Format)
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $reportFile = [System.IO.Path]::GetFullPath($OutputPath)
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $reportFile)) | Out-Null
    $arguments += @('--output-file', $reportFile)
}
$arguments += @($sources | Sort-Object FullName | ForEach-Object {
    $_.FullName.Substring($projectRoot.Length + 1)
})

& $linter --version
if ($LASTEXITCODE -ne 0) {
    throw 'The linter identity query failed.'
}
# The combined project index supplies the GUI declarations that are external
# to application files. Compiler-backed checks do not accept include-path flags
# here, so builds and runtime tests validate the real compiler context separately.
Push-Location $projectRoot
try {
    & $linter @arguments
    $lintExit = $LASTEXITCODE
}
finally {
    Pop-Location
}
Write-Output ('strict_lint_target=' + $Target)
Write-Output ('strict_lint_sources=' + $sources.Count)
Write-Output ('strict_lint_exit=' + $lintExit)
exit $lintExit

# end of tools/lint.ps1
