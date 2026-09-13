using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

namespace Gmk104LightingStudio
{
    internal static class TransportTests
    {
        private static int assertions;
        private static void Check(bool value, string label) { assertions++; if (!value) throw new Exception("FAILED: " + label); }
        private static void Reject(Action action, string label) { bool rejected = false; try { action(); } catch (Exception) { rejected = true; } Check(rejected, label); }
        public static int Main(string[] args)
        {
            try
            {
                if (args.Contains("--probe") || args.Contains("--probe-usb"))
                {
                    // A probe exchanges GET commands only; no lighting setting is sent.
                    string transport = args.Contains("--probe-usb") ? "USB" : "Bluetooth";
                    using (RGBClient client = new RGBClient(KeyboardConnections.Open(transport)))
                    {
                        Console.WriteLine("Connection: " + client.Transport.ConnectionName);
                        Console.WriteLine("Identity: " + client.Transport.DeviceIdentity);
                        BluetoothTransport bluetooth = client.Transport as BluetoothTransport;
                        if (bluetooth != null) Console.WriteLine("Advertised fast frame writes: " + bluetooth.SupportsFastFrameWrites);
                        client.Transport.CheckSingleDevice(); RGBState s = client.Read();
                        Console.WriteLine("Verified custom signature. Effect=" + s.Effect + " brightness=" + s.Brightness + " checksum=" + s.Checksum.ToString("X4") + " LED0=" + s.Color.r + "," + s.Color.g + "," + s.Color.b);
                        Console.WriteLine("Sleep seconds: " + Convert.ToString(client.ReadSleepSeconds()));
                        if (transport == "USB" && s.Effect == 19) Console.WriteLine("Full-frame GET verified: " + client.ReadFrame().Length + " LEDs");
                        else if (transport == "USB") Console.WriteLine("Stable direct-frame scan skipped: a built-in effect is active; no lighting mode was changed.");
                    }
                    Console.WriteLine("READ-ONLY " + transport.ToUpperInvariant() + " PROBE PASS"); return 0;
                }
                if (args.Contains("--discover"))
                {
                    foreach (Native.Device d in Native.Interfaces(BluetoothTransport.DeviceGuid)) Console.WriteLine("DEVICE " + d.Name + " node=" + d.Node + " " + d.Path);
                    foreach (Native.Device d in Native.Interfaces(BluetoothTransport.ServiceInterface)) Console.WriteLine("SERVICE " + d.Name + " node=" + d.Node + " " + d.Path);
                    return 0;
                }
                CheckReportStream();
                Check(Marshal.SizeOf(typeof(Native.GattUuid)) == 20, "native UUID size");
                Check(Marshal.SizeOf(typeof(Native.GattCharacteristic)) == 36, "native characteristic size");
                Check(Marshal.OffsetOf(typeof(Native.GattCharacteristic), "Readable").ToInt32() == 29, "BOOLEAN native field offsets");
                RGB[] frame = Enumerable.Range(0, 104).Select(i => new RGB((byte)i, (byte)(103-i), (byte)(i/2))).ToArray();
                List<byte[]> ble = LightingPackets.Frame(frame, 5), usb = LightingPackets.Frame(frame, 9);
                Check(ble.Count == 21 && ble.All(p => p.Length <= 20), "BLE 21 bounded ATT packets");
                Check(usb.Count == 12 && usb.All(p => p.Length <= 32), "HID 12 bounded reports");
                List<byte[]> split = LightingPackets.ValidateAndSplit(usb[0], true);
                Check(split.Count == 2 && split[0][4] == 5 && split[1][3] == 5 && split[1][4] == 4, "BLE splits HID batch without losing index");
                Check(split.SelectMany(p => p.Skip(5)).SequenceEqual(usb[0].Skip(5)), "BLE preserves RGB payload");
                Check(LightingPackets.NormalizeBluetooth(new byte[20]).Length == 32, "BLE reply normalization");
                Reject(() => LightingPackets.NormalizeBluetooth(new byte[19]), "short ATT reply rejected");
                Reject(() => LightingPackets.ValidateAndSplit(new byte[] { 7, 3, 5, 103, 2, 0, 0, 0, 0, 0, 0 }, true), "out of range rejected");
                Reject(() => LightingPackets.ValidateAndSplit(new byte[] { 7, 3, 5, 1, 0 }, true), "misplaced clear rejected");
                Reject(() => LightingPackets.ValidateAndSplit(new byte[] { 0x80, 0, 0, 0 }, true), "nonlighting commands rejected");
                Reject(() => LightingPackets.ValidateAndSplit(new byte[] { 7, 3, 2, 19 }, true), "uninitialized direct effect rejected");
                Reject(() => LightingPackets.ValidateAndSplit(new byte[] { 7, 3, 6, 1, 59, 0 }, true), "short sleep rejected");
                using (Fake fake = new Fake()) using (RGBClient client = new RGBClient(fake))
                {
                    fake.SignatureOK = false; Reject(() => client.SetFrame(frame), "stock signature rejects writes"); Check(fake.Writes == 0, "no write before custom gate"); fake.SignatureOK = true;
                    fake.Brightness = 0; Reject(() => client.SetFrame(frame), "zero brightness rejects invisible frame"); Check(fake.Writes == 0, "no invisible frame sent"); fake.Brightness = 4;
                    Reject(() => client.SetLED(0, new RGB(1, 2, 3)), "initial partial mode transition rejected"); Check(fake.Writes == 0, "initial partial no writes");
                    client.SetFrame(frame); Check(client.Shadow.SequenceEqual(frame), "full-frame verified shadow");
                    // External change with an identical additive checksum must survive the per-key edit.
                    fake.Frame[2] = new RGB(10, 20, 30); fake.Frame[3] = new RGB(30, 20, 10);
                    client.ReadFrame(); fake.Frame[2] = new RGB(30, 20, 10); fake.Frame[3] = new RGB(10, 20, 30);
                    client.SetLED(1, new RGB(9, 8, 7)); Check(client.Shadow[2].Equals(new RGB(30, 20, 10)), "per-key scans resist checksum collision");
                    fake.WhiteIndicator = 14; client.SetFrame(frame); Check(client.Shadow[14].Equals(new RGB(255, 255, 255)), "known white status override accepted");
                    fake.WhiteIndicator = 15; Reject(() => client.SetFrame(frame), "unknown white index rejected"); Check(client.Shadow == null, "failed verification clears shadow");
                    fake.WhiteIndicator = -1; fake.WrongColorIndex = 14; Reject(() => client.SetFrame(frame), "known status index wrong nonwhite rejected"); fake.WrongColorIndex = -1;
                    client.SetBrightness(2); Check(fake.Brightness == 2, "brightness readback"); client.SetSleepSeconds(120); Check(client.ReadSleepSeconds() == 120, "sleep readback");
                    client.SetAnimationFrame(frame); int reads = fake.Reads; client.SetAnimationFrame(frame); Check(fake.Reads - reads < 12, "BLE rolling animation uses bounded reads"); Check(client.Shadow == null, "sampled animation never trusts shadow");
                    client.SetLED(0, new RGB(1, 1, 1)); Check(client.Shadow[0].Equals(new RGB(1, 1, 1)), "per-key after animation rebuilds full shadow");
                    fake.ChangeDuringRead = true; Reject(() => client.ReadFrame(), "unstable frame rejected"); Check(client.Shadow == null, "unstable shadow invalidated");
                }
                Console.WriteLine("TRANSPORT / PROTOCOL TESTS PASS (" + assertions + " assertions)"); return 0;
            }
            catch (Exception ex) { Console.Error.WriteLine(ex.ToString()); return 1; }
        }
        private static void CheckReportStream()
        {
            // Exercise the production stream factory without opening a keyboard.
            // A completed report write must reach the handle without Flush, and
            // reading one report must not prefetch bytes from the next response.
            string path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "hid-stream-" + Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                File.WriteAllBytes(path, new byte[66]);
                using (var handle = Native.Open(path, true, true))
                using (FileStream stream = HidTransport.OpenReportStream(handle))
                using (FileStream observer = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite, 1))
                {
                    byte[] report = Enumerable.Repeat((byte)0x5A, 33).ToArray();
                    var write = stream.WriteAsync(report, 0, report.Length);
                    Check(write.Wait(2000), "report write completes within deadline");
                    byte[] actual = new byte[33];
                    Check(observer.Read(actual, 0, actual.Length) == 33 && actual.SequenceEqual(report), "completed HID-sized write is not buffered");
                    stream.Position = 0;
                    var read = stream.ReadAsync(actual, 0, actual.Length);
                    Check(read.Wait(2000) && read.Result == 33 && actual.SequenceEqual(report), "one complete report read");
                    observer.Position = 33;
                    observer.Write(report, 0, report.Length);
                    read = stream.ReadAsync(actual, 0, actual.Length);
                    Check(read.Wait(2000) && read.Result == 33 && actual.SequenceEqual(report), "report read does not prefetch the next response");
                }
            }
            finally { if (File.Exists(path)) File.Delete(path); }
        }
        private sealed class Fake : IReportTransport
        {
            internal RGB[] Frame = new RGB[104]; internal int Effect = 0, Brightness = 4, Writes, Reads, Sleep = 300, WhiteIndicator = -1, WrongColorIndex = -1;
            internal bool SignatureOK = true, ChangeDuringRead;
            public string ConnectionName { get { return "Mock Bluetooth"; } }
            public string DeviceIdentity { get { return "mock"; } }
            public bool UsesRollingAnimationVerification { get { return true; } }
            public void CheckSingleDevice() { }
            public void Dispose() { }
            public void WriteFrame(RGB[] frame) { Writes++; Frame = (RGB[])frame.Clone(); Effect = 19; if (WhiteIndicator >= 0) Frame[WhiteIndicator] = new RGB(255, 255, 255); if (WrongColorIndex >= 0) Frame[WrongColorIndex] = new RGB(1, 2, 3); }
            public byte[] Exchange(byte[] p)
            {
                byte[] result = new byte[32];
                if (p[0] == 8)
                {
                    Reads++;
                    if (p[2] == 6) { byte[] sleep = { 8, 3, 6, 1, 71, 77, 75, 83, (byte)(Sleep & 255), (byte)(Sleep >> 8), 3, 3, 16, 14, 60, 0 }; Array.Copy(sleep, result, sleep.Length); return result; }
                    byte[] signature = { 8, 3, 5, 2, 104, 9, 15, 71, 77, 75, 2 }; Array.Copy(signature, result, signature.Length); if (!SignatureOK) result[10] = 1;
                    int i = p[3]; result[11] = (byte)i; result[12] = Frame[i].r; result[13] = Frame[i].g; result[14] = Frame[i].b; result[15] = (byte)Effect; result[16] = (byte)Brightness;
                    ushort sum = RGBClient.Sum(Frame); result[17] = (byte)(sum & 255); result[18] = (byte)(sum >> 8); if (ChangeDuringRead && i == 7) result[17] ^= 1; return result;
                }
                Writes++;
                if (p[2] == 1) Brightness = p[3]; else if (p[2] == 2) Effect = p[3]; else if (p[2] == 6) Sleep = p[4] | p[5] << 8;
                else if (p[2] == 5) { Effect = 19; if (p[4] == 0) Frame = new RGB[104]; else for (int j = 0; j < p[4]; j++) Frame[p[3] + j] = new RGB(p[5 + j * 3], p[6 + j * 3], p[7 + j * 3]); }
                return result;
            }
        }
    }
}
