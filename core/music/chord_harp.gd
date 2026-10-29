class_name ChordHarp
extends ControlAffordance

## A floor harp of eight strings tuned to the song's chord (docs/spatial_loop.md, slice 3; idea
## #22, an air harp of the current chord). Whatever you strum is in the chord, so anyone can play
## it along to the song.
##
## The strings are the chord's first eight tones at or above G3 (`Harmony.tones(LOWEST, 8)`),
## read at the moment each strum is played, so on a chord change they are retuned at once; a
## string still ringing keeps the pitch it was plucked at. Lowest on the left as you face it.
##
## Played every way a hand can: a grab (a mouse, a pinch ray, a controller's trigger) plucks the
## string nearest where it closed, and moving while held plucks every string it crosses, either
## way: a strum. A bare hand strums by touch, with no grab at all (`tips`): a fingertip brushing
## through the strings plucks each one it passes. So a fingertip's poke is not also a grab
## (`grab_begin` ignores a PokeInteractor), or a touch would be counted twice.
##
## Its notes are this player's keys (`keys`, GuestMidi), with source `&"harp"`: heard at once on
## the keys' own synth, sent to everyone, and taken down as a take on the armed track. The studio
## puts `&"harp"` in the keys' instruments while the player is near it, a hand is on it, or a
## string still rings, so the strums with gaps between them are one take. A bandmate's harp notes
## arrive as notes, never as fingers, and are played out of the harp here (`heard`).
##
## Its output jack (`jack`, a JackSocket on the short pillar, `Jack.HARP`) is anyone's to plug,
## since the harp is the room's: into a bandmate (docs/spatial_loop.md slice 6), its strings go
## down the cable to their keys instead of onto this player's, each with the song position it
## was plucked at, and this player hears them from the harp itself (`heard`, as a bandmate's).
##
## Under a chord shape (docs/spatial_loop.md part two, slice 32; ChordHand) the strings are the
## shape's chord, for the player holding it and nobody else: their strings, letters and crown
## retune to it and back as the hand opens, and what they pluck goes out as the notes it is. A
## bandmate's chord hand plugged into this player (part two, slice 33) retunes them the same way,
## and the crown says whose it is: `IV from ADA` (ChordHand.crown_text).
##
## The octave: two buttons on the crown, `8va UP` and `8va DOWN` (any hand, and dwell), the wheel
## and the thumbstick (`nudge`) move the strings an octave at a time, at most MOST_OCTAVES either
## way. The crown says the shift in words (`+1 OCT`) and the chord's name; each string's note is
## lettered at its top; a sounding string shakes. Nothing here is told by colour.
##
## The plucking hand bends what rings (docs/spatial_loop.md part two, slice 15): tipped from where
## its first string began, its roll bends the harp's notes and its shake wobbles them, while a
## string it plucked rings (`wobble`, on the hand that plucked last: an Interactor, or a bare
## hand's HandGestures for a touch). On a desktop the mouse's wiggle over the strings is that
## shake (`plays_under_cursor`), and Alt with the mouse moving up or down bends. A ringing string
## bows across by its bend (`bow`), a bandmate's as they bend it too.

## What this harp's notes say they came from (Session.send_note's `source`).
const SOURCE := &"harp"
const MODEL := "res://assets/models/chord_harp.glb"
const STRINGS := 8
## The lowest the bottom string may be, unshifted: G3. The strings are the chord's tones from it.
const LOWEST := 55
## How long a plucked string rings before its note is let go (s), unless it is plucked again.
const RING := 1.6
## The most the strings move, in octaves either way.
const MOST_OCTAVES := 2
## A fingertip within this of the string plane (m) is touching the strings.
const TOUCH := 0.03
## How near the harp the player has to stand for it to be in reach (m, on the floor).
const NEAR := 1.6
## The softest a strum plays, however slowly it crossed (InstrumentItem.velocity_for's scale).
const SOFTEST := 50
## A click on a string, with no sweep to measure.
const PLUCK_VELOCITY := 84

## The body's sizes, as tools/blender/chord_harp.py builds it: the soundboard's top, where every
## string starts; the neck's underside at its two pillars; the pillars' x; the crown's middle.
const BOARD_Y := 0.64
const NECK_LEFT := 1.58
const NECK_RIGHT := 1.30
const FRAME_X := 0.31
const CROWN_Y := 1.665
## How wide the crown's chord may be lettered (m): between its two octave buttons, so a long one
## (`IV from GRACE`) is set smaller rather than run under them.
const CROWN_TEXT_WIDE := 0.15
const SPACING := 0.062
## Its footprint on the floor, from the plinth: half its size, and how far behind the string
## plane its middle is. And how tall it stands.
const FOOT := Vector2(0.35, 0.2)
const FOOT_Z := -0.06
const HEIGHT := 1.73
## How far a string's middle swings while it sounds, fresh from a pluck (m), and how fast.
const SHAKE := 0.004
const SHAKE_HZ := 11.0
## Where the jack is: on the front of the short pillar (the high strings' side), at a standing
## hand's height, clear of the strings' frame.
const JACK_AT := Vector3(FRAME_X, 0.98, 0.026)
## How far a ringing string's middle bows across at the most bend (m), toward the high strings
## for a bend up: under half the strings' spacing, so it never reaches the next.
const BOW_MOST := 0.03
## Where its plaque stands (Stations.plaque): on a plate at the plinth's front, under the strings,
## leant back PLAQUE_LEAN so a standing player reads it from where they play.
const PLAQUE_AT := Vector3(0, 0.3, FOOT_Z + FOOT.y + 0.02)
const PLAQUE_LEAN := 0.6

## Where its notes are played: this player's keys. Session.guest_midi unless told otherwise.
var keys: GuestMidi = null
## () -> {id: Vector3}: this player's tracked fingertips, in global space, keyed by whatever
## stays the same for one tip from frame to frame. Not set, it is every local tracked hand's
## index and middle tips (HandGestures.local_tips): none on a desktop, or with controllers in
## hand. The suite sets its own.
var tips: Callable = Callable()
## How many octaves the strings are moved, -MOST_OCTAVES..MOST_OCTAVES.
var shift := 0
## The synth a bandmate's harp notes play on, out of the harp: made the first time one arrives.
var room: MonitorSynth = null
## Its output jack, on the short pillar.
var jack: JackSocket = null
## The plucking hand's bend and wobble on what rings (Wobble): the hand that plucked last.
var wobble: Wobble = null

## {string index: [pitch sounding, seconds left, the bandmate it went into down the jack or 0]}
## for the strings ringing from this player's hand.
var _ringing := {}
## {string index: seconds left} for the strings shaking with a bandmate's note on them.
var _shaking := {}
## A bandmate's notes sounding: {Vector2i(peer, pitch): true}, so their note-off finds its own.
var _theirs := {}
## The bandmate whose controls the bandmates' synth (`room`) has now, 0 for none (`heard_control`).
var _wheel_peer := 0
## Their bend as they sent it (semitones), which their shaking strings bow by.
var _their_bend := 0.0
## How far each string bows across now (m), and each string's own material, which bows it.
var _bows := PackedFloat32Array()
var _gut: Array[ShaderMaterial] = []
## Each fingertip's place in the harp's frame last physics frame, while it touched the strings.
var _tips_was := {}
## Where the held hand was along the strings at its last move, and when (usec).
var _grab_x := 0.0
var _grab_usec := 0
var _strings: Array[MeshInstance3D] = []
var _notes: Array[Label3D] = []
var _chord_label: Label3D
var _shift_label: Label3D
var _clock := 0.0
## The tuning the labels show, and the crown's words, so they are only rewritten when they change.
var _shown := PackedInt32Array()
var _crown := ""


## Its footprint for the walker, at `at` (Venue.harp_spot), as {c, h, a, top}.
static func solid(at: Transform3D) -> Dictionary:
	var middle := at * Vector3(0, 0, FOOT_Z)
	return {"c": Vector2(middle.x, middle.z), "h": FOOT, "a": at.basis.get_euler().y, "top": HEIGHT}


## String `i`'s place across the harp, in its own frame: lowest on the left.
static func string_x(i: int) -> float:
	return (i - (STRINGS - 1) * 0.5) * SPACING


## How high string `i` reaches, to the neck's underside (tools/blender/chord_harp.py's neck_y).
static func string_top(i: int) -> float:
	var f := (string_x(i) + FRAME_X) / (FRAME_X * 2.0)
	return lerpf(NECK_LEFT, NECK_RIGHT, f) + 0.025 * sin(f * PI * 2.0)


func _init() -> void:
	name = "ChordHarp"


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	if keys == null:
		keys = Session.guest_midi
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	add_child(model)
	_dress(model)
	# What a hand finds: the strings' whole frame, thin, in their plane. Interactor._plane_point
	# then keeps a held ray in the same plane, through the harp's origin.
	var shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	var top := string_top(0)
	bounds.size = Vector3(string_x(STRINGS - 1) * 2.0 + SPACING, top - BOARD_Y, 0.07)
	shape.shape = bounds
	shape.position = Vector3(0, (top + BOARD_Y) * 0.5, 0)
	add_child(shape)
	_bows.resize(STRINGS)
	for i in STRINGS:
		var line := MeshInstance3D.new()
		line.name = "String%d" % i
		var mesh := CylinderMesh.new()
		var length := string_top(i) - BOARD_Y
		mesh.top_radius = 0.0016
		mesh.bottom_radius = 0.0016
		mesh.height = length
		mesh.radial_segments = 6
		# Rings enough to bow smoothly (`bow`).
		mesh.rings = 12
		line.mesh = mesh
		var gut := ShaderMaterial.new()
		gut.shader = _bowed()
		gut.set_shader_parameter(&"half_length", length * 0.5)
		_gut.append(gut)
		line.material_override = gut
		line.position = Vector3(string_x(i), BOARD_Y + length * 0.5, 0)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(line)
		_strings.append(line)
		_notes.append(_label(22, Vector3(string_x(i), string_top(i) + 0.075, 0.03)))
	_chord_label = _label(40, Vector3(0, CROWN_Y + 0.014, 0.003))
	_shift_label = _label(20, Vector3(0, CROWN_Y - 0.033, 0.003))
	for way in [-1, 1]:
		var button := OctaveButton.new()
		button.harp = self
		button.way = way
		button.position = Vector3(way * 0.12, CROWN_Y, 0.004)
		add_child(button)
	_lamp()
	jack = JackSocket.new(null, SOURCE)
	jack.label = "CHORD HARP"
	# Facing out of the pillar's front, toward whoever stands at the strings.
	jack.transform = Transform3D(Basis(Vector3.UP, PI), JACK_AT)
	add_child(jack)
	var plaque := Stations.plaque(&"harp")
	plaque.transform = Transform3D(Basis(Vector3.RIGHT, -PLAQUE_LEAN), PLAQUE_AT)
	add_child(plaque)
	_show_tuning(true)


## The strings' gut, bowed across by `bow` metres at the middle, nothing at the ends: one shader
## for every string, a material each.
static var _bow_shader: Shader = null


static func _bowed() -> Shader:
	if _bow_shader == null:
		_bow_shader = Shader.new()
		_bow_shader.code = """shader_type spatial;
uniform float bow = 0.0;
uniform float half_length = 0.5;
void vertex() {
	float t = clamp(VERTEX.y / half_length, -1.0, 1.0);
	VERTEX.x += bow * (1.0 - t * t);
}
void fragment() {
	ALBEDO = vec3(0.93, 0.88, 0.76);
	METALLIC = 0.4;
	ROUGHNESS = 0.35;
}
"""
	return _bow_shader


## A music-stand lamp on an arm out from the crown, down onto the strings: the harp stands in the
## live room's back corner, where nothing else lights the strings a hand is looking for.
func _lamp() -> void:
	var warm := Color(1.0, 0.82, 0.6)
	var at := Vector3(0, CROWN_Y + 0.075, 0.26)
	# Thinner than the strip it holds and ending inside it, so no face of one lies in a face of
	# the other.
	ZoneKit.block(self, Vector3(0.008, 0.008, 0.248), Vector3(0, CROWN_Y + 0.075, 0.126),
			Materials.brushed_metal(), "LampArm")
	var strip := ZoneKit.block(self, Vector3(0.16, 0.012, 0.03), at, ZoneKit.glow(warm, 3.0), "LampStrip")
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := SpotLight3D.new()
	light.name = "HarpLight"
	light.light_color = warm
	light.light_energy = 2.4
	light.spot_range = 2.4
	# Wide enough to take in the crown's buttons behind it as well as the strings below.
	light.spot_angle = 52.0
	light.spot_attenuation = 0.8
	light.shadow_enabled = false
	light.transform = Transform3D(Basis.looking_at(Vector3(0, 1.25, 0) - at, Vector3.UP), at)
	add_child(light)


func _dress(model: Node3D) -> void:
	var swap := {
		"wood": _paint(Color(0.6, 0.36, 0.17), 0.42, 0.0, 0.4),
		"board": _paint(Color(0.78, 0.64, 0.42), 0.5),
		"dark": _paint(Color(0.05, 0.04, 0.035), 0.7),
		"brass": Materials.brushed_metal(),
		"crown": _paint(Color(0.06, 0.05, 0.045), 0.6),
	}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])


func _label(size: int, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font_size = size * 4
	l.pixel_size = 0.00025
	l.position = at
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate = Color(0.95, 0.92, 0.84)
	Lettering.range_to_legibility(l)
	add_child(l)
	return l


static func _paint(colour: Color, roughness: float, metallic := 0.0, clearcoat := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	m.metallic = metallic
	if clearcoat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = clearcoat
		m.clearcoat_roughness = 0.3
	return m


# --- what it is tuned to ------------------------------------------------------------------------

## The song position a note played now is played to: as the keys stamp it while the song plays
## (GuestMidi.song), and the playhead while it is stopped. One read, for a whole strum.
func _now() -> float:
	return _moment()[0]


## [the song position a note played now takes, and whether the song is playing to it], from one
## read of the keys' clock: what a strum is pitched by, recorded at and sent with.
func _moment() -> Array:
	var song := keys.song() if keys != null else -1.0
	if song >= 0.0:
		return [song, true]
	return [DAW.state.position_seconds if DAW.state != null else 0.0, false]


## The harmony at `seconds`, as this player plays in it: the song's, or the chord shape they hold
## (ChordHand.at). The strings, their letters and the crown retune for them alone.
func harmony_at(seconds: float) -> Harmony:
	return ChordHand.at(seconds)


## The strings' pitches at `seconds`, lowest first, with the octave shift.
func tuning_at(seconds: float) -> PackedInt32Array:
	return harmony_at(seconds).tones(LOWEST + 12 * shift, STRINGS)


## The strings' pitches now.
func tuning() -> PackedInt32Array:
	return tuning_at(_now())


## Whether any string plucked here is still sounding.
func ringing() -> bool:
	return not _ringing.is_empty()


## Whether a hand here is on it or over it: the strings, or a button on the crown.
func touched() -> bool:
	if is_hovered() or is_held() or not _tips_was.is_empty():
		return true
	for child in get_children():
		var button := child as OctaveButton
		if button != null and (button.is_hovered() or button.is_held()):
			return true
	return false


# --- playing it ---------------------------------------------------------------------------------

## The string nearest `x` across the harp, in its own frame.
static func nearest(x: float) -> int:
	return clampi(roundi(x / SPACING + (STRINGS - 1) * 0.5), 0, STRINGS - 1)


## The strings a hand passes going from `from` to `to` across the harp, in the order it meets
## them: those it reaches, not the one it set out from, so a sweep that starts on a string does
## not pluck it again.
static func crossed(from: float, to: float) -> Array[int]:
	var out: Array[int] = []
	for i in STRINGS:
		var x := string_x(i)
		if (from < x and x <= to) or (to <= x and x < from):
			out.append(i)
	if to < from:
		out.reverse()
	return out


## How hard a sweep at `speed` (m/s across the strings) plays.
static func velocity_at(speed: float) -> int:
	return maxi(InstrumentItem.velocity_for(speed), SOFTEST)


## Pluck `strings` (indices), in order, at `velocity`: each at its pitch at one song position.
## `by`, the hand that plucked them (an Interactor, a bare hand's HandGestures), bends them while
## they ring (`wobble`); null leaves the bending hand as it was.
func pluck(strings: Array, velocity: int, by: Object = null) -> void:
	if strings.is_empty():
		return
	if by != null:
		_bending(by)
	var moment := _moment()
	var seconds: float = moment[0]
	var timed: bool = moment[1]
	var pitches := tuning_at(seconds)
	var jacks := Jacks.of(self)
	# Into whoever plucks it is no cable: onto their keys, as unplugged (Jacks.cable_into).
	var into := jacks.cable_into(SOURCE) if jacks != null else 0
	for i in strings:
		var pitch: int = pitches[i]
		# Plucked again, or another string ringing this pitch since a retune: that note ends here,
		# so one pitch is one note, and its note-off never ends the one that replaced it.
		for other in _ringing.keys():
			if other == i or int(_ringing[other][0]) == pitch:
				_let_ring_out(other)
		_ringing[i] = [pitch, RING, into]
		if into > 0:
			# Down the jack into a bandmate's keys, and heard here from the harp itself.
			jacks.send_to(into, SOURCE, Jack.Kind.NOTE_ON, pitch, velocity, seconds if timed else -1.0)
			heard(Session.local_peer_id, Session.Note.ON, pitch, velocity)
		elif keys != null:
			keys.note_on(pitch, velocity, 0, 0.0, false, SOURCE, seconds if timed else NAN)


func _let_ring_out(i: int) -> void:
	var was: Array = _ringing.get(i, [])
	_ringing.erase(i)
	if was.is_empty():
		return
	var into: int = was[2] if was.size() > 2 else 0
	if into > 0:
		var jacks := Jacks.of(self)
		var moment := _moment()
		if jacks != null:
			jacks.send_to(into, SOURCE, Jack.Kind.NOTE_OFF, int(was[0]), 0, moment[0] if moment[1] else -1.0)
		heard(Session.local_peer_id, Session.Note.OFF, int(was[0]), 0)
	elif keys != null:
		keys.note_off(int(was[0]), 0, 0.0, false, SOURCE)


## Every string plucked here let go, now: for a harp leaving the room with a note still on.
func silence() -> void:
	for i in _ringing.keys():
		_let_ring_out(i)


func grab_begin(by: Node, at: Vector3) -> void:
	# A fingertip touches the strings directly (`tips`); counting its contact as a grab as well
	# would pluck the string twice, and hold the harp against everyone else's hand.
	if by is PokeInteractor:
		return
	_bending(by)
	super(by, at)


## The hand that bends what rings, from its next frame: `by`.
func _bending(by: Object) -> void:
	if wobble == null:
		wobble = Wobble.new(keys, [SOURCE])
	wobble.keys = keys
	wobble.hand = by


## The harp plays under the cursor: a wiggle of the mouse over a ringing string wobbles it, with
## nothing carried and no grab (MouseInteractor.wiggles).
func plays_under_cursor() -> bool:
	return true


## How far string `i` bows across now (m): by its bend, mine while it rings from my hand, a
## bandmate's while theirs shakes it. For the suite and the shot.
func bow(i: int) -> float:
	return _bows[i] if i >= 0 and i < _bows.size() else 0.0


func _on_grab_begin(at: Vector3) -> void:
	var x := to_local(at).x
	var i := nearest(x)
	# From the string it plucked, so a sweep from there does not pluck it again.
	_grab_x = string_x(i)
	_grab_usec = Time.get_ticks_usec()
	pluck([i], PLUCK_VELOCITY)


func _on_grab_move(at: Vector3) -> void:
	var x := to_local(at).x
	var now := Time.get_ticks_usec()
	var seconds := maxf((now - _grab_usec) / 1e6, 1.0 / 120.0)
	var passed := crossed(_grab_x, x)
	if not passed.is_empty():
		pluck(passed, velocity_at(absf(x - _grab_x) / seconds))
	_grab_x = x
	_grab_usec = now


func _physics_process(delta: float) -> void:
	_strum_by_touch(delta)
	_ring_on(delta)
	if wobble != null:
		wobble.keys = keys
		wobble.step(delta)


## The hand a strumming tip's key names (HandGestures.local_tips keys it [hand, finger]): its
## HandGestures, or null for a key of the suite's own. Public so the room's strings (RoomString), which
## take the same fingertip keys from FingertipNotes, can name the plucking hand the same way.
static func tip_hand(id: Variant) -> Object:
	if id is Array and not (id as Array).is_empty() and (id as Array)[0] is int:
		return instance_from_id(int((id as Array)[0])) as HandGestures
	return null


## The fingertips, through the strings: a tip within TOUCH of their plane and inside the frame
## plucks every string between where it was last frame and where it is now, either way. So a
## hand brushing back and forth is a strum each pass.
func _strum_by_touch(delta: float) -> void:
	var now: Dictionary = tips.call() if tips.is_valid() \
			else HandGestures.local_tips(get_tree() if is_inside_tree() else null)
	var into := global_transform.affine_inverse()
	var seen := {}
	for id in now:
		var p: Vector3 = into * (now[id] as Vector3)
		if absf(p.z) > TOUCH or absf(p.x) > string_x(STRINGS - 1) + SPACING * 0.5 \
				or p.y < BOARD_Y or p.y > NECK_LEFT:
			continue
		seen[id] = true
		if _tips_was.has(id):
			var was: Vector3 = _tips_was[id]
			# Only the strings long enough to be where the tip passed them.
			var passed := crossed(was.x, p.x).filter(func(i: int) -> bool: return p.y <= string_top(i))
			if not passed.is_empty():
				pluck(passed, velocity_at(absf(p.x - was.x) / maxf(delta, 0.001)), tip_hand(id))
		_tips_was[id] = p
	for id in _tips_was.keys():
		if not seen.has(id):
			_tips_was.erase(id)


func _ring_on(delta: float) -> void:
	for i in _ringing.keys():
		_ringing[i][1] = float(_ringing[i][1]) - delta
		if float(_ringing[i][1]) <= 0.0:
			_let_ring_out(i)
	for i in _shaking.keys():
		_shaking[i] = float(_shaking[i]) - delta
		if float(_shaking[i]) <= 0.0:
			_shaking.erase(i)


func _process(delta: float) -> void:
	_clock += delta
	_show_tuning()
	for i in _strings.size():
		var left := 0.0
		if _ringing.has(i):
			left = float(_ringing[i][1])
		if _shaking.has(i):
			left = maxf(left, float(_shaking[i]))
		_strings[i].position.z = sin(_clock * TAU * SHAKE_HZ + i) * SHAKE * left / RING
		var st := 0.0
		if _ringing.has(i) and wobble != null and wobble.engaged():
			st = wobble.semitones
		elif _shaking.has(i):
			st = _their_bend
		var bowed := st / Wobble.BEND_MOST * BOW_MOST
		if bowed != _bows[i]:
			_bows[i] = bowed
			_gut[i].set_shader_parameter(&"bow", bowed)


# --- the octave ---------------------------------------------------------------------------------

## The strings an octave up (`way` 1) or down (-1), up to MOST_OCTAVES: whether they moved.
func move_octave(way: int) -> bool:
	var to := clampi(shift + way, -MOST_OCTAVES, MOST_OCTAVES)
	if to == shift:
		return false
	shift = to
	value = float(shift + MOST_OCTAVES) / float(MOST_OCTAVES * 2)
	_show_tuning(true)
	return true


## The wheel and the thumbstick move the octave, a notch an octave. Taken at the end of the
## range too, so the wheel at the top does not fall through to zooming the camera.
func _on_nudge(notches: int, _fine: bool) -> bool:
	for k in absi(notches):
		move_octave(signi(notches))
	return true


## The shift in words, as the crown says it.
func shift_text() -> String:
	return "%+d OCT" % shift if shift != 0 else "0 OCT"


# --- a bandmate's harp --------------------------------------------------------------------------

## A bandmate's harp note, as Session.note_played says it (Presence routes them here by source):
## out of the harp, on a synth of its own. Kept by who played it and the pitch, so their note-off
## finds its own note however the holds table has moved since: a pluck's hold is over before
## its string stops ringing.
func heard(peer: int, kind: int, pitch: int, velocity: int) -> void:
	var key := Vector2i(peer, pitch)
	match kind:
		Session.Note.ON:
			_voice().note_on(pitch, velocity)
			_theirs[key] = true
			var i := tuning().find(pitch)
			if i >= 0:
				_shaking[i] = RING
		Session.Note.OFF:
			if not _theirs.has(key):
				return
			_theirs.erase(key)
			if room != null and not _theirs.keys().any(func(k: Vector2i) -> bool: return k.y == pitch):
				room.note_off(pitch)
			if room != null and peer == _wheel_peer and not _sounding_for(peer):
				# Their last harp note let go: their wheel rests, here as on their end.
				room.rest_controls()
				_wheel_peer = 0
				_their_bend = 0.0


## A bandmate's control on their harp notes, as Session.control_played says it (Presence routes
## them here by source): on the one synth every bandmate's harp notes play on here, while they
## have one sounding (as TheirKeys.control has it). The latest to move one has the synth's wheel
## (`_wheel_peer`) until their own last harp note lets go, when it rests: another bandmate's
## note-off does not take it back to rest under them.
func heard_control(peer: int, kind: int, value: int) -> void:
	if room != null and _sounding_for(peer):
		_wheel_peer = peer
		room.control(kind, value)
		if kind == DawKitClip.PITCH_BEND:
			_their_bend = Wobble.semitones_of(value)


## Whether any of `peer`'s harp notes is sounding here.
func _sounding_for(peer: int) -> bool:
	return _theirs.keys().any(func(k: Vector2i) -> bool: return k.x == peer)


## Whether a bandmate's `pitch` is sounding out of the harp (any bandmate's, or `peer`'s).
func sounding(pitch: int, peer := 0) -> bool:
	if peer != 0:
		return _theirs.has(Vector2i(peer, pitch))
	return _theirs.keys().any(func(k: Vector2i) -> bool: return k.y == pitch)


## Everything `peer` had sounding let go: they left, or the session ended (0, everyone's).
func forget(peer := 0) -> void:
	for key: Vector2i in _theirs.keys():
		if peer == 0 or key.x == peer:
			heard(key.x, Session.Note.OFF, key.y, 0)


## Gone from the room (the venue changed, the studio closed): nothing it was playing goes on.
func _exit_tree() -> void:
	silence()
	forget()


func _voice() -> MonitorSynth:
	if room == null:
		room = MonitorSynth.new()
		room.volume_db = -4.0
	if room.get_parent() == null:
		room.name = "Room"
		room.allow_native = false
		room.speaker = self
		add_child(room)
		room.start()
	return room


# --- saying what it is --------------------------------------------------------------------------

func _default_title() -> String:
	return "CHORD HARP"


## `Am (A minor), bar 2 of 4`: the chord, its key, and where in the progression the song is.
func _default_readout() -> String:
	var seconds := _now()
	var h := harmony_at(seconds)
	var shaped := ChordHand.mine
	if shaped != null and is_instance_valid(shaped) and shaped.holds():
		# Under a chord shape: its chord, as yours, not the song's bar.
		var song := Harmony.at(DAW.state, seconds)
		return "%s, your %s (%s)" % [h.chord_name, ChordHand.numeral_of(song, shaped.degree, shaped.seventh),
				h.key_name if h.named else "NO KEY SET"]
	if shaped != null and is_instance_valid(shaped) and shaped.plays_theirs():
		# A bandmate's chord hand down a jack into this player: theirs, and whose.
		var song := Harmony.at(DAW.state, seconds)
		return "%s, %s's %s (%s)" % [h.chord_name, Session.name_of(shaped.their_player()),
				ChordHand.numeral_named(song, h.chord_name), h.key_name if h.named else "NO KEY SET"]
	if not h.named:
		return "%s, NO KEY SET" % h.chord_name
	var said := "%s (%s)" % [h.chord_name, h.key_name]
	var n := h.progression.size()
	if n > 1 and DAW.state != null:
		var first := _bracket_bar(seconds)
		var now := floori(DAW.state.bar_at(seconds) + Harmony.BAR_SLACK)
		said += ", bar %d of %d" % [posmod(now - first, n) + 1, n]
	return said


## The bar the bracket sounding at `seconds` was written in: where its progression counts from.
func _bracket_bar(seconds: float) -> int:
	var times: Array = DAW.state.markers.keys()
	times.sort()
	var from := 0.0
	for t in times:
		if float(t) > seconds + Harmony.AT_SLACK:
			break
		if Harmony.parse(str(DAW.state.markers[t])) != null:
			from = float(t)
	return floori(DAW.state.bar_at(from) + Harmony.BAR_SLACK)


func hint() -> String:
	return "click a string to pluck  ·  drag across to strum  ·  wheel or 8va for the octave\nwiggle over a ringing string to wobble  ·  Alt + mouse up or down bends  ·  C, then 1 to 7: chords"


## The crown's chord and shift, and each string's note at its top, from the tuning now.
func _show_tuning(force := false) -> void:
	if _chord_label == null:
		return
	var seconds := _now()
	var pitches := tuning_at(seconds)
	var shaped := ChordHand.mine
	var from := shaped.crown_text(Harmony.at(DAW.state, seconds)) \
			if shaped != null and is_instance_valid(shaped) else ""
	if not force and pitches == _shown and from == _crown:
		return
	_shown = pitches
	_crown = from
	var h := harmony_at(seconds)
	_chord_label.text = from if from != "" else (h.chord_name if h.named else "NO KEY SET")
	Lettering.fit(_chord_label, CROWN_TEXT_WIDE, 160, 48)
	_shift_label.text = shift_text()
	for i in mini(_notes.size(), pitches.size()):
		_notes[i].text = h.note_name(pitches[i])


## A button on the crown that moves the strings an octave: `8va UP` or `8va DOWN`. Its own
## control, small, so a fingertip can press it, a ray click it and a gaze dwell on it.
class OctaveButton extends ControlAffordance:
	var harp: ChordHarp
	## 1 up, -1 down.
	var way := 1
	## As big as the crown has room for: from the seat across the room it is still a target a
	## cursor can rest on (the seat audit's SEAT_MIN_PIXELS).
	const SIZE := Vector3(0.08, 0.07, 0.02)

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = SIZE
		shape.shape = box
		shape.position = Vector3(0, 0, SIZE.z * 0.5)
		add_child(shape)
		var cap := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(SIZE.x - 0.008, SIZE.y - 0.008, 0.01)
		cap.mesh = mesh
		cap.position = Vector3(0, 0, 0.005)
		# A dark key with light lettering, as the crown's: the lettering is unshaded, so it reads
		# however the corner is lit.
		cap.material_override = ChordHarp._paint(Color(0.16, 0.12, 0.08), 0.4, 0.5)
		add_child(cap)
		var legend := Label3D.new()
		legend.text = "8va\n%s" % ("UP" if way > 0 else "DOWN")
		legend.font_size = 64
		legend.pixel_size = 0.00022
		legend.position = Vector3(0, 0, 0.0115)
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		legend.modulate = Color(0.95, 0.9, 0.78)
		Lettering.range_to_legibility(legend)
		add_child(legend)

	func _default_title() -> String:
		return "CHORD HARP  8va %s" % ("UP" if way > 0 else "DOWN")

	func _default_readout() -> String:
		return harp.shift_text() if harp != null else ""

	func hint() -> String:
		return "press for the strings an octave %s, at most two" % ("up" if way > 0 else "down")

	func dwell_activates() -> bool:
		return true

	## The octave is this player's own: a bandmate's harp is not moved by it, so nobody else is
	## told this button is held.
	func personal() -> bool:
		return true

	func _on_grab_begin(_at: Vector3) -> void:
		if harp != null:
			harp.move_octave(way)

	func _on_nudge(notches: int, fine: bool) -> bool:
		return harp != null and harp._on_nudge(notches, fine)
