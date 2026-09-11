# GMK104 firmware installer

The Mac app installs **custom RGB v0.2** or restores the approved **stock firmware** on one wired ZUOYA GMK104. It contains the exact images from the PC build transferred with this project. Custom v0.2 was successfully flashed on Windows and verified with direct RGB, indexed LED readback and full-frame checksums. The Mac port preserves the same complete upload stream.

## Use

1. Quit GMK104 RGB Controller and other keyboard utilities.
2. Open GMK104 Firmware Installer from Applications. Its first check is entirely offline.
3. Connect one GMK104 directly over wired USB and click **Inspect keyboard**. Inspection sends passive version, CRC and RGB/VIA queries; it does not send OTA START.
4. Choose Custom RGB v0.2 or Stock firmware. If it is already installed, no update is offered.
5. Connect Mac power, read the on-screen precautions, select the readiness checkbox and type the exact displayed phrase.
6. Click Install or Restore. Leave the app open and USB connected while it uploads and verifies the reboot.

Custom firmware is experimental. Stock rollback requires the keyboard to boot and expose its normal OTA and RGB interfaces. No USB-dead rescue or automatic crash rollback has been verified.

## Approved images

| Target | Firmware CRC | SHA-256 |
| --- | --- | --- |
| Custom RGB v0.2 | `C6342859` | `96E431887F574CBE01E900FF08A803D8351EDE421A982809E294F34B1E7F0FD4` |
| Stock rollback | `B85531A2` | `FD6E3E8B9D67E2E4942634FCB5C44275F1B1B4F6975F1691318C5A1D44E1661F` |

Custom installation is allowed only from approved stock. Stock rollback is allowed from v0.2 or the retired v0.1 CRC `C077F2F5`. The retired v0.1 image is not bundled or installable.

## Checks

- Full image SHA-256, internal size, KNLT header, CRC32 and zero residue.
- The complete padded image and all 2,924 OTA packets (START, 2,922 data packets, END) match the verified PC flasher's golden hashes. Every packet contains the same indexed chunks and CRC16 values.
- Exact product `ZUOYA GMK104`, manufacturer `RDR`, USB version `0111`, VID/PID, report sizes and both interface usages (`FFEF:0000` OTA; `FF60:0061` RGB).
- Both interfaces must share the same physical IOUSBHostDevice registry parent and USB port. Exactly one pair is allowed.
- The keyboard is re-inspected after confirmation. The exclusively opened OTA handle returns the same approved firmware identity twice immediately before START.
- Only the OTA interface is seized; keyboard input interfaces are not opened.
- One installer lock, a macOS sleep assertion, bounded transfer deadline and no retransmission of uncertain packets.
- Success requires the target CRC and command interface after reboot on the same USB port. Custom v0.2 also requires its exact RGB signature.

Logs are kept in `~/Library/Logs/GMK104/`. If an upload fails or the result is indeterminate, keep the log, wait for USB, reconnect once if needed, and inspect. Do not automatically flash again. If the expected interfaces or an approved CRC do not return, software recovery is not assured.

## Non-flashing command-line checks

```sh
"/Applications/GMK104 Firmware Installer.app/Contents/MacOS/GMK104FirmwareInstaller" --dry-run
"/Applications/GMK104 Firmware Installer.app/Contents/MacOS/GMK104FirmwareInstaller" --inspect
```

`--dry-run` is entirely offline. `--inspect` requires Lighting Studio to be closed and performs only passive queries. Flashing is available only through the app's confirmation screen.

## Validation limits

Both Mac packet plans match the verified Windows packet streams byte for byte. Automated tests cover modified files, wrong identities, approved transitions, acknowledgment failures, deadlines and uncertain writes. Live Mac inspection confirmed custom v0.2 CRC `C6342859` and its RGB signature on the connected keyboard.

No real Mac flash was performed: the test keyboard already runs v0.2. The installer is therefore experimental. Packet equivalence and read-only inspection do not prove the entire Mac upload/reboot path, long-term firmware reliability, all key/LED labels, wireless behavior or recovery from a non-enumerating keyboard.

The bundled binaries contain vendor-derived firmware. The source-code license does not grant rights to unrelated vendor firmware or trademarks.
