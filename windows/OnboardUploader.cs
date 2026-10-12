using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Threading;

namespace Gmk104LightingStudio
{
    public sealed class OnboardCapabilities
    {
        public bool Volatile, Persistent, ActivationPending;
        public int MaximumEffectId, MaximumLength, ChunkSize, ActiveLength;
        public uint ActiveCRC;
        internal byte Flags;
    }
    public sealed class OnboardReceipt
    {
        public int Length, Chunks; public uint CRC; public bool Persistent;
    }
    public sealed class OnboardUploader
    {
        private readonly IReportTransport transport; private readonly uint session;
        public OnboardUploader(IReportTransport transport) : this(transport, NewSession()) { }
        public OnboardUploader(IReportTransport transport, uint session) { if (transport == null) throw new ArgumentNullException("transport"); if (session == 0) throw new ArgumentOutOfRangeException("session"); this.transport = transport; this.session = session; }
        private static uint NewSession() { using (var random = RandomNumberGenerator.Create()) { byte[] p = new byte[4]; uint result; do { random.GetBytes(p); result = OnboardProfile.U32(p, 0); } while (result == 0); return result; } }
        public OnboardCapabilities SupportedModes()
        {
            if (transport.ConnectionName != "USB" || transport.UsesRollingAnimationVerification) return new OnboardCapabilities();
            transport.CheckSingleDevice(); new RGBClient(transport).Read(); return ParseCapabilities(transport.Exchange(new byte[] { 8, 3, 7, 0 })) ?? new OnboardCapabilities();
        }
        public OnboardReceipt Transfer(OnboardProfile profile, bool persistent, Action<int, int> progress = null)
        {
            profile.Validate(); Require(transport.ConnectionName == "USB" && !transport.UsesRollingAnimationVerification, "Connect directly by wired USB to upload or save a keyboard profile.");
            Require(!profile.NeedsHostSensors, "Music and CPU temperature require Play from PC. Remove those layers before saving standalone lighting.");
            transport.CheckSingleDevice(); var lighting = new RGBClient(transport); lighting.Read();
            var caps = Capabilities(); Require(!caps.ActivationPending && (persistent ? caps.Persistent : caps.Volatile), "This firmware does not advertise the requested verified profile upload mode.");
            byte[] bytes = profile.Bytes; Require(bytes.Length <= caps.MaximumLength && profile.MaximumEffectId <= caps.MaximumEffectId, "The keyboard firmware does not support this profile's size or effects."); uint digest = OnboardProfile.CRC32(bytes);
            Ack(transport.Exchange(Packet(1, OnboardProfile.LE32(session), OnboardProfile.LE16(bytes.Length), OnboardProfile.LE32(digest))), 1, 0, null);
            int offset = 0, chunks = 0;
            while (offset < bytes.Length)
            {
                int count = Math.Min(caps.ChunkSize, bytes.Length - offset), next = offset + count;
                Ack(transport.Exchange(Packet(2, OnboardProfile.LE32(session), OnboardProfile.LE16(offset), new byte[] { (byte)count }, bytes.Skip(offset).Take(count).ToArray())), 2, next, null);
                offset = next; chunks++; if (progress != null) progress(offset, bytes.Length);
            }
            transport.CheckSingleDevice(); Ack(transport.Exchange(Packet(3, OnboardProfile.LE32(session))), 3, bytes.Length, digest); transport.CheckSingleDevice();
            if (lighting.Read().Effect != 20) lighting.SelectOnboardEffect();
            byte operation = (byte)(persistent ? 4 : 7);
            // A lost commit acknowledgment is indeterminate. There is no retry loop for any write.
            Ack(transport.Exchange(Packet(operation, OnboardProfile.LE32(session))), operation, bytes.Length, digest);
            OnboardCapabilities after = null;
            for (int i = 0; i < 25; i++) { transport.CheckSingleDevice(); after = Capabilities(); if (!after.ActivationPending) break; if (i < 24) Thread.Sleep(20); }
            Require(after != null && !after.ActivationPending && after.ActiveLength == bytes.Length && after.ActiveCRC == digest, "Activation was not confirmed. Inspect the keyboard before attempting another save.");
            Require(Readback(after).SequenceEqual(bytes), "The keyboard's complete profile readback differs from the file sent.");
            return new OnboardReceipt { Length = bytes.Length, CRC = digest, Chunks = chunks, Persistent = persistent };
        }
        public byte[] ReadActive()
        {
            Require(transport.ConnectionName == "USB", "Connect by USB to verify the saved profile."); transport.CheckSingleDevice(); new RGBClient(transport).Read(); var caps = Capabilities(); Require(!caps.ActivationPending && caps.ActiveLength > 0, "No active profile was reported by the keyboard."); return Readback(caps);
        }
        private byte[] Readback(OnboardCapabilities caps)
        {
            var result = new List<byte>();
            while (result.Count < caps.ActiveLength)
            {
                transport.CheckSingleDevice(); int offset = result.Count, count = Math.Min(19, caps.ActiveLength - offset);
                byte[] reply = transport.Exchange(new byte[] { 8, 3, 7, 5 }.Concat(OnboardProfile.LE16(offset)).Concat(new byte[] { (byte)count }).ToArray());
                Require(Envelope(reply, 8, 5) && reply[9] == 0 && OnboardProfile.U16(reply, 10) == offset && reply[12] == count, "Invalid saved-profile readback response."); result.AddRange(reply.Skip(13).Take(count));
            }
            byte[] bytes = result.ToArray(); Require(OnboardProfile.CRC32(bytes) == caps.ActiveCRC, "Saved-profile readback checksum differs."); new OnboardProfile(bytes).Validate(); return bytes;
        }
        private OnboardCapabilities Capabilities() { var caps = ParseCapabilities(transport.Exchange(new byte[] { 8, 3, 7, 0 })); Require(caps != null, "On-keyboard profiles require newer compatible GMK104 firmware."); return caps; }
        private static OnboardCapabilities ParseCapabilities(byte[] p)
        {
            if (!Envelope(p, 8, 0) || p[13] > 1 || (p[20] != 0 && !((p[20]>=9 && p[20]<=24) || p[20]==26)) || p.Skip(21).Any(x => x != 0)) return null;
            int length = OnboardProfile.U16(p, 10), chunk = p[12], active = OnboardProfile.U16(p, 14); bool pending = p[13] != 0;
            bool valid = length >= 1 && length <= OnboardProfile.MaximumSize && chunk >= 1 && chunk <= 21 && active <= length;
            return new OnboardCapabilities { Flags = p[9], MaximumLength = length, ChunkSize = chunk, ActivationPending = pending, ActiveLength = active, ActiveCRC = OnboardProfile.U32(p, 16), MaximumEffectId = p[20] == 0 ? 8 : p[20], Volatile = valid && !pending && (p[9] & 5) == 5, Persistent = valid && !pending && (p[9] & 7) == 7 };
        }
        private void Ack(byte[] p, byte operation, int offset, uint? digest) { Require(Envelope(p, 7, operation) && p[9] == 0 && OnboardProfile.U32(p, 10) == session && OnboardProfile.U16(p, 14) == offset && (!digest.HasValue || OnboardProfile.U32(p, 16) == digest.Value), "The keyboard did not acknowledge the profile transfer exactly. Do not retry an uncertain save automatically."); }
        private static bool Envelope(byte[] p, byte family, byte op) { return p != null && p.Length == 32 && p[0] == family && p[1] == 3 && p[2] == 7 && p[3] == op && p.Skip(4).Take(4).SequenceEqual(new byte[] { 71, 77, 75, 85 }) && p[8] == 1; }
        private static byte[] Packet(byte op, params byte[][] fields) { return new byte[] { 7, 3, 7, op }.Concat(fields.SelectMany(x => x)).ToArray(); }
        private static void Require(bool condition, string message) { PersistJson.Require(condition, message); }
    }
}
