using System;
using System.Collections.Generic;
using System.IO;

namespace Gmk104LightingStudio
{
    internal static class LightingPresets
    {
        internal static readonly string[] Names = { "Neon Circuit", "Matrix Overdrive", "Crystal Storm", "Solar Forge", "Prism Arcade", "Matrix Terminal", "Arctic Ripple", "Ember Glow", "Synthwave", "Rainbow Party", "Neon Radar", "Violet Radar" };
        private static LightingLayer Layer(string effect, RGB color, double intensity, double speed)
        {
            return new LightingLayer(new LightingSettings { effect = effect, color = color, intensity = intensity, speed = speed }) { affectAllKeys = true };
        }
        internal static LightingProfile Create(string name)
        {
            string bundled=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Profiles",name+".json");
            if(File.Exists(bundled)) return LightingProfile.Load(bundled);
            var p = new LightingProfile { resume = false, frameRate = 30, layers = new List<LightingLayer>() };
            switch (name)
            {
                case "Neon Radar":
                    p.layers.Add(Layer("radar", new RGB(20, 255, 100), 1, 0.75));
                    p.layers.Add(Layer("staticColor", new RGB(0, 25, 8), 1, 1)); break;
                case "Arctic Ripple":
                    p.layers.Add(Layer("ripple", new RGB(100, 220, 255), 1, 0.75));
                    p.layers.Add(Layer("staticColor", new RGB(0, 8, 30), 1, 1)); break;
                case "Ember Glow":
                    p.layers.Add(Layer("reactive", new RGB(255, 140, 15), 1, 0.75));
                    p.layers[0].affectAllKeys = false;
                    p.layers.Add(Layer("breathing", new RGB(255, 35, 0), 0.3, 0.5)); break;
                case "Synthwave":
                    var wasd = Layer("staticColor", new RGB(0, 255, 220), 0.8, 1);
                    wasd.keyIDs = new List<string> { "KeyW", "KeyA", "KeyS", "KeyD" }; wasd.affectAllKeys = false;
                    p.layers.Add(wasd); p.layers.Add(Layer("breathing", new RGB(255, 0, 150), 0.5, 0.5)); break;
                case "Violet Radar":
                    p.layers.Add(Layer("radar", new RGB(190, 60, 255), 1, 1.25));
                    p.layers.Add(Layer("staticColor", new RGB(8, 0, 22), 1, 1)); break;
                default: throw new ArgumentException("Unknown lighting preset.");
            }
            foreach (var layer in p.layers) layer.name = LayerNames.Next(layer.settings.effect, p.layers, layer);
            p.settings = p.layers[0].settings.Clone(); p.Validate(); return p;
        }
    }
}
