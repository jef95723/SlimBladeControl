#define main slimblade_application_main
#import "../src/main.m"
#undef main
// Read metadata only. Independent manager never opens the HID devices.
int main(void) {
    @autoreleasepool {
        IOHIDManagerRef m=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDManagerOptionIndependentDevices);
        NSDictionary *match=@{@kIOHIDVendorIDKey:@(vendorID),@kIOHIDProductIDKey:@(productID)};
        IOHIDManagerSetDeviceMatching(m,(__bridge CFDictionaryRef)match);
        IOHIDManagerScheduleWithRunLoop(m,CFRunLoopGetMain(),kCFRunLoopDefaultMode);
        IOReturn rc=IOHIDManagerOpen(m,kIOHIDOptionsTypeNone);
        CFSetRef ds=IOHIDManagerCopyDevices(m);
        printf("Discovery open: 0x%08x; matched devices: %ld\n",rc,ds?(long)CFSetGetCount(ds):0L);
        if(ds) {
            for(id obj in (__bridge NSSet *)ds) {
                IOHIDDeviceRef d=(__bridge IOHIDDeviceRef)obj;
                printf("047d:2041 descriptor supported: %s\n",supportedDescriptor(d)?"yes":"no");
            }
            CFRelease(ds);
        }
        IOHIDManagerUnscheduleFromRunLoop(m,CFRunLoopGetMain(),kCFRunLoopDefaultMode);
        IOHIDManagerClose(m,kIOHIDOptionsTypeNone); CFRelease(m);
    }
}
