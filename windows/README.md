# GMK104 Lighting Studio for Windows

**Per-key RGB control for the ZUOYA GMK104:** choose a separate color for any individual key, create key groups, and combine layered RGB effects using compatible custom firmware.

Windows port of the transferred GMK104 Mac Lighting Studio 1.5.2-beta.1 project.
For Windows 10/11 x64 with .NET Framework 4.8. No Python, Node, or administrator rights are needed for the lighting app.

See the [documentation hub](../docs/README.md) for step-by-step installation, individual-key RGB examples, troubleshooting and firmware safety.

## Start

Recommended: run **GMK104-Lighting-Studio-Windows-Setup-1.5.2.2.exe**. The per-user installer includes keyboard icons, a Start-menu entry for each app, an optional desktop shortcut, and an uninstaller. It preserves your saved lighting profiles. Opening or installing the apps never flashes firmware. The installer does not launch either app automatically.

Version 1.5.2.2 fixes the USB connection hang at "Connecting and checking the keyboard" by disabling HID report stream buffering. The same fix covers the shared 2.4 GHz transport. Exit the previous app completely, then install over the existing installation; no uninstall or firmware reflash is required. The bundled firmware and guarded flasher are unchanged.

**GMK104 Firmware Flasher.exe** is also a standalone download. It embeds the existing guarded PowerShell engine and all four approved images; Windows PowerShell 5.1 must be available. It opens with no device operation, offers offline validation, and requires both a readiness check and the exact phrase before flashing. The original PowerShell confirmation remains in the results console. Keep that console open during an operation. Session files and any durable logs remain under `%LOCALAPPDATA%\GMK104FirmwareLauncher\sessions`.

For the portable ZIP:

1. Extract the entire ZIP into a folder. Keep `layout.json` and `default-led-map.json` beside `GMK104 Lighting Studio.exe`.
2. Pair the GMK104 in Windows Bluetooth settings, or connect it using wired USB / the 2.4 GHz receiver. Close other GMK104/VIA controllers so only one app controls it.
3. Run `GMK104 Lighting Studio.exe`. It automatically connects and verifies the custom lighting protocol. Your connected Bluetooth keyboard passed a read-only identity/state/sleep probe during development; no new firmware flash is required to try this app.
4. Pick an effect, color, and brightness above zero, then click **Apply & save layers**. The default rainbow ripple lights in response to key presses; it is dark while idle. **Test pulse** previews an enabled trigger. A **Static color** layer gives continuous color.

Windows SmartScreen may flag this unsigned development build. Only run the copy you trust; no security-setting changes are required by this project.

## Lighting and individual keys

- Nine effects: ripple, rainbow ripple, reactive, rainbow wave, breathing, spectrum cycle, static color, adaptive music, and CPU temperature.
- Up to 16 layers, topmost first. Normal/additive blending, opacity, intensity, speed, key masks and separate trigger selections match the Mac profile format.
- Click **Choose keys**, select physical keys on the diagram, and finish with **Done selecting**. **Affect all keys** lets selected keys trigger an effect across the keyboard.
- To edit an individual key, first use **Manual lighting → Set all keys** to establish a known full frame if a built-in effect is active. Choose a color in Effect layers and click the key outside selection/mapping mode. The app reads/verifies the frame before partial edits; it will not guess unknown colors.
- Manual lighting also offers brightness, built-in firmware effects 0–18, clear, and wireless sleep settings from 1–60 minutes or Never. Built-in numbers follow the custom firmware; the app does not assign unverified effect names.
- Edited layers are drafts until **Apply & save layers**. Reconnecting restores the last saved profile, not unfinished edits. **Stop** ends host animation/key response and leaves the last verified frame.
- Closing the window keeps the app running in the system tray. Right-click its tray icon and choose **Quit** to exit. Host-generated effects require the app to remain running.

## Mac profiles and mapping

The transferred project includes the full 104-key row-order map but no exported personal lighting profile. Export a lighting profile in the Mac app, copy its JSON to Windows, and use **Import profile**. Studio profiles start with **Apply & save layers**; imported manual/built-in profiles start with **Manual lighting → Apply imported / saved profile**.

Version 1 and 2 Mac profile JSON and schema-version-1 LED maps are supported. Existing valid Windows maps/profiles are preserved in `%LOCALAPPDATA%\GMK104RgbController`. Export before moving to another computer. Mapping corrections are saved atomically and have an in-session Undo; mapping test colors are restored when leaving the mapping tab after a successful connection operation.

## Bluetooth, music and temperature

Bluetooth uses the firmware's custom GATT service, not VIA/WebHID. Commands are serialized; settings/manual frames have full readback verification. Streaming verifies checksums and rotates indexed LED checks, with a complete baseline before animation. The displayed FPS is measured: 15/30/60/90/120 are upper limits, not promised wireless rates. Key ripples slow their logical travel when Bluetooth stalls so they can still reach the far side of the keyboard. Use USB for faster effects.

Reactive input accepts physical key transitions from the selected GMK104 only. Other keyboards are rejected before key processing. It does not log text or suppress normal typing. **Disable key response** stops that subscription.

Adaptive music uses Windows default playback loopback, processed locally in memory; it does not select the microphone or save recordings. CPU temperature requires readable CPU sensors from an existing LibreHardwareMonitor/OpenHardwareMonitor WMI provider. If unavailable, the app reports that explicitly and does not substitute CPU usage or an ACPI temperature. No sensor driver/software is silently installed.

## Safety and troubleshooting

- The lighting app never flashes firmware. A separate optional guarded firmware tool, if included, is for wired USB only. Do not flash merely because you changed computers.
- Disconnect/close any other lighting apps before using this one. Attach only one matching GMK104 transport at a time if device identity is ambiguous.
- A failed identity check locks lighting writes. A failed verification stops animation instead of continuing unchecked.
- For a sleeping/disconnected keyboard, press a key and allow the reconnect timer to run, or use Disconnect/Connect. The saved profile is restored only when that option is enabled.
- Wireless sleep is firmware-volatile and reapplied from this computer's saved preference after reconnect. Continuous traffic may keep the device awake.
- Built-in lighting can be active while the diagram lacks a live color preview; the firmware does not expose a stable built-in animation frame.
- Bluetooth and USB passed live read-only identity/state checks. Version 1.5.2.2 fixes the USB connection hang; receiver hardware remains untested. Actual LED appearance, audio capture, sleep/wake, and sustained streaming still need a user hardware check.

## Build and verify

Source is in the accompanying Windows source archive. Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\build.ps1 -Tests` from its root. This uses the installed Windows .NET Framework C# compiler and builds offline without downloaded packages. The standalone application lands in `outputs\GMK104-Lighting-Studio-Windows`.

For a read-only connection diagnostic, run the executable with `--probe` followed by an output text-file path. For an offline UI render (no device connection), use `--preview` followed by a PNG path and optional tab index 0, 1 or 2.

Build the installer with `windows\Installer\build-installer.ps1 -InnoCompiler 'C:\path\to\ISCC.exe'` after installing [Inno Setup 6](https://jrsoftware.org/isdl.php). Icons are original code-drawn artwork; their reproducible source is `Installer/IconBuilder.cs`. Packaging version 1.5.2.1 added installation and icons; 1.5.2.2 fixes HID connection buffering. These development EXEs are unsigned, not publisher-verified builds.
