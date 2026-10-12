#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)
cd "$root"
output="${TMPDIR:-/tmp}/gmk104-renderer-test-$$"
trap 'rm -f "$output"' EXIT HUP INT TERM

"${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror -pedantic \
    mac/Firmware/Patches/native_ripple/onboard_profile.c \
    mac/Firmware/Patches/native_ripple/renderer.c \
    mac/Firmware/Patches/native_ripple/renderer_fixed.c \
    mac/Firmware/Patches/native_ripple/renderer_test.c \
    -lm -o "$output"
"$output"
