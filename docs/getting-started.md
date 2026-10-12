# Install and connect

Download from the [1.0 release](https://github.com/danny67999/gmk104-lighting-studio/releases/tag/v1.0). Windows: run the Setup EXE, or extract the complete portable ZIP. Mac: open the Apple Silicon DMG and drag both apps to Applications. Quit older copies before opening the new app. Existing computer profiles are stored separately and are not removed by the installer.

These community builds have no trusted publisher signing certificate or Apple notarization. Only open downloads you trust. macOS may offer Open Anyway under System Settings → Privacy & Security. Do not disable operating-system security globally.

Connect a GMK104 by USB data cable in wired mode. Open the separate firmware installer if compatible custom firmware is not yet installed. Choose Complete lighting firmware 1.0, inspect the keyboard, read the identified current/target firmware and confirm installation. The installer does not flash automatically on launch. Keep USB and computer power connected.

Open Lighting Studio, connect, add an effect or load a preset, then choose Play on keyboard or Save to keyboard. Save waits for a full readback; once verified, power-cycle and confirm that the lighting returns. A JSON export is a computer backup and does not change the keyboard until you upload it.

For host key-response effects, Mac needs Input Monitoring for GMK104 RGB Controller in Privacy & Security. Quit and reopen after permission changes. Windows uses Raw Input with its Enable key response control. On-keyboard effects detect key presses in firmware and do not need the desktop app running.

On Mac, profiles are under `~/Library/Application Support/GMK104RgbController/`. On Windows, use Open profile folder; the default is `%LOCALAPPDATA%\GMK104RgbController`. Export/import lets you choose any JSON file location and transfer layouts between platforms.
