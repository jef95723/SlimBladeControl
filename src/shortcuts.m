#import "shortcuts.h"
#import "actions.h"

@implementation SBShortcutEditor {
    NSPanel *sheet;
    NSPopUpButton *keyMenu;
    NSArray<NSButton *> *modifiers;
    NSTextField *preview;
    NSButton *recordButton;
    id monitor;
    BOOL recording;
    void (^completionHandler)(NSString *);
}
- (NSTextField *)label:(NSString *)text size:(CGFloat)size {
    NSTextField *label=[NSTextField wrappingLabelWithString:text]; label.font=[NSFont systemFontOfSize:size]; return label;
}
- (NSStackView *)stack:(NSArray *)views vertical:(BOOL)vertical {
    NSStackView *stack=[NSStackView stackViewWithViews:views];
    stack.orientation=vertical?NSUserInterfaceLayoutOrientationVertical:NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment=vertical?NSLayoutAttributeLeading:NSLayoutAttributeCenterY;
    stack.distribution=NSStackViewDistributionFill; stack.spacing=12; return stack;
}
- (void)beginForWindow:(NSWindow *)parent action:(NSString *)action completion:(void (^)(NSString *))completion {
    completionHandler=[completion copy];
    sheet=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,560,270) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    sheet.title=@"Keyboard shortcut"; sheet.delegate=self;
    NSTextField *heading=[self label:@"Keyboard shortcut" size:20]; heading.font=[NSFont boldSystemFontOfSize:20];
    preview=[self label:@"" size:24]; preview.font=[NSFont monospacedSystemFontOfSize:24 weight:NSFontWeightMedium];
    recordButton=[NSButton buttonWithTitle:@"Record shortcut…" target:self action:@selector(toggleRecording:)];
    [recordButton.widthAnchor constraintEqualToConstant:170].active=YES;
    NSStackView *recordRow=[self stack:@[preview,recordButton] vertical:NO];
    [preview setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSMutableArray *buttons=[NSMutableArray new];
    for(NSString *title in @[@"⌃ Control",@"⌥ Option",@"⇧ Shift",@"⌘ Command"])
        [buttons addObject:[NSButton checkboxWithTitle:title target:self action:@selector(changed:)]];
    modifiers=buttons;
    keyMenu=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; keyMenu.target=self; keyMenu.action=@selector(changed:); keyMenu.accessibilityLabel=@"Shortcut key";
    // Common navigation keys first, then all other supported physical keys.
    NSMutableOrderedSet *codes=[NSMutableOrderedSet orderedSetWithArray:@[@49,@36,@48,@53,@51,@123,@124,@125,@126]];
    for(int key=0;key<128;key++) if(key<54 || key>63) [codes addObject:@(key)];
    for(NSNumber *code in codes) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:SBKeyLabel(code.unsignedShortValue) action:nil keyEquivalent:@""];
        item.representedObject=code; [keyMenu.menu addItem:item];
    }
    [keyMenu.widthAnchor constraintEqualToConstant:220].active=YES;
    int mouse; CGKeyCode key=49; CGEventFlags flags=0;
    if([action hasPrefix:@"key:"]) SBParseAction(action,&mouse,&key,&flags);
    [self selectKey:key flags:flags];
    NSButton *cancel=[NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)]; cancel.keyEquivalent=@"\e";
    NSButton *save=[NSButton buttonWithTitle:@"Use shortcut" target:self action:@selector(save:)]; save.keyEquivalent=@"\r";
    NSView *spacer=[NSView new]; [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *footer=[self stack:@[spacer,cancel,save] vertical:NO];
    NSTextField *help=[self label:@"Record a shortcut, or choose its modifiers and key below. If macOS reserves a shortcut such as Option–Space, use these controls. Escape cancels recording." size:12];
    help.textColor=NSColor.secondaryLabelColor;
    NSStackView *root=[self stack:@[heading,recordRow,help,[self stack:modifiers vertical:NO],[self stack:@[[self label:@"Key" size:13],keyMenu] vertical:NO],footer] vertical:YES];
    root.translatesAutoresizingMaskIntoConstraints=NO; [sheet.contentView addSubview:root];
    [NSLayoutConstraint activateConstraints:@[[root.leadingAnchor constraintEqualToAnchor:sheet.contentView.leadingAnchor constant:24],
      [root.trailingAnchor constraintEqualToAnchor:sheet.contentView.trailingAnchor constant:-24],
      [root.topAnchor constraintEqualToAnchor:sheet.contentView.topAnchor constant:24],
      [root.bottomAnchor constraintLessThanOrEqualToAnchor:sheet.contentView.bottomAnchor constant:-24]]];
    for(NSView *view in @[recordRow,help,footer]) [view.widthAnchor constraintEqualToAnchor:root.widthAnchor].active=YES;
    [parent beginSheet:sheet completionHandler:^(NSModalResponse response) { (void)response; }];
}
- (CGEventFlags)flags {
    CGEventFlags flags=0;
    const CGEventFlags bits[]={kCGEventFlagMaskControl,kCGEventFlagMaskAlternate,kCGEventFlagMaskShift,kCGEventFlagMaskCommand};
    for(NSUInteger i=0;i<modifiers.count;i++) if(modifiers[i].state==NSControlStateValueOn) flags|=bits[i];
    return flags;
}
- (NSString *)action { return SBShortcutAction([keyMenu.selectedItem.representedObject unsignedShortValue],[self flags]); }
- (void)changed:(id)sender { (void)sender; preview.stringValue=SBShortcutLabel([self action]); }
- (void)selectKey:(CGKeyCode)key flags:(CGEventFlags)flags {
    for(NSMenuItem *item in keyMenu.itemArray) if([item.representedObject unsignedShortValue]==key) { [keyMenu selectItem:item]; break; }
    const CGEventFlags bits[]={kCGEventFlagMaskControl,kCGEventFlagMaskAlternate,kCGEventFlagMaskShift,kCGEventFlagMaskCommand};
    for(NSUInteger i=0;i<modifiers.count;i++) modifiers[i].state=(flags&bits[i])?NSControlStateValueOn:NSControlStateValueOff;
    [self changed:nil];
}
- (void)stopRecording {
    recording=NO;
    if(monitor) { [NSEvent removeMonitor:monitor]; monitor=nil; }
    recordButton.title=@"Record shortcut…";
}
- (void)toggleRecording:(id)sender {
    (void)sender; if(recording) { [self stopRecording]; return; }
    recording=YES; recordButton.title=@"Press shortcut…";
    __weak SBShortcutEditor *weakSelf=self;
    // Local events only. No global key listener, tap, or additional permission.
    monitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        SBShortcutEditor *strongSelf=weakSelf;
        if(!strongSelf || !strongSelf->recording || event.window!=strongSelf->sheet) return event;
        if(event.keyCode==53 && !(event.modifierFlags&(NSEventModifierFlagCommand|NSEventModifierFlagOption|NSEventModifierFlagControl|NSEventModifierFlagShift))) {
            [strongSelf stopRecording]; return nil;
        }
        if(event.isARepeat) return nil;
        if(SBShortcutAction(event.keyCode,(CGEventFlags)event.modifierFlags)) {
            [strongSelf selectKey:event.keyCode flags:(CGEventFlags)event.modifierFlags]; [strongSelf stopRecording];
        }
        return nil;
    }];
}
- (void)windowDidResignKey:(NSNotification *)notification { (void)notification; [self stopRecording]; }
- (void)finish:(NSString *)action {
    [self stopRecording]; [sheet.sheetParent endSheet:sheet]; [sheet orderOut:nil];
    void (^handler)(NSString *)=completionHandler; completionHandler=nil; sheet=nil;
    // Completion may release this editor. Finish all instance work first.
    if(handler) handler(action);
}
- (void)cancel:(id)sender { (void)sender; [self finish:nil]; }
- (void)save:(id)sender { (void)sender; [self finish:[self action]]; }
- (void)dealloc { if(monitor) [NSEvent removeMonitor:monitor]; }
@end
