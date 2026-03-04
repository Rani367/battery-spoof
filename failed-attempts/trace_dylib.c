// Trace-only dylib - logs what battery APIs PowerPreferences calls
// No modifications, just logging

#include <IOKit/IOKitLib.h>
#include <IOKit/ps/IOPowerSources.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <unistd.h>

// === IOPSGetPowerSourceDescription ===
typedef CFDictionaryRef (*orig_GetDesc_t)(CFTypeRef, CFTypeRef);
CFDictionaryRef my_IOPSGetPowerSourceDescription(CFTypeRef blob, CFTypeRef ps) {
    orig_GetDesc_t orig = dlsym(RTLD_NEXT, "IOPSGetPowerSourceDescription");
    CFDictionaryRef r = orig(blob, ps);
    fprintf(stderr, "[TRACE:%d] IOPSGetPowerSourceDescription called, result=%p\n", getpid(), r);
    return r;
}

// === IOPSCopyPowerSourcesInfo ===
typedef CFTypeRef (*orig_CopyInfo_t)(void);
CFTypeRef my_IOPSCopyPowerSourcesInfo(void) {
    orig_CopyInfo_t orig = dlsym(RTLD_NEXT, "IOPSCopyPowerSourcesInfo");
    CFTypeRef r = orig();
    fprintf(stderr, "[TRACE:%d] IOPSCopyPowerSourcesInfo called\n", getpid());
    return r;
}

// === IOPSCopyPowerSourcesList ===
typedef CFArrayRef (*orig_CopyList_t)(CFTypeRef);
CFArrayRef my_IOPSCopyPowerSourcesList(CFTypeRef blob) {
    orig_CopyList_t orig = dlsym(RTLD_NEXT, "IOPSCopyPowerSourcesList");
    CFArrayRef r = orig(blob);
    fprintf(stderr, "[TRACE:%d] IOPSCopyPowerSourcesList called\n", getpid());
    return r;
}

// === IOPSGetBatteryHealthState ===
typedef int (*orig_HealthState_t)(void);
int my_IOPSGetBatteryHealthState(void) {
    orig_HealthState_t orig = dlsym(RTLD_NEXT, "IOPSGetBatteryHealthState");
    int r = orig();
    fprintf(stderr, "[TRACE:%d] IOPSGetBatteryHealthState = %d\n", getpid(), r);
    return r;
}

// === IOPSCopyInternalBatteriesArray ===
typedef CFArrayRef (*orig_IntBatt_t)(void);
CFArrayRef my_IOPSCopyInternalBatteriesArray(void) {
    orig_IntBatt_t orig = dlsym(RTLD_NEXT, "IOPSCopyInternalBatteriesArray");
    CFArrayRef r = orig();
    fprintf(stderr, "[TRACE:%d] IOPSCopyInternalBatteriesArray called\n", getpid());
    return r;
}

// === IORegistryEntryCreateCFProperty ===
typedef CFTypeRef (*orig_RegProp_t)(io_registry_entry_t, CFStringRef, CFAllocatorRef, IOOptionBits);
CFTypeRef my_IORegistryEntryCreateCFProperty(io_registry_entry_t e, CFStringRef key, CFAllocatorRef a, IOOptionBits o) {
    orig_RegProp_t orig = dlsym(RTLD_NEXT, "IORegistryEntryCreateCFProperty");
    CFTypeRef r = orig(e, key, a, o);
    char buf[256] = {0};
    if (key && CFStringGetCString(key, buf, sizeof(buf), kCFStringEncodingUTF8)) {
        if (strstr(buf, "apacit") || strstr(buf, "ealth") || strstr(buf, "ominal") || strstr(buf, "ax")) {
            fprintf(stderr, "[TRACE:%d] IORegCreateCFProperty: %s\n", getpid(), buf);
        }
    }
    return r;
}

// === IORegistryEntryCreateCFProperties ===
typedef kern_return_t (*orig_RegProps_t)(io_registry_entry_t, CFMutableDictionaryRef*, CFAllocatorRef, IOOptionBits);
kern_return_t my_IORegistryEntryCreateCFProperties(io_registry_entry_t e, CFMutableDictionaryRef *p, CFAllocatorRef a, IOOptionBits o) {
    orig_RegProps_t orig = dlsym(RTLD_NEXT, "IORegistryEntryCreateCFProperties");
    kern_return_t kr = orig(e, p, a, o);
    if (kr == KERN_SUCCESS && p && *p) {
        if (CFDictionaryGetValue(*p, CFSTR("NominalChargeCapacity"))) {
            fprintf(stderr, "[TRACE:%d] IORegCreateCFProperties: has NominalChargeCapacity\n", getpid());
        }
    }
    return kr;
}

// === IOServiceGetMatchingService ===
typedef io_service_t (*orig_Match_t)(mach_port_t, CFDictionaryRef);
io_service_t my_IOServiceGetMatchingService(mach_port_t port, CFDictionaryRef matching) {
    orig_Match_t orig = dlsym(RTLD_NEXT, "IOServiceGetMatchingService");
    io_service_t r = orig(port, matching);
    fprintf(stderr, "[TRACE:%d] IOServiceGetMatchingService called -> 0x%x\n", getpid(), r);
    return r;
}

// === IOPMCopyBatteryInfo ===
typedef CFArrayRef (*orig_PMBatt_t)(mach_port_t);
CFArrayRef my_IOPMCopyBatteryInfo(mach_port_t port) {
    orig_PMBatt_t orig = dlsym(RTLD_NEXT, "IOPMCopyBatteryInfo");
    CFArrayRef r = orig(port);
    fprintf(stderr, "[TRACE:%d] IOPMCopyBatteryInfo called\n", getpid());
    return r;
}

#define INTERPOSE(func) \
    __attribute__((used)) static struct { const void *r; const void *o; } \
    _ip_##func __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)my_##func, (const void *)func };

INTERPOSE(IOPSGetPowerSourceDescription)
INTERPOSE(IOPSCopyPowerSourcesInfo)
INTERPOSE(IOPSCopyPowerSourcesList)
// These private functions need extern declarations for the INTERPOSE macro
extern int IOPSGetBatteryHealthState(void);
extern CFArrayRef IOPSCopyInternalBatteriesArray(void);
extern CFArrayRef IOPMCopyBatteryInfo(mach_port_t);

INTERPOSE(IOPSGetBatteryHealthState)
INTERPOSE(IOPSCopyInternalBatteriesArray)
INTERPOSE(IORegistryEntryCreateCFProperty)
INTERPOSE(IORegistryEntryCreateCFProperties)
INTERPOSE(IOServiceGetMatchingService)
INTERPOSE(IOPMCopyBatteryInfo)

__attribute__((constructor))
static void init(void) {
    fprintf(stderr, "[TRACE:%d] Battery trace dylib loaded in %s\n", getpid(), getprogname());
}
