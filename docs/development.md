# Build and test 1.0

Mac: Apple Silicon with Xcode command-line tools and Python 3. Run `./mac/test.sh`, `./mac/build.sh`, `./mac/Firmware/build.sh`, then `./mac/package.sh`. Tests use bundled stock firmware; no private analysis folder is required. The apps target macOS 13 and are ad-hoc signed.

Windows: Windows 10/11 x64, .NET Framework 4.8, Windows PowerShell 5.1 and Inno Setup 6.7.3. Run `powershell -NoProfile -ExecutionPolicy Bypass -File windows/build.ps1 -Tests`, then `windows/package.ps1 -InnoCompiler <path-to-ISCC.exe>`. Build scripts use the system .NET Framework C# compiler. Tests isolate saved state and do not open a keyboard. The installer does not flash firmware or register automatic startup.

Both platforms encode the GMKP profile format, with byte fixtures checked by the host apps and C firmware parser. Firmware renderer/storage tests use host sanitizers. The complete image is included, with reverse-engineered RISC-V patch sources in `mac/Firmware/Patches`. Rebuilding firmware is separate from building the desktop apps and requires the appropriate RISC-V toolchain and exact base image; do not substitute an unrelated keyboard image.

`firmware-catalog.json` is the public package allowlist. `python3 scripts/verify-release-catalog.py` checks source image hashes and installer selections. Historical sources/images exist for regression and recognized installed identities; the packaged installer choices are deliberately limited to the five public images.

See verification-1.0.md for tested behavior and limits. Hardware probing, flashing and permanent writes are separate explicit operations and are never part of CI.

The Windows firmware launcher source is version 1.0.2. Its build embeds `gmk104-firmware.ico` as `Gmk104.FirmwareIcon`, so opening an EXE on a UNC share does not require shell icon extraction. `--self-test <output-folder>` constructs the window and runs all five firmware packet plans without opening HID. `windows/Firmware/Test-NativeTransport.ps1` runs injected transport failures and pacing checks offline; `Test-Firmware.ps1` invokes it in a separate process. See [1.0.2 verification](verification-1.0.2.md).
