#!/bin/sh
set -eu
cd "$(dirname "$0")/../../../.."
test_directory=$(mktemp -d /tmp/gmk104-runtime-test.XXXXXX)
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM
cc -std=c11 -Wall -Wextra -Werror -pedantic -fsanitize=address,undefined \
  mac/Firmware/Patches/native_ripple/onboard_profile.c \
  mac/Firmware/Patches/native_ripple/onboard_upload_device.c \
  mac/Firmware/Patches/native_ripple/renderer_fixed.c \
  mac/Firmware/Patches/onboard_storage/onboard_storage.c \
  mac/Firmware/Patches/onboard_runtime/runtime.c \
  mac/Firmware/Patches/onboard_runtime/stored_runtime.c \
  mac/Firmware/Patches/onboard_runtime/test_runtime.c \
  -o "$test_directory/test_runtime"
"$test_directory/test_runtime"
PYTHONDONTWRITEBYTECODE=1 python3 mac/Firmware/Patches/onboard_runtime/test_scan_hook.py
