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
## Ticks across the full sweep. Twenty-four puts a detent every eleven degrees, which is about
## the smallest deliberate nudge a wrist makes; finer than that and the ticks fuse into a rattle
## that says "something is moving" without saying how much.
const DETENTS := 24
const RADIUS := 0.011
const MESH_PATH := "res://assets/hardware/knob.glb"

signal turned(v: float)

## Where this knob's body gets drawn, if the desk gave it somewhere. Ninety strips is ninety
## identical moulded knobs in one finish, which is the shape a bank wants -- the only thing
## that makes a knob harder than a lamp is that it TURNS, and a bank slot can be moved. See
## MeshBank.move_slot.
var body_bank: MeshBank

var _spindle: Node3D
## The node whose transform the bank slot follows. Kept rather than freed after the claim,
## because unlike a jack this part does not stay where it was put: every turn has to hand the
## bank a new transform, and the cheapest way to compute one is to let the scene tree do it.
var _aim: Node3D
var _slot := -1
var _grab_angle := 0.0
var _grab_value := 0.0
var _last_detent := -1


static func shared_mesh() -> Mesh:
	return Part.mesh(MESH_PATH)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0

	_spindle = Node3D.new()
	add_child(_spindle)

	# Modelled axis-up, exported through glTF's Y-up conversion, stood back up here. Same
	# correction the CylinderMesh needed, for the same reason: a panel knob's axis is the panel
	# normal, which is local Z. Done on a holder either way, so the banked knob and the loose
	# one sit at the same angle.
	_aim = Node3D.new()
	_aim.rotation_degrees = Vector3(90, 0, 0)
	_spindle.add_child(_aim)

	if body_bank != null:
		_slot = body_bank.place(_aim, Color.WHITE)
	else:
		var moulded := Part.build(
			MESH_PATH,
			Materials.cap_plastic(Color(0.14, 0.15, 0.17)),
			{"indicator": Materials.legend()},
		)
		if moulded != null:
			_aim.add_child(moulded)
		else:
			_aim.queue_free()
			_aim = null
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


## Well below the buttons. These fire twenty times a second during a sweep, and anything near
## conversational level becomes the loudest thing in the room the moment someone turns a knob.
const DETENT_DB := -16.0


func _foley_contact() -> AudioStream:
	# Taking hold of a detented knob moves it off its notch, so it ticks once before you have
	# turned it anywhere. That is not a flourish; it is the confirmation that you have it.
	return Foley.knob_detent()


func _on_grab_begin(at: Vector3) -> void:
	_grab_angle = _angle_of(at)
	_last_detent = detent_of(value)
	_grab_value = value


func _on_grab_move(at: Vector3) -> void:
	var delta := _angle_of(at) - _grab_angle
	# Wrapped, or a knob dragged past straight-down would jump a full turn.
	delta = wrapf(delta, -PI, PI)
	value = Ergonomics.current.quantise(clampf(_grab_value - delta / SWEEP, 0.0, 1.0))
	# One tick per boundary CROSSED, not one per frame in which the value changed. A knob turned
	# slowly should tick rarely and a knob spun fast should tick fast, and the only thing that
	# gets both right is counting the boundaries rather than the frames.
	var detent := detent_of(value)
	if detent != _last_detent:
		_last_detent = detent
		Foley.play(self, Foley.knob_detent(), DETENT_DB)
	_on_value_changed()
	turned.emit(value)


## Which notch a 0..1 value sits in. Static so the suite can check the thing that matters -- that
## a full sweep crosses every detent exactly once -- without turning a knob.
static func detent_of(v: float) -> int:
	return mini(int(clampf(v, 0.0, 1.0) * DETENTS), DETENTS - 1)


func _angle_of(at: Vector3) -> float:
	var local := to_local(at)
	return atan2(local.x, local.y)


func _on_value_changed() -> void:
	if _spindle == null:
		return
	_spindle.rotation = Vector3(0, 0, -(value - 0.5) * SWEEP)
	# Pushed to the bank AFTER the spindle has turned, and read off the aim node's global
	# transform rather than composed by hand: the knob sits under a strip under a panel under
	# a tilted surface, and reproducing that chain here would be a second definition of where
	# the knob is, drifting against the first.
	if _slot >= 0 and _aim != null:
		body_bank.move_slot(_slot, body_bank.global_transform.affine_inverse() * _aim.global_transform)


func hint() -> String:
	return "drag to turn"


## A pan position the way a desk prints one: centre is C, not 50%, and the sides are named.
static func pan_text(v: float) -> String:
	var off := roundi((v - 0.5) * 200.0)
	if off == 0:
		return "C"
	return "%s %d" % ["L" if off < 0 else "R", absi(off)]
