class_name Caster
extends Node3D

## One swivel caster under a piece of furniture: a top plate, a fork that turns, a wheel that
## rolls.
##
## Animated rather than painted on, because a rack that slides across the floor with its wheels
## frozen reads as a rack being dragged by an invisible crane. What sells "on wheels" is the two
## things a real caster does that nobody consciously notices until they are missing: the fork
## swings round to TRAIL the direction of travel, lazily, a beat after the push changes; and the
## wheel turns at exactly the speed the floor goes past.
##
## The origin is the floor contact point under the kingpin, so the furniture builder places a
## caster by saying where on the floor it stands.

const HEIGHT := 0.062
const WHEEL_RADIUS := 0.024
const WHEEL_WIDTH := 0.017
## How far behind the kingpin the axle sits. The offset IS the mechanism: it is the lever that
## makes the fork swing round to trail whichever way the load is moving.
const TRAIL := 0.016
## How quickly the fork comes round, in radians per second at full misalignment. Slower than the
## push, so a change of direction shows as the casters visibly turning to follow.
const SWING_RATE := 9.0

var _swivel: Node3D
var _wheel: Node3D
var _heading := 0.0


func _ready() -> void:
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.052, 0.006, 0.052)
	plate.mesh = plate_mesh
	plate.position = Vector3(0, HEIGHT - 0.003, 0)
	plate.material_override = Materials.brushed_metal()
	add_child(plate)

	_swivel = Node3D.new()
	_swivel.name = "Swivel"
	add_child(_swivel)

	var kingpin := MeshInstance3D.new()
	var pin_mesh := CylinderMesh.new()
	pin_mesh.top_radius = 0.009
	pin_mesh.bottom_radius = 0.009
	pin_mesh.height = 0.010
	pin_mesh.radial_segments = 10
	kingpin.mesh = pin_mesh
	kingpin.position = Vector3(0, HEIGHT - 0.011, 0)
	kingpin.material_override = Materials.brushed_metal()
	_swivel.add_child(kingpin)

	# The two cheeks of the fork, dropping from the kingpin to either end of the axle.
	var fork_height := HEIGHT - 0.016 - WHEEL_RADIUS + 0.006
	for side in [-1.0, 1.0]:
		var cheek := MeshInstance3D.new()
		var cheek_mesh := BoxMesh.new()
		cheek_mesh.size = Vector3(0.003, fork_height, 0.030)
		cheek.mesh = cheek_mesh
		cheek.position = Vector3(side * (WHEEL_WIDTH * 0.5 + 0.003),
				WHEEL_RADIUS - 0.006 + fork_height * 0.5, TRAIL * 0.5)
		cheek.material_override = Materials.brushed_metal()
		_swivel.add_child(cheek)

	_wheel = Node3D.new()
	_wheel.name = "Wheel"
	_wheel.position = Vector3(0, WHEEL_RADIUS, TRAIL)
	_swivel.add_child(_wheel)

	var tyre := MeshInstance3D.new()
	var tyre_mesh := CylinderMesh.new()
	tyre_mesh.top_radius = WHEEL_RADIUS
	tyre_mesh.bottom_radius = WHEEL_RADIUS
	tyre_mesh.height = WHEEL_WIDTH
	tyre_mesh.radial_segments = 18
	tyre.mesh = tyre_mesh
	tyre.rotation_degrees = Vector3(0, 0, 90)
	tyre.material_override = Materials.cap_plastic(Color(0.07, 0.07, 0.075))
	_wheel.add_child(tyre)

	# A spoke on each face, in the fork's metal. Without something off-axis on the wheel, a
	# spinning cylinder and a stationary one are the same picture and the roll is invisible.
	for side in [-1.0, 1.0]:
		var spoke := MeshInstance3D.new()
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(0.0015, WHEEL_RADIUS * 1.5, 0.005)
		spoke.mesh = spoke_mesh
		spoke.position = Vector3(side * (WHEEL_WIDTH * 0.5 + 0.0006), 0, 0)
		spoke.material_override = Materials.brushed_metal()
		_wheel.add_child(spoke)

	for node in find_children("*", "MeshInstance3D", true, false):
		# Two centimetres of wheel do not need a shadow map pass each; sixteen of them would be
		# the most expensive thing about the furniture.
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Roll by how far the floor went past this caster, in the furniture's own frame.
##
## `travel` is the floor-plane displacement of THIS caster -- not of the piece -- which matters
## when the piece turns: the casters on the outside of a turn go further than the ones on the
## inside, and the ones near the pivot barely move, exactly as on a real trolley.
func roll(travel: Vector2, delta: float) -> void:
	if _swivel == null:
		return
	var distance := travel.length()
	if distance < 0.00002:
		return
	# Trailing: the wheel sits on the fork's +Z, and it settles BEHIND the kingpin, so the
	# fork's +Z swings round to point against the direction of travel.
	var want := atan2(-travel.x, -travel.y)
	var off := wrapf(want - _heading, -PI, PI)
	# A caster pushed straight back against its trail flips through 180 degrees, but it does
	# not snap: it swings, and the push drags it the rest of the way round.
	_heading += clampf(off, -SWING_RATE * delta, SWING_RATE * delta) * clampf(distance / 0.002, 0.2, 1.0)
	_swivel.rotation.y = _heading
	# Only the part of the travel along the wheel's rolling direction turns it. The rest is the
	# wheel scrubbing sideways while the fork comes round, which is real, and silent.
	var along := Vector2(sin(_heading), cos(_heading)).dot(-travel)
	_wheel.rotate_object_local(Vector3.RIGHT, along / WHEEL_RADIUS)


func heading() -> float:
	return _heading
