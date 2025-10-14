# 📡 OaKhz Audio v2 - WiFi Access Point Fallback

Intelligent automatic switching system between WiFi client and Access Point to access the equalizer without a home network.

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

This system allows access to the CamillaDSP equalizer web interface **in all situations**:

- ✅ **At home**: Connection to home WiFi network (normal mode)
- ✅ **On the go**: Automatic WiFi Access Point creation
- ✅ **SSH always accessible**: In both modes
- ✅ **Automatic switching**: Smart detection and mode switching

### How does it work?

```
On Raspberry Pi boot
           ↓
   Home WiFi available?
           ↓
    ┌──────┴──────┐
    │             │
   YES           NO
    │             │
    ▼             ▼
┌────────┐   ┌──────────┐
│ CLIENT │   │    AP    │
│  MODE  │   │   MODE   │
└────────┘   └──────────┘
    │             │
    ▼             ▼
Access via     Access via
Local IP       192.168.50.1
```

---

## Features

### 🌐 Operating Modes

| Mode | WiFi | IP Address | Equalizer Access | SSH Access |
|------|------|------------|-----------------|-----------|
| **Client** | Connected to home network | DHCP (e.g. 192.168.1.x) | `http://[IP]` | `ssh user@[IP]` |
| **Access Point** | Creates "OaKhz-Config" network | 192.168.50.1 | `http://192.168.50.1` | `ssh user@192.168.50.1` |

### ⚡ Automatic Switching

- **Detection every 30 seconds** of WiFi connection
- **3 reconnection attempts** before switching to AP mode
- **Automatic return** to Client mode if home WiFi becomes available again
- **No SSH interruption**: Network interface remains active during switching

### 🔒 Security

- **WiFi Password**: WPA2 protection on Access Point
- **Local DNS**: Resolution `oakhz.local` → `192.168.50.1`
- **Captive Portal**: Automatic redirection to equalizer
- **Integrated DHCP**: Automatic IP assignment to clients (10-50)

### 🎯 Default Configuration

| Parameter | Value |
|-----------|--------|
| **AP SSID** | OaKhz-Config |
| **AP Password** | oakhz |
| **AP IP** | 192.168.50.1 |
| **DHCP Range** | 192.168.50.10 - 192.168.50.50 |
| **WiFi Channel** | 6 |
| **Check Interval** | 30 seconds |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              oakhz-wifi-manager.service                 │
│              (Python monitoring script)                 │
├─────────────────────────────────────────────────────────┤
│  • Monitors WiFi connection every 30s                   │
│  • Switches between CLIENT and AP modes                 │
│  • Retries connection (max 3 attempts)                  │
│  • Manages hostapd and dnsmasq services                 │
└────────────┬────────────────────────────┬───────────────┘
             │                            │
    ┌────────▼────────┐          ┌────────▼─────────┐
    │  CLIENT MODE    │          │    AP MODE       │
    ├─────────────────┤          ├──────────────────┤
    │ wpa_supplicant  │          │ hostapd          │
    │ dhcpcd          │          │ dnsmasq          │
    │ Dynamic IP      │          │ Static IP        │
    └────────┬────────┘          └────────┬─────────┘
             │                            │
             └────────────┬───────────────┘
                          │
             ┌────────────▼─────────────┐
             │      wlan0 Interface     │
             └──────────────────────────┘
```

### Involved Services

| Service | Role | Mode |
|---------|------|------|
| **oakhz-wifi-manager** | Monitoring and switching | Always active |
| **wpa_supplicant** | WiFi client connection | CLIENT only |
| **dhcpcd** | DHCP Client | CLIENT only |
| **hostapd** | Access Point creation | AP only |
| **dnsmasq** | DHCP + DNS Server | AP only |

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
   - `dnsmasq`: DHCP + DNS Server
   - `dhcpcd5`: DHCP Client
   - `python3`: Monitoring script

2. **Configurations:**
   - `/etc/hostapd/hostapd.conf`: AP configuration
   - `/etc/dnsmasq.conf`: DHCP/DNS configuration
   - `/etc/dhcpcd.conf`: Static IP configuration
   - Automatic backups of existing configs

3. **Scripts:**
   - `/usr/local/bin/oakhz-wifi-manager.py`: WiFi Manager

4. **Services:**
   - `/etc/systemd/system/oakhz-wifi-manager.service`

5. **Web Portal:**
   - `/var/www/html/index.html`: Redirection to equalizer

### Post-Installation

```bash
# Reboot to activate
sudo reboot
```

---

## Configuration

### Configure Home WiFi

**Method 1: Via raspi-config**
```bash
sudo raspi-config
# → System Options
# → Wireless LAN
# → Enter SSID and password
```

**Method 2: Via wpa_supplicant**
```bash
sudo nano /etc/wpa_supplicant/wpa_supplicant.conf
```

Add:
```
network={
    ssid="Your_WiFi"
    psk="Your_Password"
    key_mgmt=WPA-PSK
}
```

Restart:
```bash
sudo systemctl restart oakhz-wifi-manager
```

### Change AP Password

```bash
sudo nano /etc/hostapd/hostapd.conf
```

Modify:
```
wpa_passphrase=YourNewPassword
```

Restart:
```bash
sudo systemctl restart oakhz-wifi-manager
```

### Change AP SSID

```bash
sudo nano /etc/hostapd/hostapd.conf
```

Modify:
```
ssid=YourNewSSID
```

Restart:
```bash
sudo systemctl restart oakhz-wifi-manager
```

### Change AP IP

⚠️ **Warning**: Multiple files to modify

**1. hostapd (not necessary but for consistency)**

**2. dnsmasq:**
```bash
sudo nano /etc/dnsmasq.conf
```

Modify:
```
dhcp-range=192.168.60.10,192.168.60.50,12h
address=/oakhz.local/192.168.60.1
```

**3. Python Script:**
```bash
sudo nano /usr/local/bin/oakhz-wifi-manager.py
```

Modify:
```python
AP_IP = "192.168.60.1"
AP_DHCP_START = "192.168.60.10"
AP_DHCP_END = "192.168.60.50"
```

**4. Web portal:**
```bash
sudo nano /var/www/html/index.html
```

Modify all occurrences of `192.168.50.1` → `192.168.60.1`

Restart:
```bash
sudo systemctl restart oakhz-wifi-manager
```

### Change Check Interval

```bash
sudo nano /usr/local/bin/oakhz-wifi-manager.py
```

Modify:
```python
# Default: 30 seconds
CHECK_INTERVAL = 30

# Change to 60 seconds:
CHECK_INTERVAL = 60
```

Restart:
```bash
sudo systemctl restart oakhz-wifi-manager
```

### Change Number of Retries

```bash
sudo nano /usr/local/bin/oakhz-wifi-manager.py
```

Modify:
```python
# Default: 3 attempts
MAX_RETRIES = 3

# Change to 5 attempts:
MAX_RETRIES = 5
```

Restart:
```bash
sudo systemctl restart oakhz-wifi-manager
```

---

## Usage

### Scenario 1: Home Use

1. **On boot**: The Pi automatically connects to home WiFi
2. **Find the IP**:
   ```bash
   # On the Pi
   hostname -I
   # Or from another PC on the network
   ping oakhz.local
   ```
3. **Access the equalizer**: `http://[IP]`
4. **SSH**: `ssh oakhz@[IP]`

### Scenario 2: On the Go Use

1. **On boot**: No home WiFi → Automatic AP mode
2. **On your smartphone/PC**:
   - Open WiFi settings
   - Connect to `OaKhz-Config`
   - Password: `oakhz`
3. **Access the equalizer**: `http://192.168.50.1`
4. **SSH**: `ssh oakhz@192.168.50.1`

### Scenario 3: Loss of Home WiFi

1. **During use**: Home WiFi outage
2. **After 30 seconds**: Connection loss detected
3. **Reconnection attempts**: 3 spaced attempts
4. **AP switching**: If failed after 3 attempts
5. **Notification in logs**:
   ```
   [wifi-manager] WARNING: WiFi connection lost
   [wifi-manager] INFO: Attempting reconnection (1/3)...
   [wifi-manager] WARNING: Max retries reached, switching to AP mode
   [wifi-manager] INFO: ✓ Access Point started: SSID=OaKhz-Config
   ```

### Scenario 4: Home WiFi Returns

1. **In AP mode**: The Pi listens periodically
2. **Every 30 seconds**: Attempts to connect to home WiFi
3. **If successful**: Automatic switching to Client mode
4. **Notification in logs**:
   ```
   [wifi-manager] INFO: Checking if home WiFi is available...
   [wifi-manager] INFO: Successfully connected to home WiFi
   [wifi-manager] INFO: ✓ IP Address: 192.168.1.42
   ```

### Force a Mode Manually

**Force AP mode:**
```bash
sudo systemctl stop oakhz-wifi-manager
sudo systemctl stop wpa_supplicant
sudo systemctl stop dhcpcd
sudo ip addr add 192.168.50.1/24 dev wlan0
sudo systemctl start hostapd
sudo systemctl start dnsmasq
```

**Return to automatic mode:**
```bash
sudo systemctl restart oakhz-wifi-manager
```

### Check Current Mode

```bash
# Via services
systemctl is-active hostapd
systemctl is-active wpa_supplicant

# If hostapd active → AP Mode
# If wpa_supplicant active → Client Mode

# Check IP
ip addr show wlan0 | grep inet
# If 192.168.50.1 → AP Mode
# If other IP → Client Mode
```

### Monitor in Real-Time

```bash
# WiFi manager logs
sudo journalctl -u oakhz-wifi-manager -f

# Services status
watch -n 2 'systemctl is-active hostapd wpa_supplicant dhcpcd dnsmasq'
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
- [Fast Boot Optimization](./README-v2-fast-boot.md)

---

*OaKhz Audio v2 - WiFi Access Point Fallback*
*October 2025*
