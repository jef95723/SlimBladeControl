#import <Cocoa/Cocoa.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hidsystem/IOHIDLib.h>
#import <IOKit/hidsystem/IOLLEvent.h>
#import "actions.h"
#import "interface.h"
#import "shortcuts.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ApplicationServices/ApplicationServices.h>
#import <math.h>
#import "chords.h"

static double now(void) { return NSProcessInfo.processInfo.systemUptime; }
static const int vendorID=0x047d, productID=0x2041;
static NSString *const SBScreenLockedNotification=@"com.apple.screenIsLocked";
static NSString *const SBScreenUnlockedNotification=@"com.apple.screenIsUnlocked";
typedef NS_OPTIONS(NSUInteger, SBSuspension) {
    SBSuspensionSleep=1, SBSuspensionSession=2, SBSuspensionLock=4
};

// Core Graphics supplies both generic and left/right modifier bits for real
// key events. Our generated modifiers use the left-side virtual keycodes.
static CGEventFlags syntheticFlags(CGEventFlags flags) {
    if(flags&kCGEventFlagMaskCommand) flags|=NX_DEVICELCMDKEYMASK;
    if(flags&kCGEventFlagMaskControl) flags|=NX_DEVICELCTLKEYMASK;
    if(flags&kCGEventFlagMaskShift) flags|=NX_DEVICELSHIFTKEYMASK;
    if(flags&kCGEventFlagMaskAlternate) flags|=NX_DEVICELALTKEYMASK;
    return flags;
}

@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface Controller : NSObject <NSApplicationDelegate, NSTextFieldDelegate> {
#ifdef SB_TESTING
@public
#endif
    SBChords chords;
    SBMotion motion;
    IOHIDManagerRef manager;
    IOHIDDeviceRef device;
    CGEventSourceRef source;
    BOOL running, mappingsEnabled;
    SBSuspension suspensionReasons;
    double tracking, scrolling;
    uint8_t reportBuffer[64], lastButtons;
    BOOL armed, swapUpper, identify;
    CGEventFlags syntheticModifiers;
    BOOL reverseScroll;
    NSMutableDictionary<NSString *,NSNumber *> *outputs;
    NSMutableDictionary<NSNumber *,NSNumber *> *clickCounts;
    NSMutableDictionary<NSNumber *,NSNumber *> *clickTimes;
    NSMutableDictionary<NSNumber *,NSValue *> *clickPoints;
    NSMutableDictionary<NSNumber *,NSNumber *> *pressCounts;
    NSArray<NSString *> *actions;
    NSArray<NSTextField *> *fields;
    NSMutableArray<NSPopUpButton *> *mappingMenus;
    NSMutableArray<NSButton *> *mappingDetails;
    NSStackView *individualGrid, *pairGrid;
    SBShortcutEditor *shortcutEditor;
    NSSlider *trackingControl, *scrollControl, *chordControl;
    NSButton *reverseControl, *swapControl, *identifyControl, *autoStartControl, *menuBarControl, *dockControl;
    NSButton *applyButton, *pauseButton;
    NSTextField *trackingValue, *scrollValue, *chordValue, *stateLabel;
    NSTabView *tabs;
    NSSegmentedControl *navigation;
    SBBallIndicator *ballIndicator;
    NSMenuItem *menuPause, *menuStart;
    NSTextField *status, *lastInput;
    NSString *statusBeforeValidation;
    NSWindow *window;
    NSStatusItem *statusItem;
    NSTimer *timer, *connectionTimer;
}
- (void)emitSlot:(int)slot down:(BOOL)down;
- (void)attach:(IOHIDDeviceRef)d;
- (void)removed:(IOHIDDeviceRef)d;
- (void)report:(const uint8_t *)bytes length:(CFIndex)length device:(IOHIDDeviceRef)sender;
- (void)inputFailed:(IOHIDDeviceRef)sender;
- (void)discovered:(IOHIDDeviceRef)d manager:(IOHIDManagerRef)sender;
- (void)removed:(IOHIDDeviceRef)d manager:(IOHIDManagerRef)sender;
- (void)reconcileConnection;
- (void)stopDiscovery;
- (void)releaseDevice;
- (void)closeDevice;
- (void)scheduleDeadline;
- (void)moveX:(double)x y:(double)y wheel:(double)w;
- (void)stop;
- (void)start:(id)sender;
- (void)updateActivity;
- (void)openApplicationURL:(NSURL *)url;

@end

static void emit(void *ctx,int slot,bool down) { [(__bridge Controller *)ctx emitSlot:slot down:down]; }
static void added(void *ctx,IOReturn result,void *sender,IOHIDDeviceRef d) {
    if(result==kIOReturnSuccess) [(__bridge Controller *)ctx discovered:d manager:(IOHIDManagerRef)sender];
}
static void removed(void *ctx,IOReturn result,void *sender,IOHIDDeviceRef d) {
    (void)result; [(__bridge Controller *)ctx removed:d manager:(IOHIDManagerRef)sender];
}
static void reportCallback(void *ctx,IOReturn result,void *sender,IOHIDReportType type,uint32_t reportID,uint8_t *bytes,CFIndex length) {
    if(type!=kIOHIDReportTypeInput || reportID!=0) return;
    Controller *controller=(__bridge Controller *)ctx;
    if(result!=kIOReturnSuccess) { [controller inputFailed:(IOHIDDeviceRef)sender]; return; }
    [controller report:bytes length:length device:(IOHIDDeviceRef)sender];
}
// Descriptor read from the attached wired SlimBlade. Refuse unknown layouts
// before taking exclusive ownership; never interpret an arbitrary mouse report.
static BOOL supportedDescriptor(IOHIDDeviceRef d) {
    static const uint8_t bytes[]={0x05,0x01,0x09,0x02,0xa1,0x01,0x09,0x01,0xa1,0x00,0x05,0x09,0x19,0x01,0x29,0x02,0x15,0x00,0x25,0x01,0x95,0x02,0x75,0x01,0x81,0x02,0x95,0x01,0x75,0x06,0x81,0x03,0x05,0x01,0x09,0x30,0x09,0x31,0x09,0x38,0x15,0x81,0x25,0x7f,0x75,0x08,0x95,0x03,0x81,0x06,0x06,0x00,0xff,0x19,0x01,0x29,0x02,0x15,0x00,0x25,0x01,0x95,0x02,0x75,0x01,0x81,0x02,0x95,0x01,0x75,0x06,0x81,0x03,0xc0,0xc0};
    CFTypeRef descriptor=IOHIDDeviceGetProperty(d,CFSTR(kIOHIDReportDescriptorKey));
    return descriptor && CFGetTypeID(descriptor)==CFDataGetTypeID() &&
        [(__bridge NSData *)descriptor isEqualToData:[NSData dataWithBytes:bytes length:sizeof(bytes)]];
}
static CGPoint cursor(void) {
    CGEventRef e=CGEventCreate(NULL); if(!e) return CGPointZero; CGPoint p=CGEventGetLocation(e); CFRelease(e); return p;
}
static CGPoint onScreen(CGPoint p) {
    CGDirectDisplayID ids[32]; uint32_t count=0;
    if(CGGetActiveDisplayList(32,ids,&count)!=kCGErrorSuccess || !count) return p;
    CGPoint best=p; double distance=INFINITY;
    for(uint32_t i=0;i<count;i++) {
        CGRect r=CGDisplayBounds(ids[i]); if(CGRectContainsPoint(r,p)) return p;
        CGPoint q=CGPointMake(fmax(CGRectGetMinX(r),fmin(p.x,CGRectGetMaxX(r)-1)),
                              fmax(CGRectGetMinY(r),fmin(p.y,CGRectGetMaxY(r)-1)));
        double d=hypot(q.x-p.x,q.y-p.y); if(d<distance) {distance=d; best=q;}
    }
    return best;
}

@implementation Controller
- (NSTextField *)label:(NSString *)text {
    NSTextField *v=[NSTextField wrappingLabelWithString:text]; v.font=[NSFont systemFontOfSize:13]; return v;
}
- (NSTextField *)detail:(NSString *)text {
    NSTextField *v=[self label:text]; v.textColor=NSColor.secondaryLabelColor; v.font=[NSFont systemFontOfSize:12]; return v;
}
- (NSTextField *)heading:(NSString *)text {
    NSTextField *v=[self label:text]; v.font=[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold]; return v;
}
- (NSButton *)button:(NSString *)title action:(SEL)action {
    return [NSButton buttonWithTitle:title target:self action:action];
}
- (NSStackView *)row:(NSArray<NSView *> *)views {
    NSStackView *r=[NSStackView stackViewWithViews:views]; r.orientation=NSUserInterfaceLayoutOrientationHorizontal;
    r.spacing=12; r.alignment=NSLayoutAttributeCenterY; r.distribution=NSStackViewDistributionFill; return r;
}
- (NSStackView *)column:(NSArray<NSView *> *)views {
    NSStackView *s=[NSStackView stackViewWithViews:views]; s.orientation=NSUserInterfaceLayoutOrientationVertical;
    s.alignment=NSLayoutAttributeLeading; s.spacing=14; s.detachesHiddenViews=YES; return s;
}
- (void)fill:(NSView *)view in:(NSView *)parent {
    [view.widthAnchor constraintEqualToAnchor:parent.widthAnchor].active=YES;
}
- (NSView *)card:(NSArray<NSView *> *)views {
    SBCard *card=[SBCard new]; NSStackView *stack=[self column:views]; stack.translatesAutoresizingMaskIntoConstraints=NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
      [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20],
      [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
      [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20]]];
    for(NSView *v in views) [self fill:v in:stack];
    return card;
}
- (void)addPage:(NSString *)name views:(NSArray<NSView *> *)views {
    NSScrollView *scrollView=[NSScrollView new]; scrollView.hasVerticalScroller=YES; scrollView.drawsBackground=NO;
    FlippedView *document=[FlippedView new]; document.translatesAutoresizingMaskIntoConstraints=NO;
    scrollView.documentView=document;
    NSStackView *stack=[self column:views]; stack.translatesAutoresizingMaskIntoConstraints=NO;
    [document addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:document.topAnchor constant:8],
      [stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-12],
      [stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:2],
      [stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-2],
      [document.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor]]];
    for(NSView *v in views) [self fill:v in:stack];
    NSTabViewItem *item=[[NSTabViewItem alloc] initWithIdentifier:name]; item.label=name; item.view=scrollView;
    [tabs addTabViewItem:item];
}
- (NSArray<NSString *> *)presetValues {
    return @[@"none",@"mouse:1",@"mouse:2",@"mouse:3",@"mouse:4",@"mouse:5",@"shortcut",@"application",
      @"key:8:cmd",@"key:9:cmd",@"key:126:ctrl",@"key:123:ctrl",@"key:124:ctrl",@"key:33:cmd",@"key:30:cmd"];
}
- (void)refreshMapping:(NSInteger)index {
    NSString *action=fields[index].stringValue;
    NSURL *app=SBApplicationURL(action); BOOL key=[action hasPrefix:@"key:"];
    NSUInteger selected=[[self presetValues] indexOfObject:SBNormalizeAction(action)?:@"none"];
    if(app) selected=7; else if(key && selected==NSNotFound) selected=6;
    [mappingMenus[index] selectItemAtIndex:selected==NSNotFound?0:(NSInteger)selected];
    NSButton *detail=mappingDetails[index]; detail.hidden=!(key || app);
    detail.title=app?app.lastPathComponent.stringByDeletingPathExtension:SBShortcutLabel(action);
    detail.image=[NSImage imageWithSystemSymbolName:app?@"folder":@"pencil" accessibilityDescription:app?@"Choose application":@"Edit shortcut"];
    detail.imagePosition=NSImageRight; detail.toolTip=app?app.path:@"Edit keyboard shortcut";
    detail.accessibilityLabel=[NSString stringWithFormat:@"%@ — %@",app?@"Choose application":@"Edit shortcut",detail.title];
}
- (NSView *)mapping:(NSInteger)index name:(NSString *)name field:(NSTextField *)field {
    (void)field;
    NSPopUpButton *menu=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [menu addItemsWithTitles:@[@"Disabled",@"Left click",@"Right click",@"Middle click",@"Mouse button 4",@"Mouse button 5",
      @"Keyboard shortcut…",@"Open application…",@"Copy",@"Paste",@"Mission Control",@"Previous Space",@"Next Space",@"Browser Back",@"Browser Forward"]];
    menu.accessibilityLabel=[name stringByAppendingString:@" action"];
    menu.tag=index; menu.target=self; menu.action=@selector(preset:); [mappingMenus addObject:menu];
    NSButton *detail=[self button:@"" action:@selector(editMapping:)]; detail.tag=index;
    detail.lineBreakMode=NSLineBreakByTruncatingTail; [mappingDetails addObject:detail];
    NSTextField *label=[self label:name]; label.font=[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    NSStackView *editor=[self column:@[label,menu,detail]]; editor.spacing=5;
    [editor.heightAnchor constraintGreaterThanOrEqualToConstant:76].active=YES;
    [self fill:menu in:editor]; [self fill:detail in:editor];
    NSArray *assets=@[@"button-1",@"button-2",@"button-3",@"button-4",@"pair-12",@"pair-34",@"pair-13",@"pair-24",@"pair-14",@"pair-23"];
    NSString *path=[NSBundle.mainBundle pathForResource:assets[index] ofType:@"png" inDirectory:@"Buttons"];
    NSImage *image=path?[[NSImage alloc] initWithContentsOfFile:path]:nil;
    NSImageView *diagram=[NSImageView imageViewWithImage:image?:[NSImage imageNamed:NSImageNameApplicationIcon]];
    diagram.imageScaling=NSImageScaleProportionallyUpOrDown; diagram.accessibilityLabel=[name stringByAppendingString:@", highlighted in blue"];
    [diagram.widthAnchor constraintEqualToConstant:60].active=YES; [diagram.heightAnchor constraintEqualToConstant:60].active=YES;
    [editor setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *row=[self row:@[diagram,editor]]; row.translatesAutoresizingMaskIntoConstraints=NO;
    SBCard *card=[SBCard new]; [card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
      [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
      [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
      [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12]]];
    [self refreshMapping:index]; return card;
}
- (NSStackView *)mappingGrid:(NSArray<NSView *> *)cards order:(NSArray<NSNumber *> *)order {
    NSMutableArray *rows=[NSMutableArray new];
    for(NSUInteger i=0;i<order.count;i+=2) {
        NSStackView *row=[self row:@[cards[order[i].unsignedIntegerValue],cards[order[i+1].unsignedIntegerValue]]];
        row.distribution=NSStackViewDistributionFillEqually; row.alignment=NSLayoutAttributeTop; [rows addObject:row];
    }
    NSStackView *grid=[self column:rows];
    for(NSView *row in rows) [self fill:row in:grid];
    return grid;
}
- (NSTextField *)numberField:(NSString *)name minimum:(double)minimum maximum:(double)maximum integer:(BOOL)integer {
    NSTextField *field=[NSTextField textFieldWithString:@""];
    SBMotionNumberFormatter *formatter=[SBMotionNumberFormatter new];
    formatter.minimumValue=minimum; formatter.maximumValue=maximum; formatter.integerOnly=integer;
    field.formatter=formatter; field.delegate=self;
    field.font=[NSFont monospacedDigitSystemFontOfSize:15 weight:NSFontWeightMedium];
    field.alignment=NSTextAlignmentRight; field.accessibilityLabel=name;
    field.toolTip=[NSString stringWithFormat:@"%g–%g%@",minimum,maximum,integer?@" ms":@"×"];
    field.target=self; field.action=@selector(motionValueChanged:);
    [(NSTextFieldCell *)field.cell setSendsActionOnEndEditing:YES];
    return field;
}
- (NSView *)motionRow:(NSSlider *)slider value:(NSTextField *)value unit:(NSString *)unit {
    NSTextField *label=[self detail:unit]; [label.widthAnchor constraintEqualToConstant:22].active=YES;
    return [self row:@[slider,value,label]];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    outputs=[NSMutableDictionary new]; clickCounts=[NSMutableDictionary new]; clickTimes=[NSMutableDictionary new];
    clickPoints=[NSMutableDictionary new]; pressCounts=[NSMutableDictionary new];
    source=CGEventSourceCreate(kCGEventSourceStatePrivate);
    sb_init(&chords,emit,(__bridge void *)self);
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    [prefs registerDefaults:@{@"tracking":@1.0,@"scroll":@1.0,@"window":@60,@"autoStart":@YES,@"showMenuBar":@YES,@"showDock":@NO,
      @"reverse":@NO,@"actions":@[@"mouse:1",@"mouse:2",@"mouse:3",@"key:126:ctrl",@"none",@"none",@"none",@"none",@"none",@"none"]}];
    window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,840,760)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    window.title=@"SlimBlade Control"; window.releasedWhenClosed=NO; window.minSize=NSMakeSize(800,680);
    window.backgroundColor=NSColor.windowBackgroundColor;
    NSImageView *icon=[NSImageView imageViewWithImage:[NSImage imageNamed:NSImageNameApplicationIcon]];
    [icon.widthAnchor constraintEqualToConstant:76].active=YES; [icon.heightAnchor constraintEqualToConstant:76].active=YES;
    NSTextField *title=[self label:@"SlimBlade Control"]; title.font=[NSFont systemFontOfSize:27 weight:NSFontWeightBold];
    NSStackView *titles=[self column:@[title,[self detail:@"Your trackball. Your shortcuts."]]]; titles.spacing=5;
    [titles setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    stateLabel=[self heading:@"Paused"]; stateLabel.alignment=NSTextAlignmentRight;
    [stateLabel.widthAnchor constraintEqualToConstant:100].active=YES;
    NSStackView *header=[self row:@[icon,titles,stateLabel]];
    status=[self detail:@"Ready to start your saved mappings."];
    [status.heightAnchor constraintEqualToConstant:34].active=YES;
    navigation=[NSSegmentedControl segmentedControlWithLabels:@[@"Buttons",@"Motion",@"App",@"About"]
      trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(selectPage:)];
    navigation.selectedSegment=0; navigation.segmentStyle=NSSegmentStyleRounded;
    tabs=[NSTabView new]; tabs.tabViewType=NSNoTabsNoBorder;
    [tabs.heightAnchor constraintGreaterThanOrEqualToConstant:390].active=YES;
    [tabs setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];

    NSArray *names=@[@"1 · Bottom left",@"2 · Bottom right",@"3 · Top left",@"4 · Top right",@"1 + 2 · Bottom",@"3 + 4 · Top",@"1 + 3 · Left",@"2 + 4 · Right",@"1 + 4 · Diagonal ↗",@"2 + 3 · Diagonal ↖"];
    NSMutableArray *editors=[NSMutableArray new]; NSArray *saved=SBMigrateActions([prefs arrayForKey:@"actions"]);
    for(NSString *value in saved) [editors addObject:[NSTextField textFieldWithString:value]];
    fields=editors; mappingMenus=[NSMutableArray new]; mappingDetails=[NSMutableArray new];
    NSMutableArray *cards=[NSMutableArray new];
    for(NSInteger i=0;i<SB_ACTION_COUNT;i++) [cards addObject:[self mapping:i name:names[i] field:fields[i]]];
    individualGrid=[self mappingGrid:cards order:@[@2,@3,@0,@1]];
    pairGrid=[self mappingGrid:cards order:@[@4,@5,@6,@7,@8,@9]]; pairGrid.hidden=YES;
    NSSegmentedControl *mappingScope=[NSSegmentedControl segmentedControlWithLabels:@[@"Individual buttons",@"Button combinations"]
      trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(selectMappings:)];
    mappingScope.selectedSegment=0;
    lastInput=[self detail:@"Last pressed: —"];
    [self addPage:@"Buttons" views:@[mappingScope,individualGrid,pairGrid,lastInput,
      [self detail:@"Choose an action, then click its shortcut or app name to edit it. Apply changes when you’re ready."]]];

    trackingControl=[NSSlider sliderWithValue:[prefs doubleForKey:@"tracking"] minValue:.1 maxValue:5 target:self action:@selector(updateLabels:)];
    scrollControl=[NSSlider sliderWithValue:[prefs doubleForKey:@"scroll"] minValue:.1 maxValue:20 target:self action:@selector(updateLabels:)];
    chordControl=[NSSlider sliderWithValue:[prefs doubleForKey:@"window"] minValue:20 maxValue:150 target:self action:@selector(updateLabels:)];
    trackingControl.accessibilityLabel=@"Tracking speed"; scrollControl.accessibilityLabel=@"Scroll speed"; chordControl.accessibilityLabel=@"Combo window in milliseconds";
    trackingValue=[self numberField:@"Pointer speed value" minimum:.1 maximum:5 integer:NO];
    scrollValue=[self numberField:@"Twist scrolling value" minimum:.1 maximum:20 integer:NO];
    chordValue=[self numberField:@"Combination timing value" minimum:20 maximum:150 integer:YES];
    reverseControl=[NSButton checkboxWithTitle:@"Reverse scroll direction" target:nil action:nil];
    reverseControl.state=[prefs boolForKey:@"reverse"]?NSControlStateValueOn:NSControlStateValueOff;
    [self addPage:@"Motion" views:@[
      [self card:@[[self heading:@"Pointer speed"],[self motionRow:trackingControl value:trackingValue unit:@"×"],[self detail:@"0.1–5× · Drag the slider or enter a precise value."]]],
      [self card:@[[self heading:@"Twist scrolling"],[self motionRow:scrollControl value:scrollValue unit:@"×"],reverseControl,[self detail:@"0.1–20× · More range for faster scrolling."]]],
      [self card:@[[self heading:@"Combination timing"],[self motionRow:chordControl value:chordValue unit:@"ms"],[self detail:@"20–150 ms · A longer window makes two-button presses easier. Moving the ball starts a drag immediately."]]]]];
    for(NSSlider *slider in @[trackingControl,scrollControl,chordControl]) {
        [slider.widthAnchor constraintGreaterThanOrEqualToConstant:300].active=YES;
        [slider setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    for(NSTextField *value in @[trackingValue,scrollValue,chordValue]) {
        [value.widthAnchor constraintEqualToConstant:80].active=YES; value.alignment=NSTextAlignmentRight;
    }
    [self updateLabels:nil];

    autoStartControl=[NSButton checkboxWithTitle:@"Start mappings automatically when the app opens" target:self action:@selector(appOptions:)];
    autoStartControl.state=[prefs boolForKey:@"autoStart"]?NSControlStateValueOn:NSControlStateValueOff;
    menuBarControl=[NSButton checkboxWithTitle:@"Show icon in the menu bar" target:self action:@selector(appOptions:)];
    menuBarControl.state=[prefs boolForKey:@"showMenuBar"]?NSControlStateValueOn:NSControlStateValueOff;
    dockControl=[NSButton checkboxWithTitle:@"Show app in the Dock" target:self action:@selector(appOptions:)];
    dockControl.state=[prefs boolForKey:@"showDock"]?NSControlStateValueOn:NSControlStateValueOff;
    swapControl=[NSButton checkboxWithTitle:@"Swap top-left and top-right inputs" target:nil action:nil];
    swapControl.state=[prefs boolForKey:@"swapUpper"]?NSControlStateValueOn:NSControlStateValueOff;
    identifyControl=[NSButton checkboxWithTitle:@"Identify buttons (temporarily suppress clicks and shortcuts)" target:nil action:nil];
    [self addPage:@"App" views:@[
      [self card:@[[self heading:@"Keep it within reach"],autoStartControl,menuBarControl,dockControl,
        [self detail:@"The menu icon’s center turns red when connected. Closing this window keeps your mappings running. Open the app from Applications or Spotlight to return, even when both icons are hidden. Quit stops it."]]],
      [self card:@[[self heading:@"Device & permissions"],[self button:@"Grant permissions…" action:@selector(permissions:)],swapControl,identifyControl,
        [self detail:@"Identification takes effect after Apply. Release the buttons and move the ball, then check Last pressed in Buttons. Use another mouse or the keyboard to turn identification off."],
        [self detail:@"After disabling Kensington’s driver, reconnect the USB cable once. This lets macOS provide basic movement, clicks, and scrolling when this app is quit."]]],
      [self detail:@"App options save immediately. Button and motion changes save when applied."],
      [self button:@"Quit SlimBlade Control" action:@selector(quit:)]]];

    NSString *version=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"";
    NSTextField *author=[self label:@"Jeffrey Liu"]; author.font=[NSFont systemFontOfSize:24 weight:NSFontWeightSemibold];
    [self addPage:@"About" views:@[
      [self card:@[[self heading:@"SlimBlade Control"],
        [self detail:[@"Version " stringByAppendingString:version]],
        [self label:@"Custom buttons, keyboard shortcuts, app launching, and motion controls for the wired Kensington SlimBlade."]]],
      [self card:@[[self detail:@"AUTHOR"],author,
        [self detail:@"© 2026 Jeffrey Liu. Released under the MIT License."]]],
      [self card:@[[self heading:@"Made for your Mac"],
        [self label:@"Native macOS settings with a Rust input engine. Your mappings stay on this Mac. No accounts, analytics, or network connection required."]]]]];

    applyButton=[self button:@"Start mappings" action:@selector(start:)]; applyButton.keyEquivalent=@"\r";
    pauseButton=[self button:@"Pause" action:@selector(pause:)];
    [applyButton.widthAnchor constraintEqualToConstant:132].active=YES;
    [pauseButton.widthAnchor constraintEqualToConstant:70].active=YES;
    NSTextField *footer=[self detail:@"Closing this window keeps mappings running."];
    [footer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *bottom=[self row:@[footer,pauseButton,applyButton]];
    NSStackView *root=[self column:@[header,status,navigation,tabs,bottom]]; root.spacing=12; root.translatesAutoresizingMaskIntoConstraints=NO;
    [window.contentView addSubview:root];
    [NSLayoutConstraint activateConstraints:@[[root.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:24],
      [root.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-24],
      [root.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:18],
      [root.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor constant:-20]]];
    for(NSView *v in @[header,status,navigation,tabs,bottom]) [self fill:v in:root];
    [self configureMenuBar]; [self updateActivity];
    [window center]; [self show:nil];
    NSNotificationCenter *nc=NSWorkspace.sharedWorkspace.notificationCenter;
    for(NSString *name in @[NSWorkspaceWillSleepNotification,NSWorkspaceDidWakeNotification,
        NSWorkspaceSessionDidResignActiveNotification,NSWorkspaceSessionDidBecomeActiveNotification])
        [nc addObserver:self selector:@selector(sessionChanged:) name:name object:nil];
    // Lock/unlock are distributed notifications, separate from fast user switching.
    // These names are not public AppKit constants; the session snapshot also
    // checks the observed lock flag when present, including after missed events.
    NSDistributedNotificationCenter *distributed=NSDistributedNotificationCenter.defaultCenter;
    for(NSString *name in @[SBScreenLockedNotification,SBScreenUnlockedNotification])
        [distributed addObserver:self selector:@selector(sessionChanged:) name:name object:nil
            suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    // Fully initialize output, settings and UI before any exclusive device open.
    [self startAutomaticallyIfEnabled];
}
- (void)startAutomaticallyIfEnabled {
    if(autoStartControl.state==NSControlStateValueOn) [self start:nil];
}
- (void)selectPage:(NSSegmentedControl *)sender { [tabs selectTabViewItemAtIndex:sender.selectedSegment]; }
- (void)showAbout:(id)sender {
    (void)sender; [self show:nil]; navigation.selectedSegment=3; [tabs selectTabViewItemWithIdentifier:@"About"];
}
- (void)selectMappings:(NSSegmentedControl *)sender {
    individualGrid.hidden=sender.selectedSegment!=0; pairGrid.hidden=sender.selectedSegment!=1;
}
- (void)preset:(NSPopUpButton *)sender {
    NSInteger selected=sender.indexOfSelectedItem;
    if(selected==6) { [self editShortcut:sender.tag]; return; }
    if(selected==7) { [self chooseApplication:sender.tag]; return; }
    if(selected>=0 && (NSUInteger)selected<[self presetValues].count) fields[sender.tag].stringValue=[self presetValues][selected];
    [self refreshMapping:sender.tag];
}
- (void)editMapping:(NSButton *)sender {
    if(SBApplicationURL(fields[sender.tag].stringValue)) [self chooseApplication:sender.tag];
    else [self editShortcut:sender.tag];
}
- (void)editShortcut:(NSInteger)index {
    if(window.attachedSheet) return;
    shortcutEditor=[SBShortcutEditor new];
    __weak Controller *weakSelf=self;
    [shortcutEditor beginForWindow:window action:fields[index].stringValue completion:^(NSString *value) {
        Controller *controller=weakSelf; if(!controller) return;
        if(value) controller->fields[index].stringValue=value;
        [controller refreshMapping:index]; controller->shortcutEditor=nil;
    }];
}
- (void)chooseApplication:(NSInteger)index {
    if(window.attachedSheet) return;
    NSOpenPanel *picker=[NSOpenPanel openPanel]; picker.title=@"Choose an application"; picker.prompt=@"Choose App";
    picker.canChooseFiles=YES; picker.canChooseDirectories=NO; picker.allowsMultipleSelection=NO;
    picker.allowedContentTypes=@[UTTypeApplicationBundle]; picker.treatsFilePackagesAsDirectories=NO;
    picker.directoryURL=[NSURL fileURLWithPath:@"/Applications" isDirectory:YES];
    [picker beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if(response==NSModalResponseOK) {
            NSURL *url=picker.URL; NSBundle *bundle=[NSBundle bundleWithURL:url];
            if([[bundle objectForInfoDictionaryKey:@"CFBundlePackageType"] isEqual:@"APPL"]) {
                self->fields[index].stringValue=[@"app:" stringByAppendingString:url.absoluteString];
            } else self->status.stringValue=@"Choose a macOS application (.app).";
        }
        [self refreshMapping:index];
    }];
}
- (void)openApplicationURL:(NSURL *)url {
    NSWorkspaceOpenConfiguration *configuration=[NSWorkspaceOpenConfiguration configuration];
    configuration.activates=YES; configuration.createsNewApplicationInstance=NO;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:configuration completionHandler:^(NSRunningApplication *app,NSError *error) {
        (void)app;
        if(error) dispatch_async(dispatch_get_main_queue(), ^{
            self->status.stringValue=[NSString stringWithFormat:@"Couldn’t open %@. Choose the application again in Buttons.",url.lastPathComponent.stringByDeletingPathExtension];
        });
    }];
}
- (void)updateLabels:(id)sender {
    (void)sender;
    trackingValue.doubleValue=trackingControl.doubleValue; scrollValue.doubleValue=scrollControl.doubleValue;
    chordControl.doubleValue=round(chordControl.doubleValue); chordValue.doubleValue=chordControl.doubleValue;
}
- (void)motionValueChanged:(NSTextField *)sender {
    if(sender==trackingValue) trackingControl.doubleValue=sender.doubleValue;
    else if(sender==scrollValue) scrollControl.doubleValue=sender.doubleValue;
    else if(sender==chordValue) chordControl.doubleValue=sender.doubleValue;
    if(statusBeforeValidation) { status.stringValue=statusBeforeValidation; statusBeforeValidation=nil; }
}
- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error {
    (void)control; (void)string;
    if(!statusBeforeValidation) statusBeforeValidation=status.stringValue;
    status.stringValue=error; return NO;
}
- (void)appOptions:(id)sender {
    (void)sender; NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    [prefs setBool:autoStartControl.state==NSControlStateValueOn forKey:@"autoStart"];
    [prefs setBool:menuBarControl.state==NSControlStateValueOn forKey:@"showMenuBar"];
    [prefs setBool:dockControl.state==NSControlStateValueOn forKey:@"showDock"];
    [NSApp setActivationPolicy:dockControl.state==NSControlStateValueOn?NSApplicationActivationPolicyRegular:NSApplicationActivationPolicyAccessory];
    [self configureMenuBar];
}
- (void)configureMenuBar {
    if(menuBarControl.state!=NSControlStateValueOn) {
        if(statusItem) [NSStatusBar.systemStatusBar removeStatusItem:statusItem];
        statusItem=nil; ballIndicator=nil; menuPause=nil; menuStart=nil; return;
    }
    if(statusItem) return;
    statusItem=[NSStatusBar.systemStatusBar statusItemWithLength:30];
    statusItem.button.image=SBMenuBarImage(); statusItem.button.imagePosition=NSImageOnly;
    ballIndicator=[[SBBallIndicator alloc] initWithFrame:statusItem.button.bounds];
    ballIndicator.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    [statusItem.button addSubview:ballIndicator];
    NSMenu *menu=[NSMenu new];
    for(NSArray *spec in @[@[@"Open Settings…",NSStringFromSelector(@selector(show:))],@[@"Start mappings",NSStringFromSelector(@selector(start:))],@[@"Pause mappings",NSStringFromSelector(@selector(pause:))],@[@"Quit SlimBlade Control",NSStringFromSelector(@selector(quit:))]]) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:spec[0] action:NSSelectorFromString(spec[1]) keyEquivalent:@""];
        item.target=self; [menu addItem:item];
        if(item.action==@selector(pause:)) menuPause=item;
        if(item.action==@selector(start:)) menuStart=item;
    }
    menu.autoenablesItems=NO; statusItem.menu=menu; [self updateActivity];
}
- (void)updateActivity {
    BOOL connected=running && device;
    stateLabel.stringValue=connected?(identify?@"Identifying":@"Active"):(mappingsEnabled?@"Waiting":@"Paused");
    stateLabel.textColor=connected?NSColor.systemRedColor:NSColor.secondaryLabelColor;
    ballIndicator.active=connected;
    statusItem.button.toolTip=[NSString stringWithFormat:@"SlimBlade Control — %@",stateLabel.stringValue?:@"Paused"];
    statusItem.button.accessibilityLabel=statusItem.button.toolTip;
    applyButton.title=mappingsEnabled?@"Apply changes":@"Start mappings"; pauseButton.enabled=mappingsEnabled;
    menuPause.enabled=mappingsEnabled; menuStart.enabled=!mappingsEnabled;
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { (void)app; return NO; }
- (void)show:(id)sender { (void)sender; [NSApp activateIgnoringOtherApps:YES]; [window makeKeyAndOrderFront:nil]; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible {
    (void)app; (void)visible; [self show:nil]; return YES;
}
- (void)quit:(id)sender { (void)sender; [NSApp terminate:nil]; }
- (void)permissions:(id)sender {
    (void)sender; AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent);
    status.stringValue=@"Allow Accessibility and Input Monitoring for SlimBlade Control; relaunch if needed.";
}
- (void)start:(id)sender {
    (void)sender;
    // Commit the focused editor before reading values; invalid input keeps
    // editing active and must not interrupt a working device connection.
    if(window && ![window makeFirstResponder:nil]) return;
    trackingControl.doubleValue=trackingValue.doubleValue;
    scrollControl.doubleValue=scrollValue.doubleValue;
    chordControl.doubleValue=chordValue.doubleValue;
    NSMutableArray *newActions=[NSMutableArray new];
    for(NSTextField *field in fields) {
        NSString *a=SBNormalizeAction(field.stringValue);
        if(!a) { status.stringValue=@"Choose a valid mouse action, keyboard shortcut, or application for each mapping."; return; }
        [newActions addObject:a];
    }
    NSString *error=SBValidateActions(newActions);
    if(error) { status.stringValue=error; return; }
    [self stop];
    actions=newActions; tracking=trackingControl.doubleValue; scrolling=scrollControl.doubleValue;
    reverseScroll=reverseControl.state==NSControlStateValueOn; chords.window=chordControl.doubleValue/1000;
    for(int p=0;p<SB_PAIR_COUNT;p++) chords.enabled[p]=![actions[p+4] isEqual:@"none"];
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    [prefs setObject:actions forKey:@"actions"]; [prefs setDouble:tracking forKey:@"tracking"];
    [prefs setDouble:scrolling forKey:@"scroll"]; [prefs setDouble:chordControl.doubleValue forKey:@"window"];
    [prefs setBool:reverseScroll forKey:@"reverse"];
    swapUpper=swapControl.state==NSControlStateValueOn;
    identify=identifyControl.state==NSControlStateValueOn;
    [prefs setBool:swapUpper forKey:@"swapUpper"];
    for(NSUInteger i=0;i<fields.count;i++) fields[i].stringValue=actions[i];
    mappingsEnabled=YES;
    [self refreshSessionState];
    __weak Controller *weakSelf=self;
    connectionTimer=[NSTimer timerWithTimeInterval:2 repeats:YES block:^(NSTimer *t) {
        (void)t; Controller *controller=weakSelf;
        [controller refreshSessionState]; [controller reconcileConnection];
    }];
    connectionTimer.tolerance=.5;
    [NSRunLoop.mainRunLoop addTimer:connectionTimer forMode:NSRunLoopCommonModes];
    [self reconcileConnection];
}
- (NSDictionary *)currentSession {
    return CFBridgingRelease(CGSessionCopyCurrentDictionary());
}
- (BOOL)accessibilityGranted { return AXIsProcessTrusted(); }
- (BOOL)inputMonitoringGranted { return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)==kIOHIDAccessTypeGranted; }
- (void)refreshSessionState {
    NSDictionary *session=[self currentSession];
    BOOL active=[session[(__bridge NSString *)kCGSessionOnConsoleKey] boolValue] &&
        [session[(__bridge NSString *)kCGSessionLoginDoneKey] boolValue];
    if(active) suspensionReasons &= ~SBSuspensionSession; else suspensionReasons |= SBSuspensionSession;
    // This optional key is not a public API guarantee. Notifications remain the
    // fallback when macOS omits it. Never infer unlocked from a missing key.
    NSNumber *locked=session[@"CGSSessionScreenIsLocked"];
    if(locked) {
        if(locked.boolValue) suspensionReasons |= SBSuspensionLock;
        else suspensionReasons &= ~SBSuspensionLock;
    }
}
- (void)sessionChanged:(NSNotification *)notification {
    if(!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self sessionChanged:notification]; }); return;
    }
    NSString *name=notification.name;
    if([name isEqual:NSWorkspaceWillSleepNotification]) suspensionReasons |= SBSuspensionSleep;
    else if([name isEqual:NSWorkspaceDidWakeNotification]) suspensionReasons &= ~SBSuspensionSleep;
    else if([name isEqual:NSWorkspaceSessionDidResignActiveNotification]) suspensionReasons |= SBSuspensionSession;
    else if([name isEqual:NSWorkspaceSessionDidBecomeActiveNotification]) suspensionReasons &= ~SBSuspensionSession;
    else if([name isEqual:SBScreenLockedNotification]) suspensionReasons |= SBSuspensionLock;
    else if([name isEqual:SBScreenUnlockedNotification]) suspensionReasons &= ~SBSuspensionLock;
    else return;
    [self reconcileConnection];
}
- (void)reconcileConnection {
    if(!mappingsEnabled) return;
    if(suspensionReasons) {
        [self stopDiscovery];
        status.stringValue=@"Mappings will resume automatically after wake or unlock."; return;
    }
    BOOL accessibility=[self accessibilityGranted], inputMonitoring=[self inputMonitoringGranted];
    if(!accessibility || !inputMonitoring) {
        [self stopDiscovery];
        status.stringValue=[NSString stringWithFormat:@"Settings saved. Accessibility: %@ · Input Monitoring: %@. Re-add the app in Settings if an enabled entry belongs to an older build.",accessibility?@"granted":@"needed",inputMonitoring?@"granted":@"needed"]; return;
    }
    if(!source) { [self stop]; status.stringValue=@"Could not create the event source. Relaunch the app."; return; }
    // Resume the applied snapshot; never read or save unfinished UI edits here.
    if(!running) [self beginDiscovery];
    if(running && !device) [self connectAvailableDevice];
    [self updateActivity];
}
- (void)beginDiscovery {
    manager=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDManagerOptionIndependentDevices);
    if(!manager) { status.stringValue=@"Device discovery unavailable. Retrying automatically…"; return; }
    NSDictionary *match=@{@kIOHIDVendorIDKey:@(vendorID),@kIOHIDProductIDKey:@(productID)};
    IOHIDManagerSetDeviceMatching(manager,(__bridge CFDictionaryRef)match);
    IOHIDManagerRegisterDeviceMatchingCallback(manager,added,(__bridge void *)self);
    IOHIDManagerRegisterDeviceRemovalCallback(manager,removed,(__bridge void *)self);
    IOHIDManagerScheduleWithRunLoop(manager,CFRunLoopGetMain(),kCFRunLoopCommonModes);
    // Independent discovery does not implicitly open the device.
    IOReturn result=IOHIDManagerOpen(manager,kIOHIDOptionsTypeNone);
    if(result!=kIOReturnSuccess) {
        [self stopDiscovery]; status.stringValue=@"Device discovery unavailable. Retrying automatically…"; return;
    }
    running=YES;
    status.stringValue=@"Waiting for wired SlimBlade 047d:2041 · reconnect to resume automatically.";
}
- (void)connectAvailableDevice {
    CFSetRef current=manager?IOHIDManagerCopyDevices(manager):NULL;
    if(current) {
        for(id candidate in (__bridge NSSet *)current) [self attach:(__bridge IOHIDDeviceRef)candidate];
        CFRelease(current);
    }
}
- (void)discovered:(IOHIDDeviceRef)d manager:(IOHIDManagerRef)sender {
    if(sender && sender==manager) [self attach:d];
}
- (void)removed:(IOHIDDeviceRef)d manager:(IOHIDManagerRef)sender {
    if(sender && sender==manager) [self removed:d];
}
- (void)attach:(IOHIDDeviceRef)d {
    if(!mappingsEnabled || !running || device || suspensionReasons) return;
    // Device arrival can race the queued session notifications.
    [self refreshSessionState];
    if(suspensionReasons) return;
    if(!supportedDescriptor(d)) { status.stringValue=@"This SlimBlade report layout is unsupported. Device left in native mode."; return; }
    IOReturn result=IOHIDDeviceOpen(d,kIOHIDOptionsTypeSeizeDevice);
    if(result!=kIOReturnSuccess) {
        status.stringValue=[NSString stringWithFormat:@"Waiting to capture SlimBlade (0x%08x). Release other mouse drivers; retrying automatically.",result]; return;
    }
    device=(IOHIDDeviceRef)CFRetain(d); armed=NO; lastButtons=0;
    IOHIDDeviceRegisterInputReportCallback(device,reportBuffer,sizeof(reportBuffer),reportCallback,(__bridge void *)self);
    IOHIDDeviceScheduleWithRunLoop(device,CFRunLoopGetMain(),kCFRunLoopCommonModes);
    status.stringValue=@"Connected · Release all four buttons and move the ball to begin.";
    [self updateActivity];
}
- (void)scheduleDeadline {
    [timer invalidate]; timer=nil;
    double deadline=sb_deadline(&chords);
    if(!running || !isfinite(deadline)) return;
    timer=[NSTimer timerWithTimeInterval:fmax(.001,deadline-now()) repeats:NO block:^(NSTimer *t) {
        (void)t; sb_tick(&self->chords,now()); [self scheduleDeadline];
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}

- (void)removed:(IOHIDDeviceRef)d {
    if(!d || d!=device) return;
    [self releaseDevice];
    status.stringValue=@"SlimBlade disconnected · reconnect to resume automatically.";
}
- (void)releaseDevice {
    [timer invalidate]; timer=nil; sb_reset(&chords);
    [outputs removeAllObjects]; [self syncModifiers];
    [clickTimes removeAllObjects]; [clickCounts removeAllObjects];
    [clickPoints removeAllObjects]; [pressCounts removeAllObjects];
    motion=(SBMotion){0}; armed=NO; lastButtons=0;
    [self closeDevice]; [self updateActivity];
}
- (void)closeDevice {
    if(device) {
        IOHIDDeviceRef closing=device; device=NULL;
        IOHIDDeviceRegisterInputReportCallback(closing,reportBuffer,sizeof(reportBuffer),NULL,NULL);
        IOHIDDeviceUnscheduleFromRunLoop(closing,CFRunLoopGetMain(),kCFRunLoopCommonModes);
        IOHIDDeviceClose(closing,kIOHIDOptionsTypeNone); CFRelease(closing);
    }
}
- (void)stopDiscovery {
    running=NO; [self releaseDevice];
    if(manager) {
        IOHIDManagerRef closing=manager; manager=NULL;
        IOHIDManagerRegisterDeviceMatchingCallback(closing,NULL,NULL);
        IOHIDManagerRegisterDeviceRemovalCallback(closing,NULL,NULL);
        IOHIDManagerUnscheduleFromRunLoop(closing,CFRunLoopGetMain(),kCFRunLoopCommonModes);
        IOHIDManagerClose(closing,kIOHIDOptionsTypeNone); CFRelease(closing);
    }
}
- (void)stop {
    mappingsEnabled=NO; [connectionTimer invalidate]; connectionTimer=nil;
    [self stopDiscovery];
}
- (void)pause:(id)sender { (void)sender; [self stop]; status.stringValue=@"Paused · trackball released. Start mappings to resume."; }
- (void)applicationWillTerminate:(NSNotification *)n {
    (void)n; [shortcutEditor cancel:nil]; [self stop];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
    if(source) CFRelease(source);
}
- (void)inputFailed:(IOHIDDeviceRef)sender {
    if(!sender || sender!=device) return;
    [self releaseDevice];
    status.stringValue=@"Device input interrupted · reconnecting automatically…";
}
- (void)report:(const uint8_t *)bytes length:(CFIndex)length device:(IOHIDDeviceRef)sender {
    if(!running || !device || sender!=device) return;
    SBReport report;
    if(length<0 || !sb_decode_report(bytes,(size_t)length,swapUpper,&report)) { [self inputFailed:sender]; return; }
    if(!armed) {
        if(report.buttons==0) {
            armed=YES;
            status.stringValue=identify?@"Identifying · Press each button; check the number below. Use another pointer to Pause.":@"Active · Kensington SlimBlade 047d:2041";
        }
        [self moveX:report.x y:report.y wheel:report.wheel]; return;
    }
    uint8_t changed=lastButtons^report.buttons;
    if(changed) {
        NSMutableArray *names=[NSMutableArray new];
        for(int b=0;b<4;b++) if(report.buttons&(1<<b)) [names addObject:[NSString stringWithFormat:@"%d",b+1]];
        // Keep the last press visible after release so identification is readable.
        if(names.count) lastInput.stringValue=[NSString stringWithFormat:@"Last pressed: %@%@",[names componentsJoinedByString:@" + "],swapUpper?@" · upper inputs swapped":@""];
        lastButtons=report.buttons;
    }
    if(!identify) sb_buttons(&chords,report.buttons,now());
    [self moveX:report.x y:report.y wheel:report.wheel];
    [self scheduleDeadline];
}
- (CGEventFlags)flags {
    CGEventFlags f=[self physicalFlags];
    for(NSString *a in outputs) if(outputs[a].intValue>0) {
        int mouse; CGKeyCode key; CGEventFlags extra; SBParseAction(a,&mouse,&key,&extra); f |= syntheticFlags(extra);
    }
    return f;
}
- (CGEventFlags)physicalFlags { return CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState); }
- (void)post:(CGEventRef)e { if(e) { CGEventPost(kCGSessionEventTap,e); CFRelease(e); } }
- (void)syncModifiers {
    CGEventFlags desired=0;
    for(NSString *a in outputs) if(outputs[a].intValue>0) {
        int mouse; CGKeyCode key; CGEventFlags flags; SBParseAction(a,&mouse,&key,&flags); desired|=flags;
    }
    const CGEventFlags bits[]={kCGEventFlagMaskCommand,kCGEventFlagMaskControl,kCGEventFlagMaskShift,kCGEventFlagMaskAlternate};
    const CGKeyCode codes[]={55,59,56,58};
    CGEventFlags physical=[self physicalFlags];
    for(int i=0;i<4;i++) if((syntheticModifiers^desired)&bits[i]) {
        BOOL down=(desired&bits[i])!=0;
        syntheticModifiers=(syntheticModifiers&~bits[i])|(desired&bits[i]);
        // A real held modifier already supplies this state. Never release it.
        if(physical&bits[i]) continue;
        CGEventRef e=CGEventCreateKeyboardEvent(source,codes[i],down);
        if(e) { CGEventSetType(e,kCGEventFlagsChanged); CGEventSetFlags(e,physical|syntheticFlags(syntheticModifiers)); [self post:e]; }
    }
}
- (void)emitSlot:(int)slot down:(BOOL)down {
    if(slot<0 || (NSUInteger)slot>=actions.count) return;
    NSString *a=actions[slot]; if([a isEqual:@"none"]) return;
    NSURL *app=SBApplicationURL(a);
    if(app) { if(down) [self openApplicationURL:app]; return; }
    int count=outputs[a].intValue;
    if(down) { outputs[a]=@(count+1); if(count) return; }
    else { if(count<=0) return; outputs[a]=@(count-1); if(count>1) return; }
    int mouse; CGKeyCode key; CGEventFlags extra; SBParseAction(a,&mouse,&key,&extra);
    if(mouse>=0) {
        CGEventType type=mouse==0?(down?kCGEventLeftMouseDown:kCGEventLeftMouseUp):mouse==1?(down?kCGEventRightMouseDown:kCGEventRightMouseUp):(down?kCGEventOtherMouseDown:kCGEventOtherMouseUp);
        CGPoint p=cursor(); NSNumber *b=@(mouse);
        if(down) {
            NSPoint previous=[clickPoints[b] pointValue];
            BOOL repeated=clickTimes[b] && now()-clickTimes[b].doubleValue< NSEvent.doubleClickInterval && hypot(p.x-previous.x,p.y-previous.y)<4;
            clickCounts[b]=@(repeated?clickCounts[b].intValue+1:1); pressCounts[b]=clickCounts[b];
            clickTimes[b]=@(now()); clickPoints[b]=[NSValue valueWithPoint:NSMakePoint(p.x,p.y)];
        }
        CGEventRef e=CGEventCreateMouseEvent(source,type,p,(CGMouseButton)mouse);
        CGEventSetFlags(e,[self flags]); CGEventSetIntegerValueField(e,kCGMouseEventClickState,pressCounts[b].intValue);
        [self post:e];
    } else {
        if(down) [self syncModifiers];
        CGEventRef e=CGEventCreateKeyboardEvent(source,key,down);
        if(e) {
            // Arrow/function/keypad identity is supplied by CGEventCreateKeyboardEvent.
            // Replacing all flags with only Ctrl/Cmd breaks system hotkeys.
            CGEventFlags keyFlags=CGEventGetFlags(e)&(kCGEventFlagMaskNumericPad|kCGEventFlagMaskSecondaryFn);
            CGEventSetFlags(e,keyFlags|[self flags]|syntheticFlags(extra)); [self post:e];
        }
        if(!down) [self syncModifiers];
    }
}
- (void)moveX:(double)x y:(double)y wheel:(double)w {
    if(!running) return;
    SBDelta delta=sb_motion_step(&motion,x,y,w,tracking,scrolling,reverseScroll);
    if(x || y) {
        sb_flush(&chords); // Commit pending clicks before drag motion.
        double moveX=delta.x,moveY=delta.y;
        CGPoint previous=cursor(); CGPoint p=onScreen(CGPointMake(previous.x+moveX,previous.y+moveY));
        moveX=p.x-previous.x; moveY=p.y-previous.y;
        int held=-1;
        for(int b=0;b<5;b++) if(outputs[[NSString stringWithFormat:@"mouse:%d",b+1]].intValue>0) {held=b; break;}
        for(NSNumber *b in pressCounts) {
            NSPoint start=[clickPoints[b] pointValue];
            if(outputs[[NSString stringWithFormat:@"mouse:%d",b.intValue+1]].intValue>0 && hypot(p.x-start.x,p.y-start.y)>=4) [clickTimes removeObjectForKey:b];
        }
        CGEventType type=held<0?kCGEventMouseMoved:held==0?kCGEventLeftMouseDragged:held==1?kCGEventRightMouseDragged:kCGEventOtherMouseDragged;
        CGEventRef e=CGEventCreateMouseEvent(source,type,p,(CGMouseButton)MAX(held,0));
        CGEventSetFlags(e,[self flags]);
        CGEventSetIntegerValueField(e,kCGMouseEventDeltaX,(int64_t)moveX);
        CGEventSetIntegerValueField(e,kCGMouseEventDeltaY,(int64_t)moveY); [self post:e];
    }
    if(w) {
        int32_t pixels=delta.scroll;
        if(pixels) {CGEventRef e=CGEventCreateScrollWheelEvent(source,kCGScrollEventUnitPixel,1,pixels); CGEventSetFlags(e,[self flags]); [self post:e];}
    }
}
@end

int main(int argc,const char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        NSApplication *app=NSApplication.sharedApplication;
        [app setActivationPolicy:[NSUserDefaults.standardUserDefaults boolForKey:@"showDock"]?NSApplicationActivationPolicyRegular:NSApplicationActivationPolicyAccessory];
        Controller *controller=[Controller new]; app.delegate=controller;
        NSMenu *mainMenu=[NSMenu new]; NSMenuItem *appItem=[NSMenuItem new]; [mainMenu addItem:appItem];
        NSMenu *appMenu=[NSMenu new];
        NSMenuItem *about=[appMenu addItemWithTitle:@"About SlimBlade Control" action:@selector(showAbout:) keyEquivalent:@""]; about.target=controller;
        [appMenu addItem:NSMenuItem.separatorItem];
        [appMenu addItemWithTitle:@"Quit SlimBlade Control" action:@selector(terminate:) keyEquivalent:@"q"];
        appItem.submenu=appMenu;
        NSMenuItem *editItem=[[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""]; [mainMenu addItem:editItem];
        NSMenu *edit=[NSMenu new]; editItem.submenu=edit;
        [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
        [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
        [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
        [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
        app.mainMenu=mainMenu; [app run];
    }
    return 0;
}
