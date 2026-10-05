<#
    Project: OpenSesh
    ---------------------------

    File: tests/run_visual_regression.ps1

    Purpose:

        Capture and compare deterministic editor framebuffers on Windows.

    Responsibilities:

        - build a current editor and MIDI fixture when callers do not supply them
        - capture all themes plus the note palette and every generated modal route
        - compare decoded pixels instead of container bytes or filename extensions
        - update reviewed PNG baselines only when explicitly requested
        - keep file-dialog contents isolated from the source tree

    This file intentionally does NOT contain:

        - desktop screenshots affected by occlusion or display scaling
        - OCR or subjective visual-quality scoring
        - Linux framebuffer expectations
        - automatic approval of changed baselines
#>

[CmdletBinding()]
param(
    [string] $FreeBasicPath = 'C:\FreeBASIC\fbc.exe',
    [string] $OmaGuiPath = '',
    [string] $BuildDirectory = '',
    [string] $EditorPath = '',
    [string] $FixturePath = '',
    [string] $BaselineDirectory = '',
    [string[]] $CaseNames = @(),
    [switch] $UpdateBaselines,
    [ValidateRange(1, 120)]
    [int] $CaptureTimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if ($env:OS -ne 'Windows_NT') {
    throw 'Framebuffer baselines are currently defined for Windows only.'
}
if ([string]::IsNullOrWhiteSpace($OmaGuiPath)) {
    $OmaGuiPath = Join-Path $projectRoot 'vendor\omaGui'
}
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path ([System.IO.Path]::GetTempPath()) `
        ('opensesh-visual-' + $PID)
}
if ([string]::IsNullOrWhiteSpace($BaselineDirectory)) {
    $BaselineDirectory = Join-Path $PSScriptRoot 'visual_baselines'
}

$compilerPath = [System.IO.Path]::GetFullPath($FreeBasicPath)
$omaGuiRoot = [System.IO.Path]::GetFullPath($OmaGuiPath)
$buildRoot = [System.IO.Path]::GetFullPath($BuildDirectory)
$baselineRoot = [System.IO.Path]::GetFullPath($BaselineDirectory)

if (-not (Test-Path -LiteralPath $compilerPath -PathType Leaf)) {
    throw "FreeBASIC compiler was not found: $compilerPath"
}
if (-not (Test-Path -LiteralPath $omaGuiRoot -PathType Container)) {
    throw "omaGui include tree was not found: $omaGuiRoot"
}

New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
if ($UpdateBaselines) {
    New-Item -ItemType Directory -Path $baselineRoot -Force | Out-Null
}
elseif (-not (Test-Path -LiteralPath $baselineRoot -PathType Container)) {
    throw "Visual baseline directory was not found: $baselineRoot"
}

if ([string]::IsNullOrWhiteSpace($FixturePath)) {
    $fixtureGenerator = Join-Path $buildRoot 'visual_fixture_generator.exe'
    $FixturePath = Join-Path $buildRoot 'visual-fixture.mid'
    & $compilerPath `
        (Join-Path $projectRoot 'tests\empty_document_smoke.bas') `
        (Join-Path $projectRoot 'midi_model.bas') `
        '-x' $fixtureGenerator
    if ($LASTEXITCODE -ne 0) {
        throw "Visual MIDI fixture generator failed to compile: $LASTEXITCODE"
    }
    & $fixtureGenerator $FixturePath
    if ($LASTEXITCODE -ne 0) {
        throw "Visual MIDI fixture generator failed: $LASTEXITCODE"
    }
}
$fixtureFile = [System.IO.Path]::GetFullPath($FixturePath)
if (-not (Test-Path -LiteralPath $fixtureFile -PathType Leaf)) {
    throw "Visual MIDI fixture was not found: $fixtureFile"
}

# The document basename is rendered in both pane titles and status text. Use a
# fixed test copy so callers can supply identical MIDI bytes under any path
# without manufacturing a visual difference.
$canonicalFixtureFile = Join-Path $buildRoot 'visual-fixture.mid'
if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(
        $fixtureFile, $canonicalFixtureFile)) {
    Copy-Item -LiteralPath $fixtureFile -Destination $canonicalFixtureFile `
        -Force
}
$fixtureFile = $canonicalFixtureFile

if ([string]::IsNullOrWhiteSpace($EditorPath)) {
    $EditorPath = Join-Path $buildRoot 'opensesh_visual.exe'
    & (Join-Path $projectRoot 'build_editor.ps1') `
        -FreeBasicPath $compilerPath `
        -OmaGuiPath $omaGuiRoot `
        -OutputPath $EditorPath
    if ($LASTEXITCODE -ne 0) {
        throw "Visual editor failed to compile: $LASTEXITCODE"
    }
}
$editorExecutable = [System.IO.Path]::GetFullPath($EditorPath)
if (-not (Test-Path -LiteralPath $editorExecutable -PathType Leaf)) {
    throw "Visual editor executable was not found: $editorExecutable"
}

Add-Type -AssemblyName System.Drawing

function Get-CanonicalPixelHash {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ImagePath
    )

    $sourceImage = [System.Drawing.Bitmap]::new($ImagePath)
    $rectangle = [System.Drawing.Rectangle]::new(
        0, 0, $sourceImage.Width, $sourceImage.Height)
    # GDI+ converts both the backend's 24-bit BMP and the reviewed PNG into
    # the same packed pixel format. This excludes container headers, encoder
    # metadata, and palette representation from the regression comparison.
    $bitmapData = $sourceImage.LockBits(
        $rectangle,
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $byteCount = [Math]::Abs($bitmapData.Stride) * $bitmapData.Height
        $pixelBytes = [byte[]]::new($byteCount)
        [System.Runtime.InteropServices.Marshal]::Copy(
            $bitmapData.Scan0, $pixelBytes, 0, $byteCount)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            return ([System.BitConverter]::ToString(
                $sha256.ComputeHash($pixelBytes))).Replace('-', '')
        }
        finally {
            $sha256.Dispose()
        }
    }
    finally {
        $sourceImage.UnlockBits($bitmapData)
        $sourceImage.Dispose()
    }
}

function Save-PngBaseline {
    param(
        [Parameter(Mandatory = $true)]
        [string] $CapturePath,
        [Parameter(Mandatory = $true)]
        [string] $BaselinePath
    )

    $sourceImage = [System.Drawing.Bitmap]::new($CapturePath)
    try {
        $sourceImage.Save(
            $BaselinePath,
            [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $sourceImage.Dispose()
    }
}

function Assert-MatchingPixels {
    param(
        [Parameter(Mandatory = $true)]
        [string] $CapturePath,
        [Parameter(Mandatory = $true)]
        [string] $BaselinePath
    )

    $captureImage = [System.Drawing.Bitmap]::new($CapturePath)
    $baselineImage = [System.Drawing.Bitmap]::new($BaselinePath)
    try {
        if ($captureImage.Width -ne $baselineImage.Width -or
            $captureImage.Height -ne $baselineImage.Height) {
            throw ('Framebuffer dimensions changed from {0}x{1} to {2}x{3}.' -f `
                $baselineImage.Width, $baselineImage.Height,
                $captureImage.Width, $captureImage.Height)
        }
    }
    finally {
        $captureImage.Dispose()
        $baselineImage.Dispose()
    }

    $captureHash = Get-CanonicalPixelHash -ImagePath $CapturePath
    $baselineHash = Get-CanonicalPixelHash -ImagePath $BaselinePath
    if ($captureHash -ne $baselineHash) {
        throw "Framebuffer pixels changed: expected $baselineHash, got $captureHash."
    }
    return $captureHash
}

function Assert-CaptureDimensions {
    param(
        [Parameter(Mandatory = $true)]
        [string] $CapturePath,
        [Parameter(Mandatory = $true)]
        [int] $ExpectedWidth,
        [Parameter(Mandatory = $true)]
        [int] $ExpectedHeight
    )

    $captureImage = [System.Drawing.Bitmap]::new($CapturePath)
    try {
        if ($captureImage.Width -ne $ExpectedWidth -or
            $captureImage.Height -ne $ExpectedHeight) {
            throw ('Requested {0}x{1}, but gfxlib captured {2}x{3}.' -f `
                $ExpectedWidth, $ExpectedHeight,
                $captureImage.Width, $captureImage.Height)
        }
    }
    finally {
        $captureImage.Dispose()
    }
}

function Assert-ActiveMeterPixels {
    param(
        [Parameter(Mandatory = $true)]
        [string] $CapturePath,
        [Parameter(Mandatory = $true)]
        [int] $ExpectedWidth,
        [Parameter(Mandatory = $true)]
        [int] $ExpectedHeight
    )

    $bitmap = [System.Drawing.Bitmap]::new($CapturePath)
    try {
        # These calculations mirror mixerControls_CalculateLayout() and the
        # meter positions in session_DrawMixer(). Restricting the scan to the
        # three meter wells prevents an unrelated green icon from satisfying
        # the visible-activity contract.
        $masterWidth = 164
        $masterLeft = $ExpectedWidth - $masterWidth
        $visibleCount = [Math]::Floor(
            ($ExpectedWidth - $masterWidth - 8) / 58)
        if ($visibleCount -gt 16) {
            $visibleCount = 16
        }
        $channelAreaWidth = $masterLeft - 4 - 3
        $stripWidth = [Math]::Floor($channelAreaWidth / $visibleCount)
        $stripRight = 4 + $stripWidth - 2
        $channelMeterLeft = $stripRight - 9 - 4
        $faderTop = $ExpectedHeight - 238 + 52
        $faderBottom = $ExpectedHeight - 76
        $meterHeight = $faderBottom - $faderTop + 1

        $meterRectangles = @(
            [System.Drawing.Rectangle]::new(
                $channelMeterLeft, $faderTop, 9, $meterHeight),
            [System.Drawing.Rectangle]::new(
                $masterLeft + 63, $faderTop, 11, $meterHeight),
            [System.Drawing.Rectangle]::new(
                $masterLeft + 80, $faderTop, 11, $meterHeight)
        )

        foreach ($meterRectangle in $meterRectangles) {
            $brightPixels = 0
            for ($y = $meterRectangle.Top;
                $y -lt $meterRectangle.Bottom; $y++) {
                for ($x = $meterRectangle.Left;
                    $x -lt $meterRectangle.Right; $x++) {
                    $pixel = $bitmap.GetPixel($x, $y)
                    if ($pixel.R -eq 20 -and $pixel.G -eq 210 -and
                        $pixel.B -eq 42) {
                        $brightPixels++
                    }
                }
            }
            if ($brightPixels -eq 0) {
                throw 'Audition activity did not light every visible VU meter.'
            }
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

$visualCases = @(
    [pscustomobject]@{ Name = 'main-800x600'; Width = 800; Height = 600; Modal = ''; Palette = 0 },
    [pscustomobject]@{ Name = 'mixer-last-page-800x600'; Width = 800; Height = 600; Modal = ''; Palette = 0 },
    [pscustomobject]@{ Name = 'main-1280x720'; Width = 1280; Height = 720; Modal = ''; Palette = 0 },
    [pscustomobject]@{ Name = 'main-dark-1280x720'; Width = 1280; Height = 720; Modal = ''; Palette = 0 },
    [pscustomobject]@{ Name = 'main-black-1280x720'; Width = 1280; Height = 720; Modal = ''; Palette = 0 },
    [pscustomobject]@{ Name = 'active-meter-1280x720'; Width = 1280; Height = 720; Modal = ''; Palette = 0 },
    [pscustomobject]@{ Name = 'palette-1280x720'; Width = 1280; Height = 720; Modal = ''; Palette = 1 },
    [pscustomobject]@{ Name = 'main-touch-1280x720'; Width = 1280; Height = 720; Modal = ''; Palette = 0 },
    [pscustomobject]@{ Name = 'main-touch-y-zoom-1280x720'; Width = 1280; Height = 720; Modal = ''; Palette = 0 },
    [pscustomobject]@{ Name = 'palette-touch-1280x720'; Width = 1280; Height = 720; Modal = ''; Palette = 1 },
    [pscustomobject]@{ Name = 'options-menu-touch-1280x720'; Width = 1280; Height = 720; Modal = 'options_menu'; Palette = 0 },
    [pscustomobject]@{ Name = 'options-menu-1280x720'; Width = 1280; Height = 720; Modal = 'options_menu'; Palette = 0 },
    [pscustomobject]@{ Name = 'options-menu-dark-1280x720'; Width = 1280; Height = 720; Modal = 'options_menu'; Palette = 0 },
    [pscustomobject]@{ Name = 'options-menu-black-1280x720'; Width = 1280; Height = 720; Modal = 'options_menu'; Palette = 0 },
    [pscustomobject]@{ Name = 'view-menu-1280x720'; Width = 1280; Height = 720; Modal = 'view_menu'; Palette = 0 },
    [pscustomobject]@{ Name = 'about-1280x720'; Width = 1280; Height = 720; Modal = 'about'; Palette = 0 },
    [pscustomobject]@{ Name = 'about-dark-1280x720'; Width = 1280; Height = 720; Modal = 'about'; Palette = 0 },
    [pscustomobject]@{ Name = 'about-black-1280x720'; Width = 1280; Height = 720; Modal = 'about'; Palette = 0 },
    [pscustomobject]@{ Name = 'audio-1280x720'; Width = 1280; Height = 720; Modal = 'audio'; Palette = 0 },
    [pscustomobject]@{ Name = 'automation-1280x720'; Width = 1280; Height = 720; Modal = 'automation'; Palette = 0 },
    [pscustomobject]@{ Name = 'confirm-1280x720'; Width = 1280; Height = 720; Modal = 'confirm'; Palette = 0 },
    [pscustomobject]@{ Name = 'file-open-1280x720'; Width = 1280; Height = 720; Modal = 'file_open'; Palette = 0 },
    [pscustomobject]@{ Name = 'keyboard-1280x720'; Width = 1280; Height = 720; Modal = 'keyboard'; Palette = 0 },
    [pscustomobject]@{ Name = 'drums-1280x720'; Width = 1280; Height = 720; Modal = 'drums'; Palette = 0 },
    [pscustomobject]@{ Name = 'drums-dark-1280x720'; Width = 1280; Height = 720; Modal = 'drums'; Palette = 0 },
    [pscustomobject]@{ Name = 'drums-black-1280x720'; Width = 1280; Height = 720; Modal = 'drums'; Palette = 0 },
    [pscustomobject]@{ Name = 'drums-touch-1280x720'; Width = 1280; Height = 720; Modal = 'drums'; Palette = 0 },
    [pscustomobject]@{ Name = 'drum-machine-1280x720'; Width = 1280; Height = 720; Modal = 'drum_machine'; Palette = 0 },
    [pscustomobject]@{ Name = 'drum-machine-dark-1280x720'; Width = 1280; Height = 720; Modal = 'drum_machine'; Palette = 0 },
    [pscustomobject]@{ Name = 'drum-machine-black-1280x720'; Width = 1280; Height = 720; Modal = 'drum_machine'; Palette = 0 },
    [pscustomobject]@{ Name = 'drum-machine-touch-800x600'; Width = 800; Height = 600; Modal = 'drum_machine'; Palette = 0 },
    [pscustomobject]@{ Name = 'microphone-1280x720'; Width = 1280; Height = 720; Modal = 'microphone'; Palette = 0 },
    [pscustomobject]@{ Name = 'midi-input-1280x720'; Width = 1280; Height = 720; Modal = 'midi_input'; Palette = 0 },
    [pscustomobject]@{ Name = 'midi-output-1280x720'; Width = 1280; Height = 720; Modal = 'midi_output'; Palette = 0 },
    [pscustomobject]@{ Name = 'midi-save-1280x720'; Width = 1280; Height = 720; Modal = 'midi_save'; Palette = 0 },
    [pscustomobject]@{ Name = 'mod-export-1280x720'; Width = 1280; Height = 720; Modal = 'mod_export'; Palette = 0 },
    [pscustomobject]@{ Name = 'note-1280x720'; Width = 1280; Height = 720; Modal = 'note'; Palette = 0 },
    [pscustomobject]@{ Name = 'project-save-1280x720'; Width = 1280; Height = 720; Modal = 'project_save'; Palette = 0 },
    [pscustomobject]@{ Name = 'tempo-1280x720'; Width = 1280; Height = 720; Modal = 'tempo'; Palette = 0 },
    [pscustomobject]@{ Name = 'song-meter-800x600'; Width = 800; Height = 600; Modal = 'song_meter'; Palette = 0 },
    [pscustomobject]@{ Name = 'song-meter-touch-800x600'; Width = 800; Height = 600; Modal = 'song_meter'; Palette = 0 },
    [pscustomobject]@{ Name = 'note-tools-800x600'; Width = 800; Height = 600; Modal = 'note_tools'; Palette = 0 },
    [pscustomobject]@{ Name = 'note-tools-touch-800x600'; Width = 800; Height = 600; Modal = 'note_tools'; Palette = 0 },
    [pscustomobject]@{ Name = 'note-tools-dark-1280x720'; Width = 1280; Height = 720; Modal = 'note_tools'; Palette = 0 },
    [pscustomobject]@{ Name = 'drum-starter-800x600'; Width = 800; Height = 600; Modal = 'drum_starter'; Palette = 0 },
    [pscustomobject]@{ Name = 'quick-start-800x600'; Width = 800; Height = 600; Modal = 'quick_start'; Palette = 0 },
    [pscustomobject]@{ Name = 'quick-start-touch-800x600'; Width = 800; Height = 600; Modal = 'quick_start'; Palette = 0 },
    [pscustomobject]@{ Name = 'track-1280x720'; Width = 1280; Height = 720; Modal = 'track'; Palette = 0 },
    [pscustomobject]@{ Name = 'wav-export-1280x720'; Width = 1280; Height = 720; Modal = 'wav_export'; Palette = 0 }
)

# Select exact cases when reviewing one changed surface, so updating its
# baselines cannot accept unrelated framebuffer changes elsewhere in the UI.
if ($CaseNames.Count -gt 0) {
    foreach ($caseName in $CaseNames) {
        if ($caseName -notin $visualCases.Name) {
            throw "Unknown visual case: $caseName"
        }
    }
    $visualCases = @($visualCases | Where-Object { $_.Name -in $CaseNames })
}

$captureRoot = Join-Path $buildRoot 'visual-captures'
New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
$dialogRoot = Join-Path $buildRoot `
    ('visual-dialog-root-' + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dialogRoot -Force | Out-Null

$environmentNames = @(
    'OSE_TEST_SNAPSHOT',
    'OSE_TEST_SNAPSHOT_FRAME',
    'OSE_TEST_WIDTH',
    'OSE_TEST_HEIGHT',
    'OSE_TEST_THEME',
    'OSE_TEST_OPEN_ADD_PALETTE',
    'OSE_TEST_MIXER_PAGE_ANCHOR',
    'OSE_TEST_AUDITION_PITCH',
    'OSE_TEST_MODAL',
    'OSE_TEST_VISUAL_DEVICES',
    'OSE_TEST_MOUSE_X',
    'OSE_TEST_MOUSE_Y',
    'OSE_TEST_SCORE_ROW_HEIGHT',
    'OSE_TEST_PREFERENCES_FILE',
    'OSE_INTERACTION_MODE',
    'SFXLIB_DRIVER'
)
$savedEnvironment = @{}
foreach ($environmentName in $environmentNames) {
    $savedEnvironment[$environmentName] =
        [Environment]::GetEnvironmentVariable($environmentName)
}

$failures = [System.Collections.Generic.List[string]]::new()
$passedCases = 0

try {
    Remove-Item Env:OSE_TEST_PREFERENCES_FILE -ErrorAction SilentlyContinue
    foreach ($visualCase in $visualCases) {
        $capturePath = Join-Path $captureRoot ($visualCase.Name + '.bmp')
        $baselinePath = Join-Path $baselineRoot ($visualCase.Name + '.png')

        $env:OSE_TEST_SNAPSHOT = $capturePath
        $env:OSE_TEST_SNAPSHOT_FRAME = '12'
        $env:OSE_TEST_WIDTH = [string] $visualCase.Width
        $env:OSE_TEST_HEIGHT = [string] $visualCase.Height
        if ($visualCase.Name -match '-black-') {
            $env:OSE_TEST_THEME = 'black'
        }
        elseif ($visualCase.Name -match '-dark-') {
            $env:OSE_TEST_THEME = 'dark'
        }
        else {
            $env:OSE_TEST_THEME = 'light'
        }
        $env:OSE_TEST_OPEN_ADD_PALETTE = [string] $visualCase.Palette
        if ($visualCase.Name -match '-touch-') {
            $env:OSE_INTERACTION_MODE = 'touch'
        }
        else {
            Remove-Item Env:OSE_INTERACTION_MODE -ErrorAction SilentlyContinue
        }
        if ($visualCase.Name -eq 'main-touch-y-zoom-1280x720') {
            $env:OSE_TEST_SCORE_ROW_HEIGHT = '76'
        }
        else {
            Remove-Item Env:OSE_TEST_SCORE_ROW_HEIGHT `
                -ErrorAction SilentlyContinue
        }
        if ($visualCase.Name -eq 'mixer-last-page-800x600') {
            $env:OSE_TEST_MIXER_PAGE_ANCHOR = '15'
        }
        else {
            Remove-Item Env:OSE_TEST_MIXER_PAGE_ANCHOR `
                -ErrorAction SilentlyContinue
        }
        # This suite owns framebuffer determinism. Default-driver lifecycle is
        # stressed separately, so every visual process uses the null backend
        # and cannot turn an audio endpoint delay into a modal-render failure.
        $env:SFXLIB_DRIVER = 'null'
        if ($visualCase.Name -eq 'active-meter-1280x720') {
            $env:OSE_TEST_AUDITION_PITCH = '69'
            # The null backend still runs the real sfxlib mixer but keeps the
            # deterministic framebuffer suite from playing through speakers.
        }
        else {
            Remove-Item Env:OSE_TEST_AUDITION_PITCH `
                -ErrorAction SilentlyContinue
        }
        $env:OSE_TEST_MODAL = [string] $visualCase.Modal
        $env:OSE_TEST_VISUAL_DEVICES = '1'
        # Hover states, status help, and the Add Note insertion guide all read
        # the application pointer. Pin it for every route so physical desktop
        # input cannot change a reviewed framebuffer or close a capture early.
        $env:OSE_TEST_MOUSE_X = '400'
        $env:OSE_TEST_MOUSE_Y = '150'

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $editorExecutable
        $startInfo.Arguments = '"' + $fixtureFile.Replace('"', '\"') + '"'
        $startInfo.WorkingDirectory = $dialogRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $false
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo

        try {
            if (-not $process.Start()) {
                throw 'Editor process could not be started.'
            }
            if (-not $process.WaitForExit($CaptureTimeoutSeconds * 1000)) {
                $process.Kill()
                $process.WaitForExit()
                throw "Editor exceeded the $CaptureTimeoutSeconds-second bound."
            }
            if ($process.ExitCode -ne 0) {
                throw "Editor exited with $($process.ExitCode)."
            }
        }
        catch {
            $failures.Add($visualCase.Name + ': ' + $_.Exception.Message)
            Write-Output ('FAIL  ' + $visualCase.Name + ' ' + $_.Exception.Message)
            continue
        }
        finally {
            $process.Dispose()
        }

        if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) {
            $failures.Add($visualCase.Name + ': framebuffer was not written')
            Write-Output ('FAIL  ' + $visualCase.Name + ' framebuffer was not written')
            continue
        }

        try {
            Assert-CaptureDimensions `
                -CapturePath $capturePath `
                -ExpectedWidth $visualCase.Width `
                -ExpectedHeight $visualCase.Height
            if ($visualCase.Name -eq 'active-meter-1280x720') {
                Assert-ActiveMeterPixels `
                    -CapturePath $capturePath `
                    -ExpectedWidth $visualCase.Width `
                    -ExpectedHeight $visualCase.Height
            }
            if ($UpdateBaselines) {
                Save-PngBaseline -CapturePath $capturePath `
                    -BaselinePath $baselinePath
                $pixelHash = Get-CanonicalPixelHash -ImagePath $capturePath
                Write-Output ('UPDATE ' + $visualCase.Name + ' pixels=' + $pixelHash)
            }
            else {
                if (-not (Test-Path -LiteralPath $baselinePath -PathType Leaf)) {
                    throw "Reviewed baseline is missing: $baselinePath"
                }
                $pixelHash = Assert-MatchingPixels `
                    -CapturePath $capturePath -BaselinePath $baselinePath
                Write-Output ('PASS  ' + $visualCase.Name + ' pixels=' + $pixelHash)
            }
            $passedCases++
        }
        catch {
            $failures.Add($visualCase.Name + ': ' + $_.Exception.Message)
            Write-Output ('FAIL  ' + $visualCase.Name + ' ' + $_.Exception.Message)
        }
    }
}
finally {
    foreach ($environmentName in $environmentNames) {
        if ($null -eq $savedEnvironment[$environmentName]) {
            Remove-Item ('Env:' + $environmentName) -ErrorAction SilentlyContinue
        }
        else {
            Set-Item ('Env:' + $environmentName) `
                $savedEnvironment[$environmentName]
        }
    }

    if (Test-Path -LiteralPath $dialogRoot -PathType Container) {
        $resolvedDialogRoot = [System.IO.Path]::GetFullPath($dialogRoot)
        $buildBoundary = $buildRoot.TrimEnd('\') + '\'
        $dialogLeaf = Split-Path -Leaf $resolvedDialogRoot
        if (-not $resolvedDialogRoot.StartsWith(
                $buildBoundary,
                [System.StringComparison]::OrdinalIgnoreCase) -or
            -not $dialogLeaf.StartsWith('visual-dialog-root-')) {
            throw "Refusing to remove unexpected dialog root: $resolvedDialogRoot"
        }
        Remove-Item -LiteralPath $resolvedDialogRoot -Recurse -Force
    }
}

Write-Output ('visual_cases=' + $visualCases.Count)
Write-Output ('visual_passed=' + $passedCases)
Write-Output ('visual_failed=' + $failures.Count)
Write-Output ('visual_capture_directory=' + $captureRoot)

if ($failures.Count -gt 0) {
    throw ('Visual regression failed: ' + ($failures -join '; '))
}

# end of tests/run_visual_regression.ps1
