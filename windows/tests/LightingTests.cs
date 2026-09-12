using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Web.Script.Serialization;

namespace Gmk104LightingStudio
{
    public static class LightingTests
    {
        private static int checks;
        private static void Check(bool condition, string name) { checks++; if (!condition) throw new Exception("FAILED: " + name); }
        private static void Reject(Action action, string name) { try { action(); } catch { checks++; return; } throw new Exception("FAILED: accepted " + name); }
        private static bool Same(RGB[] a, RGB[] b) { return a.SequenceEqual(b); }
        private static bool Black(RGB[] frame) { return frame.All(x => x.Equals(RGB.Black)); }
        private static KeyGeometry Key(string id, double x) { return new KeyGeometry { id = id, label = id, x = x, width = 1, height = 1 }; }
        private static LightingLayer Layer(string effect, RGB color) { return new LightingLayer(new LightingSettings { effect = effect, color = color }); }
        public static int Main(string[] args)
        {
            try { Run(args.Length == 0 ? Path.Combine("windows", "Resources") : args[0]); return 0; }
            catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        }
        public static void Run(string resources)
        {
            var keys = new JavaScriptSerializer().Deserialize<KeyGeometry[]>(File.ReadAllText(Path.Combine(resources, "layout.json")));
            var mapping = MappingFile.Load(Path.Combine(resources, "default-led-map.json")); mapping.Validate(keys);
            BasicEffects(); Composition(); ReachAndBluetooth(keys, mapping); Inputs(keys, mapping); Persistence(keys, mapping);
            Console.WriteLine("PASS: " + checks + " lighting, mapping, Mac profile, input freshness and slow-Bluetooth checks.");
        }
        private static void BasicEffects()
        {
            var keys = new[] { Key("A", 0), Key("B", 2), Key("C", 6), Key("Unknown", 1) };
            var mapping = new MappingFile { mappings = new List<MappingEntry> { new MappingEntry("A", 7, true), new MappingEntry("B", 42, true), new MappingEntry("C", 103, true), new MappingEntry("Unknown", 8, false) } };
            var color = new RGB(255, 80, 40); var settings = new LightingSettings { effect = "ripple", color = color };
            var pulses = new List<KeyPulse> { new KeyPulse("A", 10) };
            Func<double, RGB[]> render = time => LightingEngine.RenderEffect(settings, keys, mapping, pulses, time);
            Check(render(10)[7] == color && render(10)[42].r < 5, "ripple starts at key center");
            var expanding = render(10.25);
            Check(expanding[42].r > 200 && expanding[7].r < 10 && expanding[103] == RGB.Black, "ripple expands spatially");
            Check(render(10.75)[103].r > 120 && Black(render(13.5)), "ripple reaches and expires");
            Check(render(10)[8] == RGB.Black && expanding[8] == RGB.Black, "unconfirmed keys remain black");
            Check(Black(render(9)) && Black(render(Double.PositiveInfinity)), "invalid/future time suppressed");
            Check(Black(LightingEngine.RenderEffect(settings, keys, mapping, new List<KeyPulse> { new KeyPulse("Unknown", 10) }, 10)), "unconfirmed trigger ignored");
            settings.speed = 2; Check(Same(render(10.125), expanding), "speed scales propagation"); settings.speed = 1;
            settings.effect = "reactive";
            Check(render(10)[7] == color && render(10)[42] == RGB.Black && render(10.7)[7].r == 64 && Black(render(11.5)), "reactive local decay");
            settings.effect = "wave"; Check(render(1)[7] != render(1)[42] && render(1)[7] != render(2)[7], "wave changes in space and time");
            mapping.mappings.Add(new MappingEntry("Duplicate", 7, false)); Check(render(1)[7] == RGB.Black, "duplicate LED excluded even if unconfirmed"); mapping.mappings.RemoveAt(4);
            mapping.mappings.Add(new MappingEntry("A", 9, true)); Check(render(1)[7] == RGB.Black && render(1)[9] == RGB.Black, "duplicate physical key excluded"); mapping.mappings.RemoveAt(4);
            settings.effect = "staticColor"; settings.intensity = 0.5;
            Check(render(0).All(x => x == new RGB(128, 40, 20)), "intensity byte rounding");
            settings.brightness = 1; var dim = render(0); settings.brightness = 4; Check(Same(dim, render(0)), "hardware brightness is never applied twice");
            foreach (var effect in LightingEngine.Effects)
            {
                settings.effect = effect; settings.intensity = 1; Check(render(Double.MaxValue).Length == 104, effect + " finite frame size");
                settings.intensity = 0; Check(Black(render(1)), effect + " zero intensity");
            }
            foreach (double speed in new[] { 0.0, 4.0, Double.NaN, Double.PositiveInfinity })
            {
                settings = new LightingSettings { speed = speed }; Reject(settings.Validate, "invalid speed"); Check(LightingEngine.InRange(settings.Normalized().speed, 0.25, 3), "speed normalization");
            }
        }
        private static void Composition()
        {
            var keys = new[] { Key("A", 0), Key("B", 2), Key("C", 6) };
            var mapping = new MappingFile { mappings = new List<MappingEntry> { new MappingEntry("A", 7, true), new MappingEntry("B", 42, true), new MappingEntry("C", 103, true) } };
            var red = new RGB(240, 0, 0); var blue = new RGB(0, 0, 200);
            var bottom = Layer("staticColor", blue); var top = Layer("staticColor", red);
            var none = new List<KeyPulse>(); var pressA = new List<KeyPulse> { new KeyPulse("A", 10) }; var pressB = new List<KeyPulse> { new KeyPulse("B", 10) };
            Func<List<KeyPulse>, double, RGB[]> render = (pulses, time) => LightingEngine.Render(new List<LightingLayer> { top, bottom }, keys, mapping, pulses, time);
            Check(render(none, 10).All(x => x == red), "topmost layer first");
            top.opacity = 0.5; Check(render(none, 10)[7] == new RGB(120, 0, 100), "normal opacity");
            top.blendMode = "additive"; Check(render(none, 10)[7] == new RGB(120, 0, 200), "additive opacity");
            top.opacity = 1; top.settings.color = new RGB(240, 0, 200); Check(render(none, 10)[7] == new RGB(240, 0, 255), "additive saturation");
            top.blendMode = "normal"; top.settings.color = RGB.Black; Check(Black(render(none, 10)), "static black is opaque");
            top.settings.color = red; top.keyIDs = new List<string> { "A" }; Check(render(none, 10)[7] == red && render(none, 10)[42] == blue, "selected output mask");
            top.keyIDs.Clear(); top.affectAllKeys = true; Check(render(pressA, 10).All(x => x == blue), "empty selection never means all");
            top.keyIDs = new List<string> { "Missing" }; top.affectAllKeys = false; Check(render(none, 10).All(x => x == blue), "unknown mask cannot guess LEDs"); Reject(() => top.Validate(keys), "unknown selected key");
            top.keyIDs = null; top.settings.effect = "reactive";
            Check(render(none, 10).All(x => x == blue), "idle reactive layer transparent");
            Check(render(pressA, 10)[7] == red && render(pressA, 10)[42] == blue, "reactive coverage independent of hue");
            Check(render(pressA, 10.7)[7] == new RGB(60, 0, 150), "faded coverage reveals background");
            top.settings.effect = "ripple"; top.keyIDs = new List<string> { "A" }; top.affectAllKeys = true;
            Check(render(pressA, 10.25)[42].r > 190 && render(pressA, 10.75)[103].r > 120, "selected trigger affects all output keys");
            Check(render(pressB, 10.25).All(x => x == blue), "affect all does not widen trigger mask");
            var second = top.Clone(); second.id = Guid.NewGuid().ToString(); second.keyIDs = new List<string> { "B" }; second.settings.color = new RGB(0, 240, 0); second.blendMode = "additive";
            var onlyA = LightingEngine.Render(new List<LightingLayer> { second, top }, keys, mapping, pressA, 10.25);
            var onlyB = LightingEngine.Render(new List<LightingLayer> { second, top }, keys, mapping, pressB, 10.25);
            Check(onlyA[42].r > 190 && onlyA.All(x => x.g == 0) && onlyB[7].g > 190 && onlyB.All(x => x.r == 0), "independent per-layer trigger masks");
            top.settings.effect = "rainbowRipple"; top.keyIDs = null;
            var mixedPulses = new List<KeyPulse> { new KeyPulse("A", 10), new KeyPulse("B", 10.1) };
            var rgb = LightingEngine.RenderEffect(top.settings, keys, mapping, mixedPulses, 10.25);
            var white = top.settings.Clone(); white.effect = "ripple"; white.color = new RGB(255, 255, 255);
            var coverage = LightingEngine.RenderEffect(white, keys, mapping, mixedPulses, 10.25); var result = render(mixedPulses, 10.25);
            Check(result.Select((x, i) => x.b == (byte)Math.Min(255, Math.Round(blue.b * (1 - coverage[i].r / 255.0) + rgb[i].b, MidpointRounding.AwayFromZero))).All(x => x), "rainbow overlap uses white coverage envelope");
            foreach (var effect in LightingEngine.Effects)
            {
                top.settings.effect = effect;
                Check(Same(LightingEngine.Render(new List<LightingLayer> { top }, keys, mapping, pressA, 10), LightingEngine.RenderEffect(top.settings, keys, mapping, pressA, 10, true)), "single layer preserves " + effect);
            }
        }
        private static void ReachAndBluetooth(KeyGeometry[] keys, MappingFile mapping)
        {
            foreach (var effect in new[] { "ripple", "rainbowRipple" }) foreach (var originID in new[] { "Escape", "KeyA", "NumpadEnter" }) foreach (double speed in new[] { 0.25, 1, 3 })
            {
                var origin = keys.First(x => x.id == originID); var layer = Layer(effect, new RGB(255, 255, 255)); layer.settings.speed = speed;
                layer.keyIDs = new List<string> { originID }; layer.affectAllKeys = true;
                var pulses = new List<KeyPulse> { new KeyPulse(originID, 100) };
                foreach (var key in keys)
                {
                    double dx = key.x + key.width / 2 - origin.x - origin.width / 2, dy = key.y + key.height / 2 - origin.y - origin.height / 2;
                    var frame = LightingEngine.Render(new List<LightingLayer> { layer }, keys, mapping, pulses, 100 + Math.Sqrt(dx * dx + dy * dy) / (8 * speed));
                    int index = mapping.mappings.First(x => x.keyId == key.id).ledIndex.Value;
                    Check(LightingEngine.Peak(frame[index]) >= 200, effect + " reaches " + key.id + " from " + originID + " at " + speed);
                }
                Check(Black(LightingEngine.Render(new List<LightingLayer> { layer }, keys, mapping, pulses, 100 + 4.5 / speed)), "pulse expires");
            }
            foreach (double speed in new[] { 0.25, 1, 3 })
            {
                var layer = Layer("rainbowRipple", RGB.Black); layer.settings.speed = speed; layer.keyIDs = new List<string> { "KeyW" }; layer.affectAllKeys = true;
                var pulses = new List<KeyPulse> { new KeyPulse("KeyW", 100) }; double previous = 100; var visited = new HashSet<int>(); RGB[] last = null;
                for (int step = 1; step <= 55; step++)
                {
                    double current = previous + (step % 10 == 0 ? 5 : 1);
                    pulses = LightingEngine.AdjustPulses(pulses, previous, current, 0.1 / speed);
                    last = LightingEngine.Render(new List<LightingLayer> { layer }, keys, mapping, pulses, current);
                    for (int i = 0; i < 104; i++) if (LightingEngine.Peak(last[i]) > 50) visited.Add(i);
                    previous = current;
                }
                Check(visited.Count == 104 && Black(last), "slow Bluetooth visits 104 LEDs then expires at speed " + speed);
            }
            Check(LightingEngine.AdjustPulses(new List<KeyPulse> { new KeyPulse("KeyW", 104.9) }, 100, 105, 0.1)[0].time == 105, "new press begins at zero age after blocked frame");
        }
        private static void Inputs(KeyGeometry[] keys, MappingFile mapping)
        {
            var inputs = new LightingInputs { music = new MusicSample { bass = 0.9, mid = 0.6, treble = 0.3, level = 0.8, timestamp = 100 } };
            var music = Layer("adaptiveMusic", RGB.Black); music.keyIDs = new List<string> { "KeyA" };
            var layers = new List<LightingLayer> { music }; var pulses = new List<KeyPulse>();
            Check(LightingEngine.Render(layers, keys, mapping, pulses, 100.1, inputs).Count(x => x != RGB.Black) <= 1, "music respects key mask");
            music.affectAllKeys = true; Check(LightingEngine.Render(layers, keys, mapping, pulses, 100.1, inputs).Count(x => x != RGB.Black) > 50, "music covers full keyboard");
            Check(Black(LightingEngine.Render(layers, keys, mapping, pulses, 101, inputs)), "stale music does not freeze effect");
            var temperature = new LightingSettings { effect = "cpuTemperature" };
            foreach (var pair in new[] { new { t = 40.0, color = new RGB(0, 0, 255) }, new { t = 65.0, color = new RGB(0, 255, 0) }, new { t = 90.0, color = new RGB(255, 0, 0) } })
            {
                inputs.cpuCelsius = pair.t; inputs.temperatureTime = 100;
                Check(LightingEngine.RenderEffect(temperature, keys, mapping, pulses, 100, false, inputs).All(x => x == pair.color), "CPU color at " + pair.t);
            }
            Check(Black(LightingEngine.RenderEffect(temperature, keys, mapping, pulses, 106, false, inputs)), "stale CPU measurement expires");
            inputs.cpuCelsius = Double.NaN; Check(Black(LightingEngine.RenderEffect(temperature, keys, mapping, pulses, 100, false, inputs)), "invalid CPU measurement ignored");
        }
        private static void Persistence(KeyGeometry[] keys, MappingFile mapping)
        {
            string directory = Path.Combine(Path.GetTempPath(), "GMK104-lighting-tests-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory); string path = Path.Combine(directory, "profile.json"), mapPath = Path.Combine(directory, "map.json");
            var serializer = new JavaScriptSerializer();
            try
            {
                Check(LightingProfile.Load(path) == null && !File.Exists(path), "missing profile is read-only");
                var layer = Layer("rainbowRipple", new RGB(30, 160, 240)); layer.name = "WASD ripple"; layer.keyIDs = new List<string> { "KeyW", "KeyA", "KeyS", "KeyD" }; layer.affectAllKeys = true; layer.opacity = 0.65;
                foreach (string mode in new[] { "studio", "builtIn", "frame" }) foreach (bool restore in new[] { false, true }) foreach (bool resume in new[] { false, true })
                {
                    var profile = new LightingProfile { mode = mode, settings = layer.settings.Clone(), builtInEffect = 18, layers = new List<LightingLayer> { layer.Clone() },
                        colors = mode == "frame" ? Enumerable.Range(0, 104).Select(i => new RGB((byte)i, (byte)(255 - i), (byte)(i * 2))).ToArray() : null,
                        restoreOnReconnect = restore, resume = resume, frameRate = 60 };
                    profile.Save(path); var loaded = LightingProfile.Load(path); loaded.Validate(keys);
                    Check(serializer.Serialize(profile) == serializer.Serialize(loaded), mode + " Mac schema roundtrip with restore/resume flags");
                }
                var valid = new LightingProfile { layers = new List<LightingLayer> { layer.Clone() } }; valid.Save(path); string original = File.ReadAllText(path);
                var bad = valid.Clone(); bad.version = 3; Reject(() => bad.Save(path), "invalid profile save"); Check(File.ReadAllText(path) == original, "failed validation preserves existing profile");
                var invalidCases = new List<LightingProfile>();
                bad = valid.Clone(); bad.version = 3; invalidCases.Add(bad);
                bad = valid.Clone(); bad.mode = "invalid"; invalidCases.Add(bad);
                bad = valid.Clone(); bad.settings.speed = 4; invalidCases.Add(bad);
                bad = valid.Clone(); bad.frameRate = 20; invalidCases.Add(bad);
                bad = valid.Clone(); bad.settings.brightness = 5; invalidCases.Add(bad);
                bad = valid.Clone(); bad.builtInEffect = 19; invalidCases.Add(bad);
                bad = valid.Clone(); bad.mode = "frame"; bad.colors = new RGB[103]; invalidCases.Add(bad);
                bad = valid.Clone(); bad.layers = null; invalidCases.Add(bad);
                bad = valid.Clone(); bad.layers.Clear(); invalidCases.Add(bad);
                bad = valid.Clone(); bad.layers.Add(bad.layers[0].Clone()); invalidCases.Add(bad);
                bad = valid.Clone(); bad.layers[0].opacity = 1.1; invalidCases.Add(bad);
                bad = valid.Clone(); bad.layers[0].keyIDs.Add("KeyW"); invalidCases.Add(bad);
                bad = valid.Clone(); bad.layers[0].settings.effect = "unknown"; invalidCases.Add(bad);
                foreach (var invalid in invalidCases) { File.WriteAllText(path, serializer.Serialize(invalid)); Reject(() => LightingProfile.Load(path), "invalid persisted profile"); }
                var legacy = valid.Clone(); legacy.version = 1; legacy.layers = null; File.WriteAllText(path, serializer.Serialize(legacy)); original = File.ReadAllText(path);
                var migrated = LightingProfile.Load(path); Check(migrated.StudioLayers.Count == 1 && migrated.StudioLayers[0].id == migrated.StudioLayers[0].id && File.ReadAllText(path) == original, "legacy layer identity stable without rewrite");
                var json = (Dictionary<string, object>)serializer.DeserializeObject(serializer.Serialize(valid));
                var jLayer = (Dictionary<string, object>)((object[])json["layers"])[0]; jLayer.Remove("affectAllKeys");
                var jSettings = (Dictionary<string, object>)jLayer["settings"]; jSettings.Remove("musicSensitivity"); jSettings.Remove("temperatureCold"); jSettings.Remove("temperatureHot");
                File.WriteAllText(path, serializer.Serialize(json)); var old = LightingProfile.Load(path);
                Check(!old.layers[0].affectAllKeys && old.layers[0].settings.musicSensitivity == 1 && old.layers[0].settings.temperatureCold == 40 && old.layers[0].settings.temperatureHot == 90, "optional Mac fields migrate with exact defaults");
                json.Remove("settings"); File.WriteAllText(path, serializer.Serialize(json)); Reject(() => LightingProfile.Load(path), "missing required settings");
                File.WriteAllText(path, "{\"version\":"); Reject(() => LightingProfile.Load(path), "truncated JSON");
                mapping.Save(mapPath, keys); var loadedMap = MappingFile.Load(mapPath); loadedMap.Validate(keys); Check(serializer.Serialize(loadedMap) == serializer.Serialize(mapping), "mapping roundtrip");
                var reassigned = mapping.Clone(); string oldKey = reassigned.mappings.First(x => x.ledIndex == 0).keyId;
                string otherKey = reassigned.mappings.First(x => x.ledIndex == 1).keyId; reassigned.Assign(otherKey, 0); reassigned.Validate(keys);
                Check(reassigned.mappings.Single(x => x.keyId == oldKey).ledIndex == null && reassigned.mappings.Single(x => x.keyId == otherKey).ledIndex == 0, "assignment clears prior owner without duplicates");
                var duplicate = mapping.Clone(); duplicate.mappings[1].ledIndex = duplicate.mappings[0].ledIndex; Reject(() => duplicate.Validate(keys), "duplicate LED mapping");
                duplicate = mapping.Clone(); duplicate.mappings[1].keyId = duplicate.mappings[0].keyId; Reject(() => duplicate.Validate(keys), "duplicate physical key");
                var row = MappingFile.RowOrder(keys); Check(row.mappings.First().keyId == "Escape", "row-order mapping begins at Escape");
                Check(row.mappings.First(x => x.keyId == "NumpadEnter").ledIndex == mapping.mappings.First(x => x.keyId == "NumpadEnter").ledIndex, "tall numpad keys use lower LED row");
            }
            finally
            {
                if (File.Exists(path)) File.Delete(path); if (File.Exists(mapPath)) File.Delete(mapPath);
                Directory.Delete(directory);
            }
        }
    }
}
