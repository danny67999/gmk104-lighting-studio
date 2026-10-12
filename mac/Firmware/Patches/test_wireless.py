"""Instruction-level tests for the experimental patch, not a full MCU emulator."""
import random
from pathlib import Path
import struct
from build_wireless import build, BASE, CFG, BUFFER, END_BSS
from rv32 import signed

SOURCE=(Path(__file__).resolve().parents[1]/"Resources/GMK104-custom-RGB-v0.2-experimental.bin").read_bytes()
IMAGE, MANIFEST=build(SOURCE)
LABELS={k:int(v,16) for k,v in MANIFEST["labels"].items()}
GP=0x80800
SENTINEL=0x30000000

class Machine:
    def __init__(self):
        self.ram=bytearray(0xA0000)
        self.r=[0]+[0x10203000+i*0x104 for i in range(1,32)]
        self.r[2]=0x9f000; self.r[3]=GP; self.r[1]=SENTINEL
        self.pc=0; self.writes=[]
        self.ram[GP+0x40f]=0
        self.ram[GP-0x2df]=19; self.ram[GP-0x2de]=4
    def read(self, address, count):
        if BASE<=address<BASE+len(IMAGE): return IMAGE[address-BASE:address-BASE+count]
        assert 0<=address<=len(self.ram)-count, hex(address)
        return self.ram[address:address+count]
    def val(self, address, size=4): return int.from_bytes(self.read(address,size),"little")
    def put(self,address,value,size=4):
        assert 0<=address<=len(self.ram)-size, hex(address)
        self.ram[address:address+size]=(value & ((1<<(8*size))-1)).to_bytes(size,"little")
        self.writes.extend(range(address,address+size))
    def run(self, entry, stop=SENTINEL):
        self.pc=entry
        for _ in range(100000):
            if self.pc==stop: return
            pc=self.pc; w=self.val(pc); nextpc=pc+4
            # Existing v0.2 helpers remain byte-for-byte identical. Decode only
            # the exact three Andes address instructions used by those helpers.
            known={0x10a4:(15,GP-0x2e0),0x1194:(15,GP-0x2e0),0x1120:(28,GP+0x13d4),0x1164:(28,GP+0x13d4),0x121c:(7,GP+0x13d4)}
            if pc-BASE in known:
                d,value=known[pc-BASE]; self.r[d]=value
            elif pc==BASE+0x1baa8:
                # Bluetooth reaches the original no-USB/no-RF response branch.
                assert self.ram[GP+0x40f]==0
                self.r[15]=0; nextpc=BASE+0x1b964
            elif pc==BASE+0xd2fc:
                # The existing effect initializer already validated on hardware
                # is an explicit stub; its internals are outside this test.
                for i in range(0x13e): self.put(GP+0x13d4+i,0,1)
                self.r[5:8]=[0xabcdef]*3
                self.r[10:18]=[0xdeadbeef]*8
                self.r[28:32]=[0xabcdef]*4
                nextpc=self.r[1]
            elif w & 3 != 3:
                h=w&65535; f=h>>13; q=h&3; d=(h>>7)&31
                nextpc=pc+2
                if q==2 and f==2: # c.lwsp
                    imm=((h>>4)&7)<<2 | ((h>>12)&1)<<5 | ((h>>2)&3)<<6
                    self.r[d]=self.val(self.r[2]+imm)
                elif q==1 and f==3 and d==2: # c.addi16sp
                    imm=((h>>12)&1)<<9 | ((h>>6)&1)<<4 | ((h>>5)&1)<<6 | ((h>>3)&3)<<7 | ((h>>2)&1)<<5
                    self.r[2]=(self.r[2]+signed(imm,10))&0xffffffff
                else: raise AssertionError((hex(pc),hex(h)))
            else:
                op=w&127; d=(w>>7)&31; f=(w>>12)&7; a=(w>>15)&31; b=(w>>20)&31
                x,y=self.r[a],self.r[b]; imm=signed(w>>20,12)
                if op==0x37: self.r[d]=w&0xfffff000
                elif op==0x13:
                    self.r[d]={0:lambda:x+imm,1:lambda:x<<(imm&31),3:lambda:int(x<(imm&0xffffffff)),4:lambda:x^(imm&0xffffffff),5:lambda:x>>(imm&31),6:lambda:x|(imm&0xffffffff),7:lambda:x&(imm&0xffffffff)}[f]()&0xffffffff
                elif op==0x33:
                    self.r[d]={0:lambda:x-y if w>>25==0x20 else x+y,4:lambda:x^y,5:lambda:x>>(y&31),6:lambda:x|y,7:lambda:x&y}[f]()&0xffffffff
                elif op==3:
                    size={0:1,1:2,2:4,4:1,5:2}[f]; v=self.val((x+imm)&0xffffffff,size)
                    self.r[d]=(signed(v,size*8) if f<2 else v)&0xffffffff
                elif op==0x23:
                    imm=signed(((w>>25)<<5)|((w>>7)&31),12)
                    self.put((x+imm)&0xffffffff,y,{0:1,1:2,2:4}[f])
                elif op==0x63:
                    imm=signed(((w>>31)<<12)|(((w>>25)&63)<<5)|(((w>>8)&15)<<1)|(((w>>7)&1)<<11),13)
                    if {0:x==y,1:x!=y,6:x<y,7:x>=y}[f]: nextpc=pc+imm
                elif op==0x6f:
                    imm=signed(((w>>31)<<20)|(((w>>21)&1023)<<1)|(((w>>20)&1)<<11)|(((w>>12)&255)<<12),21)
                    self.r[d]=pc+4; nextpc=pc+imm
                elif op==0x67: self.r[d]=pc+4; nextpc=(x+imm)&0xfffffffe
                else: raise AssertionError((hex(pc),hex(w)))
            self.r[0]=0; self.pc=nextpc
        raise AssertionError("instruction budget exhausted")
    def ble(self, payload, mode=0, opcode=0x12, handle=70, declared=None):
        p=0x90000
        self.r[11]=p; self.ram[GP+0x40f]=mode
        self.put(p+2,len(payload)+3 if declared is None else declared,2)
        self.put(p+6,opcode,1); self.put(p+7,handle,2)
        self.ram[p+9:p+9+len(payload)]=bytes(payload)
        self.writes=[]; original=self.r.copy()
        self.run(LABELS["ble_write"])
        for r in (1,2,3,4,8,9,18,19,20,21,22,23,24,25,26,27): assert self.r[r]==original[r],r
        assert self.r[10] in (0,0x0d)
        return self.ram[BUFFER:BUFFER+20]

def tests():
    bundled=Path(__file__).resolve().parents[1]/"Resources/GMK104-custom-RGB-v0.3-experimental.bin"
    assert IMAGE==bundled.read_bytes(), "Rebuilt patch differs from the bundled image"
    # Exact mutation inventory: bytes outside approved hook sites, header and
    # appended region must match the known-good source, including all old ATT
    # handles, RF code, OTA handler, HID report map and keymaps.
    allowed=set(range(0x18,0x1c))
    for p in MANIFEST["patches"]:
        allowed.update(range(int(p["offset"],16),int(p["offset"],16)+len(bytes.fromhex(p["before"]))))
    assert all(x==y or i in allowed for i,(x,y) in enumerate(zip(SOURCE[:-4],IMAGE)))
    table=int(MANIFEST["tableOffset"],16)
    assert IMAGE[table+2:table+68*24]==SOURCE[0x2013c+2:0x2079c]
    assert struct.unpack_from("<H",IMAGE,table)[0]==70
    assert struct.unpack_from("<HBBIIIII",IMAGE,table+70*24)[1:]==(0x23,16,20,BASE+table+71*24+16,BUFFER,LABELS["ble_write"],0)
    assert struct.unpack_from("<I",IMAGE,0x142)[0]>>20==0x7c2
    assert (0x2000013e+0xe0092000+0x7c2)&0xffffffff==END_BSS
    # Both modes: default, Never, every offered time and bounds, only a5 changes.
    for seconds in (None,0,60,120,300,600,900,1800,3600):
        raw=0 if seconds is None else seconds+1
        expected=299 if seconds is None else ((seconds-1)&0xffffffff)
        for label,stop in (("bluetooth_sleep_limit",BASE+0x1309c),("receiver_sleep_limit",BASE+0x136e0)):
            m=Machine(); m.put(CFG,raw); before=m.r.copy(); m.run(LABELS[label],stop)
            assert m.r[15]==expected
            assert all(v==m.r[r] for r,v in enumerate(before) if r!=15)
    # Real existing v0.2 getter executes: all 104 RGB samples and checksum.
    m=Machine(); rng=random.Random(104)
    colors=bytes(rng.randrange(256) for _ in range(312)); m.ram[GP+0x13d4:GP+0x13d4+312]=colors
    for index in range(104):
        result=m.ble([8,3,5,index])
        assert m.r[10]==0
        assert result[:11]==bytes([8,3,5,2,104,9,15,71,77,75,2])
        assert result[11]==index and result[12:15]==colors[index*3:index*3+3]
        assert int.from_bytes(result[17:19],"little")==sum(colors)%65536
    # Pack a complete frame in default-MTU-safe chunks; getter sees the exact data.
    m=Machine()
    for start in range(0,104,5):
        count=min(5,104-start); m.ble([7,3,5,start,count]+list(colors[start*3:(start+count)*3]))
    assert m.ram[GP+0x13d4:GP+0x13d4+312]==colors
    assert m.ble([8,3,5,103])[12:15]==colors[-3:]
    # Entry from a stock effect exercises the existing init call/stack adapter.
    m=Machine(); m.ram[GP-0x2df]=1; m.ble([7,3,5,103,1,12,34,56])
    assert m.ram[GP+0x13d4+309:GP+0x13d4+312]==bytes([12,34,56])
    assert m.ram[GP-0x2df]==19
    # Settings round trip and strict bounds; writes remain volatile RAM only.
    for seconds in (0,1,59,60,120,300,600,900,1800,3600,3601,65535):
        m=Machine(); m.ble([7,3,6,1,seconds&255,seconds>>8]); result=m.ble([8,3,6,1])
        expected=seconds if seconds==0 or 60<=seconds<=3600 else 300
        assert result[:8]==bytes([8,3,6,1,71,77,75,83])
        assert int.from_bytes(result[8:10],"little")==expected
    invalid=[[1,0,0,0],[7,1,5,0],[7,3,2,19],[7,3,1,5],[7,3,9,0],[8,3,5,104],[8,3,6,2],
        [7,3,5,0,6]+[1]*18,[7,3,5,103,2]+[1]*6,[7,3,5,1,0], [7,3,5,0,1,1,2], [7,3,5,0,1,1,2,3,4], [7,3,6,1]]
    for payload in invalid:
        m=Machine(); m.ble(payload); assert not m.writes,payload
        assert m.r[10]==0x0d
    for mode,opcode,handle,declared in ((1,0x12,70,None),(2,0x12,70,None),(0,0x16,70,None),(0,0x12,15,None),(0,0x12,326,None),(0,0x12,70,2),(0,0x12,70,24)):
        m=Machine(); m.ble([8,3,5,0],mode,opcode,handle,declared); assert not m.writes
    print("PASS: exact patch inventory, ATT handles/security, BSS range, both sleep thresholds, existing RGB code execution, all 104 LEDs, stack/register preservation, malformed packet rejection and sleep bounds")
    print("Not a full MCU/BLE-stack emulator; physical boot, Bluetooth throughput and sleep/wake remain unverified.")

if __name__=="__main__": tests()
