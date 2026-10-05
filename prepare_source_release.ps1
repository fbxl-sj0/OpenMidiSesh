<#
    Project: OpenSesh
    ---------------------------

    File: prepare_source_release.ps1

    Purpose:

        Build an explicit source-only archive for the independent MIDI editor.

    Responsibilities:

        - copy only reviewed project source and documentation
        - reject missing release inputs before creating an archive
        - emit canonical forward-slash ZIP entry paths for Linux extraction
        - keep generated binaries, MIDI output, and analysis trees out of the archive

    This file intentionally does NOT contain:

        - recovered Midisoft executables or libraries
        - decompiler output
        - legal advice or a publication approval
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $OutputArchive
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$ProgressPreference = 'SilentlyContinue'
$projectRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$archivePath = [System.IO.Path]::GetFullPath($OutputArchive)
$manifestFile = Join-Path $projectRoot 'release_manifest.txt'
if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
    throw 'The reviewed project release manifest is missing.'
}
$releaseFiles = @(Get-Content -LiteralPath $manifestFile | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('#')
})

# The vendored dependency has its own exact payload manifest. Derive archive
# entries from it so the source package cannot silently omit a compiled file
# or include an unreviewed sibling from the larger omaGui development tree.
$vendorMetadataFiles = @(
    'vendor\omaGui\DEPENDENCY.md',
    'vendor\omaGui\SNAPSHOT.sha256'
)
$vendorSnapshotFile = Join-Path $projectRoot `
    'vendor\omaGui\SNAPSHOT.sha256'
if (-not (Test-Path -LiteralPath $vendorSnapshotFile -PathType Leaf)) {
    throw "Vendored omaGui snapshot manifest is missing: $vendorSnapshotFile"
}
$releaseFiles += $vendorMetadataFiles
$vendorLineNumber = 0
foreach ($vendorLine in Get-Content -LiteralPath $vendorSnapshotFile) {
    $vendorLineNumber++
    if ([string]::IsNullOrWhiteSpace($vendorLine) -or
        $vendorLine.StartsWith('#')) {
        continue
    }
    $vendorMatch = [regex]::Match(
        $vendorLine,
        '^[0-9a-f]{64}  ([ -~]+)$')
    if (-not $vendorMatch.Success) {
        throw "Malformed omaGui snapshot line $vendorLineNumber."
    }
    $vendorRelativePath = $vendorMatch.Groups[1].Value
    if ($vendorRelativePath.Contains('\') -or
        $vendorRelativePath.StartsWith('/') -or
        $vendorRelativePath.Contains('//') -or
        $vendorRelativePath.Split('/') -contains '..') {
        throw "Unsafe omaGui snapshot path: $vendorRelativePath"
    }
    $releaseFiles += 'vendor\omaGui\' + `
        $vendorRelativePath.Replace('/', '\')
}

$projectBoundary = $projectRoot.TrimEnd('\') + '\'
$releasePathSet = New-Object 'System.Collections.Generic.HashSet[string]' `
    ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($relativeFile in $releaseFiles) {
    if ([string]::IsNullOrWhiteSpace($relativeFile) -or
        [System.IO.Path]::IsPathRooted($relativeFile) -or
        $relativeFile.Contains(':') -or
        $relativeFile.Replace('\', '/').Contains('//') -or
        $relativeFile.Replace('\', '/').Split('/') -contains '.' -or
        $relativeFile.Replace('\', '/').Split('/') -contains '..') {
        throw "Unsafe release manifest path: $relativeFile"
    }
    if (-not $releasePathSet.Add($relativeFile.Replace('\', '/'))) {
        throw "Duplicate release manifest path: $relativeFile"
    }

    $sourceFile = [System.IO.Path]::GetFullPath(
        (Join-Path $projectRoot $relativeFile))
    if (-not $sourceFile.StartsWith(
            $projectBoundary,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        throw "Required release file is missing or unsafe: $relativeFile"
    }
    if ((Get-Item -LiteralPath $sourceFile).Attributes -band
        [System.IO.FileAttributes]::ReparsePoint) {
        throw "Release inputs must be regular files: $relativeFile"
    }
}

# Check bytes before packaging. A stale vendor manifest must never produce an
# apparently self-contained archive which fails verification after extraction.
& (Join-Path $projectRoot 'tests\verify_dependency_snapshot.ps1')
if (-not $?) {
    throw 'GUI dependency verification failed before source packaging.'
}

# Keep the explicit manifest reviewable, but fail when a maintained source,
# test runner, or reviewed image is added without updating that manifest.
$maintainedInputs = @(Get-ChildItem -LiteralPath $projectRoot -File |
    Where-Object { $_.Extension -in @('.bas', '.bi', '.ps1', '.sh') })
$maintainedInputs += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src') `
    -Recurse -File | Where-Object { $_.Extension -in @('.bas', '.bi', '.rc', '.manifest') })
$maintainedInputs += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tools') `
    -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.py', '.sh') })
$maintainedInputs += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') `
    -File | Where-Object { $_.Extension -in @('.bas', '.bi', '.ps1', '.sh') })
$maintainedInputs += @(Get-ChildItem -LiteralPath `
    (Join-Path $projectRoot 'tests\visual_baselines') -File -Filter '*.png')
foreach ($maintainedInput in $maintainedInputs) {
    $relativeInput = $maintainedInput.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
    if (-not $releasePathSet.Contains($relativeInput)) {
        throw "Maintained source or test is missing from the release manifest: $relativeInput"
    }
}

if ([System.StringComparer]::OrdinalIgnoreCase.Equals($archivePath, $projectRoot)) {
    throw 'The output archive path must not be the project directory.'
}
if ([System.IO.Path]::GetExtension($archivePath) -ne '.zip') {
    throw 'The source archive must use a .zip filename.'
}

$parentDirectory = Split-Path -Parent $archivePath
if (-not (Test-Path -LiteralPath $parentDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
}
if (Test-Path -LiteralPath $archivePath) {
    throw "Refusing to overwrite an existing archive: $archivePath"
}

$temporaryArchive = Join-Path $parentDirectory `
    ('.opensesh-source-' + [System.Guid]::NewGuid().ToString('N') +
        '.tmp.zip')
$zipArchive = $null

try {
    <#
        Compress-Archive records backslashes when it receives Windows paths.
        Some Linux unzip tools extract those archives but still return failure.
        Create every entry with a canonical ZIP path so extraction is quiet and
        deterministic on both supported hosts.
    #>
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipArchive = [System.IO.Compression.ZipFile]::Open(
        $temporaryArchive,
        [System.IO.Compression.ZipArchiveMode]::Create)
    foreach ($relativeFile in @($releaseFiles | Sort-Object)) {
        $sourceFile = [System.IO.Path]::GetFullPath(
            (Join-Path $projectRoot $relativeFile))
        $entryName = 'opensesh/' + $relativeFile.Replace('\', '/')
        $entry = $zipArchive.CreateEntry(
            $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        # Create mode requires setting metadata before opening the entry. One
        # fixed epoch removes local modification times from source releases.
        $entry.LastWriteTime = [DateTimeOffset]::new(
            2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $inputStream = [System.IO.File]::OpenRead($sourceFile)
        try {
            $entryStream = $entry.Open()
            try {
                $inputStream.CopyTo($entryStream)
            }
            finally {
                $entryStream.Dispose()
            }
        }
        finally {
            $inputStream.Dispose()
        }
    }
    $zipArchive.Dispose()
    $zipArchive = $null

    if (-not (Test-Path -LiteralPath $temporaryArchive -PathType Leaf) -or
        (Get-Item -LiteralPath $temporaryArchive).Length -le 0) {
        throw 'The temporary source archive was not created.'
    }
    Move-Item -LiteralPath $temporaryArchive -Destination $archivePath
    Write-Output ('source_archive=' + $archivePath)
    Write-Output ('source_files=' + $releaseFiles.Count)
}
finally {
    if ($null -ne $zipArchive) {
        $zipArchive.Dispose()
    }
    if (Test-Path -LiteralPath $temporaryArchive -PathType Leaf) {
        $resolvedTemporaryArchive = [System.IO.Path]::GetFullPath(
            $temporaryArchive)
        $temporaryParent = Split-Path -Parent $resolvedTemporaryArchive
        $temporaryLeaf = Split-Path -Leaf $resolvedTemporaryArchive
        if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(
                $temporaryParent,
                [System.IO.Path]::GetFullPath($parentDirectory)) -or
            $temporaryLeaf -notmatch '^\.opensesh-source-[0-9a-f]{32}\.tmp\.zip$') {
            throw "Refusing to remove an unexpected temporary archive: $resolvedTemporaryArchive"
        }
        Remove-Item -LiteralPath $resolvedTemporaryArchive -Force
    }
}

# end of prepare_source_release.ps1
