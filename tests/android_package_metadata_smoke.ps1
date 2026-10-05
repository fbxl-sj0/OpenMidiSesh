<#
    Project: OpenSesh
    File: tests/android_package_metadata_smoke.ps1
    Purpose: Verify Android package metadata staging without an Android SDK.
    Responsibilities:
        - use fake templates and a wrapper which only records its inputs
        - check product version, upgrade counter and retained custom resources
        - require original templates and environment values to survive builds
        - require staging cleanup after successful and failed wrapper calls
    This file intentionally does NOT contain:
        - compiler, signing-tool or Android-device calls
        - changes to installed toolchains or application version constants
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildScript = Join-Path $projectRoot 'build_editor_android.ps1'
$versionSource = Get-Content -LiteralPath (Join-Path $projectRoot 'src\version.bi') -Raw
$versionMatch = [regex]::Match($versionSource,
    '(?m)^Const OSE_VERSION_TEXT As String = "([^"\r\n]+)"')
if (-not $versionMatch.Success) { throw 'The product display version was not found.' }
$expectedVersion = $versionMatch.Groups[1].Value
$androidNamespace = 'http://schemas.android.com/apk/res/android'

function Assert-Test {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Set-TestEnvironment {
    param([string] $Name, $Value)
    if ($null -eq $Value) {
        [Environment]::SetEnvironmentVariable($Name, [NullString]::Value, 'Process')
    }
    else {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
    }
}

function Get-TemplateSnapshot {
    param([string] $Root, [switch] $ExcludeManifest)
    $boundary = $Root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $entries = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File |
        Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($boundary.Length).Replace('\', '/')
            if (-not $ExcludeManifest -or $relative -ne 'AndroidManifest.xml.in') {
                $relative + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        })
    return $entries -join "`n"
}

function New-TestTemplate {
    param([string] $Root, [string] $Label, [switch] $OldVersion)
    New-Item -ItemType Directory -Path (Join-Path $Root 'res\raw') -Force | Out-Null
    $versions = ''
    if ($OldVersion) { $versions = ' android:versionName="old" android:versionCode="77"' }
    $manifestText = @"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="@PACKAGE@" android:installLocation="auto"$versions>
    <uses-sdk android:minSdkVersion="@MIN_SDK@" android:targetSdkVersion="@TARGET_SDK@" />
    <application android:label="$Label">
        <meta-data android:name="test.extra" android:value="retained &amp; escaped" />
    </application>
</manifest>
"@
    [System.IO.File]::WriteAllText((Join-Path $Root 'AndroidManifest.xml.in'), $manifestText)
    foreach ($name in @('fb_android_app.c', 'FreeBasicNativeActivity.java',
            'FreeBasicInputBridge.java', 'FreeBasicInputView.java', 'strings.xml', '.retained')) {
        [System.IO.File]::WriteAllText((Join-Path $Root $name), $Label + ':' + $name)
    }
    [System.IO.File]::WriteAllBytes((Join-Path $Root 'res\raw\payload.bin'),
        [byte[]] @(0, 1, 127, 128, 255))
}

$temporaryParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testName = 'opensesh-android-metadata-' + [Guid]::NewGuid().ToString('N')
$testRoot = Join-Path $temporaryParent $testName
$savedEnvironment = @{}
foreach ($name in @('FBANDROID_TEMPLATE', 'OSE_ANDROID_METADATA_CAPTURE', 'OSE_ANDROID_METADATA_MODE')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $wrapperRoot = Join-Path $testRoot 'fake android toolchain'
    $defaultTemplate = Join-Path $wrapperRoot 'share\freebasic-android\template'
    $customTemplate = Join-Path $testRoot 'custom template'
    New-TestTemplate -Root $defaultTemplate -Label 'default-template'
    New-TestTemplate -Root $customTemplate -Label 'custom-template' -OldVersion
    $defaultSnapshot = Get-TemplateSnapshot -Root $defaultTemplate
    $customSnapshot = Get-TemplateSnapshot -Root $customTemplate
    $wrapper = Join-Path $wrapperRoot 'fbc-android.ps1'
    $wrapperText = @'
$ErrorActionPreference = 'Stop'
$template = [Environment]::GetEnvironmentVariable('FBANDROID_TEMPLATE', 'Process')
$templateRoot = [System.IO.Path]::GetFullPath($template)
$boundary = $templateRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
$otherFiles = @(Get-ChildItem -LiteralPath $templateRoot -Recurse -Force -File |
    Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($boundary.Length).Replace('\', '/')
        if ($relative -ne 'AndroidManifest.xml.in') {
            $relative + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    })
$capture = @{
    template = $template
    manifest = [System.IO.File]::ReadAllText((Join-Path $templateRoot 'AndroidManifest.xml.in'))
    otherFiles = $otherFiles
}
[System.IO.File]::WriteAllText($env:OSE_ANDROID_METADATA_CAPTURE,
    ($capture | ConvertTo-Json -Depth 4))
if ($env:OSE_ANDROID_METADATA_MODE -eq 'throw') { throw 'fake wrapper exception' }
if ($env:OSE_ANDROID_METADATA_MODE -eq 'fail') { $global:LASTEXITCODE = 23; return }
$outputIndex = [Array]::IndexOf($args, '-x')
if ($outputIndex -lt 0 -or $outputIndex + 1 -ge $args.Count) { throw 'Missing fake APK path.' }
[System.IO.File]::WriteAllText([string] $args[$outputIndex + 1], 'fake APK')
$global:LASTEXITCODE = 0
'@
    [System.IO.File]::WriteAllText($wrapper, $wrapperText)

    $nativeOverride = $customTemplate.Replace('\', '/')
    $cygwinOverride = '/cygdrive/' + $nativeOverride.Substring(0, 1).ToLowerInvariant() +
        $nativeOverride.Substring(2)
    # .NET Framework removes empty values; newer .NET can retain them. Exercise
    # that distinct state only when the current runtime can represent it.
    [Environment]::SetEnvironmentVariable('FBANDROID_TEMPLATE', [string]::Empty, 'Process')
    $supportsEmptyEnvironment = [Environment]::GetEnvironmentVariables('Process').Contains('FBANDROID_TEMPLATE') -and
        [Environment]::GetEnvironmentVariable('FBANDROID_TEMPLATE', 'Process') -ceq [string]::Empty
    $cases = @(
        @{ Name = 'default-absent'; Template = $null; Source = $defaultTemplate; Code = $null; ExpectedCode = 1; Mode = 'ok'; Exit = 0; Label = 'default-template' }
    )
    if ($supportsEmptyEnvironment) {
        $cases += @{ Name = 'default-empty'; Template = ''; Source = $defaultTemplate; Code = $null; ExpectedCode = 1; Mode = 'ok'; Exit = 0; Label = 'default-template' }
    }
    $cases += @(
        @{ Name = 'custom'; Template = $nativeOverride; Source = $customTemplate; Code = 42; ExpectedCode = 42; Mode = 'ok'; Exit = 0; Label = 'custom-template' },
        @{ Name = 'cygwin'; Template = $cygwinOverride; Source = $customTemplate; Code = 43; ExpectedCode = 43; Mode = 'ok'; Exit = 0; Label = 'custom-template' },
        @{ Name = 'failed'; Template = $nativeOverride; Source = $customTemplate; Code = 44; ExpectedCode = 44; Mode = 'fail'; Exit = 23; Label = 'custom-template' },
        @{ Name = 'exception'; Template = $nativeOverride; Source = $customTemplate; Code = 45; ExpectedCode = 45; Mode = 'throw'; Exit = $null; Label = 'custom-template' }
    )
    foreach ($case in $cases) {
        $capturePath = Join-Path $testRoot ($case.Name + '.json')
        $apkPath = Join-Path $testRoot ($case.Name + '.apk')
        Set-TestEnvironment -Name 'FBANDROID_TEMPLATE' -Value $case.Template
        [Environment]::SetEnvironmentVariable('OSE_ANDROID_METADATA_CAPTURE', $capturePath, 'Process')
        [Environment]::SetEnvironmentVariable('OSE_ANDROID_METADATA_MODE', $case.Mode, 'Process')
        $arguments = @{ FreeBasicAndroidPath = $wrapper; OutputPath = $apkPath }
        if ($null -ne $case.Code) { $arguments.VersionCode = $case.Code }
        $caught = $null
        try {
            & $buildScript @arguments | Out-Null
            $actualExit = $LASTEXITCODE
        }
        catch { $caught = $_ }
        if ($case.Mode -eq 'throw') {
            Assert-Test ($null -ne $caught -and $caught.Exception.Message -like '*fake wrapper exception*') `
                'Wrapper exception did not propagate.'
        }
        else {
            if ($null -ne $caught) { throw $caught }
            Assert-Test ($actualExit -eq $case.Exit) ('Wrong build exit for ' + $case.Name)
        }
        $templatePresent = [Environment]::GetEnvironmentVariables('Process').Contains('FBANDROID_TEMPLATE')
        Assert-Test ($templatePresent -eq ($null -ne $case.Template) -and
            [Environment]::GetEnvironmentVariable('FBANDROID_TEMPLATE', 'Process') -ceq $case.Template) `
            ('Template environment was not restored after ' + $case.Name)
        Assert-Test (Test-Path -LiteralPath $capturePath -PathType Leaf) 'Fake wrapper did not record its template.'
        $record = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
        Assert-Test ($record.template -match '^[A-Za-z]:/' -and -not $record.template.Contains('\')) `
            'Staged template did not use a native forward-slash path.'
        $stageRoot = Split-Path -Parent ([System.IO.Path]::GetFullPath($record.template))
        Assert-Test (-not (Test-Path -LiteralPath $stageRoot)) ('Template staging survived ' + $case.Name)
        Assert-Test ((Test-Path -LiteralPath $apkPath -PathType Leaf) -eq ($case.Mode -eq 'ok')) `
            ('Unexpected fake APK state for ' + $case.Name)
        $manifest = New-Object System.Xml.XmlDocument
        $manifest.XmlResolver = $null
        $manifest.LoadXml($record.manifest)
        $root = $manifest.DocumentElement
        Assert-Test ($root.GetAttribute('versionName', $androidNamespace) -ceq $expectedVersion) `
            'Manifest version name did not come from version.bi.'
        Assert-Test ($root.GetAttribute('versionCode', $androidNamespace) -ceq [string] $case.ExpectedCode) `
            'Manifest upgrade counter was not preserved independently.'
        Assert-Test ($root.GetAttribute('package') -ceq '@PACKAGE@' -and
            $root.GetAttribute('installLocation', $androidNamespace) -ceq 'auto' -and
            $root.'uses-sdk'.GetAttribute('minSdkVersion', $androidNamespace) -ceq '@MIN_SDK@' -and
            $root.'uses-sdk'.GetAttribute('targetSdkVersion', $androidNamespace) -ceq '@TARGET_SDK@' -and
            $root.application.GetAttribute('label', $androidNamespace) -ceq $case.Label -and
            $root.application.'meta-data'.GetAttribute('value', $androidNamespace) -ceq 'retained & escaped') `
            'Staging changed unrelated manifest metadata.'
        Assert-Test (($record.otherFiles -join "`n") -ceq (Get-TemplateSnapshot -Root $case.Source -ExcludeManifest)) `
            'Staging changed or omitted custom template resources.'
        Assert-Test ((Get-TemplateSnapshot -Root $defaultTemplate) -ceq $defaultSnapshot -and
            (Get-TemplateSnapshot -Root $customTemplate) -ceq $customSnapshot) `
            'The original template changed.'
    }

    foreach ($invalidCode in @(0, -1, 2100000001)) {
        $capturePath = Join-Path $testRoot ('invalid-' + $invalidCode + '.json')
        [Environment]::SetEnvironmentVariable('OSE_ANDROID_METADATA_CAPTURE', $capturePath, 'Process')
        $rejected = $false
        try {
            & $buildScript -FreeBasicAndroidPath $wrapper -OutputPath (Join-Path $testRoot 'invalid.apk') `
                -VersionCode $invalidCode | Out-Null
        }
        catch { $rejected = $true }
        Assert-Test ($rejected -and -not (Test-Path -LiteralPath $capturePath)) 'Invalid VersionCode reached the wrapper.'
        Assert-Test ([Environment]::GetEnvironmentVariable('FBANDROID_TEMPLATE', 'Process') -ceq $nativeOverride) `
            'Invalid VersionCode changed the template environment.'
    }
}
finally {
    foreach ($name in $savedEnvironment.Keys) {
        Set-TestEnvironment -Name $name -Value $savedEnvironment[$name]
    }
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $temporaryBoundary = $temporaryParent.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedTestRoot.StartsWith($temporaryBoundary,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($resolvedTestRoot) -ne $testName) {
        throw "Refusing to remove an unexpected metadata test path: $resolvedTestRoot"
    }
    if (Test-Path -LiteralPath $resolvedTestRoot) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

Write-Output ('android_package_metadata=ok builds=' + $cases.Count + ' invalid_version_codes=3 template_sources=2')
if ($supportsEmptyEnvironment) {
    Write-Output 'android_template_environment_cases=absent,empty,nonempty empty_environment=supported'
}
else {
    Write-Output 'android_template_environment_cases=absent,nonempty empty_environment=unsupported'
}
Write-Output 'android_template_originals=unchanged environment=restored failure_cleanup=ok'

# end of tests/android_package_metadata_smoke.ps1
