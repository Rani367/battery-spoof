#!/bin/bash
# Launch System Settings with Frida battery spoof attached
# Run this AFTER setup.sh and a reboot

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRIDA_SCRIPT="$SCRIPT_DIR/spoof_battery.js"
FAKE_PCT="${1:-65}"

echo "=== Battery Health Spoofer ==="
echo "Spoofing battery health to: ${FAKE_PCT}%"
echo ""

# Update the percentage in the script if a custom value was passed
if [ "$FAKE_PCT" != "65" ]; then
    sed -i '' "s/const FAKE_MAX_CAPACITY = [0-9]*/const FAKE_MAX_CAPACITY = ${FAKE_PCT}/" "$FRIDA_SCRIPT"
    echo "Updated spoof target to ${FAKE_PCT}%"
fi

# Use the local re-signed copy (system volume is read-only)
SETTINGS_APP="$SCRIPT_DIR/System Settings.app"
SETTINGS_BIN="$SETTINGS_APP/Contents/MacOS/System Settings"

if [ ! -f "$SETTINGS_BIN" ]; then
    echo "❌ Local System Settings copy not found."
    echo "Run: cp -R '/System/Applications/System Settings.app' '$SCRIPT_DIR/System Settings.app'"
    echo "Then: codesign -f -s - --deep '$SCRIPT_DIR/System Settings.app'"
    exit 1
fi

# Kill System Settings if already running
killall "System Settings" 2>/dev/null || true
sleep 1

# Launch our re-signed copy
echo "Launching re-signed System Settings..."
open "$SETTINGS_APP"
sleep 3

# Attach Frida
echo "Attaching Frida hooks..."
echo "(Press Ctrl+C to detach and stop spoofing)"
echo ""

frida -n "System Settings" -l "$FRIDA_SCRIPT"
