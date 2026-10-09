#import <Cocoa/Cocoa.h>
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc!=2) return 1;
        NSString *directory=@(argv[1]);
        for(NSNumber *size in @[@16,@32,@128,@256,@512]) for(int scale=1;scale<=2;scale++) {
            NSInteger pixels=size.integerValue*scale;
            NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:pixels pixelsHigh:pixels bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            [NSGraphicsContext saveGraphicsState];
            NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
            NSAffineTransform *transform=[NSAffineTransform transform]; [transform scaleBy:pixels/1024.0]; [transform concat];
            NSBezierPath *tile=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(52,52,920,920) xRadius:205 yRadius:205];
            [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithRed:.16 green:.21 blue:.29 alpha:1] endingColor:[NSColor colorWithRed:.05 green:.08 blue:.13 alpha:1]] drawInBezierPath:tile angle:-90];
            [[NSColor colorWithWhite:.65 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(175,155,674,710) xRadius:155 yRadius:155] fill];
            [[NSColor colorWithWhite:.12 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(190,170,644,680) xRadius:145 yRadius:145] fill];
            [[NSColor colorWithWhite:.46 alpha:1] setStroke];
            NSBezierPath *lines=[NSBezierPath bezierPath]; lines.lineWidth=12;
            [lines moveToPoint:NSMakePoint(512,180)]; [lines lineToPoint:NSMakePoint(512,835)];
            [lines moveToPoint:NSMakePoint(200,510)]; [lines lineToPoint:NSMakePoint(824,510)]; [lines stroke];
            [[NSColor colorWithWhite:.04 alpha:1] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(286,286,452,452)] fill];
            NSBezierPath *ball=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(310,310,404,404)];
            [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithRed:.95 green:.24 blue:.32 alpha:1] endingColor:[NSColor colorWithRed:.38 green:.025 blue:.095 alpha:1]] drawInBezierPath:ball angle:-65];
            [[NSColor colorWithWhite:1 alpha:.28] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(387,584,110,62)] fill];
            [NSGraphicsContext restoreGraphicsState];
            NSString *name=[NSString stringWithFormat:@"icon_%@x%@%@.png",size,size,scale==2?@"@2x":@""];
            NSData *data=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            if(![data writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES]) return 2;
        }
    }
}
