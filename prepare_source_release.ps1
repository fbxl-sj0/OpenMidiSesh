<#
    Project: OpenSesh
    ---------------------------

    File: prepare_source_release.ps1

    Purpose:

        Build an explicit source-only archive for the independent MIDI editor.

    Responsibilities:

        - copy only reviewed project source and documentation
        - reject missing release inputs before creating an archive
        - emit canonical forward-slash ZIP entry paths for Linux extraction
        - keep generated binaries, MIDI output, and analysis trees out of the archive

    This file intentionally does NOT contain:

        - recovered Midisoft executables or libraries
        - decompiler output
        - legal advice or a publication approval
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $OutputArchive
)

$ProgressPreference = 'SilentlyContinue'
$projectRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$archivePath = [System.IO.Path]::GetFullPath($OutputArchive)
$releaseFiles = @(
    'CLEAN_ROOM.md',
    'CODE_REVIEW.md',
    'FRONTIER_REVIEW_2026-10-02.md',
    'COPYING',
    'COPYING.LESSER',
    'DEPENDENCIES.md',
    'LICENSE',
    'RELEASE_CHECKLIST.md',
    'README.md',
    'THIRD_PARTY_NOTICES.md',
    '.gitignore',
    'atomic_file_internal.bi',
    'generated_voice_stop_internal.bi',
    'binary_file_internal.bi',
    'tests\binary_file_smoke.bas',
    'capture_paths.bas',
    'capture_paths.bi',
    'numeric_text.bas',
    'numeric_text.bi',
    'build_editor.ps1',
    'build_editor_android.ps1',
    'tests\android_package_metadata_smoke.ps1',
    'build_editor.sh',
    'verify_linux_release_archive.sh',
    'midi_model.bas',
    'midi_model.bi',
    'history_timeline.bas',
    'history_timeline.bi',
    'document_history.bas',
    'document_history.bi',
    'project_transaction.bas',
    'project_transaction.bi',
    'note_selection.bas',
    'note_selection.bi',
    'selected_note_playback.bas',
    'selected_note_playback.bi',
    'score_tools.bas',
    'score_tools.bi',
    'score_controls.bas',
    'score_controls.bi',
    'score_scroll.bas',
    'score_scroll.bi',
    'score_layout.bas',
    'score_layout.bi',
    'mixer_meter.bas',
    'mixer_meter.bi',
    'mixer_controls.bas',
    'mixer_controls.bi',
    'mixer_state.bas',
    'mixer_state.bi',
    'keyboard_controls.bas',
    'keyboard_controls.bi',
    'drum_kit.bas',
    'drum_phrase.bas',
    'drum_phrase.bi',
    'drum_kit.bi',
    'playback_mix.bas',
    'playback_mix.bi',
    'playback_timing.bas',
    'playback_timing.bi',
    'soundfont_bank.bas',
    'soundfont_bank.bi',
    'soundfont_synth.bas',
    'soundfont_synth.bi',
    'software_synth.bas',
    'software_synth.bi',
    'playback_state.bas',
    'playback_state.bi',
    'master_effect.bas',
    'master_effect.bi',
    'sfx_runtime.bas',
    'sfx_runtime.bi',
    'ui_frame_pacing.bas',
    'ui_frame_pacing.bi',
    'ui_style.bas',
    'ui_style.bi',
    'ui_icons.bas',
    'ui_icons.bi',
    'ui_interaction.bas',
    'ui_interaction.bi',
    'touch_gesture.bas',
    'touch_gesture.bi',
    'user_preferences.bas',
    'user_preferences.bi',
    'music_export.bas',
    'music_export.bi',
    'wav_export_sfx.bas',
    'wav_export_sfx.bi',
    'audio_tracks.bas',
    'audio_tracks.bi',
    'audio_sample_slots.bas',
    'audio_sample_slots.bi',
    'midi_alsa.bas',
    'midi_null.bas',
    'midi_input_win.bas',
    'midi_input.bi',
    'midi_input_protocol.bas',
    'midi_input_protocol.bi',
    'midi_output_sfx.bas',
    'midi_output.bi',
    'midi_output_stop_internal.bi',
    'midi_output_setup_internal.bi',
    'tests\midi_output_stop_smoke.bas',
    'pitch_transcriber.bas',
    'pitch_transcriber.bi',
    'music_symbols.bas',
    'music_symbols.bi',
    'version.bi',
    'opensesh.bas',
    'omagui_runtime.bas',
    'opensesh_unity.bas',
    'opensesh.manifest',
    'opensesh.rc',
    'PORTABLE_README.txt',
    'portability_lint_baseline.txt',
    'windows_lint_baseline.txt',
    'prepare_source_release.ps1',
    'prepare_windows_portable_package.ps1',
    'verify_windows_release.ps1',
    'windows_toolchain_lock.json',
    'tests\atomic_file_smoke.bas',
    'tests\capture_paths_smoke.bas',
    'tests\numeric_text_smoke.bas',
    'tests\audio_formats_malformed_smoke.bas',
    'tests\audio_history_smoke.bas',
    'tests\history_timeline_smoke.bas',
    'tests\document_history_smoke.bas',
    'tests\document_endurance_smoke.bas',
    'tests\project_transaction_smoke.bas',
    'tests\empty_document_smoke.bas',
    'tests\midi_history_smoke.bas',
    'tests\midi_model_smoke.bas',
    'tests\midi_model_malformed_smoke.bas',
    'tests\midi_model_fuzz_smoke.bas',
    'tests\midi_running_status_smoke.bas',
    'tests\drum_phrase_smoke.bas',
    'tests\note_selection_smoke.bas',
    'tests\selected_note_playback_smoke.bas',
    'tests\score_tools_smoke.bas',
    'tests\score_controls_smoke.bas',
    'tests\score_scroll_smoke.bas',
    'tests\score_layout_smoke.bas',
    'tests\music_export_smoke.bas',
    'tests\music_symbols_smoke.bas',
    'tests\wav_export_smoke.bas',
    'tests\wav_export_failure_smoke.bas',
    'tests\sfxlib_smoke.bas',
    'tests\soundfont_smoke.bas',
    'tests\soundfont_shutdown_smoke.bas',
    'tests\generated_voice_stop_smoke.bas',
    'tests\soundfont_compatibility.bas',
    'tests\audio_tracks_smoke.bas',
    'tests\audio_sample_slots_smoke.bas',
    'tests\midi_input_smoke.bas',
    'tests\keyboard_controls_smoke.bas',
    'tests\drum_kit_smoke.bas',
    'tests\master_effect_smoke.bas',
    'tests\midi_input_protocol_smoke.bas',
    'tests\mixer_meter_smoke.bas',
    'tests\mixer_controls_smoke.bas',
    'tests\mixer_state_smoke.bas',
    'tests\playback_mix_smoke.bas',
    'tests\playback_state_smoke.bas',
    'tests\playback_timing_smoke.bas',
    'tests\ui_frame_pacing_smoke.bas',
    'tests\ui_style_smoke.bas',
    'tests\ui_icons_smoke.bas',
    'tests\ui_interaction_smoke.bas',
    'tests\touch_gesture_smoke.bas',
    'tests\user_preferences_smoke.bas',
    'tests\version_smoke.bas',
    'tests\midi_loopback_smoke.bas',
    'tests\midi_output_smoke.bas',
    'tests\midi_playback_audio_smoke.bas',
    'tests\playback_endurance_smoke.bas',
    'tests\notation_duration_smoke.bas',
    'tests\pitch_transcriber_smoke.bas',
    'tests\run_visual_regression.ps1',
    'tests\run_android_device_smoke.ps1',
    'tests\run_visual_lifecycle_stress.ps1',
    'tests\run_sfx_runtime_lifecycle_stress.ps1',
    'tests\run_ui_smoothness.ps1',
    'tests\run_ui_smoothness.sh',
    'tests\run_linux_ui_smoke.sh',
    'tests\fbc_sanitized.sh',
    'tests\run_linux_sanitizers.sh',
    'tests\linux_visual_baselines.sha256',
    'tests\verify_dependency_snapshot.ps1',
    'tests\verify_windows_manifest.ps1',
    'tests\verify_windows_binary.ps1',
    'tests\verify_windows_binary_negative.ps1',
    'tests\verify_windows_portable_package.ps1',
    'tests\verify_windows_portable_package_negative.ps1',
    'tests\verify_windows_toolchain.ps1',
    'tests\windows_toolchain_selection_smoke.ps1',
    'tests\run_tests.ps1',
    'tests\run_tests.sh',
    'tests\visual_baselines\about-1280x720.png',
    'tests\visual_baselines\about-black-1280x720.png',
    'tests\visual_baselines\about-dark-1280x720.png',
    'tests\visual_baselines\active-meter-1280x720.png',
    'tests\visual_baselines\audio-1280x720.png',
    'tests\visual_baselines\automation-1280x720.png',
    'tests\visual_baselines\confirm-1280x720.png',
    'tests\visual_baselines\file-open-1280x720.png',
    'tests\visual_baselines\keyboard-1280x720.png',
    'tests\visual_baselines\drums-1280x720.png',
    'tests\visual_baselines\drums-dark-1280x720.png',
    'tests\visual_baselines\drums-black-1280x720.png',
    'tests\visual_baselines\drums-touch-1280x720.png',
    'tests\visual_baselines\drum-machine-1280x720.png',
    'tests\visual_baselines\drum-machine-black-1280x720.png',
    'tests\visual_baselines\drum-machine-dark-1280x720.png',
    'tests\visual_baselines\drum-machine-touch-800x600.png',
    'tests\visual_baselines\drum-starter-800x600.png',
    'tests\visual_baselines\note-tools-800x600.png',
    'tests\visual_baselines\note-tools-dark-1280x720.png',
    'tests\visual_baselines\note-tools-touch-800x600.png',
    'tests\visual_baselines\quick-start-800x600.png',
    'tests\visual_baselines\quick-start-touch-800x600.png',
    'tests\visual_baselines\song-meter-800x600.png',
    'tests\visual_baselines\song-meter-touch-800x600.png',
    'tests\visual_baselines\main-800x600.png',
    'tests\visual_baselines\mixer-last-page-800x600.png',
    'tests\visual_baselines\main-1280x720.png',
    'tests\visual_baselines\main-black-1280x720.png',
    'tests\visual_baselines\main-dark-1280x720.png',
    'tests\visual_baselines\microphone-1280x720.png',
    'tests\visual_baselines\midi-input-1280x720.png',
    'tests\visual_baselines\midi-output-1280x720.png',
    'tests\visual_baselines\midi-save-1280x720.png',
    'tests\visual_baselines\mod-export-1280x720.png',
    'tests\visual_baselines\note-1280x720.png',
    'tests\visual_baselines\options-menu-1280x720.png',
    'tests\visual_baselines\options-menu-black-1280x720.png',
    'tests\visual_baselines\options-menu-dark-1280x720.png',
    'tests\visual_baselines\view-menu-1280x720.png',
    'tests\visual_baselines\palette-1280x720.png',
    'tests\visual_baselines\main-touch-1280x720.png',
    'tests\visual_baselines\main-touch-y-zoom-1280x720.png',
    'tests\visual_baselines\palette-touch-1280x720.png',
    'tests\visual_baselines\options-menu-touch-1280x720.png',
    'tests\visual_baselines\project-save-1280x720.png',
    'tests\visual_baselines\tempo-1280x720.png',
    'tests\visual_baselines\track-1280x720.png',
    'tests\visual_baselines\wav-export-1280x720.png'
)

# The vendored dependency has its own exact payload manifest. Derive archive
# entries from it so the source package cannot silently omit a compiled file
# or include an unreviewed sibling from the larger omaGui development tree.
$vendorMetadataFiles = @(
    'vendor\omaGui\DEPENDENCY.md',
    'vendor\omaGui\SNAPSHOT.sha256'
)
$vendorSnapshotFile = Join-Path $projectRoot `
    'vendor\omaGui\SNAPSHOT.sha256'
if (-not (Test-Path -LiteralPath $vendorSnapshotFile -PathType Leaf)) {
    throw "Vendored omaGui snapshot manifest is missing: $vendorSnapshotFile"
}
$releaseFiles += $vendorMetadataFiles
$vendorLineNumber = 0
foreach ($vendorLine in Get-Content -LiteralPath $vendorSnapshotFile) {
    $vendorLineNumber++
    if ([string]::IsNullOrWhiteSpace($vendorLine) -or
        $vendorLine.StartsWith('#')) {
        continue
    }
    $vendorMatch = [regex]::Match(
        $vendorLine,
        '^[0-9a-f]{64}  ([ -~]+)$')
    if (-not $vendorMatch.Success) {
        throw "Malformed omaGui snapshot line $vendorLineNumber."
    }
    $vendorRelativePath = $vendorMatch.Groups[1].Value
    if ($vendorRelativePath.Contains('\') -or
        $vendorRelativePath.StartsWith('/') -or
        $vendorRelativePath.Contains('//') -or
        $vendorRelativePath.Split('/') -contains '..') {
        throw "Unsafe omaGui snapshot path: $vendorRelativePath"
    }
    $releaseFiles += 'vendor\omaGui\' + `
        $vendorRelativePath.Replace('/', '\')
}

$projectBoundary = $projectRoot.TrimEnd('\') + '\'
$releasePathSet = New-Object 'System.Collections.Generic.HashSet[string]' `
    ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($relativeFile in $releaseFiles) {
    if ([string]::IsNullOrWhiteSpace($relativeFile) -or
        [System.IO.Path]::IsPathRooted($relativeFile) -or
        $relativeFile.Replace('\', '/').Split('/') -contains '..') {
        throw "Unsafe release manifest path: $relativeFile"
    }
    if (-not $releasePathSet.Add($relativeFile.Replace('\', '/'))) {
        throw "Duplicate release manifest path: $relativeFile"
    }

    $sourceFile = [System.IO.Path]::GetFullPath(
        (Join-Path $projectRoot $relativeFile))
    if (-not $sourceFile.StartsWith(
            $projectBoundary,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        throw "Required release file is missing or unsafe: $relativeFile"
    }
}

# Keep the explicit manifest reviewable, but fail when a maintained source,
# test runner, or reviewed image is added without updating that manifest.
$maintainedInputs = @(Get-ChildItem -LiteralPath $projectRoot -File |
    Where-Object { $_.Extension -in @('.bas', '.bi', '.ps1', '.sh') })
$maintainedInputs += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') `
    -File | Where-Object { $_.Extension -in @('.bas', '.bi', '.ps1', '.sh') })
$maintainedInputs += @(Get-ChildItem -LiteralPath `
    (Join-Path $projectRoot 'tests\visual_baselines') -File -Filter '*.png')
foreach ($maintainedInput in $maintainedInputs) {
    $relativeInput = $maintainedInput.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
    if (-not $releasePathSet.Contains($relativeInput)) {
        throw "Maintained source or test is missing from the release manifest: $relativeInput"
    }
}

if ([System.StringComparer]::OrdinalIgnoreCase.Equals($archivePath, $projectRoot)) {
    throw 'The output archive path must not be the project directory.'
}
if ([System.IO.Path]::GetExtension($archivePath) -ne '.zip') {
    throw 'The source archive must use a .zip filename.'
}

$parentDirectory = Split-Path -Parent $archivePath
if (-not (Test-Path -LiteralPath $parentDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
}
if (Test-Path -LiteralPath $archivePath) {
    throw "Refusing to overwrite an existing archive: $archivePath"
}

$temporaryArchive = Join-Path $parentDirectory `
    ('.opensesh-source-' + [System.Guid]::NewGuid().ToString('N') +
        '.tmp.zip')
$zipArchive = $null

try {
    <#
        Compress-Archive records backslashes when it receives Windows paths.
        Some Linux unzip tools extract those archives but still return failure.
        Create every entry with a canonical ZIP path so extraction is quiet and
        deterministic on both supported hosts.
    #>
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipArchive = [System.IO.Compression.ZipFile]::Open(
        $temporaryArchive,
        [System.IO.Compression.ZipArchiveMode]::Create)
    foreach ($relativeFile in $releaseFiles) {
        $sourceFile = [System.IO.Path]::GetFullPath(
            (Join-Path $projectRoot $relativeFile))
        $entryName = 'opensesh/' + $relativeFile.Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zipArchive,
            $sourceFile,
            $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
    $zipArchive.Dispose()
    $zipArchive = $null

    if (-not (Test-Path -LiteralPath $temporaryArchive -PathType Leaf) -or
        (Get-Item -LiteralPath $temporaryArchive).Length -le 0) {
        throw 'The temporary source archive was not created.'
    }
    Move-Item -LiteralPath $temporaryArchive -Destination $archivePath
    Write-Output ('source_archive=' + $archivePath)
    Write-Output ('source_files=' + $releaseFiles.Count)
}
finally {
    if ($null -ne $zipArchive) {
        $zipArchive.Dispose()
    }
    if (Test-Path -LiteralPath $temporaryArchive -PathType Leaf) {
        $resolvedTemporaryArchive = [System.IO.Path]::GetFullPath(
            $temporaryArchive)
        $temporaryParent = Split-Path -Parent $resolvedTemporaryArchive
        $temporaryLeaf = Split-Path -Leaf $resolvedTemporaryArchive
        if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(
                $temporaryParent,
                [System.IO.Path]::GetFullPath($parentDirectory)) -or
            $temporaryLeaf -notmatch '^\.opensesh-source-[0-9a-f]{32}\.tmp\.zip$') {
            throw "Refusing to remove an unexpected temporary archive: $resolvedTemporaryArchive"
        }
        Remove-Item -LiteralPath $resolvedTemporaryArchive -Force
    }
}

# end of prepare_source_release.ps1
