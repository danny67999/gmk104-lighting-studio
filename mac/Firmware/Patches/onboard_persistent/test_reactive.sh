#!/bin/sh
set -eu
cd "$(dirname "$0")/../../../.."
checks=$(mktemp -d /tmp/gmk104-perf-tests.XXXXXX)
trap 'rm -rf "$checks"' EXIT HUP INT TERM
shared="mac/Firmware/Patches/native_ripple/onboard_profile.c mac/Firmware/Patches/native_ripple/onboard_upload_device.c mac/Firmware/Patches/native_ripple/renderer_fixed.c mac/Firmware/Patches/onboard_runtime/runtime.c"
cc -std=c11 -Wall -Wextra -Werror -pedantic -DGMK_COOPERATIVE_RENDER -DGMK_EXTENDED_REACTIVE -fsanitize=address,undefined $shared mac/Firmware/Patches/onboard_persistent/test_reactive.c -o "$checks/render"
"$checks/render"
cc -std=c11 -Wall -Wextra -Werror -pedantic -DGMK_COOPERATIVE_RENDER -DGMK_EXTENDED_REACTIVE -DGMK_PERSISTENT_HOST_TEST -fsanitize=address,undefined $shared mac/Firmware/Patches/onboard_storage/onboard_storage.c mac/Firmware/Patches/onboard_runtime/stored_runtime.c mac/Firmware/Patches/onboard_persistent/flash_binding.c mac/Firmware/Patches/onboard_persistent/performance_adapter.c mac/Firmware/Patches/onboard_persistent/test_reactive_persistence.c -o "$checks/storage"
"$checks/storage"
PYTHONDONTWRITEBYTECODE=1 python3 mac/Firmware/Patches/onboard_persistent/test_performance_hooks.py
