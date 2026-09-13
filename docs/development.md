# Developer guide

[Documentation home](README.md)

## Source layout

- `windows/`: native x64 C# WinForms controller, transport, RGB verification, effects and input/audio support.
- `windows/tests/` and `windows/TransportTests.cs`: offline regression suites with isolated fixtures.
- `windows/Installer/`: icon generator, Inno Setup recipe and separate guarded firmware launcher.
- `windows/Firmware/`: approved firmware resources, guarded engine and offline tests.
- `mac/`: native Swift controller, firmware companion and build/test scripts.
- `release-assets/`: versioned release downloads and checksums. Published artifacts should not be replaced silently.

## Build Windows

From the repository root on Windows with the .NET Framework compiler installed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\build.ps1 -Tests
```

The app is written for the installed .NET Framework C# compiler, not a required modern .NET SDK. It builds with overflow checks. Output is under `outputs\GMK104-Lighting-Studio-Windows`; test fixtures use new directories under `outputs\windows-test-results` rather than normal user profiles.

Installer builds additionally need Inno Setup 6:

```powershell
.\windows\Installer\build-installer.ps1 -InnoCompiler 'C:\path\to\ISCC.exe'
```

The installer build reruns offline suites and validates all embedded firmware targets without flashing. The checked-in recipe targets the current packaging version. See [Mac build instructions](../README.md#build-and-test) for that platform.

## Validation boundaries

Windows 1.5.2.2 passed 2,279 offline assertions. Its four new stream checks exercise the same stream factory used by HID transport; they detect buffered report writes and read-ahead. The old 64-byte buffer could block within .NET Framework ReadAsync before the request or timeout was reached. A one-byte buffer bypasses managed buffering for the keyboard's 33-byte reports.

Keep report validation, firmware identity gating, attachment checks, bounded exchanges and readback verification intact. Mock transport tests alone cannot establish live HID behavior. For hardware work, start with the [read-only probe](troubleshooting.md#read-only-windows-diagnostic), with other controllers closed. Treat LED writes and firmware flashing as distinct tests requiring deliberate authorization.

Document which platform, connection and firmware were actually tested. Never claim that successful offline firmware plans prove a successful flash or a recoverable device. Do not bundle personal profiles, device logs, signing secrets or development credentials in a release.
