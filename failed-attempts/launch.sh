#!/bin/bash
killall "System Settings" 2>/dev/null
sleep 1
export DYLD_INSERT_LIBRARIES=/Users/rani/battery-spoof/interpose.dylib
exec "/System/Applications/System Settings.app/Contents/MacOS/System Settings" 2>&1
