#!/bin/bash
set -e

MNT="/tmp/sysvol"
sudo mkdir -p "$MNT"

echo "[*] Mounting system volume read-write..."
sudo mount -t apfs -o nobrowse /dev/disk3s3 "$MNT"

echo "[*] Copying batteryd..."
sudo mkdir -p "$MNT/usr/local/bin"
sudo cp ~/battery-spoof/batteryd "$MNT/usr/local/bin/batteryd"

echo "[*] Installing LaunchDaemon..."
sudo cp ~/battery-spoof/com.battery.spoof.plist "$MNT/System/Library/LaunchDaemons/"

echo "[*] Creating new boot snapshot..."
sudo bless --mount "$MNT" --bootefi --create-snapshot

echo "[+] Done! Survives factory reset. Reboot now."
