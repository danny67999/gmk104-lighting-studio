# Troubleshooting

[Documentation home](README.md)

## Stuck at Connecting and checking the keyboard

Windows 1.5.2.1 had a USB stream-buffering defect. Upgrade to [1.5.2.2](https://github.com/danny67999/gmk104-lighting-studio/releases/tag/windows-v1.5.2.2) or a later documented fix. Fully exit the old app before installing; if it cannot quit, end **GMK104 Lighting Studio** in Task Manager. Reopen the installed app, select USB and connect.

No firmware reflash is needed for this app bug. If it persists, check that the cable carries data, the keyboard is in wired mode, other controllers are closed and you are not launching an older portable copy.

## The keyboard types but lighting will not connect

Typing and custom RGB use different interfaces. A working typing connection does not prove the custom lighting service is available. Wake the keyboard, select the correct connection type and close competing controllers. An identity-check failure intentionally prevents lighting writes; do not bypass it.

For Bluetooth, confirm the keyboard is paired to this computer and using that Bluetooth slot. After a firmware change, Windows may need the device removed and paired again to refresh its services. Do this in Windows Bluetooth settings; do not flash again merely to refresh pairing.

## All RGB is off

Check brightness is above zero. An idle reactive/ripple effect can legitimately be dark. Try a Static color layer with **Apply & save layers**, or a base color with **Manual lighting → Set all keys**. If that fails, retain the exact status/error message and check connection and firmware identity before considering firmware changes.

## The wrong key changes color

Stop animation and check the LED map. Mapping controls test a physical LED and associate it with a diagram key; they do not remap what the keyboard types. Export/back up your current map before replacing it. Corrections have in-session Undo. See [Windows mapping and profiles](../windows/README.md#mac-profiles-and-mapping).

## Music, temperature or reactive input is inactive

- Music uses the Windows default playback device's loopback signal, not the microphone. Play audio and inspect the live meter. Processing is local; the app does not save recordings.
- CPU temperature requires an existing readable LibreHardwareMonitor/OpenHardwareMonitor WMI provider. An unavailable sensor is reported rather than replaced with CPU usage. No sensor driver is silently installed.
- Enable key response, confirm the correct GMK104 is selected and use a trigger key covered by the layer. A Static color layer does not need a key trigger.

## Read-only Windows diagnostic

Fully exit the controller and other lighting tools first. For the default per-user installation, run this in PowerShell:

```powershell
$studioExe = Join-Path $env:LOCALAPPDATA 'Programs\GMK104 Lighting Studio\GMK104 Lighting Studio.exe'
$probeReport = Join-Path $env:TEMP ('gmk104-probe-' + [guid]::NewGuid().ToString('N') + '.txt')
Start-Process -FilePath $studioExe -ArgumentList @('--probe', ('"' + $probeReport + '"')) -Wait
Get-Content -LiteralPath $probeReport
```

Use the corrected 1.5.2.2 build or newer; substitute your actual EXE location for a portable/custom installation. The probe selects Auto and reads identity/state/sleep information; it does not change colors or flash firmware.

## Report a problem

Open a [GitHub issue](https://github.com/danny67999/gmk104-lighting-studio/issues) with your app version, Windows/macOS version, connection mode, exact status text and steps to reproduce. Include whether ordinary typing works. Review diagnostic output before posting and redact personal paths or identifiers. Do not include secrets or unrelated system logs. Note what was observed rather than treating offline tests as proof of hardware behavior.
