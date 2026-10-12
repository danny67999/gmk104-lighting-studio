#include "../onboard_runtime/runtime.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint8_t fixture[GMK_PROFILE_MAX_BYTES], profile[GMK_PROFILE_MAX_BYTES];
static gmk_runtime runtime;
static void put16(uint8_t *p,unsigned n){p[0]=(uint8_t)n;p[1]=(uint8_t)(n>>8);}
static void put32(uint8_t *p,uint32_t n){unsigned i;for(i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
static unsigned create(unsigned layers,unsigned effect){
 unsigned i,at=344;
 for(i=0;i<layers;i++)at+=57+fixture[at+56];
 memcpy(profile,fixture,at);profile[6]=(uint8_t)layers;profile[11]=60;profile[20]=(uint8_t)(effect==7?1:effect==8?2:0);put16(profile+8,at);
 for(i=0,at=344;i<layers;i++){
  profile[at]=(uint8_t)effect;profile[at+1]=(uint8_t)(i&1?15:11);profile[at+4]=profile[at+5]=255;
  memset(profile+at+14,255,26);at+=57+profile[at+56];
 }
 put32(profile+12,gmk_profile_crc32(profile+32,at-32));return at;
}
static unsigned finish_frame(gmk_runtime *r,uint8_t *out,unsigned elapsed){
 unsigned visits;
 for(visits=1;visits<2000;visits++)if(gmk_runtime_step(r,out,visits==1?elapsed:0))return visits;
 assert(!"a bounded frame must finish");return 0;
}
int main(void){
 unsigned effect,layers,led,i,visits,length;gmk_profile_view view;
 uint8_t expected[312],output[312];
 FILE *file=fopen("mac/Tests/Fixtures/onboard-profile-all-effects-v1.bin","rb");assert(file);
 assert(fread(fixture,1,sizeof fixture,file)>344);assert(feof(file));fclose(file);
 for(layers=1;layers<=16;layers+=15)for(effect=0;effect<=GMK_PROFILE_MAX_EFFECT_ID;effect++){
  gmk_fixed_renderer direct,incremental;gmk_fixed_job job;
  length=create(layers,effect);assert(gmk_profile_validate(profile,(uint16_t)length,&view));
  assert(gmk_fixed_init(&direct,&view)&&gmk_fixed_init(&incremental,&view));
  for(i=0;i<16;i++){
   gmk_fixed_key_down(&direct,(uint8_t)(39+i),i*20);
   gmk_fixed_begin_key_down(&incremental,(uint8_t)(39+i),i*20);
   for(visits=0;incremental.distance_pending;visits++){
    unsigned before=incremental.distance_led;gmk_fixed_prepare_distances(&incremental);
    assert(incremental.distance_led-before<=GMK_FIXED_DISTANCE_BUDGET);
    assert(visits<26);
   }
  }
  if(effect<=1){assert(direct.pulse_count==incremental.pulse_count);assert(!memcmp(direct.distances_q8,incremental.distances_q8,sizeof direct.distances_q8));}
  if(effect>2 && !(effect>=19&&effect<=23)
#ifdef GMK_MATRIX_COLUMNS
 && effect!=26
#endif
 ){assert(incremental.pulse_count==0&&!incremental.distance_pending);}
  gmk_fixed_set_music(&direct,50,100,150,200,900);gmk_fixed_set_music(&incremental,50,100,150,200,900);
  gmk_fixed_set_temperature(&direct,6300,900);gmk_fixed_set_temperature(&incremental,6300,900);
  assert(gmk_fixed_render(&direct,1000,expected));memset(output,0xA5,sizeof output);
  gmk_fixed_job_start(&incremental,&job,1000);
  for(visits=0;visits<900;visits++){
   unsigned before=job.led;int completed=gmk_fixed_job_step(&incremental,&job,output);
   if(completed)break;
   if(job.led)assert(job.led-before<=GMK_FIXED_PIXEL_BUDGET);
   for(led=0;led<312;led++)assert(output[led]==0xA5);
  }
  assert(visits<900&&!memcmp(output,expected,312));
 }
 printf("PASS: all %u effect IDs with 1/16 layers match the full renderer byte-for-byte; incomplete frames never publish\n", GMK_PROFILE_MAX_EFFECT_ID + 1u);
 length=create(1,9);assert(gmk_runtime_init(&runtime,profile,(uint16_t)length,0,0));
 assert(finish_frame(&runtime,output,20)>1);
 gmk_runtime_key_change(&runtime,39,255);assert(finish_frame(&runtime,output,20)>1);assert(runtime.renderer.held_scan[39/8]&(1u<<(39%8)));
 gmk_runtime_key_change(&runtime,39,0);finish_frame(&runtime,output,20);assert(!(runtime.renderer.held_scan[39/8]&(1u<<(39%8))));
 for(led=0;led<312;led++)assert(output[led]==0);
 length=create(16,1);assert(gmk_runtime_init(&runtime,profile,(uint16_t)length,0,0));finish_frame(&runtime,output,20);
 for(i=0;i<16;i++)gmk_runtime_key_change(&runtime,39+i,255);
 for(i=0;i<16;i++)gmk_runtime_key_change(&runtime,39+i,0); /* force safe overflow */
 finish_frame(&runtime,output,20);for(i=0;i<13;i++)assert(!runtime.renderer.held_scan[i]);
 gmk_runtime_key_change(&runtime,39,255);
 i=runtime.event_read;assert(!gmk_runtime_step(&runtime,output,20));assert(runtime.event_read==((i+1)&31));assert(runtime.renderer.distance_pending&&runtime.renderer.distance_led==0);
 for(i=0;i<26;i++){unsigned before=runtime.renderer.distance_led;assert(!gmk_runtime_step(&runtime,output,0));assert(runtime.renderer.distance_led-before<=4);}
 assert(!runtime.renderer.distance_pending);visits=finish_frame(&runtime,output,0);assert(visits>800&&visits<900);
 /* Independently verify trigger/output masks, expiry, and native edge reach. */
 for(effect=19;effect<=23;effect++) {
  gmk_fixed_renderer direct;unsigned far=0,peak=0;uint8_t slow[312],fast[312];
  length=create(1,effect);profile[345]=3;put16(profile+346,256);
  memset(profile+358,0,13);profile[358+39/8]=(uint8_t)(1u<<(39%8));
  put32(profile+12,gmk_profile_crc32(profile+32,length-32));
  assert(gmk_profile_validate(profile,length,&view)&&gmk_fixed_init(&direct,&view));
  gmk_fixed_key_down(&direct,40,0);assert(gmk_fixed_render(&direct,20,output));
  for(i=0;i<312;i++)assert(!output[i]);
  gmk_fixed_key_down(&direct,39,0);assert(gmk_fixed_render(&direct,20,output));
  assert(output[39*3]||output[39*3+1]||output[39*3+2]);
  assert(gmk_fixed_render(&direct,20000,output));for(i=0;i<312;i++)assert(!output[i]);
  if(effect==19) continue;
  for(led=0;led<104;led++) {
   int dx=(int)profile[136+led*2]-profile[136+39*2];
   int dy=(int)profile[137+led*2]-profile[137+39*2];
   unsigned ax=(unsigned)(dx<0?-dx:dx),ay=(unsigned)(dy<0?-dy:dy),distance;
   if(effect==21&&ax>1&&ay>1)continue;
   distance=effect==22?ax:effect==23?ay:effect==21?(ax>ay?ax:ay):ax*ax+ay*ay;
   if(distance>peak){peak=distance;far=led;}
  }
  peak=0;
  for(i=0;i<4500;i+=20){gmk_fixed_render(&direct,i,output);peak|=output[far*3]|output[far*3+1]|output[far*3+2];}
  assert(peak); /* The farthest eligible physical key is visibly reached. */
  gmk_fixed_render(&direct,800,slow);put16(profile+346,512);
  put32(profile+12,gmk_profile_crc32(profile+32,length-32));
  assert(gmk_profile_validate(profile,length,&view)&&gmk_fixed_init(&direct,&view));
  gmk_fixed_key_down(&direct,39,0);gmk_fixed_render(&direct,400,fast);assert(!memcmp(slow,fast,312));
 }
 puts("PASS: native press effects ignore unrelated triggers, expire, reach the farthest eligible key, and scale their speed");
 /* Toggle is a transition, not an auto-repeat or release action. */
 length=create(1,18);profile[345]=11;put32(profile+12,gmk_profile_crc32(profile+32,length-32));assert(gmk_profile_validate(profile,length,&view));
 assert(gmk_runtime_init(&runtime,profile,length,0,0));finish_frame(&runtime,output,20);
 gmk_runtime_key_change(&runtime,39,1);finish_frame(&runtime,output,20);assert(output[0]||output[1]||output[2]);
 gmk_runtime_key_change(&runtime,39,1);finish_frame(&runtime,output,20);assert(runtime.renderer.toggled_scan[39/8]&(1u<<(39%8)));
 gmk_runtime_key_change(&runtime,39,0);finish_frame(&runtime,output,20);assert(output[0]||output[1]||output[2]);
 gmk_runtime_key_change(&runtime,39,1);finish_frame(&runtime,output,20);
 for(i=0;i<312;i++)assert(!output[i]);
 puts("PASS: toggle lights the board, ignores repeated downs, survives release, and clears on the next press");
 puts("PASS: held-key release and overflow recovery; one event/four distances/two pixels per visit; 16-layer ripple frame completes");
 return 0;
}
