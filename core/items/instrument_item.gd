class_name InstrumentItem
extends Item

## Something you play by shaking it: a shaker, a tambourine (docs/items_loop.md).
##
## A hit is a stroke that stops. The hand moves the instrument one way and brings it up short --
## or turns it round -- and the beads or the jingles carry on and hit: so the instrument watches
## where the hand that has it shakes it from (`Interactor.shake_point`), keeps the fastest it went
## this stroke, and plays when the stroke has lost most of that speed or gone back the other
## way. How hard is how fast the stroke was. In a headset that is the controller moving; on a
## desktop it is the mouse, which wiggles the hand that holds it (MouseInteractor). A click is
## one firm hit, the way a tambourine is struck with the heel of a hand.
##
## A hit played here is heard at once, by the player, and is `played` for the studio to tell
## everyone and to record. Where the studio's hits helper runs (`fast_path`, NativeKeys:
## docs/spatial_loop.md part two, slice 39) it is played there, a few milliseconds after the hand,
## panned a little to the hand's side (HAND_PAN); where it does not, or has not loaded that sound
## yet, on their own keys' bus through Godot (AudioPorts.MONITOR, "MY KEYS" in a personal mix),
## tens of milliseconds late. Its hover card says which, and how late (`path_words`).
## Anyone else's hit is heard in the room, from their hand or where it stands (`heard`), always
## through Godot: a sound placed in the room is Godot's to place.
##
## A pitched instrument (a handbell, docs/spatial_loop.md slice 4) plays a note that is a function
## of song position (`note_at`). Each hit takes ONE song position, read from `clock` as it is
## played: that one position pitches what is heard here, is what the take records it at
## (HitRecorder.hit), and is what it is sent with (`played`'s `at`, Session.send_item_hit's
## `song`). Whoever hears it elsewhere pitches it by that same position (`heard`), so a hit played
## just before a bar line rings the old chord's tone everywhere, however late it arrives.
##
## Hand percussion (`held_in_fist`: the shaker, the tambourine) is held in a closed bare hand as
## well as a pinch or a controller (XRInteractor.step_hold, docs/spatial_loop.md slice 17), round
## its `grip_point`, and its strokes are read off the palm then. Its recorded hits are snapped
## gently to the beat (HitRecorder.snapped_at): the take's note moves, never the sound. Its card
## says so while this player snaps, and in a headset how it is held (`tag_text`).
##
## Every instrument has an output jack (`jack`, a JackSocket at `jack_point`, docs/spatial_loop.md
## slice 5). Unplugged, a hit does all of the above and nothing else; plugged into a track, the
## take it is recorded in goes onto that track instead of the armed one (Jacks, HitRecorder).
##
## An instrument that stands still (`Item.fixed`, docs/spatial_loop.md part two, slice 38) is played
## where it is: its `faces` are struck by a hand or a controller crossing them (Strike), or a grab
## lands on it (`struck_by`: a click, 96, Shift-click 64). Where on it a strike lands is a `zone`
## (`zone_at`: bass, tone and slap on a drum, which drum on a pad), and the zone goes with the hit
## everywhere a hit goes: the sound (`zone_kind`), the note it is recorded as (`zone_note`),
## `played`, the room (Session.send_item_hit) and a bandmate's copy (`heard`), which rings it from
## where it stands, since nobody's hand has it.

## A hit played by a hand here: `velocity` 1 to 127, `struck` for a click rather than a shake, `at`
## the song position it was played to (one read of `clock`), `zone` where on it a fixed one was
## struck (&"" for none).
signal played(velocity: int, struck: bool, at: float, zone: StringName)

## Slower than this (m/s) is moving it, not playing it.
const STROKE_MIN := 0.35
## A stroke this fast (m/s) is as hard as it can be played.
const STROKE_FULL := 2.4
## A stroke has stopped when it is down to this much of its fastest.
const STOPPED := 0.4
## The least time between two hits (s): the beads have to get back across the tube.
const AGAIN_AFTER := 0.06
## How hard a click is.
const STRUCK := 104
## How long a hit is as a note, in a take.
const NOTE_SECONDS := 0.06
## The MIDI channel (0-based) a pitched item records on: not the drums' (HitRecorder.CHANNEL),
## which Tour reads as hand percussion, and not the keys' (0). TourPart.ITEM_CHANNELS mirrors it.
const MELODIC_CHANNEL := 10
## The most the item path's output may be late (s, AudioServer.get_output_latency) before a
## pitched item wants a MonitorSynth voice of its own (the session panel says when it is over).
const LATENCY_MOST := 0.025

## The song position a hit played now lands on, in the player's ears. Set by the studio to its
## HitRecorder's `stamp`, so this file still knows nothing of core/session/. Unset (or its owner
## gone), the playhead.
static var clock: Callable = Callable()
## Whether this player's hand percussion is snapped ("Snap hand percussion", GuestMidi.snap_hits),
## for the shelf tag to say: set by the studio, as `clock` is. Unset, not said.
static var snapping: Callable = Callable()
## Whether this player is in a headset, so the shelf tag says how a hand holds it: set by the
## studio from its medium.
static var hands_hint := false
## This player's own hits on the fast path (docs/spatial_loop.md part two, slice 39), set by the
## studio as `clock` is: called with (Foley's kind, take, gain (linear), pan (-1 to 1), speed (an
## AudioStreamPlayer's pitch_scale)), it plays the hit on the hits' helper and says true, or says
## false where it cannot (not running, that sound not loaded) and the hit is played on MONITOR.
## Unset, always MONITOR.
static var fast_path: Callable = Callable()
## How late the fast path is now (s), or a negative number while there is none: for the tag. Set
## with `fast_path`.
static var fast_latency: Callable = Callable()
## How far a hit on the fast path is panned to the side of the hand that played it: a little, so
## two hands on one drum are two hands, and never so far that a hit is only in one ear.
const HAND_PAN := 0.3
## What the shelf tag says in a headset, under SNAP.
const HANDS_HINT := "close your hand round it and shake\ncontrollers are steadier for fast parts"
## How often the shelf tag is read again (s): a setting changed shows within this.
const RETAG := 0.25

var _last := Vector3.INF
var _peak := 0.0
var _peak_way := Vector3.ZERO
var _since := 1.0
var _take := 0
## The note its last hit rang, here or heard from elsewhere (`note_at` of that hit's position).
var last_note := -1
## Where on it its last hit landed, here or heard from elsewhere (`zone_at`): &"" for one carried.
var last_zone := &""
## Which way its last hit here was heard: &"fast" on the hits' helper, &"monitor" through Godot.
var last_path := &""
## Its output jack, made as it enters the room: where what it plays goes (Jacks).
var jack: JackSocket = null

## Which of the kind's voices this copy is: 0 the first out of the case, 1 the low one. A
## second copy of a kind is a different job, not a decoy, only because it sounds (and is
## recorded) a fifth lower -- see `pitch_scale`, and each subclass's own `pitch()`.
var voice := 0
## Its shelf tag (`tag_text`), for hand percussion only: kept lettered, never shown (`_retag`).
var _tag: Label3D = null
## Whether the bandmate whose hand it is in snaps their hits, as their last hit said (`heard`).
var holder_snaps := false
## A curse on its sound only (Tour's "sour"/"low" spill): 1.0 untouched. The judge reads
## `pitch()`, not this, so a cursed instrument still plays its part -- it just sounds wrong.
var curse_pitch := 1.0
const VOICE_PITCH := [1.0, 0.8]


## How far off its own true pitch this copy's sound is played, voice and curse together.
func pitch_scale() -> float:
	return VOICE_PITCH[mini(voice, 1)] * curse_pitch


func _enter_tree() -> void:
	super()
	if fixed:
		add_to_group(Strike.GROUP)


func _ready() -> void:
	super()
	if jack == null and has_own_jack():
		jack = JackSocket.new(self)
		add_child(jack)
	if (held_in_fist() or fixed) and _tag == null:
		_tag = Label3D.new()
		_tag.name = "ShelfTag"
		_tag.font_size = 48
		_tag.pixel_size = 0.0004
		_tag.outline_size = 8
		_tag.modulate = Color(0.97, 0.94, 0.86)
		_tag.outline_modulate = Color(0.05, 0.04, 0.03)
		_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_tag.position = Vector3(0, centre_height() * 2.0 + 0.05, 0)
		_tag.visible = false
		Lettering.range_to_legibility(_tag)
		add_child(_tag)
		_retag()
		# Read again on a timer, not in a frame tick: at rest on its shelf an item does not tick.
		var again := Timer.new()
		again.name = "Retag"
		again.wait_time = RETAG
		again.autostart = true
		again.timeout.connect(_retag)
		add_child(again)


## Whether a closed bare hand holds it (XRInteractor.step_hold), not only a pinch: hand
## percussion, the shaker and the tambourine. A bell is held by its handle, by a pinch.
func held_in_fist() -> bool:
	return false


## Where a hand holds it, in global space: the point its held pose puts at the hand (`held_pose`),
## wherever it lies. What a closed hand has to close round (HandPose.grips).
func grip_point() -> Vector3:
	return global_transform * held_pose().affine_inverse().origin


## What its shelf tag would say: SNAP while this player snaps (or, in a bandmate's hand, while they
## do), and in a headset how a hand holds it and which way its hits are heard (`path_tag`); "" for
## nothing to say. Only hand percussion and the instruments that stand still have one. The card
## says the same (`readout`, `hint`), and the tag itself is never shown (`_retag`).
func tag_text() -> String:
	if not held_in_fist() and not fixed:
		return ""
	var lines: PackedStringArray = []
	var snaps := holder_snaps if is_held_elsewhere() else (snapping.is_valid() and bool(snapping.call()))
	if snaps and held_in_fist():
		lines.append("SNAP")
	if hands_hint and state != State.HELD:
		if held_in_fist():
			lines.append(HANDS_HINT)
		lines.append(path_tag())
	return "\n".join(lines)


func _retag() -> void:
	if _tag == null:
		return
	var said := tag_text()
	# Never shown: words floating over the shelf were too much of the room (2026-10-29: "i don't
	# like the floating text. its too present"). Its card, on the strip, says what it said.
	_tag.visible = false
	if _tag.text != said:
		_tag.text = said


## Where its jack is, in its own frame: out of the end on your right as you face it (-X), at its
## middle's height, just past its grip, so a ray aimed at the socket finds it before the
## instrument. From the mix position the shelf is seen along its length from that end. Override
## for an instrument with a better place (HandbellItem).
func jack_point() -> Vector3:
	var half := Vector3(0.05, 0.05, 0.05)
	var s := _shape.shape
	if s is BoxShape3D:
		half = (s as BoxShape3D).size * 0.5
	elif s is CylinderShape3D:
		half = Vector3((s as CylinderShape3D).radius, (s as CylinderShape3D).height * 0.5, (s as CylinderShape3D).radius)
	elif s is SphereShape3D:
		half = Vector3.ONE * (s as SphereShape3D).radius
	var middle := _shape.position
	return Vector3(middle.x - half.x - JackSocket.REACH * 0.6, centre_height(), middle.z)


## Which way its jack faces out of it, in its own frame: along its length, for one at its end.
func jack_out() -> Vector3:
	return Vector3.LEFT


## The source its hits are, in the room's jacks (Jacks.hit): its own id. A venue's set is one source
## however many bars it has (VenueInstrument.Bar, docs/spatial_loop.md part two, slice 42).
func jack_source() -> StringName:
	return id


## Whether it carries a jack of its own (`jack`): a venue's bars do not, the set's is on its mount.
func has_own_jack() -> bool:
	return true


## What its jack is called in a notice and on a tag (Jacks.source_name): its title, or its set's.
func jack_title() -> String:
	return item_title()


## Where its jack goes while it is unplugged (Jacks.goes_to): &"" for where any unplugged
## instrument's hits go, the armed track. The kit says the drum track (KitItem, slice 41).
func default_sink() -> StringName:
	return &""


## The General MIDI percussion note a hit is recorded as.
func pitch() -> int:
	return 82


## The note a hit played to song position `seconds` is: `pitch()` for percussion, whatever the
## song is doing. A pitched item asks the song (HandbellItem: its chord tone there).
func note_at(_seconds: float) -> int:
	return pitch()


## The harmony a pitched hit played to song position `seconds` is in: the song's, or while a
## hand here carries it, this player's own chord (ChordHand.at, docs/spatial_loop.md part two,
## slice 32), so a bell rung under a chord shape rings the shape's tone. A bandmate's carried one is
## rung here in the song's, as the hit carries only its song position.
func harmony_at(seconds: float) -> Harmony:
	if carried_by != null and is_instance_valid(carried_by):
		return ChordHand.at(seconds)
	return Harmony.at(DAW.state, seconds)


## The MIDI channel a hit is recorded on (0-based): the drums', for hand percussion.
func channel() -> int:
	return HitRecorder.CHANNEL


## How long a hit is as a note, in a take.
func note_seconds() -> float:
	return NOTE_SECONDS


## Whether its hits are notes of the song rather than drum strokes: its channel says so.
func pitched() -> bool:
	return channel() != HitRecorder.CHANNEL


## How far the sound is pitched to ring `note`: 1.0 for percussion, whose sound is its own.
func sound_pitch(_note: int) -> float:
	return 1.0


## One read of the song position a hit played now is played to: `clock`, or the playhead.
static func now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return DAW.state.position_seconds if DAW.state != null else 0.0


## The sound of a hit: shaken, or `struck`, Foley's take `take` of its kind (`sound_kind`), or
## struck on `zone`, of that zone's (`zone_kind`).
func sound(struck: bool, take: int, zone := &"") -> AudioStream:
	return Foley.take_of(kind_of_hit(struck, zone), take)


## Which of Foley's sounds a hit rings: its zone's, where it has one, or `sound_kind`'s.
func kind_of_hit(struck: bool, zone := &"") -> StringName:
	var kind := zone_kind(zone) if zone != &"" else &""
	return kind if kind != &"" else sound_kind(struck)


# --- standing still (docs/spatial_loop.md part two, slice 38) ------------------------------------

## Override: where a fixed instrument is struck, global space: each {"frame": Transform3D, its
## origin the face's middle and its +Y out of the face, and "radius" for a round head or "half"
## (Vector2, along the frame's X and Z) for a square one}. Strike reads them every frame. None for
## an instrument that is carried.
func faces() -> Array:
	return []


## Override: how slowly a hand may cross one of its faces and still strike it (m/s): a strike's
## (Strike.STRIKE_MIN), slower than which is a touch. A venue's glass rings at a touch.
func strike_least() -> float:
	return Strike.STRIKE_MIN


## Override: how hard a crossing of one of its faces at `speed` (m/s) strikes it: `velocity_for`'s.
func velocity_of(speed: float) -> int:
	return velocity_for(speed)


## Override: which part of it a strike at `point` (global) lands on, &"" for one with no parts.
func zone_at(_point: Vector3) -> StringName:
	return &""


## Override: its zones, in words for its card: "centre bass · rim slap".
func zone_words() -> String:
	return ""


## Override: which of Foley's sounds a strike on `zone` rings, &"" for `sound_kind`'s.
func zone_kind(_zone: StringName) -> StringName:
	return &""


## Override: the note a hit on `zone` played to song position `seconds` is recorded as: `note_at`,
## for one with no zones.
func zone_note(_zone: StringName, seconds: float) -> int:
	return note_at(seconds)


## Whether `zone` is one of its own (`zone_at` could answer it): a bandmate's hit naming another is
## heard as struck on none.
func has_zone(zone: StringName) -> bool:
	return zone == &""


## A strike on a fixed instrument by a hand here, `velocity` 1 to 127 on `zone` (Strike, `struck_by`),
## by the hand on `side` (-1 left, 1 right, 0 neither: the mouse).
func strike(velocity: int, zone: StringName, side := 0) -> void:
	play(velocity, true, zone, side)


## A grab on it by `hand` at `at`, a fixed one's strike: a click is Strike.CLICK, Shift-click
## Strike.CLICK_SOFT (`Interactor.fine`), on the zone it landed on.
func struck_by(hand: Interactor, at: Vector3) -> void:
	if fixed:
		strike(Strike.click_velocity(hand), zone_at(at), side_of(hand))


## Which side `hand` is: -1 a left controller or hand, 1 a right, 0 the mouse (or none).
static func side_of(hand: Interactor) -> int:
	if hand != null and hand.has_method(&"hand_side"):
		return int(hand.call(&"hand_side"))
	return 0


## What its card says it is doing, whether its hits are snapped to the beat (hand percussion,
## while they are), and which way its hits are heard (`path_words`): what its shelf tag said.
func readout() -> String:
	var said := super()
	if fixed:
		said = zone_words() if zone_words() != "" else "it stands here"
	if held_in_fist() and tag_text().begins_with("SNAP"):
		said += "  ·  snapped to the beat"
	return "%s  ·  %s" % [said, path_words()]


## Whether this player's own hits are heard on the fast path now: the hits' helper is running and
## has its sounds (`fast_latency`).
static func on_fast_path() -> bool:
	return fast_latency.is_valid() and float(fast_latency.call()) >= 0.0


## How late a hit here is heard (s): the fast path's figure, or Godot's output on MONITOR.
static func path_latency() -> float:
	return float(fast_latency.call()) if on_fast_path() else AudioServer.get_output_latency()


## The tag's line for which way a hit here is heard, and its figure, as the platter's tag says its
## scratch's: "FAST PATH · 5 ms", or "MONITOR · 41 ms" through Godot.
static func path_tag() -> String:
	return "%s · %d ms" % ["FAST PATH" if on_fast_path() else "MONITOR", roundi(path_latency() * 1000.0)]


## The same in the card's words: "heard on the fast path, 5 ms", or "heard on MONITOR through the
## app, 41 ms".
static func path_words() -> String:
	return "heard %s, %d ms" % ["on the fast path" if on_fast_path() else "on MONITOR through the app",
			roundi(path_latency() * 1000.0)]


func hint() -> String:
	if fixed:
		return STRIKE_HANDS if hands_hint else STRIKE_DESK
	return super()


## Item's, and in a headset, for hand percussion not in a hand, how a hand holds it: what its
## shelf tag said.
func _hint(loose: String) -> String:
	var said := super(loose)
	if not (held_in_fist() and hands_hint and state != State.HELD):
		return said
	var how := HANDS_HINT.replace("\n", " · ")
	return how if said == "" else "%s · %s" % [said, how]


## Override: which of Foley's sounds (Foley.take_of) a hit rings, shaken or `struck`.
func sound_kind(_struck: bool) -> StringName:
	return &"shaker"


## A click rings it struck (`use`): the sampler (Sampler) catches that sound.
func use_kind(down: bool) -> StringName:
	return sound_kind(true) if down else &""


## How fast a hit played to song position `song` (-1, now) is played against Foley's take of it:
## its voice and curse (`pitch_scale`), and a pitched one's note there (`sound_pitch`). What the
## room hears it at, and so what the sampler keeps (Sampler.heard's `pitch`).
func tune_at(song := -1.0) -> float:
	if not pitched():
		return pitch_scale()
	return pitch_scale() * sound_pitch(note_at(song if song >= 0.0 else now()))


## A click is a hit now (`tune_at`).
func use_pitch() -> float:
	return tune_at()


## What a fixed instrument's card says to do with it, at a desk and in a headset.
const STRIKE_DESK := "click to strike it, Shift-click softly · where you click picks the sound"
const STRIKE_HANDS := "strike it with a hand, or a controller's tip or grip"


## A click. Somebody else's click on a pitched item is not rung from here: it comes as a hit
## with its song position (`heard`), so it is rung in the chord they played it in.
func use(down: bool) -> void:
	if not down:
		return
	if carried_by != null:
		play(STRUCK, true, &"", side_of(carried_by))
		use_take = _take
	elif not pitched():
		heard(STRUCK, true, -1.0, _heard_take)
		use_take = _heard_take if _heard_take >= 0 else _take


## A hit by a hand here: in this player's ears at once, and out to the room and the take. The song
## position is read once (`now`), and the sound is started, pitched by it, before this returns: on
## the fast path where it runs (`fast_path`), panned to the hand's `side` (-1 left, 1 right, 0 the
## mouse), or on MONITOR through Godot. The same take of the same sound, at the same level and
## pitch, either way.
func play(velocity: int, struck := false, zone := &"", side := 0) -> void:
	velocity = clampi(velocity, 1, 127)
	var at := now()
	var note := note_at(at)
	last_note = note
	last_zone = zone
	_take += 1
	_jiggle(velocity)
	if is_inside_tree():
		var speed := pitch_scale() * sound_pitch(note)
		if fast_path.is_valid() and bool(fast_path.call(kind_of_hit(struck, zone), _take,
				monitor_gain(velocity), HAND_PAN * signf(side), speed)):
			last_path = &"fast"
		else:
			last_path = &"monitor"
			var player := AudioStreamPlayer.new()
			player.stream = sound(struck, _take, zone)
			player.volume_db = level_db(velocity)
			player.pitch_scale = speed
			player.bus = AudioPorts.bus(AudioPorts.MONITOR)
			add_child(player)
			player.finished.connect(player.queue_free)
			player.play()
	played.emit(velocity, struck, at, zone)


## A hit's level on the fast path, linear: what `level_db` is on MONITOR, through that bus's own
## fader and mute, as Godot would have played it.
static func monitor_gain(velocity: int) -> float:
	var bus := AudioServer.get_bus_index(AudioPorts.bus(AudioPorts.MONITOR))
	if bus < 0:
		return db_to_linear(level_db(velocity))
	if AudioServer.is_bus_mute(bus):
		return 0.0
	return db_to_linear(level_db(velocity) + AudioServer.get_bus_volume_db(bus))


## Somebody else's hit, as their hand plays it: in the room, from where the instrument is.
## `song` is the song position they played it to; -1 (not known) is this player's own. A pitched
## item rings its note there, exactly. `take` is which of Foley's takes their hand rang
## (`sound_take`), so everyone hears the sound its player heard; -1 (not known) is the next of
## this copy's own, with a little wobble, so a run of hits is not one sample said again and again.
## `snap`, whether they snap their hits, for its tag. `zone`, where on a fixed one they struck it:
## one it has not got is struck on none.
func heard(velocity: int, struck := false, song := -1.0, take := -1, snap := false, zone := &"") -> void:
	_take += 1
	_jiggle(velocity)
	holder_snaps = snap
	zone = zone if has_zone(zone) else &""
	last_zone = zone
	var tune := pitch_scale()
	if pitched():
		var note := note_at(song if song >= 0.0 else now())
		last_note = note
		tune *= sound_pitch(note)
	elif take < 0:
		tune *= randf_range(0.97, 1.03)
	Foley.play(ring_on(), sound(struck, take if take >= 0 else _take, zone), level_db(velocity) + 2.0, tune)


## Where somebody else's hit is rung from: here, where it stands or is held. The kit (KitItem)
## rings a bandmate's from their ghost instead, since the pad they struck is on their own surface.
func ring_on() -> Node3D:
	return self


## Which of Foley's takes its last hit rang (`sound`'s `take`): sent with a hit (Session.item_hit),
## so whoever hears it hears that one.
func sound_take() -> int:
	return _take


static func level_db(velocity: int) -> float:
	return linear_to_db(clampf(velocity / 127.0, 0.05, 1.0)) * 1.2 - 3.0


## How hard a stroke at `speed` (m/s) is played, or 0 for too slow to be one.
static func velocity_for(speed: float) -> int:
	if speed < STROKE_MIN:
		return 0
	return clampi(roundi(lerpf(40.0, 127.0, clampf((speed - STROKE_MIN) / (STROKE_FULL - STROKE_MIN), 0.0, 1.0))), 1, 127)


func _physics_process(delta: float) -> void:
	super(delta)
	_since += delta
	# A bare hand out of tracking is no stroke, and coming back is a fresh one, not the jump.
	if in_hand() and carried_by.shake_tracked():
		feel(carried_by.shake_point(), delta, carried_by.shake_lever())
	else:
		_last = Vector3.INF
		_peak = 0.0


## Where the hand shakes it from now, `delta` on from the last: a hit if a stroke has stopped.
## `lever`, how much further the instrument goes than `at` does (Interactor.shake_lever).
func feel(at: Vector3, delta: float, lever := 1.0) -> void:
	if _last == Vector3.INF or delta <= 0.0:
		_last = at
		return
	var moving := (at - _last) / delta * lever
	_last = at
	var speed := moving.length()
	if speed > _peak:
		_peak = speed
		_peak_way = moving.normalized()
	if _peak < STROKE_MIN:
		return
	var stopped := speed < _peak * STOPPED or moving.dot(_peak_way) < 0.0
	if not stopped:
		return
	if _since >= AGAIN_AFTER:
		_since = 0.0
		play(velocity_for(_peak), false, &"", side_of(carried_by))
	# Whatever it is doing now is the next stroke.
	_peak = speed if moving.dot(_peak_way) < 0.0 else 0.0
	_peak_way = moving.normalized()


## The instrument answering a hit: a small kick through its body.
func _jiggle(velocity: int) -> void:
	poke(-0.06 - 0.12 * velocity / 127.0)
