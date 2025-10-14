#!/bin/bash
#
# OaKhz Audio - Rotary Encoder Control Installation
# To be added to the v3 installation script
#

set -e

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
cat > /usr/local/bin/oakhz-rotary.py << 'EOFPY'
#!/usr/bin/env python3
"""
OaKhz Audio - Rotary Encoder Controller
Using gpiozero library with PulseAudio control
"""
from gpiozero import RotaryEncoder, Button
import subprocess
import sys
from time import sleep, time
import logging
import threading

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

program_version = "3.6"

# GPIO Configuration
CLK_PIN = 23  # pin_a
DT_PIN = 24   # pin_b
SW_PIN = 22   # button

# Volume settings
MIN_VOLUME = 1
MAX_VOLUME = 100
VOLUME_STEP = 3

# Throttling settings
THROTTLE_DELAY = 0.15  # 150ms between volume changes
last_volume_change = 0
volume_lock = threading.Lock()

# Button state for mute/unmute
last_volume = 50

def get_volume():
    """Get current volume from PulseAudio camilladsp_out sink"""
    try:
        result = subprocess.run(
            ['pactl', 'get-sink-volume', 'camilladsp_out'],
            capture_output=True,
            text=True,
            timeout=2
        )
        # Parse: "Volume: front-left: 52428 /  80% / -5.81 dB"
        for line in result.stdout.splitlines():
            if 'Volume:' in line:
                parts = line.split('/')
                if len(parts) >= 2:
                    vol_str = parts[1].strip().replace('%', '')
                    return int(vol_str)
        return 50
    except Exception as e:
        logger.error(f"Get volume error: {e}")
        return 50

def set_volume(volume):
    """Set volume via PulseAudio camilladsp_out sink"""
    volume = max(MIN_VOLUME, min(MAX_VOLUME, volume))
    try:
        subprocess.run(
            ['pactl', 'set-sink-volume', 'camilladsp_out', f'{volume}%'],
            capture_output=True,
            timeout=2
        )
        logger.info(f"Volume: {volume}%")
        return True
    except Exception as e:
        logger.error(f"Set volume error: {e}")
        return False

def volume_up():
    """Increase volume with throttling"""
    global last_volume_change

    with volume_lock:
        now = time()
        if now - last_volume_change < THROTTLE_DELAY:
            return

        current = get_volume()
        new_vol = min(MAX_VOLUME, current + VOLUME_STEP)
        if set_volume(new_vol):
            last_volume_change = now

def volume_down():
    """Decrease volume with throttling"""
    global last_volume_change

    with volume_lock:
        now = time()
        if now - last_volume_change < THROTTLE_DELAY:
            return

        current = get_volume()
        new_vol = max(MIN_VOLUME, current - VOLUME_STEP)
        if set_volume(new_vol):
            last_volume_change = now

def button_pressed():
    """Handle button press - mute/unmute, skip, or shutdown"""
    global last_volume, button

    press_start = time()

    # Wait for button release
    while button.is_pressed:
        sleep(0.01)
        if time() - press_start > 5:  # Safety timeout
            break

    press_duration = time() - press_start

    if press_duration >= 3.0:
        # Long press: shutdown
        logger.warning("Long press → Shutdown")
        try:
            subprocess.run(['mpg123', '-q', '-a', 'hw:Loopback,0', '/opt/oakhz/sounds/shutdown.mp3'],
                         timeout=3, capture_output=True)
            sleep(1)
        except:
            pass
        subprocess.run(['sudo', 'shutdown', '-h', 'now'], check=False)

    elif press_duration >= 0.3:
        # Medium press: skip track
        logger.info("Medium press → Skip track")
        try:
            # Try playerctl first
            result = subprocess.run(['playerctl', 'next'], capture_output=True, timeout=2)
            if result.returncode == 0:
                return

            # Fallback: BlueZ dbus
            result = subprocess.run(['bluetoothctl', 'devices', 'Connected'],
                                  capture_output=True, text=True, timeout=2)
            for line in result.stdout.splitlines():
                if 'Device' in line:
                    parts = line.split()
                    if len(parts) >= 2:
                        mac = parts[1].replace(':', '_')
                        subprocess.run(['dbus-send', '--system', '--type=method_call',
                                      '--dest=org.bluez', f'/org/bluez/hci0/dev_{mac}',
                                      'org.bluez.MediaControl1.Next'],
                                     capture_output=True, timeout=2)
                        return
        except Exception as e:
            logger.error(f"Skip error: {e}")

    else:
        # Short press: mute/unmute
        try:
            current_vol = get_volume()

            if current_vol > 1:
                # Mute
                last_volume = current_vol
                set_volume(1)
                logger.info(f"Muted (saved {last_volume}%)")
            else:
                # Unmute
                restore_vol = last_volume if last_volume > 1 else 50
                set_volume(restore_vol)
                logger.info(f"Unmuted → {restore_vol}%")
        except Exception as e:
            logger.error(f"Mute/unmute error: {e}")

def main():
    global button

    logger.info("=" * 50)
    logger.info(f"OaKhz Rotary Controller v{program_version} (gpiozero)")
    logger.info(f"Encoder: CLK={CLK_PIN}, DT={DT_PIN}, SW={SW_PIN}")
    logger.info("=" * 50)

    # Initialize rotary encoder
    try:
        encoder = RotaryEncoder(CLK_PIN, DT_PIN, max_steps=0)
        encoder.when_rotated_clockwise = volume_up
        encoder.when_rotated_counter_clockwise = volume_down
        logger.info("Rotary encoder initialized")
    except Exception as e:
        logger.error(f"Failed to initialize rotary encoder: {e}")
        sys.exit(1)

    # Initialize button
    try:
        button = Button(SW_PIN, bounce_time=0.2, hold_time=3.0)
        button.when_pressed = button_pressed
        logger.info("Button initialized")
    except Exception as e:
        logger.error(f"Failed to initialize button: {e}")
        sys.exit(1)

    current_vol = get_volume()
    logger.info(f"Current volume: {current_vol}%")
    logger.info("Controls:")
    logger.info("  🔄 Rotate:         Volume ±3%")
    logger.info("  🔘 Short press:    Mute/Unmute")
    logger.info("  🔘 Medium press:   Skip track")
    logger.info("  ⏱️  Long press (3s): Shutdown")
    logger.info("=" * 50)
    logger.info("Rotary controller ready")

    # Keep running
    try:
        while True:
            sleep(0.1)
    except KeyboardInterrupt:
        logger.info("Stopping rotary controller")

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)
EOFPY

chmod +x /usr/local/bin/oakhz-rotary.py

# ============================================
# Systemd service for rotary encoder
# ============================================
cat > /etc/systemd/system/oakhz-rotary.service << EOF
[Unit]
Description=OaKhz Rotary Encoder Controller
After=pulseaudio.service bluetooth.service sound.target
Wants=pulseaudio.service

[Service]
Type=simple
User=$SERVICE_USER
Group=gpio
SupplementaryGroups=audio
WorkingDirectory=/home/$SERVICE_USER
ExecStartPre=/bin/sleep 5
ExecStartPre=/bin/sh -c 'until pactl info >/dev/null 2>&1; do sleep 1; done'
ExecStartPre=/usr/bin/pactl set-sink-volume camilladsp_out 75%
ExecStart=/usr/bin/python3 /usr/local/bin/oakhz-rotary.py
Restart=always
RestartSec=5
Environment="PULSE_SERVER=unix:/run/pulse/native"
Environment="HOME=/home/$SERVICE_USER"

[Install]
WantedBy=multi-user.target
EOF

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
echo "  🔄 Rotate:          Volume up/down (±3% per step)"
echo "  🔘 Single click:    Mute/Unmute"
echo "  🔘 Medium press:    Skip to next track"
echo "  ⏱️  Long press (3s): Shutdown system"
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
