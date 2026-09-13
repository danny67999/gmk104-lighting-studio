# GMK104 Lighting Studio documentation

**Per-key RGB control for the ZUOYA GMK104 on Windows and macOS**, with layered effects and separate guarded firmware tools. Compatible custom firmware is required; installing the app alone does not add per-key RGB to stock firmware.

- [Getting started](getting-started.md): downloads, installation, connecting and upgrading.
- [Individual-key colors and layers](per-key-rgb.md): give each key its own color, select key groups and save effects.
- [Troubleshooting](troubleshooting.md): USB connection freeze, dark RGB, Bluetooth, mapping and diagnostics.
- [Firmware safety](firmware-safety.md): when firmware is needed, offline checks and recovery limitations.
- [Developer guide](development.md): source layout, builds, tests and safe validation.

## Platform and connection support

| Platform | Lighting connection | Verification limits |
| --- | --- | --- |
| Windows 10/11 x64, .NET Framework 4.8 | USB, Bluetooth, 2.4 GHz receiver code | USB and Bluetooth read-only checks passed; receiver hardware and sustained lighting remain unverified in Windows testing. |
| Apple Silicon, macOS 13+ | Wired USB | See the [Mac verification notes](../README.md#release-verification); adaptive music requires macOS 14.2+. The published Mac controller does not implement wireless lighting. |

Connection support is for **lighting control**. Firmware flashing is wired-USB-only on both platforms. Offline tests do not establish hardware compatibility or guarantee recovery.

Current Windows documentation describes **1.5.2.2**. Downloads: [Windows release](https://github.com/danny67999/gmk104-lighting-studio/releases/tag/windows-v1.5.2.2) · [all releases](https://github.com/danny67999/gmk104-lighting-studio/releases).
