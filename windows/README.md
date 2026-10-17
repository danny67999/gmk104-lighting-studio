# GMK104 Lighting Studio 1.0.2 for Windows

Windows 10/11 x64 with .NET Framework 4.8. Setup installs Lighting Studio and Firmware Flasher for the current user. For portable use, extract the entire ZIP and keep the EXEs beside layout.json, default-led-map.json, Profiles and Firmware. Quit older running copies before using the new build. Existing user profiles are preserved.

The sidebar has My Lighting, Effects and Keyboard, matching the Mac workspace. In My Lighting, choose Presets or Add Effect for up to sixteen layers. Select a layer card to edit it in the settings panel beside the keyboard. Effects shows animated previews with search and automatic/key-press filters. Drag across keys to paint a selection; drag from a gap for a rectangle. Shift adds; Alt removes. Affect all keys expands output without expanding reactive triggers. Each layer has its own Speed. Remove All edits the draft; Undo restores it.

Play on keyboard previews; Save to keyboard keeps the lighting after power-off. These operations require compatible firmware and wired USB. Wait for full readback verification. Open/import JSON and then upload explicitly to change profiles. Profiles > Export profile shares current edits; Export last saved profile shares the saved computer copy. Profiles > Show saved profile in Explorer shows the default %LOCALAPPDATA%\GMK104RgbController location.

Keyboard > PC playback > Frame rate controls PC streaming, while per-layer Speed controls motion in both modes. Firmware runs locally with a bounded schedule. Keyboard shows key-response status and its enable button. Enable key response is needed for host reactive effects; firmware handles its own keys. Audio layers use Windows playback audio. CPU temperature needs a live provider; Radar uses PC playback. They are optional and are not required by the five complex bundled profiles.

USB, Bluetooth and 2.4 GHz lighting interfaces are implemented; wireless throughput and hardware revisions vary. Firmware flashing is wired-only. The included 1.0.2 flasher contains the shared-folder startup and upload-pacing corrections and offers complete 1.0, published legacy v0.2/v0.3/v0.4 and stock recovery. It does nothing on launch and requires identity, file and explicit confirmation checks before writing.

This community build is unsigned and may show an unrecognized-publisher warning. See ../docs/getting-started.md, ../docs/firmware-safety.md and VERIFICATION.md. Do not disable operating-system security globally.
