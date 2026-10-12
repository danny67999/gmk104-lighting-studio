"""Instruction-level RV32I tests of injected trampolines, without hardware."""
from __future__ import annotations

import struct
import unittest

import build
from rv32 import REGS


def sx(value: int, bits: int) -> int:
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


class Machine:
    def __init__(self, code: bytes, labels: dict, entries: dict):
        self.code = code
        self.labels = labels
        self.entries = entries
        self.regs = [0x10000000 + i * 0x10101 for i in range(32)]
        self.regs[0] = 0
        self.regs[REGS["sp"]] = 0x9F000
        self.regs[REGS["gp"]] = 0x91000
        self.regs[REGS["a0"]] = 39  # W in the confirmed factory LED map
        self.regs[REGS["a2"]] = 0x80000
        self.mem = {}
        self.calls = []
        self.saved = tuple(self.regs)
        self.base = min(labels.values())

    def put(self, address: int, values: bytes) -> None:
        for i, byte in enumerate(values):
            self.mem[address + i] = byte

    def get(self, address: int, length: int) -> bytes:
        return bytes(self.mem.get(address + i, 0) for i in range(length))

    def run(self, start: int, stops: set[int], callback=None) -> int:
        pc = start
        for _ in range(5000):
            if pc in stops:
                return pc
            for name, address in self.entries.items():
                if pc == address:
                    self.calls.append(name)
                    if callback: callback(name, self)
                    resume = self.regs[1]
                    for index in (1, 5, 6, 7, 28, 29, 30, 31,
                                  10, 11, 12, 13, 14, 15, 16, 17):
                        self.regs[index] = 0xDEAD0000 + index
                    pc = resume
                    break
            else:
                assert self.base <= pc < self.base + len(self.code), hex(pc)
                assert (pc - self.base) % 4 == 0
                word = struct.unpack_from("<I", self.code, pc - self.base)[0]
                op = word & 0x7F
                rd = (word >> 7) & 31
                rs1 = (word >> 15) & 31
                rs2 = (word >> 20) & 31
                funct = (word >> 12) & 7
                next_pc = pc + 4
                if op == 0x13:  # addi
                    assert funct == 0
                    self.regs[rd] = (self.regs[rs1] + sx(word >> 20, 12)) & 0xFFFFFFFF
                elif op == 0x37:  # lui
                    self.regs[rd] = word & 0xFFFFF000
                elif op == 0x03:  # lbu/lw
                    at = (self.regs[rs1] + sx(word >> 20, 12)) & 0xFFFFFFFF
                    if funct == 4:
                        self.regs[rd] = self.get(at, 1)[0]
                    else:
                        assert funct == 2
                        self.regs[rd] = int.from_bytes(self.get(at, 4), "little")
                elif op == 0x23:  # sb/sw
                    at = (self.regs[rs1] + sx(((word >> 25) << 5) | rd, 12)) & 0xFFFFFFFF
                    if funct == 0:
                        self.put(at, bytes([self.regs[rs2] & 255]))
                    else:
                        assert funct == 2
                        self.put(at, self.regs[rs2].to_bytes(4, "little"))
                elif op == 0x63:  # beq/bne/bltu
                    offset = ((word >> 31) << 12 | ((word >> 7) & 1) << 11 |
                              ((word >> 25) & 63) << 5 | ((word >> 8) & 15) << 1)
                    taken = ((funct == 0 and self.regs[rs1] == self.regs[rs2]) or
                             (funct == 1 and self.regs[rs1] != self.regs[rs2]) or
                             (funct == 6 and self.regs[rs1] < self.regs[rs2]))
                    assert funct in (0, 1, 6)
                    if taken: next_pc = pc + sx(offset, 13)
                elif op == 0x6F:  # jal
                    offset = ((word >> 31) << 20 | ((word >> 12) & 255) << 12 |
                              ((word >> 20) & 1) << 11 | ((word >> 21) & 1023) << 1)
                    if rd: self.regs[rd] = pc + 4
                    next_pc = pc + sx(offset, 21)
                else:
                    raise AssertionError(f"unsupported opcode {op:02x} at {pc:08x}")
                self.regs[0] = 0
                pc = next_pc
        raise AssertionError("trampoline did not terminate")


class HookTests(unittest.TestCase):
    def setUp(self):
        plan = build.layout()
        self.active = build.RAM_BSS_END
        self.entries = {name: plan["payloadBase"] + i * 4 for i, name in
                        enumerate(("dispatch", "init", "key_down", "render"))}
        self.code, self.labels = build._assembly(plan["hookBase"], self.entries,
                                                   self.active, self.active + 0x2100)
        self.assertEqual(len(self.code), plan["hookBytes"])

    def machine(self, active: int = 0) -> Machine:
        machine = Machine(self.code, self.labels, self.entries)
        machine.put(self.active, bytes([active]))
        machine.put(machine.regs[REGS["gp"]] - 0x2df, bytes([20]))
        machine.put(machine.regs[REGS["gp"]] + 0x624, bytes([1]))
        machine.put(machine.regs[REGS["gp"]] + 0x655, bytes([20]))
        return machine

    def assert_preserved(self, machine: Machine) -> None:
        for register in "ra sp gp tp t0 t1 t2 t3 t4 t5 t6 a0 a1 a2 a3 a4 a5 a6 a7".split():
            self.assertEqual(machine.regs[REGS[register]], machine.saved[REGS[register]], register)

    def test_scan_fallback_and_key_press(self):
        old = self.machine()
        self.assertEqual(old.run(self.labels["scan"], {build.EXPECTED["scan"]}), build.EXPECTED["scan"])
        self.assertFalse(old.calls)
        self.assert_preserved(old)
        active = self.machine(1)
        self.assertEqual(active.run(self.labels["scan"], {build.BASE + 0xBE4C}), build.BASE + 0xBE4C)
        self.assertEqual(active.calls, ["key_down"])
        self.assert_preserved(active)
        self.assertEqual(active.get(active.regs[REGS["gp"]] + 0x560, 1), b"\0")
        # A held/repeated key never creates an extra event.
        repeat = self.machine(1)
        repeat.put(repeat.regs[REGS["gp"]] + 0x624, b"\0")
        repeat.run(self.labels["scan"], {build.BASE + 0xBE4C})
        self.assertFalse(repeat.calls)

    def test_set_get_dispatch_preserve_packet_pointer_and_fallback(self):
        for name, op in (("set", 7), ("get", 8)):
            for accepted in (False, True):
                machine = self.machine()
                machine.put(machine.regs[REGS["a2"]], bytes([op, 3, 7 if accepted else 6]))
                end = build.BASE + 0x1BAA8 if accepted else build.EXPECTED[name]
                self.assertEqual(machine.run(self.labels[name], {end}), end)
                self.assertEqual(machine.calls, ["dispatch"] if accepted else [])
                self.assert_preserved(machine)

    def test_mode_init_render_and_bss(self):
        machine = self.machine()
        self.assertEqual(machine.run(self.labels["init"], {build.EXPECTED["init_table"]}),
                         build.EXPECTED["init_table"])
        self.assertEqual(machine.calls, ["init"])
        active = self.machine(1)
        self.assertEqual(active.run(self.labels["init"], {build.STOCK_INIT_EPILOGUE}),
                         build.STOCK_INIT_EPILOGUE)
        render = self.machine(1)
        self.assertEqual(render.run(self.labels["render"], {build.STOCK_RENDER_EPILOGUE}),
                         build.STOCK_RENDER_EPILOGUE)
        self.assertEqual(render.calls, ["render"])
        self.assertEqual(render.get(render.regs[REGS["gp"]] + 0x655, 1), b"\0")
        original = self.machine()
        self.assertEqual(original.run(self.labels["render"], {build.EXPECTED["render_table"]}),
                         build.EXPECTED["render_table"])
        self.assertFalse(original.calls)
        bss = self.machine()
        bss.regs[REGS["t3"]] = 0x9213E
        self.assertEqual(bss.run(self.labels["bss_extend"], {build.BASE + 0x146}),
                         build.BASE + 0x146)
        self.assertEqual(bss.regs[REGS["t3"]], 0x9213E + 0x7F2 + 0x2100)


if __name__ == "__main__":
    unittest.main()
