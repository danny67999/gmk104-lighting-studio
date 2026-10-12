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
 for(layers=1;layers<=16;layers+=15)for(effect=0;effect<18;effect++){
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
  if(effect>2){assert(incremental.pulse_count==0&&!incremental.distance_pending);}
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
 puts("PASS: all 18 effect IDs with 1/16 layers match the full renderer byte-for-byte; incomplete frames never publish");
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
 puts("PASS: held-key release and overflow recovery; one event/four distances/two pixels per visit; 16-layer ripple frame completes");
 return 0;
}
