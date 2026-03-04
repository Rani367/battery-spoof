// Comprehensive tracer - hooks EVERY battery-related function
// Attach to GeneralSettings PID, then navigate TO battery section

var iokit = Process.getModuleByName("IOKit");

// Hook every IOPowerSources export
var psExports = [
    "IOPSCopyPowerSourcesInfo",
    "IOPSCopyPowerSourcesList",
    "IOPSGetPowerSourceDescription",
    "IOPSCopyInternalBatteriesArray",
    "IOPSGetBatteryHealthState",
    "IOPSCopyPowerSourcesByType",
    "IOPSCopyPowerSourcesByTypePrecise",
    "IOPSCopyPowerSourcesInfoPrecise",
    "IOPSGetPercentRemaining",
    "IOPSCopyChargeStatus",
    "IOPSCopyBatteryLevelLimits",
    "IOPMCopyBatteryInfo",
    "IOPMCopyBatteryHeatMap",
    "IORegistryEntryCreateCFProperty",
    "IORegistryEntryCreateCFProperties",
    "IOServiceGetMatchingService"
];

psExports.forEach(function(name) {
    try {
        var addr = iokit.getExportByName(name);
        Interceptor.attach(addr, {
            onEnter: function(args) {
                this.name = name;
                console.log("[CALL] " + name);
            }
        });
    } catch(e) {}
});

// Hook ALL xpc dictionary accessors
try {
    var libxpc = Process.getModuleByName("libxpc.dylib");
    var xpcFuncs = [
        "xpc_dictionary_get_int64",
        "xpc_dictionary_get_uint64",
        "xpc_dictionary_get_string",
        "xpc_dictionary_get_value"
    ];
    xpcFuncs.forEach(function(name) {
        try {
            var cf = Process.getModuleByName("CoreFoundation");
            var CFStringGetCStringPtr = new NativeFunction(cf.getExportByName("CFStringGetCStringPtr"), "pointer", ["pointer", "uint32"]);

            Interceptor.attach(libxpc.getExportByName(name), {
                onEnter: function(args) {
                    try {
                        var key = args[1].readUtf8String();
                        if (key && key.match(/[Bb]atter|[Cc]apacit|[Hh]ealth|[Mm]ax|[Nn]ominal|[Cc]ycle/)) {
                            console.log("[XPC] " + name + " key=" + key);
                        }
                    } catch(e) {}
                }
            });
        } catch(e) {}
    });
} catch(e) { console.log("[!] XPC hook error: " + e); }

// Hook ObjC methods with battery/health/capacity in selector
if (ObjC.available) {
    var resolver = new ApiResolver("objc");
    var patterns = [
        "*[* *attery*]",
        "*[* *ealth*]",
        "*[* *apacity*]",
        "*[* *aximum*]"
    ];
    patterns.forEach(function(pat) {
        try {
            resolver.enumerateMatches(pat, {
                onMatch: function(match) {
                    if (match.name.match(/battery|health|capacity|maximum/i)) {
                        try {
                            Interceptor.attach(match.address, {
                                onEnter: function() {
                                    console.log("[OBJC] " + match.name);
                                }
                            });
                        } catch(e) {}
                    }
                },
                onComplete: function() {}
            });
        } catch(e) {}
    });
}

console.log("[*] Comprehensive tracer ready.");
console.log("[*] NOW navigate to Battery in System Settings.");
