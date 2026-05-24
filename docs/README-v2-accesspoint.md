# OaKhz Audio v2 - WiFi Access Point with Captive Portal

Permanent WiFi Access Point with captive portal for easy access to the equalizer interface. Emergency WiFi client access via a file-based recovery mode.

-- Written with Claude AI

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Recovery Mode (Emergency WiFi Client)](#recovery-mode-emergency-wifi-client)
- [Troubleshooting](#troubleshooting)

---

## Overview

This system provides a **permanent WiFi Access Point** with captive portal for easy access to the CamillaDSP equalizer web interface:

- **Always accessible**: Permanent AP mode by default
- **Captive portal**: Browser auto-opens on connection
- **Recovery mode**: Emergency WiFi client access via SD card flag file
- **SSH always accessible**: In both modes

### How does it work?

```
On Raspberry Pi boot
           ↓
  oakhz-recovery-mode.service
  (checks /boot/firmware/enable-wifi-client)
           ↓
   ┌───────────────────────────┐
   │  File absent? → AP Mode   │  (default)
   │  File present? → Client   │  (recovery)
   └───────────────────────────┘
```

In **AP mode** (default):
- `wlan0` gets static IP `192.168.50.1`
- `hostapd` creates WiFi network "OaKhz Wifi"
- `dnsmasq` handles DHCP + DNS + captive portal redirect

In **Recovery mode**:
- AP services are stopped
- NetworkManager connects to saved WiFi networks
- Access via home network IP (check your router)

---

## Features

### Operating Modes

| Mode | WiFi | IP Address | Equalizer Access | SSH Access |
| ---- | ---- | ---------- | ---------------- | ---------- |
| **Access Point** (default) | Creates "OaKhz Wifi" network | `192.168.50.1` | `http://192.168.50.1` | `ssh user@192.168.50.1` |
| **Client** (recovery) | Connected to home network | DHCP (e.g. 192.168.1.x) | `http://[IP]` | `ssh user@[IP]` |

### Captive Portal

- **Automatic browser opening** when connecting to WiFi
- **DNS redirection**: All domain names point to the device
- **HTTP redirection**: All web requests redirect to equalizer interface (`http://192.168.50.1`)
- **Seamless experience**: No need to type IP address

### Default Configuration

| Parameter | Value |
| --------- | ----- |
| **AP SSID** | OaKhz Wifi |
| **AP Password** | oakhzwifi |
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
│  1. oakhz-recovery-mode.service → Check recovery file   │
│  2. wlan0-ap.service → Configure static IP              │
│  3. hostapd.service → Start Access Point                │
│  4. dnsmasq.service → Start DHCP + DNS (captive portal) │
│  5. oakhz-equalizer.service → Start web interface       │
└─────────────────────────────────────────────────────────┘
```

### Services

| Service | Role | Auto-start |
| ------- | ---- | ---------- |
| **oakhz-recovery-mode** | Check recovery flag file, optionally start NetworkManager | Yes (runs before AP services) |
| **wlan0-ap** | Configure static IP `192.168.50.1` on wlan0 | Yes |
| **hostapd** | Access Point creation | Yes |
| **dnsmasq** | DHCP + DNS + Captive portal | Yes |
| **oakhz-equalizer** | Flask web server + equalizer | Yes |
| **NetworkManager** | WiFi client connection | No (started by recovery mode only) |

---

## Installation

### Prerequisites

- Base system installed (see [README-v2-install.md](./README-v2-install.md))
- WiFi interface functional (`wlan0`)
- Raspberry Pi OS

### Quick Installation

```bash
cd /path/to/OAKHZ_DOC
sudo bash scripts/setup-accesspoint.sh
```

The script will prompt for confirmation, then install everything.

### What Gets Installed

1. **Dependencies** (via apt):
   - `hostapd`: Access Point creation
   - `dnsmasq`: DHCP + DNS + Captive portal

2. **Configurations** (from `system-files/`):
   - `/etc/hostapd/hostapd.conf`: AP configuration
   - `/etc/dnsmasq.conf`: DHCP/DNS + captive portal
   - Existing configs are backed up automatically

3. **Scripts**:
   - `/usr/local/bin/oakhz-recovery-mode`: Recovery mode handler

4. **Services**:
   - `/etc/systemd/system/wlan0-ap.service`: Static IP configuration
   - `/etc/systemd/system/oakhz-recovery-mode.service`: Recovery mode checker
   - `hostapd.service`: Access Point (enabled at boot)
   - `dnsmasq.service`: DHCP + DNS (enabled at boot)
   - `NetworkManager.service`: WiFi client (**disabled** at boot)

### Post-Installation

```bash
sudo reboot
```

---

## Configuration

### Change AP Password

Edit `/etc/hostapd/hostapd.conf`:

```
wpa_passphrase=YourNewPassword
```

Then restart:

```bash
sudo systemctl restart hostapd
```

### Change AP SSID

Edit `/etc/hostapd/hostapd.conf`:

```
ssid=YourNewSSID
```

Then restart:

```bash
sudo systemctl restart hostapd
```

### Change AP IP

Multiple files must be updated consistently:

**1. wlan0-ap service** — `/etc/systemd/system/wlan0-ap.service`:
```
ExecStart=/sbin/ip addr add 192.168.60.1/24 dev wlan0
```

**2. dnsmasq** — `/etc/dnsmasq.conf`:
```
dhcp-range=192.168.60.10,192.168.60.50,12h
address=/oakhz.local/192.168.60.1
address=/#/192.168.60.1
```

Then reload:

```bash
sudo systemctl daemon-reload
sudo systemctl restart wlan0-ap hostapd dnsmasq
```

---

## Usage

### Default Usage (AP Mode)

1. **On boot**: The Pi starts in Access Point mode automatically
2. **On your smartphone/PC**:
   - Open WiFi settings
   - Connect to `OaKhz Wifi` — password: `oakhzwifi`
   - Captive portal: your browser should automatically open the equalizer
   - If not, open any website (e.g., `google.com`) and you'll be redirected
3. **Direct access**: `http://192.168.50.1`
4. **SSH**: `ssh oakhz@192.168.50.1`

---

## Recovery Mode (Emergency WiFi Client)

When the AP is unreachable and you need to connect the device to your home WiFi network.

### Activate Recovery Mode

1. Power off the device
2. Remove the SD card and insert it into a PC
3. Create an empty file at the root of the boot partition:
   ```
   /boot/firmware/enable-wifi-client
   ```
   On Linux/Mac: `touch /media/boot/enable-wifi-client`  
   On Windows: create an empty file named `enable-wifi-client` (no extension) in the boot drive
4. Reinsert the SD card and boot
5. The device will stop AP services and start NetworkManager
6. Connect to your home router to find the assigned IP, then access:
   - Equalizer: `http://[home-network-IP]`
   - SSH: `ssh oakhz@[home-network-IP]`

### Return to AP Mode

```bash
# SSH into the device via home network
ssh oakhz@[home-network-IP]

# Remove the recovery flag file and reboot
sudo rm /boot/firmware/enable-wifi-client
sudo reboot
```
