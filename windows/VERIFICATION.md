# Windows port verification

Source baseline: Desktop GMK104 Mac Lighting Studio 1.5.2-beta.1 and its supplied firmware resources. Windows packaging build: 1.5.2.1, native x64 .NET Framework, compiled with overflow checks enabled.

Installer packaging adds original multi-resolution keyboard icons and a standalone firmware launcher. Its embedded resources pass all four target DryRun plans in Windows PowerShell 5.1 without opening HID devices. All flashing continues through the existing guarded engine and retains its typed phrase and interactive confirmation. No firmware upload was performed for packaging.

The production installer correctly refuses installation while the controller's single-instance mutex is active. The same installer recipe and payload were smoke-tested with an isolated test product identity: installation reproduced every payload hash, and uninstallation removed only the test files/registration. The running user application was left untouched. Normal installation, upgrade prompts and shortcuts still need an interactive user check.

## Completed

- Production application build using the installed C# compiler, with no downloaded dependencies.
- 2,004 lighting/map/profile checks: all nine effects, layer composition/masks, full-keyboard ripple reach, slow-Bluetooth pulse timing, validated JSON and Mac compatibility.
- 33 transport/protocol assertions: native structure layout, report encoding, signature refusal, full-frame/rolling verification, indicator exceptions and sleep capabilities.
- 157 offline native-input/audio checks, including 104-key scan-code coverage and signed PCM/extensible audio formats. A separate live read-only attachment check passed four additional assertions, matching both GMK104 Bluetooth keyboard interfaces while rejecting seven unrelated interfaces.
- 37 isolated UI integration checks: preview never connects, draft/saved profile isolation, selection/layers, mapping save failures and undo, damaged-file recovery, and legacy imports.
- 44 offline firmware companion assertions. All four image and full packet-stream golden hashes match the Mac project. Checked in both Windows PowerShell 5.1 and PowerShell 7. Independent bounded safety review found no blocking image/transition/START-order defect.
- Final application read-only probe passed against the connected Bluetooth keyboard: custom RGB signature verified, effect 1, brightness 4, LED 0 black, checksum 0000, wireless sleep 300 seconds.
- Offline form renders inspected; header, button wrapping and responsive status-row issues corrected. Native dropdown selections are covered by integration tests. Actual-window capture could not run because the local computer-use helper failed with a sandbox ACL error; some native child controls are blank in DrawToBitmap previews.

## Hardware verification still needed

No LED color writes, firmware uploads, keyboard-input subscription or playback-audio capture were started during these tests. Actual LED appearance, physical key reaction delivery, live music capture, sensor availability, sleep/wake recovery and sustained streaming must be checked by running the app. USB/receiver code is included but those live transports were not exercised in this port.

Do not interpret successful offline firmware plans as a successful Windows firmware upload or a guaranteed recovery path. The optional v0.3/v0.4 Windows uploader remains experimental. The lighting app does not invoke it, and the current keyboard's compatible Bluetooth interface does not require a new flash.

Run `windows\build.ps1 -Tests` from the source root to reproduce the offline suites. New test runs use dedicated generated fixture directories and do not modify normal user profiles.
