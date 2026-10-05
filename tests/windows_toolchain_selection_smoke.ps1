<#
    Project: OpenSesh
    File: tests/windows_toolchain_selection_smoke.ps1
    Purpose: Verify that the release lock hashes the selected Windows compiler.
    Responsibilities:
        - build an isolated fake toolchain with all fourteen locked paths
        - distinguish selected compiler bytes from a neighboring fbc.exe
        - reject changed compiler bytes even when the version banner matches
        - reject omitted compiler entries and Windows path aliases
    This file intentionally does NOT contain:
        - compilation or changes to installed toolchains
        - updates to the reviewed release hashes or compiler banner
#>

[CmdletBinding()]
param(
    [string] $VerifierPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ([string]::IsNullOrWhiteSpace($VerifierPath)) {
    $VerifierPath = Join-Path $PSScriptRoot 'verify_windows_toolchain.ps1'
}
$verifier = [System.IO.Path]::GetFullPath($VerifierPath)
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$reviewedLock = Get-Content -LiteralPath (Join-Path $projectRoot 'windows_toolchain_lock.json') -Raw |
    ConvertFrom-Json
$lockedPaths = @($reviewedLock.files | ForEach-Object { [string] $_.path })
if ($lockedPaths.Count -ne 14 -or $lockedPaths -cnotcontains 'fbc.exe') {
    throw 'The fixture requires the fourteen reviewed paths including fbc.exe.'
}

function Assert-Test {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

$temporaryParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testName = 'opensesh-windows-toolchain-' + [Guid]::NewGuid().ToString('N')
$testRoot = Join-Path $temporaryParent $testName
$failures = @()
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $compilerRoot = Join-Path $testRoot 'fake toolchain'
    New-Item -ItemType Directory -Path $compilerRoot | Out-Null
    $selectedCompiler = Join-Path $compilerRoot 'fbc64.ps1'
    $neighborCompiler = Join-Path $compilerRoot 'fbc.exe'
    $banner = 'OpenSesh compiler selection fixture'
    $matchingCompiler = @'
# fake compiler identity=A
if ($args.Count -ne 1 -or $args[0] -cne '-version') {
    throw 'The fake compiler only accepts -version.'
}
Write-Output 'OpenSesh compiler selection fixture'
$global:LASTEXITCODE = 0
'@
    # Equal-length comment changes leave exactly the same executable behavior.
    $changedCompiler = $matchingCompiler.Replace('identity=A', 'identity=B')
    Assert-Test ($matchingCompiler -cne $changedCompiler -and
        $matchingCompiler.Length -eq $changedCompiler.Length) 'Invalid changed-compiler fixture.'
    [System.IO.File]::WriteAllText($selectedCompiler, $matchingCompiler)
    [System.IO.File]::WriteAllText($neighborCompiler, $matchingCompiler)

    $fixtureFiles = @(foreach ($relativePath in $lockedPaths) {
        $fixturePath = Join-Path $compilerRoot $relativePath.Replace('/', '\')
        if ($relativePath -cne 'fbc.exe') {
            New-Item -ItemType Directory -Path (Split-Path -Parent $fixturePath) -Force | Out-Null
            [System.IO.File]::WriteAllText($fixturePath, 'fixture:' + $relativePath)
        }
        @{
            path = $relativePath
            length = (Get-Item -LiteralPath $fixturePath).Length
            sha256 = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    $lockPath = Join-Path $testRoot 'fake-toolchain-lock.json'

    # Preserve fourteen valid byte records while omitting the compiler itself.
    $extraRelativePath = 'extra-' + [Guid]::NewGuid().ToString('N') + '.dat'
    $extraPath = Join-Path $compilerRoot $extraRelativePath
    [System.IO.File]::WriteAllText($extraPath, 'unrelated fixture file')
    $extraEntry = @{
        path = $extraRelativePath
        length = (Get-Item -LiteralPath $extraPath).Length
        sha256 = (Get-FileHash -LiteralPath $extraPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $missingCompilerFiles = @($fixtureFiles | ForEach-Object {
        if ($_.path -ceq 'fbc.exe') { $extraEntry } else { $_ }
    })

    $aliasSources = @($fixtureFiles | Where-Object { $_.path -ceq 'inc/fbgfx.bi' })
    Assert-Test ($aliasSources.Count -eq 1) 'The path alias fixture needs inc/fbgfx.bi.'
    $caseAlias = $aliasSources[0].Clone()
    $caseAlias.path = 'inc/FBGFX.bi'
    $dotAlias = $aliasSources[0].Clone()
    $dotAlias.path = 'inc/./fbgfx.bi'
    $replacedPath = $fixtureFiles[-1].path
    Assert-Test ($replacedPath -cne 'fbc.exe' -and $replacedPath -cne 'inc/fbgfx.bi') `
        'The path alias fixture must retain both the compiler and original path.'
    $caseAliasFiles = @($fixtureFiles | ForEach-Object {
        if ($_.path -ceq $replacedPath) { $caseAlias } else { $_ }
    })
    $dotAliasFiles = @($fixtureFiles | ForEach-Object {
        if ($_.path -ceq $replacedPath) { $dotAlias } else { $_ }
    })

    $cases = @(
        @{ Name = 'matching-control'; Selected = $matchingCompiler; Neighbor = $matchingCompiler; Files = $fixtureFiles; Accept = $true },
        @{ Name = 'matching-selected-changed-neighbor'; Selected = $matchingCompiler; Neighbor = $changedCompiler; Files = $fixtureFiles; Accept = $true },
        @{ Name = 'changed-selected-matching-neighbor'; Selected = $changedCompiler; Neighbor = $matchingCompiler; Files = $fixtureFiles; Accept = $false; Error = 'Locked toolchain hash differs: fbc.exe' },
        @{ Name = 'missing-compiler-changed-selected'; Selected = $changedCompiler; Neighbor = $matchingCompiler; Files = $missingCompilerFiles; Accept = $false; Error = 'The Windows toolchain lock is missing the fbc.exe compiler entry.' },
        @{ Name = 'case-alias-duplicate'; Selected = $matchingCompiler; Neighbor = $matchingCompiler; Files = $caseAliasFiles; Accept = $false; Error = 'Duplicate toolchain lock path: inc/FBGFX.bi' },
        @{ Name = 'dot-alias-duplicate'; Selected = $matchingCompiler; Neighbor = $matchingCompiler; Files = $dotAliasFiles; Accept = $false; Error = 'Unsafe or malformed toolchain lock entry: inc/./fbgfx.bi' }
    )
    foreach ($case in $cases) {
        Assert-Test ($case.Files.Count -eq 14) ('Fixture count changed for ' + $case.Name)
        $fixtureLock = @{
            schema_version = 1
            platform = 'windows-x86_64'
            compiler_banner = $banner
            files = $case.Files
        }
        [System.IO.File]::WriteAllText($lockPath, ($fixtureLock | ConvertTo-Json -Depth 4))
        [System.IO.File]::WriteAllText($selectedCompiler, $case.Selected)
        [System.IO.File]::WriteAllText($neighborCompiler, $case.Neighbor)
        $selectedBanner = @(& $selectedCompiler -version)
        Assert-Test ($LASTEXITCODE -eq 0 -and $selectedBanner.Count -eq 1 -and
            $selectedBanner[0] -ceq $banner) ('Fixture banner changed for ' + $case.Name)

        $caught = $null
        $verificationOutput = @()
        try {
            $verificationOutput = @(& $verifier -FreeBasicPath $selectedCompiler -LockPath $lockPath)
        }
        catch { $caught = $_ }
        if ($case.Accept) {
            $passed = $null -eq $caught -and
                $verificationOutput -ccontains 'windows_toolchain_files=14' -and
                $verificationOutput -ccontains 'windows_toolchain_status=ok'
        }
        else {
            $passed = $null -ne $caught -and
                $caught.Exception.Message -ceq $case.Error
        }
        $actual = 'accepted'
        if ($null -ne $caught) { $actual = 'rejected' }
        $status = 'ok'
        if (-not $passed) {
            $status = 'failed'
            $detail = $actual
            if ($null -ne $caught) { $detail += ': ' + $caught.Exception.Message }
            $failures += $case.Name + ' (' + $detail + ')'
        }
        Write-Output ('windows_toolchain_selection_case=' + $case.Name +
            ' actual=' + $actual + ' status=' + $status)
    }
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $temporaryBoundary = $temporaryParent.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedTestRoot.StartsWith($temporaryBoundary,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($resolvedTestRoot) -ne $testName) {
        throw "Refusing to remove an unexpected toolchain test path: $resolvedTestRoot"
    }
    if (Test-Path -LiteralPath $resolvedTestRoot) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    throw ('Windows toolchain selection failed: ' + ($failures -join '; '))
}
Write-Output ('windows_toolchain_selection=ok cases=' + $cases.Count + ' locked_files=14')

# end of tests/windows_toolchain_selection_smoke.ps1
