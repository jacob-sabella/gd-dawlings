class_name TimelineHeader
extends ControlAffordance

## The column of track names, as the thing that scrolls the lanes.
##
## The wheel over the names moves the panel through the track list a lane per notch, and a drag
## up or down does the same at a lane per lane-height dragged. Over the lanes the wheel zooms
## time; over the names it scrolls tracks. Two places, two meanings, each where the thing it
## moves is drawn. A press that does not scroll picks the track, for the track keys.

var width := 0.1
var height := 0.2
## The TimelineSurface.
var surface: Node

var _shape: CollisionShape3D
var _grab_y := 0.0
var _scrolled := 0
var _grab_point := Vector3.ZERO


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


func _on_grab_begin(at: Vector3) -> void:
	_grab_y = to_local(at).y
	_grab_point = at
	_scrolled = 0


func _on_grab_end() -> void:
	if _scrolled == 0:
		var picked: int = surface.track_at_point(_grab_point)
		surface.pick_track(0 if picked == surface.picked_track else picked)


func _on_grab_move(at: Vector3) -> void:
	# Dragging the names up brings later tracks up into view, the way a page is pushed.
	var lanes := int((to_local(at).y - _grab_y) / (float(surface.lane_height) + TimelineSurface.LANE_GAP))
	if lanes != _scrolled:
		surface.scroll_lanes(lanes - _scrolled)
		_scrolled = lanes


func _on_nudge(notches: int, fine: bool) -> bool:
	# Wheel up is earlier tracks, as in every list. Fine is a lane at a time; plain is three.
	return surface.scroll_lanes(-notches * (1 if fine else 3))


func _default_title() -> String:
	return "TRACKS"


func _default_readout() -> String:
	var total := DAW.state.track_indices().size()
	var shown: Array = surface._shown()
	if shown.is_empty():
		return "no tracks"
	return "%d-%d of %d" % [surface.lane_first + 1, surface.lane_first + shown.size(), total]


func hint() -> String:
	return "wheel or drag to scroll the tracks; press a name to pick it for ADD, DEL and NAME"
