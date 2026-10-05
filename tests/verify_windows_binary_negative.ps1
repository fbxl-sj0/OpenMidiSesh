<#
    Project: OpenSesh
    ----------------------------

    File: tests/verify_windows_binary_negative.ps1

    Purpose:

        Prove that the Windows binary verifier rejects representative damaged,
        weakened, contaminated, and dependency-expanded PE images.

    Responsibilities:

        - create isolated mutations of one already verified executable
        - require every unsafe mutation to fail closed
        - remove all generated candidates after the test

    This file intentionally does NOT contain:

        - executable signing
        - production binary modification
        - antivirus or exploit testing
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ExecutablePath,
    [string] $VerifierPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($VerifierPath)) {
    $VerifierPath = Join-Path $PSScriptRoot 'verify_windows_binary.ps1'
}
$verifier = [System.IO.Path]::GetFullPath($VerifierPath)
$executable = [System.IO.Path]::GetFullPath($ExecutablePath)
if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) {
    throw "Windows binary verifier was not found: $verifier"
}
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Windows executable was not found: $executable"
}

# The mutation oracle is meaningful only if the unmodified control passes.
& $verifier -ExecutablePath $executable -RequireUnsignedDevelopmentBuild | Out-Null
$originalBytes = [System.IO.File]::ReadAllBytes($executable)

function Read-CandidateUInt16 {
    param([byte[]] $Bytes, [int] $Offset)
    return [uint16] ([uint16] $Bytes[$Offset] -bor
        ([uint16] $Bytes[$Offset + 1] -shl 8))
}

function Read-CandidateUInt32 {
    param([byte[]] $Bytes, [int] $Offset)
    return [uint32] ([uint32] $Bytes[$Offset] -bor
        ([uint32] $Bytes[$Offset + 1] -shl 8) -bor
        ([uint32] $Bytes[$Offset + 2] -shl 16) -bor
        ([uint32] $Bytes[$Offset + 3] -shl 24))
}

function Write-CandidateUInt16 {
    param([byte[]] $Bytes, [int] $Offset, [uint16] $Value)
    $Bytes[$Offset] = [byte] ($Value -band 0xff)
    $Bytes[$Offset + 1] = [byte] (($Value -shr 8) -band 0xff)
}

function Write-CandidateUInt32 {
    param([byte[]] $Bytes, [int] $Offset, [uint32] $Value)
    for ($byteIndex = 0; $byteIndex -lt 4; $byteIndex++) {
        $Bytes[$Offset + $byteIndex] = [byte] (
            ($Value -shr (8 * $byteIndex)) -band 0xff)
    }
}

$peOffset = [int] (Read-CandidateUInt32 -Bytes $originalBytes -Offset 0x3c)
$optionalOffset = $peOffset + 24
$sectionCount = Read-CandidateUInt16 -Bytes $originalBytes `
    -Offset ($peOffset + 6)
$optionalBytes = Read-CandidateUInt16 -Bytes $originalBytes `
    -Offset ($peOffset + 20)
$sectionTableOffset = $optionalOffset + $optionalBytes
$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$mutationRoot = Join-Path $temporaryRoot `
    ('opensesh-pe-negative-' + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $mutationRoot | Out-Null
$rejectionCount = 0

function Assert-MutationRejected {
    param([string] $Name, [byte[]] $Bytes)

    $candidatePath = Join-Path $mutationRoot ($Name + '.exe')
    [System.IO.File]::WriteAllBytes($candidatePath, $Bytes)
    $wasRejected = $false
    try {
        & $verifier -ExecutablePath $candidatePath `
            -RequireUnsignedDevelopmentBuild *> $null
    }
    catch {
        $wasRejected = $true
    }
    if (-not $wasRejected) {
        throw "Windows binary verifier accepted unsafe mutation: $Name"
    }
    $script:rejectionCount++
}

try {
    $truncated = [byte[]]::new(256)
    [Array]::Copy($originalBytes, $truncated, 256)
    Assert-MutationRejected -Name 'truncated' -Bytes $truncated

    $wrongMachine = [byte[]] $originalBytes.Clone()
    Write-CandidateUInt16 -Bytes $wrongMachine -Offset ($peOffset + 4) `
        -Value 0x014c
    Assert-MutationRejected -Name 'wrong-machine' -Bytes $wrongMachine

    $dated = [byte[]] $originalBytes.Clone()
    Write-CandidateUInt32 -Bytes $dated -Offset ($peOffset + 8) -Value 1
    Assert-MutationRejected -Name 'nonzero-timestamp' -Bytes $dated

    $noNx = [byte[]] $originalBytes.Clone()
    $characteristics = Read-CandidateUInt16 -Bytes $noNx `
        -Offset ($optionalOffset + 70)
    Write-CandidateUInt16 -Bytes $noNx -Offset ($optionalOffset + 70) `
        -Value ([uint16] ($characteristics -band (-bnot 0x0100)))
    Assert-MutationRejected -Name 'no-nx' -Bytes $noNx

    $debugSection = [byte[]] $originalBytes.Clone()
    $relocationHeader = -1
    for ($sectionIndex = 0; $sectionIndex -lt $sectionCount; $sectionIndex++) {
        $headerOffset = $sectionTableOffset + (40 * $sectionIndex)
        $name = [System.Text.Encoding]::ASCII.GetString(
            $debugSection, $headerOffset, 8).Trim([char] 0)
        if ($name -eq '.reloc') {
            $relocationHeader = $headerOffset
            break
        }
    }
    if ($relocationHeader -lt 0) {
        throw 'The control executable has no relocation section to mutate.'
    }
    $debugName = [System.Text.Encoding]::ASCII.GetBytes('.debug')
    [Array]::Clear($debugSection, $relocationHeader, 8)
    [Array]::Copy($debugName, 0, $debugSection, $relocationHeader,
        $debugName.Length)
    Assert-MutationRejected -Name 'debug-section' -Bytes $debugSection

    $unexpectedImport = [byte[]] $originalBytes.Clone()
    $expectedName = [System.Text.Encoding]::ASCII.GetBytes("KERNEL32.dll`0")
    $replacementName = [System.Text.Encoding]::ASCII.GetBytes("BADAPI32.dll`0")
    $importNameOffset = -1
    for ($byteIndex = 0;
        $byteIndex -le $unexpectedImport.Length - $expectedName.Length;
        $byteIndex++) {
        $matches = $true
        for ($nameIndex = 0; $nameIndex -lt $expectedName.Length; $nameIndex++) {
            if ($unexpectedImport[$byteIndex + $nameIndex] -ne
                $expectedName[$nameIndex]) {
                $matches = $false
                break
            }
        }
        if ($matches) {
            $importNameOffset = $byteIndex
            break
        }
    }
    if ($importNameOffset -lt 0) {
        throw 'The reviewed KERNEL32 import name was not found.'
    }
    [Array]::Copy($replacementName, 0, $unexpectedImport,
        $importNameOffset, $replacementName.Length)
    Assert-MutationRejected -Name 'unexpected-import' -Bytes $unexpectedImport

    $localPath = [byte[]] $originalBytes.Clone()
    $pathBytes = [System.Text.Encoding]::ASCII.GetBytes(
        'C:\Users\release-secret\source')
    $slackOffset = -1
    for ($sectionIndex = 0; $sectionIndex -lt $sectionCount; $sectionIndex++) {
        $headerOffset = $sectionTableOffset + (40 * $sectionIndex)
        $virtualSize = Read-CandidateUInt32 -Bytes $localPath `
            -Offset ($headerOffset + 8)
        $rawSize = Read-CandidateUInt32 -Bytes $localPath `
            -Offset ($headerOffset + 16)
        $rawOffset = Read-CandidateUInt32 -Bytes $localPath `
            -Offset ($headerOffset + 20)
        if ($rawSize -ge $virtualSize + $pathBytes.Length) {
            $slackOffset = [int] ($rawOffset + $virtualSize)
            break
        }
    }
    if ($slackOffset -lt 0) {
        throw 'No section padding is available for the path-leak mutation.'
    }
    [Array]::Copy($pathBytes, 0, $localPath, $slackOffset, $pathBytes.Length)
    Assert-MutationRejected -Name 'local-path' -Bytes $localPath

    $overlay = [byte[]]::new($originalBytes.Length + 1)
    [Array]::Copy($originalBytes, $overlay, $originalBytes.Length)
    $overlay[$overlay.Length - 1] = 0x41
    Assert-MutationRejected -Name 'overlay' -Bytes $overlay
}
finally {
    $resolvedMutationRoot = [System.IO.Path]::GetFullPath($mutationRoot)
    $temporaryBoundary = $temporaryRoot.TrimEnd('\') + '\'
    if (-not $resolvedMutationRoot.StartsWith(
            $temporaryBoundary,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Split-Path -Leaf $resolvedMutationRoot).StartsWith(
            'opensesh-pe-negative-')) {
        throw "Refusing to remove an unexpected directory: $resolvedMutationRoot"
    }
    if (Test-Path -LiteralPath $resolvedMutationRoot -PathType Container) {
        Remove-Item -LiteralPath $resolvedMutationRoot -Recurse -Force
    }
}

Write-Output 'windows_binary_negative_status=ok'
Write-Output ('windows_binary_negative_cases=' + $rejectionCount)

# end of tests/verify_windows_binary_negative.ps1
