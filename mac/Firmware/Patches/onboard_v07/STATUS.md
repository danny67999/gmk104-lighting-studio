# GMK104 v0.7 onboard profile candidate

**Unreleased hardware-test build, now installed on the owner's keyboard.**
Wired read-only inspection on September 30 verified its CRC `D79CC2E1` after
the owner installed it. The owner confirmed responsive onboard effects; the
reactive/ripple mismatch was traced to an older Mac app and resolved by using
the matching Lighting Studio build. The 16-layer and speed behavior has passed
offline tests, but a physical 16-layer stress test and persistent storage are
still outstanding.

Current image, built September 30, 2026 from the present C/assembler sources:

| Item | Value |
| --- | --- |
| Path | `mac/.build/onboard-v07/GMK104-v0.7-OFFLINE-CANDIDATE.bin` |
| Size | 159,124 bytes |
| SHA-256 | `871e0afec8c22b80432a703a8f4773caf7a0d59494ebe18b1d00bf1b0dfdf027` |
| Firmware CRC | `D79CC2E1` |
| Payload SHA-256 | `5b4b9b2d1983dbcacbb42d8aca87a70ce08064aa8469bb3014ce0355a2c31257` |
| Linked BSS end | `0x95714` (11,748-byte payload BSS) |

The ignored `mac/.build` path keeps this experimental image out of Git and the
normal user-facing installer. A separate, locally staged trial installer is
documented in [LOCAL-V07-TRIAL.md](../../LOCAL-V07-TRIAL.md). To reproduce from
the repository root with the verified
xPack RISC-V GCC 15.2.0-1 darwin-arm64 toolchain (publisher archive SHA-256
`6588E8351455FAD8ACA37551F0E5A5543F3346BFA9A837CF03CBD3BDD4989F8F`):

```sh
sh mac/Firmware/Patches/onboard_v07/build_offline.sh \
  /private/tmp/xpack-riscv-none-elf-gcc-15.2.0-1 \
  mac/.build/onboard-v07
```

The candidate accepts custom Studio profiles **over wired USB into RAM**,
validates and reads them back, and renders layers/per-key effects in effect 20.
Wired music/CPU effects use small scalar samples. Settings vanish after power
loss; permanent flash Commit is unavailable. Without an active custom profile,
effect 20 falls back to the verified v0.6 ripple. Built-in-mode profiles are
rejected until stock-effect delegation is proven. Bluetooth/2.4 GHz profile
transfer and telemetry are not implemented. Requested 60/90/120 FPS is capped
at the stock scheduler's approximately 50 FPS.

Verification completed: exact v0.6 source identity, image CRC and patch-site
tests; RV32I hook instruction tests including register preservation; linked
RV32I/ILP32 payload with no initialized `.data`, relocations, or undefined
symbols; and host AddressSanitizer/UndefinedBehaviorSanitizer tests of upload,
activation, remapped W-key ripple, scalar telemetry, and fail-closed built-in
profiles. The reproducible build is in
[build_offline.sh](build_offline.sh); the instruction and integration checks are
in [test_hooks.py](test_hooks.py) and
[test_device_adapter.c](test_device_adapter.c).

An attended, explicitly approved first hardware test would accept unmeasured
MCU timing risk and use the v0.6 fallback and a simple profile first. It must
retain a proven rollback path and check boot, keyscan, USB, and actual
RAM/heap/stack headroom. Measure render and queued key-processing time before
trying stress profiles or offering a release. Persistent storage additionally
needs a verified flash map and power-loss testing. No timer register or CSR is
currently verified for on-device timing diagnostics. A source change to any
linked C file, build script, or pinned input invalidates the hashes above;
rebuild and update this status first.
