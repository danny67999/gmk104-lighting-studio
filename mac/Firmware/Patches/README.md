# Experimental GMK104 wireless firmware

**Initial wired boot verification passed on 2026-09-11.** Installer 1.1.3 uploaded all 2,976 data reports and verified v0.3 CRC `060C4E9E`, RGB and sleep interfaces after reboot on the same USB port. On a fresh GMK104-2 pairing, controller 1.5.1 also connected through the encrypted custom service, restored and read back the lighting frame, and checked the sleep interface. Physical key presses and a ripple reaching across the keyboard also passed; its measured animation rate was about 1 fps. Physical sleep/wake results are still pending. This remains experimental and is not required for 2.4 GHz lighting, which works with v0.2.

v0.3 adds a dedicated Bluetooth RGB GATT service and a volatile adjustable sleep threshold shared by Bluetooth and 2.4 GHz. The Mac stores the requested time separately and reapplies it after reconnect. Power-off restores the firmware's five-minute default. Values are 60–3600 seconds, or zero for Never. Low-battery checks and the original key wake paths are unchanged.

## Reproduce without contacting hardware

From the repository root, with Python 3:

```sh
python3 mac/Firmware/Patches/build_wireless.py
python3 mac/Firmware/Patches/test_wireless.py
```

The builder requires the exact v0.2 SHA-256. It writes the image and a byte-level patch manifest into `mac/.build/firmware-v0.3/`. The tests also require the reconstructed image to equal the bundled v0.3 image. The Mac installer separately pins the image, padded stream and OTA packet SHA-256 values.

## Fixed patch scope

- Input: 140,244-byte v0.2, SHA-256 `96e431887f574cbe01e900ff08a803d8351ede421a982809e294f34b1e7f0fd4`.
- Output: 142,820 bytes, CRC `060C4E9E`, SHA-256 `cfb5604e1b861948078c0176801a74ef45727c96225145da82b25fb81b96dd8a`.
- All original HID report descriptors, 67 GATT handles, OTA callbacks, RF transport, mappings, calibration and v0.2 RGB handlers remain unchanged.
- Copies the original attribute table, adds service/characteristic handles 68–70 and redirects only its initialization pointer. Attribute 70 requires encrypted read/write (`0x23`); the characteristic supports read and acknowledged write. It exposes no keymap, arbitrary-memory or update commands.
- Reserves 48 more zero-initialized BSS bytes at `0x928D0–0x92900`: four bytes for encoded sleep seconds and a dedicated 32-byte RGB reply buffer at `0x928E0`. The existing stack top remains `0xA0000`.
- Replaces the `li a5,299` instruction at file offsets `0x13098` (Bluetooth) and `0x136DC` (receiver) with narrow jumps. Each helper changes only `a5`, returns to the original comparison and preserves the five-minute default. Both use the original seconds counter at `gp+0x4B8`; its clock conversion uses 16,000,000 ticks per second.
- Adds get/set dispatch for channel 3, value 6; other commands retain v0.2 behavior. Sleep get returns `08 03 06 01 47 4D 4B 53`, seconds in bytes 8–9 and exact capability bounds in bytes 10–15.
- Uses a 48-byte stack adapter matching the existing VIA epilogue for Bluetooth RGB calls. The callback returns zero on success and ATT error `0x0D` on rejection, matching this firmware's actual ATT dispatcher.
- Updates the image size and trailing CRC. The image fits the stock OTA upper bound `0x3F000`. No OTA protocol or boot copy source offsets are changed.

Service UUID: `CC731D20-572D-4CEB-91A6-856F9F2DC104`.
RGB characteristic: `CC731D21-572D-4CEB-91A6-856F9F2DC104`.

Each ATT value is at most 20 bytes. A write contains at most five RGB LEDs; the Mac splits existing nine-LED packets and pads 20-byte replies to the existing 32-byte verifier. v0.3 measured about 1 fps with the verified animation path, substantially slower than USB.

## Verification limits

The instruction tests execute the new RV32I code and the unchanged v0.2 RGB handlers, checking all 104 LEDs, checksum, stack/callee-saved registers, initial effect transition, malformed packets, sleep limits and exact mutation inventory. The existing effect initializer is an explicit stub, and the ATT dispatcher/MCU/radio are not emulated. These tests do not prove boot, wireless connectivity, physical LED output, power consumption, sleep/wake or recovery. A first flash needs an attended wired-USB test; rollback requires a working USB interface.

Ghidra independently decoded all 204 newly generated RV32I instructions and verified every direct branch destination in the built image.

The GATT layout and callback design were checked against the actual GMK104 binary and the [Telink B91 SDK documentation](https://doc.telink-semi.cn/doc/en/software/res/sdk/ble/b91_ble_single_connection_en/b91_ble_single_connection_en/). The binary's callback return convention takes precedence over older SDK examples.

## v0.4: faster Bluetooth transfer capability (hardware test pending)

v0.4 is derived from the exact v0.3 image. Its only non-CRC byte change is at `0x22DC8`, from `0A` to `0E`, advertising read, write and Write Without Response on the existing characteristic. The v0.3 callback already accepts bounded ATT Write Command (`0x52`) values. Executable code, BSS, attribute handles, encrypted permissions, HID, RF, sleep and OTA code remain identical. The 142,820-byte image has CRC `6F0AD0C1` and SHA-256 `11DB2CD854381021B45C0B025D7FABC5277CDBFED185A4E8AF0E9327D7ACC347`.

Lighting Studio 1.5.2 uses the new property only when the paired keyboard advertises it. It sends a frame as 21 bounded packets through CoreBluetooth's available write capacity, then checks the frame checksum and indexed LED colors using acknowledged queries. Queue submission alone never counts as verified delivery. v0.3 keeps its acknowledged-write path. Refresh Bluetooth pairing after v0.4 so macOS can discover the new characteristic property.

Run these additional offline checks from the repository root:

```sh
python3 mac/Firmware/Patches/build_streaming.py
python3 mac/Firmware/Patches/test_streaming.py
```

The tests verify the exact mutation inventory and retained attribute permissions, execute 20 full `0x52` frames with all 104 LED reads and checksum checks, and reject malformed packets and non-Bluetooth modes. All offline tests passed. The MCU, radio, CoreBluetooth backpressure and real throughput are not emulated. **v0.4 has not yet been flashed; physical boot, faster frame rate and stability remain unverified.** Installer 1.1.5 allows v0.3 → v0.4 and normal USB rollback to v0.3, v0.2 or stock. It requires a separate explicit experimental confirmation and a passing wired connection check.
