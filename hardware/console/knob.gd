class_name Knob
extends ControlAffordance

## A panel knob: pan, an FX parameter, a send level.
##
## Rotary rather than drag-vertical. A drag-vertical knob is easier to implement and is what most
## plugin UIs do, but this project's premise is that the thing is hardware -- and a knob you turn
## by turning it is most of why reaching for one feels different from reaching for a slider.
##
## Sweep is 270 degrees, the convention for a potentiometer, centred on local +Y at value 0.5.

const SWEEP := deg_to_rad(270.0)
const RADIUS := 0.011

signal turned(v: float)

var _indicator: Node3D
var _grab_angle := 0.0
var _grab_value := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0

	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = RADIUS * 0.88
	body_mesh.bottom_radius = RADIUS
	body_mesh.height = 0.013
	body_mesh.radial_segments = 20
	body.mesh = body_mesh
	# Cylinders stand along Y; a panel knob's axis is the panel normal, which is local Z.
	body.rotation_degrees = Vector3(90, 0, 0)
	body.material_override = Materials.cap_plastic(Color(0.14, 0.15, 0.17))
	add_child(body)

	_indicator = MeshInstance3D.new()
	var ind_mesh := BoxMesh.new()
	ind_mesh.size = Vector3(0.0018, RADIUS * 0.95, 0.002)
	_indicator.mesh = ind_mesh
	_indicator.material_override = Materials.legend()
	add_child(_indicator)

	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS * 1.5
	cyl.height = 0.02
	shape.shape = cyl
	shape.rotation_degrees = Vector3(90, 0, 0)
	add_child(shape)

	_on_value_changed()


func _on_grab_begin(at: Vector3) -> void:
	_grab_angle = _angle_of(at)
	_grab_value = value


func _on_grab_move(at: Vector3) -> void:
	var delta := _angle_of(at) - _grab_angle
	# Wrapped, or a knob dragged past straight-down would jump a full turn.
	delta = wrapf(delta, -PI, PI)
	value = clampf(_grab_value - delta / SWEEP, 0.0, 1.0)
	_on_value_changed()
	turned.emit(value)


func _angle_of(at: Vector3) -> float:
	var local := to_local(at)
	return atan2(local.x, local.y)


func _on_value_changed() -> void:
	if _indicator:
		var angle := (value - 0.5) * SWEEP
		_indicator.rotation = Vector3(0, 0, -angle)
		_indicator.position = Vector3(sin(angle) * RADIUS * 0.5, cos(angle) * RADIUS * 0.5, 0.008)
