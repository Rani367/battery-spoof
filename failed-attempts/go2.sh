#!/bin/bash
# Patch powerd memory, then open System Settings
killall "System Settings" 2>/dev/null
sleep 1

echo "=== Patching powerd memory ==="
sudo frida -n powerd -l ~/battery-spoof/patch_powerd.js --no-pause -e "setTimeout(function(){},500);" &
FRIDA_PID=$!
sleep 3

echo ""
echo "=== Opening System Settings > Battery ==="
open "x-apple.systempreferences:com.apple.Battery-Settings.extension"
echo ""
echo "Check Battery Health! Press Enter when done to clean up."
read
kill $FRIDA_PID 2>/dev/null
