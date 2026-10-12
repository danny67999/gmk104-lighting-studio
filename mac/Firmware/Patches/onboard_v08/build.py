"""Offline-only v0.8 read-only flash-survey payload packager.

This is integration infrastructure, not an uploadable release. It refuses to
produce an image without a separately linked, pinned RV32 payload implementing
the RAM profile uploader, renderer, and bounded flash survey. No device I/O is present.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib

if not __debug__:
    raise RuntimeError("Firmware identity checks require normal Python mode; -O is forbidden.")

PATCHES = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PATCHES))
from rv32 import Assembly, encode

ROOT = PATCHES.parents[1]
SOURCE = ROOT / "Firmware/Resources/GMK104-onboard-ripple-v0.6-experimental.bin"
SOURCE_SHA256 = "5a656e2295ec69d20562b11478f5cbf6d0f732d9c7e04c1c4a6b95edefc2ff51"
BASE = 0x20000000
RAM_BSS_END = 0x92930
RAM_STACK_TOP = 0xA0000
# Unverified growth is deliberately capped until heap/stack use is measured.
MAX_BSS_END = 0x96000
FRAME = 0x80800 + 0x13D4
STOCK_INIT_EPILOGUE = BASE + 0xD42C
STOCK_RENDER_EPILOGUE = BASE + 0xDCD4
MAX_IMAGE = 0x3F000

HOOKS = {
    "scan": 0xBE48,
    "set": 0x1BA38,
    "get": 0x1BD48,
    "init_table": 0x1F4C8 + 14 * 4,
    "render_table": 0x1F608 + 20 * 4,
    "bss": 0x142,
}
EXPECTED = {
    "scan": 0x20022DE0,
    "set": 0x20022410,
    "get": 0x2002242C,
    "init_table": 0x20022E78,
    "render_table": 0x20022EB4,
}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _align(value: int, step: int = 16) -> int:
    return (value + step - 1) & ~(step - 1)


def _signed(value: int, bits: int) -> int:
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def _jal_target(image: bytes, offset: int) -> int:
    word = struct.unpack_from("<I", image, offset)[0]
    assert word & 0x7f == 0x6f and (word >> 7) & 31 == 0
    immediate = ((word >> 31) << 20 | ((word >> 12) & 255) << 12 |
                 ((word >> 20) & 1) << 11 | ((word >> 21) & 1023) << 1)
    return BASE + offset + _signed(immediate, 21)


def source_layout() -> dict:
    image = SOURCE.read_bytes()
    assert len(image) == 147156 and _sha(image) == SOURCE_SHA256
    assert struct.unpack_from("<I", image, 0x18)[0] == len(image)
    assert zlib.crc32(image) ^ 0xffffffff == 0
    # The diagnostic calls only these two stock read paths. Pin their exact
    # entry bytes so a source-image change cannot silently redirect them.
    assert image[0xB11C:0xB12C] == bytes.fromhex("011106ce02c67370047d8d4778008146")
    assert image[0xF89C:0xF8AC] == bytes.fromhex("011122cc26ca4ac84ec652c456c206ce")
    for name in ("scan", "set", "get"):
        assert _jal_target(image, HOOKS[name]) == EXPECTED[name]
    for name in ("init_table", "render_table"):
        assert struct.unpack_from("<I", image, HOOKS[name])[0] == EXPECTED[name]
    assert image[HOOKS["bss"]:HOOKS["bss"] + 4] == bytes.fromhex("130e2e7f")
    return {
        "image": image,
        "hook_base": BASE + _align(len(image) - 4),
        "old_targets": EXPECTED,
        "max_image": MAX_IMAGE,
        "free_image_bytes": MAX_IMAGE - len(image),
    }


def _assembly(base: int, entries: dict[str, int], active_flag: int, bss_end: int) -> tuple[bytes, dict[str, int]]:
    assert RAM_BSS_END <= active_flag < bss_end <= MAX_BSS_END
    a = Assembly(base)
    e = a.emit

    # This replaces the one displaced BSS-limit addi. The vendor's zero loop
    # still owns the clear operation; only its upper bound changes.
    a.label("bss_extend")
    e("addi", "t3", "t3", 0x7f2)
    extra = bss_end - RAM_BSS_END
    for _ in range(8):
        part = min(extra, 2047)
        e("addi", "t3", "t3", part)
        extra -= part
    assert extra == 0
    a.jump(BASE + HOOKS["bss"] + 4)

    # The stock scan site carries a factory-mapped LED index in a0. Preserve
    # every caller-saved register before calling C, including ra. A profile's
    # scan->output permutation is applied by the C adapter, not by this hook.
    a.label("scan")
    volatile = "ra t0 t1 t2 t3 t4 t5 t6 a0 a1 a2 a3 a4 a5 a6 a7".split()
    e("addi", "sp", "sp", -64)
    for i, register in enumerate(volatile):
        e("sw", register, "sp", 4 * i)
    a.li("t0", active_flag)
    e("lbu", "t0", "t0", 0)
    e("beq", "t0", "zero", "scan_fallback")
    e("lbu", "t0", "gp", -0x2df)
    a.li("t1", 20)
    e("bne", "t0", "t1", "scan_fallback")
    e("sb", "zero", "gp", 0x560)  # displaced vendor instruction
    e("lbu", "t0", "gp", 0x624)
    e("beq", "t0", "zero", "scan_finish")
    e("jal", "ra", entries["key_down"])
    a.label("scan_finish")
    for i, register in enumerate(volatile):
        e("lw", register, "sp", 4 * i)
    e("addi", "sp", "sp", 64)
    a.jump(BASE + HOOKS["scan"] + 4)
    a.label("scan_fallback")
    for i, register in enumerate(volatile):
        e("lw", register, "sp", 4 * i)
    e("addi", "sp", "sp", 64)
    a.jump(EXPECTED["scan"])

    # Both hooks are after the vendor's 48-byte VIA prologue. Preserve every
    # caller-saved register around the C adapter, including a2 (the packet
    # pointer). The vendor's shared epilogue has custom undecoded instructions.
    for name, is_get in (("set", 0), ("get", 1)):
        a.label(name)
        e("addi", "sp", "sp", -64)
        for i, register in enumerate(volatile):
            e("sw", register, "sp", 4 * i)
        e("lbu", "t0", "a2", 1)
        a.li("t1", 3)
        e("bne", "t0", "t1", f"{name}_fallback")
        e("lbu", "t0", "a2", 2)
        a.li("t1", 7)
        e("bne", "t0", "t1", f"{name}_fallback")
        e("addi", "a0", "a2", 0)
        a.li("a1", is_get)
        e("jal", "ra", entries["dispatch"])
        for i, register in enumerate(volatile):
            e("lw", register, "sp", 4 * i)
        e("addi", "sp", "sp", 64)
        a.jump(BASE + 0x1BAA8)
        a.label(f"{name}_fallback")
        for i, register in enumerate(volatile):
            e("lw", register, "sp", 4 * i)
        e("addi", "sp", "sp", 64)
        a.jump(EXPECTED[name])

    # Mode 20 remains the same externally. With no validated profile, both
    # paths tail-jump into the verified v0.6 effect, preserving its behavior.
    a.label("init")
    e("addi", "sp", "sp", -16)
    e("sw", "ra", "sp", 12)
    e("jal", "ra", entries["init"])
    e("lw", "ra", "sp", 12)
    e("addi", "sp", "sp", 16)
    a.li("t0", active_flag)
    e("lbu", "t0", "t0", 0)
    e("beq", "t0", "zero", "init_fallback")
    a.jump(STOCK_INIT_EPILOGUE)
    a.label("init_fallback")
    a.jump(EXPECTED["init_table"])

    a.label("render")
    a.li("t0", active_flag)
    e("lbu", "t0", "t0", 0)
    e("beq", "t0", "zero", "render_fallback")
    e("lbu", "t0", "gp", 0x655)
    a.li("t1", 20)
    e("bltu", "t0", "t1", "render_done")
    e("sb", "zero", "gp", 0x655)
    e("addi", "sp", "sp", -16)
    e("sw", "ra", "sp", 12)
    a.li("a0", FRAME)
    a.li("a1", 20)
    e("jal", "ra", entries["render"])
    e("lw", "ra", "sp", 12)
    e("addi", "sp", "sp", 16)
    a.label("render_done")
    a.jump(STOCK_RENDER_EPILOGUE)
    a.label("render_fallback")
    a.jump(EXPECTED["render_table"])

    return a.finish(), a.labels


def layout() -> dict:
    source = source_layout()
    # Entrypoints have fixed-width JAL operands, so placeholder values do not
    # affect trampoline size. This is the address for the external linker.
    dummy = {name: source["hook_base"] + 0x1000 for name in ("dispatch", "init", "key_down", "render")}
    code, labels = _assembly(source["hook_base"], dummy, RAM_BSS_END, RAM_BSS_END + 16)
    return {
        "sourceSHA256": SOURCE_SHA256,
        "hookBase": source["hook_base"],
        "hookBytes": len(code),
        "payloadBase": _align(source["hook_base"] + len(code)),
        "imageCeiling": MAX_IMAGE,
        "minimumBssStart": RAM_BSS_END,
        "maximumBssEnd": MAX_BSS_END,
        "stackTop": RAM_STACK_TOP,
        "labels": labels,
    }


def linker_script() -> str:
    plan = layout()
    payload_length = MAX_IMAGE - (plan["payloadBase"] - BASE) - 16
    return f"""/* Generated from pinned v0.6 layout; offline payload only. */
OUTPUT_ARCH(riscv)
ENTRY(gmk_v07_init)
MEMORY {{
  PAYLOAD (rwx) : ORIGIN = 0x{plan['payloadBase']:08X}, LENGTH = 0x{payload_length:X}
  V07_BSS (rw) : ORIGIN = 0x{RAM_BSS_END:08X}, LENGTH = 0x{MAX_BSS_END - RAM_BSS_END:X}
}}
SECTIONS {{
  .payload : {{
    __v07_payload_start = .;
    *(.text .text.*)
    *(.rodata .rodata.*)
    __v07_payload_end = .;
  }} > PAYLOAD
  .data : {{ *(.data .data.*) *(.sdata .sdata.*) }} > PAYLOAD
  .bss (NOLOAD) : {{
    __v07_bss_start = .;
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
    __v07_bss_end = .;
  }} > V07_BSS
  /DISCARD/ : {{ *(.comment) *(.note*) *(.eh_frame*) }}
}}
ASSERT(__v07_bss_end <= 0x{MAX_BSS_END:X}, "v0.7 BSS exceeds provisional cap")
ASSERT(SIZEOF(.data) == 0, "initialized globals require a RAM copy routine")
"""


def build(payload: bytes, manifest: dict) -> tuple[bytes, dict]:
    plan = layout()
    assert manifest["format"] == "GMK104-v08-rv32-payload-v1"
    assert int(manifest["base"], 0) == plan["payloadBase"]
    assert _sha(payload) == manifest["sha256"].lower()
    assert 0 < len(payload) <= MAX_IMAGE - (plan["payloadBase"] - BASE) - 4
    bss_end = int(manifest["bssEnd"], 0)
    active = int(manifest["activeFlag"], 0)
    assert RAM_BSS_END <= active < bss_end <= MAX_BSS_END
    entries = {key: int(manifest["entries"][key], 0) for key in ("dispatch", "init", "key_down", "render")}
    assert all(plan["payloadBase"] <= value < plan["payloadBase"] + len(payload) and value % 4 == 0
               for value in entries.values())
    assert len(set(entries.values())) == len(entries)
    code, labels = _assembly(plan["hookBase"], entries, active, bss_end)
    assert len(code) == plan["hookBytes"]

    source = source_layout()["image"]
    image = bytearray(source[:-4])
    assert BASE + len(image) == plan["hookBase"]
    image.extend(code)
    image.extend(b"\xff" * (plan["payloadBase"] - BASE - len(image)))
    image.extend(payload)
    while len(image) % 16:
        image.append(255)

    changes = []
    def patch(offset: int, expected: bytes, replacement: bytes) -> None:
        assert len(expected) == len(replacement)
        assert image[offset:offset + len(expected)] == expected, hex(offset)
        image[offset:offset + len(expected)] = replacement
        changes.append({"offset": hex(offset), "before": expected.hex(), "after": replacement.hex()})

    def encoded_jump(offset: int, target: int) -> bytes:
        return struct.pack("<I", encode("jal", ("zero", target), BASE + offset))

    for name in ("scan", "set", "get"):
        offset = HOOKS[name]
        patch(offset, encoded_jump(offset, EXPECTED[name]), encoded_jump(offset, labels[name]))
    for name in ("init_table", "render_table"):
        offset = HOOKS[name]
        patch(offset, struct.pack("<I", EXPECTED[name]), struct.pack("<I", labels[name.removesuffix("_table")]))
    patch(HOOKS["bss"], bytes.fromhex("130e2e7f"), encoded_jump(HOOKS["bss"], labels["bss_extend"]))
    struct.pack_into("<I", image, 0x18, len(image) + 4)
    crc = zlib.crc32(image) ^ 0xffffffff
    image.extend(struct.pack("<I", crc))
    assert len(image) < MAX_IMAGE and zlib.crc32(image) ^ 0xffffffff == 0
    return bytes(image), {
        "status": "offline-candidate-only",
        "flashApproved": False,
        "hardwareTested": False,
        "sourceSHA256": SOURCE_SHA256,
        "sha256": _sha(image),
        "crc": f"{crc:08X}",
        "size": len(image),
        "payloadSHA256": _sha(payload),
        "bssEnd": hex(bss_end),
        "entrypoints": {key: hex(value) for key, value in entries.items()},
        "capabilities": manifest.get("capabilities", []),
        "unverified": manifest.get("unverified", []),
        "patches": changes,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--payload-bin", type=Path)
    parser.add_argument("--payload-manifest", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--linker-script", action="store_true")
    args = parser.parse_args()
    if args.linker_script:
        if args.payload_bin or args.payload_manifest or args.output_dir:
            parser.error("Linker-script mode does not accept a payload.")
        print(linker_script(), end="")
        return
    if not args.payload_bin and not args.payload_manifest and not args.output_dir:
        print(json.dumps({key: (hex(value) if isinstance(value, int) else value)
                          for key, value in layout().items() if key != "labels"}, indent=2))
        return
    if not (args.payload_bin and args.payload_manifest and args.output_dir):
        parser.error("No v0.8 image is available: device payload build and validation are unfinished.")
    payload = args.payload_bin.read_bytes()
    manifest = json.loads(args.payload_manifest.read_text())
    image, build_manifest = build(payload, manifest)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "GMK104-v0.8-READ-ONLY-DIAGNOSTIC.bin").write_bytes(image)
    (args.output_dir / "manifest.json").write_text(json.dumps(build_manifest, indent=2) + "\n")
    print(json.dumps({key: build_manifest[key] for key in ("status", "size", "sha256", "crc")}, indent=2))


if __name__ == "__main__":
    main()
