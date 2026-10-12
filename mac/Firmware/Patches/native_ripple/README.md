# On-device rainbow ripple prototype

`build_native_ripple.py` reproduces the exact v0.5 image from the verified v0.3
image. v0.5 installed and booted on 2026-09-30, but selecting its new mode 20
stalled USB until the keyboard was reconnected. Installer 1.2.2 recognizes this
image for inspection and rollback but rejects any new v0.5 installation.
`build_native_ripple_v06.py` makes the narrow initializer fix described below.
Do not use either output for an unattended update.

The keyboard's own scan path records new W/A/S/D presses in four bounded pulse
slots. A new mode 20 animates those pulses across all 104 LEDs in the stock RGB
framebuffer. The renderer uses the keyboard's existing lighting scheduler; it
does not stream frames from the Mac, Bluetooth, or the 2.4 GHz receiver. Hue
repeats independently of pulse age. Each wave expires only after its radius
passes the most distant LED. The existing direct RGB mode 19 and vendor modes
0–18 remain available. Mode 20 has a fixed layout, palette and speed for this
first prototype; app-configurable layers and sensor effects are specified in
[the uploadable profile design](ONBOARD-PROFILES.md) but not yet implemented.

Build and test without touching hardware:

```sh
python3 mac/Firmware/Patches/native_ripple/build_native_ripple.py
python3 mac/Firmware/Patches/native_ripple/test_native_ripple.py
python3 mac/Firmware/Patches/native_ripple/build_native_ripple_v06.py
python3 mac/Firmware/Patches/native_ripple/test_native_ripple_v06.py
```

The output is `mac/.build/native-ripple-v0.5/GMK104-onboard-ripple-v0.5-OFFLINE-ONLY.bin`
with a JSON manifest listing every changed four-byte word. The same bytes are
staged at `mac/Firmware/Resources/GMK104-onboard-ripple-v0.5-experimental.bin`
and is a selectable experimental installer target. Its size is 147,156 bytes,
SHA-256 is `DB44BDBAB849F041C1EE44E3317D3B8E6DC9BD483C691B98F1D5C5011450EBF4`,
and firmware CRC is `6CF41421`. The builder pins
the v0.3 source SHA-256 and original CRC, checks all 104 layout coordinates,
limits the image below the stock OTA ceiling, updates the size/CRC, and changes
only the scan hook, the mode-20 render/init pointers, two effect bounds, the
Bluetooth command bound, and the BSS extent in the original image.

The instruction test executes the new RV32 code. It verifies that key-up and
non-WASD presses do not trigger, live scan registers are restored, four waves
can coexist, all 104 frame positions stay in bounds, the farthest key lights
after palette wrap, and malformed mode 21 is rejected by the Bluetooth gate.
It also checks the exact mutation inventory and image CRC.

Ghidra 12.1.3 independently decoded all 141 added RV32 instructions in the
built image. The 28 explicit branch destinations all target decoded code or
the two expected original-firmware continuation addresses.

This is **not yet physical validation**. The instruction simulator does not
run the full stock scheduler, matrix scanner, LED driver, OTA boot copy, or
Bluetooth radio. The added code was independently disassembled, the installer
pins the exact image and packet stream and offers wired rollback while USB
responds, and the owner approved this exact image and CRC for an attended test.
The installer must verify the installed firmware and pass its 4,000-query wired
connection test before sending an update. A failed boot could require hardware
recovery.

On 2026-09-30, installer 1.2.0 passed its wired inspection and 4,000-query
connection test. It acknowledged 2,523 of 3,066 v0.5 data reports, then the
next write returned IOKit Not Ready (`0xE00002D8`) at 120.27 seconds after
START. No END command was sent. The keyboard re-enumerated; a read-only check
confirmed v0.3 CRC `060C4E9E` and its RGB and sleep interfaces. Installer
1.2.1 reduced the post-reply interval from 40 to 24 ms. An actual firmware-side
timeout remains unproven. In the user's approved retry, installer 1.2.1
acknowledged all 3,066 data reports, received exact END success, and verified
v0.5 CRC `6CF41421`, RGB and sleep interfaces after reboot at about 96 seconds.
Selecting mode 20 then stalled USB; the keyboard recovered after one USB
reconnect, and a fresh read-only inspection confirmed v0.5 remained installed.

The stock effect initializer dispatcher enters the selected initializer using
`jr a5` at `0x2000D3E0` while its 48-byte stack frame remains live. The v0.5
mode-20 initializer ended with `jalr zero,ra,0`, skipping that frame's cleanup.
v0.6 replaces only that instruction, at file offset `0x22EB0`, with a direct
jump to the stock epilogue at `0x2000D42C`. Four CRC bytes are updated. The
v0.6 image remains 147,156 bytes, has SHA-256
`5A656E2295EC69D20562B11478F5CBF6D0F732D9C7E04C1C4A6B95EDEFC2FF51`
and CRC `89EEE309`. The new instruction test executes both the initializer and
stock epilogue, verifies that the stack and saved registers are restored, and
confirms the rest of the image is unchanged. The existing tests exercise the
unchanged press hook and all-key renderer. On 2026-09-30, the attended v0.6
upload received exact END success, passed postboot verification of CRC
`89EEE309`, and the owner reported much more responsive native ripple after
testing it. This does not prove every effect, wireless mode, sleep/wake path,
or future custom-profile upload.
