<#
    Project: OpenSesh
    ----------------------------

    File: build_editor.ps1

    Purpose:

        Compile the native FreeBASIC editor from the reviewed project sources.

    Responsibilities:

        - validate the local compiler, omaGui include tree, and source inputs
        - compile Windows version and process-manifest resources
        - invoke FreeBASIC with the required omaGui include path
        - strip debug data and remove the host-clock PE timestamp
        - report the resulting executable path and compiler status

    This file intentionally does NOT contain:

        - dependency installation or redistribution
        - recovered Midisoft files or decompiler output
        - packaging, deployment, or runtime testing
#>

[CmdletBinding()]
param(
    [string] $FreeBasicPath = 'C:\FreeBASIC\fbc.exe',
    [string] $OmaGuiPath = '',
    [string] $ResourceCompilerPath = '',
    [string] $OutputPath = ''
)

$projectRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$sourceRoot = Join-Path $projectRoot 'src'
if ([string]::IsNullOrWhiteSpace($OmaGuiPath)) {
    $OmaGuiPath = Join-Path $projectRoot 'vendor\omaGui'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot 'opensesh.exe'
}

$compilerPath = [System.IO.Path]::GetFullPath($FreeBasicPath)
$omaGuiRoot = [System.IO.Path]::GetFullPath($OmaGuiPath)
$outputFile = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $outputFile
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}
$resourceFile = Join-Path $projectRoot 'src\opensesh.rc'
$manifestFile = Join-Path $projectRoot 'src\opensesh.manifest'

if (-not (Test-Path -LiteralPath $compilerPath -PathType Leaf)) {
    throw "FreeBASIC compiler was not found: $compilerPath"
}
if (-not (Test-Path -LiteralPath $omaGuiRoot -PathType Container)) {
    throw "omaGui include tree was not found: $omaGuiRoot"
}
if (-not (Test-Path -LiteralPath $resourceFile -PathType Leaf)) {
    throw "Windows version resource was not found: $resourceFile"
}
if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
    throw "Windows process manifest was not found: $manifestFile"
}

if ([string]::IsNullOrWhiteSpace($ResourceCompilerPath)) {
    $compilerRoot = Split-Path -Parent $compilerPath
    $resourceCandidates = @(
        (Join-Path $compilerRoot 'bin\win64\windres.exe'),
        (Join-Path $compilerRoot 'bin\win32\windres.exe')
    )
    $ResourceCompilerPath = $resourceCandidates | Where-Object {
        Test-Path -LiteralPath $_ -PathType Leaf
    } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($ResourceCompilerPath) -or
    -not (Test-Path -LiteralPath $ResourceCompilerPath -PathType Leaf)) {
    throw 'A GNU windres executable is required for Windows version metadata.'
}
$resourceCompiler = [System.IO.Path]::GetFullPath($ResourceCompilerPath)

$sourceFiles = @(
    'src\opensesh.bas',
    'src\omagui_runtime.bas',
    'src\midi_model.bas',
    'src\history_timeline.bas',
    'src\document_history.bas',
    'src\project_transaction.bas',
    'src\note_selection.bas',
    'src\selected_note_playback.bas',
    'src\score_tools.bas',
    'src\score_controls.bas',
    'src\numeric_text.bas',
    'src\capture_paths.bas',
    'src\score_scroll.bas',
    'src\score_layout.bas',
    'src\mixer_meter.bas',
    'src\mixer_controls.bas',
    'src\mixer_state.bas',
    'src\keyboard_controls.bas',
    'src\drum_kit.bas',
    'src\drum_phrase.bas',
    'src\playback_mix.bas',
    'src\playback_timing.bas',
    'src\ui_frame_pacing.bas',
    'src\soundfont_bank.bas',
    'src\soundfont_synth.bas',
    'src\software_synth.bas',
    'src\playback_state.bas',
    'src\master_effect.bas',
    'src\sfx_runtime.bas',
    'src\ui_style.bas',
    'src\ui_icons.bas',
    'src\ui_interaction.bas',
    'src\touch_gesture.bas',
    'src\user_preferences.bas',
    'src\music_export.bas',
    'src\wav_export_sfx.bas',
    'src\audio_tracks.bas',
    'src\audio_sample_slots.bas',
    'src\midi_input_protocol.bas',
    'src\midi_input_win.bas',
    'src\midi_output_sfx.bas',
    'src\pitch_transcriber.bas',
    'src\music_symbols.bas'
)

foreach ($relativeFile in $sourceFiles) {
    $sourceFile = Join-Path $projectRoot $relativeFile
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        throw "Required source file is missing: $relativeFile"
    }
}

$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$objectRoot = Join-Path $temporaryRoot `
    ('opensesh-build-' + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $objectRoot | Out-Null
$resourceObject = Join-Path $objectRoot 'opensesh_resource.o'
$linkedExecutable = Join-Path $objectRoot 'opensesh.exe'
$objectFiles = [System.Collections.Generic.List[string]]::new()
$compileExit = 1
try {
    & $resourceCompiler '--input-format=rc' '--output-format=coff' `
        '--include-dir' $sourceRoot `
        '--input' $resourceFile '--output' $resourceObject
    $resourceExit = $LASTEXITCODE
    if ($resourceExit -ne 0 -or
        -not (Test-Path -LiteralPath $resourceObject -PathType Leaf)) {
        Write-Output ('resource_compile_exit=' + $resourceExit)
    }
    else {
        <#
            Compile one source at a time into the temporary build tree. fbc
            otherwise retains every generated assembly file beside the source
            until the final link, which can exhaust a nearly full source drive.
        #>
        $compileExit = 0
        foreach ($relativeFile in $sourceFiles) {
            $sourceFile = Join-Path $projectRoot $relativeFile
            $objectName = [System.IO.Path]::GetFileNameWithoutExtension(
                $relativeFile) + '.o'
            $objectFile = Join-Path $objectRoot $objectName
            # Level 2 retains debuggable, standards-compliant code generation
            # while removing avoidable work from the continuously redrawn UI.
            # The SoundFont renderer owns an audio worker. Every object must
            # therefore use FreeBASIC's thread-safe runtime, including objects
            # which do not call the threading API directly.
            $sourceArguments = @('-i', $omaGuiRoot, '-O', '2', '-mt', '-w', 'all', '-c')
            If ($relativeFile -eq 'src\opensesh.bas') {
                $sourceArguments += @('-m', 'opensesh', '-s', 'gui')
            }
            $sourceArguments += @($sourceFile, '-o', $objectFile)
            $compilerOutput = @(& $compilerPath @sourceArguments 2>&1)
            $sourceExit = $LASTEXITCODE
            $compilerOutput | ForEach-Object { Write-Output $_ }
            # fbc has no warning-as-error switch. A release object is accepted
            # only when the compiler succeeds without a warning diagnostic.
            $hasWarnings = @($compilerOutput | Where-Object {
                [string] $_ -match '(?i)\bwarning\s+\d+'
            }).Count -gt 0
            if ($sourceExit -ne 0 -or $hasWarnings -or
                -not (Test-Path -LiteralPath $objectFile -PathType Leaf)) {
                $compileExit = $sourceExit
                if ($compileExit -eq 0) {
                    $compileExit = 1
                }
                Write-Output ('source_compile_failure=' + $relativeFile)
                break
            }
            $objectFiles.Add($objectFile)
        }

        if ($compileExit -eq 0) {
            <#
                Customer binaries must not retain source-level DWARF sections
                from statically linked libraries. A zero PE timestamp also
                removes the final host-clock input from otherwise identical
                release builds, allowing the verifier to compare two builds
                byte for byte before packaging.
            #>
            $linkArguments = @(
                '-s', 'gui',
                '-mt',
                '-strip',
                '-Wl', '--no-insert-timestamp'
            ) + @($objectFiles) + @(
                $resourceObject, '-x', $linkedExecutable
            )
            & $compilerPath @linkArguments
            $compileExit = $LASTEXITCODE
            if ($compileExit -eq 0 -and
                (Test-Path -LiteralPath $linkedExecutable -PathType Leaf)) {
                Copy-Item -LiteralPath $linkedExecutable `
                    -Destination $outputFile -Force
            }
            elseif ($compileExit -eq 0) {
                $compileExit = 1
                Write-Output 'link_output_missing=1'
            }
        }
    }
}
finally {
    <#
        The recursively removed directory has a generated, fixed-prefix name
        and must resolve inside the operating-system temporary directory.
    #>
    $resolvedObjectRoot = [System.IO.Path]::GetFullPath($objectRoot)
    $temporaryBoundary = $temporaryRoot.TrimEnd('\') + '\'
    $objectLeaf = Split-Path -Leaf $resolvedObjectRoot
    if (-not $resolvedObjectRoot.StartsWith(
            $temporaryBoundary,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not $objectLeaf.StartsWith('opensesh-build-')) {
        throw "Refusing to remove an unexpected build directory: $resolvedObjectRoot"
    }
    if (Test-Path -LiteralPath $resolvedObjectRoot -PathType Container) {
        Remove-Item -LiteralPath $resolvedObjectRoot -Recurse -Force
    }
}
Write-Output ('editor_executable=' + $outputFile)
Write-Output ('editor_compile_exit=' + $compileExit)
exit $compileExit

# end of build_editor.ps1
