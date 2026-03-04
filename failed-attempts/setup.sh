#!/bin/bash
# Battery Health Spoofer Setup
# Run this AFTER disabling SIP from Recovery Mode

set -e

echo "=== Battery Health Spoofer Setup ==="
echo ""

# Step 1: Verify SIP is disabled
SIP_STATUS=$(csrutil status 2>&1)
if echo "$SIP_STATUS" | grep -q "enabled"; then
    echo "❌ SIP is still ENABLED."
    echo ""
    echo "To disable SIP:"
    echo "  1. Shut down your Mac"
    echo "  2. Hold the power button until 'Loading startup options' appears"
    echo "  3. Click Options → Continue"
    echo "  4. Menu bar: Utilities → Terminal"
    echo "  5. Run: csrutil disable"
    echo "  6. Reboot and run this script again"
    exit 1
fi
echo "✅ SIP is disabled"

# Step 2: Set arm64e preview ABI boot arg (needed for Frida on arm64e processes)
echo ""
echo "Setting arm64e_preview_abi boot arg..."
sudo nvram boot-args="-arm64e_preview_abi"
echo "✅ Boot args set (will take effect after reboot)"

# Step 3: Install Frida
echo ""
echo "Installing Frida tools..."
pip3 install frida-tools --break-system-packages 2>/dev/null || pip3 install frida-tools
echo "✅ Frida installed"

# Step 4: Re-sign System Settings to remove library validation
echo ""
SETTINGS_PATH="/System/Applications/System Settings.app"
SETTINGS_BIN="$SETTINGS_PATH/Contents/MacOS/System Settings"

echo "Re-signing System Settings to remove library validation..."
echo "(This allows Frida to inject into the process)"
sudo codesign -f -s - --deep "$SETTINGS_PATH"
echo "✅ System Settings re-signed"

echo ""
echo "=== Setup complete! ==="
echo ""
echo "⚠️  You need to REBOOT once for the arm64e boot arg to take effect."
echo ""
echo "After reboot, run:"
echo "  ./run.sh"
