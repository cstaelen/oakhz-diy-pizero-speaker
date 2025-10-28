#!/bin/bash
#
# OaKhz Audio - Web Equalizer Setup
# Installs Flask web interface for CamillaDSP control
#
# Prerequisites: Base system installed (install.sh must be run first)
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
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}"
echo "============================================"
echo "  OaKhz Audio - Web Equalizer Setup"
echo "============================================"
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

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

if [ ! -f "/usr/local/bin/camilladsp" ]; then
    echo -e "${RED}✗ CamillaDSP not found${NC}"
    echo -e "${YELLOW}Please run install.sh first to install base system${NC}"
    exit 1
fi

if [ ! -f "/opt/camilladsp/config.yml" ]; then
    echo -e "${RED}✗ CamillaDSP configuration not found${NC}"
    echo -e "${YELLOW}Please run install.sh first to install base system${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}"
echo ""

# ============================================
# PHASE 1: Install Python dependencies
# ============================================
echo -e "${YELLOW}[1/4] Installing Python dependencies...${NC}"

apt update
apt install -y \
    python3-pip \
    python3-flask \
    python3-flask-cors \
    python3-yaml \
    python3-websocket

echo -e "${GREEN}✓ Python dependencies installed${NC}"

# ============================================
# PHASE 2: Install Flask server and web interface
# ============================================
echo -e "${YELLOW}[2/4] Installing web interface...${NC}"

# Creating directories
mkdir -p $INSTALL_DIR/templates
cd $INSTALL_DIR

# Flask server
copy_system_file "opt/oakhz/eq_server.py" "$INSTALL_DIR/eq_server.py"
chmod +x $INSTALL_DIR/eq_server.py

# Web Interface HTML
copy_system_file "opt/oakhz/templates/index.html" "$INSTALL_DIR/templates/index.html"

# Service systemd pour l'equalizer
copy_system_file "etc/systemd/system/oakhz-equalizer.service" "/etc/systemd/system/oakhz-equalizer.service"

echo -e "${GREEN}✓ Web interface installed${NC}"

# ============================================
# PHASE 3: Configure Python capabilities
# ============================================
echo -e "${YELLOW}[3/4] Configuring Python to bind port 80...${NC}"

# Allow Python to bind to port 80 (privileged port)
setcap 'cap_net_bind_service=+ep' /usr/bin/python3 || setcap 'cap_net_bind_service=+ep' $(which python3)

echo -e "${GREEN}✓ Python configured for port 80${NC}"

# ============================================
# PHASE 4: Enable and start service
# ============================================
echo -e "${YELLOW}[4/4] Enabling equalizer service...${NC}"

systemctl daemon-reload
systemctl enable oakhz-equalizer
systemctl start oakhz-equalizer

# Wait for service to start
sleep 2

# Check service status
if systemctl is-active --quiet oakhz-equalizer; then
    echo -e "${GREEN}✓ Equalizer service is running${NC}"
else
    echo -e "${RED}✗ Equalizer service failed to start${NC}"
    echo -e "${YELLOW}Check logs: sudo journalctl -u oakhz-equalizer -n 50${NC}"
    exit 1
fi

# ============================================
# Summary
# ============================================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Web Equalizer Setup Complete! 🎛️${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Service status:"
echo "  ✓ oakhz-equalizer: $(systemctl is-active oakhz-equalizer)"
echo ""
echo "Web interface:"
echo "  🌐 http://$(hostname -I | awk '{print $1}')"
echo ""
echo "Features:"
echo "  • 10-band parametric equalizer (CamillaDSP)"
echo "  • Real-time frequency adjustment"
echo "  • Visual frequency response graph"
echo "  • Preset management"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status oakhz-equalizer"
echo "  sudo systemctl restart oakhz-equalizer"
echo "  sudo journalctl -u oakhz-equalizer -f"
echo ""
echo "Configuration files:"
echo "  • Flask server: /opt/oakhz/eq_server.py"
echo "  • Web UI: /opt/oakhz/templates/index.html"
echo "  • CamillaDSP config: /opt/camilladsp/config.yml"
echo ""
