class_name InputHost
extends RefCounted

## The studio's input: the unhandled-input handler and the keys it reads, and the hit voices that sound a hit on the fast path.
## Moved out of `scenes/studio.gd` without change of behaviour; the state stays on the studio, which delegates the calls other code makes.

## The keys that take you somewhere else: F to the gear (and the seat), I to the next instrument,
## V to the next venue, N up out of your body.
const MOVES_YOU := [KEY_F, KEY_I, KEY_V, KEY_N]

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


## Whether `keycode` is one that would move you while a piano has the keyboard (KeyCatcher: the
## modular's PLAY, the fingertips): held back, so a stray I in the middle of a phrase
## does not carry you off to another instrument with the keys still playing this one. Said, so the
## way on (Esc first) is not a guess.
func _held_while_playing(keycode: int) -> bool:
	if not keycode in MOVES_YOU or studio.get_viewport() == null \
			or not studio.get_viewport().gui_get_focus_owner() is KeyCatcher:
		return false
	Session.notice.emit("The keys are playing: Esc gives them back, then %s moves you." % OS.get_keycode_string(keycode))
	return true


## Orbit on right-drag, zoom on wheel, WASD to walk. Not a replacement for standing in the room;
## it is how the screen half of a hybrid session gets around, and how every screenshot of this
## project is framed.
func _unhandled_input(event: InputEvent) -> void:
	if studio.camera == null:
		return
	# A text field has the keyboard: none of the room's key shortcuts are for it.
	if event is InputEventKey and TextFocus.held(studio.get_viewport()):
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			and not studio.god_mode and studio.walker != null:
		studio.walker.look(event.relative)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		studio._orbit_yaw -= event.relative.x * 0.005
		studio._orbit_pitch = clampf(studio._orbit_pitch - event.relative.y * 0.005, -1.4, 1.2)
		studio.view_host._update_camera()
	elif event is InputEventKey and event.keycode == KEY_R and not event.echo:
		# Hold to wind up a throw of what you carry, let go to throw it where the cursor is.
		# R: beside Q, which puts it down, under the same hand.
		var hand := studio.get_node_or_null("MouseHand") as MouseInteractor
		if hand != null:
			if event.pressed:
				hand.begin_throw()
			else:
				hand.release_throw()
	elif event is InputEventKey and event.keycode == KEY_K and not event.echo and not event.ctrl_pressed:
		# The desktop's clap: K held over a track mutes it while held, a tap latches it.
		# Held for as long as the frames say (_follow_clap), the clock a clap is timed by.
		if event.pressed and not studio.key_clap.pressed:
			studio.key_clap.press(studio.mix_follow._mouse_track(), true)
		elif not event.pressed and studio.key_clap.pressed:
			studio.key_clap.release(studio.key_clap.held_for())
	elif event is InputEventKey and event.keycode == KEY_U and not event.echo and not event.ctrl_pressed:
		# Look to solo: U held, with the signal view on, solos the track under the cursor alone.
		if event.pressed:
			studio.signal_views.look_solo_press(&"key")
		else:
			studio.signal_views.look_solo_release(&"key")
	elif event is InputEventKey and event.keycode == KEY_L and not event.echo and not event.ctrl_pressed:
		# Lean in to the stage voice under the cursor while L is held.
		studio._lean_key = event.pressed
		studio.mix_follow._follow_lean()
	elif event is InputEventKey and event.pressed and not event.echo and _held_while_playing(event.keycode):
		pass
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			# Walk the gear past you one piece at a time, and off either end to put it back.
			# Shift goes the other way. One key, no modifier needed to start, and the exit is
			# where you would find it by accident.
			KEY_F:
				studio.focus.cycle(-1 if event.shift_pressed else 1)
				studio.station_host._sit_down()
			# The other half of the desk. A console pages by default, because twelve strips
			# you can face beats forty-eight you have to turn your head through -- but a
			# mix is sometimes a thing you want to see all of at once, and then the tiers
			# are worth the neck. One key, and it is the one the desk is named after.
			KEY_E:
				studio.view_host._toggle_expanded()
			KEY_G:
				studio.station_host._toggle_summoning()
			# Somewhere else to stand. The setup comes along; only the world changes.
			KEY_V:
				studio.venue_switch.cycle_venue()
			# The history, from anywhere in the room. The deck has keys for it too.
			KEY_Z when event.ctrl_pressed:
				DAW.redo() if event.shift_pressed else DAW.undo()
			KEY_Y when event.ctrl_pressed:
				DAW.redo()
			# Split the selected items at the playhead. B for blade: S is walking backwards.
			KEY_B:
				DAW.split_selected(DAW.state.position_seconds)
			# Put down what you are carrying, where you are looking. Q: the key under the hand
			# that is on WASD, and the one games drop things with.
			KEY_Q:
				studio.player_host.put_down_items()
			# Headphones on, or off into your hand. H: beside the hand's other item keys.
			KEY_H:
				studio.player_host._toggle_headphones()
			# See the signal (docs/spatial_loop.md part three): X, an x-ray of the mix, with or
			# without the glasses. G was taken by the gear's summoning.
			KEY_X when not event.ctrl_pressed and not event.meta_pressed:
				studio.signal_views.toggle_signal_view()
			# Why can't I hear this? Y over it, with the signal showing; Shift-Y does the fix.
			KEY_Y when not event.ctrl_pressed and not event.meta_pressed:
				if event.shift_pressed:
					studio.signal_views.fix_traced()
				else:
					studio.signal_views.trace_pointed(studio.get_node_or_null("MouseHand") as Interactor)
			# Your pockets: left hip, right hip, back. What is in the hand goes in, and what was
			# in comes out.
			KEY_1, KEY_2, KEY_3:
				studio.player_host._pocket(event.keycode - KEY_1)
			# The desk's six drum pads, KICK to RIM along its front rail: 4 to 9, the number row's
			# next six after the pockets.
			KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				studio.view_host.strike_desk_pad(event.keycode - KEY_4, event.shift_pressed)
			# Leave your body and fly, or come back down into it.
			KEY_N:
				studio.player_host.set_god_mode(not studio.god_mode)
			# Your fingertips as notes, on J K L ;: T, beside the home row they play on.
			KEY_T:
				studio.surface_host.toggle_fingertips()
			# The computer keyboard as a piano, to play whatever instrument is on the track: P.
			KEY_P when not event.ctrl_pressed and not event.meta_pressed:
				studio.computer_keys_toggled.emit()
			# The chord layer: C for chords. 1 to 7 then pick them in the keys that play.
			KEY_C when not event.ctrl_pressed and not event.meta_pressed:
				studio.surface_host.toggle_chords()
			# Go to the instruments one at a time, as F goes to the gear: I for instrument.
			# Shift goes the other way. The help card's PLAY pages go to one by name.
			KEY_I:
				studio.station_host.cycle_stations(-1 if event.shift_pressed else 1)
			KEY_ESCAPE:
				studio.view_host._on_escape()
			# Backspace over a voice on the stage table, or anything of its tag: that track back to
			# centre, 0 dB and full width, as a double-click on it does.
			KEY_BACKSPACE:
				var hand := studio.get_node_or_null("MouseHand") as MouseInteractor
				var under: Node = (hand.held if hand.held != null else hand.hovered) if hand != null else null
				if studio.stage != null and hand != null:
					studio.stage.reset_under(under)
			# [ and ] over a section block on the bricks table: it a place earlier or later, as one
			# rearrangement of the song; again with the cursor still, the same block on. Held, it
			# moves in the held order, written when it is let go.
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				var hand := studio.get_node_or_null("MouseHand") as MouseInteractor
				if studio.sections != null and is_instance_valid(studio.sections) and hand != null:
					studio.sections.step_under(hand.held if hand.held != null else hand.hovered,
							-1 if event.keycode == KEY_BRACKETLEFT else 1, hand.hover_point)
			# Comfort and eyesight, live, because the only way anyone finds the right value is
			# by changing it while looking at the thing.
			KEY_EQUAL, KEY_KP_ADD:
				studio.view_host._set_text_scale(studio.ergonomics.text_scale * 1.15)
			KEY_MINUS, KEY_KP_SUBTRACT:
				studio.view_host._set_text_scale(studio.ergonomics.text_scale / 1.15)
			KEY_0:
				studio.view_host._set_text_scale(1.0)
	elif event is InputEventMouseButton and event.pressed:
		# The wheel goes through what you carry while you carry anything; ctrl and the wheel
		# still zooms.
		var hand := studio.get_node_or_null("MouseHand") as MouseInteractor
		var notches := 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0
		if notches != 0 and not event.ctrl_pressed and hand != null and hand.pockets != null \
				and (hand.carrying != null or not hand.pockets.items().is_empty()):
			if hand.cycle_pockets(notches):
				studio.player_host._say_pockets(hand)
			return
		if not studio.god_mode and studio.walker != null:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				studio.camera.fov = maxf(30.0, studio.camera.fov - 3.0)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				studio.camera.fov = minf(Studio.ROOM_FOV, studio.camera.fov + 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			studio._orbit_distance = maxf(0.4, studio._orbit_distance - 0.12)
			studio.view_host._update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			studio._orbit_distance = minf(6.0, studio._orbit_distance + 0.12)
			studio.view_host._update_camera()


# --- strikes on the fast path (docs/spatial_loop.md part two, slice 39) ---------------------------

## The hits' helper started, where it can run as the keys' does (MonitorSynth.start's conditions:
## a sound card, the ports not bypassed, NativeKeys buildable, R3D_GODOT_KEYS not set), and Foley's
## struck sounds written and loaded into it. Until they are loaded, and wherever it cannot run,
## hits play on MONITOR through Godot, and the tag says so.
func _start_hit_voices() -> void:
	if studio.hit_voices != null or not MonitorSynth.available() or AudioPorts.direct \
			or OS.get_environment("R3D_GODOT_KEYS") == "1" or not NativeKeys.available():
		return
	var keys := NativeKeys.new()
	if not keys.start(AudioPorts.target, false, "dawlings · hits"):
		return
	studio.hit_voices = keys
	studio.hit_voices.load_hits()


## The helper's news read each frame: what it has loaded, how late it is; and if it has gone,
## every hit back on MONITOR.
func _follow_hit_voices() -> void:
	if studio.hit_voices == null:
		return
	studio.hit_voices.poll()
	if not studio.hit_voices.running():
		push_warning("The hits' helper stopped; playing them through the app instead.")
		studio.hit_voices.stop()
		studio.hit_voices = null


## InstrumentItem.fast_path: this player's own hit on the helper, if it holds that sound.
func _hit_on_fast_path(kind: StringName, take: int, gain: float, pan: float, speed: float) -> bool:
	return studio.hit_voices != null and studio.hit_voices.play_hit(kind, take, gain, pan, speed)


## InstrumentItem.fast_latency: the helper's figure once its sounds are in, else -1 (MONITOR).
func _fast_path_latency() -> float:
	if studio.hit_voices == null or studio.hit_voices.loaded.is_empty():
		return -1.0
	return studio.hit_voices.hit_latency()
