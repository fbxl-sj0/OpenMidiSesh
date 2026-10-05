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
if ([string]::IsNullOrWhiteSpace($OmaGuiPath)) {
    $OmaGuiPath = Join-Path $projectRoot 'vendor\omaGui'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot 'opensesh.exe'
}

$compilerPath = [System.IO.Path]::GetFullPath($FreeBasicPath)
$omaGuiRoot = [System.IO.Path]::GetFullPath($OmaGuiPath)
$outputFile = [System.IO.Path]::GetFullPath($OutputPath)
$resourceFile = Join-Path $projectRoot 'opensesh.rc'
$manifestFile = Join-Path $projectRoot 'opensesh.manifest'

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
    'midi_input_win.bas',
    'midi_output_sfx.bas',
    'pitch_transcriber.bas',
    'music_symbols.bas'
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
        '--include-dir' $projectRoot `
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
            $sourceArguments = @('-i', $omaGuiRoot, '-O', '2', '-mt', '-c')
            If ($relativeFile -eq 'opensesh.bas') {
                $sourceArguments += @('-m', 'opensesh', '-s', 'gui')
            }
            $sourceArguments += @($sourceFile, '-o', $objectFile)
            & $compilerPath @sourceArguments
            if ($LASTEXITCODE -ne 0 -or
                -not (Test-Path -LiteralPath $objectFile -PathType Leaf)) {
                $compileExit = $LASTEXITCODE
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
