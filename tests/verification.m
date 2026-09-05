#define CGGetDisplayTransferByTable testGetDisplayTransferByTable
#define main helperMain
#include "../src/truetone-hold.m"
#undef main
#undef CGGetDisplayTransferByTable
#include <assert.h>
static float testBlue = 0.8f;
CGError testGetDisplayTransferByTable(CGDirectDisplayID display, uint32_t capacity,
    CGGammaValue *r, CGGammaValue *g, CGGammaValue *b, uint32_t *count) {
    (void)display; (void)capacity;
    *count = 2;
    r[0] = g[0] = b[0] = 0;
    r[1] = 1; g[1] = 0.9f; b[1] = testBlue;
    return kCGErrorSuccess;
}
int main(void) {
    @autoreleasepool {
        float baseline[] = {0, 1};
        Sample *s = [Sample new];
        s.count = 2;
        s.r = s.g = s.b = [NSData dataWithBytes:baseline length:sizeof(baseline)];
        s.gain = @[@1, @0.9, @0.8];
        assert(correctionMatches(s, 1));
        testBlue = 1; // Simulate a macOS reset of the corrected output.
        assert(!correctionMatches(s, 1));
        testBlue = NAN;
        assert(!correctionMatches(s, 1));
        puts("PASS: verification distinguishes held correction from reset or invalid gamma");
    }
    return 0;
}
