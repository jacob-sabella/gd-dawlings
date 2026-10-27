class_name HihatItem
extends InstrumentItem

## A pair of hi-hats, closed: struck or shaken, a stroke-stop plays it exactly like a click
## (InstrumentItem.feel). Recorded as the General MIDI closed hi-hat, 42, or its low voice, the
## open hi-hat, 46 -- a Tour spill's second copy (`voice`).

const MODEL := "res://assets/models/hihat.glb"
## tools/blender/spill_percussion.py's two stacked discs: its own origin is its vertical middle,
## the same convention as the cowbell, the pad, the triangle and the claves.
const HEIGHT := 0.026
const CYMBAL := Color(0.74, 0.62, 0.28)
const PITCHES := [42, 46]


func _init() -> void:
	id = &"hihat"
	super()
	_shape.position.y = HEIGHT * 0.5


func item_title() -> String:
	return ("OPEN " if voice > 0 else "") + "HI-HAT"


func hint() -> String:
	return _hint("click to pick up, then shake or strike it")


func pitch() -> int:
	return PITCHES[mini(voice, 1)]


func sound_kind(_struck: bool) -> StringName:
	return &"hihat"


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.position.y = HEIGHT * 0.5
	root.add_child(model)
	var cymbal := StandardMaterial3D.new()
	cymbal.albedo_color = CYMBAL
	cymbal.metallic = 0.9
	cymbal.roughness = 0.35
	var swap := {"cymbal": cymbal}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return root


func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.21, 0.03, 0.21)
	return s


func centre_height() -> float:
	return HEIGHT * 0.5


## Held flat, edge toward you, the same held-across gesture as the woodblock's and the claves'.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.FORWARD, 0.35) * Basis(Vector3.UP, 0.2), Vector3(0.02, -0.03, 0))


func flies() -> Dictionary:
	return {"bounce": 0.2, "roll": 3.0, "drag": 0.06}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.hihat(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -18.0, 0.0), pitch_scale())


func _foley_contact() -> AudioStream:
	return Foley.gear_bump()
