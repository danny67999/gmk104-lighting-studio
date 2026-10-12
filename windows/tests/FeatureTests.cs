using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading;
using System.Web.Script.Serialization;

namespace Gmk104LightingStudio
{
    internal static class FeatureTests
    {
        private static int count;
        private static void Check(bool value, string name) { count++; if (!value) throw new Exception(name); }
        public static int Main(string[] args)
        {
            try
            {
                if (args.Contains("--sensor-probe"))
                {
                    using (var native = new NativeLightingInputs())
                    {
                        native.RefreshTemperature();
                        for (int i = 0; i < 40; i++)
                        {
                            double now = NativeLightingInputs.MonotonicTime; var inputs = native.Snapshot(now);
                            if (inputs.Temperature(now).HasValue)
                            {
                                var frame = LightingEngine.RenderEffect(new LightingSettings { effect = "cpuTemperature" }, null, null, null, now, false, inputs);
                                Check(frame.Any(c => c != RGB.Black), "Live CPU temperature renders a colored frame");
                                Console.WriteLine(native.TemperatureStatus + "; rendered color " + frame[0] + "; no keyboard writes."); return 0;
                            }
                            Thread.Sleep(100);
                        }
                        throw new Exception(native.TemperatureStatus);
                    }
                }
                Radar(); Sensors(); PresetsAndNames();
                Console.WriteLine("FEATURE TESTS PASS: " + count + " radar, sensor-log, preset and layer-name checks."); return 0;
            }
            catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
        }
        private static void Radar()
        {
            var keys = new[] {
                new KeyGeometry { id = "E", x = 2, y = 0, width = 1, height = 1 },
                new KeyGeometry { id = "S", x = 0, y = 2, width = 1, height = 1 },
                new KeyGeometry { id = "W", x = -2, y = 0, width = 1, height = 1 },
                new KeyGeometry { id = "N", x = 0, y = -2, width = 1, height = 1 } };
            var map = new MappingFile { mappings = keys.Select((k, i) => new MappingEntry(k.id, i, true)).ToList() };
            var settings = new LightingSettings { effect = "radar", color = new RGB(20, 255, 80) };
            Func<double, RGB[]> render = t => LightingEngine.RenderEffect(settings, keys, map, null, t);
            Check(LightingEngine.RequiresMapping("radar") && !LightingEngine.RequiresKeyPresses("radar"), "Radar needs mapping but not keys");
            for (int i = 0; i < 4; i++) Check(render(i)[i] == settings.color, "Clockwise radar reaches quadrant " + i);
            Check(render(0).SequenceEqual(render(4)), "Radar repeats seamlessly at four seconds");
            Check(render(0)[3].g > render(0)[1].g, "Trail follows behind the sweep");
            var quarter = render(1); settings.speed = 2; Check(render(0.5).SequenceEqual(quarter), "Radar speed scales rotation");
            settings.intensity = 0; Check(render(1).All(c => c == RGB.Black), "Zero intensity"); settings.intensity = 1;
            map.mappings[0].confirmed = false; Check(render(0)[0] == RGB.Black, "Unconfirmed LED excluded"); map.mappings[0].confirmed = true;
            var layer = new LightingLayer(settings) { keyIDs = new List<string> { "E" } };
            var mask = LightingEngine.Render(new List<LightingLayer> { layer }, keys, map, null, 0);
            Check(mask[0] != RGB.Black && mask.Skip(1).All(c => c == RGB.Black), "Radar respects key masks");
            Check(LightingEngine.RenderEffect(settings, keys, null, null, 0).All(c => c == RGB.Black), "No map means no guessed LED positions");
        }
        private static void Sensors()
        {
            var now = DateTime.UtcNow; string stamp = now.ToLocalTime().ToString("MM/dd/yyyy HH:mm:ss", CultureInfo.InvariantCulture);
            string header = ",/amdcpu/0/temperature/2,/intelcpu/0/temperature/0,/nvidiagpu/0/temperature/0,/amdcpu/0/load/0";
            var sample = CpuSensorLog.Parse(header, stamp + ",61.5,72.25,99,100", now);
            Check(sample.Values.SequenceEqual(new[] { 61.5, 72.25 }), "Only CPU temperature identifiers accepted");
            Check(CpuSensorLog.Parse(header, stamp + ",61.5,72.25,99,100", now.AddSeconds(6)) == null, "Stale log expires");
            Check(CpuSensorLog.Parse(header, stamp + ",61.5,72.25,99,100", now.AddSeconds(-2)) == null, "Future timestamp rejected");
            Check(CpuSensorLog.Parse(header, stamp + ",NaN,Infinity,99,100", now) == null, "Nonfinite readings rejected");
            Check(CpuSensorLog.Parse(header, stamp + ",-1,126,99,100", now) == null, "Implausible readings rejected");
            Check(CpuSensorLog.Parse(header, stamp + ",61.5", now) == null, "Partial row rejected");
            Check(CpuSensorLog.Parse(header, "Time,CPU,CPU,GPU,Load", now) == null, "Label row rejected");
            string path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, Guid.NewGuid().ToString("N") + ".csv");
            try
            {
                string row = stamp + ",61.5,72.25,99,100\r\n";
                File.WriteAllText(path, header + "\r\nTime,CPU,CPU,GPU,Load\r\n" + String.Concat(Enumerable.Repeat(row, 3000)) + "incomplete");
                Check(CpuSensorLog.ReadFile(path, now).Values.Max() == 72.25, "Bounded tail reader ignores incomplete append");
            }
            finally { if (File.Exists(path)) File.Delete(path); }
            Check(CpuSensorLog.SetupHelp.Contains("PawnIO") && CpuSensorLog.SetupHelp.Contains("separate sensor provider"), "Dependency guidance is explicit");
        }
        private static void PresetsAndNames()
        {
            var keys = new JavaScriptSerializer().Deserialize<KeyGeometry[]>(File.ReadAllText("windows/Resources/layout.json"));
            foreach (string name in LightingPresets.Names)
            {
                var profile = LightingPresets.Create(name); profile.Validate(keys);
                Check(!profile.resume && profile.mode == "studio" && profile.layers.Count >= 2, "Preset loads paused: " + name);
                var copy = LightingPresets.Create(name); RGB original = copy.layers[0].settings.color;
                profile.layers[0].settings.color = new RGB(1, 2, 3);
                Check(copy.layers[0].settings.color == original && !Object.ReferenceEquals(copy.layers[0].settings, profile.layers[0].settings), "Preset instance isolation: " + name);
                string path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, Guid.NewGuid().ToString("N") + ".json");
                try { copy.Save(path); var imported = LightingProfile.Load(path); imported.Validate(keys); Check(new JavaScriptSerializer().Serialize(copy) == new JavaScriptSerializer().Serialize(imported), "Preset JSON round trip: " + name); }
                finally { if (File.Exists(path)) File.Delete(path); }
            }
            var layers = new List<LightingLayer> { new LightingLayer { name = "Static color 1" }, new LightingLayer { name = "Static color 2" } };
            Check(LayerNames.Next("staticColor", layers) == "Static color 3", "Names avoid collisions");
            Check(LayerNames.Next("staticColor", layers, layers[0]) == "Static color 1", "Current layer excluded");
            Check(LayerNames.IsAutomatic("Static color", "staticColor") && LayerNames.IsAutomatic("Static color 12", "staticColor"), "Legacy and numbered names recognized");
            Check(!LayerNames.IsAutomatic("My orange keys", "staticColor"), "Custom names preserved");
        }
    }
}
