#!/bin/sh
set -eu
cd "$(dirname "$0")/../../../.."
test_directory=$(mktemp -d /tmp/gmk104-persistent-test.XXXXXX)
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM
cc -std=c11 -Wall -Wextra -Werror -pedantic -DGMK_PERSISTENT_HOST_TEST \
 -fsanitize=address,undefined \
 mac/Firmware/Patches/native_ripple/onboard_profile.c \
 mac/Firmware/Patches/native_ripple/onboard_upload_device.c \
 mac/Firmware/Patches/native_ripple/renderer_fixed.c \
 mac/Firmware/Patches/onboard_storage/onboard_storage.c \
 mac/Firmware/Patches/onboard_runtime/runtime.c \
 mac/Firmware/Patches/onboard_runtime/stored_runtime.c \
 mac/Firmware/Patches/onboard_persistent/flash_binding.c \
 mac/Firmware/Patches/onboard_persistent/device_adapter.c \
 mac/Firmware/Patches/onboard_persistent/test_persistence.c \
 -o "$test_directory/test_persistent"
"$test_directory/test_persistent"
PYTHONDONTWRITEBYTECODE=1 python3 mac/Firmware/Patches/onboard_persistent/test_build.py
PYTHONDONTWRITEBYTECODE=1 python3 mac/Firmware/Patches/onboard_persistent/test_hooks.py
