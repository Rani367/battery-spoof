#!/bin/bash
# One-liner installer for battery-spoof
# After factory reset, just run:
#   curl -sL https://raw.githubusercontent.com/Rani367/battery-spoof/refs/heads/main/install-remote.sh | sudo bash
#
# SIP stays disabled through factory reset (stored in Secure Enclave).
# boot-args get reset, so we re-set them here.

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
    echo "    4. Reboot and run this again"
    exit 1
fi

# Set boot-args if not set (factory reset clears NVRAM)
if ! nvram boot-args 2>/dev/null | grep -q "arm64e_preview_abi"; then
    echo "[*] Setting boot-args..."
    nvram boot-args="-arm64e_preview_abi"
    NEEDS_REBOOT=1
fi

# Try downloading pre-compiled binary first
echo "[*] Downloading pre-compiled batteryd..."
TMPDIR=$(mktemp -d)
if curl -sL "${REPO}/batteryd.bin" -o "$TMPDIR/batteryd" 2>/dev/null && \
   file "$TMPDIR/batteryd" 2>/dev/null | grep -q "Mach-O"; then
    echo "[*] Using pre-compiled binary"
    cp "$TMPDIR/batteryd" "$DEST"
else
    # Fall back to compiling from source
    echo "[*] Pre-compiled binary not available, compiling from source..."
    curl -sL "${REPO}/batteryd.m" -o "$TMPDIR/batteryd.m"
    if ! command -v clang &>/dev/null; then
        echo "[*] Installing Xcode Command Line Tools (needed to compile)..."
        xcode-select --install 2>/dev/null
        echo "[!] Please wait for CLT install to finish, then re-run this script."
        rm -rf "$TMPDIR"
        exit 1
    fi
    xcrun --sdk macosx clang -arch arm64e -framework Foundation \
        -o "$DEST" "$TMPDIR/batteryd.m"
fi
chmod +x "$DEST"

# Install LaunchDaemon plist
echo "[*] Installing LaunchDaemon..."
mkdir -p /usr/local/bin
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

if [ -n "$NEEDS_REBOOT" ]; then
    echo "[+] Done! Reboot once for boot-args to take effect."
else
    echo "[+] Done! Open System Settings > Battery."
fi
echo "[+] Survives reboots and macOS updates automatically."
