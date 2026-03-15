#!/bin/bash
# One-liner installer for battery-spoof
# After factory reset: disable SIP in Recovery, reboot, then run:
#   curl -sL https://raw.githubusercontent.com/Rani367/battery-spoof/main/install-remote.sh | sudo bash
#
# What it does:
# 1. Downloads and compiles batteryd from GitHub
# 2. Installs LaunchDaemon
# 3. Sets boot-args
# 4. Starts the daemon

set -e

PCT="${1:-100}"
REPO="https://raw.githubusercontent.com/Rani367/battery-spoof/refs/heads/main"
DEST="/usr/local/bin/batteryd"
PLIST="/Library/LaunchDaemons/com.battery.spoof.plist"

echo "[*] battery-spoof installer (target: ${PCT}%)"

# Check SIP
if csrutil status 2>&1 | grep -q "enabled"; then
    echo "[!] SIP is enabled. Disable it first:"
    echo "    1. Shut down"
    echo "    2. Hold power button -> Options -> Terminal"
    echo "    3. csrutil disable"
    echo "    4. csrutil authenticated-root disable"
    echo "    5. Reboot and run this again"
    exit 1
fi

# Set boot-args if not set
if ! nvram boot-args 2>/dev/null | grep -q "arm64e_preview_abi"; then
    echo "[*] Setting boot-args..."
    nvram boot-args="-arm64e_preview_abi"
fi

# Download source
echo "[*] Downloading batteryd.m..."
TMPDIR=$(mktemp -d)
curl -sL "$REPO/batteryd.m" -o "$TMPDIR/batteryd.m"

# Compile
echo "[*] Compiling..."
xcrun --sdk macosx clang -arch arm64e -framework Foundation \
    -o "$DEST" "$TMPDIR/batteryd.m"
chmod +x "$DEST"

# Install LaunchDaemon plist
echo "[*] Installing LaunchDaemon..."
cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.battery.spoof</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/batteryd</string>
        <string>${PCT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/batteryd.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/batteryd.log</string>
</dict>
</plist>
PLISTEOF

# Start daemon
echo "[*] Starting daemon..."
launchctl bootout system/com.battery.spoof 2>/dev/null || true
launchctl bootstrap system "$PLIST"

# Cleanup
rm -rf "$TMPDIR"

echo "[+] Done! Open System Settings > Battery."
echo "[+] Survives reboots and macOS updates automatically."
echo "[+] After factory reset, re-disable SIP and run this again."
