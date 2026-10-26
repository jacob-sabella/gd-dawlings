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
## A hit played here is heard at once, by the player, on their own keys' bus (the low-latency
## path, the same as their keys: AudioPorts.MONITOR, "MY KEYS" in a personal mix), and is
## `played` for the studio to tell everyone and to record. Anyone else's hit is heard in the
## room, from their hand (`heard`).
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
## gently to the beat (HitRecorder.snapped_at): the take's note moves, never the sound. A tag over it
## on the shelf says SNAP while this player snaps, and in a headset how it is held.
##
## Every instrument has an output jack (`jack`, a JackSocket at `jack_point`, docs/spatial_loop.md
## slice 5). Unplugged, a hit does all of the above and nothing else; plugged into a track, the
## take it is recorded in goes onto that track instead of the armed one (Jacks, HitRecorder).

## A hit played by a hand here: `velocity` 1 to 127, `struck` for a click rather than a shake, `at`
## the song position it was played to (one read of `clock`).
signal played(velocity: int, struck: bool, at: float)

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
## Its output jack, made as it enters the room: where what it plays goes (Jacks).
var jack: JackSocket = null

## Which of the kind's voices this copy is: 0 the first out of the case, 1 the low one. A
## second copy of a kind is a different job, not a decoy, only because it sounds (and is
## recorded) a fifth lower -- see `pitch_scale`, and each subclass's own `pitch()`.
var voice := 0
## Its shelf tag (`tag_text`), for hand percussion only.
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


func _ready() -> void:
	super()
	if jack == null:
		jack = JackSocket.new(self)
		add_child(jack)
	if held_in_fist() and _tag == null:
		_tag = Label3D.new()
		_tag.name = "ShelfTag"
		_tag.font_size = 48
		_tag.pixel_size = 0.0004
		_tag.outline_size = 8
		_tag.modulate = Color(0.97, 0.94, 0.86)
		_tag.outline_modulate = Color(0.05, 0.04, 0.03)
		_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
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


## What its shelf tag says: SNAP while this player snaps (or, in a bandmate's hand, while they do),
## and in a headset how a hand holds it; "" for nothing to say. Only hand percussion has one.
func tag_text() -> String:
	if not held_in_fist():
		return ""
	var lines: PackedStringArray = []
	var snaps := holder_snaps if is_held_elsewhere() else (snapping.is_valid() and bool(snapping.call()))
	if snaps:
		lines.append("SNAP")
	if hands_hint and state != State.HELD:
		lines.append(HANDS_HINT)
	return "\n".join(lines)


func _retag() -> void:
	if _tag == null:
		return
	var said := tag_text()
	# Not over it in your own hand, where it would sit in front of everything you look at.
	_tag.visible = said != "" and not in_hand()
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


## The General MIDI percussion note a hit is recorded as.
func pitch() -> int:
	return 82


## The note a hit played to song position `seconds` is: `pitch()` for percussion, whatever the
## song is doing. A pitched item asks the song (HandbellItem: its chord tone there).
func note_at(_seconds: float) -> int:
	return pitch()


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


## The sound of a hit: shaken, or `struck`.
func sound(_struck: bool, take: int) -> AudioStream:
	return Foley.shaker(take)


## A click. Somebody else's click on a pitched item is not rung from here: it comes as a hit
## with its song position (`heard`), so it is rung in the chord they played it in.
func use(down: bool) -> void:
	if not down:
		return
	if carried_by != null:
		play(STRUCK, true)
	elif not pitched():
		heard(STRUCK, true)


## A hit by a hand here: in this player's ears at once, and out to the room and the take. The song
## position is read once (`now`), and the sound is started, pitched by it, before this returns.
func play(velocity: int, struck := false) -> void:
	velocity = clampi(velocity, 1, 127)
	var at := now()
	var note := note_at(at)
	last_note = note
	_take += 1
	_jiggle(velocity)
	if is_inside_tree():
		var player := AudioStreamPlayer.new()
		player.stream = sound(struck, _take)
		player.volume_db = level_db(velocity)
		player.pitch_scale = pitch_scale() * sound_pitch(note)
		player.bus = AudioPorts.bus(AudioPorts.MONITOR)
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play()
	played.emit(velocity, struck, at)


## Somebody else's hit, as their hand plays it: in the room, from where the instrument is.
## `song` is the song position they played it to; -1 (not known) is this player's own. A pitched
## item rings its note there, exactly. `take` is which of Foley's takes their hand rang
## (`sound_take`), so everyone hears the sound its player heard; -1 (not known) is the next of
## this copy's own, with a little wobble, so a run of hits is not one sample said again and again.
## `snap`, whether they snap their hits, for its tag.
func heard(velocity: int, struck := false, song := -1.0, take := -1, snap := false) -> void:
	_take += 1
	_jiggle(velocity)
	holder_snaps = snap
	var tune := pitch_scale()
	if pitched():
		var note := note_at(song if song >= 0.0 else now())
		last_note = note
		tune *= sound_pitch(note)
	elif take < 0:
		tune *= randf_range(0.97, 1.03)
	Foley.play(self, sound(struck, take if take >= 0 else _take), level_db(velocity) + 2.0, tune)


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
		play(velocity_for(_peak))
	# Whatever it is doing now is the next stroke.
	_peak = speed if moving.dot(_peak_way) < 0.0 else 0.0
	_peak_way = moving.normalized()


## The instrument answering a hit: a small kick through its body.
func _jiggle(velocity: int) -> void:
	poke(-0.06 - 0.12 * velocity / 127.0)
