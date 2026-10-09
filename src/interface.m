#import "interface.h"
#import <math.h>

@implementation SBMotionNumberFormatter
- (NSString *)stringForObjectValue:(id)object {
    if(![object isKindOfClass:NSNumber.class]) return @"";
    return self.integerOnly?[NSString localizedStringWithFormat:@"%.0f",[object doubleValue]]:
      [NSString localizedStringWithFormat:@"%.2f",[object doubleValue]];
}
- (BOOL)getObjectValue:(out id *)object forString:(NSString *)string errorDescription:(out NSString **)error {
    NSScanner *scanner=[NSScanner localizedScannerWithString:[string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    double value=0;
    if(![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value) ||
       value<self.minimumValue || value>self.maximumValue || (self.integerOnly && value!=trunc(value))) {
        if(error) *error=[NSString localizedStringWithFormat:@"Enter %@ between %g and %g.",self.integerOnly?@"a whole number":@"a number",self.minimumValue,self.maximumValue];
        return NO;
    }
    if(object) *object=@(value); return YES;
}
@end

@implementation SBCard
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.wantsLayer=YES; self.layer.cornerRadius=14; self.layer.borderWidth=1;
    }
    return self;
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
    self.layer.backgroundColor=NSColor.controlBackgroundColor.CGColor;
    self.layer.borderColor=[NSColor.separatorColor colorWithAlphaComponent:.25].CGColor;
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES; }
@end

NSImage *SBMenuBarImage(void) {
    NSImage *image=[NSImage imageWithSize:NSMakeSize(22,22) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        (void)rect; [NSColor.blackColor setStroke]; [NSColor.blackColor setFill];
        NSBezierPath *body=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(3.5,1.5,15,19) xRadius:4.5 yRadius:4.5];
        body.lineWidth=1.5; [body stroke];
        NSBezierPath *seams=[NSBezierPath bezierPath]; seams.lineWidth=1;
        [seams moveToPoint:NSMakePoint(11,2)]; [seams lineToPoint:NSMakePoint(11,6.5)];
        [seams moveToPoint:NSMakePoint(11,17.5)]; [seams lineToPoint:NSMakePoint(11,20)];
        [seams moveToPoint:NSMakePoint(4,12)]; [seams lineToPoint:NSMakePoint(5.5,12)];
        [seams moveToPoint:NSMakePoint(16.5,12)]; [seams lineToPoint:NSMakePoint(18,12)]; [seams stroke];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(6.5,7.5,9,9)] fill];
        return YES;
    }];
    image.template=YES; image.accessibilityDescription=@"SlimBlade trackball"; return image;
}
@implementation SBBallIndicator
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
- (BOOL)isAccessibilityElement { return NO; }
- (void)setActive:(BOOL)active { _active=active; self.needsDisplay=YES; }
- (void)drawRect:(NSRect)rect {
    (void)rect; if(!self.active) return;
    [[NSColor colorWithSRGBRed:.94 green:.16 blue:.22 alpha:1] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(self.bounds)-4.5,NSMidY(self.bounds)-3.5,9,9)] fill];
}
@end
