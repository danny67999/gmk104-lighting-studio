# GMK104 stock image and storage evidence

Verified on 2026-10-01 against the owner's explicitly identified GMK104 file.
The Wobkey firmware is for another keyboard and is excluded from this evidence.

The original extracted image was compared with both owner-provided copies.
The matching public test fixture is `mac/Firmware/Resources/GMK104-stock-recovery.bin`.

Image identity: 140,244 bytes, Telink `KNLT` marker at offset `0x20`, trailing
stock CRC `B85531A2`, SHA-256
`fd6e3e8b9d67e2e4942634fcb5c44275f1b1b4f6975f1691318c5a1d44e1661f`.
The declared size and trailing CRC validate. The owner's extraction script
strips the .NET byte-array prefix, takes the application from offset `0x100`
in the updater payload, and validates it. There is no decryption operation.

The two `code_2M.resource.bin` files in the local copy are 2,097,156-byte .NET
resources containing padded 2 MB updater payloads. They are not physical
readouts of keyboard flash. The decompiled C files are analysis exports of the
same application; they do not contain the keyboard's stored settings bytes.

## Initialized storage pointers

The stock startup copy at image offsets `0xB8–0xDC` copies initialized data
from image `0x2E8` to instruction-SRAM address `0x178`. For this range, the
initializer's image offset equals the RAM address plus `0x170`.

| RAM address | Image offset | Initial value | Interpretation |
| --- | --- | --- | --- |
| `0x178` | `0x2E8` | `0x14` | Default flash capacity code; replaced by live JEDEC sizing |
| `0x180` | `0x2F0` | `0xFC000` | BLE storage initializer; runtime ownership must still be traced |
| `0xAF8` | `0xC68` | `0` | OTA write-base initializer |
| `0xAFC` | `0xC6C` | `0x40000` | Alternate/current-image offset initializer |
| `0xBB4` | `0xD24` | `0x2000B1E0` | Raw page-program routine |
| `0xBB8` | `0xD28` | `0x2000B148` | Raw flash-read routine |
| `0x1130` | `0x12A0` | `0xFE000` | Calibration initializer; relocated from live capacity |

These confirm the stock application's bank and driver initializers. They do
not prove the actual fitted chip's capacity or the contents/ownership of every
sector. Bootloader and retained-runtime changes to the pointers remain relevant.

## Stock flash operations

`work/gmk104-analysis/decompiled-andes.c` and instruction disassembly show:

- `0x2000B11C`: SPI command `0x9F`, reading three JEDEC-ID bytes.
- `0x2000B148`: SPI command `0x3B`, flash read through ROM `0x1294`.
- `0x2000B1E0`: SPI command `0x02`, programming bounded chunks that stop at
  256-byte page boundaries through ROM `0x1790`.
- `0x2000B244`: waits for radio work, issues SPI command `0x20` for sector
  erase through ROM `0x1790`.
- `0x2000F89C` / `0x2000F918`: delayed read/program wrappers using the raw
  callbacks, processing chunks of at most 256 bytes.
- `0x2000F828`: reads the live JEDEC capacity byte and selects calibration at
  `0x7E000`, `0xFE000`, `0x1FE000` or `0x3FE000` for codes `0x13–0x16`.

The raw operations clear and then set CSR `0x7D0` mask `0x08` around the ROM call.
The actual call contexts, interrupt behavior and timing require target checks
before adding a new commit path. A stock wrapper returning zero is not proof
that bytes were programmed: the journal must independently read them back.

Stock keyboard settings explicitly use these sectors:

| Sector | Records observed in the settings loader |
| --- | --- |
| `0x82000` | 64-byte settings |
| `0x83000` | 64-byte lighting settings |
| `0x84000–0x87000` | Four 240-byte keymap record areas |
| `0x89000` | 384-byte records |
| `0x8A000` | 512-byte records |
| `0x8B000` | 16-byte records |

Additional paths reference `0x81000`, `0xFA000`, `0xFB000`, calibration and
`0xFF000` identity data. Settings journal offsets are bounded to a sector.
Generated BLE record addresses come from runtime tables such as RAM `0x65C`,
`0x670`, `0xBDC` and `0xC34`; several are initialized to zero and populated
later. ROM code is not present in the extracted application.

No literal `0x8C000` or `0x8D000` is present in the stock application/export.
Those remain proposed sectors, not established allocations. Their `0xFF`
padding in the vendor updater cannot establish their state on the keyboard.
Do not erase them based on this analysis alone.

## Current boundary

The available files establish the correct stock application and narrow the
flash analysis. They do not supply a full physical flash dump, authoritative
vendor flash map, or a verified way to read arbitrary sectors through the
original v0.7 firmware. A fresh live inspection after the owner's correction
now establishes that v0.8 is already installed. Its bounded read command
successfully reports JEDEC `0x00146085`, 1 MB capacity and two fully erased
candidate sectors (SHA-256
`F47A8EC3E9AFF2318D896942282AD4FE37D6391C82914F54A5DA8A37DE1300C6`).
No reinstall or storage write was performed. This supersedes the stale
installation assumption; it establishes capacity/current contents, not
ownership or a full physical flash dump. A complete persistent image still
needs allocation evidence plus a tested hardware binding.
