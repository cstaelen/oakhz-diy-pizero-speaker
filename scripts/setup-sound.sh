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
echo "Creating demo audio files..."

# Note: These commands require 'sox' to generate sounds
# If you want to use your own WAVs, place them in $SOUNDS_DIR

if command -v sox &> /dev/null; then
    # Generate pleasant sounds for each event

    # Ready sound (ascending major chord arpeggio - C major)
    # Plays when Bluetooth is discoverable and ready
    sox -n -r 48000 -c 2 $SOUNDS_DIR/ready.wav \
        synth 0.15 pluck C4 synth 0.15 pluck E4 synth 0.15 pluck G4 synth 0.2 pluck C5 \
        fade t 0.01 0.6 0.1 norm -9

    # Connect sound (pleasant "ding" - high chime)
    # Plays when a Bluetooth device connects
    sox -n -r 48000 -c 2 $SOUNDS_DIR/connect.wav \
        synth 0.08 sine 1760 fade t 0.01 0.08 0.01 : synth 0.12 sine 2093 fade t 0.01 0.12 0.08 \
        norm -12

    # Disconnect sound (subtle "bloop" - lower tone)
    # Plays when a Bluetooth device disconnects
    sox -n -r 48000 -c 2 $SOUNDS_DIR/disconnect.wav \
        synth 0.12 sine 587 fade t 0.01 0.12 0.05 : synth 0.08 sine 523 fade t 0.01 0.08 0.05 \
        norm -12

    # Shutdown sound (descending minor chord - soft goodbye)
    # Plays before system shutdown
    sox -n -r 48000 -c 2 $SOUNDS_DIR/shutdown.wav \
        synth 0.15 pluck G4 synth 0.15 pluck E4 synth 0.15 pluck C4 synth 0.25 pluck G3 \
        fade t 0.01 0.7 0.2 norm -9

    echo "Demo audio files created successfully"
else
    echo "Note: sox not installed, demo sounds not generated"
    echo "You can place your own WAV files in $SOUNDS_DIR:"
    echo "  - ready.wav (startup - Bluetooth ready)"
    echo "  - connect.wav (device connection)"
    echo "  - disconnect.wav (device disconnection)"
    echo "  - shutdown.wav (system shutdown)"

    # Create empty files to avoid errors
    touch $SOUNDS_DIR/ready.wav
    touch $SOUNDS_DIR/connect.wav
    touch $SOUNDS_DIR/disconnect.wav
    touch $SOUNDS_DIR/shutdown.wav
fi

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