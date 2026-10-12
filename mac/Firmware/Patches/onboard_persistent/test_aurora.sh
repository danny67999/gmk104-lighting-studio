#!/bin/sh
set -eu
cd "$(dirname "$0")/../../../.."
checks=$(mktemp -d /tmp/gmk104-aurora-tests.XXXXXX)
trap 'rm -rf "$checks"' EXIT HUP INT TERM
cc -std=c11 -Wall -Wextra -Werror -pedantic -DGMK_COOPERATIVE_RENDER -DGMK_EXTENDED_REACTIVE -DGMK_MATRIX_RAIN -DGMK_MATRIX_COLUMNS -DGMK_AURORA_MATCH -fsanitize=address,undefined -I mac/Firmware/Patches/native_ripple mac/Firmware/Patches/native_ripple/onboard_profile.c mac/Firmware/Patches/native_ripple/onboard_upload_device.c mac/Firmware/Patches/native_ripple/renderer_fixed.c mac/Firmware/Patches/onboard_persistent/test_aurora.c -o "$checks/aurora"
"$checks/aurora"
