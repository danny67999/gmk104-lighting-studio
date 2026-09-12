# Optional Windows firmware companion

The Windows Lighting Studio supports the Mac project's existing custom v0.2, v0.3 and v0.4 firmware. If Bluetooth lighting is already working, no firmware installation is needed.

This separate PowerShell companion extends the previously tested Windows guarded flasher with the exact Mac v0.3 and v0.4 images. Opening Lighting Studio never launches this tool. All firmware operations require wired USB; Bluetooth and the receiver are excluded.

## Check without flashing

Open PowerShell in this folder. These commands do not modify firmware:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\GMK104-Guarded-Flasher.ps1 -Mode DryRun -Target Wireless
powershell -NoProfile -ExecutionPolicy Bypass -File .\GMK104-Guarded-Flasher.ps1 -Mode Inspect
powershell -NoProfile -ExecutionPolicy Bypass -File .\GMK104-Guarded-Flasher.ps1 -Mode TestConnection
```

DryRun is entirely offline. Inspect and TestConnection require one keyboard in wired mode, with Lighting Studio and other keyboard utilities closed. The connection test reads 4,000 firmware-identity responses and then rechecks the attachment.

Targets and approved transitions are identical to the supplied Mac project:

| Target | Installed CRC required | Target CRC |
| --- | --- | --- |
| Custom (v0.2) | Stock, v0.3 or v0.4 | C6342859 |
| Wireless (v0.3) | v0.2 or v0.4 | 060C4E9E |
| Streaming (v0.4) | v0.3 | 6F0AD0C1 |
| Stock recovery | v0.2, v0.3, v0.4 or retired v0.1 | B85531A2 |

The default operation is Inspect. Flash requires an explicit target, its exact typed confirmation phrase, and PowerShell's confirmation prompt. The tool repeats the sustained connection test and source-identity checks before sending any OTA START. It validates the complete image, vendor CRC, block CRCs, reconstructed image and complete packet stream against fixed Mac golden hashes. It waits at least 16 ms between reports and 40 ms after upload replies, stops on uncertain writes, prevents computer sleep during transfer, and verifies the target CRC and command interfaces on the same USB attachment after reboot. v0.3/v0.4 also require the sleep-setting signature.

Each transfer log has a unique GUID in its filename and is opened with CreateNew, so an existing log cannot be overwritten.

The phrases are `FLASH GMK104 CUSTOM C6342859`, `TEST GMK104 WIRELESS 060C4E9E`, `TEST GMK104 BLUETOOTH 6F0AD0C1`, and `RESTORE GMK104 STOCK B85531A2`. Use `-Mode Flash -Target <target> -Confirmation '<matching phrase>'` only for a deliberate firmware installation. Keep USB and computer power connected throughout. Never automatically repeat a transfer that failed or became uncertain.

## Verification limits

All four Windows packet plans have been checked offline against the exact Mac image, padded-image and full stream hashes; automated negative tests cover modified packet streams, invalid transitions and acknowledgments. No v0.3/v0.4 upload has been performed by this Windows port. The supplied Mac notes record one successful v0.3 installation; v0.4 and the later installer pacing remained experimental in those notes. The current Bluetooth lighting signature does not distinguish v0.3 from v0.4; wired Inspect reads the installed CRC.

This tool cannot recover a keyboard that no longer enumerates its normal USB interfaces. The known stock recovery image is included, but recovery from a USB-dead device is unverified. The included vendor-derived binaries retain their original provenance; no third-party firmware license is granted by the controller source.

The Mac installer filters unrelated keyboard/media reports on the shared interface. This Windows port expects the OTA report ID 5 from its selected HID collection; an unexpected report ID fails acknowledgment validation and stops the operation without retrying the packet. Whether Windows ever delivers those other report IDs through this collection remains unverified. A stop after OTA START can leave an incomplete transfer, so inspect the keyboard before deciding any recovery action.

To rerun offline tests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Firmware.ps1
```
