// Standalone regression test: compile the real module, substituting only IOKit input.
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <LuaSkin/LuaSkin.h>
#include <string.h>

static const char *scenario;
static IOReturn testCopyAssertions(CFDictionaryRef *output) {
    *output = NULL;
    if (!strcmp(scenario, "error")) return kIOReturnError;
    if (!strcmp(scenario, "null")) return kIOReturnSuccess;
    NSDictionary *value = !strcmp(scenario, "empty") ? @{} :
        @{@123: @[@{@"AssertType": @"PreventUserIdleDisplaySleep", @"AssertLevel": @1}]};
    *output = CFBridgingRetain(value);
    return kIOReturnSuccess;
}
#define IOPMCopyAssertionsByProcess testCopyAssertions
#ifndef CAFFEINATE_SOURCE
#define CAFFEINATE_SOURCE "../../extensions/caffeinate/libcaffeinate.m"
#endif
#include CAFFEINATE_SOURCE
#undef IOPMCopyAssertionsByProcess

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2 || (strcmp(argv[1], "null") && strcmp(argv[1], "error") &&
                         strcmp(argv[1], "empty") && strcmp(argv[1], "populated"))) return 2;
        scenario = argv[1];
        LuaSkin *skin = [LuaSkin sharedWithState:NULL];
        lua_State *L = skin.L;
        luaopen_hs_libcaffeinate(L);
        lua_setglobal(L, "caffeinate");
        const char *check = !strcmp(scenario, "populated") ?
            "local a = caffeinate.currentAssertions(); assert(type(a) == 'table'); "
            "assert(a[123][1].AssertType == 'PreventUserIdleDisplaySleep'); assert(a[123][1].AssertLevel == 1)" :
            "local a = caffeinate.currentAssertions(); assert(type(a) == 'table'); assert(next(a) == nil)";
        for (int i = 0; i < 100; i++) {
            if (luaL_dostring(L, check) != LUA_OK) {
                fprintf(stderr, "%s\n", lua_tostring(L, -1));
                return 1;
            }
        }
        printf("PASS: %s (100 calls)\n", scenario);
        return 0;
    }
}
