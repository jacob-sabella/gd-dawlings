class_name ClavesItem
extends InstrumentItem

## A pair of claves: struck together, or swung onto a beater -- a stroke-stop plays it exactly
## like a click (InstrumentItem.feel). Recorded as the General MIDI claves, 75, or its low voice,
## the vibraslap, 58 -- a Tour spill's second copy (`voice`), named "LOW CLAVES" the same way
## cowbell's own second voice is a different instrument ("low agogo") wearing the kind's name.

const MODEL := "res://assets/models/claves.glb"
## tools/blender/spill_percussion.py's two parallel sticks: its own origin is its vertical
## middle, the same convention as the cowbell, the pad and the triangle.
const HEIGHT := 0.0288
const WOOD := Color(0.5, 0.32, 0.16)
const PITCHES := [75, 58]


func _init() -> void:
	id = &"claves"
	super()
	_shape.position.y = HEIGHT * 0.5


func item_title() -> String:
	return ("LOW " if voice > 0 else "") + "CLAVES"


func hint() -> String:
	return _hint("click to pick up, then shake or strike it")


func pitch() -> int:
	return PITCHES[mini(voice, 1)]


func sound(_struck: bool, take: int) -> AudioStream:
	return Foley.claves(take)


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.position.y = HEIGHT * 0.5
	root.add_child(model)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = WOOD
	wood.roughness = 0.55
	var swap := {"wood": wood}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return root


func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.27, 0.03, 0.1)
	return s


func centre_height() -> float:
	return HEIGHT * 0.5


## Held flat across the palm, both sticks pointing out where a strike lands -- the same
## held-across gesture as the woodblock's, flattened for a pair that lies this thin.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.FORWARD, 0.4) * Basis(Vector3.UP, 0.3), Vector3(0.02, -0.03, 0))


func flies() -> Dictionary:
	return {"bounce": 0.25, "roll": 2.8, "drag": 0.06}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.claves(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -18.0, 0.0), pitch_scale())


func _foley_contact() -> AudioStream:
	return Foley.rubber_tap()
