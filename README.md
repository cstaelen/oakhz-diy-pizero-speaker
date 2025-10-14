# 🎵 OaKhz Audio v3 - Complete DIY Bluetooth Speaker System

High-quality DIY Bluetooth speaker built with Raspberry Pi Zero 2W, HiFiBerry MiniAmp, and CamillaDSP equalizer with web interface, sound feedback, and physical rotary controls.

This educational project aims to build a prototype of a Bluetooth speaker that is detachable, reusable, and repairable, using open-source softwares, standards, and norms as much as possible.

-- Written with Claude AI

---

[<img title="a title" alt="Final render" src="./.github/img/photo.jpg" style="width:49%" />](./.github/img/photo.jpg)
[<img title="a title" alt="Final render" src="./.github/img/photo2.jpg" style="width:49%" />](./.github/img/photo2.jpg)
[<img title="a title" alt="Inside" src="./.github/img/inside.jpg" style="width:32%" />](./.github/img/inside.jpg)
[<img title="a title" alt="Inside" src="./.github/img/inside2.jpg" style="width:32%" />](./.github/img/inside2.jpg)
[<img title="a title" alt="Inside" src="./.github/img/side.jpg" style="width:32%" />](./.github/img/side.jpg)

## 📦 What's Included

This complete system includes three main components:

### 1. 🔊 [Base System - Bluetooth Speaker & Equalizer](./README-v2-install.md)

The core audio system with Bluetooth streaming and web-based parametric equalizer.

**Features:**
- ✅ Bluetooth A2DP streaming (auto-pairing, no PIN)
- ✅ 10-band parametric equalizer (CamillaDSP)
- ✅ Web interface with 8 presets (natural wood theme)
- ✅ Professional audio pipeline: PulseAudio → Loopback → CamillaDSP → HiFiBerry
- ✅ Real-time debounced controls (150ms)

**[📖 Read Full Installation Guide →](./README-v2-install.md)**

---

### 2. 🔔 [Sound Feedback System](./README-v2-sound.md)

Audible notifications for system events through PulseAudio.

**Features:**
- 🎵 Ready sound (Bluetooth discoverable - C major arpeggio)
- 🎵 Connection sound (device connects/reconnects - high chime)
- 🎵 Shutdown sound (system powering off - descending arpeggio)
- 🔊 All sounds at 65% volume via `paplay`
- 🎯 Automatic PulseAudio routing through equalizer
- 🔄 Single device mode (auto-disconnect old connections)

**[📖 Read Full Documentation →](./README-v2-sound.md)**

---

### 3. 🎛️ [Rotary Encoder Control](./README-v2-rotary.md)

Physical rotary encoder for tactile volume and media control.

**Features:**
- 🔄 Rotate: Volume up/down (±3% per step)
- 🔘 Short press: Mute/Unmute
- 🔘 Medium press: Skip track
- ⏱️ Long press (3s): System shutdown
- 🎯 PulseAudio volume control (`pactl` → `camilladsp_out` sink)
- 🔒 Thread-safe with 150ms throttling
- 👤 Runs as user `oakhz` (gpio + audio groups)

**GPIO Pins:** CLK=23, DT=24, SW=22

**[📖 Read Full Documentation →](./README-v2-rotary.md)**

---

### 4. 🚀 [Fast Boot Optimization](./README-v2-fast-boot.md) *(Optional)*

Optimize Raspberry Pi boot time for rapid Bluetooth availability.

**Features:**
- ⚡ Boot time: ~30s → ~12s (60% faster)
- 🎯 Bluetooth ready in 12-18 seconds
- 🔧 Disabled non-essential services
- ⏱️ Reduced systemd timeouts
- 🎯 Parallelized Bluetooth startup
- 📊 Detailed benchmarking tools

**Impact:** Connect to Bluetooth twice as fast after boot!

**[📖 Read Full Documentation →](./README-v2-fast-boot.md)**

---

### 5. 📡 [WiFi Access Point Fallback](./README-v2-accesspoint.md) *(Optional)*

Automatic WiFi client/Access Point switching for equalizer access anywhere.

**Features:**
- 🌐 Auto-connect to home WiFi when available
- 📡 Auto-switch to AP mode when no WiFi
- 🔄 Smart monitoring and switching (every 30s)
- 🔒 WPA2 secured Access Point
- 🎯 Equalizer accessible in both modes
- 💻 SSH always available

**Access:** Home WiFi → `http://[IP]` | AP mode → `http://192.168.50.1`

**[📖 Read Full Documentation →](./README-v2-accesspoint.md)**

---

## 🚀 Quick Installation

### Prerequisites

- Raspberry Pi Zero 2W or Raspberry Pi 4
- Raspberry Pi OS Lite 64-bit
- HiFiBerry MiniAmp (or compatible DAC)
- 2x 4Ω 3W speakers
- KY-040 rotary encoder (optional)

### Installation Steps

```bash
# 1. Base System (Required)
sudo bash scripts/install.sh
sudo reboot

# 2. Sound Feedback (Optional)
sudo bash scripts/setup-sound.sh

# 3. Rotary Encoder (Optional)
sudo bash scripts/setup-rotary.sh

# 4. Fast Boot (Optional - Recommended)
sudo bash scripts/setup-fast-boot.sh
sudo reboot

# 5. WiFi Access Point Fallback (Optional)
sudo bash scripts/setup-accesspoint.sh
sudo reboot
```

### After Installation

1. **Connect Bluetooth**: Look for "OaKhz audio" on your phone
2. **Access Web Interface**: `http://[Pi-IP]`
3. **Use Rotary Control**: Turn for volume, press for mute/skip

---

## 🛠️ Hardware Requirements

### Essential Components

| Component | Model | Price |
|-----------|-------|-------|
| **Raspberry Pi** | Zero 2W | ~€20 |
| **SD Card** | 16GB+ Class 10 | ~€10 |
| **Audio DAC** | HiFiBerry MiniAmp | ~€25 |
| **Power Supply** | 5V 3A USB-C | ~€10 |
| **Speakers** | 2x 4Ω 3W | ~€15 |
| **Total** | | **~€80** |

### Optional Components

| Component | Model | Price |
|-----------|-------|-------|
| **Rotary Encoder** | KY-040 | ~€2 |
| **Enclosure** | 3D printed or custom | Variable |

---

## 📊 System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    User Interfaces                      │
├─────────────────────────────────────────────────────────┤
│  Web Browser     │  Bluetooth Device  │  Rotary Encoder │
│  (Equalizer)     │  (Audio Source)    │  (Volume/Skip)  │
│  Port 80         │                    │  GPIO 23/24/22  │
└────────┬─────────┴─────────┬──────────┴────────┬────────┘
         │                   │                   │
┌────────▼───────────────────▼───────────────────▼────────┐
│                 Audio Processing Layer                   │
├──────────────────────────────────────────────────────────┤
│  Flask Server  │  PulseAudio    │  pactl (Volume)       │
│  (Python)      │  (System Mode) │  (Rotary Control)     │
└────────┬───────┴───────┬────────┴───────────────────────┘
         │               │
┌────────▼───────────────▼────────────────────────────────┐
│              Sound Feedback & Routing                    │
├──────────────────────────────────────────────────────────┤
│  Audio Events  │  Bluetooth     │  Auto-routing         │
│  (paplay 65%)  │  Monitor       │  (switch-on-connect)  │
│  - Ready       │  - Connection  │                        │
│  - Shutdown    │  - Single dev  │                        │
└────────┬───────┴───────┬────────┴────────────────────────┘
         │               │
┌────────▼───────────────▼─────────────────────────────────┐
│                 ALSA Loopback Layer                      │
│  hw:Loopback,0 ──────────→ hw:Loopback,1                │
└────────────────────────┬─────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────┐
│                  CamillaDSP (Equalizer)                  │
│  10-Band Parametric EQ @ 48kHz                           │
│  WebSocket: 1234                                         │
└────────────────────────┬─────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────┐
│              HiFiBerry MiniAmp (I2S DAC)                 │
│              hw:1,0 (Card 1)                             │
└────────────────────────┬─────────────────────────────────┘
                         │
                    ┌────▼─────┐
                    │ Speakers │
                    │  🔊 🔊   │
                    └──────────┘
```

---

## 🎯 Key Features

### Audio Quality
- **48kHz/16-bit** audio pipeline
- **Professional DSP** with CamillaDSP
- **Zero latency** Bluetooth routing
- **HiFiBerry DAC** for superior sound quality

### User Experience
- **Auto-pairing** Bluetooth (no PIN)
- **Web interface** for equalizer (natural wood theme)
- **Physical controls** with rotary encoder
- **Audio feedback** for system events
- **Real-time** equalizer adjustments

### Technical Excellence
- **Thread-safe** volume control with locking
- **Debounced** controls (150ms throttling)
- **Single device mode** (auto-disconnect old devices)
- **PulseAudio system mode** for stability
- **Systemd services** for automatic startup

---

## 📱 Usage

### Bluetooth Playback
1. On your phone, look for "OaKhz audio" in Bluetooth settings
2. Connect (no PIN required)
3. Play music - audio routes automatically through equalizer

### Web Equalizer
1. Open `http://[Raspberry-Pi-IP]`
2. Choose a preset or adjust 10 bands manually
3. Changes apply in real-time

### Rotary Controls
- **Turn left/right**: Volume ±3%
- **Press briefly**: Mute/Unmute
- **Press medium**: Skip to next track
- **Hold 3 seconds**: Shutdown system

---

## 🔧 Services Overview

| Service | Purpose | Status Command |
|---------|---------|----------------|
| **bluetooth.service** | Bluetooth stack | `sudo systemctl status bluetooth` |
| **bt-agent.service** | Auto-pairing | `sudo systemctl status bt-agent` |
| **pulseaudio.service** | System audio | `sudo systemctl status pulseaudio` |
| **camilladsp.service** | Equalizer | `sudo systemctl status camilladsp` |
| **oakhz-equalizer.service** | Web interface | `sudo systemctl status oakhz-equalizer` |
| **oakhz-audio-events.service** | Sound feedback | `sudo systemctl status oakhz-audio-events` |
| **oakhz-rotary.service** | Rotary control | `sudo systemctl status oakhz-rotary` |

---

## 🔍 Troubleshooting Quick Links

### Common Issues

**No Bluetooth connection?**
→ See [Base System Troubleshooting](./README-v2-install.md#troubleshooting)

**No sound output?**
→ See [Base System - No Sound](./README-v2-install.md#no-sound)

**Sound feedback not playing?**
→ See [Sound Feedback Troubleshooting](./README-v2-sound.md#troubleshooting)

**Rotary encoder not responding?**
→ See [Rotary Encoder Troubleshooting](./README-v2-rotary.md#troubleshooting)

**Volume control not working?**
→ See [Rotary - Volume Not Changing](./README-v2-rotary.md#volume-not-changing)

**Web interface not accessible?**
→ See [Base System - Web Interface Not Responding](./README-v2-install.md#web-interface-not-responding)

---

## 📚 Documentation Structure

```
OAKHZ_DOC/
├── README.md                         # Project overview
├── docs/                             # Documentation
│   ├── README-v2-install.md          # Base system installation guide
│   ├── README-v2-sound.md            # Sound feedback system
│   ├── README-v2-rotary.md           # Rotary encoder control
│   ├── README-v2-fast-boot.md        # Fast boot optimization
│   └── README-v2-accesspoint.md      # WiFi Access Point fallback
├── scripts/                          # Installation scripts
│   ├── install.sh                    # Base system installer
│   ├── setup-sound.sh                # Sound feedback installer
│   ├── setup-rotary.sh               # Rotary encoder installer
│   ├── setup-fast-boot.sh            # Fast boot installer
│   ├── setup-accesspoint.sh          # WiFi AP fallback installer
│   └── setup-events.sh               # System events installer
└── sounds/                           # Audio files
```

---

## 🎨 Customization

Each component can be customized independently:

- **Base System**: Change Bluetooth name, web interface port, add custom EQ presets
- **Sound Feedback**: Replace WAV files, adjust volumes, change polling intervals
- **Rotary Encoder**: Modify GPIO pins, adjust volume steps, change button timings

See individual documentation for detailed customization guides.

---

## 📦 Component Dependencies

```
Base System (Required)
    ↓
    ├── Sound Feedback (Optional) ← Depends on PulseAudio from base
    ├── Rotary Encoder (Optional) ← Depends on PulseAudio from base
    ├── Fast Boot (Optional) ← Optimizes boot time
    └── WiFi AP Fallback (Optional) ← Independent, works with all components
```

**Installation order:**
1. Always install Base System first
2. Add optional components in any order
3. WiFi AP Fallback is completely independent

---

## 🔒 Security & Performance

- **User separation**: Services run as appropriate users (`oakhz`, `pulse`, `root`)
- **Minimal permissions**: Only required groups (gpio, audio)
- **Low resource usage**: ~50MB RAM total for all services
- **No network exposure**: Only local web interface (port 80)
- **Automatic updates**: Use `sudo apt update && sudo apt upgrade`

---

## 📝 Version Information

**Current Version**: v3.6 (October 2025)

**Recent Changes:**
- Fixed rotary encoder volume control (PulseAudio integration)
- Improved thread-safety with volume locking
- Updated GPIO pins (23/24/22)
- Enhanced sound feedback with paplay
- Optimized debouncing (150ms)

**See individual changelogs:**
- [Base System Changelog](./README-v2-install.md) (section not available)
- [Sound Feedback Changelog](./README-v2-sound.md#changelog)
- [Rotary Encoder Changelog](./README-v2-rotary.md#changelog)

---

## 🤝 Contributing

Improvements welcome!

- Report bugs via GitHub Issues
- Share custom sound packs
- Contribute equalizer presets
- Design 3D-printed enclosures
- Improve documentation

---

## 📜 License

GPL-3.0 License - Free to use, modify, and redistribute

---

## 🙏 Credits

**Software:**
- Raspberry Pi OS
- BlueZ (Bluetooth)
- PulseAudio (Audio routing)
- CamillaDSP (Equalizer)
- Flask (Web interface)
- gpiozero (GPIO control)

**Hardware:**
- HiFiBerry (Audio DAC)
- Raspberry Pi Foundation

---

## 📞 Support

- **Documentation**: This repository
- **Issues**: GitHub Issues (if repository available)
- **Community**: Share your builds!

---

**Build your own intelligent speaker! 🎵**

*OaKhz Audio v3 - Complete System*
*October 2025*
