# 🎵 OaKhz Audio - DIY Bluetooth Speaker

Complete documentation for building your own intelligent Bluetooth speaker with Raspberry Pi Zero 2W, HiFiBerry MiniAmp, and CamillaDSP equalizer.

-- Written with Claude AI

## 📋 Table of Contents

- [Overview](#overview)
- [Required Hardware](#required-hardware)
- [Quick Installation](#quick-installation)
- [Detailed Installation](#detailed-installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Technical Architecture](#technical-architecture)

---

## 🎯 Overview

OaKhz Audio is a DIY Bluetooth speaker based on Raspberry Pi that offers:

- ✅ **Bluetooth A2DP Streaming** - High-quality audio
- ✅ **10-Band Parametric Equalizer** - Precise sound control with CamillaDSP
- ✅ **Web Interface** - Natural wood-themed design matching the speaker aesthetics
- ✅ **Real-time Debounced Controls** - Smooth equalizer adjustments (150ms debounce)
- ✅ **Audio Feedback System** - Ready, connection sounds via PulseAudio (65% volume)
- ✅ **Auto-pairing** - Automatic connection without PIN
- ✅ **HiFiBerry DAC** - Superior audio quality
- ✅ **Professional Audio Pipeline** - PulseAudio → ALSA Loopback → CamillaDSP → HiFiBerry

---

## 🛠️ Required Hardware

### Essential Components

| Component | Recommended Model | Approx. Price |
|-----------|------------------|---------------|
| **Raspberry Pi** | Zero 2W | ~€20 |
| **SD Card** | 16GB+ Class 10 | ~€10 |
| **Audio DAC** | HiFiBerry MiniAmp | ~€25 |
| **Power Supply** | 5V 3A USB-C | ~€10 |
| **Speakers** | 2x 4Ω 3W | ~€15 |

### Optional Components

- **Push button** for physical controls (GPIO 22)
- **3D printed enclosure** or custom case
- **Status LED** (optional)

### Connection Diagram

```
Raspberry Pi Zero 2W
├── GPIO 22 ────→ Push button (to GND)
├── I2S ────────→ HiFiBerry MiniAmp
│   ├── BCM 18 (PCM_CLK)
│   ├── BCM 19 (PCM_FS)
│   └── BCM 21 (PCM_DIN)
└── Power ─────→ 5V 3A

HiFiBerry MiniAmp
├── Left + / - ─→ Left speaker
└── Right + / -─→ Right speaker
```

---

## 🚀 Quick Installation

### 1. Prepare SD Card

```bash
# Download Raspberry Pi OS Lite (64-bit)
# Flash with Raspberry Pi Imager
# Enable SSH in settings
```

### 2. First Boot

```bash
# Connect via SSH
ssh your_user@raspberrypi.local

# Update system
sudo apt update && sudo apt upgrade -y
```

### 3. Automatic Installation

```bash
# Download installation script
wget https://raw.githubusercontent.com/your-repo/oakhz-audio/main/scripts/install.sh

# Make executable
chmod +x install.sh

# Run installation
sudo ./install.sh

# Reboot
sudo reboot
```

### 4. Ready! 🎉

- **Bluetooth**: Look for "OaKhz audio" on your phone
- **Web Interface**: `http://Pi-IP`

---

## 📚 Detailed Installation

### Step 1: Raspberry Pi OS Lite Installation

1. Download [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Flash **Raspberry Pi OS Lite (64-bit)** to your SD card
3. Before ejecting, configure:
   - Username and password
   - WiFi (SSID and password)
   - Enable SSH

### Step 2: Initial Configuration

```bash
# SSH connection
ssh your_user@raspberrypi.local

# System update
sudo apt update
sudo apt upgrade -y

# Hostname configuration (optional)
sudo nano /etc/machine-info
# Add: PRETTY_HOSTNAME="OaKhz audio"
```

### Step 3: Dependencies Installation

The script automatically installs:

```bash
# Core packages
- bluez, bluez-tools (Bluetooth stack)
- pulseaudio, pulseaudio-module-bluetooth (Audio system)
- alsa-utils (ALSA utilities)
- python3-pip, python3-flask, python3-flask-cors (Web server)
- python3-yaml (CamillaDSP configuration)
```

### Step 4: HiFiBerry MiniAmp Configuration

The script configures `/boot/firmware/config.txt`:

```ini
# Disable onboard audio
#dtparam=audio=on

# Enable HiFiBerry DAC
dtoverlay=hifiberry-dac
```

Verify after reboot:
```bash
aplay -l
# You should see: snd_rpi_hifiberry_dac (card 1)
```

### Step 5: Bluetooth Configuration

Configuration in `/etc/bluetooth/main.conf`:

```ini
[General]
Name = OaKhz audio
Class = 0x400428
DiscoverableTimeout = 0
PairableTimeout = 0
JustWorksRepairing = always
FastConnectable = true

[Policy]
AutoEnable = true
```

### Step 6: PulseAudio Configuration

**System service** (`/etc/systemd/system/pulseaudio.service`):
```ini
[Unit]
Description=PulseAudio system server
After=bluetooth.service

[Service]
Type=notify
ExecStart=/usr/bin/pulseaudio --system --disallow-exit --log-target=journal
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

**Audio routing** (`/etc/pulse/system.pa`):
```
### Bluetooth Support
load-module module-bluetooth-policy
load-module module-bluetooth-discover autodetect_mtu=yes

### CamillaDSP Sink
load-module module-alsa-sink device=hw:Loopback,0 sink_name=camilladsp_out rate=48000
set-default-sink camilladsp_out

### Auto-switch Bluetooth connections
load-module module-switch-on-connect
```

### Step 7: CamillaDSP Installation

The script:
1. Downloads CamillaDSP v2.0.3 (ARM64 binary)
2. Configures ALSA loopback (`snd-aloop` module)
3. Creates 10-band parametric equalizer config
4. Sets up systemd service

**Configuration** (`/opt/camilladsp/config.yml`):
```yaml
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
    device: "hw:1,0"  # HiFiBerry is card 1
    format: S16LE

filters:
  eq_31:
    type: Biquad
    parameters:
      type: Peaking
      freq: 31
      q: 1.0
      gain: 0.0
  # ... 10 bands total (31Hz, 63Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz)
```

### Step 8: Web Equalizer Installation

**Flask server** (`/opt/oakhz/eq_server.py`):
- Reads/writes CamillaDSP YAML configuration
- Sends SIGHUP to CamillaDSP for live reload
- Manages presets (flat, rock, pop, jazz, classical, bass, treble, vocal)
- REST API on port 80

**Web interface** features:
- 10 vertical sliders (-12dB to +12dB)
- Preamp control
- 8 built-in presets
- 150ms debounce on slider changes
- Real-time visual feedback
- Responsive design
- **Natural wood color scheme** - Warm browns, beige tones matching the speaker enclosure

---

## ⚙️ Configuration

### Access Web Interface

```
http://[Raspberry-Pi-IP]
```

Find IP address:
```bash
hostname -I
```

### Equalizer Presets

| Preset | Description |
|--------|-------------|
| **Flat** | Neutral, no coloration |
| **Rock** | Scooped mids, boosted highs/lows |
| **Pop** | Enhanced mid-highs |
| **Jazz** | Warm bass, present highs |
| **Classical** | Natural balance |
| **Bass** | Powerful low-end |
| **Treble** | Bright highs |
| **Vocal** | Mids for voices |

### Frequency Bands

- **32 Hz, 64 Hz** - Deep bass
- **125 Hz, 250 Hz** - Bass/Low mids
- **500 Hz, 1 kHz** - Midrange
- **2 kHz, 4 kHz** - Upper mids/Presence
- **8 kHz, 16 kHz** - Treble

---

## 📱 Usage

### Bluetooth Connection

1. **On your phone/computer**:
   - Open Bluetooth settings
   - Look for "OaKhz audio"
   - Connect (no PIN required)

2. **The speaker**:
   - Automatically accepts connection
   - Routes audio through PulseAudio → CamillaDSP → HiFiBerry

### Equalizer Adjustment

**Via Web Interface**:
1. Open `http://Pi-IP`
2. Select a preset or adjust manually
3. Changes apply in real-time (with 150ms debounce)
4. Settings auto-save to `~/.oakhz_eq.json`

### Phone Controls

Standard Bluetooth controls work:
- ▶️ Play / Pause
- ⏭️ Next track
- ⏮️ Previous track
- 🔊 Volume

---

## 🔧 Troubleshooting

### Bluetooth Won't Connect

```bash
# Check Bluetooth service
sudo systemctl status bluetooth

# Check if discoverable
bluetoothctl
> power on
> discoverable on
> pairable on

# Restart services
sudo systemctl restart bluetooth
sudo systemctl restart bt-agent
```

### No Sound

```bash
# Check sound cards
aplay -l
# HiFiBerry should be card 1

# Check PulseAudio sinks
sudo -u pulse pactl list sinks short
# camilladsp_out should exist

# Check CamillaDSP is running
sudo systemctl status camilladsp

# Test loopback
speaker-test -D hw:Loopback,0 -c 2 -t sine -f 440 -l 1

# Check volume
amixer -c 1 sget PCM
```

### Equalizer Not Working

```bash
# Check equalizer service
sudo systemctl status oakhz-equalizer

# View logs
journalctl -u oakhz-equalizer -f

# Check if enabled
curl http://localhost/api/equalizer
# "enabled" should be true

# Enable equalizer
curl -X POST http://localhost/api/equalizer \
  -H 'Content-Type: application/json' \
  -d '{"type": "enabled", "data": {"value": true}}'
```

### Web Interface Not Responding

```bash
# Check service
sudo systemctl status oakhz-equalizer

# Restart
sudo systemctl restart oakhz-equalizer

# Check firewall
sudo ufw status
```

### Bluetooth Audio Not Routing to Speakers

```bash
# Check if Bluetooth source exists
sudo -u pulse pactl list sources short | grep bluez

# Check card profile
sudo -u pulse pactl list cards | grep -A20 bluez

# Set profile to a2dp_source
sudo -u pulse pactl set-card-profile bluez_card.XX_XX_XX_XX_XX_XX a2dp_source

# Check loopback modules
sudo -u pulse pactl list modules short | grep loopback
```

---

## 🏗️ Technical Architecture

### Audio Pipeline

```
Android/Mac Bluetooth
       ↓
PulseAudio (module-bluetooth-discover)
       ↓
module-switch-on-connect (auto-routing)
       ↓
ALSA Loopback (hw:Loopback,0 → hw:Loopback,1)
       ↓
CamillaDSP (10-band parametric EQ)
       ↓
HiFiBerry MiniAmp (hw:1,0 - card 1)
       ↓
Speakers 🔊
```

### Services Architecture

```
┌─────────────────────────────────────────┐
│          User Interface Layer           │
│  ┌────────────────┐  ┌────────────────┐ │
│  │  Web Browser   │  │  Bluetooth     │ │
│  │  (Port 80)     │  │  Device        │ │
│  └───────┬────────┘  └────────┬───────┘ │
└──────────┼──────────────────────┼────────┘
           │                      │
┌──────────▼──────────────────────▼────────┐
│         Application Layer                │
│  ┌────────────────┐  ┌────────────────┐  │
│  │  Flask Server  │  │  bt-agent      │  │
│  │  (Python)      │  │  (NoInputNo    │  │
│  │                │  │   Output)      │  │
│  └───────┬────────┘  └────────┬───────┘  │
└──────────┼──────────────────────┼─────────┘
           │                      │
┌──────────▼──────────────────────▼─────────┐
│         Audio Processing Layer            │
│  ┌────────────────┐  ┌────────────────┐   │
│  │  CamillaDSP    │←─│  PulseAudio    │   │
│  │  (Equalizer)   │  │  (System)      │   │
│  └───────┬────────┘  └────────┬───────┘   │
└──────────┼──────────────────────┼──────────┘
           │                      │
┌──────────▼──────────────────────▼──────────┐
│         Hardware Layer                     │
│  ┌────────────────┐  ┌────────────────┐    │
│  │  ALSA Loopback │  │  Bluetooth     │    │
│  │  (snd-aloop)   │  │  HCI           │    │
│  └───────┬────────┘  └────────────────┘    │
└──────────┼──────────────────────────────────┘
           │
┌──────────▼──────────┐
│  HiFiBerry MiniAmp  │
│  (I2S DAC)          │
└──────────┬──────────┘
           │
     ┌─────▼─────┐
     │  Speakers │
     └───────────┘
```

### Key Services

| Service | Purpose | Port/Device |
|---------|---------|-------------|
| **bluetooth.service** | Bluetooth daemon | - |
| **bt-agent.service** | Auto-pairing (NoInputNoOutput) | - |
| **pulseaudio.service** | System audio + Bluetooth routing | - |
| **camilladsp.service** | Parametric equalizer | WebSocket 1234 |
| **oakhz-equalizer.service** | Web interface | HTTP 80 |

### Configuration Files

| File | Purpose |
|------|---------|
| `/etc/bluetooth/main.conf` | Bluetooth device name & class |
| `/etc/pulse/system.pa` | PulseAudio routing & modules |
| `/etc/asound.conf` | ALSA default device config |
| `/opt/camilladsp/config.yml` | Equalizer bands & audio pipeline |
| `/opt/oakhz/eq_server.py` | Flask REST API server |
| `~/.oakhz_eq.json` | User equalizer settings |

---

## 📊 Useful Commands

### Service Status

```bash
sudo systemctl status bluetooth
sudo systemctl status pulseaudio
sudo systemctl status camilladsp
sudo systemctl status oakhz-equalizer
sudo systemctl status bt-agent
```

### Real-time Logs

```bash
# All OaKhz services
journalctl -f | grep oakhz

# Specific service
journalctl -u camilladsp -f
```

### Bluetooth Devices

```bash
# List connected devices
bluetoothctl devices Connected

# Device info
bluetoothctl info [MAC]
```

### Audio

```bash
# List sound cards
aplay -l

# PulseAudio sinks
sudo -u pulse pactl list sinks short

# PulseAudio sources (Bluetooth)
sudo -u pulse pactl list sources short

# ALSA mixer
alsamixer -c 1

# Test audio
speaker-test -D hw:Loopback,0 -c 2 -t sine -f 440 -l 1
```

### CamillaDSP

```bash
# Check config syntax
/usr/local/bin/camilladsp -c /opt/camilladsp/config.yml

# View real-time signal levels (verbose mode)
sudo systemctl stop camilladsp
sudo /usr/local/bin/camilladsp -v /opt/camilladsp/config.yml
# Watch for "signal rms:" in output
```

---

## 🎨 Customization

### Change Bluetooth Name

```bash
sudo nano /etc/bluetooth/main.conf
# Modify: Name = Your Name
sudo systemctl restart bluetooth
```

### Change Web Interface Port

```bash
sudo nano /opt/oakhz/eq_server.py
# Modify: app.run(host='0.0.0.0', port=80)
sudo systemctl restart oakhz-equalizer
```

### Add Custom Presets

Edit both `/opt/oakhz/eq_server.py` and `/opt/oakhz/templates/index.html`:

```python
# In eq_server.py
presets = {
    'custom': [3, 2, 1, 0, -1, -1, 0, 1, 2, 3],
    # ...
}
```

```javascript
// In index.html
const presets = {
    custom: [3, 2, 1, 0, -1, -1, 0, 1, 2, 3],
    // ...
};
```

### Optimize Bluetooth Latency

Already optimized in `/etc/pulse/system.pa`:
- `autodetect_mtu=yes` for Bluetooth
- `rate=48000` for CamillaDSP sink
- `module-switch-on-connect` for instant routing

---

## 🔒 Security

### Recommendations

1. **Change default password**
```bash
passwd
```

2. **Regular updates**
```bash
sudo apt update && sudo apt upgrade -y
```

3. **Configure firewall** (optional)
```bash
sudo apt install ufw
sudo ufw allow 22/tcp  # SSH
sudo ufw allow 80/tcp  # Web Interface
sudo ufw enable
```

4. **Disable unused services**
```bash
sudo systemctl disable [service-name]
```

---

## 🚀 Performance

### Recommended Optimizations

**Reduce power consumption**:
```bash
# Disable WiFi if not used
sudo rfkill block wifi

# Disable HDMI
sudo /usr/bin/tvservice -o

# Reduce LED brightness
echo 0 | sudo tee /sys/class/leds/led0/brightness
```

**Improve audio**:
```bash
# Increase PulseAudio priority
sudo nano /etc/systemd/system/pulseaudio.service
# Add under [Service]:
Nice=-11
```

---

## 📦 Backup and Restore

### Backup Configuration

```bash
# Create backup
sudo tar -czf oakhz-backup.tar.gz \
    /opt/oakhz \
    /etc/bluetooth/main.conf \
    /etc/pulse/system.pa \
    /etc/systemd/system/oakhz-* \
    /etc/systemd/system/camilladsp.service \
    /etc/systemd/system/bt-agent.service \
    /etc/systemd/system/pulseaudio.service \
    /opt/camilladsp \
    /etc/asound.conf

# Download backup
scp your_user@raspberrypi:/home/your_user/oakhz-backup.tar.gz .
```

### Restore

```bash
# Upload backup
scp oakhz-backup.tar.gz your_user@raspberrypi:

# Extract
sudo tar -xzf oakhz-backup.tar.gz -C /

# Reload systemd
sudo systemctl daemon-reload
```

---

*Version 3.0 - October 2025*
