# 🔊 OaKhz Audio - Sound Feedback System

Audio feedback system for OaKhz Audio Bluetooth speaker. Provides audible notifications for system events via PulseAudio.

-- Written with Claude AI

---

## 📋 Table of Contents

- [Overview](#overview)
- [Sound Events](#sound-events)
- [Installation](#installation)
- [Configuration](#configuration)
- [Customization](#customization)
- [Troubleshooting](#troubleshooting)
- [Technical Details](#technical-details)

---

## 🎯 Overview

The OaKhz Audio sound feedback system provides pleasant audible notifications for important system events:

- **Startup Ready** - Speaker is ready and Bluetooth is discoverable
- **Device Connection** - A Bluetooth device has connected (reconnection detection included)
- **System Shutdown** - System is about to shutdown/reboot

**Note**: Disconnection sound is disabled by default (not played when devices disconnect).

All sounds use **PulseAudio (paplay)** at 65% volume (except shutdown sound at 75%) and are routed through the CamillaDSP equalizer pipeline.

---

## 🎵 Sound Events

### 1. Ready Sound (Bluetooth Discoverable)

**Trigger**: System startup, when PulseAudio is ready
**Sound**: Ascending C major arpeggio (C-E-G-C)
**Duration**: ~0.6 seconds
**Volume**: 65% (PulseAudio volume: 42598)
**Purpose**: Confirms the speaker is ready to pair and accept connections

```
Event Flow:
  Boot → Wait for PulseAudio (pactl info) → Play ready.wav via paplay
```

### 2. Connection Sound

**Trigger**: When a Bluetooth device connects or reconnects
**Sound**: Pleasant high "ding" chime
**Duration**: ~0.2 seconds
**Volume**: 65%
**Purpose**: Confirms successful Bluetooth pairing/reconnection

**Features**:
- Detects reconnections (device connects again after disconnect)
- Single device mode (auto-disconnects old devices if multiple connect)
- No delay before playing (immediate feedback)

```
Event Flow:
  Device connects → Monitor detects (bluetoothctl info) → Play connect.wav
```

### 3. Disconnection Sound

**Status**: ⚠️ Disabled by default (not played)
**Reason**: Device disconnections tracked but no sound notification

### 4. Shutdown Sound

**Trigger**: Before system shutdown or reboot
**Sound**: WAV audio file
**Duration**: Variable
**Volume**: 75% (PulseAudio volume: 49152)
**Purpose**: "Goodbye" notification before powering off

```
Event Flow:
  Shutdown command → Play shutdown.wav via paplay → Wait 2s → Shutdown
```

---

## 🚀 Installation

### Automatic Installation

Run the setup script as root:

```bash
sudo bash scripts/setup-sound.sh
```

The script will:
1. Install required packages (`sox`, `pulseaudio-utils`)
2. Create unified audio events manager service
3. Generate demo WAV files (48kHz stereo) with pleasant tones
4. Enable and start services

### Manual Installation

If you prefer manual installation:

```bash
# Install dependencies
sudo apt install -y sox pulseaudio-utils

# Create sounds directory
sudo mkdir -p /opt/oakhz/sounds

# Copy sound files (48kHz WAV format)
sudo cp ready.wav /opt/oakhz/sounds/
sudo cp connect.wav /opt/oakhz/sounds/
sudo cp disconnect.wav /opt/oakhz/sounds/
sudo cp shutdown.wav /opt/oakhz/sounds/

# Set permissions
sudo chown -R root:root /opt/oakhz/sounds
sudo chmod 644 /opt/oakhz/sounds/*.wav

# Install services (see setup-sound.sh for service definitions)
sudo cp oakhz-audio-events.service /etc/systemd/system/
sudo cp oakhz-shutdown-sound.service /etc/systemd/system/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable --now oakhz-audio-events.service
sudo systemctl enable oakhz-shutdown-sound.service
```

---

## ⚙️ Configuration

### Service Management

```bash
# Check service status
sudo systemctl status oakhz-audio-events
sudo systemctl status oakhz-shutdown-sound

# View logs (with debug output)
journalctl -u oakhz-audio-events -f

# Restart services
sudo systemctl restart oakhz-audio-events

# Disable sound feedback
sudo systemctl stop oakhz-audio-events
sudo systemctl disable oakhz-audio-events
```

### Testing Sounds

Test sounds manually:

```bash
# Test with paplay (65% volume for ready/connect, 75% for shutdown)
paplay --volume=42598 /opt/oakhz/sounds/ready.wav
paplay --volume=42598 /opt/oakhz/sounds/connect.wav
paplay --volume=49152 /opt/oakhz/sounds/shutdown.wav  # 75%

# Test at different volumes
paplay --volume=32768 /opt/oakhz/sounds/ready.wav  # 50%
paplay --volume=52428 /opt/oakhz/sounds/ready.wav  # 80%
```

### Volume Control

Sound volume is controlled by:
1. **PulseAudio volume** via `paplay --volume` parameter (65% = 42598)
2. **CamillaDSP equalizer** settings
3. **WAV file normalization** (-9dB to -12dB)

To adjust notification volume:

```bash
# Edit the script
sudo nano /usr/local/bin/oakhz-audio-events.py

# Change volume_percent value:
volume_percent = 65  # Change to 50, 75, 100, etc.

# Restart service
sudo systemctl restart oakhz-audio-events
```

---

## 🎨 Customization

### Replace with Custom Sounds

You can replace the demo sounds with your own WAV files:

```bash
# Copy your custom WAVs
sudo cp my-ready-sound.wav /opt/oakhz/sounds/ready.wav
sudo cp my-connect-sound.wav /opt/oakhz/sounds/connect.wav
sudo cp my-shutdown-sound.wav /opt/oakhz/sounds/shutdown.wav

# Set permissions
sudo chmod 644 /opt/oakhz/sounds/*.wav

# Restart service to apply
sudo systemctl restart oakhz-audio-events
```

**Recommendations for custom sounds:**
- **Format**: WAV, 48kHz, stereo (S16LE)
- **Duration**: 0.2-1 second (short and sweet)
- **Volume**: Normalized to -9dB to -12dB
- **File size**: < 500KB per file

### Create Custom Sounds with Sox

Generate your own sounds using `sox`:

```bash
# Simple beep (440Hz sine wave)
sox -n -r 48000 -c 2 /opt/oakhz/sounds/connect.wav synth 0.2 sine 440 norm -12

# Two-tone chime (ascending)
sox -n -r 48000 -c 2 /opt/oakhz/sounds/ready.wav \
    synth 0.1 sine 880 : synth 0.15 sine 1320 \
    fade t 0.01 0.25 0.05 norm -9

# Voice notification (requires text-to-speech)
espeak "Bluetooth ready" -w /tmp/ready.wav
sox /tmp/ready.wav -r 48000 -c 2 /opt/oakhz/sounds/ready.wav norm -9
```

### Change Monitor Polling Interval

The Bluetooth monitor checks for connections every 1 second. To change:

```bash
# Edit the unified audio events script
sudo nano /usr/local/bin/oakhz-audio-events.py

# Find this line in monitor_bluetooth():
time.sleep(1)
# Change to your preferred interval:
time.sleep(2)  # Check every 2 seconds

# Restart service
sudo systemctl restart oakhz-audio-events
```

### Enable Disconnection Sound

By default, disconnection sounds are NOT played. To enable:

```bash
# Edit the script
sudo nano /usr/local/bin/oakhz-audio-events.py

# In monitor_bluetooth(), find this section:
else:
    if last_connected_device is not None:
        logger.info(f'Device disconnected: {last_connected_device}')
        last_connected_device = None

# Add play_sound() call:
else:
    if last_connected_device is not None:
        logger.info(f'Device disconnected: {last_connected_device}')
        play_sound(SOUND_DISCONNECT)  # <-- Add this line
        last_connected_device = None

# Restart service
sudo systemctl restart oakhz-audio-events
```

---

## 🔧 Troubleshooting

### No Sound on Events

**Check if services are running:**
```bash
sudo systemctl status oakhz-bt-monitor
sudo systemctl status oakhz-ready-sound
```

**Check if sound files exist:**
```bash
ls -lh /opt/oakhz/sounds/
```

**Test manual playback:**
```bash
mpg123 -q -a hw:Loopback,0 /opt/oakhz/sounds/ready.mp3
```

**Check audio pipeline:**
```bash
# Verify CamillaDSP is running
sudo systemctl status camilladsp

# Check ALSA devices
aplay -l

# Verify loopback module
lsmod | grep snd_aloop
```

### Ready Sound Not Playing on Boot

**Check service dependencies:**
```bash
sudo systemctl status oakhz-ready-sound
journalctl -u oakhz-ready-sound
```

**Increase startup delay:**
```bash
sudo nano /usr/local/bin/oakhz-ready-sound.sh
# Increase sleep value from 12 to 15 or 20
```

### Connection Sound Not Playing

**Check monitor logs:**
```bash
journalctl -u oakhz-bt-monitor -f
```

**Verify Bluetooth connections are detected:**
```bash
bluetoothctl devices Connected
```

**Restart monitor:**
```bash
sudo systemctl restart oakhz-bt-monitor
```

### Shutdown Sound Not Playing

The shutdown sound may not play if:
- System shuts down too quickly
- Audio pipeline is stopped before sound finishes
- CamillaDSP stops before shutdown service runs

**Check service order:**
```bash
sudo systemctl status oakhz-shutdown-sound
```

The service should run **before** shutdown.target and **after** camilladsp.service.

### Sound Quality Issues

**Check sample rate:**
```bash
# CamillaDSP uses 48kHz
# Ensure your MP3s are also 48kHz
soxi /opt/oakhz/sounds/ready.mp3
```

**Convert to 48kHz if needed:**
```bash
sox input.mp3 -r 48000 -c 2 output.wav
lame -q 0 -b 192 output.wav output_48k.mp3
```

---

## 🏗️ Technical Details

### Audio Pipeline

```
Sound File (WAV 48kHz)
      ↓
paplay (PulseAudio @ 65%/75% volume)
      ↓
PulseAudio (camilladsp_out sink)
      ↓
ALSA Loopback (hw:Loopback,0 → hw:Loopback,1)
      ↓
CamillaDSP (equalizer)
      ↓
HiFiBerry MiniAmp (hw:1,0)
      ↓
Speakers 🔊
```

### System Architecture

```
┌────────────────────────────────────────────┐
│            Sound Events                    │
├────────────────────────────────────────────┤
│  Boot          │  Connect/Reconnect        │  Shutdown
   ↓                      ↓                        ↓
┌──────────────────────────────────────┐  ┌─────────────┐
│  OaKhz Audio Events Manager          │  │  Shutdown   │
│  (Unified Python daemon)             │  │  Sound      │
│  - Ready sound on startup            │  │  Script     │
│  - Bluetooth connection monitoring   │  └──────┬──────┘
│  - Single device mode enforcement    │         │
└────────────┬─────────────────────────┘         │
             │                                    │
             └────────────────┬───────────────────┘
                              ↓
                     ┌──────────────────┐
                     │  paplay (65%/75%)│
                     │  PulseAudio      │
                     └────────┬─────────┘
                              ↓
                     ┌──────────────────┐
                     │  ALSA Loopback   │
                     └────────┬─────────┘
                              ↓
                     ┌──────────────────┐
                     │   CamillaDSP     │
                     │   (Equalizer)    │
                     └────────┬─────────┘
                              ↓
                     ┌──────────────────┐
                     │  HiFiBerry DAC   │
                     └────────┬─────────┘
                              ↓
                          Speakers 🔊
```

### Services

| Service | Type | Trigger | Purpose |
|---------|------|---------|---------|
| **oakhz-audio-events.service** | daemon | After PulseAudio ready | Unified manager: ready sound + Bluetooth monitoring |
| **oakhz-shutdown-sound.service** | oneshot | Before shutdown | Plays goodbye sound |

**Key Features**:
- Waits for PulseAudio with `pactl info` before starting
- Single device mode (auto-disconnects extra devices)
- Robust reconnection detection
- Debug logging enabled

### Files

| Path | Purpose |
|------|---------|
| `/opt/oakhz/sounds/ready.wav` | Bluetooth ready notification (48kHz WAV) |
| `/opt/oakhz/sounds/connect.wav` | Device connection notification (48kHz WAV) |
| `/opt/oakhz/sounds/disconnect.wav` | Device disconnection (not used by default) |
| `/opt/oakhz/sounds/shutdown.wav` | System shutdown notification (48kHz WAV) |
| `/usr/local/bin/oakhz-audio-events.py` | Unified audio events manager (Python) |
| `/usr/local/bin/oakhz-shutdown-sound.sh` | Shutdown sound script (bash + paplay) |
| `/etc/systemd/system/oakhz-audio-events.service` | Main service (daemon) |
| `/etc/systemd/system/oakhz-shutdown-sound.service` | Shutdown service (oneshot) |

### Sound Generation Details

**Ready Sound (C major arpeggio):**
```bash
sox -n -r 48000 -c 2 ready.wav \
    synth 0.15 pluck C4 \
    synth 0.15 pluck E4 \
    synth 0.15 pluck G4 \
    synth 0.2 pluck C5 \
    fade t 0.01 0.6 0.1 norm -3
```
- Notes: C4 (261Hz), E4 (329Hz), G4 (392Hz), C5 (523Hz)
- Duration: 0.6s total
- Effect: Plucked string sound with fade

**Connect Sound (high chime):**
```bash
sox -n -r 48000 -c 2 connect.wav \
    synth 0.08 sine 1760 \
    synth 0.12 sine 2093 \
    fade t 0.01 0.2 0.08 norm -6
```
- Notes: A6 (1760Hz), C7 (2093Hz)
- Duration: 0.2s total
- Effect: Two overlapping sine tones

**Disconnect Sound (low bloop):**
```bash
sox -n -r 48000 -c 2 disconnect.wav \
    synth 0.12 sine 587 \
    synth 0.08 sine 523 \
    fade t 0.01 0.2 0.08 norm -6
```
- Notes: D5 (587Hz), C5 (523Hz)
- Duration: 0.2s total
- Effect: Descending tone pair

**Shutdown Sound (minor arpeggio):**
```bash
sox -n -r 48000 -c 2 shutdown.wav \
    synth 0.15 pluck G4 \
    synth 0.15 pluck E4 \
    synth 0.15 pluck C4 \
    synth 0.25 pluck G3 \
    fade t 0.01 0.7 0.2 norm -3
```
- Notes: G4 (392Hz), E4 (329Hz), C4 (261Hz), G3 (196Hz)
- Duration: 0.7s total
- Effect: Descending plucked arpeggio with longer fade

---

## 📊 Resource Usage

The sound feedback system has minimal impact on system resources:

| Component | CPU | RAM | Storage |
|-----------|-----|-----|---------|
| **oakhz-bt-monitor** | ~0.1% | ~15MB | - |
| **Sound files** | - | - | ~200KB total |
| **mpg123 (playing)** | ~2% | ~8MB | - |

**Total footprint**: ~25MB RAM when active, negligible when idle.

---

## 🔒 Security Considerations

- Scripts run as **root** (required for systemd integration)
- Sound files are **read-only** (644 permissions)
- Monitor uses standard `bluetoothctl` commands
- No network access required
- No sensitive data processed

---

## 🚀 Performance Tips

### Reduce Latency

If you experience delays, try:

```bash
# Reduce monitor polling interval
sudo nano /usr/local/bin/oakhz-bt-monitor.py
# Change: time.sleep(2) → time.sleep(1)

# Use smaller MP3 files
# Keep sounds under 0.5 seconds duration
```

### Disable Specific Sounds

```bash
# Disable disconnect sound only
sudo nano /usr/local/bin/oakhz-bt-monitor.py
# Comment out the disconnect sound section:
# if disconnected:
#     logger.info(f"Device disconnected: {disconnected}")
#     play_sound(SOUND_DISCONNECT)

sudo systemctl restart oakhz-bt-monitor
```

### Disable All Sound Feedback

```bash
# Stop and disable all services
sudo systemctl stop oakhz-ready-sound oakhz-bt-monitor oakhz-shutdown-sound
sudo systemctl disable oakhz-ready-sound oakhz-bt-monitor oakhz-shutdown-sound
```

---

*OaKhz Audio - October 2025*
