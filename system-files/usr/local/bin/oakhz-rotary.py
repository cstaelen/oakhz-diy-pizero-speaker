#!/usr/bin/env python3
"""
OaKhz Audio - Rotary Encoder Controller
Using gpiozero library (RPi.GPIO event detection doesn't work on this system)
"""
from gpiozero import RotaryEncoder, Button
import subprocess
import sys
from time import sleep, time
import logging
import threading

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

program_version = "4.0"

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

def get_bluetooth_device_path():
    """Get the D-Bus path of the connected Bluetooth device"""
    try:
        result = subprocess.run(['bluetoothctl', 'devices', 'Connected'],
                              capture_output=True, text=True, timeout=2)
        for line in result.stdout.splitlines():
            if 'Device' in line:
                parts = line.split()
                if len(parts) >= 2:
                    mac = parts[1].replace(':', '_')
                    return f"/org/bluez/hci0/dev_{mac}"
        return None
    except Exception:
        return None

def get_playback_status(device_path):
    """Get current playback status (playing/paused/stopped)"""
    try:
        result = subprocess.run([
            'dbus-send', '--system', '--print-reply',
            '--dest=org.bluez',
            f'{device_path}/player0',
            'org.freedesktop.DBus.Properties.Get',
            'string:org.bluez.MediaPlayer1',
            'string:Status'
        ], capture_output=True, text=True, timeout=2)

        if result.returncode == 0:
            for line in result.stdout.splitlines():
                if 'variant' in line and 'string' in line:
                    parts = line.strip().split('"')
                    if len(parts) >= 2:
                        return parts[1].lower()
        return None
    except Exception:
        return None

def bluetooth_play_pause():
    """Toggle play/pause for Bluetooth media"""
    try:
        device_path = get_bluetooth_device_path()
        if not device_path:
            logger.warning("No Bluetooth device connected")
            return False

        # Get current status first to send the correct command
        status = get_playback_status(device_path)

        if status == 'playing':
            # Currently playing, so pause
            result = subprocess.run([
                'dbus-send', '--system', '--type=method_call',
                '--dest=org.bluez',
                device_path,
                'org.bluez.MediaControl1.Pause'
            ], capture_output=True, timeout=2)
            if result.returncode == 0:
                logger.info("Pause command sent via BlueZ MediaControl1")
                return True
        else:
            # Currently paused or stopped, so play
            result = subprocess.run([
                'dbus-send', '--system', '--type=method_call',
                '--dest=org.bluez',
                device_path,
                'org.bluez.MediaControl1.Play'
            ], capture_output=True, timeout=2)
            if result.returncode == 0:
                logger.info("Play command sent via BlueZ MediaControl1")
                return True

        logger.warning("Play/Pause command failed")
        return False

    except Exception as e:
        logger.error(f"Play/Pause error: {e}")
        return False

def bluetooth_next():
    """Skip to next track"""
    try:
        device_path = get_bluetooth_device_path()
        if not device_path:
            logger.warning("No Bluetooth device connected")
            return False

        # Use D-Bus to send AVRCP Next command via BlueZ MediaControl1
        result = subprocess.run([
            'dbus-send', '--system', '--type=method_call',
            '--dest=org.bluez',
            device_path,
            'org.bluez.MediaControl1.Next'
        ], capture_output=True, timeout=2)

        if result.returncode == 0:
            logger.info("Next track via BlueZ MediaControl1")
            return True

        logger.warning("Next track command failed")
        return False

    except Exception as e:
        logger.error(f"Next track error: {e}")
        return False

def button_pressed():
    """Handle button press - play/pause, skip, or shutdown"""
    global button

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

    elif press_duration >= 1.0:
        # Medium press: skip track
        logger.info("Medium press (≥1s) → Skip track")
        bluetooth_next()

    else:
        # Short press: play/pause
        logger.info("Short press (<1s) → Play/Pause")
        bluetooth_play_pause()

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
    logger.info("  🔄 Rotate:           Volume ±3%")
    logger.info("  🔘 Short press (<1s): Play/Pause")
    logger.info("  🔘 Medium press (1s): Skip track")
    logger.info("  ⏱️  Long press (3s):  Shutdown")
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
