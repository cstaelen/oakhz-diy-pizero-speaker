#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2014 The moOde audio player project / Tim Curtis
# Copyright 2025 OaKhz moode player project / cl-st

import RPi.GPIO as GPIO
import threading
import subprocess
import sys
from time import sleep, time
import sqlite3
import musicpd
import os
import requests

program_version = "1.0"

current_pos = 0
last_pos = 0
last_a_state = 1
last_b_state = 1
pin_a = 23
pin_b = 24
pin_button = 22
poll_interval = 100 # milliseconds
accel_factor = 2
volume_step = 3
print_debug = 0
thread_lock = threading.Lock()
last_volume = 0
init_volume = 80

def main():
	global poll_interval, accel_factor, volume_step, pin_a, pin_b, print_debug, mpd_cli

	# Parse input args (if any)
	if len(sys.argv) > 1:
		if sys.argv[1] == "--version" or sys.argv[1] == "-v":
			print("rotenc.py version " + program_version)
			sys.exit(0)

		if len(sys.argv) >= 6:
			poll_interval = int(sys.argv[1])
			accel_factor = int(sys.argv[2])
			volume_step = int(sys.argv[3])
			pin_a = int(sys.argv[4])
			pin_b = int(sys.argv[5])

		if len(sys.argv) == 7:
			print_debug = int(sys.argv[6])

		if print_debug:
			print(sys.argv, len(sys.argv))

	mpd_cli = musicpd.MPDClient()
	
	if print_debug:
		print("set initial volume")

	set_volume(init_volume)
	
	GPIO.setmode(GPIO.BCM)
	GPIO.setwarnings(True)
	GPIO.setup(pin_a, GPIO.IN, pull_up_down=GPIO.PUD_UP)
	GPIO.setup(pin_b, GPIO.IN, pull_up_down=GPIO.PUD_UP)
	GPIO.setup(pin_button, GPIO.IN, pull_up_down=GPIO.PUD_UP)
	GPIO.add_event_detect(pin_a, GPIO.BOTH, callback=encoder_isr)
	GPIO.add_event_detect(pin_b, GPIO.BOTH, callback=encoder_isr)
	GPIO.add_event_detect(pin_button, GPIO.FALLING, callback=button_handler, bouncetime=200)

	poll_encoder()

def set_volume(volume):
	global mpd_cli
 
	# For some reasons, on boot, volume is set to 0 despite of the `set_volume` in the main function.
	# If volume equal 0, we assume it's a volume initialisation and set it to initial volume.
	if volume == 0:
		volume = init_volume

	# Reduced volume range: 1 - 100
	volume = max(1, min(100, volume))

	if print_debug:
		print("set_volume:" +  str(volume))

	# Handle volume in UI
	with sqlite3.connect('/var/local/www/db/moode-sqlite3.db') as db:
		db.row_factory = sqlite3.Row
		db.text_factory = str
		db_cursor = db.cursor()
		db_cursor.execute("UPDATE cfg_system SET value=? WHERE param='volknob'", (str(volume),))
		db.commit()
	
 	# Handle volume for bluetooth 
	subprocess.run(
		["amixer", "-D", "default", "set", "SoftMaster", f"{volume}%"],
		stdout=subprocess.DEVNULL,
	)

	# Handle volume for mpd
	mpd_cli.connect()
	mpd_cli.setvol(volume)
	mpd_cli.disconnect()
 
 	# Handle vollume for plexamp
	PLEXAMP_URL = f"http://localhost:32500/player/playback/setParameters?volume={volume}&commandID=9999&type=music"
	try:
		response = requests.get(PLEXAMP_URL)
		response.raise_for_status()
	except requests.RequestException as e:
		print(f"Error setting Plexamp volume: {e}")

def encoder_isr(pin):
	global current_pos, last_a_state, last_b_state, thread_lock

	pin_a_state = GPIO.input(pin_a)
	pin_b_state = GPIO.input(pin_b)

	if last_a_state == pin_a_state and last_b_state == pin_b_state:
		return

	last_a_state = pin_a_state
	last_b_state = pin_b_state

	if pin_a_state and pin_b_state:
		thread_lock.acquire()
		if pin == pin_a:
			current_pos -= 1
		else:
			current_pos += 1
		thread_lock.release()

def poll_encoder():
	global current_pos, last_pos, thread_lock
	direction = ""

	while True:
		thread_lock.acquire()

		if current_pos > last_pos:
			direction = "+"
			step = 1 if (current_pos - last_pos) < accel_factor else volume_step
			update_volume(direction, step)
		elif current_pos < last_pos:
			direction = "-"
			step = 1 if (last_pos - current_pos) < accel_factor else volume_step
			update_volume(direction, step)

		thread_lock.release()

		if (current_pos != last_pos) and print_debug:
			print(abs(current_pos - last_pos), direction)

		last_pos = current_pos

		sleep(poll_interval / 1000)

def update_volume(direction, step):
	with sqlite3.connect('/var/local/www/db/moode-sqlite3.db') as db:
		db.row_factory = sqlite3.Row
		db.text_factory = str
		db_cursor = db.cursor()
		db_cursor.execute("SELECT value FROM cfg_system WHERE param='volknob' OR param='volume_mpd_max'")
		row = db_cursor.fetchone()
		current_vol = int(row['value'])
		row = db_cursor.fetchone()
		volume_mpd_max = int(row['value'])

	new_volume = current_vol + step if direction == "+" else current_vol - step
	new_volume = min(volume_mpd_max, max(0, min(100, new_volume)))

	set_volume(new_volume)

def button_handler(channel):
	global last_volume

	press_start = time()
	while GPIO.input(pin_button) == 0:
		sleep(0.01)
	press_duration = time() - press_start

	if press_duration >= 3:
		if print_debug:
			print("Long press : shutdown...")
		os.system("sudo shutdown -h now")
	else:
		try:
			output = subprocess.check_output(["amixer", "-D", "default", "get", "SoftMaster"]).decode()
			for line in output.splitlines():
				if "Front Left:" in line:
					current_vol = int(line.split()[3].strip('[]%'))

			if current_vol > 1:
				last_volume = current_vol
				set_volume(1)
				if print_debug:
					print("Mute")
			else:
				set_volume(last_volume)
				if print_debug:
					print(f"Unmute → {last_volume}%")
		except Exception as e:
			print("Error mute/unmute :", e)

if __name__ == '__main__':
	main()