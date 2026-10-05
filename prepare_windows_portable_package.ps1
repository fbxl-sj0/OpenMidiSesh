<#
    Project: OpenSesh
    ----------------------------

    File: prepare_windows_portable_package.ps1

    Purpose:

        Create the deterministic, unsigned Windows portable package from one
        verified executable and its exact corresponding source archive.

    Responsibilities:

        - include the executable, source, licenses, notices, and user readme
        - record exact executable, source, and toolchain-lock identities
        - generate an internal SHA-256 manifest
        - write sorted ZIP entries with one fixed timestamp

    This file intentionally does NOT contain:

        - compilation or test execution
        - installer creation
        - executable or package signing
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ExecutablePath,
    [Parameter(Mandatory = $true)]
    [string] $SourceArchivePath,
    [Parameter(Mandatory = $true)]
    [string] $OutputPackage
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$executable = [System.IO.Path]::GetFullPath($ExecutablePath)
$sourceArchive = [System.IO.Path]::GetFullPath($SourceArchivePath)
$packagePath = [System.IO.Path]::GetFullPath($OutputPackage)
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Verified Windows executable was not found: $executable"
}
if (-not (Test-Path -LiteralPath $sourceArchive -PathType Leaf)) {
    throw "Corresponding source archive was not found: $sourceArchive"
}
if ([System.IO.Path]::GetExtension($packagePath) -ne '.zip') {
    throw 'Portable package output must use the .zip extension.'
}
if (Test-Path -LiteralPath $packagePath) {
    throw "Refusing to overwrite an existing portable package: $packagePath"
}

$packageParent = Split-Path -Parent $packagePath
if (-not (Test-Path -LiteralPath $packageParent -PathType Container)) {
    New-Item -ItemType Directory -Path $packageParent -Force | Out-Null
}

$versionInfo = (Get-Item -LiteralPath $executable).VersionInfo
$version = $versionInfo.FileVersion
if ($versionInfo.ProductName -ne 'OpenSesh' -or
    $version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+-[A-Za-z0-9.]+$') {
    throw 'Windows executable has no valid development product version.'
}
$expectedSourceName = "OpenSesh-source-$version.zip"
if ([System.IO.Path]::GetFileName($sourceArchive) -ne $expectedSourceName) {
    throw "Corresponding source archive must be named $expectedSourceName."
}

$documentMap = [ordered]@{
    'README.txt' = (Join-Path $projectRoot 'PORTABLE_README.txt')
    'LICENSE' = (Join-Path $projectRoot 'LICENSE')
    'COPYING' = (Join-Path $projectRoot 'COPYING')
    'COPYING.LESSER' = (Join-Path $projectRoot 'COPYING.LESSER')
    'THIRD_PARTY_NOTICES.md' = (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md')
}
foreach ($documentPath in $documentMap.Values) {
    if (-not (Test-Path -LiteralPath $documentPath -PathType Leaf)) {
        throw "Required portable-package document is missing: $documentPath"
    }
}
$toolchainLock = Join-Path $projectRoot 'windows_toolchain_lock.json'
if (-not (Test-Path -LiteralPath $toolchainLock -PathType Leaf)) {
    throw 'Windows toolchain lock is missing.'
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

$executableBytes = [System.IO.File]::ReadAllBytes($executable)
$sourceBytes = [System.IO.File]::ReadAllBytes($sourceArchive)
$executableHash = Get-ByteSha256 -Bytes $executableBytes
$sourceHash = Get-ByteSha256 -Bytes $sourceBytes
$toolchainLockHash = (Get-FileHash -LiteralPath $toolchainLock `
    -Algorithm SHA256).Hash
$rootName = "OpenSesh-$version-windows-portable"

$payload = [ordered]@{}
$payload['OpenSesh.exe'] = $executableBytes
foreach ($documentName in $documentMap.Keys) {
    $payload[$documentName] = [System.IO.File]::ReadAllBytes(
        $documentMap[$documentName])
}
$sourceEntry = 'source/' + $expectedSourceName
$payload[$sourceEntry] = $sourceBytes

$buildInfo = [ordered]@{
    schema_version = 1
    product = 'OpenSesh'
    version = $version
    platform = 'windows-x86_64'
    package_kind = 'portable-unsigned-development'
    executable_file = 'OpenSesh.exe'
    executable_sha256 = $executableHash
    source_archive_file = $expectedSourceName
    source_archive_sha256 = $sourceHash
    windows_toolchain_lock_sha256 = $toolchainLockHash
    reproducible_binary = $true
    bundled_corresponding_source = $true
}
$buildInfoText = (($buildInfo | ConvertTo-Json -Depth 3) -replace
    "`r`n", "`n") + "`n"
$payload['BUILD-INFO.json'] = [System.Text.UTF8Encoding]::new($false).GetBytes(
    $buildInfoText)

$manifestLines = [System.Collections.Generic.List[string]]::new()
foreach ($relativeName in @($payload.Keys | Sort-Object)) {
    $manifestLines.Add(
        (Get-ByteSha256 -Bytes $payload[$relativeName]).ToLowerInvariant() +
        '  ' + $relativeName)
}
$manifestText = ($manifestLines -join "`n") + "`n"
$payload['SHA256SUMS.txt'] = [System.Text.UTF8Encoding]::new($false).GetBytes(
    $manifestText)

Add-Type -AssemblyName System.IO.Compression
$packageStream = $null
$zipArchive = $null
try {
    $packageStream = [System.IO.File]::Open(
        $packagePath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None)
    $zipArchive = [System.IO.Compression.ZipArchive]::new(
        $packageStream,
        [System.IO.Compression.ZipArchiveMode]::Create,
        $false)
    $fixedTimestamp = [System.DateTimeOffset]::new(
        1980, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)

    foreach ($relativeName in @($payload.Keys | Sort-Object)) {
        $entry = $zipArchive.CreateEntry(
            $rootName + '/' + $relativeName,
            [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $fixedTimestamp
        $entryStream = $entry.Open()
        try {
            $entryBytes = [byte[]] $payload[$relativeName]
            $entryStream.Write($entryBytes, 0, $entryBytes.Length)
        }
        finally {
            $entryStream.Dispose()
        }
    }
}
catch {
    if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
        Remove-Item -LiteralPath $packagePath -Force
    }
    throw
}
finally {
    if ($null -ne $zipArchive) {
        $zipArchive.Dispose()
    }
    if ($null -ne $packageStream) {
        $packageStream.Dispose()
    }
}

$packageHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
Write-Output ('portable_package=' + $packagePath)
Write-Output ('portable_package_sha256=' + $packageHash)
Write-Output ('portable_package_files=' + $payload.Count)
Write-Output ('portable_package_root=' + $rootName)
Write-Output ('portable_executable_sha256=' + $executableHash)
Write-Output ('portable_source_sha256=' + $sourceHash)

# end of prepare_windows_portable_package.ps1
