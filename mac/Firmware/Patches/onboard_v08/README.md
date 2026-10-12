# GMK104 v0.8: local read-only storage diagnostic

**Current status (2026-10-01): v0.8 is installed and live USB identity/storage reads are verified.**
Fresh inspection reports CRC `B6EA62D8`. The read-only survey reports a 1 MB
chip (`JEDEC 0x00146085`) and two blank candidate sectors. See [STATUS.md](STATUS.md).
The earlier claim that v0.8 was never installed was stale and is superseded.
This diagnostic is a small extension of v0.7; it is not the persistent-profile release. It still accepts
up to 16 layered profiles in RAM and loses them when power is removed.

The factory rainbow wave proves that built-in effect settings can survive a
restart. It does not establish an available location for a larger uploaded
profile. Stock settings use sectors beginning at `0x82000`, including indexed
records through `0x8B000`; writing to an unverified sector could overwrite
settings, pairing data, or firmware-owned storage.

The v0.8 addition is a bounded, wired-only GET command `[8,3,7,6]`. It reports
the flash JEDEC ID and reads only 4 KB each at candidate addresses `0x8C000`
and `0x8D000`, in chunks of at most 18 bytes. It rejects unknown flash sizes,
wireless mode, out-of-range reads, and nonzero trailing request bytes. The
new diagnostic code contains no flash erase or program call, and the profile uploader
does not advertise persistence. The Mac installer reduces returned sectors to
blank/nonblank status and SHA-256 digests without saving raw bytes.

These addresses are *candidates*, not allocated slots. A sector that appears
blank once is not evidence that another keyboard feature will never use it.
Before adding flash writes, compare the stock firmware's full address use,
inspect the live flash ID and candidate-sector digests, and verify keyboard
behavior across startup, sleep, wired, Bluetooth, and 2.4 GHz modes.

## Offline reproduction

From the project root, with the pinned xPack RV32 toolchain in `/private/tmp`:

```sh
sh mac/Firmware/Patches/onboard_v08/build_offline.sh \
  /private/tmp/xpack-riscv-none-elf-gcc-15.2.0-1 \
  mac/.build/onboard-v08
bash mac/Firmware/test-v08-local-staging.sh
bash mac/Firmware/build-v08-local-test.sh
```

The candidate image is 159,588 bytes, CRC `B6EA62D8`, SHA-256
`005DFCBCA508610AFE4231BE3AEC4399572B8CF765B9CD8BE4696F3D705AB507`.
The separate signed installer contains that exact image and the verified v0.7
rollback. Its `Read storage sectors (no changes)` control becomes available
only when a wired keyboard is identified as running v0.8. The offline build
and tests do not contact the keyboard or approve a firmware update.

Any future firmware installation requires separate, explicit approval of its
exact image. The current keyboard already has v0.8; do not reinstall it just
to obtain this read-only survey. A successful blank read does not approve a
permanent profile write or prove ownership of the proposed sectors.
