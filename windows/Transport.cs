using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace Gmk104LightingStudio
{
    public interface IReportTransport : IDisposable
    {
        string ConnectionName { get; }
        bool UsesRollingAnimationVerification { get; }
        string DeviceIdentity { get; }
        byte[] Exchange(byte[] payload);
        void WriteFrame(RGB[] frame);
        void CheckSingleDevice();
    }
    public sealed class TransportUnavailableException : IOException
    {
        public TransportUnavailableException(string message) : base(message) { }
        public TransportUnavailableException(string message, Exception inner) : base(message, inner) { }
    }

    internal static class LightingPackets
    {
        internal static List<byte[]> Frame(RGB[] frame, int batch)
        {
            if (frame == null || frame.Length != 104) throw new ArgumentException("A frame requires exactly 104 colors.");
            List<byte[]> packets = new List<byte[]>();
            for (int start = 0; start < 104; start += batch)
            {
                int count = Math.Min(batch, 104 - start); byte[] p = new byte[5 + count * 3];
                p[0] = 7; p[1] = 3; p[2] = 5; p[3] = (byte)start; p[4] = (byte)count;
                for (int i = 0; i < count; i++) { p[5 + i * 3] = frame[start + i].r; p[6 + i * 3] = frame[start + i].g; p[7 + i * 3] = frame[start + i].b; }
                packets.Add(p);
            }
            return packets;
        }
        internal static List<byte[]> ValidateAndSplit(byte[] payload, bool bluetooth)
        {
            if (payload == null || payload.Length < 4 || payload.Length > 32 || payload[1] != 3) throw new ArgumentException("Unsupported lighting command.");
            byte[] p = (byte[])payload.Clone(); bool valid = false;
            if (p[0] == 8) valid = p.Length == 4 && ((p[2] == 5 && p[3] < 104) || (p[2] == 6 && p[3] == 1));
            else if (p[0] == 7)
            {
                if (p[2] == 5 && p.Length >= 5)
                {
                    int start = p[3], count = p[4]; valid = start < 104 && count <= 9 && start + count <= 104 && p.Length == 5 + count * 3 && (count != 0 || start == 0);
                    if (valid && bluetooth && count > 5)
                    {
                        List<byte[]> result = new List<byte[]>();
                        for (int offset = 0; offset < count; offset += 5) { int n = Math.Min(5, count - offset); byte[] q = new byte[5 + n * 3]; q[0] = 7; q[1] = 3; q[2] = 5; q[3] = (byte)(start + offset); q[4] = (byte)n; Array.Copy(p, 5 + offset * 3, q, 5, n * 3); result.Add(q); }
                        return result;
                    }
                }
                else if (p[2] == 6 && p.Length == 6 && p[3] == 1) { int seconds = p[4] | p[5] << 8; valid = seconds == 0 || (seconds >= 60 && seconds <= 3600); }
                else valid = p.Length == 4 && ((p[2] == 1 && p[3] <= 4) || (p[2] == 2 && p[3] <= 18));
            }
            if (!valid) throw new ArgumentException("Invalid lighting command or RGB range.");
            return new List<byte[]> { p };
        }
        internal static byte[] NormalizeBluetooth(byte[] data)
        {
            if (data == null || data.Length != 20) throw new TransportUnavailableException("Invalid Bluetooth lighting response length.");
            byte[] result = new byte[32]; Array.Copy(data, result, data.Length); return result;
        }
    }

    public static class KeyboardConnections
    {
        public static IReportTransport Open(string preferred)
        {
            preferred = preferred ?? "Auto";
            bool automatic = preferred.Equals("Auto", StringComparison.OrdinalIgnoreCase);
            if (!automatic && preferred != "USB" && preferred != "2.4 GHz" && preferred != "Bluetooth") throw new ArgumentException("Unknown connection type.");
            if (automatic || preferred == "USB")
            {
                List<HidTransport.Candidate> wired = HidTransport.Candidates(0x5055);
                if (wired.Count > 0 || !automatic) return HidTransport.Open(wired, 0x5055);
            }
            if (automatic || preferred == "Bluetooth")
            {
                List<Native.Device> bluetooth = BluetoothTransport.Candidates();
                if (bluetooth.Count > 0 || !automatic) return BluetoothTransport.Open(bluetooth);
            }
            return HidTransport.Open(HidTransport.Candidates(0x5088), 0x5088);
        }
    }

    internal sealed class HidTransport : IReportTransport
    {
        internal sealed class Candidate { internal Native.Device Device; internal ushort Input, Output; }
        private readonly object sync = new object();
        private readonly SafeFileHandle handle;
        private readonly FileStream stream;
        private readonly Candidate candidate;
        private readonly ushort product;
        private bool closed;
        public string ConnectionName { get { return product == 0x5055 ? "USB" : "2.4 GHz"; } }
        public bool UsesRollingAnimationVerification { get { return false; } }
        public string DeviceIdentity { get { return candidate.Device.Path; } }
        internal static List<Candidate> Candidates(ushort product)
        {
            Guid guid; Native.HidD_GetHidGuid(out guid); List<Candidate> matches = new List<Candidate>();
            foreach (Native.Device d in Native.Interfaces(guid))
            {
                using (SafeFileHandle h = Native.Open(d.Path, false, false))
                {
                    if (h.IsInvalid) continue;
                    Native.HidAttributes a = new Native.HidAttributes(); a.Size = Marshal.SizeOf(a);
                    if (!Native.HidD_GetAttributes(h, ref a) || a.Vendor != 0x320F || a.Product != product) continue;
                    IntPtr data; if (!Native.HidD_GetPreparsedData(h, out data)) continue;
                    try { Native.HidCaps caps; if (Native.HidP_GetCaps(data, out caps) >= 0 && caps.UsagePage == 0xFF60 && caps.Usage == 0x61) matches.Add(new Candidate { Device = d, Input = caps.Input, Output = caps.Output }); }
                    finally { Native.HidD_FreePreparsedData(data); }
                }
            }
            return matches;
        }
        internal static HidTransport Open(List<Candidate> candidates, ushort product)
        {
            if (candidates.Count != 1) throw new TransportUnavailableException("Found " + candidates.Count + " matching " + (product == 0x5055 ? "USB" : "2.4 GHz") + " interfaces. Connect exactly one GMK104 and select the matching keyboard mode.");
            return new HidTransport(candidates[0], product);
        }
        private HidTransport(Candidate selected, ushort productID)
        {
            candidate = selected; product = productID;
            if (candidate.Input != 33 || candidate.Output != 33) throw new TransportUnavailableException("GMK104 must expose 33-byte Windows HID reports.");
            handle = Native.Open(selected.Device.Path, true, true);
            if (handle.IsInvalid) { handle.Dispose(); throw new TransportUnavailableException("Could not open GMK104. Close other lighting applications and reconnect.", new Win32Exception(Marshal.GetLastWin32Error())); }
            try { stream = new FileStream(handle, FileAccess.ReadWrite, 64, true); }
            catch { handle.Dispose(); throw; }
        }
        private void Available() { if (closed) throw new TransportUnavailableException("This keyboard connection is closed. Connect again."); }
        public void CheckSingleDevice()
        {
            lock (sync) { Available(); List<Candidate> current = Candidates(product); if (current.Count != 1 || !current[0].Device.Same(candidate.Device)) { Dispose(); throw new TransportUnavailableException("The keyboard attachment changed. Connect again."); } }
        }
        public byte[] Exchange(byte[] payload)
        {
            lock (sync)
            {
                Available(); byte[] packet = LightingPackets.ValidateAndSplit(payload, false)[0]; byte[] report = new byte[33], response = new byte[33]; Array.Copy(packet, 0, report, 1, packet.Length);
                Task<int> read = null; Task write = null; Stopwatch timer = Stopwatch.StartNew();
                try
                {
                    if (!Native.HidD_FlushQueue(handle)) throw new Win32Exception(Marshal.GetLastWin32Error());
                    read = stream.ReadAsync(response, 0, response.Length); write = stream.WriteAsync(report, 0, report.Length);
                    if (Task.WaitAny(new Task[] { write }, 2000) != 0) throw new TimeoutException(); write.GetAwaiter().GetResult();
                    if (Task.WaitAny(new Task[] { read }, Math.Max(0, 2000 - (int)timer.ElapsedMilliseconds)) != 0) throw new TimeoutException();
                    if (read.GetAwaiter().GetResult() != 33 || response[0] != 0) throw new IOException("Invalid HID response length or report ID.");
                    byte[] result = new byte[32]; Array.Copy(response, 1, result, 0, 32); return result;
                }
                catch (Exception ex) { Native.Observe(read); Native.Observe(write); Dispose(); throw new TransportUnavailableException(ConnectionName + " lighting communication failed. Wake the keyboard, check its connection mode, and connect again.", ex); }
            }
        }
        public void WriteFrame(RGB[] frame) { lock (sync) { foreach (byte[] p in LightingPackets.Frame(frame, 9)) Exchange(p); } }
        public void Dispose() { lock (sync) { if (closed) return; closed = true; try { Native.CancelIoEx(handle, IntPtr.Zero); } catch { } try { stream.Dispose(); } finally { handle.Dispose(); } } }
    }

    internal sealed class BluetoothTransport : IReportTransport
    {
        internal static readonly Guid DeviceGuid = new Guid("781aee18-7733-4ce4-add0-91f41c67b592");
        internal static readonly Guid ServiceInterface = new Guid("6e3bb679-4372-40c8-9eaa-4509df260cd8");
        internal static readonly Guid LightingService = new Guid("cc731d20-572d-4ceb-91a6-856f9f2dc104");
        internal static readonly Guid LightingCharacteristic = new Guid("cc731d21-572d-4ceb-91a6-856f9f2dc104");
        private static readonly Guid InformationService = new Guid("0000180a-0000-1000-8000-00805f9b34fb");
        private static readonly Guid PnpCharacteristic = new Guid("00002a50-0000-1000-8000-00805f9b34fb");
        private readonly object sync = new object();
        private readonly Native.Device candidate, rgbService;
        private readonly SafeFileHandle handle;
        private Native.GattCharacteristic characteristic;
        private volatile bool closed;
        public string ConnectionName { get { return "Bluetooth"; } }
        public bool UsesRollingAnimationVerification { get { return true; } }
        internal bool SupportsFastFrameWrites { get { return characteristic.WritableWithoutResponse != 0; } }
        public string DeviceIdentity { get { return candidate.Path; } }
        internal static List<Native.Device> Candidates() { return Native.Interfaces(DeviceGuid).Where(d => d.Name == "ZUOYA GMK104-1" || d.Name == "ZUOYA GMK104-2" || d.Name == "ZUOYA GMK104-3").ToList(); }
        internal static BluetoothTransport Open(List<Native.Device> candidates)
        {
            if (candidates.Count != 1) throw new TransportUnavailableException("Found " + candidates.Count + " paired GMK104 Bluetooth keyboards. Turn on Bluetooth and connect exactly one GMK104.");
            return new BluetoothTransport(candidates[0]);
        }
        private static Native.Device Service(List<Native.Device> services, Native.Device owner, Guid uuid)
        {
            List<Native.Device> matches = services.Where(d => d.InstanceId.IndexOf("{" + uuid.ToString() + "}", StringComparison.OrdinalIgnoreCase) >= 0 && Native.DescendsFrom(d.Node, owner.Node)).ToList();
            if (matches.Count != 1) throw new TransportUnavailableException("The GMK104 Bluetooth lighting service is unavailable or ambiguous. If updated firmware is installed, remove and pair this keyboard again in Windows Bluetooth settings to refresh its services.");
            return matches[0];
        }
        private BluetoothTransport(Native.Device selected)
        {
            candidate = selected; List<Native.Device> services = Native.Interfaces(ServiceInterface);
            rgbService = Service(services, candidate, LightingService); Native.Device info = Service(services, candidate, InformationService);
            handle = Native.Open(rgbService.Path, true, false);
            if (handle.IsInvalid) { handle.Dispose(); throw new TransportUnavailableException("Windows could not open the GMK104 Bluetooth lighting service.", new Win32Exception(Marshal.GetLastWin32Error())); }
            try
            {
                characteristic = Timed(() => Native.Characteristics(handle).Single(c => c.Uuid.Guid == LightingCharacteristic));
                if (characteristic.Readable == 0 || characteristic.Writable == 0) throw new TransportUnavailableException("The GMK104 Bluetooth lighting characteristic is incompatible.");
                // The information handle belongs to the same PnP ancestry as the RGB service.
                // Its lifetime is inside the worker so timeout never frees an active native call's buffer.
                byte[] pnp = Timed(() =>
                {
                    using (SafeFileHandle h = Native.Open(info.Path, true, false))
                    {
                        if (h.IsInvalid) throw new TransportUnavailableException("Windows could not read the GMK104 Bluetooth identity.");
                        Native.GattCharacteristic p = Native.Characteristics(h).Single(c => c.Uuid.Guid == PnpCharacteristic);
                        if (p.Readable == 0) throw new TransportUnavailableException("The GMK104 PnP identity is not readable.");
                        if (closed) throw new ObjectDisposedException("BluetoothTransport");
                        return Native.ReadValue(h, p);
                    }
                });
                if (!pnp.SequenceEqual(new byte[] { 2, 0x5A, 0x24, 0x76, 0x82, 1, 0 })) throw new TransportUnavailableException("Bluetooth hardware identity does not match the GMK104 firmware.");
            }
            catch { Dispose(); throw; }
        }
        private void Available() { if (closed || handle.IsInvalid || handle.IsClosed) throw new TransportUnavailableException("Bluetooth keyboard is offline. Wake it and connect again."); }
        private T Timed<T>(Func<T> action)
        {
            Available(); Task<T> task = Task.Factory.StartNew(() => { Available(); return action(); }, CancellationToken.None, TaskCreationOptions.DenyChildAttach, TaskScheduler.Default);
            try
            {
                if (Task.WaitAny(new Task[] { task }, 3000) != 0) throw new TimeoutException("Bluetooth lighting timed out. Wake the keyboard and keep it in Bluetooth mode.");
                return task.GetAwaiter().GetResult();
            }
            catch (Exception ex) { Native.Observe(task); Dispose(); throw new TransportUnavailableException("Bluetooth lighting communication failed. Wake the keyboard and connect again. " + ex.Message, ex); }
        }
        public void CheckSingleDevice()
        {
            lock (sync)
            {
                Available(); List<Native.Device> current = Candidates();
                if (current.Count != 1 || !current[0].Same(candidate)) { Dispose(); throw new TransportUnavailableException("The Bluetooth keyboard attachment changed. Connect again."); }
            }
        }
        public byte[] Exchange(byte[] payload)
        {
            lock (sync)
            {
                Available(); List<byte[]> packets = LightingPackets.ValidateAndSplit(payload, true);
                foreach (byte[] packet in packets) Timed(() => { Native.WriteValue(handle, characteristic, packet, false); return 0; });
                if (payload[0] == 8) return LightingPackets.NormalizeBluetooth(Timed(() => Native.ReadValue(handle, characteristic)));
                byte[] result = new byte[32]; Array.Copy(payload, result, payload.Length); return result;
            }
        }
        public void WriteFrame(RGB[] frame)
        {
            lock (sync)
            {
                Available(); List<byte[]> packets = LightingPackets.Frame(frame, 5);
                // Only use commands when the device advertises them. Windows provides no
                // CoreBluetooth-style capacity callback, so pace the 21 packets at 8 ms.
                // Success still requires RGBClient's acknowledged checksum/color readback.
                bool fast = characteristic.WritableWithoutResponse != 0;
                foreach (byte[] packet in packets) { Timed(() => { Native.WriteValue(handle, characteristic, packet, fast); return 0; }); if (fast) Thread.Sleep(8); }
            }
        }
        public void Dispose() { lock (sync) { if (closed) return; closed = true; try { Native.CancelIoEx(handle, IntPtr.Zero); } catch { } handle.Dispose(); } }
    }

    // Layouts and flags follow Microsoft's bthledef.h and BluetoothGATT API contracts.
    // GATT values are forced from the device, never satisfied by the Windows cache.
    internal static class Native
    {
        internal sealed class Device
        {
            internal string Path, Name, InstanceId; internal uint Node;
            internal bool Same(Device d) { return d != null && Node == d.Node && String.Equals(Path, d.Path, StringComparison.OrdinalIgnoreCase) && String.Equals(InstanceId, d.InstanceId, StringComparison.OrdinalIgnoreCase); }
        }
        internal static void Observe(Task task) { if (task != null) task.ContinueWith(t => { var ignored = t.Exception; }, TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously); }
        internal static SafeFileHandle Open(string path, bool readWrite, bool overlapped) { return CreateFile(path, readWrite ? 0xC0000000u : 0, 3, IntPtr.Zero, 3, overlapped ? 0x40000000u : 0, IntPtr.Zero); }
        internal static bool DescendsFrom(uint node, uint ancestor) { for (int i = 0; i < 16; i++) { if (node == ancestor) return true; uint parent; if (CM_Get_Parent(out parent, node, 0) != 0 || parent == node) return false; node = parent; } return false; }
        internal static List<Device> Interfaces(Guid guid)
        {
            IntPtr set = SetupDiGetClassDevs(ref guid, null, IntPtr.Zero, 0x12); if (set == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
            List<Device> results = new List<Device>();
            try
            {
                for (uint i = 0; ; i++)
                {
                    InterfaceData face = new InterfaceData(); face.Size = Marshal.SizeOf(face);
                    if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, i, ref face)) { int error = Marshal.GetLastWin32Error(); if (error == 259) break; throw new Win32Exception(error); }
                    int size; InfoData info = new InfoData(); info.Size = Marshal.SizeOf(info); SetupDiGetDeviceInterfaceDetail(set, ref face, IntPtr.Zero, 0, out size, ref info);
                    if (size < 8 || size > 65536) throw new IOException("Windows returned an invalid interface path size.");
                    IntPtr detail = Marshal.AllocHGlobal(size);
                    try
                    {
                        Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                        if (!SetupDiGetDeviceInterfaceDetail(set, ref face, detail, size, out size, ref info)) throw new Win32Exception(Marshal.GetLastWin32Error());
                        string path = Marshal.PtrToStringUni(IntPtr.Add(detail, 4)); if (String.IsNullOrEmpty(path)) throw new IOException("Windows returned an empty interface path.");
                        StringBuilder id = new StringBuilder(4096); int required;
                        if (!SetupDiGetDeviceInstanceId(set, ref info, id, id.Capacity, out required)) throw new Win32Exception(Marshal.GetLastWin32Error());
                        results.Add(new Device { Path = path, Name = Property(set, ref info, 12) ?? Property(set, ref info, 0) ?? "", InstanceId = id.ToString(), Node = info.Node });
                    }
                    finally { Marshal.FreeHGlobal(detail); }
                }
            }
            finally { SetupDiDestroyDeviceInfoList(set); }
            return results;
        }
        private static string Property(IntPtr set, ref InfoData info, uint property)
        {
            byte[] buffer = new byte[8192]; uint type, required;
            return SetupDiGetDeviceRegistryProperty(set, ref info, property, out type, buffer, (uint)buffer.Length, out required) && required >= 2 ? Encoding.Unicode.GetString(buffer, 0, Math.Min(buffer.Length, (int)required)).TrimEnd('\0') : null;
        }
        [StructLayout(LayoutKind.Explicit, Size = 20)]
        internal struct GattUuid { [FieldOffset(0)] internal byte Short; [FieldOffset(4)] internal ushort ShortValue; [FieldOffset(4)] internal Guid Long; internal Guid Guid { get { return Short != 0 ? new Guid(ShortValue.ToString("x8") + "-0000-1000-8000-00805f9b34fb") : Long; } } }
        [StructLayout(LayoutKind.Sequential)]
        internal struct GattCharacteristic
        {
            internal ushort ServiceHandle; internal GattUuid Uuid; internal ushort AttributeHandle, ValueHandle;
            internal byte Broadcastable, Readable, Writable, WritableWithoutResponse, SignedWritable, Notifiable, Indicatable, Extended;
        }
        internal static List<GattCharacteristic> Characteristics(SafeFileHandle handle)
        {
            ushort count; int hr = BluetoothGATTGetCharacteristics(handle, IntPtr.Zero, 0, IntPtr.Zero, out count, 0);
            if (hr != unchecked((int)0x800700EA) && hr != 0) Hr(hr, "discover Bluetooth characteristics");
            if (count == 0 || count > 512) throw new IOException("No valid Bluetooth characteristics found.");
            int size = Marshal.SizeOf(typeof(GattCharacteristic)); IntPtr buffer = Marshal.AllocHGlobal(size * count);
            try
            {
                ushort actual; Hr(BluetoothGATTGetCharacteristics(handle, IntPtr.Zero, count, buffer, out actual, 0), "read Bluetooth characteristics");
                if (actual > count) throw new IOException("Invalid Bluetooth characteristic count.");
                List<GattCharacteristic> result = new List<GattCharacteristic>(); for (int i = 0; i < actual; i++) result.Add((GattCharacteristic)Marshal.PtrToStructure(IntPtr.Add(buffer, size * i), typeof(GattCharacteristic))); return result;
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        internal static byte[] ReadValue(SafeFileHandle handle, GattCharacteristic characteristic)
        {
            const int capacity = 516; IntPtr value = Marshal.AllocHGlobal(capacity);
            try
            {
                ushort required; Hr(BluetoothGATTGetCharacteristicValue(handle, ref characteristic, capacity, value, out required, 4), "read Bluetooth value");
                int count = Marshal.ReadInt32(value); if (count < 0 || count > 512 || (required != 0 && required > capacity)) throw new IOException("Invalid Bluetooth value length.");
                byte[] result = new byte[count]; Marshal.Copy(IntPtr.Add(value, 4), result, 0, count); return result;
            }
            finally { Marshal.FreeHGlobal(value); }
        }
        internal static void WriteValue(SafeFileHandle handle, GattCharacteristic characteristic, byte[] data, bool withoutResponse)
        {
            if (data.Length > 20) throw new ArgumentException("Bluetooth lighting packets must be at most 20 bytes.");
            IntPtr value = Marshal.AllocHGlobal(4 + data.Length);
            try { Marshal.WriteInt32(value, data.Length); Marshal.Copy(data, 0, IntPtr.Add(value, 4), data.Length); Hr(BluetoothGATTSetCharacteristicValue(handle, ref characteristic, value, 0, withoutResponse ? 0x20u : 0u), "write Bluetooth lighting command"); }
            finally { Marshal.FreeHGlobal(value); }
        }
        private static void Hr(int hr, string action) { if (hr < 0) throw new IOException("Windows could not " + action + " (0x" + hr.ToString("X8") + ").", Marshal.GetExceptionForHR(hr)); }
        [StructLayout(LayoutKind.Sequential)] private struct InterfaceData { internal int Size; internal Guid Class; internal int Flags; internal IntPtr Reserved; }
        [StructLayout(LayoutKind.Sequential)] private struct InfoData { internal int Size; internal Guid Class; internal uint Node; internal IntPtr Reserved; }
        [StructLayout(LayoutKind.Sequential)] internal struct HidAttributes { internal int Size; internal ushort Vendor, Product, Version; }
        [StructLayout(LayoutKind.Sequential)] internal struct HidCaps
        {
            internal ushort Usage, UsagePage, Input, Output, Feature;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] internal ushort[] Reserved;
            internal ushort Links, InputButtons, InputValues, InputIndices, OutputButtons, OutputValues, OutputIndices, FeatureButtons, FeatureValues, FeatureIndices;
        }
        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern IntPtr SetupDiGetClassDevs(ref Guid guid, string enumerator, IntPtr window, uint flags);
        [DllImport("setupapi.dll", SetLastError = true)] private static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr info, ref Guid guid, uint index, ref InterfaceData data);
        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr set, ref InterfaceData data, IntPtr detail, int size, out int required, ref InfoData info);
        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool SetupDiGetDeviceInstanceId(IntPtr set, ref InfoData info, StringBuilder id, int size, out int required);
        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool SetupDiGetDeviceRegistryProperty(IntPtr set, ref InfoData info, uint property, out uint type, [Out] byte[] buffer, uint size, out uint required);
        [DllImport("setupapi.dll")] private static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
        [DllImport("cfgmgr32.dll")] private static extern uint CM_Get_Parent(out uint parent, uint node, uint flags);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)] internal static extern bool CancelIoEx(SafeFileHandle handle, IntPtr overlapped);
        [DllImport("hid.dll")] internal static extern void HidD_GetHidGuid(out Guid guid);
        [DllImport("hid.dll", SetLastError = true)] internal static extern bool HidD_GetAttributes(SafeFileHandle handle, ref HidAttributes attributes);
        [DllImport("hid.dll", SetLastError = true)] internal static extern bool HidD_GetPreparsedData(SafeFileHandle handle, out IntPtr data);
        [DllImport("hid.dll")] internal static extern bool HidD_FreePreparsedData(IntPtr data);
        [DllImport("hid.dll")] internal static extern int HidP_GetCaps(IntPtr data, out HidCaps caps);
        [DllImport("hid.dll", SetLastError = true)] internal static extern bool HidD_FlushQueue(SafeFileHandle handle);
        [DllImport("BluetoothApis.dll")] private static extern int BluetoothGATTGetCharacteristics(SafeFileHandle handle, IntPtr service, ushort count, IntPtr buffer, out ushort actual, uint flags);
        [DllImport("BluetoothApis.dll")] private static extern int BluetoothGATTGetCharacteristicValue(SafeFileHandle handle, ref GattCharacteristic characteristic, uint capacity, IntPtr value, out ushort required, uint flags);
        [DllImport("BluetoothApis.dll")] private static extern int BluetoothGATTSetCharacteristicValue(SafeFileHandle handle, ref GattCharacteristic characteristic, IntPtr value, ulong context, uint flags);
    }
}
