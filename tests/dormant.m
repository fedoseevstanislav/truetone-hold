// Exercise the actual reconciliation path with no external display attached.
#define CGGetOnlineDisplayList testGetOnlineDisplayList
#define IORegistryEntryCreateCFProperty testRegistryProperty
#define main helperMain
#include "../src/truetone-hold.m"
#undef main
#undef IORegistryEntryCreateCFProperty
#undef CGGetOnlineDisplayList
#include <assert.h>
CGError testGetOnlineDisplayList(uint32_t capacity, CGDirectDisplayID *ids, uint32_t *count) {
    (void)capacity; (void)ids;
    *count = 0;
    return kCGErrorSuccess;
}
CFTypeRef testRegistryProperty(io_registry_entry_t entry, CFStringRef name, CFAllocatorRef allocator, IOOptionBits options) {
    (void)entry; (void)name; (void)allocator; (void)options;
    return CFRetain(kCFBooleanFalse); // Simulate reopening after missed hotplug.
}
int main(void) {
    @autoreleasepool {
        samples = [NSMutableDictionary new];
        held = [NSMutableDictionary new];
        samples[@"disconnected"] = [Sample new];
        held[@"disconnected"] = [Sample new];
        assert(watchLid());
        reconcile();
        assert(client == nil && watched == nil);
        assert(powerPort != NULL && powerNotification != 0);
        assert(pending == nil && transitionGuard == nil);
        assert(samples.count == 0 && held.count == 0);
        powerChanged(NULL, 0, kIOPMMessageClamshellStateChange, NULL);
        assert(pending != nil); // Lid recovery requests fresh connection detection.
        dispatch_source_cancel(pending);
        pending = nil;
        unwatchLid();
        puts("PASS: dormant state has no color client/timer; passive lid listener survives and reopening schedules recovery");
    }
    return 0;
}
