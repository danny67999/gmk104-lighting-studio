"""Small RV32I encoder for the fixed GMK104 patch; no vendor toolchain needed."""
import struct

REGS = dict(zip("zero ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6".split(), range(32)))

def reg(name):
    return REGS[name]

def signed(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value

def encode(op, args, pc=0, labels=None):
    labels = labels or {}
    def target(value):
        return labels[value] if isinstance(value, str) else value
    if op == "lui":
        d, imm = args
        return ((imm & 0xfffff) << 12) | reg(d) << 7 | 0x37
    if op in ("addi", "andi", "ori", "xori", "slli", "srli", "sltiu"):
        d, a, imm = args
        f = {"addi": 0, "andi": 7, "ori": 6, "xori": 4, "slli": 1, "srli": 5, "sltiu": 3}[op]
        assert -2048 <= imm <= 2047
        return (imm & 4095) << 20 | reg(a) << 15 | f << 12 | reg(d) << 7 | 0x13
    if op in ("add", "sub", "or", "xor", "and", "srl"):
        d, a, b = args
        f = {"add": 0, "sub": 0, "or": 6, "xor": 4, "and": 7, "srl": 5}[op]
        return (0x20 if op == "sub" else 0) << 25 | reg(b) << 20 | reg(a) << 15 | f << 12 | reg(d) << 7 | 0x33
    if op in ("lb", "lbu", "lh", "lhu", "lw", "jalr"):
        d, a, imm = args
        f = {"lb": 0, "lbu": 4, "lh": 1, "lhu": 5, "lw": 2, "jalr": 0}[op]
        assert -2048 <= imm <= 2047
        return (imm & 4095) << 20 | reg(a) << 15 | f << 12 | reg(d) << 7 | (0x67 if op == "jalr" else 3)
    if op in ("sb", "sh", "sw"):
        b, a, imm = args
        assert -2048 <= imm <= 2047
        imm &= 4095
        return (imm >> 5) << 25 | reg(b) << 20 | reg(a) << 15 | {"sb": 0, "sh": 1, "sw": 2}[op] << 12 | (imm & 31) << 7 | 0x23
    if op in ("beq", "bne", "bltu", "bgeu"):
        a, b, dest = args
        imm = target(dest) - pc
        assert -4096 <= imm <= 4094 and imm % 2 == 0
        imm &= 8191
        return (imm >> 12) << 31 | ((imm >> 5) & 63) << 25 | reg(b) << 20 | reg(a) << 15 | {"beq": 0, "bne": 1, "bltu": 6, "bgeu": 7}[op] << 12 | ((imm >> 1) & 15) << 8 | ((imm >> 11) & 1) << 7 | 0x63
    if op == "jal":
        d, dest = args
        imm = target(dest) - pc
        assert -(1 << 20) <= imm < (1 << 20) and imm % 2 == 0
        imm &= (1 << 21) - 1
        return (imm >> 20) << 31 | ((imm >> 1) & 1023) << 21 | ((imm >> 11) & 1) << 20 | ((imm >> 12) & 255) << 12 | reg(d) << 7 | 0x6f
    raise ValueError(op)

class Assembly:
    def __init__(self, base):
        self.base, self.code, self.labels = base, [], {}
    @property
    def pc(self):
        return self.base + 4 * len(self.code)
    def label(self, name):
        assert name not in self.labels
        self.labels[name] = self.pc
    def emit(self, op, *args):
        self.code.append((op, args))
    def li(self, d, value):
        if -2048 <= value <= 2047:
            self.emit("addi", d, "zero", value)
        else:
            self.emit("lui", d, (value + 0x800) >> 12)
            self.emit("addi", d, d, signed(value, 12))
    def jump(self, target):
        self.emit("jal", "zero", target)
    def finish(self):
        return b"".join(struct.pack("<I", encode(op, args, self.base + 4*i, self.labels)) for i, (op, args) in enumerate(self.code))
