from flask import Flask, jsonify, request, render_template, redirect
from flask_cors import CORS
import subprocess
import os
import json
import logging
import threading
import time
import socket
from ruamel.yaml import YAML
import signal

app = Flask(__name__, template_folder='templates')
CORS(app)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONFIG_FILE = os.path.expanduser('~/.oakhz_eq.json')
CAMILLADSP_CONFIG = '/opt/camilladsp/config.yml'

# --- Volume adaptive profile settings ---
# When volume drops below LOW_THRESHOLD, apply a loudness compensation boost
# to maintain perceived bass and treble at low listening levels (Fletcher-Munson)
VOLUME_ADAPTIVE_LOW_THRESHOLD = -20    # dB preamp below which "night boost" kicks in
VOLUME_ADAPTIVE_HIGH_THRESHOLD = 0     # dB preamp above which boosts are reduced
VOLUME_ADAPTIVE_CHECK_INTERVAL = 2     # seconds between volume checks


class EqualizerController:
    def __init__(self):
        self.bands = 10
        self.band_names = ['eq_31', 'eq_63', 'eq_125', 'eq_250', 'eq_500', 'eq_1k', 'eq_2k', 'eq_4k', 'eq_8k', 'eq_16k']
        self._adaptive_volume_enabled = False
        self._adaptive_thread = None
        self._adaptive_stop = threading.Event()
        self._last_adaptive_state = None  # 'low', 'normal', 'high'
        self.load_config()

    def load_config(self):
        try:
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r') as f:
                    self.config = json.load(f)
                # Ensure adaptive_volume key exists for backward compat
                if 'adaptive_volume' not in self.config:
                    self.config['adaptive_volume'] = False
            else:
                self.config = {
                    'enabled': True,
                    'preamp': self._read_preamp_from_camilladsp(),
                    'bands': self._read_bands_from_camilladsp(),
                    'preset': 'default',
                    'adaptive_volume': False
                }
                self.save_config()
        except Exception as e:
            logger.error(f"Config load error: {e}")
            self.config = {'enabled': True, 'preamp': 0, 'bands': [0] * self.bands, 'preset': 'default', 'adaptive_volume': False}

    def _read_preamp_from_camilladsp(self):
        try:
            ryaml = YAML()
            with open(CAMILLADSP_CONFIG, 'r') as f:
                cdsp_config = ryaml.load(f)
            return cdsp_config['filters']['preamp_gain']['parameters']['gain']
        except Exception:
            return 0

    def _read_bands_from_camilladsp(self):
        try:
            ryaml = YAML()
            with open(CAMILLADSP_CONFIG, 'r') as f:
                cdsp_config = ryaml.load(f)
            return [
                cdsp_config['filters'][name]['parameters']['gain']
                for name in self.band_names
                if name in cdsp_config['filters']
            ]
        except Exception:
            return [0] * self.bands

    def save_config(self):
        try:
            with open(CONFIG_FILE, 'w') as f:
                json.dump(self.config, f, indent=2)
        except Exception as e:
            logger.error(f"Config save error: {e}")

    def update_camilladsp(self):
        """Update CamillaDSP config and reload"""
        try:
            ryaml = YAML()
            ryaml.preserve_quotes = True

            with open(CAMILLADSP_CONFIG, 'r') as f:
                cdsp_config = ryaml.load(f)

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

            for i, band_name in enumerate(self.band_names):
                gain = self.config['bands'][i] if self.config['enabled'] else 0.0
                if band_name in cdsp_config['filters']:
                    cdsp_config['filters'][band_name]['parameters']['gain'] = gain

            if 'pipeline' in cdsp_config:
                for channel_pipeline in cdsp_config['pipeline']:
                    if 'names' in channel_pipeline:
                        if 'preamp_gain' not in channel_pipeline['names']:
                            channel_pipeline['names'].insert(0, 'preamp_gain')

            with open(CAMILLADSP_CONFIG, 'w') as f:
                ryaml.dump(cdsp_config, f)

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
            'flat':      [0,  0,  0,  0,  0,  0,  0,  0,  0,  0],
            'rock':      [5,  4, -2, -3, -1,  2,  4,  5,  5,  5],
            'pop':       [-1, 3,  4,  4,  2, -1, -2, -2, -1, -1],
            'jazz':      [4,  3,  1,  2, -1, -1,  0,  1,  2,  3],
            'classical': [5,  4,  3,  2, -1, -1,  0,  2,  3,  4],
            'bass':      [6,  5,  4,  2,  0, -1, -2, -3, -3, -3],
            'treble':    [-3,-3, -2, -1,  0,  2,  4,  5,  6,  6],
            'vocal':     [-2,-3, -2,  1,  3,  3,  2,  1,  0, -1],

            # Outdoor: compensates open air absorption of bass and treble
            # Strong bass + treble boost to cut through ambient noise outdoors
            'outdoor':   [6,  6,  5,  2, -1,  0,  2,  5,  6,  6],

            # Night: optimized for low volume listening (Fletcher-Munson compensation)
            # Boosted mids for speech intelligibility, reduced sub and extreme treble
            'night':     [2,  3,  4,  3,  3,  4,  3,  2,  1,  0],
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

    # --- Adaptive volume profile ---

    def set_adaptive_volume(self, enabled):
        """Enable or disable adaptive volume profile"""
        self.config['adaptive_volume'] = enabled
        self._adaptive_volume_enabled = enabled
        self.save_config()
        if enabled:
            self._start_adaptive_thread()
        else:
            self._stop_adaptive_thread()
            self._last_adaptive_state = None
        logger.info(f"Adaptive volume {'enabled' if enabled else 'disabled'}")

    def _start_adaptive_thread(self):
        if self._adaptive_thread is None or not self._adaptive_thread.is_alive():
            self._adaptive_stop.clear()
            self._adaptive_thread = threading.Thread(target=self._adaptive_loop, daemon=True)
            self._adaptive_thread.start()

    def _stop_adaptive_thread(self):
        self._adaptive_stop.set()

    def _adaptive_loop(self):
        """Background thread that adjusts loudness compensation based on preamp volume"""
        logger.info("Adaptive volume thread started")
        while not self._adaptive_stop.is_set():
            try:
                if self._adaptive_volume_enabled:
                    preamp = self.config.get('preamp', 0)

                    if preamp <= VOLUME_ADAPTIVE_LOW_THRESHOLD:
                        state = 'low'
                    elif preamp >= VOLUME_ADAPTIVE_HIGH_THRESHOLD:
                        state = 'high'
                    else:
                        state = 'normal'

                    if state != self._last_adaptive_state:
                        self._apply_adaptive_compensation(state)
                        self._last_adaptive_state = state

            except Exception as e:
                logger.error(f"Adaptive volume loop error: {e}")

            self._adaptive_stop.wait(VOLUME_ADAPTIVE_CHECK_INTERVAL)

        logger.info("Adaptive volume thread stopped")

    def _apply_adaptive_compensation(self, state):
        """Apply loudness compensation offsets to CamillaDSP without changing user EQ bands"""
        try:
            ryaml = YAML()
            ryaml.preserve_quotes = True

            with open(CAMILLADSP_CONFIG, 'r') as f:
                cdsp_config = ryaml.load(f)

            # Compensation offsets applied directly to loudness filters in config
            # low volume: boost bass and treble (Fletcher-Munson)
            # high volume: reduce boosts to protect drivers
            if state == 'low':
                bass_offset = 2    # extra boost on loudness_bass_mid at low volume
                treble_offset = 2  # extra boost on loudness_treble at low volume
                logger.info("Adaptive volume: low → applying loudness compensation")
            elif state == 'high':
                bass_offset = -2   # reduce bass at high volume to protect HP
                treble_offset = -1
                logger.info("Adaptive volume: high → reducing boosts")
            else:
                bass_offset = 0
                treble_offset = 0
                logger.info("Adaptive volume: normal → no compensation")

            if 'loudness_bass_mid' in cdsp_config['filters']:
                base_gain = 2  # base value from config
                cdsp_config['filters']['loudness_bass_mid']['parameters']['gain'] = base_gain + bass_offset

            if 'loudness_treble' in cdsp_config['filters']:
                base_gain = 4  # base value from config
                cdsp_config['filters']['loudness_treble']['parameters']['gain'] = base_gain + treble_offset

            with open(CAMILLADSP_CONFIG, 'w') as f:
                ryaml.dump(cdsp_config, f)

            subprocess.run(['sudo', 'pkill', '-HUP', 'camilladsp'], check=False)

        except Exception as e:
            logger.error(f"Adaptive compensation error: {e}")

    def apply_current_config(self):
        self.update_camilladsp()
        # Restart adaptive thread if it was enabled
        if self.config.get('adaptive_volume', False):
            self._adaptive_volume_enabled = True
            self._start_adaptive_thread()

    def get_config(self):
        return self.config


eq = EqualizerController()


# --- System info ---

def get_ip_address():
    """Get the current IP address of the Pi"""
    try:
        # Try to get the main network interface IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        try:
            # Fallback: hostname resolution
            return socket.gethostbyname(socket.gethostname())
        except Exception:
            return "unavailable"


def get_cpu_temperature():
    """Get CPU temperature in Celsius"""
    try:
        with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
            return round(int(f.read().strip()) / 1000, 1)
    except Exception:
        return None

def get_cpu_usage():
    """Get CPU usage percentage"""
    try:
        with open('/proc/stat', 'r') as f:
            line = f.readline()
        parts = list(map(int, line.split()[1:]))
        idle = parts[3]
        total = sum(parts)
        time.sleep(0.1)
        with open('/proc/stat', 'r') as f:
            line = f.readline()
        parts2 = list(map(int, line.split()[1:]))
        idle2 = parts2[3]
        total2 = sum(parts2)
        return round((1 - (idle2 - idle) / (total2 - total)) * 100, 1)
    except Exception:
        return None

def get_ram_usage():
    """Get RAM usage percentage"""
    try:
        with open('/proc/meminfo', 'r') as f:
            lines = f.readlines()
        mem = {}
        for line in lines:
            parts = line.split()
            if parts[0] in ('MemTotal:', 'MemAvailable:'):
                mem[parts[0]] = int(parts[1])
        total = mem.get('MemTotal:', 0)
        available = mem.get('MemAvailable:', 0)
        if total > 0:
            return round((total - available) / total * 100, 1)
        return None
    except Exception:
        return None

def get_uptime():
    """Get system uptime as human readable string"""
    try:
        with open('/proc/uptime', 'r') as f:
            seconds = float(f.read().split()[0])
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        if hours > 0:
            return f"{hours}h {minutes}m"
        return f"{minutes}m"
    except Exception:
        return None

def get_camilladsp_status():
    """Check if CamillaDSP is running"""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', 'camilladsp'],
            capture_output=True, text=True
        )
        return result.stdout.strip()
    except Exception:
        return "unknown"

def get_connected_bluetooth_device():
    """Get name of connected Bluetooth device"""
    try:
        result = subprocess.run(
            ['bluetoothctl', 'devices', 'Connected'],
            capture_output=True, text=True, timeout=2
        )
        for line in result.stdout.splitlines():
            if 'Device' in line:
                parts = line.split(None, 2)
                if len(parts) >= 3:
                    return parts[2].strip()
        return None
    except Exception:
        return None


# --- EQ routes ---

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
    elif action_type == 'adaptive_volume':
        success = True
        eq.set_adaptive_volume(action_data['value'])

    if success:
        return jsonify({'status': 'ok', 'config': eq.get_config()})
    else:
        return jsonify({'status': 'error'}), 500


# --- System routes ---

@app.route('/api/system/info', methods=['GET'])
def get_system_info():
    """Return system info: IP, CPU temp, CPU usage, RAM, uptime, CamillaDSP status, Bluetooth device"""
    return jsonify({
        'ip': get_ip_address(),
        'hostname': socket.gethostname(),
        'cpu_temp': get_cpu_temperature(),
        'cpu_usage': get_cpu_usage(),
        'ram_usage': get_ram_usage(),
        'uptime': get_uptime(),
        'camilladsp': get_camilladsp_status(),
        'bluetooth_device': get_connected_bluetooth_device()
    })


# --- Bluetooth routes ---

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
            for line in result.stdout.splitlines():
                if 'variant' in line or 'string' in line:
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

        info = {}
        status = get_dbus_property(device_path, 'org.bluez.MediaPlayer1', 'Status')
        info['status'] = status.lower() if status else 'stopped'

        result = subprocess.run([
            'dbus-send', '--system', '--print-reply',
            '--dest=org.bluez',
            f'{device_path}/player0',
            'org.freedesktop.DBus.Properties.Get',
            'string:org.bluez.MediaPlayer1',
            'string:Track'
        ], capture_output=True, text=True, timeout=2)

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
    try:
        device_path = get_bluetooth_device_path()
        if not device_path:
            return jsonify({'status': 'error', 'message': 'No device connected'}), 400
        subprocess.run([
            'dbus-send', '--system', '--type=method_call',
            '--dest=org.bluez', device_path,
            'org.bluez.MediaControl1.Play'
        ], capture_output=True, timeout=2)
        logger.info("Media: Play")
        return jsonify({'status': 'ok'})
    except Exception as e:
        logger.error(f"Media play error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/media/pause', methods=['POST'])
def media_pause():
    try:
        device_path = get_bluetooth_device_path()
        if not device_path:
            return jsonify({'status': 'error', 'message': 'No device connected'}), 400
        subprocess.run([
            'dbus-send', '--system', '--type=method_call',
            '--dest=org.bluez', device_path,
            'org.bluez.MediaControl1.Pause'
        ], capture_output=True, timeout=2)
        logger.info("Media: Pause")
        return jsonify({'status': 'ok'})
    except Exception as e:
        logger.error(f"Media pause error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/media/play-pause', methods=['POST'])
def media_play_pause():
    try:
        device_path = get_bluetooth_device_path()
        if not device_path:
            return jsonify({'status': 'error', 'message': 'No device connected'}), 400
        status = get_dbus_property(device_path, 'org.bluez.MediaPlayer1', 'Status')
        if status and status.lower() == 'playing':
            subprocess.run([
                'dbus-send', '--system', '--type=method_call',
                '--dest=org.bluez', device_path,
                'org.bluez.MediaControl1.Pause'
            ], capture_output=True, timeout=2)
            logger.info("Media: Pause")
        else:
            subprocess.run([
                'dbus-send', '--system', '--type=method_call',
                '--dest=org.bluez', device_path,
                'org.bluez.MediaControl1.Play'
            ], capture_output=True, timeout=2)
            logger.info("Media: Play")
        return jsonify({'status': 'ok'})
    except Exception as e:
        logger.error(f"Media play-pause error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/media/next', methods=['POST'])
def media_next():
    try:
        device_path = get_bluetooth_device_path()
        if not device_path:
            return jsonify({'status': 'error', 'message': 'No device connected'}), 400
        subprocess.run([
            'dbus-send', '--system', '--type=method_call',
            '--dest=org.bluez', device_path,
            'org.bluez.MediaControl1.Next'
        ], capture_output=True, timeout=2)
        logger.info("Media: Next track")
        return jsonify({'status': 'ok'})
    except Exception as e:
        logger.error(f"Media next error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/media/previous', methods=['POST'])
def media_previous():
    try:
        device_path = get_bluetooth_device_path()
        if not device_path:
            return jsonify({'status': 'error', 'message': 'No device connected'}), 400
        subprocess.run([
            'dbus-send', '--system', '--type=method_call',
            '--dest=org.bluez', device_path,
            'org.bluez.MediaControl1.Previous'
        ], capture_output=True, timeout=2)
        logger.info("Media: Previous track")
        return jsonify({'status': 'ok'})
    except Exception as e:
        logger.error(f"Media previous error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

DEFAULT_CONFIG = '/opt/camilladsp/config.default.yml'

@app.route('/api/equalizer/reset-default', methods=['POST'])
def reset_to_default():
    try:
        if os.path.exists(CONFIG_FILE):
            os.remove(CONFIG_FILE)
        # Restore from default
        subprocess.run(['sudo', 'cp', DEFAULT_CONFIG, CAMILLADSP_CONFIG], check=True)
        subprocess.run(['sudo', 'pkill', '-HUP', 'camilladsp'], check=False)
        # Reload eq state from restored config
        eq.config = {
            'enabled': True,
            'preamp': eq._read_preamp_from_camilladsp(),
            'bands': eq._read_bands_from_camilladsp(),
            'preset': 'default',
            'adaptive_volume': False
        }
        logger.info("Reset to default config.yml")
        return jsonify({'status': 'ok', 'config': eq.get_config()})
    except Exception as e:
        logger.error(f"Reset default error: {e}")
        return jsonify({'status': 'error'}), 500
    
# --- App routes ---

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
