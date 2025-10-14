# 📡 OaKhz Audio v2 - WiFi Access Point Fallback

Système intelligent de basculement automatique entre WiFi client et Access Point pour accéder à l'égaliseur sans réseau domestique.

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

Ce système permet d'accéder à l'interface web de l'égaliseur CamillaDSP **dans toutes les situations** :

- ✅ **À la maison** : Connexion au réseau WiFi domestique (mode normal)
- ✅ **En déplacement** : Création automatique d'un Access Point WiFi
- ✅ **SSH toujours accessible** : Dans les deux modes
- ✅ **Basculement automatique** : Détection et changement de mode intelligent

### Comment ça marche ?

```
Au démarrage du Raspberry Pi
           ↓
   WiFi domestique disponible ?
           ↓
    ┌──────┴──────┐
    │             │
   OUI           NON
    │             │
    ▼             ▼
┌────────┐   ┌──────────┐
│ CLIENT │   │    AP    │
│  MODE  │   │   MODE   │
└────────┘   └──────────┘
    │             │
    ▼             ▼
Accès via      Accès via
IP locale      192.168.50.1
```

---

## Features

### 🌐 Modes de Fonctionnement

| Mode | WiFi | IP Address | Accès Égaliseur | Accès SSH |
|------|------|------------|-----------------|-----------|
| **Client** | Connecté au réseau domestique | DHCP (ex: 192.168.1.x) | `http://[IP]` | `ssh user@[IP]` |
| **Access Point** | Crée réseau "OaKhz-Config" | 192.168.50.1 | `http://192.168.50.1` | `ssh user@192.168.50.1` |

### ⚡ Basculement Automatique

- **Détection toutes les 30 secondes** de la connexion WiFi
- **3 tentatives de reconnexion** avant de basculer en mode AP
- **Retour automatique** au mode Client si le WiFi domestique redevient disponible
- **Pas de coupure SSH** : L'interface réseau reste active pendant le basculement

### 🔒 Sécurité

- **Mot de passe WiFi** : Protection WPA2 sur l'Access Point
- **DNS local** : Résolution `oakhz.local` → `192.168.50.1`
- **Portail captif** : Redirection automatique vers l'égaliseur
- **DHCP intégré** : Attribution automatique d'IPs aux clients (10-50)

### 🎯 Configuration par Défaut

| Paramètre | Valeur |
|-----------|--------|
| **SSID AP** | OaKhz-Config |
| **Mot de passe AP** | oakhz |
| **IP AP** | 192.168.50.1 |
| **Plage DHCP** | 192.168.50.10 - 192.168.50.50 |
| **Canal WiFi** | 6 |
| **Intervalle de vérification** | 30 secondes |

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

### Services Impliqués

| Service | Rôle | Mode |
|---------|------|------|
| **oakhz-wifi-manager** | Monitoring et basculement | Toujours actif |
| **wpa_supplicant** | Connexion WiFi client | CLIENT uniquement |
| **dhcpcd** | Client DHCP | CLIENT uniquement |
| **hostapd** | Création Access Point | AP uniquement |
| **dnsmasq** | Serveur DHCP + DNS | AP uniquement |

---

## Installation

### Prerequisites

- **Base system installed** (voir [README-v2-install.md](./README-v2-install.md))
- **Interface WiFi** fonctionnelle (wlan0)
- **Raspberry Pi OS** avec NetworkManager ou dhcpcd

### Installation Rapide

```bash
cd /path/to/OAKHZ_DOC
sudo bash scripts/setup-accesspoint.sh
```

### Installation Guidée

Le script vous demandera confirmation :

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

### Ce qui est Installé

1. **Dépendances :**
   - `hostapd` : Création d'Access Point
   - `dnsmasq` : Serveur DHCP + DNS
   - `dhcpcd5` : Client DHCP
   - `python3` : Script de monitoring

2. **Configurations :**
   - `/etc/hostapd/hostapd.conf` : Configuration AP
   - `/etc/dnsmasq.conf` : Configuration DHCP/DNS
   - `/etc/dhcpcd.conf` : Configuration IP statique
   - Backups automatiques des configs existantes

3. **Scripts :**
   - `/usr/local/bin/oakhz-wifi-manager.py` : Gestionnaire WiFi

4. **Services :**
   - `/etc/systemd/system/oakhz-wifi-manager.service`

5. **Portail Web :**
   - `/var/www/html/index.html` : Redirection vers égaliseur

### Post-Installation

```bash
# Redémarrer pour activer
sudo reboot
```

---

## Configuration

### Configurer le WiFi Domestique

**Méthode 1 : Via raspi-config**
```bash
sudo raspi-config
# → System Options
# → Wireless LAN
# → Enter SSID and password
```

**Méthode 2 : Via wpa_supplicant**
```bash
sudo nano /etc/wpa_supplicant/wpa_supplicant.conf
```

Ajouter :
```
network={
    ssid="Votre_WiFi"
    psk="Votre_Mot_De_Passe"
    key_mgmt=WPA-PSK
}
```

Redémarrer :
```bash
sudo systemctl restart oakhz-wifi-manager
```

### Changer le Mot de Passe de l'AP

```bash
sudo nano /etc/hostapd/hostapd.conf
```

Modifier :
```
wpa_passphrase=VotreNouveauMotDePasse
```

Redémarrer :
```bash
sudo systemctl restart oakhz-wifi-manager
```

### Changer le SSID de l'AP

```bash
sudo nano /etc/hostapd/hostapd.conf
```

Modifier :
```
ssid=VotreNouveauSSID
```

Redémarrer :
```bash
sudo systemctl restart oakhz-wifi-manager
```

### Changer l'IP de l'AP

⚠️ **Attention** : Plusieurs fichiers à modifier

**1. hostapd (pas nécessaire mais pour cohérence)**

**2. dnsmasq :**
```bash
sudo nano /etc/dnsmasq.conf
```

Modifier :
```
dhcp-range=192.168.60.10,192.168.60.50,12h
address=/oakhz.local/192.168.60.1
```

**3. Script Python :**
```bash
sudo nano /usr/local/bin/oakhz-wifi-manager.py
```

Modifier :
```python
AP_IP = "192.168.60.1"
AP_DHCP_START = "192.168.60.10"
AP_DHCP_END = "192.168.60.50"
```

**4. Portail web :**
```bash
sudo nano /var/www/html/index.html
```

Modifier toutes les occurrences de `192.168.50.1` → `192.168.60.1`

Redémarrer :
```bash
sudo systemctl restart oakhz-wifi-manager
```

### Changer l'Intervalle de Vérification

```bash
sudo nano /usr/local/bin/oakhz-wifi-manager.py
```

Modifier :
```python
# Default: 30 secondes
CHECK_INTERVAL = 30

# Change to 60 secondes :
CHECK_INTERVAL = 60
```

Redémarrer :
```bash
sudo systemctl restart oakhz-wifi-manager
```

### Changer le Nombre de Tentatives

```bash
sudo nano /usr/local/bin/oakhz-wifi-manager.py
```

Modifier :
```python
# Default: 3 tentatives
MAX_RETRIES = 3

# Change to 5 tentatives :
MAX_RETRIES = 5
```

Redémarrer :
```bash
sudo systemctl restart oakhz-wifi-manager
```

---

## Usage

### Scénario 1 : Utilisation à la Maison

1. **Au démarrage** : Le Pi se connecte automatiquement au WiFi domestique
2. **Trouver l'IP** :
   ```bash
   # Sur le Pi
   hostname -I
   # Ou depuis un autre PC sur le réseau
   ping oakhz.local
   ```
3. **Accéder à l'égaliseur** : `http://[IP]`
4. **SSH** : `ssh oakhz@[IP]`

### Scénario 2 : Utilisation en Déplacement

1. **Au démarrage** : Pas de WiFi domestique → Mode AP automatique
2. **Sur votre smartphone/PC** :
   - Ouvrir les réglages WiFi
   - Se connecter à `OaKhz-Config`
   - Mot de passe : `oakhz`
3. **Accéder à l'égaliseur** : `http://192.168.50.1`
4. **SSH** : `ssh oakhz@192.168.50.1`

### Scénario 3 : Perte du WiFi Domestique

1. **Pendant l'utilisation** : Coupure du WiFi domestique
2. **Après 30 secondes** : Détection de la perte de connexion
3. **Tentatives de reconnexion** : 3 essais espacés
4. **Basculement AP** : Si échec après 3 tentatives
5. **Notification dans les logs** :
   ```
   [wifi-manager] WARNING: WiFi connection lost
   [wifi-manager] INFO: Attempting reconnection (1/3)...
   [wifi-manager] WARNING: Max retries reached, switching to AP mode
   [wifi-manager] INFO: ✓ Access Point started: SSID=OaKhz-Config
   ```

### Scénario 4 : Retour du WiFi Domestique

1. **En mode AP** : Le Pi écoute périodiquement
2. **Toutes les 30 secondes** : Tentative de connexion au WiFi domestique
3. **Si succès** : Basculement automatique en mode Client
4. **Notification dans les logs** :
   ```
   [wifi-manager] INFO: Checking if home WiFi is available...
   [wifi-manager] INFO: Successfully connected to home WiFi
   [wifi-manager] INFO: ✓ IP Address: 192.168.1.42
   ```

### Forcer un Mode Manuellement

**Forcer le mode AP :**
```bash
sudo systemctl stop oakhz-wifi-manager
sudo systemctl stop wpa_supplicant
sudo systemctl stop dhcpcd
sudo ip addr add 192.168.50.1/24 dev wlan0
sudo systemctl start hostapd
sudo systemctl start dnsmasq
```

**Revenir en mode automatique :**
```bash
sudo systemctl restart oakhz-wifi-manager
```

### Vérifier le Mode Actuel

```bash
# Via les services
systemctl is-active hostapd
systemctl is-active wpa_supplicant

# Si hostapd actif → Mode AP
# Si wpa_supplicant actif → Mode Client

# Vérifier l'IP
ip addr show wlan0 | grep inet
# Si 192.168.50.1 → Mode AP
# Si autre IP → Mode Client
```

### Monitorer en Temps Réel

```bash
# Logs du WiFi manager
sudo journalctl -u oakhz-wifi-manager -f

# État des services
watch -n 2 'systemctl is-active hostapd wpa_supplicant dhcpcd dnsmasq'
```

---

## Troubleshooting

### Le Pi ne démarre pas l'AP

**Vérifier le service :**
```bash
sudo systemctl status oakhz-wifi-manager
```

**Vérifier hostapd :**
```bash
sudo systemctl status hostapd
sudo journalctl -u hostapd -n 50
```

**Problèmes courants :**

1. **"Failed to initialize interface"**
   - L'interface wlan0 est peut-être utilisée
   ```bash
   sudo systemctl stop wpa_supplicant
   sudo systemctl restart oakhz-wifi-manager
   ```

2. **"Could not configure driver mode"**
   - Conflit avec NetworkManager
   ```bash
   sudo systemctl stop NetworkManager
   sudo systemctl disable NetworkManager
   sudo reboot
   ```

3. **"Channel X not allowed"**
   - Changer le canal dans `/etc/hostapd/hostapd.conf`
   ```bash
   sudo nano /etc/hostapd/hostapd.conf
   # Essayer channel=1 ou channel=11
   ```

### Impossible de se Connecter au WiFi Domestique

**Vérifier wpa_supplicant :**
```bash
sudo wpa_cli -i wlan0 status
sudo wpa_cli -i wlan0 scan_results
sudo wpa_cli -i wlan0 list_networks
```

**Reconfigurer le WiFi :**
```bash
sudo wpa_cli -i wlan0 reconfigure
```

**Vérifier les logs :**
```bash
sudo journalctl -u wpa_supplicant -n 50
```

**Tester manuellement :**
```bash
sudo systemctl stop oakhz-wifi-manager
sudo systemctl start wpa_supplicant
sudo systemctl start dhcpcd
sudo wpa_cli -i wlan0 reconfigure
# Attendre 10 secondes
iwgetid wlan0 -r
# Devrait afficher le SSID
```

### L'Égaliseur n'est pas Accessible

**En mode Client :**
```bash
# Vérifier l'IP
hostname -I
# Tester l'accès
curl http://localhost
```

**En mode AP :**
```bash
# Vérifier l'IP de l'AP
ip addr show wlan0 | grep inet
# Devrait montrer 192.168.50.1

# Vérifier le service égaliseur
sudo systemctl status oakhz-equalizer
```

**Problème de firewall :**
```bash
# Vérifier iptables
sudo iptables -L -n

# Autoriser le port 80
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
```

### SSH ne Fonctionne pas

**Vérifier SSH est actif :**
```bash
sudo systemctl status ssh
```

**Réactiver SSH :**
```bash
sudo systemctl enable ssh
sudo systemctl start ssh
```

**Vérifier le firewall :**
```bash
sudo iptables -L -n | grep 22
```

### Basculement ne se Fait pas

**Vérifier le service de monitoring :**
```bash
sudo systemctl status oakhz-wifi-manager
sudo journalctl -u oakhz-wifi-manager -n 100
```

**Tester manuellement :**
```bash
# Déconnecter du WiFi
sudo wpa_cli -i wlan0 disconnect

# Observer les logs (attendre ~2 minutes)
sudo journalctl -u oakhz-wifi-manager -f
```

**Redémarrer le service :**
```bash
sudo systemctl restart oakhz-wifi-manager
```

### DHCP ne Distribue pas d'IPs

**Vérifier dnsmasq :**
```bash
sudo systemctl status dnsmasq
sudo journalctl -u dnsmasq -n 50
```

**Tester la configuration :**
```bash
sudo dnsmasq --test
```

**Vérifier les leases :**
```bash
cat /var/lib/misc/dnsmasq.leases
```

**Redémarrer dnsmasq :**
```bash
sudo systemctl restart dnsmasq
```

---

## Advanced Configuration

### Ajouter des Réseaux WiFi Prioritaires

```bash
sudo nano /etc/wpa_supplicant/wpa_supplicant.conf
```

```
# Priorité haute (maison)
network={
    ssid="WiFi_Maison"
    psk="password123"
    priority=10
}

# Priorité moyenne (bureau)
network={
    ssid="WiFi_Bureau"
    psk="password456"
    priority=5
}

# Priorité basse (backup)
network={
    ssid="WiFi_Backup"
    psk="password789"
    priority=1
}
```

### Activer le Mode 5GHz

⚠️ **Nécessite un Pi avec WiFi 5GHz** (Pi 3B+, Pi 4, Pi Zero 2W ne supporte PAS 5GHz)

```bash
sudo nano /etc/hostapd/hostapd.conf
```

Modifier :
```
hw_mode=a
channel=36
ieee80211ac=1
```

### Limiter la Bande Passante DHCP

```bash
sudo nano /etc/dnsmasq.conf
```

Ajouter :
```
# Limiter à 10 clients maximum
dhcp-range=192.168.50.10,192.168.50.20,12h
```

### Ajouter un Portail Captif Complet

Installer nginx :
```bash
sudo apt install nginx
```

Configurer :
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

Activer :
```bash
sudo ln -s /etc/nginx/sites-available/captive /etc/nginx/sites-enabled/
sudo systemctl restart nginx
```

### Logging Avancé

```bash
sudo nano /usr/local/bin/oakhz-wifi-manager.py
```

Modifier :
```python
logging.basicConfig(
    level=logging.DEBUG,  # Plus de détails
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('/var/log/oakhz-wifi.log')
    ]
)
```

### Désactiver le Basculement Automatique

Pour rester en mode AP en permanence :

```bash
sudo systemctl stop oakhz-wifi-manager
sudo systemctl disable oakhz-wifi-manager

# Démarrer AP manuellement
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl start hostapd
sudo systemctl start dnsmasq
```

---

## Technical Details

### Détection de Connexion

Le script utilise plusieurs méthodes :

1. **iwgetid** : Vérifie le SSID connecté
```python
iwgetid wlan0 -r
```

2. **Ping DNS** : Vérifie l'accès Internet
```python
ping -c 1 -W 2 8.8.8.8
```

3. **wpa_cli** : Liste les réseaux sauvegardés
```python
wpa_cli -i wlan0 list_networks
```

### Flux de Basculement

```
Client Mode
    ↓
Vérification toutes les 30s
    ↓
Connexion perdue ?
    ↓
Tentative 1 (après 30s)
    ↓
Échec ?
    ↓
Tentative 2 (après 60s)
    ↓
Échec ?
    ↓
Tentative 3 (après 90s)
    ↓
Échec ?
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
AP Mode actif
```

### Performance

| Métrique | Valeur |
|----------|--------|
| **Temps de basculement Client → AP** | ~10 secondes |
| **Temps de basculement AP → Client** | ~15 secondes |
| **CPU usage (monitoring)** | ~0.1% |
| **RAM usage** | ~15 MB |
| **Intervalle de vérification** | 30 secondes |

### Sécurité WPA2

Configuration hostapd :
```
auth_algs=1           # Open authentication
wpa=2                 # WPA2 only
wpa_key_mgmt=WPA-PSK  # Pre-Shared Key
wpa_pairwise=CCMP     # AES encryption
rsn_pairwise=CCMP     # Robust Security Network
```

### DNS Local

dnsmasq résout automatiquement :
```
oakhz.local → 192.168.50.1
```

Permet d'utiliser `http://oakhz.local` au lieu de l'IP.

---

## FAQ

### Q: Le basculement coupe-t-il le Bluetooth ?

**R:** Non ! Le Bluetooth est complètement indépendant du WiFi. Votre musique continue de jouer pendant le basculement.

### Q: Puis-je utiliser le Pi en mode AP en permanence ?

**R:** Oui, désactivez simplement le WiFi manager et activez hostapd en permanence.

### Q: Combien d'appareils peuvent se connecter à l'AP ?

**R:** Par défaut, jusqu'à 41 appareils (plage DHCP .10 à .50). Modifiable dans dnsmasq.conf.

### Q: Le mode AP consomme-t-il plus de batterie ?

**R:** Légèrement plus (~5-10%) car le Pi doit gérer les clients WiFi.

### Q: Puis-je changer le nom "OaKhz-Config" ?

**R:** Oui, modifiez le SSID dans `/etc/hostapd/hostapd.conf`.

### Q: Est-ce compatible avec tous les Raspberry Pi ?

**R:** Oui, tous les modèles avec WiFi intégré (Pi 3, 4, Zero W, Zero 2W).

### Q: Que se passe-t-il si je configure plusieurs réseaux WiFi ?

**R:** Le Pi essaie de se connecter au réseau avec la priorité la plus élevée disponible.

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

**OaKhz Audio v2 - WiFi Access Point Fallback**
*Accédez à votre égaliseur partout, tout le temps*
*October 2025*
