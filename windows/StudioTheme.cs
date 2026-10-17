using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Gmk104LightingStudio
{
    internal static class StudioTheme
    {
        internal static readonly bool Dark = ReadDark();
        internal static readonly Color Background = Dark ? Color.FromArgb(30, 30, 32) : Color.FromArgb(247, 247, 249);
        internal static readonly Color Sidebar = Dark ? Color.FromArgb(39, 39, 42) : Color.FromArgb(235, 235, 240);
        internal static readonly Color Card = Dark ? Color.FromArgb(44, 44, 47) : Color.White;
        internal static readonly Color Text = Dark ? Color.FromArgb(239, 239, 243) : Color.FromArgb(31, 31, 35);
        internal static readonly Color Secondary = Dark ? Color.FromArgb(166, 166, 176) : Color.FromArgb(105, 105, 115);
        internal static readonly Color Border = Dark ? Color.FromArgb(64, 64, 69) : Color.FromArgb(221, 221, 228);
        internal static Color Accent { get { return SystemColors.Highlight; } }
        private static bool ReadDark()
        {
            try { using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")) return key != null && Convert.ToInt32(key.GetValue("AppsUseLightTheme", 1)) == 0; }
            catch { return false; }
        }
        internal static GraphicsPath Round(RectangleF rect, float radius)
        {
            var p = new GraphicsPath(); float d = Math.Max(1, Math.Min(radius * 2, Math.Min(rect.Width, rect.Height)));
            p.AddArc(rect.X, rect.Y, d, d, 180, 90); p.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
            p.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90); p.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90); p.CloseFigure(); return p;
        }
    }
    internal sealed class StudioButton : Button
    {
        internal bool Primary, Navigation, Selected;
        private bool hover;
        internal StudioButton()
        {
            FlatStyle = FlatStyle.Flat; FlatAppearance.BorderSize = 0;
            BackColor = StudioTheme.Card; ForeColor = StudioTheme.Text;
            Cursor = Cursors.Hand; DoubleBuffered = true; Height = 34; AutoSize = true;
            MinimumSize = new Size(60, 34); Margin = new Padding(4); Padding = new Padding(10, 2, 10, 2);
        }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Color fill = Primary || Selected ? StudioTheme.Accent : Navigation ? StudioTheme.Sidebar : BackColor;
            Color text = Primary || Selected ? Color.White : ForeColor;
            if (!Enabled) { fill = StudioTheme.Sidebar; text = StudioTheme.Secondary; }
            var rect = new RectangleF(1, 1, Width - 3, Height - 3);
            using (var path = StudioTheme.Round(rect, 7))
            using (var brush = new SolidBrush(fill))
            using (var pen = new Pen(Primary || Selected ? fill : StudioTheme.Border))
            {
                e.Graphics.FillPath(brush, path);
                if (!Navigation) e.Graphics.DrawPath(pen, path);
                if (hover && Enabled) using (var overlay = new SolidBrush(Color.FromArgb(18, StudioTheme.Accent))) e.Graphics.FillPath(overlay, path);
                if (Focused && ShowFocusCues) using (var focus = new Pen(StudioTheme.Accent, 2)) e.Graphics.DrawPath(focus, path);
            }
            TextRenderer.DrawText(e.Graphics, Text, Font, new Rectangle(Navigation ? 12 : 4, 0, Width - (Navigation ? 16 : 8), Height), text,
                TextFormatFlags.VerticalCenter | (Navigation ? TextFormatFlags.Left : TextFormatFlags.HorizontalCenter) | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }
    }
    internal sealed class StudioCombo : ComboBox
    {
        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            if (DropDownStyle != ComboBoxStyle.DropDownList || !IsHandleCreated) return;
            if (m.Msg == 0x000F)
                using (var graphics = Graphics.FromHwnd(Handle)) PaintValue(graphics);
            else if ((m.Msg == 0x0317 || m.Msg == 0x0318) && m.WParam != IntPtr.Zero)
                using (var graphics = Graphics.FromHdc(m.WParam)) PaintValue(graphics);
        }
        private void PaintValue(Graphics graphics)
        {
            using (var fill = new SolidBrush(StudioTheme.Card)) graphics.FillRectangle(fill, ClientRectangle);
            using (var border = new Pen(StudioTheme.Border)) graphics.DrawRectangle(border, 0, 0, Width - 1, Height - 1);
            TextRenderer.DrawText(graphics, Text, Font, new Rectangle(7, 0, Math.Max(1, Width - 28), Height), Enabled ? StudioTheme.Text : StudioTheme.Secondary, TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            int x = Width - 14, y = Height / 2;
            using (var brush = new SolidBrush(StudioTheme.Secondary)) graphics.FillPolygon(brush, new[] { new Point(x - 3, y - 1), new Point(x + 3, y - 1), new Point(x, y + 2) });
        }
    }
    internal sealed class StudioToggle : CheckBox
    {
        internal StudioToggle() { AutoSize = false; Size = new Size(40, 25); Cursor = Cursors.Hand; DoubleBuffered = true; AccessibleRole = AccessibleRole.CheckButton; }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var path = StudioTheme.Round(new RectangleF(1, 3, Width - 3, 20), 10))
            using (var brush = new SolidBrush(Checked && Enabled ? StudioTheme.Accent : StudioTheme.Border)) e.Graphics.FillPath(brush, path);
            using (var brush = new SolidBrush(Enabled ? Color.White : StudioTheme.Secondary)) e.Graphics.FillEllipse(brush, Checked ? Width - 20 : 4, 6, 14, 14);
            if (Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics, ClientRectangle);
        }
    }
    internal sealed class StudioCard : Panel
    {
        internal bool Selected;
        internal StudioCard() { DoubleBuffered = true; BackColor = StudioTheme.Card; Padding = new Padding(12); }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e); e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var path = StudioTheme.Round(new RectangleF(1, 1, Width - 3, Height - 3), 9))
            using (var line = new Pen(Selected ? StudioTheme.Accent : StudioTheme.Border, Selected ? 1.5f : 1)) e.Graphics.DrawPath(line, path);
        }
    }
    internal sealed class EffectThumbnail : Control
    {
        internal KeyGeometry[] Geometry;
        internal MappingFile Map;
        internal LightingLayer Layer;
        internal RGB[] Colors;
        internal EffectThumbnail() { DoubleBuffered = true; BackColor = Color.FromArgb(15, 15, 17); }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e); if (Geometry == null) return;
            double width = 23, height = 7;
            foreach (var k in Geometry) { width = Math.Max(width, k.x + k.width); height = Math.Max(height, k.y + k.height); }
            float unit = (float)Math.Min((Width - 20) / width, (Height - 16) / height);
            foreach (var k in Geometry)
            {
                var entry = Map == null ? null : Map.mappings.Find(m => m.keyId == k.id);
                RGB rgb = entry != null && entry.ledIndex.HasValue && Colors != null ? Colors[entry.ledIndex.Value] : new RGB(0, 0, 0);
                var r = new RectangleF((Width - (float)width * unit) / 2 + (float)k.x * unit + 1, (Height - (float)height * unit) / 2 + (float)k.y * unit + 1, Math.Max(2, (float)k.width * unit - 2), Math.Max(2, (float)k.height * unit - 2));
                using (var brush = new SolidBrush(Color.FromArgb(Math.Max(23, (int)rgb.r), Math.Max(23, (int)rgb.g), Math.Max(27, (int)rgb.b)))) e.Graphics.FillRectangle(brush, r);
            }
        }
    }
}
