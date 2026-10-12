"""Build an experimental v0.3 ONLY from the exact, known v0.2 GMK104 image.

This does not contact hardware. The new image has not been physically validated.
Stock code, HID descriptors, RF protocol, OTA handlers, calibration and keymaps
are preserved. New BSS occupies 48 bytes below the existing stack reservation.
"""
import hashlib
import json
from pathlib import Path
import struct
import uuid
import zlib
from rv32 import Assembly, encode

BASE = 0x20000000
CFG = 0x928D0                  # encoded sleep seconds + 1; zero = factory 300 s
BUFFER = 0x928E0               # dedicated 32-byte Bluetooth command/reply buffer
END_BSS = 0x92900
SERVICE_UUID = "CC731D20-572D-4CEB-91A6-856F9F2DC104"
CHAR_UUID = "CC731D21-572D-4CEB-91A6-856F9F2DC104"
SOURCE_HASH = "96e431887f574cbe01e900ff08a803d8351ede421a982809e294f34b1e7f0fd4"

def build(source):
    assert len(source) == 140244 and hashlib.sha256(source).hexdigest() == SOURCE_HASH
    image = bytearray(source[:-4])
    while len(image) % 16: image.append(255)
    code_start = BASE + len(image)
    a = Assembly(code_start)
    e = a.emit

    # These hooks replace only the original `li a5,299` in each sleep check.
    # Only a5 changes; absolute jumps preserve all registers and the original
    # branch instruction. Never = UINT32_MAX, so that branch never enters sleep.
    for name, resume in (("bluetooth_sleep_limit", BASE+0x1309c), ("receiver_sleep_limit", BASE+0x136e0)):
        a.label(name)
        a.li("a5", CFG); e("lw", "a5", "a5", 0)
        e("beq", "a5", "zero", name+"_default")
        e("addi", "a5", "a5", -2); a.jump(resume)
        a.label(name+"_default"); a.li("a5", 299); a.jump(resume)

    # VIA get/set interception is narrow; every other command retains v0.2.
    for name, fallback in (("set_dispatch", BASE+0x10a4), ("get_dispatch", BASE+0x1194)):
        a.label(name)
        e("lbu", "t0", "a2", 1); a.li("t1", 3)
        e("bne", "t0", "t1", fallback)
        e("lbu", "t0", "a2", 2); a.li("t1", 6)
        e("bne", "t0", "t1", fallback)
        # Branches to the old cave exceed conditional range: fixed below via
        # nearby trampoline labels, while unconditional JAL has ample reach.
        a.jump("sleep_set" if name == "set_dispatch" else "sleep_get")
    a.label("sleep_set")
    e("lbu", "t0", "a2", 3); a.li("t1", 1)
    e("bne", "t0", "t1", "sleep_done")
    e("lbu", "t0", "a2", 4); e("lbu", "t1", "a2", 5)
    e("slli", "t1", "t1", 8); e("or", "t0", "t0", "t1")
    e("beq", "t0", "zero", "sleep_store")
    a.li("t1", 60); e("bltu", "t0", "t1", "sleep_done")
    a.li("t1", 3601); e("bgeu", "t0", "t1", "sleep_done")
    a.label("sleep_store")
    e("addi", "t0", "t0", 1); a.li("t1", CFG); e("sw", "t0", "t1", 0)
    a.label("sleep_done"); a.jump(BASE+0x1baa8)
    a.label("sleep_get")
    a.li("t0", CFG); e("lw", "t0", "t0", 0)
    e("bne", "t0", "zero", "sleep_configured")
    a.li("t0", 301)
    a.label("sleep_configured"); e("addi", "t0", "t0", -1)
    e("sb", "t0", "a2", 8); e("srli", "t0", "t0", 8); e("sb", "t0", "a2", 9)
    for offset, value in enumerate([8, 3, 6, 1, 71, 77, 75, 83]):
        a.li("t0", value); e("sb", "t0", "a2", offset)
    for offset, value in ((10, 3), (11, 3), (12, 0x10), (13, 0x0e), (14, 60), (15, 0)):
        a.li("t0", value); e("sb", "t0", "a2", offset)
    a.jump(BASE+0x1baa8)

    # A normal C-callable adapter for the existing branch-based VIA handlers.
    # The vendor's shared epilogue restores this exact 48-byte stack layout.
    a.label("call_via")
    e("addi", "sp", "sp", -48)
    for r, offset in (("ra",44),("s0",40),("s1",36),("s2",32),("s3",28)): e("sw",r,"sp",offset)
    e("lbu", "t0", "a2", 0); a.li("t1", 7)
    e("beq", "t0", "t1", "set_dispatch"); a.jump("get_dispatch")

    # Telink ATT callback ABI: (connection handle, rf_packet_att_data_t*).
    # Accept only this attribute, normal write opcodes, Bluetooth mode, and
    # explicitly bounded RGB/brightness/effect/sleep requests. Never OTA/VIA
    # keymap or arbitrary memory commands. Payloads fit the default ATT MTU.
    a.label("ble_write")
    e("lbu", "t0", "gp", 0x40f); e("bne", "t0", "zero", "reject")
    e("lbu", "t0", "a1", 6); a.li("t1", 0x12)
    e("beq", "t0", "t1", "ble_opcode_ok"); a.li("t1", 0x52)
    e("bne", "t0", "t1", "reject")
    a.label("ble_opcode_ok")
    e("lbu", "t0", "a1", 7); a.li("t1", 70); e("bne", "t0", "t1", "reject")
    e("lbu", "t0", "a1", 8); e("bne", "t0", "zero", "reject")
    e("lhu", "t1", "a1", 2); e("addi", "t1", "t1", -3)
    a.li("t0", 4); e("bltu", "t1", "t0", "reject")
    a.li("t0", 21); e("bgeu", "t1", "t0", "reject")
    e("addi", "t2", "a1", 9)
    e("lbu", "t0", "t2", 1); a.li("t3", 3); e("bne", "t0", "t3", "reject")
    e("lbu", "t0", "t2", 0); a.li("t3", 8); e("beq", "t0", "t3", "ble_get")
    a.li("t3", 7); e("bne", "t0", "t3", "reject")
    e("lbu", "t0", "t2", 2); a.li("t3", 5); e("beq", "t0", "t3", "ble_rgb")
    a.li("t3", 6); e("beq", "t0", "t3", "ble_sleep_set")
    a.li("t3", 4); e("bne", "t1", "t3", "reject")
    a.li("t3", 1); e("beq", "t0", "t3", "ble_brightness")
    a.li("t3", 2); e("bne", "t0", "t3", "reject")
    a.li("t3", 19); a.jump("ble_value")
    a.label("ble_brightness"); a.li("t3", 5)
    a.label("ble_value"); e("lbu", "t0", "t2", 3); e("bgeu", "t0", "t3", "reject"); a.jump("accept")
    a.label("ble_get")
    a.li("t0", 4); e("bne", "t1", "t0", "reject")
    e("lbu", "t0", "t2", 2); a.li("t3", 6); e("beq", "t0", "t3", "ble_sleep_version")
    a.li("t3", 5); e("bne", "t0", "t3", "reject")
    e("lbu", "t0", "t2", 3); a.li("t3", 104); e("bgeu", "t0", "t3", "reject"); a.jump("accept")
    a.label("ble_sleep_set"); a.li("t0", 6); e("bne", "t1", "t0", "reject")
    a.label("ble_sleep_version")
    e("lbu", "t0", "t2", 3); a.li("t3", 1); e("bne", "t0", "t3", "reject"); a.jump("accept")
    a.label("ble_rgb")
    a.li("t0", 5); e("bltu", "t1", "t0", "reject")
    e("lbu", "t0", "t2", 3); a.li("t3", 104); e("bgeu", "t0", "t3", "reject")
    e("lbu", "t3", "t2", 4); a.li("t4", 6); e("bgeu", "t3", "t4", "reject")
    e("bne", "t3", "zero", "ble_rgb_nonzero"); e("bne", "t0", "zero", "reject")
    a.label("ble_rgb_nonzero")
    e("add", "t0", "t0", "t3"); a.li("t4", 105); e("bgeu", "t0", "t4", "reject")
    e("slli", "t4", "t3", 1); e("add", "t4", "t4", "t3"); e("addi", "t4", "t4", 5)
    e("bne", "t1", "t4", "reject")
    a.label("accept")
    a.li("a2", BUFFER)
    for offset in range(0, 32, 4): e("sw", "zero", "a2", offset)
    e("addi", "t3", "a2", 0)
    a.label("copy")
    e("lbu", "t0", "t2", 0); e("sb", "t0", "t3", 0)
    e("addi", "t2", "t2", 1); e("addi", "t3", "t3", 1); e("addi", "t1", "t1", -1)
    e("bne", "t1", "zero", "copy")
    e("addi", "sp", "sp", -16); e("sw", "ra", "sp", 12)
    e("jal", "ra", "call_via")
    e("lw", "ra", "sp", 12); e("addi", "sp", "sp", 16)
    # This firmware's ATT dispatcher treats zero as success, nonzero as an ATT
    # error code (2001a180..2001a198), unlike some older Telink callback examples.
    a.li("a0", 0); e("jalr", "zero", "ra", 0)
    a.label("reject"); a.li("a0", 0x0d); e("jalr", "zero", "ra", 0)

    # Conditional far fallbacks become local trampolines without touching the
    # original handlers. All other conditionals remain within the new code.
    for i, (op, args) in enumerate(list(a.code)):
        if op in ("bne",) and isinstance(args[-1], int):
            target = args[-1]; name = "fallback_"+str(i)
            a.code[i] = (op, args[:-1]+(name,))
            a.label(name); a.jump(target)
    code = a.finish(); image.extend(code)
    while len(image) % 4: image.append(255)
    table_offset = len(image)
    table = bytearray(source[0x2013c:0x2079c])
    assert len(table) == 68*24 and struct.unpack_from("<H", table)[0] == 67
    struct.pack_into("<H", table, 0, 70)
    newdata = BASE + table_offset + 71*24
    service_uuid = bytes(reversed(uuid.UUID(SERVICE_UUID).bytes))
    char_uuid = bytes(reversed(uuid.UUID(CHAR_UUID).bytes))
    declaration = bytes([0x0a, 70, 0])+char_uuid # read and write-with-response
    primary_uuid_ptr = struct.unpack_from("<I", source, 0x2013c+24+8)[0]
    char_decl_uuid_ptr = struct.unpack_from("<I", source, 0x2013c+48+8)[0]
    def attr(n, p, ulen, vlen, uptr, vptr, w=0, r=0):
        return struct.pack("<HBBIIIII", n,p,ulen,vlen,uptr,vptr,w,r)
    table.extend(attr(3,1,2,16,primary_uuid_ptr,newdata))
    table.extend(attr(0,1,2,19,char_decl_uuid_ptr,newdata+32))
    table.extend(attr(0,0x23,16,20,newdata+16,BUFFER,a.labels["ble_write"]))
    image.extend(table+service_uuid+char_uuid+declaration)
    while len(image)%16: image.append(255)

    changes=[]
    def patch(offset, expected, replacement):
        expected=bytes.fromhex(expected)
        assert image[offset:offset+len(expected)] == expected, hex(offset)
        assert len(expected) == len(replacement)
        image[offset:offset+len(expected)] = replacement
        changes.append(dict(offset=hex(offset), before=expected.hex(), after=replacement.hex()))
    def word(op, args, offset): return struct.pack("<I", encode(op,args,BASE+offset,a.labels))
    patch(0x13098, "9307b012", word("jal",("zero","bluetooth_sleep_limit"),0x13098))
    patch(0x136dc, "9307b012", word("jal",("zero","receiver_sleep_limit"),0x136dc))
    patch(0x142, "130e2e79", word("addi",("t3","t3",0x7c2),0x142)) # BSS end 928d0 -> 92900
    old_set = source[0x1ba38:0x1ba3c].hex(); old_get = source[0x1bd48:0x1bd4c].hex()
    patch(0x1ba38,old_set,word("jal",("zero","set_dispatch"),0x1ba38))
    patch(0x1bd48,old_get,word("jal",("zero","get_dispatch"),0x1bd48))
    table_address=BASE+table_offset
    patch(0x1180c,"b7070220",word("lui",("a5",(table_address+0x800)>>12),0x1180c))
    patch(0x11814,"9387c713",word("addi",("a5","a5",((table_address+0x800)&0xfff)-0x800),0x11814))
    struct.pack_into("<I",image,0x18,len(image)+4)
    crc=zlib.crc32(image)^0xffffffff; image.extend(struct.pack("<I",crc))
    assert len(image)%16==4 and 0x4000 <= len(image) <= 0x3f000
    assert zlib.crc32(image)^0xffffffff == 0
    return bytes(image), dict(version="0.3-experimental-unverified",sourceSHA256=SOURCE_HASH,
        sha256=hashlib.sha256(image).hexdigest(),crc=f"{crc:08X}",size=len(image),
        bssStart=hex(CFG),bssEnd=hex(END_BSS),codeStart=hex(code_start),codeEnd=hex(code_start+len(code)),
        tableOffset=hex(table_offset),serviceUUID=SERVICE_UUID,characteristicUUID=CHAR_UUID,
        instructions=[dict(address=hex(code_start+4*i),operation=op,args=args) for i,(op,args) in enumerate(a.code)],
        labels={k:hex(v) for k,v in a.labels.items()},patches=changes)

if __name__ == "__main__":
    import sys
    root=Path(__file__).resolve().parents[1]
    data,manifest=build((root/"Resources/GMK104-custom-RGB-v0.2-experimental.bin").read_bytes())
    output=Path(sys.argv[1]) if len(sys.argv)>1 else root.parent/".build/firmware-v0.3"
    output.mkdir(parents=True,exist_ok=True)
    (output/"GMK104-custom-RGB-v0.3-experimental.bin").write_bytes(data)
    (output/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    print(json.dumps({k:manifest[k] for k in ("version","size","sha256","crc")},indent=2))
