# Complete release 1.0.2 verification

The release includes Lighting Studio and firmware tools together for Windows and macOS. Windows includes the tested three-page workspace UI previously delivered locally as 1.0.1, plus the corrected 1.0.2 uploader. Both platforms display desktop package version 1.0.2. No firmware image bytes changed.

- Launcher: x64 .NET Framework, assembly/file version 1.0.2.0.
- Launcher SHA-256: `b44d6be59a4e14dd1c7cd00cc486a6d38cca037cdd64b5c9cbad37d9a1fdd866`.
- Complete Lighting image: 174,372 bytes, CRC `7F2F4310`, SHA-256 `4bdc3e9729a0583f2daea150fa1ccf4374c5115046f3b8f0655a4758b1dfe22e`.
- All five image/stream plans passed; 103 firmware regression assertions passed.
- 32,774 injected native transport assertions passed, including failure positions 2560/3495, short replies, packet order, acknowledgement gating and no END after uncertain data.
- Read-only storage reservation checks passed.
- Packaged `--self-test` constructed the GUI and checked all five plans from a local Windows path and the exact Parallels UNC share that previously crashed. No HID was opened by these tests.
- The window was then visibly opened in Parallels Windows 11 from the shared Mac folder, showing Ready and no device operation run. The user confirmed that the build opens.

A previous stock-to-1.0 upload disconnected after 120.322 seconds, at report 3495 of 3633 (last acknowledgement 3494). The reporter’s separate failure at packet 2560 has not been reproduced on that reporter’s hardware. Neither observation proves a specific firmware watchdog or a hardware-revision mismatch. Native pacing-only measurements exclude device I/O and are not a flash-duration or success measurement.

The revised uploader has not yet completed a physical flash during this investigation. Startup success, image/packet checks and mocked transport tests do not establish hardware flash reliability, boot, lighting, typing or power-cycle persistence for every unit. Physical flashing remains a separate attended operation.
