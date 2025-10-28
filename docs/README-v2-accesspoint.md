# 📡 OaKhz Audio v2 - WiFi Access Point with Captive Portal

Permanent WiFi Access Point with captive portal for easy access to the equalizer interface. Optional manual switching to WiFi client mode for home network connection.

-- Written with Claude AI

---

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Advanced Configuration](#advanced-configuration)
- [Technical Details](#technical-details)

---

## Overview

This system provides a **permanent WiFi Access Point** with captive portal for easy access to the CamillaDSP equalizer web interface:

- ✅ **Always accessible**: Permanent AP mode by default
- ✅ **Captive portal**: Browser auto-opens on connection
- ✅ **Home WiFi option**: Manual switch to client mode when needed
- ✅ **SSH always accessible**: In both modes
- ✅ **Simple management**: Single command to switch modes

### How does it work?

```
On Raspberry Pi boot
           ↓
    Starts in AP Mode
           ↓
   ┌──────────────┐
   │   AP MODE    │
   │ (Default)    │
   └──────────────┘
           │
           ▼
   Access via captive portal
   http://192.168.50.1

Manual switch available:
   oakhz-wifi-mode client  → WiFi Client
   oakhz-wifi-mode ap      → Access Point
```

---

## Features

### 🌐 Operating Modes

| Mode | WiFi | IP Address | Equalizer Access | SSH Access |
|------|------|------------|-----------------|-----------|
| **Access Point** (default) | Creates "OaKhzWifi" network | 192.168.50.1 | `http://192.168.50.1` | `ssh user@192.168.50.1` |
| **Client** (manual) | Connected to home network | DHCP (e.g. 192.168.1.x) | `http://[IP]` | `ssh user@[IP]` |

### ⚡ Captive Portal

- **Automatic browser opening** when connecting to WiFi
- **DNS redirection**: All domain names point to the device
- **HTTP redirection**: All web requests redirect to equalizer interface
- **Seamless experience**: No need to type IP address

### 🔄 Manual Mode Switching

- **Simple command**: `oakhz-wifi-mode {ap|client|status}`
- **NetworkManager integration**: Automatic connection to saved WiFi networks
- **Persistent**: Mode survives until manually changed
- **No downtime**: Clean transition between modes

### 🔒 Security

- **WiFi Password**: WPA2 protection on Access Point
- **Local DNS**: Resolution `oakhz.local` → `192.168.50.1`
- **Captive Portal**: Automatic redirection to equalizer
- **Integrated DHCP**: Automatic IP assignment to clients (10-50)

### 🎯 Default Configuration

| Parameter | Value |
|-----------|--------|
| **AP SSID** | OaKhzWifi |
| **AP Password** | oakhz |
| **AP IP** | 192.168.50.1 |
| **DHCP Range** | 192.168.50.10 - 192.168.50.50 |
| **WiFi Channel** | 6 |
| **Default Mode** | Access Point |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Boot Sequence                          │
├─────────────────────────────────────────────────────────┤
│  1. wlan0-ap.service → Configure static IP              │
│  2. hostapd.service → Start Access Point                │
│  3. dnsmasq.service → Start DHCP + DNS (captive portal) │
│  4. oakhz-equalizer.service → Start web interface       │
└─────────────────────────────────────────────────────────┘
             │
             ▼
    ┌────────────────┐
    │    AP MODE     │
    │   (Default)    │
    ├────────────────┤
    │ hostapd        │
    │ dnsmasq        │
    │ Static IP      │
    │ Captive portal │
    └────────────────┘
             │
             ▼
   ┌──────────────────┐
   │ wlan0 Interface  │
   │  192.168.50.1    │
   └──────────────────┘

Manual switch via oakhz-wifi-mode:
    ┌────────────────┐
    │  CLIENT MODE   │
    ├────────────────┤
    │ NetworkManager │
    │ Dynamic IP     │
    └────────────────┘
```

### Involved Services

| Service | Role | Auto-start |
|---------|------|------------|
| **wlan0-ap** | Configure static IP for AP | Yes (before hostapd) |
| **hostapd** | Access Point creation | Yes |
| **dnsmasq** | DHCP + DNS Server + Captive portal | Yes |
| **oakhz-equalizer** | Flask web server + equalizer | Yes |
| **NetworkManager** | WiFi client connection | No (manual via script) |

---

## Installation

### Prerequisites

- **Base system installed** (see [README-v2-install.md](./README-v2-install.md))
- **WiFi interface** functional (wlan0)
- **Raspberry Pi OS** with NetworkManager or dhcpcd

### Quick Installation

```bash
cd /path/to/OAKHZ_DOC
sudo bash scripts/setup-accesspoint.sh
```

### Guided Installation

The script will ask for confirmation:

```
═══════════════════════════════════════════════════════════════
  OaKhz Audio - WiFi Access Point Fallback Setup
═══════════════════════════════════════════════════════════════

ℹ Configuration:
  • AP SSID: OaKhz-Config
  • AP Password: oakhz
  • AP IP Address: 192.168.50.1
  • DHCP Range: 192.168.50.10 - 192.168.50.50
  • WiFi Interface: wlan0
  • Web Equalizer: http://192.168.50.1

Continue with installation? (y/n)
```

### What Gets Installed

1. **Dependencies:**
   - `hostapd`: Access Point creation
   - `dnsmasq`: DHCP + DNS Server + Captive portal

2. **Configurations:**
   - `/etc/hostapd/hostapd.conf`: AP configuration
   - `/etc/dnsmasq.conf`: DHCP/DNS + captive portal configuration
   - `/opt/oakhz/eq_server.py`: Flask catch-all route for captive portal
   - Automatic backups of existing configs

3. **Scripts:**
   - `/usr/local/bin/oakhz-wifi-mode`: Manual mode switcher script

4. **Services:**
   - `/etc/systemd/system/wlan0-ap.service`: Static IP configuration
   - `hostapd.service`: Access Point (enabled at boot)
   - `dnsmasq.service`: DHCP + DNS (enabled at boot)
   - `NetworkManager.service`: WiFi client (disabled at boot)

### Post-Installation

```bash
# Reboot to activate
sudo reboot
```

---

## Configuration

### Configure Home WiFi (for Client Mode)

NetworkManager will automatically connect to saved WiFi networks when you switch to client mode.

**To add a WiFi network:**
```bash
# Switch to client mode
oakhz-wifi-mode client

# NetworkManager will connect to saved networks automatically
# Or use nmcli to add a new network:
sudo nmcli dev wifi connect "YourSSID" password "YourPassword"
```

**To return to AP mode:**
```bash
oakhz-wifi-mode ap
```

### Change AP Password

```bash
sudo nano /etc/hostapd/hostapd.conf
```

Modify:
```
wpa_passphrase=YourNewPassword
```

Restart hostapd:
```bash
sudo systemctl restart hostapd
```

### Change AP SSID

```bash
sudo nano /etc/hostapd/hostapd.conf
```

Modify:
```
ssid=YourNewSSID
```

Restart hostapd:
```bash
sudo systemctl restart hostapd
```

### Change AP IP

⚠️ **Warning**: Multiple files to modify

**1. wlan0-ap service:**
```bash
sudo nano /etc/systemd/system/wlan0-ap.service
```

Modify:
```
ExecStart=/sbin/ip addr add 192.168.60.1/24 dev wlan0
```

**2. dnsmasq:**
```bash
sudo nano /etc/dnsmasq.conf
```

Modify:
```
dhcp-range=192.168.60.10,192.168.60.50,12h
address=/oakhz.local/192.168.60.1
address=/#/192.168.60.1
```

**3. Mode switcher script:**
```bash
sudo nano /usr/local/bin/oakhz-wifi-mode
```

Modify the AP section with the new IP.

Restart services:
```bash
sudo systemctl daemon-reload
sudo systemctl restart wlan0-ap hostapd dnsmasq
```

---

## Usage

### Default Usage (AP Mode)

1. **On boot**: The Pi starts in Access Point mode
2. **On your smartphone/PC**:
   - Open WiFi settings
   - Connect to `OaKhzWifi`
   - Password: `oakhz`
   - **Captive portal**: Your browser should automatically open the equalizer interface
   - If not, open any website (e.g., `google.com`) and you'll be redirected
3. **Access the equalizer**: `http://192.168.50.1`
4. **SSH**: `ssh oakhz@192.168.50.1`

### Switch to Client Mode (Home WiFi)

When you want to connect the device to your home WiFi network:

```bash
# SSH into the device (via AP mode first)
ssh oakhz@192.168.50.1

# Switch to client mode
oakhz-wifi-mode client
```

The device will:
1. Stop the Access Point
2. Start NetworkManager
3. Automatically connect to saved WiFi networks
4. Display the new IP address

**Access the equalizer on home WiFi:**
```bash
# Find the IP
hostname -I
# Or from another PC
ping oakhz.local

# Access equalizer
http://[home-network-IP]
```

### Return to AP Mode

```bash
# SSH into the device (via home network)
ssh oakhz@[home-network-IP]

# Switch back to AP mode
oakhz-wifi-mode ap
```

### Check Current Mode

```bash
# Display current WiFi mode and status
oakhz-wifi-mode status
```

Output example:
```
Current WiFi status:
Mode: Access Point (AP)
SSID: OaKhzWifi
IP: 192.168.50.1
```

or

```
Current WiFi status:
Mode: WiFi Client
wlan0: connected to YourHomeWiFi
```

### Manual Mode Control Commands

```bash
# Check status
oakhz-wifi-mode status

# Switch to WiFi client (connect to home network)
oakhz-wifi-mode client

# Switch to Access Point (captive portal)
oakhz-wifi-mode ap
```

### Monitor Services

```bash
# Check AP services
systemctl status hostapd dnsmasq

# Check NetworkManager (client mode)
systemctl status NetworkManager

# View logs
sudo journalctl -u hostapd -f
sudo journalctl -u dnsmasq -f
```

---

## Troubleshooting

### Pi Doesn't Start AP

**Check the service:**
```bash
sudo systemctl status oakhz-wifi-manager
```

**Check hostapd:**
```bash
sudo systemctl status hostapd
sudo journalctl -u hostapd -n 50
```

**Common issues:**

1. **"Failed to initialize interface"**
   - The wlan0 interface may be in use
   ```bash
   sudo systemctl stop wpa_supplicant
   sudo systemctl restart oakhz-wifi-manager
   ```

2. **"Could not configure driver mode"**
   - Conflict with NetworkManager
   ```bash
   sudo systemctl stop NetworkManager
   sudo systemctl disable NetworkManager
   sudo reboot
   ```

3. **"Channel X not allowed"**
   - Change the channel in `/etc/hostapd/hostapd.conf`
   ```bash
   sudo nano /etc/hostapd/hostapd.conf
   # Try channel=1 or channel=11
   ```

### Cannot Connect to Home WiFi

**Check wpa_supplicant:**
```bash
sudo wpa_cli -i wlan0 status
sudo wpa_cli -i wlan0 scan_results
sudo wpa_cli -i wlan0 list_networks
```

**Reconfigure WiFi:**
```bash
sudo wpa_cli -i wlan0 reconfigure
```

**Check logs:**
```bash
sudo journalctl -u wpa_supplicant -n 50
```

**Test manually:**
```bash
sudo systemctl stop oakhz-wifi-manager
sudo systemctl start wpa_supplicant
sudo systemctl start dhcpcd
sudo wpa_cli -i wlan0 reconfigure
# Wait 10 seconds
iwgetid wlan0 -r
# Should display the SSID
```

### Equalizer Not Accessible

**In Client mode:**
```bash
# Check IP
hostname -I
# Test access
curl http://localhost
```

**In AP mode:**
```bash
# Check AP IP
ip addr show wlan0 | grep inet
# Should show 192.168.50.1

# Check equalizer service
sudo systemctl status oakhz-equalizer
```

**Firewall issue:**
```bash
# Check iptables
sudo iptables -L -n

# Allow port 80
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
```

### SSH Doesn't Work

**Check SSH is active:**
```bash
sudo systemctl status ssh
```

**Reactivate SSH:**
```bash
sudo systemctl enable ssh
sudo systemctl start ssh
```

**Check firewall:**
```bash
sudo iptables -L -n | grep 22
```

### Switching Doesn't Happen

**Check monitoring service:**
```bash
sudo systemctl status oakhz-wifi-manager
sudo journalctl -u oakhz-wifi-manager -n 100
```

**Test manually:**
```bash
# Disconnect from WiFi
sudo wpa_cli -i wlan0 disconnect

# Observe logs (wait ~2 minutes)
sudo journalctl -u oakhz-wifi-manager -f
```

**Restart service:**
```bash
sudo systemctl restart oakhz-wifi-manager
```

### DHCP Doesn't Distribute IPs

**Check dnsmasq:**
```bash
sudo systemctl status dnsmasq
sudo journalctl -u dnsmasq -n 50
```

**Test configuration:**
```bash
sudo dnsmasq --test
```

**Check leases:**
```bash
cat /var/lib/misc/dnsmasq.leases
```

**Restart dnsmasq:**
```bash
sudo systemctl restart dnsmasq
```

---

## Advanced Configuration

### Add Priority WiFi Networks

```bash
sudo nano /etc/wpa_supplicant/wpa_supplicant.conf
```

```
# High priority (home)
network={
    ssid="Home_WiFi"
    psk="password123"
    priority=10
}

# Medium priority (office)
network={
    ssid="Office_WiFi"
    psk="password456"
    priority=5
}

# Low priority (backup)
network={
    ssid="Backup_WiFi"
    psk="password789"
    priority=1
}
```

### Enable 5GHz Mode

⚠️ **Requires a Pi with 5GHz WiFi** (Pi 3B+, Pi 4, Pi Zero 2W does NOT support 5GHz)

```bash
sudo nano /etc/hostapd/hostapd.conf
```

Modify:
```
hw_mode=a
channel=36
ieee80211ac=1
```

### Limit DHCP Bandwidth

```bash
sudo nano /etc/dnsmasq.conf
```

Add:
```
# Limit to maximum 10 clients
dhcp-range=192.168.50.10,192.168.50.20,12h
```

### Add Complete Captive Portal

Install nginx:
```bash
sudo apt install nginx
```

Configure:
```bash
sudo nano /etc/nginx/sites-available/captive
```

```nginx
server {
    listen 80 default_server;
    server_name _;

    location / {
        return 302 http://192.168.50.1;
    }
}
```

Activate:
```bash
sudo ln -s /etc/nginx/sites-available/captive /etc/nginx/sites-enabled/
sudo systemctl restart nginx
```

### Advanced Logging

```bash
sudo nano /usr/local/bin/oakhz-wifi-manager.py
```

Modify:
```python
logging.basicConfig(
    level=logging.DEBUG,  # More details
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('/var/log/oakhz-wifi.log')
    ]
)
```

### Disable Automatic Switching

To stay in AP mode permanently:

```bash
sudo systemctl stop oakhz-wifi-manager
sudo systemctl disable oakhz-wifi-manager

# Start AP manually
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl start hostapd
sudo systemctl start dnsmasq
```

---

## Technical Details

### Connection Detection

The script uses several methods:

1. **iwgetid**: Checks connected SSID
```python
iwgetid wlan0 -r
```

2. **DNS Ping**: Checks Internet access
```python
ping -c 1 -W 2 8.8.8.8
```

3. **wpa_cli**: Lists saved networks
```python
wpa_cli -i wlan0 list_networks
```

### Switching Flow

```
Client Mode
    ↓
Check every 30s
    ↓
Connection lost?
    ↓
Attempt 1 (after 30s)
    ↓
Failed?
    ↓
Attempt 2 (after 60s)
    ↓
Failed?
    ↓
Attempt 3 (after 90s)
    ↓
Failed?
    ↓
Stop wpa_supplicant
Stop dhcpcd
    ↓
Flush IP wlan0
    ↓
Configure static IP (192.168.50.1/24)
    ↓
Start hostapd
Start dnsmasq
    ↓
AP Mode active
```

### Performance

| Metric | Value |
|----------|--------|
| **Client → AP switching time** | ~10 seconds |
| **AP → Client switching time** | ~15 seconds |
| **CPU usage (monitoring)** | ~0.1% |
| **RAM usage** | ~15 MB |
| **Check interval** | 30 seconds |

### WPA2 Security

hostapd configuration:
```
auth_algs=1           # Open authentication
wpa=2                 # WPA2 only
wpa_key_mgmt=WPA-PSK  # Pre-Shared Key
wpa_pairwise=CCMP     # AES encryption
rsn_pairwise=CCMP     # Robust Security Network
```

### Local DNS

dnsmasq automatically resolves:
```
oakhz.local → 192.168.50.1
```

Allows using `http://oakhz.local` instead of the IP.

---

## Uninstall

```bash
# Stop services
sudo systemctl stop oakhz-wifi-manager
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq

# Disable services
sudo systemctl disable oakhz-wifi-manager
sudo systemctl disable hostapd
sudo systemctl disable dnsmasq

# Remove service file
sudo rm /etc/systemd/system/oakhz-wifi-manager.service

# Remove script
sudo rm /usr/local/bin/oakhz-wifi-manager.py

# Restore backups
sudo mv /etc/hostapd/hostapd.conf.backup /etc/hostapd/hostapd.conf 2>/dev/null || true
sudo mv /etc/dnsmasq.conf.backup /etc/dnsmasq.conf 2>/dev/null || true
sudo mv /etc/dhcpcd.conf.backup /etc/dhcpcd.conf 2>/dev/null || true

# Reload systemd
sudo systemctl daemon-reload

# Restart networking
sudo systemctl restart dhcpcd
sudo systemctl restart wpa_supplicant

# Reboot
sudo reboot
```

---

## Related Documentation

- [Base System Installation](./README-v2-install.md)
- [Sound Feedback System](./README-v2-sound.md)
- [Rotary Encoder Control](./README-v2-rotary.md)

---

*OaKhz Audio v2 - WiFi Access Point Fallback*
*October 2025*
