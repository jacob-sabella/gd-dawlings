class_name TimelineLanes
extends ControlAffordance

## The lanes of the timeline, as something a hand can edit.
##
## Press an item to select it (fine -- shift on a monitor -- adds it to the selection or takes it
## out). Drag it to move it along its lane, snapped to the beat unless fine. Drag an edge to trim
## the item there, snapped the same way, its contents staying where they are in the song. Drag a
## top corner -- or the top of a fade's line -- to set that fade, snapped the same way, one undo
## step when let go. Press empty lane to
## drop the selection and put the playhead there. The wheel zooms, round the playhead the way
## Reaper zooms round its edit cursor. Splitting is a key, not a gesture: see the surface.
##
## While the picked track shows a lane of automation (TimelineTrackStrip's LANE key), presses on
## that track's lane edit the lane instead: press bare lane to add a point there (snapped to the
## beat unless fine) and drag it into place, drag a point to move it, click a point to make it
## hold or ramp to the next, fine-click it to remove it, and the wheel over a point nudges its
## value. Each change to the lane is one undo step.
##
## One control over every lane rather than one per item. Items come and go with every edit and
## every poll, and a control rebuilt under a held drag drops the drag; this one is built once.
## The surface answers "what is under this point", so the lanes need no picture of their own.

## Less than this between press and release is a click, not a drag. Metres along the lane.
const CLICK_SLOP := 0.0025
## How much one wheel notch zooms. Fine zooms a fifth as far.
const ZOOM_STEP := 0.8

var width := 0.4
var height := 0.2
## The TimelineSurface. Typed loosely so the two files do not have to load in an order.
var surface: Node

var _shape: CollisionShape3D
## [track, item] under the press, or empty for bare lane.
var _hit: Array = []
var _grab_x := 0.0
var _grab_seconds := 0.0
var _item_start := 0.0
var _dragged := false
var _target_start := 0.0
## -1 or 1 while an edge is being dragged (see TimelineSurface.item_edge_at_point), 0 for a move.
var _edge := 0
var _item_end := 0.0
var _target_end := 0.0
## -1 or 1 while a fade's handle is being dragged (TimelineSurface.fade_handle_at_point), and the
## fades as dragged.
var _fade := 0
var _fade_in := 0.0
var _fade_out := 0.0
## Editing the shown lane of automation: its points as edited, the one held, and whether the
## press made it.
var _auto_on := false
var _auto_points: Array = []
var _auto_index := -1
var _auto_added := false
var _grab_y := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	_shape = CollisionShape3D.new()
	_shape.shape = BoxShape3D.new()
	add_child(_shape)
	refresh()


## How deep the box presses land on is, and how much further forward than that it reaches: out
## to the faces of the blocks in the shelf view.
const DEPTH := 0.010
var front := 0.0


func refresh() -> void:
	if _shape == null:
		return
	(_shape.shape as BoxShape3D).size = Vector3(width, height, DEPTH + front)
	_shape.position = Vector3(0, 0, front * 0.5)


## Snapped to the beat, unless fine.
static func snap(seconds: float, fine: bool) -> float:
	var s := maxf(seconds, 0.0)
	if fine:
		return s
	return DAW.state.seconds_at_beat(roundf(DAW.state.beat_at(s)))


## Where a sound file let go over `point` would go: [track, seconds], the lane under it and its
## time snapped to the beat unless `fine`; [] off the lanes.
func drop_spot(point: Vector3, fine: bool) -> Array:
	var track: int = surface.track_at_point(point)
	if track <= 0:
		return []
	return [track, snap(surface.seconds_at_point(point), fine)]


func _fine() -> bool:
	return held_by != null and held_by.has_method("fine") and held_by.fine()


## The lane a dragged item is over, which it goes onto when let go.
var _target_track := -1


func _on_grab_begin(at: Vector3) -> void:
	_target_track = -1
	_grab_x = to_local(at).x
	_grab_y = to_local(at).y
	_dragged = false
	_auto_on = surface.on_shown_lane(at)
	if _auto_on:
		_hit = []
		_auto_points = surface.shown_points().duplicate(true)
		_auto_index = surface.automation_point_at(at)
		_auto_added = _auto_index < 0
		if _auto_added:
			var target: String = surface.shown_lane
			var shape := DawKitAutomation.HOLD if target == "mute" else DawKitAutomation.LINEAR
			_auto_index = _place_point(snap(surface.seconds_at_point(at), _fine()),
					surface.value_at_point(at), shape)
			surface.preview_lane(_auto_points)
		return
	_grab_seconds = surface.seconds_at_point(at)
	_hit = surface.item_at_point(at)
	_edge = 0
	if not _hit.is_empty():
		var item: MixState.ItemState = DAW.state.item(_hit[0], _hit[1])
		_item_start = item.start
		_item_end = item.end()
		_target_start = _item_start
		_target_end = _item_end
		_fade_in = item.fade_in
		_fade_out = item.fade_out
		# A block's top corners are its fades; the rest of its edges trim.
		_fade = surface.fade_handle_at_point(at)
		_edge = 0 if _fade != 0 else surface.item_edge_at_point(at)


func _on_grab_move(at: Vector3) -> void:
	if _auto_on:
		if not _dragged and absf(to_local(at).x - _grab_x) < CLICK_SLOP and absf(to_local(at).y - _grab_y) < CLICK_SLOP:
			return
		_dragged = true
		var shape := int(_auto_points[_auto_index][2])
		_auto_points.remove_at(_auto_index)
		_auto_index = _place_point(snap(surface.seconds_at_point(at), _fine()), surface.value_at_point(at), shape)
		surface.preview_lane(_auto_points)
		return
	if _hit.is_empty():
		return
	if not _dragged and absf(to_local(at).x - _grab_x) < CLICK_SLOP and absf(to_local(at).y - _grab_y) < CLICK_SLOP:
		return
	_dragged = true
	var moved: float = surface.seconds_at_point(at) - _grab_seconds
	if _fade != 0:
		# The fade's end snaps to the beat, unless fine; a fade is never longer than the item.
		var length := _item_end - _item_start
		var here: float = surface.seconds_at_point(at)
		if _fade < 0:
			_fade_in = clampf(snap(here, _fine()) - _item_start, 0.0, length)
		else:
			_fade_out = clampf(_item_end - snap(here, _fine()), 0.0, length)
		surface.preview_fades(_hit[0], _hit[1], _fade_in, _fade_out)
		return
	if _edge != 0:
		# The edge being dragged snaps; the other stays put, and the item keeps a real length.
		if _edge < 0:
			_target_start = minf(snap(_item_start + moved, _fine()), _item_end - DAWBackend.MIN_ITEM_SECONDS)
		else:
			_target_end = maxf(snap(_item_end + moved, _fine()), _item_start + DAWBackend.MIN_ITEM_SECONDS)
		surface.preview_item(_hit[0], _hit[1], _target_start, _target_end - _target_start)
		return
	# The START snaps, not the distance moved: an item that began off the grid lands on it, which
	# is what a drag in an arranger is nearly always for.
	_target_start = snap(_item_start + surface.seconds_at_point(at) - _grab_seconds, _fine())
	# And onto whichever lane it is over now: off one shelf and onto another.
	_target_track = surface.track_at_point(at)
	if _target_track <= 0:
		_target_track = _hit[0]
	surface.preview_item(_hit[0], _hit[1], _target_start, -1.0, _target_track)


func _on_grab_end() -> void:
	if _auto_on:
		_finish_point()
		_auto_on = false
		_dragged = false
		return
	_finish_grab()
	# Forgotten once the hand lets go. Kept, the hover card went on reading "move to 27.1.00"
	# under a pointer resting on an item that had long since landed.
	_hit = []
	_dragged = false
	_edge = 0
	_fade = 0


func _finish_grab() -> void:
	if _hit.is_empty():
		if not _dragged:
			DAW.clear_item_selection()
			DAW.seek(snap(_grab_seconds, _fine()))
		return
	var item: MixState.ItemState = DAW.state.item(_hit[0], _hit[1])
	surface.preview_item(-1, -1, 0.0)
	if item == null:
		return
	if not _dragged:
		DAW.select_item(_hit[0], _hit[1], _fine())
		return
	# Dragging an item that was not selected selects it, as it does in Reaper -- what you just
	# moved is what you are working on.
	if not item.selected:
		DAW.select_item(_hit[0], _hit[1], false)
	if _fade != 0:
		surface.preview_fades(-1, -1)
		if not is_equal_approx(_fade_in, item.fade_in) or not is_equal_approx(_fade_out, item.fade_out):
			DAW.set_item_fades(_hit[0], _hit[1], _fade_in, _fade_out)
		return
	if _edge != 0:
		if not is_equal_approx(_target_start, item.start) or not is_equal_approx(_target_end, item.end()):
			DAW.trim_item(_hit[0], _hit[1], _target_start, _target_end)
		return
	var onto := _target_track if _target_track > 0 and _target_track != _hit[0] else 0
	if not is_equal_approx(_target_start, item.start) or onto > 0:
		DAW.move_item(_hit[0], _hit[1], _target_start, onto)


## A point into the lane being edited, replacing one at the same moment; its index.
func _place_point(seconds: float, value: float, shape: int) -> int:
	var target: String = surface.shown_lane
	var point := [maxf(seconds, 0.0), DawKitAutomation.clamp_value(target, value), shape]
	for i in _auto_points.size():
		if absf(float(_auto_points[i][0]) - point[0]) < 0.0005:
			_auto_points[i] = point
			return i
	var at := 0
	while at < _auto_points.size() and float(_auto_points[at][0]) < point[0]:
		at += 1
	_auto_points.insert(at, point)
	return at


func _finish_point() -> void:
	var target: String = surface.shown_lane
	var track: int = surface.picked_track
	surface.preview_lane([])
	if not _dragged and not _auto_added and _auto_index >= 0 and _auto_index < _auto_points.size():
		if _fine():
			_auto_points.remove_at(_auto_index)
		elif target != "mute":
			var p: Array = _auto_points[_auto_index]
			p[2] = DawKitAutomation.LINEAR if int(p[2]) == DawKitAutomation.HOLD else DawKitAutomation.HOLD
	# The lane as it stands (the preview is gone): a track's, or the master's.
	if _auto_points != surface.shown_points():
		DAW.set_automation(track, target, _auto_points)
	_auto_points = []
	_auto_index = -1


## How far one wheel notch moves a point's value; fine moves it a tenth as far.
static func nudge_step(target: String) -> float:
	match DawKitAutomation.kind_of(target):
		"volume", "send":
			return 0.5
		"pan":
			return 0.02
		"mute":
			return 1.0
	return 0.01


func _on_nudge(notches: int, fine: bool) -> bool:
	var by: Node = held_by if held_by != null else (_hovered_by[0] if not _hovered_by.is_empty() else null)
	if by != null and "hover_point" in by and surface.on_shown_lane(by.hover_point):
		var i: int = surface.automation_point_at(by.hover_point)
		if i >= 0:
			var target: String = surface.shown_lane
			var points: Array = surface.shown_points().duplicate(true)
			var v := float(points[i][1])
			if target == "mute":
				v = 1.0 - v if notches % 2 != 0 else v
			else:
				v += notches * nudge_step(target) * (0.1 if fine else 1.0)
			points[i][1] = DawKitAutomation.clamp_value(target, v)
			DAW.set_automation(surface.picked_track, target, points)
			return true
	var factor := pow(ZOOM_STEP if not fine else 0.96, notches)
	surface.zoom_view(factor)
	return true


## What is under the pointer, for the hover card.
func _pointer_item() -> MixState.ItemState:
	var by: Node = held_by if held_by != null else (_hovered_by[0] if not _hovered_by.is_empty() else null)
	if by == null or not ("hover_point" in by):
		return null
	var hit: Array = surface.item_at_point(by.hover_point)
	return null if hit.is_empty() else DAW.state.item(hit[0], hit[1])


## The lanes as a whole, not the item under the pointer. The title follows the pointer, so it
## would name a different control on every frame of a drag -- and on every other desk, where
## the pointer is somebody else's.
func network_key() -> String:
	return "TIMELINE"


func _default_title() -> String:
	if _lane_readout() != "":
		return "AUTOMATION  %s" % TimelineSurface.lane_name(surface.shown_lane)
	var item := _pointer_item()
	if item == null:
		return "TIMELINE"
	return "ITEM  %s%s" % [item.name if item.name != "" else "(unnamed)", "  SELECTED" if item.selected else ""]


## The shown lane under the pointer: the point there, or the lane's value where the pointer is.
func _lane_readout() -> String:
	var by: Node = held_by if held_by != null else (_hovered_by[0] if not _hovered_by.is_empty() else null)
	if by == null or not ("hover_point" in by) or not surface.on_shown_lane(by.hover_point):
		return ""
	var target: String = surface.shown_lane
	var points: Array = surface.shown_points()
	var i: int = _auto_index if _auto_on and _auto_index >= 0 else surface.automation_point_at(by.hover_point)
	if i >= 0 and i < points.size():
		return "%s at %s%s" % [TimelineSurface.lane_text(target, points[i][1]),
				DAW.state.bar_beat(points[i][0]), ", held" if int(points[i][2]) == DawKitAutomation.HOLD else ""]
	var at: float = surface.seconds_at_point(by.hover_point)
	return "press to add a point: %s at %s" % [TimelineSurface.lane_text(target, surface.value_at_point(by.hover_point)),
			DAW.state.bar_beat(snap(at, false))]


func _default_readout() -> String:
	var lane := _lane_readout()
	if lane != "":
		return lane
	var s := DAW.state
	if _dragged and not _hit.is_empty():
		if _fade < 0:
			return "fade in %.2f s" % _fade_in
		if _fade > 0:
			return "fade out %.2f s" % _fade_out
		if _edge < 0:
			return "trim start to %s" % s.bar_beat(_target_start)
		if _edge > 0:
			return "trim end to %s" % s.bar_beat(_target_end)
		return "move to %s" % s.bar_beat(_target_start)
	var item := _pointer_item()
	if item == null:
		return "view %s - %s" % [s.bar_beat(surface.view_start), s.bar_beat(surface.view_start + surface.view_span)]
	var bar := s.bar_to_seconds(2.0)
	return "%s - %s  (%.2f bars, %s)" % [s.bar_beat(item.start), s.bar_beat(item.end()),
			item.length / maxf(bar, 0.0001), TimelineRuler._clock(item.start)]


func hint() -> String:
	return "click to select, shift adds; drag to move, by an edge to trim, by a top corner to fade; wheel zooms; B or SPLIT cuts at the playhead"
