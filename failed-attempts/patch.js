// Memory patch approach: find and replace battery health values in PowerPreferences
// Attach to PowerPreferences PID after Battery pane is open

console.log("[*] Battery Memory Patcher");

// Step 1: Find all ObjC objects related to battery
if (ObjC.available) {
    console.log("[*] Scanning ObjC classes for battery-related objects...");

    var batteryClasses = [];
    Object.keys(ObjC.classes).forEach(function(name) {
        if (name.match(/[Bb]atter|[Pp]ower[Ss]ource|[Hh]ealth|[Cc]apacity/)) {
            batteryClasses.push(name);
        }
    });

    console.log("[*] Found " + batteryClasses.length + " battery-related classes:");
    batteryClasses.forEach(function(name) {
        console.log("    " + name);
        try {
            var cls = ObjC.classes[name];
            var methods = cls.$ownMethods;
            methods.forEach(function(m) {
                if (m.match(/[Mm]ax|[Hh]ealth|[Cc]apacit|[Nn]ominal|[Pp]ercent|89|65/i)) {
                    console.log("      " + m);
                }
            });
        } catch(e) {}
    });

    // Step 2: Search for instances of battery-related classes
    console.log("\n[*] Searching heap for battery object instances...");
    batteryClasses.forEach(function(name) {
        try {
            var instances = ObjC.chooseSync(ObjC.classes[name]);
            if (instances.length > 0) {
                console.log("  " + name + ": " + instances.length + " instance(s)");
                instances.forEach(function(obj) {
                    try {
                        // Try to get all properties
                        var props = ObjC.classes[name].$ownMethods;
                        props.forEach(function(m) {
                            if (m.startsWith("- ") && !m.includes(":") && m.match(/[Mm]ax|[Hh]ealth|[Cc]apacit|[Nn]ominal|[Pp]ercent|[Cc]ondition/)) {
                                try {
                                    var sel = m.substring(2);
                                    var val = obj[sel]();
                                    console.log("    " + sel + " = " + val);
                                } catch(e2) {}
                            }
                        });
                    } catch(e) {}
                });
            }
        } catch(e) {}
    });

    // Step 3: Also look for NSNumber objects with value 89 or 4061
    console.log("\n[*] Searching for key values in memory...");

    // Search process memory for the integer 4061 (NominalChargeCapacity)
    var ranges = Process.enumerateRanges({protection: 'rw-', coalesce: true});
    var found4061 = [];
    var found89 = [];

    ranges.forEach(function(range) {
        try {
            var results = Memory.scanSync(range.base, range.size, "FD 0F 00 00"); // 4061 = 0x0FFD little-endian
            results.forEach(function(match) {
                found4061.push(match.address);
            });

            var results89 = Memory.scanSync(range.base, range.size, "59 00 00 00"); // 89 = 0x59
            // Too many matches for 89, so we'll filter later
        } catch(e) {}
    });

    console.log("  Found " + found4061.length + " instances of 4061 (0x0FFD) in memory");
    found4061.forEach(function(addr) {
        console.log("    @ " + addr);
    });

    if (found4061.length > 0) {
        console.log("\n[*] Replacing 4061 with " + Math.round(4563 * 65 / 100) + " (65%)...");
        var replacement = 2965; // 65% of 4563
        found4061.forEach(function(addr) {
            try {
                Memory.writeS32(addr, replacement);
                console.log("  [+] Patched @ " + addr);
            } catch(e) {
                console.log("  [-] Failed @ " + addr + ": " + e);
            }
        });
    }
}

console.log("\n[*] Patch complete. Check if Battery Health changed in UI.");
console.log("[*] If not, try scrolling away and back to Battery Health info.");
