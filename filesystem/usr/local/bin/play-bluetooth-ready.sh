#!/bin/bash

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

HELLO_SOUND="/usr/share/sounds/hello.mp3"
PAIR_SOUND="/usr/share/sounds/pair.mp3"

# Check if bluetooth is ready and pairable
wait_for_pairable() {
    for i in {1..300}; do
        if bluetoothctl show | grep -q "Powered: yes" &&
           bluetoothctl show | grep -q "Discoverable: yes" &&
           bluetoothctl show | grep -q "Pairable: yes"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Bluetooth start up
if wait_for_pairable; then
    echo "Bluetooth pairable"
    play --volume=0.10 "$HELLO_SOUND"
else
    echo "Bluetooth not pairable after 30s"
    exit 1
fi

# Main loop
paired_announced=false
stream_ready_announced=false

while true; do
    connected_devices=$(bluetoothctl devices Connected | wc -l)

    # Refused connection if a device is already paired
    if [ "$connected_devices" -gt 1 ]; then
	echo "A device is already connected. Disconnect others."
        bluetoothctl devices Connected | awk '{print $2}' | tail -n +2 | while read -r mac; do
            echo "Disconnect $mac"
            bluetoothctl disconnect "$mac"
        done
    fi

    if bluetoothctl info | grep -q "Paired: yes" && ! $paired_announced; then
        play --volume=0.05 "$PAIR_SOUND"
        paired_announced=true
    fi

    # Reset on disconnect
    if ! bluetoothctl info | grep -q "Connected: yes"; then
        paired_announced=false
        stream_ready_announced=false
    fi

    sleep 1
done