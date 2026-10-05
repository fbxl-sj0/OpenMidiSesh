<#
    Project: OpenSesh
    File: tools/ci_windows.ps1
    Purpose: gate portable Windows packages on native build and execution.
    Responsibilities: verify source/toolchain, run core tests and editor launches.
    This file does not replace interactive frame-pacing or baseline qualification.
#>

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:FREEBASIC_PATH -or
    -not $env:OSE_CI_TOOLCHAIN_LOCK) { throw 'Provisioned GitHub runner required.' }
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
New-Item -ItemType Directory -Path 'build/ci/logs' -Force | Out-Null
& python tools/check_repository.py --tracked
if ($LASTEXITCODE -ne 0) { throw 'Source integrity failed.' }
& python tests/source_archive_safety.py
if ($LASTEXITCODE -ne 0) { throw 'Archive safety fixtures failed.' }
& python tests/ci_package_safety.py
if ($LASTEXITCODE -ne 0) { throw 'CI package safety fixtures failed.' }
# Headless audio is explicit. Hosted Windows does not supply speakers or MIDI.
$env:SFXLIB_DRIVER = 'null'
& powershell -NoProfile -File tests/run_tests.ps1 -FreeBasicPath $env:FREEBASIC_PATH `
    -ToolchainLockPath $env:OSE_CI_TOOLCHAIN_LOCK -CoreOnly `
    -BuildDirectory (Join-Path $projectRoot 'build/ci/tests') 2>&1 |
    Tee-Object -FilePath 'build/ci/logs/tests.log'
if ($LASTEXITCODE -ne 0) { throw 'Native Windows tests failed.' }
& powershell -NoProfile -File build_editor.ps1 -FreeBasicPath $env:FREEBASIC_PATH `
    -OutputPath (Join-Path $projectRoot 'build/ci/opensesh.exe') 2>&1 |
    Tee-Object -FilePath 'build/ci/logs/build.log'
if ($LASTEXITCODE -ne 0) { throw 'Native Windows build failed.' }
& python tools/ci_editor_smoke.py build/ci/opensesh.exe build/ci/editor
if ($LASTEXITCODE -ne 0) { throw 'Native Windows editor launch checks failed.' }
& python tools/package_platform.py build/ci/opensesh.exe build/ci/logs/tests.log build/packages
if ($LASTEXITCODE -ne 0) { throw 'Extracted Windows package checks failed.' }
Write-Output 'native_package_gate=pass'

# end of tools/ci_windows.ps1
