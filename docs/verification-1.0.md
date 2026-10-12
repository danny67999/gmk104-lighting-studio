# Release 1.0 verification

Release builds use a fresh GitHub checkout on Mac and a separate source/build folder on the owner's Windows PC over SSH. Existing installed applications, user profiles and physical keyboard firmware are not replaced during release preparation.

## macOS

- Full Swift/C/Python regression suite passes: protocol validation, identity selection, key monitoring, profile persistence, sixteen-layer upload/readback, selection gestures and firmware plans.
- Storage tests exercise 5,675 interruption boundaries and reject unknown inactive-sector contents.
- 120 production Matrix frames match the Mac renderer fixtures. Forty Aurora frames match the preview within a maximum channel error of 3/255 and mean error of 0.407.
- Both arm64 application bundles build, report version 1.0, and pass strict ad-hoc signature verification.
- The packaged firmware installer's offline validation checks exactly five images and their complete packet streams. No HID device is opened.

## Windows

- The Windows application builds with the system .NET Framework compiler; its six isolated suites and firmware tests pass on Windows.
- Checks cover shared Mac profile fixtures, all firmware effect identifiers, masks, layers, pointer brush/rectangle selection, empty drafts, Undo, key holds/toggles and transport validation.
- The packaged flasher validates all five target images and full packet plans without opening HID. The packaging compiler's digital signatures are checked before use.
- A separate-AppId installer smoke test installs the exact payload into a fresh folder, runs the installed flasher's offline checks, then uninstalls. Existing application installation and user profile folders are not used by the test.
- Offline screenshots check all three Windows tabs. Desktop playback, profile files and native firmware use the same supported effect format.

## Packages and limits

Every ZIP is checked for archive errors. Both platforms' installer payloads must contain exactly the catalog's five firmware images, with matching SHA-256 hashes. The new 1.0 image matches the prior complete local v1.8 image byte-for-byte. Release assets have a SHA256SUMS.txt file.

These checks do not constitute a physical 1.0 flash, boot, typing-latency, radio-throughput or power-cycle test. Those must be evaluated on the target hardware. Historical hardware observations are not represented as new release validation. Reverse-engineered firmware and storage retain hardware-recovery risks. These community desktop builds are unsigned on Windows and ad-hoc signed, without notarization, on Mac.
