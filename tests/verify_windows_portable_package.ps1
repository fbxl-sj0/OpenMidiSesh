<#
    Project: OpenSesh
    ----------------------------

    File: tests/verify_windows_portable_package.ps1

    Purpose:

        Verify the final Windows portable ZIP as a complete customer-facing
        bundle rather than trusting the package creator's success status.

    Responsibilities:

        - reject unsafe paths, duplicate names, extra files, and changed dates
        - compare executable, source, licenses, notices, and readme byte hashes
        - verify internal checksums and machine-readable build identity
        - require bundled corresponding source for the GPL binary

    This file intentionally does NOT contain:

        - package creation
        - source compilation
        - installer or signature approval
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PackagePath,
    [Parameter(Mandatory = $true)]
    [string] $ExecutablePath,
    [Parameter(Mandatory = $true)]
    [string] $SourceArchivePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$package = [System.IO.Path]::GetFullPath($PackagePath)
$executable = [System.IO.Path]::GetFullPath($ExecutablePath)
$sourceArchive = [System.IO.Path]::GetFullPath($SourceArchivePath)
foreach ($requiredFile in @($package, $executable, $sourceArchive)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Portable-package verification input is missing: $requiredFile"
    }
}

$versionInfo = (Get-Item -LiteralPath $executable).VersionInfo
$version = $versionInfo.FileVersion
if ($versionInfo.ProductName -ne 'OpenSesh' -or
    $version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+-[A-Za-z0-9.]+$') {
    throw 'Portable executable version metadata is invalid.'
}
$rootName = "OpenSesh-$version-windows-portable"
$sourceName = "OpenSesh-source-$version.zip"
if ([System.IO.Path]::GetFileName($sourceArchive) -ne $sourceName) {
    throw "Corresponding source archive must be named $sourceName."
}

$expectedRelativeNames = @(
    'BUILD-INFO.json',
    'COPYING',
    'COPYING.LESSER',
    'LICENSE',
    'OpenSesh.exe',
    'README.txt',
    'SHA256SUMS.txt',
    ('source/' + $sourceName),
    'THIRD_PARTY_NOTICES.md'
)
$expectedPathSet = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
foreach ($relativeName in $expectedRelativeNames) {
    [void] $expectedPathSet.Add($rootName + '/' + $relativeName)
}

function Get-ByteSha256 {
    param([byte[]] $Bytes)

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString(
            $algorithm.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $algorithm.Dispose()
    }
}

Add-Type -AssemblyName System.IO.Compression
$packageStream = [System.IO.File]::OpenRead($package)
$zipArchive = $null
$payload = [ordered]@{}
try {
    $zipArchive = [System.IO.Compression.ZipArchive]::new(
        $packageStream,
        [System.IO.Compression.ZipArchiveMode]::Read,
        $false)
    if ($zipArchive.Entries.Count -ne $expectedRelativeNames.Count) {
        throw ('Portable package file count differs: expected={0} actual={1}' -f
            $expectedRelativeNames.Count, $zipArchive.Entries.Count)
    }

    $seenPaths = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $zipArchive.Entries) {
        $entryPath = $entry.FullName
        if ($entry.Name -eq '' -or $entryPath.Contains('\') -or
            $entryPath.StartsWith('/') -or $entryPath.Contains(':') -or
            $entryPath -match '(^|/)\.\.(/|$)' -or
            -not $expectedPathSet.Contains($entryPath)) {
            throw "Portable package contains an unsafe or unexpected path: $entryPath"
        }
        if (-not $seenPaths.Add($entryPath)) {
            throw "Portable package contains a duplicate path: $entryPath"
        }
        # ZIP stores a DOS wall-clock value without a timezone. Compare the
        # recorded fields, not the host-specific offset assigned while reading.
        if ($entry.LastWriteTime.Year -ne 1980 -or
            $entry.LastWriteTime.Month -ne 1 -or
            $entry.LastWriteTime.Day -ne 1 -or
            $entry.LastWriteTime.Hour -ne 0 -or
            $entry.LastWriteTime.Minute -ne 0 -or
            $entry.LastWriteTime.Second -ne 0) {
            throw "Portable package entry timestamp changed: $entryPath"
        }
        if ($entry.Length -lt 1 -or $entry.Length -gt 100MB) {
            throw "Portable package entry size is outside bounds: $entryPath"
        }

        $entryStream = $entry.Open()
        $memoryStream = [System.IO.MemoryStream]::new()
        try {
            $entryStream.CopyTo($memoryStream)
            if ($memoryStream.Length -ne $entry.Length) {
                throw "Portable package entry ended early: $entryPath"
            }
            $relativeName = $entryPath.Substring($rootName.Length + 1)
            $payload[$relativeName] = $memoryStream.ToArray()
        }
        finally {
            $memoryStream.Dispose()
            $entryStream.Dispose()
        }
    }
}
finally {
    if ($null -ne $zipArchive) {
        $zipArchive.Dispose()
    }
    $packageStream.Dispose()
}

$executableHash = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash
$sourceHash = (Get-FileHash -LiteralPath $sourceArchive -Algorithm SHA256).Hash
if ((Get-ByteSha256 -Bytes $payload['OpenSesh.exe']) -ne
    $executableHash) {
    throw 'Portable package executable differs from the verified build.'
}
$sourceEntry = 'source/' + $sourceName
if ((Get-ByteSha256 -Bytes $payload[$sourceEntry]) -ne $sourceHash) {
    throw 'Portable package source differs from the verified source archive.'
}

$sourceDocumentMap = [ordered]@{
    'README.txt' = (Join-Path $projectRoot 'PORTABLE_README.txt')
    'LICENSE' = (Join-Path $projectRoot 'LICENSE')
    'COPYING' = (Join-Path $projectRoot 'COPYING')
    'COPYING.LESSER' = (Join-Path $projectRoot 'COPYING.LESSER')
    'THIRD_PARTY_NOTICES.md' = (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md')
}
foreach ($relativeName in $sourceDocumentMap.Keys) {
    $sourceDocument = $sourceDocumentMap[$relativeName]
    if (-not (Test-Path -LiteralPath $sourceDocument -PathType Leaf)) {
        throw "Current package document is missing: $sourceDocument"
    }
    $sourceDocumentHash = (Get-FileHash -LiteralPath $sourceDocument `
        -Algorithm SHA256).Hash
    if ((Get-ByteSha256 -Bytes $payload[$relativeName]) -ne
        $sourceDocumentHash) {
        throw "Portable package document differs from source: $relativeName"
    }
}

$buildInfoText = [System.Text.UTF8Encoding]::new($false).GetString(
    $payload['BUILD-INFO.json'])
if (-not $buildInfoText.EndsWith("`n") -or $buildInfoText.Contains("`r")) {
    throw 'Portable build information is not canonical LF text.'
}
$buildInfo = $buildInfoText | ConvertFrom-Json
$toolchainLockHash = (Get-FileHash -LiteralPath (
    Join-Path $projectRoot 'windows_toolchain_lock.json') -Algorithm SHA256).Hash
if ($buildInfo.schema_version -ne 1 -or
    $buildInfo.product -ne 'OpenSesh' -or
    $buildInfo.version -ne $version -or
    $buildInfo.platform -ne 'windows-x86_64' -or
    $buildInfo.package_kind -ne 'portable-unsigned-development' -or
    $buildInfo.executable_file -ne 'OpenSesh.exe' -or
    $buildInfo.executable_sha256 -ne $executableHash -or
    $buildInfo.source_archive_file -ne $sourceName -or
    $buildInfo.source_archive_sha256 -ne $sourceHash -or
    $buildInfo.windows_toolchain_lock_sha256 -ne $toolchainLockHash -or
    $buildInfo.reproducible_binary -ne $true -or
    $buildInfo.bundled_corresponding_source -ne $true) {
    throw 'Portable BUILD-INFO.json does not match the verified release inputs.'
}

$manifestText = [System.Text.UTF8Encoding]::new($false).GetString(
    $payload['SHA256SUMS.txt'])
if (-not $manifestText.EndsWith("`n") -or $manifestText.Contains("`r")) {
    throw 'Portable SHA-256 manifest is not canonical LF text.'
}
$actualManifestLines = @($manifestText.TrimEnd("`n").Split("`n"))
$expectedManifestLines = [System.Collections.Generic.List[string]]::new()
foreach ($relativeName in @($payload.Keys | Where-Object {
            $_ -ne 'SHA256SUMS.txt'
        } | Sort-Object)) {
    $expectedManifestLines.Add(
        (Get-ByteSha256 -Bytes $payload[$relativeName]).ToLowerInvariant() +
        '  ' + $relativeName)
}
if ($actualManifestLines.Count -ne $expectedManifestLines.Count) {
    throw 'Portable SHA-256 manifest row count differs.'
}
for ($lineIndex = 0; $lineIndex -lt $expectedManifestLines.Count; $lineIndex++) {
    if ($actualManifestLines[$lineIndex] -cne $expectedManifestLines[$lineIndex]) {
        throw "Portable SHA-256 manifest differs at row $($lineIndex + 1)."
    }
}

Write-Output 'portable_package_status=ok'
Write-Output ('portable_package_files=' + $payload.Count)
Write-Output 'portable_package_notice_files=4'
Write-Output 'portable_package_bundled_source=1'
Write-Output ('portable_package_root=' + $rootName)
Write-Output ('portable_package_sha256=' + (
    Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash)

# end of tests/verify_windows_portable_package.ps1
