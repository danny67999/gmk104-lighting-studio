using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Gmk104LightingStudio
{
    // The firmware and both desktop apps share this byte format. Encoding never opens a device.
    public sealed class OnboardProfile
    {
        public const int MaximumSize = 4064, HeaderSize = 32, KeyCount = 104;
        public static readonly string[] EffectIds = { "ripple", "rainbowRipple", "reactive", "wave", "breathing", "spectrum", "staticColor", "adaptiveMusic", "cpuTemperature", "keyHold", "starlight", "rainbowStarlight", "fire", "colorWheel", "scanner", "comet", "rain", "aurora", "keyToggle", "rainbowReactive", "splash", "crossRipple", "rowWave", "columnWave", "matrixRain", "spacedMatrixRain", "matrixKeyRain" };
        private readonly byte[] data;
        public byte[] Bytes { get { return (byte[])data.Clone(); } }
        public bool NeedsHostSensors { get { return data[20] != 0; } }
        public int MaximumEffectId
        {
            get { int highest = 0, at = HeaderSize + 312; if (data[5] == 0) for (int i = 0; i < data[6]; i++) { highest = Math.Max(highest, data[at]); at += 57 + data[at + 56]; } return highest; }
        }
        public OnboardProfile(byte[] bytes) { data = (byte[])bytes.Clone(); Validate(); }
        private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);
        public static OnboardProfile Compile(LightingProfile profile, KeyGeometry[] keys, MappingFile mapping, MappingFile factory)
        {
            profile.Validate(keys); mapping.Validate(keys); factory.Validate(keys);
            Require(keys.Length == KeyCount && keys.Select(x => x.id).Distinct().Count() == KeyCount, "The keyboard layout needs 104 unique keys.");
            Require(mapping.mappings.All(x => x.confirmed && x.ledIndex.HasValue) && factory.mappings.All(x => x.confirmed && x.ledIndex.HasValue), "Confirm all 104 keys before sending an on-keyboard profile.");
            var layout = keys.ToDictionary(x => x.id); var output = mapping.mappings.ToDictionary(x => x.keyId, x => x.ledIndex.Value); var scan = factory.mappings.ToDictionary(x => x.keyId, x => x.ledIndex.Value);
            byte[] scanToOutput = new byte[104], geometry = new byte[208];
            foreach (var pair in scan)
            {
                var key = layout[pair.Key]; int led = output[pair.Key];
                Require(LightingEngine.Finite(key.x) && LightingEngine.Finite(key.y) && LightingEngine.Finite(key.width) && LightingEngine.Finite(key.height) && key.width > 0 && key.height > 0, "Invalid keyboard geometry.");
                double x = Math.Round((key.x + key.width / 2) * 2, MidpointRounding.AwayFromZero), y = Math.Round((key.y + key.height / 2) * 2, MidpointRounding.AwayFromZero);
                Require(x >= 0 && x <= 127 && y >= 0 && y <= 127, "A key position is outside the supported keyboard area.");
                scanToOutput[pair.Value] = (byte)led; geometry[led * 2] = (byte)x; geometry[led * 2 + 1] = (byte)y;
            }
            var payload = new List<byte>(); payload.AddRange(scanToOutput); payload.AddRange(geometry);
            var layers = profile.mode == "studio" ? profile.StudioLayers : new List<LightingLayer>(); byte sensors = 0;
            // An empty editor exports as one disabled black layer; the wire format stays compatible.
            if (profile.mode == "studio" && layers.Count == 0) layers = new List<LightingLayer> { new LightingLayer(new LightingSettings { effect = "staticColor", color = RGB.Black }) { id = "00000000-0000-4000-8000-000000000000", name = "No effects", enabled = false, keyIDs = new List<string>() } };
            if (profile.mode == "frame") foreach (var c in profile.colors) payload.AddRange(new byte[] { c.r, c.g, c.b });
            foreach (var layer in layers)
            {
                int effect = Array.IndexOf(EffectIds, layer.settings.effect); Require(effect >= 0, "" + layer.settings.effect + " requires Play from PC; this firmware cannot play that effect itself.");
                byte[] name = Utf8.GetBytes(layer.name); Require(name.Length > 0 && name.Length <= 80, "On-keyboard layer names must fit in 80 UTF-8 bytes.");
                if (layer.enabled && layer.opacity > 0) { if (effect == 7) sensors |= 1; if (effect == 8) sensors |= 2; }
                byte flags = (byte)((layer.enabled ? 1 : 0) | (layer.affectAllKeys ? 2 : 0) | (layer.blendMode == "additive" ? 4 : 0) | (layer.keyIDs == null ? 8 : 0));
                var selected = layer.keyIDs == null ? new HashSet<string>(layout.Keys) : new HashSet<string>(layer.keyIDs);
                byte[] trigger = Mask(selected.Select(x => scan[x]));
                byte[] visible = selected.Count == 0 ? new byte[13] : layer.affectAllKeys ? Mask(Enumerable.Range(0, 104)) : Mask(selected.Select(x => output[x]));
                payload.AddRange(new byte[] { (byte)effect, flags }); payload.AddRange(LE16(Quantize(layer.settings.speed, 256)));
                payload.AddRange(new byte[] { (byte)Quantize(layer.settings.intensity, 255), (byte)Quantize(layer.opacity, 255), (byte)layer.settings.brightness, layer.settings.color.r, layer.settings.color.g, layer.settings.color.b });
                payload.AddRange(LE16(Quantize(layer.settings.musicSensitivity, 256)));
                payload.AddRange(new byte[] { (byte)Quantize(layer.settings.temperatureCold, 1), (byte)Quantize(layer.settings.temperatureHot, 1) }); payload.AddRange(trigger); payload.AddRange(visible);
                // Guid.ToByteArray reverses the first three fields. Swift/firmware use UUID network order.
                string uuid = Guid.Parse(layer.id).ToString("N"); for (int i = 0; i < 32; i += 2) payload.Add(Convert.ToByte(uuid.Substring(i, 2), 16));
                payload.Add((byte)name.Length); payload.AddRange(name);
            }
            int length = HeaderSize + payload.Count; Require(length <= MaximumSize, "This profile exceeds the keyboard profile limit.");
            byte[] header = new byte[HeaderSize]; Encoding.ASCII.GetBytes("GMKP").CopyTo(header, 0); header[4] = 1; header[5] = (byte)(profile.mode == "studio" ? 0 : profile.mode == "builtIn" ? 1 : 2); header[6] = (byte)layers.Count; header[7] = (byte)profile.builtInEffect;
            LE16(length).CopyTo(header, 8); header[10] = (byte)profile.settings.brightness; header[11] = (byte)(profile.frameRate ?? 60); LE32(CRC32(payload.ToArray())).CopyTo(header, 12); Encoding.ASCII.GetBytes("A104").CopyTo(header, 16); header[20] = sensors;
            return new OnboardProfile(header.Concat(payload).ToArray());
        }
        public void Validate()
        {
            Require(data.Length >= HeaderSize + 312 && data.Length <= MaximumSize, "Invalid on-keyboard profile size.");
            Require(Encoding.ASCII.GetString(data, 0, 4) == "GMKP" && data[4] == 1 && Encoding.ASCII.GetString(data, 16, 4) == "A104" && U16(data, 8) == data.Length, "Unsupported or truncated on-keyboard profile.");
            Require(data[5] <= 2 && data[6] <= 16 && (data[5] == 0 ? data[6] > 0 : data[6] == 0) && data[7] <= 20 && data[7] != 19 && data[10] <= 4 && new[] { 15, 30, 60, 90, 120 }.Contains((int)data[11]) && (data[20] & ~3) == 0 && data.Skip(21).Take(11).All(x => x == 0), "Invalid on-keyboard profile header.");
            byte[] payload = data.Skip(HeaderSize).ToArray(); Require(CRC32(payload) == U32(data, 12), "The on-keyboard profile checksum differs.");
            byte[] scan = payload.Take(104).ToArray(); Require(scan.Distinct().Count() == 104 && scan.All(x => x < 104), "The physical key map is not a permutation."); Require(payload.Skip(104).Take(208).All(x => x < 128), "Invalid keyboard geometry.");
            if (data[5] != 0) { Require(data[20] == 0 && payload.Length == (data[5] == 2 ? 624 : 312), "Invalid manual or built-in profile payload."); return; }
            int at = 312; var ids = new HashSet<string>(); byte sensors = 0; byte[] all = Enumerable.Repeat((byte)255, 13).ToArray();
            for (int i = 0; i < data[6]; i++)
            {
                Require(at + 57 <= payload.Length, "Truncated layer."); int effect = payload[at], flags = payload[at + 1], speed = U16(payload, at + 2), music = U16(payload, at + 10);
                Require(effect < EffectIds.Length && (flags & ~15) == 0 && speed >= 64 && speed <= 768 && music >= 64 && music <= 1024 && payload[at + 6] <= 4 && payload[at + 12] >= 10 && payload[at + 12] <= 80 && payload[at + 13] >= 40 && payload[at + 13] <= 110 && payload[at + 13] - payload[at + 12] >= 5, "Invalid layer settings.");
                byte[] trigger = payload.Skip(at + 14).Take(13).ToArray(), output = payload.Skip(at + 27).Take(13).ToArray();
                if ((flags & 8) != 0) Require(trigger.SequenceEqual(all), "The all-key trigger flag differs from its mask.");
                byte[] expected = trigger.All(x => x == 0) ? new byte[13] : (flags & 2) != 0 ? all : Mask(Enumerable.Range(0, 104).Where(x => (trigger[x / 8] & (1 << (x % 8))) != 0).Select(x => (int)scan[x]));
                Require(output.SequenceEqual(expected), "The output mask differs from the physical mapping.");
                Require(ids.Add(BitConverter.ToString(payload, at + 40, 16)), "Duplicate layer identifier.");
                int nameLength = payload[at + 56]; Require(nameLength > 0 && nameLength <= 80 && at + 57 + nameLength <= payload.Length, "Invalid layer name length."); Require(!String.IsNullOrWhiteSpace(Utf8.GetString(payload, at + 57, nameLength)), "Invalid layer name.");
                if ((flags & 1) != 0 && payload[at + 5] > 0) { if (effect == 7) sensors |= 1; if (effect == 8) sensors |= 2; }
                at += 57 + nameLength;
            }
            Require(at == payload.Length && sensors == data[20], "Trailing profile data or incorrect sensor flags.");
        }
        private static void Require(bool condition, string message) { PersistJson.Require(condition, message); }
        private static byte[] Mask(IEnumerable<int> indices) { byte[] result = new byte[13]; foreach (int i in indices) { Require(i >= 0 && i < 104, "Invalid key index."); result[i / 8] |= (byte)(1 << (i % 8)); } return result; }
        private static int Quantize(double value, int scale) { return (int)Math.Round(value * scale, MidpointRounding.AwayFromZero); }
        internal static byte[] LE16(int value) { return new byte[] { unchecked((byte)value), unchecked((byte)(value >> 8)) }; }
        internal static byte[] LE32(uint value) { return Enumerable.Range(0, 4).Select(x => unchecked((byte)(value >> (x * 8)))).ToArray(); }
        internal static int U16(byte[] p, int offset) { return p[offset] | (p[offset + 1] << 8); }
        internal static uint U32(byte[] p, int offset) { return (uint)p[offset] | (uint)p[offset + 1] << 8 | (uint)p[offset + 2] << 16 | (uint)p[offset + 3] << 24; }
        public static uint CRC32(byte[] bytes) { uint crc = UInt32.MaxValue; foreach (byte b in bytes) { crc ^= b; for (int bit = 0; bit < 8; bit++) crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320U : crc >> 1; } return ~crc; }
    }
}
