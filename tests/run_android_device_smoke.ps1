<#
    Project: OpenSesh
    ----------------------------

    File: tests/run_android_device_smoke.ps1

    Purpose:

        Verify the shared editor and touch interface on an attached Android
        device.

    Responsibilities:

        - build and install the current Android package
        - verify the device, API level, ABI, launch state, and framebuffer size
        - exercise palette, note insertion, selection, drag, and playback input
        - open the shared drum kit and change velocity through real touch input
        - reject stale palette rendering, missing score changes, or fatal logs
        - retain screenshots and logcat output as reviewable device evidence

    This file intentionally does NOT contain:

        - application UI or Android runtime implementation
        - device provisioning or bootloader operations
        - destructive application-data or device-storage cleanup
#>

[CmdletBinding()]
param(
    [string] $AdbPath =
        'C:\Users\admin\AppData\Local\Android\platform-tools\adb.exe',
    [string] $DeviceSerial = '',
    [string] $ApkPath = '',
    [string] $BuildDirectory = '',
    [switch] $SkipBuild,
    [ValidateRange(5, 60)]
    [int] $LaunchTimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$adbExecutable = [System.IO.Path]::GetFullPath($AdbPath)
$packageName = 'net.fbxl.opensesh'
$activityName = 'org.freebasic.android.FreeBasicNativeActivity'
$componentName = $packageName + '/' + $activityName

if (-not (Test-Path -LiteralPath $adbExecutable -PathType Leaf)) {
    throw "Android Debug Bridge was not found: $adbExecutable"
}
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $PSScriptRoot 'build\android-device-smoke'
}
$buildRoot = [System.IO.Path]::GetFullPath($BuildDirectory)
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
Add-Type -AssemblyName System.Drawing

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = Join-Path $buildRoot 'opensesh-device-smoke.apk'
}
$apkFile = [System.IO.Path]::GetFullPath($ApkPath)

function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $CommandArguments,
        [switch] $AllowEmptyOutput
    )

    # Windows PowerShell promotes any native stderr text to an ErrorRecord
    # while ErrorActionPreference is Stop. adb reports successful transfer
    # statistics on stderr, so inspect its process exit code explicitly.
    $savedErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $adbExecutable '-s' $script:SelectedDevice `
            @CommandArguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorPreference
    }
    if ($exitCode -ne 0) {
        throw ('adb failed with exit {0}: adb {1}{2}{3}' -f `
            $exitCode,
            ($CommandArguments -join ' '),
            [Environment]::NewLine,
            ($output -join [Environment]::NewLine))
    }
    if (-not $AllowEmptyOutput -and $null -eq $output) {
        throw 'adb returned no output for a command that requires a result.'
    }
    return $output
}

function Save-DeviceScreenshot {
    param(
        [Parameter(Mandatory = $true)]
        [string] $DestinationPath
    )

    $remotePath = '/sdcard/opensesh-device-smoke.png'
    Invoke-Adb -CommandArguments @('shell', 'screencap', '-p', $remotePath) `
        -AllowEmptyOutput | Out-Null
    Invoke-Adb -CommandArguments @('pull', $remotePath, $DestinationPath) |
        Out-Null
    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf) -or
        (Get-Item -LiteralPath $DestinationPath).Length -le 0) {
        throw "Android screenshot was not retrieved: $DestinationPath"
    }
}

function Invoke-DeviceTouch {
    param(
        [Parameter(Mandatory = $true)]
        [int] $StartX,
        [Parameter(Mandatory = $true)]
        [int] $StartY,
        [Parameter(Mandatory = $true)]
        [int] $EndX,
        [Parameter(Mandatory = $true)]
        [int] $EndY,
        [ValidateRange(100, 2000)]
        [int] $DurationMilliseconds = 280
    )

    Invoke-Adb -CommandArguments @(
        'shell', 'input', 'swipe',
        [string] $StartX, [string] $StartY,
        [string] $EndX, [string] $EndY,
        [string] $DurationMilliseconds
    ) -AllowEmptyOutput | Out-Null
    Start-Sleep -Milliseconds 450
}

function Get-RegionHash {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ImagePath,
        [Parameter(Mandatory = $true)]
        [System.Drawing.Rectangle] $Rectangle
    )

    $sourceImage = [System.Drawing.Bitmap]::new($ImagePath)
    try {
        if ($Rectangle.Left -lt 0 -or $Rectangle.Top -lt 0 -or
            $Rectangle.Right -gt $sourceImage.Width -or
            $Rectangle.Bottom -gt $sourceImage.Height) {
            throw "Screenshot region is outside the image: $Rectangle"
        }
        $regionImage = $sourceImage.Clone(
            $Rectangle,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $memory = [System.IO.MemoryStream]::new()
            try {
                $regionImage.Save(
                    $memory,
                    [System.Drawing.Imaging.ImageFormat]::Bmp)
                $sha256 = [System.Security.Cryptography.SHA256]::Create()
                try {
                    return ([System.BitConverter]::ToString(
                        $sha256.ComputeHash($memory.ToArray()))).Replace('-', '')
                }
                finally {
                    $sha256.Dispose()
                }
            }
            finally {
                $memory.Dispose()
            }
        }
        finally {
            $regionImage.Dispose()
        }
    }
    finally {
        $sourceImage.Dispose()
    }
}

$deviceLines = & $adbExecutable 'devices'
if ($LASTEXITCODE -ne 0) {
    throw 'adb could not enumerate attached devices.'
}
$availableDevices = @($deviceLines | ForEach-Object {
    if ($_ -match '^([^\s]+)\s+device$') {
        $matches[1]
    }
})
if ([string]::IsNullOrWhiteSpace($DeviceSerial)) {
    if ($availableDevices.Count -ne 1) {
        throw ('Exactly one ready Android device is required when ' +
            '-DeviceSerial is omitted.')
    }
    $script:SelectedDevice = $availableDevices[0]
}
else {
    if ($availableDevices -notcontains $DeviceSerial) {
        throw "The requested Android device is not ready: $DeviceSerial"
    }
    $script:SelectedDevice = $DeviceSerial
}

$apiLevelText = [string] (Invoke-Adb -CommandArguments @(
    'shell', 'getprop', 'ro.build.version.sdk'))
$abiName = ([string] (Invoke-Adb -CommandArguments @(
    'shell', 'getprop', 'ro.product.cpu.abi'))).Trim()
$modelName = ([string] (Invoke-Adb -CommandArguments @(
    'shell', 'getprop', 'ro.product.model'))).Trim()
$apiLevel = 0
if (-not [int]::TryParse($apiLevelText.Trim(), [ref] $apiLevel) -or
    $apiLevel -lt 21) {
    throw "Android API 21 or newer is required; device reported $apiLevelText."
}
if ($abiName -notmatch '^arm64-v8a$') {
    throw "The default Android package requires arm64-v8a; device reported $abiName."
}

if (-not $SkipBuild) {
    & (Join-Path $projectRoot 'build_editor_android.ps1') `
        -OutputPath $apkFile
    if ($LASTEXITCODE -ne 0) {
        throw "Android package build failed with exit $LASTEXITCODE."
    }
}
if (-not (Test-Path -LiteralPath $apkFile -PathType Leaf)) {
    throw "Android package was not found: $apkFile"
}

$installOutput = Invoke-Adb -CommandArguments @('install', '-r', $apkFile)
if (($installOutput -join "`n") -notmatch '(?m)^Success\s*$') {
    throw 'adb did not confirm successful package installation.'
}

Invoke-Adb -CommandArguments @('logcat', '-c') -AllowEmptyOutput | Out-Null
Invoke-Adb -CommandArguments @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP') `
    -AllowEmptyOutput | Out-Null
Invoke-Adb -CommandArguments @('shell', 'wm', 'dismiss-keyguard') `
    -AllowEmptyOutput | Out-Null
Invoke-Adb -CommandArguments @('shell', 'am', 'force-stop', $packageName) `
    -AllowEmptyOutput | Out-Null
$launchOutput = Invoke-Adb -CommandArguments @(
    'shell', 'am', 'start', '-W', '-n', $componentName)
if (($launchOutput -join "`n") -notmatch '(?m)^Status:\s+ok\s*$') {
    throw 'Android activity manager did not report a successful launch.'
}
Start-Sleep -Seconds 2

$initialPath = Join-Path $buildRoot '01-initial.png'
$palettePath = Join-Path $buildRoot '02-palette.png'
$notePath = Join-Path $buildRoot '03-note.png'
$selectedPath = Join-Path $buildRoot '04-selected.png'
$draggedPath = Join-Path $buildRoot '05-dragged.png'
$drumPath = Join-Path $buildRoot '06-drums.png'
$drumHardPath = Join-Path $buildRoot '07-drums-hard.png'
Save-DeviceScreenshot -DestinationPath $initialPath

$initialImage = [System.Drawing.Bitmap]::new($initialPath)
try {
    $screenWidth = $initialImage.Width
    $screenHeight = $initialImage.Height
}
finally {
    $initialImage.Dispose()
}
if ($screenWidth -lt 800 -or $screenHeight -lt 600 -or
    $screenWidth -le $screenHeight) {
    throw ('The Android editor requires a landscape framebuffer of at least ' +
        "800x600; device presented ${screenWidth}x${screenHeight}.")
}

$toolX = [int] [Math]::Round($screenWidth * 0.043)
$selectY = [int] [Math]::Round($screenHeight * 0.226)
$noteToolY = [int] [Math]::Round($screenHeight * 0.294)
$noteX = [int] [Math]::Round($screenWidth * 0.390)
$noteY = [int] [Math]::Round($screenHeight * 0.255)
$dragX = [int] [Math]::Round($screenWidth * 0.484)
$dragY = [int] [Math]::Round($screenHeight * 0.238)
$playX = [int] [Math]::Round($screenWidth * 0.318)
$playY = [int] [Math]::Round($screenHeight * 0.103)

$paletteRegion = [System.Drawing.Rectangle]::new(
    [int] [Math]::Round($screenWidth * 0.086),
    [int] [Math]::Round($screenHeight * 0.196),
    [int] [Math]::Round($screenWidth * 0.193),
    [int] [Math]::Round($screenHeight * 0.400))
$scoreRegion = [System.Drawing.Rectangle]::new(
    [int] [Math]::Round($screenWidth * 0.280),
    [int] [Math]::Round($screenHeight * 0.200),
    [int] [Math]::Round($screenWidth * 0.420),
    [int] [Math]::Round($screenHeight * 0.120))
$initialPaletteHash = Get-RegionHash -ImagePath $initialPath `
    -Rectangle $paletteRegion
$initialScoreHash = Get-RegionHash -ImagePath $initialPath `
    -Rectangle $scoreRegion

Invoke-DeviceTouch -StartX $toolX -StartY $noteToolY `
    -EndX $toolX -EndY $noteToolY
Save-DeviceScreenshot -DestinationPath $palettePath
$openPaletteHash = Get-RegionHash -ImagePath $palettePath `
    -Rectangle $paletteRegion
if ($openPaletteHash -eq $initialPaletteHash) {
    throw 'Touching Note did not open the coarse-pointer note palette.'
}

Invoke-DeviceTouch -StartX $noteX -StartY $noteY `
    -EndX $noteX -EndY $noteY
Save-DeviceScreenshot -DestinationPath $notePath
$noteScoreHash = Get-RegionHash -ImagePath $notePath -Rectangle $scoreRegion
if ($noteScoreHash -eq $initialScoreHash) {
    throw 'Touching the score did not produce a visible note change.'
}

Invoke-DeviceTouch -StartX $toolX -StartY $selectY `
    -EndX $toolX -EndY $selectY
Save-DeviceScreenshot -DestinationPath $selectedPath
$closedPaletteHash = Get-RegionHash -ImagePath $selectedPath `
    -Rectangle $paletteRegion
if ($closedPaletteHash -ne $initialPaletteHash) {
    throw 'Selecting the pointer tool left stale palette pixels on the score.'
}

Invoke-DeviceTouch -StartX $noteX -StartY $noteY `
    -EndX $dragX -EndY $dragY -DurationMilliseconds 450
Save-DeviceScreenshot -DestinationPath $draggedPath
$draggedScoreHash = Get-RegionHash -ImagePath $draggedPath `
    -Rectangle $scoreRegion
if ($draggedScoreHash -eq $noteScoreHash) {
    throw 'Dragging the inserted note did not produce a visible score change.'
}

Invoke-DeviceTouch -StartX $playX -StartY $playY `
    -EndX $playX -EndY $playY
$processIdText = ([string] (Invoke-Adb -CommandArguments @(
    'shell', 'pidof', $packageName))).Trim()
if ($processIdText -notmatch '^\d+(\s+\d+)*$') {
    throw 'The Android editor process was not alive after touch playback.'
}

# The menu bar and generated drum buttons use the ordinary pointer stream,
# while the pads consume independent touch contacts. Opening the kit and
# changing one velocity therefore proves both sides of the shared adapter on
# the physical device.
$musicMenuX = 324
$musicMenuY = [int] [Math]::Round($screenHeight * 0.031)
$drumMenuItemX = 350
$drumMenuItemY = [int] [Math]::Round($screenHeight * 0.392)
Invoke-DeviceTouch -StartX $musicMenuX -StartY $musicMenuY `
    -EndX $musicMenuX -EndY $musicMenuY
Invoke-DeviceTouch -StartX $drumMenuItemX -StartY $drumMenuItemY `
    -EndX $drumMenuItemX -EndY $drumMenuItemY
Save-DeviceScreenshot -DestinationPath $drumPath

$drumWindowWidth = [Math]::Min($screenWidth - 24, 920)
$drumWindowHeight = [Math]::Min($screenHeight - 24, 650)
if ($drumWindowWidth -lt 620) {
    $drumWindowWidth = $screenWidth
}
if ($drumWindowHeight -lt 500) {
    $drumWindowHeight = $screenHeight
}
$drumWindowX = [int] (($screenWidth - $drumWindowWidth) / 2)
$drumWindowY = [int] (($screenHeight - $drumWindowHeight) / 2)
$drumRegion = [System.Drawing.Rectangle]::new(
    $drumWindowX,
    $drumWindowY,
    $drumWindowWidth,
    $drumWindowHeight)
$initialDrumRegionHash = Get-RegionHash -ImagePath $initialPath `
    -Rectangle $drumRegion
$openDrumRegionHash = Get-RegionHash -ImagePath $drumPath `
    -Rectangle $drumRegion
if ($openDrumRegionHash -eq $initialDrumRegionHash) {
    throw 'Touching Drum Kit did not open its shared performance surface.'
}

$velocityRegion = [System.Drawing.Rectangle]::new(
    $drumWindowX + 150,
    $drumWindowY + 32,
    350,
    56)
$mediumVelocityHash = Get-RegionHash -ImagePath $drumPath `
    -Rectangle $velocityRegion
$hardButtonX = $drumWindowX + 437
$hardButtonY = $drumWindowY + 58
Invoke-DeviceTouch -StartX $hardButtonX -StartY $hardButtonY `
    -EndX $hardButtonX -EndY $hardButtonY
Save-DeviceScreenshot -DestinationPath $drumHardPath
$hardVelocityHash = Get-RegionHash -ImagePath $drumHardPath `
    -Rectangle $velocityRegion
if ($hardVelocityHash -eq $mediumVelocityHash) {
    throw 'Touching Hard did not change the drum velocity selection.'
}

$drumSurfaceX = $drumWindowX + 18
$drumSurfaceY = $drumWindowY + 142
$drumSurfaceWidth = $drumWindowWidth - 36
$drumSurfaceHeight = $drumWindowHeight - 160
$drumPadWidth = [int] (($drumSurfaceWidth - 30) / 4)
$drumPadHeight = [int] (($drumSurfaceHeight - 20) / 3)
$kickX = $drumSurfaceX + [int] ($drumPadWidth / 2)
$kickY = $drumSurfaceY + 2 * ($drumPadHeight + 10) + `
    [int] ($drumPadHeight / 2)
Invoke-DeviceTouch -StartX $kickX -StartY $kickY `
    -EndX $kickX -EndY $kickY
$processIdText = ([string] (Invoke-Adb -CommandArguments @(
    'shell', 'pidof', $packageName))).Trim()
if ($processIdText -notmatch '^\d+(\s+\d+)*$') {
    throw 'The Android editor process was not alive after a drum strike.'
}

$logPath = Join-Path $buildRoot 'logcat.txt'
$logLines = Invoke-Adb -CommandArguments @('logcat', '-d', '-v', 'brief')
[System.IO.File]::WriteAllLines($logPath, [string[]] $logLines)
$logText = $logLines -join "`n"
if ($logText -match '(?i)FATAL EXCEPTION|Fatal signal|ANR in net\.fbxl\.opensesh') {
    throw 'Fatal Android runtime output was found in the retained logcat file.'
}
if ($logText -notmatch 'FreeBASIC Android sfx warmup complete') {
    throw 'The Android audio backend did not report successful warmup.'
}

Write-Output ('android_device_serial=' + $script:SelectedDevice)
Write-Output ('android_device_model=' + $modelName)
Write-Output ('android_device_api=' + $apiLevel)
Write-Output ('android_device_abi=' + $abiName)
Write-Output ('android_framebuffer=' + $screenWidth + 'x' + $screenHeight)
Write-Output ('android_touch_actions=9')
Write-Output ('android_screenshots=' + $buildRoot)
Write-Output ('android_logcat=' + $logPath)
Write-Output 'android_device_smoke=pass'

# end of tests/run_android_device_smoke.ps1
