"""Reproduce the retired v0.5 GMK104 on-keyboard rainbow ripple image.

No hardware is accessed. This version boots, but selecting mode 20 stalls USB.
The v0.6 builder applies the narrow control-flow fix to this exact image.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from rv32 import Assembly, encode

ROOT = Path(__file__).resolve().parents[2]
BASE = 0x20000000
SOURCE = ROOT / "Resources/GMK104-custom-RGB-v0.3-experimental.bin"
SOURCE_SHA = "cfb5604e1b861948078c0176801a74ef45727c96225145da82b25fb81b96dd8a"
STATE = 0x92900
STATE_END = 0x92930
FRAME = 0x80800 + 0x13D4
PALETTE = bytes((255, 0, 0, 255, 125, 0, 255, 255, 0, 0, 255, 0,
                 0, 255, 255, 0, 0, 255, 135, 0, 255, 255, 0, 180))
TRIGGERS = (39, 58, 59, 60)


def geometry() -> bytes:
    layout = json.loads((ROOT.parent / "Resources/layout.json").read_text())
    mapping = json.loads((ROOT.parent / "Resources/default-led-map.json").read_text())
    by_key = {entry["keyId"]: entry["ledIndex"] for entry in mapping["mappings"]
              if entry["confirmed"] and entry["ledIndex"] is not None}
    result = bytearray(208)
    seen = set()
    for key in layout if isinstance(layout, list) else layout["keys"]:
        index = by_key[key["id"]]
        assert index not in seen and 0 <= index < 104
        seen.add(index)
        x = round((key["x"] + key["width"] / 2) * 2)
        y = round((key["y"] + key["height"] / 2) * 2)
        assert 0 <= x < 128 and 0 <= y < 128
        result[2 * index:2 * index + 2] = bytes((x, y))
    assert seen == set(range(104))
    assert max(abs(result[2*i] - result[2*t]) + abs(result[2*i+1] - result[2*t+1])
               for i in range(104) for t in TRIGGERS) <= 48
    return bytes(result)


def build() -> tuple[bytes, dict]:
    source = SOURCE.read_bytes()
    assert len(source) == 142820 and hashlib.sha256(source).hexdigest() == SOURCE_SHA
    assert zlib.crc32(source) ^ 0xffffffff == 0
    image = bytearray(source[:-4])
    while len(image) % 16:
        image.append(255)
    start = BASE + len(image)
    data_address = start + 0x1000
    coord_address = data_address
    palette_address = coord_address + 208
    a = Assembly(start)
    e = a.emit

    # Scanner hook: at 0xBE48, a0 is the mapped LED index and gp+0x624 is
    # nonzero for a new key-down transition. Save the live temporary registers.
    a.label("press_hook")
    e("addi", "sp", "sp", -16)
    for r, offset in (("t0", 0), ("t1", 4), ("t2", 8)):
        e("sw", r, "sp", offset)
    e("sb", "zero", "gp", 0x560)  # displaced original sbgp instruction
    e("lbu", "t0", "gp", -0x2df)
    a.li("t1", 20)
    e("bne", "t0", "t1", "press_done")
    e("lbu", "t0", "gp", 0x624)
    e("beq", "t0", "zero", "press_done")
    for index in TRIGGERS:
        a.li("t1", index)
        e("beq", "a0", "t1", "press_accepted")
    a.jump("press_done")
    a.label("press_accepted")
    a.li("t0", STATE)
    e("lbu", "t1", "t0", 0)
    e("andi", "t1", "t1", 3)
    e("slli", "t2", "t1", 2)
    e("add", "t2", "t2", "t0")
    e("sb", "a0", "t2", 4)  # physical LED origin
    e("sb", "zero", "t2", 5)  # age in 20 ms steps
    a.li("t1", 1)
    e("sb", "t1", "t2", 6)  # active
    e("lbu", "t1", "t0", 0)
    e("addi", "t1", "t1", 1)
    e("andi", "t1", "t1", 3)
    e("sb", "t1", "t0", 0)
    a.label("press_done")
    for r, offset in (("t0", 0), ("t1", 4), ("t2", 8)):
        e("lw", r, "sp", offset)
    e("addi", "sp", "sp", 16)
    a.jump(BASE + 0xBE4C)

    # Called by the stock effect-initialization dispatcher when mode 20 starts.
    a.label("init")
    a.li("t0", STATE)
    for offset in range(0, 0x30, 4):
        e("sw", "zero", "t0", offset)
    e("jalr", "zero", "ra", 0)

    # The stock animation dispatcher runs this in keyboard firmware. Its
    # gp+0x655 clock already gates the other effects in ~20 ms steps.
    a.label("render")
    e("lbu", "t0", "gp", 0x655)
    a.li("t1", 20)
    e("bltu", "t0", "t1", "render_done")
    e("sb", "zero", "gp", 0x655)
    a.li("t0", FRAME)
    a.li("t1", 312)
    a.label("clear_frame")
    e("sb", "zero", "t0", 0)
    e("addi", "t0", "t0", 1)
    e("addi", "t1", "t1", -1)
    e("bne", "t1", "zero", "clear_frame")

    a.li("t2", STATE + 4)
    a.li("t3", 4)
    a.label("slot_loop")
    e("lbu", "a4", "t2", 2)
    e("beq", "a4", "zero", "next_slot")
    e("lbu", "a0", "t2", 0)
    a.li("a4", 104)
    e("bgeu", "a0", "a4", "disable_slot")
    e("lbu", "a1", "t2", 1)
    e("slli", "a3", "a1", 1)  # radius; 2 half-key units per frame
    e("slli", "a4", "a0", 1)
    a.li("t6", coord_address)
    e("add", "a4", "a4", "t6")
    e("lbu", "t4", "a4", 0)  # origin x
    e("lbu", "t5", "a4", 1)  # origin y
    a.li("t0", FRAME)
    a.li("t1", 0)
    a.label("led_loop")
    e("lbu", "a2", "t6", 0)
    e("bltu", "a2", "t4", "x_before")
    e("sub", "a2", "a2", "t4")
    a.jump("x_done")
    a.label("x_before")
    e("sub", "a2", "t4", "a2")
    a.label("x_done")
    e("lbu", "a4", "t6", 1)
    e("bltu", "a4", "t5", "y_before")
    e("sub", "a4", "a4", "t5")
    a.jump("y_done")
    a.label("y_before")
    e("sub", "a4", "t5", "a4")
    a.label("y_done")
    e("add", "a2", "a2", "a4")
    e("addi", "a4", "a3", 3)
    e("bgeu", "a2", "a4", "next_led")
    e("addi", "a4", "a2", 3)
    e("bgeu", "a3", "a4", "next_led")

    # The palette cycles independently of radius and expiration. A color wrap
    # can never end the wave before it reaches the far edge.
    e("slli", "a5", "a1", 1)
    e("add", "a5", "a5", "t1")
    e("andi", "a5", "a5", 7)
    e("slli", "a4", "a5", 1)
    e("add", "a5", "a5", "a4")
    a.li("a4", palette_address)
    e("add", "a5", "a5", "a4")
    a.li("a4", 0)  # attenuation shift: 0, 1, or 2
    e("beq", "a2", "a3", "draw")
    e("bltu", "a2", "a3", "inside_ring")
    e("sub", "a4", "a2", "a3")
    a.jump("draw")
    a.label("inside_ring")
    e("sub", "a4", "a3", "a2")
    a.label("draw")
    for channel in range(3):
        e("lbu", "a7", "a5", channel)
        e("srl", "a7", "a7", "a4")
        e("lbu", "a6", "t0", channel)
        e("bgeu", "a6", "a7", f"keep_{channel}")
        e("sb", "a7", "t0", channel)
        a.label(f"keep_{channel}")
    a.label("next_led")
    e("addi", "t0", "t0", 3)
    e("addi", "t6", "t6", 2)
    e("addi", "t1", "t1", 1)
    a.li("a4", 104)
    e("bltu", "t1", "a4", "led_loop")
    e("addi", "a1", "a1", 1)
    e("sb", "a1", "t2", 1)
    a.li("a4", 26)  # radius 50 exceeds the worst WASD-to-LED distance (45)
    e("bltu", "a1", "a4", "next_slot")
    a.label("disable_slot")
    e("sb", "zero", "t2", 2)
    a.label("next_slot")
    e("addi", "t2", "t2", 4)
    e("addi", "t3", "t3", -1)
    e("bne", "t3", "zero", "slot_loop")
    a.label("render_done")
    a.jump(BASE + 0xDCD4)  # stock effect epilogue/status-light handling

    code = a.finish()
    assert len(code) < 0x1000
    image.extend(code)
    image.extend(b"\xff" * (data_address - BASE - len(image)))
    coords = geometry()
    image.extend(coords + PALETTE)
    while len(image) % 16:
        image.append(255)

    changes = []
    def patch(offset: int, expected: bytes, replacement: bytes):
        assert image[offset:offset + len(expected)] == expected, hex(offset)
        assert len(expected) == len(replacement)
        image[offset:offset + len(expected)] = replacement
        changes.append(dict(offset=hex(offset), before=expected.hex(), after=replacement.hex()))

    def word(op: str, args: tuple, offset: int) -> bytes:
        return struct.pack("<I", encode(op, args, BASE + offset, a.labels))

    patch(0x142, bytes.fromhex("130e2e7c"), word("addi", ("t3", "t3", 0x7f2), 0x142))
    patch(0xBE48, bytes.fromhex("0b300056"), word("jal", ("zero", "press_hook"), 0xBE48))
    patch(0x1F608 + 20 * 4, struct.pack("<I", BASE + 0xE85C), struct.pack("<I", a.labels["render"]))
    patch(0x1F4C8 + (20 - 6) * 4, struct.pack("<I", BASE + 0xD42C), struct.pack("<I", a.labels["init"]))
    for offset in (0x1C5E0, 0x1C604):
        patch(offset, word("addi", ("a2", "zero", 18), offset),
              word("addi", ("a2", "zero", 20), offset))

    # The encrypted Bluetooth characteristic allows a bounded mode-selection
    # command. Increase only its effect upper bound from 19 to 21 (exclusive).
    from build_wireless import build as rebuild_v03
    v02 = (ROOT / "Resources/GMK104-custom-RGB-v0.2-experimental.bin").read_bytes()
    rebuilt, old = rebuild_v03(v02)
    assert rebuilt == source
    ble_value = int(old["labels"]["ble_value"], 16) - BASE
    ble_bound = ble_value - 12
    patch(ble_bound, word("addi", ("t3", "zero", 19), ble_bound),
          word("addi", ("t3", "zero", 21), ble_bound))

    struct.pack_into("<I", image, 0x18, len(image) + 4)
    crc = zlib.crc32(image) ^ 0xffffffff
    image.extend(struct.pack("<I", crc))
    assert len(image) % 16 == 4 and len(image) < 0x3F000
    assert zlib.crc32(image) ^ 0xffffffff == 0
    return bytes(image), dict(version="0.5-offline-prototype", sourceSHA256=SOURCE_SHA,
                              sha256=hashlib.sha256(image).hexdigest(), crc=f"{crc:08X}",
                              size=len(image), codeStart=hex(start), codeEnd=hex(start + len(code)),
                              coordinates=hex(coord_address), palette=hex(palette_address),
                              stateStart=hex(STATE), stateEnd=hex(STATE_END),
                              labels={k: hex(v) for k, v in a.labels.items()}, patches=changes)


if __name__ == "__main__":
    image, manifest = build()
    out = ROOT.parent / ".build/native-ripple-v0.5"
    out.mkdir(parents=True, exist_ok=True)
    (out / "GMK104-onboard-ripple-v0.5-OFFLINE-ONLY.bin").write_bytes(image)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({k: manifest[k] for k in ("version", "size", "sha256", "crc")}, indent=2))
