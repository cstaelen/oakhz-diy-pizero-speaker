# OaKhz Audio - Rotary Encoder Control

Physical rotary encoder control for OaKhz Audio. Provides volume control and media playback functions.

-- Written with Claude AI

---

## Table of Contents

- [Overview](#overview)
- [Hardware Requirements](#hardware-requirements)
- [Installation](#installation)
- [Controls](#controls)
- [Configuration](#configuration)
- [Service Management](#service-management)

---

## Overview

The rotary encoder provides physical controls:

| Gesture | Action |
| ------- | ------ |
| Rotate clockwise | Volume +3% |
| Rotate counter-clockwise | Volume -3% |
| Short press (< 1s) | Play / Pause |
| Medium press (≥ 1s) | Skip to next track |
| Long press (≥ 3s) | Shutdown system |

Volume is controlled via PulseAudio (`pactl` on the `camilladsp_out` sink). Media commands use BlueZ D-Bus (`MediaControl1`) on the connected Bluetooth device.

---

## Hardware Requirements

**Recommended**: KY-040 Rotary Encoder Module

**Wiring:**

```
KY-040 Rotary Encoder        Raspberry Pi Zero 2W
┌─────────────────┐          ┌──────────────────┐
│  CLK  ──────────┼──────────┤ GPIO 23 (Pin 16) │
│  DT   ──────────┼──────────┤ GPIO 24 (Pin 18) │
│  SW   ──────────┼──────────┤ GPIO 22 (Pin 15) │
│  +    ──────────┼──────────┤ 3.3V (Pin 1)     │
│  GND  ──────────┼──────────┤ GND (Pin 6)      │
└─────────────────┘          └──────────────────┘
```

> Use **3.3V**, not 5V — Raspberry Pi GPIO pins are 3.3V only.

---

## Installation

```bash
sudo bash scripts/setup-rotary.sh
```

The script:
1. Installs `python3-gpiozero`, `python3-rpi.gpio`, `playerctl`
2. Copies `/usr/local/bin/oakhz-rotary.py` from `system-files/`
3. Installs and enables `oakhz-rotary.service`
4. Adds the service user to the `gpio` group

Default GPIO pins can be overridden before running:

```bash
ROTARY_CLK=23 ROTARY_DT=24 ROTARY_SW=22 sudo -E bash scripts/setup-rotary.sh
```

### Verify Installation

```bash
sudo systemctl status oakhz-rotary
journalctl -u oakhz-rotary -f
```

Expected output on startup:

```
OaKhz Rotary Controller v4.0 (gpiozero)
Encoder: CLK=23, DT=24, SW=22
Rotary encoder initialized
Button initialized
Current volume: 75%
Rotary controller ready
```

---

## Controls

### Rotation — Volume

- Clockwise: **+3%** per step
- Counter-clockwise: **-3%** per step
- Range: 1–100%
- Throttled: max one change every 150ms

### Short press (< 1s) — Play/Pause

Toggles playback on the connected Bluetooth source via BlueZ `MediaControl1`:
- If playing → sends Pause
- If paused/stopped → sends Play

### Medium press (≥ 1s) — Skip track

Sends `MediaControl1.Next` to the connected Bluetooth device.

### Long press (≥ 3s) — Shutdown

1. Plays `/opt/oakhz/sounds/shutdown.mp3` via `mpg123` on `hw:Loopback,0`
2. Waits 1 second
3. Executes `sudo shutdown -h now`

---

## Configuration

### Change GPIO pins

Edit `/usr/local/bin/oakhz-rotary.py`:

```python
CLK_PIN = 23  # Change to your CLK pin
DT_PIN = 24   # Change to your DT pin
SW_PIN = 22   # Change to your SW pin
```

Then restart:

```bash
sudo systemctl restart oakhz-rotary
```

### Change volume step

Edit `/usr/local/bin/oakhz-rotary.py`:

```python
VOLUME_STEP = 3  # Percent per rotation step
```

### Change initial volume

The service sets volume to **75%** at startup via `ExecStartPre`. Edit `/etc/systemd/system/oakhz-rotary.service`:

```
ExecStartPre=/usr/bin/pactl set-sink-volume camilladsp_out 75%
```

Then reload:

```bash
sudo systemctl daemon-reload
sudo systemctl restart oakhz-rotary
```

---

## Service Management

```bash
sudo systemctl status oakhz-rotary
sudo systemctl restart oakhz-rotary
sudo systemctl stop oakhz-rotary
journalctl -u oakhz-rotary -f
journalctl -u oakhz-rotary -n 50
```

The service waits for PulseAudio to be ready before starting (`until pactl info`), then sets volume to 75%.

---

## Related Documentation

- [Base System Installation](./README-v2-install.md)
- [Web Equalizer Interface](./README-v2-equalizer.md)
- [WiFi Access Point](./README-v2-accesspoint.md)
- [Sound Feedback System](./README-v2-sound.md)
