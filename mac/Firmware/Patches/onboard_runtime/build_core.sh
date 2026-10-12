#!/bin/sh
# Compile/measure the complete portable core. No firmware image or device I/O.
set -eu
if [ "$#" -ne 2 ]; then
  echo "Usage: build_core.sh /path/to/riscv-toolchain /path/to/output-directory" >&2
  exit 2
fi
toolchain_directory=$1
output_directory=$2
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
native_directory="$script_directory/../native_ripple"
storage_directory="$script_directory/../onboard_storage"
compiler="$toolchain_directory/bin/riscv-none-elf-gcc"
test -x "$compiler"
mkdir -p "$output_directory"
cat > "$output_directory/footprint.c" <<'EOF'
#include "stored_runtime.h"
/* Preserve exactly one MCU context in BSS so the linker measures its bound. */
gmk_stored_runtime gmk_core_state;
int gmk_core_boot(const gmk_store_io *verified_io) {
    return gmk_stored_runtime_init(&gmk_core_state, verified_io);
}
EOF
cat > "$output_directory/core.ld" <<'EOF'
OUTPUT_ARCH(riscv)
ENTRY(gmk_core_boot)
MEMORY {
  CODE (rx) : ORIGIN = 0x20025000, LENGTH = 0x1A000
  STATE (rw) : ORIGIN = 0x92930, LENGTH = 0x36D0
}
SECTIONS {
  .text : { *(.text .text.*) *(.rodata .rodata.*) } > CODE
  .data : { *(.data .data.*) *(.sdata .sdata.*) } > CODE
  .bss (NOLOAD) : {
    __core_bss_start = .;
    *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON)
    __core_bss_end = .;
  } > STATE
  /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
ASSERT(__core_bss_end <= 0x96000, "persistent core exceeds provisional BSS limit")
ASSERT(SIZEOF(.data) == 0, "initialized globals need a startup copy routine")
EOF
compile() {
  "$compiler" -march=rv32i -mabi=ilp32 -Os -ffreestanding -fno-builtin \
    -fno-pic -fno-asynchronous-unwind-tables -msmall-data-limit=0 -mno-relax \
    -fstack-usage -Wall -Wextra -Werror -I "$script_directory" -I "$native_directory" \
    -c "$1" -o "$output_directory/$2.o"
}
compile "$native_directory/onboard_profile.c" profile
compile "$native_directory/onboard_upload_device.c" upload
compile "$native_directory/renderer_fixed.c" renderer
compile "$storage_directory/onboard_storage.c" storage
compile "$script_directory/runtime.c" runtime
compile "$script_directory/stored_runtime.c" stored_runtime
compile "$script_directory/../onboard_v07/freestanding_mem.c" memory
compile "$output_directory/footprint.c" footprint
"$compiler" -march=rv32i -mabi=ilp32 -Os -nostdlib -fno-pic \
  -msmall-data-limit=0 -mno-relax -Wl,--no-relax,-T,"$output_directory/core.ld",-Map,"$output_directory/core.map" \
  "$output_directory/profile.o" "$output_directory/upload.o" \
  "$output_directory/renderer.o" "$output_directory/storage.o" \
  "$output_directory/runtime.o" "$output_directory/stored_runtime.o" \
  "$output_directory/memory.o" "$output_directory/footprint.o" -lgcc \
  -o "$output_directory/core.elf"
unresolved_symbols=$("$toolchain_directory/bin/riscv-none-elf-nm" -u "$output_directory/core.elf")
test -z "$unresolved_symbols"
"$toolchain_directory/bin/riscv-none-elf-nm" -n -S "$output_directory/core.elf" > "$output_directory/core-symbols.txt"
"$toolchain_directory/bin/riscv-none-elf-size" "$output_directory/core.elf"
echo "Portable core ELF only. No complete keyboard image, hardware binding, or flash command." >&2
