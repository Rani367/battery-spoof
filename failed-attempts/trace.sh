#!/bin/bash
launchctl unsetenv DYLD_INSERT_LIBRARIES 2>/dev/null
killall "System Settings" 2>/dev/null
sleep 2
open -a "System Settings"
sleep 3

# Navigate to Wi-Fi first (so Battery data isn't loaded yet)
open "x-apple.systempreferences:com.apple.wifi-settings-extension"
sleep 2

PID=$(pgrep -f GeneralSettings | head -1)
if [ -z "$PID" ]; then
    echo "GeneralSettings not found, trying to find it..."
    sleep 3
    PID=$(pgrep -f GeneralSettings | head -1)
fi

if [ -z "$PID" ]; then
    echo "ERROR: Cannot find GeneralSettings process"
    exit 1
fi

echo "Found GeneralSettings at PID $PID"
echo ">>> NOW CLICK ON 'Battery' IN SYSTEM SETTINGS <<<"
echo ""
frida -p "$PID" -l ~/battery-spoof/trace.js
