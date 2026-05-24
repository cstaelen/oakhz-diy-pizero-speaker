# OaKhz Audio - Web Equalizer Interface

Web-based interface for controlling CamillaDSP parametric equalizer and Bluetooth media playback in real-time.

-- Written with Claude AI

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Features](#features)
- [Architecture](#architecture)
- [Configuration](#configuration)
- [Service Management](#service-management)
- [API Reference](#api-reference)

---

## Overview

The web equalizer provides a browser-based interface to control CamillaDSP's 10-band parametric equalizer and Bluetooth media playback. Access it from any device on your network (phone, tablet, computer).

---

## Prerequisites

- OaKhz Audio base system installed (`install.sh` must be run first)
- CamillaDSP installed at `/usr/local/bin/camilladsp`
- CamillaDSP config present at `/opt/camilladsp/config.yml`

---

## Installation

### Step 1: Install base system (if not done)

```bash
sudo bash scripts/install.sh
sudo reboot
```

### Step 2: Install web equalizer

```bash
sudo bash scripts/setup-equalizer.sh
```

The script runs 4 phases:
1. Install Python dependencies (`python3-flask`, `python3-flask-cors`, `python3-yaml`, `python3-websocket`)
2. Copy Flask server and web UI to `/opt/oakhz/`
3. Grant Python permission to bind port 80 (`setcap cap_net_bind_service`)
4. Enable and start the `oakhz-equalizer` systemd service

### Step 3: Access the interface

```
http://[raspberry-pi-ip]
```

Or in Access Point mode:

```
http://192.168.50.1
```

---

## Features

### 10-Band Parametric Equalizer

| Band | Frequency | Internal name | Adjustable Range |
| ---- | --------- | ------------- | ---------------- |
| 1    | 31 Hz     | `eq_31`       | -12 dB to +12 dB |
| 2    | 63 Hz     | `eq_63`       | -12 dB to +12 dB |
| 3    | 125 Hz    | `eq_125`      | -12 dB to +12 dB |
| 4    | 250 Hz    | `eq_250`      | -12 dB to +12 dB |
| 5    | 500 Hz    | `eq_500`      | -12 dB to +12 dB |
| 6    | 1 kHz     | `eq_1k`       | -12 dB to +12 dB |
| 7    | 2 kHz     | `eq_2k`       | -12 dB to +12 dB |
| 8    | 4 kHz     | `eq_4k`       | -12 dB to +12 dB |
| 9    | 8 kHz     | `eq_8k`       | -12 dB to +12 dB |
| 10   | 16 kHz    | `eq_16k`      | -12 dB to +12 dB |

EQ state is persisted in `~/.oakhz_eq.json` and applied to `/opt/camilladsp/config.yml` on every change. CamillaDSP is reloaded via `SIGHUP`.

### Bluetooth Media Control

The interface exposes controls for the currently connected Bluetooth source:
- Play / Pause / Play-Pause toggle
- Next / Previous track
- Current media info (track, artist, album)

Media controls use `bluetoothctl` and D-Bus to communicate with the connected device.

### Captive Portal Support

All unknown URL paths redirect to `http://192.168.50.1/` — this enables automatic captive portal detection when connecting to the OaKhz WiFi Access Point.

---

## Architecture

```
┌─────────────────────────────┐
│   Web Browser (Any Device)  │
│   HTML5 + JavaScript + CSS  │
└──────────────┬──────────────┘
               │ HTTP REST
               │ Port 80
┌──────────────▼──────────────┐
│   Flask Web Server          │
│   /opt/oakhz/eq_server.py   │
└──────────┬──────────────────┘
           │ Write config.yml + SIGHUP
┌──────────▼──────────────────┐
│   CamillaDSP                │
│   /usr/local/bin/camilladsp │
└──────────┬──────────────────┘
           │ ALSA  hw:1,0
┌──────────▼──────────────────┐
│   HiFiBerry MiniAmp (DAC)   │
└─────────────────────────────┘
```

Flask communicates with CamillaDSP by writing `/opt/camilladsp/config.yml` and sending `SIGHUP` (no WebSocket between Flask and CamillaDSP).

### Files and Directories

```
/opt/oakhz/
├── eq_server.py              # Flask web server
└── templates/
    └── index.html            # Web UI

/opt/camilladsp/
└── config.yml                # CamillaDSP config (updated on each EQ change)

~/.oakhz_eq.json              # Persisted EQ state (bands, preamp, preset name)

/etc/systemd/system/
└── oakhz-equalizer.service   # Systemd service
```

---

## Configuration

### Customize Web Interface

```bash
sudo nano /opt/oakhz/templates/index.html
```

---

## Service Management

```bash
# Status
sudo systemctl status oakhz-equalizer

# Restart
sudo systemctl restart oakhz-equalizer

# Logs (follow)
sudo journalctl -u oakhz-equalizer -f

# Logs (last 50 lines)
sudo journalctl -u oakhz-equalizer -n 50
```

---

## API Reference

### GET /api/equalizer

Returns current EQ state.

```json
{
  "enabled": true,
  "preamp": 0,
  "bands": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  "preset": "flat"
}
```

### POST /api/equalizer

Update EQ settings. Accepts partial updates.

```json
{
  "bands": [3, 2, 0, -1, 0, 0, 1, 2, 3, 2],
  "preamp": -3,
  "enabled": true
}
```

### GET /api/bluetooth/devices

Returns currently connected Bluetooth devices.

### GET /api/media/info

Returns current media metadata from the connected Bluetooth source (track, artist, album, status).

### POST /api/media/play

Start playback on connected Bluetooth device.

### POST /api/media/pause

Pause playback.

### POST /api/media/play-pause

Toggle play/pause.

### POST /api/media/next

Skip to next track.

### POST /api/media/previous

Go to previous track.

---

## Related Documentation

- [Base System Installation](./README-v2-install.md)
- [WiFi Access Point](./README-v2-accesspoint.md)
- [Sound Feedback System](./README-v2-sound.md)
- [Rotary Encoder Control](./README-v2-rotary.md)
