class_name Clap
extends RefCounted

## Clap to mute (docs/spatial_loop.md slice 19, idea #14): the palms pressed together mute the
## track being pointed at for as long as they stay together, and a clap latches it.
##
## Pressed is HandPose.palms_meet for two tracked bare hands (middles within 5 cm, facing each
## other within 40 degrees), or two controllers' grips within GRIPS_TOUCH. The track is read once,
## as they meet (`target`): the one under either hand's ray, or else the head's gaze
## (Studio.track_under). Held, the track is muted until they part, and put back as it was. A clap
## -- meeting faster than CLAP_SPEED and parting within LATCH_WITHIN -- latches instead: a mute
## toggle, left as it is when they part.
##
## A desktop's K is the same thing by a key (Studio): held over a track it mutes it while held, and
## a tap under LATCH_WITHIN latches, a key press being always quick (`press` with `quick` true). How
## long it was held is counted on the same frame clock as the hands (`hold`, then `held_for`), not
## the wall clock, so a slow frame cannot make a hold a tap.
##
## Every change is DAW.set_track_mute, so a pressed mute shows on the voice and the strip as any
## mute does, and a guest's is an intent the host carries out. Nothing is predicted: what this
## asked last is kept (`_asked`), so a guest's release answers its own press, not a cache the
## host's echo has yet to reach.

## Two controllers' grip points this near (m) are hands pressed together.
const GRIPS_TOUCH := 0.08
## Closing faster than this (m/s) as they meet is a clap, not a press.
const CLAP_SPEED := 0.8
## A clap parts within this (s); a key let go within it is a tap.
const LATCH_WITHIN := 0.3
## How far back the closing speed is measured over (s), so one jittery frame is not a clap.
const SPEED_WINDOW := 0.08

## Whether the hands are pressed together now.
var pressed := false
## The track muted while they are, 0 for none (pressed at nothing).
var track := 0
## () -> int: the track pointed at as the hands meet, 0 for none. Read once a press.
var target: Callable = Callable()

var _was_muted := false
var _asked := false
var _quick := false
var _for := 0.0
var _clock := 0.0
## [clock, gap] while apart, over SPEED_WINDOW: how fast they closed.
var _trail: Array = []


## One frame of two hands, `delta` on: `together` whether they are pressed now, `gap` how far
## apart they are (m; INF when that cannot be read). Their meeting presses, their parting lets go.
func step(together: bool, gap: float, delta: float) -> void:
	_clock += delta
	if pressed:
		_for += delta
		if not together:
			release(_for)
		return
	if is_finite(gap):
		_trail.append([_clock, gap])
		while _trail.size() > 2 and _clock - float(_trail[0][0]) > SPEED_WINDOW:
			_trail.pop_front()
	if together:
		var speed := closing_speed()
		_trail.clear()
		press(int(target.call()) if target.is_valid() else 0, speed >= CLAP_SPEED)


## One frame of a key held down, `delta` on: counted toward `held_for` while pressed.
func hold(delta: float) -> void:
	if pressed:
		_for += delta


## How long the press has been held (s), by the frames `step` or `hold` were given.
func held_for() -> float:
	return _for


## How fast the hands were closing over the last SPEED_WINDOW (m/s), 0 for not at all.
func closing_speed() -> float:
	if _trail.size() < 2:
		return 0.0
	var first: Array = _trail[0]
	var last: Array = _trail[-1]
	var span := float(last[0]) - float(first[0])
	return maxf(0.0, (float(first[1]) - float(last[1])) / span) if span > 0.0001 else 0.0


## The hands meet, or K goes down, over `on_track` (0 for nothing): muted now, unless it is
## already. `quick` is a clap's speed, or a key, which may latch on the let-go.
func press(on_track: int, quick: bool) -> void:
	pressed = true
	_for = 0.0
	_quick = quick
	track = 0
	var t := DAW.state.track(on_track, false) if on_track > 0 and DAW.state != null else null
	if t == null:
		return
	track = on_track
	_was_muted = t.mute
	_asked = t.mute
	if t.mute:
		Session.notice.emit("%s is muted already: a quick clap or tap unmutes it" % _title())
		return
	_ask(true)
	Session.notice.emit("%s muted while held" % _title())


## They part, or K comes up, `held` seconds after: a quick press let go within LATCH_WITHIN latches
## (the mute toggled from what it was, and left), anything else puts the track back as it was.
func release(held: float) -> void:
	pressed = false
	_trail.clear()
	if track == 0:
		return
	var latched := _quick and held <= LATCH_WITHIN + 0.0001
	var want := (not _was_muted) if latched else _was_muted
	if want != _asked:
		_ask(want)
	if latched:
		Session.notice.emit("%s %s: latched" % [_title(), "muted" if want else "unmuted"])
	elif not _was_muted:
		Session.notice.emit("%s unmuted" % _title())
	track = 0


## Whether the last let-go latched: for the suite and the probe.
func latches(held: float) -> bool:
	return _quick and held <= LATCH_WITHIN + 0.0001


func _ask(muted: bool) -> void:
	_asked = muted
	DAW.set_track_mute(track, muted)


## "3 BASS".
func _title() -> String:
	var t := DAW.state.track(track, false)
	var name := t.display_name() if t != null else "Track %d" % track
	return "%d %s" % [DAW.state.bank_offset + track, name.to_upper()]


## The two hands' readings, as XRInteractor.clap_palm gives them ([point, normal], normal ZERO
## for a controller's grip, empty for nothing to read): [together, gap]. Two bare palms by
## HandPose.palms_meet; two controllers, or a controller and a palm, by GRIPS_TOUCH.
static func reading(a: Array, b: Array) -> Array:
	if a.size() < 2 or b.size() < 2:
		return [false, INF]
	var gap := (a[0] as Vector3).distance_to(b[0])
	var a_normal: Vector3 = a[1]
	var b_normal: Vector3 = b[1]
	if a_normal == Vector3.ZERO or b_normal == Vector3.ZERO:
		return [gap <= GRIPS_TOUCH, gap]
	return [HandPose.palms_meet(a[0], a_normal, b[0], b_normal), gap]
