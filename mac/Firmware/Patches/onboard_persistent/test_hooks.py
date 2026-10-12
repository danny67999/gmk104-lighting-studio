"""Simulate both scan transitions and caller register preservation."""
from pathlib import Path
import sys
import unittest

import build
from types import SimpleNamespace

def full_hook(base, flag, callback, name):
    entries={key:base+0x1000+index*4 for index,key in enumerate(("dispatch","init","key_change","render","boot"))}
    entries[name]=callback
    return build._assembly(base,entries,flag,flag+16)
scan_hook=SimpleNamespace(assemble=lambda base,flag,callback:full_hook(base,flag,callback,"key_change"), SCAN_SITE=build.BASE+0xBE48, FALLBACK=build.EXPECTED["scan"])
startup_hook=SimpleNamespace(assemble=lambda base,flag,callback:full_hook(base,flag,callback,"boot"), CONTINUE=build.BASE+0x10294)

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "onboard_v08"))
from test_hooks import Machine
from rv32 import REGS


class TransitionHookTests(unittest.TestCase):
    def test_press_and_release_reach_runtime_with_registers_preserved(self):
        active_flag, callback = 0x92930, 0x20027000
        code, labels = scan_hook.assemble(0x20024000, active_flag, callback)
        for state in (0, 255):
            machine = Machine(code, labels, {"key_change": callback})
            machine.put(active_flag, b"\x01")
            machine.put(machine.regs[REGS["gp"]] - 0x2df, b"\x14")
            machine.put(machine.regs[REGS["gp"]] + 0x624, bytes([state]))
            observed = []
            end = machine.run(labels["scan"], {scan_hook.SCAN_SITE + 4},
                              lambda name, m: observed.append((name, m.regs[REGS["a0"]], m.regs[REGS["a1"]])))
            self.assertEqual(end, scan_hook.SCAN_SITE + 4)
            self.assertEqual(observed, [("key_change", 39, state)])
            for register in "ra sp gp tp t0 t1 t2 t3 t4 t5 t6 a0 a1 a2 a3 a4 a5 a6 a7".split():
                self.assertEqual(machine.regs[REGS[register]], machine.saved[REGS[register]])

    def test_inactive_or_stock_mode_keeps_stock_scan(self):
        active_flag, callback = 0x92930, 0x20027000
        code, labels = scan_hook.assemble(0x20024000, active_flag, callback)
        for active, mode in ((0, 20), (1, 1)):
            machine = Machine(code, labels, {"key_change": callback})
            machine.put(active_flag, bytes([active]))
            machine.put(machine.regs[REGS["gp"]] - 0x2df, bytes([mode]))
            self.assertEqual(machine.run(labels["scan"], {scan_hook.FALLBACK}), scan_hook.FALLBACK)
            self.assertFalse(machine.calls)


class StartupHookTests(unittest.TestCase):
    def test_exact_stock_site_and_remaining_epilogue(self):
        root = Path(__file__).resolve().parents[4]
        self.assertEqual(build.source_layout()["image"][0x10290:0x10294], bytes.fromhex("f6406644"))

    def test_restored_profile_selects_custom_mode_before_stock_cleanup(self):
        flag, callback = 0x92930, 0x20027000
        code, labels = startup_hook.assemble(0x20024000, flag, callback)
        for restored in (False, True):
            machine = Machine(code, labels, {"boot": callback})
            sp = machine.regs[REGS["sp"]]
            machine.put(sp + 92, machine.saved[REGS["ra"]].to_bytes(4, "little"))
            machine.put(sp + 88, machine.saved[REGS["s0"]].to_bytes(4, "little"))
            mode = machine.regs[REGS["gp"]] - 0x2df
            machine.put(mode, b"\x03")
            def restore(name, emulator):
                self.assertEqual(name, "boot")
                self.assertEqual(emulator.get(mode, 1), b"\x03")
                emulator.put(flag, bytes([restored]))
            self.assertEqual(machine.run(labels["startup"], {startup_hook.CONTINUE}, restore),
                             startup_hook.CONTINUE)
            self.assertEqual(machine.get(mode, 1), b"\x14" if restored else b"\x03")
            for register in "ra sp gp tp s0 t0 t1 t2 t3 t4 t5 t6 a0 a1 a2 a3 a4 a5 a6 a7".split():
                self.assertEqual(machine.regs[REGS[register]], machine.saved[REGS[register]], register)


if __name__ == "__main__":
    unittest.main()
