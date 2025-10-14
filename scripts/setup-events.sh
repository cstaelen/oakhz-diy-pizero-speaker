#!/bin/bash

################################################################################
# OaKhz Audio v2 - Events & Power Management Setup
################################################################################
# This script installs:
# 1. Bluetooth monitor with hibernation mode
# 2. Audio events manager (connection sounds)
# 3. Sound files for feedback
# 4. Systemd services
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (use sudo)"
    exit 1
fi

# Detect the main user
if [ -n "$SUDO_USER" ]; then
    MAIN_USER="$SUDO_USER"
else
    MAIN_USER=$(logname 2>/dev/null || echo "oakhz")
fi

log_info "Detected main user: $MAIN_USER"

################################################################################
# 1. Install dependencies
################################################################################
log_info "Installing dependencies..."
apt-get update -qq
apt-get install -y sox libsox-fmt-all python3 python3-dbus python3-gi gir1.2-glib-2.0 gpiod bc

log_success "Dependencies installed"

################################################################################
# 2. Create sound files directory
################################################################################
log_info "Creating sound files..."

mkdir -p /usr/share/sounds/oakhz

# Generate hello sound (C major arpeggio - Bluetooth ready)
if ! [ -f /usr/share/sounds/oakhz/hello.mp3 ]; then
    log_info "Generating hello.mp3 (Bluetooth ready sound)..."
    sox -n -r 48000 -c 2 /tmp/hello.wav \
        synth 0.15 sine 523.25 : \
        synth 0.15 sine 659.25 : \
        synth 0.3 sine 783.99 \
        fade t 0.01 : 0.6 0.1
    sox /tmp/hello.wav -C 192 /usr/share/sounds/oakhz/hello.mp3
    rm /tmp/hello.wav
    log_success "hello.mp3 created"
else
    log_warning "hello.mp3 already exists, skipping"
fi

# Generate pair sound (High chime - device connected)
if ! [ -f /usr/share/sounds/oakhz/pair.mp3 ]; then
    log_info "Generating pair.mp3 (device connected sound)..."
    sox -n -r 48000 -c 2 /tmp/pair.wav \
        synth 0.2 sine 1046.50 : \
        synth 0.3 sine 1318.51 \
        fade t 0.01 : 0.5 0.2
    sox /tmp/pair.wav -C 192 /usr/share/sounds/oakhz/pair.mp3
    rm /tmp/pair.wav
    log_success "pair.mp3 created"
else
    log_warning "pair.mp3 already exists, skipping"
fi

# Generate shutdown sound (Descending arpeggio)
if ! [ -f /usr/share/sounds/oakhz/shutdown.mp3 ]; then
    log_info "Generating shutdown.mp3 (system shutdown sound)..."
    sox -n -r 48000 -c 2 /tmp/shutdown.wav \
        synth 0.15 sine 783.99 : \
        synth 0.15 sine 659.25 : \
        synth 0.3 sine 523.25 \
        fade t 0.01 : 0.6 0.1
    sox /tmp/shutdown.wav -C 192 /usr/share/sounds/oakhz/shutdown.mp3
    rm /tmp/shutdown.wav
    log_success "shutdown.mp3 created"
else
    log_warning "shutdown.mp3 already exists, skipping"
fi

chmod 644 /usr/share/sounds/oakhz/*.mp3

################################################################################
# 3. Create bluetooth-monitor.sh
################################################################################
log_info "Creating bluetooth-monitor.sh..."

cat > /usr/local/bin/bluetooth-monitor.sh << 'EOF'
#!/bin/bash

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

HELLO_SOUND="/usr/share/sounds/oakhz/hello.mp3"
PAIR_SOUND="/usr/share/sounds/oakhz/pair.mp3"
VOLUME=0.15

NO_CLIENT_TIMER="/tmp/bt_no_client_since"
NO_STREAM_TIMER="/tmp/bt_no_stream_since"
DELAY=$((5*60))
PREV_STATE_FILE="/tmp/bt_client_prev_state"
PREV_STATE="disconnected"
GPIO_PIN=21

# Function to log
log() {
    echo "[bt-monitor] $1"
}

# Function to check if bluetooth is ready and pairable
wait_for_pairable() {
    for i in {1..300}; do
        if bluetoothctl show | grep -q "Powered: yes" &&
           bluetoothctl show | grep -q "Discoverable: yes" &&
           bluetoothctl show | grep -q "Pairable: yes"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Function to call when entering hibernate mode
hibernate() {
    log "Entering hibernate mode..."

    # 1. Disconnect all connected Bluetooth clients
    devices=$(bluetoothctl devices Connected | awk '{print $2}')
    for dev in $devices; do
        bluetoothctl disconnect $dev
    done

    # 2. Reduce CPU frequency to powersave governor
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo powersave | sudo tee $cpu > /dev/null
    done

    # 3. Mute audio output
    amixer -D default set 'SoftMaster' 0

    # 4. Set GPIO 21 (Pin 40) LOW to mute MiniAmp
    gpioset --mode=time --sec=1 gpiochip0 $GPIO_PIN=0

    # 5. Stop rotary encoder service
    systemctl stop oakhz-rotary 2>/dev/null || true

    log "Hibernate mode activated."
}

# Function to call when waking up
wake_up() {
    log "Waking up from hibernate"

    # Set GPIO 21 HIGH to enable MiniAmp
    gpioset --mode=time --sec=1 gpiochip0 $GPIO_PIN=1

    # Restore CPU frequency
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo ondemand | sudo tee $cpu > /dev/null
    done

    # Unmute audio (software)
    amixer -D default set 'SoftMaster' 80%

    # Start rotary encoder service
    systemctl start oakhz-rotary 2>/dev/null || true

    log "Wake up complete."
}

bt_should_hibernate() {
    command -v bc >/dev/null 2>&1 || { echo >&2 "Error: 'bc' is required but not installed."; exit 1; }

    # Read previous state if it exists
    if [ -f "$PREV_STATE_FILE" ]; then
        PREV_STATE=$(cat "$PREV_STATE_FILE")
    fi

    # Check Bluetooth connection
    CONNECTED=$(bluetoothctl devices Connected | grep "Device")

    if [ -z "$CONNECTED" ]; then
        CURRENT_STATE="disconnected"
        log "Client not connected"

        [ -f "$NO_STREAM_TIMER" ] && rm -f "$NO_STREAM_TIMER"

        if [ ! -f "$NO_CLIENT_TIMER" ]; then
            date +%s > "$NO_CLIENT_TIMER"
        else
            NOW=$(date +%s)
            START=$(cat "$NO_CLIENT_TIMER")
            ELAPSED=$((NOW - START))

            if [ $ELAPSED -ge $DELAY ]; then
                hibernate
                date +%s > "$NO_CLIENT_TIMER"
            fi
        fi

    else
        CURRENT_STATE="connected"
        log "Client connected"

        [ -f "$NO_CLIENT_TIMER" ] && rm -f "$NO_CLIENT_TIMER"

        CPU_USAGE=$(top -b -n1 | grep bluealsa | awk '{print $9}')
        THRESHOLD=0.1
        STREAM_ACTIVE=$(echo "$CPU_USAGE > $THRESHOLD" | bc)

        if [ "$STREAM_ACTIVE" -eq 1 ]; then
            log "Streaming active"
            [ -f "$NO_STREAM_TIMER" ] && rm -f "$NO_STREAM_TIMER"
        else
            log "No streaming active"
            if [ ! -f "$NO_STREAM_TIMER" ]; then
                date +%s > "$NO_STREAM_TIMER"
            else
                NOW=$(date +%s)
                START=$(cat "$NO_STREAM_TIMER")
                ELAPSED=$((NOW - START))

                if [ $ELAPSED -ge $DELAY ]; then
                    hibernate
                    date +%s > "$NO_STREAM_TIMER"
                fi
            fi
        fi
    fi

    # Detect transition from disconnected -> connected = wake_up
    if [ "$PREV_STATE" = "disconnected" ] && [ "$CURRENT_STATE" = "connected" ]; then
        wake_up
    fi

    # Save current state
    echo "$CURRENT_STATE" > "$PREV_STATE_FILE"
    log "Current state: $CURRENT_STATE"
}

# Startup: wait for Bluetooth to be pairable
if wait_for_pairable; then
    log "Bluetooth is ready for pairing"
    play --volume=$VOLUME "$HELLO_SOUND"
else
    log "Bluetooth not pairable after 30s"
    exit 1
fi

# Main loop
paired_announced=false
stream_ready_announced=false

while true; do
    connected_devices=$(bluetoothctl devices Connected | wc -l)

    # Refused connection if a device is already paired
    if [ "$connected_devices" -gt 1 ]; then
        echo "A device is already connected. Disconnect others."
        bluetoothctl devices Connected | awk '{print $2}' | tail -n +2 | while read -r mac; do
            echo "Disconnect $mac"
            bluetoothctl disconnect "$mac"
        done
    fi

    # Play sound on pairing
    if bluetoothctl info | grep -q "Paired: yes" && ! $paired_announced; then
        wake_up
        play --volume=$VOLUME "$PAIR_SOUND"
        paired_announced=true
    fi

    # Reset on disconnect
    if ! bluetoothctl info | grep -q "Connected: yes"; then
        paired_announced=false
        stream_ready_announced=false
    fi

    bt_should_hibernate
    sleep 1
done
EOF

chmod +x /usr/local/bin/bluetooth-monitor.sh
log_success "bluetooth-monitor.sh created"

################################################################################
# 4. Create oakhz-audio-events.py
################################################################################
log_info "Creating oakhz-audio-events.py..."

cat > /usr/local/bin/oakhz-audio-events.py << 'EOF'
#!/usr/bin/env python3
"""
OaKhz Audio Events Manager
Monitors Bluetooth connections and plays feedback sounds
"""

import dbus
import dbus.mainloop.glib
from gi.repository import GLib
import subprocess
import time
import os

PAIR_SOUND = "/usr/share/sounds/oakhz/pair.mp3"
SHUTDOWN_SOUND = "/usr/share/sounds/oakhz/shutdown.mp3"
VOLUME = "0.65"

def log(message):
    print(f"[audio-events] {message}", flush=True)

def play_sound(sound_file):
    """Play sound via paplay (PulseAudio)"""
    try:
        if os.path.exists(sound_file):
            subprocess.run([
                "paplay",
                "--volume", str(int(float(VOLUME) * 65536)),
                sound_file
            ], check=True)
            log(f"Played: {sound_file}")
        else:
            log(f"Sound file not found: {sound_file}")
    except subprocess.CalledProcessError as e:
        log(f"Error playing sound: {e}")

class BluetoothMonitor:
    def __init__(self):
        self.connected_devices = set()

        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        self.bus = dbus.SystemBus()

        # Monitor PropertiesChanged signals from BlueZ
        self.bus.add_signal_receiver(
            self.properties_changed,
            dbus_interface="org.freedesktop.DBus.Properties",
            signal_name="PropertiesChanged",
            path_keyword="path"
        )

        log("Audio events monitor started")

        # Check initial state
        self.scan_connected_devices()

    def scan_connected_devices(self):
        """Scan for already connected devices at startup"""
        try:
            result = subprocess.run(
                ["bluetoothctl", "devices", "Connected"],
                capture_output=True,
                text=True,
                check=True
            )

            for line in result.stdout.strip().split('\n'):
                if line and "Device" in line:
                    mac = line.split()[1]
                    if mac not in self.connected_devices:
                        self.connected_devices.add(mac)
                        log(f"Already connected at startup: {mac}")
        except Exception as e:
            log(f"Error scanning devices: {e}")

    def properties_changed(self, interface, changed, invalidated, path):
        """Handle Bluetooth property changes"""
        if interface != "org.bluez.Device1":
            return

        if "Connected" in changed:
            connected = changed["Connected"]
            device_path = str(path)

            # Extract MAC address from path
            mac = device_path.split("/")[-1].replace("dev_", "").replace("_", ":")

            if connected:
                if mac not in self.connected_devices:
                    self.connected_devices.add(mac)
                    log(f"Device connected: {mac}")
                    time.sleep(0.5)  # Small delay for audio system
                    play_sound(PAIR_SOUND)
            else:
                if mac in self.connected_devices:
                    self.connected_devices.remove(mac)
                    log(f"Device disconnected: {mac}")

def handle_shutdown():
    """Play shutdown sound before system halts"""
    log("Shutdown detected")
    play_sound(SHUTDOWN_SOUND)
    time.sleep(2)  # Wait for sound to finish

def main():
    try:
        monitor = BluetoothMonitor()
        loop = GLib.MainLoop()

        # Handle graceful shutdown
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, 15, lambda: loop.quit())  # SIGTERM
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, 2, lambda: loop.quit())   # SIGINT

        loop.run()

    except KeyboardInterrupt:
        log("Interrupted by user")
    except Exception as e:
        log(f"Fatal error: {e}")
    finally:
        handle_shutdown()

if __name__ == "__main__":
    main()
EOF

chmod +x /usr/local/bin/oakhz-audio-events.py
log_success "oakhz-audio-events.py created"

################################################################################
# 5. Create systemd services
################################################################################
log_info "Creating systemd services..."

# Bluetooth monitor service
cat > /etc/systemd/system/bluetooth-monitor.service << EOF
[Unit]
Description=Bluetooth Monitor with Hibernate/Wake-up
After=network.target bluetooth.target sound.target
Wants=bluetooth.target

[Service]
ExecStart=/usr/local/bin/bluetooth-monitor.sh
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

log_success "bluetooth-monitor.service created"

# Audio events service
cat > /etc/systemd/system/oakhz-audio-events.service << EOF
[Unit]
Description=OaKhz Audio Events Manager
After=sound.target bluetooth.target pulseaudio.service
Wants=bluetooth.service

[Service]
Type=simple
User=$MAIN_USER
Group=audio
ExecStartPre=/bin/sleep 10
ExecStartPre=/bin/sh -c 'until pactl info >/dev/null 2>&1; do sleep 1; done'
ExecStart=/usr/bin/python3 /usr/local/bin/oakhz-audio-events.py
Restart=always
RestartSec=5
Environment="XDG_RUNTIME_DIR=/run/user/1000"
Environment="PULSE_RUNTIME_PATH=/run/user/1000/pulse"

[Install]
WantedBy=multi-user.target
EOF

log_success "oakhz-audio-events.service created"

################################################################################
# 6. Enable and start services
################################################################################
log_info "Enabling and starting services..."

systemctl daemon-reload

systemctl enable bluetooth-monitor.service
systemctl enable oakhz-audio-events.service

systemctl restart bluetooth-monitor.service
systemctl restart oakhz-audio-events.service

sleep 2

################################################################################
# 7. Verify installation
################################################################################
log_info "Verifying installation..."

errors=0

# Check bluetooth-monitor service
if systemctl is-active --quiet bluetooth-monitor.service; then
    log_success "bluetooth-monitor.service is running"
else
    log_error "bluetooth-monitor.service is NOT running"
    ((errors++))
fi

# Check audio-events service
if systemctl is-active --quiet oakhz-audio-events.service; then
    log_success "oakhz-audio-events.service is running"
else
    log_error "oakhz-audio-events.service is NOT running"
    ((errors++))
fi

# Check sound files
for sound in hello.mp3 pair.mp3 shutdown.mp3; do
    if [ -f "/usr/share/sounds/oakhz/$sound" ]; then
        log_success "$sound exists"
    else
        log_error "$sound NOT found"
        ((errors++))
    fi
done

################################################################################
# Summary
################################################################################
echo ""
echo "═══════════════════════════════════════════════════════════════"
if [ $errors -eq 0 ]; then
    log_success "Events & Power Management setup completed successfully!"
    echo ""
    log_info "Features enabled:"
    echo "  • Bluetooth ready sound (C major arpeggio)"
    echo "  • Device connection sound (high chime)"
    echo "  • Shutdown sound (descending arpeggio)"
    echo "  • Auto-hibernation after 5 minutes of inactivity"
    echo "  • Auto wake-up on Bluetooth connection"
    echo "  • Single device mode (auto-disconnect old devices)"
    echo ""
    log_info "Test the sounds:"
    echo "  play --volume=0.15 /usr/share/sounds/oakhz/hello.mp3"
    echo "  play --volume=0.15 /usr/share/sounds/oakhz/pair.mp3"
    echo "  play --volume=0.15 /usr/share/sounds/oakhz/shutdown.mp3"
    echo ""
    log_info "Monitor services:"
    echo "  sudo systemctl status bluetooth-monitor"
    echo "  sudo systemctl status oakhz-audio-events"
    echo ""
    log_info "View logs:"
    echo "  sudo journalctl -u bluetooth-monitor -f"
    echo "  sudo journalctl -u oakhz-audio-events -f"
else
    log_error "Setup completed with $errors error(s)"
    echo ""
    log_warning "Check the logs for details:"
    echo "  sudo journalctl -u bluetooth-monitor -n 50"
    echo "  sudo journalctl -u oakhz-audio-events -n 50"
fi
echo "═══════════════════════════════════════════════════════════════"
