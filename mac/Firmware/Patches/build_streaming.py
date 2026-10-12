"""Experimental v0.4: advertise the existing bounded ATT Write Command handler.

Offline only. v0.3 already implements opcode 0x52 with the same length, mode,
handle and command checks as acknowledged writes. Only the characteristic
property byte and the image CRC change; no executable instruction changes.
"""
from pathlib import Path
import hashlib
import json
import struct
import zlib
from build_wireless import build as build_wireless, BASE

ROOT = Path(__file__).resolve().parents[1]

def build():
    source = (ROOT / 'Resources/GMK104-custom-RGB-v0.3-experimental.bin').read_bytes()
    assert hashlib.sha256(source).hexdigest() == 'cfb5604e1b861948078c0176801a74ef45727c96225145da82b25fb81b96dd8a'
    rebuilt, old = build_wireless((ROOT / 'Resources/GMK104-custom-RGB-v0.2-experimental.bin').read_bytes())
    assert rebuilt == source
    image = bytearray(source)
    table = int(old['tableOffset'], 16)
    declaration = struct.unpack_from('<I', image, table + 69 * 24 + 12)[0] - BASE
    assert image[declaration:declaration+3] == bytes([0x0a, 70, 0])
    image[declaration] = 0x0e  # read, write, write without response
    crc = zlib.crc32(image[:-4]) ^ 0xffffffff
    struct.pack_into('<I', image, len(image)-4, crc)
    assert zlib.crc32(image) ^ 0xffffffff == 0
    assert [i for i in range(len(image)-4) if image[i] != source[i]] == [declaration]
    padded = bytes(image) + bytes([255]) * 12
    def packet(prefix): return bytes(prefix) + bytes([255]) * (64-len(prefix))
    def crc16(data):
        c = 0xffff
        for byte in data:
            c ^= byte
            for _ in range(8): c = (c >> 1) ^ (0xa001 if c & 1 else 0)
        return c
    chunks = len(padded)//16
    stream = bytearray(packet([5,2,2,0,1,255]))
    for first in range(0,chunks,3):
        count = min(3,chunks-first)
        data = bytearray([5,2,count*20,0])
        for i in range(first,first+count):
            chunk = struct.pack('<H',i) + padded[i*16:(i+1)*16]
            data.extend(chunk + struct.pack('<H',crc16(chunk)))
        stream.extend(packet(data))
    last = chunks-1
    stream.extend(packet(bytes([5,2,6,0,2,255])+struct.pack('<HH',last,(-last)&65535)))
    sha = lambda data: hashlib.sha256(data).hexdigest().upper()
    return bytes(image), dict(version='0.4-experimental', size=len(image), crc=f'{crc:08X}',
        sha256=sha(image), paddedHash=sha(padded), streamHash=sha(stream),
        propertyOffset=hex(declaration), before='0A', after='0E',
        sourceSHA256=sha(source), dataReports=(len(image)+47)//48)

if __name__ == '__main__':
    image, manifest = build()
    output = ROOT.parent / '.build/firmware-v0.4'
    output.mkdir(parents=True,exist_ok=True)
    (output / 'GMK104-custom-RGB-v0.4-experimental.bin').write_bytes(image)
    (output / 'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(manifest,indent=2))
