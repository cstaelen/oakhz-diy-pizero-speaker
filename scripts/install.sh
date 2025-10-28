#!/bin/bash
#
# OaKhz Audio - Installation Script
# Automatic installation for Raspberry Pi OS Lite + HiFiBerry MiniAmp
#

set -e

# Get script directory and system files location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_FILES="$(cd "$SCRIPT_DIR/../system-files" && pwd)"

# Helper function to copy system files
copy_system_file() {
    local src="$1"
    local dest="$2"
    if [ -f "$SYSTEM_FILES/$src" ]; then
        cp "$SYSTEM_FILES/$src" "$dest"
        echo -e "${GREEN}✓ Installed: $dest${NC}"
    else
        echo -e "${RED}✗ File not found: $SYSTEM_FILES/$src${NC}"
        return 1
    fi
}

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}"
echo "=================================="
echo "  OaKhz Audio - Installation"
echo "=================================="
echo -e "${NC}"

# Root verification
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# Automatic user detection
if [ -n "$SUDO_USER" ]; then
    SERVICE_USER="$SUDO_USER"
else
    SERVICE_USER=$(logname 2>/dev/null || echo "pi")
fi

echo -e "${GREEN}Detected user: $SERVICE_USER${NC}"

INSTALL_DIR="/opt/oakhz"
USER_HOME="/home/$SERVICE_USER"

echo -e "${YELLOW}[1/9] Enabling Bluetooth...${NC}"
rfkill unblock bluetooth
sleep 2
hciconfig hci0 up

echo -e "${YELLOW}[2/8] System update...${NC}"
apt update
apt upgrade -y

echo -e "${YELLOW}[3/8] Installing dependencies...${NC}"
apt install -y \
    bluez \
    bluez-tools \
    pulseaudio \
    pulseaudio-module-bluetooth \
    alsa-utils \
    python3-pip \
    wget

echo -e "${YELLOW}[3.5/8] Installation de CamillaDSP...${NC}"

# Télécharge CamillaDSP (version ARM64)
CAMILLADSP_VERSION="2.0.3"
CAMILLADSP_URL="https://github.com/HEnquist/camilladsp/releases/download/v${CAMILLADSP_VERSION}/camilladsp-linux-aarch64.tar.gz"

cd /tmp
wget -O camilladsp.tar.gz "$CAMILLADSP_URL"
tar -xzf camilladsp.tar.gz
mv camilladsp /usr/local/bin/
chmod +x /usr/local/bin/camilladsp
rm camilladsp.tar.gz

echo -e "${GREEN}CamillaDSP installé : $(camilladsp --version)${NC}"

echo -e "${YELLOW}[4/8] Configuration du HiFiBerry MiniAmp...${NC}"

# Détecte le bon chemin config.txt
if [ -f /boot/firmware/config.txt ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
elif [ -f /boot/config.txt ]; then
    CONFIG_FILE="/boot/config.txt"
else
    echo -e "${RED}Fichier config.txt introuvable${NC}"
    exit 1
fi

echo -e "${GREEN}Configuration found : $CONFIG_FILE${NC}"

# Backup
cp $CONFIG_FILE ${CONFIG_FILE}.backup

# Disable onboard audio
sed -i 's/^dtparam=audio=on/#dtparam=audio=on/' $CONFIG_FILE

# Add HiFiBerry overlay if not already present
if ! grep -q "dtoverlay=hifiberry-dac" $CONFIG_FILE; then
    echo "dtoverlay=hifiberry-dac" >> $CONFIG_FILE
    echo -e "${GREEN}HiFiBerry MiniAmp configured${NC}"
else
    echo -e "${GREEN}HiFiBerry MiniAmp already configured${NC}"
fi

echo -e "${YELLOW}[5/8] Bluetooth configuration...${NC}"

# Backup existing config
if [ -f /etc/bluetooth/main.conf ]; then
    cp /etc/bluetooth/main.conf /etc/bluetooth/main.conf.backup
fi

# Bluetooth configuration
copy_system_file "etc/bluetooth/main.conf" "/etc/bluetooth/main.conf"

echo -e "${YELLOW}[6/8] PulseAudio and CamillaDSP configuration...${NC}"

# PulseAudio system service
copy_system_file "etc/systemd/system/pulseaudio.service" "/etc/systemd/system/pulseaudio.service"

# Add pulse to bluetooth group
usermod -a -G bluetooth pulse

# PulseAudio system configuration for CamillaDSP and Bluetooth
sed -i 's/load-module module-udev-detect$/load-module module-udev-detect ignore_dB=1 tsched=0/' /etc/pulse/system.pa

# Add Bluetooth and CamillaDSP à system.pa
cat "$SYSTEM_FILES/pulseaudio/system.pa.append" >> /etc/pulse/system.pa

# Load ALSA loopback module pour CamillaDSP
if ! lsmod | grep -q snd_aloop; then
    modprobe snd-aloop
    echo "snd-aloop" >> /etc/modules
fi

# ALSA configuration for HiFiBerry + CamillaDSP
copy_system_file "etc/asound.conf" "/etc/asound.conf"

# Configuration CamillaDSP
mkdir -p /opt/camilladsp
copy_system_file "opt/camilladsp/config.yml" "/opt/camilladsp/config.yml"

chmod 644 /opt/camilladsp/config.yml

# Service systemd pour CamillaDSP
copy_system_file "etc/systemd/system/camilladsp.service" "/etc/systemd/system/camilladsp.service"

echo -e "${YELLOW}[7/8] Bluetooth agent configuration...${NC}"

# bt-agent service for automatic NoInputNoOutput pairing
copy_system_file "etc/systemd/system/bt-agent.service" "/etc/systemd/system/bt-agent.service"

echo -e "${YELLOW}[8/8] Sudo permissions and services activation...${NC}"

# Allow user to reload CamillaDSP without password
copy_system_file "etc/sudoers.d/oakhz-camilladsp" "/etc/sudoers.d/oakhz-camilladsp"
chmod 440 /etc/sudoers.d/oakhz-camilladsp

# Give permissions to write on CamillaDSP config
chown $SERVICE_USER:$SERVICE_USER /opt/camilladsp/config.yml

echo -e "${GREEN}OaKhz Audio hostname configuration...${NC}"

# Configure pretty hostname
if [ -f /etc/machine-info ]; then
    # Backup existing file
    sudo cp /etc/machine-info /etc/machine-info.backup
    # Remove old line PRETTY_HOSTNAME if it exists
    sudo sed -i '/^PRETTY_HOSTNAME=/d' /etc/machine-info
fi

# Add or create file with new hostname
echo 'PRETTY_HOSTNAME="OaKhz audio"' | sudo tee -a /etc/machine-info > /dev/null

# Apply change immediately
sudo hostnamectl set-hostname --pretty "OaKhz Audio"

echo -e "${GREEN}✓ Hostname configuré !${NC}"
echo ""
echo "Device display name is now : OaKhz audio"
echo ""
echo "Verification :"
hostnamectl status | grep "Pretty hostname"

# Enable and start services
systemctl daemon-reload
systemctl restart bluetooth
systemctl enable bluetooth
systemctl enable pulseaudio
systemctl start pulseaudio
systemctl enable bt-agent
systemctl start bt-agent
systemctl enable camilladsp
systemctl start camilladsp

echo ""
echo -e "${GREEN}✓ Base system installation complete !${NC}"
echo ""
echo "Installed services :"
echo "  - Bluetooth : automatic pairing without PIN"
echo "  - PulseAudio : system audio management with Bluetooth"
echo "  - HiFiBerry MiniAmp : DAC audio output"
echo "  - CamillaDSP : 10-band parametric equalizer (48kHz)"
echo ""
echo "Your speaker is visible via Bluetooth as : 'OaKhz audio'"
echo ""
echo "Useful commands :"
echo "  sudo systemctl status camilladsp"
echo "  sudo systemctl status bt-agent"
echo "  sudo systemctl restart bluetooth"
echo "  bluetoothctl devices"
echo "  speaker-test -D camilladsp -c 2 -t wav  # Test sound with equalizer"
echo "  aplay -l  # Check sound cards"
echo ""
echo "Audio architecture :"
echo "  Bluetooth → PulseAudio → ALSA Loopback → CamillaDSP → HiFiBerry DAC"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT : Reboot Raspberry Pi to activate all services${NC}"
echo -e "${YELLOW}    sudo reboot${NC}"
echo ""
echo -e "${GREEN}Optional components:${NC}"
echo "  - Web Equalizer Interface: sudo bash scripts/setup-equalizer.sh"
echo "  - Sound Feedback System: sudo bash scripts/setup-sound.sh"
echo "  - Rotary Encoder Control: sudo bash scripts/setup-rotary.sh"
echo "  - WiFi Access Point: sudo bash scripts/setup-accesspoint.sh"
echo ""
