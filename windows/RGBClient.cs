using System;
using System.Collections.Generic;
using System.Linq;

namespace Gmk104LightingStudio
{
    public sealed class RGBState
    {
        public int Index, Effect, Brightness;
        public RGB Color;
        public ushort Checksum;
        internal bool Same(RGBState other) { return other != null && Index == other.Index && Effect == other.Effect && Brightness == other.Brightness && Color.Equals(other.Color) && Checksum == other.Checksum; }
    }

    public sealed class LightingVerificationException : Exception
    {
        public LightingVerificationException(string message) : base(message) { }
    }

    // All public operations are serialized, including the gate and their complete readback.
    public sealed class RGBClient : IDisposable
    {
        private readonly object sync = new object();
        private RGB[] shadow;
        private bool animationBaseline, disposed;
        private int animationSequence;
        private readonly HashSet<int> indicatorOverrides = new HashSet<int>();
        private static readonly int[] Indicators = { 14, 33, 57, 91 };
        private static readonly byte[] Signature = { 8, 3, 5, 2, 104, 9, 15, 71, 77, 75, 2 };
        public IReportTransport Transport { get; private set; }
        public RGB[] Shadow { get { lock (sync) { return shadow == null ? null : (RGB[])shadow.Clone(); } } }
        public RGBClient(IReportTransport transport) { if (transport == null) throw new ArgumentNullException("transport"); Transport = transport; }
        private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
        private static void Verify(bool condition, string message) { if (!condition) throw new LightingVerificationException(message); }
        private void Available() { if (disposed) throw new ObjectDisposedException("RGBClient"); }
        private static void ValidIndex(int i) { Require(i >= 0 && i < 104, "LED index must be 0–103."); }
        private static RGB[] Frame(RGB[] frame) { Require(frame != null && frame.Length == 104, "A frame requires exactly 104 colors."); return (RGB[])frame.Clone(); }
        public static ushort Sum(RGB[] frame) { int sum = 0; foreach (RGB c in frame) sum += c.r + c.g + c.b; return unchecked((ushort)sum); }
        internal static bool IndicatorOverride(int index, RGB actual, RGB expected) { return !actual.Equals(expected) && Array.IndexOf(Indicators, index) >= 0 && actual.Equals(new RGB(255, 255, 255)); }
        internal static RGBState Parse(byte[] p, int index)
        {
            Require(p != null && p.Length == 32, "Invalid lighting response length. Reconnect the keyboard.");
            Require(p.Take(11).SequenceEqual(Signature), "Compatible custom GMK104 firmware signature not found. Lighting controls are locked.");
            Require(p[11] == index, "The keyboard returned the wrong LED index.");
            Require(p[15] <= 19 && p[16] <= 4, "The keyboard returned invalid lighting settings.");
            return new RGBState { Index = index, Color = new RGB(p[12], p[13], p[14]), Effect = p[15], Brightness = p[16], Checksum = (ushort)(p[17] | p[18] << 8) };
        }
        public RGBState Read(int index = 0) { lock (sync) { Available(); ValidIndex(index); return Parse(Transport.Exchange(new byte[] { 8, 3, 5, (byte)index }), index); } }
        private RGBState Gate(bool visible = false) { Available(); Transport.CheckSingleDevice(); RGBState s = Read(); Require(!visible || s.Brightness > 0, "Brightness is zero. Apply brightness 1–4 before changing colors."); return s; }
        public RGB[] ReadFrame(RGB[] expected = null)
        {
            lock (sync)
            {
                Available(); if (expected != null) expected = Frame(expected);
                shadow = null; animationBaseline = false;
                RGBState first = Read(); Verify(first.Effect == 19, "A stable direct RGB frame is required.");
                RGB[] frame = new RGB[104]; frame[0] = first.Color;
                for (int i = 1; i < 104; i++) { RGBState s = Read(i); Verify(s.Effect == 19 && s.Brightness == first.Brightness && s.Checksum == first.Checksum, "The lighting changed during readback. Try the lighting action again."); frame[i] = s.Color; }
                Verify(Read().Same(first), "The lighting was not stable during readback.");
                Verify(Sum(frame) == first.Checksum, "The checksum did not match the 104 LED samples.");
                indicatorOverrides.Clear();
                if (expected != null) for (int i = 0; i < 104; i++) if (!frame[i].Equals(expected[i])) { Verify(IndicatorOverride(i, frame[i], expected[i]), "LED " + i + " did not match the requested color."); indicatorOverrides.Add(i); }
                shadow = frame; animationBaseline = true; return (RGB[])frame.Clone();
            }
        }
        private void WriteFrame(RGB[] frame) { shadow = null; animationBaseline = false; Transport.WriteFrame(frame); }
        public void SetFrame(RGB[] frame) { lock (sync) { RGB[] desired = Frame(frame); Gate(true); WriteFrame(desired); ReadFrame(desired); } }
        public void SetLED(int index, RGB color)
        {
            lock (sync)
            {
                ValidIndex(index); RGBState s = Gate(true); if (s.Effect == 19) ReadFrame();
                Require(shadow != null, "Choose Set all keys first to establish a complete direct RGB frame.");
                RGB[] desired = (RGB[])shadow.Clone(); desired[index] = color;
                if (s.Effect != 19) WriteFrame(desired);
                else { shadow = null; animationBaseline = false; Transport.Exchange(new byte[] { 7, 3, 5, (byte)index, 1, color.r, color.g, color.b }); }
                ReadFrame(desired);
            }
        }
        public void Clear() { lock (sync) { Gate(); shadow = null; animationBaseline = false; Transport.Exchange(new byte[] { 7, 3, 5, 0, 0 }); ReadFrame(new RGB[104]); } }
        public void SetBrightness(int value) { lock (sync) { Require(value >= 0 && value <= 4, "Brightness must be 0–4."); Gate(); animationBaseline = false; Transport.Exchange(new byte[] { 7, 3, 1, (byte)value }); Require(Read().Brightness == value, "Brightness readback did not match."); } }
        public void SetEffect(int value) { lock (sync) { Require(value >= 0 && value <= 18, "Built-in effect must be 0–18."); Gate(); animationBaseline = false; Transport.Exchange(new byte[] { 7, 3, 2, (byte)value }); Require(Read().Effect == value, "Effect readback did not match."); } }
        public int? ReadSleepSeconds()
        {
            lock (sync)
            {
                Available(); byte[] p = Transport.Exchange(new byte[] { 8, 3, 6, 1 });
                Require(p != null && p.Length == 32, "Invalid sleep-setting response length.");
                if (!p.Take(8).SequenceEqual(new byte[] { 8, 3, 6, 1, 71, 77, 75, 83 })) return null;
                Require(p.Skip(10).Take(6).SequenceEqual(new byte[] { 3, 3, 16, 14, 60, 0 }), "Unrecognized keyboard sleep capabilities.");
                int seconds = p[8] | p[9] << 8;
                Require(seconds == 0 || (seconds >= 60 && seconds <= 3600), "The keyboard returned an invalid sleep time."); return seconds;
            }
        }
        public void SetSleepSeconds(int seconds)
        {
            lock (sync) { Require(seconds == 0 || (seconds >= 60 && seconds <= 3600), "Sleep time must be 1–60 minutes or Never."); Gate(); Require(ReadSleepSeconds().HasValue, "Adjustable sleep requires custom firmware v0.3 or later."); Transport.Exchange(new byte[] { 7, 3, 6, 1, (byte)(seconds & 255), (byte)(seconds >> 8) }); Require(ReadSleepSeconds() == seconds, "The keyboard did not accept the sleep time."); }
        }
        public RGBState SetAnimationFrame(RGB[] frame, bool fullVerification = false)
        {
            lock (sync)
            {
                frame = Frame(frame); RGBState before = Gate(true); bool baseline = animationBaseline; WriteFrame(frame);
                if (fullVerification || !baseline || before.Effect != 19 || (!Transport.UsesRollingAnimationVerification && animationSequence % 30 == 0)) ReadFrame(frame);
                else if (Transport.UsesRollingAnimationVerification)
                {
                    RGBState first = Read(); RGB[] verified = (RGB[])frame.Clone(); indicatorOverrides.Clear();
                    if (first.Checksum != Sum(frame)) foreach (int i in Indicators)
                    {
                        RGBState s = Read(i); Verify(s.Effect == 19 && s.Brightness == before.Brightness && s.Checksum == first.Checksum, "Animation changed during status-light verification.");
                        if (IndicatorOverride(i, s.Color, frame[i])) { verified[i] = s.Color; indicatorOverrides.Add(i); }
                        else Verify(s.Color.Equals(frame[i]), "Animation status light did not match.");
                    }
                    Verify(first.Effect == 19 && first.Brightness == before.Brightness && first.Color.Equals(frame[0]) && first.Checksum == Sum(verified), "Animation checksum did not match. Playback stopped.");
                    int index = animationSequence % 52;
                    foreach (int i in new int[] { index, index + 52 }) { RGBState s = Read(i); Verify(s.Effect == 19 && s.Brightness == before.Brightness && s.Checksum == first.Checksum && s.Color.Equals(verified[i]), "Animation LED " + i + " did not match. Playback stopped."); }
                }
                else
                {
                    int index = animationSequence % 104; RGB[] verified = (RGB[])frame.Clone(); indicatorOverrides.Clear(); List<RGBState> samples = new List<RGBState>();
                    foreach (int i in Indicators.Concat(new int[] { index, (index + 52) % 104 }).Distinct().OrderBy(i => i))
                    {
                        RGBState s = Read(i); bool over = IndicatorOverride(i, s.Color, frame[i]);
                        Verify(s.Effect == 19 && s.Brightness == before.Brightness && (s.Color.Equals(frame[i]) || over), "Animation LED " + i + " did not match. Playback stopped.");
                        if (over) { verified[i] = s.Color; indicatorOverrides.Add(i); } samples.Add(s);
                    }
                    Verify(samples.All(s => s.Checksum == Sum(verified)), "Animation checksum did not match. Playback stopped.");
                    Verify(Read(samples[0].Index).Same(samples[0]), "Animation frame changed during verification.");
                }
                animationSequence = (animationSequence + 1) % 3120; shadow = null; animationBaseline = false;
                RGBState final = Read(); RGB[] finalFrame = (RGB[])frame.Clone(); foreach (int i in indicatorOverrides) finalFrame[i] = new RGB(255, 255, 255);
                Verify(final.Effect == 19 && final.Brightness == before.Brightness && final.Color.Equals(frame[0]) && final.Checksum == Sum(finalFrame), "Animation frame changed before completion. Playback stopped.");
                animationBaseline = true; return final;
            }
        }
        public void Dispose() { lock (sync) { if (disposed) return; disposed = true; shadow = null; Transport.Dispose(); } }
    }
}
