class_name ShakerItem
extends InstrumentItem

## A tube shaker: shake it and the beads hit the end (InstrumentItem). Recorded as the General
## MIDI shaker, note 82.

const MODEL := "res://assets/models/shaker.glb"
## The tube's radius (tools/blender/percussion.py): lying down, its middle is this high.
const RADIUS := 0.0188
const WOOD := Color(0.62, 0.38, 0.19)
const CAP := Color(0.18, 0.11, 0.07)
## A painted band, so it is picked out on a shelf of dark things.
const BAND := Color(0.09, 0.45, 0.52)


func _init() -> void:
	id = &"shaker"
	super()
	_shape.position.y = RADIUS


func item_title() -> String:
	return "SHAKER"


func hint() -> String:
	return _hint("click to pick up, then shake the mouse to play it")


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.position.y = RADIUS
	root.add_child(model)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = WOOD
	wood.roughness = 0.38
	var cap := StandardMaterial3D.new()
	cap.albedo_color = CAP
	cap.roughness = 0.45
	var band := StandardMaterial3D.new()
	band.albedo_color = BAND
	band.roughness = 0.35
	var swap := {"wood": wood, "cap": cap, "band": band}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return root


## A box the length of it, a little fatter: a thin tube on a shelf is a hard thing to point at.
func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.21, 0.06, 0.06)
	return s


func centre_height() -> float:
	return RADIUS


## Held by its middle, across the view and tipped up toward the outside, as a shaker is held
## ready to play.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.FORWARD, 0.5) * Basis(Vector3.UP, 0.35), Vector3(0.02, -RADIUS, 0))


func flies() -> Dictionary:
	return {"bounce": 0.3, "roll": 2.0, "drag": 0.06}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.shaker(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -18.0, 0.0))


func _foley_contact() -> AudioStream:
	return Foley.rubber_tap()
