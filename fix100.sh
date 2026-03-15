#!/bin/bash
# Update system volume plist to 100%
MNT="/tmp/sysvol"
sudo mkdir -p "$MNT"
sudo mount -t apfs -o nobrowse /dev/disk3s3 "$MNT"
sudo sed -i '' 's|65</string>|100</string>|' "$MNT/System/Library/LaunchDaemons/com.battery.spoof.plist"
sudo bless --mount "$MNT" --bootefi --create-snapshot
echo "System volume updated to 100%. Survives factory reset."
