class_name TimelineRuler
extends ControlAffordance

## One band of the timeline's ruler, as something a hand can work.
##
## SEEK, the bar numbers: press to put the playhead there, drag to scrub it. Pulled onto the
## timeline's grid (TimelineLanes.grid) when it comes within TimelineLanes.MAGNET of a line, because
## the place anyone wants the playhead is nearly always "bar 33" and never "bar 32.97" -- and left
## where it is between lines, zoomed in far enough to want somewhere else; fine (shift on a
## monitor) takes the pull off altogether.
##
## LOOP, the thin band above: drag out a range to loop, press without dragging to switch the
## loop on and off. The same gesture as Reaper's own ruler, and the same pair of bands most
## arrangers draw, so nothing here has to be learnt twice.
##
## Neither is a value in ControlAffordance's sense. The transport is the value; these send
## intents at it and the surface draws what comes back, so a guest's ruler shows the host's
## loop and not a local guess at it.

enum Kind {SEEK, LOOP}

## Less than this between press and release is a click, not a drag. In metres along the strip.
const CLICK_SLOP := 0.0025

var kind := Kind.SEEK
var width := 0.4
var height := 0.02
## Callable(local_x: float) -> float seconds. The surface owns the window, so it owns this.
var seconds_at: Callable

var _shape: CollisionShape3D
var _grab_x := 0.0
var _grab_seconds := 0.0
var _dragged := false
var _last_seconds := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	_shape = CollisionShape3D.new()
	_shape.shape = BoxShape3D.new()
	add_child(_shape)
	refresh()


func refresh() -> void:
	if _shape == null:
		return
	# Deeper than it looks, like the scrubber, so there is something with volume to aim at.
	(_shape.shape as BoxShape3D).size = Vector3(width, height, 0.010)


## Pulled onto the grid when near a line, unless fine (TimelineLanes.pull): near meaning
## TimelineLanes.MAGNET along the strip, through the window as it is zoomed now.
func snap(seconds: float, fine: bool) -> float:
	var reach := 0.0
	if seconds_at.is_valid():
		reach = absf(seconds_at.call(TimelineLanes.MAGNET) - seconds_at.call(0.0))
	return TimelineLanes.pull(seconds, fine, reach)


func _seconds(at: Vector3) -> float:
	var local := to_local(at)
	return seconds_at.call(local.x) if seconds_at.is_valid() else 0.0


func _fine() -> bool:
	return held_by != null and held_by.has_method("fine") and held_by.fine()


func _on_grab_begin(at: Vector3) -> void:
	_grab_x = to_local(at).x
	_dragged = false
	_grab_seconds = snap(_seconds(at), _fine())
	_last_seconds = _grab_seconds
	if kind == Kind.SEEK:
		DAW.seek(_grab_seconds)


func _on_grab_move(at: Vector3) -> void:
	if not _dragged and absf(to_local(at).x - _grab_x) < CLICK_SLOP:
		return
	_dragged = true
	var now := snap(_seconds(at), _fine())
	if is_equal_approx(now, _last_seconds):
		return
	_last_seconds = now
	if kind == Kind.SEEK:
		DAW.seek(now)
	else:
		DAW.set_loop_range(_grab_seconds, now)


func _on_grab_end() -> void:
	if kind == Kind.LOOP:
		if not _dragged:
			# A press on the band. With no range yet there is nothing to loop, so a press makes
			# one -- the bar it landed in -- rather than lighting a loop round nothing.
			if not DAW.state.has_loop_range():
				var bar := floorf(DAW.state.bar_at(_grab_seconds)) + 1.0
				DAW.set_loop_range(DAW.state.bar_to_seconds(bar), DAW.state.bar_to_seconds(bar + 1.0))
			DAW.set_looping(not DAW.state.looping)
		elif DAW.state.has_loop_range() and not DAW.state.looping:
			# Dragging out a range is asking to hear it.
			DAW.set_looping(true)


func _default_title() -> String:
	return "PLAYHEAD" if kind == Kind.SEEK else "LOOP"


func _default_readout() -> String:
	var s := DAW.state
	if kind == Kind.SEEK:
		return "%s  (%s)" % [s.bar_beat(s.position_seconds), _clock(s.position_seconds)]
	if not s.has_loop_range():
		return "no range"
	return "%s - %s  %s" % [s.bar_beat(s.loop_start), s.bar_beat(s.loop_end),
			"ON" if s.looping else "off"]


func hint() -> String:
	return "click or drag to move the playhead, snapping to the grid when close (fine for free)" if kind == Kind.SEEK \
			else "drag a range to loop it, snapping to the grid when close; click to switch looping"


static func _clock(seconds: float) -> String:
	var m := int(seconds / 60.0)
	return "%d:%06.3f" % [m, seconds - m * 60.0]
