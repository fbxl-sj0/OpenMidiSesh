<#
    Project: OpenMidiSesh
    ----------------------------

    File: tests/run_android_device_smoke.ps1

    Purpose:

        Verify the shared editor and touch interface on an attached Android
        device.

    Responsibilities:

        - build and install the current Android package
        - verify the device, API level, ABI, launch state, and framebuffer size
        - exercise Monitor and the MIDI input chooser at native display density
        - verify portrait and landscape rotation and restore device settings
        - reject unsolicited keyboards, unresponsive controls or fatal logs
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
$packageName = 'net.fbxl.openmidisesh'
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
    $ApkPath = Join-Path $buildRoot 'openmidisesh-device-smoke.apk'
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

    $remotePath = '/sdcard/openmidisesh-device-smoke.png'
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
    $apiLevel -lt 23) {
    throw "Android API 23 or newer is required; device reported $apiLevelText."
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

# The physical controller check is separate: the USB socket may be occupied by
# ADB. This smoke verifies the packaged bridge/UI and records no hardware claim.
$initialPath = Join-Path $buildRoot '01-initial.png'
Save-DeviceScreenshot -DestinationPath $initialPath
$initialImage = [System.Drawing.Bitmap]::new($initialPath)
try {
    $screenWidth = $initialImage.Width
    $screenHeight = $initialImage.Height
}
finally { $initialImage.Dispose() }
if ($screenWidth -lt 320 -or $screenHeight -lt 240) {
    throw "Display is too small: ${screenWidth}x${screenHeight}."
}
$imeState = (Invoke-Adb -CommandArguments @('shell', 'dumpsys', 'input_method')) -join "`n"
if ($imeState -match 'mInputShown=true') { throw 'The software keyboard opened without a text request.' }
$densityText = (Invoke-Adb -CommandArguments @('shell', 'wm', 'density')) -join "`n"
$densityMatches = [regex]::Matches($densityText, 'density:\s*(\d+)')
if ($densityMatches.Count -eq 0) { throw 'Device density was not reported.' }
$dpi = [int] $densityMatches[$densityMatches.Count - 1].Groups[1].Value
$logicalWidth = [Math]::Max(320, [int] [Math]::Floor($screenWidth * 160.0 / $dpi))
$logicalHeight = [Math]::Max(240, [int] [Math]::Floor($screenHeight * 160.0 / $dpi))
$scaleX = $screenWidth / [double] $logicalWidth
$scaleY = $screenHeight / [double] $logicalHeight
$menuHeight = 38
if ($logicalWidth -lt 640) { $menuHeight = 76 }
$transportCount = 7
if ($logicalWidth -lt 800) { $transportCount = 4 }
$monitorLeft = 8 + 62 * $transportCount
$monitorTop = $menuHeight + 7
if ($monitorLeft + 92 -gt $logicalWidth - 8) { $monitorLeft = 8; $monitorTop += 62 }
$inputLeft = $monitorLeft + 98
$inputTop = $monitorTop
if ($inputLeft + 76 -gt $logicalWidth - 8) { $inputLeft = 8; $inputTop += 62 }

function Invoke-LogicalTap {
    param([double] $X, [double] $Y, [int] $DurationMilliseconds = 280)
    $pixelX = [int] [Math]::Round($X * $scaleX)
    $pixelY = [int] [Math]::Round($Y * $scaleY)
    Invoke-DeviceTouch -StartX $pixelX -StartY $pixelY -EndX $pixelX -EndY $pixelY -DurationMilliseconds $DurationMilliseconds
}
Invoke-LogicalTap ($monitorLeft + 46) ($monitorTop + 28)
$monitorPath = Join-Path $buildRoot '02-monitor.png'
Save-DeviceScreenshot -DestinationPath $monitorPath
if ((Get-FileHash $initialPath).Hash -eq (Get-FileHash $monitorPath).Hash) {
    throw 'Monitor produced no visible response.'
}
Invoke-LogicalTap ($inputLeft + 38) ($inputTop + 28)
$inputPath = Join-Path $buildRoot '03-input.png'
Save-DeviceScreenshot -DestinationPath $inputPath
if ((Get-FileHash $inputPath).Hash -eq (Get-FileHash $monitorPath).Hash) {
    throw 'MIDI In did not open its chooser.'
}
$chooserWidth = [Math]::Min(460, $logicalWidth - 16)
$chooserLeft = ($logicalWidth - $chooserWidth) / 2
$chooserTop = [Math]::Max(0, ($logicalHeight - 280) / 2)
Invoke-LogicalTap ($chooserLeft + $chooserWidth - 12) ($chooserTop + 10)

$savedAuto = ([string] (Invoke-Adb -CommandArguments @('shell', 'settings', 'get', 'system', 'accelerometer_rotation'))).Trim()
$savedRotation = ([string] (Invoke-Adb -CommandArguments @('shell', 'settings', 'get', 'system', 'user_rotation'))).Trim()
try {
    Invoke-Adb -CommandArguments @('shell', 'settings', 'put', 'system', 'accelerometer_rotation', '0') -AllowEmptyOutput | Out-Null
    foreach ($rotation in @(0, 1)) {
        Invoke-Adb -CommandArguments @('shell', 'settings', 'put', 'system', 'user_rotation', [string] $rotation) -AllowEmptyOutput | Out-Null
        # The compositor rotates before older NativeActivity runtimes finish
        # replacing their input surface. Test controls after both have settled.
        Start-Sleep -Seconds 5
        $rotationPath = Join-Path $buildRoot ('04-rotation-' + $rotation + '.png')
        Save-DeviceScreenshot -DestinationPath $rotationPath
        $rotated = [System.Drawing.Bitmap]::new($rotationPath)
        try {
            if (($rotation -eq 0 -and $rotated.Width -ge $rotated.Height) -or
                ($rotation -eq 1 -and $rotated.Width -le $rotated.Height)) {
                throw 'The activity did not follow requested portrait/landscape rotation.'
            }
        }
        finally { $rotated.Dispose() }
        if ($rotation -eq 1 -and $logicalWidth -eq 360 -and $logicalHeight -eq 640) {
            # The 360x640 phone profile rotates to a 640x360 viewport and uses the View menu's last command.
            # A popup must fit all eight rows so a touch can reach that command.
            # Hold menu gestures across the older runtime's idle input sampling.
            Invoke-LogicalTap 225 19 650
            Save-DeviceScreenshot -DestinationPath (Join-Path $buildRoot '05-view-menu.png')
            Invoke-LogicalTap 225 336 650
            $mixerPath = Join-Path $buildRoot '06-mixer.png'
            Start-Sleep -Seconds 2
            Save-DeviceScreenshot -DestinationPath $mixerPath
            if ((Get-FileHash $mixerPath).Hash -eq (Get-FileHash $rotationPath).Hash) {
                throw 'The compact Score/Mixer switch produced no visible change.'
            }
            Invoke-LogicalTap 225 19 650
            Invoke-LogicalTap 225 336 650
            $scorePath = Join-Path $buildRoot '07-score.png'
            Start-Sleep -Seconds 2
            Save-DeviceScreenshot -DestinationPath $scorePath
            if ((Get-FileHash $mixerPath).Hash -eq (Get-FileHash $scorePath).Hash) {
                throw 'The compact pane did not switch back to Score.'
            }
            $statusRegion = [Drawing.Rectangle]::new(0, 202, 500, 22)
            if ((Get-RegionHash -ImagePath $rotationPath -Rectangle $statusRegion) -ne
                (Get-RegionHash -ImagePath $scorePath -Rectangle $statusRegion)) {
                throw 'A popup selection also activated a control underneath it.'
            }
            $scoreRegion = [Drawing.Rectangle]::new(230, 280, 960, 350)
            if ((Get-RegionHash -ImagePath $rotationPath -Rectangle $scoreRegion) -ne
                (Get-RegionHash -ImagePath $scorePath -Rectangle $scoreRegion)) {
                throw 'Returning to Score left stale mixer pixels in the notation.'
            }
        }
    }
}
finally {
    foreach ($setting in @(@('user_rotation', $savedRotation), @('accelerometer_rotation', $savedAuto))) {
        if ($setting[1] -eq 'null') {
            Invoke-Adb -CommandArguments @('shell', 'settings', 'delete', 'system', $setting[0]) -AllowEmptyOutput | Out-Null
        }
        else {
            Invoke-Adb -CommandArguments @('shell', 'settings', 'put', 'system', $setting[0], $setting[1]) -AllowEmptyOutput | Out-Null
        }
    }
}
$processIdText = ([string] (Invoke-Adb -CommandArguments @('shell', 'pidof', $packageName))).Trim()
if ($processIdText -notmatch '^\d+(\s+\d+)*$') { throw 'The editor exited during mobile input or rotation.' }
$logPath = Join-Path $buildRoot 'logcat.txt'
$logLines = Invoke-Adb -CommandArguments @('logcat', '-d', '-v', 'brief')
[IO.File]::WriteAllLines($logPath, [string[]] $logLines)
$logText = $logLines -join "`n"
if ($logText -match '(?i)FATAL EXCEPTION|Fatal signal|ANR in net\.fbxl\.openmidisesh') {
    throw 'Fatal Android runtime output was found in logcat.'
}
if ($logText -notmatch 'FreeBASIC Android sfx warmup complete') { throw 'Audio warmup did not complete.' }
Write-Output ('android_device_serial=' + $script:SelectedDevice)
Write-Output ('android_device_model=' + $modelName)
Write-Output ('android_device_api=' + $apiLevel)
Write-Output ('android_device_abi=' + $abiName)
Write-Output ('android_framebuffer=' + $screenWidth + 'x' + $screenHeight)
Write-Output ('android_logical_viewport=' + $logicalWidth + 'x' + $logicalHeight)
Write-Output ('android_screenshots=' + $buildRoot)
Write-Output 'android_rotations=portrait,landscape settings=restored'
if ($logicalWidth -eq 360 -and $logicalHeight -eq 640) { Write-Output 'android_compact_panes=score,mixer touch=pass' }
Write-Output 'android_usb_midi_hardware=not_tested'
Write-Output 'android_device_smoke=pass'

# end of tests/run_android_device_smoke.ps1
