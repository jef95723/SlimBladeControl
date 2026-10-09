#import <Cocoa/Cocoa.h>

@interface SBShortcutEditor : NSObject <NSWindowDelegate>
- (void)beginForWindow:(NSWindow *)parent action:(NSString *)action completion:(void (^)(NSString *))completion;
- (void)cancel:(id)sender;
@end
