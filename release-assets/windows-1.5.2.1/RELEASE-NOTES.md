# Per-key RGB control for the ZUOYA GMK104 — Windows 1.5.2.1

**Set individual GMK104 keys to different RGB colors.** Highlight WASD, create custom key groups, or build layered lighting with ripple, rainbow ripple, reactive, wave, breathing, spectrum, static color, music response and CPU-temperature effects. Requires compatible custom firmware.

## Downloads

- **GMK104-Lighting-Studio-Windows-Setup-1.5.2.1.exe** — recommended installer. Includes the controller and guarded flasher, custom keyboard icons, Start-menu entries, an optional desktop shortcut and an uninstaller. Saves are preserved.
- **GMK104-Firmware-Flasher-1.5.2.1.exe** — standalone guarded firmware tool; all four approved images are embedded. Nothing is flashed on launch.
- **GMK104-Windows-Portable-1.5.2.1.zip** — controller and flasher without installation. Extract the whole folder before running.
- **GMK104-Windows-Source-1.5.2.1.zip** — Windows source, icon generator, tests, installer recipe and firmware resources.
- **SHA256SUMS.txt** — download checksums.

## Start with individual-key colors

Open Lighting Studio, connect, choose a color and use **Manual lighting → Set all keys** to establish the direct RGB frame. Pick another color and click an individual key: only that key's assigned color changes. Use **Choose keys** and layers for groups and animations.

Windows 10/11 x64 and .NET Framework 4.8. Includes Bluetooth, USB and 2.4 GHz lighting code; the connected Bluetooth custom interface passed live read-only checks. Actual LED appearance, physical key reactions, live audio and long-running USB/receiver behavior still require user hardware checks. Music uses local playback loopback, not the microphone. CPU temperature needs a readable existing sensor provider.

## Firmware safety

**You do not need another flash if the keyboard already responds to the custom Bluetooth interface.** Firmware updates require wired USB; no Bluetooth or receiver flashing is offered. The EXE preserves image hashes, allowed transitions, the long connection test, typed phrase, interactive confirmation, upload pacing and post-reboot verification. All embedded target plans passed offline tests; no Windows v0.3/v0.4 upload was performed for this release. Recovery is unverified if normal USB interfaces stop responding.

These development EXEs are unsigned. Only run downloads you trust. Installing or uninstalling the app does not flash firmware or delete your lighting profiles. Existing macOS source/releases are unchanged.
