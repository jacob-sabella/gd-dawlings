class_name HeadphonesItem
extends Item

## A pair of closed-back studio headphones (docs/items_loop.md). Picked up, a click puts them on
## (`Interactor.wear`); on a head they are seen on that person's ghost, and the hand is free
## again. While they are on, the wearer hears their personal mix with the room muffled (Ears).
## No cord: what is in them is the personal mixer's to say, not a socket's.
##
## Whether they are on is part of how they are held, and the room carries it (`Item.set_worn`,
## ItemRoom.state), so everyone sees them on the wearer's ghost.
##
## The model's cups swivel: flat on the shelf, as headphones are laid down, and square to the
## head in a hand or on one.

const MODEL := "res://assets/models/headphones.glb"
const SHELL := Color(0.075, 0.075, 0.085)
const PAD := Color(0.12, 0.115, 0.12)
## A copper ring round each cup: a little warmth on a black thing.
const ACCENT := Color(0.78, 0.48, 0.26)
## The band drawn down to sit on a ghost's dome, which is broader than a head is tall.
const BAND_ON_HEAD := 0.68
## How far the inside of the band's top is above the model's origin, between the cups: what
## rests on a hook.
const HANG := 0.205
## How quickly the cups swivel between flat and square, per second.
const SWIVEL_RATE := 9.0
var _model: Node3D
var _band: Node3D
var _cups: Array[Node3D] = []
var _cup_rest: Array[Transform3D] = []
## 1 lying flat, 0 square: how far through the swivel the cups are.
var _flat := 1.0
## The model lying flat on the shelf: turned onto its back and set down on its lowest point.
var _lying := Transform3D.IDENTITY


func _init() -> void:
	id = &"headphones"
	super()
	state_changed.connect(func(_s: State) -> void: set_process(true))


func item_title() -> String:
	return "HEADPHONES"


func hint() -> String:
	if in_hand():
		return "click to put them on (H)"
	return _hint("click to pick up")


func wearable() -> bool:
	return true


func _build_body() -> Node3D:
	var root := Node3D.new()
	_model = (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(_model)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = SHELL
	shell.roughness = 0.5
	var pad := StandardMaterial3D.new()
	pad.albedo_color = PAD
	pad.roughness = 0.85
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.63, 0.65)
	metal.metallic = 0.85
	metal.roughness = 0.3
	var accent := StandardMaterial3D.new()
	accent.albedo_color = ACCENT
	accent.metallic = 0.8
	accent.roughness = 0.35
	var swap := {"shell": shell, "pad": pad, "metal": metal, "accent": accent}
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	_band = _model.find_child("Band", true, false) as Node3D
	for cup_name in ["CupL", "CupR"]:
		var cup := _model.find_child(cup_name, true, false) as Node3D
		_cups.append(cup)
		_cup_rest.append(cup.transform)
	_lying = _lie_flat()
	_pose_model()
	return root


## Where the model goes to lie on its back with its cups flat: worked out once from its own
## shape, so a remodel needs no new numbers here.
func _lie_flat() -> Transform3D:
	_flat = 1.0
	_swivel_cups()
	var turn := Basis(Vector3.RIGHT, PI * 0.5)
	var low := Vector3.INF
	var high := -Vector3.INF
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var box := Transform3D(turn) * _in_model(mesh) * mesh.get_aabb()
		low = low.min(box.position)
		high = high.max(box.end)
	var middle := (low + high) * 0.5
	return Transform3D(turn, Vector3(-middle.x, -low.y, -middle.z))


## `node`'s transform in the model's frame, out of the tree.
func _in_model(node: Node3D) -> Transform3D:
	var at := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != _model:
		if n is Node3D:
			at = (n as Node3D).transform * at
		n = n.get_parent()
	return at


func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.28, 0.12, 0.26)
	return s


func centre_height() -> float:
	return 0.03


## Held by the band, edge on, cups hanging: the way a pair is carried to be put on, and narrow
## enough not to fill the view on the way.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, 1.25) * Basis(Vector3.RIGHT, 0.15), Vector3(0.0, -0.09, 0.03))


## Soft and floppy: they land and stay.
func flies() -> Dictionary:
	return {"bounce": 0.12, "roll": 6.0, "drag": 0.1}


## A click with them in your hand: on they go.
func use(down: bool) -> void:
	if down and in_hand():
		carried_by.wear()


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.gear_bump(), clampf(linear_to_db(speed / 4.0), -24.0, -6.0), 0.8)


func _foley_contact() -> AudioStream:
	return Foley.gear_bump()


func _ready() -> void:
	super()
	set_process(true)


func _process(delta: float) -> void:
	# Flat on the floor, and on a shelf; hung by the band on a hook of their own, square.
	var flat_wanted := 0.0 if state == State.HELD or (state == State.HOME and own_home) else 1.0
	_flat = move_toward(_flat, flat_wanted, delta * SWIVEL_RATE * 0.5)
	_pose_model()
	if is_equal_approx(_flat, flat_wanted):
		set_process(false)


func _pose_model() -> void:
	_swivel_cups()
	_model.transform = Transform3D.IDENTITY.interpolate_with(_lying, _flat)
	if _band != null:
		_band.scale.y = BAND_ON_HEAD if on_head else 1.0


func _swivel_cups() -> void:
	for i in _cups.size():
		var side := -1.0 if i == 0 else 1.0
		# Each turns its pad toward the front, then the whole lies back: pads up, on the shelf.
		_cups[i].transform = _cup_rest[i] * Transform3D(Basis(Vector3.UP, -side * PI * 0.5 * smoothstep(0.0, 1.0, _flat)), Vector3.ZERO)
