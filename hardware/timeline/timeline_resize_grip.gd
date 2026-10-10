class_name TimelineResizeGrip
extends ControlAffordance

## The timeline's size, by its bottom right corner, the way a window is resized: drag sideways
## for a wider or narrower panel, up or down for shorter or taller lanes -- more of the song's
## tracks in view, or bigger blocks to take hold of. The corner follows the hand. A click without
## a drag puts the usual size back.
##
## Built once, like the surface's keys: the panel rebuilds under it while it is dragged, and a
## control rebuilt under a held drag drops the drag.

## Less than this between press and release is a click, not a drag. Metres.
const CLICK_SLOP := 0.002
## How often a drag resizes the panel: each resize is a rebuild of it.
const RESIZE_MSEC := 60
const SIZE := Vector2(0.022, 0.014)

## The TimelineSurface. Typed loosely so the two files do not have to load in an order.
var surface: Node

var _from := Vector3.ZERO
var _from_scale := 1.0
var _from_lane := 0.0
var _from_width := 1.0
var _lanes := 1
var _moved := false
var _wanted := Vector2.ZERO
var _applied_msec := 0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x, SIZE.y, 0.010)
	shape.shape = box
	add_child(shape)
	# Three ridges across the corner, as on a window's.
	for i in 3:
		var ridge := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.004 + i * 0.004, 0.0008, 0.0006)
		ridge.mesh = mesh
		ridge.rotation.z = PI * 0.25
		ridge.position = Vector3(0.004 - i * 0.002, -0.002 + i * 0.002, 0.0004)
		ridge.material_override = TimelineSurface.flat(TimelineSurface.RULER_TICK)
		ridge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ridge)
	describe_title = func() -> String: return "VIEW  SIZE"
	describe_value = func(_v: float) -> String:
		return "%d%% wide, lanes %.0fmm: drag to resize, click for the usual size" % [
				roundi(float(surface.width_scale) * 100.0), float(surface.lane_height) * 1000.0]


func _on_grab_begin(at: Vector3) -> void:
	_from = surface.to_local(at)
	_from_scale = surface.width_scale
	_from_lane = surface.lane_height
	_from_width = surface.width
	_lanes = maxi((surface._lane_y as Array).size(), 1)
	_moved = false
	_wanted = Vector2(_from_scale, _from_lane)


func _on_grab_move(at: Vector3) -> void:
	var here: Vector3 = surface.to_local(at)
	var dx := here.x - _from.x
	var dy := here.y - _from.y
	if not _moved and absf(dx) < CLICK_SLOP and absf(dy) < CLICK_SLOP:
		return
	_moved = true
	# The panel grows about its middle, so the corner moves half as far as the panel grows:
	# twice the hand's travel, and the corner stays under the hand.
	_wanted = Vector2(_from_scale * (_from_width + 2.0 * dx) / _from_width,
			_from_lane - 2.0 * dy / float(_lanes))
	if Time.get_ticks_msec() - _applied_msec >= RESIZE_MSEC:
		_applied_msec = Time.get_ticks_msec()
		surface.set_size(_wanted.x, _wanted.y)


func _on_grab_end() -> void:
	if _moved:
		surface.choose_size(_wanted.x, _wanted.y)
	else:
		surface.choose_size(1.0, TimelineSurface.LANE_HEIGHT)
