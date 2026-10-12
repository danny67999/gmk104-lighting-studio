# Complete on-keyboard firmware: current gates

Fresh live inspection on 2026-10-01 confirms installed v0.8 CRC `B6EA62D8`.
The owner corrected the earlier stale v0.7 installation assumption. v0.8
renders uploaded compatible profiles in RAM. Power loss clears the profile.
Do not label the v0.8 read-only survey or the current C renderer as a
complete persistent firmware, and do not install either as a release.

Implemented and checked offline:

- The v1 profile format encodes up to 16 layers with per-key trigger/output
  masks, independent effect speed, color, brightness, opacity and blend mode.
- The integer C renderer implements held-key lighting and eight additional
  animations. Host tests cover release, trigger selection, whole-board reach,
  bounded key events and changing frames. The existing hardware image does
  not contain these renderer additions.
- The two-slot storage journal validates and reads back a profile before
  writing a final commit marker. Simulation covers 5,643 power-cut points.
- The combined `onboard_runtime` core restores a maximum-size 16-layer
  journal profile on simulated boot, forwards both press and release, and
  disables persistent writes after uncertain storage reads/commits. Its
  freestanding RV32 build uses 11,308 BSS bytes, ending at `0x9555C` within
  the provisional memory cap. Instruction tests verify the proposed stock
  startup trampoline. No physical binding or full image was produced.
- The explicitly supplied GMK104 stock image matches the local and PC copies
  (140,244 bytes; stock CRC `B85531A2`). The stock initializers identify OTA
  bases `0`/`0x40000` and raw read/program callbacks. The supplied larger
  resources are padded updater files, not physical flash dumps. Details are
  in `onboard_runtime/STOCK-STORAGE-ANALYSIS.md`.
- The installed v0.8 diagnostic now completed a live read-only survey:
  JEDEC `0x00146085`, capacity 1 MB, and 4,096 erased bytes in each candidate
  `0x8C000`/`0x8D000` sector. Both hashes are
  `F47A8EC3E9AFF2318D896942282AD4FE37D6391C82914F54A5DA8A37DE1300C6`.
  No firmware install, sector erase/program or profile commit was performed.
- Mac app 1.6.4 exports/imports a portable lighting profile with its LED map
  and rejects new effect IDs on older connected firmware before writing.

## Complete image now built; physical validation remains

On 2026-10-01, `onboard_persistent` produced a full feature image, CRC
`D51110C3`, with physical flash binding, guarded allocation, boot selection,
saved brightness and press/release hooks. The normal installer 1.3.0 bundles
it and the exact v0.8 rollback. See `onboard_persistent/README.md` for the
allocation decision, tests and limits. No new firmware or persistent profile
has been written to the target.

The earlier requirement for a complete vendor allocation map was replaced by
an explicitly reverse-engineered allocation with live chip/OTA/BLE-pointer
checks, unfamiliar-data refusal and per-sector reservation records. This is
not a claim that all vendor ROM behavior is known. Source and simulator checks
now cover integration; physical power-cycle, typing, wireless and sleep tests
still gate a verified release.

Earlier implementation checklist (superseded by the built image where noted):

1. Establish ownership of two 4 KB sectors from stock/ROM address tracing or
   authoritative vendor documentation. Live chip capacity and current blank
   sector contents are now established. Decompiled stock code
   uses settings sectors `0x82000` through `0x8B000`; the proposed `0x8C000`
   and `0x8D000` are blank but their ownership remains unverified; do not
   erase them based only on that observation.
2. Bind the journal to verified flash read/erase/program routines, prove page
   limits and timing, and reserve enough MCU RAM for its separate readback
   buffer without colliding with the stock heap or stack. The separate
   portable readback buffer now fits the provisional BSS cap; live stock
   heap/interrupt bounds and hardware driver timing are still unverified.
3. Route both key-down and key-up transitions from the stock scan hook to the
   renderer. The new source and instruction tests cover both transitions;
   the installed v0.8 image still forwards key-down only.
4. Load a validated journal profile on boot and select the custom effect at
   startup. The installed init path starts only when effect 20 is selected; a saved
   record alone cannot guarantee lighting resumes after unplugging. The new
   source includes a pinned startup-selection trampoline and a read-only
   restore core, but they still require the physical flash adapter, saved
   brightness integration and full-image/hardware validation.
5. Build and pin one exact full image, add it to the normal Mac installer,
   verify OTA transfer/rollback and physical typing, lighting, sleep and
   power-cycle behavior on the GMK104. A compiled image is not hardware proof.

The existing installed v0.8 read command resolves the capacity/current-contents
question without another diagnostic installation. It does not replace an
allocation/ownership check or provide a full physical flash dump. Until that
allocation and the remaining integration/target checks are complete, the installed v0.8 continues to advertise RAM-only capability. The new guarded
image enables permanent capability only when its allocation checks succeed;
it still requires exact-image approval and physical validation before release.
