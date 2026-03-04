#!/usr/bin/env python3
"""
Battery Health Spoofer Daemon
Runs in the background and automatically spoofs battery health
whenever System Settings > Battery is opened.
"""
import frida
import sys
import time
import os

FAKE_PCT = int(sys.argv[1]) if len(sys.argv) > 1 else 65

HOOK_JS = """
var FAKE_PCT = %d;

// Hook the class method that returns battery health %%
Interceptor.attach(ObjC.classes.PLBatteryUIBackendModel["+ getMaximumCapacity"].implementation, {
    onLeave: function(r) { r.replace(ptr(FAKE_PCT)); }
});

// Patch the view model's cached value + fire KVO to trigger SwiftUI re-render
var vms = ObjC.chooseSync(ObjC.classes["PowerPreferences.BatteryHealthViewModel"]);
if (vms.length > 0) {
    var vm = vms[0];
    vm.handle.add(0x68).writeU64(FAKE_PCT);
    var keys = [
        "maximumCapacity", "maximumCapacityPercentage", "healthPercentage",
        "maxCapacity", "batteryHealth", "capacityPercentage", "condition",
        "maximumCapacityString", "healthDescription", "batteryCondition"
    ];
    keys.forEach(function(k) {
        try { vm.willChangeValueForKey_(k); vm.didChangeValueForKey_(k); } catch(e) {}
    });
    send({type: "success", pct: FAKE_PCT});
} else {
    send({type: "no_vm"});
}
""" % FAKE_PCT

def on_message(message, data):
    if message["type"] == "send":
        payload = message["payload"]
        if payload.get("type") == "success":
            print(f"  [+] Spoofed to {payload['pct']}%")
        elif payload.get("type") == "no_vm":
            print("  [!] ViewModel not found (Battery pane might not be visible yet)")

def attach_and_hook(pid):
    try:
        session = frida.attach(pid)
        script = session.create_script(HOOK_JS)
        script.on("message", on_message)
        script.load()
        return session
    except Exception as e:
        print(f"  [-] Failed to hook PID {pid}: {e}")
        return None

print(f"Battery Health Spoofer Daemon (target: {FAKE_PCT}%)")
print(f"Watching for PowerPreferences... (Ctrl+C to stop)")
print()

current_session = None
last_pid = None

while True:
    try:
        # Check if PowerPreferences is running
        try:
            device = frida.get_local_device()
            processes = device.enumerate_processes()
            pp = [p for p in processes if p.name == "PowerPreferences"]
        except Exception:
            pp = []

        if pp:
            pid = pp[0].pid
            if pid != last_pid:
                # New PowerPreferences instance — hook it
                print(f"[*] PowerPreferences detected (PID {pid})")
                current_session = attach_and_hook(pid)
                last_pid = pid
        else:
            if last_pid is not None:
                print("[*] PowerPreferences exited, waiting for next launch...")
                current_session = None
                last_pid = None

        time.sleep(0.3)

    except KeyboardInterrupt:
        print("\nStopping daemon.")
        break
    except Exception as e:
        time.sleep(1)
