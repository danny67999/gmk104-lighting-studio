//@category Analysis
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Instruction;
import java.io.PrintWriter;
import java.io.File;

public class VerifyNative extends GhidraScript {
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 3) throw new IllegalArgumentException("output start end required");
        long start = Long.decode(args[1]);
        long end = Long.decode(args[2]);
        if (start >= end || end-start > 4096 || ((end-start) & 3) != 0)
            throw new IllegalArgumentException("invalid code bounds");
        int count = 0;
        try (PrintWriter out = new PrintWriter(new File(args[0]), "UTF-8")) {
            for (long pc = start; pc < end; pc += 4) {
                Address address = toAddr(pc);
                disassemble(address);
                Instruction instruction = getInstructionAt(address);
                if (instruction == null || instruction.getLength() != 4)
                    throw new IllegalStateException("Undecodable instruction at " + address);
                out.println(instruction.getAddress() + " " + instruction);
                count++;
            }
            out.println("DECODED=" + count);
        }
        println("Native ripple instructions decoded: " + count);
    }
}
