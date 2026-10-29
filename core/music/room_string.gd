class_name RoomString
extends ControlAffordance

## A string across the room (docs/spatial_loop.md part two, slice 48; idea #34): stretched between
## any two points, its length sets its pitch, snapped to the song's key. A giant bass string across
## the room, or five short ones by the window.
##
## THE LAW. Its length sets its pitch over four octaves, log in length (`raw_pitch`):
## 76 - 48 * log2(length / 0.3) / log2(40), so SHORTEST (0.3 m) is E5, a metre is about middle C
## and LONGEST (12 m) is E1 (41 Hz), the bottom of a bass. Played, it is snapped to the song's
## scale where the song is (Harmony.snap, `pitch_in`), and never under E1, so no string is
## subsonic, whatever the key. Its note is lettered at its middle, and retuned there as the key
## changes; one still ringing keeps the pitch it was plucked at.
##
## THE ROOM'S. Strings are the room's row `strings` {id: [a, b, maker]} (its two ends in the venue's
## frame, and the peer who tied it), at most MOST, asked with the room verb `string` [id, a, b], a
## and b the same point to cut it. `answer` is the rule: the host keeps it (Studio._answer_string,
## and says why not to whoever asked), and a guest predicts with it. Every machine stands the same
## strings from the row (Studio._show_strings); nothing of a pluck crosses the wire but its notes.
##
## PLAYED as the harp is. A fingertip brushing through it (`tips`: a tip whose path goes past the
## string within TOUCH of it) or a grab (a click, a pinch's ray, a trigger) plucks it; a fingertip's
## poke is its brush, not a grab as well. Its notes are this player's keys (`keys`,
## GuestMidi) with source SOURCE: heard at once on the keys' own synth, sent to everyone, and taken
## down as a take on the armed track. It rings RING, shakes while it does (a brightness instead, at
## Ergonomics motion 0), and bends by the plucking hand's tilt and wobbles by its shake (slice 15):
## one Wobble for every string on this machine (`wobble`), since the strings are one instrument with
## one source, on the hand that plucked last. On a desktop the mouse's wiggle over a ringing string
## is the shake, and Alt with the mouse moving up or down bends. A bandmate's string notes arrive as
## notes and are heard from the string that plays that pitch here (`heard`), which shakes.
##
## CUT. Grab it and pull hard, CUT_PULL off its line (`cut_asked`), or press a knot at either end
## (`Knot`, with its X).
##
## MADE at the spool (`Spool`, station `strings`): its reel gives an end, and the hand that took it
## ties the first end where it next presses and the second where it lets go, or, a press and a
## let-go in one place (a desk's clicks), where it presses again. Where is wherever its ray first
## meets something (`surface_hit`): the gear, the furniture, the floor, the walls, the ceiling.

## What its notes say they came from (Session.send_note's `source`).
const SOURCE := &"string"
## Its station: the spool (Stations.ALL).
const STATION := &"strings"
## The room verb that ties or cuts one, and the room's row of them.
const VERB := &"string"
const ROW := "strings"
## The shortest and longest a string may be (m), and the most a room takes.
const SHORTEST := 0.3
const LONGEST := 12.0
const MOST := 8
## The law's ends: E5 at SHORTEST, E1 at LONGEST, four octaves apart.
const TOP_PITCH := 76
const BOTTOM_PITCH := 28
## How long a plucked string rings before its note is let go (s), unless it is plucked again.
const RING := 2.5
## A grab's pluck, with no sweep to measure; and the softest a brush plays, however slow.
const PLUCK_VELOCITY := 84
const SOFTEST := 50
## A fingertip's path within this of the string (m) crosses it.
const TOUCH := 0.02
## Held, and pulled this far off its line from where it was taken (m), it is cut.
const CUT_PULL := 0.4
## The most it bows toward a hand pulling it (m), and toward a bend, at the middle.
const PULL_SHOWN := 0.2
const BOW_MOST := 0.04
## How far its middle swings while it sounds, fresh from a pluck (m), and how fast. A long string
## swings further and slower, as a real one does.
const SHAKE := 0.006
const SHAKE_HZ := 9.0
## The string's thickness: a short one's radius, a long one's (m). Thick enough to see across the
## room, a bass string thicker than a treble one.
const THIN := 0.0025
const THICK := 0.007
## What a hand finds round it: this far either side of its line (m).
const GRAB := 0.03
## A knot at each end: its radius (m).
const KNOT := 0.024
## Its lettering at the middle: the cap height (m), readable across the room, and how far above
## the string it hangs.
const LETTER_CAP := 0.06
const LETTER_ABOVE := 0.07
## The furthest a ray looks for somewhere to tie (m), and how far from the room's middle an end
## may be at all (m), so a row cannot name a point nobody could reach.
const FAR := 14.0
const BOUND := 40.0

## The spool (Spool, from tools/blender/string_spool.py): its footprint on the floor, half its
## size, its middle on its origin; how tall it stands; its reel's axle; the eyelet the end hangs
## from; the reel's radius and half its length; and where its plaque stands, on an arm off the
## post's front, leant back so a standing player reads it, and how wide it is.
const SPOOL_FOOT := Vector2(0.17, 0.17)
const SPOOL_FOOT_Z := 0.0
const SPOOL_TOP := 1.09
const SPOOL_AXLE := Vector3(0, 1.0, 0)
const SPOOL_EYELET := Vector3(0, 0.93, 0.105)
const SPOOL_RADIUS := 0.085
const SPOOL_HALF := 0.07
const SPOOL_PLAQUE := Vector3(0, 0.62, 0.05)
const SPOOL_PLAQUE_LEAN := 0.3
const SPOOL_PLAQUE_WIDE := 0.5
## Where the plaque's top edge is, on its arm: it hangs down from there, folded or opened.
const SPOOL_PLAQUE_TOP := 0.68
## The station's frame (Stations.ALL): the reel's top, and its plaque's foot, opened.
const SPOOL_FRAME_TOP := Vector3(0, SPOOL_AXLE.y + SPOOL_RADIUS, 0)
const SPOOL_FRAME_FOOT := Vector3(0, 0.3, 0.1)

## Its id in the room's row.
var id := StringName()
## Its ends, in its parent's frame (the venue's), as the row has them, and who tied it.
var a := Vector3.ZERO
var b := Vector3(1, 0, 0)
var maker := 0
## Where its notes are played: this player's keys. Session.guest_midi unless told otherwise.
var keys: GuestMidi = null
## () -> {id: Vector3}: this player's tracked fingertips, in global space (ChordHarp.tips). Not
## set, every local tracked hand's index and middle tips (HandGestures.local_tips).
var tips: Callable = Callable()
## (seconds) -> Harmony: the harmony a pluck at that song position is snapped to. Not set, the
## song's (Harmony.at), as the chord shapes do not change a string's note.
var harmony: Callable = Callable()
## The synth a bandmate's string notes play on, out of this string: made the first time one arrives.
var room: MonitorSynth = null

## A grab pulling it this far off its line, or a press on a knot: cut it (the studio asks the room).
signal cut_asked(id: StringName)

## The plucking hand's bend and wobble on what rings, one for every string here (`_bending`).
static var wobble: Wobble = null
static var _wobble_frame := -1
## {pitch: RoomString} for the strings ringing from this player's hand, so one pitch is one note
## and its note-off never ends the string that replaced it.
static var _sounding := {}

## [pitch sounding, seconds left] while it rings from this player's hand; empty while not.
var _ringing: Array = []
## Seconds left of a bandmate's note shaking it.
var _shaking := 0.0
## A bandmate's notes sounding from it: {Vector2i(peer, pitch): true}.
var _theirs := {}
## Each fingertip's place in its frame last physics frame, while it was near it.
var _tips_was := {}
## How far off its line the holding hand was when it took hold (m), and its pull now in its frame.
var _pull_from := 0.0
var _pull := Vector3.ZERO
var _line: MeshInstance3D
var _gut: ShaderMaterial
var _shape: CollisionShape3D
var _letter: Label3D
var _knots: Array[Knot] = []
var _clock := 0.0
var _shown := -1


## The pitch a string `length` metres long plays by the law, unsnapped (MIDI, fractional): E5 at
## SHORTEST down to E1 at LONGEST, log in length; outside them, held at the nearer end.
static func raw_pitch(length: float) -> float:
	var l := clampf(length, SHORTEST, LONGEST)
	return TOP_PITCH - (TOP_PITCH - BOTTOM_PITCH) * log(l / SHORTEST) / log(LONGEST / SHORTEST)


## The law's pitch rounded to a semitone, before the key: E5, C4 and E1 at 0.3 m, 1 m and 12 m.
static func plain_pitch(length: float) -> int:
	return roundi(raw_pitch(length))


## The note a string `length` metres long plays in `h`: the law's, snapped to its scale
## (Harmony.snap), and the scale's lowest tone at or above E1 where snapping would go under it.
## With no key, the law's semitone.
static func pitch_in(length: float, h: Harmony) -> int:
	var p := plain_pitch(length)
	if h != null:
		p = h.snap(p)
	if p < BOTTOM_PITCH:
		p = BOTTOM_PITCH
		if h != null and not h.scale.is_empty():
			while not h.scale.has(posmod(p, 12)):
				p += 1
	return p


## Room row `rows` with string `id` tied from `a` to `b` by `from`, or cut where `a` is `b`: "" when
## done, else why not, in words for whoever asked. What the host keeps and a guest predicts with.
## A string from SHORTEST to LONGEST long, its ends inside BOUND, and a new one only while the room
## has fewer than MOST; tying an id again moves that string. Anyone may cut any string.
static func answer(rows: Dictionary, string_id: StringName, from_a: Vector3, to_b: Vector3, from: int) -> String:
	if from_a.is_equal_approx(to_b):
		rows.erase(string_id)
		return ""
	if String(string_id).is_empty() or String(string_id).length() > 24:
		return "That string has no name the room can keep."
	if not (_in_bounds(from_a) and _in_bounds(to_b)):
		return "That string's ends are out of the room."
	var length := from_a.distance_to(to_b)
	if length < SHORTEST - 0.0005:
		return "A string is %d cm at the shortest: that one would be %d cm." % [roundi(SHORTEST * 100.0), roundi(length * 100.0)]
	if length > LONGEST + 0.0005:
		return "A string is %d m at the longest: that one would be %.1f m." % [roundi(LONGEST), length]
	if not rows.has(string_id) and rows.size() >= MOST:
		return "The room has %d strings, the most it takes: cut one first (pull it hard, or press a knot)." % MOST
	rows[string_id] = [from_a, to_b, from]
	return ""


static func _in_bounds(p: Vector3) -> bool:
	return p.is_finite() and absf(p.x) <= BOUND and absf(p.z) <= BOUND and p.y >= -2.0 and p.y <= BOUND * 0.5


## Where a ray from `from` along `toward` (global) first meets something to tie a string to, in
## `venue`'s frame, out to FAR; INF for nothing there. Whatever has a body (the gear, a stand's feet,
## another string: every physics layer but the walker's), the floor, what stands on it (`solids`, the
## walker's {c, h, a, top}, as boxes up to their tops), the walls round `rooms` (Rect2s on the floor,
## the rooms a person walks in), and the ceiling at Venue.LIVE_ROOM_HEIGHT. `exclude`: bodies (RIDs)
## the ray passes through.
static func surface_hit(from: Vector3, toward: Vector3, venue: Node3D, rooms: Array, solids: Array,
		exclude: Array = []) -> Vector3:
	if toward.length() < 0.0001:
		return Vector3.INF
	var d := toward.normalized()
	var into := venue.global_transform.affine_inverse() if venue != null and venue.is_inside_tree() \
			else Transform3D.IDENTITY
	var o := into * from
	var dl := (into.basis * d).normalized()
	var best := FAR
	if venue != null and venue.is_inside_tree():
		var query := PhysicsRayQueryParameters3D.create(from, from + d * FAR)
		query.collision_mask = 0xFFFFFFFF & ~(1 << (Walker.SOLID_LAYER - 1))
		query.exclude = exclude
		var hit := venue.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			best = minf(best, (into * (hit["position"] as Vector3)).distance_to(o))
	if dl.y < -0.0001 and o.y >= 0.0:
		best = minf(best, -o.y / dl.y)
	if dl.y > 0.0001 and o.y < Venue.LIVE_ROOM_HEIGHT:
		best = minf(best, (Venue.LIVE_ROOM_HEIGHT - o.y) / dl.y)
	for f: Dictionary in solids:
		best = minf(best, _box_hit(o, dl, f))
	best = minf(best, _wall_hit(o, dl, rooms))
	if best >= FAR - 0.0001:
		return Vector3.INF
	return o + dl * best


## How far along `d` from `o` a ray enters walker footprint `f` ({c, h, a, top}, a box from the floor
## to its top), INF for not at all or from inside it.
static func _box_hit(o: Vector3, d: Vector3, f: Dictionary) -> float:
	var c: Vector2 = f.get("c", Vector2.ZERO)
	var h: Vector2 = f.get("h", Vector2.ZERO)
	var back := Basis(Vector3.UP, -float(f.get("a", 0.0)))
	var lo := back * (o - Vector3(c.x, 0, c.y))
	var ld := back * d
	var near := -INF
	var far := INF
	var lows := [-h.x, 0.0, -h.y]
	var highs := [h.x, float(f.get("top", Walker.SOLID_HEIGHT)), h.y]
	for axis in 3:
		if absf(ld[axis]) < 1e-6:
			if lo[axis] < lows[axis] or lo[axis] > highs[axis]:
				return INF
			continue
		var t0: float = (lows[axis] - lo[axis]) / ld[axis]
		var t1: float = (highs[axis] - lo[axis]) / ld[axis]
		near = maxf(near, minf(t0, t1))
		far = minf(far, maxf(t0, t1))
	if near > far or near <= 0.0:
		return INF
	return near


## How far along `d` from `o` a ray leaves the floor of `rooms` (Rect2s that meet along shared
## lines), where their walls are; INF for a ray from outside them all.
static func _wall_hit(o: Vector3, d: Vector3, rooms: Array) -> float:
	var v := Vector2(d.x, d.z)
	if v.length() < 1e-5:
		return INF
	var p := Vector2(o.x, o.z)
	var t := 0.0
	for step in 8:
		var q := p + v * t
		var leaves := -1.0
		for r: Rect2 in rooms:
			if not r.grow(0.001).has_point(q):
				continue
			var tx := INF
			if v.x > 0.0:
				tx = (r.end.x - q.x) / v.x
			elif v.x < 0.0:
				tx = (r.position.x - q.x) / v.x
			var tz := INF
			if v.y > 0.0:
				tz = (r.end.y - q.y) / v.y
			elif v.y < 0.0:
				tz = (r.position.y - q.y) / v.y
			leaves = maxf(leaves, minf(tx, tz))
		if leaves < 0.0:
			return t if step > 0 else INF
		t += leaves + 0.002
	return t


## The spool's footprint for the walker, at `at` (Venue.string_spool_spot), as {c, h, a, top}.
static func spool_solid(at: Transform3D) -> Dictionary:
	var middle := at * Vector3(0, 0, SPOOL_FOOT_Z)
	return {"c": Vector2(middle.x, middle.z), "h": SPOOL_FOOT, "a": at.basis.get_euler().y, "top": SPOOL_TOP}


## The hand an end is tied with, for a hand `by` that took it: a fingertip's poke presses only what
## it touches, so the end goes to the same hand's ray (the XRInteractor reading its HandGestures);
## anything else, itself.
static func tying_hand(by: Node) -> Interactor:
	var poke := by as PokeInteractor
	if poke != null and poke.is_inside_tree():
		for n in poke.get_tree().get_nodes_in_group(Interactor.GROUP):
			var ray := n as XRInteractor
			if ray != null and ray.gestures != null and ray.gestures.tracker_name == poke.tracker_name:
				return ray
	return by as Interactor


func _init() -> void:
	name = "RoomString"


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	if keys == null:
		keys = Session.guest_midi
	_shape = CollisionShape3D.new()
	_shape.shape = BoxShape3D.new()
	add_child(_shape)
	_line = MeshInstance3D.new()
	_line.name = "Line"
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 8
	# Rings enough to bow and shake smoothly.
	mesh.rings = 24
	_line.mesh = mesh
	_gut = ShaderMaterial.new()
	_gut.shader = _bowed()
	_line.material_override = _gut
	# The cylinder's length along the string (this node's X): its own Y turned onto X.
	_line.transform = Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3.ZERO)
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)
	_letter = Label3D.new()
	_letter.name = "Letter"
	_letter.pixel_size = 0.0004
	_letter.font_size = roundi(LETTER_CAP / 0.7 / _letter.pixel_size)
	_letter.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_letter.modulate = Color(0.97, 0.93, 0.82)
	Lettering.range_to_legibility(_letter)
	add_child(_letter)
	for end in 2:
		var knot := Knot.new()
		knot.name = "KnotA" if end == 0 else "KnotB"
		knot.string = self
		add_child(knot)
		_knots.append(knot)
	_place()


## Tied from `from_a` to `to_b` (its parent's frame), by `by`: stood there, its note lettered.
func tie(from_a: Vector3, to_b: Vector3, by := 0) -> void:
	if from_a.is_equal_approx(a) and to_b.is_equal_approx(b) and by == maker and is_inside_tree():
		return
	a = from_a
	b = to_b
	maker = by
	if is_inside_tree():
		_place()


## How long it is (m).
func length() -> float:
	return a.distance_to(b)


## Its middle stands at the middle of its ends, its X along it from `a` to `b`, its Y as near to
## up as it can be square to it: so the plane a held ray is kept in (Interactor._plane_point) is
## the upright one the string lies in.
func _place() -> void:
	var along := b - a
	var span := along.length()
	var x := along / maxf(span, 0.0001)
	var up := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.98 else Vector3.BACK
	var y := (up - x * up.dot(x)).normalized()
	var z := x.cross(y).normalized()
	transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	var f := clampf((span - SHORTEST) / (LONGEST - SHORTEST), 0.0, 1.0)
	var mesh := _line.mesh as CylinderMesh
	mesh.height = span
	mesh.top_radius = lerpf(THIN, THICK, sqrt(f))
	mesh.bottom_radius = mesh.top_radius
	_gut.set_shader_parameter(&"half_length", span * 0.5)
	# Steel for the short ones, bronze-wound for the long: as a guitar's are.
	var colour := Color(0.86, 0.87, 0.9).lerp(Color(0.72, 0.5, 0.26), sqrt(f))
	_gut.set_shader_parameter(&"colour", Vector3(colour.r, colour.g, colour.b))
	(_shape.shape as BoxShape3D).size = Vector3(maxf(span - KNOT * 2.0, 0.05), GRAB * 2.0, GRAB * 2.0)
	_letter.position = Vector3(0, LETTER_ABOVE, 0)
	_knots[0].position = Vector3(-span * 0.5, 0, 0)
	_knots[1].position = Vector3(span * 0.5, 0, 0)
	_show_note(true)


## The string's material: bowed sideways by `bow` (m) and shaken by `shake`, pulled by `pull`
## (its frame's Y and Z, m), all at the middle and nothing at the ends, and lit by `glow` while it
## rings at motion 0. One shader for every string, a material each.
static var _bow_shader: Shader = null


static func _bowed() -> Shader:
	if _bow_shader == null:
		_bow_shader = Shader.new()
		_bow_shader.code = """shader_type spatial;
uniform float half_length = 0.5;
uniform float bow = 0.0;
uniform float shake = 0.0;
uniform vec2 pull = vec2(0.0);
uniform float glow = 0.0;
uniform vec3 colour = vec3(0.86, 0.87, 0.9);
void vertex() {
	float t = clamp(VERTEX.y / half_length, -1.0, 1.0);
	float belly = 1.0 - t * t;
	// The cylinder's X is the string's -Y (up), its Z the string's Z (across).
	VERTEX.x += (shake - pull.x) * belly;
	VERTEX.z += (bow + pull.y) * belly;
}
void fragment() {
	ALBEDO = colour;
	METALLIC = 0.6;
	ROUGHNESS = 0.32;
	EMISSION = colour * (0.12 + glow * 0.9);
}
"""
	return _bow_shader


# --- what it plays ------------------------------------------------------------------------------

## The song position a note played now is played to, and whether the song is playing to it.
func _moment() -> Array:
	var song := keys.song() if keys != null else -1.0
	if song >= 0.0:
		return [song, true]
	return [DAW.state.position_seconds if DAW.state != null else 0.0, false]


## The harmony a pluck at `seconds` is snapped to.
func harmony_at(seconds: float) -> Harmony:
	if harmony.is_valid():
		return harmony.call(seconds)
	return Harmony.at(DAW.state, seconds)


## Its note at `seconds`, and now.
func pitch_at(seconds: float) -> int:
	return pitch_in(length(), harmony_at(seconds))


func pitch() -> int:
	return pitch_at(_moment()[0])


## Whether it rings from this player's hand.
func ringing() -> bool:
	return not _ringing.is_empty()


## Whether it shakes with a note on it: this player's or a bandmate's.
func sounding() -> bool:
	return not _ringing.is_empty() or _shaking > 0.0


## Whether a hand here is on it or over it, or a fingertip near it.
func touched() -> bool:
	if is_hovered() or is_held() or not _tips_was.is_empty():
		return true
	return _knots.any(func(k: Knot) -> bool: return k.is_hovered() or k.is_held())


## Plucked, at `velocity`: its note now on this player's keys, ringing RING. `by`, the hand that
## plucked it (an Interactor, a bare hand's HandGestures), bends it while it rings; null leaves the
## bending hand as it was.
func pluck(velocity: int, by: Object = null) -> void:
	if by != null:
		_bending(by)
	var moment := _moment()
	var seconds: float = moment[0]
	var p := pitch_at(seconds)
	_let_ring_out()
	var other: RoomString = _sounding.get(p)
	if other != null and is_instance_valid(other) and other != self:
		other._let_ring_out()
	_ringing = [p, RING]
	_sounding[p] = self
	if keys != null:
		keys.note_on(p, velocity, 0, 0.0, false, SOURCE, seconds if moment[1] else NAN)


func _let_ring_out() -> void:
	if _ringing.is_empty():
		return
	var p := int(_ringing[0])
	_ringing = []
	if _sounding.get(p) == self:
		_sounding.erase(p)
	if keys != null:
		keys.note_off(p, 0, 0.0, false, SOURCE)


## Let go of what it plays, now: for a string cut or gone from the room with its note still on.
func silence() -> void:
	_let_ring_out()


## The hand that bends what rings, from its next frame: `by`.
func _bending(by: Object) -> void:
	if wobble == null:
		wobble = Wobble.new(keys, [SOURCE])
	wobble.keys = keys
	wobble.hand = by


func plays_under_cursor() -> bool:
	return true


## Plucking is this player's own: two players may pluck one string, and nobody else is told it is
## held.
func personal() -> bool:
	return true


func grab_begin(by: Node, at: Vector3) -> void:
	# A fingertip brushes it directly (`tips`); a poke's contact counted as a grab as well would
	# pluck it twice.
	if by is PokeInteractor:
		return
	super(by, at)
	if held_by != by:
		return
	_pull_from = _off_line(_held_point(by, at))
	_pull = Vector3.ZERO
	pluck(PLUCK_VELOCITY, by)


func grab_move(by: Node, at: Vector3) -> void:
	if held_by != by:
		return
	var p := _held_point(by, at)
	var local := to_local(p)
	var off := Vector3(0, local.y, local.z)
	var pulled := _off_line(p) - _pull_from
	_pull = off.normalized() * clampf(pulled, 0.0, PULL_SHOWN) if off.length() > 0.001 else Vector3.ZERO
	if pulled >= CUT_PULL:
		_pull = Vector3.ZERO
		held_by = null
		cut_asked.emit(id)
		return
	super(by, at)


func grab_end(by: Node) -> void:
	_pull = Vector3.ZERO
	super(by)


## Where the holding hand is: a mouse's ray in the string's upright plane (`at`), a hand's own place.
func _held_point(by: Node, at: Vector3) -> Vector3:
	var hand := by as Interactor
	if hand == null or hand is MouseInteractor or hand is PokeInteractor:
		return at
	return hand.catch_point()


## How far `p` (global) is off its line (m).
func _off_line(p: Vector3) -> float:
	var local := to_local(p)
	return Vector2(local.y, local.z).length()


func _physics_process(delta: float) -> void:
	_brush(delta)
	if not _ringing.is_empty():
		_ringing[1] = float(_ringing[1]) - delta
		if float(_ringing[1]) <= 0.0:
			_let_ring_out()
	_shaking = maxf(_shaking - delta, 0.0)
	var frame := Engine.get_physics_frames()
	if wobble != null and frame != _wobble_frame:
		_wobble_frame = frame
		wobble.keys = keys
		wobble.step(delta)


## The fingertips, through it: a tip whose path since last frame passes the string within TOUCH of
## it (its nearest to the line inside that path, not at either end), away from its knots, plucks
## it, as hard as it was going.
func _brush(delta: float) -> void:
	var now: Dictionary = tips.call() if tips.is_valid() \
			else HandGestures.local_tips(get_tree() if is_inside_tree() else null)
	var into := global_transform.affine_inverse()
	var half := length() * 0.5 - KNOT
	var seen := {}
	for tip in now:
		var p: Vector3 = into * (now[tip] as Vector3)
		if absf(p.x) > half or Vector2(p.y, p.z).length() > GRAB * 3.0:
			continue
		seen[tip] = true
		if _tips_was.has(tip):
			var was: Vector3 = _tips_was[tip]
			var from := Vector2(was.y, was.z)
			var to := Vector2(p.y, p.z)
			# Past the line: its nearest to it between where it was and where it is (so a tip
			# resting on it plucks once, not every frame), and that within TOUCH of it.
			var went := to - from
			if from.dot(went) < 0.0 and to.dot(went) > 0.0 \
					and Geometry2D.get_closest_point_to_segment(Vector2.ZERO, from, to).length() <= TOUCH:
				var speed := (p - was).length() / maxf(delta, 0.001)
				pluck(maxi(InstrumentItem.velocity_for(speed), SOFTEST), ChordHarp.tip_hand(tip))
		_tips_was[tip] = p
	for tip in _tips_was.keys():
		if not seen.has(tip):
			_tips_was.erase(tip)


func _process(delta: float) -> void:
	_clock += delta
	_show_note()
	var left := 0.0
	if not _ringing.is_empty():
		left = float(_ringing[1])
	left = maxf(left, _shaking) / RING
	var motion := Ergonomics.current.motion_scale if Ergonomics.current != null else 1.0
	# A long string swings wider and slower: by its length's square root, against a metre's.
	var scale := sqrt(clampf(length(), SHORTEST, LONGEST))
	var shake := sin(_clock * TAU * SHAKE_HZ / scale) * SHAKE * scale * left * clampf(motion, 0.0, 1.0)
	_gut.set_shader_parameter(&"shake", shake)
	_gut.set_shader_parameter(&"glow", left if motion <= 0.01 else left * 0.3)
	var st := 0.0
	if not _ringing.is_empty() and wobble != null and wobble.engaged():
		st = wobble.semitones
	_gut.set_shader_parameter(&"bow", st / Wobble.BEND_MOST * BOW_MOST)
	_gut.set_shader_parameter(&"pull", Vector2(_pull.y, _pull.z))


## How far its middle shakes now (m): for the suite and the shot.
func shake_now() -> float:
	return float(_gut.get_shader_parameter(&"shake")) if _gut != null else 0.0


## How bright it is lit by its ringing now, 0 to 1.
func glow_now() -> float:
	return float(_gut.get_shader_parameter(&"glow")) if _gut != null else 0.0


## Its letter: the note it plays now, retuned as the key changes.
func _show_note(force := false) -> void:
	if _letter == null:
		return
	var seconds: float = _moment()[0]
	var p := pitch_at(seconds)
	if p == _shown and not force:
		return
	_shown = p
	_letter.text = harmony_at(seconds).note_name(p)


## The note in words, as its letter says it.
func note_name() -> String:
	return _letter.text if _letter != null else ""


# --- a bandmate's string ------------------------------------------------------------------------

## A bandmate's string note, as Session.note_played says it (the studio routes them here by
## source and pitch): out of this string, on a synth of its own, and it shakes.
func heard(peer: int, kind: int, p: int, velocity: int) -> void:
	var key := Vector2i(peer, p)
	match kind:
		Session.Note.ON:
			_voice().note_on(p, velocity)
			_theirs[key] = true
			_shaking = RING
		Session.Note.OFF:
			if not _theirs.has(key):
				return
			_theirs.erase(key)
			if room != null and not _theirs.keys().any(func(k: Vector2i) -> bool: return k.y == p):
				room.note_off(p)


## Whether `peer`'s `p` is sounding from it.
func sounds_for(peer: int, p: int) -> bool:
	return _theirs.has(Vector2i(peer, p))


## Everything `peer` had sounding from it let go (0, everyone's).
func forget(peer := 0) -> void:
	for key: Vector2i in _theirs.keys():
		if peer == 0 or key.x == peer:
			heard(key.x, Session.Note.OFF, key.y, 0)


func _exit_tree() -> void:
	silence()
	forget()
	super()


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
	return "STRING  %s" % note_name()


## `E2, 6.4 m (A minor)`: its note, its length, the key it is snapped to.
func _default_readout() -> String:
	var h := harmony_at(_moment()[0])
	return "%s, %.1f m (%s)" % [note_name(), length(), h.key_name if h.named else "NO KEY SET"]


func hint() -> String:
	if InstrumentItem.hands_hint:
		return "brush through it with a fingertip, or pinch it, to pluck  ·  tilt to bend, shake to wobble\ngrab it and pull hard, or press a knot, to cut it"
	return "click to pluck  ·  wiggle over it while it rings to wobble  ·  Alt + mouse up or down bends\ndrag it hard off its line, or click a knot, to cut it"


## A knot at one end, with an X beside it: pressed, the string is cut. Its own control, small, so a
## fingertip can press it and a ray click it.
class Knot extends ControlAffordance:
	var string: RoomString

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * RoomString.KNOT * 2.4
		shape.shape = box
		add_child(shape)
		var ball := MeshInstance3D.new()
		ball.name = "Ball"
		var mesh := SphereMesh.new()
		mesh.radius = RoomString.KNOT
		mesh.height = RoomString.KNOT * 2.0
		mesh.radial_segments = 12
		mesh.rings = 6
		ball.mesh = mesh
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color(0.62, 0.45, 0.2)
		brass.metallic = 0.7
		brass.roughness = 0.4
		ball.material_override = brass
		add_child(ball)
		var x := Label3D.new()
		x.name = "X"
		x.text = "X"
		x.pixel_size = 0.0004
		x.font_size = 96
		x.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		x.modulate = Color(0.97, 0.93, 0.82)
		x.position = Vector3(0, RoomString.KNOT * 2.4, 0)
		Lettering.range_to_legibility(x)
		add_child(x)

	func _default_title() -> String:
		return "STRING  %s  KNOT" % (string.note_name() if string != null else "")

	func _default_readout() -> String:
		return "press to cut it"

	func hint() -> String:
		return "press the knot to cut the string · or grab the string and pull it hard"

	func personal() -> bool:
		return true

	func _on_grab_begin(_at: Vector3) -> void:
		if string != null:
			string.cut_asked.emit(string.id)


## The spool (station `strings`, tools/blender/string_spool.py): a bobbin of string on a stand, on a
## trolley in a studio. Its reel (`Reel`) gives an end to the hand that presses it (`take_end`): that
## hand's button is then the end's (Interactor.tool), not the controls'. Its next press ties the
## first end where its ray meets something (`surface_hit`), and its let-go, somewhere else, ties the
## second there; a press and let-go in one place (a desk's click) waits for a second press for the
## second end. Between them the string is drawn as it would be, lettered with its note and length, or
## why not. Then `string_asked` (the venue's frame), and the end is gone from the hand. Esc, a press
## on the reel again, or the hand taking an end from somewhere else, drops it.
class Spool extends Node3D:
	## Both ends tied, in the venue's frame: the studio asks the room for the string.
	signal string_asked(from_a: Vector3, to_b: Vector3)
	## Something to say to this player.
	signal told(text: String)

	const MODEL := "res://assets/models/string_spool.glb"

	## The hand carrying an end, or null.
	var hand: Interactor = null
	## The first end, tied, in the venue's frame; INF until it is.
	var first := Vector3.INF
	## () -> [rooms, solids]: the floors a person walks (Rect2s) and what stands on them (walker
	## footprints), in the venue's frame, for `surface_hit`. Not set, its parent venue's own.
	var bounds: Callable = Callable()
	## () -> int: how many strings the room has, for its card.
	var count: Callable = Callable()
	## () -> Harmony: the key the preview is lettered in. Not set, the song's at the playhead.
	var harmony: Callable = Callable()
	var reel: Reel
	## Whether the carrying hand's button has gone down since it took the end (the press that took
	## it is the reel's, and its let-go is not the end's).
	var _down := false
	var _preview: MeshInstance3D
	var _preview_letter: Label3D
	var _wound: StandardMaterial3D

	func _init() -> void:
		name = "StringSpool"

	func _ready() -> void:
		if ResourceLoader.exists(MODEL):
			var model := (load(MODEL) as PackedScene).instantiate() as Node3D
			add_child(model)
			_dress(model)
		reel = Reel.new()
		reel.name = "Reel"
		reel.spool = self
		reel.position = RoomString.SPOOL_AXLE
		add_child(reel)
		var plaque := Stations.plaque(RoomString.STATION, RoomString.SPOOL_PLAQUE_WIDE)
		# Its top edge at SPOOL_PLAQUE_TOP, on the arm's end, leant back.
		var top := float(plaque.get_meta(&"plaque_tall", 0.2)) * 0.5
		var lean := Basis(Vector3.RIGHT, -RoomString.SPOOL_PLAQUE_LEAN)
		var edge := Vector3(0, RoomString.SPOOL_PLAQUE_TOP, RoomString.SPOOL_PLAQUE.z + 0.012)
		plaque.transform = Transform3D(lean, edge - lean * Vector3(0, top, 0))
		add_child(plaque)
		_preview = MeshInstance3D.new()
		_preview.name = "Preview"
		var line := CylinderMesh.new()
		line.top_radius = 0.004
		line.bottom_radius = 0.004
		line.radial_segments = 6
		line.rings = 1
		_preview.mesh = line
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(0.95, 0.9, 0.75, 0.7)
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_preview.material_override = glow
		_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_preview.top_level = true
		_preview.visible = false
		add_child(_preview)
		_preview_letter = Label3D.new()
		_preview_letter.name = "PreviewLetter"
		_preview_letter.pixel_size = 0.0004
		_preview_letter.font_size = roundi(RoomString.LETTER_CAP / 0.7 / _preview_letter.pixel_size)
		_preview_letter.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_preview_letter.no_depth_test = true
		_preview_letter.modulate = Color(0.97, 0.93, 0.82)
		_preview_letter.top_level = true
		_preview_letter.visible = false
		Lettering.range_to_legibility(_preview_letter)
		add_child(_preview_letter)

	func _dress(model: Node3D) -> void:
		var swap := {
			"stand": _paint(Color(0.2, 0.12, 0.065), 0.5),
			"bobbin": _paint(Color(0.58, 0.39, 0.21), 0.45),
			"brass": Materials.brushed_metal(),
		}
		_wound = _paint(Color(0.88, 0.82, 0.68), 0.7)
		swap["wound"] = _wound
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for s in mesh.mesh.get_surface_count():
				var m := mesh.mesh.surface_get_material(s)
				if m != null and swap.has(m.resource_name):
					mesh.set_surface_override_material(s, swap[m.resource_name])

	static func _paint(colour: Color, roughness: float) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = roughness
		return m

	## Whether a hand here is carrying an end.
	func carrying() -> bool:
		return hand != null and is_instance_valid(hand)

	## An end to `by`'s hand (a poke's goes to its ray, `tying_hand`), or, if it already carries one,
	## dropped again: a second press on the reel puts it back.
	func take_end(by: Node) -> void:
		var h := RoomString.tying_hand(by)
		if h == null:
			return
		if carrying() and hand == h:
			drop("The end is back on the spool.")
			return
		drop()
		# Another spool's end in this hand goes back there.
		if h.tool.is_valid():
			h.tool = Callable()
		hand = h
		first = Vector3.INF
		_down = false
		h.tool = _on_tool
		told.emit(_first_words(h))

	func _first_words(h: Interactor) -> String:
		if h is MouseInteractor:
			return "STRING: click where its first end goes (any wall, the floor, the gear), then where its second goes · Esc drops it"
		return "STRING: press where its first end goes (anything your ray meets), carry it, let go where the second goes · press the spool to drop it"

	## The end back on the spool, nothing tied: `words` said, if any.
	func drop(words := "") -> void:
		if carrying() and hand.tool == _on_tool:
			hand.tool = Callable()
		hand = null
		first = Vector3.INF
		_down = false
		if _preview != null:
			_preview.visible = false
			_preview_letter.visible = false
		if words != "":
			told.emit(words)

	## The carrying hand's button: down ties the first end (or the second, if the first is tied and
	## the button came up where it went down), up ties the second where it is now.
	func _on_tool(h: Interactor, down: bool) -> void:
		if h != hand:
			return
		if down:
			_down = true
			if h.hovered == reel:
				drop("The end is back on the spool.")
				return
			var p := point_for(h)
			if not p.is_finite():
				told.emit("Nothing there to tie it to: aim at a wall, the floor or the gear.")
				return
			if not first.is_finite():
				first = p
			else:
				_tie(p)
			return
		if not _down or not first.is_finite():
			return
		var p := point_for(h)
		if p.is_finite() and p.distance_to(first) >= RoomString.SHORTEST:
			_tie(p)
		elif h is MouseInteractor:
			told.emit("STRING: now click where its second end goes · Esc drops it")
		else:
			told.emit("STRING: carry it further than 30 cm and let go, or press where its second end goes")

	func _tie(second: Vector3) -> void:
		var from_a := first
		drop()
		string_asked.emit(from_a, second)

	## Where `h`'s ray meets something to tie to, in the venue's frame (its parent's); INF for nothing.
	func point_for(h: Interactor) -> Vector3:
		var venue := get_parent() as Node3D
		var shape: Array = bounds.call() if bounds.is_valid() else []
		if shape.is_empty() and venue is Venue:
			shape = [(venue as Venue).rooms(), (venue as Venue).solids()]
		var aim := h.aim()
		return RoomString.surface_hit(aim.origin, -aim.basis.z, venue,
				shape[0] if shape.size() > 0 else [], shape[1] if shape.size() > 1 else [])

	func _process(_delta: float) -> void:
		if not carrying():
			if hand != null:
				drop()
			return
		var p := point_for(hand)
		var venue := get_parent() as Node3D
		var to_world := venue.global_transform if venue != null else Transform3D.IDENTITY
		if not p.is_finite():
			_preview.visible = false
			_preview_letter.visible = false
			return
		_preview_letter.visible = true
		if not first.is_finite():
			# Where the first end would go: a dot, lettered.
			_preview.visible = false
			_preview_letter.global_position = to_world * p + Vector3.UP * RoomString.LETTER_ABOVE
			_preview_letter.text = "FIRST END"
			return
		var from_w := to_world * first
		var to_w := to_world * p
		var along := to_w - from_w
		var length := along.length()
		_preview.visible = length > 0.01
		if length > 0.01:
			# The cylinder's Y along the string.
			var y := along / length
			var across := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.98 else Vector3.BACK
			var z := y.cross(across).normalized()
			(_preview.mesh as CylinderMesh).height = length
			_preview.global_transform = Transform3D(Basis(y.cross(z), y, z), (from_w + to_w) * 0.5)
		_preview_letter.global_position = (from_w + to_w) * 0.5 + Vector3.UP * RoomString.LETTER_ABOVE
		_preview_letter.text = preview_words(length)

	## What the string drawn from the first end to the ray says: its note and length, or why it
	## cannot be.
	func preview_words(length: float) -> String:
		if length < RoomString.SHORTEST:
			return "TOO SHORT  %d cm (30 cm least)" % roundi(length * 100.0)
		if length > RoomString.LONGEST:
			return "TOO LONG  %.1f m (12 m most)" % length
		var h: Harmony = harmony.call() if harmony.is_valid() \
				else Harmony.at(DAW.state, DAW.state.position_seconds if DAW.state != null else 0.0)
		return "%s  %.1f m" % [h.note_name(RoomString.pitch_in(length, h)), length]

	## The preview's lettering now, for the suite.
	func preview_text() -> String:
		return _preview_letter.text if _preview_letter != null and _preview_letter.visible else ""


## The spool's reel: pressed, an end of string to the hand that pressed it (Spool.take_end).
class Reel extends ControlAffordance:
	var spool: Spool

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(RoomString.SPOOL_HALF * 2.0 + 0.04, RoomString.SPOOL_RADIUS * 2.0 + 0.02,
				RoomString.SPOOL_RADIUS * 2.0 + 0.02)
		shape.shape = box
		add_child(shape)

	func _default_title() -> String:
		return "STRING SPOOL"

	func _default_readout() -> String:
		var n: int = spool.count.call() if spool != null and spool.count.is_valid() else 0
		if spool != null and spool.carrying():
			return "an end in hand · %d of %d strings in the room" % [n, RoomString.MOST]
		return "%d of %d strings in the room" % [n, RoomString.MOST]

	func hint() -> String:
		if InstrumentItem.hands_hint:
			return "press for an end · press where it goes, carry it, let go where it ends\nits length is its note: across the room a bass, a hand's width high"
		return "click for an end · click where it goes, then where it ends (any surface)\nits length is its note: across the room a bass, short ones high · Esc drops it"

	func dwell_activates() -> bool:
		return false

	## Taking an end is this player's own.
	func personal() -> bool:
		return true

	func grab_begin(by: Node, at: Vector3) -> void:
		super(by, at)
		if held_by == by and spool != null:
			spool.take_end(by)
