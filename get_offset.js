var impl = ObjC.classes.PLBatteryUIBackendModel["+ getMaximumCapacity"].implementation;
var mod = Process.getModuleByName("PowerLog");
console.log("implementation: " + impl);
console.log("PowerLog base:  " + mod.base);
console.log("offset:         " + ptr(impl).sub(mod.base));

// Also dump the first few instructions so we know what we're replacing
console.log("current bytes:  " + hexdump(impl, {length: 32, ansi: false}));
