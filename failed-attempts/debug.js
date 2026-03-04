// Debug script - find what battery-related symbols are available
console.log("[*] Debugging battery APIs...\n");

// Check IOKit exports
const funcs = [
    "IOPSCopyPowerSourcesInfo",
    "IOPSCopyPowerSourcesList",
    "IOPSGetPowerSourceDescription",
    "IORegistryEntryCreateCFProperty",
    "IORegistryEntryCreateCFProperties",
    "IOServiceGetMatchingService",
    "IOServiceMatching"
];

funcs.forEach(function(name) {
    const addr = Module.findExportByName("IOKit", name);
    console.log("  IOKit." + name + " = " + addr);
});

// Check if these are in a different framework
const frameworks = ["IOKit", "CoreFoundation", "Foundation", "libSystem.B.dylib"];
frameworks.forEach(function(fw) {
    const addr = Module.findExportByName(fw, "IOPSCopyPowerSourcesInfo");
    if (addr) console.log("  Found IOPSCopyPowerSourcesInfo in: " + fw + " at " + addr);
});

// Try IOPowerSources specifically
try {
    const ps = Module.findExportByName(null, "IOPSCopyPowerSourcesInfo");
    console.log("\n  Global search IOPSCopyPowerSourcesInfo = " + ps);
} catch(e) {
    console.log("  Global search failed: " + e);
}

// List loaded modules that might contain power/battery symbols
console.log("\n[*] Loaded modules with 'Power' or 'Battery' in name:");
Process.enumerateModules().forEach(function(m) {
    if (m.name.match(/power|battery|energy/i)) {
        console.log("  " + m.name + " @ " + m.base);
    }
});

// Search for battery-related ObjC classes
console.log("\n[*] ObjC classes with 'Battery' or 'Power' in name:");
if (ObjC.available) {
    Object.keys(ObjC.classes).forEach(function(name) {
        if (name.match(/battery|powersource/i)) {
            console.log("  " + name);
            try {
                const methods = ObjC.classes[name].$ownMethods;
                methods.forEach(function(m) {
                    if (m.toLowerCase().match(/max|capacity|health|percent/)) {
                        console.log("    " + m);
                    }
                });
            } catch(e) {}
        }
    });
}

console.log("\n[*] Debug complete. Use exit to detach.");
