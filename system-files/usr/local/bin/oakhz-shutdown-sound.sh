#!/bin/bash
# Play shutdown sound directly via ALSA (bypass PulseAudio)
# Stop CamillaDSP first to release the DAC
# Uses pre-adjusted 25% volume WAV file

# Stop CamillaDSP to release the HiFiBerry DAC
systemctl stop camilladsp.service 2>/dev/null

# Small delay to ensure DAC is released
sleep 0.2

# Play directly to HiFiBerry DAC using plughw for automatic rate conversion
# Volume is pre-adjusted to 25% in the WAV file
aplay -D plughw:1,0 /opt/oakhz/sounds/shutdown.wav 2>/dev/null

# Wait for playback to complete
sleep 1
