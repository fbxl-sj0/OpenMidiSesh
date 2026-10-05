#!/usr/bin/env bash

# Project: OpenSesh
# ----------------------------
#
# File: tests/run_tests.sh
#
# Purpose:
#
#     Build and run the deterministic FreeBASIC suite on Linux and Unix hosts.
#
# Responsibilities:
#
#     - compile every test from the current project sources
#     - isolate generated fixtures in a caller-selected build directory
#     - use sfxlib's hardware-independent null output driver by default
#     - report all compile and runtime failures through the process exit code
#
# This file intentionally does NOT contain:
#
#     - package installation
#     - graphical desktop automation
#     - assumptions about MIDI hardware indices

set -u

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
compiler_path=${FREEBASIC_PATH:-fbc}
omagui_root=${OMAGUI_PATH:-"$project_root/vendor/omaGui"}
build_root=${BUILD_DIRECTORY:-"${TMPDIR:-/tmp}/opensesh-tests-$$"}
test_timeout_seconds=${TEST_TIMEOUT_SECONDS:-60}

if ! command -v "$compiler_path" >/dev/null 2>&1; then
    echo "FreeBASIC compiler was not found: $compiler_path" >&2
    exit 1
fi
if [ ! -d "$omagui_root" ]; then
    echo "omaGui include tree was not found: $omagui_root" >&2
    exit 1
fi
if ! mkdir -p -- "$build_root"; then
    echo "Test build directory could not be created: $build_root" >&2
    exit 1
fi
case "$test_timeout_seconds" in
    ''|*[!0-9]*)
        echo 'TEST_TIMEOUT_SECONDS must be an integer from 1 to 3600.' >&2
        exit 1
        ;;
esac
if [ "$test_timeout_seconds" -lt 1 ] || [ "$test_timeout_seconds" -gt 3600 ]; then
    echo 'TEST_TIMEOUT_SECONDS must be an integer from 1 to 3600.' >&2
    exit 1
fi
if ! command -v timeout >/dev/null 2>&1; then
    echo 'The coreutils timeout command is required to bound test execution.' >&2
    exit 1
fi

export SFXLIB_DRIVER=${SFXLIB_DRIVER:-null}
passed_tests=0
failed_tests=0
failed_names=()

echo 'RUN   dependency_snapshot_smoke'
if ! bash "$project_root/tests/verify_dependency_snapshot.sh" "$omagui_root"; then
    echo 'FAIL  dependency_snapshot_smoke'
    failed_tests=$((failed_tests + 1))
    failed_names+=("dependency_snapshot_smoke (run)")
else
    passed_tests=$((passed_tests + 1))
    echo 'PASS  dependency_snapshot_smoke'
fi

run_test()
{
    local test_name=$1
    shift
    local output_file="$build_root/$test_name"
    local token
    # Use one thread-safe runtime for every test source. This is required by
    # programs which link the shared SoundFont audio worker.
    local -a compiler_arguments=(-i "$omagui_root" -mt -w all)
    local -a run_arguments=()

    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
        token=$1
        shift
        case "$token" in
            define:*)
                compiler_arguments+=(-d "${token#define:}")
                ;;
            *)
                if [ ! -f "$project_root/$token" ]; then
                    echo "Required test source was not found: $project_root/$token" >&2
                    exit 1
                fi
                compiler_arguments+=("$project_root/$token")
                ;;
        esac
    done
    if [ "$#" -gt 0 ]; then
        shift
    fi
    run_arguments=("$@")
    compiler_arguments+=(-x "$output_file")

    echo "BUILD $test_name"
    "$compiler_path" "${compiler_arguments[@]}" > "$build_root/$test_name.compile.log" 2>&1
    compile_exit=$?
    cat -- "$build_root/$test_name.compile.log"
    if [ "$compile_exit" -eq 0 ] && \
       grep -Eiq '\bwarning[[:space:]]+[0-9]+' "$build_root/$test_name.compile.log"; then
        compile_exit=1
        echo "Compiler warnings are rejected: $test_name" >&2
    fi
    if [ "$compile_exit" -ne 0 ]; then
        echo "FAIL  $test_name compile_exit=$compile_exit"
        failed_tests=$((failed_tests + 1))
        failed_names+=("$test_name (compile)")
        return
    fi

    echo "RUN   $test_name"
    timeout --kill-after=5s "${test_timeout_seconds}s" \
        "$output_file" "${run_arguments[@]}"
    run_exit=$?
    if [ "$run_exit" -ne 0 ]; then
        if [ "$run_exit" -eq 124 ] || [ "$run_exit" -eq 137 ]; then
            echo "TIMEOUT $test_name exceeded $test_timeout_seconds seconds."
        fi
        echo "FAIL  $test_name run_exit=$run_exit"
        failed_tests=$((failed_tests + 1))
        failed_names+=("$test_name (run)")
        return
    fi

    passed_tests=$((passed_tests + 1))
    echo "PASS  $test_name"
}

run_test omagui_safety_smoke tests/omagui_safety_smoke.bas --
run_test atomic_file_smoke tests/atomic_file_smoke.bas -- \
    "$build_root/atomic-file-smoke.bin"
run_test capture_paths_smoke \
    tests/capture_paths_smoke.bas src/capture_paths.bas -- \
    "$build_root/capture-paths-fixtures"
run_test numeric_text_smoke \
    tests/numeric_text_smoke.bas src/numeric_text.bas --
run_test audio_formats_malformed_smoke \
    tests/audio_formats_malformed_smoke.bas src/audio_tracks.bas -- \
    "$build_root/audio-formats-malformed"
run_test audio_tracks_smoke \
    tests/audio_tracks_smoke.bas src/audio_tracks.bas -- \
    "$build_root/audio-tracks-smoke.ose"
run_test audio_sample_slots_smoke \
    tests/audio_sample_slots_smoke.bas src/audio_sample_slots.bas \
    src/audio_tracks.bas src/wav_export_sfx.bas src/sfx_runtime.bas -- \
    "$build_root/audio-sample-slots-low.wav" \
    "$build_root/audio-sample-slots-high.wav" \
    "$build_root/audio-sample-slots-output.wav"
run_test audio_history_smoke \
    tests/audio_history_smoke.bas src/audio_tracks.bas -- \
    "$build_root/audio-history-smoke.wav"
run_test history_timeline_smoke \
    tests/history_timeline_smoke.bas src/history_timeline.bas --
run_test document_history_smoke \
    tests/document_history_smoke.bas src/document_history.bas \
    src/history_timeline.bas src/midi_model.bas src/audio_tracks.bas -- \
    "$build_root/document-history-smoke.wav"
run_test document_endurance_smoke \
    tests/document_endurance_smoke.bas src/document_history.bas \
    src/history_timeline.bas src/midi_model.bas src/audio_tracks.bas -- \
    "$build_root/document-endurance-smoke.wav"
run_test project_transaction_smoke \
    define:OSE_PROJECT_TRANSACTION_TESTING \
    tests/project_transaction_smoke.bas src/project_transaction.bas \
    src/numeric_text.bas -- \
    "$build_root/project-transaction-smoke"
run_test empty_document_smoke \
    tests/empty_document_smoke.bas src/midi_model.bas -- \
    "$build_root/empty-document-smoke.mid"
run_test midi_input_smoke \
    tests/midi_input_smoke.bas src/midi_alsa.bas src/midi_input_protocol.bas --
run_test keyboard_controls_smoke \
    tests/keyboard_controls_smoke.bas src/keyboard_controls.bas --
run_test drum_kit_smoke \
    tests/drum_kit_smoke.bas src/drum_kit.bas --
run_test drum_phrase_smoke \
    tests/drum_phrase_smoke.bas src/drum_phrase.bas src/drum_kit.bas src/midi_model.bas -- \
    "$build_root/drum-phrase-smoke.mid"
run_test master_effect_smoke \
    tests/master_effect_smoke.bas src/master_effect.bas src/sfx_runtime.bas --
run_test midi_input_protocol_smoke \
    tests/midi_input_protocol_smoke.bas src/midi_input_protocol.bas --
run_test mixer_meter_smoke \
    tests/mixer_meter_smoke.bas src/mixer_meter.bas --
run_test mixer_controls_smoke \
    tests/mixer_controls_smoke.bas src/mixer_controls.bas src/ui_interaction.bas --
run_test mixer_state_smoke \
    tests/mixer_state_smoke.bas src/mixer_state.bas --
run_test midi_model_smoke \
    tests/midi_model_smoke.bas src/midi_model.bas -- \
    "$build_root/empty-document-smoke.mid" \
    "$build_root/midi-model-roundtrip.mid"
run_test midi_history_smoke \
    tests/midi_history_smoke.bas src/midi_model.bas --
run_test midi_model_malformed_smoke \
    tests/midi_model_malformed_smoke.bas src/midi_model.bas -- \
    "$build_root/midi-model-malformed.mid"
run_test midi_model_fuzz_smoke \
    tests/midi_model_fuzz_smoke.bas src/midi_model.bas -- \
    "$build_root/midi-model-fuzz"
run_test midi_running_status_smoke \
    tests/midi_running_status_smoke.bas src/midi_model.bas -- \
    "$build_root/midi-running-status.mid"
run_test document_save_routing_smoke tests/document_save_routing_smoke.bas --
run_test midi_output_smoke \
    define:OSE_MIDI_OUTPUT_TESTING \
    tests/midi_output_smoke.bas src/midi_alsa.bas src/midi_input_protocol.bas --
run_test midi_playback_audio_smoke \
    tests/midi_playback_audio_smoke.bas src/midi_model.bas src/audio_tracks.bas \
    src/wav_export_sfx.bas src/playback_mix.bas src/playback_timing.bas src/soundfont_bank.bas \
    src/soundfont_synth.bas src/software_synth.bas src/mixer_state.bas src/sfx_runtime.bas -- \
    "$build_root/midi-playback-audio-smoke.mid" \
    "$build_root/midi-playback-audio-smoke.wav"
run_test playback_endurance_smoke \
    tests/playback_endurance_smoke.bas src/audio_tracks.bas src/wav_export_sfx.bas \
    src/playback_mix.bas src/soundfont_bank.bas src/soundfont_synth.bas \
    src/software_synth.bas src/sfx_runtime.bas -- \
    "$build_root/playback-endurance-smoke.wav"
run_test music_export_smoke \
    tests/music_export_smoke.bas src/midi_model.bas src/music_export.bas -- \
    "$build_root/music-export-smoke.mod"
run_test music_symbols_smoke \
    tests/music_symbols_smoke.bas src/music_symbols.bas src/numeric_text.bas -- \
    "$build_root/music-screen-glyphs.mask"
run_test notation_duration_smoke \
    tests/notation_duration_smoke.bas src/midi_model.bas -- \
    "$build_root/notation-duration-smoke.mid"
run_test note_selection_smoke \
    tests/note_selection_smoke.bas src/note_selection.bas src/midi_model.bas --
run_test selected_note_playback_smoke \
    tests/selected_note_playback_smoke.bas src/selected_note_playback.bas \
    src/note_selection.bas src/midi_model.bas src/playback_timing.bas --
run_test pitch_transcriber_smoke \
    tests/pitch_transcriber_smoke.bas src/pitch_transcriber.bas -- \
    "$build_root/pitch-transcriber-smoke.wav"
run_test playback_mix_smoke \
    tests/playback_mix_smoke.bas src/playback_mix.bas --
run_test playback_state_smoke \
    tests/playback_state_smoke.bas src/playback_state.bas --
run_test playback_timing_smoke \
    tests/playback_timing_smoke.bas src/playback_timing.bas --
run_test ui_frame_pacing_smoke \
    tests/ui_frame_pacing_smoke.bas src/ui_frame_pacing.bas --
run_test score_controls_smoke \
    tests/score_controls_smoke.bas src/score_controls.bas src/ui_interaction.bas --
run_test score_layout_smoke \
    tests/score_layout_smoke.bas src/score_layout.bas --
run_test score_scroll_smoke \
    tests/score_scroll_smoke.bas src/score_scroll.bas --
run_test score_tools_smoke \
    tests/score_tools_smoke.bas src/score_tools.bas --
run_test sfxlib_smoke tests/sfxlib_smoke.bas src/sfx_runtime.bas -- \
    "$build_root/sfxlib-capture-smoke.wav"
run_test midi_output_stop_smoke tests/midi_output_stop_smoke.bas --

run_test soundfont_smoke \
    tests/soundfont_smoke.bas src/soundfont_bank.bas src/soundfont_synth.bas \
    src/playback_mix.bas src/sfx_runtime.bas -- \
    "$build_root/soundfont-smoke.sf2" \
    "$build_root/soundfont-malformed.sf2" \
    "$build_root/soundfont-smoke.result"
run_test soundfont_shutdown_smoke \
    tests/soundfont_shutdown_smoke.bas src/soundfont_synth.bas --
run_test generated_voice_stop_smoke tests/generated_voice_stop_smoke.bas --
run_test touch_gesture_smoke \
    tests/touch_gesture_smoke.bas src/touch_gesture.bas --
run_test ui_interaction_smoke \
    tests/ui_interaction_smoke.bas src/ui_interaction.bas --
run_test ui_style_smoke tests/ui_style_smoke.bas src/ui_style.bas --
run_test ui_icons_smoke tests/ui_icons_smoke.bas src/ui_icons.bas --
run_test user_preferences_smoke \
    tests/user_preferences_smoke.bas src/user_preferences.bas \
    src/ui_interaction.bas -- \
    "$build_root/user-preferences-smoke.conf"
run_test version_smoke tests/version_smoke.bas --
run_test wav_export_smoke \
    tests/wav_export_smoke.bas src/audio_tracks.bas src/wav_export_sfx.bas -- \
    "$build_root/wav-export-smoke.wav"
run_test wav_export_failure_smoke \
    tests/wav_export_failure_smoke.bas src/wav_export_sfx.bas -- \
    "$build_root/wav-export-failure.wav"
run_test binary_file_smoke tests/binary_file_smoke.bas -- \
    "$build_root/binary-file-smoke.bin"

if [ -n "${OSE_MIDI_INPUT_INDEX:-}" ] || [ -n "${OSE_MIDI_OUTPUT_INDEX:-}" ]; then
    if [ -z "${OSE_MIDI_INPUT_INDEX:-}" ] || [ -z "${OSE_MIDI_OUTPUT_INDEX:-}" ]; then
        echo 'Both OSE_MIDI_INPUT_INDEX and OSE_MIDI_OUTPUT_INDEX are required.' >&2
        exit 1
    fi
    run_test midi_loopback_smoke \
        tests/midi_loopback_smoke.bas src/midi_alsa.bas \
        src/midi_input_protocol.bas -- \
        "$OSE_MIDI_INPUT_INDEX" "$OSE_MIDI_OUTPUT_INDEX"
else
    echo 'midi_loopback=skipped (no input/output device indices supplied)'
fi

echo "test_build_directory=$build_root"
echo "tests_passed=$passed_tests"
echo "tests_failed=$failed_tests"
for failed_name in "${failed_names[@]}"; do
    echo "failed_test=$failed_name"
done

if [ "$failed_tests" -ne 0 ]; then
    exit 1
fi
exit 0

# end of tests/run_tests.sh
