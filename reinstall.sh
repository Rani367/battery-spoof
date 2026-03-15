#!/bin/bash
sudo launchctl bootout system/com.battery.spoof 2>/dev/null
sudo cp ~/battery-spoof/batteryd /usr/local/bin/batteryd
sudo launchctl bootstrap system /Library/LaunchDaemons/com.battery.spoof.plist
killall "System Settings" 2>/dev/null
killall PowerPreferences 2>/dev/null
echo "Done. Open Settings > Battery."
