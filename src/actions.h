#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
BOOL SBParseAction(NSString *text, int *mouse, CGKeyCode *key, CGEventFlags *flags);
NSString *SBNormalizeAction(NSString *text);
NSString *SBValidateActions(NSArray<NSString *> *actions);
NSURL *SBApplicationURL(NSString *action);
NSArray<NSString *> *SBMigrateActions(NSArray *saved);
NSString *SBShortcutAction(CGKeyCode key, CGEventFlags flags);
NSString *SBShortcutLabel(NSString *action);
NSString *SBKeyLabel(CGKeyCode key);
