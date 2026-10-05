<#
    Project: OpenSesh
    ----------------------------

    File: tests/run_tests.ps1

    Purpose:

        Build and run the complete deterministic FreeBASIC test suite from
        current source instead of relying on checked-out executable files.

    Responsibilities:

        - validate the compiler, project sources, and omaGui include tree
        - build every automated test with its real source dependencies
        - keep generated fixtures outside the source tree by default
        - report every failure and return a nonzero process exit code
        - optionally run the physical or virtual MIDI loopback test
        - gate measured native UI frame pacing on Windows

    This file intentionally does NOT contain:

        - dependency installation
        - assumptions about installed MIDI device indices
        - unscripted human usability approval
        - cleanup of user-owned files
#>

[CmdletBinding()]
param(
    [string] $FreeBasicPath = 'C:\FreeBASIC\fbc.exe',
    [string] $OmaGuiPath = '',
    [string] $BuildDirectory = '',
    [switch] $IncludeMidiLoopback,
    [int] $MidiInputIndex = -1,
    [int] $MidiOutputIndex = -1,
    [ValidateRange(1, 3600)]
    [int] $TestTimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if ([string]::IsNullOrWhiteSpace($OmaGuiPath)) {
    $OmaGuiPath = Join-Path $projectRoot 'vendor\omaGui'
}
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path ([System.IO.Path]::GetTempPath()) `
        ('opensesh-tests-' + $PID)
}

$compilerPath = [System.IO.Path]::GetFullPath($FreeBasicPath)
$omaGuiRoot = [System.IO.Path]::GetFullPath($OmaGuiPath)
$buildRoot = [System.IO.Path]::GetFullPath($BuildDirectory)

if (-not (Test-Path -LiteralPath $compilerPath -PathType Leaf)) {
    throw "FreeBASIC compiler was not found: $compilerPath"
}
if (-not (Test-Path -LiteralPath $omaGuiRoot -PathType Container)) {
    throw "omaGui include tree was not found: $omaGuiRoot"
}
if ($IncludeMidiLoopback -and
    ($MidiInputIndex -lt 0 -or $MidiOutputIndex -lt 0)) {
    throw 'MIDI loopback requires nonnegative input and output indices.'
}

New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null

function Invoke-BoundedTest {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Executable,
        [string[]] $Arguments = @(),
        [Parameter(Mandatory = $true)]
        [string] $TestName
    )

    # Windows PowerShell's Start-Process wrapper can expose a blank ExitCode
    # after redirected execution. A direct Process object retains the native
    # status while allowing test output to inherit the runner's console.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false
    if ($TestName -eq 'generated_voice_stop_smoke') {
        $startInfo.EnvironmentVariables['SFXLIB_DRIVER'] = 'null'
    }
    if ($Arguments.Count -gt 0) {
        # Current test arguments are paths or decimal device indices. Quoting
        # each value preserves caller-selected paths with spaces.
        $startInfo.Arguments = (@($Arguments | ForEach-Object {
            '"' + ([string] $_).Replace('"', '\"') + '"'
        }) -join ' ')
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $runExit = 124

    try {
        if (-not $process.Start()) {
            [Console]::Error.WriteLine("FAIL $TestName could not be started.")
            return 125
        }
        if (-not $process.WaitForExit($TestTimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            [Console]::Error.WriteLine(
                "TIMEOUT $TestName exceeded $TestTimeoutSeconds seconds.")
        }
        else {
            $runExit = $process.ExitCode
        }
    }
    finally {
        $process.Dispose()
    }

    return $runExit
}

$tests = @(
    [pscustomobject]@{
        Name = 'omagui_safety_smoke'
        Sources = @('tests\omagui_safety_smoke.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'atomic_file_smoke'
        Sources = @('tests\atomic_file_smoke.bas')
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'atomic-file-smoke.bin'))
    },
    [pscustomobject]@{
        Name = 'capture_paths_smoke'
        Sources = @('tests\capture_paths_smoke.bas', 'src\capture_paths.bas')
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'capture-paths-fixtures'))
    },
    [pscustomobject]@{
        Name = 'numeric_text_smoke'
        Sources = @('tests\numeric_text_smoke.bas', 'src\numeric_text.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'audio_formats_malformed_smoke'
        Sources = @(
            'tests\audio_formats_malformed_smoke.bas',
            'src\audio_tracks.bas'
        )
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'audio-formats-malformed'))
    },
    [pscustomobject]@{
        Name = 'audio_tracks_smoke'
        Sources = @('tests\audio_tracks_smoke.bas', 'src\audio_tracks.bas')
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'audio-tracks-smoke.ose'))
    },
    [pscustomobject]@{
        Name = 'audio_sample_slots_smoke'
        Sources = @(
            'tests\audio_sample_slots_smoke.bas',
            'src\audio_sample_slots.bas',
            'src\audio_tracks.bas',
            'src\wav_export_sfx.bas',
            'src\sfx_runtime.bas'
        )
        Defines = @()
        Arguments = @(
            (Join-Path $buildRoot 'audio-sample-slots-low.wav'),
            (Join-Path $buildRoot 'audio-sample-slots-high.wav'),
            (Join-Path $buildRoot 'audio-sample-slots-output.wav')
        )
    },
    [pscustomobject]@{
        Name = 'audio_history_smoke'
        Sources = @('tests\audio_history_smoke.bas', 'src\audio_tracks.bas')
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'audio-history-smoke.wav'))
    },
    [pscustomobject]@{
        Name = 'history_timeline_smoke'
        Sources = @('tests\history_timeline_smoke.bas', 'src\history_timeline.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'document_history_smoke'
        Sources = @(
            'tests\document_history_smoke.bas',
            'src\document_history.bas',
            'src\history_timeline.bas',
            'src\midi_model.bas',
            'src\audio_tracks.bas'
        )
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'document-history-smoke.wav'))
    },
    [pscustomobject]@{
        Name = 'document_endurance_smoke'
        Sources = @(
            'tests\document_endurance_smoke.bas',
            'src\document_history.bas',
            'src\history_timeline.bas',
            'src\midi_model.bas',
            'src\audio_tracks.bas'
        )
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'document-endurance-smoke.wav'))
    },
    [pscustomobject]@{
        Name = 'project_transaction_smoke'
        Sources = @(
            'tests\project_transaction_smoke.bas',
            'src\project_transaction.bas',
            'src\numeric_text.bas'
        )
        Defines = @('OSE_PROJECT_TRANSACTION_TESTING')
        Arguments = @((Join-Path $buildRoot 'project-transaction-smoke'))
    },
    [pscustomobject]@{
        Name = 'empty_document_smoke'
        Sources = @('tests\empty_document_smoke.bas', 'src\midi_model.bas')
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'empty-document-smoke.mid'))
    },
    [pscustomobject]@{
        Name = 'midi_input_smoke'
        Sources = @(
            'tests\midi_input_smoke.bas',
            'src\midi_input_win.bas',
            'src\midi_input_protocol.bas'
        )
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'keyboard_controls_smoke'
        Sources = @('tests\keyboard_controls_smoke.bas', 'src\keyboard_controls.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'drum_kit_smoke'
        Sources = @('tests\drum_kit_smoke.bas', 'src\drum_kit.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'drum_phrase_smoke'
        Sources = @('tests\drum_phrase_smoke.bas', 'src\drum_phrase.bas', 'src\drum_kit.bas', 'src\midi_model.bas')
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'drum-phrase-smoke.mid'))
    },
    [pscustomobject]@{
        Name = 'master_effect_smoke'
        Sources = @(
            'tests\master_effect_smoke.bas',
            'src\master_effect.bas',
            'src\sfx_runtime.bas'
        )
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'midi_input_protocol_smoke'
        Sources = @(
            'tests\midi_input_protocol_smoke.bas',
            'src\midi_input_protocol.bas'
        )
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'mixer_meter_smoke'
        Sources = @('tests\mixer_meter_smoke.bas', 'src\mixer_meter.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'mixer_controls_smoke'
        Sources = @(
            'tests\mixer_controls_smoke.bas',
            'src\mixer_controls.bas',
            'src\ui_interaction.bas'
        )
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'mixer_state_smoke'
        Sources = @('tests\mixer_state_smoke.bas', 'src\mixer_state.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'midi_model_smoke'
        Sources = @('tests\midi_model_smoke.bas', 'src\midi_model.bas')
        Defines = @()
        Arguments = @(
            (Join-Path $buildRoot 'empty-document-smoke.mid'),
            (Join-Path $buildRoot 'midi-model-roundtrip.mid')
        )
    },
    [pscustomobject]@{
        Name = 'midi_history_smoke'
        Sources = @('tests\midi_history_smoke.bas', 'src\midi_model.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'midi_model_malformed_smoke'
        Sources = @(
            'tests\midi_model_malformed_smoke.bas',
            'src\midi_model.bas'
        )
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'midi-model-malformed.mid'))
    },
    [pscustomobject]@{
        Name = 'midi_model_fuzz_smoke'
        Sources = @(
            'tests\midi_model_fuzz_smoke.bas',
            'src\midi_model.bas'
        )
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'midi-model-fuzz'))
    },
    [pscustomobject]@{
        Name = 'document_save_routing_smoke'
        Sources = @('tests\document_save_routing_smoke.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'midi_output_smoke'
        Sources = @('tests\midi_output_smoke.bas', 'src\midi_output_sfx.bas')
        Defines = @('OSE_MIDI_OUTPUT_TESTING')
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'midi_playback_audio_smoke'
        Sources = @(
            'tests\midi_playback_audio_smoke.bas',
            'src\midi_model.bas',
            'src\audio_tracks.bas',
            'src\wav_export_sfx.bas',
            'src\playback_mix.bas',
            'src\playback_timing.bas',
            'src\soundfont_bank.bas',
            'src\soundfont_synth.bas',
            'src\software_synth.bas',
            'src\mixer_state.bas',
            'src\sfx_runtime.bas'
        )
        Defines = @()
        Arguments = @(
            (Join-Path $buildRoot 'midi-playback-audio-smoke.mid'),
            (Join-Path $buildRoot 'midi-playback-audio-smoke.wav')
        )
    },
    [pscustomobject]@{
        Name = 'playback_endurance_smoke'
        Sources = @(
            'tests\playback_endurance_smoke.bas',
            'src\audio_tracks.bas',
            'src\wav_export_sfx.bas',
            'src\playback_mix.bas',
            'src\soundfont_bank.bas',
            'src\soundfont_synth.bas',
            'src\software_synth.bas',
            'src\sfx_runtime.bas'
        )
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'playback-endurance-smoke.wav'))
    },
    [pscustomobject]@{
        Name = 'music_export_smoke'
        Sources = @(
            'tests\music_export_smoke.bas',
            'src\midi_model.bas',
            'src\music_export.bas'
        )
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'music-export-smoke.mod'))
    },
    [pscustomobject]@{
        Name = 'music_symbols_smoke'
        Sources = @(
            'tests\music_symbols_smoke.bas',
            'src\music_symbols.bas',
            'src\numeric_text.bas'
        )
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'music-screen-glyphs.mask'))
    },
    [pscustomobject]@{
        Name = 'notation_duration_smoke'
        Sources = @('tests\notation_duration_smoke.bas', 'src\midi_model.bas')
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'notation-duration-smoke.mid'))
    },
    [pscustomobject]@{
        Name = 'note_selection_smoke'
        Sources = @(
            'tests\note_selection_smoke.bas',
            'src\note_selection.bas',
            'src\midi_model.bas'
        )
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'selected_note_playback_smoke'
        Sources = @(
            'tests\selected_note_playback_smoke.bas',
            'src\selected_note_playback.bas',
            'src\note_selection.bas',
            'src\midi_model.bas',
            'src\playback_timing.bas'
        )
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'pitch_transcriber_smoke'
        Sources = @(
            'tests\pitch_transcriber_smoke.bas',
            'src\pitch_transcriber.bas'
        )
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'pitch-transcriber-smoke.wav'))
    },
    [pscustomobject]@{
        Name = 'playback_mix_smoke'
        Sources = @('tests\playback_mix_smoke.bas', 'src\playback_mix.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'playback_state_smoke'
        Sources = @('tests\playback_state_smoke.bas', 'src\playback_state.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'playback_timing_smoke'
        Sources = @('tests\playback_timing_smoke.bas', 'src\playback_timing.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'ui_frame_pacing_smoke'
        Sources = @('tests\ui_frame_pacing_smoke.bas', 'src\ui_frame_pacing.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'score_controls_smoke'
        Sources = @(
            'tests\score_controls_smoke.bas',
            'src\score_controls.bas',
            'src\ui_interaction.bas'
        )
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'score_layout_smoke'
        Sources = @('tests\score_layout_smoke.bas', 'src\score_layout.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'score_scroll_smoke'
        Sources = @('tests\score_scroll_smoke.bas', 'src\score_scroll.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'score_tools_smoke'
        Sources = @('tests\score_tools_smoke.bas', 'src\score_tools.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'sfxlib_smoke'
        Sources = @('tests\sfxlib_smoke.bas', 'src\sfx_runtime.bas')
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'sfxlib-capture-smoke.wav'))
    },
    [pscustomobject]@{
        Name = 'midi_running_status_smoke'
        Sources = @('tests\midi_running_status_smoke.bas', 'src\midi_model.bas')
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'midi-running-status.mid'))
    },
    [pscustomobject]@{
        Name = 'midi_output_stop_smoke'
        Sources = @('tests\midi_output_stop_smoke.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'soundfont_shutdown_smoke'
        Sources = @('tests\soundfont_shutdown_smoke.bas', 'src\soundfont_synth.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'generated_voice_stop_smoke'
        Sources = @('tests\generated_voice_stop_smoke.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'soundfont_smoke'
        Sources = @(
            'tests\soundfont_smoke.bas',
            'src\soundfont_bank.bas',
            'src\soundfont_synth.bas',
            'src\playback_mix.bas',
            'src\sfx_runtime.bas'
        )
        Defines = @()
        Arguments = @(
            (Join-Path $buildRoot 'soundfont-smoke.sf2'),
            (Join-Path $buildRoot 'soundfont-malformed.sf2'),
            (Join-Path $buildRoot 'soundfont-smoke.result')
        )
    },
    [pscustomobject]@{
        Name = 'touch_gesture_smoke'
        Sources = @('tests\touch_gesture_smoke.bas', 'src\touch_gesture.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'ui_interaction_smoke'
        Sources = @('tests\ui_interaction_smoke.bas', 'src\ui_interaction.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'ui_style_smoke'
        Sources = @('tests\ui_style_smoke.bas', 'src\ui_style.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'ui_icons_smoke'
        Sources = @('tests\ui_icons_smoke.bas', 'src\ui_icons.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'user_preferences_smoke'
        Sources = @(
            'tests\user_preferences_smoke.bas',
            'src\user_preferences.bas',
            'src\ui_interaction.bas'
        )
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'user-preferences-smoke.conf'))
    },
    [pscustomobject]@{
        Name = 'version_smoke'
        Sources = @('tests\version_smoke.bas')
        Defines = @()
        Arguments = @()
    },
    [pscustomobject]@{
        Name = 'wav_export_smoke'
        Sources = @(
            'tests\wav_export_smoke.bas',
            'src\audio_tracks.bas',
            'src\wav_export_sfx.bas'
        )
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'wav-export-smoke.wav'))
    },
    [pscustomobject]@{
        Name = 'binary_file_smoke'
        Sources = @('tests\binary_file_smoke.bas')
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'binary-file-smoke.bin'))
    },
    [pscustomobject]@{
        Name = 'wav_export_failure_smoke'
        Sources = @('tests\wav_export_failure_smoke.bas', 'src\wav_export_sfx.bas')
        Defines = @()
        Arguments = @((Join-Path $buildRoot 'wav-export-failure.wav'))
    }
)

if ($IncludeMidiLoopback) {
    $tests += [pscustomobject]@{
        Name = 'midi_loopback_smoke'
        Sources = @(
            'tests\midi_loopback_smoke.bas',
            'src\midi_input_win.bas',
            'src\midi_input_protocol.bas',
            'src\midi_output_sfx.bas'
        )
        Defines = @()
        Arguments = @([string] $MidiInputIndex, [string] $MidiOutputIndex)
    }
}

$failedTests = [System.Collections.Generic.List[string]]::new()
$passedTests = 0

# A source release must compile the exact reviewed GUI dependency, not whatever
# happens to be installed beside the project on one build host.
$dependencySnapshotName = 'dependency_snapshot_smoke'
Write-Output ("RUN   " + $dependencySnapshotName)
try {
    & (Join-Path $projectRoot 'tests\verify_dependency_snapshot.ps1') `
        -OmaGuiPath $omaGuiRoot
    $passedTests++
    Write-Output ("PASS  " + $dependencySnapshotName)
}
catch {
    $failedTests.Add($dependencySnapshotName + ' (run)')
    Write-Output ("FAIL  " + $dependencySnapshotName + " " + `
        $_.Exception.Message)
}

# Release tests use an exact compiler and static-library identity. A different
# toolchain can still be evaluated deliberately by updating the reviewed lock.
$windowsToolchainName = 'windows_toolchain_smoke'
Write-Output ("RUN   " + $windowsToolchainName)
try {
    & (Join-Path $projectRoot 'tests\verify_windows_toolchain.ps1') `
        -FreeBasicPath $compilerPath
    $passedTests++
    Write-Output ("PASS  " + $windowsToolchainName)
}
catch {
    $failedTests.Add($windowsToolchainName + ' (run)')
    Write-Output ("FAIL  " + $windowsToolchainName + " " + `
        $_.Exception.Message)
}

foreach ($test in $tests) {
    $outputFile = Join-Path $buildRoot ($test.Name + '.exe')
    # Test programs which link the SoundFont worker must use one consistent
    # thread-safe runtime across every translated source module.
    $compilerArguments = @('-i', $omaGuiRoot, '-mt', '-w', 'all')

    foreach ($define in $test.Defines) {
        $compilerArguments += @('-d', $define)
    }
    foreach ($relativeSource in $test.Sources) {
        $sourcePath = Join-Path $projectRoot $relativeSource
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Required test source was not found: $sourcePath"
        }
        $compilerArguments += $sourcePath
    }
    $compilerArguments += @('-x', $outputFile)

    Write-Output ("BUILD " + $test.Name)
    $compilerOutput = @(& $compilerPath @compilerArguments 2>&1)
    $compileExit = $LASTEXITCODE
    $compilerOutput | ForEach-Object { Write-Output $_ }
    if (@($compilerOutput | Where-Object {
        [string] $_ -match '(?i)\bwarning\s+\d+'
    }).Count -gt 0) { $compileExit = 1 }
    if ($compileExit -ne 0) {
        $failedTests.Add($test.Name + ' (compile)')
        Write-Output ("FAIL  " + $test.Name + " compile_exit=" + $compileExit)
        continue
    }

    Write-Output ("RUN   " + $test.Name)
    $runExit = Invoke-BoundedTest -Executable $outputFile `
        -Arguments @($test.Arguments) -TestName $test.Name
    if ($runExit -ne 0) {
        $failedTests.Add($test.Name + ' (run)')
        Write-Output ("FAIL  " + $test.Name + " run_exit=" + $runExit)
        continue
    }

    $passedTests++
    Write-Output ("PASS  " + $test.Name)
}

# The default Windows sound backend has its own process-lifecycle gate. This
# keeps audio worker teardown coverage independent from the null-driver GUI
# lifecycle stress below, so a failure identifies the responsible subsystem.
$sfxLifecycleName = 'sfx_runtime_lifecycle_stress'
Write-Output ("RUN   " + $sfxLifecycleName)
try {
    $masterEffectExecutable = Join-Path $buildRoot 'master_effect_smoke.exe'
    if (-not (Test-Path -LiteralPath $masterEffectExecutable -PathType Leaf)) {
        throw 'The effect executable required for sound lifecycle stress is missing.'
    }
    & (Join-Path $projectRoot 'tests\run_sfx_runtime_lifecycle_stress.ps1') `
        -ExecutablePath $masterEffectExecutable `
        -LaunchCount 25 `
        -ProcessTimeoutSeconds 10
    $passedTests++
    Write-Output ("PASS  " + $sfxLifecycleName)
}
catch {
    $failedTests.Add($sfxLifecycleName + ' (run)')
    Write-Output ("FAIL  " + $sfxLifecycleName + " " + `
        $_.Exception.Message)
}

# The application-level contract audit inspects the actual omaGUI widgets
# after construction. It complements the pure style and behavior tests by
# proving exact handlers for every toolbar, menu, and generated dialog action.
$uiContractName = 'ui_widget_contract_smoke'
$uiContractExecutable = Join-Path $buildRoot ($uiContractName + '.exe')
$uiContractReport = Join-Path $buildRoot ($uiContractName + '.txt')
Write-Output ("BUILD " + $uiContractName)
& (Join-Path $projectRoot 'build_editor.ps1') `
    -FreeBasicPath $compilerPath `
    -OmaGuiPath $omaGuiRoot `
    -OutputPath $uiContractExecutable
$uiCompileExit = $LASTEXITCODE
if ($uiCompileExit -ne 0) {
    $failedTests.Add($uiContractName + ' (compile)')
    Write-Output ("FAIL  " + $uiContractName + " compile_exit=" + $uiCompileExit)
}
else {
    Write-Output ("RUN   " + $uiContractName)
    $previousReportValue = $env:OSE_TEST_CONTROL_REPORT
    $previousAudioFixtureValue = $env:OSE_TEST_AUDIO_FIXTURE
    $previousPreferencesValue = $env:OSE_TEST_PREFERENCES_FILE
    try {
        $uiAudioFixture = Join-Path $buildRoot 'audio-tracks-smoke.ose.wav'
        if (-not (Test-Path -LiteralPath $uiAudioFixture -PathType Leaf)) {
            throw 'The PCM WAV fixture required by the UI audit is missing.'
        }
        $env:OSE_TEST_CONTROL_REPORT = $uiContractReport
        $env:OSE_TEST_AUDIO_FIXTURE = $uiAudioFixture
        $uiPreferencesFile = Join-Path $buildRoot 'ui-theme-preferences.conf'
        [System.IO.File]::WriteAllText(
            $uiPreferencesFile,
            "format=OpenSeshPreferences`nversion=1`ntheme=dark`n")
        $env:OSE_TEST_PREFERENCES_FILE = $uiPreferencesFile
        $uiFixtureArgument = '"' + `
            (Join-Path $buildRoot 'empty-document-smoke.mid').Replace('"', '\"') + `
            '"'
        $uiProcess = Start-Process `
            -FilePath $uiContractExecutable `
            -ArgumentList $uiFixtureArgument `
            -WindowStyle Hidden `
            -PassThru
        if (-not $uiProcess.WaitForExit($TestTimeoutSeconds * 1000)) {
            Stop-Process -Id $uiProcess.Id -Force
            throw ("UI control contract process exceeded its " +
                "$TestTimeoutSeconds-second bound.")
        }
        if ($uiProcess.ExitCode -ne 0) {
            throw "UI control contract process exited with $($uiProcess.ExitCode)."
        }
        if (-not (Test-Path -LiteralPath $uiContractReport -PathType Leaf)) {
            throw 'UI control contract report was not created.'
        }
        $uiReportText = Get-Content -LiteralPath $uiContractReport -Raw
        $requiredReportLines = @(
            'status=ok',
            'widget_actions=117',
            'text_controls=29',
            'list_controls=5',
            'scroll_controls=2',
            'custom_controls=171',
            'behavior_checks=508',
            'startup_theme=Dark',
            'startup_interaction=Desktop',
            'persisted_theme=Dark',
            'persisted_interaction=Desktop',
            'total_controls=324'
        )
        foreach ($requiredLine in $requiredReportLines) {
            if ($uiReportText -notmatch [regex]::Escape($requiredLine)) {
                throw "UI control report is missing: $requiredLine"
            }
        }
        $versionInfo = (Get-Item -LiteralPath $uiContractExecutable).VersionInfo
        if ($versionInfo.FileVersion -ne '0.9.0-dev' -or
            $versionInfo.ProductVersion -ne '0.9.0-dev' -or
            $versionInfo.ProductName -ne 'OpenSesh') {
            throw 'Windows executable version metadata is missing or inconsistent.'
        }
        $passedTests++
        Write-Output $uiReportText.TrimEnd()
        Write-Output ("PASS  " + $uiContractName)
    }
    catch {
        $failedTests.Add($uiContractName + ' (run)')
        Write-Output ("FAIL  " + $uiContractName + " " + $_.Exception.Message)
    }
    finally {
        if ($null -eq $previousReportValue) {
            Remove-Item Env:OSE_TEST_CONTROL_REPORT -ErrorAction SilentlyContinue
        }
        else {
            $env:OSE_TEST_CONTROL_REPORT = $previousReportValue
        }
        if ($null -eq $previousAudioFixtureValue) {
            Remove-Item Env:OSE_TEST_AUDIO_FIXTURE -ErrorAction SilentlyContinue
        }
        else {
            $env:OSE_TEST_AUDIO_FIXTURE = $previousAudioFixtureValue
        }
        if ($null -eq $previousPreferencesValue) {
            Remove-Item Env:OSE_TEST_PREFERENCES_FILE -ErrorAction SilentlyContinue
        }
        else {
            $env:OSE_TEST_PREFERENCES_FILE = $previousPreferencesValue
        }
    }
}

# Repeat the application contract under the coarse-pointer profile. The same
# editor executable must preserve every command while paging the wider mixer
# strips and using larger score, toolbar, scrollbar, and menu targets.
$uiTouchContractName = 'ui_touch_contract_smoke'
$uiTouchContractReport = Join-Path $buildRoot `
    ($uiTouchContractName + '.txt')
Write-Output ("RUN   " + $uiTouchContractName)
$previousReportValue = $env:OSE_TEST_CONTROL_REPORT
$previousAudioFixtureValue = $env:OSE_TEST_AUDIO_FIXTURE
$previousPreferencesValue = $env:OSE_TEST_PREFERENCES_FILE
$previousDefaultInteractionValue = $env:OSE_DEFAULT_INTERACTION_MODE
try {
    $uiAudioFixture = Join-Path $buildRoot 'audio-tracks-smoke.ose.wav'
    $uiTouchPreferencesFile = Join-Path $buildRoot `
        'ui-touch-preferences.conf'
    Remove-Item -LiteralPath $uiTouchPreferencesFile `
        -ErrorAction SilentlyContinue
    $env:OSE_TEST_CONTROL_REPORT = $uiTouchContractReport
    $env:OSE_TEST_AUDIO_FIXTURE = $uiAudioFixture
    $env:OSE_TEST_PREFERENCES_FILE = $uiTouchPreferencesFile
    $env:OSE_DEFAULT_INTERACTION_MODE = 'touch'
    $uiFixtureArgument = '"' + `
        (Join-Path $buildRoot 'empty-document-smoke.mid').Replace('"', '\"') + `
        '"'
    $uiProcess = Start-Process `
        -FilePath $uiContractExecutable `
        -ArgumentList $uiFixtureArgument `
        -WindowStyle Hidden `
        -PassThru
    if (-not $uiProcess.WaitForExit($TestTimeoutSeconds * 1000)) {
        Stop-Process -Id $uiProcess.Id -Force
        throw ("Touch UI contract process exceeded its " +
            "$TestTimeoutSeconds-second bound.")
    }
    if ($uiProcess.ExitCode -ne 0) {
        throw "Touch UI contract process exited with $($uiProcess.ExitCode)."
    }
    if (-not (Test-Path -LiteralPath $uiTouchContractReport -PathType Leaf)) {
        throw 'Touch UI control contract report was not created.'
    }
    $uiTouchReportText = Get-Content `
        -LiteralPath $uiTouchContractReport -Raw
    foreach ($requiredLine in @(
            'status=ok',
            'widget_actions=117',
            'text_controls=29',
            'list_controls=5',
            'scroll_controls=2',
            'custom_controls=171',
            'behavior_checks=508',
            'startup_theme=Light',
            'startup_interaction=Touch',
            'persisted_theme=Light',
            'persisted_interaction=Touch',
            'total_controls=324')) {
        if ($uiTouchReportText -notmatch [regex]::Escape($requiredLine)) {
            throw "Touch UI control report is missing: $requiredLine"
        }
    }
    $passedTests++
    Write-Output $uiTouchReportText.TrimEnd()
    Write-Output ("PASS  " + $uiTouchContractName)
}
catch {
    $failedTests.Add($uiTouchContractName + ' (run)')
    Write-Output ("FAIL  " + $uiTouchContractName + " " + `
        $_.Exception.Message)
}
finally {
    if ($null -eq $previousReportValue) {
        Remove-Item Env:OSE_TEST_CONTROL_REPORT -ErrorAction SilentlyContinue
    }
    else {
        $env:OSE_TEST_CONTROL_REPORT = $previousReportValue
    }
    if ($null -eq $previousAudioFixtureValue) {
        Remove-Item Env:OSE_TEST_AUDIO_FIXTURE -ErrorAction SilentlyContinue
    }
    else {
        $env:OSE_TEST_AUDIO_FIXTURE = $previousAudioFixtureValue
    }
    if ($null -eq $previousPreferencesValue) {
        Remove-Item Env:OSE_TEST_PREFERENCES_FILE -ErrorAction SilentlyContinue
    }
    else {
        $env:OSE_TEST_PREFERENCES_FILE = $previousPreferencesValue
    }
    if ($null -eq $previousDefaultInteractionValue) {
        Remove-Item Env:OSE_DEFAULT_INTERACTION_MODE `
            -ErrorAction SilentlyContinue
    }
    else {
        $env:OSE_DEFAULT_INTERACTION_MODE = $previousDefaultInteractionValue
    }
}

# Smoothness uses the production editor, production input handlers, and a
# shipping-size 2,048-note workload. The runner validates both the timing
# contract and the fact that scrolling, dragging, playback, and VU meters moved.
$uiSmoothnessName = 'ui_smoothness_smoke'
Write-Output ("RUN   " + $uiSmoothnessName)
try {
    if (-not (Test-Path -LiteralPath $uiContractExecutable -PathType Leaf)) {
        throw 'The editor executable required for smoothness testing is missing.'
    }
    & (Join-Path $projectRoot 'tests\run_ui_smoothness.ps1') `
        -EditorPath $uiContractExecutable `
        -BuildDirectory (Join-Path $buildRoot 'smoothness') `
        -FrameCount 480 `
        -ProcessTimeoutSeconds $TestTimeoutSeconds
    $passedTests++
    Write-Output ("PASS  " + $uiSmoothnessName)
}
catch {
    $failedTests.Add($uiSmoothnessName + ' (run)')
    Write-Output ("FAIL  " + $uiSmoothnessName + " " + `
        $_.Exception.Message)
}

# The process loader consumes the manifest before application code runs. Read
# the RT_MANIFEST bytes back from the completed executable so a resource build
# omission cannot silently change privileges or DPI behavior.
$windowsManifestName = 'windows_manifest_smoke'
Write-Output ("RUN   " + $windowsManifestName)
try {
    if (-not (Test-Path -LiteralPath $uiContractExecutable -PathType Leaf)) {
        throw 'The editor executable required for manifest inspection is missing.'
    }
    & (Join-Path $projectRoot 'tests\verify_windows_manifest.ps1') `
        -ExecutablePath $uiContractExecutable
    $passedTests++
    Write-Output ("PASS  " + $windowsManifestName)
}
catch {
    $failedTests.Add($windowsManifestName + ' (run)')
    Write-Output ("FAIL  " + $windowsManifestName + " " + `
        $_.Exception.Message)
}

# Reviewed framebuffers cover the code-drawn surfaces and generated widgets.
# Reuse the editor and MIDI fixture already built above so visual coverage adds
# capture time without another full application compile.
$visualRegressionName = 'visual_regression_smoke'
Write-Output ("RUN   " + $visualRegressionName)
try {
    if (-not (Test-Path -LiteralPath $uiContractExecutable -PathType Leaf)) {
        throw 'The editor executable required for visual capture is missing.'
    }
    $visualFixture = Join-Path $buildRoot 'empty-document-smoke.mid'
    if (-not (Test-Path -LiteralPath $visualFixture -PathType Leaf)) {
        throw 'The MIDI fixture required for visual capture is missing.'
    }

    & (Join-Path $projectRoot 'tests\run_visual_regression.ps1') `
        -FreeBasicPath $compilerPath `
        -OmaGuiPath $omaGuiRoot `
        -BuildDirectory $buildRoot `
        -EditorPath $uiContractExecutable `
        -FixturePath $visualFixture `
        -CaptureTimeoutSeconds $TestTimeoutSeconds
    $passedTests++
    Write-Output ("PASS  " + $visualRegressionName)
}
catch {
    $failedTests.Add($visualRegressionName + ' (run)')
    Write-Output ("FAIL  " + $visualRegressionName + " " + `
        $_.Exception.Message)
}

# Every visual case starts a fresh process, but a dedicated longer sequence
# makes display-driver teardown regressions reproducible without multiplying
# the reviewed framebuffer baseline set.
$visualLifecycleName = 'visual_lifecycle_stress'
Write-Output ("RUN   " + $visualLifecycleName)
try {
    if (-not (Test-Path -LiteralPath $uiContractExecutable -PathType Leaf)) {
        throw 'The editor executable required for lifecycle stress is missing.'
    }
    $visualFixture = Join-Path $buildRoot 'empty-document-smoke.mid'
    if (-not (Test-Path -LiteralPath $visualFixture -PathType Leaf)) {
        throw 'The MIDI fixture required for lifecycle stress is missing.'
    }

    & (Join-Path $projectRoot 'tests\run_visual_lifecycle_stress.ps1') `
        -EditorPath $uiContractExecutable `
        -FixturePath $visualFixture `
        -BuildDirectory $buildRoot `
        -LaunchCount 60 `
        -ProcessTimeoutSeconds 10
    $passedTests++
    Write-Output ("PASS  " + $visualLifecycleName)
}
catch {
    $failedTests.Add($visualLifecycleName + ' (run)')
    Write-Output ("FAIL  " + $visualLifecycleName + " " + `
        $_.Exception.Message)
}

Write-Output ("test_build_directory=" + $buildRoot)
Write-Output ("tests_passed=" + $passedTests)
Write-Output ("tests_failed=" + $failedTests.Count)

if ($failedTests.Count -gt 0) {
    foreach ($failedTest in $failedTests) {
        Write-Output ("failed_test=" + $failedTest)
    }
    exit 1
}

exit 0

# end of tests/run_tests.ps1
