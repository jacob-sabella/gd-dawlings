class_name TimelineLanes
extends ControlAffordance

## The lanes of the timeline, as something a hand can edit.
##
## Press an item to select it (fine -- shift on a monitor -- adds it to the selection or takes it
## out). Drag it to move it along its lane, snapped to the beat unless fine. Press empty lane to
## drop the selection and put the playhead there. The wheel zooms, round the playhead the way
## Reaper zooms round its edit cursor. Splitting is a key, not a gesture: see the surface.
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
	(_shape.shape as BoxShape3D).size = Vector3(width, height, 0.010)


## Snapped to the beat, unless fine.
static func snap(seconds: float, fine: bool) -> float:
	var s := maxf(seconds, 0.0)
	if fine:
		return s
	var beat := 60.0 / maxf(DAW.state.tempo, 1.0)
	return roundf(s / beat) * beat


func _fine() -> bool:
	return held_by != null and held_by.has_method("fine") and held_by.fine()


func _on_grab_begin(at: Vector3) -> void:
	_grab_x = to_local(at).x
	_dragged = false
	_grab_seconds = surface.seconds_at_point(at)
	_hit = surface.item_at_point(at)
	if not _hit.is_empty():
		_item_start = DAW.state.item(_hit[0], _hit[1]).start
		_target_start = _item_start


func _on_grab_move(at: Vector3) -> void:
	if _hit.is_empty():
		return
	if not _dragged and absf(to_local(at).x - _grab_x) < CLICK_SLOP:
		return
	_dragged = true
	# The START snaps, not the distance moved: an item that began off the grid lands on it, which
	# is what a drag in an arranger is nearly always for.
	_target_start = snap(_item_start + surface.seconds_at_point(at) - _grab_seconds, _fine())
	surface.preview_item(_hit[0], _hit[1], _target_start)


func _on_grab_end() -> void:
	_finish_grab()
	# Forgotten once the hand lets go. Kept, the hover card went on reading "move to 27.1.00"
	# under a pointer resting on an item that had long since landed.
	_hit = []
	_dragged = false


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
	if not is_equal_approx(_target_start, item.start):
		DAW.move_item(_hit[0], _hit[1], _target_start)


func _on_nudge(notches: int, fine: bool) -> bool:
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
	var item := _pointer_item()
	if item == null:
		return "TIMELINE"
	return "ITEM  %s%s" % [item.name if item.name != "" else "(unnamed)", "  SELECTED" if item.selected else ""]


func _default_readout() -> String:
	var s := DAW.state
	if _dragged and not _hit.is_empty():
		return "move to %s" % s.bar_beat(_target_start)
	var item := _pointer_item()
	if item == null:
		return "view %s - %s" % [s.bar_beat(surface.view_start), s.bar_beat(surface.view_start + surface.view_span)]
	var bar := s.bar_to_seconds(2.0)
	return "%s - %s  (%.2f bars, %s)" % [s.bar_beat(item.start), s.bar_beat(item.end()),
			item.length / maxf(bar, 0.0001), TimelineRuler._clock(item.start)]


func hint() -> String:
	return "click to select, shift adds; drag to move; wheel zooms; B or SPLIT cuts at the playhead"
