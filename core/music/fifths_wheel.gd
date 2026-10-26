class_name FifthsWheel
extends ControlAffordance

## A circle-of-fifths wheel on the bricks table (docs/spatial_loop.md slice 9; idea #29): where
## the song's key and chords are written from the room, not typed on the 2D ruler.
##
## Its outer ring is the twelve major chords in fifths order, C at the top and G clockwise from
## it; the inner ring is their relative minors. The key's seven chords (`Harmony.diatonic`) stand
## raised: three majors and three minors round the key, and its diminished chord, lettered so,
## on the inner ring two steps clockwise of the key. The others are lower and dimmed, and are
## lettered all the same. The chords that lead well on from the last one pressed
## (`Harmony.follows`) rise further and breathe (Ergonomics.motion_scale; held still for anyone who
## asked for no motion, and still higher). Nothing here is told by colour alone.
##
## Pressing a segment plays its chord on this player's keys (`keys`, GuestMidi), source
## `&"wheel"`, for RING seconds, and adds it to the strip of up to STRIP_MOST bar tiles along the
## bottom of the board. The hub (this control itself) turns the key by fifths: twist a hand on
## it, drag round it with a mouse or a fingertip, the wheel or the thumbstick as a nudge, or the
## two arrow buttons on it. Its middle swaps major and minor: C major and A minor, the relative
## pair, so the same seven stay raised. CLEAR empties the strip.
##
## SET writes `[key: strip]` into the song's markers at one bar: the bar after the playhead's
## while the song plays (as this player hears it, GuestMidi.song), and the playhead's own while
## it is stopped (`target_bar`). A marker already at that bar gets the brackets (Harmony.written,
## DAW.edit_marker); otherwise a marker that is only brackets is added there (DAW.add_marker).
## Either way it is one undo step, and the harmony before that bar is untouched: the new chords
## count from it, and the old ones come back only at the next bracket after it, as any bracket's
## do. A guest's SET is a room ask, `harmony` [bar, inside], carrying the bar the guest chose; the
## host writes it there (`answer`) and the markers replicate to everyone.
##
## Each segment's hover card names it (`F · IV of C major · follows well`), and SET's says where
## it will write.

## What the wheel's notes say they came from (Session.send_note's `source`), and the name it
## goes by in GuestMidi.instruments.
const SOURCE := &"wheel"
## The room ask a guest's SET is (Session.ROOM_VERBS): [bar, the brackets' inside].
const VERB := &"harmony"
## The most bars the strip holds, and the furthest bar a SET may name.
const STRIP_MOST := 8
const BAR_MOST := 100000
## How long a pressed chord sounds (s), how hard, and where it is voiced (Harmony.voiced).
const RING := 0.6
const VELOCITY := 90
const CENTRE := 60
const OUTER := 0
const INNER := 1
## The outer ring's majors in fifths order from C at the top, and the inner ring's minors'
## roots under them, as the wheel letters them when the key does not spell them its own way.
const MAJORS := ["C", "G", "D", "A", "E", "B", "F#", "Db", "Ab", "Eb", "Bb", "F"]
const MINORS := ["A", "E", "B", "F#", "C#", "G#", "D#", "Bb", "F", "C", "G", "D"]

## The rings' radii (m): the outer ring's rim, where the two rings meet, and the hub's edge.
const R_OUT := 0.3
const R_MID := 0.205
const R_HUB := 0.12
## Each segment is a block this deep, sunk into the board so only its top stands proud of it: by
## LOW out of the key, IN_KEY in it, and RISEN when it follows well, breathing BREATH either way
## at BREATH_HZ.
const DEPTH := 0.03
const LOW := 0.005
const IN_KEY := 0.016
const RISEN := 0.028
const BREATH := 0.003
const BREATH_HZ := 0.5
## The board the wheel is on, leant back LEAN from upright on the table like a music stand: its
## size, and how far up it from its bottom edge the wheel's middle is.
const BOARD := Vector3(0.9, 0.84, 0.025)
const LEAN := 0.4363
const CENTRE_Y := 0.48
## The strip's row, under the wheel, in the wheel's frame; each tile's size and spacing.
const STRIP_Y := -0.405
const TILE := Vector2(0.066, 0.062)
const TILE_STEP := 0.075
## Its plaque (Stations.plaque) hangs on the table's end under the board, facing whoever stands
## there: this far below the table top.
const PLAQUE_DROP := 0.12

## Where its notes are played: this player's keys. Session.guest_midi unless told otherwise.
var keys: GuestMidi = null
## The key: how many fifths clockwise of C the key's major is (its relative major for a minor
## key), and whether it is the minor.
var turn := 0
var minor := false
## The chords pressed, one a bar, in order: what SET writes after the key.
var strip := PackedStringArray()
## The chord pressed last: what the follow-ups are of. "" before any.
var last := ""
## The last SET a guest sent the host, as [VERB, [bar, inside]]; empty before one.
var asked: Array = []

## [outer segments, inner segments], each by fifths index.
var _segments: Array = [[], []]
var _tiles: Array[MeshInstance3D] = []
var _tile_letters: Array[Label3D] = []
var _pointer: Node3D
var _swap: WheelButton
var _set: WheelButton
## The pitches the last press has sounding, and how long until they are let go.
var _sounding := PackedInt32Array()
var _left := 0.0
var _clock := 0.0
## The hub's turn so far while held: where the hand's twist or the contact's angle round the
## middle began, and how many fifths it has turned the key since.
var _grab_twist := NAN
var _grab_angle := 0.0
var _grab_steps := 0


## Its frame on the table from where it stands (Venue.wheel_spot: the board's bottom edge, facing
## whoever stands at it): lifted a hair so the leant board's back edge clears the top, leant
## back, and up the board to the wheel's middle. The control's own plane is the wheel's face, so
## a held ray stays in it (Interactor._plane_point).
static func on_stand(spot: Transform3D) -> Transform3D:
	return spot * Transform3D(Basis.IDENTITY, Vector3(0, 0.012, 0)) \
			* Transform3D(Basis(Vector3.RIGHT, -LEAN), Vector3.ZERO) \
			* Transform3D(Basis.IDENTITY, Vector3(0, CENTRE_Y, 0))


## The middle of segment `i` of `ring` on the wheel's face, as an angle clockwise from the top.
static func angle_of(i: int) -> float:
	return i * TAU / 12.0


func _init() -> void:
	name = "FifthsWheel"


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	if keys == null:
		keys = Session.guest_midi
	_adopt_the_songs_key()
	# What a hand finds of the hub: a thin square over it, under the buttons on it.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(R_HUB * 1.4, R_HUB * 1.4, 0.012)
	shape.shape = box
	shape.position = Vector3(0, 0, 0.006)
	add_child(shape)
	_build_board()
	_lamp()
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var disc := CylinderMesh.new()
	disc.top_radius = R_HUB - 0.004
	disc.bottom_radius = R_HUB - 0.004
	disc.height = 0.012
	disc.radial_segments = 48
	hub.mesh = disc
	hub.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.006))
	hub.material_override = _paint(Color(0.14, 0.11, 0.09), 0.45, 0.3)
	add_child(hub)
	# The pointer: a notch on the hub's rim, toward the key's own segment.
	_pointer = Node3D.new()
	_pointer.name = "Pointer"
	add_child(_pointer)
	ZoneKit.block(_pointer, Vector3(0.012, 0.022, 0.006), Vector3(0, R_HUB - 0.016, 0.014),
			_paint(Color(0.95, 0.9, 0.78), 0.4), "Notch")
	for ring in [OUTER, INNER]:
		for i in 12:
			var segment := Segment.new()
			segment.wheel = self
			segment.ring = ring
			segment.index = i
			add_child(segment)
			_segments[ring].append(segment)
	_swap = _button("", Vector3(0, 0.004, 0), Vector2(0.11, 0.058), 30, _swap_mode)
	_swap.titled = "FIFTHS WHEEL  MAJOR / MINOR"
	_swap.says = func() -> String: return "%s, press for %s" % [key_text(), _key_text(turn, not minor)]
	_swap.hinted = "press the middle to swap major and its relative minor"
	var down := _button("<", Vector3(-0.048, -0.064, 0), Vector2(0.055, 0.05), 40, turn_by.bind(-1))
	down.titled = "FIFTHS WHEEL  A FIFTH DOWN"
	down.says = func() -> String: return "to %s" % _key_text(posmod(turn - 1, 12), minor)
	down.hinted = "press to turn the key a fifth down, toward the flats"
	var up := _button(">", Vector3(0.048, -0.064, 0), Vector2(0.055, 0.05), 40, turn_by.bind(1))
	up.titled = "FIFTHS WHEEL  A FIFTH UP"
	up.says = func() -> String: return "to %s" % _key_text(posmod(turn + 1, 12), minor)
	up.hinted = "press to turn the key a fifth up, toward the sharps"
	for b in STRIP_MOST:
		var x := (b - (STRIP_MOST - 1) * 0.5) * TILE_STEP
		var tile := ZoneKit.block(self, Vector3(TILE.x, TILE.y, DEPTH), Vector3(x, STRIP_Y, 0),
				_paint(Color(0.82, 0.74, 0.6), 0.55), "Bar%d" % (b + 1))
		_tiles.append(tile)
		var number := _letter(self, 14, Vector3(x, STRIP_Y + TILE.y * 0.5 + 0.012, 0.002), Color(0.9, 0.86, 0.78))
		number.text = str(b + 1)
		var chord := _letter(tile, 26, Vector3(0, 0, DEPTH * 0.5 + 0.001), Color(0.1, 0.08, 0.06))
		_tile_letters.append(chord)
	var clear := _button("CLEAR", Vector3(-0.375, STRIP_Y, 0), Vector2(0.1, 0.062), 22, clear_strip)
	clear.titled = "FIFTHS WHEEL  CLEAR"
	clear.says = func() -> String: return "the strip: %s" % " ".join(strip) if not strip.is_empty() else "the strip is empty"
	clear.hinted = "press to empty the strip"
	_set = _button("SET", Vector3(0.375, STRIP_Y, 0), Vector2(0.1, 0.062), 30, set_harmony)
	_set.titled = "FIFTHS WHEEL  SET"
	_set.says = set_text
	_set.hinted = "press to write the key and the strip into the song from that bar"
	# In the stand's frame (Venue.wheel_spot), out past the board's bottom edge to the table's end.
	var plaque := Stations.plaque(&"wheel")
	var stand := on_stand(Transform3D.IDENTITY).affine_inverse()
	plaque.transform = stand * Transform3D(Basis.IDENTITY, Vector3(0, -PLAQUE_DROP, Venue.WHEEL_IN + 0.006))
	add_child(plaque)
	_show()


## The board, its ledge along the bottom and the strut behind it down to the table, all in the
## wheel's frame.
func _build_board() -> void:
	var wood := _paint(Color(0.32, 0.2, 0.11), 0.55, 0.0, 0.3)
	var bottom := -CENTRE_Y
	ZoneKit.block(self, BOARD, Vector3(0, bottom + BOARD.y * 0.5, -BOARD.z * 0.5), wood, "Board")
	# A hair wider than the board, so no end of one lies in an end of the other.
	ZoneKit.block(self, Vector3(BOARD.x + 0.012, 0.03, 0.05), Vector3(0, bottom + 0.012, 0.022), wood, "Ledge")
	# From the board's back two thirds of the way up, straight back and down to the table.
	var top := Vector3(0, bottom + BOARD.y * 0.66, -BOARD.z)
	var lean := Basis(Vector3.RIGHT, -LEAN)
	# The table, in this frame: the plane the board's bottom edge stands on, 12 mm below it.
	var up := lean.inverse() * Vector3.UP
	var away := lean.inverse() * Vector3.FORWARD
	var foot_at := Vector3(0, bottom, 0) - up * 0.012
	var drop := (top - foot_at).dot(up)
	var foot := top - up * drop + away * 0.16
	var along := (foot - top)
	var strut := ZoneKit.block(self, Vector3(0.05, along.length(), 0.02), (top + foot) * 0.5,
			Materials.brushed_metal(), "Strut")
	var y := along.normalized()
	var x := Vector3.RIGHT
	strut.basis = Basis(x, y, x.cross(y).normalized())


## A reading lamp on an arm out from the board's top, down onto the wheel: the board leans back
## from a table lit from above, so its face would otherwise be in its own shade. A SpotLight3D,
## as the harp's, not an OmniLight.
func _lamp() -> void:
	var warm := Color(1.0, 0.84, 0.64)
	var top := BOARD.y - CENTRE_Y
	var at := Vector3(0, top + 0.02, 0.3)
	ZoneKit.block(self, Vector3(0.008, 0.008, 0.29), Vector3(0, top + 0.02, 0.145), Materials.brushed_metal(), "LampArm")
	var strip := ZoneKit.block(self, Vector3(0.18, 0.03, 0.012), at, ZoneKit.glow(warm, 3.0), "LampStrip")
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := SpotLight3D.new()
	light.name = "WheelLight"
	light.light_color = warm
	light.light_energy = 0.9
	light.spot_range = 1.6
	# Wide enough for the strip and its buttons under the wheel as well.
	light.spot_angle = 62.0
	light.spot_attenuation = 0.8
	light.shadow_enabled = false
	light.transform = Transform3D(Basis.looking_at(Vector3(0, -0.12, 0) - at, Vector3.UP), at)
	add_child(light)


func _button(legend: String, at: Vector3, size: Vector2, font: int, pressed: Callable) -> WheelButton:
	var b := WheelButton.new()
	b.legend = legend
	b.size = size
	b.font = font
	b.pressed = pressed
	b.position = at
	add_child(b)
	return b


func _letter(parent: Node3D, size: int, at: Vector3, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.font_size = size * 4
	l.pixel_size = 0.00025
	l.position = at
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate = colour
	l.outline_size = 0
	Lettering.range_to_legibility(l)
	parent.add_child(l)
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


# --- the key ------------------------------------------------------------------------------------

## The key as the song's brackets say it: "C major", "A minor".
func key_text() -> String:
	return _key_text(turn, minor)


static func _key_text(at: int, is_minor: bool) -> String:
	return "%s minor" % MINORS[at] if is_minor else "%s major" % MAJORS[at]


## The key, as Harmony reads it.
func key() -> Harmony:
	return Harmony.parse("[%s]" % key_text())


## The song's key where it is now, when it is a major or a minor one: what the wheel starts in.
func _adopt_the_songs_key() -> void:
	var h := Harmony.at(DAW.state, _moment()[0]) if DAW.state != null else Harmony.NONE
	if not h.named or not h.mode in ["major", "minor"]:
		return
	minor = h.mode == "minor"
	turn = ((h.root + (3 if minor else 0)) * 7) % 12


## The key `steps` fifths round, clockwise (toward the sharps) for more than 0.
func turn_by(steps: int) -> void:
	if steps == 0:
		return
	turn = posmod(turn + steps, 12)
	value = turn / 12.0
	_show()


## Major for its relative minor, or back.
func _swap_mode() -> void:
	minor = not minor
	_show()


## Whether segment `i` of `ring` is one of the key's seven.
func in_key(ring: int, i: int) -> bool:
	var d := posmod(i - turn, 12)
	return d in [11, 0, 1] or (ring == INNER and d == 2)


## The chord segment `i` of `ring` stands for: a major outside, its relative minor inside, and
## the key's diminished chord where that is. Spelled as the key spells it when it is one of the
## key's, else as the wheel letters it (MAJORS, MINORS).
func chord_at(ring: int, i: int) -> String:
	var root := (i * 7 + (9 if ring == INNER else 0)) % 12
	var quality := "" if ring == OUTER else ("dim" if posmod(i - turn, 12) == 2 else "m")
	if in_key(ring, i):
		return key().note_name(root, false) + quality
	return (MAJORS[i] if ring == OUTER else MINORS[i]) + quality


## Whether segment `i` of `ring` leads well on from the chord pressed last.
func rises(ring: int, i: int) -> bool:
	if last == "":
		return false
	var tones := Harmony.chord_tones(chord_at(ring, i))
	for said in Harmony.follows(key(), last):
		if Harmony.chord_tones(said) == tones:
			return true
	return false


## What a segment is, in words: `F · IV of C major · follows well`.
func segment_text(ring: int, i: int) -> String:
	var chord := chord_at(ring, i)
	var k := key()
	var role := k.numeral(chord)
	var said := "%s · %s of %s" % [chord, role, k.key_name] if role != "" else "%s · out of %s" % [chord, k.key_name]
	if rises(ring, i):
		said += " · follows well"
	return said


# --- playing it ---------------------------------------------------------------------------------

## [the song position a chord played now takes, and whether the song is playing to it], from one
## read of the keys' clock, as the harp has it.
func _moment() -> Array:
	var song := keys.song() if keys != null else -1.0
	if song >= 0.0:
		return [song, true]
	return [DAW.state.position_seconds if DAW.state != null else 0.0, false]


## A segment pressed: its chord played, put on the end of the strip if there is room, and the
## follow-ups from it raised.
func press(ring: int, i: int) -> void:
	var chord := chord_at(ring, i)
	play(chord)
	if strip.size() < STRIP_MOST:
		strip.append(chord)
	last = chord
	_show()


## `chord` played on this player's keys for RING seconds, voiced at CENTRE, with source
## SOURCE. What was still sounding from the last press is let go first.
func play(chord: String) -> void:
	silence()
	var h := Harmony.parse("[%s: %s]" % [key_text(), chord])
	if h == null or keys == null:
		return
	var moment := _moment()
	var at: float = moment[0] if moment[1] else NAN
	_sounding = Harmony.voiced(h, CENTRE, 4)
	_left = RING
	for pitch in _sounding:
		keys.note_on(pitch, VELOCITY, 0, 0.0, false, SOURCE, at)


## Whatever the last press has sounding, let go now.
func silence() -> void:
	if keys != null:
		for pitch in _sounding:
			keys.note_off(pitch, 0, 0.0, false, SOURCE)
	_sounding = PackedInt32Array()


## Whether a chord pressed here is still sounding.
func sounding() -> bool:
	return not _sounding.is_empty()


## Whether a hand here is on the wheel or over it: the hub, a segment or a button.
func touched() -> bool:
	if is_hovered() or is_held():
		return true
	for child in get_children():
		var c := child as ControlAffordance
		if c != null and (c.is_hovered() or c.is_held()):
			return true
	return false


func clear_strip() -> void:
	strip = PackedStringArray()
	last = ""
	_show()


func _process(delta: float) -> void:
	_clock += delta
	if not _sounding.is_empty():
		_left -= delta
		if _left <= 0.0:
			silence()
	var breath := sin(_clock * TAU * BREATH_HZ) * BREATH * Ergonomics.current.motion_scale
	for ring in [OUTER, INNER]:
		for segment: Segment in _segments[ring]:
			segment.stand(segment.height + (breath if segment.risen else 0.0))


func _exit_tree() -> void:
	silence()


# --- writing it ---------------------------------------------------------------------------------

## The bar SET writes at, counted as MixState.bar_at counts (0 is the first): the bar after the
## one the song is heard in while it plays, so the change lands on a bar line still to come; the
## playhead's own bar while it is stopped.
func target_bar() -> int:
	var s := DAW.state
	if s == null:
		return 0
	var moment := _moment()
	var bar := floori(s.bar_at(moment[0]) + Harmony.BAR_SLACK)
	return bar + 1 if moment[1] else bar


## What SET writes inside the brackets: the key, and the strip's chords after a colon.
func inside_text() -> String:
	return key_text() if strip.is_empty() else "%s: %s" % [key_text(), " ".join(strip)]


## SET's hover card: what it writes and at which bar (as the tape deck counts them, from 1).
func set_text() -> String:
	var playing: bool = _moment()[1]
	return "[%s] at bar %d, %s" % [inside_text(), target_bar() + 1, "the next one" if playing else "where the playhead is"]


## SET: the key and the strip written into the song at `target_bar`. Here on the host (or alone);
## asked of the host, with the bar, from a guest.
func set_harmony() -> void:
	var bar := target_bar()
	var inside := inside_text()
	if Session.is_authority():
		var named := write(bar, inside)
		if named != "":
			Session.notice.emit("The song is in %s from bar %d." % [inside, bar + 1])
		return
	asked = [VERB, [bar, inside]]
	Session.ask_room(VERB, [bar, inside])
	Session.notice.emit("Asked the host to put the song in %s from bar %d." % [inside, bar + 1])


## The host's word on a SET, a guest's (Session.room_asked) or its own: `inside` written at
## `bar` if it reads as a key and the bar is one there can be. What the marker is called now, or
## "" when refused.
static func answer(bar: int, inside: String) -> String:
	if bar < 0 or bar > BAR_MOST:
		return ""
	return write(bar, inside)


## `[inside]` written into the markers at the start of `bar`: onto a marker already there
## (Harmony.written, so its section stays and any brackets it had are replaced), or as a marker
## that is only brackets. One undo step either way, and nothing before the bar changes. What the
## marker is called now, "" when `inside` is not a key.
static func write(bar: int, inside: String) -> String:
	var h := Harmony.parse("[%s]" % inside)
	var s := DAW.state
	if h == null or s == null or bar < 0:
		return ""
	var at := s.bar_to_seconds(bar + 1.0)
	var there := DAWBackend.marker_key(s.markers, at)
	if is_nan(there):
		var added := Harmony.written("", h)
		DAW.add_marker(at, added)
		return added
	var named := Harmony.written(str(s.markers[there]), h)
	DAW.edit_marker(there, there, named)
	return named


# --- showing it ---------------------------------------------------------------------------------

## Each segment's height, letters and finish, the hub's pointer and key, and the strip, from the
## key, the strip and the chord pressed last.
func _show() -> void:
	if _pointer == null:
		return
	# Clockwise to the key's own segment, outer or inner: the same twelfth either way.
	_pointer.basis = Basis(Vector3.BACK, -angle_of(turn))
	for ring in [OUTER, INNER]:
		for i in 12:
			var segment: Segment = _segments[ring][i]
			var ours := in_key(ring, i)
			segment.risen = rises(ring, i)
			segment.height = RISEN if segment.risen else (IN_KEY if ours else LOW)
			segment.show_as(chord_at(ring, i), ours, segment.risen)
			segment.stand(segment.height)
	_swap.relabel("%s\n%s" % [(MINORS[turn] if minor else MAJORS[turn]), "minor" if minor else "major"])
	for b in STRIP_MOST:
		var filled := b < strip.size()
		_tile_letters[b].text = strip[b] if filled else ""
		# A filled bar stands proud of the board; an empty one lies nearly flat in it.
		_tiles[b].position.z = 0.012 - DEPTH * 0.5 if filled else 0.003 - DEPTH * 0.5


func _default_title() -> String:
	return "FIFTHS WHEEL  KEY"


func _default_readout() -> String:
	return key_text()


func hint() -> String:
	return "twist, drag round, or wheel to turn the key by fifths  ·  press the middle for major or minor"


## The key's own: a bandmate's wheel is not turned by it, so nobody else is told it is held.
func personal() -> bool:
	return true


# --- turning the hub ----------------------------------------------------------------------------

func _on_grab_begin(at: Vector3) -> void:
	_grab_steps = 0
	_grab_twist = NAN
	_grab_angle = _angle_at(at)
	if held_by is Interactor and not (held_by as Interactor).touches_directly():
		_grab_twist = (held_by as Interactor).twist()


## Turned by turning the hand, a fifth a twelfth of a turn, clockwise sharpward; a mouse or a
## fingertip, which cannot twist, by going round the middle.
func _on_grab_move(at: Vector3) -> void:
	var turned: float
	if not is_nan(_grab_twist):
		turned = (held_by as Interactor).twist() - _grab_twist
	else:
		turned = wrapf(_angle_at(at) - _grab_angle, -PI, PI)
	var steps := roundi(turned / (TAU / 12.0))
	if steps != _grab_steps:
		turn_by(steps - _grab_steps)
		_grab_steps = steps
		if is_nan(_grab_twist) and absi(steps) >= 6:
			# Half way round: start counting again from here, so wrapping never jumps back.
			_grab_angle = _angle_at(at)
			_grab_steps = 0


## Where `at` is round the wheel's middle, clockwise from the top, as the person facing it sees it.
func _angle_at(at: Vector3) -> float:
	var p := to_local(at)
	return atan2(p.x, p.y)


## The wheel and the thumbstick turn the key, a notch a fifth.
func _on_nudge(notches: int, _fine: bool) -> bool:
	turn_by(notches)
	return true


## One chord of the wheel: a block in the shape of its twelfth of a ring, sunk in the board as far
## as its standing says. Its own control, so each has a hover card and a press of its own.
class Segment extends ControlAffordance:
	var wheel: FifthsWheel
	var ring := FifthsWheel.OUTER
	var index := 0
	## How far it stands proud of the board, before any breath; and whether it is risen.
	var height := FifthsWheel.LOW
	var risen := false
	var _top: StandardMaterial3D
	var _letters: Label3D

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		name = "%s%d" % ["Outer" if ring == FifthsWheel.OUTER else "Inner", index]
		var r0 := FifthsWheel.R_MID + 0.003 if ring == FifthsWheel.OUTER else FifthsWheel.R_HUB + 0.003
		var r1 := FifthsWheel.R_OUT if ring == FifthsWheel.OUTER else FifthsWheel.R_MID - 0.003
		var gap := 0.003
		var a := FifthsWheel.angle_of(index)
		var a0 := a - PI / 12.0 + gap / r1
		var a1 := a + PI / 12.0 - gap / r1
		var mid := (r0 + r1) * 0.5
		# The shape is placed at the segment's own middle, not the wheel's, so that is where a ray
		# aimed at it goes.
		var centre := Vector3(sin(a) * mid, cos(a) * mid, 0)
		var points := PackedVector3Array()
		for k in 7:
			var t := lerpf(a0, a1, k / 6.0)
			for r in [r0, r1]:
				for z in [-FifthsWheel.DEPTH, 0.0]:
					points.append(Vector3(sin(t) * r, cos(t) * r, z) - centre)
		var shape := CollisionShape3D.new()
		var hull := ConvexPolygonShape3D.new()
		hull.points = points
		shape.shape = hull
		shape.position = centre
		add_child(shape)
		var look := MeshInstance3D.new()
		look.name = "Look"
		look.mesh = FifthsWheel.sector_mesh(r0, r1, a0, a1, FifthsWheel.DEPTH)
		_top = FifthsWheel._paint(Color(0.85, 0.78, 0.62), 0.5)
		look.material_override = _top
		add_child(look)
		_letters = Label3D.new()
		_letters.font_size = (34 if ring == FifthsWheel.OUTER else 24) * 4
		_letters.pixel_size = 0.00025
		_letters.position = Vector3(sin(a) * mid, cos(a) * mid, 0.0012)
		_letters.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_letters.outline_size = 0
		Lettering.range_to_legibility(_letters)
		add_child(_letters)

	## Stood `proud` of the board.
	func stand(proud: float) -> void:
		position.z = proud

	## Lettered `chord`; light and raised in the key, dark and low out of it.
	func show_as(chord: String, ours: bool, up: bool) -> void:
		if _letters == null:
			return
		_letters.text = chord
		var base := Color(0.72, 0.63, 0.47) if ring == FifthsWheel.OUTER else Color(0.62, 0.53, 0.39)
		# Risen is light whether it is in the key or not (the V of the next is not), so its dark
		# letters read.
		if up:
			base = base.lightened(0.12)
		elif not ours:
			base = base.darkened(0.55)
		_top.albedo_color = base
		_letters.modulate = Color(0.04, 0.03, 0.02) if ours or up else Color(0.86, 0.82, 0.74)

	func _default_title() -> String:
		return "FIFTHS WHEEL  %s" % (wheel.chord_at(ring, index) if wheel != null else "")

	func _default_readout() -> String:
		return wheel.segment_text(ring, index) if wheel != null else ""

	func hint() -> String:
		return "press to play it and add it to the strip"

	func dwell_activates() -> bool:
		return true

	func personal() -> bool:
		return true

	func _on_grab_begin(_at: Vector3) -> void:
		if wheel != null:
			wheel.press(ring, index)

	## The wheel over a segment turns the key, as over the hub.
	func _on_nudge(notches: int, fine: bool) -> bool:
		return wheel != null and wheel._on_nudge(notches, fine)


## A twelfth of a ring from `r0` to `r1` and from angle `a0` to `a1` (clockwise from the top), a
## block from -`depth` to 0 with its top facing +Z: its top, its two arcs and its two ends.
static func sector_mesh(r0: float, r1: float, a0: float, a1: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 6
	var at := func(r: float, a: float, z: float) -> Vector3: return Vector3(sin(a) * r, cos(a) * r, z)
	for k in n:
		var t0 := lerpf(a0, a1, k / float(n))
		var t1 := lerpf(a0, a1, (k + 1) / float(n))
		_quad(st, [at.call(r0, t0, 0.0), at.call(r1, t0, 0.0), at.call(r1, t1, 0.0), at.call(r0, t1, 0.0)],
				[Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
		var out0 := Vector3(sin(t0), cos(t0), 0)
		var out1 := Vector3(sin(t1), cos(t1), 0)
		_quad(st, [at.call(r1, t1, 0.0), at.call(r1, t0, 0.0), at.call(r1, t0, -depth), at.call(r1, t1, -depth)],
				[out1, out0, out0, out1])
		_quad(st, [at.call(r0, t0, 0.0), at.call(r0, t1, 0.0), at.call(r0, t1, -depth), at.call(r0, t0, -depth)],
				[-out0, -out1, -out1, -out0])
	var start := -Vector3(cos(a0), -sin(a0), 0)
	_quad(st, [at.call(r1, a0, 0.0), at.call(r0, a0, 0.0), at.call(r0, a0, -depth), at.call(r1, a0, -depth)],
			[start, start, start, start])
	var end := Vector3(cos(a1), -sin(a1), 0)
	_quad(st, [at.call(r0, a1, 0.0), at.call(r1, a1, 0.0), at.call(r1, a1, -depth), at.call(r0, a1, -depth)],
			[end, end, end, end])
	return st.commit()


## Corners in clockwise order as seen from the side the face faces (Godot's front), each with its
## normal.
static func _quad(st: SurfaceTool, corners: Array, normals: Array) -> void:
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normals[k])
		st.add_vertex(corners[k])


## A button on the wheel's board: the hub's middle and arrows, CLEAR and SET. Small, pressable by
## a fingertip, a ray, a controller and a gaze's dwell; what it does is `pressed`.
class WheelButton extends ControlAffordance:
	var legend := ""
	var size := Vector2(0.05, 0.04)
	var font := 30
	var pressed: Callable = Callable()
	var titled := "FIFTHS WHEEL"
	var says: Callable = Callable()
	var hinted := ""
	var _label: Label3D

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, size.y, 0.02)
		shape.shape = box
		shape.position = Vector3(0, 0, 0.01)
		add_child(shape)
		var cap := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x - 0.006, size.y - 0.006, 0.014)
		cap.mesh = mesh
		cap.position = Vector3(0, 0, 0.007 + 0.006)
		# A dark key with light lettering, as the harp's crown buttons: unshaded lettering reads
		# however the table is lit.
		cap.material_override = FifthsWheel._paint(Color(0.16, 0.12, 0.08), 0.4, 0.5)
		add_child(cap)
		_label = Label3D.new()
		_label.font_size = font * 4
		_label.pixel_size = 0.00022
		_label.position = Vector3(0, 0, 0.0205)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.modulate = Color(0.95, 0.9, 0.78)
		_label.text = legend
		Lettering.range_to_legibility(_label)
		add_child(_label)

	func relabel(text: String) -> void:
		legend = text
		if _label != null:
			_label.text = text

	func _default_title() -> String:
		return titled

	func _default_readout() -> String:
		return says.call() if says.is_valid() else ""

	func hint() -> String:
		return hinted

	func dwell_activates() -> bool:
		return true

	func personal() -> bool:
		return true

	func _on_grab_begin(_at: Vector3) -> void:
		if pressed.is_valid():
			pressed.call()
