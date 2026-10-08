class_name PatchPoint
extends ControlAffordance

## One track's row on the bay: its outputs in the FROM column, or its inputs in the TO column.
##
## A row, not a jack, is what you aim at. The row is a colour chip, the track's name in big
## letters, and a short strip of jacks; any of it can be grabbed to start a cable, and any of it
## is somewhere to drop one. Aiming a cable at an 18mm hole across a room is a test of the mouse,
## not of the routing, and which jack it lands in is the bay's business: always the row's free one.
##
## Dragging is the whole gesture, with a mouse and with a hand alike: press on a row, a cable
## comes out of its free jack and follows you, the rows it could go to light up, and letting go
## over one of them patches it. Let go anywhere else and the cable goes back. The bay does the
## patching (PatchbaySurface); a row only says where the drag went.

signal drag_began(from: ControlAffordance, at: Vector3)
signal drag_moved(from: ControlAffordance, at: Vector3, over: ControlAffordance)
signal drag_finished(from: ControlAffordance, over: ControlAffordance)

const Kind := {OUTPUT = 0, INPUT = 1}

const RADIUS := 0.009
const MESH_PATH := "res://assets/hardware/jack.glb"
## How far in front of the panel a jack's face is.
const JACK_Z := 0.004

## How a row is lit: as itself, as somewhere a cable being carried could go, as the place it
## will go if you let go now, or as one end of what is under the pointer.
enum Light { PLAIN, CANDIDATE, TARGET, EMPHASIS }

var track_index: int = 0
var kind: int = Kind.OUTPUT
var label_text: String = ""
var colour := Color(0.5, 0.5, 0.5)
## The row's size on the panel, centred on this node: the column's width and the row pitch.
var size := Vector2(0.43, 0.05)
## Where each jack is across the row, in this node's own x. Index 0 is the one nearest the gap.
var jack_xs: Array[float] = []
## Every other row is a shade lighter, so a long column can be read across without a ruler.
var banded := false
## How many of this row's jacks have a plug in them.
var used := 0

## Where this row's sockets get drawn, if the bay gave it somewhere. See hardware/mesh_bank.gd.
var socket_bank: MeshBank

var _stripe_material := StandardMaterial3D.new()
var _name: Label3D
var _light: int = Light.PLAIN


static func create(track_idx: int, jack_kind: int, text: String) -> PatchPoint:
	var p := PatchPoint.new()
	p.track_index = track_idx
	p.kind = jack_kind
	p.label_text = text
	p.name = "Row_%s_%d" % ["out" if jack_kind == Kind.OUTPUT else "in", track_idx]
	return p


## How far this particular nut was done up. Nobody torques two dozen jacks to the same angle,
## and a bay where every hex points the same way reads as a texture rather than as hardware.
##
## Derived from the jack's own identity rather than randomised, so it survives a rebuild: the
## bay redraws whenever the routing changes, and nuts that reshuffled on every redraw would be a
## shimmer nobody could explain.
static func nut_angle(track_idx: int, jack_kind: int, slot: int = 0) -> float:
	# Sixty degrees is a whole turn as far as a hexagon is concerned.
	return fposmod(float(track_idx * 23 + jack_kind * 41 + slot * 17), 60.0)


## +1 for the TO column, on the right; -1 for FROM, on the left. Names sit on the outside of a
## column and jacks on the inside, facing each other across the gap the cables run through.
func outward() -> float:
	return -1.0 if kind == Kind.OUTPUT else 1.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var out := outward()

	# The band behind the row. Every row has one, because it is also what lights up when a cable
	# could go here; the banding is only its resting shade.
	var stripe := MeshInstance3D.new()
	stripe.name = "Band"
	var quad := QuadMesh.new()
	quad.size = Vector2(size.x, size.y * 0.92)
	stripe.mesh = quad
	stripe.position.z = 0.0008
	stripe.material_override = _stripe_material
	stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stripe)
	_stripe_material.roughness = 0.75
	_set_light(Light.PLAIN)

	# The track's colour as a bar at the outer edge: the first thing the eye finds, and the same
	# colour as every cable that leaves this track.
	var chip := MeshInstance3D.new()
	chip.name = "Chip"
	var bar := QuadMesh.new()
	bar.size = Vector2(0.012, size.y * 0.66)
	chip.mesh = bar
	chip.position = Vector3(out * (size.x * 0.5 - 0.014), 0, 0.0014)
	var lit := StandardMaterial3D.new()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit.albedo_color = Materials.chip_colour(colour)
	chip.material_override = lit
	add_child(chip)

	# The name, as big as the row allows, between the chip and the nearest jack. Measured in
	# "outward" terms so one sum serves both columns.
	var name_outer := size.x * 0.5 - 0.03
	var name_inner := -name_outer
	for x in jack_xs:
		name_inner = maxf(name_inner, x * out + RADIUS * 2.2)
	_name = Label3D.new()
	_name.name = "Name"
	_name.text = label_text.to_upper()
	_name.pixel_size = 0.0003
	_name.font_size = clampi(int(size.y * 0.5 / _name.pixel_size), 24, 80)
	_name.modulate = Color(0.93, 0.92, 0.88)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if out > 0.0 else HORIZONTAL_ALIGNMENT_LEFT
	_name.position = Vector3(out * name_outer, 0, 0.0016)
	Lettering.range_to_legibility(_name)
	Lettering.fit(_name, name_outer - name_inner, _name.font_size)
	add_child(_name)

	for slot in jack_xs.size():
		_socket(slot)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y * 0.96, 0.02)
	shape.shape = box
	shape.position.z = 0.01
	add_child(shape)


func _socket(slot: int) -> void:
	# Clocked through a parent rather than a third Euler angle, because spinning the part about
	# ITS axis and spinning it about the panel's are different rotations.
	var spin := Node3D.new()
	spin.position = Vector3(jack_xs[slot], 0, JACK_Z)
	spin.rotation_degrees = Vector3(0, 0, nut_angle(track_index, kind, slot))
	add_child(spin)
	if socket_bank != null:
		# Modelled axis-up; the axis here is the panel normal, which is local Z.
		var at := Node3D.new()
		at.rotation_degrees = Vector3(90, 0, 0)
		spin.add_child(at)
		socket_bank.place(at, Color.WHITE)
		spin.queue_free()
		return
	var socket := Part.build(MESH_PATH, Materials.brushed_metal(), {"bore": Materials.recess()})
	if socket != null:
		socket.rotation_degrees = Vector3(90, 0, 0)
		spin.add_child(socket)
	else:
		spin.add_child(_stand_in())


## The pre-Blender jack: a torus with a dark disc behind it. Kept because a bay whose sockets you
## cannot see is a bay you cannot aim at.
func _stand_in() -> Node3D:
	var holder := Node3D.new()
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = RADIUS * 0.62
	ring_mesh.outer_radius = RADIUS
	ring.mesh = ring_mesh
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.material_override = Materials.brushed_metal()
	holder.add_child(ring)
	var bore := MeshInstance3D.new()
	var bore_mesh := CylinderMesh.new()
	bore_mesh.top_radius = RADIUS * 0.6
	bore_mesh.bottom_radius = RADIUS * 0.6
	bore_mesh.height = 0.008
	bore.mesh = bore_mesh
	bore.rotation_degrees = Vector3(90, 0, 0)
	bore.position = Vector3(0, 0, -0.004)
	bore.material_override = Materials.recess()
	holder.add_child(bore)
	return holder


## Where a plug in jack `slot` sits, in world space, facing out of the panel.
func jack_transform(slot: int) -> Transform3D:
	var x: float = jack_xs[clampi(slot, 0, jack_xs.size() - 1)] if not jack_xs.is_empty() else 0.0
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(x, 0, JACK_Z))


## The jack a new cable goes into: the first one nothing is plugged into, or the last if every
## one is taken.
func free_slot() -> int:
	return mini(used, maxi(jack_xs.size() - 1, 0))


func light() -> int:
	return _light


func set_light(how: int) -> void:
	if how != _light:
		_set_light(how)


func _set_light(how: int) -> void:
	_light = how
	var rest := Color(0.115, 0.118, 0.13) if banded else Color(0.085, 0.087, 0.096)
	_stripe_material.emission_enabled = how != Light.PLAIN
	match how:
		Light.PLAIN:
			_stripe_material.albedo_color = rest
		Light.CANDIDATE:
			_stripe_material.albedo_color = rest.lerp(colour, 0.18)
			_stripe_material.emission = colour * 0.10
		Light.TARGET:
			_stripe_material.albedo_color = rest.lerp(colour, 0.45)
			_stripe_material.emission = colour * 0.35
		Light.EMPHASIS:
			_stripe_material.albedo_color = rest.lerp(colour, 0.25)
			_stripe_material.emission = colour * 0.12


func _on_grab_begin(at: Vector3) -> void:
	drag_began.emit(self, at)


func _on_grab_move(at: Vector3) -> void:
	drag_moved.emit(self, at, _under_hand())


func _on_grab_end() -> void:
	# held_by is still set here -- ControlAffordance clears it after this returns, which is what
	# makes reading the hand's hover possible at all.
	drag_finished.emit(self, _under_hand())


## What the hand holding this is over now, if it can say.
func _under_hand() -> ControlAffordance:
	if held_by is Interactor:
		return (held_by as Interactor).hovered
	return null


func _foley_contact() -> AudioStream:
	return Foley.plug_seat()


func _default_title() -> String:
	return "%s  %s" % [label_text.to_upper(), "OUT" if kind == Kind.OUTPUT else "IN"]


func _default_readout() -> String:
	if used == 0:
		return "not patched"
	if kind == Kind.OUTPUT:
		return "sends to %d" % used
	return "%d sending in" % used


func hint() -> String:
	if kind == Kind.OUTPUT:
		return "drag across to a TO row to send this track there"
	return "drag across to a FROM row to send that track here"
