# Getting started

[Documentation home](README.md)

## Windows installation

1. Download **GMK104-Lighting-Studio-Windows-Setup-1.5.2.2.exe** from the [Windows release](https://github.com/danny67999/gmk104-lighting-studio/releases/tag/windows-v1.5.2.2).
2. Fully exit any older Lighting Studio instance: right-click its system-tray icon and choose **Quit**. Closing the window only hides it in the tray.
3. Run the installer. It installs the controller and a separate firmware flasher for your Windows user, with Start-menu entries and an optional desktop shortcut. Installation does not flash firmware.
4. Open **GMK104 Lighting Studio** from the Start menu. Close VIA and other lighting controllers before connecting.
5. Connect one GMK104, select the matching connection type and click **Connect**. The app verifies the compatible custom lighting protocol before allowing writes.
6. Follow the [per-key RGB guide](per-key-rgb.md) to set your first colors.

Requirements: Windows 10/11 x64, .NET Framework 4.8 and compatible custom firmware. Builds are unsigned; only run trusted downloads. Do not disable Windows security protections to install this project.

## Choose a connection

- **USB:** use a data-capable cable and switch the keyboard to wired mode. This is also the only connection allowed for firmware operations.
- **Bluetooth:** pair the keyboard in Windows settings and select its paired Bluetooth mode on the keyboard. Lighting needs the custom firmware's Bluetooth service, not just a working typing connection.
- **2.4 GHz:** connect the receiver and switch the keyboard to receiver mode. The code path is included, but this release has not been verified with receiver hardware.
- **Auto:** the Windows app checks USB first, then Bluetooth, then the receiver. Select a specific transport when troubleshooting. Keep only one matching keyboard attached if identity is ambiguous.

## Upgrade an installed copy

Exit the old app and run the new installer over it. No uninstall is needed; saved profiles remain in `%LOCALAPPDATA%\GMK104RgbController`. Version 1.5.2.2 fixes the USB connection freeze without a firmware update.

The portable ZIP is an alternative to installation. Extract the whole folder; keep the JSON resource files beside the controller EXE. Avoid running installed and portable copies together.

## macOS

Download the Mac disk image from the [releases page](https://github.com/danny67999/gmk104-lighting-studio/releases) and drag the controller and firmware installer into Applications. Use wired USB for the published Mac controller. See the [Mac installation instructions](../README.md#install) for Input Monitoring, platform requirements and the separate firmware workflow. The Windows installer cannot run on macOS.

If the controller rejects the installed firmware, read [firmware safety](firmware-safety.md) before attempting an update. A working custom lighting connection does not need reflashing because you changed computers.
