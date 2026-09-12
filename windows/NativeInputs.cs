using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace Gmk104LightingStudio
{
    /// <summary>Physical key transitions from the selected GMK104 attachment only.</summary>
    public sealed class KeyboardInput : IDisposable
    {
        private readonly IntPtr window;
        private readonly Dictionary<IntPtr, HashSet<string>> devices = new Dictionary<IntPtr, HashSet<string>>();
        private bool registered;
        public event Action<string> KeyPressed;
        public string Status { get; private set; }
        public bool IsRunning { get { return registered; } }

        public KeyboardInput(IntPtr hwnd) { window = hwnd; Status = "Key reactions are stopped"; }

        public bool Start(string connectionName, string deviceIdentity)
        {
            Stop();
            if (window == IntPtr.Zero || String.IsNullOrWhiteSpace(deviceIdentity))
            {
                Status = "Connect the GMK104 before enabling key reactions"; return false;
            }
            try
            {
                Attachment selected = Attachment.Read(deviceIdentity);
                uint count = 0;
                uint itemSize = (uint)Marshal.SizeOf(typeof(RawDeviceList));
                if (GetRawInputDeviceList(null, ref count, itemSize) == UInt32.MaxValue || count > 256)
                    throw new InvalidOperationException("Keyboard interfaces could not be enumerated");
                RawDeviceList[] all = new RawDeviceList[count];
                uint found = GetRawInputDeviceList(all, ref count, itemSize);
                if (found == UInt32.MaxValue) throw new InvalidOperationException("Keyboard interfaces changed; reconnect and retry");
                for (int i = 0; i < Math.Min(found, all.Length); i++)
                {
                    if (all[i].type != 1) continue;
                    string name = DeviceName(all[i].device);
                    Attachment candidate = Attachment.Read(name);
                    if (candidate.IsGmk104 && candidate.Matches(selected))
                        devices[all[i].device] = new HashSet<string>(StringComparer.Ordinal);
                }
                if (devices.Count == 0)
                {
                    Status = "No keyboard input interface matches this GMK104 connection; reconnect and retry";
                    return false;
                }
                // Windows registers by usage, so reject other devices by HEADER before reading key data.
                // INPUTSINK preserves ordinary keyboard handling; there is no NOLEGACY or global hook.
                RawRegistration[] registration = { new RawRegistration { page = 1, usage = 6, flags = 0x2100, target = window } };
                if (!RegisterRawInputDevices(registration, 1, (uint)Marshal.SizeOf(typeof(RawRegistration))))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                registered = true;
                Status = "Key reactions follow this GMK104 only (" + (connectionName ?? "connected") + ")";
                return true;
            }
            catch (Exception ex) { Stop(); Status = "Key reactions unavailable: " + ex.Message; return false; }
        }

        public void ProcessMessage(ref Message message)
        {
            if (!registered) return;
            if (message.Msg == 0x00FE && message.WParam.ToInt64() == 2)
            {
                devices.Remove(message.LParam);
                if (devices.Count == 0) { Stop(); Status = "GMK104 input disconnected; reconnect to resume key reactions"; }
                return;
            }
            if (message.Msg != 0x00FF) return;
            uint headerSize = (uint)Marshal.SizeOf(typeof(RawHeader));
            uint length = headerSize;
            // RAWINPUT union padding differs by architecture; accept the reported keyboard size.
            IntPtr buffer = Marshal.AllocHGlobal(64);
            try
            {
                if (GetRawInputData(message.LParam, 0x10000005, buffer, ref length, headerSize) != headerSize) return;
                RawHeader header = (RawHeader)Marshal.PtrToStructure(buffer, typeof(RawHeader));
                HashSet<string> held;
                if (header.type != 1 || !devices.TryGetValue(header.device, out held)) return;
                if (header.size < headerSize + 16 || header.size > 64) return;
                length = 64;
                uint copied = GetRawInputData(message.LParam, 0x10000003, buffer, ref length, headerSize);
                if (copied == UInt32.MaxValue || copied < headerSize + 16 || copied > 64) return;
                int offset = (int)headerSize;
                ushort scan = unchecked((ushort)Marshal.ReadInt16(buffer, offset));
                ushort flags = unchecked((ushort)Marshal.ReadInt16(buffer, offset + 2));
                ushort vkey = unchecked((ushort)Marshal.ReadInt16(buffer, offset + 6));
                string key = KeyForScanCode(scan, flags, vkey);
                if (key == null) return;
                bool down = (flags & 1) == 0;
                if (!down) { held.Remove(key); return; }
                bool wasDown = false;
                foreach (HashSet<string> other in devices.Values) if (other.Contains(key)) { wasDown = true; break; }
                // Pause has no reliable break packet. It is not typematic and can pulse on each make.
                if (key != "Pause") held.Add(key);
                if (!wasDown)
                {
                    Action<string> handler = KeyPressed;
                    if (handler != null) handler(key);
                }
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }

        public void Stop()
        {
            if (registered)
            {
                RawRegistration[] registration = { new RawRegistration { page = 1, usage = 6, flags = 1, target = IntPtr.Zero } };
                RegisterRawInputDevices(registration, 1, (uint)Marshal.SizeOf(typeof(RawRegistration)));
            }
            registered = false; devices.Clear(); Status = "Key reactions are stopped";
        }
        public void Dispose() { Stop(); KeyPressed = null; }

        // Set-1 physical positions; extended flags distinguish keypad/navigation and modifier sides.
        public static string KeyForScanCode(ushort scan, ushort flags, ushort virtualKey)
        {
            if (scan == 0xFF || virtualKey >= 0xFF) return null;
            bool e0 = (flags & 2) != 0, e1 = (flags & 4) != 0;
            if (virtualKey == 0x13 || (e1 && scan == 0x45) || (e0 && scan == 0x46 && virtualKey == 0x03)) return "Pause";
            // Alt+PrintScreen can use the legacy SysRq scan code instead of E0 37.
            if (virtualKey == 0x2C && (scan == 0x54 || (e0 && scan == 0x37))) return "PrintScreen";
            if (e1) return null;
            if (virtualKey == 0x90 || scan == 0x45) return "NumLock";
            if (e0)
            {
                switch (scan)
                {
                    case 0x1C: return "NumpadEnter"; case 0x1D: return "ControlRight";
                    case 0x35: return "NumpadDivide"; case 0x37: return "PrintScreen";
                    case 0x38: return "AltRight"; case 0x47: return "Home";
                    case 0x48: return "ArrowUp"; case 0x49: return "PageUp";
                    case 0x4B: return "ArrowLeft"; case 0x4D: return "ArrowRight";
                    case 0x4F: return "End"; case 0x50: return "ArrowDown";
                    case 0x51: return "PageDown"; case 0x52: return "Insert";
                    case 0x53: return "Delete"; case 0x5B: return "MetaLeft";
                    case 0x5C: return "MetaRight"; case 0x5D: return "ContextMenu";
                    default: return null;
                }
            }
            if (scan >= 0x02 && scan <= 0x0A) return "Digit" + (scan - 1).ToString(CultureInfo.InvariantCulture);
            if (scan >= 0x3B && scan <= 0x44) return "F" + (scan - 0x3A).ToString(CultureInfo.InvariantCulture);
            const string upper = "QWERTYUIOP", middle = "ASDFGHJKL", lower = "ZXCVBNM";
            if (scan >= 0x10 && scan <= 0x19) return "Key" + upper[scan - 0x10];
            if (scan >= 0x1E && scan <= 0x26) return "Key" + middle[scan - 0x1E];
            if (scan >= 0x2C && scan <= 0x32) return "Key" + lower[scan - 0x2C];
            switch (scan)
            {
                case 0x01: return "Escape"; case 0x0B: return "Digit0"; case 0x0C: return "Minus";
                case 0x0D: return "Equal"; case 0x0E: return "Backspace"; case 0x0F: return "Tab";
                case 0x1A: return "BracketLeft"; case 0x1B: return "BracketRight"; case 0x1C: return "Enter";
                case 0x1D: return "ControlLeft"; case 0x27: return "Semicolon"; case 0x28: return "Quote";
                case 0x29: return "Backquote"; case 0x2A: return "ShiftLeft"; case 0x2B: return "Backslash";
                case 0x33: return "Comma"; case 0x34: return "Period"; case 0x35: return "Slash";
                case 0x36: return "ShiftRight"; case 0x37: return "NumpadMultiply"; case 0x38: return "AltLeft";
                case 0x39: return "Space"; case 0x3A: return "CapsLock"; case 0x46: return "ScrollLock";
                case 0x47: return "Numpad7"; case 0x48: return "Numpad8"; case 0x49: return "Numpad9";
                case 0x4A: return "NumpadSubtract"; case 0x4B: return "Numpad4"; case 0x4C: return "Numpad5";
                case 0x4D: return "Numpad6"; case 0x4E: return "NumpadAdd"; case 0x4F: return "Numpad1";
                case 0x50: return "Numpad2"; case 0x51: return "Numpad3"; case 0x52: return "Numpad0";
                case 0x53: return "NumpadDecimal"; case 0x57: return "F11"; case 0x58: return "F12";
                default: return null;
            }
        }

        private static string DeviceName(IntPtr device)
        {
            uint size = 0;
            if (GetRawInputDeviceInfo(device, 0x20000007, null, ref size) == UInt32.MaxValue || size == 0 || size > 32768) return "";
            StringBuilder name = new StringBuilder((int)size + 1);
            return GetRawInputDeviceInfo(device, 0x20000007, name, ref size) == UInt32.MaxValue ? "" : name.ToString();
        }

        private sealed class Attachment
        {
            internal string path = "", address = "", usbAncestor = "";
            internal Guid container;
            internal bool IsGmk104;
            internal static Attachment Read(string devicePath)
            {
                Attachment result = new Attachment();
                result.path = (devicePath ?? "").ToUpperInvariant();
                string instance = result.path;
                if (instance.StartsWith(@"\\?\") || instance.StartsWith(@"\??\")) instance = instance.Substring(4);
                // Bluetooth HID instance IDs themselves begin with a service GUID.
                // Only the final #{interface-guid} component is the interface suffix.
                int suffix = instance.LastIndexOf("#{", StringComparison.Ordinal);
                if (suffix >= 0) instance = instance.Substring(0, suffix);
                instance = instance.Replace('#', '\\');
                List<string> ancestry = new List<string>(); ancestry.Add(result.path); ancestry.Add(instance);
                uint node;
                if (CM_Locate_DevNode(out node, instance, 0) == 0)
                {
                    for (int depth = 0; depth < 32; depth++)
                    {
                        StringBuilder id = new StringBuilder(4096);
                        if (CM_Get_Device_ID(node, id, id.Capacity, 0) == 0)
                        {
                            string value = id.ToString().ToUpperInvariant(); ancestry.Add(value);
                            if (value.StartsWith("USB\\VID_320F&") && value.IndexOf("&MI_", StringComparison.Ordinal) < 0 && result.usbAncestor.Length == 0)
                                result.usbAncestor = value;
                        }
                        if (result.container == Guid.Empty)
                        {
                            DeviceProperty key = new DeviceProperty(new Guid("8C7ED206-3F8A-4827-B3AB-AE9E1FAEFC6C"), 2);
                            byte[] bytes = new byte[16]; uint bytesLength = 16, type;
                            if (CM_Get_DevNode_Property(node, ref key, out type, bytes, ref bytesLength, 0) == 0 && type == 13 && bytesLength == 16)
                                result.container = new Guid(bytes);
                        }
                        uint parent;
                        if (CM_Get_Parent(out parent, node, 0) != 0) break;
                        node = parent;
                    }
                }
                string joined = String.Join("|", ancestry.ToArray());
                result.IsGmk104 = Regex.IsMatch(joined, @"VID[_&](?:02)?320F.*?PID[_&](?:5055|5088)") ||
                    Regex.IsMatch(joined, @"VID[_&](?:02)?245A.*?PID[_&]8276");
                Match addr = Regex.Match(joined, @"DEV_([0-9A-F]{12})(?:[^0-9A-F]|$)");
                if (addr.Success) result.address = addr.Groups[1].Value;
                return result;
            }
            internal bool Matches(Attachment selected)
            {
                // A Bluetooth address on the enumerated parent is stronger than a shared HID container.
                if (selected.address.Length != 0) return address.Length != 0 && address == selected.address;
                if (selected.usbAncestor.Length != 0 && usbAncestor.Length != 0) return usbAncestor == selected.usbAncestor;
                if (selected.container != Guid.Empty && container != Guid.Empty) return selected.container == container;
                return path.Length != 0 && path == selected.path;
            }
        }

        [StructLayout(LayoutKind.Sequential)] private struct RawDeviceList { internal IntPtr device; internal uint type; }
        [StructLayout(LayoutKind.Sequential)] private struct RawRegistration { internal ushort page, usage; internal uint flags; internal IntPtr target; }
        [StructLayout(LayoutKind.Sequential)] private struct RawHeader { internal uint type, size; internal IntPtr device, parameter; }
        [StructLayout(LayoutKind.Sequential)] private struct DeviceProperty
        { internal Guid format; internal uint id; internal DeviceProperty(Guid guid, uint pid) { format = guid; id = pid; } }
        [DllImport("user32.dll", SetLastError = true)] private static extern uint GetRawInputDeviceList([In, Out] RawDeviceList[] list, ref uint count, uint size);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern uint GetRawInputDeviceInfo(IntPtr device, uint command, StringBuilder data, ref uint size);
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool RegisterRawInputDevices(RawRegistration[] devices, uint count, uint size);
        [DllImport("user32.dll", SetLastError = true)] private static extern uint GetRawInputData(IntPtr input, uint command, IntPtr data, ref uint size, uint headerSize);
        [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)] private static extern uint CM_Locate_DevNode(out uint node, string instance, uint flags);
        [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)] private static extern uint CM_Get_Device_ID(uint node, StringBuilder value, int length, uint flags);
        [DllImport("cfgmgr32.dll")] private static extern uint CM_Get_Parent(out uint parent, uint node, uint flags);
        [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)] private static extern uint CM_Get_DevNode_Property(uint node, ref DeviceProperty key, out uint type, [Out] byte[] value, ref uint length, uint flags);
    }

    /// <summary>One shared system-output analyzer and optional read-only CPU temperature provider.</summary>
    public sealed class NativeLightingInputs : IDisposable
    {
        private readonly object sync = new object();
        private AudioSession audio;
        private MusicSample sample = new MusicSample();
        private bool audioRunning, disposed, temperatureBusy;
        private double? temperature;
        private double temperatureTime = Double.NegativeInfinity, lastTemperatureRequest = Double.NegativeInfinity;
        private string audioStatus = "Windows audio is stopped";
        private string temperatureStatus = "CPU temperature requires a running LibreHardwareMonitor or OpenHardwareMonitor WMI provider";

        public static double MonotonicTime { get { return (double)Stopwatch.GetTimestamp() / Stopwatch.Frequency; } }
        public string AudioStatus { get { lock (sync) return audioStatus; } }
        public string TemperatureStatus { get { lock (sync) return temperatureStatus; } }

        public void StartAudio()
        {
            AudioSession session;
            lock (sync)
            {
                if (disposed) return;
                if (audio != null && !audio.Completed) return;
                sample = new MusicSample(); audioRunning = false;
                audioStatus = "Starting Windows playback audio";
                session = new AudioSession(this); audio = session;
            }
            session.Start();
        }

        public void StopAudio()
        {
            AudioSession old;
            lock (sync)
            {
                old = audio; audio = null; audioRunning = false; sample = new MusicSample();
                audioStatus = "Windows audio is stopped";
            }
            if (old != null) old.Stop();
        }

        public void RefreshTemperature()
        {
            lock (sync)
            {
                double now = MonotonicTime;
                if (disposed || temperatureBusy || now - lastTemperatureRequest < 1) return;
                lastTemperatureRequest = now; temperatureBusy = true;
            }
            ThreadPool.QueueUserWorkItem(delegate
            {
                double? hottest = null; int count = 0; string provider = "";
                try
                {
                    foreach (string name in new[] { "LibreHardwareMonitor", "OpenHardwareMonitor" })
                    {
                        try
                        {
                            List<double> values = ReadCpuTemperatures(name);
                            if (values.Count == 0) continue;
                            count = values.Count; provider = name;
                            foreach (double value in values) if (!hottest.HasValue || value > hottest.Value) hottest = value;
                            break;
                        }
                        catch (ManagementException) { }
                        catch (UnauthorizedAccessException) { }
                        catch (COMException) { }
                        catch (TimeoutException) { }
                    }
                }
                catch (Exception) { hottest = null; }
                finally
                {
                    lock (sync)
                    {
                        temperatureBusy = false;
                        if (!disposed)
                        {
                            temperature = hottest; temperatureTime = MonotonicTime;
                            temperatureStatus = hottest.HasValue ? String.Format(CultureInfo.InvariantCulture,
                                "CPU {0:F1} °C · hottest of {1} sensors ({2})", hottest.Value, count, provider) :
                                "CPU temperature unavailable · run LibreHardwareMonitor or OpenHardwareMonitor with WMI enabled";
                        }
                    }
                }
            });
        }

        public LightingInputs Snapshot(double monotonicTime)
        {
            lock (sync)
            {
                double now = MonotonicTime;
                MusicSample copy = new MusicSample {
                    bass = sample.bass, mid = sample.mid, treble = sample.treble, level = sample.level,
                    timestamp = monotonicTime - (now - sample.timestamp)
                };
                string status = audioStatus;
                if (audioRunning && now - sample.timestamp >= 1) status = "Listening to playback · play audio on your PC";
                return new LightingInputs {
                    music = copy.Fresh(monotonicTime), musicStatus = status, audioRunning = audioRunning,
                    cpuCelsius = temperature, temperatureTime = monotonicTime - (now - temperatureTime), temperatureStatus = temperatureStatus
                };
            }
        }

        public void Dispose()
        {
            lock (sync) { if (disposed) return; disposed = true; temperature = null; }
            StopAudio();
        }

        private void PublishAudio(AudioSession source, MusicSample levels, bool running, string status)
        {
            lock (sync)
            {
                if (disposed || audio != source) return;
                if (levels != null) sample = levels;
                audioRunning = running; audioStatus = status;
            }
        }

        private static List<double> ReadCpuTemperatures(string provider)
        {
            // WMI exposes real sensor values from these existing providers. No driver is installed,
            // and CPU load / ACPI thermal zones are deliberately not substituted for CPU sensors.
            ManagementScope scope = new ManagementScope(@"\\.\root\" + provider,
                new ConnectionOptions { Timeout = TimeSpan.FromSeconds(2), EnablePrivileges = false });
            scope.Connect();
            EnumerationOptions options = new EnumerationOptions { Timeout = TimeSpan.FromSeconds(2), ReturnImmediately = false };
            HashSet<string> cpuIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            using (ManagementObjectSearcher search = new ManagementObjectSearcher(scope, new ObjectQuery("SELECT Identifier, HardwareType FROM Hardware"), options))
            using (ManagementObjectCollection found = search.Get())
                foreach (ManagementObject item in found)
                    using (item)
                        if (String.Equals(Convert.ToString(item["HardwareType"], CultureInfo.InvariantCulture), "Cpu", StringComparison.OrdinalIgnoreCase))
                            cpuIds.Add(Convert.ToString(item["Identifier"], CultureInfo.InvariantCulture));
            List<double> result = new List<double>();
            using (ManagementObjectSearcher search = new ManagementObjectSearcher(scope, new ObjectQuery("SELECT Parent, Value FROM Sensor WHERE SensorType='Temperature'"), options))
            using (ManagementObjectCollection found = search.Get())
                foreach (ManagementObject item in found)
                    using (item)
                    {
                        string parent = Convert.ToString(item["Parent"], CultureInfo.InvariantCulture);
                        if (!cpuIds.Contains(parent) || item["Value"] == null) continue;
                        double value;
                        if (Double.TryParse(Convert.ToString(item["Value"], CultureInfo.InvariantCulture), NumberStyles.Float, CultureInfo.InvariantCulture, out value)
                            && !Double.IsNaN(value) && !Double.IsInfinity(value) && value >= 1 && value <= 125) result.Add(value);
                    }
            return result;
        }

        /// <summary>Mac-equivalent complementary bands, adaptive reference, attack/release envelopes.</summary>
        public sealed class AudioAnalyzer
        {
            private double low, middleLow, reference = 0.02, previousRate;
            private readonly double[] envelopes = new double[4];
            public MusicSample Process(float[] samples, double sampleRate, double time)
            {
                if (samples == null || samples.Length == 0 || samples.Length > 65536 || Double.IsNaN(sampleRate) ||
                    sampleRate < 8000 || sampleRate > 384000 || Double.IsNaN(time) || Double.IsInfinity(time)) return new MusicSample();
                if (sampleRate != previousRate) { low = middleLow = 0; previousRate = sampleRate; }
                double a = 1 - Math.Exp(-2 * Math.PI * 220 / sampleRate), b = 1 - Math.Exp(-2 * Math.PI * 2200 / sampleRate);
                double[] power = new double[4];
                foreach (float sample in samples)
                {
                    double value = Single.IsNaN(sample) || Single.IsInfinity(sample) ? 0 : Math.Min(1, Math.Max(-1, sample));
                    low += a * (value - low); middleLow += b * (value - middleLow);
                    power[0] += low * low;
                    double mid = middleLow - low, high = value - middleLow;
                    power[1] += mid * mid; power[2] += high * high; power[3] += value * value;
                }
                double dt = samples.Length / sampleRate, rms = Math.Sqrt(power[3] / samples.Length);
                reference = Math.Max(0.01, Math.Max(rms, reference * Math.Exp(-dt / 3)));
                for (int i = 0; i < 4; i++)
                {
                    rms = Math.Sqrt(power[i] / samples.Length);
                    double target = rms < 0.0002 ? 0 : Math.Min(1, Math.Sqrt(rms / reference));
                    double tau = target > envelopes[i] ? 0.025 : 0.16;
                    envelopes[i] += (target - envelopes[i]) * (1 - Math.Exp(-dt / tau));
                    if (envelopes[i] < 0.002) envelopes[i] = 0;
                }
                return new MusicSample { bass = envelopes[0], mid = envelopes[1], treble = envelopes[2], level = envelopes[3], timestamp = time };
            }
        }

        private sealed class AudioSession
        {
            private readonly NativeLightingInputs owner;
            private readonly ManualResetEvent stop = new ManualResetEvent(false);
            private readonly object lifecycle = new object();
            private bool finished;
            internal bool Completed { get { lock (lifecycle) return finished; } }
            internal AudioSession(NativeLightingInputs parent) { owner = parent; }
            internal void Start()
            {
                Thread worker = new Thread(Run) { IsBackground = true, Name = "GMK104 playback levels" };
                worker.SetApartmentState(ApartmentState.STA); worker.Start();
            }
            internal void Stop() { lock (lifecycle) { if (!finished) stop.Set(); } }

            private void Run()
            {
                IMMDeviceEnumerator enumerator = null; IMMDevice endpoint = null;
                IAudioClient client = null; IAudioCaptureClient capture = null;
                IntPtr formatPointer = IntPtr.Zero;
                bool started = false, com = false;
                try
                {
                    Check(CoInitializeEx(IntPtr.Zero, 2), "Initialize playback audio"); com = true;
                    if (stop.WaitOne(0)) return;
                    enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
                    // eRender/eMultimedia: the default speaker/headphone playback mix, never eCapture.
                    Check(enumerator.GetDefaultAudioEndpoint(0, 1, out endpoint), "Find playback device");
                    Guid clientId = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"); object activated;
                    Check(endpoint.Activate(ref clientId, 23, IntPtr.Zero, out activated), "Open playback device");
                    client = (IAudioClient)activated;
                    Check(client.GetMixFormat(out formatPointer), "Read playback format");
                    WaveFormat format = WaveFormat.Read(formatPointer);
                    // Shared-mode loopback; polling avoids the old Windows loopback event limitation.
                    Check(client.Initialize(0, 0x20000, 1000000, 0, formatPointer, IntPtr.Zero), "Start playback analysis");
                    Guid captureId = new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"); object service;
                    Check(client.GetService(ref captureId, out service), "Open playback analysis buffer");
                    capture = (IAudioCaptureClient)service;
                    if (stop.WaitOne(0)) return;
                    Check(client.Start(), "Listen to playback"); started = true;
                    owner.PublishAudio(this, null, true, "Listening to Windows playback audio");
                    AudioAnalyzer analyzer = new AudioAnalyzer();
                    while (!stop.WaitOne(10))
                    {
                        uint pending; Check(capture.GetNextPacketSize(out pending), "Read playback packet");
                        while (pending != 0 && !stop.WaitOne(0))
                        {
                            IntPtr data; uint frames, flags; ulong position, timestamp;
                            Check(capture.GetBuffer(out data, out frames, out flags, out position, out timestamp), "Read playback samples");
                            if (frames == 0) break;
                            MusicSample levels = null;
                            try
                            {
                                if ((flags & 1) != 0) analyzer = new AudioAnalyzer();
                                float[] mono = format.StrongestChannel(data, frames, (flags & 2) != 0);
                                levels = analyzer.Process(mono, format.sampleRate, MonotonicTime);
                            }
                            finally { Check(capture.ReleaseBuffer(frames), "Release playback samples"); }
                            owner.PublishAudio(this, levels, true, levels.level > 0.01 ? "Listening to Windows playback audio" : "Listening to playback · play audio on your PC");
                            Check(capture.GetNextPacketSize(out pending), "Read playback packet");
                        }
                    }
                }
                catch (Exception ex)
                {
                    owner.PublishAudio(this, new MusicSample(), false, "Playback audio unavailable: " + ex.Message + " · retry audio after choosing your output device");
                }
                finally
                {
                    if (started && client != null) try { client.Stop(); } catch (COMException) { }
                    if (formatPointer != IntPtr.Zero) Marshal.FreeCoTaskMem(formatPointer);
                    Release(capture); Release(client); Release(endpoint); Release(enumerator);
                    if (com) CoUninitialize();
                    lock (lifecycle) { finished = true; stop.Dispose(); }
                }
            }
        }

        private sealed class WaveFormat
        {
            internal int channels, sampleRate, bits, blockAlign;
            internal bool floating;
            private static int Word(IntPtr pointer, int offset) { return unchecked((ushort)Marshal.ReadInt16(pointer, offset)); }
            internal static WaveFormat Read(IntPtr pointer)
            {
                int tag = Word(pointer, 0);
                WaveFormat result = new WaveFormat {
                    channels = Word(pointer, 2), sampleRate = Marshal.ReadInt32(pointer, 4),
                    blockAlign = Word(pointer, 12), bits = Word(pointer, 14)
                };
                if (tag == 0xFFFE)
                {
                    if (Word(pointer, 16) < 22) throw new InvalidOperationException("Incomplete playback format");
                    Guid subtype = (Guid)Marshal.PtrToStructure(IntPtr.Add(pointer, 24), typeof(Guid));
                    if (subtype == new Guid("00000003-0000-0010-8000-00aa00389b71")) tag = 3;
                    else if (subtype == new Guid("00000001-0000-0010-8000-00aa00389b71")) tag = 1;
                }
                result.floating = tag == 3;
                bool supported = (tag == 3 && result.bits == 32) || (tag == 1 && (result.bits == 16 || result.bits == 24 || result.bits == 32));
                if (!supported || result.channels < 1 || result.channels > 32 || result.sampleRate < 8000 || result.sampleRate > 384000 ||
                    result.blockAlign != result.channels * (result.bits / 8)) throw new InvalidOperationException("Unsupported playback format");
                return result;
            }
            internal float[] StrongestChannel(IntPtr pointer, uint frameCount, bool silent)
            {
                if (frameCount == 0 || frameCount > 65536) throw new InvalidOperationException("Unexpected playback packet size");
                int frames = (int)frameCount;
                float[] result = new float[frames];
                if (silent) return result;
                if (pointer == IntPtr.Zero) throw new InvalidOperationException("Playback samples are unavailable");
                byte[] raw = new byte[checked(frames * blockAlign)]; Marshal.Copy(pointer, raw, 0, raw.Length);
                double strongest = -1; int winner = 0;
                for (int channel = 0; channel < channels; channel++)
                {
                    double energy = 0;
                    for (int frame = 0; frame < frames; frame++)
                    { double value = Decode(raw, frame * blockAlign + channel * (bits / 8)); energy += value * value; }
                    if (energy > strongest) { strongest = energy; winner = channel; }
                }
                for (int frame = 0; frame < frames; frame++) result[frame] = Decode(raw, frame * blockAlign + winner * (bits / 8));
                // Only compact levels leave this callback. No samples are stored or written to disk.
                Array.Clear(raw, 0, raw.Length); return result;
            }
            private float Decode(byte[] bytes, int offset)
            {
                if (floating) { float value = BitConverter.ToSingle(bytes, offset); return Single.IsNaN(value) || Single.IsInfinity(value) ? 0 : value; }
                if (bits == 16) return BitConverter.ToInt16(bytes, offset) / 32768f;
                if (bits == 32) return (float)(BitConverter.ToInt32(bytes, offset) / 2147483648.0);
                int value24 = bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
                if ((value24 & 0x800000) != 0) value24 |= unchecked((int)0xFF000000);
                return value24 / 8388608f;
            }
        }

        private static void Check(int result, string operation)
        { if (result < 0) throw new COMException(operation + " (0x" + result.ToString("X8", CultureInfo.InvariantCulture) + ")", result); }
        private static void Release(object value) { if (value != null && Marshal.IsComObject(value)) Marshal.ReleaseComObject(value); }
        [DllImport("ole32.dll")] private static extern int CoInitializeEx(IntPtr reserved, uint flags);
        [DllImport("ole32.dll")] private static extern void CoUninitialize();

        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] private class MMDeviceEnumerator { }
        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IMMDeviceEnumerator
        {
            [PreserveSig] int EnumAudioEndpoints(int flow, uint mask, out IntPtr devices);
            [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice endpoint);
            [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice endpoint);
            [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr callback);
            [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr callback);
        }
        [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IMMDevice
        {
            [PreserveSig] int Activate(ref Guid iid, uint context, IntPtr parameters, [MarshalAs(UnmanagedType.IUnknown)] out object value);
            [PreserveSig] int OpenPropertyStore(uint mode, out IntPtr properties);
            [PreserveSig] int GetId(out IntPtr id);
            [PreserveSig] int GetState(out uint state);
        }
        [ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAudioClient
        {
            [PreserveSig] int Initialize(int shareMode, uint flags, long duration, long periodicity, IntPtr format, IntPtr sessionGuid);
            [PreserveSig] int GetBufferSize(out uint frames);
            [PreserveSig] int GetStreamLatency(out long latency);
            [PreserveSig] int GetCurrentPadding(out uint padding);
            [PreserveSig] int IsFormatSupported(int shareMode, IntPtr format, out IntPtr closest);
            [PreserveSig] int GetMixFormat(out IntPtr format);
            [PreserveSig] int GetDevicePeriod(out long normal, out long minimum);
            [PreserveSig] int Start();
            [PreserveSig] int Stop();
            [PreserveSig] int Reset();
            [PreserveSig] int SetEventHandle(IntPtr handle);
            [PreserveSig] int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object service);
        }
        [ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAudioCaptureClient
        {
            [PreserveSig] int GetBuffer(out IntPtr samples, out uint frames, out uint flags, out ulong devicePosition, out ulong timestamp);
            [PreserveSig] int ReleaseBuffer(uint frames);
            [PreserveSig] int GetNextPacketSize(out uint frames);
        }
    }
}
