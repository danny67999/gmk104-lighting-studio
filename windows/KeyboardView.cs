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
        public bool SelectionEnabled;
        public event Action<string> KeyClicked;
        public event Action<List<string>> SelectionChanged;
        private bool dragging, marquee, removing;
        private Point dragStart, previousPoint;
        private Rectangle selectionRect;
        private HashSet<string> original, painted;
        private System.Windows.Forms.Keys dragModifiers;
        public KeyboardView() { DoubleBuffered = true; BackColor = Color.FromArgb(10, 14, 19); Dock = DockStyle.Fill; Cursor = Cursors.Hand; }
        internal RectangleF BoundsFor(KeyGeometry key)
        {
            double w = Keys.Length == 0 ? 23 : Keys.Max(k => k.x + k.width);
            double h = Keys.Length == 0 ? 7 : Keys.Max(k => k.y + k.height);
            float unit = (float)Math.Min((Width - 28) / w, (Height - 24) / h);
            return new RectangleF((Width - (float)w * unit) / 2 + (float)key.x * unit + 2, 12 + (float)key.y * unit + 2, Math.Max(3, (float)key.width * unit - 4), Math.Max(3, (float)key.height * unit - 4));
        }
        protected override void OnMouseClick(MouseEventArgs e)
        {
            base.OnMouseClick(e);
            if (SelectionEnabled) return;
            foreach (KeyGeometry key in Keys) if (BoundsFor(key).Contains(e.Location)) { if (KeyClicked != null) KeyClicked(key.id); break; }
        }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (!SelectionEnabled || e.Button != MouseButtons.Left) return;
            Focus(); dragging = true; dragStart = previousPoint = e.Location; dragModifiers = ModifierKeys;
            original = Selection == null ? new HashSet<string>(Keys.Select(k => k.id)) : new HashSet<string>(Selection);
            painted = new HashSet<string>();
            var hit = Keys.FirstOrDefault(k => BoundsFor(k).Contains(e.Location)); marquee = hit == null;
            removing = (dragModifiers & System.Windows.Forms.Keys.Alt) != 0 || (hit != null && original.Contains(hit.id) && (dragModifiers & System.Windows.Forms.Keys.Shift) == 0);
            Capture = true; SelectAt(e.Location);
        }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e); if (!dragging) return; SelectAt(e.Location); previousPoint = e.Location;
        }
        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e); if (!dragging || e.Button != MouseButtons.Left) return;
            SelectAt(e.Location); dragging = false; Capture = false; selectionRect = Rectangle.Empty; Invalidate();
        }
        protected override void OnMouseCaptureChanged(EventArgs e)
        {
            base.OnMouseCaptureChanged(e); if (!Capture) { dragging = false; selectionRect = Rectangle.Empty; Invalidate(); }
        }
        private void SelectAt(Point point)
        {
            HashSet<string> next;
            if (marquee)
            {
                selectionRect = Rectangle.FromLTRB(Math.Min(dragStart.X, point.X), Math.Min(dragStart.Y, point.Y), Math.Max(dragStart.X, point.X), Math.Max(dragStart.Y, point.Y));
                var hit = Keys.Where(k => BoundsFor(k).IntersectsWith(selectionRect)).Select(k => k.id);
                next = (dragModifiers & (System.Windows.Forms.Keys.Shift | System.Windows.Forms.Keys.Alt)) == 0 ? new HashSet<string>() : new HashSet<string>(original);
                if ((dragModifiers & System.Windows.Forms.Keys.Alt) != 0) next.ExceptWith(hit); else next.UnionWith(hit);
            }
            else
            {
                // Sample the whole pointer segment so quick strokes cannot skip keys.
                int steps = Math.Max(1, Math.Max(Math.Abs(point.X - previousPoint.X), Math.Abs(point.Y - previousPoint.Y)) / 3);
                for (int step = 0; step <= steps; step++)
                {
                    var sample = new PointF(previousPoint.X + (point.X - previousPoint.X) * step / (float)steps, previousPoint.Y + (point.Y - previousPoint.Y) * step / (float)steps);
                    foreach (var key in Keys) if (BoundsFor(key).Contains(sample)) painted.Add(key.id);
                }
                next = new HashSet<string>(original); if (removing) next.ExceptWith(painted); else next.UnionWith(painted);
            }
            Selection = next; if (SelectionChanged != null) SelectionChanged(Keys.Where(k => next.Contains(k.id)).Select(k => k.id).ToList()); Invalidate();
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
                using (var border = new Pen(selected ? SystemColors.Highlight : known ? color : Color.FromArgb(55, 60, 69), selected ? 1.5f : 1))
                {
                    e.Graphics.FillPath(fill, shape); e.Graphics.DrawPath(border, shape);
                    if (selected) using (var tint = new SolidBrush(Color.FromArgb(34, SystemColors.Highlight))) e.Graphics.FillPath(tint, shape);
                }
                string label = key.label.Replace("\n", " ");
                if (ShowIndices && known) label += "\n" + m.ledIndex.Value;
                var flags = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix;
                TextRenderer.DrawText(e.Graphics, label, Font, Rectangle.Round(rect), Selection != null && !selected ? Color.FromArgb(124, 135, 145) : Color.FromArgb(237, 242, 247), flags);
            }
            if (dragging && marquee && !selectionRect.IsEmpty)
                using (var tint = new SolidBrush(Color.FromArgb(26, SystemColors.Highlight)))
                using (var line = new Pen(SystemColors.Highlight, 1)) { e.Graphics.FillRectangle(tint, selectionRect); e.Graphics.DrawRectangle(line, selectionRect); }
        }
        private static GraphicsPath Rounded(RectangleF r, float radius)
        {
            var p = new GraphicsPath(); float d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
            p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure(); return p;
        }
    }
}
