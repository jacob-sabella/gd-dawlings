class_name TimelineItemStrip
extends Node3D

## What can be done to one item, under the timeline while exactly one is selected: its gain and
## fades on knobs, its notes up or down a semitone, and onto the beat.
##
## A knob edits the item when it is let go (or wheeled), not on every tick of the turn: an item's
## gain is an edit, one undo step and one call to the DAW, where a fader is a live control. The
## card says what letting go will do while it turns.

## Gain across the knob's sweep, in dB. The DAW takes more (DAWBackend.ITEM_GAIN_MIN/MAX); a knob
## that spent most of its sweep below -24 dB would be a mute with extra steps.
const GAIN_LOW := -24.0
const GAIN_HIGH := 12.0
## A note grid for QUANT, in beats: the beat, or a sixteenth when fine.
const QUANT_GRID := 1.0
const QUANT_FINE_GRID := 0.25
const PITCH := 0.028
const CAPTION := Color(0.62, 0.64, 0.68)

## The TimelineSurface, for its lettering. Typed loosely so the files load in any order.
var surface: Node

var gain: Knob
var fade_in: Knob
var fade_out: Knob
var down: PanelButton
var up: PanelButton
var quant: PanelButton
var mute: PanelButton
var copy_here: PanelButton
var normalise: PanelButton
var softer: PanelButton
var harder: PanelButton
## [track, item] being edited, or empty while there is not exactly one selected.
var _target: Array = []


func _ready() -> void:
	# A plate under the controls, hung from the panel's bottom edge like a desk's meter bridge
	# turned upside down: without it they float in front of whatever is behind the timeline.
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	box.size = Vector3(11 * PITCH, 0.036, 0.004)
	plate.mesh = box
	plate.material_override = Materials.chassis()
	plate.position = Vector3(5.0 * PITCH, -0.004, -0.002)
	add_child(plate)
	gain = _knob("GAIN", 0, func(v: float) -> String: return "%+.1f dB" % _gain_db(v))
	gain.value_committed.connect(func(v: float):
		if not _target.is_empty():
			DAW.set_item_gain(_target[0], _target[1], _gain_db(v)))
	fade_in = _knob("IN", 1, func(v: float) -> String: return "%.2f s" % _fade_seconds(v))
	fade_in.value_committed.connect(func(v: float): _set_fades(_fade_seconds(v), NAN))
	fade_out = _knob("OUT", 2, func(v: float) -> String: return "%.2f s" % _fade_seconds(v))
	fade_out.value_committed.connect(func(v: float): _set_fades(NAN, _fade_seconds(v)))
	down = _key("ItemDown", "-", 3, Color(0.55, 0.7, 0.95), "ITEM  TRANSPOSE DOWN",
			func(): _transpose(-1), "a semitone down; fine: an octave")
	up = _key("ItemUp", "+", 4, Color(0.55, 0.7, 0.95), "ITEM  TRANSPOSE UP",
			func(): _transpose(1), "a semitone up; fine: an octave")
	quant = _key("ItemQuant", "Q", 5, Color(0.9, 0.8, 0.4), "ITEM  QUANTISE",
			func(): _quantise(), "notes onto the beat; fine: onto sixteenths")
	mute = _key("ItemMute", "M", 6, Color(0.95, 0.45, 0.4), "ITEM  MUTE",
			func(): _toggle_mute(), "silence it, or play it again")
	copy_here = _key("ItemCopyHere", "P", 7, Color(0.55, 0.85, 0.55), "ITEM  COPY TO PLAYHEAD",
			func(): DAW.copy_selected_to(DAW.state.position_seconds), "a copy where the song is now")
	copy_here.describe_value = func(_v: float) -> String: return "a copy where the song is now"
	normalise = _key("ItemNormalise", "N", 8, Color(0.9, 0.8, 0.4), "ITEM  NORMALISE",
			func(): _normalise(), "gain so its loudest moment is full scale")
	normalise.describe_value = func(_v: float) -> String:
		return "gain so its loudest moment is full scale" if normalise.lit else "for a recorded item"
	softer = _key("ItemSofter", "V-", 9, Color(0.55, 0.7, 0.95), "ITEM  NOTES SOFTER",
			func(): _velocity(-1), "every note a little softer; fine: much softer")
	harder = _key("ItemHarder", "V+", 10, Color(0.55, 0.7, 0.95), "ITEM  NOTES HARDER",
			func(): _velocity(1), "every note a little harder; fine: much harder")
	DAW.timeline_changed.connect(refresh)
	DAW.transport_changed.connect(refresh)
	refresh()


## Follows the selection: shown, and the knobs set from the item, while exactly one is selected.
func refresh() -> void:
	var picked: Array = DAW.state.selected_items()
	_target = picked[0] if picked.size() == 1 else []
	var item: MixState.ItemState = null if _target.is_empty() else DAW.state.item(_target[0], _target[1])
	if item == null:
		_target = []
	visible = item != null
	for c in [gain, fade_in, fade_out, down, up, quant, mute, copy_here, normalise, softer, harder]:
		c.collision_layer = 2 if item != null else 0
	if item == null:
		return
	gain.snap_to(clampf((item.gain_db - GAIN_LOW) / (GAIN_HIGH - GAIN_LOW), 0.0, 1.0))
	fade_in.snap_to(_fade_value(item.fade_in))
	fade_out.snap_to(_fade_value(item.fade_out))
	mute.lit = item.muted
	mute.describe_value = func(_v: float) -> String: return "muted: press to play it again" if item.muted else "silence it"
	normalise.lit = item.sound_peak() > 0.0
	copy_here.lit = true
	var midi := not item.notes.is_empty()
	for key in [down, up, quant, softer, harder]:
		key.lit = midi


func _gain_db(v: float) -> float:
	return lerpf(GAIN_LOW, GAIN_HIGH, v)


## Squared, so the short fades a click wants have most of the sweep; the whole item at the end.
func _fade_seconds(v: float) -> float:
	return v * v * _item_length()


func _fade_value(seconds: float) -> float:
	return sqrt(clampf(seconds / maxf(_item_length(), 0.0001), 0.0, 1.0))


func _item_length() -> float:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	return item.length if item != null else 1.0


func _set_fades(fin: float, fout: float) -> void:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item == null:
		return
	DAW.set_item_fades(_target[0], _target[1], item.fade_in if is_nan(fin) else fin,
			item.fade_out if is_nan(fout) else fout)


func _transpose(direction: int) -> void:
	if not _target.is_empty():
		DAW.transpose_item(_target[0], _target[1], direction * (12 if _fine(up) or _fine(down) else 1))


func _normalise() -> void:
	if not _target.is_empty():
		DAW.normalise_item(_target[0], _target[1])


func _toggle_mute() -> void:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item != null:
		DAW.set_item_muted(_target[0], _target[1], not item.muted)


func _velocity(direction: int) -> void:
	if not _target.is_empty():
		DAW.shift_velocity(_target[0], _target[1], direction * (32 if _fine(harder) or _fine(softer) else 8))


func _quantise() -> void:
	if not _target.is_empty():
		DAW.quantize_item(_target[0], _target[1], QUANT_FINE_GRID if _fine(quant) else QUANT_GRID)


## The hand pressing a key holds fine (shift on a monitor).
func _fine(key: PanelButton) -> bool:
	var by: Node = key.held_by
	return by != null and by.has_method("fine") and by.fine()


func _knob(caption: String, slot: int, text: Callable) -> Knob:
	var k := Knob.new()
	k.name = "Item" + caption.capitalize()
	k.position = Vector3(slot * PITCH, 0.0, 0.004)
	k.scale = Vector3(0.75, 0.75, 0.75)
	k.describe_title = func() -> String: return "ITEM  " + caption
	k.describe_value = text
	add_child(k)
	_caption(caption, slot)
	return k


func _key(key_name: String, caption: String, slot: int, colour: Color, title: String,
		act: Callable, what: String) -> PanelButton:
	var key := PanelButton.new()
	key.name = key_name
	key.led_colour = colour
	key.lamp_scale = Vector2(0.8, 0.5)
	key.scale = Vector3(1.4, 1.4, 1.4)
	key.position = Vector3(slot * PITCH, 0.0, 0.003)
	key.pressed.connect(act)
	key.describe_title = func() -> String: return title
	key.describe_value = func(_v: float) -> String: return what if key.lit else "for a MIDI item"
	add_child(key)
	_caption(caption, slot)
	return key


func _caption(text: String, slot: int) -> void:
	var l: Label3D = surface._text(text, 22, CAPTION)
	l.position = Vector3(slot * PITCH, -0.015, 0.0016)
	add_child(l)
