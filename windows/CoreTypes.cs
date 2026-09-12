using System;

namespace Gmk104LightingStudio
{
    public struct RGB : IEquatable<RGB>
    {
        public byte r;
        public byte g;
        public byte b;
        public RGB(byte red, byte green, byte blue) { r = red; g = green; b = blue; }
        public static readonly RGB Black = new RGB(0, 0, 0);
        public bool Equals(RGB other) { return r == other.r && g == other.g && b == other.b; }
        public override bool Equals(object other) { return other is RGB && Equals((RGB)other); }
        public override int GetHashCode() { return (r << 16) | (g << 8) | b; }
        public static bool operator ==(RGB a, RGB b) { return a.Equals(b); }
        public static bool operator !=(RGB a, RGB b) { return !a.Equals(b); }
        public override string ToString() { return String.Format("#{0:X2}{1:X2}{2:X2}", r, g, b); }
    }

    public sealed class KeyGeometry
    {
        public string id;
        public string label;
        public double x;
        public double y;
        public double width;
        public double height;
    }
}
