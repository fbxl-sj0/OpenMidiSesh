#!/usr/bin/env bash
# Project: OpenSesh
# File: tests/verify_dependency_snapshot.sh
#
# Purpose:
#     Verify the byte-pinned GUI release subset and optional full local tree.
# Responsibilities:
#     - reject unsafe, duplicate, missing, extra and changed payload paths
#     - verify release licenses and exclude historical font conversions
#     - support a fresh checkout and the larger shared development tree
# This file intentionally does NOT contain package installation or updates.

set -eu
export LC_ALL=C
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vendor_root=${1:-"$project_root/vendor/omaGui"}
if [ ! -d "$vendor_root" ]; then
    echo "GUI dependency directory was not found: $vendor_root" >&2
    exit 1
fi
vendor_root=$(CDPATH= cd -- "$vendor_root" && pwd)
for executable in sha256sum tr find mktemp grep; do
    command -v "$executable" >/dev/null 2>&1 || {
        echo "Dependency verification needs $executable." >&2
        exit 1
    }
done

normalized_manifest=$(mktemp "${TMPDIR:-/tmp}/opensesh-manifest.XXXXXXXX")
payload_list=''
trap 'rm -f -- "$normalized_manifest" "$payload_list"' EXIT
payload_list=$(mktemp "${TMPDIR:-/tmp}/opensesh-payload.XXXXXXXX")
declare -A release_paths=()
declare -A tree_paths=()

read_manifest()
{
    local manifest=$1
    local kind=$2
    local line path
    if [ ! -f "$manifest" ]; then
        echo "Required dependency manifest was not found: $manifest" >&2
        return 1
    fi
    # Only metadata is normalized. Hashed payload bytes remain unchanged.
    tr -d '\r' < "$manifest" > "$normalized_manifest"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|'#'*) continue ;; esac
        if ! [[ $line =~ ^[0-9a-f]{64}\ \ [\ -~]+$ ]]; then
            echo "Malformed dependency manifest line in $manifest." >&2
            return 1
        fi
        path=${line:66}
        case "$path" in
            /*|*\\*|*:*|..|../*|*/../*|*/..|./*|*/./*|*/.|*//*|*/)
                echo "Unsafe dependency path: $path" >&2
                return 1
                ;;
        esac
        if [ "$kind" = release ]; then
            if [[ -n ${release_paths[$path]+present} ]]; then
                echo "Duplicate release dependency path: $path" >&2
                return 1
            fi
            case "$path" in
                *font_arial*|*font_data_impl.bi)
                    echo "Historical font is in the release payload: $path" >&2
                    return 1
                    ;;
            esac
            release_paths[$path]=1
        else
            if [[ -n ${tree_paths[$path]+present} ]]; then
                echo "Duplicate development dependency path: $path" >&2
                return 1
            fi
            tree_paths[$path]=1
        fi
        if [ ! -f "$vendor_root/$path" ] || [ -L "$vendor_root/$path" ]; then
            echo "Dependency payload is missing or is a symbolic link: $path" >&2
            return 1
        fi
    done < "$normalized_manifest"
    (cd -- "$vendor_root" && sha256sum --quiet --check "$normalized_manifest")
}

read_manifest "$vendor_root/SNAPSHOT.sha256" release
if [ "${#release_paths[@]}" -eq 0 ]; then
    echo 'The GUI release manifest is empty.' >&2
    exit 1
fi
if [ -f "$vendor_root/TREE.sha256" ]; then
    read_manifest "$vendor_root/TREE.sha256" tree
    for path in "${!release_paths[@]}"; do
        if [[ -z ${tree_paths[$path]+present} ]]; then
            echo "Release payload is absent from the development tree: $path" >&2
            exit 1
        fi
    done
    expected_count=${#tree_paths[@]}
    for path in DEPENDENCY.md SNAPSHOT.sha256; do
        if [[ -z ${tree_paths[$path]+present} ]]; then
            echo "Development manifest omits metadata: $path" >&2
            exit 1
        fi
    done
else
    expected_count=${#release_paths[@]}
fi

actual_count=0
# Materialize enumeration so a failed find is not hidden by process substitution.
# Links are rejected even when they add no regular file to the payload count.
find "$vendor_root" \( -type f -o -type l \) -print0 > "$payload_list"
while IFS= read -r -d '' file; do
    relative=${file#"$vendor_root/"}
    if [ -L "$file" ]; then
        echo "Symbolic link in the GUI dependency tree: $relative" >&2
        exit 1
    fi
    case "$relative" in DEPENDENCY.md|SNAPSHOT.sha256|TREE.sha256) continue ;; esac
    if [ -f "$vendor_root/TREE.sha256" ]; then
        if [[ -z ${tree_paths[$relative]+present} ]]; then
            echo "Unreviewed file in the GUI development tree: $relative" >&2
            exit 1
        fi
    elif [[ -z ${release_paths[$relative]+present} ]]; then
        echo "Unreviewed file in the GUI release subset: $relative" >&2
        exit 1
    fi
    actual_count=$((actual_count + 1))
done < "$payload_list"
# TREE includes the two other metadata documents as payload entries.
if [ -f "$vendor_root/TREE.sha256" ]; then
    expected_count=$((expected_count - 2))
fi
if [ "$actual_count" -ne "$expected_count" ]; then
    echo "GUI payload count mismatch: expected=$expected_count actual=$actual_count" >&2
    exit 1
fi

for path in DEPENDENCY.md LICENSE assets/fonts/FONTS.md assets/fonts/OFL-1.1.txt \
    LICENSES/Cascadia-Mono-OFL.txt LICENSES/LGPL-2.1.txt \
    LICENSES/Noto-CJK-OFL.txt LICENSES/Noto-Sans-OFL.txt \
    LICENSES/Spleen-BSD-2-Clause.txt omaGUI.bi; do
    if [ ! -f "$vendor_root/$path" ]; then
        echo "Required GUI attribution file was not found: $path" >&2
        exit 1
    fi
done
for path in "${!release_paths[@]}"; do
    case "$path" in *.bas|*.bi|*.md|*.txt)
        if grep -Eiq 'arialbd?\.ttf|C:\\Windows\\Fonts\\arial' "$vendor_root/$path"; then
            echo "Historical font conversion appears in release input: $path" >&2
            exit 1
        else
            grep_status=$?
            if [ "$grep_status" -ne 1 ]; then
                echo "Could not inspect dependency attribution: $path" >&2
                exit 1
            fi
        fi
        ;;
    esac
done

echo 'omagui_snapshot=ok'
echo "omagui_payload_files=${#release_paths[@]}"
echo 'omagui_licenses=MIT,OFL-1.1,LGPL-2.1-or-later,BSD-2-Clause'
echo 'windows_font_conversions=absent'
echo 'dependency_snapshot_status=ok'

# end of tests/verify_dependency_snapshot.sh
