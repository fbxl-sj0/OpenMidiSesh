#!/usr/bin/env bash

# Project: OpenSesh
# ----------------------------
#
# File: tests/run_ui_smoothness.sh
#
# Purpose:
#
#     Run the native Linux editor's measurable UI smoothness acceptance matrix.
#
# Responsibilities:
#
#     - exercise idle rendering in Light, Dark, and Black themes
#     - exercise real mouse and touch-profile interaction workloads
#     - exercise score scrolling, master-fader dragging, playback, and VU meters
#     - present every measured frame through the visible X11 compositor
#     - retain a full-HD idle gate in addition to shipping-size interaction gates
#     - reject missing, malformed, incomplete, or threshold-failing reports
#
# This file intentionally does NOT contain:
#
#     - editor compilation
#     - visual-baseline approval
#     - synthetic timing values or threshold overrides

set -u

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
editor_path=${EDITOR_PATH:-"$project_root/opensesh"}
build_root=${BUILD_DIRECTORY:-}
frame_count=${SMOOTHNESS_FRAME_COUNT:-480}
test_timeout_seconds=${TEST_TIMEOUT_SECONDS:-45}
display_name=${LINUX_UI_DISPLAY:-${DISPLAY:-}}
xauthority_path=${LINUX_UI_XAUTHORITY:-${XAUTHORITY:-}}
owns_build_root=0

case "$frame_count" in
    ''|*[!0-9]*)
        echo 'SMOOTHNESS_FRAME_COUNT must be an integer from 240 to 1800.' >&2
        exit 2
        ;;
esac
if [ "$frame_count" -lt 240 ] || [ "$frame_count" -gt 1800 ]; then
    echo 'SMOOTHNESS_FRAME_COUNT must be an integer from 240 to 1800.' >&2
    exit 2
fi
case "$test_timeout_seconds" in
    ''|*[!0-9]*)
        echo 'TEST_TIMEOUT_SECONDS must be an integer from 10 to 300.' >&2
        exit 2
        ;;
esac
if [ "$test_timeout_seconds" -lt 10 ] || \
   [ "$test_timeout_seconds" -gt 300 ]; then
    echo 'TEST_TIMEOUT_SECONDS must be an integer from 10 to 300.' >&2
    exit 2
fi

for required_command in timeout xdpyinfo awk mkdir mktemp rm dirname basename; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "Required smoothness command was not found: $required_command" >&2
        exit 1
    fi
done

editor_directory=$(CDPATH= cd -- "$(dirname -- "$editor_path")" 2>/dev/null && pwd)
if [ -z "$editor_directory" ]; then
    echo "Editor directory was not found: $editor_path" >&2
    exit 1
fi
editor_path="$editor_directory/$(basename -- "$editor_path")"
if [ ! -x "$editor_path" ]; then
    echo "Linux editor executable was not found: $editor_path" >&2
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
if ! XAUTHORITY="$xauthority_path" DISPLAY="$display_name" \
    xdpyinfo >/dev/null 2>&1; then
    echo "The authenticated X11 display is not usable: $display_name" >&2
    exit 1
fi

if [ -z "$build_root" ]; then
    build_root=$(mktemp -d /tmp/opensesh-smoothness-XXXXXX)
    owns_build_root=1
else
    if [ -e "$build_root" ]; then
        echo "Smoothness build directory already exists: $build_root" >&2
        exit 1
    fi
    if ! mkdir -- "$build_root"; then
        echo "Smoothness build directory could not be created: $build_root" >&2
        exit 1
    fi
fi

cleanup_smoothness_directory()
{
    if [ "$owns_build_root" -eq 0 ]; then
        return
    fi
    case "$build_root" in
        /tmp/opensesh-smoothness-??????)
            rm -rf -- "$build_root"
            ;;
        *)
            echo "Refusing to remove unexpected smoothness path: $build_root" >&2
            ;;
    esac
}

trap cleanup_smoothness_directory EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

report_value()
{
    local report_path=$1
    local report_key=$2
    awk -v wanted_key="$report_key" '
        index($0, "=") > 1 {
            key = substr($0, 1, index($0, "=") - 1)
            if (key == wanted_key) {
                matches++
                value = substr($0, index($0, "=") + 1)
            }
        }
        END {
            if (matches != 1) exit 1
            print value
        }
    ' "$report_path"
}

require_report_value()
{
    local report_path=$1
    local case_name=$2
    local report_key=$3
    local expected_value=$4
    local actual_value

    if ! actual_value=$(report_value "$report_path" "$report_key"); then
        echo "$case_name is missing or repeats report key: $report_key" >&2
        return 1
    fi
    if [ "$actual_value" != "$expected_value" ]; then
        echo "$case_name expected $report_key=$expected_value, received $actual_value." >&2
        return 1
    fi
    return 0
}

require_numeric_metric()
{
    local report_path=$1
    local case_name=$2
    local report_key=$3
    local actual_value

    if ! actual_value=$(report_value "$report_path" "$report_key"); then
        echo "$case_name is missing or repeats metric: $report_key" >&2
        return 1
    fi
    if ! awk -v value="$actual_value" 'BEGIN {
        if (value == "" || value !~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$/) exit 1
    }'; then
        echo "$case_name has a nonnumeric metric: $report_key=$actual_value" >&2
        return 1
    fi
    return 0
}

cases=(
    'idle-light-1280x720|idle|light|fine|desktop|1280|720'
    'idle-dark-1280x720|idle|dark|fine|desktop|1280|720'
    'idle-black-1280x720|idle|black|fine|desktop|1280|720'
    'interaction-dark-1280x720|interaction|dark|fine|desktop|1280|720'
    'interaction-touch-1280x720|interaction|dark|touch|touch|1280|720'
    'playback-dark-1280x720|playback|dark|fine|desktop|1280|720'
    'playback-touch-1280x720|playback|dark|touch|touch|1280|720'
    'idle-dark-1920x1080|idle|dark|fine|desktop|1920|1080'
)

for case_specification in "${cases[@]}"; do
    IFS='|' read -r case_name mode_name theme_name interaction_name \
        expected_interaction case_width case_height \
        <<< "$case_specification"
    report_path="$build_root/$case_name.txt"
    process_log="$build_root/$case_name.log"

    echo "RUN   ui_smoothness_$case_name"
    if ! (
        cd -- "$editor_directory" || exit 1
        XAUTHORITY="$xauthority_path" DISPLAY="$display_name" \
            SFXLIB_DRIVER=null OSE_TEST_HIDE_WINDOW=0 \
            OSE_TEST_SMOOTHNESS_REPORT="$report_path" \
            OSE_TEST_SMOOTHNESS_MODE="$mode_name" \
            OSE_TEST_SMOOTHNESS_FRAMES="$frame_count" \
            OSE_TEST_WIDTH="$case_width" OSE_TEST_HEIGHT="$case_height" \
            OSE_TEST_THEME="$theme_name" \
            OSE_INTERACTION_MODE="$interaction_name" \
            timeout "$test_timeout_seconds" "$editor_path"
    ) >"$process_log" 2>&1; then
        echo "$case_name failed or exceeded $test_timeout_seconds seconds." >&2
        awk 'NR <= 80 { print }' "$process_log" >&2
        exit 1
    fi
    if [ ! -s "$report_path" ]; then
        echo "$case_name did not create a smoothness report." >&2
        exit 1
    fi
    if ! awk '
        index($0, "=") <= 1 { exit 1 }
        {
            key = substr($0, 1, index($0, "=") - 1)
            if (seen[key]++) exit 1
        }
    ' "$report_path"; then
        echo "$case_name contains malformed or repeated report fields." >&2
        exit 1
    fi

    require_report_value "$report_path" "$case_name" format \
        OpenSeshUiSmoothness || exit 1
    require_report_value "$report_path" "$case_name" version 1 || exit 1
    require_report_value "$report_path" "$case_name" status pass || exit 1
    require_report_value "$report_path" "$case_name" scenario "$mode_name" || exit 1
    require_report_value "$report_path" "$case_name" width "$case_width" || exit 1
    require_report_value "$report_path" "$case_name" height "$case_height" || exit 1
    require_report_value "$report_path" "$case_name" theme "$theme_name" || exit 1
    require_report_value "$report_path" "$case_name" interaction \
        "$expected_interaction" || exit 1
    require_report_value "$report_path" "$case_name" tracks 16 || exit 1
    require_report_value "$report_path" "$case_name" notes 2048 || exit 1
    require_report_value "$report_path" "$case_name" samples "$frame_count" || exit 1
    require_report_value "$report_path" "$case_name" rejected_samples 0 || exit 1
    require_report_value "$report_path" "$case_name" workload_valid yes || exit 1
    require_report_value "$report_path" "$case_name" minimum_fps 59 || exit 1
    require_report_value "$report_path" "$case_name" maximum_interval_p95_ms 20 || exit 1
    require_report_value "$report_path" "$case_name" maximum_interval_p99_ms 25 || exit 1
    require_report_value "$report_path" "$case_name" maximum_interval_ms 50 || exit 1
    require_report_value "$report_path" "$case_name" maximum_work_p95_ms 16.67 || exit 1
    require_report_value "$report_path" "$case_name" maximum_input_p95_ms 20 || exit 1
    require_report_value "$report_path" "$case_name" maximum_hitches 2 || exit 1

    for metric_name in average_fps interval_p95_ms interval_p99_ms \
        interval_max_ms work_p95_ms input_p95_ms application_render_p95_ms \
        presentation_p95_ms hitches_over_33_34_ms hitches_over_50_ms; do
        require_numeric_metric "$report_path" "$case_name" "$metric_name" || exit 1
    done

    average_fps=$(report_value "$report_path" average_fps)
    interval_p95=$(report_value "$report_path" interval_p95_ms)
    interval_p99=$(report_value "$report_path" interval_p99_ms)
    interval_max=$(report_value "$report_path" interval_max_ms)
    work_p95=$(report_value "$report_path" work_p95_ms)
    input_p95=$(report_value "$report_path" input_p95_ms)
    echo "PASS  ui_smoothness_$case_name fps=$average_fps p95_ms=$interval_p95 p99_ms=$interval_p99 max_ms=$interval_max work_p95_ms=$work_p95 input_p95_ms=$input_p95"
done

echo "ui_smoothness_cases=${#cases[@]}"
echo 'ui_smoothness_status=pass'

# end of tests/run_ui_smoothness.sh
