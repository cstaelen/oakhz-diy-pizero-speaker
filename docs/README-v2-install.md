# OaKhz Audio - Base System Installation

Complete installation guide for the OaKhz Audio DIY Bluetooth speaker on Raspberry Pi Zero 2W + HiFiBerry MiniAmp.

-- Written with Claude AI

---

## Table of Contents

- [Overview](#overview)
- [Required Hardware](#required-hardware)
- [Preparation](#preparation)
- [Installation](#installation)
- [Optional Components](#optional-components)
- [Usage](#usage)
- [Technical Architecture](#technical-architecture)
- [Useful Commands](#useful-commands)

---

## Overview

OaKhz Audio is a DIY Bluetooth speaker based on Raspberry Pi that provides:

- **Bluetooth A2DP Streaming** — automatic pairing without PIN
- **DSP audio pipeline** — CamillaDSP with loudness, protection, stereo widening, and 10-band parametric EQ
- **Web Interface** — equalizer control from any browser
- **Audio Feedback** — startup/connect/shutdown sounds
- **Physical Controls** — rotary encoder for volume and media
- **WiFi Access Point** — captive portal for easy access

---

## Required Hardware

| Component | Recommended | Approx. Price |
| --------- | ----------- | ------------- |
| **Raspberry Pi** | Zero 2W | ~€20 |
| **SD Card** | 16GB+ Class 10 | ~€10 |
| **Audio DAC** | HiFiBerry MiniAmp | ~€25 |
| **Power Supply** | 5V 3A USB-C | ~€10 |
| **Speakers** | 2x 4Ω 3W | ~€15 |
| **Rotary encoder** | KY-040 (optional) | ~€2 |

### Wiring

```
Raspberry Pi Zero 2W
├── I2S → HiFiBerry MiniAmp
│   ├── BCM 18 (PCM_CLK)
│   ├── BCM 19 (PCM_FS)
│   └── BCM 21 (PCM_DIN)
├── GPIO 23 → Rotary CLK (optional)
├── GPIO 24 → Rotary DT  (optional)
└── GPIO 22 → Rotary SW  (optional)

HiFiBerry MiniAmp
├── Left +/- → Left speaker
└── Right +/- → Right speaker
```

---

## Preparation

### 1. Flash SD card

- Download [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
- Flash **Raspberry Pi OS Lite (64-bit)**
- In Imager settings, configure: username/password, WiFi, SSH

### 2. Clone this repository onto the Pi

```bash
ssh your_user@raspberrypi.local
git clone https://github.com/your-repo/OAKHZ_DOC.git
cd OAKHZ_DOC
```

---

## Installation

### Base system

```bash
sudo bash scripts/install.sh
```

The script runs as root and auto-detects the current user (`$SUDO_USER`). It performs these steps:

1. **Enable Bluetooth** — `rfkill unblock bluetooth`, `hciconfig hci0 up`
2. **System update** — `apt update && apt upgrade`
3. **Install dependencies** — `bluez`, `bluez-tools`, `pulseaudio`, `pulseaudio-module-bluetooth`, `alsa-utils`, `python3-pip`, `ladspa-sdk`, `swh-plugins`, `wget`
4. **Install CamillaDSP v2.0.3** — ARM64 binary from GitHub, installed to `/usr/local/bin/camilladsp`
5. **Configure HiFiBerry MiniAmp** — adds `dtoverlay=hifiberry-dac` to `/boot/firmware/config.txt`, disables onboard audio
6. **Configure Bluetooth** — installs `/etc/bluetooth/main.conf` (name, class, auto-pairing)
7. **Configure PulseAudio + CamillaDSP** — system service, ALSA loopback module (`snd-aloop`), `system.pa` routing, CamillaDSP config, sudoers rule
8. **Configure Bluetooth agent** — `bt-agent.service` for automatic NoInputNoOutput pairing
9. **Enable and start services** — bluetooth, pulseaudio, bt-agent, camilladsp

After installation:

```bash
sudo reboot
```

### Verify

```bash
# Check sound cards (HiFiBerry should appear as card 1)
aplay -l

# Check services
sudo systemctl status bluetooth pulseaudio camilladsp bt-agent

# Test audio through equalizer pipeline
speaker-test -D camilladsp_out -c 2 -t wav
```

---

## Optional Components

Install after the base system and reboot:

| Component | Script | Documentation |
| --------- | ------ | ------------- |
| Web Equalizer | `sudo bash scripts/setup-equalizer.sh` | [README-v2-equalizer.md](./README-v2-equalizer.md) |
| Sound Feedback | `sudo bash scripts/setup-sound.sh` | [README-v2-sound.md](./README-v2-sound.md) |
| Rotary Encoder | `sudo bash scripts/setup-rotary.sh` | [README-v2-rotary.md](./README-v2-rotary.md) |
| WiFi Access Point | `sudo bash scripts/setup-accesspoint.sh` | [README-v2-accesspoint.md](./README-v2-accesspoint.md) |

---

## Usage

### Bluetooth connection

1. On your phone/computer, open Bluetooth settings
2. Look for **"OaKhz Audio"**
3. Connect — no PIN required

### Web equalizer

```
http://[Pi-IP]
```

Or in Access Point mode: `http://192.168.50.1`

---

## Technical Architecture

### Audio pipeline

```
Bluetooth device
      ↓
PulseAudio (module-bluetooth-discover, module-switch-on-connect)
      ↓
camilladsp_out sink (ALSA Loopback hw:Loopback,0)
      ↓
CamillaDSP (hw:Loopback,1 → hw:1,0)
      ↓
HiFiBerry MiniAmp
      ↓
Speakers
```

### CamillaDSP DSP chain

CamillaDSP applies the following filter chain on each channel (in order):

| Stage | Filter | Description |
| ----- | ------ | ----------- |
| 1 | `peak_limiter` | -2dB gain, prevents clipping |
| 2 | `hp_protection` | Highpass 45Hz (Q=0.7), protects drivers |
| 3 | `preamp_gain` | +5dB global gain |
| 4 | `loudness_bass_low` | +6dB peaking at 58Hz (Q=0.9) |
| 5 | `loudness_bass_mid` | +4dB peaking at 100Hz (Q=1.2) |
| 6 | `room_correction` | +2dB peaking at 200Hz (Q=0.8) |
| 7 | `mid_cut_low` | -3dB peaking at 300Hz (Q=1.0) |
| 8 | `mid_cut_high` | -2dB peaking at 600Hz (Q=1.0) |
| 9 | `presence` | +2dB peaking at 3kHz (Q=1.5) |
| 10 | `loudness_treble` | +4dB highshelf at 8kHz |
| 11–20 | `eq_31` … `eq_16k` | 10-band parametric EQ (user-adjustable via web) |

After both channels: **stereo widening mixer** (cross-channel phase inversion at -9dB).

### Services

| Service | Purpose | Auto-start |
| ------- | ------- | ---------- |
| **bluetooth** | Bluetooth daemon | Yes |
| **bt-agent** | Auto-pairing (NoInputNoOutput) | Yes |
| **pulseaudio** | System audio + Bluetooth routing | Yes |
| **camilladsp** | DSP processor, WebSocket port 1234 | Yes |
| **oakhz-equalizer** | Web interface (port 80) | Yes (setup-equalizer.sh) |
| **oakhz-audio-events** | Startup/connect sounds + BT monitor | Yes (setup-sound.sh) |
| **oakhz-shutdown-sound** | Shutdown sound (before halt) | Yes (setup-sound.sh) |
| **oakhz-rotary** | Rotary encoder controller | Yes (setup-rotary.sh) |
| **hostapd / dnsmasq / wlan0-ap** | WiFi Access Point | Yes (setup-accesspoint.sh) |
| **oakhz-recovery-mode** | Boot-time WiFi mode selector | Yes (setup-accesspoint.sh) |

### Configuration files

| File | Purpose |
| ---- | ------- |
| `/etc/bluetooth/main.conf` | Bluetooth name (`OaKhz Audio`), class, auto-pairing |
| `/etc/pulse/system.pa` | PulseAudio routing + Bluetooth + CamillaDSP sink |
| `/etc/asound.conf` | ALSA default device → CamillaDSP loopback |
| `/opt/camilladsp/config.yml` | DSP pipeline (EQ, loudness, protection, stereo widening) |
| `/etc/sudoers.d/oakhz-camilladsp` | Allows user to send SIGHUP to camilladsp without password |
| `~/.oakhz_eq.json` | Persisted EQ state (bands, preamp) |

---

## Useful Commands

### Services

```bash
sudo systemctl status bluetooth pulseaudio camilladsp bt-agent
sudo systemctl restart bluetooth
sudo systemctl restart camilladsp
```

### Bluetooth

```bash
bluetoothctl devices Connected
bluetoothctl info [MAC]
```

### Audio

```bash
aplay -l                                        # List sound cards
pactl list sinks short                          # PulseAudio sinks
pactl list sources short                        # PulseAudio sources (BT)
alsamixer -c 1                                  # HiFiBerry mixer
speaker-test -D camilladsp_out -c 2 -t wav      # Test through DSP
```

### CamillaDSP

```bash
sudo systemctl status camilladsp
journalctl -u camilladsp -f
# Manual test (stop service first):
sudo systemctl stop camilladsp
sudo /usr/local/bin/camilladsp -v -p 1234 /opt/camilladsp/config.yml
```