#!/usr/bin/env python3
"""Race to hook PowerPreferences before it reads battery data."""
import frida
import subprocess
import time
import sys

HOOK_JS = """
Interceptor.attach(ObjC.classes.PLBatteryUIBackendModel["+ getMaximumCapacity"].implementation, {
    onLeave: function(r) { r.replace(ptr(65)); }
});
send("hooked");
"""

def on_message(message, data):
    if message["type"] == "send":
        print(f"[+] {message['payload']}")

# Kill existing
subprocess.run(["killall", "System Settings"], capture_output=True)
time.sleep(1)

# Open to Wi-Fi
subprocess.Popen(["open", "x-apple.systempreferences:com.apple.wifi-settings-extension"])
time.sleep(2)

print("Now click Battery in System Settings!")
print("Racing to hook PowerPreferences...")

# Tight poll loop
attempts = 0
while True:
    try:
        session = frida.attach("PowerPreferences")
        print(f"[+] Attached after {attempts} attempts!")
        script = session.create_script(HOOK_JS)
        script.on("message", on_message)
        script.load()
        print("[+] Hook installed! Check Battery Health.")
        print("Press Ctrl+C to exit.")
        sys.stdin.read()
    except frida.ProcessNotFoundError:
        attempts += 1
    except KeyboardInterrupt:
        break
    except Exception as e:
        print(f"Error: {e}")
        break
