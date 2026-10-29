class_name Weather
extends Node3D

## Generative weather (docs/spatial_loop.md part two, slice 44, idea #20): in a weather
## arrangement each raindrop on the glass is a note of the song's scale, and so is each drip off the
## cave's ceiling into its pools. The loft's Thunderstorm (rain on the tall windows, in gusts), the
## greenhouse's Rain (on the glass) and the cabin's Snowy night (snow on the window, sparse and
## soft); the cave's grotto and glowworm lake have `drips`, a drop every few bars. The lava tube has
## nothing that drips, and the other arrangements no weather.
##
## A drop is a function of the song clock, never of physics or chance (`drops`): in each sixteenth
## of the song, a hash of (bar, sixteenth, the venue's seed) says whether a drop lands and where on
## the glass (or which pool). Density is the kind's (KINDS), the storm's rising and falling over
## GUST_BARS bars; the cave's drips are one candidate a bar. Each drop rings the scale tone of its
## height on the glass, higher up higher (or its pool's), from the key's root nearest the venue's
## `low` (VenueInstrument.scale_tone), softly, so it is in the song's key and retunes at a bracket.
## Everyone with the same markers, tempo and venue hears the same drops at the same song positions,
## so only the switch crosses the wire.
##
## This node is the station `weather` (Stations.ALL), mounted on the venue at its spot
## (Venue.weather_spot): on the window's sill, or on a short iron post at the floor's edge where the
## sill is past a planted bed or the pools are on the rock. It carries:
## - the switch (`Switch`): OFF, the drops fall silent; LISTEN, every machine plays them from where
##   they land. Its state is the room's row `weather` (`listening`), asked and predicted like the
##   sampler's REC, and said in words on its legend and its lever's throw, never by colour alone;
## - its plaque (Stations.plaque) and its jack (`source`: `weather`, or `drips` in the cave), a
##   source that is no item. Plugged into a track, the host records every drop onto it as it lands,
##   heard or not (HitRecorder.note): the notes the schedule says, at the song positions it says;
## - its socket on the modular's patch (slice 53, WorldSocket `modular`: `world:weather`, or
##   `world:drips` in the cave), beside the jack and independent of it: the density as a level and a
##   gate a drop, patched into the modular wall from here with a long cable (ModularWorld);
## - the drops drawn where they land (`drawn`): beads on the glass that run down it, flakes that
##   settle and melt, a drip falling into its pool and a ring on the water. Motion is scaled by
##   Ergonomics' motion_scale; at 0 a drop shows where it landed, still, and fades.
##
## The venue says what its weather is (Venue.weather): its `kind`, its `spot` (the switch's frame, its
## front +Z into the room, on the floor under it), `sill` (the switch's height), `glass` (the pane
## the drops land on, a frame at its middle, X across and Y up, +Z into the room) and its `size`, or
## the cave's `pools` (points on the water), a `post` where it stands on one, and `low`.

## The station, and the room's row and the verb that asks for it (Session.ROOM_VERBS).
const STATION := &"weather"
const VERB := &"weather"
## The two jack sources: the rain or snow on the glass, and the cave's drips (Jack.WORLD).
const SOURCE := &"weather"
const DRIPS := &"drips"
## A sixteenth, in the tempo map's quarter-note beats (HitRecorder.SIXTEENTH).
const SIXTEENTH := 0.25
## The storm's gusts rise and fall over this many bars.
const GUST_BARS := 8
## The scale tones the glass's height spans, low to high: an octave and one.
const TONES := 8
## The scale tones the pools ring, pool by pool: root, third, fifth, the octave.
const POOL_DEGREES := [0, 2, 4, 7]
## The most sixteenths one call of `drops` reads: a frame's worth many times over, and a bound.
const MOST_STEPS := 4096
## A jump of the song this far or more (s), or back, is a seek: nothing between is played.
const JUMP := 1.0
## The most drops drawn at once.
const MOST_DRAWN := 96
## How long the ring where a drop landed on the glass shows (s).
const RING_LIFE := 0.9
## A drip falls this long from the ceiling before it lands (s).
const FALL := 0.55
## How far above its pool a drip is first drawn (m), at full motion.
const FALL_FROM := 1.6
## How loud a drop is (dB) over its velocity's own level: soft.
const LEVEL_DB := -6.0
## The switch: its plate, its lever's throw (radians, up for LISTEN) and the legend's size.
const PLATE := Vector3(0.18, 0.014, 0.11)
const THROW := 0.5
const LEGEND_SIZE := 190
const LEGEND_WIDTH := 0.15
## How far the legend leans up off the plate toward whoever stands at it (radians).
const LEGEND_LEAN := 0.55
## The plaque's width, how far under the sill its top hangs, and the jack beside it.
const PLAQUE_WIDTH := 0.5
const PLAQUE_UNDER := 0.06
const JACK_SIDE := 0.06
## The post a switch stands on where it has no sill to stand on: its radius.
const POST_RADIUS := 0.035

## What each kind is: its `title` (the plaque's and the station's), its jack's `source`, its density
## (`dense`, [the least, the most] chance a sixteenth has a drop: the storm's swings with its gusts,
## the others' is the first), `gust` (whether it gusts), `velocity` [soft, firm], its Foley sound
## (`sound`, Foley.WEATHER_SOUNDS), how long its note is (`length`, s), how fast a drop runs down the
## glass at full motion (`run`, m/s), how long one is drawn (`life`, s), its colour and its bead's
## size (`bead`, m), how a drop's note is chosen in a few words (`pitch`, for the switch's hint and
## notice), and its help lines. The drips' density is the chance a bar has one.
const KINDS := {
	&"storm": {"title": "THUNDERSTORM", "source": SOURCE, "dense": [0.08, 0.42], "gust": true,
			"velocity": [42, 74], "sound": &"rain_glass", "length": 0.35, "run": 0.22, "life": 2.4,
			"pitch": "higher up the glass higher",
			"colour": Color(0.85, 0.92, 1.0, 0.95), "bead": Vector2(0.02, 0.03),
			"desk": "click the switch on the sill: LISTEN plays each raindrop on the glass as a note of the song's scale, higher up the glass higher · OFF silences them · click its jack to record the rain onto a track",
			"hands": "press the switch on the sill: LISTEN, each raindrop is a note of the song's scale, higher up the glass higher · OFF, silent · its jack into a track records them"},
	&"rain": {"title": "RAIN ON THE GLASS", "source": SOURCE, "dense": [0.16, 0.16], "gust": false,
			"velocity": [34, 58], "sound": &"rain_glass", "length": 0.35, "run": 0.16, "life": 2.6,
			"pitch": "higher up the glass higher",
			"colour": Color(0.85, 0.9, 0.97, 0.9), "bead": Vector2(0.018, 0.026),
			"desk": "click the switch on its post: LISTEN plays each raindrop on the glass as a note of the song's scale, higher up the glass higher · OFF silences them · click its jack to record the rain onto a track",
			"hands": "press the switch on the post: LISTEN, each raindrop on the glass is a note of the song's scale, higher up higher · OFF, silent · its jack into a track records them"},
	&"snow": {"title": "SNOW ON THE WINDOW", "source": SOURCE, "dense": [0.045, 0.045], "gust": false,
			"velocity": [18, 34], "sound": &"snow", "length": 0.6, "run": 0.0, "life": 4.0,
			"pitch": "higher up the glass higher",
			"colour": Color(0.97, 0.98, 1.0, 0.95), "bead": Vector2(0.026, 0.026),
			"desk": "click the switch on the sill: LISTEN plays each snowflake that lands on the window as a soft note of the song's scale, higher up higher · OFF silences them · click its jack to record the snow onto a track",
			"hands": "press the switch on the sill: LISTEN, each snowflake on the window is a soft note of the song's scale · OFF, silent · its jack into a track records them"},
	&"drips": {"title": "DRIPS", "source": DRIPS, "dense": [0.35, 0.35], "gust": false,
			"velocity": [36, 56], "sound": &"drip", "length": 0.8, "run": 0.0, "life": 1.6,
			"pitch": "each pool its own",
			"colour": Color(0.7, 0.85, 1.0, 0.85), "bead": Vector2(0.01, 0.03),
			"desk": "click the switch on its post: LISTEN plays each drip off the ceiling into the pools as a note of the song's scale, each pool its own · OFF silences them · click its jack to record the drips onto a track",
			"hands": "press the switch on the post: LISTEN, each drip into the pools is a note of the song's scale, each pool its own · OFF, silent · its jack into a track records them"},
}

## A hand here pressed the switch: `on` for LISTEN, off for OFF. For the studio to do, or ask.
signal switch_pressed(on: bool)
## A drop landed, here, at the song position the schedule says: {song, bar, step, u, v, pool, note,
## velocity, length, source}. Fired as the song plays past it, heard or not.
signal dropped(drop: Dictionary)

## What this weather is (`spec_of`).
var spec: Dictionary = {}
## The venue's seed (`seed_of`): which drops this venue's weather has.
var seed := 0
## The switch's state, the room's `weather` row: LISTEN (true) or OFF.
var listening := false:
	set(v):
		if v == listening:
			return
		listening = v
		_show()
## Where the song is, here: {seconds, playing, valid}. GuestMidi.heard by default; the suite gives
## its own.
var heard_source: Callable = Callable()
## How much of a drop's movement to show, 0..1: Ergonomics' motion_scale by default.
var motion: Callable = Callable()
var switch: Switch = null
var jack: JackSocket = null
## Its socket on the modular's patch (slice 53), beside the jack.
var modular: WorldSocket = null
## How many drops have been played aloud here, and how many landed, for the suite.
var rung := 0
var landed := 0
## The song position the schedule has been played up to, or NAN while the song is not playing.
var _until := NAN
## The drops drawn now: [drop, age (s)], oldest first.
var _shown: Array = []
## The drips falling now, drawn before they land (`FALL`): their drops.
var _falling: Array = []
var _marks: MultiMeshInstance3D = null
var _rings: MultiMeshInstance3D = null
var _take := 0


func _init(given: Dictionary = {}, venue_seed := 0) -> void:
	spec = given
	seed = venue_seed
	name = "Weather"


func _ready() -> void:
	if spec.is_empty():
		return
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.08, 0.08, 0.085)
	iron.metallic = 0.7
	iron.roughness = 0.45
	var sill := float(spec["sill"])
	if spec.get("post", false):
		var post := MeshInstance3D.new()
		post.name = "Post"
		var rod := CylinderMesh.new()
		rod.top_radius = POST_RADIUS
		rod.bottom_radius = POST_RADIUS * 1.4
		rod.height = sill
		post.mesh = rod
		post.position = Vector3(0, sill * 0.5, 0)
		post.material_override = iron
		add_child(post)
	switch = Switch.new()
	switch.weather = self
	switch.name = "Switch"
	switch.position = switch_point(spec)
	add_child(switch)
	var plaque := Stations.plaque(STATION, PLAQUE_WIDTH)
	plaque.transform = plaque_frame(spec)
	add_child(plaque)
	jack = JackSocket.new(null, source_of(spec))
	jack.label = str(spec["title"])
	# Facing out of the station's front, toward whoever stands at it, beside the plaque.
	jack.transform = Transform3D(Basis(Vector3.UP, PI), jack_point(spec))
	add_child(jack)
	modular = WorldSocket.new(ModularWorld.weather_socket(spec))
	modular.position = jack_point(spec) + Vector3(WorldSocket.BESIDE, 0, 0)
	add_child(modular)
	_build_drawing()
	_show()


# --- what a weather is ------------------------------------------------------------------------

## The weather `venue` has (Venue.weather), filled out from its kind (KINDS). Empty where it has
## none, or there is no venue.
static func spec_of(venue: Venue) -> Dictionary:
	if venue == null:
		return {}
	return filled(venue.weather())


## `given` (a venue's `weather()`) filled out from its kind: empty for none, or a kind not known.
static func filled(given: Dictionary) -> Dictionary:
	if given.is_empty() or not KINDS.has(given.get("kind", &"")) or not (given.get("spot") is Transform3D):
		return {}
	var out: Dictionary = (KINDS[given["kind"]] as Dictionary).duplicate()
	out.merge(given, true)
	if not out.has("low"):
		out["low"] = 76
	if not out.has("sill"):
		out["sill"] = 0.95
	return out


## The jack source of a weather: `weather`, or the cave's `drips`.
static func source_of(given: Dictionary) -> StringName:
	return StringName(given.get("source", SOURCE))


## Whether `source` is a weather's jack: a source that is no item, onto a track only (Jack.WORLD).
static func is_source(source: StringName) -> bool:
	return source == SOURCE or source == DRIPS


## A venue's seed: an FNV-1a hash of its id, 24 bits, the same on every machine (unlike String.hash,
## which a build is free to change).
static func seed_of(venue_id: StringName) -> int:
	var h := 2166136261
	for b in String(venue_id).to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h & 0xFFFFFF


## Three numbers into one, 32 bits, well stirred (a murmur-style finaliser). Each input is kept to
## 24 bits first, so no product overflows a 64-bit int.
static func mix(a: int, b: int, c: int) -> int:
	var h := ((a & 0xFFFFFF) * 0x9E3779B1 + (b & 0xFFFFFF) * 0x85EBCA77 + (c & 0xFFFFFF) * 0x27D4EB2F) & 0xFFFFFFFF
	h ^= h >> 15
	h = (h * 0x2C1B3C6D) & 0xFFFFFFFF
	h ^= h >> 12
	h = (h * 0x297A2D39) & 0xFFFFFFFF
	h ^= h >> 15
	return h


## A hash as a number from 0 up to 1.
static func unit(h: int) -> float:
	return float(h & 0xFFFFFF) / 16777216.0


## The chance a sixteenth of bar `bar` (from 0) has a drop: the kind's least, swinging up to its most
## and back over GUST_BARS bars where it gusts. For the drips, the chance a bar has one.
static func density(given: Dictionary, bar: int) -> float:
	var dense: Array = given.get("dense", [0.0, 0.0])
	if not given.get("gust", false):
		return float(dense[0])
	var gust := 0.5 - 0.5 * cos(TAU * float(posmod(bar, GUST_BARS)) / float(GUST_BARS))
	return lerpf(float(dense[0]), float(dense[1]), gust)


## The weather's density as it swings through bar `bar` (from 0, with its fraction), smoothly: the
## level the modular's `world:weather` socket carries (slice 53, ModularWorld). The kind's least, and
## where it gusts, rising to its most and back over GUST_BARS bars, as `density` does bar by bar.
static func level(given: Dictionary, bar: float) -> float:
	var dense: Array = given.get("dense", [0.0, 0.0])
	if not given.get("gust", false):
		return float(dense[0])
	var gust := 0.5 - 0.5 * cos(TAU * fposmod(bar, float(GUST_BARS)) / float(GUST_BARS))
	return lerpf(float(dense[0]), float(dense[1]), gust)


## Every drop of weather `given` (with venue seed `venue_seed`) that lands from song position `from`
## up to, not including, `to`, in the song `state` (its tempo, meter and brackets), in order: each
## {song (s), bar (from 0), step (its sixteenth in the bar), u and v (where on the glass, 0..1 across
## and up), pool (which pool, -1 off the glass of a pane), note, velocity, length, source}. The same
## for the same span, on every machine.
static func drops(given: Dictionary, venue_seed: int, state: MixState, from: float, to: float) -> Array:
	var out: Array = []
	if given.is_empty() or state == null or to <= from:
		return out
	var meter := state.meter()
	var first := state.beat_at(maxf(from, 0.0))
	var last := state.beat_at(maxf(to, 0.0))
	var n := ceili(first / SIXTEENTH - 0.000001)
	var drips: bool = given.get("kind", &"") == &"drips"
	var pools: Array = given.get("pools", [])
	var steps := 0
	while steps < MOST_STEPS:
		var beat := float(n) * SIXTEENTH
		n += 1
		steps += 1
		if beat >= last:
			break
		if beat < first:
			continue
		var bar := floori(meter.bar_at(beat) + 0.000001)
		var bar_from := meter.beat_of_bar(float(bar))
		var step := roundi((beat - bar_from) / SIXTEENTH)
		var h := 0
		if drips:
			# One candidate a bar, on a sixteenth of its own: a drip every few bars.
			var in_bar := maxi(roundi((meter.beat_of_bar(float(bar + 1)) - bar_from) / SIXTEENTH), 1)
			var pick := mix(bar, 0xD1, venue_seed)
			if unit(pick) >= density(given, bar) or step != posmod(pick >> 8, in_bar):
				continue
			h = mix(pick, step, venue_seed)
		else:
			h = mix(bar, step, venue_seed)
			if unit(h) >= density(given, bar):
				continue
		var song := state.seconds_at_beat(beat)
		var u := unit(mix(h, 1, venue_seed))
		var v := unit(mix(h, 2, venue_seed))
		var pool := posmod(mix(h, 3, venue_seed), pools.size()) if drips and not pools.is_empty() else -1
		var degree := mini(int(v * TONES), TONES - 1) if not drips else int(POOL_DEGREES[maxi(pool, 0) % POOL_DEGREES.size()])
		var velocity: Array = given.get("velocity", [40, 60])
		var soft := int(velocity[0])
		out.append({"song": song, "bar": bar, "step": step, "u": u, "v": v, "pool": pool,
				"note": VenueInstrument.scale_tone(Harmony.at(state, song), int(given.get("low", 76)), degree),
				"velocity": soft + posmod(mix(h, 4, venue_seed), int(velocity[1]) - soft + 1),
				"length": float(given.get("length", 0.4)), "source": source_of(given)})
	return out


## Where drop `drop` lands, in the weather's own frame (`spot`'s): on the glass at its u and v, or on
## its pool's water.
static func landing(given: Dictionary, drop: Dictionary) -> Vector3:
	var spot: Transform3D = given["spot"]
	var pool := int(drop.get("pool", -1))
	var pools: Array = given.get("pools", [])
	if pool >= 0 and pool < pools.size():
		return spot.affine_inverse() * (pools[pool] as Vector3)
	var glass: Transform3D = given.get("glass", spot)
	var size: Vector2 = given.get("size", Vector2.ONE)
	var on := Vector3((float(drop["u"]) - 0.5) * size.x, (float(drop["v"]) - 0.5) * size.y, 0.006)
	return spot.affine_inverse() * glass * on


## Where the switch sits, in its frame: on the sill (or the post's cap), a little in from the front.
static func switch_point(given: Dictionary) -> Vector3:
	return Vector3(0, float(given["sill"]), float(given.get("switch_z", 0.0)))


## Where the plaque hangs, in its frame: its top PLAQUE_UNDER under the sill (under a cabin's sill
## board), facing the room; on a post, on its front, leant back like a lectern's.
static func plaque_frame(given: Dictionary) -> Transform3D:
	var at := Vector3(0, float(given["sill"]) - PLAQUE_UNDER - plaque_half(given), float(given.get("plaque_z", 0.012)))
	if given.get("post", false):
		return Transform3D(Basis(Vector3.RIGHT, -0.35), at + Vector3(0, 0, POST_RADIUS * 1.5 + 0.03))
	return Transform3D(Basis.IDENTITY, at)


## Half the plaque's lettered height, its keys' row left out (Stations.plaque, from this weather's
## hands line): how far its top is over its middle.
static func plaque_half(given: Dictionary) -> float:
	var lines := Stations._plaque_lines(str(given.get("hands", "")), PLAQUE_WIDTH - 0.04)
	return (Stations.PLAQUE_CAP * 1.6 + lines * Stations.PLAQUE_CAP * 1.45 + 0.03) * 0.5


## Where the jack is, in its frame: off the plaque's right end, at its height.
static func jack_point(given: Dictionary) -> Vector3:
	var at := plaque_frame(given).origin
	return Vector3(PLAQUE_WIDTH * 0.5 + JACK_SIDE, at.y, at.z)


## What the station row says in this venue (Stations.row_in): its title, help lines, what a player
## looks at (the switch), what they should see (the switch over the plaque's foot) and where a
## headset stands to reach it.
static func row_for(given: Dictionary) -> Dictionary:
	if given.is_empty():
		return {}
	var sill := float(given["sill"])
	var plaque := plaque_frame(given).origin
	return {"title": given["title"], "desk": given["desk"], "hands": given["hands"],
			"at": Vector3(0, sill, 0), "frame": [Vector3(0, sill + 0.1, 0),
					Vector3(0, plaque.y - plaque_half(given) - Stations.PLAQUE_KEYS_ROW, plaque.z)],
			"reach": VenueInstrument.REACH}


## The station's walker solid where it stands on a post ({c, h, a, top}); empty on a sill, which is
## the wall's.
static func solid(given: Dictionary) -> Dictionary:
	if given.is_empty() or not given.get("post", false):
		return {}
	var at: Transform3D = given["spot"]
	return {"c": Vector2(at.origin.x, at.origin.z), "h": Vector2(0.09, 0.09), "a": at.basis.get_euler().y,
			"top": float(given["sill"]) + 0.03}


# --- playing it -------------------------------------------------------------------------------

func heard() -> Dictionary:
	if heard_source.is_valid():
		return heard_source.call()
	if Session.guest_midi != null:
		return Session.guest_midi.heard()
	return {"seconds": 0.0, "playing": false, "valid": false}


func _motion() -> float:
	if motion.is_valid():
		return clampf(float(motion.call()), 0.0, 1.0)
	return Ergonomics.current.motion_scale if Ergonomics.current != null else 1.0


func _process(delta: float) -> void:
	if spec.is_empty():
		return
	follow(heard(), delta)


## One frame of the song as heard (`h`), `delta` seconds on: every drop the song has played past since
## the last frame lands (`land`), and the drawn ones age. A jump (a seek, the loop going round, a
## stop) plays nothing between.
func follow(h: Dictionary, delta := 0.0) -> void:
	var now := float(h.get("seconds", 0.0))
	if not h.get("valid", false) or not h.get("playing", false):
		_until = NAN
	elif is_nan(_until) or now < _until or now - _until >= JUMP:
		_until = now
	elif now > _until:
		for drop: Dictionary in drops(spec, seed, DAW.state, _until, now):
			land(drop)
		_until = now
	_age(delta, now)


## Drop `drop` landing: drawn where it lands, played aloud from there while the switch says LISTEN,
## and said (`dropped`), for the jack.
func land(drop: Dictionary) -> void:
	landed += 1
	_shown.append([drop, 0.0])
	while _shown.size() > MOST_DRAWN:
		_shown.pop_front()
	if listening and is_inside_tree():
		rung += 1
		_take += 1
		var sound: StringName = spec.get("sound", &"rain_glass")
		var stream := Foley.weather_drop(sound, _take)
		var player := Foley.emitter(stream, linear_to_db(float(drop["velocity"]) / 127.0) + LEVEL_DB,
				pow(2.0, float(int(drop["note"]) - Foley.weather_drop_note(sound)) / 12.0))
		player.name = "Drop"
		player.position = landing(spec, drop)
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play()
	dropped.emit(drop)


# --- drawing it -------------------------------------------------------------------------------

func _build_drawing() -> void:
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ink.vertex_color_use_as_albedo = true
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = spec.get("bead", Vector2(0.012, 0.02))
	quad.material = ink
	_marks = _multimesh("Drops", quad)
	# Where each drop landed, a ring: on the glass, the note it rang, for a moment; on a pool, its
	# ripple. What tells the drops that are notes from the rain the glass draws by itself.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.86
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 4
	ring.material = ink
	_rings = _multimesh("Rings", ring)


func _multimesh(label: String, mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = MOST_DRAWN
	# Every instance set, unseen, before any is shown: none is drawn from whatever the buffer held.
	for n in MOST_DRAWN:
		mm.set_instance_transform(n, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.0001), Vector3.ZERO))
		mm.set_instance_color(n, Color(0, 0, 0, 0))
	mm.visible_instance_count = 0
	var holder := MultiMeshInstance3D.new()
	holder.name = label
	holder.multimesh = mm
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(holder)
	return holder


## The drawn drops grown `delta` older, those past their `life` gone, the cave's falling drips found
## ahead of the song (they are on the schedule already), and every one put where it is now.
func _age(delta: float, now: float) -> void:
	var life := float(spec.get("life", 2.0))
	for shown: Array in _shown:
		shown[1] = float(shown[1]) + delta
	_shown = _shown.filter(func(s: Array) -> bool: return float(s[1]) < life)
	_falling = []
	if _drips() and not is_nan(_until) and _motion() > 0.0:
		_falling = drops(spec, seed, DAW.state, now, now + FALL)
	_draw(now)


## Each drawn drop as it is now: [position in this frame, how strongly it shows 0..1, falling]; and
## each drip still falling, ahead of its landing (falling true). What the drawing shows, and what the suite reads.
func drawn(now := NAN) -> Array:
	var out: Array = []
	var life := float(spec.get("life", 2.0))
	var moves := _motion()
	var run := float(spec.get("run", 0.0)) * moves
	var bottom := -0.5 * float((spec.get("size", Vector2.ONE) as Vector2).y)
	for shown: Array in _shown:
		var drop: Dictionary = shown[0]
		var age := float(shown[1])
		var p := landing(spec, drop)
		if run > 0.0 and int(drop.get("pool", -1)) < 0:
			# Down the glass, in the glass's own up, as far as its foot.
			var glass: Transform3D = spec["glass"]
			var spot: Transform3D = spec["spot"]
			var on := glass.affine_inverse() * (spot * p)
			on.y = maxf(on.y - run * age, bottom)
			p = spot.affine_inverse() * glass * on
		out.append([p, clampf(1.0 - age / life, 0.0, 1.0), false])
	if not is_nan(now):
		for drop: Dictionary in _falling:
			var left := clampf((float(drop["song"]) - now) / FALL, 0.0, 1.0)
			out.append([landing(spec, drop) + Vector3.UP * FALL_FROM * left * left * moves, 1.0, true])
	return out


func _draw(now: float) -> void:
	if _marks == null:
		return
	var marks := _marks.multimesh
	var colour: Color = spec.get("colour", Color.WHITE)
	var turn := Basis.IDENTITY
	if spec.has("glass"):
		turn = ((spec["spot"] as Transform3D).affine_inverse() * (spec["glass"] as Transform3D)).basis.orthonormalized()
	var drips := _drips()
	var at := 0
	var ripples := 0
	var moves := _motion()
	for each: Array in drawn(now):
		if at >= MOST_DRAWN:
			break
		# A drip that has landed is its ripple, below; one still falling is a drop.
		if drips and not each[2]:
			continue
		var show := float(each[1])
		marks.set_instance_transform(at, Transform3D((turn if not drips else Basis.IDENTITY).scaled(Vector3.ONE * lerpf(0.6, 1.0, show)), each[0]))
		marks.set_instance_color(at, Color(colour, colour.a * show))
		at += 1
	marks.visible_instance_count = at
	var rings := _rings.multimesh
	var life := float(spec.get("life", 2.0)) if drips else RING_LIFE
	var wide := 0.3 if drips else 0.05
	# Lying on the water, or standing in the glass's plane.
	var lie := Basis.IDENTITY if drips else turn * Basis(Vector3.RIGHT, PI * 0.5)
	for shown: Array in _shown:
		if ripples >= MOST_DRAWN:
			break
		var age := float(shown[1])
		if age >= life:
			continue
		# Out from where it landed, wider as it ages; at motion 0 one size, fading.
		var r := lerpf(0.03, 0.03 + wide * age / life, moves) if moves > 0.0 else 0.03 + wide * 0.5
		rings.set_instance_transform(ripples, Transform3D(lie * Basis.IDENTITY.scaled(Vector3(r, 0.02, r)),
				landing(spec, shown[0]) + (Vector3.UP * 0.004 if drips else Vector3.ZERO)))
		rings.set_instance_color(ripples, Color(colour, colour.a * clampf(1.0 - age / life, 0.0, 1.0)))
		ripples += 1
	rings.visible_instance_count = ripples


## How a drop's note is chosen, in a few words, for the switch's hint and notice: its kind's
## `pitch`, higher up the glass higher where it has none.
static func pitch_of(given: Dictionary) -> String:
	return str(given.get("pitch", "higher up the glass higher"))


## Whether this is the cave's drips, which fall into pools, rather than drops on glass.
func _drips() -> bool:
	return spec.get("kind", &"") == &"drips"


# --- the switch -------------------------------------------------------------------------------

## A hand here pressed the switch: LISTEN if it was OFF, OFF if it was LISTEN.
func press() -> void:
	switch_pressed.emit(not listening)


## What the switch says: LISTEN or OFF.
func state_text() -> String:
	return "LISTEN" if listening else "OFF"


func _show() -> void:
	if switch == null:
		return
	switch.lever.rotation.x = -THROW if listening else THROW
	if switch.legend.text != state_text():
		switch.legend.text = state_text()
		Lettering.fit(switch.legend, LEGEND_WIDTH, LEGEND_SIZE, 70)


## The switch: a toggle on a small iron plate, its lever thrown up for LISTEN and down for OFF, and
## the word for which lettered in front of it. A press is the weather's (`press`).
class Switch extends ControlAffordance:
	var weather: Weather
	var lever: Node3D
	var legend: Label3D

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(PLATE.x + 0.02, 0.07, PLATE.z + 0.02)
		shape.shape = box
		shape.position = Vector3(0, 0.03, 0)
		add_child(shape)
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color(0.1, 0.1, 0.11)
		iron.metallic = 0.6
		iron.roughness = 0.45
		var plate := MeshInstance3D.new()
		plate.name = "Plate"
		var slab := BoxMesh.new()
		slab.size = PLATE
		plate.mesh = slab
		plate.position = Vector3(0, PLATE.y * 0.5, 0)
		plate.material_override = iron
		add_child(plate)
		lever = Node3D.new()
		lever.name = "Lever"
		lever.position = Vector3(0, PLATE.y, -0.03)
		add_child(lever)
		var bat := MeshInstance3D.new()
		bat.name = "Bat"
		var rod := CylinderMesh.new()
		rod.top_radius = 0.006
		rod.bottom_radius = 0.004
		rod.height = 0.07
		bat.mesh = rod
		bat.position = Vector3(0, 0.035, 0)
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color(0.78, 0.64, 0.36)
		brass.metallic = 0.85
		brass.roughness = 0.3
		bat.material_override = brass
		lever.add_child(bat)
		legend = Label3D.new()
		legend.name = "Legend"
		legend.text = "OFF"
		legend.pixel_size = 0.0002
		legend.font_size = LEGEND_SIZE
		legend.outline_size = 0
		legend.modulate = Color(0.95, 0.92, 0.84)
		legend.shaded = false
		legend.double_sided = false
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# On the plate in front of the lever, its top toward the back, leant up a little toward
		# whoever stands at it, so it reads from there and not only from over it.
		legend.rotation.x = -PI * 0.5 + LEGEND_LEAN
		legend.position = Vector3(0, PLATE.y + 0.012, 0.03)
		Lettering.range_to_legibility(legend)
		add_child(legend)

	func personal() -> bool:
		return true

	func dwell_activates() -> bool:
		return true

	func _default_title() -> String:
		return "%s  SWITCH" % (str(weather.spec.get("title", "WEATHER")) if weather != null else "WEATHER")

	func _default_readout() -> String:
		if weather == null or not weather.listening:
			return "OFF: the drops fall silent"
		return "LISTEN: each drop a note of the song's scale, heard by everyone"

	func hint() -> String:
		if weather != null and weather.listening:
			return "press for OFF · its jack records the drops onto a track, heard or not"
		return "press for LISTEN: each drop a note of the song's scale, %s · its jack records them onto a track" \
				% Weather.pitch_of(weather.spec if weather != null else {})

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		if weather != null:
			weather.press()
