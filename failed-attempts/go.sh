#!/bin/bash
# One-shot: open Battery, attach Frida to PowerPreferences, patch memory
launchctl unsetenv DYLD_INSERT_LIBRARIES 2>/dev/null
killall "System Settings" 2>/dev/null
sleep 1

open -a "System Settings"
sleep 2
open "x-apple.systempreferences:com.apple.Battery-Settings.extension"
sleep 3

PID=$(pgrep -f PowerPreferences | head -1)
if [ -z "$PID" ]; then
    echo "PowerPreferences not found!"
    exit 1
fi

echo "Attaching to PowerPreferences (PID $PID)..."
frida -p "$PID" -l ~/battery-spoof/patch.js
