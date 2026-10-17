# GMK104 Lighting Studio 1.0.2 — Windows and macOS

**This is the complete download release.** Lighting Studio and the firmware installer are included together. You do not need to download any earlier release.

## Choose one download

| Platform | Recommended download | Includes |
| --- | --- | --- |
| Windows 10/11 x64 | [Windows Setup](https://github.com/danny67999/gmk104-lighting-studio/releases/download/v1.0.2/GMK104-Lighting-Studio-Windows-Setup-1.0.2.exe) | Lighting Studio 1.0.2, corrected Firmware Flasher 1.0.2 and five complex profiles |
| Apple Silicon Mac, macOS 13+ | [Mac DMG](https://github.com/danny67999/gmk104-lighting-studio/releases/download/v1.0.2/GMK104-Lighting-Studio-1.0.2-macOS-arm64.dmg) | Lighting Studio 1.0.2, Firmware Installer 1.0.2 and five complex profiles |

Windows: run Setup. Mac: open the DMG and drag both apps to Applications. Quit old copies first. Installing either package does not flash the keyboard.

The Windows portable ZIP includes both apps too. Separate Mac app ZIPs, standalone firmware tools, the firmware BIN, profile ZIP and checksums on this page are optional downloads for people who need them separately.

## Included

- Per-key RGB, up to **16 lighting layers**, independent effect speed, key masks and **Affect all keys**.
- On-keyboard effects and saved profiles that resume after unplugging, with compatible firmware.
- Windows now includes the improved sidebar workspace, visual effect cards, inline layer editor, stable playback controls and theme-aware key selection.
- Windows Firmware Flasher fixes the startup crash on shared network folders, including Parallels’ shared Mac folders. Its native transfer loop reduces PowerShell overhead and uses the Mac uploader’s 16 ms post-acknowledgement settling interval.
- Transfer errors include elapsed time, the last acknowledged packet and native Windows queue details. Strict acknowledgements, one-minute waits per USB exchange and no automatic retry after uncertain transfers remain.
- Five eight-layer profiles: Neon Circuit, Matrix Overdrive, Crystal Storm, Solar Forge and Prism Arcade.

**Desktop version 1.0.2 still uses Complete Lighting firmware 1.0**, CRC `7F2F4310`, SHA-256 `4bdc3e9729a0583f2daea150fa1ccf4374c5115046f3b8f0655a4758b1dfe22e`. Firmware bytes are unchanged. If this firmware is already installed, no firmware update is needed to update the desktop app. The installers contain only complete 1.0, previously published v0.2/v0.3/v0.4 and stock recovery.

Use wired USB to flash firmware or upload/save profiles. Windows requires .NET Framework 4.8. Builds are unsigned on Windows and ad-hoc signed, without notarization, on Mac; operating-system publisher warnings may appear.

## Verification

Offline renderer/profile/transport suites, all five firmware image plans and native transfer failure checks are required for this release. Packaging checks verify that complete Windows Setup/portable downloads contain both apps and the corrected firmware tools, and the Mac DMG contains both 1.0.2 apps.

The startup fix was visibly verified in Parallels. The upload-pacing change still needs confirmation through a completed physical flash; offline tests do not establish compatibility with every hardware revision. A failed boot can require hardware recovery. See [verification details](https://github.com/danny67999/gmk104-lighting-studio/blob/main/docs/verification-1.0.2.md).
