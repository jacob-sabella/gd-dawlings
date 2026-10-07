class_name PatchPoint
extends ControlAffordance

## One jack on the bay: a track's output, or a track's input.
##
## Dragging from an output to an input is how a send gets made. The gesture is the same with a
## mouse and with a hand because it is built on the shared grab contract -- press on one jack,
## release on another -- and the Interactor's hover is what names the second jack. There is no
## separate "connect mode".
##
## A drag that ends on nothing is a cancelled patch, not an error. That is the behaviour of a
## cable you picked up and put back.

signal patch_requested(from: PatchPoint, to: PatchPoint)

const Kind := {OUTPUT = 0, INPUT = 1}

const RADIUS := 0.009
const MESH_PATH := "res://assets/hardware/jack.glb"

var track_index: int = 0
var kind: int = Kind.OUTPUT
var label_text: String = ""

var _ring: MeshInstance3D


static func create(track_idx: int, jack_kind: int, text: String) -> PatchPoint:
	var p := PatchPoint.new()
	p.track_index = track_idx
	p.kind = jack_kind
	p.label_text = text
	p.name = "Jack_%s_%d" % ["out" if jack_kind == Kind.OUTPUT else "in", track_idx]
	return p


## How far this particular nut was done up. Nobody torques two dozen jacks to the same angle,
## and a bay where every hex points the same way reads as a texture rather than as hardware.
##
## Derived from the jack's own identity rather than randomised, so it survives a rebuild: the
## bay redraws whenever the track list changes, and nuts that reshuffled on every redraw would
## be a shimmer nobody could explain.
static func nut_angle(track_idx: int, jack_kind: int) -> float:
	# Sixty degrees is a whole turn as far as a hexagon is concerned.
	return fposmod(float(track_idx * 23 + jack_kind * 41), 60.0)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0

	# A hex nut, a chamfered mouth and a 20mm barrel behind the panel, which is where most of a
	# jack lives and where all of a seated plug goes (tools/blender/jack.py).
	var socket := Part.build(
		MESH_PATH,
		Materials.brushed_metal(),
		{"bore": Materials.recess()},
	)
	if socket != null:
		# Modelled axis-up; the axis here is the panel normal, which is local Z.
		socket.rotation_degrees = Vector3(90, 0, 0)
		# Clocked, through a parent rather than a third Euler angle, because spinning the part
		# about ITS axis and spinning it about the panel's are different rotations and the
		# Euler order quietly picks the wrong one.
		var spin := Node3D.new()
		spin.rotation_degrees = Vector3(0, 0, nut_angle(track_index, kind))
		spin.add_child(socket)
		add_child(spin)
	else:
		add_child(_stand_in())

	var caption := Label3D.new()
	caption.font_size = 32
	caption.pixel_size = 0.00017
	caption.text = label_text.to_upper()
	caption.position = Vector3(0, -RADIUS - 0.006, 0.001)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.modulate = Color(0.7, 0.72, 0.74)
	add_child(caption)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS * 1.5
	shape.shape = sphere
	add_child(shape)


## The pre-Blender jack: a torus with a flat dark disc behind it. Kept because a bay whose
## sockets you cannot see is a bay you cannot aim at.
func _stand_in() -> Node3D:
	var holder := Node3D.new()

	_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = RADIUS * 0.62
	ring_mesh.outer_radius = RADIUS
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 8
	_ring.mesh = ring_mesh
	_ring.rotation_degrees = Vector3(90, 0, 0)
	_ring.material_override = Materials.brushed_metal()
	holder.add_child(_ring)

	var bore := MeshInstance3D.new()
	var bore_mesh := CylinderMesh.new()
	bore_mesh.top_radius = RADIUS * 0.6
	bore_mesh.bottom_radius = RADIUS * 0.6
	bore_mesh.height = 0.008
	bore_mesh.radial_segments = 14
	bore.mesh = bore_mesh
	bore.rotation_degrees = Vector3(90, 0, 0)
	bore.position = Vector3(0, 0, -0.004)
	bore.material_override = Materials.recess()
	holder.add_child(bore)
	return holder


func _on_grab_end() -> void:
	# held_by is still set at this point -- ControlAffordance clears it after this returns, which
	# is what makes reading the interactor's hover here possible at all.
	if held_by is Interactor:
		var target = held_by.hovered
		if target is PatchPoint and target != self:
			patch_requested.emit(self, target)
