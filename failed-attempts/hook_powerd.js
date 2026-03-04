// Hook powerd - the daemon that serves battery data to ALL processes
// This modifies data at the source, so System Settings will read fake values
// Usage: sudo frida -n powerd -l hook_powerd.js

var FAKE_PCT = 65;

var iokit = Process.getModuleByName("IOKit");
var cf = Process.getModuleByName("CoreFoundation");

var CFStringCreateWithCString = new NativeFunction(
    cf.getExportByName("CFStringCreateWithCString"),
    "pointer", ["pointer", "pointer", "uint32"]
);
var CFStringGetCStringPtr = new NativeFunction(
    cf.getExportByName("CFStringGetCStringPtr"),
    "pointer", ["pointer", "uint32"]
);
var CFNumberCreate = new NativeFunction(
    cf.getExportByName("CFNumberCreate"),
    "pointer", ["pointer", "long", "pointer"]
);
var CFNumberGetValue = new NativeFunction(
    cf.getExportByName("CFNumberGetValue"),
    "bool", ["pointer", "long", "pointer"]
);
var CFDictionarySetValue = new NativeFunction(
    cf.getExportByName("CFDictionarySetValue"),
    "void", ["pointer", "pointer", "pointer"]
);
var CFDictionaryGetValue = new NativeFunction(
    cf.getExportByName("CFDictionaryGetValue"),
    "pointer", ["pointer", "pointer"]
);

var kCFStringEncodingUTF8 = 0x08000100;
var kCFNumberSInt32Type = 3;

function makeCFString(s) {
    return CFStringCreateWithCString(ptr(0), Memory.allocUtf8String(s), kCFStringEncodingUTF8);
}
function makeCFInt(v) {
    var buf = Memory.alloc(4);
    buf.writeS32(v);
    return CFNumberCreate(ptr(0), kCFNumberSInt32Type, buf);
}
function cfStrToJs(p) {
    if (p.isNull()) return null;
    var c = CFStringGetCStringPtr(p, kCFStringEncodingUTF8);
    return c.isNull() ? null : c.readUtf8String();
}

// Keys
var keyMaxCap = makeCFString("MaxCapacity");
var keyRawMaxCap = makeCFString("AppleRawMaxCapacity");
var keyHealthMaxCap = makeCFString("BatteryHealthMaximumCapacity");
var keyDesignCap = makeCFString("DesignCapacity");
var fakeRaw = Math.round(4563 * (FAKE_PCT / 100));
var fakeRawCF = makeCFInt(fakeRaw);
var fakePctCF = makeCFInt(FAKE_PCT);

console.log("[*] powerd Battery Spoofer");
console.log("[*] Target: " + FAKE_PCT + "% (raw: " + fakeRaw + ")");

// Hook IORegistryEntryCreateCFProperty in powerd
Interceptor.attach(iokit.getExportByName("IORegistryEntryCreateCFProperty"), {
    onEnter: function(args) {
        this.keyPtr = args[1];
    },
    onLeave: function(retval) {
        if (retval.isNull()) return;
        try {
            var name = cfStrToJs(this.keyPtr);
            if (name === "MaxCapacity" || name === "AppleRawMaxCapacity") {
                retval.replace(makeCFInt(fakeRaw));
                console.log("[+] powerd: spoofed " + name + " -> " + fakeRaw);
            }
        } catch(e) {}
    }
});

// Hook IORegistryEntryCreateCFProperties in powerd
Interceptor.attach(iokit.getExportByName("IORegistryEntryCreateCFProperties"), {
    onEnter: function(args) {
        this.outDict = args[1];
    },
    onLeave: function(retval) {
        try {
            var dictPtr = this.outDict.readPointer();
            if (dictPtr.isNull()) return;
            var val = CFDictionaryGetValue(dictPtr, keyMaxCap);
            if (!val.isNull()) {
                CFDictionarySetValue(dictPtr, keyMaxCap, fakeRawCF);
                CFDictionarySetValue(dictPtr, keyRawMaxCap, fakeRawCF);
                console.log("[+] powerd: spoofed bulk MaxCapacity -> " + fakeRaw);
            }
            var healthVal = CFDictionaryGetValue(dictPtr, keyHealthMaxCap);
            if (!healthVal.isNull()) {
                CFDictionarySetValue(dictPtr, keyHealthMaxCap, fakePctCF);
                console.log("[+] powerd: spoofed BatteryHealthMaximumCapacity -> " + FAKE_PCT);
            }
        } catch(e) {}
    }
});

// Hook any XPC reply that sends battery data
// powerd uses IOPSSetPowerSourceDetails to publish battery info
var setDetails = iokit.getExportByName("IOPSSetPowerSourceDetails");
if (setDetails) {
    Interceptor.attach(setDetails, {
        onEnter: function(args) {
            // args[0] = power source ID, args[1] = CFDictionary of details
            var dict = args[1];
            if (dict.isNull()) return;
            try {
                var val = CFDictionaryGetValue(dict, keyMaxCap);
                if (!val.isNull()) {
                    CFDictionarySetValue(dict, keyMaxCap, fakeRawCF);
                    console.log("[+] IOPSSetPowerSourceDetails: spoofed MaxCapacity -> " + fakeRaw);
                }
                var rawVal = CFDictionaryGetValue(dict, keyRawMaxCap);
                if (!rawVal.isNull()) {
                    CFDictionarySetValue(dict, keyRawMaxCap, fakeRawCF);
                    console.log("[+] IOPSSetPowerSourceDetails: spoofed AppleRawMaxCapacity -> " + fakeRaw);
                }
                var healthVal = CFDictionaryGetValue(dict, keyHealthMaxCap);
                if (!healthVal.isNull()) {
                    CFDictionarySetValue(dict, keyHealthMaxCap, fakePctCF);
                    console.log("[+] IOPSSetPowerSourceDetails: spoofed BatteryHealthMaximumCapacity -> " + FAKE_PCT);
                }
            } catch(e) {
                console.log("[!] Error in IOPSSetPowerSourceDetails hook: " + e);
            }
        }
    });
    console.log("[+] Hooked IOPSSetPowerSourceDetails");
} else {
    console.log("[!] IOPSSetPowerSourceDetails not found");
}

console.log("[*] All hooks active on powerd. Now reopen System Settings > Battery.");
