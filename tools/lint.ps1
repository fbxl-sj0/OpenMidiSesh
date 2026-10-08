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
    [string] $CompilerPath = 'C:\FreeBASIC\fbc.exe',
    [string] $CompilerIncludePath = 'C:\FreeBASIC\inc',
    [string] $OmaGuiPath = '',
    [switch] $ListScopes,
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
if ($OmaGuiPath) { $vendorRoot = [IO.Path]::GetFullPath($OmaGuiPath) }
$vendorSources = @()
foreach ($line in Get-Content -LiteralPath (Join-Path $vendorRoot 'SNAPSHOT.sha256')) {
    if ($line -match '^[0-9a-f]{64}  ([^\\]+\.(bas|bi))$') {
        $relativePath = $Matches[1]
        if ($relativePath.StartsWith('/') -or
            $relativePath.Split('/') -contains '..') {
            throw "Unsafe dependency source path: $relativePath"
        }
        $vendorSources += Get-Item -LiteralPath (Join-Path $vendorRoot $relativePath)
    }
}
if ($sources.Count -eq 0) {
    throw 'The strict lint source boundary is empty.'
}

$compiler = [IO.Path]::GetFullPath($CompilerPath)
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "Configured semantic compiler was not found: $compiler"
}
$compilerTarget = 'win64'
if ($Target -eq 'linux') { $compilerTarget = 'linux-x86_64' }
$compilerIncludes = [IO.Path]::GetFullPath($CompilerIncludePath)
if (-not (Test-Path -LiteralPath $compilerIncludes -PathType Container)) {
    throw "Configured compiler include directory was not found: $compilerIncludes"
}
$arguments = @('--profile', 'strict', '--target', $Target,
    '--require-semantic', '--compiler', $compiler,
    '--compiler-target', $compilerTarget, '--compiler-backend', 'gcc',
    '--compiler-multithreaded', '--compiler-include', $vendorRoot,
    '--compiler-include', $compilerIncludes,
    '--honor-suppressions', '--fail-on-warning',
    '--strict-headers', '--strict-tabs', '--format', $Format)
$runtimeRoot = Join-Path $projectRoot 'src\omagui_runtime.bas'
$applicationSources = @($sources | Where-Object { $_.FullName -ne $runtimeRoot })
$navigationPaths = @(
    'src/backend/navigation_input.bas', 'src/backend/navigation_input.bi',
    'src/backend/navigation_viewport.bas', 'src/backend/navigation_viewport.bi',
    'src/widgets/navigation.bas', 'src/widgets/navigation.bi',
    'src/widgets/layout.bas', 'src/widgets/layout.bi'
)
# These files belong to an explicitly enabled library profile. Select real
# compilation contexts before asking the compiler to prove every input.
# The Windows import boundary is outside Linux translation units.
$profileSources = @($vendorSources | Where-Object {
    $relative = $_.FullName.Substring($vendorRoot.Length + 1).Replace('\', '/')
    $Target -ne 'linux' -or $relative -ne 'src/backend/backend_windows.bi'
})
$guiSources = @((Get-Item -LiteralPath $runtimeRoot)) + @($profileSources | Where-Object {
    $relative = $_.FullName.Substring($vendorRoot.Length + 1).Replace('\', '/')
    $navigationPaths -notcontains $relative
})
$navigationSources = @((Get-Item -LiteralPath $runtimeRoot)) + $profileSources
# Literal include paths select candidate compilation contexts, not semantic
# facts. The compiler must still prove that each selected header was included
# with the active target and definitions; an inactive include fails the gate.
$includeGraph = @{}
function Get-SourceIncludes([string] $Path) {
    if ($includeGraph.ContainsKey($Path)) { return $includeGraph[$Path] }
    $included = @()
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -notmatch '^\s*#include\s+(?:once\s+)?"([^"]+)"') { continue }
        $includeName = $Matches[1]
        foreach ($directory in @((Split-Path -Parent $Path),
                (Join-Path $projectRoot 'src'), $vendorRoot)) {
            $candidate = [IO.Path]::GetFullPath((Join-Path $directory $includeName))
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $included += $candidate
                break
            }
        }
    }
    $includeGraph[$Path] = $included
    return $included
}
function Test-SourceIncludes([string] $Root, [string] $Header) {
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $visited = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $pending.Push($Root)
    while ($pending.Count -gt 0) {
        $path = $pending.Pop()
        if (-not $visited.Add($path)) { continue }
        foreach ($included in @(Get-SourceIncludes $path)) {
            if ($included -eq $Header) { return $true }
            $pending.Push($included)
        }
    }
    return $false
}
$scopes = @(@{ Name = 'omagui'; Sources = $guiSources; Context = @('--semantic-root', $runtimeRoot) })
if (@($profileSources | Where-Object {
        $navigationPaths -contains $_.FullName.Substring($vendorRoot.Length + 1).Replace('\', '/')
    }).Count -gt 0) {
    $scopes += @{ Name = 'omagui-navigation'; Sources = $navigationSources;
        Context = @('--semantic-root', $runtimeRoot, '--compiler-define', 'OMAGUI_NAVIGATION_EXTENSIONS') }
}
$roots = @($applicationSources | Where-Object Extension -eq '.bas' | Sort-Object FullName)
$headers = @($applicationSources | Where-Object Extension -eq '.bi')
$rootScopes = @{}
foreach ($root in $roots) {
    $name = $root.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
    $scope = @{ Name = $name; Sources = @($root); Context = @('--semantic-root', $root.FullName) }
    $scopes += $scope
    $rootScopes[$root.FullName] = $scope
}
foreach ($header in $headers) {
    $candidates = @($roots | Sort-Object @{ Expression = { $_.BaseName -ne $header.BaseName } }, FullName)
    $owner = $null
    foreach ($root in $candidates) {
        if (Test-SourceIncludes $root.FullName $header.FullName) { $owner = $root; break }
    }
    if ($null -eq $owner) { throw "No real compilation context includes $($header.FullName)" }
    $rootScopes[$owner.FullName].Sources += $header
}
if ($ListScopes) {
    foreach ($scope in $scopes) {
        [pscustomobject] @{ Name = $scope.Name; Files = $scope.Sources.Count; Root = $scope.Context[1] }
    }
    return
}
$reportFile = ''
if ($OutputPath) {
    $reportFile = [IO.Path]::GetFullPath($OutputPath)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $reportFile)) | Out-Null
}

& $linter --version
if ($LASTEXITCODE -ne 0) {
    throw 'The linter identity query failed.'
}
# omaGUI implementation files share one real translation unit. The linter
# projects compiler facts to each included source and rejects absent inputs.
# Application/test .bas files remain independent compiler roots. Headers are
# selected in an actual including root, with no include-only exemption.
$lintExit = 0
$reports = New-Object 'System.Collections.Generic.List[string]'
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$batchRoot = Join-Path $temporaryRoot ('opensesh-lint-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($batchRoot) | Out-Null
Push-Location $projectRoot
try {
    $batchNumber = 0
    foreach ($scope in $scopes) {
        $batchNumber += 1
        $batchArguments = $arguments + $scope.Context
        $batchReport = Join-Path $batchRoot ($batchNumber.ToString() + '.txt')
        if ($reportFile) { $batchArguments += @('--output-file', $batchReport) }
        $batchArguments += @($scope.Sources | Sort-Object FullName | ForEach-Object { $_.FullName })
        Write-Output ('strict_lint_scope=' + $scope.Name)
        & $linter @batchArguments
        $batchExit = $LASTEXITCODE
        if ($batchExit -lt 0) { $batchExit = 2 }
        if ($batchExit -ne 0) { $lintExit = [Math]::Max($lintExit, $batchExit) }
        if ($reportFile -and (Test-Path -LiteralPath $batchReport)) {
            $reports.Add([IO.File]::ReadAllText($batchReport))
        }
    }
    if ($reportFile) {
        [IO.File]::WriteAllText($reportFile, ($reports -join ''), [Text.UTF8Encoding]::new($false))
    }
}
finally {
    Pop-Location
    $resolvedBatchRoot = [IO.Path]::GetFullPath($batchRoot)
    if (-not $resolvedBatchRoot.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedBatchRoot) -notmatch '^opensesh-lint-[0-9a-f]{32}$') {
        throw 'Unsafe lint report cleanup path.'
    }
    Remove-Item -LiteralPath $resolvedBatchRoot -Recurse -Force
}
Write-Output ('strict_lint_target=' + $Target)
Write-Output ('strict_lint_sources=' + ($sources.Count + $vendorSources.Count))
Write-Output ('strict_lint_exit=' + $lintExit)
exit $lintExit

# end of tools/lint.ps1
