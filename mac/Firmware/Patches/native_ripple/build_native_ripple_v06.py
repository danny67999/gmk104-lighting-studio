"""Build the v0.6 mode-20 continuation fix without accessing the keyboard.

The v0.5 image is immutable. Its mode-20 initializer was entered by a tail
jump from the stock effect dispatcher, so returning through ra skipped that
dispatcher's stack cleanup. Replace only that return with a jump to the same
cleanup used by the stock effect initializers; update the image CRC.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import zlib

from build_native_ripple import BASE, build as build_v05
from rv32 import encode

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Resources/GMK104-onboard-ripple-v0.5-experimental.bin"
SOURCE_SHA = "db44bdbab849f041c1ee44e3317d3b8e6dc9bd483c691b98f1d5c5011450ebf4"
EPILOGUE = BASE + 0xD42C


def build() -> tuple[bytes, dict]:
    source = SOURCE.read_bytes()
    reference, old = build_v05()
    assert source == reference and hashlib.sha256(source).hexdigest() == SOURCE_SHA
    assert zlib.crc32(source) ^ 0xffffffff == 0
    image = bytearray(source)

    init = int(old["labels"]["init"], 16)
    render = int(old["labels"]["render"], 16)
    patch_at = render - BASE - 4
    assert init + 0x38 == render - 4
    old_return = struct.pack("<I", encode("jalr", ("zero", "ra", 0)))
    new_jump = struct.pack("<I", encode("jal", ("zero", EPILOGUE), render - 4))
    assert image[patch_at:patch_at + 4] == old_return
    image[patch_at:patch_at + 4] = new_jump

    crc = zlib.crc32(image[:-4]) ^ 0xffffffff
    struct.pack_into("<I", image, len(image) - 4, crc)
    assert zlib.crc32(image) ^ 0xffffffff == 0
    assert len(image) == len(source)
    assert [i for i, (a, b) in enumerate(zip(image, source)) if a != b] == [
        *[patch_at + j for j in range(4) if new_jump[j] != old_return[j]],
        *[len(image) - 4 + j for j in range(4) if image[-4 + j] != source[-4 + j]],
    ]
    manifest = {
        "version": "0.6-offline-prototype",
        "sourceSHA256": SOURCE_SHA,
        "sha256": hashlib.sha256(image).hexdigest(),
        "crc": f"{crc:08X}",
        "size": len(image),
        "init": hex(init),
        "render": hex(render),
        "stockEpilogue": hex(EPILOGUE),
        "patch": {"offset": hex(patch_at), "before": old_return.hex(), "after": new_jump.hex()},
    }
    return bytes(image), manifest


if __name__ == "__main__":
    image, manifest = build()
    out = ROOT.parent / ".build/native-ripple-v0.6"
    out.mkdir(parents=True, exist_ok=True)
    (out / "GMK104-onboard-ripple-v0.6-OFFLINE-ONLY.bin").write_bytes(image)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
