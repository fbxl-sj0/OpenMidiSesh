<#
    Project: OpenSesh
    ----------------------------

    File: tests/run_ui_smoothness.ps1

    Purpose:

        Run the native editor's measurable UI smoothness acceptance matrix.

    Responsibilities:

        - exercise idle rendering in Light, Dark, and Black themes
        - exercise real mouse and touch-profile interaction workloads
        - exercise score scrolling, master-fader dragging, playback, and VU meters
        - present every measured frame through the visible desktop compositor
        - retain a full-HD idle gate in addition to the shipping-size interaction gates
        - reject missing, malformed, incomplete, or threshold-failing reports
        - allow focused scenario selection while defaulting to the full matrix

    This file intentionally does NOT contain:

        - editor compilation
        - visual-baseline approval
        - synthetic timing values or threshold overrides
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $EditorPath,
    [string] $BuildDirectory = '',
    [string[]] $CaseNames = @(),
    [ValidateRange(240, 1800)]
    [int] $FrameCount = 480,
    [ValidateRange(10, 300)]
    [int] $ProcessTimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'
$editorFile = [System.IO.Path]::GetFullPath($EditorPath)
if (-not (Test-Path -LiteralPath $editorFile -PathType Leaf)) {
    throw "Editor executable was not found: $editorFile"
}

$ownsBuildDirectory = [string]::IsNullOrWhiteSpace($BuildDirectory)
if ($ownsBuildDirectory) {
    $buildRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
        ('opensesh-smoothness-' + [System.Guid]::NewGuid().ToString('N'))
}
else {
    $buildRoot = [System.IO.Path]::GetFullPath($BuildDirectory)
}

$environmentNames = @(
    'OSE_TEST_SMOOTHNESS_REPORT',
    'OSE_TEST_SMOOTHNESS_MODE',
    'OSE_TEST_SMOOTHNESS_FRAMES',
    'OSE_TEST_WIDTH',
    'OSE_TEST_HEIGHT',
    'OSE_TEST_THEME',
    'OSE_TEST_HIDE_WINDOW',
    'OSE_INTERACTION_MODE'
)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable(
        $name, [EnvironmentVariableTarget]::Process)
}

$cases = @(
    [pscustomobject]@{ Name = 'idle-light-1280x720'; Mode = 'idle'; Theme = 'light'; Interaction = 'fine'; ExpectedInteraction = 'desktop'; Width = 1280; Height = 720 },
    [pscustomobject]@{ Name = 'idle-dark-1280x720'; Mode = 'idle'; Theme = 'dark'; Interaction = 'fine'; ExpectedInteraction = 'desktop'; Width = 1280; Height = 720 },
    [pscustomobject]@{ Name = 'idle-black-1280x720'; Mode = 'idle'; Theme = 'black'; Interaction = 'fine'; ExpectedInteraction = 'desktop'; Width = 1280; Height = 720 },
    [pscustomobject]@{ Name = 'interaction-dark-1280x720'; Mode = 'interaction'; Theme = 'dark'; Interaction = 'fine'; ExpectedInteraction = 'desktop'; Width = 1280; Height = 720 },
    [pscustomobject]@{ Name = 'interaction-touch-1280x720'; Mode = 'interaction'; Theme = 'dark'; Interaction = 'touch'; ExpectedInteraction = 'touch'; Width = 1280; Height = 720 },
    [pscustomobject]@{ Name = 'playback-dark-1280x720'; Mode = 'playback'; Theme = 'dark'; Interaction = 'fine'; ExpectedInteraction = 'desktop'; Width = 1280; Height = 720 },
    [pscustomobject]@{ Name = 'playback-touch-1280x720'; Mode = 'playback'; Theme = 'dark'; Interaction = 'touch'; ExpectedInteraction = 'touch'; Width = 1280; Height = 720 },
    [pscustomobject]@{ Name = 'idle-dark-1920x1080'; Mode = 'idle'; Theme = 'dark'; Interaction = 'fine'; ExpectedInteraction = 'desktop'; Width = 1920; Height = 1080 }
)

$contentionProcessNames = @(
    'cc1', 'cc1plus', 'clang', 'clang++', 'fbc', 'fb_linter', 'gcc', 'g++'
)

# A focused run uses the same sample and acceptance requirements as the full
# release matrix. Validate names before setting any child-process environment.
if ($CaseNames.Count -gt 0) {
    $requestedCases = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($caseName in $CaseNames) {
        if ($cases.Name -notcontains $caseName -or
            -not $requestedCases.Add($caseName)) {
            throw "Unknown or repeated smoothness case: $caseName"
        }
    }
    $cases = @($cases | Where-Object { $requestedCases.Contains($_.Name) })
}

function Test-CompilerContention {
    $matchingProcesses = @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            # Private validator/compiler candidates use suffixes while sharing
            # the same workload. They can disturb presentation just as much as
            # the installed executable. Exited handles are not active work.
            $isCompiler = (
                $contentionProcessNames -contains $_.ProcessName -or
                $_.ProcessName -like 'fb_linter.*' -or
                $_.ProcessName -like 'fbc.*' -or
                $_.ProcessName -eq 'fbc64')
            if (-not $isCompiler) { return $false }
            try { return -not $_.HasExited }
            catch {
                # An inaccessible compiler cannot certify a quiet desktop.
                return $true
            }
        })
    return $matchingProcesses.Count -gt 0
}

function Wait-ForCompilerQuietWindow {
    param(
        [ValidateRange(1, 30)]
        [int] $QuietSeconds = 5,
        [ValidateRange(10, 600)]
        [int] $TimeoutSeconds = 300
    )

    <#
        Frame presentation measures host scheduling as well as application
        work. A concurrent compiler can consume a core for the entire sample
        and turn a healthy 16 ms presentation into a false 30 ms failure.
        Require a sustained quiet window, then continue monitoring throughout
        the case so a compiler that starts later cannot contaminate evidence.
    #>
    $pollMilliseconds = 250
    $quietMilliseconds = 0
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if (Test-CompilerContention) {
            $quietMilliseconds = 0
        }
        else {
            $quietMilliseconds += $pollMilliseconds
            if ($quietMilliseconds -ge ($QuietSeconds * 1000)) {
                return
            }
        }
        Start-Sleep -Milliseconds $pollMilliseconds
    }

    throw "Compiler contention did not clear within $TimeoutSeconds seconds."
}

try {
    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    foreach ($case in $cases) {
        $reportPath = Join-Path $buildRoot ($case.Name + '.txt')
        $env:OSE_TEST_SMOOTHNESS_REPORT = $reportPath
        $env:OSE_TEST_SMOOTHNESS_MODE = $case.Mode
        $env:OSE_TEST_SMOOTHNESS_FRAMES = [string] $FrameCount
        $env:OSE_TEST_WIDTH = [string] $case.Width
        $env:OSE_TEST_HEIGHT = [string] $case.Height
        $env:OSE_TEST_THEME = $case.Theme
        $env:OSE_INTERACTION_MODE = $case.Interaction
        <#
            A hidden or off-screen native window can be deprioritized by DWM,
            creating presentation stalls that a user cannot encounter while
            operating the visible editor. The acceptance test must exercise
            the same compositor path as the interface being certified.
        #>
        $env:OSE_TEST_HIDE_WINDOW = '0'

        # One good presentation trace can occur by chance on a busy desktop.
        # Require two passing uncontended measurements while allowing one
        # clean threshold miss. Compiler activity is retried separately and
        # never counts as evidence for or against the editor.
        $acceptedReport = $false
        $acceptedReportCount = 0
        $measurementCount = 0
        $contentionCount = 0
        $lastThresholdDiagnostics = ''
        for ($attempt = 1; $attempt -le 6; $attempt++) {
            Wait-ForCompilerQuietWindow
            Remove-Item -LiteralPath $reportPath -ErrorAction SilentlyContinue
            Write-Output ('RUN   ui_smoothness_' + $case.Name)
            $process = Start-Process -FilePath $editorFile `
                -WorkingDirectory (Split-Path -Parent $editorFile) `
                -PassThru
            $contentionObserved = $false
            $deadlineUtc = [DateTime]::UtcNow.AddSeconds($ProcessTimeoutSeconds)
            while (-not $process.HasExited) {
                if (Test-CompilerContention) {
                    $contentionObserved = $true
                }
                if ([DateTime]::UtcNow -ge $deadlineUtc) {
                    Stop-Process -Id $process.Id -Force
                    throw "$($case.Name) exceeded $ProcessTimeoutSeconds seconds."
                }
                Start-Sleep -Milliseconds 100
            }
            $process.WaitForExit()
            if ($contentionObserved) {
                $contentionCount++
                Write-Output ("RETRY ui_smoothness_$($case.Name) " +
                    "external_compiler_contention=$contentionCount")
                if ($contentionCount -ge 3) {
                    throw "$($case.Name) encountered compiler contention on all attempts."
                }
                continue
            }
        if ($process.ExitCode -ne 0) {
            throw "$($case.Name) exited with status $($process.ExitCode)."
        }
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
            throw "$($case.Name) did not create a smoothness report."
        }

        $report = @{}
        foreach ($line in Get-Content -LiteralPath $reportPath) {
            $separator = $line.IndexOf('=')
            if ($separator -le 0) {
                throw "$($case.Name) contains a malformed report line: $line"
            }
            $key = $line.Substring(0, $separator)
            if ($report.ContainsKey($key)) {
                throw "$($case.Name) repeats report key: $key"
            }
            $report[$key] = $line.Substring($separator + 1)
        }
        $measurementCount++

        # A failed threshold must identify its measured evidence. Without this
        # detail, a compositor hitch and an invalid workload look identical in
        # the aggregate Windows suite and cannot be investigated reliably.
        if ($report.ContainsKey('status') -and $report.status -eq 'fail') {
            $diagnosticKeys = @(
                'average_fps', 'interval_p95_ms', 'interval_p99_ms',
                'interval_max_ms', 'work_p95_ms', 'input_p95_ms',
                'application_render_p95_ms', 'presentation_p95_ms',
                'hitches_over_33_34_ms', 'hitches_over_50_ms',
                'rejected_samples', 'workload_valid',
                'score_scroll_updates', 'mixer_drag_updates',
                'playback_advance_frames', 'meter_change_frames'
            )
            $diagnostics = @($diagnosticKeys | ForEach-Object {
                if ($report.ContainsKey($_)) {
                    $_ + '=' + $report[$_]
                }
                else {
                    $_ + '=<missing>'
                }
            }) -join ' '
            $lastThresholdDiagnostics = $diagnostics
            Write-Output ("RETRY ui_smoothness_$($case.Name) " +
                "threshold_miss=$measurementCount $diagnostics")
            if ($measurementCount -ge 3) {
                throw ("$($case.Name) passed $acceptedReportCount of 3 " +
                    "uncontended measurements; last miss: $diagnostics")
            }
            continue
        }

        $expected = @{
            format = 'OpenSeshUiSmoothness'
            version = '1'
            status = 'pass'
            scenario = $case.Mode
            width = [string] $case.Width
            height = [string] $case.Height
            theme = $case.Theme
            interaction = $case.ExpectedInteraction
            tracks = '16'
            notes = '2048'
            samples = [string] $FrameCount
            rejected_samples = '0'
            workload_valid = 'yes'
            minimum_fps = '59'
            maximum_interval_p95_ms = '20'
            maximum_interval_p99_ms = '25'
            maximum_interval_ms = '50'
            maximum_work_p95_ms = '16.67'
            maximum_input_p95_ms = '20'
            maximum_hitches = '2'
        }
        foreach ($entry in $expected.GetEnumerator()) {
            if (-not $report.ContainsKey($entry.Key) -or
                $report[$entry.Key] -cne $entry.Value) {
                $actualValue = if ($report.ContainsKey($entry.Key)) {
                    $report[$entry.Key]
                }
                else {
                    '<missing>'
                }
                throw ("$($case.Name) expected $($entry.Key)=$($entry.Value), " +
                    "received $actualValue.")
            }
        }

        foreach ($requiredMetric in @(
            'average_fps', 'interval_p95_ms', 'interval_p99_ms',
            'interval_max_ms', 'work_p95_ms', 'input_p95_ms',
            'application_render_p95_ms', 'presentation_p95_ms',
            'hitches_over_33_34_ms', 'hitches_over_50_ms'
        )) {
            if (-not $report.ContainsKey($requiredMetric)) {
                throw "$($case.Name) is missing metric: $requiredMetric"
            }
        }

        Write-Output ("PASS  ui_smoothness_$($case.Name) " +
            "measurement=$measurementCount " +
            "fps=$($report.average_fps) p95_ms=$($report.interval_p95_ms) " +
            "p99_ms=$($report.interval_p99_ms) max_ms=$($report.interval_max_ms) " +
            "work_p95_ms=$($report.work_p95_ms) " +
            "input_p95_ms=$($report.input_p95_ms)")
            $acceptedReportCount++
            if ($acceptedReportCount -ge 2) {
                $acceptedReport = $true
                break
            }
        }
        if (-not $acceptedReport) {
            throw ("$($case.Name) produced only $acceptedReportCount passing " +
                "uncontended measurement(s). Last miss: $lastThresholdDiagnostics")
        }
    }

    Write-Output ('ui_smoothness_cases=' + $cases.Count)
    Write-Output 'ui_smoothness_status=pass'
}
finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable(
            $name, $previousEnvironment[$name],
            [EnvironmentVariableTarget]::Process)
    }

    if ($ownsBuildDirectory -and
        (Test-Path -LiteralPath $buildRoot -PathType Container)) {
        $temporaryRoot = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        $resolvedBuildRoot = [System.IO.Path]::GetFullPath($buildRoot)
        $buildLeaf = Split-Path -Leaf $resolvedBuildRoot
        if (-not $resolvedBuildRoot.StartsWith(
                $temporaryRoot,
                [System.StringComparison]::OrdinalIgnoreCase) -or
            -not $buildLeaf.StartsWith('opensesh-smoothness-')) {
            throw "Refusing to remove unexpected smoothness path: $resolvedBuildRoot"
        }
        Remove-Item -LiteralPath $resolvedBuildRoot -Recurse -Force
    }
}

# end of tests/run_ui_smoothness.ps1
