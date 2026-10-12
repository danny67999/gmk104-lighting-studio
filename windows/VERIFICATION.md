# Windows 1.0 verification

The application, six isolated regression suites, five firmware packet plans and packaged launcher self-test are built/run on Windows over SSH in a fresh release directory. The suite covers profile roundtrips shared with Mac, all firmware effect IDs, sixteen layers, masks, mock upload/readback, trigger/release behavior, pointer selection, empty drafts, Undo and transport validation.

The release build and tests do not contact or flash a keyboard. Previous read-only USB/Bluetooth checks are historical evidence, not a new hardware test of 1.0. Physical LEDs, sustained radio playback, receiver compatibility, real upload timing and power-cycle behavior need separate hardware validation. The public 1.0 firmware bytes match the prior local complete v1.8 image; no new flash is performed while packaging.
