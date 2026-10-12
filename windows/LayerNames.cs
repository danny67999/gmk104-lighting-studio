using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace Gmk104LightingStudio
{
    internal static class LayerNames
    {
        internal static bool IsAutomatic(string name, string effect)
        {
            string label = LightingEngine.DisplayName(effect);
            return String.Equals(name, label, StringComparison.OrdinalIgnoreCase) || Regex.IsMatch(name ?? "", "^" + Regex.Escape(label) + @" [1-9][0-9]*$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        }
        internal static string Next(string effect, IEnumerable<LightingLayer> layers, LightingLayer except = null)
        {
            var used = new HashSet<string>(layers.Where(l => !Object.ReferenceEquals(l, except)).Select(l => l.name), StringComparer.OrdinalIgnoreCase);
            string label = LightingEngine.DisplayName(effect); int n = 1;
            while (used.Contains(label + " " + n)) n++;
            return label + " " + n;
        }
    }
}
