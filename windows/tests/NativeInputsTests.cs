using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using Gmk104LightingStudio;

internal static class NativeInputsTests
{
    private static int checks;
    private static void Assert(bool value, string message) { checks++; if (!value) throw new Exception(message); }
    public static int Main(string[] args)
    {
        try
        {
            HashSet<string> produced = new HashSet<string>();
            using (KeyboardInput inactive = new KeyboardInput(IntPtr.Zero))
            {
                Assert(!inactive.IsRunning, "Keyboard input remains off before explicit start");
                inactive.Stop(); Assert(!inactive.IsRunning, "Keyboard stop is idempotent");
            }
            for (ushort scan = 1; scan < 128; scan++)
                for (ushort flags = 0; flags <= 4; flags += 2)
                {
                    string key = KeyboardInput.KeyForScanCode(scan, flags, 1);
                    if (key != null) produced.Add(key);
                }
            KeyGeometry[] layout = new JavaScriptSerializer().Deserialize<KeyGeometry[]>(File.ReadAllText("windows/Resources/layout.json"));
            Assert(layout.Length == 104, "Layout has 104 keys");
            foreach (KeyGeometry key in layout) Assert(produced.Contains(key.id), "Missing scan code: " + key.id);
            Assert(KeyboardInput.KeyForScanCode(0x1D, 0, 0x11) == "ControlLeft", "Left Ctrl");
            Assert(KeyboardInput.KeyForScanCode(0x1D, 2, 0x11) == "ControlRight", "Right Ctrl");
            Assert(KeyboardInput.KeyForScanCode(0x1C, 0, 0x0D) == "Enter", "Main Enter");
            Assert(KeyboardInput.KeyForScanCode(0x1C, 2, 0x0D) == "NumpadEnter", "Keypad Enter");
            Assert(KeyboardInput.KeyForScanCode(0x52, 0, 0x2D) == "Numpad0", "NumLock off keypad does not become Insert");
            Assert(KeyboardInput.KeyForScanCode(0x52, 2, 0x2D) == "Insert", "Dedicated Insert");
            Assert(KeyboardInput.KeyForScanCode(0x2A, 2, 0x10) == null, "Ignore synthesized PrintScreen shift");
            Assert(KeyboardInput.KeyForScanCode(0x1D, 4, 0x11) == null, "Ignore Pause prefix Ctrl");
            Assert(KeyboardInput.KeyForScanCode(0x45, 4, 0x13) == "Pause", "Pause");
            Assert(KeyboardInput.KeyForScanCode(0x45, 2, 0x90) == "NumLock", "Extended NumLock");
            Assert(KeyboardInput.KeyForScanCode(0x46, 2, 0x03) == "Pause", "Ctrl+Pause remains physical Pause");
            Assert(KeyboardInput.KeyForScanCode(0x54, 0, 0x2C) == "PrintScreen", "Alt+PrintScreen remains physical PrintScreen");
            Assert(KeyboardInput.KeyForScanCode(0xFF, 0, 0x41) == null, "Ignore overflow");
            Assert(KeyboardInput.KeyForScanCode(0x1E, 0, 0xFF) == null, "Ignore fake key");

            NativeLightingInputs.AudioAnalyzer analyzer = new NativeLightingInputs.AudioAnalyzer();
            Assert(analyzer.Process(new float[480], 48000, 1).level == 0, "Silence remains dark");
            Assert(Double.IsNegativeInfinity(analyzer.Process(new float[1], 1, 1).timestamp), "Invalid rate rejected");
            float[] bass = Tone(100), mid = Tone(1000), treble = Tone(9000);
            MusicSample b = Settle(bass), m = Settle(mid), t = Settle(treble);
            Assert(b.bass > b.mid && b.bass > b.treble, "100 Hz bass dominance");
            Assert(m.mid > m.bass && m.mid > m.treble, "1 kHz middle dominance");
            Assert(t.treble > t.bass && t.treble > t.mid, "9 kHz treble dominance");
            MusicSample loud = null;
            for (int i = 0; i < 200; i++) loud = analyzer.Process(bass, 48000, i / 100.0);
            Assert(loud.level > 0.95 && loud.level <= 1, "Adaptive gain bounded");
            for (int i = 0; i < 300; i++) loud = analyzer.Process(new float[480], 48000, i / 100.0 + 2);
            Assert(loud.level == 0 && loud.bass == 0 && loud.mid == 0 && loud.treble == 0, "Silence decays all envelopes");
            using (NativeLightingInputs native = new NativeLightingInputs())
            {
                LightingInputs initial = native.Snapshot(12);
                Assert(!initial.audioRunning && initial.music.level == 0, "Constructor does not start audio");
                Assert(initial.cpuCelsius == null, "No fabricated CPU temperature");
                native.StopAudio(); native.StopAudio();
            }
            VerifyWaveFormats();
            if (args.Length == 2 && args[0] == "--identity") VerifyBluetoothIdentity(args[1]);
            Console.WriteLine("NATIVE INPUT TESTS PASS: " + checks + " checks; no audio recording or keyboard subscription started.");
            return 0;
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }
    private static float[] Tone(double frequency)
    {
        float[] values = new float[480];
        for (int i = 0; i < values.Length; i++) values[i] = (float)(0.1 * Math.Sin(2 * Math.PI * frequency * i / 48000));
        return values;
    }
    private static void VerifyWaveFormats()
    {
        object format = ReadFormat(Format(0xFFFE, 2, 32, 48000, true));
        Assert(format != null, "WAVEFORMATEXTENSIBLE 0xFFFE reads correctly under checked+");
        float[] antiPhase = Decode(format, Floats(.5f, -.5f, -.25f, .25f), 2, false);
        Assert(antiPhase[0] == .5f && antiPhase[1] == -.25f, "Opposite phase stereo does not cancel");
        float[] right = Decode(format, Floats(.01f, -.5f, -.01f, .25f), 2, false);
        Assert(right[0] == -.5f && right[1] == .25f, "Strongest right channel selected");
        float[] bad = Decode(format, Floats(float.NaN, float.PositiveInfinity, 0, 0), 2, false);
        Assert(bad.All(v => v == 0), "Nonfinite PCM floats sanitized");
        float[] silence = Decode(format, null, 32, true);
        Assert(silence.Length == 32 && silence.All(v => v == 0), "SILENT flag accepts null packet pointer");
        object pcm16 = ReadFormat(Format(1, 1, 16, 44100, false));
        AssertSequence(Decode(pcm16, new byte[] { 0, 128, 0, 64, 0, 0 }, 3, false), new[] { -1f, .5f, 0f }, "Signed 16-bit PCM");
        object pcm24 = ReadFormat(Format(1, 1, 24, 96000, false));
        AssertSequence(Decode(pcm24, new byte[] { 0, 0, 128, 0, 0, 64, 255, 255, 255 }, 3, false), new[] { -1f, .5f, -1f / 8388608 }, "Signed 24-bit PCM");
        object pcm32 = ReadFormat(Format(0xFFFE, 1, 32, 192000, false));
        AssertSequence(Decode(pcm32, new byte[] { 0, 0, 0, 128, 0, 0, 0, 64 }, 2, false), new[] { -1f, .5f }, "Signed extensible 32-bit PCM");
        Assert(ReadFormat(Format(3, 1, 32, 8000, true)) != null, "8 kHz minimum float format accepted");
        Assert(ReadFormat(Format(3, 1, 32, 384000, true)) != null, "384 kHz maximum float format accepted");
        MustReject(() => ReadFormat(Format(3, 2, 64, 48000, true)), "Unsupported float64 rejected");
        MustReject(() => ReadFormat(Format(1, 0, 16, 48000, false)), "Zero channels rejected");
        MustReject(() => ReadFormat(Format(1, 2, 16, 7999, false)), "Unsupported sample rate rejected");
        byte[] shortExtension = Format(0xFFFE, 2, 32, 48000, true); shortExtension[16] = 2;
        MustReject(() => ReadFormat(shortExtension), "Short extensible format rejected before GUID read");
        byte[] oddAlign = Format(1, 2, 16, 48000, false); oddAlign[12] = 3;
        MustReject(() => ReadFormat(oddAlign), "Inconsistent block alignment rejected");
        byte[] alienSubtype = Format(0xFFFE, 2, 32, 48000, true); alienSubtype[24] = 99;
        MustReject(() => ReadFormat(alienSubtype), "Unknown extensible subtype rejected");
        MustReject(() => Decode(format, null, 65537, true), "Oversized packet rejected");
        MustReject(() => Decode(format, null, 0, true), "Empty direct decode packet rejected");
        MustReject(() => Decode(format, null, 1, false), "Nonsilent null pointer rejected");
    }
    private static byte[] Format(int tag, int channels, int bits, int rate, bool floating)
    {
        byte[] bytes = new byte[40];
        Array.Copy(BitConverter.GetBytes((ushort)tag), 0, bytes, 0, 2);
        Array.Copy(BitConverter.GetBytes((ushort)channels), 0, bytes, 2, 2);
        Array.Copy(BitConverter.GetBytes(rate), 0, bytes, 4, 4);
        Array.Copy(BitConverter.GetBytes(rate * channels * bits / 8), 0, bytes, 8, 4);
        Array.Copy(BitConverter.GetBytes((ushort)(channels * bits / 8)), 0, bytes, 12, 2);
        Array.Copy(BitConverter.GetBytes((ushort)bits), 0, bytes, 14, 2);
        if (tag == 0xFFFE)
        {
            bytes[16] = 22; bytes[18] = (byte)bits;
            Guid guid = new Guid(floating ? "00000003-0000-0010-8000-00aa00389b71" : "00000001-0000-0010-8000-00aa00389b71");
            Array.Copy(guid.ToByteArray(), 0, bytes, 24, 16);
        }
        return bytes;
    }
    private static object ReadFormat(byte[] bytes)
    {
        Type type = typeof(NativeLightingInputs).GetNestedType("WaveFormat", BindingFlags.NonPublic);
        IntPtr pointer = Marshal.AllocHGlobal(bytes.Length);
        try { Marshal.Copy(bytes, 0, pointer, bytes.Length); return type.GetMethod("Read", BindingFlags.Static | BindingFlags.NonPublic).Invoke(null, new object[] { pointer }); }
        finally { Marshal.FreeHGlobal(pointer); }
    }
    private static float[] Decode(object format, byte[] bytes, uint frames, bool silent)
    {
        IntPtr pointer = bytes == null ? IntPtr.Zero : Marshal.AllocHGlobal(bytes.Length);
        try
        {
            if (bytes != null) Marshal.Copy(bytes, 0, pointer, bytes.Length);
            return (float[])format.GetType().GetMethod("StrongestChannel", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(format, new object[] { pointer, frames, silent });
        }
        finally { if (pointer != IntPtr.Zero) Marshal.FreeHGlobal(pointer); }
    }
    private static byte[] Floats(params float[] values)
    {
        byte[] bytes = new byte[values.Length * 4];
        for (int i = 0; i < values.Length; i++) Array.Copy(BitConverter.GetBytes(values[i]), 0, bytes, i * 4, 4);
        return bytes;
    }
    private static void AssertSequence(float[] actual, float[] expected, string message)
    {
        Assert(actual.Length == expected.Length, message + " length");
        for (int i = 0; i < actual.Length; i++) Assert(actual[i] == expected[i], message + " sample " + i);
    }
    private static void MustReject(Action action, string message)
    {
        bool rejected = false;
        try { action(); }
        catch (TargetInvocationException ex) { if (!(ex.InnerException is InvalidOperationException)) throw; rejected = true; }
        Assert(rejected, message);
    }
    private static MusicSample Settle(float[] samples)
    {
        NativeLightingInputs.AudioAnalyzer analyzer = new NativeLightingInputs.AudioAnalyzer(); MusicSample result = null;
        for (int i = 0; i < 100; i++) result = analyzer.Process(samples, 48000, i / 100.0);
        return result;
    }
    private static void VerifyBluetoothIdentity(string selectedPath)
    {
        Type attachment = typeof(KeyboardInput).GetNestedType("Attachment", BindingFlags.NonPublic);
        MethodInfo read = attachment.GetMethod("Read", BindingFlags.Static | BindingFlags.NonPublic);
        MethodInfo match = attachment.GetMethod("Matches", BindingFlags.Instance | BindingFlags.NonPublic);
        FieldInfo known = attachment.GetField("IsGmk104", BindingFlags.Instance | BindingFlags.NonPublic);
        object selected = read.Invoke(null, new object[] { selectedPath });
        uint count = 0, size = (uint)Marshal.SizeOf(typeof(RawDevice));
        Assert(GetRawInputDeviceList(null, ref count, size) != UInt32.MaxValue, "Enumerate raw input metadata");
        RawDevice[] all = new RawDevice[count]; uint found = GetRawInputDeviceList(all, ref count, size);
        Assert(found != UInt32.MaxValue, "Read raw input metadata");
        int matched = 0, rejected = 0;
        for (int i = 0; i < found; i++)
        {
            if (all[i].type != 1) continue;
            uint length = 0; GetRawInputDeviceInfo(all[i].handle, 0x20000007, null, ref length);
            StringBuilder name = new StringBuilder((int)length + 1); GetRawInputDeviceInfo(all[i].handle, 0x20000007, name, ref length);
            object candidate = read.Invoke(null, new object[] { name.ToString() });
            if ((bool)known.GetValue(candidate) && (bool)match.Invoke(candidate, new object[] { selected })) matched++;
            else rejected++;
        }
        Assert(matched >= 1, "Current selected Bluetooth GMK104 must match an actual Raw Input interface");
        object other = read.Invoke(null, new object[] { @"\\?\bthle#dev_000000000000#test-fixture#{781aee18-7733-4ce4-add0-91f41c67b592}" });
        Assert(!(bool)match.Invoke(selected, new object[] { other }), "Different Bluetooth address rejected");
        Console.WriteLine("READ-ONLY DEVICE IDENTITY PASS: " + matched + " selected keyboard interfaces; " + rejected + " other interfaces rejected.");
    }
    [StructLayout(LayoutKind.Sequential)] private struct RawDevice { internal IntPtr handle; internal uint type; }
    [DllImport("user32.dll")] private static extern uint GetRawInputDeviceList([In, Out] RawDevice[] devices, ref uint count, uint size);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint GetRawInputDeviceInfo(IntPtr device, uint command, StringBuilder value, ref uint size);
}
