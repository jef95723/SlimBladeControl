#include "../src/chords.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
static int events[128], n;
static void emit(void *ctx,int slot,bool down) { (void)ctx; events[n++]=(slot+1)*(down?1:-1); }
static SBChords make(void) { SBChords s; sb_init(&s,emit,0); n=0; return s; }
static void expect(const int *v,int count) { assert(n==count); assert(!memcmp(v,events,count*sizeof(int))); }
static int balances[SB_ACTION_COUNT];
static void audit(void *ctx,int slot,bool down) {
    (void)ctx; assert(slot>=0 && slot<SB_ACTION_COUNT);
    balances[slot]+=down?1:-1;
    assert(balances[slot]>=0 && balances[slot]<=1);
}
#define CHECK(...) do {int e[]={__VA_ARGS__}; expect(e,sizeof(e)/sizeof(*e));} while(0)
int main(void) {
#ifdef RUST_CORE
    assert(sb_state_size()==sizeof(SBChords));
    SBReport report={0}; const uint8_t bytes[]={2,0x81,0x7f,0xff,1};
    assert(sb_decode_report(bytes,sizeof(bytes),false,&report));
    assert(report.buttons==6 && report.x==-127 && report.y==127 && report.wheel==-1);
    assert(sb_decode_report(bytes,sizeof(bytes),true,&report) && report.buttons==10);
    SBMotion motion={0}; SBDelta delta=sb_motion_step(&motion,3,-5,1,.5,.5,false);
    assert(delta.x==1 && delta.y==-2 && delta.scroll==12);
    delta=sb_motion_step(&motion,1,-1,0,.5,.5,false);
    assert(delta.x==1 && delta.y==-1 && delta.scroll==0);
    delta=sb_motion_step(&motion,0,0,1,1,20,false);
    assert(delta.scroll==480);
    SBChords atomic; sb_init(&atomic,emit,0); atomic.enabled[0]=true;
    assert(isinf(sb_deadline(&atomic)));
    sb_buttons(&atomic,1,0); assert(fabs(sb_deadline(&atomic)-.06)<1e-9);
    sb_buttons(&atomic,3,.02); assert(isinf(sb_deadline(&atomic)));
    sb_reset(&atomic);

#endif
    SBChords s=make(); sb_button(&s,0,true,0); sb_button(&s,0,false,.01); CHECK(1,-1);
    s=make(); s.enabled[0]=true; sb_button(&s,0,true,0); assert(!n); sb_button(&s,0,false,.02); CHECK(1,-1);
    s=make(); s.enabled[0]=true; sb_button(&s,0,true,0); sb_tick(&s,.061); sb_button(&s,0,false,.2); CHECK(1,-1);
    unsigned a[]={0,2,0,1,0,1}, b[]={1,3,2,3,3,2};
    for (int p=0;p<SB_PAIR_COUNT;p++) for(int reverse=0;reverse<2;reverse++) {
        s=make(); s.enabled[p]=true; unsigned x=reverse?b[p]:a[p], y=reverse?a[p]:b[p];
        sb_button(&s,x,true,0); sb_button(&s,y,true,.02); sb_tick(&s,1);
        sb_button(&s,x,false,1.1); sb_button(&s,y,false,1.2);
        int e[]={p+5,-(p+5)}; expect(e,2);
    }
    s=make(); s.enabled[0]=true; sb_button(&s,0,true,0); sb_button(&s,1,true,.1); sb_tick(&s,.2);
    sb_reset(&s); CHECK(1,2,-1,-2); /* Late second press cannot undo first click. */
    s=make(); s.enabled[0]=true; sb_button(&s,0,true,0); sb_flush(&s); sb_button(&s,1,true,.01);
    sb_reset(&s); CHECK(1,-1); /* Movement starts drag immediately; pending second cancels. */
    s=make(); s.enabled[0]=s.enabled[1]=true;
    sb_button(&s,0,true,0); sb_button(&s,1,true,.01); sb_button(&s,2,true,.02); sb_button(&s,3,true,.03);
    sb_reset(&s); CHECK(5,6,-5,-6);
    s=make(); s.enabled[0]=true; sb_button(&s,0,true,0); sb_reset(&s); assert(!n);
    s=make(); sb_button(&s,0,true,0); sb_button(&s,0,true,.01); sb_button(&s,0,false,.02); CHECK(1,-1);
    unsigned random=1234567;
    for(unsigned config=0;config<64;config++) {
        sb_init(&s,audit,0); memset(balances,0,sizeof(balances));
        for(unsigned p=0;p<SB_PAIR_COUNT;p++) s.enabled[p]=!!(config&(1u<<p));
        double time=0;
        for(unsigned i=0;i<10000;i++) {
            random=random*1664525u+1013904223u;
            time+=(random%100)/1000.0;
            unsigned op=(random>>8)%12, button=(random>>16)%4;
            if(op<8) sb_button(&s,button,!!(op&1),time);
            else if(op==8) sb_tick(&s,time);
            else if(op==9) sb_flush(&s);
            else sb_reset(&s);
        }
        sb_reset(&s);
        for(unsigned i=0;i<SB_ACTION_COUNT;i++) assert(balances[i]==0);
    }
    puts("All chord tests passed, including 640,000 randomized transitions across all 64 combo configurations.");
}
