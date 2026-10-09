class_name KeytarItem
extends Item

## A keytar: a keyboard on a strap, to walk round the room playing (docs/items_loop.md).
##
## It has no sound of its own here. What plays it is this player's keys as they already are
## (GuestMidi): a MIDI keyboard, or the computer keyboard's piano rows, which picking it up turns
## on (the studio's `keytar_keys`). So a keytar in your hand is heard the instant you play, on
## the keys' own low-latency synth, goes to everyone as notes, and is recorded as a take by song
## position, all as a guest's keys are; the keytar is where you see it happen, each key going
## down as its note plays. Anyone else's keytar is heard from their hands in the room, on a synth
## of its own that plays out of the keytar (`heard`).

## Pressed from the studio, for the computer keyboard to be the keytar's again after it was let
## go (Esc, a click elsewhere): a click with the keytar in hand.
signal wants_keys()

const MODEL := "res://assets/models/keytar.glb"
## The keys (tools/blender/keytar.py): "Key00" to "Key24", by semitone up from a C.
const KEYS := 25
## The C the lowest key plays, before the octave is moved: what a note is shown on is the key
## an octave or two off it, wherever it is played.
const LOW_C := 48
## How far a key turns about its hinge going down (rad): its front drops about 7 mm, more than a
## real key's travel, because 4 mm is not seen from where it is held.
const PRESS := 0.08
## A key that is down is lit, the way a lit-keys keytar's are: seen from any side of it, and from
## across the room on somebody else's.
const LIT := Color(1.0, 0.5, 0.12)
## From the keytar's back face to the front edge of its body (tools/blender/keytar.py's FRONT
## less its rim): standing on its edge, its origin is this high over what it stands on.
const FRONT_EDGE := 0.104
## Where the hand closes on it, in its own frame: the middle of the grip round its neck.
const GRIP := Vector3(-0.36, 0.03, -0.012)
## Where a mouse's hand holds it: the front edge of the body beside the low keys, from under.
const CRADLE := Vector3(0.0, 0.0, 0.1)
## A bright red: on its rack it is above the shelf's lamp, and a dark red there is black.
const BODY := Color(0.66, 0.06, 0.06)
const TRIM := Color(0.02, 0.02, 0.025)
const IVORY := Color(0.78, 0.76, 0.7)
const EBONY := Color(0.03, 0.03, 0.035)
const DISPLAY := Color(1.0, 0.45, 0.12)

## {key index: MeshInstance3D}, from the model.
var keys: Dictionary = {}
## {key index: how many notes are holding it down}: two pitches an octave apart fall on one key
## when the note is outside the keytar's two octaves.
var _down: Dictionary = {}
## Somebody else's playing, out of the keytar: made the first time they play.
var _room: MonitorSynth = null
var _lit: StandardMaterial3D = null


func _init() -> void:
	id = &"keytar"
	super()
	_shape.position = Vector3(0, 0.035, 0.016)


func item_title() -> String:
	return "KEYTAR"


func hint() -> String:
	if state == State.HELD and not is_held_elsewhere():
		return "A–' play  ·  Z X octave  ·  arrows walk  ·  click for the keys again"
	return _hint("click to pick up and play it")


## The key a pitch is shown on: itself if it is on the keytar, else the same note an octave or
## more in.
static func key_of(pitch: int) -> int:
	var k := pitch - LOW_C
	while k < 0:
		k += 12
	while k >= KEYS:
		k -= 12
	return k


## A note down or up on it, shown on its key.
func press(pitch: int, down: bool) -> void:
	var k := key_of(pitch)
	var n: int = _down.get(k, 0) + (1 if down else -1)
	if n <= 0:
		_down.erase(k)
	else:
		_down[k] = n
	var key: MeshInstance3D = keys.get(k)
	if key != null:
		key.rotation.x = PRESS if _down.has(k) else 0.0
		key.material_override = _lit_material() if _down.has(k) else null


func is_down(pitch: int) -> bool:
	return _down.has(key_of(pitch))


## Every key up, and anything sounding out of it stopped.
func release_all() -> void:
	for k in _down.keys():
		var key: MeshInstance3D = keys.get(k)
		if key != null:
			key.rotation.x = 0.0
			key.material_override = null
	_down.clear()
	if _room != null:
		_room.all_off()


## Somebody else's note, as Session.note_played says it, while it is in their hands: out of the
## keytar into the room, and on its keys.
func heard(kind: int, pitch: int, velocity: int) -> void:
	if _room == null:
		_room = MonitorSynth.new()
		_room.name = "Room"
		_room.allow_native = false
		_room.speaker = self
		_room.volume_db = -4.0
		add_child(_room)
		_room.start()
	match kind:
		Session.Note.ON:
			_room.note_on(pitch, velocity)
			press(pitch, true)
		Session.Note.OFF:
			_room.note_off(pitch)
			press(pitch, false)
		Session.Note.PEDAL_DOWN:
			_room.sustain(true)
		Session.Note.PEDAL_UP:
			_room.sustain(false)


func use(down: bool) -> void:
	if down and carried_by != null:
		wants_keys.emit()


func on_put_down() -> void:
	release_all()


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var swap := {
		"body": _paint(BODY, 0.3, 0.0, 0.3),
		"trim": _paint(TRIM, 0.5),
		"white": _paint(IVORY, 0.35),
		"black": _paint(EBONY, 0.3),
		"grip": _paint(Color(0.04, 0.04, 0.045), 0.85),
		"metal": Materials.brushed_metal(),
		"led": Materials.led(DISPLAY, true),
	}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
		var named := String(mesh.name)
		if not named.begins_with("Key"):
			named = String(mesh.get_parent().name)
		if named.begins_with("Key") and named.substr(3).is_valid_int():
			keys[int(named.substr(3))] = mesh
	return root


func _lit_material() -> StandardMaterial3D:
	if _lit == null:
		_lit = _paint(LIT, 0.4)
		_lit.emission_enabled = true
		_lit.emission = LIT
		_lit.emission_energy_multiplier = 1.4
	return _lit


static func _paint(colour: Color, roughness: float, metallic := 0.0, clearcoat := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	m.metallic = metallic
	if clearcoat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = clearcoat
		m.clearcoat_roughness = 0.2
	return m


## The whole of it, keybed and neck: it is long, and an end of it is what a pointer finds.
func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.9, 0.08, 0.19)
	return s


func centre_height() -> float:
	return 0.035


## In a headset, by the grip on its neck, keys up, the body out across in front of you the way it
## hangs on a strap. On a desktop, by the body's front edge beside the low keys and a little
## further out, turned so the neck runs off to the left and back: the keys in view, tipped up
## toward the eye.
func held_pose() -> Transform3D:
	if carried_by is MouseInteractor:
		var turn := Basis(Vector3.UP, -0.42) * Basis(Vector3.FORWARD, -0.12) * Basis(Vector3.RIGHT, 0.75)
		return Transform3D(turn, Vector3(0.03, -0.02, 0.0) - turn * CRADLE)
	var hang := Basis(Vector3.UP, -0.3) * Basis(Vector3.RIGHT, 0.5)
	return Transform3D(hang, -(hang * GRIP))


func flies() -> Dictionary:
	return {"bounce": 0.2, "roll": 5.0, "drag": 0.1}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.rubber_tap(), clampf(linear_to_db(speed / 4.0), -18.0, 0.0), 0.7)


func _foley_contact() -> AudioStream:
	return Foley.rubber_tap()
