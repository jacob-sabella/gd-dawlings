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

## A hit played by a hand here: `velocity` 1 to 127, `struck` for a click rather than a shake.
signal played(velocity: int, struck: bool)

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

var _last := Vector3.INF
var _peak := 0.0
var _peak_way := Vector3.ZERO
var _since := 1.0
var _take := 0


## The General MIDI percussion note a hit is recorded as.
func pitch() -> int:
	return 82


## The sound of a hit: shaken, or `struck`.
func sound(_struck: bool, take: int) -> AudioStream:
	return Foley.shaker(take)


func use(down: bool) -> void:
	if not down:
		return
	if carried_by != null:
		play(STRUCK, true)
	else:
		heard(STRUCK, true)


## A hit by a hand here: in this player's ears at once, and out to the room and the take.
func play(velocity: int, struck := false) -> void:
	velocity = clampi(velocity, 1, 127)
	_take += 1
	_jiggle(velocity)
	if is_inside_tree():
		var player := AudioStreamPlayer.new()
		player.stream = sound(struck, _take)
		player.volume_db = level_db(velocity)
		player.bus = AudioPorts.bus(AudioPorts.MONITOR)
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play()
	played.emit(velocity, struck)


## Somebody else's hit, as their hand plays it: in the room, from where the instrument is.
func heard(velocity: int, struck := false) -> void:
	_take += 1
	_jiggle(velocity)
	Foley.play(self, sound(struck, _take), level_db(velocity) + 2.0, randf_range(0.97, 1.03))


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
	if in_hand():
		feel(carried_by.shake_point(), delta)
	else:
		_last = Vector3.INF
		_peak = 0.0


## Where the hand shakes it from now, `delta` on from the last: a hit if a stroke has stopped.
func feel(at: Vector3, delta: float) -> void:
	if _last == Vector3.INF or delta <= 0.0:
		_last = at
		return
	var moving := (at - _last) / delta
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
