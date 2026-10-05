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

set -u

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
    opensesh.bas
    omagui_runtime.bas
    midi_model.bas
    history_timeline.bas
    document_history.bas
    project_transaction.bas
    note_selection.bas
    selected_note_playback.bas
    score_tools.bas
    score_controls.bas
    numeric_text.bas
    capture_paths.bas
    score_scroll.bas
    score_layout.bas
    mixer_meter.bas
    mixer_controls.bas
    mixer_state.bas
    keyboard_controls.bas
    drum_kit.bas
    drum_phrase.bas
    playback_mix.bas
    playback_timing.bas
    ui_frame_pacing.bas
    soundfont_bank.bas
    soundfont_synth.bas
    software_synth.bas
    playback_state.bas
    master_effect.bas
    sfx_runtime.bas
    ui_style.bas
    ui_icons.bas
    ui_interaction.bas
    touch_gesture.bas
    user_preferences.bas
    music_export.bas
    wav_export_sfx.bas
    audio_tracks.bas
    audio_sample_slots.bas
    midi_input_protocol.bas
    midi_alsa.bas
    pitch_transcriber.bas
    music_symbols.bas
)

# The SoundFont renderer owns an audio worker, so every object must use the
# thread-safe FreeBASIC runtime even when a particular module has no threads.
compiler_arguments=(-i "$omagui_root" -O 2 -mt)
for relative_file in "${source_files[@]}"; do
    source_file="$project_root/$relative_file"
    if [ ! -f "$source_file" ]; then
        echo "Required source file is missing: $relative_file" >&2
        exit 1
    fi
    compiler_arguments+=("$source_file")
done
compiler_arguments+=(-x "$output_file")

"$compiler_path" "${compiler_arguments[@]}"
compile_exit=$?
echo "editor_executable=$output_file"
echo "editor_compile_exit=$compile_exit"
exit "$compile_exit"

# end of build_editor.sh
