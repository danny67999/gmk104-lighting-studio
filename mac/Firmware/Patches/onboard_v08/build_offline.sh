#!/bin/sh
# Build an offline candidate only. Never contacts the keyboard or installer.
set -eu

if [ "$#" -ne 2 ]; then
  echo "Usage: build_offline.sh /path/to/xpack-riscv-toolchain /path/to/output-dir" >&2
  exit 2
fi

TOOLCHAIN=$1
OUTPUT=$2
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO=$(CDPATH= cd -- "$SCRIPT_DIR/../../../.." && pwd)
NATIVE="$REPO/mac/Firmware/Patches/native_ripple"
GCC="$TOOLCHAIN/bin/riscv-none-elf-gcc"
OBJCOPY="$TOOLCHAIN/bin/riscv-none-elf-objcopy"
NM="$TOOLCHAIN/bin/riscv-none-elf-nm"
SIZE="$TOOLCHAIN/bin/riscv-none-elf-size"
OBJDUMP="$TOOLCHAIN/bin/riscv-none-elf-objdump"

test -x "$GCC" && test -x "$OBJCOPY" && test -x "$NM"
mkdir -p "$OUTPUT"
python3 "$SCRIPT_DIR/build.py" --linker-script > "$OUTPUT/linker.ld"

compile() {
  "$GCC" -march=rv32i -mabi=ilp32 -Os -ffreestanding -fno-builtin \
    -fno-pic -fno-asynchronous-unwind-tables -msmall-data-limit=0 -mno-relax \
    -I "$NATIVE" -c "$1" -o "$2"
}
compile "$SCRIPT_DIR/device_adapter.c" "$OUTPUT/device_adapter.o"
compile "$SCRIPT_DIR/freestanding_mem.c" "$OUTPUT/freestanding_mem.o"
compile "$NATIVE/onboard_profile.c" "$OUTPUT/onboard_profile.o"
compile "$NATIVE/onboard_upload_device.c" "$OUTPUT/onboard_upload_device.o"
compile "$NATIVE/renderer_fixed.c" "$OUTPUT/renderer_fixed.o"

"$GCC" -march=rv32i -mabi=ilp32 -Os -nostdlib -fno-pic \
  -msmall-data-limit=0 -mno-relax \
  -Wl,--no-relax,-T,"$OUTPUT/linker.ld",-Map,"$OUTPUT/payload.map" \
  -o "$OUTPUT/payload.elf" \
  "$OUTPUT/device_adapter.o" "$OUTPUT/onboard_profile.o" \
  "$OUTPUT/onboard_upload_device.o" "$OUTPUT/renderer_fixed.o" \
  "$OUTPUT/freestanding_mem.o" -lgcc

UNRESOLVED=$("$NM" -u "$OUTPUT/payload.elf")
if [ -n "$UNRESOLVED" ]; then
  echo "Unresolved RV32 symbols: $UNRESOLVED" >&2
  exit 1
fi
"$OBJCOPY" -O binary -j .payload "$OUTPUT/payload.elf" "$OUTPUT/payload.bin"
"$SIZE" "$OUTPUT/payload.elf" > "$OUTPUT/payload-size.txt"
"$OBJDUMP" -dr "$OUTPUT/payload.elf" > "$OUTPUT/payload-disassembly.txt"
"$NM" -n "$OUTPUT/payload.elf" > "$OUTPUT/payload-symbols.txt"

python3 - "$SCRIPT_DIR" "$OUTPUT" <<'PY'
import hashlib, json, pathlib, sys
sys.path.insert(0, sys.argv[1])
import build
out = pathlib.Path(sys.argv[2])
symbols = {}
for line in (out / 'payload-symbols.txt').read_text().splitlines():
    parts = line.split()
    if len(parts) >= 3:
        symbols[parts[-1]] = int(parts[0], 16)
payload = (out / 'payload.bin').read_bytes()
plan = build.layout()
assert symbols['__v07_payload_start'] == plan['payloadBase']
assert symbols['__v07_payload_end'] == plan['payloadBase'] + len(payload)
assert symbols['__v07_bss_start'] == build.RAM_BSS_END
assert symbols['__v07_bss_end'] <= build.MAX_BSS_END
manifest = {
    'format': 'GMK104-v08-rv32-payload-v1',
    'base': hex(plan['payloadBase']),
    'sha256': hashlib.sha256(payload).hexdigest(),
    'bssEnd': hex(symbols['__v07_bss_end']),
    'activeFlag': hex(symbols['gmk_v07_profile_active']),
    'entries': {name: hex(symbols['gmk_v07_' + name])
                for name in ('dispatch', 'init', 'key_down', 'render')},
    'toolchain': 'xPack RISC-V GCC 15.2.0 darwin-arm64, publisher archive SHA-256 6588e8351455fad8aca37551f0e5a5543f3346bfa9a837cf03cbd3bdd4989f8f',
    'capabilities': ['read-only JEDEC ID and bounded 0x8C000/0x8D000 sector survey',
                     'prototype wired USB RAM-only profile upload and readback',
                     'prototype Studio/manual mode 20 rendering',
                     'prototype wired scalar music/temperature samples'],
    'unverified': ['hardware boot and scan timing', 'read-only flash survey on target',
                   'physical flash-sector ownership', 'all-effect physical output',
                   'RV32 worst-case render cycles', 'RAM/heap collision risk',
                   'persistent flash storage', 'Bluetooth/2.4 GHz profile transfer',
                   'stock built-in profile delegation', 'requested 60/90/120 FPS'],
}
(out / 'payload-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY

python3 "$SCRIPT_DIR/build.py" --payload-bin "$OUTPUT/payload.bin" \
  --payload-manifest "$OUTPUT/payload-manifest.json" --output-dir "$OUTPUT"
python3 "$SCRIPT_DIR/test_build.py"
python3 "$SCRIPT_DIR/test_hooks.py"
echo "Unreleased candidate only. Do not flash without an exact-image attended test approval." >&2
