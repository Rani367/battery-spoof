#!/bin/bash
# Update the spoofed percentage. Usage: ./update.sh 100
PCT="${1:-100}"
sudo launchctl unload /Library/LaunchDaemons/com.battery.spoof.plist 2>/dev/null
sudo sed -i '' "s|<string>[0-9]*</string>|<string>${PCT}</string>|2" /Library/LaunchDaemons/com.battery.spoof.plist
sudo launchctl load /Library/LaunchDaemons/com.battery.spoof.plist
killall "System Settings" 2>/dev/null
echo "Done. Battery health now shows ${PCT}%."
