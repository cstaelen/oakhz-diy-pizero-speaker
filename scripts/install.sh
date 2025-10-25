#!/bin/bash
#
# OaKhz Audio - Installation Script
# Automatic installation for Raspberry Pi OS Lite + HiFiBerry MiniAmp
#

set -e

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}"
echo "=================================="
echo "  OaKhz Audio - Installation"
echo "=================================="
echo -e "${NC}"

# Root verification
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# Automatic user detection
if [ -n "$SUDO_USER" ]; then
    SERVICE_USER="$SUDO_USER"
else
    SERVICE_USER=$(logname 2>/dev/null || echo "pi")
fi

echo -e "${GREEN}Detected user: $SERVICE_USER${NC}"

INSTALL_DIR="/opt/oakhz"
USER_HOME="/home/$SERVICE_USER"

echo -e "${YELLOW}[1/9] Enabling Bluetooth...${NC}"
rfkill unblock bluetooth
sleep 2
hciconfig hci0 up

echo -e "${YELLOW}[2/9] System update...${NC}"
apt update
apt upgrade -y

echo -e "${YELLOW}[3/9] Installing dependencies...${NC}"
apt install -y \
    bluez \
    bluez-tools \
    pulseaudio \
    pulseaudio-module-bluetooth \
    alsa-utils \
    python3-pip \
    python3-flask \
    python3-flask-cors \
    python3-yaml \
    python3-websocket \
    wget

echo -e "${YELLOW}[3.5/9] Installation de CamillaDSP...${NC}"

# Télécharge CamillaDSP (version ARM64)
CAMILLADSP_VERSION="2.0.3"
CAMILLADSP_URL="https://github.com/HEnquist/camilladsp/releases/download/v${CAMILLADSP_VERSION}/camilladsp-linux-aarch64.tar.gz"

cd /tmp
wget -O camilladsp.tar.gz "$CAMILLADSP_URL"
tar -xzf camilladsp.tar.gz
mv camilladsp /usr/local/bin/
chmod +x /usr/local/bin/camilladsp
rm camilladsp.tar.gz

echo -e "${GREEN}CamillaDSP installé : $(camilladsp --version)${NC}"

echo -e "${YELLOW}[4/9] Configuration du HiFiBerry MiniAmp...${NC}"

# Détecte le bon chemin config.txt
if [ -f /boot/firmware/config.txt ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
elif [ -f /boot/config.txt ]; then
    CONFIG_FILE="/boot/config.txt"
else
    echo -e "${RED}Fichier config.txt introuvable${NC}"
    exit 1
fi

echo -e "${GREEN}Configuration found : $CONFIG_FILE${NC}"

# Backup
cp $CONFIG_FILE ${CONFIG_FILE}.backup

# Disable onboard audio
sed -i 's/^dtparam=audio=on/#dtparam=audio=on/' $CONFIG_FILE

# Add HiFiBerry overlay if not already present
if ! grep -q "dtoverlay=hifiberry-dac" $CONFIG_FILE; then
    echo "dtoverlay=hifiberry-dac" >> $CONFIG_FILE
    echo -e "${GREEN}HiFiBerry MiniAmp configured${NC}"
else
    echo -e "${GREEN}HiFiBerry MiniAmp already configured${NC}"
fi

echo -e "${YELLOW}[5/9] Bluetooth configuration...${NC}"

# Backup existing config
if [ -f /etc/bluetooth/main.conf ]; then
    cp /etc/bluetooth/main.conf /etc/bluetooth/main.conf.backup
fi

# Bluetooth configuration
cat > /etc/bluetooth/main.conf << 'EOF'
[General]
Name = OaKhz audio
Class = 0x400428
DiscoverableTimeout = 0
PairableTimeout = 0
JustWorksRepairing = always
FastConnectable = true

[Policy]
AutoEnable = true
EOF

echo -e "${YELLOW}[6/9] PulseAudio configuration...${NC}"

# PulseAudio system service
cat > /etc/systemd/system/pulseaudio.service << 'EOF'
[Unit]
Description=PulseAudio system server
After=bluetooth.service

[Service]
Type=notify
ExecStart=/usr/bin/pulseaudio --system --disallow-exit --log-target=journal
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Add pulse to bluetooth group
usermod -a -G bluetooth pulse

# PulseAudio system configuration for CamillaDSP and Bluetooth
sed -i 's/load-module module-udev-detect$/load-module module-udev-detect ignore_dB=1 tsched=0/' /etc/pulse/system.pa

# Add Bluetooth and CamillaDSP à system.pa
cat >> /etc/pulse/system.pa << 'EOFPA'

### Bluetooth Support
.ifexists module-bluetooth-policy.so
load-module module-bluetooth-policy
.endif

.ifexists module-bluetooth-discover.so
load-module module-bluetooth-discover autodetect_mtu=yes
.endif

### Blacklist auto-detected cards
.nofail
unload-module module-alsa-card
.fail

### CamillaDSP Sink
.nofail
load-module module-alsa-sink device=hw:Loopback,0 sink_name=camilladsp_out rate=48000
.fail
set-default-sink camilladsp_out

### Auto-switch and route Bluetooth connections
load-module module-switch-on-connect
EOFPA

# Load ALSA loopback module pour CamillaDSP
if ! lsmod | grep -q snd_aloop; then
    modprobe snd-aloop
    echo "snd-aloop" >> /etc/modules
fi

# ALSA configuration for HiFiBerry + CamillaDSP
cat > /etc/asound.conf << 'EOF'
# CamillaDSP Device (uses loopback)
pcm.camilladsp {
    type plug
    slave.pcm "hw:Loopback,0"
}

# Default playback via CamillaDSP
pcm.!default {
    type plug
    slave.pcm "camilladsp"
}

# Default control
ctl.!default {
    type hw
    card 0
}
EOF

# Configuration CamillaDSP
mkdir -p /opt/camilladsp
cat > /opt/camilladsp/config.yml << 'EOF'
---
devices:
  samplerate: 48000
  chunksize: 1024
  capture:
    type: Alsa
    channels: 2
    device: "hw:Loopback,1"
    format: S16LE
  playback:
    type: Alsa
    channels: 2
    device: "hw:1,0"
    format: S16LE

filters:
  # 10-band parametric equalizer
  eq_31:
    type: Biquad
    parameters:
      type: Peaking
      freq: 31
      q: 1.0
      gain: 0.0
  eq_63:
    type: Biquad
    parameters:
      type: Peaking
      freq: 63
      q: 1.0
      gain: 0.0
  eq_125:
    type: Biquad
    parameters:
      type: Peaking
      freq: 125
      q: 1.0
      gain: 0.0
  eq_250:
    type: Biquad
    parameters:
      type: Peaking
      freq: 250
      q: 1.0
      gain: 0.0
  eq_500:
    type: Biquad
    parameters:
      type: Peaking
      freq: 500
      q: 1.0
      gain: 0.0
  eq_1k:
    type: Biquad
    parameters:
      type: Peaking
      freq: 1000
      q: 1.0
      gain: 0.0
  eq_2k:
    type: Biquad
    parameters:
      type: Peaking
      freq: 2000
      q: 1.0
      gain: 0.0
  eq_4k:
    type: Biquad
    parameters:
      type: Peaking
      freq: 4000
      q: 1.0
      gain: 0.0
  eq_8k:
    type: Biquad
    parameters:
      type: Peaking
      freq: 8000
      q: 1.0
      gain: 0.0
  eq_16k:
    type: Biquad
    parameters:
      type: Peaking
      freq: 16000
      q: 1.0
      gain: 0.0

pipeline:
  - type: Filter
    channel: 0
    names:
      - eq_31
      - eq_63
      - eq_125
      - eq_250
      - eq_500
      - eq_1k
      - eq_2k
      - eq_4k
      - eq_8k
      - eq_16k
  - type: Filter
    channel: 1
    names:
      - eq_31
      - eq_63
      - eq_125
      - eq_250
      - eq_500
      - eq_1k
      - eq_2k
      - eq_4k
      - eq_8k
      - eq_16k
EOF

chmod 644 /opt/camilladsp/config.yml

# Service systemd pour CamillaDSP
cat > /etc/systemd/system/camilladsp.service << 'EOF'
[Unit]
Description=CamillaDSP Audio Processor
After=sound.target

[Service]
Type=simple
ExecStart=/usr/local/bin/camilladsp -p 1234 /opt/camilladsp/config.yml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo -e "${YELLOW}[7/9] Web Equalizer server installation...${NC}"

# Creating directories
mkdir -p $INSTALL_DIR/templates
cd $INSTALL_DIR

# Flask server
cat > $INSTALL_DIR/eq_server.py << 'EOFPY'
from flask import Flask, jsonify, request, render_template
from flask_cors import CORS
import subprocess
import os
import json
import logging
import yaml
import signal

app = Flask(__name__, template_folder='templates')
CORS(app)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONFIG_FILE = os.path.expanduser('~/.oakhz_eq.json')
CAMILLADSP_CONFIG = '/opt/camilladsp/config.yml'

class EqualizerController:
    def __init__(self):
        self.bands = 10
        self.band_names = ['eq_31', 'eq_63', 'eq_125', 'eq_250', 'eq_500', 'eq_1k', 'eq_2k', 'eq_4k', 'eq_8k', 'eq_16k']
        self.load_config()

    def load_config(self):
        try:
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r') as f:
                    self.config = json.load(f)
            else:
                self.config = {
                    'enabled': True,
                    'preamp': 0,
                    'bands': [0] * self.bands,
                    'preset': 'flat'
                }
                self.save_config()
        except Exception as e:
            logger.error(f"Config load error: {e}")
            self.config = {'enabled': True, 'preamp': 0, 'bands': [0] * self.bands, 'preset': 'flat'}

    def save_config(self):
        try:
            with open(CONFIG_FILE, 'w') as f:
                json.dump(self.config, f, indent=2)
        except Exception as e:
            logger.error(f"Config save error: {e}")

    def update_camilladsp(self):
        """Met à jour la config CamillaDSP et recharge"""
        try:
            # Lit la config CamillaDSP
            with open(CAMILLADSP_CONFIG, 'r') as f:
                cdsp_config = yaml.safe_load(f)

            # Met à jour ou crée le filtre preamp (gain global)
            preamp_gain = self.config['preamp'] if self.config['enabled'] else 0.0
            if 'preamp_gain' not in cdsp_config['filters']:
                cdsp_config['filters']['preamp_gain'] = {
                    'type': 'Gain',
                    'parameters': {
                        'gain': preamp_gain,
                        'inverted': False
                    }
                }
            else:
                cdsp_config['filters']['preamp_gain']['parameters']['gain'] = preamp_gain

            # Met à jour les gains de chaque bande EQ
            for i, band_name in enumerate(self.band_names):
                gain = self.config['bands'][i] if self.config['enabled'] else 0.0
                if band_name in cdsp_config['filters']:
                    cdsp_config['filters'][band_name]['parameters']['gain'] = gain

            # Ajoute le preamp au début du pipeline s'il n'y est pas
            if 'pipeline' in cdsp_config:
                for channel_pipeline in cdsp_config['pipeline']:
                    if 'names' in channel_pipeline:
                        if 'preamp_gain' not in channel_pipeline['names']:
                            channel_pipeline['names'].insert(0, 'preamp_gain')

            # Sauvegarde la config CamillaDSP
            with open(CAMILLADSP_CONFIG, 'w') as f:
                yaml.dump(cdsp_config, f, default_flow_style=False)

            # Recharge CamillaDSP (envoie SIGHUP)
            subprocess.run(['sudo', 'pkill', '-HUP', 'camilladsp'], check=False)
            logger.info("CamillaDSP config updated and reloaded")
            return True
        except Exception as e:
            logger.error(f"CamillaDSP update error: {e}")
            return False

    def set_band(self, band_index, value):
        try:
            self.config['bands'][band_index] = value
            self.save_config()
            self.update_camilladsp()
            logger.info(f"Band {band_index} set to {value} dB")
            return True
        except Exception as e:
            logger.error(f"Band {band_index} error: {e}")
            return False

    def set_preamp(self, value):
        try:
            self.config['preamp'] = value
            self.save_config()
            self.update_camilladsp()
            logger.info(f"Preamp set to {value} dB")
            return True
        except Exception as e:
            logger.error(f"Preamp error: {e}")
            return False

    def set_enabled(self, enabled):
        try:
            self.config['enabled'] = enabled
            self.save_config()
            self.update_camilladsp()
            logger.info(f"Equalizer {'enabled' if enabled else 'disabled'}")
            return True
        except Exception as e:
            logger.error(f"Enable error: {e}")
            return False

    def apply_preset(self, preset_name):
        presets = {
            'flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            'rock': [5, 4, -2, -3, -1, 2, 4, 5, 5, 5],
            'pop': [-1, 3, 4, 4, 2, -1, -2, -2, -1, -1],
            'jazz': [4, 3, 1, 2, -1, -1, 0, 1, 2, 3],
            'classical': [5, 4, 3, 2, -1, -1, 0, 2, 3, 4],
            'bass': [6, 5, 4, 2, 0, -1, -2, -3, -3, -3],
            'treble': [-3, -3, -2, -1, 0, 2, 4, 5, 6, 6],
            'vocal': [-2, -3, -2, 1, 3, 3, 2, 1, 0, -1]
        }
        if preset_name not in presets:
            return False
        values = presets[preset_name]
        for i, value in enumerate(values):
            self.config['bands'][i] = value
        self.config['preset'] = preset_name
        self.save_config()
        self.update_camilladsp()
        logger.info(f"Preset '{preset_name}' applied")
        return True

    def apply_current_config(self):
        self.update_camilladsp()

    def get_config(self):
        return self.config

eq = EqualizerController()

@app.route('/api/equalizer', methods=['GET'])
def get_equalizer():
    return jsonify(eq.get_config())

@app.route('/api/equalizer', methods=['POST'])
def update_equalizer():
    data = request.json
    action_type = data.get('type')
    action_data = data.get('data')

    success = False
    if action_type == 'band':
        success = eq.set_band(action_data['index'], action_data['value'])
    elif action_type == 'preamp':
        success = eq.set_preamp(action_data['value'])
    elif action_type == 'enabled':
        success = eq.set_enabled(action_data['value'])
    elif action_type == 'preset':
        success = eq.apply_preset(action_data['name'])

    if success:
        return jsonify({'status': 'ok', 'config': eq.get_config()})
    else:
        return jsonify({'status': 'error'}), 500

@app.route('/api/bluetooth/devices', methods=['GET'])
def get_bluetooth_devices():
    try:
        result = subprocess.run(['bluetoothctl', 'devices', 'Connected'], capture_output=True, text=True)
        devices = []
        for line in result.stdout.splitlines():
            if 'Device' in line:
                parts = line.split()
                if len(parts) >= 3:
                    devices.append({'address': parts[1], 'name': ' '.join(parts[2:])})
        return jsonify({'devices': devices})
    except Exception as e:
        logger.error(f"Bluetooth error: {e}")
        return jsonify({'devices': []}), 500

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

def get_dbus_property(device_path, interface, property_name):
    """Get a D-Bus property value"""
    try:
        result = subprocess.run([
            'dbus-send', '--system', '--print-reply',
            '--dest=org.bluez',
            f'{device_path}/player0',
            'org.freedesktop.DBus.Properties.Get',
            f'string:{interface}',
            f'string:{property_name}'
        ], capture_output=True, text=True, timeout=2)

        if result.returncode == 0:
            # Parse the output to extract the value
            for line in result.stdout.splitlines():
                if 'variant' in line or 'string' in line:
                    # Extract value after the type
                    parts = line.strip().split('"')
                    if len(parts) >= 2:
                        return parts[1]
        return None
    except Exception:
        return None

@app.route('/api/media/info', methods=['GET'])
def get_media_info():
    """Get current playing media metadata (artist, title, status)"""
    try:
        device_path = get_bluetooth_device_path()
        if not device_path:
            return jsonify({
                'status': 'stopped',
                'artist': 'No device connected',
                'title': 'Connect a Bluetooth device',
                'album': ''
            })

        # Get metadata via BlueZ D-Bus
        info = {}

        # Get status
        status = get_dbus_property(device_path, 'org.bluez.MediaPlayer1', 'Status')
        info['status'] = status.lower() if status else 'stopped'

        # Get Track metadata (contains all track info)
        result = subprocess.run([
            'dbus-send', '--system', '--print-reply',
            '--dest=org.bluez',
            f'{device_path}/player0',
            'org.freedesktop.DBus.Properties.Get',
            'string:org.bluez.MediaPlayer1',
            'string:Track'
        ], capture_output=True, text=True, timeout=2)

        # Parse the Track dictionary
        info['artist'] = 'Unknown Artist'
        info['title'] = 'Unknown Title'
        info['album'] = ''

        if result.returncode == 0:
            lines = result.stdout.splitlines()
            current_key = None
            for line in lines:
                line = line.strip()
                if 'string "Title"' in line:
                    current_key = 'title'
                elif 'string "Artist"' in line:
                    current_key = 'artist'
                elif 'string "Album"' in line:
                    current_key = 'album'
                elif current_key and 'variant' in line and 'string "' in line:
                    # Extract value between quotes
                    parts = line.split('string "')
                    if len(parts) >= 2:
                        value = parts[1].rstrip('"')
                        info[current_key] = value
                        current_key = None

        return jsonify(info)
    except Exception as e:
        logger.error(f"Media info error: {e}")
        return jsonify({
            'status': 'stopped',
            'artist': 'Unknown Artist',
            'title': 'No media playing',
            'album': ''
        })

@app.route('/api/media/play', methods=['POST'])
def media_play():
    """Play media"""
    try:
        device_path = get_bluetooth_device_path()
        if not device_path:
            return jsonify({'status': 'error', 'message': 'No device connected'}), 400

        subprocess.run([
            'dbus-send', '--system', '--type=method_call',
            '--dest=org.bluez',
            device_path,
            'org.bluez.MediaControl1.Play'
        ], capture_output=True, timeout=2)
        logger.info("Media: Play")
        return jsonify({'status': 'ok'})
    except Exception as e:
        logger.error(f"Media play error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/media/pause', methods=['POST'])
def media_pause():
    """Pause media"""
    try:
        device_path = get_bluetooth_device_path()
        if not device_path:
            return jsonify({'status': 'error', 'message': 'No device connected'}), 400

        subprocess.run([
            'dbus-send', '--system', '--type=method_call',
            '--dest=org.bluez',
            device_path,
            'org.bluez.MediaControl1.Pause'
        ], capture_output=True, timeout=2)
        logger.info("Media: Pause")
        return jsonify({'status': 'ok'})
    except Exception as e:
        logger.error(f"Media pause error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/media/play-pause', methods=['POST'])
def media_play_pause():
    """Toggle play/pause"""
    try:
        device_path = get_bluetooth_device_path()
        if not device_path:
            return jsonify({'status': 'error', 'message': 'No device connected'}), 400

        # Get current status first
        status = get_dbus_property(device_path, 'org.bluez.MediaPlayer1', 'Status')

        if status and status.lower() == 'playing':
            # Currently playing, so pause
            subprocess.run([
                'dbus-send', '--system', '--type=method_call',
                '--dest=org.bluez',
                device_path,
                'org.bluez.MediaControl1.Pause'
            ], capture_output=True, timeout=2)
            logger.info("Media: Pause")
        else:
            # Currently paused or stopped, so play
            subprocess.run([
                'dbus-send', '--system', '--type=method_call',
                '--dest=org.bluez',
                device_path,
                'org.bluez.MediaControl1.Play'
            ], capture_output=True, timeout=2)
            logger.info("Media: Play")

        return jsonify({'status': 'ok'})
    except Exception as e:
        logger.error(f"Media play-pause error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/media/next', methods=['POST'])
def media_next():
    """Skip to next track"""
    try:
        device_path = get_bluetooth_device_path()
        if not device_path:
            return jsonify({'status': 'error', 'message': 'No device connected'}), 400

        subprocess.run([
            'dbus-send', '--system', '--type=method_call',
            '--dest=org.bluez',
            device_path,
            'org.bluez.MediaControl1.Next'
        ], capture_output=True, timeout=2)
        logger.info("Media: Next track")
        return jsonify({'status': 'ok'})
    except Exception as e:
        logger.error(f"Media next error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/media/previous', methods=['POST'])
def media_previous():
    """Go to previous track"""
    try:
        device_path = get_bluetooth_device_path()
        if not device_path:
            return jsonify({'status': 'error', 'message': 'No device connected'}), 400

        subprocess.run([
            'dbus-send', '--system', '--type=method_call',
            '--dest=org.bluez',
            device_path,
            'org.bluez.MediaControl1.Previous'
        ], capture_output=True, timeout=2)
        logger.info("Media: Previous track")
        return jsonify({'status': 'ok'})
    except Exception as e:
        logger.error(f"Media previous error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/')
def home():
    return render_template('index.html')

# Import WiFi management routes
try:
    from wifi_manager_routes import add_wifi_routes
    add_wifi_routes(app)
    logger.info("WiFi management interface enabled")
except Exception as e:
    logger.warning(f"WiFi management not available: {e}")

if __name__ == '__main__':
    eq.apply_current_config()
    app.run(host='0.0.0.0', port=80, debug=False)
EOFPY

chmod +x $INSTALL_DIR/eq_server.py

# Web Interface HTML
cat > $INSTALL_DIR/templates/index.html << 'EOFHTML'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OaKhz Audio - Equalizer</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            background: linear-gradient(135deg, #2d2520 0%, #3d3530 50%, #2d2520 100%);
            color: #f5f0e8;
            min-height: 100vh;
            padding: 20px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        header { text-align: center; margin-bottom: 40px; }
        h1 {
            font-size: 2.5rem;
            background: linear-gradient(135deg, #d4a574 0%, #c89860 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            margin-bottom: 10px;
        }
        .subtitle { color: #b8a894; font-size: 1rem; }
        .card {
            background: rgba(80, 65, 55, 0.4);
            backdrop-filter: blur(10px);
            border: 1px solid #6b5848;
            border-radius: 16px;
            padding: 24px;
            margin-bottom: 24px;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.4);
        }

        /* Media Player Styles */
        .media-player {
            margin-bottom: 24px;
        }
        .media-info {
            text-align: center;
            margin-bottom: 20px;
            padding: 20px;
            background: rgba(90, 74, 58, 0.3);
            border-radius: 12px;
        }
        .media-title {
            font-size: 1.4rem;
            font-weight: 600;
            color: #f5f0e8;
            margin-bottom: 8px;
        }
        .media-artist {
            font-size: 1.1rem;
            color: #d4c4b0;
            margin-bottom: 4px;
        }
        .media-album {
            font-size: 0.9rem;
            color: #b8a894;
        }
        .media-status {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.8rem;
            margin-top: 8px;
            text-transform: uppercase;
            font-weight: 600;
        }
        .media-status.playing {
            background: rgba(76, 175, 80, 0.3);
            color: #4caf50;
        }
        .media-status.paused {
            background: rgba(255, 193, 7, 0.3);
            color: #ffc107;
        }
        .media-status.stopped {
            background: rgba(158, 158, 158, 0.3);
            color: #9e9e9e;
        }
        .media-controls {
            display: flex;
            justify-content: center;
            gap: 12px;
        }
        .media-btn {
            width: 56px;
            height: 56px;
            border: none;
            border-radius: 50%;
            cursor: pointer;
            font-size: 1.3rem;
            display: flex;
            align-items: center;
            justify-content: center;
            transition: all 0.2s;
            background: #5a4a3a;
            color: #f5f0e8;
        }
        .media-btn:hover {
            background: #6b5848;
            transform: scale(1.05);
        }
        .media-btn.play-pause {
            width: 72px;
            height: 72px;
            font-size: 1.8rem;
            background: #8b6f47;
        }
        .media-btn.play-pause:hover {
            background: #a58556;
        }

        .controls-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 24px;
        }
        .controls-title {
            display: flex;
            align-items: center;
            gap: 10px;
            font-size: 1.2rem;
            font-weight: 600;
        }
        .btn {
            padding: 10px 20px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 0.9rem;
            font-weight: 500;
            transition: all 0.2s;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .btn-power { background: #8b6f47; }
        .btn-power:hover { background: #a58556; }
        .btn-power.off { background: #5a4a3a; }
        .btn-power.off:hover { background: #6b5848; }
        .presets { margin-bottom: 24px; }
        .presets label {
            display: block;
            font-size: 0.9rem;
            color: #d4c4b0;
            margin-bottom: 12px;
        }
        .preset-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 8px;
        }
        .preset-btn {
            padding: 10px 16px;
            background: #5a4a3a;
            border: none;
            border-radius: 8px;
            color: #f5f0e8;
            cursor: pointer;
            transition: all 0.2s;
            text-transform: capitalize;
        }
        .preset-btn:hover { background: #6b5848; }
        .preset-btn.active { background: #a58556; }
        .preset-btn.active:hover { background: #b89660; }
        .preamp-control { margin-bottom: 24px; }
        .preamp-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 8px;
        }
        .preamp-value {
            font-family: 'Courier New', monospace;
            background: #5a4a3a;
            padding: 4px 12px;
            border-radius: 6px;
            font-size: 0.9rem;
            color: #f5f0e8;
        }
        .slider {
            width: 100%;
            height: 8px;
            background: #5a4a3a;
            border-radius: 4px;
            outline: none;
            -webkit-appearance: none;
            cursor: pointer;
        }
        .slider::-webkit-slider-thumb {
            -webkit-appearance: none;
            width: 20px;
            height: 20px;
            background: #c89860;
            border-radius: 50%;
            cursor: pointer;
            box-shadow: 0 0 10px rgba(200, 152, 96, 0.5);
        }
        .slider::-moz-range-thumb {
            width: 20px;
            height: 20px;
            background: #c89860;
            border-radius: 50%;
            cursor: pointer;
            border: none;
        }
        .slider:disabled::-webkit-slider-thumb {
            background: #7a6a5a;
            box-shadow: none;
        }
        .btn-reset {
            width: 100%;
            background: #5a4a3a;
            color: #f5f0e8;
            justify-content: center;
        }
        .btn-reset:hover { background: #6b5848; }
        .equalizer { padding: 24px; }
        .eq-title {
            font-size: 1.2rem;
            font-weight: 600;
            margin-bottom: 24px;
        }
        .bands {
            display: grid;
            grid-template-columns: repeat(10, 1fr);
            gap: 16px;
        }
        .band {
            display: flex;
            flex-direction: column;
            align-items: center;
        }
        .band-slider-container {
            position: relative;
            width: 48px;
            height: 192px;
            background: #5a4a3a;
            border-radius: 8px;
            margin-bottom: 12px;
        }
        .band-slider {
            position: absolute;
            width: 192px;
            height: 48px;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%) rotate(-90deg);
            transform-origin: center;
        }
        .band-center-line {
            position: absolute;
            top: 50%;
            left: 0;
            right: 0;
            height: 2px;
            background: #6b5848;
            pointer-events: none;
        }
        .band-value {
            font-family: 'Courier New', monospace;
            background: #5a4a3a;
            padding: 4px 8px;
            border-radius: 6px;
            font-size: 0.75rem;
            margin-bottom: 4px;
            color: #f5f0e8;
        }
        .band-label {
            font-size: 0.7rem;
            color: #b8a894;
            text-align: center;
        }
        footer {
            text-align: center;
            margin-top: 24px;
            color: #8a7a6a;
            font-size: 0.85rem;
        }
        @media (max-width: 768px) {
            .bands { grid-template-columns: repeat(5, 1fr); }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🎵 OaKhz Audio</h1>
            <p class="subtitle">Equalizer & Media Controller</p>
        </header>

        <!-- Media Player Card -->
        <div class="card media-player">
            <div class="controls-title" style="margin-bottom: 20px;">
                <span>🎧</span>
                <span>Now Playing</span>
            </div>

            <div class="media-info">
                <div class="media-title" id="mediaTitle">No media playing</div>
                <div class="media-artist" id="mediaArtist">Unknown Artist</div>
                <div class="media-album" id="mediaAlbum"></div>
                <span class="media-status stopped" id="mediaStatus">stopped</span>
            </div>

            <div class="media-controls">
                <button class="media-btn" onclick="mediaPrevious()" title="Previous">⏮</button>
                <button class="media-btn play-pause" onclick="mediaPlayPause()" title="Play/Pause">
                    <span id="playPauseIcon">▶️</span>
                </button>
                <button class="media-btn" onclick="mediaNext()" title="Next">⏭</button>
            </div>
        </div>

        <!-- Equalizer Card -->
        <div class="card">
            <div class="controls-header">
                <div class="controls-title">
                    <span>🔊</span>
                    <span>Equalizer Status</span>
                </div>
                <button class="btn btn-power" id="powerBtn" onclick="togglePower()">
                    <span>⚡</span>
                    <span id="powerText">ON</span>
                </button>
            </div>

            <div class="presets">
                <label>Presets</label>
                <div class="preset-grid">
                    <button class="preset-btn active" onclick="applyPreset('flat')">Flat</button>
                    <button class="preset-btn" onclick="applyPreset('rock')">Rock</button>
                    <button class="preset-btn" onclick="applyPreset('pop')">Pop</button>
                    <button class="preset-btn" onclick="applyPreset('jazz')">Jazz</button>
                    <button class="preset-btn" onclick="applyPreset('classical')">Classical</button>
                    <button class="preset-btn" onclick="applyPreset('bass')">Bass</button>
                    <button class="preset-btn" onclick="applyPreset('treble')">Treble</button>
                    <button class="preset-btn" onclick="applyPreset('vocal')">Vocal</button>
                </div>
            </div>

            <div class="preamp-control">
                <div class="preamp-header">
                    <label>Preamp</label>
                    <span class="preamp-value" id="preampValue">0 dB</span>
                </div>
                <input type="range" class="slider" id="preampSlider" min="-12" max="12" value="0"
                       oninput="updatePreamp(this.value)">
            </div>

            <button class="btn btn-reset" onclick="resetEqualizer()">
                <span>🔄</span>
                <span>Reset to Flat</span>
            </button>
        </div>

        <div class="card equalizer">
            <h2 class="eq-title">10-Band Equalizer</h2>
            <div class="bands" id="bands"></div>
        </div>

        <footer>
            <p>OaKhz DIY Bluetooth Speaker v4.0</p>
        </footer>
    </div>

    <script>
        const frequencies = ['32 Hz', '64 Hz', '125 Hz', '250 Hz', '500 Hz', '1 kHz', '2 kHz', '4 kHz', '8 kHz', '16 kHz'];
        const presets = {
            flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            rock: [5, 4, -2, -3, -1, 2, 4, 5, 5, 5],
            pop: [-1, 3, 4, 4, 2, -1, -2, -2, -1, -1],
            jazz: [4, 3, 1, 2, -1, -1, 0, 1, 2, 3],
            classical: [5, 4, 3, 2, -1, -1, 0, 2, 3, 4],
            bass: [6, 5, 4, 2, 0, -1, -2, -3, -3, -3],
            treble: [-3, -3, -2, -1, 0, 2, 4, 5, 6, 6],
            vocal: [-2, -3, -2, 1, 3, 3, 2, 1, 0, -1]
        };

        let enabled = true;
        let currentPreset = 'flat';
        let bandValues = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        let debounceTimers = {};
        let mediaUpdateInterval;

        // Media Control Functions
        function updateMediaInfo() {
            fetch('/api/media/info')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('mediaTitle').textContent = data.title || 'No media playing';
                    document.getElementById('mediaArtist').textContent = data.artist || 'Unknown Artist';
                    document.getElementById('mediaAlbum').textContent = data.album || '';

                    const statusEl = document.getElementById('mediaStatus');
                    const playPauseIcon = document.getElementById('playPauseIcon');

                    statusEl.className = 'media-status ' + (data.status || 'stopped');
                    statusEl.textContent = data.status || 'stopped';

                    if (data.status === 'playing') {
                        playPauseIcon.textContent = '⏸';
                    } else {
                        playPauseIcon.textContent = '▶️';
                    }
                })
                .catch(error => console.error('Error fetching media info:', error));
        }

        function mediaPlayPause() {
            fetch('/api/media/play-pause', { method: 'POST' })
                .then(response => response.json())
                .then(() => {
                    setTimeout(updateMediaInfo, 200);
                })
                .catch(error => console.error('Error:', error));
        }

        function mediaNext() {
            fetch('/api/media/next', { method: 'POST' })
                .then(response => response.json())
                .then(() => {
                    setTimeout(updateMediaInfo, 200);
                })
                .catch(error => console.error('Error:', error));
        }

        function mediaPrevious() {
            fetch('/api/media/previous', { method: 'POST' })
                .then(response => response.json())
                .then(() => {
                    setTimeout(updateMediaInfo, 200);
                })
                .catch(error => console.error('Error:', error));
        }

        // Equalizer Functions
        function initBands() {
            const container = document.getElementById('bands');
            frequencies.forEach((freq, index) => {
                const band = document.createElement('div');
                band.className = 'band';
                band.innerHTML = `
                    <div class="band-slider-container">
                        <input type="range" class="slider band-slider"
                               id="band${index}"
                               min="-12" max="12" value="0"
                               oninput="updateBand(${index}, this.value)">
                        <div class="band-center-line"></div>
                    </div>
                    <span class="band-value" id="bandValue${index}">0</span>
                    <span class="band-label">${freq}</span>
                `;
                container.appendChild(band);
            });
        }

        function updateBand(index, value) {
            bandValues[index] = parseInt(value);
            document.getElementById(`bandValue${index}`).textContent = value > 0 ? `+${value}` : value;
            currentPreset = 'custom';
            updatePresetButtons();

            if (debounceTimers[`band_${index}`]) {
                clearTimeout(debounceTimers[`band_${index}`]);
            }
            debounceTimers[`band_${index}`] = setTimeout(() => {
                sendToBackend('band', { index, value: parseInt(value) });
            }, 150);
        }

        function updatePreamp(value) {
            document.getElementById('preampValue').textContent = `${value > 0 ? '+' : ''}${value} dB`;

            if (debounceTimers.preamp) {
                clearTimeout(debounceTimers.preamp);
            }
            debounceTimers.preamp = setTimeout(() => {
                sendToBackend('preamp', { value: parseInt(value) });
            }, 150);
        }

        function togglePower() {
            enabled = !enabled;
            const btn = document.getElementById('powerBtn');
            const text = document.getElementById('powerText');

            if (enabled) {
                btn.classList.remove('off');
                text.textContent = 'ON';
            } else {
                btn.classList.add('off');
                text.textContent = 'OFF';
            }

            sendToBackend('enabled', { value: enabled });
        }

        function applyPreset(presetName) {
            currentPreset = presetName;
            const values = presets[presetName];

            values.forEach((value, index) => {
                bandValues[index] = value;
                document.getElementById(`band${index}`).value = value;
                document.getElementById(`bandValue${index}`).textContent = value > 0 ? `+${value}` : value;
            });

            updatePresetButtons();
            sendToBackend('preset', { name: presetName });
        }

        function updatePresetButtons() {
            document.querySelectorAll('.preset-btn').forEach(btn => {
                btn.classList.remove('active');
            });
            document.querySelectorAll('.preset-btn').forEach(btn => {
                if (btn.textContent.toLowerCase() === currentPreset) {
                    btn.classList.add('active');
                }
            });
        }

        function resetEqualizer() {
            applyPreset('flat');
            document.getElementById('preampSlider').value = 0;
            document.getElementById('preampValue').textContent = '0 dB';
        }

        function sendToBackend(type, data) {
            fetch('/api/equalizer', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ type, data })
            })
            .then(response => response.json())
            .then(data => console.log('Success:', data))
            .catch(error => console.error('Error:', error));
        }

        function loadConfig() {
            fetch('/api/equalizer')
                .then(response => response.json())
                .then(config => {
                    enabled = config.enabled;
                    currentPreset = config.preset;

                    if (!enabled) {
                        document.getElementById('powerBtn').classList.add('off');
                        document.getElementById('powerText').textContent = 'OFF';
                    }

                    config.bands.forEach((value, index) => {
                        document.getElementById(`band${index}`).value = value;
                        document.getElementById(`bandValue${index}`).textContent = value > 0 ? `+${value}` : value;
                    });

                    document.getElementById('preampSlider').value = config.preamp;
                    document.getElementById('preampValue').textContent = `${config.preamp > 0 ? '+' : ''}${config.preamp} dB`;

                    updatePresetButtons();
                })
                .catch(error => console.error('Error loading config:', error));
        }

        // Initialize
        initBands();
        loadConfig();
        updateMediaInfo();

        // Update media info every 2 seconds
        mediaUpdateInterval = setInterval(updateMediaInfo, 2000);
    </script>
</body>
</html>
EOFHTML

# Service systemd pour l'equalizer
cat > /etc/systemd/system/oakhz-equalizer.service << EOF
[Unit]
Description=OaKhz Equalizer Web Server
After=network.target pulseaudio.service

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=/opt/oakhz
ExecStart=/usr/bin/python3 /opt/oakhz/eq_server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo -e "${YELLOW}[8/9] Bluetooth agent configuration...${NC}"

# bt-agent service for automatic NoInputNoOutput pairing
cat > /etc/systemd/system/bt-agent.service << 'EOF'
[Unit]
Description=Bluetooth Agent
After=bluetooth.service
Requires=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/bin/bt-agent -c NoInputNoOutput
RestartSec=5
Restart=always
KillSignal=SIGUSR1

[Install]
WantedBy=multi-user.target
EOF

echo -e "${YELLOW}[9/10] Sudo permissions configuration...${NC}"

# Allow user to reload CamillaDSP without password
cat > /etc/sudoers.d/oakhz-camilladsp << EOF
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/pkill -HUP camilladsp
EOF
chmod 440 /etc/sudoers.d/oakhz-camilladsp

# Give permissions to write on CamillaDSP config
chown $SERVICE_USER:$SERVICE_USER /opt/camilladsp/config.yml

# Allow Python to bind to port 80 (privileged port)
echo -e "${GREEN}Allowing Python to bind to port 80...${NC}"
setcap 'cap_net_bind_service=+ep' /usr/bin/python3 || setcap 'cap_net_bind_service=+ep' $(which python3)

echo -e "${YELLOW}[10/10] Services activation...${NC}"

echo -e "${GREEN}OaKhz Audio hostname configuration...${NC}"

# Configure pretty hostname
if [ -f /etc/machine-info ]; then
    # Backup existing file
    sudo cp /etc/machine-info /etc/machine-info.backup
    # Remove old line PRETTY_HOSTNAME if it exists
    sudo sed -i '/^PRETTY_HOSTNAME=/d' /etc/machine-info
fi

# Add or create file with new hostname
echo 'PRETTY_HOSTNAME="OaKhz audio"' | sudo tee -a /etc/machine-info > /dev/null

# Apply change immediately
sudo hostnamectl set-hostname --pretty "OaKhz Audio"

echo -e "${GREEN}✓ Hostname configuré !${NC}"
echo ""
echo "Device display name is now : OaKhz audio"
echo ""
echo "Verification :"
hostnamectl status | grep "Pretty hostname"

# Enable and start services
systemctl daemon-reload
systemctl restart bluetooth
systemctl enable bluetooth
systemctl enable pulseaudio
systemctl start pulseaudio
systemctl enable bt-agent
systemctl start bt-agent
systemctl enable camilladsp
systemctl start camilladsp
systemctl enable oakhz-equalizer
systemctl start oakhz-equalizer

echo ""
echo -e "${GREEN}✓ Installation complete !${NC}"
echo ""
echo "Installed services :"
echo "  - Bluetooth : automatic pairing without PIN"
echo "  - PulseAudio : system audio management with Bluetooth"
echo "  - HiFiBerry MiniAmp : DAC audio output"
echo "  - CamillaDSP : 10-band parametric equalizer"
echo "  - Web Interface : http://$(hostname -I | awk '{print $1}')"
echo ""
echo "Your speaker is visible via Bluetooth as : 'OaKhz audio'"
echo ""
echo -e "${GREEN}✓ Web equalizer is functional !${NC}"
echo "  Modify bands and presets from the web interface."
echo "  Changes are applied in real-time via CamillaDSP."
echo ""
echo "Useful commands :"
echo "  sudo systemctl status camilladsp"
echo "  sudo systemctl status oakhz-equalizer"
echo "  sudo systemctl status bt-agent"
echo "  sudo systemctl restart bluetooth"
echo "  bluetoothctl devices"
echo "  speaker-test -D camilladsp -c 2 -t wav  # Test sound with equalizer"
echo "  aplay -l  # Check sound cards"
echo ""
echo "Audio architecture :"
echo "  Bluetooth → PulseAudio → CamillaDSP (Equalizer) → HiFiBerry MiniAmp"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT : Reboot Raspberry Pi to activate all services${NC}"
echo -e "${YELLOW}    sudo reboot${NC}"