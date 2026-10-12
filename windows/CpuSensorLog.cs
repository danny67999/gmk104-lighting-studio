using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Gmk104LightingStudio
{
    internal sealed class CpuSensorSample
    {
        internal List<double> Values = new List<double>();
        internal double AgeSeconds;
    }
    internal static class CpuSensorLog
    {
        internal static string DefaultDirectory { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "LibreHardwareMonitor-0.9.6"); } }
        internal const string SetupHelp = "CPU temperature requires a separate sensor provider.\r\n\r\nLibreHardwareMonitor 0.9.6: keep it running with CPU sensors enabled, Options > Log Sensors enabled, and a 1-second logging interval. Choose its program/log folder here. Administrator access and the official PawnIO driver may be required. Older WMI providers remain supported.\r\n\r\nNo web server is needed. Logs stay on this PC and can grow over time; manage old logs with the monitor closed. Missing or stale readings make this layer transparent, not a guessed CPU temperature. The app never installs drivers or disables security protections.\r\n\r\nOfficial download: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases";
        internal static CpuSensorSample ReadDirectory(string directory, DateTime nowUtc)
        {
            if (String.IsNullOrWhiteSpace(directory) || directory.StartsWith(@"\\") || !Path.IsPathRooted(directory) || !Directory.Exists(directory)) return null;
            string pattern = "LibreHardwareMonitorLog-" + nowUtc.ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + "*.csv";
            foreach (var file in new DirectoryInfo(directory).EnumerateFiles(pattern).Take(128).OrderByDescending(f => f.LastWriteTimeUtc).Take(4))
            {
                if (nowUtc - file.LastWriteTimeUtc > TimeSpan.FromSeconds(5)) continue;
                try { var sample = ReadFile(file.FullName, nowUtc); if (sample != null) return sample; }
                catch (IOException) { }
            }
            return null;
        }
        internal static CpuSensorSample ReadFile(string path, DateTime nowUtc)
        {
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                long length = stream.Length;
                byte[] head = new byte[(int)Math.Min(65536, length)]; int got = ReadBytes(stream, head);
                string start = Encoding.UTF8.GetString(head, 0, got); int newline = start.IndexOf('\n');
                if (newline < 0) return null;
                byte[] tail = new byte[(int)Math.Min(65536, length)]; stream.Position = length - tail.Length;
                got = ReadBytes(stream, tail); string end = Encoding.UTF8.GetString(tail, 0, got);
                // Ignore an unfinished last row while the monitor is appending.
                int last = end.LastIndexOf('\n'); if (last <= 0) return null;
                int previous = end.LastIndexOf('\n', Math.Max(0, last - 1));
                if (previous < 0 && length > tail.Length) return null;
                return Parse(start.Substring(0, newline).TrimEnd('\r'), end.Substring(previous + 1, last - previous - 1).TrimEnd('\r'), nowUtc);
            }
        }
        private static int ReadBytes(Stream stream, byte[] bytes)
        {
            int total = 0, read; while (total < bytes.Length && (read = stream.Read(bytes, total, bytes.Length - total)) > 0) total += read; return total;
        }
        internal static CpuSensorSample Parse(string header, string row, DateTime nowUtc)
        {
            var ids = header.TrimStart('\uFEFF').Split(','); var values = row.Split(',');
            if (ids.Length != values.Length || ids.Length > 4096 || ids[0] != "") return null;
            DateTime local;
            if (!DateTime.TryParseExact(values[0], "MM/dd/yyyy HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out local)) return null;
            double age = (nowUtc - DateTime.SpecifyKind(local, DateTimeKind.Local).ToUniversalTime()).TotalSeconds;
            if (age < 0 || age >= 5) return null;
            var sample = new CpuSensorSample { AgeSeconds = age };
            for (int i = 1; i < ids.Length; i++)
            {
                if (!Regex.IsMatch(ids[i], @"^/(amdcpu|intelcpu)/[0-9]+/temperature/[0-9]+$", RegexOptions.CultureInvariant)) continue;
                double value;
                if (Double.TryParse(values[i], NumberStyles.Float, CultureInfo.InvariantCulture, out value) && !Double.IsNaN(value) && !Double.IsInfinity(value) && value >= 1 && value <= 125) sample.Values.Add(value);
            }
            return sample.Values.Count == 0 ? null : sample;
        }
    }
}
