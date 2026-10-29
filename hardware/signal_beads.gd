class_name SignalBeads
extends MeshBank

## Signal you can see (docs/spatial_loop.md part two, slice 21, idea #3): small bright beads riding
## every cable in the room, spaced and paced by the level at the cable's source.
##
## WHAT IT ANSWERS. "Why is there no sound" is the question a desk asks most and answers worst: the
## meters say a track is silent, not where the signal stopped. A bead on a cable is the signal
## going along that cable, so the answer is to follow the light until it stops. A muted track's
## loom stops at its strip, a send at zero carries nothing past its jack, and an instrument's lead
## with nothing playing is still.
##
## WHAT RIDES. Anything in the CARRIERS group with four methods: `signal_spine()` (its centre
## line, world space), `signal_length()` (that line's length, in metres), `signal_level()` (how
## loud what it carries is now, 0..1 on the fader law: 0.716 is 0 dBFS) and `signal_radius()` (how
## thick it is, so a bead sits on it rather than in it). Today: the modular's patch cables
## (PatchCable), the looms' runs (GearLoom), the instruments' leads and their cables into bandmates
## (JackSocket) and the stage table's ropes (StageTable.Rope). The routing bay has no cables: its
## pins pulse with `level_between` instead (PinMatrix.signal_of).
##
## LOUDER IS CLOSER, FASTER AND BRIGHTER, never another colour: the beads are one warm white, and
## the level is how many there are along a metre, how fast they go and how brightly they burn. At
## Ergonomics.motion_scale 0 they stand still, evenly spaced whatever the level, and their
## brightness alone carries it; at 0.4 (COMFORT's "gentle") they go at 0.4 of the pace.
##
## ONE DRAW CALL. Every bead in the room is an instance of one MultiMesh (this bank), sized once
## at CAPACITY and drawn `show_first(n)` deep, so ninety tracks of patching costs what one cable
## does. Over CAPACITY the beads are shared out so every carrier still has at least one
## (`allot`): a cable with signal on it is never drawn dark to make room for another.

const CARRIERS := &"signal_carriers"
## How many beads the room can show at once, and the most one carrier is given.
const CAPACITY := 640
const MOST_ON_ONE := 48
## Under this a carrier carries nothing: about -60 dBFS on the fader law.
const FLOOR := 0.08
## Between beads at the quietest and at the loudest (m), and how fast they go (m/s at motion 1).
const SPACING_QUIET := 0.15
const SPACING_LOUD := 0.045
const SPEED_QUIET := 0.07
const SPEED_LOUD := 0.42
## Spacing goes in this many steps, not continuously: a bead far down a long cable sits at k
## spacings from its first, so a spacing that followed every flicker of a meter would shake it.
const SPACING_STEPS := 5
## Between beads at motion 0, whatever the level.
const SPACING_STILL := 0.09
## A bead's radius against its cable's, quiet to loud.
const SIZE_QUIET := 1.6
const SIZE_LOUD := 2.7
## The beads' one colour, and their brightness quiet to loud: above 1 is what glow picks up.
const COLOUR := Color(1.0, 0.93, 0.78)
const GLOW_QUIET := 0.55
const GLOW_LOUD := 3.2
## How the level a carrier shows follows its source (per second): fast up, slow down, a meter's
## ballistics, so the beads do not flicker with every sample of a meter.
const ATTACK := 30.0
const RELEASE := 4.0

## {carrier instance id: [phase (m travelled), the level shown]}.
var _runs := {}
## How many beads were drawn last frame, and on which carriers: {instance id: count}.
var shown := 0
var on := {}
## The motion it was last driven at, for the suite.
var motion := 1.0


## A bank of CAPACITY beads, committed, none shown.
static func create() -> SignalBeads:
	var beads := SignalBeads.new()
	beads.name = "SignalBeads"
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 8
	ball.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = ball
	beads.multimesh = mm
	beads.material_override = MeshBank._lamp_material()
	beads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Beads go anywhere in the room, and a bank's own bounds would be recomputed every frame they
	# move: one box round the whole of it instead.
	mm.custom_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 24, 80))
	for i in CAPACITY:
		beads.claim(Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO), Color.BLACK)
	beads.commit()
	beads.show_first(0)
	return beads


## A level over a send: the source's level, down by the send's own fader (`send_volume`, the fader
## law). A send at zero carries nothing.
static func through(level: float, send_volume: float) -> float:
	if level <= 0.0 or send_volume <= 0.0:
		return 0.0
	return clampf(FaderLaw.to_taper(FaderLaw.to_db(level) + FaderLaw.to_db(send_volume)), 0.0, 1.0)


## Whether track `index` is heard: not muted, and not left out by another track's solo.
## Constant time: whether anything is soloed is worked out once a change (`any_solo`), not once a
## call, since every cable, loom and strip in the room asks this every frame.
static func heard(index: int) -> bool:
	if DAW.state == null:
		return false
	var t := DAW.state.track(index, false)
	if t == null or t.mute:
		return false
	return t.solo or not any_solo()


## The state, solo version and track count `_any_solo` was worked out for.
static var _solo_state := 0
static var _solo_version := -1
static var _solo_tracks := -1
static var _any_solo := false


## Whether any track is soloed: one pass over the tracks when a solo changes or a track comes or
## goes (MixState.TrackState.solo_version), and the answer kept until then.
static func any_solo() -> bool:
	if DAW.state == null:
		return false
	var s := DAW.state
	if s.get_instance_id() != _solo_state or MixState.TrackState.solo_version != _solo_version \
			or s.tracks.size() != _solo_tracks:
		_solo_state = s.get_instance_id()
		_solo_version = MixState.TrackState.solo_version
		_solo_tracks = s.tracks.size()
		_any_solo = false
		for t: MixState.TrackState in s.tracks.values():
			if t.solo:
				_any_solo = true
				break
	return _any_solo


## What track `index` puts out now: its meter, and nothing while it is not heard (a muted track's
## meter can still show what it would play; its loom does not carry it).
static func track_level(index: int) -> float:
	if not heard(index):
		return 0.0
	var t := DAW.state.track(index)
	return maxf(t.vu_l, t.vu_r)


## What track `index`'s send `send` carries: the track's level through the send's fader.
static func send_level(index: int, send: int) -> float:
	var t := DAW.state.track(index, false) if DAW.state != null else null
	if t == null or not t.sends.has(send):
		return 0.0
	return through(track_level(index), (t.sends[send] as MixState.SendState).volume)


## What goes from track `from` to track `to`: the loudest of `from`'s sends that reach it.
static func level_between(from: int, to: int) -> float:
	var t := DAW.state.track(from, false) if DAW.state != null else null
	if t == null:
		return 0.0
	var most := 0.0
	for n in t.sends:
		if (t.sends[n] as MixState.SendState).resolve(DAW.state) == to:
			most = maxf(most, send_level(from, int(n)))
	return most


## The master's level.
static func master_level() -> float:
	return maxf(DAW.state.master.vu_l, DAW.state.master.vu_r) if DAW.state != null else 0.0


## The loudest of every heard track, or of those `keep` keeps (index -> bool).
static func loudest(keep: Callable = Callable()) -> float:
	if DAW.state == null:
		return 0.0
	var most := 0.0
	# In no order: the loudest is the loudest whichever way round they are asked.
	for index in DAW.state.tracks:
		if keep.is_valid() and not keep.call(index):
			continue
		most = maxf(most, track_level(index))
	return most


## Between beads at `level` (m), in SPACING_STEPS steps; at motion 0, SPACING_STILL.
static func spacing(level: float, motion_scale: float) -> float:
	if motion_scale <= 0.0:
		return SPACING_STILL
	var step := roundf(_loudness(level) * float(SPACING_STEPS - 1)) / float(SPACING_STEPS - 1)
	return lerpf(SPACING_QUIET, SPACING_LOUD, step)


## How fast the beads go at `level` (m/s), scaled by the motion setting.
static func speed(level: float, motion_scale: float) -> float:
	if level < FLOOR:
		return 0.0
	return lerpf(SPEED_QUIET, SPEED_LOUD, _loudness(level)) * clampf(motion_scale, 0.0, 1.0)


## How many beads pass a point on a cable each second at `level`: the rate the eye reads.
static func rate(level: float, motion_scale: float) -> float:
	return speed(level, motion_scale) / spacing(level, motion_scale)


## A bead's colour at `level`: one hue, brighter louder.
static func glow(level: float) -> Color:
	return COLOUR * lerpf(GLOW_QUIET, GLOW_LOUD, _loudness(level))


## 0..1 from FLOOR to 0 dBFS (0.716), so the whole of the bead's range is the part of a meter that
## a mix lives in.
static func _loudness(level: float) -> float:
	return clampf((level - FLOOR) / (0.716 - FLOOR), 0.0, 1.0)


## How many beads each carrier gets, wanted being how many it would like: all of them while they
## fit in `capacity`, else shared so every one keeps at least one and the rest go by how many each
## wanted.
static func allot(wanted: PackedInt32Array, capacity: int) -> PackedInt32Array:
	var out := wanted.duplicate()
	var total := 0
	for n in wanted:
		total += n
	if total <= capacity:
		return out
	var carriers := 0
	for n in wanted:
		if n > 0:
			carriers += 1
	var spare := maxi(capacity - carriers, 0)
	var extra := total - carriers
	var given := 0
	for i in out.size():
		if wanted[i] <= 0:
			continue
		if given >= capacity:
			out[i] = 0
			continue
		var n := 1 + (int(floor(float(wanted[i] - 1) * float(spare) / float(extra))) if extra > 0 else 0)
		out[i] = mini(n, capacity - given)
		given += out[i]
	return out


## The length of a spine (m).
static func length_of(spine: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, spine.size()):
		total += spine[i - 1].distance_to(spine[i])
	return total


func _process(delta: float) -> void:
	drive(delta, Ergonomics.current.motion_scale if Ergonomics.current != null else 1.0)


## One frame of beads: every carrier's level followed, its beads moved on by its speed and laid
## along it, and the rest of the bank not drawn.
func drive(delta: float, motion_scale: float) -> void:
	motion = motion_scale
	var carriers: Array = get_tree().get_nodes_in_group(CARRIERS) if is_inside_tree() else []
	var lit: Array = []
	var wanted := PackedInt32Array()
	var seen := {}
	for node in carriers:
		if not is_instance_valid(node) or not (node as Node3D).is_visible_in_tree():
			continue
		var id: int = node.get_instance_id()
		seen[id] = true
		var run: Array = _runs.get(id, [0.0, 0.0])
		var level: float = clampf(node.signal_level(), 0.0, 1.0)
		var follow := ATTACK if level > float(run[1]) else RELEASE
		run[1] = lerpf(float(run[1]), level, clampf(follow * delta, 0.0, 1.0)) if delta > 0.0 else level
		if level <= 0.0 and float(run[1]) < FLOOR:
			run[1] = 0.0
		var shown_level: float = run[1]
		run[0] = fmod(float(run[0]) + speed(shown_level, motion_scale) * delta, 1000.0)
		_runs[id] = run
		var length: float = node.signal_length()
		if shown_level < FLOOR or length <= 0.0:
			continue
		lit.append(node)
		wanted.append(clampi(int(floor(length / spacing(shown_level, motion_scale))), 1, MOST_ON_ONE))
	if _runs.size() > seen.size() * 2 + 16:
		for id in _runs.keys():
			if not seen.has(id):
				_runs.erase(id)
	var given := allot(wanted, CAPACITY)
	var to_bank := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	var slot := 0
	on.clear()
	for i in lit.size():
		var n := given[i]
		if n <= 0:
			continue
		var node: Node3D = lit[i]
		var run: Array = _runs[node.get_instance_id()]
		var level: float = run[1]
		var length: float = node.signal_length()
		var gap := maxf(spacing(level, motion_scale), length / float(n))
		var size := float(node.signal_radius()) * lerpf(SIZE_QUIET, SIZE_LOUD, _loudness(level)) \
				if motion_scale > 0.0 else float(node.signal_radius()) * SIZE_QUIET
		var tint := glow(level)
		var placed := _lay(node.signal_spine(), fmod(float(run[0]), gap), gap, n, size, tint, to_bank, slot)
		on[node.get_instance_id()] = placed
		slot += placed
	shown = slot
	show_first(slot)


## `n` beads along `spine`, the first `first` m in and then every `gap`, into slots from `slot`.
## How many it laid.
func _lay(spine: PackedVector3Array, first: float, gap: float, n: int, size: float, tint: Color,
		to_bank: Transform3D, slot: int) -> int:
	var laid := 0
	var want := first
	var walked := 0.0
	var scale := Basis.from_scale(Vector3.ONE * size)
	for i in range(1, spine.size()):
		var a := spine[i - 1]
		var b := spine[i]
		var piece := a.distance_to(b)
		while laid < n and want <= walked + piece and slot + laid < CAPACITY:
			var at := a.lerp(b, (want - walked) / piece if piece > 0.0 else 0.0)
			move_slot(slot + laid, Transform3D(scale, to_bank * at))
			set_colour(slot + laid, tint)
			laid += 1
			want += gap
		walked += piece
		if laid >= n:
			break
	return laid


## How many beads are on `carrier` now.
func beads_on(carrier: Node) -> int:
	return int(on.get(carrier.get_instance_id(), 0))


## The slots `carrier`'s beads are in this frame: the first, and how many.
func slots_of(carrier: Node) -> Vector2i:
	var from := 0
	for id in on:
		if id == carrier.get_instance_id():
			return Vector2i(from, int(on[id]))
		from += int(on[id])
	return Vector2i(from, 0)


## Where the beads on `carrier` are, in world space, in order along it.
func places_on(carrier: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var slots := slots_of(carrier)
	for k in slots.y:
		var at := transform_of(slots.x + k).origin
		out.append(global_transform * at if is_inside_tree() else at)
	return out


## A carrier for anything with a line and a level: `spine` (world space), and `level` () -> float.
## A modular's patch cable, or the suite's.
class Run extends Node3D:
	var spine := PackedVector3Array()
	var level: Callable = Callable()
	var radius := 0.0025
	var _length := -1.0

	func _enter_tree() -> void:
		add_to_group(SignalBeads.CARRIERS)

	func lay(points: PackedVector3Array) -> void:
		spine = points
		_length = SignalBeads.length_of(points)

	func signal_spine() -> PackedVector3Array:
		return spine

	func signal_length() -> float:
		if _length < 0.0:
			_length = SignalBeads.length_of(spine)
		return _length

	func signal_level() -> float:
		return float(level.call()) if level.is_valid() else 0.0

	func signal_radius() -> float:
		return radius
