// Fake hardware at the API boundary: this test never changes a real display.
#define CGGetDisplayTransferByTable testGetDisplayTransferByTable
#define CGSetDisplayTransferByTable testSetDisplayTransferByTable
#define CGGetOnlineDisplayList testGetOnlineDisplayList
#define IORegistryEntryCreateCFProperty testRegistryProperty
#define main helperMain
#include "../src/truetone-hold.m"
#undef main
#undef CGGetDisplayTransferByTable
#undef CGSetDisplayTransferByTable
#undef CGGetOnlineDisplayList
#undef IORegistryEntryCreateCFProperty
#include <assert.h>
static int reads, writes;
CFTypeRef testRegistryProperty(io_registry_entry_t entry, CFStringRef name, CFAllocatorRef allocator, IOOptionBits options) {
    (void)entry; (void)name; (void)allocator; (void)options;
    return CFRetain(kCFBooleanTrue);
}
CGError testGetOnlineDisplayList(uint32_t capacity, CGDirectDisplayID *ids, uint32_t *count) {
    (void)capacity; ids[0] = 2; *count = 1; return kCGErrorSuccess;
}
CGError testGetDisplayTransferByTable(CGDirectDisplayID d, uint32_t capacity,
    CGGammaValue *r, CGGammaValue *g, CGGammaValue *b, uint32_t *count) {
    (void)d; (void)capacity;
    reads++; *count = 2;
    r[0] = g[0] = b[0] = 0;
    r[1] = 1; g[1] = 0.9f;
    b[1] = reads == 3 ? 1 : 0.8f; // One asynchronous reset.
    return kCGErrorSuccess;
}
CGError testSetDisplayTransferByTable(CGDirectDisplayID d, uint32_t n,
    const CGGammaValue *r, const CGGammaValue *g, const CGGammaValue *b) {
    (void)d; (void)r; (void)g;
    assert(n == 2 && fabs(b[1] - 0.8f) < 0.002);
    writes++;
    return kCGErrorSuccess;
}
int main(void) {
    @autoreleasepool {
        held = [NSMutableDictionary new];
        Sample *s = [Sample new]; float baseline[] = {0, 1};
        s.count = 2; s.gain = @[@1, @0.9, @0.8];
        s.r = s.g = s.b = [NSData dataWithBytes:baseline length:sizeof(baseline)];
        held[key(2)] = s;
        startTransitionGuard();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            assert(transitionGuard == nil);
            assert(reads > 3 && reads <= 76 && writes == 1);
            int stoppedReads = reads;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                assert(reads == stoppedReads);
                puts("PASS: reset repaired once; guard stops and performs no later reads");
                exit(0);
            });
        });
    }
    dispatch_main();
}
