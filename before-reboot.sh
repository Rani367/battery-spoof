#!/bin/bash
# Run this BEFORE rebooting to Recovery Mode
launchctl unload ~/Library/LaunchAgents/com.battery.spoof.plist 2>/dev/null
rm ~/Library/LaunchAgents/com.battery.spoof.plist 2>/dev/null
sudo cp ~/battery-spoof/batteryd /usr/local/bin/batteryd
sudo cp ~/battery-spoof/com.battery.spoof.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.battery.spoof.plist
echo "Done. Now reboot to Recovery and run: csrutil authenticated-root disable"
