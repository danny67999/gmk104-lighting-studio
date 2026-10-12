"""Instruction-level checks for the offline on-keyboard effect prototype."""
import json
from pathlib import Path
import struct
import sys
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_wireless
from test_wireless import Machine, GP
from build_native_ripple import BASE, FRAME, SOURCE, STATE, STATE_END, TRIGGERS, build, geometry
from build_wireless import BUFFER


def run():
    image, manifest = build()
    source = SOURCE.read_bytes()
    test_wireless.IMAGE = image
    labels = {name: int(address, 16) for name, address in manifest["labels"].items()}

    assert zlib.crc32(image) ^ 0xffffffff == 0
    assert struct.unpack_from("<I", image, 0x18)[0] == len(image)
    assert len(image) < 0x3f000
    assert (0x2000013e + 0xe0092000 + 0x7f2) & 0xffffffff == STATE_END
    assert struct.unpack_from("<I", image, 0x1f608 + 20*4)[0] == labels["render"]
    assert struct.unpack_from("<I", image, 0x1f4c8 + 14*4)[0] == labels["init"]
    assert image[int(manifest["coordinates"], 16)-BASE:][:208] == geometry()
    allowed = set(range(0x18, 0x1c))
    for change in manifest["patches"]:
        at = int(change["offset"], 16)
        old = bytes.fromhex(change["before"])
        assert source[at:at+len(old)] == old
        allowed.update(range(at, at+len(old)))
    assert all(x == y or i in allowed for i, (x, y) in enumerate(zip(source[:-4], image)))
    assert len(manifest["patches"]) == 7

    m = Machine()
    m.put(STATE, 3, 1)
    m.put(STATE+4+3*4+2, 1, 1)
    m.run(labels["init"])
    assert m.ram[STATE:STATE_END] == bytes(STATE_END-STATE)

    # A real key transition uses a0=physical LED index and gp+0x624 as down.
    for index in list(TRIGGERS) + [0, 103]:
        m = Machine()
        m.ram[GP-0x2df] = 20
        m.ram[GP+0x624] = 255
        m.r[10] = index
        prior = m.r.copy()
        m.run(labels["press_hook"], BASE+0xbe4c)
        assert m.r == prior
        assert m.ram[GP+0x560] == 0
        assert m.ram[STATE] == (1 if index in TRIGGERS else 0)
        assert m.ram[STATE+4:STATE+7] == (bytes((index, 0, 1)) if index in TRIGGERS else bytes(3))
        m.ram[GP+0x624] = 0
        m.run(labels["press_hook"], BASE+0xbe4c)
        assert m.ram[STATE] == (1 if index in TRIGGERS else 0)

    # Renderer writes a keyboard-wide frame and reaches the farthest key even
    # after its 8-color rainbow palette has wrapped several times.
    coords = geometry()
    origin = 39  # W
    far = max(range(104), key=lambda led: abs(coords[led*2]-coords[origin*2])
              + abs(coords[led*2+1]-coords[origin*2+1]))
    distance = abs(coords[far*2]-coords[origin*2]) + abs(coords[far*2+1]-coords[origin*2+1])
    assert distance > 35
    m = Machine()
    m.ram[GP-0x2df] = 20
    m.ram[GP+0x624] = 255
    m.r[10] = origin
    m.run(labels["press_hook"], BASE+0xbe4c)
    far_seen = False
    for tick in range(27):
        m.ram[GP+0x655] = 20
        m.run(labels["render"], BASE+0xdcd4)
        frame = m.ram[FRAME:FRAME+312]
        assert len(frame) == 312
        if tick == 0:
            assert any(frame[origin*3:origin*3+3])
        if any(frame[far*3:far*3+3]):
            far_seen = True
        assert set(m.writes).issubset(set(range(STATE, STATE_END)) |
                                          set(range(FRAME, FRAME+312)) |
                                          {GP+0x655, GP+0x560} |
                                          set(range(0x9eff0, 0x9f000)))
    assert far_seen, (far, distance)
    assert m.ram[STATE+6] == 0  # wave expires by radius, independent of hue
    assert not any(m.ram[FRAME:FRAME+312])

    # Four rapid key presses retain four independent waves; fifth overwrites
    # only the oldest slot, bounded to the fixed 4-slot state array.
    m = Machine()
    m.ram[GP-0x2df] = 20
    m.ram[GP+0x624] = 255
    for index in (*TRIGGERS, TRIGGERS[0]):
        m.r[10] = index
        m.run(labels["press_hook"], BASE+0xbe4c)
    assert m.ram[STATE] == 1
    assert [m.ram[STATE+4+4*i] for i in range(4)] == [TRIGGERS[0], *TRIGGERS[1:]]
    assert all(m.ram[STATE+6+4*i] == 1 for i in range(4))
    m.ram[GP+0x655] = 20
    m.run(labels["render"], BASE+0xdcd4)
    assert all(any(m.ram[FRAME+i*3:FRAME+i*3+3]) for i in TRIGGERS)

    # Verify the encrypted Bluetooth command gate can pass mode 20 while mode
    # 21 is rejected before reaching the vendor VIA handler.
    from build_wireless import build as rebuild_v03
    source_v02 = (SOURCE.parent / "GMK104-custom-RGB-v0.2-experimental.bin").read_bytes()
    _, old = rebuild_v03(source_v02)
    ble_entry = int(old["labels"]["ble_write"], 16)
    via_entry = int(old["labels"]["call_via"], 16)
    for mode, accepted in ((20, True), (21, False)):
        m = Machine()
        packet = 0x90000
        m.r[11] = packet
        m.put(packet+2, 7, 2)
        m.put(packet+6, 0x12, 1)
        m.put(packet+7, 70, 2)
        m.ram[packet+9:packet+13] = bytes((7, 3, 2, mode))
        m.run(ble_entry, via_entry if accepted else test_wireless.SENTINEL)
        if accepted:
            assert m.ram[BUFFER:BUFFER+4] == bytes((7, 3, 2, 20))
        else:
            assert m.r[10] == 0x0d
    print("PASS: source identity, bounded patch inventory, checksum, scan hook, "
          "four pulses, all 104 RGB pixels, far-edge propagation, and Bluetooth command gate")
    print("Offline instruction simulation only; boot, exact scan timing, LEDs, and wireless behavior need hardware checks.")


if __name__ == "__main__":
    run()
