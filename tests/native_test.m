#define SB_TESTING 1
#define main slimblade_application_main
#import "../src/main.m"
#undef main
#include <assert.h>
#import <IOKit/hidsystem/IOLLEvent.h>

// Exercise production event creation while intercepting every post. These tests
// never capture devices, request privacy access, or inject input into the OS.
@interface Recorder : Controller
@property NSMutableArray<NSDictionary *> *recorded;
@property CGEventFlags heldPhysicalFlags;
@property NSMutableArray<NSURL *> *openedURLs;
@end
@implementation Recorder
- (CGEventFlags)physicalFlags { return self.heldPhysicalFlags; }
- (void)openApplicationURL:(NSURL *)url { [self.openedURLs addObject:url]; }
- (void)post:(CGEventRef)e {
    if(!e) return;
    [self.recorded addObject:@{@"type":@(CGEventGetType(e)), @"flags":@(CGEventGetFlags(e)),
      @"key":@(CGEventGetIntegerValueField(e,kCGKeyboardEventKeycode))}];
    CFRelease(e);
}
@end
@interface LaunchRecorder : Recorder
@property NSUInteger starts;
@end
@implementation LaunchRecorder
- (void)start:(id)sender { (void)sender; self.starts++; }
@end
static Recorder *make(NSArray *mappings) {
    Recorder *c=[Recorder new]; c.recorded=[NSMutableArray new];
    c.openedURLs=[NSMutableArray new];
    c->outputs=[NSMutableDictionary new]; c->clickCounts=[NSMutableDictionary new];
    c->clickTimes=[NSMutableDictionary new]; c->clickPoints=[NSMutableDictionary new];
    c->pressCounts=[NSMutableDictionary new]; c->actions=mappings;
    c->source=CGEventSourceCreate(kCGEventSourceStatePrivate);
    c->status=[NSTextField labelWithString:@""]; c->lastInput=[NSTextField labelWithString:@""];
    c->tracking=1; c->scrolling=1;
    sb_init(&c->chords,emit,(__bridge void *)c);
    return c;
}
static void finish(Recorder *c) { [c stop]; if(c->source) CFRelease(c->source); c->source=NULL; }
int main(void) {
    @autoreleasepool {
        assert([SBNormalizeAction(@" KEY:008:shift+cmd+cmd ") isEqual:@"key:8:cmd+shift"]);
        for(NSString *bad in @[@"mouse:0",@"mouse:6",@"key:128",@"key:55",@"key:8:meta",@"key:8:cmd+",@"mouse:1junk"])
            assert(!SBNormalizeAction(bad));
        NSArray *legacy=@[@"mouse:1",@"mouse:1",@"none",@"none",@"none",@"none",@"none",@"none"];
        NSArray *clicks=SBMigrateActions(legacy);
        assert(clicks.count==10 && [[clicks subarrayWithRange:NSMakeRange(0,8)] isEqual:legacy]);
        assert([clicks[8] isEqual:@"none"] && [clicks[9] isEqual:@"none"]);
        assert([SBMigrateActions(clicks) isEqual:clicks]);
        assert(!SBValidateActions(clicks));
        NSMutableArray *conflict=[clicks mutableCopy]; conflict[0]=@"key:8:cmd"; conflict[1]=@"key:8:ctrl";
        assert(SBValidateActions(conflict)); conflict[1]=@"key:8:cmd"; assert(!SBValidateActions(conflict));
        Recorder *c=make(clicks);
        sb_buttons(&c->chords,3,0); assert(c.recorded.count==1);
        sb_buttons(&c->chords,2,.1); assert(c.recorded.count==1);
        sb_buttons(&c->chords,0,.2); assert(c.recorded.count==2);
        assert([c.recorded.lastObject[@"type"] intValue]==kCGEventLeftMouseUp);
        [c.recorded removeAllObjects];
        sb_buttons(&c->chords,1,1); [c stop];
        assert(c.recorded.count==2 && [c.recorded.lastObject[@"type"] intValue]==kCGEventLeftMouseUp);
        finish(c);

        c=make(conflict); c.heldPhysicalFlags=kCGEventFlagMaskShift;
        sb_buttons(&c->chords,3,0);
        assert(c.recorded.count==2); // Cmd modifier, then one shared C down.
        assert([c.recorded[0][@"type"] intValue]==kCGEventFlagsChanged);
        assert([c.recorded[1][@"type"] intValue]==kCGEventKeyDown);
        sb_buttons(&c->chords,2,.1); assert(c.recorded.count==2);
        [c stop]; assert(c.recorded.count==4);
        assert([c.recorded[2][@"type"] intValue]==kCGEventKeyUp);
        assert([c.recorded[3][@"type"] intValue]==kCGEventFlagsChanged);
        assert([c.recorded[3][@"flags"] unsignedLongLongValue]==kCGEventFlagMaskShift);
        assert(c->syntheticModifiers==0); finish(c);

        // macOS system shortcuts must retain arrow-key identity and the
        // device-specific Control bit, not just the generic Control flag.
        for(NSNumber *key in @[@123,@124,@125,@126]) {
            NSArray *shortcut=@[[NSString stringWithFormat:@"key:%@:ctrl",key],@"none",@"none",@"none",@"none",@"none",@"none",@"none"];
            c=make(shortcut);
            sb_buttons(&c->chords,1,0); sb_buttons(&c->chords,0,.1);
            assert(c.recorded.count==4);
            assert(([c.recorded[0][@"flags"] unsignedLongLongValue]&NX_DEVICELCTLKEYMASK)!=0);
            for(int i=1;i<=2;i++) {
                CGEventFlags flags=[c.recorded[i][@"flags"] unsignedLongLongValue];
                assert((flags&kCGEventFlagMaskControl)!=0);
                assert((flags&NX_DEVICELCTLKEYMASK)!=0);
                assert((flags&kCGEventFlagMaskNumericPad)!=0);
                assert((flags&kCGEventFlagMaskSecondaryFn)!=0);
                assert([c.recorded[i][@"key"] intValue]==key.intValue);
            }
            assert([c.recorded[3][@"flags"] unsignedLongLongValue]==0);
            finish(c);
        }

        c=make(clicks); c->running=YES; c->device=(IOHIDDeviceRef)(uintptr_t)1;
        const uint8_t held[]={1,0,0,0,0}, neutral[]={0,0,0,0,0};
        [c report:held length:5 device:c->device]; assert(!c->armed && c.recorded.count==0);
        [c report:neutral length:5 device:c->device]; assert(c->armed);
        [c report:held length:5 device:c->device];
        [c report:held length:5 device:c->device]; assert(c.recorded.count==1);
        [c report:neutral length:5 device:c->device]; assert(c.recorded.count==2);
        c->device=NULL; finish(c);

        assert([SBShortcutAction(49,kCGEventFlagMaskAlternate) isEqual:@"key:49:alt"]);
        assert([SBShortcutLabel(@"key:49:alt") isEqual:@"⌥Space"]);
        assert(!SBShortcutAction(55,kCGEventFlagMaskCommand));
        NSMutableArray *optionSpace=[clicks mutableCopy]; optionSpace[0]=@"key:49:alt";
        c=make(optionSpace); sb_buttons(&c->chords,1,0); sb_buttons(&c->chords,0,.1);
        assert(c.recorded.count==4);
        assert([c.recorded[1][@"key"] intValue]==49);
        assert(([c.recorded[1][@"flags"] unsignedLongLongValue]&NX_DEVICELALTKEYMASK)!=0);
        assert([c.recorded.lastObject[@"flags"] unsignedLongLongValue]==0); finish(c);

        NSString *appAction=@"app:file:///Applications/My%20MixedCase.app";
        assert([SBApplicationURL(SBNormalizeAction(appAction)).path isEqual:@"/Applications/My MixedCase.app"]);
        for(NSString *bad in @[@"app:https://example.com/Test.app",@"app:file://remote/Test.app",@"app:file:///tmp/run.sh",@"app:file:///Applications/Test.app?run=1",@"app:bad"])
            assert(!SBNormalizeAction(bad));
        NSMutableArray *appMappings=[clicks mutableCopy]; appMappings[8]=appAction;
        assert(!SBValidateActions(appMappings)); c=make(appMappings); c->chords.enabled[4]=true;
        sb_buttons(&c->chords,9,0); sb_buttons(&c->chords,9,.01);
        assert(c.openedURLs.count==1 && c.recorded.count==0);
        sb_buttons(&c->chords,0,.02); [c stop]; assert(c.openedURLs.count==1);
        sb_buttons(&c->chords,9,.1); sb_reset(&c->chords);
        assert(c.openedURLs.count==2 && c.recorded.count==0); finish(c);

        // Launch starts saved mappings only when enabled. Closing the settings
        // window must never terminate the background input controller.
        LaunchRecorder *launch=[LaunchRecorder new];
        launch->autoStartControl=[NSButton checkboxWithTitle:@"Auto start" target:nil action:nil];
        launch->autoStartControl.state=NSControlStateValueOn;
        [launch startAutomaticallyIfEnabled]; assert(launch.starts==1);
        launch->autoStartControl.state=NSControlStateValueOff;
        [launch startAutomaticallyIfEnabled]; assert(launch.starts==1);
        assert(![launch applicationShouldTerminateAfterLastWindowClosed:NSApplication.sharedApplication]);
        // Editable motion fields reject partial/invalid input, preserve numeric
        // precision internally, and can drive a slider beyond the old 5x limit.
        NSTextField *number=[launch numberField:@"Scroll" minimum:.1 maximum:20 integer:NO];
        id parsed=nil; NSString *error=nil;
        assert([number.formatter getObjectValue:&parsed forString:@"7.5" errorDescription:&error]);
        assert([parsed doubleValue]==7.5);
        for(NSString *bad in @[@"",@"abc",@"7.5junk",@"nan",@"inf",@"0",@"-1",@"20.01"])
            assert(![number.formatter getObjectValue:&parsed forString:bad errorDescription:&error]);
        assert([number.formatter getObjectValue:&parsed forString:@"20" errorDescription:&error]);
        number.doubleValue=1.499075284090909; assert(number.doubleValue==1.499075284090909);
        launch->scrollValue=number;
        launch->scrollControl=[NSSlider sliderWithValue:5 minValue:.1 maxValue:20 target:nil action:nil];
        number.doubleValue=7.5; [launch motionValueChanged:number]; assert(launch->scrollControl.doubleValue==7.5);
        NSTextField *timing=[launch numberField:@"Timing" minimum:20 maximum:150 integer:YES];
        assert([timing.formatter getObjectValue:&parsed forString:@"75" errorDescription:&error]);
        for(NSString *bad in @[@"19",@"151",@"60.5"])
            assert(![timing.formatter getObjectValue:&parsed forString:bad errorDescription:&error]);
        // Appearance state follows capture, not merely a running discovery loop.
        launch->ballIndicator=[SBBallIndicator new]; launch->running=YES;
        [launch updateActivity]; assert(!launch->ballIndicator.active);
        launch->device=(IOHIDDeviceRef)(uintptr_t)1;
        [launch updateActivity]; assert(launch->ballIndicator.active);
        launch->device=NULL; launch->running=NO;
        [launch updateActivity]; assert(!launch->ballIndicator.active);
        puts("Native tests passed: action validation, saved mapping migration, custom shortcuts, application actions, shared output ownership, modifier release, stop cleanup, startup arming, duplicate reports, automatic launch, window-close policy, numeric input, connection indicator.");
    }
}
