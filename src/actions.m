#import "actions.h"
#import "chords.h"
#import <Carbon/Carbon.h>

NSURL *SBApplicationURL(NSString *action) {
    if(![action isKindOfClass:NSString.class] || ![action hasPrefix:@"app:"]) return nil;
    NSURL *url=[NSURL URLWithString:[action substringFromIndex:4]];
    if(!url.isFileURL || (url.host.length && ![url.host isEqual:@"localhost"]) || url.query || url.fragment ||
       ![url.path isAbsolutePath] || [url.path.pathExtension caseInsensitiveCompare:@"app"]!=NSOrderedSame) return nil;
    return [NSURL fileURLWithPath:url.path.stringByStandardizingPath];
}

NSArray<NSString *> *SBMigrateActions(NSArray *saved) {
    NSMutableArray *result=[NSMutableArray new];
    for(NSUInteger i=0;i<SB_ACTION_COUNT;i++) {
        [result addObject:(i<saved.count && [saved[i] isKindOfClass:NSString.class])?saved[i]:@"none"];
    }
    return result;
}
BOOL SBParseAction(NSString *text, int *mouse, CGKeyCode *key, CGEventFlags *flags) {
    *mouse=-1; *key=0; *flags=0;
    if(SBApplicationURL(text)) return YES;
    if([text isEqualToString:@"none"]) return YES;
    NSArray *parts=[text componentsSeparatedByString:@":"];
    if(parts.count==2 && [parts[0] isEqual:@"mouse"]) {
        NSScanner *s=[NSScanner scannerWithString:parts[1]]; int n;
        if(![s scanInt:&n] || !s.isAtEnd || n<1 || n>5) return NO;
        *mouse=n-1; return YES;
    }
    if(parts.count<2 || parts.count>3 || ![parts[0] isEqual:@"key"]) return NO;
    NSScanner *s=[NSScanner scannerWithString:parts[1]]; int n;
    if(![s scanInt:&n] || !s.isAtEnd || n<0 || n>127) return NO;
    *key=(CGKeyCode)n;
    if(parts.count==3 && [parts[2] length]) for(NSString *m in [parts[2] componentsSeparatedByString:@"+"]) {
        if([m isEqual:@"cmd"]) *flags |= kCGEventFlagMaskCommand;
        else if([m isEqual:@"ctrl"]) *flags |= kCGEventFlagMaskControl;
        else if([m isEqual:@"shift"]) *flags |= kCGEventFlagMaskShift;
        else if([m isEqual:@"alt"]) *flags |= kCGEventFlagMaskAlternate;
        else return NO;
    }
    return YES;
}

NSString *SBNormalizeAction(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return nil;
    text=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // Application paths are case-sensitive data, never lowercase them.
    NSURL *app=SBApplicationURL(text);
    if(app) return [@"app:" stringByAppendingString:app.absoluteString];
    if([text.lowercaseString hasPrefix:@"app:"]) return nil;
    text=text.lowercaseString;
    int mouse; CGKeyCode key; CGEventFlags flags;
    if(!SBParseAction(text,&mouse,&key,&flags)) return nil;
    if([text isEqual:@"none"]) return text;
    if(mouse>=0) return [NSString stringWithFormat:@"mouse:%d",mouse+1];
    // Modifier-only keys need different ownership rules and are not shortcuts.
    if(key>=54 && key<=63) return nil;
    NSMutableArray *mods=[NSMutableArray new];
    if(flags&kCGEventFlagMaskCommand) [mods addObject:@"cmd"];
    if(flags&kCGEventFlagMaskControl) [mods addObject:@"ctrl"];
    if(flags&kCGEventFlagMaskShift) [mods addObject:@"shift"];
    if(flags&kCGEventFlagMaskAlternate) [mods addObject:@"alt"];
    return [NSString stringWithFormat:@"key:%u:%@",key,[mods componentsJoinedByString:@"+"]];
}
NSString *SBValidateActions(NSArray<NSString *> *actions) {
    if(actions.count!=SB_ACTION_COUNT) return @"Ten button and combination mappings are required.";
    NSMutableDictionary *keys=[NSMutableDictionary new];
    for(NSString *action in actions) {
        NSString *a=SBNormalizeAction(action);
        if(!a) return @"Choose a mouse action, a keyboard shortcut, or an application for each mapping.";
        if(SBApplicationURL(a)) continue;
        int mouse; CGKeyCode key; CGEventFlags flags;
        SBParseAction(a,&mouse,&key,&flags);
        if(mouse>=0 || [a isEqual:@"none"]) continue;
        if(keys[@(key)] && ![keys[@(key)] isEqual:@(flags)])
            return [NSString stringWithFormat:@"Key %u has different modifiers in two mappings. Use the same shortcut so held actions cannot conflict.",key];
        keys[@(key)]=@(flags);
    }
    return nil;
}

NSString *SBShortcutAction(CGKeyCode key, CGEventFlags flags) {
    NSMutableArray *mods=[NSMutableArray new];
    if(flags&kCGEventFlagMaskCommand) [mods addObject:@"cmd"];
    if(flags&kCGEventFlagMaskControl) [mods addObject:@"ctrl"];
    if(flags&kCGEventFlagMaskShift) [mods addObject:@"shift"];
    if(flags&kCGEventFlagMaskAlternate) [mods addObject:@"alt"];
    return SBNormalizeAction([NSString stringWithFormat:@"key:%u:%@",key,[mods componentsJoinedByString:@"+"]]);
}
NSString *SBKeyLabel(CGKeyCode key) {
    NSDictionary *special=@{@36:@"Return",@48:@"Tab",@49:@"Space",@51:@"Delete",@53:@"Escape",@76:@"Enter",@71:@"Clear",
      @114:@"Help",@115:@"Home",@116:@"Page Up",@117:@"Forward Delete",@119:@"End",@121:@"Page Down",
      @123:@"←",@124:@"→",@125:@"↓",@126:@"↑"};
    if(special[@(key)]) return special[@(key)];
    NSArray *fkeys=@[@122,@120,@99,@118,@96,@97,@98,@100,@101,@109,@103,@111,@105,@107,@113,@106,@64,@79,@80,@90];
    NSUInteger f=[fkeys indexOfObject:@(key)];
    if(f!=NSNotFound) return [NSString stringWithFormat:@"F%lu",(unsigned long)f+1];
    NSString *label=nil;
    TISInputSourceRef source=TISCopyCurrentKeyboardLayoutInputSource();
    CFDataRef data=source?TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData):NULL;
    if(data) {
        const UCKeyboardLayout *layout=(const UCKeyboardLayout *)CFDataGetBytePtr(data);
        UInt32 dead=0; UniChar chars[8]; UniCharCount length=0;
        if(UCKeyTranslate(layout,key,kUCKeyActionDisplay,0,LMGetKbdType(),kUCKeyTranslateNoDeadKeysBit,&dead,8,&length,chars)==noErr && length)
            label=[[NSString stringWithCharacters:chars length:length] uppercaseString];
    }
    if(source) CFRelease(source);
    if(!label.length || [label rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)
        label=[NSString stringWithFormat:@"Key %u",key];
    if(key>=65 && key<=92 && f==NSNotFound) label=[@"Keypad " stringByAppendingString:label];
    return label;
}
NSString *SBShortcutLabel(NSString *action) {
    int mouse; CGKeyCode key; CGEventFlags flags;
    if(![action hasPrefix:@"key:"] || !SBParseAction(action,&mouse,&key,&flags)) return @"Choose shortcut…";
    NSMutableString *label=[NSMutableString new];
    if(flags&kCGEventFlagMaskControl) [label appendString:@"⌃"];
    if(flags&kCGEventFlagMaskAlternate) [label appendString:@"⌥"];
    if(flags&kCGEventFlagMaskShift) [label appendString:@"⇧"];
    if(flags&kCGEventFlagMaskCommand) [label appendString:@"⌘"];
    [label appendString:SBKeyLabel(key)]; return label;
}
