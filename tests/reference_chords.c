#include "../src/chords.h"
#include <string.h>
static const uint8_t pairs[] = {3, 12, 5, 10};
void sb_init(SBChords *s, SBEmit emit, void *context) {
    memset(s, 0, sizeof(*s)); s->emit = emit; s->context = context; s->window = .060;
}
static void single(SBChords *s, unsigned b) {
    uint8_t bit = 1u << b;
    s->pending &= ~bit; s->singles |= bit;
    s->emit(s->context, (int)b, true);
}
void sb_tick(SBChords *s, double now) {
    for (unsigned b=0;b<4;b++)
        if ((s->pending & (1u<<b)) && now-s->since[b]>=s->window) single(s,b);
}
void sb_flush(SBChords *s) {
    for (unsigned b=0;b<4;b++) if (s->pending & (1u<<b)) single(s,b);
}
void sb_button(SBChords *s, unsigned b, bool down, double now) {
    if (b>=4) return;
    uint8_t bit=1u<<b;
    if (!!(s->held & bit)==down) return;
    sb_tick(s,now);
    if (down) {
        s->held |= bit; s->pending |= bit; s->since[b]=now;
        for (unsigned p=0;p<4;p++) {
            uint8_t pair=pairs[p];
            if (s->enabled[p] && (pair & bit) && (s->pending & pair)==pair) {
                s->pending &= ~pair; s->consumed |= pair; s->active |= 1u<<p;
                s->emit(s->context,4+(int)p,true); return;
            }
        }
        bool wait=false;
        for (unsigned p=0;p<4;p++)
            if (s->enabled[p] && (pairs[p]&bit)) wait=true;
        if (!wait || s->window<=0) single(s,b);
    } else {
        s->held &= ~bit;
        if (s->pending & bit) single(s,b); /* Fast tap is never lost. */
        if (s->singles & bit) {
            s->singles &= ~bit; s->emit(s->context,(int)b,false);
        }
        for (unsigned p=0;p<4;p++) if ((s->active&(1u<<p)) && (pairs[p]&bit)) {
            s->active &= ~(1u<<p); s->emit(s->context,4+(int)p,false);
        }
        /* Keep both members consumed until the original pair is fully released.
           A held remainder cannot become a phantom individual click. */
        s->consumed &= s->held;
    }
}
void sb_reset(SBChords *s) {
    for (unsigned b=0;b<4;b++) if (s->singles&(1u<<b)) s->emit(s->context,(int)b,false);
    for (unsigned p=0;p<4;p++) if (s->active&(1u<<p)) s->emit(s->context,4+(int)p,false);
    s->held=s->pending=s->singles=s->consumed=s->active=0;
}
