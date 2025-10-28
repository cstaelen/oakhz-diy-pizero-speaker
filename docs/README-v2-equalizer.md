# 🎛️ OaKhz Audio - Web Equalizer Interface

Web-based interface for controlling CamillaDSP parametric equalizer in real-time.

-- Written with Claude AI

---

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Installation](#quick-installation)
- [Features](#features)
- [Usage](#usage)
- [Architecture](#architecture)
- [Customization](#customization)
- [Troubleshooting](#troubleshooting)
- [API Reference](#api-reference)

---

## 🎯 Overview

The web equalizer provides a user-friendly interface to control CamillaDSP's 10-band parametric equalizer. Access it from any device on your network (phone, tablet, computer) to adjust audio frequencies in real-time.

### What it does

- **Visual EQ Control**: Interactive sliders for 10 frequency bands
- **Real-time Updates**: Changes applied instantly via WebSocket
- **Frequency Response Graph**: Visual representation of EQ curve
- **Preset Management**: Save and load custom EQ configurations
- **Cross-platform**: Works on any device with a web browser

---

## ✅ Prerequisites

**Required:**
- OaKhz Audio base system installed (`install.sh` must be run first)
- CamillaDSP configured and running
- Network connectivity (for web access)

**Hardware:**
- Raspberry Pi Zero 2W (or better)
- HiFiBerry MiniAmp (or compatible DAC)
- Active network connection (WiFi or Ethernet)

---

## 🚀 Quick Installation

### Step 1: Install Base System

If not already done:

```bash
cd ~/oakhz-audio
sudo bash scripts/install.sh
sudo reboot
```

### Step 2: Install Web Equalizer

```bash
cd ~/oakhz-audio
sudo bash scripts/setup-equalizer.sh
```

### Step 3: Access Web Interface

Open your browser and navigate to:
```
http://[raspberry-pi-ip]
```

Or if using Access Point mode:
```
http://192.168.50.1
```

---

## 🎨 Features

### 10-Band Parametric Equalizer

| Band | Frequency | Type      | Adjustable Range |
|------|-----------|-----------|------------------|
| 1    | 32 Hz     | Peaking   | -12 dB to +12 dB |
| 2    | 64 Hz     | Peaking   | -12 dB to +12 dB |
| 3    | 125 Hz    | Peaking   | -12 dB to +12 dB |
| 4    | 250 Hz    | Peaking   | -12 dB to +12 dB |
| 5    | 500 Hz    | Peaking   | -12 dB to +12 dB |
| 6    | 1 kHz     | Peaking   | -12 dB to +12 dB |
| 7    | 2 kHz     | Peaking   | -12 dB to +12 dB |
| 8    | 4 kHz     | Peaking   | -12 dB to +12 dB |
| 9    | 8 kHz     | Peaking   | -12 dB to +12 dB |
| 10   | 16 kHz    | Peaking   | -12 dB to +12 dB |

### Real-time Processing

- **Latency**: < 50ms from slider adjustment to audio output
- **WebSocket Updates**: Bidirectional communication for instant feedback
- **Sample Rate**: Fixed at 48kHz (CamillaDSP)

### Preset System

- Save custom EQ configurations
- Load presets instantly
- Export/import presets (YAML format)
- Built-in presets: Flat, Bass Boost, Treble Boost, Voice Enhance

---

## 💻 Usage

### Basic Operation

1. **Open Web Interface**
   - Navigate to `http://[pi-ip]` in your browser
   - Interface loads automatically

2. **Adjust Frequencies**
   - Drag sliders up/down to boost/cut frequencies
   - Changes apply instantly to audio
   - Visual graph updates in real-time

3. **Save Preset**
   - Adjust EQ to your liking
   - Click "Save Preset"
   - Enter a name
   - Preset stored in `/opt/camilladsp/presets/`

4. **Load Preset**
   - Click "Load Preset"
   - Select from saved presets
   - EQ adjusts automatically

### Mobile Access

The interface is fully responsive and works on:
- iOS (Safari, Chrome)
- Android (Chrome, Firefox)
- Tablets
- Desktop browsers

**Tip**: Add to home screen on mobile for app-like experience!

---

## 🏗️ Architecture

### Component Stack

```
┌─────────────────────────────┐
│   Web Browser (Any Device)  │
│   HTML5 + JavaScript + CSS   │
└──────────────┬──────────────┘
               │ HTTP/WebSocket
               │ Port 80
┌──────────────▼──────────────┐
│   Flask Web Server (Python)  │
│   /opt/oakhz/eq_server.py    │
└──────────────┬──────────────┘
               │ WebSocket API
               │ Port 1234
┌──────────────▼──────────────┐
│   CamillaDSP Process         │
│   /usr/local/bin/camilladsp  │
└──────────────┬──────────────┘
               │ ALSA
               │ hw:1,0
┌──────────────▼──────────────┐
│   HiFiBerry MiniAmp (DAC)    │
└──────────────────────────────┘
```

### Files and Directories

```
/opt/oakhz/
├── eq_server.py                 # Flask web server
├── templates/
│   └── index.html               # Web UI
└── static/                      # (optional) CSS/JS assets

/opt/camilladsp/
├── config.yml                   # CamillaDSP configuration
└── presets/                     # Saved EQ presets

/etc/systemd/system/
└── oakhz-equalizer.service      # Systemd service
```

---

## 🎨 Customization

### Change Web Server Port

Edit `/etc/systemd/system/oakhz-equalizer.service`:

```bash
sudo nano /etc/systemd/system/oakhz-equalizer.service
```

Modify `eq_server.py` to change port:
```python
app.run(host='0.0.0.0', port=8080)  # Change 80 to 8080
```

Then restart:
```bash
sudo systemctl daemon-reload
sudo systemctl restart oakhz-equalizer
```

### Customize Web Interface

Edit the HTML template:
```bash
sudo nano /opt/oakhz/templates/index.html
```

Changes:
- Colors and theme
- Layout and responsiveness
- Add custom presets
- Modify frequency bands

### Add Custom Presets

Create preset file in `/opt/camilladsp/presets/`:

```yaml
# /opt/camilladsp/presets/my-preset.yml
filters:
  eq_32:
    type: Peaking
    freq: 32
    gain: 3.0
    q: 1.0
  # ... more bands
```

---

## 🔍 Troubleshooting

### Web Interface Not Loading

**Symptom**: Browser shows "Connection refused" or timeout

**Solution**:
```bash
# Check service status
sudo systemctl status oakhz-equalizer

# View logs
sudo journalctl -u oakhz-equalizer -n 50

# Restart service
sudo systemctl restart oakhz-equalizer

# Check if port 80 is available
sudo netstat -tulpn | grep :80
```

### Changes Not Applied to Audio

**Symptom**: Sliders move but audio doesn't change

**Solution**:
```bash
# Check CamillaDSP status
sudo systemctl status camilladsp

# Check CamillaDSP WebSocket
curl http://localhost:1234

# Restart CamillaDSP
sudo systemctl restart camilladsp

# Check logs
sudo journalctl -u camilladsp -n 50
```

### Permission Denied on Port 80

**Symptom**: Flask fails to start with "Permission denied" error

**Solution**:
```bash
# Re-apply Python capabilities
sudo setcap 'cap_net_bind_service=+ep' /usr/bin/python3

# Verify
getcap /usr/bin/python3
# Should show: cap_net_bind_service=ep
```

### Python Dependencies Missing

**Symptom**: Import errors when starting Flask

**Solution**:
```bash
# Reinstall Python dependencies
sudo apt install -y python3-flask python3-flask-cors python3-yaml python3-websocket

# Verify installation
python3 -c "import flask; import yaml; print('OK')"
```

### Preset Not Loading

**Symptom**: Error when clicking "Load Preset"

**Solution**:
```bash
# Check preset file syntax
cat /opt/camilladsp/presets/[preset-name].yml

# Validate YAML
python3 -c "import yaml; yaml.safe_load(open('/opt/camilladsp/presets/[preset-name].yml'))"

# Check file permissions
ls -la /opt/camilladsp/presets/

# Fix permissions if needed
sudo chown -R oakhz:oakhz /opt/camilladsp/presets/
```

---

## 📡 API Reference

### HTTP Endpoints

#### GET /
Returns the web interface HTML

#### GET /config
Returns current CamillaDSP configuration

```bash
curl http://localhost/config
```

Response:
```json
{
  "filters": {
    "eq_32": {"type": "Peaking", "freq": 32, "gain": 0.0, "q": 1.0},
    ...
  }
}
```

#### POST /config
Updates CamillaDSP configuration

```bash
curl -X POST http://localhost/config \
  -H "Content-Type: application/json" \
  -d '{"filters": {...}}'
```

#### GET /presets
Lists available presets

```bash
curl http://localhost/presets
```

Response:
```json
["flat", "bass-boost", "treble-boost", "custom-1"]
```

#### POST /preset/load
Loads a preset

```bash
curl -X POST http://localhost/preset/load \
  -H "Content-Type: application/json" \
  -d '{"name": "bass-boost"}'
```

### WebSocket API

Connect to `ws://[pi-ip]/ws` for real-time updates:

```javascript
const ws = new WebSocket('ws://192.168.50.1/ws');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('EQ Updated:', data);
};

// Send update
ws.send(JSON.stringify({
  type: 'update_eq',
  band: 'eq_32',
  gain: 3.0
}));
```

---

## 📊 Performance

### Resource Usage

- **Memory**: ~30-50 MB (Flask + Python)
- **CPU**: < 5% idle, ~10-15% during updates
- **Network**: Minimal (WebSocket only sends changes)
- **Disk**: ~5 MB (code + templates)

### Tested On

- Raspberry Pi Zero 2W (512MB RAM)
- Raspberry Pi 3B+ (1GB RAM)
- Raspberry Pi 4B (2GB+ RAM)

All models perform well with no noticeable latency.

---

## 🛠️ Advanced Configuration

### Enable HTTPS

1. Generate SSL certificate:
```bash
cd /opt/oakhz
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout key.pem -out cert.pem -days 365
```

2. Update Flask server to use SSL
3. Access via `https://[pi-ip]`

### Add Authentication

Edit `eq_server.py` to add basic auth:
```python
from flask_httpauth import HTTPBasicAuth

auth = HTTPBasicAuth()

@auth.verify_password
def verify_password(username, password):
    return username == 'oakhz' and password == 'your-password'

@app.route('/')
@auth.login_required
def index():
    return render_template('index.html')
```

### Integrate with Home Assistant

Add REST sensor to Home Assistant:
```yaml
sensor:
  - platform: rest
    resource: http://[pi-ip]/config
    name: OaKhz EQ Status
    json_attributes:
      - filters
    value_template: '{{ value_json.filters | length }}'
```

---

## 📝 Service Management

### Commands

```bash
# Start service
sudo systemctl start oakhz-equalizer

# Stop service
sudo systemctl stop oakhz-equalizer

# Restart service
sudo systemctl restart oakhz-equalizer

# View status
sudo systemctl status oakhz-equalizer

# View logs (follow mode)
sudo journalctl -u oakhz-equalizer -f

# View logs (last 100 lines)
sudo journalctl -u oakhz-equalizer -n 100

# Enable auto-start
sudo systemctl enable oakhz-equalizer

# Disable auto-start
sudo systemctl disable oakhz-equalizer
```

---

## Related Documentation

- [Base System Installation](./README-v2-install.md)
- [Sound Feedback System](./README-v2-sound.md)
- [Rotary Encoder Control](./README-v2-rotary.md)
- [WiFi Access Point](./README-v2-accesspoint.md)

---

*OaKhz Audio v2 - Web Equalizer Interface*
*October 2025*
