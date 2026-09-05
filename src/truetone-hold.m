// Approximate the last True Tone white balance while the lid is closed.
// CoreBrightness is a private, runtime-loaded read interface.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPM.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <signal.h>
#import <math.h>
@interface NSObject (CB)
- (id)copyPropertyForKey:(id)key andDisplay:(unsigned long long)display;
- (void)registerDisplayNotificationCallbackBlock:(void (^)(NSString *, uint64_t, id))block;
- (void)registerNotificationForKey:(id)key andDisplay:(unsigned long long)display;
- (void)unregisterNotificationForKey:(id)key andDisplay:(unsigned long long)display;
- (void)unregisterDisplayNotificationBlock;
@end
@interface Sample:NSObject
@property uint32_t count;
@property NSData *r,*g,*b;
@property NSArray *gain;
@property CGDirectDisplayID display;
@end
@implementation Sample
@end
static int lid(void){
    io_service_t s=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("IOPMrootDomain"));
    if(!s)return -1;
    CFTypeRef v=IORegistryEntryCreateCFProperty(s,CFSTR("AppleClamshellState"),kCFAllocatorDefault,0);
    IOObjectRelease(s);
    if(!v)return -1;
    int result=CFGetTypeID(v)==CFBooleanGetTypeID()?CFBooleanGetValue(v):-1;
    CFRelease(v);
    return result;
}
static NSString *key(CGDirectDisplayID d){
    return [NSString stringWithFormat:@"%u-%u-%u-%u",CGDisplayVendorNumber(d),CGDisplayModelNumber(d),CGDisplaySerialNumber(d),d];
}
static Sample *capture(id client,CGDirectDisplayID d){
    NSDictionary*p=[client copyPropertyForKey:@"ColorRamp" andDisplay:d];
    NSArray*m=p[@"ColorRampTarget"];
    if(m.count!=9)return nil;
    float r[4096],g[4096],b[4096];
    uint32_t n=0;
    if(CGGetDisplayTransferByTable(d,4096,r,g,b,&n)!=kCGErrorSuccess||!n)return nil;
    NSMutableArray *gains=[NSMutableArray new];
    for(int i=0;i<3;i++){
        double v=0;
        for(int j=0;j<3;j++)v+=[m[i*3+j] doubleValue];
        if(!isfinite(v)||v<0.2||v>1.5)return nil;
        [gains addObject:@(pow(fmin(v,1.0),1.0/2.2))];
    }
    Sample*s=[Sample new];
    s.count=n;
    s.r=[NSData dataWithBytes:r length:n*sizeof(float)];
    s.g=[NSData dataWithBytes:g length:n*sizeof(float)];
    s.b=[NSData dataWithBytes:b length:n*sizeof(float)];
    s.gain=gains;
    s.display=d;
    return s;
}
static CGError apply(Sample*s,CGDirectDisplayID d,BOOL tint){
    float r[4096],g[4096],b[4096];
    const float*rr=s.r.bytes,*gg=s.g.bytes,*bb=s.b.bytes;
    for(uint32_t i=0;i<s.count;i++){
        r[i]=rr[i]*(tint?[s.gain[0] floatValue]:1);
        g[i]=gg[i]*(tint?[s.gain[1] floatValue]:1);
        b[i]=bb[i]*(tint?[s.gain[2] floatValue]:1);
    }
    return CGSetDisplayTransferByTable(d,s.count,r,g,b);
}
static NSArray *displays(void){
    CGDirectDisplayID ds[32];
    uint32_t n=0;
    NSMutableArray*a=[NSMutableArray new];
    if(CGGetOnlineDisplayList(32,ds,&n)==0)for(uint32_t i=0;i<n;i++)if(!CGDisplayIsBuiltin(ds[i]))[a addObject:@(ds[i])];
    return a;
}
// All mutable state is confined to the main dispatch queue. No repeating timers.
static NSMutableDictionary<NSString *, Sample *> *samples, *held;
static NSArray<NSNumber *> *watched;
static id client;
static IONotificationPortRef powerPort;
static io_object_t powerNotification;
static dispatch_source_t pending, termSource, intSource, statusSource;
static unsigned long colorEvents;
static BOOL stopping;
static void reconcile(void);

static void scheduleReconcile(double delay) {
    if (stopping) return;
    if (pending) dispatch_source_cancel(pending);
    pending = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    // One coalesced, one-shot timer lets a display/lid transition settle.
    dispatch_source_set_timer(pending, dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC),
                              DISPATCH_TIME_FOREVER, 50 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(pending, ^{
        dispatch_source_cancel(pending);
        pending = nil;
        @autoreleasepool { reconcile(); }
    });
    dispatch_resume(pending);
}

static void unsubscribe(void) {
    for (NSNumber *d in watched)
        [client unregisterNotificationForKey:@"ColorRamp" andDisplay:d.unsignedIntValue];
    [client unregisterDisplayNotificationBlock];
    watched = nil;
    client = nil;
}

static void restore(NSArray<NSNumber *> *online) {
    for (NSNumber *d in online) {
        NSString *k = key(d.unsignedIntValue);
        Sample *s = held[k];
        if (s && apply(s, d.unsignedIntValue, NO) == kCGErrorSuccess) {
            [held removeObjectForKey:k];
            NSLog(@"Restored display %u", d.unsignedIntValue);
        }
    }
}

static void powerChanged(void *refcon, io_service_t service, natural_t message, void *argument) {
    (void)refcon; (void)service; (void)argument;
    if (message != kIOPMMessageClamshellStateChange) return;
    @autoreleasepool {
        if (lid() == 1) {
            // Never replace the last open-lid sample with the neutral closing ramp.
            unsubscribe();
            scheduleReconcile(1.0);
        } else {
            restore(displays());
            scheduleReconcile(0.3);
        }
    }
}

static BOOL watchLid(void) {
    if (powerPort) return YES;
    powerPort = IONotificationPortCreate(kIOMainPortDefault);
    if (!powerPort) return NO;
    IONotificationPortSetDispatchQueue(powerPort, dispatch_get_main_queue());
    io_service_t root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
    kern_return_t result = root ? IOServiceAddInterestNotification(powerPort, root, kIOGeneralInterest,
        powerChanged, NULL, &powerNotification) : KERN_FAILURE;
    if (root) IOObjectRelease(root);
    if (result != KERN_SUCCESS) {
        IONotificationPortDestroy(powerPort);
        powerPort = NULL;
        return NO;
    }
    return YES;
}

static void unwatchLid(void) {
    if (powerNotification) IOObjectRelease(powerNotification);
    powerNotification = 0;
    if (powerPort) IONotificationPortDestroy(powerPort);
    powerPort = NULL;
}

static void subscribe(NSArray<NSNumber *> *online) {
    if ([watched isEqual:online]) return;
    unsubscribe();
    dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW);
    client = [NSClassFromString(@"BrightnessSystemClient") new];
    if (![client respondsToSelector:@selector(registerDisplayNotificationCallbackBlock:)]) {
        client = nil;
        NSLog(@"CoreBrightness notifications unavailable; leaving displays unchanged");
        return;
    }
    watched = [online copy];
    [client registerDisplayNotificationCallbackBlock:^(NSString *property, uint64_t display, id value) {
        if (![property isEqual:@"ColorRamp"]) return;
        // The callback arrives on CoreBrightness's queue. Use the delivered matrix
        // instead of querying every display whenever the ambient light changes.
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                if (stopping || ![watched containsObject:@(display)] || lid() != 0) return;
                Sample *s = samples[key((CGDirectDisplayID)display)];
                NSArray *matrix = [value isKindOfClass:NSDictionary.class] ? value[@"ColorRampTarget"] : nil;
                if (!s || matrix.count != 9) return;
                NSMutableArray *gains = [NSMutableArray new];
                for (int row = 0; row < 3; row++) {
                    double sum = 0;
                    for (int col = 0; col < 3; col++) sum += [matrix[row * 3 + col] doubleValue];
                    if (!isfinite(sum) || sum < 0.2 || sum > 1.5) return;
                    [gains addObject:@(pow(fmin(sum, 1.0), 1.0 / 2.2))];
                }
                s.gain = gains;
                colorEvents++;
            }
        });
    }];
    for (NSNumber *d in watched)
        [client registerNotificationForKey:@"ColorRamp" andDisplay:d.unsignedIntValue];
}

static void reconcile(void) {
    NSArray<NSNumber *> *online = displays();
    if (!online.count) {
        unsubscribe();
        unwatchLid();
        [samples removeAllObjects];
        [held removeAllObjects];
        NSLog(@"Dormant: no external display; only display-connection listener remains");
        return;
    }
    if (!watchLid()) {
        NSLog(@"Cannot register lid notifications; leaving displays unchanged");
        return;
    }
    int closed = lid();
    if (closed < 0) return;
    if (closed) {
        unsubscribe();
        for (NSNumber *d in online) {
            NSString *k = key(d.unsignedIntValue);
            Sample *s = samples[k];
            if (s && apply(s, d.unsignedIntValue, YES) == kCGErrorSuccess) {
                held[k] = s;
                NSLog(@"Holding display %u until next lid/display event", d.unsignedIntValue);
            }
        }
    } else {
        restore(online);
        subscribe(online);
        for (NSNumber *d in online) {
            NSString *k = key(d.unsignedIntValue);
            if (held[k]) continue; // Do not capture a failed restoration as baseline.
            Sample *s = capture(client, d.unsignedIntValue);
            if (s) samples[k] = s;
        }
        NSLog(@"Lid open: watching True Tone changes on %lu external display(s)", online.count);
    }
}

static void displayChanged(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *context) {
    (void)display; (void)context;
    if (flags & kCGDisplayBeginConfigurationFlag) return;
    dispatch_async(dispatch_get_main_queue(), ^{ scheduleReconcile(0.3); });
}

static void shutdownHelper(void) {
    stopping = YES;
    if (pending) dispatch_source_cancel(pending);
    CGDisplayRemoveReconfigurationCallback(displayChanged, NULL);
    unsubscribe();
    unwatchLid();
    restore(displays());
    NSLog(@"Stopped; original gamma restored on connected displays");
    exit(0);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        samples = [NSMutableDictionary new];
        held = [NSMutableDictionary new];
        if (argc > 1 && !strcmp(argv[1], "--self-test")) {
            if (lid() != 0) return 3;
            subscribe(displays());
            int count = 0;
            for (NSNumber *d in displays()) {
                Sample *s = capture(client, d.unsignedIntValue);
                if (!s) continue;
                count++;
                CGError write = apply(s, d.unsignedIntValue, YES);
                float r[4096], g[4096], b[4096]; uint32_t n = 0;
                CGError read = CGGetDisplayTransferByTable(d.unsignedIntValue, 4096, r, g, b, &n);
                BOOL matches = read == 0 && n == s.count && n &&
                    fabs(b[n-1] - ((const float *)s.b.bytes)[n-1] * [s.gain[2] floatValue]) < 0.002;
                CGError reset = apply(s, d.unsignedIntValue, NO);
                NSLog(@"Gamma test: write=%d match=%d restore=%d", write, matches, reset);
                if (write || !matches || reset) return 2;
            }
            unsubscribe();
            return count ? 0 : 3;
        }
        if (CGDisplayRegisterReconfigurationCallback(displayChanged, NULL) != kCGErrorSuccess) return 1;
        signal(SIGTERM, SIG_IGN);
        signal(SIGINT, SIG_IGN);
        signal(SIGUSR1, SIG_IGN);
        termSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        intSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(termSource, ^{ shutdownHelper(); });
        dispatch_source_set_event_handler(intSource, ^{ shutdownHelper(); });
        statusSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGUSR1, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(statusSource, ^{
            NSLog(@"Status: subscribed=%lu cached=%lu held=%lu colorEvents=%lu pendingTransition=%d",
                  watched.count, samples.count, held.count, colorEvents, pending != nil);
        });
        dispatch_resume(statusSource);
        dispatch_resume(termSource);
        dispatch_resume(intSource);
        reconcile();
        NSLog(@"Event-driven helper ready; no polling timer");
    }
    dispatch_main();
}
