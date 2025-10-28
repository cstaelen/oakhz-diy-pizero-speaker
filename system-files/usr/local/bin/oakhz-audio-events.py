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
