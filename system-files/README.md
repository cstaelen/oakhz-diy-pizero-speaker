# System Files Directory

This directory contains all configuration files and scripts that are installed by the OaKhz Audio installation scripts.

Instead of embedding these files directly in the shell scripts using `cat > file << EOF`, they are stored here as separate files for better maintainability.

## Directory Structure

```
system-files/
├── etc/                           # Files to be copied to /etc
│   ├── asound.conf               # ALSA configuration
│   ├── bluetooth/
│   │   └── main.conf             # Bluetooth configuration
│   ├── dnsmasq.conf              # DNSMASQ DHCP/DNS configuration
│   ├── hostapd/
│   │   └── hostapd.conf          # WiFi Access Point configuration
│   ├── modules-load.d/
│   │   └── oakhz-audio.conf      # Kernel modules to load at boot
│   ├── sudoers.d/
│   │   └── oakhz-camilladsp      # Sudo permissions for CamillaDSP
│   └── systemd/
│       ├── system.conf           # systemd configuration
│       └── system/               # systemd services
│           ├── *.service         # Service files
│           └── *.service.d/      # Service drop-in overrides
│               └── *.conf
│
├── opt/                          # Files to be copied to /opt
│   ├── camilladsp/
│   │   └── config.yml            # CamillaDSP configuration
│   └── oakhz/
│       ├── eq_server.py          # Flask equalizer server
│       └── templates/
│           └── index.html        # Web interface
│
└── usr/                          # Files to be copied to /usr
    └── local/
        └── bin/                  # Executable scripts
            ├── oakhz-audio-events.py
            ├── oakhz-recovery-mode
            ├── oakhz-rotary.py
            └── oakhz-shutdown-sound.sh
```