<#
    Project: OpenSesh
    ---------------------------

    File: tests/verify_dependency_snapshot.ps1

    Purpose:

        Verify the shared omaGUI tree or its source release subset.

    Responsibilities:

        - parse the SHA-256 tree and release subset manifests
        - reject changed, missing, duplicate, unsafe, or extra files
        - require the dependency and embedded-font license documents
        - keep historical fonts out of the release subset

    This file intentionally does NOT contain:

        - compiler installation checks
        - network access or dependency updates
        - an upstream Git commit claim
#>

[CmdletBinding()]
param(
    [string] $OmaGuiPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OmaGuiPath)) {
    $OmaGuiPath = Join-Path $projectRoot 'vendor\omaGui'
}
$vendorRoot = [System.IO.Path]::GetFullPath($OmaGuiPath)
$snapshotFile = Join-Path $vendorRoot 'SNAPSHOT.sha256'
$treeFile = Join-Path $vendorRoot 'TREE.sha256'
$metadataFiles = @('DEPENDENCY.md', 'SNAPSHOT.sha256', 'TREE.sha256')

if (-not (Test-Path -LiteralPath $vendorRoot -PathType Container)) {
    throw "Vendored omaGui directory was not found: $vendorRoot"
}
if (-not (Test-Path -LiteralPath $snapshotFile -PathType Leaf)) {
    throw "omaGui snapshot manifest was not found: $snapshotFile"
}

$vendorBoundary = $vendorRoot.TrimEnd('\') + '\'
$expectedPaths = New-Object 'System.Collections.Generic.HashSet[string]' `
    ([System.StringComparer]::Ordinal)
$expectedHashes = @{}
$lineNumber = 0

foreach ($line in Get-Content -LiteralPath $snapshotFile) {
    $lineNumber++
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
        continue
    }

    $match = [regex]::Match($line, '^([0-9a-f]{64})  ([ -~]+)$')
    if (-not $match.Success) {
        throw "Malformed snapshot line $lineNumber."
    }
    $expectedHash = $match.Groups[1].Value
    $relativePath = $match.Groups[2].Value
    if ($relativePath.Contains('\') -or $relativePath.StartsWith('/') -or
        $relativePath.Contains('//') -or
        $relativePath.Split('/') -contains '..') {
        throw "Unsafe snapshot path on line ${lineNumber}: $relativePath"
    }
    if (-not $expectedPaths.Add($relativePath)) {
        throw "Duplicate snapshot path on line ${lineNumber}: $relativePath"
    }

    $payloadFile = [System.IO.Path]::GetFullPath((Join-Path `
        $vendorRoot $relativePath.Replace('/', '\')))
    if (-not $payloadFile.StartsWith(
            $vendorBoundary,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $payloadFile -PathType Leaf)) {
        throw "Snapshot payload is missing or unsafe: $relativePath"
    }
    $actualHash = (Get-FileHash -LiteralPath $payloadFile `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Snapshot hash differs: $relativePath"
    }
    $expectedHashes[$relativePath] = $expectedHash
}

if ($expectedPaths.Count -le 0) {
    throw 'The omaGui snapshot manifest contains no payload files.'
}

$actualPaths = @(Get-ChildItem -LiteralPath $vendorRoot -Recurse -File |
    ForEach-Object {
        $_.FullName.Substring($vendorRoot.Length + 1).Replace('\', '/')
    } | Where-Object { $metadataFiles -notcontains $_ } | Sort-Object)
if (Test-Path -LiteralPath $treeFile -PathType Leaf) {
    # A development copy carries every asset. Its tree manifest covers the
    # release manifest too, while the release subset remains independently
    # checked above for the archive's narrower font boundary.
    $treePaths = New-Object 'System.Collections.Generic.HashSet[string]' `
        ([System.StringComparer]::Ordinal)
    $treeLineNumber = 0
    foreach ($line in Get-Content -LiteralPath $treeFile) {
        $treeLineNumber++
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }
        $match = [regex]::Match($line, '^([0-9a-f]{64})  ([ -~]+)$')
        if (-not $match.Success) {
            throw "Malformed tree line $treeLineNumber."
        }
        $relativePath = $match.Groups[2].Value
        if ($relativePath.Contains('\') -or $relativePath.StartsWith('/') -or
            $relativePath.Contains('//') -or
            $relativePath.Split('/') -contains '..' -or
            $relativePath -eq 'TREE.sha256') {
            throw "Unsafe tree path on line ${treeLineNumber}: $relativePath"
        }
        if (-not $treePaths.Add($relativePath)) {
            throw "Duplicate tree path on line ${treeLineNumber}: $relativePath"
        }
        $treePayloadFile = [System.IO.Path]::GetFullPath((Join-Path `
            $vendorRoot $relativePath.Replace('/', '\')))
        if (-not $treePayloadFile.StartsWith(
                $vendorBoundary,
                [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $treePayloadFile -PathType Leaf)) {
            throw "Tree payload is missing or unsafe: $relativePath"
        }
        $actualHash = (Get-FileHash -LiteralPath $treePayloadFile `
            -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $match.Groups[1].Value) {
            throw "Tree hash differs: $relativePath"
        }
    }
    $actualTreePaths = @($actualPaths + @('DEPENDENCY.md', 'SNAPSHOT.sha256') | Sort-Object)
    if ($actualTreePaths.Count -ne $treePaths.Count) {
        throw "omaGui tree count differs: expected=$($treePaths.Count) actual=$($actualTreePaths.Count)"
    }
    foreach ($actualPath in $actualTreePaths) {
        if (-not $treePaths.Contains($actualPath)) {
            throw "Unreviewed file exists in the omaGui tree: $actualPath"
        }
    }
    foreach ($snapshotPath in $expectedPaths) {
        if (-not $treePaths.Contains($snapshotPath)) {
            throw "Release subset is missing from the tree: $snapshotPath"
        }
    }
    Write-Output ('omagui_tree_files=' + $treePaths.Count)
} else {
    if ($actualPaths.Count -ne $expectedPaths.Count) {
        throw "omaGui payload count differs: expected=$($expectedPaths.Count) actual=$($actualPaths.Count)"
    }
    foreach ($actualPath in $actualPaths) {
        if (-not $expectedPaths.Contains($actualPath)) {
            throw "Unreviewed file exists in the omaGui snapshot: $actualPath"
        }
    }
}

foreach ($requiredFile in @(
        'DEPENDENCY.md',
        'LICENSE',
        'assets/fonts/FONTS.md',
        'assets/fonts/OFL-1.1.txt',
        'LICENSES/Cascadia-Mono-OFL.txt',
        'LICENSES/LGPL-2.1.txt',
        'LICENSES/Noto-CJK-OFL.txt',
        'LICENSES/Noto-Sans-OFL.txt',
        'LICENSES/Spleen-BSD-2-Clause.txt',
        'omaGUI.bi')) {
    if (-not (Test-Path -LiteralPath (Join-Path `
            $vendorRoot $requiredFile.Replace('/', '\')) -PathType Leaf)) {
        throw "Required omaGui dependency file is missing: $requiredFile"
    }
}

foreach ($payloadPath in $expectedPaths) {
    if ($payloadPath -match '(?i)(^|/)font_arial|font_data_impl\.bi$') {
        throw "Historical font asset is in the release subset: $payloadPath"
    }
    $extension = [System.IO.Path]::GetExtension($payloadPath).ToLowerInvariant()
    if ($extension -notin @('.bas', '.bi', '.md', '.txt', '.ogf', '')) {
        throw "Unexpected omaGui payload type: $payloadPath"
    }
    if ($extension -in @('.bas', '.bi', '.md', '.txt')) {
        $payloadText = Get-Content -LiteralPath `
            (Join-Path $vendorRoot $payloadPath.Replace('/', '\')) -Raw
        if ($payloadText -match '(?i)arialbd?\.ttf' -or
            $payloadText -match '(?i)C:\\Windows\\Fonts\\arial') {
            throw "Removed Windows font conversion is referenced by: $payloadPath"
        }
    }
}

Write-Output 'omagui_snapshot=ok'
Write-Output ('omagui_payload_files=' + $expectedPaths.Count)
Write-Output 'omagui_licenses=MIT,OFL-1.1,LGPL-2.1-or-later,BSD-2-Clause'
Write-Output 'windows_font_conversions=absent'
Write-Output 'dependency_snapshot_status=ok'

# end of tests/verify_dependency_snapshot.ps1
