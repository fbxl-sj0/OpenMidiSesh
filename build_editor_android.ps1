<#
    Project: OpenSesh
    ----------------------------

    File: build_editor_android.ps1

    Purpose:

        Package the shared FreeBASIC editor as an Android application.

    Responsibilities:

        - validate the Android FreeBASIC wrapper and shared project sources
        - select the coarse-pointer profile as a first-run runtime default
        - substitute only the unavailable external-MIDI endpoint adapter
        - stage package version metadata without changing installed templates
        - produce one signed development APK for the requested Android ABI
        - optionally install and launch that APK on the attached device

    This file intentionally does NOT contain:

        - Android UI or touch behavior
        - duplicated editor, model, rendering, or audio implementation
        - SDK or device provisioning
#>

[CmdletBinding()]
param(
    [string] $FreeBasicAndroidPath = 'C:\freebasic-android\fbc-android.cmd',
    [string] $OmaGuiPath = '',
    [string] $OutputPath = '',
    [ValidateSet('android-arm', 'android-aarch64', 'android-x86_64')]
    [string] $Target = 'android-aarch64',
    [ValidateRange(21, 35)]
    [int] $ApiLevel = 24,
    [ValidateRange(1, 2100000000)]
    [int] $VersionCode = 1,
    [switch] $RunOnDevice
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($OmaGuiPath)) {
    $OmaGuiPath = Join-Path $projectRoot 'vendor\omaGui'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot 'build\android\opensesh-debug.apk'
}

$compilerPath = [System.IO.Path]::GetFullPath($FreeBasicAndroidPath)
$omaGuiRoot = [System.IO.Path]::GetFullPath($OmaGuiPath)
$outputFile = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $outputFile
$packageName = 'net.fbxl.opensesh'

if (-not (Test-Path -LiteralPath $compilerPath -PathType Leaf)) {
    throw "Android FreeBASIC wrapper was not found: $compilerPath"
}
if (-not (Test-Path -LiteralPath $omaGuiRoot -PathType Container)) {
    throw "omaGui include tree was not found: $omaGuiRoot"
}

$versionSource = Get-Content -LiteralPath (Join-Path $projectRoot 'version.bi') -Raw
$versionMatches = [regex]::Matches($versionSource,
    '(?m)^\s*Const\s+OSE_VERSION_TEXT\s+As\s+String\s*=\s*"([^"\r\n]+)"\s*$')
if ($versionMatches.Count -ne 1 -or
    [string]::IsNullOrWhiteSpace($versionMatches[0].Groups[1].Value)) {
    throw 'version.bi must declare one nonempty OSE_VERSION_TEXT string.'
}
$versionName = $versionMatches[0].Groups[1].Value

# The installed Windows wrapper selects this template unless the caller has
# supplied FBANDROID_TEMPLATE. Accept its native or Cygwin absolute path form.
$previousTemplate = [Environment]::GetEnvironmentVariable('FBANDROID_TEMPLATE', 'Process')
if ([string]::IsNullOrEmpty($previousTemplate)) {
    $templateSource = Join-Path (Split-Path -Parent $compilerPath) `
        'share\freebasic-android\template'
}
else {
    $templateSource = $previousTemplate
    if ($templateSource -match '^/cygdrive/([A-Za-z])(?:/(.*))?$') {
        $templateSource = $Matches[1] + ':\' + ([string] $Matches[2]).Replace('/', '\')
    }
}
if (-not (Test-Path -LiteralPath $templateSource -PathType Container)) {
    throw "Android package template was not found: $templateSource"
}
$templateSource = (Resolve-Path -LiteralPath $templateSource).ProviderPath
if (-not (Test-Path -LiteralPath (Join-Path $templateSource 'AndroidManifest.xml.in') -PathType Leaf)) {
    throw "Android manifest template was not found in: $templateSource"
}

$sourceFiles = @(
    'opensesh_unity.bas',
    'opensesh.bas',
    'omagui_runtime.bas',
    'midi_model.bas',
    'history_timeline.bas',
    'document_history.bas',
    'project_transaction.bas',
    'note_selection.bas',
    'selected_note_playback.bas',
    'score_tools.bas',
    'score_controls.bas',
    'numeric_text.bas',
    'capture_paths.bas',
    'score_scroll.bas',
    'score_layout.bas',
    'mixer_meter.bas',
    'mixer_controls.bas',
    'mixer_state.bas',
    'keyboard_controls.bas',
    'drum_kit.bas',
    'drum_phrase.bas',
    'playback_mix.bas',
    'playback_timing.bas',
    'ui_frame_pacing.bas',
    'soundfont_bank.bas',
    'soundfont_synth.bas',
    'software_synth.bas',
    'playback_state.bas',
    'master_effect.bas',
    'sfx_runtime.bas',
    'ui_style.bas',
    'ui_icons.bas',
    'ui_interaction.bas',
    'touch_gesture.bas',
    'user_preferences.bas',
    'music_export.bas',
    'wav_export_sfx.bas',
    'audio_tracks.bas',
    'audio_sample_slots.bas',
    'midi_input_protocol.bas',
    'midi_null.bas',
    'pitch_transcriber.bas',
    'music_symbols.bas'
)

foreach ($relativeFile in $sourceFiles) {
    $sourceFile = Join-Path $projectRoot $relativeFile
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        throw "Required source file is missing: $relativeFile"
    }
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

<#
    Android defaults are injected as ordinary application configuration. The
    program itself remains unaware of Android: it receives the same interaction
    and XDG paths that can be supplied on any host. Native external MIDI is the
    only substituted module; software-synth playback stays in the shared code.
#>
$compilerArguments = @(
    '--api', $ApiLevel,
    '--min-api', 21,
    '--target-api', 35,
    '--target', $Target,
    '--package', $packageName,
    '--label', 'OpenSesh',
    '--landscape',
    '--env', 'OSE_DEFAULT_INTERACTION_MODE=touch',
    '--env', "XDG_CONFIG_HOME=/data/data/$packageName",
    '-i', $omaGuiRoot,
    '-O', '2',
    '-mt',
    '-d', 'OSE_SFX_ECHO_AVAILABLE=0',
    '-d', 'OSE_SFX_OUTPUT_TELEMETRY_AVAILABLE=0',
    (Join-Path $projectRoot 'opensesh_unity.bas'),
    '-x', $outputFile
)
if ($RunOnDevice) {
    $compilerArguments += '--runOnPhone'
}

$temporaryParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$stageName = 'opensesh-android-template-' + [Guid]::NewGuid().ToString('N')
$stageRoot = Join-Path $temporaryParent $stageName
New-Item -ItemType Directory -Path $stageRoot | Out-Null
try {
    $stagedTemplate = Join-Path $stageRoot 'template'
    Copy-Item -LiteralPath $templateSource -Destination $stagedTemplate -Recurse -Force
    $manifestPath = Join-Path $stagedTemplate 'AndroidManifest.xml.in'
    $readerSettings = New-Object System.Xml.XmlReaderSettings
    $readerSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $readerSettings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create($manifestPath, $readerSettings)
    try {
        $manifest = New-Object System.Xml.XmlDocument
        $manifest.PreserveWhitespace = $true
        $manifest.XmlResolver = $null
        $manifest.Load($reader)
    }
    finally {
        $reader.Dispose()
    }
    if ($null -eq $manifest.DocumentElement -or
        $manifest.DocumentElement.Name -ne 'manifest') {
        throw 'Android manifest template must have a manifest document element.'
    }
    $androidNamespace = 'http://schemas.android.com/apk/res/android'
    foreach ($entry in @(
            @('versionName', $versionName),
            @('versionCode', $VersionCode.ToString([Globalization.CultureInfo]::InvariantCulture)))) {
        $attribute = $manifest.CreateAttribute('android', $entry[0], $androidNamespace)
        $attribute.Value = $entry[1]
        [void] $manifest.DocumentElement.Attributes.SetNamedItem($attribute)
    }
    $manifest.Save($manifestPath)

    # This counter is independent of the product's display version. Native
    # forward-slash paths are understood by the wrapper's bundled shell.
    [Environment]::SetEnvironmentVariable('FBANDROID_TEMPLATE',
        $stagedTemplate.Replace('\', '/'), 'Process')
    & $compilerPath @compilerArguments
    $compileExit = $LASTEXITCODE
    if ($compileExit -eq 0 -and
        -not (Test-Path -LiteralPath $outputFile -PathType Leaf)) {
        $compileExit = 1
        Write-Output 'android_apk_missing=1'
    }
}
finally {
    # PowerShell can coerce $null to an empty string for this .NET call. Newer
    # runtimes preserve empty environment values, so explicitly remove an unset
    # override while retaining a caller's existing empty value.
    if ($null -eq $previousTemplate) {
        [Environment]::SetEnvironmentVariable('FBANDROID_TEMPLATE', [NullString]::Value, 'Process')
    }
    else {
        [Environment]::SetEnvironmentVariable('FBANDROID_TEMPLATE', $previousTemplate, 'Process')
    }
    $resolvedStageRoot = [System.IO.Path]::GetFullPath($stageRoot)
    $temporaryBoundary = $temporaryParent.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedStageRoot.StartsWith($temporaryBoundary,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($resolvedStageRoot) -ne $stageName) {
        throw "Refusing to remove an unexpected template staging path: $resolvedStageRoot"
    }
    if (Test-Path -LiteralPath $resolvedStageRoot) {
        Remove-Item -LiteralPath $resolvedStageRoot -Recurse -Force
    }
}

Write-Output ('android_apk=' + $outputFile)
Write-Output ('android_target=' + $Target)
Write-Output ('android_api=' + $ApiLevel)
Write-Output ('android_version_name=' + $versionName)
Write-Output ('android_version_code=' + $VersionCode)
Write-Output ('android_compile_exit=' + $compileExit)
exit $compileExit

# end of build_editor_android.ps1
