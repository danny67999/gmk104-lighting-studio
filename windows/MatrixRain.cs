using System;
namespace Gmk104LightingStudio {
    internal static class MatrixRainRaster {
        private static int Noise(uint seed) { unchecked { seed ^= seed >> 16; seed *= 0x7feb352d; seed ^= seed >> 15; seed *= 0x846ca68b; seed ^= seed >> 16; return (int)(seed >> 24); } }
        private static int Mul(int a,int b) { return (a*b+127)/255; }
        internal static RGB Pixel(int x,int y,int minY,int maxY,double time,LightingSettings settings) {
            double ms=Math.Floor((time % (4294967296.0/1000))*1000);if(ms<0)ms+=4294967296.0;
            uint t=(uint)ms;int column=Math.Max(0,x)/2,rows=Math.Max(0,maxY-minY)/2+1;
            int speed=(int)Math.Round(settings.speed*256,MidpointRounding.AwayFromZero);uint period=(uint)(1800*256/speed);
            int phase=(int)((ulong)(t%period)*65536/period);uint cycle=t/period;
            int offset=column==0?0:Noise((uint)(column*811))*257,head=(phase-offset)&65535;
            int row=Math.Max(0,y-minY)/2,position=row*65536/rows,distance=(head-position)&65535;
            if(cycle==0&&phase<offset)return RGB.Black;
            if((cycle==0||(cycle==1&&phase<offset))&&position>head)return RGB.Black;
            if(distance>=49152)return RGB.Black;
            int white=0,glow;
            if(distance<8192){white=255-distance*255/8192;glow=255-distance*32/8192;}
            else {glow=220*(49152-distance)/40960;}
            int coverage=Mul(glow,(int)Math.Round(settings.intensity*255,MidpointRounding.AwayFromZero));
            return new RGB((byte)Mul(settings.color.r+Mul(255-settings.color.r,white),coverage),(byte)Mul(settings.color.g+Mul(255-settings.color.g,white),coverage),(byte)Mul(settings.color.b+Mul(255-settings.color.b,white),coverage));
        }
    }
}
