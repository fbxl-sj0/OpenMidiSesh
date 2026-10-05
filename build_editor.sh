#!/usr/bin/env bash

# Project: OpenSesh
# ----------------------------
#
# File: build_editor.sh
#
# Purpose:
#
#     Compile the native FreeBASIC editor on Linux with the ALSA MIDI backend.
#
# Responsibilities:
#
#     - validate the compiler, omaGui include tree, and project sources
#     - invoke FreeBASIC with the same source set as the Windows build
#     - report an unambiguous compiler result and output path
#
# This file intentionally does NOT contain:
#
#     - dependency installation
#     - platform package-manager assumptions
#     - runtime or graphical desktop tests

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
compiler_path=${FREEBASIC_PATH:-fbc}
omagui_root=${OMAGUI_PATH:-"$project_root/vendor/omaGui"}
output_file=${OUTPUT_PATH:-"$project_root/opensesh"}

if ! command -v "$compiler_path" >/dev/null 2>&1; then
    echo "FreeBASIC compiler was not found: $compiler_path" >&2
    exit 1
fi
if [ ! -d "$omagui_root" ]; then
    echo "omaGui include tree was not found: $omagui_root" >&2
    exit 1
fi

source_files=(
    src/opensesh.bas
    src/omagui_runtime.bas
    src/midi_model.bas
    src/history_timeline.bas
    src/document_history.bas
    src/project_transaction.bas
    src/note_selection.bas
    src/selected_note_playback.bas
    src/score_tools.bas
    src/score_controls.bas
    src/numeric_text.bas
    src/capture_paths.bas
    src/score_scroll.bas
    src/score_layout.bas
    src/mixer_meter.bas
    src/mixer_controls.bas
    src/mixer_state.bas
    src/keyboard_controls.bas
    src/drum_kit.bas
    src/drum_phrase.bas
    src/playback_mix.bas
    src/playback_timing.bas
    src/ui_frame_pacing.bas
    src/soundfont_bank.bas
    src/soundfont_synth.bas
    src/software_synth.bas
    src/playback_state.bas
    src/master_effect.bas
    src/sfx_runtime.bas
    src/ui_style.bas
    src/ui_icons.bas
    src/ui_interaction.bas
    src/touch_gesture.bas
    src/user_preferences.bas
    src/music_export.bas
    src/wav_export_sfx.bas
    src/audio_tracks.bas
    src/audio_sample_slots.bas
    src/midi_input_protocol.bas
    src/midi_alsa.bas
    src/pitch_transcriber.bas
    src/music_symbols.bas
)

# The SoundFont renderer owns an audio worker, so every object must use the
# thread-safe FreeBASIC runtime even when a particular module has no threads.
mkdir -p -- "$(dirname -- "$output_file")"
object_root=$(mktemp -d "${TMPDIR:-/tmp}/opensesh-build.XXXXXXXX")
# Only this invocation's mktemp directory is removed. Objects never accumulate
# beside sources, and a failed build leaves the last working executable intact.
trap 'rm -rf -- "$object_root"' EXIT
object_files=()
for relative_file in "${source_files[@]}"; do
    source_file="$project_root/$relative_file"
    if [ ! -f "$source_file" ]; then
        echo "Required source file is missing: $relative_file" >&2
        exit 1
    fi
    object_file="$object_root/$(basename -- "${relative_file%.bas}").o"
    compiler_arguments=(-i "$omagui_root" -O 2 -mt -w all -c)
    if [ "$relative_file" = src/opensesh.bas ]; then
        compiler_arguments+=(-m opensesh)
    fi
    # FreeBASIC has no warning-as-error option. Preserve its status, show the
    # diagnostics, and reject an otherwise successful compile with warnings.
    compile_exit=0
    "$compiler_path" "${compiler_arguments[@]}" "$source_file" -o "$object_file" \
        > "$object_root/compiler.log" 2>&1 || compile_exit=$?
    cat -- "$object_root/compiler.log"
    if [ "$compile_exit" -ne 0 ] || \
       grep -Eiq '\bwarning[[:space:]]+[0-9]+' "$object_root/compiler.log" || \
       [ ! -f "$object_file" ]; then
        echo "source_compile_failure=$relative_file" >&2
        echo 'editor_compile_exit=1'
        exit 1
    fi
    object_files+=("$object_file")
done

compile_exit=0
"$compiler_path" -mt -strip "${object_files[@]}" -x "$object_root/opensesh" \
    > "$object_root/compiler.log" 2>&1 || compile_exit=$?
cat -- "$object_root/compiler.log"
if [ "$compile_exit" -ne 0 ] || \
   grep -Eiq '\bwarning[[:space:]]+[0-9]+' "$object_root/compiler.log" || \
   [ ! -f "$object_root/opensesh" ]; then
    echo 'editor_compile_exit=1'
    exit 1
fi
mv -f -- "$object_root/opensesh" "$output_file"
echo "editor_executable=$output_file"
echo "editor_compile_exit=$compile_exit"
exit "$compile_exit"

# end of build_editor.sh
