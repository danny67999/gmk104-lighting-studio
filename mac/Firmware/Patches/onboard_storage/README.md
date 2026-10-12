# On-keyboard profile storage reference

**Status: offline model only.** This directory does not produce a GMK104
firmware image, select physical flash addresses, bind hardware flash routines,
or send commands to the keyboard. Live inspection on 2026-10-01 confirms
installed v0.8 (`B6EA62D8`), which accepts uploaded Lighting Studio profiles
in RAM but cannot persist them.

The v1 profile is the existing `GMKP` record validated by
`../native_ripple/onboard_profile.c`: 344–2536 bytes. Every valid v1 layout
fits that bound, including sixteen 80-byte layer names. The sector allowance
is 4064 bytes, with a 32-byte storage tail at offset 4064. Two independent 4 KB sectors would hold an
active and an inactive generation. The caller must map abstract slots 0 and 1
to real sectors **only after** proving those sectors are reserved and are
within the actual keyboard's flash capacity. There are no candidate addresses
in the code.

## Why flash placement is still blocked

The recovered stock application in
`work/gmk104-analysis/decompiled-andes.c` reads, writes, or erases settings in
`0x82000`, `0x83000`, `0x84000`, `0x85000`, `0x86000`, `0x87000`, `0x89000`,
`0x8A000`, and `0x8B000` (around lines 6256–6400). Other code references
`0x81000`, `0xFA000`, `0xFB000`, `0xFE000`, and `0xFF000`. Absence of another
address from that decompilation does not prove its sector is unused: generated
addresses, OTA/bootloader ownership, chip variants, and settings written by
another processor remain possible. The `code_2M` updater resource is a 2 MB
*file*, not proof of the fitted chip's flash size or writable layout.

The installed v0.8 diagnostic provides a bounded read-only storage query.
The live survey on 2026-10-01 identified JEDEC `0x00146085`, reported 1 MB
capacity, and read all 4,096 bytes of each proposed sector at `0x8C000` and
`0x8D000`; both are blank. See `../onboard_v08/STATUS.md` for the digests and
verification limits. This is not a full flash dump. These sectors remain
unallocated until ownership checks are complete; the capacity and current
contents checks have passed. No reinstall is needed for another read-only
survey. A RAM-only profile upload was developed and tested without this
storage decision.

The combined `../onboard_runtime/stored_runtime.c` now uses this journal for
read-only boot restore and one-shot commits through caller-supplied verified
callbacks. It allocates a distinct 2536-byte readback buffer and disables
permanent capability for the boot after an uncertain read/commit. It still
does not allocate or touch physical keyboard sectors.

## Journal format and commit sequence

Each sector holds profile bytes at offset `0…length-1`. Its final 32 bytes,
beginning at `0xFE0`, are:

| Tail offset | Bytes | Value |
| --- | ---: | --- |
| 0 | 4 | `GMKS` |
| 4 | 1 | storage format `1` |
| 5 | 1 | abstract slot index `0` or `1` |
| 6 | 2 | zero |
| 8 | 4 | little-endian generation, wrapping after `UINT32_MAX` |
| 12 | 2 | profile length |
| 14 | 2 | zero |
| 16 | 4 | CRC-32 of the complete profile |
| 20 | 4 | copy of the profile payload CRC at profile offset 12 |
| 24 | 4 | CRC-32 of tail bytes `0…23` |
| 28 | 4 | `CMIT`, programmed **last** |

The reference implementation validates the candidate profile **before any
erase**, scans both existing slots, and erases only the inactive slot. It
programs the candidate without crossing a 256-byte page boundary; reads back
every candidate byte and runs `gmk_profile_validate`; programs and reads back
the first 28 metadata bytes; finally programs the four-byte commit marker.
It rescans before reporting success. The boot scan checks marker, metadata
CRC, full-profile CRC, payload CRC, and the full v1 parser. It chooses the
newer valid generation with modular wraparound. Equal or exactly halfway
generations are ambiguous and fail closed. With no valid slot, firmware should
use a known built-in effect while keeping typing functional.

An interrupted upload may leave either the old generation or a fully
validated new generation active. The host must rescan after reconnect; it must
not infer success or retry a write from a timeout. The two-sector rule protects
an active profile from interruption; it does not establish that any particular
physical sectors are safe to erase. Firmware integration must also prove flash
driver behavior, page limits, radio/USB timing, available RAM for the parser,
and that the bootloader/stock firmware never erases the selected sectors.

Run the offline test from the repository root with:

```sh
sh mac/Firmware/Patches/onboard_storage/test.sh
```

The test uses an in-memory NOR-flash simulator, the Mac-generated 16-layer
fixture, AddressSanitizer, and UndefinedBehaviorSanitizer. It verifies first
save, replacement, readback, corrupt input rejection before erase, failed
reads, silent write corruption, CRC fallback, generation wraparound, and every
byte boundary across one replacement's erase/profile/metadata/commit stages
(5,643 simulated power cuts). It does **not** establish hardware reliability.
