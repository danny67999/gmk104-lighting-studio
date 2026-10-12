# Complete-profile runtime integration

This directory contains the portable integration core for the requested
complete firmware. It is **not a complete keyboard image or a public release**.
The installed v0.8 diagnostic image remains unchanged; fresh live identity and
storage reads are recorded in `../onboard_v08/STATUS.md`. None of these scripts
opens the keyboard, flashes firmware, or binds the journal to physical sectors.

The runtime connects the existing uploader, integer renderer and two-slot
journal. It handles both key press and release, including remapped keys;
supports all effect IDs 0–17 and up to 16 layers; consumes events before frame
pacing; and starts a validated saved Studio/manual profile without another
host upload. The stock 20 ms scheduler still imposes a 50 FPS ceiling. Music
and temperature remain optional host samples rather than autonomous sensors.

`stored_runtime.c` owns a separate readback buffer alongside the runtime. Its
initialization only reads storage. An empty verified allocation permits a
first save; a read error or generation conflict disables permanent writes.
A failed commit is one-shot and disables permanent capability for the rest
of that boot. The preceding active profile remains immutable until the render
task switches every pointer to the new buffer.

Every valid v1 profile fits in 2,536 bytes: 344 fixed bytes plus sixteen layer
records of 57 bytes and at most 80 name bytes each. The MCU allocates its two
upload buffers and separate journal scratch buffer using this actual bound.
The storage tail remains at offset 4,064 in each 4 KB sector, preserving the
journal format. The new uploader advertises 2,536 bytes; the existing Mac
uploader already checks each actual profile against the advertised limit.

`scan_hook.py` forwards the stock transition state at `gp+0x624` as well as
the factory scan index: `0xFF` means press and zero means release. A full queue
clears held state so a lost release cannot strand a key in its held color.
The callback does no distance calculation in the scan path.

`startup_hook.py` provides a narrow trampoline for the verified stock settings
loader epilogue at `0x20010290`. It invokes a future hardware boot binding,
selects effect 20 only when that binding publishes a valid active profile,
replays the two displaced loads, and resumes the stock stack cleanup. It is
source/assembly only; it has not been patched into an image. The complete
adapter must still restore saved global brightness through the stock lighting
path and initialize once, rather than reloading during every mode change.

## Validation on 2026-10-01

`test.sh` passes AddressSanitizer/UndefinedBehaviorSanitizer checks for remapped
held lighting, release after five seconds, overflow recovery, persistent
roundtrips, a maximum-size 16-layer profile, storage read failures and one-shot
commit failures. Oversized upload/stored lengths are rejected before they can
overrun the bounded MCU buffers. Four instruction-level tests verify the exact stock startup
site, press/release forwarding, fallback behavior, mode selection and register
preservation. The journal suite separately passes 5,643 power-cut points.

```sh
sh mac/Firmware/Patches/onboard_runtime/test.sh
sh mac/Firmware/Patches/onboard_runtime/build_core.sh \
  /private/tmp/xpack-riscv-none-elf-gcc-15.2.0-1 \
  /private/tmp/gmk104-persistent-core
```

The freestanding RV32I/ILP32 build has 16,432 bytes of code/read-only data,
zero initialized data, and 11,308 bytes of static state. Its BSS extends from
`0x92930` to `0x9555C`, below the provisional `0x96000` limit. There are no
unresolved symbols or heap allocations. Compiler stack-usage output accompanies
the ELF; the largest listed core function frame is 208 bytes. These are compile
results, not proof of the vendor heap, interrupt footprint, render timing or
physical boot behavior. The ELF intentionally contains no keyboard image.

See [the stock storage analysis](STOCK-STORAGE-ANALYSIS.md) and
[the completion gates](../COMPLETION-GATES.md) for the remaining hardware work.
