<#
    Project: OpenSesh
    ----------------------------

    File: tests/verify_windows_binary.ps1

    Purpose:

        Inspect the final Windows executable as a PE image without trusting
        filename extensions or an external binary-inspection installation.

    Responsibilities:

        - require a stripped 64-bit Windows GUI image with a zero timestamp
        - require relocations, high-entropy ASLR, dynamic ASLR, and NX support
        - allow only the reviewed Windows system-library import set
        - reject overlays, debug sections, local build paths, and bad signatures

    This file intentionally does NOT contain:

        - source compilation
        - application runtime tests
        - certificate acquisition or release signing
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ExecutablePath,
    [switch] $RequireUnsignedDevelopmentBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

if ($env:OS -ne 'Windows_NT') {
    throw 'Windows PE verification requires Windows.'
}

$executable = [System.IO.Path]::GetFullPath($ExecutablePath)
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Windows executable was not found: $executable"
}

$script:binaryBytes = [System.IO.File]::ReadAllBytes($executable)
if ($script:binaryBytes.LongLength -lt 1024 -or
    $script:binaryBytes.LongLength -gt 100MB) {
    throw 'Windows executable size is outside the reviewed release bounds.'
}

function Assert-BinaryRange {
    param(
        [long] $Offset,
        [long] $Count,
        [string] $Description
    )

    if ($Offset -lt 0 -or $Count -lt 0 -or
        $Offset -gt $script:binaryBytes.LongLength -or
        $Count -gt ($script:binaryBytes.LongLength - $Offset)) {
        throw "PE field is outside the file: $Description"
    }
}

function Read-UInt16LE {
    param([long] $Offset, [string] $Description)

    Assert-BinaryRange -Offset $Offset -Count 2 -Description $Description
    return [uint16] (
        [uint16] $script:binaryBytes[$Offset] -bor
        ([uint16] $script:binaryBytes[$Offset + 1] -shl 8))
}

function Read-UInt32LE {
    param([long] $Offset, [string] $Description)

    Assert-BinaryRange -Offset $Offset -Count 4 -Description $Description
    return [uint32] (
        [uint32] $script:binaryBytes[$Offset] -bor
        ([uint32] $script:binaryBytes[$Offset + 1] -shl 8) -bor
        ([uint32] $script:binaryBytes[$Offset + 2] -shl 16) -bor
        ([uint32] $script:binaryBytes[$Offset + 3] -shl 24))
}

function Read-AsciiField {
    param(
        [long] $Offset,
        [int] $MaximumBytes,
        [string] $Description
    )

    Assert-BinaryRange -Offset $Offset -Count 1 -Description $Description
    $characters = [System.Collections.Generic.List[char]]::new()
    for ($index = 0; $index -lt $MaximumBytes; $index++) {
        Assert-BinaryRange -Offset ($Offset + $index) -Count 1 `
            -Description $Description
        $value = $script:binaryBytes[$Offset + $index]
        if ($value -eq 0) {
            return -join $characters
        }
        if ($value -lt 32 -or $value -gt 126) {
            throw "PE text field is not printable ASCII: $Description"
        }
        $characters.Add([char] $value)
    }
    throw "PE text field is not terminated: $Description"
}

if ($script:binaryBytes[0] -ne 0x4d -or
    $script:binaryBytes[1] -ne 0x5a) {
    throw 'Windows executable is missing its MZ signature.'
}

$peOffset = [long] (Read-UInt32LE -Offset 0x3c `
    -Description 'DOS e_lfanew')
Assert-BinaryRange -Offset $peOffset -Count 24 -Description 'PE header'
if ($script:binaryBytes[$peOffset] -ne 0x50 -or
    $script:binaryBytes[$peOffset + 1] -ne 0x45 -or
    $script:binaryBytes[$peOffset + 2] -ne 0 -or
    $script:binaryBytes[$peOffset + 3] -ne 0) {
    throw 'Windows executable is missing its PE signature.'
}

$machine = Read-UInt16LE -Offset ($peOffset + 4) -Description 'COFF machine'
$sectionCount = Read-UInt16LE -Offset ($peOffset + 6) `
    -Description 'COFF section count'
$coffTimestamp = Read-UInt32LE -Offset ($peOffset + 8) `
    -Description 'COFF timestamp'
$optionalHeaderBytes = Read-UInt16LE -Offset ($peOffset + 20) `
    -Description 'COFF optional-header size'
$fileCharacteristics = Read-UInt16LE -Offset ($peOffset + 22) `
    -Description 'COFF characteristics'
$optionalOffset = $peOffset + 24

if ($machine -ne 0x8664) {
    throw ('Expected AMD64 machine 0x8664; found 0x{0:X4}.' -f $machine)
}
if ($sectionCount -lt 1 -or $sectionCount -gt 96) {
    throw "PE section count is outside the reviewed bounds: $sectionCount"
}
if ($optionalHeaderBytes -lt 240) {
    throw 'PE32+ optional header is incomplete.'
}
Assert-BinaryRange -Offset $optionalOffset -Count $optionalHeaderBytes `
    -Description 'PE optional header'
if ((Read-UInt16LE -Offset $optionalOffset `
        -Description 'optional-header magic') -ne 0x20b) {
    throw 'Windows executable is not a PE32+ image.'
}
if (($fileCharacteristics -band 0x0002) -eq 0 -or
    ($fileCharacteristics -band 0x0020) -eq 0) {
    throw 'PE image is not executable and large-address aware.'
}
if ($coffTimestamp -ne 0) {
    throw 'PE build timestamp is not zero; the binary is not reproducible.'
}

$checksum = Read-UInt32LE -Offset ($optionalOffset + 64) `
    -Description 'PE checksum'
$subsystem = Read-UInt16LE -Offset ($optionalOffset + 68) `
    -Description 'PE subsystem'
$dllCharacteristics = Read-UInt16LE -Offset ($optionalOffset + 70) `
    -Description 'PE DLL characteristics'
$sizeOfHeaders = Read-UInt32LE -Offset ($optionalOffset + 60) `
    -Description 'PE header size'
$dataDirectoryCount = Read-UInt32LE -Offset ($optionalOffset + 108) `
    -Description 'PE data-directory count'

if ($checksum -eq 0) {
    throw 'PE checksum is absent.'
}
if ($subsystem -ne 2) {
    throw "Expected the Windows GUI subsystem; found $subsystem."
}
foreach ($hardeningFlag in @(
        [pscustomobject]@{ Mask = 0x0020; Name = 'HIGH_ENTROPY_VA' },
        [pscustomobject]@{ Mask = 0x0040; Name = 'DYNAMIC_BASE' },
        [pscustomobject]@{ Mask = 0x0100; Name = 'NX_COMPAT' })) {
    if (($dllCharacteristics -band $hardeningFlag.Mask) -eq 0) {
        throw "PE hardening flag is missing: $($hardeningFlag.Name)"
    }
}
if ($dataDirectoryCount -lt 5) {
    throw 'PE data-directory table is incomplete.'
}

$sectionTableOffset = $optionalOffset + $optionalHeaderBytes
Assert-BinaryRange -Offset $sectionTableOffset `
    -Count (40 * $sectionCount) -Description 'PE section table'
$sections = [System.Collections.Generic.List[object]]::new()
$maximumRawEnd = [long] $sizeOfHeaders
$hasRelocations = $false

for ($sectionIndex = 0; $sectionIndex -lt $sectionCount; $sectionIndex++) {
    $sectionOffset = $sectionTableOffset + (40 * $sectionIndex)
    $sectionName = Read-AsciiField -Offset $sectionOffset -MaximumBytes 8 `
        -Description "section $sectionIndex name"
    $virtualSize = Read-UInt32LE -Offset ($sectionOffset + 8) `
        -Description "$sectionName virtual size"
    $virtualAddress = Read-UInt32LE -Offset ($sectionOffset + 12) `
        -Description "$sectionName virtual address"
    $rawSize = Read-UInt32LE -Offset ($sectionOffset + 16) `
        -Description "$sectionName raw size"
    $rawOffset = Read-UInt32LE -Offset ($sectionOffset + 20) `
        -Description "$sectionName raw offset"

    if ($sectionName.StartsWith('.debug',
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Release binary contains a debug section: $sectionName"
    }
    if ($sectionName -eq '.reloc') {
        $hasRelocations = $true
    }
    if ($rawSize -gt 0) {
        Assert-BinaryRange -Offset $rawOffset -Count $rawSize `
            -Description "$sectionName raw data"
        $rawEnd = [long] $rawOffset + [long] $rawSize
        if ($rawEnd -gt $maximumRawEnd) {
            $maximumRawEnd = $rawEnd
        }
    }
    $sections.Add([pscustomobject]@{
        Name = $sectionName
        VirtualSize = [uint32] $virtualSize
        VirtualAddress = [uint32] $virtualAddress
        RawSize = [uint32] $rawSize
        RawOffset = [uint32] $rawOffset
    })
}

if (-not $hasRelocations) {
    throw 'Release binary has no relocation section for ASLR.'
}
$overlayBytes = $script:binaryBytes.LongLength - $maximumRawEnd
if ($overlayBytes -ne 0) {
    throw "Unsigned development binary contains $overlayBytes overlay byte(s)."
}

function Convert-RvaToFileOffset {
    param([uint32] $Rva, [string] $Description)

    foreach ($section in $sections) {
        $extent = [Math]::Max(
            [uint64] $section.VirtualSize,
            [uint64] $section.RawSize)
        $start = [uint64] $section.VirtualAddress
        $value = [uint64] $Rva
        if ($value -lt $start -or $value -ge ($start + $extent)) {
            continue
        }
        $relativeOffset = $value - $start
        if ($relativeOffset -ge [uint64] $section.RawSize) {
            throw "RVA resolves outside raw section data: $Description"
        }
        $fileOffset = [uint64] $section.RawOffset + $relativeOffset
        Assert-BinaryRange -Offset ([long] $fileOffset) -Count 1 `
            -Description $Description
        return [long] $fileOffset
    }
    throw "RVA does not resolve to a PE section: $Description"
}

$importDirectoryRva = Read-UInt32LE -Offset ($optionalOffset + 120) `
    -Description 'import directory RVA'
$importDirectoryBytes = Read-UInt32LE -Offset ($optionalOffset + 124) `
    -Description 'import directory size'
if ($importDirectoryRva -eq 0 -or $importDirectoryBytes -lt 20) {
    throw 'PE import directory is missing.'
}
$importOffset = Convert-RvaToFileOffset -Rva $importDirectoryRva `
    -Description 'import directory'
$importDlls = [System.Collections.Generic.List[string]]::new()
$foundImportTerminator = $false

for ($descriptorIndex = 0; $descriptorIndex -lt 64; $descriptorIndex++) {
    $descriptorOffset = $importOffset + (20 * $descriptorIndex)
    Assert-BinaryRange -Offset $descriptorOffset -Count 20 `
        -Description "import descriptor $descriptorIndex"
    $descriptorValues = @(
        (Read-UInt32LE -Offset $descriptorOffset -Description 'import lookup'),
        (Read-UInt32LE -Offset ($descriptorOffset + 4) -Description 'import time'),
        (Read-UInt32LE -Offset ($descriptorOffset + 8) -Description 'import chain'),
        (Read-UInt32LE -Offset ($descriptorOffset + 12) -Description 'import name'),
        (Read-UInt32LE -Offset ($descriptorOffset + 16) -Description 'import address')
    )
    if (@($descriptorValues | Where-Object { $_ -ne 0 }).Count -eq 0) {
        $foundImportTerminator = $true
        break
    }
    if ($descriptorValues[3] -eq 0) {
        throw "Import descriptor $descriptorIndex has no DLL name."
    }
    $nameOffset = Convert-RvaToFileOffset `
        -Rva ([uint32] $descriptorValues[3]) `
        -Description "import descriptor $descriptorIndex name"
    $importDlls.Add((Read-AsciiField -Offset $nameOffset -MaximumBytes 128 `
        -Description "import descriptor $descriptorIndex name"))
}
if (-not $foundImportTerminator) {
    throw 'PE import directory has no bounded terminator.'
}

$allowedImports = @(
    'GDI32.dll',
    'KERNEL32.dll',
    'msvcrt.dll',
    'ole32.dll',
    'USER32.dll',
    'WINMM.dll'
)
if ($importDlls.Count -ne $allowedImports.Count) {
    throw "Expected $($allowedImports.Count) imported DLLs; found $($importDlls.Count)."
}
foreach ($importDll in $importDlls) {
    if ($allowedImports -notcontains $importDll) {
        throw "Release binary imports an unreviewed DLL: $importDll"
    }
}
foreach ($allowedImport in $allowedImports) {
    if ($importDlls -notcontains $allowedImport) {
        throw "Release binary is missing a reviewed DLL import: $allowedImport"
    }
}

$binaryText = [System.Text.Encoding]::GetEncoding(28591).GetString(
    $script:binaryBytes)
foreach ($forbiddenFragment in @(
        'C:\Users\',
        'E:\Midisoft',
        'opensesh-build-',
        '\midisoft-fb\')) {
    if ($binaryText.IndexOf(
            $forbiddenFragment,
            [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Release binary leaks a local build path: $forbiddenFragment"
    }
}

$securityDirectoryOffset = Read-UInt32LE -Offset ($optionalOffset + 144) `
    -Description 'certificate table offset'
$securityDirectoryBytes = Read-UInt32LE -Offset ($optionalOffset + 148) `
    -Description 'certificate table size'
$signature = Get-AuthenticodeSignature -LiteralPath $executable
if ($RequireUnsignedDevelopmentBuild) {
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::NotSigned -or
        $securityDirectoryOffset -ne 0 -or $securityDirectoryBytes -ne 0) {
        throw 'Development binary is expected to be completely unsigned.'
    }
    $signatureText = 'unsigned_development'
}
else {
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -and
        $signature.Status -ne [System.Management.Automation.SignatureStatus]::NotSigned) {
        throw "Authenticode status is unacceptable: $($signature.Status)"
    }
    $signatureText = $signature.Status.ToString().ToLowerInvariant()
}

Write-Output 'pe_architecture=x86_64'
Write-Output 'pe_subsystem=windows_gui'
Write-Output 'pe_hardening=high_entropy_va,dynamic_base,nx_compat'
Write-Output 'pe_reproducible_timestamp=0'
Write-Output 'pe_debug_sections=0'
Write-Output ('pe_import_dlls=' + ($allowedImports -join ','))
Write-Output ('pe_overlay_bytes=' + $overlayBytes)
Write-Output ('pe_checksum=0x{0:X8}' -f $checksum)
Write-Output ('authenticode_status=' + $signatureText)
Write-Output 'windows_binary_status=ok'

# end of tests/verify_windows_binary.ps1
