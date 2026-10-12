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
            PersistJson.Require(layers != null && layers.Count <= Limit && layers.All(x => x != null), "Use up to 16 lighting layers.");
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
        public MappingFile mapping;
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
            if (mapping != null) mapping.Validate(keys);
            if (layers != null) LightingLayer.ValidateLayers(layers, keys);
            PersistJson.Require(!(version == 2 && mode == "studio" && layers == null), "Saved studio profile is missing its layers.");
            PersistJson.Require((builtInEffect >= 0 && builtInEffect <= 18 || builtInEffect == 20), "Saved built-in effect is invalid.");
            if (mode == "frame") PersistJson.Require(colors != null && colors.Length == 104, "Saved lighting frame must contain 104 colors.");
        }
        public LightingProfile Clone()
        {
            var p = (LightingProfile)MemberwiseClone(); p.settings = settings.Clone(); p.colors = colors == null ? null : (RGB[])colors.Clone();
            p.mapping = mapping == null ? null : mapping.Clone();
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
            if (j.TryGetValue("mapping", out optional) && optional != null) p.mapping = MappingFile.FromJson(optional);
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
        public static readonly string[] Effects = { "ripple", "rainbowRipple", "reactive", "wave", "breathing", "spectrum", "staticColor", "adaptiveMusic", "cpuTemperature", "keyHold", "starlight", "rainbowStarlight", "fire", "colorWheel", "scanner", "comet", "rain", "aurora", "keyToggle", "rainbowReactive", "splash", "crossRipple", "rowWave", "columnWave", "matrixRain", "spacedMatrixRain", "matrixKeyRain", "radar" };
        public static string DisplayName(string effect)
        {
            switch (effect) { case "ripple": return "Ripple"; case "rainbowRipple": return "Rainbow ripple"; case "reactive": return "Reactive";
                case "wave": return "Rainbow wave"; case "breathing": return "Breathing"; case "spectrum": return "Spectrum cycle";
                case "staticColor": return "Static color"; case "adaptiveMusic": return "Adaptive music"; case "cpuTemperature": return "CPU temperature"; case "keyHold": return "Hold (press/release)"; case "starlight": return "Starlight";
                case "rainbowStarlight": return "Rainbow starlight"; case "fire": return "Fire"; case "colorWheel": return "Color wheel";
                case "scanner": return "Scanner"; case "comet": return "Comet"; case "rain": return "Rain"; case "aurora": return "Aurora"; case "radar": return "Radar"; case "keyToggle": return "Key toggle"; case "rainbowReactive": return "Rainbow reactive"; case "splash": return "Splash"; case "crossRipple": return "Cross ripple"; case "rowWave": return "Row wave"; case "columnWave": return "Column wave"; case "matrixRain": return "Matrix rain"; case "spacedMatrixRain": return "Spaced matrix rain"; case "matrixKeyRain": return "Matrix key rain"; default: return effect; }
        }
        public static bool RequiresKeyPresses(string effect) { return new[] { "ripple", "rainbowRipple", "reactive", "keyHold", "keyToggle", "rainbowReactive", "splash", "crossRipple", "rowWave", "columnWave", "matrixKeyRain" }.Contains(effect); }
        public static bool RequiresMapping(string effect) { return effect != "staticColor" && effect != "breathing" && effect != "spectrum" && effect != "cpuTemperature"; }
        public static bool UsesSelectedColor(string effect) { return !new[] { "wave", "spectrum", "rainbowRipple", "adaptiveMusic", "cpuTemperature", "rainbowStarlight", "fire", "colorWheel", "aurora", "rainbowReactive" }.Contains(effect); }
        public static double MaximumPulseAge(LightingSettings settings) { return 4.5 / settings.Normalized().speed; }
        public static List<KeyPulse> AdjustPulses(List<KeyPulse> pulses, double previous, double now, double maximumStep)
        {
            if (!Finite(previous) || !Finite(now) || !Finite(maximumStep) || maximumStep < 0) return pulses.Select(x => new KeyPulse(x.keyID, x.time)).ToList();
            double skipped = Math.Max(0, now - previous - maximumStep);
            return pulses.Select(x => new KeyPulse(x.keyID, Math.Min(now, x.time + skipped))).ToList();
        }

        // Layers are displayed topmost first and compose into one framebuffer.
        public static RGB[] Render(List<LightingLayer> layers, KeyGeometry[] keys, MappingFile mapping, List<KeyPulse> pulses, double time, LightingInputs inputs = null, HashSet<string> heldKeys = null, HashSet<string> toggledKeys = null)
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
                var layerHeld = heldKeys == null ? new HashSet<string>() : new HashSet<string>(heldKeys.Where(layer.AcceptsTrigger));
                var layerToggled = toggledKeys == null ? new HashSet<string>() : new HashSet<string>(toggledKeys.Where(layer.AcceptsTrigger));
                var colors = RenderEffect(layer.settings, keys, mapping, layerPulses, time, layer.affectAllKeys, inputs, layerHeld, layerToggled);
                var white = layer.settings.Clone(); white.color = new RGB(255, 255, 255);
                if (white.effect == "rainbowRipple") white.effect = "ripple";
                if (white.effect == "rainbowReactive") white.effect = "reactive";
                var coverage = UsesSelectedColor(layer.settings.effect) || layer.settings.effect == "rainbowRipple" || layer.settings.effect == "rainbowReactive"
                    ? RenderEffect(white, keys, mapping, layerPulses, time, layer.affectAllKeys, inputs, layerHeld, layerToggled) : colors;
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

        public static RGB[] RenderEffect(LightingSettings settings, KeyGeometry[] keys, MappingFile mapping, List<KeyPulse> pulses, double time, bool reactiveAffectsAllKeys = false, LightingInputs inputs = null, HashSet<string> heldKeys = null, HashSet<string> toggledKeys = null)
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
                case "ripple": case "rainbowRipple": case "reactive": case "wave": case "adaptiveMusic": case "radar": case "keyHold": case "starlight": case "rainbowStarlight": case "fire": case "colorWheel": case "scanner": case "comet": case "rain": case "aurora": case "keyToggle": case "rainbowReactive": case "splash": case "crossRipple": case "rowWave": case "columnWave": case "matrixRain": case "spacedMatrixRain": case "matrixKeyRain": break;
                default: return frame;
            }
            var mapped = ConfirmedKeys(keys ?? new KeyGeometry[0], mapping);
            if (settings.effect == "spacedMatrixRain" || settings.effect == "matrixKeyRain") {
                var known=new HashSet<string>(mapped.Select(k=>k.id));
                var validPulses=pulses.Where(k=>k!=null&&known.Contains(k.keyID)).ToList();
                foreach(var key in mapped) frame[key.index]=settings.effect=="spacedMatrixRain" ? LogicalMatrixRaster.Automatic(key.id,clock,settings) : LogicalMatrixRaster.Reactive(key.id,clock,validPulses,settings);
                return frame;
            }
            if (settings.effect == "matrixRain")
            {
                if (mapped.Count == 0) return frame;
                int minY = mapped.Min(k => (int)Math.Round(k.y * 2, MidpointRounding.AwayFromZero));
                int maxY = mapped.Max(k => (int)Math.Round(k.y * 2, MidpointRounding.AwayFromZero));
                foreach (var key in mapped) frame[key.index] = MatrixRainRaster.Pixel((int)Math.Round(key.x * 2, MidpointRounding.AwayFromZero), (int)Math.Round(key.y * 2, MidpointRounding.AwayFromZero), minY, maxY, clock, settings);
                return frame;
            }
            if (settings.effect == "radar")
            {
                if (mapped.Count == 0) return frame;
                double cx = (mapped.Min(k => k.x) + mapped.Max(k => k.x)) / 2;
                double cy = (mapped.Min(k => k.y) + mapped.Max(k => k.y)) / 2;
                double sweep = Wrapped(clock, 4 / settings.speed) * 2 * Math.PI;
                foreach (var key in mapped)
                {
                    double dx = key.x - cx, dy = key.y - cy;
                    double behind = (sweep - Math.Atan2(dy, dx) + 4 * Math.PI) % (2 * Math.PI);
                    double level = dx * dx + dy * dy < 0.000001 ? 1 : Math.Exp(-behind * 2.5);
                    frame[key.index] = Scale(settings.color, level * settings.intensity);
                }
                return frame;
            }
            if (settings.effect == "keyHold" || settings.effect == "keyToggle")
            {
                var litKeys = (settings.effect == "keyToggle" ? toggledKeys : heldKeys) ?? new HashSet<string>();
                if (!mapped.Any(x => litKeys.Contains(x.id))) return frame;
                foreach (var key in mapped.Where(x => reactiveAffectsAllKeys || litKeys.Contains(x.id))) frame[key.index] = Scale(settings.color, settings.intensity);
                return frame;
            }
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
            if (new[] { "starlight", "rainbowStarlight", "fire", "colorWheel", "scanner", "comet", "rain", "aurora" }.Contains(settings.effect))
            {
                if (mapped.Count == 0) return frame;
                double minX = mapped.Min(x => x.x), maxX = mapped.Max(x => x.x), minY = mapped.Min(x => x.y), maxY = mapped.Max(x => x.y);
                double movement = Wrapped(clock, 4 / settings.speed);
                foreach (var key in mapped)
                {
                    double x = (key.x - minX) / Math.Max(1, maxX - minX), y = (key.y - minY) / Math.Max(1, maxY - minY); RGB color = RGB.Black;
                    switch (settings.effect)
                    {
                        case "starlight": case "rainbowStarlight":
                            double moment = Wrapped(clock, 8 / settings.speed) * 8, tick = Math.Floor(moment), progress = moment - tick;
                            double seed = Noise(key.index * 13.31 + tick * 71.9), glow = seed > .80 ? Math.Pow(Math.Sin(Math.PI * progress), 2) : 0;
                            color = settings.effect == "starlight" ? Scale(settings.color, glow * settings.intensity) : HueColor(Noise(key.index * 5.17 + tick * 3.77), glow * settings.intensity); break;
                        case "fire":
                            double flicker = Noise(key.index * 7.11 + Math.Floor(Wrapped(clock, 16 / settings.speed) * 32) * 23.3), flame = Math.Max(.08, .85 - y * .52 + flicker * .38);
                            color = HueColor(.005 + (1 - y) * .09 + flicker * .025, flame * settings.intensity); break;
                        case "colorWheel": color = HueColor(Math.Atan2(y - .5, x - .5) / (2 * Math.PI) + movement, settings.intensity); break;
                        case "scanner": double distance = Math.Abs(x - (1 - Math.Abs(2 * movement - 1))); color = Scale(settings.color, Math.Exp(-distance * distance / .003) * settings.intensity); break;
                        case "comet": double tail = movement * 1.3 - .15 - x; color = Scale(settings.color, (tail < 0 ? Math.Exp(-Math.Pow(tail / .025, 2)) : Math.Exp(-tail / .12)) * settings.intensity); break;
                        case "rain": double drop = Wrapped(Wrapped(clock, 3 / settings.speed) + Noise(Math.Floor(key.x * 1.6) * 12.7), 1), delta = Math.Abs(y - drop); color = Scale(settings.color, Math.Exp(-Math.Pow(Math.Min(delta, 1 - delta) / .10, 2)) * settings.intensity); break;
                        case "aurora": double fold = Math.Sin(x * 13 + movement * 4 * Math.PI + y * 3), band = Math.Exp(-Math.Pow((y - .48 - .22 * fold) / .28, 2)); color = HueColor(.38 + .12 * Math.Sin(x * 6 - movement * 2 * Math.PI), (.08 + .92 * band) * settings.intensity); break;
                    }
                    frame[key.index] = color;
                }
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
                    if (settings.effect == "reactive" || settings.effect == "rainbowReactive")
                    {
                        if ((!reactiveAffectsAllKeys && key.id != pulse.origin.id) || pulse.age >= 1.4) continue;
                        double remaining = 1 - pulse.age / 1.4, contribution = remaining * remaining; level += contribution;
                        if (settings.effect == "rainbowReactive") {
                            RGB color = HueColor(pulse.origin.index * .618 + pulse.age * .4, 1);
                            red += color.r * contribution; green += color.g * contribution; blue += color.b * contribution;
                        }
                    }
                    else
                    {
                        double dx = Math.Abs(key.x - pulse.origin.x), dy = Math.Abs(key.y - pulse.origin.y);
                        double distance = Distance(dx, dy), reach = pulse.reach;
                        if (settings.effect == "rowWave") { distance = dx; reach = mapped.Max(x => Math.Abs(x.x - pulse.origin.x)); }
                        if (settings.effect == "columnWave") { distance = dy; reach = mapped.Max(x => Math.Abs(x.y - pulse.origin.y)); }
                        if (settings.effect == "crossRipple") { if (Math.Min(dx, dy) > .75) continue; distance = Math.Max(dx, dy); reach = mapped.Max(x => Math.Max(Math.Abs(x.x - pulse.origin.x), Math.Abs(x.y - pulse.origin.y))); }
                        double radius = pulse.age * (settings.effect == "splash" ? 6 : 8);
                        double width = 0.6 + radius * 0.045, offset = (settings.effect == "splash" ? Math.Max(0, distance - radius) : distance - radius) / width;
                        double travelFade = 1 - 0.2 * Math.Min(1, radius / Math.Max(1, reach));
                        double exitFade = Math.Max(0, 1 - Math.Max(0, radius - reach) / (width * 3));
                        double contribution = Math.Exp(-0.5 * offset * offset) * travelFade * exitFade * exitFade;
                        level += contribution;
                        if (settings.effect == "rainbowRipple")
                        {
                            RGB color = HueColor(Math.Atan2(key.y - pulse.origin.y, key.x - pulse.origin.x) / (2 * Math.PI) + pulse.age * 0.4, 1);
                            red += color.r * contribution; green += color.g * contribution; blue += color.b * contribution;
                        }
                    }
                }
                if (settings.effect == "rainbowRipple" || settings.effect == "rainbowReactive")
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
        private static double Noise(double seed) { double value = Math.Sin(seed * 12.9898) * 43758.5453; return value - Math.Floor(value); }
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
