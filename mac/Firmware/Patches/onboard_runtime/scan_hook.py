"""Key transition hook for the complete runtime; no image or device writes."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from rv32 import Assembly

BASE = 0x20000000
SCAN_SITE = BASE + 0xBE48
FALLBACK = BASE + 0x22DE0


def assemble(base: int, active_flag: int, key_change: int) -> tuple[bytes, dict[str, int]]:
    a = Assembly(base)
    e = a.emit
    a.label("scan")
    volatile = "ra t0 t1 t2 t3 t4 t5 t6 a0 a1 a2 a3 a4 a5 a6 a7".split()
    e("addi", "sp", "sp", -64)
    for index, register in enumerate(volatile):
        e("sw", register, "sp", index * 4)
    a.li("t0", active_flag)
    e("lbu", "t0", "t0", 0)
    e("beq", "t0", "zero", "scan_fallback")
    e("lbu", "t0", "gp", -0x2df)
    a.li("t1", 20)
    e("bne", "t0", "t1", "scan_fallback")
    e("sb", "zero", "gp", 0x560)
    # The stock transition state is 0xff on press and 0 on release. a0
    # already contains the factory scan index. Both transitions reach C.
    e("lbu", "a1", "gp", 0x624)
    e("jal", "ra", key_change)
    for index, register in enumerate(volatile):
        e("lw", register, "sp", index * 4)
    e("addi", "sp", "sp", 64)
    a.jump(SCAN_SITE + 4)
    a.label("scan_fallback")
    for index, register in enumerate(volatile):
        e("lw", register, "sp", index * 4)
    e("addi", "sp", "sp", 64)
    a.jump(FALLBACK)
    return a.finish(), a.labels
