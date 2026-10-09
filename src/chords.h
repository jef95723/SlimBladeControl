#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
enum { SB_BUTTON_COUNT=4, SB_PAIR_COUNT=6, SB_ACTION_COUNT=10 };
typedef void (*SBEmit)(void *, int slot, bool down);
typedef struct {
    uint8_t held, pending, singles, consumed, active;
    double since[4], window;
    bool enabled[SB_PAIR_COUNT];
    SBEmit emit;
    void *context;
} SBChords;
/* Slots 0..3: physical buttons. Combinations: bottom, top, left, right, 1+4, 2+3 pairs (slots 4..9). */
void sb_init(SBChords *, SBEmit, void *);
void sb_button(SBChords *, unsigned button, bool down, double now);
void sb_tick(SBChords *, double now);
void sb_flush(SBChords *);
void sb_reset(SBChords *);

/* Rust static library FFI; all calls must run on the main thread. */
size_t sb_state_size(void);
void sb_buttons(SBChords *, uint8_t held, double now);
double sb_deadline(const SBChords *);
typedef struct { uint8_t buttons; int8_t x, y, wheel; } SBReport;
bool sb_decode_report(const uint8_t *, size_t length, bool swap_upper, SBReport *);
typedef struct { double x, y, scroll; } SBMotion;
typedef struct { double x, y; int32_t scroll; } SBDelta;
SBDelta sb_motion_step(SBMotion *, double x, double y, double wheel, double tracking, double scrolling, bool reverse);
