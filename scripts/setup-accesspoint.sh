#!/bin/bash

################################################################################
# OaKhz Audio - Permanent WiFi Access Point + Captive Portal + Recovery Mode
################################################################################
# This script installs:
# 1. hostapd (WiFi Access Point - permanent mode)
# 2. dnsmasq (DHCP + DNS + Captive Portal)
# 3. Recovery mode (emergency WiFi client access)
# 4. Static IP configuration (wlan0-ap.service)
################################################################################

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
        echo "  ✓ Installed: $dest"
    else
        echo "  ✗ File not found: $SYSTEM_FILES/$src"
        return 1
    fi
}

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

# Configuration variables
AP_SSID="OaKhz Wifi"
AP_PASSWORD="oakhzwifi"
AP_IP="192.168.50.1"
AP_DHCP_START="192.168.50.10"
AP_DHCP_END="192.168.50.50"
AP_CHANNEL="6"
WIFI_INTERFACE="wlan0"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  OaKhz Audio - WiFi Access Point Setup"
echo "═══════════════════════════════════════════════════════════════"
echo ""
log_info "Configuration:"
echo "  • Mode: Permanent Access Point (100%)"
echo "  • SSID: $AP_SSID"
echo "  • Password: $AP_PASSWORD"
echo "  • IP Address: $AP_IP"
echo "  • DHCP Range: $AP_DHCP_START - $AP_DHCP_END"
echo "  • Captive Portal: Enabled"
echo "  • Recovery Mode: File-based (/boot/firmware/enable-wifi-client)"
echo ""

read -p "Continue with installation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warning "Installation cancelled"
    exit 0
fi

################################################################################
# 1. Check WiFi interface
################################################################################
log_info "Checking WiFi interface..."

if ! ip link show "$WIFI_INTERFACE" &> /dev/null; then
    log_error "WiFi interface $WIFI_INTERFACE not found!"
    log_info "Available interfaces:"
    ip link show | grep -E "^[0-9]+:" | awk '{print $2}' | sed 's/:$//'
    exit 1
fi

log_success "WiFi interface $WIFI_INTERFACE found"

################################################################################
# 2. Install dependencies
################################################################################
log_info "Installing dependencies..."
apt-get update -qq
apt-get install -y hostapd dnsmasq

log_success "Dependencies installed"

################################################################################
# 3. Backup existing configurations
################################################################################
log_info "Backing up existing configurations..."

if [ -f /etc/hostapd/hostapd.conf ]; then
    cp /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.backup
    log_warning "Existing hostapd.conf backed up"
fi

if [ -f /etc/dnsmasq.conf ]; then
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
    log_warning "Existing dnsmasq.conf backed up"
fi

log_success "Backups created"

################################################################################
# 4. Configure hostapd (Access Point)
################################################################################
log_info "Configuring hostapd..."

copy_system_file "etc/hostapd/hostapd.conf" "/etc/hostapd/hostapd.conf"

chmod 600 /etc/hostapd/hostapd.conf

# Update hostapd default config
sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd 2>/dev/null || true

log_success "hostapd configured"

################################################################################
# 5. Configure dnsmasq (DHCP + DNS + Captive Portal)
################################################################################
log_info "Configuring dnsmasq..."

# Backup original dnsmasq.conf
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig 2>/dev/null || true

copy_system_file "etc/dnsmasq.conf" "/etc/dnsmasq.conf"

log_success "dnsmasq configured"

################################################################################
# 6. Configure static IP for AP mode (wlan0-ap.service)
################################################################################
log_info "Creating wlan0-ap service for static IP..."

copy_system_file "etc/systemd/system/wlan0-ap.service" "/etc/systemd/system/wlan0-ap.service"

log_success "wlan0-ap service created"

################################################################################
# 7. Create Recovery Mode script
################################################################################
log_info "Creating recovery mode script..."

copy_system_file "usr/local/bin/oakhz-recovery-mode" "/usr/local/bin/oakhz-recovery-mode"

chmod +x /usr/local/bin/oakhz-recovery-mode

log_success "Recovery mode script created"

################################################################################
# 8. Create Recovery Mode systemd service
################################################################################
log_info "Creating recovery mode service..."

copy_system_file "etc/systemd/system/oakhz-recovery-mode.service" "/etc/systemd/system/oakhz-recovery-mode.service"

log_success "Recovery mode service created"

################################################################################
# 9. Disable NetworkManager (only for recovery mode)
################################################################################
log_info "Disabling NetworkManager (will only start in recovery mode)..."

systemctl disable NetworkManager 2>/dev/null || true
systemctl stop NetworkManager 2>/dev/null || true

log_success "NetworkManager disabled"

################################################################################
# 10. Enable and start services
################################################################################
log_info "Enabling services..."

systemctl daemon-reload
systemctl unmask hostapd 2>/dev/null || true
systemctl unmask dnsmasq 2>/dev/null || true

systemctl enable wlan0-ap.service
systemctl enable hostapd.service
systemctl enable dnsmasq.service
systemctl enable oakhz-recovery-mode.service

log_success "Services enabled"

################################################################################
# 11. Note about Captive Portal integration
################################################################################
echo ""
log_info "Captive Portal Configuration:"
echo ""
echo "  The Flask server (oakhz-equalizer) needs this route for captive portal:"
echo ""
echo "  @app.route('/<path:path>')"
echo "  def captive_portal_redirect(path):"
echo '      return redirect("http://192.168.50.1/", code=302)'
echo ""
echo "  This should already be configured in eq_server.py"
echo ""

################################################################################
# 12. Summary and instructions
################################################################################
echo ""
echo "═══════════════════════════════════════════════════════════════"
log_success "WiFi Access Point setup completed!"
echo ""
log_info "Configuration summary:"
echo "  • Mode: Permanent Access Point (100%)"
echo "  • SSID: $AP_SSID"
echo "  • Password: $AP_PASSWORD"
echo "  • IP Address: $AP_IP"
echo "  • Web Interface: http://$AP_IP"
echo "  • Captive Portal: Enabled (auto-opens browser)"
echo ""
log_info "Recovery Mode (Emergency WiFi Client Access):"
echo "  1. Power off device"
echo "  2. Remove SD card and insert into PC"
echo "  3. Create file: /boot/firmware/enable-wifi-client"
echo "  4. Reinsert SD card and boot"
echo "  5. Device will connect to saved WiFi networks via NetworkManager"
echo "  6. Access via home network IP (check router)"
echo "  7. To return to AP mode: sudo rm /boot/firmware/enable-wifi-client && sudo reboot"
echo ""
log_warning "IMPORTANT: Reboot required to activate Access Point"
echo ""
log_info "After reboot:"
echo "  1. Connect to WiFi: $AP_SSID (password: $AP_PASSWORD)"
echo "  2. Browser should auto-open to equalizer interface"
echo "  3. If not, navigate to: http://$AP_IP"
echo "  4. SSH access: ssh $MAIN_USER@$AP_IP"
echo ""
log_info "Useful commands:"
echo "  sudo systemctl status hostapd dnsmasq wlan0-ap"
echo "  sudo systemctl status oakhz-recovery-mode"
echo "  sudo journalctl -u hostapd -f"
echo "  ip addr show wlan0  # Should show $AP_IP"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

read -p "Reboot now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Rebooting in 3 seconds..."
    sleep 3
    reboot
else
    log_warning "Please reboot manually: sudo reboot"
fi
