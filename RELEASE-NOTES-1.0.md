# GMK104 Lighting Studio 1.0 — Windows, macOS and per-key RGB

A unified release of the lighting apps and firmware tools for **Windows and macOS**, adding individual-key RGB, up to **16 independent lighting layers**, adjustable effect speed, and profiles that the keyboard plays itself and restores after unplugging.

- Complete firmware 1.0 includes reactive effects, hold and toggle, ripple/rainbow ripple, Matrix rain, spaced Matrix rain, key-triggered Matrix trails and corrected Aurora, alongside the other built-in Studio effects.
- Mac includes the native effect-card UI, inline editing, system-accent key selection, direct key dragging/rectangle selection, visible playback exits and stable navigation/actions.
- Windows includes native profile upload/save, the shared effect format, direct key dragging/rectangle selection, Clear All/Undo and preset loading.
- Both platforms include five complex eight-layer profiles: **Neon Circuit, Matrix Overdrive, Crystal Storm, Solar Forge and Prism Arcade**. Open/import their JSON files, then Play or Save to keyboard.
- Both firmware installers contain only **complete 1.0**, previously GitHub-published **v0.2, v0.3, v0.4**, and **stock recovery**. Intermediate local test images are excluded. Each flashing exchange waits up to **one minute**; uncertain uploads are not automatically retried.

## Choose your download

| Platform / item | File |
| --- | --- |
| Windows installation — Studio and Flasher | GMK104-Lighting-Studio-Windows-Setup-1.0.exe |
| Windows portable — Studio and Flasher | GMK104-Lighting-Studio-1.0-Windows-x64.zip |
| Windows firmware tool only | GMK104-Firmware-Installer-1.0-Windows-x64.zip |
| Mac disk image — both apps and profile files | GMK104-Lighting-Studio-1.0-macOS-arm64.dmg |
| Mac Lighting Studio only | GMK104-Lighting-Studio-1.0-macOS-arm64.zip |
| Mac firmware installer only | GMK104-Firmware-Installer-1.0-macOS-arm64.zip |
| Complete keyboard firmware | GMK104-firmware-1.0.bin |
| Five complex profiles | GMK104-Complex-Profiles-1.0.zip |
| Download checksums | SHA256SUMS.txt |

Windows requires Windows 10/11 x64 and .NET Framework 4.8. Mac requires Apple Silicon and macOS 13+. Keep portable EXEs beside their resources and Firmware folder. The standalone firmware BIN should be installed through the guarded tool, not sent directly to the keyboard.

Connect by **wired USB** to install firmware or upload/save a profile. After a verified save, firmware plays compatible effects without continuous computer streaming. Host-only effects/sensors still need the computer. Wireless lighting transports are included, but bandwidth and receiver revisions vary.

**Version naming:** public 1.0 groups the current apps and complete firmware. The 174,372-byte image has CRC **7F2F4310** and SHA-256 **4BDC3E9729A0583F2DAEA150FA1CCF4374C5115046F3B8F0655A4758B1DFE22E**. Its bytes match the prior local v1.8 image. It is distinct from the older local persistent v1.0 image (D51110C3).

Mac and Windows offline regression suites, packet/image checks and packaging validation passed. Windows also passed a separate-identity installer smoke test. **No keyboard was flashed for release preparation; physical boot, typing, wireless throughput and power-cycle validation remain separate.** Firmware and storage are reverse engineered; failed boot can require hardware recovery. Stock recovery requires responsive wired USB.

These community apps are unsigned on Windows and ad-hoc signed on Mac, without notarization, so operating-system publisher warnings may appear. The existing **Free Use and No Resale License** permits free personal and business use and free sharing; paid resale requires separate permission. See the platform guides and verification notes in the repository.
