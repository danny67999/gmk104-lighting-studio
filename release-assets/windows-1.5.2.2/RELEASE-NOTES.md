# GMK104 per-key RGB — Windows 1.5.2.2 USB connection fix

**Give each individual key on the ZUOYA GMK104 its own RGB color.** Highlight WASD, create key groups and combine layered RGB effects with compatible custom firmware.

## Fixed

- Fixed the app hanging at **Connecting and checking the keyboard** when connecting over USB. HID stream buffering could block the read before the request was sent or the timeout was checked. USB and the shared receiver transport now bypass that buffering.
- Added four stream-level regression assertions. The test failed with the old buffering configuration and passed with the fix.
- All **2,279 offline assertions passed**. Three fresh live USB read-only connections completed in **122–146 ms**, and the actual packaged app also passed USB identity/state/sleep checks.

## Upgrade

Fully exit the old app (including its tray icon), then run **GMK104-Lighting-Studio-Windows-Setup-1.5.2.2.exe** over the existing installation. Open Lighting Studio and select **USB → Connect**. Your profiles are preserved. **No uninstall or firmware reflash is needed for this fix.**

## Downloads

- **GMK104-Lighting-Studio-Windows-Setup-1.5.2.2.exe** — recommended installer with controller, keyboard icons and the existing guarded firmware flasher.
- **GMK104-Windows-Portable-1.5.2.2.zip** — extract the whole folder before running; includes controller and guarded flasher.
- **GMK104-Windows-Source-1.5.2.2.zip** — Windows source, tests, icon generator, installer recipe and firmware resources.
- **SHA256SUMS.txt** — checksums for the three downloads.

Firmware images and the flasher source are unchanged. The standalone flasher remains available in the [1.5.2.1 release](https://github.com/danny67999/gmk104-lighting-studio/releases/tag/windows-v1.5.2.1).

Windows 10/11 x64 and .NET Framework 4.8. These community EXEs are unsigned. USB lighting writes, sustained streaming and receiver hardware remain unverified in this testing; read-only connection checks are not a full hardware qualification. No firmware was flashed during testing. Firmware flashing remains wired-USB-only and experimental, with no guaranteed USB-dead recovery. macOS source and releases are unchanged.
