# OaKhz Audio - Sound Feedback System

Audio feedback system for OaKhz Audio. Provides audible notifications for system events via PulseAudio.

-- Written with Claude AI

---

## Table of Contents

- [Overview](#overview)
- [Sound Events](#sound-events)
- [Installation](#installation)
- [Configuration](#configuration)

---

## Overview

The sound feedback system plays WAV notifications for system events:

| Event | Sound | Trigger |
| ----- | ----- | ------- |
| **Ready** | Ascending C major arpeggio (C-E-G-C) | Startup, once PulseAudio is ready |
| **Connect** | High "ding" chime | Bluetooth device connects or reconnects |
| **Disconnect** | (tracked, no sound played) | Bluetooth device disconnects |
| **Shutdown** | Descending minor arpeggio (G-E-C-G) | Before system shutdown |

All sounds are 48kHz stereo WAV files in `/opt/oakhz/sounds/`. Ready/connect sounds play via `paplay` at **80% volume** through PulseAudio → CamillaDSP. The shutdown sound plays via `aplay` directly to the HiFiBerry DAC (PulseAudio is not used for shutdown).

---

## Sound Events

### Ready

- **Trigger**: Startup, after PulseAudio becomes available
- **Sound**: `ready.wav` — ascending C major arpeggio (~0.6s)
- **Volume**: 80% via `paplay`

### Connect

- **Trigger**: A Bluetooth device connects or reconnects
- **Sound**: `connect.wav` — high chime (~0.2s)
- **Volume**: 80% via `paplay`
- **Single device mode**: if multiple devices connect simultaneously, all but the first are automatically disconnected via `bluetoothctl`

### Disconnect

- Disconnect events are detected and logged, but **no sound is played**

### Shutdown

- **Trigger**: System shutdown / reboot / halt
- **Sound**: `shutdown.wav` — descending minor arpeggio (~0.7s)
- **Playback**: CamillaDSP is stopped first to release the DAC, then `aplay -D plughw:1,0` plays directly to the HiFiBerry
- **Service**: `oakhz-shutdown-sound.service` runs as root before `shutdown.target`

---

## Installation

```bash
sudo bash scripts/setup-sound.sh
```

The script:
1. Installs `sox` and `pulseaudio-utils`
2. Copies `oakhz-audio-events.py` and `oakhz-shutdown-sound.sh` to `/usr/local/bin/`
3. Installs both systemd services
4. Generates demo WAV files via `sox` (or creates empty placeholders if `sox` is unavailable)
5. Enables and starts `oakhz-audio-events.service`

### Generated WAV files

| File | Generated sound |
| ---- | --------------- |
| `ready.wav` | C4 E4 G4 C5 pluck arpeggio, norm -9dB |
| `connect.wav` | 1760Hz + 2093Hz sine chime, norm -12dB |
| `disconnect.wav` | 587Hz + 523Hz descending sine, norm -12dB |
| `shutdown.wav` | G4 E4 C4 G3 pluck arpeggio, norm -9dB |

Replace any file with your own 48kHz stereo WAV to customize the sound.

---

## Configuration

### Service management

```bash
sudo systemctl status oakhz-audio-events
sudo systemctl status oakhz-shutdown-sound
sudo systemctl restart oakhz-audio-events
journalctl -u oakhz-audio-events -f
journalctl -u oakhz-audio-events -n 50
```

### Test sounds manually

```bash
paplay --volume=52428 /opt/oakhz/sounds/ready.wav      # 80%
paplay --volume=52428 /opt/oakhz/sounds/connect.wav
aplay -D plughw:1,0 /opt/oakhz/sounds/shutdown.wav    # direct ALSA
```

### Change notification volume

Edit `/usr/local/bin/oakhz-audio-events.py`:

```python
volume_percent = 80  # Change to desired value (0–100)
```

Then restart:

```bash
sudo systemctl restart oakhz-audio-events
```

### Replace sound files

Copy any 48kHz stereo WAV to `/opt/oakhz/sounds/`:

```bash
sudo cp my-sound.wav /opt/oakhz/sounds/ready.wav
sudo chmod 644 /opt/oakhz/sounds/ready.wav
```

---

## Architecture

```
Boot
  ↓
oakhz-audio-events.service
  Wait for PulseAudio (pactl info)
  ↓
Play ready.wav (paplay 80%)
  ↓
Monitor Bluetooth (loop every 1s)
  ↓ device connects/reconnects
Play connect.wav (paplay 80%)

Shutdown
  ↓
oakhz-shutdown-sound.service (root, before shutdown.target)
  Stop camilladsp.service
  aplay -D plughw:1,0 shutdown.wav
```

### Audio pipeline (ready/connect)

```
WAV file (48kHz stereo)
  → paplay (PulseAudio, 80%)
  → camilladsp_out sink
  → ALSA Loopback
  → CamillaDSP (equalizer)
  → HiFiBerry MiniAmp (hw:1,0)
  → Speakers
```

### Files

| Path | Purpose |
| ---- | ------- |
| `/opt/oakhz/sounds/ready.wav` | Startup ready notification |
| `/opt/oakhz/sounds/connect.wav` | Bluetooth connect notification |
| `/opt/oakhz/sounds/disconnect.wav` | Defined but not played |
| `/opt/oakhz/sounds/shutdown.wav` | Shutdown notification |
| `/usr/local/bin/oakhz-audio-events.py` | Python daemon (ready + Bluetooth monitor) |
| `/usr/local/bin/oakhz-shutdown-sound.sh` | Shutdown sound script (bash + aplay) |
| `/etc/systemd/system/oakhz-audio-events.service` | Main service (daemon, user: oakhz) |
| `/etc/systemd/system/oakhz-shutdown-sound.service` | Shutdown service (oneshot, user: root) |


---

## Related Documentation

- [Base System Installation](./README-v2-install.md)
- [Web Equalizer Interface](./README-v2-equalizer.md)
- [Rotary Encoder Control](./README-v2-rotary.md)
- [WiFi Access Point](./README-v2-accesspoint.md)
