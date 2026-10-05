#!/usr/bin/env bash

# Project: OpenSesh
# ----------------------------
#
# File: tests/run_linux_sanitizers.sh
#
# Purpose:
#
#     Run the complete Linux suite and the real GUI behavior audit under
#     dynamic memory and undefined-behavior analysis.
#
# Responsibilities:
#
#     - create an isolated temporary build tree
#     - run all deterministic tests with checked and sanitized binaries
#     - optionally require a real ALSA input/output loopback path
#     - build the complete editor with the same instrumentation
#     - exercise audio edit, undo, GUI, and shutdown ownership paths on X11
#     - fail on leaks, invalid memory access, or undefined behavior
#
# This file intentionally does NOT contain:
#
#     - package installation or network access
#     - display-server startup
#     - physical audio or MIDI approval

set -u
set -o pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
compiler_wrapper_source="$project_root/tests/fbc_sanitized.sh"
display_name=${LINUX_UI_DISPLAY:-${DISPLAY:-}}
xauthority_path=${LINUX_UI_XAUTHORITY:-${XAUTHORITY:-}}
test_timeout_seconds=${TEST_TIMEOUT_SECONDS:-300}
keep_build=${KEEP_SANITIZER_BUILD:-0}
require_linux_midi_loopback=${REQUIRE_LINUX_MIDI_LOOPBACK:-0}
midi_input_index=${OSE_MIDI_INPUT_INDEX:-}
midi_output_index=${OSE_MIDI_OUTPUT_INDEX:-}

case "$test_timeout_seconds" in
    ''|*[!0-9]*)
        echo 'TEST_TIMEOUT_SECONDS must be an integer from 1 to 600.' >&2
        exit 2
        ;;
esac
if [ "$test_timeout_seconds" -lt 1 ] || \
   [ "$test_timeout_seconds" -gt 600 ]; then
    echo 'TEST_TIMEOUT_SECONDS must be an integer from 1 to 600.' >&2
    exit 2
fi
case "$keep_build" in
    0|1) ;;
    *)
        echo 'KEEP_SANITIZER_BUILD must be 0 or 1.' >&2
        exit 2
        ;;
esac
case "$require_linux_midi_loopback" in
    0|1) ;;
    *)
        echo 'REQUIRE_LINUX_MIDI_LOOPBACK must be 0 or 1.' >&2
        exit 2
        ;;
esac
if [ -n "$midi_input_index" ] || [ -n "$midi_output_index" ]; then
    if [ -z "$midi_input_index" ] || [ -z "$midi_output_index" ]; then
        echo 'Both OSE_MIDI_INPUT_INDEX and OSE_MIDI_OUTPUT_INDEX are required.' >&2
        exit 2
    fi
elif [ "$require_linux_midi_loopback" -ne 0 ]; then
    midi_input_index=auto
    midi_output_index=auto
fi

sanitizer_test_count=60
if [ -n "$midi_input_index" ]; then
    sanitizer_test_count=61
fi

for required_command in bash chmod cp grep mktemp rm tee timeout; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "Required sanitizer command was not found: $required_command" >&2
        exit 1
    fi
done
if [ ! -f "$compiler_wrapper_source" ]; then
    echo "Sanitizer compiler wrapper was not found: $compiler_wrapper_source" >&2
    exit 1
fi
if [ -z "$display_name" ]; then
    echo 'An authenticated X11 display is required for the GUI audit.' >&2
    exit 1
fi
if [ -n "$xauthority_path" ] && [ ! -f "$xauthority_path" ]; then
    echo "Linux Xauthority file was not found: $xauthority_path" >&2
    exit 1
fi

build_root=$(mktemp -d "${TMPDIR:-/tmp}/opensesh-sanitizers.XXXXXX")
compiler_wrapper="$build_root/fbc-sanitized.sh"
cp -- "$compiler_wrapper_source" "$compiler_wrapper"
chmod 700 "$compiler_wrapper"
cleanup()
{
    if [ "$keep_build" -ne 0 ]; then
        return
    fi
    case "$build_root" in
        "${TMPDIR:-/tmp}"/opensesh-sanitizers.*)
            rm -rf -- "$build_root"
            ;;
        *)
            echo "Refusing to remove unexpected sanitizer path: $build_root" >&2
            ;;
    esac
}
trap cleanup EXIT HUP INT TERM

export ASAN_OPTIONS=${ASAN_OPTIONS:-detect_leaks=1:halt_on_error=1:strict_string_checks=1:check_initialization_order=1}
export LSAN_OPTIONS=${LSAN_OPTIONS:-exitcode=101:report_objects=1}
export UBSAN_OPTIONS=${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}
export SFXLIB_DRIVER=null

linux_test_log="$build_root/linux-tests.log"
OSE_MIDI_INPUT_INDEX="$midi_input_index" \
    OSE_MIDI_OUTPUT_INDEX="$midi_output_index" \
    FREEBASIC_PATH="$compiler_wrapper" \
    BUILD_DIRECTORY="$build_root/tests" \
    TEST_TIMEOUT_SECONDS="$test_timeout_seconds" bash \
    "$project_root/tests/run_tests.sh" 2>&1 | tee "$linux_test_log"
test_exit=${PIPESTATUS[0]}
if [ "$test_exit" -ne 0 ]; then
    echo "Sanitized Linux suite failed with exit code $test_exit." >&2
    exit "$test_exit"
fi
if ! grep -Fqx "tests_passed=$sanitizer_test_count" "$linux_test_log" || \
   ! grep -Fqx 'tests_failed=0' "$linux_test_log"; then
    echo 'Sanitized Linux suite did not report the expected test totals.' >&2
    exit 1
fi
if [ -n "$midi_input_index" ]; then
    if ! grep -Fqx 'midi_loopback=ok' "$linux_test_log" || \
       ! grep -Eq '^messages=[[:space:]]*7[[:space:]]*$' "$linux_test_log"; then
        echo 'Sanitized Linux suite did not prove the seven-message MIDI loopback.' >&2
        exit 1
    fi
fi

editor_path="$build_root/opensesh-sanitized"
FREEBASIC_PATH="$compiler_wrapper" OUTPUT_PATH="$editor_path" \
    bash "$project_root/build_editor.sh"
build_exit=$?
if [ "$build_exit" -ne 0 ] || [ ! -x "$editor_path" ]; then
    echo "Sanitized editor build failed with exit code $build_exit." >&2
    exit 1
fi

control_report="$build_root/control-report.txt"
preferences_file="$build_root/preferences.conf"
printf '%s\n' \
    'format=OpenSeshPreferences' \
    'version=1' \
    'theme=dark' > "$preferences_file"

DISPLAY="$display_name" XAUTHORITY="$xauthority_path" \
    OSE_TEST_HIDE_WINDOW=1 \
    OSE_TEST_CONTROL_REPORT="$control_report" \
    OSE_TEST_AUDIO_FIXTURE="$build_root/tests/audio-tracks-smoke.ose.wav" \
    OSE_TEST_PREFERENCES_FILE="$preferences_file" \
    timeout --kill-after=5s "${test_timeout_seconds}s" "$editor_path" \
    "$build_root/tests/empty-document-smoke.mid"
editor_exit=$?
if [ "$editor_exit" -ne 0 ]; then
    echo "Sanitized GUI audit failed with exit code $editor_exit." >&2
    exit "$editor_exit"
fi

for required_line in \
    'status=ok' \
    'text_controls=29' \
    'list_controls=5' \
    'behavior_checks=508' \
    'total_controls=324'; do
    if ! grep -Fqx "$required_line" "$control_report"; then
        echo "Sanitized GUI report is missing: $required_line" >&2
        exit 1
    fi
done

echo "sanitizer_linux_tests=$sanitizer_test_count"
if [ -n "$midi_input_index" ]; then
    echo 'sanitizer_midi_loopback=pass'
else
    echo 'sanitizer_midi_loopback=skipped'
fi
echo 'sanitizer_gui_behavior_checks=508'
echo 'sanitizer_gui_control_contracts=324'
echo "sanitizer_build_root=$build_root"
echo 'sanitizer_status=pass'

# end of tests/run_linux_sanitizers.sh
