// Minimal: hook + patch + KVO trigger
Interceptor.attach(ObjC.classes.PLBatteryUIBackendModel["+ getMaximumCapacity"].implementation, {
    onLeave: function(r) { r.replace(ptr(65)); }
});

var vms = ObjC.chooseSync(ObjC.classes["PowerPreferences.BatteryHealthViewModel"]);
if (vms.length > 0) {
    var vm = vms[0];
    // Patch the integer 89 -> 65 in memory
    vm.handle.add(0x68).writeU64(65);
    console.log("[+] Patched memory: 89 -> 65");

    // Try KVO notifications to trigger SwiftUI refresh
    var keys = ["maximumCapacity", "maximumCapacityPercentage", "healthPercentage",
                "maxCapacity", "batteryHealth", "capacityPercentage", "condition",
                "maximumCapacityString", "healthDescription", "batteryCondition"];
    keys.forEach(function(k) {
        try {
            vm.willChangeValueForKey_(k);
            vm.didChangeValueForKey_(k);
        } catch(e) {}
    });
    console.log("[+] Fired KVO for common property names");
}
console.log("[+] Done. Close and reopen the (i) popup.");
