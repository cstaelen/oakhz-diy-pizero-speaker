# Oakhz — Electronic wiring documentation

## Overview

The Oakhz speaker is a DIY Bluetooth portable speaker based on a Raspberry Pi Zero,
powered by a Seengreat Solar Energy Manager (18650 batteries), with a HiFiBerry MiniAmp
DAC/amplifier and CamillaDSP for audio processing.

---

## Components

| Component | Role |
|---|---|
| Seengreat Solar Energy Manager | Battery management, 5V output |
| 2x 18650 Li-ion batteries | Power source (1S parallel, 3.7V / 4.2V) |
| Raspberry Pi Zero | Main controller, Bluetooth, CamillaDSP |
| HiFiBerry MiniAmp | DAC + amplifier (I2S) |
| Rotary encoder | Volume control / playback / shutdown |
| DPDT ON-OFF-ON switch | 3-position power switch |
| 2x 80mm speakers | Audio output |

---

## Power wiring

### Seengreat charging board

The Seengreat onboard switch COM pin has been cut to disable it permanently.
The DPDT ON-OFF-ON switch replaces it entirely.

**Switch wiring (DPDT ON-OFF-ON, 6 pins):**

```
Switch pins layout:
A1  A2  A3
B1  B2  B3
```

| Switch pin | Connected to | Notes |
|---|---|---|
| A2 (COM) | Seengreat board COM pad | Seengreat control |
| A1 | Seengreat board ON pad | Position middle |
| A3 | Seengreat board ON pad | Position up (bridged with A1) |
| B2 (COM) | Seengreat 5V output | Pi Zero power source |
| B1 | nothing | Position down = Pi OFF |
| B3 | Pi Zero GPIO pin 2 or 4 (5V) | Position up = Pi ON |

**Switch positions:**

| Position | Seengreat | Pi Zero |
|---|---|---|
| Down (OFF) | OFF | OFF |
| Middle | ON | OFF |
| Up (ON) | ON | ON |

**Wire type:** Use copper hifi wire (≥22 AWG) for the Seengreat COM/ON circuit —
it carries the full system current (up to 2A peak).

### Pi Zero power supply

Power is supplied via GPIO header, not micro-USB (more reliable, avoids fragile connector).

| Pi Zero pin | Connected to |
|---|---|
| Pin 2 or 4 (5V) | Seengreat 5V output via switch B3 |
| Pin 6 (GND) | Seengreat GND output |

> **Warning:** No reverse polarity protection on GPIO power input — double check polarity before connecting.

### USB-C charging

The Seengreat USB-C charging port (connector ③ on the board) is extended to the side panel
via an encastered USB-C panel mount connector. Use a 5V/3A minimum charger.

---

## HiFiBerry MiniAmp GPIO wiring

The MiniAmp connects to the Pi Zero via GPIO header using dupont female-female cables.

| Pi Zero pin | GPIO | Signal | Notes |
|---|---|---|---|
| Pin 1 | 3.3V | Power | Logic supply |
| Pin 2 | 5V | Power | Amplifier supply |
| Pin 6 | GND | Ground | |
| Pin 12 | GPIO18 | I2S BCLK | Bit clock — mandatory |
| Pin 35 | GPIO19 | I2S LRCLK | Left/right clock — mandatory |
| Pin 37 | GPIO26 | Shutdown | Power stage enable — mandatory |
| Pin 38 | GPIO20 | I2S SDIN | Audio data — mandatory |
| Pin 40 | GPIO21 | I2S SCLK | System clock — mandatory |

> **Warning:** Pin 37 (GPIO26 shutdown) is required — without it the amplifier power stage
> stays in shutdown mode and no audio is output.

**Speaker wiring:** Use copper hifi wire between MiniAmp output terminals and the 80mm speakers.
Keep wires as short as possible and away from power supply cables to avoid noise.

---

## Rotary encoder GPIO wiring

The rotary encoder handles volume control, play/pause, next/previous track, and shutdown.

| Pi Zero pin | GPIO | Signal |
|---|---|---|
| Pin 15 | GPIO22 | Encoder A (CLK) |
| Pin 16 | GPIO23 | Encoder B (DT) |
| Pin 17 | 3.3V | Power |
| Pin 18 | GPIO24 | Encoder button (SW) |
| Pin 20 | GND | Ground |

---

## Battery level indicator

The battery level indicator connects directly to the Seengreat connector ⑲.

| Seengreat pin ⑲ | Connected to | Notes |
|---|---|---|
| VBAT | Indicator V+ | Battery voltage 3.7V–4.2V |
| GND | Indicator GND | |

Module spec: 1S Li-ion, 3.7V–4.2V, 4-level LED display (25/50/75/100%).
Module size: 5x9.5mm — fits flush in a small panel cutout.

---

## Charging status LEDs

Two LEDs mounted on the side panel indicate charging status from the Seengreat connector ⑲.

| LED | Seengreat pin | Resistor | Color | Meaning |
|---|---|---|---|---|
| CHRG | CHRG | 180Ω | Yellow | Charging in progress |
| DONE | DONE | 180Ω | Green | Battery full |

**Wiring:** VBAT → 180Ω resistor → LED anode → LED cathode → CHRG or DONE pin.

> CHRG and DONE are active low — the Seengreat pulls them to GND when active.
> Current flows from VBAT through the resistor and LED to the pin.

---

## Seengreat connector ⑲ pinout

```
GND | DONE | CHRG | VBAT | GND
```

---

## GPIO availability summary

| Pi Zero pin | GPIO | Used by | Available |
|---|---|---|---|
| 1 | 3.3V | HiFiBerry | No |
| 2 | 5V | HiFiBerry + Power | No |
| 6 | GND | HiFiBerry + Power | No |
| 12 | GPIO18 | HiFiBerry I2S | No |
| 15 | GPIO22 | Rotary encoder CLK | No |
| 16 | GPIO23 | Rotary encoder DT | No |
| 17 | 3.3V | Rotary encoder | No |
| 18 | GPIO24 | Rotary encoder SW | No |
| 20 | GND | Rotary encoder | No |
| 35 | GPIO19 | HiFiBerry I2S | No |
| 37 | GPIO26 | HiFiBerry shutdown | No |
| 38 | GPIO20 | HiFiBerry I2S | No |
| 40 | GPIO21 | HiFiBerry I2S | No |
| Others | — | — | Available |

---

## Cable types reference

| Connection | Wire type | Reason |
|---|---|---|
| Switch COM/ON → Seengreat | Copper hifi wire ≥22 AWG | Full system current |
| Seengreat 5V → Pi Zero GPIO | Flexible stranded wire 22-24 AWG | Fixed internal wiring |
| GPIO signal cables | Dupont female-female 20cm | Short distances, signal only |
| MiniAmp → speakers | Copper hifi wire | Audio signal, minimise resistance |
| LEDs + indicator | Dupont or thin wire | Low current, a few mA only |