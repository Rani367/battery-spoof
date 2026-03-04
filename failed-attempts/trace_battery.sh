#!/bin/bash
# Inject dylib and trace PowerPreferences battery API calls
killall "System Settings" 2>/dev/null
launchctl unsetenv DYLD_INSERT_LIBRARIES 2>/dev/null
sleep 1

launchctl setenv DYLD_INSERT_LIBRARIES /Users/rani/battery-spoof/interpose.dylib

# Open to Wi-Fi first, then Battery
open "x-apple.systempreferences:com.apple.wifi-settings-extension"
sleep 3
open "x-apple.systempreferences:com.apple.Battery-Settings.extension"
sleep 4

echo "=== Log from PowerPreferences ==="
log show --last 15s --predicate 'process == "PowerPreferences" OR process == "System Settings"' --style compact 2>/dev/null | grep -i "spoof\|trace\|battery\|capacity\|health" | head -30

echo ""
echo "=== stderr from syslog ==="
log show --last 15s --predicate 'eventMessage CONTAINS "SPOOF" OR eventMessage CONTAINS "TRACE"' --style compact 2>/dev/null | head -30

launchctl unsetenv DYLD_INSERT_LIBRARIES
