class_name GrainCloud
extends Node3D

## A sample as a cloud of grains (docs/spatial_loop.md part two, slice 54; idea #24): reach into the
## cloud and it plays grains from where your hand is; spread the fingers to widen the spray.
## Granular synthesis made intuitive.
##
## WHAT IT PLAYS. A plinth with a bowl on it (station `grains`, Venue.grains_spot, a trolley in a
## studio) and a cloud a metre across hanging over it. A cassette put in the bowl (the room's holder
## `bowl`, one slot) is the cloud's sound: a sample cassette's file (slice 26) or an audio clip's,
## a MIDI clip's render through the built-in instrument, or a demo part's window as the song plays
## it there (CassetteItem.sound_work), as the platter and the ear hear them. A guest without the
## file fetches it from the host (FileSend), and the tag says FETCHING meanwhile. The sound's length
## lies left to right across the cloud, drawn as motes, brightest where it is loud
## (GrainVoice.envelope_of). An empty cloud is faint, and its tag says to put a sample in the bowl.
##
## THE HAND. A hand in the cloud (a tracked bare hand's palm, a controller, or at a desk the mouse
## held on its face, `Face`) plays grains from where it is: across is where in the sound (`at_for`,
## the start at the left), up is how long each grain is (`length_for`, SHORTEST to LONGEST), and in,
## away from whoever stands at it, is how many a second (`density_for`, SPARSEST at the front face
## to DENSEST at the back). Spreading the fingers (the span of a bare hand's thumb and little tips,
## a controller's grip travel, the desk's wheel) widens the spray, up to SPREAD_MOST of the sound
## either way. At a desk the face has no depth: Shift with the wheel is the density.
##
## EVENTS, NEVER THE HAND. Thirty times a second (GrainVoice.EVENT_HZ) the hand is read into an
## event (`events`, GrainVoice.event: where, how long, how many, how wide, how pitched, and its
## tick), and the voice plays that event. Nothing reaches the voice from the hand directly, so what
## it plays is what the same events render anywhere (GrainVoice.render): what slice 55 sends to
## bandmates and keeps as a take. A window missed in a long frame still counts its tick, so the
## ticks keep time with the clock the song keeps.
##
## THE BAND AND THE TAKE (slice 55). Each event played is `played`, for the studio to send
## (Session.send_grains), which keeps it in this player's take while the song records
## (GrainTakes): ended, the host renders it from its own copy of the sound as an audio take named
## `grains`. A bandmate's events arrive here (`hear`) and play on a voice of theirs from this cloud's
## sound, out of the air at the cloud on the room's bus, THEIRS_WAIT windows behind so the network's
## unevenness is ridden over, each window the event of its own tick (or a rest), so what is heard
## of them is what their events render. A bandmate's grains light the cloud's sparks where they play
## from too, and the tag says who plays it.
##
## KEY. Its KEY switch (the room's row `grains_key`, so everyone's cloud is the same) pitches every
## grain by the chord's root from the key's tonic (`pitch_for`): the chord moves and the cloud
## moves with it, never further than a fourth down or a tritone up. Off, the sound is at its own pitch.
##
## HEARD. This player's own on their MONITOR, through Godot's mixer, at the figure on its tag
## (GrainVoice.latency_seconds): a texture one player makes, as decided; a bandmate's from the cloud.
##
## Everything that moves by itself (the motes' shimmer, the sparks' drift) is scaled by
## Ergonomics.motion_scale. Nothing is said by colour alone: the tag says what it is doing in words,
## and the motes' brightness is the sound's loudness, which the ear confirms.
##
## Its numbers are tools/blender/grain_cloud.py's, which builds the plinth, the bowl and the rail.
## Origin the middle of the plinth's foot on the floor, its front (where its player stands) +Z.

## A KEY press here: the room's ask, the studio's to answer (with none listening, it is done here).
signal key_pressed(on: bool)
## An event this player's hand made and the voice played: for the studio to send to the band and
## keep in a take (Session.send_grains).
signal played(e: PackedFloat32Array)

const STATION := &"grains"
const HOLDER := &"bowl"
## The room's row and verb for the KEY switch.
const ROW := &"grains_key"
const VERB := &"grains_key"
const MODEL := "res://assets/models/grain_cloud.glb"

## The plinth's footprint, half its size, its middle on its origin; its cap's top, the bowl on it
## (its rim, its inner floor, its radius), and how tall it stands: the bowl's rim.
const FOOT := Vector2(0.16, 0.16)
const FOOT_Z := 0.0
const PLINTH_TOP := 0.9
const BOWL_RIM := 0.95
const BOWL_FLOOR := 0.914
const BOWL_RADIUS := 0.12
const TOP := BOWL_RIM
## A cassette in the bowl, standing on its long edge, its label to the front.
const SLOT_POSE := Transform3D(Basis.IDENTITY, Vector3(0, BOWL_FLOOR, 0))
## The cloud: its middle and half its size, in the plinth's frame. A metre across, half a metre
## tall, forty centimetres deep, its back over the bowl.
const MID := Vector3(0, 1.32, 0.1)
const HALF := Vector3(0.5, 0.26, 0.2)
## The model's brass rail along the cloud's front (its height and radius, 2 cm behind the front),
## and the tag's middle: its two lines stand on the rail, between it and the cloud's foot, so the
## rail crosses no word of what plays from any eye above it.
const RAIL_Y := 0.975
const RAIL := 0.005
const TAG_AT := Vector3(0, MID.y - HALF.y - 0.035, MID.z + HALF.z)
## How far past the cloud's faces a hand still plays it, at the nearest edge's value.
const EDGE := 0.03
## Free air round the cloud (Stations `air`, round `air_at`): half its width and a little more.
const AIR := 0.55
const AIR_AT := MID
## A bare hand's spray: the span of its thumb's and little finger's tips closed (no spray) and open
## (the widest), m.
const SPAN_CLOSED := 0.05
const SPAN_OPEN := 0.17
## The desk's wheel: a notch of spray or of density (Shift), as a fraction of the whole.
const WHEEL_STEP := 0.125
## The plaque, hung on the plinth's left side (-X), the side a player coming from the desk walks up
## by where it stands in the aisle side on to the desk, so it faces them and the desk's seat rather
## than lying edge on to both: its top edge, how far out, its width; and the KEY switch's size and
## middle, on the plinth's front.
const PLAQUE_TOP := 0.76
const PLAQUE_X := -FOOT.x - 0.006
const PLAQUE_WIDE := 0.3
const KEY := Vector2(0.16, 0.07)
const KEY_AT := Vector3(0, 0.82, FOOT.y + 0.002)
## The station's frame (Stations.ALL): the cloud's top, and its plaque's foot, opened.
const FRAME_TOP := Vector3(0, MID.y + HALF.y, MID.z)
const FRAME_FOOT := Vector3(PLAQUE_X, 0.4, 0)
## What a player at it looks at: the cloud's middle.
const LOOK := MID
## The motes: columns across the sound, and motes in each; their size.
const COLUMNS := 40
const PER_COLUMN := 9
const MOTE := 0.0065
## The sparks: one for each grain sounding, lit as it starts, for SPARK_LIFE.
const SPARK_LIFE := 0.15
## The tag's width and lettering.
const TAG_WIDE := 0.7
const TAG_SIZE := 120
## How many events it keeps (the newest), for the suite and for slice 55 to send.
const EVENTS_KEPT := 300
## A bandmate's grains: how many windows behind their first event they begin (the jitter they ride
## over), how many may wait before the oldest are skipped to catch up, how loud from the cloud (dB),
## and how long after their last event the tag still says they play it (s).
const THEIRS_WAIT := 3
const THEIRS_MOST := 12
const THEIRS_DB := -3.0
const THEIRS_SAID := 0.5

## The room whose cassette its bowl holds.
var items: ItemRoom = null
## Where this machine has file `source` (an audio clip's), "" where it has none (a guest's begins a
## fetch of it); and whether a fetch of it is under way. The platter's, given by the studio.
var find_file: Callable = Callable()
var fetching: Callable = Callable()
## () -> Array of {at: Vector3 (global), by: Object, spread: 0..1}: this player's hands now. Not set,
## every local tracked bare hand's palm and every sure controller (`local_hands`).
var hands: Callable = Callable()
## () -> float: the song position its KEY reads the chord at. Not set, the playhead.
var clock: Callable = Callable()
## The KEY switch, as the room has it.
var key_on := false:
	set(v):
		key_on = v
		_show_key()
## The desk's spray and density, 0 to 1: the wheel and Shift with it over the face.
var desk_spread := 0.0
var desk_density := 0.5

## The cassette in the bowl, and how getting its sound is going.
var cassette: CassetteItem = null
enum Source { NONE, RENDERING, FETCHING, MISSING, EMPTY, READY }
var source := Source.NONE
## How long the sound in it is (s).
var seconds := 0.0
## How loud the sound is across its length (COLUMNS of it, 0 to 1).
var envelope := PackedFloat32Array()
## The events it has played, the newest last (EVENTS_KEPT at most), and how many windows it has
## counted: the next event's tick.
var events: Array[PackedFloat32Array] = []
var ticks := 0
## The hand playing it now, in its frame (INF for none), and its spray (0 to 1); and the event it
## last made, empty while no hand plays.
var hand_at := Vector3.INF
var hand_spread := 0.0
var last := PackedFloat32Array()
var voice: GrainVoice
## A bandmate's grains as they arrive (`hear`), by peer: {voice (a GrainVoice at the cloud), queue
## {tick: event}, next (the tick it plays next, -1 while it has not begun), wait (windows before it
## begins), last (the event it last played), when (the cloud's clock then)}.
var theirs := {}
var face: Face
var bowl: Bowl
var key: KeySwitch
var tag_label: Label3D

var _source_key := ""
## Sounds made, {key: [mono at GrainVoice.RATE, envelope]}, the newest last; and makings under way
## {key: [task, result]}.
var _sounds := {}
var _tasks := {}
const KEPT := 4
var _since := 0.0
var _clock := 0.0
var _fetch_looked := 0.0
const FETCH_EVERY := 0.25
var _since_shown := INF
const SHOW_EVERY := 0.1
var _motes: MultiMeshInstance3D
## How bright each column of motes is lit now (0 to 1): what they were coloured by, kept here, since
## a multimesh's colours are the renderer's to keep and not read back everywhere.
var _mote_levels := PackedFloat32Array()
var _mote_rest := PackedVector3Array()
var _mote_phase := PackedFloat32Array()
var _sparks: MultiMeshInstance3D
var _spark_age := PackedFloat32Array()
var _next_spark := 0
var _spray: MeshInstance3D
var _start_label: Label3D
var _end_label: Label3D
var _long_label: Label3D


func _init() -> void:
	name = "GrainCloud"


func _ready() -> void:
	if ResourceLoader.exists(MODEL):
		var model := (load(MODEL) as PackedScene).instantiate() as Node3D
		model.name = "Model"
		add_child(model)
	voice = GrainVoice.new()
	voice.name = "Voice"
	add_child(voice)
	face = Face.new()
	face.name = "Face"
	face.cloud = self
	face.position = Vector3(MID.x, MID.y, MID.z + HALF.z)
	add_child(face)
	bowl = Bowl.new()
	bowl.name = "Bowl"
	bowl.cloud = self
	bowl.position = Vector3(0, BOWL_RIM - 0.015, 0)
	add_child(bowl)
	key = KeySwitch.new()
	key.name = "KeySwitch"
	key.cloud = self
	key.position = KEY_AT
	add_child(key)
	_show_key()
	var plaque := Stations.plaque(STATION, PLAQUE_WIDE)
	var top := float(plaque.get_meta(&"plaque_tall", 0.2)) * 0.5
	plaque.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(PLAQUE_X, PLAQUE_TOP - top, 0))
	add_child(plaque)
	tag_label = _letters("Tag", TAG_SIZE, TAG_AT)
	_start_label = _letters("Start", 70, Vector3(MID.x - HALF.x + 0.06, MID.y - HALF.y + 0.02, MID.z + HALF.z))
	_end_label = _letters("End", 70, Vector3(MID.x + HALF.x - 0.09, MID.y - HALF.y + 0.02, MID.z + HALF.z))
	_long_label = _letters("Long", 70, Vector3(MID.x - HALF.x + 0.08, MID.y + HALF.y - 0.02, MID.z + HALF.z))
	_long_label.text = "LONG GRAINS"
	_start_label.text = "START"
	_build_motes()
	_build_sparks()
	_build_spray()
	_show_motes()
	_show()


func _letters(called: String, size: int, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.name = called
	l.pixel_size = 0.0002
	l.font_size = size
	l.outline_size = 0
	l.modulate = Color(0.95, 0.9, 0.8)
	l.shaded = false
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = at
	Lettering.range_to_legibility(l)
	add_child(l)
	return l


## The slot's pose in the cloud's parent frame: what the room's holder is, laid by the studio.
func slot_in(frame: Transform3D) -> Transform3D:
	return frame * SLOT_POSE


## Its footprint for the walker, at `at` (Venue.grains_spot), as {c, h, a, top}.
static func solid(at: Transform3D) -> Dictionary:
	var middle := at * Vector3(0, 0, FOOT_Z)
	return {"c": Vector2(middle.x, middle.z), "h": FOOT, "a": at.basis.get_euler().y, "top": TOP}


# --- the hand's place ---------------------------------------------------------------------------

## Where in the sound (0 the start, 1 the end) a hand at `p` (its frame) plays from: across the cloud.
static func at_for(p: Vector3) -> float:
	return clampf((p.x - (MID.x - HALF.x)) / (HALF.x * 2.0), 0.0, 1.0)


## How long a grain is (s) for a hand at `p`: up the cloud, SHORTEST at its foot to LONGEST at its top.
static func length_for(p: Vector3) -> float:
	return lerpf(GrainVoice.SHORTEST, GrainVoice.LONGEST, clampf((p.y - (MID.y - HALF.y)) / (HALF.y * 2.0), 0.0, 1.0))


## How far in a hand at `p` is: 0 at the cloud's front face, 1 at its back.
static func depth_for(p: Vector3) -> float:
	return clampf(((MID.z + HALF.z) - p.z) / (HALF.z * 2.0), 0.0, 1.0)


## How many grains a second at depth `depth` (0 to 1): SPARSEST to DENSEST, each step in the same
## proportion, so the front of the cloud is a scatter and the back a smear.
static func density_of(depth: float) -> float:
	return GrainVoice.SPARSEST * pow(GrainVoice.DENSEST / GrainVoice.SPARSEST, clampf(depth, 0.0, 1.0))


static func density_for(p: Vector3) -> float:
	return density_of(depth_for(p))


## Where in its frame a hand plays from `at`, grains `length` long, `density` a second: the inverse.
static func place_for(at: float, length: float, density: float) -> Vector3:
	var up := (clampf(length, GrainVoice.SHORTEST, GrainVoice.LONGEST) - GrainVoice.SHORTEST) / (GrainVoice.LONGEST - GrainVoice.SHORTEST)
	var depth := log(clampf(density, GrainVoice.SPARSEST, GrainVoice.DENSEST) / GrainVoice.SPARSEST) \
			/ log(GrainVoice.DENSEST / GrainVoice.SPARSEST)
	return Vector3(MID.x - HALF.x + clampf(at, 0.0, 1.0) * HALF.x * 2.0, MID.y - HALF.y + up * HALF.y * 2.0,
			MID.z + HALF.z - depth * HALF.z * 2.0)


## Whether a hand at `p` (its frame) is in the cloud, EDGE past its faces counting.
static func inside(p: Vector3) -> bool:
	var d := (p - MID).abs()
	return d.x <= HALF.x + EDGE and d.y <= HALF.y + EDGE and d.z <= HALF.z + EDGE


## A bare hand's spray (0 to 1) from the span of its thumb's and little finger's tips (m).
static func spread_of_span(span: float) -> float:
	return clampf((span - SPAN_CLOSED) / (SPAN_OPEN - SPAN_CLOSED), 0.0, 1.0)


## How far the grains are pitched (semitones) in harmony `h` with KEY `on`: the chord's root from
## the key's tonic, the nearer way round, a fourth down (-5) to a tritone up (+6), so the cloud
## follows the chord without leaping; 0 with KEY off.
static func pitch_for(h: Harmony, on: bool) -> float:
	if not on or h == null or h.chord.is_empty():
		return 0.0
	return float(wrapi(h.chord[0] - h.root, -5, 7))


## Every hand of this player's in `tree`: each tracked bare hand's palm, seen with confidence, its
## spray its tips' span; and each sure controller, its spray its grip's travel, as {at, by, spread}.
static func local_hands(tree: SceneTree) -> Array:
	var out: Array = []
	if tree == null:
		return out
	for node in tree.get_nodes_in_group(HandGestures.GROUP):
		var g := node as HandGestures
		if g != null and g.tracked and g.confident and g.joints.size() > HandPose.TIPS[3]:
			var span := g.joints[HandPose.THUMB_TIP].distance_to(g.joints[HandPose.TIPS[3]])
			out.append({"at": g.palm(), "by": g, "spread": spread_of_span(span)})
	for node in tree.get_nodes_in_group(Interactor.GROUP):
		var hand := node as XRInteractor
		if hand == null or hand.bare_hand():
			continue
		var c := hand.controller
		if c != null and c.is_inside_tree() and Strike.controller_sure(c):
			var travel := hand.finger_travel()
			var grip := travel[1] if travel.size() > 1 and is_finite(travel[1]) else 0.0
			out.append({"at": c.global_position, "by": hand, "spread": clampf(grip, 0.0, 1.0)})
	return out


## The song position its KEY reads the chord at.
func now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return DAW.state.position_seconds if DAW.state != null else 0.0


## The harmony it is pitched in now: this player's (their chord hand's chord in the song's key).
func harmony_now() -> Harmony:
	return ChordHand.at(now())


## The hand that plays it now, as {at (its frame), spread (0 to 1), desk}: the nearest the cloud's
## middle of the hands in it, or, with none, the mouse holding its face, its spray and density the
## wheel's. Empty for none.
func reading() -> Dictionary:
	var readings: Array = hands.call() if hands.is_valid() else local_hands(get_tree() if is_inside_tree() else null)
	var best := {}
	var nearest := INF
	for r: Dictionary in readings:
		var p := to_local(r["at"] as Vector3)
		if inside(p) and p.distance_to(MID) < nearest:
			nearest = p.distance_to(MID)
			best = {"at": p, "spread": clampf(float(r.get("spread", 0.0)), 0.0, 1.0), "desk": false}
	if best.is_empty() and face != null and face.player() != null:
		var m := face.player()
		var p := to_local(face.point_of(m))
		p.z = MID.z + HALF.z - clampf(desk_density, 0.0, 1.0) * HALF.z * 2.0
		best = {"at": p, "spread": desk_spread, "desk": true}
	return best


## The event a hand at `r` (`reading`) makes now, at tick `tick`.
func event_for(r: Dictionary, tick: int) -> PackedFloat32Array:
	var p: Vector3 = r["at"]
	return GrainVoice.event(tick, at_for(p), length_for(p), density_for(p),
			float(r["spread"]) * GrainVoice.SPREAD_MOST, pitch_for(harmony_now(), key_on))


# --- each frame -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	step(delta)


## A frame `delta` seconds on: the bowl watched, its sound collected, the windows due played, and
## what it shows brought up to date.
func step(delta: float) -> void:
	_clock += delta
	_watch_bowl()
	_collect()
	_since += maxf(delta, 0.0)
	var window := 1.0 / GrainVoice.EVENT_HZ
	var due := 0
	while _since >= window and due < 4:
		_since -= window
		due += 1
		play_window()
	if _since >= window:
		# Fallen behind (a long frame): the windows it missed are rested, not played late, but counted,
		# so the ticks keep the clock's time and a take renders the gap where it fell.
		ticks += floori(_since / window)
		_since = 0.0
	_animate(delta)
	_since_shown += delta
	if _since_shown >= SHOW_EVERY:
		_show()


## One window (an EVENT_HZ'th of a second): the hand read into an event and played, or, with no
## hand in it or no sound to play, a rest.
func play_window() -> void:
	var r := reading()
	hand_at = r.get("at", Vector3.INF)
	hand_spread = float(r.get("spread", 0.0))
	_play_theirs()
	if r.is_empty() or source != Source.READY:
		last = PackedFloat32Array()
		if voice != null:
			voice.rest()
		ticks += 1
		return
	last = event_for(r, ticks)
	ticks += 1
	events.append(last)
	if events.size() > EVENTS_KEPT:
		events.remove_at(0)
	if voice != null:
		voice.play(last)
		_light_sparks(voice.last_born(), hand_at)
	played.emit(last)


## Whether a hand plays it now.
func playing() -> bool:
	return not last.is_empty()


# --- a bandmate's grains (slice 55) ------------------------------------------------------------

## Bandmate `peer`'s grain event `e` as it arrived (Session.grains_played): queued to play from this
## cloud's sound on a voice of theirs at its own tick. Nothing plays while this cloud has no sound
## (its tag says why: FETCHING, RENDERING); one arriving after its window has gone by is dropped.
func hear(peer: int, e: PackedFloat32Array) -> void:
	if not GrainVoice.is_event(e) or source != Source.READY:
		return
	var t: Dictionary = theirs.get(peer, {})
	if t.is_empty():
		var v := GrainVoice.new()
		v.name = "Theirs%d" % peer
		v.speaker = self
		v.speaker_at = MID
		v.volume_db = THEIRS_DB
		add_child(v)
		v.use(voice.source if voice != null else PackedFloat32Array())
		t = {"voice": v, "queue": {}, "next": -1, "wait": THEIRS_WAIT, "last": PackedFloat32Array(), "when": -INF}
		theirs[peer] = t
	var tick := int(e[GrainVoice.TICK])
	if int(t["next"]) >= 0 and tick < int(t["next"]):
		return
	(t["queue"] as Dictionary)[tick] = e


## Bandmate `peer` gone: their voice let go.
func forget(peer: int) -> void:
	var t: Dictionary = theirs.get(peer, {})
	theirs.erase(peer)
	if not t.is_empty() and is_instance_valid(t["voice"]):
		(t["voice"] as GrainVoice).queue_free()


## The voice bandmate `peer`'s grains play on here, or null.
func voice_of(peer: int) -> GrainVoice:
	var t: Dictionary = theirs.get(peer, {})
	return t["voice"] if not t.is_empty() else null


## Each bandmate's window: begun THEIRS_WAIT windows after their first event arrived, then their
## event for each tick in turn, or a rest where none came (they let go, or it is late). Too far
## behind (more than THEIRS_MOST waiting), it skips to the oldest waiting. Once nothing waits and
## their voice has rung out and let its player go, the next event begins afresh.
func _play_theirs() -> void:
	for peer: int in theirs:
		var t: Dictionary = theirs[peer]
		var queue: Dictionary = t["queue"]
		var v: GrainVoice = t["voice"]
		if int(t["next"]) < 0:
			if queue.is_empty():
				continue
			if int(t["wait"]) > 0:
				t["wait"] = int(t["wait"]) - 1
				continue
			t["next"] = queue.keys().min()
		elif queue.size() > THEIRS_MOST:
			t["next"] = queue.keys().min()
		var tick: int = t["next"]
		if queue.has(tick):
			var e: PackedFloat32Array = queue[tick]
			queue.erase(tick)
			v.play(e)
			t["last"] = e
			t["when"] = _clock
			_light_sparks(v.last_born(), place_for(e[GrainVoice.AT], e[GrainVoice.LENGTH], e[GrainVoice.DENSITY]))
		else:
			v.rest()
		t["next"] = tick + 1
		if queue.is_empty() and not v.is_playing():
			t["next"] = -1
			t["wait"] = THEIRS_WAIT


## The bandmates playing it now (an event within THEIRS_SAID), by name.
func players() -> PackedStringArray:
	var out := PackedStringArray()
	for peer: int in theirs:
		if _clock - float(theirs[peer]["when"]) <= THEIRS_SAID:
			out.append(Session.name_of(peer))
	return out


## Whether this player's grains are being recorded now (GrainTakes.mine).
func recording() -> bool:
	return Session.grain_takes != null and Session.grain_takes.mine != null


# --- the cassette in the bowl ------------------------------------------------------------------

## The cassette in the room's bowl now: a new one's sound begun, a gone one's tag cleared.
func _watch_bowl() -> void:
	var now: CassetteItem = null
	if items != null and items.holders.has(HOLDER):
		now = items.in_slot(HOLDER, 0) as CassetteItem
	if now != null and not is_instance_valid(now):
		now = null
	if now == cassette:
		return
	if cassette != null and is_instance_valid(cassette):
		cassette.hearing = ""
	if voice != null:
		voice.stop()
	for peer: int in theirs:
		var t: Dictionary = theirs[peer]
		(t["voice"] as GrainVoice).stop()
		(t["queue"] as Dictionary).clear()
		t["next"] = -1
		t["wait"] = THEIRS_WAIT
	cassette = now
	source = Source.NONE
	_source_key = ""
	seconds = 0.0
	envelope = PackedFloat32Array()
	last = PackedFloat32Array()
	if cassette != null:
		_load()
	_show_motes()
	_show()


## What the cassette in the bowl is heard as: its sound, kept, or begun on a worker.
func _load() -> void:
	var clip := cassette.clip
	var k := Platter.key_of(clip)
	_source_key = k
	if _sounds.has(k):
		_ready_with(k)
		return
	var item := MixWire.unpack_item(clip)
	if item == null:
		_mark(Source.EMPTY)
		return
	var work := CassetteItem.sound_work(item, GrainVoice.RATE)
	if work.is_valid():
		_make(k, work)
		return
	if item.source.is_empty():
		_mark(Source.EMPTY)
		return
	var path := str(find_file.call(item.source)) if find_file.is_valid() else ""
	if path.is_empty():
		var waiting := bool(fetching.call(item.source)) if fetching.is_valid() else false
		_mark(Source.FETCHING if waiting else Source.MISSING)
		return
	var wav := AudioStreamWAV.load_from_file(path)
	var offset := item.source_offset
	var long := item.length
	var reversed := item.reversed
	_make(k, func() -> Array:
		return [Varispeed.frames_of(wav, offset, long, reversed), wav.mix_rate if wav != null else 0])


## Sound `k` made on a worker from `work` (-> [stereo frames, their rate]): mono at the voice's rate
## and its envelope.
func _make(k: String, work: Callable) -> void:
	_mark(Source.RENDERING)
	if _tasks.has(k):
		return
	var result := [null]
	var job := func() -> void:
		var made: Array = work.call()
		var mono := GrainVoice.mono_of(made[0], int(made[1]))
		result[0] = [mono, GrainVoice.envelope_of(mono, COLUMNS)]
	_tasks[k] = [WorkerThreadPool.add_task(job, false, "make a cassette's sound for the grain cloud"), result]


## Sounds made, kept; the bowl's, used; a fetch arrived, loaded.
func _collect() -> void:
	for k: String in _tasks.keys():
		var running: Array = _tasks[k]
		if not WorkerThreadPool.is_task_completed(running[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(running[0])
		_tasks.erase(k)
		var made: Variant = running[1][0]
		if made is Array and (made[0] as PackedFloat32Array).size() > 1:
			_sounds.erase(k)
			_sounds[k] = made
			while _sounds.size() > KEPT:
				_sounds.erase(_sounds.keys()[0])
	if cassette == null:
		return
	if source == Source.RENDERING and _sounds.has(_source_key):
		_ready_with(_source_key)
	elif source == Source.RENDERING and not _tasks.has(_source_key):
		_mark(Source.EMPTY)
	elif source == Source.FETCHING and _clock - _fetch_looked >= FETCH_EVERY:
		_fetch_looked = _clock
		_load()


func _ready_with(k: String) -> void:
	var made: Array = _sounds[k]
	voice.use(made[0])
	for peer: int in theirs:
		(theirs[peer]["voice"] as GrainVoice).use(made[0])
	seconds = float((made[0] as PackedFloat32Array).size()) / GrainVoice.RATE
	envelope = made[1]
	_mark(Source.READY)
	_show_motes()


func _mark(s: Source) -> void:
	source = s
	if cassette != null and is_instance_valid(cassette):
		cassette.hearing = tag()
	_show()


func _exit_tree() -> void:
	for running: Array in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(running[0])
	_tasks.clear()


# --- what it says -----------------------------------------------------------------------------

## The cassette's tag in the bowl, and the cloud's: how it is heard, at its figure, or why it is not.
func tag() -> String:
	match source:
		Source.READY:
			return "GRAINS · MONITOR %d ms" % roundi(GrainVoice.latency_seconds() * 1000.0)
		Source.RENDERING:
			return "RENDERING"
		Source.FETCHING:
			return "FETCHING"
		Source.MISSING:
			return "not on this machine"
		Source.EMPTY:
			return "nothing to play"
	return "PUT A SAMPLE IN THE BOWL"


## The lettering under the cloud: what it plays and how, or what it wants.
func tag_text() -> String:
	if cassette == null:
		return "PUT A SAMPLE IN THE BOWL\na cassette off the rack, or any clip"
	var what := cassette.clip_name()
	if source != Source.READY:
		return "%s\n%s" % [what, tag().to_upper() if source != Source.MISSING else "NOT ON THIS MACHINE"]
	if playing():
		return "%s · %s\n%s%s" % [what, tag(), "REC · " if recording() else "", play_words()]
	var band := players()
	if not band.is_empty():
		return "%s · %s\n%s %s playing it · reach in too" % [what, tag(), " and ".join(band), "is" if band.size() == 1 else "are"]
	return "%s · %s\nreach in to play it" % [what, tag()]


## What the grains are now, in words: where, how long, how many, how wide.
func play_words() -> String:
	if last.is_empty():
		return ""
	var pitch := "" if is_zero_approx(last[GrainVoice.PITCH]) else " · %+d semitones" % roundi(last[GrainVoice.PITCH])
	return "at %.2f s · %d ms grains · %d a second · spray ±%d%%%s" % [last[GrainVoice.AT] * seconds,
			roundi(last[GrainVoice.LENGTH] * 1000.0), roundi(last[GrainVoice.DENSITY]),
			roundi(last[GrainVoice.SPREAD] * 100.0), pitch]


## What happens to this player's grains while the song records, in words.
func take_words() -> String:
	if recording():
		var t := GrainTakes.track()
		var called := DAW.state.track(t).display_name() if DAW.state != null and DAW.state.tracks.has(t) else "its track"
		return "REC: your grains go onto %s as audio" % called
	return "while the song records, your grains go onto the armed track as audio"


## What KEY does, in words.
func key_words() -> String:
	if not key_on:
		return "KEY off: the sound at its own pitch"
	var h := harmony_now()
	return "KEY on: pitched by %s's root in %s, %+d semitones now" % [h.chord_name, h.key_name if h.named else "C major (no key set)",
			roundi(pitch_for(h, true))]


func _show() -> void:
	_since_shown = 0.0
	if tag_label == null:
		return
	var said := tag_text()
	if said != tag_label.text:
		tag_label.text = said
		Lettering.fit(tag_label, TAG_WIDE, TAG_SIZE, 50)
	var end := "END · %.2f s" % seconds if cassette != null and source == Source.READY else "END"
	if _end_label.text != end:
		_end_label.text = end


func _show_key() -> void:
	if key != null:
		key.show_legend("KEY\n%s" % ("ON" if key_on else "OFF"))


# --- what it shows ----------------------------------------------------------------------------

func _build_motes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 54
	var mesh := SphereMesh.new()
	mesh.radius = MOTE
	mesh.height = MOTE * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _glow()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = COLUMNS * PER_COLUMN
	_mote_rest.resize(mm.instance_count)
	_mote_phase.resize(mm.instance_count)
	for c in COLUMNS:
		for k in PER_COLUMN:
			var n := c * PER_COLUMN + k
			var x := MID.x - HALF.x + (float(c) + rng.randf()) / COLUMNS * HALF.x * 2.0
			_mote_rest[n] = Vector3(x, MID.y + rng.randf_range(-HALF.y, HALF.y), MID.z + rng.randf_range(-HALF.z, HALF.z))
			_mote_phase[n] = rng.randf() * TAU
			mm.set_instance_transform(n, Transform3D(Basis.IDENTITY, _mote_rest[n]))
	_motes = MultiMeshInstance3D.new()
	_motes.name = "Motes"
	_motes.multimesh = mm
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_motes)


func _build_sparks() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = MOTE * 1.8
	mesh.height = MOTE * 3.6
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = _glow()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = GrainVoice.MOST
	_spark_age.resize(mm.instance_count)
	for n in mm.instance_count:
		_spark_age[n] = SPARK_LIFE
		mm.set_instance_transform(n, Transform3D(Basis.IDENTITY, MID))
		mm.set_instance_color(n, Color(0, 0, 0, 0))
	_sparks = MultiMeshInstance3D.new()
	_sparks.name = "Sparks"
	_sparks.multimesh = mm
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sparks)


func _build_spray() -> void:
	_spray = MeshInstance3D.new()
	_spray.name = "Spray"
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.008, 0.008)
	_spray.mesh = box
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.92, 0.75, 0.55)
	_spray.material_override = m
	_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spray.visible = false
	add_child(_spray)


static func _glow() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


## The motes lit by the sound: each column as bright as its stretch is loud, faint where it is
## quiet, and all of them faint and grey with nothing in the bowl.
func _show_motes() -> void:
	if _motes == null:
		return
	var mm := _motes.multimesh
	var lit := source == Source.READY and envelope.size() == COLUMNS
	_mote_levels.resize(COLUMNS)
	for c in COLUMNS:
		var level := 0.08 + 0.92 * envelope[c] if lit else 0.1
		_mote_levels[c] = level
		var colour := Color(1.0, 0.78, 0.5) * level if lit else Color(0.6, 0.62, 0.66) * level
		colour.a = 1.0
		for k in PER_COLUMN:
			mm.set_instance_color(c * PER_COLUMN + k, colour)


## A column of motes' brightness now, 0 to 1: the faint floor everywhere with nothing to play, and
## with a sound, its stretch's loudness over it. What the suite reads.
func mote_level(column: int) -> float:
	if column < 0 or column >= _mote_levels.size():
		return 0.0
	return _mote_levels[column]


## The grains the last window started, lit where they play from at the height and depth of the hand
## that played them (`at`, in its frame).
func _light_sparks(born: PackedFloat32Array, at_hand: Vector3) -> void:
	if _sparks == null or at_hand == Vector3.INF:
		return
	var mm := _sparks.multimesh
	for b in born.size():
		var n := _next_spark
		_next_spark = (_next_spark + 1) % mm.instance_count
		var jitter := float(hash(ticks * 37 + b) % 1000) / 1000.0 - 0.5
		var at := Vector3(MID.x - HALF.x + born[b] * HALF.x * 2.0, at_hand.y + jitter * 0.04,
				clampf(at_hand.z + jitter * 0.06, MID.z - HALF.z, MID.z + HALF.z))
		mm.set_instance_transform(n, Transform3D(Basis.IDENTITY, at))
		_spark_age[n] = 0.0


func _animate(delta: float) -> void:
	var motion := Ergonomics.current.motion_scale if Ergonomics.current != null else 1.0
	if _motes != null and motion > 0.0:
		var mm := _motes.multimesh
		for n in mm.instance_count:
			var drift := sin(_clock * 0.9 + _mote_phase[n]) * 0.01 * motion
			mm.set_instance_transform(n, Transform3D(Basis.IDENTITY, _mote_rest[n] + Vector3(0, drift, 0)))
	if _sparks != null:
		var mm := _sparks.multimesh
		for n in mm.instance_count:
			if _spark_age[n] >= SPARK_LIFE:
				continue
			_spark_age[n] += delta
			var left := clampf(1.0 - _spark_age[n] / SPARK_LIFE, 0.0, 1.0)
			mm.set_instance_color(n, Color(1.0, 0.95, 0.8, 1.0) * left)
			if motion > 0.0:
				var t := mm.get_instance_transform(n)
				t.origin.y += delta * 0.12 * motion
				mm.set_instance_transform(n, t)
	if _spray != null:
		_spray.visible = playing() and hand_at != Vector3.INF
		if _spray.visible:
			var wide := maxf(last[GrainVoice.SPREAD] * 2.0 * HALF.x * 2.0, 0.01)
			var x := MID.x - HALF.x + last[GrainVoice.AT] * HALF.x * 2.0
			var from := maxf(x - wide * 0.5, MID.x - HALF.x)
			var to := minf(x + wide * 0.5, MID.x + HALF.x)
			_spray.transform = Transform3D(Basis.from_scale(Vector3(maxf(to - from, 0.01), 1, 1)),
					Vector3((from + to) * 0.5, hand_at.y, hand_at.z))


## The cloud's front face, for a desk: the mouse held on it plays grains from where it is (across
## is where in the sound, up the grains' length), the wheel over it widens the spray, and Shift with
## the wheel thickens it (the density a headset's hand reaches in for). A headset's hands play it by
## being in it, not by this.
class Face extends ControlAffordance:
	var cloud: GrainCloud
	var _drag := Vector3.INF

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(HALF.x * 2.0, HALF.y * 2.0, 0.02)
		shape.shape = b
		add_child(shape)

	## The mouse playing it: the one holding it down, or null.
	func player() -> MouseInteractor:
		if held_by is MouseInteractor and is_instance_valid(held_by):
			return held_by as MouseInteractor
		return null

	## Where mouse `m` is on the face (global): its drag while it holds it, else where its ray rests.
	func point_of(m: MouseInteractor) -> Vector3:
		if held_by == m and _drag.is_finite():
			return _drag
		return m.hover_point

	func plays_under_cursor() -> bool:
		return true

	## Playing it is this player's own.
	func personal() -> bool:
		return true

	func grab_begin(by: Node, at: Vector3) -> void:
		# Only a desk's button: a headset's hands play it by reaching in.
		if not by is MouseInteractor:
			return
		super(by, at)
		if held_by == by:
			_drag = at

	func grab_move(by: Node, at: Vector3) -> void:
		if held_by == by:
			_drag = at
		super(by, at)

	func grab_end(by: Node) -> void:
		_drag = Vector3.INF
		super(by)

	func _on_nudge(notches: int, fine: bool) -> bool:
		if cloud == null:
			return false
		if fine:
			cloud.desk_density = clampf(cloud.desk_density + notches * WHEEL_STEP, 0.0, 1.0)
		else:
			cloud.desk_spread = clampf(cloud.desk_spread + notches * WHEEL_STEP, 0.0, 1.0)
		return true

	func _default_title() -> String:
		if cloud == null or cloud.cassette == null:
			return "GRAIN CLOUD"
		return "GRAIN CLOUD  %s" % cloud.cassette.clip_name()

	func _default_readout() -> String:
		if cloud == null:
			return ""
		if cloud.source != Source.READY:
			if cloud.cassette == null:
				return "empty: put a sample in the bowl (a cassette off the rack, or any clip pulled off the timeline)"
			return "%s: %s" % [cloud.cassette.clip_name(), cloud.tag()]
		var desk := "spray ±%d%% (wheel) · %d grains a second (Shift + wheel)" % [roundi(cloud.desk_spread * GrainVoice.SPREAD_MOST * 100.0),
				roundi(GrainCloud.density_of(cloud.desk_density))]
		var now := cloud.play_words() if cloud.playing() else desk
		return "%s · in your ears: MONITOR through Godot, %d ms; the band hears it from the cloud · %s · %s" % [now,
				roundi(GrainVoice.latency_seconds() * 1000.0), cloud.key_words(), cloud.take_words()]

	func hint() -> String:
		if InstrumentItem.hands_hint:
			return "reach in: across is where in the sound, up is longer grains, further in is more of them\nspread your fingers, or squeeze the grip, to widen the spray"
		return "hold the button on the cloud to play grains from there: across is where in the sound, up is longer grains\nthe wheel widens the spray · Shift + wheel is more grains a second"


## The bowl on the plinth: a click with a cassette in the hand puts it in, and the cloud is its sound;
## a cassette in it is taken by clicking the cassette itself. A headset lets one go into it.
class Bowl extends ControlAffordance:
	var cloud: GrainCloud

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# Taller than the bowl is deep, so from across the room it is a target the cursor can find.
		box.size = Vector3(BOWL_RADIUS * 2.0, 0.05, BOWL_RADIUS * 2.0)
		shape.shape = box
		add_child(shape)

	func personal() -> bool:
		return true

	func _default_title() -> String:
		return "GRAIN CLOUD  BOWL"

	func _default_readout() -> String:
		if cloud == null or cloud.cassette == null:
			return "empty: put a sample in the bowl, and the cloud over it is its sound"
		return "%s: %s" % [cloud.cassette.clip_name(), cloud.tag()]

	func hint() -> String:
		if InstrumentItem.hands_hint:
			return "let a cassette go over the bowl to put it in · take it out by its edge"
		return "with a cassette in your hand, click to put it in the bowl · click the cassette to take it out"

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		var item := CassetteRack.made_in(hand)
		if item == null or cloud == null or cloud.items == null:
			if cloud != null and cloud.cassette == null:
				Session.notice.emit("The grain cloud's bowl takes a cassette: one off the rack, a sample, or a clip pulled off the timeline.")
			return
		cloud.items.slot_item(item, HOLDER, 0)


## The KEY switch on the plinth's front, lettered KEY over ON or OFF: pressed, it turns over, for
## everyone (the room's row); the wheel either way.
class KeySwitch extends ControlAffordance:
	var cloud: GrainCloud
	var legend: Label3D

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(KEY.x, KEY.y, 0.02)
		shape.shape = b
		add_child(shape)
		var face := MeshInstance3D.new()
		face.name = "Face"
		var slab := BoxMesh.new()
		slab.size = Vector3(KEY.x - 0.008, KEY.y - 0.008, 0.006)
		face.mesh = slab
		face.position = Vector3(0, 0, 0.001)
		var cap := StandardMaterial3D.new()
		cap.albedo_color = Color(0.1, 0.09, 0.08)
		cap.roughness = 0.55
		face.material_override = cap
		add_child(face)
		legend = Label3D.new()
		legend.name = "Legend"
		legend.pixel_size = 0.0002
		legend.font_size = 78
		legend.outline_size = 0
		legend.modulate = Color(0.96, 0.9, 0.76)
		legend.shaded = false
		legend.double_sided = false
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		legend.position = Vector3(0, 0, 0.0045)
		Lettering.range_to_legibility(legend)
		add_child(legend)

	func show_legend(text: String) -> void:
		legend.text = text
		Lettering.fit(legend, KEY.x - 0.014, 78, 40)

	func dwell_activates() -> bool:
		return true

	func _default_title() -> String:
		return "GRAIN CLOUD  KEY  %s" % ("ON" if cloud != null and cloud.key_on else "OFF")

	func _default_readout() -> String:
		return "%s · for everyone in the room" % cloud.key_words() if cloud != null else ""

	func hint() -> String:
		return "press to follow the chord's root, or not · %s either way" % ("the stick" if InstrumentItem.hands_hint else "the wheel")

	func grab_begin(by: Node, at: Vector3) -> void:
		super(by, at)
		if held_by == by and cloud != null:
			cloud.press_key(not cloud.key_on)

	func _on_nudge(notches: int, _fine: bool) -> bool:
		if cloud == null or notches == 0:
			return false
		cloud.press_key(notches > 0)
		return true


## A hand here pressed KEY to `on`: the studio's to make the room's (`key_pressed`), or done here when
## nothing listens.
func press_key(on: bool) -> void:
	if key_pressed.get_connections().is_empty():
		key_on = on
		return
	key_pressed.emit(on)
