#!/bin/bash
#
# OaKhz Audio - Rotary Encoder Control Installation
# To be added to the installation script
#

set -e

# Get script directory and system files location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_FILES="$(cd "$SCRIPT_DIR/../system-files" && pwd)"

# Helper function to copy system files
copy_system_file() {
    local src="$1"
    local dest="$2"
    if [ -f "$SYSTEM_FILES/$src" ]; then
        cp "$SYSTEM_FILES/$src" "$dest"
        echo "  ✓ Installed: $dest"
    else
        echo "  ✗ File not found: $SYSTEM_FILES/$src"
        return 1
    fi
}

SERVICE_USER=${SERVICE_USER:-"oakhz"}
ROTARY_CLK=${ROTARY_CLK:-23}
ROTARY_DT=${ROTARY_DT:-24}
ROTARY_SW=${ROTARY_SW:-22}

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Installing rotary encoder control...${NC}"

# Install dependencies
echo "Installing Python dependencies..."
apt update
apt install -y python3-gpiozero python3-rpi.gpio playerctl

echo "Creating rotary encoder control script..."

# ============================================
# Script: Rotary Encoder Controller (gpiozero + threading)
# ============================================
copy_system_file "usr/local/bin/oakhz-rotary.py" "/usr/local/bin/oakhz-rotary.py"

chmod +x /usr/local/bin/oakhz-rotary.py

# ============================================
# Systemd service for rotary encoder
# ============================================
copy_system_file "etc/systemd/system/oakhz-rotary.service" "/etc/systemd/system/oakhz-rotary.service"

# ============================================
# Configure GPIO permissions
# ============================================
# Add user to gpio group for GPIO access
if groups $SERVICE_USER 2>/dev/null | grep -q gpio; then
    echo "User $SERVICE_USER already in gpio group"
else
    if id "$SERVICE_USER" &>/dev/null; then
        usermod -a -G gpio $SERVICE_USER
        echo "Added $SERVICE_USER to gpio group"
    fi
fi

# ============================================
# Enable and start service
# ============================================
echo "Enabling rotary encoder service..."
systemctl daemon-reload
systemctl enable oakhz-rotary.service
systemctl start oakhz-rotary.service

echo ""
echo -e "${GREEN}✓ Rotary encoder control installed successfully!${NC}"
echo ""
echo "GPIO Pin Configuration:"
echo "  CLK (Rotation): GPIO $ROTARY_CLK"
echo "  DT (Direction): GPIO $ROTARY_DT"
echo "  SW (Button):    GPIO $ROTARY_SW"
echo ""
echo "Controls:"
echo "  🔄 Rotate:           Volume up/down (±3% per step)"
echo "  🔘 Short press (<1s): Play/Pause"
echo "  🔘 Medium press (1s): Skip to next track"
echo "  ⏱️  Long press (3s):  Shutdown system"
echo ""
echo "Volume Control: PulseAudio (pactl → camilladsp_out sink)"
echo "Service runs as: $SERVICE_USER (gpio + audio groups)"
echo ""
echo "Service: oakhz-rotary.service"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status oakhz-rotary"
echo "  journalctl -u oakhz-rotary -f"
echo "  sudo systemctl restart oakhz-rotary"
echo ""
echo "To customize GPIO pins, edit:"
echo "  /usr/local/bin/oakhz-rotary.py"
echo "  (Change CLK_PIN, DT_PIN, SW_PIN at the top)"
