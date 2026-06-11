#!/bin/bash
#
# OaKhz Audio - Audio Feedback Services Installation
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

SOUNDS_DIR="/opt/oakhz/sounds"
SERVICE_USER=${SERVICE_USER:-"oakhz"}

echo "Installing audio feedback services..."

# Create sounds directory
mkdir -p $SOUNDS_DIR

# Install sox for WAV generation (no mpg123 needed with paplay)
apt install -y sox pulseaudio-utils

echo "Creating audio feedback scripts..."

# ============================================
# Unified Audio Events Manager
# Manages ready sound + Bluetooth monitoring
# ============================================
copy_system_file "usr/local/bin/oakhz-audio-events.py" "/usr/local/bin/oakhz-audio-events.py"

chmod +x /usr/local/bin/oakhz-audio-events.py

# Systemd service for unified audio events manager
copy_system_file "etc/systemd/system/oakhz-audio-events.service" "/etc/systemd/system/oakhz-audio-events.service"

# ============================================
# Script 3: Sound before shutdown
# ============================================
copy_system_file "usr/local/bin/oakhz-shutdown-sound.sh" "/usr/local/bin/oakhz-shutdown-sound.sh"

chmod +x /usr/local/bin/oakhz-shutdown-sound.sh

# Systemd service for shutdown sound
copy_system_file "etc/systemd/system/oakhz-shutdown-sound.service" "/etc/systemd/system/oakhz-shutdown-sound.service"

# ============================================
# Create demo WAV files (optional)
# ============================================
echo "Installing audio files..."

copy_system_file "opt/oakhz/sounds/ready.wav"      "$SOUNDS_DIR/ready.wav"
copy_system_file "opt/oakhz/sounds/connect.wav"    "$SOUNDS_DIR/connect.wav"
copy_system_file "opt/oakhz/sounds/disconnect.wav" "$SOUNDS_DIR/disconnect.wav"
copy_system_file "opt/oakhz/sounds/shutdown.wav"   "$SOUNDS_DIR/shutdown.wav"

# Permissions
chown -R root:root $SOUNDS_DIR
chmod 644 $SOUNDS_DIR/*.wav

echo "Enabling services..."

# Enable services
systemctl daemon-reload
systemctl enable oakhz-audio-events.service
systemctl enable oakhz-shutdown-sound.service

# Start services (except shutdown which only runs on shutdown)
systemctl start oakhz-audio-events.service

echo ""
echo "✓ Audio feedback services installed successfully!"
echo ""
echo "Services created:"
echo "  - oakhz-audio-events.service   : Unified manager (ready + Bluetooth monitoring)"
echo "  - oakhz-shutdown-sound.service : Shutdown sound"
echo ""
echo "Audio files in $SOUNDS_DIR:"
echo "  - ready.wav       : Played when speaker is ready and Bluetooth discoverable"
echo "  - connect.wav     : Played on Bluetooth device connection"
echo "  - disconnect.wav  : Played on device disconnection (not used currently)"
echo "  - shutdown.wav    : Played before system shutdown"
echo ""
echo "To replace sounds, copy your own WAV files (48kHz, stereo) to $SOUNDS_DIR"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status oakhz-audio-events"
echo "  journalctl -u oakhz-audio-events -f"
echo "  sudo systemctl restart oakhz-audio-events"
echo ""
echo "Test sounds manually:"
echo "  paplay --volume=49152 $SOUNDS_DIR/ready.wav"
echo "  paplay --volume=49152 $SOUNDS_DIR/connect.wav"