class_name SendSocket
extends ControlAffordance

## A quarter-inch SEND socket on the master section: where a personal mix takes its sound from
## (PersonalMix). Somebody drags a wireless plug off their tablet and drops it here, and the
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

var _ring: MeshInstance3D
var _plugs: Array[Node3D] = []
var _colours: Array[Color] = []
static var _plug_scene: PackedScene


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	# The nut round the hole, the hole, and a thin ring of light that says a plug is in.
	var nut := MeshInstance3D.new()
	var nut_mesh := CylinderMesh.new()
	nut_mesh.top_radius = RADIUS
	nut_mesh.bottom_radius = RADIUS
	nut_mesh.height = 0.003
	nut_mesh.radial_segments = 24
	nut.mesh = nut_mesh
	nut.rotation.x = PI * 0.5
	nut.position.z = 0.0015
	nut.material_override = Materials.brushed_metal()
	add_child(nut)
	var hole := MeshInstance3D.new()
	var hole_mesh := CylinderMesh.new()
	hole_mesh.top_radius = RADIUS * 0.52
	hole_mesh.bottom_radius = RADIUS * 0.52
	hole_mesh.height = 0.001
	hole_mesh.radial_segments = 20
	hole.mesh = hole_mesh
	hole.rotation.x = PI * 0.5
	hole.position.z = 0.0031
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.015, 0.015, 0.018)
	black.roughness = 0.9
	hole.material_override = black
	add_child(hole)
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
	add_child(_ring)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = HIT
	shape.shape = box
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
	if _ring == null:
		return
	_ring.material_override = Materials.led(LAMP, not _colours.is_empty())
	for plug in _plugs:
		plug.queue_free()
	_plugs.clear()
	for i in mini(_colours.size(), MOST_SHOWN):
		var plug := make_plug(_colours[i])
		plug.position = Vector3(0, 0, 0.003 + STACK * i)
		add_child(plug)
		_plugs.append(plug)
