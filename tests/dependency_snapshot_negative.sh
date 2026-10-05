#!/usr/bin/env bash
# Project: OpenSesh
# File: tests/dependency_snapshot_negative.sh
# Purpose: exercise the GUI release subset's integrity and path boundaries.
# Responsibilities: mutate one private payload copy and require specific errors.
# This file does not modify the vendored source or historical development files.

set -eu
export LC_ALL=C
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
verifier="$project_root/tests/verify_dependency_snapshot.sh"
vendor_source="$project_root/vendor/omaGui"
bash "$verifier" "$vendor_source"
work_root=$(mktemp -d "${TMPDIR:-/tmp}/opensesh-dependency-check.XXXXXXXX")
# The only recursive cleanup target is the directory returned by mktemp above.
trap 'rm -rf -- "$work_root"' EXIT
vendor="$work_root/omaGui"
mkdir "$vendor"
tr -d '\r' < "$vendor_source/SNAPSHOT.sha256" > "$vendor/SNAPSHOT.sha256"
cp -- "$vendor_source/DEPENDENCY.md" "$vendor/DEPENDENCY.md"
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    path=${line:66}
    mkdir -p -- "$vendor/$(dirname -- "$path")"
    cp -- "$vendor_source/$path" "$vendor/$path"
done < "$vendor/SNAPSHOT.sha256"
cp -- "$vendor/SNAPSHOT.sha256" "$work_root/manifest"
bash "$verifier" "$vendor"
awk '{ printf "%s\r\n", $0 }' "$work_root/manifest" > "$vendor/SNAPSHOT.sha256"
bash "$verifier" "$vendor"
cp -- "$work_root/manifest" "$vendor/SNAPSHOT.sha256"

expect_rejection()
{
    local name=$1 message=$2
    if bash "$verifier" "$vendor" > "$work_root/result" 2>&1; then
        echo "Dependency corruption was accepted: $name" >&2
        exit 1
    fi
    if ! grep -Fq -- "$message" "$work_root/result"; then
        cat "$work_root/result" >&2
        echo "Dependency failure did not identify $name." >&2
        exit 1
    fi
    echo "dependency_negative_case=$name"
}

first_line=$(awk '!/^#/ && NF { print; exit }' "$work_root/manifest")
printf '%s\n' "$first_line" >> "$vendor/SNAPSHOT.sha256"
expect_rejection duplicate 'Duplicate release dependency path'
cp -- "$work_root/manifest" "$vendor/SNAPSHOT.sha256"
printf '%064d  ../outside\n' 0 > "$vendor/SNAPSHOT.sha256"
expect_rejection unsafe 'Unsafe dependency path'
cp -- "$work_root/manifest" "$vendor/SNAPSHOT.sha256"

payload=omaGUI.bi
mv -- "$vendor/$payload" "$work_root/payload"
expect_rejection missing 'Dependency payload is missing'
cp -- "$work_root/payload" "$vendor/$payload"
printf '\nchanged\n' >> "$vendor/$payload"
expect_rejection changed 'FAILED'
mv -- "$work_root/payload" "$vendor/$payload"

: > "$vendor/extra.txt"
expect_rejection extra 'Unreviewed file'
rm -- "$vendor/extra.txt"
ln -s -- "$vendor/$payload" "$vendor/extra-link"
expect_rejection file_link 'Symbolic link'
rm -- "$vendor/extra-link"
ln -s -- "$vendor_source/src" "$vendor/link-directory"
expect_rejection directory_link 'Symbolic link'
rm -- "$vendor/link-directory"
printf '%064d  assets/fonts/font_arial_10.bi\n' 0 >> "$vendor/SNAPSHOT.sha256"
expect_rejection historical_font 'Historical font is in the release payload'
cp -- "$work_root/manifest" "$vendor/SNAPSHOT.sha256"
bash "$verifier" "$vendor"
echo 'dependency_negative_cases=8'
echo 'dependency_negative_status=ok'

# end of tests/dependency_snapshot_negative.sh
