#!/usr/bin/env bash

# Project: OpenSesh
# ----------------------------
#
# File: tests/run_linux_ui_smoke.sh
#
# Purpose:
#
#     Exercise the real editor process on an authenticated Linux X11 display.
#
# Responsibilities:
#
#     - capture Light, Dark, and Black main, menu, dialog, and active-meter views
#     - validate deterministic 800 x 600 and 1920 x 1080, 24-bit BMP output
#     - compare every Linux framebuffer against reviewed SHA-256 baselines
#     - run the complete application control and semantic-behavior audit
#     - gate idle, interaction, playback, and VU frame pacing at 60 Hz
#     - prove repeated GUI startup and explicit display teardown complete in time
#
# This file intentionally does NOT contain:
#
#     - display-server installation or startup
#     - desktop pointer or keyboard automation
#     - physical MIDI, microphone, or speaker approval

set -u

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
editor_path=${EDITOR_PATH:-"$project_root/opensesh"}
midi_fixture=${MIDI_FIXTURE_PATH:-}
audio_fixture=${AUDIO_FIXTURE_PATH:-}
display_name=${LINUX_UI_DISPLAY:-${DISPLAY:-}}
xauthority_path=${LINUX_UI_XAUTHORITY:-${XAUTHORITY:-}}
baseline_file=${LINUX_VISUAL_BASELINE_FILE:-"$project_root/tests/linux_visual_baselines.sha256"}
record_baselines=${OSE_LINUX_VISUAL_RECORD:-0}
test_timeout_seconds=${TEST_TIMEOUT_SECONDS:-30}
build_root=${BUILD_DIRECTORY:-}
owns_build_root=0

case "$record_baselines" in
    0|1) ;;
    *)
        echo 'OSE_LINUX_VISUAL_RECORD must be 0 or 1.' >&2
        exit 2
        ;;
esac
case "$test_timeout_seconds" in
    ''|*[!0-9]*)
        echo 'TEST_TIMEOUT_SECONDS must be an integer from 1 to 300.' >&2
        exit 2
        ;;
esac
if [ "$test_timeout_seconds" -lt 1 ] || [ "$test_timeout_seconds" -gt 300 ]; then
    echo 'TEST_TIMEOUT_SECONDS must be an integer from 1 to 300.' >&2
    exit 2
fi

for required_command in timeout xdpyinfo sha256sum od wc grep mkdir mktemp rm \
    sed cat; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "Required Linux UI command was not found: $required_command" >&2
        exit 1
    fi
done
if [ ! -x "$editor_path" ]; then
    echo "Linux editor executable was not found: $editor_path" >&2
    exit 1
fi
if [ ! -f "$midi_fixture" ]; then
    echo "Linux UI MIDI fixture was not found: $midi_fixture" >&2
    exit 1
fi
if [ ! -f "$audio_fixture" ]; then
    echo "Linux UI audio fixture was not found: $audio_fixture" >&2
    exit 1
fi
if [ -z "$display_name" ]; then
    echo 'LINUX_UI_DISPLAY or DISPLAY must name an X11 display.' >&2
    exit 1
fi
if [ -n "$xauthority_path" ] && [ ! -f "$xauthority_path" ]; then
    echo "Linux UI Xauthority file was not found: $xauthority_path" >&2
    exit 1
fi
if [ "$record_baselines" -eq 0 ] && [ ! -f "$baseline_file" ]; then
    echo "Linux visual baseline file was not found: $baseline_file" >&2
    exit 1
fi

if ! XAUTHORITY="$xauthority_path" DISPLAY="$display_name" \
    xdpyinfo >/dev/null 2>&1; then
    echo "The authenticated X11 display is not usable: $display_name" >&2
    exit 1
fi

if [ -z "$build_root" ]; then
    build_root=$(mktemp -d /tmp/opensesh-linux-ui-XXXXXX)
    owns_build_root=1
else
    if [ -e "$build_root" ]; then
        echo "Linux UI build directory already exists: $build_root" >&2
        exit 1
    fi
    if ! mkdir -- "$build_root"; then
        echo "Linux UI build directory could not be created: $build_root" >&2
        exit 1
    fi
fi

cleanup_linux_ui_directory()
{
    if [ "$owns_build_root" -eq 0 ]; then
        return
    fi
    case "$build_root" in
        /tmp/opensesh-linux-ui-??????)
            rm -rf -- "$build_root"
            ;;
        *)
            echo "Refusing to remove unexpected Linux UI path: $build_root" >&2
            ;;
    esac
}

trap cleanup_linux_ui_directory EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

capture_root="$build_root/captures"
dialog_root="$build_root/dialog-root"
actual_manifest="$build_root/linux-visual-actual.sha256"
mkdir -- "$capture_root" "$dialog_root"
: > "$actual_manifest"

validate_snapshot()
{
    local snapshot_path=$1
    local snapshot_name=$2
    local expected_width=$3
    local expected_height=$4
    local header_bytes
    local width
    local height
    local bits_per_pixel
    local compression
    local data_offset
    local row_bytes
    local expected_bytes
    local actual_bytes
    local snapshot_hash

    if [ ! -s "$snapshot_path" ]; then
        echo "Linux UI snapshot was not created: $snapshot_name" >&2
        return 1
    fi
    header_bytes=($(od -An -tu1 -N34 -- "$snapshot_path"))
    if [ "${#header_bytes[@]}" -ne 34 ]; then
        echo "Linux UI snapshot header is truncated: $snapshot_name" >&2
        return 1
    fi
    if [ "${header_bytes[0]}" -ne 66 ] || [ "${header_bytes[1]}" -ne 77 ]; then
        echo "Linux UI snapshot is not a BMP file: $snapshot_name" >&2
        return 1
    fi

    data_offset=$((header_bytes[10] + header_bytes[11] * 256 + \
        header_bytes[12] * 65536 + header_bytes[13] * 16777216))
    width=$((header_bytes[18] + header_bytes[19] * 256 + \
        header_bytes[20] * 65536 + header_bytes[21] * 16777216))
    height=$((header_bytes[22] + header_bytes[23] * 256 + \
        header_bytes[24] * 65536 + header_bytes[25] * 16777216))
    bits_per_pixel=$((header_bytes[28] + header_bytes[29] * 256))
    compression=$((header_bytes[30] + header_bytes[31] * 256 + \
        header_bytes[32] * 65536 + header_bytes[33] * 16777216))
    if [ "$data_offset" -ne 54 ] || [ "$width" -ne "$expected_width" ] || \
       [ "$height" -ne "$expected_height" ] || \
       [ "$bits_per_pixel" -ne 24 ] || \
       [ "$compression" -ne 0 ]; then
        echo "Linux UI snapshot format changed: $snapshot_name offset=$data_offset width=$width height=$height bpp=$bits_per_pixel compression=$compression" >&2
        return 1
    fi

    row_bytes=$((((width * 3) + 3) / 4 * 4))
    expected_bytes=$((data_offset + row_bytes * height))
    actual_bytes=$(wc -c < "$snapshot_path")
    actual_bytes=${actual_bytes//[[:space:]]/}
    if [ "$actual_bytes" -ne "$expected_bytes" ]; then
        echo "Linux UI snapshot byte count changed: $snapshot_name expected=$expected_bytes actual=$actual_bytes" >&2
        return 1
    fi

    snapshot_hash=$(sha256sum -- "$snapshot_path")
    snapshot_hash=${snapshot_hash%% *}
    printf '%s  %s\n' "$snapshot_hash" "$snapshot_name" >> "$actual_manifest"
    return 0
}


linux_ui_visual_launches=0
linux_ui_control_launches=0

capture_case()
{
    local case_name=$1
    local theme_name=$2
    local modal_name=$3
    local audition_pitch=$4
    local capture_width=$5
    local capture_height=$6
    local snapshot_name="$case_name.bmp"
    local snapshot_path="$capture_root/$snapshot_name"
    local process_log="$build_root/$case_name.log"
    linux_ui_visual_launches=$((linux_ui_visual_launches + 1))

    if ! (
        cd -- "$dialog_root" || exit 1
        XAUTHORITY="$xauthority_path" DISPLAY="$display_name" \
            SFXLIB_DRIVER=null OSE_TEST_HIDE_WINDOW=1 \
            OSE_TEST_SNAPSHOT="$snapshot_path" OSE_TEST_SNAPSHOT_FRAME=12 \
            OSE_TEST_WIDTH="$capture_width" OSE_TEST_HEIGHT="$capture_height" \
            OSE_TEST_THEME="$theme_name" OSE_TEST_MODAL="$modal_name" \
            OSE_TEST_AUDITION_PITCH="$audition_pitch" \
            OSE_TEST_VISUAL_DEVICES=1 timeout "$test_timeout_seconds" \
            "$editor_path" "$midi_fixture"
    ) >"$process_log" 2>&1; then
        echo "Linux UI process failed or timed out: $case_name" >&2
        sed -n '1,80p' "$process_log" >&2
        return 1
    fi
    validate_snapshot "$snapshot_path" "$snapshot_name" \
        "$capture_width" "$capture_height"
}


capture_case main-light-800x600 light '' '' 800 600 || exit 1
capture_case main-dark-800x600 dark '' '' 800 600 || exit 1
capture_case main-black-800x600 black '' '' 800 600 || exit 1
capture_case options-light-800x600 light options_menu '' 800 600 || exit 1
capture_case options-dark-800x600 dark options_menu '' 800 600 || exit 1
capture_case options-black-800x600 black options_menu '' 800 600 || exit 1
capture_case view-light-800x600 light view_menu '' 800 600 || exit 1
capture_case about-light-800x600 light about '' 800 600 || exit 1
capture_case about-dark-800x600 dark about '' 800 600 || exit 1
capture_case about-black-800x600 black about '' 800 600 || exit 1
capture_case drums-light-800x600 light drums '' 800 600 || exit 1
capture_case drums-dark-800x600 dark drums '' 800 600 || exit 1
capture_case drums-black-800x600 black drums '' 800 600 || exit 1
capture_case active-meter-light-800x600 light '' 69 800 600 || exit 1
capture_case active-meter-dark-800x600 dark '' 69 800 600 || exit 1
capture_case active-meter-black-800x600 black '' 69 800 600 || exit 1

# The larger desktop cases guard against right-edge clipping, incomplete theme
# coverage, and mixer layouts that only happen to fit the minimum window.
capture_case main-light-1920x1080 light '' '' 1920 1080 || exit 1
capture_case main-dark-1920x1080 dark '' '' 1920 1080 || exit 1
capture_case main-black-1920x1080 black '' '' 1920 1080 || exit 1
capture_case options-dark-1920x1080 dark options_menu '' 1920 1080 || exit 1
capture_case active-meter-black-1920x1080 black '' 69 1920 1080 || exit 1

if [ "$record_baselines" -ne 0 ]; then
    echo 'linux_visual_baselines_begin'
    cat "$actual_manifest"
    echo 'linux_visual_baselines_end'
else
    if ! (cd -- "$capture_root" && sha256sum --check --strict "$baseline_file"); then
        echo 'One or more Linux framebuffer baselines changed.' >&2
        exit 1
    fi
fi

control_report="$build_root/linux-ui-control-report.txt"
control_log="$build_root/linux-ui-control-audit.log"
preferences_file="$build_root/linux-ui-preferences.conf"
printf 'format=OpenSeshPreferences\nversion=1\ntheme=dark\ninteraction=fine\n' \
    > "$preferences_file"

linux_ui_control_launches=$((linux_ui_control_launches + 1))
if ! (
    cd -- "$dialog_root" || exit 1
    XAUTHORITY="$xauthority_path" DISPLAY="$display_name" \
        SFXLIB_DRIVER=null OSE_TEST_HIDE_WINDOW=1 \
        OSE_TEST_CONTROL_REPORT="$control_report" \
        OSE_TEST_AUDIO_FIXTURE="$audio_fixture" \
        OSE_TEST_PREFERENCES_FILE="$preferences_file" \
        timeout "$test_timeout_seconds" "$editor_path" "$midi_fixture"
) >"$control_log" 2>&1; then
    echo 'Linux UI control audit failed or timed out.' >&2
    sed -n '1,120p' "$control_log" >&2
    exit 1
fi
if [ ! -f "$control_report" ]; then
    echo 'Linux UI control audit did not create its report.' >&2
    exit 1
fi
for required_report_line in \
    'status=ok' \
    'widget_actions=117' \
    'text_controls=29' \
    'list_controls=5' \
    'scroll_controls=2' \
    'custom_controls=171' \
    'behavior_checks=508' \
    'startup_theme=Dark' \
    'startup_interaction=Desktop' \
    'persisted_theme=Dark' \
    'persisted_interaction=Desktop' \
    'total_controls=324'; do
    if ! grep -Fqx "$required_report_line" "$control_report"; then
        echo "Linux UI control report is missing: $required_report_line" >&2
        sed -n '1,120p' "$control_report" >&2
        exit 1
    fi
done

touch_control_report="$build_root/linux-ui-touch-control-report.txt"
touch_control_log="$build_root/linux-ui-touch-control-audit.log"
touch_preferences_file="$build_root/linux-ui-touch-preferences.conf"
linux_ui_control_launches=$((linux_ui_control_launches + 1))
if ! (
    cd -- "$dialog_root" || exit 1
    XAUTHORITY="$xauthority_path" DISPLAY="$display_name" \
        SFXLIB_DRIVER=null OSE_TEST_HIDE_WINDOW=1 \
        OSE_DEFAULT_INTERACTION_MODE=touch \
        OSE_TEST_CONTROL_REPORT="$touch_control_report" \
        OSE_TEST_AUDIO_FIXTURE="$audio_fixture" \
        OSE_TEST_PREFERENCES_FILE="$touch_preferences_file" \
        timeout "$test_timeout_seconds" "$editor_path" "$midi_fixture"
) >"$touch_control_log" 2>&1; then
    echo 'Linux touch UI control audit failed or timed out.' >&2
    sed -n '1,120p' "$touch_control_log" >&2
    exit 1
fi
for required_report_line in \
    'status=ok' \
    'widget_actions=117' \
    'text_controls=29' \
    'list_controls=5' \
    'scroll_controls=2' \
    'custom_controls=171' \
    'behavior_checks=508' \
    'startup_theme=Light' \
    'startup_interaction=Touch' \
    'persisted_theme=Light' \
    'persisted_interaction=Touch' \
    'total_controls=324'; do
    if ! grep -Fqx "$required_report_line" "$touch_control_report"; then
        echo "Linux touch UI report is missing: $required_report_line" >&2
        sed -n '1,120p' "$touch_control_report" >&2
        exit 1
    fi
done

# The smoothness runner owns its child directory and reports the number of cases it completed.
smoothness_log="$build_root/linux-ui-smoothness.log"
if ! BUILD_DIRECTORY="$build_root/smoothness" \
    EDITOR_PATH="$editor_path" \
    LINUX_UI_DISPLAY="$display_name" \
    LINUX_UI_XAUTHORITY="$xauthority_path" \
    TEST_TIMEOUT_SECONDS="$test_timeout_seconds" \
    bash "$project_root/tests/run_ui_smoothness.sh" >"$smoothness_log" 2>&1; then
    echo 'Linux UI smoothness acceptance matrix failed.' >&2
    sed -n '1,120p' "$smoothness_log" >&2
    exit 1
fi
cat "$smoothness_log"
smoothness_cases=$(sed -n 's/^ui_smoothness_cases=//p' "$smoothness_log")
case "$smoothness_cases" in
    ''|*[!0-9]*)
        echo 'Linux UI smoothness case count is missing or invalid.' >&2
        exit 1
        ;;
esac

echo 'linux_ui_runtime_status=pass'
echo "linux_ui_visual_cases=$linux_ui_visual_launches"
echo "linux_ui_process_launches=$((linux_ui_visual_launches + linux_ui_control_launches + smoothness_cases))"
echo 'linux_ui_behavior_checks=1016'
echo 'linux_ui_control_contracts=648'
echo "linux_ui_smoothness_cases=$smoothness_cases"

# end of tests/run_linux_ui_smoke.sh
