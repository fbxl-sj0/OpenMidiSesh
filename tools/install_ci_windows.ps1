<#
    Project: OpenSesh
    File: tools/install_ci_windows.ps1
    Purpose: install the pinned public compiler in an ephemeral Windows runner.
    Responsibilities: verify the archive, discover its root, lock linked inputs.
    This file does not replace C:\FreeBASIC or alter a developer installation.
#>

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) {
    throw 'This provisioner is restricted to ephemeral GitHub Actions jobs.'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$taskRoot = Join-Path $env:RUNNER_TEMP 'opensesh-ci-toolchain'
if (Test-Path -LiteralPath $taskRoot) { throw 'Compiler staging directory already exists.' }
New-Item -ItemType Directory -Path $taskRoot | Out-Null
& python (Join-Path $PSScriptRoot 'fetch_ci_toolchain.py') windows $taskRoot
if ($LASTEXITCODE -ne 0) { throw 'Pinned Windows compiler download failed.' }
$archive = @(Get-ChildItem -LiteralPath $taskRoot -Filter '*.zip' -File)
if ($archive.Count -ne 1) { throw 'Expected one Windows compiler archive.' }
& 7z x '-y' ('-o' + (Join-Path $taskRoot 'compiler')) $archive[0].FullName | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Windows compiler extraction failed.' }
# Keep one extracted toolchain. The large Winlibs download is not a cache.
Remove-Item -LiteralPath $archive[0].FullName
$candidates = @(Get-ChildItem -LiteralPath (Join-Path $taskRoot 'compiler') `
    -Recurse -File -Filter 'fbc.exe' | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.DirectoryName 'lib\win64\libfbmt.a')
    })
if ($candidates.Count -ne 1) { throw 'Expected one complete native Win64 compiler.' }
$compiler = $candidates[0].FullName
$compilerRoot = $candidates[0].DirectoryName
$banner = @(& $compiler -version)[0]
if ($LASTEXITCODE -ne 0 -or $banner -notmatch 'Version 1\.20\.4') {
    throw 'Unexpected public compiler version.'
}
$lock = Get-Content -LiteralPath (Join-Path $projectRoot 'windows_toolchain_lock.json') -Raw |
    ConvertFrom-Json
$lock.compiler_banner = $banner
foreach ($entry in $lock.files) {
    $path = Join-Path $compilerRoot $entry.path
    $entry.length = (Get-Item -LiteralPath $path).Length
    $entry.sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
$lockPath = Join-Path $taskRoot 'windows-toolchain-lock.json'
$lock | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $lockPath -Encoding utf8
"FREEBASIC_PATH=$compiler" | Out-File -LiteralPath $env:GITHUB_ENV -Append -Encoding utf8
"OSE_CI_TOOLCHAIN_LOCK=$lockPath" | Out-File -LiteralPath $env:GITHUB_ENV -Append -Encoding utf8
Write-Output $banner

# end of tools/install_ci_windows.ps1
