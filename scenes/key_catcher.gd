class_name KeyCatcher
extends Control

## The computer keyboard as a small piano, for a guest with no MIDI keyboard to hand.
##
## Opt in, never on by default: the studio already walks on WASD and Space and gives F, E, G, V,
## B and N jobs of their own, and a piano laid over the home row would take every one of them.
## So this is an invisible control that plays only while it has keyboard focus. Focus is also
## what the studio and the walker already check before they read the keyboard, so while it
## plays nothing else moves. Click anywhere else, or press Esc, and the keys are the studio's
## again.
##
## Laid out by where the keys are, not by what they say, so the shape is the same on any
## keyboard: the home row from A is the white keys from C, the row above holds the black keys
## between them, and Z and X move the octave.
##
## The arrow keys are not the piano's: they walk (Walker, which looks for WALKS_ON_ARROWS), so
## the keytar can be played on the move. Taken here all the same, or the GUI would move focus on
## them and the piano would stop.

signal note_on(pitch: int, velocity: int)
signal note_off(pitch: int)
## Turned on or off, by the panel, by Esc, or by focus going elsewhere.
signal active_changed(active: bool)

## The group a control that has the keyboard and still lets the arrow keys walk is in.
const WALKS_ON_ARROWS := &"walks_on_arrows"
const ARROWS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
const VELOCITY := 100
## Semitones above the octave's C, by physical key.
const LAYOUT := {
	KEY_A: 0, KEY_W: 1, KEY_S: 2, KEY_E: 3, KEY_D: 4, KEY_F: 5, KEY_T: 6, KEY_G: 7, KEY_Y: 8,
	KEY_H: 9, KEY_U: 10, KEY_J: 11, KEY_K: 12, KEY_O: 13, KEY_L: 14, KEY_P: 15,
	KEY_SEMICOLON: 16, KEY_APOSTROPHE: 17,
}
const LOWEST_C := 24
const HIGHEST_C := 96

## The C under the A key. Middle C to start with.
var base := 60
## Physical key -> the pitch it started, so a key let go after an octave change stops the note
## it started rather than one it did not.
var _down := {}


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ZERO
	size = Vector2.ZERO
	focus_exited.connect(_on_focus_exited)
	add_to_group(WALKS_ON_ARROWS)


func is_active() -> bool:
	return has_focus()


func set_active(on: bool) -> void:
	if on == has_focus():
		return
	if on:
		grab_focus()
		active_changed.emit(true)
	else:
		release_focus()


func octave_name() -> String:
	return "C%d" % (base / 12 - 1)


func _gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return
	# Shortcuts with a modifier stay the studio's: Ctrl+Z is undo whether or not this plays.
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
		return
	if key.physical_keycode in ARROWS:
		accept_event()
		return
	if key.echo:
		if LAYOUT.has(key.physical_keycode):
			accept_event()
		return
	if key.physical_keycode == KEY_ESCAPE and key.pressed:
		accept_event()
		set_active(false)
		return
	if handle(key.physical_keycode, key.pressed):
		accept_event()


## One key, down or up. True when the key is this piano's. Public so the suite can play it.
func handle(physical: int, pressed: bool) -> bool:
	if physical == KEY_Z or physical == KEY_X:
		if pressed:
			base = clampi(base + (12 if physical == KEY_X else -12), LOWEST_C, HIGHEST_C)
		return true
	if not LAYOUT.has(physical):
		return false
	if pressed:
		if _down.has(physical):
			return true
		var pitch: int = clampi(base + LAYOUT[physical], 0, 127)
		_down[physical] = pitch
		note_on.emit(pitch, VELOCITY)
	elif _down.has(physical):
		note_off.emit(_down[physical])
		_down.erase(physical)
	return true


## Every key this piano has down, let go.
func release_all() -> void:
	for physical in _down.keys():
		note_off.emit(_down[physical])
	_down.clear()


func _on_focus_exited() -> void:
	release_all()
	active_changed.emit(false)
