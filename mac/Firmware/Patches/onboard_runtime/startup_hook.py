"""Restore-before-effect-selection trampoline, without an image/device write.

The pinned stock settings loader restores ra/s0 at 0x20010290, then finishes
its 96-byte frame cleanup. A caller can replace only those two compressed
loads with a four-byte jump to this trampoline. Physical storage callbacks
and the complete-image builder are deliberately outside this module.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from rv32 import Assembly

BASE = 0x20000000
SITE = BASE + 0x10290
CONTINUE = SITE + 4
EXPECTED = bytes.fromhex("f6406644")  # c.lwsp ra,92; c.lwsp s0,88
STOCK_SHA256 = "fd6e3e8b9d67e2e4942634fcb5c44275f1b1b4f6975f1691318c5a1d44e1661f"


def verify_stock(image: bytes) -> None:
    assert hashlib.sha256(image).hexdigest() == STOCK_SHA256
    assert image[SITE - BASE:CONTINUE - BASE] == EXPECTED
    # Pin the remainder of the stock epilogue as well: saved s1-s11,
    # 96-byte stack release and a normal return. The callback cannot bypass it.
    assert image[CONTINUE - BASE:0x102b0] == bytes.fromhex(
        "d6444649b649264a964a064bf25b625cd25c425db25d256167800000")


def assemble(base: int, active_flag: int, boot_callback: int) -> tuple[bytes, dict[str, int]]:
    a = Assembly(base)
    e = a.emit
    a.label("startup")
    volatile = "ra t0 t1 t2 t3 t4 t5 t6 a0 a1 a2 a3 a4 a5 a6 a7".split()
    e("addi", "sp", "sp", -64)
    for index, register in enumerate(volatile):
        e("sw", register, "sp", index * 4)
    e("jal", "ra", boot_callback)
    a.li("t0", active_flag)
    e("lbu", "t0", "t0", 0)
    e("beq", "t0", "zero", "startup_restore")
    a.li("t0", 20)
    e("sb", "t0", "gp", -0x2df)
    a.label("startup_restore")
    for index, register in enumerate(volatile):
        e("lw", register, "sp", index * 4)
    e("addi", "sp", "sp", 64)
    # Replay the two displaced compressed loads as ordinary RV32I loads.
    e("lw", "ra", "sp", 92)
    e("lw", "s0", "sp", 88)
    a.jump(CONTINUE)
    return a.finish(), a.labels
