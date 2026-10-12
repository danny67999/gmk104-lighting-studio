#include "onboard_profile.h"
#include "renderer_fixed.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
#include <string.h>
static uint8_t profile[GMK_PROFILE_BUFFER_BYTES];
static unsigned length;
static void reset(gmk_fixed_renderer *r) {
    uint32_t crc=gmk_profile_crc32(profile+32,length-32);unsigned i;gmk_profile_view v;
    for(i=0;i<4;i++)profile[12+i]=(uint8_t)(crc>>(8*i));
    assert(gmk_profile_validate(profile,length,&v)&&gmk_fixed_init(r,&v));
}
int main(int argc,char **argv) {
    gmk_fixed_renderer r,fast;unsigned i,t,ch,minx=127,miny=127,maxx=0,maxy=0;
    uint8_t frame[312],second[312];int maxerr=0;double total=0;unsigned samples=0;
    FILE *f=fopen("mac/Tests/Fixtures/onboard-profile-matrix-v1.3.bin","rb");assert(f);
    length=(unsigned)fread(profile,1,sizeof profile,f);assert(feof(f));fclose(f);
    profile[344]=17;profile[345]=9;profile[348]=255;profile[349]=255;
    reset(&r);
    for(i=0;i<104;i++) { unsigned x=profile[136+i*2],y=profile[137+i*2];if(x<minx)minx=x;if(x>maxx)maxx=x;if(y<miny)miny=y;if(y>maxy)maxy=y; }
    f=argc==2 ? fopen(argv[1],"wb") : NULL;
    for(t=0;t<4000;t+=100) {
        unsigned darkest=255,brightest=0;assert(gmk_fixed_render(&r,t,frame));
        if(f)assert(fwrite(frame,1,312,f)==312);
        for(i=0;i<104;i++) {
            double x=(double)(profile[136+i*2]-minx)/(maxx-minx),y=(double)(profile[137+i*2]-miny)/(maxy-miny),motion=t/4000.0;
            double fold=sin(x*13+motion*4*3.141592653589793+y*3);
            double band=exp(-pow((y-.48-.22*fold)/.28,2));
            double level=(.08+.92*band)*255,hue=.38+.12*sin(x*6-motion*2*3.141592653589793);
            double h=hue*6,part=h-floor(h),rgb[3]={0,0,0};int sector=(int)floor(h);
            switch(sector){case 1:rgb[0]=1-part;rgb[1]=1;break;case 2:rgb[1]=1;rgb[2]=part;break;case 3:rgb[1]=1-part;rgb[2]=1;break;default:assert(0);}
            unsigned peak=0;
            for(ch=0;ch<3;ch++){int expected=(int)round(rgb[ch]*level),err=(int)frame[i*3+ch]-expected;if(err<0)err=-err;if(err>maxerr)maxerr=err;total+=err;samples++;if(frame[i*3+ch]>peak)peak=frame[i*3+ch];}
            if(peak<darkest)darkest=peak;if(peak>brightest)brightest=peak;
        }
        assert(brightest>230&&darkest<45&&brightest-darkest>190);
    }
    if(f)assert(fclose(f)==0);
    assert(maxerr<=8&&total/samples<2);
    gmk_fixed_render(&r,1300,frame);profile[346]=0;profile[347]=2;reset(&fast);gmk_fixed_render(&fast,650,second);assert(!memcmp(frame,second,312));
    profile[345]=1;memset(profile+358,0,13);profile[358+58/8]=(uint8_t)(1u<<(58%8));memset(profile+371,0,13);profile[371+58/8]=(uint8_t)(1u<<(58%8));reset(&fast);gmk_fixed_render(&fast,650,second);
    for(i=0;i<104;i++)if(i!=58)for(ch=0;ch<3;ch++)assert(second[i*3+ch]==0);
    printf("PASS: 40 Aurora frames match the preview's sine/Gaussian formula; max channel error %d/255, mean %.3f; every frame has bright bands/dim gaps, speed and key masks preserved\n",maxerr,total/samples);
    return 0;
}
