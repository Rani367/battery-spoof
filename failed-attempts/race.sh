#!/bin/bash
# Race to hook PowerPreferences before it reads battery data
killall "System Settings" 2>/dev/null
sleep 1

# Open Settings to Wi-Fi (PowerPreferences not yet spawned)
open "x-apple.systempreferences:com.apple.wifi-settings-extension"
sleep 2

echo "Waiting for you to click Battery..."
echo "Polling for PowerPreferences process..."

# Poll until PowerPreferences appears, then attach INSTANTLY
while true; do
    PID=$(pgrep -x PowerPreferences 2>/dev/null)
    if [ -n "$PID" ]; then
        echo "CAUGHT IT! PID=$PID - attaching NOW"
        frida -p "$PID" -l ~/battery-spoof/hook65.js
        break
    fi
done
