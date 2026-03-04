// Battery Health Spoofer - Frida script
// Spoofs the "Maximum Capacity" percentage in macOS System Settings > Battery
//
// How it works:
// 1. Hooks PLBatteryUIBackendModel.getMaximumCapacity to return our fake value
// 2. Patches the BatteryHealthViewModel's cached value in memory (offset 0x68)
// 3. Fires KVO notifications to trigger SwiftUI to re-render with the new value
//
// Tested on: macOS 26.3 Tahoe, MacBook Air M2

var FAKE_PCT = 65;

// Hook the class method that returns battery health percentage
Interceptor.attach(ObjC.classes.PLBatteryUIBackendModel["+ getMaximumCapacity"].implementation, {
    onLeave: function(r) {
        r.replace(ptr(FAKE_PCT));
    }
});

// Find the SwiftUI view model and patch its cached value
var vms = ObjC.chooseSync(ObjC.classes["PowerPreferences.BatteryHealthViewModel"]);
if (vms.length > 0) {
    var vm = vms[0];

    // The health percentage integer is stored at offset 0x68 in the view model
    vm.handle.add(0x68).writeU64(FAKE_PCT);

    // Fire KVO notifications on likely property names to trigger SwiftUI re-render
    var keys = [
        "maximumCapacity", "maximumCapacityPercentage", "healthPercentage",
        "maxCapacity", "batteryHealth", "capacityPercentage", "condition",
        "maximumCapacityString", "healthDescription", "batteryCondition"
    ];
    keys.forEach(function(k) {
        try {
            vm.willChangeValueForKey_(k);
            vm.didChangeValueForKey_(k);
        } catch(e) {}
    });

    console.log("[+] Battery health spoofed to " + FAKE_PCT + "%");
    console.log("[+] Close and reopen the Battery Health (i) popup to see it.");
} else {
    console.log("[!] BatteryHealthViewModel not found. Is the Battery pane open?");
}
