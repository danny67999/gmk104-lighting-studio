# Firmware safety

[Documentation home](README.md)

**Custom firmware is experimental. Flashing can leave the keyboard unusable. There is no established percentage risk and no guaranteed recovery if its normal USB interfaces stop enumerating.**

## Do you need to flash?

If the controller already verifies its custom lighting interface, you do not need another flash to install an app update or switch computers. The Windows 1.5.2.2 USB fix is entirely in the application.

Stock firmware does not become per-key-capable merely by installing Lighting Studio. If firmware is incompatible, use the platform-specific firmware guide to identify the installed image and allowed transition before deciding whether to proceed. Do not choose a target simply because it has the highest version number.

## Separate tools, separate actions

The controller never flashes firmware. Installing it, opening the guarded flasher or running an offline validation does not start a transfer. Firmware operations require **wired USB**, not Bluetooth or a receiver.

- **Offline validation / DryRun** checks bundled images and transfer plans without opening the keyboard.
- **Inspect** reads the connected device identity.
- **TestConnection** performs sustained read-only checks; it is not a guarantee that a later flash will succeed.
- **Flash** requires an allowed source/target transition, readiness checks, an exact typed phrase and interactive confirmation.

Close the controller and other keyboard utilities before device inspection or flashing. Keep the computer powered and the USB connection stable. Never disconnect during an upload or automatically retry an uncertain transfer.

## Recovery limits and provenance

The bundled stock image is a rollback option only while the required USB interfaces still respond. It is not evidence of a USB-dead bootloader recovery method. After a failed or uncertain transfer, preserve the log and inspect the current state before deciding the next action.

Windows v0.3/v0.4 upload paths have offline validation but were not flashed during Windows-port verification. Bluetooth lighting identity alone does not distinguish v0.3 from v0.4; wired inspection reads the installed CRC. Vendor-derived firmware retains its original provenance; the application source license does not grant rights to vendor firmware.

Read the [Windows firmware guide](../windows/Firmware/README.md) or [Mac firmware guide](../mac/Firmware/README.md) for exact target transitions and checks. Also see [Windows verification limits](../windows/VERIFICATION.md). This overview intentionally does not provide a one-click flash command.
