#!/bin/bash
launchctl unload ~/Library/LaunchAgents/com.battery.spoof.plist 2>/dev/null
killall "System Settings" 2>/dev/null
sleep 1
open -a "System Settings"
sleep 2
open "x-apple.systempreferences:com.apple.Battery-Settings.extension"
sleep 3
PID=$(pgrep -x PowerPreferences | head -1)
echo "PowerPreferences PID: $PID"
frida -p "$PID" -e 'console.log(ObjC.classes.PLBatteryUIBackendModel["+ getMaximumCapacity"].implementation);'
