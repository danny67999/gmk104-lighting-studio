"""Actual performance trampoline checks plus unchanged image-boundary tests."""
import unittest
import performance_build as build
import test_build
from pathlib import Path
import importlib.util
spec = importlib.util.spec_from_file_location("gmk_budget_vm", Path(__file__).resolve().parents[1] / "onboard_v08/test_hooks.py")
vm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vm)
Machine = vm.Machine
from rv32 import REGS

test_build.build = build
PackageTests = test_build.PackageTests

class RenderBudgetHooks(unittest.TestCase):
    def test_each_visit_passes_elapsed_time_and_only_complete_frames_publish(self):
        plan = build.layout()
        flag = build.RAM_BSS_END
        entries = {key:plan["payloadBase"]+0x1000+i*4 for i,key in enumerate(("dispatch","init","key_change","render","boot"))}
        code,labels = build._assembly(plan["hookBase"],entries,flag,flag+16)
        for elapsed in (0,1,20,255):
            for complete in (0,1):
                m = Machine(code,labels,entries)
                m.put(flag,b"\1")
                m.put(m.regs[REGS["gp"]]+0x655,bytes([elapsed]))
                calls=[]
                def callback(name,vm):
                    calls.append((name,vm.regs[REGS["a0"]],vm.regs[REGS["a1"]]))
                    return complete
                endpoint = build.STOCK_RENDER_EPILOGUE if complete else build.STOCK_RENDER_IDLE
                self.assertEqual(m.run(labels["render"],{endpoint},callback),endpoint)
                self.assertEqual(calls,[("render",build.FRAME,elapsed)])
                self.assertEqual(m.get(m.saved[REGS["gp"]]+0x655,1),b"\0")
                for register in ("ra","sp","gp","tp"):
                    self.assertEqual(m.regs[REGS[register]],m.saved[REGS[register]])
    def test_no_profile_retains_stock_renderer(self):
        plan=build.layout();flag=build.RAM_BSS_END
        entries={key:plan["payloadBase"]+0x1000+i*4 for i,key in enumerate(("dispatch","init","key_change","render","boot"))}
        code,labels=build._assembly(plan["hookBase"],entries,flag,flag+16)
        m=Machine(code,labels,entries)
        self.assertEqual(m.run(labels["render"],{build.EXPECTED["render_table"]}),build.EXPECTED["render_table"])
        self.assertFalse(m.calls)

if __name__=="__main__":unittest.main()
