class_name PatchMult
extends Node3D

## A mult: a short strip of jacks wired to each other, bolted under the bay.
##
## WHY IT EXISTS. One jack takes one plug. That is not a detail -- it is the whole physical
## premise of a patchbay, and the bay was breaking it: four tracks sending to the reverb return
## drew four cables ending at the same bore, four plugs occupying one hole. At a distance it
## read as a neat fan into a return. Up close it read as geometry that had never been asked
## what it was.
##
## A mult is what a studio actually reaches for. Several jacks bussed together in parallel, so
## signals can be split off one source or -- as here -- gathered onto one destination. The
## sources plug into the mult, and ONE cable runs from the mult up to the return's input. The
## picture is now true: every bore holds exactly one plug, and the extra hardware the routing
## needs is visible as extra hardware rather than hidden inside an impossible socket.
##
## Mults are packed left to right below the bay and never overlap, so an arbitrary number of
## them at arbitrary fan-in still lays out. They are deliberately plain -- a dark block, a
## painted bus bar, a name -- because they are the least interesting object on the bridge and
## should not compete with the cables they exist to make honest.

const WAY_PITCH := 0.022
const HEIGHT := 0.040
const DEPTH := 0.012
const PAD := 0.012

## How far above the block the bay's lower edge is, so the straps that hang it can be drawn
## to reach. Zero means draw none -- a mult sitting on something does not need hanging.
var strap_length := 0.0

var _jacks: Array[Node3D] = []


## How wide a mult gathering `ways` sources will be. Known before the node is built, because
## the bay has to pack a row of these and packing needs widths first.
static func width_for(ways: int) -> float:
	return (ways + 1) * WAY_PITCH + PAD


static func create(dest_name: String, ways: int, bank: MeshBank = null) -> PatchMult:
	var m := PatchMult.new()
	m.name = "Mult_%s" % dest_name
	m._ways = maxi(1, ways)
	m._dest_name = dest_name
	m._socket_bank = bank
	return m


var _ways := 1
var _dest_name := ""
var _socket_bank: MeshBank


func _ready() -> void:
	var total := width_for(_ways)

	var block := MeshInstance3D.new()
	var block_mesh := BoxMesh.new()
	block_mesh.size = Vector3(total, HEIGHT, DEPTH)
	block.mesh = block_mesh
	block.position = Vector3(0, 0, -DEPTH * 0.5)
	block.material_override = Materials.chassis()
	add_child(block)

	# The painted bar that says these holes are the same hole. Without it a mult is just a row
	# of jacks, which is exactly what the rest of the bay is, and the one thing a viewer has to
	# understand here is that these are bussed.
	var bus := MeshInstance3D.new()
	var bus_mesh := BoxMesh.new()
	bus_mesh.size = Vector3(_ways * WAY_PITCH, 0.0014, 0.001)
	bus.mesh = bus_mesh
	bus.position = Vector3(0, HEIGHT * 0.5 - 0.026, 0.0006)
	bus.material_override = Materials.cap_plastic(Color(0.62, 0.52, 0.30))
	add_child(bus)

	# Jacks sit on a row: the trunk first, then one per source. Order matters only for reading
	# -- the trunk at the left end is where the eye starts, and it is the one cable that leaves.
	var first_x := -total * 0.5 + PAD * 0.5 + WAY_PITCH * 0.5
	for i in _ways + 1:
		var holder := Node3D.new()
		holder.position = Vector3(first_x + i * WAY_PITCH, HEIGHT * 0.5 - 0.013, 0.002)
		add_child(holder)
		_jacks.append(holder)
		_seat_socket(holder, i)

	# Hung off the bay rather than floating under it. Two straps is what a small box bolted to
	# the underside of a bridge actually has, and without them the mult reads as a UI panel
	# that happens to be in the scene -- which is the one thing everything here is not.
	if strap_length > 0.0:
		for side in [-1.0, 1.0]:
			var strap := MeshInstance3D.new()
			var strap_mesh := BoxMesh.new()
			strap_mesh.size = Vector3(0.006, strap_length, 0.004)
			strap.mesh = strap_mesh
			strap.position = Vector3(
					side * (total * 0.5 - 0.008),
					HEIGHT * 0.5 + strap_length * 0.5,
					-0.004)
			strap.material_override = Materials.brushed_metal()
			add_child(strap)

	var caption := Label3D.new()
	caption.font_size = 30
	caption.pixel_size = 0.00017
	caption.text = ("MULT -> %s" % _dest_name).to_upper()
	caption.position = Vector3(0, -HEIGHT * 0.5 + 0.007, 0.002)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.modulate = Color(0.68, 0.60, 0.46)
	caption.outline_size = 0
	Lettering.range_to_legibility(caption)
	add_child(caption)


## Where a cable plugs in. `way` 0 is the trunk that runs to the destination; 1..n are the
## sources. Global, because that is what PatchCable takes.
func jack_transform(way: int) -> Transform3D:
	if _jacks.is_empty():
		return global_transform
	return _jacks[clampi(way, 0, _jacks.size() - 1)].global_transform


func trunk_transform() -> Transform3D:
	return jack_transform(0)


func _seat_socket(holder: Node3D, i: int) -> void:
	# Clocked off the index for the reason PatchPoint.nut_angle exists: a row of hex nuts all
	# pointing the same way reads as a texture.
	var spin := Node3D.new()
	spin.rotation_degrees = Vector3(0, 0, fposmod(float(i * 29 + 11), 60.0))
	holder.add_child(spin)
	if _socket_bank != null:
		var at := Node3D.new()
		at.rotation_degrees = Vector3(90, 0, 0)
		spin.add_child(at)
		_socket_bank.place(at, Color.WHITE)
		at.queue_free()
		spin.queue_free()
		return
	var socket := Part.build(
		PatchPoint.MESH_PATH,
		Materials.brushed_metal(),
		{"bore": Materials.recess()},
	)
	if socket != null:
		socket.rotation_degrees = Vector3(90, 0, 0)
		spin.add_child(socket)
	else:
		spin.queue_free()
