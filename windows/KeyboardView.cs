using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

namespace Gmk104LightingStudio
{
    public sealed class KeyboardView : Control
    {
        public KeyGeometry[] Keys = new KeyGeometry[0];
        public MappingFile Mapping;
        public RGB[] Frame;
        public HashSet<string> Selection;
        public bool ShowIndices;
        public event Action<string> KeyClicked;
        public KeyboardView() { DoubleBuffered = true; BackColor = Color.FromArgb(10, 14, 19); Dock = DockStyle.Fill; Cursor = Cursors.Hand; }
        private RectangleF BoundsFor(KeyGeometry key)
        {
            double w = Keys.Length == 0 ? 23 : Keys.Max(k => k.x + k.width);
            double h = Keys.Length == 0 ? 7 : Keys.Max(k => k.y + k.height);
            float unit = (float)Math.Min((Width - 28) / w, (Height - 24) / h);
            return new RectangleF((Width - (float)w * unit) / 2 + (float)key.x * unit + 2, 12 + (float)key.y * unit + 2, Math.Max(3, (float)key.width * unit - 4), Math.Max(3, (float)key.height * unit - 4));
        }
        protected override void OnMouseClick(MouseEventArgs e)
        {
            base.OnMouseClick(e);
            foreach (KeyGeometry key in Keys) if (BoundsFor(key).Contains(e.Location)) { if (KeyClicked != null) KeyClicked(key.id); break; }
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e); e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            foreach (KeyGeometry key in Keys)
            {
                var m = Mapping == null ? null : Mapping.mappings.FirstOrDefault(x => x.keyId == key.id);
                bool known = m != null && m.confirmed && m.ledIndex.HasValue;
                RGB rgb = known && Frame != null && Frame.Length == 104 ? Frame[m.ledIndex.Value] : new RGB(49, 127, 110);
                Color color = Color.FromArgb(rgb.r, rgb.g, rgb.b);
                bool selected = Selection != null && Selection.Contains(key.id);
                var rect = BoundsFor(key);
                using (var shape = Rounded(rect, 5))
                using (var fill = new SolidBrush(Color.FromArgb(26 + rgb.r / 6, 30 + rgb.g / 6, 35 + rgb.b / 6)))
                using (var border = new Pen(selected ? Color.FromArgb(80, 239, 155) : known ? color : Color.FromArgb(55, 60, 69), selected ? 2.5f : 1))
                {
                    e.Graphics.FillPath(fill, shape); e.Graphics.DrawPath(border, shape);
                }
                string label = key.label.Replace("\n", " ");
                if (ShowIndices && known) label += "\n" + m.ledIndex.Value;
                var flags = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix;
                TextRenderer.DrawText(e.Graphics, label, Font, Rectangle.Round(rect), Selection != null && !selected ? Color.FromArgb(124, 135, 145) : Color.FromArgb(237, 242, 247), flags);
            }
        }
        private static GraphicsPath Rounded(RectangleF r, float radius)
        {
            var p = new GraphicsPath(); float d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
            p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure(); return p;
        }
    }
}
