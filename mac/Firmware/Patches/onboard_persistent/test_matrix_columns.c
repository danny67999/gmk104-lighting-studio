#include "../onboard_runtime/runtime.h"
#include "../native_ripple/logical_columns.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint8_t original[GMK_PROFILE_BUFFER_BYTES],profile[GMK_PROFILE_BUFFER_BYTES],frames[60*312];
static unsigned length;
static void put32(uint8_t *p,uint32_t n){unsigned i;for(i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
static void setup(gmk_fixed_renderer *r,unsigned effect){gmk_profile_view v;memcpy(profile,original,length);profile[344]=(uint8_t)effect;put32(profile+12,gmk_profile_crc32(profile+32,length-32));assert(gmk_profile_validate(profile,length,&v)&&gmk_fixed_init(r,&v));}
static void reset(gmk_fixed_renderer *r){gmk_profile_view v;put32(profile+12,gmk_profile_crc32(profile+32,length-32));assert(gmk_profile_validate(profile,length,&v)&&gmk_fixed_init(r,&v));}
static int lit(const uint8_t *f,unsigned scan){unsigned out=profile[32+scan];return f[out*3]||f[out*3+1]||f[out*3+2];}
static void save(const char *p,const uint8_t *b,size_t n){FILE*f=fopen(p,"wb");assert(f&&fwrite(b,1,n,f)==n&&fclose(f)==0);}
int main(int argc,char **argv){
 gmk_fixed_renderer r,fast;gmk_runtime rt;unsigned i,j,col,seen[104]={0},trigger[21],a=0;uint8_t f[312],sped[312],caps[32],request[32]={8,3,7,0};
 FILE*file=fopen("mac/Tests/Fixtures/onboard-profile-matrix-v1.3.bin","rb");assert(file);length=(unsigned)fread(original,1,sizeof original,file);assert(feof(file));fclose(file);assert(GMK_PROFILE_MAX_EFFECT_ID==26);
 for(i=0;i<21;i++)trigger[i]=104;
 for(i=0;i<104;i++){assert(gmk_logical_scan[i]<192);col=gmk_logical_scan[i]&31;assert(col<21);if(trigger[col]==104)trigger[col]=i;if(gmk_logical_scan[i]==97)a=i;}
 assert(gmk_logical_scan[0]==0&&gmk_logical_scan[a]==97);
 for(i=0;i<21;i++)assert(trigger[i]<104);
 setup(&r,25);
 for(i=0;i<60;i++){assert(gmk_fixed_render(&r,i*100,frames+i*312));for(j=0;j<104;j++){int on=lit(frames+i*312,j);if(gmk_logical_scan[j]&1)assert(!on);else if(on)seen[j]=1;}}
 for(j=0;j<104;j++)assert(seen[j]==((gmk_logical_scan[j]&1)==0));
 gmk_runtime_init(&rt,NULL,0,NULL,NULL);assert(gmk_runtime_dispatch(&rt,request,caps,1)&&caps[20]==26);
 if(argc==2&&!strcmp(argv[1],"--emit-fixtures")){save("mac/Tests/Fixtures/spaced-matrix-native-v1.7.bin",frames,sizeof frames);save("mac/Tests/Fixtures/onboard-profile-spaced-matrix-v1.7.bin",profile,length);save("mac/Tests/Fixtures/onboard-capabilities-v1.7.bin",caps,32);}
 gmk_fixed_render(&r,1300,f);profile[346]=0;profile[347]=2;reset(&fast);gmk_fixed_render(&fast,650,sped);assert(!memcmp(f,sped,312));
 setup(&r,26);assert(gmk_fixed_render(&r,0,f));for(i=0;i<312;i++)assert(!f[i]);
 gmk_fixed_key_down(&r,(uint8_t)a,0);assert(r.pulse_count==1&&!r.distance_pending);gmk_fixed_key_down(&r,(uint8_t)a,0);assert(r.pulse_count==1);
 memset(seen,0,sizeof seen);
 for(i=0;i<60;i++){gmk_fixed_render(&r,i*100,frames+i*312);for(j=0;j<104;j++){int on=lit(frames+i*312,j);if((gmk_logical_scan[j]&31)!=1)assert(!on);else if(on)seen[j]=1;if(i==0&&on)assert(gmk_logical_scan[j]>>5==0);}}
 for(j=0;j<104;j++)assert(seen[j]==((gmk_logical_scan[j]&31)==1));
 for(j=0;j<312;j++)assert(frames[59*312+j]==0);
 if(argc==2&&!strcmp(argv[1],"--emit-fixtures")){save("mac/Tests/Fixtures/key-matrix-native-v1.7.bin",frames,sizeof frames);save("mac/Tests/Fixtures/onboard-profile-key-matrix-v1.7.bin",profile,length);}
 gmk_fixed_render(&r,800,f);profile[346]=0;profile[347]=2;reset(&fast);gmk_fixed_key_down(&fast,(uint8_t)a,0);gmk_fixed_render(&fast,400,sped);assert(!memcmp(f,sped,312));
 for(col=0;col<21;col++){setup(&r,26);gmk_fixed_key_down(&r,(uint8_t)trigger[col],0);memset(seen,0,sizeof seen);for(i=0;i<3000;i+=20){gmk_fixed_render(&r,i,f);for(j=0;j<104;j++)if(lit(f,j)){assert((gmk_logical_scan[j]&31)==col);seen[j]=1;}}for(j=0;j<104;j++)if((gmk_logical_scan[j]&31)==col)assert(seen[j]);}
 /* Separate trigger/output masks, including custom LED permutations. */
 setup(&r,26);profile[345]=3;memset(profile+358,0,13);profile[358+a/8]=(uint8_t)(1u<<(a%8));reset(&r);gmk_fixed_key_down(&r,(uint8_t)trigger[2],0);gmk_fixed_render(&r,100,f);for(i=0;i<312;i++)assert(!f[i]);gmk_fixed_key_down(&r,(uint8_t)a,0);gmk_fixed_render(&r,100,f);assert(lit(f,trigger[1]));
 profile[345]=1;memset(profile+371,0,13);profile[371+a/8]=(uint8_t)(1u<<(a%8));reset(&r);gmk_fixed_key_down(&r,(uint8_t)a,0);for(i=0;i<3000;i+=20){gmk_fixed_render(&r,i,f);for(j=0;j<104;j++)if(j!=a)assert(!lit(f,j));}
 setup(&r,25);{uint8_t tmp=profile[32];profile[32]=profile[33];profile[33]=tmp;}reset(&r);assert(r.logical_output[profile[32]]==gmk_logical_scan[0]);assert(r.logical_output[profile[33]]==gmk_logical_scan[1]);
 for(i=0;i<60;i++){gmk_fixed_render(&r,i*100,f);for(j=0;j<104;j++)if(gmk_logical_scan[j]&1)assert(!lit(f,j));}
 puts("PASS: fixed 104-key logical columns; continuous odd-column spacing; all 21 reactive columns reach every assigned row, start at top, expire, ignore repeated down and honor independent masks/remapping/speed");return 0;
}
