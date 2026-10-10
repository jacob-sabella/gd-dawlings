class_name PoseTrail
extends RefCounted

## Something someone else is moving, drawn as it moved rather than chased.
##
## Poses arrive twenty times a second, each a little late and never quite evenly. Chasing the
## newest one -- easing toward it every frame -- turns each arrival into a lurch and the gaps
## into a slide, and the thing is forever correcting itself onto where it was a moment ago. So
## the poses heard are kept, each with when it was heard, and the thing is drawn DELAY behind
## now, between the two it was at either side of that moment: at the speed it really moved, and
## smooth through a late packet. Past the newest, it carries on as it was going for a moment,
## then stands.

## How far behind the poses heard it is drawn: two send intervals, so the moment drawn nearly
## always has a pose heard after it.
const DELAY_MSEC := 100.0
## How long past the newest pose it carries on as it was going; it comes back to the newest over
## as long again, so a thing that stopped is drawn where it stopped, not a little past it.
const EXTRAPOLATE_MSEC := 100.0
## A gap longer than this is a stop, not a late packet: it stood where it was until it moved on.
const STILL_MSEC := 250.0
const KEEP := 8

## Added to the clock: the suite moves time on with it rather than waiting for it.
static var skew_msec := 0.0

var _times: Array[float] = []
var _poses: Array[Transform3D] = []


## The clock poses are heard and drawn by.
static func now() -> float:
	return Time.get_ticks_msec() + skew_msec


func push(at_msec: float, pose: Transform3D) -> void:
	if not _times.is_empty():
		var last := _times[-1]
		if at_msec - last > STILL_MSEC:
			# It stood still between the two, rather than creeping from the old pose to the new.
			_times.append(at_msec - 50.0)
			_poses.append(_poses[-1])
		at_msec = maxf(at_msec, _times[-1] + 0.001)
	_times.append(at_msec)
	_poses.append(pose)
	while _times.size() > KEEP:
		_times.pop_front()
		_poses.pop_front()


func is_empty() -> bool:
	return _times.is_empty()


func latest() -> Transform3D:
	return _poses[-1] if not _poses.is_empty() else Transform3D()


## When the newest pose was heard.
func last_heard() -> float:
	return _times[-1] if not _times.is_empty() else -INF


## Whether it has stopped being moved: nothing heard for longer than it is drawn behind and
## carried on for.
func settled(now_msec: float) -> bool:
	return _times.is_empty() or now_msec - _times[-1] > DELAY_MSEC + EXTRAPOLATE_MSEC + 50.0


func clear() -> void:
	_times.clear()
	_poses.clear()


## Where to draw it at `now_msec`.
func sample(now_msec: float) -> Transform3D:
	if _poses.is_empty():
		return Transform3D()
	var t := now_msec - DELAY_MSEC
	if t <= _times[0]:
		return _poses[0]
	for i in range(1, _times.size()):
		if t <= _times[i]:
			var w := (t - _times[i - 1]) / (_times[i] - _times[i - 1])
			return _poses[i - 1].interpolate_with(_poses[i], w)
	if _times.size() >= 2:
		var span := _times[-1] - _times[-2]
		if span > 0.0 and span < STILL_MSEC:
			var past := t - _times[-1]
			var over := past if past < EXTRAPOLATE_MSEC else maxf(0.0, 2.0 * EXTRAPOLATE_MSEC - past)
			return Transform3D(_poses[-1].basis, _poses[-2].origin.lerp(_poses[-1].origin, 1.0 + over / span))
	return _poses[-1]
