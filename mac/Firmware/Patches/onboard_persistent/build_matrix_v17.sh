#!/bin/sh
# Produces a complete firmware file. Never opens or writes a hardware device.
set -eu
if [ "$#" -ne 2 ]; then
  echo "Usage: build_matrix_v17.sh /path/to/riscv-toolchain /path/to/output-directory" >&2
  exit 2
fi
toolchain_directory=$1
output_directory=$2
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
patch_directory="$script_directory/.."
compiler="$toolchain_directory/bin/riscv-none-elf-gcc"
test -x "$compiler"
mkdir -p "$output_directory"
python3 "$script_directory/performance_build.py" --linker-script > "$output_directory/linker.ld"
compile() {
  "$compiler" -march=rv32im -mabi=ilp32 -O2 -DGMK_COOPERATIVE_RENDER -DGMK_EXTENDED_REACTIVE -DGMK_MATRIX_RAIN -DGMK_MATRIX_COLUMNS -ffreestanding -fno-builtin \
    -fno-pic -fno-asynchronous-unwind-tables -msmall-data-limit=0 -mno-relax \
    -fstack-usage -Wall -Wextra -Werror -I "$patch_directory/native_ripple" \
    -c "$1" -o "$output_directory/$2.o"
}
compile "$script_directory/performance_adapter.c" adapter
compile "$script_directory/flash_binding.c" flash
compile "$patch_directory/onboard_v07/freestanding_mem.c" memory
compile "$patch_directory/native_ripple/onboard_profile.c" profile
compile "$patch_directory/native_ripple/onboard_upload_device.c" upload
compile "$patch_directory/native_ripple/renderer_fixed.c" renderer
compile "$patch_directory/onboard_storage/onboard_storage.c" storage
compile "$patch_directory/onboard_runtime/runtime.c" runtime
compile "$patch_directory/onboard_runtime/stored_runtime.c" stored
"$compiler" -march=rv32im -mabi=ilp32 -Os -nostdlib -fno-pic \
  -msmall-data-limit=0 -mno-relax -Wl,--no-relax,-T,"$output_directory/linker.ld",-Map,"$output_directory/payload.map" \
  "$output_directory/adapter.o" "$output_directory/flash.o" "$output_directory/memory.o" \
  "$output_directory/profile.o" "$output_directory/upload.o" "$output_directory/renderer.o" \
  "$output_directory/storage.o" "$output_directory/runtime.o" "$output_directory/stored.o" \
  -lgcc -o "$output_directory/payload.elf"
unresolved_symbols=$("$toolchain_directory/bin/riscv-none-elf-nm" -u "$output_directory/payload.elf")
test -z "$unresolved_symbols"
"$toolchain_directory/bin/riscv-none-elf-objcopy" -O binary -j .payload "$output_directory/payload.elf" "$output_directory/payload.bin"
"$toolchain_directory/bin/riscv-none-elf-nm" -n "$output_directory/payload.elf" > "$output_directory/payload-symbols.txt"
"$toolchain_directory/bin/riscv-none-elf-size" "$output_directory/payload.elf"
python3 - "$script_directory" "$output_directory" <<'PY'
import hashlib,json,pathlib,sys
sys.path.insert(0,sys.argv[1])
import performance_build as build
out=pathlib.Path(sys.argv[2])
symbols={}
for line in (out/'payload-symbols.txt').read_text().splitlines():
    parts=line.split()
    if len(parts)>=3: symbols[parts[-1]]=int(parts[0],16)
payload=(out/'payload.bin').read_bytes()
plan=build.layout()
assert symbols['__v07_payload_start']==plan['payloadBase']
assert symbols['__v07_payload_end']==plan['payloadBase']+len(payload)
assert symbols['__v07_bss_start']==build.RAM_BSS_END
assert symbols['__v07_bss_end']<=build.MAX_BSS_END
manifest={
 'format':'GMK104-persistent-rv32-payload-v1','base':hex(plan['payloadBase']),
 'sha256':hashlib.sha256(payload).hexdigest(),'bssEnd':hex(symbols['__v07_bss_end']),
 'activeFlag':hex(symbols['gmk_profile_active']),
 'entries':{k:hex(symbols['gmk_persistent_'+k]) for k in ('dispatch','init','key_change','render','boot')},
 'capabilities':['all Studio/manual effects 0-26','16 layers and per-key mappings','independent layer speeds',
                 'press and release events','two-slot verified persistent save','read-only boot restoration',
                 'saved global brightness','runtime flash-layout and sector ownership guards'],
 'continuousEffects':['Spaced Matrix rain: alternate fixed logical columns remain dark','Video-reference looping streaks transposed vertically: white heads, colored fading tails and moving dark spaces'],
 'reactiveEffects':['matrix key rain','key toggle','rainbow reactive','splash','cross ripple','row wave','column wave'],
 'performance':['native RV32M arithmetic','two LED pixels per main-loop visit','four ripple distances per visit','one input event per visit','atomic complete-frame publication'],
 'unverified':['physical boot and power-cycle restoration','factory and radio behavior on target',
               'vendor ROM memory and flash timing','reverse-engineered allocation requires target validation',
               'Bluetooth and receiver profile transfer are unavailable; save uses wired USB',
               'requested frame rates above 50 FPS use the stock 50 FPS ceiling']}
(out/'payload-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
image,details=build.build(payload,manifest)
(out/'GMK104-matrix-lighting-v1.7.bin').write_bytes(image)
(out/'manifest.json').write_text(json.dumps(details,indent=2)+'\n')
print(json.dumps({k:details[k] for k in ('status','size','sha256','crc','bssEnd')},indent=2))
PY
