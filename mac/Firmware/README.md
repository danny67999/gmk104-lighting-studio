# Firmware Installer 1.0.2 (Complete Lighting firmware 1.0)

The Mac and Windows installers ship the same five hash-pinned images: complete lighting firmware 1.0, legacy custom v0.2/v0.3/v0.4, and stock recovery. These legacy images were already included in published GitHub releases. The intermediate local test builds are not offered by either installer. See `firmware-catalog.json` at the repository root for exact hashes.

Use a USB data cable, wired mode, stable computer power and one GMK104. Close Lighting Studio and other keyboard tools before the installer's inspection and transfer. Mac may require Input Monitoring and administrator approval for exclusive HID access. Windows provides offline validation, read-only inspection and a connection test before the explicit flash action.

The complete 1.0 image is 174,372 bytes, CRC 7F2F4310, SHA-256 4BDC3E9729A0583F2DAEA150FA1CCF4374C5115046F3B8F0655A4758B1DFE22E. It is the prior complete local v1.8 image with a public 1.0 filename, not the older local persistent v1.0 image. Known legacy identities remain recognized for supported upgrades and rollback. Unknown identities are rejected; rollback still requires working USB.

Each flashing exchange may wait up to one minute. A separate overall deadline bounds the operation. If a transfer times out or loses its response, read its logs and check the keyboard's current state before another attempt. The tool does not automatically retry an uncertain flash. Never assume success just because progress reached the last block.

Persistent storage is reverse engineered and checked by the firmware before committing. A failed boot can require hardware recovery. Neither application installation nor opening the firmware tool flashes anything automatically. The 1.0 release preparation runs offline tests and does not flash a physical keyboard.
