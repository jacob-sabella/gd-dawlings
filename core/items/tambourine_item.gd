class_name TambourineItem
extends InstrumentItem

## A tambourine: shake it for the jingles, click to strike the head (InstrumentItem). Recorded
## as the General MIDI tambourine, note 54.

const MODEL := "res://assets/models/tambourine.glb"
## Half the hoop's depth (tools/blender/percussion.py): lying flat, its middle is this high.
const HALF_DEPTH := 0.025
const RADIUS := 0.125
const HOOP := Color(0.55, 0.13, 0.09)
## A natural skin, tan rather than white: it lies under the shelf's lamp, and white there is a
## glare.
const HEAD := Color(0.6, 0.52, 0.38)
## Bright nickel, so the jingles catch the light the way they do and are not dark lumps in the slots.
const JINGLE := Color(0.88, 0.85, 0.78)

var _jingles: Node3D
## How far the jingles are swinging after a hit, and their swing's phase.
var _shimmer := 0.0
var _shimmer_t := 0.0


func _init() -> void:
	id = &"tambourine"
	super()
	_shape.position.y = HALF_DEPTH


func item_title() -> String:
	return "TAMBOURINE"


func hint() -> String:
	return _hint("click to pick up, then shake the mouse to play it, click to strike it")


func pitch() -> int:
	return 54


func sound(struck: bool, take: int) -> AudioStream:
	return Foley.tambourine_hit(take) if struck else Foley.jingle(take)


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.position.y = HALF_DEPTH
	root.add_child(model)
	var hoop := StandardMaterial3D.new()
	hoop.albedo_color = HOOP
	hoop.roughness = 0.35
	var head := StandardMaterial3D.new()
	head.albedo_color = HEAD
	head.roughness = 0.85
	var jingle := StandardMaterial3D.new()
	jingle.albedo_color = JINGLE
	jingle.metallic = 0.9
	jingle.roughness = 0.22
	var swap := {"hoop": hoop, "head": head, "jingle": jingle}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	_jingles = model.find_child("Jingles", true, false) as Node3D
	return root


func _grip_shape() -> Shape3D:
	var s := CylinderShape3D.new()
	s.radius = RADIUS + 0.01
	s.height = 0.07
	return s


func centre_height() -> float:
	return HALF_DEPTH


## Held by the bare stretch of hoop with no jingles, the rest of it out in front, nearly flat and
## turned a little across: the head seen at a slant, the jingles along its rim. Held up face on,
## it is a disc that hides half the desk.
func held_pose() -> Transform3D:
	var turn := Basis(Vector3.UP, 0.4) * Basis(Vector3.FORWARD, 0.3) * Basis(Vector3.RIGHT, 0.2)
	return Transform3D(turn, turn * Vector3(0, -HALF_DEPTH, -RADIUS + 0.01))


func flies() -> Dictionary:
	return {"bounce": 0.25, "roll": 4.0, "drag": 0.1}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.jingle(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -16.0, 0.0))


func _foley_contact() -> AudioStream:
	return Foley.gear_bump()


func _jiggle(velocity: int) -> void:
	super(velocity)
	_shimmer = maxf(_shimmer, 0.05 + 0.1 * velocity / 127.0)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	super(delta)
	if _jingles == null or _shimmer <= 0.0:
		return
	# The jingles rattle on their pins and settle.
	_shimmer_t += delta
	_shimmer *= exp(-delta / 0.12)
	if _shimmer < 0.002:
		_shimmer = 0.0
	_jingles.rotation.y = sin(_shimmer_t * 70.0) * _shimmer * 0.15
