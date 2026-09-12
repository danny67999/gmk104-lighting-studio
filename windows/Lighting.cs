using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Web.Script.Serialization;

namespace Gmk104LightingStudio
{
    public sealed class LightingSettings
    {
        public string effect = "ripple";
        public RGB color = new RGB(0, 220, 255);
        public double speed = 1, intensity = 1;
        public int brightness = 3;
        public double musicSensitivity = 1, temperatureCold = 40, temperatureHot = 90;
        public LightingSettings Clone() { return (LightingSettings)MemberwiseClone(); }
        public void Validate()
        {
            PersistJson.Require(LightingEngine.Effects.Contains(effect), "Unknown lighting effect.");
            PersistJson.Require(LightingEngine.InRange(speed, 0.25, 3), "Effect speed must be between 0.25 and 3.");
            PersistJson.Require(LightingEngine.InRange(intensity, 0, 1), "Effect intensity must be between 0 and 1.");
            PersistJson.Require(brightness >= 0 && brightness <= 4, "Brightness must be 0-4.");
            PersistJson.Require(LightingEngine.InRange(musicSensitivity, 0.25, 4), "Music sensitivity must be between 0.25 and 4.");
            PersistJson.Require(LightingEngine.InRange(temperatureCold, 10, 80) && LightingEngine.InRange(temperatureHot, 40, 110) && temperatureHot - temperatureCold >= 5,
                "Choose a cool temperature of 10-80 C and a hot temperature of 40-110 C, at least 5 C apart.");
        }
        public LightingSettings Normalized()
        {
            var result = Clone(); result.speed = LightingEngine.ClampFinite(speed, 0.25, 3, 1);
            result.intensity = LightingEngine.ClampFinite(intensity, 0, 1, 1);
            result.brightness = Math.Min(4, Math.Max(0, brightness));
            result.musicSensitivity = LightingEngine.ClampFinite(musicSensitivity, 0.25, 4, 1);
            result.temperatureCold = LightingEngine.ClampFinite(temperatureCold, 10, 80, 40);
            result.temperatureHot = LightingEngine.ClampFinite(temperatureHot, Math.Max(40, result.temperatureCold + 5), 110, 90);
            return result;
        }
        internal static LightingSettings FromJson(object value)
        {
            var j = PersistJson.Object(value);
            return new LightingSettings { effect = PersistJson.String(j, "effect"), color = PersistJson.Color(PersistJson.Field(j, "color")),
                speed = PersistJson.Number(j, "speed"), intensity = PersistJson.Number(j, "intensity"), brightness = PersistJson.Int(j, "brightness"),
                musicSensitivity = PersistJson.OptionalNumber(j, "musicSensitivity", 1), temperatureCold = PersistJson.OptionalNumber(j, "temperatureCold", 40),
                temperatureHot = PersistJson.OptionalNumber(j, "temperatureHot", 90) };
        }
    }

    public sealed class LightingLayer
    {
        public const int Limit = 16;
        public string id = Guid.NewGuid().ToString();
        public string name = "Ripple";
        public bool enabled = true;
        public LightingSettings settings = new LightingSettings();
        public double opacity = 1;
        public string blendMode = "normal";
        public List<string> keyIDs;
        public bool affectAllKeys;
        public LightingLayer() { }
        public LightingLayer(LightingSettings settings) { this.settings = settings.Clone(); name = LightingEngine.DisplayName(settings.effect); }
        public LightingLayer Clone()
        {
            var value = (LightingLayer)MemberwiseClone(); value.settings = settings.Clone();
            value.keyIDs = keyIDs == null ? null : new List<string>(keyIDs); return value;
        }
        public bool AcceptsTrigger(string keyID) { return keyIDs == null || keyIDs.Contains(keyID); }
        public void Validate(KeyGeometry[] keys = null)
        {
            Guid guid;
            PersistJson.Require(Guid.TryParse(id, out guid), "Each layer needs a valid identifier.");
            PersistJson.Require(settings != null, "A layer is missing its settings."); settings.Validate();
            PersistJson.Require(!String.IsNullOrWhiteSpace(name) && name.Length <= 80, "Give each layer a name of 1-80 characters.");
            PersistJson.Require(LightingEngine.InRange(opacity, 0, 1), "Layer opacity must be between 0 and 1.");
            PersistJson.Require(blendMode == "normal" || blendMode == "additive", "Unknown layer blend mode.");
            if (keyIDs != null)
            {
                PersistJson.Require(keyIDs.Count <= 104 && keyIDs.All(x => !String.IsNullOrEmpty(x)) && keyIDs.Distinct().Count() == keyIDs.Count,
                    "Layer selections must contain unique keyboard keys.");
                if (keys != null) PersistJson.Require(new HashSet<string>(keys.Select(x => x.id)).IsSupersetOf(keyIDs), "A layer contains keys outside this keyboard layout.");
            }
        }
        public static void ValidateLayers(List<LightingLayer> layers, KeyGeometry[] keys = null)
        {
            PersistJson.Require(layers != null && layers.Count >= 1 && layers.Count <= Limit && layers.All(x => x != null), "Use between 1 and 16 lighting layers.");
            foreach (var layer in layers) layer.Validate(keys);
            PersistJson.Require(layers.Select(x => Guid.Parse(x.id)).Distinct().Count() == layers.Count, "Lighting layers must have unique identifiers.");
        }
        internal static LightingLayer FromJson(object value)
        {
            var j = PersistJson.Object(value); object selection;
            var layer = new LightingLayer { id = PersistJson.String(j, "id"), name = PersistJson.String(j, "name"), enabled = PersistJson.Bool(j, "enabled"),
                settings = LightingSettings.FromJson(PersistJson.Field(j, "settings")), opacity = PersistJson.Number(j, "opacity"),
                blendMode = PersistJson.String(j, "blendMode"), affectAllKeys = PersistJson.OptionalBool(j, "affectAllKeys", false) };
            if (j.TryGetValue("keyIDs", out selection) && selection != null)
            {
                var ids = PersistJson.Array(j, "keyIDs"); PersistJson.Require(ids.All(x => x is string), "Invalid layer key selection.");
                layer.keyIDs = ids.Cast<string>().ToList();
            }
            return layer;
        }
    }

    public sealed class LightingProfile
    {
        public int version = 2;
        public string mode = "studio";
        public LightingSettings settings = new LightingSettings();
        public int builtInEffect = 1;
        public RGB[] colors;
        public bool restoreOnReconnect = true, resume = true;
        public List<LightingLayer> layers = new List<LightingLayer> { new LightingLayer() };
        public int? frameRate;
        [ScriptIgnore] public List<LightingLayer> StudioLayers
        {
            get { return layers ?? new List<LightingLayer> { new LightingLayer(settings) { id = "00000000-0000-4000-8000-000000000001" } }; }
        }
        public void Validate(KeyGeometry[] keys = null)
        {
            PersistJson.Require(version == 1 || version == 2, "Unsupported saved lighting profile.");
            PersistJson.Require(mode == "studio" || mode == "builtIn" || mode == "frame", "Unknown saved lighting mode.");
            PersistJson.Require(settings != null, "Profile is missing its settings."); settings.Validate();
            if (frameRate.HasValue) PersistJson.Require(new[] { 15, 30, 60, 90, 120 }.Contains(frameRate.Value), "Animation FPS must be 15, 30, 60, 90 or 120.");
            if (layers != null) LightingLayer.ValidateLayers(layers, keys);
            PersistJson.Require(!(version == 2 && mode == "studio" && layers == null), "Saved studio profile is missing its layers.");
            PersistJson.Require(builtInEffect >= 0 && builtInEffect <= 18, "Saved built-in effect is invalid.");
            if (mode == "frame") PersistJson.Require(colors != null && colors.Length == 104, "Saved lighting frame must contain 104 colors.");
        }
        public LightingProfile Clone()
        {
            var p = (LightingProfile)MemberwiseClone(); p.settings = settings.Clone(); p.colors = colors == null ? null : (RGB[])colors.Clone();
            p.layers = layers == null ? null : layers.Select(x => x.Clone()).ToList(); return p;
        }
        public void Save(string path) { Validate(); PersistJson.Save(path, this); }
        public static LightingProfile Load(string path)
        {
            if (!File.Exists(path)) return null;
            var j = PersistJson.Read(path); object optional;
            var p = new LightingProfile { version = PersistJson.Int(j, "version"), mode = PersistJson.String(j, "mode"),
                settings = LightingSettings.FromJson(PersistJson.Field(j, "settings")), builtInEffect = PersistJson.Int(j, "builtInEffect"),
                restoreOnReconnect = PersistJson.Bool(j, "restoreOnReconnect"), resume = PersistJson.Bool(j, "resume"),
                layers = null, frameRate = PersistJson.OptionalInt(j, "frameRate") };
            if (j.TryGetValue("layers", out optional) && optional != null) p.layers = PersistJson.Array(j, "layers").Select(LightingLayer.FromJson).ToList();
            if (j.TryGetValue("colors", out optional) && optional != null) p.colors = PersistJson.Array(j, "colors").Select(PersistJson.Color).ToArray();
            p.Validate(); return p;
        }
    }

    public sealed class KeyPulse
    {
        public string keyID;
        public double time;
        public KeyPulse() { }
        public KeyPulse(string keyID, double time) { this.keyID = keyID; this.time = time; }
    }
    public sealed class MusicSample
    {
        public double bass, mid, treble, level;
        public double timestamp = Double.NegativeInfinity;
        public MusicSample Fresh(double time)
        {
            if (!LightingEngine.Finite(time) || !LightingEngine.Finite(timestamp) || time < timestamp || time - timestamp >= 0.5) return new MusicSample();
            return new MusicSample { bass = LightingEngine.ClampFinite(bass, 0, 1, 0), mid = LightingEngine.ClampFinite(mid, 0, 1, 0),
                treble = LightingEngine.ClampFinite(treble, 0, 1, 0), level = LightingEngine.ClampFinite(level, 0, 1, 0), timestamp = timestamp };
        }
    }
    public sealed class LightingInputs
    {
        public MusicSample music = new MusicSample();
        public string musicStatus = "Windows audio is stopped", temperatureStatus = "CPU temperature is stopped";
        public bool audioRunning;
        public double? cpuCelsius;
        public double temperatureTime = Double.NegativeInfinity;
        public double? Temperature(double time)
        {
            return cpuCelsius.HasValue && LightingEngine.InRange(cpuCelsius.Value, 1, 125) && LightingEngine.Finite(time) &&
                LightingEngine.Finite(temperatureTime) && time >= temperatureTime && time - temperatureTime < 5 ? cpuCelsius : null;
        }
    }

    public static class LightingEngine
    {
        public const int LedCount = 104;
        public static readonly string[] Effects = { "ripple", "rainbowRipple", "reactive", "wave", "breathing", "spectrum", "staticColor", "adaptiveMusic", "cpuTemperature" };
        public static string DisplayName(string effect)
        {
            switch (effect) { case "ripple": return "Ripple"; case "rainbowRipple": return "Rainbow ripple"; case "reactive": return "Reactive";
                case "wave": return "Rainbow wave"; case "breathing": return "Breathing"; case "spectrum": return "Spectrum cycle";
                case "staticColor": return "Static color"; case "adaptiveMusic": return "Adaptive music"; case "cpuTemperature": return "CPU temperature"; default: return effect; }
        }
        public static bool RequiresKeyPresses(string effect) { return effect == "ripple" || effect == "rainbowRipple" || effect == "reactive"; }
        public static bool RequiresMapping(string effect) { return RequiresKeyPresses(effect) || effect == "wave" || effect == "adaptiveMusic"; }
        public static bool UsesSelectedColor(string effect) { return effect != "wave" && effect != "spectrum" && effect != "rainbowRipple" && effect != "adaptiveMusic" && effect != "cpuTemperature"; }
        public static double MaximumPulseAge(LightingSettings settings) { return 4.5 / settings.Normalized().speed; }
        public static List<KeyPulse> AdjustPulses(List<KeyPulse> pulses, double previous, double now, double maximumStep)
        {
            if (!Finite(previous) || !Finite(now) || !Finite(maximumStep) || maximumStep < 0) return pulses.Select(x => new KeyPulse(x.keyID, x.time)).ToList();
            double skipped = Math.Max(0, now - previous - maximumStep);
            return pulses.Select(x => new KeyPulse(x.keyID, Math.Min(now, x.time + skipped))).ToList();
        }

        // Layers are displayed topmost first and compose into one framebuffer.
        public static RGB[] Render(List<LightingLayer> layers, KeyGeometry[] keys, MappingFile mapping, List<KeyPulse> pulses, double time, LightingInputs inputs = null)
        {
            var result = new RGB[LedCount];
            if (layers == null) return result;
            keys = keys ?? new KeyGeometry[0]; pulses = pulses ?? new List<KeyPulse>(); inputs = inputs ?? new LightingInputs();
            var safeKeys = ConfirmedKeys(keys, mapping);
            for (int li = layers.Count - 1; li >= 0; li--)
            {
                var layer = layers[li];
                if (layer == null || layer.settings == null || !layer.enabled || !Finite(layer.opacity) || layer.opacity <= 0 || (layer.keyIDs != null && layer.keyIDs.Count == 0)) continue;
                double opacity = Math.Min(1, layer.opacity);
                var layerPulses = RequiresKeyPresses(layer.settings.effect) ? pulses.Where(x => x != null && layer.AcceptsTrigger(x.keyID)).ToList() : pulses;
                var colors = RenderEffect(layer.settings, keys, mapping, layerPulses, time, layer.affectAllKeys, inputs);
                var white = layer.settings.Clone(); white.color = new RGB(255, 255, 255);
                if (white.effect == "rainbowRipple") white.effect = "ripple";
                var coverage = UsesSelectedColor(layer.settings.effect) || layer.settings.effect == "rainbowRipple"
                    ? RenderEffect(white, keys, mapping, layerPulses, time, layer.affectAllKeys, inputs) : colors;
                HashSet<int> mask = layer.affectAllKeys || layer.keyIDs == null ? null : new HashSet<int>(safeKeys.Where(x => layer.keyIDs.Contains(x.id)).Select(x => x.index));
                for (int i = 0; i < LedCount; i++)
                {
                    if (mask != null && !mask.Contains(i)) continue;
                    double alpha = Peak(coverage[i]) / 255.0 * opacity;
                    double remaining = layer.blendMode == "normal" ? 1 - alpha : 1;
                    result[i] = new RGB(Byte(result[i].r * remaining + colors[i].r * opacity), Byte(result[i].g * remaining + colors[i].g * opacity), Byte(result[i].b * remaining + colors[i].b * opacity));
                }
            }
            return result;
        }

        public static RGB[] RenderEffect(LightingSettings settings, KeyGeometry[] keys, MappingFile mapping, List<KeyPulse> pulses, double time, bool reactiveAffectsAllKeys = false, LightingInputs inputs = null)
        {
            settings = (settings ?? new LightingSettings()).Normalized(); inputs = inputs ?? new LightingInputs();
            var frame = new RGB[LedCount]; if (settings.intensity == 0) return frame;
            double clock = Finite(time) ? time : 0;
            switch (settings.effect)
            {
                case "staticColor": return Solid(Scale(settings.color, settings.intensity));
                case "breathing":
                    double breath = (1 - Math.Cos(Wrapped(clock, 3 / settings.speed) * 2 * Math.PI)) / 2;
                    return Solid(Scale(settings.color, (0.025 + 0.975 * breath * breath) * settings.intensity));
                case "spectrum": return Solid(HueColor(Wrapped(clock, 9 / settings.speed), settings.intensity));
                case "cpuTemperature":
                    double? temp = inputs.Temperature(time); if (!temp.HasValue) return frame;
                    double fraction = Math.Min(1, Math.Max(0, (temp.Value - settings.temperatureCold) / (settings.temperatureHot - settings.temperatureCold)));
                    return Solid(HueColor((1 - fraction) * (2.0 / 3), settings.intensity));
                case "ripple": case "rainbowRipple": case "reactive": case "wave": case "adaptiveMusic": break;
                default: return frame;
            }
            var mapped = ConfirmedKeys(keys ?? new KeyGeometry[0], mapping);
            if (settings.effect == "adaptiveMusic")
            {
                var audio = (inputs.music ?? new MusicSample()).Fresh(time);
                if (audio.level <= 0 || mapped.Count == 0) return frame;
                double minX = mapped.Min(x => x.x), maxX = mapped.Max(x => x.x), minY = mapped.Min(x => x.y), maxY = mapped.Max(x => x.y);
                foreach (var key in mapped)
                {
                    double x = (key.x - minX) / Math.Max(1, maxX - minX), height = (maxY - key.y) / Math.Max(1, maxY - minY);
                    double band = x < 0.5 ? audio.bass * (1 - x * 2) + audio.mid * x * 2 : audio.mid * (2 - x * 2) + audio.treble * (x * 2 - 1);
                    double level = Math.Min(1, band * settings.musicSensitivity), bar = Math.Min(1, Math.Max(0, (level - height * 0.85) * 5));
                    frame[key.index] = HueColor(x * 0.8 - Wrapped(clock, 12 / settings.speed), (0.08 * level + 0.92 * bar * level) * settings.intensity);
                }
                return frame;
            }
            if (settings.effect == "wave")
            {
                double phase = Wrapped(clock, 5 / settings.speed);
                foreach (var key in mapped) frame[key.index] = HueColor(key.x / 8 + key.y * (0.35 / 8) - phase, settings.intensity);
                return frame;
            }
            if (!Finite(time)) return frame;
            var origins = mapped.ToDictionary(x => x.id); var active = new List<ActivePulse>();
            foreach (var pulse in pulses ?? new List<KeyPulse>())
            {
                MappedKey origin;
                if (pulse == null || !Finite(pulse.time) || pulse.keyID == null || !origins.TryGetValue(pulse.keyID, out origin)) continue;
                double age = (time - pulse.time) * settings.speed;
                if (!Finite(age) || age < 0 || age >= 4.5) continue;
                active.Add(new ActivePulse { origin = origin, age = age, reach = mapped.Max(x => Distance(x.x - origin.x, x.y - origin.y)) });
            }
            foreach (var key in mapped)
            {
                double level = 0, red = 0, green = 0, blue = 0;
                foreach (var pulse in active)
                {
                    if (settings.effect == "reactive")
                    {
                        if ((!reactiveAffectsAllKeys && key.id != pulse.origin.id) || pulse.age >= 1.4) continue;
                        double remaining = 1 - pulse.age / 1.4; level += remaining * remaining;
                    }
                    else
                    {
                        double distance = Distance(key.x - pulse.origin.x, key.y - pulse.origin.y), radius = pulse.age * 8;
                        double width = 0.6 + radius * 0.045, offset = (distance - radius) / width;
                        double travelFade = 1 - 0.2 * Math.Min(1, radius / Math.Max(1, pulse.reach));
                        double exitFade = Math.Max(0, 1 - Math.Max(0, radius - pulse.reach) / (width * 3));
                        double contribution = Math.Exp(-0.5 * offset * offset) * travelFade * exitFade * exitFade;
                        level += contribution;
                        if (settings.effect == "rainbowRipple")
                        {
                            RGB color = HueColor(Math.Atan2(key.y - pulse.origin.y, key.x - pulse.origin.x) / (2 * Math.PI) + pulse.age * 0.4, 1);
                            red += color.r * contribution; green += color.g * contribution; blue += color.b * contribution;
                        }
                    }
                }
                if (settings.effect == "rainbowRipple")
                {
                    double amount = settings.intensity / Math.Max(1, level);
                    frame[key.index] = new RGB(Byte(red * amount), Byte(green * amount), Byte(blue * amount));
                }
                else frame[key.index] = Scale(settings.color, Math.Min(1, level) * settings.intensity);
            }
            return frame;
        }

        private sealed class MappedKey { public string id; public int index; public double x, y; }
        private sealed class ActivePulse { public MappedKey origin; public double age, reach; }
        private static List<MappedKey> ConfirmedKeys(KeyGeometry[] keys, MappingFile mapping)
        {
            var result = new List<MappedKey>();
            if (mapping == null || mapping.schemaVersion != 1 || mapping.layoutId != "ansi-104" || mapping.ledCount != LedCount || mapping.mappings == null) return result;
            var geometry = keys.Where(x => x != null && x.id != null).GroupBy(x => x.id).ToDictionary(x => x.Key, x => x.ToArray());
            var entries = mapping.mappings.Where(x => x != null && x.keyId != null).ToArray();
            var keyCounts = entries.GroupBy(x => x.keyId).ToDictionary(x => x.Key, x => x.Count());
            var ledCounts = entries.Where(x => x.ledIndex.HasValue).GroupBy(x => x.ledIndex.Value).ToDictionary(x => x.Key, x => x.Count());
            foreach (var entry in entries)
            {
                KeyGeometry[] candidates;
                if (!entry.confirmed || !entry.ledIndex.HasValue || entry.ledIndex.Value < 0 || entry.ledIndex.Value >= LedCount ||
                    ledCounts[entry.ledIndex.Value] != 1 || keyCounts[entry.keyId] != 1 || !geometry.TryGetValue(entry.keyId, out candidates) || candidates.Length != 1) continue;
                var key = candidates[0]; if (!Finite(key.x) || !Finite(key.y) || !Finite(key.width) || !Finite(key.height) || key.width <= 0 || key.height <= 0) continue;
                double x = key.x + key.width / 2, y = key.y + key.height / 2;
                if (Finite(x) && Finite(y)) result.Add(new MappedKey { id = key.id, index = entry.ledIndex.Value, x = x, y = y });
            }
            return result;
        }
        public static bool Finite(double value) { return !Double.IsNaN(value) && !Double.IsInfinity(value); }
        public static bool InRange(double value, double low, double high) { return Finite(value) && value >= low && value <= high; }
        public static double ClampFinite(double value, double low, double high, double fallback) { return Finite(value) ? Math.Min(high, Math.Max(low, value)) : fallback; }
        public static int Peak(RGB color) { return Math.Max(color.r, Math.Max(color.g, color.b)); }
        private static byte Byte(double value) { return (byte)Math.Round(ClampFinite(value, 0, 255, 0), MidpointRounding.AwayFromZero); }
        private static RGB[] Solid(RGB color) { return Enumerable.Repeat(color, LedCount).ToArray(); }
        private static double Wrapped(double time, double period) { double phase = (time % period) / period; return phase < 0 ? phase + 1 : phase; }
        private static double Distance(double x, double y) { x = Math.Abs(x); y = Math.Abs(y); double max = Math.Max(x, y); if (max == 0) return 0; return max * Math.Sqrt((x / max) * (x / max) + (y / max) * (y / max)); }
        private static RGB Scale(RGB color, double level) { double amount = ClampFinite(level, 0, 1, 0); return new RGB(Byte(color.r * amount), Byte(color.g * amount), Byte(color.b * amount)); }
        private static RGB HueColor(double hue, double level)
        {
            if (!Finite(hue)) return RGB.Black;
            hue -= Math.Floor(hue); double sector = hue * 6, fraction = sector - Math.Floor(sector);
            byte up = Byte(fraction * 255), down = Byte((1 - fraction) * 255); RGB color;
            switch ((int)sector) { case 0: color = new RGB(255, up, 0); break; case 1: color = new RGB(down, 255, 0); break;
                case 2: color = new RGB(0, 255, up); break; case 3: color = new RGB(0, down, 255); break;
                case 4: color = new RGB(up, 0, 255); break; default: color = new RGB(255, 0, down); break; }
            return Scale(color, level);
        }
    }
}
