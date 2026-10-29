class_name ModularJack
extends ControlAffordance

## One jack on the modular wall (ModularWall, docs/spatial_loop.md part two, slice 51): the
## jack socket a patch cable plugs into (PatchCable.JACK_MESH), lettered with its name over it, an output's on a pale
## plate and an input's bare, so which way it goes is a shape and a shade before it is a word.
##
## Dragging is the whole gesture, with a mouse and with a hand alike: press on a
## jack and a cable comes out of it and follows you, the jacks it could go into light up, and letting
## go over one patches it. An input with a cable in it gives up that cable's plug instead, to carry to
## another input or off the wall to pull it. The wall does the patching; a jack only says where the
## drag went.

signal drag_began(from: ModularJack, at: Vector3)
signal drag_moved(from: ModularJack, at: Vector3, over: ControlAffordance)
signal drag_finished(from: ModularJack, over: ControlAffordance)

## Where to aim: the socket and its letters, so a 1 cm hole is not a test of the mouse.
const SIZE := Vector2(0.046, 0.062)
const RADIUS := 0.0062
## How far in front of the panel the socket's face is, where a plug seats.
const FACE_Z := 0.006

enum Light { PLAIN, CANDIDATE, TARGET }

## Its id (Modular.OUTS or INS: `vcf.cv`) and whether it is an output.
var jack := &""
var output := false
## What the wall says it carries: for its card. Set by the wall as the patch changes.
var plugged_to: Array[StringName] = []

var _ring_material := StandardMaterial3D.new()
var _ring: MeshInstance3D
var _light := Light.PLAIN


static func create(id: StringName) -> ModularJack:
	var j := ModularJack.new()
	j.jack = id
	j.output = Modular.OUTS.has(id)
	j.name = "Jack_%s" % String(id).replace(".", "_")
	return j


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	if output:
		# An output's pale plate: what is sent from, as a shape you can see across the room.
		var plate := MeshInstance3D.new()
		plate.name = "Plate"
		var quad := QuadMesh.new()
		quad.size = Vector2(SIZE.x - 0.008, SIZE.y - 0.006)
		plate.mesh = quad
		plate.position = Vector3(0, 0.004, 0.0006)
		var pale := StandardMaterial3D.new()
		pale.albedo_color = Color(0.78, 0.76, 0.7)
		pale.roughness = 0.7
		plate.material_override = pale
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(plate)
	var socket := Part.build(PatchCable.JACK_MESH, Materials.brushed_metal(), {"bore": Materials.recess()})
	var holder := Node3D.new()
	holder.position = Vector3(0, -0.008, 0.001)
	add_child(holder)
	if socket != null:
		socket.rotation_degrees = Vector3(90, 0, 0)
		socket.scale = Vector3.ONE * (RADIUS / PatchCable.JACK_RADIUS)
		holder.add_child(socket)
	# The ring round the socket that lights while a cable could go here.
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS * 1.25
	torus.outer_radius = RADIUS * 1.6
	_ring.mesh = torus
	_ring.rotation_degrees = Vector3(90, 0, 0)
	_ring.position = Vector3(0, -0.008, 0.002)
	_ring_material.roughness = 0.5
	_ring.material_override = _ring_material
	add_child(_ring)
	_set_light(Light.PLAIN)
	var words := Label3D.new()
	words.name = "Name"
	var short := String(jack).get_slice(".", 1).to_upper()
	words.text = short
	words.pixel_size = 0.0002
	words.font_size = roundi(0.0105 / words.pixel_size)
	words.modulate = Color(0.12, 0.11, 0.1) if output else Color(0.9, 0.88, 0.82)
	words.position = Vector3(0, 0.016, 0.0012)
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.double_sided = false
	Lettering.range_to_legibility(words)
	add_child(words)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x, SIZE.y, 0.02)
	shape.shape = box
	shape.position = Vector3(0, 0, 0.01)
	add_child(shape)


## Where a plug in this jack sits, in world space, facing out of the panel.
func plug_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.008, FACE_Z))


func set_light(how: int) -> void:
	if how != _light:
		_set_light(how)


func light() -> int:
	return _light


## Plain, a dull ring; somewhere the carried cable could go, a brighter ring grown a little; where it
## goes if let go now, bright and grown more. Brightness and size, not colour alone.
func _set_light(how: int) -> void:
	_light = how
	_ring_material.emission_enabled = how != Light.PLAIN
	match how:
		Light.PLAIN:
			_ring_material.albedo_color = Color(0.2, 0.2, 0.21)
			if _ring != null:
				_ring.scale = Vector3.ONE
		Light.CANDIDATE:
			_ring_material.albedo_color = Color(0.85, 0.8, 0.6)
			_ring_material.emission = Color(0.5, 0.45, 0.3)
			if _ring != null:
				_ring.scale = Vector3.ONE * 1.2
		Light.TARGET:
			_ring_material.albedo_color = Color(1.0, 0.95, 0.75)
			_ring_material.emission = Color(1.2, 1.1, 0.7)
			if _ring != null:
				_ring.scale = Vector3.ONE * 1.45


func _on_grab_begin(at: Vector3) -> void:
	drag_began.emit(self, at)


func _on_grab_move(at: Vector3) -> void:
	drag_moved.emit(self, at, _under_hand())


func _on_grab_end() -> void:
	drag_finished.emit(self, _under_hand())


func _under_hand() -> ControlAffordance:
	if held_by is Interactor:
		return (held_by as Interactor).hovered
	return null


func _foley_contact() -> AudioStream:
	return Foley.plug_seat()


func _default_title() -> String:
	return "MODULAR  %s" % Modular.jack_title(jack)


func _default_readout() -> String:
	if plugged_to.is_empty():
		return "not patched"
	var names := plugged_to.map(func(j: StringName) -> String: return Modular.jack_title(j))
	return ("to %s" if output else "from %s") % ", ".join(names)


func hint() -> String:
	if output:
		return "drag to an input to patch a cable · an output feeds as many as you like"
	if plugged_to.is_empty():
		return "drag to an output to patch a cable into it"
	return "drag its plug to another input, or off the jacks to pull it out"
