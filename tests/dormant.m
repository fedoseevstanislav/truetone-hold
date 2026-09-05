// Exercise the actual reconciliation path with no external display attached.
#define CGGetOnlineDisplayList testGetOnlineDisplayList
#define main helperMain
#include "../src/truetone-hold.m"
#undef main
#undef CGGetOnlineDisplayList
#include <assert.h>
CGError testGetOnlineDisplayList(uint32_t capacity, CGDirectDisplayID *ids, uint32_t *count) {
    (void)capacity; (void)ids;
    *count = 0;
    return kCGErrorSuccess;
}
int main(void) {
    @autoreleasepool {
        samples = [NSMutableDictionary new];
        held = [NSMutableDictionary new];
        samples[@"disconnected"] = [Sample new];
        held[@"disconnected"] = [Sample new];
        reconcile();
        assert(client == nil && watched == nil);
        assert(powerPort == NULL && powerNotification == 0);
        assert(pending == nil && transitionGuard == nil);
        assert(samples.count == 0 && held.count == 0);
        puts("PASS: no external display leaves no color client, lid listener, timer, or cached readings");
    }
    return 0;
}
