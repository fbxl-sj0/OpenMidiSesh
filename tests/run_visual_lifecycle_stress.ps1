<#
    Project: OpenSesh
    ----------------------------

    File: tests/run_visual_lifecycle_stress.ps1

    Purpose:

        Prove that short-lived editor windows initialize, capture, and exit
        repeatedly without leaking or racing gfxlib display state.

    Responsibilities:

        - launch the current editor sixty times in deterministic snapshot mode
        - alternate minimum and normal supported window dimensions
        - prove malformed numeric test configuration falls back atomically
        - require a valid framebuffer, clean exit, and bounded duration each time
        - report the slowest observed process lifecycle

    This file intentionally does NOT contain:

        - visual baseline approval
        - desktop input automation
        - audio or MIDI hardware qualification
        - unbounded retry behavior
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $EditorPath,
    [Parameter(Mandatory = $true)]
    [string] $FixturePath,
    [Parameter(Mandatory = $true)]
    [string] $BuildDirectory,
    [ValidateRange(1, 1000)]
    [int] $LaunchCount = 60,
    [ValidateRange(1, 120)]
    [int] $ProcessTimeoutSeconds = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

if ($env:OS -ne 'Windows_NT') {
    throw 'The visual lifecycle stress test requires Windows.'
}

$editorExecutable = [System.IO.Path]::GetFullPath($EditorPath)
$midiFixture = [System.IO.Path]::GetFullPath($FixturePath)
$buildRoot = [System.IO.Path]::GetFullPath($BuildDirectory)
if (-not (Test-Path -LiteralPath $editorExecutable -PathType Leaf)) {
    throw "Editor executable was not found: $editorExecutable"
}
if (-not (Test-Path -LiteralPath $midiFixture -PathType Leaf)) {
    throw "MIDI fixture was not found: $midiFixture"
}
if ($midiFixture.Contains('"')) {
    throw 'The MIDI fixture path contains an unsupported quote character.'
}

$stressRoot = Join-Path $buildRoot 'visual-lifecycle-stress'
$workingRoot = Join-Path $stressRoot 'working'
$capturePath = Join-Path $stressRoot 'lifecycle-frame.bmp'
New-Item -ItemType Directory -Path $workingRoot -Force | Out-Null
Add-Type -AssemblyName System.Drawing

$slowestMilliseconds = 0
$minimumWidthLaunches = 0
$normalWidthLaunches = 0
$malformedConfigurationRejections = 0

for ($launchIndex = 1; $launchIndex -le $LaunchCount; $launchIndex++) {
    if (($launchIndex % 3) -eq 0) {
        $requestedWidth = 1280
        $requestedHeight = 720
        $normalWidthLaunches++
    }
    else {
        $requestedWidth = 800
        $requestedHeight = 600
        $minimumWidthLaunches++
    }

    if (Test-Path -LiteralPath $capturePath -PathType Leaf) {
        Remove-Item -LiteralPath $capturePath -Force
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $editorExecutable
    $startInfo.Arguments = '"' + $midiFixture + '"'
    $startInfo.WorkingDirectory = $workingRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false
    $startInfo.EnvironmentVariables['OSE_TEST_SNAPSHOT'] = $capturePath
    $startInfo.EnvironmentVariables['OSE_TEST_SNAPSHOT_FRAME'] = '12'
    if ($launchIndex -eq 3) {
        # Numeric prefixes must not control release evidence. These values
        # previously selected 800 x 600 even though their complete text is not
        # an integer; strict parsing must retain the 1280 x 720 defaults.
        $startInfo.EnvironmentVariables['OSE_TEST_WIDTH'] = '800x'
        $startInfo.EnvironmentVariables['OSE_TEST_HEIGHT'] = '600x'
        $malformedConfigurationRejections++
    }
    else {
        $startInfo.EnvironmentVariables['OSE_TEST_WIDTH'] = [string] $requestedWidth
        $startInfo.EnvironmentVariables['OSE_TEST_HEIGHT'] = [string] $requestedHeight
    }
    $startInfo.EnvironmentVariables['OSE_TEST_OPEN_ADD_PALETTE'] = '0'
    $startInfo.EnvironmentVariables['OSE_TEST_MODAL'] = ''
    $startInfo.EnvironmentVariables['OSE_TEST_VISUAL_DEVICES'] = '1'
    # Sound lifecycle is stressed separately against the default backend.
    # Keeping this graphics test on the null driver makes a timeout identify
    # the display/window teardown path that this script owns.
    $startInfo.EnvironmentVariables['SFXLIB_DRIVER'] = 'null'
    foreach ($unusedHook in @(
            'OSE_TEST_CONTROL_REPORT',
            'OSE_TEST_MIXER_PAGE_ANCHOR',
            'OSE_TEST_MOUSE_X',
            'OSE_TEST_MOUSE_Y',
            'OSE_TEST_PREFERENCES_FILE')) {
        $startInfo.EnvironmentVariables.Remove($unusedHook)
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) {
            throw "Launch $launchIndex could not start the editor."
        }
        if (-not $process.WaitForExit($ProcessTimeoutSeconds * 1000)) {
            $captureWasWritten = Test-Path -LiteralPath $capturePath -PathType Leaf
            $process.Kill()
            $process.WaitForExit()
            throw ('Launch {0} exceeded {1} seconds; capture_written={2}.' -f
                $launchIndex, $ProcessTimeoutSeconds, $captureWasWritten)
        }
        if ($process.ExitCode -ne 0) {
            throw "Launch $launchIndex exited with status $($process.ExitCode)."
        }
    }
    finally {
        $stopwatch.Stop()
        $process.Dispose()
    }

    if ($stopwatch.ElapsedMilliseconds -gt $slowestMilliseconds) {
        $slowestMilliseconds = $stopwatch.ElapsedMilliseconds
    }
    if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf) -or
        (Get-Item -LiteralPath $capturePath).Length -le 54) {
        throw "Launch $launchIndex did not write a complete BMP framebuffer."
    }

    $captureImage = [System.Drawing.Image]::FromFile($capturePath)
    try {
        if ($captureImage.Width -ne $requestedWidth -or
            $captureImage.Height -ne $requestedHeight) {
            throw ('Launch {0} requested {1}x{2}, but captured {3}x{4}.' -f
                $launchIndex, $requestedWidth, $requestedHeight,
                $captureImage.Width, $captureImage.Height)
        }
    }
    finally {
        $captureImage.Dispose()
    }

    if (($launchIndex % 10) -eq 0) {
        Write-Output ('LIFECYCLE completed=' + $launchIndex)
    }
}

Write-Output 'visual_lifecycle=ok'
Write-Output ('process_launches=' + $LaunchCount)
Write-Output ('minimum_window_launches=' + $minimumWidthLaunches)
Write-Output ('normal_window_launches=' + $normalWidthLaunches)
Write-Output ('malformed_test_configuration_rejections=' + `
    $malformedConfigurationRejections)
Write-Output ('slowest_exit_ms=' + $slowestMilliseconds)

# end of tests/run_visual_lifecycle_stress.ps1
