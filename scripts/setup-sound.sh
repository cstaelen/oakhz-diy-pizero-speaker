#!/bin/bash
#
# OaKhz Audio - Audio Feedback Services Installation
# To be added to the installation script
#

set -e

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
cat > /usr/local/bin/oakhz-audio-events.py << 'EOFPY'
#!/usr/bin/env python3
"""
OaKhz Audio Events Manager
Manages all audio feedback events:
- Startup ready sound (Bluetooth discoverable)
- Device connection/disconnection sounds
- Single device mode (auto-disconnect old devices)
"""
import subprocess
import time
import logging
import sys
import os

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# Sound files
SOUND_READY = '/opt/oakhz/sounds/ready.wav'
SOUND_CONNECT = "/opt/oakhz/sounds/connect.wav"
SOUND_DISCONNECT = "/opt/oakhz/sounds/disconnect.wav"

def play_sound(sound_file, restore_volume=True):
    """Play sound using paplay (PulseAudio) with volume adjustment"""
    try:
        logger.info(f'Playing: {sound_file}')
        volume_percent = 80
        pa_volume = int(65536 * volume_percent / 100)

        env = os.environ.copy()
        env['PULSE_SERVER'] = 'unix:/run/pulse/native'

        result = subprocess.run(
            ['paplay', '--volume', str(pa_volume), sound_file],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
            env=env
        )
        if result.returncode != 0:
            logger.error(f'paplay error: {result.stderr}')
        else:
            logger.info('Sound played successfully')
    except Exception as e:
        logger.error(f'Sound playback error: {e}')

def play_ready_sound():
    """Play ready sound at startup"""
    logger.info('Playing ready sound (Bluetooth discoverable)')
    # Wait for audio system to be fully ready
    play_sound(SOUND_READY, restore_volume=False)
    logger.info('Ready sound played')

def disconnect_device(mac_address):
    """Disconnect a Bluetooth device"""
    try:
        result = subprocess.run(
            ['bluetoothctl', 'disconnect', mac_address],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            logger.info(f"Disconnected old device: {mac_address}")
            return True
        return False
    except Exception as e:
        logger.error(f"Disconnect error: {e}")
        return False

def get_connected_devices():
    """Get list of connected device MAC addresses using bluetoothctl info"""
    try:
        result = subprocess.run(
            ['bluetoothctl', 'devices'],
            capture_output=True,
            text=True,
            timeout=5
        )
        devices = set()
        for line in result.stdout.splitlines():
            if 'Device' in line:
                mac = line.split()[1]
                # Check if device is connected
                info = subprocess.run(
                    ['bluetoothctl', 'info', mac],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if 'Connected: yes' in info.stdout:
                    devices.add(mac)
        return devices
    except Exception as e:
        logger.error(f'Device retrieval error: {e}')
        return set()

def monitor_bluetooth():
    """Monitor Bluetooth connections (single device mode, robust reconnection detection)"""
    logger.info('Starting Bluetooth monitor (single device mode)')
    previous_devices = set()
    last_connected_device = None

    while True:
        try:
            current_devices = get_connected_devices()
            logger.info(f"🔍 Current: {current_devices}, Last: {last_connected_device}")

            if len(current_devices) > 1:
                logger.warning(f"Multiple devices connected: {current_devices}. Enforcing single device mode.")
                first_device = list(current_devices)[0]
                for mac in current_devices:
                    if mac != first_device:
                        logger.info(f"Disconnecting extra device: {mac}")
                        disconnect_device(mac)
                current_devices = {first_device}
                time.sleep(1)

            if current_devices:
                current_device = list(current_devices)[0]
                if current_device != last_connected_device:
                    logger.info(f'Device connected/reconnected: {current_device}')
                    # time.sleep(2)
                    play_sound(SOUND_CONNECT)
                    last_connected_device = current_device
            else:
                if last_connected_device is not None:
                    logger.info(f'Device disconnected: {last_connected_device}')
                    last_connected_device = None

            previous_devices = current_devices.copy()
            time.sleep(1)

        except KeyboardInterrupt:
            logger.info('Stopping Bluetooth monitor')
            break
        except Exception as e:
            logger.error(f'Error: {e}')
            time.sleep(5)

def main():
    logger.info('=' * 60)
    logger.info('OaKhz Audio Events Manager starting...')
    logger.info('=' * 60)

    # Parse command line arguments
    if len(sys.argv) > 1:
        if sys.argv[1] == '--ready-only':
            # Only play ready sound and exit (for oneshot service)
            play_ready_sound()
            return
        elif sys.argv[1] == '--monitor-only':
            # Only monitor Bluetooth (no ready sound)
            monitor_bluetooth()
            return

    # Default: play ready sound, then monitor Bluetooth
    play_ready_sound()
    monitor_bluetooth()

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        logger.error(f'Fatal error: {e}')
        sys.exit(1)
EOFPY

chmod +x /usr/local/bin/oakhz-audio-events.py

# Systemd service for unified audio events manager
cat > /etc/systemd/system/oakhz-audio-events.service << 'EOF'
[Unit]
Description=OaKhz Audio Events Manager
After=sound.target bluetooth.target pulseaudio.service
Wants=bluetooth.service

[Service]
Type=simple
User=oakhz
Group=audio
#ExecStartPre=/bin/sleep 5
ExecStartPre=/bin/sh -c 'until pactl info >/dev/null 2>&1; do sleep 1; done'
ExecStart=/usr/bin/python3 /usr/local/bin/oakhz-audio-events.py
Restart=always
RestartSec=5
Environment="XDG_RUNTIME_DIR=/run/user/1000"
Environment="PULSE_RUNTIME_PATH=/run/user/1000/pulse"

[Install]
WantedBy=multi-user.target
EOF

# ============================================
# Script 3: Sound before shutdown
# ============================================
cat > /usr/local/bin/oakhz-shutdown-sound.sh << 'EOF'
#!/bin/bash
# Play shutdown sound directly via ALSA (bypass PulseAudio)
# Stop CamillaDSP first to release the DAC
# Uses pre-adjusted 25% volume WAV file

# Stop CamillaDSP to release the HiFiBerry DAC
systemctl stop camilladsp.service 2>/dev/null

# Small delay to ensure DAC is released
sleep 0.2

# Play directly to HiFiBerry DAC using plughw for automatic rate conversion
# Volume is pre-adjusted to 25% in the WAV file
aplay -D plughw:1,0 /opt/oakhz/sounds/shutdown.wav 2>/dev/null

# Wait for playback to complete
sleep 1
EOF

chmod +x /usr/local/bin/oakhz-shutdown-sound.sh

# Systemd service for shutdown sound
cat > /etc/systemd/system/oakhz-shutdown-sound.service << 'EOF'
[Unit]
Description=OaKhz Shutdown Sound
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/oakhz-shutdown-sound.sh
TimeoutStartSec=10
RemainAfterExit=yes

[Install]
WantedBy=halt.target reboot.target shutdown.target
EOF

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