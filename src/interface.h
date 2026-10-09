#import <Cocoa/Cocoa.h>

@interface SBCard : NSView
@end

@interface SBMotionNumberFormatter : NSFormatter
@property double minimumValue;
@property double maximumValue;
@property BOOL integerOnly;
@end

// A template silhouette lets macOS choose the correct menu-bar foreground.
NSImage *SBMenuBarImage(void);
@interface SBBallIndicator : NSView
@property(nonatomic) BOOL active;
@end
