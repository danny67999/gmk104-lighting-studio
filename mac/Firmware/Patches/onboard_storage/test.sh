#!/bin/sh
set -eu
cd "$(dirname "$0")/../../../.."
test_directory=$(mktemp -d /tmp/gmk104-onboard-storage-test.XXXXXX)
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM
cc -std=c11 -Wall -Wextra -Werror -pedantic -fsanitize=address,undefined \
  mac/Firmware/Patches/native_ripple/onboard_profile.c \
  mac/Firmware/Patches/onboard_storage/onboard_storage.c \
  mac/Firmware/Patches/onboard_storage/test_onboard_storage.c \
  -o "$test_directory/test_onboard_storage"
"$test_directory/test_onboard_storage"
