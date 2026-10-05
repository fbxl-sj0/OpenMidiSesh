<#
    Project: OpenSesh
    ---------------------------

    File: tests/verify_windows_toolchain.ps1

    Purpose:

        Verify the release-critical Windows FreeBASIC toolchain identity.

    Responsibilities:

        - validate the compiler banner against the reviewed lock
        - validate every locked path, length, and SHA-256 digest
        - reject unsafe, duplicate, missing, or malformed lock entries

    This file intentionally does NOT contain:

        - dependency installation or updates
        - Linux package identity checks
        - a complete manifest of unrelated compiler examples and documents
#>

[CmdletBinding()]
param(
    [string] $FreeBasicPath = 'C:\FreeBASIC\fbc.exe',
    [string] $LockPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($LockPath)) {
    $LockPath = Join-Path $projectRoot 'windows_toolchain_lock.json'
}
$compilerPath = [System.IO.Path]::GetFullPath($FreeBasicPath)
$lockFile = [System.IO.Path]::GetFullPath($LockPath)

if (-not (Test-Path -LiteralPath $compilerPath -PathType Leaf)) {
    throw "FreeBASIC compiler was not found: $compilerPath"
}
if (-not (Test-Path -LiteralPath $lockFile -PathType Leaf)) {
    throw "Windows toolchain lock was not found: $lockFile"
}

$lock = Get-Content -LiteralPath $lockFile -Raw | ConvertFrom-Json
if ($lock.schema_version -ne 1 -or
    $lock.platform -ne 'windows-x86_64' -or
    [string]::IsNullOrWhiteSpace($lock.compiler_banner)) {
    throw 'The Windows toolchain lock header is malformed or unsupported.'
}
$lockedFiles = @($lock.files)
if ($lockedFiles.Count -ne 14) {
    throw "Expected 14 locked toolchain files; found $($lockedFiles.Count)."
}

$compilerRoot = [System.IO.Path]::GetFullPath(
    (Split-Path -Parent $compilerPath))
$compilerBoundary = $compilerRoot.TrimEnd('\') + '\'
$pathSet = New-Object 'System.Collections.Generic.HashSet[string]' `
    ([System.StringComparer]::OrdinalIgnoreCase)

foreach ($lockedFile in $lockedFiles) {
    $relativePath = [string] $lockedFile.path
    $expectedHash = ([string] $lockedFile.sha256).ToLowerInvariant()
    $expectedLength = [long] $lockedFile.length
    if ([string]::IsNullOrWhiteSpace($relativePath) -or
        $relativePath.Contains('\') -or
        $relativePath.StartsWith('/') -or
        $relativePath.Contains('//') -or
        $relativePath.Split('/') -contains '.' -or
        $relativePath.Split('/') -contains '..' -or
        $expectedHash -notmatch '^[0-9a-f]{64}$' -or
        $expectedLength -le 0) {
        throw "Unsafe or malformed toolchain lock entry: $relativePath"
    }
    if (-not $pathSet.Add($relativePath)) {
        throw "Duplicate toolchain lock path: $relativePath"
    }

    # fbc.exe identifies the selected compiler even when the installed binary
    # uses another filename, such as fbc64.exe. Other paths stay root-relative.
    if ($relativePath -eq 'fbc.exe') {
        $resolvedFile = $compilerPath
    }
    else {
        $resolvedFile = [System.IO.Path]::GetFullPath((Join-Path `
            $compilerRoot $relativePath.Replace('/', '\')))
    }
    if (-not $resolvedFile.StartsWith(
            $compilerBoundary,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $resolvedFile -PathType Leaf)) {
        throw "Locked toolchain file is missing or unsafe: $relativePath"
    }
    $fileInfo = Get-Item -LiteralPath $resolvedFile
    if ($fileInfo.Length -ne $expectedLength) {
        throw "Locked toolchain length differs: $relativePath"
    }
    $actualHash = (Get-FileHash -LiteralPath $resolvedFile `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Locked toolchain hash differs: $relativePath"
    }
}
if (-not $pathSet.Contains('fbc.exe')) {
    throw 'The Windows toolchain lock is missing the fbc.exe compiler entry.'
}

$compilerOutput = @(& $compilerPath -version 2>&1 | ForEach-Object {
    [string] $_
})
if ($LASTEXITCODE -ne 0 -or $compilerOutput.Count -le 0 -or
    $compilerOutput[0] -ne [string] $lock.compiler_banner) {
    throw 'The FreeBASIC compiler banner differs from the reviewed lock.'
}

Write-Output 'windows_toolchain=locked'
Write-Output ('windows_toolchain_files=' + $lockedFiles.Count)
Write-Output ('freebasic_banner=' + $compilerOutput[0])
Write-Output 'windows_toolchain_status=ok'

# end of tests/verify_windows_toolchain.ps1
