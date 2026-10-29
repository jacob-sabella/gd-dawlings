class_name TestDrumItem
extends InstrumentItem

## A drum that stands still, for the suite and the session probe only (docs/spatial_loop.md part two,
## slice 38): never in ItemRoom.KINDS, so never in a player's room. It proves fixed instruments
## (`Item.fixed`, Strike) before the first ones a player meets, slice 40's hand drums, stand on them.
##
## A plain drum on the floor: a round head of radius HEAD_RADIUS, HEIGHT up, facing up. Where the head
## is struck is its zone, as slice 40's drums will have it: bass inside BASS_WITHIN of the radius,
## slap past SLAP_PAST, tone between. Each zone rings a Foley sound of its own and is recorded as a
## General MIDI conga stroke.

const HEIGHT := 0.62
const HEAD_RADIUS := 0.15
const BASS_WITHIN := 0.35
const SLAP_PAST := 0.8
const ZONES: Array[StringName] = [&"bass", &"tone", &"slap"]
## Foley's sound and the General MIDI note of each zone: low conga, open high conga, muted high conga.
const KINDS := {&"bass": &"conga", &"tone": &"bongo", &"slap": &"rim"}
const NOTES := {&"bass": 64, &"tone": 63, &"slap": 62}
const SHELL := Color(0.46, 0.27, 0.13)
const SKIN := Color(0.86, 0.8, 0.66)


func _init() -> void:
	id = &"testdrum"
	fixed = true
	own_home = true
	super()
	_shape.position.y = HEIGHT * 0.5


func item_title() -> String:
	return "TEST DRUM"


func pitch() -> int:
	return NOTES[&"tone"]


func sound_kind(_struck: bool) -> StringName:
	return KINDS[&"tone"]


func faces() -> Array:
	return [{"frame": global_transform * Transform3D(Basis.IDENTITY, Vector3.UP * HEIGHT),
			"radius": HEAD_RADIUS}]


## Bass at the centre, slap at the rim, tone between: by how far from the head's middle `point`
## is, across the head, whatever its height (a click on the shell's side is at the rim).
func zone_at(point: Vector3) -> StringName:
	var local := global_transform.affine_inverse() * point
	var out := Vector2(local.x, local.z).length() / HEAD_RADIUS
	if out < BASS_WITHIN:
		return &"bass"
	if out > SLAP_PAST:
		return &"slap"
	return &"tone"


func zone_words() -> String:
	return "centre bass · between tone · rim slap"


func zone_kind(zone: StringName) -> StringName:
	return KINDS.get(zone, &"")


func zone_note(zone: StringName, seconds: float) -> int:
	return NOTES.get(zone, note_at(seconds))


func has_zone(zone: StringName) -> bool:
	return zone == &"" or zone in ZONES


func centre_height() -> float:
	return HEIGHT * 0.5


func _grip_shape() -> Shape3D:
	var s := CylinderShape3D.new()
	s.radius = HEAD_RADIUS + 0.01
	s.height = HEIGHT
	return s


func _build_body() -> Node3D:
	var root := Node3D.new()
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	var tube := CylinderMesh.new()
	tube.top_radius = HEAD_RADIUS
	tube.bottom_radius = HEAD_RADIUS * 0.7
	tube.height = HEIGHT - 0.01
	shell.mesh = tube
	shell.position.y = (HEIGHT - 0.01) * 0.5
	var wood := StandardMaterial3D.new()
	wood.albedo_color = SHELL
	wood.roughness = 0.6
	shell.set_surface_override_material(0, wood)
	root.add_child(shell)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var skin := CylinderMesh.new()
	skin.top_radius = HEAD_RADIUS
	skin.bottom_radius = HEAD_RADIUS
	skin.height = 0.01
	head.mesh = skin
	head.position.y = HEIGHT - 0.005
	var hide := StandardMaterial3D.new()
	hide.albedo_color = SKIN
	hide.roughness = 0.8
	head.set_surface_override_material(0, hide)
	root.add_child(head)
	return root
