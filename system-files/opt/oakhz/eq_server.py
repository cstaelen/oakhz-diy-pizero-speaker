from flask import Flask, jsonify, request, render_template, redirect
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

@app.route("/<path:path>")
def captive_portal_redirect(path):
    """Redirect all unknown paths to home page for captive portal detection"""
    logger.info(f"Captive portal redirect: {path}")
    return redirect("http://192.168.50.1/", code=302)

if __name__ == '__main__':
    eq.apply_current_config()
    app.run(host='0.0.0.0', port=80, debug=False)
