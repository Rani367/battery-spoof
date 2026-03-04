// Minimal interpose - only active in PowerPreferences, only hooks 2 functions
#include <IOKit/IOKitLib.h>
#include <IOKit/ps/IOPowerSources.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <unistd.h>

#define FAKE_PCT 65
#define DESIGN_CAP 4563
#define FAKE_NOMINAL ((DESIGN_CAP * FAKE_PCT) / 100)

static int is_target_process(void) {
    static int cached = -1;
    if (cached == -1) {
        const char *name = getprogname();
        cached = (name && strcmp(name, "PowerPreferences") == 0) ? 1 : 0;
    }
    return cached;
}

// Hook IORegistryEntryCreateCFProperty
typedef CFTypeRef (*orig_prop_t)(io_registry_entry_t, CFStringRef, CFAllocatorRef, IOOptionBits);
CFTypeRef my_IORegistryEntryCreateCFProperty(io_registry_entry_t e, CFStringRef key, CFAllocatorRef a, IOOptionBits o) {
    orig_prop_t orig = dlsym(RTLD_NEXT, "IORegistryEntryCreateCFProperty");
    CFTypeRef r = orig(e, key, a, o);
    if (!is_target_process() || !r || !key) return r;
    char buf[256] = {0};
    if (CFStringGetCString(key, buf, sizeof(buf), kCFStringEncodingUTF8)) {
        if (strcmp(buf, "NominalChargeCapacity") == 0 || strcmp(buf, "AppleRawMaxCapacity") == 0) {
            int fake = FAKE_NOMINAL;
            CFNumberRef fn = CFNumberCreate(NULL, kCFNumberSInt32Type, &fake);
            fprintf(stderr, "[SPOOF] %s: %s -> %d\n", getprogname(), buf, fake);
            CFRelease(r);
            return fn;
        }
        // Log all property reads for debugging
        fprintf(stderr, "[TRACE] IORegProp: %s\n", buf);
    }
    return r;
}

// Hook IORegistryEntryCreateCFProperties (bulk)
typedef kern_return_t (*orig_props_t)(io_registry_entry_t, CFMutableDictionaryRef*, CFAllocatorRef, IOOptionBits);
kern_return_t my_IORegistryEntryCreateCFProperties(io_registry_entry_t e, CFMutableDictionaryRef *p, CFAllocatorRef a, IOOptionBits o) {
    orig_props_t orig = dlsym(RTLD_NEXT, "IORegistryEntryCreateCFProperties");
    kern_return_t kr = orig(e, p, a, o);
    if (!is_target_process() || kr != KERN_SUCCESS || !p || !*p) return kr;
    if (CFDictionaryGetValue(*p, CFSTR("NominalChargeCapacity"))) {
        int fake = FAKE_NOMINAL;
        CFNumberRef fn = CFNumberCreate(NULL, kCFNumberSInt32Type, &fake);
        CFDictionarySetValue(*p, CFSTR("NominalChargeCapacity"), fn);
        CFDictionarySetValue(*p, CFSTR("AppleRawMaxCapacity"), fn);
        CFRelease(fn);
        fprintf(stderr, "[SPOOF] %s: bulk NominalChargeCapacity -> %d\n", getprogname(), fake);
    }
    return kr;
}

// Hook IOPSCopyPowerSourcesInfo
typedef CFTypeRef (*orig_info_t)(void);
CFTypeRef my_IOPSCopyPowerSourcesInfo(void) {
    orig_info_t orig = dlsym(RTLD_NEXT, "IOPSCopyPowerSourcesInfo");
    CFTypeRef r = orig();
    if (is_target_process()) fprintf(stderr, "[TRACE] IOPSCopyPowerSourcesInfo called\n");
    return r;
}

// Hook IOPSGetPowerSourceDescription
typedef CFDictionaryRef (*orig_desc_t)(CFTypeRef, CFTypeRef);
CFDictionaryRef my_IOPSGetPowerSourceDescription(CFTypeRef blob, CFTypeRef ps) {
    orig_desc_t orig = dlsym(RTLD_NEXT, "IOPSGetPowerSourceDescription");
    CFDictionaryRef r = orig(blob, ps);
    if (!is_target_process() || !r) return r;
    fprintf(stderr, "[TRACE] IOPSGetPowerSourceDescription called\n");
    // Log all keys in the dictionary
    CFIndex count = CFDictionaryGetCount(r);
    const void **keys = malloc(sizeof(void*) * count);
    const void **vals = malloc(sizeof(void*) * count);
    CFDictionaryGetKeysAndValues(r, keys, vals);
    for (CFIndex i = 0; i < count; i++) {
        char kbuf[256] = {0};
        if (CFGetTypeID(keys[i]) == CFStringGetTypeID()) {
            CFStringGetCString(keys[i], kbuf, sizeof(kbuf), kCFStringEncodingUTF8);
            if (strstr(kbuf, "apacit") || strstr(kbuf, "ealth") || strstr(kbuf, "ax") || strstr(kbuf, "ominal")) {
                if (CFGetTypeID(vals[i]) == CFNumberGetTypeID()) {
                    int v; CFNumberGetValue(vals[i], kCFNumberSInt32Type, &v);
                    fprintf(stderr, "[TRACE]   %s = %d\n", kbuf, v);
                }
            }
        }
    }
    free(keys); free(vals);
    return r;
}

// Hook IOPSCopyPowerSourcesList
typedef CFArrayRef (*orig_list_t)(CFTypeRef);
CFArrayRef my_IOPSCopyPowerSourcesList(CFTypeRef blob) {
    orig_list_t orig = dlsym(RTLD_NEXT, "IOPSCopyPowerSourcesList");
    CFArrayRef r = orig(blob);
    if (is_target_process()) fprintf(stderr, "[TRACE] IOPSCopyPowerSourcesList called\n");
    return r;
}

#define INTERPOSE(func) \
    __attribute__((used)) static struct { const void *r; const void *o; } \
    _ip_##func __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)my_##func, (const void *)func };

INTERPOSE(IORegistryEntryCreateCFProperty)
INTERPOSE(IORegistryEntryCreateCFProperties)
INTERPOSE(IOPSCopyPowerSourcesInfo)
INTERPOSE(IOPSGetPowerSourceDescription)
INTERPOSE(IOPSCopyPowerSourcesList)

__attribute__((constructor))
static void init(void) {
    fprintf(stderr, "[SPOOF] dylib loaded in %s (pid %d) target=%s\n",
            getprogname(), getpid(), is_target_process() ? "YES" : "no");
}
