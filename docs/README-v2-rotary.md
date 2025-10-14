# 🎛️ OaKhz Audio - Rotary Encoder Control

Physical rotary encoder control for OaKhz Audio Bluetooth speaker. Provides tactile volume control and media functions.

-- Written with Claude AI

---

## 📋 Table of Contents

- [Overview](#overview)
- [Hardware Requirements](#hardware-requirements)
- [Installation](#installation)
- [Controls](#controls)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Technical Details](#technical-details)
- [Customization](#customization)

---

## 🎯 Overview

The OaKhz Audio rotary encoder system provides intuitive physical controls:

- **Rotate** - Volume up/down
- **Single click** - Mute/unmute
- **Double click** - Skip to next track
- **Long press (2s)** - Shutdown system

All controls work seamlessly with PulseAudio and Bluetooth audio sources.

---

## 🛠️ Hardware Requirements

### Rotary Encoder Module

**Recommended**: KY-040 Rotary Encoder Module

**Specifications:**
- Operating Voltage: 5V
- Interface: CLK, DT, SW, +, GND
- Rotation: 360° endless rotation
- Click: Built-in push button

**Where to buy:**
- AliExpress, Amazon, eBay
- Search: "KY-040 rotary encoder"
- Price: ~$1-3

### Wiring Diagram

```
KY-040 Rotary Encoder        Raspberry Pi Zero 2W
┌─────────────────┐          ┌──────────────────┐
│                 │          │                  │
│  CLK  ──────────┼──────────┤ GPIO 23          │
│  DT   ──────────┼──────────┤ GPIO 24          │
│  SW   ──────────┼──────────┤ GPIO 22          │
│  +    ──────────┼──────────┤ 3.3V (Pin 1)     │
│  GND  ──────────┼──────────┤ GND (Pin 6)      │
│                 │          │                  │
└─────────────────┘          └──────────────────┘
```

### GPIO Pin Reference

| Function | GPIO BCM | Physical Pin | Wire Color (typical) |
|----------|----------|--------------|----------------------|
| **CLK** (Rotation) | GPIO 23 | Pin 16 | White/Yellow |
| **DT** (Direction) | GPIO 24 | Pin 18 | Green |
| **SW** (Button) | GPIO 22 | Pin 15 | Blue |
| **VCC** (Power) | 3.3V | Pin 1 | Red |
| **GND** (Ground) | GND | Pin 6 | Black |

**⚠️ Important:** Use 3.3V, NOT 5V! Raspberry Pi GPIO pins are 3.3V only.

---

## 🚀 Installation

### Prerequisites

- Raspberry Pi OS Lite 64-bit
- OaKhz Audio base system installed
- Rotary encoder connected to GPIO pins

### Quick Installation

```bash
# Download and run installation script
sudo bash scripts/setup-rotary.sh
```

The script will:
1. Install `python3-rpi.gpio`, `python3-gpiozero`, `playerctl`
2. Create `/usr/local/bin/oakhz-rotary.py` control script
3. Create and enable `oakhz-rotary.service`
4. Start the service

### Verify Installation

```bash
# Check service status
sudo systemctl status oakhz-rotary

# View live logs
journalctl -u oakhz-rotary -f
```

You should see:
```
==================================================
OaKhz Rotary Controller v3.6 (gpiozero)
Encoder: CLK=23, DT=24, SW=22
==================================================
Rotary encoder initialized
Button initialized
Current volume: 50%
Controls:
  🔄 Rotate:         Volume ±3%
  🔘 Short press:    Mute/Unmute
  🔘 Medium press:   Skip track
  ⏱️  Long press (3s): Shutdown
==================================================
Rotary controller ready
```

---

## 🎮 Controls

### Rotation - Volume Control

**Clockwise rotation** → Volume +5%
**Counter-clockwise rotation** → Volume -5%

- Smooth volume adjustment
- Automatic unmute if currently muted
- Range: 0-100%
- Step: 5% per click

**Example:**
```
Current volume: 50%
Rotate clockwise 3 clicks → 65%
Rotate counter-clockwise 2 clicks → 55%
```

### Single Click - Mute/Unmute Toggle

**Press and release** (< 0.4s)

- **First click** → Mute audio (saves current volume)
- **Second click** → Unmute (restores saved volume)

**Visual feedback:** Check logs:
```bash
journalctl -u oakhz-rotary -f
# Shows: "Muted (saved volume: 75%)"
# Or: "Unmuted (restored volume: 75%)"
```

### Double Click - Skip Track

**Press twice quickly** (within 0.4s)

- Skips to next track in playlist
- Works with Bluetooth audio sources
- Uses `playerctl` (universal) or BlueZ D-Bus (fallback)

**Supported sources:**
- Spotify (mobile/desktop)
- YouTube Music
- Apple Music
- Any Bluetooth A2DP source with AVRCP

### Long Press - System Shutdown

**Press and hold** (2+ seconds)

1. Plays shutdown sound (`/opt/oakhz/sounds/shutdown.mp3`)
2. Waits 1 second for sound to finish
3. Executes `sudo shutdown -h now`

**⚠️ Warning:** This immediately shuts down the system. Ensure you have saved any work.

---

## ⚙️ Configuration

### Service Management

```bash
# Check status
sudo systemctl status oakhz-rotary

# Start service
sudo systemctl start oakhz-rotary

# Stop service
sudo systemctl stop oakhz-rotary

# Restart service
sudo systemctl restart oakhz-rotary

# Enable at boot
sudo systemctl enable oakhz-rotary

# Disable at boot
sudo systemctl disable oakhz-rotary

# View logs
journalctl -u oakhz-rotary -f

# View last 50 log lines
journalctl -u oakhz-rotary -n 50
```

### Change GPIO Pins

If your wiring differs, edit the configuration:

```bash
sudo nano /usr/local/bin/oakhz-rotary.py
```

Change these lines near the top:
```python
# GPIO Configuration
CLK_PIN = 23  # Change to your CLK pin
DT_PIN = 24   # Change to your DT pin
SW_PIN = 22   # Change to your SW pin
```

Then restart:
```bash
sudo systemctl restart oakhz-rotary
```

### Adjust Volume Step

To change volume increment per rotation:

```bash
sudo nano /usr/local/bin/oakhz-rotary.py
```

Change:
```python
# Volume settings
VOLUME_STEP = 5  # Change from 5% to your preference (1-20)
```

**Examples:**
- `VOLUME_STEP = 2` → Fine control (50 clicks for 0-100%)
- `VOLUME_STEP = 10` → Coarse control (10 clicks for 0-100%)

### Adjust Click Timing

```bash
sudo nano /usr/local/bin/oakhz-rotary.py
```

Modify timing constants:
```python
# Button timing (in seconds)
DEBOUNCE_TIME = 0.02        # Anti-bounce delay
DOUBLE_CLICK_TIME = 0.4     # Max time between clicks for double-click
LONG_PRESS_TIME = 2.0       # How long to hold for shutdown
```

After any changes:
```bash
sudo systemctl restart oakhz-rotary
```

---

## 🔧 Troubleshooting

### Rotary Encoder Not Responding

**Check wiring:**
```bash
# Test GPIO pins
gpio readall
```

**Check service:**
```bash
sudo systemctl status oakhz-rotary
journalctl -u oakhz-rotary -n 50
```

**Common issues:**
- ❌ Wrong GPIO pins → Check wiring against pin configuration
- ❌ 5V instead of 3.3V → **DANGEROUS!** Use 3.3V only
- ❌ Loose connections → Check breadboard/jumper wires
- ❌ Wrong ground → Ensure GND is connected

**Test GPIO manually:**
```bash
# Install GPIO test tool
sudo apt install python3-gpiozero

# Test rotation detection
python3 << 'EOF'
from gpiozero import RotaryEncoder
from signal import pause

encoder = RotaryEncoder(23, 24)
encoder.when_rotated_clockwise = lambda: print("Clockwise")
encoder.when_rotated_counter_clockwise = lambda: print("Counter-clockwise")

print("Rotate encoder... (Ctrl+C to exit)")
pause()
EOF
```

### Volume Not Changing

**Check PulseAudio:**
```bash
# Verify PulseAudio is running
systemctl status pulseaudio

# Check default sink
pactl info | grep "Default Sink"
# Should show: camilladsp_out

# Test volume manually
pactl set-sink-volume camilladsp_out 50%
pactl get-sink-volume camilladsp_out
```

**Check logs for errors:**
```bash
journalctl -u oakhz-rotary -f
# Look for "Set volume error" messages
```

### Button Clicks Not Working

**Test button manually:**
```bash
python3 << 'EOF'
from gpiozero import Button
from signal import pause

button = Button(22)
button.when_pressed = lambda: print("Pressed")
button.when_released = lambda: print("Released")

print("Press button... (Ctrl+C to exit)")
pause()
EOF
```

**Check debounce settings:**
- If clicks are missed → Increase `DEBOUNCE_TIME` to 0.05
- If double-clicks register as singles → Increase `DOUBLE_CLICK_TIME` to 0.6

### Track Skip Not Working

**Check if Bluetooth device is connected:**
```bash
bluetoothctl devices Connected
```

**Test playerctl:**
```bash
# Check if playerctl sees media player
playerctl status

# Try manual skip
playerctl next
```

**Check BlueZ D-Bus (fallback):**
```bash
# Get connected device MAC
MAC=$(bluetoothctl devices Connected | grep -oP 'Device \K[^ ]+')
echo "Connected: $MAC"

# Test skip via D-Bus
dbus-send --system --type=method_call \
  --dest=org.bluez \
  /org/bluez/hci0/dev_${MAC//:/_} \
  org.bluez.MediaControl1.Next
```

### Long Press Triggers Too Soon/Late

Adjust timing:
```bash
sudo nano /usr/local/bin/oakhz-rotary.py
```

Change:
```python
LONG_PRESS_TIME = 2.0  # Increase to 3.0 or decrease to 1.5
```

### Service Won't Start

**Check Python dependencies:**
```bash
python3 -c "import RPi.GPIO, gpiozero"
```

If error, reinstall:
```bash
sudo apt install --reinstall python3-rpi.gpio python3-gpiozero
```

**Check permissions:**
```bash
ls -l /usr/local/bin/oakhz-rotary.py
# Should show: -rwxr-xr-x (executable)

# If not:
sudo chmod +x /usr/local/bin/oakhz-rotary.py
```

---

## 🏗️ Technical Details

### Architecture

```
┌─────────────────────────────────────────────┐
│         Physical Controls                   │
├─────────────────────────────────────────────┤
│  Rotation     │  Click       │  Long Press  │
│  (CLK+DT)     │  (SW)        │  (SW held)   │
└──────┬────────┴───────┬──────┴──────┬───────┘
       │                │             │
┌──────▼────────────────▼─────────────▼───────┐
│         gpiozero Library                     │
│  ┌──────────────┐  ┌──────────────────────┐ │
│  │ RotaryEncoder│  │  Button              │ │
│  │  - Clockwise │  │  - when_pressed      │ │
│  │  - Counter   │  │  - when_released     │ │
│  │    clockwise │  │  - when_held         │ │
│  └──────────────┘  └──────────────────────┘ │
└──────┬────────────────┬─────────────┬────────┘
       │                │             │
┌──────▼────────────────▼─────────────▼────────┐
│      OakhzRotaryController Class             │
│  ┌─────────────────────────────────────────┐ │
│  │ • volume_up()     • volume_down()       │ │
│  │ • toggle_mute()   • skip_track()        │ │
│  │ • shutdown_system()                     │ │
│  └─────────────────────────────────────────┘ │
└──────┬────────────────┬─────────────┬─────────┘
       │                │             │
┌──────▼────────┐  ┌────▼──────┐  ┌──▼─────────┐
│  PulseAudio   │  │ playerctl │  │  shutdown  │
│  (amixer)     │  │ / D-Bus   │  │  command   │
└───────────────┘  └───────────┘  └────────────┘
```

### Click Detection Algorithm

```python
# Single vs Double Click Logic
if time_since_last_click <= DOUBLE_CLICK_TIME:
    click_count += 1
else:
    click_count = 1

# Wait for potential second click
sleep(DOUBLE_CLICK_TIME + 0.05)

# Process
if click_count == 1:
    → Mute/Unmute
elif click_count >= 2:
    → Skip Track
```

### Volume Control

Uses PulseAudio `camilladsp_out` sink:
```bash
pactl get-sink-volume camilladsp_out  # Get volume
pactl set-sink-volume camilladsp_out 75%  # Set volume
```

Volume control flow:
1. Script calls `pactl set-sink-volume camilladsp_out XX%`
2. PulseAudio adjusts volume on `camilladsp_out` sink
3. Audio flows: PulseAudio → Loopback → CamillaDSP → HiFiBerry

Volume stored globally:
- `last_volume` - Saved volume before mute (for restore)
- Throttling: 150ms delay between volume changes to prevent event flooding

### Track Skip Methods

**Priority 1 - playerctl:**
```bash
playerctl next
```
Works with most media players (Spotify, YouTube Music, etc.)

**Priority 2 - BlueZ D-Bus:**
```bash
dbus-send --system --type=method_call \
  --dest=org.bluez \
  /org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX \
  org.bluez.MediaControl1.Next
```
Works with Bluetooth devices supporting AVRCP.

### Dependencies

| Package | Purpose | Size |
|---------|---------|------|
| **python3-rpi.gpio** | Low-level GPIO control | ~150KB |
| **python3-gpiozero** | High-level GPIO abstraction | ~500KB |
| **playerctl** | Media player control | ~100KB |

Total additional space: ~750KB

### Service Configuration

```ini
[Unit]
Description=OaKhz Rotary Encoder Controller
After=pulseaudio.service bluetooth.service sound.target
Requires=pulseaudio.service

[Service]
Type=simple
User=oakhz
Group=gpio
SupplementaryGroups=audio
WorkingDirectory=/home/oakhz
ExecStart=/usr/bin/python3 /usr/local/bin/oakhz-rotary.py
Restart=always
RestartSec=5
Environment="PULSE_SERVER=unix:/run/pulse/native"
Environment="HOME=/home/oakhz"

[Install]
WantedBy=multi-user.target
```

**Service runs as `oakhz` user:**
- User must be in `gpio` group for GPIO access
- User must be in `audio` group for PulseAudio access
- `PULSE_SERVER` environment variable points to system PulseAudio socket

### Resource Usage

| Resource | Idle | Active (rotation) |
|----------|------|-------------------|
| **CPU** | < 0.5% | ~2% |
| **RAM** | ~15MB | ~18MB |
| **GPIO Interrupts** | Event-driven | Event-driven |

Very low overhead - safe for continuous operation.

---

## 🎨 Customization

### Different Encoder Model

If using a different rotary encoder (not KY-040):

**Check your encoder specifications:**
- Some encoders use different pull-up/pull-down resistors
- Some require different debounce values
- Some have inverted CLK/DT signals

**Test and adjust:**
```python
# In oakhz-rotary.py
self.encoder = RotaryEncoder(CLK_PIN, DT_PIN,
                             max_steps=0,
                             wrap=False,      # Don't wrap around
                             threshold_steps=(0, 0))  # Adjust sensitivity
```

### Add LED Feedback

Want visual feedback? Add an LED:

```python
from gpiozero import LED

# Add to __init__
self.led = LED(23)  # GPIO 23 for LED

# In toggle_mute
def toggle_mute(self):
    # ... existing code ...
    if self.is_muted:
        self.led.on()  # LED on when muted
    else:
        self.led.off()  # LED off when unmuted
```

**Wiring:**
```
LED+ → GPIO 23
LED- → 220Ω resistor → GND
```

### Add Acceleration

Want faster volume changes with rapid rotation?

```python
import time

class OakhzRotaryController:
    def __init__(self):
        # ... existing code ...
        self.last_rotation_time = 0
        self.rotation_speed = 1.0

    def volume_up(self):
        # Calculate rotation speed
        current_time = time.time()
        if current_time - self.last_rotation_time < 0.1:
            self.rotation_speed = min(4.0, self.rotation_speed + 0.5)
        else:
            self.rotation_speed = 1.0

        self.last_rotation_time = current_time

        # Apply accelerated volume change
        step = int(VOLUME_STEP * self.rotation_speed)
        new_volume = self.current_volume + step
        self.set_volume(new_volume)
```

### Multiple Functions

Want more button actions? Add:

**Triple click:**
```python
# In process_clicks()
elif self.click_count == 3:
    logger.info("Triple click → Previous track")
    subprocess.run(['playerctl', 'previous'])
```

**Different long press durations:**
```python
def button_released(self):
    press_duration = time.time() - self.button_press_time

    if 2.0 <= press_duration < 5.0:
        logger.info("Medium press → Reboot")
        subprocess.run(['sudo', 'reboot'])
    elif press_duration >= 5.0:
        logger.info("Very long press → Shutdown")
        self.shutdown_system()
```

---

## 📊 Performance Tips

### Reduce Latency

For instant response:

```python
# Lower debounce time (if no bouncing issues)
DEBOUNCE_TIME = 0.01

# Lower thread sleep in process_clicks
time.sleep(DOUBLE_CLICK_TIME + 0.02)  # Was 0.05
```

### Battery Optimization

For battery-powered builds:

```python
# Reduce logging
logging.basicConfig(level=logging.WARNING)  # Was INFO

# Increase sleep time in main loop
# (gpiozero handles interrupts efficiently already)
```

---

## 🔒 Security Notes

- Script runs as **root** (required for GPIO)
- No network access
- No external dependencies downloaded at runtime
- Shutdown command requires local physical access

**For extra security:**
```bash
# Restrict script permissions
sudo chown root:root /usr/local/bin/oakhz-rotary.py
sudo chmod 750 /usr/local/bin/oakhz-rotary.py
```

---

## 🐛 Known Issues

### Issue: Phantom Rotations

**Symptom:** Volume changes randomly without rotation

**Causes:**
- Electromagnetic interference
- Poor quality encoder
- Loose wiring

**Solutions:**
1. Add capacitor between CLK/GND and DT/GND (0.1µF)
2. Use shielded cables
3. Enable pull-up resistors in software:
```python
self.encoder = RotaryEncoder(CLK_PIN, DT_PIN,
                             bounce_time=0.05)  # Increase bounce time
```

### Issue: Missed Clicks

**Symptom:** Need to click twice for single action

**Solutions:**
1. Check button quality
2. Increase debounce:
```python
DEBOUNCE_TIME = 0.05
```

### Issue: Wrong Rotation Direction

**Symptom:** Clockwise decreases volume

**Solution:** Swap CLK and DT pins in code:
```python
# Swap these:
CLK_PIN = 24  # Was 23
DT_PIN = 23   # Was 24
```

---

*OaKhz Audio - October 2025*
