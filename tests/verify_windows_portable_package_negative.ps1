<#
    Project: OpenSesh
    ----------------------------

    File: tests/verify_windows_portable_package_negative.ps1

    Purpose:

        Prove that the portable-package verifier rejects corrupt, incomplete,
        unsafe, non-reproducible, and silently modified customer bundles.

    Responsibilities:

        - derive isolated ZIP mutations from one verified control package
        - require every mutation to fail closed
        - remove all generated packages after the test

    This file intentionally does NOT contain:

        - production package modification
        - source compilation
        - certificate or installer tests
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PackagePath,
    [Parameter(Mandatory = $true)]
    [string] $ExecutablePath,
    [Parameter(Mandatory = $true)]
    [string] $SourceArchivePath,
    [string] $VerifierPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

if ([string]::IsNullOrWhiteSpace($VerifierPath)) {
    $VerifierPath = Join-Path $PSScriptRoot `
        'verify_windows_portable_package.ps1'
}
$verifier = [System.IO.Path]::GetFullPath($VerifierPath)
$package = [System.IO.Path]::GetFullPath($PackagePath)
$executable = [System.IO.Path]::GetFullPath($ExecutablePath)
$sourceArchive = [System.IO.Path]::GetFullPath($SourceArchivePath)
foreach ($requiredFile in @($verifier, $package, $executable, $sourceArchive)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Portable-package negative-test input is missing: $requiredFile"
    }
}

# Refuse to test an invalid control because every negative result would then be
# meaningless and could hide a broken verifier invocation.
& $verifier -PackagePath $package -ExecutablePath $executable `
    -SourceArchivePath $sourceArchive | Out-Null

Add-Type -AssemblyName System.IO.Compression
$version = (Get-Item -LiteralPath $executable).VersionInfo.FileVersion
$packageRootName = "OpenSesh-$version-windows-portable"
$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$mutationRoot = Join-Path $temporaryRoot `
    ('opensesh-package-negative-' + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $mutationRoot | Out-Null
$rejectionCount = 0

function Read-EntryBytes {
    param([System.IO.Compression.ZipArchiveEntry] $Entry)

    $entryStream = $Entry.Open()
    $memoryStream = [System.IO.MemoryStream]::new()
    try {
        $entryStream.CopyTo($memoryStream)
        return $memoryStream.ToArray()
    }
    finally {
        $memoryStream.Dispose()
        $entryStream.Dispose()
    }
}

function Write-EntryBytes {
    param(
        [System.IO.Compression.ZipArchive] $Archive,
        [string] $EntryName,
        [byte[]] $Bytes,
        [System.DateTimeOffset] $Timestamp
    )

    $entry = $Archive.CreateEntry(
        $EntryName,
        [System.IO.Compression.CompressionLevel]::Optimal)
    $entry.LastWriteTime = $Timestamp
    $entryStream = $entry.Open()
    try {
        $entryStream.Write($Bytes, 0, $Bytes.Length)
    }
    finally {
        $entryStream.Dispose()
    }
}

function New-MutatedPackage {
    param([string] $Mode, [string] $Destination)

    if ($Mode -eq 'truncated') {
        $controlBytes = [System.IO.File]::ReadAllBytes($package)
        $truncatedBytes = [byte[]]::new(256)
        [Array]::Copy($controlBytes, $truncatedBytes,
            [Math]::Min($controlBytes.Length, $truncatedBytes.Length))
        [System.IO.File]::WriteAllBytes($Destination, $truncatedBytes)
        return
    }

    $sourceStream = [System.IO.File]::OpenRead($package)
    $sourceZip = $null
    $destinationStream = $null
    $destinationZip = $null
    try {
        $sourceZip = [System.IO.Compression.ZipArchive]::new(
            $sourceStream,
            [System.IO.Compression.ZipArchiveMode]::Read,
            $false)
        $destinationStream = [System.IO.File]::Open(
            $Destination,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None)
        $destinationZip = [System.IO.Compression.ZipArchive]::new(
            $destinationStream,
            [System.IO.Compression.ZipArchiveMode]::Create,
            $false)

        foreach ($sourceEntry in $sourceZip.Entries) {
            if ($Mode -eq 'missing-notice' -and
                $sourceEntry.Name -eq 'THIRD_PARTY_NOTICES.md') {
                continue
            }
            $entryBytes = Read-EntryBytes -Entry $sourceEntry
            if ($Mode -eq 'changed-executable' -and
                $sourceEntry.Name -eq 'OpenSesh.exe') {
                if ($entryBytes.Length -lt 1024) {
                    throw 'Control executable is too small for a safe mutation.'
                }
                $entryBytes[1000] = $entryBytes[1000] -bxor 0x01
            }
            $entryTimestamp = $sourceEntry.LastWriteTime
            if ($Mode -eq 'changed-timestamp' -and
                $sourceEntry.Name -eq 'BUILD-INFO.json') {
                $entryTimestamp = [System.DateTimeOffset]::new(
                    2020, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)
            }
            Write-EntryBytes -Archive $destinationZip `
                -EntryName $sourceEntry.FullName `
                -Bytes $entryBytes -Timestamp $entryTimestamp
        }

        $fixedTimestamp = [System.DateTimeOffset]::new(
            1980, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)
        $extraBytes = [System.Text.UTF8Encoding]::new($false).GetBytes("unsafe`n")
        if ($Mode -eq 'extra-file') {
            Write-EntryBytes -Archive $destinationZip `
                -EntryName ($packageRootName + '/unexpected.dll') `
                -Bytes $extraBytes -Timestamp $fixedTimestamp
        }
        elseif ($Mode -eq 'traversal') {
            Write-EntryBytes -Archive $destinationZip `
                -EntryName ($packageRootName + '/../escape.txt') `
                -Bytes $extraBytes -Timestamp $fixedTimestamp
        }
        elseif ($Mode -eq 'duplicate-case') {
            Write-EntryBytes -Archive $destinationZip `
                -EntryName ($packageRootName + '/license') `
                -Bytes $extraBytes -Timestamp $fixedTimestamp
        }
    }
    finally {
        if ($null -ne $destinationZip) {
            $destinationZip.Dispose()
        }
        if ($null -ne $destinationStream) {
            $destinationStream.Dispose()
        }
        if ($null -ne $sourceZip) {
            $sourceZip.Dispose()
        }
        $sourceStream.Dispose()
    }
}

function Assert-PackageRejected {
    param([string] $Mode)

    $candidate = Join-Path $mutationRoot ($Mode + '.zip')
    New-MutatedPackage -Mode $Mode -Destination $candidate
    $wasRejected = $false
    try {
        & $verifier -PackagePath $candidate -ExecutablePath $executable `
            -SourceArchivePath $sourceArchive *> $null
    }
    catch {
        $wasRejected = $true
    }
    if (-not $wasRejected) {
        throw "Portable-package verifier accepted unsafe mutation: $Mode"
    }
    $script:rejectionCount++
}

try {
    foreach ($mutationMode in @(
            'truncated',
            'extra-file',
            'traversal',
            'missing-notice',
            'changed-executable',
            'duplicate-case',
            'changed-timestamp')) {
        Assert-PackageRejected -Mode $mutationMode
    }
}
finally {
    $resolvedMutationRoot = [System.IO.Path]::GetFullPath($mutationRoot)
    $temporaryBoundary = $temporaryRoot.TrimEnd('\') + '\'
    if (-not $resolvedMutationRoot.StartsWith(
            $temporaryBoundary,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Split-Path -Leaf $resolvedMutationRoot).StartsWith(
            'opensesh-package-negative-')) {
        throw "Refusing to remove an unexpected directory: $resolvedMutationRoot"
    }
    if (Test-Path -LiteralPath $resolvedMutationRoot -PathType Container) {
        Remove-Item -LiteralPath $resolvedMutationRoot -Recurse -Force
    }
}

Write-Output 'portable_package_negative_status=ok'
Write-Output ('portable_package_negative_cases=' + $rejectionCount)

# end of tests/verify_windows_portable_package_negative.ps1
