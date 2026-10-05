#!/usr/bin/env bash

# Project: OpenSesh
# ----------------------------
#
# File: tests/fbc_sanitized.sh
#
# Purpose:
#
#     Compile Linux test and application targets with checked FreeBASIC
#     runtime behavior plus GCC address and undefined-behavior sanitizers.
#
# Responsibilities:
#
#     - preserve the normal compiler command line supplied by build scripts
#     - enable FreeBASIC bounds and runtime checks
#     - link AddressSanitizer and UndefinedBehaviorSanitizer into each target
#     - reject generated-C paths that GCC cannot prove are initialized
#
# This file intentionally does NOT contain:
#
#     - source selection
#     - test execution
#     - package installation

set -eu

compiler_path=${OSE_SANITIZER_FBC:-/usr/bin/fbc}

if [ ! -x "$compiler_path" ]; then
    echo "FreeBASIC compiler was not found: $compiler_path" >&2
    exit 1
fi

exec "$compiler_path" \
    -exx \
    -gen gcc \
    -Wc -fsanitize=address,-fsanitize=undefined,-fno-omit-frame-pointer,-O1,-Werror=maybe-uninitialized \
    -l asan \
    -l ubsan \
    "$@"

# end of tests/fbc_sanitized.sh
