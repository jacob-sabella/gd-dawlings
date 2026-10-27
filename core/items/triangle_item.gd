class_name TriangleItem
extends InstrumentItem

## A triangle: struck with a beater, or swung onto one -- a stroke-stop plays it exactly like a
## click (InstrumentItem.feel). Recorded as the General MIDI open triangle, 81, or its low voice,
## the muted triangle, 80 -- a Tour spill's second copy (`voice`).

const MODEL := "res://assets/models/triangle.glb"
## tools/blender/spill_percussion.py's rod triangle: its own origin is its vertical middle, the
## same convention as the cowbell and the pad.
const HEIGHT := 0.16
const ROD := Color(0.8, 0.81, 0.83)
const PITCHES := [81, 80]


func _init() -> void:
	id = &"triangle"
	super()
	_shape.position.y = HEIGHT * 0.5


func item_title() -> String:
	return ("MUTED " if voice > 0 else "") + "TRIANGLE"


func hint() -> String:
	return _hint("click to pick up, then shake or strike it")


func pitch() -> int:
	return PITCHES[mini(voice, 1)]


func sound_kind(_struck: bool) -> StringName:
	return &"triangle"


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.position.y = HEIGHT * 0.5
	root.add_child(model)
	var rod := StandardMaterial3D.new()
	rod.albedo_color = ROD
	rod.metallic = 0.85
	rod.roughness = 0.25
	var swap := {"rod": rod}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return root


func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.15, 0.18, 0.02)
	return s


func centre_height() -> float:
	return HEIGHT * 0.5


## Hung edge-on toward you, the open corner down where a beater can reach it -- the same gesture
## as the cowbell's held pose, turned so the gap faces out.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -0.3) * Basis(Vector3.UP, 0.25), Vector3(0.02, -0.07, 0))


func flies() -> Dictionary:
	return {"bounce": 0.22, "roll": 3.5, "drag": 0.06}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.triangle(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -18.0, 0.0), pitch_scale())


func _foley_contact() -> AudioStream:
	return Foley.gear_bump()
