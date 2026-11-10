class_name RackHandle
extends ControlAffordance

## The grip along the top of a rack module: press it, mouse or hand, and the module comes away from the
## case and follows you; let go over a free place and it settles there. The wall does the moving; the
## handle only says where the drag went.

## A drag started on the handle at world point `at`.
signal drag_began(from: RackHandle, at: Vector3)
## The drag moved to `at`.
signal drag_moved(from: RackHandle, at: Vector3)
## The drag was let go at `at`.
signal drag_finished(from: RackHandle, at: Vector3)
## The handle was pressed and let go without moving: a click on the module's name, which asks for its help.
signal clicked(from: RackHandle)

## How far, in metres, a press may wander and still be a click.
const CLICK_SLACK := 0.012

var module_id := ""
var module_title := ""
var size := Vector2(0.1, 0.05)
var _strip: MeshInstance3D
var _at := Vector3.ZERO
var _start := Vector3.ZERO


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.02)
	shape.shape = box
	shape.position = Vector3(0, 0, 0.01)
	add_child(shape)
	# A strip that lights under a hand, so the grip is found before it is pressed.
	_strip = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	_strip.mesh = quad
	_strip.position = Vector3(0, 0, 0.0012)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.0)
	_strip.material_override = m
	_strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_strip)
	hover_changed.connect(func(_h: bool) -> void: _shine())


func _shine() -> void:
	var m := _strip.material_override as StandardMaterial3D
	m.albedo_color = Color(1, 0.95, 0.8, 0.28 if is_held() else (0.14 if is_hovered() else 0.0))


func _default_title() -> String:
	return "RACK  %s" % module_title


func _default_readout() -> String:
	return "in the case"


func hint() -> String:
	return "click the name, or the ? on the plate, for help · drag to move it about the case, let go over a free place to put it there"


func _on_grab_begin(at: Vector3) -> void:
	_at = at
	_start = at
	_shine()
	drag_began.emit(self, at)


func _on_grab_move(at: Vector3) -> void:
	_at = at
	drag_moved.emit(self, at)


func _on_grab_end() -> void:
	_shine()
	drag_finished.emit(self, _at)
	if _at.distance_to(_start) <= CLICK_SLACK:
		clicked.emit(self)
