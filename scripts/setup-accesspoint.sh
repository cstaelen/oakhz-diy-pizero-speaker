#!/bin/bash

################################################################################
# OaKhz Audio v2 - WiFi Access Point Fallback Setup
################################################################################
# This script installs:
# 1. hostapd (WiFi Access Point)
# 2. dnsmasq (DHCP + DNS server)
# 3. WiFi manager (automatic client/AP switching)
# 4. Systemd service for monitoring
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

# Configuration variables
AP_SSID="OaKhz Wifi"
AP_PASSWORD="oakhz"
AP_IP="192.168.50.1"
AP_DHCP_START="192.168.50.10"
AP_DHCP_END="192.168.50.50"
AP_CHANNEL="6"
WIFI_INTERFACE="wlan0"
FLASK_PORT="80"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  OaKhz Audio - WiFi Access Point Fallback Setup"
echo "═══════════════════════════════════════════════════════════════"
echo ""
log_info "Configuration:"
echo "  • AP SSID: $AP_SSID"
echo "  • AP Password: $AP_PASSWORD"
echo "  • AP IP Address: $AP_IP"
echo "  • DHCP Range: $AP_DHCP_START - $AP_DHCP_END"
echo "  • WiFi Interface: $WIFI_INTERFACE"
echo "  • Web Equalizer: http://$AP_IP"
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
apt-get install -y hostapd dnsmasq iptables python3 dhcpcd5

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

if [ -f /etc/dhcpcd.conf ]; then
    cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup
    log_warning "Existing dhcpcd.conf backed up"
fi

log_success "Backups created"

################################################################################
# 4. Configure hostapd (Access Point)
################################################################################
log_info "Configuring hostapd..."

cat > /etc/hostapd/hostapd.conf << EOF
# OaKhz Audio - WiFi Access Point Configuration
interface=$WIFI_INTERFACE
driver=nl80211

# Network configuration
ssid=$AP_SSID
hw_mode=g
channel=$AP_CHANNEL
ieee80211n=1
wmm_enabled=1

# Authentication
auth_algs=1
wpa=2
wpa_passphrase=$AP_PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP

# Logging
logger_syslog=-1
logger_syslog_level=2
EOF

chmod 600 /etc/hostapd/hostapd.conf

# Update hostapd default config
sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd 2>/dev/null || true

log_success "hostapd configured"

################################################################################
# 5. Configure dnsmasq (DHCP + DNS)
################################################################################
log_info "Configuring dnsmasq..."

# Backup original dnsmasq.conf
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig 2>/dev/null || true

cat > /etc/dnsmasq.conf << EOF
# OaKhz Audio - DHCP/DNS Configuration
interface=$WIFI_INTERFACE
bind-interfaces

# DHCP range
dhcp-range=$AP_DHCP_START,$AP_DHCP_END,12h

# DNS
domain=oakhz.local
address=/oakhz.local/$AP_IP

# Logging
log-queries
log-dhcp
EOF

log_success "dnsmasq configured"

################################################################################
# 6. Configure static IP for AP mode
################################################################################
log_info "Configuring static IP for AP mode..."

# Add static IP configuration to dhcpcd.conf if not already present
if ! grep -q "# OaKhz AP static IP" /etc/dhcpcd.conf; then
    cat >> /etc/dhcpcd.conf << EOF

# OaKhz AP static IP (managed by oakhz-wifi-manager)
# This will be activated only in AP mode
EOF
    log_success "Static IP configuration added"
else
    log_warning "Static IP configuration already present"
fi

################################################################################
# 7. Create WiFi manager script
################################################################################
log_info "Creating WiFi manager script..."

cat > /usr/local/bin/oakhz-wifi-manager.py << 'EOFPY'
#!/usr/bin/env python3
"""
OaKhz WiFi Manager
Automatically switches between WiFi client and Access Point modes
"""

import subprocess
import time
import os
import sys
import logging

# Configuration
WIFI_INTERFACE = "wlan0"
AP_IP = "192.168.50.1"
CHECK_INTERVAL = 30  # seconds
MAX_RETRIES = 3

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [wifi-manager] %(levelname)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

class WiFiMode:
    CLIENT = "client"
    AP = "ap"

class WiFiManager:
    def __init__(self):
        self.current_mode = None
        self.retry_count = 0

    def run_command(self, cmd, check=False):
        """Run shell command and return output"""
        try:
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=30
            )
            if check and result.returncode != 0:
                logging.error(f"Command failed: {cmd}")
                logging.error(f"Error: {result.stderr}")
            return result.stdout.strip(), result.returncode
        except subprocess.TimeoutExpired:
            logging.error(f"Command timeout: {cmd}")
            return "", 1
        except Exception as e:
            logging.error(f"Command error: {e}")
            return "", 1

    def is_wifi_connected(self):
        """Check if connected to a WiFi network"""
        output, code = self.run_command(f"iwgetid {WIFI_INTERFACE} -r")
        if code == 0 and output:
            logging.debug(f"Connected to WiFi: {output}")
            return True
        return False

    def has_internet(self):
        """Check if we have internet connectivity"""
        # Try to reach common DNS servers
        for host in ["8.8.8.8", "1.1.1.1"]:
            output, code = self.run_command(f"ping -c 1 -W 2 {host} > /dev/null 2>&1")
            if code == 0:
                logging.debug("Internet connectivity confirmed")
                return True
        return False

    def get_saved_networks(self):
        """Check if there are saved WiFi networks"""
        output, code = self.run_command("wpa_cli -i wlan0 list_networks 2>/dev/null | tail -n +2")
        if code == 0 and output:
            networks = [line.split('\t')[1] for line in output.split('\n') if line]
            logging.debug(f"Found {len(networks)} saved networks")
            return len(networks) > 0
        return False

    def start_ap_mode(self):
        """Start Access Point mode"""
        logging.info("Starting Access Point mode...")

        # Stop services
        self.run_command("systemctl stop wpa_supplicant")
        self.run_command("systemctl stop dhcpcd")
        time.sleep(1)

        # Configure static IP
        self.run_command(f"ip addr flush dev {WIFI_INTERFACE}")
        self.run_command(f"ip addr add {AP_IP}/24 dev {WIFI_INTERFACE}")
        self.run_command(f"ip link set {WIFI_INTERFACE} up")

        # Start hostapd and dnsmasq
        self.run_command("systemctl start hostapd")
        self.run_command("systemctl start dnsmasq")

        time.sleep(2)

        # Verify AP is running
        output, code = self.run_command("systemctl is-active hostapd")
        if code == 0 and output == "active":
            self.current_mode = WiFiMode.AP
            logging.info(f"✓ Access Point started: SSID={self.get_ap_ssid()}")
            logging.info(f"✓ Web interface: http://{AP_IP}")
            logging.info(f"✓ SSH access: ssh <user>@{AP_IP}")
            return True
        else:
            logging.error("Failed to start Access Point")
            return False

    def start_client_mode(self):
        """Start WiFi Client mode"""
        logging.info("Starting WiFi Client mode...")

        # Stop AP services
        self.run_command("systemctl stop hostapd")
        self.run_command("systemctl stop dnsmasq")
        time.sleep(1)

        # Flush IP
        self.run_command(f"ip addr flush dev {WIFI_INTERFACE}")

        # Start dhcpcd and wpa_supplicant
        self.run_command("systemctl start wpa_supplicant")
        self.run_command("systemctl start dhcpcd")

        time.sleep(5)

        # Try to connect
        self.run_command("wpa_cli -i wlan0 reconfigure")
        time.sleep(5)

        # Verify connection
        if self.is_wifi_connected():
            ip_output, _ = self.run_command(f"ip -4 addr show {WIFI_INTERFACE} | grep inet")
            ip_addr = ip_output.split()[1].split('/')[0] if ip_output else "unknown"
            self.current_mode = WiFiMode.CLIENT
            logging.info(f"✓ Connected to WiFi network")
            logging.info(f"✓ IP Address: {ip_addr}")
            logging.info(f"✓ Web interface: http://{ip_addr}")
            logging.info(f"✓ SSH access: ssh <user>@{ip_addr}")
            self.retry_count = 0
            return True
        else:
            logging.warning("Failed to connect to WiFi")
            self.retry_count += 1
            return False

    def get_ap_ssid(self):
        """Get AP SSID from config"""
        try:
            with open('/etc/hostapd/hostapd.conf', 'r') as f:
                for line in f:
                    if line.startswith('ssid='):
                        return line.split('=', 1)[1].strip()
        except:
            pass
        return "OaKhz-Config"

    def monitor(self):
        """Main monitoring loop"""
        logging.info("WiFi Manager started")

        # Initial state check
        time.sleep(10)  # Wait for system to settle

        while True:
            try:
                if self.current_mode == WiFiMode.CLIENT or self.current_mode is None:
                    # Client mode: check if still connected
                    if self.is_wifi_connected():
                        if self.current_mode is None:
                            logging.info("Already connected to WiFi")
                            self.current_mode = WiFiMode.CLIENT
                    else:
                        logging.warning("WiFi connection lost")

                        # Try to reconnect
                        if self.retry_count < MAX_RETRIES:
                            logging.info(f"Attempting reconnection ({self.retry_count + 1}/{MAX_RETRIES})...")
                            if not self.start_client_mode():
                                if self.retry_count >= MAX_RETRIES:
                                    logging.warning("Max retries reached, switching to AP mode")
                                    self.start_ap_mode()
                        else:
                            # Switch to AP mode
                            self.start_ap_mode()

                elif self.current_mode == WiFiMode.AP:
                    # AP mode: check if home WiFi is available
                    if self.get_saved_networks():
                        logging.info("Checking if home WiFi is available...")

                        # Temporarily try client mode
                        if self.start_client_mode():
                            logging.info("Successfully connected to home WiFi")
                        else:
                            # Revert to AP mode
                            logging.info("Home WiFi not available, staying in AP mode")
                            self.start_ap_mode()

                time.sleep(CHECK_INTERVAL)

            except KeyboardInterrupt:
                logging.info("Shutting down...")
                break
            except Exception as e:
                logging.error(f"Error in monitor loop: {e}")
                time.sleep(10)

def main():
    # Check if running as root
    if os.geteuid() != 0:
        logging.error("This script must be run as root")
        sys.exit(1)

    manager = WiFiManager()
    manager.monitor()

if __name__ == "__main__":
    main()
EOFPY

chmod +x /usr/local/bin/oakhz-wifi-manager.py

log_success "WiFi manager script created"

################################################################################
# 8. Create systemd service
################################################################################
log_info "Creating systemd service..."

cat > /etc/systemd/system/oakhz-wifi-manager.service << EOF
[Unit]
Description=OaKhz WiFi Manager (Client/AP Fallback)
After=network.target wpa_supplicant.service dhcpcd.service
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/oakhz-wifi-manager.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

log_success "Systemd service created"

################################################################################
# 9. Disable auto-start of conflicting services
################################################################################
log_info "Configuring service startup..."

# Let the manager handle these services
systemctl unmask hostapd 2>/dev/null || true
systemctl unmask dnsmasq 2>/dev/null || true

# Don't auto-start them at boot
systemctl disable hostapd 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true

log_success "Service startup configured"

################################################################################
# 10. Enable WiFi manager service
################################################################################
log_info "Enabling WiFi manager service..."

systemctl daemon-reload
systemctl enable oakhz-wifi-manager.service

log_success "WiFi manager service enabled"

################################################################################
# 11. Add WiFi management to Flask interface
################################################################################
log_info "Adding WiFi management interface to Flask..."

# Create WiFi management Python module
cat > /opt/oakhz/wifi_manager_routes.py << 'EOFWIFI'
#!/usr/bin/env python3
"""
WiFi Management Routes for OaKhz Equalizer
Adds WiFi configuration interface to the Flask app
"""

import subprocess
import re
from flask import jsonify, request, render_template

def add_wifi_routes(app):
    """Add WiFi management routes to Flask app"""

    @app.route('/wifi')
    def wifi_page():
        """WiFi management page"""
        return render_template('wifi.html')

    @app.route('/api/wifi/scan', methods=['GET'])
    def wifi_scan():
        """Scan for available WiFi networks"""
        try:
            # Scan for networks
            result = subprocess.run(
                ['sudo', 'iwlist', 'wlan0', 'scan'],
                capture_output=True,
                text=True,
                timeout=10
            )

            networks = []
            current_network = {}

            for line in result.stdout.split('\n'):
                line = line.strip()

                # New cell = new network
                if 'Cell' in line and 'Address' in line:
                    if current_network:
                        networks.append(current_network)
                    current_network = {}

                # SSID
                elif 'ESSID:' in line:
                    essid = re.search(r'ESSID:"(.*?)"', line)
                    if essid:
                        current_network['ssid'] = essid.group(1)

                # Signal quality
                elif 'Quality=' in line:
                    quality = re.search(r'Quality=(\d+)/(\d+)', line)
                    if quality:
                        q = int(quality.group(1))
                        max_q = int(quality.group(2))
                        current_network['quality'] = int((q / max_q) * 100)

                # Encryption
                elif 'Encryption key:' in line:
                    if 'on' in line:
                        current_network['encrypted'] = True
                    else:
                        current_network['encrypted'] = False

                # WPA/WPA2
                elif 'WPA' in line or 'WPA2' in line:
                    current_network['encryption_type'] = 'WPA/WPA2'

            # Add last network
            if current_network and 'ssid' in current_network:
                networks.append(current_network)

            # Remove duplicates and sort by quality
            seen = set()
            unique_networks = []
            for net in networks:
                if net.get('ssid') and net['ssid'] not in seen:
                    seen.add(net['ssid'])
                    unique_networks.append(net)

            unique_networks.sort(key=lambda x: x.get('quality', 0), reverse=True)

            return jsonify({'networks': unique_networks})

        except subprocess.TimeoutExpired:
            return jsonify({'error': 'Scan timeout'}), 500
        except Exception as e:
            return jsonify({'error': str(e)}), 500

    @app.route('/api/wifi/current', methods=['GET'])
    def wifi_current():
        """Get current WiFi connection status"""
        try:
            # Get current SSID
            result = subprocess.run(
                ['iwgetid', 'wlan0', '-r'],
                capture_output=True,
                text=True
            )
            ssid = result.stdout.strip()

            # Get IP address
            result_ip = subprocess.run(
                ['ip', '-4', 'addr', 'show', 'wlan0'],
                capture_output=True,
                text=True
            )

            ip_match = re.search(r'inet (\d+\.\d+\.\d+\.\d+)', result_ip.stdout)
            ip = ip_match.group(1) if ip_match else None

            # Get signal strength
            result_signal = subprocess.run(
                ['iwconfig', 'wlan0'],
                capture_output=True,
                text=True
            )

            signal_match = re.search(r'Signal level=(-?\d+)', result_signal.stdout)
            signal = signal_match.group(1) if signal_match else None

            # Check mode (AP or Client)
            mode = 'ap' if ip == '192.168.50.1' else 'client'

            return jsonify({
                'connected': bool(ssid),
                'ssid': ssid if ssid else None,
                'ip': ip,
                'signal': signal,
                'mode': mode
            })

        except Exception as e:
            return jsonify({'error': str(e)}), 500

    @app.route('/api/wifi/saved', methods=['GET'])
    def wifi_saved():
        """Get list of saved WiFi networks"""
        try:
            result = subprocess.run(
                ['sudo', 'wpa_cli', '-i', 'wlan0', 'list_networks'],
                capture_output=True,
                text=True
            )

            networks = []
            for line in result.stdout.split('\n')[1:]:  # Skip header
                if line.strip():
                    parts = line.split('\t')
                    if len(parts) >= 2:
                        networks.append({
                            'id': parts[0],
                            'ssid': parts[1],
                            'current': '[CURRENT]' in line
                        })

            return jsonify({'networks': networks})

        except Exception as e:
            return jsonify({'error': str(e)}), 500

    @app.route('/api/wifi/connect', methods=['POST'])
    def wifi_connect():
        """Connect to a WiFi network"""
        try:
            data = request.json
            ssid = data.get('ssid')
            password = data.get('password')

            if not ssid:
                return jsonify({'error': 'SSID required'}), 400

            # Add network to wpa_supplicant
            if password:
                # Network with password
                result = subprocess.run(
                    ['sudo', 'wpa_passphrase', ssid, password],
                    capture_output=True,
                    text=True
                )
                network_config = result.stdout
            else:
                # Open network
                network_config = f'''network={{
    ssid="{ssid}"
    key_mgmt=NONE
}}
'''

            # Append to wpa_supplicant.conf
            with open('/tmp/network_to_add.conf', 'w') as f:
                f.write(network_config)

            subprocess.run(
                ['sudo', 'bash', '-c', 'cat /tmp/network_to_add.conf >> /etc/wpa_supplicant/wpa_supplicant.conf'],
                check=True
            )

            # Reconfigure wpa_supplicant
            subprocess.run(
                ['sudo', 'wpa_cli', '-i', 'wlan0', 'reconfigure'],
                check=True
            )

            # Clean up
            subprocess.run(['sudo', 'rm', '/tmp/network_to_add.conf'])

            return jsonify({'status': 'success', 'message': 'Network added. Connecting...'})

        except Exception as e:
            return jsonify({'error': str(e)}), 500

    @app.route('/api/wifi/forget/<network_id>', methods=['DELETE'])
    def wifi_forget(network_id):
        """Forget a saved WiFi network"""
        try:
            # Remove network
            subprocess.run(
                ['sudo', 'wpa_cli', '-i', 'wlan0', 'remove_network', network_id],
                check=True
            )

            # Save config
            subprocess.run(
                ['sudo', 'wpa_cli', '-i', 'wlan0', 'save_config'],
                check=True
            )

            return jsonify({'status': 'success', 'message': 'Network forgotten'})

        except Exception as e:
            return jsonify({'error': str(e)}), 500

    @app.route('/api/wifi/mode', methods=['GET'])
    def wifi_mode():
        """Get current WiFi mode (AP or Client)"""
        try:
            # Check if hostapd is running
            result = subprocess.run(
                ['systemctl', 'is-active', 'hostapd'],
                capture_output=True,
                text=True
            )

            mode = 'ap' if result.returncode == 0 else 'client'

            return jsonify({'mode': mode})

        except Exception as e:
            return jsonify({'error': str(e)}), 500

EOFWIFI

chmod 644 /opt/oakhz/wifi_manager_routes.py

# Modify eq_server.py to import WiFi routes
log_info "Integrating WiFi routes into eq_server.py..."

# Add import and route integration before app.run()
sed -i '/if __name__ == .__main__.:/ i\
# Import WiFi management routes\
try:\
    from wifi_manager_routes import add_wifi_routes\
    add_wifi_routes(app)\
    logger.info("WiFi management interface enabled")\
except Exception as e:\
    logger.warning(f"WiFi management not available: {e}")\
' /opt/oakhz/eq_server.py

log_success "WiFi management routes added"

# Create WiFi management HTML template
log_info "Creating WiFi management interface..."

cat > /opt/oakhz/templates/wifi.html << 'EOFHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OaKhz Audio - WiFi Settings</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            background: linear-gradient(135deg, #2d2520 0%, #3d3530 50%, #2d2520 100%);
            color: #f5f0e8;
            min-height: 100vh;
            padding: 20px;
        }
        .container { max-width: 800px; margin: 0 auto; }
        header { text-align: center; margin-bottom: 30px; }
        h1 {
            font-size: 2rem;
            background: linear-gradient(135deg, #d4a574 0%, #c89860 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            margin-bottom: 10px;
        }
        .nav { display: flex; gap: 10px; justify-content: center; margin-bottom: 20px; }
        .nav a {
            padding: 10px 20px;
            background: rgba(80, 65, 55, 0.4);
            border: 1px solid #6b5848;
            border-radius: 8px;
            color: #f5f0e8;
            text-decoration: none;
            transition: all 0.2s;
        }
        .nav a:hover { background: rgba(100, 85, 75, 0.6); }
        .card {
            background: rgba(80, 65, 55, 0.4);
            backdrop-filter: blur(10px);
            border: 1px solid #6b5848;
            border-radius: 16px;
            padding: 24px;
            margin-bottom: 24px;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.4);
        }
        .card-title {
            font-size: 1.3rem;
            font-weight: 600;
            margin-bottom: 16px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .status {
            padding: 8px 16px;
            border-radius: 6px;
            font-size: 0.9rem;
            display: inline-block;
        }
        .status.connected { background: #2d5016; color: #7dd156; }
        .status.disconnected { background: #5a3030; color: #ff6b6b; }
        .status.ap-mode { background: #4a4a2d; color: #f0d956; }
        .info-grid {
            display: grid;
            grid-template-columns: 120px 1fr;
            gap: 12px;
            margin-top: 16px;
        }
        .info-label { color: #b8a894; font-size: 0.9rem; }
        .info-value { color: #f5f0e8; font-weight: 500; }
        .btn {
            padding: 10px 20px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 0.9rem;
            font-weight: 500;
            transition: all 0.2s;
            background: #8b6f47;
            color: #f5f0e8;
        }
        .btn:hover { background: #a58556; }
        .btn-scan { background: #6b8b47; }
        .btn-scan:hover { background: #85a556; }
        .btn-danger { background: #8b4747; }
        .btn-danger:hover { background: #a55656; }
        .network-list {
            display: flex;
            flex-direction: column;
            gap: 8px;
            margin-top: 16px;
        }
        .network-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px;
            background: rgba(60, 50, 40, 0.6);
            border: 1px solid #6b5848;
            border-radius: 8px;
            transition: all 0.2s;
        }
        .network-item:hover { background: rgba(80, 65, 55, 0.6); }
        .network-info { display: flex; align-items: center; gap: 12px; flex: 1; }
        .network-name { font-weight: 500; font-size: 1rem; }
        .network-meta {
            display: flex;
            gap: 12px;
            font-size: 0.85rem;
            color: #b8a894;
        }
        .signal-bar {
            display: flex;
            gap: 2px;
            align-items: flex-end;
        }
        .signal-bar span {
            width: 4px;
            background: #6b5848;
            border-radius: 2px;
        }
        .signal-bar.excellent span { background: #7dd156; }
        .signal-bar.good span { background: #f0d956; }
        .signal-bar.fair span { background: #ffa556; }
        .signal-bar.poor span { background: #ff6b6b; }
        .modal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.8);
            z-index: 1000;
            align-items: center;
            justify-content: center;
        }
        .modal.active { display: flex; }
        .modal-content {
            background: #2d2520;
            border: 2px solid #6b5848;
            border-radius: 16px;
            padding: 32px;
            max-width: 400px;
            width: 90%;
        }
        .modal-title { font-size: 1.5rem; margin-bottom: 20px; }
        .form-group { margin-bottom: 16px; }
        .form-group label {
            display: block;
            margin-bottom: 8px;
            color: #b8a894;
            font-size: 0.9rem;
        }
        .form-group input {
            width: 100%;
            padding: 10px;
            background: rgba(60, 50, 40, 0.6);
            border: 1px solid #6b5848;
            border-radius: 8px;
            color: #f5f0e8;
            font-size: 1rem;
        }
        .form-group input:focus {
            outline: none;
            border-color: #c89860;
        }
        .modal-actions {
            display: flex;
            gap: 10px;
            margin-top: 24px;
        }
        .modal-actions button { flex: 1; }
        .loading {
            display: inline-block;
            width: 16px;
            height: 16px;
            border: 2px solid #6b5848;
            border-top-color: #c89860;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>📡 WiFi Settings</h1>
            <div class="nav">
                <a href="/">🎵 Equalizer</a>
                <a href="/wifi">📡 WiFi</a>
            </div>
        </header>

        <!-- Current Connection Status -->
        <div class="card">
            <div class="card-title">
                Current Connection
                <span class="status" id="statusBadge">Checking...</span>
            </div>
            <div class="info-grid" id="currentInfo">
                <span class="info-label">Mode:</span>
                <span class="info-value" id="modeValue">-</span>
                <span class="info-label">Network:</span>
                <span class="info-value" id="ssidValue">-</span>
                <span class="info-label">IP Address:</span>
                <span class="info-value" id="ipValue">-</span>
                <span class="info-label">Signal:</span>
                <span class="info-value" id="signalValue">-</span>
            </div>
        </div>

        <!-- Available Networks -->
        <div class="card">
            <div class="card-title" style="justify-content: space-between;">
                <span>Available Networks</span>
                <button class="btn btn-scan" onclick="scanNetworks()">
                    <span id="scanBtn">🔍 Scan</span>
                </button>
            </div>
            <div class="network-list" id="networkList">
                <p style="color: #b8a894;">Click "Scan" to find networks</p>
            </div>
        </div>

        <!-- Saved Networks -->
        <div class="card">
            <div class="card-title">Saved Networks</div>
            <div class="network-list" id="savedList">
                <p style="color: #b8a894;">Loading...</p>
            </div>
        </div>
    </div>

    <!-- Connect Modal -->
    <div class="modal" id="connectModal">
        <div class="modal-content">
            <div class="modal-title">Connect to Network</div>
            <div class="form-group">
                <label>Network Name (SSID)</label>
                <input type="text" id="modalSSID" readonly>
            </div>
            <div class="form-group">
                <label>Password</label>
                <input type="password" id="modalPassword" placeholder="Enter password">
            </div>
            <div class="modal-actions">
                <button class="btn" onclick="closeModal()">Cancel</button>
                <button class="btn btn-scan" onclick="connectToNetwork()">Connect</button>
            </div>
        </div>
    </div>

    <script>
        let selectedSSID = '';

        // Load current status
        async function loadStatus() {
            try {
                const res = await fetch('/api/wifi/current');
                const data = await res.json();

                const statusBadge = document.getElementById('statusBadge');
                if (data.mode === 'ap') {
                    statusBadge.textContent = 'Access Point Mode';
                    statusBadge.className = 'status ap-mode';
                } else if (data.connected) {
                    statusBadge.textContent = 'Connected';
                    statusBadge.className = 'status connected';
                } else {
                    statusBadge.textContent = 'Disconnected';
                    statusBadge.className = 'status disconnected';
                }

                document.getElementById('modeValue').textContent = data.mode === 'ap' ? 'Access Point' : 'Client';
                document.getElementById('ssidValue').textContent = data.ssid || '-';
                document.getElementById('ipValue').textContent = data.ip || '-';
                document.getElementById('signalValue').textContent = data.signal ? `${data.signal} dBm` : '-';
            } catch (e) {
                console.error('Status error:', e);
            }
        }

        // Scan for networks
        async function scanNetworks() {
            const btn = document.getElementById('scanBtn');
            btn.innerHTML = '<span class="loading"></span> Scanning...';

            try {
                const res = await fetch('/api/wifi/scan');
                const data = await res.json();

                const list = document.getElementById('networkList');
                list.innerHTML = '';

                if (data.networks && data.networks.length > 0) {
                    data.networks.forEach(net => {
                        const item = document.createElement('div');
                        item.className = 'network-item';

                        let signalClass = 'poor';
                        if (net.quality > 75) signalClass = 'excellent';
                        else if (net.quality > 50) signalClass = 'good';
                        else if (net.quality > 25) signalClass = 'fair';

                        item.innerHTML = `
                            <div class="network-info">
                                <div class="signal-bar ${signalClass}">
                                    <span style="height: 8px"></span>
                                    <span style="height: 12px"></span>
                                    <span style="height: 16px"></span>
                                    <span style="height: 20px"></span>
                                </div>
                                <div>
                                    <div class="network-name">${net.ssid}</div>
                                    <div class="network-meta">
                                        <span>${net.encrypted ? '🔒 Secured' : '🔓 Open'}</span>
                                        <span>${net.quality}%</span>
                                    </div>
                                </div>
                            </div>
                            <button class="btn" onclick="showConnectModal('${net.ssid}', ${net.encrypted})">Connect</button>
                        `;
                        list.appendChild(item);
                    });
                } else {
                    list.innerHTML = '<p style="color: #b8a894;">No networks found</p>';
                }
            } catch (e) {
                console.error('Scan error:', e);
                document.getElementById('networkList').innerHTML = '<p style="color: #ff6b6b;">Scan failed</p>';
            } finally {
                btn.innerHTML = '🔍 Scan';
            }
        }

        // Load saved networks
        async function loadSaved() {
            try {
                const res = await fetch('/api/wifi/saved');
                const data = await res.json();

                const list = document.getElementById('savedList');
                list.innerHTML = '';

                if (data.networks && data.networks.length > 0) {
                    data.networks.forEach(net => {
                        const item = document.createElement('div');
                        item.className = 'network-item';
                        item.innerHTML = `
                            <div class="network-info">
                                <div class="network-name">${net.ssid} ${net.current ? '(Current)' : ''}</div>
                            </div>
                            <button class="btn btn-danger" onclick="forgetNetwork('${net.id}', '${net.ssid}')">Forget</button>
                        `;
                        list.appendChild(item);
                    });
                } else {
                    list.innerHTML = '<p style="color: #b8a894;">No saved networks</p>';
                }
            } catch (e) {
                console.error('Load saved error:', e);
            }
        }

        function showConnectModal(ssid, encrypted) {
            selectedSSID = ssid;
            document.getElementById('modalSSID').value = ssid;
            document.getElementById('modalPassword').value = '';
            document.getElementById('modalPassword').required = encrypted;
            document.getElementById('connectModal').classList.add('active');
        }

        function closeModal() {
            document.getElementById('connectModal').classList.remove('active');
        }

        async function connectToNetwork() {
            const password = document.getElementById('modalPassword').value;

            try {
                const res = await fetch('/api/wifi/connect', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({ssid: selectedSSID, password})
                });

                const data = await res.json();

                if (res.ok) {
                    alert('Network added! Connecting...');
                    closeModal();
                    setTimeout(() => {
                        loadStatus();
                        loadSaved();
                    }, 5000);
                } else {
                    alert('Error: ' + (data.error || 'Connection failed'));
                }
            } catch (e) {
                alert('Error: ' + e.message);
            }
        }

        async function forgetNetwork(id, ssid) {
            if (!confirm(`Forget network "${ssid}"?`)) return;

            try {
                const res = await fetch(`/api/wifi/forget/${id}`, {method: 'DELETE'});
                if (res.ok) {
                    loadSaved();
                    loadStatus();
                } else {
                    alert('Error forgetting network');
                }
            } catch (e) {
                alert('Error: ' + e.message);
            }
        }

        // Initial load
        loadStatus();
        loadSaved();
        setInterval(loadStatus, 10000);
    </script>
</body>
</html>
EOFHTML

log_success "WiFi management interface created"

# Add sudo permissions for WiFi management commands
log_info "Configuring sudo permissions for WiFi management..."

cat > /etc/sudoers.d/oakhz-wifi << EOF
$MAIN_USER ALL=(ALL) NOPASSWD: /usr/sbin/iwlist wlan0 scan
$MAIN_USER ALL=(ALL) NOPASSWD: /usr/sbin/wpa_cli -i wlan0 *
$MAIN_USER ALL=(ALL) NOPASSWD: /usr/bin/wpa_passphrase * *
$MAIN_USER ALL=(ALL) NOPASSWD: /bin/bash -c cat /tmp/network_to_add.conf >> /etc/wpa_supplicant/wpa_supplicant.conf
$MAIN_USER ALL=(ALL) NOPASSWD: /bin/rm /tmp/network_to_add.conf
EOF

chmod 440 /etc/sudoers.d/oakhz-wifi

log_success "Sudo permissions configured"

################################################################################
# 12. Create web portal redirect (optional)
################################################################################
log_info "Creating captive portal redirect..."

mkdir -p /var/www/html

cat > /var/www/html/index.html << 'EOFHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="0; url=http://192.168.50.1">
    <title>OaKhz Audio - Redirecting...</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            background: linear-gradient(135deg, #2d2520 0%, #3d3530 100%);
            color: #f5f0e8;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
        }
        .container {
            text-align: center;
            padding: 40px;
            background: rgba(80, 65, 55, 0.4);
            border-radius: 16px;
            border: 1px solid #6b5848;
        }
        h1 {
            font-size: 2rem;
            margin-bottom: 20px;
        }
        p {
            font-size: 1.2rem;
            color: #b8a894;
        }
        a {
            color: #d4a574;
            text-decoration: none;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎵 OaKhz Audio</h1>
        <p>Redirecting to equalizer...</p>
        <p><a href="http://192.168.50.1">Click here if not redirected</a></p>
    </div>
</body>
</html>
EOFHTML

log_success "Captive portal redirect created"

################################################################################
# 12. Summary and instructions
################################################################################
echo ""
echo "═══════════════════════════════════════════════════════════════"
log_success "WiFi Access Point Fallback setup completed!"
echo ""
log_info "Configuration summary:"
echo "  • Access Point SSID: $AP_SSID"
echo "  • Access Point Password: $AP_PASSWORD"
echo "  • Access Point IP: $AP_IP"
echo "  • Equalizer (AP mode): http://$AP_IP"
echo "  • Equalizer (Client mode): http://[home-network-ip]"
echo ""
log_warning "IMPORTANT: Reboot required to activate WiFi manager"
echo ""
log_info "After reboot, the system will:"
echo "  1. Try to connect to your home WiFi (if configured)"
echo "  2. If no home WiFi available → Start Access Point mode"
echo "  3. Monitor connection and switch modes automatically"
echo ""
log_info "How to configure home WiFi:"
echo "  sudo raspi-config"
echo "  → System Options → Wireless LAN"
echo "  → Enter SSID and password"
echo ""
log_info "Useful commands:"
echo "  sudo systemctl status oakhz-wifi-manager"
echo "  sudo journalctl -u oakhz-wifi-manager -f"
echo "  sudo systemctl restart oakhz-wifi-manager"
echo ""
log_info "To connect in AP mode:"
echo "  1. Connect to WiFi: $AP_SSID"
echo "  2. Password: $AP_PASSWORD"
echo "  3. Open browser: http://$AP_IP"
echo "  4. SSH access: ssh $MAIN_USER@$AP_IP"
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
