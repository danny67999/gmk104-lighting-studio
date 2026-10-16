# GMK104 Lighting Studio 1.0 — per-key RGB for Windows and macOS

Give every key on the ZUOYA GMK104 its own color, combine up to **16 lighting layers**, and save the effects to the keyboard so they run without the app and return after unplugging it. Compatible custom firmware is required; installing the desktop app alone does not add per-key RGB to stock firmware.

## Downloads

Get Lighting Studio and the Mac apps from the **[1.0 release](https://github.com/danny67999/gmk104-lighting-studio/releases/tag/v1.0)**. For Windows firmware installation, use **[Firmware Installer 1.0.2](https://github.com/danny67999/gmk104-lighting-studio/releases/tag/v1.0.2)** in place of the older flasher bundled with 1.0. It fixes opening from shared network folders and updates upload pacing; the keyboard firmware remains 1.0.

| Platform | Recommended download | Requirements |
| --- | --- | --- |
| Windows | `GMK104-Lighting-Studio-Windows-Setup-1.0.exe` — installs Lighting Studio and Firmware Flasher | Windows 10/11 x64, .NET Framework 4.8 |
| Windows firmware tool | `GMK104-Firmware-Installer-1.0.2-Windows-x64.zip` — extract all files, then open `GMK104 Firmware Flasher.exe` | Windows 10/11 x64, .NET Framework 4.8 |
| macOS | `GMK104-Lighting-Studio-1.0-macOS-arm64.dmg` — drag both apps into Applications | Apple Silicon, macOS 13 or later |

Portable Windows packages, separate Mac app ZIPs, the standalone firmware image, five complex profiles and checksums are also included. Keep the Windows portable app beside its bundled resources and `Firmware` folder.

## Start here

1. Connect your GMK104 with a USB data cable and choose wired mode. If it still has stock firmware, use the separate firmware installer and choose **Complete lighting firmware 1.0**. Read its connection checks and confirmation before installing.
2. Open Lighting Studio, connect, then add an effect or load a preset. Select keys directly on the keyboard diagram: drag across keys to paint a selection, or start dragging in a gap to draw a rectangle. Shift adds keys; Option on Mac or Alt on Windows removes them.
3. Adjust each layer's **Speed**, color, opacity and selected keys. **Affect all keys** expands the effect's output while keeping the selected keys as triggers. Leave it off for a reactive effect that lights only each pressed key.
4. Choose **Play on keyboard** to preview, or **Save to keyboard** to keep the layout after power-off. Both operations require wired USB and compatible firmware. Keep the connection until full readback verification completes.

## Effects and profiles

Firmware 1.0 plays ripple, rainbow ripple, reactive, rainbow reactive, hold, toggle, splash, cross ripple, row/column wave, wave, breathing, spectrum, static color, starlight, rainbow starlight, fire, color wheel, scanner, comet, rain, Aurora and three Matrix rain variants. Layers have independent speed, brightness, opacity, blend and key masks.

**Spaced Matrix rain** uses fixed vertical key columns with every other column dark. **Matrix key rain** starts a finite trail at the top of the pressed key's column. **Key hold** stays lit until release; **Key toggle** changes state with each distinct press.

Try the eight-layer **Neon Circuit, Matrix Overdrive, Crystal Storm, Solar Forge and Prism Arcade** profiles. They are bundled with both apps and also available as `GMK104-Complex-Profiles-1.0.zip`. Open/import a JSON profile, then play or save it to the keyboard. Exporting a file saves a computer copy; it does not upload it.

Mac playback and Play from PC stream effects from the computer. Their FPS controls affect host streaming; firmware playback uses its own bounded render schedule (up to 50 fps). Per-layer Speed changes motion and fading in either mode. Audio and CPU temperature need the computer as a live sensor source. Windows Radar is also a PC playback effect.

## Connections and firmware

Both apps include USB, Bluetooth and 2.4 GHz lighting transports. Wireless host streaming is bandwidth-limited and depends on compatible firmware and receiver hardware. Use wired USB to upload profiles or flash firmware. Once saved, supported firmware runs the lighting itself without continuous computer streaming.

Both installers contain exactly **five** images: complete **1.0**, previously published custom **v0.2, v0.3, v0.4**, and **stock recovery**. Intermediate local test images are excluded from the installer packages. [The catalog](firmware-catalog.json) records their SHA-256 hashes and release provenance.

This release groups the current Mac and Windows apps and complete firmware under version **1.0**. The complete image has CRC `7F2F4310` and is byte-identical to the previous local v1.8 image; it is not the older local persistent v1.0 (`D51110C3`). Firmware support is detected by protocol capabilities and identity rather than the release number alone.

Firmware modification is community-developed and reverse engineered. Flashing is wired-only, requires an exact recognized keyboard and explicit confirmation, and can require hardware recovery if boot fails. Stock recovery requires a keyboard that still answers over USB. The one-minute setting is the maximum wait for each USB exchange, not the total installation time. An uncertain upload is never retried automatically.

## Installation and verification

These builds are unsigned on Windows and ad-hoc signed on macOS, without Apple notarization. Your operating system may display an unrecognized-publisher warning. On Mac, use Privacy & Security → Open Anyway for a download you trust. Enable Input Monitoring for host key-response effects; on-keyboard effects read keys directly. See [getting started](docs/getting-started.md).

The 1.0 apps, catalog, profile format and firmware plans are checked offline on Mac and Windows. Hardware behavior and flashing are separate checks: release preparation does not flash the keyboard or establish compatibility with every GMK104 hardware revision. See [verification details](docs/verification-1.0.md).

[Documentation](docs/README.md) · [Mac guide](mac/README.md) · [Windows guide](windows/README.md) · [Build instructions](docs/development.md) · [All releases](https://github.com/danny67999/gmk104-lighting-studio/releases)

## License

[GMK104 Free Use and No Resale License 1.0](LICENSE) permits personal use, internal business use, modification and free sharing. Selling the app or paid derivatives requires separate written permission. Earlier MIT-licensed copies retain those rights. Vendor-derived firmware and third-party components retain their respective rights and notices.
