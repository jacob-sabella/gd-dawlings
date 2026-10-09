class_name SendSocket
extends ControlAffordance

## A quarter-inch SEND socket, on the master section or a channel strip: where a personal mix
## takes its sound from (PersonalMix). Somebody drags a wireless plug off their tablet and drops it here, and the
## receiver it pairs with on their tablet hears what this socket carries.
##
## The plugs are seen by everyone, each lit in its owner's colour, stacked one into the back of
## the next the way stackable patch plugs are: at a glance, who is listening to this. Nothing
## here reaches the DAW. A click is all it reports (`pressed`); what a click means -- pull my
## plug out, or "bring a plug from your tablet" -- is the studio's to decide.

signal pressed()

const RADIUS := 0.0062
## What a click lands on: bigger than the socket, which is small and a long way from the seat.
const HIT := Vector3(0.026, 0.02, 0.012)
## On a channel strip, narrower: it sits beside the buttons, and must not take their clicks.
const STRIP_HIT := Vector3(0.015, 0.017, 0.012)
## Amber, the desk's colour for "something is patched here" rather than a state of the mix.
const LAMP := Color(0.95, 0.62, 0.22)
const PLUG_MODEL := "res://assets/models/wireless_plug.glb"
## From one plug's shoulder to the next one's, stacked (tools/blender/tablet.py's PLUG_BODY, and
## the back socket's lip).
const STACK := 0.0372
## More than this many are drawn as this many: past it a stack is a pole, not a read.
const MOST_SHOWN := 4

## Which socket this is, by its source's name (PersonalMix.SOURCES).
var source: StringName = &""
## What it is called on the panel and on its hover card.
var label := ""
## What a click lands on.
var hit := HIT
## Where the nut and bore are drawn, when a desk gives it somewhere: a strip's worth of sockets
## is one draw a surface rather than one each. Built loose without it.
var face_bank: MeshBank

var _ring: MeshInstance3D
var _plugs: Array[Node3D] = []
var _colours: Array[Color] = []
static var _plug_scene: PackedScene
static var _face_mesh: ArrayMesh


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	# The nut round the bore, and the bore.
	if face_bank != null:
		face_bank.place(self, Color.WHITE)
	else:
		var face := MeshInstance3D.new()
		face.mesh = face_mesh()
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(face)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = hit
	shape.shape = box
	# Standing out of the panel, where a plug does: in front of the buttons beside it, which a
	# strip seen from an angle would otherwise put over it.
	shape.position.z = hit.z * 0.5
	add_child(shape)
	_refresh()


## The plugs in it, by their owners' colours, first in nearest the panel.
func set_plugs(colours: Array[Color]) -> void:
	if colours == _colours:
		return
	_colours = colours.duplicate()
	_refresh()


func plug_count() -> int:
	return _colours.size()


## Where a plug sits in it, in the world: its shoulder on the nut, its body out along +Z.
func plug_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.003))


func personal() -> bool:
	return true


func title() -> String:
	return "SEND  " + label


func readout() -> String:
	match _colours.size():
		0: return "nothing plugged in"
		1: return "1 plug"
	return "%d plugs" % _colours.size()


func hint() -> String:
	return "drag a plug here from your tablet · click to pull yours out"


func _on_grab_begin(_at: Vector3) -> void:
	pressed.emit()


## Silent: the plug makes the noise, when there is one.
func _foley_contact() -> AudioStream:
	return null


## The nut and the bore, one mesh of two surfaces, made once: its face looks along +Z.
static func face_mesh() -> ArrayMesh:
	if _face_mesh != null:
		return _face_mesh
	_face_mesh = ArrayMesh.new()
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.015, 0.015, 0.018)
	black.roughness = 0.9
	# A dark satin nut, not bright nickel: a desk's worth in a row read as a row of white rings,
	# louder than the lamps.
	var nut := StandardMaterial3D.new()
	nut.albedo_color = Color(0.2, 0.205, 0.215)
	nut.metallic = 0.7
	nut.roughness = 0.5
	for spec in [[RADIUS, 0.003, 0.0015, 24, nut], [RADIUS * 0.52, 0.001, 0.0031, 20, black]]:
		var c := CylinderMesh.new()
		c.top_radius = spec[0]
		c.bottom_radius = spec[0]
		c.height = spec[1]
		c.radial_segments = spec[3]
		c.rings = 1
		var arrays := c.get_mesh_arrays()
		var to := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, spec[2]))
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			verts[i] = to * verts[i]
			normals[i] = to.basis * normals[i]
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		_face_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_face_mesh.surface_set_material(_face_mesh.get_surface_count() - 1, spec[4])
	return _face_mesh


## A plug for the stack, lit `colour`.
static func make_plug(colour: Color) -> Node3D:
	if _plug_scene == null:
		_plug_scene = load(PLUG_MODEL) as PackedScene
	var plug := _plug_scene.instantiate() as Node3D
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.07, 0.07, 0.08)
	body.roughness = 0.45
	var socket := StandardMaterial3D.new()
	socket.albedo_color = Color(0.01, 0.01, 0.012)
	var swap := {"body": body, "metal": Materials.brushed_metal(), "led": Materials.led(colour, true),
			"socket": socket}
	for mesh: MeshInstance3D in plug.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return plug


func _refresh() -> void:
	if not is_inside_tree():
		return
	# A thin ring of light round the nut that says a plug is in: made the first time one is, so a
	# desk of empty sockets carries none.
	if _ring == null and not _colours.is_empty():
		_ring = MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = RADIUS * 1.08
		ring_mesh.outer_radius = RADIUS * 1.32
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 6
		_ring.mesh = ring_mesh
		_ring.rotation.x = PI * 0.5
		_ring.position.z = 0.0008
		_ring.scale = Vector3(1, 0.25, 1)
		_ring.material_override = Materials.led(LAMP, true)
		add_child(_ring)
	if _ring != null:
		_ring.visible = not _colours.is_empty()
	for plug in _plugs:
		plug.queue_free()
	_plugs.clear()
	for i in mini(_colours.size(), MOST_SHOWN):
		var plug := make_plug(_colours[i])
		plug.position = Vector3(0, 0, 0.003 + STACK * i)
		add_child(plug)
		_plugs.append(plug)
