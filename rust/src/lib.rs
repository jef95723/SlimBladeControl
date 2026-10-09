//! Allocation-free combo and motion logic. Cocoa/IOKit call the C ABI on the main thread.
//! No external crates. Unsafe code is limited to validating/dereferencing FFI pointers.
use std::ffi::c_void;

const PAIRS: [u8; 6] = [3, 12, 5, 10, 9, 6];
pub type Emit = extern "C" fn(*mut c_void, i32, bool);

/// Layout mirrored in src/chords.h; checked by the C integration test.
#[repr(C)]
pub struct SBChords {
    held: u8,
    pending: u8,
    singles: u8,
    consumed: u8,
    active: u8,
    since: [f64; 4],
    window: f64,
    enabled: [bool; 6],
    emit: Option<Emit>,
    context: *mut c_void,
}
impl SBChords {
    fn new(emit: Option<Emit>, context: *mut c_void) -> Self {
        Self { held: 0, pending: 0, singles: 0, consumed: 0, active: 0,
            since: [0.; 4], window: 0.060, enabled: [false; 6], emit, context }
    }
    fn output(&self, slot: usize, down: bool) {
        if let Some(callback) = self.emit { callback(self.context, slot as i32, down); }
    }
    fn single(&mut self, b: usize) {
        let bit = 1 << b;
        self.pending &= !bit;
        self.singles |= bit;
        self.output(b, true);
    }
    fn tick(&mut self, now: f64) {
        for b in 0..4 {
            if self.pending & (1 << b) != 0 && now - self.since[b] >= self.window {
                self.single(b);
            }
        }
    }
    fn flush(&mut self) {
        for b in 0..4 { if self.pending & (1 << b) != 0 { self.single(b); } }
    }
    fn button(&mut self, b: usize, down: bool, now: f64) {
        if b >= 4 || !now.is_finite() { return; }
        let bit = 1 << b;
        if (self.held & bit != 0) == down { return; }
        self.tick(now);
        if down {
            self.held |= bit;
            self.pending |= bit;
            self.since[b] = now;
            for (p, &pair) in PAIRS.iter().enumerate() {
                if self.enabled[p] && pair & bit != 0 && self.pending & pair == pair {
                    self.pending &= !pair;
                    self.consumed |= pair;
                    self.active |= 1 << p;
                    self.output(4 + p, true);
                    return;
                }
            }
            let wait = PAIRS.iter().enumerate().any(|(p, pair)| self.enabled[p] && pair & bit != 0);
            if !wait || self.window <= 0. { self.single(b); }
        } else {
            self.held &= !bit;
            if self.pending & bit != 0 { self.single(b); }
            if self.singles & bit != 0 {
                self.singles &= !bit;
                self.output(b, false);
            }
            for (p, &pair) in PAIRS.iter().enumerate() {
                if self.active & (1 << p) != 0 && pair & bit != 0 {
                    self.active &= !(1 << p);
                    self.output(4 + p, false);
                }
            }
            self.consumed &= self.held;
        }
    }
    fn reset(&mut self) {
        for b in 0..4 { if self.singles & (1 << b) != 0 { self.output(b, false); } }
        for p in 0..PAIRS.len() { if self.active & (1 << p) != 0 { self.output(4 + p, false); } }
        self.held = 0; self.pending = 0; self.singles = 0; self.consumed = 0; self.active = 0;
    }
    fn buttons(&mut self, held: u8, now: f64) {
        if !now.is_finite() { return; }
        // Release the old state first: a release and another press in the same
        // USB report must never invent a two-button chord.
        for b in 0..4 { if held & (1 << b) == 0 { self.button(b, false, now); } }
        for b in 0..4 { if held & (1 << b) != 0 { self.button(b, true, now); } }
    }
    fn deadline(&self) -> f64 {
        (0..4).filter(|b| self.pending & (1 << b) != 0)
            .map(|b| self.since[b] + self.window).fold(f64::INFINITY, f64::min)
    }
}

// FFI contract: pointers must reference aligned, live C-layout objects. All calls
// are serialized on the main thread. Callback must not re-enter this engine,
// free its storage, or unwind/throw. sb_init requires uninitialized writable
// storage; subsequent calls require successful initialization. Null is ignored.
#[no_mangle]
pub unsafe extern "C" fn sb_init(s: *mut SBChords, emit: Option<Emit>, context: *mut c_void) {
    if !s.is_null() { unsafe { s.write(SBChords::new(emit, context)); } }
}
#[no_mangle]
pub unsafe extern "C" fn sb_button(s: *mut SBChords, b: u32, down: bool, now: f64) {
    if let Some(s) = unsafe { s.as_mut() } { s.button(b as usize, down, now); }
}
#[no_mangle]
pub unsafe extern "C" fn sb_tick(s: *mut SBChords, now: f64) {
    if !now.is_finite() { return; }
    if let Some(s) = unsafe { s.as_mut() } { s.tick(now); }
}
#[no_mangle]
pub unsafe extern "C" fn sb_flush(s: *mut SBChords) {
    if let Some(s) = unsafe { s.as_mut() } { s.flush(); }
}
#[no_mangle]
pub unsafe extern "C" fn sb_reset(s: *mut SBChords) {
    if let Some(s) = unsafe { s.as_mut() } { s.reset(); }
}
#[no_mangle]
pub extern "C" fn sb_state_size() -> usize { std::mem::size_of::<SBChords>() }

#[no_mangle]
pub unsafe extern "C" fn sb_buttons(s: *mut SBChords, held: u8, now: f64) {
    if let Some(s) = unsafe { s.as_mut() } { s.buttons(held & 15, now); }
}
#[no_mangle]
pub unsafe extern "C" fn sb_deadline(s: *const SBChords) -> f64 {
    unsafe { s.as_ref() }.map_or(f64::INFINITY, SBChords::deadline)
}

/// The five-byte report from the verified 047d:2041 descriptor (no report ID).
/// Caller must validate the descriptor before using this device-specific decoder.
#[repr(C)]
#[derive(Default, Debug, PartialEq)]
pub struct SBReport { pub buttons: u8, pub x: i8, pub y: i8, pub wheel: i8 }
#[no_mangle]
pub unsafe extern "C" fn sb_decode_report(bytes: *const u8, len: usize, swap: bool, out: *mut SBReport) -> bool {
    if bytes.is_null() || out.is_null() || len != 5 { return false; }
    let bytes = unsafe { std::slice::from_raw_parts(bytes, len) };
    let upper = if swap { ((bytes[4] & 1) << 1) | ((bytes[4] & 2) >> 1) } else { bytes[4] & 3 };
    unsafe { out.write(SBReport { buttons: (bytes[0] & 3) | (upper << 2),
        x: bytes[1] as i8, y: bytes[2] as i8, wheel: bytes[3] as i8 }); }
    true
}

#[repr(C)]
#[derive(Default)]
pub struct SBMotion { x: f64, y: f64, scroll: f64 }
#[repr(C)]
#[derive(Default, Debug)]
pub struct SBDelta { pub x: f64, pub y: f64, pub scroll: i32 }
impl SBMotion {
    fn step(&mut self, x: f64, y: f64, wheel: f64, tracking: f64, scrolling: f64, reverse: bool) -> SBDelta {
        if ![x,y,wheel,tracking,scrolling].iter().all(|v| v.is_finite()) { return SBDelta::default(); }
        self.x += x.clamp(-32768.,32767.) * tracking.clamp(0.1,5.);
        self.y += y.clamp(-32768.,32767.) * tracking.clamp(0.1,5.);
        self.scroll += wheel.clamp(-32768.,32767.) * 24. * scrolling.clamp(0.1,20.) * if reverse {-1.} else {1.};
        let result = SBDelta {x:self.x.trunc(), y:self.y.trunc(), scroll:self.scroll.trunc() as i32};
        self.x -= result.x; self.y -= result.y; self.scroll -= f64::from(result.scroll);
        result
    }
}
#[no_mangle]
pub unsafe extern "C" fn sb_motion_step(s: *mut SBMotion, x: f64, y: f64, wheel: f64, tracking: f64, scrolling: f64, reverse: bool) -> SBDelta {
    match unsafe { s.as_mut() } {
        Some(s) => s.step(x,y,wheel,tracking,scrolling,reverse),
        None => SBDelta::default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    extern "C" fn collect(context: *mut c_void, slot: i32, down: bool) {
        let log = unsafe { &mut *(context as *mut Vec<i32>) };
        log.push((slot+1) * if down {1} else {-1});
    }
    #[test]
    fn every_pair_both_orders() {
        for (p, &(a,b)) in [(0,1),(2,3),(0,2),(1,3),(0,3),(1,2)].iter().enumerate() {
            for (first,second) in [(a,b),(b,a)] {
                let mut log = Vec::<i32>::new();
                let mut s=SBChords::new(Some(collect), &mut log as *mut _ as *mut c_void);
                s.enabled[p]=true;
                s.button(first,true,0.); s.button(second,true,0.02);
                s.button(first,false,0.04); s.button(second,false,0.05);
                assert_eq!(log, vec![(p+5) as i32,-((p+5) as i32)]);
            }
        }
    }
    #[test]
    fn fractional_motion_and_scroll() {
        let mut s=SBMotion::default();
        for _ in 0..3 { let d=s.step(1.,-1.,0.,0.25,1.,false); assert_eq!((d.x,d.y),(0.,0.)); }
        let d=s.step(1.,-1.,1.,0.25,0.5,false);
        assert_eq!((d.x,d.y,d.scroll),(1.,-1.,12));
        assert_eq!(s.step(0.,0.,1.,1.,2.,true).scroll,-48);
        assert_eq!(s.step(f64::NAN,0.,0.,1.,1.,false).x,0.);
    }
    #[test]
    fn extended_scroll_range() {
        let mut s=SBMotion::default();
        assert_eq!(s.step(0.,0.,1.,1.,7.5,false).scroll,180);
        assert_eq!(s.step(0.,0.,1.,1.,20.,false).scroll,480);
        assert_eq!(s.step(0.,0.,-1.,1.,20.,true).scroll,480);
        assert_eq!(s.step(0.,0.,1.,1.,100.,false).scroll,480);
        // Raising the scroll ceiling must not change the pointer ceiling.
        assert_eq!(s.step(1.,-1.,0.,20.,20.,false).x,5.);
    }
    #[test]
    fn tap_drag_and_reset() {
        let mut log=Vec::<i32>::new();
        let mut s=SBChords::new(Some(collect), &mut log as *mut _ as *mut c_void);
        s.enabled[0]=true;
        s.button(0,true,0.); s.button(0,false,0.01);
        assert_eq!(log,vec![1,-1]); log.clear();
        s.button(0,true,1.); s.flush(); s.reset();
        assert_eq!(log,vec![1,-1]); log.clear();
        s.button(0,true,2.); s.reset(); assert!(log.is_empty());
    }
    #[test]
    fn report_replacement_does_not_invent_chord() {
        let mut log=Vec::<i32>::new();
        let mut s=SBChords::new(Some(collect), &mut log as *mut _ as *mut c_void);
        s.enabled[0]=true;
        assert!(s.deadline().is_infinite());
        s.buttons(1, 1.);
        assert_eq!(s.deadline(), 1.06);
        s.buttons(2, 1.02);
        s.buttons(0, 1.03);
        assert_eq!(log, vec![1,-1,2,-2]);
        assert!(s.deadline().is_infinite());
    }
    #[test]
    fn atomic_pair_duplicate_reports_and_repress() {
        let mut log=Vec::<i32>::new();
        let mut s=SBChords::new(Some(collect), &mut log as *mut _ as *mut c_void);
        s.enabled=[true;6];
        s.buttons(3, 0.); s.buttons(3, 0.01);
        assert!(s.deadline().is_infinite());
        s.buttons(2, 0.02); s.buttons(3, 0.03); s.buttons(0, 0.04);
        assert_eq!(log, vec![5,-5,1,-1]);
    }
    #[test]
    fn decode_signed_report_and_swap() {
        let bytes=[0xfd,0x81,0x7f,0xff,0xfd];
        let mut r=SBReport::default();
        unsafe {
            assert!(sb_decode_report(bytes.as_ptr(),5,false,&mut r));
            assert_eq!(r,SBReport{buttons:5,x:-127,y:127,wheel:-1});
            assert!(sb_decode_report(bytes.as_ptr(),5,true,&mut r));
            assert_eq!(r.buttons,9);
            assert!(!sb_decode_report(bytes.as_ptr(),4,false,&mut r));
            assert!(!sb_decode_report(std::ptr::null(),5,false,&mut r));
        }
    }
}
