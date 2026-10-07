class_name Knob
extends ControlAffordance

## A panel knob: pan, an FX parameter, a send level.
##
## Rotary rather than drag-vertical. A drag-vertical knob is easier to implement and is what most
## plugin UIs do, but this project's premise is that the thing is hardware -- and a knob you turn
## by turning it is most of why reaching for one feels different from reaching for a slider.
##
## Sweep is 270 degrees, the convention for a potentiometer, centred on local +Y at value 0.5.
##
## THE WHOLE KNOB TURNS, not a marker on top of it. The mesh is a moulded part with a knurled
## skirt and an indicator flute bent over its top edge (tools/blender/knob.py), so the knurling
## rotating under the light is itself a readout -- the same reason real skirts are knurled rather
## than smooth. The old shape was a cylinder with a white box orbiting a stationary body, which
## at a glance read as a dial with a pointer floating above it.
##
## The envelope is unchanged: 22mm across, 13mm deep, centred on this node. Consoles laid
## themselves out around those numbers before the mesh existed.

const SWEEP := deg_to_rad(270.0)
const RADIUS := 0.011
const MESH_PATH := "res://assets/hardware/knob.glb"

signal turned(v: float)

var _spindle: Node3D
var _grab_angle := 0.0
var _grab_value := 0.0


static func shared_mesh() -> Mesh:
	return Part.mesh(MESH_PATH)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0

	_spindle = Node3D.new()
	add_child(_spindle)

	var moulded := Part.build(
		MESH_PATH,
		Materials.cap_plastic(Color(0.14, 0.15, 0.17)),
		{"indicator": Materials.legend()},
	)
	if moulded != null:
		# Modelled axis-up, exported through glTF's Y-up conversion, stood back up here. Same
		# correction the CylinderMesh needed, for the same reason: a panel knob's axis is the
		# panel normal, which is local Z.
		moulded.rotation_degrees = Vector3(90, 0, 0)
		_spindle.add_child(moulded)
	else:
		_spindle.add_child(_stand_in())

	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS * 1.5
	cyl.height = 0.02
	shape.shape = cyl
	shape.rotation_degrees = Vector3(90, 0, 0)
	add_child(shape)

	_on_value_changed()


## The pre-Blender knob, kept as the fallback so a missing asset is a plainer desk rather than a
## desk with invisible controls on it.
func _stand_in() -> Node3D:
	var holder := Node3D.new()

	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = RADIUS * 0.88
	body_mesh.bottom_radius = RADIUS
	body_mesh.height = 0.013
	body_mesh.radial_segments = 20
	body.mesh = body_mesh
	body.rotation_degrees = Vector3(90, 0, 0)
	body.material_override = Materials.cap_plastic(Color(0.14, 0.15, 0.17))
	holder.add_child(body)

	var indicator := MeshInstance3D.new()
	var ind_mesh := BoxMesh.new()
	ind_mesh.size = Vector3(0.0018, RADIUS * 0.95, 0.002)
	indicator.mesh = ind_mesh
	indicator.position = Vector3(0, RADIUS * 0.5, 0.008)
	indicator.material_override = Materials.legend()
	holder.add_child(indicator)

	return holder


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
	if _spindle:
		_spindle.rotation = Vector3(0, 0, -(value - 0.5) * SWEEP)
