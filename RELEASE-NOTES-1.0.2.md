# Windows Firmware Installer 1.0.2

Use this standalone Windows firmware tool instead of the older flasher bundled with Lighting Studio 1.0. Lighting Studio and the macOS apps are available in the [1.0 release](https://github.com/danny67999/gmk104-lighting-studio/releases/tag/v1.0).

## Changes

- Fixes the startup crash when opening the installer from a shared network folder, including Parallels’ shared Mac folders. The window icon is loaded from the application’s embedded resource.
- Moves firmware transfer into a native C# loop and uses the Mac uploader’s 16 ms post-acknowledgement settling interval to reduce Windows/PowerShell overhead.
- Adds elapsed time, last acknowledged packet and native Windows queue error details to failure logs.
- Keeps strict acknowledgement checks, the one-minute wait per USB exchange, the overall deadline and the rule against automatic retries after uncertain transfers.

**The keyboard firmware is unchanged:** Complete Lighting 1.0, CRC `7F2F4310`, SHA-256 `4bdc3e9729a0583f2daea150fa1ccf4374c5115046f3b8f0655a4758b1dfe22e`. The installer still offers only complete 1.0, previously published v0.2/v0.3/v0.4 and stock recovery.

## Download and run

1. Download `GMK104-Firmware-Installer-1.0.2-Windows-x64.zip` and extract **all** files.
2. Open `GMK104 Firmware Flasher.exe`. Keep the `Firmware` folder beside it; the window title should show **1.0.2**.
3. Start with **Validate files (offline)**, then use **Inspect USB keyboard** and **Test USB connection** before deciding whether to flash. Flashing requires wired USB and the installer’s explicit confirmations.

Windows 10/11 x64 and .NET Framework 4.8 are required. The community build is unsigned. Opening the app does not contact or flash a keyboard.

## Verification and limits

The corrected window opened successfully in Windows 11 under Parallels from the shared Mac folder. Its offline startup test and all five image/packet plans passed. The regression suites passed 103 golden firmware checks and 32,774 native transport checks, including failures around packets 2560 and 3495, zero-byte replies, strict order and withholding activation after a missing data acknowledgement.

The upload timing change has **not yet been verified by a completed hardware flash**. It addresses overhead observed during a transfer that disconnected after about 120 seconds; it is not proof that every timeout or hardware revision is fixed. If a transfer fails, retain its log and check the keyboard’s current state before another attempt. The installer never retries automatically. Reverse-engineered firmware can require hardware recovery if boot fails.
