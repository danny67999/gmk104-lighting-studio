using System;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace Gmk104LightingStudio
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            if (args.Length > 1 && args[0] == "--preview")
            {
                Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
                using (var form = new StudioForm(true))
                {
                    form.Show(); if (args.Length > 2) form.SelectPreviewTab(Int32.Parse(args[2])); Application.DoEvents();
                    using (var bitmap = new System.Drawing.Bitmap(form.Width, form.Height)) { form.DrawToBitmap(bitmap, new System.Drawing.Rectangle(0, 0, form.Width, form.Height)); bitmap.Save(args[1], System.Drawing.Imaging.ImageFormat.Png); }
                    form.Close();
                }
                return;
            }
            if (args.Length > 0 && args[0] == "--probe")
            {
                // Reads identity, RGB state and optional sleep capabilities only.
                string report;
                int result = 0;
                try
                {
                    using (RGBClient client = new RGBClient(KeyboardConnections.Open("Auto")))
                    {
                        RGBState s = client.Read();
                        int? sleep = client.ReadSleepSeconds();
                        report = String.Format("READ-ONLY PROBE PASS\r\nTransport: {0}\r\nCustom RGB signature verified\r\nEffect: {1}\r\nBrightness: {2}\r\nLED 0: {3}\r\nChecksum: {4:X4}\r\nSleep seconds: {5}\r\n", client.Transport.ConnectionName, s.Effect, s.Brightness, s.Color, s.Checksum, sleep.HasValue ? sleep.Value.ToString() : "unsupported");
                    }
                }
                catch (Exception ex) { result = 1; report = "READ-ONLY PROBE FAILED\r\n" + ex.ToString(); }
                if (args.Length > 1) File.WriteAllText(args[1], report);
                Environment.ExitCode = result;
                return;
            }
            bool first;
            using (Mutex mutex = new Mutex(true, @"Local\GMK104LightingStudio", out first))
            {
                if (!first) { MessageBox.Show("GMK104 Lighting Studio is already running. Look for its app icon in the system tray."); return; }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new StudioForm());
            }
        }
    }
}
