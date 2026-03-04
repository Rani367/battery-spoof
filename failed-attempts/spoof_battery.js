// Battery Health Spoofer v3
// Key insight: Health % = NominalChargeCapacity / DesignCapacity
// Real values: 4061 / 4563 = 89%
// To show 65%: need NominalChargeCapacity = 2966

var FAKE_PCT = 65;
var DESIGN_CAP = 4563;
var FAKE_NOMINAL = Math.round(DESIGN_CAP * (FAKE_PCT / 100));

var iokit = Process.getModuleByName("IOKit");
var cf = Process.getModuleByName("CoreFoundation");

var CFStringCreateWithCString = new NativeFunction(cf.getExportByName("CFStringCreateWithCString"), "pointer", ["pointer", "pointer", "uint32"]);
var CFStringGetCStringPtr = new NativeFunction(cf.getExportByName("CFStringGetCStringPtr"), "pointer", ["pointer", "uint32"]);
var CFNumberCreate = new NativeFunction(cf.getExportByName("CFNumberCreate"), "pointer", ["pointer", "long", "pointer"]);
var CFNumberGetValue = new NativeFunction(cf.getExportByName("CFNumberGetValue"), "bool", ["pointer", "long", "pointer"]);
var CFDictionarySetValue = new NativeFunction(cf.getExportByName("CFDictionarySetValue"), "void", ["pointer", "pointer", "pointer"]);
var CFDictionaryGetValue = new NativeFunction(cf.getExportByName("CFDictionaryGetValue"), "pointer", ["pointer", "pointer"]);

var kUTF8 = 0x08000100;
var kSInt32 = 3;

function mkStr(s) { return CFStringCreateWithCString(ptr(0), Memory.allocUtf8String(s), kUTF8); }
function mkInt(v) { var b = Memory.alloc(4); b.writeS32(v); return CFNumberCreate(ptr(0), kSInt32, b); }
function readStr(p) { if(p.isNull()) return null; var c = CFStringGetCStringPtr(p,kUTF8); return c.isNull()?null:c.readUtf8String(); }
function readInt(p) { if(p.isNull()) return null; var b = Memory.alloc(4); CFNumberGetValue(p,kSInt32,b); return b.readS32(); }

var fakeNomCF = mkInt(FAKE_NOMINAL);
var fakeRawCF = mkInt(FAKE_NOMINAL);
var keyNominal = mkStr("NominalChargeCapacity");
var keyMaxCap = mkStr("MaxCapacity");
var keyRawMax = mkStr("AppleRawMaxCapacity");

console.log("[*] Battery Spoofer v3");
console.log("[*] Spoofing NominalChargeCapacity: 4061 -> " + FAKE_NOMINAL + " (" + FAKE_PCT + "%)");

// Track how many hooks fire
var hookCount = 0;

// Hook 1: IORegistryEntryCreateCFProperty - single property reads
Interceptor.attach(iokit.getExportByName("IORegistryEntryCreateCFProperty"), {
    onEnter: function(args) { this.key = readStr(args[1]); },
    onLeave: function(retval) {
        if (retval.isNull() || !this.key) return;
        var k = this.key;
        if (k === "NominalChargeCapacity") {
            var orig = readInt(retval);
            retval.replace(fakeNomCF);
            hookCount++;
            console.log("[+] IORegCreateCFProp: " + k + " " + orig + " -> " + FAKE_NOMINAL + " (hit #" + hookCount + ")");
        } else if (k === "AppleRawMaxCapacity") {
            var orig = readInt(retval);
            retval.replace(fakeRawCF);
            hookCount++;
            console.log("[+] IORegCreateCFProp: " + k + " " + orig + " -> " + FAKE_NOMINAL + " (hit #" + hookCount + ")");
        }
        // Log ALL battery-related property reads for debugging
        if (k && (k.match(/[Cc]apacity|[Hh]ealth|[Mm]ax|[Nn]ominal|[Cc]ycle/) || false)) {
            console.log("[i] Read property: " + k + " = " + readInt(retval));
        }
    }
});

// Hook 2: IORegistryEntryCreateCFProperties - bulk reads
Interceptor.attach(iokit.getExportByName("IORegistryEntryCreateCFProperties"), {
    onEnter: function(args) { this.outDict = args[1]; },
    onLeave: function(retval) {
        try {
            var d = this.outDict.readPointer();
            if (d.isNull()) return;
            var nomVal = CFDictionaryGetValue(d, keyNominal);
            if (!nomVal.isNull()) {
                var orig = readInt(nomVal);
                CFDictionarySetValue(d, keyNominal, fakeNomCF);
                CFDictionarySetValue(d, keyRawMax, fakeRawCF);
                hookCount++;
                console.log("[+] IORegCreateCFProps: NominalChargeCapacity " + orig + " -> " + FAKE_NOMINAL + " (hit #" + hookCount + ")");
            }
        } catch(e) {}
    }
});

// Hook 3: IOPSGetPowerSourceDescription
Interceptor.attach(iokit.getExportByName("IOPSGetPowerSourceDescription"), {
    onLeave: function(retval) {
        if (retval.isNull()) return;
        try {
            // Try modifying the dictionary if it has our keys
            var nomVal = CFDictionaryGetValue(retval, keyNominal);
            if (!nomVal.isNull()) {
                // This is an immutable dict from IOKit, we can't modify it directly
                // But let's log it
                console.log("[i] IOPSGetPowerSourceDescription has NominalChargeCapacity = " + readInt(nomVal));
            }
            // Log all keys we care about
            var rawMax = CFDictionaryGetValue(retval, keyRawMax);
            if (!rawMax.isNull()) console.log("[i] IOPSGetPowerSourceDescription has AppleRawMaxCapacity = " + readInt(rawMax));
        } catch(e) {}
    }
});

// Hook 4: IOPSCopyPowerSourcesInfo
Interceptor.attach(iokit.getExportByName("IOPSCopyPowerSourcesInfo"), {
    onLeave: function(retval) {
        hookCount++;
        console.log("[+] IOPSCopyPowerSourcesInfo called (hit #" + hookCount + ")");
    }
});

// Hook 5: IOPSCopyInternalBatteriesArray
Interceptor.attach(iokit.getExportByName("IOPSCopyInternalBatteriesArray"), {
    onLeave: function(retval) {
        hookCount++;
        console.log("[+] IOPSCopyInternalBatteriesArray called (hit #" + hookCount + ")");
    }
});

console.log("[*] All hooks installed. Waiting for battery data reads...");
