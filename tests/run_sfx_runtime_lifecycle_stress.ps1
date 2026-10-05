<#
    Project: OpenSesh
    ----------------------------

    File: tests/run_sfx_runtime_lifecycle_stress.ps1

    Purpose:

        Repeatedly initialize and release the default Windows sfxlib output
        backend through the maintained master-effect smoke executable.

    Responsibilities:

        - remove test-only driver overrides before each child process starts
        - require every process to validate its effect state and exit in time
        - make sound-worker shutdown races reproducible at the release gate

    This file intentionally does NOT contain:

        - waveform or MIDI correctness checks
        - physical speaker-output approval
        - retries after a timeout or failed process
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ExecutablePath,
    [ValidateRange(1, 1000)]
    [int] $LaunchCount = 25,
    [ValidateRange(1, 120)]
    [int] $ProcessTimeoutSeconds = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

if ($env:OS -ne 'Windows_NT') {
    throw 'The default-audio lifecycle stress test requires Windows.'
}

$testExecutable = [System.IO.Path]::GetFullPath($ExecutablePath)
if (-not (Test-Path -LiteralPath $testExecutable -PathType Leaf)) {
    throw "The master-effect smoke executable was not found: $testExecutable"
}

$slowestMilliseconds = 0

for ($launchIndex = 1; $launchIndex -le $LaunchCount; $launchIndex++) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $testExecutable
    $startInfo.WorkingDirectory = Split-Path -Parent $testExecutable
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    # This stress test owns default-driver coverage. Removing inherited test
    # overrides allows sfxlib to select the installed Windows backend and use
    # its documented null fallback only when no physical endpoint is usable.
    $startInfo.EnvironmentVariables.Remove('SFXLIB_DRIVER')
    $startInfo.EnvironmentVariables.Remove('SFXLIB_DEBUG')

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $standardOutput = ''
    $standardError = ''

    try {
        if (-not $process.Start()) {
            throw "Launch $launchIndex could not start the effect smoke test."
        }
        if (-not $process.WaitForExit($ProcessTimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            throw ('Launch {0} exceeded {1} seconds.' -f
                $launchIndex, $ProcessTimeoutSeconds)
        }

        $standardOutput = $process.StandardOutput.ReadToEnd()
        $standardError = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) {
            throw ('Launch {0} exited with status {1}. stderr={2}' -f
                $launchIndex, $process.ExitCode, $standardError.Trim())
        }
        if ($standardOutput -notmatch '(?m)^master_effect=ok\s*$' -or
            $standardOutput -notmatch
                '(?m)^wet=0\.20 feedback=0\.45 delay=0\.14\s*$') {
            throw "Launch $launchIndex did not report the complete effect contract."
        }
    }
    finally {
        $stopwatch.Stop()
        $process.Dispose()
    }

    if ($stopwatch.ElapsedMilliseconds -gt $slowestMilliseconds) {
        $slowestMilliseconds = $stopwatch.ElapsedMilliseconds
    }
    if (($launchIndex % 5) -eq 0) {
        Write-Output ('SFX_LIFECYCLE completed=' + $launchIndex)
    }
}

Write-Output 'sfx_runtime_lifecycle=ok'
Write-Output ('sfx_runtime_process_launches=' + $LaunchCount)
Write-Output ('sfx_runtime_slowest_exit_ms=' + $slowestMilliseconds)
Write-Output 'sfx_runtime_driver_selection=default'

# end of tests/run_sfx_runtime_lifecycle_stress.ps1
