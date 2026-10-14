class_name TimelineScrubber
extends ControlAffordance

## The overview bar under the timeline: the whole project as one strip, with the part you are
## looking at drawn on it.
##
## Three grab zones in one control, decided at the moment of the grab from where the contact
## point landed: the body scrolls, either end resizes. That is how every arranger's overview
## bar has worked for twenty years, and copying it is the right call -- it is one object to
## find, one gesture to learn, and it tells you where you are while you use it.
##
## Zones are picked ONCE, at grab time, and held for the whole drag. Re-deciding per frame
## would mean a window dragged narrow flips to scrolling the instant its own edge slides under
## the hand, which is both wrong and impossible to recover from.
##
## It does not inherit ControlAffordance's `value`, because a window is a pair of numbers and
## not a position. It reports through `view_changed` instead, and the surface owns the window.

signal view_changed(start: float, span: float)

const HEIGHT := 0.0085
const EDGE_ZONE := 0.0075
## Narrower than this and the window has no body left to grab, so the end zones stop shrinking
## and start overlapping -- at which point the body wins, because a window you cannot scroll is
## worse than one you cannot resize by this particular gesture.
const MIN_THUMB := 0.020
## Shortest window, in seconds. Two bars at 120bpm. Past this the ruler has nothing to label.
const MIN_SPAN := 4.0

enum Zone {BODY, LEFT, RIGHT}

var width := 0.4
## Seconds. The thing being represented.
var project_length := 1.0
var view_start := 0.0
var view_span := 1.0

var _track: MeshInstance3D
var _thumb: MeshInstance3D
var _zone := Zone.BODY
var _grab_x := 0.0
var _grab_start := 0.0
var _grab_span := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0

	_track = MeshInstance3D.new()
	_track.mesh = BoxMesh.new()
	# Unlit, as the rest of the screen is (TimelineSurface.SCREEN_FACE). Lit, the thumb -- the
	# timeline's full width when the whole song is in view -- caught the floor lamps and read as
	# a bright slab along the bottom of the panel.
	_track.material_override = TimelineSurface.flat(TimelineSurface.RULER_FACE)
	_track.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_track)

	_thumb = MeshInstance3D.new()
	_thumb.mesh = BoxMesh.new()
	_thumb.material_override = TimelineSurface.flat(Color(0.24, 0.27, 0.33))
	_thumb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_thumb)

	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	add_child(shape)
	refresh()


## Resize to the panel and redraw the window. Called by the surface on every rebuild, and after
## every change the surface makes to the window itself.
func refresh() -> void:
	if _track == null:
		return
	var track_mesh := _track.mesh as BoxMesh
	track_mesh.size = Vector3(width, HEIGHT, 0.0010)
	_track.position = Vector3(0, 0, 0.0005)

	var shape := get_child(2) as CollisionShape3D
	if shape:
		# Deeper than it looks, so a tracked controller aiming at an 8mm strip from across a
		# room has something with volume to hit.
		(shape.shape as BoxShape3D).size = Vector3(width, HEIGHT * 2.4, 0.012)

	var span := maxf(project_length, 0.001)
	var left := clampf(view_start / span, 0.0, 1.0)
	var size := clampf(view_span / span, 0.0, 1.0)
	var thumb_width := maxf(size * width, MIN_THUMB)
	var thumb_mesh := _thumb.mesh as BoxMesh
	thumb_mesh.size = Vector3(thumb_width, HEIGHT - 0.0016, 0.0014)
	# Standing just proud of the track rather than sunk into it: a window over the whole song
	# has its ends in the track's ends' planes, and sunk in, those overlapped enough to flicker
	# once the timeline is scaled up to stand in a room.
	_thumb.position = Vector3(-width * 0.5 + left * width + thumb_width * 0.5, 0, 0.0018)


func _on_grab_begin(at: Vector3) -> void:
	var local := to_local(at)
	_grab_x = local.x
	_grab_start = view_start
	_grab_span = view_span

	var thumb_width: float = (_thumb.mesh as BoxMesh).size.x
	var offset := local.x - _thumb.position.x
	if thumb_width > MIN_THUMB * 1.5 and offset < -thumb_width * 0.5 + EDGE_ZONE:
		_zone = Zone.LEFT
	elif thumb_width > MIN_THUMB * 1.5 and offset > thumb_width * 0.5 - EDGE_ZONE:
		_zone = Zone.RIGHT
	else:
		_zone = Zone.BODY
		# Grabbing the bar away from the window jumps to it, the way clicking the trough of a
		# fader jumps the cap. Without this, getting from bar 1 to bar 300 is a long drag.
		if absf(offset) > thumb_width * 0.5:
			_set_window(_seconds_at(local.x) - view_span * 0.5, view_span)
			_grab_x = local.x
			_grab_start = view_start


func _on_grab_move(at: Vector3) -> void:
	var local := to_local(at)
	var delta := (local.x - _grab_x) / maxf(width, 0.0001) * maxf(project_length, 0.001)
	match _zone:
		Zone.BODY:
			_set_window(_grab_start + delta, _grab_span)
		Zone.LEFT:
			# The right edge stays put: dragging the left edge is "show me more of what came
			# before", and a resize that moved both edges would scroll as well as zoom.
			var right := _grab_start + _grab_span
			var start := minf(_grab_start + delta, right - MIN_SPAN)
			_set_window(start, right - start)
		Zone.RIGHT:
			_set_window(_grab_start, maxf(_grab_span + delta, MIN_SPAN))


func _set_window(start: float, span: float) -> void:
	var limit := maxf(project_length, MIN_SPAN)
	view_span = clampf(span, MIN_SPAN, limit)
	view_start = clampf(start, 0.0, maxf(limit - view_span, 0.0))
	refresh()
	view_changed.emit(view_start, view_span)


func _seconds_at(x: float) -> float:
	return (x + width * 0.5) / maxf(width, 0.0001) * maxf(project_length, 0.001)


func _default_title() -> String:
	return "TIMELINE VIEW"


func _default_readout() -> String:
	return "%.1fs - %.1fs" % [view_start, view_start + view_span]


func hint() -> String:
	return "drag to scroll"
