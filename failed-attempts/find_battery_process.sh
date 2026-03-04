#!/bin/bash
# Open Battery pane and find which process handles it
killall "System Settings" 2>/dev/null
sleep 1
open -a "System Settings"
sleep 2

echo "=== Processes BEFORE clicking Battery ==="
ps aux | grep -i "settings\|battery\|power\|energy" | grep -v grep > /tmp/before.txt
cat /tmp/before.txt

echo ""
echo "Opening Battery pane..."
open "x-apple.systempreferences:com.apple.Battery-Settings.extension"
sleep 3

echo ""
echo "=== Processes AFTER clicking Battery ==="
ps aux | grep -i "settings\|battery\|power\|energy" | grep -v grep > /tmp/after.txt
cat /tmp/after.txt

echo ""
echo "=== NEW processes (appeared after opening Battery) ==="
diff /tmp/before.txt /tmp/after.txt | grep "^>" | sed 's/^> //'
