#!/bin/bash
# Battery Health Spoofer for macOS (Apple Silicon)
# Spoofs the "Maximum Capacity" percentage in System Settings > Battery
#
# Requirements: macOS with SIP disabled, Frida (`pip3 install frida-tools`)
# Usage: ./spoof.sh [percentage]  (default: 65)

set -e

PCT="${1:-65}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/spoof.js"

if ! command -v frida &>/dev/null; then
    echo "Error: frida not found. Install with: pip3 install frida-tools"
    exit 1
fi

if [ "$PCT" -lt 1 ] || [ "$PCT" -gt 100 ] 2>/dev/null; then
    echo "Usage: $0 [1-100]"
    exit 1
fi

# Update percentage in the Frida script
sed -i '' "s/var FAKE_PCT = [0-9]*/var FAKE_PCT = ${PCT}/" "$SCRIPT"

# Restart System Settings and navigate to Battery
killall "System Settings" 2>/dev/null || true
sleep 1
open -a "System Settings"
sleep 2
open "x-apple.systempreferences:com.apple.Battery-Settings.extension"
sleep 3

# Find the PowerPreferences extension process (handles the Battery pane)
PID=$(pgrep -x PowerPreferences | head -1)
if [ -z "$PID" ]; then
    echo "Error: PowerPreferences process not found."
    echo "Make sure System Settings is open on the Battery page."
    exit 1
fi

echo "Spoofing battery health to ${PCT}%..."
echo "(Close the Battery Health popup and reopen it to see the change)"
echo "(Press Ctrl+C to detach)"
echo ""
frida -p "$PID" -l "$SCRIPT"
