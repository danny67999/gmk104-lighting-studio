# GMK104 Lighting Studio 1.0 for macOS

Apple Silicon, macOS 13+. Open the 1.0 DMG and drag GMK104 RGB Controller and GMK104 Firmware Installer to Applications. These builds are ad-hoc signed, without Apple notarization; a trusted download may need Privacy & Security → Open Anyway.

Connect the keyboard, use My Lighting to add effects and edit each layer inline. Click/drag on keys to paint a selection or start in a gap to draw a selection rectangle. Shift adds; Option removes. Affect all keys is always visible in the layer editor. Per-layer Speed controls motion and fading. Up to sixteen layers can run on the keyboard.

Use Play on keyboard for a temporary preview or Save to keyboard for lighting that returns after unplugging. Both use wired USB; wait for full readback before disconnecting. The Keyboard page reports firmware capabilities and Input Monitoring/key-response status. Input Monitoring is needed for Mac-streamed reactive effects, not firmware playback.

Mac playback has visible Close controls and a Frame rate setting. Its FPS affects streamed effects; firmware has its own bounded render schedule. USB, Bluetooth and 2.4 GHz transports require compatible hardware/firmware. Wireless streaming may be slow. Audio playback capture requires macOS 14.2+; live sensor layers require the app.

The Profiles menu opens, saves and exports JSON layouts. Files also live under ~/Library/Application Support/GMK104RgbController/. Remove all effects has Undo. Five complex eight-layer profiles and five simpler presets are bundled; import a profile, then Play or Save to keyboard explicitly.

See ../docs/getting-started.md and ../docs/firmware-safety.md. Installing or opening the apps does not automatically flash firmware.
