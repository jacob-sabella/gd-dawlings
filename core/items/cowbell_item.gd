class_name CowbellItem
extends InstrumentItem

## A cowbell: struck with a beater, or swung onto one -- a stroke-stop plays it exactly like a
## click (InstrumentItem.feel). Recorded as the General MIDI cowbell, 56, or its low voice, the
## low agogo, 68 -- a Tour spill's second copy (`voice`).

const MODEL := "res://assets/models/cowbell.glb"
## tools/blender/spill_percussion.py's cone, flattened: lying mouth-down, its middle is this high.
const HEIGHT := 0.14
const BELL := Color(0.16, 0.14, 0.11)
const HANDLE := Color(0.62, 0.59, 0.54)
const PITCHES := [56, 68]


func _init() -> void:
	id = &"cowbell"
	super()
	_shape.position.y = HEIGHT * 0.5


func item_title() -> String:
	return ("LOW " if voice > 0 else "") + "COWBELL"


func hint() -> String:
	return _hint("click to pick up, then shake or strike it")


func pitch() -> int:
	return PITCHES[mini(voice, 1)]


func sound(_struck: bool, take: int) -> AudioStream:
	return Foley.cowbell(take)


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.position.y = HEIGHT * 0.5
	root.add_child(model)
	var bell := StandardMaterial3D.new()
	bell.albedo_color = BELL
	bell.metallic = 0.55
	bell.roughness = 0.45
	var handle := StandardMaterial3D.new()
	handle.albedo_color = HANDLE
	handle.metallic = 0.7
	handle.roughness = 0.35
	var swap := {"bell": bell, "handle": handle}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return root


func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.13, 0.16, 0.09)
	return s


func centre_height() -> float:
	return 0.07


## Mouth tipped toward you, slightly across, the way a hand-held cowbell is carried ready to
## strike -- the same gesture as a shaker's held pose, turned the other way about.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -0.35) * Basis(Vector3.UP, 0.3), Vector3(0.02, -0.08, 0))


func flies() -> Dictionary:
	return {"bounce": 0.2, "roll": 3.0, "drag": 0.08}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.cowbell(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -18.0, 0.0), pitch_scale())


func _foley_contact() -> AudioStream:
	return Foley.gear_bump()
