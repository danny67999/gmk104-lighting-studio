"""Regression check for the v0.5 effect-initializer stack leak."""
import hashlib
from pathlib import Path
import struct
import sys
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_wireless
from test_wireless import Machine
from build_native_ripple import BASE, STATE, build as build_v05
from build_native_ripple_v06 import EPILOGUE, build as build_v06


def run():
    old, prior = build_v05()
    image, manifest = build_v06()
    patch = int(manifest["patch"]["offset"], 16)
    assert len(image) == len(old) == 147156
    assert hashlib.sha256(image).hexdigest() == manifest["sha256"]
    assert zlib.crc32(image) ^ 0xffffffff == 0
    assert image[:patch] == old[:patch]
    assert image[patch + 4:-4] == old[patch + 4:-4]
    assert struct.unpack_from("<I", image, 0x1f4c8 + 14*4)[0] == int(prior["labels"]["init"], 16)
    # Stock dispatcher enters effect initializers by jr, while its stack
    # frame is still live. The replacement must reach its normal epilogue.
    assert old[0xd3e0:0xd3e4] == bytes.fromhex("67800700")
    assert image[EPILOGUE - BASE:EPILOGUE - BASE + 2] == bytes.fromhex("b250")
    test_wireless.IMAGE = image
    m = Machine()
    saved_sp = m.r[2] - 0x30
    m.r[2] = saved_sp
    for i in range(STATE, STATE + 0x30): m.put(i, 0xA5, 1)
    saved = {1: 0x30000000, 8: 0x10203040, 9: 0x10203044, 18: 0x10203048,
             19: 0x1020304C, 20: 0x10203050, 21: 0x10203054, 22: 0x10203058,
             23: 0x1020305C}
    for register, offset in ((1, 0x2c), (8, 0x28), (9, 0x24), (18, 0x20),
                             (19, 0x1c), (20, 0x18), (21, 0x14), (22, 0x10),
                             (23, 0x0c)):
        m.put(saved_sp + offset, saved[register])
    m.run(int(prior["labels"]["init"], 16), EPILOGUE + 0x14)
    assert m.r[2] == saved_sp + 0x30
    assert all(m.r[register] == value for register, value in saved.items())
    assert m.ram[STATE:STATE + 0x30] == bytes(0x30)
    assert set(m.writes).issubset(set(range(STATE, STATE + 0x30)) |
                                  set(range(saved_sp + 0x0c, saved_sp + 0x30)))
    # Renderer and scan hook are byte-identical to the instruction-tested v0.5
    # image. The new patch changes only initializer control flow and CRC.
    render = int(prior["labels"]["render"], 16) - BASE
    assert image[render:-4] == old[render:-4]
    print("PASS: mode-20 initializer reaches the stock epilogue, restores its frame, "
          "and changes only one instruction plus the image CRC")
    print("Offline instruction simulation only; the separate attended v0.6 test verified boot and responsive mode 20, not future profile uploads.")


if __name__ == "__main__":
    run()
