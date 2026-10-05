#!/usr/bin/env bash

# Project: OpenSesh
# ----------------------------
#
# File: verify_linux_release_archive.sh
#
# Purpose:
#
#     Verify and exercise an exact source release archive on Linux.
#
# Responsibilities:
#
#     - require the caller-supplied SHA-256 and archive entry count
#     - reject unexpected or unsafe ZIP entry paths before extraction
#     - run the complete Linux test suite from the extracted source
#     - require the ALSA loopback contract when selected by the release owner
#     - build the complete Linux editor from only the extracted source
#     - remove the isolated verification directory on every exit path
#
# This file intentionally does NOT contain:
#
#     - package installation or network access
#     - graphical desktop runtime automation
#     - physical-device configuration or approval
#     - permission to publish a commercial release

set -u

if [ "$#" -ne 3 ]; then
    echo 'Usage: verify_linux_release_archive.sh ARCHIVE SHA256 ENTRY_COUNT' >&2
    exit 2
fi

archive_input=$1
expected_sha=$2
expected_entry_count=$3
require_linux_ui_runtime=${REQUIRE_LINUX_UI_RUNTIME:-0}
require_linux_midi_loopback=${REQUIRE_LINUX_MIDI_LOOPBACK:-0}
midi_input_index=${OSE_MIDI_INPUT_INDEX:-}
midi_output_index=${OSE_MIDI_OUTPUT_INDEX:-}

case "$expected_sha" in
    *[!0-9A-Fa-f]*|'')
        echo 'SHA256 must contain exactly 64 hexadecimal characters.' >&2
        exit 2
        ;;
esac
if [ "${#expected_sha}" -ne 64 ]; then
    echo 'SHA256 must contain exactly 64 hexadecimal characters.' >&2
    exit 2
fi
case "$expected_entry_count" in
    ''|*[!0-9]*)
        echo 'ENTRY_COUNT must be an integer from 1 to 100000.' >&2
        exit 2
        ;;
esac
if [ "$expected_entry_count" -lt 1 ] || \
   [ "$expected_entry_count" -gt 100000 ]; then
    echo 'ENTRY_COUNT must be an integer from 1 to 100000.' >&2
    exit 2
fi
case "$require_linux_ui_runtime" in
    0|1) ;;
    *)
        echo 'REQUIRE_LINUX_UI_RUNTIME must be 0 or 1.' >&2
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

for required_command in \
    sha256sum unzip mktemp awk wc rm mkdir dirname basename bash cat grep; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "Required verification command was not found: $required_command" >&2
        exit 1
    fi
done
if [ ! -f "$archive_input" ]; then
    echo "Source archive was not found: $archive_input" >&2
    exit 1
fi

archive_directory=$(CDPATH= cd -- "$(dirname -- "$archive_input")" && pwd)
archive_name=$(basename -- "$archive_input")
archive_path="$archive_directory/$archive_name"
temporary_parent=${TMPDIR:-/tmp}
work_root=''

cleanup_verification_directory()
{
    if [ -z "$work_root" ]; then
        return
    fi

    # mktemp owns the six-character suffix.  Refuse cleanup if the returned
    # path ever falls outside that exact private naming boundary.
    case "$work_root" in
        "$temporary_parent"/opensesh-release-??????)
            rm -rf -- "$work_root"
            ;;
        *)
            echo "Refusing to remove unexpected temporary path: $work_root" >&2
            ;;
    esac
}

trap cleanup_verification_directory EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
work_root=$(mktemp -d \
    "$temporary_parent/opensesh-release-XXXXXX")
entry_list="$work_root/archive-entries.txt"
extract_root="$work_root/extracted"

actual_sha=$(sha256sum -- "$archive_path" | awk '{ print $1 }')
if [ "${actual_sha,,}" != "${expected_sha,,}" ]; then
    echo "Source archive SHA-256 mismatch: expected=$expected_sha actual=$actual_sha" >&2
    exit 1
fi
echo "source_archive_sha256=$actual_sha"

if ! unzip -tq "$archive_path"; then
    echo 'Source archive compression or structure validation failed.' >&2
    exit 1
fi
if ! unzip -Z1 "$archive_path" > "$entry_list"; then
    echo 'Source archive entry enumeration failed.' >&2
    exit 1
fi

actual_entry_count=$(wc -l < "$entry_list")
actual_entry_count=${actual_entry_count//[[:space:]]/}
if [ "$actual_entry_count" -ne "$expected_entry_count" ]; then
    echo "Source archive entry count mismatch: expected=$expected_entry_count actual=$actual_entry_count" >&2
    exit 1
fi

while IFS= read -r archive_entry; do
    case "$archive_entry" in
        ''|/*|*\\*|..|../*|*/..|*/../*|*//*)
            echo "Unsafe source archive entry: $archive_entry" >&2
            exit 1
            ;;
    esac
    case "$archive_entry" in
        opensesh/*) ;;
        *)
            echo "Unexpected source archive root: $archive_entry" >&2
            exit 1
            ;;
    esac
done < "$entry_list"
echo "source_archive_files=$actual_entry_count"

mkdir -- "$extract_root"
if ! unzip -q "$archive_path" -d "$extract_root"; then
    echo 'Source archive extraction failed.' >&2
    exit 1
fi

project_root="$extract_root/opensesh"
if [ ! -f "$project_root/tests/run_tests.sh" ] || \
   [ ! -f "$project_root/build_editor.sh" ] || \
   [ ! -d "$project_root/vendor/omaGui" ]; then
    echo 'Extracted source tree is missing required build or test content.' >&2
    exit 1
fi

test_timeout_seconds=${TEST_TIMEOUT_SECONDS:-90}
linux_test_log="$work_root/linux-tests.log"
if ! OSE_MIDI_INPUT_INDEX="$midi_input_index" \
    OSE_MIDI_OUTPUT_INDEX="$midi_output_index" \
    TEST_TIMEOUT_SECONDS="$test_timeout_seconds" \
    BUILD_DIRECTORY="$work_root/test-build" bash \
    "$project_root/tests/run_tests.sh" > "$linux_test_log" 2>&1; then
    cat "$linux_test_log"
    echo 'Extracted Linux test suite failed.' >&2
    exit 1
fi
cat "$linux_test_log"

expected_linux_tests=58
if [ -n "$midi_input_index" ]; then
    expected_linux_tests=59
fi
if ! grep -Fqx "tests_passed=$expected_linux_tests" "$linux_test_log" || \
   ! grep -Fqx 'tests_failed=0' "$linux_test_log"; then
    echo 'Extracted Linux suite did not report the expected test totals.' >&2
    exit 1
fi
if [ -n "$midi_input_index" ]; then
    if ! grep -Fqx 'midi_loopback=ok' "$linux_test_log" || \
       ! grep -Eq '^messages=[[:space:]]*7[[:space:]]*$' "$linux_test_log"; then
        echo 'Extracted Linux suite did not prove the seven-message MIDI loopback.' >&2
        exit 1
    fi
    echo 'linux_midi_loopback_status=pass'
else
    echo 'linux_midi_loopback_status=skipped'
fi

editor_path="$work_root/opensesh-linux"
if ! OUTPUT_PATH="$editor_path" bash "$project_root/build_editor.sh"; then
    echo 'Extracted Linux editor build failed.' >&2
    exit 1
fi
if [ ! -x "$editor_path" ]; then
    echo 'Linux editor build did not produce an executable.' >&2
    exit 1
fi

if [ "$require_linux_ui_runtime" -ne 0 ]; then
    linux_ui_display=${LINUX_UI_DISPLAY:-${DISPLAY:-}}
    linux_ui_xauthority=${LINUX_UI_XAUTHORITY:-${XAUTHORITY:-}}
    if [ -z "$linux_ui_display" ]; then
        echo 'A Linux UI display is required but LINUX_UI_DISPLAY and DISPLAY are empty.' >&2
        exit 1
    fi
    if ! BUILD_DIRECTORY="$work_root/linux-ui" \
        EDITOR_PATH="$editor_path" \
        MIDI_FIXTURE_PATH="$work_root/test-build/empty-document-smoke.mid" \
        AUDIO_FIXTURE_PATH="$work_root/test-build/audio-tracks-smoke.ose.wav" \
        LINUX_UI_DISPLAY="$linux_ui_display" \
        LINUX_UI_XAUTHORITY="$linux_ui_xauthority" \
        TEST_TIMEOUT_SECONDS="$test_timeout_seconds" \
        bash "$project_root/tests/run_linux_ui_smoke.sh"; then
        echo 'Extracted Linux GUI runtime contract failed.' >&2
        exit 1
    fi
else
    echo 'linux_ui_runtime_status=skipped (REQUIRE_LINUX_UI_RUNTIME is not 1)'
fi

editor_sha=$(sha256sum -- "$editor_path" | awk '{ print $1 }')
echo "linux_editor_sha256=$editor_sha"
echo 'linux_release_archive_status=pass'

# end of verify_linux_release_archive.sh
