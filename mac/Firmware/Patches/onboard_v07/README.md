# v0.7 onboard-profile candidate: offline integration

**Status: unreleased hardware-test candidate. No keyboard test or flash approval yet.**
The pinned v0.6 image remains the installed, owner-tested firmware. This
directory adds a reproducible integration path for the Mac profile encoder,
portable upload handler, and integer-only on-keyboard renderer. The candidate
has never booted on a keyboard; a valid CRC is not hardware proof.

## What the current candidate implements

- Starts from the exact v0.6 image (SHA-256
  `5A656E2295EC69D20562B11478F5CBF6D0F732D9C7E04C1C4A6B95EDEFC2FF51`).
  The builder verifies its length, full-image CRC, hook targets, and BSS
  instruction before modifying it. Stock HID, OTA, Bluetooth, and 2.4 GHz
  command handlers are left in place, with narrow trampolines for VIA channel
  3/value 7, the key-down scan site, and effect 20.
- Offers a **wired USB, RAM-only** profile transfer. The device validates all
  chunks and the full profile; Activate swaps two buffers and makes the next
  Begin wait until the render task has switched to the new buffer. Query and
  readback expose the active length/CRC/profile. There is no flash commit
  callback, so persistent Commit returns a failure and no settings sector is
  touched. Unplugging/power loss loses the profile.
- In effect 20, renders Studio layers or a manual 104-color frame using the
  integer-only reference in `../native_ripple/renderer_fixed.c`. With no active
  profile it falls back to the verified v0.6 ripple. A built-in-mode profile is
  rejected on RAM Activate until stock-effect delegation is proven.
- Accepts bounded **wired USB** music and CPU-temperature scalar samples on
  value-7 subcommands 8/9. It never streams per-key RGB frames for those
  effects. The scan callback queues key indices; the effect task performs the
  heavier 104-distance preparation and consumes validated telemetry.
- Uses the stock ~20 ms effect scheduler. Requested 15/30 FPS is approximated
  with skipped ticks; 60/90/120 FPS is capped at roughly 50 FPS. Actual MCU
  throughput remains unmeasured.

The profile's "factory scan index" is the same index used by the vendor's
default LED map. The hooked scan value `a0` carries that factory LED index;
`default-led-map.json` assigns W/A/S/D indices 39/58/59/60, matching the
tested v0.6 trigger values. The new renderer applies the uploaded
scan-to-output permutation once. The focused host test swaps W to LED 103 and
checks that only the remapped origin lights when W is pressed. Physical
coverage of all 104 keys still needs a keyboard test.

## Reproduce, without hardware

The local Mac did not contain a RISC-V compiler. We downloaded the publisher's
[xPack GNU RISC-V Embedded GCC 15.2.0-1 arm64 release](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/tag/v15.2.0-1)
into `/private/tmp`, verified the [publisher package manifest](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/blob/xpack/package.json)
SHA-256 `6588E8351455FAD8ACA37551F0E5A5543F3346BFA9A837CF03CBD3BDD4989F8F`,
and extracted it there. No Homebrew package or system toolchain was installed.
The source is compiled `rv32i/ilp32`, freestanding, without initialized C
globals, newlib startup, or unresolved linker symbols. The linker script is
generated from the pinned v0.6 layout and asserts that `.data` is empty.

From the repository root:

```sh
sh mac/Firmware/Patches/onboard_v07/build_offline.sh \
  /private/tmp/xpack-riscv-none-elf-gcc-15.2.0-1 \
  mac/.build/onboard-v07
```

The ignored `mac/.build/onboard-v07/` directory contains the candidate `.bin`,
payload ELF, map, disassembly, and exact hash/CRC manifest. The script never
opens the HID device or copies the image into the normal installer resources.
A separate local trial installer is staged as described in
[LOCAL-V07-TRIAL.md](../../LOCAL-V07-TRIAL.md), but it has not been used to
write to the keyboard.
`test_build.py` verifies source identity, patched-site inventory, size and
CRC; `test_hooks.py` executes the RV32 trampolines for scan, get/set, init,
render, and BSS growth and tests register preservation. The host adapter test
checks RAM upload, activation handoff, remapped W trigger, scalar samples, and
built-in rejection under AddressSanitizer/UndefinedBehaviorSanitizer:

```sh
clang -std=c11 -O1 -g -fsanitize=address,undefined \
  -fno-omit-frame-pointer -DGMK_V07_HOST_TEST \
  -I mac/Firmware/Patches/native_ripple \
  mac/Firmware/Patches/onboard_v07/test_device_adapter.c \
  mac/Firmware/Patches/onboard_v07/device_adapter.c \
  mac/Firmware/Patches/native_ripple/onboard_profile.c \
  mac/Firmware/Patches/native_ripple/onboard_upload_device.c \
  mac/Firmware/Patches/native_ripple/renderer_fixed.c \
  -o /private/tmp/gmk104-v07-host-test-sanitized
/private/tmp/gmk104-v07-host-test-sanitized
```

## Gates before an attended keyboard test

1. Measure the worst-case 16-layer render and queued key-down processing on
   the actual RV32 MCU. Host timing does not bound device cycles. An overrun
   could delay scanning, USB, or radio work. The integer renderer approximates
   some curves; compare its physical output with Lighting Studio, including a
   ripple crossing the whole board.
2. Prove the extended BSS range and vendor heap/stack use do not collide.
   The current payload uses roughly 11.8 KB beyond v0.6 BSS and retains more
   than 40 KB below the documented stack top, but the live heap/interrupt
   footprint is not yet known.
3. Inspect and test the VIA, scanner, and effect-task call contexts on the
   keyboard. The hook tests emulate RV32 instructions, not Telink custom
   instructions, interrupts, timing, USB radio behavior, or a full boot.
4. Add persistent profile storage only after the actual flash map is proved.
   The portable A/B storage model in `../onboard_storage/` is not linked here;
   no sector address is assumed. Verify power-loss recovery and readback before
   advertising Save to keyboard.
5. Add and test stock built-in profile delegation and scalar telemetry over
   Bluetooth/2.4 GHz if those are to work without USB. The current custom GATT
   allowlist does not carry value-7 upload/sensor packets. Re-test sleep/wake,
   every key, stock effects, rollback, and all three connection modes.

Only after those gates and an explicit owner-approved attended test should
this become a released firmware version. The staged trial installer is for
that controlled test; it is not a public release.
