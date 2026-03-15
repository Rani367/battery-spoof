#!/bin/bash
sudo launchctl bootout system/com.battery.spoof 2>/dev/null
sudo sed -i '' 's|65</string>|100</string>|' /Library/LaunchDaemons/com.battery.spoof.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.battery.spoof.plist
killall "System Settings" 2>/dev/null
killall PowerPreferences 2>/dev/null
echo "Done. Open Settings > Battery."
