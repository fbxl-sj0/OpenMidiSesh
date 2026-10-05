#!/usr/bin/env bash
# Project: OpenSesh
# File: tools/ci_native.sh
# Purpose: run native Unix build, tests, window checks and packaging as one gate.
# Responsibilities: preserve failures, isolate a display, verify packaged startup.
# This file does not install a compiler or run on a persistent service host.

set -euo pipefail
[ "${GITHUB_ACTIONS:-}" = true ] || { echo 'CI runner required.' >&2; exit 1; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
mkdir -p build/ci/bin build/ci/logs
export PATH="$root/build/ci/bin:/usr/local/bin:/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R6/bin:/usr/X11R7/bin:$PATH"
# GNU command names are prefixed on the BSDs. Limit compatibility links to
# this job's private directory; never replace host utilities.
for utility in timeout sha256sum; do
    if ! command -v "$utility" >/dev/null 2>&1; then
        ln -s "$(command -v "g$utility")" "$root/build/ci/bin/$utility"
    fi
done
if ! command -v python3 >/dev/null 2>&1; then
    ln -s "$(command -v python3.12)" "$root/build/ci/bin/python3"
fi
git config --global --add safe.directory "$root"
python3 tools/check_repository.py --tracked
python3 tests/source_archive_safety.py
python3 tests/ci_package_safety.py
bash tests/dependency_snapshot_negative.sh
BUILD_DIRECTORY="$root/build/ci/tests" bash tests/run_tests.sh 2>&1 | tee build/ci/logs/tests.log
OUTPUT_PATH="$root/build/ci/opensesh" bash build_editor.sh 2>&1 | tee build/ci/logs/build.log

display_pid=''
cleanup() {
    if [ -n "$display_pid" ]; then
        kill "$display_pid" 2>/dev/null || true
        wait "$display_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT
if [ "$(uname -s)" != Haiku ]; then
    # A private virtual display exercises the target's real X11 graphics code.
    # It does not supply physical presentation or frame-pacing evidence.
    Xvfb :97 -screen 0 1280x1024x24 -nolisten tcp >build/ci/logs/display.log 2>&1 &
    display_pid=$!
    export DISPLAY=:97
    sleep 2
    kill -0 "$display_pid"
fi
python3 tools/ci_editor_smoke.py build/ci/opensesh build/ci/editor
python3 tools/package_platform.py build/ci/opensesh build/ci/logs/tests.log build/packages
echo 'native_package_gate=pass'

# end of tools/ci_native.sh
