#!/bin/bash

CONFIG_DIR="/usr/share/camilladsp/configs"
PID_FILE="/run/camilladsp.pid"

if pgrep camilladsp > /dev/null; then
    sudo kill "$(cat "$PID_FILE")"
fi

# Vérifie quel fichier était utilisé
if grep -q "Loudness" /run/camilladsp.cmdline 2>/dev/null; then
    CONFIG="$CONFIG_DIR/OaKhz-Default.yml"
else
    CONFIG="$CONFIG_DIR/OaKhz-Loudness.yml"
fi

echo "Kill existing Camilla process"
pid=$(pgrep camilladsp)
kill "$pid"

echo "Switching to $CONFIG"
camilladsp  "$CONFIG" &
echo "$CONFIG" > /run/camilladsp.cmdline