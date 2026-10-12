# Uploadable Lighting Studio profiles: implementation contract

Status: **Mac-side profile compiler/uploader, portable C parser/upload handler,
integer-only renderer, and two-slot storage model pass offline tests.** These
parts are not yet verified as a complete running keyboard firmware. The
installed GMK104 v0.6 runs only its fixed mode-20 rainbow ripple and cannot
accept a profile. Do not send this format to v0.6 or describe profile upload
as available in a release.

## User behavior

Lighting Studio remains the editor. “Save to keyboard” will compile the current
layers and mapping, show any unsupported item, transfer over a wired GMK104
connection, read the result back, and activate it only after verification.
The profile should then run without Lighting Studio, over USB,
Bluetooth, or the 2.4 GHz receiver, and resume after unplug/restart. Saving a
new profile must preserve the last working one if power or radio is lost. The
installed on-keyboard profile and the Mac's editable copy are distinct; edits
in the app are not uploaded until the user selects Save to keyboard.

The uploaded configuration must include all nine existing effects, all 1–16
layers in stack order, enabled state, names, per-layer effect settings, opacity,
blend mode, per-key trigger mask, per-key output mask, “affect all keys,” the
104-key LED mapping and geometry, brightness, and the requested animation rate.
The manual 104-color layout and existing built-in mode are separate modes in
the same format. Mac and Windows Lighting Studio must produce the same binary
for the same profile; a shared test vector should gate both encoders. A layer
with an explicit empty key selection remains inactive,
even when “affect all keys” is checked. For a selected WASD rainbow-ripple layer
with “affect all keys,” the trigger mask contains only WASD and the output mask
contains all 104 LEDs.

The planned firmware must render ripple, rainbow ripple, reactive, wave,
breathing, spectrum, and static color independently. Adaptive music and CPU temperature
need measurements from the connected computer. The computer should send only
bounded bass/mid/treble/level and temperature samples, never 104-key RGB frames
or audio. A stale audio sample becomes zero after 0.5 s; a stale temperature
sample makes that layer transparent after 5 s, matching Lighting Studio's
current behavior. Other layers continue on the keyboard. A profile with no
host-dependent layers needs no running app once uploaded. The UI must explain
this difference before saving.

The existing mode-20 renderer uses roughly 20 ms scheduler ticks. The profile
can carry the Studio FPS selection, but a future firmware must measure and
report its actual safe rate. A 60/90/120 FPS selection cannot be promised on
hardware until its scheduler and LED timing are verified at that rate.

## Version 1 binary

`mac/Sources/OnboardProfile.swift` is the normative Mac encoder and validator.
All multi-byte integers are little-endian. The profile is at most 4064 bytes,
leaving 32 bytes at the end of a proposed 4096-byte flash sector for commit
metadata. The payload CRC is IEEE CRC-32.

The deterministic all-effects, 16-layer cross-platform test vector is
[`mac/Tests/Fixtures/onboard-profile-all-effects-v1.bin`](../../../Tests/Fixtures/onboard-profile-all-effects-v1.bin)
(1514 bytes; SHA-256 `079070E9F573CEAA83FCA171B6205DD67AE6F48BBA9AEFE6B06409D16F1A0F60`).
The Windows encoder and the eventual firmware parser should consume this
exact vector before any hardware upload is offered.

[`onboard_profile.c`](onboard_profile.c) is a no-I/O C parser for the same
format. Its host test accepts this fixture and rejects corrupted checksums,
lengths, key masks, layer IDs and sensor flags. It has not been built for, or
executed on, the keyboard's RISC-V processor.

| Offset | Bytes | Meaning |
| --- | ---: | --- |
| 0 | 4 | `GMKP` |
| 4 | 1 | format version `1` |
| 5 | 1 | mode: studio `0`, built-in `1`, manual colors `2` |
| 6 | 1 | studio layer count `1…16`, otherwise `0` |
| 7 | 1 | built-in effect `0…18` or `20` |
| 8 | 2 | total profile length |
| 10 | 1 | global brightness `0…4` |
| 11 | 1 | requested rate `15`, `30`, `60`, `90`, or `120` Hz |
| 12 | 4 | CRC-32 of payload beginning at offset 32 |
| 16 | 4 | layout tag `A104` |
| 20 | 1 | host-sensor flags: audio bit 0, temperature bit 1 |
| 21 | 11 | zero |
| 32 | 104 | factory scan index to output LED index; a permutation of `0…103` |
| 136 | 208 | x/y centers for output LED `0…103`, in half-key units |
| 344 | variable | mode-specific data |

Manual-color mode adds exactly 312 bytes of RGB in output LED order. Built-in
mode adds nothing. Studio mode adds one record per layer, topmost first:

| Record offset | Bytes | Meaning |
| --- | ---: | --- |
| 0 | 1 | effect ID `0…8` in `OnboardProfile.effectIDs` order |
| 1 | 1 | enabled, affect-all, additive-blend, all-key-selection bits |
| 2 | 2 | speed, unsigned Q8.8 |
| 4 | 1 | intensity, `0…255` |
| 5 | 1 | opacity, `0…255` |
| 6 | 1 | layer brightness `0…4` (reserved for round-trip; global brightness controls LEDs) |
| 7 | 3 | selected RGB color |
| 10 | 2 | music sensitivity, unsigned Q8.8 |
| 12 | 2 | cold/hot CPU thresholds in degrees C |
| 14 | 13 | trigger mask in factory scan order |
| 27 | 13 | output mask in output LED order |
| 40 | 16 | layer UUID |
| 56 | 1 | UTF-8 name byte count `1…80` |
| 57 | variable | UTF-8 name |

The receiver must validate the entire length, CRC, version, all field ranges,
unique LED permutation and layer IDs, legal masks, and absence of trailing
bytes before activating or saving a profile. Unknown versions are rejected.
Quantized speed, intensity, and opacity can differ by one display step from
the Mac preview; firmware needs fixed-point effect math with visual comparison
tests against `LightingRenderer` before claiming effect parity.

## Upload and persistence boundary

The current RGB and Bluetooth commands are not an upload channel. A new
versioned capability query and bounded transfer operations are required. The
Mac must query the capability before writing anything, check the exact
keyboard/firmware identity, transfer numbered chunks with acknowledged offsets,
ask the keyboard to validate the entire image, then request commit and read
the committed length/CRC/profile bytes back. A timeout must never be treated as
success; after reconnect, query which profile is actually active. The transfer
format should allow future 32-byte HID and 20-byte Bluetooth ATT transports,
but the initial persistent-save flow should require wired USB. Telink's BLE
guide warns that sector erase can disrupt radio timing. Wireless profile save
requires separate interruption and timing tests; onboard playback over
Bluetooth and the 2.4 GHz receiver does not require wireless upload. Profile
writes must be serialized with other RGB/sleep commands.

`mac/Sources/OnboardUploader.swift` implements the proposed wired host flow
against a simulated keyboard, but is not exposed in the app. `OnboardTelemetry.swift`
implements small wired music/temperature sample packets with exact active-profile
acknowledgments. They reserve VIA
channel 3, value 7; the existing firmware has no value-7 upload handler.
Every transport reply is exactly 32 bytes, begins with the echoed operation,
`GMKU` and protocol version 1, and is rejected on wrong status or offset.

| Request | Payload after `[kind, 3, 7, operation]` | Verified result |
| --- | --- | --- |
| Query `[8,3,7,0]` | none | flags, max length/chunk, activation-pending byte, active length/full CRC |
| Begin `[7,3,7,1]` | session `u32`, length `u16`, full-profile CRC `u32` | session, next offset `0` |
| Chunk `[7,3,7,2]` | session `u32`, offset `u16`, count `u8`, up to 21 bytes | session, exact next offset |
| Validate `[7,3,7,3]` | session `u32` | full-profile CRC and final offset |
| Commit `[7,3,7,4]` | session `u32` | full-profile CRC and final offset; never retry automatically |
| Read `[8,3,7,5]` | offset `u16`, count `u8`, up to 19 requested bytes | exact saved bytes at offset |
| Activate RAM `[7,3,7,7]` | session `u32` after Validate | active until reboot, without flash writes |
| Music `[7,3,7,8]` | bass, mid, treble, level as four `u8` samples | accepted only for a wired active music layer |
| CPU temperature `[7,3,7,9]` | Celsius × 100 as `u16` | accepted only for a wired active temperature layer |

The host refuses a pre-v1 capability reply before sending Begin, rechecks the
same USB attachment before Validate and Commit, then queries the active record
and waits for the render task to clear activation-pending before comparing every
read-back byte. A new Begin is rejected while activation is pending so its
staging buffer cannot overwrite an in-flight renderer's profile. A lost Commit
reply is indeterminate, so a
future UI must direct the user to reconnect and inspect the active profile.
After full validation and before activation, the Mac selects and verifies
keyboard effect 20 if needed; this is the only stock scheduler entry that runs
the prototype profile renderer. A transfer failure before validation leaves
the currently selected effect untouched.

Store two generations in separate 4 KB sectors. Write and read back the
inactive generation, program its valid/sequence marker last, then select the
newest valid generation at boot. Never erase the active generation during an
upload. If neither validates, boot into a known built-in effect while leaving
typing available. The stock firmware's settings code references sectors
`0x82000…0x87000` and `0x89000…0x8B000`; this does **not** prove any other
sector is blank or reserved. Do not assign flash addresses until the exact
GMK104 flash map and candidate sectors have been checked on the real device.
Keep both slots out of the firmware/OTA, pairing, MAC, and calibration areas.
The [Telink B91 SDK flash documentation](https://doc.telink-semi.cn/doc/en/software/res/sdk/ble/b91_ble_single_connection_en/b91_ble_single_connection_en/)
describes 4 KB erase sectors and 256-byte pages; this must still be reconciled
with the actual GMK104 firmware and chip.

## Acceptance gates

1. Integrate the parser and complete an on-device renderer for all nine effects. Compare
   rendered frames and layer order against Lighting Studio for representative
   profiles, including WASD-only triggers with all-key output and far-edge
   rainbow ripple. Measure worst-case 16-layer render time under key input.
2. Add a RAM-only upload path first. Verify the active profile by readback and
   real key presses over wired USB before enabling any flash write.
3. Prove the flash map, then test both persistent slots and interruption at
   each erase/program/commit stage. Verify typing, stock modes, OTA rollback,
   and profile survival after unplug/reboot.
4. Add the Mac “Save to keyboard” flow and sensor-sample packets. Verify that
   the app shows the keyboard's **read-back** profile and host-sensor status,
   then validate onboard playback over USB, Bluetooth, and 2.4 GHz separately.
5. Any new firmware image needs its own pinned hash/CRC, complete offline
   tests, and explicit owner approval before an attended flash. v0.6 is the
   only installed image verified by the owner for responsive native ripple.
