// Direct IORegistry modification - modifies battery data at the source
// Compile: clang -framework IOKit -framework CoreFoundation -o set_battery set_battery.c
// Usage: sudo ./set_battery 65

#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    int fakePct = 65;
    if (argc > 1) fakePct = atoi(argv[1]);
    if (fakePct < 1 || fakePct > 100) {
        fprintf(stderr, "Usage: %s <percent 1-100>\n", argv[0]);
        return 1;
    }

    // Find AppleSmartBattery service
    io_service_t service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("AppleSmartBattery")
    );
    if (!service) {
        fprintf(stderr, "Cannot find AppleSmartBattery service\n");
        return 1;
    }
    printf("Found AppleSmartBattery service: 0x%x\n", service);

    // Read current DesignCapacity
    CFNumberRef designCap = IORegistryEntryCreateCFProperty(
        service, CFSTR("DesignCapacity"), kCFAllocatorDefault, 0);
    int designCapVal = 4563; // fallback
    if (designCap) {
        CFNumberGetValue(designCap, kCFNumberIntType, &designCapVal);
        CFRelease(designCap);
    }
    printf("DesignCapacity: %d\n", designCapVal);

    // Read current MaxCapacity
    CFNumberRef curMax = IORegistryEntryCreateCFProperty(
        service, CFSTR("MaxCapacity"), kCFAllocatorDefault, 0);
    if (curMax) {
        int curVal;
        CFNumberGetValue(curMax, kCFNumberIntType, &curVal);
        printf("Current MaxCapacity: %d (%d%%)\n", curVal, (curVal * 100) / designCapVal);
        CFRelease(curMax);
    }

    // Calculate fake MaxCapacity
    int fakeMax = (designCapVal * fakePct) / 100;
    printf("Setting MaxCapacity to: %d (%d%%)\n", fakeMax, fakePct);

    // Try setting properties
    CFNumberRef fakeNum = CFNumberCreate(NULL, kCFNumberIntType, &fakeMax);

    const char *keys[] = {
        "MaxCapacity",
        "AppleRawMaxCapacity",
        "BatteryHealthMaximumCapacity",
        "AppleRawMaxCapacity0",
    };
    int numKeys = sizeof(keys) / sizeof(keys[0]);

    for (int i = 0; i < numKeys; i++) {
        CFStringRef key = CFStringCreateWithCString(NULL, keys[i], kCFStringEncodingUTF8);
        kern_return_t kr = IORegistryEntrySetCFProperty(service, key, fakeNum);
        printf("  Set %-35s -> %s (0x%x)\n", keys[i],
               kr == KERN_SUCCESS ? "SUCCESS" : "FAILED", kr);
        CFRelease(key);
    }

    // Also try setting via the parent (AppleSmartBatteryManager)
    io_service_t parent = 0;
    IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent);
    if (parent) {
        printf("\nTrying via AppleSmartBatteryManager (parent):\n");
        CFStringRef key = CFSTR("MaxCapacity");
        kern_return_t kr = IORegistryEntrySetCFProperty(parent, key, fakeNum);
        printf("  Set MaxCapacity -> %s (0x%x)\n",
               kr == KERN_SUCCESS ? "SUCCESS" : "FAILED", kr);
        IOObjectRelease(parent);
    }

    CFRelease(fakeNum);
    IOObjectRelease(service);

    printf("\nDone. Reopen System Settings to check.\n");
    return 0;
}
