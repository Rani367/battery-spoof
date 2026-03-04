// Patch powerd's cached battery data in memory
// 4061 (NominalChargeCapacity) = 0x0FDD -> little-endian: DD 0F 00 00
// Replace with 2966 (65% of 4563) = 0x0B96 -> little-endian: 96 0B 00 00

console.log("[*] Scanning powerd memory for NominalChargeCapacity (4061 = 0x0FDD)...");

var ranges = Process.enumerateRanges({protection: "rw-", coalesce: true});
var found = [];

ranges.forEach(function(range) {
    try {
        var results = Memory.scanSync(range.base, range.size, "DD 0F 00 00");
        results.forEach(function(match) {
            found.push(match.address);
        });
    } catch(e) {}
});

console.log("[*] Found " + found.length + " instances of 4061 in writable memory");

// Also search for 89 (0x59) near a 4061 hit to confirm context
found.forEach(function(addr) {
    try {
        // Read surrounding bytes for context
        var before = addr.sub(16).readByteArray(48);
        console.log("[*] @ " + addr + ":");
        console.log(hexdump(addr.sub(16), {length: 48, ansi: false}));

        // Patch it
        addr.writeS32(2966);
        console.log("[+] Patched @ " + addr + ": 4061 -> 2966");
    } catch(e) {
        console.log("[-] Failed @ " + addr + ": " + e);
    }
});

// Also search for AppleRawMaxCapacity value (3934 = 0x0F5E)
console.log("\n[*] Scanning for AppleRawMaxCapacity (3934 = 0x0F5E)...");
var found2 = [];
ranges.forEach(function(range) {
    try {
        var results = Memory.scanSync(range.base, range.size, "5E 0F 00 00");
        results.forEach(function(match) { found2.push(match.address); });
    } catch(e) {}
});
console.log("[*] Found " + found2.length + " instances of 3934");
found2.forEach(function(addr) {
    try {
        addr.writeS32(2966);
        console.log("[+] Patched @ " + addr + ": 3934 -> 2966");
    } catch(e) {
        console.log("[-] Failed @ " + addr + ": " + e);
    }
});

console.log("\n[*] Done. Now open System Settings > Battery.");
console.log("[*] Type 'exit' when done.");
