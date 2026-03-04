// Debug script v2 - find battery APIs
console.log("[*] Modules with power/battery/iokit:");
Process.enumerateModules().forEach(function(m) {
    if (m.name.match(/power|battery|iokit/i)) {
        console.log("  " + m.name + " -> " + m.path);
    }
});

console.log("\n[*] Searching for IOPSCopyPowerSourcesInfo globally...");
var addr = Module.findExportByName(null, "IOPSCopyPowerSourcesInfo");
console.log("  result: " + addr);

console.log("\n[*] Searching for IORegistryEntryCreateCFProperty globally...");
var addr2 = Module.findExportByName(null, "IORegistryEntryCreateCFProperty");
console.log("  result: " + addr2);

console.log("\n[*] ObjC classes with battery/power:");
if (ObjC.available) {
    var names = Object.keys(ObjC.classes);
    for (var i = 0; i < names.length; i++) {
        if (names[i].match(/battery|powersource/i)) {
            console.log("  " + names[i]);
        }
    }
}

console.log("\n[*] Done. Type exit to quit.");
