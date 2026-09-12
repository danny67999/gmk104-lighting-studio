using System;
using System.IO;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;

internal static class IconBuilder
{
    private static GraphicsPath Round(float x, float y, float w, float h, float r)
    {
        var p = new GraphicsPath(); p.AddArc(x,y,r,r,180,90); p.AddArc(x+w-r,y,r,r,270,90);
        p.AddArc(x+w-r,y+h-r,r,r,0,90); p.AddArc(x,y+h-r,r,r,90,90); p.CloseFigure(); return p;
    }
    private static Bitmap Draw(int size, bool firmware)
    {
        var b = new Bitmap(size,size,PixelFormat.Format32bppArgb);
        using(var g = Graphics.FromImage(b))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias; g.ScaleTransform(size/256f,size/256f);
            using(var p=Round(8,8,240,240,56)) using(var fill=new LinearGradientBrush(new Rectangle(8,8,240,240),Color.FromArgb(31,47,64),Color.FromArgb(8,14,23),60)) g.FillPath(fill,p);
            using(var p=Round(30,60,196,136,24)) using(var fill=new SolidBrush(Color.FromArgb(22,32,45))) using(var pen=new Pen(firmware?Color.FromArgb(255,178,65):Color.FromArgb(49,223,165),7)) { g.FillPath(fill,p);g.DrawPath(pen,p); }
            for(int row=0;row<3;row++) for(int col=0;col<6;col++)
            {
                var c=firmware?Color.FromArgb(255,190-row*30,70):Color.FromArgb(50+col*20,225-row*16,150+row*30);
                using(var fill=new SolidBrush(c)) using(var p=Round(48+col*27,80+row*27,19,17,5)) g.FillPath(fill,p);
            }
            using(var p=Round(73,166,110,14,5)) using(var fill=new SolidBrush(firmware?Color.FromArgb(255,178,65):Color.FromArgb(92,220,235))) g.FillPath(fill,p);
            if(firmware) using(var fill=new SolidBrush(Color.FromArgb(255,231,173))) g.FillPolygon(fill,new[]{new Point(178,24),new Point(158,53),new Point(174,53),new Point(165,76),new Point(200,43),new Point(182,43),new Point(191,24)});
        }
        return b;
    }
    public static void Main(string[] args)
    {
        Directory.CreateDirectory(args[0]);
        foreach(bool firmware in new[]{false,true})
        {
            string name=firmware?"gmk104-firmware":"gmk104";
            int[] sizes={16,24,32,48,64,128,256};var images=new List<byte[]>();
            foreach(int size in sizes) using(var b=Draw(size,firmware)) using(var m=new MemoryStream()) {b.Save(m,ImageFormat.Png);images.Add(m.ToArray());if(size==256)b.Save(Path.Combine(args[0],name+".png"),ImageFormat.Png);}
            using(var stream=File.Create(Path.Combine(args[0],name+".ico"))) using(var w=new BinaryWriter(stream))
            {
                w.Write((ushort)0);w.Write((ushort)1);w.Write((ushort)sizes.Length);int offset=6+16*sizes.Length;
                for(int i=0;i<sizes.Length;i++){w.Write((byte)(sizes[i]==256?0:sizes[i]));w.Write((byte)(sizes[i]==256?0:sizes[i]));w.Write((ushort)0);w.Write((ushort)1);w.Write((ushort)32);w.Write(images[i].Length);w.Write(offset);offset+=images[i].Length;}
                foreach(var image in images)w.Write(image);
            }
        }
    }
}
